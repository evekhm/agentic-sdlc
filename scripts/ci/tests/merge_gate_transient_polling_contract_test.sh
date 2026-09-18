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

TOTAL=8
PASSED=0
FAILURES=0

# Source the hermetic test harness from merge_gate_test.sh up to the first scenario (MG-1)
source <(sed -e "s|^REPO=.*|REPO=\"$REPO\"|" -e '/^banner "MG-1/,$d' "$TEST_SUITE")
type mk_green >/dev/null 2>&1 || { echo "ERROR: failed to source test harness from merge_gate_test.sh" >&2; exit 2; }

set +e
banner() { printf '\n=== %s ===\n' "$*"; }

pass() {
    echo "PASS: $*"
    PASSED=$((PASSED + 1))
}

fail() {
    echo "FAIL: $*" >&2
    FAILURES=$((FAILURES + 1))
}

# Run helper that captures output without altering assertion counter
run_gate() {
    local rc=0
    MERGE_STATE_RETRY_SLEEP=0 OUT="$(bash "$GATE" "$@" 2>&1)"
    rc=$?
    return "$rc"
}

# Patch gh stub to support per-attempt checks fixture ($FX/mergestate-$pr.checks.$n or $idx)
sed -i 's|if \[ -f "\$FX/mergestate-\$pr\.checks" \]; then|c_file="\$FX/mergestate-\$pr.checks.\$n"; [ -f "\$c_file" ] \|\| c_file="\$FX/mergestate-\$pr.checks.\$idx"; [ -f "\$c_file" ] \|\| c_file="\$FX/mergestate-\$pr.checks"; if [ -f "\$c_file" ]; then|g' "$WORK/bin/gh"
sed -i 's|done < "\$FX/mergestate-\$pr\.checks"|done < "\$c_file"|g' "$WORK/bin/gh"

mergestate_checks_attempt() { # <pr> <attempt-index> <row>...
    local pr="$1" idx="$2"; shift 2
    printf '%s\n' "$@" > "$FX/mergestate-$pr.checks.$idx"
    if [ -f "$FX/mergestate-$pr.state" ]; then
        local last_state
        last_state="$(tail -n 1 "$FX/mergestate-$pr.state")"
        while [ "$(wc -l < "$FX/mergestate-$pr.state")" -le "$idx" ]; do
            printf '%s\n' "$last_state" >> "$FX/mergestate-$pr.state"
        done
    fi
}

# ==============================================================================
# Assertion 1: D1, D4 / AT-514-1, AT-514-5: Configurable timeout bounds and polling interval
# ==============================================================================
banner "D1, D4 / AT-514-1, AT-514-5: Configurable timeout bounds and zero-delay testing"
mk_green
mergestate_checks 123 \
    "$(row check merge-gate '' 999)" \
    "$(row check 'execution — bindings' IN_PROGRESS 1001)" \
    "$(row status 'argus via gh-actions' SUCCESS '')"

MERGE_GATE_TRANSIENT_POLL_INTERVAL=0 MERGE_GATE_TRANSIENT_TIMEOUT=0 run_gate 123
out_zero="$OUT"

if grep -qF "MERGE_GATE_TRANSIENT_TIMEOUT" "$GATE" && \
   grep -qF "MERGE_GATE_TRANSIENT_POLL_INTERVAL" "$GATE" && \
   grep -qE "check\(s\) in flight timed out after" <<<"$out_zero"; then
    pass "D1, D4 / AT-514-1, AT-514-5: configurable transient timeout and poll interval honored with zero delay"
else
    fail "D1, D4 / AT-514-1, AT-514-5: merge_gate.sh missing configurable transient timeout bounds or zero-delay override"
fi

# ==============================================================================
# Assertion 2: D1 / AT-514-1: Transient in-flight check and UNKNOWN merge state polling to merge
# ==============================================================================
banner "D1 / AT-514-1: Transient in-flight check and UNKNOWN merge state poll to resolution and merge"
# Subcase A: Transient in-flight check transitions to SUCCESS
mk_green
mergestate_fixture 123 CLEAN CLEAN
mergestate_checks_attempt 123 0 \
    "$(row check merge-gate '' 999)" \
    "$(row check 'execution — bindings' IN_PROGRESS 1001)" \
    "$(row status 'argus via gh-actions' SUCCESS '')"
mergestate_checks_attempt 123 1 \
    "$(row check merge-gate '' 999)" \
    "$(row check 'execution — bindings' SUCCESS 1001)" \
    "$(row status 'argus via gh-actions' SUCCESS '')"

