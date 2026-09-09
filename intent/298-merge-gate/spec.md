# Spec: Merge Gate Skipped Jobs and Refs-only Pull Request Resolution

**Issue:** #298 · **Status:** Approved (approval = merge of this PR) ·
**Author:** athena (`evekhm-athena-app[bot]`) ·
**Open questions:** none

## What is being built

Two defects in the merge gating and review dispatch machinery prevent autonomous
operation on pull requests. This specification resolves both without weakening
existing anti-spoofing guarantees:

1. **Workflow separation for `evaluate`**: Extract the `evaluate` job from
   `.github/workflows/merge-gate.yml` into a standalone workflow file
   `.github/workflows/merge-gate-evaluate.yml` triggered strictly on
   `pull_request: types: [opened, synchronize, reopened]`. Remove `pull_request`
   from `.github/workflows/merge-gate.yml` triggers. This stops GitHub Actions
   from scheduling `record` and `gate` on pull request events, eliminating the
   creation of skipped `merge-gate (record)` and `merge-gate` check runs on head
   commits. D24's anti-spoofing identity check (`databaseId == GITHUB_RUN_ID`)
   remains fully intact.
2. **Check rollup deduplication in `merge_gate.sh`**: When evaluating conjunct 2
   in `scripts/ci/merge_gate.sh`, deduplicate check runs in `statusCheckRollup` by
   check name (or context), selecting the latest entry by highest `databaseId`
   (or last appearance in document order). Check runs with conclusion `CANCELLED`
   from superseded workflow runs (such as cancelled CI gates runs) no longer fail
   conjunct 2 if a newer run of that same check concluded `SUCCESS`.
3. **CI gates concurrency scoping**: In `.github/workflows/ci-gates.yml`, scope
   the concurrency group to include the head commit SHA, ensuring that non-push
   events on the same commit (such as `edited` pull request descriptions) do not
   cancel in-progress gate jobs.
