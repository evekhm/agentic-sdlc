#!/usr/bin/env bash
# Contract tests for excluding withdrawn findings from merge gate dispute check (#508).
# Cites Decisions D1, D2, D3, D4, D5, D6 and Acceptance Tests AT-508-1 through AT-508-9.
#
# Every assertion cites its Decision ID and Acceptance Test ID.
# Hermetic: tests run locally without network access.
# Under the baseline tree before Odyssey's implementation, all assertions
# must FAIL (red) cleanly with exit code 1, proving behavior is not smuggled.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
GATE="$REPO/scripts/ci/merge_gate.sh"
TEST_SUITE="$REPO/scripts/ci/tests/merge_gate_test.sh"
SPEC_MD="$REPO/docs/SPEC.md"

TOTAL=0
PASSED=0
FAILURES=0

# Source the hermetic test harness from merge_gate_test.sh (up to MG-1 banner)
source <(sed -e "s|^REPO=.*|REPO=\"$REPO\"|" -e '/^# ---*$/q' "$TEST_SUITE")

# Redefine pass and fail after source to count assertions without exiting
set +e
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

# Run helper that captures output without auto-incrementing pass counter
run_gate() {
    local name="$1"; shift
    local rc=0
    OUT="$(bash "$GATE" "$@" 2>&1)"
    rc=$?
    if [ "$rc" -ne 0 ]; then
        printf '%s\n' "$OUT" >&2
        fail "$name (exit $rc)"
        return 1
    fi
    return 0
}

# ==============================================================================
# Assertion 1: D1 / AT-508-1: merge_gate.sh:312 excludes withdrawn status from DISPUTED
# ==============================================================================
banner "D1 / AT-508-1: merge_gate.sh:312 excludes withdrawn status from DISPUTED"
if grep -Eq 'DISPUTED=.*\$3 != "withdrawn" && \$4 == "dispute"' "$GATE"; then
    pass "D1 / AT-508-1: merge_gate.sh:312 filters out withdrawn findings from DISPUTED"
else
    fail "D1 / AT-508-1: merge_gate.sh:312 does not filter out withdrawn findings from DISPUTED"
fi

# ==============================================================================
# Assertion 2: D1, D4 / AT-508-2: withdrawn:dispute passes conjunct (5)
# ==============================================================================
banner "D1, D4 / AT-508-2: withdrawn:dispute passes conjunct (5)"
mk_green
comments_fixture 123 "$(comment "$MERGER" "$(consensus_ledger 123 "$H" "$H" R1-1:normal:withdrawn:dispute)" 2026-01-04T00:00:00Z 800)"
run_gate "evaluating PR with withdrawn:dispute" 123
if grep -qF "conjunct (5): true" <<<"$OUT"; then
    pass "D1, D4 / AT-508-2: conjunct (5) reports true when ledger carries withdrawn:dispute"
else
    fail "D1, D4 / AT-508-2: conjunct (5) failed on withdrawn:dispute"
fi

# ==============================================================================
# Assertion 3: D2, D4 / AT-508-5: Atlas carry-forward succeeds with withdrawn:dispute (D7 (iv))
# ==============================================================================
banner "D2, D4 / AT-508-5: Atlas carry-forward succeeds with withdrawn:dispute (D7 (iv))"
mk_green
comments_fixture 123 "$(comment "$MERGER" "$(consensus_ledger 123 "$H" "$H0" R1-1:normal:withdrawn:dispute)" 2026-01-04T00:00:00Z 803)"
run_gate "evaluating carry-forward with withdrawn:dispute" 123
if grep -qF "conjunct (3): true" <<<"$OUT" && grep -Eq "^gh pr merge 123 --merge --match-head-commit $H\$" "$WRITES"; then
    pass "D2, D4 / AT-508-5: Atlas carries forward under D7 condition (iv) with withdrawn:dispute"
else
    fail "D2, D4 / AT-508-5: Atlas carry-forward failed on withdrawn:dispute"
fi

# ==============================================================================
# Assertion 4: D2, D4 / AT-508-6: review:3 with withdrawn:dispute does not escalate dispute-at-cap
# ==============================================================================
banner "D2, D4 / AT-508-6: review:3 with withdrawn:dispute does not escalate dispute-at-cap"
mk_green; PR_LABELS='["review:3"]'; pr_fixture 123
comments_fixture 123 "$(comment "$MERGER" "$(consensus_ledger 123 "$H" "$H" R1-1:normal:withdrawn:dispute)" 2026-01-04T00:00:00Z 815)"
run_gate "evaluating review:3 with withdrawn:dispute" 123
if ! grep -q "refusal:dispute-at-cap" "$WRITES" && ! grep -q "escalation:status:implementing:dispute-at-cap" "$WRITES"; then
    pass "D2, D4 / AT-508-6: review:3 with withdrawn:dispute does not escalate dispute-at-cap"
else
    fail "D2, D4 / AT-508-6: review:3 with withdrawn:dispute escalated dispute-at-cap"
fi

# ==============================================================================
# Assertion 5: D1, D3, D4 / AT-508-4: merge_gate_test.sh covers fixed:dispute
# ==============================================================================
banner "D1, D3, D4 / AT-508-4: merge_gate_test.sh covers fixed:dispute"
if grep -qF "fixed:dispute" "$TEST_SUITE"; then
    pass "D1, D3, D4 / AT-508-4: merge_gate_test.sh contains test cases for fixed:dispute"
else
    fail "D1, D3, D4 / AT-508-4: merge_gate_test.sh missing test cases for fixed:dispute"
fi

# ==============================================================================
# Assertion 6: D4 / AT-508-2, AT-508-5, AT-508-6: merge_gate_test.sh covers withdrawn:dispute
# ==============================================================================
banner "D4 / AT-508-2, AT-508-5, AT-508-6: merge_gate_test.sh covers withdrawn:dispute"
if grep -qF "withdrawn:dispute" "$TEST_SUITE"; then
    pass "D4 / AT-508-2, AT-508-5, AT-508-6: merge_gate_test.sh contains test cases for withdrawn:dispute"
else
    fail "D4 / AT-508-2, AT-508-5, AT-508-6: merge_gate_test.sh missing test cases for withdrawn:dispute"
fi

# ==============================================================================
# Assertion 7: D5 / AT-508-8: docs/SPEC.md living spec documentation
# ==============================================================================
banner "D5 / AT-508-8: docs/SPEC.md living spec documentation"
if grep -qiE 'withdrawn.*dispute|dispute.*withdrawn' "$SPEC_MD"; then
    pass "D5 / AT-508-8: docs/SPEC.md documents exclusion of withdrawn findings from dispute check"
else
    fail "D5 / AT-508-8: docs/SPEC.md missing living spec update for withdrawn findings"
fi

# ==============================================================================
# Summary
# ==============================================================================
banner "Contract Test Summary"
echo "Total assertions: $TOTAL"
echo "Passed:           $PASSED"
echo "Failed:           $FAILURES"

if [ "$FAILURES" -gt 0 ]; then
    echo "Total failures: $FAILURES (EXPECTED RED at build rung)" >&2
    exit 1
fi

echo "ALL TESTS PASSED"
exit 0
