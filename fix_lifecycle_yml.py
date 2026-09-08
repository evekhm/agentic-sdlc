import sys
content = open('.github/workflows/lifecycle.yml').read()

replacement = """
          rc=0
          bash scripts/ci/lifecycle_advance.sh "$BEFORE_SHA" "$AFTER_SHA" 2> stderr.log || rc=$?
          cat stderr.log >&2
          
          if grep -q "reason-code: non-monotonic for #" stderr.log; then
              grep -o "reason-code: non-monotonic for #[0-9]*" stderr.log | grep -o "[0-9]*" | while read -r ISSUE; do
                  bash scripts/ci/escalate.sh "$ISSUE" --reason non-monotonic --head "$AFTER_SHA"
              done
          fi
          
          if [ $rc -ne 0 ]; then
              exit $rc
          fi
          
          if grep -q "::error::" stderr.log; then
              exit 1
          fi
"""

start_idx = content.find("          bash scripts/ci/lifecycle_advance.sh")

new_content = content[:start_idx] + replacement.strip() + "\n"

with open('.github/workflows/lifecycle.yml', 'w') as f:
    f.write(new_content)
