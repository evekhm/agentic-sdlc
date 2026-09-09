# Plan: Severity-tiered review recorder and consensus ledger

**Issue:** #267 · **Spec:** spec.md (Approved, D1-D12, AT-1..AT-18) · **Author:** daedalus (`evekhm-daedalus-app[bot]`)

Eight tasks. Each names the files it touches, the steps in order, the Decision rows it implements, the acceptance tests it makes pass, and its done-when. **Implement on top of `origin/main` at the SHA the dispatcher pins; this plan was verified at `9d81c76b1127ff8a997821e441e6fa2b010cae29`.** Every `file:line` below was re-read at that commit.

Order: T1 (contract tests, all red) → T2 (review protocol and compiled personas) → T3 (label taxonomy) → T4 (merge gate updates) → T5 (review recorder implementation) → T6 (workflow integration) → T7 (living spec updates) → T8 (gates).

## Branch slug notice

The current build rung branch is `daedalus/267-severity-recorder-plan`. The implementation rung head branch MUST be `odyssey/267-severity-tiered-merge-gate-review-md` matching the intent folder slug. This allows `scripts/ci/lifecycle_advance.sh` to advance the issue lifecycle to `status:implementing`.

## The calls this plan makes

**P1 · Consensus ledger bridge and gate sequencing:** The recorder executes in `.github/workflows/merge-gate.yml` inside a new `record` job placed prior to the `gate` job (`gate` declares `needs: [record]`). Both jobs run under `environment: themis` and share concurrency group `merge-gate`. On review and push events, `record` re-derives the ledger and updates the single consensus ledger comment in place. The `record` job runs under condition `if: github.event_name != 'pull_request' && (github.event_name != 'issue_comment' || github.event.issue.pull_request)` and uses the same per-event TARGET resolution as `gate` (`merge-gate.yml:123-135`). An empty target logs an informative message and exits 0.

**P2 · Review protocol structured blocks and closed high list:** Reviewers emit structured verdict blocks containing verdict, head commit OID, Actions run ID, round number, finding tuples, and failure scenario markers. Clean reviews emit zero finding rows between round and verdict trailer (AT-R1-6). High findings require an immediate sibling `failure-scenario` marker; findings lacking this marker are demoted mechanically to `normal` with an audit note. Evaluating whether high findings belong to the closed list in `REVIEW.md:102-111` is a reviewer duty documented in `personas/skills/review-protocol.md`.

**P3 · Severity enum alignment and regex update:** The severity enum is standardized to `security`, `high`, `normal`, `suggestion`, replacing legacy `low` across `scripts/ci/merge_gate.sh:28,271` and `scripts/ci/tests/merge_gate_test.sh`. Finding IDs support Decision citations using `@<Dn>` tags matching character class `[A-Za-z0-9@-]` with hyphen placed last to guarantee shell compatibility.

**P4 · Single consensus ledger comment lifecycle and wire format:** The consensus ledger is maintained as exactly one comment per pull request authored by Themis (`evekhm-themis-app[bot]`). Initial creation uses `POST`; subsequent updates use `PATCH` in place. Emitted ledger format matches `scripts/ci/merge_gate.sh:265-271` and includes `<!-- assigned:argus,atlas -->` immediately following `<!-- consensus-ledger:<pr> -->` per #265 interface design.

**P5 · Provenance verification and marker withdrawal:** Actions run IDs are validated against authentic runs of `.github/workflows/unattended.yml` matching the pull request head SHA, repo, and actor. On `check_suite: completed` re-derivation, if a cited run finished as `failure` or `cancelled`, the recorder withdraws the verdict: the reviewer head marker reverts to the previous accepted head without deleting the line, and `[run <n> ended <conclusion>; verdict withdrawn]` is appended to the ledger (Argus R3-1).

**P6 · Label taxonomy and authority boundaries:** Labels derived from ledger state (`argus:findings`, `argus:suggestions`, `consensus:*`, `review:merge-ready`, `review:verifying`, and `review:1..3`) synchronize via `gh issue edit`. Maintainer retier commands (`@argus retier <id> <severity>`) verify `author_association` in `OWNER, MEMBER, COLLABORATOR` to avoid requiring `administration:read` permissions under Themis (Atlas AT-R1-2).

## T1 · The failing contract test suite

