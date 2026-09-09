#!/usr/bin/env bash
# Contract tests for review split execution model, parser, config, and workflow structure (#265).
# Cites Decisions D1, D2, D3, D4, D6, D7 and Acceptance Tests AT-1..AT-11, AT-14..AT-15.
#
# Every assertion cites its Decision ID and Acceptance Test ID.
# Under the baseline tree at 696f516239efaa8d9c63592354a08fc398b410f4, every assertion
# must FAIL (red) because the production implementation has not been written yet.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
EXEC_PY="$REPO/scripts/ops/execution.py"
EXEC_YAML="$REPO/config/execution.yaml"
UNATTENDED_WF="$REPO/.github/workflows/unattended.yml"
REVIEW_MD="$REPO/REVIEW.md"
REVIEW_SKILL="$REPO/personas/skills/review-protocol.md"
DEEP_REVIEW_SKILL="$REPO/personas/skills/deep-review.md"

FAILURES=0

banner() { printf '\n=== %s ===\n' "$*"; }

pass() {
    echo "PASS: $*"
}

fail() {
    echo "FAIL: $*" >&2
    FAILURES=$((FAILURES + 1))
}

# --- D1 / AT-1: config/execution.yaml schema and argus assigned_when ----------------
banner "D1 / AT-1: config/execution.yaml assigned_when for argus"

# Assertion D1: config/execution.yaml argus binding has assigned_when with required categories
if python3 -c "
import yaml, sys
with open('$EXEC_YAML') as f:
    d = yaml.safe_load(f)
argus = d.get('personas', {}).get('argus', {})
aw = argus.get('assigned_when')
if not isinstance(aw, dict):
    sys.exit(1)
req = {'status_labels', 'paths', 'labels', 'open_ledger_tiers'}
if not req.issubset(set(aw.keys())):
    sys.exit(1)
" 2>/dev/null; then
    pass "D1 / AT-1: config/execution.yaml defines assigned_when for argus with all 4 categories"
else
    fail "D1 / AT-1: config/execution.yaml missing assigned_when with required categories for argus"
fi

# Assertion D1: execution.py --check exits 0 on valid config
out="$(python3 "$EXEC_PY" --check 2>&1)" || true
if [[ "$out" == *"PASS: execution gate green"* ]] && python3 -c "
import yaml, sys
with open('$EXEC_YAML') as f:
    d = yaml.safe_load(f)
sys.exit(0 if 'assigned_when' in d.get('personas', {}).get('argus', {}) else 1)
" 2>/dev/null; then
    pass "D1 / AT-1: execution.py --check passes and validates assigned_when"
else
    fail "D1 / AT-1: execution.py --check does not pass with assigned_when in config/execution.yaml"
fi

# --- D1 / AT-2: Schema validations in execution.py --check ------------------------
banner "D1 / AT-2: Schema validations in execution.py --check"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

check_schema_rejection() {
    local dec="$1"
    local desc="$2"
    local cfg_snippet="$3"
    local expected_err="$4"

    local fixture="$TMP_DIR/exec_$RANDOM.yaml"
    cat <<YML > "$fixture"
personas:
  atlas:
    trigger: repo-event
    events: [pull_request]
    placement: gh-actions
    max_cost_usd: 8.00
  argus:
    trigger: repo-event
    events: [pull_request]
    placement: gh-actions
    max_cost_usd: 8.00
$cfg_snippet
loop:
  autonomous_merge: true
  max_rung_dispatches_per_issue: 12
  max_cost_usd_per_issue: 50.00
YML

    local out
    out="$(EXECUTION_YAML="$fixture" python3 -c "
import os, sys
os.environ['EXECUTION_YAML'] = '$fixture'
# Test execution.py loading this fixture
import importlib.util
spec = importlib.util.spec_from_file_location('execution', '$EXEC_PY')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
m.EXECUTION_YAML = __import__('pathlib').Path('$fixture')
try:
    c = m.load()
    m.check(c)
    print('PASS_UNEXPECTED')
except SystemExit as e:
    print(f'EXIT: {e}')
" 2>&1)" || true

    if [[ "$out" == *"$expected_err"* ]]; then
        pass "$dec / AT-2: $desc correctly rejected with '$expected_err'"
    else
        fail "$dec / AT-2: $desc not rejected with '$expected_err' (got: $out)"
    fi
}

