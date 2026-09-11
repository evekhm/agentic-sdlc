#!/usr/bin/env bash
# Contract tests for Athena as the Front Door (#404).
# Cites Decisions D1, D2, D3, D4, D5, D6, D7, D9, D10, D11, D12
# and Acceptance Tests AT-1, AT-2, AT-3, AT-4, AT-5, AT-6, AT-7, AT-8.
#
# Every assertion cites its Decision ID and Acceptance Test ID.
# Under the baseline tree at 2764617, every assertion must FAIL (red)
# because the production implementation has not been written yet.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$REPO"

ATHENA_YAML="$REPO/personas/athena.yaml"
INTAKE_SKILL="$REPO/personas/skills/intake-protocol.md"
COHERENCE_SKILL="$REPO/personas/skills/product-coherence.md"
ADVERSARY_SKILL="$REPO/personas/skills/spec-adversary.md"
CLAUDE_TARGET="$REPO/.claude/agents/athena.md"
AGY_TARGET="$REPO/.agents/agents/athena/agent.md"
INTENT_MD="$REPO/INTENT.md"
TRACKER_SEARCH="$REPO/scripts/ops/tracker_search.sh"
BOOTSTRAP_TRACKER="$REPO/scripts/setup/bootstrap_tracker.sh"
README_MD="$REPO/README.md"

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

# --- D1 / AT-1: personas/athena.yaml stage list includes intake --------------------
banner "D1 / AT-1: personas/athena.yaml stage list"
if python3 -c "
import yaml, sys
with open('$ATHENA_YAML') as f:
    d = yaml.safe_load(f)
stages = d.get('stage', [])
if stages == ['intake', 'plan', 'design']:
    sys.exit(0)
sys.exit(1)
" 2>/dev/null; then
    pass "D1 / AT-1: personas/athena.yaml defines stage list [intake, plan, design]"
else
    fail "D1 / AT-1: personas/athena.yaml stage list does not match [intake, plan, design]"
fi

# --- D1 / AT-1, AT-2: personas/athena.yaml role description -----------------------
banner "D1 / AT-1, AT-2: personas/athena.yaml role description"
if python3 -c "
import yaml, sys
with open('$ATHENA_YAML') as f:
    d = yaml.safe_load(f)
role = d.get('role', '')
req = 'You hold the front door of the tracker and the two gates where words become commitments'
if req in role and 'At INTAKE you sit with the human' in role:
    sys.exit(0)
sys.exit(1)
" 2>/dev/null; then
    pass "D1 / AT-1, AT-2: personas/athena.yaml role description includes front-door contract"
else
    fail "D1 / AT-1, AT-2: personas/athena.yaml role description missing front-door contract"
fi

# --- D2 / AT-1: personas/athena.yaml skills ordering ------------------------------
banner "D2 / AT-1: personas/athena.yaml skills composition and ordering"
if python3 -c "
import yaml, sys
with open('$ATHENA_YAML') as f:
    d = yaml.safe_load(f)
skills = d.get('skills', [])
expected = [
    'intake-protocol.md',
    'product-coherence.md',
    'spec-adversary.md',
    'trusted-posting.md',
    'resume-protocol.md',
]
if skills == expected:
    sys.exit(0)
sys.exit(1)
" 2>/dev/null; then
    pass "D2 / AT-1: personas/athena.yaml defines five skills in required order"
else
    fail "D2 / AT-1: personas/athena.yaml skills list does not match required 5 skills in order"
fi

# --- D3 / AT-3: personas/athena.yaml authority.paths expansion -------------------
banner "D3 / AT-3: personas/athena.yaml authority.paths"
if python3 -c "
import yaml, sys
with open('$ATHENA_YAML') as f:
    d = yaml.safe_load(f)
paths = d.get('authority', {}).get('paths', [])
expected = ['intent/**', 'README.md', 'INTENT.md']
if paths == expected:
    sys.exit(0)
sys.exit(1)
" 2>/dev/null; then
    pass "D3 / AT-3: personas/athena.yaml authority.paths includes README.md and INTENT.md"
else
    fail "D3 / AT-3: personas/athena.yaml authority.paths does not match ['intent/**', 'README.md', 'INTENT.md']"
fi

# --- D4 / AT-1, AT-2: personas/skills/intake-protocol.md content -------------------
banner "D4 / AT-1, AT-2: personas/skills/intake-protocol.md"
if [ -f "$INTAKE_SKILL" ] && \
   grep -q '^# Skill: intake-protocol' "$INTAKE_SKILL" && \
   grep -q '1. \*\*Scope first, file last.\*\*' "$INTAKE_SKILL" && \
   grep -q '## Refusals' "$INTAKE_SKILL" && \
   grep -q '## Exit condition' "$INTAKE_SKILL"; then
    pass "D4 / AT-1, AT-2: personas/skills/intake-protocol.md exists with required sections"
else
    fail "D4 / AT-1, AT-2: personas/skills/intake-protocol.md missing or incomplete"
fi

# --- D5 / AT-1, AT-2: personas/skills/product-coherence.md content -----------------
banner "D5 / AT-1, AT-2: personas/skills/product-coherence.md"
if [ -f "$COHERENCE_SKILL" ] && \
   grep -q '^# Skill: product-coherence' "$COHERENCE_SKILL" && \
   grep -q '1. \*\*Map the surfaces before you change one.\*\*' "$COHERENCE_SKILL" && \
   grep -q '2. \*\*README is concept and vision.\*\*' "$COHERENCE_SKILL" && \
   grep -q '## Exit condition' "$COHERENCE_SKILL"; then
    pass "D5 / AT-1, AT-2: personas/skills/product-coherence.md exists with required sections"
