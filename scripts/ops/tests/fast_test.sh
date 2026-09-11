#!/usr/bin/env bash
# Tests for scripts/ops/fast.sh (#444).
#
#   bash scripts/ops/tests/fast_test.sh
#
# Hermetic: a stub `gh` on PATH simulates GitHub API calls from fixtures,
# recording mutations to a write log. No network, no token.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
FAST_SH="$REPO/scripts/ops/fast.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FIXTURES="$WORK/fixtures"
WRITES="$WORK/writes.log"
CALLS="$WORK/calls.log"
mkdir -p "$FIXTURES" "$WORK/bin"
: > "$WRITES"
: > "$CALLS"

export GITHUB_REPO="test/repo"
export FIXTURES WRITES CALLS
export PATH="$WORK/bin:$PATH"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

# --- Stub gh ---
cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CALLS"

if [ "${1:-}" = "api" ]; then
    if [ "$#" -eq 2 ] && [[ "$2" != -* ]]; then
        file="$FIXTURES/${2//\//_}.json"
        if [ -f "$file" ]; then
            cat "$file"
            exit 0
        fi
        echo "stub gh: no fixture for $2 ($file)" >&2
        exit 1
    fi
fi

printf '%s\n' "$*" >> "$WRITES"
if [[ "$*" == *"pr list"* ]]; then
    echo "[]"
    exit 0
fi
if [[ "$*" == *"pr create"* ]]; then
    echo "https://github.com/test/repo/pull/999"
    exit 0
fi
exit 0
STUB
chmod +x "$WORK/bin/gh"

# --- Test 1: --help exits 0 ---
set +e
help_out="$("$FAST_SH" --help)"
status=$?
set -e
[ "$status" -eq 0 ] || fail "--help did not exit 0"
grep -q "Usage: scripts/ops/fast.sh" <<<"$help_out" || fail "--help missing usage text"
pass "1. --help prints usage and exits 0"

# --- Test 2: Missing issue argument exits 1 ---
set +e
"$FAST_SH" >/dev/null 2>&1
status=$?
set -e
[ "$status" -eq 1 ] || fail "missing issue argument did not exit 1 (got $status)"
pass "2. missing issue argument exits 1"

# --- Test 3: Non-numeric issue exits 1 ---
set +e
err_out="$("$FAST_SH" "abc" 2>&1 || true)"
set -e
grep -q "issue must be a positive integer" <<<"$err_out" || fail "non-numeric issue error missing"
pass "3. non-numeric issue exits 1"

# --- Test 4: Refusal on closed issue (exits 2) ---
cat > "$FIXTURES/repos_test_repo_issues_101.json" <<'JSON'
{
  "state": "closed",
  "title": "Closed item",
  "labels": []
}
JSON
set +e
err_out="$("$FAST_SH" 101 2>&1)"
status=$?
set -e
[ "$status" -eq 2 ] || fail "closed issue did not exit 2 (got $status)"
grep -q "refused: issue #101 is closed" <<<"$err_out" || fail "closed issue message mismatch"
pass "4. refusal on closed issue"

# --- Test 5: Refusal on hold issue (exits 2) ---
cat > "$FIXTURES/repos_test_repo_issues_102.json" <<'JSON'
{
  "state": "open",
  "title": "Held item",
  "labels": [{"name": "hold"}]
}
JSON
set +e
err_out="$("$FAST_SH" 102 2>&1)"
status=$?
set -e
[ "$status" -eq 2 ] || fail "hold issue did not exit 2 (got $status)"
grep -q "refused: issue #102 carries hold label" <<<"$err_out" || fail "hold issue message mismatch"
pass "5. refusal on hold issue"

# --- Test 6: Refusal on blocked issue (exits 2) ---
cat > "$FIXTURES/repos_test_repo_issues_103.json" <<'JSON'
{
  "state": "open",
  "title": "Blocked item",
  "labels": [{"name": "blocked"}]
}
JSON
set +e
err_out="$("$FAST_SH" 103 2>&1)"
status=$?
set -e
[ "$status" -eq 2 ] || fail "blocked issue did not exit 2 (got $status)"
grep -q "refused: issue #103 carries blocked label" <<<"$err_out" || fail "blocked issue message mismatch"
pass "6. refusal on blocked issue"

# --- Test 7: Stage transition and dry-run preview ---
cat > "$FIXTURES/repos_test_repo_issues_104.json" <<'JSON'
{
  "state": "open",
  "title": "Fresh issue",
  "labels": [{"name": "intent:new"}]
}
JSON
set +e
out="$("$FAST_SH" 104 --dry-run 2>&1)"
status=$?
set -e
[ "$status" -eq 0 ] || fail "dry-run on fresh issue failed (got $status)"
grep -q "Transitioning issue #104 to status:implementing" <<<"$out" || fail "transition log missing"
grep -q "would: remove obsolete intake/stage labels and add status:implementing" <<<"$out" || fail "dry run would missing"
pass "7. dry-run transition preview"

echo ""
echo "=== All 7 tests in fast_test.sh passed ==="
