#!/usr/bin/env bash
# Continuous poller for vm-local placement (#251, D2, D4, D5).
#
# Usage:
#   scripts/placement/vm-local/poll.sh [--once] [--interval <seconds>]
#
# Discovers candidate work via label queries and loop-ledger comments,
# claims issues under persona identity, and dispatches via vm-local adapter.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
RUN_SH="${RUN_SH:-$REPO_ROOT/scripts/placement/vm-local/run.sh}"
CLAIM_SH="${CLAIM_SH:-$REPO_ROOT/scripts/ops/claim.sh}"
GITHUB_REPO="${GITHUB_REPO:-${GITHUB_REPOSITORY:-evekhm/agentic-sdlc}}"
TMPDIR="${TMPDIR:-/tmp}"

ONCE=0
POLL_INTERVAL="${POLL_INTERVAL_SECONDS:-${POLL_INTERVAL:-30}}"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --once)
            ONCE=1
            shift
            ;;
        --interval)
            [ "$#" -ge 2 ] || { echo "poll.sh: --interval needs a number" >&2; exit 1; }
            POLL_INTERVAL="$2"
            shift 2
            ;;
        --interval=*)
            POLL_INTERVAL="${1#--interval=}"
            shift
            ;;
        -h|--help)
            echo "Usage: scripts/placement/vm-local/poll.sh [--once] [--interval <seconds>]"
            exit 0
            ;;
        *)
            echo "poll.sh: unknown argument '$1'" >&2
            exit 1
            ;;
    esac
done

resolve_claim_cmd() {
    if [ -n "${CLAIM_SH:-}" ] && [ -x "$CLAIM_SH" ]; then
        echo "$CLAIM_SH"
    elif [ -x "$REPO_ROOT/scripts/ops/claim.sh" ]; then
        echo "$REPO_ROOT/scripts/ops/claim.sh"
    elif command -v claim.sh >/dev/null 2>&1; then
        echo "claim.sh"
    else
        echo "$CLAIM_SH"
    fi
}

claim_cmd="$(resolve_claim_cmd)"

