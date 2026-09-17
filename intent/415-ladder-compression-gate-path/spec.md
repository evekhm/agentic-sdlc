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
   Issue #407 was created carrying only `intent:new`. The merge gate (`merge_gate.sh:227`, `:425-428`) defaulted an issue with only `intent:new` to `idx=0` (rung 1, `status:planning`, which owes `intent.md`). Because PR #409 was a compressed code implementation, no `intent/407-*/intent.md` existed at `$HEAD`. Conjunct 9 failed closed with (quotation with substitution: double hyphen replaces the em dash in `merge_gate.sh:534`):
   ```text
   conjunct (9): false -- expected exactly one intent/407-*/ folder at 7627557120c37407027fdef4330c3be018c1beac, found: none
   ```
   When the operator manually updated issue #407 to `status:implementing`, conjunct 9 (`status:implementing owes no artifact`) and conjunct 10 (`rung 4 > highest merged rung 0`) passed. However, `.github/workflows/merge-gate.yml` does not trigger on label events, requiring a manual `workflow_dispatch` to merge.

2. **Post-Merge Advancer Stall (`scripts/ci/lifecycle_advance.sh`)**:
   Following the merge of PR #409 to `main`, `lifecycle_advance.sh` ran to advance the issue. Line 406 executed (quotation with substitution: double hyphen replaces the em dash in `lifecycle_advance.sh:407`):
   ```bash
   intent_folders "$resolved"
   if [ "${FOLDER_N[$resolved]}" -eq 0 ]; then
       log "    pull request #$pr_number names #$resolved, which has no intent/$resolved-*/ directory at ${AFTER:0:12} -- no merge candidate"
       continue
   fi
   ```
   Because compressed issue #407 had no `intent/407-*/` directory, `FOLDER_N` was 0. `lifecycle_advance.sh` silently discarded PR #409 as a merge candidate. The transition from `status:implementing` to `status:in-review` never fired, and the `in-progress` label was never deleted, leaving issue #407 stranded holding a mutex slot until cleared by hand.

### Prior Art and Shipped Fast-Track Door (#444, PR #447)

