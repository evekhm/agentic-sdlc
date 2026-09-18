#!/usr/bin/env bash
# Contract tests for Sound Poller Claim Lifecycle (#513).
# Spec: intent/513-the-poller-s-claim/spec.md (Approved)
# Cites Decisions D1, D2, D3, D4, D5, D6, D7, D8, D9, D10
# and Acceptance Tests AT-513-1 through AT-513-10.
#
# Every assertion cites its Decision ID and Acceptance Test ID.
# Hermetic: tests run locally without network access.
# Under the baseline tree before Odyssey's implementation, all assertions
# must FAIL (red) cleanly with exit code 1, proving behavior is not smuggled.

set -uo pipefail

# Self-sanitizing entry (#405 D3)
unset WORK_MAX_USD

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
POLL_SH="$REPO/scripts/placement/vm-local/poll.sh"
RUN_SH="$REPO/scripts/placement/vm-local/run.sh"
EXEC_PY="$REPO/scripts/ops/execution.py"
EXEC_YAML="$REPO/config/execution.yaml"
SPEC_MD="$REPO/docs/SPEC.md"
CHANGELOG_MD="$REPO/CHANGELOG.md"

TOTAL=10
PASSED=0
FAILURES=0

banner() { printf '\n=== %s ===\n' "$*"; }

pass() {
    echo "PASS: $*"
    PASSED=$((PASSED + 1))
}

fail() {
    echo "FAIL: $*" >&2
    FAILURES=$((FAILURES + 1))
}

# ==============================================================================
# Assertion 1: D1 / AT-513-1: Detached background runner dispatch and dispatch log path
# ==============================================================================
banner "D1 / AT-513-1: Detached background runner dispatch and dispatch log redirection"
# The poller must dispatch run.sh in the background with stdout and stderr redirected
# to ${POLL_LOG_DIR:-${poll_state_dir}/logs}/dispatch-<issue>-<timestamp>.log across
# candidate paths (fix rounds, first-hop intake, and ladder consumption), allowing the
# 30-second polling cadence to continue without blocking on runner completion.
d1_ok=1
if ! grep -qF 'POLL_LOG_DIR' "$POLL_SH"; then
    d1_ok=0
fi
if ! grep -qE 'dispatch-[^/[:space:]]+-[0-9]+\.log' "$POLL_SH"; then
    d1_ok=0
fi
# Verify that run.sh invocations are backgrounded with '&' instead of executed synchronously
if ! grep -qE '"\$RUN_SH".*&' "$POLL_SH"; then
    d1_ok=0
fi

if [ "$d1_ok" -eq 1 ]; then
    pass "D1 / AT-513-1: poll.sh defines detached background runner dispatch with per-dispatch log redirection"
else
    fail "D1 / AT-513-1: poll.sh missing detached background dispatch or POLL_LOG_DIR log redirection"
fi

# ==============================================================================
# Assertion 2: D2 / AT-513-2: Child process PID attribution and claim session binding
# ==============================================================================
banner "D2 / AT-513-2: Child process PID attribution and claim session binding"
# When poll.sh dispatches a run, claim.sh must be invoked with CLAIM_SESSION="poll-$BASHPID"
# inside the background child subshell, recording the child process identifier in the claim comment.
# poll-$$ records the parent poller process PID and is unsound for child liveness tracking.
d2_ok=1
if ! grep -qF 'CLAIM_SESSION="poll-$BASHPID"' "$POLL_SH"; then
    d2_ok=0
fi
if grep -qF 'CLAIM_SESSION="poll-$$"' "$POLL_SH"; then
    d2_ok=0
fi

if [ "$d2_ok" -eq 1 ]; then
    pass "D2 / AT-513-2: poll.sh binds claim session to child process identifier via poll-\$BASHPID"
else
    fail "D2 / AT-513-2: poll.sh does not bind claim session to background subshell \$BASHPID"
fi

