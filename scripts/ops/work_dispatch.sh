#!/usr/bin/env bash
# scripts/ops/work_dispatch.sh [<issue-number>] [--as <persona>] [--yolo] (#441)
#
# The dispatch logic behind the `/work` command (.claude/commands/work.md).
# Before #441 that command always ran headless (HEADLESS=1 scripts/ops/
# work.sh), whatever it was asked and whether or not a human was watching.
# This is the two ways of working the README names instead:
#
#   /work [<n>]            at the keyboard: resolve <n> (an explicit
#                           argument, the current worktree's branch, the
#                           last issue this session touched, or — none of
#                           those — a picker), claim it if nobody has, and
#                           stop at its state and stage. The session
#                           itself drives the stage from there, one rung
#                           at a time, in the foreground.
#   /work [<n>] --yolo     handing off: unchanged from before #441 —
#                           resolve <n> the same way, then
#                           HEADLESS=1 scripts/ops/work.sh <n> [--as ...],
#                           which dispatches the owning persona unattended.
#
# scripts/ops/work.sh itself is untouched by #441 (#36 D7: a number is
# the whole instruction, nothing else is an argument); this script only
# decides what number reaches it, whether headless mode is asked for, or
# whether it is called at all.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GITHUB_REPO="${GITHUB_REPO:-${GITHUB_REPOSITORY:-evekhm/agentic-sdlc}}"

die() { echo "work_dispatch.sh: $*" >&2; exit 1; }

# --- Arguments: a number, --as <persona> (forwarded to work.sh), --yolo ----
YOLO=0
NUMBER=""
PASSTHROUGH=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        --yolo) YOLO=1; shift ;;
        --as) [ "$#" -ge 2 ] || die "--as needs a persona name"; PASSTHROUGH+=(--as "$2"); shift 2 ;;
        --as=*) PASSTHROUGH+=("$1"); shift ;;
        *)
            STRIPPED="${1#\#}"
            case "$STRIPPED" in
                ''|*[!0-9]*)
                    die "'$1' is not an issue number, --as <persona>, or --yolo (a free-text description isn't resolved yet, #441)"
                    ;;
            esac
            [ -z "$NUMBER" ] || die "one number per dispatch (saw '$NUMBER' and '$STRIPPED')"
            NUMBER="$STRIPPED"; shift ;;
    esac
done

# --- Resolve <n> ------------------------------------------------------------
STATUS=0
if [ -n "$NUMBER" ]; then
    RESOLVED="$("$REPO_ROOT/scripts/ops/resolve_work_target.sh" "$NUMBER")" || STATUS=$?
else
    RESOLVED="$("$REPO_ROOT/scripts/ops/resolve_work_target.sh")" || STATUS=$?
fi

if [ "$STATUS" -eq 3 ]; then
    echo "$RESOLVED"
    exit 3
fi
[ "$STATUS" -eq 0 ] || exit "$STATUS"
NUMBER="$RESOLVED"

# --- --as is a --yolo dispatch override; guided mode has no dispatch to
# override (#441 D3). Refused before any digest line, not just dropped.
if [ "$YOLO" -eq 0 ] && [ "${#PASSTHROUGH[@]}" -gt 0 ]; then
    die "--as is a --yolo dispatch override; add --yolo, or drop --as for guided mode"
fi

# --- Handing off: unchanged headless dispatch -------------------------------
if [ "$YOLO" -eq 1 ]; then
    exec env HEADLESS=1 "$REPO_ROOT/scripts/ops/work.sh" "$NUMBER" "${PASSTHROUGH[@]}"
fi

# --- At the keyboard: claim if nobody has, then stop at the digest ---------
"$REPO_ROOT/scripts/ops/digest.sh" "$NUMBER"
echo "---"

# hold, closed, status:review-stuck and blocked are checked here even when
# the issue already carries in-progress: skipping straight to "leave the
# existing claim in place" below would otherwise never invoke claim.sh,
# and claim.sh is the only component downstream that refuses on any of
# them. Same set and order work.sh's own circuit breaker refuses at its
# steps (a), (c) and (d) (work.sh:294-320) — this is the guided path
# getting the same circuit breaker (#441 D4).
ISSUE_JSON="$(gh issue view "$NUMBER" --repo "$GITHUB_REPO" --json state,labels,comments 2>/dev/null || echo '{"state":"OPEN","labels":[],"comments":[]}')"
ISSUE_STATE="$(jq -r '.state' <<<"$ISSUE_JSON")"
LABELS="$(jq -c '[.labels[].name]' <<<"$ISSUE_JSON")"
if jq -e 'index("hold")' <<<"$LABELS" >/dev/null 2>&1; then
    echo "work_dispatch.sh: refused: #$NUMBER carries hold" >&2
    exit 2
fi
if [ "$ISSUE_STATE" != "OPEN" ]; then
    echo "work_dispatch.sh: refused: #$NUMBER is closed" >&2
    exit 2
fi
if jq -e 'index("status:review-stuck")' <<<"$LABELS" >/dev/null 2>&1; then
    echo "work_dispatch.sh: refused: #$NUMBER carries status:review-stuck" >&2
    exit 2
fi
if jq -e 'index("blocked")' <<<"$LABELS" >/dev/null 2>&1; then
    echo "work_dispatch.sh: refused: #$NUMBER carries blocked" >&2
    exit 2
fi

ALREADY_CLAIMED="$(jq -r 'index("in-progress") // "null"' <<<"$LABELS")"
if [ "$ALREADY_CLAIMED" = "null" ]; then
    "$REPO_ROOT/scripts/ops/claim.sh" "$NUMBER"
else
    # digest.sh's last-comment line is whatever comment is newest, which
    # is usually a bot's review or escalation note, not the claim — so it
    # cannot be trusted to name the holder (Argus R1-1 on PR #462). The
    # holder is the AUTHOR of the comment that opens with a structured
    # claim line (AGENTS.md, "Working the tracker", step 2;
    # resume-protocol.md refusal 5), read the same way work.sh's own (g)
    # check does — never a name out of the body, which any commenter
    # could forge.
    CLAIM_RE='\A[[:space:]]*\**[[:space:]]*Claim(ing)?\b'
    CLAIM_LOGIN="$(jq -r --arg re "$CLAIM_RE" \
        '[.comments[] | select((.body // "") | test($re; "i"))] | last | .author.login // ""' \
        <<<"$ISSUE_JSON" 2>/dev/null)"
    if [ -n "$CLAIM_LOGIN" ]; then
        echo "work_dispatch.sh: #$NUMBER already carries in-progress, held by $CLAIM_LOGIN; leaving the existing claim in place"
    else
        echo "work_dispatch.sh: #$NUMBER already carries in-progress, but the holder cannot be established (no comment opens with a structured claim line); leaving the existing claim in place"
    fi
fi
