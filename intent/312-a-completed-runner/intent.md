# Intent: Resilient Runner Completion and Merge Gate Reviewer Check Handling

**Issue:** #312 · **Author:** athena (`evekhm-athena-app[bot]`) · **Status:** Draft

## Problem

In unattended reviewer workflows and autonomous merge evaluation, a transport-level stream interruption during a successful runner review causes an artificial exit 1, and the resulting failed check run permanently blocks merge gate Conjunct 2 from advancing the pull request head.

### 1. Headless runner wrapper conflates transport stream interruptions with execution failure

In `.github/workflows/unattended.yml` (lines 413–432), unattended reviewer personas (`argus`, `atlas`) execute via `scripts/placement/gh-actions/run.sh "$NUMBER" --as "$PERSONA"`, which delegates to `scripts/ops/work.sh "$NUMBER" --as "$PERSONA"`.

In `scripts/ops/work.sh` (lines 1354–1359), headless execution outcome handling evaluates the child process return code (`rc`) and the harness JSON envelope status:
```bash
status="$(printf '%s' "$raw" | process_status "$launch_harness" 2>/dev/null)" || status=""
[ -n "$status" ] || status="ERROR"
if [ "$rc" -ne 0 ] || [ "$status" != "SUCCESS" ]; then
    echo "==> $launch_persona's session did not complete (exit $rc, status $status)." >&2
    exit 1
fi
```
For the `antigravity` harness (`agy`), `process_status` (lines 816–819) extracts `.status` from the output JSON envelope:
```bash
antigravity) jq -r 'if (.status // "ERROR") == "SUCCESS"
                    then "SUCCESS" else "ERROR" end' ;;
```
On long-running sessions, `agy` can encounter a transport-layer stream interruption (`"error": "The stream was interrupted. Please continue the task you were working on."`). When this occurs after the persona has finished its tool turns, `agy` itself exits 0 (`rc=0`), and its output envelope contains the completed response including the terminal result line (`WORK-RESULT: ok ...`). Furthermore, external side-effects (such as posting the review comment with consensus markers) have already succeeded on GitHub.

However, because `agy` sets `"status": "ERROR"` in the envelope, `work.sh` evaluates `[ "$status" != "SUCCESS" ]` as true. It immediately logs `==> atlas's session did not complete (exit 0, status ERROR).` and terminates with exit code 1 *before* extracting `.response` or evaluating the `WORK-RESULT:` line (lines 1361–1379).

This failure mode was observed on PR #309 during unattended run `34389163039` for job `atlas via gh-actions`:
- Atlas completed its review turns and posted a clean review comment (`5606845153`) carrying its clean verdict marker and its reviewed-head marker for `006c51c0ff463768ea3c04fe08893713ca64f8a6`.
- Atlas emitted `WORK-RESULT: ok #291 posted clean round 1 review on pull request #309`.
- `agy` encountered a stream interrupt error at stream close and exited 0 with envelope `"status": "ERROR"`.
- `work.sh` exited 1, causing job `atlas via gh-actions` to conclude with `FAILURE`.

### 2. Merge Gate Conjunct 2 permanently blocks PR heads on reviewer check run conclusions

In `scripts/ci/merge_gate.sh` (lines 407–434), Conjunct 2 evaluates GitHub's merge state and the status check rollup for the PR head commit via GraphQL `statusCheckRollup`:
```awk
for (i = 1; i <= total; i++) {
    n = names[i]; s = state[n]; val = (s == "" ? "PENDING" : toupper(s))
    if (val != "SUCCESS" && val != "NEUTRAL") failing = failing " " n "=" val
}
```
Excluding only the gate's own run ID, Conjunct 2 requires *every* check run on the head commit to conclude `SUCCESS` or `NEUTRAL`.

When a reviewer dispatch job fails (e.g. `atlas via gh-actions=FAILURE`), Conjunct 2 fails:
```text
conjunct (2): false — mergeStateStatus CLEAN but check(s) not success: atlas via gh-actions=FAILURE
```
This blocks autonomous merge even when:
- Consensus Conjuncts 3, 4, 5, and 11 are completely satisfied (both Argus and Atlas verdicts are recorded on the head commit in the consensus ledger).
- All actual CI test gates (`sanitize`, `sync_agents`, `spec_check`, etc.) have passed.

