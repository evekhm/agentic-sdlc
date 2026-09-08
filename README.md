# agentic-sdlc

A software development lifecycle where agents do the work and humans
keep the judgment. This repository is a working, clonable instance of
that idea. A cast of AI personas plans, designs, builds, implements,
reviews and maintains software. Each persona acts under a real GitHub
identity. Every stage ends in a merge. Every session is measured in
dollars. And the system built itself by following the loop it
demonstrates.

The repository exists to make one claim concrete. The
[AI-native SDLC
playbook](https://claude.com/blog/the-ai-native-sdlc-playbook)
argues that writing code is no longer the bottleneck. The human-speed
stages around the code are. This repository runs the playbook end to
end, on two harnesses and two model families, and records what it
took. The destination is an orchestrator with a YOLO switch: label an
issue, and the loop carries it to a merged, verified, closed result.
A person is only the escalation path.

## What this repository is

A change arrives as a GitHub issue. Nobody writes code yet. A
product-owner persona turns the idea into an `intent.md` and opens a
pull request. Someone merges it. That merge is the only signal
anything else needs. A deterministic workflow reads which artifact
landed and moves a label. The label tells the next persona what the
item owes. The intent becomes a `spec.md` with numbered decisions. The
spec becomes a `plan.md`, committed before any code. The plan becomes
a diff with tests. Two independent reviewers on two different model
families read the result and post findings. Each rung ends in a pull
request. Each merge is an acceptance. The git history is the audit
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

The unusual part: the system in this repository is itself the
software under development. A person wrote the first persona sources
and the review protocol by hand. From then on the personas built the
rest through the loop, one rung at a time: the compiler, the label
state machine, the unattended reviewers, the dispatcher and the cost
tooling. The folders under [`intent/`](intent/) are the change
records of that bootstrap. When you watch a rung run here, you watch
the system extend itself.

That is also why it works as a workshop. The format is a
presenter-driven demo plus a take-home. The demo drives one real
change of this repository through every rung in front of the
audience. The take-home is this same repository, packaged so the
whole cast installs with one command
([INTENT.md, "Workshop storyline"](INTENT.md)).

## The goal: an orchestrator with a YOLO switch

This repository is building an orchestrator. Today a person opens a
session and types `/work <n>` once per rung, merges what comes back,
and notices when the next gate has opened. At the destination,
labeling an issue is the entire human act. The orchestrator reads the
label. It dispatches the owning persona at its tier under its own
identity. At each gate it waits for the merge that the two reviewers'
consensus triggers. It dispatches the next rung itself. It closes the
issue once delivery is verified. It stops on `hold`, on a failed
consensus, on a tripped budget and on an open security finding.

This goes one step past the playbook. In the playbook, agents never
reach the default branch. Here, evidence-based consensus between two
model families does reach it, and the person becomes the escalation
path. [#64](https://github.com/evekhm/agentic-sdlc/issues/64)
reversed the founding rule that humans merge on every path. The
playbook document calls the two ends of that distance YOLO off and
YOLO on ([`docs/PLAYBOOK.md`](docs/PLAYBOOK.md), "Roadmap").

Three seats make the orchestrator trustworthy. **Nestor, the
advisor,** is the standing frontier-judgment seat that helps
orchestrate. It decides process questions, authors the prompts the
cheaper personas are dispatched with, helps at the spec gate and
keeps the playbook current. It never implements and never reviews
([#199](https://github.com/evekhm/agentic-sdlc/issues/199)). **The
verifier** is the review stage given depth. It re-runs every gate
independently and reads the job log behind every green check before
anything merges
([#204](https://github.com/evekhm/agentic-sdlc/issues/204)).
**Cassandra, the maintainer,** watches the running system and files
the next intent when a control band breaks. The orchestrator's
backlog refills from evidence
([#11](https://github.com/evekhm/agentic-sdlc/issues/11)).

The loop improves itself by construction. The frontier family
compiles judgment into rules, prompts and repository plumbing. The
inexpensive family executes. When a persona had to be told something
it should already have known, that gap is filed as an issue and the
rule moves into the repository. Each wave the prompts get shorter and
the repository gets smarter
([#181](https://github.com/evekhm/agentic-sdlc/issues/181)). The
agreed next step turns each of those scars into a permanent eval
([#254](https://github.com/evekhm/agentic-sdlc/issues/254)).

The pieces of the switch are on the tracker. `/work <n>` carries an
item through every remaining rung with a subagent per rung
([#89](https://github.com/evekhm/agentic-sdlc/issues/89)).
`mode:autonomous` and per-issue pins become labels
([#147](https://github.com/evekhm/agentic-sdlc/issues/147)). The
reviewers' consensus merges the pull request through a merge
identity that belongs to no persona
([#64](https://github.com/evekhm/agentic-sdlc/issues/64),
[#251](https://github.com/evekhm/agentic-sdlc/issues/251)). An
enforced budget guard and a sequential queue driver run the backlog
([#108](https://github.com/evekhm/agentic-sdlc/issues/108)). A
deterministic close verifies delivery and closes the issue
([#148](https://github.com/evekhm/agentic-sdlc/issues/148)). The demo
claim: a backlog closes itself on the cheapest capable model, safely,
because every unit of distrust is built into a file, a gate or an
independent reader.

## The playbook, and what this adds to it

The playbook describes six stages. Each ends with a committed
artifact, and that commit starts the next stage. Plan writes
`intent.md`. Design writes `spec.md`. Build writes `plan.md` and then
the diff. Test proves it. Deploy reviews it against a repo-root
`REVIEW.md` and ships it up to a human gate. Maintain watches control
bands and writes a fresh `intent.md` when one breaks. Humans stay
above the loop, at the gates. The distilled reference we design
against is [`docs/BLOG.md`](docs/BLOG.md). The play-by-play score of
what is merged here against each play is in
[`docs/PLAYBOOK.md`](docs/PLAYBOOK.md).

The playbook is written for one vendor's tooling and describes the
loop in prose. This repository adds five things on top of it.

**One persona, every harness.** A persona is defined once, in a
vendor-free source file. The file names its stage, its protocol, its
authority and the kind of work it does. A compiler emits the prompt
files each harness loads. A CI gate fails the build if a compiled
file drifts from its source. The shared standard every session reads
is also one file, [AGENTS.md](AGENTS.md), with thin per-harness
adapters beside it. Which harness and which model family run a
persona is a one-line pin in [`config/`](config/). The same lifecycle
moves between vendors without touching the lifecycle. Two harnesses
are compiled and running today.

**Two model families in the review seat, on purpose.** The two
reviewers are pinned to different families. A blind spot in one
family stays a blind spot in one family, and consensus between them
means something. Which family sits where is a fact in `config/` and
appears in no persona, prompt or document.

**Real identities and mechanical authority.** Each persona is its own
GitHub App. The platform enforces authorship, claims, branch
namespaces and what a persona may write.

**Cost as a first-class subsystem.** Every tier of work is routed to
the cheapest capable model. Sessions are measured in dollars. Every
dispatch carries a spend ceiling. The claim under test: an
inexpensive model family carries the volume, and a frontier family is
spent only where its judgment changes the outcome.

**A living spec beside the change records.** The playbook's
`intent.md`, `spec.md` and `plan.md` are per-change. This repository
also keeps [`docs/SPEC.md`](docs/SPEC.md), the current-state truth of
what is built. Every behavior-changing pull request upserts it. The
change triple says what was asked and decided. The living spec says
what is true now.

## The loop, stage by stage

Lifecycle state lives in GitHub issue labels. An issue enters with
`intent:new` and no stage label. That is what makes it stage *plan*
to a session that has never seen it. A person, the maintainer's
watchers, or the system's own field notes can file it.

**Plan.** The product owner writes `intent.md` into
`intent/<n>-<slug>/`: problem, outcome, constraints, open questions.
Merging it moves the item to design.

**Design.** The same persona turns the intent into `spec.md`. Then
she plays adversary against her own draft: one ambiguity at a time,
two defensible readings, no recommendation, every resolution a
numbered decision. A spec is approved only when its open questions
are empty. Nothing is dispatched against a draft. Merging the spec
moves the item to build.

**Build.** The architect writes `plan.md`: the order of work and the
check that proves each decision landed. It is committed before any
code exists. Contract tests are written to fail, and every assertion
cites the decision it derives from. Merging the plan moves the item
to implement.

**Implement.** The implementer is dispatched at a pinned commit
against the approved spec and the committed plan. It works test-first
in its own branch namespace and opens one pull request. The pull
request carries the diff, any plan correction, and the living-spec
upsert. The playbook's test stage lives inside this rung. The session
verifies its own work against the contract tests before anyone reads
it. CI gates on every pull request then check four things: compiled
files match their sources, nothing committed leaks a credential or a
path, bindings and adapters agree, and the living spec was upserted
or explicitly excused.

**Review.** Two reviewers read the change against
[REVIEW.md](REVIEW.md): severity tiers, per-finding ids, a bounded
round funnel, consensus keyed to decision ids. A third round
(`review:3`) escalates the item to `status:review-stuck` for a human.
Today the ladder ends at this rung and a human closes the item. A
deterministic close rung that verifies delivery before closing is
agreed and in flight
([#148](https://github.com/evekhm/agentic-sdlc/issues/148)).

**Deploy.** The only product behind this repository is the system
itself. Deploy therefore means CI shipping the system's own
automation: the workflows, the compiled personas, the scripts. The
reviewers already run as event-driven workflows on a hosted runner
under their own identities. Where each persona runs, on what trigger
and under what spend ceiling is a per-persona binding in
[`config/execution.yaml`](config/execution.yaml). That axis is kept
separate from which harness interprets the persona
([#25](https://github.com/evekhm/agentic-sdlc/issues/25)).

**Maintain.** Deterministic watchers compare live metrics to control
bands and respond in proportion. At one sigma they log. At two they
diagnose read-only. At three they file a new `intent:new` issue. That
issue closes the loop on itself. The stage is reserved in the schema
and its persona exists. The watchers are the open rung of the
bootstrap ([#11](https://github.com/evekhm/agentic-sdlc/issues/11)).

The transition between stages has no model in it. On a merge to the
default branch a workflow reads which artifact file was added, looks
the next stage up in `personas/lifecycle.json`, moves the label and
posts a stamped comment. The merge is the gate. The label is its
shadow. Defects in merged work take a shorter path. A repair that
leaves the spec entry unchanged skips intent, spec and plan: issue,
fix pull request with a regression check, review, merge. A repair
that changes a spec entry is a change and re-enters at plan
([#32](https://github.com/evekhm/agentic-sdlc/issues/32), [INTENT.md,
"Defect repair"](INTENT.md)).

## The cast

Each persona is defined in [`personas/`](personas/) by five facts:
the stage it owns, the protocol it runs, the authority it holds, the
tier it thinks at, and the GitHub identity it acts as. The model
behind it is never one of those facts.

- **Athena, the product owner.** Owns the two gates where words become
  commitments: intake to `intent.md`, and `spec.md` under the
  adversarial protocol. May touch `intent/` only. Frontier tier.
- **Daedalus, the architect.** Turns an approved spec into a
  micro-stepped plan and the failing contract tests. Reads code
  freely and writes none. Frontier tier.
- **Odyssey, the implementer.** Dispatched at a pinned commit, works
  test-first, ships one pull request per rung. Never writes the
  default branch. Implementation tier, escalating when debugging
  demands it.
- **Argus and Atlas, the two reviewers.** The same protocol, two
  independent voices, two model families. Comment-only: neither
  approves, merges, closes or edits a label. Review tier.
- **Cassandra, the maintainer.** Watchers, control bands, proportional
  response, and the new intent that closes the loop. Fast tier for
  sweeps, review tier for diagnosis.
- **Nestor, the advisor.** The standing frontier-judgment seat that
  helps orchestrate: process decisions, dispatch-prompt authoring,
  help at the spec gate, stewardship of the playbook. Owns no rung, so
  no dispatcher can resolve to it. Never implements and never
  reviews. Specified and planned, compilation open
  ([#199](https://github.com/evekhm/agentic-sdlc/issues/199)).

Two further seats are on the record. The **verifier** is the review
stage given depth. It re-runs every gate independently, mutation-tests
the tests, reads the job log behind every green check, and runs four
mechanizable ladder checks. The recommendation is that Argus carries
it ([#204](https://github.com/evekhm/agentic-sdlc/issues/204)). A
dedicated **merge identity** arrives with the autonomous loop, so no
persona ever merges its own pull request
([#64](https://github.com/evekhm/agentic-sdlc/issues/64),
[#251](https://github.com/evekhm/agentic-sdlc/issues/251)).

Five sub-agents with no GitHub identity do the delegated work a
persona hands off. Raw material stays out of the persona's own
context. **mechanic** does fully specified edits and test runs.
**coder** does dispatch-ready implementation. **contract-writer**
writes acceptance tests that cite decision ids. **scanner** wraps
deterministic check scripts. **explorer** does read-only fan-out and
returns conclusions.

**Tiers.** Work is graded on a five-step ladder: fast, mechanical,
implementation, review, frontier. A persona names the grade its work
needs. Each harness binds the grades to its own models in
[`config/model_tiers.yaml`](config/model_tiers.yaml). Moving a persona
to another harness is one line in
[`config/deployments.yaml`](config/deployments.yaml) and a compiler
run. The compiler, [`scripts/sync_agents.py`](scripts/sync_agents.py),
is byte-deterministic, so the drift gate is rebuild and diff.

## Distrust is structural

The most durable lesson of building this: a rule stated in a prompt
is a suggestion. The system holds where the rule is in a file, a gate
or an independent reader. Several mechanisms follow from that.

The **labels are the state machine**, and the machine fails closed.
Exactly one `status:*` label is legal at a time. Two at once means two
state machines disagree, so automation applies `hold` and stops.
`hold` is an absolute circuit breaker. Nothing steps past it.
`blocked` means a session stopped and reported.

**All unattended GitHub writes go through one posting path.** It
re-reads `hold` immediately before writing. A post the breaker
suppresses is a clean stop.

**Dispatch has one door.** Inside a harness session the whole
instruction is `/work <n>`. The command resolves the number to its
stage and owning persona from the labels and starts that persona
under its own identity. Nothing else is passed. A flag naming a stage
would let a session work a rung the labels say is stale. The resolver
behind the command is a deterministic script with no model in it.
Both harnesses' commands compile from one source, so they cannot
drift ([#122](https://github.com/evekhm/agentic-sdlc/issues/122)).

**Authority is checked.** Branch protection and persona branch
namespaces bound what each identity can write. The review mutex keeps
a persona from reviewing its own rung. The distinct-family constraint
on the reviewers is declared in config and is becoming a CI gate
([#198](https://github.com/evekhm/agentic-sdlc/issues/198)). A re-pin
then cannot collapse both reviewers onto one family.

The field notes behind these rules are the fabrication catalog in
[`docs/PLAYBOOK.md`](docs/PLAYBOOK.md). The model fabricates. The
prompt author fabricates. The environment fabricates green and red.
The loop fabricates convergence. Two rules generalize from it: one
scar, one rule; and a stable countermeasure checks evidence that
lives outside the model. The agreed next step turns every entry in
the catalog into
a permanent eval in CI
([#254](https://github.com/evekhm/agentic-sdlc/issues/254)) and puts
deterministic hooks behind the advisory rules
([#255](https://github.com/evekhm/agentic-sdlc/issues/255)).

## How it built itself, and where it stands

The system could not run its own loop before the loop existed. So the
backlog was organised as a bootstrap ladder, indexed by one pinned
tracker issue
([#12](https://github.com/evekhm/agentic-sdlc/issues/12)).

- **Rung 1, wizard of Oz.** A human authored the persona sources, the
  config and the review protocol. Personas ran by hand as sub-agents
  of that person's own session. Done.
- **Rung 2, the machinery.** The compiler, the CI gates, the label
  taxonomy, the six bot identities, the one-door dispatcher, this
  document, and launching any persona on its own harness. Done.
  Harness-agnostic launch and the session close-out are still landing
  ([#43](https://github.com/evekhm/agentic-sdlc/issues/43),
  [#85](https://github.com/evekhm/agentic-sdlc/issues/85)).
- **Rung 3, unattended personas.** The reviewers run as event-driven
  workflows on a hosted runner under their own identities. This met
  its gate on 2026-09-08, when both reviewers posted real rounds from
  the runner itself. The product owner picking up `intent:new` on her
  own is open
  ([#10](https://github.com/evekhm/agentic-sdlc/issues/10)).
  The reviewer-consensus merge is implementing
  ([#64](https://github.com/evekhm/agentic-sdlc/issues/64)).
- **Rung 4, maintain.** Deterministic watchers and a seeded incident
  that files a new intent. Open
  ([#11](https://github.com/evekhm/agentic-sdlc/issues/11)).
- **Rung 5, packaging.** The personas compiled into an installable
  plugin, published from an in-repo marketplace. An attendee installs
  the whole cast with one command. Open
  ([#31](https://github.com/evekhm/agentic-sdlc/issues/31)).

From rung 2 on, features were delivered through the repository's own
ladder: an `intent/<n>-<slug>/` folder, a spec authored under the
persona's App identity, a persona-namespaced branch, commits that cite
reviewer finding ids. Twenty-one change folders exist today. Sometimes
the bootstrap cut a corner, because the machinery a rung needed was
the thing being built. Each such shortcut is written down as an
explicit, non-precedent deviation in the spec that cut it. The field
notes in [`docs/PLAYBOOK.md`](docs/PLAYBOOK.md) record what each
shortcut cost.

The live ordering of what remains is
[`docs/CRITICAL_PATH.md`](docs/CRITICAL_PATH.md), stated as three
gates. Gate one, unattended review on every rung, is met. Gate two
turns the trigger into a label and the merge into a decision: a
`mode:autonomous` switch and per-issue overrides
([#147](https://github.com/evekhm/agentic-sdlc/issues/147)), an
enforced budget guard and queue driver
([#108](https://github.com/evekhm/agentic-sdlc/issues/108)), the
consensus merge
([#64](https://github.com/evekhm/agentic-sdlc/issues/64)), and the
deterministic close
([#148](https://github.com/evekhm/agentic-sdlc/issues/148)). Gate
three makes issues dispatch-ready by construction: typed intake
([#117](https://github.com/evekhm/agentic-sdlc/issues/117)), the
repair path through the same `/work <n>`
([#82](https://github.com/evekhm/agentic-sdlc/issues/82)), and one
`/work <n>` that drives all five rungs from a single session
([#89](https://github.com/evekhm/agentic-sdlc/issues/89)). Alongside
them: a live board of who owns which issue at which rung
([#68](https://github.com/evekhm/agentic-sdlc/issues/68)), the past of
one issue as a trace
([#71](https://github.com/evekhm/agentic-sdlc/issues/71)), a CI gate
on the distinct-family constraint
([#198](https://github.com/evekhm/agentic-sdlc/issues/198)), and the
ops scripts repackaged as skills both harnesses can load
([#122](https://github.com/evekhm/agentic-sdlc/issues/122)).

Today a person fires each session and merges when an independent
verifier session agrees. That is YOLO off. When gates two and three
close, labeling an issue is the entire human act. That is YOLO on,
the orchestrator described above.

## What it costs, and how we know

Cost discipline here is curriculum as much as tooling. A working
context has a hard ceiling. Read-many work is delegated, so the parent
receives a summary and the raw material stays out. Polling cadence is
matched to the model's cache lifetime. Spend is ranked in dollars.
Those rules are in
[AGENTS.md](AGENTS.md#context-and-cost-discipline), with the measured
sessions that taught them.

What is built: a script that prices a session transcript from either
harness and reports cache hit rate and tokens per message, and a
per-dispatch spend ceiling that the invoking script enforces. The
first datum for the thesis is in. The first wave dispatched on the
inexpensive family produced five pull requests, all merged the same
morning, each under ten minutes of wall clock
([`docs/CRITICAL_PATH.md`](docs/CRITICAL_PATH.md)).

What is agreed and open: a cost ledger where every run posts a
deterministic spend marker on its issue and one loader builds views
per issue, pull request, persona, model and configuration
([#104](https://github.com/evekhm/agentic-sdlc/issues/104));
provenance written by the invoking script
([#190](https://github.com/evekhm/agentic-sdlc/issues/190)); model
routing keyed on persona and stage, with escalation as a recorded,
once-per-rung hop
([#107](https://github.com/evekhm/agentic-sdlc/issues/107)); and flow
metrics beside the cost ones. The first traced issue showed under half
an hour of agent work waiting more than two hours for a human merge
([#71](https://github.com/evekhm/agentic-sdlc/issues/71)).

## Running it yourself

You need a clone on a branch you can push, the persona App private
keys, and `gh` and `jq` authenticated against the repository. Keys
live outside the repository and are never committed. Registering the
Apps is [`scripts/auth/README.md`](scripts/auth/README.md). Labels and
backlog are provisioned idempotently by
[`scripts/setup/`](scripts/setup/).

Anyone files issues, and the system files its own. An issue comes
from a person, from the maintainer's watchers when a control band
breaks, or from the loop's own failures. When a rung goes wrong, the
verifier and the advisor file the gap as an issue, and the fix moves
the rule into the repository. That is what makes the system
self-improving. It is also why the backlog, together with the code,
is the full picture of the system. Two rules bind every filer,
person or persona. Search the tracker first
([AGENTS.md, "Before filing an
issue"](AGENTS.md#before-filing-an-issue)). Keep a reviewer's findings
on the pull request they review in that pull request's thread. Say
what the problem is and what would be true if it were solved. The
first rung writes the rest.

Then open a session in your harness and type, for any item at any
rung:

```text
/work <n>
```

`<n>` is an issue or pull request number. The command prints what it
resolved: stage, artifact owed, owning persona, branch, and the
one-line brief the persona is handed. Then it dispatches that
persona. When the persona is pinned to the other harness, the command
prints the launch line today. Once harness-agnostic launch lands, it
starts the persona there itself
([#43](https://github.com/evekhm/agentic-sdlc/issues/43)). The command
refuses before anything starts when the item is on hold, closed,
blocked, claimed by another actor or in contradictory state. The
review rung has two owners, so the command launches neither until you
name one. Today one invocation works one rung. The agreed end state:
one `/work <n>` carries the item through every remaining rung, each
rung as a subagent of the owning persona in its own worktree, and
waits at each gate for the merge
([#89](https://github.com/evekhm/agentic-sdlc/issues/89)). The same
command will drive a defect through the repair path
([#82](https://github.com/evekhm/agentic-sdlc/issues/82)). Full
contract: [`docs/SPEC.md`](docs/SPEC.md) `ops.dispatch`.

Your merge means the same thing at every gate. A merged pull request
is the product owner's acceptance of the artifact it carries. A closed
pull request is a rejection, and a rejection is final. When a decision
in the artifact is wrong, edit it in the pull request. The edited row
*is* the decision. You never comment asking for a change and wait for
a session to make it ([REVIEW.md, "Merge is the escape
hatch"](REVIEW.md#merge-is-the-escape-hatch)). Until the consensus
merge lands, a human is the merge authority on every path.

## Where the rules actually live

- [AGENTS.md](AGENTS.md), the cross-harness standard every session
  reads: working the tracker, run folders, cost discipline, the tier
  ladder, the context ceiling.
- [INTENT.md](INTENT.md), the founding intent: why this system exists,
  what the workshop sets out to prove, and the questions still open.
- [`docs/SPEC.md`](docs/SPEC.md), the living spec: what is built
  today, keyed by capability, and what is agreed and unbuilt. Trust
  it over any narrative, this one included.
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
  dashboard of the ladder. There is deliberately no status file.

This file explains. It is normative for nothing. Wherever it and one
of those documents disagree, the other is right. Its section list is
governed by its own spec in
[`intent/35-readme/`](intent/35-readme/spec.md) and grows only by
editing that list.
