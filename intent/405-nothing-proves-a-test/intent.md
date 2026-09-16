# Intent: Test suite verdict integrity against null implementations and ambient environment pollution

**Issue:** #405 · **Stage:** plan · **Author:** athena (`evekhm-athena-app[bot]`) · **Status:** accepted on merge of this PR

## Problem

Under this repository's autonomous software development lifecycle (`AGENTS.md`, `personas/lifecycle.json`, `docs/SPEC.md`), contract test suites are the foundational verification mechanism and trust boundary:
- At the **BUILD** rung, Daedalus commits failing contract assertions (`plan.md`, `AT-*`).
- At the **IMPLEMENT** rung, Odyssey greens those assertions as proof that functionality conforms to specification.
- At the **REVIEW** rung, Argus and Atlas run test suites to produce review verdicts.
- At the **DEPLOY / MERGE GATE** rung, `ci-gates.yml` and `scripts/ci/merge_gate.sh` require zero test failures before autonomous merge.

Nothing in this repository currently proves that a test suite's verdict is a deterministic function of the code under test. Three suites were discovered within 48 hours whose verdicts were dictated by in-process shell isolation or by ambient environment variables, operating in both failure directions:

| Suite | Verdict source | Direction | How it was discovered |
|---|---|---|---|
| `scripts/ops/tests/wrap_test.sh` | Its own `fail()` counter, which cannot see 24 of its 49 `fail` calls inside subshells | False green | Executing it against a stub implementation |
| `scripts/ops/tests/harness_test.sh` | `CLAUDE_SEAT` inherited from operator/verifier shell | False red | Executing it from an interactive seated shell |
| `scripts/ops/tests/placement_test.sh` | `WORK_MAX_USD` inherited from dispatched persona environment (#244) | False red | A dispatched persona failing a suite it did not touch |

### 1. The False-Green Failure Mode (Broken Reporting Channel)

In `scripts/ops/tests/wrap_test.sh` (merged at `e4f2bc1` during #85), the `fail()` function increments an in-process shell variable: `FAILURES=$((FAILURES + 1))`. However, 24 of the suite's 49 `fail` invocations are executed inside `( ... )` subshells (typically used to isolate fixture setup, working directories, or command pipes). Because variable mutations in child subshells do not propagate back to the parent shell process, the parent counter never increments when subshell assertions fail.

This was empirically reproduced across three runs from the merged head:
- **Run A (merged head, unbuilt implementation):** Exits 1 with 23 failures counted, reporting `"EXPECTED RED at build rung"`.
- **Run B (`WRAP_SH` replaced by a stub whose whole body is `exit 0`):** Exits 1 with 6 failures counted.
- **Run C (same `exit 0` stub, plus the 5 static artifacts AT-14 and AT-15 assert):** Exits 0, reporting `"ALL TESTS PASSED"`, with `counter 0` despite printing 21 FAIL lines (17 behavioural test failures).

Because Run C adds the exact static files that #85 D8 and D15 oblige the implement rung to produce, greening the static existence tests simultaneously eliminates the suite's last visible failure counter in the parent shell. In `ci-gates.yml`, only the suite's exit code is evaluated. A completely hollow implementation emitting no output passes CI cleanly, leaving broken behaviour completely undetected.

### 2. The False-Red Failure Mode (Ambient Environment Pollution)

In the false-red failure mode, an implementation under test is completely correct, but the test suite fails because it inherits unpinned or uncleared environment variables from the caller shell:

- **`placement_test.sh` (#244):** PR #232 added budget ceiling enforcement by exporting `WORK_MAX_USD`. When `placement_test.sh` runs inside an unattended persona session (the exact environment where `WORK_MAX_USD` is exported), mutant test cases inherit the caller's ceiling, causing the assertion `"the mutant still carries a ceiling, so the assertion above proves nothing"` to fail. The suite is fail-fast, causing the persona to see a red test suite on clean code.
- **`harness_test.sh` (#330 / PR #403):** `statusline.sh` reads `SEAT="${AGENTIC_SEAT:-${CLAUDE_SEAT:-}}"` and appends ` · $SEAT` when set. When `harness_test.sh` is executed by a human operator or verifier whose shell has `CLAUDE_SEAT=verifier` (or `AGENTIC_SEAT`), tests AT-2, AT-3, AT-20, and AT-21 fail because they expect unseated output and did not pin or clear the seat variable.

In both instances, `ci-gates.yml` runs in a clean GitHub Actions environment where these variables are unset, so CI stays green and hides the defect. Meanwhile, human operators, verifiers, and unattended personas run the suites locally or in-session and hit false red. This creates severe danger: developers or agents assume the red is real and attempt to "repair" the code under test (e.g. by removing the seat segment or crippling budget enforcement), breaking working features.

### 3. The Structural Void

Coverage tracking (#355 and #249) counts which suites are executed by CI. That is an orthogonal question: even when a suite is wired into CI and executed on every commit, neither CI nor the test suites themselves prove that:
1. When the implementation under test is a stub, the suite fails cleanly and reports all failures.
2. When the caller environment is polluted with ambient variables, the suite remains hermetic and green.

## Proposed outcome

1. **Reporting Channel Integrity (Elimination of False Green):**
   - Repair `scripts/ops/tests/wrap_test.sh`: Fix subshell failure recording so all 49 `fail` call sites (including the 24 nested in subshells) reliably increment the suite's failure count and force exit 1 on failure.
   - Standardize failure reporting across all repository shell test suites: test assertions executed in subshells, sub-processes, or traps must propagate failure signals to the primary exit status (e.g., via sandbox-backed failure logs, explicit status aggregation, or eliminating unnecessary subshell forks).

2. **Input Channel Hermeticity (Elimination of False Red):**
   - Repair `scripts/ops/tests/placement_test.sh`: Neutralize `WORK_MAX_USD` and related `WORK_*` variables at entry and ensure mutant runs invoke clean sub-environments.
   - Repair `scripts/ops/tests/harness_test.sh`: Neutralize `CLAUDE_SEAT` and `AGENTIC_SEAT` at entry, pinning seat values explicitly only in tests that assert seated behavior.
   - Establish repository-wide environment hygiene: every test suite asserting on or executing code that reads ambient variables must clear (`env -u`, `unset`) or pin those variables at entry so external session state cannot alter verdicts.

3. **Mechanical Verification Proofs (Automated Test Suite Auditing):**
   - Implement an automated, deterministic verification mechanism (e.g., a test-the-tests tool or CI check) that can audit repository test suites:
     - **Proof 1 (Null-Implementation Proof / Anti-False-Green):** Runs a suite with its script under test replaced by an `exit 0` stub plus required static mocks. The suite must exit nonzero, and the reported failure count must equal the number of `FAIL` lines printed.
     - **Proof 2 (Ambient-Environment Proof / Anti-False-Red):** Runs a suite under dirty ambient environments (e.g., `CLAUDE_SEAT=polluter WORK_MAX_USD=9999 bash <suite>`), asserting that the suite exits 0 on valid code.

4. **CI Enforcement & System Standards:**
   - Wire the suite integrity proofs or hygiene checks into CI (`.github/workflows/ci-gates.yml`) so reporting lapses or unpinned variables cannot be merged.
   - Upsert `docs/SPEC.md` and update `AGENTS.md` with explicit contract test authoring standards: mandatory failure propagation across subshells and mandatory environment clearing at suite entry.

## Affected users and systems

- **Test Suite Authors (`daedalus`, `contract-writer`):** Must author contract suites that propagate failures across subshells and isolate ambient variables.
- **Implementers & Reviewers (`odyssey`, `argus`, `atlas`, interactive operators):** Can run suites in any shell or dispatched session without false red from ambient variables, and can trust that green suites reflect working code.
- **Specific Test Suites:**
  - `scripts/ops/tests/wrap_test.sh` (subshell counter fix).
  - `scripts/ops/tests/placement_test.sh` (`WORK_MAX_USD` clearing).
  - `scripts/ops/tests/harness_test.sh` (`CLAUDE_SEAT` clearing/pinning).
  - All test suites in `scripts/ops/tests/` and `scripts/ci/tests/`.
- **CI Workflows (`.github/workflows/ci-gates.yml`):** Runs suites with verified verdict integrity and enforces anti-drift/anti-pollution gates.
- **Documentation & Standards (`docs/SPEC.md`, `AGENTS.md`):** Documents contract test hermeticity rules.

## Constraints

- **Preserve Production Behavior:** Changes are strictly scoped to test suites, testing harnesses, and CI validation. No modifications to production contracts (`wrap.sh`, `placement/`, `statusline.sh`) are permitted.
- **Hermetic & Offline Execution:** Proofs and suites must execute deterministically without network access, third-party packages, or side effects on the developer checkout.
- **Orthogonal to CI Suite Coverage (#355, #249):** This issue resolves verdict integrity (verdict is a function of code under test); wiring un-run suites into CI remains the domain of #355 and #249.
- **Standard SDLC Lifecycle Discipline:** At the PLAN gate, only `intent/<issue>-<slug>/intent.md` is authored and committed. Design choices (e.g., file-backed counters vs helper library, exact sanitization list, meta-suite location) remain open questions for DESIGN (`spec.md`).

## Relationships

- **Addresses #405:** Core issue.
- **Resolves / Extends #244:** First sighting of Proof 2 failure (`placement_test.sh`).
- **Repairs #85 (`wrap_test.sh`):** Resolves the subshell counter blind spot introduced in PR #85.
- **Repairs #330 / PR #403 (`harness_test.sh`):** Resolves `CLAUDE_SEAT` ambient pollution in statusline tests.
- **Complements #355 & #249:** Orthogonal CI suite scheduling issues.

## Open questions

1. **Subshell Failure Propagation Mechanism (Proof 1 Remediation):**
   How should shell test suites collect failure records across subshells?
   - *Option A (File-backed accumulator):* Write failure events to a sandbox file (e.g. `echo "$msg" >> "$SANDBOX/failures.log"`), reading and counting lines at suite conclusion.
   - *Option B (Subshell exit propagation):* Avoid `( ... )` where feasible, or enforce that subshells return failure exit codes captured by parent error handling (`if ! ( ... ); then fail ...; fi`).
   - *Option C (Common test harness library):* Introduce a lightweight test helper script in `scripts/ops/lib/` or `scripts/ci/` that provides robust `pass`, `fail`, `assert`, and `summary` primitives.
2. **Ambient Variable Sanitization Strategy (Proof 2 Remediation):**
   How should environment isolation be enforced at suite entry?
   - *Option A (Per-suite targeted unset):* Each suite unsets or pins the specific variables it and its target scripts read (e.g. `unset CLAUDE_SEAT AGENTIC_SEAT`).
   - *Option B (Shared environment scrubber):* A standard entry routine unsets all known repo prefixes (`WORK_*`, `CLAIM_*`, `CLAUDE_*`, `AGENTIC_*`, `GH_*`), preserving only essential system variables (`PATH`, `HOME`, `TERM`, `TMPDIR`).
   - *Option C (External hermetic runner):* An invocation wrapper (e.g. `scripts/ops/tests/run_hermetic.sh <suite>`) executes suites in a stripped `env -i` environment.
3. **Architecture and Scope of Automated Integrity Proofs:**
   How should the Null-Implementation and Ambient-Environment proofs be structured and executed?
   - *Option A (Standalone meta-test suite):* A single suite (e.g. `scripts/ci/tests/suite_integrity_test.sh`) iterates over candidate suites, executing stubbed and polluted scenarios.
   - *Option B (Self-auditing suites):* Each test suite supports flags (e.g. `--verify-null`, `--verify-ambient`) allowing self-contained auditing.
   - *Option C (CI lint/audit step):* A CI script that statically and dynamically verifies test suite compliance before running the full test matrix.
4. **Feasibility of Null-Implementation Proof Across Diverse Suite Architectures:**
   Not all repository suites test a single external script path via an environment variable (like `WRAP_SH` or `STATUSLINE_SH`). Some suites test multi-component workflows, Python modules, or shell functions. How should the null-implementation proof define the stubbing interface for diverse suites?
5. **Disposition of Issue #244:**
   Should issue #244 be closed as superseded once #405 implements the general fix, or kept open and closed via a separate verification commit?
