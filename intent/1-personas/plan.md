# Plan: persona schema and canonical sources

**Issue:** #1 · committed before implementation per the lifecycle.

Order of work (implementation PR, branched from this one):

1. `personas/schema.json` — JSON Schema 2020-12 encoding D2–D9:
   required fields per `kind`, tier enum, capability string pattern,
   authority object shape, the persona/sub-agent field split.
2. `personas/skills/` — three files: `spec-adversary.md` (from the
   colleague lab's method, docs/CONTEXT.md §2), `review-protocol.md`
   (procedure + pointer to root REVIEW.md, lands via #3),
   `trusted-posting.md` (predecessor discipline: all workflow-driven
   GitHub writes go through vetted posting steps).
3. Six persona sources — role contracts distilled from INTENT.md's
   persona cast section; authority per that section's table of
   facts; tiers per the five-grade ladder.
4. Five sub-agent sources — role contracts from INTENT.md's
   sub-agent roster.
5. `docs/SPEC.md` upsert — `personas.sources` moves from *Agreed,
   not yet built* into Capabilities.

Verification (manual until #5, per D8):

- YAML parse check on all 11 sources.
- The vendor-leak grep from the spec's Acceptance section.
- Field-by-field spot check of two sources (one persona, one
  sub-agent) against `schema.json`.

Merge order: this planning PR first, then the implementation PR
(stacked on this branch), then #2's config PR (stacked on the
implementation branch — it reads the schema's field names).
