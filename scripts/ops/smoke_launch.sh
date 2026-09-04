#!/usr/bin/env bash
# One measured launch per harness, against a live scratch issue
# (#43, intent/43-harness-agnostic-launch/spec.md D18, D19).
#
#   scripts/ops/smoke_launch.sh <scratch-issue> [persona ...]
#
# work_test.sh proves the launcher's LOGIC against stubs. Nothing a stub
# says can prove that a harness actually loads the compiled target, that
# a minted App token actually authenticates a push, or that the
# `WORK-RESULT:` line actually survives a real harness's JSON. That is
# what this script is for: one real session per harness, three named
# observables each, so a failure says WHICH one broke rather than "the
# smoke failed".
#
# NO PERSONA NAME IS WRITTEN IN THIS FILE (#44, spec D7). Which harnesses
# run and which persona runs each are DERIVED from config, so flipping a
# pin changes what this gate covers with no edit here:
#
#   the harnesses  every distinct `personas.*.harness` value in
#                  config/deployments.yaml, in first-appearance order
#   the arm for a  the FIRST persona, in that file's own declaration
#   harness        order, pinned to that harness whose App in
#                  scripts/auth/app_manifests.yaml grants every
#                  permission this arm's observables need — `issues:
#                  write` to comment, `contents: write` to push — and
#                  which owns a stage that some rung of
#                  personas/lifecycle.json labels, since `work.sh --as`
#                  refuses a persona that does not own the current stage
#   its relabel    the label of such a rung, from the same join
#   housekeeping   the first persona in declaration order granting both
#                  permissions, any harness: writing the issue body,
#                  relabelling and reading comments makes no model call
#
# A harness with NO qualifying persona is exit 1 naming the harness and
# what is missing — never a skipped arm, and never exit 0 having covered
# some other harness twice (#44, spec D14). That is the whole of the
# tolerate mechanism: an observable an arm's persona cannot produce is
# rejected at selection, not excused at assertion time. The verdict's
# tolerated count stays and now prints 0.
#
# Identity is NEVER checked with `gh api user`: an App token has no user
# and gets 403 (findings Q7). The token-side check is
# `GET /installation/repositories`; the outcome-side check is who
# authored the comment and the pushed commit, compared against the
# persona's own `authority.identity`.
#
# Environment (argv stays closed to everything but the arms, as in
# work.sh):
#   DRY_RUN=1              resolve and print the arms, launch nothing,
#                          mint nothing, write nothing.
#   SMOKE_DEPLOYMENTS      read the pins from another file, so a scratch
#                          copy with one pin flipped proves the arms
#                          follow config and not this script.
#   SMOKE_APP_MANIFESTS    read the App permissions from another file,
#                          so a scratch copy proves the exit-1 branch.
#
# Trailing arguments name the arms explicitly: each persona binds to the
# harness ITS OWN pin names and replaces that harness's derived arm. A
# name that is not a persona, two names resolving to one harness, or a
# name whose App or rung does not qualify is exit 1 — the override picks
# a different arm, it does not switch the selection rule off.
#
# Exit 0 = every required observable held. Exit 1 = one did not, or the
# inputs were unusable.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GITHUB_REPO="${GITHUB_REPO:-evekhm/agentic-sdlc}"
PUSH_URL="https://github.com/$GITHUB_REPO.git"
DRY_RUN="${DRY_RUN:-0}"

DEPLOYMENTS="${SMOKE_DEPLOYMENTS:-$REPO_ROOT/config/deployments.yaml}"
APP_MANIFESTS="${SMOKE_APP_MANIFESTS:-$REPO_ROOT/scripts/auth/app_manifests.yaml}"
LIFECYCLE_JSON="$REPO_ROOT/personas/lifecycle.json"
PERSONA_DIR="$REPO_ROOT/personas"

