# Reference: The AI-Native SDLC Playbook

Source: <https://claude.com/blog/the-ai-native-sdlc-playbook>
(fetched 2026-09-01). This is the flow the workshop demonstrates.
This file is the distilled reference we design against; on any doubt
the article wins.

## Core thesis

Code is no longer the bottleneck — agents write code fast, but the
human-speed stages around building (planning, review, deployment,
governance) haven't kept pace. Rebuild the SDLC as a **loop**, not a
line, with AI embedded at every point. **A stage ends by committing
an artifact, and that commit initiates the next stage.** The chain of
commits is the audit trail: who asked for what, what the agent
produced, who approved it.

## The six stages

### 1. Plan → `intent.md`

- An idea enters via a person, a ticket, or an incident alert. The
  originator (often a non-engineer) brainstorms with Claude in plain
  language; Claude asks analyst-style questions about scope, users,
  constraints, and success criteria, then writes the result to the
  org's template (encodable as a skill).
- Non-engineers work in claude.ai or Cowork; a GitHub connector lets
  Claude commit the markdown on their behalf — they never touch git.
- **Location:** a shared, version-controlled home the product owner
  watches. For a single product, "the simplest home is an `intent/`
  folder in the product repo" — keeps the artifact chain next to the
  code derived from it. A dedicated intent repo only pays off when
  intent spans many repositories.
- Template sections: Problem, Proposed outcome, Affected users and
  systems, Constraints, Open questions — plus author/status line.
- **Gate:** the product owner reviews and corrects the agent-written
  intent before commit; accept/reject is recorded as the merge or the
  closing review. Metric: intent survival rate.

### 2. Design → `spec.md`

- An **accepted intent.md triggers** the requirements/design pass.
  Claude converts intent → spec, constrained by organizational
  **skills** (brand, security, compliance, UX) so policy is applied
  while writing, not caught in later review. Contradicting policies
  must be flagged, not silently resolved.
- The product owner reviews the spec but doesn't write it; a
  technical lead is consulted for higher-risk changes. A human always
  makes the call.
- **Location:** "Commit `spec.md` alongside `intent.md`. The file
  pair records what was asked for and what was decided."
- Automation ladder: run by hand → org-level slash command →
  non-interactive job that fires on the intent-acceptance merge and
  opens spec.md as a PR.
- The spec, the prompt that produced it, and the skill versions in
  force are all logged in version control.
- **Gate:** accepting the spec starts plan mode. Metric: rework =
  spec.md commits dated after the first plan.md commit for the same
  change.

### 3. Build → `plan.md` + diff

- Engineer starts Claude Code in **plan mode** with intent.md +
  spec.md; the plan names the files that change, the order of work,
  and the tests that prove it. Iterate until an uninvolved engineer
  could implement from the plan alone.
- **The approved plan is committed as `plan.md` BEFORE code is
  written**; the later PR review checks the eventual diff against
  it. If implementation deviates, update plan.md in the same commit
  (optionally hook-enforced).
- Practices: `CLAUDE.md` as versioned institutional knowledge; skills
  for policy, **hooks as deterministic guardrails behind advisory
  skills**; auto-accept mode once guardrails mature; parallel
  sessions in git worktrees; subagents (verifier, simplifier,
  researcher) — the engineer shifts to orchestration.

### 4. Test

- Every session verifies its own work (tests, builds, screenshot
  diffs) before humans see it. For bug fixes: write the failing test
  first; hooks block agents from editing test files.
- **Continuous evals in CI** regression-test the agent configuration
  itself (`CLAUDE.md`, skills, hooks) whenever it changes; production
  incidents become permanent evals. Eval suites live in `evals/`.

### 5. Deploy

- Claude both gives and receives PR reviews using a repo-root
  **`REVIEW.md`** policy: bug, security, and compliance passes with
  severity ranking. Humans judge intent and risk; agents never have a
  path to main (branch protection + human code-owner approval).
- Hooks become human-approval gates (e.g. production deploys require
  named release authorization). Claude runs non-interactively in CI
  (`claude -p`) for triage, changelogs, fixes; deployment exposed via
  MCP; autonomy tiered by environment. **The agent acts up to the
  production gate, never past it.**

### 6. Maintain → new `intent.md`

- Deterministic scripts watch metrics against control bands
  (`bands.yaml`) and invoke Claude on breaches with tiered response:
  log at 1σ, diagnose read-only at 2σ, propose PR/runbook at 3σ.
- Findings become new intent.md files — **closing the loop**. Plus
  scheduled security scans and a Slack first-responder.

## Artifact chain summary

```text
issue/idea/incident
  → intent/<change>/intent.md      (PO accepts = merge)
  → spec.md alongside intent.md    (PO accepts = merge; skills constrain)
  → plan.md committed before code  (plan-mode approval)
  → diff + tests                   (session self-verifies)
  → PR + REVIEW.md findings        (human merges; agents never reach main)
  → deploy up to the prod gate     (hook-gated human authorization)
  → control-band breach            (new intent.md — loop closes)
```

Named files/paths in the article: `intent.md`, `spec.md`, `plan.md`,
`CLAUDE.md`, `REVIEW.md`, `intent/`, `.claude/skills/<name>/SKILL.md`,
`.claude/agents/*.md`, `.claude/settings.json`, `.claude/hooks/`,
`evals/`, `bands.yaml`.

## Notable: what the article does NOT define

- **No living system-wide spec.** The article's spec.md is per-change
  only; persistent knowledge lives in CLAUDE.md, skills, and
  REVIEW.md. Our repo adds the predecessor's living `SPEC.md`
  (current-state truth, upserted by every behavior-changing PR) on
  top of the per-change chain — the two are complementary: the
  intent/spec/plan triple is the *change record*, SPEC.md is the
  *current state*.
- No multi-harness / vendor-neutral persona story (it is Claude-only
  by construction) — our harness-agnostic compilation layer is
  additive.
- No multi-model review consensus — our dual-reviewer (Argus/Atlas)
  protocol is additive.

## Governance thread

Every play specifies enforcement, evidence, logging, and approvers.
Managed settings (permissions, sandboxing, credential denial, plugin
allowlists) are enforced centrally. Leading/lagging metrics per stage
come from git and PR metadata. Humans remain accountable for judgment
calls throughout.
