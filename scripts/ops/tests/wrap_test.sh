#!/usr/bin/env bash
# Contract test suite for session close-out (/wrap) (#85).
# Spec: intent/85-session-close-out/spec.md (Approved, D1-D14, AT-1-AT-20)
#
# Cites Decisions D1-D14 and Acceptance Tests AT-1..AT-20.
# Every assertion cites its Decision ID and Acceptance Test ID.
# Under the baseline tree at c2c317a44f6fe2e098bb499d23335630e5d9d17f,
# every assertion must fail (red) because the production implementation
# has not been written yet.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WRAP_SH="$REPO/scripts/ops/wrap.sh"
CLAUDE_DOOR="$REPO/.claude/commands/wrap.md"
AGY_DOOR="$REPO/.agents/workflows/wrap.md"
SPEC_MD="$REPO/docs/SPEC.md"
AGENTS_MD="$REPO/AGENTS.md"

FAILURES=0

banner() { printf '\n=== %s ===\n' "$*"; }

pass() {
    echo "PASS: $*"
}

fail() {
    echo "FAIL: $*" >&2
    FAILURES=$((FAILURES + 1))
}

# --- AT-1 (D7, Exit 0): Clean session close-out -------------------------------
banner "AT-1 (D7, Exit 0): Clean session close-out"
if [ ! -x "$WRAP_SH" ]; then
    fail "AT-1 (D7): $WRAP_SH does not exist or is not executable"
else
    out="$("$WRAP_SH" test-session 2>&1)" || rc=$?
    rc="${rc:-0}"
    if [ "$rc" -eq 0 ] && grep -qi "closed" <<<"$out" && grep -q "handoff:" <<<"$out"; then
        pass "AT-1 (D7): wrap.sh prints closed, outputs handoff block, and exits 0"
    else
        fail "AT-1 (D7): wrap.sh failed clean close-out check (rc=$rc, out=$out)"
    fi
fi

# --- AT-2 (D1, Check 1): Active child processes -------------------------------
banner "AT-2 (D1, Check 1): Active child processes and subagents"
if [ ! -x "$WRAP_SH" ]; then
    fail "AT-2 (D1): $WRAP_SH does not exist or is not executable"
else
    out="$(WRAP_TEST_ACTIVE_CHILDREN=1 "$WRAP_SH" test-session 2>&1)" || rc=$?
    rc="${rc:-0}"
    if [ "$rc" -eq 2 ] && grep -q "refused: child processes still running" <<<"$out"; then
        pass "AT-2 (D1): wrap.sh reports fail on Check 1 and exits 2 when child processes are active"
    else
        fail "AT-2 (D1): wrap.sh did not refuse with exit 2 when child processes were active (rc=$rc, out=$out)"
    fi
fi

# --- AT-3 (D1, Check 3): Unpushed worktree branch commits ---------------------
banner "AT-3 (D1, Check 3): Unpushed worktree branch commits"
if [ ! -x "$WRAP_SH" ]; then
    fail "AT-3 (D1): $WRAP_SH does not exist or is not executable"
else
    out="$(WRAP_TEST_UNPUSHED=1 "$WRAP_SH" test-session 2>&1)" || rc=$?
    rc="${rc:-0}"
    if [ "$rc" -eq 2 ] && grep -qE "refused: unpushed commits on" <<<"$out"; then
        pass "AT-3 (D1): wrap.sh reports fail on Check 3 and exits 2 on unpushed commits"
    else
        fail "AT-3 (D1): wrap.sh did not refuse with exit 2 on unpushed branch commits (rc=$rc, out=$out)"
    fi
fi

# --- AT-4 (D1, Check 4): Primary checkout dirty or behind origin/main ---------
banner "AT-4 (D1, Check 4): Primary checkout dirty or behind origin/main"
if [ ! -x "$WRAP_SH" ]; then
    fail "AT-4 (D1): $WRAP_SH does not exist or is not executable"
