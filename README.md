# agentic-sdlc

You are the operator at the keyboard — the presenter running this
workshop, or an attendee following along on your own clone. This is the
walkthrough of one change through the whole loop. Your entire job is
two actions, repeated: typing a number, and merging a pull request.

## The loop in one picture

This repository builds its own development lifecycle. A cast of
personas is defined once as source files and compiled into the prompts
their harnesses run; each works one rung of a five-rung ladder that
ends, every rung, in a pull request a human merges. Why any of this
exists is [INTENT.md](INTENT.md).

```text
issue filed (intent:new)
   |
   v
plan  ->  design  ->  build  ->  implement  ->  review
 |          |          |           |              |
intent.md  spec.md   plan.md      code         findings
```

One pull request per rung. Nothing advances because a session declares
itself done; it advances because you merged something.

## Before you start

**A clone of this repository**, on a branch you can push.

**The six persona private keys.** Each persona is its own GitHub App,
and its key is what lets your machine act as that persona; keys live
outside the repository and are never committed. Registering the Apps
and minting a token is [`scripts/auth/README.md`](scripts/auth/README.md).

**`gh` and `jq`**, authenticated against this repository. Labels and
backlog are provisioned idempotently by
[`scripts/setup/`](scripts/setup/), run once per fork.

## File the change

**Humans file issues.** No persona opens an intake issue — Atlas
included: a reviewer's findings belong in the pull request thread that
raised them, never as new issues. Search the tracker before you file,
every time, per [AGENTS.md, "Before filing an
issue"](AGENTS.md#before-filing-an-issue).

Every issue enters with `intent:new` and no `status:*` label. That is
not decoration: it is precisely what makes the item's current rung
`plan` to a session that has never seen it. Say what the problem is and
what would be true if it were solved — the first rung writes the rest.

## Type the number

Your whole typed input, at every rung, for every item:

```bash
scripts/ops/work.sh <n>
```

`<n>` is an issue or pull request number; a pull request resolves to
the issue it closes. Nothing else is passed — no stage, folder, branch
or artifact — because a flag naming one would let a session work a rung
the labels say is not current. It reads the labels and the repository,
prints what it resolved (stage, label, artifact owed, owning persona,
intent folder, branch, and the one-line brief the session is handed)
and starts that session; where a persona's pinned harness cannot be
started for you it prints the equivalent instruction and exits cleanly.
It refuses, before anything starts, when the item is on hold, closed,
blocked, claimed by another actor, or in contradictory state. Full
contract: [`docs/SPEC.md`](docs/SPEC.md) `ops.dispatch`.

## What happens at each gate

**Plan.** Athena writes `intent.md` into `intent/<n>-<slug>/`: problem,
outcome, constraints, open questions. Merging it moves the item to
design.

**Design.** Athena turns that into `spec.md` — numbered decisions with
rationale plus an acceptance list, approved only with no open question
left. Merging it moves the item to build.

**Build.** Daedalus writes `plan.md`: the order of work and the check
proving each decision landed. Merging it moves the item to implement.

**Implement.** Odyssey writes the code and the tests against that plan.
Merging that pull request moves the item to review.

**Review.** Two reviewers read the change and post findings; this rung
ends the ladder and the human closes the item. Which label means which rung,
and what each posts, is [`docs/SPEC.md`](docs/SPEC.md) `lifecycle.labels`.

## What you merge

A merged pull request is the human product owner's acceptance of the
artifact it carries — the whole meaning of the gate, and the same
meaning at all five rungs. A closed pull request is a rejection, and a
rejection is not relitigated. When a decision in the artifact is wrong,
**edit it in the pull request**: the edited row *is* the decision, so
you never comment asking for a change and wait for a session to make
it. You are the sole merge authority on every path. See [REVIEW.md,
"Merge is the escape hatch"](REVIEW.md#merge-is-the-escape-hatch).

## Review

Two independent reviewers read every implementing pull request, pinned
to different model families so a blind spot in one is not a blind spot
in both. Which family backs which reviewer is a fact in `config/` and
appears in no document, prompt or persona source: a reviewer's identity
is its role, its finding namespace and its account. Both are
comment-only — neither approves, merges, closes, nor edits a label.

Until the automation lands, review is dispatched by hand like every
other rung: the one command, on the pull request number. Because that
rung has two owners it prints both instructions and launches neither
unless you name one with `--as <persona>`. The protocol — severity
tiers, the round funnel, the ledger, consensus — is
[REVIEW.md](REVIEW.md), as `review.policy` in [`docs/SPEC.md`](docs/SPEC.md).

## When something is wrong

`hold` halts all automation absolutely while it is present; it is the
circuit breaker and nothing steps past it. `blocked` means a session
stopped and reported rather than guessed. More than one `status:*`
label is corrupted state rather than a state, and is reported, never
guessed at. A third reviewer iteration, `review:3`, escalates the item
to `status:review-stuck` for a human. Each label's semantics are
[`docs/SPEC.md`](docs/SPEC.md) `lifecycle.labels`.

When merged work turns out to be wrong, file the defect as its own
issue. If its `docs/SPEC.md` entry is unchanged, the repair skips the
intent/spec/plan triple: issue, fix PR with a regression check, review,
human merge. A spec-changing repair re-enters at PLAN. Ratified on #32.

## Where the rules actually live

- [AGENTS.md](AGENTS.md) — the cross-harness standard every session
  reads: working the tracker, run folders, cost discipline.
- [INTENT.md](INTENT.md) — why this system exists and what the
  workshop sets out to prove.
- [`docs/SPEC.md`](docs/SPEC.md) — the living spec: what is built
  today, keyed by capability.
- [REVIEW.md](REVIEW.md) — the review protocol both reviewers compile
  against.
- [`docs/CONTEXT.md`](docs/CONTEXT.md) — the prior art it was built on.

This file explains and never duplicates: it is normative for nothing,
and wherever it and one of those documents disagree, the other is
right. A tenth topic is a link from this section, never a tenth section.
