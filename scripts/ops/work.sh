#!/usr/bin/env bash
# One-argument dispatch (#36, intent/36-dispatch/spec.md).
#
#   scripts/ops/work.sh <issue-or-pr-number> [--as <persona>]
#   DRY_RUN=1  scripts/ops/work.sh <issue-or-pr-number>
#   HEADLESS=1 scripts/ops/work.sh <issue-or-pr-number>
#
# A NUMBER IS THE WHOLE INSTRUCTION (D7). There is deliberately no flag
# naming a stage, a folder, an artifact or a branch: such a flag would
# let a session work a stage the labels say is not current, which is
# exactly the drift the labels-are-the-state-machine rule exists to
# stop. `--as <persona>` picks one of several owners of the same stage
# and is the only other input. Every MODE is an environment variable for
# the same reason argv is closed: `DRY_RUN`, and now `HEADLESS` (#43,
# D5) — a mode is how a run is executed, never what is worked.
#
# Deterministic bash + gh + jq up to the launch. No model call, no prompt,
# the issue's labels, the merged folder layout and three committed data
# files are the whole input, which is why the same number always
# resolves the same way. Failure mode first — the order is
#
#   resolve the number -> refusals -> owner set -> harness pin -> launch
#
# and every refusal happens BEFORE anything is dispatched.
#
# THIS SCRIPT NEVER WRITES TO GITHUB. It reads. The claim (`in-progress`
# plus the one-line claim comment, AGENTS.md "Working the tracker" step
# 2) belongs to the session this script launches, not to the launcher —
# a dispatcher that claimed on behalf of a session that then failed to
# start would leave the mutex held by nobody. `DRY_RUN=1` therefore
# differs in exactly one way: it prints the resolved launch command
# instead of executing it. Reads still run, so every guard below is
# exercised against the live issue.
#
# Where the facts come from, none of them restated here:
#   personas/lifecycle.json   label <-> stage, the artifact each stage
#                             owes, and the one-line brief (D1, D2)
#   personas/*.yaml           WHO owns a stage — derived, never stored:
#                             every kind: persona source whose `stage`
#                             list contains it (D2)
#   config/deployments.yaml   which harness a persona runs on (D10)
#
# THIS SCRIPT NEVER PRINTS A TOKEN. It mints the launched persona's App
# token in the one step between the last refusal and the launch (#43,
# D11) and hands it to the child by `export` inside the subshell that
# runs the harness — never in a file, an argument or the log. `export`
# rather than an `env VAR=… ` prefix because argv is world-readable;
# xtrace is suppressed for the whole window between the mint and the
# child's return, because `bash -x` would otherwise expand the value
# into stderr, which a session captures verbatim into a transcript
# (PR #60, AT-2 and AT-7). A run that launches nothing — a dry run, a
# two-owner stage, a harness with no row — exchanges nothing and leaves
# no live credential behind.
#
# Exit codes (D8, extended by #43 D14/D23):
#   0  launched and the session reported `WORK-RESULT: ok`, or printed
#      (a dry run, an unlaunchable harness, or a multi-owner stage that
#      deliberately launches nothing)
#   2  the number was NOT WORKED, BY DESIGN — either this script refused
#      (an unresolvable pull request #216, one of the eight refusal
#      conditions: re-entrancy #134, the six D5 conditions, or a number on
#      no rung #129) or the launched persona itself reported
#      `WORK-RESULT: refused|blocked`. One code, because a caller asks
#      whether the number was worked, not which layer declined (#43, D23).
#   1  unusable input: an unreadable number, a PR that closes more than one
#      issue, a stage no label names, a persona with no harness pin, an
#      unparsable source file, a missing compiled target, a token that
#      could not be minted — or a headless session whose outcome could
#      not be observed (a crash, a timeout, or a clean exit with no
#      WORK-RESULT line; returning 0 for an outcome nobody saw is a lie).

set -euo pipefail

GITHUB_REPO="${GITHUB_REPO:-${GITHUB_REPOSITORY:-evekhm/agentic-sdlc}}"
DRY_RUN="${DRY_RUN:-0}"
HEADLESS="${HEADLESS:-0}"
# Unattended-run controls (#108). All three are opt-in: unset, this script
# behaves exactly as it did before.
#   WORK_MAX_USD          spend ceiling (pre-emptive for Claude, post-hoc for Antigravity)
#   WORK_PERMISSION_MODE  claude-code's vocabulary, translated per harness
#                         (--permission-mode there, --dangerously-skip-
#                         permissions / --mode on agy); without it an
#                         unattended persona is denied Edit/git/gh
#   WORK_COST_FILE        path the observed cost (line 1) and the model the run
#                         actually billed to (line 2) are written to,
#                         so a caller can meter without scanning transcripts
#   WORK_MODEL            re-tier ONE dispatch without a compiler run
# Re-entrancy control (#134).
#   WORK_DISPATCHED_ISSUE colon-separated issue numbers the current session
#                         was launched for (the dispatch chain); refuses
#                         re-entrant dispatch of any issue in the chain.
WORK_MAX_USD="${WORK_MAX_USD:-}"
if [ -n "$WORK_MAX_USD" ]; then
    if ! grep -qE '^[0-9]+(\.[0-9]+)?$' <<<"$WORK_MAX_USD"; then
        echo "==> WORK_MAX_USD must be numeric, got '$WORK_MAX_USD'" >&2
        exit 1
    fi
fi
WORK_PERMISSION_MODE="${WORK_PERMISSION_MODE:-}"
WORK_COST_FILE="${WORK_COST_FILE:-}"
WORK_MODEL="${WORK_MODEL:-}"
WORK_DISPATCHED_ISSUE="${WORK_DISPATCHED_ISSUE:-}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GITHUB_LIB="$REPO_ROOT/scripts/ops/lib/github.sh"
LIFECYCLE_JSON="$REPO_ROOT/personas/lifecycle.json"
DEPLOYMENTS="${DEPLOYMENTS:-$REPO_ROOT/config/deployments.yaml}"
PERSONA_DIR="$REPO_ROOT/personas"

usage() {
    cat <<'USAGE'
usage: scripts/ops/work.sh <issue-or-pr-number> [--as <persona>]
       DRY_RUN=1  scripts/ops/work.sh <issue-or-pr-number>
       HEADLESS=1 scripts/ops/work.sh <issue-or-pr-number>

The number is the whole instruction. Nothing else about the work is an
argument: the stage comes from the issue's single status:* label, the
owner from the persona sources, the folder from the repository, and the
harness from config/deployments.yaml.

Modes are environment variables, never flags:
  DRY_RUN=1   resolve and print, launch nothing, mint nothing.
  HEADLESS=1  run the session non-interactively and map its
              WORK-RESULT line to an exit code. Antigravity personas
              are always headless; there is no interactive row.

Unattended-run controls, all opt-in (#108):
  WORK_MAX_USD=<amount>       spend ceiling (pre-emptive for Claude,
                              post-hoc detection after run for Antigravity).
  WORK_PERMISSION_MODE=<mode> claude-code's vocabulary, translated to
                              whatever the resolved harness calls it —
                              --permission-mode for claude-code;
                              bypassPermissions, acceptEdits and plan
                              for agy, and any other value refuses the
                              launch rather than dropping the mode.
                              Without it the default mode denies Edit,
                              git and gh, and the persona spends its
                              preamble to report that it could not act.
  WORK_COST_FILE=<path>       write this run's observed cost there, so a
                              caller can meter a dispatch without
                              scanning transcripts — which is wrong for
                              worktrees anyway, since each working
                              directory gets its own transcript tree.
                              Line 1 is the cost; line 2 names the model
                              the run actually billed to.
  WORK_MODEL=<model>          run this one dispatch on another model. It
                              must be this and not ANTHROPIC_MODEL: the
                              environment variable does NOT override the
                              model: line the compiler writes into the
                              persona's agent file, so a run set that way
                              bills to the compiled pin regardless.

Re-entrancy control (#134):
  WORK_DISPATCHED_ISSUE=<list> colon-separated issue numbers in the current
                              session's dispatch chain; prevents recursive
                              self-dispatch.
USAGE
}

die() { echo "work.sh: $*" >&2; exit 1; }             # unusable input
refuse() { echo "refused: $*" >&2; exit 2; }          # a stated D5 condition

# --- Arguments ----------------------------------------------------------------
NUMBER=""
AS=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --as)
            [ "$#" -ge 2 ] || die "--as needs a persona name"
            AS="$2"; shift 2 ;;
        --as=*) AS="${1#--as=}"; shift ;;
        -*) usage >&2; die "unknown flag '$1'; the number is the whole instruction" ;;
        *)
            [ -z "$NUMBER" ] \
                || die "one number is one run; got '$NUMBER' and '$1'"
            NUMBER="${1#\#}"; shift ;;
    esac