else
    out="$(WRAP_TEST_PRIMARY_DIRTY=1 "$WRAP_SH" test-session 2>&1)" || rc=$?
    rc="${rc:-0}"
    if [ "$rc" -eq 2 ] && grep -q "refused: primary checkout dirty or behind origin/main" <<<"$out"; then
        pass "AT-4 (D1): wrap.sh reports fail on Check 4 and exits 2 when primary is dirty or behind"
    else
        fail "AT-4 (D1): wrap.sh did not refuse with exit 2 when primary is dirty or behind (rc=$rc, out=$out)"
    fi
fi

# --- AT-5 (D1, Check 5): PR CI check status (code defect vs ambient outage) ---
banner "AT-5 (D1, Check 5): PR CI check status (code defect vs ambient outage)"
if [ ! -x "$WRAP_SH" ]; then
    fail "AT-5 (D1): $WRAP_SH does not exist or is not executable"
else
    out="$(WRAP_TEST_PR_FAIL="code" "$WRAP_SH" test-session 2>&1)" || rc=$?
    rc="${rc:-0}"
    if [ "$rc" -eq 2 ] && grep -qE "refused: PR #[0-9]+ checks failing" <<<"$out"; then
        pass "AT-5 (D1): wrap.sh reports fail and exits 2 on code-defect PR check failure"
    else
        fail "AT-5 (D1): wrap.sh did not refuse with exit 2 on code-defect PR check failure (rc=$rc, out=$out)"
    fi

    out="$(WRAP_TEST_PR_FAIL="ambient" "$WRAP_SH" test-session 2>&1)" || rc=$?
    rc="${rc:-0}"
    if [ "$rc" -eq 0 ] && grep -qi "warn" <<<"$out"; then
        pass "AT-5 (D1): wrap.sh reports warn and exits 0 on ambient environment defect"
    else
        fail "AT-5 (D1): wrap.sh did not warn and exit 0 on ambient environment defect (rc=$rc, out=$out)"
    fi
fi

# --- AT-6 (D4, Check 8 auto-repair): in-progress label removal -----------------
banner "AT-6 (D4, Check 8 auto-repair): in-progress label removal"
if [ ! -x "$WRAP_SH" ]; then
    fail "AT-6 (D4): $WRAP_SH does not exist or is not executable"
else
    out="$(WRAP_TEST_STALE_IN_PROGRESS=1 "$WRAP_SH" test-session 2>&1)" || rc=$?
    rc="${rc:-0}"
    if [ "$rc" -eq 0 ] && grep -qE "fixed: removed in-progress from #[0-9]+" <<<"$out"; then
        pass "AT-6 (D4): wrap.sh removes in-progress, reports fixed, and exits 0"
    else
        fail "AT-6 (D4): wrap.sh did not auto-repair stale in-progress label (rc=$rc, out=$out)"
    fi
fi

# --- AT-7 (D4, DRY_RUN contract): dry-run would-fix refusal -------------------
banner "AT-7 (D4, DRY_RUN contract): dry-run would-fix refusal"
if [ ! -x "$WRAP_SH" ]; then
    fail "AT-7 (D4): $WRAP_SH does not exist or is not executable"
else
    out="$(DRY_RUN=1 WRAP_TEST_STALE_IN_PROGRESS=1 "$WRAP_SH" test-session 2>&1)" || rc=$?
    rc="${rc:-0}"
    if [ "$rc" -eq 2 ] && grep -qE "would: remove in-progress from #[0-9]+" <<<"$out" && grep -qE "fail: #[0-9]+ carries in-progress \(dry-run\)" <<<"$out"; then
        pass "AT-7 (D4): wrap.sh prints would-fix, reports fail, and exits 2 under DRY_RUN=1"
    else
        fail "AT-7 (D4): wrap.sh failed DRY_RUN contract on would-fix scenario (rc=$rc, out=$out)"
    fi
fi

