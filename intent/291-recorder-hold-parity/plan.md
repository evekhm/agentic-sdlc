# Plan: Consensus Recorder Hold Parity and Spec Reconciliation

**Issue:** #291 · **Spec:** spec.md (Approved, D1–D10, AT-291-1..AT-291-11) · **Author:** daedalus (`evekhm-daedalus-app[bot]`)

Five tasks. Each names the files it touches, the steps in order, the Decision rows it implements, the acceptance tests it makes pass, and its done-when. **Implement on top of `origin/main` at the SHA the dispatcher pins; this plan was verified at `cf45f7ee1c4ab9817745db710fb8e270929069cd`.** Every `file:line` below was re-read at that commit.

Order: T1 (contract test suite, red gate) → T2 (Python engine extraction) → T3 (shell entrypoint refactoring and fail-closed hold circuit breaker) → T4 (living spec and cross-reference documentation) → T5 (gates verification).
T2 and T3 turn T1's failing tests green; T4 updates living specifications; T5 proves the entire repository verification suite passes.

## Branch slug notice

The current build rung branch is `daedalus/291-recorder-hold-parity`. The implementation rung head branch MUST be `odyssey/291-recorder-hold-parity` matching the intent folder slug. This allows `scripts/ci/lifecycle_advance.sh` to advance the issue lifecycle to `status:in-review`.

## The calls this plan makes

The spec and PR #309 review carried four reconciliation items into this build rung. Each is decided here; the implementer does not re-open them.

**P1 · Hold circuit breaker write-time re-read invariant and contiguous write sequence (D1, D2):**
The consensus recorder performs hold evaluation twice: first during initial preflight (Guard 2 at lines 57-72 of `scripts/ci/review_recorder.sh`), and second immediately before entering the write sequence (lines 607-622). The write sequence performs comment updates (`POST` or `PATCH`) and label synchronization (`gh issue edit`). All writes execute together within this single contiguous block. If `hold` is present on the pull request or any linked issue during the write-time re-read, the recorder halts immediately, logs `hold present on #<target>, recorder writes nothing`, and exits 0 with zero writes.

**P2 · Linked issue resolution scope (D2):**
The target set checked for `hold` encompasses the pull request itself and all linked issues resolved from GraphQL `closingIssuesReferences`, pull request body references matching `\b(close[sd]?|fix(es|ed)?|resolve[sd]?|refs?)\s+#[0-9]+` case-insensitively, and the head branch name matching `^([a-zA-Z0-9_-]+/)?([0-9]+)-`.

**P3 · Fail-closed hold probe error handling (D1, D2, Argus R1-3, AT-291-11):**
When checking `hold` via `gh pr view` or `gh issue view`, errors from the GitHub CLI (such as HTTP 500, rate limits, or network timeouts) must NOT fail open under `2>/dev/null || true`. If a hold probe fails (exit code != 0 or empty/unparseable JSON), the recorder must fail closed: log an error (`error: failed to probe hold status on #<target>; aborting to fail closed`), perform zero writes, and exit 1.

**P4 · Reconciliation of #267 D7 versus REVIEW.md:275 (Advisor row 4):**
`#267 D7` wins for consensus ledger wire row recording. `REVIEW.md:275` defines reviewer protocol duties ("From round 2 on, no peer verdict is owed or requested for `high`, `normal`, or `suggestion` rows. Each reviewer verifies its own open blocking rows"). In the ledger state machine (`#267 D7`), peer concurrence (`peer=agree`) is only tracked and evaluated for `security` rows across all rounds (`REVIEW.md:278-280`, `merge_gate.sh:28,271`). For non-security rows (`high`, `normal`, `suggestion`), peer consensus state on the wire row is `none` (unless an explicit dispute is filed, setting `peer=dispute`). The recorder discards round-1 peer agreement on non-security findings because peer agreement is not a gate condition for clearing `high` findings (only the discovering reviewer can verify the fix and transition status to `fixed`). Emitting `peer=none` accurately reflects that no peer agreement is tracked or required by `merge_gate.sh` for non-security rows. Drifted line pointers in `REVIEW.md` (`REVIEW.md:119-122`, `REVIEW.md:166-168`) are updated in passing.

