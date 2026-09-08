import sys
content = open('docs/SPEC.md').read()

replacement = r"""
- `loop.autonomous_merge`: boolean. When `true`, D5 runs its 11-conjunct guard logic and merges the pull request itself if all hold; when `false`, D5 runs its guard logic but drops its outcome and merges nothing.
- `loop.max_rung_dispatches_per_issue`: integer (e.g. 10). The maximum number of autonomous dispatches (any stage) allowed on one issue. A dispatch that would exceed this budget exits 0 and writes a `refusal:budget` row.
- `loop.max_cost_usd_per_issue`: float (e.g. 50.0). The maximum accumulated `WORK_COST_FILE` spend allowed on one issue. A dispatch that would exceed this budget exits 0 and writes a `refusal:budget` row.
"""

import re
new_content = re.sub(r'- `loop.autonomous`:.*?- `loop.max_dispatches_per_issue`:.*?- `loop.max_cost_usd`:.*?(?=\n-|$)', replacement.strip(), content, flags=re.DOTALL)

with open('docs/SPEC.md', 'w') as f:
    f.write(new_content)
