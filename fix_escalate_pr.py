import sys
content = open('scripts/ci/escalate.sh').read()

replacement = """
# D15 Check hold / blocked on issue and PR
ISSUE_JSON=$(gh issue view "$ISSUE" --json labels -q '.' 2>/dev/null || true)
if [[ -z "$ISSUE_JSON" ]]; then
  echo "Decline: Could not read issue labels." >&2
  exit 1
fi
ISSUE_LABELS=$(jq -r '.labels[].name' <<<"$ISSUE_JSON" 2>/dev/null || echo "")

PR_LABELS=""
if [[ -n "$PR" ]]; then
  PR_JSON=$(gh pr view "$PR" --json labels -q '.' 2>/dev/null || true)
  if [[ -n "$PR_JSON" ]]; then
    PR_LABELS=$(jq -r '.labels[].name' <<<"$PR_JSON" 2>/dev/null || echo "")
  fi
fi

if echo -e "$ISSUE_LABELS\\n$PR_LABELS" | grep -qE "^(hold|blocked)$"; then
  echo "halted by hold or blocked" >&2
  exit 0
fi
"""
start_idx = content.find("# D15 Check hold / blocked on issue")
end_idx = content.find("# Before writing, read comments")

new_content = content[:start_idx] + replacement.strip() + "\n\n" + content[end_idx:]

with open('scripts/ci/escalate.sh', 'w') as f:
    f.write(new_content)
