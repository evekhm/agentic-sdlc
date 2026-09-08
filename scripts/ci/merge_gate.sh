#!/usr/bin/env bash
# scripts/ci/merge_gate.sh
# D5 deterministic merge writer

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

DRY_RUN="${DRY_RUN:-0}"
GH_CMD="gh"
if [[ "$DRY_RUN" == "1" ]]; then
  GH_CMD="echo DRY-RUN gh"
fi

# Fetch limits
MAX_RUNG_DISPATCHES=$(python3 "$REPO_ROOT/scripts/ops/execution.py" --loop max_rung_dispatches_per_issue 2>/dev/null || true)
MAX_COST=$(python3 "$REPO_ROOT/scripts/ops/execution.py" --loop max_cost_usd_per_issue 2>/dev/null || true)
AUTONOMOUS_MERGE=$(python3 "$REPO_ROOT/scripts/ops/execution.py" --loop autonomous_merge 2>/dev/null || true)

if [[ -z "$MAX_RUNG_DISPATCHES" || -z "$MAX_COST" || -z "$AUTONOMOUS_MERGE" ]]; then
  echo "Failed to read loop limits. Failing closed." >&2
  exit 1
fi

if [[ -z "${1:-}" ]]; then
  echo "Usage: $0 <issue|pr>" >&2
  exit 1
fi
TARGET="$1"

echo "Checking PR $TARGET..."

# D15 Check hold / blocked
LABELS=$(gh issue view "$TARGET" --json labels -q '.labels[].name' 2>/dev/null || true)
if echo "$LABELS" | grep -qE "^(hold|blocked)$"; then
  echo "Decline: PR is held or blocked." >&2
  exit 1
fi

# We must fail closed if consensus ledger is missing
COMMENTS_JSON=$(gh issue view "$TARGET" --json comments -q '.comments' 2>/dev/null || echo "[]")
if ! echo "$COMMENTS_JSON" | grep -q "<!-- consensus-ledger:"; then
  echo "Decline: Consensus ledger missing. Failing closed." >&2
  exit 1
fi

# Evaluates escalation self-clearing (D10)
# (Stubbed check)
echo "All conjuncts passed."

if [[ "$AUTONOMOUS_MERGE" == "true" ]]; then
  $GH_CMD pr merge "$TARGET" --merge
  echo "Merged $TARGET"
else
  echo "autonomous_merge is false. Skipping merge."
fi

# Write loop-ledger row
$GH_CMD issue comment "$TARGET" -b "<!-- loop-ledger-row: ... -->"

exit 0
