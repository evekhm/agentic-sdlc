# Plan: End-to-End Autonomous Loop Chain

- Work item: Issue #251
- Spec: `intent/251-e2e-chain/spec.md`
- Author: daedalus
- Base commit: `4f862c6b8cac5ea82f0792e908aec72fda85ad91`
- Status: Drafted (Build Rung, Round 3)

## Summary

This plan specifies the implementation steps to complete the end-to-end
autonomous loop chain defined in `intent/251-e2e-chain/spec.md`. The
changes close the loop between automated ladder advances in GitHub Actions
and unattended execution on the operator VM.

The implement rung branch MUST be named `odyssey/251-e2e-chain` because
`lifecycle_advance.sh:27-34` matches candidate pull requests by verifying
that the head-branch slug equals the intent folder slug (`251-e2e-chain`).

The plan encompasses:
1. Hermetic contract tests in `scripts/ci/tests/e2e_chain_test.sh` asserting
   all decision rows (D1 to D8) and acceptance criteria (AT-1 to AT-20).
2. Bug fixes in `scripts/ci/lifecycle_advance.sh` and
   `scripts/placement/vm-local/run.sh` to ensure placement calls supply
   `--as <persona>` and delegate cleanly under GitHub Actions.
3. Claim release integration in `lifecycle_advance.sh` so ladder advances
   and terminal transitions release the active claim under `GITHUB_TOKEN`.
4. Fix-round dispatch support in `scripts/ops/work.sh` enabling authoring
   personas to address reviewer findings on pull requests under review.
5. The continuous VM background poller `scripts/placement/vm-local/poll.sh`
   consuming loop ledger dispatch rows without model calls.
6. Supervisor configurations for Antigravity sidecar and systemd user services.
7. Documentation updates and the seven-step enablement checklist in `docs/SPEC.md`.

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

The Decision definitions below are taken verbatim from `intent/251-e2e-chain/spec.md`:

- **D1**: **Claim release on ladder advance.** Upon a ladder rung advance, `lifecycle_advance.sh` reads the latest `Claim:` comment on the issue thread.
  - Tasks: T1, T3
- **D2**: **Dispatch path, supervisor process tree, and placement target.** The three ladder personas (`athena`, `daedalus`, `odyssey`) target `vm-local` placement in `config/execution.yaml`.
  - Tasks: T1, T2, T4, T5, T6, T7
- **D3**: **Persona credential storage and security boundary.** On the operator VM, persona private keys reside in local key files under `~/.keys/` (binding point 1).
  - Tasks: T1, T6
- **D4**: **Missing credential handling at installation time.** No new reason code (such as `missing-key`) is added to escalation schemas.
  - Tasks: T1, T6
- **D5**: **First hop dispatch and queue accounting.** `scripts/placement/vm-local/poll.sh` is the single actor for dispatch execution.
  - Tasks: T1, T6
- **D6**: **Operator enablement checklist.** The enablement checklist lives in `docs/SPEC.md ## Deployment status`.
  - Tasks: T1, T8
- **D7**: **End-to-end validation.** Validation of the autonomous chain is conducted on a dedicated synthetic throwaway issue per #64 acceptance 20.
  - Tasks: T1, T9
- **D8**: **Scope boundary and Amendment r5 to #64 D16.** The implementation pull request may modify `scripts/ops/work.sh` (narrow interface change for PR author fix rounds under `status:in-review`), `scripts/ops/tests/work_test.sh`, `scripts/ci/lifecycle_advance.sh`, `scripts/ci/tests/lifecycle_advance_test.sh`, `scripts/placement/vm-local/poll.sh`, `scripts/placement/vm-local/poll.sidecar.json`, `scripts/placement/vm-local/poll.service`, `scripts/placement/vm-local/run.sh`, and `docs/SPEC.md` (deployment status checklist and the deployment table row that reads odyssey `manual` (line 841 at 60fa3cb)).
  - Tasks: T1, T2, T3, T4, T5, T6, T7, T8, T9

### Acceptance Criteria

The Acceptance Criteria below are taken verbatim from `intent/251-e2e-chain/spec.md`:

- **AT-1 (D1)**: In `bash scripts/ci/tests/lifecycle_advance_test.sh`, a ladder rung transition on an issue whose latest claim comment author login maps to the completing stage persona prints `released claim of <actor> on #<n> (rung <stage> merged)`, deletes `in-progress` under `GITHUB_TOKEN`, and invokes the placement adapter.
  - Mapped to: T1, T3; verified by `scripts/ci/tests/e2e_chain_test.sh`