**P5 · Finding ID attribution in failure scenario demotion notes (D4, AT-291-4):**
When a `high` severity finding lacks a sibling `<!-- failure-scenario:<id> -->` marker, the demotion audit note appended to the ledger table must explicitly identify the finding: `[demoted from high: missing failure_scenario marker] on <id>`. This prevents note deduplication from collapsing distinct demotions into a single line, adhering to `REVIEW.md:119-122`.

**P6 · Python engine extraction to `scripts/ci/review_recorder.py` (D8, AT-291-8):**
In compliance with `docs/PLAYBOOK.md:521-524`, the embedded Python heredoc inside `scripts/ci/review_recorder.sh` is extracted into a standalone executable script `scripts/ci/review_recorder.py` (`chmod +x`). `scripts/ci/review_recorder.sh` handles shell environment setup, preflight token checks, viewer login queries, pre-write hold checks, and invokes `python3 "$REPO/scripts/ci/review_recorder.py" "$PR" "$REPO" "$PR_JSON" "$WORKDIR" "$RECORDER_LOGIN"`. The python engine parses review comments, checks provenance, enforces the round admissibility funnel, builds the consensus ledger markdown, derives label changes, and writes `action_plan.json` and `new_body.md` into `$WORKDIR`.

**P7 · Acceptance test namespace disambiguation and observable re-read (Advisor rows 1 & 2):**
To eliminate namespace collisions between #267's `AT-1..18` and #291's acceptance criteria, all acceptance tests for #291 are prefixed as `AT-291-1` through `AT-291-11`. In `scripts/ci/tests/review_recorder_test.sh`, test cases cite both the #267 and #291 acceptance IDs. Furthermore, AT-291-9 is implemented as an observable contract test (`test_write_time_hold_reread`) that flips `hold` dynamically between initial action plan derivation and the write sequence, verifying zero writes and exit 0.

## T1 · Failing contract test suite updates and additions

Touch: `scripts/ci/tests/review_recorder_test.sh`

1. Update `scripts/ci/tests/review_recorder_test.sh` test header and existing test cases to cite `AT-291-1` through `AT-291-11` and Decisions D1 through D10:
   - `test_high_failure_scenario_demotion` (AT-5, D5 / AT-291-4, D4): assert finding ID attribution `[demoted from high: missing failure_scenario marker] on R1-2@D5`.
   - `test_round_funnel` (AT-7, D6 / AT-291-6, D6): cite non-blocking finding round funnel classification.
   - `test_label_sync` (AT-10, D5, D7, D8 / AT-291-1, AT-291-2, AT-291-3, AT-291-5, AT-291-7):
     - Case (a): PR carrying hold produces zero writes, logs held line, exits 0 (AT-291-1, D1, D2).
     - Case (b): Label synchronization preserves unrelated labels such as `bootstrap` (AT-291-3, D3), preserves withdrawn/dispute rows (AT-291-5, D5).
     - Case (c): PR closing held issue produces zero writes, logs held line, exits 0 (AT-291-2, D1, D2).
     - Case (d): Monotonic round counter progression: existing `review:2` is not decremented to `review:1` on round-1 review arrival (AT-291-7, D7).
2. Add new observable write-time hold re-read contract test `test_write_time_hold_reread` (AT-291-9, D1, D2):
   - Configure stub `gh` to return normal PR on initial view, and return `hold` label on second view (the write-time re-read).
   - Assert that recorder halts prior to any write, logs `hold present on #114, recorder writes nothing`, exits 0, and `$WRITES` is empty.
3. Add new fail-closed hold probe contract test `test_hold_probe_fail_closed` (AT-291-11, D1, D2, Argus R1-3):
   - Configure stub `gh` to fail with HTTP 500 when probing issue #215.
   - Assert that recorder exits non-zero (exit 1), logs error diagnostic, and `$WRITES` is empty (fails RED against current `review_recorder.sh:616` which fails open).
