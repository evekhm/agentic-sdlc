Title: Rung 1: config/ — model tiers, deployment pins, tools
Labels: bootstrap
Depends: personas
---
The three files that keep vendor facts out of persona sources:

- `config/model_tiers.yaml` — the five-tier semantic ladder
  (FAST / MECHANICAL / IMPLEMENTATION / REVIEW / FRONTIER, per
  AGENTS.md) bound to concrete models per harness.
- `config/deployments.yaml` — persona → harness pins, and the
  deployment rule that the two reviewers resolve to **different
  model families**. Swapping a harness must be an edit here, never
  in `personas/`.
- `config/tools.yaml` — MCP-first tool map with harness-native
  fallbacks.

**Done when:** merged via the lifecycle; CLAUDE.md and GEMINI.md tier
sections point at the config instead of duplicating it; the
reviewer family-difference rule is expressed here and nowhere in
persona sources.

**Depends on:** {{personas}} — the schema fixes what a persona may
reference.
