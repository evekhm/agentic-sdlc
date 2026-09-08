import sys
content = open('scripts/ci/lifecycle_advance.sh').read()

replacement = """
    if [[ "$target_rank" -gt 0 && "$target_rank" -eq "$HIGHEST_MERGED_RANK" ]] && echo "$LEDGER_COMMENT" | grep -qF "head-oid:$AFTER"; then
        log "    #$issue is already recorded at rank $target_rank for head $AFTER — idempotent green exit"
        continue
    elif [[ "$target_rank" -lt "$HIGHEST_MERGED_RANK" ]] || ( [[ "$target_rank" -gt 0 && "$target_rank" -eq "$HIGHEST_MERGED_RANK" ]] && ! echo "$LEDGER_COMMENT" | grep -qF "head-oid:$AFTER" ); then
        echo "::error::lifecycle_advance: refusal reason-code: non-monotonic for #$issue" >&2
        fail_issue "refusal reason-code: non-monotonic for #$issue"
        # Write refusal row to ledger
        post_comment "$issue" "<!-- loop-ledger-row: refusal:non-monotonic rung:$target_rank head-oid:$AFTER pr:${BEST_PR[$issue]:-} -->" || true
        bash "$REPO_ROOT/scripts/ci/escalate.sh" "$issue" --reason "non-monotonic" --head "$AFTER" 2>/dev/null || true
        continue
    fi
"""

start_idx = content.find("    if [[ \"$target_rank\" -eq \"$HIGHEST_MERGED_RANK\" ]]")
end_idx = content.find("    edit_labels \"$issue\" \"$target\" \"$remove\"")

new_content = content[:start_idx] + replacement.strip() + "\n\n" + content[end_idx:]

with open('scripts/ci/lifecycle_advance.sh', 'w') as f:
    f.write(new_content)