check_schema_rejection "D1" "unknown key in assigned_when" \
    "    assigned_when: { unknown_key: true, status_labels: ['status:implementing'] }" \
    "ERROR: unknown key in assigned_when"

check_schema_rejection "D1" "unknown status label in status_labels" \
    "    assigned_when: { status_labels: ['status:invalid-stage'] }" \
    "ERROR: unknown status label"

check_schema_rejection "D1" "unknown severity tier in open_ledger_tiers" \
    "    assigned_when: { open_ledger_tiers: ['critical'] }" \
    "ERROR: unknown severity tier"

check_schema_rejection "D1" "assigned_when on non-pull_request event" \
    "    events: [issues]
    assigned_when: { status_labels: ['status:implementing'] }" \
    "ERROR: assigned_when allowed only for pull_request repo-events"

# --- D1 / AT-3..AT-7, AT-11: Subscribers assignment -------------------------------
banner "D1 / AT-3..AT-7, AT-11: execution.py --subscribers filtering"

# AT-3: Doc PR assignment: status:spec on spec.md -> atlas only (argus absent)
out="$(python3 "$EXEC_PY" --subscribers pull_request --status-label status:spec --paths intent/265-review-split/spec.md 2>&1)" || true
expected="$(printf 'atlas\tgh-actions')"
if [ "$out" = "$expected" ]; then
    pass "D1 / AT-3: Doc PR assigned to Atlas only"
else
    fail "D1 / AT-3: Doc PR assigned to Atlas only (got: $out, expected: $expected)"
fi

# AT-4: Code PR assignment: status:implementing on code.py -> argus and atlas
out="$(python3 "$EXEC_PY" --subscribers pull_request --status-label status:implementing --paths src/code.py 2>&1)" || true
expected="$(printf 'argus\tgh-actions\natlas\tgh-actions')"
if [ "$out" = "$expected" ]; then
    pass "D1 / AT-4: Code PR assigned to Argus and Atlas"
else
    fail "D1 / AT-4: Code PR assigned to Argus and Atlas (got: $out, expected: $expected)"
fi

# AT-5: Trust-bearing path assignment: status:spec on trust-bearing paths assigns Argus and Atlas
for tb_path in \
    ".github/workflows/unattended.yml" \
    "REVIEW.md" \
    "scripts/sync_agents.py" \
    "scripts/setup/foo.sh" \
    "AGENTS.md"; do
    out="$(python3 "$EXEC_PY" --subscribers pull_request --status-label status:spec --paths "$tb_path" 2>&1)" || true
    expected="$(printf 'argus\tgh-actions\natlas\tgh-actions')"
    if [ "$out" = "$expected" ]; then
        pass "D1 / AT-5: Trust-bearing path $tb_path assigned to Argus and Atlas"
    else
        fail "D1 / AT-5: Trust-bearing path $tb_path assigned to Argus and Atlas (got: $out, expected: $expected)"
    fi
done

# AT-6: Label assignment via deep-review: status:planning with deep-review -> argus and atlas
out="$(python3 "$EXEC_PY" --subscribers pull_request --status-label status:planning --paths intent/100-test/intent.md --labels deep-review 2>&1)" || true
expected="$(printf 'argus\tgh-actions\natlas\tgh-actions')"
if [ "$out" = "$expected" ]; then
    pass "D1 / AT-6: deep-review label assigns Argus and Atlas"
