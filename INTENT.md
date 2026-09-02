# Intent: The Agentic SDLC Workshop

**Author:** evekhm · **Status:** Draft
**Sources:** [docs/BLOG.md](docs/BLOG.md) (the playbook), [docs/CONTEXT.md](docs/CONTEXT.md) (prior art and adopted conventions)

This is the founding, system-level intent — change #0 of the system
it describes. It follows the playbook's intent template (Problem,
Proposed outcome, Affected users and systems, Constraints, Open
questions). Once the flow below is live, every subsequent change gets
its own `intent/<issue>-<slug>/intent.md`, and this file's accepted
content graduates into `docs/SPEC.md` through the normal path.

## Problem

Teams adopting coding agents bolt them onto a human-speed SDLC, and
the existing teaching material each covers only a slice:

- The playbook (docs/BLOG.md) defines the six-stage loop but is
  single-vendor by construction, has no multi-model review, and no
  living system spec.
- The colleague codelab (workshop-agentic-sdlc-lab) nails adversarial
  spec-grilling and contract traceability but is single-harness
  (everything Antigravity-coupled), has no review step, no CI, and no
  cost discipline.
- The predecessor repo (agentic-experiments-lab) proved dual-model
  review consensus, bot identities, and cost discipline — but its
  per-harness prompts were hand-maintained and drifted.

Nothing demonstrates the full loop with harness-agnostic personas,
real GitHub identities, multi-model review, and cost discipline in
one clonable repository.

## Proposed outcome

