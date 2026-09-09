# Plan: Headless Runner Error Demotion and Check Evaluation

**Issue:** #312 · **Spec:** spec.md (Approved, D1–D8, AT-312-1..AT-312-8) · **Author:** daedalus (`evekhm-daedalus-app[bot]`)

Four tasks. Each names the files it touches, the steps in order, the Decision rows it implements, the acceptance tests it makes pass, and its done-when. **Implement on top of `origin/main` at the SHA the dispatcher pins; this plan was verified at `9a3c4f1ea01b547516a15f0d428ee6789675a233`.** Every `file:line` below was re-read at that commit.

Order: T1 (contract tests, red gate) → T2 (headless outcome resolution in `work.sh`) → T3 (living spec updates in `docs/SPEC.md` and review row reconciliation) → T4 (verification suite execution).
T2 turns T1's red contract tests green; T3 records living specification updates; T4 proves the entire repository verification suite passes.

## Branch slug notice

The current build rung branch is `daedalus/312-a-completed-runner`. The implementation rung head branch MUST be `odyssey/312-a-completed-runner` matching the intent folder slug. This allows `scripts/ci/lifecycle_advance.sh` to advance the issue lifecycle to `status:in-review`.

## The calls this plan makes

The spec and PR #334 review carried four reconciliation items into this build rung. Each is decided here; the implementer does not re-open them.

**P1 · Child process return code ($rc) precedence over envelope status (D1):**
Child return code `rc` is primary. When `rc != 0` (process crash, unhandled signal, OOM, or non-zero exit from runner/wrapper), `work.sh` logs `==> $launch_persona's session did not complete (exit $rc, status $status).` and exits 1 immediately (fails closed). It never inspects or honors a `WORK-RESULT:` line in response text when `rc != 0`.