else
    fail "D1 / AT-6: deep-review label assigns Argus and Atlas (got: $out, expected: $expected)"
fi

# AT-7: Open security row assignment: status:build with open-ledger security -> argus and atlas
out="$(python3 "$EXEC_PY" --subscribers pull_request --status-label status:build --paths intent/100-test/plan.md --open-ledger security 2>&1)" || true
expected="$(printf 'argus\tgh-actions\natlas\tgh-actions')"
if [ "$out" = "$expected" ]; then
    pass "D1 / AT-7: Open security row in ledger assigns Argus and Atlas"
else
    fail "D1 / AT-7: Open security row in ledger assigns Argus and Atlas (got: $out, expected: $expected)"
fi

# AT-11: Fail-closed rung resolution: missing --status-label assigns both argus and atlas
out="$(python3 "$EXEC_PY" --subscribers pull_request --paths intent/265-review-split/spec.md 2>&1)" || true
expected="$(printf 'argus\tgh-actions\natlas\tgh-actions')"
if [ "$out" = "$expected" ]; then
    pass "D1 / AT-11: Missing status label fails closed to dual assignment"
else
    fail "D1 / AT-11: Missing status label fails closed to dual assignment (got: $out, expected: $expected)"
fi

# --- D2 / AT-8..AT-10: Action and draft flags in execution.py --subscribers --------
banner "D2 / AT-8..AT-10: Action and draft flags in execution.py --subscribers"

# AT-8: Action synchronize dispatches only assigned reviewers
# On doc PR (Argus not assigned under D1): dispatches only Atlas
out="$(python3 "$EXEC_PY" --subscribers pull_request --action synchronize --status-label status:spec --paths docs/foo.md 2>&1)" || true
expected="$(printf 'atlas\tgh-actions')"
if [ "$out" = "$expected" ]; then
    pass "D2 / AT-8: action synchronize on doc PR dispatches only Atlas"
else
    fail "D2 / AT-8: action synchronize on doc PR dispatches only Atlas (got: $out, expected: $expected)"
fi
# On code PR (Argus assigned under D1): dispatches both Argus and Atlas
out="$(python3 "$EXEC_PY" --subscribers pull_request --action synchronize --status-label status:implementing --paths src/code.py 2>&1)" || true
expected="$(printf 'argus\tgh-actions\natlas\tgh-actions')"
if [ "$out" = "$expected" ]; then
    pass "D2 / AT-8: action synchronize on code PR dispatches both Argus and Atlas"
else
    fail "D2 / AT-8: action synchronize on code PR dispatches both Argus and Atlas (got: $out, expected: $expected)"
fi

# AT-9: Draft PR skip
out="$(python3 "$EXEC_PY" --subscribers pull_request --draft --status-label status:implementing --paths src/code.py 2>&1)" || true
if [ -z "$out" ]; then
    pass "D2 / AT-9: draft PR skips subscribers (empty output)"
else
    fail "D2 / AT-9: draft PR should output nothing (got: $out)"
fi

# AT-10: Action ready_for_review dispatches only assigned reviewers
# On doc PR (Argus not assigned under D1): dispatches only Atlas
out="$(python3 "$EXEC_PY" --subscribers pull_request --action ready_for_review --status-label status:spec --paths docs/foo.md 2>&1)" || true
expected="$(printf 'atlas\tgh-actions')"
if [ "$out" = "$expected" ]; then
    pass "D2 / AT-10: action ready_for_review on doc PR dispatches only Atlas"
else
    fail "D2 / AT-10: action ready_for_review on doc PR dispatches only Atlas (got: $out, expected: $expected)"
fi
# On code PR (Argus assigned under D1): dispatches both Argus and Atlas
out="$(python3 "$EXEC_PY" --subscribers pull_request --action ready_for_review --status-label status:implementing --paths src/code.py 2>&1)" || true
expected="$(printf 'argus\tgh-actions\natlas\tgh-actions')"
if [ "$out" = "$expected" ]; then
    pass "D2 / AT-10: action ready_for_review on code PR dispatches both Argus and Atlas"