done
[ -n "$NUMBER" ] || { usage >&2; exit 1; }
case "$NUMBER" in
    ''|*[!0-9]*) die "'$NUMBER' is not an issue or pull-request number" ;;
esac
[ -z "$AS" ] || case "$AS" in
    *[!a-z-]*) die "--as '$AS' is not a persona name" ;;
esac

# --- Preflight ----------------------------------------------------------------
for cmd in gh jq git; do
    command -v "$cmd" >/dev/null || die "$cmd is not installed"
done
[ -r "$GITHUB_LIB" ] || die "cannot read $GITHUB_LIB"

gh api "repos/$GITHUB_REPO" >/dev/null 2>&1 \
    || die "environment cannot run: cannot read $GITHUB_REPO from GitHub"

base="${GITHUB_BASE_REF:-main}"
git -C "$REPO_ROOT" cat-file -e "origin/$base^{commit}" >/dev/null 2>&1 \
    || die "environment cannot run: no base object origin/$base (reviewer cannot compute a diff)"


# The pull-request resolver and has_label live here rather than in this
# file so that D14's "the same way work.sh resolves it" is ONE
# implementation: scripts/ops/post.sh gates its writes on the issues a
# pull request closes, and two resolvers is two answers (#25, T7).
# shellcheck source=lib/github.sh
. "$GITHUB_LIB"
[ -r "$LIFECYCLE_JSON" ] || die "cannot read $LIFECYCLE_JSON"
jq -e '.stages | type == "array" and length > 0' "$LIFECYCLE_JSON" >/dev/null 2>&1 \
    || die "$LIFECYCLE_JSON has no usable 'stages' array"
[ -r "$DEPLOYMENTS" ] || die "cannot read $DEPLOYMENTS"
[ -d "$PERSONA_DIR" ] || die "cannot read $PERSONA_DIR"

# gh_json — including #51's `--paginate` mode — now lives in
# scripts/ops/lib/github.sh with the resolver that calls it, sourced
# above (#25, T7). It is the same function; a list read that forgets
# `--paginate` reads the oldest thirty items here exactly as it did
# when the definition sat in this file.

# --- Resolve the number (D9) ---------------------------------------------------
# gh_json, resolve_issue and has_label come from scripts/ops/lib/github.sh,
# sourced in the preflight above (#25, T7). A pull request is not the unit
# of work; the issue is, and the resolver is shared with
# scripts/ops/post.sh so the dispatcher and the circuit breaker cannot
# disagree about which issue a pull request belongs to. It sets ISSUE,
# RESOLVED_VIA and ISSUE_JSON — and, when the number given was a pull
# request, IS_PR and PR_JSON — reporting through this file's own die(),
# or refusing (exit 2) when an input pull request resolves to no issue (#216).
resolve_issue "$NUMBER" || {
    rc=$?
    if [ "$rc" -eq 2 ]; then
        refuse "cannot resolve PR #$NUMBER to an issue"
    fi
    exit "$rc"
}
view="$ISSUE_JSON"

# The pull request's own labels, kept because `view` is now the ISSUE's.
# The pull request is not the unit of work, but it IS a place an operator
# puts a label, and a `hold` written there must stop the dispatch rather
# than be thrown away with the rest of that response (#50, Atlas AT-1).
# PR_JSON is that response, held by the resolver for exactly this.
PR_LABELS=""
if [ "$IS_PR" = "1" ]; then
    PR_LABELS="$(jq -r '.labels[].name' <<<"$PR_JSON")"
fi

state="$(jq -r '.state' <<<"$view")"
title="$(jq -r '.title // ""' <<<"$view")"
issue_labels="$(jq -r '.labels[].name' <<<"$view")"

# The refusals below read the UNION of the resolved issue's labels and,
# when a pull-request number was given, the pull request's own — a
# circuit breaker on either side stops the dispatch (#50, Atlas AT-1).
# For a plain issue number PR_LABELS is empty and this is the issue's
# set unchanged. The STAGE is deliberately not part of the union: it is
# derived from `issue_labels` below, because the state machine belongs
# to the unit of work and a status:* label on a pull request must not
# decide which rung the issue is on (D9).
labels="$(printf '%s\n%s\n' "$issue_labels" "$PR_LABELS" | grep -v '^$' | sort -u || true)"

# has_label is the library's, and is still a closure over the `labels`
# set above — the union — exactly as this file has always spelled it.
# Which side carries a label, so a refusal sends the operator to the
# number they have to clear rather than to the other one. BOTH sides are
# named when both carry it: reporting only the issue there hands the
# operator half the work, and they clear it, re-run, and are refused a
# second time by the other number (PR #95, Argus R1-2).
label_side() { # <label> -> "#<issue>" | "#<pr> (the pull request)" | "#<issue> (and #<pr>, the pull request)"
    local on_issue=0 on_pr=0
    if grep -Fxq "$1" <<<"$issue_labels"; then on_issue=1; fi
    if grep -Fxq "$1" <<<"$PR_LABELS"; then on_pr=1; fi
    if [ "$on_issue" = 1 ] && [ "$on_pr" = 1 ]; then
        printf '#%s (and #%s, the pull request)' "$ISSUE" "$NUMBER"
    elif [ "$on_issue" = 1 ]; then
        printf '#%s' "$ISSUE"
    else
        printf '#%s (the pull request)' "$NUMBER"
    fi
}


# --- Refusals, in D5's order, before anything else -----------------------------
# A refusal is a report, never a partial claim.

# (a) hold is absolute — not even a look further down the list.
if has_label "hold"; then
    refuse "$(label_side hold) carries hold"
fi

# (b) self-dispatch re-entrancy (#134): a session must not dispatch any
#     issue in its dispatch chain.
if [ -n "$WORK_DISPATCHED_ISSUE" ]; then
    case ":$WORK_DISPATCHED_ISSUE:" in
        *":$ISSUE:"*)
            refuse "session was launched for #$ISSUE; refusing re-entrant dispatch"
            ;;
    esac
fi

# (c) humans have taken over.
if [ "$state" != "open" ]; then
    refuse "#$ISSUE is closed"
fi
if has_label "status:review-stuck"; then
    refuse "$(label_side status:review-stuck) carries status:review-stuck"
fi

# (d) blocked is a report-and-stop, not a wait.
if has_label "blocked"; then
    refuse "$(label_side blocked) carries blocked"
fi

# (e) more than one status:* is a corrupted state machine. Report the
#     labels and stop: never guess which is true, and never apply `hold`
#     either — the stage advancer is the single writer of the circuit
#     breaker, and two writers is two circuit breakers (#4, D1).
status_labels="$(grep '^status:' <<<"$issue_labels" || true)"
status_count=0
[ -z "$status_labels" ] || status_count="$(grep -c . <<<"$status_labels")"
if [ "$status_count" -gt 1 ]; then
    refuse "#$ISSUE carries more than one status:* label: $(tr '\n' ' ' <<<"$status_labels")"
fi

# --- Owners: derived from the sources, never stored (D2) -----------------------
# Every kind: persona source whose `stage` list contains this stage.
owners_of() { # <stage> -> sorted persona names, one per line
    local want="$1" file name stages
    for file in "$PERSONA_DIR"/*.yaml; do
        [ -f "$file" ] || continue
        grep -qx 'kind: persona' "$file" || continue
        stages="$(sed -n 's/^stage:[[:space:]]*\[\(.*\)\].*/\1/p' "$file")"
        [ -n "$stages" ] || continue
        name="$(basename "$file" .yaml)"
        case ",$(tr -d '[:space:]' <<<"$stages")," in
            *",$want,"*) echo "$name" ;;
        esac
    done | sort
}

# --- Stage, from the label, through the one table (D2, D4) ---------------------
if [ "$status_count" -eq 1 ]; then
    stage="$(jq -r --arg l "$status_labels" \
        '.stages[] | select(.label == $l) | .stage' "$LIFECYCLE_JSON")"
    [ -n "$stage" ] \
        || die "#$ISSUE carries '$status_labels', which is not a rung in $LIFECYCLE_JSON"
elif grep -Fxq "intent:new" <<<"$issue_labels"; then
    # Filed but not yet on the ladder: the first rung is where work starts.
    stage="$(jq -r '.stages[0].stage' "$LIFECYCLE_JSON")"
else
    # (f) not on the ladder at all (#129): a defect-repair issue (`bug`,
    #     no rung — its fix PR is the final stage, AGENTS.md) or a bare
    #     filing. Nothing is wrong with it; it is simply not a number
    #     this script works, so it is a refusal like the five above, not
    #     an error: unattended, the difference is a named green line
    #     versus a red check on every fix PR in the repository (#129).
    refuse "cannot derive a stage for #$ISSUE: it carries no status:* label and no intent:new"
