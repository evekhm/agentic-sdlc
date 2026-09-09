#!/usr/bin/env bash
# scripts/ci/review_recorder.sh - Consensus ledger recorder (#267)
#
# Usage: scripts/ci/review_recorder.sh <pr-number>
#
# Derives and maintains the consensus ledger comment and pull request labels
# from structured review verdicts posted by Argus and Atlas.

set -euo pipefail

PR="${1:-}"
if [ -z "$PR" ]; then
  echo "Usage: $0 <pr-number>" >&2
  exit 1
fi

# Guard 1 (D1): Skip execution entirely when sender is Themis App
if [ "${GITHUB_EVENT_SENDER_LOGIN:-}" = "evekhm-themis-app[bot]" ]; then
  exit 0
fi

# Resolve repository
REPO="${GITHUB_REPOSITORY:-}"
if [ -z "$REPO" ]; then
  REPO="$(git config --get remote.origin.url | sed -E 's#.*[:/]([^/]+/[^/]+)(\.git)?$#\1#' || true)"
fi
REPO="${REPO:-evekhm/agentic-sdlc}"
export GITHUB_REPOSITORY="$REPO"

# Token setup (Smoke N2)
if [ -z "${THEMIS_TOKEN:-}" ] && [ -z "${FX:-}" ]; then
  echo "THEMIS_TOKEN is not set; recorder writes nothing"
  exit 0
fi
export GH_TOKEN="${THEMIS_TOKEN:-}"

# Query pull request info
PR_JSON="$(gh pr view "$PR" --json number,headRefName,labels,closingIssuesReferences,body,headRefOid,commits 2>/dev/null || true)"
if [ -z "$PR_JSON" ]; then
  echo "Failed to retrieve pull request #$PR" >&2
  exit 1
fi

get_linked_issues() {
  local json="$1"
  local closing_refs body_refs branch_ref head_ref
  closing_refs="$(echo "$json" | jq -r '(.closingIssuesReferences[]?.number // empty)')"
  body_refs="$(echo "$json" | jq -r '.body // ""' | grep -oEi '\b(close|closes|closed|fix|fixes|fixed|resolve|resolves|resolved|refs?)\s+#[0-9]+' | grep -oE '[0-9]+' || true)"
  head_ref="$(echo "$json" | jq -r '.headRefName // ""')"
  branch_ref=""
  if [[ "$head_ref" =~ ^([a-zA-Z0-9_-]+/)?([0-9]+)- ]]; then
    branch_ref="${BASH_REMATCH[2]}"
  fi
  printf '%s\n%s\n%s\n' "$closing_refs" "$body_refs" "$branch_ref" | grep -E '^[0-9]+$' | sort -u || true
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Guard 2 (#291): Circuit breaker on hold
# Check PR itself
if echo "$PR_JSON" | jq -e '.labels[]? | select(.name == "hold")' >/dev/null 2>&1; then
  echo "hold present on #$PR, recorder writes nothing"
  exit 0
fi

# Check linked issues (closing references, body closing/refs keywords, branch name pattern)
ALL_LINKED="$(get_linked_issues "$PR_JSON")"
for iss in $ALL_LINKED; do
  if ! iss_json="$(gh issue view "$iss" --json labels 2>&1)"; then
    if echo "$iss_json" | grep -Eiq "could not resolve to an issue|not found|404"; then
      echo "note: #$iss is not an issue, treating as not held"
    else
      echo "error: failed to probe hold status on #$iss; recorder aborts to fail closed" >&2
      exit 1
    fi
  elif echo "$iss_json" | jq -e '.labels[]? | select(.name == "hold")' >/dev/null 2>&1; then
    echo "hold present on #$iss, recorder writes nothing"
    exit 0
  fi
done

# Resolve recorder login via GraphQL viewer query (S3, D30)
VIEWER_QUERY='query { viewer { login } }'
RECORDER_LOGIN="$(gh api graphql -f query="$VIEWER_QUERY" 2>/dev/null | jq -r '.data.viewer.login // empty' || true)"
if [ -z "$RECORDER_LOGIN" ] || [ "$RECORDER_LOGIN" = "github-actions[bot]" ]; then
  echo "recorder login is '$RECORDER_LOGIN' (unauthenticated or github-actions[bot]), recorder writes nothing"
  exit 0
fi

# Run the python engine to derive ledger state and actions
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

python3 "$SCRIPT_DIR/review_recorder.py" "$PR" "$REPO" "$PR_JSON" "$WORKDIR" "$RECORDER_LOGIN"

# Read action plan
PLAN_JSON="$WORKDIR/action_plan.json"
if [ ! -f "$PLAN_JSON" ]; then
  exit 0
fi
COMMENT_ACTION="$(jq -r '.comment_action' "$PLAN_JSON")"
COMMENT_ID="$(jq -r '.existing_comment_id // empty' "$PLAN_JSON")"
TO_ADD="$(jq -r '.to_add | join(",")' "$PLAN_JSON")"
TO_REMOVE="$(jq -r '.to_remove | join(",")' "$PLAN_JSON")"

if [ "${DRY_RUN:-0}" != "1" ]; then
  # Guard 2 (#291, Smoke N6): Re-read hold immediately before the first write
  if ! PR_LATEST_JSON="$(gh pr view "$PR" --json number,headRefName,labels,closingIssuesReferences,body 2>&1)"; then
    echo "error: failed to probe hold status on #$PR at write time; recorder aborts to fail closed" >&2
    exit 1
  fi
  if echo "$PR_LATEST_JSON" | jq -e '.labels[]? | select(.name == "hold")' >/dev/null 2>&1; then
    echo "hold present on #$PR, recorder writes nothing"
    exit 0
  fi
  ALL_LINKED_LATEST="$(get_linked_issues "$PR_LATEST_JSON")"

  for iss in $ALL_LINKED_LATEST; do
    if ! iss_json="$(gh issue view "$iss" --json labels 2>&1)"; then
      if echo "$iss_json" | grep -Eiq "could not resolve to an issue|not found|404"; then
        echo "note: #$iss is not an issue, treating as not held"
      else
        echo "error: failed to probe hold status on #$iss at write time; recorder aborts to fail closed" >&2
        exit 1
      fi
    elif echo "$iss_json" | jq -e '.labels[]? | select(.name == "hold")' >/dev/null 2>&1; then
      echo "hold present on #$iss, recorder writes nothing"
      exit 0
    fi
  done

  # Execute comment write if needed
  if [ "$COMMENT_ACTION" = "POST" ]; then
    gh api -X POST "repos/$REPO/issues/$PR/comments" -F "body=@$WORKDIR/new_body.md"
  elif [ "$COMMENT_ACTION" = "PATCH" ] && [ -n "$COMMENT_ID" ]; then
    gh api -X PATCH "repos/$REPO/issues/comments/$COMMENT_ID" -F "body=@$WORKDIR/new_body.md"
  fi

  # Execute label updates if needed
  EDIT_ARGS=()
  [ -n "$TO_ADD" ] && EDIT_ARGS+=(--add-label "$TO_ADD")
  [ -n "$TO_REMOVE" ] && EDIT_ARGS+=(--remove-label "$TO_REMOVE")
  if [ "${#EDIT_ARGS[@]}" -gt 0 ]; then
    gh issue edit "$PR" "${EDIT_ARGS[@]}"
  fi
fi

exit 0

