# Reference context: prior art this workshop builds on

Companion to [BLOG.md](BLOG.md) (the AI-native SDLC playbook, our
primary flow reference). This file indexes the other source material —
colleague workshops and repos — and records what we adopt from each.
Full research reports live in `runs/2026-09-01_research/` (local
scratch, gitignored); this file carries the durable conclusions.

## 1. The predecessor repo — `~/ccai/agentic-experiments-lab`

Our own prior system: three-agent dual-reviewer consensus on GitHub —
Argus (Claude, event-driven Actions reviewer), Atlas (Gemini, polling
sidecar reviewer), Odyssey (Claude Code, mention-summoned
implementer), each a dedicated bot account, all GitHub writes through
trusted bash posting steps.

**Adopt:** the bot-identity and trusted-posting-step pattern
(`scripts/ci/argus_post_review.sh`), the idempotent provisioning
script (`scripts/setup/argus_setup.sh` + `docs/ARGUS_SETUP.md`), the
review protocol v2 (severity tiers, round funnel, per-finding IDs,
signature convention), the living `docs/SPEC.md` discipline with CI
enforcement (`scripts/ci/spec_check.sh`), the measured cost lessons
(already ported into AGENTS.md/CLAUDE.md here), and the
Atlas sidecar + Odyssey watcher runtimes.
**Avoid:** hand-maintained per-harness prompts (its Atlas
instructions, Claude agents, and AGENTS.md sections drifted and
duplicated — the exact problem persona compilation solves).

## 2. `evekhm/workshop-agentic-sdlc-lab` (fork of alanblythe's)

A 60-minute Cloud Shell codelab: spec-driven development + TDD, where
an adversarial skill forces the spec to be unambiguous before any
code exists, and a remote coder-agent is dispatched at a pinned
commit. Companion "front-door" repo `alanblythe/workshop-agentic-sdlc`
holds setup/preflight/Terraform.

Its artifact chain: vague `docs/request.md` → GitHub issue (verbatim)
→ deliberately-flawed `docs/spec.md` (Status: Draft) → interrogated
by the **spec-adversary** skill in Antigravity → each resolution
becomes a numbered row in the spec's **Decisions table** → the
**contract-writer** subagent emits failing acceptance tests, every
assertion carrying a trailing comment naming the Decision ID it came
from → coder-agent (ADK on Agent Runtime, SPIFFE identity + GitHub
deploy key) dispatched at a pinned SHA with `{repo, sha, branch,
issue}` → pushes branch `agent/parse` → human opens PR, reviews,
merges (`Closes #N`).

