Title: Rung 3: Argus — event-driven review workflow
Labels: bootstrap
Depends: compiler review-policy label-taxonomy
---
Automate the most-tested predecessor artifact first. Port the Argus
review pipeline: PR-triggered Actions workflow, WIF auth to the model
runtime, budget guards, and all GitHub writes through the trusted
posting step (`scripts/ci/argus_post_review.sh` pattern). Provisioning
stays idempotent (`argus_setup.sh` is the template).

One difference from the predecessor: Argus's instructions arrive
**compiled** from `personas/argus` — never hand-written into the
workflow.

**Done when:** a real PR in this repo receives a protocol-v2 review
posted by `evekhm-argus-app[bot]` through the trusted step, with severity
tiers and finding IDs.

**Depends on:** {{compiler}}, {{review-policy}}, {{label-taxonomy}}.
