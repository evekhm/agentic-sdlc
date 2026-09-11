# Changelog

All notable behavioral and user-facing changes to this repository are documented in this file in reverse-chronological order. Each entry describes what capability changed, why the change was made, and the operational or user-visible impact on operators, personas, or workflows.

## 2026-09-11

### [PR #450](https://github.com/evekhm/agentic-sdlc/pull/450): Ban Rhetorical Negated-Contrast Prose in AGENTS.md
Adds a "Prose style" MUST rule to AGENTS.md banning the `X, never Y` / `X, not Y` / `rather than X` / `instead of X` construction when used purely for rhetorical parallelism, with the exact grep to catch it before delivery, and fixes the ~20 existing instances already in the file. The construction had spread through the repository's own canonical docs because the prior ban lived only in one operator's private notes; every persona and every harness reads AGENTS.md before writing, so the rule now lives where it will actually be seen.

### [PR #440](https://github.com/evekhm/agentic-sdlc/pull/440): Athena as the Front Door for Product Intake ([#404](https://github.com/evekhm/agentic-sdlc/issues/404))
Athena now owns product intake: an interactive protocol that scopes an ask down one question at a time, searches the tracker for prior art and recorded decisions before filing, states how a new issue relates to existing threads, and keeps README.md as the concept and vision document. New intents were being filed without a duplicate search or a decision lookup, and the spec gate let self-contradicting decisions through. Operators start an intent conversation with Athena from either harness, the tracker search gains a decisions pass over every merged spec, and the tracker carries the duplicate and area labels the protocol assigns.

## 2026-09-10

### [PR #414](https://github.com/evekhm/agentic-sdlc/pull/414): Approved Specification for CHANGELOG.md and Hard CI Merge Gate ([#410](https://github.com/evekhm/agentic-sdlc/issues/410))
Establishes the specification for a root CHANGELOG.md, a dedicated fail-closed CI verification gate, and governance updates across repository standards. This resolves the gap where changes merged without accessible human-readable summaries. Implementers and reviewers gain clear requirements for changelog entries and bypass markers on behavior-bearing PRs.

### [PR #409](https://github.com/evekhm/agentic-sdlc/pull/409): Structured CLI Intake Commands for Issues and Bugs ([#407](https://github.com/evekhm/agentic-sdlc/issues/407))
Adds structured CLI intake commands in `scripts/ops/intake.sh` for filing feature intents, bugs, and operational tasks. Manual issue filing was prone to missing required frontmatter, malformed headers, and incomplete dependency declarations. Operators and unattended agents can now deterministically create properly structured issues and worktrees.

### [PR #403](https://github.com/evekhm/agentic-sdlc/pull/403): Statusline Instrumentation for Background Sessions ([#330](https://github.com/evekhm/agentic-sdlc/issues/330))
Introduces statusline instrumentation and telemetry formatting for running harness sessions. Operators previously had limited visibility into background runner execution status and token expenditure without scanning raw transcript files. The statusline provides live stage, duration, cost, and health diagnostics.

### [PR #401](https://github.com/evekhm/agentic-sdlc/pull/401): Multi-Harness Persona Compilation Parity ([#401](https://github.com/evekhm/agentic-sdlc/issues/401))
Ensures persona compilation generates targets for both Claude and Antigravity harnesses symmetrically. A compiler divergence previously allowed one harness target to fall out of sync with persona YAML sources without triggering drift detection. Drift checks now rigorously validate all harness targets across the repository.

### [PR #388](https://github.com/evekhm/agentic-sdlc/pull/388): Review Recorder Initial Run Evaluation Hardening ([#353](https://github.com/evekhm/agentic-sdlc/issues/353))
Fixes edge-case handling in the review recorder when processing initial runner verdicts with run ID zero. The consensus recorder previously failed to parse review comments that omitted non-zero run identifiers. Consensus evaluation now reliably records early review verdicts without stalling the autonomous merge gate.

### [PR #387](https://github.com/evekhm/agentic-sdlc/pull/387): Lock Severity on Previously Observed Findings ([#361](https://github.com/evekhm/agentic-sdlc/issues/361))
Enforces immutability of severity ratings for findings previously recorded by Argus or Atlas. Reviewers could previously downgrade findings across rounds without explicit remediation evidence, risking premature merge. The recorder preserves finding severity until the filing reviewer explicitly signs off on closure.