**Adopt (in value order):**
1. The **spec-adversary method** — one ambiguity at a time; exactly
   two defensible readings plus "the assertion that differs" (a
   concrete case from real data where the readings diverge); never
   recommend ("a spec they approved is a spec they will not have
   read"); resolutions recorded as builder-followable rules. This
   becomes the Product Owner persona's core protocol.
2. The **Decision-ID traceability spine** — an uncited assertion is
   an invention; also the natural unit for dual-reviewer consensus
   (reviewers agree/dispute per Decision ID, not per diff).
3. **Three crisp gates:** spec gate (Status: Approved + Open
   questions empty — "nothing is dispatched against a Draft");
   contract gate (`pytest` shows **failures, not errors**; a passing
   contract test means the test-writer smuggled in behavior); merge
   gate (check *which files* the agent touched — "an edit naming a
   test is the agent changing what 'done' means").
4. **Pinned-SHA dispatch** and the planted-ambiguity fixture design
   (every seeded gap has a concrete data row; include one
   contradiction between two individually-clear passages).
5. The hook allow-list pattern with default-ask and a decision log
   ("a hook that only ever says ask looks the same from the prompt as
   a hook that is not running at all"), and the scripts'
   failure-mode-first writing.

**Avoid:** single-harness coupling (everything is
Antigravity-specific packaging over portable content — the case for
our compiler; its own SKILL.md hand-writes the capability fallback a
compiler should generate); no review step at all; zero cost
discipline (open-ended interrogation loop, no meter); no CI; the
in-place `adapt_tutorial.py` mutation bug (generate all guide
variants from one template instead); the fragile 5-part "restore your
Cloud Shell" step.

## 3. `davidstanke/lite-luncher` — candidate playground app

A working ADK multi-agent app (plan a team lunch): orchestrator on
Agent Runtime → scheduling agent over A2A on Cloud Run → ADK Memory
for dietary preferences → BigQuery menu via MCP Toolbox → synthesized
menu options. Terraform, WIF-authenticated GitHub Actions, and an
Antigravity-SDK PR-review agent on Cloud Run called from CI.

**Adopt:**
- The `.agents/skills/` convention: skills that **mandate subagent
  execution** ("Always Run as Sub-Agent", justified on
  context-economics grounds) and delegate the actual check to a
  **deterministic script** (exit 0/1) — credential-detector,
  variable-naming-checker, and sanity-checker (which fans both out in
  parallel and consolidates into one reviewable report artifact).
- The code-review service's **four-tier posting fallback ladder**
  (full review → COMMENT+inline → COMMENT summary → issue comment)
  and graceful auth fallback; WIF scoped per-repo via
  `--attribute-condition="assertion.repository == …"`.
- The GEMINI.md guardrails encoding named failure loops ("stop on
  repeated errors: 3+ same error → fix root cause", "model 404 → fix
  location, not model name", eval loop as the main iteration phase,
  deploy gated on explicit human approval).
- Its two honest defects as teaching material: missing `tests/`
  despite GEMINI.md mandating pytest, and two `.agents/rules` files
  that are stale copy-paste from another project (rule drift, live).

## 4. `davidstanke/agy-subagents` — delegation economics, minimal

A five-file experiment rig: three read-only counter subagents
(tool-allowlisted, `subagent: true`) each answer a trivially
verifiable question about an 11KB lorem-ipsum file. Executed by the
parent, 11KB enters the parent context three times; delegated, three
integers come back — the delegation-as-context-firewall lesson in
measurable form. Whimsical unique names (`_koala`, `_squirrel`,
`_elephant`) make delegation auditable from the transcript; only one
agent carries the "always execute via a dedicated sub-agent"
description clause (a deliberate A/B of whether prompt mandates
change routing).

**Adopt:** as the workshop's five-minute opener for the cost module —
same task, parent-executed vs delegated, token difference on screen.
It grounds our AGENTS.md cost rules in something attendees run.

## 5. `davidstanke/adk-agents` — the pattern catalogue

A sprawling fork (IT Bug Assistant, Django + ADK) that has
accumulated **four coexisting SDLC harnesses** — itself the teaching
material:

- **`.agents/` (Antigravity swarm):** Orchestrator → Architect → ≤3
  parallel Engineers → Reviewer; "Direct Injection Proxy Method"
  (inject the agent's verbatim md file into the subagent prompt;
  `Model: "inherit"`); design-before-code prohibited to skip; exact
  plan template with checkboxes.
- **`extensions/agent-farm` (packaged Gemini CLI extension) — the
  most liftable:** 8 agents + 14 skills; a **7-phase state machine
  driven entirely by GitHub issue labels** (`status: pm-review` →
  `needs-tpm` → … → `ready-to-merge`), phases 5–7 headless in CI; a
  `review:X` iteration counter escalating to `status: review-stuck`
  for humans; a `hold` label as circuit breaker halting all
  automation; category labels that reroute (`type: doc` bypasses
  QA/engineer); "Strict Delegation Mandate" for production work
  paired with "Interactive Refinement" *forbidding* delegation of
  refinement (black-box-assumption prevention); `.agentfarm/` scratch
  dir convention; per-agent tool allowlists and execution caps
  (`max_turns`, `timeout_mins`).
- **`.gemini/` (mode-based, no subagents):** DEFAULT/EXPLAIN/PLAN/
  IMPLEMENT/DEPLOY protocol blocks + slash commands — the "one agent,
  disciplined phases" contrast to teach against.
- **`conductor/` (TDD tracks):** per-track `spec.md`/`plan.md`;
  failing-tests-first hard gate; deviation = STOP and update
  `tech-stack.md` first; and **rationale committed via `git notes`**
  after every commit so the "why" outlives the session.

**Caution:** its root `.env` is committed with a real `DB_PASS` —
while its own docs claim `.env` is not committed, and lite-luncher's
credential-detector would have caught it. A live argument for
scanners in CI rather than in invoke-me-maybe skills. Strip before
any reuse.

## Conventions adopted wholesale (cross-cutting shortlist)

1. Spec-adversary grilling with a Decisions table; Decision IDs cited
   by every contract-test assertion (lab).
2. Lifecycle state in GitHub issue labels with an iteration counter
   and a `hold` circuit breaker, headless phases in CI (agent-farm).
3. Skills that mandate subagent execution and delegate to
   deterministic scripts; consolidate findings into one artifact
   (lite-luncher).
4. Dual-model review consensus with trusted posting steps and bot
   identities (predecessor repo).
5. Cost discipline as curriculum: delegation-economics opener
   (agy-subagents) + the measured rules in AGENTS.md.
6. Git notes for per-commit rationale (conductor) — candidate,
   pending fit with the review protocol.

---
Disposition (2026-09-01): context index created during planning;
sources: blog.md, runs/2026-09-01_research/{lab-research.md,
stanke-research.md} (local), predecessor repo docs. Feeds INTENT.md.
