# Intent: Per-Pull-Request Concurrency for Merge Gate and Recorder Cancellation Isolation

**Issue:** #308 · **Author:** athena (`evekhm-athena-app[bot]`) · **Status:** Draft

## Problem

A concurrency group misconfiguration in `.github/workflows/merge-gate.yml` causes the Themis consensus recorder to permanently drop review updates during concurrent wave traffic, leaving pull requests in an unmerged or stale state.

### 1. Global Concurrency Cancels Pending Recorder Runs Across Pull Requests

In `.github/workflows/merge-gate.yml`, both mutating jobs (`record` at line 42 and `gate` at line 106) declare:

```yaml
concurrency:
  group: merge-gate
  cancel-in-progress: false
```

GitHub Actions enforces concurrency by keeping at most one running job and at most one pending job per concurrency group. When a new run arrives in a group that already has a pending run queued, GitHub cancels the older pending run.

Because `merge-gate` is defined as a static literal without scoping, all events across all pull requests in the repository contend for the exact same queue and execution slot. When multiple pull requests receive events in close succession (for example, during wave review rounds or automated verifications across PRs #304, #305, #306, and #307), a run triggered for PR B enters the queue and immediately cancels the pending run for PR A.

### 2. Themis Consensuses Miss Reviews Permanently

Because `scripts/ci/review_recorder.sh` is an event-driven worker rather than a scheduled polling daemon, a cancelled run is never automatically retried. If PR A's pending run is cancelled, PR A's consensus ledger comment remains stuck at its prior state indefinitely.

This failure was observed concretely on PR #304 (for issue #291):
- **18:01:20Z**: Atlas posted its review.
- **18:01:36Z**: The recorder ran on Atlas's comment and posted the consensus ledger.
- **18:01:53Z**: Argus posted its review.
- **18:01:56Z**: Argus's comment triggered a `merge-gate.yml` `issue_comment` run (`34386529610`).
- Because traffic arrived from sibling wave PRs, run `34386529610` was marked `cancelled` by GitHub.

No subsequent event occurred for PR #304, leaving its consensus ledger showing only Atlas's review marker (`<!-- reviewed-head:atlas:8b02eed -->`), zero Argus markers, zero finding rows, and the message `_No findings recorded._` — despite both reviews existing on the thread. The ledger remained inaccurate for 11 minutes until an unrelated comment was posted by the verifier at 18:12:43Z.

Between 17:57Z and 18:19Z, six separate `issue_comment` runs were cancelled (`34386501857`, `34386529610`, `34386554891`, `34386740357`, `34386755467`, `34387067469`, `34387097859`), confirming systematic loss under normal multi-agent activity.

### 3. Loop Stalling Under Autonomous Merge

Under autonomous merge (#298), Themis evaluates merge readiness and merges CLEAN PRs without human intervention. The gate requires full reviewer consensus before merging. If a pull request's final review comment has its recorder run cancelled, the merge gate evaluates consensus as missing and declines to merge. Under automated VM poller operation (#251, PR #294), no interactive human comments are posted, causing the autonomous loop to stall indefinitely on completed, passing pull requests.

## Proposed outcome

1. **Scope Concurrency Per Pull Request**:
   - Scope the concurrency group in `.github/workflows/merge-gate.yml` per pull request (e.g. `group: merge-gate-${{ <pr-key> }}`).
   - Isolate execution and queue slots across distinct pull requests so that events for PR B never cancel or block runs for PR A.
   - Retain mutual exclusion for the *same* pull request: two recorder runs for the same PR must never execute simultaneously.

2. **Deterministic Payload-Based PR Resolution**:
   - Resolve the pull request number directly from event payloads in the workflow concurrency expression before job execution starts:
     - `issue_comment`: `github.event.issue.number` (guarded by `github.event.issue.pull_request`).
     - `workflow_dispatch`: `github.event.inputs.pull_request`.
     - `check_suite`: `github.event.check_suite.pull_requests[0].number`.
   - Remove the unresolvable, dead-weight `status` trigger from `.github/workflows/merge-gate.yml`. Verification shows zero `status` events across hundreds of runs (all CI checks are CheckRuns that emit `check_suite`). Removing `status` eliminates the single trigger whose payload contains only a commit SHA and lacks a pull request number.
   - Provide a safe fallback or early skip for `check_suite` events on non-PR commits where `check_suite.pull_requests` is empty, ensuring they never evaluate to an invalid or shared key that could collide with real PRs.

3. **Reduce High-Volume Non-Review Trigger Events**:
   - Filter `issue_comment` events so that `record` and `gate` only execute when the comment is on a pull request and the body contains review-relevant markers (such as `review-verdict:` or explicit merge gate directives).
   - Casual discussion, claim comments, and handoff notes currently account for ~72% of all merge-gate workflow executions; filtering them reduces runner pressure, contention, and Actions spend.

4. **Verify Concurrency and Ledger Integrity**:
   - Add contract test cases (in `scripts/ci/tests/merge_gate_test.sh` or related suites) asserting:
     - Independent concurrency group evaluation across distinct pull requests.
     - Accurate payload extraction across all active triggers (`check_suite`, `issue_comment`, `workflow_dispatch`).
     - Safe handling of check suites without associated pull requests.

## Affected users and systems

- **Autonomous Reviewers (`argus`, `atlas`)**: Review verdicts reliably reach the consensus ledger without being dropped by cross-PR concurrency.
- **Autonomous Merge Gate / Themis (`evekhm-themis-app[bot]`)**: Operates continuously without stalling due to silently dropped review records.
- **Workflows**:
  - `.github/workflows/merge-gate.yml`: Concurrency definitions, trigger list (`status` removal), and `issue_comment` filtering.
- **Scripts & Tests**:
  - `scripts/ci/tests/merge_gate_test.sh`: Contract test coverage for merge gate triggers and concurrency keys.
  - `scripts/ci/review_recorder.sh`: Consumed by `record`.
  - `scripts/ci/merge_gate.sh`: Consumed by `gate`.
- **Preceding & Related Changes**:
  - #298: Separated read-only evaluation into `.github/workflows/merge-gate-evaluate.yml`; this change applies to the remaining mutating jobs in `merge-gate.yml`.
  - #291: Recorder hold parity and circuit breaker.
  - #267: Severity-tiered review consensus and merge gate architecture.
  - #64: Autonomous loop lifecycle.

## Constraints

- **Single-PR Mutex**: Two recorder runs for the same pull request must never execute concurrently. Because `review_recorder.sh` inspects the comment thread to detect existing ledger comments, concurrent runs could both perceive no existing ledger and post duplicate `<!-- consensus-ledger:PR -->` comments.
- **Zero Cross-PR Cancellation**: A run or queue event on PR B must never cancel, displace, or invalidate an event on PR A.
- **Themis Isolation**: Credentials for Themis remain restricted to jobs declaring `environment: themis` on runs against default branch refs.
- **Idempotency Preservation**: The recorder's model of rebuilding complete consensus from the full comment list on every run must remain unchanged.
- **Spec Integrity**: Any changes to behavior-bearing workflow paths must be accompanied by updates to `docs/SPEC.md` during implementation per AGENTS.md.
- **Persona Role Discipline**: Athena delivers only `intent/308-merge-gate-yml/intent.md` at this stage. No workflow files, scripts, or plans are modified in this PR.

## Open questions

1. **Intra-PR Cancellation Policy (`cancel-in-progress: false` vs `true`)**:
   - Because `review_recorder.sh` is idempotent and parses the full comment thread, would setting `cancel-in-progress: true` within a PR's dedicated group be beneficial (cancelling an in-flight recorder if a newer verdict arrives), or should `cancel-in-progress: false` be preserved so in-flight runs complete cleanly and GitHub's queue naturally holds the latest pending run?
2. **Fallback for `check_suite` with Empty `pull_requests`**:
   - If a `check_suite: completed` event fires for a commit where `github.event.check_suite.pull_requests` is empty (e.g. pushes to non-PR branches or commits on main), what should the concurrency group evaluate to? Should job-level `if:` conditions skip the job entirely before concurrency evaluation, or should the group fall back to `merge-gate-orphan-${{ github.run_id }}` so unassociated runs never collide with any PR?
3. **Filtering `issue_comment` at Workflow vs Job Level**:
   - Should `issue_comment` filtering (e.g. checking for `<!-- review-verdict:` or `review-verdict:`) be applied in the workflow `if:` at the job level, or is an explicit list of markers needed to ensure verifier or human override comments can also trigger the recorder/gate if necessary?
4. **Relationship Between `record` and `gate` Concurrency**:
   - Currently, `gate` declares `needs: [record]` and runs in the same workflow. Should both jobs share the same PR-scoped group `merge-gate-${{ pr }}`, or does `gate` need a distinct group `merge-gate-eval-${{ pr }}`? When both share the same group in the same workflow run, sequential execution within the run is preserved without self-cancellation.
5. **Handling Multiple PRs Associated With a Single `check_suite`**:
   - While rare, a commit could theoretically be the head of more than one PR (`pull_requests` length > 1). Does the group expression `pull_requests[0].number` adequately cover all typical git workflows in this repository, or does the recorder need to loop over all associated PRs?
