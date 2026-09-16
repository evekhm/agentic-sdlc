#!/usr/bin/env bash
# Contract tests for native Issue Dependencies in claim.sh (#372).
# Cites Decisions D1, D2, D3, D4, D5, D6, D7, D8
# and Acceptance Tests AT-372-1 through AT-372-10.
#
# Every assertion cites its Decision ID and Acceptance Test ID.
# Under the baseline tree before Odyssey's implementation, all assertions
# must FAIL (red) cleanly with exit code 1, proving behavior is not smuggled.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
CLAIM_SH="$REPO/scripts/ops/claim.sh"
CLAIM_TEST_SH="$REPO/scripts/ops/tests/claim_test.sh"
AGENTS_MD="$REPO/AGENTS.md"
IDEA_MD="$REPO/.claude/commands/idea.md"
BUG_MD="$REPO/.claude/commands/bug.md"
SPEC_MD="$REPO/docs/SPEC.md"

TOTAL=0
PASSED=0
FAILURES=0

banner() { printf '\n=== %s ===\n' "$*"; }

pass() {
    echo "PASS: $*"
    TOTAL=$((TOTAL + 1))
    PASSED=$((PASSED + 1))
}

fail() {
    echo "FAIL: $*" >&2
    TOTAL=$((TOTAL + 1))
    FAILURES=$((FAILURES + 1))
}

# --- Hermetic environment setup for dynamic tests ---
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
export CLAIM_ACTOR=tester CLAIM_SESSION=test-session CLAIM_STAGE=implement
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# Stub gh: answers reads from fixtures, logs calls and writes
cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CALLS"
if [ "${1:-}" = "api" ] && [ "$#" -ge 2 ]; then
  # Strip leading slashes and extract path
  api_path="$2"
  file="$FIXTURES/${api_path//\//_}.json"
  if [ -f "$file" ]; then
    cat "$file"
    if [ -f "$file.next" ]; then mv "$file.next" "$file"; fi
    exit 0
  fi
fi
printf '%s\n' "$*" >> "$WRITES"
echo '{}'
STUB
chmod +x "$WORK/bin/gh"

# Fixture helper for issue payload
# issue <n> <state> <labels-csv> <title> [<body>] [<total_blocked_by>]
fixture_issue() {
  local n="$1" state="$2" labels="$3" title="$4" body="${5:-}" total_blocked_by="${6:-0}"
  jq -n --argjson n "$n" --arg state "$state" --arg labels "$labels" --arg title "$title" \
        --arg body "$body" --argjson total_blocked_by "$total_blocked_by" \
    '{number: $n, state: $state, title: $title, body: $body,
      issue_dependencies_summary: {total_blocked_by: $total_blocked_by},
      labels: ($labels | if . == "" then [] else split(",") end | map({name: .}))}' \
    > "$FIXTURES/repos_test_repo_issues_$n.json"
  echo '[]' > "$FIXTURES/repos_test_repo_issues_${n}_comments.json"
}

# Fixture helper for dependencies/blocked_by endpoint
# blocked_by <n> <json-array-string>
fixture_blocked_by() {
  local n="$1" json="$2"
  printf '%s\n' "$json" > "$FIXTURES/repos_test_repo_issues_${n}_dependencies_blocked_by.json"
}

# Test repo setup for claim.sh primary checkout
git init -q --bare -b main "$WORK/origin.git"
git clone -q "$WORK/origin.git" "$WORK/repo" 2>/dev/null
PRIMARY="$WORK/repo"
cd "$PRIMARY"
git checkout -q -b main
echo base > base.txt
printf '.claude/\n' > .gitignore
mkdir -p "$PRIMARY/personas"
cat > "$PRIMARY/personas/lifecycle.json" <<'JSON'
{"stages":[
  {"stage":"plan","label":"status:planning"},
  {"stage":"design","label":"status:spec"},
  {"stage":"build","label":"status:build"},
  {"stage":"implement","label":"status:implementing"},
  {"stage":"review","label":"status:in-review"}
]}
JSON
git add base.txt .gitignore personas/lifecycle.json
git commit -q -m "initial commit"
git push -q -u origin main
cd "$REPO"

# Helper to run claim.sh in the hermetic repository
run_claim() {
  local num="$1"
  shift
  OUT=""
  set +e
  OUT="$(cd "$PRIMARY" && DRY_RUN=1 bash "$CLAIM_SH" "$num" "$@" 2>&1)"
  EXIT_CODE=$?
  set -e
}

