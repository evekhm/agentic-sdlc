#!/usr/bin/env bash
# Contract tests for pricing Gemini Flash and Pro at pinned 3.x versions (#269).
# Cites Decisions D1, D2, D3, D4, D5, D6, D7
# and Acceptance Tests AT-269-1 through AT-269-12.
#
# Every assertion cites its Decision ID and Acceptance Test ID.
# Hermetic: tests run locally without network access.
# Under the baseline tree before Odyssey's implementation, all assertions
# for updated behavior must FAIL (red) cleanly, while legacy preservation
# assertions pass, proving behavior is not smuggled.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SESSION_SPEND_SH="$REPO/scripts/ops/session_spend.sh"
WORK_SH="$REPO/scripts/ops/work.sh"
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

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Helper: format assistant message JSONL
msg() {
    local f=$1 ts=$2 model=$3 inp=$4 cr=$5 c5=$6 c1=$7 out=$8
    jq -cn --arg ts "$ts" --arg m "$model" \
        --argjson i "$inp" --argjson r "$cr" --argjson a "$c5" --argjson b "$c1" --argjson o "$out" \
        '{type:"assistant", timestamp:$ts, message:{model:$m, usage:{
            input_tokens:$i, cache_read_input_tokens:$r,
            cache_creation:{ephemeral_5m_input_tokens:$a, ephemeral_1h_input_tokens:$b},
            cache_creation_input_tokens:($a+$b), output_tokens:$o}}}' >> "$f"
}

# Helper: format Antigravity dispatch envelope JSON
envelope_msg() {
    local f=$1 ts=$2 conv=$3 model=$4 inp=$5 cr=$6 out=$7 think=$8
    jq -cn --arg ts "$ts" --arg conv "$conv" --arg m "$model" \
        --argjson i "$inp" --argjson cr "$cr" --argjson o "$out" --argjson th "$think" \
        '{conversation_id:$conv, status:"SUCCESS", timestamp:$ts, model:$m, usage:{
            input_tokens:$i, cache_read_tokens:$cr, output_tokens:$o, thinking_tokens:$th,
            total_tokens:($i+$cr+$o+$th)}}' >> "$f"
}

# Helper: extract USD cell from Per model table
model_usd() {
    printf '%s\n' "$1" | awk -v m="$2" \
        '/^== Per model ==/ {f=1; next} /^== Main vs/ {f=0} f && $1==m {print $3}'
}

# Helper: dynamically evaluate rate_tier(m) from session_spend.sh
session_spend_rate_tier() {
    local model="$1"
    awk -f <(awk '/function model_family\(m\)/,/function usd\(model,/ { if ($0 !~ /function usd\(model,/) print }' "$SESSION_SPEND_SH") -e '
    BEGIN {
        r = rate_tier("'"$model"'")
        print r
    }'
}

# Helper: dynamically evaluate rate_tier(m) from work.sh
work_rate_tier() {
    local model="$1"
    awk -f <(awk '/function model_family\(m\)/,/BEGIN \{/ { if ($0 !~ /BEGIN \{/) print }' "$WORK_SH") -e '
    BEGIN {
        r = rate_tier("'"$model"'")
        print r
    }'
}

# Helper: dynamically compute cost in work.sh awk block
work_cost_compute() {
    local models="$1" inp="$2" cr="$3" out="$4"
    awk -v m="$models" -v inp="$inp" -v cr="$cr" -v out="$out" \
        -f <(awk '/function model_family\(m\)/,/BEGIN \{/ { if ($0 !~ /BEGIN \{/) print }' "$WORK_SH") -e '
    BEGIN {
        r = rate_tier(m)
        if (r == "") exit 1
        split(r, p, " ")
        printf "%.6f\n", (inp*p[1] + cr*p[4] + out*p[5]) / 1e6
    }'
}

# ==============================================================================
# Assertion 1: D1, D2 / AT-269-1: Flash 3.8 Rate Tuple in session_spend.sh
# ==============================================================================
banner "D1, D2 / AT-269-1: Flash 3.8 Rate Tuple in session_spend.sh"
flash_tier="$(session_spend_rate_tier "gemini-3.8-flash-high")"
if [ "$flash_tier" = "0.75 0 0 0.075 3.75" ]; then
    pass "D1, D2 / AT-269-1: rate_tier(gemini-3.8-flash-high) returns 0.75 0 0 0.075 3.75"
else
    fail "D1, D2 / AT-269-1: rate_tier(gemini-3.8-flash-high) expected '0.75 0 0 0.075 3.75', got '${flash_tier:-<empty>}'"
fi

# ==============================================================================
# Assertion 2: D1, D2, D6 / AT-269-2: Flash 3.8 Session Spend Calculation in session_spend.sh
# ==============================================================================
banner "D1, D2, D6 / AT-269-2: Flash 3.8 Session Spend Calculation in session_spend.sh"
T2="$WORK/t2"; mkdir -p "$T2"
msg "$T2/turn.jsonl" "2026-08-20T10:00:00.000Z" "gemini-3.8-flash-high" 1000000 1000000 0 0 1000000
out2="$(bash "$SESSION_SPEND_SH" "$T2" --out "$WORK/o2" 2>&1 || true)"
usd2="$(model_usd "$out2" "gemini-3.8-flash-high")"
if [ "$usd2" = "4.58" ]; then
    pass "D1, D2, D6 / AT-269-2: gemini-3.8-flash-high (1M in + 1M cr + 1M out) prices at \$4.58"
