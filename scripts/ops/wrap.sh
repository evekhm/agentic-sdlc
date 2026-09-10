#!/usr/bin/env bash
# Deterministic session close-out and mid-flight snapshotting (#85).
set -euo pipefail

# 1. Environment and required binary verification (AT-13)
for req_bin in git gh jq; do
    if ! command -v "$req_bin" >/dev/null 2>&1; then
        echo "error: required binary '$req_bin' not found in PATH" >&2
        exit 1
    fi
done

if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "error: not inside a git repository" >&2
    exit 1
fi

# 2. Argument parsing (AT-13)
SESSION_NAME=""
SEAT_ARG=""
SNAPSHOT=0

for arg in "$@"; do
    case "$arg" in
        --snapshot)
            SNAPSHOT=1
            ;;
        *)
            if [ -z "$SESSION_NAME" ]; then
                SESSION_NAME="$arg"
            elif [ -z "$SEAT_ARG" ]; then
                SEAT_ARG="$arg"
            fi
            ;;
    esac
done

if [ -z "$SESSION_NAME" ] || [[ "$SESSION_NAME" == --* ]]; then
    echo "usage: wrap.sh <session-name> [seat-or-slug] [--snapshot]" >&2
    exit 1
fi

# 3. Repository root and path resolution
COMMON_DIR="$(git rev-parse --git-common-dir)"
PRIMARY_REPO="$(cd "$COMMON_DIR/.." && pwd)"
TODAY="$(date -u +%Y-%m-%d)"
NOW_TIME="$(date -u +%H:%M)"

# 4. Mode-gated probe: cheap probe runs in both modes (D12, AT-18)
git status --short --branch >/dev/null 2>&1 || true

# 5. Seat resolution order (D13, AT-19, AT-16)
SEAT=""
SUPPLIED_TOKEN=""
if [ -n "$SEAT_ARG" ]; then
    SUPPLIED_TOKEN="$SEAT_ARG"
elif [ -n "${CLAUDE_SEAT:-}" ]; then
    SUPPLIED_TOKEN="${CLAUDE_SEAT}"
fi

if [ -n "$SUPPLIED_TOKEN" ]; then
    # Validate against standing seats or existing handoffs
    token_valid=0
    if [ -x "$PRIMARY_REPO/ops/waves/seat.sh" ]; then
        if "$PRIMARY_REPO/ops/waves/seat.sh" --list 2>/dev/null | grep -qw "$SUPPLIED_TOKEN"; then
            token_valid=1
        fi
    fi
    if [ "$token_valid" -eq 0 ]; then
        if compgen -G "$PRIMARY_REPO/ops/handoffs/handoff-${SUPPLIED_TOKEN}-*.txt" >/dev/null 2>&1 \
           || [ -f "$PRIMARY_REPO/ops/handoffs/handoff-${SUPPLIED_TOKEN}.txt" ]; then
            token_valid=1
        fi
    fi
    if [ "$token_valid" -eq 0 ]; then
        echo "refused: unrecognized seat token '$SUPPLIED_TOKEN'" >&2
        exit 2
    fi
    SEAT="$SUPPLIED_TOKEN"
else
    # Step 3: check today's handoff written by this session
    if [ -d "$PRIMARY_REPO/ops/handoffs" ]; then
        for cand in "$PRIMARY_REPO/ops/handoffs"/handoff-*-"${TODAY}"*.txt; do
            if [ -f "$cand" ] && grep -q "session: $SESSION_NAME" "$cand" 2>/dev/null; then
                bname="$(basename "$cand")"
                bname="${bname#handoff-}"
                SEAT="${bname%%-${TODAY}*}"
                break
            fi
        done
    fi
    # Step 4: mint short kebab-case slug naming the work
    if [ -z "$SEAT" ]; then
        cur_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
        if [ -n "$cur_branch" ] && [ "$cur_branch" != "HEAD" ] && [ "$cur_branch" != "main" ]; then
            minted="$(echo "$cur_branch" | sed 's|^[^/]*/||' | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-' | sed 's/^-*//;s/-*$//')"
        else
            minted="$(echo "$SESSION_NAME" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-' | sed 's/^-*//;s/-*$//')"
        fi
        [ -n "$minted" ] || minted="session-work"
        SEAT="$minted"
    fi
fi

# 6. Empty session short-circuit (D12, AT-17)
has_session_state=0

