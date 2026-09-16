# Spec: Test suite verdict integrity against null implementations and ambient environment pollution

**Issue:** #405 · **Status:** Approved (approval = merge of this PR) · **Author:** athena (`evekhm-athena-app[bot]`) · **Open questions:** none

## What is being built

Under this repository autonomous development lifecycle, contract test suites form the verification boundary for builders, implementers, reviewers, and automated merge gates. Three test suites demonstrated that their exit verdicts depended on shell subshell boundaries or ambient environment state instead of the code under test:
1. `scripts/ops/tests/wrap_test.sh`: subshell failure recording isolated 24 of 49 `fail` calls, allowing an empty stub implementation to pass with zero counted failures.
2. `scripts/ops/tests/placement_test.sh`: inherited caller `WORK_MAX_USD` settings, causing a mutation test to fail when run inside an unattended persona session.
3. `scripts/ops/tests/harness_test.sh`: inherited caller `CLAUDE_SEAT` and `AGENTIC_SEAT` variables, causing statusline assertions to fail when executed in a seated shell.

This specification establishes mechanical verdict integrity across the repository test surface:
1. **Reporting Channel Integrity (Anti-False-Green):**
   - Standardizes file-backed failure accumulation (`$FAIL_LOG`) for all aggregating test suites, ensuring that every assertion failure occurring within subshells `( ... )`, pipes, or background traps propagates to the suite final exit code and failure count.
   - Mandates explicit subshell exit guards (`|| exit 1`) for all fail-fast test suites.
