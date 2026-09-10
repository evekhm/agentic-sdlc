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
cd "$REPO_ROOT" || exit 1
RUN_SH="${RUN_SH:-$REPO_ROOT/scripts/placement/vm-local/run.sh}"
CLAIM_SH="${CLAIM_SH:-$REPO_ROOT/scripts/ops/claim.sh}"
GITHUB_REPO="${GITHUB_REPO:-${GITHUB_REPOSITORY:-evekhm/agentic-sdlc}}"
TMPDIR="${TMPDIR:-/tmp}"

die() {
    echo "poll.sh: $*" >&2
    exit 1
}
# shellcheck source=scripts/ops/lib/github.sh
source "$REPO_ROOT/scripts/ops/lib/github.sh"

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

stage_for_rung() { # <rung> -> stage name, or empty
    local r="$1"
    [ "$r" -ge 1 ] 2>/dev/null || return 0
    jq -r --argjson idx "$((r - 1))" '.stages[$idx].stage // empty' "$REPO_ROOT/personas/lifecycle.json" 2>/dev/null || true
}

owner_for_stage() { # <stage> -> persona name, or empty
    local stg="$1" p_file
    for p_file in "$REPO_ROOT/personas"/*.yaml; do
        [ -f "$p_file" ] || continue
        grep -q '^kind: persona$' "$p_file" 2>/dev/null || continue
        if grep -qE "^stage: \[( *[a-z]+,)* *$stg( *, *[a-z]+)* *\]" "$p_file"; then
            basename "$p_file" .yaml
            return 0
        fi
    done
    return 0
}

poll_tick() {
    local auto_merge
    auto_merge="$(python3 "$REPO_ROOT/scripts/ops/execution.py" --loop autonomous_merge 2>/dev/null || echo false)"
    if [ "$auto_merge" != "true" ]; then
        echo "poll.sh: autonomous_merge is not true; idling queues"
        return 0
    fi

    local processed_issues=" "
    declare -A TICK_TOKENS=()

    mint_cached_token() {
        local p="$1"
        if [ -n "${TICK_TOKENS[$p]:-}" ]; then
            echo "${TICK_TOKENS[$p]}"
            return 0
        fi
        local tok
        tok="$(python3 "$REPO_ROOT/scripts/auth/mint_app_token.py" "$p" 2>/dev/null || true)"
        if [ -n "$tok" ]; then
            TICK_TOKENS["$p"]="$tok"
            echo "$tok"
            return 0
        fi
        return 1
    }

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

    # 2. Fix rounds on open builder pull requests (D2, D6, AT-20, AT-24)
    local prs_json="[]"
    prs_json="$(gh pr list --state open --draft=false --json number,title,labels,headRefName,headRefOid,isCrossRepository,isDraft --limit 300 2>/dev/null || echo '[]')"
    if [ -n "$prs_json" ] && [ "$prs_json" != "[]" ]; then
        local state_base="${XDG_STATE_HOME:-}"
        [ -z "$state_base" ] && state_base=~/.local/state
        local poll_state_dir="${POLL_STATE_DIR:-${state_base}/sdlc-poller}"
        mkdir -p "$poll_state_dir" 2>/dev/null || true

        # Clean state keys for PRs no longer in the open list
        local open_pr_nums
        open_pr_nums="$(jq -r '.[].number // empty' <<<"$prs_json" 2>/dev/null || true)"
        if [ -n "$open_pr_nums" ]; then
            for f in "$poll_state_dir"/pr-* "$poll_state_dir"/refuse-pr-*; do
                [ -f "$f" ] || continue
                local fname fnum=""
                fname="$(basename "$f")"
                if [[ "$fname" =~ ^pr-([0-9]+)- ]]; then
                    fnum="${BASH_REMATCH[1]}"
                elif [[ "$fname" =~ ^refuse-pr-([0-9]+)- ]]; then
                    fnum="${BASH_REMATCH[1]}"
                fi
                if [ -n "$fnum" ] && ! grep -qxE "$fnum" <<<"$open_pr_nums"; then
                    rm -f "$f"
                fi
            done
        fi

        local pr_count
        pr_count="$(jq '. | length' <<<"$prs_json" 2>/dev/null || echo 0)"
        for (( idx=0; idx<pr_count; idx++ )); do
            local pr_obj
            pr_obj="$(jq -c ".[$idx]" <<<"$prs_json")"
            local pr_num
            pr_num="$(jq -r '.number // empty' <<<"$pr_obj")"
            [ -n "$pr_num" ] || continue

            # C1: Skip cross-repository (fork) PRs; missing field defaults to false
            local is_cross
            is_cross="$(jq -r '.isCrossRepository // false' <<<"$pr_obj")"
            [ "$is_cross" = "true" ] && continue

            # Skip draft pull requests
            local is_draft
            is_draft="$(jq -r '.isDraft // false' <<<"$pr_obj")"
            [ "$is_draft" = "true" ] && continue

            local head_ref head_oid
            head_ref="$(jq -r '.headRefName // empty' <<<"$pr_obj")"
            [ -n "$head_ref" ] || continue
            head_oid="$(jq -r '.headRefOid // empty' <<<"$pr_obj")"

            local author_persona="${head_ref%%/*}"
            case "$author_persona" in
                athena|daedalus|odyssey) ;;
                *) continue ;;
            esac

            is_skipped "$author_persona" && continue

            local state_base="${XDG_STATE_HOME:-}"
            [ -z "$state_base" ] && state_base=~/.local/state
            local poll_state_dir="${POLL_STATE_DIR:-${state_base}/sdlc-poller}"
            mkdir -p "$poll_state_dir" 2>/dev/null || true
            local repo_hash
            repo_hash="$(printf '%s' "$REPO_ROOT" | sha256sum | head -c 8)"

            # Check cached terminal refusal
            local refuse_key=""
            if [ -n "$head_oid" ]; then
                refuse_key="${poll_state_dir}/refuse-pr-${pr_num}-${repo_hash}-${head_oid}"
                if [ -f "$refuse_key" ]; then
                    echo "poll.sh: skipping PR #$pr_num (terminal refusal cached at $head_oid)"
                    continue
                fi
            fi

            local pr_comments="[]"
            pr_comments="$(gh api "repos/$GITHUB_REPO/issues/$pr_num/comments" 2>/dev/null || echo '[]')"

            # C2: Trigger predicate
            local trigger_body
            trigger_body="$(jq -r '
              [
                [
                  .[]? |
                  select((.user.login // "") == "evekhm-argus-app[bot]" or (.user.login // "") == "evekhm-atlas-app[bot]")
                ] |
                group_by(.user.login)[]? | last |
                select(
                  ((.body // "") | contains("review findings: blocking")) or
                  (
                    ((.body // "") | test("<!-- review-verdict:[^:]+:findings -->")) and
                    ((.body // "") | test("<!-- finding:[^:]+:(security|high):open:"))
                  )
                )
              ] | last | .body // empty
            ' <<<"$pr_comments" 2>/dev/null || echo '')"

            [ -n "$trigger_body" ] || continue

            # C3: Compute trigger key per PR
            local key=""
            if grep -qE '<!-- reviewed-head:[a-f0-9]+ -->' <<<"$trigger_body"; then
                key="$(grep -oE '<!-- reviewed-head:[a-f0-9]+ -->' <<<"$trigger_body" | head -1 | sed -E 's/.*<!-- reviewed-head:([a-f0-9]+) -->.*/\1/')"
            else
                key="$(printf '%s' "$trigger_body" | sha256sum | awk '{print $1}')"
            fi

            local key_file="${poll_state_dir}/pr-${pr_num}-${repo_hash}-${key}"

            # C4: Lock handling with staleness
            local lock_file="${poll_state_dir}/poll-pr-${pr_num}.lock"
            if [ -f "$lock_file" ]; then
                local lock_age=0 mtime now max_age="${POLL_LOCK_MAX_AGE:-7200}"
                mtime="$(stat -c %Y "$lock_file" 2>/dev/null || echo 0)"
                now="$(date +%s)"
                lock_age=$(( now - mtime ))
                if [ "$lock_age" -ge "$max_age" ]; then
                    local lock_pid=""
                    lock_pid="$(cat "$lock_file" 2>/dev/null | tr -d '[:space:]' || true)"
                    if [ -n "$lock_pid" ]; then
                        if ! kill -0 "$lock_pid" 2>/dev/null; then
                            echo "poll.sh: removing stale lock for PR #$pr_num (pid $lock_pid dead, age ${lock_age}s)"
                            rm -f "$lock_file"
                        else
                            continue
                        fi
                    else
                        echo "poll.sh: removing stale empty lock for PR #$pr_num (age ${lock_age}s)"
                        rm -f "$lock_file"
                    fi
                else
                    continue
                fi
            fi

            # Check consumed keys (C3)
            if [ -f "$key_file" ]; then
                echo "#$pr_num: review at $key already dispatched"
                continue
            fi

            # Subshell PR-to-issue resolution (D3)
            local res_json="" rc_res=0
            res_json="$( ( resolve_issue "$pr_num" && jq -nc --arg issue "$ISSUE" --argjson issue_json "$ISSUE_JSON" '{issue: $issue, issue_json: $issue_json}' ) 2>/dev/null )" || rc_res=$?
            if [ "$rc_res" -ne 0 ] || [ -z "$res_json" ]; then
                echo "poll.sh: skipping PR #$pr_num (could not resolve to tracking issue)"
                continue
            fi
            local resolved_issue issue_obj
            resolved_issue="$(jq -r '.issue // empty' <<<"$res_json")"
            issue_obj="$(jq -c '.issue_json // empty' <<<"$res_json")"
            if ! [[ "$resolved_issue" =~ ^[0-9]+$ ]] || [ -z "$issue_obj" ] || [ "$issue_obj" = "null" ]; then
                echo "poll.sh: skipping PR #$pr_num (could not resolve to tracking issue)"
                continue
            fi

            # Transient circuit breakers (D4)
            local issue_labels pr_labels has_issue_hold has_issue_blocked has_pr_hold
            issue_labels="$(jq -r '[.labels[]? | (.name // .)]' <<<"$issue_obj")"
            pr_labels="$(jq -r '[.labels[]? | (.name // .)]' <<<"$pr_obj")"

            has_issue_hold="$(jq -r 'if index("hold") != null then "yes" else "no" end' <<<"$issue_labels")"
            has_issue_blocked="$(jq -r 'if index("blocked") != null then "yes" else "no" end' <<<"$issue_labels")"
            has_pr_hold="$(jq -r 'if index("hold") != null then "yes" else "no" end' <<<"$pr_labels")"

            if [ "$has_issue_hold" = "yes" ]; then
                echo "poll.sh: skipping PR #$pr_num (issue #$resolved_issue carries hold)"
                continue
            fi
            if [ "$has_issue_blocked" = "yes" ]; then
                echo "poll.sh: skipping PR #$pr_num (issue #$resolved_issue carries blocked)"
                continue
            fi
            if [ "$has_pr_hold" = "yes" ]; then
                echo "poll.sh: skipping PR #$pr_num (PR #$pr_num carries hold)"
                continue
            fi

            # Terminal refusals and negative caching (D5)
            local issue_state has_review_stuck
            issue_state="$(jq -r '.state // empty' <<<"$issue_obj")"
            if [ "$issue_state" != "open" ]; then
                echo "poll.sh: skipping PR #$pr_num (tracking issue #$resolved_issue is closed)"
                [ -n "$refuse_key" ] && touch "$refuse_key"
                continue
            fi

            has_review_stuck="$(jq -r 'if index("status:review-stuck") != null then "yes" else "no" end' <<<"$issue_labels")"
            if [ "$has_review_stuck" = "yes" ]; then
                echo "poll.sh: skipping PR #$pr_num (tracking issue #$resolved_issue carries status:review-stuck)"
                [ -n "$refuse_key" ] && touch "$refuse_key"
                continue
            fi

            # Stage-to-author alignment (D6)
            local status_label expected_status=""
            status_label="$(jq -r '[.labels[]? | (.name // .) | select(startswith("status:"))] | .[0] // empty' <<<"$issue_obj")"

            case "$author_persona" in
                athena) expected_status="status:spec" ;;
                daedalus) expected_status="status:build" ;;
                odyssey) expected_status="status:implementing" ;;
            esac

            if [ -z "$expected_status" ] || [ "$status_label" != "$expected_status" ]; then
                echo "poll.sh: skipping PR #$pr_num (author persona $author_persona does not match issue #$resolved_issue stage ${status_label:-none})"
                [ -n "$refuse_key" ] && touch "$refuse_key"
                continue
            fi

            # Write key file before calling run.sh
            touch "$key_file"

            # Create lock in parent shell, run, remove in parent shell
            echo "$$" > "$lock_file"
            (
                "$RUN_SH" "$pr_num" --as "$author_persona"
            ) || true
            rm -f "$lock_file"
        done
    fi

    # 3. First-hop intake: open unclaimed intent:new issues with intake:auto (D3, D4, D5, AT-15, AT-22)
    local limit active_count in_progress_raw in_progress_json="[]"
    limit="$(python3 "$REPO_ROOT/scripts/ops/execution.py" --loop max_concurrent_first_hops 2>/dev/null || echo 1)"
    [ -n "$limit" ] || limit=1
    # Query limit 300 exceeds active in-progress issues across the fleet by an order of magnitude (typically <20), preventing truncation to gh default 30 (R1-2).
    if ! in_progress_raw="$(gh issue list --repo "$GITHUB_REPO" --state open --label "in-progress" --limit 300 --json number,comments 2>/dev/null)"; then
        echo "poll.sh: measuring query failed (gh issue list --label in-progress); skipping intake"
    else
        in_progress_json="${in_progress_raw:-[]}"
        active_count="$(jq '
          [
            .[]? |
            [ .comments[]? | select((.body // "") | test("^[[:space:]]*[Cc]laim:")) ] | last |
            select(. != null) |
            ((.author.login // .user.login // "") | sub("\\[bot\\]$"; "")) |
            select(. == "evekhm-athena-app")
          ] | length
        ' <<<"$in_progress_json" 2>/dev/null || echo 0)"

        if [ "$active_count" -ge "$limit" ]; then
            echo "poll.sh: first-hop intake concurrency limit reached ($active_count/$limit), skipping intake"
        else
            local intake_json="[]"
            # Query limit 300 covers the entire repository backlog (~40 issues total) in a single page, preventing truncation to gh default 30 (R1-2).
            intake_json="$(gh issue list --repo "$GITHUB_REPO" --state open --label "intent:new" --label "intake:auto" --limit 300 --json number,title,labels 2>/dev/null || echo '[]')"
            if [ -n "$intake_json" ] && [ "$intake_json" != "[]" ]; then
                local intake_count
                intake_count="$(jq '. | length' <<<"$intake_json" 2>/dev/null || echo 0)"
                for (( idx=0; idx<intake_count; idx++ )); do
                    if [ "$active_count" -ge "$limit" ]; then
                        break
                    fi

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
                    token="$(mint_cached_token athena)"
                    if [ -z "$token" ]; then
                        echo "missing key for athena, skipping its rows"
                        continue
                    fi

                    if ! GH_TOKEN="$token" CLAIM_ACTOR="athena" CLAIM_SESSION="poll-$$" "$claim_cmd" "$issue_num"; then
                        continue
                    fi

                    active_count=$((active_count + 1))
                    processed_issues="$processed_issues $issue_num "
                    "$RUN_SH" "$issue_num" --as athena || true
                done
            fi
        fi
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

            local stage_name persona=""
            stage_name="$(stage_for_rung "$rung")"
            if [ -n "$stage_name" ]; then
                persona="$(owner_for_stage "$stage_name")"
            fi
            if [ -z "$persona" ]; then
                echo "rung $rung has no owner"
                continue
            fi

            if is_skipped "$persona"; then
                continue
            fi

            local token
            token="$(mint_cached_token "$persona")"
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
