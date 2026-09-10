# Spec: Mutable Finding Severity by Discovering Reviewer in Consensus Recorder

**Issue:** #361 · **Status:** Approved (approval = merge of this PR) ·
**Author:** athena (`evekhm-athena-app[bot]`) ·
**Open questions:** none

## What is being built

This specification resolves issue #361 by enabling discovering reviewers (`argus` and `atlas`) to update finding severity across review rounds in the Themis consensus recorder (`scripts/ci/review_recorder.py`).

### Background and Defect

Under the autonomous review architecture (`REVIEW.md`, #267, #291; `docs/SPEC.md:544-630`), pull request reviews run unattended rounds using independent reviewers (`argus` and `atlas`). Reviewers evaluate changes and post structured review verdict blocks containing finding lines:
```markdown
<!-- review-verdict:<reviewer>:<verdict> -->
<!-- reviewed-head:<full-oid> -->
<!-- run-id:<n> -->
<!-- round:<n> -->
<!-- finding:<id>:<severity>:<status>:<peer> -->
<!-- failure-scenario:<id> -->
<!-- review-verdict-end -->
```

The consensus recorder (`scripts/ci/review_recorder.py`) parses these comments, derives the authoritative consensus ledger comment (`<!-- consensus-ledger:<pr> -->`) authored by Themis (`evekhm-themis-app[bot]`), and synchronizes PR lifecycle review labels (`review:merge-ready`, `consensus:agreed`, etc.). The autonomous merge gate (`scripts/ci/merge_gate.sh`) evaluates conjunct 4: whether any `security` or `high` finding in the consensus ledger remains in an `open` status (`BLOCKING`).

In `scripts/ci/review_recorder.py`, finding severity is currently write-once from its initial observation:
1. Lines 118–135 seed the dictionary `rows` from existing `<!-- ledger-row:<fid>:<severity>:<status>:<peer> -->` markers in the ledger comment.
2. In Pass 2 (lines 277–363), when processing findings in accepted review verdict blocks, if an existing finding ID is re-encountered (`fid in rows`), the recorder updates `rows[fid]["status"] = fst`, but **never** updates `rows[fid]["severity"]`.
3. Consequently, if the discovering reviewer lowers the severity of a finding in a subsequent round (such as from `high` to `normal` after author explanations, fix commits, or re-scoping), the recorder ignores the new severity in the footer marker and preserves the original `high` severity indefinitely.
4. Because maintainer retier directives (`@argus retier <fid> <severity>`) are restricted to human non-bot maintainers (`review_recorder.py:267`: `user_type != "Bot"`), reviewer bots cannot emit retier directives to bypass this write-once freeze.

This defect manifested on PR #319 (implementing #265 review split):
- Argus round 2 recorded `finding:R2-1@D5:high:open:none`.
- In subsequent rounds 3, 4, and 5, Argus re-evaluated the defect as non-blocking and emitted `finding:R2-1@D5:normal:open:none`.
- The consensus ledger retained `<!-- ledger-row:R2-1@D5:high:open:none -->`, causing Actions merge gate run 34441378531 to fail on `conjunct (4): false — blocking set: R2-1@D5` despite both reviewers emitting clean/approve verdicts. Unblocking required a human collaborator to post `@argus retier R2-1@D5 normal` on the PR thread.

### The Solution

This specification defines ten numbered decisions governing severity mutability:
1. **Discoverer severity updates in review verdict blocks (D1)**: In Pass 2 of `scripts/ci/review_recorder.py`, when processing an accepted review verdict block for an existing finding ID (`fid in rows`), if `reviewer == discoverer`, `rows[fid]["severity"]` is updated to the stated severity (`fsev`), subject to funnel, failure-scenario, and security constraints.
2. **Round funnel rules for severity transitions across rounds (D2)**: Downward severity transitions (`high` -> `normal`, `high` -> `suggestion`, `normal` -> `suggestion`) are admissible in all review rounds (rounds 1, 2, 3, 4+). Upward transitions to `high` are admissible during initial and verification rounds (rounds 1, 2, 3). In round 4 or later (post-cap rounds, `effective_round >= 4`), any upward severity transition of an existing non-security finding to `high` is demoted to `normal` per `REVIEW.md:174-176`.
3. **Failure-scenario requirement for `high` severity findings (D3)**: Whenever a finding is re-encountered with or transitioned to `high` severity (`fsev == "high"`), it must be accompanied by a matching sibling failure-scenario marker (`<!-- failure-scenario:<id> -->`, evaluating base ID normalization per #354) within that review verdict block. If the sibling failure-scenario marker is absent, and the finding is neither `withdrawn` nor `dispute` (#291 D5), `fsev` is demoted to `normal` with audit note `[demoted from high: missing failure_scenario marker] on <fid>` and diagnostic logging to stdout before updating `rows[fid]["severity"]`.
4. **Security tier protection against unilateral footer downgrades (D4)**: An existing row whose recorded severity in the ledger is `security` (`rows[fid]["severity"] == "security"`) cannot be downgraded to a non-security tier (`high`, `normal`, `suggestion`) by a reviewer verdict block footer marker. If the discovering reviewer emits a non-security severity for an existing `security` row, the recorder ignores the footer severity change, preserves `rows[fid]["severity"] = "security"`, and logs a diagnostic message to stdout. Downgrading an existing `security` row requires an authorized human maintainer retier directive (`@<reviewer> retier <fid> <severity>`) under #291 D9. Conversely, if a discovering reviewer elevates an existing non-security finding to `security`, the row transitions to `severity = "security"` and `peer = "pending"`, requiring dual agreement.
5. **Peer reviewer non-interference (D5)**: When `fid in rows` and `reviewer != discoverer`, the peer reviewer cannot alter `rows[fid]["severity"]`. Any severity emitted by a peer reviewer on another reviewer's finding is strictly ignored by the recorder, preserving the existing row severity.
6. **Consensus ledger audit trail and execution logging (D6)**: When `rows[fid]["severity"]` is updated by the discovering reviewer from `old_sev` to `new_sev` (where `old_sev != new_sev`), the recorder appends an audit note to `audit_notes`: `[severity updated to {new_sev} by @{reviewer} on {fid}]`, and emits a diagnostic log line to stdout: `print(f"finding {fid}: severity updated from {old_sev} to {new_sev} by @{reviewer}")`. If `old_sev == new_sev`, no audit note is appended.
7. **Downstream merge gate conjunct 4 and label synchronization (D7)**: When a discovering reviewer downgrades a `high` finding to `normal` or `suggestion`, the consensus ledger records the row as `<!-- ledger-row:<fid>:normal:open:none -->`. The recorder clears the `argus:findings` label (if no other blocking rows remain open) and sets `review:merge-ready` (if consensus criteria are satisfied). Downstream in `scripts/ci/merge_gate.sh`, the row is omitted from `BLOCKING`, allowing conjunct 4 to evaluate true (`C[4]=1; WHY[4]="blocking set empty"`).
8. **Contract test coverage matrix in `scripts/ci/tests/review_recorder_test.sh` (D8)**: Expands `scripts/ci/tests/review_recorder_test.sh` with test cases verifying discoverer updates, gate unblocking, peer non-interference, failure-scenario demotions, security tier protections, and late-round funnel caps.
9. **Implementation scope boundary (D9)**: Confines code changes strictly to the recorder engine, test suite, protocol documentation, living spec, and lifecycle artifacts.
10. **Living specification synchronization (D10)**: Updates `docs/SPEC.md` under `review.policy` upon implementation.

### File Manifest

#### Touched by this PR (Athena · DESIGN stage)
```text
intent/361-review-recorder-severity-of-a-seen/spec.md   # this specification
intent/361-review-recorder-severity-of-a-seen/intent.md # intent artifact updated to Status: Accepted
```

#### Touched by Implementation (Daedalus / Odyssey · BUILD and IMPLEMENT stages)
```text
scripts/ci/review_recorder.py             # update rows[fid]["severity"] for discoverer in pass 2, enforce demotion/funnel/security guards, emit audit notes and logs
scripts/ci/tests/review_recorder_test.sh  # contract and regression tests for discoverer updates, peer non-interference, demotions, security guards, and gate unblocking
docs/SPEC.md                              # living spec update under review.policy
REVIEW.md                                 # protocol documentation update clarifying discoverer severity mutability
personas/skills/review-protocol.md        # protocol skill documentation update clarifying discoverer severity mutability
intent/361-review-recorder-severity-of-a-seen/plan.md   # build plan authored by Daedalus
```

#### Untouched Files (Forbidden)
```text
.github/workflows/**
scripts/ops/**
scripts/ci/merge_gate.sh
personas/** (excluding skills/review-protocol.md)
```

## Decisions

| ID | Decision | Rationale |
|---|---|---|
| **D1** | **Discoverer severity updates in review verdict blocks.** In Pass 2 of `scripts/ci/review_recorder.py`, when processing an accepted review verdict block for an existing finding ID (`fid in rows`), if `reviewer == discoverer`, the recorder updates `rows[fid]["severity"]` to the finding line's stated severity (`fsev`), subject to round-cap funnel constraints (D2), failure-scenario verification (D3), and security tier protection (D4). | Fixes the root cause identified in #361 (PR #319 R2-1@D5). Reviewers communicate updated assessments across rounds via structured footer markers (`REVIEW.md:252-254`). Enabling discovering reviewers to update their own finding severities ensures the consensus ledger synchronizes with reviewer verdicts, preventing false-positive gate failures. |
| **D2** | **Round funnel rules for severity transitions across rounds.** Downward severity transitions (`high` -> `normal`, `high` -> `suggestion`, `normal` -> `suggestion`) narrow blocking scope and are admissible across all review rounds (rounds 1, 2, 3, 4+). Upward transitions to `high` are admissible during initial and verification rounds (rounds 1, 2, 3). In round 4 or later (post-cap rounds, `effective_round >= 4`), any upward severity transition of an existing non-security finding to `high` is demoted to `normal` per `REVIEW.md:174-176` ("Past round 3 reviewers post verification comments only... The recorder demotes any other post-cap filing to normal."). | Enforces the round funnel bound (`REVIEW.md:189-191`), preventing reviewers from circumventing the round 3 cap by escalating existing findings into the blocking set in late verification rounds. Downward transitions are always permitted because they reduce blocking scope and accelerate convergence. |
| **D3** | **Failure-scenario requirement for `high` severity findings.** Whenever a finding is re-encountered with or transitioned to `high` severity (`fsev == "high"`), it must be accompanied by a matching sibling failure-scenario marker (`<!-- failure-scenario:<id> -->`, evaluating base ID normalization per #354) within that review verdict block. If the sibling failure-scenario marker is absent, and the finding is neither `withdrawn` nor `dispute` (#291 D5), `fsev` is demoted to `normal` with audit note `[demoted from high: missing failure_scenario marker] on <fid>` and diagnostic logging to stdout before updating `rows[fid]["severity"]`. | Enforces strict compliance with the failure-scenario protocol (`REVIEW.md:124-127`). Reviewers must prove concrete failure scenarios for all active `high` findings in every round they assert `high` severity. Omitting the marker automatically demotes the row to `normal`, preserving the integrity of the blocking tier. |
| **D4** | **Security tier protection against unilateral footer downgrades.** An existing row whose recorded severity in the ledger is `security` (`rows[fid]["severity"] == "security"`) cannot be downgraded to a non-security tier (`high`, `normal`, `suggestion`) by a reviewer's verdict block footer marker. If the discovering reviewer emits a non-security severity for an existing `security` row, the recorder ignores the footer severity change, preserves `rows[fid]["severity"] = "security"`, and logs a diagnostic message to stdout (`f"finding {fid}: footer severity change from security to {fsev} ignored; security rows require maintainer retier"`). Retiering an existing `security` finding to a non-security tier requires an authorized human maintainer retier directive (`@<reviewer> retier <fid> <severity>`) under #291 D9. Conversely, if a discovering reviewer elevates an existing non-security finding to `security`, the row transitions to `severity = "security"` and `peer = "pending"`, requiring dual agreement. | Preserves the strict dual-agreement invariant for security findings (`REVIEW.md:283-285`: "security rows always require both reviewers' explicit AGREE, twice: once on existence, once on the fix. This is the guardrail the funnel never relaxes."). Unilateral retraction or footer downgrade of a recorded security finding without human maintainer intervention would create a dangerous bypass of the security gate. |
| **D5** | **Peer reviewer non-interference.** When `fid in rows` and `reviewer != discoverer`, the peer reviewer cannot alter `rows[fid]["severity"]`. Any severity emitted by a peer reviewer on another reviewer's finding is strictly ignored by the recorder, preserving the existing row severity. Peer reviewers may only participate in consensus according to established protocol: recording dispute (`fpr == "dispute"`), and for `security` findings, recording concurrence (`agree`/`dispute`) or fix verification concurrence. | Upholds discoverer exclusivity and prevents peer reviewers from unilaterally overriding or tampering with each other's finding severities. Dispute and concurrence mechanisms exist separately on the peer axis. |
| **D6** | **Consensus ledger audit trail and execution logging.** When `rows[fid]["severity"]` is updated by the discovering reviewer from `old_sev` to `new_sev` (where `old_sev != new_sev`), the recorder: 1. Appends an audit note to `audit_notes`: `[severity updated to {new_sev} by @{reviewer} on {fid}]`. 2. Emits a diagnostic log line to stdout: `print(f"finding {fid}: severity updated from {old_sev} to {new_sev} by @{reviewer}")`. If `rows[fid]["severity"] == new_sev` (no change in severity across rounds), no audit note is appended. | Provides full audit visibility in the Themis consensus ledger table notes and GitHub Actions step logs. Transparently distinguishes reviewer-driven footer updates from human maintainer retier directives (`[retiered to <sev> by @<user>]`). |
| **D7** | **Downstream merge gate conjunct 4 and label synchronization.** When a discovering reviewer updates an open finding's severity from `high` to `normal` or `suggestion`, the consensus ledger records the row as `<!-- ledger-row:<fid>:normal:open:none -->`. The recorder clears the `argus:findings` label (if no other blocking rows remain open) and sets `review:merge-ready` (if consensus criteria are satisfied). Downstream in `scripts/ci/merge_gate.sh`, the row is omitted from `BLOCKING`, allowing conjunct 4 to evaluate true (`C[4]=1; WHY[4]="blocking set empty"`). | Ensures immediate unblocking of the autonomous merge loop when reviewers downgrade findings to non-blocking tiers, fulfilling the core operational objective of YOLO Gate Y. |
| **D8** | **Contract test coverage matrix in `scripts/ci/tests/review_recorder_test.sh`.** `scripts/ci/tests/review_recorder_test.sh` must include test cases verifying: 1. Discoverer downgrading `high` to `normal` across rounds updates ledger row severity to `normal`, appends audit note, and emits stdout diagnostic log. 2. Downgrade from `high` to `normal` removes row from blocking set, allowing `merge_gate.sh` conjunct 4 to pass. 3. Peer reviewer emitting different severity on discoverer's finding leaves row severity unchanged. 4. Discoverer emitting `high` in subsequent round without sibling failure-scenario marker demotes to `normal` with demotion audit note and stdout log. 5. Discoverer emitting non-security severity for an existing `security` row is ignored; row remains `security` with diagnostic log. 6. Discoverer elevating `normal` to `high` in round 4+ is demoted to `normal` per round-cap funnel. 7. Maintainer retier directive takes precedence and can retier any finding including `security`. | Provides comprehensive contract verification and regression prevention across all severity transition paths, guards, and gate interactions. |
| **D9** | **Implementation scope boundary.** The implementing pull request for #361 may touch `scripts/ci/review_recorder.py`, `scripts/ci/tests/review_recorder_test.sh`, `docs/SPEC.md`, `REVIEW.md`, `personas/skills/review-protocol.md`, `intent/361-review-recorder-severity-of-a-seen/intent.md`, and `intent/361-review-recorder-severity-of-a-seen/spec.md`. It may not touch `.github/workflows/**`, `scripts/ops/**`, `scripts/ci/merge_gate.sh`, or other persona definitions under `personas/**`. | Confines code changes strictly to the recorder engine, test suite, protocol documentation, and living spec, protecting workflow and merge gate orchestration. |
| **D10** | **Living specification synchronization (`docs/SPEC.md`).** During the implementation stage, `docs/SPEC.md` under `### review.policy` is updated to specify that finding severity in `scripts/ci/review_recorder.py` is mutable across review rounds by the discovering reviewer, subject to failure-scenario validation, round funnel bounds, and security tier protection, with transparent audit note attribution. | Maintains living specification fidelity per repository standards. |

## Acceptance

- **AT-361-1 (D1, D6, D8)** Run `bash scripts/ci/tests/review_recorder_test.sh`: passes with exit code 0, verifying that when discovering reviewer Argus emits `finding:R2-1@D5:normal:open:none` after earlier `finding:R2-1@D5:high:open:none`, the ledger row updates to `ledger-row:R2-1@D5:normal:open:none`, audit note `[severity updated to normal by @argus on R2-1@D5]` is recorded in `$WRITES`, and stdout logs `finding R2-1@D5: severity updated from high to normal by @argus`.
- **AT-361-2 (D1, D7, D8)** Run `bash scripts/ci/tests/review_recorder_test.sh`: passes with exit code 0, verifying that after the discovering reviewer downgrades `R2-1@D5` from `high` to `normal`, running `merge_gate.sh` evaluates conjunct 4 to true (`C[4]=1; WHY[4]="blocking set empty"`).
- **AT-361-3 (D5, D8)** Run `bash scripts/ci/tests/review_recorder_test.sh`: passes with exit code 0, verifying that when peer reviewer Atlas emits `finding:R2-1@D5:normal:open:none` on Argus's finding `R2-1@D5` (currently `high`), the ledger row remains `ledger-row:R2-1@D5:high:open:none` and no severity update note is written in `$WRITES`.
- **AT-361-4 (D3, D8)** Run `bash scripts/ci/tests/review_recorder_test.sh`: passes with exit code 0, verifying that when discoverer Argus emits `finding:R2-1@D5:high:open:none` in a subsequent round without a sibling failure-scenario marker, the finding is demoted to `normal` (`ledger-row:R2-1@D5:normal:open:none`), audit note `[demoted from high: missing failure_scenario marker] on R2-1@D5` is recorded in `$WRITES`, and stdout emits the diagnostic demotion log.
- **AT-361-5 (D4, D8)** Run `bash scripts/ci/tests/review_recorder_test.sh`: passes with exit code 0, verifying that when discoverer Argus emits `finding:R1-1:normal:open:none` on an existing row recorded as `security`, the row remains `ledger-row:R1-1:security:open:pending`, the footer downgrade is ignored, and stdout logs `finding R1-1: footer severity change from security to normal ignored; security rows require maintainer retier`.
- **AT-361-6 (D2, D8)** Run `bash scripts/ci/tests/review_recorder_test.sh`: passes with exit code 0, verifying that when discoverer Argus attempts to elevate an existing finding `R1-5` from `normal` to `high` in round 4 (`effective_round=4`), the finding is demoted to `normal` per the post-round-3 funnel cap (`ledger-row:R1-5:normal:open:none`).
- **AT-361-7 (D4, D8)** Run `bash scripts/ci/tests/review_recorder_test.sh`: passes with exit code 0, verifying that a maintainer retier directive (`@argus retier R1-1 normal`) from an authorized human maintainer successfully retiers a `security` row to `normal` with audit note `[retiered to normal by @<user>]`.
- **AT-361-8 (D9)** Run `bash scripts/ci/sanitize_check.sh`, `bash scripts/ci/spec_check.sh origin/main`, and `python3 scripts/sync_agents.py --check`: all exit 0 with clean output.
- **AT-361-9 (D10)** Verify `docs/SPEC.md` under `### review.policy` specifies discoverer severity mutability across rounds, failure-scenario demotion guards, round funnel constraints, and security tier protection.

## Concerns

- **Stateless Reviewer Re-emission Integrity**: Reviewers are stateless between runs (`REVIEW.md:252`). If a reviewer re-emits a `high` finding in a verification round without repeating the sibling `<!-- failure-scenario:<id> -->` marker, D3 will demote the finding to `normal`. This is by design: the review protocol requires continuous proof of failure for every active `high` assertion.
- **Security Invariant Sanctity**: Prohibiting bot verdict blocks from unilaterally downgrading `security` findings prevents transient hallucinations or prompt drift from compromising security gates without human approval.
- **Audit Table Length**: To avoid bloating the consensus ledger comment, D6 deduplicates audit notes and records severity updates only when `old_sev != new_sev`.

## Out of scope

- Peer consensus state retraction toward `agree`/`pending` (tracked separately in #331).
- Assigned reviewer set decoupling for split review gating (tracked separately in #328).
- Modifications to `scripts/ci/merge_gate.sh` (the gate dynamically evaluates severities from ledger rows; no code changes required).
- Redefining the 4-tier severity model or round budget architecture.

## Operator decisions

None required.

Open questions: none
