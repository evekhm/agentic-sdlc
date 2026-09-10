# Spec: Normalize Finding Base IDs for Failure-Scenario Matching in Review Recorder

**Issue:** #354 · **Status:** Approved (approval = merge of this PR) ·
**Author:** athena (`evekhm-athena-app[bot]`) ·
**Open questions:** none

## What is being built

This specification establishes base ID normalization between review finding lines and failure-scenario markers in the Themis consensus recorder (`scripts/ci/review_recorder.py`). It resolves a critical defect where the consensus recorder demoted every `high` severity finding to `normal` whenever reviewers cited decisions on finding lines (such as `R1-1@D7`) alongside bare failure-scenario markers (`<!-- failure-scenario:R1-1 -->`). Because `normal` findings are non-blocking, this demotion allowed pull requests carrying active blocking defects to auto-merge autonomously into `main` (as observed on PR #349).

The specification defines ten numbered decisions:

1. **Base ID normalization for failure-scenario matching (D1)**: Normalizes both finding IDs (`fid`) and failure-scenario markers (`fs`) by stripping any `@` character and subsequent citation tag (`token.split('@', 1)[0]`).
2. **Symmetric syntax support (D2)**: Symmetrically matches all four combinations of bare and suffixed finding IDs and failure-scenario markers.
3. **Full finding ID preservation in ledger rows and audit notes (D3)**: Preserves the full, unmodified finding ID (`fid`) in consensus ledger rows (`<!-- ledger-row:<fid>:... -->`) and demotion audit notes.
4. **Verdict block scope and non-decremented marker presence (D4)**: Scopes failure-scenario marker sets to the containing review verdict block, satisfying all findings sharing the base ID without consuming or decrementing markers.
5. **Diagnostic execution logging of demotions (D5)**: Prints an explicit diagnostic message to stdout when a `high` finding is demoted due to a missing failure-scenario marker.
6. **Review protocol documentation update (D6)**: Updates `personas/skills/review-protocol.md` and `REVIEW.md` to document that failure-scenario markers match on base finding IDs and accept both bare and suffixed marker forms.
7. **Exemption preservation (D7)**: Preserves #291 D5 exemptions from demotion for findings with status `withdrawn` or peer consensus state `dispute`.
8. **Contract test coverage matrix (D8)**: Expands `scripts/ci/tests/review_recorder_test.sh` to cover all four syntax combinations, negative demotion paths, and stdout diagnostic logging.
9. **Implementation scope boundary (D9)**: Confines implementation changes strictly to the recorder engine, test suite, protocol documentation, living spec, and lifecycle artifacts.
10. **Living specification synchronization (D10)**: Updates `docs/SPEC.md` under `review.policy` upon implementation.

### File Manifest

```text
scripts/ci/review_recorder.py            # normalizes base IDs for failure-scenario matching, logs demotions to stdout
scripts/ci/tests/review_recorder_test.sh # contract and regression tests for all syntax combinations and demotions
personas/skills/review-protocol.md       # protocol documentation clarifying marker pairing rules
REVIEW.md                                # root review protocol documentation clarifying marker pairing rules
docs/SPEC.md                             # living spec update under review.policy
intent/354-recorder-demotes-every/spec.md # this specification
intent/354-recorder-demotes-every/intent.md # intent artifact updated to Status: Accepted
```

Files under `.github/workflows/**`, `scripts/ops/**`, `scripts/ci/merge_gate.sh`, and other persona files are not touched.

## Decisions

| ID | Decision | Rationale |
|---|---|---|
| D1 | **Base ID normalization for failure-scenario matching.** When evaluating whether a `high` severity finding is accompanied by a sibling failure-scenario marker in `scripts/ci/review_recorder.py`, the recorder extracts the base finding ID from both the finding ID (`fid`) and each extracted failure-scenario marker (`fs`) by stripping any `@` character and all characters following it: `base_id = token.split('@', 1)[0]`. Membership is evaluated as `base_fid not in failure_scenarios_base`. | Reviewers cite spec decisions on finding lines (e.g. `<!-- finding:R1-1@D7:high:open:pending -->`) per review protocol, but emit failure-scenario markers citing the base ID (`<!-- failure-scenario:R1-1 -->`). Direct exact matching (`"R1-1@D7" not in {"R1-1"}`) produced false-positive demotions, disabling the blocking tier. Normalizing base IDs aligns the comparison with reviewer practice. |
| D2 | **Symmetric syntax support across bare and suffixed formats.** The failure-scenario matching logic in `scripts/ci/review_recorder.py` must symmetrically accept all four combinations of finding ID format and failure-scenario marker format:<br>1. Suffixed finding (`R1-1@D7`) + Bare marker (`R1-1`) -> match.<br>2. Suffixed finding (`R1-1@D7`) + Suffixed marker (`R1-1@D7`) -> match.<br>3. Bare finding (`R1-1`) + Bare marker (`R1-1`) -> match.<br>4. Bare finding (`R1-1`) + Suffixed marker (`R1-1@D7`) -> match.<br>In all four cases, an active, undisputed `high` finding retains `high` severity in the consensus ledger and incurs no demotion. | Eliminates syntax fragility between reviewers and recorder. Whether a reviewer provides a bare base marker or a decision-cited marker, valid failure scenarios are reliably recognized without requiring retroactive edits to historical comments. |
| D3 | **Full finding ID preservation in ledger rows and audit notes.** Base ID normalization is strictly internal to the failure-scenario presence check. The recorded ledger row identifier (`<!-- ledger-row:<fid>:<severity>:<status>:<peer> -->`), the Markdown ledger table entry, and any demotion audit note (`[demoted from high: missing failure_scenario marker] on <fid>`) must retain the full, unmodified finding ID `fid` as emitted by the reviewer (including any decision citation `@<Dn>`). | Downstream builders and reviewers track, dispute, retier, and resolve findings by their exact declared IDs. Truncating finding IDs in the public ledger would break cross-round traceability and decision citation provenance. |
| D4 | **Verdict block scope and non-decremented marker presence.** Sibling failure-scenario markers are extracted per accepted review verdict block (`accepted_blocks_by_comment`). A failure-scenario marker satisfies the requirement for any and all `high` findings within that verdict block that share the matching base ID. Markers are not consumed, counted, or decremented. Findings declared across different review blocks or comments must provide their own sibling failure-scenario markers. | Maintains the block-level scoping invariant of review comments while avoiding artificial 1-to-1 consumption rules when a reviewer decomposes a failure scenario across multiple specific decision violations under the same base ID. |
| D5 | **Diagnostic execution logging of demotions.** When an active, undisputed `high` finding lacks a matching sibling failure-scenario marker and is demoted to `normal`, `scripts/ci/review_recorder.py` must print a diagnostic line to stdout: `print(f"finding {fid}: demoted from high to normal: missing failure_scenario marker")`. | `REVIEW.md:126-127` requires demotions to be noted loudly and never silently. Printing to stdout ensures immediate visibility in GitHub Actions step logs, matching the diagnostic logging emitted for invalid severity refusals. |
| D6 | **Review protocol marker syntax specification.** `personas/skills/review-protocol.md` and `REVIEW.md` are updated to explicitly document that failure-scenario markers match on base finding IDs, and that reviewers may provide either the base ID (`<!-- failure-scenario:R1-1 -->`) or the decision-cited ID (`<!-- failure-scenario:R1-1@D7 -->`), with both treated as valid and equivalent by the consensus recorder. | Eliminates the protocol ambiguity between template tokens and finding ID citation rules that caused the divergence between reviewers and recorder. |
| D7 | **Exemption preservation (#291 D5 parity).** A `high` severity finding lacking a sibling failure-scenario marker is exempted from demotion to `normal` if its status is `withdrawn` (the discovering reviewer retracted the finding) or its peer consensus state is `dispute` (the finding is actively contested by a peer reviewer). Only active, undisputed `high` findings (`status != 'withdrawn'` and `peer != 'dispute'`) without failure-scenario markers are demoted to `normal`. | Preserves existing consensus invariants established in #291 D5: retracted findings require no scenario proof, and disputed findings must retain their contested tier for peer arbitration. |
| D8 | **Contract test coverage matrix in `scripts/ci/tests/review_recorder_test.sh`.** `scripts/ci/tests/review_recorder_test.sh` must include test cases verifying:<br>1. All four combinations of bare/suffixed finding and marker formats retain `high` severity without demotion.<br>2. Suffixed `high` finding without matching marker demotes to `normal` with audit note citing the full ID (`R1-1@D7`) and emits the stdout diagnostic log.<br>3. Bare `high` finding without matching marker demotes to `normal` with audit note citing `R1-1` and emits the stdout diagnostic log.<br>4. Mismatched markers (e.g. marker `R1-2` for finding `R1-1@D7`) do not prevent demotion.<br>5. Exemption preservation for `withdrawn` and `dispute` findings without markers. | Provides comprehensive regression and contract coverage across the entire syntax space, preventing future regressions of the PR #349 failure mode. |
| D9 | **Implementation scope boundary.** The implementing pull request for #354 may touch `scripts/ci/review_recorder.py`, `scripts/ci/tests/review_recorder_test.sh`, `personas/skills/review-protocol.md`, `REVIEW.md`, `docs/SPEC.md`, `intent/354-recorder-demotes-every/intent.md`, and `intent/354-recorder-demotes-every/spec.md`. It may not touch `.github/workflows/**`, `scripts/ops/**`, `scripts/ci/merge_gate.sh`, other persona files under `personas/**`, or files outside `intent/354-recorder-demotes-every/`. | Enforces strict scope fences preventing unintentional modifications to merge gate orchestration, dispatch scripts, or protected persona definitions. |
| D10 | **Living specification synchronization (`docs/SPEC.md`).** During the implementation stage, `docs/SPEC.md` under `### review.policy` is updated to specify that failure-scenario presence is evaluated on normalized base finding IDs, accepting both bare and decision-cited marker syntaxes, while retaining full finding IDs in ledger rows and audit notes. | Maintains living spec fidelity with shipped behavior per repository standards. |

## Acceptance

- **AT-354-1 (D1, D2, D8)** Run `bash scripts/ci/tests/review_recorder_test.sh`: passes with exit code 0, verifying that a suffixed finding `R1-1@D7` accompanied by a bare failure-scenario marker `<!-- failure-scenario:R1-1 -->` retains `high` severity in the ledger row (`ledger-row:R1-1@D7:high:...`) with zero demotion audit notes in `$WRITES`.
- **AT-354-2 (D1, D2, D8)** Run `bash scripts/ci/tests/review_recorder_test.sh`: passes with exit code 0, verifying that a suffixed finding `R1-1@D7` accompanied by a suffixed failure-scenario marker `<!-- failure-scenario:R1-1@D7 -->` retains `high` severity in the ledger row (`ledger-row:R1-1@D7:high:...`) with zero demotion audit notes in `$WRITES`.
- **AT-354-3 (D1, D2, D8)** Run `bash scripts/ci/tests/review_recorder_test.sh`: passes with exit code 0, verifying that a bare finding `R1-1` accompanied by a bare failure-scenario marker `<!-- failure-scenario:R1-1 -->` retains `high` severity in the ledger row (`ledger-row:R1-1:high:...`) with zero demotion audit notes in `$WRITES`.
- **AT-354-4 (D1, D2, D8)** Run `bash scripts/ci/tests/review_recorder_test.sh`: passes with exit code 0, verifying that a bare finding `R1-1` accompanied by a suffixed failure-scenario marker `<!-- failure-scenario:R1-1@D7 -->` retains `high` severity in the ledger row (`ledger-row:R1-1:high:...`) with zero demotion audit notes in `$WRITES`.
- **AT-354-5 (D1, D2, D3, D5, D8)** Run `bash scripts/ci/tests/review_recorder_test.sh`: passes with exit code 0, verifying that a suffixed finding `R1-1@D7` lacking a matching failure-scenario marker is demoted to `normal` (`ledger-row:R1-1@D7:normal:...`), appends audit note `[demoted from high: missing failure_scenario marker] on R1-1@D7` to `$WRITES`, and emits `finding R1-1@D7: demoted from high to normal: missing failure_scenario marker` to stdout.
- **AT-354-6 (D1, D2, D3, D5, D8)** Run `bash scripts/ci/tests/review_recorder_test.sh`: passes with exit code 0, verifying that a bare finding `R1-1` lacking a matching failure-scenario marker is demoted to `normal` (`ledger-row:R1-1:normal:...`), appends audit note `[demoted from high: missing failure_scenario marker] on R1-1` to `$WRITES`, and emits `finding R1-1: demoted from high to normal: missing failure_scenario marker` to stdout.
- **AT-354-7 (D4, D8)** Run `bash scripts/ci/tests/review_recorder_test.sh`: passes with exit code 0, verifying that multiple findings sharing a base ID in one review block (e.g. `R1-1@D1` and `R1-1@D2`) are both satisfied by a single sibling marker `<!-- failure-scenario:R1-1 -->`, retaining `high` for both rows.
- **AT-354-8 (D7, D8)** Run `bash scripts/ci/tests/review_recorder_test.sh`: passes with exit code 0, verifying that a `high` finding lacking a failure-scenario marker bearing `peer=dispute` or `status=withdrawn` survives as `high` and is not demoted.
- **AT-354-9 (D6)** Verify `personas/skills/review-protocol.md` and `REVIEW.md` document that failure-scenario markers match on base finding IDs and accept both bare and suffixed marker forms.
- **AT-354-10 (D10)** Verify `docs/SPEC.md` under `### review.policy` specifies base ID normalization for failure-scenario matching.
- **AT-354-11 (D9)** Run `bash scripts/ci/sanitize_check.sh`, `bash scripts/ci/spec_check.sh origin/main`, and `python3 scripts/sync_agents.py --check`: all exit 0 with clean output.

## Concerns

- **Symmetric normalization versus strict syntax enforcement.** Strictly requiring reviewers to strip decision tags from failure-scenario markers or strictly requiring decision tags on both lines would introduce review format failures. Symmetric normalization (`split('@', 1)[0]` on both sides) ensures total interoperability regardless of reviewer formatting habits.
- **Unintended cross-matching of distinct findings.** Base IDs follow the convention `R<round>-<index>` (e.g. `R1-1`, `AT-R1-2`). Distinct findings within a review round have distinct numeric indices (`R1-1`, `R1-2`), so stripping decision tags `@<Dn>` cannot cause false-positive matches across distinct findings within a review block.
- **Audit note clarity.** Preserving the full finding ID in `[demoted from high: missing failure_scenario marker] on <fid>` ensures that operators and reviewers immediately see which specific finding was demoted.

## Out of scope

- Modifying the 4-tier severity policy or review funnel (governed by #267 and #291).
- Modifying merge gate conjunct evaluation in `scripts/ci/merge_gate.sh`.
- Modifying reviewer triggering or dispatch policies in `.github/workflows/unattended.yml`.
- Enabling un-executed test suites in CI workflows (tracked in #355).

## Operator decisions

None required.

Open questions: none
