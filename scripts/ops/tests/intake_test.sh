#!/usr/bin/env bash
# Tests for scripts/ops/intake.sh (#407).
#
#   bash scripts/ops/tests/intake_test.sh
#
# Hermetic, same technique as scripts/ops/tests/work_test.sh:
#   - a fixture TREE holds its own copy of intake.sh alongside a STUB
#     tracker_search.sh (intake.sh resolves it by absolute path from
#     BASH_SOURCE, same as work.sh resolves mint_app_token.py, so PATH
#     cannot stub it — a whole tree can); the stub's exit code and
#     output are driven by an env var so no real gh/jq call is made by
#     tracker_search.sh's own logic.
#   - a stub `gh` first on PATH answers `gh issue create` and logs it,
#     so a scenario that must not file anything fails loudly if it did.
#
# Exit 0 with a PASS line per assertion, non-zero on the first failure.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass() { echo "PASS: $*" >&2; }
fail() { echo "FAIL: $*" >&2; exit 1; }

# --- fixture tree: real intake.sh, stub tracker_search.sh ----------------------
T="$WORK/tree"
mkdir -p "$T/scripts/ops"
cp "$REPO/scripts/ops/intake.sh" "$T/scripts/ops/intake.sh"
chmod +x "$T/scripts/ops/intake.sh"
INTAKE="$T/scripts/ops/intake.sh"

TRACKER_LOG="$WORK/tracker.log"
cat > "$T/scripts/ops/tracker_search.sh" <<'STUB'
#!/usr/bin/env bash
echo "$@" >> "$TRACKER_LOG"
echo "== stub tracker_search =="
if [ "${TRACKER_RC:-0}" -eq 2 ]; then
    echo "  #999 a matching issue"
    exit 2
fi
echo "tracker searched, no prior art: (stub)"
exit 0
STUB
chmod +x "$T/scripts/ops/tracker_search.sh"

# --- stub gh: only `gh issue create ...` is handled, everything logged --------
ISSUE_CREATE_LOG="$WORK/issue_create.log"
: > "$ISSUE_CREATE_LOG"
mkdir -p "$WORK/bin"
cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = "issue" ] && [ "${2:-}" = "create" ]; then
    echo "$@" >> "$ISSUE_CREATE_LOG"
    echo "https://github.com/evekhm/agentic-sdlc/issues/999"
    exit 0
fi
echo "stub gh: unexpected call: $*" >&2
exit 1
STUB
chmod +x "$WORK/bin/gh"
export PATH="$WORK/bin:$PATH"
export TRACKER_LOG ISSUE_CREATE_LOG

BODY="$WORK/body.txt"
echo "a placeholder body" > "$BODY"

run() { # <expected-rc> <label> -- <args...>
    local expected="$1" label="$2"
    shift 3
    : > "$TRACKER_LOG"; : > "$ISSUE_CREATE_LOG"
    local out rc=0
    out="$("$INTAKE" "$@" 2>&1)" || rc=$?
    [ "$rc" -eq "$expected" ] \
        || fail "$label: expected exit $expected, got $rc -- output:\n$out"
    pass "$label"
    printf '%s' "$out"
}

# --- bad --kind: exit 1, nothing searched, nothing filed -----------------------
TRACKER_RC=0 run 1 "bad --kind rejected" -- --kind idea-typo --title "x" --body-file "$BODY" >/dev/null
[ ! -s "$TRACKER_LOG" ] || fail "bad --kind: tracker_search.sh must not run"
[ ! -s "$ISSUE_CREATE_LOG" ] || fail "bad --kind: gh issue create must not run"

# --- missing required args: exit 1 ---------------------------------------------
TRACKER_RC=0 run 1 "missing --title" -- --kind idea --body-file "$BODY" >/dev/null
TRACKER_RC=0 run 1 "missing --body-file" -- --kind idea --title "x" >/dev/null
TRACKER_RC=0 run 1 "missing --kind" -- --title "x" --body-file "$BODY" >/dev/null

# --- search-only path, clear: exit 0, searched, nothing filed ------------------
TRACKER_RC=0 run 0 "search-only clear" -- --kind idea --title "a new idea" --body-file "$BODY" >/dev/null
grep -q -- "--terms a new idea" "$TRACKER_LOG" \
    || fail "search-only clear: expected title words passed as --terms"
[ ! -s "$ISSUE_CREATE_LOG" ] || fail "search-only clear: gh issue create must not run"

# --- search-only path, matches: exit 2, nothing filed --------------------------
TRACKER_RC=2 run 2 "search-only matches" -- --kind idea --title "a new idea" --body-file "$BODY" >/dev/null
[ ! -s "$ISSUE_CREATE_LOG" ] || fail "search-only matches: gh issue create must not run"

# --- --file path, matches: exit 2, still nothing filed (re-checked) -----------
TRACKER_RC=2 run 2 "--file re-checks search, refuses on matches" -- --kind idea --title "a new idea" --body-file "$BODY" --file >/dev/null
[ ! -s "$ISSUE_CREATE_LOG" ] || fail "--file with matches: gh issue create must not run"

# --- --file path, clear, kind idea: exit 0, filed with intent:new only --------
TRACKER_RC=0 run 0 "--file idea files intent:new" -- --kind idea --title "a new idea" --body-file "$BODY" --file >/dev/null
grep -q -- "--label intent:new" "$ISSUE_CREATE_LOG" \
    || fail "--file idea: expected --label intent:new"
grep -q -- "--label bug" "$ISSUE_CREATE_LOG" \
    && fail "--file idea: must not add --label bug"

# --- --file path, clear, kind bug: exit 0, filed with intent:new AND bug ------
TRACKER_RC=0 run 0 "--file bug files intent:new + bug" -- --kind bug --title "a new bug" --body-file "$BODY" --file >/dev/null
grep -q -- "--label intent:new" "$ISSUE_CREATE_LOG" \
    || fail "--file bug: expected --label intent:new"
grep -q -- "--label bug" "$ISSUE_CREATE_LOG" \
    || fail "--file bug: expected --label bug"

echo "intake_test.sh: all scenarios passed"
