#!/usr/bin/env bash
# Tests for scripts/ops/fast.sh (#444).
#
#   bash scripts/ops/tests/fast_test.sh
#
# Hermetic: a stub `gh` on PATH simulates GitHub API calls from fixtures,
# recording mutations to a write log. No network, no token.

set -euo pipefail

# Unset GITHUB_ACTIONS so hermetic tests run cleanly in CI environments;
# Test 10 explicitly sets GITHUB_ACTIONS=true to test the guard.
unset GITHUB_ACTIONS

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
export WORK FIXTURES WRITES CALLS
export PATH="$WORK/bin:$PATH"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

# --- Stub gh ---
cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CALLS"

if [ "${1:-}" = "api" ]; then
    shift
    # Check for DELETE or POST flags
    is_mutation=0
    for arg in "$@"; do
        if [ "$arg" = "-X" ] || [ "$arg" = "-f" ] || [ "$arg" = "-F" ]; then
            is_mutation=1
            break
        fi
    done
    if [ "$is_mutation" -eq 1 ]; then
        printf 'gh api %s\n' "$*" >> "$WRITES"
        exit 0
    fi

    # Read endpoints and jq queries
    endpoint=""
    jq_query=""
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -q|--jq) jq_query="$2"; shift 2 ;;
            -*) shift ;;
            *) endpoint="$1"; shift ;;
        esac
    done

    json_out=""
    if [ "$endpoint" = "user" ]; then
        user_login="${STUB_USER_LOGIN:-eva}"
        user_type="${STUB_USER_TYPE:-User}"
        json_out="{\"login\": \"$user_login\", \"type\": \"$user_type\"}"
    elif [[ "$endpoint" =~ repos/[^/]+/[^/]+/collaborators/([^/]+)/permission ]]; then
        user_perm="${STUB_USER_PERM:-write}"
        json_out="{\"permission\": \"$user_perm\"}"
    else
        file="$FIXTURES/${endpoint//\//_}.json"
        if [ -f "$file" ]; then
            json_out="$(cat "$file")"
        else
            echo "stub gh: no fixture for $endpoint ($file)" >&2
            exit 1
        fi
    fi

    if [ -n "$jq_query" ]; then
        jq -r "$jq_query" <<<"$json_out"
    else
        echo "$json_out"
    fi
    exit 0
fi

printf 'gh %s\n' "$*" >> "$WRITES"
if [[ "$*" == *"pr list"* ]]; then
    if [[ "$*" =~ (-q|--jq) ]]; then
        exit 0
    fi
    echo "[]"
    exit 0
