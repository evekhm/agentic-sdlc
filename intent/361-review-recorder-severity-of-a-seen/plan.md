# Plan: Mutable Finding Severity by Discovering Reviewer in Consensus Recorder

**Issue:** #361 · **Spec:** `intent/361-review-recorder-severity-of-a-seen/spec.md` (Approved, PR #378, D1–D10, AT-361-1–AT-361-9)  
**Author:** daedalus (`evekhm-daedalus-app[bot]`)  
**Base commit:** `29b6b40b31d9fd150c1bdac875008c2db3f49d25`  
**Target branch for implementation (Odyssey):** `odyssey/361-review-recorder-severity-of-a-seen`

---

## 1. Executive Summary and Problem Statement

Under the multi-reviewer consensus protocol (`REVIEW.md`, `docs/SPEC.md:544-577`), Argus and Atlas evaluate pull requests concurrently across review rounds. In `scripts/ci/review_recorder.py`, findings are tracked in the consensus ledger table. However, finding severity in `review_recorder.py` has historically been **write-once**: when an active finding line is re-encountered in subsequent review rounds, the recorder updates the finding's status (`open`, `fixed`, `withdrawn`) but completely ignores any severity modification (`security`, `high`, `normal`, `suggestion`).

### Production Incident
On PR #319 (round 2/3), discovering reviewer Argus identified that a previous finding `R2-1@D5` initially raised at `high` severity had been clarified or mitigated, and Argus downgraded the finding to `normal` in its round-3 review verdict block. However, because `review_recorder.py` ignored the discoverer's severity update, the consensus ledger retained `high` severity. Consequently, `scripts/ci/merge_gate.sh` evaluated conjunct (4) against the stale `high` row, finding blocking items still open, preventing autonomous merge indefinitely.

### Root Cause
1. In `scripts/ci/review_recorder.py:356-366` (Pass 2):
   ```python
   if fid not in rows:
       rows[fid] = {
           "severity": fsev,
           "status": fst,
           "peer": fpr,
           "round": finding_round,
       }
   else:
       # Update status if reviewer is discoverer
       if reviewer == discoverer:
           rows[fid]["status"] = fst
   ```
   When `fid in rows`, only `rows[fid]["status"] = fst` is executed. `rows[fid]["severity"]` is never touched.
2. The maintainer retier mechanism (`@<reviewer> retier <fid> <severity>`) in `review_recorder.py:255-275` was designed as an administrative override for human maintainers (`OWNER`, `MEMBER`, `COLLABORATOR`), not an automated channel for discovering review bots to update their own findings.
3. Because severity was immutable in Pass 2, reviewers had no mechanism to downgrade false-positive or mitigated `high` findings to non-blocking tiers, leading to stuck PRs.

This plan details the implementation to allow the discovering reviewer to mutate a finding's severity across rounds, subject to round funnel caps (D2), existing sibling failure-scenario demotion constraints (D3), security tier protections (D4), peer reviewer non-interference (D5), audit logging (D6), and merge gate conjunct 4 synchronization (D7).

---

## 2. Scope and Persona Boundaries