else
    fail "D1, D2, D6 / AT-269-2: gemini-3.8-flash-high expected \$4.58, got '${usd2:-<no row>}'"
fi

# ==============================================================================
# Assertion 3: D1, D6 / AT-269-3: Flash 3.8 Input-Only Calculation in session_spend.sh
# ==============================================================================
banner "D1, D6 / AT-269-3: Flash 3.8 Input-Only Calculation in session_spend.sh"
T3="$WORK/t3"; mkdir -p "$T3"
msg "$T3/turn.jsonl" "2026-08-20T10:00:00.000Z" "gemini-3.8-flash-medium" 1000000 0 0 0 0
out3="$(bash "$SESSION_SPEND_SH" "$T3" --out "$WORK/o3" 2>&1 || true)"
usd3="$(model_usd "$out3" "gemini-3.8-flash-medium")"
if [ "$usd3" = "0.75" ]; then
    pass "D1, D6 / AT-269-3: gemini-3.8-flash-medium (1M in) prices at \$0.75"
else
    fail "D1, D6 / AT-269-3: gemini-3.8-flash-medium expected \$0.75, got '${usd3:-<no row>}'"
fi

# ==============================================================================
# Assertion 4: D1, D6 / AT-269-4: Legacy Flash 1.5 Rate Preservation in session_spend.sh
# ==============================================================================
banner "D1, D6 / AT-269-4: Legacy Flash 1.5 Rate Preservation in session_spend.sh"
T4="$WORK/t4"; mkdir -p "$T4"
msg "$T4/turn.jsonl" "2026-08-20T10:00:00.000Z" "gemini-1.5-flash" 1000000 0 0 0 0
out4="$(bash "$SESSION_SPEND_SH" "$T4" --out "$WORK/o4" 2>&1 || true)"
usd4="$(model_usd "$out4" "gemini-1.5-flash")"
if [ "$usd4" = "0.15" ]; then
    pass "D1, D6 / AT-269-4: legacy gemini-1.5-flash (1M in) preserved at \$0.15"
else
    fail "D1, D6 / AT-269-4: legacy gemini-1.5-flash expected \$0.15, got '${usd4:-<no row>}'"
fi

# ==============================================================================
# Assertion 5: D1, D2, D6 / AT-269-5: Pro 3.1 Rate Tuple and Calculation in session_spend.sh
# ==============================================================================
banner "D1, D2, D6 / AT-269-5: Pro 3.1 Rate Tuple and Calculation in session_spend.sh"
pro31_tier="$(session_spend_rate_tier "gemini-3.1-pro-low-thinking")"
T5="$WORK/t5"; mkdir -p "$T5"
msg "$T5/turn.jsonl" "2026-08-20T10:00:00.000Z" "gemini-3.1-pro-low-thinking" 1000000 1000000 0 0 1000000
out5="$(bash "$SESSION_SPEND_SH" "$T5" --out "$WORK/o5" 2>&1 || true)"
usd5="$(model_usd "$out5" "gemini-3.1-pro-low-thinking")"
if [ "$pro31_tier" = "2.00 0 0 0.20 12.00" ] && [ "$usd5" = "14.20" ]; then
    pass "D1, D2, D6 / AT-269-5: gemini-3.1-pro rates tuple 2.00 0 0 0.20 12.00 and spend \$14.20"
else
    fail "D1, D2, D6 / AT-269-5: gemini-3.1-pro expected tuple '2.00 0 0 0.20 12.00' (got '${pro31_tier:-<empty>}') and spend \$14.20 (got '${usd5:-<no row>}')"
fi

# ==============================================================================
# Assertion 6: D1, D6 / AT-269-6: Legacy Pro 1.5 Rate Preservation in session_spend.sh
# ==============================================================================
banner "D1, D6 / AT-269-6: Legacy Pro 1.5 Rate Preservation in session_spend.sh"
T6="$WORK/t6"; mkdir -p "$T6"
msg "$T6/turn.jsonl" "2026-08-20T10:00:00.000Z" "gemini-1.5-pro" 1000000 0 0 0 0
out6="$(bash "$SESSION_SPEND_SH" "$T6" --out "$WORK/o6" 2>&1 || true)"
usd6="$(model_usd "$out6" "gemini-1.5-pro")"
if [ "$usd6" = "1.25" ]; then
    pass "D1, D6 / AT-269-6: legacy gemini-1.5-pro (1M in) preserved at \$1.25"
else
    fail "D1, D6 / AT-269-6: legacy gemini-1.5-pro expected \$1.25, got '${usd6:-<no row>}'"
fi

