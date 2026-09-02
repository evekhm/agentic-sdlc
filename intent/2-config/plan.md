# Plan: deployment bindings (config/)

**Issue:** #2 · single PR (bootstrap compression, see spec.md).

1. `config/model_tiers.yaml` — claude-code and antigravity columns
   for the five tiers, from the verified bindings in CLAUDE.md and
   GEMINI.md (including the sonnet-alias trap note).
2. `config/deployments.yaml` — six pins (reviewers on different
   families: argus→claude-code, atlas→antigravity) + the
   `distinct_model_families` constraint entry.
3. `config/tools.yaml` — the seven capabilities used by #1's sources
   mapped for both harnesses; `ask_user` demonstrates the optional→
   fallback path (no native tool on antigravity).
4. `docs/SPEC.md` — upsert `config.bindings` into Capabilities.

Verification: YAML parse; cross-check every persona pinned and every
capability mapped (script in the run folder); reviewer-family check
by inspection of model_tiers.yaml.
