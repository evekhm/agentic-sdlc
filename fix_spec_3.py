import sys
content = open('docs/SPEC.md').read()
import re
new_content = content.replace("if a missing or unreadable loop limits", "if the loop limits are missing or unreadable")
new_content = new_content.replace("merges the pull request itsel", "merges the pull request itself")
with open('docs/SPEC.md', 'w') as f:
    f.write(new_content)
