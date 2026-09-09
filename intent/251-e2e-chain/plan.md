# Plan: End-to-End Autonomous Loop Chain

- Work item: Issue #251
- Spec: `intent/251-e2e-chain/spec.md`
- Author: daedalus
- Base commit: `4f862c6b8cac5ea82f0792e908aec72fda85ad91`
- Status: Drafted (Build Rung)

## Summary

This plan specifies the implementation steps to complete the end-to-end
autonomous loop chain defined in `intent/251-e2e-chain/spec.md`. The
changes close the loop between automated ladder advances in GitHub Actions
and unattended execution on the operator VM.

The plan encompasses:
1. Hermetic contract tests in `scripts/ci/tests/e2e_chain_test.sh` asserting
   all decision rows (D1 to D8) and acceptance criteria (AT-1 to AT-20).
2. Bug fixes in `scripts/ci/lifecycle_advance.sh` and
   `scripts/placement/vm-local/run.sh` to ensure placement calls supply
   `--as <persona>` and delegate cleanly under GitHub Actions.
3. Claim release integration in `lifecycle_advance.sh` so ladder advances
   and terminal transitions release the active claim.
4. Fix-round dispatch support in `scripts/ops/work.sh` enabling authoring
   personas to address reviewer findings on pull requests under review.
5. The continuous VM background poller `scripts/placement/vm-local/poll.sh`
   consuming loop ledger dispatch rows without model calls.
6. Supervisor configurations for Antigravity sidecar and systemd user services.
7. Documentation updates in `docs/SPEC.md`.

## Corrections to Spec Citations

The spec references line numbers from earlier commits. At base commit
`4f862c6b8cac5ea82f0792e908aec72fda85ad91`, the following line shifts exist:
1. `scripts/ci/lifecycle_advance.sh`:
   The placement adapter calls sit at lines 1073 and 1076 (cited as ~1065
   in early notes). Both omit `--as "$persona"`.
2. `scripts/placement/vm-local/run.sh`:
   Flag validation sits at lines 40-56; execution delegation sits at line 98.
3. `scripts/ops/work.sh`:
   Review stage derivation sits at lines 340-395; stage ownership refusal (h)
   sits at line 488.
