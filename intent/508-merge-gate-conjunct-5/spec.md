# Spec: Exclude Withdrawn Findings From Merge Gate Dispute Check

**Issue:** #508 · **Status:** Approved (approval = merge of this PR) · **Author:** athena (`evekhm-athena-app[bot]`) · **Open questions:** none

## What is being built

In `scripts/ci/merge_gate.sh:312`, the merge gate evaluates the set of disputed findings by scanning the parsed consensus ledger tuple:

```bash
DISPUTED="$(awk -F: '$4 == "dispute" {print $1}' <<<"$CTUP")"
```

The consensus tuple format parsed at line 306 is `id:severity:status:peer`. Field 3 represents finding status (`open`, `fixed`, `withdrawn`) and field 4 represents peer consensus state (`pending`, `agree`, `dispute`, `none`).

When a reviewer withdraws a finding after a peer dispute, the finding status transitions to `withdrawn`. The peer column retains the historical record of the dispute (such as `R1-6@none:normal:withdrawn:dispute`). Because line 312 inspects field 4 alone without inspecting field 3, it treats the withdrawn finding as an active dispute.

This causes three downstream check failures:
1. Line 324 fails conjunct (5) (`WHY[5]="dispute on: ..."`) even though the dispute is resolved by withdrawal.
2. Line 374 rejects Atlas carry-forward under Decision #64 D7 condition (iv) (`WHY[3]="atlas cannot carry forward: dispute (D7 (iv))"`).
3. Line 557 triggers a `dispute-at-cap` escalation when the pull request reaches the round cap `review:3`.

This specification updates line 312 to filter out findings with status `withdrawn`:

```bash
DISPUTED="$(awk -F: '$3 != "withdrawn" && $4 == "dispute" {print $1}' <<<"$CTUP")"
```

Withdrawn findings are excluded from `DISPUTED`. Findings with status `open` or `fixed` that carry peer state `dispute` remain in `DISPUTED`.

### Manifest of Files Touched by the Implementation Rung

- `scripts/ci/merge_gate.sh`: update line 312 dispute filter expression to exclude status `withdrawn`.
- `scripts/ci/tests/merge_gate_test.sh`: add test cases verifying that `withdrawn:dispute` passes conjunct (5), permits Atlas carry-forward, and avoids round-cap escalation.
- `docs/SPEC.md`: update the merge gate living spec under `loop.autonomous` documenting the exclusion of withdrawn findings from the dispute scan.
- `CHANGELOG.md`: document the bug fix under the current release notes.
- `intent/508-merge-gate-conjunct-5/plan.md`: ordered implementation plan authored by Daedalus.

### Manifest of Files Touched by this PR (Athena)

- `intent/508-merge-gate-conjunct-5/intent.md`: update status to `Accepted`.
- `intent/508-merge-gate-conjunct-5/spec.md`: this specification.

### Forbidden Files (Untouched)

- `scripts/ci/review_recorder.py`: consensus ledger derivation and label sync logic are preserved unchanged.
- `scripts/ci/review_recorder.sh`: recorder entrypoint is preserved unchanged.
- `scripts/ci/tests/review_recorder_test.sh`: recorder test suite is preserved unchanged.
- `scripts/ci/escalate.sh`: escalation execution logic is preserved unchanged.
- `scripts/ci/lifecycle_advance.sh`: ladder transition logic is preserved unchanged.
- `.github/workflows/**`: GitHub Actions workflow definitions are preserved unchanged.
- `personas/**`: persona instructions and boundaries are preserved unchanged.
- `config/**`: execution configuration and model tiers are preserved unchanged.

## Decisions

