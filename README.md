# agentic-sdlc

A software development lifecycle in which agents do the work and
humans keep the judgment. This repository is a working, clonable
instance of that idea: a cast of AI personas that plan, design, build,
implement, review and maintain software, wired to real GitHub
identities, gated by merges, measured in dollars, and built by
following the very loop it demonstrates.

It exists to make a claim concrete. The
[AI-native SDLC
playbook](https://claude.com/blog/the-ai-native-sdlc-playbook)
argues that code is no longer the bottleneck and that the human-speed
stages around it are. This repository takes the playbook at its word,
runs it end to end on more than one harness and more than one model
family, and records what it took. Its destination is an orchestrator
with a YOLO switch: label an issue, and the loop carries it to a
merged, verified, closed result with a person only as the escalation
path.

## What this repository is

Picture a change arriving as a GitHub issue. Nobody writes code yet.
A product-owner persona turns the idea into an `intent.md` and opens
a pull request. Someone merges it, and that merge is the only signal
anything else needs: a deterministic workflow reads which artifact
landed, moves a label, and the label alone tells the next persona
what the item owes. The intent becomes a `spec.md` with numbered
decisions, the spec
becomes a `plan.md` committed before any code, the plan becomes a diff
with tests, and two independent reviewers on two different model
families read the result and post findings. Each rung ends in a pull
request; each merge is an acceptance; the git history is the audit
trail the playbook asks for.

```text
issue filed (intent:new)
   |
   v
plan  ->  design  ->  build  ->  implement  ->  review  ->  (close)
 |          |          |           |              |
intent.md  spec.md   plan.md      code         findings
                                                  |
                          maintain: watchers file the next intent
```

The unusual part is that the system in this repository is itself the
software under development. A person wrote the first persona sources
and the review protocol by hand; from then on the compiler, the label
state machine, the unattended reviewers, the dispatcher and the cost
tooling were specified, planned, implemented and reviewed by the
personas, through the loop, one rung at a time. The folders under
[`intent/`](intent/) are the change records of that bootstrap. When
you watch a rung run here, you are watching the system extend itself.

That is also why it works as a workshop. The format is a
presenter-driven demo plus a take-home: the demo drives one real
change of this repository through every rung in front of the
audience, and the take-home is this same repository, packaged so the
whole cast installs with one command
([INTENT.md, "Workshop storyline"](INTENT.md)).

## The goal: an orchestrator with a YOLO switch

What this repository is building toward is not a set of prompts but
an orchestrator. Today a person opens a session and types `/work <n>`
once per rung, merges what comes back, and notices when the next gate
has opened. The destination is that labeling an issue is the entire
human act. The orchestrator reads the label, dispatches the owning
persona at its tier under its own identity, waits at each gate for a
merge that the two reviewers' consensus triggers rather than for a
person, dispatches the next rung itself, closes the issue once
delivery is verified, and stops only on `hold`, a failed consensus, a
tripped budget or an open security finding. This is deliberately one
step past the playbook, whose agents never have a path to the default
branch: here evidence-based consensus between two model families
does, and the person becomes the escalation path rather than the
gate ([#64](https://github.com/evekhm/agentic-sdlc/issues/64)
reversed the founding intent's rule that humans merge on every
path). The playbook document calls the two ends of that distance YOLO
off and YOLO on ([`docs/PLAYBOOK.md`](docs/PLAYBOOK.md), "Roadmap").

Three seats make the orchestrator trustworthy rather than merely
fast. **Nestor, the advisor,** is the standing frontier-judgment seat
that helps orchestrate: it decides process questions, authors the
prompts the cheaper personas are dispatched with, helps at the spec
gate and keeps the playbook honest, without ever implementing or
reviewing ([#199](https://github.com/evekhm/agentic-sdlc/issues/199)).
**The verifier** is the review stage given depth,
re-running every gate independently and reading the job log behind
every green check before anything merges
([#204](https://github.com/evekhm/agentic-sdlc/issues/204)).
**Cassandra, the
maintainer,** watches the running system and files the next intent
when a control band breaks, so the orchestrator's backlog refills
from evidence rather than from someone's memory
([#11](https://github.com/evekhm/agentic-sdlc/issues/11)).
The loop is self-improving by construction. The frontier family
compiles judgment into rules, prompts and repository plumbing; the
inexpensive family executes; and the gap between what a persona had
to be told and what it should already have known is filed as an
issue that moves the rule into the repository, so each wave the
prompts get shorter and the repository smarter
([#181](https://github.com/evekhm/agentic-sdlc/issues/181)). The
agreed next step turns each of those scars into a permanent eval
([#254](https://github.com/evekhm/agentic-sdlc/issues/254)).

The pieces of the switch are on the tracker: `/work <n>` carrying an
item through every remaining rung with a subagent per rung
([#89](https://github.com/evekhm/agentic-sdlc/issues/89));
`mode:autonomous` and per-issue pins as labels
([#147](https://github.com/evekhm/agentic-sdlc/issues/147)); the
reviewer-consensus merge and a merge identity that belongs to no
persona ([#64](https://github.com/evekhm/agentic-sdlc/issues/64),
[#251](https://github.com/evekhm/agentic-sdlc/issues/251)); an enforced
budget guard and a sequential queue
driver ([#108](https://github.com/evekhm/agentic-sdlc/issues/108));
and the deterministic close
([#148](https://github.com/evekhm/agentic-sdlc/issues/148)). The demo
claim is
that a backlog closes itself on the cheapest capable model, safely,
because every unit of distrust is structural rather than in anyone's
attention.

## The playbook, and what this adds to it

The playbook describes six stages, each ending with a committed
artifact whose commit starts the next stage: plan writes `intent.md`,
design writes `spec.md`, build writes `plan.md` and then the diff,
test proves it, deploy reviews it against a repo-root `REVIEW.md` and
ships it up to a human gate, and maintain watches control bands and
writes a fresh `intent.md` when one breaks. Humans stay above the
loop, at the gates. The distilled reference we design against is
[`docs/BLOG.md`](docs/BLOG.md); how each play scores against what is
merged here is the reference standard in
[`docs/PLAYBOOK.md`](docs/PLAYBOOK.md).

The playbook is written for one vendor's tooling and describes the
loop in prose. This repository adds five things on top of it.

**One persona, every harness.** A persona is defined once, in a
vendor-free source file that names its stage, its protocol, its
authority and the kind of work it does. A compiler emits the prompt
files each harness actually loads, and a CI gate fails the build if a
compiled file drifts from its source. The shared standard every
session reads is likewise one file, [AGENTS.md](AGENTS.md), with thin
per-harness adapters beside it. Which harness and which model family
run a persona is a one-line pin in [`config/`](config/), so the same
lifecycle can be moved between vendors without touching the
lifecycle. Two harnesses are compiled and running today.

**Two model families in the review seat, on purpose.** The two
reviewers are pinned to different families so that a blind spot in
one is not a blind spot in both, and consensus between them means
something. Which family sits where is a fact in `config/` and appears
in no persona, prompt or document.

**Real identities and mechanical authority.** Each persona is its own
GitHub App. Authorship, claims, branch namespaces and what a persona
may write are enforced by the platform, not requested in a prompt.

**Cost as a first-class subsystem.** Every tier of work is routed to
the cheapest capable model; sessions are measured in dollars; every
dispatch carries a spend ceiling. The claim being tested is that an
inexpensive model family can carry the volume while a frontier family
is spent only where its judgment changes the outcome.

**A living spec beside the change records.** The playbook's
`intent.md`, `spec.md` and `plan.md` are per-change. This repository
also keeps [`docs/SPEC.md`](docs/SPEC.md), the current-state truth of
what is built, upserted by every behavior-changing pull request. The
change triple says what was asked and decided; the living spec says
what is true now.

## The loop, stage by stage

Lifecycle state lives in GitHub issue labels, never in a chat
transcript. An issue enters, whether a person, the maintainer's
watchers or the system's own field notes filed it, with `intent:new`
and no stage label, which is exactly what makes it stage *plan* to a
session that has never seen it.

**Plan.** The product owner writes `intent.md` into
`intent/<n>-<slug>/`: problem, outcome, constraints, open questions.
Merging it moves the item to design.

**Design.** The same persona turns that into `spec.md`, then turns
adversary against her own draft: one ambiguity at a time, two
defensible readings, never a recommendation, every resolution a
numbered decision. A spec is approved only when its open questions
are empty, and nothing is dispatched against a draft. Merging it moves
the item to build.

**Build.** The architect writes `plan.md`, the order of work and the
check that proves each decision landed, committed before any code
exists. Contract tests are written to fail, and every assertion cites
the decision it derives from. Merging the plan moves the item to
implement.

**Implement.** The implementer is dispatched at a pinned commit
against the approved spec and the committed plan, works test-first
in its own branch namespace, and opens one pull request carrying the
diff, any plan correction, and the living-spec upsert. The playbook's
test stage lives here rather than as a rung of its own: the session
verifies its own work against the contract tests before anyone reads
it, and CI gates on every pull request check that compiled files
match their sources, that nothing committed leaks a credential or a
path, that bindings and adapters agree, and that the living spec was
upserted or explicitly excused.

**Review.** Two reviewers read the change against
[REVIEW.md](REVIEW.md): severity tiers, per-finding ids, a bounded
round funnel, consensus keyed to decision ids. A third round
(`review:3`) escalates the item to `status:review-stuck` for a human.
Today the review rung is where the
ladder ends and a human closes the item; a deterministic close rung
that verifies delivery before closing is agreed and in flight
([#148](https://github.com/evekhm/agentic-sdlc/issues/148)).

**Deploy.** There is no product behind this repository other than
the system itself, so deploy means CI shipping the system's own
automation: the workflows, the compiled personas, the scripts. The
reviewers already run as event-driven workflows on a hosted runner
under their own identities; where each persona runs, on what trigger
and under what spend ceiling is a per-persona binding in
[`config/execution.yaml`](config/execution.yaml), an axis kept
deliberately separate from which harness interprets it
([#25](https://github.com/evekhm/agentic-sdlc/issues/25)).

**Maintain.** Deterministic watchers compare live metrics to control
bands and respond in proportion: log at one sigma, diagnose read-only
at two, and at three file a new `intent:new` issue. That issue is how
the loop closes on itself. The stage is reserved in the schema and
its persona exists; the watchers are the open rung of the bootstrap
([#11](https://github.com/evekhm/agentic-sdlc/issues/11)).

The transition between stages has no model in it. On a merge to the
default branch a workflow reads which artifact file was added, looks
the next stage up in `personas/lifecycle.json`, moves the label and
posts a stamped comment. The merge is the gate; the label is its
shadow. Defects in merged work take a shorter path: a repair whose
spec entry is unchanged skips the intent, spec and plan and goes
issue, fix pull request with a regression check, review, merge; a
repair that changes a spec entry is a change and re-enters at plan
([#32](https://github.com/evekhm/agentic-sdlc/issues/32), [INTENT.md,
"Defect repair"](INTENT.md)).

## The cast

Each persona is defined in [`personas/`](personas/) by five facts:
the stage it owns, the protocol it runs, the authority it holds, the
tier it thinks at, and the GitHub identity it acts as. Never the
model behind it.

- **Athena, the product owner.** Owns the two gates where words become
  commitments: intake to `intent.md`, and `spec.md` under the
  adversarial protocol. May touch `intent/` and nothing else. Thinks
  at the frontier tier.
- **Daedalus, the architect.** Turns an approved spec into a
  micro-stepped plan and the failing contract tests. Reads code
  freely, writes none. Frontier tier.
- **Odyssey, the implementer.** Dispatched at a pinned commit, works
  test-first, ships one pull request per rung, never writes the
  default branch. Implementation tier, escalating when debugging
  demands it.
- **Argus and Atlas, the two reviewers.** The same protocol, two
  independent voices, two model families. Comment-only: neither
  approves, merges, closes nor edits a label. Review tier.
- **Cassandra, the maintainer.** Watchers, control bands, proportional
  response, and the new intent that closes the loop. Fast tier for
  sweeps, review tier for diagnosis.
- **Nestor, the advisor.** The standing frontier-judgment seat that
  helps orchestrate: process decisions, dispatch-prompt authoring,
  help at the spec gate, stewardship of the playbook. Owns no rung,
  so no dispatcher can ever resolve to it, and never implements or
  reviews. Specified and planned, not yet compiled
  ([#199](https://github.com/evekhm/agentic-sdlc/issues/199)).

Two further seats are on the record. The **verifier** is not a new
persona but the review stage given depth: independently re-running
every gate, mutation-testing the tests, reading the job log behind
every green check, and four mechanizable ladder checks; the
recommendation is that Argus carries it
([#204](https://github.com/evekhm/agentic-sdlc/issues/204)). A
dedicated **merge
identity**, so that no persona ever merges its own pull request,
arrives with the autonomous loop
([#64](https://github.com/evekhm/agentic-sdlc/issues/64),
[#251](https://github.com/evekhm/agentic-sdlc/issues/251)).

Five sub-agents with no GitHub identity do the delegated work a
persona hands off, so raw material never enters the persona's own
context: **mechanic** for fully specified edits and test runs,
**coder** for dispatch-ready implementation, **contract-writer** for
acceptance tests that cite decision ids, **scanner** for wrapping
deterministic check scripts, and **explorer** for read-only fan-out
that returns conclusions rather than file dumps.

**Tiers, not prices.** Work is graded on a five-step ladder: fast,
mechanical, implementation, review, frontier. A persona names the
grade its work needs; each harness binds the grades to its own
models in [`config/model_tiers.yaml`](config/model_tiers.yaml).
Moving a persona to another harness is one line in
[`config/deployments.yaml`](config/deployments.yaml) and a compiler
run. The compiler, [`scripts/sync_agents.py`](scripts/sync_agents.py),
is byte-deterministic so the drift gate is simply rebuild and diff.

## Distrust is structural

The most durable lesson of building this was that a rule stated in a
prompt is a suggestion, and the system holds only where the rule is
in a file, a gate or an independent reader. Several mechanisms follow
from that.

The **labels are the state machine**, and the machine fails closed.
Exactly one `status:*` label is legal at a time; two at once means two
state machines disagree, so automation applies `hold` and stops.
`hold` is an absolute circuit breaker that nothing steps past.
`blocked` means a session stopped and reported rather than guessed.

**All unattended GitHub writes go through one posting path** that
re-reads `hold` immediately before writing, so a post suppressed by
the breaker is a deliberate, clean stop rather than a retry around it.

**Dispatch has one door.** Inside a harness session the whole
instruction is `/work <n>`. The command resolves the number to its
stage and owning persona from the labels and starts that persona
under its own identity. Nothing else is passed, because a flag naming
a stage would let a session work a rung the labels say is not
current. The resolver behind the command is a deterministic script
with no model in it, and both harnesses' commands are meant to compile
from one source so they cannot drift
([#122](https://github.com/evekhm/agentic-sdlc/issues/122)).

**Authority is checked, not trusted.** Branch protection and persona
branch namespaces bound what each identity can write, the review
mutex keeps a persona from reviewing its own rung, and the
distinct-family constraint on the reviewers is declared in config and
becoming a CI gate
([#198](https://github.com/evekhm/agentic-sdlc/issues/198)), so a
re-pin cannot silently collapse both
reviewers onto one family.

The field notes behind these rules are the fabrication catalog in
[`docs/PLAYBOOK.md`](docs/PLAYBOOK.md): the model fabricates, the
prompt author fabricates, the environment fabricates green and red,
and the loop fabricates convergence. Two rules generalize from it:
one scar, one rule, and stable countermeasures never ask the model
for testimony. The next step, agreed and open, turns every entry in
the catalog into a permanent eval in CI
([#254](https://github.com/evekhm/agentic-sdlc/issues/254)) and
puts deterministic
hooks behind the advisory rules
([#255](https://github.com/evekhm/agentic-sdlc/issues/255)).

## How it built itself, and where it stands

The system could not run its own loop before the loop existed, so the
backlog was organised as a bootstrap ladder, indexed by one pinned
tracker issue
([#12](https://github.com/evekhm/agentic-sdlc/issues/12)).

- **Rung 1, wizard of Oz.** A human authored the persona sources, the
  config and the review protocol. Personas ran by hand as sub-agents
  of that person's own session. Done.
- **Rung 2, the machinery.** The compiler, the CI gates, the label
  taxonomy, the six bot identities, the one-door dispatcher, this
  document, and launching any persona on its own harness. Done, with
  harness-agnostic launch and the session close-out still landing
  ([#43](https://github.com/evekhm/agentic-sdlc/issues/43),
  [#85](https://github.com/evekhm/agentic-sdlc/issues/85)).
- **Rung 3, unattended personas.** The reviewers as event-driven
  workflows running on a hosted runner under their own identities,
  which met its gate on 2026-09-08 when both reviewers posted real
  rounds from the runner itself. The product owner picking up
  `intent:new` on her own is open
  ([#10](https://github.com/evekhm/agentic-sdlc/issues/10)), and
  the reviewer-consensus
  merge is implementing
  ([#64](https://github.com/evekhm/agentic-sdlc/issues/64)).
- **Rung 4, maintain.** Deterministic watchers and a seeded incident
  that files a new intent. Open
  ([#11](https://github.com/evekhm/agentic-sdlc/issues/11)).
- **Rung 5, packaging.** The personas compiled into an installable
  plugin, published from an in-repo marketplace, so an attendee can
  install the whole cast with one command. Open
  ([#31](https://github.com/evekhm/agentic-sdlc/issues/31)).

From rung 2 on, features were delivered through the repository's own
ladder: an `intent/<n>-<slug>/` folder, a spec authored under the
persona's App identity, a persona-namespaced branch, commits that cite
reviewer finding ids. Twenty-one change folders exist today. Where
the bootstrap cut a corner, because the machinery a rung needed was
the thing being built, it wrote that down as an explicit,
non-precedent deviation in the spec that cut it, and the field notes
in [`docs/PLAYBOOK.md`](docs/PLAYBOOK.md) record what each shortcut
cost.

The live ordering of what remains is
[`docs/CRITICAL_PATH.md`](docs/CRITICAL_PATH.md), stated as three
gates. Gate one, unattended review on every rung, is met. Gate two
turns the trigger into a label and the merge into a decision: a
`mode:autonomous` switch and per-issue overrides
([#147](https://github.com/evekhm/agentic-sdlc/issues/147)),
an enforced
budget guard and queue driver
([#108](https://github.com/evekhm/agentic-sdlc/issues/108)),
the consensus merge
([#64](https://github.com/evekhm/agentic-sdlc/issues/64)), and
the deterministic close
([#148](https://github.com/evekhm/agentic-sdlc/issues/148)). Gate
three makes issues dispatch-ready
by construction: typed intake
([#117](https://github.com/evekhm/agentic-sdlc/issues/117)), the
repair path through the same
`/work <n>` ([#82](https://github.com/evekhm/agentic-sdlc/issues/82)),
and one `/work <n>` that drives all five rungs from
a single session
([#89](https://github.com/evekhm/agentic-sdlc/issues/89)). Alongside
them: a live board of who owns which
issue at which rung
([#68](https://github.com/evekhm/agentic-sdlc/issues/68)),
the past of one issue as a trace
([#71](https://github.com/evekhm/agentic-sdlc/issues/71)), a
CI gate on the distinct-family constraint
([#198](https://github.com/evekhm/agentic-sdlc/issues/198)), and the
ops scripts
repackaged as skills both harnesses can load
([#122](https://github.com/evekhm/agentic-sdlc/issues/122)).

Today a person fires each session and merges when an independent
verifier session agrees: YOLO off. When gates two and three close,
labeling an issue is the entire human act: YOLO on, the orchestrator
described above.

## What it costs, and how we know

Cost discipline here is curriculum, not just tooling. A working
context has a hard ceiling; read-many work is delegated so the parent
receives a summary and never the raw material; polling cadence is
matched to the model's cache lifetime; spend is ranked in dollars,
never in tokens. Those rules are in
[AGENTS.md](AGENTS.md#context-and-cost-discipline) with the measured
sessions that taught them.

What is built: a script that prices a session transcript from either
harness and reports cache hit rate and tokens per message, and a
per-dispatch spend ceiling that is enforced, not printed. The first
datum for the thesis is in: the first wave dispatched on the
inexpensive family produced five pull requests, all merged the same
morning, each under ten minutes of wall clock
([`docs/CRITICAL_PATH.md`](docs/CRITICAL_PATH.md)). What is agreed
and open: a cost ledger where every run posts a deterministic
spend marker on its issue and one loader builds views per issue, pull
request, persona, model and configuration
([#104](https://github.com/evekhm/agentic-sdlc/issues/104));
provenance written
by the invoking script rather than self-reported by the model
([#190](https://github.com/evekhm/agentic-sdlc/issues/190));
model routing keyed on persona and stage with escalation as a
recorded, once-per-rung hop
([#107](https://github.com/evekhm/agentic-sdlc/issues/107)); and flow
metrics beside the cost
ones, because the first traced issue showed under half an hour of
agent work waiting more than two hours for a human merge
([#71](https://github.com/evekhm/agentic-sdlc/issues/71)).

## Running it yourself

You need a clone on a branch you can push, the persona App private
keys, and `gh` and `jq` authenticated against the repository. Keys
live outside the repository and are never committed; registering the
Apps is [`scripts/auth/README.md`](scripts/auth/README.md), and labels
and backlog are provisioned idempotently by
[`scripts/setup/`](scripts/setup/).

Anyone files issues, and the system files its own. An issue enters
from a person, from the maintainer's watchers when a control band
breaks, or from the loop's own failures: when a rung goes wrong, the
gap between what a persona needed to be told and what it should have
known becomes a tracked issue that moves the rule into the
repository, and the verifier and the advisor file those gaps as they
find them. That is what makes the system self-improving, and it is
why the backlog is the honest picture of the system, not the code
alone. Two rules bind every filer, person or persona: search the
tracker first
([AGENTS.md, "Before filing an
issue"](AGENTS.md#before-filing-an-issue)),
and a reviewer's findings about the pull request under review belong
in that thread, never as new issues. Say what the problem is and what
would be true if it were solved; the first rung writes the rest.

Then open a session in your harness and type, for any item at any
rung:

```text
/work <n>
```

`<n>` is an issue or pull request number. The command prints what it
resolved (stage, artifact owed, owning persona, branch, the one-line
brief the persona is handed) and dispatches that persona; where a
persona's pinned harness is not the one you are sitting in, it prints
the launch line today and will start it there itself once
harness-agnostic launch lands
([#43](https://github.com/evekhm/agentic-sdlc/issues/43)). It refuses,
before anything starts, when the item is on
hold, closed, blocked, claimed by another actor or in contradictory
state. Because the review rung has two owners it launches neither
unless you name one. Today one invocation works one rung; the agreed
end state is that one `/work <n>` carries the item through every
remaining rung, each as a subagent of the owning persona in its own
worktree, waiting at each gate for the merge rather than assuming it
([#89](https://github.com/evekhm/agentic-sdlc/issues/89)), and that
the same command drives a defect through the repair
path ([#82](https://github.com/evekhm/agentic-sdlc/issues/82)). Full
contract: [`docs/SPEC.md`](docs/SPEC.md)
`ops.dispatch`.

What your merge means is the same at every gate. A merged pull
request is the product owner's acceptance of the artifact it carries.
A closed pull request is a rejection, and a rejection is not
relitigated. When a decision in the artifact is wrong, edit it in the
pull request: the edited row *is* the decision, so you never comment
asking for a change and wait for a session to make it
([REVIEW.md, "Merge is the escape
hatch"](REVIEW.md#merge-is-the-escape-hatch)).
Until the consensus merge lands, a human is the merge authority on
every path.

## Where the rules actually live

- [AGENTS.md](AGENTS.md), the cross-harness standard every session
  reads: working the tracker, run folders, cost discipline, the tier
  ladder, the context ceiling.
- [INTENT.md](INTENT.md), the founding intent: why this system exists,
  what the workshop sets out to prove, and the questions still open.
- [`docs/SPEC.md`](docs/SPEC.md), the living spec: what is built
  today, keyed by capability, and what is agreed but not yet built.
  Trust it over any narrative, this one included.
- [REVIEW.md](REVIEW.md), the protocol both reviewers compile against.
- [`docs/PLAYBOOK.md`](docs/PLAYBOOK.md), the process, the field notes
  and the play-by-play scorecard against the playbook;
  [`docs/CRITICAL_PATH.md`](docs/CRITICAL_PATH.md), the live ordering.
- [`docs/BLOG.md`](docs/BLOG.md), the playbook distilled;
  [`docs/CONTEXT.md`](docs/CONTEXT.md), the prior art and what was
  adopted from each.
- [`config/`](config/), the only place a harness, vendor or model
  family is named.
- The pinned tracker issue
([#12](https://github.com/evekhm/agentic-sdlc/issues/12)), the live
dashboard of the ladder.
  There is deliberately no status file.

This file explains and never duplicates: it is normative for nothing,
and wherever it and one of those documents disagree, the other is
right. Its section list is governed by its own spec in
[`intent/35-readme/`](intent/35-readme/spec.md), and grows only by
editing that list.
