# Spec: Owner-Authorized Ladder Compression Gate Path and Lifecycle Advance

**Issue:** #415 · **Status:** Approved (approval = merge of this PR) · **Author:** athena (`evekhm-athena-app[bot]`) · **Open questions:** none

## What is being built

This specification resolves issue #415 by establishing an explicit, fail-closed gate and advancement path for **Owner-Authorized Ladder Compression** across `scripts/ci/merge_gate.sh`, `scripts/ci/lifecycle_advance.sh`, `docs/SPEC.md`, and `AGENTS.md`.

### Context and Incident Analysis

Under the autonomous software development lifecycle (`AGENTS.md`, `personas/lifecycle.json`, `docs/SPEC.md`), issues normally traverse five sequential rungs:
1. `plan` (`status:planning`, artifact: `intent.md`, owner: Athena)
2. `design` (`status:spec`, artifact: `spec.md`, owner: Athena)
3. `build` (`status:build`, artifact: `plan.md`, owner: Daedalus)
4. `implement` (`status:implementing`, artifact: null / code diff outside `intent/`, owner: Odyssey)
5. `review` (`status:in-review`, artifact: null / reviewer consensus verdicts, owners: Argus & Atlas)

During the interactive development of issue #407, the repository owner explicitly authorized bypassing the three intermediate artifact PRs (`intent.md`, `spec.md`, `plan.md`) and opening a single implementing pull request (PR #409). Although PR #409 achieved full reviewer consensus (`consensus:agreed`, `review:merge-ready`) and passed all CI checks (`mergeStateStatus: CLEAN`), it encountered two compounding automation failures:

1. **Pre-Merge Gate Stall (`scripts/ci/merge_gate.sh`)**:
   Issue #407 was created carrying only `intent:new`. The merge gate (`merge_gate.sh:227`, `:425-428`) defaulted an issue with only `intent:new` to `idx=0` (rung 1, `status:planning`, which owes `intent.md`). Because PR #409 was a compressed code implementation, no `intent/407-*/intent.md` existed at `$HEAD`. Conjunct 9 failed closed with:
   ```text
   conjunct (9): false — expected exactly one intent/407-*/ folder at 7627557120c37407027fdef4330c3be018c1beac, found: none
   ```
   When the operator manually updated issue #407 to `status:implementing`, conjunct 9 (`status:implementing owes no artifact`) and conjunct 10 (`rung 4 > highest merged rung 0`) passed. However, `.github/workflows/merge-gate.yml` does not trigger on label events, requiring a manual `workflow_dispatch` to merge.

2. **Post-Merge Advancer Stall (`scripts/ci/lifecycle_advance.sh`)**:
   Following the merge of PR #409 to `main`, `lifecycle_advance.sh` ran to advance the issue. Line 405 executed:
   ```bash
   intent_folders "$resolved"
   if [ "${FOLDER_N[$resolved]}" -eq 0 ]; then
       log "    pull request #$pr_number names #$resolved, which has no intent/$resolved-*/ directory at ${AFTER:0:12} — no merge candidate"
       continue
   fi
   ```
   Because compressed issue #407 had no `intent/407-*/` directory, `FOLDER_N` was 0. `lifecycle_advance.sh` silently discarded PR #409 as a merge candidate. The transition from `status:implementing` to `status:in-review` never fired, and the `in-progress` label was never deleted, leaving issue #407 stranded holding a mutex slot until cleared by hand.

This change:
1. Formalizes the policy that owner-authorized ladder compression is authorized strictly via maintainer pre-application of the target status label (`status:implementing`) on the issue (clearing `intent:new`).
2. Preserves fail-closed evaluation in `scripts/ci/merge_gate.sh`: an issue carrying only `intent:new` missing intermediate artifacts fails conjunct 9; an issue carrying `status:implementing` owes no artifact and passes conjuncts 9 and 10.
3. Amends candidate discovery in `scripts/ci/lifecycle_advance.sh`: when discovering implementing pull requests, an issue with zero `intent/<n>-*/` directories is provisionally admitted as a candidate; in the per-issue loop, if the issue's current status is `status:implementing`, it cleanly advances to `status:in-review`, emits the transition comment naming the merged PR, and deletes the `in-progress` label.
4. Preserves current event triggers in `.github/workflows/merge-gate.yml`, avoiding noisy label webhooks and documenting standard PR comment re-gating.
5. Adds hermetic contract test coverage across `merge_gate_test.sh` and `lifecycle_advance_test.sh`.
6. Upserts `docs/SPEC.md` and `AGENTS.md` in place per repository living spec discipline.

### Manifest of Files Touched by the Implementation Rung (Odyssey)

