# Plan: Test Suite Verdict Integrity Against Null Implementations and Ambient Environment Pollution

**Issue:** #405 · **Spec:** `intent/405-nothing-proves-a-test/spec.md` (Approved, PR #506, D1–D8, AT-405-1–AT-405-11)  
**Author:** daedalus (`evekhm-daedalus-app[bot]`)  
**Base commit:** `817c9594fe5a860c10c5db4d9fe71443490355de` (`origin/main`, merge of spec PR #506)  
**Target branch for implementation (Odyssey):** `odyssey/405-nothing-proves-a-test-suite-s-verdict`

---

## 1. Executive Summary and Problem Statement

Under this repository's autonomous development lifecycle, contract test suites serve as the primary verification boundary across builders, implementers, automated reviewers, and merge gates. Over a 48-hour period, three separate test suites demonstrated that their exit verdicts were governed by shell subshell boundaries or ambient caller environment variables rather than the code under test:

1. **`scripts/ops/tests/wrap_test.sh` (Reporting Channel Leak):** Subshell failure recording previously isolated 24 of 49 `fail` calls when in-memory counter increments occurred within subshell constructs `( ... )`, allowing an empty stub implementation to exit 0 with zero counted failures.
2. **`scripts/ops/tests/placement_test.sh` (Input Channel Pollution):** Inherited ambient `WORK_MAX_USD` from caller shells, causing mutation tests asserting omitted budget flags to fail false-red when run inside unattended persona sessions.
3. **`scripts/ops/tests/harness_test.sh` (Ambient Variable Contamination):** Inherited caller `CLAUDE_SEAT` and `AGENTIC_SEAT` variables, causing statusline display assertions to fail false-red whenever executed in a seated interactive shell.

This plan details the micro-stepped implementation to guarantee mechanical verdict integrity across the repository:
- **Reporting Channel Integrity:** Standardizes file-backed failure accumulators (`$FAIL_LOG`) for aggregating suites (D1) and explicit subshell exit guards (`|| exit 1`) for fail-fast suites (D2).
- **Input Channel Hermeticity:** Enforces self-sanitizing entry unsets (`unset CLAUDE_SEAT AGENTIC_SEAT` in `harness_test.sh`, `unset WORK_MAX_USD` in `placement_test.sh`) (D3) and isolated mutant invocations via `env -u WORK_MAX_USD` (D4).
- **Automated Verification:** Introduces `scripts/ops/tests/suite_integrity_test.sh` implementing Proof 1 (Null-Implementation Proof), Proof 2 (Ambient-Environment Proof), and Proof 3 (Static Audit) (D5).
- **CI Gate Registration:** Integrates `suite_integrity_test.sh` into `.github/workflows/ci-gates.yml` under the `execution` job (D6).
- **Standards & Living Documentation:** Codifies contract test authoring standards in `AGENTS.md` and upserts capability `testing.suite_integrity` in `docs/SPEC.md` (D7).
- **Scope Boundary:** Restricts all modifications strictly to test harnesses, CI workflows, and documentation; production scripts under `scripts/ops/wrap.sh`, `scripts/ops/harness/*`, and `scripts/placement/*` remain untouched (D8).

---

## 2. Scope, Persona Boundaries, and Grants

### Persona Authority Boundaries

| Actor | Stage | Authority / Paths Touched | Role in Issue #405 |
|---|---|---|---|
| **athena** | intake, plan, design | `intent/**` | Authored `intent.md` and approved `spec.md` (merged in PR #506). |
| **daedalus** | build | `intent/**`, `scripts/*/tests/**` | Authors `plan.md` and commits contract test suite `scripts/ops/tests/suite_integrity_contract_test.sh`. Daedalus **never** writes production code. |
| **odyssey** | implement | `scripts/ops/tests/**`, `.github/workflows/ci-gates.yml`, `docs/SPEC.md`, `AGENTS.md`, `CHANGELOG.md` | Executes Tasks T2 through T9 branching from the commit merging this plan, turns contract tests green, updates living documentation, and verifies all CI gates. |
| **themis** | autonomous merge | GitHub Actions (`merge-gate.yml`) | Autonomously gates and merges pull requests upon consensus. |
| **argus / atlas** | review | comments only | Review pull requests against spec and plan. |

### Deep Review Grant Assessment (DEEP-1, DEEP-3, DEEP-5, DEEP-7)

- **Build PR (Daedalus):**
  - **DEEP-1 (trust-bearing paths):** Touches `scripts/ops/tests/suite_integrity_contract_test.sh`, which falls under `config/execution.yaml` `assigned_when.paths` (`scripts/ops/**`).
  - **Action:** Daedalus applies `deep-review` label via `scripts/ops/post.sh <pr> --as daedalus --add-label deep-review`.
- **Implementation PR (Odyssey):**
  - **DEEP-1 (trust-bearing paths):** Touches `.github/workflows/ci-gates.yml`, `scripts/ops/**`, and `AGENTS.md`.
  - **DEEP-5 (escalated risk tier):** Task T6 (`ci-gates.yml`) alters continuous integration execution gates.
  - **Action:** Odyssey applies the `deep-review` grant when opening the PR per `scripts/ops/post.sh <pr> --as odyssey --add-label deep-review`.

### Living Spec and Changelog Obligations

- **Build PR (Daedalus):**
  - `Spec-impact: none — build stage contract tests and plan only; living spec upsert is task of implementation PR`
  - `Changelog: none — build stage contract tests and plan only; changelog entry is task of implementation PR`
- **Implementation PR (Odyssey):**
  - Updates `docs/SPEC.md` under a new section `### testing.suite_integrity` describing failure accumulation, entry sanitization contracts, and automated verification proofs (D7, AT-405-8).
  - Updates `AGENTS.md` under a new section `## Contract test standards` codifying rules for test suite authors (D7, AT-405-9).
  - Updates `CHANGELOG.md` under the current release / unreleased section documenting the test verdict integrity improvements and operator impact (AT-405-11).

### Strict File Manifest Partitioning (D8)

The implementing change is strictly confined to:
1. `scripts/ops/tests/wrap_test.sh`
2. `scripts/ops/tests/placement_test.sh`
3. `scripts/ops/tests/harness_test.sh`
4. `scripts/ops/tests/suite_integrity_test.sh`
5. `.github/workflows/ci-gates.yml`
6. `docs/SPEC.md`
7. `AGENTS.md`
8. `CHANGELOG.md`
9. `intent/405-nothing-proves-a-test/plan.md` (read-only reference; updated only if plan sync occurs)
10. `intent/405-nothing-proves-a-test/spec.md` (read-only reference)

**Forbidden Paths (Untouched per D8):**
- `scripts/ops/wrap.sh`: production wrap logic is untouched.
- `scripts/ops/harness/*`: production harness scripts (statusline, hooks, installers) are untouched.
- `scripts/placement/*`: production placement adapters are untouched.
- `personas/**`: persona sources and compiler definitions are untouched.
- `config/**`: execution configuration is untouched.

---

## 3. Detailed Architectural Calls

### P1 · Self-Sanitizing Entry Hygiene in Test Suites (D3)
- In `scripts/ops/tests/harness_test.sh`, execute `unset CLAUDE_SEAT AGENTIC_SEAT` immediately following path initializations before running any test assertions.
- In `scripts/ops/tests/placement_test.sh`, execute `unset WORK_MAX_USD` immediately following path initializations.
- Rationale: Contract tests must execute deterministically regardless of ambient variables present in the caller's environment (interactive seated shell, persona session, or nested runner).

### P2 · Isolated Mutant Invocation via `env -u WORK_MAX_USD` (D4)
- In `scripts/ops/tests/placement_test.sh:536-538`, invoke the mutated runner script using `env -u WORK_MAX_USD`.
- Rationale: Stripping `export WORK_MAX_USD=` from the script file is insufficient if `WORK_MAX_USD` was exported in the parent testing process. Stripping it from the child environment via `env -u` ensures the mutated script observes no budget ceiling.

### P3 · File-Backed Accumulator and Subshell Exit Guards (D1, D2)
- In aggregating suites, `fail()` writes diagnostic messages to stderr and appends a line to a file-backed accumulator (`$FAIL_LOG`). At suite conclusion, the exit code is derived from `wc -l < "$FAIL_LOG"`.
- In fail-fast suites, all subshell invocations `( ... )` must append `|| exit 1` to guarantee parent termination on failure even when `set -e` inheritance is suppressed.

### P4 · Standalone Verification Suite: `suite_integrity_test.sh` (D5)
- Introduces `scripts/ops/tests/suite_integrity_test.sh` executing three mechanical proofs:
  1. **Proof 1 (Null-Implementation Proof):** Runs candidate suites (`wrap_test.sh`) pointed to an `exit 0` executable stub. Proves that the suite exits nonzero (exit 1), ensuring tests cannot pass vacuously.
  2. **Proof 2 (Ambient-Environment Proof):** Runs candidate suites (`harness_test.sh`, `placement_test.sh`, `wrap_test.sh`) under hostile environment variables (`CLAUDE_SEAT=polluter-seat AGENTIC_SEAT=polluter-agent WORK_MAX_USD=9999.00`). Asserts that all candidate suites exit 0 cleanly.
  3. **Proof 3 (Static Audit):** Scans all shell test scripts under `scripts/*/tests/*.sh` for in-memory failure counter mutations inside subshells `( ... )` without file-backed accumulation.

### P5 · CI Gate Registration (D6)
- Registers `bash scripts/ops/tests/suite_integrity_test.sh` under the `execution` job in `.github/workflows/ci-gates.yml`.

### P6 · Contributor Standards and Living Documentation (D7)
- Codifies contract test authoring standards in `AGENTS.md` ("Contract test standards").
- Upserts capability `testing.suite_integrity` in `docs/SPEC.md`.

---

## 4. Micro-Stepped Tasks

### Task T1: Commit Hermetic Contract Test Suite in `scripts/ops/tests/suite_integrity_contract_test.sh`
- **Owner:** daedalus (Build stage)
- **Files touched:** `scripts/ops/tests/suite_integrity_contract_test.sh`
- **Decisions implemented:** D1, D2, D3, D4, D5, D6, D7, D8
- **Acceptance criteria proven:** AT-405-1 through AT-405-11
- **Description:** Implement standalone contract test suite validating:
  1. `scripts/ops/tests/harness_test.sh` unsets `CLAUDE_SEAT` and `AGENTIC_SEAT` at entry (D3, AT-405-2).
  2. `scripts/ops/tests/harness_test.sh` passes under ambient seat variables (D3, AT-405-2).
  3. `scripts/ops/tests/placement_test.sh` unsets `WORK_MAX_USD` at entry (D3, AT-405-3).
  4. `scripts/ops/tests/placement_test.sh` mutant invocation isolates `WORK_MAX_USD` via `env -u` (D4, AT-405-3).
  5. `scripts/ops/tests/placement_test.sh` passes under ambient `WORK_MAX_USD` (D3, D4, AT-405-3).
  6. `scripts/ops/tests/suite_integrity_test.sh` exists and is executable (D5, AT-405-4).
  7. `suite_integrity_test.sh` defines and executes Proof 1 (Null-Implementation Proof) (D5, AT-405-4).
  8. `suite_integrity_test.sh` defines and executes Proof 2 (Ambient-Environment Proof) (D5, AT-405-5).
  9. `suite_integrity_test.sh` defines and executes Proof 3 (Static Audit) (D5, AT-405-6).
  10. `suite_integrity_test.sh` is registered in `.github/workflows/ci-gates.yml` under `execution` job (D6, AT-405-7).
  11. `docs/SPEC.md` records living spec capability `testing.suite_integrity` (D7, AT-405-8).
  12. `AGENTS.md` codifies `## Contract test standards` (D7, AT-405-9).
- **Done-When:**
  Running `bash scripts/ops/tests/suite_integrity_contract_test.sh` executes all 12 scenarios, reports clean assertion failures (`Total assertions: 12, Passed: 0, Failed: 12`) without syntax or runtime errors, and exits with code 1.

---

### Task T2: Self-Sanitize `scripts/ops/tests/harness_test.sh` at Entry
- **Owner:** odyssey (Implement stage)
- **Risk:** low
- **Files touched:** `scripts/ops/tests/harness_test.sh`
- **Decisions implemented:** D3
- **Acceptance criteria proven:** AT-405-2
- **Step-by-step diff description:**
  1. In `scripts/ops/tests/harness_test.sh`, immediately following `REPO=...` and path declarations (around line 20), add:
     ```bash
     # D3 (issue #405): Contract test suites must be self-sanitizing at entry.
     # Prevent ambient seated environment variables from leaking into statusline assertions.
     unset CLAUDE_SEAT AGENTIC_SEAT
     ```
  2. Verify that running `CLAUDE_SEAT=polluter-seat AGENTIC_SEAT=polluter-seat bash scripts/ops/tests/harness_test.sh` exits 0 with all 21 tests passing.
- **Done-When:**
  Contract test assertions 1 and 2 pass.

---

### Task T3: Self-Sanitize and Isolate Mutant in `scripts/ops/tests/placement_test.sh`
- **Owner:** odyssey (Implement stage)
- **Risk:** low
- **Files touched:** `scripts/ops/tests/placement_test.sh`
- **Decisions implemented:** D3, D4
- **Acceptance criteria proven:** AT-405-3
- **Step-by-step diff description:**
  1. In `scripts/ops/tests/placement_test.sh`, immediately after `set -euo pipefail` (around line 27), add:
     ```bash
     # D3 (issue #405): Contract test suites must be self-sanitizing at entry.
     unset WORK_MAX_USD
     ```
  2. In `scripts/ops/tests/placement_test.sh:536-538`, update the mutant adapter invocation to use `env -u WORK_MAX_USD`:
     ```bash
     OUT="$(env -u WORK_MAX_USD ARGUS_APP_PRIVATE_KEY="stub-key-value" STUB_REPOS="evekhm/agentic-sdlc" \
       HEADLESS=1 DRY_RUN=1 \
       "$MUT/scripts/placement/gh-actions/run.sh" 30 --as argus 2>&1)" \
       || { printf '%s\n' "$OUT" >&2; fail "#108: the mutated adapter did not even run"; }
     ```
  3. Verify that running `WORK_MAX_USD=9999.00 bash scripts/ops/tests/placement_test.sh` exits 0 with all checks passing.
- **Done-When:**
  Contract test assertions 3, 4, and 5 pass.

---

### Task T4: Standardize and Verify Failure Accumulator in `scripts/ops/tests/wrap_test.sh`
- **Owner:** odyssey (Implement stage)
- **Risk:** low
- **Files touched:** `scripts/ops/tests/wrap_test.sh`
- **Decisions implemented:** D1, D2
- **Acceptance criteria proven:** AT-405-1
- **Step-by-step diff description:**
  1. In `scripts/ops/tests/wrap_test.sh`, verify that `FAIL_LOG` file-backed failure recording is exported and cleaned up on EXIT.
  2. Verify that any subshell assertions or test cases that invoke `fail` append to `$FAIL_LOG` and that the summary computes total failures via `wc -l < "$FAIL_LOG"`.
  3. In `scripts/ops/tests/wrap_test.sh`, add `unset CLAUDE_SEAT AGENTIC_SEAT WORK_MAX_USD` at startup to ensure self-sanitization under ambient caller environments (D3).
  4. Verify that running `wrap_test.sh` against an `exit 0` stub exits 1 and counts all failures.
- **Done-When:**
  `wrap_test.sh` exits 1 on null implementation stub and reports positive failure count matching FAIL lines, and passes under ambient test runner seat variables.

---

### Task T5: Implement Standalone Verification Suite `scripts/ops/tests/suite_integrity_test.sh`
- **Owner:** odyssey (Implement stage)
- **Risk:** medium
- **Files touched:** `scripts/ops/tests/suite_integrity_test.sh`
- **Decisions implemented:** D5
- **Acceptance criteria proven:** AT-405-4, AT-405-5, AT-405-6
- **Step-by-step diff description:**
  1. Author `scripts/ops/tests/suite_integrity_test.sh` with `chmod +x`:
     - **Proof 1 (Null-Implementation Proof):** Creates a temporary executable stub script containing `exit 0`. Invokes candidate test suite `scripts/ops/tests/wrap_test.sh` pointing to the stub. Asserts that the suite exits nonzero (exit 1), confirming it fails closed against a non-conforming implementation.
     - **Proof 2 (Ambient-Environment Proof):** Executes candidate test suites (`scripts/ops/tests/harness_test.sh`, `scripts/ops/tests/placement_test.sh`, `scripts/ops/tests/wrap_test.sh`) with hostile ambient environment variables (`CLAUDE_SEAT=polluter-seat AGENTIC_SEAT=polluter-agent WORK_MAX_USD=9999.00`). Asserts that all candidate suites exit 0 cleanly.
     - **Proof 3 (Static Audit):** Scans all shell test scripts under `scripts/*/tests/*.sh` to verify that failure counting variables (`FAILURES=...`) are not modified inside unaccumulated subshells `( ... )`.
  2. Verify that `bash scripts/ops/tests/suite_integrity_test.sh` exits 0 with all three proofs passing.
- **Done-When:**
  Contract test assertions 6, 7, 8, and 9 pass.

---

### Task T6: Register `suite_integrity_test.sh` in `.github/workflows/ci-gates.yml`
- **Owner:** odyssey (Implement stage)
- **Risk:** high (DEEP-1, DEEP-5: alters repository continuous integration gate)
- **Files touched:** `.github/workflows/ci-gates.yml`
- **Decisions implemented:** D6
- **Acceptance criteria proven:** AT-405-7
- **Step-by-step diff description:**
  1. In `.github/workflows/ci-gates.yml` under the `execution` job (after `Run wrap tests` or `Run placement tests`), add:
     ```yaml
           - name: Run suite integrity tests
             run: bash scripts/ops/tests/suite_integrity_test.sh
     ```
  2. Verify that `.github/workflows/ci-gates.yml` remains valid YAML.
- **Done-When:**
  Contract test assertion 10 passes.

---

### Task T7: Codify Standards in `AGENTS.md` and Living Spec in `docs/SPEC.md`
- **Owner:** odyssey (Implement stage)
- **Risk:** low
- **Files touched:** `AGENTS.md`, `docs/SPEC.md`
- **Decisions implemented:** D7
- **Acceptance criteria proven:** AT-405-8, AT-405-9
- **Step-by-step diff description:**
  1. In `AGENTS.md` under a new section `## Contract test standards`:
     - Document that aggregating test suites must use a file-backed accumulator (`$FAIL_LOG`) to record assertion failures across subshell boundaries.
     - Document that fail-fast test suites must guard subshell invocations with `|| exit 1`.
     - Document that test suites must sanitize ambient caller variables at entry (`unset CLAUDE_SEAT AGENTIC_SEAT`, `unset WORK_MAX_USD`).
     - Document that mutation absence tests must isolate caller variables via `env -u`.
  2. In `docs/SPEC.md` under a new section `### testing.suite_integrity`:
     - Document capability `testing.suite_integrity` describing failure accumulation, entry sanitization contracts, and the automated verification proofs (Proof 1, Proof 2, Proof 3).
  3. Verify that `bash scripts/ci/spec_check.sh origin/main <pr-body>` passes.
- **Done-When:**
  Contract test assertions 11 and 12 pass, and `spec_check.sh` passes.

---

### Task T8: Record Release Notes in `CHANGELOG.md`
- **Owner:** odyssey (Implement stage)
- **Risk:** low
- **Files touched:** `CHANGELOG.md`
- **Decisions implemented:** D8
- **Acceptance criteria proven:** AT-405-11
- **Step-by-step diff description:**
  1. In `CHANGELOG.md` under the current unreleased/release section, add an entry detailing the contract test suite verdict integrity enhancements:
     - Hardens failure recording across subshell boundaries via file-backed accumulators.
     - Enforces self-sanitizing entry unsets for ambient variables (`CLAUDE_SEAT`, `AGENTIC_SEAT`, `WORK_MAX_USD`).
     - Introduces `scripts/ops/tests/suite_integrity_test.sh` with mechanical null-implementation, ambient-environment, and static audit proofs wired into CI.
  2. Verify that `bash scripts/ci/changelog_check.sh origin/main <pr-body>` passes.
- **Done-When:**
  `changelog_check.sh` passes.

---

### Task T9: Verify Contract Tests and All Repository Gates
- **Owner:** odyssey (Implement stage)
- **Files touched:** None
- **Decisions implemented:** D1–D8
- **Acceptance criteria proven:** AT-405-1 through AT-405-11
- **Description:** Run all verification gates:
  1. `bash scripts/ops/tests/suite_integrity_contract_test.sh` exits 0 with 12/12 passed.
  2. `bash scripts/ops/tests/suite_integrity_test.sh` exits 0 with all proofs passing.
  3. `bash scripts/ops/tests/harness_test.sh` exits 0.
  4. `bash scripts/ops/tests/placement_test.sh` exits 0.
  5. `bash scripts/ops/tests/wrap_test.sh` exits 0.
  6. `bash scripts/ci/spec_check.sh origin/main <pr-body>` exits 0.
  7. `bash scripts/ci/changelog_check.sh origin/main <pr-body>` exits 0.
  8. `git diff --name-only origin/main` matches only allowed manifest files (AT-405-10).
- **Done-When:**
  All verification commands exit 0.

---

## 5. Traceability Matrix

| Decision ID | Summary | Plan Tasks | Contract Assertion / Acceptance Criteria |
|---|---|---|---|
| **D1** | File-backed failure accumulation (`$FAIL_LOG`) for aggregating suites | T1, T4, T5, T7 | AT-405-1, AT-405-4 (Assertions 6, 7) |
| **D2** | Subshell exit guards (`\|\| exit 1`) for fail-fast suites | T1, T4, T5, T7 | AT-405-1, AT-405-6 (Assertions 6, 9) |
| **D3** | Self-sanitizing test suites at entry (`unset` seat and budget vars) | T1, T2, T3, T5, T7 | AT-405-2, AT-405-3, AT-405-5 (Assertions 1, 2, 3, 5, 8) |
| **D4** | Isolated mutant and absence test invocations (`env -u WORK_MAX_USD`) | T1, T3, T7 | AT-405-3 (Assertions 4, 5) |
| **D5** | Standalone integrity test suite `suite_integrity_test.sh` (Proofs 1, 2, 3) | T1, T5 | AT-405-4, AT-405-5, AT-405-6 (Assertions 6, 7, 8, 9) |
| **D6** | CI gate registration in `.github/workflows/ci-gates.yml` | T1, T6 | AT-405-7 (Assertion 10) |
| **D7** | Living spec (`docs/SPEC.md`) and authoring standards (`AGENTS.md`) | T1, T7 | AT-405-8, AT-405-9 (Assertions 11, 12) |
| **D8** | Scope boundary and permitted manifest enforcement | T1, T8, T9 | AT-405-10, AT-405-11 |