4. `scripts/ops/tests/work_test.sh`:
   Line 486 expects `claude-code` for odyssey. Commit `60fa3cb` (PR #287)
   re-pinned odyssey to `antigravity` in `config/deployments.yaml`. Because
   `work_test.sh` does not run in CI (tracked under #246), this test failure
   pre-dates this change. Task T5 updates the assertion to reflect the
   antigravity pin.

## Design Decisions and Architectural Calls

### P1: Ledger Consumption and Claim Audit
The poller in `scripts/placement/vm-local/poll.sh` detects pending work by
reading issue comments for ledger rows matching the specification in
`lifecycle_advance.sh:566`:
`^<!-- loop-ledger-row: (dispatch|terminal|refusal:[a-z-]+) rung:[0-9]+ head-oid:[0-9a-f]{40}( [a-z-]+:[^ ]+)* -->$`
A dispatch row is unconsumed when no subsequent `Claim:` comment exists from
the dispatched persona App identity. Once a matching claim comment appears,
the poller marks the row consumed and skips it.

### P2: Process Mutex and Restart Idempotence
The poller checks whether an issue carries `hold`, `blocked`, or an active
`in-progress` label before taking action. For existing claims, the poller
inspects the session identifier. When a local process identifier `<pid>` is
recorded, `kill -0 <pid>` determines if the process is alive. If alive, the
poller leaves the issue untouched. If dead, the poller unlocks the worktree
and resumes execution.

### P3: Adapter Invocation Contract
`scripts/placement/README.md` defines the adapter contract as
`run.sh <number> --as <persona>`. `lifecycle_advance.sh` is updated to pass
`--as "$persona"` in both dry-run logging and execution paths.

### P4: Fix-Round Stage Retention
In `scripts/ops/work.sh`, when an open pull request sits at `status:in-review`
and `--as <persona>` matches the pull request head branch prefix, the script
preserves the authoring stage instead of switching to `review`. This bypasses
refusal (h) and allows the authoring persona to push fix commits.

## Traceability Matrix

### Decision Rows
- D1 (Continuous VM poller loop): T1, T6
- D2 (Fix-round dispatch on review-blocked PRs): T1, T5, T6
- D3 (Claim before launch): T1, T6
- D4 (Supervised execution): T1, T7
- D5 (Harness-agnostic launcher): T1, T6
- D6 (Failure containment and backoff): T1, T6
- D7 (Single-session execution and worktree cleanup): T1, T3, T6
- D8 (Scope boundary and bug fixes): T1, T2, T3, T4, T5, T8, T9

### Acceptance Criteria
- AT-1 (`poll.sh` executable, dry run): T1, T6; verified by `e2e_chain_test.sh`
- AT-2 (Unconsumed dispatch row detection): T1, T6; verified by `e2e_chain_test.sh`
- AT-3 (Consumed dispatch row skipped): T1, T6; verified by `e2e_chain_test.sh`
- AT-4 (Mutex and hold safety): T1, T6; verified by `e2e_chain_test.sh`
- AT-5 (Claim before launch): T1, T6; verified by `e2e_chain_test.sh`
- AT-6 (Review round detection): T1, T6; verified by `e2e_chain_test.sh`
- AT-7 (vm-local delegation under GITHUB_ACTIONS): T1, T4; verified by `e2e_chain_test.sh`
- AT-8 (Harness pin compliance): T1, T6; verified by `e2e_chain_test.sh`
- AT-9 (Sidecar config validation): T1, T7; verified by `e2e_chain_test.sh`
- AT-10 (Systemd service unit validation): T1, T7; verified by `e2e_chain_test.sh`
- AT-11 (Supervised execution): Operator precondition; verified by systemctl/sidecar status
- AT-12 (Error containment): T1, T6; verified by `e2e_chain_test.sh`
- AT-13 (work.sh fix-round acceptance): T1, T5; verified by `e2e_chain_test.sh`
- AT-14 (Worktree branch format): T1, T6; verified by `e2e_chain_test.sh`
- AT-15 (Primary checkout immutability): T1, T6; verified by `e2e_chain_test.sh`
- AT-16 (Step 1 intent to spec via Athena): Operator precondition; verified by live issue transition
- AT-17 (Claim release on session exit): T1, T3, T6; verified by `e2e_chain_test.sh`
- AT-18 (Full ladder execution): Operator precondition; verified by live issue progression
- AT-19 (`lifecycle_advance.sh` adapter invocation with `--as`): T1, T2; verified by `e2e_chain_test.sh`
- AT-20 (`docs/SPEC.md:841` carries `ladder at vm-local`): T1, T8; verified by `e2e_chain_test.sh`

## Detailed Implementation Tasks

### T1: Hermetic Contract Tests (Build Rung Deliverable)
- File: `scripts/ci/tests/e2e_chain_test.sh`
- Description: Implement hermetic test suite covering AT-1 through AT-20.
  Stubs `gh` and `git` in a temporary workspace. Asserts poller behavior,
  delegation flags, adapter invocation, fix-round handling, configuration
  validity, and documentation state.
- Status at Build Rung: Written and failing (RED).

### T2: Adapter Invocation Fix in Lifecycle Advancer (D8, AT-19)
- File: `scripts/ci/lifecycle_advance.sh`
- Description: In `scripts/ci/lifecycle_advance.sh` lines 1073 and 1076, add
  `--as "$persona"` to the invocation of `scripts/placement/$placement/run.sh`.
- Test: `bash scripts/ci/tests/e2e_chain_test.sh` (AT-19 turns green).

### T3: Lifecycle Claim Release (D1, D7, AT-17)
- File: `scripts/ci/lifecycle_advance.sh`
- Description: In `lifecycle_advance.sh`, implement claim release before
  transitioning labels or when reaching terminal states (`advances_to` empty).
  Verify the current claim holder matches the stage completing its run.
  Remove `in-progress` label using GitHub API under ambient credentials.
- Test: `bash scripts/ci/tests/lifecycle_advance_test.sh`.

### T4: VM-Local Adapter GitHub Actions Delegation (D8, AT-7)
- File: `scripts/placement/vm-local/run.sh`
- Description: In `scripts/placement/vm-local/run.sh`, inspect the
  `GITHUB_ACTIONS` environment variable. When set to `true`, emit:
  `vm-local: delegating #$NUMBER execution to operator VM poller`
  and exit 0 immediately before executing preflight checks or `work.sh`.
- Test: `bash scripts/ci/tests/e2e_chain_test.sh` (AT-7 turns green).

### T5: Work Dispatch Fix-Round Support (D2, D8, AT-13)
- Files: `scripts/ops/work.sh`, `scripts/ops/tests/work_test.sh`
- Description: In `scripts/ops/work.sh`, when an issue is an open pull request
  at `status:in-review` and `--as <persona>` matches the pull request head
  branch author, retain the author's stage. Bypass the review stage switch and
  refusal (h). In `scripts/ops/tests/work_test.sh:486`, update the expected
  harness string for odyssey from `claude-code` to `antigravity`.
- Test: `bash scripts/ops/tests/work_test.sh` and `e2e_chain_test.sh` (AT-13 turns green).

### T6: Continuous Background Poller (D1, D2, D3, D5, D6, D7, AT-1 to AT-6, AT-12)
- File: `scripts/placement/vm-local/poll.sh`
- Description: Create executable bash script implementing the continuous
  poller loop on a 30-second interval. The script uses `gh` and `jq` without
  model calls. Reads open issues and pull requests, evaluates unconsumed
  dispatch rows, checks mutex and hold conditions, claims via `claim.sh`
  under minted persona tokens, dispatches via `run.sh`, logs execution
  summaries, and implements error backoff.
- Test: `bash scripts/ci/tests/e2e_chain_test.sh` (AT-1 to AT-6, AT-12 turn green).

### T7: Supervisor Unit Configurations (D4, AT-9, AT-10)
- Files: `scripts/placement/vm-local/poll.sidecar.json`,
  `scripts/placement/vm-local/agentic-sdlc-poll.service`
- Description: Create Antigravity sidecar configuration with `command: "bash"`,
  `args: ["-c", "exec scripts/placement/vm-local/poll.sh"]`,
  `restart_policy: "always"`, and required environment variables.
  Create systemd user service unit with `Restart=always` and `ExecStart`.
- Test: `bash scripts/ci/tests/e2e_chain_test.sh` (AT-9, AT-10 turn green).

### T8: Living Spec and Documentation (D8, AT-20)
- File: `docs/SPEC.md`
- Description: Update line 841 in `docs/SPEC.md` to state that athena,
  daedalus, and odyssey carry bindings for `ladder at vm-local`.
  Document the VM poller architecture and sidecar supervisor configuration.
- Test: `bash scripts/ci/tests/e2e_chain_test.sh` (AT-20 turns green).

### T9: Test Suite Integration (D8)
- Files: `.github/workflows/ci-gates.yml`, `scripts/ci/tests/lifecycle_advance_test.sh`
- Description: Wire `scripts/ci/tests/e2e_chain_test.sh` into the `execution`
  gate job in `.github/workflows/ci-gates.yml`.
- Test: `python3 scripts/ops/execution.py --check` and full CI suite.

## Risk Classifications and Mitigations

### DEEP-3: Credentials and Token Safety
Persona tokens are minted at execution time by `mint_app_token.py` using
App private keys resolved from environment variables or secure key paths.
Tokens are never committed, logged, or exported into unattended environments.
The preflight in `run.sh` asserts repository coverage using `--quiet` to
prevent token exposure in shell output.

### DEEP-5: State Machine, Mutex, and Ledger Integrity
The loop ledger in issue comments is append-only and keyed by `(rung, head-oid)`.
The poller inspects existing claims and process liveness before claiming.
Claim creation via `claim.sh` acts as an atomic mutex on the issue.
Claim release in `lifecycle_advance.sh` ensures that only the holding persona
can release `in-progress` upon transition.

### DEEP-6: Supervisor and Process Management
The poller runs under a supervisor (Antigravity sidecar or systemd user unit)
with `restart_policy: always`. The poller traps signals, records child process
identifiers, handles child exits cleanly, and avoids orphaned subshells.
File-based lock records track running worker sessions.

## Gates Table

| Gate / Test Suite | Command | Scope | Rung Status |
|---|---|---|---|
| Contract Suite | `bash scripts/ci/tests/e2e_chain_test.sh` | Decisions D1-D8, AT-1 to AT-20 | FAIL (RED at base) |
| Sanitize Gate | `bash scripts/ci/sanitize_check.sh` | Tracked files security and credentials | PASS |
| Spec Gate | `bash scripts/ci/spec_check.sh` | Living spec obligations | PASS |
| Execution Gate | `python3 scripts/ops/execution.py --check` | Execution bindings and config schema | PASS |
| Execution Tests | `bash scripts/ops/tests/execution_test.sh` | Execution model tests | PASS |
| Placement Tests | `bash scripts/ops/tests/placement_test.sh` | Placement adapter contract tests | PASS |
| Post Tests | `bash scripts/ops/tests/post_test.sh` | Posting path contract tests | PASS |
| Advancer Suite | `bash scripts/ci/tests/lifecycle_advance_test.sh` | Lifecycle state transitions | PASS |
| Work Suite | `bash scripts/ops/tests/work_test.sh` | Dispatch and stage resolution | FAIL (pre-existing odyssey pin mismatch #246) |
| Supervised Run | System service check | AT-11 operator precondition | NOT RUN (Operator Precondition) |
| Live Step 1 | Manual issue run | AT-16 operator precondition | NOT RUN (Operator Precondition) |
| Live End-to-End | Full ladder loop | AT-18 operator precondition | NOT RUN (Operator Precondition) |
