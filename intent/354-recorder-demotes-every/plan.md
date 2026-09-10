# Plan: Normalize Finding Base IDs for Failure-Scenario Matching in Review Recorder

**Issue:** #354 · **Spec:** `intent/354-recorder-demotes-every/spec.md` (Approved, D1–D10, AT-354-1–AT-354-11)  
**Author:** daedalus (`evekhm-daedalus-app[bot]`)  
**Base commit:** `7a8152836a7cfdb2a8ffca6532c0b9e5c830a99a`  
**Target branch for implementation (Odyssey):** `odyssey/354-recorder-demotes-every-high-finding-to`

---

## 1. Executive Summary and Problem Statement

Under `review.policy` (`docs/SPEC.md:544-577`, PR #267, PR #291), the review system enforces four severity tiers (`security`, `high`, `normal`, `suggestion`). Every `high` finding requires an immediate sibling `<!-- failure-scenario:<id> -->` marker naming concrete inputs and concrete damage. Any `high` finding lacking this marker is demoted to `normal` by the consensus recorder (`scripts/ci/review_recorder.py:304-307`).

In production, `scripts/ci/review_recorder.py` demotes **every** `high` finding to `normal`, even when reviewers provide valid sibling failure-scenario markers. Because `high` findings are the primary blocking tier that prevents autonomous merge of defects, demoting them to `normal` leaves the pull request with zero blocking findings, allowing the autonomous merge gate (`scripts/ci/merge_gate.sh`) to auto-merge broken pull requests into `main` (as observed live on PR #349 at 2026-09-10T04:51:19Z).

### Root Cause
1. In `scripts/ci/review_recorder.py:280`:
   ```python
   failure_scenarios = set(re.findall(r'<!-- failure-scenario:([A-Za-z0-9@-]+) -->', block))
   ```
   When a reviewer writes `<!-- failure-scenario:R1-1 -->`, `failure_scenarios` contains `{"R1-1"}`.
2. In `scripts/ci/review_recorder.py:283-287`:
   ```python
   finding_matches = re.finditer(r'<!-- finding:([A-Za-z0-9@-]+):([A-Za-z0-9]+):([A-Za-z0-9]+):([A-Za-z0-9]+) -->', block)
   fid = fm.group(1)
   ```
   Per review protocol, reviewers cite spec decisions on finding lines (e.g. `R1-1@D7`). Thus `fid` becomes `"R1-1@D7"`.
3. In `scripts/ci/review_recorder.py:304-307`:
   ```python
   if fsev == "high" and fpr != "dispute" and fst != "withdrawn":
       if fid not in failure_scenarios:
           fsev = "normal"
           audit_notes.append(f"[demoted from high: missing failure_scenario marker] on {fid}")
   ```
   `"R1-1@D7" not in {"R1-1"}` evaluates to `True`. The demotion fires falsely on every decision-cited finding.
4. **Diagnostic logging absence**: In `review_recorder.py:306`, demotions are noted only in `audit_notes` appended to the markdown table, with zero stdout logging during recorder execution, making demotions silent in CI step logs.
5. **Protocol documentation ambiguity**: `personas/skills/review-protocol.md` and `REVIEW.md` do not explicitly state whether failure-scenario markers should include or omit the decision citation `@<Dn>`.

This plan establishes symmetric base ID normalization in the recorder engine (`token.split('@', 1)[0]`), preserves full finding IDs in ledger rows and audit notes, adds explicit diagnostic stdout logging for demotions, clarifies review protocol documentation, and expands the contract test suite in `scripts/ci/tests/review_recorder_test.sh`.

---

## 2. Scope and Persona Boundaries

| Actor | Stage | Authority / Files Touched | Role in Issue #354 |
|---|---|---|---|
| **athena** | plan / design | `intent/**` | Authored `intent.md` and approved `spec.md` (PR #357). |
| **daedalus** | build | `intent/**`, `scripts/*/tests/**` | Authors `plan.md` and commits failing contract tests (`test_failure_scenario_symmetric_syntax_matrix`, `test_failure_scenario_demotion_attribution_and_logging`, `test_failure_scenario_exemptions_preservation`) in `scripts/ci/tests/review_recorder_test.sh`. Daedalus **never** edits production code (`scripts/ci/review_recorder.py`, `personas/**`, `REVIEW.md`, or `docs/SPEC.md`). |
| **odyssey** | implement | `scripts/ci/review_recorder.py`, `personas/skills/review-protocol.md`, `REVIEW.md`, `docs/SPEC.md`, compiled targets | Implements the plan at pinned base commit `7a8152836a7cfdb2a8ffca6532c0b9e5c830a99a`, turning contract tests green, re-syncing compiled agents, updating `docs/SPEC.md`, and passing all CI gates. |
| **themis** | autonomous merge | GitHub Actions (`merge-gate.yml`) | Evaluates conjuncts and autonomously merges pull requests when consensus is reached. |
| **argus / atlas** | review | comments only | Review pull requests against spec and plan. |

### Deep Review Grant (DEEP-7)
- **Criterion Met:** DEEP-7 (compiler blast radius).
- **Reason:** The implementation alters `personas/skills/review-protocol.md`. Regenerating output via `scripts/sync_agents.py` touches compiled targets across multiple personas (`.agents/agents/**` and `.claude/agents/**` for argus, atlas, odyssey, etc.).
- **Action:** Odyssey applies the `deep-review` grant when opening the PR per `scripts/ops/post.sh <pr> --as odyssey --add-label deep-review`.

---

## 3. Detailed Architectural Calls

### P1 · Base ID Normalization for Failure-Scenario Matching (D1, D2, D4)
In `scripts/ci/review_recorder.py`, within the verdict block processing loop (`for reviewer, verdict, block, reviewed_head, block_round in accepted_blocks_by_comment.get(c_idx, []):`):
1. Extract failure-scenario markers from `block`:
   ```python
   failure_scenarios = set(re.findall(r'<!-- failure-scenario:([A-Za-z0-9@-]+) -->', block))
   failure_scenarios_base = {fs.split('@', 1)[0] for fs in failure_scenarios}
   ```
2. When evaluating a `high` severity finding:
   ```python
   if fsev == "high" and fpr != "dispute" and fst != "withdrawn":
       base_fid = fid.split('@', 1)[0]
       if base_fid not in failure_scenarios_base:
           fsev = "normal"
           audit_notes.append(f"[demoted from high: missing failure_scenario marker] on {fid}")
           print(f"finding {fid}: demoted from high to normal: missing failure_scenario marker")
   ```
This provides symmetric matching across all 4 syntax combinations (D2):
- Suffixed finding (`R1-1@D7`) + Bare marker (`R1-1`): `base_fid="R1-1" in {"R1-1"}` -> MATCH.
- Suffixed finding (`R1-1@D7`) + Suffixed marker (`R1-1@D7`): `base_fid="R1-1" in {"R1-1"}` -> MATCH.
- Bare finding (`R1-1`) + Bare marker (`R1-1`): `base_fid="R1-1" in {"R1-1"}` -> MATCH.
- Bare finding (`R1-1`) + Suffixed marker (`R1-1@D7`): `base_fid="R1-1" in {"R1-1"}` -> MATCH.

### P2 · Full Finding ID Preservation in Ledger Rows and Audit Notes (D3)
Normalization to `base_fid` is strictly internal to the membership check.
- Ledger row retains full `fid`: `<!-- ledger-row:<fid>:<severity>:<status>:<peer> -->`
- Markdown table retains full `fid` in finding column
- Demotion audit note retains full `fid`: `[demoted from high: missing failure_scenario marker] on <fid>` (e.g. `on R1-1@D7`)

### P3 · Verdict Block Scoping and Non-Decremented Presence (D4)
Failure-scenario markers are extracted per verdict block (`block`). A single marker `<!-- failure-scenario:R1-1 -->` satisfies multiple findings in the same block sharing that base ID (e.g. `R1-1@D1` and `R1-1@D2`). Markers are not decremented or consumed. Findings in different blocks or comments must provide their own sibling markers.

### P4 · Diagnostic Execution Logging of Demotions (D5)
When demoting an active, undisputed `high` finding lacking a marker, `scripts/ci/review_recorder.py` prints:
```python
print(f"finding {fid}: demoted from high to normal: missing failure_scenario marker")
```
This output mirrors the existing diagnostic logging for invalid severity refusals (`finding {fid}: severity {fsev} is not one of...`) and ensures immediate visibility in GitHub Actions execution logs.

### P5 · Review Protocol Marker Syntax Clarification (D6)
In `personas/skills/review-protocol.md` and `REVIEW.md`:
- Document that failure-scenario markers match on base finding IDs (`R1-1`).
- Explicitly state that reviewers may emit either the base ID form (`<!-- failure-scenario:R1-1 -->`) or the decision-cited form (`<!-- failure-scenario:R1-1@D7 -->`), and both are recognized as equivalent.
- Run `python3 scripts/sync_agents.py` to propagate changes to compiled agent instructions.

### P6 · Exemption Preservation (#291 Parity) (D7)
Findings with `status == "withdrawn"` or `peer == "dispute"` are exempted from the failure-scenario presence check and retain their declared severity.

---

## 4. Micro-Stepped Tasks

### Task T1: Commit Contract Test Scenarios in `scripts/ci/tests/review_recorder_test.sh`
- **Owner:** daedalus (Build stage)
- **File touched:** `scripts/ci/tests/review_recorder_test.sh`
- **Decisions implemented:** D1, D2, D3, D4, D5, D7, D8
- **Acceptance criteria proven:** AT-354-1, AT-354-2, AT-354-3, AT-354-4, AT-354-5, AT-354-6, AT-354-7, AT-354-8
- **Description:** Append 3 contract test functions to `scripts/ci/tests/review_recorder_test.sh` and register them in `TESTS=(...)`:
  1. `test_failure_scenario_symmetric_syntax_matrix` (AT-354-1..4, AT-354-7):
     - Fixture PR 118 with Argus verdict block containing:
       - `R1-1@D7` with `failure-scenario:R1-1` (AT-354-1)
       - `R1-2@D7` with `failure-scenario:R1-2@D7` (AT-354-2)
       - `R1-3` with `failure-scenario:R1-3` (AT-354-3)
       - `R1-4` with `failure-scenario:R1-4@D7` (AT-354-4)
       - `R1-5@D1` and `R1-5@D2` with single `failure-scenario:R1-5` (AT-354-7)
     - Asserts all 6 findings retain `high` in `$WRITES` ledger rows (`ledger-row:...:high:...`).
     - Asserts zero demotion notes written to `$WRITES`.
  2. `test_failure_scenario_demotion_attribution_and_logging` (AT-354-5, AT-354-6, D3, D5):
     - Fixture PR 119 with Argus verdict block containing:
       - `R1-1@D7:high` (unmarked)
       - `R1-2:high` (unmarked)
       - `R1-3@D7:high` with mismatched marker `failure-scenario:R1-99`
     - Asserts all demote to `normal` in `$WRITES`.
     - Asserts audit notes cite full finding IDs: `on R1-1@D7`, `on R1-2`, `on R1-3@D7`.
     - Asserts stdout contains diagnostic lines for each demoted finding.
  3. `test_failure_scenario_exemptions_preservation` (AT-354-8, D7):
     - Fixture PR 120 with Argus verdict block containing:
       - `R1-1@D7:high:open:dispute` (unmarked)
       - `R1-2@D7:high:withdrawn:none` (unmarked)
     - Asserts both retain `high` in `$WRITES` with zero demotion audit notes.
- **Done-When:**
  Running `bash scripts/ci/tests/review_recorder_test.sh` against unmodified `review_recorder.py` fails on:
  - `FAIL: test_failure_scenario_symmetric_syntax_matrix: suffixed finding with bare marker demoted (D1, D2, AT-354-1)`
  - `FAIL: test_failure_scenario_demotion_attribution_and_logging: stdout missing diagnostic log for R1-1@D7 (D5, AT-354-5)`
  (Contract suite exits code 1, failures not errors, proving tests are RED).

---

### Task T2: Implement Base ID Normalization & Diagnostic Logging in `scripts/ci/review_recorder.py`
- **Owner:** odyssey (Implement stage)
- **File touched:** `scripts/ci/review_recorder.py`
- **Decisions implemented:** D1, D2, D3, D4, D5, D7
- **Acceptance criteria proven:** AT-354-1..8
- **Step-by-step diff:**
  In `scripts/ci/review_recorder.py`:
  ```diff
  @@ -278,6 +278,7 @@
           for reviewer, verdict, block, reviewed_head, block_round in accepted_blocks_by_comment.get(c_idx, []):
               # Extract sibling failure scenarios
               failure_scenarios = set(re.findall(r'<!-- failure-scenario:([A-Za-z0-9@-]+) -->', block))
  +            failure_scenarios_base = {fs.split('@', 1)[0] for fs in failure_scenarios}

               # Parse finding lines
               finding_matches = re.finditer(r'<!-- finding:([A-Za-z0-9@-]+):([A-Za-z0-9]+):([A-Za-z0-9]+):([A-Za-z0-9]+) -->', block)
  @@ -302,9 +303,11 @@
                       finding_round = effective_round

                   # Check high failure scenario marker (D5) keyed on block: any high finding without sibling marker is demoted
                   if fsev == "high" and fpr != "dispute" and fst != "withdrawn":
  -                    if fid not in failure_scenarios:
  +                    base_fid = fid.split('@', 1)[0]
  +                    if base_fid not in failure_scenarios_base:
                           fsev = "normal"
                           audit_notes.append(f"[demoted from high: missing failure_scenario marker] on {fid}")
  +                        print(f"finding {fid}: demoted from high to normal: missing failure_scenario marker")

                   is_new = (fid not in initial_existing_row_ids and fid not in rows)
  ```
- **Done-When:**
  Running `bash scripts/ci/tests/review_recorder_test.sh` exits 0 with all 20 scenarios passing green.

---

### Task T3: Update Review Protocol Documentation & Re-sync Agents
- **Owner:** odyssey (Implement stage)
- **Files touched:**
  - `personas/skills/review-protocol.md`
  - `REVIEW.md`
  - Compiled targets (`.agents/agents/**`, `.claude/agents/**`) via `scripts/sync_agents.py`
- **Decisions implemented:** D6
- **Acceptance criteria proven:** AT-354-9, AT-354-11
- **Step-by-step diff:**
  1. In `personas/skills/review-protocol.md` (around line 34):
     Document that `<!-- failure-scenario:<id> -->` matches on base finding ID (`token.split('@', 1)[0]`), accepting both `<!-- failure-scenario:R1-1 -->` and `<!-- failure-scenario:R1-1@D7 -->`.
  2. In `REVIEW.md` (around lines 124–130):
     Update the failure-scenario requirement section to state that marker matching evaluates on base finding IDs symmetrically.
  3. Execute `python3 scripts/sync_agents.py` to regenerate sidecar targets.
- **Done-When:**
  `python3 scripts/sync_agents.py --check` exits 0 with zero drift.

---

### Task T4: Update Living Spec in `docs/SPEC.md`
- **Owner:** odyssey (Implement stage)
- **File touched:** `docs/SPEC.md`
- **Decisions implemented:** D10
- **Acceptance criteria proven:** AT-354-10, AT-354-11
- **Step-by-step diff:**
  In `docs/SPEC.md`, under `### review.policy`:
  Add or update specification statements:
  - Failure-scenario marker presence is evaluated against normalized base finding IDs (`split('@', 1)[0]`), symmetrically accepting both bare (`R1-1`) and decision-cited (`R1-1@D7`) marker spellings (#354, D1, D2).
  - Full finding IDs (including decision citation) are preserved in ledger row comments, markdown ledger tables, and demotion audit notes (#354, D3).
  - Unmarked, active `high` findings demoted to `normal` emit diagnostic notifications to stdout (#354, D5).
- **Done-When:**
  `bash scripts/ci/spec_check.sh origin/main <pr-body>` exits 0.

---

### Task T5: Integration Testing and CI Gates Verification
- **Owner:** odyssey (Implement stage)
- **Files touched:** none
- **Decisions implemented:** D1–D10
- **Acceptance criteria proven:** AT-354-1 through AT-354-11
- **Step-by-step verification commands:**
  1. `bash scripts/ci/tests/review_recorder_test.sh` -> PASS (all 20 scenarios passed)
  2. `python3 scripts/sync_agents.py --check` -> PASS
  3. `bash scripts/ci/sanitize_check.sh` -> PASS
  4. `bash scripts/ci/spec_check.sh origin/main` -> PASS
  5. `python3 scripts/ops/execution.py --check` -> PASS
  6. `bash scripts/ops/tests/execution_test.sh` -> PASS
  7. `bash scripts/ops/tests/placement_test.sh` -> PASS
  8. `bash scripts/ops/tests/post_test.sh` -> PASS
  9. `bash scripts/ci/tests/merge_gate_test.sh` -> PASS
- **Done-When:**
  All test suites and CI gate checks exit 0 cleanly.

---

## 5. Traceability Matrix

| Acceptance Test | Decision IDs | Test Scenario in `review_recorder_test.sh` | Implementing Task | Verification Proof |
|---|---|---|---|---|
| **AT-354-1** | D1, D2, D8 | `test_failure_scenario_symmetric_syntax_matrix` | T1 (test), T2 (code) | `R1-1@D7` finding + `R1-1` bare marker retains `high` with no demotion note |
| **AT-354-2** | D1, D2, D8 | `test_failure_scenario_symmetric_syntax_matrix` | T1 (test), T2 (code) | `R1-1@D7` finding + `R1-1@D7` suffixed marker retains `high` with no demotion note |
| **AT-354-3** | D1, D2, D8 | `test_failure_scenario_symmetric_syntax_matrix` | T1 (test), T2 (code) | `R1-1` bare finding + `R1-1` bare marker retains `high` with no demotion note |
| **AT-354-4** | D1, D2, D8 | `test_failure_scenario_symmetric_syntax_matrix` | T1 (test), T2 (code) | `R1-1` bare finding + `R1-1@D7` suffixed marker retains `high` with no demotion note |
| **AT-354-5** | D1, D2, D3, D5, D8 | `test_failure_scenario_demotion_attribution_and_logging` | T1 (test), T2 (code) | Suffixed `R1-1@D7` lacking marker demotes to `normal`, notes full ID `on R1-1@D7`, logs to stdout |
| **AT-354-6** | D1, D2, D3, D5, D8 | `test_failure_scenario_demotion_attribution_and_logging` | T1 (test), T2 (code) | Bare `R1-1` lacking marker demotes to `normal`, notes `on R1-1`, logs to stdout |
| **AT-354-7** | D4, D8 | `test_failure_scenario_symmetric_syntax_matrix` | T1 (test), T2 (code) | Multiple findings `R1-5@D1` and `R1-5@D2` satisfied by single `failure-scenario:R1-5` marker |
| **AT-354-8** | D7, D8 | `test_failure_scenario_exemptions_preservation` | T1 (test), T2 (code) | `dispute` and `withdrawn` findings lacking markers retain `high` without demotion |
| **AT-354-9** | D6 | Inspection of protocol docs | T3 | `personas/skills/review-protocol.md` & `REVIEW.md` document symmetric matching |
| **AT-354-10** | D10 | Inspection of living spec | T4 | `docs/SPEC.md` specifies base ID normalization under `review.policy` |
| **AT-354-11** | D9 | CI gate scripts | T5 | `sanitize_check.sh`, `spec_check.sh`, `sync_agents.py --check` exit 0 |

---

## 6. Handoff to Odyssey (Implement Stage)

- **Branch:** `odyssey/354-recorder-demotes-every-high-finding-to`
- **Base commit:** `7a8152836a7cfdb2a8ffca6532c0b9e5c830a99a` (or the commit merging this plan)
- **PR Title:** `fix(recorder): normalize base IDs for failure-scenario matching (#354)`
- **PR Body Requirements:**
  - Reference: `Refs #354` (or `Closes #354`)
  - Deep Review grant: include `deep-review` grant label (DEEP-7: alters `personas/skills/review-protocol.md`)
  - Summary of implemented tasks T2, T3, T4
  - Proof that all 20 scenarios in `scripts/ci/tests/review_recorder_test.sh` pass green
  - Proof that `python3 scripts/sync_agents.py --check` passes green