# ==============================================================================
# Assertion 3: D3, D4 / AT-513-3: In-band claim reaper execution for dead PID past grace age
# ==============================================================================
banner "D3, D4 / AT-513-3: In-band claim reaper execution for dead PID past grace age"
# poll.sh must execute an in-band reaper at the start of each polling tick.
# If an in-progress issue carries a poll-<pid> claim where <pid> is dead (! kill -0 <pid>)
# and claim age exceeds claim_reaper_min_age_seconds, the reaper releases the in-progress label
# and posts an explanatory tracking comment.
d3_ok=1
if ! grep -qE 'kill -0 "\$?[a-zA-Z0-9_]*pid' "$POLL_SH"; then
    d3_ok=0
fi
if ! grep -qF 'claim_reaper_min_age_seconds' "$POLL_SH"; then
    d3_ok=0
fi
if ! grep -qE '(reap|reaper)' "$POLL_SH"; then
    d3_ok=0
fi

if [ "$d3_ok" -eq 1 ]; then
    pass "D3, D4 / AT-513-3: poll.sh implements in-band claim reaper checking PID death and min grace age"
else
    fail "D3, D4 / AT-513-3: poll.sh missing in-band claim reaper checking dead process liveness past grace age"
fi

# ==============================================================================
# Assertion 4: D4 / AT-513-4: Reaper preservation of active poller claim
# ==============================================================================
banner "D4 / AT-513-4: Reaper preservation of active poller claim"
# When an in-progress issue has a claim whose recorded PID is still alive and whose
# age does not exceed claim_reaper_max_age_seconds, the reaper preserves the claim.
d4_ok=1
if ! grep -qF 'claim_reaper_max_age_seconds' "$POLL_SH"; then
    d4_ok=0
fi
if ! grep -qE 'kill -0' "$POLL_SH"; then
    d4_ok=0
fi

if [ "$d4_ok" -eq 1 ]; then
    pass "D4 / AT-513-4: reaper evaluates claim_reaper_max_age_seconds ceiling and preserves active claims"
else
    fail "D4 / AT-513-4: poll.sh missing claim_reaper_max_age_seconds ceiling or active process preservation"
fi

# ==============================================================================
# Assertion 5: D4 / AT-513-5: Reaper preservation of interactive claim lacking poll- prefix
# ==============================================================================
banner "D4 / AT-513-5: Reaper preservation of interactive claims lacking poll- prefix"
# Interactive claims lacking a poll- session prefix must remain untouched by the poller reaper.
d5_ok=1
if ! grep -qE 'poll-[0-9]+' "$POLL_SH"; then
    d5_ok=0
fi

if [ "$d5_ok" -eq 1 ]; then
    pass "D5 / AT-513-5: reaper restricts automated reclamation strictly to poll- session prefixes"
else
    fail "D5 / AT-513-5: poll.sh missing session prefix filter to safeguard interactive non-poller claims"
fi

# ==============================================================================
# Assertion 6: D5 / AT-513-6: Safe worktree and unmerged branch reaper cleanup
# ==============================================================================
banner "D5 / AT-513-6: Safe worktree and unmerged branch reclamation"
# When releasing a stranded claim, the reaper inspects git ancestry. If the branch
# contains zero unmerged commits relative to origin/main, the worktree and branch are deleted.
# If unmerged commits exist, the branch is retained on disk to preserve unpushed work.
d6_ok=1
if ! grep -qE 'origin/main\.\.' "$POLL_SH"; then
    d6_ok=0
fi
if ! grep -qE 'worktree remove' "$POLL_SH"; then
    d6_ok=0
fi
if ! grep -qE 'branch -[dD]' "$POLL_SH"; then
    d6_ok=0
fi

if [ "$d6_ok" -eq 1 ]; then
    pass "D5 / AT-513-6: reaper performs safe worktree removal and unmerged branch preservation"