| Actor | Stage | Authority / Files Touched | Role in Issue #361 |
|---|---|---|---|
| **athena** | plan / design | `intent/**` | Authored `intent.md` and approved `spec.md` (merged as PR #378). |
| **daedalus** | build | `intent/**`, `scripts/*/tests/**` | Authors `plan.md` and commits contract test suite (`test_discoverer_severity_downgrade_and_unblock`, `test_peer_severity_non_interference`, `test_re_encounter_high_missing_failure_scenario`, `test_security_tier_footer_downgrade_protection`, `test_late_round_funnel_elevation_cap`) in `scripts/ci/tests/review_recorder_test.sh`. Daedalus **never** edits production code. |
| **odyssey** | implement | `scripts/ci/review_recorder.py`, `docs/SPEC.md`, `REVIEW.md`, `personas/skills/review-protocol.md`, compiled targets | Implements the plan at pinned base commit `29b6b40b31d9fd150c1bdac875008c2db3f49d25`, turning contract tests green, updating living spec, and verifying all CI gates. |
| **themis** | autonomous merge | GitHub Actions (`merge-gate.yml`) | Autonomously gates and merges pull requests upon consensus. |
| **argus / atlas** | review | comments only | Review pull requests against spec and plan. |

### Deep Review Grant (DEEP-3, DEEP-5, DEEP-7)
- **Criteria Met:**
  - **DEEP-3 (irreversible or privileged operations):** Modifies consensus ledger state machine that directly drives autonomous PR gating, label management (`review:merge-ready`, `consensus:agreed`, `argus:findings`), and merge unblocking.
  - **DEEP-5 (escalated risk tier):** Task T2 modifies state machine transitions for severity in `review_recorder.py`, requiring careful fence against unilateral security downgrades and peer interference.
  - **DEEP-7 (compiler blast radius):** The implementation updates `personas/skills/review-protocol.md`. Regenerating output via `scripts/sync_agents.py` touches compiled agent targets across multiple personas (`.agents/agents/**` and `.claude/agents/**`).
- **Action:** Odyssey applies the `deep-review` grant when opening the PR per `scripts/ops/post.sh <pr> --as odyssey --add-label deep-review`.

---

## 3. Detailed Architectural Calls

### P1 · Discoverer Severity Mutability in Pass 2 (D1)
In `scripts/ci/review_recorder.py`, when a verdict block finding line matches an existing ledger row (`fid in rows`) and `reviewer == discoverer`:
- The recorder updates `rows[fid]["severity"]` to the surviving `fsev` parsed from the verdict block footer, subject to the constraints in P2, P3, and P4.
- If `reviewer != discoverer`, severity is not touched (P5, D5).

### P2 · Existing Failure-Scenario Demotion Constraint Integration (D3)
In PR #375 (`eedc2a8`), failure-scenario base ID normalization landed in `review_recorder.py:305-310`:
```python
if fsev == "high" and fpr != "dispute" and fst != "withdrawn":
    base_fid = fid.split('@', 1)[0]
    if base_fid not in failure_scenarios_base:
        fsev = "normal"
        audit_notes.append(f"[demoted from high: missing failure_scenario marker] on {fid}")
        print(f"finding {fid}: demoted from high to normal: missing failure_scenario marker")
```
D3 acts as an inbound constraint on D1's write:
- The existing failure-scenario demotion check executes **first**, evaluating whether any active `high` finding in the block has a matching sibling `<!-- failure-scenario:<id> -->` marker.
- If the marker is missing (and finding is not `withdrawn` or `dispute`), `fsev` is demoted to `normal`, the demotion audit note is appended, and the diagnostic message is logged to stdout.
- When D1 executes subsequently in the discoverer branch, it receives the already demoted `fsev = "normal"` and updates `rows[fid]["severity"]` accordingly.
- **Architectural call:** No redundant second demotion block is introduced. D1 simply assigns the surviving `fsev` after lines 305–310.

### P3 · Round Funnel Rules for Severity Transitions Across Rounds (D2)
Transitions across review rounds adhere to the funnel rules:
- **Downward transitions** (`high` -> `normal`, `high` -> `suggestion`, `normal` -> `suggestion`) are admissible in all rounds without restriction.
- **Upward transitions to high** (`normal` -> `high`, `suggestion` -> `high`) are admissible in rounds 1 through 3.
- In round 4 or later (`effective_round >= 4`), any upward transition of an existing non-security finding to `high` is demoted to `normal` per the post-round-3 funnel cap (`REVIEW.md:174-176`).

### P4 · Security Tier Protection Against Unilateral Footer Downgrades (D4)
The `security` tier carries existential impact:
- If an existing ledger row has `severity == "security"`, a review verdict block footer finding line **cannot** downgrade it to a lower severity (`fsev != "security"`).
- Any footer downgrade attempt on a `security` row is ignored; the row remains `security`.
- The recorder emits a diagnostic log to stdout:
  `print(f"finding {fid}: footer severity change from security to {fsev} ignored; security rows require maintainer retier")`
- A `security` row can only be downgraded through an authorized maintainer retier directive (`@<reviewer> retier <fid> <severity>`), as verified by AT-361-7.
- Elevation of an existing non-security finding to `security` by the discoverer is permitted, but sets `rows[fid]["peer"] = "pending"` to enforce dual-agreement existence verification before merge.

### P5 · Peer Reviewer Non-Interference (D5)
A non-discovering peer reviewer (`reviewer != discoverer`) cannot alter the severity of a finding. If Atlas emits `finding:R2-1@D5:normal:open:none` on Argus's finding `R2-1@D5`:
- The severity remains `high`.
- No audit note is recorded, and no stdout log is emitted.
- Peer concurrence or dispute on status/existence (`agree`, `dispute`) continues to follow standard consensus rules.

### P6 · Consensus Ledger Audit Trail and Execution Logging (D6)
When the discoverer changes a finding's severity (`old_sev != new_sev`):
- Ledger audit note appended: `[severity updated to {new_sev} by @{reviewer} on {fid}]`
- Execution log to stdout: `print(f"finding {fid}: severity updated from {old_sev} to {new_sev} by @{reviewer}")`
- If `old_sev == new_sev`, neither the audit note nor the stdout log is emitted.

### P7 · Downstream Merge Gate Conjunct 4 and Label Synchronization (D7)
When a `high` finding is downgraded to `normal` or `suggestion`:
- The consensus ledger table records `normal`.
- `review_recorder.py` label synchronization clears `argus:findings` (if no other blocking rows remain) and adds `argus:suggestions`.
- If both reviewers' accepted heads match the PR head and no blocking rows exist, `review:merge-ready` is added.
- In `merge_gate.sh:308-316`, `BLOCKING` excludes `normal` findings. Conjunct (4) evaluates to `true` (`C[4]=1; WHY[4]="blocking set empty"`).

### P8 · Synergy and Sequencing Boundaries
- **Issue #381 (maintainer retier verb regex):** Filed regarding maintainer retier verb parsing in comment prose without fence exclusion. D4 relies on maintainer retiers for `security` downgrades; implementation in T2 must preserve retier parsing integrity.
- **Issue #355 / #249 (CI gates registration):** Contract tests in `scripts/ci/tests/review_recorder_test.sh` run hermetically in local test executions and can be wired into CI workflows.
- **Issue #353 (run-id 0 handling):** Merged spec PR #380 immediately prior to #378, touching the same `### review.policy` section in `docs/SPEC.md`. Odyssey must ensure clean textual integration without merge conflicts.

---

## 4. Micro-Stepped Tasks

### Task T1: Commit Contract Test Scenarios in `scripts/ci/tests/review_recorder_test.sh`
- **Owner:** daedalus (Build stage)
- **File touched:** `scripts/ci/tests/review_recorder_test.sh`
- **Decisions implemented:** D1, D2, D3, D4, D5, D6, D7, D8
- **Acceptance criteria proven:** AT-361-1 through AT-361-7
- **Description:** Append 5 contract test functions and register them in `TESTS=(...)`:
  1. `test_discoverer_severity_downgrade_and_unblock` [RED-NOW] (D1, D6, D7, D8, AT-361-1, AT-361-2):
     - Fixture PR 121 with Argus finding `R2-1@D5:high:open:none`.
     - In round 3, Argus emits `finding:R2-1@D5:normal:open:none`, Atlas emits `clean`.
     - Asserts `ledger-row:R2-1@D5:normal:open:none` in `$WRITES`.
     - Asserts audit note `[severity updated to normal by @argus on R2-1@D5]` in `$WRITES`.
     - Asserts stdout diagnostic `finding R2-1@D5: severity updated from high to normal by @argus`.
     - Asserts `review:merge-ready` added to labels.
     - Feeds emitted ledger to `run_gate 121` and asserts conjunct (4) evaluates to `true` with `blocking set empty`.
  2. `test_peer_severity_non_interference` [REGRESSION GUARD] (D5, D8, AT-361-3):
     - Fixture PR 122 with Argus finding `R2-1@D5:high:open:none`.
     - Peer Atlas emits `finding:R2-1@D5:normal:open:none`.
     - Asserts row remains `high`, no severity update audit note, no stdout log.
  3. `test_re_encounter_high_missing_failure_scenario` [RED-NOW] (D3, D8, AT-361-4):
     - Fixture PR 123 with existing finding `R2-1@D5:high:open:none`.
     - Argus in round 3 re-emits `finding:R2-1@D5:high:open:none` without sibling failure-scenario marker.
     - Asserts row demotes to `normal`, audit note `[demoted from high: missing failure_scenario marker] on R2-1@D5`, and stdout demotion log.
  4. `test_security_tier_footer_downgrade_protection` [RED-NOW on log / REGRESSION GUARD on row] (D4, D8, AT-361-5, AT-361-7):
     - Fixture PR 124 with `R1-1:security:open:pending`.
     - Argus emits `finding:R1-1:normal:open:none` in round 2.
     - Asserts row remains `security:open:pending`, normal row not recorded, no severity update note, and stdout diagnostic logged.
     - Case 2: Authorized maintainer `@argus retier R1-1 normal` retiers row to `normal` with audit note.
  5. `test_late_round_funnel_elevation_cap` [REGRESSION GUARD] (D2, D8, AT-361-6):
     - Fixture PR 125 with existing `R1-5:normal:open:none`.
     - In round 4, Argus attempts to elevate `R1-5` to `high` with failure scenario.
     - Asserts row remains `normal` per post-round-3 funnel cap.
- **Done-When:**
  Running `bash scripts/ci/tests/review_recorder_test.sh` exits with code 1, reporting `22 passed, 3 failed out of 25 run` (clean assertion failures, not syntax crashes), fulfilling Daedalus's contract test gate.

---

### Task T2: Implement Discoverer Severity Mutability & Protections in `scripts/ci/review_recorder.py`
- **Owner:** odyssey (Implement stage)
- **File touched:** `scripts/ci/review_recorder.py`
- **Decisions implemented:** D1, D2, D3, D4, D5, D6, D7
- **Acceptance criteria proven:** AT-361-1 through AT-361-7
- **Step-by-step diff:**
  In `scripts/ci/review_recorder.py` around lines 356–366:
  ```diff
                   else:
                       # Update status if reviewer is discoverer
                       if reviewer == discoverer:
                           rows[fid]["status"] = fst
  +                        old_sev = rows[fid]["severity"]
  +
  +                        # D4: Security tier protection against unilateral footer downgrades
  +                        if old_sev == "security" and fsev != "security":
  +                            print(f"finding {fid}: footer severity change from security to {fsev} ignored; security rows require maintainer retier")
  +                        else:
  +                            new_sev = fsev
  +                            # D2: Post-cap funnel rules: in round 4+, upward transition to high demoted to normal
  +                            if effective_round >= 4 and old_sev in ("normal", "suggestion") and new_sev == "high":
  +                                new_sev = "normal"
  +
  +                            if old_sev != new_sev:
  +                                rows[fid]["severity"] = new_sev
  +                                audit_notes.append(f"[severity updated to {new_sev} by @{reviewer} on {fid}]")
  +                                print(f"finding {fid}: severity updated from {old_sev} to {new_sev} by @{reviewer}")
  +                                # D4: Non-security elevation to security requires peer confirmation
  +                                if new_sev == "security":
  +                                    rows[fid]["peer"] = "pending"
  ```
- **Done-When:**
  `bash scripts/ci/tests/review_recorder_test.sh` runs all 25 tests green (25 passed, 0 failed).

---

### Task T3: Update Review Protocol Documentation & Re-sync Agents
- **Owner:** odyssey (Implement stage)
- **Files touched:**
  - `personas/skills/review-protocol.md`
  - `REVIEW.md`
  - Compiled targets (`.agents/agents/**`, `.claude/agents/**`) via `scripts/sync_agents.py`
- **Decisions implemented:** D1, D2, D4, D5
- **Acceptance criteria proven:** AT-361-8
- **Step-by-step diff:**
  1. In `personas/skills/review-protocol.md`:
     Document that discovering reviewers may update finding severity in subsequent review verdict blocks; that `security` findings cannot be downgraded via verdict blocks; and that late-round upward escalations to `high` are capped to `normal`.
  2. In `REVIEW.md`:
     Update consensus table and severity progression documentation to reflect discoverer severity mutability and security tier protection.
  3. Execute `python3 scripts/sync_agents.py` to regenerate sidecar targets.
- **Done-When:**
  `python3 scripts/sync_agents.py --check` exits 0 with zero drift.

---

### Task T4: Update Living Spec in `docs/SPEC.md`
- **Owner:** odyssey (Implement stage)
- **File touched:** `docs/SPEC.md`
- **Decisions implemented:** D10
- **Acceptance criteria proven:** AT-361-9
- **Step-by-step diff:**
  In `docs/SPEC.md`, under `### review.policy`:
  Add specification statements:
  - Finding severity in consensus ledger is mutable across rounds by discovering reviewer (`reviewer == discoverer`) (#361, D1).
  - Downward severity transitions are unrestricted across all rounds; upward escalation of existing findings to `high` in round 4+ demotes to `normal` (#361, D2).
  - Existing `high` findings re-encountered without sibling failure-scenario markers demote to `normal` with audit note and stdout logging (#361, D3).
  - Existing `security` rows cannot be downgraded via review verdict footers; maintainer retier directives are required (#361, D4).
  - Peer reviewers (`reviewer != discoverer`) cannot alter finding severity (#361, D5).
  - Severity modifications by discoverer append `[severity updated to {new_sev} by @{reviewer} on {fid}]` to consensus ledger and log to stdout (#361, D6).
- **Done-When:**
  `bash scripts/ci/spec_check.sh origin/main <pr-body>` exits 0.

---

### Task T5: Integration Testing and CI Gates Verification
- **Owner:** odyssey (Implement stage)
- **Files touched:** none
- **Decisions implemented:** D1–D10
- **Acceptance criteria proven:** AT-361-1 through AT-361-9
- **Step-by-step verification commands:**
  1. `bash scripts/ci/tests/review_recorder_test.sh` -> PASS (all 25 scenarios passed)
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

| Acceptance Test | Decision IDs | Category | Test Scenario in `review_recorder_test.sh` | Implementing Task | Verification Proof |
|---|---|---|---|---|---|
| **AT-361-1** | D1, D6, D8 | **RED-NOW** | `test_discoverer_severity_downgrade_and_unblock` | T1 (test), T2 (code) | Discoverer Argus emits `normal` on `high` finding: ledger updates to `normal`, audit note recorded, stdout diagnostic logged |
| **AT-361-2** | D1, D7, D8 | **RED-NOW** | `test_discoverer_severity_downgrade_and_unblock` | T1 (test), T2 (code) | Running `merge_gate.sh` after downgrade evaluates conjunct (4) to true (`blocking set empty`) |
| **AT-361-3** | D5, D8 | **REGRESSION GUARD** | `test_peer_severity_non_interference` | T1 (test), T2 (code) | Peer Atlas emitting `normal` leaves Argus finding at `high`, no note recorded |
| **AT-361-4** | D3, D8 | **RED-NOW** | `test_re_encounter_high_missing_failure_scenario` | T1 (test), T2 (code) | Re-encountered `high` finding without failure-scenario marker demotes to `normal`, notes full ID, logs to stdout |
| **AT-361-5** | D4, D8 | **RED-NOW (log) / GUARD (row)** | `test_security_tier_footer_downgrade_protection` | T1 (test), T2 (code) | Discoverer emitting `normal` on `security` row is ignored; stdout logs footer downgrade refusal |
| **AT-361-6** | D2, D8 | **REGRESSION GUARD** | `test_late_round_funnel_elevation_cap` | T1 (test), T2 (code) | Escalation of existing finding to `high` in round 4 is demoted to `normal` |
| **AT-361-7** | D4, D8 | **REGRESSION GUARD** | `test_security_tier_footer_downgrade_protection` | T1 (test), T2 (code) | Maintainer retier directive from authorized owner successfully retiers `security` row to `normal` |
| **AT-361-8** | D9 | **HYGIENE** | Gate verification scripts | T3, T5 | `sanitize_check.sh`, `spec_check.sh`, `sync_agents.py --check` exit 0 |
| **AT-361-9** | D10 | **SPEC** | Inspection of living spec | T4 | `docs/SPEC.md` updated under `### review.policy` |

---

## 6. Handoff to Odyssey (Implement Stage)

- **Branch:** `odyssey/361-review-recorder-severity-of-a-seen`
- **Base commit:** SHA of the commit merging this plan
- **PR Title:** `fix(ci): mutable finding severity by discovering reviewer in consensus recorder (#361)`
- **PR Body Requirements:**
  - Reference: `Refs #361` (or `Closes #361`)
  - Deep Review grant: apply `deep-review` grant label (`scripts/ops/post.sh <pr> --as odyssey --add-label deep-review`) per DEEP-3, DEEP-5, DEEP-7.
  - Plan sync / Summary of implemented tasks T2, T3, T4.
  - Proof that all 25 scenarios in `scripts/ci/tests/review_recorder_test.sh` pass green.
  - Proof that `python3 scripts/sync_agents.py --check` passes green.
