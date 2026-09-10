# Plan: Per-Pull-Request Concurrency for Merge Gate and Recorder Isolation

**Issue:** #308 · **Spec:** spec.md (Approved, D1–D9, AT-1..AT-12) · **Author:** daedalus (`evekhm-daedalus-app[bot]`)

Four tasks. Each names the files it touches, the steps in order, the Decision rows it implements, the acceptance tests it makes pass, and its done-when. **Implement on top of `origin/main` at the SHA the dispatcher pins; this plan was verified at `a8cab61eaba4db8effec5b04ad8e1ad74406e964`.** Every `file:line` below was re-read at that commit.

Order: T1 (contract tests, red gate) → T2 (workflow concurrency, trigger cleanup, pre-runner guards, target resolution) → T3 (living spec upsert in `docs/SPEC.md`) → T4 (verification suite execution).
T2 turns T1's red contract tests green; T3 records living specification updates; T4 proves the entire repository verification suite passes.

## Branch slug notice

The current build rung branch is `daedalus/308-merge-gate-yml-repository-wide`. The implementation rung head branch MUST be `odyssey/308-merge-gate-yml` matching the intent folder slug `intent/308-merge-gate-yml/`. This allows `scripts/ci/lifecycle_advance.sh` to advance the issue lifecycle to `status:in-review`.

## The calls this plan makes

The spec carried several architectural details into this build rung. Each is decided here; the implementer does not re-open them.

**P1 · Top-level workflow concurrency with per-PR group key (D1, D2, D4):**
Declare `concurrency:` once at the root level of `.github/workflows/merge-gate.yml`, above `permissions: {}`.
```yaml
concurrency:
  group: merge-gate-${{ github.event.issue.number || github.event.check_suite.pull_requests[0].number || github.event.inputs.pull_request || github.run_id }}
  cancel-in-progress: false
```
Remove job-level `concurrency:` blocks from both `record` and `gate` jobs. Under Actions concurrency semantics, scoping by PR key completely isolates concurrent pull requests from cancelling or contending with each other. Retaining `cancel-in-progress: false` ensures that in-flight recording and merge evaluation complete cleanly without being killed mid-step.

**P2 · Removal of dead `status` trigger and legacy fallbacks (D3, D7):**
In `.github/workflows/merge-gate.yml`, drop `status:` from `on:`. Repository run history shows zero `status` events (all CI checks produce CheckRuns and `check_suite` events). In both `record` and `gate` job steps:
- Remove `STATUS_SHA: ${{ github.event.sha }}` and `CS_SHA: ${{ github.event.check_suite.head_sha }}` from `env:`.
- Remove `status)` branch from the `case "$EVENT_NAME" in` block.
- Remove commit API fallback `[ -n "$TARGET" ] || TARGET="$(gh api ...)"`.
- Resolve `TARGET` directly from `$CS_PR` (`check_suite`), `$ISSUE_NUMBER` (`issue_comment`), or `$DISPATCH_PR` (`workflow_dispatch`).
- Retain the defensive guard:
  ```bash
  if [ -z "$TARGET" ] || [ "$TARGET" = "null" ]; then
    echo "no pull request behind this $EVENT_NAME event — nothing to <record|gate>"
    exit 0
  fi
  ```

**P3 · Pre-runner filtering for non-PR events (D5, D6):**
Check suites on non-PR commits (such as direct pushes to `main`) and non-PR issue comments must be skipped before runner VM allocation.
- In `jobs.record.if`:
  ```yaml
  if: github.event_name == 'workflow_dispatch' || (github.event_name == 'issue_comment' && github.event.issue.pull_request) || (github.event_name == 'check_suite' && github.event.check_suite.pull_requests[0].number)
  ```
- In `jobs.gate.if`:
  ```yaml
  if: ${{ always() && !cancelled() && (github.event_name == 'workflow_dispatch' || (github.event_name == 'issue_comment' && github.event.issue.pull_request) || (github.event_name == 'check_suite' && github.event.check_suite.pull_requests[0].number)) }}
  ```
- Retain permissive comment triggering without filtering comment body strings (such as `review-verdict:`), ensuring operator repair and verifier comments continue to trigger gating cleanly (D6).

**P4 · Orphan event fallback isolation (D4):**
If an event fires that has no associated pull request (such as a check suite before pre-runner filtering or edge event), `github.run_id` evaluates as the group key suffix (`merge-gate-<run_id>`), guaranteeing that any unassociated run receives a unique concurrency group and never interferes with any pull request queue.

