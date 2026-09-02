# Skill: resume-protocol

How an actor resumes a cold issue. The tracker is the state and the
labels are the state machine (AGENTS.md, "Working the tracker");
this skill is the ordered procedure that turns one number into
either the stage's artifact or a refusal. It cites AGENTS.md
rather than restating it, and holds no copy of the label ladder:
that table is written once in `personas/lifecycle.json` and reaches
this prompt as the generated `## Lifecycle stages` section below.

**A number is the whole instruction.** The only input is the issue
or pull-request number; nothing naming a stage, a folder, an
artifact or a branch is accepted, because such an input would let a
session work a stage the labels say is not current.
`scripts/ops/work.sh <n>` performs steps 1, 2, 3 and 5
deterministically and prints what it resolved.

## Steps

1. **Read the issue.** Its open/closed state, its labels, and the
   thread bottom-up to the last handoff comment, which says where
   to resume. A pull-request number resolves to its issue first:
   `Closes #<n>` in the body, else the `<actor>/<n>-<slug>` branch
   name. The pull request is not the unit of work; the issue is.
2. **Apply the refusals below, in the order they are written,
   before any write.** A refusal is a report, never a partial claim.
3. **Derive the stage** from the single `status:*` label. An issue
   carrying `intent:new` and no `status:*` label is at the first
   rung of the ladder.
4. **Claim.** Add `in-progress` and post the one-line claim saying
   who is working and at what stage (AGENTS.md, "Working the
   tracker", step 2).
5. **Resolve the folder and the branch.** If exactly one
   `intent/<n>-*/` directory exists, use it. If none exists, derive
   the slug from the issue title: cut it at the first `:` or `;`,
   lowercase it, replace every run of characters outside `[a-z0-9]`
   with `-`, trim leading and trailing `-`, then truncate to at most
   24 characters at the last `-` that leaves a non-empty slug. More
   than one existing folder is corrupted state — refuse and name
   them. The branch is `<actor>/<n>-<slug>`.
6. **Produce the stage's artifact** — the one the lifecycle source
   names for that stage, and only that one.
7. **Hand off** with one pull request plus the
   Done/Decided/Next/Blocked comment (AGENTS.md). Remove
   `in-progress` if pausing rather than finishing.

## Refusals

Checked in this order, before any write:

1. **`hold` is present.** Write nothing at all, not even the claim.
   The circuit breaker is absolute (trusted-posting, rule 5).
2. **The issue is closed, or carries `status:review-stuck`.**
   Humans have taken over.
3. **`blocked` is present.** Report and stop.
4. **More than one `status:*` label.** Corrupted state: report the
   labels found and stop — without guessing which is true, and
   without applying `hold`. The stage advancer is the single writer
   of the circuit breaker, and two writers is two circuit breakers.
5. **`in-progress` is present and the last claim comment names a
   different actor.** Stop and name the holder. The same label with
   a claim naming this actor is a resume of its own work and
   proceeds.
6. **The derived stage is not one this actor owns.** Name the
   owner(s) of that stage and stop.
