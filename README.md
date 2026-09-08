# agentic-sdlc

**TL;DR:** a harness-agnostic AI SDLC loop that stays high-quality and
cost-effective by placing every stage on whichever harness and model
family fits it best — cheap capacity for volume, expensive judgment
only where it changes the outcome (the [cost
thesis](#two-harnesses-two-model-families)).

A software development lifecycle run by AI agents. A GitHub issue
goes in. Reviewed, merged code comes out. A cast of AI personas plans,
designs, builds, implements, reviews and maintains the software. A
human sets direction and is called only on escalation. The system is
built with its own loop. It follows the
[AI-native SDLC playbook](https://claude.com/blog/the-ai-native-sdlc-playbook).
Every issue link in this file points at the tracker item that owns
that part of the design.

## What this is

Two kinds of actors appear in this document.

A **persona** is an AI agent. It has a name, one job, a protocol and
its own GitHub account. Athena is the product owner. Daedalus is the
architect. Odyssey is the implementer. Argus and Atlas are the two
reviewers. Cassandra is the maintainer. Nestor is the advisor. A
persona runs inside a coding harness, Claude Code or Antigravity, on
a model chosen for its job.

The **owner** is the human who runs the repository. The owner speaks
intent: an idea, a problem, an outcome wanted, written as a GitHub
issue in plain language. The owner answers the questions the personas
ask back, and decides escalations. What comes out the other end is
specified, planned, implemented, tested and reviewed work, merged on
the default branch. Every lesson learned on the way, a rule a persona
had to be told, a gap a check missed, a measurement that drifted,
comes back as a new issue. The system consumes intent and produces
working software and a better version of itself.

The loop has five steps. Every issue climbs them in order. Each step is
a **rung**. Each rung ends in a pull request that carries one
artifact. Atlas, the cheap reviewer, reads every pull request. Argus,
the deep reviewer, joins at the code gate or can be requested on demand. A pull request merges when
its assigned reviewers have no open blocking finding — a security or
high defect, per [REVIEW.md](REVIEW.md)'s severity tiers. A suggestion
or a normal-tier defect is recorded and never gates the merge. The merge means accepted,
and it moves the issue to the next rung. The chain of merges is the audit trail: who asked for
what, what the persona produced, who accepted it.

```text
issue filed (intent:new)
   |
   v
plan  ->  design  ->  build  ->  implement  ->  review  ->  close
Athena    Athena    Daedalus    Odyssey      Argus+Atlas
intent.md spec.md   plan.md     code         findings
                                                  |
                          maintain: Cassandra files the next issue
```

The software under development is this system. A person wrote the
first persona sources and the review protocol by hand. From then on
the personas build the rest through their own loop: the compiler, the
label state machine, the unattended reviewers, the orchestrator and
the cost tooling. The folders under [`intent/`](intent/) are the
record of that. The repository is also a workshop: a presenter drives
one real change through every rung in front of an audience, and the
audience takes the repository home ([INTENT.md](INTENT.md)).

## The cast

Each persona is defined once in [`personas/`](personas/) by the stage
it owns, the protocol it runs, the authority it holds, the tier it
thinks at, and the GitHub identity it acts as.

- **Athena, the product owner.** Talks with the filer, writes
  `intent.md`, then writes `spec.md` under an adversarial protocol.
  Writes only under `intent/`. Frontier tier.
- **Daedalus, the architect.** Turns an approved spec into `plan.md`
  and the failing contract tests. Reads code and writes none.
  Frontier tier.
- **Odyssey, the implementer.** Writes the code that makes the tests
  pass. Starts at a pinned commit in its own branch namespace. One
  pull request per rung. Implementation tier.
- **Atlas, the reviewer and verifier of every gate.** Reads every pull
  request at every rung on Gemini, the cheap seat. Posts findings with
  severity and ids. Runs the verification checklist for the rung: the
  intent lost nothing from the issue, the spec has no open question and
  every acceptance row is runnable, the contract tests fail before the
  code exists, the job log behind every green check says what the
  check claims. Never approves, merges, closes or edits a label. Review
  tier ([#204](https://github.com/evekhm/agentic-sdlc/issues/204)).
- **Argus, the second family at the code gate.** Joins at the implement
  rung, on any change to a trust-bearing path, and on a `review:deep`
  grant. Runs the same protocol on Claude, the other family, plus the
  deep checks: mutation-tests the tests, re-runs the gates, reads the
  diff in full. Comment-only like Atlas. Review tier
  ([#265](https://github.com/evekhm/agentic-sdlc/issues/265)).
- **The merge identity.** Merges in autonomous mode when the assigned
  reviewers are clean. It belongs to no persona, so no persona merges
  its own work
  ([#64](https://github.com/evekhm/agentic-sdlc/issues/64),
  [#251](https://github.com/evekhm/agentic-sdlc/issues/251)).
- **Cassandra, the maintainer.** Runs watchers over the live system.
  When a control band breaks she files the next issue. Fast tier for
  sweeps, review tier for diagnosis
  ([#11](https://github.com/evekhm/agentic-sdlc/issues/11)).
- **Nestor, the advisor.** The standing judgment seat that helps
  orchestrate. It decides process questions, writes the prompts the
  cheaper personas run with, and helps at the spec gate. It owns no
  rung. It does not implement and does not review
  ([#199](https://github.com/evekhm/agentic-sdlc/issues/199)).
- **The owner.** The human. Files ideas, answers Athena's questions,
  and decides escalations.

Five sub-agents with no GitHub identity do delegated work for the
personas: mechanic, coder, contract-writer, scanner and explorer. They
keep raw material out of a persona's context.

**Tiers.** Work is graded fast, mechanical, implementation, review or
frontier. A persona names the grade its work needs. Each harness binds
the grades to models in
[`config/model_tiers.yaml`](config/model_tiers.yaml). On Claude Code:
Haiku, Sonnet 5, Sonnet 5, Opus, Fable 5.1. On Antigravity: Gemini
3.8 Flash for the first three, Gemini 3.1 Pro for review and frontier.
A new model version is a one-line change in that file.

## The flow, rung by rung

**Plan.** Athena reads the issue. When a section is thin she asks her
questions on the issue thread and waits for the filer, at most two
rounds. The intake is a skill, and every persona that files issues
carries it, so system-filed issues arrive in intent shape
([#10](https://github.com/evekhm/agentic-sdlc/issues/10),
[#117](https://github.com/evekhm/agentic-sdlc/issues/117)). She writes
`intent.md`: the problem, the outcome wanted, the constraints, the
open questions. Merged, the issue moves to design.

**Design.** Athena turns the intent into `spec.md`. She reads her own
draft as an adversary. Every ambiguity becomes a numbered decision.
The spec is approved when no open question remains. Merged, the issue
moves to build.

**Build.** Daedalus writes `plan.md`: the ordered steps and the check
that proves each decision landed. He writes the contract tests, which
fail until the code exists. Each test cites the decision it proves.
Merged, the issue moves to implement.

**Implement.** Odyssey starts at a pinned commit with the spec, the
plan and the failing tests. It writes the code that makes them pass
and opens the pull request. The playbook's Test stage lives here. CI
checks that compiled files match their sources, that nothing leaks a
credential or a path, and that the living spec was updated.

**Review.** Atlas reads every pull request against
[REVIEW.md](REVIEW.md), posts findings with severity and ids, and runs
the verification checklist for the rung: at plan, the intent carries
every item from the issue; at design, no open question and every
acceptance row runnable; at build, the contract tests fail; at
implement, the job log behind every green check says what the check
claims ([#204](https://github.com/evekhm/agentic-sdlc/issues/204)).
Argus joins at the code gate, on trust-bearing paths, and on a
`review:deep` grant, and adds the deep checks there. Any persona may apply that grant when the change meets a named
criterion: privileged operations, a plan deviation, a large diff, an
escalated tier, a second review round. The grant is consumed on use.
A push re-triggers a review only when a reviewer has an open blocking
finding to verify. The author answers each blocking finding. When the
assigned reviewers have none open, the pull request merges. A third round marks the
issue `status:review-stuck` and the owner decides
([#265](https://github.com/evekhm/agentic-sdlc/issues/265)).

**Close.** A deterministic check verifies that the delivery matches
the spec and closes the issue
([#148](https://github.com/evekhm/agentic-sdlc/issues/148)).

**Maintain.** Cassandra's watchers compare live metrics to control
bands. At one sigma they log. At two they diagnose. At three they file
a new issue, and the loop starts again
([#11](https://github.com/evekhm/agentic-sdlc/issues/11)).

The state of every issue is its labels. A merge triggers a workflow
with no model in it. It reads which artifact landed, looks up the next
rung in `personas/lifecycle.json`, and moves the label. The `hold`
label stops all automation. The `blocked` label means a persona
stopped and reported. Two state labels at once is corrupted state and
automation stops. A defect takes a shorter path. A fix that leaves the
living spec unchanged goes issue, fix pull request with a regression
check, review, merge. A fix that changes the spec re-enters at plan
([#32](https://github.com/evekhm/agentic-sdlc/issues/32),
[INTENT.md, "Defect repair"](INTENT.md)).

## The orchestrator

The owner files an issue and marks it ready for the loop. From that
moment the orchestrator owns the issue. It reads the issue's state,
finds the rung it is at, and dispatches the owning persona on its
harness, at its tier, under its own identity. At each gate it waits
for the merge. It dispatches the next rung. It closes the issue once
delivery is verified. It stops on `hold`, on a failed consensus, on a
tripped budget and on an open security finding, and calls the owner.

Who merges depends on the mode, and the mode is set per issue.

- **Manual mode.** The owner is the gate. The owner reads each pull
  request and its findings and merges it by hand. A merge is
  acceptance. A close is rejection.
- **Autonomous mode.** The `mode:autonomous` label switches it on
  ([#147](https://github.com/evekhm/agentic-sdlc/issues/147)). The
  merge identity merges a rung's pull request when CI is green and the
  assigned reviewers have no open blocking finding. At the code gate
  both families must be clear of blocking findings. The owner is
  called only on escalation.

The playbook keeps a human at every merge. Autonomous mode goes one
step further: consensus between two model families reaches the
default branch
([#64](https://github.com/evekhm/agentic-sdlc/issues/64)). Three
seats make that safe. Nestor holds the judgment. Atlas verifies every
gate and Argus adds a second family at the code gate. Cassandra
refills the backlog from measurements.

Dispatch has one door. Inside a harness session the instruction is
`/work <n>`. The command resolves the number to its rung and owning
persona from the labels and starts that persona. Nothing else is
passed. One invocation carries the item through every remaining rung,
each rung as a sub-agent of the owning persona in its own worktree
([#89](https://github.com/evekhm/agentic-sdlc/issues/89)). The
orchestrator fires the same command on a `mode:autonomous` label, with
a budget guard and a sequential queue
([#147](https://github.com/evekhm/agentic-sdlc/issues/147),
[#108](https://github.com/evekhm/agentic-sdlc/issues/108)).

The loop improves itself. When a persona had to be told something it
should have known, the gap becomes an issue and the rule moves into
the repository. Each wave the prompts get shorter
([#181](https://github.com/evekhm/agentic-sdlc/issues/181)). Each
scar becomes a permanent eval in CI
([#254](https://github.com/evekhm/agentic-sdlc/issues/254)), and
deterministic hooks stand behind the advisory rules
([#255](https://github.com/evekhm/agentic-sdlc/issues/255)). A rule
stated in a prompt is a suggestion. A rule holds when it lives in a
file, a gate or an independent reader. The field notes behind every
rule are in [`docs/PLAYBOOK.md`](docs/PLAYBOOK.md).

## Two harnesses, two model families

A harness is the program a persona runs inside. Claude Code is
Anthropic's terminal agent. Antigravity is Google's agentic IDE with
its `agy` command line. A persona is written once, in a vendor-free
source file, naming only the tier its work needs — fast, mechanical,
implementation, review or frontier. The compiler
[`scripts/sync_agents.py`](scripts/sync_agents.py) emits the prompt
files each harness loads, and a CI gate fails when a compiled file
drifts from its source.

Which harness and model answer that tier is a pin in config — one
line per persona in
[`config/deployments.yaml`](config/deployments.yaml), resolved against
the tier table in [`config/model_tiers.yaml`](config/model_tiers.yaml).
The tier a persona names is a recommendation for the grade of
judgment its stage needs. Which harness and model deliver that grade
is free choice: repin any persona by editing its one line, and the
persona source stays untouched.

The two reviewers are the one hard constraint: they must resolve to
different model families, enforced by a CI gate
([#198](https://github.com/evekhm/agentic-sdlc/issues/198)). Every
other pin is free choice. Repin either reviewer on its own — land
both on the same family and their agreement stops meaning anything.

The cost thesis, and where it points: Gemini Flash already carries
the volume — specs, plans, implementation. Gemini Pro and Claude Opus
review it. Claude Fable is spent only where judgment changes the
outcome, at the spec gate and the advisor seat. Claude Code is doing
more of that judgment today because the process is still being
built: specs are still being tightened, gates are still being
written, the compiler is still new. Each round of that work turns a
judgment call into a deterministic check, and every check that lands
moves the target further: a mature, fully specified process is one
where the cheap, low-latency model is the right pin for most stages,
and Claude Code's job shrinks to the plumbing that stood the process
up.

List rates, $ per million tokens, for the exact model id each tier
pins in [`config/model_tiers.yaml`](config/model_tiers.yaml), for
prompts at or under 200k tokens — this system's own context ceiling
(AGENTS.md). Claude rates match
[`scripts/ops/session_spend.sh`](scripts/ops/session_spend.sh); Gemini
rates are the published Gemini API price
([ai.google.dev/gemini-api/docs/pricing](https://ai.google.dev/gemini-api/docs/pricing)) —
`session_spend.sh`'s Gemini table predates this pricing and needs the
same correction, tracked separately. `haiku` and `opus` are aliases
the config leaves unpinned; the price shown is their current
resolution. Re-check all of it before citing a number, since a rate
or a pin can move — Gemini 3.8 Flash's rate below rises to
$1.50 / $7.50 on 2027-01-01, and both Gemini rates roughly double for
prompts over 200k tokens:

| Tier | Claude Code model id | $/1M tok in | $/1M tok out | Antigravity model id | $/1M tok in | $/1M tok out |
|---|---|---|---|---|---|---|
| Fast | `haiku` (Haiku 4.5) | $1.00 | $5.00 | `gemini-3.8-flash-medium` | $0.75 | $3.75 |
| Mechanical / Implementation | `claude-sonnet-5` | $2.00 | $10.00 | `gemini-3.8-flash-high` | $0.75 | $3.75 |
| Review | `opus` (Opus 5) | $5.00 | $25.00 | `gemini-3.1-pro-low-thinking` | $2.00 | $12.00 |
| Frontier | `claude-fable-5-1` | $10.00 | $50.00 | `gemini-3.1-pro-low-thinking` | $2.00 | $12.00 |

Antigravity pins the same model id, `gemini-3.1-pro-low-thinking`, to
both Review and Frontier. A higher-thinking-budget sibling exists and
answers under an interactive login; the runner's credential path
offers only this one today — `config/model_tiers.yaml` has the
evidence and [#167](https://github.com/evekhm/agentic-sdlc/issues/167).
Claude Code pins Frontier to a separate, pricier model.

The spread is widest at the top: Frontier costs 4-5x more on Claude
Code than the tier Antigravity treats as its own ceiling. The more of
the system's judgment a mature process can push down from Frontier to
Review or below, the more of that spread it recovers.

## The playbook, and what this adds

The playbook has six **stages**: Plan, Design, Build, Test, Deploy,
Maintain. Each stage ends in a committed artifact. Plan writes
`intent.md`, Design writes `spec.md`, Build writes `plan.md` and the
code, Test proves it, Deploy ships it past a gate, Maintain watches
control bands and writes the next `intent.md`. A **play** is one named
practice inside a stage, with an enforcer, evidence, a log and an
approver. There are fifteen plays. The stages are non-linear: work
enters wherever its evidence puts it, and plays are adopted one at a
time.

This system maps the six stages onto five rungs and a close. Test
lives inside implement. Deploy is the close, because the only product
is the system itself and CI ships it. Maintain is Cassandra. The
non-linearity lives at the system level: Cassandra enters at Maintain
and produces a Plan, a defect enters at implement, a stuck review
returns to the owner, and many issues sit at different rungs at once.
The scorecard in [`docs/PLAYBOOK.md`](docs/PLAYBOOK.md) has one row
per play: what the playbook asks, how this system does it, and the
issue that tracks any gap.

On top of the playbook this system adds five things. One persona
source, every harness. Two model families in the review seat. A real
GitHub identity per persona, so the platform enforces authorship and
authority. Cost as a subsystem: every tier routed to the cheapest
capable model, every session priced, every dispatch under a spend
ceiling, a ledger per issue, pull request, persona and model
([#104](https://github.com/evekhm/agentic-sdlc/issues/104)). And a
living spec, [`docs/SPEC.md`](docs/SPEC.md), that says what is true
now, beside the per-change intent, spec and plan.

## Running it yourself

You need a clone on a branch you can push, the persona App private
keys, and `gh` and `jq` authenticated against the repository.
Registering the Apps is [`scripts/auth/README.md`](scripts/auth/README.md).
Labels and backlog come from [`scripts/setup/`](scripts/setup/).

Anyone files issues, and the system files its own: Cassandra's
watchers when a control band breaks, and the reviewers and the advisor
when a rung goes wrong. Search the tracker first
([AGENTS.md, "Before filing an issue"](AGENTS.md#before-filing-an-issue)).
A reviewer keeps its findings on the pull request it reviews. State
the problem and what would be true if it were solved. Athena asks the
rest on the thread.

Open a session in your harness and type, for any item at any rung:

```text
/work <n>
```

`<n>` is an issue or pull request number. The command resolves the
rung and the owning persona from the labels, prints what it resolved,
and dispatches that persona under its own identity. It refuses when
the item is on hold, closed, blocked, claimed or in contradictory
state. Full contract: [`docs/SPEC.md`](docs/SPEC.md) `ops.dispatch`.

When the owner steps in at a gate, the action means the same thing
everywhere. A merged pull request is acceptance of the artifact in it.
A closed pull request is a rejection, and it is final. When a decision
in the artifact is wrong, edit it in the pull request. The edited row
is the decision
([REVIEW.md, "Merge is the escape hatch"](REVIEW.md#merge-is-the-escape-hatch)).

## Where the rules live

- [AGENTS.md](AGENTS.md), the standard every session reads.
- [INTENT.md](INTENT.md), why this system exists.
- [`docs/SPEC.md`](docs/SPEC.md), what is built. Trust it over
  this file.
- [REVIEW.md](REVIEW.md), the review protocol.
- [`docs/PLAYBOOK.md`](docs/PLAYBOOK.md), the process, the field notes
  and the scorecard; [`docs/CRITICAL_PATH.md`](docs/CRITICAL_PATH.md),
  what is built and what is next.
- [`docs/BLOG.md`](docs/BLOG.md), the playbook distilled;
  [`docs/CONTEXT.md`](docs/CONTEXT.md), prior art.
- [`config/`](config/), the only place a harness or model is named.
- The pinned tracker issue
  ([#12](https://github.com/evekhm/agentic-sdlc/issues/12)), the live
  dashboard.

This file describes the system as designed. It is normative for
nothing. Where it and any of those documents disagree, the other is
right. Its section list lives in
[`intent/35-readme/spec.md`](intent/35-readme/spec.md).