Commit `6bbca26` (PR #447, resolving #444) shipped the operator fast-track door, introducing:
- `scripts/ops/fast.sh` and command `.claude/commands/fast.md` (`/fast <issue>`).
- Protocol skill `personas/skills/fast-track.md`.
- `AGENTS.md:380-387` ("Owner-authorized ladder compression: the fast-track door").
- `docs/SPEC.md:1128-1136` (`ops.fast_track`).

The shipped fast-track door formalizes maintainer authorization capture, verifies caller permissions, transitions the issue directly to `status:implementing` (clearing `intent:new`), runs preflight checks, and mandates the PR body header:
`Owner-authorized ladder compression: combines intent/spec/plan/implement into one round (Refs #<n>)`

What remained open and unresolved after #447:
1. `scripts/ci/lifecycle_advance.sh:405-410` still unconditionally discards pull requests for issues with zero `intent/<n>-*/` directories, causing the post-merge advancer stall on every compressed PR.
2. The merge gate and lifecycle advancer lacked hermetic contract test coverage protecting the zero-folder compressed path and its fail-closed defenses.
3. Living documentation in `docs/SPEC.md` and `AGENTS.md` required updates describing the zero-folder candidate admission and discriminator rules in `lifecycle_advance.sh`.

This change completes the ladder compression lifecycle:
1. Formalizes the policy that owner-authorized ladder compression is executed via maintainer pre-application of `status:implementing` on the issue (clearing `intent:new`), as automated by `/fast` and `scripts/ops/fast.sh`.
2. Preserves fail-closed evaluation in `scripts/ci/merge_gate.sh`: an issue carrying only `intent:new` missing intermediate artifacts fails conjunct 9; an issue carrying `status:implementing` owes no artifact and passes conjuncts 9 and 10.
3. Amends candidate discovery in `scripts/ci/lifecycle_advance.sh`: when discovering implementing pull requests, an issue with zero `intent/<n>-*/` directories in `$AFTER` is evaluated using the mandatory header discriminator `Owner-authorized ladder compression: combines intent/spec/plan/implement into one round (Refs #<n>)`. If the header is present and the PR touches files outside `intent/`, the PR is admitted as a provisional candidate and participates in standard later-merge-wins ranking. In the per-issue loop: if the issue sits at `status:implementing`, it advances to `status:in-review`, emits the transition comment naming the merged PR, and deletes the `in-progress` label. If the header is missing, the PR is rejected as an implementation candidate and recorded as a near miss under D17.
4. Preserves current event triggers in `.github/workflows/merge-gate.yml` (`check_suite: [completed]`, `issue_comment: [created]`, `workflow_dispatch`; `status` was removed under #308 D3), avoiding noisy label webhooks and documenting standard PR comment re-gating.
5. Adds hermetic contract test coverage across `merge_gate_test.sh` and `lifecycle_advance_test.sh`.
6. Upserts `docs/SPEC.md`, `AGENTS.md`, and `CHANGELOG.md` in place per repository living spec and changelog discipline.

### Manifest of Files Touched by the Implementation Rung (Odyssey)

- `scripts/ci/lifecycle_advance.sh`: Zero-folder candidate admission with header discriminator and candidate ranking.
- `scripts/ci/tests/lifecycle_advance_test.sh`: Hermetic contract test scenarios for compressed merges, zero-folder transitions, and missing-header near misses.
- `scripts/ci/tests/merge_gate_test.sh`: Hermetic contract test scenarios for pre-labeled compressed gating and fail-closed defense.
- `docs/SPEC.md`: Living spec upserts under `ops.fast_track` and `ci.lifecycle`.
- `AGENTS.md`: Update `### Owner-authorized ladder compression: the fast-track door` documenting advancer zero-folder candidate handling.
- `CHANGELOG.md`: Record lifecycle advancer zero-folder candidate handling and test coverage additions, satisfying `scripts/ci/changelog_check.sh`.
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
- `scripts/ops/fast.sh` (shipped under #447, unchanged).

## Decisions

| ID | Decision | Rationale |
|---|---|---|
| **D1** | **Definition, Scope, and Authority of Owner-Authorized Ladder Compression.** Owner-authorized ladder compression is the deliberate skipping of intermediate ladder rungs (`plan`, `design`, or `build`) to deliver code directly in a single pull request at the `implement` rung. Authority to compress the ladder belongs **exclusively** to authenticated human repository owners and maintainers. Autonomous agents (`athena`, `daedalus`, `odyssey`, `argus`, `atlas`, `themis`) NEVER possess unilateral authority to compress the ladder, skip rungs, or bypass required artifacts. The operator fast-track door (`scripts/ops/fast.sh`, `/fast`, shipped in #447) is the designated mechanism executing maintainer authorization to transition an issue directly to `status:implementing`. Consistent with the repository principle that "the labels are the state machine", the presence of `status:implementing` and absence of `intent:new` represents this authorization to CI gates. Autonomous bot self-authorization policies remain open for future exploration per `AGENTS.md:383` and `docs/SPEC.md:1130`. | Autonomous agents must not have authority to declare their own exemptions or bypass specification gates. Tying gate admission to the verified issue label state set by maintainer-authenticated tooling (`fast.sh`) ensures fail-closed defense while enabling owner-directed velocity. |
| **D2** | **Merge Gate Evaluation for Compressed Issues (Conjuncts 9 & 10).** In `scripts/ci/merge_gate.sh`: (1) When an issue carries `status:implementing` (`idx=3`, `RUNG=4`), `ARTIFACT` evaluates to empty string (`""`); under line 436, conjunct 9 evaluates to `true` (`C[9]=1`, `WHY[9]="status:implementing owes no artifact"`). (2) In conjunct 10, when no prior ladder pull requests have merged for the issue (`HIGHEST_MERGED_RANK=0`), `RUNG` (4) is compared against `HIGHEST_MERGED_RANK` (0): `4 > 0` evaluates to `true` (`C[10]=1`, `WHY[10]="rung 4 > highest merged rung 0"`). If an implementation PR has already merged for this issue (`HIGHEST_MERGED_RANK >= 4`), conjunct 10 evaluates to `false` (`rung 4 is not above highest merged rung $HIGHEST_MERGED_RANK (D14)`). (3) **Fail-Closed Invariant**: If an issue carries only `intent:new` (and no `status:*` label), `merge_gate.sh` resolves `idx=0` (rung 1, `status:planning`, artifact `intent.md`). If `intent/$dirs/intent.md` is absent at `$HEAD`, conjunct 9 MUST evaluate to `false` (`expected exactly one intent/$ISSUE-*/ folder at $HEAD, found: none`). The gate NEVER infers ladder compression from PR branch names, diff contents, or PR body markers when the issue remains at `intent:new`. | Retains strict monotonicity (D14 of #64). The mathematical formulation of conjuncts 9 and 10 in `merge_gate.sh` already handles multi-rung jumps correctly when the issue carries `status:implementing`. Failing closed on `intent:new` ensures that unapproved or uncoordinated PRs cannot merge without proper artifacts. |
| **D3** | **Lifecycle Advancer Candidate Discovery and Header Discriminator for Zero-Folder Compressed Issues.** In `scripts/ci/lifecycle_advance.sh`, amend the implementing pull request candidate check (lines 405-410). When a merged pull request in `$BEFORE..$AFTER` has head branch parsing as `^([a-z][a-z-]*)/0*([0-9]+)-(.+)$` (yielding `<actor>`, `<resolved>`, `<slug>`) and touches at least one path outside `intent/`: (1) **Single-Folder Candidate**: If exactly one directory `intent/$resolved-*/` exists in `$AFTER`, `<slug>` must match that folder's slug exactly (normal ladder flow, D15 conjunct 3). If slug mismatches, record a near miss under D17. (2) **Multi-Folder Corrupted State**: If more than one directory `intent/$resolved-*/` exists in `$AFTER`, record a counted failure (`corrupted state`, D15 conjunct 3). (3) **Zero-Folder Compressed Candidate with Header Discriminator**: If **zero** directories `intent/$resolved-*/` exist in `$AFTER`, `lifecycle_advance.sh` inspects the pull request body for the mandatory header mandated by `AGENTS.md:385`, `docs/SPEC.md:1132`, and `scripts/ops/fast.sh:290`: `Owner-authorized ladder compression: combines intent/spec/plan/implement into one round (Refs #<n>)` where `<n>` equals `$resolved`. If the header is present and the PR touches files outside `intent/`, the pull request is admitted as a provisional candidate for `$resolved`. If the header is absent, the PR is NOT an authorized compression candidate: it is recorded as a near miss (`NEAR_MISS[$resolved]`, `n_near=$((n_near + 1))`), logging that the zero-folder PR on branch `$pr_head` lacks the owner-authorized compression header. (4) **Candidate Ranking and Advancer Transition**: An admitted zero-folder candidate participates in later-merge-wins ranking identical to standard candidates (`lines 465-474`): if a later candidate exists in the range, the later merge wins. In the subsequent per-issue loop (`lines 488+`): if issue `$resolved` is currently labeled `status:implementing` (`advances_on: "merge"`), the advancer executes the transition to `status:in-review`, emits the transition comment naming the merged PR, and deletes the `in-progress` label. If issue `$resolved` carries any other label (e.g. `intent:new`, `status:planning`, `status:spec`, or `status:build`), the PR yields no transition, logging that the issue is not at the merge rung. | Resolves Argus R1-1 and prevents arbitrary branches naming the issue number from spoofing implementation delivery. Requiring the standardized owner-authorized compression header ensures that only authorized fast-track pull requests can advance zero-folder issues, while maintaining standard candidate ranking and near-miss accounting. |
| **D4** | **Workflow Trigger Policy and Re-Gating Protocol.** (1) Event triggers in `.github/workflows/merge-gate.yml` remain strictly: `check_suite: [completed]`, `issue_comment: [created]`, and `workflow_dispatch` (concurring with #308 D3, which removed the dead `status` trigger). We do NOT add `issues: [labeled]` or `pull_request: [labeled]` triggers. (2) **Operational Standard**: When directing ladder compression, the owner/operator applies `status:implementing` (and clears `intent:new`) before reviewer verdicts and CI checks complete (as automated by `/fast` and `fast.sh`). Normal reviewer comments (`issue_comment`) and CI completion (`check_suite`) will naturally fire `merge-gate.yml` and evaluate with the status label already present. (3) **Repair Re-Gating**: If an operator applies `status:implementing` to an issue after all PR checks and reviews have already completed, the operator or reviewer triggers re-evaluation simply by posting any comment on the pull request thread (e.g. `re-gate`), which triggers `issue_comment: [created]`, or via manual `workflow_dispatch`. | Resolves Argus R1-3 and R2-1. Reconciles with #308 D3, which removed the dead status trigger and its STATUS_SHA resolution. Adding `issues: [labeled]` triggers would cause excessive, wasteful Actions runs across every label mutation on all repository issues, and GitHub issue label webhook payloads lack pull request context. Pull request comments are already isolated per-PR by workflow concurrency (D1 of #308) and provide an immediate, zero-overhead re-trigger mechanism. |
| **D5** | **Artifact Optionality and Required Header in Compressed Implementation PRs.** In an owner-authorized ladder compression round: (1) The PR is NOT required to create `intent/<issue>-<slug>/` or commit `intent.md`, `spec.md`, or `plan.md`. (2) All architectural contracts, behavior modifications, and living spec updates MUST be committed to `docs/SPEC.md` within the implementing PR, compliant with AGENTS.md living spec discipline. (3) The PR body MUST contain the exact header specified in `AGENTS.md:385` and `docs/SPEC.md:1132`: `Owner-authorized ladder compression: combines intent/spec/plan/implement into one round (Refs #<n>)` where `<n>` is the issue number. (4) If a compressed PR optionally chooses to commit an `intent/<issue>-<slug>/` folder (e.g. summarizing intent and spec), it is accepted provided exactly one such folder exists in `$AFTER` and its slug matches the branch slug. | Resolves Argus R1-2 item 3. Cites the exact header established in #447. An owner-directed fast-track change does not require redundant intermediate documentation artifacts when `docs/SPEC.md` serves as the authoritative source of truth. |
| **D6** | **Hermetic Contract Test Coverage.** Hermetic contract tests must be implemented in both CI test suites: (1) In `scripts/ci/tests/merge_gate_test.sh`: test scenario verifying an issue labeled `status:implementing` with zero `intent/` folders passes conjunct 9 and conjunct 10 and merges; test scenario verifying an issue carrying only `intent:new` without `intent.md` fails conjunct 9 fail-closed; test scenario verifying monotonicity refusal when `status:implementing` has already merged (`HIGHEST_MERGED_RANK >= 4`). (2) In `scripts/ci/tests/lifecycle_advance_test.sh`: test scenario verifying a merged PR on `odyssey/<n>-<slug>` carrying the header `Owner-authorized ladder compression: combines intent/spec/plan/implement into one round (Refs #<n>)` for an issue at `status:implementing` with zero `intent/<n>-*/` folders advances to `status:in-review` and deletes `in-progress`; test scenario verifying a zero-folder merged PR where the issue is at `intent:new` or `status:planning` produces no transition; test scenario verifying a zero-folder merged PR on `odyssey/<n>-<slug>` touching files outside `intent/` that lacks the `Owner-authorized ladder compression:` header does NOT advance the issue and is recorded as a near miss. | Resolves Argus R1-1. Ensures comprehensive hermetic regression testing of ladder compression across both the merge gate and the lifecycle advancer without network dependencies or live GitHub API tokens. |
| **D7** | **Living Spec, Operational Playbook, and Changelog Updates.** The implementing pull request (Odyssey) will upsert: (1) `docs/SPEC.md` under `ops.fast_track` and `ci.lifecycle`: documenting zero-folder candidate admission, the header discriminator requirement, and post-merge lifecycle advance to `status:in-review`. (2) `AGENTS.md` under `### Owner-authorized ladder compression: the fast-track door`: documenting that `lifecycle_advance.sh` recognizes zero-folder PRs carrying the required header and advances them to `status:in-review`. (3) `CHANGELOG.md`: recording the lifecycle advancer zero-folder candidate handling and test additions under the appropriate date section, satisfying `scripts/ci/changelog_check.sh`. Athena touches only `intent/415-ladder-compression-gate-path/**` at this DESIGN stage. | Resolves Argus R1-2 and R1-4. Reconciles with the fast-track documentation already shipped in #447 without creating duplicate sections, and satisfies changelog obligations. |

## Acceptance

- **AT-1 (D1, D2)** In `scripts/ci/tests/merge_gate_test.sh`, a pull request for an issue pre-labeled `status:implementing` (and no `intent:new`) with zero `intent/<issue>-*/` directories in the repository passes conjunct 9 (`status:implementing owes no artifact`), passes conjunct 10 (`rung 4 > highest merged rung 0`), and merges autonomously upon clean reviewer consensus and green CI checks.
- **AT-2 (D1, D2)** In `scripts/ci/tests/merge_gate_test.sh`, a pull request for an issue carrying only `intent:new` with zero `intent/<issue>-*/` directories at `$HEAD` fails conjunct 9 fail-closed (`expected exactly one intent/$ISSUE-*/ folder at $HEAD, found: none`), and the merge gate does not merge.
- **AT-3 (D2)** In `scripts/ci/tests/merge_gate_test.sh`, a pull request for an issue carrying `status:implementing` where the loop ledger already records a merged rung at or above rung 4 (`HIGHEST_MERGED_RANK >= 4`) fails conjunct 10 (`rung 4 is not above highest merged rung $HIGHEST_MERGED_RANK (D14)`), preventing duplicate or regressive implementation merges.
- **AT-4 (D3, D5)** In `scripts/ci/tests/lifecycle_advance_test.sh`, a commit range containing a merged pull request on branch `odyssey/<n>-<slug>` carrying the header `Owner-authorized ladder compression: combines intent/spec/plan/implement into one round (Refs #<n>)` and touching files outside `intent/` for an issue sitting at `status:implementing` with zero `intent/<n>-*/` directories in `$AFTER` advances the issue to `status:in-review`, emits the lifecycle advance comment naming the pull request, and deletes the `in-progress` label.
- **AT-5 (D3)** In `scripts/ci/tests/lifecycle_advance_test.sh`, a commit range containing a merged pull request on branch `odyssey/<n>-<slug>` with zero `intent/<n>-*/` directories in `$AFTER` where issue `<n>` is at `status:planning` or carries only `intent:new` yields zero transitions and does not advance the issue.
- **AT-6 (D3)** In `scripts/ci/tests/lifecycle_advance_test.sh`, a commit range containing a merged pull request on branch `odyssey/<n>-<slug>` touching files outside `intent/` with zero `intent/<n>-*/` directories in `$AFTER` that lacks the `Owner-authorized ladder compression:` header yields zero transitions, does not advance issue `<n>`, and is recorded as a near miss.
- **AT-7 (D3)** In `scripts/ci/tests/lifecycle_advance_test.sh`, a commit range containing a merged pull request on branch `odyssey/<n>-<slug>` where issue `<n>` has more than one `intent/<n>-*/` directory in `$AFTER` fails as corrupted state.
- **AT-8 (D4)** In `.github/workflows/merge-gate.yml`, event triggers are verified to contain `check_suite: [completed]`, `issue_comment: [created]`, and `workflow_dispatch` (omitting `status` per #308 D3), and omit `issues: [labeled]` and `pull_request: [labeled]`.
- **AT-9 (D5, D7)** In `docs/SPEC.md` and `AGENTS.md`, living spec entries under `ops.fast_track` and `ci.lifecycle` and tracker instructions under AGENTS.md document owner-authorized ladder compression zero-folder advancer candidate handling; verified mechanically via `grep -F "### Owner-authorized ladder compression: the fast-track door" AGENTS.md`, `grep -F "### ops.fast_track" docs/SPEC.md`, `grep -F "zero-folder" docs/SPEC.md`, and `bash scripts/ci/spec_check.sh origin/main <pr-description-file>` passing with exit code 0.

## Concerns

- **Risk of autonomous stage skipping**: If bots could declare compression, the verification gates of the SDLC would be eroded. Decision D1 eliminates this risk by tying compression strictly to issue label state, which only human maintainers can set outside the automated ladder.
- **Zombie concurrency locks**: When `lifecycle_advance.sh` skipped candidate PRs due to `FOLDER_N == 0`, issues remained at `status:implementing` with `in-progress` held, blocking the poller's intake slots. Decision D3 guarantees that zero-folder compressed PRs advance to `status:in-review` and delete `in-progress`.
- **Workflow event storms**: Gating on label webhooks would trigger unnecessary runs for every claim, hold, or triage action. Retaining comment triggers (D4) avoids event storms while providing a seamless re-gate path.

## Out of scope

- Modifying `personas/lifecycle.json` or changing the canonical ladder definition.
- Modifying `scripts/ci/review_recorder.sh` or reviewer consensus rules.
- Modifying `scripts/ops/work.sh` or `scripts/ops/claim.sh`.
- Intake CLI command enhancements (e.g. `--stage implement` flag on `/work` or `/idea`), which are tracked under issue #407 / #416.
- Modifying `scripts/ops/fast.sh` (shipped and verified under #444/#447).

## Operator decisions

None required.

## Open questions

none