Because GitHub check run conclusions attach directly to the head commit SHA, Conjunct 2 remains permanently false for that commit SHA unless the failed job is manually re-run or a new commit is pushed.

### 3. Inefficient recovery semantics for transient check failures on clean PR heads

Under current mechanics, the only automated path to clear a failed check on a head is to push a new commit. On a clean pull request that has already achieved reviewer consensus, requiring a no-op commit forces redundant re-execution of all CI workflows, invalidates reviewer `reviewed-head` hashes, and triggers unwanted reviewer re-runs.

The interim remedy verified on PR #309 was manual operator dispatch of `gh run rerun 34389163039 --failed`. This re-ran only `atlas via gh-actions` (attempt 2), succeeded, and updated the check run conclusion on the head to `SUCCESS`, clearing Conjunct 2. However, this recovery path is entirely manual and not integrated into the unattended loop.

## Proposed outcome

1. **Resilient outcome resolution in `scripts/ops/work.sh`**:
   - Update `work.sh` headless outcome processing so that when the harness child process exits 0 (`rc=0`), the wrapper inspects the response for a valid `WORK-RESULT: <ok|refused|blocked>` line.
   - If a valid `WORK-RESULT:` line is present, demote an envelope `"status": "ERROR"` (with transport/stream interrupt error messages) to a logged warning and proceed with standard verdict exit mapping (`ok` -> exit 0; `refused|blocked` -> exit 2).
   - Ensure that true failures (crashes with non-zero `rc`, turn exhaustion without `WORK-RESULT:`, missing output payloads, or unrecognized verdicts) continue to fail closed with exit code 1.

2. **Define reviewer check run semantics in Conjunct 2 (`scripts/ci/merge_gate.sh`)**:
   - Resolve whether reviewer dispatch check runs (`* via gh-actions`) should be excluded from Conjunct 2 evaluation:
     - If excluded: Reviewer status is governed exclusively by the consensus ledger (Conjuncts 3, 4, 5, 11), ensuring runner transport errors cannot block merge when valid verdicts are posted.
     - If retained: Conjunct 2 continues to inspect all check runs, relying on the resilient wrapper (Outcome 1) to ensure completed runs conclude `SUCCESS`.

3. **Establish clean re-run and check clearing mechanics without requiring new commits**:
   - Document and standardize the re-run pattern (`gh run rerun <run_id> --failed`) for transient runner failures.
   - Clarify whether the merge gate or autonomous poller may initiate targeted re-runs when a head commit meets consensus requirements but carries a retryable failed check.

4. **Hermetic test coverage and regression protection**:
   - Add unit test scenarios in `scripts/ops/tests/work_test.sh` asserting that:
     - An `antigravity` output envelope with `rc=0`, `"status": "ERROR"`, `"error": "The stream was interrupted..."`, and `"response": "... WORK-RESULT: ok ..."` produces exit code 0 and logs a warning.
     - An output envelope with `rc=0`, `"status": "ERROR"`, and no `WORK-RESULT:` line produces exit code 1.
   - Add unit test scenarios in `scripts/ci/tests/merge_gate_test.sh` asserting Conjunct 2 behavior when reviewer check runs are present in failing, neutral, or success states.

## Affected users and systems

- **Autonomous Merger (Themis / `evekhm-themis-app[bot]`)**: Evaluates Conjunct 2 in `scripts/ci/merge_gate.sh` under `.github/workflows/merge-gate.yml`.
- **Reviewers (`argus`, `atlas`)**: Run headless reviews on GitHub-hosted runners via `.github/workflows/unattended.yml`.
- **Launch Wrapper (`scripts/ops/work.sh`)**: Parses headless JSON envelopes and maps execution results to process exit codes.
- **Merge Gate (`scripts/ci/merge_gate.sh`)**: Evaluates check run rollup contexts for head commits.
- **Placement Adapter (`scripts/placement/gh-actions/run.sh`)**: Wraps unattended execution and forwards exit codes.
- **Test Suites**:
  - `scripts/ops/tests/work_test.sh`: Launcher outcome and exit code mapping tests.
  - `scripts/ci/tests/merge_gate_test.sh`: Conjunct 2 check run evaluation tests.