fi

# --- The review dispatch (#207, D1, D2) ----------------------------------------
# A reviewer dispatched at a pull request of THIS repository is
# reviewing that pull request, not claiming the issue's work. All
# three conjuncts, and nothing else is a review dispatch: the number
# resolved as a pull request; --as names a persona that declares the
# review stage; and the head repository is this one. The third is a
# fail-closed duplicate of a rule .github/workflows/unattended.yml
# already owns for the unattended path — work.sh is also invoked by
# hand, where no workflow guard stands in front of it, and if the two
# ever disagree the workflow is right and this is a bug (D1c).
#
# It is evaluated HERE, after (e) and (f): the issue's rung is still
# derived from its own status:* label alone, so a repair-path pull
# request whose issue carries only `bug` still refuses at (f) and
# stays #82's. The retarget then feeds the rung table below, so
# `label`, `brief`, `artifact` and `owners` all come from the review
# row of personas/lifecycle.json through the same jq as every other
# stage — no second derivation, no new label, no new stage value (D4).
review_dispatch() {
    [ "$IS_PR" = "1" ] || return 1
    [ -n "$AS" ] || return 1
    grep -Fxq "$AS" <<<"$(owners_of review)" || return 1
    [ -n "$PR_HEAD_REPO" ] && [ "$PR_HEAD_REPO" = "$GITHUB_REPO" ]
}

pr_head_ref="${BRANCH_REF:-}"
if [ "$IS_PR" = "1" ] && [ -z "$pr_head_ref" ]; then
    pr_head_ref="$(jq -r '.head.ref // empty' <<<"$(gh_json "repos/$GITHUB_REPO/pulls/$NUMBER" 2>/dev/null || true)")"
fi
pr_head_author=""
pr_head_slug=""
if [ "$IS_PR" = "1" ] && [ -n "$pr_head_ref" ]; then
    if [[ "$pr_head_ref" =~ ^([a-z][a-z-]*)/([0-9]+)-(.*)$ ]]; then
        pr_head_author="${BASH_REMATCH[1]}"
        pr_head_slug="${BASH_REMATCH[3]}"
    fi
fi

is_fix_round=0
if [ "$IS_PR" = "1" ] && [ "$status_labels" = "status:in-review" ] && [ -n "$AS" ] && [ -n "$pr_head_author" ] && [ "$AS" = "$pr_head_author" ] && [ -n "$PR_HEAD_REPO" ] && [ "$PR_HEAD_REPO" = "$GITHUB_REPO" ]; then
    is_fix_round=1
    author_stage="$(jq -r '.stages[] | select(.advances_to == "status:in-review") | .stage // empty' "$LIFECYCLE_JSON")"
    [ -n "$author_stage" ] || author_stage="$(sed -n 's/^stage:[[:space:]]*\[\(.*\)\].*/\1/p' "$PERSONA_DIR/$AS.yaml" 2>/dev/null | tr -d ' ')"
    stage="${author_stage:-implement}"
fi

RUNG_STAGE="$stage"
RUNG_LABEL="$status_labels"
REVIEW_DISPATCH=0
if review_dispatch; then
    REVIEW_DISPATCH=1
    stage="review"
fi

row="$(jq -ec --arg s "$stage" '.stages[] | select(.stage == $s)' "$LIFECYCLE_JSON")" \
    || die "no lifecycle row for stage '$stage'"
label="$(jq -r '.label' <<<"$row")"
brief="$(jq -r '.dispatch_brief' <<<"$row")"
artifact="$(jq -r '.artifact // "none — the output is code or a review"' <<<"$row")"

owners="$(owners_of "$stage")"
[ -n "$owners" ] \
    || die "no persona source declares stage '$stage'; nothing can be dispatched"

# The identity a persona posts as, so a claim comment's author names an
# actor rather than a login.
# Compared as a string, never as a pattern: an app login ends in
# "[bot]", which a regexp would read as a character class and quietly
# mis-match.
persona_for_login() { # <login> -> persona name, or empty
    local login="$1" file id
    for file in "$PERSONA_DIR"/*.yaml; do
        [ -f "$file" ] || continue
        id="$(sed -n 's/^[[:space:]]*identity:[[:space:]]*"\(.*\)".*/\1/p' "$file" | head -1)"
        if [ -n "$id" ] && [ "$id" = "$login" ]; then
            basename "$file" .yaml
            return 0
        fi
    done
    return 0
}

# (g) in-progress held by somebody else. The holder is the AUTHOR of the
#     last claim comment, mapped through the identity table in
#     personas/*.yaml — never a name read out of the comment body. A body
#     is an unauthenticated string, and reading an actor out of it lets
#     any commenter decide whether dispatch refuses or proceeds, in both
#     directions (#36, Argus R1-1).
#     What counts as a claim is the structured line AGENTS.md "Working
#     the tracker" step 2 prescribes: the comment OPENS with `Claim`
#     (or `Claiming`, optionally bold). Prose that merely contains the
#     word — "the PR claims it is byte-identical" — is not a claim and is
#     ignored. An author no persona identity names is a foreign claim:
#     fail closed and name the login, because an unknown actor is exactly
#     the case where this script must not assume it is looking at itself.
#     A claim by an owner of this stage is that actor resuming its own
#     work and proceeds; when `--as` names one owner the mutex binds
#     against that actor alone, since atlas holding the claim is a
#     different actor from argus even though both own review. `--as` is
#     itself validated against the stage's owners by (h) below, which
#     leaves D5's refusal ORDER as written.
#     The label alone is enough to stop: `in-progress` whose thread
#     carries no structured claim is a mutex that names nobody, and
#     dispatching on it would launch a second session on an issue some
#     actor is holding without a readable claim (#36, Argus R2-1). The
#     same goes for a thread this script cannot read — an unverifiable
#     mutex is a held mutex. Removing `in-progress` is how a session
#     hands the issue back (AGENTS.md, "Working the tracker", step 5).
#     `in-progress` is read from the UNION like every other refusal
#     above, so its four messages name the side that carries the label
#     through `label_side` rather than asserting it of the issue — a
#     mutex an operator set on the pull request was being reported
#     against a clean issue number they could not clear it from (PR #95,
#     Argus R1-1). The THREAD is always the issue's, on both sides: the
#     claim AGENTS.md prescribes is posted on the unit of work, so a
#     pull-request-side `in-progress` refuses with both numbers in view
#     — the one carrying the label and the one whose thread was read.
#     A REVIEW DISPATCH is passed through here without reading the
#     claim at all — no label read, no thread read, none of the four
#     messages above (#207, D3). The mutex protects one issue's working
#     tree; a review dispatch writes no branch, holds no worktree and
#     produces comments, so the collision this refusal prevents cannot
#     occur on that path. Everything else about (g) is unchanged, for
#     every other caller, at an issue or at a pull request: it keeps its
#     position in D5's order, it keeps its count, and it keeps its
#     meaning — passing through rather than re-deciding is what makes
#     that true. The claim itself is untouched and stays held by the
#     rung's author for the whole review window (D5).
claim_holder=""
if [ "$REVIEW_DISPATCH" != 1 ] && has_label "in-progress"; then
    resumers="$owners"
    [ -z "$AS" ] || resumers="$AS"
    held_on="$(label_side in-progress)"
    comments=""
    comments="$(gh_json "repos/$GITHUB_REPO/issues/$ISSUE/comments" --paginate)" \
        || refuse "in-progress on $held_on is set and #$ISSUE's thread cannot be read, so the holder cannot be established"
    claim_re='\A[[:space:]]*\**[[:space:]]*Claim(ing)?\b'
    claim_login="$(jq -r --arg re "$claim_re" \
        '[.[] | select((.body // "") | test($re; "i"))] | last | .user.login // ""' \
        <<<"$comments")"
    [ -n "$claim_login" ] \
        || refuse "in-progress on $held_on is set but no comment opens with a structured claim line (AGENTS.md, \"Working the tracker\", step 2) in #$ISSUE's thread: the mutex names no holder"
    claim_holder="$(persona_for_login "$claim_login")"
    [ -n "$claim_holder" ] \
        || refuse "in-progress on $held_on is held by $claim_login, a login no persona identity names"
    grep -Fxq "$claim_holder" <<<"$resumers" \
        || refuse "in-progress on $held_on is held by $claim_holder"
fi

# (h) --as must name an owner of the stage the labels say is current.
if [ -n "$AS" ] && ! grep -Fxq "$AS" <<<"$owners"; then
    refuse "$AS does not own stage $stage (owners: $(tr '\n' ' ' <<<"$owners"))"
fi
[ -z "$AS" ] || owners="$AS"