Touch: `scripts/ci/tests/review_recorder_test.sh`

1. Deliver hermetic test suite `scripts/ci/tests/review_recorder_test.sh` modeled after `scripts/ci/tests/merge_gate_test.sh`.
2. Implement argument parsing supporting `-k <filter>` and `--filter <filter>` to select individual scenarios.
3. Stub external tools (`claude`, `gemini`, `agy`, `curl`) to fail if invoked. Stub `gh` to intercept reads and record writes under `$WRITES`, supporting flag forms `--input <file>`, `-F body=@<file>`, `--field body=@<file>`, `-f body=<text>`, and `--body-file <file>`.
4. Implement 13 test scenarios covering the 14 acceptance criteria:
   - `test_marker_parsing` (AT-2, D2, D10)
   - `test_provenance_validation` (AT-3, D2, D3)
   - `test_ledger_comment_lifecycle` (AT-4, D1, D4)
   - `test_high_failure_scenario_demotion` (AT-5, D5)
   - `test_non_enum_severity_refusal` (AT-6, D5)
   - `test_round_funnel` (AT-7, D6)
   - `test_security_dual_agreement` (AT-8, D7)
   - `test_owner_retier` (AT-9, D9)
   - `test_label_sync` (AT-10, D5, D7, D8)
   - `test_merge_gate_round_trip` (AT-13, D4, D5)
   - `test_atlas_carry_forward` (AT-16, D4, D7)
   - `test_provenance_workflow_dispatch` (AT-17, D3)
   - `test_wire_format_assigned` (AT-18, D4)
5. Contract tests execute against `scripts/ci/review_recorder.sh`. Tests are committed RED at base because `scripts/ci/review_recorder.sh` does not exist yet. Other acceptance criteria are checked separately: AT-11 via the regex one-liner and `merge_gate_test.sh`, AT-12 during provisioning, AT-14 during live execution (NOT RUN), and AT-15 via `spec_check.sh` and `sanitize_check.sh`.

**Decisions:** D1, D2, D3, D4, D5, D6, D7, D8, D9, D10.
**Acceptance:** AT-1, AT-2, AT-3, AT-4, AT-5, AT-6, AT-7, AT-8, AT-9, AT-10, AT-13, AT-16, AT-17, AT-18.
**Done when:** Test suite runs locally via `bash scripts/ci/tests/review_recorder_test.sh` and reports 13 failed tests out of 13 run due to missing implementation script.

## T2 · Review protocol and compiled persona updates

Touch: `REVIEW.md`, `personas/skills/review-protocol.md`, `.claude/**`, `.agents/**`

Review protocol changes carry risk of reviewer instruction drift if compiler sync is skipped.

1. **`REVIEW.md`**:
   - Update severity table and definitions around lines 79-100 to document `suggestion` as the authoritative non-defect improvement tier, eliminating legacy references to `low`.
   - Update structured comment block specifications around lines 200-245:
     ```markdown
     <!-- review-verdict:<reviewer>:<verdict> -->
     <!-- reviewed-head:<full-oid> -->
     <!-- run-id:<n> -->
     <!-- round:<n> -->
     <!-- finding:<id>:<severity>:<status>:<peer> -->
     <!-- failure-scenario:<id> -->
     <!-- review-verdict-end -->
     ```
   - Specify that clean reviews emit zero `<!-- finding:... -->` lines between round and verdict trailer.
   - Document that findings citing spec decisions use format `<id>@<Dn>` (or `<id>@none`), matching lines 290-305.
   - Document maintainer retier command `@argus retier <id> <severity>` and `@atlas retier <id> <severity>`.
2. **`personas/skills/review-protocol.md`**:
   - Instruct Argus and Atlas reviewer personas to output the structured review verdict block in review comments alongside markdown tables.
   - Instruct reviewers to enforce the closed high list from `REVIEW.md:102-111` and emit sibling `<!-- failure-scenario:<id> -->` markers for high findings.
3. **Recompile persona targets**:
   - Run `python3 scripts/sync_agents.py` to regenerate compiled agent files under `.claude/agents/` and `.agents/agents/` (AT-R1-3).
   - Verify compiler clean check via `python3 scripts/sync_agents.py --check`.

