import sys
content = open('scripts/ci/tests/merge_gate_test.sh').read()

replacement = r"""
# 6. Budget
cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
if [[ "$*" == *"pr view"* ]]; then
  echo '{"number":123,"body":"Refs #456","baseRefName":"main","headRepository":{"nameWithOwner":"evekhm/agentic-sdlc"},"author":{"login":"someone"},"statusCheckRollup":{"state":"SUCCESS"}}'
  exit 0
fi
if [[ "$*" == *"issue view"* ]]; then echo '{"labels":[]}'; exit 0; fi
if [[ "$*" == *"api"* ]]; then
  echo -e "<!-- loop-ledger:456 -->\n<!-- loop-ledger-row: dispatch: 1 ... -->\n<!-- loop-ledger-row: dispatch: 2 ... -->\n<!-- loop-ledger-row: dispatch: 3 ... -->\n<!-- loop-ledger-row: dispatch: 4 ... -->\n<!-- loop-ledger-row: dispatch: 5 ... -->\n<!-- loop-ledger-row: dispatch: 6 ... -->\n<!-- loop-ledger-row: dispatch: 7 ... -->\n<!-- loop-ledger-row: dispatch: 8 ... -->\n<!-- loop-ledger-row: dispatch: 9 ... -->\n<!-- loop-ledger-row: dispatch: 10 ... -->\n<!-- loop-ledger-row: dispatch: 11 ... -->\n<!-- loop-ledger-row: dispatch: 12 ... -->\n"
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

start_idx = content.find("# 6. Budget")
end_idx = content.find("echo \"merge_gate_test.sh: all scenarios passed\"")

new_content = content[:start_idx] + replacement.strip() + "\n\n" + content[end_idx:]

with open('scripts/ci/tests/merge_gate_test.sh', 'w') as f:
    f.write(new_content)
