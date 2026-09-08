import sys
content = open('scripts/ci/lifecycle_advance.sh').read()

import re

# We will replace lines 857-876 with our new logic
# We can use string replacement

replacement = """
    # D14 Monotonic progress check
    # Locate ledger by paginating exhaustively (D13)
    ALL_COMMENTS="$(gh api --paginate "repos/$GITHUB_REPO/issues/$issue/comments" -q '.[].body' 2>/dev/null)" || {
        fail_issue "could not read comments for #$issue to find loop ledger"
        continue
    }
    
    LEDGER_COMMENT="$(echo "$ALL_COMMENTS" | awk '/<!-- loop-ledger:'"$issue"' -->/{flag=1; print; next} /<!-- loop-ledger-end -->/{if(flag){print; flag=0; next}} flag' || true)"
    
    if [[ -z "$LEDGER_COMMENT" ]]; then
        HIGHEST_MERGED_RANK=0
    else
        HIGHEST_MERGED_RANK=$(echo "$LEDGER_COMMENT" | grep -oE 'rung:[0-9]+' | grep -oE '[0-9]+' | sort -nr | head -1 || echo 0)
    fi
    if [[ -z "$HIGHEST_MERGED_RANK" ]]; then HIGHEST_MERGED_RANK=0; fi

    if [[ "$target_rank" -eq "$HIGHEST_MERGED_RANK" ]] && echo "$LEDGER_COMMENT" | grep -qF "head-oid:$AFTER"; then
        log "    #$issue is already recorded at rank $target_rank for head $AFTER — idempotent green exit"
        continue
    elif [[ "$target_rank" -lt "$HIGHEST_MERGED_RANK" ]] || [[ "$target_rank" -eq "$HIGHEST_MERGED_RANK" ]]; then
        echo "::error::lifecycle_advance: refusal reason-code: non-monotonic for #$issue" >&2
        fail_issue "refusal reason-code: non-monotonic for #$issue"
        # Write refusal row to ledger
        post_comment "$issue" "<!-- loop-ledger-row: refusal:non-monotonic rung:$target_rank head-oid:$AFTER pr:$merge_pr -->" || true
        bash "$REPO_ROOT/scripts/ci/escalate.sh" "$issue" --reason "non-monotonic" --head "$AFTER" 2>/dev/null || true
        continue
    fi
"""

# Find the start and end indices
start_idx = content.find("    # D14 Monotonic progress check")
end_idx = content.find("    edit_labels \"$issue\" \"$target\" \"$remove\"")

new_content = content[:start_idx] + replacement.strip() + "\n\n" + content[end_idx:]

with open('scripts/ci/lifecycle_advance.sh', 'w') as f:
    f.write(new_content)

