# Intent: Merge Gate Skipped Jobs and Refs-only Pull Request Resolution

**Issue:** #298 · **Author:** athena (`evekhm-athena-app[bot]`) · **Status:** Draft

## Problem

Two defects in the merge gating and review dispatch machinery prevent autonomous operation on pull requests:

### 1. Conjunct 2 evaluates false on every head due to skipped jobs and superseded cancelled runs

In `.github/workflows/merge-gate.yml`, three jobs are declared: `evaluate`, `record`, and `gate`. On a `pull_request` event, only `evaluate` runs; `record` and `gate` are skipped by their `if:` conditions (`merge-gate.yml:83,147`). GitHub Actions creates check runs for all three jobs on the pull request's head commit:
- `merge-gate (evaluate)`: completed, `SUCCESS`
- `merge-gate (record)`: completed, `SKIPPED`
- `merge-gate`: completed, `SKIPPED`

When a subsequent main-ref trigger executes (e.g., `check_suite: completed` from CI gates or `issue_comment: created` from a review comment), `scripts/ci/merge_gate.sh` evaluates conjunct 2 according to Decision D24 of `intent/64-autonomous-loop/spec.md`. D24 requires that every check run and commit status on the head commit other than the gate's own run must conclude `SUCCESS`. The gate's own run is excluded by database ID equality (`checkSuite.workflowRun.databaseId == GITHUB_RUN_ID`).

Because the earlier `pull_request` event run had a different `GITHUB_RUN_ID` from the current main-ref evaluation run, the two skipped entries (`merge-gate (record)` and `merge-gate`) are treated as foreign check runs. Because `SKIPPED` is not `SUCCESS`, conjunct 2 evaluates to `false` on every head:
```text
conjunct (2): false — mergeStateStatus CLEAN but check(s) not success: merge-gate (record)=SKIPPED merge-gate=SKIPPED
```
This was observed on run 34365593567 for PR #297 (head `275b24a`) and run 34360984750.

Furthermore, on PR #294 (head `35f9a91`), conjunct 2 failed because `CANCELLED` check run entries were left in GraphQL `statusCheckRollup` by superseded runs of `.github/workflows/ci-gates.yml` (runs 34362738489, 34362863141, 34363457498, 34363668892). When `ci-gates.yml` cancels an earlier in-progress run on the same head (via `concurrency.cancel-in-progress: true`), the cancelled check runs persist in the commit's check rollup alongside the newer succeeding check runs. `merge_gate.sh` evaluates all entries in `statusCheckRollup.contexts.nodes`, so the presence of any stale `CANCELLED` entry keeps conjunct 2 permanently false.

As a consequence, with `loop.autonomous_merge: true`, the merge actor declines every pull request on conjunct 2 regardless of reviewer consensus and passing test checks.

### 2. Runner reviewers refuse Refs-only pull requests while the merge gate resolves them

In `scripts/ops/lib/github.sh`, `resolve_issue` (lines 100–142) resolves a pull request to its target issue by checking for closing keywords in the PR description (`Closes #n`, `Fixes #n`, `Resolves #n`) or an issue number in the branch name (`<actor>/<n>-<slug>`). If neither is present, it returns status 2:
```text
refused: cannot resolve PR #<pr> to an issue
```
Meanwhile, `scripts/ci/merge_gate.sh` (lines 102–106) inspects both GitHub closing references and body references matching `refs? #[0-9]+`.