ISSUE="${1:-}"
case "$ISSUE" in
    ''|*[!0-9]*)
        echo "usage: scripts/ops/smoke_launch.sh <scratch-issue> [persona ...]" >&2
        exit 1 ;;
esac
shift
OVERRIDES=("$@")

# `runs/` is ONE directory per machine — the primary checkout's — and
# not whatever worktree this run started from (AGENTS.md, "Outputs go in
# timestamped run folders"). It is gitignored, so a run folder written
# inside a worktree never travels with the branch and dies with the
# worktree; every session in every harness resolves the root this way
# before writing. The launched persona therefore puts its artifact
# there, and this observable has to read the same place: looking under
# $REPO_ROOT instead reports "left no artifact" for a file that exists,
# which is a false negative for every session working the way this
# repository tells sessions to work.
git_common_dir="$(git -C "$REPO_ROOT" rev-parse --git-common-dir 2>/dev/null || echo '')"
case "$git_common_dir" in
    '')  RUNS_ROOT="$REPO_ROOT/runs" ;;
    /*)  RUNS_ROOT="$(cd "$git_common_dir/.." && pwd)/runs" ;;
    *)   RUNS_ROOT="$(cd "$REPO_ROOT/$git_common_dir/.." && pwd)/runs" ;;
esac
SMOKE_DIR="$RUNS_ROOT/smoke-$ISSUE"

failures=0
blocked=0
ok()      { echo "  ok       $*"; }
bad()     { echo "  FAILED   $*"; failures=$((failures + 1)); }
note()    { echo "  note     $*"; }
banner()  { echo; echo "=== $*"; }
die()     { echo "smoke_launch: $*" >&2; exit 1; }

# --- reading the config the arms are derived from -------------------------------
# One parse of the pins, the same shape work.sh's harness_of uses, so
# this script does not introduce a second reading of the file.
pins() { # -> "<persona> <harness>", declaration order
    awk '
        $1 == "personas:" { inside = 1; next }
        /^[^[:space:]#]/  { inside = 0 }
        !inside { next }
        {
            n = $1; sub(/:$/, "", n)
            for (k = 2; k <= NF; k++)
                if ($k == "harness:") { v = $(k + 1); gsub(/[,}]/, "", v); print n, v }
        }
    ' "$DEPLOYMENTS"
}

harness_of() { # <persona> -> its pinned harness, or empty
    pins | awk -v want="$1" '$1 == want { print $2; exit }'
}

# The App permission block, read from the manifest source. `contents`
# and `pull_requests` vary per persona (reviewers are comment-only and
# never push), which is exactly what makes the selection a real test.
grant_of() { # <persona> <permission> -> the granted value, or empty
    awk -v want="$1" -v key="$2" '
        /^[a-z][a-z0-9_-]*:[[:space:]]*$/ {
            p = $1; sub(/:$/, "", p); inperm = 0; next
        }
        /^  default_permissions:[[:space:]]*$/ { inperm = 1; next }
        /^  [^ ]/ { inperm = 0 }
        inperm && p == want && $1 == key ":" { print $2; exit }
    ' "$APP_MANIFESTS"
}

# The label of a rung this persona owns. `work.sh --as` refuses a persona
# that does not own the stage the labels say is current (refusal (f)), so
# a relabel target that is not derived from the same join is a refusal
# waiting to happen. A persona all of whose stages are rungless — the
# stage-enum values lifecycle.json records as "absent by construction" —
# yields nothing here and can never be an arm.
relabel_of() { # <persona> -> the status:* label to put on the scratch issue, or empty
    local persona="$1" file stages stage label
    file="$PERSONA_DIR/$persona.yaml"
    [ -f "$file" ] || return 0
    stages="$(awk '$1 == "stage:" { gsub(/[][,]/, " "); $1 = ""; print }' "$file")"
    for stage in $stages; do
        label="$(jq -r --arg s "$stage" \
            '.stages[] | select(.stage == $s) | .label' "$LIFECYCLE_JSON")"
        [ -n "$label" ] && { printf '%s\n' "$label"; return 0; }
    done
    return 0
}

identity_of() { # <persona> -> the App login it acts as, or empty
    local file="$PERSONA_DIR/$1.yaml"
    [ -f "$file" ] || return 0
    sed -n 's/^[[:space:]]*identity:[[:space:]]*"\(.*\)".*/\1/p' "$file" | head -1
}

