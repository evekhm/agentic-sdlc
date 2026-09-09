# Spec: Poller Fix-Round Queue Resolves PR to Issue for Multi-Rung Stage Verification

**Issue:** #337 · **Status:** Approved (approval = merge of this PR) · **Author:** athena (`evekhm-athena-app[bot]`) · **Open questions:** none

## What is being built

This specification resolves issue #337 by repairing the VM poller's fix-round queue (`scripts/placement/vm-local/poll.sh`) and dispatch handling (`scripts/ops/work.sh`) to support automated fix rounds across all builder rungs (spec PRs by Athena, plan PRs by Daedalus, and implement PRs by Odyssey).

In the current implementation:
1. `poll.sh` queries open pull requests with `--label status:in-review` and asserts that candidate PRs carry `status:in-review`. However, pull requests in this repository never carry `status:*` labels (the lifecycle state machine is maintained solely on the underlying tracking issue by `lifecycle_advance.sh`).
2. Even on the tracking issue, `status:in-review` is written only when an implementation PR merges, advancing the issue to the terminal review rung. While any PR is open and under review, its tracking issue carries the stage label corresponding to that rung:
   - Intent PR: issue carries `intent:new` or `status:planning`
   - Spec PR: issue carries `status:spec`
   - Plan PR: issue carries `status:build`
   - Implement PR: issue carries `status:implementing`
3. As observed empirically on PR #335 (spec PR for issue #308), when Atlas posted a blocking `high` finding, `poll.sh` found 0 candidate PRs because of the non-existent `status:in-review` filter, leaving the PR blocked until manual operator intervention.
4. In `scripts/ops/work.sh:399`, `is_fix_round` detection required `[ "$status_labels" = "status:in-review" ]`, which similarly blocked non-implement PR fix rounds and caused branch/slug mismatches.
5. In `scripts/ci/tests/e2e_chain_test.sh`, tests AT-13, AT-20, and AT-21 used synthetic fixtures where PR objects carried artificial `status:in-review` labels, masking this bug in CI.

This specification:
1. Removes `--label status:in-review` from `poll.sh` section 2, querying all open repository pull requests with fields `number,title,labels,headRefName,isCrossRepository`.
2. Sources `scripts/ops/lib/github.sh` in `poll.sh` and defines a daemon-safe `die()` handler so unresolvable or malformed PRs do not terminate the long-running poller daemon.
3. Implements deferred PR-to-issue resolution: `poll.sh` checks the reviewer trigger predicate (blocking findings by Argus or Atlas) and consumption key first. Only when an unconsumed blocking review finding exists does `poll.sh` invoke `resolve_issue "$pr_num"`, eliminating redundant GitHub API requests on non-actionable PRs.
4. Enforces fail-closed tracking issue validation: the resolved tracking issue must be open (`state == "open"`), must not carry circuit breakers (`hold`, `blocked`, or `status:review-stuck`), and the PR itself must not carry `hold`.
5. Enforces strict stage-to-author alignment before dispatching:
   - `athena`: resolved issue must carry `intent:new`, `status:planning`, or `status:spec`.
   - `daedalus`: resolved issue must carry `status:build`.
   - `odyssey`: resolved issue must carry `status:implementing`.
   If the stage does not match the author persona, `poll.sh` logs a skip notice and does not dispatch.
6. Harmonizes `is_fix_round` in `scripts/ops/work.sh` so that any PR authored by a builder persona (`athena`, `daedalus`, `odyssey`) dispatched with `--as "$pr_head_author"` on an issue at the author's stage sets `is_fix_round=1`, preserving the PR's exact branch slug (`pr_head_slug`).
7. Updates contract tests AT-13, AT-20, and AT-21 in `scripts/ci/tests/e2e_chain_test.sh` to remove `status:in-review` from PR fixtures, provide realistic tracking issue fixtures, and add multi-rung test coverage for Athena (spec PR) and Daedalus (plan PR).
8. Updates the living specification (`docs/SPEC.md`).

### Manifest of Files Touched by this PR (Athena)

- `intent/337-poller-fix-round-queue/spec.md`: This specification.
- `intent/337-poller-fix-round-queue/intent.md`: Status update to Accepted.

### Manifest of Files Touched by the Implementation Rung (Daedalus / Odyssey)

- `scripts/placement/vm-local/poll.sh`: Query open PRs without status filter, source `github.sh`, define daemon-safe `die()`, deferred `resolve_issue`, issue validation, stage alignment.
- `scripts/ops/work.sh`: Generalize `is_fix_round` to all builder personas matching PR head author and issue stage.
- `scripts/ci/tests/e2e_chain_test.sh`: Update AT-13, AT-20, AT-21 fixtures (no status labels on PRs) and add multi-rung fix-round test coverage.
- `docs/SPEC.md`: Living spec update describing PR-to-issue resolution for poller fix-round queue and multi-rung fix-round support.
- `intent/337-poller-fix-round-queue/plan.md`: Build plan authored by Daedalus.