- `scripts/ci/lifecycle_advance.sh`: Zero-folder candidate admission for implementing pull requests.
- `scripts/ci/tests/lifecycle_advance_test.sh`: Hermetic contract test scenarios for compressed merges.
- `scripts/ci/tests/merge_gate_test.sh`: Hermetic contract test scenarios for pre-labeled compressed gating and fail-closed defense.
- `docs/SPEC.md`: Living spec upserts under `lifecycle.labels` and `ci.merge-gate`.
- `AGENTS.md`: Operational policy and procedure for owner-authorized ladder compression.
- `intent/415-ladder-compression-gate-path/plan.md`: Ordered implementation plan authored by Daedalus.

### Manifest of Files Touched by this PR (Athena)

- `intent/415-ladder-compression-gate-path/spec.md`: This specification.

### Forbidden Files (Untouched)

- `personas/lifecycle.json` (canonical ladder definition is unchanged).
- `personas/**` (no persona sources, briefs, or schemas modified).
- `.github/workflows/merge-gate.yml` (triggers and concurrency unchanged).
- `.github/workflows/lifecycle.yml` (push trigger and permissions unchanged).
- `scripts/ci/review_recorder.sh` / `scripts/ci/review_recorder.py`.
- `scripts/ops/work.sh` / `scripts/ops/claim.sh`.

## Decisions

