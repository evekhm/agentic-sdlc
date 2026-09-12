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
        ''|*[!0-9]*)
            die "'$1' is not an issue number, --as <persona>, or --yolo (a free-text description isn't resolved yet, #441)"
            ;;
        *)
            [ -z "$NUMBER" ] || die "one number per dispatch (saw '$NUMBER' and '$1')"
            NUMBER="$1"; shift ;;
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

# --- Handing off: unchanged headless dispatch -------------------------------
if [ "$YOLO" -eq 1 ]; then
    exec env HEADLESS=1 "$REPO_ROOT/scripts/ops/work.sh" "$NUMBER" "${PASSTHROUGH[@]}"
fi

# --- At the keyboard: claim if nobody has, then stop at the digest ---------
"$REPO_ROOT/scripts/ops/digest.sh" "$NUMBER"
echo "---"

ALREADY_CLAIMED="$(gh issue view "$NUMBER" --repo "$GITHUB_REPO" --json labels -q '[.labels[].name] | index("in-progress")' 2>/dev/null || true)"
if [ "$ALREADY_CLAIMED" = "null" ] || [ -z "$ALREADY_CLAIMED" ]; then
    "$REPO_ROOT/scripts/ops/claim.sh" "$NUMBER"
else
    echo "work_dispatch.sh: #$NUMBER already carries in-progress; leaving the existing claim in place"
fi