### [PR #375](https://github.com/evekhm/agentic-sdlc/pull/375): Prevent Demotion of High-Severity Findings ([#354](https://github.com/evekhm/agentic-sdlc/issues/354))
Blocks automated demotion of high-severity review findings to lower tiers during multi-round reviews. High-severity issues require verified fixes and must not be suppressed by secondary model evaluations. The autonomous loop prevents PR merges while any high-severity finding remains unaddressed.

### [PR #371](https://github.com/evekhm/agentic-sdlc/pull/371): Prioritize Fix-Round Queue in Continuous Poller ([#337](https://github.com/evekhm/agentic-sdlc/issues/337))
Updates the poller dispatch queue to prioritize active repair rounds over new issue intake. Sessions in active review fix cycles previously competed with unstarted backlog items, delaying PR closure. Active pull requests with review findings are now dispatched ahead of new work items.

### [PR #351](https://github.com/evekhm/agentic-sdlc/pull/351): Preserve Completed Runner Review State on Timeout ([#312](https://github.com/evekhm/agentic-sdlc/issues/312))
Preserves posted review artifacts and verdicts even when a background runner execution exceeds its timeout threshold. Runner timeouts previously discarded partially completed review comments and caused redundant re-dispatches. Completed review verdicts remain intact on pull requests despite harness termination.

## 2026-09-09

### [PR #350](https://github.com/evekhm/agentic-sdlc/pull/350): Merge Gate Conjunct Alignment with Branch Protection ([#321](https://github.com/evekhm/agentic-sdlc/issues/321))
Aligns merge gate conjuncts 9 and 10 with required status checks declared in GitHub branch protection rules. Mismatches between branch protection contexts and merge gate evaluation previously caused conflicting merge eligibility states. The autonomous merge gate now matches repository branch protection rules cleanly.

### [PR #327](https://github.com/evekhm/agentic-sdlc/pull/327): Poller Intake Gating and Concurrency Controls ([#295](https://github.com/evekhm/agentic-sdlc/issues/295))
Introduces explicit `intake:auto` label gating and the `loop.max_concurrent_first_hops` ceiling for the poller. Unattended first-hop intake previously risked overwhelming model quotas and concurrent runner limits. Operators now maintain precise control over automated task intake volume and concurrency.

### [PR #326](https://github.com/evekhm/agentic-sdlc/pull/326): Review Recorder Hold Parity and Fail-Closed Engine ([#291](https://github.com/evekhm/agentic-sdlc/issues/291))
Extracts the review recording logic into a robust Python engine and enforces absolute hold label parity. Inconsistent hold checking previously allowed the recorder to process reviews while work was paused by operators. The circuit breaker is now universally respected across both merge and review recording operations.

### [PR #319](https://github.com/evekhm/agentic-sdlc/pull/319): Two-Tier Review Assignment and Deep Review Grant ([#265](https://github.com/evekhm/agentic-sdlc/issues/265))
Implements two-tier review assignment routing Atlas to lightweight checks and Argus to deep reviews, with criteria-based deep review grants. Running full-depth multi-model reviews on routine or documentation diffs created unnecessary cost and latency. Trust-bearing paths, large diffs, and high-risk changes automatically inherit comprehensive review coverage.

### [PR #310](https://github.com/evekhm/agentic-sdlc/pull/310): Merge Gate Skipped Job Handling and PR Resolution ([#298](https://github.com/evekhm/agentic-sdlc/issues/298))
Hardens merge gate evaluation to treat skipped conditional CI jobs as non-failing and improves PR issue reference parsing. Conditional workflow jobs previously blocked Conjunct 2 evaluation because skipped states were treated as unpassed checks. Merge gate status check evaluation now correctly distinguishes skipped jobs from genuine failures.