fi
if [[ "$*" == *"pr create"* ]]; then
    body_file=""
    args=("$@")
    for ((i=0; i<${#args[@]}; i++)); do
        if [ "${args[i]}" = "--body-file" ] && [ $((i+1)) -lt ${#args[@]} ]; then
            body_file="${args[i+1]}"
            break
        fi
    done
    if [ -n "$body_file" ] && [ -f "$body_file" ]; then
        cp "$body_file" "$WORK/last_pr_body.txt"
    fi
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

# --- Test 7: Refusal on status:review-stuck (exits 2) ---
cat > "$FIXTURES/repos_test_repo_issues_105.json" <<'JSON'
{
  "state": "open",
  "title": "Review stuck item",
  "labels": [{"name": "status:review-stuck"}]
}
JSON
set +e
err_out="$("$FAST_SH" 105 2>&1)"
status=$?
set -e
[ "$status" -eq 2 ] || fail "review-stuck issue did not exit 2 (got $status)"
grep -q "carries status:review-stuck" <<<"$err_out" || fail "review-stuck message mismatch"
pass "7. refusal on status:review-stuck"

# --- Test 8: Refusal on status:in-review (exits 2) ---
cat > "$FIXTURES/repos_test_repo_issues_106.json" <<'JSON'
{
  "state": "open",
  "title": "In review item",
  "labels": [{"name": "status:in-review"}]
}
JSON
set +e
err_out="$("$FAST_SH" 106 2>&1)"
status=$?
set -e
[ "$status" -eq 2 ] || fail "in-review issue did not exit 2 (got $status)"
grep -q "carries status:in-review" <<<"$err_out" || fail "in-review message mismatch"
pass "8. refusal on status:in-review"

# --- Test 9: Refusal on multiple contradictory status labels (exits 2) ---
cat > "$FIXTURES/repos_test_repo_issues_107.json" <<'JSON'
{
  "state": "open",
  "title": "Conflicting status item",
  "labels": [{"name": "status:spec"}, {"name": "status:build"}]
}
JSON
set +e
err_out="$("$FAST_SH" 107 2>&1)"
status=$?
set -e
[ "$status" -eq 2 ] || fail "multiple status labels did not exit 2 (got $status)"
grep -q "contradictory status labels" <<<"$err_out" || fail "multiple status error missing"
pass "9. refusal on multiple contradictory status labels"

# --- Test 10: Authorization boundary — refusal in GitHub Actions context (exits 2) ---
cat > "$FIXTURES/repos_test_repo_issues_104.json" <<'JSON'
{
  "state": "open",
  "title": "Fresh issue",
  "labels": [{"name": "intent:new"}]
}
JSON
set +e
err_out="$(GITHUB_ACTIONS=true "$FAST_SH" 104 2>&1)"
status=$?
set -e
[ "$status" -eq 2 ] || fail "GITHUB_ACTIONS=true did not exit 2 (got $status)"
grep -q "fast-track cannot be initiated within GitHub Actions" <<<"$err_out" || fail "actions context message missing"
pass "10. refusal within GitHub Actions context"

# --- Test 11: Authorization boundary — refusal on autonomous bot identity (exits 2) ---
set +e
err_out="$(STUB_USER_LOGIN="evekhm-atlas-app[bot]" "$FAST_SH" 104 2>&1)"
status=$?
set -e
[ "$status" -eq 2 ] || fail "bot identity did not exit 2 (got $status)"
grep -q "cannot be initiated by an autonomous bot identity" <<<"$err_out" || fail "bot identity message missing"
pass "11. refusal on autonomous bot identity"

# --- Test 12: Authorization boundary — refusal on non-write permissions (exits 2) ---
set +e
err_out="$(STUB_USER_PERM="read" "$FAST_SH" 104 2>&1)"
status=$?
set -e
[ "$status" -eq 2 ] || fail "read-only user did not exit 2 (got $status)"
grep -q "does not have write or admin permissions" <<<"$err_out" || fail "permission check message missing"
pass "12. refusal on read-only user permissions"

# --- Test 13: Stage transition dry-run preview ---
set +e
out="$("$FAST_SH" 104 --dry-run 2>&1)"
status=$?
set -e
[ "$status" -eq 0 ] || fail "dry-run on fresh issue failed (got $status)"
grep -q "Transitioning issue #104 to status:implementing" <<<"$out" || fail "transition log missing"
grep -q "would: remove obsolete intake/authoring labels and add status:implementing" <<<"$out" || fail "dry run would missing"
pass "13. dry-run transition preview"

# --- Test 14: Non-dry-run transition deletes ONLY authoring labels and uses file body ---
: > "$WRITES"
set +e
out="$("$FAST_SH" 104 2>&1)"
status=$?
set -e
[ "$status" -eq 0 ] || fail "fast.sh on fresh issue failed (got $status)"

# Verify DELETE calls only target authoring labels
grep -q "DELETE repos/test/repo/issues/104/labels/intent:new" "$WRITES" || fail "intent:new not deleted"
grep -q "DELETE repos/test/repo/issues/104/labels/status:planning" "$WRITES" || fail "status:planning not deleted"
grep -q "DELETE repos/test/repo/issues/104/labels/status:spec" "$WRITES" || fail "status:spec not deleted"
grep -q "DELETE repos/test/repo/issues/104/labels/status:build" "$WRITES" || fail "status:build not deleted"

# Verify forbidden deletions NEVER happened
grep -q "labels/hold" "$WRITES" && fail "deleted hold label"
grep -q "labels/status:review-stuck" "$WRITES" && fail "deleted status:review-stuck"
grep -q "labels/status:in-review" "$WRITES" && fail "deleted status:in-review"

# Verify body posted via -F body=@file
grep -q "issues/104/comments -F body=@" "$WRITES" || fail "comment not posted via -F body=@file"
pass "14. non-dry-run transition deletes only authoring labels and posts via file"

echo ""

# --- Test 15: Refusal when behavior files touched without CHANGELOG.md or --changelog-reason ---
# Create a dummy git repo and worktree to test PR preparation
TEST_REPO="$WORK/test_git_repo"
git init -q -b main "$TEST_REPO"
git -C "$TEST_REPO" config user.email "test@example.com"
git -C "$TEST_REPO" config user.name "Test User"
git -C "$TEST_REPO" commit --allow-empty -m "initial commit"
git -C "$TEST_REPO" branch -M main

TEST_WT="$WORK/wt-200-test"
git -C "$TEST_REPO" worktree add -b eva/200-test "$TEST_WT" main >/dev/null

# Touch a behavior-bearing path
mkdir -p "$TEST_WT/scripts"
echo "echo hello" > "$TEST_WT/scripts/test_script.sh"
git -C "$TEST_WT" add scripts/test_script.sh
git -C "$TEST_WT" commit -m "add test script"

cat > "$FIXTURES/repos_test_repo_issues_200.json" <<'JSON'
{
  "state": "open",
  "title": "Behavior issue",
  "labels": [{"name": "status:implementing"}]
}
JSON

# Run fast.sh inside test repo context with git worktree list pointing to TEST_WT
set +e
err_out="$(cd "$TEST_REPO" && "$FAST_SH" 200 2>&1)"
status=$?
set -e
[ "$status" -eq 2 ] || fail "behavior change without changelog reason did not exit 2 (got $status)"
grep -q "behavior-bearing files changed without a CHANGELOG.md update" <<<"$err_out" || fail "changelog refusal message missing"
pass "15. refusal on behavior change without changelog reason"

# --- Test 16: Refusal on boilerplate changelog reason ---
set +e
err_out="$(cd "$TEST_REPO" && "$FAST_SH" 200 --changelog-reason "fast-track" 2>&1)"
status=$?
set -e
[ "$status" -eq 2 ] || fail "boilerplate changelog reason did not exit 2 (got $status)"
grep -q "boilerplate changelog reason is not permitted" <<<"$err_out" || fail "boilerplate message missing"
pass "16. refusal on boilerplate changelog reason"

# --- Test 17: Valid substantive changelog reason creates PR with mandatory header ---
: > "$WRITES"
set +e
out="$(cd "$TEST_REPO" && "$FAST_SH" 200 --changelog-reason "internal test tool not user facing" 2>&1)"
status=$?
set -e
[ "$status" -eq 0 ] || fail "substantive changelog reason failed (got $status)"

# Verify pr create was called
grep -q "pr create" "$WRITES" || fail "pr create not executed"
grep -q "Owner-authorized ladder compression: combines intent/spec/plan/implement into one round (Refs #200)" "$WORK/last_pr_body.txt" || fail "mandatory PR header missing"
grep -q "Changelog: none — internal test tool not user facing" "$WORK/last_pr_body.txt" || fail "changelog reason missing from PR body"
grep -q "Closes #200" "$WORK/last_pr_body.txt" || fail "Closes #200 missing from PR body"
pass "17. valid changelog reason creates PR with mandatory header and closes reference"


echo ""
echo "=== All 17 tests in fast_test.sh passed ==="