# --- AT-8 (D1, Check 8 refusal): missing handoff comment ----------------------
banner "AT-8 (D1, Check 8 refusal): missing handoff comment"
if [ ! -x "$WRAP_SH" ]; then
    fail "AT-8 (D1): $WRAP_SH does not exist or is not executable"
else
    out="$(WRAP_TEST_MISSING_HANDOFF=1 "$WRAP_SH" test-session 2>&1)" || rc=$?
    rc="${rc:-0}"
    if [ "$rc" -eq 2 ] && grep -qE "fail: missing handoff comment on #[0-9]+" <<<"$out"; then
        pass "AT-8 (D1): wrap.sh reports fail on missing handoff comment and exits 2"
    else
        fail "AT-8 (D1): wrap.sh did not refuse with exit 2 when handoff comment was missing (rc=$rc, out=$out)"
    fi
fi

# --- AT-9 (D1, Check 10): run artifact missing disposition --------------------
banner "AT-9 (D1, Check 10): run artifact missing disposition"
if [ ! -x "$WRAP_SH" ]; then
    fail "AT-9 (D1): $WRAP_SH does not exist or is not executable"
else
    out="$(WRAP_TEST_UNDISPOSITIONED_RUN=1 "$WRAP_SH" test-session 2>&1)" || rc=$?
    rc="${rc:-0}"
    if [ "$rc" -eq 2 ] && grep -qE "fail: artifact .* missing disposition" <<<"$out"; then
        pass "AT-9 (D1): wrap.sh reports fail on missing artifact disposition and exits 2"
    else
        fail "AT-9 (D1): wrap.sh did not refuse with exit 2 on missing artifact disposition (rc=$rc, out=$out)"
    fi
fi

# --- AT-10 (D1, Check 15): peer worktree anomaly warning ----------------------
banner "AT-10 (D1, Check 15): peer worktree anomaly warning"
if [ ! -x "$WRAP_SH" ]; then
    fail "AT-10 (D1): $WRAP_SH does not exist or is not executable"
else
    out="$(WRAP_TEST_PEER_WORKTREE_DIRTY=1 "$WRAP_SH" test-session 2>&1)" || rc=$?
    rc="${rc:-0}"
    if [ "$rc" -eq 0 ] && grep -qE "warn: peer worktree .* held by " <<<"$out"; then
        pass "AT-10 (D1): wrap.sh reports warn on peer worktree and exits 0"
    else
        fail "AT-10 (D1): wrap.sh did not warn and exit 0 on peer worktree anomaly (rc=$rc, out=$out)"
    fi
fi

# --- AT-11 (D5): Mandatory Learnings step verification ------------------------
banner "AT-11 (D5): Mandatory Learnings step verification"
if [ ! -x "$WRAP_SH" ]; then
    fail "AT-11 (D5): $WRAP_SH does not exist or is not executable"
else
    out="$(WRAP_LEARNINGS="" "$WRAP_SH" test-session 2>&1)" || rc=$?
    rc="${rc:-0}"
    if [ "$rc" -eq 2 ] && grep -q "fail: learnings step omitted" <<<"$out"; then
        pass "AT-11 (D5): wrap.sh refuses with exit 2 when learnings step is omitted"
    else
        fail "AT-11 (D5): wrap.sh did not refuse when learnings step was omitted (rc=$rc, out=$out)"
    fi

    out="$(WRAP_LEARNINGS="learnings: no learnings to persist" "$WRAP_SH" test-session 2>&1)" || rc=$?
    rc="${rc:-0}"
    if [ "$rc" -eq 0 ] && grep -q "pass: learnings accounted for" <<<"$out"; then
        pass "AT-11 (D5): wrap.sh passes when learnings attestation is provided"
    else
        fail "AT-11 (D5): wrap.sh did not pass when learnings attestation was provided (rc=$rc, out=$out)"
    fi
fi

# --- AT-12 (D1, Check 17): Credential leak detection --------------------------
banner "AT-12 (D1, Check 17): Credential leak detection"
if [ ! -x "$WRAP_SH" ]; then
    fail "AT-12 (D1): $WRAP_SH does not exist or is not executable"
