# agentic-sdlc

**TL;DR:** A harness-agnostic software development lifecycle run by
a cast of AI agents. The process is defined once, independent of any
vendor, and each role is placed on the coding harness and model that
fit it best. An idea enters as intent and leaves as reviewed, merged
software, and every pass through the loop improves the system that
built it.

An intent goes in. One agent sharpens it into a specification, one
plans the work, one builds it, two independent reviewers from
different model families judge the result, and a maintainer watches
it run and proposes what comes next. A human sets direction and
decides escalations.

This is a **harness-agnostic SDLC**. The process comes first: the
roles, the protocols, the gates and the artifacts are defined once,
in vendor-free sources that carry over to any harness. Each persona
is then assigned its own coding harness and model,
whichever fits the team's needs and requirements: frontier reasoning
where judgment shapes the outcome, fast capacity where the process has
matured, or the platform a team already runs on. Currently supported
harnesses are Antigravity and Claude Code.
Reassigning a persona is a one-line change, and the process stays the
same (the [placement thesis](#two-harnesses-two-model-families)). The
system follows the
[AI-native SDLC playbook](https://claude.com/blog/the-ai-native-sdlc-playbook)
and builds itself with its own loop.

## What this is

Two kinds of actors appear in this document.

- **A persona** is an AI agent. It has one job, a protocol, its own
  GitHub account and a model tier. It runs inside a coding harness of
  the owner's choosing (currently supported: Antigravity, Claude Code).
- **The owner** is the human who runs the repository. The owner files
  intent as a plain-language issue, answers the questions the personas
  ask back, and decides escalations.

Six personas cover six jobs: product owner, architect, implementer,
two reviewers and maintainer. Two seats stand beside them: an advisor
and a merge actor. Each persona carries a name from Greek myth. 

**The loop.** Every issue climbs five rungs in order. Each rung ends
in a pull request that carries one artifact. A merge means the
artifact is accepted, and it moves the issue to the next rung. The
chain of merges is the audit trail: who asked for what, what the
persona produced, who accepted it.

```text
 issue filed (intent:new, no status label)
   |
   v
 plan ----> design ----> build ------> implement ----> review ----> close
 product    product     architect     implementer    two
 owner      owner                                    reviewers
 intent.md  spec.md     plan.md +     code           findings
                        failing tests
   ^                                                              |
   |         maintain: the maintainer measures, files the next issue
   +--------------------------------------------------------------+
```

**What a merge needs.** CI is green, and the assigned reviewers have
no open blocking finding: a security or high defect, per
[REVIEW.md](REVIEW.md)'s severity tiers. A suggestion or a normal-tier
defect is recorded and never gates a merge. Who applies the merge
depends on the mode: the owner by hand, or the merge actor in
autonomous mode.

**Self-building.** A person wrote the first persona sources and the
review protocol by hand. From then on the personas build the rest
through their own loop: the compiler, the label state machine, the
unattended reviewers, the merge gate, the poller and the cost tooling.
The folders under [`intent/`](intent/) are the record. The repository
is also a workshop: a presenter drives one real change through every
rung in front of an audience, and the audience takes the repository
home ([INTENT.md](INTENT.md)).

## The cast

Each persona is defined once in [`personas/`](personas/): the stage it
owns, the protocol it runs, the authority it holds, the tier it thinks
at, and the GitHub identity it acts as.

- **Product owner, *Athena*.** Talks with the filer, writes
  `intent.md`, then writes `spec.md` under an adversarial protocol.
  Writes only under `intent/`. Frontier tier.
- **Architect, *Daedalus*.** Turns an approved spec into `plan.md` and
  the failing contract tests. Reads code and writes none. Frontier
  tier.
- **Implementer, *Odyssey*.** Writes the code that makes the tests
  pass. Starts at a pinned commit in its own branch namespace. One pull
  request per rung. Implementation tier.
- **Reviewer of every gate, *Atlas*.** Reads every pull request at
  every rung on Gemini, the high-volume seat. Posts findings with severity
  and ids. Runs the verification checklist for the rung. Never
  approves, merges, closes or edits a label. Review tier
  ([#204](https://github.com/evekhm/agentic-sdlc/issues/204)).
- **Deep reviewer, *Argus*.** Joins at the code gate, on any change to
  a trust-bearing path, and on a `review:deep` grant. Runs the same
  protocol on Claude, the other model family, plus the deep checks:
  mutation-tests the tests, re-runs the gates, reads the diff in full.
  Comment-only like *Atlas*. Review tier
  ([#265](https://github.com/evekhm/agentic-sdlc/issues/265)).
- **Maintainer, *Cassandra*.** Runs watchers over the live system.
  When a control band breaks she files the next issue. Fast tier for
  sweeps, review tier for diagnosis
  ([#11](https://github.com/evekhm/agentic-sdlc/issues/11)).
- **Advisor, *Nestor*.** The standing judgment seat. Decides process
  questions, writes the prompts the other personas run with, and
  helps at the spec gate. Owns no rung, implements nothing, reviews
  nothing ([#199](https://github.com/evekhm/agentic-sdlc/issues/199)).
- **Merge actor, *Themis*.** A system actor with no prompt, no harness
  and no goals. The one trusted writer of the loop's state, and the
  identity that merges a pull request once consensus is reached. It
  belongs to no persona, so no persona merges its own work
  ([#64](https://github.com/evekhm/agentic-sdlc/issues/64)).
- **The owner.** The human. Files ideas, answers the product owner's
  questions, and decides escalations.

Five sub-agents with no GitHub identity do delegated work for the
personas: mechanic, coder, contract-writer, scanner and explorer. They
keep raw material out of a persona's context.

**Tiers.** Work is graded fast, mechanical, implementation, review or
frontier. A persona names the grade its work needs. Each harness binds
the grades to models in
[`config/model_tiers.yaml`](config/model_tiers.yaml).

## The flow, rung by rung

- **Plan.** *Athena* reads the issue. When a section is thin she asks
  on the issue thread and waits for the filer, at most two rounds.
  Intake is a skill every issue-filing persona carries, so system-filed
  issues arrive in intent shape
  ([#10](https://github.com/evekhm/agentic-sdlc/issues/10),
  [#117](https://github.com/evekhm/agentic-sdlc/issues/117)). She
  writes `intent.md`: the problem, the outcome wanted, the constraints,
  the open questions. Merged, the issue moves to design.
- **Design.** *Athena* turns the intent into `spec.md`. She reads her
  own draft as an adversary. Every ambiguity becomes a numbered
  decision. The spec is approved when no open question remains.
  Merged, the issue moves to build.
- **Build.** *Daedalus* writes `plan.md`: the ordered steps and the
  check that proves each decision landed. He writes the contract
  tests, which fail until the code exists. Each test cites the decision
  it proves. Merged, the issue moves to implement.
- **Implement.** *Odyssey* starts at a pinned commit with the spec,
  the plan and the failing tests. It writes the code that makes them
  pass and opens the pull request. Five CI gates run on every pull request:
  compiled files match their sources, nothing leaks a credential or a path,
  the living spec was updated, the execution bindings validate, and the
  changelog was updated ([`docs/SPEC.md`](docs/SPEC.md)).
- **Review.** *Atlas* reads every pull request against
  [REVIEW.md](REVIEW.md), posts findings with severity and ids, and
  runs the verification checklist for the rung: at plan, the intent
  carries every item from the issue; at design, no open question and
  every acceptance row runnable; at build, the contract tests fail; at
  implement, the job log behind every green check says what the check
  claims ([#204](https://github.com/evekhm/agentic-sdlc/issues/204)).
  *Argus* joins at the code gate, on trust-bearing paths and on a
  `review:deep` grant, which any persona may apply for a privileged
  operation, a plan deviation, a large diff, an escalated tier or a
  second round. The author answers each blocking finding. A push
  re-triggers review only while a blocking finding stays unresolved. A third
  round marks the issue `status:review-stuck` and the owner decides
  ([#265](https://github.com/evekhm/agentic-sdlc/issues/265)).
- **Close.** A deterministic check verifies that the delivery matches
  the spec and closes the issue
  ([#148](https://github.com/evekhm/agentic-sdlc/issues/148)).
- **Maintain.** *Cassandra*'s watchers compare live metrics to control
  bands. One sigma logs. Two diagnose. Three file a new issue, and the
  loop starts again
  ([#11](https://github.com/evekhm/agentic-sdlc/issues/11)).

**State and halts.** The state of every issue is its labels. A merge
triggers a workflow with no model in it. It reads which artifact
landed, looks up the next rung in `personas/lifecycle.json`, and moves
the label. `hold` stops all automation. `blocked` means a persona
stopped and reported. Two state labels at once is corrupted state and
automation stops.

**Defects** take a shorter path. A fix that leaves the living spec
unchanged goes issue, fix pull request with a regression check,
review, merge. A fix that changes the spec re-enters at plan
([#32](https://github.com/evekhm/agentic-sdlc/issues/32),
[INTENT.md, "Defect repair"](INTENT.md)).

## The orchestrator

The owner files an issue. From that moment the loop owns it. Between
the human gates, four pieces with no model in them carry an issue from
one rung to the next.

```text
 pull request opened or pushed
   |
   +--> CI: drift, sanitize, spec-check, execution
   +--> reviewers: Atlas on every PR, Argus at the code gate
   |
   v
 recorder ...... one consensus ledger per PR: findings, severities,
   |             the head each reviewer read, agreed / pending / disputed
   v
 merge gate .... Themis merges when every condition holds at that head
   |
   v
 lifecycle ..... moves the status label, appends a dispatch row
   |             to the issue's loop ledger
   v
 poller ........ on the VM: runs the row as the next persona, in its
                 own worktree, under its spend ceiling
```

- **The recorder** turns review comments into one consensus ledger
  per pull request and verifies that each review came from a real
  reviewer run
  ([#267](https://github.com/evekhm/agentic-sdlc/issues/267)).
- **The merge gate** is one script, run from Actions as *Themis*. It
  merges when every condition holds at the current head: both
  assigned reviewers read that head, no blocking finding remains, the
  consensus is agreed, neither `hold` nor `blocked` is present, the
  merger differs from the author, and CI is clean. A false condition
  writes a refusal row
  ([#64](https://github.com/evekhm/agentic-sdlc/issues/64)).
- **The loop ledger** is one comment per issue with dispatch, terminal
  and refusal rows. Only rows *Themis* wrote count as state
  ([#64](https://github.com/evekhm/agentic-sdlc/issues/64)).
- **The lifecycle workflow** moves the label and writes the next
  dispatch row. It refuses once an issue has spent its dispatch count
  or its budget ([#64](https://github.com/evekhm/agentic-sdlc/issues/64)).
- **The poller** runs each dispatch row from the VM: it claims the
  issue as the next persona and runs it through the placement in
  [`config/execution.yaml`](config/execution.yaml) under that persona's
  spend ceiling. It also hands new `intent:new` issues to the product
  owner ([#251](https://github.com/evekhm/agentic-sdlc/issues/251),
  [#108](https://github.com/evekhm/agentic-sdlc/issues/108)).

**Two modes.** One key, `loop.autonomous_merge` in
[`config/execution.yaml`](config/execution.yaml), arms the merge and
the next-rung dispatch. A per-issue override is tracked
([#147](https://github.com/evekhm/agentic-sdlc/issues/147)).

- **Manual.** The owner is the gate. Every guard still runs and every
  ledger row is still written. The owner reads each pull request and
  its findings and merges by hand.
- **Autonomous.** *Themis* merges when the gate's conditions hold. At
  the code gate both model families must be clear of blocking
  findings. The owner is called only on escalation.

The playbook keeps a human at every merge. Autonomous mode goes one
step further: consensus between two model families reaches the default
branch ([#64](https://github.com/evekhm/agentic-sdlc/issues/64)).
Three seats make that safe. *Nestor* holds the judgment. *Atlas*
verifies every gate and *Argus* adds a second family at the code gate.
*Cassandra* refills the backlog from measurements.

**Stops.** The loop stops on `hold`, on a failed consensus, on a
tripped budget and on an open security finding, and calls the owner.
A person joins the loop through one door, `/work <n>`, described under
"Running it yourself"
([#89](https://github.com/evekhm/agentic-sdlc/issues/89)).

**Self-improvement.** When a persona had to be told something it
should have known, the gap becomes an issue and the rule moves into the
repository. Each wave the prompts get shorter
([#181](https://github.com/evekhm/agentic-sdlc/issues/181)), each scar
becomes a permanent eval in CI
([#254](https://github.com/evekhm/agentic-sdlc/issues/254)), and
deterministic hooks stand behind the advisory rules
([#255](https://github.com/evekhm/agentic-sdlc/issues/255)). A rule in
a prompt is a suggestion. A rule holds when it lives in a file, a gate
or an independent reader
([`docs/PLAYBOOK.md`](docs/PLAYBOOK.md)).

## Two harnesses, two model families

A **harness** is the program a persona runs inside: Claude Code
(Anthropic) or Antigravity (Google, via `agy`). The process owns the
personas, the protocols and the gates; a harness only executes them.
A persona names only a tier in a vendor-free source file, and the
compiler [`scripts/sync_agents.py`](scripts/sync_agents.py) emits each
harness's prompt file from it; CI fails if a compiled file drifts from
its source. A third harness is one more compiler target, and the
personas, the ladder and the review protocol carry over unchanged.

**Pins.** Harness and model are one line per persona in
[`config/deployments.yaml`](config/deployments.yaml), resolved against
[`config/model_tiers.yaml`](config/model_tiers.yaml). Repin any persona
by editing its line; the source never changes. One hard constraint:
the two reviewers must resolve to different model families
([#198](https://github.com/evekhm/agentic-sdlc/issues/198)). For local
single-harness authoring operations without dirtying tracked files or worktrees,
the dispatcher supports the `DEPLOYMENTS` environment variable override
pointing to an unversioned `ops/deployments.yaml` ([#251](https://github.com/evekhm/agentic-sdlc/issues/251), [#433](https://github.com/evekhm/agentic-sdlc/issues/433)).
(Reviewer dispatches require distinct model families for protocol-valid consensus).

```text
 Antigravity  /  Gemini 3.8 Flash            Claude Code  /  Claude
 ------------------------------------        -----------------------------
 Athena     product owner   frontier         Argus      deep reviewer  review
 Daedalus   architect       frontier         Cassandra  maintainer     fast
 Odyssey    implementer     implementation
 Atlas      reviewer        review
```

**The goal** is a process mature enough to run every seat on Gemini
3.8 Flash through Antigravity
([#271](https://github.com/evekhm/agentic-sdlc/issues/271)). Every
rung persona is pinned there, and each of the five tiers maps to a
Flash thinking level in
[`config/model_tiers.yaml`](config/model_tiers.yaml). The design runs
whole on either harness. Where Claude pays for itself is judgment:
the second review family at the code gate, and the frontier seats a
team already invested in Claude keeps there, such as the advisor
([#199](https://github.com/evekhm/agentic-sdlc/issues/199)).

**The placement thesis.** A stage that is well specified and well gated
runs well on a fast, light model. The tier names the judgment; the
pin decides the cost. The two review seats show it: *Atlas* reads
every pull request on Flash-high, and *Argus* reads the code gate on
Opus, both at review tier. Keep a seat on the pricier model where a
wrong call is expensive. Move a seat to Flash once its process earns
it, the way every rung persona already has.

List rates in $/1M tokens at or under 200k context (the system's own
ceiling, [AGENTS.md](AGENTS.md)): input / cache write (5m TTL) / cache
read / output. Claude rates match
[`scripts/ops/session_spend.sh`](scripts/ops/session_spend.sh); a 1h
TTL write costs 2x input and Fable 5.1's cache read is $0.25. The
Antigravity column is Google Cloud's Gemini Enterprise / Agent Platform
price ([#269](https://github.com/evekhm/agentic-sdlc/issues/269)); its
caching is automatic, and Flash's rate rises to $1.50 / $0.15 / $7.50
on 2027-01-01:

| Tier | Claude Code | $/1M in / write / read / out | Antigravity | $/1M in / read / out |
|---|---|---|---|---|
| Fast | `haiku` | $1.00 / $1.25 / $0.10 / $5.00 | `gemini-3.8-flash-low` | $0.75 / $0.075 / $3.75 |
| Mechanical / Implementation | `claude-sonnet-5` | $2.00 / $2.50 / $0.20 / $10.00 | `gemini-3.8-flash-medium` | $0.75 / $0.075 / $3.75 |
| Review | `opus` | $5.00 / $6.25 / $0.50 / $25.00 | `gemini-3.8-flash-high` | $0.75 / $0.075 / $3.75 |
| Frontier | `claude-fable-5-1` | $10.00 / $12.50 / $0.25 / $50.00 | `gemini-3.8-flash-high` | $0.75 / $0.075 / $3.75 |

Antigravity's rate is flat across the ladder: a higher thinking level
spends more tokens at the same rate per token. Claude Code carries the
whole spread, a 10x range from `haiku` to `claude-fable-5-1`. Moving a
seat down that spread, or onto Antigravity at any tier, is what a
maturing process recovers.

## The playbook, and what this adds

The playbook has six **stages**: Plan, Design, Build, Test, Deploy,
Maintain. Each stage ends in a committed artifact. A **play** is one
named practice inside a stage, with an enforcer, evidence, a log and an
approver. There are sixteen plays. The stages are non-linear: work
enters wherever its evidence puts it, and plays are adopted one at a
time.

This system maps the six stages onto five rungs and a close. Test
lives inside implement. Deploy is the close, because the only product
is the system itself and CI ships it. Maintain is *Cassandra*. The
non-linearity lives at the system level: *Cassandra* enters at
Maintain and produces a Plan, a defect enters at implement, a stuck
review returns to the owner, and many issues sit at different rungs at
once. The scorecard in [`docs/PLAYBOOK.md`](docs/PLAYBOOK.md) has one
row per play: what the playbook asks, how this system does it, and the
issue that tracks any gap.

On top of the playbook this system adds five things:

- **One persona source, every harness.** The compiler emits each
  harness's prompt file from one vendor-free source.
- **Two model families in the review seat.** Consensus between them is
  what reaches the default branch.
- **A real GitHub identity per persona**, so the platform enforces
  authorship and authority. The merge actor is one more identity that
  no persona holds.
- **Cost as a subsystem.** Every tier routed to the model that fits
  it, every session priced, every dispatch under a spend ceiling,
  and a ledger per issue, pull request, persona and model
  ([#104](https://github.com/evekhm/agentic-sdlc/issues/104)).
- **A living spec**, [`docs/SPEC.md`](docs/SPEC.md), that says what is
  true, beside the per-change intent, spec and plan.

## Running it yourself

You need three things:

- a clone on a branch you can push;
- the App private keys, one per persona plus *Themis*; registering
  them is [`scripts/auth/README.md`](scripts/auth/README.md);
- `gh` and `jq` authenticated against the repository. Labels and
  backlog come from [`scripts/setup/`](scripts/setup/).

The autonomous loop adds an enablement checklist, kept in
[`docs/SPEC.md`](docs/SPEC.md): *Themis* provisioned, the poller under
a supervisor, branch protection on `main`, execution bindings
validated, builder credentials preflighted, then the flip of
`loop.autonomous_merge`.

Anyone files issues, and the system files its own: *Cassandra*'s
watchers when a control band breaks, and the reviewers and the advisor
when a rung goes wrong. Search the tracker first
([AGENTS.md, "Before filing an issue"](AGENTS.md#before-filing-an-issue)).
A reviewer keeps its findings on the pull request it reviews. State
the problem and what would be true if it were solved. *Athena* asks
the rest on the thread.

Two doors file that search for you: `/idea <text>` and `/bug <text>`,
in Claude Code. Each searches the tracker first, either extends a
matching thread or files a new `intent:new` issue naming the
relationship, and never re-asks a question a `Given design:`, `Given
spec:`, or `Given code:` section in the text already answered
([#407](https://github.com/evekhm/agentic-sdlc/issues/407)).

Open a session in your harness and type, for any item at any rung:

```text
/work <n>
```

`<n>` is an issue or pull request number. The command resolves the
rung and the owning persona from the labels, prints what it resolved,
and dispatches that persona under its own identity. It prints a short
digest — status, labels, any open pull request, the last comment —
before it dispatches, so the caller can judge whether the launch is
worth it. It refuses when the item is on hold, closed, blocked,
claimed or in contradictory state. Full contract:
[`docs/SPEC.md`](docs/SPEC.md) `ops.dispatch`.

**A session ends with a handoff.** A session is ephemeral and its
context is the expensive part, so nothing it settled may live only in
its transcript. Before it ends, the session wraps with `/wrap`, the
one door
[#85](https://github.com/evekhm/agentic-sdlc/issues/85) D8 defines,
in Claude Code. The wrap runs the session
checklist, records what the session learned, and writes a dated
handoff for its seat under `ops/handoffs/`, outside git. The next
session for that seat opens with that handoff as its first input,
injected at start by the harness hook or loaded by the seat launcher,
so a successor never starts cold and never re-derives what its
predecessor already decided. The handoff joins sessions the way the
issue thread joins rungs. Close-out is
[#85](https://github.com/evekhm/agentic-sdlc/issues/85), priming and
the statusline are
[#330](https://github.com/evekhm/agentic-sdlc/issues/330), the nudge
that keeps the handoff current as the context fills is
[#329](https://github.com/evekhm/agentic-sdlc/issues/329), and the
shared store that keys handoffs per user and per seat so a seat
resumes on any machine is
[#399](https://github.com/evekhm/agentic-sdlc/issues/399).

When the owner steps in at a gate, the action means the same thing
everywhere:

- A merged pull request is acceptance of the artifact in it.
- A closed pull request is a rejection, and it is final.
- When a decision in the artifact is wrong, edit it in the pull
  request. The edited row *is* the decision. You never comment asking
  for a change and wait for a session to make it
  ([REVIEW.md, "Merge is the escape hatch"](REVIEW.md#merge-is-the-escape-hatch)).

In autonomous mode the loop merges itself when consensus is reached,
and the owner is the escalation path.

## Where the rules live

- [AGENTS.md](AGENTS.md), the standard every session reads.
- [INTENT.md](INTENT.md), why this system exists.
- [`docs/SPEC.md`](docs/SPEC.md), what is built. Trust it over this
  file.
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

This file describes the system as designed. Every issue link in it
points at the tracker item that owns that part of the design. It is
normative for nothing. Where it and any of those documents disagree, the other is
right. Its section list lives in
[`intent/35-readme/spec.md`](intent/35-readme/spec.md).