### [PR #297](https://github.com/evekhm/agentic-sdlc/pull/297): Enable Autonomous Merge Loop in Configuration ([#64](https://github.com/evekhm/agentic-sdlc/issues/64))
Activates `loop.autonomous_merge: true` in repository configuration to turn on automatic pull request merging. Pull requests meeting all eleven merge conjuncts had previously required manual operator merges during staging. Eligible pull requests reaching consensus now merge autonomously without operator intervention.

### [PR #294](https://github.com/evekhm/agentic-sdlc/pull/294): End-to-End Autonomous Lifecycle Chain Validation ([#251](https://github.com/evekhm/agentic-sdlc/issues/251))
Proves the complete five-stage autonomous lifecycle from intent through review consensus in continuous integration. Integration confidence required verified end-to-end multi-agent execution across realistic repository tasks. All persona stages and merge gating conjuncts operate cohesively in production.

### [PR #292](https://github.com/evekhm/agentic-sdlc/pull/292): Severity-Tiered Review Verdicts and Review Policy ([#267](https://github.com/evekhm/agentic-sdlc/issues/267))`
Implements the consensus review recorder and four-tier severity classification in `REVIEW.md`. Subjective reviewer comments previously lacked deterministic criteria for determining when a PR was safe to merge. The recorder objectively evaluates structured review findings and enforces blocking rules.

## 2026-09-08

### [PR #279](https://github.com/evekhm/agentic-sdlc/pull/279): Autonomous Loop Orchestrator and Eleven-Conjunct Merge Gate ([#64](https://github.com/evekhm/agentic-sdlc/issues/64))
Implements `scripts/ci/merge_gate.sh` evaluating eleven strict conjuncts before permitting pull request merges. Merging changes safely required automated validation of branch protection, CI status checks, review consensus, and ledger state. Autonomous PR merges are strictly gated against regressions and unverified changes.

## 2026-09-07

### [PR #218](https://github.com/evekhm/agentic-sdlc/pull/218): Independent Review Claim Mutex ([#207](https://github.com/evekhm/agentic-sdlc/issues/207))
Isolates pull request review dispatch mutexes from the issue's authoring in-progress label. Reviewers were previously prevented from claiming PR reviews when an implementer's claim was active on the issue. Review personas can now claim and execute reviews concurrently without colliding with implementation mutexes.

### [PR #214](https://github.com/evekhm/agentic-sdlc/pull/214): Hardened Runner Dependency Environment ([#169](https://github.com/evekhm/agentic-sdlc/issues/169))
Ensures unattended runner environments pre-install required JSON schema dependencies. Unattended worker jobs previously failed when validating configurations in fresh virtual environments. Personas executing on runners now reliably perform schema validation without missing environment packages.

### [PR #208](https://github.com/evekhm/agentic-sdlc/pull/208): Nestor Advisor Persona and Critical Path Governance ([#199](https://github.com/evekhm/agentic-sdlc/issues/199))
Introduces the Nestor advisor persona and operational tracking standards in `docs/CRITICAL_PATH.md`. Managing complex milestone sequencing required centralized guidance on task priority and unblocking strategies. Nestor maintains the critical path roadmap and provides architectural guidance across personas.

## 2026-09-06

### [PR #189](https://github.com/evekhm/agentic-sdlc/pull/189): Fail-Closed Guard Against Unreviewable Dispatches ([#165](https://github.com/evekhm/agentic-sdlc/issues/165))
Adds fail-closed validation to prevent review sessions from dispatching against unresolvable diffs or corrupted states. Review runners previously stalled or burned quota attempting to evaluate invalid pull requests. The dispatch launcher exits early with informative diagnostics when a PR cannot be reviewed.

### [PR #187](https://github.com/evekhm/agentic-sdlc/pull/187): Strict Schema Validation for Lifecycle Definitions ([#52](https://github.com/evekhm/agentic-sdlc/issues/52))
Implements JSON schema validation for `personas/lifecycle.json` in the compiler test suite. Manual edits to lifecycle transition tables risked introducing silent state machine regressions or invalid stage names. The compiler and CI suites verify lifecycle definitions against a rigid schema.

