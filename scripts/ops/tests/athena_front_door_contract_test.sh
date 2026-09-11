#!/usr/bin/env bash
# Contract tests for Athena as the Front Door (#404).
# Cites Decisions D1, D2, D3, D4, D5, D6, D7, D9, D10, D11, D12
# and Acceptance Tests AT-1, AT-3, AT-4, AT-5, AT-6, AT-7, AT-8.
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
if grep -Fq 'stage: [intake, plan, design]' "$ATHENA_YAML"; then
    pass "D1 / AT-1: personas/athena.yaml defines stage list [intake, plan, design]"
else
    fail "D1 / AT-1: personas/athena.yaml stage list does not match [intake, plan, design]"
fi

# --- D1 / AT-1: personas/athena.yaml role description -----------------------
banner "D1 / AT-1: personas/athena.yaml role description"
# The role is a folded YAML scalar wrapped across lines in the source file;
# join lines and squeeze whitespace before matching so the wrap point does
# not split a phrase the way a raw single-line grep would.
role_joined="$(tr '\n' ' ' < "$ATHENA_YAML" | tr -s ' ')"
if printf '%s' "$role_joined" | grep -Fq 'You hold the front door of the tracker and the two gates where words become commitments' && \
   printf '%s' "$role_joined" | grep -Fq 'At INTAKE you sit with the human'; then
    pass "D1 / AT-1: personas/athena.yaml role description includes front-door contract"
else
    fail "D1 / AT-1: personas/athena.yaml role description missing front-door contract"
fi

# --- D2 / AT-1: personas/athena.yaml skills ordering ------------------------------
banner "D2 / AT-1: personas/athena.yaml skills composition and ordering"
skills_actual="$(awk '/^skills:/{f=1;next} f&&/^[^ -]/{f=0} f&&/^ *- /{sub(/^ *- */,"");print}' "$ATHENA_YAML" | tr '\n' ' ' | sed 's/ *$//')"
if [ "$skills_actual" = "intake-protocol.md product-coherence.md spec-adversary.md trusted-posting.md resume-protocol.md" ]; then
    pass "D2 / AT-1: personas/athena.yaml defines five skills in required order"
else
    fail "D2 / AT-1: personas/athena.yaml skills list does not match required 5 skills in order"
fi

# --- D3 / AT-3: personas/athena.yaml authority.paths expansion -------------------
banner "D3 / AT-3: personas/athena.yaml authority.paths"
authority_paths_actual="$(awk '/^ *paths:/{f=1;next} f&&/^ *[^ -]/{f=0} f&&/^ *- /{gsub(/"/,""); sub(/^ *- */,""); print}' "$ATHENA_YAML" | tr '\n' ' ' | sed 's/ *$//')"
if [ "$authority_paths_actual" = "intent/** README.md INTENT.md" ]; then
    pass "D3 / AT-3: personas/athena.yaml authority.paths includes README.md and INTENT.md"
else
    fail "D3 / AT-3: personas/athena.yaml authority.paths does not match ['intent/**', 'README.md', 'INTENT.md']"
fi

# --- D4 / AT-1: personas/skills/intake-protocol.md content -------------------
banner "D4 / AT-1: personas/skills/intake-protocol.md"
if [ -f "$INTAKE_SKILL" ] && \
   grep -q '^# Skill: intake-protocol' "$INTAKE_SKILL" && \
   grep -q '1. \*\*Scope first, file last.\*\*' "$INTAKE_SKILL" && \
   grep -q '## Refusals' "$INTAKE_SKILL" && \
   grep -q '## Exit condition' "$INTAKE_SKILL"; then
    pass "D4 / AT-1: personas/skills/intake-protocol.md exists with required sections"
else
    fail "D4 / AT-1: personas/skills/intake-protocol.md missing or incomplete"
fi

# --- D5 / AT-1: personas/skills/product-coherence.md content -----------------
banner "D5 / AT-1: personas/skills/product-coherence.md"
if [ -f "$COHERENCE_SKILL" ] && \
   grep -q '^# Skill: product-coherence' "$COHERENCE_SKILL" && \
   grep -q '1. \*\*Map the surfaces before you change one.\*\*' "$COHERENCE_SKILL" && \
   grep -q '2. \*\*README is concept and vision.\*\*' "$COHERENCE_SKILL" && \
   grep -q '## Exit condition' "$COHERENCE_SKILL"; then
    pass "D5 / AT-1: personas/skills/product-coherence.md exists with required sections"
else
    fail "D5 / AT-1: personas/skills/product-coherence.md missing or incomplete"
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
expected_bullet="Paths this actor's pull requests may touch: \`intent/**\`, \`README.md\`, \`INTENT.md\`"
# The compiler wraps this bullet after "README.md`," onto a two-space
# indented continuation line; join that wrap back to one line before
# matching so the wrap point does not split the expected literal.
if [ -f "$CLAUDE_TARGET" ] && [ -f "$AGY_TARGET" ] && \
   sed -e ':a' -e 'N' -e '$!ba' -e 's/,\n  /, /g' "$CLAUDE_TARGET" | grep -Fq "$expected_bullet" && \
   sed -e ':a' -e 'N' -e '$!ba' -e 's/,\n  /, /g' "$AGY_TARGET" | grep -Fq "$expected_bullet"; then
    pass "D7, D3 / AT-1, AT-3: compiled targets carry expanded authority paths bullet"
else
    fail "D7, D3 / AT-1, AT-3: compiled targets missing expanded authority paths bullet"
fi

# --- D8, D9 / AT-7: INTENT.md trailing Amendments section -----------------------------
banner "D8, D9 / AT-7: INTENT.md trailing Amendments section"
last_heading="$(grep -E '^## ' "$INTENT_MD" | tail -1 || true)"
if [ "$last_heading" = "## Amendments" ] && ! git -C "$REPO" diff origin/main -- INTENT.md | grep -Eq '^-[^-]'; then
    pass "D8, D9 / AT-7: INTENT.md ends with trailing ## Amendments section and removes no lines"
else
    fail "D8, D9 / AT-7: INTENT.md last heading is '$last_heading', expected '## Amendments', or the diff removes a line"
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

# --- D11 / AT-6: bootstrap_tracker.sh provisions duplicate and all five area:* labels -----
banner "D11 / AT-6: bootstrap_tracker.sh label provisioning declarations"
at6_missing=()
grep -Eq 'ensure_label[[:space:]]+"?duplicate"?' "$BOOTSTRAP_TRACKER" || at6_missing+=("duplicate")
for at6_label in area:personas area:ci area:ops area:docs area:harness; do
    grep -Eq "ensure_label[[:space:]]+\"?${at6_label}\"?" "$BOOTSTRAP_TRACKER" || at6_missing+=("$at6_label")
done
if [ "${#at6_missing[@]}" -eq 0 ]; then
    pass "D11 / AT-6: bootstrap_tracker.sh provisions duplicate, area:personas, area:ci, area:ops, area:docs, and area:harness through ensure_label"
else
    fail "D11 / AT-6: bootstrap_tracker.sh missing ensure_label for: ${at6_missing[*]}"
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
