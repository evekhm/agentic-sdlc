# Plan: Exclude Withdrawn Findings From Merge Gate Dispute Check

**Issue:** #508 · **Spec:** `intent/508-merge-gate-conjunct-5/spec.md` (Approved, PR #511, D1–D6, AT-508-1–AT-508-9)  
**Author:** daedalus (`evekhm-daedalus-app[bot]`)  
**Base commit:** `a811abd4967f293b5abba5851053f7d1d9405ecb` (`origin/main`, merge of spec PR #511)  
**Target branch for implementation (Odyssey):** `odyssey/508-merge-gate-conjunct-5-treats-a`

---

## 1. Executive Summary and Problem Statement

`scripts/ci/merge_gate.sh:312` extracts disputed consensus findings from the parsed consensus ledger tuple (`id:severity:status:peer`) by evaluating field 4 alone:

```bash
DISPUTED="$(awk -F: '$4 == "dispute" {print $1}' <<<"$CTUP")"
```

In the consensus tuple format parsed at line 306, field 3 represents the finding status (`open`, `fixed`, `withdrawn`), and field 4 represents the peer consensus state (`pending`, `agree`, `dispute`, `none`). When a reviewer withdraws a finding after a peer dispute, the finding status transitions to `withdrawn`, but the peer consensus column historically records the interaction (`withdrawn:dispute`).

Because line 312 inspects field 4 (`$4 == "dispute"`) without checking field 3 (`status`), it evaluates withdrawn findings as active disputes. This causes three distinct check failures:
1. **Line 324 (Conjunct 5 failure):** Evaluates conjunct (5) as false (`WHY[5]="dispute on: ..."`) despite consensus agreement having been reached through retraction.
2. **Line 374 (Atlas carry-forward denial):** Rejects Atlas carry-forward under Decision #64 D7 condition (iv) (`WHY[3]="atlas cannot carry forward: dispute (D7 (iv))"`).
3. **Line 557 (Spurious escalation at round cap):** At `review:3`, evaluates `DISPUTED` as non-empty and escalates with reason `dispute-at-cap`, recording `refusal:dispute-at-cap` on the loop ledger and flipping the issue label to `status:review-stuck`.

This defect blocked PR #500 (implementing #372) on gate run 35159849478 where ten of eleven conjuncts were true, and the sole blocking row was `<!-- ledger-row:R1-6@none:normal:withdrawn:dispute -->`.

This plan details the implementation to update line 312 in `scripts/ci/merge_gate.sh` to filter out findings with status `withdrawn`:

```bash
DISPUTED="$(awk -F: '$3 != "withdrawn" && $4 == "dispute" {print $1}' <<<"$CTUP")"
```

The filtered `DISPUTED` set is consumed uniformly across conjunct (5), Atlas carry-forward, and round-cap escalation. Hermetic regression tests in `scripts/ci/tests/merge_gate_test.sh` verify that `withdrawn:dispute` passes conjunct (5), permits carry-forward, and avoids escalation, while active disputes (`open:dispute` and `fixed:dispute`) continue to block conjunct (5).

---

## 2. Scope, Persona Boundaries, and Grants

### Persona Authority Boundaries

| Actor | Stage | Authority / Paths Touched | Role in Issue #508 |
|---|---|---|---|
| **athena** | intake, plan, design | `intent/**` | Authored `intent.md` and approved `spec.md` (merged in PR #511). |
| **daedalus** | build | `intent/**`, `scripts/*/tests/**` | Authors `plan.md` and commits contract test suite `scripts/ci/tests/merge_gate_withdrawn_dispute_contract_test.sh`. Daedalus **never** edits production code. |
| **odyssey** | implement | `scripts/ci/merge_gate.sh`, `scripts/ci/tests/merge_gate_test.sh`, `docs/SPEC.md`, `CHANGELOG.md` | Executes Tasks T2 through T6 branching from the commit merging this plan, turns contract tests green, updates living spec, and verifies all CI gates. |
| **themis** | autonomous merge | GitHub Actions (`merge-gate.yml`) | Autonomously gates and merges pull requests upon consensus. |
| **argus / atlas** | review | comments only | Review pull requests against spec and plan. |

### Deep Review Grant Assessment (DEEP-1, DEEP-3, DEEP-5)

- **Build PR (Daedalus):**
  - **DEEP-1 (trust-bearing paths):** Touches `scripts/ci/tests/merge_gate_withdrawn_dispute_contract_test.sh`, which falls under `config/execution.yaml` `assigned_when.paths` (`scripts/ci/**`).
  - **Action:** Daedalus applies `deep-review` label via `scripts/ops/post.sh <pr> --as daedalus --add-label deep-review`.
- **Implementation PR (Odyssey):**
  - **DEEP-1 (trust-bearing paths):** Touches `scripts/ci/merge_gate.sh` and `scripts/ci/tests/merge_gate_test.sh`.
  - **DEEP-3 (privileged / irreversible operations):** Modifies `scripts/ci/merge_gate.sh`, the repository's sole autonomous merger script executing `gh pr merge`.
  - **DEEP-5 (escalated risk tier):** Task T2 (`merge_gate.sh`) alters core consensus evaluation and round-cap escalation. Marked `risk: high`.
  - **Action:** Odyssey applies the `deep-review` grant when opening the PR per `scripts/ops/post.sh <pr> --as odyssey --add-label deep-review`.

### Living Spec and Changelog Obligations

- **Build PR (Daedalus):**
  - `Spec-impact: none — build stage contract tests and plan only; living spec upsert is task of implementation PR`
  - `Changelog: none — build stage contract tests and plan only; changelog entry is task of implementation PR`
- **Implementation PR (Odyssey):**
  - Updates `docs/SPEC.md` under `### loop.autonomous` (around line 1444) documenting the exclusion of withdrawn findings from the dispute check in conjunct (5), Atlas carry-forward condition (iv), and round-cap escalation (D5, AT-508-8).
  - Updates `CHANGELOG.md` under the current release / unreleased section documenting the bug fix and operator impact (AT-508-7).

### Strict File Manifest Partitioning (D6)

The implementing change is strictly confined to:
1. `scripts/ci/merge_gate.sh`
2. `scripts/ci/tests/merge_gate_test.sh`
3. `docs/SPEC.md`
4. `CHANGELOG.md`
5. `intent/508-merge-gate-conjunct-5/plan.md` (read-only reference; updated only if plan sync occurs)

**Forbidden Paths (Untouched per D6):**
- `scripts/ci/review_recorder.py`: consensus derivation and label sync logic are preserved unchanged.
- `scripts/ci/review_recorder.sh`: entry point preserved unchanged.
- `scripts/ci/tests/review_recorder_test.sh`: recorder test suite preserved unchanged.
- `scripts/ci/escalate.sh`: escalation execution logic preserved unchanged.
- `scripts/ci/lifecycle_advance.sh`: ladder transitions preserved unchanged.
- `.github/workflows/**`: workflow definitions preserved unchanged.
- `personas/**`: persona instructions preserved unchanged.
- `config/**`: execution configuration preserved unchanged.

---

## 3. Detailed Architectural Calls

### P1 · Filter Out Status `withdrawn` from `DISPUTED` at Line 312 (D1)
- In `scripts/ci/merge_gate.sh:312`:
  ```bash
  DISPUTED="$(awk -F: '$3 != "withdrawn" && $4 == "dispute" {print $1}' <<<"$CTUP")"
  ```
- Rationale: A finding with status `withdrawn` represents a reviewer conceding and retracting the finding. No disagreement remains. In contrast, `open:dispute` (active disputed finding) and `fixed:dispute` (dispute over whether a fix is adequate) must remain in `DISPUTED`.

### P2 · Uniform Consumption Across All Downstream Merge Gate Checks (D2)
- Line 324: `if [ -n "$DISPUTED" ]; then WHY[5]="dispute on: $(tr '\n' ' ' <<<"$DISPUTED")"`
- Line 370: `elif [ -n "$DISPUTED" ]; then ... WHY[3]="atlas cannot carry forward: dispute (D7 (iv))"`
- Line 557: `elif [ -n "$DISPUTED" ]; then reason="dispute-at-cap"`
- No separate or secondary dispute scan is introduced. All three locations consume the single filtered `DISPUTED` set.

### P3 · Preservation of Severity-Agnostic Matching for Active Disputes (D3)
- The filter in line 312 checks status alone (`$3 != "withdrawn"`). It does not filter field 2 (`severity`).
- Active disputes on `normal` or `suggestion` findings continue to populate `DISPUTED` and fail conjunct (5). Policy regarding severity filtering of disputes is owned by issue #503; #508 strictly bounds scope to retracted findings.

### P4 · Hermetic Regression Suite Expansion (D4)
- Extend `scripts/ci/tests/merge_gate_test.sh` with four explicit test scenarios:
  1. `MG-13g`: A consensus ledger containing `R1-1:normal:withdrawn:dispute` evaluates conjunct (5) as true (`consensus axis agreed, no dispute`) and proceeds to merge.
  2. `MG-13h`: A consensus ledger containing `R1-1:high:fixed:dispute` evaluates conjunct (5) as false (`dispute on: R1-1`) and does not merge.
  3. `MG-12f`: A fixture where Atlas has an older verdict and no new comments or mentions, but the consensus ledger contains `R1-1:normal:withdrawn:dispute`, satisfies condition (iv) of Decision #64 D7 and carries forward Atlas's verdict.
  4. `MG-18b`: A fixture at round cap `review:3` whose consensus ledger contains `R1-1:normal:withdrawn:dispute` does not emit loop-ledger marker `refusal:dispute-at-cap` and does not escalate with reason `dispute-at-cap`.

---

## 4. Micro-Stepped Tasks

### Task T1: Commit Hermetic Contract Test Suite in `scripts/ci/tests/merge_gate_withdrawn_dispute_contract_test.sh`
- **Owner:** daedalus (Build stage)
- **Files touched:** `scripts/ci/tests/merge_gate_withdrawn_dispute_contract_test.sh`
- **Decisions implemented:** D1, D2, D3, D4, D5, D6
- **Acceptance criteria proven:** AT-508-1 through AT-508-8
- **Description:** Implement standalone contract test suite validating:
  1. `scripts/ci/merge_gate.sh:312` filters out withdrawn findings from `DISPUTED` (D1, AT-508-1).
  2. Conjunct (5) evaluates to true on `withdrawn:dispute` (D1, D4, AT-508-2).
  3. Atlas carries forward under Decision #64 D7 condition (iv) on `withdrawn:dispute` (D2, D4, AT-508-5).
  4. Round cap `review:3` does not escalate with reason `dispute-at-cap` on `withdrawn:dispute` (D2, D4, AT-508-6).
  5. `scripts/ci/tests/merge_gate_test.sh` includes regression tests for `fixed:dispute` (D1, D3, D4, AT-508-4).
  6. `scripts/ci/tests/merge_gate_test.sh` includes regression tests for `withdrawn:dispute` (D4, AT-508-2, AT-508-5, AT-508-6).
  7. `docs/SPEC.md` records living spec update for withdrawn findings (D5, AT-508-8).
- **Done-When:**
  Running `bash scripts/ci/tests/merge_gate_withdrawn_dispute_contract_test.sh` executes all 7 scenarios, reports clean assertion failures (`Total: 7, Passed: 0, Failed: 7`) without syntax or runtime errors, and exits with code 1.

---

### Task T2: Exclude Withdrawn Findings from `DISPUTED` in `scripts/ci/merge_gate.sh`
- **Owner:** odyssey (Implement stage)
- **Risk:** high (DEEP-3, DEEP-5: alters core merge gate consensus logic and escalation triggers)
- **Files touched:** `scripts/ci/merge_gate.sh`
- **Decisions implemented:** D1, D2, D3
- **Acceptance criteria proven:** AT-508-1, AT-508-2, AT-508-3, AT-508-4, AT-508-5, AT-508-6
- **Step-by-step diff description:**
  1. In `scripts/ci/merge_gate.sh`, locate line 312:
     ```bash
     DISPUTED="$(awk -F: '$4 == "dispute" {print $1}' <<<"$CTUP")"
     ```
  2. Update the awk filter condition to require `$3 != "withdrawn"`:
     ```bash
     DISPUTED="$(awk -F: '$3 != "withdrawn" && $4 == "dispute" {print $1}' <<<"$CTUP")"
     ```
  3. Verify that lines 324, 370, and 557 consume `DISPUTED` directly without introducing separate scans (D2).
- **Done-When:**
  `grep -n 'DISPUTED=' scripts/ci/merge_gate.sh` matches `awk -F: '$3 != "withdrawn" && $4 == "dispute" {print $1}' <<<"$CTUP"`, and contract test assertions 1, 2, 3, and 4 pass.

---

### Task T3: Add Regression Test Cases to `scripts/ci/tests/merge_gate_test.sh`
- **Owner:** odyssey (Implement stage)
- **Files touched:** `scripts/ci/tests/merge_gate_test.sh`
- **Decisions implemented:** D1, D2, D3, D4
- **Acceptance criteria proven:** AT-508-2, AT-508-3, AT-508-4, AT-508-5, AT-508-6, AT-508-7
- **Step-by-step diff description:**
  1. In `scripts/ci/tests/merge_gate_test.sh` under `banner "MG-13 ..."` (following `MG-13f`):
     ```bash
     mk_green
     comments_fixture 123 "$(comment "$MERGER" "$(consensus_ledger 123 "$H" "$H" "R1-1:normal:withdrawn:dispute")" 2026-01-04T00:00:00Z 826)"
     run "MG-13g: withdrawn dispute row passes conjunct (5) and merges" 123
     has "conjunct (5): true" "MG-13g: withdrawn dispute passes conjunct (5)"
     merged "MG-13g"

     mk_green
     comments_fixture 123 "$(comment "$MERGER" "$(consensus_ledger 123 "$H" "$H" "R1-1:high:fixed:dispute")" 2026-01-04T00:00:00Z 827)"
     run "MG-13h: fixed dispute row fails conjunct (5)" 123
     has "conjunct (5): false" "MG-13h: a fixed dispute fails the axis"
     not_merged "MG-13h"
     ```
  2. Under `banner "MG-12 ..."` (following `MG-12e`):
     ```bash
     mk_green
     comments_fixture 123 "$(comment "$MERGER" "$(consensus_ledger 123 "$H" "$H0" "R1-1:normal:withdrawn:dispute")" 2026-01-04T00:00:00Z 828)"
     run "MG-12f: atlas at older head with withdrawn dispute carries forward" 123
     has "conjunct (3): true" "MG-12f: atlas carries forward with withdrawn dispute (D7 (iv))"
     merged "MG-12f"
     ```
  3. Under `banner "MG-18 ..."` (following `MG-18`):
     ```bash
     mk_green; PR_LABELS='["review:3"]'; pr_fixture 123
     comments_fixture 123 "$(comment "$MERGER" "$(consensus_ledger 123 "$H" "$H" "R1-1:normal:withdrawn:dispute")" 2026-01-04T00:00:00Z 829)"
     run "MG-18b: at round cap review:3 a withdrawn dispute does not escalate dispute-at-cap" 123
     not_wrote "loop-ledger-row: refusal:dispute-at-cap" "MG-18b: no dispute-at-cap refusal row"
     not_wrote "<!-- escalation:status:implementing:dispute-at-cap" "MG-18b: no dispute-at-cap escalation marker"
     ```
- **Done-When:**
  `bash scripts/ci/tests/merge_gate_test.sh` exits 0 with all test assertions passing, and contract test assertions 5 and 6 pass.

---

### Task T4: Update Living Spec in `docs/SPEC.md`
- **Owner:** odyssey (Implement stage)
- **Files touched:** `docs/SPEC.md`
- **Decisions implemented:** D5
- **Acceptance criteria proven:** AT-508-8
- **Step-by-step diff description:**
  In `docs/SPEC.md` under `### loop.autonomous` (around line 1444), update the sentence describing conjunct (5) and Atlas carry-forward to specify that findings with status `withdrawn` are excluded from the dispute check in conjunct (5), Atlas carry-forward condition (iv), and round-cap escalation.
- **Done-When:**
  Contract test assertion 7 passes, and `bash scripts/ci/spec_check.sh origin/main <pr-body>` exits 0.

---

### Task T5: Update Release Notes in `CHANGELOG.md`
- **Owner:** odyssey (Implement stage)
- **Files touched:** `CHANGELOG.md`
- **Decisions implemented:** D6
- **Description:** Document the bug fix in `CHANGELOG.md` under the current release / unreleased section per #410 changelog gate standards:
  Record that `scripts/ci/merge_gate.sh:312` filters out findings with status `withdrawn` from the dispute check, preventing retracted findings from falsely blocking conjunct (5), denying Atlas carry-forward, or triggering spurious `dispute-at-cap` escalations.
- **Done-When:**
  `bash scripts/ci/changelog_check.sh origin/main <pr-body>` exits 0.

---

### Task T6: Verify Contract Tests and Full Test Suite Green
- **Owner:** odyssey (Implement stage)
- **Files touched:** None
- **Decisions implemented:** D1–D6
- **Acceptance criteria proven:** AT-508-1 through AT-508-9
- **Description:** Run all verification gates:
  1. `bash scripts/ci/tests/merge_gate_withdrawn_dispute_contract_test.sh` exits 0 with 7/7 passed.
  2. `bash scripts/ci/tests/merge_gate_test.sh` exits 0 with all scenarios passing.
  3. `bash scripts/ci/spec_check.sh origin/main <pr-body>` exits 0.
  4. `bash scripts/ci/changelog_check.sh origin/main <pr-body>` exits 0.
  5. `git diff --name-only origin/main` matches only allowed manifest files (AT-508-9).
- **Done-When:**
  All verification commands exit 0.

---

## 5. Traceability Matrix

| Decision ID | Summary | Plan Tasks | Contract Assertion / Acceptance Criteria |
|---|---|---|---|
| **D1** | Exclude withdrawn status from `DISPUTED` scan at line 312 | T1, T2, T3 | AT-508-1, AT-508-2, AT-508-3, AT-508-4 (Assertions 1, 2) |
| **D2** | Uniform consumption of `DISPUTED` across conjunct (5), carry-forward, and escalation | T1, T2, T3 | AT-508-5, AT-508-6 (Assertions 3, 4) |
| **D3** | Severity-agnostic dispute matching for active findings (`open` and `fixed`) | T1, T2, T3 | AT-508-3, AT-508-4 (Assertion 5) |
| **D4** | Hermetic regression test coverage in `merge_gate_test.sh` | T1, T3 | AT-508-2, AT-508-3, AT-508-4, AT-508-5, AT-508-6, AT-508-7 (Assertions 2, 5, 6) |
| **D5** | Living spec update obligation in `docs/SPEC.md` | T1, T4 | AT-508-8 (Assertion 7) |
| **D6** | Scope boundary and file manifest enforcement | T1, T2, T3, T4, T5, T6 | AT-508-9 |

