Title: Decision: label taxonomy for the lifecycle state machine
Labels: bootstrap
Depends:
---
One taxonomy must win before any workflow exists (INTENT.md, open
question 4): adopt agent-farm's `status:*` state machine names
verbatim (with its `review:N` iteration counter and
`status:review-stuck` escalation), align with the predecessor's
`argus:*` / `review:*` labels, or define a merged set.

Whatever wins must cover: lifecycle stage per issue, the session
claim (`in-progress`), the `hold` circuit breaker, `blocked`, and
`intent:new` intake.

**Done when:** the decision is recorded as a comment here, INTENT.md's
open question 4 is closed by PR, and the labels exist in the repo
(extend `scripts/setup/bootstrap_tracker.sh` so provisioning stays
idempotent and re-runnable).

**Depends on:** nothing — claimable any time; blocks Rung 3.

### `deep-review`
Deep-review grant (#5319E7): brings Argus into review before code gate (e.g. for design, spec, or multi-component reviews). Applied via `post.sh --add-label deep-review`.
