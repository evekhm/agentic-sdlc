#!/usr/bin/env bash
# scripts/ops/digest.sh — read-only pre-dispatch summary for /work (#407).
#
#   scripts/ops/digest.sh <issue-or-pr-number> [args ignored]
#
# Purely informational, printed by .claude/commands/work.md BEFORE
# scripts/ops/work.sh's own dispatch line runs. Additive and read-only:
# it does not touch work.sh, and it must never be allowed to block the
# dispatch that follows it, so it MUST fail open — every lookup below
# degrades to an "(unavailable)"-style line instead of aborting, there
# is no `set -e`, and the script always exits 0. This does not change
# work.sh's documented exit-code contract (docs/SPEC.md ~line 856-891).
#
# Same owner/repo resolution as scripts/ops/tracker_search.sh.

REPO="${GITHUB_REPO:-${GITHUB_REPOSITORY:-evekhm/agentic-sdlc}}"
NUMBER="${1:-}"

if [ -z "$NUMBER" ]; then
    echo "digest: unavailable (no issue/PR number given)"
    exit 0
fi

# Try issue view first (D9-style: most numbers here are issues), fall
# back to pull-request view — see work.sh's own "Resolve the number"
# comments for the fuller resolver this script deliberately does not
# replicate.
kind="issue"
view_json="$(gh issue view "$NUMBER" --repo "$REPO" --json title,state,labels,comments 2>/dev/null)"
if [ -z "$view_json" ]; then
    kind="pr"
    view_json="$(gh pr view "$NUMBER" --repo "$REPO" --json title,state,labels,comments 2>/dev/null)"
fi

if [ -n "$view_json" ]; then
    title="$(jq -r '.title // "(unknown)"' <<<"$view_json" 2>/dev/null)"
    [ -n "$title" ] || title="(unknown)"
    state="$(jq -r '.state // "(unknown)"' <<<"$view_json" 2>/dev/null)"
    [ -n "$state" ] || state="(unknown)"
    echo "digest: #$NUMBER ($kind) \"$title\" -- $state"

    labels="$(jq -r '[.labels[].name] | join(", ")' <<<"$view_json" 2>/dev/null)"
    [ -n "$labels" ] || labels="(none)"
    echo "digest: labels: $labels"
else
    echo "digest: #$NUMBER -- (unavailable)"
    echo "digest: labels: (unavailable)"
fi

pr_json="$(gh pr list --repo "$REPO" --search "$NUMBER" --state open --json number,title,url 2>/dev/null)"
pr_count="$(jq 'length' <<<"$pr_json" 2>/dev/null)"
if [ -n "$pr_count" ] && [ "$pr_count" -gt 0 ] 2>/dev/null; then
    pr_line="$(jq -r '.[0] | "#\(.number) \(.title) (\(.url))"' <<<"$pr_json" 2>/dev/null)"
    echo "digest: open PR: $pr_line"
else
    echo "digest: no open PR references it"
fi

if [ -n "$view_json" ]; then
    last_comment="$(jq -r '.comments | if length > 0 then (.[-1].author.login + ": " + ((.[-1].body // "") | split("\n")[0])) else "" end' <<<"$view_json" 2>/dev/null)"
    if [ -n "$last_comment" ]; then
        echo "digest: last comment: $last_comment"
    else
        echo "digest: no comments yet"
    fi
else
    echo "digest: last comment: (unavailable)"
fi

exit 0
