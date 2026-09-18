#!/usr/bin/env bash
# Contract tests for Auto-Resolution of Transient Conjunct (2) Merge Gate Declines (#514).
# Spec: intent/514-merge-gate-never-re/spec.md (Approved)
# Cites Decisions D1, D2, D3, D4, D5, D6, D7 and Acceptance Tests AT-514-1 through AT-514-9.
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
CHANGELOG_MD="$REPO/CHANGELOG.md"

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

# Run helper that captures output
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

# Patch gh stub to support per-attempt checks fixture ($FX/mergestate-$pr.checks.$idx)
sed -i 's|if \[ -f "\$FX/mergestate-\$pr\.checks" \]; then|c_file="\$FX/mergestate-\$pr.checks.\$idx"; [ -f "\$c_file" ] \|\| c_file="\$FX/mergestate-\$pr.checks"; if [ -f "\$c_file" ]; then|g' "$WORK/bin/gh"
sed -i 's|done < "\$FX/mergestate-\$pr\.checks"|done < "\$c_file"|g' "$WORK/bin/gh"

mergestate_checks_attempt() { # <pr> <attempt-index> <row>...
    local pr="$1" idx="$2"; shift 2
    printf '%s\n' "$@" > "$FX/mergestate-$pr.checks.$idx"
}

# ==============================================================================
# Assertion 1: D1, D4 / AT-514-1, AT-514-5: Configurable timeout bounds and polling interval
# ==============================================================================
banner "D1, D4 / AT-514-1, AT-514-5: merge_gate.sh defines MERGE_GATE_TRANSIENT_TIMEOUT and MERGE_GATE_TRANSIENT_POLL_INTERVAL"
if grep -Eq 'MERGE_GATE_TRANSIENT_TIMEOUT' "$GATE" && grep -Eq 'MERGE_GATE_TRANSIENT_POLL_INTERVAL' "$GATE"; then
    pass "D1, D4 / AT-514-1, AT-514-5: merge_gate.sh defines configurable transient timeout and poll interval"
else
    fail "D1, D4 / AT-514-1, AT-514-5: merge_gate.sh missing MERGE_GATE_TRANSIENT_TIMEOUT or MERGE_GATE_TRANSIENT_POLL_INTERVAL"
fi

# ==============================================================================
# Assertion 2: D1 / AT-514-1: Transient in-flight check polling and eventual merge resolution
# ==============================================================================
banner "D1 / AT-514-1: Transient in-flight check polls until SUCCESS and merges"
mk_green
mergestate_checks_attempt 123 0 \
    "$(row check merge-gate '' 999)" \
    "$(row check 'execution — bindings' IN_PROGRESS 1001)" \
    "$(row status 'argus via gh-actions' SUCCESS '')"
mergestate_checks_attempt 123 1 \
    "$(row check merge-gate '' 999)" \
    "$(row check 'execution — bindings' SUCCESS 1001)" \
    "$(row status 'argus via gh-actions' SUCCESS '')"

MERGE_GATE_TRANSIENT_POLL_INTERVAL=0 MERGE_GATE_TRANSIENT_TIMEOUT=10 run_gate "evaluating PR with transient in-flight check" 123
if grep -qF "merged #123 at $H" <<<"$OUT" && grep -Eq "^gh pr merge 123 --merge --match-head-commit $H\$" "$WRITES"; then
    pass "D1 / AT-514-1: in-flight check polled to SUCCESS and PR was merged"
else
    fail "D1 / AT-514-1: in-flight check did not poll to resolution or merge PR"
fi

# ==============================================================================
# Assertion 3: D2 / AT-514-2: Precondition gating prevents polling when other conjuncts fail
# ==============================================================================
banner "D2 / AT-514-2: Precondition gating guards transient check polling"
if grep -Eq 'OTHER_CONJUNCTS.*=.*1|PRECONDITIONS_OK|precondition.*poll' "$GATE"; then
    pass "D2 / AT-514-2: merge_gate.sh explicitly guards transient polling with precondition check"
else
    fail "D2 / AT-514-2: merge_gate.sh does not guard transient polling with non-conjunct-(2) precondition checks"
fi

# ==============================================================================
# Assertion 4: D3 / AT-514-3: Immediate abort on terminal check failure
# ==============================================================================
banner "D3 / AT-514-3: Immediate abort on terminal check failure"
if grep -Eq 'FAILURE\|CANCELLED\|TIMED_OUT\|ACTION_REQUIRED\|STALE\|STARTUP_FAILURE' "$GATE"; then
    pass "D3 / AT-514-3: merge_gate.sh explicitly aborts polling on terminal check failure states"
else
    fail "D3 / AT-514-3: merge_gate.sh missing immediate abort logic for terminal failure states"
fi

# ==============================================================================
# Assertion 5: D4, D5 / AT-514-4, AT-514-6: In-flight check timeout diagnostic categorisation
# ==============================================================================
banner "D4, D5 / AT-514-4, AT-514-6: In-flight check timeout diagnostic categorisation"
mk_green
mergestate_checks 123 \
    "$(row check merge-gate '' 999)" \
    "$(row check 'execution — bindings' IN_PROGRESS 1001)" \
    "$(row status 'argus via gh-actions' SUCCESS '')"

MERGE_GATE_TRANSIENT_POLL_INTERVAL=0 MERGE_GATE_TRANSIENT_TIMEOUT=0 run_gate "evaluating PR with timed-out in-flight check" 123
if grep -qE "check\(s\) in flight timed out after" <<<"$OUT"; then
    pass "D4, D5 / AT-514-4, AT-514-6: gate emits explicit timeout diagnostic when in-flight checks time out"
else
    fail "D4, D5 / AT-514-4, AT-514-6: gate did not emit 'check(s) in flight timed out after' diagnostic"
fi

# ==============================================================================
# Assertion 6: D1, D2, D3, D4 / AT-514-1..6: merge_gate_test.sh regression suite coverage
# ==============================================================================
banner "D1, D2, D3, D4 / AT-514-1..6: merge_gate_test.sh covers transient polling and timeout"
if grep -qF "MERGE_GATE_TRANSIENT_TIMEOUT" "$TEST_SUITE"; then
    pass "D1, D2, D3, D4 / AT-514-1..6: merge_gate_test.sh includes transient polling test scenarios"
else
    fail "D1, D2, D3, D4 / AT-514-1..6: merge_gate_test.sh missing test cases for MERGE_GATE_TRANSIENT_TIMEOUT"
fi

# ==============================================================================
# Assertion 7: D6 / AT-514-7: docs/SPEC.md living spec documentation
# ==============================================================================
banner "D6 / AT-514-7: docs/SPEC.md living spec documentation for transient polling"
if grep -qF "MERGE_GATE_TRANSIENT_TIMEOUT" "$SPEC_MD" && grep -qiE "in-gate.*polling|transient.*poll" "$SPEC_MD"; then
    pass "D6 / AT-514-7: docs/SPEC.md documents in-gate bounded polling loop for conjunct (2)"
else
    fail "D6 / AT-514-7: docs/SPEC.md missing living spec update for conjunct (2) transient polling loop"
fi

# ==============================================================================
# Assertion 8: D7 / AT-514-9: CHANGELOG.md release notes entry
# ==============================================================================
banner "D7 / AT-514-9: CHANGELOG.md release notes entry"
if grep -Eq '514|transient conjunct \(2\)' "$CHANGELOG_MD"; then
    pass "D7 / AT-514-9: CHANGELOG.md records auto-resolution of transient conjunct (2) declines"
else
    fail "D7 / AT-514-9: CHANGELOG.md missing entry for issue #514"
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
