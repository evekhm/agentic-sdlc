---
description: Manual intake door for a defect — searches the tracker first, then files an intent:new + bug issue.
argument-hint: <free text describing the bug: repro, expected vs actual; may include "Given design:", "Given spec:", or "Given code:" sections>
allowed-tools: Bash(scripts/ops/intake.sh:*), Bash(scripts/ops/tracker_search.sh:*), Bash(gh issue create:*), Bash(gh issue view:*), Bash(gh issue list:*), Bash(gh search issues:*), Bash(gh search prs:*), Read, Write
---

`$ARGUMENTS` is the raw text describing the bug. It may contain one or
more sections labelled `Given design:`, `Given spec:`, or `Given
code:`; treat those as **authoritative input, verbatim** — never
re-derive or question them, only ask about genuine gaps they do not
cover.

Before drafting anything, check that the raw text supplies all four
of: reproduction steps, expected behavior, actual behavior, and
evidence (command output, error text, or a file:line). Given sections
count toward satisfying these even if worded differently. If one or
more is missing, ask the user for exactly the missing piece(s) in ONE
question — not a checklist — and wait for the answer before
continuing.

1. Draft a short title from the text.
2. Write a temporary body file (any placeholder content is fine for
   this pass — it is not filed yet) and run, WITHOUT `--file`:

   `scripts/ops/intake.sh --kind bug --title "<short title>" --body-file <temp file>`

   This runs `scripts/ops/tracker_search.sh`'s search only; nothing is
   filed by this step.

3. If it exits 2 (matches found): read the matches, including the
   comment threads on any matching issue or PR (AGENTS.md, "Before
   filing an issue", step 4). Then either comment on the existing
   issue extending it, or — if this is genuinely a different defect —
   file a new issue that names the relationship to the existing one
   explicitly (absorbs/refines/depends on/supersedes). Never file a
   silent duplicate.

4. If it exits 0 (clear): compose the real issue body, in this order,
   omitting any section that does not apply:
   - Problem (repro steps, expected vs actual, evidence)
   - Given design (only if supplied)
   - Given spec (only if supplied)
   - Given code (only if supplied)
   - Proposed outcome
   - Affected users and systems
   - Constraints
   - Relationships (state explicitly, or "tracker searched, no prior
     art: <what was searched>" per AGENTS.md's exact phrasing)
   - Open questions (only real gaps)

   Write that body to a temp file, then re-run:

   `scripts/ops/intake.sh --kind bug --title "<same or refined title>" --body-file <file> --file`

   `intake.sh` applies both `intent:new` and `bug` labels automatically
   for `--kind bug`; no extra labeling step is needed here.

5. Print the created issue URL back to the user and stop. Do not
   claim the issue or start working it in this command.