# ==============================================================================
# Assertion 1: D1 / AT-372-1: No body regex in scripts/ops/claim.sh
# ==============================================================================
banner "D1 / AT-372-1: No body dependency scanning in claim.sh"
if [ "$(grep -c "grep -Ei 'depends on'" "$CLAIM_SH" || true)" -eq 0 ] && \
   ! grep -q 'dep_lines.*depends on' "$CLAIM_SH"; then
    pass "D1 / AT-372-1: claim.sh contains no body-text dependency scanning logic"
else
    fail "D1 / AT-372-1: claim.sh still scans issue body for 'depends on'"
fi

# ==============================================================================
# Assertion 2: D1, D3 / AT-372-2: total_blocked_by == 0 short-circuits API call
# ==============================================================================
banner "D1, D3 / AT-372-2: total_blocked_by == 0 skips blocked_by endpoint"
: > "$CALLS"
fixture_issue 201 "open" "status:implementing" "Zero dependencies issue" "No deps" 0
run_claim 201
if ! grep -q 'issues/201/dependencies/blocked_by' "$CALLS" && \
   grep -q 'issue_dependencies_summary' "$CLAIM_SH"; then
    pass "D1, D3 / AT-372-2: claim.sh short-circuits when total_blocked_by is 0"
else
    fail "D1, D3 / AT-372-2: claim.sh does not inspect issue_dependencies_summary or short-circuit correctly"
fi

# ==============================================================================
# Assertion 3: D1, D2 / AT-372-3: Open blocker in blocked_by refuses with format
# ==============================================================================
banner "D1, D2 / AT-372-3: Open blocker refusal format"
fixture_issue 202 "open" "status:implementing" "Blocked issue" "Body" 1
fixture_blocked_by 202 '[{"number": 203, "state": "open", "title": "Core compiler work"}]'
run_claim 202
if [ "$EXIT_CODE" -eq 2 ] && \
   printf '%s' "$OUT" | grep -Fq "#202 is blocked by #203 (open): Core compiler work"; then
    pass "D1, D2 / AT-372-3: Refuses claim naming open blocker (#202 is blocked by #203 (open): Core compiler work)"
else
    fail "D1, D2 / AT-372-3: Did not refuse with required format '#202 is blocked by #203 (open): Core compiler work' (got exit $EXIT_CODE: $OUT)"
fi

# ==============================================================================
# Assertion 4: D1, D2 / AT-372-3: Multiple open blockers joined with semicolon
# ==============================================================================
banner "D1, D2 / AT-372-3: Multiple open blockers format"
fixture_issue 204 "open" "status:implementing" "Multi blocked issue" "Body" 2
fixture_blocked_by 204 '[{"number": 205, "state": "open", "title": "Blocker alpha"}, {"number": 206, "state": "open", "title": "Blocker beta"}]'
run_claim 204
expected_multi="#204 is blocked by #205 (open): Blocker alpha; #206 (open): Blocker beta"
if [ "$EXIT_CODE" -eq 2 ] && \
   printf '%s' "$OUT" | grep -Fq "$expected_multi"; then
    pass "D1, D2 / AT-372-3: Refuses claim joining multiple open blockers with '; '"
else
    fail "D1, D2 / AT-372-3: Did not join multiple open blockers with '; ' (got exit $EXIT_CODE: $OUT)"
fi

# ==============================================================================
# Assertion 5: D1 / AT-372-4: All closed blockers in blocked_by list does not refuse
# ==============================================================================
banner "D1 / AT-372-4: Closed blockers in blocked_by list"
: > "$CALLS"
fixture_issue 207 "open" "status:implementing" "Resolved dependency issue" "Body" 1
fixture_blocked_by 207 '[{"number": 208, "state": "closed", "title": "Completed prerequisite"}]'
run_claim 207
if [ "$EXIT_CODE" -eq 0 ] && \
   grep -q "issues/207/dependencies/blocked_by" "$CALLS" && \
   printf '%s' "$OUT" | grep -Fq "would: gh api --method POST repos/test/repo/issues/207/labels -f labels[]=in-progress"; then
    pass "D1 / AT-372-4: Claim proceeds when all dependencies in blocked_by list are closed"
else
    fail "D1 / AT-372-4: Claim did not call blocked_by endpoint or proceed past closed dependencies (got exit $EXIT_CODE: $OUT)"
fi