4. **Recognition of `Refs #n` in issue resolution**: In
   `scripts/ops/lib/github.sh`, expand issue reference extraction to recognize
   `Refs #n` (and case-insensitive variants `refs? #n`, `references? #n`) in
   pull request descriptions alongside closing keywords. This enables ladder
   pull requests (#245) and operator pull requests (e.g. `ops/*`) to resolve to
   their target issue, allowing runner reviewers (`argus`, `atlas`) to be
   dispatched without refusal.
5. **Strict single-issue invariant**: Enforce across both
   `scripts/ops/lib/github.sh` and `scripts/ci/merge_gate.sh` that a pull request
   links to exactly one issue across body references (`Closes #n`, `Refs #n`) and
   branch name (`<actor>/<n>-<slug>`). Conflicting issue numbers fail closed as
   corrupted input (`die` / `decline`), refusing to guess.
6. **Harmonized issue resolution**: Unify the issue resolution rules between
   `scripts/ops/lib/github.sh` and `scripts/ci/merge_gate.sh` so that any pull
   request the merge gate can evaluate can also be resolved and reviewed by
   runner reviewers.

```text
.github/workflows/merge-gate-evaluate.yml  # new standalone workflow for evaluate on pull_request events
.github/workflows/merge-gate.yml           # remove pull_request trigger and evaluate job; adjust if conditions
.github/workflows/ci-gates.yml             # concurrency group scoped to head SHA
scripts/ci/merge_gate.sh                   # check rollup deduplication by check name; unified issue resolution
scripts/ci/tests/merge_gate_test.sh        # test cases for deduplicated rollup, superseded cancelled runs, and issue refs
scripts/ops/lib/github.sh                  # resolve_issue recognizes Refs #n; strict single-issue validation
scripts/ops/tests/work_test.sh             # test cases for Refs-only PRs, operator branch PRs, conflicting issue refusal
docs/SPEC.md                               # living spec updates for merge gate conjunct 2 and ops.dispatch resolver
```

`personas/**`, `personas/lifecycle.json`, `scripts/ops/claim.sh`, `scripts/ops/work.sh`
(outside library sourcing), `scripts/ci/escalate.sh`, and `scripts/ci/lifecycle_advance.sh`
are **not** touched.

## Decisions

| ID | Decision | Rationale |
|---|---|---|
| D1 | **Standalone `merge-gate-evaluate.yml` workflow for PR events.** The `evaluate` job is extracted from `.github/workflows/merge-gate.yml` into a dedicated, standalone workflow file at `.github/workflows/merge-gate-evaluate.yml`. It triggers exclusively on `pull_request: types: [opened, synchronize, reopened]`. It contains a single job named `merge-gate (evaluate)` running with read-only permissions (`contents: read`, `pull-requests: read`, `issues: read`, `checks: read`, `statuses: read`) using `github.token` with `DRY_RUN=1`. It checks out `ref: main`, enforces base branch `github.base_ref == 'main'` (failing closed if not), and runs `bash scripts/ci/merge_gate.sh "$TARGET"`. It creates exactly one check run named `merge-gate (evaluate)` on the pull request head commit with conclusion `SUCCESS` when evaluation succeeds. | In GitHub Actions, any workflow triggered on `pull_request` creates check run entries for all jobs declared in that workflow file; jobs skipped by `if:` conditions conclude as `SKIPPED`. Moving `evaluate` to its own workflow file ensures that on `pull_request` events, only the evaluate job is scheduled. No `record` or `gate` jobs exist in that workflow, so zero skipped check runs are created on the PR head commit. This completely resolves the skipped jobs defect without relaxing D24's anti-spoofing identity rule. |
| D2 | **`.github/workflows/merge-gate.yml` trigger list and job conditions.** `.github/workflows/merge-gate.yml` removes `pull_request` from its `on:` trigger list. Its triggers are strictly: `check_suite: types: [completed]`, `status:`, `issue_comment: types: [created]`, and `workflow_dispatch:` (with `pull_request` number input). The `evaluate` job is removed entirely from `merge-gate.yml`. The remaining jobs, `record` and `gate`, run under `environment: themis` on the default branch `main`. The `if:` conditions on `record` and `gate` are simplified to `github.event_name != 'issue_comment' \|\| github.event.issue.pull_request` (for `gate`: `${{ always() && (github.event_name != 'issue_comment' \|\| github.event.issue.pull_request) }}`). | Removing `pull_request` ensures that every execution of `merge-gate.yml` runs from the default branch `main` under the protected `themis` environment. With `evaluate` moved to `merge-gate-evaluate.yml`, `merge-gate.yml` runs only when writes are actually permitted (`record` and `gate`). |
| D3 | **Check rollup deduplication by check name / context in `merge_gate.sh`.** When `scripts/ci/merge_gate.sh` evaluates conjunct 2 (`CLEAN` or `UNSTABLE` with all foreign checks passing), it deduplicates entries in `statusCheckRollup.contexts.nodes` by check name (for `CheckRun`) or context (for `StatusContext`):<br>1. GraphQL query `GRAPHQL_ROLLUP` requests `databaseId` on `CheckRun`: `... on CheckRun{name conclusion status databaseId checkSuite{workflowRun{databaseId}}}`.<br>2. Check runs whose `checkSuite.workflowRun.databaseId == GITHUB_RUN_ID` are excluded first, by identity (D24).<br>3. Among the remaining foreign checks, if multiple entries share the same `name` (or `context`), `merge_gate.sh` selects the entry with the highest `databaseId` (or the last entry in document order if `databaseId` is absent), representing the latest run of that check.<br>4. Conjunct 2 evaluates the deduplicated set of latest checks: every check in the deduplicated set must have conclusion/state `SUCCESS`. If any check has conclusion/state `CANCELLED`, `FAILURE`, `TIMED_OUT`, `ACTION_REQUIRED`, or `PENDING` (empty or `IN_PROGRESS`/`QUEUED`), conjunct 2 is `false` and lists the failing check(s). If the deduplicated set contains 0 foreign checks, conjunct 2 is `false` (`mergeStateStatus $MERGE_STATE but no check besides the gate's own run`). | GitHub GraphQL `statusCheckRollup` retains check runs from superseded workflow runs. When a workflow run is cancelled due to concurrency or re-run, earlier cancelled runs remain attached to the commit. GitHub's own pull request UI displays the status of the latest run of each check. Deduplicating by check name and taking the latest entry ensures that a cancelled check from a superseded run does not block merge once a subsequent run of that check has succeeded, while ensuring that active failures or pending runs still prevent merge. |
| D4 | **Concurrency group scoping in `.github/workflows/ci-gates.yml`.** In `.github/workflows/ci-gates.yml`, the concurrency group is updated to incorporate the head commit SHA:<br>`group: ci-gates-${{ github.event.pull_request.number \|\| github.ref }}-${{ github.event.pull_request.head.sha \|\| github.sha }}`<br>with `cancel-in-progress: true`. | Incorporating the head commit SHA into the concurrency group ensures that non-commit events on the pull request (specifically `edited`, which fires when the PR title or description is updated to satisfy the spec check) do not cancel in-progress test runs on the same commit. Pushing a new commit creates a different concurrency group and does not cancel the same commit's run, while redundant triggers on the exact same commit are serialized or replaced safely. |
| D5 | **`resolve_issue` recognizes `Refs #n` reference mentions.** In `scripts/ops/lib/github.sh`, pull request body issue extraction is expanded: helper `closing_refs` is complemented or generalized by `issue_refs` to extract both GitHub closing keywords (`\b(close[sd]?\|fix(es\|ed)?\|resolve[sd]?)[[:space:]]+#[0-9]+`) and reference keywords (`\b(refs?\|references?)[[:space:]]+#[0-9]+`), case-insensitively. `resolve_issue` uses this extractor to parse the pull request body. When the body contains a reference like `Refs #298`, `resolve_issue` successfully resolves the issue number (`ISSUE="298"`, `RESOLVED_VIA="Refs #298 in the body"`). | Under the SDLC ladder workflow (#245), intermediate pull requests (plan, spec, implementation) carry `Refs #n` rather than closing keywords because the pull request merge must not close the tracking issue prematurely. Operator pull requests (e.g. `ops/flip-autonomous-merge`) also carry `Refs #n`. Today, `resolve_issue` only recognized closing keywords, causing unattended reviewers (`argus`, `atlas`) to refuse dispatch on ladder and operator pull requests with status 2. Recognizing `Refs #n` allows runner reviewers to review all pull requests linking to an issue. |
| D6 | **Strict single-issue invariant across body and branch.** Pull request resolution strictly enforces that a pull request links to exactly one issue: the set of issue numbers extracted from the body (via closing keywords and reference keywords) and the issue number extracted from the head branch name (matching `^[a-z][a-z-]*/([0-9]+)-`) are unioned.<br>1. If the union contains zero issue numbers: in `scripts/ops/lib/github.sh` (`resolve_issue`), the function returns 2 (`cannot resolve PR #n to an issue`); in `scripts/ci/merge_gate.sh`, the gate logs `no linked issue on #$PR ... — not a ladder pull request; nothing evaluated, nothing written` and exits 0.<br>2. If the union contains more than one issue number (for example, body references `#10` but branch is `odyssey/20-slug`, or body mentions both `#10` and `#12`): in `scripts/ops/lib/github.sh` (`resolve_issue`), it calls `die "PR #$number links more than one issue: ... — dispatch one of them by its own number"`; in `scripts/ci/merge_gate.sh`, it declines with `decline "#$PR links two different issues (...) — corrupted input, nothing written"`.<br>3. If the union contains exactly one issue number, that number is `ISSUE`. | A pull request is not the unit of work; the issue is. Allowing a pull request to link to multiple distinct issues would create ambiguity about which issue's claim, lifecycle labels, and loop ledger apply. Never guessing between conflicting body references and branch names adheres to the fail-closed core principle of the repository. |
| D7 | **Harmonized issue resolution between `scripts/ops/lib/github.sh` and `scripts/ci/merge_gate.sh`.** `scripts/ci/merge_gate.sh` aligns its PR-to-issue resolution with `scripts/ops/lib/github.sh`. Both scripts use the exact same regex for body issue references (`(^\|[^[:alnum:]])(refs?\|references?\|close[sd]?\|fix(es\|ed)?\|resolve[sd]?)[[:space:]]+#[0-9]+`), the exact same branch name regex (`^[a-z][a-z-]*/([0-9]+)-`), and evaluate the union of body issues and branch issue under Decision D6. | Having two different scripts implement two different interpretations of how a pull request resolves to an issue caused the defect in #298, where `merge_gate.sh` resolved PR #297 to issue #64 while `work.sh` refused it. Unifying the resolution logic guarantees that if the merge gate can evaluate a pull request, the runner reviewers can also resolve and review it. |
| D8 | **Operator pull requests undergo standard runner review.** Operator pull requests targeting `main` whose branch names do not follow the persona convention (e.g. `ops/*`) and which reference a tracking issue via `Refs #n` in the body are resolved to that issue by `resolve_issue` and are reviewed by Argus and Atlas via standard review dispatch (#207). If an operator pull request references no issue and carries no closing keyword, it does not resolve to an issue (returns 2 in `resolve_issue`, exits 0 unlinked in `merge_gate.sh`); it is treated as an unlinked pull request outside the SDLC ladder and receives no unattended review or autonomous merge. | Any PR modifying configuration or code on `main` benefits from independent review by Argus and Atlas. Making `Refs #n` sufficient for issue resolution allows operators to opt-in any branch (including `ops/*`) to full reviewer scrutiny simply by citing the issue, while branches without issue citations remain manual/operator-only. |
| D9 | **Implementation scope boundaries.** The implementing pull request may touch: `.github/workflows/merge-gate-evaluate.yml` (new), `.github/workflows/merge-gate.yml`, `.github/workflows/ci-gates.yml`, `scripts/ci/merge_gate.sh`, `scripts/ci/tests/merge_gate_test.sh`, `scripts/ops/lib/github.sh`, `scripts/ops/tests/work_test.sh`, and `docs/SPEC.md`. It may NOT touch `personas/**`, `personas/lifecycle.json`, `scripts/ops/claim.sh`, `scripts/ops/work.sh` (outside library sourcing), `scripts/ci/escalate.sh`, or `scripts/ci/lifecycle_advance.sh`. | Clean scope boundaries prevent merge conflicts with concurrent issues, protect the autonomous lifecycle advance workflow, and ensure persona definitions remain unchanged. |

## Acceptance

- **AT-1 (D1, D2)** On a `pull_request` event, `.github/workflows/merge-gate-evaluate.yml`
  runs `evaluate` read-only (`DRY_RUN=1`) and creates check run `merge-gate (evaluate)`
  with conclusion `SUCCESS`. Workflow `.github/workflows/merge-gate.yml` does not trigger
  on `pull_request`, creating zero skipped check runs on the pull request head.
- **AT-2 (D2)** In `.github/workflows/merge-gate.yml`, jobs `record` and `gate` declare
  conditions excluding `pull_request` and running only on main-ref events
  (`check_suite`, `status`, `issue_comment`, `workflow_dispatch`).
- **AT-3 (D3)** In `scripts/ci/tests/merge_gate_test.sh`, a commit whose `statusCheckRollup`
  contains a `CANCELLED` CheckRun entry superseded by a newer `SUCCESS` CheckRun entry
  with the same name passes conjunct 2 (`conjunct (2): true`).
- **AT-4 (D3)** In `scripts/ci/tests/merge_gate_test.sh`, a commit whose `statusCheckRollup`
  contains an older `SUCCESS` CheckRun entry superseded by a newer `CANCELLED` or
  `FAILURE` CheckRun entry fails conjunct 2 (`conjunct (2): false`).
- **AT-5 (D3)** In `scripts/ci/tests/merge_gate_test.sh`, a commit whose `statusCheckRollup`
  contains an active `PENDING` (or null conclusion) CheckRun entry fails conjunct 2
  (`conjunct (2): false`).
- **AT-6 (D3)** In `scripts/ci/tests/merge_gate_test.sh`, the gate's own run is excluded
  by database ID (`checkSuite.workflowRun.databaseId == GITHUB_RUN_ID`), and a foreign
  check run named `merge-gate` still counts and fails conjunct 2 if not success
  (D24 anti-spoofing preserved).
- **AT-7 (D4)** In `.github/workflows/ci-gates.yml`, the concurrency group includes
  `github.event.pull_request.head.sha || github.sha`.
- **AT-8 (D5, D8)** In `scripts/ops/tests/work_test.sh`, `resolve_issue` on a pull request
  with no closing keyword and body containing `Refs #123` on an operator branch
  `ops/flip-flag` successfully resolves to issue 123 (`ISSUE=123`).
- **AT-9 (D5)** In `scripts/ops/tests/work_test.sh`, `work.sh <pr> --as argus` on a ladder
  pull request with `Refs #123` on branch `athena/123-slug` resolves to issue 123 and
  proceeds to review dispatch.
- **AT-10 (D6)** In `scripts/ops/tests/work_test.sh`, a pull request with body `Refs #100`
  and branch `odyssey/200-slug` fails as corrupted input, refusing to guess between
  conflicting issues.
- **AT-11 (D6)** In `scripts/ci/tests/merge_gate_test.sh`, a pull request with body
  `Refs #100` and branch `odyssey/200-slug` is declined with `corrupted input, nothing written`.
- **AT-12 (D6, D8)** In `scripts/ops/tests/work_test.sh`, a pull request with no body
  references and branch `ops/no-issue` exits 2 (`cannot resolve PR to an issue`).
- **AT-13 (D7)** In `scripts/ci/tests/merge_gate_test.sh`, an unlinked pull request
  (no closing keyword, no `Refs #n`, no `<actor>/<n>-<slug>` branch) exits 0 without
  evaluation or writes.
- **AT-14 (D9)** The implementing pull request updates `docs/SPEC.md` under `ci.merge-gate`
  and `ops.dispatch`, and `bash scripts/ci/spec_check.sh origin/main <body-file>` exits 0.

## Open questions

none
