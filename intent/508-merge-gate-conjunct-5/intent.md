# Intent: Exclude Withdrawn Findings From Merge Gate Dispute Check

**Issue:** #508 · **Author:** athena (`evekhm-athena-app[bot]`) · **Status:** Accepted

## Problem

In `scripts/ci/merge_gate.sh:312`, the merge gate evaluates conjunct (5) by collecting disputed finding identifiers from parsed consensus ledger rows:

```bash
DISPUTED="$(awk -F: '$4 == "dispute" {print $1}' <<<"$CTUP")"
```

The consensus ledger row format parsed at line 306 is `id:severity:status:peer`, where `status` is one of `open`, `fixed`, or `withdrawn`, and `peer` is one of `pending`, `agree`, `dispute`, or `none`. Line 312 inspects field 4 (`peer`) without inspecting field 3 (`status`).

When a reviewer withdraws a finding after a peer dispute, the finding status transitions to `withdrawn` while the peer column preserves the historical record of the dispute (for example, `R1-6@none:normal:withdrawn:dispute`). Because line 312 tests `$4 == "dispute"` alone, it treats the withdrawn finding as an active dispute.

This causes three downstream failures in `scripts/ci/merge_gate.sh`:
1. Line 324 fails conjunct (5) (`WHY[5]="dispute on: ..."`) even though the dispute reached agreement through finding retraction.
2. Line 374 rejects Atlas carry-forward under Decision #64 D7 (iv) (`WHY[3]="atlas cannot carry forward: dispute (D7 (iv))"`).
3. Line 557 triggers a `dispute-at-cap` escalation when the pull request reaches the round cap.

This failure occurred on PR #500, where Argus withdrew finding `R1-6` following citations provided by Atlas. Ten of eleven conjuncts passed, but conjunct (5) remained false due to the withdrawn row, resulting in a terminal stall requiring manual human intervention.

## Proposed outcome

1. Restrict the dispute check in `scripts/ci/merge_gate.sh:312` to exclude findings with status `withdrawn`. A finding with status `withdrawn` is excluded from `DISPUTED`.
2. A consensus ledger carrying a row with status `withdrawn` and peer `dispute` satisfies conjunct (5) when no other active disputes exist.
3. The carry-forward check at line 374 and the round-cap escalation check at line 557 consume the updated `DISPUTED` set, preventing carry-forward refusals and `dispute-at-cap` escalations on withdrawn findings.
4. Active disputes on open findings (such as `open:dispute`) continue to populate `DISPUTED`, failing conjunct (5) as required by Decision #64 D5.
5. Automated contract tests in `scripts/ci/tests/merge_gate_test.sh` verify that `withdrawn:dispute` passes conjunct (5), carry-forward, and escalation checks, while `open:dispute` fails conjunct (5).

## Affected users and systems

- Autonomous merge gate (`scripts/ci/merge_gate.sh`): conjunct (5) evaluation, Atlas carry-forward condition (iv), and round-cap escalation.
- Merge gate test suite (`scripts/ci/tests/merge_gate_test.sh`): test coverage for withdrawn dispute rows and active open dispute rows.
- Autonomous pull request lifecycle: pull requests where reviewer disagreement concludes with finding withdrawal will merge autonomously without manual human override.

## Constraints

- Scope is strictly bounded to excluding `withdrawn` findings from the `DISPUTED` check in `scripts/ci/merge_gate.sh:312`.
- Active disputes must continue to fail conjunct (5) and trigger escalation at the round cap.
- All tests in `scripts/ci/tests/merge_gate_test.sh` must remain hermetic and pass with exit code 0.
- Surface mapping hits and change obligations:
  - `README.md`: concept and vision remain true (line 464 describes agreed / pending / disputed status generally); no edit required.
  - `INTENT.md`: founding statements remain untouched; no edit required.
  - `REVIEW.md`: review protocol and marker formats remain unchanged; no edit required.
  - `docs/SPEC.md`: living spec update owed during implementation under the merge gate specification.
  - `config/`: no configuration schema changes; no edit required.
  - `intent/64-autonomous-loop/spec.md`: Decisions D5, D6, D7, D9, D10 are refined in implementation; no retrospective edit required.
  - `intent/267-severity-tiered-merge-gate-review-md/spec.md`: Decision D7 is respected; no retrospective edit required.
  - `intent/291-recorder-hold-parity/spec.md`: Decision D5 invariant (withdrawn findings are inactive) is upheld; no retrospective edit required.
- Prose coherence rules apply: no em dash characters, no comparative exclusion phrasing, no contrast sentences, and no machine home paths.

## Relationships

- `refines #64`: Decision #64 D5 conjunct (5) requires no live dispute on the consensus axis; this intent refines the merge gate dispute scan so that withdrawn findings are recognized as resolved.
- `refines #267`: Decision #267 D7 defines finding status transitions including `withdrawn` for retracted findings; this intent ensures the merge gate respects this status transition.
- `depends on #291`: Decision #291 D5 establishes that retracted findings are inactive; this intent aligns conjunct (5) with that invariant.
- `refines #503`: Issue #503 evaluates policy regarding whether open disputes on non-blocking severity tiers should block conjunct (5); this intent resolves the defect for retracted findings while leaving open dispute policy to #503.

## Open questions

None. The scope is bounded to excluding withdrawn findings from the dispute check in `scripts/ci/merge_gate.sh:312`.

## Non-goals

- Changing severity tiering for active disputes, which is addressed in issue #503.
- Modifying `scripts/ci/review_recorder.py` or the emitted consensus ledger schema.
- Clearing `fixed:dispute` rows, which remain active questions regarding fix verification.
- Introducing manual merge overrides or changing human operator escalation flows.
