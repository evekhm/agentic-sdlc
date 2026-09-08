#!/usr/bin/env bash
# scripts/ci/escalate.sh
# Escalates an issue by swapping its status:* label for status:review-stuck.
# Usage: escalate.sh <issue> --reason <reason-code> --head <oid> [--pr <n>]

set -euo pipefail

ISSUE=""
REASON=""
HEAD=""
PR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --reason) REASON="$2"; shift 2 ;;
    --head) HEAD="$2"; shift 2 ;;
    --pr) PR="$2"; shift 2 ;;
    *) ISSUE="$1"; shift 1 ;;
  esac
done

if [[ -z "$ISSUE" || -z "$REASON" || -z "$HEAD" ]]; then
  echo "Usage: $0 <issue> --reason <reason-code> --head <oid> [--pr <n>]" >&2
  exit 1
fi

COMMENTS_JSON=$(gh issue view "$ISSUE" --json comments -q '.comments')
# Check for existing marker: <!-- escalation:<displaced-label>:<reason-code>:<head-oid> -->
# We don't know displaced-label yet, so we can just regex match it.
if echo "$COMMENTS_JSON" | grep -q "<!-- escalation:.*:$REASON:$HEAD -->"; then
  echo "Escalation for reason $REASON and head $HEAD already exists. Exiting cleanly."
  exit 0
fi

LABELS_JSON=$(gh issue view "$ISSUE" --json labels -q '.labels[].name')
CURRENT_STATUS=""
for label in $LABELS_JSON; do
  if [[ "$label" == status:* ]]; then
    CURRENT_STATUS="$label"
    break
  fi
done

DISPLACED_LABEL="$CURRENT_STATUS"
if [[ "$CURRENT_STATUS" == "status:review-stuck" ]]; then
  DISPLACED_LABEL=""
fi

# Ensure DRY_RUN behaves correctly
GH_CMD="gh"
if [[ "${DRY_RUN:-0}" == "1" ]]; then
  GH_CMD="echo DRY-RUN gh"
fi

if [[ -n "$CURRENT_STATUS" && "$CURRENT_STATUS" != "status:review-stuck" ]]; then
  $GH_CMD issue edit "$ISSUE" --remove-label "$CURRENT_STATUS" --add-label "status:review-stuck"
elif [[ "$CURRENT_STATUS" != "status:review-stuck" ]]; then
  $GH_CMD issue edit "$ISSUE" --add-label "status:review-stuck"
fi

MARKER="<!-- escalation:$DISPLACED_LABEL:$REASON:$HEAD -->"
BODY="### Escalation: Review Stuck
Reason: \`$REASON\`
Head: \`$HEAD\`"
if [[ -n "$PR" ]]; then
  BODY="$BODY
PR: #$PR"
fi
BODY="$BODY

$MARKER"

printf "%s\n" "$BODY" | $GH_CMD issue comment "$ISSUE" -F -
