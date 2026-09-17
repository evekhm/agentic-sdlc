#!/usr/bin/env bash
# Contract tests for Test Suite Verdict Integrity (#405).
# Cites Decisions D1, D2, D3, D4, D5, D6, D7, D8 and Acceptance Tests AT-405-1 through AT-405-11.
# Spec: intent/405-nothing-proves-a-test/spec.md (Approved)
#
# Every assertion cites its Decision ID and Acceptance Test ID.
# Hermetic: tests run locally without network access.
# Under the baseline tree before Odyssey's implementation, all assertions
# must FAIL (red) cleanly with exit code 1, proving behavior is not smuggled.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
HARNESS_TEST="$REPO/scripts/ops/tests/harness_test.sh"
PLACEMENT_TEST="$REPO/scripts/ops/tests/placement_test.sh"
SUITE_INTEGRITY_TEST="$REPO/scripts/ops/tests/suite_integrity_test.sh"
CI_GATES="$REPO/.github/workflows/ci-gates.yml"
SPEC_MD="$REPO/docs/SPEC.md"
AGENTS_MD="$REPO/AGENTS.md"

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

# ==============================================================================
# Assertion 1: D3 / AT-405-2: harness_test.sh entry sanitization (unset seat variables)
# ==============================================================================
banner "D3 / AT-405-2: harness_test.sh unsets CLAUDE_SEAT and AGENTIC_SEAT at startup"
if grep -qE 'unset[[:space:]]+.*CLAUDE_SEAT' "$HARNESS_TEST" && grep -qE 'unset[[:space:]]+.*AGENTIC_SEAT' "$HARNESS_TEST"; then
    pass "D3 / AT-405-2: harness_test.sh unsets CLAUDE_SEAT and AGENTIC_SEAT at startup"
else
    fail "D3 / AT-405-2: harness_test.sh does not unset CLAUDE_SEAT and AGENTIC_SEAT at startup"
fi

# ==============================================================================
# Assertion 2: D3 / AT-405-2: harness_test.sh hermeticity against ambient seat variables
# ==============================================================================
banner "D3 / AT-405-2: harness_test.sh passes when run with ambient seat variables"
if CLAUDE_SEAT=polluter-seat AGENTIC_SEAT=polluter-seat bash "$HARNESS_TEST" >/dev/null 2>&1; then
    pass "D3 / AT-405-2: harness_test.sh exits 0 under hostile ambient seat variables"
else
    fail "D3 / AT-405-2: harness_test.sh fails under hostile ambient seat variables (pollution leaks into statusline)"
fi

# ==============================================================================
# Assertion 3: D3 / AT-405-3: placement_test.sh entry sanitization (unset WORK_MAX_USD)
# ==============================================================================
banner "D3 / AT-405-3: placement_test.sh unsets WORK_MAX_USD at startup"
if grep -qE 'unset[[:space:]]+.*WORK_MAX_USD' "$PLACEMENT_TEST"; then
    pass "D3 / AT-405-3: placement_test.sh unsets WORK_MAX_USD at startup"
else
    fail "D3 / AT-405-3: placement_test.sh does not unset WORK_MAX_USD at startup"
fi

# ==============================================================================
# Assertion 4: D4 / AT-405-3: placement_test.sh mutant invocation isolates WORK_MAX_USD
# ==============================================================================
banner "D4 / AT-405-3: placement_test.sh mutant invocation executes with env -u WORK_MAX_USD"
if grep -q "env -u WORK_MAX_USD" "$PLACEMENT_TEST"; then
    pass "D4 / AT-405-3: placement_test.sh executes mutant invocation with env -u WORK_MAX_USD"
else
    fail "D4 / AT-405-3: placement_test.sh does not isolate mutant invocation with env -u WORK_MAX_USD"
fi

# ==============================================================================
# Assertion 5: D3, D4 / AT-405-3: placement_test.sh hermeticity against ambient budget ceiling
# ==============================================================================
banner "D3, D4 / AT-405-3: placement_test.sh passes when run with ambient WORK_MAX_USD"
if WORK_MAX_USD=9999.00 bash "$PLACEMENT_TEST" >/dev/null 2>&1; then
    pass "D3, D4 / AT-405-3: placement_test.sh exits 0 under hostile WORK_MAX_USD"
else
    fail "D3, D4 / AT-405-3: placement_test.sh fails under hostile WORK_MAX_USD (ambient budget overrides adapter default)"
fi

