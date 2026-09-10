#!/usr/bin/env bash
# Tests for scripts/ops/digest.sh (#407).
#
#   bash scripts/ops/tests/digest_test.sh
#
# Hermetic, same stubbing technique as scripts/ops/tests/work_test.sh: a
# stub `gh` first on PATH answers every call from canned fixtures, and
# an unrecognised call is a loud failure rather than a silent one.
# digest.sh calls `gh` directly (no other repo-relative script), so no
# fixture tree is needed here.
#
# Exit 0 with a PASS line per assertion, non-zero on the first failure.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
DIGEST="$REPO/scripts/ops/digest.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass() { echo "PASS: $*" >&2; }
fail() { echo "FAIL: $*" >&2; exit 1; }

mkdir -p "$WORK/bin"
export GITHUB_REPO="test/repo"

# --- stub gh --------------------------------------------------------------
# Controlled by env vars so each scenario can flip one call's behaviour:
#   ISSUE_VIEW_RC   exit code for `gh issue view`  (default 0)
#   PR_LIST_RC      exit code for `gh pr list`      (default 0)
cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
case "$1 $2" in
    "issue view")
        [ "${ISSUE_VIEW_RC:-0}" -eq 0 ] || exit "${ISSUE_VIEW_RC}"
        cat <<'JSON'
{"title":"A digest test issue","state":"OPEN","labels":[{"name":"status:build"},{"name":"in-progress"}],"comments":[{"author":{"login":"argus"},"body":"first line of last comment\nrest is ignored"}]}
JSON
        exit 0
        ;;
    "pr list")
        [ "${PR_LIST_RC:-0}" -eq 0 ] || exit "${PR_LIST_RC}"
        cat <<'JSON'
[{"number":42,"title":"Fix the thing","url":"https://github.com/test/repo/pull/42"}]
JSON
        exit 0
        ;;
    *)
        echo "stub gh: unexpected call: $*" >&2
        exit 1
        ;;
esac
STUB
chmod +x "$WORK/bin/gh"
export PATH="$WORK/bin:$PATH"

# --- good data: all four lines present, exit 0 -----------------------------
out="$(ISSUE_VIEW_RC=0 PR_LIST_RC=0 "$DIGEST" 7 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || fail "good data: expected exit 0, got $rc"
echo "$out" | grep -q '^digest: #7 (issue) "A digest test issue" -- OPEN$' \
    || fail "good data: missing title/state line -- got:\n$out"
echo "$out" | grep -q '^digest: labels: status:build, in-progress$' \
    || fail "good data: missing labels line -- got:\n$out"
echo "$out" | grep -q '^digest: open PR: #42 Fix the thing (https://github.com/test/repo/pull/42)$' \
    || fail "good data: missing open-PR line -- got:\n$out"
echo "$out" | grep -q '^digest: last comment: argus: first line of last comment$' \
    || fail "good data: missing last-comment line -- got:\n$out"
pass "good data: all four digest lines present, exit 0"

# --- degrade gracefully: issue view fails, still exits 0 -------------------
out="$(ISSUE_VIEW_RC=1 PR_LIST_RC=0 "$DIGEST" 7 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || fail "degraded issue view: expected exit 0, got $rc"
echo "$out" | grep -q 'unavailable' \
    || fail "degraded issue view: expected an (unavailable) line -- got:\n$out"
pass "degraded issue view: still exits 0 and prints (unavailable)"

# --- degrade gracefully: pr list fails, still exits 0 -----------------------
out="$(ISSUE_VIEW_RC=0 PR_LIST_RC=1 "$DIGEST" 7 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || fail "degraded pr list: expected exit 0, got $rc"
echo "$out" | grep -q '^digest: no open PR references it$' \
    || fail "degraded pr list: expected the no-PR fallback line -- got:\n$out"
pass "degraded pr list: still exits 0 and falls back cleanly"

# --- no number given: still exits 0 -----------------------------------------
out="$("$DIGEST" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || fail "no number: expected exit 0, got $rc"
echo "$out" | grep -q 'unavailable' \
    || fail "no number: expected an unavailable line -- got:\n$out"
pass "no number given: still exits 0"

echo "digest_test.sh: all scenarios passed"