# --- Folder and branch (D6) ----------------------------------------------------
# Reuse beats derive, and derive beats named-in-a-comment: two sessions
# on the same cold issue must land on the same path without reading each
# other.
derive_slug() { # <title> -> slug
    local s="$1" cut trimmed
    s="${s%%:*}"
    s="${s%%;*}"
    s="$(tr '[:upper:]' '[:lower:]' <<<"$s" | tr -cs 'a-z0-9' '-')"
    s="${s#-}"; s="${s%-}"
    if [ "${#s}" -gt 24 ]; then
        cut="${s:0:24}"
        trimmed="${cut%-*}"
        if [ -n "$trimmed" ] && [ "$trimmed" != "$cut" ]; then
            s="$trimmed"
        else
            s="${cut%-}"
        fi
    fi
    printf '%s\n' "$s"
}

shopt -s nullglob
existing=( "$REPO_ROOT/intent/$ISSUE-"*/ )
shopt -u nullglob
case "${#existing[@]}" in
    0)
        slug="$(derive_slug "$title")"
        [ -n "$slug" ] || die "cannot derive a folder slug from the title of #$ISSUE"
        folder_origin="derived from the title"
        ;;
    1)
        slug="$(basename "${existing[0]}")"
        slug="${slug#"$ISSUE-"}"
        folder_origin="existing"
        ;;
    *)
        refuse "#$ISSUE has more than one intent folder: $(
            for d in "${existing[@]}"; do printf '%s ' "$(basename "$d")"; done)"
        ;;
esac
if [ "${is_fix_round:-0}" -eq 1 ] && [ -n "$pr_head_slug" ]; then
    slug="$pr_head_slug"
fi
folder="intent/$ISSUE-$slug/"

# --- Harness and the launch table (D10) ----------------------------------------
# The pin says WHICH harness; this script says how to start the ones it
# knows. An unlaunchable harness is a supported outcome — it prints and
# exits 0. An owner with no pin is not: that is a broken deployment.
harness_of() { # <persona> -> harness, or empty
    awk -v want="$1" '
        $1 == "personas:" { inside = 1; next }
        /^[^[:space:]#]/  { inside = 0 }
        !inside { next }
        $1 == want ":" {
            for (i = 2; i <= NF; i++) {
                if ($i == "harness:") { v = $(i + 1); gsub(/[,}]/, "", v); print v; exit }
            }
            block = 1; next
        }
        block && $1 == "harness:" { v = $2; gsub(/[,}]/, "", v); print v; exit }
        block && $1 ~ /:$/ { block = 0 }
    ' "$DEPLOYMENTS"
}

target_of() { # <persona> <harness> -> the compiled target a launch runs
    case "$2" in
        claude-code) printf '.claude/agents/%s.md' "$1" ;;
        antigravity) printf '.agents/agents/%s/agent.md' "$1" ;;
        *)           printf '' ;;
    esac
}

# The persona's own cap, read from the SOURCE. Limits live in
# personas/<p>.yaml and nowhere else: the compiler no longer copies them
# into a target, so there is one home for the fact (#43, D6, D9).
timeout_mins_of() { # <persona> -> limits.timeout_mins
    local persona="$1" file value
    file="$PERSONA_DIR/$persona.yaml"
    [ -f "$file" ] || die "personas/$persona.yaml does not exist"
    value="$(sed -n '/^limits:/,$p' "$file" \
        | sed -n 's/^[[:space:]][[:space:]]*timeout_mins:[[:space:]]*\([0-9][0-9]*\).*/\1/p' \
        | head -1)"
    [ -n "$value" ] \
        || die "personas/$persona.yaml declares no numeric limits.timeout_mins"
    printf '%s\n' "$value"
}

# The RESOLVED model, read from the compiled sidecar. Re-resolving the
# persona's tier against config/model_tiers.yaml in awk here would be a
# second implementation of the compiler's one job, and two of them drift
# silently (#43, D9).
model_of() { # <persona> -> the model agy is launched with
    local persona="$1" sidecar value
    sidecar=".agents/agents/$persona/agent.json"
    [ -f "$REPO_ROOT/$sidecar" ] \
        || die "$sidecar is missing; run scripts/sync_agents.py and commit the result"
    value="$(jq -r '.model // empty' "$REPO_ROOT/$sidecar")" \
        || die "$sidecar is not readable JSON"
    [ -n "$value" ] || die "$sidecar names no model for $persona"
    printf '%s\n' "$value"
}

# THE PROMPT (#43, D2, D21, D22). One literal, both harnesses, both
# modes. It names a number and nothing else — no stage, no folder, no
# artifact, no branch — so a launch cannot tell a session to work a rung
# the labels say is not current, which is the same rule that closes argv
# (D7). A bare `#<n>` is NOT sent: `#` is not a sigil to either harness,
# and a bare number handed to a persona that failed to load was measured
# burning 160k tokens before timing out. The WORK-RESULT sentence lives
# here rather than in personas/**: only a launcher reads it, and putting
# it in the sources would make every hand-opened interactive session emit
# a machine-readable result line for nobody (D21).
PROMPT="Work issue #$ISSUE in this repository. Follow your persona instructions and the repository's AGENTS.md; when you finish or refuse, print one final line WORK-RESULT: <ok|refused|blocked> #$ISSUE <one-line reason>."
# THE REVIEW PROMPT (#207, D8). A reviewer told to "work issue #M" while
# the artifact under review is pull request #N has to re-derive #N from
# the issue — the exact guess the resolver exists to prevent. This
# literal is used only when the review-dispatch predicate holds, and it
# mirrors PROMPT's WORK-RESULT sentence unchanged. The rule PROMPT
# protects is intact: a pull-request number is not a stage, a folder, an
# artifact or a branch, and a review dispatch's stage IS current (D2).
REVIEW_PROMPT="Review pull request #$NUMBER for issue #$ISSUE in this repository. Follow your persona instructions and the repository's AGENTS.md; when you finish or refuse, print one final line WORK-RESULT: <ok|refused|blocked> #$ISSUE <one-line reason>."
[ "$REVIEW_DISPATCH" != 1 ] || PROMPT="$REVIEW_PROMPT"

# The launch table (#43, D1, D5, D6). An ARRAY, not a string: a printed
# command and an executed one must not be two spellings of the same
# thing, so the report prints this array through printf '%q ' and the
# launch execs it.
#
#   harness       HEADLESS=0                     HEADLESS=1
#   claude-code   claude --agent P "$PROMPT"     claude -p … --output-format json
#   antigravity   (same as headless — D5)        agy -p … --add-dir … --print-timeout
#
# Every row is wrapped in `timeout $((T*60+60))` so a harness that
# ignores its own print timeout still ends; the spare minute is for the
# harness's own teardown.
#
# The INTERACTIVE row additionally gets `timeout --foreground` (PR #60,
# round-2 finding R2-1). GNU `timeout` calls `setpgid(0,0)` unless that
# flag is given, which puts the harness in a process group that is NOT
# the terminal's foreground group — and nothing calls `tcsetpgrp()` to
# make it one. A child in a background group cannot read the terminal
# (SIGTTIN) and cannot put it in raw mode (SIGTTOU, which is the first
# thing an interactive TUI does): it stops, and then sits stopped with a
# live token until the cap fires. While the row was `exec`'d this was a
# no-op — `timeout` *was* the process the shell had made the foreground
# leader — so dropping `exec` (AT-5) is what made the flag necessary.
# Its documented cost is that `timeout` then signals only COMMAND rather
# than the whole group, which for a session the operator is watching is
# the wanted behaviour anyway.
#
# The HEADLESS rows do not get it and must not: nothing there reads or
# reconfigures a terminal, stdout is captured by `$( )` rather than a
# tty, and group-wide signalling is what should kill a runaway
# non-interactive harness and its children at the cap.
LAUNCH_ARGV=()
#
# `antigravity` is ALWAYS headless, whatever HEADLESS says: only print
# mode was ever measured, an interactive agy session is untested, and it
# is not what a dispatcher needs — the presenter drives interactive
# antigravity work in the IDE, not through this script (D5).
headless_for() { # <harness> -> 1 | 0
    case "$1" in
        antigravity) printf '1\n' ;;
        *)           printf '%s\n' "$([ "$HEADLESS" = "1" ] && echo 1 || echo 0)" ;;
    esac
}