**Decisions:** D2, D5, D6, D7, D9, D12.
**Acceptance:** AT-2, AT-5, AT-6, AT-7, AT-8, AT-9, AT-15.
**Done when:** `REVIEW.md` and `personas/skills/review-protocol.md` are updated, and `python3 scripts/sync_agents.py --check` passes with zero drift.

## T3 · Label taxonomy provisioning

Touch: `scripts/setup/bootstrap_tracker.sh`

1. **`scripts/setup/bootstrap_tracker.sh`**:
   - Add `ensure_label` invocations in `bootstrap_tracker.sh` around lines 102-124 for the seven review and consensus labels named in AT-12:
     - `argus:findings` (`#d93f0b`): Open blocking findings (security or high) on the pull request
     - `argus:suggestions` (`#c5def5`): Open non-blocking findings (normal or suggestion) on the pull request
     - `consensus:agreed` (`#0e8a16`): All security findings agreed and no disputes on blocking rows
     - `consensus:pending` (`#fbca04`): Security findings awaiting peer review concurrence
     - `consensus:disputed` (`#b60205`): Active dispute on one or more blocking findings
     - `review:merge-ready` (`#0e8a16`): No open blocking findings, consensus agreed, reviewed at current head
     - `review:verifying` (`#1d76db`): Open blocking findings exist and pull request head is newer than reviewed head
   - Round labels `review:1` through `review:3` already exist at `bootstrap_tracker.sh:121-124` and remain untouched.
2. Support `--labels-only` invocation for dry-run and provisioning verification.

**Decisions:** D8, D12.
**Acceptance:** AT-10, AT-12.
**Done when:** `scripts/setup/bootstrap_tracker.sh` provisions the seven labels and AT-12 is supported under `--labels-only`.

## T4 · Merge gate severity enum and regex update

Touch: `scripts/ci/merge_gate.sh`, `scripts/ci/tests/merge_gate_test.sh`

1. **`scripts/ci/merge_gate.sh`**:
   - Update line 28 comment: `row = id:severity:status:peer row tuple, severity in security|high|normal|suggestion`.
   - Update line 271 regex from:
     `^<!-- ledger-row:([A-Za-z0-9-]+:(security|high|normal|low):(open|fixed|withdrawn):(pending|agree|dispute|none)) -->$`
     to:
     `^<!-- ledger-row:([A-Za-z0-9@-]+:(security|high|normal|suggestion):(open|fixed|withdrawn):(pending|agree|dispute|none)) -->$`.
2. **`scripts/ci/tests/merge_gate_test.sh`**:
   - Update `consensus_ledger` helper at `scripts/ci/tests/merge_gate_test.sh:236-243` to emit `<!-- assigned:argus,atlas -->` directly after `<!-- consensus-ledger:$pr -->`, ensuring `merge_gate.sh` parses it cleanly.
   - Update `consensus_ledger` helper to accommodate `@<Dn>` tags and `suggestion`.
   - Update scenario MG-13e at `scripts/ci/tests/merge_gate_test.sh:527` to verify refusal of legacy `low`.
   - Add scenario asserting acceptance of `suggestion` and Decision-tagged IDs (`R1-1@D4`).

**Decisions:** D4, D5, D12.
**Acceptance:** AT-11, AT-13, AT-18.
**Done when:** Pattern test in AT-11 passes and `bash scripts/ci/tests/merge_gate_test.sh` passes all scenarios.

## T5 · Consensus ledger recorder implementation

Touch: `scripts/ci/review_recorder.sh`

Concurrency between multiple webhook events requires careful state ordering and atomic writes.

1. Create `scripts/ci/review_recorder.sh` with executable permissions (`chmod +x`).
2. Implement invocation contract: accepts `<pr-number>` argument, respects `DRY_RUN` environment variable, reads repository context.
3. Validate sender and event triggers:
   - Skip execution when `github.event.sender.login` equals `evekhm-themis-app[bot]` to prevent self-trigger cycles.
4. Implement comment pagination and extraction:
   - Fetch comments via `gh api repos/<repo>/issues/<pr>/comments`.
   - Identify existing consensus ledger comment authored by Themis.
   - Ignore unformatted human comments and bot comments lacking structured blocks without error (D10).
   - Filter and parse structured review verdict blocks from authorized reviewer logins (`evekhm-argus-app[bot]`, `evekhm-atlas-app[bot]`).