A presenter-driven workshop plus take-home template repo
demonstrating the playbook's six-stage loop end to end, where **the
demo is meta: the system builds itself.** The personas spec, plan,
implement, review, and maintain this repository — its own personas,
compiler, and workflows. The bootstrap ladder is the narrative, and
the live demo drives one real change (e.g. "add the maintainer
persona") through the entire loop.

### The artifact lifecycle (end to end)

One change, from idea to closed loop. Every stage ends by committing
an artifact whose merge triggers the next stage; lifecycle state
lives in GitHub issue labels, never in a chat transcript.

```text
1. INTAKE   GitHub issue labeled intent:new (human-filed, or filed by an
            intake chat agent per the playbook's connector pattern later).
2. PLAN     Athena brainstorms in the issue thread (analyst questions:
            scope, users, constraints, success), then opens a PR adding
            intent/<issue>-<slug>/intent.md  (template: Problem, Proposed
            outcome, Affected users and systems, Constraints, Open
            questions; author + status line).
            GATE: product owner (human) edits/accepts; MERGE = accepted.
            Reject = closed PR. Metric: intent survival rate.
3. DESIGN   The intent-acceptance merge triggers the spec pass: Athena
            drafts spec.md into the SAME folder as a PR, constrained by
            repo skills (security, style, sanitization policy), then
            interrogates it with the spec-adversary protocol: one
            ambiguity at a time, two defensible readings plus the
            concrete assertion that differs, never recommends; every
            resolution becomes a numbered row in the spec's Decisions
            table. Spec status Draft → Approved only when Open questions
            is empty.
            GATE: "nothing is dispatched against a Draft." PO merges.
4. BUILD    Daedalus converts the approved spec into plan.md (same
            folder): files that change, order of work, tests that prove
            it — committed BEFORE any code. The contract-writer subagent
            emits failing acceptance tests; every assertion cites the
            Decision ID it derives from (an uncited assertion is an
            invention; an underivable assertion returns control to the
            adversary).
            GATE: contract shows failures, not errors.
5. IMPLEMENT Odyssey is dispatched at a pinned SHA ({repo, sha, branch,
            issue}); works on odyssey/<issue>-<slug>; self-verifies; the
            implementation PR carries the diff, the plan.md sync (any
            deviation updates plan.md in the same commit), and the
            docs/SPEC.md upsert (per-change spec outcome merged into the
            living system spec).
6. REVIEW   Argus and Atlas — two independent reviewers, deployment-
            pinned to different model families — review per protocol v2:
            severity tiers, per-finding IDs, and consensus votes keyed
            per Decision ID where applicable. review:N counter labels
            escalate to status:review-stuck for humans; a hold label is
            the circuit breaker halting all automation.
            GATE: human merges; agents have no path to main. Merge gate
            includes checking WHICH files the agent touched.
7. DEPLOY   CI ships the system's own automation (workflows, compiled
            personas, sidecars) up to the human-authorized gate.
8. MAINTAIN Cassandra's deterministic watchers compare metrics to
            control bands: log at 1σ, diagnose read-only at 2σ, propose
            at 3σ — a proposal is a new issue labeled intent:new,
            closing the loop.
```

### Where artifacts live

```text
INTENT.md                     # this file: the system-level intent (change #0)
intent/<issue>-<slug>/        # one folder per change — the change record
  intent.md                   #   what was asked for        (Plan gate)
  spec.md                     #   what was decided + Decisions table (Design gate)
  plan.md                     #   how it was built           (committed before code)
docs/SPEC.md                  # the LIVING system spec: current-state truth,
                              #   upserted by every behavior-changing PR
                              #   (per AGENTS.md; CI-enforced spec check)
REVIEW.md                     # review policy the reviewers compile against
```

The per-change triple is the immutable audit trail ("what was asked,
what was decided, how it was built"); `docs/SPEC.md` is the queryable
current state. The playbook defines only the former; the predecessor
proved the latter; this repo runs both, joined by the SPEC.md-upsert
rule in the implementation PR.

### The persona cast (six, each a GitHub bot identity)

Persona definitions are **fully harness- and vendor-agnostic**: no
persona source names a harness, a model family, or a model ID. Which
runtime and family back each persona is a deployment pin in `config/`
and can be switched without touching the persona. A persona is
defined by five facts — the stage it owns, the protocol it runs, the
authority it holds (enforced by branch protections and path checks,
not by prompt), the tier it thinks at, and the GitHub identity it
acts as. Never the model behind it.

**Athena — the product owner** *(Plan + Design · GitHub App
`evekhm-athena-app`)*
Owns the two gates where words become commitments. Brainstorms in the
intake issue (scope, users, constraints, success), opens the PR
adding `intent.md`, and after acceptance drafts `spec.md` — then
turns adversary against her own draft: one ambiguity at a time, two
defensible readings plus the concrete assertion that differs, never
recommending; every resolution lands as a numbered row in the
Decisions table. Authority: comments and PRs touching `intent/` only.
Tier: FRONTIER.

**Daedalus — the architect** *(Build · GitHub App
`evekhm-daedalus-app`)*
Converts an approved spec into a micro-stepped `plan.md`: the files
that change, the order of work, the tests that prove it — committed
before any code exists. Reads code freely, never writes it.
Authority: PRs touching plan files only. Tier: FRONTIER.

**Odyssey — the implementer** *(Implement · GitHub App
`evekhm-odyssey-app`, carry-over identity, now App-backed)*
Dispatched at a pinned SHA (`{repo, sha, branch, issue}`), works TDD
against the contract tests, and ships one PR carrying three things:
the diff, the `plan.md` sync (any deviation updates the plan in the
same commit), and the `docs/SPEC.md` upsert. Authority: writes only
`odyssey/*` branches, never the default branch. Tier:
IMPLEMENTATION, escalating to FRONTIER when debugging demands it.

**Argus and Atlas — the two reviewers** *(Review · GitHub Apps
`evekhm-argus-app` and `evekhm-atlas-app`, carry-over identities, now
App-backed)*
Two independent voices running the same protocol v2 — severity
tiers, per-finding IDs, consensus keyed to Decision IDs — with all
GitHub writes through trusted posting steps. Argus is event-driven;
Atlas is the second opinion that makes consensus meaningful. Their
value is disagreement resolved by evidence, which is why deployment
pins them to different model families. Authority: comment-only, for
both. Tier: REVIEW.

**Cassandra — the maintainer** *(Maintain · GitHub App
`evekhm-cassandra-app`)*
Deterministic watchers compare live metrics to control bands; she
responds in proportion: log at 1σ, diagnose read-only at 2σ, propose
at 3σ — and a proposal is a new issue labeled `intent:new`, which is
how the loop closes. Authority: comments and issues only. Tier: FAST
for sweeps, REVIEW for diagnosis.

Non-negotiables: the two reviewers are deployment-pinned to
**different model families** (which family backs which reviewer is a
config fact, not part of the persona); evidence arbitrates, never
identity; all workflow-driven GitHub writes go through trusted
posting steps; humans own every activation act.

#### Sub-agents (compiled workers — no GitHub identity)

Personas delegate to a shared roster of sub-agents, also defined
canonically in `personas/` (flagged `subagent: true`, tool-
allowlisted, cheaper tiers). They exist for two reasons: cost (route
work to the cheapest capable tier) and context (the parent receives
summaries, never the raw material — delegation as context firewall).
Carry-overs are proven in the predecessor repo.

- **mechanic** (MECHANICAL, carry-over) — executor for fully
  specified mechanical work: batch edits from an explicit spec,
  multi-file greps/searches, running test suites and reporting
  results, formatting sweeps, applying a reviewer's named fixes.
  Makes no design decisions; reports what was done and what was
  verified.
- **coder** (IMPLEMENTATION, carry-over) — spec-driven implementer:
  takes a dispatch-ready spec (target SHA, file-level steps, test
  plan, acceptance criteria) and implements it exactly; runs the
  tests; never pushes; hands open design questions back instead of
  deciding them.
- **contract-writer** (IMPLEMENTATION, new — from the colleague lab)
  — converts an Approved spec into failing acceptance tests; every
  assertion cites the Decision ID it derives from; an assertion it
  cannot derive is returned as a gap (missed ambiguity), never
  guessed.
- **scanner** (FAST, new — lite-luncher pattern) — wraps
  deterministic check scripts (credentials, home paths, naming): runs
  the script, parses exit code and output, consolidates findings into
  one reviewable report artifact. The script decides; the sub-agent
  only orchestrates and reports.
- **explorer** (FAST, new) — read-only search fan-out over code,
  docs, and threads; returns conclusions and locations, never file
  dumps. The default vehicle for any read-many task.

### Harness-agnostic architecture (the compiler)

1. **Canonical personas** in `personas/<name>.yaml`: metadata +
   authority level, pure behavioral contract, abstract capabilities,
   semantic model tier. The colleague lab's SKILL.md hand-writes its
   own capability fallback ("where there is no ask_question tool,
   write the three parts out and wait") — exactly what the compiler
   generates instead.
2. **Semantic tiers**, a five-grade ladder mapped in
   `config/model_tiers.yaml`; no vendor model IDs in persona sources,
   ever. Each grade is defined by the work it is trusted with, not by
   any vendor's product line:
   - `FAST_TIER` — deterministic sweeps, trivial lookups, routing,
     script-wrapping (scanner, explorer).
   - `MECHANICAL_TIER` — batch edits from an explicit spec, greps,
     test runs, formatting, applying named fixes (mechanic). No
     decisions.
   - `IMPLEMENTATION_TIER` — spec-driven coding from a dispatch-ready
     spec with no open design decisions (coder, contract-writer,
     Odyssey's normal mode).
   - `REVIEW_TIER` — evidence-based review and analysis: reading
     diffs against a protocol, diagnosing from logs (Argus, Atlas,
     Cassandra at 2σ).
   - `FRONTIER_TIER` — design, architecture, adversarial spec
     grilling, tricky debugging (Athena, Daedalus, escalations).
3. **MCP-first tools** where supported; mapped to harness-native
   primitives (Bash/Read/Edit vs view_file/write_to_file) otherwise.
4. **One build** (`scripts/sync_agents.py`) emitting: Claude Code
   targets (`.claude/agents/<name>.md`), Antigravity targets
   (`.agents/agents/<name>/{agent.json,config.yaml,instructions.md}`),
   IDE targets (compiled, CI-validated, not demoed), and keeping
   `AGENTS.md` canonical with `CLAUDE.md`/`GEMINI.md` as thin
   adapters (already seeded).
5. **Identity/auth separation:** credentials never in persona
   sources; env wrappers on Claude Code, token files +
   `inherit_user: false` on Antigravity. Each of the six personas is
   its own GitHub App (`evekhm-<name>-app[bot]`); no static PATs. A
   session mints a ~1-hour installation token on demand
   (`scripts/auth/mint_app_token.py <persona>`) from the App's
   private key — the only secret, held in an Actions secret or a
   local `~/.keys/*.private-key.pem` file, never a long-lived token
   committed or stored as a login credential.
6. **Gates in CI:** drift check (hand-edited compiled files fail the
   build), secret/path sanitization of everything compiled
   (deterministic scanner scripts in CI, not invoke-me-maybe skills —
   adk-agents ships a committed `.env` password *alongside* an unused
   credential-scanner skill, which is the argument), spec check, and
   roundtrip validation (new persona → working configs on both live
   harnesses from one command).

Deployment pinning: persona sources never say which harness or model
family runs them. `config/` carries the pins — which harness executes
which persona, and which vendor family backs each tier on that
harness. v1 deploys **two harnesses live** (currently Claude Code and
Antigravity — swappable by editing pins, not personas); dual-model
review only requires that the two reviewers' pins resolve to
different model families. IDE targets compiled-only.

### Repository layout (target)

Placement rule: the root holds only files a harness or GitHub
requires at the root, plus the flagship trio (README, REVIEW policy,
this founding intent). All other prose lives in `docs/`; everything
generated is never hand-edited; everything experimental lands in
`runs/` and stays out of git.

```text
AGENTS.md  CLAUDE.md  GEMINI.md   # harness entry points (root-required);
                                  #   AGENTS.md canonical, others thin adapters
README.md  REVIEW.md  INTENT.md   # flagship docs (README/REVIEW.md to come)
intent/<issue>-<slug>/            # per-change record: intent.md, spec.md, plan.md
docs/                             # SPEC.md (living spec), BLOG.md, CONTEXT.md,
                                  #   setup guides
personas/                         # canonical persona + sub-agent sources
config/                           # model_tiers.yaml, deployments.yaml, tools.yaml
scripts/                          # sync_agents.py; ci/, setup/, ops/ subdirs
evals/                            # continuous evals for personas/config changes
.github/workflows/                # stage triggers, gates, drift + sanitization CI
.claude/agents/  .agents/agents/  # GENERATED harness targets — never hand-edited
runs/YYYY-MM-DD_*/                # experiment/run artifacts (gitignored)
```

### Workshop storyline (presenter-driven, shared repo)

1. **Delegation economics opener (5 min)** — the agy-subagents
   pattern: same task parent-executed vs delegated, token difference
   on screen. Grounds the cost module.
2. **The foundation** — AGENTS.md discipline: run folders, living
   spec, 200K ceiling and `/autocompact`, cache-TTL-matched looping,
   `session_spend.sh` on a real transcript.
3. **One persona, every harness** — edit a canonical persona, run the
   compiler, show both harness outputs; hand-edit a compiled file and
   watch the CI drift check fail.
4. **The loop, live (the meta act)** — file an `intent:new` issue for
   a real capability of this repo; Athena grills a deliberately
   flawed draft spec (planted ambiguities with concrete fixture rows,
   including one contradiction between two individually-clear
   passages); contract tests cite Decision IDs; Odyssey dispatched at
   a pinned SHA; Argus and Atlas disagree on at least one finding and
   resolve by evidence; human merges; SPEC.md gains the capability.
5. **Closing the loop** — a seeded control-band breach; Cassandra
   diagnoses read-only and files the next `intent:new` issue.

## Affected users and systems

- **Workshop attendees** (engineers/leads adopting agentic SDLC) —
  watch live, clone the template after.
- **Presenter** — needs a re-runnable demo: resettable repo state,
  seeded incident, idempotent provisioning.
- **GitHub** — the demo org/repo, six bot identities, Actions
  workflows, labels as the state machine.
- **Model runtimes (GCP)** — two model-family deployments behind the
  tier pins (WIF-authenticated from Actions, per the predecessor's
  Argus path); optional Agent Runtime for a dispatched implementer.
  Which family serves which persona is config, not architecture.
- **The predecessor repo** — source of tested artifacts (see
  docs/CONTEXT.md §1); not modified.

## Constraints

- Zero prompt duplication: every rule in a compiled target traces to
  one canonical source; drift fails CI.
- No secrets or local paths in anything committed or compiled;
  scanning is deterministic and in CI.
- Cost discipline is curriculum, not just tooling: the 200K ceiling,
  delegation economics, and dollar-ranked spend measurement get stage
  time and are encoded in the template's settings.
- Humans gate merge/deploy/close on every path; agents never reach
  the default branch; `hold` halts everything.
- The demo must be re-runnable and fail loudly: scripts follow the
  predecessor's and the lab's failure-mode-first style.
- Repo working standards are binding: run folders with dispositions,
  no document sprawl, living-spec upserts (AGENTS.md).

## Out of scope (v1)

- Live IDE-assistant demo (compiled configs only).
- Attendee self-provisioning labs (v2, once setup scripts are
  hardened for strangers).
- The chat-based intake agent for non-engineers (playbook connector
  pattern) — narrated, not built, in v1.
- Production deployment beyond the repo's own automation ("deploy" in
  the meta demo = shipping workflows, compiled personas, sidecars).

## Open questions

1. ~~**New bot identities**~~ — RESOLVED (#7): all six personas are
   GitHub Apps with short-lived installation tokens (no PAT-backed
   bot users), one App per persona so each keeps a distinct identity;
   the existing three carry-overs (Odyssey, Argus, Atlas) migrate off
   their PAT accounts onto Apps named `evekhm-<name>-app` — every App
   uses an `-app` suffix (not `-bot`) since the pre-existing PAT
   accounts held the bare `-bot`/plain names at registration time and
   App slugs share the username namespace. Names, per-persona
   permissions, and webhook events are recorded on issue #7; the
   `personas/*.yaml` authority blocks and `scripts/auth/mint_app_token.py`
   carry the mechanism.
2. **Hosting**: which org/repo for the shared demo; is the take-home
   template the same repo or a sanitized twin?
3. **Runtime placement** — PARTIALLY RESOLVED: harness (which agent
   framework interprets a persona — Claude Code vs Antigravity, pinned
   in `config/deployments.yaml`) and deployment/execution environment
   (where that framework's process runs and what triggers it — local
   interactive, GitHub Actions, a VM, Cloud Run, an agent platform) are
   orthogonal axes. The compiler (#5) stays scoped to producing the
   harness-native persona definition only and carries no deployment
   knowledge; each automation issue (#8 Argus, #9 Atlas, #10 Athena
   intake, #11 Cassandra watchers) decides its own execution
   environment at build time rather than one upfront global pin, since
   event-triggered review/intake and continuous watching are genuinely
   different trigger shapes. Antigravity does support headless
   invocation (confirmed), so atlas being antigravity-pinned does not
   block #9. Still open: the concrete target per persona/issue (which
   of local/github-actions/vm/agent-platform/cloud-run) and Cassandra's
   watcher cadence and seeded-incident mechanism — decided when each
   issue is picked up, not now.
4. **Label taxonomy**: adopt agent-farm's `status:*` state machine
   names verbatim or align with the predecessor's `argus:*` /
   `review:*` labels? One taxonomy must win before workflows exist.
5. **Dispatched implementer transport**: predecessor's
   watcher-daemon Odyssey (mention-summoned, headless CLI dispatch)
   vs the lab's Agent-Runtime dispatch at pinned SHA — or show both
   as two deployment options of one persona?
6. **lite-luncher**: offer it as the optional hands-on target in the
   take-home template (its missing tests and rule drift are
   ready-made exercises), alongside the meta demo? (Recommended: yes,
   as an appendix track.)
7. **Test-stage depth in v1**: ship continuous evals in CI for
   `personas/**` changes, or narrate and defer to v2?
8. **Git notes for per-commit rationale** (conductor pattern): adopt,
   or does the intent-folder audit trail make it redundant?
9. **Workshop length** (60 min like the colleague lab, or 90–120 for
   the full loop) and audience seniority — determines cost-module
   stage time.

---
Disposition (2026-09-01): rewritten after research pass
(runs/2026-09-01_research/); supersedes the first draft (intent.md,
deleted same day). Later same day: repo went live at
github.com/evekhm/agentic-sdlc with the bootstrap backlog filed as
issues (scripts/setup/bootstrap_tracker.sh) — the pinned Bootstrap
tracker issue is now the tracker of record, per AGENTS.md "Working
the tracker".
