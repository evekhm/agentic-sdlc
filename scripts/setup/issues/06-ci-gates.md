Title: Rung 2: CI gates — drift, sanitization, spec check
Labels: bootstrap
Depends: compiler
---
The standards in AGENTS.md become mechanical:

- **Drift check** — recompile in CI and fail on any diff: a
  hand-edited compiled target cannot merge.
- **Sanitization scanners** — deterministic scripts (credentials,
  home paths, naming), run in CI on everything committed or
  compiled. In CI, not invoke-me-maybe skills: adk-agents ships a
  committed `.env` password *alongside* an unused credential-scanner
  skill (docs/CONTEXT.md §5) — that is the argument.
- **Spec check** — port `scripts/ci/spec_check.sh` + workflow from
  the predecessor: a PR touching behavior-bearing paths must touch
  `docs/SPEC.md` or carry the `Spec-impact: none — <reason>` marker.

**Done when:** each gate demonstrably fails a deliberately bad PR
(one per gate, closed unmerged as evidence) and passes a good one.

**Depends on:** {{compiler}} for the drift gate; the sanitization and
spec-check gates may land first within this issue.
