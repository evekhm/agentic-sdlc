import sys
content = open('scripts/ci/tests/merge_gate_test.sh').read()

replacement = """
# R1-9 test gaps
# 1. Missing limits
cat > "$WORK/bin/python3" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
bash "$MERGE_GATE" 123 2> stderr.log || true
if ! grep -q "Failed to read loop limits. Failing closed." stderr.log; then
  cat stderr.log >&2
  fail "Failed to decline on missing limits"
fi
pass "Fails closed on missing limits"

# Restore python3
cat > "$WORK/bin/python3" <<'STUB'
#!/usr/bin/env bash
if [[ "$*" == *"--loop max_rung_dispatches_per_issue"* ]]; then echo "12"; exit 0; fi
if [[ "$*" == *"--loop max_cost_usd_per_issue"* ]]; then echo "50.00"; exit 0; fi
if [[ "$*" == *"--loop autonomous_merge"* ]]; then echo "true"; exit 0; fi
exec /usr/bin/python3 "$@"
STUB
chmod +x "$WORK/bin/python3"

# 2. Fork branch (D5-1)
cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
if [[ "$*" == *"pr view"* ]]; then
  echo '{"number":123,"body":"Refs #456","baseRefName":"main","headRepository":{"nameWithOwner":"fork/agentic-sdlc"},"author":{"login":"someone"},"statusCheckRollup":{"state":"SUCCESS"}}'
  exit 0
fi
if [[ "$*" == *"issue view"* ]]; then echo '{"labels":[]}'; exit 0; fi
if [[ "$*" == *"api"* ]]; then echo '[]'; exit 0; fi
STUB
bash "$MERGE_GATE" 123 2> stderr.log || true
if ! grep -q "Decline: Fork branch not allowed" stderr.log; then
  cat stderr.log >&2
  fail "Failed to decline fork branch"
fi
pass "Fails on fork branch"

# 3. Merger == Author (D5-7)
cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
if [[ "$*" == *"pr view"* ]]; then
  echo '{"number":123,"body":"Refs #456","baseRefName":"main","headRepository":{"nameWithOwner":"evekhm/agentic-sdlc"},"author":{"login":"evekhm-merge-actor-app[bot]"},"statusCheckRollup":{"state":"SUCCESS"}}'
  exit 0
fi
if [[ "$*" == *"issue view"* ]]; then echo '{"labels":[]}'; exit 0; fi
if [[ "$*" == *"api"* ]]; then echo '[]'; exit 0; fi
STUB
bash "$MERGE_GATE" 123 2> stderr.log || true
if ! grep -q "Decline: Merger cannot be author" stderr.log; then
  cat stderr.log >&2
  fail "Failed to decline merger==author"
fi
pass "Fails on merger == author"

# 4. Checks missing (D5-2)
cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
if [[ "$*" == *"pr view"* ]]; then
  echo '{"number":123,"body":"Refs #456","baseRefName":"main","headRepository":{"nameWithOwner":"evekhm/agentic-sdlc"},"author":{"login":"someone"},"statusCheckRollup":null}'
  exit 0
fi
if [[ "$*" == *"issue view"* ]]; then echo '{"labels":[]}'; exit 0; fi
if [[ "$*" == *"api"* ]]; then echo '[]'; exit 0; fi
STUB
bash "$MERGE_GATE" 123 2> stderr.log || true
if ! grep -q "Decline: checks missing" stderr.log; then
  cat stderr.log >&2
  fail "Failed to decline on missing checks"
fi
pass "Fails on missing checks"

# 5. Hold/Blocked
cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
if [[ "$*" == *"pr view"* ]]; then
  echo '{"number":123,"body":"Refs #456","baseRefName":"main","headRepository":{"nameWithOwner":"evekhm/agentic-sdlc"},"author":{"login":"someone"},"statusCheckRollup":{"state":"SUCCESS"},"labels":[{"name":"hold"}]}'
  exit 0
fi
if [[ "$*" == *"issue view"* ]]; then echo '{"labels":[]}'; exit 0; fi
if [[ "$*" == *"api"* ]]; then echo '[]'; exit 0; fi
STUB
bash "$MERGE_GATE" 123 2> stderr.log || true
if ! grep -q "halted by hold or blocked" stderr.log; then
  cat stderr.log >&2
  fail "Failed to halt on hold label"
fi
pass "Halts on hold label"

# 6. Budget
cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
if [[ "$*" == *"pr view"* ]]; then
  echo '{"number":123,"body":"Refs #456","baseRefName":"main","headRepository":{"nameWithOwner":"evekhm/agentic-sdlc"},"author":{"login":"someone"},"statusCheckRollup":{"state":"SUCCESS"}}'
  exit 0
fi
if [[ "$*" == *"issue view"* ]]; then echo '{"labels":[]}'; exit 0; fi
if [[ "$*" == *"api"* ]]; then
  echo '["<!-- loop-ledger:456 -->\\n<!-- loop-ledger-row: dispatch: 1 ... -->\\n<!-- loop-ledger-row: dispatch: 2 ... -->\\n<!-- loop-ledger-row: dispatch: 3 ... -->\\n<!-- loop-ledger-row: dispatch: 4 ... -->\\n<!-- loop-ledger-row: dispatch: 5 ... -->\\n<!-- loop-ledger-row: dispatch: 6 ... -->\\n<!-- loop-ledger-row: dispatch: 7 ... -->\\n<!-- loop-ledger-row: dispatch: 8 ... -->\\n<!-- loop-ledger-row: dispatch: 9 ... -->\\n<!-- loop-ledger-row: dispatch: 10 ... -->\\n<!-- loop-ledger-row: dispatch: 11 ... -->\\n<!-- loop-ledger-row: dispatch: 12 ... -->"]'
  exit 0
fi
if [[ "$*" == *"issue comment"* ]]; then exit 0; fi
STUB
bash "$MERGE_GATE" 123 2> stderr.log || true
if ! grep -q "max_rung_dispatches_per_issue exceeded" stderr.log; then
  cat stderr.log >&2
  fail "Failed to halt on budget exceeded"
fi
pass "Halts on budget exceeded"

"""

start_idx = content.find("echo \"merge_gate_test.sh: all scenarios passed\"")

new_content = content[:start_idx] + replacement.strip() + "\n\n" + content[start_idx:]

with open('scripts/ci/tests/merge_gate_test.sh', 'w') as f:
    f.write(new_content)