else
    out="$(WRAP_TEST_LEAKED_CREDENTIAL=1 "$WRAP_SH" test-session 2>&1)" || rc=$?
    rc="${rc:-0}"
    if [ "$rc" -eq 2 ] && grep -q "fail: credential exposure detected" <<<"$out"; then
        pass "AT-12 (D1): wrap.sh refuses with exit 2 when credential exposure is detected"
    else
        fail "AT-12 (D1): wrap.sh did not refuse with exit 2 on credential exposure (rc=$rc, out=$out)"
    fi
fi

# --- AT-13 (D7, Exit 1): Environment and argument failure ---------------------
banner "AT-13 (D7, Exit 1): Environment and argument failure"
if [ ! -x "$WRAP_SH" ]; then
    fail "AT-13 (D7): $WRAP_SH does not exist or is not executable"
else
    out="$("$WRAP_SH" 2>&1)" || rc=$?
    rc="${rc:-0}"
    if [ "$rc" -eq 1 ]; then
        pass "AT-13 (D7): wrap.sh exits 1 when invoked without required arguments"
    else
        fail "AT-13 (D7): wrap.sh did not exit 1 on missing arguments (rc=$rc, out=$out)"
    fi
fi

# --- AT-14 (D8): Dual harness doors and parity --------------------------------
banner "AT-14 (D8): Dual harness doors and parity"
if git -C "$REPO" ls-files --error-unmatch "$CLAUDE_DOOR" >/dev/null 2>&1; then
    pass "AT-14 (D8): .claude/commands/wrap.md is tracked"
else
    fail "AT-14 (D8): .claude/commands/wrap.md is missing or untracked"
fi

if git -C "$REPO" ls-files --error-unmatch "$AGY_DOOR" >/dev/null 2>&1; then
    pass "AT-14 (D8): .agents/workflows/wrap.md is tracked"
else
    fail "AT-14 (D8): .agents/workflows/wrap.md is missing or untracked"
fi

if [ -f "$CLAUDE_DOOR" ] && grep -q 'scripts/ops/wrap.sh' "$CLAUDE_DOOR"; then
    pass "AT-14 (D8): .claude/commands/wrap.md invokes scripts/ops/wrap.sh"
else
    fail "AT-14 (D8): .claude/commands/wrap.md does not invoke scripts/ops/wrap.sh"
fi

if [ -f "$AGY_DOOR" ] && grep -q 'scripts/ops/wrap.sh' "$AGY_DOOR"; then
    pass "AT-14 (D8): .agents/workflows/wrap.md invokes scripts/ops/wrap.sh"
else
    fail "AT-14 (D8): .agents/workflows/wrap.md does not invoke scripts/ops/wrap.sh"
fi

# --- AT-15 (D10): Scope, living spec upsert, and checklist obligation ---------
banner "AT-15 (D10): Scope, living spec upsert, and checklist obligation"
if grep -q 'ops\.wrap' "$SPEC_MD" 2>/dev/null; then
    pass "AT-15 (D10): docs/SPEC.md defines capability ops.wrap"
else
    fail "AT-15 (D10): docs/SPEC.md missing capability ops.wrap"
fi

if grep -q '/wrap' "$AGENTS_MD" 2>/dev/null; then
    pass "AT-15 (D10): AGENTS.md includes /wrap in session checklist"
else
    fail "AT-15 (D10): AGENTS.md missing /wrap session checklist step"
fi

# --- AT-16 (D11): Snapshot mode execution and overwrite in place --------------
banner "AT-16 (D11): Snapshot mode execution and overwrite in place"
if [ ! -x "$WRAP_SH" ]; then
    fail "AT-16 (D11): $WRAP_SH does not exist or is not executable"