# Check git modifications in current checkout
if [ -n "$(git status --porcelain 2>/dev/null || true)" ]; then
    has_session_state=1
fi

# Check commit divergence from origin/main
if git rev-parse origin/main >/dev/null 2>&1; then
    divergence="$(git rev-list --count HEAD..origin/main 2>/dev/null || echo 0)"
    ahead="$(git rev-list --count origin/main..HEAD 2>/dev/null || echo 0)"
    if [ "$divergence" -gt 0 ] || [ "$ahead" -gt 0 ]; then
        has_session_state=1
    fi
fi

# Check run artifacts for this session
if [ -d "$PRIMARY_REPO/runs/$SESSION_NAME" ]; then
    if [ "$(find "$PRIMARY_REPO/runs/$SESSION_NAME" -type f 2>/dev/null | wc -l)" -gt 0 ]; then
        has_session_state=1
    fi
fi

# In close-out mode, probe tracker claims and PRs
if [ "$SNAPSHOT" -eq 0 ]; then
    issues_list="$(gh issue list --json number,title,labels 2>/dev/null || echo "[]")"
    if [ -n "$issues_list" ] && [ "$issues_list" != "[]" ]; then
        inums="$(echo "$issues_list" | jq -r '.[].number' 2>/dev/null || true)"
        for n in $inums; do
            icomm="$(gh api "repos/:owner/:repo/issues/$n/comments" 2>/dev/null || echo "[]")"
            if echo "$icomm" | jq -r '.[].body' 2>/dev/null | grep -q "Claim:.*${SESSION_NAME}"; then
                has_session_state=1
                break
            fi
        done
    fi

    prs_list="$(gh pr list --json number,headRefName,author,statusCheckRollup 2>/dev/null || echo "[]")"
    if [ -n "$prs_list" ] && [ "$prs_list" != "[]" ]; then
        has_session_state=1
    fi
fi

if [ "$has_session_state" -eq 0 ]; then
    echo "nothing to hand off: session clean and produced no state"
    exit 0
fi

# 7. Close-out validation checks (D1, D3, D4, D5, D6, D9, D12)
FAIL=0

