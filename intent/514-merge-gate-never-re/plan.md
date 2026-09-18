# Plan: Auto-Resolution of Transient Conjunct (2) Merge Gate Declines

**Issue:** #514 · **Spec:** `intent/514-merge-gate-never-re/spec.md` (Approved, PR #522, D1–D7, AT-514-1–AT-514-9)  
**Author:** daedalus (`evekhm-daedalus-app[bot]`)  
**Base commit:** `c4fc19f4fb23020ac08fee952f6b8c2ea878285d` (`origin/main`, merge of spec PR #522)  
**Target branch for implementation (Odyssey):** `odyssey/514-merge-gate-never-re-evaluates-a`

---

## 1. Executive Summary and Problem Statement

`scripts/ci/merge_gate.sh` evaluates eleven conjuncts to decide whether a pull request merges autonomously. Under the current implementation, the merge gate evaluates once upon receiving a trigger event and never re-evaluates automatically. When a gate decline is caused by a transient condition—specifically when foreign checks on the head commit are still in flight (`IN_PROGRESS`, `QUEUED`, `PENDING`, `WAITING`, `REQUESTED`) or when `mergeStateStatus` is `UNKNOWN`—the pull request is stranded indefinitely in a declined state.

When an automated reviewer (Argus or Atlas) posts a review comment, that comment triggers `merge-gate.yml` within seconds while the reviewer's own workflow run or concurrent infrastructure workflow jobs (such as `resolve`) are still executing. Measured production incidents demonstrate this defect:
1. **Pull Request #512 (Build rung of #508, 2026-09-17):** Argus posted its review comment at 17:33:24Z, triggering the gate 4 seconds later at 17:33:28Z. The gate read `argus=IN_PROGRESS` in `statusCheckRollup` and declined on conjunct (2). All other conjuncts were true, including reviewer consensus and loop ledger checks. The pull request sat stranded for 3 hours and 28 minutes until an operator manually reran the gate without code or comment changes, whereupon all checks evaluated green and the pull request merged at 21:01:46Z.
2. **Pull Request #515 (Implement rung of #508, 2026-09-17):** Reviewer posted review while `resolve` was `QUEUED`. The gate declined on conjunct (2). Within one minute, every check on the commit head reached `SUCCESS`. The pull request sat stranded until an operator triggered a manual rerun.

This failure silently halts unattended lifecycle advancement without failing commit checks or notifying operators.

This plan details the implementation to introduce mechanical auto-resolution of transient conjunct (2) declines directly within `scripts/ci/merge_gate.sh`:
- **In-Gate Bounded Polling Loop (D1):** When conjunct (2) detects in-flight checks or `mergeStateStatus: UNKNOWN` while all other merge preconditions hold, it enters a polling loop re-reading `statusCheckRollup` and `mergeStateStatus` via GraphQL until checks pass, a check terminally fails, or the timeout ceiling expires.
- **Precondition Gating (Anti-Resource-Waste) (D2):** The polling loop executes if and only if all other conjuncts (1, 3, 4, 5, 6, 7, 8, 9, 10, 11) evaluate true. If any non-conjunct-(2) precondition is false (e.g. blocking findings, active hold/blocked labels, budget exhaustion), the gate declines immediately without polling.
- **Immediate Abort on Terminal Failure (Fail-Fast) (D3):** If any check transitions to a terminal failure state (`FAILURE`, `CANCELLED`, `TIMED_OUT`, `ACTION_REQUIRED`, `STALE`, `STARTUP_FAILURE`) or `mergeStateStatus` transitions to a terminal state (`DIRTY`, `BLOCKED`, `DRAFT`), the polling loop terminates immediately and declines.
- **Configurable Timeout Bounds and Zero-Delay Testing (D4):** Polling timeout (`MERGE_GATE_TRANSIENT_TIMEOUT`, default 120s) and polling interval (`MERGE_GATE_TRANSIENT_POLL_INTERVAL`, default 5s) are configurable via environment variables, with 0 enabling instantaneous hermetic test execution.
- **Explicit Diagnostic Categorization (D5):** `WHY[2]` and gate output logs explicitly distinguish in-flight timeouts (`check(s) in flight timed out after <N>s:`) from terminal check failures (`check(s) not success:`).

---

## 2. Scope, Persona Boundaries, and Grants

### Persona Authority Boundaries

| Actor | Stage | Authority / Paths Touched | Role in Issue #514 |
|---|---|---|---|
| **athena** | intake, plan, design | `intent/**` | Authored `intent.md` and approved `spec.md` (merged in PR #522). |
| **daedalus** | build | `intent/**`, `scripts/*/tests/**` | Authors `plan.md` and commits contract test suite `scripts/ci/tests/merge_gate_transient_polling_contract_test.sh`. Daedalus **never** edits production code. |
| **odyssey** | implement | `scripts/ci/merge_gate.sh`, `scripts/ci/tests/merge_gate_test.sh`, `docs/SPEC.md`, `CHANGELOG.md` | Executes Tasks T2 through T6 branching from the commit merging this plan, turns contract tests green, updates living documentation, and verifies all CI gates. |
| **themis** | autonomous merge | GitHub Actions (`merge-gate.yml`) | Autonomously gates and merges pull requests upon consensus. |
| **argus / atlas** | review | comments only | Review pull requests against spec and plan. |

### Deep Review Grant Assessment (DEEP-1, DEEP-3, DEEP-5)

- **Build PR (Daedalus):**
  - **DEEP-1 (trust-bearing paths):** Touches `scripts/ci/tests/merge_gate_transient_polling_contract_test.sh`, which falls under `config/execution.yaml` `assigned_when.paths` (`scripts/ci/**`).
  - **Action:** Daedalus applies `deep-review` label via `scripts/ops/post.sh <pr> --as daedalus --add-label deep-review`.
- **Implementation PR (Odyssey):**
  - **DEEP-1 (trust-bearing paths):** Touches `scripts/ci/merge_gate.sh` and `scripts/ci/tests/merge_gate_test.sh`.
  - **DEEP-3 (privileged / irreversible operations):** Modifies `scripts/ci/merge_gate.sh`, the repository's sole autonomous merger script executing `gh pr merge`.
  - **DEEP-5 (escalated risk tier):** Task T2 (`merge_gate.sh`) alters core gate polling and execution loops. Marked `risk: high`.
  - **Action:** Odyssey applies the `deep-review` grant when opening the PR per `scripts/ops/post.sh <pr> --as odyssey --add-label deep-review`.

### Living Spec and Changelog Obligations

- **Build PR (Daedalus):**
  - `Spec-impact: none — build stage contract tests and plan only; living spec upsert is task of implementation PR`
  - `Changelog: none — build stage contract tests and plan only; changelog entry is task of implementation PR`
- **Implementation PR (Odyssey):**
  - Updates `docs/SPEC.md` under `### loop.autonomous` (conjunct 2) documenting in-gate bounded polling, timeout bounds (`MERGE_GATE_TRANSIENT_TIMEOUT`), polling interval (`MERGE_GATE_TRANSIENT_POLL_INTERVAL`), and precondition gating (D6, AT-514-7).
  - Updates `CHANGELOG.md` under the unreleased / current release section documenting the bug fix and operator impact (AT-514-9).

### Strict File Manifest Partitioning (D7)

The implementing change (Odyssey) is strictly confined to:
1. `scripts/ci/merge_gate.sh`
2. `scripts/ci/tests/merge_gate_test.sh`
3. `docs/SPEC.md`
4. `CHANGELOG.md`
5. `intent/514-merge-gate-never-re/plan.md` (read-only reference; updated only if plan sync occurs)
6. `intent/514-merge-gate-never-re/spec.md` (read-only reference)

**Forbidden Paths (Untouched per D7):**
- `.github/workflows/**`: workflow definitions, concurrency groups, and triggers are untouched.
- `personas/**`: persona instructions and compiled targets are untouched.
- `config/**`: execution configuration is untouched.
- `scripts/ci/review_recorder.sh` and `scripts/ci/review_recorder.py`: consensus recording is untouched.
- `scripts/ci/escalate.sh`: escalation execution logic is untouched.
- `scripts/ci/lifecycle_advance.sh`: ladder transitions are untouched.

Note on Contract Test Suite (`scripts/ci/tests/merge_gate_transient_polling_contract_test.sh`): Authored and committed in this Build PR (#528) by Daedalus under Daedalus's authority (`scripts/*/tests/**`). It does not appear in Odyssey's diff against `origin/main` because it merges as part of this Build PR.

---

## 3. Detailed Architectural Calls

### P1 · Precondition Gating Before Transient Polling (D2)
- In `scripts/ci/merge_gate.sh`, before entering any transient check polling loop for conjunct (2), verify that all other conjuncts (1, 3, 4, 5, 6, 7, 8, 9, 10, 11) have evaluated to true:
  ```bash
  OTHER_CONJUNCTS_OK=0
  [ "${C[1]}" = 1 ] && [ "${C[3]}" = 1 ] && [ "${C[4]}" = 1 ] && [ "${C[5]}" = 1 ] && \
  [ "${C[6]}" = 1 ] && [ "${C[7]}" = 1 ] && [ "${C[8]}" = 1 ] && [ "${C[9]}" = 1 ] && \
  [ "${C[10]}" = 1 ] && [ "${C[11]}" = 1 ] && OTHER_CONJUNCTS_OK=1
  ```
- If `OTHER_CONJUNCTS_OK` is 0, the gate immediately declines on the failed conjuncts without sleeping or re-reading check status.

### P2 · In-Gate Bounded Polling Loop (D1, D4)
- When `OTHER_CONJUNCTS_OK=1`, if foreign checks in `CHECKS_TSV` are in transient states (`IN_PROGRESS`, `QUEUED`, `PENDING`, `WAITING`, `REQUESTED`) or `MERGE_STATE` is `UNKNOWN`, enter the transient polling loop.
- **Handling of `mergeStateStatus: UNKNOWN` (D1, R1-4):**
  In `merge_gate.sh:480-482`, `UNKNOWN` is currently handled by short-circuiting to unevaluable:
  ```bash
  elif [ "$MERGE_STATE" = "UNKNOWN" ]; then
      WHY[2]="mergeStateStatus is still UNKNOWN after $merge_state_attempt re-read(s) — unevaluable (D24)"
      ledger_append "refusal:unknown" "$RUNG"
  ```
  When `OTHER_CONJUNCTS_OK=1`, `UNKNOWN` mergeStateStatus must not decline immediately. Instead, `merge_gate.sh` enters the bounded transient polling loop, continuing to re-read merge state via `read_merge_state`. If `MERGE_STATE` transitions to `CLEAN` or `UNSTABLE` and checks pass, the gate proceeds to merge. If the timeout expires while `MERGE_STATE` remains `UNKNOWN`, the gate records `WHY[2]="mergeStateStatus is still UNKNOWN after ${elapsed}s — unevaluable (D24)"` and logs `refusal:unknown`. If `OTHER_CONJUNCTS_OK=0`, the gate declines immediately without polling.
- **Polling bounds:**
  ```bash
  MERGE_GATE_TRANSIENT_TIMEOUT="${MERGE_GATE_TRANSIENT_TIMEOUT:-120}"
  MERGE_GATE_TRANSIENT_POLL_INTERVAL="${MERGE_GATE_TRANSIENT_POLL_INTERVAL:-5}"
  ```
- **Polling loop structure:**
  1. Record loop start timestamp: `poll_start="$(date +%s)"`.
  2. While elapsed time does not exceed `MERGE_GATE_TRANSIENT_TIMEOUT`:
     - Evaluate current check roll-up and merge state.
     - **Success condition:** If all checks are `SUCCESS`, `NEUTRAL`, or `SKIPPED`, and merge state is `CLEAN` or `UNSTABLE`: set `C[2]=1`, record `WHY[2]`, and break loop.
     - **Terminal failure abort (D3):** If any check has reached a terminal failure state (`FAILURE`, `CANCELLED`, `TIMED_OUT`, `ACTION_REQUIRED`, `STALE`, `STARTUP_FAILURE`) or merge state is `DIRTY`, `BLOCKED`, or `DRAFT`: abort polling immediately, set `C[2]=0`, record `WHY[2]`, and break loop.
     - Calculate remaining time. If elapsed time >= `MERGE_GATE_TRANSIENT_TIMEOUT`, break loop with timeout diagnostic.
     - Sleep `MERGE_GATE_TRANSIENT_POLL_INTERVAL` (if interval > 0).
     - Re-read merge state and check roll-up via `read_merge_state`.

### P3 · Fail-Fast Terminal State Abort (D3)
- An awk helper categorizes checks into passing, transient, and terminal:
  - Passing: `SUCCESS`, `NEUTRAL`, `SKIPPED`
  - Transient: `IN_PROGRESS`, `QUEUED`, `PENDING`, `WAITING`, `REQUESTED`
  - Terminal failure: `FAILURE`, `CANCELLED`, `TIMED_OUT`, `ACTION_REQUIRED`, `STALE`, `STARTUP_FAILURE`
- If any check is in a terminal failure state, the loop terminates immediately: no further sleep or polling is performed.

### P4 · Explicit Diagnostic Categorization (D5)
- If the loop exits due to elapsed timeout while checks remain in transient states:
  ```bash
  WHY[2]="mergeStateStatus $MERGE_STATE but check(s) in flight timed out after ${elapsed}s:$transient_checks"
  ```
- If the loop exits due to terminal check failure:
  ```bash
  WHY[2]="mergeStateStatus $MERGE_STATE but check(s) not success:$terminal_checks"
  ```
- If mergeStateStatus is not clean:
  ```bash
  WHY[2]="mergeStateStatus is $MERGE_STATE"
  ```

---

## 4. Micro-Stepped Tasks

### Task T1: Commit Hermetic Contract Test Suite in `scripts/ci/tests/merge_gate_transient_polling_contract_test.sh`
- **Owner:** daedalus (Build stage)
- **Files touched:** `scripts/ci/tests/merge_gate_transient_polling_contract_test.sh`
- **Decisions implemented:** D1, D2, D3, D4, D5, D6, D7
- **Acceptance criteria proven:** AT-514-1 through AT-514-9
- **Description:** Implement standalone contract test suite validating:
  1. `scripts/ci/merge_gate.sh` defines configurable `MERGE_GATE_TRANSIENT_TIMEOUT` and `MERGE_GATE_TRANSIENT_POLL_INTERVAL`, and executes zero-delay overrides with immediate timeout diagnostic (D1, D4, AT-514-1, AT-514-5).
  2. In-flight checks and `UNKNOWN` mergeStateStatus poll to resolution (`SUCCESS` / `CLEAN`) and merge PR when all other conjuncts hold (D1, AT-514-1).
  3. Precondition gating guards transient polling: positive control polls when preconditions hold, negative control declines immediately without polling when conjunct (4) fails (`C[4]=0`) (D2, AT-514-2).
  4. Immediate abort on terminal check failure states: positive control polls when transient, negative control aborts immediately without polling remaining attempts when a terminal failure exists (D3, AT-514-3).
  5. In-flight check timeout emits `check(s) in flight timed out after <N>s:` diagnostic (D4, D5, AT-514-4, AT-514-6).
  6. `scripts/ci/tests/merge_gate_test.sh` includes regression test coverage for transient polling (scenarios `MG-2c` through `MG-2f` and `MERGE_GATE_TRANSIENT_TIMEOUT`) (D1, D2, D3, D4, AT-514-1..6).
  7. `docs/SPEC.md` records living spec update for conjunct (2) transient polling (D6, AT-514-7).
  8. `CHANGELOG.md` records auto-resolution of transient conjunct (2) declines (D7, AT-514-9).
- **Harness Details:**
  - Extracts mock harness from `merge_gate_test.sh` cleanly up to `banner "MG-1` (`sed -e ... /banner "MG-1/,$d`), preventing truncation on comment separators (R1-7).
  - Verifies harness sourced successfully via `type mk_green`.
  - Fixes assertion count invariant (`TOTAL=8`, each assertion calls `pass` or `fail` exactly once, no phantom totals from harness helper exit codes) (R1-8).
  - Uses `mergestate_checks_attempt` with dynamic state padding and `$n` / `$idx` dispatch in `gh` stub to ensure multi-attempt check fixtures advance cleanly (R1-1).
  - Tests actual gate behavior with positive and negative controls rather than source string comments (R1-2, R1-3).
  - Asserts dual-case transient polling covering in-flight checks and `UNKNOWN` mergeStateStatus (R1-4).
- **Done-When:**
  Running `bash scripts/ci/tests/merge_gate_transient_polling_contract_test.sh` executes all 8 assertions, reports clean assertion failures (`Total: 8, Passed: 0, Failed: 8`) without syntax or runtime errors, and exits with code 1.

---

### Task T2: Implement In-Gate Bounded Transient Check Polling in `scripts/ci/merge_gate.sh`
- **Owner:** odyssey (Implement stage)
- **Risk:** high (DEEP-3, DEEP-5: alters core merge gate polling and merge execution)
- **Files touched:** `scripts/ci/merge_gate.sh`
- **Decisions implemented:** D1, D2, D3, D4, D5
- **Acceptance criteria proven:** AT-514-1, AT-514-2, AT-514-3, AT-514-4, AT-514-5, AT-514-6
- **Step-by-step diff description:**
  1. Define configurable timeout and poll interval environment variable defaults near lines 268–270:
     ```bash
     MERGE_GATE_TRANSIENT_TIMEOUT="${MERGE_GATE_TRANSIENT_TIMEOUT:-120}"
     MERGE_GATE_TRANSIENT_POLL_INTERVAL="${MERGE_GATE_TRANSIENT_POLL_INTERVAL:-5}"
     ```
  2. In the conjunct (2) evaluation section (around line 471), compute `OTHER_CONJUNCTS_OK`:
     ```bash
     OTHER_CONJUNCTS_OK=0
     [ "${C[1]}" = 1 ] && [ "${C[3]}" = 1 ] && [ "${C[4]}" = 1 ] && [ "${C[5]}" = 1 ] && \
     [ "${C[6]}" = 1 ] && [ "${C[7]}" = 1 ] && [ "${C[8]}" = 1 ] && [ "${C[9]}" = 1 ] && \
     [ "${C[10]}" = 1 ] && [ "${C[11]}" = 1 ] && OTHER_CONJUNCTS_OK=1
     ```
  3. When `OTHER_CONJUNCTS_OK=1`:
     a. If `MERGE_STATE` is `UNKNOWN`: enter the bounded polling loop re-reading `read_merge_state`. If it resolves to `CLEAN`/`UNSTABLE`, continue to check evaluation. If timeout expires while still `UNKNOWN`, set `WHY[2]="mergeStateStatus is still UNKNOWN after ${elapsed}s — unevaluable (D24)"`, append `refusal:unknown` to ledger, and break.
     b. When `MERGE_STATE` is `CLEAN` or `UNSTABLE`:
        Parse checks with an awk script separating `passing`, `transient`, and `terminal` states.
        - If all checks pass: set `C[2]=1`.
        - If foreign checks are in transient states (`IN_PROGRESS`, `QUEUED`, `PENDING`, `WAITING`, `REQUESTED`):
          Enter bounded polling loop. Sleep `MERGE_GATE_TRANSIENT_POLL_INTERVAL` (if > 0) unless elapsed time exceeds `MERGE_GATE_TRANSIENT_TIMEOUT`.
          On each iteration, call `read_merge_state` and re-evaluate.
          - If all checks reach passing states: set `C[2]=1` and break.
          - If any check reaches terminal failure (`FAILURE`, `CANCELLED`, `TIMED_OUT`, `ACTION_REQUIRED`, `STALE`, `STARTUP_FAILURE`): abort polling immediately, set `WHY[2]="mergeStateStatus $MERGE_STATE but check(s) not success:$failing"`, and break.
          - If timeout expires: set `WHY[2]="mergeStateStatus $MERGE_STATE but check(s) in flight timed out after ${elapsed}s:$transient"`, and break.
  4. When `OTHER_CONJUNCTS_OK=0`:
     - If `MERGE_STATE` is `UNKNOWN`: decline immediately as unevaluable (`refusal:unknown`) without polling.
     - If checks are transient under `CLEAN`/`UNSTABLE`: decline immediately with `check(s) not success:$transient` without polling.
- **Done-When:**
  Contract test assertions 1, 2, 3, 4, and 5 pass.

---

### Task T3: Add Regression Test Scenarios to `scripts/ci/tests/merge_gate_test.sh`
- **Owner:** odyssey (Implement stage)
- **Files touched:** `scripts/ci/tests/merge_gate_test.sh`
- **Decisions implemented:** D1, D2, D3, D4, D5
- **Acceptance criteria proven:** AT-514-1, AT-514-2, AT-514-3, AT-514-4, AT-514-5, AT-514-6
- **Step-by-step diff description:**
  1. Support per-attempt check files in `merge_gate_test.sh`'s `gh` stub using call count `$n` and clamped `$idx`:
     ```bash
     c_file="$FX/mergestate-$pr.checks.$n"; [ -f "$c_file" ] || c_file="$FX/mergestate-$pr.checks.$idx"; [ -f "$c_file" ] || c_file="$FX/mergestate-$pr.checks"
     ```
     Ensure `mergestate_fixture` or helpers provide multiple state lines when multiple attempts are expected so `$idx` does not clamp to 0.
  2. Add test scenario `MG-2c: in-flight check polls to success and merges`:
     PR has an `IN_PROGRESS` check on attempt 0 that transitions to `SUCCESS` on attempt 1. Assert PR merges.
  3. Add test scenario `MG-2d: precondition gating skips polling when conjunct (4) fails`:
     PR has `C[4]=0` (open blocking finding) and an `IN_PROGRESS` check. Assert gate declines immediately without polling attempts (`mergestate-$pr.count` == 1).
  4. Add test scenario `MG-2e: immediate abort on terminal check failure`:
     PR has one `FAILURE` check and one `IN_PROGRESS` check. Assert gate aborts immediately without waiting for in-flight checks (`mergestate-$pr.count` == 1).
  5. Add test scenario `MG-2f: in-flight check timeout diagnostic`:
     PR has `IN_PROGRESS` check through timeout. Assert `WHY[2]` contains `check(s) in flight timed out after`.
  6. Add test scenario `MG-2g: UNKNOWN mergeStateStatus polls to CLEAN and merges`:
     PR has `UNKNOWN` mergeStateStatus on attempt 0 that transitions to `CLEAN` on attempt 1. Assert PR merges.
- **Done-When:**
  `bash scripts/ci/tests/merge_gate_test.sh` exits 0 with all test assertions passing, and contract test assertion 6 passes.

---

### Task T4: Update Living Spec in `docs/SPEC.md`
- **Owner:** odyssey (Implement stage)
- **Files touched:** `docs/SPEC.md`
- **Decisions implemented:** D6
- **Acceptance criteria proven:** AT-514-7
- **Step-by-step diff description:**
  Under `### loop.autonomous` (conjunct 2 description), update documentation to state:
  When foreign check runs are in transient states (`IN_PROGRESS`, `QUEUED`, `PENDING`, `WAITING`, `REQUESTED`) or `mergeStateStatus` is `UNKNOWN`, and all other conjuncts (1, 3, 4, 5, 6, 7, 8, 9, 10, 11) evaluate true, `merge_gate.sh` executes an in-gate bounded polling loop up to `MERGE_GATE_TRANSIENT_TIMEOUT` (default 120s) with interval `MERGE_GATE_TRANSIENT_POLL_INTERVAL` (default 5s). Polling aborts immediately if any check resolves to a terminal failure state or mergeStateStatus becomes terminal. Setting interval or timeout to 0 enables zero-sleep hermetic testing.
- **Done-When:**
  Contract test assertion 7 passes, and `bash scripts/ci/spec_check.sh origin/main <pr-body>` exits 0.

---

### Task T5: Update Release Notes in `CHANGELOG.md`
- **Owner:** odyssey (Implement stage)
- **Files touched:** `CHANGELOG.md`
- **Decisions implemented:** D7
- **Acceptance criteria proven:** AT-514-9
- **Description:** Document the bug fix in `CHANGELOG.md` under the current release / unreleased section:
  Record that `scripts/ci/merge_gate.sh` implements an in-gate bounded polling loop for transient conjunct (2) check states, resolving premature gate declines that stranded merge-ready pull requests (#514).
- **Done-When:**
  `bash scripts/ci/changelog_check.sh origin/main <pr-body>` exits 0, and contract test assertion 8 passes.

---

### Task T6: Verify Full Test Suite and Verification Gates
- **Owner:** odyssey (Implement stage)
- **Files touched:** None
- **Decisions implemented:** D1–D7
- **Acceptance criteria proven:** AT-514-1 through AT-514-9
- **Description:** Run all verification gates:
  1. `bash scripts/ci/tests/merge_gate_transient_polling_contract_test.sh` exits 0 with 8/8 passed.
  2. `bash scripts/ci/tests/merge_gate_test.sh` exits 0 with all scenarios passing.
  3. `bash scripts/ci/spec_check.sh origin/main <pr-body>` exits 0.
  4. `bash scripts/ci/changelog_check.sh origin/main <pr-body>` exits 0.
  5. `git diff --name-only origin/main` matches only allowed manifest files (AT-514-8).
- **Done-When:**
  All verification commands exit 0.

---

## 5. Traceability Matrix

| Decision ID | Summary | Plan Tasks | Contract Assertion / Acceptance Criteria |
|---|---|---|---|
| **D1** | In-gate bounded polling loop for transient checks (`IN_PROGRESS`, `QUEUED`, `PENDING`, `WAITING`, `REQUESTED`, `UNKNOWN`) | T1, T2, T3 | AT-514-1 (Assertions 1, 2) |
| **D2** | Precondition gating: poll if and only if all other conjuncts (1, 3..11) hold | T1, T2, T3 | AT-514-2 (Assertion 3) |
| **D3** | Fail-fast immediate abort on terminal check failure or terminal merge state | T1, T2, T3 | AT-514-3 (Assertion 4) |
| **D4** | Configurable timeout bounds (`MERGE_GATE_TRANSIENT_TIMEOUT`, `MERGE_GATE_TRANSIENT_POLL_INTERVAL`) with zero-delay testing | T1, T2, T3 | AT-514-4, AT-514-5 (Assertions 1, 5) |
| **D5** | Explicit diagnostic categorization in gate output and `WHY[2]` (`timed out after` vs `not success:`) | T1, T2, T3 | AT-514-6 (Assertion 5) |
| **D6** | Living specification update obligation in `docs/SPEC.md` | T1, T4 | AT-514-7 (Assertion 7) |
| **D7** | Scope boundary and permitted file manifest enforcement | T1, T2, T3, T4, T5, T6 | AT-514-8, AT-514-9 (Assertion 8) |

---

## 6. Review Round 1 Ledger Reconciliation

This plan and contract test suite resolve the findings raised by Argus during Round 1 deep review of PR #528:

| Finding ID | Severity | Disposition | Resolution Details |
|---|---|---|---|
| **R1-1@D1** | `high` | fixed | Multi-attempt checks fixture in `scripts/ci/tests/merge_gate_transient_polling_contract_test.sh` updated: `mergestate_checks_attempt` dynamically pads `mergestate-$pr.state` so `$idx` does not clamp to 0, and the `gh` stub checks `$n` then `$idx`. Task T3 explicitly instructs Odyssey to apply the same mechanism to `merge_gate_test.sh`. |
| **R1-2@D3** | `normal` | fixed | Removed invalid literal-pipe grep (`\|`). Assertion 4 replaced with a pure behavioral assertion executing `run_gate` against a multi-attempt fixture with terminal failure, verifying immediate abort (calls <= 1) and decline diagnostics. |
| **R1-3@D2** | `normal` | fixed | Replaced comment-matching greps across Assertions 1, 2, 3, 4, and 5 with behavioral executions of `run_gate` against the mock test harness with positive controls (requiring transient polling to succeed) and negative controls (verifying precondition gating and early abort). Comment-only mutations now cleanly fail 5 of 8 assertions. |
| **R1-4@D1** | `normal` | fixed | `mergeStateStatus: UNKNOWN` polling trigger added to Plan §P2 and Task T2 step 3, replacing the line 480 short-circuit when `OTHER_CONJUNCTS_OK=1`. Assertion 2 Subcase B asserts `UNKNOWN` polls to `CLEAN` and merges. Task T3 adds regression scenario `MG-2g`. |
| **R1-5@D7** | `normal` | fixed | Clarified in Section 2 that `scripts/ci/tests/merge_gate_transient_polling_contract_test.sh` is authored and committed by Daedalus on this Build PR (#528) within Daedalus's permitted authority (`scripts/*/tests/**`). The implementing PR (Odyssey) branches from main after this PR merges and touches only permitted files per D7. |
| **R1-6@D7** | `normal` | noted | Acknowledged that workflow files (`.github/workflows/*`) are strictly forbidden by D7 to bound blast radius; contract suite execution is verified at build and implement rungs via Task T6 checklist. |
| **R1-7@none** | `normal` | fixed | Test harness extraction boundary in `merge_gate_transient_polling_contract_test.sh` changed from `/^# ---*$/q` to `/^banner "MG-1/,$d`, decoupling helper sourcing from comment banners, and verified via `type mk_green`. |
| **R1-8@none** | `suggestion` | fixed | Assertion total pinned as a constant `TOTAL=8`, and `run_gate` refactored so non-zero exits from the gate do not increment assertion counters or create phantom rows. |
