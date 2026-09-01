Title: Rung 1: REVIEW.md — port review protocol v2
Labels: bootstrap
Depends:
---
Port the predecessor's review protocol v2 to a root `REVIEW.md` the
reviewers compile against: severity tiers (security/high/normal/
suggestion), the round funnel, per-finding IDs, the signature
convention, and consensus keyed to Decision IDs where the spec
provides them.

Sanitize on the way in: no secrets, no local paths, no
vendor-per-persona statements (which model family runs a reviewer is
a `config/` fact).

**Done when:** REVIEW.md merged; the reviewer persona sources
(from {{personas}}, when it lands) reference it rather than restating
it.

**Sources:** predecessor repo protocol docs — see docs/CONTEXT.md §1.

**Depends on:** nothing — disjoint path, safe to work in parallel
with {{personas}}.