5. Implement provenance validation:
   - Query `gh api repos/<repo>/actions/runs/<run_id>` for cited run IDs.
   - Verify head SHA matches pull request commits, workflow is `.github/workflows/unattended.yml`, repo is this repository, and event is `pull_request` or `workflow_dispatch`.
   - On `check_suite: completed` events, if conclusion is `failure` or `cancelled`, withdraw the verdict: revert that reviewer's head marker to the previous accepted head, record table note `[run <n> ended <conclusion>; verdict withdrawn]`, and never delete the line.
6. Implement severity validation and round funnel rules:
   - Validate severity against `security`, `high`, `normal`, `suggestion`.
   - Loud refusal for invalid severities: log error, append table note `[refused: <id>: invalid severity <x>]`, create no ledger row, exit 0.
   - High findings without sibling `<!-- failure-scenario:<id> -->` are demoted to `normal` with table note `[demoted from high: missing failure_scenario marker]`.
   - Round funnel enforcement: Round 1 admits all tiers. Rounds 2-3 admit new findings at security or high; new non-blocking observations create `normal` tracking rows owing no verdict. Past round 3, admit only security findings; demote any other filing to `normal`.
7. Implement security dual agreement and status transitions:
   - Security rows require peer concurrence on finding existence (`agree`) and on fix verification (`fixed:agree`) before leaving the blocking set.
   - Atlas carry-forward: preserve Atlas last accepted head marker across newer commits.
8. Implement maintainer retier verb:
   - Parse `@argus retier <id> <severity>` and `@atlas retier <id> <severity>`.
   - Check commenter `author_association` in `OWNER, MEMBER, COLLABORATOR`.
   - Update finding severity in row and table with audit note `[retiered to <severity> by @<user>]`.
9. Format and emit ledger:
   - Header: `### Findings ledger for #<pr>`
   - Markers:
     `<!-- consensus-ledger:<pr> -->`
     `<!-- assigned:argus,atlas -->`
     `<!-- reviewed-head:argus:<oid> -->`
     `<!-- reviewed-head:atlas:<oid> -->`
     `<!-- ledger-row:<id>:<severity>:<status>:<peer> -->`
     `<!-- consensus-ledger-end -->`
     followed by markdown table and notes.
10. Update ledger comment:
    - If comment unchanged byte for byte, skip API write.
    - If ledger comment exists, update via `gh api -X PATCH repos/<repo>/issues/comments/<id> -F body=@<file>`.
    - If absent, create via `gh api -X POST repos/<repo>/issues/<pr>/comments -F body=@<file>`.
11. Synchronize labels:
    - Read current labels via `gh issue view <pr> --json labels`.
    - Calculate derived labels (`argus:findings`, `argus:suggestions`, `consensus:*`, `review:merge-ready`, `review:verifying`, `review:1..3`).
    - Reconcile derived labels on each execution, adding required labels and removing stale labels while preserving unrelated issue labels such as `bootstrap` (spec.md:163-164).
    - Apply updates via `gh issue edit <pr> --add-label ... --remove-label ...`.

**Decisions:** D1, D2, D3, D4, D5, D6, D7, D8, D9, D10, D11, D12.
**Acceptance:** AT-1, AT-2, AT-3, AT-4, AT-5, AT-6, AT-7, AT-8, AT-9, AT-10, AT-13, AT-16, AT-17, AT-18.
**Done when:** All scenarios in `scripts/ci/tests/review_recorder_test.sh` turn green.

## T6 · Merge gate workflow integration

Touch: `.github/workflows/merge-gate.yml`

Workflow modifications must avoid unintended trigger amplification across concurrent events.

1. Update workflow triggers to match all five events:
   - `pull_request` (types: `[opened, synchronize, reopened]`)
   - `issue_comment` (types: `[created]`)
   - `check_suite` (types: `[completed]`)
   - `status`
   - `workflow_dispatch`
