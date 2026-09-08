import sys
content = open('docs/SPEC.md').read()

replacement = """
### loop.autonomous
The loop merges itself autonomously when consensus is reached. Loop limits are defined in the `loop:` block in `config/execution.yaml` (D20):
- `loop.autonomous_merge`: boolean (`true`/`false`). When `true`, D5 runs its 11-conjunct guard logic and merges the pull request itself if all hold; when `false`, D5 runs its guard logic but drops its outcome and merges nothing.
- `loop.max_rung_dispatches_per_issue`: integer (e.g. 10). The maximum number of autonomous dispatches (any stage) allowed on one issue. A dispatch that would exceed this budget exits 0 and writes a `refusal:budget` row.
- `loop.max_cost_usd_per_issue`: float (e.g. 50.0). The maximum accumulated spend allowed on one issue. A dispatch that would exceed this budget exits 0 and writes a `refusal:budget` row.

If the loop limits are missing or unreadable, the gate fails closed. D13/D14 enforce monotonic progress on a loop ledger and D15 enforces hold/blocked. 
An escalation writes the `status:review-stuck` label (never `status:escalated`).
"""

import re
new_content = re.sub(r'### loop\.autonomous\n.*', replacement.strip() + "\n", content, flags=re.DOTALL)

with open('docs/SPEC.md', 'w') as f:
    f.write(new_content)
