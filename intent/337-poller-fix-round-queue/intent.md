# Intent: Poller Fix-Round Queue Resolves PR to Issue for Stage Verification

**Issue:** #337 · **Author:** athena (`evekhm-athena-app[bot]`) · **Status:** Draft

## Problem

Under `loop.autonomous_merge: true` (PR #297), the autonomous software development lifecycle operates an unattended poller daemon (`scripts/placement/vm-local/poll.sh`) to advance issues and pull requests through the development ladder. The poller is responsible for three distinct queues:
1. Advancing issues with loop-ledger `dispatch` rows across ladder transitions.
2. Intaking new issues carrying `intent:new` and `intake:auto` (Decision D4 of #295).
3. Dispatching fix rounds on open pull requests when autonomous reviewers (`evekhm-argus-app[bot]` or `evekhm-atlas-app[bot]`) post blocking findings (Decision D2 of #251, Decision D6 of #295).

While first-hop intake and ladder dispatch row consumption function properly, the poller's fix-round queue is completely inoperative in production:

1. **Filtering by a Non-Existent Pull Request Label (`status:in-review`):**
   In `scripts/placement/vm-local/poll.sh` lines 128 and 145, the fix-round queue attempts to discover pull requests eligible for fix rounds using:
   ```bash
   prs_json="$(gh pr list --state open --label status:in-review --json number,title,labels,headRefName,isCrossRepository 2>/dev/null || echo '[]')"
   ...
   has_in_review="$(jq -r '[.labels[]? | (.name // .)] | if index("status:in-review") != null then "yes" else "no" end' <<<"$pr_obj")"
   [ "$has_in_review" = "yes" ] || continue
   ```
   In this repository's architecture (AGENTS.md, `scripts/setup/bootstrap_tracker.sh`), pull requests **never** carry `status:*` labels. The tracker labels are the state machine, and lifecycle stage labels (`status:planning`, `status:spec`, `status:build`, `status:implementing`, `status:in-review`) are written solely to the underlying **tracking issue** by `scripts/ci/lifecycle_advance.sh`.

2. **Stage Lifecycle Realities Across Pull Request Types:**
   Even on the tracking issue, `status:in-review` is written only upon the merge of an implementation pull request (`lifecycle_advance.sh:1022-1078`, advancing to the terminal review rung). While any pull request is open and awaiting review, its tracking issue carries the stage label corresponding to that rung:
   - **Intent PRs** (stage: `plan`, author: `athena`): issue carries `intent:new` (or `status:planning`).
   - **Spec PRs** (stage: `design`, author: `athena`): issue carries `status:spec`.
   - **Plan PRs** (stage: `build`, author: `daedalus`): issue carries `status:build`.
   - **Implementation PRs** (stage: `implement`, author: `odyssey`): issue carries `status:implementing`.
   Therefore, an open pull request under review never has its tracking issue at `status:in-review` either.

3. **Live Failure Mode (Empirical Evidence):**
   On pull request #335 (spec PR for issue #308, branch `athena/308-merge-gate-yml-repository-wide`), Atlas posted a blocking `high` finding (`AT-R1-1@none`, closing keyword `Resolves #308` in PR body). Issue #308 was at `status:spec`. The pull request satisfied the reviewer trigger predicate in `poll.sh:163-178`. However, `gh pr list --label status:in-review` returned zero pull requests. The poller never reached the trigger predicate, and no fix round fired. As a result, the PR remained blocked and required manual operator intervention.

4. **Masked by Contract Test Fixture Discrepancy:**
   Contract test row AT-13 in `scripts/ci/tests/e2e_chain_test.sh:1281-1310` sets up a synthetic fixture `issue-108.json` representing a PR with `"labels": [{"name": "status:in-review"}]`. The test suite passed green because the test asserted against an artificial label shape that the live system never creates.

## Proposed outcome

1. **Query Open Pull Requests Without Status Label Filter:**
   In `scripts/placement/vm-local/poll.sh` section 2, remove `--label status:in-review` from the `gh pr list` invocation, querying all open repository pull requests with fields `number,title,labels,headRefName,isCrossRepository`.

2. **Resolve PR to Tracking Issue via `resolve_issue()`:**
   Incorporate `scripts/ops/lib/github.sh` into `poll.sh` and utilize the canonical `resolve_issue "$pr_num"` helper (the identical function used by `scripts/ops/work.sh` and `scripts/ops/post.sh`).
   - For each candidate pull request, verify that it is authored by an authorized ladder builder persona (`athena`, `daedalus`, `odyssey`) from `headRefName` (`head_ref%%/*`).
   - Resolve the pull request to its tracking issue via closing keywords, body references, or head branch naming.
   - If the pull request cannot be resolved cleanly to a single issue (e.g. references zero issues or closes multiple issues), skip the pull request fail-closed.

3. **Verify Tracking Issue State and Admissibility:**
   Verify that the resolved tracking issue:
   - Is open (`state == "open"`).
   - Does not carry circuit breakers or halts (`hold`, `blocked`, or `status:review-stuck`).
   - Matches the author persona's stage ownership:
     - `athena`: issue carries `intent:new`, `status:planning`, or `status:spec`.
     - `daedalus`: issue carries `status:build`.
     - `odyssey`: issue carries `status:implementing`.

4. **Multi-Rung Fix-Round Eligibility:**
   Explicitly specify that builder pull requests across all rungs (spec PRs by `athena`, plan PRs by `daedalus`, and implement PRs by `odyssey`) are eligible for automated fix rounds when an authorized reviewer (`argus` or `atlas`) posts blocking findings (`security` or `high`).

5. **Harmonize `scripts/ops/work.sh` Fix-Round Handling:**
   Review and update `scripts/ops/work.sh:398-404` so that fix-round detection (`is_fix_round`) properly recognizes PR fix rounds for all builder personas under their valid issue stages, ensuring consistent branch and slug resolution without failing Refusal (h).

6. **Repair Contract Test Fixtures in `e2e_chain_test.sh`:**
   Update contract test row AT-13 in `scripts/ci/tests/e2e_chain_test.sh` to remove `"labels": [{"name": "status:in-review"}]` from `issue-108.json` (the PR fixture), ensuring the test exercises the real repository data shape. Add contract coverage verifying that fix rounds fire for `athena` (spec PR), `daedalus` (plan PR), and `odyssey` (implement PR).

7. **Update Living Specification:**
   Update `docs/SPEC.md` to document that the poller fix-round queue resolves pull requests to their tracking issues via `resolve_issue()` and evaluates the issue's stage rather than checking pull request labels.

## Affected users and systems

- **VM Poller Daemon (`scripts/placement/vm-local/poll.sh`)**: Fix-round candidate discovery, PR-to-issue resolution, issue stage verification, and trigger predicate evaluation.
- **Work Dispatch Adapter (`scripts/ops/work.sh`)**: Fix-round path detection and stage derivation across all builder personas.
- **Contract Test Suite (`scripts/ci/tests/e2e_chain_test.sh`)**: Scenario AT-13 and test fixtures for pull requests.
- **Autonomous Builders (`athena`, `daedalus`, `odyssey`)**: Receive unattended fix-round dispatches to address reviewer feedback promptly.
- **Autonomous Reviewers (`argus`, `atlas`)**: Review findings reliably trigger builder fixes without manual operator triage.
- **Living Specification (`docs/SPEC.md`)**: Poller fix-round mechanics and issue resolution contract.

## Constraints

- **Single Source of Truth for Lifecycle State**: Stage labels (`status:*`) belong strictly to issues. No workflow, script, or actor may write `status:*` labels to pull requests.
- **Established Helper Reuse**: Re-use `resolve_issue()` in `scripts/ops/lib/github.sh`. Do not introduce redundant or disparate resolution logic.
- **Fail-Closed Safety**: A pull request that cannot be unambiguously resolved to a single tracking issue, or whose tracking issue carries `hold`, `blocked`, or `status:review-stuck`, must be skipped without dispatch.
- **Strict Reviewer Identity Bounds**: Trigger predicates continue to admit only authorized reviewer bot logins (`evekhm-argus-app[bot]` and `evekhm-atlas-app[bot]`) per Decision D6 of #295.
- **Persona Boundaries**: Athena authors only intent and spec artifacts (`intent/**`). Daedalus plans the build (`plan.md`), and Odyssey implements code and tests.

## Open questions

*Note: These questions are reserved for Athena's DESIGN pass (`spec.md`) following acceptance of this intent.*

1. **Stage Check Scope on the Tracking Issue:**
   Should `poll.sh` enforce a strict 1-to-1 mapping between the pull request author persona and the issue's current `status:*` label (e.g. `athena` requires `intent:new`/`status:planning` or `status:spec`; `daedalus` requires `status:build`; `odyssey` requires `status:implementing`), or should it accept any open, non-held/non-blocked issue where the PR author matches the branch prefix?

2. **Refining `is_fix_round` in `scripts/ops/work.sh`:**
   In `scripts/ops/work.sh:399`, the condition `[ "$status_labels" = "status:in-review" ]` was originally written under the assumption that issues sit at `status:in-review` during review. For spec and plan PRs, the issue sits at `status:spec` or `status:build`. Should `work.sh` update `is_fix_round=1` to trigger whenever `IS_PR=1`, `--as` matches the PR head author, and the issue stage matches the author's declared stage?

3. **Intent PR Fix-Round Eligibility:**
   Under the merge gate rules of #321, intent PRs carry `intent:new` without a `status:*` label. While intent PRs rarely receive blocking review findings, should they be eligible for fix rounds if Argus or Atlas flags a blocking finding, or should fix rounds strictly require a ranked `status:*` label on the issue?

4. **Poller Tick Rate and API Quota Management:**
   Listing all open pull requests (`gh pr list --state open`) and calling `resolve_issue` for each candidate on every 30-second tick makes additional GitHub API calls. With typical repository volume (< 10 open PRs), this consumes negligible quota. Should `poll.sh` cache resolved issue numbers per PR head SHA in `POLL_STATE_DIR` to optimize API traffic, or is querying per tick preferred for state freshness?