poll_tick() {
    local processed_issues=" "

    # 1. Credential preflight for vm-local personas (D4, AT-14)
    local vm_personas=("athena" "daedalus" "odyssey")
    local skipped_personas=()
    for p in "${vm_personas[@]}"; do
        if ! python3 "$REPO_ROOT/scripts/auth/mint_app_token.py" "$p" --require-repo --quiet >/dev/null 2>&1; then
            echo "missing key for $p, skipping its rows"
            skipped_personas+=("$p")
        fi
    done

    is_skipped() {
        local check="$1"
        for s in "${skipped_personas[@]}"; do
            [ "$s" = "$check" ] && return 0
        done
        return 1
    }

    # 2. Fix rounds on open pull requests at status:in-review (D2, AT-20)
    local prs_json="[]"
    prs_json="$(gh pr list --state open --json number,title,labels,headRefName 2>/dev/null || echo '[]')"
    if [ -n "$prs_json" ] && [ "$prs_json" != "[]" ]; then
        local pr_count
        pr_count="$(jq '. | length' <<<"$prs_json" 2>/dev/null || echo 0)"
        for (( idx=0; idx<pr_count; idx++ )); do
            local pr_obj
            pr_obj="$(jq -c ".[$idx]" <<<"$prs_json")"
            local pr_num
            pr_num="$(jq -r '.number // empty' <<<"$pr_obj")"
            [ -n "$pr_num" ] || continue

            local has_in_review
            has_in_review="$(jq -r '[.labels[]? | (.name // .)] | if index("status:in-review") != null then "yes" else "no" end' <<<"$pr_obj")"
            [ "$has_in_review" = "yes" ] || continue

            local head_ref
            head_ref="$(jq -r '.headRefName // empty' <<<"$pr_obj")"
            local author_persona="${head_ref%%/*}"
            case "$author_persona" in
                athena|daedalus|odyssey) ;;
                *) continue ;;
            esac

            is_skipped "$author_persona" && continue

            local lock_file="${TMPDIR}/poll-pr-${pr_num}.lock"
            if [ -f "$lock_file" ]; then
                continue
            fi

            local pr_comments="[]"
            pr_comments="$(gh api "repos/$GITHUB_REPO/issues/$pr_num/comments" 2>/dev/null || echo '[]')"
            local pr_bodies
            pr_bodies="$(jq -r '.[].body // empty' <<<"$pr_comments" 2>/dev/null || echo '')"
            if grep -iqE 'review findings: blocking|<!-- review-verdict:[^:]*:(blocking|blocked|changes_requested) -->|\bblocking\b' <<<"$pr_bodies"; then
                touch "$lock_file"
                (
                    trap 'rm -f "$lock_file"' EXIT INT TERM
                    "$RUN_SH" "$pr_num" --as "$author_persona"
                ) || true
            fi
        done
    fi

    # 3. First-hop intake: open unclaimed intent:new issues (D5, AT-15)
    local intake_json="[]"
    intake_json="$(gh issue list --state open --label "intent:new" --json number,title,labels 2>/dev/null || echo '[]')"
    if [ -n "$intake_json" ] && [ "$intake_json" != "[]" ]; then
        local intake_count
        intake_count="$(jq '. | length' <<<"$intake_json" 2>/dev/null || echo 0)"
        for (( idx=0; idx<intake_count; idx++ )); do
            local issue_obj
            issue_obj="$(jq -c ".[$idx]" <<<"$intake_json")"
            local issue_num
            issue_num="$(jq -r '.number // empty' <<<"$issue_obj")"
            [ -n "$issue_num" ] || continue

            local is_claimed
            is_claimed="$(jq -r '[.labels[]? | (.name // .)] | if index("in-progress") != null then "yes" else "no" end' <<<"$issue_obj")"
            [ "$is_claimed" = "no" ] || continue

            is_skipped "athena" && continue

            local token
            token="$(python3 "$REPO_ROOT/scripts/auth/mint_app_token.py" athena 2>/dev/null || true)"
            if [ -z "$token" ]; then
                echo "missing key for athena, skipping its rows"
                continue
            fi

            if ! GH_TOKEN="$token" CLAIM_ACTOR="athena" CLAIM_SESSION="poll-$$" "$claim_cmd" "$issue_num"; then
                continue
            fi

            processed_issues="$processed_issues $issue_num "
            "$RUN_SH" "$issue_num" --as athena || true
        done
    fi

    # 4. Ledger consumption: open issues with unconsumed dispatch rows (D2, D4, AT-8, AT-14)
    local ladder_labels=("status:planning" "status:spec" "status:build" "status:implementing")
    for status_label in "${ladder_labels[@]}"; do
        local issues_json="[]"
        issues_json="$(gh issue list --state open --label "$status_label" --json number,title,labels,comments 2>/dev/null || echo '[]')"
        [ -n "$issues_json" ] && [ "$issues_json" != "[]" ] || continue

        local issue_count
        issue_count="$(jq '. | length' <<<"$issues_json" 2>/dev/null || echo 0)"
        for (( idx=0; idx<issue_count; idx++ )); do
            local issue_obj
            issue_obj="$(jq -c ".[$idx]" <<<"$issues_json")"
            local issue_num
            issue_num="$(jq -r '.number // empty' <<<"$issue_obj")"
            [ -n "$issue_num" ] || continue

            if [[ "$processed_issues" == *" $issue_num "* ]]; then
                continue
            fi

            # Extract comments
            local comments_json
            comments_json="$(jq -c '.comments // empty' <<<"$issue_obj")"
            if [ -z "$comments_json" ] || [ "$comments_json" = "null" ] || [ "$comments_json" = "[]" ]; then
                comments_json="$(gh api "repos/$GITHUB_REPO/issues/$issue_num/comments" 2>/dev/null || echo '[]')"
            fi

            local comment_bodies
            comment_bodies="$(jq -r '.[].body // empty' <<<"$comments_json" 2>/dev/null || echo '')"
            if [ -z "$comment_bodies" ]; then
                continue
            fi

            # Check for unparseable ledger
            if grep -q "loop-ledger" <<<"$comment_bodies" && ! grep -qE '<!-- loop-ledger-row:' <<<"$comment_bodies"; then
                echo "poll.sh: notice: issue #$issue_num carries loop ledger marker but no parseable rows"
                continue
            fi

            local last_row
            last_row="$(grep -oE '<!-- loop-ledger-row: [^>]+ -->' <<<"$comment_bodies" | tail -n 1 || true)"
            [ -n "$last_row" ] || continue

            if ! grep -qE '^<!-- loop-ledger-row: dispatch ' <<<"$last_row"; then
                continue
            fi

            local rung
            rung="$(grep -oE 'rung:[0-9]+' <<<"$last_row" | cut -d: -f2 || true)"
            [ -n "$rung" ] || continue

            local persona=""
            case "$rung" in
                1|2) persona="athena" ;;
                3)   persona="daedalus" ;;
                4)   persona="odyssey" ;;
                *)   continue ;;
            esac

            if is_skipped "$persona"; then
                continue
            fi

            local token
            token="$(python3 "$REPO_ROOT/scripts/auth/mint_app_token.py" "$persona" 2>/dev/null || true)"
            if [ -z "$token" ]; then
                echo "missing key for $persona, skipping its rows"
                continue
            fi

            if ! GH_TOKEN="$token" CLAIM_ACTOR="$persona" CLAIM_SESSION="poll-$$" "$claim_cmd" "$issue_num"; then
                continue
            fi

            processed_issues="$processed_issues $issue_num "
            "$RUN_SH" "$issue_num" --as "$persona" || true
        done
    done
}

echo "poller active, interval: ${POLL_INTERVAL}s"

if [ "$ONCE" -eq 1 ]; then
    poll_tick
    exit 0
fi

while true; do
    poll_tick
    sleep "$POLL_INTERVAL"
done