MERGE_GATE_TRANSIENT_POLL_INTERVAL=0 MERGE_GATE_TRANSIENT_TIMEOUT=10 run_gate 123
out_inflight="$OUT"
writes_inflight="$(cat "$WRITES")"
cnt_inflight="$(cat "$FX/mergestate-123.count" 2>/dev/null || echo 0)"

# Subcase B (R1-4): UNKNOWN mergeStateStatus transitions to CLEAN
mk_green
mergestate_fixture 123 UNKNOWN CLEAN
mergestate_checks 123 "${GREEN_CHECKS[@]}"
MERGE_GATE_TRANSIENT_POLL_INTERVAL=0 MERGE_GATE_TRANSIENT_TIMEOUT=10 run_gate 123
out_unknown="$OUT"
writes_unknown="$(cat "$WRITES")"

merged_inflight=0
[ "$cnt_inflight" -ge 2 ] && grep -qF "merged #123 at $H" <<<"$out_inflight" && grep -Eq "^gh pr merge 123 --merge --match-head-commit $H\$" <<<"$writes_inflight" && merged_inflight=1

merged_unknown=0
grep -qF "merged #123 at $H" <<<"$out_unknown" && grep -Eq "^gh pr merge 123 --merge --match-head-commit $H\$" <<<"$writes_unknown" && merged_unknown=1

if [ "$merged_inflight" -eq 1 ] && [ "$merged_unknown" -eq 1 ]; then
    pass "D1 / AT-514-1: in-flight checks and UNKNOWN merge state poll to resolution and merge PR"
else
    fail "D1 / AT-514-1: in-flight checks or UNKNOWN merge state did not poll to resolution or merge PR"
fi

# ==============================================================================
# Assertion 3: D2 / AT-514-2: Precondition gating guards transient check polling
# ==============================================================================
banner "D2 / AT-514-2: Precondition gating guards transient check polling"
# Positive control: with preconditions green, transient check triggers polling (>= 2 calls)
mk_green
mergestate_fixture 123 CLEAN CLEAN
mergestate_checks_attempt 123 0 \
    "$(row check merge-gate '' 999)" \
    "$(row check 'execution — bindings' IN_PROGRESS 1001)" \
    "$(row status 'argus via gh-actions' SUCCESS '')"
mergestate_checks_attempt 123 1 \
    "$(row check merge-gate '' 999)" \
    "$(row check 'execution — bindings' SUCCESS 1001)" \
    "$(row status 'argus via gh-actions' SUCCESS '')"
MERGE_GATE_TRANSIENT_POLL_INTERVAL=0 MERGE_GATE_TRANSIENT_TIMEOUT=10 run_gate 123
cnt_green="$(cat "$FX/mergestate-123.count" 2>/dev/null || echo 0)"

# Negative control: when conjunct (4) fails (open blocking finding), gate must NOT poll (count == 1)
mk_green
comments_fixture 123 "$(comment "$MERGER" "$(consensus_ledger 123 "$H" "$H" R1-1:high:open:none R1-2:normal:open:none)" 2026-01-04T00:00:00Z 800)"
mergestate_fixture 123 CLEAN CLEAN
mergestate_checks_attempt 123 0 \
    "$(row check merge-gate '' 999)" \
    "$(row check 'execution — bindings' IN_PROGRESS 1001)" \
    "$(row status 'argus via gh-actions' SUCCESS '')"
mergestate_checks_attempt 123 1 \
    "$(row check merge-gate '' 999)" \
    "$(row check 'execution — bindings' SUCCESS 1001)" \
    "$(row status 'argus via gh-actions' SUCCESS '')"
MERGE_GATE_TRANSIENT_POLL_INTERVAL=0 MERGE_GATE_TRANSIENT_TIMEOUT=10 run_gate 123
cnt_gated="$(cat "$FX/mergestate-123.count" 2>/dev/null || echo 0)"
writes_gated="$(cat "$WRITES")"

if [ "$cnt_green" -ge 2 ] && [ "$cnt_gated" -le 1 ] && ! grep -Eq "^gh pr merge" <<<"$writes_gated"; then
    pass "D2 / AT-514-2: gate polls when preconditions hold, but declines immediately without polling when preconditions fail"
else
    fail "D2 / AT-514-2: gate did not enforce precondition gating (green calls: $cnt_green, gated calls: $cnt_gated)"
fi

# ==============================================================================
# Assertion 4: D3 / AT-514-3: Immediate abort on terminal check failure
# ==============================================================================
banner "D3 / AT-514-3: Immediate abort on terminal check failure"
# Positive control: with transient check, gate polls (>= 2 calls)
mk_green
mergestate_fixture 123 CLEAN CLEAN
mergestate_checks_attempt 123 0 \
    "$(row check merge-gate '' 999)" \
    "$(row check 'execution — bindings' IN_PROGRESS 1001)" \
    "$(row status 'argus via gh-actions' SUCCESS '')"