2. Add dedicated `record` job before `gate` job:
   - Environment: `themis`
   - Concurrency group: `merge-gate`
   - Condition: `if: github.event_name != 'pull_request' && (github.event_name != 'issue_comment' || github.event.issue.pull_request)`
   - TARGET resolution: resolve TARGET using the identical per-event logic as `gate` (`merge-gate.yml:123-135`). If TARGET is empty, log an informative message and exit 0.
   - Mint Themis App installation token via `actions/create-github-app-token`.
   - Re-read `hold` on the pull request and on every issue the pull request closes immediately before the first write; with `hold` present anywhere in that set, write nothing, log one line naming the held object, and exit 0 (#291, REVIEW.md D13/D14).
   - Run `bash scripts/ci/review_recorder.sh "$TARGET"`.
3. Update `gate` job dependencies:
   - Set `needs: [record]` only.
   - Ensure `gate` executes evaluation against updated ledger state.

**Decisions:** D1, D12.
**Acceptance:** AT-1, AT-14.
**Done when:** `.github/workflows/merge-gate.yml` validates syntactically, runs `record` before `gate`, and passes workflow checks.

## T7 · Living spec documentation updates

Touch: `docs/SPEC.md`

1. Update `### review.policy` around line 434:
   - Upsert description of structured review verdict blocks, failure scenario sibling markers, mechanical demotion of high findings, authoritative four-tier enum (`security`, `high`, `normal`, `suggestion`), round admissibility funnel, and maintainer retier commands.
2. Update `### lifecycle.labels` around line 290:
   - Document review and consensus label taxonomy derived by Themis: `argus:findings`, `argus:suggestions`, `consensus:*`, `review:merge-ready`, `review:verifying`, and round indicators `review:1..3`.
3. Update `### loop.autonomous` around line 953:
   - Document consensus ledger recorder placement in `merge-gate.yml`, single in-place comment lifecycle, Actions run provenance verification, and marker withdrawal rules.

**Decisions:** D10, D12.
**Acceptance:** AT-15.
**Done when:** `docs/SPEC.md` reflects implemented behavior and `bash scripts/ci/spec_check.sh origin/main <pr-body-file>` passes with exit code 0.

## T8 · Gates check and test verification

Touch: (none; contract tests run in no CI workflow at this rung, tracked by #246)

1. Contract tests are verified locally and run in no CI workflow at this rung. Adding them to CI workflows is tracked under issue #246.
2. Execute the verification suite locally from the repository root:
   - `bash scripts/ci/tests/review_recorder_test.sh`
   - `bash scripts/ci/tests/merge_gate_test.sh`
   - `python3 scripts/sync_agents.py --check`
   - `bash scripts/ci/compiler_roundtrip.sh`
   - `bash scripts/ci/sanitize_check.sh`
   - `bash scripts/ci/spec_check.sh origin/main <body-file>`

**Decisions:** D1, D5, D8, D10, D12.
**Acceptance:** AT-1, AT-11, AT-15.
**Done when:** All specified local check scripts pass.

## Commutability

- **T2, T3, T4** touch disjoint file sets and can be implemented in parallel or in arbitrary sequence.
  - T2 touches review protocol documents and compiled persona targets.
  - T3 touches label definitions and tracker setup scripts.
  - T4 touches merge gate parsing and merge gate tests.
- **T5** depends on T3 (label taxonomy) and T4 (severity enum format).
- **T6** depends on T5 (`review_recorder.sh` existing).
- **T7** depends on T5 and T6 to document finalized behaviors.
- **T8** depends on completion of all preceding tasks.

## Gates table

Commands to run from the root of the tree:

| # | Command | Expected | Proves |
|---|---|---|---|
| 1 | `bash scripts/ci/tests/review_recorder_test.sh` | exit 0 | AT-1..AT-10, AT-13, AT-16..AT-18 |
| 2 | `printf '%s\n' '<!-- ledger-row:R1-1@D4:high:open:none -->' \| sed -nE 's/^<!-- ledger-row:([A-Za-z0-9@-]+:(security\|high\|normal\|suggestion):(open\|fixed\|withdrawn):(pending\|agree\|dispute\|none)) -->$/OK[\1]/p'` | `OK[R1-1@D4:high:open:none]` | AT-11 regex compatibility |
| 3 | `bash scripts/ci/tests/merge_gate_test.sh` | exit 0 | AT-11, AT-13, AT-18 |
| 4 | `python3 scripts/sync_agents.py --check` | exit 0 | AT-15, compiler drift check |
| 5 | `bash scripts/ci/compiler_roundtrip.sh` | exit 0 | compiler roundtrip integrity |
| 6 | `bash scripts/ci/sanitize_check.sh` | exit 0, `PASS` | repository cleanliness |
| 7 | `bash scripts/ci/spec_check.sh origin/main <body-file>` | exit 0 | AT-15, living spec obligation |

Done when: All seven verification commands exit 0.

## NOT RUN list

- **AT-12 (D8):** `bash scripts/setup/bootstrap_tracker.sh --labels-only` requires repository write access to provision GitHub labels. Moved to NOT RUN for local test runs until deployment or provisioning execution.
- **AT-14 (D4):** Live execution of `Merge Gate` workflow on an Actions runner evaluating conjuncts 3, 4, 5, and 11 as true, cited by Actions run ID. Listed under NOT RUN until issue #64 acceptance 20, because executing live Actions runs requires real pull request merge events on GitHub infrastructure.

## Corrections

Round 1 review and smoke review findings addressed in Round 2:

- **R1-1 / AT-R1-1 (D2 comment format):** Standardized review verdict structured blocks to use `<!-- review-verdict:<reviewer>:<verdict> -->` and `<!-- reviewed-head:<oid> -->`, eliminating the obsolete `reviewer:` opener.
- **R1-2 / AT-R1-3 (D3 Actions run provenance):** Added workflow path and head repository verification to test fixtures; split provenance validation into an accepting case and four specific refusal checks; added marker withdrawal scenarios on failed or cancelled workflow runs.
- **R1-3 / AT-R1-5 (D4 merge gate round-trip):** Invoked `scripts/ci/merge_gate.sh` directly within the test suite under hermetic stubs, asserting conjuncts 3, 4, 5, 11 and WHY[3] carry-forward text.
- **R1-4 / AT-R1-6.2 (D7 security dual agreement):** Added negative tests ensuring author cannot self-agree on security findings, and unauthenticated comments claiming fixes are ignored.
- **R1-5 (D8 label synchronization):** Added assertions that label synchronization preserves unrelated labels such as `hold` while updating `review:1..3`. Restored label preservation clause in plan T5.11 verbatim from `spec.md:160-164`.
- **R1-6 / AT-R1-6.1 (D6 round funnel):** Added test fixtures for rounds 2, 3, and 4 verifying non-blocking normal tracking rows, high finding admission in round 3, and demotion beyond round 3.
- **R1-7 / Smoke blocking 2 (D12 CI gates workflow):** Dropped `.github/workflows/ci-gates.yml` from T8; documented that contract tests run in no CI workflow at this rung, tracked under issue #246.
- **R1-8 / Smoke blocking 3 (D8 label provisioning):** Scoped T3 label provisioning to the seven labels named in AT-12; noted that `review:1..3` exist in `bootstrap_tracker.sh` and are untouched; moved AT-12 to NOT RUN.
- **R1-9 (D1 single comment lifecycle):** Implemented skip guard when sender is Themis, and byte-identical PATCH suppression.
- **R1-10 (D10 unformatted comments):** Added scenario mixing unformatted human and bot comments with structured review blocks, ensuring graceful handling without error. Added D10 to T1 decisions.
- **R1-11 (D5 suggestions and D7 disputes):** Verified suggestion, dispute, and withdrawn rows through the parse-to-ledger path.
- **R1-12 (gh stub flag handling):** Expanded stub to support `--input <file>`, `-F body=@<file>`, `--field body=@<file>`, `-f body=<text>`, and `--body-file <file>`. Cites Decisions and Acceptance IDs in test failure output.
- **AT-R1-2 (D9 maintainer retier):** Retier authorization verifies `author_association` in `OWNER, MEMBER, COLLABORATOR`.
- **Smoke blocking 1 (T4 wire format):** Added step to T4 updating `consensus_ledger` in `merge_gate_test.sh:236-243` with `<!-- assigned:argus,atlas -->`.
- **Smoke blocking 4 (T6 target resolution and needs):** Updated T6 to set `needs: [record]` only, match per-event TARGET resolution from `gate`, and exit 0 on empty target.
- **Smoke non-blocking:** Deleted invalid line 273 error log message step in T4; corrected citation to `merge_gate_test.sh:527`; removed `[DEEP-n]` tags and replaced with risk sentences; added AT-11 sed one-liner to gates table; updated T1 done-when.