| ID | Decision | Rationale |
|---|---|---|
| **D1** | **Definition, Scope, and Authority of Owner-Authorized Ladder Compression.** Owner-authorized ladder compression is the deliberate skipping of intermediate ladder rungs (`plan`, `design`, or `build`) to deliver code directly in a single pull request at the `implement` rung. Authority to compress the ladder belongs **exclusively** to authenticated human repository owners and maintainers. Autonomous agents (`athena`, `daedalus`, `odyssey`, `argus`, `atlas`, `themis`) NEVER possess unilateral authority to compress the ladder, skip rungs, or bypass required artifacts. Consistent with the repository's foundational principle that "the labels are the state machine", the sole authorized representation of ladder compression on an issue is the explicit presence of the target status label (e.g. `status:implementing`) and the absence of `intent:new`. | Autonomous agents must not have authority to declare their own exemptions or bypass specification gates. Because only human maintainers (or maintainer-invoked intake tooling with maintainer credentials) can write labels to GitHub issues outside deterministic CI automation, an issue labeled `status:implementing` without prior merged ladder artifacts constitutes authentic, verifiable, fail-closed proof of owner authorization. |
| **D2** | **Merge Gate Evaluation for Compressed Issues (Conjuncts 9 & 10).** In `scripts/ci/merge_gate.sh`: (1) When an issue carries `status:implementing` (`idx=3`, `RUNG=4`), `ARTIFACT` evaluates to empty string (`""`); under line 436, conjunct 9 evaluates to `true` (`C[9]=1`, `WHY[9]="status:implementing owes no artifact"`). (2) In conjunct 10, when no prior ladder pull requests have merged for the issue (`HIGHEST_MERGED_RANK=0`), `RUNG` (4) is compared against `HIGHEST_MERGED_RANK` (0): `4 > 0` evaluates to `true` (`C[10]=1`, `WHY[10]="rung 4 > highest merged rung 0"`). If an implementation PR has already merged for this issue (`HIGHEST_MERGED_RANK >= 4`), conjunct 10 evaluates to `false` (`rung 4 is not above highest merged rung $HIGHEST_MERGED_RANK (D14)`). (3) **Fail-Closed Invariant**: If an issue carries only `intent:new` (and no `status:*` label), `merge_gate.sh` resolves `idx=0` (rung 1, `status:planning`, artifact `intent.md`). If `intent/$dirs/intent.md` is absent at `$HEAD`, conjunct 9 MUST evaluate to `false` (`expected exactly one intent/$ISSUE-*/ folder at $HEAD, found: none`). The gate NEVER infers ladder compression from PR branch names, diff contents, or PR body markers when the issue remains at `intent:new`. | Retains strict monotonicity (D14 of #64). The mathematical formulation of conjuncts 9 and 10 in `merge_gate.sh` already handles multi-rung jumps correctly when the issue carries `status:implementing`. Failing closed on `intent:new` ensures that unapproved or uncoordinated PRs cannot merge without proper artifacts. |
| **D3** | **Lifecycle Advancer Candidate Discovery for Zero-Folder Compressed Issues.** In `scripts/ci/lifecycle_advance.sh`, amend the implementing pull request candidate check (lines 405–410). When a merged pull request in `$BEFORE..$AFTER` has head branch parsing as `^([a-z][a-z-]*)/0*([0-9]+)-(.+)$` (yielding `<actor>`, `<resolved>`, `<slug>`) and touches at least one path outside `intent/`: (1) If exactly one directory `intent/$resolved-*/` exists in `$AFTER`, `<slug>` must match that folder's slug exactly (normal ladder flow, D15 conjunct 3). (2) If more than one directory `intent/$resolved-*/` exists in `$AFTER`, record a counted failure (`corrupted state`, D15 conjunct 3). (3) **Zero-Folder Compressed Candidate**: If **zero** directories `intent/$resolved-*/` exist in `$AFTER`, `lifecycle_advance.sh` does NOT skip the pull request with `no merge candidate`. Instead, the PR is admitted as a provisional candidate for `$resolved`. In the subsequent per-issue loop: if issue `$resolved` is currently labeled `status:implementing` (`advances_on: "merge"`), the advancer executes the transition to `status:in-review`, emits the transition comment naming the merged PR, and deletes the `in-progress` label. If issue `$resolved` carries any other label (e.g. `intent:new`, `status:planning`, `status:spec`, or `status:build`), the PR yields no transition, logging that the issue is not at the merge rung. | Resolves Root Cause 4. The previous assumption that any issue reaching `status:implementing` MUST have created an `intent/<issue>-*/` folder in a prior rung is invalidated by ladder compression. Admitting zero-folder PRs provisionally and validating that the issue sits at `status:implementing` enables `lifecycle_advance.sh` to advance the stage and release the claim mutex, eliminating stranded issues and zombie concurrency locks. |
| **D4** | **Workflow Trigger Policy and Re-Gating Protocol.** (1) Event triggers in `.github/workflows/merge-gate.yml` remain strictly: `check_suite: [completed]`, `issue_comment: [created]`, and `workflow_dispatch`. We do NOT add `issues: [labeled]` or `pull_request: [labeled]` triggers. (2) **Operational Standard**: When directing ladder compression, the owner/operator applies `status:implementing` (and clears `intent:new`) before reviewer verdicts and CI checks complete. Normal reviewer comments (`issue_comment`) and CI completion (`check_suite`) will naturally fire `merge-gate.yml` and evaluate with the status label already present. (3) **Repair Re-Gating**: If an operator applies `status:implementing` to an issue after all PR checks and reviews have already completed, the operator or reviewer triggers re-evaluation simply by posting any comment on the pull request thread (e.g. `re-gate`), which triggers `issue_comment: [created]`, or via manual `workflow_dispatch`. | Adding `issues: [labeled]` triggers would cause excessive, wasteful Actions runs across every label mutation on all repository issues, and GitHub issue label webhook payloads lack pull request context. Pull request comments are already isolated per-PR by workflow concurrency (D1 of #308) and provide an immediate, zero-overhead re-trigger mechanism. |
| **D5** | **Artifact Optionality in Compressed Implementation PRs.** In an owner-authorized ladder compression round: (1) The PR is NOT required to create `intent/<issue>-<slug>/` or commit `intent.md`, `spec.md`, or `plan.md`. (2) All architectural contracts, behavior modifications, and living spec updates MUST be committed to `docs/SPEC.md` within the implementing PR, compliant with AGENTS.md living spec discipline. (3) The PR body must state that the round is an owner-authorized compression. (4) If a compressed PR optionally chooses to commit an `intent/<issue>-<slug>/` folder (e.g. summarizing intent and spec), it is accepted provided exactly one such folder exists in `$AFTER` and its slug matches the branch slug. | An owner-directed fast-track change does not require redundant intermediate documentation artifacts when `docs/SPEC.md` serves as the authoritative source of truth. Permitting both zero folders and one folder provides operational flexibility while maintaining rigorous validation. |
| **D6** | **Hermetic Contract Test Coverage.** Hermetic contract tests must be implemented in both CI test suites: (1) In `scripts/ci/tests/merge_gate_test.sh`: test scenario verifying an issue labeled `status:implementing` with zero `intent/` folders passes conjunct 9 and conjunct 10 and merges; test scenario verifying an issue carrying only `intent:new` without `intent.md` fails conjunct 9 fail-closed; test scenario verifying monotonicity refusal when `status:implementing` has already merged (`HIGHEST_MERGED_RANK >= 4`). (2) In `scripts/ci/tests/lifecycle_advance_test.sh`: test scenario verifying a merged PR on `odyssey/<n>-<slug>` for an issue at `status:implementing` with zero `intent/<n>-*/` folders advances to `status:in-review` and deletes `in-progress`; test scenario verifying a zero-folder merged PR where the issue is at `intent:new` or `status:planning` produces no transition. | Ensures hermetic regression testing of ladder compression across both the merge gate and the lifecycle advancer without network dependencies or live GitHub API tokens. |
| **D7** | **Living Spec and Operational Playbook Updates.** The implementing pull request (Odyssey) will upsert: (1) `docs/SPEC.md` under `ci.merge-gate` and `lifecycle.labels`: documenting owner-authorized ladder compression, the pre-applied status label mechanism, zero-folder advancer candidate admission, and fail-closed gate evaluation. (2) `AGENTS.md` under "Working the tracker": adding an explicit "Owner-Authorized Ladder Compression" subsection detailing the operator procedure for setting `status:implementing` and clearing `intent:new`. Athena touches only `intent/415-ladder-compression-gate-path/**` at this DESIGN stage. | Maintains complete living documentation in compliance with AGENTS.md and respects persona path authority bounds. |

## Acceptance

- **AT-1 (D1, D2)** In `scripts/ci/tests/merge_gate_test.sh`, a pull request for an issue pre-labeled `status:implementing` (and no `intent:new`) with zero `intent/<issue>-*/` directories in the repository passes conjunct 9 (`status:implementing owes no artifact`), passes conjunct 10 (`rung 4 > highest merged rung 0`), and merges autonomously upon clean reviewer consensus and green CI checks.
- **AT-2 (D1, D2)** In `scripts/ci/tests/merge_gate_test.sh`, a pull request for an issue carrying only `intent:new` with zero `intent/<issue>-*/` directories at `$HEAD` fails conjunct 9 fail-closed (`expected exactly one intent/$ISSUE-*/ folder at $HEAD, found: none`), and the merge gate does not merge.
- **AT-3 (D2)** In `scripts/ci/tests/merge_gate_test.sh`, a pull request for an issue carrying `status:implementing` where the loop ledger already records a merged rung at or above rung 4 (`HIGHEST_MERGED_RANK >= 4`) fails conjunct 10 (`rung 4 is not above highest merged rung $HIGHEST_MERGED_RANK (D14)`), preventing duplicate or regressive implementation merges.
- **AT-4 (D3)** In `scripts/ci/tests/lifecycle_advance_test.sh`, a commit range containing a merged pull request on branch `odyssey/<n>-<slug>` touching files outside `intent/` for an issue sitting at `status:implementing` with zero `intent/<n>-*/` directories in `$AFTER` advances the issue to `status:in-review`, emits the lifecycle advance comment naming the pull request, and deletes the `in-progress` label.
- **AT-5 (D3)** In `scripts/ci/tests/lifecycle_advance_test.sh`, a commit range containing a merged pull request on branch `odyssey/<n>-<slug>` with zero `intent/<n>-*/` directories in `$AFTER` where issue `<n>` is at `status:planning` or carries only `intent:new` yields zero transitions and does not advance the issue.
- **AT-6 (D3)** In `scripts/ci/tests/lifecycle_advance_test.sh`, a commit range containing a merged pull request on branch `odyssey/<n>-<slug>` where issue `<n>` has more than one `intent/<n>-*/` directory in `$AFTER` fails as corrupted state.
- **AT-7 (D4)** In `.github/workflows/merge-gate.yml`, event triggers are verified to contain `check_suite: [completed]`, `issue_comment: [created]`, and `workflow_dispatch`, and omit `issues: [labeled]` and `pull_request: [labeled]`.
- **AT-8 (D5, D7)** In `docs/SPEC.md` and `AGENTS.md`, living spec entries under `lifecycle.labels` and `ci.merge-gate` and tracker instructions under AGENTS.md document owner-authorized ladder compression, pre-applied status labels, and zero-folder advancer handling; `bash scripts/ci/spec_check.sh origin/main <pr-description-file>` passes with exit code 0.

## Concerns

- **Risk of autonomous stage skipping**: If bots could declare compression, the verification gates of the SDLC would be eroded. Decision D1 eliminates this risk by tying compression strictly to issue label state, which only human maintainers can set outside the automated ladder.
- **Zombie concurrency locks**: When `lifecycle_advance.sh` skipped candidate PRs due to `FOLDER_N == 0`, issues remained at `status:implementing` with `in-progress` held, blocking the poller's intake slots. Decision D3 guarantees that zero-folder compressed PRs advance to `status:in-review` and delete `in-progress`.
- **Workflow event storms**: Gating on label webhooks would trigger unnecessary runs for every claim, hold, or triage action. Retaining comment triggers (D4) avoids event storms while providing a seamless re-gate path.

## Out of scope

- Modifying `personas/lifecycle.json` or changing the canonical ladder definition.
- Modifying `scripts/ci/review_recorder.sh` or reviewer consensus rules.
- Modifying `scripts/ops/work.sh` or `scripts/ops/claim.sh`.
- Intake CLI command enhancements (e.g. `--stage implement` flag on `/work` or `/idea`), which are tracked under issue #407 / #416.

## Operator decisions

None required.

## Open questions

none