launch_argv() { # <persona> <harness> -> fills LAUNCH_ARGV; empty = no row
    local persona="$1" harness="$2" mins wrap model headless
    LAUNCH_ARGV=()
    # Set instead of exiting when this persona cannot be launched as
    # configured; the caller decides whether that is fatal (D20).
    ARGV_REFUSAL=""
    case "$harness" in
        claude-code|antigravity) ;;
        *) return 0 ;;
    esac
    mins="$(timeout_mins_of "$persona")" || exit 1
    wrap=$(( mins * 60 + 60 ))
    headless="$(headless_for "$harness")"
    # `--foreground` goes BEFORE the duration: `timeout` takes its
    # options first and everything after the duration is the command.
    LAUNCH_ARGV=( timeout )
    [ "$headless" = "1" ] || LAUNCH_ARGV+=( --foreground )
    LAUNCH_ARGV+=( "$wrap" )
    case "$harness" in
        claude-code)
            if [ "$headless" = "1" ]; then
                LAUNCH_ARGV+=( claude -p "$PROMPT" --agent "$persona"
                               --output-format json )
                # An unattended dispatch needs a spend ceiling the machine
                # holds, not one a config file merely declares (#108). Both
                # flags are print-mode only and both are opt-in: unset, the
                # argv is byte-for-byte what it was before.
                [ -z "$WORK_MAX_USD" ] \
                    || LAUNCH_ARGV+=( --max-budget-usd "$WORK_MAX_USD" )
                # Without this the default mode denies Edit, git and gh, and
                # the persona burns its ~35k-token preamble to report that it
                # could not act. The denials are counted in the envelope's
                # permission_denials field; see WORK_COST_FILE below.
                [ -z "$WORK_PERMISSION_MODE" ] \
                    || LAUNCH_ARGV+=( --permission-mode "$WORK_PERMISSION_MODE" )
                # Re-tier one dispatch without recompiling the persona. This
                # MUST be the flag: ANTHROPIC_MODEL does not override the
                # `model:` line the compiler writes into the agent file, and
                # measuring the difference is not optional -- a run launched
                # with the environment variable set to a cheaper model billed
                # in full to the compiled pin while the caller's ledger
                # recorded the model it had asked for.
                [ -z "$WORK_MODEL" ] \
                    || LAUNCH_ARGV+=( --model "$WORK_MODEL" )
            else
                LAUNCH_ARGV+=( claude --agent "$persona" "$PROMPT" )
            fi
            ;;
        antigravity)
            # --add-dir is MANDATORY and is $REPO_ROOT: print mode
            # ignores the working directory entirely, and without this
            # flag not one repository file is opened. $REPO_ROOT is the
            # checkout that owns this script (derived from BASH_SOURCE
            # above), never `git rev-parse` from the caller's cwd — the
            # labels, the folder layout and the deployment pins were all
            # read from that tree, and reading state from one checkout
            # while editing another is the split #36 exists to avoid
            # (D24). This file `cd`s exactly once, immediately before
            # the launch, and only ever to $REPO_ROOT — the same value
            # --add-dir receives (D1 as amended). A `cd` to anywhere
            # else is what remains forbidden.
            model="$(model_of "$persona")" || exit 1
            launch_model="$model"
            LAUNCH_ARGV+=( agy -p "$PROMPT" --agent "$persona"
                           --add-dir "$REPO_ROOT" --model "$model"
                           --output-format json --print-timeout "${mins}m" )
            # The antigravity half of WORK_PERMISSION_MODE. Headless agy
            # cannot prompt, so it AUTO-DENIES every tool that needs the
            # `command` permission and then exits 0 having produced
            # nothing — "no output produced — a tool required the
            # 'command' permission that headless mode cannot prompt
            # for". A reviewer that cannot run a command cannot read a
            # diff, so this is not a degraded review, it is no review.
            #
            # Measured on the first runner dispatch that reached a model
            # at all (#167): SUCCESS, 380 output tokens, empty response.
            #
            # The caller's vocabulary is claude-code's, because that is
            # what the workflow already sets, and each value that agy
            # has a flag for is translated to it (`agy --help`:
            # `--dangerously-skip-permissions`, `--mode
            # accept-edits|plan`). Only `bypassPermissions` has been
            # measured on this harness; the other two are mapped on the
            # help text alone. Anything else is refused rather than
            # silently ignored — a permission mode that does not reach
            # the harness is exactly the failure above. The scope, and
            # the objection to its width, are the same as the
            # claude-code branch's: see
            # .github/workflows/unattended.yml and #168.
            case "${WORK_PERMISSION_MODE:-}" in
                '') ;;
                bypassPermissions)
                    LAUNCH_ARGV+=( --dangerously-skip-permissions ) ;;
                acceptEdits)
                    LAUNCH_ARGV+=( --mode accept-edits ) ;;
                plan)
                    LAUNCH_ARGV+=( --mode plan ) ;;
                *)
                    # NOT `exit 1`. This function runs once per owner of
                    # the stage, for printing as well as for launching,
                    # and D20 puts an unusable row on exactly one side
                    # of that line: a broken atlas must not stop
                    # `--as argus`, and a plain `work.sh <n>` on a
                    # two-owner stage launches nothing and so cannot be
                    # stopped by a value nothing will use. Recorded as a
                    # marker here and made fatal below, for the one
                    # persona actually about to launch — the same split
                    # the missing-target preflight already draws
                    # (argus R2-1 / atlas A1-2 on PR #221).
                    LAUNCH_ARGV=()
                    ARGV_REFUSAL="WORK_PERMISSION_MODE=$WORK_PERMISSION_MODE has no agy flag; this harness maps bypassPermissions, acceptEdits and plan (#167)"
                    return 0 ;;
            esac
            ;;
    esac
}

# Neither harness signals a model-level refusal at the process boundary:
# a forced `REFUSED: …` exits 0 with a SUCCESS status on both. So the
# outcome is read IN BAND, from the decoded response text — never
# grepped out of the raw JSON, where the newline is escaped and
# `^WORK-RESULT:` would silently never match. The two harnesses disagree
# on key names (measured, #43 probe P4: agy answers `.status`/`.response`,
# Claude Code `.is_error`/`.result`), so this is one mapping with one
# jq expression each rather than two mappings.
response_text() { # <harness>; raw JSON on stdin
    case "$1" in
        antigravity) jq -r '.response // ""' ;;
        claude-code) jq -r '.result // ""' ;;
        *)           cat ;;
    esac
}
process_status() { # <harness>; raw JSON on stdin -> SUCCESS | ERROR
    case "$1" in
        antigravity) jq -r 'if (.status // "ERROR") == "SUCCESS"
                            then "SUCCESS" else "ERROR" end' ;;
        # `.is_error == false`, not `.is_error // true`: jq's `//` treats
        # `false` as absent, so the alternative form turns every SUCCESS
        # into an ERROR. Written the explicit way, a missing key is an
        # ERROR too, which is the conservative reading we want.
        claude-code) jq -r 'if (.is_error == false) then "SUCCESS" else "ERROR" end' ;;
        *)           printf 'ERROR\n' ;;
    esac
}

# --- Report --------------------------------------------------------------------
owner_list="$(tr '\n' ' ' <<<"$owners")"
owner_count="$(grep -c . <<<"$owners")"

echo "==> #$ISSUE · $title"
[ -z "$RESOLVED_VIA" ] || echo "    resolved from #$NUMBER via $RESOLVED_VIA"
# Which checkout a session will actually edit (D24). Printed because the
# operator standing in a worktree and invoking another tree's copy of
# this script is a real and silent mistake.
echo "    root:     $REPO_ROOT"
if [ "$REVIEW_DISPATCH" = 1 ]; then
    # A job log is the only place a reader can tell a review dispatch
    # from a rung dispatch, and the operating rule is to read the job
    # log behind every green check (#207, D10). The label line prints
    # the issue's OWN rung label, never the review row's: the issue does
    # not carry that one, and printing it next to a claim the issue does
    # carry would assert a state that does not exist.
    echo "    stage:    $stage (pull request #$NUMBER; #$ISSUE is on $RUNG_STAGE)"
    echo "    label:    ${RUNG_LABEL:--} (#$ISSUE's rung; a review dispatch carries no label of its own)"
else
    echo "    stage:    $stage"
    echo "    label:    $label"
fi
echo "    artifact: $artifact"
echo "    owner:    ${owner_list% }"
echo "    folder:   $folder ($folder_origin)"
# Printed once, unquoted, because the per-owner `command:` line below is
# shell-escaped and a human cannot read the prompt out of it.
echo "    prompt:   $PROMPT"
if has_label "in-progress"; then
    if [ "$REVIEW_DISPATCH" = 1 ]; then
        # (g) was passed through, so no holder was established and none
        # was looked for. Say that, rather than printing an empty name.
        echo "    claim:    in-progress on $(label_side in-progress), not read — a review dispatch is not measured against it (#207, D3)"
    else
        # Reaching here with `in-progress` means (g) established a holder.
        echo "    claim:    in-progress, held by $claim_holder"
    fi
fi

