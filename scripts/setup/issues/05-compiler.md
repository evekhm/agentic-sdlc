Title: Rung 2: sync_agents.py — compile personas to harness targets
Labels: bootstrap
Depends: personas config
---
One build from `personas/` + `config/` to every target:

- Claude Code: `.claude/agents/<name>.md`
- Antigravity: `.agents/agents/<name>/{agent.json,config.yaml,instructions.md}`
- IDE targets (compiled and CI-validated, not demoed)
- AGENTS.md stays canonical; CLAUDE.md/GEMINI.md stay thin adapters.

Capability fallbacks are generated, not hand-written (the colleague
lab's SKILL.md hand-writes its own — docs/CONTEXT.md §2 explains why
that is the anti-pattern). Compilation is deterministic: running the
build twice yields a zero diff.

**Roundtrip validation:** one command takes a new persona source to
working configs on both live harnesses.

**Done when:** compiled outputs are committed, the rebuild is a
no-op, and a session can start *as* a compiled persona on each
harness — wizard-of-Oz ends here.

**Depends on:** {{personas}}, {{config}}.