# Why this persona cannot be an arm, or empty if it can. Both halves are
# named rather than collapsed into "does not qualify", because the
# operator's fix differs: a permission is granted on github.com, a rung
# is given by #11 or #25.
disqualifies() { # <persona> -> the reason, or empty
    [ "$(grant_of "$1" issues)"   = write ] || { echo "its App lacks issues: write";   return 0; }
    [ "$(grant_of "$1" contents)" = write ] || { echo "its App lacks contents: write"; return 0; }
    [ -n "$(relabel_of "$1")" ]             || { echo "it owns no stage any rung labels"; return 0; }
    return 0
}

arm_for() { # <harness> -> the selected persona; exits 1 naming the harness if none
    local harness="$1" persona why reasons=""
    while read -r persona _; do
        [ "$(harness_of "$persona")" = "$harness" ] || continue
        why="$(disqualifies "$persona")"
        [ -z "$why" ] && { printf '%s\n' "$persona"; return 0; }
        reasons="$reasons
  $persona: $why"
    done < <(pins)
    [ -n "$reasons" ] || reasons="
  (no persona is pinned to it at all)"
    echo "smoke_launch: no persona pinned to $harness can produce this arm's observables.$reasons" >&2
    echo "smoke_launch: an arm needs issues: write to comment and contents: write to push, plus a stage some rung labels; $harness has no such persona, so the run fails rather than skipping it or covering another harness twice." >&2
    exit 1
}

# --- the derivation ---------------------------------------------------------------
command -v jq >/dev/null || die "jq is not on PATH; the arms cannot be derived without it"
[ -r "$DEPLOYMENTS" ]   || die "$DEPLOYMENTS is not readable"
[ -r "$APP_MANIFESTS" ] || die "$APP_MANIFESTS is not readable"

HARNESSES=()
while read -r harness; do HARNESSES+=("$harness"); done < <(pins | awk '!seen[$2]++ { print $2 }')
[ "${#HARNESSES[@]}" -gt 0 ] || die "$DEPLOYMENTS pins no persona to any harness"

# Trailing arguments override the derived arm for the harness their own
# pin names. Validated before anything is written: an unusable override
# discovered after the issue was relabelled is the failure the preflight
# below exists to prevent.
declare -A OVERRIDE_ARM=()
for persona in ${OVERRIDES+"${OVERRIDES[@]}"}; do
    harness="$(harness_of "$persona")"
    [ -n "$harness" ] || die "$persona is not a persona pinned in $DEPLOYMENTS"
    [ -z "${OVERRIDE_ARM[$harness]:-}" ] \
        || die "$persona and ${OVERRIDE_ARM[$harness]} both resolve to $harness; one arm per harness"
    why="$(disqualifies "$persona")"
    [ -z "$why" ] || die "$persona cannot be the $harness arm: $why"
    OVERRIDE_ARM[$harness]="$persona"
done

ARMS=()
for harness in "${HARNESSES[@]}"; do
    if [ -n "${OVERRIDE_ARM[$harness]:-}" ]; then
        ARMS+=("$harness ${OVERRIDE_ARM[$harness]}")
    else
        # `|| exit 1` and not `set -e`: arm_for's exit 1 ends the command
        # substitution's subshell, so without this the run would carry on
        # with an empty arm — the silent success D14 forbids.
        persona="$(arm_for "$harness")" || exit 1
        ARMS+=("$harness $persona")
    fi
done