launch_persona=""
launch_harness=""
launch_target=""
launch_missing=0
launch_refusal=""
launch_model=""
LAUNCH=()
while read -r persona; do
    [ -n "$persona" ] || continue
    harness="$(harness_of "$persona")"
    [ -n "$harness" ] \
        || die "config/deployments.yaml has no harness pin for persona '$persona'"
    target="$(target_of "$persona" "$harness")"
    # PREFLIGHT (D3). agy's failure mode for a missing agent file is
    # SILENT — it runs its stock agent, prints nothing anywhere a script
    # can see, and exits 0 — so before the process starts is the only
    # cheap place to notice. For an owner that is merely being printed
    # this is a marker and nothing more: a broken atlas target must not
    # stop `--as argus` (D20). It becomes fatal below, for the one
    # persona actually about to be launched.
    missing=0
    if [ "$DEPLOYMENTS" = "$REPO_ROOT/config/deployments.yaml" ] && [ -n "$target" ] && [ ! -f "$REPO_ROOT/$target" ]; then
        missing=1
    fi
    LAUNCH_ARGV=()
    ARGV_REFUSAL=""
    [ "$missing" -eq 1 ] || launch_argv "$persona" "$harness"
    refusal="$ARGV_REFUSAL"
    echo "--> $persona"
    echo "    harness:  $harness"
    if [ -z "$target" ]; then
        echo "    target:   (no compiled target known for harness $harness)"
    elif [ "$missing" -eq 1 ]; then
        echo "    target:   $target (missing)"
    else
        echo "    target:   $target"
    fi
    echo "    branch:   $persona/$ISSUE-$slug"
    echo "    brief:    $brief"
    if [ -n "$refusal" ]; then
        echo "    command:  refused — $refusal"
    elif [ "${#LAUNCH_ARGV[@]}" -gt 0 ]; then
        # printf '%q ' so what is shown is exactly what runs.
        echo "    command:  $(printf '%q ' "${LAUNCH_ARGV[@]}")"
    else
        echo "    command:  none — this harness is started by hand; open the target"
        echo "              above and give it the prompt printed above."
    fi
    if [ -z "$launch_persona" ]; then
        launch_persona="$persona"
        launch_harness="$harness"
        launch_target="$target"
        launch_missing="$missing"
        launch_refusal="$refusal"
        LAUNCH=( ${LAUNCH_ARGV[@]+"${LAUNCH_ARGV[@]}"} )
    fi
done <<<"$owners"

# --- Launch (or deliberately not) ----------------------------------------------
if [ "$owner_count" -gt 1 ]; then
    # Auto-picking would silently halve a policy whose whole content is
    # that two independent reviewers both look (#2, D4). Name one with
    # --as if that is really what you meant. Nothing was minted and no
    # target was required to exist: a run that launches nothing
    # exchanges nothing (D20).
    echo "==> stage $stage has $owner_count owners; printing both and launching neither."
    echo "    Re-run with --as <persona> to launch exactly one."
    exit 0
fi
if [ -n "$launch_refusal" ]; then
    die "refused: $launch_refusal"
fi
if [ "$launch_missing" -eq 1 ]; then
    die "$launch_persona is pinned to $launch_harness but $launch_target does not exist in $REPO_ROOT; run scripts/sync_agents.py and commit the result. Launching without it would silently run the harness's stock agent and exit 0"
fi

# The identity the launched session will act as. The token itself is
# minted below and never printed; this line is the whole of what the
# operator gets to see about it (D11).
identity_of() { # <persona> -> the App login it posts as, or empty
    local file="$PERSONA_DIR/$1.yaml"
    [ -f "$file" ] || return 0
    sed -n 's/^[[:space:]]*identity:[[:space:]]*"\(.*\)".*/\1/p' "$file" | head -1
}

# The NAME of the variable holding the App's private key — never its
# value, which this script reads only by handing the name to the minter.
# Unquoted in the persona files (`token: ARGUS_APP_PRIVATE_KEY`), so the
# pattern is deliberately not identity_of's.
token_var_of() { # <persona> -> the env var name of its App private key, or empty
    local file="$PERSONA_DIR/$1.yaml"
    [ -f "$file" ] || return 0
    sed -n 's/^[[:space:]]*token:[[:space:]]*"\{0,1\}\([A-Za-z_][A-Za-z0-9_]*\)"\{0,1\}[[:space:]]*$/\1/p' \
        "$file" | head -1
}
echo "    identity: $(identity_of "$launch_persona") (token minted at launch; not printed)"

if [ "$DRY_RUN" = "1" ]; then
    echo "==> DRY_RUN=1 — nothing was launched, nothing was written, and no token was minted."
    exit 0
fi
if [ "${#LAUNCH[@]}" -eq 0 ]; then
    echo "==> $launch_persona's harness is not one this script starts — printed above."
    exit 0
fi

# The harness binary, checked BEFORE the mint below. Without this the
# run exchanges a one-hour credential for a process that cannot start:
# `timeout 5460 agy …` with agy off PATH exits 127, `timeout` itself off
# PATH kills the launch outright, and either way a live token has been
# minted for a session that never ran — exactly what D11's grounds for
# minting last forbid. (The status a caller sees is now 1 either way,
# since AT-5 removed the `exec` and every child status is mapped; the
# abandoned credential is the hazard, not the code.) The generic
# preflight near the top cannot do this check: which binary is needed is
# not known until the persona, its harness and its --as narrowing have
# all resolved.
#
# LAUNCH is ( timeout [--foreground] <seconds> <binary> … ), so index 0
# is the wrapper and the harness binary follows the duration — index 3
# on the interactive row that carries R2-1's `--foreground`, index 2
# otherwise. Both are checked: the generic preflight near the top makes
# exactly this assumption explicit for `gh` and `jq`, and an absent
# `timeout` would strand a credential the same way (N1).
_bin_idx=2
[ "${LAUNCH[1]}" != "--foreground" ] || _bin_idx=3
for _bin in "${LAUNCH[0]}" "${LAUNCH[$_bin_idx]}"; do
    command -v "$_bin" >/dev/null \
        || die "$_bin is not installed, so $launch_persona's $launch_harness session cannot start; nothing was minted"
done

# D16 as amended, clause (c). The interactive row IS the operator's
# terminal; with no tty on stdin or stdout the child cannot start, and
# minting first would abandon a live one-hour credential for a session
# that never ran — precisely what D11's mint-last ordering exists to
# prevent. Exit 1, not 2: like a missing harness binary this is an
# environment that cannot start the row rather than a decision about
# the number, so 2 keeps meaning "not worked, by design" (D23). The
# same guard holds for every other non-TTY caller — the `/work` door,
# cron, a CI step, a subagent's bash.
if [ "$(headless_for "$launch_harness")" != "1" ] \
   && { [ ! -t 0 ] || [ ! -t 1 ]; }; then
    die "$launch_persona's $launch_harness row is interactive and there is no terminal on stdin/stdout; re-run with HEADLESS=1, or from a terminal. Nothing was minted and nothing was launched"
fi

# The persona's own cap in minutes, for the 124 message below (D15 as
# amended). Read before the mint so a bad persona file cannot strand a
# live credential.
launch_mins="$(timeout_mins_of "$launch_persona")"

# --- Identity (#43, D11, D12, D13) ---------------------------------------------
# The last step before the launch, so that every run which prints and
# launches nothing performs no token exchange. A failed mint is FATAL:
# the alternative — warn and fall back to whatever credential the
# operator happens to be carrying — produces exactly the bug this exists
# to fix, a session that posts as the operator while everyone believes a
# persona ran. A launch that cannot be attributed is not a launch.
#
# XTRACE IS SUPPRESSED from here to the launch, and the caller's setting
# restored the moment the child returns (D11 as amended, PR #60, AT-2).
# Bash's xtrace expands both `tok="$(mint …)"` and every `GH_TOKEN="$tok"`
# assignment, so `bash -x scripts/ops/work.sh <n>` would write the live
# installation token to stderr — and a Claude Code session captures tool
# stderr verbatim into an on-disk transcript, a file and a log, the two
# places D11 says the token never reaches. The suppression is a no-op
# when xtrace is off, and `set -x` stays in force everywhere else.
_xtrace_was_on=0
case "$-" in *x*) _xtrace_was_on=1; set +x ;; esac

tok=""
tok="$("$REPO_ROOT/scripts/auth/mint_app_token.py" "$launch_persona")" \
    || die "cannot mint an App token for $launch_persona; refusing to launch as somebody else"
[ -n "$tok" ] \
    || die "the App token minted for $launch_persona is empty; refusing to launch as somebody else"