mergestate_checks_attempt 123 1 \
    "$(row check merge-gate '' 999)" \
    "$(row check 'execution — bindings' SUCCESS 1001)" \
    "$(row status 'argus via gh-actions' SUCCESS '')"
MERGE_GATE_TRANSIENT_POLL_INTERVAL=0 MERGE_GATE_TRANSIENT_TIMEOUT=10 run_gate 123
cnt_green="$(cat "$FX/mergestate-123.count" 2>/dev/null || echo 0)"

# Fail-fast test: attempt 0 has one FAILURE check and one IN_PROGRESS check.
# Attempt 1 would have had SUCCESS, but gate must abort immediately on attempt 0 (count <= 1)
mk_green
mergestate_fixture 123 CLEAN CLEAN
mergestate_checks_attempt 123 0 \
    "$(row check merge-gate '' 999)" \
    "$(row check 'execution — bindings' IN_PROGRESS 1001)" \
    "$(row check 'test-suite' FAILURE 1002)" \
    "$(row status 'argus via gh-actions' SUCCESS '')"
mergestate_checks_attempt 123 1 \
    "$(row check merge-gate '' 999)" \
    "$(row check 'execution — bindings' SUCCESS 1001)" \
    "$(row check 'test-suite' SUCCESS 1002)" \
    "$(row status 'argus via gh-actions' SUCCESS '')"
MERGE_GATE_TRANSIENT_POLL_INTERVAL=0 MERGE_GATE_TRANSIENT_TIMEOUT=10 run_gate 123
cnt_terminal="$(cat "$FX/mergestate-123.count" 2>/dev/null || echo 0)"
out_terminal="$OUT"
writes_terminal="$(cat "$WRITES")"

if [ "$cnt_green" -ge 2 ] && [ "$cnt_terminal" -le 1 ] && \
   grep -qE "check\(s\) not success:.*(test-suite=FAILURE|FAILURE)" <<<"$out_terminal" && \
   ! grep -Eq "^gh pr merge" <<<"$writes_terminal"; then
    pass "D3 / AT-514-3: gate aborts polling immediately on terminal check failure without waiting"
else
    fail "D3 / AT-514-3: gate did not immediately abort polling on terminal failure (green calls: $cnt_green, terminal calls: $cnt_terminal)"
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

MERGE_GATE_TRANSIENT_POLL_INTERVAL=0 MERGE_GATE_TRANSIENT_TIMEOUT=0 run_gate 123
if grep -qE "check\(s\) in flight timed out after" <<<"$OUT" && \
   grep -qF "execution — bindings=IN_PROGRESS" <<<"$OUT"; then
    pass "D4, D5 / AT-514-4, AT-514-6: gate emits explicit timeout diagnostic when in-flight checks time out"
else
    fail "D4, D5 / AT-514-4, AT-514-6: gate did not emit 'check(s) in flight timed out after' diagnostic"
fi

# ==============================================================================
# Assertion 6: D1, D2, D3, D4 / AT-514-1..6: merge_gate_test.sh regression suite coverage
# ==============================================================================
banner "D1, D2, D3, D4 / AT-514-1..6: merge_gate_test.sh covers transient polling and timeout"
if grep -qF "MG-2c" "$TEST_SUITE" && \
   grep -qF "MG-2d" "$TEST_SUITE" && \
   grep -qF "MG-2e" "$TEST_SUITE" && \
   grep -qF "MG-2f" "$TEST_SUITE" && \
   grep -qF "MERGE_GATE_TRANSIENT_TIMEOUT" "$TEST_SUITE"; then
    pass "D1, D2, D3, D4 / AT-514-1..6: merge_gate_test.sh defines regression scenarios MG-2c..MG-2f"
else
    fail "D1, D2, D3, D4 / AT-514-1..6: merge_gate_test.sh missing required regression scenarios MG-2c..MG-2f"
fi

# ==============================================================================
# Assertion 7: D6 / AT-514-7: docs/SPEC.md living spec documentation
# ==============================================================================
banner "D6 / AT-514-7: docs/SPEC.md living spec documentation for transient polling"
if grep -qF "MERGE_GATE_TRANSIENT_TIMEOUT" "$SPEC_MD" && \
   grep -qF "MERGE_GATE_TRANSIENT_POLL_INTERVAL" "$SPEC_MD" && \
   grep -qiE "in-gate.*polling|transient.*poll" "$SPEC_MD"; then
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
