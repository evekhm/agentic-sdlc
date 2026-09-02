# Intent: the label taxonomy and the stage advancer

**Issue:** #4 · **Status:** accepted on merge of this PR

## Problem

INTENT.md commits to one thing about lifecycle state: it "lives in
GitHub issue labels, never in a chat transcript." AGENTS.md repeats
it — "Lifecycle state lives in the issue's labels, never in prose."
Neither says which labels. Five exist (`bootstrap`, `intent:new`,
`in-progress`, `hold`, `blocked`); none of them names a lifecycle
stage. The state machine the whole design rests on currently has no
states.

Two consequences, both already visible. A session that wants to know
where an issue stands has to read the issue's folder and infer the
stage from which files exist — which is the transcript problem again,
just moved into a directory listing. And the automation queued behind
this one (#8, #9, #10) has nothing to condition on: a review workflow
that cannot ask "is this issue in review?" ends up asking a model, and
a model asked a question a `grep` answers is a bill, not a design.

The second half of the problem is drift. The predecessor system used
`argus:*` and `review:*`; agent-farm used a seven-phase `status:*`
set. Adopting neither, or both, leaves every future workflow author
inventing a name. Names invented per workflow are names that disagree.

## Proposed outcome

One taxonomy, decided once and provisioned by the script that already
provisions labels; plus the first thing that writes it, so the
taxonomy ships proven rather than aspirational.

- **The taxonomy** — the five human-facing labels kept as they are,
  a `status:*` ladder for machine-driven stage state with the
  invariant that exactly one is set at a time, `review:1..3` as the
  iteration counter, and `status:review-stuck` as its escalation.
- **The writer** — `.github/workflows/lifecycle.yml`, which watches
  pushes to `main` and mirrors each merge gate into the ladder:
  intent.md merged → `status:spec`, an *Approved* spec.md →
  `status:build`, plan.md → `status:implementing`. Deterministic bash,
  no model call, runnable on a laptop against the same range CI reads.

The advancer does not decide anything. INTENT.md already says the
merge IS the transition; this makes the transition legible without
moving the authority. A human still merges, and a human can still
overrule the label by hand.

## Affected users and systems

Every issue from intake onward, and every workflow that follows this
one: the review automation (#8, #9) writes `status:in-review` and the
`review:N` counter into the taxonomy defined here rather than
inventing its own, and the intake agent (#10) has a defined first
state to leave the issue in. Humans reading the tracker get the stage
at a glance instead of by archaeology. Presenters get a demo whose
whole cost is a GitHub Actions minute.

## Constraints

- **No model calls anywhere in the shipped automation.** A merged path
  and a `Status:` line are the entire input.
- **`hold` outranks everything.** A circuit breaker automation gets a
  vote on is not a circuit breaker.
- **Every write idempotent.** A re-run of a range must be a no-op, or
  nobody will dare re-run one after a partial failure.
- **Least privilege.** `issues: write`, `contents: read`, the default
  token, no secrets, no persona identity.
- Provisioning extends `scripts/setup/bootstrap_tracker.sh` — no new
  script — and must be runnable long after that script's issue bodies
  have drifted.

## Open questions

None — resolved in [spec.md](spec.md). The taxonomy itself was decided
on the issue thread (proposal comment, then "Decision: adopted as
proposed", 2026-09-01); this folder records it, it does not re-open it.
