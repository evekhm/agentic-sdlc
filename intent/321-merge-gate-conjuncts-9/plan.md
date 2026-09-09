# Plan: Merge Gate Rung-1 Resolution for Intent Pull Requests

**Issue:** #321 · **Spec:** `intent/321-merge-gate-conjuncts-9/spec.md` (Approved, D1–D6, AT-1–AT-7)  
**Author:** daedalus (`evekhm-daedalus-app[bot]`)  
**Base commit:** `9a3c4f1ea01b547516a15f0d428ee6789675a233`  
**Target branch for implementation (Odyssey):** `odyssey/321-merge-gate-conjuncts-9`

---

## 1. Executive Summary and Problem Statement

When an initial intent pull request (such as PRs #315 and #316 for Issue #265) is evaluated by `scripts/ci/merge_gate.sh`, the merge gate declines evaluation with:
```
#<issue> carries no ranked status label (none)
```
Consequently, conjunct (9) (`intent/.../intent.md present at $HEAD`) and conjunct (10) (`rung 1 > highest merged rung 0`) evaluate to `false`. Even with green CI checks, reviewer consensus, empty blocking set, and no hold markers, the pull request cannot merge autonomously.

### Root Cause
1. `scripts/ci/merge_gate.sh` derives the issue status label via:
   ```bash
   STATUS="$(grep '^status:' <<<"$ISSUE_LABELS" || true)"
   ```
2. In accordance with AGENTS.md ("Lifecycle stages"), new issues entering the autonomous loop carry only `intent:new` and no `status:*` label until intent is merged.
3. Because `STATUS` is empty, `idx="$(rung_of "$STATUS")"` evaluates to `null`.
4. In lines 343–346 of `scripts/ci/merge_gate.sh`, the empty `STATUS` branch immediately fails conjuncts 9 and 10 with `#$ISSUE carries no ranked status label (${STATUS:-none})`.
5. In line 220 of `scripts/ci/merge_gate.sh`, budget refusal evaluation logs `refusal:budget 0` instead of identifying rung 1.

The approved spec (`intent/321-merge-gate-conjuncts-9/spec.md`, merged in PR #332) specifies that when `STATUS` is empty and the issue carries label `intent:new`, the issue resolves as stage index `idx=0` (`status:planning`, ladder rung `RUNG=1`, artifact `intent.md`).

---

## 2. Scope and Persona Boundaries

| Actor | Stage | Authority / Files Touched | Role in Issue #321 |
|---|---|---|---|
| **athena** | plan / design | `intent/**` | Authored `intent.md` and approved `spec.md` (PR #332). |
| **daedalus** | build | `intent/**`, `scripts/*/tests/**` | Authors `plan.md` and commits hermetic failing contract tests (scenarios MG-37..MG-42) in `scripts/ci/tests/merge_gate_test.sh`. Daedalus **never** edits production code (`scripts/ci/merge_gate.sh` or `docs/SPEC.md`). |
| **odyssey** | implement | `scripts/ci/merge_gate.sh`, `docs/SPEC.md` | Implements the plan at pinned base commit `9a3c4f1ea01b547516a15f0d428ee6789675a233`, turning contract tests green, updating `docs/SPEC.md`, and passing all CI gates. |
| **themis** | autonomous merge | GitHub Actions (`merge-gate.yml`) | Evaluates conjuncts and autonomously merges pull requests. |
| **argus / atlas** | review | comments only | Review pull requests against spec and plan. |

---

## 3. The Calls This Plan Makes

### P1 · Rung derivation for `intent:new` (D1, D5)
In `scripts/ci/merge_gate.sh`, the stage derivation for conjuncts 9 and 10 must recognize `intent:new` when `STATUS` is empty:
```bash
idx="$(rung_of "$STATUS")"
if [ -z "$STATUS" ] && grep -Fxq "intent:new" <<<"$ISSUE_LABELS"; then
    idx=0
fi
if [ -z "$STATUS" ] && ! grep -Fxq "intent:new" <<<"$ISSUE_LABELS" || [ "$idx" = "null" ]; then
    WHY[9]="#$ISSUE carries no ranked status label (${STATUS:-none})"; WHY[10]="${WHY[9]}"
else
    RUNG=$((idx + 1))
    ARTIFACT="$(jq -r ".stages[$idx].artifact // empty" "$LIFECYCLE_JSON")"
...
```
This guarantees:
- If a single `status:*` label is present (e.g. `status:spec`), `idx` is derived from `STATUS`, taking precedence over `intent:new` even if `intent:new` was not yet removed (D5).
- If `STATUS` is empty and `intent:new` is present, `idx=0`, resolving to `RUNG=1` and `ARTIFACT="intent.md"` (D1).
- If `STATUS` is empty and `intent:new` is absent (e.g. `bug` label or empty labels), the issue fails closed with `#$ISSUE carries no ranked status label (none)` (D1, D5).
- If `STATUS` carries an unranked status label (e.g. `status:unknown`), `idx` is `null`, and the issue fails closed with `#$ISSUE carries no ranked status label (status:unknown)` (D5).

### P2 · Artifact verification for `intent.md` in Conjunct 9 (D2)
When `ARTIFACT="intent.md"`:
- `merge_gate.sh` queries `repos/$R/contents/intent?ref=$HEAD` and verifies that exactly one directory matching `intent/$ISSUE-*/` exists at `$HEAD`.
- It fetches `repos/$R/contents/intent/$dirs/$ARTIFACT?ref=$HEAD` and verifies that content exists and is non-empty.
- In `merge_gate.sh`, lines 359–368:
  ```bash
  elif [ "$ARTIFACT" = "spec.md" ]; then
      ...
  else
      C[9]=1; WHY[9]="intent/$dirs/$ARTIFACT present at $HEAD"
  fi
  ```
  Any non-empty `intent.md` automatically falls into the `else` branch, setting `C[9]=1` and `WHY[9]="intent/$dirs/intent.md present at $HEAD"`. Unlike `spec.md`, `intent.md` requires no `Status: Approved` or `Open questions: none` header status markers (D2).

### P3 · Monotonicity enforcement for Rung 1 in Conjunct 10 (D3)
Lines 349–350 in `scripts/ci/merge_gate.sh`:
```bash
if [ "$RUNG" -gt "$HIGHEST_MERGED_RANK" ]; then C[10]=1; WHY[10]="rung $RUNG > highest merged rung $HIGHEST_MERGED_RANK"
else WHY[10]="rung $RUNG is not above highest merged rung $HIGHEST_MERGED_RANK (D14)"; fi
```
When `RUNG=1`:
- If `HIGHEST_MERGED_RANK=0` (empty loop ledger), `1 > 0` is true -> `C[10]=1; WHY[10]="rung 1 > highest merged rung 0"`.
- If `HIGHEST_MERGED_RANK >= 1` (a prior rung has already merged), `1 > 1` is false -> `C[10]=0; WHY[10]="rung 1 is not above highest merged rung $HIGHEST_MERGED_RANK (D14)"`, performing zero writes.

### P4 · Budget refusal derivation at Rung 1 (D4)
In `scripts/ci/merge_gate.sh`, lines 218–225:
```bash
if [ -n "$over_budget" ]; then
    log "Decline: $over_budget"
    idx="$(rung_of "$STATUS")"
    if [ -z "$STATUS" ] && grep -Fxq "intent:new" <<<"$ISSUE_LABELS"; then
        idx=0
    fi
    [ "$idx" != "null" ] && rung=$((idx + 1)) || rung=0
    ledger_append "refusal:budget" "$rung"
    if [ "$AUTONOMOUS" = "true" ]; then escalate budget
    else log "autonomous_merge is false — refusal recorded, no escalation (D18)"; fi
    finish "no merge for #$TARGET"
fi
```
When an issue carrying `intent:new` exceeds budget bounds (`max_cost_usd_per_issue` or `max_rung_dispatches_per_issue`), `rung` evaluates to `1`, logging `refusal:budget 1` rather than `refusal:budget 0` (D4).

### P5 · Label precedence and safety guards (D5)
- Pre-existing guard at line 213 remains unchanged: multiple `status:*` labels decline as corrupted state:
  ```bash
  [ "$n_status" -le 1 ] || decline "#$ISSUE carries more than one status:* label ($(tr '
' ' ' <<<"$STATUS")) — corrupted state, nothing written"
  ```
- Single `status:*` label takes strict precedence over `intent:new`.
- Unranked issues fail closed.

### P6 · Living spec upsert (D6, AT-7)
In `docs/SPEC.md`, under `### loop.autonomous` (lines 1103–1109), the living spec is updated to document rung-1 resolution for `intent:new` issues, explicit label precedence, fail-closed unranked handling, and budget refusal logging at rung 1.

---

## 4. Micro-Stepped Tasks

### Task T1: Commit Contract Test Scenarios MG-37..MG-42
- **Owner:** daedalus (Build stage)
- **File touched:** `scripts/ci/tests/merge_gate_test.sh`
- **Decisions implemented:** D1, D2, D3, D4, D5
- **Acceptance criteria proven:** AT-1, AT-2, AT-3, AT-4, AT-5, AT-6
- **Description:** Append scenarios MG-37 through MG-42 to `scripts/ci/tests/merge_gate_test.sh`:
  1. `MG-37` (AT-1, D1/D2/D3): PR for issue with `intent:new`, non-empty `intent.md` present at `$HEAD`, `HIGHEST_MERGED_RANK=0` -> asserts `conjunct (9): true`, `conjunct (10): true`, autonomous merge succeeds.
  2. `MG-38` (AT-2, D1/D2): PR for issue with `intent:new`, `intent.md` absent at `$HEAD` -> asserts `conjunct (9): false`, `intent/456-thing/intent.md is absent at $HEAD`, merge does not occur.
  3. `MG-39` (AT-3, D1/D3): PR for issue with `intent:new`, `HIGHEST_MERGED_RANK=1` in loop ledger -> asserts `conjunct (9): true`, `conjunct (10): false`, `rung 1 is not above highest merged rung 1 (D14)`, zero writes.
  4. `MG-40` (AT-4, D1/D5): PR for issue with no `status:*` label and no `intent:new` (e.g. `bug`) -> asserts `conjunct (9): false`, `conjunct (10): false`, `#456 carries no ranked status label (none)`, zero writes.
  5. `MG-41` (AT-5, D4): PR for issue with `intent:new` exceeding cost bound ($60 > $50) -> asserts ledger refusal row records `refusal:budget 1`, merge does not occur.
  6. `MG-42` (AT-6, D5): PR for issue with both `status:spec` and `intent:new` -> asserts evaluated under `status:spec` (rung 2, `spec.md`), `conjunct (9): true`, `conjunct (10): true`, merges autonomously.
- **Verification / Done-When:**
  Running `bash scripts/ci/tests/merge_gate_test.sh` against unmodified `scripts/ci/merge_gate.sh` fails on scenario MG-37 with test assertion failure:
  `FAIL: MG-37 (D1, D2): intent.md present at HEAD passes conjunct 9 (expected to find: conjunct (9): true)`
  (Exit code 1, failures not errors, proving tests are RED).

---

### Task T2: Implement Budget Bounds Rung-1 Derivation
- **Owner:** odyssey (Implement stage)
- **File touched:** `scripts/ci/merge_gate.sh`
- **Decisions implemented:** D4
- **Acceptance criteria proven:** AT-5 (MG-41)
- **Step-by-step diff:**
  In `scripts/ci/merge_gate.sh`, update lines 218–222:
  ```diff
   if [ -n "$over_budget" ]; then
       log "Decline: $over_budget"
  -    idx="$(rung_of "$STATUS")"; [ "$idx" != "null" ] && rung=$((idx + 1)) || rung=0
  +    idx="$(rung_of "$STATUS")"
  +    if [ -z "$STATUS" ] && grep -Fxq "intent:new" <<<"$ISSUE_LABELS"; then
  +        idx=0
  +    fi
  +    [ "$idx" != "null" ] && rung=$((idx + 1)) || rung=0
       ledger_append "refusal:budget" "$rung"
  ```
- **Done-When:** Scenario MG-41 passes; issues carrying only `intent:new` record `refusal:budget 1` when exceeding limits.

---

### Task T3: Implement Conjuncts 9 and 10 Rung-1 Derivation and Precedence
- **Owner:** odyssey (Implement stage)
- **File touched:** `scripts/ci/merge_gate.sh`
- **Decisions implemented:** D1, D2, D3, D5
- **Acceptance criteria proven:** AT-1, AT-2, AT-3, AT-4, AT-6 (MG-37, MG-38, MG-39, MG-40, MG-42)
- **Step-by-step diff:**
  In `scripts/ci/merge_gate.sh`, update lines 342–346:
  ```diff
   # --- conjuncts 9 and 10 ---------------------------------------------------------------
   RUNG=0; ARTIFACT=""
   idx="$(rung_of "$STATUS")"
  -if [ -z "$STATUS" ] || [ "$idx" = "null" ]; then
  +if [ -z "$STATUS" ] && grep -Fxq "intent:new" <<<"$ISSUE_LABELS"; then
  +    idx=0
  +fi
  +if [ -z "$STATUS" ] && ! grep -Fxq "intent:new" <<<"$ISSUE_LABELS" || [ "$idx" = "null" ]; then
       WHY[9]="#$ISSUE carries no ranked status label (${STATUS:-none})"; WHY[10]="${WHY[9]}"
   else
  ```
- **Done-When:**
  Scenarios MG-37, MG-38, MG-39, MG-40, and MG-42 pass. `scripts/ci/tests/merge_gate_test.sh` exits 0 with all 42 scenarios passing green.

---

### Task T4: Update Living Spec in docs/SPEC.md
- **Owner:** odyssey (Implement stage)
- **File touched:** `docs/SPEC.md`
- **Decisions implemented:** D6
- **Acceptance criteria proven:** AT-7
- **Step-by-step diff:**
  In `docs/SPEC.md`, under `### loop.autonomous` (around line 1108):
  ```diff
   The gate merges only when all eleven D5 conjuncts hold at the pull request's current head, among them: both reviewers reviewed that head (Atlas may carry forward under D7), the blocking set is empty, the consensus axis is agreed, neither `hold` nor `blocked` is present, the merger is a different identity from the author, the target rung outranks every rung the loop ledger records, and the ledger's head marker is present. With the flag off the same evaluation runs and nothing is written.
  +When evaluating conjuncts 9 and 10, an issue carrying only `intent:new` with no `status:*` label resolves as ladder rung 1 (`status:planning`, artifact `intent.md`), enabling initial intent pull requests to merge autonomously once reviewer consensus is reached (#321, D1); if an explicit single `status:*` label is present alongside `intent:new`, the `status:*` label takes precedence (D5); unranked issues lacking both `status:*` and `intent:new` fail closed (D5). Budget refusals on `intent:new` issues record `refusal:budget 1` (D4).
  ```
- **Done-When:**
  Running `bash scripts/ci/spec_check.sh origin/main <pr-body-file>` exits 0.

---

### Task T5: Integration Testing and CI Gates Verification
- **Owner:** odyssey (Implement stage)
- **Files touched:** none
- **Decisions implemented:** D1–D6
- **Acceptance criteria proven:** AT-1 through AT-7
- **Step-by-step verification commands:**
  1. `bash scripts/ci/tests/merge_gate_test.sh` -> PASS (all 42 scenarios passed)
  2. `python3 scripts/ops/execution.py --check` -> PASS
  3. `bash scripts/ops/tests/execution_test.sh` -> PASS
  4. `bash scripts/ops/tests/placement_test.sh` -> PASS
  5. `bash scripts/ops/tests/post_test.sh` -> PASS
  6. `bash scripts/ci/tests/lifecycle_advance_test.sh` -> PASS
  7. `python3 scripts/sync_agents.py --check` -> PASS
  8. `bash scripts/ci/sanitize_check.sh` -> PASS
  9. `bash scripts/ci/spec_check.sh origin/main <pr-body-file>` -> PASS
- **Done-When:** All CI checks and local test suites pass with zero warnings and zero failures.

---

## 5. Traceability Matrix

| Acceptance Test | Decision IDs | Test Scenario | Implementing Task | Verification Proof |
|---|---|---|---|---|
| **AT-1** | D1, D2, D3 | `MG-37` in `merge_gate_test.sh` | T1 (test), T3 (code) | `intent:new` issue with `intent.md` passes conjuncts 9 & 10, merges autonomously |
| **AT-2** | D1, D2 | `MG-38` in `merge_gate_test.sh` | T1 (test), T3 (code) | `intent:new` issue with absent `intent.md` fails conjunct 9 (`is absent at $HEAD`) |
| **AT-3** | D1, D3 | `MG-39` in `merge_gate_test.sh` | T1 (test), T3 (code) | `intent:new` issue with `HIGHEST_MERGED_RANK >= 1` fails conjunct 10 (`is not above highest merged rung 1 (D14)`) |
| **AT-4** | D1, D5 | `MG-40` in `merge_gate_test.sh` | T1 (test), T3 (code) | Issue without `status:*` and without `intent:new` fails conjuncts 9 & 10 (`carries no ranked status label (none)`) |
| **AT-5** | D4 | `MG-41` in `merge_gate_test.sh` | T1 (test), T2 (code) | Issue with `intent:new` over budget writes `refusal:budget 1` to loop ledger |
| **AT-6** | D5 | `MG-42` in `merge_gate_test.sh` | T1 (test), T3 (code) | Issue with `status:spec` and `intent:new` evaluates under `status:spec` (rung 2, `spec.md`) |
| **AT-7** | D6 | N/A | T4 (living spec), T5 | `docs/SPEC.md` updated under `ci.merge-gate` / `### loop.autonomous`; `spec_check.sh` passes |

---

## 6. Handoff to Odyssey (Implement Rung)

- **Branch:** `odyssey/321-merge-gate-conjuncts-9`
- **Base commit:** `9a3c4f1ea01b547516a15f0d428ee6789675a233` (or the commit merging this plan)
- **PR Title:** `feat(#321): merge gate conjuncts 9/10 rung-1 resolution for intent:new`
- **PR Body Requirements:**
  - Closing keyword: `Refs #321` or `Closes #321`
  - Living spec sync: diff includes `docs/SPEC.md` update
  - Summary of implemented tasks T2, T3, T4
  - Proof that all 42 scenarios in `scripts/ci/tests/merge_gate_test.sh` pass green