HOUSEKEEPER=""
while read -r persona _; do
    [ "$(grant_of "$persona" issues)"   = write ] || continue
    [ "$(grant_of "$persona" contents)" = write ] || continue
    HOUSEKEEPER="$persona"; break
done < <(pins)
[ -n "$HOUSEKEEPER" ] \
    || die "no persona's App grants both issues: write and contents: write, so the run has no housekeeping identity"

banner "derived from $(basename "$DEPLOYMENTS") + $(basename "$APP_MANIFESTS")"
n=0
for arm in "${ARMS[@]}"; do
    n=$((n + 1))
    set -- $arm
    note "run $n · $1 · $2 · relabel $(relabel_of "$2") · as $(identity_of "$2")"
done
note "housekeeping identity: $HOUSEKEEPER ($(identity_of "$HOUSEKEEPER"))"

if [ "$DRY_RUN" = "1" ]; then
    echo
    echo "smoke_launch: DRY_RUN=1 — arms resolved above; nothing launched, minted or written."
    exit 0
fi

# --- identity, in-band ----------------------------------------------------------
# This script used to shell out to `ghp`, a wrapper that exists only in
# its author's ~/.local/bin and is named nowhere in this repository. The
# one artifact in #43 whose entire purpose is reproducibility was the one
# nobody else could run: it would have died on the first observable with
# `ghp: command not found`, having already relabelled the scratch issue.
# It now mints exactly the way work.sh does, from this checkout's own
# copy of mint_app_token.py, and calls plain `gh`.
#
# The token never reaches argv, a file or a log: it is a shell variable
# and an assignment prefix on the single `gh` call that needs it. Minted
# once per persona and reused, because a smoke run makes a dozen reads
# and an installation token is good for an hour.
MINT="$REPO_ROOT/scripts/auth/mint_app_token.py"
declare -A SMOKE_TOKENS=()
gh_as() { # <persona> <gh args...> — one gh call as that persona's App
    local persona="$1"; shift
    if [ -z "${SMOKE_TOKENS[$persona]:-}" ]; then
        SMOKE_TOKENS[$persona]="$("$MINT" "$persona")" || {
            echo "smoke_launch: cannot mint an App token for $persona" >&2
            return 1
        }
    fi
    GH_TOKEN="${SMOKE_TOKENS[$persona]}" GITHUB_TOKEN="${SMOKE_TOKENS[$persona]}" \
        gh "$@"
}

# --- preflight --------------------------------------------------------------------
# Name every missing prerequisite up front, all of them in one pass.
# Discovering one at the third observable — with the scratch issue
# already relabelled and a live persona launch already spent — is how a
# smoke test becomes worse than no smoke test.
prereq_missing=0
for cmd in gh jq claude agy; do
    command -v "$cmd" >/dev/null || {
        echo "smoke_launch: $cmd is not on PATH; smoking both harnesses needs both installed" >&2
        prereq_missing=1
    }
done
for prog in "$MINT" "$REPO_ROOT/scripts/ops/work.sh"; do
    [ -x "$prog" ] || {
        echo "smoke_launch: $prog is missing or not executable" >&2
        prereq_missing=1
    }
done
[ "$prereq_missing" -eq 0 ] || exit 1