4. Add new Python engine extraction contract test `test_python_engine_extraction` (AT-291-8, D8):
   - Assert `scripts/ci/review_recorder.py` exists, is executable, and is invoked by `scripts/ci/review_recorder.sh`.
   - Assert direct CLI execution of `python3 scripts/ci/review_recorder.py` generates `action_plan.json` and `new_body.md` (fails RED against current tree where `scripts/ci/review_recorder.py` does not exist).
5. Add the three new tests to `TESTS=( ... )` array.

**Decisions:** D1, D2, D3, D4, D5, D6, D7, D8, D10.
**Acceptance:** AT-291-1, AT-291-2, AT-291-3, AT-291-4, AT-291-5, AT-291-6, AT-291-7, AT-291-8, AT-291-9, AT-291-11.
**Done when:** `bash scripts/ci/tests/review_recorder_test.sh` runs cleanly and reports 14 passed, 2 failed out of 16 run (RED gate: `test_hold_probe_fail_closed` and `test_python_engine_extraction` fail awaiting implementation).

## T2 · Standalone Python engine extraction (`scripts/ci/review_recorder.py`)

Touch: `scripts/ci/review_recorder.py` (new file)

1. Create `scripts/ci/review_recorder.py` with permissions `chmod +x`.
2. Implement argument handling expecting:
   `sys.argv[1]`: PR number
   `sys.argv[2]`: repository (`owner/repo`)
   `sys.argv[3]`: pull request JSON string
   `sys.argv[4]`: temporary work directory path
   `sys.argv[5]`: recorder login (`evekhm-themis-app[bot]`)
3. Extract core consensus recorder logic from `scripts/ci/review_recorder.sh:87-594`:
   - Paginate issue comments via `gh api repos/<repo>/issues/<pr>/comments`.
   - Extract and validate structured review verdict blocks from authorized reviewer logins (`evekhm-argus-app[bot]`, `evekhm-atlas-app[bot]`).
   - Validate Actions run provenance via `GET repos/<repo>/actions/runs/<run_id>` against head SHA, workflow path, repo, and event.
   - Enforce round funnel: Round 1 admits all tiers; Rounds 2-3 admit new findings at security or high, with new observations filed as `normal` with `peer=none`; historical suggestions retain `suggestion` (D6).
   - Enforce high failure scenario demotion with finding ID attribution: `[demoted from high: missing failure_scenario marker] on {fid}` (D4).
   - Enforce demotion exemptions: high findings with `status == "withdrawn"` or `peer == "dispute"` are exempted from demotion (D5).
   - Enforce monotonic round counter progression: `target_round = min(effective_round, 3)` does not decrement existing higher `review:<n>` labels (D7).
   - Reconcile derived labels: compute `desired_labels`, `to_add`, and `to_remove` while strictly preserving unmanaged labels (D3).
   - Generate `new_body.md` containing consensus ledger comment Markdown.
   - Write `action_plan.json` containing `comment_action` (`POST`, `PATCH`, or `NONE`), `existing_comment_id`, `to_add`, and `to_remove`.

**Decisions:** D4, D5, D6, D7, D8, D9, D10.
**Acceptance:** AT-291-4, AT-291-5, AT-291-6, AT-291-7, AT-291-8.
**Done when:** `scripts/ci/review_recorder.py` exists as an executable script and produces valid `action_plan.json` and `new_body.md` when invoked standalone.

## T3 · Shell entrypoint refactoring and fail-closed hold circuit breaker

Touch: `scripts/ci/review_recorder.sh`

1. Replace the embedded Python heredoc in `scripts/ci/review_recorder.sh:86-594` with:
   ```bash
   python3 "$REPO/scripts/ci/review_recorder.py" "$PR" "$REPO" "$PR_JSON" "$WORKDIR" "$RECORDER_LOGIN"
   ```
