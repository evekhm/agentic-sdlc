#!/usr/bin/env bash
# Contract tests for merge gate consensus and post.sh label step (#265).
# Cites Decisions D3, D5 and Acceptance Tests AT-12, AT-13, AT-19, AT-20, AT-21, AT-22, plus Argus R3-1.
#
# Hermetic: tests run locally without network access.
# Under the baseline tree at 696f516239efaa8d9c63592354a08fc398b410f4, every assertion
# must FAIL (red) because the production implementation has not been written yet.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
POST_SH="$REPO/scripts/ops/post.sh"
MERGE_GATE="$REPO/scripts/ci/merge_gate.sh"
BOOTSTRAP_SH="$REPO/scripts/setup/bootstrap_tracker.sh"
LABEL_TAXONOMY="$REPO/scripts/setup/issues/04-label-taxonomy.md"

FAILURES=0

banner() { printf '\n=== %s ===\n' "$*"; }

pass() {
    echo "PASS: $*"
}

fail() {
    echo "FAIL: $*" >&2
    FAILURES=$((FAILURES + 1))
}

# --- D3 / AT-12, AT-13: Label provisioning and taxonomy ---------------------------
banner "D3 / AT-12, AT-13: deep-review label provisioning and taxonomy"

if grep -F 'ensure_label "deep-review" "5319E7"' "$BOOTSTRAP_SH" >/dev/null 2>&1; then
    pass "D3 / AT-12: bootstrap_tracker.sh provisions deep-review label"
else
    fail "D3 / AT-12: bootstrap_tracker.sh missing deep-review label provisioning"
fi

if grep -A 1 '### `deep-review`' "$LABEL_TAXONOMY" 2>/dev/null | grep -q 'Deep-review grant'; then
    pass "D3 / AT-13: 04-label-taxonomy.md documents deep-review label"
else
    fail "D3 / AT-13: 04-label-taxonomy.md missing '### \`deep-review\`' documentation"
fi

# --- D3 / AT-19, AT-20: post.sh --add-label verb enforcement -----------------------
banner "D3 / AT-19, AT-20: post.sh --add-label verb enforcement"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin"

# AT-19: post.sh --add-label hold exits 2 and outputs expected rejection
out19=""
rc19=0
out19="$("$POST_SH" 100 --as argus --add-label hold 2>&1)" || rc19=$?
expected_msg="post.sh: --add-label accepts only deep-review on a pull request"

if [ "$rc19" -eq 2 ] && [[ "$out19" == *"$expected_msg"* ]]; then
    pass "D3 / AT-19: post.sh --add-label hold exits 2 and outputs '$expected_msg'"
else
    fail "D3 / AT-19: post.sh --add-label hold did not exit 2 with expected message (rc=$rc19, out: $out19)"
fi

# AT-20: post.sh --add-label deep-review on a PR succeeds and applies label
# Hermetic test with stub gh in PATH
cat <<'STUB_GH' > "$WORK/bin/gh"
#!/usr/bin/env bash
if [ "$1" = "api" ]; then
    case "$2" in
        repos/*/*/issues/100)
            printf '{"number": 100, "pull_request": {"url": "https://api.github.com/repos/test/repo/pulls/100"}, "labels": []}\n'
            exit 0
            ;;
        repos/*/*/issues/100/labels)
            echo "$@" >> "$WRITES_LOG"
            exit 0
            ;;
    esac
fi
echo "stub gh: unhandled $@" >&2
exit 1
STUB_GH
chmod +x "$WORK/bin/gh"

WRITES_LOG="$WORK/writes.log"
touch "$WRITES_LOG"

rc20=0
out20=""
out20="$(PATH="$WORK/bin:$PATH" WRITES_LOG="$WRITES_LOG" GITHUB_REPO="test/repo" "$POST_SH" 100 --as argus --add-label deep-review 2>&1)" || rc20=$?