# --- the instruction every arm will read ----------------------------------------
# Written into the issue body rather than into the prompt: work.sh has
# exactly one prompt literal for both harnesses (#43 D6), and a smoke
# test that needed a second one would be testing something work.sh does
# not do. ONE errand for every arm, keyed on the reader's own persona
# rather than branching per name: which personas read it is a fact of
# the pins, so a branch per name would be a hardcoded arm in the one
# place the arms are supposed to be derived (#44 D7). It is also why
# every arm now produces all three observables — which arm pushed and
# which arm only commented used to be a property of the order they ran
# in, and that is not a config fact.
body="$(cat <<BODY
**SMOKE TEST — not a unit of work.** Created by
\`scripts/ops/smoke_launch.sh\` for #43 (spec D19) and #44 (spec D7). Do
the errand below and nothing else: do not open a pull request, do not
modify a tracked file on this branch, do not touch any other issue.

Throughout, **YOU** is your own persona name — the agent you were
launched as — and **YOUR LOGIN** is the App login your persona
instructions give under *Acts as GitHub identity*. The errand is the
same for every persona; nothing in it is keyed to a particular one.

Write one line naming your persona, your harness and the UTC time. Call
it **THE LINE**, and deliver it three times:

1. Create \`smoke-$ISSUE/YOU.md\` under the shared run root containing
   THE LINE. The run root is the PRIMARY checkout's \`runs/\`, never this
   worktree's — AGENTS.md, *Outputs go in timestamped run folders*:
   \`RUNS_ROOT="\$(cd "\$(git rev-parse --git-common-dir)/.." && pwd)/runs"\`.
2. Post THE LINE as a comment on this issue, using
   \`gh issue comment $ISSUE --repo $GITHUB_REPO --body-file <a file>\`.
   Your \`GH_TOKEN\` is already your own App's; plain \`gh\` posts as you.
3. Push THE LINE as a commit on the branch \`smoke/$ISSUE-YOU\`, WITHOUT
   changing the branch this worktree is on — use a temporary worktree:
   \`\`\`
   git worktree add -b smoke/$ISSUE-YOU /tmp/smoke-$ISSUE-YOU HEAD
   # write /tmp/smoke-$ISSUE-YOU/SMOKE-$ISSUE.md containing THE LINE
   git -C /tmp/smoke-$ISSUE-YOU add SMOKE-$ISSUE.md
   git -C /tmp/smoke-$ISSUE-YOU \\
       -c user.name='YOUR LOGIN' \\
       -c user.email='YOUR LOGIN@users.noreply.github.com' \\
       commit -m 'smoke: YOU launched by work.sh (#$ISSUE)'
   git -C /tmp/smoke-$ISSUE-YOU push $PUSH_URL smoke/$ISSUE-YOU
   \`\`\`
   Your git is already configured with a credential helper that mints
   your App token, so the push needs no token from you.

Then print \`WORK-RESULT: ok #$ISSUE smoke launch completed\`.

Claiming this issue is not part of the errand. Neither is dispatching:
you are ALREADY the session \`scripts/ops/work.sh\` launched for this
issue, so running \`scripts/ops/work.sh\` (or any other launcher) here
launches a copy of yourself on the issue you are already working, and
that copy does the same. Do not run it.
BODY
)"

printf '%s\n' "$body" > "/tmp/smoke-$ISSUE-body.md"
gh_as "$HOUSEKEEPER" issue edit "$ISSUE" --repo "$GITHUB_REPO" \
    --body-file "/tmp/smoke-$ISSUE-body.md" >/dev/null \
    || { echo "smoke_launch: cannot write the scratch issue body" >&2; exit 1; }

# --- shared checks -------------------------------------------------------------

# The token-side identity check. `gh api user` is 403 for an App token
# and would prove nothing either way; this endpoint is what an
# installation token IS for.
check_token() { # <persona>
    local persona="$1" n
    if n="$(gh_as "$persona" api /installation/repositories --jq '.total_count' 2>/dev/null)"; then
        ok "$persona's App token authenticates ($n repository/ies in the installation)"
    else
        bad "$persona's App token could not read /installation/repositories"
    fi
}

# The clock the comment observable is measured against. A scratch issue
# is reused run after run, so "is there a comment by this persona" is
# always true after the first run and proves nothing; only "is there one
# created after this arm was launched" does.
#
# It is a TIMESTAMP and not a count on purpose. Counting was the obvious
# reading and it is wrong: `/issues/N/comments` paginates at 30 by
# default, so once a scratch issue passes thirty comments the count
# freezes at 30 and `.[-1]` names the thirtieth-oldest author. Both
# assertions then fail on arms that did comment — a green run reported
# red, naming the wrong persona. `since` plus an explicit `per_page` and
# `--paginate` reads the whole thread; `select(.created_at > ...)` is
# because `since` filters on `updated_at`, and an edited old comment is
# not a new one.
now_utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# `gh api` prints the error body on stdout, so this is a list of logins
# or nothing: a 404's JSON has no `.[].user.login` and yields empty.
comment_authors() { # <iso-8601> -> the login behind every comment created after it
    gh_as "$HOUSEKEEPER" api --paginate \
        "/repos/$GITHUB_REPO/issues/$ISSUE/comments?per_page=100&since=$1" \
        --jq ".[] | select(.created_at > \"$1\") | .user.login" 2>/dev/null || true
}

# A scratch issue is a fixture, not a unit of work, and the errand tells
# every arm that claiming is not part of it. An arm that claims anyway —
# or whose session dies between the claim and the handoff — leaves
# `in-progress` behind, and work.sh's mutex then refuses the NEXT arm on
# a claim this very run produced (refusal (e), exit 2). Clearing it per
# arm is what keeps one arm's accident from being reported as another
# harness's failure; it removes the label only, never a comment, so the
# thread still records what happened.
# It VERIFIES rather than fires and hopes: `|| true` on the edit would
# hide both a failed removal and GitHub serving the label list from
# before it, and either one surfaces two steps later as work.sh refusing
# the arm on a mutex the operator can see is gone — a failure report
# naming the wrong cause, which is the one thing this gate must not do.
clear_claim() {
    local attempt
    for attempt in 1 2 3 4 5 6 7 8 9 10; do
        gh_as "$HOUSEKEEPER" api \
            -X DELETE "/repos/$GITHUB_REPO/issues/$ISSUE/labels/in-progress" \
            >/dev/null 2>&1 || true
        gh_as "$HOUSEKEEPER" api "/repos/$GITHUB_REPO/issues/$ISSUE" \
            --jq '[.labels[].name] | index("in-progress") // "gone"' 2>/dev/null \
            | grep -qx gone && return 0
        sleep 2
    done
    note "in-progress is still on #$ISSUE after 10 attempts; work.sh's mutex will refuse this arm"
    return 0
}

relabel() { # <status-label>
    local want="$1" have
    for have in status:planning status:spec status:build status:implementing \
                status:in-review status:done; do
        [ "$have" = "$want" ] && continue
        gh_as "$HOUSEKEEPER" issue edit "$ISSUE" --repo "$GITHUB_REPO" \
            --remove-label "$have" >/dev/null 2>&1 || true
    done
    gh_as "$HOUSEKEEPER" issue edit "$ISSUE" --repo "$GITHUB_REPO" \
        --add-label "$want" >/dev/null \
        || { echo "smoke_launch: cannot put $want on #$ISSUE" >&2; exit 1; }
}

launch() { # <persona>; -> exit code of work.sh
    local persona="$1" rc=0
    echo "  --- launching $persona (capped by its own limits.timeout_mins)"
    HEADLESS=1 "$REPO_ROOT/scripts/ops/work.sh" --as "$persona" "$ISSUE" || rc=$?
    echo "  --- work.sh exited $rc"
    return "$rc"
}

# Observable 1. runs/ is gitignored, so a smoke run leaves the tree clean.
check_local_artifact() { # <persona>
    local persona="$1"
    if [ -s "$SMOKE_DIR/$persona.md" ]; then
        ok "$persona wrote $SMOKE_DIR/$persona.md: $(head -1 "$SMOKE_DIR/$persona.md")"
    else
        bad "$persona left no artifact at $SMOKE_DIR/$persona.md"
    fi
}

# Observable 2. Authorship, not content: the comment proves the minted
# token reached the session as its own identity.
check_comment() { # <persona> <iso-8601-before-the-launch>
    local persona="$1" since="$2" want authors
    want="$(identity_of "$persona")"
    authors="$(comment_authors "$since")"
    if printf '%s\n' "$authors" | grep -qxF "$want"; then
        ok "#$ISSUE carries a comment by $want posted after $since"
    else
        bad "no comment by $want on #$ISSUE after $since (authors since: $(printf '%s' "${authors:-none}" | tr '\n' ' '))"
    fi
}

# Observable 3. The push is the token-handoff proof: a harness's stock
# fallback agent has no instruction to push anything, so a scratch branch
# on origin means the persona loaded AND its minted token authenticated.
# Shape-checked, not just non-empty: `gh api` prints the error body on
# stdout for a 404, so `|| true` alone would hand a JSON blob to the
# assertion and call a missing branch a pass.
check_pushed_artifact() { # <persona> <ref>
    local persona="$1" ref="$2" pushed want author size
    pushed="$(gh_as "$HOUSEKEEPER" api "/repos/$GITHUB_REPO/git/ref/heads/$ref" \
                  --jq '.object.sha' 2>/dev/null || true)"
    case "$pushed" in
        [0-9a-f][0-9a-f]*) [ "${#pushed}" = "40" ] || pushed="" ;;
        *) pushed="" ;;
    esac
    if [ -z "$pushed" ]; then
        bad "$persona pushed no $ref — the persona did not load, or the token did not authenticate"
        return
    fi
    ok "$ref exists on origin ($pushed)"
    want="$(identity_of "$persona")"
    author="$(gh_as "$HOUSEKEEPER" api "/repos/$GITHUB_REPO/commits/$pushed" \
                  --jq '.commit.author.name' 2>/dev/null || echo '')"
    [ "$author" = "$want" ] \
        && ok "its head commit is authored by $want" \
        || bad "its head commit is authored by '${author:-unknown}'"
    size="$(gh_as "$HOUSEKEEPER" api \
                "/repos/$GITHUB_REPO/contents/SMOKE-$ISSUE.md?ref=$ref" \
                --jq '.size' 2>/dev/null || true)"
    case "$size" in
        ''|*[!0-9]*) bad "$persona pushed no SMOKE-$ISSUE.md on $ref" ;;
        0)           bad "$persona pushed an empty SMOKE-$ISSUE.md on $ref" ;;
        *)           ok "$persona's commit carries SMOKE-$ISSUE.md ($size bytes)" ;;
    esac
}

# --- the runs -------------------------------------------------------------------
rm -rf "$SMOKE_DIR"
n=0
for arm in "${ARMS[@]}"; do
    n=$((n + 1))
    set -- $arm
    harness="$1"; persona="$2"
    branch="smoke/$ISSUE-$persona"

    banner "run $n · $harness · $persona · #$ISSUE"
    check_token "$persona"
    clear_claim
    relabel "$(relabel_of "$persona")"
    # Cleared through the API, not through the launcher's own git: this
    # script must never push with whatever credentials the operator's
    # shell happens to carry — that is the identity confusion #43 exists
    # to end.
    gh_as "$HOUSEKEEPER" api -X DELETE "/repos/$GITHUB_REPO/git/refs/heads/$branch" \
        >/dev/null 2>&1 || true
    before="$(now_utc)"

    rc=0; launch "$persona" || rc=$?
    [ "$rc" = "0" ] && ok "work.sh exited 0 (the session reported WORK-RESULT: ok)" \
                    || bad "work.sh exited $rc, not 0"
    check_local_artifact  "$persona"
    check_comment         "$persona" "$before"
    check_pushed_artifact "$persona" "$branch"
done

# --- verdict -------------------------------------------------------------------
banner "verdict"
note "$blocked observable(s) tolerated and are not failures"
if [ "$failures" -gt 0 ]; then
    echo "smoke_launch: $failures observable(s) failed."
    exit 1
fi
echo "smoke_launch: every pinned harness launched; every required observable held."