2. Refactor hold probing logic in both preflight Guard 2 and write-time Guard 2 to fail closed on API errors (Argus R1-3, D1, D2), while treating non-issue numbers scraped from PR body/branch as "not held" with a logged note (Argus R1-2, D2):
   - Preflight Guard 2 (`scripts/ci/review_recorder.sh:57-72`):
     ```bash
     for iss in $ALL_LINKED; do
       if ! iss_json="$(gh issue view "$iss" --json labels 2>&1)"; then
         if echo "$iss_json" | grep -Eiq "could not resolve to an issue|not found|404"; then
           echo "note: #$iss is not an issue, treating as not held"
         else
           echo "error: failed to probe hold status on #$iss; recorder aborts to fail closed" >&2
           exit 1
         fi
       elif echo "$iss_json" | jq -e '.labels[]? | select(.name == "hold")' >/dev/null 2>&1; then
         echo "hold present on #$iss, recorder writes nothing"
         exit 0
       fi
     done
     ```
   - Write-time Guard 2 (`scripts/ci/review_recorder.sh:607-622`):
     ```bash
     if ! PR_LATEST_JSON="$(gh pr view "$PR" --json number,headRefName,labels,closingIssuesReferences,body 2>&1)"; then
       echo "error: failed to probe hold status on #$PR at write time; recorder aborts to fail closed" >&2
       exit 1
     fi
     if echo "$PR_LATEST_JSON" | jq -e '.labels[]? | select(.name == "hold")' >/dev/null 2>&1; then
       echo "hold present on #$PR, recorder writes nothing"
       exit 0
     fi
     ALL_LINKED_LATEST="$(get_linked_issues "$PR_LATEST_JSON")"
     for iss in $ALL_LINKED_LATEST; do
       if ! iss_json="$(gh issue view "$iss" --json labels 2>&1)"; then
         if echo "$iss_json" | grep -Eiq "could not resolve to an issue|not found|404"; then
           echo "note: #$iss is not an issue, treating as not held"
         else
           echo "error: failed to probe hold status on #$iss at write time; recorder aborts to fail closed" >&2
           exit 1
         fi
       elif echo "$iss_json" | jq -e '.labels[]? | select(.name == "hold")' >/dev/null 2>&1; then
         echo "hold present on #$iss, recorder writes nothing"
         exit 0
       fi
     done
     ```
3. Maintain the contiguous write sequence executing `COMMENT_ACTION` and `gh issue edit` immediately following the write-time re-read in the shell entrypoint (governed by D1 write-time guard placement, narrowing D8 write execution per Advisor V-2).

**Decisions:** D1, D2, D3, D8, D10.
**Acceptance:** AT-291-1, AT-291-2, AT-291-3, AT-291-8, AT-291-9, AT-291-11, AT-291-12.
**Done when:** `scripts/ci/review_recorder.sh` delegates to `review_recorder.py` and fails closed on hold probe errors; all 17 test cases in `scripts/ci/tests/review_recorder_test.sh` turn green.

## T4 · Living spec updates and cross-reference documentation

Touch: `docs/SPEC.md`, `intent/267-severity-tiered-merge-gate-review-md/spec.md`, `intent/291-recorder-hold-parity/spec.md`