# ==============================================================================
# Assertion 7: D1, D6 / AT-269-7: Antigravity Envelope Spend Calculation in session_spend.sh
# ==============================================================================
banner "D1, D6 / AT-269-7: Antigravity Envelope Spend Calculation in session_spend.sh"
T7="$WORK/t7"; mkdir -p "$T7"
envelope_msg "$T7/dispatch.json" "2026-08-20T10:00:00.000Z" "conv-269" "gemini-3.8-flash-high" 1000000 0 500000 500000
out7="$(bash "$SESSION_SPEND_SH" "$T7" --out "$WORK/o7" 2>&1 || true)"
usd7="$(model_usd "$out7" "gemini-3.8-flash-high")"
if [ "$usd7" = "4.50" ]; then
    pass "D1, D6 / AT-269-7: Antigravity envelope on gemini-3.8-flash-high (1M in + 1M out+think) prices at \$4.50"
else
    fail "D1, D6 / AT-269-7: Antigravity envelope expected \$4.50, got '${usd7:-<no row>}'"
fi

# ==============================================================================
# Assertion 8: D1, D3 / AT-269-8: Flash 3.8 Rate Tuple in work.sh
# ==============================================================================
banner "D1, D3 / AT-269-8: Flash 3.8 Rate Tuple in work.sh"
work_flash_tier="$(work_rate_tier "gemini-3.8-flash-high")"
if [ "$work_flash_tier" = "0.75 0 0 0.075 3.75" ]; then
    pass "D1, D3 / AT-269-8: work.sh rate_tier(gemini-3.8-flash-high) returns 0.75 0 0 0.075 3.75"
else
    fail "D1, D3 / AT-269-8: work.sh rate_tier(gemini-3.8-flash-high) expected '0.75 0 0 0.075 3.75', got '${work_flash_tier:-<empty>}'"
fi

# ==============================================================================
# Assertion 9: D1, D3, D6 / AT-269-9: Antigravity Envelope Cost Calculation in work.sh
# ==============================================================================
banner "D1, D3, D6 / AT-269-9: Antigravity Envelope Cost Calculation in work.sh"
cost9="$(work_cost_compute "gemini-3.8-flash-high" 1000000 0 0 || true)"
if [ "$cost9" = "0.750000" ]; then
    pass "D1, D3, D6 / AT-269-9: work.sh computes 0.750000 for gemini-3.8-flash-high with 1M input"
else
    fail "D1, D3, D6 / AT-269-9: work.sh expected cost 0.750000, got '${cost9:-<error>}'"
fi

# ==============================================================================
# Assertion 10: D1, D3, D6 / AT-269-10: Legacy Pro Cost Calculation in work.sh
# ==============================================================================
banner "D1, D3, D6 / AT-269-10: Legacy Pro Cost Calculation in work.sh"
cost10="$(work_cost_compute "gemini-1.5-pro-002" 1000000 0 0 || true)"
if [ "$cost10" = "1.250000" ]; then
    pass "D1, D3, D6 / AT-269-10: work.sh legacy preservation computes 1.250000 for gemini-1.5-pro-002 with 1M input"
else
    fail "D1, D3, D6 / AT-269-10: work.sh expected legacy cost 1.250000, got '${cost10:-<error>}'"
fi

# ==============================================================================
# Assertion 11: D5 / AT-269-11: Unpriced Gemini Models Fail Closed
# ==============================================================================
banner "D5 / AT-269-11: Unpriced Gemini Models Fail Closed"
s_unk="$(session_spend_rate_tier "gemini-9.9-flash")"
s_bare="$(session_spend_rate_tier "gemini")"
w_unk="$(work_rate_tier "gemini-9.9-flash")"
w_bare="$(work_rate_tier "gemini")"
T11="$WORK/t11"; mkdir -p "$T11"
msg "$T11/unk.jsonl" "2026-08-20T10:00:00.000Z" "gemini-9.9-flash" 1000000 0 0 0 0
rc11=0
bash "$SESSION_SPEND_SH" "$T11" --out "$WORK/o11" >/dev/null 2>&1 || rc11=$?
if [ -z "$s_unk" ] && [ -z "$s_bare" ] && [ -z "$w_unk" ] && [ -z "$w_bare" ] && [ "$rc11" -ne 0 ]; then
    pass "D5 / AT-269-11: unpriced Gemini models return empty rate tuple and fail closed with exit $rc11"
else
    fail "D5 / AT-269-11: unpriced Gemini models did not fail closed properly"
fi

# ==============================================================================
# Assertion 12: D7 / AT-269-12: docs/SPEC.md living spec documentation under ops.spend
# ==============================================================================
banner "D7 / AT-269-12: docs/SPEC.md living spec documentation under ops.spend"
# Under ops.spend, living spec must document Gemini 3.x rates referencing #269
if awk '/### ops\.spend/,/### ops\./ {print}' "$SPEC_MD" | grep -Eq '(#269|269)'; then
    pass "D7 / AT-269-12: docs/SPEC.md under ops.spend documents updated Gemini 3.x pricing referencing #269"
else
    fail "D7 / AT-269-12: docs/SPEC.md under ops.spend missing reference to #269 Gemini 3.x pricing"
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
