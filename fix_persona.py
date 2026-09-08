import sys
content = open('scripts/ci/lifecycle_advance.sh').read()

replacement = """
    # Determine persona from the rung by scanning personas/*.yaml for the NEW stage
    NEW_STAGE=$(jq -r --arg t "$target" '.stages[] | select(.label == $t) | .stage' "$LIFECYCLE_JSON" 2>/dev/null || true)
    PERSONA=""
    if [[ -n "$NEW_STAGE" && "$NEW_STAGE" != "null" ]]; then
        for p_file in "$REPO_ROOT"/personas/*.yaml; do
            if grep -q "kind: persona" "$p_file" 2>/dev/null; then
                if python3 -c "import sys, yaml; d=yaml.safe_load(open(sys.argv[1])); sys.exit(0 if sys.argv[2] in d.get('stage', []) else 1)" "$p_file" "$NEW_STAGE" 2>/dev/null; then
                    PERSONA=$(basename "$p_file" .yaml)
                    break
                fi
            fi
        done
    fi

    if [[ -n "$PERSONA" ]]; then
"""

start_idx = content.find("    # Determine persona from the rung")
end_idx = content.find("    if [[ -n \"$PERSONA\" ]]; then")

new_content = content[:start_idx] + replacement.strip() + "\n" + content[end_idx + len("    if [[ -n \"$PERSONA\" ]]; then"):]

with open('scripts/ci/lifecycle_advance.sh', 'w') as f:
    f.write(new_content)