if [ "$SNAPSHOT" -eq 0 ]; then
    # Check 1: In-flight child processes and subagents (AT-2)
    children="$(pgrep -P "$PPID" 2>/dev/null | grep -v "^$$$" || true)"
    active_children=0
    for cpid in $children; do
        if kill -0 "$cpid" 2>/dev/null; then
            active_children=1
            break
        fi
    done
    if [ -d "$COMMON_DIR/worktrees" ]; then
        for lock in "$COMMON_DIR/worktrees"/*/locked; do
            if [ -f "$lock" ]; then
                lpid="$(cat "$lock" 2>/dev/null || true)"
                if [ -n "$lpid" ] && kill -0 "$lpid" 2>/dev/null; then
                    active_children=1
                    break
                fi
            fi
        done
    fi
    if [ "$active_children" -eq 1 ]; then
        echo "refused: child processes still running" >&2
        FAIL=1
    fi

    # Check 3: Worktree branch synchronization (AT-3)
    cbranch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
    if [ -n "$cbranch" ] && [ "$cbranch" != "HEAD" ]; then
        upstream="$(git rev-parse --abbrev-ref '@{u}' 2>/dev/null || echo "")"
        if [ -n "$upstream" ]; then
            unpushed="$(git rev-list --count "${upstream}..HEAD" 2>/dev/null || echo 0)"
        elif git rev-parse origin/main >/dev/null 2>&1; then
            unpushed="$(git rev-list --count "origin/main..HEAD" 2>/dev/null || echo 0)"
        else
            unpushed=0
        fi
        if [ "$unpushed" -gt 0 ]; then
            echo "refused: unpushed commits on $cbranch" >&2
            FAIL=1
        fi
    fi

    # Check 4: Primary checkout on main and clean (AT-4)
    primary_dirty="$(git -C "$PRIMARY_REPO" status --porcelain 2>/dev/null || echo "")"
    primary_behind=0
    if git -C "$PRIMARY_REPO" rev-parse origin/main >/dev/null 2>&1; then
        primary_behind="$(git -C "$PRIMARY_REPO" rev-list --count "HEAD..origin/main" 2>/dev/null || echo 0)"
    fi
    if [ -n "$primary_dirty" ] || [ "$primary_behind" -gt 0 ]; then
        echo "refused: primary checkout dirty or behind origin/main" >&2
        FAIL=1
    fi

    # Check 5: PR CI check status (AT-5)
    prs_data="$(gh pr list --json number,headRefName,author,statusCheckRollup 2>/dev/null || echo "[]")"
    if [ -n "$prs_data" ] && [ "$prs_data" != "[]" ]; then
        code_failure_prs="$(echo "$prs_data" | jq -r '.[] | select(.statusCheckRollup != null) | select(.statusCheckRollup[]?.conclusion == "FAILURE") | .number' 2>/dev/null | sort -u || true)"
        infra_failure_prs="$(echo "$prs_data" | jq -r '.[] | select(.statusCheckRollup != null) | select(.statusCheckRollup[]?.conclusion == "STARTUP_FAILURE" or (.statusCheckRollup[]?.name | test("infrastructure"; "i"))) | .number' 2>/dev/null | sort -u || true)"
        if [ -n "$code_failure_prs" ]; then
            for p in $code_failure_prs; do
                echo "refused: PR #$p checks failing" >&2
            done
            FAIL=1
        elif [ -n "$infra_failure_prs" ]; then
            for p in $infra_failure_prs; do
                echo "warn: PR #$p check had ambient infrastructure startup failure"
            done
        fi
    fi

    # Check 8: Claim release and auto-repair (AT-6, AT-7, AT-8)
    claim_issues="$(gh issue list --json number,title,labels 2>/dev/null || echo "[]")"
    if [ -n "$claim_issues" ] && [ "$claim_issues" != "[]" ]; then
        all_nums="$(echo "$claim_issues" | jq -r '.[].number' 2>/dev/null || true)"
        for inum in $all_nums; do
            comments="$(gh api "repos/:owner/:repo/issues/$inum/comments" 2>/dev/null || echo "[]")"
            if echo "$comments" | jq -r '.[].body' 2>/dev/null | grep -q "Claim:.*${SESSION_NAME}"; then
                # Check for complete handoff comment
                all_comment_text="$(echo "$comments" | jq -r '.[].body' 2>/dev/null || true)"
                has_handoff=0
                if echo "$all_comment_text" | grep -q "Done:" \
                   && echo "$all_comment_text" | grep -q "Decided:" \
                   && echo "$all_comment_text" | grep -q "Next:" \
                   && echo "$all_comment_text" | grep -q "Blocked:"; then
                    has_handoff=1
                fi

                if [ "$has_handoff" -eq 0 ]; then
                    echo "fail: missing handoff comment on #$inum" >&2
                    FAIL=1
                else
                    # Check if in-progress label is still present
                    has_in_prog="$(echo "$claim_issues" | jq -r ".[] | select(.number == $inum) | .labels[].name" 2>/dev/null | grep "^in-progress$" || true)"
                    if [ -n "$has_in_prog" ]; then
                        if [ "${DRY_RUN:-0}" -eq 1 ]; then
                            echo "would: remove in-progress from #$inum"
                            echo "fail: #$inum carries in-progress (dry-run)" >&2
                            FAIL=1
                        else
                            gh api -X DELETE "repos/:owner/:repo/issues/$inum/labels/in-progress" >/dev/null 2>&1 || true
                            echo "fixed: removed in-progress from #$inum"
                        fi
                    fi
                fi
            fi
        done
    fi

    # Check 10: Run artifact disposition footnotes (AT-9)
    if [ -d "$PRIMARY_REPO/runs/$SESSION_NAME" ]; then
        while IFS= read -r art_file; do
            [ -f "$art_file" ] || continue
            if ! grep -q "Disposition" "$art_file"; then
                echo "fail: artifact $art_file missing disposition" >&2
                FAIL=1
            fi
        done < <(find "$PRIMARY_REPO/runs/$SESSION_NAME" -type f)
    fi

    # Check 12: Compiler integrity and drift
    if [ -f "$PRIMARY_REPO/scripts/sync_agents.py" ]; then
        python3 "$PRIMARY_REPO/scripts/sync_agents.py" --check >/dev/null 2>&1 || {
            echo "fail: compiler drift detected" >&2
            FAIL=1
        }
    fi
    if [ -x "$PRIMARY_REPO/scripts/ci/compiler_roundtrip.sh" ]; then
        "$PRIMARY_REPO/scripts/ci/compiler_roundtrip.sh" >/dev/null 2>&1 || {
            echo "fail: compiler roundtrip failed" >&2
            FAIL=1
        }
    fi

    # Check 15: Worktree hygiene report (AT-10)
    wt_cmd=""
    if [ -x "$PRIMARY_REPO/scripts/ops/worktrees.sh" ]; then
        wt_cmd="$PRIMARY_REPO/scripts/ops/worktrees.sh"
    elif command -v worktrees.sh >/dev/null 2>&1; then
        wt_cmd="worktrees.sh"
    fi
    if [ -n "$wt_cmd" ]; then
        wt_out="$("$wt_cmd" 2>&1 || true)"
        while IFS= read -r line; do
            [ -n "$line" ] || continue
            if [[ "$line" =~ dirty|locked ]]; then
                wt_name="$(echo "$line" | awk '{print $1}')"
                wt_branch="$(echo "$line" | awk '{print $2}')"
                if [ "$wt_name" != "primary" ] && [[ "$wt_name" != *"$SESSION_NAME"* ]]; then
                    echo "warn: peer worktree $wt_name held by $wt_branch is dirty"
                fi
            fi
        done <<< "$wt_out"
    fi

    # Check 17: Credential exposure (AT-12)
    leak=0
    if git diff --cached 2>/dev/null | grep -qE "ghp_[A-Za-z0-9]{20,}|gho_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}"; then
        leak=1
    elif git diff 2>/dev/null | grep -qE "ghp_[A-Za-z0-9]{20,}|gho_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}"; then
        leak=1
    fi
    if [ "$leak" -eq 1 ]; then
        echo "fail: credential exposure detected" >&2
        FAIL=1
    fi

    # Mandatory Learnings step (D5, AT-11)
    if [ -z "${WRAP_LEARNINGS+x}" ] || [ -z "$WRAP_LEARNINGS" ]; then
        echo "fail: learnings step omitted" >&2
        FAIL=1
    else
        echo "pass: learnings accounted for"
    fi
fi

if [ "$FAIL" -ne 0 ]; then
    exit 2
fi

# 8. Handoff file writing and overwrite in place (D11, AT-16, AT-19)
mkdir -p "$PRIMARY_REPO/ops/handoffs"
target_file=""

# Check if an existing file for this seat was written today by this session
if compgen -G "$PRIMARY_REPO/ops/handoffs/handoff-${SEAT}-${TODAY}*.txt" >/dev/null 2>&1; then
    for cand in "$PRIMARY_REPO/ops/handoffs"/handoff-"${SEAT}"-"${TODAY}"*.txt; do
        if [ -f "$cand" ] && grep -q "session: $SESSION_NAME" "$cand" 2>/dev/null; then
            target_file="$cand"
            break
        fi
    done
fi

if [ -z "$target_file" ]; then
    base_target="$PRIMARY_REPO/ops/handoffs/handoff-${SEAT}-${TODAY}.txt"
    if [ ! -f "$base_target" ]; then
        target_file="$base_target"
    else
        idx=1
        while [ -f "$PRIMARY_REPO/ops/handoffs/handoff-${SEAT}-${TODAY}-${idx}.txt" ]; do
            idx=$((idx + 1))
        done
        target_file="$PRIMARY_REPO/ops/handoffs/handoff-${SEAT}-${TODAY}-${idx}.txt"
    fi
fi

if [ "$SNAPSHOT" -eq 1 ]; then
    header_line="SNAPSHOT (session still running, written ${NOW_TIME}Z)"
else
    header_line="closed"
fi

cat <<HANDOFF_EOF > "$target_file"
$header_line
session: $SESSION_NAME
seat: $SEAT
date: $TODAY
status: $([ "$SNAPSHOT" -eq 1 ] && echo "snapshot" || echo "closed")
HANDOFF_EOF

# 9. Output report and resume block (D13, AT-1, AT-19)
abs_handoff_dir="$(cd "$(dirname "$target_file")" && pwd)"
abs_handoff_path="$abs_handoff_dir/$(basename "$target_file")"

if [ "$SNAPSHOT" -eq 0 ]; then
    echo "status: closed"
fi

echo "handoff:  $abs_handoff_path"
echo "resume:   ops/waves/seat.sh $SEAT"
echo "session:  ${CLAUDE_SESSION_ID:-$SESSION_NAME}"
echo "pointers: ops/waves/seat.sh --list, ops/waves/seat.sh --last"
echo "note: claude --resume is rejected; start a fresh session primed with the handoff"

exit 0
