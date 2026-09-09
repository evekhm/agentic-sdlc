# Spec: Merge Gate Rung-1 Resolution for Intent Pull Requests

**Issue:** #321 · **Status:** Approved (approval = merge of this PR) ·
**Author:** athena (`evekhm-athena-app[bot]`) ·
**Open questions:** none

## What is being built

Under `loop.autonomous_merge: true` (PR #297), Themis evaluates merge readiness and merges eligible pull requests autonomously. While pull requests at the design rung (`status:spec`, e.g. PR #309, #311) and the build rung (`status:build`, e.g. PR #307) have successfully merged autonomously, no intent pull request can merge autonomously under the current gate logic.

This defect stalls the autonomous loop at the intake gate of every new issue. In `scripts/ci/merge_gate.sh`, conjuncts 9 and 10 evaluate the issue's current rung by extracting `STATUS` from the issue's `status:*` labels and calling `rung_of "$STATUS"` against `personas/lifecycle.json`. However, issues at the first lifecycle stage enter the ladder carrying `intent:new` and zero `status:*` labels (#57, #295). Because nothing in the repository writes `status:planning`, `STATUS` is empty, `idx` evaluates to `null`, and both conjunct 9 (artifact presence at `$HEAD`) and conjunct 10 (rung rank strictly exceeding highest merged rank) evaluate to `false` with `#<issue> carries no ranked status label (none)`.

This specification resolves the first-hop autonomous merge defect across six binding decisions:

1. **Rung-1 resolution for `intent:new` in `merge_gate.sh` (D1)**: In `scripts/ci/merge_gate.sh`, when `STATUS` is empty and the issue carries `intent:new`, resolve the issue as stage index `idx=0` (`status:planning`, ladder rung `RUNG=1`, artifact `intent.md`).
2. **Artifact verification for Rung 1 (`intent.md`) in Conjunct 9 (D2)**: Conjunct 9 verifies that exactly one `intent/<issue>-<slug>/` directory exists at `$HEAD` and that `intent.md` exists and is non-empty. Unlike `spec.md` (which requires `Status: Approved` and `Open questions: none`), `intent.md` requires no specific header approval status.
3. **Monotonicity enforcement for Rung 1 in Conjunct 10 (D3)**: Conjunct 10 enforces `RUNG (1) > HIGHEST_MERGED_RANK`. For an initial intent PR (`HIGHEST_MERGED_RANK=0`), conjunct 10 evaluates to `true`. If the loop ledger already records a merged rung at or above rung 1 (`HIGHEST_MERGED_RANK >= 1`), conjunct 10 evaluates to `false`, preventing duplicate or regressive intent merges.
4. **Rung derivation in budget refusal evaluation (D4)**: In the budget bounds block of `merge_gate.sh`, resolve `rung=1` when `intent:new` is present so that budget refusals on intent PRs record `refusal:budget 1` instead of `rung 0`.
5. **Label precedence and fail-closed safety (D5)**: If an issue carries an explicit single `status:*` label alongside `intent:new`, the `status:*` label takes precedence. If an issue carries more than one `status:*` label, `merge_gate.sh` declines as corrupted state. Issues carrying neither `status:*` nor `intent:new` (such as defect repairs with only `bug`) fail conjuncts 9 and 10 as unranked.
6. **Scope boundaries and living spec updates (D6)**: Bound implementation changes to `scripts/ci/merge_gate.sh`, `scripts/ci/tests/merge_gate_test.sh`, and `docs/SPEC.md`. `personas/lifecycle.json`, `personas/**`, `scripts/ci/lifecycle_advance.sh`, `scripts/ci/escalate.sh`, and `scripts/ops/*` are not touched.

```text
scripts/ci/merge_gate.sh            # rung-1 derivation for intent:new in conjuncts 9/10 and budget refusals
scripts/ci/tests/merge_gate_test.sh # hermetic contract tests for rung-1 autonomous merge and monotonicity
docs/SPEC.md                        # living spec update documenting intent:new rung-1 merge gate evaluation
intent/321-merge-gate-conjuncts-9/spec.md # this specification
```

`personas/lifecycle.json`, `personas/**`, `scripts/ci/lifecycle_advance.sh`, `scripts/ci/escalate.sh`,
`scripts/ops/claim.sh`, and `scripts/ops/work.sh` are **not** touched.

## Decisions

| ID | Decision | Rationale |
|---|---|---|
| D1 | **Rung-1 resolution for `intent:new` in `scripts/ci/merge_gate.sh` (Conjuncts 9 and 10).** When deriving the stage index for an issue in `scripts/ci/merge_gate.sh`: (1) If `STATUS` contains a single `status:*` label, `idx` is resolved via `rung_of "$STATUS"` in `personas/lifecycle.json`. (2) If `STATUS` is empty and the issue carries label `intent:new` (`grep -Fxq "intent:new" <<<"$ISSUE_LABELS"`), the issue resolves as stage index `idx=0` (`status:planning`, ladder rung `RUNG=1`, artifact `intent.md`). (3) If `STATUS` is empty and the issue lacks `intent:new`, or if `STATUS` carries an unranked status label where `idx` is `null`, conjuncts 9 and 10 evaluate to `false` with `#$ISSUE carries no ranked status label (${STATUS:-none})`. | Aligns `merge_gate.sh` with `scripts/ops/work.sh:347` and the lifecycle architecture (#57), where no automation writes `status:planning` and the intake rung is marked exclusively by `intent:new`. This allows intent pull requests to pass conjuncts 9 and 10 autonomously when verifier and reviewer consensus gates are satisfied. |
| D2 | **Artifact verification for Rung 1 (`intent.md`) in Conjunct 9.** When an issue is resolved at rung 1 (`idx=0`, `RUNG=1`, `ARTIFACT="intent.md"`): (1) `merge_gate.sh` verifies that exactly one directory matching `intent/$ISSUE-*/` exists at `$HEAD`. If zero or more than one such directory exists, conjunct 9 evaluates to `false` (`expected exactly one intent/$ISSUE-*/ folder at $HEAD, found: <list>`). (2) `merge_gate.sh` verifies that `intent/$dirs/intent.md` exists and is non-empty at `$HEAD`. If absent or empty, conjunct 9 evaluates to `false` (`intent/$dirs/intent.md is absent at $HEAD`). (3) Unlike `spec.md` (which requires `Status: Approved` and `Open questions: none`), `intent.md` does not require specific header status markers: any non-empty `intent.md` under `intent/$ISSUE-*/` satisfies the artifact check, setting `C[9]=1` and `WHY[9]="intent/$dirs/intent.md present at $HEAD"`. | At the PLAN gate, the intent document defines the problem, proposed outcome, affected systems, constraints, and open questions. Unlike `spec.md`, which requires formal approval status and zero open questions before implementation planning, `intent.md` carries no approval metadata; its acceptance is signified by reviewer consensus and the merge itself. |
| D3 | **Monotonicity enforcement for Rung 1 in Conjunct 10.** When an issue is resolved at rung 1 (`RUNG=1`): (1) Conjunct 10 evaluates `if [ "$RUNG" -gt "$HIGHEST_MERGED_RANK" ]`. (2) If `HIGHEST_MERGED_RANK` is 0 (no ladder rung has merged for this issue yet), conjunct 10 evaluates to `true` (`C[10]=1`, `WHY[10]="rung 1 > highest merged rung 0"`). (3) If `HIGHEST_MERGED_RANK` is greater than or equal to 1 (meaning an intent PR or higher-rung artifact has already merged for this issue), conjunct 10 evaluates to `false` (`C[10]=0`, `WHY[10]="rung 1 is not above highest merged rung $HIGHEST_MERGED_RANK (D14)"`). | Preserves strict monotonicity (Decision D14 of #64). An issue whose intent artifact has already merged must never merge a duplicate or regressive intent pull request. Retaining the standard D14 error format ensures backwards compatibility with existing diagnostics and assertions. |
| D4 | **Rung derivation in budget refusal evaluation.** In `scripts/ci/merge_gate.sh` lines 218-225 (the budget bounds check), when `over_budget` is non-empty: (1) Rung derivation applies the same resolution as D1: if `STATUS` is empty and `intent:new` is present, `idx=0` and `rung=1`. (2) If an issue carrying only `intent:new` breaches `max_rung_dispatches_per_issue` or `max_cost_usd_per_issue`, the recorded loop ledger row is `refusal:budget 1` (identifying rung 1) rather than `rung 0`. (3) If neither a ranked `status:*` label nor `intent:new` is present, `rung` defaults to 0. | Ensures that budget refusals occurring on intent pull requests accurately reflect the active ladder rung (`rung:1`), consistent with ledger reporting for subsequent rungs. |
| D5 | **Label precedence and fail-closed safety.** In `scripts/ci/merge_gate.sh`: (1) If an issue carries both a single `status:*` label and `intent:new` (e.g. if `intent:new` was not removed upon advancing to `status:spec`), the explicit `status:*` label takes precedence. Rung derivation uses `status:*` and ignores `intent:new`. (2) If an issue carries more than one `status:*` label (regardless of whether `intent:new` is present), `merge_gate.sh` declines as corrupted state (`#$ISSUE carries more than one status:* label ... — corrupted state, nothing written`), performing zero writes. (3) Issues without any `status:*` label and without `intent:new` (including defect-repair issues carrying only `bug`, unlabelled issues, or unranked labels) fail conjuncts 9 and 10 with `#$ISSUE carries no ranked status label (none)`. | Maintains exact parity with `scripts/ops/work.sh:342-358`. Explicit status labels represent forward progression on the ladder. Corrupted multi-status states fail closed immediately without guessing. Issues outside the ladder cannot merge through the autonomous ladder gate. |
| D6 | **Implementation scope boundaries and living spec updates.** Implementation changes are strictly confined to: `scripts/ci/merge_gate.sh` (stage derivation for conjuncts 9/10 and budget refusals), `scripts/ci/tests/merge_gate_test.sh` (contract test suite additions), and `docs/SPEC.md` (living spec updates under `ci.merge-gate`). Files `personas/lifecycle.json`, `personas/**`, `scripts/ci/lifecycle_advance.sh`, `scripts/ci/escalate.sh`, `scripts/ops/claim.sh`, and `scripts/ops/work.sh` are not touched. | `personas/lifecycle.json` defines `status:planning` as the canonical lifecycle stage definition; changing it would trigger widespread recompilation and affect the lifecycle state machine. `scripts/ci/lifecycle_advance.sh` already clears `intent:new` upon writing `status:spec` on intent merge. Keeping scope tight prevents regressions and conflicts. |

## Acceptance

- **AT-1 (D1, D2, D3)** In `scripts/ci/tests/merge_gate_test.sh` (scenario MG-37), a pull request for an issue carrying only `intent:new` (no `status:*` label) with `intent/<issue>-<slug>/intent.md` present at `$HEAD`, CLEAN verifier and reviewer consensus, and empty loop ledger (`HIGHEST_MERGED_RANK=0`), passes conjunct 9 (`intent/.../intent.md present at $HEAD`), passes conjunct 10 (`rung 1 > highest merged rung 0`), and merges autonomously.
- **AT-2 (D1, D2)** In `scripts/ci/tests/merge_gate_test.sh` (scenario MG-38), a pull request for an issue carrying only `intent:new` where `intent.md` is absent at `$HEAD` fails conjunct 9 (`intent/.../intent.md is absent at $HEAD`), and the merge gate does not merge.
- **AT-3 (D1, D3)** In `scripts/ci/tests/merge_gate_test.sh` (scenario MG-39), a pull request for an issue carrying only `intent:new` where the loop ledger already records a merged rung at or above rung 1 (`HIGHEST_MERGED_RANK >= 1`) passes conjunct 9 but fails conjunct 10 (`rung 1 is not above highest merged rung 1 (D14)`), performing zero writes.
- **AT-4 (D1, D5)** In `scripts/ci/tests/merge_gate_test.sh` (scenario MG-40), a pull request for an issue carrying no `status:*` label and no `intent:new` label (e.g. only `bug` or empty labels) fails conjuncts 9 and 10 with `#$ISSUE carries no ranked status label (none)`, performing zero writes.
- **AT-5 (D4)** In `scripts/ci/tests/merge_gate_test.sh` (scenario MG-41), a pull request for an issue carrying only `intent:new` that exceeds `max_cost_usd_per_issue` or `max_rung_dispatches_per_issue` records a ledger refusal row `refusal:budget 1` (identifying rung 1).
- **AT-6 (D5)** In `scripts/ci/tests/merge_gate_test.sh` (scenario MG-42), an issue carrying both `status:spec` and `intent:new` is evaluated as `status:spec` (rung 2, artifact `spec.md`), ignoring `intent:new`.
- **AT-7 (D6)** In `docs/SPEC.md`, the living spec under `ci.merge-gate` is updated to describe rung-1 resolution for `intent:new` issues; `bash scripts/ci/spec_check.sh origin/main <pr-description-file>` passes with exit code 0.

## Concerns

- **Monotonicity across retries and re-opened PRs**: Conjunct 10 guarantees that if `intent.md` was already merged for an issue (evidenced by a loop ledger dispatch row at rung 2 or terminal row), another intent PR cannot merge autonomously.
- **Clean transition to DESIGN gate**: Once `intent.md` merges, `scripts/ci/lifecycle_advance.sh` removes `intent:new` and adds `status:spec`. The issue advances normally to rung 2 where Athena drafts `spec.md`.
- **Diagnostic clarity**: Retaining standard D14 error formatting (`rung 1 is not above highest merged rung N (D14)`) avoids regressions in automated monitoring or ledger analysis.

## Out of scope

- Modifying `personas/lifecycle.json` or changing the canonical ladder definitions.
- Adding label writers to `scripts/ops/claim.sh`.
- Modifying `scripts/ci/lifecycle_advance.sh` or `scripts/ci/escalate.sh`.
- Altering the defect-repair workflow (`bug` label).

## Operator decisions

None required.

## Open questions

none
