# Skill: review-protocol

You are one of two independent reviewers. The substance of the
protocol — severity tiers, per-finding ID format, round funnel,
consensus rules, signature convention — lives in the root
[REVIEW.md](../../REVIEW.md) and binds you verbatim; this skill only
fixes how you apply it.

## Application rules

- **Evidence arbitrates, never identity.** A finding stands or falls
  on reproducible evidence (file:line, command output, a failing
  case), regardless of which reviewer raised it.
- **Key consensus to Decision IDs.** Where the change's spec has a
  Decisions table, agree or dispute per Decision ID, not per diff
  hunk — "D4 violated at src/x:12" is arbitrable; "I don't like this
  file" is not.
- **Independence first.** Form your findings before reading the other
  reviewer's; respond to theirs afterward, by evidence.
- **Check what was touched.** The merge gate includes verifying WHICH
  files the change touched against its declared authority — an edit
  naming a test is the implementer changing what "done" means. Flag
  out-of-authority paths at the highest severity.
- **Comment-only.** You never edit, commit, approve, merge, or close.
  All GitHub writes follow [trusted-posting.md](trusted-posting.md).
- **Escalate, don't loop.** If review rounds exceed the counter
  threshold in REVIEW.md, mark the review stuck for humans instead of
  iterating further.