# git does not read GH_TOKEN, and an installation token lives about an
# hour while odyssey's cap is ninety minutes — so `gh` gets the snapshot
# and `git` gets a helper that re-mints on every call. Both are
# installed through the CHILD's environment only: nothing is written to
# .git/config, so a crashed session leaves no credential configuration
# behind.
#
# The two EMPTY helper values are load-bearing. git collects every
# matching `credential.helper` and `credential.<url>.helper` into ONE
# ordered list and tries them in turn; an empty value clears whatever
# has accumulated so far, and a later entry appends to it. Without a
# reset an operator's global helper (a `gh auth git-credential` entry
# is the common one) is in that list ahead of ours and answers the
# push, so the session pushes as the operator — the exact bug D12
# exists to stop.
#
# Both keys are reset rather than one, and the honest reason is belt
# and braces rather than measurement: GIT_CONFIG_* entries carry
# command-line precedence, so ours would very likely win with a single
# reset. Two resets are idempotent and make ours the only helper in the
# list however the operator configured theirs, on either key. The
# failure this guards against is silent, which is what makes the extra
# pair of variables worth it.
#
# The insteadOf rewrite is load-bearing for a different reason: this
# repository's origin is SSH, and an SSH remote never consults a
# credential helper at all.
CRED_HELPER="$REPO_ROOT/scripts/auth/git-credential-persona"

# ONE install, used by both rows — the four pairs were written twice and
# had to stay byte-identical to be correct. Two properties beyond the
# comment above:
#
#   * the pairs are APPENDED at the caller's own GIT_CONFIG_COUNT rather
#     than written at index 0. An outer launch, or a runner that installs
#     `http.proxy` or `safe.directory` that way, would otherwise have its
#     entries silently replaced and see a push fail for an unrelated
#     reason (PR #60, AT-7). With no inherited set the offset is 0 and
#     the child sees exactly what it saw before.
#   * `export` inside a subshell, never an `env` prefix: `env
#     GH_TOKEN=… ` would put the token in a process's argv, which is
#     world-readable, and D11 forbids exactly that. The assignment
#     prefix this replaces had the same property; a builtin `export`
#     keeps it.
launch_child() { # runs "${LAUNCH[@]}" with the persona's credentials in its env
    local base="${GIT_CONFIG_COUNT:-0}"
    case "$base" in ''|*[!0-9]*) base=0 ;; esac
    (
        # The child gets the one-hour installation token and NEVER the
        # App's private key. By the time this runs the mint has already
        # happened, so the PEM has no remaining use inside the session —
        # while its blast radius is every installation of the App and
        # its rotation is a human clicking in the GitHub UI, against the
        # token's one hour and single repository. Argus found it holding
        # the live key in its own environment on a runner (#164 R1-1),
        # which is only reachable at all because the harness permission
        # gate is bypassed there (#163); this is the half of that grant
        # a launcher can take back unilaterally, and it costs nothing.
        local key_var
        key_var="$(token_var_of "$launch_persona")"
        [ -z "$key_var" ] || unset "$key_var"
        export GH_TOKEN="$tok" GITHUB_TOKEN="$tok"
        export "GIT_CONFIG_KEY_$base=credential.helper"
        export "GIT_CONFIG_VALUE_$base="
        export "GIT_CONFIG_KEY_$((base + 1))=credential.https://github.com.helper"
        export "GIT_CONFIG_VALUE_$((base + 1))="
        export "GIT_CONFIG_KEY_$((base + 2))=credential.https://github.com.helper"
        export "GIT_CONFIG_VALUE_$((base + 2))=$CRED_HELPER $launch_persona"
        export "GIT_CONFIG_KEY_$((base + 3))=url.https://github.com/.insteadOf"
        export "GIT_CONFIG_VALUE_$((base + 3))=git@github.com:"
        export GIT_CONFIG_COUNT=$((base + 4))
        export WORK_DISPATCHED_ISSUE="${WORK_DISPATCHED_ISSUE:+$WORK_DISPATCHED_ISSUE:}$ISSUE"
        # agy needs a DIFFERENT cloud credential than claude-code, and
        # this is the only place that knows which harness is about to
        # launch — the workflow is harness-blind by design (D18), so it
        # cannot make this choice for us (#167).
        #
        # Why a second credential at all. agy ships no built-in model
        # list: it fetches its catalog at startup from
        # cloudcode-pa.googleapis.com, which serves that catalog per
        # IDENTITY ENTITLEMENT, not per project. A federated service
        # account has no Antigravity entitlement, so under WIF the fetch
        # returns nothing ("timed out waiting for available models") and
        # agy then rejects EVERY --model value with "not recognized as a
        # known model" — which is why re-pinning the model never fixed
        # this and no IAM role can. Measured on a runner: WIF service
        # account 0 models; an authorized_user ADC credential, same
        # runner shape, 15 models and a successful Pro call.
        #
        # claude-code is untouched: it talks to Vertex, where the WIF
        # service account works and stays least-privilege.
        #
        # The VALUE never reaches this environment at all — the caller
        # passes a path — and for a claude-code dispatch the file that
        # path named was deleted before this function was called
        # (argus/atlas R1-1, atlas A1-1 on PR #221). Unsetting the path
        # is tidiness, not the control: a path is not a secret, and
        # `unset` cannot take back an environment a parent already has
        # in /proc, which is precisely why the value is not in one.
        unset ANTIGRAVITY_ADC_FILE
        [ -z "${AGY_CREDENTIAL_FILE:-}" ] \
            || export GOOGLE_APPLICATION_CREDENTIALS="$AGY_CREDENTIAL_FILE"
        unset AGY_CREDENTIAL_FILE
        exec "${LAUNCH[@]}"
    )
}

# The child starts in the checkout work.sh itself came from. agy is
# pinned with `--add-dir`; claude-code has no such flag and takes the
# working directory as the project, so a launcher invoked by absolute
# path from somewhere else would hand the session a DIFFERENT checkout
# than the one whose personas, labels and targets it just resolved.
# Measured: the first smoke run wrote its artifact into a sibling clone.
cd "$REPO_ROOT"

# agy's credential, kept or destroyed HERE (#167).
#
# Why the credential at all: agy ships no built-in model list. It
# fetches its catalog from cloudcode-pa.googleapis.com, which serves
# that catalog per IDENTITY ENTITLEMENT — not per project and not per
# IAM role. A federated service account holds none, gets an empty
# catalog, and agy then rejects EVERY --model value with "not
# recognized as a known model". Measured on a runner: WIF service
# account 0 models; the same runner shape with an authorized_user ADC
# credential, 15 models and a successful Pro call. No re-pin and no
# role grant reaches this.
#
# The caller passes a PATH, never the value. An earlier round of this
# change took the value in $ANTIGRAVITY_ADC_JSON and wrote the file
# here, on the theory that `unset` before the launch withheld it from
# the harnesses that must not see it. It does not: the kernel keeps
# every process's INITIAL environment in /proc/<pid>/environ, so a
# value exported into the step that hosts the harness stays readable —
# to any child, under the same runner user, for the whole run — no
# matter what this script unsets. `cat /proc/$PPID/environ` is the
# whole attack (atlas A1-1 on PR #221).
#
# A path can be taken back, by deleting what it points at. So the
# workflow stages the file for every runner because it is harness-blind
# by design (D18), and this is the first point in the chain that knows
# which harness is about to launch — and therefore the last point at
# which the file can be destroyed before any session exists to read it.
# A claude-code dispatch reaches its launch with the path pointing at
# nothing.
AGY_CREDENTIAL_FILE=""
cleanup_agy_credential() {
    [ -z "$AGY_CREDENTIAL_FILE" ] || rm -f "$AGY_CREDENTIAL_FILE"
}
if [ -n "${ANTIGRAVITY_ADC_FILE:-}" ] && [ -f "$ANTIGRAVITY_ADC_FILE" ]; then
    if [ "$launch_harness" = "antigravity" ]; then
        AGY_CREDENTIAL_FILE="$ANTIGRAVITY_ADC_FILE"
        # Deleted on the way out however this ends, including the
        # signals a cancelled Actions job sends.
        trap cleanup_agy_credential EXIT INT TERM
    else
        rm -f "$ANTIGRAVITY_ADC_FILE"
    fi
elif [ "$launch_harness" = "antigravity" ]; then
    echo "==> WARNING: no ANTIGRAVITY_ADC_FILE, so $launch_persona has no" >&2
    echo "    entitled credential and agy will report every model as unrecognized." >&2
    echo "    Provision it with scripts/setup/wif_setup.sh --check (#167)." >&2
fi
export AGY_CREDENTIAL_FILE