**P2 · Error demotion criteria and fail-closed absence handling (D1, D2, Argus R1-1):**
When `rc == 0`, `work.sh` does not terminate immediately upon seeing `status != "SUCCESS"`. It decodes the response text via `response_text "$launch_harness"` and parses for a terminal `WORK-RESULT:` line via `grep -E '^[[:space:]]*WORK-RESULT:' | tail -1`.
- If a valid terminal `WORK-RESULT:` line is present: `work.sh` demotes the envelope error to a warning logged to stderr (P3) and maps the parsed verdict (`ok` exits 0; `refused` or `blocked` exits 2; unrecognised verdict exits 1).
- If no valid `WORK-RESULT:` line is present: `work.sh` logs `==> $launch_persona's session did not complete (exit 0, status $status).` and exits 1 (fails closed). This disposes of Open Question 1's differing case (Argus R1-1).
- If `status == "SUCCESS"` but no `WORK-RESULT:` line is present: `work.sh` logs `==> $launch_persona's session exited cleanly but printed no WORK-RESULT line; the outcome was not observed.` and exits 1 (#43 D14 preserved).

**P3 · Warning formatting and diagnostic transparency (D6):**
When demoting an envelope status error under P2, `work.sh` logs to stderr:
`==> warning: $launch_persona's harness reported status $status with error: $err; terminal WORK-RESULT observed, proceeding.`
Where `$err` is extracted from `.error` in the JSON payload (trimmed and truncated to a single line). If `.error` is absent, empty, or null, the fallback is `status $status (no error detail)`.

**P4 · Harness-agnostic outcome resolution (D2, D5):**
Demotion applies uniformly to all headless harnesses (`antigravity` and `claude-code`). `response_text()` and `process_status()` in `scripts/ops/work.sh` continue to normalize harness-specific JSON shapes (`.response` vs `.result`, `.status == "SUCCESS"` vs `.is_error == false`). Error extraction inspects `.error` uniformly across harnesses.

**P5 · Conjunct 2 check run evaluation preservation (D3, D4, Argus R1-2, R1-4):**
In `scripts/ci/merge_gate.sh`, Conjunct 2 evaluates foreign check runs on the head commit without name or context exclusions (#64 D24, #298 D3). At `merge_gate.sh:424`, both `SUCCESS` and `NEUTRAL` conclusions are admitted; any other conclusion (including reviewer check runs like `atlas via gh-actions=FAILURE`) causes Conjunct 2 to fail. Transient check failures are remediated via GitHub Actions retry mechanisms (`gh run rerun <run_id> --failed`, measured on PR #309 per `intent/312-a-completed-runner/intent.md:62`), which update check run entries on the head commit and resolve cleanly under #298 D3 deduplication without code changes to `merge_gate.sh`.

**P6 · Scope boundary verification duty (D7, Argus R1-3):**
The files touched by issue #312 are strictly bounded by D7: `scripts/ops/work.sh`, `scripts/ops/tests/work_test.sh`, `scripts/ci/tests/merge_gate_test.sh`, `docs/SPEC.md`, and `intent/312-a-completed-runner/spec.md`. Because no automated path boundary gate runs in `scripts/ci`, D7 compliance is a reviewer verification duty (Argus R1-3) evaluated by inspecting the PR diff against this allowlist.

**P7 · Ambient environment hygiene in test runner (D8):**
`scripts/ops/tests/work_test.sh` unsets `WORK_MAX_USD` alongside `WORK_DISPATCHED_ISSUE` in its preamble, ensuring hermetic test suite execution in runner and container environments where spend ceilings are exported.

---

## T1 · Failing contract test suite additions

Touch: `scripts/ops/tests/work_test.sh`, `scripts/ci/tests/merge_gate_test.sh`

1. In `scripts/ops/tests/work_test.sh`:
   - At line 49, add `unset WORK_MAX_USD` directly following `unset WORK_DISPATCHED_ISSUE` (P7).
   - Add test banner `#312 D1/D2/D5/D6/D8 stream interrupt and headless outcome error demotion` before final suite summary.
   - Define test fixtures:
     - `$WORK/agy_stream_interrupt_ok.json`: `{"status":"ERROR","error":"The stream was interrupted. Please continue the task you were working on.","response":"Review finished.\nWORK-RESULT: ok #113 posted clean review"}`
     - `$WORK/agy_stream_interrupt_refused.json`: `{"status":"ERROR","error":"The stream was interrupted. Please continue the task you were working on.","response":"Cannot proceed.\nWORK-RESULT: refused #113 hold present"}`
     - `$WORK/agy_stream_interrupt_no_result.json`: `{"status":"ERROR","error":"The stream was interrupted. Please continue the task you were working on.","response":"Processing half way through and stopped."}`
     - `$WORK/cc_stream_interrupt_ok.json`: `{"type":"result","subtype":"error","is_error":true,"error":"Connection reset by peer","result":"All checks passed.\nWORK-RESULT: ok #130 implemented"}`
   - Add test cases:
     - **AT-312-1 (D1, D2, D5, D6, D8):** Run with `AGY_RC=0`, `AGY_JSON="$WORK/agy_stream_interrupt_ok.json"`, assert exit 0, verdict `ok`, and stderr warning `warning: daedalus's harness reported status ERROR with error: The stream was interrupted. Please continue the task you were working on.; terminal WORK-RESULT observed, proceeding.`.
     - **AT-312-2 (D1, D2, D5, D8):** Run with `AGY_RC=0`, `AGY_JSON="$WORK/agy_stream_interrupt_refused.json"`, assert exit 2 and verdict `refused`.
     - **AT-312-3 (D1, D5, D8):** Run with `AGY_RC=0`, `AGY_JSON="$WORK/agy_stream_interrupt_no_result.json"`, assert exit 1 and stderr message `session did not complete (exit 0, status ERROR)`.
     - **AT-312-4 (D1, D8):** Run with `AGY_RC=1`, `AGY_JSON="$WORK/agy_stream_interrupt_ok.json"`, assert exit 1 and stderr message `session did not complete (exit 1, status ERROR)` (child non-zero exit code takes precedence).
     - **AT-312-5 (D1, D2, D5, D8):** Run with `CLAUDE_RC=0`, `CLAUDE_JSON="$WORK/cc_stream_interrupt_ok.json"`, assert exit 0 and verdict `ok` for claude-code.
2. In `scripts/ci/tests/merge_gate_test.sh`:
   - Add scenario **MG-37 (D3, D4, AT-312-6):** foreign check run `atlas via gh-actions` with status `FAILURE` fails Conjunct 2 (`conjunct (2): false`), names the failing check `atlas via gh-actions=FAILURE`, and prevents merge.

**Decisions:** D1, D2, D3, D4, D5, D6, D8.
**Acceptance:** AT-312-1, AT-312-2, AT-312-3, AT-312-4, AT-312-5, AT-312-6, AT-312-7.
**Done when:** `bash scripts/ci/tests/merge_gate_test.sh` exits 0, and `bash scripts/ops/tests/work_test.sh` reports clean assertion failure on AT-312-1 (RED contract gate: expected exit 0, got 1 against unmodified `work.sh`).

---

## T2 · Headless outcome resolution refactoring and error demotion in `scripts/ops/work.sh`

Touch: `scripts/ops/work.sh`

1. In `scripts/ops/work.sh` (lines 1354–1380), refactor post-execution status evaluation:
   - First check child return code `rc`:
     ```bash
     if [ "$rc" -ne 0 ]; then
         echo "==> $launch_persona's session did not complete (exit $rc, status $status)." >&2
         exit 1
     fi
     ```
   - Extract decoded response text and terminal `WORK-RESULT:` line:
     ```bash
     text="$(printf '%s' "$raw" | response_text "$launch_harness" 2>/dev/null)" || text=""
     result_line="$(printf '%s\n' "$text" \
         | grep -E '^[[:space:]]*WORK-RESULT:' | tail -1)" || result_line=""
     ```
   - If `status != "SUCCESS"`:
     - If `[ -z "$result_line" ]`: log `==> $launch_persona's session did not complete (exit 0, status $status).` >&2 and exit 1 (fails closed, D1).
     - If `[ -n "$result_line" ]`: demote error to warning (D1, D2, D6). Extract `err`:
       ```bash
       err="$(printf '%s' "$raw" | jq -r '(.error // "")' 2>/dev/null | tr '\n' ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
       if [ -n "$err" ]; then
           echo "==> warning: $launch_persona's harness reported status $status with error: $err; terminal WORK-RESULT observed, proceeding." >&2
       else
           echo "==> warning: $launch_persona's harness reported status $status (no error detail); terminal WORK-RESULT observed, proceeding." >&2
       fi
       ```
   - If `status == "SUCCESS"` and `[ -z "$result_line" ]`:
     - Log `==> $launch_persona's session exited cleanly but printed no WORK-RESULT line; the outcome was not observed.` >&2 and exit 1 (#43 D14 preserved, D1).
   - Evaluate verdict from `result_line`:
     ```bash
     verdict="$(printf '%s\n' "$result_line" | awk '{print $2}')"
     echo "==> $launch_persona reported: $verdict"
     case "$verdict" in
         ok)              exit 0 ;;
         refused|blocked) exit 2 ;;
         *)
             echo "==> '$verdict' is not one of ok|refused|blocked; the outcome was not observed." >&2
             exit 1 ;;
     esac
     ```

**Decisions:** D1, D2, D5, D6.
**Acceptance:** AT-312-1, AT-312-2, AT-312-3, AT-312-4, AT-312-5.
**Done when:** All scenarios in `scripts/ops/tests/work_test.sh` pass with exit code 0.

---

## T3 · Living spec updates in `docs/SPEC.md` and review row reconciliation

Touch: `docs/SPEC.md`, `intent/312-a-completed-runner/spec.md`

1. In `docs/SPEC.md`:
   - Under `### loop.autonomous` (or headless outcome processing): document the outcome resolution rules amending #43 D14:
     - Process exit code `rc == 0` is required for error demotion; `rc != 0` always fails closed (exit 1).
     - When `rc == 0`, a non-SUCCESS harness status is demoted to a warning logged to stderr if a valid terminal `WORK-RESULT:` line is observed.
     - When `rc == 0` and status is not SUCCESS without a terminal `WORK-RESULT:` line, `work.sh` fails closed with exit 1.
     - Document that Conjunct 2 in `merge_gate.sh` evaluates foreign check runs without name exclusions (#64 D24), admitting `SUCCESS` and `NEUTRAL` (#298 D3).
2. In `intent/312-a-completed-runner/spec.md`:
   - Address the four review rows from Argus's review of PR #334:
     - Record that Open Question 1's differing case fails closed under D1 (Argus R1-1).
     - Quote and supersede #298 D3's admissible conclusions to reflect `SUCCESS` and `NEUTRAL` per `merge_gate.sh:424` (Argus R1-2).
     - Note that D7 (scope boundary) is an operator/reviewer verification duty against git diff, as no path filter gate exists in `scripts/ci` (Argus R1-3).
     - Cite `intent/312-a-completed-runner/intent.md:62` for live `gh run rerun` measurement on PR #309 (Argus R1-4).

**Decisions:** D1, D2, D3, D4, D5, D6, D7.
**Acceptance:** AT-312-8.
**Done when:** `bash scripts/ci/spec_check.sh origin/main <pr-body-file>` passes with exit code 0.

---

## T4 · Verification suite execution and clean gates check

Touch: (none)

1. Execute full verification suite from repository root:
   - `bash scripts/ops/tests/work_test.sh` (all scenarios pass, exit 0).
   - `bash scripts/ci/tests/merge_gate_test.sh` (all scenarios pass, exit 0).
   - `bash scripts/ci/sanitize_check.sh` (PASS, exit 0).
   - `python3 scripts/sync_agents.py --check` (PASS, 0 drift, exit 0).
   - `python3 scripts/ops/execution.py --check` (PASS, 5 bindings, 1 event, exit 0).
   - `bash scripts/ci/spec_check.sh origin/main <pr-body-file>` (PASS, exit 0).

**Decisions:** D1..D8.
**Acceptance:** AT-312-1..AT-312-8.
**Done when:** All six verification commands exit 0.

---

## Traceability matrix

| Decision / Acceptance | Implementing Task | Proving Test / Verification |
|---|---|---|
| D1 (Supersession of #43 D14) | T1, T2 | AT-312-1, AT-312-2, AT-312-3, AT-312-4 |
| D2 (Harness-agnostic demotion) | T1, T2 | AT-312-1, AT-312-5 |
| D3 (Conjunct 2 check run preservation) | T1, T3 | AT-312-6 (MG-31..MG-34, MG-37) |
| D4 (Transient check failure remediation) | T1, T3 | AT-312-6, AT-312-7 |
| D5 (Terminal WORK-RESULT line extraction) | T1, T2 | AT-312-1, AT-312-2, AT-312-3, AT-312-5 |
| D6 (Warning logging transparency) | T1, T2 | AT-312-1 |
| D7 (Scope boundary) | T1, T2, T3, T4 | AT-312-8, reviewer diff check |
| D8 (Hermetic contract tests) | T1 | `scripts/ops/tests/work_test.sh` |
| AT-312-1 (Stream interrupt + ok verdict) | T1, T2 | `work_test.sh` AT-312-1 |
| AT-312-2 (Stream interrupt + refused verdict) | T1, T2 | `work_test.sh` AT-312-2 |
| AT-312-3 (Stream interrupt without WORK-RESULT) | T1, T2 | `work_test.sh` AT-312-3 |
| AT-312-4 (Child rc=1 precedence) | T1, T2 | `work_test.sh` AT-312-4 |
| AT-312-5 (Claude-code is_error demotion) | T1, T2 | `work_test.sh` AT-312-5 |
| AT-312-6 (Foreign check evaluation in Conjunct 2) | T1, T4 | `merge_gate_test.sh` MG-37 |
| AT-312-7 (Check roll-up deduplication) | T1, T4 | `merge_gate_test.sh` MG-31 |
| AT-312-8 (Clean gates verification) | T4 | `sanitize_check.sh`, `spec_check.sh`, `sync_agents.py` |

---

## Commutability

- **T1** is committed first by Daedalus (Build stage), establishing the red contract test gate.
- **T2** implements the behavior in `scripts/ops/work.sh`, turning T1's tests green.
- **T3** (living spec update) commutes with T2 and can be staged alongside T2 in the Implementation PR.
- **T4** depends on completion of T1, T2, and T3.

---

## Gates table

Commands to run from the root of the tree:

| # | Command | Expected | Proves |
|---|---|---|---|
| 1 | `bash scripts/ops/tests/work_test.sh` | exit 0 | AT-312-1..AT-312-5 (D1, D2, D5, D6, D8) |
| 2 | `bash scripts/ci/tests/merge_gate_test.sh` | exit 0 | AT-312-6, AT-312-7 (D3, D4) |
| 3 | `bash scripts/ci/sanitize_check.sh` | exit 0, `PASS` | AT-312-8, repository cleanliness |
| 4 | `python3 scripts/sync_agents.py --check` | exit 0 | AT-312-8, agent compiler parity |
| 5 | `python3 scripts/ops/execution.py --check` | exit 0 | AT-312-8, execution binding parity |
| 6 | `bash scripts/ci/spec_check.sh origin/main <pr-body-file>` | exit 0 | AT-312-8, living spec obligation |

---

## NOT RUN list

None. All contract tests in `scripts/ops/tests/work_test.sh` and `scripts/ci/tests/merge_gate_test.sh` execute hermetically using existing stub fixtures without network calls or external tokens.