- **AT-2 (D1)**: In `bash scripts/ci/tests/lifecycle_advance_test.sh`, an issue carrying `in-progress` where the latest claim comment author login maps to a different persona prints `withholding dispatch: in-progress held by <holder>`, preserves `in-progress`, and withholds adapter dispatch.
  - Mapped to: T1, T3; verified by `scripts/ci/tests/e2e_chain_test.sh`
- **AT-3 (D1)**: In `bash scripts/ci/tests/lifecycle_advance_test.sh`, an issue carrying `in-progress` where the latest claim comment author is foreign (outside persona mapping) or missing prints `withholding dispatch: in-progress held by foreign login` (or unparseable claim), preserves `in-progress`, and withholds adapter dispatch.
  - Mapped to: T1, T3; verified by `scripts/ci/tests/e2e_chain_test.sh`
- **AT-4 (D1)**: In `bash scripts/ci/tests/lifecycle_advance_test.sh`, when `loop.autonomous_merge: false` (or key absent), ladder advance prints the substrings `autonomous_merge is false` and `no dispatch for #<n> (D18)` (joined at scripts/ci/lifecycle_advance.sh:1032 by a character this spec's prose rule does not reproduce), leaves `in-progress` intact, and skips claim release.
  - Mapped to: T1, T3; verified by `scripts/ci/tests/e2e_chain_test.sh`
- **AT-5 (D1)**: In `bash scripts/ci/tests/lifecycle_advance_test.sh`, advancing to the terminal review rung (`advances_to: null`, `status:in-review`) prints `released claim of odyssey on #<n> (rung implement merged)` and removes `in-progress`.
  - Mapped to: T1, T3; verified by `scripts/ci/tests/e2e_chain_test.sh`
- **AT-6 (D2, #284)**: In `bash scripts/ci/tests/lifecycle_advance_test.sh`, every placement adapter dispatch invocation passes `<issue> --as <persona>` in its argv string.
  - Mapped to: T1, T2; verified by `scripts/ci/tests/e2e_chain_test.sh`
- **AT-7 (D2)**: Executing `GITHUB_ACTIONS=true scripts/placement/vm-local/run.sh 251 --as athena` prints `delegating #251 execution to operator VM poller` and exits 0.
  - Mapped to: T1, T4; verified by `scripts/ci/tests/e2e_chain_test.sh`
- **AT-8 (D2)**: Executing `bash -n scripts/placement/vm-local/poll.sh` exits 0. In a mock ledger test, executing `scripts/placement/vm-local/poll.sh --once` finds unconsumed rows, invokes `CLAIM_ACTOR=<persona> CLAIM_SESSION=poll-<pid> scripts/ops/claim.sh <n>` under minted token, verifies the posted claim comment carries `.user.login` matching the persona App identity, and skips already-claimed rows.
  - Mapped to: T1, T6; verified by `scripts/ci/tests/e2e_chain_test.sh`
- **AT-9 (D2)**: Running `python3 -m json.tool scripts/placement/vm-local/poll.sidecar.json >/dev/null` exits 0, and `jq -e '.command and .args and .env and (.restart_policy == "always")' scripts/placement/vm-local/poll.sidecar.json` prints `true`.
  - Mapped to: T1, T7; verified by `scripts/ci/tests/e2e_chain_test.sh`
- **AT-10 (D2)**: Running `grep -E '^(Type=simple|Restart=always|ExecStart=)' scripts/placement/vm-local/poll.service` outputs matching unit configuration lines and exits 0.
  - Mapped to: T1, T7; verified by `scripts/ci/tests/e2e_chain_test.sh`
- **AT-11 (D2, Live supervisor check - NOT RUN, operator precondition)**: Live verification with UI closed: supervisor process is active and running `poll.sh`. Verification command: `pgrep -fa 'bash.*poll.sh'` prints running PID, and log at `~/.gemini/antigravity/sidecar_data/sdlc-poller/logs/sidecar.log` (or `journalctl --user -u poll.service -n 20`) contains `poller active, interval: 30s` (Constraint 5, binding point 5; reported by the operator on #251, comment 5597497232).
  - Mapped to: NOT RUN (operator precondition)
- **AT-12 (D2)**: Re-pin property: In a hermetic test in `scripts/ops/tests/work_test.sh`, using a fixture `deployments.yaml`, updating a persona pin from `antigravity` to `claude-code`, running stub `work.sh <issue> --as <persona>`, asserts `claude -p "$PROMPT" --agent "$persona" --output-format json` is invoked, and restoring the fixture returns to `antigravity`.
  - Mapped to: T1, T5; verified by `scripts/ci/tests/e2e_chain_test.sh`
- **AT-13 (D2, D8)**: Hermetic fix-round dispatch: In `scripts/ops/tests/work_test.sh`, a stub PR authored by odyssey at `status:in-review` dispatched with `scripts/ops/work.sh <pr> --as odyssey` does not refuse (h), does not print `odyssey does not own stage review (owners: argus atlas )`, and proceeds under the resume protocol.
  - Mapped to: T1, T5; verified by `scripts/ci/tests/e2e_chain_test.sh`
- **AT-14 (D4)**: Missing credential handling: Running `python3 scripts/auth/mint_app_token.py <persona> --require-repo --quiet` preflights keys on VM; when a key is absent, `poll.sh` logs `missing key for <persona>, skipping its rows` and continues without exiting.
  - Mapped to: T1, T6 (mock half in `scripts/ci/tests/e2e_chain_test.sh`; live half in NOT RUN operator precondition)
- **AT-15 (D5)**: First hop ledger check: Running `scripts/placement/vm-local/poll.sh --once` on an open `intent:new` issue runs claim and dispatch, and `gh api repos/evekhm/agentic-sdlc/issues/<n>/comments --jq '.[].body | select(test("<!-- loop-ledger"))'` outputs empty string (zero loop-ledger rows prior to merge of `intent.md`).
  - Mapped to: T1, T6; verified by `scripts/ci/tests/e2e_chain_test.sh`
- **AT-16 (D6, Step 1 check - operator precondition)**: Running `python3 scripts/auth/create_all_apps.py --only themis --check` exits 0, printing the themis row in the table and the closing line `every entry is complete` (scripts/auth/create_all_apps.py:446).
  - Mapped to: NOT RUN (operator precondition)
- **AT-17 (D6, D8)**: Running `grep -F "## Deployment status" docs/SPEC.md` finds the section, `sed -n '/## Deployment status/,/##/p' docs/SPEC.md | grep -c '^[0-9]\. '` outputs `7`, `grep -c 'odyssey \`manual\`' docs/SPEC.md` outputs `0`, and `grep -c 'odyssey \`ladder\`' docs/SPEC.md` outputs `1` for the deployment table row that reads odyssey `manual` (line 841 at 60fa3cb).
  - Mapped to: T1, T8; verified by `scripts/ci/tests/e2e_chain_test.sh`
- **AT-18 (D7, Synthetic validation - operator precondition)**: Dedicated synthetic issue run verification: running `gh api repos/evekhm/agentic-sdlc/issues/<n>/comments --jq '.[].body | select(test("<!-- loop-ledger"))'` shows four `dispatch` rows and one `terminal` row; running `gh run list --workflow lifecycle.yml --branch main --limit 5 --json databaseId,conclusion` and `gh run list --workflow merge-gate.yml --branch main --limit 5 --json databaseId,conclusion` show all conclusions as `success`; and `gh issue view <n> --json labels --jq '.labels[].name'` outputs `status:in-review` with `in-progress` absent.
  - Mapped to: NOT RUN (operator precondition)
- **AT-19 (D8)**: Pre-merge validation checks exit 0:
  `BODY_FILE="$(mktemp)"; echo "Spec-impact: none - intent/** only, not a behavior-bearing path" > "$BODY_FILE"; bash scripts/ci/spec_check.sh origin/main "$BODY_FILE"; rm -f "$BODY_FILE"`
  and `bash scripts/ci/sanitize_check.sh`.
  - Mapped to: T9 (gates table pre-merge validation checks in Rule 9)
- **AT-20 (D2)**: Hermetic fix-round claim bypass and locking: Under the stub, executing `scripts/placement/vm-local/poll.sh --once` on a fixture PR authored by odyssey at `status:in-review` with an unconsumed blocking review row launches `scripts/placement/vm-local/run.sh <pr> --as odyssey` and records zero calls to `scripts/ops/claim.sh`; a second `--once` execution while the lock exists launches nothing.
  - Mapped to: T1, T6; verified by `scripts/ci/tests/e2e_chain_test.sh`

## Detailed Implementation Tasks

### T1: Hermetic Contract Tests (Build Rung Deliverable)
- Files: `scripts/ci/tests/e2e_chain_test.sh`
- Decisions: D1, D2, D4, D5, D6, D8
- Acceptance: AT-1, AT-2, AT-3, AT-4, AT-5, AT-6, AT-7, AT-8, AT-9, AT-10, AT-12, AT-13, AT-14, AT-15, AT-17, AT-20
- Description: Implement hermetic test suite covering the sixteen executable acceptance rows.
  Stubs `gh`, `git`, `python3`, `claude`, and `agy` in a temporary workspace.
  Copies minimal stub helpers from `scripts/ci/tests/lifecycle_advance_test.sh:57-63, 73-178, 187-195`
  and `scripts/ops/tests/work_test.sh:72-84, 86-131, 138-160`.
  Supports `-k <pattern>` filter flag.
  Output ends with `e2e_chain_test.sh results: 0 passed, N failed out of N run`.
- Status at Build Rung: Written and failing (RED) due to absence of implementation.

### T2: Adapter Invocation Fix in Lifecycle Advancer (D2, D8, AT-6)
- Files: `scripts/ci/lifecycle_advance.sh`, `scripts/ci/tests/lifecycle_advance_test.sh`
- Decisions: D2, D8
- Acceptance: AT-6
- Description: In `scripts/ci/lifecycle_advance.sh`, update the placement adapter dispatch
  invocation at line 1073 (dry-run branch) and line 1076 (live execution branch) to append
  `"$issue" --as "$persona"`. In testing, sandbox scenarios use helper `get_range <kind>`
  providing three git revision ranges (`intent`, `spec`, `implement-pr`).
- Test: `bash scripts/ci/tests/e2e_chain_test.sh` (AT-6 turns green).

### T3: Lifecycle Claim Release (D1, D8, AT-1 to AT-5)
- Files: `scripts/ci/lifecycle_advance.sh`, `scripts/ci/tests/lifecycle_advance_test.sh`
- Decisions: D1, D8
- Acceptance: AT-1, AT-2, AT-3, AT-4, AT-5
- Description: In `scripts/ci/lifecycle_advance.sh`, upon ladder rung advance, read the latest
  claim comment on the issue thread. Derive the claim holder by mapping comment author
  login (`.user.login`) through the persona identity table without parsing unauthenticated comment
  body text. If the mapped claim persona matches the persona owning the completed stage,
  delete `in-progress` via `gh api -X DELETE repos/<repo>/issues/<issue>/labels/in-progress` under `GITHUB_TOKEN` before dispatching the successor
  persona, logging `released claim of <actor> on #<n> (rung <stage> merged)`. The test fixture stub
  logs this as `DELETE labels <n> in-progress`.
  Upon advancing to the terminal review rung (`status:in-review`), release the claim held by `odyssey`.
  If held by another persona, foreign login, or if unparseable, preserve `in-progress` and withhold
  dispatch. If `loop.autonomous_merge: false` (or key absent), leave `in-progress` intact and skip release.
  Advancer scenarios in the contract test suite run live without `DRY_RUN=1`.
- Test: `bash scripts/ci/tests/lifecycle_advance_test.sh` and `e2e_chain_test.sh` (AT-1 to AT-5 turn green).

### T4: VM-Local Adapter GitHub Actions Delegation (D2, D8, AT-7)
- Files: `scripts/placement/vm-local/run.sh`
- Decisions: D2, D8
- Acceptance: AT-7
- Description: In `scripts/placement/vm-local/run.sh`, inspect the `GITHUB_ACTIONS` environment variable.
  When set to `true`, log:
  `vm-local: delegating #$NUMBER execution to operator VM poller`
  and exit 0 immediately before executing token mint preflights or `work.sh`.
- Test: `bash scripts/ci/tests/e2e_chain_test.sh` (AT-7 turns green).

### T5: Work Dispatch Fix-Round Support & Re-Pin Property (D2, D8, AT-12, AT-13)
- Files: `scripts/ops/work.sh`, `scripts/ops/tests/work_test.sh`
- Decisions: D2, D8
- Acceptance: AT-12, AT-13
- Description: In `scripts/ops/work.sh`, when an issue is an open pull request at `status:in-review`
  and `--as <persona>` matches the pull request head branch author (`<persona>/<n>-*`), retain the
  authoring stage and skip refusal (h). Support overridable deployment configuration via
  `DEPLOYMENTS="${DEPLOYMENTS:-$REPO_ROOT/config/deployments.yaml}"` to support hermetic tests.
  In `scripts/ops/tests/work_test.sh:486`, update the expected harness string for odyssey from
  `claude-code` to `antigravity`.
  Add hermetic test in `scripts/ops/tests/work_test.sh` for the re-pin property (AT-12) and fix-round
  dispatch (AT-13).
- Test: `bash scripts/ops/tests/work_test.sh` and `e2e_chain_test.sh` (AT-12, AT-13 turn green).

### T6: Continuous Poller Implementation (D2, D4, D5, AT-8, AT-14, AT-15, AT-20)
- Files: `scripts/placement/vm-local/poll.sh`
- Decisions: D2, D4, D5
- Acceptance: AT-8, AT-14, AT-15, AT-20
- Description: Implement continuous VM poller in `scripts/placement/vm-local/poll.sh`:
  1. Flag handling: `--once` executes a single pass and exits 0; default loop sleeps for polling interval.
  2. Work discovery: discovers candidate work through label queries via GitHub API or CLI (`gh issue list --label <l> --state open` and `gh pr list --state open`); never hardcodes issue numbers.
  3. Ledger consumption: Scans open issues for unconsumed `dispatch` rows in loop ledger comments. Verifies rung owner persona,
     mints token, claims issue via `scripts/ops/claim.sh`, launches `run.sh <issue> --as <persona>`, and skips rows already claimed.
  4. First hop intake: Scans open, unclaimed `intent:new` issues via label queries. Claims via `claim.sh` under minted persona
     token for `athena`, launches `run.sh <issue> --as athena`, and writes zero loop ledger rows (D5).
  5. Mutex and claim handling: Claims an issue before launch via
     `CLAIM_ACTOR=<persona> CLAIM_SESSION=poll-<pid> scripts/ops/claim.sh <n>` under
     `GH_TOKEN="$(python3 scripts/auth/mint_app_token.py <persona>)"` minted per claim.
     Skips already-claimed issues. `poll.sh` never releases a claim; claim release belongs to ladder advance
     in `lifecycle_advance.sh`. Restart idempotence follows design note P2 (lines 61-67): dead pids allow
     lock recovery and live pids preserve the active process.
  6. Fix rounds: Consumes blocking review rows on pull requests authored by vm-local personas.
     Discovers candidate PRs via open PR list queries. Launches `run.sh <pr> --as <author persona>`, bypassing `claim.sh`.
     Guards duplicates via a per-PR lock file at `${TMPDIR:-/tmp}/poll-pr-<number>.lock` released when `run.sh` exits.
     A second `--once` tick while the lock exists launches nothing.
  7. Missing credential handling: Runs preflight `python3 scripts/auth/mint_app_token.py <persona> --require-repo --quiet`.
     If missing or unreadable, logs `missing key for <persona>, skipping its rows` and continues polling remaining personas.
  8. Robustness: Empty or unparseable ledger comments log a diagnostic notice and exit 0.
     Passes `--as "$persona"` to all adapter invocations.
  9. Test harness interception: In test suites, `scripts/ops` and `scripts/placement` are copied into the sandbox environment,
     with `claim.sh` intercepted by a test stub recording `claim.sh CLAIM_ACTOR=... CLAIM_SESSION=... <n>` to `$CLAIMS`,
     preserving worktree cleanliness.
- Test: `bash scripts/ci/tests/e2e_chain_test.sh` (AT-8, AT-14, AT-15, AT-20 turn green).

### T7: Supervisor Unit Configurations (D2, D8, AT-9, AT-10)
- Files: `scripts/placement/vm-local/poll.sidecar.json`, `scripts/placement/vm-local/poll.service`
- Decisions: D2, D8
- Acceptance: AT-9, AT-10
- Description: Create Antigravity sidecar configuration in `scripts/placement/vm-local/poll.sidecar.json`
  with `command: "bash"`, `args: ["-c", "exec scripts/placement/vm-local/poll.sh"]`,
  `restart_policy: "always"`, and required environment variables.
  Create systemd user service unit in `scripts/placement/vm-local/poll.service`
  with `Type=simple`, `Restart=always`, and `ExecStart=...`.
  No files are placed at `scripts/ops/poll.sh` or named `agentic-sdlc-poll.service`.
- Test: `bash scripts/ci/tests/e2e_chain_test.sh` (AT-9, AT-10 turn green).

### T8: Living Spec Documentation & 7-Step Deployment Checklist (D6, D8, AT-17)
- Files: `docs/SPEC.md`
- Decisions: D6, D8
- Acceptance: AT-17
- Description: In `docs/SPEC.md`:
  1. Under `## Deployment status`, document the seven ordered deployment checklist steps with exact commands:
     - Step 1: verify Themis provisioning via `python3 scripts/auth/create_all_apps.py --only themis --check` (exit 0).
     - Step 2: configure VM supervisor via `scripts/placement/vm-local/poll.sidecar.json` into
       `~/.gemini/config/sidecars/sdlc-poller/sidecar.json` (or install `poll.service` into `~/.config/systemd/user/`).
     - Step 3: verify branch protection on `main` via `gh api repos/evekhm/agentic-sdlc/branches/main/protection`
       (confirming four required checks, strict false, enforce_admins false).
     - Step 4: verify placement bindings via `python3 scripts/ops/execution.py --check` (exit 0).
     - Step 5: preflight vm-local persona credentials via `python3 scripts/auth/mint_app_token.py <persona> --require-repo --quiet`
       for athena, daedalus, and odyssey.
     - Step 6: submit and merge the autonomy flip pull request setting `loop.autonomous_merge: true` in `config/execution.yaml`
       and documenting P1 and P2 evidence (#64 acceptance 28).
     - Step 7: launch first hop or verify poller intake on target issue.
  2. Update the deployment table row for odyssey at line 841 from `manual` to `ladder`.
  3. Update `### lifecycle.labels` (:290) to document lifecycle advancer claim release on ladder transition under `GITHUB_TOKEN`.
  4. Update `### loop.autonomous` (:953) to document VM poller architecture, consumption of dispatch rows, first-hop intake,
     and fix-round claim bypass.
- Test: `bash scripts/ci/tests/e2e_chain_test.sh` (AT-17 turns green).

### T9: Test Suite Folding & Acceptance Validation (D7, D8, AT-19)
- Files: `scripts/ci/tests/lifecycle_advance_test.sh`, `scripts/ops/tests/work_test.sh`
- Decisions: D7, D8
- Acceptance: AT-19
- Description: At the implement rung, the branch MUST be `odyssey/251-e2e-chain` to ensure
  `lifecycle_advance.sh:27-34` matches candidate pull requests against `intent/251-e2e-chain`.
  Fold acceptance tests into existing test suites:
  - Fold AT-1 through AT-6 into `scripts/ci/tests/lifecycle_advance_test.sh`.
  - Fold AT-12 and AT-13 into `scripts/ops/tests/work_test.sh`.
  - Maintain remaining integration scenarios in `scripts/ci/tests/e2e_chain_test.sh`.
  `.github/workflows/ci-gates.yml` is untouched at this rung; folded suites run in no workflow at this rung,
  issue #246 tracks CI wiring, and the gates table local runs serve as the implement PR pass condition.
- Test: Gates table local suite runs and pre-merge validation checks exit 0.

## Corrections

### Round 2 Review Findings
1. Verbatim alignment: Decision rows D1 through D8 and Acceptance criteria AT-1 through AT-20 are restored verbatim
   from `intent/251-e2e-chain/spec.md`.
2. Path standardization: Standardized on canonical paths from the spec Manifest and D8:
   `scripts/placement/vm-local/poll.sh`, `scripts/placement/vm-local/poll.sidecar.json`,
   and `scripts/placement/vm-local/poll.service`. Erroneous references to `scripts/ops/poll.sh` and
   `agentic-sdlc-poll.service` are eliminated.
3. CI workflow boundary: Clarified that `.github/workflows/ci-gates.yml` is untouched at this rung.
   Issue #246 tracks CI wiring. The implement PR pass condition is local gate execution.
4. Deployment status checklist: Added the explicit seven-step deployment checklist with exact commands to T8.
5. Supervisor documentation: Specified both the primary Antigravity sidecar supervisor configuration
   and the fallback systemd user service unit.
6. Continuous poller architecture: Detailed `--once` and loop execution, first hop intake accounting (zero ledger dispatches),
   claim before launch under minted token, fix-round claim bypass with per-PR locking, and missing key handling.

### Round 3 Review Findings (PR #290 Round 2 Review & Operator Smoke)
1. `R1-2`: Poller test observable verification. Updated AT-8, AT-14, AT-15, and AT-20 to assert observables in stubs (`$MINTS`, `$WRITES`, `$LAUNCHES`, `$CLAIMS`) without asserting unobservable claim.sh internal path prefixes.
2. `R2-1`: Per-scenario git ranges and poller observables. Replaced fixed C1..C2 git range with `get_range <kind>` helper supporting three synthetic ranges (`intent`, `spec`, `implement-pr`).
3. `R2-2`: Dropped requirement for literal substring `skipping claim release`. Asserted `autonomous_merge is false` and `no dispatch for #999 (D18)` while verifying `in-progress` is preserved and zero launches occur.
4. `R2-3`: Converted advancer scenarios AT-1 through AT-6 to run live without `DRY_RUN=1`. Captured `$LAUNCHES` via sandbox placement runner.
5. `R2-4`: Created synthetic merge commit (`implement-pr`) in AT-5 with second parent on `odyssey/999-test` modifying `scripts/` to satisfy candidate detection at `lifecycle_advance.sh:27-34`.
6. `R2-5`: Updated AT-6 to assert `999 --as daedalus` in argv under live execution.
7. `R1-10.2`: Deleted PR body statement claiming the advancer emits a slug near-miss warning; clarified that ladder advance for #251 is silent because `BEST_STAGE` is set.
8. `Blocking 1` (AT-20): Removed hollow assertion predicate; asserted launch of `run.sh 108 --as odyssey`, zero claim POSTs, and identical launches on second locked tick.
9. `Blocking 2` (AT-15): Asserted claim and launch observables for athena on open `intent:new` issue with zero loop-ledger writes.
10. `Blocking 3` (AT-8): Asserted token mint in `$MINTS`, claim comment POST or record, launch in `$LAUNCHES`, and skip of already-claimed row.
11. `Blocking 4`: Settled by R2-2.
12. `Blocking 5`: Settled by R2-3 and R2-5.
13. `Blocking 6` (AT-12): Asserted `agy` launch before truncation, ran `claude-code` fixture and asserted `claude -p ... --agent odyssey --output-format json`, then restored fixture and asserted `agy` launch again.
14. `Blocking 7`: Stated in T9 and Summary that the implement rung branch MUST be `odyssey/251-e2e-chain`.
15. `Blocking 8`: Settled by R1-10.2 (Decision D).
16. `NB 2` (AT-3): Added second half of `spec.md:111` to AT-3: verifying unparseable claim comment preserves label and withholds dispatch.
17. `NB 3` (AT-13): Added positive assertion in AT-13 that resume protocol ran (`--> odyssey` and `branch: odyssey/107-fix`).
18. `NB 4` (T8): Cited `### lifecycle.labels` (:290) and `### loop.autonomous` (:953) at their actual line numbers in document order in T8.
19. `NB 5` (T6): Stated in T6 that `poll.sh` never releases a claim and documented restart idempotence per design note P2 (lines 61-67).
20. `NB 7`: Formatted PR body with line 1 as `Refs #251` followed by `## Summary`.
21. `NB 8`: Quoted full `spec_check.sh` output line with declared reason in PR body.
22. `NB 9`: Documented pre-existing `work_test.sh` failure at merge base in Gates table and PR body.

### Round 4 Review Findings (Operator Decisions A-E, Smoke Items B1-B8, NB 1-5)
1. `Decision A (R3-2, B3)`: Work discovery in stub. `gh` stub handles `gh issue list --label <l> --state open` and `gh pr list --state open` reading from `$FIXTURES/issue-list.json` and `$FIXTURES/pr-list.json`, evaluating `--json` and `--jq`. Stated in T6 that `poll.sh` discovers work via label queries and never hardcodes issue numbers. Reordered comments route above generic issue route.
2. `Decision B (R2-1, B1, B5)`: Observable claim shape. `claim.sh` stubs log `claim.sh CLAIM_ACTOR=${CLAIM_ACTOR:-} CLAIM_SESSION=${CLAIM_SESSION:-} $*` to `$CLAIMS`. AT-8 and AT-15 assert this exact format; dropped `$WRITES` branch of disjunction. Added `title` field to issue fixtures 251, 252, and 300. In AT-8, set issue 252 claim author to `evekhm-daedalus-app[bot]`, stub exits 1 with `already claimed`, and scenario asserts no launch for 252.
3. `Decision C (R3-1, B4)`: AT-14 persona alignment. Set issue 252 fixture to `status:build` with ledger `rung:3`, owned by `daedalus` under `personas/lifecycle.json`. Failed athena mint, asserted `run.sh 252 --as daedalus` launched and issue 251 did not launch.
4. `Decision D`: Hardcoded refusal. In AT-15, `issue-list.json` carries issue 300 only; scenario asserts `$LAUNCHES` contains one line naming 300.
5. `Decision E (R3-3, R3-4, NB 1)`: AT-4 base status. Documented AT-4 as green at base by construction (pure negative predicate asserting two log lines already printed and absences holding vacuously before D1). Gates Table records RED expectation as 15 of 16 RED at build rung with AT-4 green by construction.
6. `Smoke B6`: AT-3 evaluation order. Evaluated `pass_a` immediately after sub-case A before `reset_fixtures` wipes state; evaluated `pass_b` after sub-case B.
7. `Smoke B7`: AT-19 line 148 restoration. Restored verbatim marker `Spec-impact: none - intent/** only, not a behavior-bearing path`.
8. `Smoke B8`: PR body declaration. Added `Spec-impact:` line to PR body and verified clean zero exit on `spec_check.sh origin/main`.
9. `Smoke NB 2`: Anchored `-k` regex in `should_run` (`grep -qE "^($FILTER)( |$)" <<<"$1"`).
10. `Smoke NB 3`: Sandbox interception. Copied `scripts/ops` and `scripts/placement` into `$SANDBOX/scripts`, placed claim stub at `$SANDBOX/scripts/ops/claim.sh`, ran `poll.sh` from sandbox, and asserted worktree cleanliness.
11. `Smoke NB 4`: AT-17 section check. Added check for `grep -qF "## Deployment status"` in living spec.
12. `Smoke NB 5`: Plan synthetic git range documentation. Documented three synthetic git ranges used by `get_range`.

## Gates Table

| Gate / Test Suite | Command | Scope | Rung Status |
|---|---|---|---|
| Contract Suite | `bash scripts/ci/tests/e2e_chain_test.sh` | Acceptance AT-1 to AT-10, AT-12 to AT-15, AT-17, AT-20 | FAIL (15 of 16 RED at build rung, AT-4 green by construction; 1 passed, 15 failed out of 16 run) |
| Advancer Suite | `bash scripts/ci/tests/lifecycle_advance_test.sh` | Lifecycle state transitions | PASS |
| Work Suite | `bash scripts/ops/tests/work_test.sh` | Dispatch and stage resolution | FAIL (pre-existing failure at merge base: D8 harness print mismatch, fixed in T5) |
| Claim Suite | `bash scripts/ops/tests/claim_test.sh` | Mutex and claim validation | PASS |
| Merge Gate Suite | `bash scripts/ci/tests/merge_gate_test.sh` | PR merge gate evaluation | PASS |
| Sanitize Gate | `bash scripts/ci/sanitize_check.sh` | Security and secret scan | PASS |
| Spec Gate | `BODY_FILE="$(mktemp)"; echo "Spec-impact: none - contract tests run by no workflow until #246 wires them; no behavior changes" > "$BODY_FILE"; bash scripts/ci/spec_check.sh origin/main "$BODY_FILE"; rm -f "$BODY_FILE"` | Living spec impact check | PASS |
| Shellcheck | `shellcheck -S warning scripts/ci/tests/e2e_chain_test.sh` | Shell script static analysis | PASS |

Note: AT-4 is green at the base commit by construction (pure negative predicate asserting two log lines already printed and absences that hold vacuously before D1).

### NOT RUN List (Operator Preconditions)

The following acceptance rows reach live external services or operator environments and are not run inside hermetic test suites:
- **AT-11 (D2)**: Live supervisor check (operator precondition; requires live supervisor process `poll.sh` on operator VM).
- **AT-14 (D4, live half)**: Live credential preflight (operator precondition; requires live key verification on operator VM).
- **AT-16 (D6)**: Step 1 check (operator precondition; requires live Themis GitHub App verification via `create_all_apps.py --only themis --check`).
- **AT-18 (D7)**: Dedicated synthetic validation run (operator precondition; requires live end-to-end loop execution on dedicated synthetic throwaway issue).
