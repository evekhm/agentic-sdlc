#!/usr/bin/env bash
# Claim an issue and enter its worktree (#87; AGENTS.md "Working the
# tracker" steps 1-3, CLAUDE.md "Parallel sessions").
#
#   scripts/ops/claim.sh <issue> [<slug>]    verify, claim, create the worktree
#   scripts/ops/claim.sh --release <issue>   drop the claim (the pause case)
#   DRY_RUN=1 scripts/ops/claim.sh ...       every read runs, nothing is written
#
# The claim protocol is six steps of prose, and a session that
# re-derives it skips one. This is the one command: it runs every
# refusal BEFORE it writes anything, then writes both halves of the
# mutex (the `in-progress` label and the claim comment) and creates the
# worktree the claim comment names.
#
# Refusals, in this order — one reason line, exit 2, on the first:
#
#   closed        not a work item; the follow-up is a new issue
#   hold          the circuit breaker, and it is absolute
#   in-progress   somebody holds it; the last claim comment's author and
#                 first line are printed, so the caller knows whom to ask
#   depends on    an issue named on a "Depends on" line is still open
#   collision     the branch or the worktree path already exists. Checked
#                 before the claim on purpose: a `worktree add` that
#                 fails after the label was set leaves the mutex held by
#                 nobody.
#
# --release removes `in-progress` and posts NOTHING: the handoff comment
# (AGENTS.md "Working the tracker" step 5) says where the work stopped,
# which only the session that stopped can write.
#
# Environment:
#   CLAIM_ACTOR    branch/worktree prefix and the name in the claim
#                  comment. Default: `git config user.name`, first token,
#                  lowercased; else $USER.
#   CLAIM_SESSION  the harness session name, so a peer can message it.
#                  Default `unnamed`.
#   CLAIM_STAGE    the stage being worked. Default `implement`.
#   GITHUB_REPO    default evekhm/agentic-sdlc.
#   DRY_RUN=1      print `would: <command>` for every mutation instead of
#                  running it. All reads still run, so every refusal
#                  above is exercised against the live issue.
#
# Deterministic bash + gh + git + jq. No model call. Exit codes follow
# work.sh: 0 claimed (or previewed), 2 refused — an expected state of
# the tracker, not a bug — and 1 unusable input or an unreadable tracker.

set -euo pipefail

GITHUB_REPO="${GITHUB_REPO:-${GITHUB_REPOSITORY:-evekhm/agentic-sdlc}}"
DRY_RUN="${DRY_RUN:-0}"
LABEL="in-progress"

die() { echo "claim.sh: $*" >&2; exit 1; }    # unusable input
refuse() { echo "refused: $*" >&2; exit 2; }  # a stated tracker condition

# --- Arguments ----------------------------------------------------------------
RELEASE=0
NUMBER=""
SLUG=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--help) sed -n '2,45p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        --release) RELEASE=1; shift ;;
        -*) die "unknown argument '$1' (see --help)" ;;
        *)
            if [ -z "$NUMBER" ]; then NUMBER="${1#\#}"
            elif [ -z "$SLUG" ]; then SLUG="$1"
            else die "one issue is one claim; got '$NUMBER' and '$1'"
            fi
            shift ;;
    esac
done
[ -n "$NUMBER" ] || { sed -n '5,7p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 1; }
case "$NUMBER" in
    ''|*[!0-9]*) die "'$NUMBER' is not an issue number" ;;
esac
[ "$RELEASE" = 0 ] || [ -z "$SLUG" ] || die "--release takes only an issue number"

for cmd in gh git jq; do
    command -v "$cmd" >/dev/null || die "$cmd is not installed"
done

# The ONE read path to GitHub, single-argument so a test can put a stub
# `gh` first on PATH and the whole script becomes hermetic.
gh_json() { # <api-path>
    gh api "$1"
}

# The ONE mutation path: everything that writes GitHub or the filesystem
# goes through here, which is what makes DRY_RUN total rather than
# best-effort.
run() {
    if [ "$DRY_RUN" = 1 ]; then printf 'would: %s\n' "$*"; return 0; fi
    "$@" >/dev/null
}

# --- The issue ------------------------------------------------------------------
view=""
view="$(gh_json "repos/$GITHUB_REPO/issues/$NUMBER")" \
    || die "cannot read #$NUMBER from $GITHUB_REPO"
if jq -e 'has("pull_request")' <<<"$view" >/dev/null 2>&1; then
    die "#$NUMBER is a pull request; the issue is the unit of work"
fi

state="$(jq -r '.state' <<<"$view")"
title="$(jq -r '.title // ""' <<<"$view")"
body="$(jq -r '.body // ""' <<<"$view")"
labels="$(jq -r '.labels[].name' <<<"$view")"
has_label() { grep -Fxq "$1" <<<"$labels"; }

