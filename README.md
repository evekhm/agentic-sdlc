# agentic-sdlc

**TL;DR:** A harness-agnostic software development lifecycle run by
a cast of AI agents. The process is defined once, independent of any
vendor, and each role is placed on the coding harness and model that
fit it best. An idea enters as intent and leaves as reviewed, merged
software, and every pass through the loop improves the system that
built it.

An intent goes in. One agent sharpens it into a specification, one
plans the work, one builds it, two independent reviewers judge the
result, and a maintainer watches
it run and proposes what comes next. A human sets direction and
decides escalations.

The system follows the
[AI-native SDLC playbook](https://claude.com/blog/the-ai-native-sdlc-playbook)
and builds itself with its own loop.

## What it solves

**The process is a ladder.** This is a **harness-agnostic SDLC**: the
stages, the protocols and the gates are defined once, in vendor-free
sources, and compile to every supported harness (currently Antigravity
and Claude Code). An ask climbs a fixed sequence of stages, one persona
per stage. Every stage ends in one artifact that a person and the next
agent both read: `intent.md`, `spec.md`, `plan.md` with its failing
tests, then the code itself. Each artifact lands as a pull request, and
a merge is its acceptance.

**The team is yours to compose.** Each persona names the grade of
judgment its work needs. You decide which harness and which model
serve that grade: budget first, then the complexity of the system
being built, then what the organization already runs on and how you
like to work. A frontier model where a wrong call is expensive, a
fast and cheap model where the stage is well specified and well gated,
the platform the team already licenses everywhere else. The pins are
one line per persona in
[`config/deployments.yaml`](config/deployments.yaml), resolved against
[`config/model_tiers.yaml`](config/model_tiers.yaml). Copy the file,
edit the pins, and point the `DEPLOYMENTS` environment variable at
your copy ([#433](https://github.com/evekhm/agentic-sdlc/issues/433)).
Every composition keeps two reviewers working alongside each other;
placing them on different model families is the suggested default
([#198](https://github.com/evekhm/agentic-sdlc/issues/198)). With the
pins set, the team is ready to work.

**What the team does on its own.** Work enters as an idea written
in plain language: a problem to solve and what would be true once it
is solved. It becomes an issue on the tracker, and from that moment
the loop owns it. The product owner sharpens the ask into a
specification with numbered decisions, and asks you when a section is
thin. The architect plans the work and writes the tests that fail
until it is done. The implementer starts at a pinned commit and makes
them pass. Two reviewers judge every gate, each from a different
model family in the suggested setup, and the merge actor merges when
they agree. Each merge advances the issue to the next stage and
starts the next persona; that handover is plain automation with no AI
judgment in it. The maintainer watches the running system and files a
new issue when a metric drifts out of its band. A lesson a persona
learned the hard way is written back into the repository as a rule, a
check or a test, so the process improves with every pass. Every
session prices itself, and every dispatch runs under a spend ceiling.

**Two ways to work with it.** Both run the same ladder through the
same gates. They differ in where you sit.

- **At the keyboard.** Open a session in the harness you prefer and
  capture an idea with `/idea <text>`. The product owner searches the
  tracker, files the intent and asks you what is missing. From there
  `/work <n>` runs the next stage of that issue from inside your
  session: it starts the owning persona on its pinned harness and
  hands you back a short summary and the pull request. You read it,
  answer the questions the persona raised, and merge, or the merge
  actor merges once the reviewers agree. Then `/work <n>` again, one
  stage at a time, until the change lands. This is how one change is
  driven end to end in front of an audience. `<n>` is rarely typed
  twice: inside the issue's own worktree, `/work` alone reads it from
  the branch; from any other session it offers your open, unclaimed
  issues to pick from.
- **Handing off the day.** When an issue can run without you,
  `/work <n> --yolo` picks it up and hands it to the loop: every stage
  is dispatched, reviewed and merged on consensus, and the final pull
  request waits for your merge. Add `--auto-close` and the final pull
  request merges and the issue closes on its own. For a whole day's
  worth, sit with the advisor, pick the issues and the order they run
  in, confirm the batch once, and step away. The maintainer refills
  the backlog from what it measures. You are called on escalation
  only: a `hold`, a failed consensus, a tripped budget, an open
  security finding.

```text
 +--------------------------------------+   +----------------------------------------+
 | AT THE KEYBOARD                      |   | HANDING OFF THE DAY                    |
 | one issue, one stage at a time       |   | the loop runs while you are away       |
 +--------------------------------------+   +----------------------------------------+
 |                                      |   |                                        |
 | /idea <text>                         |   | /work <n> --yolo                       |
 |    the intent is filed               |   |    every stage dispatched, reviewed    |
 |         |                            |   |    and merged on consensus; the last   |
 |         v                            |   |    pull request waits for you          |
 | /work                                |   |                                        |
 |    one stage runs; the pull          |   | /work <n> --yolo --auto-close          |
 |    request comes back to you         |   |    the last pull request merges and    |
 |         |                            |   |    the issue closes on its own         |
 |         v                            |   |                                        |
 | you answer, you merge                |   | a whole day                            |
 |         |                            |   |    the advisor picks the batch,        |
 |         v                            |   |    you confirm it once                 |
 | /work again, until it lands          |   |                                        |
 |                                      |   | you are called on escalation only      |
 +--------------------------------------+   +----------------------------------------+
```

Autonomy is chosen per issue: the `yolo` label lets the loop run the
stages, and `auto-close` lets it land the last one
([#439](https://github.com/evekhm/agentic-sdlc/issues/439),
[#147](https://github.com/evekhm/agentic-sdlc/issues/147)). One
repository-wide kill switch, `loop.autonomy_enabled` in
[`config/execution.yaml`](config/execution.yaml), freezes every
issue's autonomy at once during an incident ("The orchestrator").
Without `--yolo`, `/work <n>` runs and blocks on one stage
([#441](https://github.com/evekhm/agentic-sdlc/issues/441)). The
advisor's scheduling of a batch across the whole backlog is
[#446](https://github.com/evekhm/agentic-sdlc/issues/446).

**The doors.** Five commands, typed inside a harness session, are the
whole typed input to the loop:

- `/idea <text>` and `/bug <text>` search the tracker first, then
  extend a matching thread or file a new issue that names the
  relationship, so duplicates stay visible
  ([#407](https://github.com/evekhm/agentic-sdlc/issues/407)).
- `/work <n>` resolves the rung and the owning persona, prints a
  digest, and dispatches that persona under its own identity;
  `--yolo` and `--auto-close` set the issue's autonomy as it goes.
  Without `--yolo` it runs one stage and hands back the pull request;
  `<n>` itself is optional, read from the current worktree's branch
  or, failing that, offered as a pick from your open issues
  ([#439](https://github.com/evekhm/agentic-sdlc/issues/439),
  [#441](https://github.com/evekhm/agentic-sdlc/issues/441); full
  contract [`docs/SPEC.md`](docs/SPEC.md) `ops.dispatch`).
- `/fast <n>` compresses the ladder for a proof of concept already
  working locally: it starts at implementation and closes on a single
  review round
  ([#444](https://github.com/evekhm/agentic-sdlc/issues/444)).
- `/wrap` closes a session: it runs the close-out checklist, records
  what the session learned, and writes a dated handoff so the next
  session at that seat starts warm and never re-derives a decision
  ([#85](https://github.com/evekhm/agentic-sdlc/issues/85)).

The commands are one source compiled to each harness, the same way
the personas are
([#416](https://github.com/evekhm/agentic-sdlc/issues/416)). A longer
conversation with the product owner, before anything is filed, is a
session with her directly: `claude --agent athena` in Claude Code, or
the compiled `.agents/agents/athena` configuration in Antigravity
([#404](https://github.com/evekhm/agentic-sdlc/issues/404)).

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
at, and the GitHub identity it acts as. Branch protections and path
checks enforce that authority.

- **Product owner, *Athena*.** Talks with the filer, writes
  `intent.md`, then writes `spec.md` under an adversarial protocol —
  one ambiguity at a time, two defensible readings, no
  recommendation. Authority: comments and pull requests touching
  `intent/` only. Frontier tier.
- **Architect, *Daedalus*.** Turns an approved spec into `plan.md` and
  the failing contract tests. Reads code freely, writes none.
  Authority: pull requests touching plan files only. Frontier tier.
- **Implementer, *Odyssey*.** Writes the code that makes the tests
  pass. Starts at a pinned commit, one pull request per rung.
  Authority: writes only `odyssey/*` branches; the default branch
  stays closed to it. Implementation tier.
- **Reviewer of every gate, *Atlas*.** Reads every pull request at
  every rung on Gemini, the high-volume seat. Posts findings with severity
  and ids. Runs the verification checklist for the rung. Authority:
  comment-only — never approves, merges, closes or edits a label.
  Review tier ([#204](https://github.com/evekhm/agentic-sdlc/issues/204)).
- **Deep reviewer, *Argus*.** Joins at the code gate, on any change to
  a trust-bearing path, and on a `review:deep` grant. Runs the same
  protocol on Claude, the other model family, plus the deep checks:
  mutation-tests the tests, re-runs the gates, reads the diff in full.
  Authority: comment-only, like *Atlas*. Review tier
  ([#265](https://github.com/evekhm/agentic-sdlc/issues/265)).
- **Maintainer, *Cassandra*.** Runs watchers over the live system.
  When a control band breaks she files the next issue. Authority:
  comments and issues only. Fast tier for sweeps, review tier for
  diagnosis ([#11](https://github.com/evekhm/agentic-sdlc/issues/11)).
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

Non-negotiables: two independent reviewers, one covering every gate
and one going deep at the code gate; evidence alone decides a
review's outcome; every workflow-driven write goes through a trusted
posting step; humans own every activation act.

**Identity and authentication.** Each persona registers as its own
GitHub App — seven Apps total, one per persona plus *Themis* — each
with its own scoped permissions: *Argus* and *Atlas* hold
`contents: read` and comment-only write, *Athena* writes only under
`intent/`. A leaked key exposes one persona's narrow scope; revoking
or rotating it leaves the other six untouched. GitHub renders every
action under that App's own `<name>[bot]` login, so a branch
protection rule, a required reviewer, or an audit trail can name a
specific persona directly. `scripts/auth/mint_app_token.py <persona>`
signs a JWT with the persona's private key and exchanges it for an
hour-long installation token, minted fresh per dispatch; the private
key is the only credential that persists, held as an Actions secret
for a hosted persona or a local key file for a VM-local one. A
dispatched session carries only the token for the persona it launches.
Full contract: [`docs/SPEC.md`](docs/SPEC.md) `identity.bots`;
registration: [`scripts/auth/README.md`](scripts/auth/README.md).

Five sub-agents carry no GitHub identity. They keep raw material out
of a persona's context and route work to the cheapest capable tier:

- **mechanic** (mechanical) — executor for fully specified work: batch
  edits from an explicit spec, multi-file greps, running test suites,
  formatting sweeps, applying a reviewer's named fixes. No design
  decisions.
- **coder** (implementation) — spec-driven implementer: takes a
  dispatch-ready spec and implements it exactly, running the tests;
  surfaces open design questions to the caller and leaves the decision
  there.
- **contract-writer** (implementation) — converts an approved spec
  into failing acceptance tests; every assertion cites the decision it
  derives from, and an assertion it cannot derive comes back as a gap.
- **scanner** (fast) — wraps a deterministic check script (credential,
  path, naming): the script decides, the sub-agent only reports.
- **explorer** (fast) — read-only search fan-out over code, docs and
  threads; returns conclusions and locations only, no file dumps.

**Tiers.** Work is graded fast, mechanical, implementation, review or
frontier. A persona names the grade its work needs. Each harness binds
the grades to models in
[`config/model_tiers.yaml`](config/model_tiers.yaml).

## The flow, rung by rung

- **Idea, before the first rung.** The owner files with `/idea <text>`
  or `/bug <text>`, or the system files on what it found —
  *Cassandra*'s watchers, a reviewer, or the advisor. *Athena* runs
  intake on every filing. A filing may already carry a `Given design:`,
  `Given spec:`, or `Given code:` section; intake treats it as
  authoritative and verbatim, taken as-is without re-derivation or
  re-questioning. The issue still climbs every rung in order, but each
  gate only fills the gaps the Given sections leave open. Full contract:
  [`docs/SPEC.md`](docs/SPEC.md) `ops.intake`.
- **Plan.** *Athena* reads the issue. When a section is thin she asks
  on the issue thread and waits for the filer, at most two rounds. She
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

## The living spec

[`docs/SPEC.md`](docs/SPEC.md) is the living spec: the queryable
statement of what the merged system does, keyed by stable capability
ids, written in the present tense, describing merged code only. The
per-change triple under `intent/` is the immutable record of one
change: what was asked, what was decided, how it was built. The spec
is the current state those changes add up to, and the pull request
that ships a behavior upserts its entry in place; git history is the
archive of every earlier wording
([AGENTS.md, "The living spec"](AGENTS.md)).

```text
intent/<issue>-<slug>/   # intent.md, spec.md, plan.md — the per-change record
docs/SPEC.md             # the living spec, upserted by every behavior-changing PR
CHANGELOG.md             # the plain-English trail of what shipped and why
REVIEW.md                # the review protocol the reviewers compile against
```

**Guardrails.** A living document rots when nothing forces the
update, so deterministic checks stand behind the rule:

- **The spec check** fails any pull request that touches a
  behavior-bearing path (`scripts/`, `personas/`, `config/`, the
  workflows, AGENTS.md, REVIEW.md) without also touching
  `docs/SPEC.md`, unless the body carries the literal marker
  `Spec-impact: none — <reason>`
  ([`scripts/ci/spec_check.sh`](scripts/ci/spec_check.sh)).
- **The changelog check** puts the same choice on `CHANGELOG.md`
  ([`scripts/ci/changelog_check.sh`](scripts/ci/changelog_check.sh),
  [#410](https://github.com/evekhm/agentic-sdlc/issues/410)).
- **The drift check** rebuilds every compiled persona file from its
  source and fails on any difference, so a hand edit to a compiled
  target cannot become a second truth
  ([`scripts/sync_agents.py`](scripts/sync_agents.py)).
- **The reviewers** read every added or changed spec entry as a claim
  and verify it against the diff that ships it
  ([REVIEW.md](REVIEW.md)).

The checks verify that the choice was made. Whether the entry is
right stays with the reviewers. Where README and any of those
documents differ, the other wins; README is normative for nothing.

## The orchestrator

The orchestrator is a seat, the advisor *Nestor*, with a
deterministic workflow beneath it. *Nestor* guides the flow: it reads
the backlog as one dependency graph and proposes which issues run and
in what order, writes the prompts the other personas run with, watches
each issue as it climbs, and steps in where something slips: a rung
that stalled, a decision nobody owns, a rule a persona had to be told.
Everything it discovers along the way it files as an issue, so no gap
lives only in a conversation. It owns no rung, implements nothing,
reviews nothing, and merges only when the merge is itself the decision
it is resolving
([#199](https://github.com/evekhm/agentic-sdlc/issues/199),
[#446](https://github.com/evekhm/agentic-sdlc/issues/446),
[#452](https://github.com/evekhm/agentic-sdlc/issues/452)).

The workflow beneath it is deterministic. It carries an issue from
one rung to the next on the same trigger every time, a merge, and it
makes no judgment call: every condition it checks is a fact it reads
from the pull request, the labels or the ledger.

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
- **The poller** is a deterministic bash script
  ([`scripts/placement/vm-local/poll.sh`](scripts/placement/vm-local/poll.sh)),
  zero model calls, ticking every 30 seconds on the operator's own
  machine. A supervisor keeps it running continuously: an Antigravity
  sidecar (`poll.sidecar.json`, `restart_policy: always`), or a
  `systemd --user` unit (`poll.service`) as the documented fallback —
  the sidecar itself makes no model call either, it only keeps the
  bash process alive and restarts it if it dies. Each tick it scans
  for an unconsumed dispatch row, a new `intent:new` issue, or a
  blocking review row on one of its own personas' pull requests; on a
  hit it claims the issue, mints that persona's own App token, and
  hands off to
  [`scripts/placement/vm-local/run.sh`](scripts/placement/vm-local/run.sh),
  which launches the persona's harness session under
  [`config/execution.yaml`](config/execution.yaml)'s spend ceiling
  ([#251](https://github.com/evekhm/agentic-sdlc/issues/251),
  [#108](https://github.com/evekhm/agentic-sdlc/issues/108)). Builders
  run here to keep their App keys off any GitHub-hosted runner.

**Two modes.** The `yolo` label on an issue arms the next-rung
dispatch and the merge of every stage; `auto-close` adds the merge of
the final pull request and the close of the issue
([#439](https://github.com/evekhm/agentic-sdlc/issues/439),
[#147](https://github.com/evekhm/agentic-sdlc/issues/147)). One
repository-wide kill switch, `loop.autonomy_enabled` in
[`config/execution.yaml`](config/execution.yaml), overrides every
label when set to false. These are the two ways to work in "What it
solves".

- **Manual.** The owner is the gate. Every guard still runs and every
  ledger row is still written. The owner reads each pull request and
  its findings and merges by hand. The action means the same thing at
  every gate: a merged pull request is acceptance of the artifact in
  it; a closed pull request is a rejection, and it is final; when a
  decision in the artifact is wrong, the owner edits it in the pull
  request, and the edited row *is* the decision
  ([REVIEW.md, "Merge is the escape hatch"](REVIEW.md#merge-is-the-escape-hatch)).
- **Autonomous.** *Themis* merges when the gate's conditions hold. At
  the code gate both reviewers must be clear of blocking findings. The
  owner is called only on escalation.

The [AI-native SDLC playbook](https://claude.com/blog/the-ai-native-sdlc-playbook)
keeps a human at every merge. Autonomous mode goes one step further:
the reviewers' consensus reaches the default branch
([#64](https://github.com/evekhm/agentic-sdlc/issues/64)). Four seats
make that safe. *Nestor* holds the judgment and files what it notices.
*Atlas* verifies every gate, and *Argus* adds a second reading at the
code gate, on another model family in the suggested setup.
*Cassandra* refills the backlog from what it measures: her watchers
compare live metrics to control bands, and a broken band becomes an
issue ([#11](https://github.com/evekhm/agentic-sdlc/issues/11)). So
the loop feeds itself from two sources, judgment through *Nestor* and
measurement through *Cassandra*, and anyone feeds it from outside
through `/idea` and `/bug`. Every filer searches the tracker first,
and a reviewer keeps its findings on the pull request it reviews
([AGENTS.md, "Before filing an issue"](AGENTS.md#before-filing-an-issue)).

**Stops.** The loop stops on `hold`, on a failed consensus, on a
tripped budget and on an open security finding, and calls the owner.
A person rejoins at the keyboard with `/work <n>`, or hands the issue
back to the loop with `/work <n> --yolo` ("What it solves",
[#89](https://github.com/evekhm/agentic-sdlc/issues/89)).

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
by editing its line; the source never changes. To run your own
composition without touching the tracked file, copy it, edit the pins,
and point the `DEPLOYMENTS` environment variable at your copy; the
dispatcher reads that copy first
([#433](https://github.com/evekhm/agentic-sdlc/issues/433),
[#251](https://github.com/evekhm/agentic-sdlc/issues/251)). The
suggested composition places the two reviewers on different model
families ([#198](https://github.com/evekhm/agentic-sdlc/issues/198)).

**The harnesses.** Each is installed once per machine[^harness]:

- **Claude Code** (Anthropic), the `claude` command. A persona runs
  as its compiled agent under `.claude/agents/`.
- **Antigravity** (Google), the `agy` command. A persona runs from
  its compiled configuration under `.agents/agents/`.

[^harness]: Install and prepare a harness once per machine:
    [`scripts/ci/install_harness.sh`](scripts/ci/install_harness.sh)
    puts both harness binaries on a fresh machine; a clone you can
    push to; `gh` and `jq` authenticated (labels and backlog come from
    [`scripts/setup/`](scripts/setup/)); persona App private keys, one
    per persona plus *Themis*
    ([`scripts/auth/README.md`](scripts/auth/README.md)); and the
    statusline plus session priming
    ([`scripts/ops/harness/README.md`](scripts/ops/harness/README.md)).


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

Rates below are $/1M tokens at or under 200k context (the system's own
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
- **Two independent reviewers.** Their consensus is what reaches the
  default branch; the suggested setup puts them on different model
  families.
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

TBD. A step-by-step guide to setting up a machine and running a
working demo, from the first `/idea` to an issue landing on its own,
is written as its own document and will be linked from here.

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