| ID | Decision | Rationale |
|---|---|---|
| **D1** | **Exclusion of withdrawn findings from merge gate dispute check.** In `scripts/ci/merge_gate.sh:312`, `DISPUTED` is defined as `awk -F: '$3 != "withdrawn" && $4 == "dispute" {print $1}' <<<"$CTUP"`. Findings with status `withdrawn` are omitted from `DISPUTED`. | *Adversary analysis:* Two defensible readings: (1) Check `$3 == "open" && $4 == "dispute"`, admitting only open disputes; (2) Check `$3 != "withdrawn" && $4 == "dispute"`, admitting open and fixed disputes while excluding withdrawn findings. Differing case: A consensus ledger row carries `R1-1@D1:high:fixed:dispute`. Under Reading 1, `DISPUTED` is empty and conjunct (5) passes. Under Reading 2, `DISPUTED` contains `R1-1@D1` and conjunct (5) fails (`WHY[5]="dispute on: R1-1@D1"`). Reading 2 is adopted. A finding whose fix adequacy is disputed by a peer remains an active disagreement requiring resolution. A finding retracted by its discovering author represents resolved consensus agreement. |
| **D2** | **Uniform consumption of the filtered `DISPUTED` set across merge gate checks.** The `DISPUTED` variable populated at line 312 is consumed directly by conjunct (5) evaluation at line 324, Atlas carry-forward evaluation at line 370, and round-cap escalation at line 557. No separate unfiltered dispute scan is introduced. | *Adversary analysis:* Two defensible readings: (1) Consume the filtered `DISPUTED` variable across all three check locations; (2) Retain an unfiltered historical dispute check for Atlas carry-forward or round-cap escalation. Differing case: A pull request at round cap `review:3` has one ledger row `R1-1@D1:high:withdrawn:dispute`. Under Reading 1, line 557 evaluates `DISPUTED` as empty, avoiding a `dispute-at-cap` escalation. Under Reading 2, an unfiltered check detects `peer == "dispute"` and escalates to `status:review-stuck`. Reading 1 is adopted. Withdrawing a finding resolves peer disagreement completely. The pull request has no active dispute blocking conjunct (5), no dispute invalidating Atlas carry-forward, and no unresolved dispute warranting escalation. |
| **D3** | **Preservation of severity-agnostic dispute matching for active findings.** The filter in line 312 checks status alone (`$3 != "withdrawn"`). It does not filter field 2 (`severity`). Active disputes on `normal` or `suggestion` rows continue to populate `DISPUTED`. | *Adversary analysis:* Two defensible readings: (1) Maintain severity-agnostic dispute collection (`$3 != "withdrawn" && $4 == "dispute"`); (2) Restrict disputes to blocking severities (`$2 ~ /^(security|high)$/`). Differing case: A consensus ledger contains an open disputed row of normal severity (`R1-2@none:normal:open:dispute`). Under Reading 1, `DISPUTED` contains `R1-2@none` and conjunct (5) fails. Under Reading 2, `DISPUTED` is empty and conjunct (5) passes. Reading 1 is adopted. Policy governing whether non-blocking severity disputes block conjunct (5) is owned by issue #503. Issue #508 bounds scope strictly to retracted findings. |
| **D4** | **Hermetic test suite coverage in `scripts/ci/tests/merge_gate_test.sh`.** The test suite `scripts/ci/tests/merge_gate_test.sh` is extended with explicit test cases covering: (a) conjunct (5) passes when a ledger contains `withdrawn:dispute` without other disputes; (b) conjunct (5) fails when a ledger contains `open:dispute`; (c) conjunct (5) fails when a ledger contains `fixed:dispute`; (d) Atlas carry-forward under Decision #64 D7 succeeds when the only dispute row is `withdrawn:dispute`; (e) at round cap `review:3`, a ledger carrying `withdrawn:dispute` does not escalate with reason `dispute-at-cap`. | *Adversary analysis:* Two defensible readings: (1) Add unit tests solely for conjunct (5); (2) Add test coverage across conjunct (5), Atlas carry-forward, and round-cap escalation. Differing case: An implementation modifies line 312 but introduces a secondary dispute check in `escalate.sh` or at line 557. Under Reading 1, tests pass despite a defect in round-cap escalation. Under Reading 2, test scenario (e) fails loudly. Reading 2 is adopted. All three functional areas consuming `DISPUTED` must have explicit regression coverage. |
| **D5** | **Living spec update obligation.** The implementing pull request updates `docs/SPEC.md` under `loop.autonomous` (around line 1444) to document that findings with status `withdrawn` are excluded from the dispute check in conjunct (5), Atlas carry-forward condition (iv), and round-cap escalation. | *Adversary analysis:* Two defensible readings: (1) Classify the fix as an internal implementation detail requiring no living spec update; (2) Require a living spec update describing the exclusion of withdrawn findings. Differing case: `spec_check.sh` validates the implementation pull request. Under Reading 1, `spec_check.sh` permits `Spec-impact: none`. Under Reading 2, `spec_check.sh` enforces a concrete diff in `docs/SPEC.md`. Reading 2 is adopted. `docs/SPEC.md` specifies conjunct (5) requirements and must reflect accurate system behavior. |
| **D6** | **Scope boundary and file manifest.** The implementing change touches only the five files listed in the implementation manifest. It does not modify `review_recorder.py`, `review_recorder.sh`, `escalate.sh`, `lifecycle_advance.sh`, or workflow files. | *Adversary analysis:* Two defensible readings: (1) Permit edits to `review_recorder.py` to synchronize labels for withdrawn disputes; (2) Confine changes to `merge_gate.sh` and its test suite. Differing case: An implementation updates `review_recorder.py` to suppress `consensus:disputed` on withdrawn findings. Under Reading 1, this edit is accepted. Under Reading 2, this edit violates the scope boundary. Reading 2 is adopted. Retaining `review_recorder.py` unchanged is an explicit non-goal in `intent.md`. |

