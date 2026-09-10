#!/usr/bin/env bash
# scripts/ops/intake.sh — shared mechanics for the /idea and /bug command
# doors (#407).
#
#   scripts/ops/intake.sh --kind idea|bug --title "<title>" --body-file <path> [--file]
#
# No search logic lives here: this delegates both of tracker_search.sh's
# passes (file-scoped and keyword) to that script as-is. Keyword terms
# are the title's words, split on whitespace, passed through as
# --terms. --body-file's own path is passed as the (required) --files
# argument for the file-scoped pass; it is never a tracked repository
# path, so that pass reports "none" for a fresh intake by construction —
# the keyword pass is where a real match for intake text is expected to
# surface.
#
# The search always runs, --file or not: a caller that re-invokes with
# --file after already reading a clear search gets it re-checked for
# free, and a caller that races and finds new matches on the --file
# call is refused just as it would be on the search-only call.
#
# Only when the search is clear AND --file is given does this run
# `gh issue create` (with --label bug added for --kind bug).
#
# Exit codes mirror scripts/ops/work.sh's die()/refuse() convention:
#   0  search ran, clear (no prior art) — filed too, if --file was given
#   1  unusable input (die): bad --kind, missing/unreadable arguments
#   2  refuse: tracker search found matches; nothing was filed
set -euo pipefail

die() { echo "intake.sh: $*" >&2; exit 1; }

KIND=""
TITLE=""
BODY_FILE=""
DO_FILE=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --kind) [ "$#" -ge 2 ] || die "--kind needs a value"; KIND="$2"; shift 2 ;;
        --title) [ "$#" -ge 2 ] || die "--title needs a value"; TITLE="$2"; shift 2 ;;
        --body-file) [ "$#" -ge 2 ] || die "--body-file needs a value"; BODY_FILE="$2"; shift 2 ;;
        --file) DO_FILE=1; shift ;;
        *) die "unknown argument '$1'" ;;
    esac
done

case "$KIND" in
    idea|bug) ;;
    *) die "--kind must be 'idea' or 'bug', got '${KIND:-<empty>}'" ;;
esac
[ -n "$TITLE" ] || die "--title is required"
[ -n "$BODY_FILE" ] || die "--body-file is required"
[ -r "$BODY_FILE" ] || die "cannot read --body-file '$BODY_FILE'"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TRACKER_SEARCH="$REPO_ROOT/scripts/ops/tracker_search.sh"
[ -x "$TRACKER_SEARCH" ] || die "cannot run $TRACKER_SEARCH"

read -ra TERMS <<<"$TITLE"

rc=0
search_output="$("$TRACKER_SEARCH" --files "$BODY_FILE" --terms "${TERMS[@]}" 2>&1)" || rc=$?
echo "$search_output"

if [ "$rc" -eq 1 ]; then
    die "tracker_search.sh could not run (see output above)"
fi
if [ "$rc" -eq 2 ]; then
    echo
    echo "intake.sh: matches found above. Read them, including comment threads (AGENTS.md, \"Before filing an issue\", step 4), and decide duplicate-vs-new yourself before re-running with --file." >&2
    exit 2
fi

if [ "$DO_FILE" -eq 1 ]; then
    args=(gh issue create --title "$TITLE" --body-file "$BODY_FILE" --label intent:new)
    [ "$KIND" != "bug" ] || args+=(--label bug)
    "${args[@]}"
fi
exit 0