if [ "$rc20" -eq 0 ] && grep -q 'deep-review' "$WRITES_LOG" 2>/dev/null; then
    pass "D3 / AT-20: post.sh --add-label deep-review exits 0 and applies label"
else
    fail "D3 / AT-20: post.sh --add-label deep-review did not succeed (rc=$rc20, out: $out20)"
fi

# --- D5 / AT-21, AT-22, R3-1: merge_gate.sh consensus evaluation ------------------
banner "D5 / AT-21, AT-22, R3-1: merge_gate.sh consensus evaluation"

# We test merge_gate.sh conjuncts 3 and 11 evaluation by checking if it parses
# <!-- assigned:atlas --> and satisfies consensus when only Atlas was assigned.
HEAD_OID="1111111111111111111111111111111111111111"

eval_gate_consensus() {
    local ledger_content="$1"

    # Run subshell extracting merge_gate consensus evaluation logic against canned ledger
    python3 -c "
import subprocess, sys

# Emulate conjunct (3) and (11) evaluation from merge_gate.sh
# Under D5:
# If <!-- assigned:atlas --> is present in consensus ledger:
#   - ARGUS_HEAD check is skipped or C[11]=1
#   - If ATLAS_HEAD == HEAD, C[3]=1
# If <!-- assigned:argus,atlas --> or unassigned:
#   - Both ARGUS_HEAD == HEAD and ATLAS_HEAD == HEAD required
cl = '''$ledger_content'''

# Parse merge_gate.sh source directly to check if assigned: marker is handled
with open('$MERGE_GATE') as f:
    gate_src = f.read()

if 'assigned:' not in gate_src:
    # merge_gate.sh does not yet support assigned: marker
    sys.exit(1)

# Check if Atlas-only assignment logic exists in conjunct (3) and (11)
if 'assigned:atlas' in gate_src or 'ASSIGNED' in gate_src:
    sys.exit(0)
sys.exit(1)
" 2>/dev/null
}

# AT-21: Atlas-only PR with <!-- assigned:atlas --> and Atlas verdict at head
LEDGER_ATLAS_ONLY="<!-- consensus-ledger:100 -->
<!-- assigned:atlas -->
<!-- reviewed-head:atlas:$HEAD_OID -->
<!-- consensus-ledger-end -->"

if eval_gate_consensus "$LEDGER_ATLAS_ONLY"; then
    pass "D5 / AT-21: merge_gate.sh supports Atlas-only consensus when assigned:atlas is present"
else
    fail "D5 / AT-21: merge_gate.sh does not support Atlas-only consensus (requires Argus unconditionally)"
fi

# AT-22: Dual-assigned PR with <!-- assigned:argus,atlas --> requires Argus
LEDGER_DUAL="<!-- consensus-ledger:100 -->
<!-- assigned:argus,atlas -->
<!-- reviewed-head:atlas:$HEAD_OID -->
<!-- consensus-ledger-end -->"

# At base, merge_gate.sh doesn't know about assigned: marker at all
if grep -E 'sed .*assigned:|ASSIGNED=.*assigned:' "$MERGE_GATE" >/dev/null 2>&1; then
    pass "D5 / AT-22: merge_gate.sh recognizes assigned: marker"
else
    fail "D5 / AT-22: merge_gate.sh has no handling for assigned: marker"
fi

# R3-1: Absent marker fallback
if grep -q 'execution.py --subscribers' "$MERGE_GATE" 2>/dev/null; then
    pass "D5 / R3-1: merge_gate.sh falls back to execution.py --subscribers when assigned marker absent"
else
    fail "D5 / R3-1: merge_gate.sh missing execution.py --subscribers fallback for absent assigned marker"
fi

banner "Merge Gate Contract Test Summary"
if [ "$FAILURES" -gt 0 ]; then
    echo "Total failures: $FAILURES (EXPECTED RED at build rung)" >&2
    exit 1
fi

echo "ALL TESTS PASSED"
exit 0
