# Intent: persona schema and canonical sources

**Issue:** #1 · **Author:** Athena (wizard-of-Oz: presenter-driven
session) · **Status:** accepted on merge of this PR

## Problem

The system's actors exist only as prose in INTENT.md. Nothing
machine-readable defines who the personas are, what they may do,
which tier they think at, or which tools they may touch — so nothing
can be compiled (#5), enforced (#6), or automated (#8–#11). Every
downstream rung is blocked on this definition existing in one
canonical, vendor-agnostic form.

## Proposed outcome

A `personas/` directory holding one canonical YAML source per actor —
six personas, five sub-agents — plus shared protocol text in
`personas/skills/` and a machine schema that validates all of it.
Vendor-agnostic throughout: semantic tiers and abstract capabilities
only; models and tool names are `config/` facts (#2). The compiler
(#5) consumes these sources unchanged.

## Affected users and systems

- The compiler (#5) — direct consumer; its emitters read these files.
- CI (#6) — validates sources against the schema and greps for
  vendor leakage.
- Every automation rung (#8–#11) — runs what these files define.
- Presenter/attendees — `personas/` is the workshop's teaching
  artifact for "one source, many harnesses".

## Constraints

- No vendor model IDs, harness names, or tool names in any source
  (AGENTS.md tier rule; INTENT.md pillar 2).
- No secrets, token values, or local paths; token references by
  secret NAME only (INTENT.md pillar 5).
- Authority is declared here but enforced mechanically elsewhere —
  the schema must not pretend prompts are enforcement.
- No duplication: protocols shared by two personas live once in
  `personas/skills/`; root docs (REVIEW.md) are referenced, never
  restated.

## Open questions

None — resolved into the Decisions table of [spec.md](spec.md).
