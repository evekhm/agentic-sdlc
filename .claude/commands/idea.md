---
description: Manual intake door for a new idea — searches the tracker first, then files an intent:new issue.
argument-hint: <free text idea; may include "Given design:", "Given spec:", or "Given code:" sections>
allowed-tools: Bash(scripts/ops/intake.sh:*), Bash(scripts/ops/tracker_search.sh:*), Bash(gh issue create:*), Bash(gh issue view:*), Bash(gh issue list:*), Bash(gh search issues:*), Bash(gh search prs:*), Read, Write
---

`$ARGUMENTS` is the raw text of the idea. It may contain one or more
sections labelled `Given design:`, `Given spec:`, or `Given code:`.
Treat any such section as **authoritative input, verbatim**: never
re-derive it, never question it, never propose an alternative to
something a Given section already states. Only ask about genuine gaps
a Given section does not cover.

1. Draft a short title from the text.
2. Write a temporary body file (any placeholder content is fine for
   this pass — it is not filed yet) and run, WITHOUT `--file`:

   `scripts/ops/intake.sh --kind idea --title "<short title>" --body-file <temp file>`

   This runs `scripts/ops/tracker_search.sh`'s search only; nothing is
   filed by this step.

3. If it exits 2 (matches found): read the matches, including the
   comment threads on any matching issue or PR (AGENTS.md, "Before
   filing an issue", step 4). Then either comment on the existing
   issue extending it, or — if this idea is genuinely different — file
   a new issue that names the relationship to the existing one
   explicitly (absorbs/refines/depends on/supersedes). Never file a
   silent duplicate.

4. If it exits 0 (clear): compose the real issue body, in this order,
   omitting any section that does not apply:
   - Problem/Idea
   - Given design (only if supplied)
   - Given spec (only if supplied)
   - Given code (only if supplied)
   - Proposed outcome
   - Affected users and systems
   - Constraints
   - Relationships (state explicitly, or "tracker searched, no prior
     art: <what was searched>" per AGENTS.md's exact phrasing)
   - Open questions (only real gaps left after the Given sections)

   Write that body to a temp file, then re-run:

   `scripts/ops/intake.sh --kind idea --title "<same or refined title>" --body-file <file> --file`

   This actually files the issue (`intent:new`).

5. Print the created issue URL back to the user and stop. Do not
   claim the issue or start working it in this command.