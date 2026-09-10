# Plan: Enforce Reviewer Run-ID Provenance Injection and Surface Verdict Refusals

**Issue:** #353 · **Spec:** `intent/353-reviewer-verdict-with/spec.md` (Approved, D1–D10, AT-353-1–AT-353-13)  
**Author:** daedalus (`evekhm-daedalus-app[bot]`)  
**Base commit:** `29b6b40b31d9fd150c1bdac875008c2db3f49d25`  
**Target branch for implementation (Odyssey):** `odyssey/353-reviewer-verdict-with-run-id-0-is`

---

## 1. Executive Summary and Problem Statement

Under repository review policy (`docs/SPEC.md:544-577`, `REVIEW.md:231-255`, PR #14, #267, #291), autonomous review agents (`argus`, `atlas`) post structured review verdict blocks containing machine-readable markers (`review-verdict`, `reviewed-head`, `run-id`, `round`, `finding`, `failure-scenario`). To prevent forged or out-of-band reviews, the consensus recorder (`scripts/ci/review_recorder.py`) validates four API provenance predicates against GitHub Actions API (`GET /repos/<repo>/actions/runs/<run_id>`):
1. `head_sha` equals the verdict block's `reviewed-head`.
2. Workflow path equals `.github/workflows/unattended.yml`.
3. `head_repository.full_name` equals this repository (`evekhm/agentic-sdlc`).
4. `event` is in `{"pull_request", "workflow_dispatch"}`.

In production, four interrelated defects caused autonomous loop deadlocks (as observed live on PR #344 and PR #319):
1. **Model Delegation of Infrastructure Metadata**: Reviewer prompts instruct LLMs to emit `<!-- run-id:<n> -->`. As inference engines, LLMs should review code diffs rather than inspect runner process environments. When an LLM fails to invoke a shell tool or copies boilerplate, it outputs `<!-- run-id:0 -->`.
2. **Missing Runner Post-Processing and Fail-Closed Guard**: Review comments are posted via `scripts/ops/post.sh <pr> --as <persona> --body-file <path>`. `post.sh` verified only `hold` labels and author identity, performing zero inspection, injection, or validation on verdict blocks. It neither injected authentic `GITHUB_RUN_ID` nor prevented invalid `run-id:0` from being published.
3. **Unattributed and Unmarked Recorder Refusals**: When `review_recorder.py` encountered `run-id:0` or provenance mismatches, it emitted unattributed notes (e.g. `[refused: run 0 head_sha mismatch: expected <sha>, got ]`) and no machine-readable marker in the consensus block (`<!-- consensus-ledger:<pr> -->`). The ledger comment remained pinned to the reviewer's prior head.
4. **Merge Gate Diagnostic Blindness**: `merge_gate.sh` evaluated conjunct (3) solely against recorded ledger heads (`ARGUS_HEAD`, `ATLAS_HEAD`). When a reviewer's verdict at `HEAD` was refused by the recorder, the gate emitted `WHY[3]="<reviewer> verdict is at <old-head>, head is <HEAD>"`. This diagnostic failed to distinguish between a pending review and a rejected review, obscuring the refusal from pollers and operators.

This plan shifts `run-id` provenance management from inference models to runner infrastructure (`scripts/ops/post.sh`), enforces fail-closed validation on verdict blocks in unattended environments, formats attributed audit notes and emits machine-readable refusal markers in `scripts/ci/review_recorder.py`, surfaces explicit refusal diagnostics in `scripts/ci/merge_gate.sh`, and expands the test matrix across repository test suites.

---

## 2. Scope and Persona Boundaries

| Actor | Stage | Authority / Files Touched | Role in Issue #353 |
|---|---|---|---|
| **athena** | plan / design | `intent/**` | Authored `intent.md` and approved `spec.md` (PR #380). |
| **daedalus** | build | `intent/**`, `scripts/*/tests/**` | Authors `plan.md` and commits failing contract tests (`test_post_run_id_injection_and_guards`, `test_attributed_verdict_refusal_audit_notes_and_logging`, `test_machine_readable_refusal_markers`, `test_refusal_marker_superseded_by_accepted_verdict`, `test_consensus_ledger_refusal_notes_rendering` in `scripts/ci/tests/review_recorder_test.sh`, and MG-47..MG-49 in `scripts/ci/tests/merge_gate_test.sh`). Daedalus **never** edits production code (`scripts/ops/post.sh`, `scripts/ci/review_recorder.py`, `scripts/ci/merge_gate.sh`, `personas/**`, `REVIEW.md`, or `docs/SPEC.md`). |
| **odyssey** | implement | `scripts/ops/post.sh`, `scripts/ci/review_recorder.py`, `scripts/ci/merge_gate.sh`, `personas/skills/review-protocol.md`, `REVIEW.md`, `docs/SPEC.md`, compiled targets | Implements the plan at pinned base commit `29b6b40b31d9fd150c1bdac875008c2db3f49d25`, turning contract tests green, re-syncing compiled agents, updating `docs/SPEC.md`, and passing all CI gates. |
| **themis** | autonomous merge | GitHub Actions (`merge-gate.yml`) | Evaluates conjuncts and autonomously merges pull requests when consensus is reached. |
| **argus / atlas** | review | comments only | Review pull requests against spec and plan. |

### Deep Review Grant (DEEP-7, DEEP-3)
- **Criteria Met:**
  - **DEEP-7 (compiler blast radius):** The implementation alters `personas/skills/review-protocol.md`. Regenerating output via `scripts/sync_agents.py` touches compiled targets across multiple personas (`.agents/agents/**` and `.claude/agents/**` for argus, atlas, odyssey, etc.).
  - **DEEP-3 (privileged/posting operations):** The implementation alters `scripts/ops/post.sh` which executes comment postings to the GitHub API.
- **Action:** Odyssey applies the `deep-review` grant when opening the PR per `scripts/ops/post.sh <pr> --as odyssey --add-label deep-review`.

---

## 3. Detailed Architectural Calls

### P1 · Automated Run-ID Provenance Injection in Runner Infrastructure (D1)
In `scripts/ops/post.sh`:
1. When posting a comment (`--body-file <path>`), inspect whether `--as <persona>` is an authorized reviewer persona (`argus` or `atlas`) and the body file contains `<!-- review-verdict:`.
2. If `GITHUB_RUN_ID` is set and non-empty (positive integer):
   - For each review verdict block (`<!-- review-verdict:<reviewer>:<verdict> -->` ... `<!-- review-verdict-end -->`):
     - If `<!-- run-id:[0-9]+ -->` is present, replace it with `<!-- run-id:${GITHUB_RUN_ID} -->`.
     - Else if `<!-- run-id:... -->` is omitted, insert `<!-- run-id:${GITHUB_RUN_ID} -->` immediately after `<!-- reviewed-head:[0-9a-f]{40} -->`.
3. Perform this transformation before the comment is posted to GitHub. If the body was modified, ensure the staged body file contains the authentic `run-id`.
4. Non-reviewer personas (`odyssey`, `daedalus`, `athena`, `themis`, `cassandra`) and comments lacking `<!-- review-verdict:` blocks are posted verbatim without modification.

### P2 · Fail-Closed Runner Guard for Unattended Reviews (D2)
In `scripts/ops/post.sh`:
1. When posting a review verdict block (`<!-- review-verdict:`) as an authorized reviewer (`argus`, `atlas`):
2. If `GITHUB_ACTIONS=true` (unattended runner environment) and `GITHUB_RUN_ID` is unset, empty, or `"0"`:
   - Abort immediately with exit status 1.
   - Emit to stderr: `GITHUB_RUN_ID is unset or zero in unattended environment; refusing to post verdict block without authentic run-id`.
   - Perform zero writes to GitHub.
3. If running locally outside GitHub Actions (`GITHUB_ACTIONS` unset or not `"true"`):
   - If `ALLOW_UNSAFE_RUN_ID=1` is exported:
     - Emit a warning to stderr: `post.sh: warning: posting review verdict with unvalidated run-id (ALLOW_UNSAFE_RUN_ID=1)`.
     - Allow the comment to post (using existing `run-id` in body or `0` if omitted).
   - Else if `GITHUB_RUN_ID` is set and > 0: proceed with P1 injection.
   - Else: exit 1 with an error requiring `GITHUB_RUN_ID` or `ALLOW_UNSAFE_RUN_ID=1`.

### P3 · Review Protocol Documentation Update (D3)
In `personas/skills/review-protocol.md` and `REVIEW.md`:
1. Document that `<!-- run-id:<n> -->` is an infrastructure-managed marker automatically injected by `scripts/ops/post.sh`.
2. Explicitly note that reviewer models may emit `<!-- run-id:0 -->` as a placeholder or omit the marker entirely; the runner will replace or insert the authentic `GITHUB_RUN_ID` at post time.
3. Run `python3 scripts/sync_agents.py` to propagate changes across compiled agent instructions.

### P4 · Attributed Verdict Refusal Audit Notes and Diagnostics (D4)
In `scripts/ci/review_recorder.py`:
1. Standardize all 8 verdict refusal conditions to output uniform attributed audit notes:
   ```text
   [refused: verdict block from @{reviewer}: {reason}]
   ```
2. Specific refusal reasons:
   - Commit not in history: `commit {reviewed_head} not in pull request history`
   - Missing reviewed-head marker: `missing reviewed-head marker`
   - Missing run-id marker: `missing run-id marker`
   - Head SHA mismatch: `run {run_id} head_sha mismatch: expected {reviewed_head}, got {run_head}`
   - Workflow path mismatch: `run {run_id} workflow path mismatch: expected .github/workflows/unattended.yml, got {run_path}`
   - Repository mismatch: `run {run_id} repository mismatch: expected evekhm/agentic-sdlc, got {run_repo}`
   - Event mismatch: `run {run_id} event mismatch: event must be pull_request or workflow_dispatch, got {run_event}`
   - Terminal run failure: `run {run_id} ended {conclusion}; verdict withdrawn`
3. Concurrently log each refused verdict diagnostic to `sys.stderr`:
   ```python
   print(f"refused: verdict block from @{reviewer}: {reason}", file=sys.stderr)
   ```

### P5 · Machine-Readable Verdict Refusal Markers in Consensus Ledger (D5)
In `scripts/ci/review_recorder.py`:
1. Whenever a verdict block for commit `H` from reviewer `R` is refused, record a machine-readable refusal marker inside the consensus ledger block (`<!-- consensus-ledger:<pr> -->` ... `<!-- consensus-ledger-end -->`):
   ```markdown
   <!-- refused-verdict:<reviewer>:<reviewed_head>:<reason_code> -->
   ```
   Reason codes:
   - `commit-not-in-history`
   - `missing-reviewed-head`
   - `missing-run-id`
   - `run-head-sha-mismatch`
   - `run-workflow-path-mismatch`
   - `run-repo-mismatch`
   - `run-event-mismatch`
   - `run-terminal-failure`
2. **Marker Superseding and Lifecycle**:
   - The ledger maintains at most one `refused-verdict` marker per `(reviewer, reviewed_head)`.
   - If a reviewer subsequently posts an accepted verdict at that same `reviewed_head` in a later comment, the `refused-verdict` marker for `(reviewer, reviewed_head)` is deleted.
   - Refusal markers for older commits are retained or pruned per head history; refusal at `HEAD` remains active until superseded by an accepted verdict from that reviewer at `HEAD`.

### P6 · Consensus Ledger Notes Rendering for Refused Verdicts (D6)
In `scripts/ci/review_recorder.py`:
1. In the generated Markdown comment for the consensus ledger:
   - When no findings are recorded and all review verdicts are refused, render the findings table placeholder:
     ```markdown
     |_No findings recorded._|||||
     ```
   - Render unique attributed refusal audit notes under `#### Notes`:
     ```markdown
     #### Notes
     - [refused: verdict block from @argus: run 2040 head_sha mismatch: expected <sha>, got <sha>]
     ```

### P7 · Refused Verdict Diagnostic Visibility in Merge Gate Conjunct (3) (D7)
In `scripts/ci/merge_gate.sh`:
1. During evaluation of conjunct (3) (Review Consensus):
   - Parse `refused-verdict` markers from `$CL` (the consensus ledger body, `merge_gate.sh:288-293`; `$LEDGER_BODY` is a different artifact):
     `<!-- refused-verdict:(argus|atlas):([0-9a-f]{40}):([a-z0-9-]+) -->`
   - For each required reviewer lacking an accepted verdict at `$HEAD` (`ARGUS_HEAD != HEAD` or `ATLAS_HEAD != HEAD`):
     - Check if a refusal marker exists for that reviewer at `$HEAD`:
       `<!-- refused-verdict:<reviewer>:$HEAD:<reason_code> -->`
     - If present, format the diagnostic:
       `WHY[3]="<reviewer> verdict at $HEAD was refused by recorder (<reason_code>); ledger recorded head is ${RECORDED_HEAD:-none}"`
     - If both Argus and Atlas have refused verdicts at `$HEAD`, format both joined by semicolon:
       `WHY[3]="argus verdict at $HEAD was refused by recorder (<reason_1>); ledger recorded head is ${ARGUS_HEAD:-none}; atlas verdict at $HEAD was refused by recorder (<reason_2>); ledger recorded head is ${ATLAS_HEAD:-none}"`
   - Refusal markers at `$HEAD` take precedence over carry-forward evaluation: if Atlas carries a refused verdict at `$HEAD`, carry-forward does not suppress the refusal diagnostic.
   - If no refusal marker exists at `$HEAD`, preserve existing behavior:
     `WHY[3]="<reviewer> verdict is at ${RECORDED_HEAD:-none}, head is $HEAD"`

---

## 4. Micro-Stepped Tasks

### Task T1: Commit Contract Test Scenarios in `scripts/ci/tests/review_recorder_test.sh` and `scripts/ci/tests/merge_gate_test.sh`
- **Owner:** daedalus (Build stage)
- **Files touched:**
  - `scripts/ci/tests/review_recorder_test.sh`
  - `scripts/ci/tests/merge_gate_test.sh`
- **Decisions implemented:** D1, D2, D4, D5, D6, D7, D8
- **Acceptance criteria proven:** AT-353-1, AT-353-2, AT-353-3, AT-353-4, AT-353-5, AT-353-6, AT-353-7, AT-353-8, AT-353-9, AT-353-10
- **Description:** Append contract tests to `review_recorder_test.sh` and `merge_gate_test.sh`:
  1. `test_post_run_id_injection_and_guards` (AT-353-1..4, D1, D2, D8):
     - Tests `post.sh` overwrites `run-id:0` with `GITHUB_RUN_ID` (AT-353-1).
     - Tests `post.sh` inserts missing `run-id` after `reviewed-head` (AT-353-2).
     - Tests `post.sh` fails closed with code 1 when `GITHUB_ACTIONS=true` and `GITHUB_RUN_ID=0` (AT-353-3).
     - Tests `post.sh` succeeds with warning when `ALLOW_UNSAFE_RUN_ID=1` outside CI (AT-353-4).
  2. `test_attributed_verdict_refusal_audit_notes_and_logging` (AT-353-5, D4, D8):
     - Tests all 8 refusal conditions emit `[refused: verdict block from @<reviewer>: <reason>]` and stderr diagnostics.
  3. `test_machine_readable_refusal_markers` (AT-353-6, D5, D8):
     - Tests refused verdict emits `<!-- refused-verdict:<reviewer>:$H:<reason_code> -->` in consensus ledger block.
  4. `test_refusal_marker_superseded_by_accepted_verdict` (AT-353-7, D5, D8):
     - Tests refusal marker is emitted initially and cleared when subsequent accepted verdict arrives at that head.
  5. `test_consensus_ledger_refusal_notes_rendering` (AT-353-8, D6, D8):
     - Tests attributed refusal notes rendered under `#### Notes` and empty findings table placeholder rendered.
  6. In `merge_gate_test.sh`: MG-47, MG-48, MG-49 (AT-353-9, AT-353-10, D7, D8):
     - MG-47: reports Argus verdict refused by recorder in `WHY[3]`.
     - MG-48: reports Atlas verdict refused by recorder in `WHY[3]`.
     - MG-49: reports dual refusals joined by semicolon in `WHY[3]`.
- **Done-When:**
  Running `bash scripts/ci/tests/review_recorder_test.sh` outputs:
  `review_recorder_test.sh results: 20 passed, 5 failed out of 25 run`
  (20 regression tests pass green, 5 contract tests fail cleanly on assertion messages, zero crashes).

---

### Task T2: Implement Automated Run-ID Injection & Fail-Closed Guard in `scripts/ops/post.sh`
- **Owner:** odyssey (Implement stage)
- **File touched:** `scripts/ops/post.sh`
- **Decisions implemented:** D1, D2
- **Acceptance criteria proven:** AT-353-1, AT-353-2, AT-353-3, AT-353-4
- **Implementation Outline:**
  In `scripts/ops/post.sh`:
  ```bash
  # Check if posting a review verdict block as reviewer persona
  if [[ "$AS" =~ ^(argus|atlas)$ ]] && grep -q "<!-- review-verdict:" "$BODY_FILE"; then
      run_id="${GITHUB_RUN_ID:-}"
      if [ -z "$run_id" ] || [ "$run_id" -eq 0 ] 2>/dev/null; then
          if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
              die "GITHUB_RUN_ID is unset or zero in unattended environment; refusing to post verdict block without authentic run-id"
          elif [ "${ALLOW_UNSAFE_RUN_ID:-}" = "1" ]; then
              echo "post.sh: warning: posting review verdict with unvalidated run-id (ALLOW_UNSAFE_RUN_ID=1)" >&2
          else
              die "GITHUB_RUN_ID is unset or 0; export GITHUB_RUN_ID or ALLOW_UNSAFE_RUN_ID=1 to post review verdicts locally"
          fi
      else
          # Process body file to inject/overwrite run-id
          new_body="$(mktemp)"
          # Python/sed injection logic replacing run-id:0 or inserting after reviewed-head
          ...
          BODY_FILE="$new_body"
      fi
  fi
  ```
- **Done-When:**
  `bash scripts/ci/tests/review_recorder_test.sh -k post_run_id` passes green.

---

### Task T3: Implement Attributed Refusal Audit Notes, Logging, and Refusal Markers in `scripts/ci/review_recorder.py`
- **Owner:** odyssey (Implement stage)
- **File touched:** `scripts/ci/review_recorder.py`
- **Decisions implemented:** D4, D5, D6
- **Acceptance criteria proven:** AT-353-5, AT-353-6, AT-353-7, AT-353-8
- **Implementation Outline:**
  1. In `scripts/ci/review_recorder.py`:
     - Update all refusal message formatting to `f"[refused: verdict block from @{reviewer}: {reason}]"`.
     - Add `print(f"refused: verdict block from @{reviewer}: {reason}", file=sys.stderr)`.
  2. Refusal marker tracking:
     - Maintain `refused_verdicts = {}` mapping `(reviewer, head)` -> `reason_code`.
     - When a block is accepted, delete `(reviewer, head)` from `refused_verdicts`.
     - When building ledger text, append `<!-- refused-verdict:{rev}:{head}:{code} -->`.
  3. Notes rendering:
     - In markdown comment generation, render unique attributed refusal notes under `#### Notes`.
     - If findings table is empty, render `|_No findings recorded._|||||`.
- **Done-When:**
  `bash scripts/ci/tests/review_recorder_test.sh` passes all 25 scenarios green.

---

### Task T4: Implement Refused Verdict Diagnostics in `scripts/ci/merge_gate.sh`
- **Owner:** odyssey (Implement stage)
- **File touched:** `scripts/ci/merge_gate.sh`
- **Decisions implemented:** D7
- **Acceptance criteria proven:** AT-353-9, AT-353-10
- **Implementation Outline:**
  In `scripts/ci/merge_gate.sh` under conjunct (3) evaluation:
  1. Extract `refused-verdict` markers from `$CL`:
     ```bash
     ARGUS_REFUSED_REASON="$(grep -Eo "<!-- refused-verdict:argus:$HEAD:[a-z0-9-]+ -->" <<<"$CL" | sed -E 's/.*:([a-z0-9-]+) -->/\1/' | head -n1 || true)"
     ATLAS_REFUSED_REASON="$(grep -Eo "<!-- refused-verdict:atlas:$HEAD:[a-z0-9-]+ -->" <<<"$CL" | sed -E 's/.*:([a-z0-9-]+) -->/\1/' | head -n1 || true)"
     ```
  2. When Argus or Atlas review is not at `$HEAD`, format `WHY[3]` incorporating `<reviewer> verdict at $HEAD was refused by recorder (<reason_code>); ledger recorded head is ${RECORDED_HEAD:-none}`.
  3. Handle dual refusals joined by `; `.
- **Done-When:**
  The observable command is a scratch copy of the suite with `fail()` made non-fatal, because `fail()` (`scripts/ci/tests/merge_gate_test.sh:33`) exits the suite at MG-38 (plan(#308), 42c6828, #308's outstanding contract, tracked as #386) some 700 lines before MG-47:
  ```bash
  sed 's/^fail() { .*/fail() { echo "FAIL: $*" >\&2; FAILED=1; }/' scripts/ci/tests/merge_gate_test.sh > /tmp/mgt-nonfatal.sh \
    && bash /tmp/mgt-nonfatal.sh 2>&1 | grep -E '^(PASS|FAIL): MG-4[789]'
  ```
  Done when that output contains no `FAIL:` line for MG-47, MG-48 or MG-49. The suite file itself is not edited and `.github/workflows/**` is not touched (D10).
- **Build-gate evidence (RED at the plan head `5b8f37e`, same command):**
  ```text
  FAIL: MG-47 (D7): conjunct (3) reports false when Argus verdict refused at HEAD (expected to find: conjunct (3): false)
  FAIL: MG-47 (D7, AT-353-9): explanatory refused verdict diagnostic reported (expected to find: argus verdict at aaaaaaaa... was refused by recorder (run-head-sha-mismatch); ledger recorded head is ...)
  FAIL: MG-48 (D7): conjunct (3) reports false when Atlas verdict refused at HEAD (expected to find: conjunct (3): false)
  FAIL: MG-48 (D7, AT-353-10): explanatory Atlas refused verdict diagnostic reported (expected to find: atlas verdict at aaaaaaaa... was refused by recorder (run-workflow-path-mismatch); ...)
  FAIL: MG-49 (D7): conjunct (3) reports false when both reviewers refused at HEAD (expected to find: conjunct (3): false)
  FAIL: MG-49 (D7): dual refusal diagnostics joined by semicolon (expected to find: argus verdict at aaaaaaaa... was refused by recorder (commit-not-in-history); ledger recorded head is bbb...)
  ```
  The `PR does not merge` guard of each scenario already passes at the head (the gate declines today for the wrong reason); the D7 assertions are the RED half.
- **Plan sync (AT-353-9, AT-353-10):** the Approved rows read "`bash scripts/ci/tests/merge_gate_test.sh` passes with exit code 0". That form is unreachable in this tree until #308 lands MG-38's contract (#386 tracks the abort class). This plan does not narrow the rows: they stay the acceptance, and the implement PR states that the exit-0 form is blocked on #308/#386 and proves D7 through the scratch command above. When #386 gives the suite an expected-red list or a scenario filter, the exit-0 form becomes observable without any change to this plan.

---

### Task T5: Update Review Protocol Documentation & Re-sync Agents
- **Owner:** odyssey (Implement stage)
- **Files touched:**
  - `personas/skills/review-protocol.md`
  - `REVIEW.md`
  - Compiled targets (`.agents/agents/**`, `.claude/agents/**`) via `scripts/sync_agents.py`
- **Decisions implemented:** D3
- **Acceptance criteria proven:** AT-353-11, AT-353-13
- **Implementation Outline:**
  1. Update `personas/skills/review-protocol.md` and `REVIEW.md` to document that `run-id` is an infrastructure-managed marker.
  2. Execute `python3 scripts/sync_agents.py` to regenerate sidecar targets.
- **Done-When:**
  `python3 scripts/sync_agents.py --check` exits 0 with zero drift.

---

### Task T6: Update Living Spec in `docs/SPEC.md`
- **Owner:** odyssey (Implement stage)
- **File touched:** `docs/SPEC.md`
- **Decisions implemented:** D9
- **Acceptance criteria proven:** AT-353-12, AT-353-13
- **Implementation Outline:**
  In `docs/SPEC.md`, under `### review.policy`:
  Document automated `run-id` injection in `post.sh`, fail-closed unattended guard, attributed refusal audit notes and stderr diagnostics in `review_recorder.py`, machine-readable `refused-verdict` markers in consensus ledger, and merge gate conjunct (3) diagnostic reporting.
- **Done-When:**
  `bash scripts/ci/spec_check.sh origin/main <pr-body>` exits 0.

---

### Task T7: Regression Test Integration and CI Gates Verification
- **Owner:** odyssey (Implement stage)
- **Files touched:**
  - `scripts/ops/tests/post_test.sh` (or `scripts/ci/tests/review_split_gate_contract_test.sh`)
- **Decisions implemented:** D8, D10
- **Acceptance criteria proven:** AT-353-1 through AT-353-13
- **Verification Commands:**
  1. `bash scripts/ci/tests/review_recorder_test.sh` -> PASS (all 25 scenarios)
  2. `python3 scripts/sync_agents.py --check` -> PASS
  3. `bash scripts/ci/sanitize_check.sh` -> PASS
  4. `bash scripts/ci/spec_check.sh origin/main` -> PASS
  5. `python3 scripts/ops/execution.py --check` -> PASS
  6. `bash scripts/ops/tests/execution_test.sh` -> PASS
  7. `bash scripts/ops/tests/placement_test.sh` -> PASS
  8. `bash scripts/ops/tests/post_test.sh` -> PASS
  9. The T4 scratch command (`fail()` non-fatal copy, `grep -E '^(PASS|FAIL): MG-4[789]'`) -> no `FAIL:` line for MG-47, MG-48, MG-49; paste the output into the implement PR body next to the note that the exit-0 form of AT-353-9/10 waits on #308/#386 (see T4 Plan sync)
- **Done-When:**
  Items 1-8 exit 0; item 9 shows no `FAIL:` line for MG-47, MG-48, MG-49 under the scratch command, with the output pasted into the implement PR body.

---

## 5. Traceability Matrix

| Acceptance Test | Decision IDs | Test Scenario / Proof | Implementing Task | Verifier Proof |
|---|---|---|---|---|
| **AT-353-1** | D1, D8 | `test_post_run_id_injection_and_guards` in `review_recorder_test.sh` | T1 (test), T2 (code) | `post.sh` overwrites `run-id:0` with `GITHUB_RUN_ID` when posted as reviewer |
| **AT-353-2** | D1, D8 | `test_post_run_id_injection_and_guards` in `review_recorder_test.sh` | T1 (test), T2 (code) | `post.sh` inserts missing `run-id` after `reviewed-head` when posted as reviewer |
| **AT-353-3** | D2, D8 | `test_post_run_id_injection_and_guards` in `review_recorder_test.sh` | T1 (test), T2 (code) | `post.sh` exits 1 with error message when `GITHUB_ACTIONS=true` and `GITHUB_RUN_ID` is unset/0 |
| **AT-353-4** | D2, D8 | `test_post_run_id_injection_and_guards` in `review_recorder_test.sh` | T1 (test), T2 (code) | `post.sh` exits 0 with warning when `ALLOW_UNSAFE_RUN_ID=1` outside CI |
| **AT-353-5** | D4, D8 | `test_attributed_verdict_refusal_audit_notes_and_logging` in `review_recorder_test.sh` | T1 (test), T3 (code) | All 8 refusal conditions emit attributed notes `[refused: verdict block from @<reviewer>: <reason>]` and stderr logging |
| **AT-353-6** | D5, D8 | `test_machine_readable_refusal_markers` in `review_recorder_test.sh` | T1 (test), T3 (code) | Refused verdict emits `<!-- refused-verdict:<reviewer>:$H:<reason_code> -->` in consensus ledger block |
| **AT-353-7** | D5, D8 | `test_refusal_marker_superseded_by_accepted_verdict` in `review_recorder_test.sh` | T1 (test), T3 (code) | Refusal marker cleared when followed by accepted verdict at that head |
| **AT-353-8** | D6, D8 | `test_consensus_ledger_refusal_notes_rendering` in `review_recorder_test.sh` | T1 (test), T3 (code) | Attributed refusal notes rendered under `#### Notes` and empty findings table rendered |
| **AT-353-9** | D7, D8 | MG-47 in `merge_gate_test.sh` | T1 (test), T4 (code) | `WHY[3]` reports Argus verdict refused by recorder with reason code and recorded head |
| **AT-353-10** | D7, D8 | MG-48, MG-49 in `merge_gate_test.sh` | T1 (test), T4 (code) | `WHY[3]` reports Atlas refused verdict and dual refusals joined by semicolon |
| **AT-353-11** | D3 | Inspection of protocol docs | T5 | `review-protocol.md` and `REVIEW.md` document infrastructure-managed `run-id` |
| **AT-353-12** | D9 | Inspection of living spec | T6 | `docs/SPEC.md` specifies run-id injection, guards, refusal markers, and gate diagnostics |
| **AT-353-13** | D10 | CI gate scripts | T7 | `sanitize_check.sh`, `spec_check.sh`, `sync_agents.py --check` exit 0 |

---

## 6. Handoff to Odyssey (Implement Stage)

- **Branch:** `odyssey/353-reviewer-verdict-with-run-id-0-is`
- **Base commit:** `29b6b40b31d9fd150c1bdac875008c2db3f49d25` (or the commit merging this plan)
- **PR Title:** `fix(review): enforce reviewer run-id provenance injection and surface verdict refusals (#353)`
- **PR Body Requirements:**
  - Reference: `Refs #353` only. No closing keyword anywhere in the PR body, commit messages or comments (docs/SPEC.md:448, #245).
  - Deep Review grant: apply `deep-review` grant label (DEEP-7: alters `personas/skills/review-protocol.md`; DEEP-3: alters `scripts/ops/post.sh`)
  - Summary of implemented tasks T2, T3, T4, T5, T6, T7
  - Proof that all 25 scenarios in `scripts/ci/tests/review_recorder_test.sh` pass green
  - Proof that `python3 scripts/sync_agents.py --check` passes green
  - Proof that `scripts/ci/spec_check.sh origin/main` passes green
