import sys
content = open('docs/SPEC.md').read()
import re
new_content = re.sub(r'status:escalated', 'status:review-stuck', content)
with open('docs/SPEC.md', 'w') as f:
    f.write(new_content)