- **Specifications**:
  - `intent/43-harness-agnostic-launch/spec.md`: Source specification for D14 exit mapping.
  - `intent/64-autonomous-loop/spec.md`: Source specification for D24 check roll-up evaluation.
  - `docs/SPEC.md`: Living specification for launch wrapper and merge gate conjuncts.

## Constraints

- **Fail-Closed Principle**: A process crash, uncaught exception, turn exhaustion, or unobserved outcome must never be converted to success. Exit 0 is reserved strictly for sessions that completed and emitted a valid result.
- **Anti-Spoofing and Ledger Integrity**: Review verdicts must remain authenticated via trusted GitHub logins and ledger comments on the pull request. Relaxing wrapper error checks must not weaken ledger verification.
- **Hermetic Testing**: All test suite assertions in `work_test.sh` and `merge_gate_test.sh` must remain completely hermetic with zero external network or model dependencies.
- **Authority Bounds**: As Athena, this stage delivers only `intent/312-a-completed-runner/intent.md`. No implementation code or workflow configurations are modified at this stage.

## Open questions

1. **Wrapper outcome resolution under transport error**:
   - *Reading 1*: The wrapper treats `WORK-RESULT: <ok|refused|blocked>` in `.response` as sufficient evidence of completion whenever `rc == 0`, demoting envelope `status: ERROR` to a warning unconditionally.
   - *Reading 2*: The wrapper requires `rc == 0`, `WORK-RESULT:` in `.response`, *and* explicit verification of external state (e.g., confirming a review verdict marker was posted on the head commit for review dispatches) before demoting `status: ERROR`.
   - *Differing case*: A session emits `WORK-RESULT: ok` in its response stream, but a transport disruption drops the connection before its final GitHub API call (comment post or branch push) completes. Under Reading 1, `work.sh` exits 0 (false success); under Reading 2, `work.sh` detects the missing external artifact and exits 1 (fails closed).

2. **Scope of transport error demotion in `work.sh`**:
   - *Reading 1*: Demotion applies specifically to the `antigravity` harness when `.status == "ERROR"` and `.error` matches stream interrupt patterns (`stream was interrupted`).
   - *Reading 2*: Demotion is harness-agnostic, applying to any harness where `rc == 0` and a valid terminal `WORK-RESULT:` line is parsed from the response payload.
   - *Differing case*: A `claude-code` print-mode session encounters an SDK transport warning setting `.is_error = true` but prints `WORK-RESULT: ok`. Under Reading 1, it exits 1; under Reading 2, it exits 0.

3. **Treatment of reviewer dispatch check runs in Conjunct 2**:
   - *Reading 1*: Conjunct 2 explicitly filters out reviewer dispatch check runs (`argus via gh-actions`, `atlas via gh-actions`), delegating reviewer verification entirely to the consensus ledger (Conjuncts 3, 4, 5, 11).
   - *Reading 2*: Conjunct 2 continues to evaluate all check runs on the head commit including reviewer dispatches, relying on the wrapper fix (Outcome 1) to prevent false failures.
   - *Differing case*: A reviewer dispatch job crashes due to an infrastructure issue (e.g. runner OOM or kernel panic) after having posted a valid clean review comment to the PR. Under Reading 1, Conjunct 2 ignores the failed runner job and allows merge; under Reading 2, Conjunct 2 blocks merge until the job is re-run.

4. **Transient check failure recovery path**:
   - *Reading 1*: Check run re-runs (`gh run rerun <run_id> --failed`) remain an operator/advisor remedy triggered outside the gate script.
   - *Reading 2*: The merge gate or poller automatically detects a head commit blocked solely by a retryable failed runner check run and dispatches a re-run.
   - *Differing case*: A transient runner network fault causes `atlas via gh-actions` to fail on a head with full consensus. Under Reading 1, the PR remains blocked until an operator manually triggers `gh run rerun`; under Reading 2, the loop triggers the re-run automatically on the next evaluation pass.
