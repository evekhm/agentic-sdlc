# agentic-sdlc

You are the operator at the keyboard — the presenter running this
workshop, or an attendee following along on your own clone. The first
four sections tell you what this repository is and why; the rest walk
one change through the whole loop. Your entire job is two actions,
repeated: typing a number, and merging a pull request.

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

## Why this exists

Three motivations stack on top of each other.

**The playbook made concrete.** The AI-native SDLC playbook
([`docs/BLOG.md`](docs/BLOG.md)) argues that code is no longer the
bottleneck; planning, review and governance are. It proposes a loop in
which every stage commits an artifact and that commit starts the next
stage. The playbook describes the loop in prose, for one harness.
Nothing demonstrated the whole loop with real GitHub identities, more
than one harness, review by two model families and cost discipline in
one clonable repository. This repository is that demonstration.

**One workflow, each harness where it fits best.** The goal is not to
crown a harness. It is to run one lifecycle across several of them and
to place each role on the harness and model family that returns the
most per dollar. The working thesis: a fast, inexpensive model family
is the workhorse and carries the bulk of the mechanical, implementation
and review-reading work; a frontier family is uniquely strong at design
and at the hardest code, and far more expensive, so it is spent only
where its reasoning changes the outcome — interrogating a spec, a
tricky design, the implementation nobody else can land. The best result
at the best cost comes from making them work together, and the persona
compiler plus the pins in `config/` are what let the placement change
without touching the workflow. Which family sits where is a fact in
[`config/model_tiers.yaml`](config/model_tiers.yaml) and
[`config/deployments.yaml`](config/deployments.yaml), and appears in no
other document.

**A workshop that proves it live.** The format is a presenter-driven
demo plus a take-home template. Because the demo is the system building
itself, every rung the audience watches is a real change landing in
this repository, and the presenter's whole job is the two actions
above.

## The cast

Six personas, each its own GitHub App with its own bot identity, each
defined once in `personas/<name>.yaml` with no vendor named:

- **Athena**, the product owner, works the plan and design rungs at the
  frontier tier. Her protocol is adversarial: one ambiguity at a time,
  two defensible readings, never a recommendation, every resolution a
  numbered decision.
- **Daedalus**, the architect, works the build rung at the frontier
  tier: the order of work and the check that proves each decision
  landed.
- **Odyssey**, the implementer, works the implement rung at the
  implementation tier, dispatched at a pinned commit against an
  approved spec and a committed plan.
- **Argus** and **Atlas**, the two reviewers, work the review rung at
  the review tier on two distinct model families, comment-only.
- **Cassandra**, the maintainer, watches metrics against control bands
  and files a new intent when one breaks, at the fast tier. Maintain
  has no rung on the ladder yet.

Five sub-agents with no GitHub identity — mechanic, coder,
contract-writer, scanner, explorer — do the delegated work a persona
hands off so that raw material never enters the persona's own context.

**Tiers, not prices.** A persona declares the kind of work it does,
on a five-grade ladder: fast (sweeps, lookups, routing), mechanical
(batch edits, greps, test runs), implementation (coding against a
dispatch-ready spec), review (evidence-based reading), frontier
(design, interrogation, the hardest debugging). Each harness binds the
tiers to its own models in `config/model_tiers.yaml`; adjacent tiers may
share a model. Repinning a persona to another harness is a one-line
change in `config/` followed by a compiler run — the tier ladder is
[AGENTS.md, "Subagent model tiers"](AGENTS.md#subagent-model-tiers).

**The compiler.** [`scripts/sync_agents.py`](scripts/sync_agents.py)
reads `personas/` and `config/` and emits the prompt files each harness
actually loads. The generated files are committed, and a CI gate
recompiles them and fails the build if they drift from their sources.
It exists because the predecessor repository hand-maintained one prompt
per harness and they diverged within days; "one persona, every
harness" is a demonstrated fact here rather than a claim. What it
emits and how is [`docs/SPEC.md`](docs/SPEC.md) `personas.compiler`.

## How it builds itself

The system could not run its own loop before the loop existed, so its
backlog is organised as a bootstrap ladder, indexed by one pinned
tracker issue that lists every rung and ticks items off as they land:

- **Rung 1, wizard of Oz.** A human authored the persona sources, the
  config and the review protocol. Personas ran by hand, as sub-agents
  of the operator's own session.
- **Rung 2, the machinery.** The compiler, the CI gates, the label
  taxonomy, the bot identities, the one-command dispatcher, this
  document, and launching any persona on its own harness.
- **Rung 3, unattended personas.** The reviewers as event-driven
  workflows and the product owner picking up `intent:new` on her own,
  which first needs the execution model that decides where each persona
  runs.
- **Rung 4, maintain.** Deterministic watchers and a seeded incident
  that files a new intent — the loop closing on itself.
- **Rung 5, packaging.** The personas compiled into an installable
  plugin for the take-home.

From rung 2 on, every feature of this repository is delivered through
the repository's own ladder: an `intent/<n>-<slug>/` folder holding the
intent, the spec and the plan; a spec authored under the persona's own
App identity; a persona-namespaced branch; commits that cite reviewer
finding ids. The audit trail the playbook asks for is the git history.
Where the system cut a corner it wrote that down too, as an explicit,
non-precedent deviation in the spec that cut it. What is merged and
behaving today — and what is agreed but not yet built — is
[`docs/SPEC.md`](docs/SPEC.md); trust it over any narrative, this one
included.

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

The transition itself is a deterministic workflow with no model call:
on a merge to the default branch it reads which artifact file was
added, looks the next stage up in `personas/lifecycle.json`, moves the
label and posts a stamped comment. The merge is the gate; the label is
its shadow.

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
intent/spec/plan triple: issue, fix pull request with a regression
check, review, human merge. A repair that changes a spec entry is a
change, and re-enters at plan. The rule is stated normatively in
[INTENT.md, "Defect repair"](INTENT.md).

## Where the rules actually live

- [AGENTS.md](AGENTS.md) — the cross-harness standard every session
  reads: working the tracker, run folders, cost discipline, the tier
  ladder, the context ceiling.
- [INTENT.md](INTENT.md) — why this system exists, what the workshop
  sets out to prove, and the questions still open.
- [`docs/SPEC.md`](docs/SPEC.md) — the living spec: what is built
  today, keyed by capability, and what is agreed but not yet built.
  Trust it over memory.
- [REVIEW.md](REVIEW.md) — the protocol both reviewers compile against.
- [`docs/BLOG.md`](docs/BLOG.md) — the playbook this loop implements.
- [`docs/CONTEXT.md`](docs/CONTEXT.md) — the prior art it was built on,
  and what was adopted from each.
- [`config/`](config/) — the only place a harness, vendor or model
  family is named: tier bindings, deployment pins, tools.
- The pinned tracker issue in this repository's issue tracker — the
  live dashboard of the ladder. There is deliberately no status file.

This file explains and never duplicates: it is normative for nothing,
and wherever it and one of those documents disagree, the other is
right. A new topic is a link from this section, or a deliberate
addition to the section list in this document's own spec under
`intent/`, never a drop-in section that list does not name.
