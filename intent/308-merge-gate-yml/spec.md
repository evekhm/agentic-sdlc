# Spec: Per-Pull-Request Concurrency for Merge Gate and Recorder Isolation

**Issue:** #308 · **Status:** Approved (approval = merge of this PR) · **Author:** athena (`evekhm-athena-app[bot]`) · **Open questions:** none

## What is being built

This specification resolves issue #308 by eliminating cross-pull-request concurrency cancellations in `.github/workflows/merge-gate.yml`. 

Previously, both mutating jobs (`record` and `gate`) declared a static, repository-wide concurrency group:
```yaml
concurrency:
  group: merge-gate
  cancel-in-progress: false
```
Under GitHub Actions concurrency semantics with `cancel-in-progress: false`, at most one running job and at most one pending job are permitted in a concurrency group. When burst traffic occurs across multiple active pull requests (e.g. concurrent review rounds across PRs #304, #305, #306, and #307), an incoming event for PR B queued into the shared group and cancelled any pending run for PR A. Because `review_recorder.sh` is event-driven, the cancelled run for PR A was never re-attempted, leaving PR A's consensus ledger permanently missing review verdicts unless a human intervened. Under autonomous merge (#298), this silently stalled merge progression.

This change:
1. Elevates `concurrency:` to the workflow level in `.github/workflows/merge-gate.yml`, scoped per pull request:
   `group: merge-gate-${{ github.event.issue.number || github.event.check_suite.pull_requests[0].number || github.event.inputs.pull_request || github.run_id }}` with `cancel-in-progress: false`.
2. Removes individual job-level `concurrency:` blocks from `record` and `gate`, ensuring atomic, sequential execution of consensus recording followed immediately by merge gate evaluation for that pull request without mid-pipeline preemption or inter-job race conditions.
3. Removes the unresolvable `status` trigger from `merge-gate.yml` (all CI gates emit CheckRuns that fire `check_suite`; `status` webhook payloads lack pull request numbers and cannot be resolved in workflow expressions).
4. Adds pre-runner filtering in job `if:` conditions to immediately skip `check_suite` events on commits without open pull requests (such as pushes directly to `main`), saving runner minutes and queue contention.
5. Preserves permissive PR `issue_comment` triggering so operators and verifiers can repair or re-trigger pull requests via comments.
6. Adds hermetic contract tests in `scripts/ci/tests/merge_gate_test.sh` asserting workflow concurrency configuration, trigger cleanliness, and event isolation.

### Manifest of Files Touched by the Implementation Rung

- `.github/workflows/merge-gate.yml`: Workflow-level concurrency scoping, removal of job-level concurrency, removal of `status` trigger, pre-runner filtering in `record` and `gate`, and simplified target resolution.
- `scripts/ci/tests/merge_gate_test.sh`: Hermetic contract test suite validating workflow concurrency, triggers, and payload extraction.
- `docs/SPEC.md`: Living spec update describing workflow-level per-PR concurrency and `status` removal.
- `intent/308-merge-gate-yml/plan.md`: Ordered implementation plan authored by Daedalus.

### Manifest of Files Touched by this PR (Athena)

- `intent/308-merge-gate-yml/spec.md`: This specification.
- `intent/308-merge-gate-yml/intent.md`: Status update to Accepted.

### Forbidden Files (Untouched)

- `.github/workflows/lifecycle.yml`
- `.github/workflows/merge-gate-evaluate.yml`
- `scripts/ci/merge_gate.sh`
- `scripts/ci/review_recorder.sh`
- `scripts/ci/review_recorder.py`
- `personas/**`

## Decisions

| ID | Decision | Rationale |
|---|---|---|
| **D1** | **Workflow-level concurrency scoped per pull request.** Declare `concurrency:` once at the root of `.github/workflows/merge-gate.yml`, scoped to the pull request number: `group: merge-gate-${{ github.event.issue.number \|\| github.event.check_suite.pull_requests[0].number \|\| github.event.inputs.pull_request \|\| github.run_id }}`. Remove job-level `concurrency:` from both `record` and `gate`. | Cross-PR cancellations occur because different pull requests contend for a single global queue. Scoping by PR number provides total isolation between distinct PRs. Moving concurrency to the workflow level ensures that `record` and downstream `gate` run as an uninterrupted atomic sequence within the same workflow run, preventing a subsequent event from preempting `gate` after `record` finishes. |
| **D2** | **Intra-PR execution policy retains `cancel-in-progress: false`.** Workflow-level concurrency sets `cancel-in-progress: false`. | `cancel-in-progress: false` prevents in-flight `record` and `gate` executions from being cancelled mid-run while writing comments or executing `gh pr merge`. GitHub Actions permits one active run and queues at most one pending run. When the active run finishes, the queued run executes and observes the latest thread state. |
| **D3** | **Removal of `status` trigger.** Remove the `status:` trigger from `on:` in `.github/workflows/merge-gate.yml`. Remove the `STATUS_SHA` environment variable and `status)` case block in `record` and `gate`. | Webhook payloads for `status` events contain commit SHAs only and omit pull request numbers, making workflow expression interpolation impossible. Repository run history shows zero `status` events across hundreds of runs because all CI gates emit CheckRuns producing `check_suite` events. Removing `status` eliminates dead triggers cleanly. |
| **D4** | **Deterministic payload-based PR resolution and orphan fallback.** Concurrency group interpolation resolves the pull request number directly from event payloads: `github.event.issue.number` (for `issue_comment`), `github.event.check_suite.pull_requests[0].number` (for `check_suite`), `github.event.inputs.pull_request` (for `workflow_dispatch`), and `github.run_id` as the fallback. | Using `github.run_id` as the final fallback ensures that any unassociated run (such as an event without an attached PR) evaluates to an isolated, unique group key (`merge-gate-<run_id>`) that never collides with, blocks, or cancels any pull request queue. |
| **D5** | **Pre-runner filtering for non-PR events.** In `.github/workflows/merge-gate.yml`, both `record` and `gate` jobs enforce pre-runner conditions: `record` requires `github.event_name == 'workflow_dispatch' \|\| (github.event_name == 'issue_comment' && github.event.issue.pull_request) \|\| (github.event_name == 'check_suite' && github.event.check_suite.pull_requests[0].number)`. `gate` requires `${{ always() && !cancelled() && (github.event_name == 'workflow_dispatch' \|\| (github.event_name == 'issue_comment' && github.event.issue.pull_request) \|\| (github.event_name == 'check_suite' && github.event.check_suite.pull_requests[0].number)) }}`. | Check suites completed on non-PR commits (such as direct pushes to `main`) emit empty `check_suite.pull_requests` arrays. Skipping them in job `if:` conditions prevents runner VM allocation, eliminating wasted Actions compute and runner slot consumption. Non-PR issue comments are similarly skipped pre-runner. |
| **D6** | **Permissive PR `issue_comment` triggering.** Comments on pull requests (`github.event.issue.pull_request`) remain eligible to trigger `merge-gate.yml` without filtering on comment body strings (such as `review-verdict:`). | Cross-PR interference is completely eliminated by per-PR scoping (D1). Retaining permissive PR comment triggering ensures that operator repair comments, verifier notes, and manual re-triggers remain effective on pull request threads without requiring manual workflow dispatch. |
| **D7** | **Deterministic target resolution in job steps.** In both `record` and `gate` steps, derive `TARGET` directly from `$CS_PR` (for `check_suite`), `$ISSUE_NUMBER` (for `issue_comment`), or `$DISPATCH_PR` (for `workflow_dispatch`). Drop `gh api .../commits/$CS_SHA/pulls` API fallbacks and retain defensive check `if [ -z "$TARGET" ] \|\| [ "$TARGET" = "null" ]; then exit 0; fi`. | Because D3 removes `status` and D5 skips events without a resolvable PR number, target resolution in bash is deterministic from environment variables already populated from the webhook payload without extra API calls. |
| **D8** | **Hermetic contract testing in `merge_gate_test.sh`.** Add contract tests to `scripts/ci/tests/merge_gate_test.sh` asserting: (1) workflow-level `concurrency.group` contains the per-PR expression, (2) `cancel-in-progress` is `false`, (3) neither `record` nor `gate` declares job-level `concurrency`, (4) `status` is absent from `on:`, (5) job `if:` conditions enforce PR guards, and (6) simulated payload evaluations yield distinct concurrency keys for distinct PRs and run-isolated keys for orphan events. | Hermetic contract tests prevent configuration drift and regression during future workflow edits without relying on live GitHub Actions infrastructure. |
| **D9** | **Living spec update scope.** `docs/SPEC.md` line 1114 is amended in the implementation PR to state that mutating jobs share workflow-level concurrency scoped per pull request (`merge-gate-${{ pr }}`), that `status` is removed from triggers, and that check suites without PRs skip pre-runner. Athena touches only `intent/308-merge-gate-yml/**` at this stage. | Enforces AGENTS.md living spec maintenance rules and respects Athena's path authority bounds (`intent/**`). |

## Acceptance

- **AT-1 (Workflow Concurrency Scope):** `.github/workflows/merge-gate.yml` declares top-level `concurrency:` with `group: merge-gate-${{ github.event.issue.number || github.event.check_suite.pull_requests[0].number || github.event.inputs.pull_request || github.run_id }}` (derives from D1, D4).
- **AT-2 (Cancellation Disabled):** `.github/workflows/merge-gate.yml` sets top-level `cancel-in-progress: false` (derives from D2).
- **AT-3 (Job-Level Concurrency Removed):** Neither `record` nor `gate` in `.github/workflows/merge-gate.yml` contains a `concurrency:` block (derives from D1).
- **AT-4 (Status Trigger Removed):** `.github/workflows/merge-gate.yml` contains no `status:` entry under `on:` (derives from D3).
- **AT-5 (Check Suite and Issue Comment Retained):** `.github/workflows/merge-gate.yml` triggers on `check_suite` (types: `[completed]`), `issue_comment` (types: `[created]`), and `workflow_dispatch` (derives from D3, D5).
- **AT-6 (Record Job Pre-Runner Guard):** `jobs.record.if` evaluates to true only for `workflow_dispatch`, PR `issue_comment`, and `check_suite` with a non-empty `pull_requests[0].number` (derives from D5).
- **AT-7 (Gate Job Pre-Runner Guard):** `jobs.gate.if` evaluates to true only when `record` was not cancelled and the event is a `workflow_dispatch`, PR `issue_comment`, or `check_suite` with a non-empty `pull_requests[0].number` (derives from D5).
- **AT-8 (Permissive PR Comments):** An `issue_comment` on a pull request triggers the workflow regardless of whether the body contains `review-verdict:` or other specific keywords (derives from D6).
- **AT-9 (Orphan Fallback Isolation):** An event payload lacking an associated PR evaluates to `merge-gate-<run_id>`, differing from any `merge-gate-<pr_number>` (derives from D4).
- **AT-10 (Simplified Target Resolution):** In both `record` and `gate` steps, `TARGET` is resolved directly from `CS_PR`, `ISSUE_NUMBER`, and `DISPATCH_PR` without calling `gh api .../commits/$CS_SHA/pulls` (derives from D7).
- **AT-11 (Hermetic Contract Test Pass):** `bash scripts/ci/tests/merge_gate_test.sh` executes all test scenarios (including MG-37 through MG-41) and exits 0 (derives from D8).
- **AT-12 (Living Spec Sync in Implement Stage):** `docs/SPEC.md` line 1114 is updated to describe workflow-level per-PR concurrency `merge-gate-${{ pr }}` and the removal of `status` (derives from D9).

## Open questions

none
