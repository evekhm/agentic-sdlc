#!/usr/bin/env bash
# Contract test suite for context statusline and handoff instrumentation (#330).
# Spec: intent/330-statusline-instrumentation/spec.md (Approved, D1-D17, AT-1-AT-21)
#
# Cites Decisions D1-D17 and Acceptance Tests AT-1..AT-21.
# Every assertion cites its Decision ID and Acceptance Test ID.
# Under the baseline tree before implementation by Odyssey,
# every assertion fails (RED) because scripts/ops/harness/ does not exist yet.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
HARNESS_DIR="$REPO/scripts/ops/harness"
STATUSLINE="$HARNESS_DIR/statusline.sh"
SESSION_START="$HARNESS_DIR/session-start.sh"
NEWEST_DATED="$HARNESS_DIR/newest-dated.sh"
NEWEST_HANDOFF="$HARNESS_DIR/newest-handoff.sh"
INSTALL_SH="$HARNESS_DIR/install.sh"
FIXTURES_DIR="$REPO/scripts/ops/tests/fixtures/harness"

FAILURES=0
TESTS_RUN=0
TESTS_PASSED=0

banner() { printf '
=== %s ===
' "$*"; }

pass() {
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "PASS: $*"
}

fail() {
    TESTS_RUN=$((TESTS_RUN + 1))
    FAILURES=$((FAILURES + 1))
    echo "FAIL: $*" >&2
}

strip_ansi() {
    sed -E 's/\[[0-9;]*m//g' <<<"$1" | tr -d '
'
}

# Temporary sandbox directory for hermetic test execution
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

CTX_DIR="$WORK/context"
HANDOFF_DIR="$WORK/handoffs"
mkdir -p "$CTX_DIR" "$HANDOFF_DIR"

# --- AT-1 (D1, D8, D10, D11, D12): Claude payload with cost, cache write, effort, seat
banner "AT-1 (D1, D8, D10, D11, D12): Claude payload with cost, cache write, effort, seat"
if [ ! -x "$STATUSLINE" ]; then
    fail "AT-1 (D1, D8, D10, D11, D12): $STATUSLINE does not exist or is not executable"
else
    fixture="$FIXTURES_DIR/claude-with-cost-effort.json"
    expected="ctx 105.3K/200K 52%  \$81.40  tok 105.3K in/4 out/105.3K tot  cache 88% 5m cw 3.5M  Fable 5.1 [high] · advisor"
    out="$(AGENTIC_SEAT="advisor" AGENTIC_CTX_DIR="$CTX_DIR" "$STATUSLINE" < "$fixture" 2>/dev/null || true)"
    clean="$(strip_ansi "$out" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    if [ "$clean" = "$expected" ]; then
        pass "AT-1 (D1, D8, D10, D11, D12): Claude payload renders exact display contract line with cost and cw"
    else
        fail "AT-1 (D1, D8, D10, D11, D12): output mismatch. Expected: '$expected', Got: '$clean'"
    fi
fi

# --- AT-2 (D1, D8, D9, D10, D12): Antigravity internal quota without cost
banner "AT-2 (D1, D8, D9, D10, D12): Antigravity internal quota without cost"
if [ ! -x "$STATUSLINE" ]; then
    fail "AT-2 (D1, D8, D9, D10, D12): $STATUSLINE does not exist or is not executable"
else
    fixture="$FIXTURES_DIR/agy-internal-quota-no-cost.json"
    expected="ctx 107.0K/200K 53%  tok 107.0K in/45.1K out/152.2K tot  cache 94%  Gemini 3.8 Flash [high]"
    out="$(AGENTIC_CTX_DIR="$CTX_DIR" "$STATUSLINE" < "$fixture" 2>/dev/null || true)"
    clean="$(strip_ansi "$out" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    if [ "$clean" = "$expected" ]; then
        pass "AT-2 (D1, D8, D9, D10, D12): Antigravity internal quota omits cost segment and outputs tokens"
    else
        fail "AT-2 (D1, D8, D9, D10, D12): output mismatch. Expected: '$expected', Got: '$clean'"
    fi
fi

# --- AT-3 (D1, D9, D10, D11): Explicit cost of zero
banner "AT-3 (D1, D9, D10, D11): Explicit cost of zero"
if [ ! -x "$STATUSLINE" ]; then
    fail "AT-3 (D1, D9, D10, D11): $STATUSLINE does not exist or is not executable"
else
    fixture="$FIXTURES_DIR/claude-1m-zero-cost.json"
    expected="ctx 12.0K/200K 6%  \$0.00  tok 12.0K in/10 out/12.0K tot  cache 0% cold cw 11.0K  Opus 5"
    out="$(AGENTIC_CTX_DIR="$CTX_DIR" "$STATUSLINE" < "$fixture" 2>/dev/null || true)"
    clean="$(strip_ansi "$out" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    if [ "$clean" = "$expected" ]; then
        pass "AT-3 (D1, D9, D10, D11): Explicit cost of zero prints \$0.00"
    else
        fail "AT-3 (D1, D9, D10, D11): output mismatch. Expected: '$expected', Got: '$clean'"
    fi
fi

# --- AT-4 (D1): Malformed or non-JSON input survives silently
banner "AT-4 (D1): Malformed or non-JSON input survives silently"
if [ ! -x "$STATUSLINE" ]; then
    fail "AT-4 (D1): $STATUSLINE does not exist or is not executable"
else
    rc=0
    out="$(printf 'garbage non-json text {' | AGENTIC_CTX_DIR="$CTX_DIR" "$STATUSLINE" 2>/dev/null)" || rc=$?
    if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
        pass "AT-4 (D1): Malformed input exits 0 with empty stdout"
    else
        fail "AT-4 (D1): Malformed input did not exit 0 or emitted output (rc=$rc, out='$out')"
    fi
fi

# --- AT-5 (D2, D10, D13): Side-channel state contract and schema completeness
banner "AT-5 (D2, D10, D13): Side-channel state contract and schema completeness"
if [ ! -x "$STATUSLINE" ]; then
    fail "AT-5 (D2, D10, D13): $STATUSLINE does not exist or is not executable"
else
    test_ctx="$WORK/at5_ctx"
    mkdir -p "$test_ctx"
    fixture="$FIXTURES_DIR/claude-with-cost-effort.json"
    AGENTIC_SEAT="advisor" AGENTIC_CTX_DIR="$test_ctx" "$STATUSLINE" < "$fixture" >/dev/null 2>&1 || true
    side_json="$test_ctx/claude-200k.json"
    raw_json="$test_ctx/claude-200k.raw.json"
    dotfiles="$(find "$test_ctx" -maxdepth 1 -name '.*' ! -name '.' ! -name '..' 2>/dev/null)"

    if [ -f "$side_json" ] && [ -f "$raw_json" ] && [ -z "$dotfiles" ]; then
        has_schema="$(jq -r '
            (.session_id == "claude-200k") and
            (.used_tokens == 105300) and
            (.ceiling == 200000) and
            (.pct == 52) and
            (.cost_usd == 81.4) and
            (.accum_input_tokens != null) and
            (.accum_output_tokens != null) and
            (.accum_total_tokens != null) and
            (.accum_total_tokens == (.accum_input_tokens + .accum_output_tokens)) and
            (has("pre_compact_mechanical_ts")) and
            (.pre_compact_mechanical_ts == null) and
            (has("pre_compact_narrative_ts")) and
            (.pre_compact_narrative_ts == null) and
            (.seat == "advisor") and
            (.cache.hit_pct == 88)
        ' "$side_json" 2>/dev/null || echo "false")"

        if [ "$has_schema" = "true" ]; then
            pass "AT-5 (D2, D10, D13): Side-channel file schema matches contract with reserved snapshot fields"
        else
            fail "AT-5 (D2, D10, D13): Side-channel schema validation failed on $side_json"
        fi
    else
        fail "AT-5 (D2, D10, D13): Missing side-channel file or lingering dotfiles in $test_ctx"
    fi
fi

# --- AT-6 (D2): Empty session_id and conversation_id skips side channel
banner "AT-6 (D2): Empty session_id and conversation_id skips side channel"
if [ ! -x "$STATUSLINE" ]; then
    fail "AT-6 (D2): $STATUSLINE does not exist or is not executable"
else
    test_ctx="$WORK/at6_ctx"
    mkdir -p "$test_ctx"
    payload='{"session_id":"","conversation_id":"","model":{"id":"test"},"context_window":{"total_input_tokens":1000}}'
    printf '%s' "$payload" | AGENTIC_CTX_DIR="$test_ctx" "$STATUSLINE" >/dev/null 2>&1 || true
    n_files="$(find "$test_ctx" -type f -name '*.json' 2>/dev/null | wc -l)"
    if [ "$n_files" -eq 0 ]; then
        pass "AT-6 (D2): Empty session/conversation ID produces no side-channel file"
    else
        fail "AT-6 (D2): Expected 0 side-channel files for empty session ID, found $n_files"
    fi
fi

# --- AT-7 (D3): Session-start hook injects handoff when seat is set
banner "AT-7 (D3): Session-start hook injects handoff when seat is set"
if [ ! -x "$SESSION_START" ]; then
    fail "AT-7 (D3): $SESSION_START does not exist or is not executable"
else
    test_handoffs="$WORK/at7_handoffs"
    mkdir -p "$test_handoffs"
    printf 'Verifier handoff content line 1
Verifier handoff content line 2
' > "$test_handoffs/handoff-verifier-2026-09-10.txt"
    out="$(printf '{}' | AGENTIC_SEAT="verifier" CLAUDE_HANDOFF_DIR="$test_handoffs" AGENTIC_HANDOFF_DIR="$test_handoffs" "$SESSION_START" 2>/dev/null || true)"
    if grep -q "Handoff for the verifier seat" <<<"$out" && grep -q "Verifier handoff content line 2" <<<"$out"; then
        pass "AT-7 (D3): Session-start injects full handoff when seat is set"
    else
        fail "AT-7 (D3): Session-start failed to inject handoff for seat verifier"
    fi
fi

# --- AT-8 (D3): Session-start hook emits operator pointer when seat is unset
banner "AT-8 (D3): Session-start hook emits operator pointer when seat is unset"
if [ ! -x "$SESSION_START" ]; then
    fail "AT-8 (D3): $SESSION_START does not exist or is not executable"
else
    test_handoffs="$WORK/at8_handoffs"
    mkdir -p "$test_handoffs"
    printf 'Plan handoff confidential content
' > "$test_handoffs/handoff-plan-2026-09-10.txt"
    out="$(printf '{}' | AGENTIC_SEAT="" CLAUDE_SEAT="" CLAUDE_HANDOFF_DIR="$test_handoffs" AGENTIC_HANDOFF_DIR="$test_handoffs" "$SESSION_START" 2>/dev/null || true)"
    if grep -q "Operator state: the newest handoff for this checkout is" <<<"$out" && ! grep -q "Plan handoff confidential content" <<<"$out"; then
        pass "AT-8 (D3): Session-start emits operator pointer without leaking handoff text"
    else
        fail "AT-8 (D3): Session-start did not emit pointer or leaked handoff text when seat unset"
    fi
fi

# --- AT-9 (D3): Session-start hook oversize protection
banner "AT-9 (D3): Session-start hook oversize protection"
if [ ! -x "$SESSION_START" ]; then
    fail "AT-9 (D3): $SESSION_START does not exist or is not executable"
else
    test_handoffs="$WORK/at9_handoffs"
    mkdir -p "$test_handoffs"
    python3 -c "print('A' * 70000)" > "$test_handoffs/handoff-verifier-2026-09-10.txt"
    out="$(printf '{}' | AGENTIC_SEAT="verifier" CLAUDE_HANDOFF_MAX_BYTES=60000 AGENTIC_HANDOFF_MAX_BYTES=60000 CLAUDE_HANDOFF_DIR="$test_handoffs" AGENTIC_HANDOFF_DIR="$test_handoffs" "$SESSION_START" 2>/dev/null || true)"
    if grep -q "too large to inject" <<<"$out" && [ "${#out}" -lt 5000 ]; then
        pass "AT-9 (D3): Session-start gates oversized handoff and emits warning pointer"
    else
        fail "AT-9 (D3): Session-start oversized handoff check failed"
    fi
fi

# --- AT-10 (D4): Date and numeric suffix ordering in newest-dated.sh
banner "AT-10 (D4): Date and numeric suffix ordering in newest-dated.sh"
if [ ! -x "$NEWEST_DATED" ]; then
    fail "AT-10 (D4): $NEWEST_DATED does not exist or is not executable"
else
    test_dated="$WORK/at10_dated"
    mkdir -p "$test_dated"
    touch "$test_dated/x-2026-09-09.txt"
    touch "$test_dated/x-2026-09-09-3.txt"
    touch "$test_dated/x-2026-09-10.txt"

    res1="$("$NEWEST_DATED" "$test_dated/x" 2>/dev/null || true)"
    rm "$test_dated/x-2026-09-10.txt"
    res2="$("$NEWEST_DATED" "$test_dated/x" 2>/dev/null || true)"

    if [ "$res1" = "$test_dated/x-2026-09-10.txt" ] && [ "$res2" = "$test_dated/x-2026-09-09-3.txt" ]; then
        pass "AT-10 (D4): Date and numeric suffix ordering resolves newest file correctly"
    else
        fail "AT-10 (D4): Date ordering resolution failed (res1='$res1', res2='$res2')"
    fi
fi

# --- AT-11 (D4): Worktree handoff resolution in newest-handoff.sh
banner "AT-11 (D4): Worktree handoff resolution in newest-handoff.sh"
if [ ! -x "$NEWEST_HANDOFF" ]; then
    fail "AT-11 (D4): $NEWEST_HANDOFF does not exist or is not executable"
else
    if grep -q "git-common-dir" "$NEWEST_HANDOFF" 2>/dev/null; then
        pass "AT-11 (D4): newest-handoff.sh resolves primary checkout via git-common-dir"
    else
        fail "AT-11 (D4): newest-handoff.sh does not use git-common-dir for worktree resolution"
    fi
fi

# --- AT-12 (D5, D7): Idempotent installer and project settings tracking
banner "AT-12 (D5, D7): Idempotent installer and project settings tracking"
if [ ! -x "$INSTALL_SH" ]; then
    fail "AT-12 (D5, D7): $INSTALL_SH does not exist or is not executable"
else
    mock_home="$WORK/mock_home"
    mock_repo="$WORK/mock_repo"
    mkdir -p "$mock_home/.claude" "$mock_repo/.claude"
    echo '{}' > "$mock_home/.claude/settings.json"
    echo '{}' > "$mock_repo/.claude/settings.json"

    HOME="$mock_home" REPO_DIR="$mock_repo" "$INSTALL_SH" >/dev/null 2>&1 || true
    HOME="$mock_home" REPO_DIR="$mock_repo" "$INSTALL_SH" >/dev/null 2>&1 || true

    proj_json="$mock_repo/.claude/settings.json"
    cmd="$(jq -r '.hooks.SessionStart[0].hooks[0].command // ""' "$proj_json" 2>/dev/null || true)"
    count="$(jq -r '.hooks.SessionStart | length' "$proj_json" 2>/dev/null || echo 0)"

    if [ "$count" -eq 1 ] && grep -q '\${CLAUDE_PROJECT_DIR}' <<<"$cmd" && ! grep -q "$REPO" <<<"$cmd"; then
        pass "AT-12 (D5, D7): install.sh is idempotent and uses \${CLAUDE_PROJECT_DIR} without absolute paths"
    else
        fail "AT-12 (D5, D7): Installer idempotency or relative project path check failed"
    fi
fi

# --- AT-13 (D5, D16): install.sh --check verification and drift check
banner "AT-13 (D5, D16): install.sh --check verification and drift check"
if [ ! -x "$INSTALL_SH" ]; then
    fail "AT-13 (D5, D16): $INSTALL_SH does not exist or is not executable"
else
    if grep -q -- "--check" "$INSTALL_SH" 2>/dev/null && grep -q "drift" "$INSTALL_SH" 2>/dev/null; then
        pass "AT-13 (D5, D16): install.sh implements --check validation and dual-harness drift check"
    else
        fail "AT-13 (D5, D16): install.sh missing --check or drift check logic"
    fi
fi

# --- AT-14 (D6, D17): CI workflow integration and harness_test.sh wiring
banner "AT-14 (D6, D17): CI workflow integration and harness_test.sh wiring"
ci_workflow="$REPO/.github/workflows/ci-gates.yml"
if grep -q "harness_test.sh" "$ci_workflow" 2>/dev/null; then
    pass "AT-14 (D6, D17): ci-gates.yml wires harness_test.sh into execution job"
else
    fail "AT-14 (D6, D17): ci-gates.yml does not wire harness_test.sh into execution job"
fi

# --- AT-15 (D8): Wrap tag threshold at 60% (wrap soon)
banner "AT-15 (D8): Wrap tag threshold at 60% (wrap soon)"
if [ ! -x "$STATUSLINE" ]; then
    fail "AT-15 (D8): $STATUSLINE does not exist or is not executable"
else
    payload='{"session_id":"t60","model":{"id":"m"},"context_window":{"total_input_tokens":120000,"context_window_size":200000}}'
    out="$(printf '%s' "$payload" | AGENTIC_CTX_DIR="$CTX_DIR" "$STATUSLINE" 2>/dev/null || true)"
    clean="$(strip_ansi "$out")"
    if grep -q "60% wrap soon" <<<"$clean"; then
        pass "AT-15 (D8): 60% threshold triggers yellow 'wrap soon' tag"
    else
        fail "AT-15 (D8): 60% threshold tag missing (out='$clean')"
    fi
fi

# --- AT-16 (D8): Wrap tag threshold at 70% (WRAP NOW)
banner "AT-16 (D8): Wrap tag threshold at 70% (WRAP NOW)"
if [ ! -x "$STATUSLINE" ]; then
    fail "AT-16 (D8): $STATUSLINE does not exist or is not executable"
else
    payload='{"session_id":"t70","model":{"id":"m"},"context_window":{"total_input_tokens":140000,"context_window_size":200000}}'
    out="$(printf '%s' "$payload" | AGENTIC_CTX_DIR="$CTX_DIR" "$STATUSLINE" 2>/dev/null || true)"
    clean="$(strip_ansi "$out")"
    if grep -q "70% WRAP NOW" <<<"$clean"; then
        pass "AT-16 (D8): 70% threshold triggers red 'WRAP NOW' tag"
    else
        fail "AT-16 (D8): 70% threshold tag missing (out='$clean')"
    fi
fi

# --- AT-17 (D8): Wrap tag threshold at 90% (COMPACTING)
banner "AT-17 (D8): Wrap tag threshold at 90% (COMPACTING)"
if [ ! -x "$STATUSLINE" ]; then
    fail "AT-17 (D8): $STATUSLINE does not exist or is not executable"
else
    payload='{"session_id":"t90","model":{"id":"m"},"context_window":{"total_input_tokens":180000,"context_window_size":200000}}'
    out="$(printf '%s' "$payload" | AGENTIC_CTX_DIR="$CTX_DIR" "$STATUSLINE" 2>/dev/null || true)"
    clean="$(strip_ansi "$out")"
    if grep -q "90% COMPACTING" <<<"$clean"; then
        pass "AT-17 (D8): 90% threshold triggers 'COMPACTING' tag"
    else
        fail "AT-17 (D8): 90% threshold tag missing (out='$clean')"
    fi
fi

# --- AT-18 (D10): Session token accumulator on Claude Code
banner "AT-18 (D10): Session token accumulator on Claude Code"
if [ ! -x "$STATUSLINE" ]; then
    fail "AT-18 (D10): $STATUSLINE does not exist or is not executable"
else
    test_ctx="$WORK/at18_ctx"
    mkdir -p "$test_ctx"
    p1='{"session_id":"s_claude","model":{"id":"m"},"context_window":{"total_input_tokens":50000,"total_output_tokens":1000},"prompt_cache":{"requests":1}}'
    p2='{"session_id":"s_claude","model":{"id":"m"},"context_window":{"total_input_tokens":50000,"total_output_tokens":1000},"prompt_cache":{"requests":1}}'
    p3='{"session_id":"s_claude","model":{"id":"m"},"context_window":{"total_input_tokens":60000,"total_output_tokens":2000},"prompt_cache":{"requests":2}}'

    printf '%s' "$p1" | AGENTIC_CTX_DIR="$test_ctx" "$STATUSLINE" >/dev/null 2>&1 || true
    printf '%s' "$p2" | AGENTIC_CTX_DIR="$test_ctx" "$STATUSLINE" >/dev/null 2>&1 || true
    out="$(printf '%s' "$p3" | AGENTIC_CTX_DIR="$test_ctx" "$STATUSLINE" 2>/dev/null || true)"
    clean="$(strip_ansi "$out")"

    side="$test_ctx/s_claude.json"
    accum_in="$(jq -r '.accum_input_tokens // 0' "$side" 2>/dev/null || echo 0)"
    accum_out="$(jq -r '.accum_output_tokens // 0' "$side" 2>/dev/null || echo 0)"

    if [ "$accum_in" -eq 110000 ] && [ "$accum_out" -eq 3000 ] && grep -q "tok 110.0K in/3.0K out/113.0K tot" <<<"$clean"; then
        pass "AT-18 (D10): Claude accumulator advances on requests change and ignores redraws"
    else
        fail "AT-18 (D10): Claude accumulator failed (accum_in=$accum_in, accum_out=$accum_out, out='$clean')"
    fi
fi

# --- AT-19 (D10): Session token accumulator on Antigravity
banner "AT-19 (D10): Session token accumulator on Antigravity"
if [ ! -x "$STATUSLINE" ]; then
    fail "AT-19 (D10): $STATUSLINE does not exist or is not executable"
else
    test_ctx="$WORK/at19_ctx"
    mkdir -p "$test_ctx"
    p1='{"session_id":"s_agy","model":{"id":"m"},"context_window":{"total_input_tokens":59793,"total_output_tokens":5163}}'
    p2='{"session_id":"s_agy","model":{"id":"m"},"context_window":{"total_input_tokens":107087,"total_output_tokens":45175}}'

    printf '%s' "$p1" | AGENTIC_CTX_DIR="$test_ctx" "$STATUSLINE" >/dev/null 2>&1 || true
    out="$(printf '%s' "$p2" | AGENTIC_CTX_DIR="$test_ctx" "$STATUSLINE" 2>/dev/null || true)"
    clean="$(strip_ansi "$out")"

    side="$test_ctx/s_agy.json"
    accum_out="$(jq -r '.accum_output_tokens // 0' "$side" 2>/dev/null || echo 0)"

    if [ "$accum_out" -eq 45175 ] && grep -q "45.1K out" <<<"$clean"; then
        pass "AT-19 (D10): Antigravity accumulator tracks running output tokens"
    else
        fail "AT-19 (D10): Antigravity accumulator failed (accum_out=$accum_out, out='$clean')"
    fi
fi

# --- AT-20 (D17): Claude no-cost fixture (Fixture 3) byte-comparison
banner "AT-20 (D17): Claude no-cost fixture (Fixture 3) byte-comparison"
if [ ! -x "$STATUSLINE" ]; then
    fail "AT-20 (D17): $STATUSLINE does not exist or is not executable"
else
    fixture="$FIXTURES_DIR/claude-no-cost-wrap.json"
    expected="ctx 127.7K/200K 63% wrap soon  tok 127.7K in/1.5K out/129.2K tot  gemini-3.8-flash"
    out="$(AGENTIC_CTX_DIR="$CTX_DIR" "$STATUSLINE" < "$fixture" 2>/dev/null || true)"
    clean="$(strip_ansi "$out" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    if [ "$clean" = "$expected" ]; then
        pass "AT-20 (D17): Claude no-cost fixture matches exact display line"
    else
        fail "AT-20 (D17): Claude no-cost fixture mismatch. Expected: '$expected', Got: '$clean'"
    fi
fi

# --- AT-21 (D17): Antigravity with cost fixture (Fixture 5) byte-comparison
banner "AT-21 (D17): Antigravity with cost fixture (Fixture 5) byte-comparison"
if [ ! -x "$STATUSLINE" ]; then
    fail "AT-21 (D17): $STATUSLINE does not exist or is not executable"
else
    fixture="$FIXTURES_DIR/agy-with-cost.json"
    expected="ctx 50.0K/200K 25%  \$2.45  tok 50.0K in/5.0K out/55.0K tot  cache 50%  Gemini 3.8 Pro [medium]"
    out="$(AGENTIC_CTX_DIR="$CTX_DIR" "$STATUSLINE" < "$fixture" 2>/dev/null || true)"
    clean="$(strip_ansi "$out" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    if [ "$clean" = "$expected" ]; then
        pass "AT-21 (D17): Antigravity with cost fixture matches exact display line"
    else
        fail "AT-21 (D17): Antigravity with cost fixture mismatch. Expected: '$expected', Got: '$clean'"
    fi
fi

# --- Summary ------------------------------------------------------------------
banner "Harness Contract Test Summary"
echo "Ran $TESTS_RUN tests: $TESTS_PASSED passed, $FAILURES failed"
if [ "$FAILURES" -gt 0 ]; then
    echo "Total contract test failures: $FAILURES (EXPECTED RED at build rung)" >&2
    exit 1
fi

echo "ALL TESTS PASSED"
exit 0
