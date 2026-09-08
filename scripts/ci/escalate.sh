#!/usr/bin/env bash
# scripts/ci/escalate.sh
# The ONE escalation writer (D9)

set -euo pipefail

if [[ $# -lt 5 ]]; then
  echo "Usage: $0 <issue> --reason <reason-code> --head <oid> [--pr <n>]" >&2
  exit 1
fi

ISSUE="$1"
shift
REASON=""
HEAD=""
PR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --reason) REASON="$2"; shift 2 ;;
    --head) HEAD="$2"; shift 2 ;;
    --pr) PR="$2"; shift 2 ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$REASON" || -z "$HEAD" ]]; then
  echo "Usage: $0 <issue> --reason <reason-code> --head <oid> [--pr <n>]" >&2
  exit 1
fi

GH_CMD="gh"
if [[ "${DRY_RUN:-0}" == "1" ]]; then
  GH_CMD="echo DRY-RUN gh"
fi

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

if echo -e "$ISSUE_LABELS\n$PR_LABELS" | grep -qE "^(hold|blocked)$"; then
  echo "halted by hold or blocked" >&2
  exit 0
fi

# Before writing, read comments to exhaustive depth to check idempotency.
COMMENTS=$(gh api --paginate "repos/{owner}/{repo}/issues/$ISSUE/comments" -q '.[].body' 2>/dev/null || echo "")
if [[ -z "$COMMENTS" ]]; then
  # Truncated or error -> fail closed (do not duplicate)
  # Actually, if gh api fails, it will exit non-zero and set -e will catch it, unless we use || true
  # Let's check exit code.
  if ! COMMENTS=$(gh api --paginate "repos/$GITHUB_REPOSITORY/issues/$ISSUE/comments" -q '.[].body' 2>/dev/null); then
    echo "Decline: Could not read issue comments." >&2
    exit 1 # Or exit 0? "unreadable issue and the escalation is refused rather than duplicated" -> meaning it doesn't write anything.
  fi
fi

# Marker format: <!-- escalation:<displaced-label>:<reason-code>:<head-oid> -->
# The idempotency check is (reason-code, head-oid).
if echo "$COMMENTS" | grep -qF "<!-- escalation:"; then
  if echo "$COMMENTS" | grep -qF ":$REASON:$HEAD -->"; then
    echo "Escalation already exists for reason=$REASON head=$HEAD. Idempotent exit."
    exit 0
  fi
fi

# Swap the status:* label for status:review-stuck.
ISSUE_JSON=$(gh issue view "$ISSUE" --json labels -q '.' 2>/dev/null || true)
if [[ -z "$ISSUE_JSON" ]]; then
  echo "Decline: Could not read issue labels." >&2
  exit 1
fi

CURRENT_STATUS=$(jq -r '.labels[].name | select(startswith("status:"))' <<<"$ISSUE_JSON" || true)

# If already review-stuck, displaced label is empty.
if [[ "$CURRENT_STATUS" == "status:review-stuck" ]]; then
  DISPLACED=""
else
  DISPLACED="$CURRENT_STATUS"
fi

MARKER="<!-- escalation:$DISPLACED:$REASON:$HEAD -->"
BODY="Escalation: $REASON at head $HEAD.\n\n$MARKER"

if [[ -n "$CURRENT_STATUS" && "$CURRENT_STATUS" != "status:review-stuck" ]]; then
  $GH_CMD issue edit "$ISSUE" --add-label "status:review-stuck" --remove-label "$CURRENT_STATUS"
elif [[ -z "$CURRENT_STATUS" ]]; then
  $GH_CMD issue edit "$ISSUE" --add-label "status:review-stuck"
fi

$GH_CMD issue comment "$ISSUE" -b "$BODY"

exit 0
