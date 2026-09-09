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
claim (`in-progress`), the `hold` circuit breaker, `blocked`,
`intent:new` intake, and `intake:auto` (opt-in for automated first-hop poller intake).

**Done when:** the decision is recorded as a comment here, INTENT.md's
open question 4 is closed by PR, and the labels exist in the repo
(extend `scripts/setup/bootstrap_tracker.sh` so provisioning stays
idempotent and re-runnable).

**Depends on:** nothing — claimable any time; blocks Rung 3.