else
    fail "D5 / AT-1, AT-2: personas/skills/product-coherence.md missing or incomplete"
fi

# --- D6 / AT-1: personas/skills/spec-adversary.md additions -----------------------
banner "D6 / AT-1: personas/skills/spec-adversary.md rules 6-8"
if grep -q '6. \*\*Every acceptance row can fail.\*\*' "$ADVERSARY_SKILL" && \
   grep -q '7. \*\*Neighbours first.\*\*' "$ADVERSARY_SKILL" && \
   grep -q '8. \*\*One pass for self-contradiction.\*\*' "$ADVERSARY_SKILL"; then
    pass "D6 / AT-1: personas/skills/spec-adversary.md contains rules 6, 7, and 8"
else
    fail "D6 / AT-1: personas/skills/spec-adversary.md missing rules 6, 7, or 8"
fi

# --- D7, D3 / AT-1, AT-3: compiled targets carry authority paths -------------------
banner "D7, D3 / AT-1, AT-3: compiled target authority paths"
if [ -f "$CLAUDE_TARGET" ] && [ -f "$AGY_TARGET" ] && python3 -c "
import sys
expected = \"Paths this actor's pull requests may touch: \`intent/**\`, \`README.md\`, \`INTENT.md\`\"
for p in sys.argv[1:]:
    with open(p) as f:
        text = ' '.join(f.read().split())
    if ' '.join(expected.split()) not in text:
        sys.exit(1)
sys.exit(0)
" "$CLAUDE_TARGET" "$AGY_TARGET" 2>/dev/null; then
    pass "D7, D3 / AT-1, AT-3: compiled targets carry expanded authority paths bullet"
else
    fail "D7, D3 / AT-1, AT-3: compiled targets missing expanded authority paths bullet"
fi

# --- D9 / AT-7: INTENT.md trailing Amendments section -----------------------------
banner "D9 / AT-7: INTENT.md trailing Amendments section"
last_heading="$(grep -E '^## ' "$INTENT_MD" | tail -1 || true)"
if [ "$last_heading" = "## Amendments" ]; then
    pass "D9 / AT-7: INTENT.md ends with trailing ## Amendments section"
else
    fail "D9 / AT-7: INTENT.md last heading is '$last_heading', expected '## Amendments'"
fi

# --- D10 / AT-4: tracker_search.sh --decisions matching query --------------------
banner "D10 / AT-4: tracker_search.sh --decisions with matching term"
matching_out="$(bash "$TRACKER_SEARCH" --decisions FRONTIER 2>&1)"
matching_status=$?
if [ "$matching_status" -eq 2 ] && \
   echo "$matching_out" | grep -Eq '^intent/[^:]+/spec.md:[0-9]+:'; then
    pass "D10 / AT-4: tracker_search.sh --decisions matches rows, prints <file>:<line>: <row>, exits 2"
else
    fail "D10 / AT-4: tracker_search.sh --decisions failed matching check (status=$matching_status)"
fi

# --- D10 / AT-5: tracker_search.sh --decisions non-matching query -----------------
banner "D10 / AT-5: tracker_search.sh --decisions with non-matching term"
nonmatching_out="$(bash "$TRACKER_SEARCH" --decisions nonexistenttermxyz123 2>&1)"
nonmatching_status=$?
nonmatching_lines="$(echo "$nonmatching_out" | grep -v '^$' | wc -l || true)"
if [ "$nonmatching_status" -eq 0 ] && [ "$nonmatching_lines" -eq 0 ]; then
    pass "D10 / AT-5: tracker_search.sh --decisions with non-matching term prints 0 lines and exits 0"
else
    fail "D10 / AT-5: tracker_search.sh --decisions failed non-matching check (status=$nonmatching_status, lines=$nonmatching_lines)"
fi

# --- D11 / AT-6: bootstrap_tracker.sh provisions duplicate and area:* labels -------
banner "D11 / AT-6: bootstrap_tracker.sh label provisioning declarations"
if grep -q 'ensure_label "duplicate"' "$BOOTSTRAP_TRACKER" && \
   grep -q 'ensure_label "area:personas"' "$BOOTSTRAP_TRACKER" && \
   grep -q 'ensure_label "area:ci"' "$BOOTSTRAP_TRACKER" && \
   grep -q 'ensure_label "area:ops"' "$BOOTSTRAP_TRACKER" && \
   grep -q 'ensure_label "area:docs"' "$BOOTSTRAP_TRACKER" && \
   grep -q 'ensure_label "area:harness"' "$BOOTSTRAP_TRACKER"; then
    pass "D11 / AT-6: bootstrap_tracker.sh provisions duplicate and area:* labels"
else
    fail "D11 / AT-6: bootstrap_tracker.sh missing duplicate or area:* label provisioning"
fi

# --- D12 / AT-8: README.md Athena interactive entry point -------------------------
banner "D12 / AT-8: README.md Athena interactive entry point"
if grep -q 'claude --agent athena' "$README_MD" && \
   grep -q '\.agents/agents/athena' "$README_MD"; then
    pass "D12 / AT-8: README.md documents interactive entry points for Athena"
else
    fail "D12 / AT-8: README.md missing interactive entry points for Athena"
fi

# --- Test Summary -----------------------------------------------------------------
banner "Summary"
echo "Total: $TOTAL, Passed: $PASSED, Failed: $FAILURES"

if [ "$FAILURES" -gt 0 ]; then
    exit 1
fi
exit 0