# --- --release: hand the mutex back ---------------------------------------------
if [ "$RELEASE" = 1 ]; then
    has_label "$LABEL" \
        || refuse "#$NUMBER does not carry $LABEL; there is no claim to release"
    run gh api --method DELETE "repos/$GITHUB_REPO/issues/$NUMBER/labels/$LABEL"
    echo "released #$NUMBER: $LABEL removed."
    echo "The handoff comment is yours to post (AGENTS.md \"Working the tracker\", step 5)."
    exit 0
fi

# --- Refusals, in order, before anything is written -----------------------------

# A closed issue is not a work item. Reopening it to work it would make
# the tracker lie about what shipped; the follow-up is its own issue.
[ "$state" = "open" ] \
    || refuse "#$NUMBER is closed — not a work item; file a follow-up per AGENTS.md \"Before filing an issue\" naming #$NUMBER"

# hold is the circuit breaker and it is checked before anything else
# about the issue's contents.
! has_label "hold" || refuse "#$NUMBER carries hold"

# The label alone is the mutex. Naming the holder is a courtesy on top:
# a claim comment is the structured line AGENTS.md prescribes (the body
# OPENS with `Claim`/`Claiming`, optionally bold), and its AUTHOR is the
# only trustworthy identity — a body is an unauthenticated string.
if has_label "$LABEL"; then
    holder="(no comment opens with a structured claim line)"
    if comments="$(gh_json "repos/$GITHUB_REPO/issues/$NUMBER/comments" 2>/dev/null)"; then
        line="$(jq -r '
            [.[] | select((.body // "") | test("\\A[[:space:]]*\\**[[:space:]]*Claim(ing)?\\b"; "i"))]
            | last
            | if . == null then ""
              else "\(.user.login // "?"): \((.body // "") | split("\n")[0])"
              end' <<<"$comments")"
        [ -z "$line" ] || holder="$line"
    else
        holder="(the thread cannot be read, so the holder cannot be established)"
    fi
    refuse "#$NUMBER carries $LABEL — held by $holder"
fi

# "Depends on #12, #34" / "Depends on: #12". Every issue named on such a
# line must be closed: the dependency is what makes the work orderable,
# and starting early is how two PRs end up editing the same section.
dep_lines="$(grep -Ei 'depends on' <<<"$body" || true)"
if [ -n "$dep_lines" ]; then
    while read -r dep; do
        [ -n "$dep" ] || continue
        [ "$dep" != "$NUMBER" ] || continue
        dep_view=""
        dep_view="$(gh_json "repos/$GITHUB_REPO/issues/$dep")" \
            || die "#$NUMBER depends on #$dep, which cannot be read from $GITHUB_REPO"
        dep_state="$(jq -r '.state' <<<"$dep_view")"
        [ "$dep_state" = "closed" ] \
            || refuse "#$NUMBER depends on #$dep, which is still $dep_state"
    done < <(grep -Eo '#[0-9]+' <<<"$dep_lines" | tr -d '#' | sort -un)
fi

# --- Names: actor, slug, branch, worktree ---------------------------------------
ACTOR="${CLAIM_ACTOR:-}"
if [ -z "$ACTOR" ]; then
    ACTOR="$(git config user.name 2>/dev/null | awk '{print tolower($1)}')"
    [ -n "$ACTOR" ] || ACTOR="${USER:-}"
fi
ACTOR="$(tr '[:upper:]' '[:lower:]' <<<"$ACTOR" | tr -cs 'a-z0-9' '-')"
ACTOR="${ACTOR#-}"; ACTOR="${ACTOR%-}"
[ -n "$ACTOR" ] \
    || die "cannot derive an actor name; set CLAIM_ACTOR or git config user.name"
SESSION="${CLAIM_SESSION:-unnamed}"
STAGE="${CLAIM_STAGE:-implement}"

# The slug is cosmetic — the issue number is the identity — so it is
# derived, never asked for, and cut on a word boundary at 40 characters.
derive_slug() { # <title> -> slug
    local s cut trimmed
    s="$(tr '[:upper:]' '[:lower:]' <<<"$1" | tr -cs 'a-z0-9' '-')"
    s="${s#-}"; s="${s%-}"
    if [ "${#s}" -gt 40 ]; then
        cut="${s:0:40}"
        trimmed="${cut%-*}"
        if [ -n "$trimmed" ] && [ "$trimmed" != "$cut" ]; then s="$trimmed"
        else s="${cut%-}"
        fi
    fi
    printf '%s\n' "$s"
}
if [ -z "$SLUG" ]; then
    SLUG="$(derive_slug "$title")"
    [ -n "$SLUG" ] || die "cannot derive a slug from the title of #$NUMBER; pass one"
else
    SLUG="$(derive_slug "$SLUG")"
    [ -n "$SLUG" ] || die "the slug argument has no usable characters"
fi

# Every git write targets the primary checkout: worktrees are registered
# there whichever worktree this script is invoked from.
# The awk reads the whole stream on purpose: exiting on the first match
# leaves git writing into a closed pipe, and that SIGPIPE would fail the
# assignment for a reason that has nothing to do with the repository.
PRIMARY="$(git worktree list --porcelain 2>/dev/null \
    | awk '/^worktree / && !p { print $2; p = 1 }')" || true
[ -n "$PRIMARY" ] || die "not inside a git repository"
ROOT="$(git -C "$PRIMARY" rev-parse --show-toplevel)"

BRANCH="$ACTOR/$NUMBER-$SLUG"
WT_REL=".claude/worktrees/$ACTOR-$NUMBER-$SLUG"
WT_ABS="$ROOT/$WT_REL"

# The fifth refusal. Both halves are checked here, before the label, so
# a failing `git worktree add` can never strand the claim.
! git -C "$ROOT" show-ref -q --verify "refs/heads/$BRANCH" \
    || refuse "branch $BRANCH already exists — resume that work or pick another slug"
[ ! -e "$WT_ABS" ] \
    || refuse "$WT_REL already exists — it is somebody's live work; never reuse a worktree you did not create"
! git -C "$ROOT" worktree list --porcelain | grep -Fxq "worktree $WT_ABS" \
    || refuse "$WT_REL is already registered as a worktree (its directory is missing: run 'git worktree prune')"

# A dirty primary is a peer's. Report it and carry on; the one thing
# this script must never do is touch it.
p_branch="$(git -C "$ROOT" branch --show-current 2>/dev/null || true)"
p_dirty="$(git -C "$ROOT" status --short 2>/dev/null | wc -l | tr -d ' ')"
if [ "$p_branch" != "main" ] || [ "$p_dirty" != 0 ]; then
    echo "warning: primary checkout $ROOT is on '${p_branch:-(detached)}' with $p_dirty uncommitted/untracked file(s) — left untouched (it is a peer's)" >&2
fi

# --- Claim, then enter -----------------------------------------------------------
COMMENT="Claim: $ACTOR ($SESSION), stage: $STAGE. Worktree: $WT_REL"

echo "==> #$NUMBER · $title"
echo "    claim:    $COMMENT"
echo "    branch:   $BRANCH"

PERSONA_DIR="$ROOT/personas"
if [ "$DRY_RUN" = 1 ]; then
    run gh api --method POST "repos/$GITHUB_REPO/issues/$NUMBER/labels" -f "labels[]=$LABEL"
    run gh api --method POST "repos/$GITHUB_REPO/issues/$NUMBER/comments" -f "body=$COMMENT"
else
    run gh api --method POST "repos/$GITHUB_REPO/issues/$NUMBER/labels" -f "labels[]=$LABEL"
    response="$(gh api --method POST "repos/$GITHUB_REPO/issues/$NUMBER/comments" -f "body=$COMMENT")" \
        || die "the claim comment on #$NUMBER was not posted"

    if [ -f "$PERSONA_DIR/$ACTOR.yaml" ]; then
        expected="$(sed -n '/^authority:/,/^[^[:space:]#]/p' "$PERSONA_DIR/$ACTOR.yaml" \
            | sed -n 's/^[[:space:]][[:space:]]*identity:[[:space:]]*//p' \
            | head -1 | tr -d '"' | sed 's/[[:space:]]*$//')"
        actual="$(jq -r '.user.login // ""' <<<"$response")"
        url="$(jq -r '.html_url // ""' <<<"$response")"

        if [ -n "$expected" ] && [ -n "$actual" ] && [ "$expected" != "$actual" ]; then
            echo "$url"
            die "the comment on #$NUMBER was posted by '$actual', but CLAIM_ACTOR says '$ACTOR', whose personas/$ACTOR.yaml names '$expected'; GH_TOKEN does not belong to that persona. Delete $url and remove the $LABEL label, then re-run with the right credential"
        fi
    fi
fi

run git -C "$ROOT" fetch -q origin
run git -C "$ROOT" worktree add -q -b "$BRANCH" "$WT_REL" origin/main

if [ "$DRY_RUN" = 1 ]; then
    echo "==> DRY_RUN=1 — nothing was written to GitHub and no worktree was created."
else
    echo "==> claimed #$NUMBER; work only in the worktree below."
fi
echo "$WT_ABS"