## Acceptance

- **AT-508-1 (D1):** `scripts/ci/merge_gate.sh:312` extracts `DISPUTED` using `awk -F: '$3 != "withdrawn" && $4 == "dispute" {print $1}' <<<"$CTUP"`. `grep -n 'DISPUTED=' scripts/ci/merge_gate.sh` confirms status `withdrawn` is filtered out.
- **AT-508-2 (D1, D4):** In `scripts/ci/tests/merge_gate_test.sh`, a fixture containing consensus ledger row `R1-1:normal:withdrawn:dispute` evaluates conjunct (5) as true (`consensus axis agreed, no dispute`).
- **AT-508-3 (D1, D3, D4):** In `scripts/ci/tests/merge_gate_test.sh`, a fixture containing consensus ledger row `R1-1:high:open:dispute` evaluates conjunct (5) as false with output `dispute on: R1-1`.
- **AT-508-4 (D1, D3, D4):** In `scripts/ci/tests/merge_gate_test.sh`, a fixture containing consensus ledger row `R1-1:high:fixed:dispute` evaluates conjunct (5) as false with output `dispute on: R1-1`.
- **AT-508-5 (D2, D4):** In `scripts/ci/tests/merge_gate_test.sh`, a fixture where Atlas has not reviewed the current head but satisfies conditions (i), (ii), (iii), and (v) of Decision #64 D7, and whose consensus ledger carries `R1-1:normal:withdrawn:dispute`, satisfies condition (iv) and carries forward Atlas's verdict.
- **AT-508-6 (D2, D4):** In `scripts/ci/tests/merge_gate_test.sh`, a fixture at round cap `review:3` whose consensus ledger carries `R1-1:normal:withdrawn:dispute` does not emit loop-ledger marker `refusal:dispute-at-cap` and does not escalate with reason `dispute-at-cap`.
- **AT-508-7 (D4):** `bash scripts/ci/tests/merge_gate_test.sh` exits 0 with all test assertions passing.
- **AT-508-8 (D5):** `docs/SPEC.md` records that findings with status `withdrawn` are excluded from the merge gate dispute check, and `bash scripts/ci/spec_check.sh origin/main <pr-body>` exits 0.
- **AT-508-9 (D6):** `git diff --name-only origin/main` on the implementation pull request matches only the files permitted in the implementation manifest.

## Open questions

none