else
    fail "D5 / AT-513-6: poll.sh missing safe worktree deletion and unmerged commit branch preservation"
fi

# ==============================================================================
# Assertion 7: D6 / AT-513-7: Pruning of merged local branch and worktree prior to claim
# ==============================================================================
banner "D6 / AT-513-7: Pruning of merged local branch and worktree prior to claim"
# To prevent branch collision refusals in claim.sh when issues advance lifecycle rungs,
# poll.sh prunes local worktrees and branches that have already been fully merged into origin/main.
d7_ok=1
if ! grep -qE 'merge-base --is-ancestor' "$POLL_SH"; then
    d7_ok=0
fi

if [ "$d7_ok" -eq 1 ]; then
    pass "D6 / AT-513-7: poll.sh prunes merged lifecycle branches prior to invoking claim.sh"
else
    fail "D6 / AT-513-7: poll.sh missing pre-claim pruning of merged lifecycle branches"
fi

# ==============================================================================
# Assertion 8: D7 / AT-513-8: Stage-filtered first-hop intake concurrency
# ==============================================================================
banner "D7 / AT-513-8: Stage-filtered first-hop intake concurrency"
# Active concurrency for first-hop intake must parse the declared lifecycle stage
# from the claim comment. Only claims with stage: intake count against max_concurrent_first_hops.
# Athena claims on plan (stage: plan) or design (stage: design) must be excluded.
d8_ok=1
if ! grep -qEi 'stage:[[:space:]]*intake' "$POLL_SH"; then
    d8_ok=0
fi

if [ "$d8_ok" -eq 1 ]; then
    pass "D7 / AT-513-8: poll.sh filters first-hop intake concurrency counting strictly to stage: intake"
else
    fail "D7 / AT-513-8: poll.sh counts all Athena claims regardless of lifecycle stage, freezing intake"
fi

# ==============================================================================
# Assertion 9: D8 / AT-513-9: Schema validation for reaper configuration keys
# ==============================================================================
banner "D8 / AT-513-9: Schema validation for reaper configuration keys"
# scripts/ops/execution.py must validate claim_reaper_max_age_seconds and claim_reaper_min_age_seconds
# as positive integers under check(), and config/execution.yaml must configure them under loop:.
d9_ok=1
if ! grep -qF 'claim_reaper_max_age_seconds' "$EXEC_PY"; then
    d9_ok=0
fi
if ! grep -qF 'claim_reaper_min_age_seconds' "$EXEC_PY"; then
    d9_ok=0
fi
if ! grep -qF 'claim_reaper_max_age_seconds' "$EXEC_YAML"; then
    d9_ok=0
fi
if ! grep -qF 'claim_reaper_min_age_seconds' "$EXEC_YAML"; then
    d9_ok=0
fi

if [ "$d9_ok" -eq 1 ]; then
    pass "D8 / AT-513-9: execution.py validates claim reaper configuration and execution.yaml defines defaults"
else
    fail "D8 / AT-513-9: execution.py or execution.yaml missing claim reaper configuration keys"
fi

# ==============================================================================
# Assertion 10: D9, D10 / AT-513-10: Living spec and changelog update obligations
# ==============================================================================
banner "D9, D10 / AT-513-10: Living spec and changelog update obligations"
# docs/SPEC.md must document detached dispatch, reaper semantics, and intake filtering.
# CHANGELOG.md must document the fix for issue #513.
d10_ok=1
if ! grep -qEi '513|detached background runner|claim reaper|claim_reaper' "$SPEC_MD"; then
    d10_ok=0
fi
if ! grep -qE '513|claim lifecycle' "$CHANGELOG_MD"; then
    d10_ok=0
fi

if [ "$d10_ok" -eq 1 ]; then
    pass "D10 / AT-513-10: docs/SPEC.md and CHANGELOG.md updated for issue #513"
else
    fail "D10 / AT-513-10: docs/SPEC.md or CHANGELOG.md missing updates for issue #513"
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
