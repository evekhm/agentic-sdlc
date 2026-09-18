#!/usr/bin/env bash
# Standalone Test Suite Verdict Integrity Test Suite (#405).
# Cites Decisions D1, D2, D3, D4, D5, D6, D7, D8 and Acceptance Tests AT-405-1 through AT-405-11.
# Spec: intent/405-nothing-proves-a-test/spec.md (Approved)
#
# Mechanically proves test suite verdict integrity:
# Proof 1 (Null-Implementation Proof): candidate suite fails closed (exit nonzero) on exit 0 stub.
# Proof 2 (Ambient-Environment Proof): candidate suites pass (exit 0) under hostile ambient variables.
# Proof 3 (Static Audit): scans shell test scripts for in-memory failure counter modification inside subshells.

set -uo pipefail

# D3 (issue #405): Self-sanitizing at entry
unset CLAUDE_SEAT AGENTIC_SEAT WORK_MAX_USD

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WRAP_TEST="$REPO/scripts/ops/tests/wrap_test.sh"
HARNESS_TEST="$REPO/scripts/ops/tests/harness_test.sh"
PLACEMENT_TEST="$REPO/scripts/ops/tests/placement_test.sh"

FAIL_LOG="$(mktemp "${TMPDIR:-/tmp}/suite_integrity_test_fails.XXXXXX")"
export FAIL_LOG
FAILURES=0
TOTAL=0
PASSED=0

cleanup() {
    rm -f "$FAIL_LOG"
}
trap cleanup EXIT

banner() { printf '\n=== %s ===\n' "$*"; }

pass() {
    TOTAL=$((TOTAL + 1))
    PASSED=$((PASSED + 1))
    echo "PASS: $*"
}

fail() {
    TOTAL=$((TOTAL + 1))
    echo "FAIL: $*" >&2
    echo "1" >> "$FAIL_LOG"
}

# ==============================================================================
# Proof 1 (Null-Implementation Proof)
# ==============================================================================
banner "Proof 1 (Null-Implementation Proof): wrap_test.sh fails closed on null implementation stub"
STUB="$(mktemp "${TMPDIR:-/tmp}/stub_null_wrap.XXXXXX")"
cat <<'EOF' > "$STUB"
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$STUB"

rc=0
WRAP_SH="$STUB" bash "$WRAP_TEST" >/dev/null 2>&1 || rc=$?
rm -f "$STUB"

if [ "$rc" -ne 0 ]; then
    pass "Proof 1 (Null-Implementation Proof): wrap_test.sh failed closed (rc=$rc) against null stub"
else
    fail "Proof 1 (Null-Implementation Proof): wrap_test.sh exited 0 against null stub (false-green anti-pattern)"
fi

# ==============================================================================
# Proof 2 (Ambient-Environment Proof)
# ==============================================================================
banner "Proof 2 (Ambient-Environment Proof): Candidate suites pass under hostile ambient variables"
# Candidate 1: harness_test.sh
if CLAUDE_SEAT=polluter-seat AGENTIC_SEAT=polluter-agent WORK_MAX_USD=9999.00 bash "$HARNESS_TEST" >/dev/null 2>&1; then
    pass "Proof 2 (Ambient-Environment Proof): harness_test.sh exits 0 under hostile ambient variables"
else
    fail "Proof 2 (Ambient-Environment Proof): harness_test.sh failed under hostile ambient variables"
fi

# Candidate 2: placement_test.sh
if CLAUDE_SEAT=polluter-seat AGENTIC_SEAT=polluter-agent WORK_MAX_USD=9999.00 bash "$PLACEMENT_TEST" >/dev/null 2>&1; then
    pass "Proof 2 (Ambient-Environment Proof): placement_test.sh exits 0 under hostile ambient variables"
else
    fail "Proof 2 (Ambient-Environment Proof): placement_test.sh failed under hostile ambient variables"
fi

# Candidate 3: wrap_test.sh
if CLAUDE_SEAT=polluter-seat AGENTIC_SEAT=polluter-agent WORK_MAX_USD=9999.00 bash "$WRAP_TEST" >/dev/null 2>&1; then
    pass "Proof 2 (Ambient-Environment Proof): wrap_test.sh exits 0 under hostile ambient variables"
else
    fail "Proof 2 (Ambient-Environment Proof): wrap_test.sh failed under hostile ambient variables"
fi

# ==============================================================================
# Proof 3 (Static Audit)
# ==============================================================================
banner "Proof 3 (Static Audit): No in-memory failure counter modification inside subshells"
if audit_out="$(python3 -c '
import glob, re, sys

all_issues = []
for path in sorted(glob.glob("scripts/*/tests/*.sh")):
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        lines = f.readlines()
    depth = 0
    subshell_start = []
    for idx, line in enumerate(lines, 1):
        stripped = line.strip()
        if stripped.startswith("#"):
            continue
        cleaned = re.sub(r"\$\(\([^\)]*\)\)", "", stripped)
        cleaned = re.sub(r"\$\([^\)]*\)", "", cleaned)
        cleaned = re.sub(r"\(\([^\)]*\)\)", "", cleaned)
        cleaned = re.sub(r"[a-zA-Z0-9_-]+\(\)\s*\{", "", cleaned)
        
        if re.match(r"^\(\s*$", stripped) or (stripped.startswith("(") and not stripped.startswith("((") and not stripped.startswith("()")):
            depth += 1
            subshell_start.append(idx)
        
        if depth > 0:
            if re.search(r"\bFAILURES\s*(\+|\$)?=", stripped) or re.search(r"\bFAILURES\+\+", stripped):
                all_issues.append(f"{path}:{idx}: in-memory failure counter modification inside subshell: {stripped}")
                
        if re.match(r"^\)\s*(;|&&|\|\|)?\s*$", stripped) or (stripped.endswith(")") and not stripped.endswith("))") and not stripped.startswith("case")):
            if depth > 0:
                depth -= 1
                subshell_start.pop()

if all_issues:
    for iss in all_issues:
        print(iss)
    sys.exit(1)
sys.exit(0)
' 2>&1)"; then
    pass "Proof 3 (Static Audit): all shell test suites verified clean of in-memory subshell counter mutations"
else
    fail "Proof 3 (Static Audit): detected in-memory subshell counter anti-pattern: $audit_out"
fi

# ==============================================================================
# Summary
# ==============================================================================
banner "Suite Integrity Summary"
FAILURES=$(wc -l < "$FAIL_LOG" 2>/dev/null | tr -d ' ')
FAILURES="${FAILURES:-0}"
echo "Total assertions: $TOTAL"
echo "Passed:           $PASSED"
echo "Failed:           $FAILURES"

if [ "$FAILURES" -gt 0 ]; then
    echo "Suite integrity failures: $FAILURES" >&2
    exit 1
fi

echo "ALL SUITE INTEGRITY PROOFS PASSED"
exit 0