### [PR #184](https://github.com/evekhm/agentic-sdlc/pull/184): Enforcement of Session Spend and Cost Ceilings ([#172](https://github.com/evekhm/agentic-sdlc/issues/172))
Introduces pre-emptive and post-hoc session spend controls via `WORK_MAX_USD` and `WORK_COST_FILE`. Unattended agent loops without financial guardrails risked runaway model consumption on complex tasks. Sessions automatically terminate or refuse execution when exceeding configured spend limits.

### [PR #164](https://github.com/evekhm/agentic-sdlc/pull/164): Comprehensive Diff Visibility for Reviewers ([#162](https://github.com/evekhm/agentic-sdlc/issues/162))
Ensures review dispatches fetch full git history and compute diffs against the proper base commit. Review personas previously evaluated incomplete diffs when shallow checkouts omitted base commit context. Reviewers now reliably inspect the full change set and surrounding file context.

## 2026-09-05

### [PR #178](https://github.com/evekhm/agentic-sdlc/pull/178): Unattended Workflow Credential Preflight Verification ([#131](https://github.com/evekhm/agentic-sdlc/issues/131))
Replaces silent credential fallbacks with explicit preflight checks in `.github/workflows/unattended.yml`. Unset secrets previously caused cryptic failures late in workflow runs or silently skipped critical stages. Workflows now fail fast with actionable diagnostics when required credentials are missing.

## 2026-09-04

### [PR #171](https://github.com/evekhm/agentic-sdlc/pull/171): Dispatch Re-entrancy Protection ([#134](https://github.com/evekhm/agentic-sdlc/issues/134))
Adds `WORK_DISPATCHED_ISSUE` tracking to prevent re-entrant dispatch cycles. Automated tasks executing scripts could accidentally trigger nested dispatches of the same issue number. The dispatcher refuses re-entrant invocations, preventing infinite session recursion.

### [PR #160](https://github.com/evekhm/agentic-sdlc/pull/160): Headless Execution Mode for Automated Dispatches ([#159](https://github.com/evekhm/agentic-sdlc/issues/159))
Adds `HEADLESS=1` mode to `scripts/ops/work.sh` for non-interactive execution in CI runners. Interactive CLI prompts blocked automated background execution on unattended virtual machines. Agents execute unattended in headless containers while streaming structured logs.

### [PR #140](https://github.com/evekhm/agentic-sdlc/pull/140): Strict Marker Syntax Validation in Standards ([#139](https://github.com/evekhm/agentic-sdlc/issues/139))
Clarifies in `AGENTS.md` that machine bypass markers are exact regex prefixes rather than prose descriptions. Contributors previously wrote descriptive paraphrases that failed automated grep validation in CI. The documentation explicitly prescribes the required marker format and separator rules.

### [PR #138](https://github.com/evekhm/agentic-sdlc/pull/138): Fail-Closed Refusal for Off-Ladder Issue States ([#129](https://github.com/evekhm/agentic-sdlc/issues/129))
Ensures `scripts/ops/work.sh` returns exit code 2 when an issue carries no recognized lifecycle stage. Ambiguous issue states previously resulted in indeterminate failures or unguided model prompts. The launcher refuses execution cleanly when an issue is not on an actionable rung.

### [PR #133](https://github.com/evekhm/agentic-sdlc/pull/133): Externalized Harness Deployment Configuration ([#44](https://github.com/evekhm/agentic-sdlc/issues/44))
Moves persona-to-harness pins into `config/deployments.yaml`. Hardcoded harness assignments in shell scripts made changing models or runtimes brittle and fragmented. Harness selections and model configurations are managed centrally in declarative YAML.

### [PR #116](https://github.com/evekhm/agentic-sdlc/pull/116): Dynamic Model Tier Selection via CLI Flags ([#108](https://github.com/evekhm/agentic-sdlc/issues/108))
Adds `--model` flag support to `scripts/ops/work.sh` and logs actual billed model names. Operators needed the flexibility to escalate individual runs to frontier models without recompiling persona definitions. Dispatches can be retiered on demand while tracking precise cost attribution.

### [PR #111](https://github.com/evekhm/agentic-sdlc/pull/111): Resilient Comment Handling in Lifecycle Advance ([#73](https://github.com/evekhm/agentic-sdlc/issues/73))
Prevents `scripts/ci/lifecycle_advance.sh` from failing when transition comment posting encounters errors. Comment API failures previously caused the entire lifecycle transition to crash after labels had already updated. State machine advancement proceeds reliably with appropriate error logging.

