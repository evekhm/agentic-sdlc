Title: Rung 1: persona schema and canonical sources (personas/)
Labels: bootstrap
Depends:
---
The first change driven through the full lifecycle by hand — this
issue exists to prove the artifact chain as much as to produce the
personas.

**Process (the lifecycle, wizard-of-Oz):**
`intent/<this-issue>-personas/intent.md` PR (merge = accepted) →
`spec.md` grilled by the spec-adversary method until Open questions
is empty, resolutions in the Decisions table (merge = approved) →
`plan.md` committed before code → implementation PR.

**Deliverables:**
- The persona schema (format is a spec decision — record it as a
  Decision row).
- Six persona sources: athena, daedalus, odyssey, argus, atlas,
  cassandra — role, protocol, authority, semantic tier, identity.
- Five sub-agent sources flagged `subagent: true`: mechanic, coder,
  contract-writer, scanner, explorer.
- The implementation PR seeds `docs/SPEC.md` with its first entries —
  the living spec starts here, per the upsert rule in AGENTS.md.

**Done when:** implementation PR merged; `docs/SPEC.md` exists; a
grep for vendor model IDs in `personas/` finds nothing.

**Sources:** INTENT.md ("The persona cast", "Harness-agnostic
architecture"); predecessor repo `agentic-experiments-lab`
(`.agents/agents/mechanic.md`, `.agents/agents/coder.md`);
docs/CONTEXT.md §2 (contract-writer), §3 (scanner pattern).

**Depends on:** nothing — claimable immediately.