if [ "$(headless_for "$launch_harness")" != "1" ]; then
    # D15 and D23, both as amended (PR #60, AT-5): the interactive row
    # is NOT `exec`'d. The child runs in the FOREGROUND and inherits
    # stdin, stdout, stderr and the terminal — which is all "the
    # operator's terminal IS the session" ever required; `timeout` was
    # already an un-`exec`'d process between the two, so this costs one
    # process and changes nothing the operator can see. work.sh then
    # waits, maps and exits, so EVERY exit of this script is 0, 1 or 2.
    #
    # The map is two-valued: child 0 → 0; anything non-zero → 1, with
    # the raw status named, and for 124 the cap named too. A timeout is
    # not a new outcome kind — WORK-RESULT is a line the persona prints
    # (D2, D21) and a timed-out session prints nothing — so 124 is the
    # launcher's own observation, the same fact D14 maps to 1 when it
    # arrives headless as status ERROR. A child's status of 2 is never
    # forwarded: exit 2 is PRODUCED by the launcher's own refusals and
    # by D14's parsed refused/blocked, and by nothing else, or the
    # vocabulary #25's adapter branches on could be minted by an
    # unrelated harness's numbering (D23 as amended).
    echo "==> launching: $(printf '%q ' "${LAUNCH[@]}")"
    set +e
    launch_child
    rc=$?
    set -e
    tok=""
    [ "$_xtrace_was_on" = "0" ] || set -x
    if [ "$rc" -eq 0 ]; then
        # Interactive 0 means the session RAN TO COMPLETION, not that
        # the work was done: an in-session refusal is visible to the
        # operator and to the tracker, not to this script.
        exit 0
    elif [ "$rc" -eq 124 ]; then
        echo "==> $launch_persona's session hit the $launch_mins-minute cap (exit 124)." >&2
    else
        echo "==> $launch_persona's session did not complete (exit $rc)." >&2
    fi
    exit 1
fi

echo "==> launching headless: $(printf '%q ' "${LAUNCH[@]}")"
set +e
raw="$(launch_child)"
rc=$?
set -e
tok=""
[ "$_xtrace_was_on" = "0" ] || set -x

# Echoed first, always: nothing a session said is swallowed by the
# mapping that follows.
printf '%s\n' "$raw"

# What the run cost, recorded BEFORE any exit path below: a dispatch that
# refused or timed out still spent money, and a guard that only sees the
# successes cannot hold a budget (#108). The envelope is the right source
# because it travels with the run — a transcript lands in a per-working-
# directory tree, so a dispatch inside a worktree writes its usage
# somewhere a caller scanning the main tree will never look, and the
# ceiling silently never trips.
if [ -n "$WORK_COST_FILE" ] || { [ "$launch_harness" = "antigravity" ] && [ -n "$WORK_MAX_USD" ]; }; then
    cost="$(printf '%s' "$raw" | jq -r '.total_cost_usd // empty' 2>/dev/null)" || cost=""
    case "$cost" in ''|*[!0-9.]*) cost="" ;; esac
    if [ -n "$cost" ]; then
        # Line 1 is the cost. Line 2 is the model or models the run ACTUALLY
        # billed to, read from the envelope rather than echoed back from what
        # the caller asked for -- a ledger that records the request cannot
        # show a re-tiering that silently did not happen, which is exactly how
        # a run meant for a cheap model was billed to an expensive one while
        # the ledger said otherwise. A caller wanting only the cost reads the
        # first line.
        models="$(printf '%s' "$raw" \
            | jq -r '(.modelUsage // {}) | keys | join(",")' 2>/dev/null)" || models=""
    elif [ "$launch_harness" = "antigravity" ]; then
        models="${launch_model:-$(model_of "$launch_persona" 2>/dev/null)}" || models=""
        models="${models:-$(printf '%s' "$raw" | jq -r '.model // empty' 2>/dev/null)}"
        inp="$(printf '%s' "$raw" | jq -r '.usage.input_tokens // empty' 2>/dev/null)" || inp=""
        out="$(printf '%s' "$raw" | jq -r '((.usage.output_tokens // 0) + (.usage.thinking_tokens // 0))' 2>/dev/null)" || out=""
        cr="$(printf '%s' "$raw" | jq -r '.usage.cache_read_tokens // 0' 2>/dev/null)" || cr="0"
        if [ -n "$inp" ] && [ -n "$models" ]; then
            cost="$(awk -v m="$models" -v inp="$inp" -v cr="$cr" -v out="$out" '
            function model_family(m) {
              if (m ~ /gemini/) return "gemini"
              return ""
            }
            function model_version(m,   idx, s) {
              idx = match(m, /gemini-[0-9]+\.[0-9]+/)
              if (idx) {
                s = substr(m, idx + 7, RLENGTH - 7)
                return s
              }
              return ""
            }
            function rate_tier(m,   f, v) {
              f = model_family(m)
              if (f != "gemini") return ""
              v = model_version(m)
              if (m ~ /flash/) {
                if (v == "1.5" || v == "2.0" || v == "2.5" ||
                    v == "3.5" || v == "3.6" || v == "3.7" || v == "3.8")
                  return "0.15 0.1875 0.30 0.0375 0.60"
                return ""
              }
              if (m ~ /pro/) {
                if (v == "1.5" || v == "2.5" || v == "3.1")
                  return "1.25 1.5625 2.50 0.3125 5.00"
                return ""
              }
              return ""
            }
            BEGIN {
              r = rate_tier(m)
              if (r == "") exit 1
              split(r, p, " ")
              printf "%.6f\n", (inp*p[1] + cr*p[4] + out*p[5]) / 1e6
            }')" || cost=""
        fi
    fi

    if [ -n "$WORK_COST_FILE" ]; then
        if [ -n "$cost" ]; then
            printf '%s\n%s\n' "$cost" "$models" > "$WORK_COST_FILE"
        elif [ "$launch_harness" = "antigravity" ]; then
            : > "$WORK_COST_FILE"
            echo "==> no total_cost_usd or unpriced .usage in $launch_harness's envelope; wrote no cost to $WORK_COST_FILE" >&2
        else
            # Truncate rather than guess. A caller that reads an empty cost
            # must refuse; one that reads a fabricated 0 would keep spending.
            : > "$WORK_COST_FILE"
            echo "==> no total_cost_usd in $launch_harness's envelope; wrote no cost to $WORK_COST_FILE" >&2
        fi
    fi

    if [ "$launch_harness" = "antigravity" ] && [ -n "$WORK_MAX_USD" ]; then
        if [ -z "$cost" ]; then
            echo "==> $launch_persona has WORK_MAX_USD set to \$${WORK_MAX_USD}, but the session envelope missing .usage data to measure cost against. Refusing to fail open." >&2
            exit 1
        elif awk -v c="$cost" -v m="$WORK_MAX_USD" 'BEGIN { if (c > m) exit 0; else exit 1 }'; then
            echo "==> $launch_persona exceeded the \$${WORK_MAX_USD} spend ceiling: session cost \$${cost}. The Antigravity harness cannot enforce ceilings pre-emptively; overrun was detected post-hoc." >&2
            exit 1
        fi
    fi

    denials="$(printf '%s' "$raw" | jq -r '(.permission_denials // []) | length' 2>/dev/null)" || denials=0
    [ "${denials:-0}" = "0" ] \
        || echo "==> $launch_persona hit $denials permission denial(s); set WORK_PERMISSION_MODE if it needs to act." >&2
fi

status="$(printf '%s' "$raw" | process_status "$launch_harness" 2>/dev/null)" || status=""
[ -n "$status" ] || status="ERROR"
if [ "$rc" -ne 0 ]; then
    echo "==> $launch_persona's session did not complete (exit $rc, status $status)." >&2
    exit 1
fi

text="$(printf '%s' "$raw" | response_text "$launch_harness" 2>/dev/null)" || text=""
result_line="$(printf '%s\n' "$text" \
    | grep -E '^[[:space:]]*WORK-RESULT:' | tail -1)" || result_line=""

if [ "$status" != "SUCCESS" ]; then
    if [ -z "$result_line" ]; then
        echo "==> $launch_persona's session did not complete (exit 0, status $status)." >&2
        exit 1
    fi
    err="$(printf '%s' "$raw" | jq -r '(.error // "")' 2>/dev/null | tr '\n' ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    if [ -n "$err" ]; then
        echo "==> warning: $launch_persona's harness reported status $status with error: $err; terminal WORK-RESULT observed, proceeding." >&2
    else
        echo "==> warning: $launch_persona's harness reported status $status (no error detail); terminal WORK-RESULT observed, proceeding." >&2
    fi
elif [ -z "$result_line" ]; then
    # A launcher that returns 0 for an outcome it could not observe is
    # lying, and a session that ran out of turns leaves exactly this
    # trace (D14).
    echo "==> $launch_persona's session exited cleanly but printed no WORK-RESULT line; the outcome was not observed." >&2
    exit 1
fi
verdict="$(printf '%s\n' "$result_line" | awk '{print $2}')"
echo "==> $launch_persona reported: $verdict"
case "$verdict" in
    ok)              exit 0 ;;
    refused|blocked) exit 2 ;;
    *)
        echo "==> '$verdict' is not one of ok|refused|blocked; the outcome was not observed." >&2
        exit 1 ;;
esac