# ==============================================================================
# Assertion 6: D1, D6c / AT-372-5: Leading 'Depends on #<n>' line with open blocker
# and total_blocked_by == 0 is NOT refused (regression guard against false-positive)
# ==============================================================================
banner "D1, D6c / AT-372-5: Leading 'Depends on #open' prose ignored when total_blocked_by == 0"
# In the fixture, #210 is an open issue. Body of #209 says "Depends on #210", but total_blocked_by is 0.
fixture_issue 210 "open" "" "Prerequisite in prose" "" 0
fixture_issue 209 "open" "status:implementing" "Issue with prose dependency" "Depends on #210 (documentation only)" 0
run_claim 209
if [ "$EXIT_CODE" -eq 0 ] && \
   ! printf '%s' "$OUT" | grep -Fq "depends on #210, which is still open"; then
    pass "D1, D6c / AT-372-5: Prose 'Depends on #210' ignored when total_blocked_by == 0"
else
    fail "D1, D6c / AT-372-5: Prose 'Depends on' still refused the claim (got exit $EXIT_CODE: $OUT)"
fi

# ==============================================================================
# Assertion 7: D4 / AT-372-7: claim.sh header docstring updated
# ==============================================================================
banner "D4 / AT-372-7: claim.sh header docstring describes native mechanism"
if grep -q 'blocked by.*native' "$CLAIM_SH" || \
   ( ! grep -q 'depends on.*an issue named on a "Depends on" line is still open' "$CLAIM_SH" && \
     grep -q 'blocked_by' "$CLAIM_SH" ); then
    pass "D4 / AT-372-7: claim.sh header docstring describes native dependency mechanism"
else
    fail "D4 / AT-372-7: claim.sh header docstring still describes body-text 'Depends on' line"
fi

# ==============================================================================
# Assertion 8: D4 / AT-372-7: AGENTS.md claimable definition updated
# ==============================================================================
banner "D4 / AT-372-7: AGENTS.md claimable definition describes native mechanism"
claimable_line="$(grep -n 'Claimable:' "$AGENTS_MD" | head -1 || true)"
if printf '%s' "$claimable_line" | grep -qiE '(blocked_by|native dependenc)' && \
   ! printf '%s' "$claimable_line" | grep -q 'issue named in its "Depends on" line'; then
    pass "D4 / AT-372-7: AGENTS.md claimable definition specifies native dependencies"
else
    fail "D4 / AT-372-7: AGENTS.md claimable definition still references 'Depends on' line"
fi

# ==============================================================================
# Assertion 9: D5 / AT-372-8: .claude/commands/idea.md documents two-command native linking
# ==============================================================================
banner "D5 / AT-372-8: idea.md documents two-command native-linking sequence"
if grep -Fq 'dependencies/blocked_by' "$IDEA_MD" && \
   grep -Fq 'issue_id=' "$IDEA_MD"; then
    pass "D5 / AT-372-8: idea.md documents two-command native linking sequence"
else
    fail "D5 / AT-372-8: idea.md missing two-command native linking sequence"
fi

# ==============================================================================
# Assertion 10: D5 / AT-372-8: .claude/commands/bug.md documents two-command native linking
# ==============================================================================
banner "D5 / AT-372-8: bug.md documents two-command native-linking sequence"
if grep -Fq 'dependencies/blocked_by' "$BUG_MD" && \
   grep -Fq 'issue_id=' "$BUG_MD"; then
    pass "D5 / AT-372-8: bug.md documents two-command native linking sequence"
else
    fail "D5 / AT-372-8: bug.md missing two-command native linking sequence"
fi

# ==============================================================================
# Assertion 11: D6 / AT-372-6: claim_test.sh drops body-text case and adds native cases
# ==============================================================================
banner "D6 / AT-372-6: claim_test.sh updated"
if ! grep -Fq 'Depends on #101, #106 (land the docs first)' "$CLAIM_TEST_SH" && \
   grep -Fq 'dependencies/blocked_by' "$CLAIM_TEST_SH"; then
    pass "D6 / AT-372-6: claim_test.sh drops body-text test and contains native dependency tests"
else
    fail "D6 / AT-372-6: claim_test.sh still contains old body-text dependency test or lacks native cases"
fi

# ==============================================================================
# Assertion 12: D8 / AT-372-10: docs/SPEC.md documents native dependency enforcement
# ==============================================================================
banner "D8 / AT-372-10: docs/SPEC.md living spec documentation"
if grep -qiE '(blocked_by|issue_dependencies_summary)' "$SPEC_MD"; then
    pass "D8 / AT-372-10: docs/SPEC.md contains native dependency enforcement specification"
else
    fail "D8 / AT-372-10: docs/SPEC.md missing native dependency enforcement documentation"
fi

# ==============================================================================
# Summary
# ==============================================================================
banner "Contract Test Summary"
echo "Total assertions: $TOTAL"
echo "Passed:           $PASSED"
echo "Failed:           $FAILURES"

if [ "$FAILURES" -gt 0 ]; then
    exit 1
fi
exit 0