### [PR #102](https://github.com/evekhm/agentic-sdlc/pull/102): Monotonic State Transitions and Fork Security ([#72](https://github.com/evekhm/agentic-sdlc/issues/72))
Hardens the lifecycle state machine to enforce strictly monotonic status transitions and reject untrusted forks. Out-of-order event delivery or unauthorized pull requests could potentially regress issue stages. Transitions are strictly ordered and validated against merge base commits.

### [PR #97](https://github.com/evekhm/agentic-sdlc/pull/97): Unattended Agent Execution Framework ([#25](https://github.com/evekhm/agentic-sdlc/issues/25))
Implements `.github/workflows/unattended.yml` and `config/execution.yaml` for automated event-driven agent runs. Autonomous development required a robust mechanism to trigger persona executions on repository events. Event subscriptions, persona placement, and runner workflows operate automatically.

### [PR #90](https://github.com/evekhm/agentic-sdlc/pull/90): Atomic Issue Claiming and Worktree Isolation ([#87](https://github.com/evekhm/agentic-sdlc/issues/87))
Introduces `scripts/ops/claim.sh` to provide an atomic mutex and dedicated git worktree for each session. Concurrent agent sessions previously risked editing the same working tree or duplicating work on open issues. Claims guarantee that exactly one session operates on an issue in an isolated directory.

## 2026-09-03

### [PR #84](https://github.com/evekhm/agentic-sdlc/pull/84): Repository Scripts Reference and Contract Catalog ([#83](https://github.com/evekhm/agentic-sdlc/issues/83))
Adds `scripts/README.md` documenting every operational and CI script, its argument contract, and its side effects. Tooling had grown rapidly without a centralized guide for operators and automated agents. Agents and contributors have clear documentation for invoking repository utilities safely.

### [PR #81](https://github.com/evekhm/agentic-sdlc/pull/81): Worktree Hygiene and Pruning Utilities ([#80](https://github.com/evekhm/agentic-sdlc/issues/80))
Adds `scripts/ops/worktrees.sh` to monitor, inspect, and prune abandoned or completed session worktrees. Accumulated git worktrees from completed sessions consumed disk space and cluttered local working environments. Operators can inspect worktree status and prune merged session branches cleanly.

### [PR #67](https://github.com/evekhm/agentic-sdlc/pull/67): Complete Five-Rung Lifecycle State Machine ([#57](https://github.com/evekhm/agentic-sdlc/issues/57))
Implements full progression through the five-rung ladder (`intent:new` through `status:in-review`) with human gate closeout. The initial state machine lacked automated advancement rules for final stage artifacts and review handoffs. Issues advance deterministically from planning to review as stage deliverables merge.

### [PR #60](https://github.com/evekhm/agentic-sdlc/pull/60): Multi-Harness Agnostic Persona Launcher ([#43](https://github.com/evekhm/agentic-sdlc/issues/43))
Generalizes `scripts/ops/work.sh` to launch personas across Claude Code and Google Antigravity runtimes with ephemeral token minting. Personas were previously constrained to manual execution setups without automated credential management. Sessions launch agnostically on configured harnesses using short-lived GitHub App tokens.

### [PR #58](https://github.com/evekhm/agentic-sdlc/pull/58): GitHub App Write Permissions for Personas ([#47](https://github.com/evekhm/agentic-sdlc/issues/47))
Configures GitHub App identities with issue and discussion write permissions. Personas lacked authorized credentials to post claim comments and transition handoffs directly to GitHub threads. Agents post authenticated claims, reviews, and handoffs under their verified bot identities.

### [PR #42](https://github.com/evekhm/agentic-sdlc/pull/42): Operator Walkthrough and Target Architecture Documentation ([#35](https://github.com/evekhm/agentic-sdlc/issues/35))
Rewrites `README.md` to document the autonomous SDLC operational walkthrough, persona cast, and CI gate mechanics. The repository lacked an accessible overview explaining how humans and agents collaborate across the lifecycle ladder. Operators have an architectural reference explaining system mechanics and dispatch commands.