1. Update `docs/SPEC.md`:
   - Under `### review.policy`: document write-time hold re-read parity (#25 D13/D14), fail-closed hold probing, finding ID attribution in failure scenario demotions (`on <id>`), withdrawn/dispute demotion exemptions, and round funnel historical suggestion preservation.
   - Under `### loop.autonomous`: document extraction of consensus recorder engine to `scripts/ci/review_recorder.py`.
2. Add amendment cross-reference in `intent/267-severity-tiered-merge-gate-review-md/spec.md`:
   - Note that #291 amends #267 D1, D5, D6, D8 to establish hold write-time parity, fail-closed probing, demotion finding ID attribution, withdrawn/dispute exemptions, and Python engine extraction.
3. In `intent/291-recorder-hold-parity/spec.md`:
   - Ensure Acceptance section reflects `AT-291-1` through `AT-291-12` with observable re-read, fail-closed probe assertions, and non-issue reference handling.
   - Fix drifted line pointers for `REVIEW.md:119-122` and `REVIEW.md:166-168` (Argus R1-4).

**Decisions:** D1, D4, D5, D6, D7, D8, D9, D10.
**Acceptance:** AT-291-10.
**Done when:** `docs/SPEC.md` reflects implemented behavior, and `bash scripts/ci/spec_check.sh origin/main <pr-body-file>` passes with exit code 0.

## T5 · Verification suite execution and clean gates check

Touch: (none)

1. Run verification suite from repository root:
   - `bash scripts/ci/tests/review_recorder_test.sh` (all 17 tests pass, exit 0).
   - `bash scripts/ci/tests/merge_gate_test.sh` (all scenarios pass, exit 0).
   - `python3 scripts/sync_agents.py --check` (clean, 0 drift, exit 0).
   - `bash scripts/ci/compiler_roundtrip.sh` (roundtrip clean, exit 0).
   - `bash scripts/ci/sanitize_check.sh` (PASS, exit 0).
   - `bash scripts/ci/spec_check.sh origin/main <pr-body-file>` (PASS, exit 0).

**Decisions:** D1..D10.
**Acceptance:** AT-291-1..AT-291-12.
**Done when:** All six verification commands exit 0.

## Commutability

- **T1** is committed first by Daedalus (Build stage), establishing the red contract test gate.
- **T2** (Python engine) and **T3** (shell wrapper) can be implemented together in the Implement stage. T3 depends on T2 to execute the standalone script.
- **T4** (Living spec and cross-references) commutes with T2 and T3.
- **T5** depends on completion of T2, T3, and T4.

## Gates table

Commands to run from the root of the tree:

| # | Command | Expected | Proves |
|---|---|---|---|
| 1 | `bash scripts/ci/tests/review_recorder_test.sh` | exit 0 | AT-291-1..AT-291-9, AT-291-11 |
| 2 | `bash scripts/ci/tests/merge_gate_test.sh` | exit 0 | merge gate consensus ledger compatibility |
| 3 | `python3 scripts/sync_agents.py --check` | exit 0 | compiler drift check |
| 4 | `bash scripts/ci/compiler_roundtrip.sh` | exit 0 | compiler roundtrip integrity |
| 5 | `bash scripts/ci/sanitize_check.sh` | exit 0, `PASS` | repository cleanliness |
| 6 | `bash scripts/ci/spec_check.sh origin/main <body-file>` | exit 0 | AT-291-10, living spec obligation |

Done when: All six verification commands exit 0.

## NOT RUN list

None. All 16 contract test cases in `scripts/ci/tests/review_recorder_test.sh` execute hermetically under the test fixture environment without live network calls.

## Reconciliation of review and advisor items carried from PR #309

1. **AT namespace collision (smoke N-1):**
   Disambiguated acceptance test identifiers across `spec.md`, `plan.md`, and `scripts/ci/tests/review_recorder_test.sh` by using namespace `AT-291-1` through `AT-291-11`. Existing #267 test citations (`AT-1` through `AT-18`) in `review_recorder_test.sh` remain distinct.
2. **AT-9 observable restatement (smoke N-2):**
   Restated AT-291-9 from static text inspection into an observable behavioral test (`test_write_time_hold_reread`). The test fixture dynamically flips `hold` after action plan derivation, asserting that the write-time re-read halts execution, logs `hold present on #114, recorder writes nothing`, and produces zero writes.
3. **Fail-open hold probe (Argus R1-3):**
   Addressed in P3, T1, and T3 by requiring the recorder to fail closed when `gh pr view` or `gh issue view` returns non-zero during hold probing. Proven by contract test `test_hold_probe_fail_closed` (AT-291-11).
4. **#267 D7 versus REVIEW.md:275:**
   Reconciled in P4. `#267 D7` wins for ledger recording: peer agreement is not a tracked state machine transition for non-security rows (`high`, `normal`, `suggestion`), which carry `peer=none` unless explicitly disputed. Cosmetic line pointer drift in `REVIEW.md` (`REVIEW.md:119-122`, `REVIEW.md:166-168`) is corrected in T4.