### Forbidden Files (Untouched)

- `scripts/ci/merge_gate.sh`
- `scripts/ci/escalate.sh`
- `.github/workflows/**`
- `personas/**`

## Decisions

| ID | Decision | Rationale |
|---|---|---|
| **D1** | **Amendment target and supersession structure.** This specification forms the normative design for issue #337 and amends the merged specifications of #251 (`intent/251-e2e-chain/spec.md`), #288 (`intent/288-d16-vm-poller/spec.md`), and #295 (`intent/295-poller-intake-gate/spec.md`). Specifically: Decision D2 of #251 and Decision D6 of #295 are amended to remove the pull request label requirement `status:in-review` and replace it with PR-to-issue resolution via `resolve_issue()`; Decision D8 of #251 is updated to admit the manifest of files touched by this implementation; and Decision D9 of #36 (`intent/36-dispatch/spec.md`) / Decision D1 of #207 (`intent/207-review-mutex/spec.md`) is clarified regarding `is_fix_round` stage matching across all builder rungs. | Formal supersession preserves traceable lineage across specifications while defining unambiguous, binding rules for the autonomous fix-round subsystem. |
| **D2** | **Query open pull requests without status label filter.** In `scripts/placement/vm-local/poll.sh` section 2, remove `--label status:in-review` from the `gh pr list` invocation and remove the `has_in_review` check at line 145. Query open pull requests using `gh pr list --state open --json number,title,labels,headRefName,isCrossRepository` (with `--limit 300` to prevent default truncation). PRs with `isCrossRepository == true` or missing `headRefName` are skipped. Author persona is extracted as `author_persona="${head_ref%%/*}"` and must match one of the closed builder persona set `athena\|daedalus\|odyssey`. | Pull requests in this repository never carry `status:*` labels. Omitting the label filter allows `poll.sh` to discover candidate pull requests authored by all builder personas across all development rungs. |
| **D3** | **Deferred PR-to-issue resolution with daemon-safe error handling.** Source `scripts/ops/lib/github.sh` in `poll.sh`. In `poll.sh`, define a daemon-safe error handler `die() { echo "poll.sh: $*" >&2; return 1; }` prior to sourcing `github.sh`, ensuring that unresolvable PRs or unexpected errors emit a warning and return non-zero rather than terminating the supervisor loop. PR-to-issue resolution via `resolve_issue "$pr_num"` is deferred until AFTER the reviewer trigger predicate (Argus/Atlas blocking findings) and consumption key (`key_file`) checks pass. If `resolve_issue "$pr_num"` fails (returns non-zero), `poll.sh` logs `poll.sh: skipping PR #$pr_num (could not resolve to tracking issue)` and continues to the next candidate PR without creating `key_file`. | Deferring `resolve_issue` until after the reviewer trigger check avoids redundant API queries across non-actionable PRs during 30-second polling ticks. Daemon-safe `die()` prevents malformed PR descriptions (e.g. closing multiple issues) from crashing the long-running poller daemon. |
| **D4** | **Fail-closed tracking issue state validation.** Before dispatching a fix round, `poll.sh` validates the state of the resolved tracking issue `$ISSUE`: (1) the issue must be open (`state == "open"` in `$ISSUE_JSON`); (2) the issue must not carry `hold`, `blocked`, or `status:review-stuck`; (3) the pull request itself must not carry `hold` (`PR_LABELS` / `has_label "hold"`). If any condition is violated, `poll.sh` logs the refusal reason (e.g. `poll.sh: skipping PR #$pr_num (issue #$ISSUE carries hold)`) and skips dispatch without creating `key_file`. | Circuit breakers on either the tracking issue or the pull request must stop autonomous dispatch fail-closed. Not creating `key_file` ensures that when an operator lifts the hold or unblocks the issue, the fix round fires on the subsequent tick without manual cache invalidation. |
| **D5** | **Strict stage-to-author alignment check before dispatch.** `poll.sh` verifies that the resolved tracking issue's current stage matches the PR author persona: (1) `athena`: issue carries `intent:new`, `status:planning`, or `status:spec`; (2) `daedalus`: issue carries `status:build`; (3) `odyssey`: issue carries `status:implementing`. If the issue stage does not match the author persona, `poll.sh` logs `poll.sh: skipping PR #$pr_num (issue #$ISSUE stage mismatch for $author_persona)` and skips dispatch without writing `key_file`. | Strict stage verification prevents the poller from repeatedly spawning doomed runner sessions for stale or out-of-sequence PRs whose issues have already advanced to another stage or persona. |
| **D6** | **Universal fix-round eligibility across all builder rungs.** All builder pull requests (intent PRs by Athena, spec PRs by Athena, plan PRs by Daedalus, and implement PRs by Odyssey) are eligible for automated fix rounds when an authorized reviewer (`evekhm-argus-app[bot]` or `evekhm-atlas-app[bot]`) posts blocking findings (`security` or `high` findings, or `review findings: blocking`). When triggered, `poll.sh` touches `key_file`, acquires `lock_file`, executes `"$RUN_SH" "$pr_num" --as "$author_persona"`, and clears `lock_file`. | Every stage of the autonomous software development lifecycle undergoes review by Argus and Atlas. Making fix rounds multi-rung closes the autonomous loop so that spec and plan PR defects are repaired by their authors without requiring human operator intervention. |
| **D7** | **Harmonization of `is_fix_round` in `scripts/ops/work.sh`.** In `scripts/ops/work.sh`, line 399 is updated so that `is_fix_round=1` is set whenever: `[ "$IS_PR" = "1" ] && [ -n "$AS" ] && [ -n "$pr_head_author" ] && [ "$AS" = "$pr_head_author" ] && [ -n "$PR_HEAD_REPO" ] && [ "$PR_HEAD_REPO" = "$GITHUB_REPO" ]`. If `status_labels == "status:in-review"` (legacy compatibility), `stage` is mapped to `implement` (or the persona's stage); otherwise, `stage` retains the stage already derived from the issue's labels (`design`, `build`, `implement`, or `plan`). At line 556, `if [ "${is_fix_round:-0}" -eq 1 ] && [ -n "$pr_head_slug" ]; then slug="$pr_head_slug"; fi` executes for all builder fix rounds, ensuring the branch and worktree accurately target the PR head ref `<author>/<n>-<pr_head_slug>`. | Eliminating the hardcoded `status:in-review` requirement from `work.sh:399` allows `work.sh` to dispatch fix rounds for Athena (spec PRs) and Daedalus (plan PRs) as well as Odyssey (implement PRs) while preserving exact branch slugs across all rungs. |
| **D8** | **Contract test modernization and multi-rung coverage in `e2e_chain_test.sh`.** In `scripts/ci/tests/e2e_chain_test.sh`: (1) AT-13 is updated so `issue-108.json` (PR fixture) contains no `status:*` labels, `issue-107.json` (issue fixture) carries `status:implementing`, and `repos_evekhm_agentic-sdlc_pulls_108.json` defines head ref `odyssey/107-fix`; (2) AT-20 and AT-21 are updated so `pr-list.json` and PR fixtures contain no `status:*` labels, and corresponding tracking issue fixtures (`issue-4241.json` at `status:implementing`) are provided; (3) test scenarios are added asserting fix-round dispatch for `athena` (spec PR on issue at `status:spec`) and `daedalus` (plan PR on issue at `status:build`), verifying that `run.sh` is invoked under `--as athena` and `--as daedalus` respectively. | Modernizing test fixtures to reflect real repository objects ensures tests run against realistic data shapes and verifies multi-rung fix-round functionality. |
| **D9** | **Living spec synchronization in `docs/SPEC.md`.** In `docs/SPEC.md ## Deployment status`, the fix-round queue documentation is updated to specify that `poll.sh` queries open pull requests without status label filters, resolves candidate PRs to tracking issues via `resolve_issue()`, validates issue state (`open`, no `hold`/`blocked`/`review-stuck`), verifies author persona stage alignment, and dispatches fix rounds across all builder rungs (`athena`, `daedalus`, `odyssey`). Athena touches only `intent/337-poller-fix-round-queue/**` at this stage; `docs/SPEC.md` is updated by Odyssey during the implement stage. | Enforces AGENTS.md living spec maintenance standards while respecting Athena's strict `intent/**` authority boundary. |
| **D10** | **Implementation scope boundary and file manifest.** The implementation pull request for #337 may touch: `scripts/placement/vm-local/poll.sh`, `scripts/ops/work.sh`, `scripts/ci/tests/e2e_chain_test.sh`, `docs/SPEC.md`, and `intent/337-poller-fix-round-queue/plan.md`. It may NOT touch `scripts/ci/merge_gate.sh`, `scripts/ci/escalate.sh`, `.github/workflows/**`, or `personas/**`. | Explicit boundaries prevent accidental regressions in merge gating, escalations, workflow definitions, and persona authority. |

## Acceptance

Every acceptance test assertion cites the Decision ID it derives from and is checkable without model calls:

- **AT-1 (Poller Candidate Discovery Without PR Status Labels):** In `scripts/ci/tests/e2e_chain_test.sh`, `poll.sh --once` discovers open candidate pull requests that carry no `status:*` labels in `pr-list.json` and extracts `author_persona` from `headRefName` (derives from D2).
- **AT-2 (Deferred Resolution and Quota Conservation):** In `poll.sh`, an open PR authored by a builder persona with no blocking reviewer comments causes zero calls to `resolve_issue` and zero tracking issue fetches (derives from D3).
- **AT-3 (Daemon-Safe Error Handling):** In `poll.sh`, when an open candidate PR with blocking review comments links multiple issues or cannot be resolved by `resolve_issue`, `poll.sh` logs a skip message, leaves `key_file` unwritten, and continues execution without exiting non-zero (derives from D3).
- **AT-4 (Hold Circuit Breaker on Issue or PR):** When an open candidate PR with blocking review findings resolves to a tracking issue carrying `hold`, or when the PR itself carries `hold`, `poll.sh` logs a refusal, touches no `key_file`, and performs zero launches (derives from D4).
- **AT-5 (Blocked and Review-Stuck Refusals):** When an open candidate PR resolves to a tracking issue that is closed, carries `blocked`, or carries `status:review-stuck`, `poll.sh` logs a refusal, touches no `key_file`, and performs zero launches (derives from D4).
- **AT-6 (Stage-to-Author Alignment Verification):** When an open PR with blocking reviewer findings authored by `athena` resolves to an issue at `status:build`, `poll.sh` refuses dispatch with an informative stage mismatch message, touches no `key_file`, and performs zero launches (derives from D5).
- **AT-7 (Multi-Rung Fix-Round Dispatches in `poll.sh`):** In `scripts/ci/tests/e2e_chain_test.sh`:
  (a) a spec PR authored by `athena` with blocking findings on an issue at `status:spec` dispatches `run.sh <pr> --as athena`;
  (b) a plan PR authored by `daedalus` with blocking findings on an issue at `status:build` dispatches `run.sh <pr> --as daedalus`;
  (c) an implement PR authored by `odyssey` with blocking findings on an issue at `status:implementing` dispatches `run.sh <pr> --as odyssey` (derives from D5, D6).
- **AT-8 (Harmonized `work.sh` Fix-Round Execution):** Executing `DRY_RUN=1 HEADLESS=1 work.sh <pr> --as <persona>` on an open PR with head branch `<persona>/<n>-<slug>`:
  (a) for `athena` on an issue at `status:spec`, derives stage `design` and branch `athena/<n>-<slug>`;
  (b) for `daedalus` on an issue at `status:build`, derives stage `build` and branch `daedalus/<n>-<slug>`;
  (c) for `odyssey` on an issue at `status:implementing`, derives stage `implement` and branch `odyssey/<n>-<slug>`, exiting 0 without refusal in all cases (derives from D7).
- **AT-9 (E2E Contract Test Suite Pass):** Running `bash scripts/ci/tests/e2e_chain_test.sh` passes all scenarios (including updated AT-13, AT-20, AT-21, and multi-rung fix-round tests) with exit 0 (derives from D8).
- **AT-10 (Living Spec Sync):** `docs/SPEC.md ## Deployment status` documents PR-to-issue resolution and multi-rung fix-round mechanics (derives from D9).
- **AT-11 (Pre-Merge CI Checks):** Pre-merge validation checks exit 0:
  `BODY_FILE="$(mktemp)"; echo "Spec-impact: none - intent/** only, not a behavior-bearing path" > "$BODY_FILE"; bash scripts/ci/spec_check.sh origin/main "$BODY_FILE"; rm -f "$BODY_FILE"`
  and `bash scripts/ci/sanitize_check.sh` (derives from D10).

## Concerns

- **API Rate Limiting:** Sourcing `github.sh` and invoking `resolve_issue` adds GitHub API calls. By deferring resolution until after checking the reviewer trigger predicate and consumption key, resolution occurs only when an unconsumed blocking review finding exists (at most once per review round per PR). Under normal repository load, this adds < 10 API calls per day, well within GitHub token quotas.
- **Daemon Resilience:** `poll.sh` runs continuously under systemd/supervisor. Sourcing a shared library that expects `die()` requires careful contract fulfillment; defining `die()` to log and return 1 rather than exiting ensures daemon uptime is preserved even if a PR description is malformed.
- **Key and Lock Cleanup:** Fix-round lock files and consumption keys remain in `POLL_STATE_DIR`. The existing PID liveness checks and 2-hour staleness threshold in `poll.sh:200-222` protect against abandoned locks.

## Out of scope

- Direct implementation of code, test suites, or configuration files (owned by Daedalus at BUILD and Odyssey at IMPLEMENT).
- Modifications to reviewer persona prompts, schemas, or consensus ledger recording in `scripts/ci/review_recorder.sh`.
- Modifications to `.github/workflows/**` or `scripts/ci/merge_gate.sh`.
- Modification of escalation reason codes in `scripts/ci/escalate.sh`.

## Open questions

none