### [PR #41](https://github.com/evekhm/agentic-sdlc/pull/41): Deterministic One-Argument Session Dispatch ([#36](https://github.com/evekhm/agentic-sdlc/issues/36))
Introduces `scripts/ops/work.sh` accepting only an issue or pull-request number to launch the appropriate persona. Operators previously had to manually determine lifecycle stage, select personas, and configure worktree paths. The dispatcher deterministically resolves stage, verifies claims, and sets up isolated working environments.

## 2026-09-02

### [PR #33](https://github.com/evekhm/agentic-sdlc/pull/33): Defect Repair Discipline and Advance Guard ([#32](https://github.com/evekhm/agentic-sdlc/issues/32))
Adds the three-stage defect repair flow (`intent:defect` -> `plan.md` -> fix PR) and guards `lifecycle_advance.sh` against pushes without gate crossings. Unhandled push events caused lifecycle workflow crashes, and ad-hoc bugfixes bypassed standard planning gates. Defect repairs follow an expedited yet gated path with crash-resilient CI automation.

### [PR #22](https://github.com/evekhm/agentic-sdlc/pull/22): Event-Driven Lifecycle State Machine Workflow ([#4](https://github.com/evekhm/agentic-sdlc/issues/4))
Implements `.github/workflows/lifecycle.yml` and `scripts/ci/lifecycle_advance.sh` to advance `status:*` labels on merged stage artifacts. Manual issue label manipulation was error-prone and caused tracker state to drift from committed code. Lifecycle progression is driven deterministically by artifact merges on `main`.

### [PR #21](https://github.com/evekhm/agentic-sdlc/pull/21): Deterministic Continuous Integration Merge Gates ([#6](https://github.com/evekhm/agentic-sdlc/issues/6))
Implements `.github/workflows/ci-gates.yml` running parallel drift, sanitize, and spec-check verification gates. Behavioral changes risked introducing unauthorized credential patterns, uncompiled persona drift, or unrecorded specification divergence. Pull requests are mechanically gated against drift and policy violations before merging.

### [PR #17](https://github.com/evekhm/agentic-sdlc/pull/17): Canonical Persona Compiler and Multi-Target Code Generation ([#5](https://github.com/evekhm/agentic-sdlc/issues/5))
Creates `scripts/sync_agents.py` compiling canonical YAML definitions under `personas/` into runtime targets for multiple agent harnesses. Maintaining separate instruction prompts across Claude Code and Antigravity led to prompt drift and duplicated standards. Persona instructions are maintained in single YAML sources and compiled deterministically into harness targets.

### [PR #16](https://github.com/evekhm/agentic-sdlc/pull/16): Centralized Runtime Placement Configuration ([#2](https://github.com/evekhm/agentic-sdlc/issues/2))
Establishes `config/deployments.yaml` and schema definitions to govern harness assignments and runtime placement. Persona configuration was coupled to specific runner scripts without a central registry. The repository maintains a single declarative source of truth for persona runtime bindings.

### [PR #15](https://github.com/evekhm/agentic-sdlc/pull/15): Persona Definitions and GitHub App Identity Bindings ([#1](https://github.com/evekhm/agentic-sdlc/issues/1), [#7](https://github.com/evekhm/agentic-sdlc/issues/7))
Defines canonical YAML personas (`athena`, `daedalus`, `odyssey`, `argus`, `atlas`, `themis`) and binds individual GitHub App identities. Collaborative multi-agent development requires distinct role boundaries, authority limits, and verifiable cryptographic identities. Each persona is assigned specific lifecycle stages, write boundaries, and App credentials.

### [PR #14](https://github.com/evekhm/agentic-sdlc/pull/14): Two-Reviewer Consensus and Review Verification Protocol ([#3](https://github.com/evekhm/agentic-sdlc/issues/3))
Establishes `REVIEW.md` defining dual-reviewer consensus (`argus` and `atlas`), four-tier severity classification, and verification checklists. Unstructured code reviews previously lacked objective standards for merge blocking and resolution tracking. Pull requests require structured multi-model consensus before qualifying for autonomous merge.