else
    out="$("$WRAP_SH" test-session --snapshot 2>&1)" || rc=$?
    rc="${rc:-0}"
    if [ "$rc" -eq 0 ] && grep -qE "^SNAPSHOT \(session still running, written [0-9]{2}:[0-9]{2}Z\)" <<<"$out"; then
        pass "AT-16 (D11): wrap.sh --snapshot marks line 1 with snapshot timestamp and exits 0"
    else
        fail "AT-16 (D11): wrap.sh --snapshot failed snapshot contract (rc=$rc, out=$out)"
    fi
fi

# --- AT-17 (D12): Empty session short-circuit ---------------------------------
banner "AT-17 (D12): Empty session short-circuit"
if [ ! -x "$WRAP_SH" ]; then
    fail "AT-17 (D12): $WRAP_SH does not exist or is not executable"
else
    out="$(WRAP_TEST_EMPTY_SESSION=1 "$WRAP_SH" test-session 2>&1)" || rc=$?
    rc="${rc:-0}"
    if [ "$rc" -eq 0 ] && grep -q "nothing to hand off: session clean and produced no state" <<<"$out"; then
        pass "AT-17 (D12): wrap.sh short-circuits empty clean session with exit 0 and zero files"
    else
        fail "AT-17 (D12): wrap.sh did not short-circuit empty clean session (rc=$rc, out=$out)"
    fi
fi

# --- AT-18 (D12): Mode-gated probe counts under snapshot ----------------------
banner "AT-18 (D12): Mode-gated probe counts under snapshot"
if [ ! -x "$WRAP_SH" ]; then
    fail "AT-18 (D12): $WRAP_SH does not exist or is not executable"
else
    out="$(WRAP_TEST_PROBE_COUNTS=1 "$WRAP_SH" test-session --snapshot 2>&1)" || rc=$?
    rc="${rc:-0}"
    if [ "$rc" -eq 0 ] && grep -q "probes: gated (network/worktree: 0)" <<<"$out"; then
        pass "AT-18 (D12): wrap.sh gates probes under snapshot mode"
    else
        fail "AT-18 (D12): wrap.sh did not gate expensive probes under snapshot mode (rc=$rc, out=$out)"
    fi
fi

# --- AT-19 (D13): Seat resolution order and resume block ----------------------
banner "AT-19 (D13): Seat resolution order and resume block"
if [ ! -x "$WRAP_SH" ]; then
    fail "AT-19 (D13): $WRAP_SH does not exist or is not executable"
else
    out="$("$WRAP_SH" test-session my-seat 2>&1)" || rc=$?
    rc="${rc:-0}"
    if [ "$rc" -eq 0 ] && grep -qE "resume: ops/waves/seat\.sh my-seat" <<<"$out" && grep -qE "session: test-session" <<<"$out"; then
        pass "AT-19 (D13): wrap.sh resolves seat and outputs verbatim resume block"
    else
        fail "AT-19 (D13): wrap.sh failed seat resolution or resume block format (rc=$rc, out=$out)"
    fi
fi

# --- AT-20 (D14): Cross-harness interoperability and side-channel reader ------
banner "AT-20 (D14): Cross-harness interoperability and side-channel reader"
if [ ! -x "$WRAP_SH" ]; then
    fail "AT-20 (D14): $WRAP_SH does not exist or is not executable"
else
    out="$(WRAP_TEST_CROSS_HARNESS=1 "$WRAP_SH" test-session 2>&1)" || rc=$?
    rc="${rc:-0}"
    if [ "$rc" -eq 0 ] && grep -q "sidechannel: normalized (~/.claude/context/test-session.json)" <<<"$out"; then
        pass "AT-20 (D14): wrap.sh reads normalized side-channel file across harnesses"
    else
        fail "AT-20 (D14): wrap.sh failed cross-harness side-channel contract (rc=$rc, out=$out)"
    fi
fi

# --- Summary ------------------------------------------------------------------
banner "Wrap Contract Test Summary"
if [ "$FAILURES" -gt 0 ]; then
    echo "Total contract test failures: $FAILURES (EXPECTED RED at build rung)" >&2
    exit 1
fi

echo "ALL TESTS PASSED"
exit 0