# ==============================================================================
# Assertion 6: D5 / AT-405-4, AT-405-5, AT-405-6: suite_integrity_test.sh exists and is executable
# ==============================================================================
banner "D5 / AT-405-4: suite_integrity_test.sh exists and is executable"
if [ -x "$SUITE_INTEGRITY_TEST" ]; then
    pass "D5 / AT-405-4: scripts/ops/tests/suite_integrity_test.sh exists and is executable"
else
    fail "D5 / AT-405-4: scripts/ops/tests/suite_integrity_test.sh does not exist or is not executable"
fi

# ==============================================================================
# Assertion 7: D5 / AT-405-4: suite_integrity_test.sh executes Proof 1 (Null-Implementation Proof)
# ==============================================================================
banner "D5 / AT-405-4: suite_integrity_test.sh implements Proof 1 (Null-Implementation Proof)"
if [ -f "$SUITE_INTEGRITY_TEST" ] && grep -qi "proof 1" "$SUITE_INTEGRITY_TEST"; then
    pass "D5 / AT-405-4: suite_integrity_test.sh defines Proof 1 (Null-Implementation Proof)"
else
    fail "D5 / AT-405-4: suite_integrity_test.sh missing Proof 1 (Null-Implementation Proof)"
fi

# ==============================================================================
# Assertion 8: D5 / AT-405-5: suite_integrity_test.sh implements Proof 2 (Ambient-Environment Proof)
# ==============================================================================
banner "D5 / AT-405-5: suite_integrity_test.sh implements Proof 2 (Ambient-Environment Proof)"
if [ -f "$SUITE_INTEGRITY_TEST" ] && grep -qi "proof 2" "$SUITE_INTEGRITY_TEST"; then
    pass "D5 / AT-405-5: suite_integrity_test.sh defines Proof 2 (Ambient-Environment Proof)"
else
    fail "D5 / AT-405-5: suite_integrity_test.sh missing Proof 2 (Ambient-Environment Proof)"
fi

# ==============================================================================
# Assertion 9: D5 / AT-405-6: suite_integrity_test.sh implements Proof 3 (Static Audit)
# ==============================================================================
banner "D5 / AT-405-6: suite_integrity_test.sh implements Proof 3 (Static Audit)"
if [ -f "$SUITE_INTEGRITY_TEST" ] && grep -qi "proof 3" "$SUITE_INTEGRITY_TEST"; then
    pass "D5 / AT-405-6: suite_integrity_test.sh defines Proof 3 (Static Audit)"
else
    fail "D5 / AT-405-6: suite_integrity_test.sh missing Proof 3 (Static Audit)"
fi

# ==============================================================================
# Assertion 10: D6 / AT-405-7: CI gate registration in ci-gates.yml
# ==============================================================================
banner "D6 / AT-405-7: suite_integrity_test.sh registered in .github/workflows/ci-gates.yml"
if grep -q "bash scripts/ops/tests/suite_integrity_test.sh" "$CI_GATES"; then
    pass "D6 / AT-405-7: ci-gates.yml registers suite_integrity_test.sh in execution job"
else
    fail "D6 / AT-405-7: ci-gates.yml missing suite_integrity_test.sh registration in execution job"
fi

# ==============================================================================
# Assertion 11: D7 / AT-405-8: docs/SPEC.md living spec documentation
# ==============================================================================
banner "D7 / AT-405-8: docs/SPEC.md living spec documentation (testing.suite_integrity)"
if grep -q "### testing.suite_integrity" "$SPEC_MD"; then
    pass "D7 / AT-405-8: docs/SPEC.md documents testing.suite_integrity capability"
else
    fail "D7 / AT-405-8: docs/SPEC.md missing ### testing.suite_integrity capability section"
fi

# ==============================================================================
# Assertion 12: D7 / AT-405-9: AGENTS.md contributor standards (Contract test standards)
# ==============================================================================
banner "D7 / AT-405-9: AGENTS.md codifies Contract test standards"
if grep -q "## Contract test standards" "$AGENTS_MD"; then
    pass "D7 / AT-405-9: AGENTS.md includes ## Contract test standards section"
else
    fail "D7 / AT-405-9: AGENTS.md missing ## Contract test standards section"
fi

# ==============================================================================
# Summary
# ==============================================================================
banner "Contract Test Summary"
echo "Total assertions: $TOTAL"
echo "Passed:           $PASSED"
echo "Failed:           $FAILURES"

if [ "$FAILURES" -gt 0 ]; then
    echo "Total contract test failures: $FAILURES (EXPECTED RED at build rung)" >&2
    exit 1
fi

echo "ALL TESTS PASSED"
exit 0