else
    fail "D2 / AT-10: action ready_for_review on code PR dispatches both Argus and Atlas (got: $out, expected: $expected)"
fi

# --- D3 / AT-14: Duplicate deep-review grant refusal in execution.py -----------------
banner "D3 / AT-14: execution.py --check-grant spend cap"

out="$(python3 "$EXEC_PY" --check-grant --pr 100 --rung design --existing-grants design 2>&1)" || true
expected="Refused: PR #100 already received a deep-review grant on the 'design' rung. Policy allows at most one deep-review grant per PR per rung (REVIEW.md, #265). Escalating to human."
if [[ "$out" == *"$expected"* ]]; then
    pass "D3 / AT-14: duplicate grant refused with expected message"
else
    fail "D3 / AT-14: duplicate grant refusal missing or incorrect (got: $out)"
fi

# Contract assertion (F-1): workflow timeline construction of existing-grants refuses second grant
timeline_fixture='[
  {"event": "labeled", "label": {"name": "deep-review"}, "created_at": "2026-09-09T18:00:00Z"},
  {"event": "unlabeled", "label": {"name": "deep-review"}, "created_at": "2026-09-09T18:00:05Z"},
  {"event": "labeled", "label": {"name": "deep-review"}, "created_at": "2026-09-09T18:05:00Z"}
]'
existing_from_timeline="$(jq -r --arg rung "design" '[.[] | select(.event == "labeled" and .label.name == "deep-review")] | if length > 1 then (.[0:-1][] | (.rung // $rung)) else empty end' <<<"$timeline_fixture")"
out_tl="$(python3 "$EXEC_PY" --check-grant --pr 100 --rung design --existing-grants $existing_from_timeline 2>&1)" || true
if [[ "$out_tl" == *"$expected"* ]]; then
    pass "D3 / AT-14 / F-1: second grant on same rung refused when existing-grants built from timeline fixture"
else
    fail "D3 / AT-14 / F-1: second grant on same rung not refused from timeline fixture (got: $out_tl)"
fi

# --- D4 / AT-15: Diff rules evaluation in execution.py ------------------------------
banner "D4 / AT-15: execution.py --diff-rules evaluation"

out1="$(python3 "$EXEC_PY" --diff-rules --lines 401 --paths src/code.py 2>&1)" || true
if [ "$out1" = "deep-review" ]; then
    pass "D4 / AT-15: lines > 400 triggers deep-review (DEEP-2)"
else
    fail "D4 / AT-15: lines > 400 triggers deep-review (got: $out1)"
fi

out1b="$(python3 "$EXEC_PY" --diff-rules --files 13 --paths src/code.py 2>&1)" || true
if [ "$out1b" = "deep-review" ]; then
    pass "D4 / AT-15: files > 12 triggers deep-review (DEEP-2)"
else
    fail "D4 / AT-15: files > 12 triggers deep-review (got: $out1b)"
fi

out2="$(python3 "$EXEC_PY" --diff-rules --lines 50 --paths scripts/auth/mint_app_token.py 2>&1)" || true
if [ "$out2" = "deep-review" ]; then
    pass "D4 / AT-15: trust-bearing path triggers deep-review (DEEP-1)"
else
    fail "D4 / AT-15: trust-bearing path triggers deep-review (got: $out2)"
fi

out3="$(python3 "$EXEC_PY" --diff-rules --lines 50 --files 5 --paths intent/265-review-split/spec.md 2>&1)" || true
if [ -z "$out3" ]; then
    pass "D4 / AT-15: doc path under threshold emits empty"
else
    fail "D4 / AT-15: doc path under threshold emits empty (got: $out3)"
fi