2. **Input Channel Hermeticity (Anti-False-Red):**
   - Mandates self-sanitizing entry hygiene for all contract test suites.
   - Clears `CLAUDE_SEAT` and `AGENTIC_SEAT` at entry in `scripts/ops/tests/harness_test.sh`.
   - Clears `WORK_MAX_USD` at entry in `scripts/ops/tests/placement_test.sh`, and isolates its mutation execution subshell with `env -u WORK_MAX_USD` (absorbing #244).
3. **Automated Suite Integrity Verification:**
   - Introduces `scripts/ops/tests/suite_integrity_test.sh` executing three mechanical proofs:
     - Proof 1 (Null-Implementation Proof): Asserts that candidate suites fail closed (exit nonzero) when run against an `exit 0` stub script.
     - Proof 2 (Ambient-Environment Proof): Asserts that candidate suites pass cleanly (exit 0) when run under hostile ambient variables (`CLAUDE_SEAT=polluter-seat AGENTIC_SEAT=polluter-agent WORK_MAX_USD=9999.00`).
     - Proof 3 (Static Audit): Scans all shell test suites in `scripts/*/tests/*.sh` for in-memory failure counter mutations inside subshells.
4. **CI Enforcement and Living Documentation:**
   - Registers `suite_integrity_test.sh` in `.github/workflows/ci-gates.yml` under the `execution` job.
   - Updates `docs/SPEC.md` with capability `testing.suite_integrity`.
   - Updates `AGENTS.md` with explicit contract test authoring standards.

### Manifest of Files Touched by the Implementation Rung

- `scripts/ops/tests/wrap_test.sh`: failure accumulator verification ensuring subshell failures increment the exit count.
- `scripts/ops/tests/placement_test.sh`: environment sanitization at entry and `env -u WORK_MAX_USD` on the mutant invocation (lines 536-538).
- `scripts/ops/tests/harness_test.sh`: environment sanitization (`unset CLAUDE_SEAT AGENTIC_SEAT`) at entry.
- `scripts/ops/tests/suite_integrity_test.sh`: automated test suite executing Proof 1, Proof 2, and Proof 3.
- `.github/workflows/ci-gates.yml`: wires `scripts/ops/tests/suite_integrity_test.sh` into the `execution` job.
- `docs/SPEC.md`: upserts capability `testing.suite_integrity`.
- `AGENTS.md`: adds the "Contract test standards" section.
- `CHANGELOG.md`: records the test verdict integrity capability.
- `intent/405-nothing-proves-a-test/plan.md`: implementation plan authored by Daedalus.

### Manifest of Files Touched by this PR (Athena)

- `intent/405-nothing-proves-a-test/spec.md`: this specification.

### Forbidden Files (Untouched)

- `scripts/ops/wrap.sh`: production wrap logic is untouched.
- `scripts/ops/harness/*`: production statusline and session hooks are untouched.
- `scripts/placement/*`: production placement adapters are untouched.
- `personas/**`: persona sources and compiler definitions are untouched.
- `config/**`: execution configuration is untouched.

## Decisions

| ID | Decision | Rationale |
|---|---|---|
| **D1** | **File-Backed Failure Accumulation for Aggregating Suites (Resolves Open Question 1).** Test suites that aggregate assertion failures across multiple checks and print a summary before exiting must record failures via a file-backed accumulator (`$FAIL_LOG` within `$WORK` or `$SANDBOX`). `fail()` prints diagnostic output to stderr and appends a line to `$FAIL_LOG`. The summary section computes the total failure count from `$FAIL_LOG` via `wc -l` and exits 1 if that count is greater than zero. | *Adversary analysis:* Two defensible readings: (1) Use subshell exit status aggregation (`( ... ) || fail ...`). (2) Use a file-backed accumulator (`$FAIL_LOG`). Differing case: A test suite executes a subshell containing multiple assertion points (`( cd "$SANDBOX" && ...; fail "first failure"; ...; fail "second failure" )`). Under Reading 1, if the subshell aborts on the first failure, subsequent failures remain unobserved. If the subshell continues, earlier failures are discarded upon subshell exit, causing the parent shell to exit 0. Under Reading 2, both failures write to `$FAIL_LOG`. The parent shell reads `$FAIL_LOG`, reports two failures, and exits 1. |
| **D2** | **Subshell Exit Guards for Fail-Fast Suites.** Fail-fast test suites (suites whose `fail()` terminates execution immediately via `exit 1`) that execute assertions or fixture setups within subshells must append `|| exit 1` to every subshell invocation `( ... )`. | *Adversary analysis:* Two defensible readings: (1) Rely on `set -e` in the parent script to catch subshell non-zero exits. (2) Mandate explicit `|| exit 1` guards on subshell invocations. Differing case: A subshell runs within a compound command, conditional block, or command substitution where bash disables `set -e` inheritance. Under Reading 1, an assertion failure inside the subshell exits the subshell with code 1, but the parent script continues executing. Under Reading 2, the `|| exit 1` guard forces immediate parent process termination upon subshell failure. |
| **D3** | **Self-Sanitizing Test Suites at Entry (Resolves Open Question 2).** Contract test suites must sanitize their own execution environment at entry and must not depend on external runners or clean CI environments. Specifically: `scripts/ops/tests/harness_test.sh` must execute `unset CLAUDE_SEAT AGENTIC_SEAT` at startup before executing assertions. Tests asserting seated behavior must supply explicit seat variables on the command line for that specific invocation. `scripts/ops/tests/placement_test.sh` must execute `unset WORK_MAX_USD` at startup. | *Adversary analysis:* Two defensible readings: (1) Rely on an external invocation wrapper (such as `run_hermetic.sh`) or clean CI runners. (2) Enforce self-sanitizing entry unsets within the test scripts themselves. Differing case: An operator or unattended persona executes `bash scripts/ops/tests/harness_test.sh` directly from an interactive or seated shell where `CLAUDE_SEAT=verifier` is present in the environment. Under Reading 1, the test suite inherits `CLAUDE_SEAT` and fails false-red on four separate acceptance checks. Under Reading 2, the suite clears ambient seat variables at entry and executes cleanly to exit 0. |
| **D4** | **Isolated Mutant and Absence Test Invocations (Resolves Absorbed Issue #244).** Mutation tests asserting that an omitted configuration or stripped export removes a command flag must execute the mutated code using `env -u <VAR>` or an isolated sub-environment. In `scripts/ops/tests/placement_test.sh:536-538`, the mutant adapter invocation must execute via `env -u WORK_MAX_USD`. | *Adversary analysis:* Two defensible readings: (1) Rely on stripping the script export alone (`sed -i '/export WORK_MAX_USD=/d'`). (2) Explicitly unset the variable on the mutant invocation command (`env -u WORK_MAX_USD`). Differing case: `placement_test.sh` runs inside an unattended persona session where `WORK_MAX_USD` is exported in the caller environment. Under Reading 1, the mutated child script still inherits `WORK_MAX_USD` from the parent process, causing `--max-budget-usd` to appear in the launch output and failing the test on line 541. Under Reading 2, `env -u WORK_MAX_USD` strips the ambient variable before launching the child script, ensuring that no ceiling flag is passed and the test passes. |
| **D5** | **Standalone Integrity Verification Test Suite: `scripts/ops/tests/suite_integrity_test.sh` (Resolves Open Questions 3 & 4).** A standalone test suite `scripts/ops/tests/suite_integrity_test.sh` is introduced to mechanically verify test suite integrity. It executes three deterministic verification proofs: (1) Proof 1 (Null-Implementation Proof): Executes candidate test suites with their implementation target pointed to an executable stub that exits 0 (`exit 0`). The suite must fail closed (exit nonzero), proving that suite passage requires actual compliance. (2) Proof 2 (Ambient-Environment Proof): Executes candidate test suites (`harness_test.sh`, `placement_test.sh`, `wrap_test.sh`) under hostile ambient environment variables (`CLAUDE_SEAT=polluter-seat AGENTIC_SEAT=polluter-agent WORK_MAX_USD=9999.00`). All candidate suites must exit 0, proving isolation from ambient environment variables. (3) Proof 3 (Static Audit / Subshell Anti-Pattern Check): Scans all shell test scripts under `scripts/*/tests/*.sh` to verify that failure accounting does not rely on unprotected in-memory shell variables modified inside subshells without file-backed accumulation or explicit exit guards. | *Adversary analysis:* Two defensible readings: (1) Add internal `--verify-null` and `--verify-ambient` CLI flags to every individual test script. (2) Provide an external meta-suite that exercises candidate suites against stubs and polluted environments. Differing case: A developer authors a new contract test suite. Under Reading 1, each suite requires internal self-mocking and audit flag machinery, increasing code complexity and introducing new failure modes. Under Reading 2, suites remain standard bash scripts evaluated externally as black boxes against defined stubs and hostile environments. Candidate suites that support parameterization (such as `WRAP_SH`) are exercised for Proof 1, while the full test matrix is verified for Proof 2 and Proof 3. |
| **D6** | **Continuous Integration Gate Registration.** `scripts/ops/tests/suite_integrity_test.sh` is added as an automated test step within the `execution` job in `.github/workflows/ci-gates.yml`. | *Adversary analysis:* Two defensible readings: (1) Create a separate GitHub Actions workflow for test integrity checks. (2) Register the step in the existing `execution` job in `ci-gates.yml`. Differing case: A pull request introduces an unpinned ambient variable in a contract test suite. Under Reading 1, a separate workflow adds runner setup overhead and increases workflow proliferation. Under Reading 2, the check runs alongside the other contract suites in `execution`, catching regressions deterministically on every pull request. |
| **D7** | **Living Documentation and Authoring Standards (`AGENTS.md` and `docs/SPEC.md`).** `AGENTS.md` is updated with a section titled "Contract test standards" codifying the rules for aggregating suites (file-backed accumulators), fail-fast suites (subshell exit guards), and self-sanitizing entry hygiene. `docs/SPEC.md` is updated with capability `testing.suite_integrity` describing the failure propagation rules, entry sanitization contracts, and automated verification proofs. | *Adversary analysis:* Two defensible readings: (1) Leave authoring guidelines undocumented and enforce only through code review. (2) Codify the requirements in `AGENTS.md` and `docs/SPEC.md`. Differing case: A future persona or contributor authors a contract test suite using in-memory subshell counters or reading ambient variables. Under Reading 1, reviewers lack an authoritative repository standard to cite when rejecting the defect. Under Reading 2, the standard is explicitly stated in `AGENTS.md` and `docs/SPEC.md`. |
| **D8** | **Scope Boundary and Permitted Modifications.** The implementing PR is permitted to touch: `scripts/ops/tests/wrap_test.sh`, `scripts/ops/tests/placement_test.sh`, `scripts/ops/tests/harness_test.sh`, `scripts/ops/tests/suite_integrity_test.sh`, `.github/workflows/ci-gates.yml`, `docs/SPEC.md`, `AGENTS.md`, `CHANGELOG.md`, `intent/405-nothing-proves-a-test/plan.md`, and `intent/405-nothing-proves-a-test/spec.md`. All production scripts under `scripts/ops/wrap.sh`, `scripts/ops/harness/*`, and `scripts/placement/*` remain strictly forbidden from modification. | *Adversary analysis:* Two defensible readings: (1) Permit the implementing PR to modify production code (such as changing `statusline.sh` or `wrap.sh`). (2) Confine all changes strictly to test suites, CI workflows, and documentation. Differing case: An implementer modifies `scripts/ops/harness/statusline.sh` to ignore `CLAUDE_SEAT`. Under Reading 1, production behavior is modified, breaking seated statusline display. Under Reading 2, production behavior is preserved; only the test harnesses and documentation are updated. |

## Acceptance

- **AT-405-1 (D1):** `wrap_test.sh` failure propagation across subshells. When `scripts/ops/tests/wrap_test.sh` runs with `WRAP_SH` pointing to a stub executable that exits 0 (`exit 0`), and with the 5 static mock files present (satisfying AT-14 and AT-15), the suite exits 1, prints failure lines for behavioral assertions, and reports a total failure count greater than 0 matching the number of `FAIL:` lines printed.
  - *Red input:* A stub script where `WRAP_SH` exits 0 coupled with an in-memory counter that does not propagate subshell failures causes the suite to exit 0 with 0 failures counted, turning this assertion red.
- **AT-405-2 (D3):** `harness_test.sh` hermeticity against ambient seat variables. Executing `CLAUDE_SEAT=polluter-seat AGENTIC_SEAT=polluter-seat bash scripts/ops/tests/harness_test.sh` exits 0 with all 21 tests passing.
  - *Red input:* Unset or unpinned `CLAUDE_SEAT` in `harness_test.sh` causes AT-2, AT-3, AT-20, and AT-21 to fail due to mismatched seat suffixes in the statusline output, turning this assertion red.
- **AT-405-3 (D3, D4):** `placement_test.sh` hermeticity against ambient budget ceiling. Executing `WORK_MAX_USD=9999.00 bash scripts/ops/tests/placement_test.sh` exits 0 with all scenarios passing.
  - *Red input:* Ambient `WORK_MAX_USD=9999.00` with the un-isolated mutant invocation in `placement_test.sh:536-541` causes the mutant launch to carry `--max-budget-usd`, turning line 541 red.
- **AT-405-4 (D5):** `suite_integrity_test.sh` Proof 1 (Null-Implementation Proof). Executing `bash scripts/ops/tests/suite_integrity_test.sh` verifies that invoking `scripts/ops/tests/wrap_test.sh` with a null stub implementation exits nonzero (exit 1).
  - *Red input:* Running Proof 1 against a test suite that ignores subshell failures (exiting 0 on null implementation) causes Proof 1 to report failure and exit 1.
- **AT-405-5 (D5):** `suite_integrity_test.sh` Proof 2 (Ambient-Environment Proof). Executing `bash scripts/ops/tests/suite_integrity_test.sh` verifies that running candidate test suites (`harness_test.sh`, `placement_test.sh`, `wrap_test.sh`) under ambient variables `CLAUDE_SEAT=dirty AGENTIC_SEAT=dirty WORK_MAX_USD=9999.99` exits 0 for every candidate suite.
  - *Red input:* Any candidate suite leaking ambient variables into assertion checks fails, causing Proof 2 to report failure and exit 1.
- **AT-405-6 (D5):** `suite_integrity_test.sh` Proof 3 (Static Audit). Executing `bash scripts/ops/tests/suite_integrity_test.sh` scans test scripts under `scripts/*/tests/*.sh` and verifies that no test suite performs in-memory failure counter increments (`FAILURES=$((FAILURES + 1))`) within a `( ... )` subshell without file-backed accumulation.
  - *Red input:* Introducing an in-memory counter modification inside a subshell block in any shell test suite causes Proof 3 to detect the anti-pattern and exit 1.
- **AT-405-7 (D6):** CI registration in `.github/workflows/ci-gates.yml`. `grep -q "bash scripts/ops/tests/suite_integrity_test.sh" .github/workflows/ci-gates.yml` exits 0, confirming that `suite_integrity_test.sh` is registered as a step in the `execution` job.
  - *Red input:* Omitting the step from `.github/workflows/ci-gates.yml` causes this check to exit 1.
- **AT-405-8 (D7):** Living documentation in `docs/SPEC.md`. `docs/SPEC.md` contains a section `### testing.suite_integrity` detailing the file-backed accumulator requirement, entry sanitization requirement, and the suite integrity proofs. `bash scripts/ci/spec_check.sh` passes.
  - *Red input:* Omitting section `testing.suite_integrity` from `docs/SPEC.md` causes `scripts/ci/spec_check.sh` to fail.
- **AT-405-9 (D7):** Contributor standards in `AGENTS.md`. `AGENTS.md` contains a section "Contract test standards" mandating: (1) file-backed failure accumulators for aggregating suites, (2) subshell exit guards for fail-fast suites, and (3) entry sanitization for ambient variables.
  - *Red input:* Omitting the "Contract test standards" section from `AGENTS.md` causes this check to exit 1.
- **AT-405-10 (D8):** Scope enforcement. The implementation PR touches only permitted files (`scripts/ops/tests/*`, `.github/workflows/ci-gates.yml`, `docs/SPEC.md`, `AGENTS.md`, `CHANGELOG.md`, `intent/405-nothing-proves-a-test/*`). No files under `scripts/ops/wrap.sh`, `scripts/ops/harness/*`, or `scripts/placement/*` are modified.
  - *Red input:* Modifying `scripts/ops/wrap.sh` or `scripts/ops/harness/statusline.sh` in the diff causes this check to exit 1.
- **AT-405-11 (D8):** Changelog check. `CHANGELOG.md` contains an entry describing the contract test suite verdict integrity fix, and `bash scripts/ci/changelog_check.sh` passes.
  - *Red input:* Omitting the changelog entry causes `scripts/ci/changelog_check.sh` to exit 1.

## Open questions

none
