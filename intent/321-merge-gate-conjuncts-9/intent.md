# Intent: Merge Gate Rung-1 Resolution for Intent Pull Requests

**Issue:** #321 · **Author:** athena (`evekhm-athena-app[bot]`) · **Status:** Draft

## Problem

Under `loop.autonomous_merge: true` (enabled since PR #297), Themis evaluates merge readiness and merges eligible pull requests without human intervention. While pull requests at the design rung (`status:spec`, e.g. PR #309, #311) and the build rung (`status:build`, e.g. PR #307) have successfully merged autonomously, no intent pull request can merge autonomously under the current gate logic.

This defect prevents the autonomous loop from starting any new issue without human intervention. The cause lies in the interaction between the issue label lifecycle and the merge gate's rung evaluation:

1. **Conjuncts 9 and 10 Require a Ranked `status:*` Label**:
   In `scripts/ci/merge_gate.sh` (lines 211-214 and 342-368), the merge gate extracts the issue's current status label with:
   ```bash
   STATUS="$(grep '^status:' <<<"$ISSUE_LABELS" || true)"
   idx="$(rung_of "$STATUS")"
   ```
   `rung_of` looks up `$STATUS` in `personas/lifecycle.json`. If `$STATUS` is empty or `idx` is `null`, conjuncts 9 and 10 evaluate to false:
   ```bash
   if [ -z "$STATUS" ] || [ "$idx" = "null" ]; then
       WHY[9]="#$ISSUE carries no ranked status label (${STATUS:-none})"; WHY[10]="${WHY[9]}"
   ```

2. **Rung 1 Issues Carry Only `intent:new`**:
   In the repository's lifecycle design (#57), no automation writes `status:planning`. When an issue enters the lifecycle, it carries the label `intent:new` and no `status:*` label.
   - `scripts/ops/work.sh` (lines 347-350) treats an issue carrying `intent:new` and no `status:*` label as being on stage 0 (`plan`, the first rung in `personas/lifecycle.json`).
   - `scripts/ops/claim.sh` claims `intent:new` issues by adding `in-progress` and creates a worktree, but does not write `status:planning`.
   - `scripts/ci/lifecycle_advance.sh` (lines 1033-1045) clears `intent:new` when it writes the first `status:*` label on the ladder, which is `status:spec` upon the merge of `intent.md`.
   - As a result, throughout the entire plan stage, the issue carries `intent:new` and zero `status:*` labels.

3. **Autonomous Merge Loop Stalls at the First Gate**:
   Because `scripts/ci/merge_gate.sh` does not recognize `intent:new` as marking the first rung, `STATUS` is empty, `idx` is `null`, and both conjunct 9 (artifact presence at `$HEAD`) and conjunct 10 (rung rank strictly exceeding highest merged rank) evaluate to false.
   
   This failure was observed live on PR #315 (issue #308's intent PR). PR #315 received CLEAN verdicts from the verifier and both runner reviewers (Argus and Atlas), passing 9 of 11 conjuncts, but stalled permanently because conjuncts 9 and 10 evaluated to false with `#308 carries no ranked status label (none)`. The same failure will recur on every intent PR, including PR #316 and issue #321's own intent PR.
   
   A human operator must currently merge the intent PR for every issue by hand before the autonomous loop can take over.

## Proposed outcome

1. **Resolve `intent:new` as Rung 1 in `merge_gate.sh`**:
   - In `scripts/ci/merge_gate.sh`, update the conjunct 9 and 10 evaluation block: when `STATUS` is empty and `ISSUE_LABELS` contains `intent:new`, resolve the stage index as 0 (`status:planning`, rung 1, artifact `intent.md`).
   - In the budget bounds block (lines 218-225), update the rung index derivation so that an issue carrying `intent:new` records budget refusals at rung 1 rather than falling back to rung 0.
   - Ensure `RUNG` is set to 1 and `ARTIFACT` is set to `intent.md`.
   - Conjunct 9 verifies that `intent/<issue>-<slug>/intent.md` exists and is non-empty at `$HEAD`.
   - Conjunct 10 verifies monotonicity: `RUNG` (1) > `HIGHEST_MERGED_RANK` (which is 0 when no earlier rung has merged).

2. **Preserve Monotonicity and Fail-Closed Safety**:
   - If an issue carries neither a ranked `status:*` label nor `intent:new`, conjuncts 9 and 10 must continue to evaluate to false with `#$ISSUE carries no ranked status label (none)`.
   - If an issue carries `intent:new` but the loop ledger already records a merged rung at or above rung 1 (`HIGHEST_MERGED_RANK >= 1`), conjunct 10 evaluates to false, blocking duplicate or regressive intent merges.

3. **Update Living Spec in `docs/SPEC.md`**:
   - Update `docs/SPEC.md` under the merge gate section to document that an issue carrying `intent:new` with no `status:*` label is recognized as rung 1 (`status:planning`, artifact `intent.md`).

4. **Add Contract Test Coverage in `scripts/ci/tests/merge_gate_test.sh`**:
   - Add hermetic test cases covering:
     - An issue carrying only `intent:new` with `intent.md` present at `$HEAD` passes conjuncts 9 and 10 and merges when all other conjuncts hold.
     - An issue carrying only `intent:new` with `intent.md` missing at `$HEAD` fails conjunct 9.
     - An issue carrying only `intent:new` where rung 1 is already recorded in the loop ledger fails conjunct 10.
     - An issue carrying no `status:*` label and no `intent:new` label fails conjuncts 9 and 10.

## Affected users and systems

- **Autonomous Merge Gate / Themis (`evekhm-themis-app[bot]`)**: Evaluates conjuncts 9 and 10 in `scripts/ci/merge_gate.sh` to permit autonomous merging of intent PRs.
- **Autonomous Reviewers (`argus`, `atlas`)**: Review intent PRs with confidence that approved pull requests will merge autonomously once verifier and gate criteria are met.
- **Workflow Operations**: Eliminates required manual human merges on intent PRs, enabling end-to-end autonomous progression from intake to completion.
- **Scripts**:
  - `scripts/ci/merge_gate.sh`: Conjunct 9/10 evaluation and budget refusal rung derivation.
- **Tests**:
  - `scripts/ci/tests/merge_gate_test.sh`: New test scenarios verifying rung-1 evaluation for `intent:new`.
- **Documentation**:
  - `docs/SPEC.md`: Living spec entry for merge gate rung evaluation rules.

## Constraints

- **Fail-Closed Security**: An unlabelled issue or an issue carrying unranked labels without `intent:new` must never satisfy conjuncts 9 or 10.
- **Monotonicity Invariant**: An intent PR must not merge if an intent artifact (or higher rung artifact) has already merged for the issue. Conjunct 10 must strictly guard against backwards progression.
- **Zero Label Mutation**: The fix must not require changing existing issue labels across the tracker or adding premature label writers in `claim.sh`.
- **Hermetic Tests**: Tests in `scripts/ci/tests/merge_gate_test.sh` must remain completely hermetic, relying on the test suite's stub `gh` and local fixtures with no network access.
- **Persona Role Boundary**: Athena produces only this intent artifact (`intent/321-merge-gate-conjuncts-9/intent.md`). Implementation changes to shell scripts and test files belong to Odyssey after Daedalus plans the build.

## Open questions

*Note: These open questions are for the spec rung to evaluate and resolve, owned by Athena (Product Owner).*

1. **Budget Refusal Rung Mapping**:
   In `scripts/ci/merge_gate.sh` lines 218-225, `idx="$(rung_of "$STATUS")"` defaults `rung=0` if `STATUS` is empty. Should the `intent:new` mapping explicitly set `rung=1` in the budget check block so that a budget refusal on an intent PR records `loop-ledger-row: refusal:budget rung:1` instead of `rung:0`?

2. **Taxonomy Long-Term Alignment**:
   Should `intent:new` remain the permanent marker for rung 1, or should intake automation eventually replace `intent:new` with `status:planning` upon intake triage? If `intent:new` remains the permanent marker, should `personas/lifecycle.json` formally acknowledge `intent:new` alongside `status:planning`?

3. **Handling of Multiple Conflicting Labels**:
   `scripts/ci/merge_gate.sh` line 213 checks that `n_status <= 1`. If an issue somehow carries both `intent:new` and a `status:*` label (for instance, if `lifecycle_advance.sh` failed to strip `intent:new`), should `merge_gate.sh` decline as corrupted state, or should the explicit `status:*` label take precedence over `intent:new`?

4. **Diagnostic Specificity for Monotonicity Failures**:
   When an issue carrying `intent:new` is evaluated against an existing ledger where `HIGHEST_MERGED_RANK >= 1`, does the existing failure reason `"rung 1 is not above highest merged rung N (D14)"` provide sufficient diagnostic clarity, or should an explicit message indicate that an intent artifact was already merged?

5. **Defect-Repair Issues (`bug` label)**:
   Defect-repair issues carry `bug` without a `status:*` label or `intent:new`. Does defect repair merge through `merge_gate.sh`, or does it follow a separate operator or fast-track merge path?