**P5 · Implementation scope boundaries (D9):**
The files touched by the implementation rung (Odyssey) are strictly bounded to:
- `.github/workflows/merge-gate.yml` (concurrency, triggers, pre-runner guards, target resolution)
- `scripts/ci/tests/merge_gate_test.sh` (hermetic contract tests)
- `docs/SPEC.md` (living spec update at line 1114)
All other paths (including `merge_gate.sh`, `review_recorder.sh`, `personas/**`) are strictly forbidden.

---

## T1 · Failing contract test additions in `scripts/ci/tests/merge_gate_test.sh`

Touch: `scripts/ci/tests/merge_gate_test.sh`

1. In `scripts/ci/tests/merge_gate_test.sh`, append six hermetic contract test scenarios (MG-38 through MG-43) immediately before the closing `echo "merge_gate_test.sh: all scenarios passed"`:
   - **MG-38 · D1 D2 D4 (AT-1, AT-2, AT-9):** Workflow-level concurrency scoping. Parse `.github/workflows/merge-gate.yml` and assert:
     - Root-level `concurrency.group` equals `merge-gate-${{ github.event.issue.number || github.event.check_suite.pull_requests[0].number || github.event.inputs.pull_request || github.run_id }}`.
     - Root-level `concurrency.cancel-in-progress` is `false`.
   - **MG-39 · D1 (AT-3):** Job-level concurrency removal. Assert neither `jobs.record` nor `jobs.gate` declares a `concurrency:` block.
   - **MG-40 · D3 D5 (AT-4, AT-5):** Trigger cleanliness. Assert:
     - `status:` is absent from `on:`.
     - `check_suite:` is present under `on:` with `types: [completed]`.
     - `issue_comment:` is present under `on:` with `types: [created]`.
     - `workflow_dispatch:` is present under `on:` with input `pull_request` (required: true, type: string).
   - **MG-41 · D5 D6 (AT-6, AT-7, AT-8):** Pre-runner job guards and permissive PR comments. Assert:
     - `jobs.record.if` contains guards for `workflow_dispatch`, `github.event.issue.pull_request`, and `github.event.check_suite.pull_requests[0].number`.
     - `jobs.gate.if` contains `!cancelled()` and the same event guards.
     - Neither condition filters on comment body strings (e.g. `review-verdict:` is absent from `if:` expressions).
   - **MG-42 · D4 (AT-9):** Expression simulation and orphan isolation. Simulate expression evaluation across `issue_comment` (#101), `check_suite` (#202), `workflow_dispatch` (#303), and orphan event with `run_id` (98765). Assert distinct PR keys and isolated orphan key (`merge-gate-98765`).
   - **MG-43 · D7 (AT-10):** Simplified target resolution without API fallbacks. Assert:
     - In both `record` and `gate` steps, `STATUS_SHA` and `CS_SHA` are absent from `env:`.
     - `status)` branch is absent from the `case` statement.
     - `commits/$CS_SHA/pulls` API fallback is absent.
     - `TARGET="$CS_PR"` assignment is present.
     - Defensive empty/null TARGET exit check is preserved.

**Decisions:** D1, D2, D3, D4, D5, D6, D7, D8.
**Acceptance:** AT-1, AT-2, AT-3, AT-4, AT-5, AT-6, AT-7, AT-8, AT-9, AT-10, AT-11.
**Done when:** `bash scripts/ci/tests/merge_gate_test.sh` executes scenarios MG-1 through MG-37 successfully and fails cleanly on MG-38 (RED contract gate: expected workflow-level concurrency block, got None against unmodified `merge-gate.yml`).

---

## T2 · Workflow-level concurrency, trigger clean-up, and pre-runner guards in `.github/workflows/merge-gate.yml`

Touch: `.github/workflows/merge-gate.yml`

1. In `.github/workflows/merge-gate.yml`:
   - Immediately before `permissions: {}` (line 33), insert top-level workflow concurrency:
     ```yaml
     concurrency:
       group: merge-gate-${{ github.event.issue.number || github.event.check_suite.pull_requests[0].number || github.event.inputs.pull_request || github.run_id }}
       cancel-in-progress: false
     ```
   - In `on:` (lines 20-32), delete the `status:` trigger.
   - In `jobs.record`:
     - Delete the job-level `concurrency:` block (lines 42-44):
       ```yaml
       concurrency:
         group: merge-gate
         cancel-in-progress: false
       ```
     - Update `if:` (line 38) to pre-runner filter non-PR events:
       ```yaml
       if: github.event_name == 'workflow_dispatch' || (github.event_name == 'issue_comment' && github.event.issue.pull_request) || (github.event_name == 'check_suite' && github.event.check_suite.pull_requests[0].number)
       ```
     - In step `Resolve the pull request and record review consensus`:
       - Remove `CS_SHA: ${{ github.event.check_suite.head_sha }}` and `STATUS_SHA: ${{ github.event.sha }}` from `env:`.
       - Update the `case "$EVENT_NAME" in` block to eliminate the API fallback and `status)` branch:
         ```bash
         case "$EVENT_NAME" in
           check_suite)
             TARGET="$CS_PR";;
           issue_comment)
             TARGET="$ISSUE_NUMBER";;
           workflow_dispatch)
             TARGET="$DISPATCH_PR";;
           *)
             TARGET="";;
         esac
         ```
   - In `jobs.gate`:
     - Delete the job-level `concurrency:` block (lines 106-108).
     - Update `if:` (line 102) to:
       ```yaml
       if: ${{ always() && !cancelled() && (github.event_name == 'workflow_dispatch' || (github.event_name == 'issue_comment' && github.event.issue.pull_request) || (github.event_name == 'check_suite' && github.event.check_suite.pull_requests[0].number)) }}
       ```
     - In step `Resolve the pull request and run the gate`:
       - Remove `CS_SHA: ${{ github.event.check_suite.head_sha }}` and `STATUS_SHA: ${{ github.event.sha }}` from `env:`.
       - Update the `case "$EVENT_NAME" in` block identically to `record`:
         ```bash
         case "$EVENT_NAME" in
           check_suite)
             TARGET="$CS_PR";;
           issue_comment)
             TARGET="$ISSUE_NUMBER";;
           workflow_dispatch)
             TARGET="$DISPATCH_PR";;
           *)
             TARGET="";;
         esac
         ```

**Decisions:** D1, D2, D3, D4, D5, D6, D7.
**Acceptance:** AT-1, AT-2, AT-3, AT-4, AT-5, AT-6, AT-7, AT-8, AT-9, AT-10, AT-11.
**Done when:** `bash scripts/ci/tests/merge_gate_test.sh` exits 0 with all scenarios (MG-1 through MG-43) passing green.

---

## T3 · Living spec upsert in `docs/SPEC.md`

Touch: `docs/SPEC.md`

1. In `docs/SPEC.md` at line 1114:
   - Amend the paragraph describing merge gate concurrency:
     - Replace:
       `Both jobs run under `environment: themis` and share `concurrency: group: merge-gate` (#267).`
     - With:
       `Both mutating jobs run under `environment: themis` and share workflow-level concurrency scoped per pull request (`concurrency: group: merge-gate-${{ pr }}` with `cancel-in-progress: false`) (#308). The `status` trigger is removed (all CI gates emit CheckRuns producing `check_suite` events), and check suites without pull requests (e.g. pushes to `main`) skip pre-runner in job `if:` conditions (#308).`
2. Verify living spec update conformance:
   - Run `bash scripts/ci/spec_check.sh origin/main` to prove the spec obligation is satisfied by the direct diff to `docs/SPEC.md`.

**Decisions:** D9.
**Acceptance:** AT-12.
**Done when:** `docs/SPEC.md` accurately documents workflow-level per-PR concurrency and `status` trigger removal, and `bash scripts/ci/spec_check.sh origin/main` exits 0.

---

## T4 · Verification and CI gates suite execution

Touch: None (verification only)

1. Execute all mechanical verification checks across the repository:
   - `python3 scripts/sync_agents.py --check` (exit 0, no compiler drift)
   - `bash scripts/ci/compiler_roundtrip.sh` (exit 0)
   - `bash scripts/ci/sanitize_check.sh` (exit 0)
   - `python3 scripts/ops/execution.py --check` (exit 0)
   - `bash scripts/ops/tests/execution_test.sh` (exit 0)
   - `bash scripts/ops/tests/placement_test.sh` (exit 0)
   - `bash scripts/ops/tests/post_test.sh` (exit 0)
   - `bash scripts/ci/tests/merge_gate_test.sh` (exit 0, all 43 scenarios pass)

**Decisions:** D1–D9.
**Acceptance:** AT-11.
**Done when:** All verification suites exit 0.

---

## Summary of Gates and Checks

| Task | Check | Expected Result | Acceptance |
|---|---|---|---|
| T1 | `bash scripts/ci/tests/merge_gate_test.sh` | RED: fails on MG-38 (missing workflow concurrency) | AT-1..AT-11 |
| T2 | `bash scripts/ci/tests/merge_gate_test.sh` | GREEN: exits 0 (all MG-1..MG-43 scenarios pass) | AT-1..AT-11 |
| T3 | `bash scripts/ci/spec_check.sh origin/main` | GREEN: exits 0 (living spec updated) | AT-12 |
| T4 | `bash scripts/ci/sanitize_check.sh` | GREEN: exits 0 | D8 |
| T4 | `python3 scripts/ops/execution.py --check` | GREEN: exits 0 | D8 |
| T4 | `bash scripts/ops/tests/execution_test.sh` | GREEN: exits 0 | D8 |
