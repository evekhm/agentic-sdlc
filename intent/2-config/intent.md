# Intent: deployment bindings (config/)

**Issue:** #2 · **Status:** accepted on merge of this PR

## Problem

Persona sources are deliberately vendor-agnostic (#1, D3/D4): they
name semantic tiers and abstract capabilities. Nothing yet says which
harness runs each persona, which model backs each tier on each
harness, or which concrete tools realize each capability — so the
compiler (#5) has nothing to resolve against and "swap the vendor by
editing pins, not personas" (INTENT.md) is not yet demonstrable.

## Proposed outcome

A `config/` directory that is the ONLY place vendor names appear:
`model_tiers.yaml` (tier→model per harness), `deployments.yaml`
(persona→harness pins + the distinct-model-families reviewer
constraint), `tools.yaml` (capability→tool per harness, with
generated-fallback text for optional capabilities).

## Affected users and systems

The compiler (#5) resolves against all three files; CI (#6) enforces
the reviewer-family constraint and vendor containment; presenters
edit pins live in the workshop's "one persona, every harness" act.

## Constraints

- Vendor names appear here and nowhere else in canonical sources.
- Deployment pins carry the facts personas must never state
  (which family backs which reviewer).
- Model IDs must be ones verified enabled on the actual deployments.

## Open questions

None — resolved in [spec.md](spec.md).