Ladder pull requests (#245) carry `Refs #n` and no closing keyword. Operator pull requests (such as PR #297 on branch `ops/flip-autonomous-merge`) also carry `Refs #n` with a branch name that contains no issue number. When unattended runner reviewers (`argus`, `atlas`) are dispatched against such a pull request (e.g., `work.sh 297 --as argus`), `work.sh` invokes `resolve_issue`, which fails with status 2 and refuses the dispatch (observed on unattended run 34365012629 for PR #297). The merge gate can evaluate the pull request, but automated reviewers cannot review it.

## Proposed outcome

1. **Eliminate skipped check runs on pull request events**:
   - Separate the read-only pull request evaluation job into its own workflow file (e.g., `.github/workflows/merge-gate-evaluate.yml`), removing the `pull_request` trigger from `.github/workflows/merge-gate.yml`.
   - On `pull_request` events, only the evaluate job is scheduled. No `record` or `gate` jobs exist in that workflow run, eliminating the creation of `SKIPPED` check runs on PR heads.
   - Preserves #64 D24's anti-spoofing identity check (`databaseId == GITHUB_RUN_ID`) intact without relaxing exclusion rules.

2. **Handle superseded cancelled check runs in conjunct 2 evaluation**:
   - Update `scripts/ci/merge_gate.sh` check rollup processing to evaluate the latest status/conclusion per check name or context, matching GitHub's own UI rollup behavior.
   - Ensure that a cancelled run superseded by a successful run for the same check name does not falsify conjunct 2.
   - Alternatively or concurrently, refine `.github/workflows/ci-gates.yml` concurrency configuration to prevent cancelling in-progress runs on identical commits.

3. **Unify pull request issue resolution for runner reviewers and merge gate**:
   - Update `scripts/ops/lib/github.sh:resolve_issue` to recognize `Refs #n` (and case-insensitive variants `ref: #n`, `references: #n`), resolving ladder and operator PRs to their referenced issue.
   - Enforce the single-issue invariant strictly: a pull request that references or closes more than one distinct issue fails closed as corrupted input.
   - Deduplicate PR issue resolution logic between `scripts/ops/lib/github.sh` and `scripts/ci/merge_gate.sh` so both tools use a single canonical implementation.
   - Enable unattended runner reviewers (`argus`, `atlas`) to review ladder and operator PRs without resolution refusal.

4. **Hermetic test coverage and regression protection**:
   - Add test scenarios in `scripts/ci/tests/merge_gate_test.sh` verifying conjunct 2 evaluation when earlier evaluate runs exist, when sibling runs are absent, and when superseded cancelled runs are present.
   - Add test scenarios in `scripts/ops/tests/work_test.sh` verifying `resolve_issue` behavior for `Refs #n` PR bodies and non-issue branch names (`ops/*`).

## Affected users and systems

- **Themis (`evekhm-themis-app[bot]`) / Merge Gate**: Evaluates D5 conjuncts and executes autonomous merges under `.github/workflows/merge-gate.yml` and `scripts/ci/merge_gate.sh`.
- **Runner Reviewers (`argus`, `atlas`)**: Review automated and operator PRs under `.github/workflows/unattended.yml`, `scripts/ops/work.sh`, and `scripts/ops/lib/github.sh`.
- **Operators**: Land autonomous merge flips, maintenance updates, and ladder PRs without encountering false declines or dispatch refusals.
- **Workflows**:
  - `.github/workflows/merge-gate.yml`: Triggers and job definitions.
  - `.github/workflows/merge-gate-evaluate.yml` (new): Dedicated PR-event evaluate workflow.
  - `.github/workflows/ci-gates.yml`: Concurrency settings.
- **Scripts**:
  - `scripts/ci/merge_gate.sh`: Conjunct 2 check rollup evaluation and issue resolution.
  - `scripts/ops/lib/github.sh`: `resolve_issue` and `closing_refs` functions.
- **Tests**:
  - `scripts/ci/tests/merge_gate_test.sh`: Conjunct 2 test cases.
  - `scripts/ops/tests/work_test.sh`: Issue resolution test cases.
- **Documentation**:
  - `docs/SPEC.md`: Merge gate conjunct 2 specifications and issue resolution rules.
  - `intent/64-autonomous-loop/spec.md`: Amendment notes for D24 if required.

## Constraints

- **D24 Anti-Spoofing Guarantee**: Check runs must continue to be excluded by verified identity and never by name alone. Foreign check runs named `merge-gate` or crafted to mimic gate jobs must not satisfy conjunct 2.
- **Fail-Closed Security**: Any ambiguous or unreadable state (multiple issues referenced in a PR body, unreadable check rollups, UNKNOWN merge status) must decline or refuse, never merge.
- **Single Unit of Work**: An issue remains the single unit of work (AGENTS.md, #36 D9). A pull request resolving to multiple issues must fail closed.
- **Least Privilege and Environment Isolation**: The PR-event workflow must run read-only under the default `GITHUB_TOKEN` (`DRY_RUN=1`) with no access to secrets or the `themis` Environment. Credential minting remains restricted to the `themis` Environment on default branch events.
- **Spec Integrity**: Any changes to behavior-bearing paths (`scripts/**`, `.github/workflows/**`) during implementation must update `docs/SPEC.md` within the same pull request.

## Open questions

1. **Workflow separation vs trigger gating**: Should `evaluate` be moved to a standalone workflow file `.github/workflows/merge-gate-evaluate.yml`, or can `.github/workflows/merge-gate.yml` configure workflow-level event filtering to avoid creating check runs for skipped jobs?
2. **Rollup deduplication rule**: When multiple check runs exist with the same check name on a commit (such as a cancelled run and a successful run), should `merge_gate.sh` select the check run with the latest `completedAt` timestamp, the highest database ID, or rely on GitHub GraphQL `statusCheckRollup` rollup summary if available?
3. **CI gates concurrency policy**: Should `.github/workflows/ci-gates.yml` retain `cancel-in-progress: true` on PR branches, scope concurrency cancellation strictly to differing commit SHAs, or remove in-progress cancellation to eliminate cancelled check run generation?
4. **Precedence in issue resolution**: When a pull request body carries `Refs #A` and the branch name is `<actor>/<B>-<slug>` (naming two different issues), should `resolve_issue` refuse as corrupted input, or does one source take precedence?
5. **Operator branch review policy**: Should PRs on operator branches (e.g. `ops/*`) undergo standard runner review by Argus and Atlas, or should they follow a dedicated review policy (e.g. smoke test verification only)?
6. **Code sharing for issue resolution**: Should `scripts/ci/merge_gate.sh` source `scripts/ops/lib/github.sh` directly for `resolve_issue`, or should `resolve_issue` be extended and exposed so that both scripts share identical logic?
