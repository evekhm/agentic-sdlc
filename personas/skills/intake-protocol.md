# Skill: intake-protocol

Turn a raw ask into one tracked, linked, scoped item. You run this at
the front door, before any issue exists, and again at PLAN before the
intent PR opens.

## Protocol

1. **Scope first, file last.** Ask the human one question per turn:
   who is affected, what changes for them, what stays out, how anyone
   would know it worked. Stop after three rounds or when answers
   repeat; write the draft from the answers and read it back for
   confirmation.
2. **Search before you write.** Run the tracker search (AGENTS.md,
   "Before filing an issue") with the paths and key terms of the ask;
   list open issues on the same area; read every match including its
   comment thread. Agreed findings in a thread are settled design.
3. **Read the decisions of the neighbours.** For every related intent
   folder open spec.md and read its Decisions table. Quote each
   decision the ask touches by ID (#n Dm). A decision the ask would
   reverse goes into the draft as an explicit reversal; a silent
   contradiction is a defect.
4. **Name every relationship.** The body carries a Relationships
   section: one line per related item with its number and one verb:
   absorbs, refines, depends on, supersedes. Nothing related found:
   write "tracker searched, no prior art:" followed by the labels and
   terms used.
5. **One problem, one thread.** An open issue already owns the
   problem: comment there with the new evidence and stop. An ask
   larger than one rung: split into a parent and children, linked both
   ways.
6. **House shape.** Problem, Proposed outcome, Affected users and
   systems, Constraints, Relationships, Open questions, Non-goals.
   Every section filled, or marked "none" with the reason.
7. **Search again before the PR.** Rerun the tracker search
   immediately before opening the intent PR. A match between filing
   and PR is the check working.

## Refusals

- A second issue for a problem an open thread owns.
- An intent that touches a recorded decision without naming it.
- Filing before the human confirmed the read-back (interactive), or
  while the body lacks a Relationships section (headless).

## Exit condition

An issue labeled intent:new whose body carries the house shape and a
Relationships section, or a comment on the existing thread and no new
issue.