# --- D2, D3 / R3-2: Unattended workflow structure -----------------------------------
banner "D2, D3 / R3-2: .github/workflows/unattended.yml structure"

# Check on.pull_request.types has ready_for_review and labeled
types="$(python3 -c "
import yaml
with open('$UNATTENDED_WF') as f:
    d = yaml.safe_load(f)
t = d.get('on', d.get(True, {})).get('pull_request', {}).get('types', [])
print(' '.join(sorted(t)))
" 2>/dev/null)" || true

if [[ "$types" == *"ready_for_review"* ]] && [[ "$types" == *"labeled"* ]]; then
    pass "D2, D3: unattended.yml pull_request triggers on ready_for_review and labeled"
else
    fail "D2, D3: unattended.yml pull_request types missing ready_for_review or labeled (got: $types)"
fi

# Check draft PR skip logic in resolve job
if grep -q 'github.event.pull_request.draft' "$UNATTENDED_WF" 2>/dev/null; then
    pass "D2: unattended.yml inspects pull_request.draft"
else
    fail "D2: unattended.yml missing pull_request.draft inspection"
fi

# Check labeled event grant check and Argus dispatch sequencing (R3-2)
if grep -q -- '--check-grant' "$UNATTENDED_WF" 2>/dev/null; then
    pass "D3 / R3-2: unattended.yml sequences --check-grant before deep-review dispatch"
else
    fail "D3 / R3-2: unattended.yml missing --check-grant sequencing before deep-review dispatch"
fi

# --- D4: personas/skills/deep-review.md and persona declarations --------------------
banner "D4: personas/skills/deep-review.md and persona declarations"

if [ -f "$DEEP_REVIEW_SKILL" ] && grep -q 'DEEP-1' "$DEEP_REVIEW_SKILL" && grep -q 'DEEP-7' "$DEEP_REVIEW_SKILL"; then
    pass "D4: personas/skills/deep-review.md exists and covers DEEP-1..DEEP-7"
else
    fail "D4: personas/skills/deep-review.md missing or does not cover DEEP-1..DEEP-7"
fi

for persona in argus atlas daedalus odyssey cassandra; do
    pfile="$REPO/personas/$persona.yaml"
    if grep -q 'deep-review.md' "$pfile" 2>/dev/null; then
        pass "D4: persona $persona declares deep-review.md"
    else
        fail "D4: persona $persona does not declare deep-review.md"
    fi
done

# --- D6, D7: REVIEW.md verification protocol and policy text -----------------------
banner "D6, D7: REVIEW.md verification protocol and policy text"

if grep -q '^## The verification protocol' "$REVIEW_MD" 2>/dev/null; then
    pass "D6: REVIEW.md contains '## The verification protocol'"
else
    fail "D6: REVIEW.md missing '## The verification protocol' section"
fi

if grep -q 'Atlas reviews every PR at every rung; Argus joins at the code gate' "$REVIEW_MD" 2>/dev/null; then
    pass "D7: REVIEW.md line 8 carries two-tier review assignment summary"
else
    fail "D7: REVIEW.md missing two-tier review assignment summary on line 8"
fi

if grep -q '^## Asking for more: the deep-review grant' "$REVIEW_MD" 2>/dev/null; then
    pass "D7: REVIEW.md carries '## Asking for more: the deep-review grant' (with colon)"
else
    fail "D7: REVIEW.md missing '## Asking for more: the deep-review grant'"
fi

if grep -q 'The verification protocol' "$REVIEW_SKILL" 2>/dev/null; then
    pass "D6: review-protocol.md references '## The verification protocol' in REVIEW.md"
else
    fail "D6: review-protocol.md does not reference '## The verification protocol'"
fi

banner "Review Split Contract Test Summary"
if [ "$FAILURES" -gt 0 ]; then
    echo "Total failures: $FAILURES (EXPECTED RED at build rung)" >&2
    exit 1
fi

echo "ALL TESTS PASSED"
exit 0
