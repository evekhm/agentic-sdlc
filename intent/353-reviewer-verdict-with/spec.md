# Spec: Enforce Reviewer Run-ID Provenance Injection and Surface Verdict Refusals

**Issue:** #353 · **Status:** Approved (approval = merge of this PR) ·
**Author:** athena (`evekhm-athena-app[bot]`) ·
**Open questions:** none

## What is being built

This specification resolves issue #353 by shifting GitHub Actions `run-id` provenance management from inference models to runner infrastructure (`scripts/ops/post.sh`), enforcing fail-closed posting validation on review verdicts in unattended environments, formatting attributed audit notes and emitting machine-readable refusal markers in the consensus recorder (`scripts/ci/review_recorder.py`), and surfacing explicit refusal diagnostics in merge gate conjunct (3) (`scripts/ci/merge_gate.sh`).

### Background and Root Causes

Under repository review policy (PR #14, #267, #291; `docs/SPEC.md:544-577`, `REVIEW.md:231-255`), autonomous reviewers (`argus`, `atlas`) post structured review verdict blocks containing machine-readable markers:
```markdown
<!-- review-verdict:<reviewer>:<verdict> -->
<!-- reviewed-head:<full-oid> -->
<!-- run-id:<n> -->
<!-- round:<n> -->
<!-- finding:<id>:<severity>:<status>:<peer> -->
<!-- failure-scenario:<id> -->
<!-- review-verdict-end -->
```
To guarantee authentic provenance and protect against forged or out-of-band reviews, the consensus recorder (`scripts/ci/review_recorder.py`) checks four API provenance predicates against GitHub Actions API (`GET /repos/<repo>/actions/runs/<run_id>`):
1. `head_sha` equals the verdict's `reviewed-head`.
2. Workflow path equals `.github/workflows/unattended.yml`.
3. `head_repository.full_name` equals this repository.
4. `event` is in `{"pull_request", "workflow_dispatch"}`.

In production, four interrelated defects caused autonomous loop deadlocks (as observed on PR #344 and PR #319):
1. **Model Delegation of Infrastructure Metadata**: Reviewer prompts and protocols instruct LLMs to emit `<!-- run-id:<n> -->` without specifying an automated retrieval mechanism. As inference models, LLMs should review code diffs and contract obligations rather than query runner process environments. When an LLM fails to run an extra shell tool or defaults to template values, it generates `<!-- run-id:0 -->`.
2. **Missing Runner Post-Processing and Fail-Closed Guard**: Review comments are posted via `scripts/ops/post.sh <pr> --as <persona> --body-file <path>`. `post.sh` verified only `hold` labels and author identity, performing zero validation or injection on verdict blocks. It neither injected `GITHUB_RUN_ID` nor prevented `run-id:0` from being published.
3. **Unattributed and Unmarked Recorder Refusals**: When `review_recorder.py` encountered `run-id:0` or provenance mismatches, it emitted unattributed notes (e.g. `[refused: run 0 head_sha mismatch: expected <sha>, got ]`) and no machine-readable marker in the consensus block (`<!-- consensus-ledger:<pr> -->`). The ledger comment remained pinned to the reviewer's prior head.
4. **Merge Gate Diagnostic Blindness**: `merge_gate.sh` evaluated conjunct (3) solely against recorded ledger heads (`ARGUS_HEAD`, `ATLAS_HEAD`). When a reviewer's verdict at `HEAD` was refused by the recorder, the gate emitted `WHY[3]="<reviewer> verdict is at <old-head>, head is <HEAD>"`. This diagnostic failed to distinguish between a pending review and a rejected review, obscuring the refusal from pollers and operators.

### Proposed Architecture

This specification defines ten numbered decisions:
1. **Automated Run-ID Provenance Injection (D1)**: In `scripts/ops/post.sh`, automatically inject or overwrite `<!-- run-id:${GITHUB_RUN_ID} -->` into every review verdict block in the comment body whenever an authorized reviewer (`argus`, `atlas`) posts a review verdict.
2. **Fail-Closed Runner Guard for Unattended Reviews (D2)**: In `scripts/ops/post.sh`, fail closed (exit status 1) if a review verdict block is posted when `GITHUB_ACTIONS=true` and `GITHUB_RUN_ID` is unset, empty, or `0`. Provide `ALLOW_UNSAFE_RUN_ID=1` bypass exclusively for local/test executions outside GitHub Actions.
3. **Review Protocol Documentation Update (D3)**: Update `personas/skills/review-protocol.md` and `REVIEW.md` to document that `run-id` is an infrastructure-managed marker and that models may emit `<!-- run-id:0 -->` or omit the marker.
4. **Attributed Refusal Audit Notes (D4)**: In `scripts/ci/review_recorder.py`, format all verdict block refusal audit notes with uniform reviewer attribution: `[refused: verdict block from @{reviewer}: <reason>]`, and log refusals to stderr.
5. **Machine-Readable Refusal Markers in Consensus Ledger (D5)**: In `scripts/ci/review_recorder.py`, emit `<!-- refused-verdict:<reviewer>:<reviewed_head>:<reason_code> -->` inside the consensus ledger block for unaccepted refused verdicts at that head.
6. **Consensus Ledger Notes Rendering (D6)**: Render attributed refusal notes visibly under `#### Notes` in the PR consensus ledger Markdown comment.
7. **Explanatory Refusal Diagnostics in Merge Gate Conjunct 3 (D7)**: In `scripts/ci/merge_gate.sh`, inspect the ledger for `refused-verdict` markers targeting `$HEAD` and surface explicit refusal diagnostics: `WHY[3]="<reviewer> verdict at $HEAD was refused by recorder (<reason_code>); ledger recorded head is <recorded_head>"`.
8. **Contract and Regression Test Matrix (D8)**: Comprehensive contract tests across `review_recorder_test.sh`, `merge_gate_test.sh`, and `post.sh` test suites covering injection, fail-closed guards, attributed notes, refusal markers, and gate diagnostics.
9. **Living Specification Synchronization (D9)**: Upsert `docs/SPEC.md` under `### review.policy`.
10. **Implementation Scope Boundary (D10)**: Strict scope fences confining changes to posting infrastructure, recorder engine, merge gate, test suites, protocol documentation, and lifecycle artifacts.

### File Manifest

```text
scripts/ops/post.sh                              # automated run-id injection and fail-closed guard
scripts/ci/review_recorder.py                    # attributed refusal audit notes, machine-readable refused-verdict markers
scripts/ci/merge_gate.sh                         # conjunct (3) refused verdict diagnostic inspection and reporting
personas/skills/review-protocol.md               # protocol documentation: run-id is infrastructure-managed
REVIEW.md                                        # root review protocol: run-id injection contract and refusal markers
docs/SPEC.md                                     # living spec update under review.policy
scripts/ci/tests/review_recorder_test.sh         # contract tests: attributed refusal notes, refusal markers, ledger notes
scripts/ci/tests/merge_gate_test.sh              # contract tests: conjunct (3) refused verdict diagnostic reporting
scripts/ci/tests/review_split_gate_contract_test.sh # contract tests: post.sh run-id injection and fail-closed guards
intent/353-reviewer-verdict-with/spec.md         # this specification
intent/353-reviewer-verdict-with/intent.md       # intent artifact updated to Status: Accepted
```

Files under `.github/workflows/**`, `scripts/setup/**`, `scripts/auth/**`, and persona definitions outside `skills/review-protocol.md` are not touched.

## Decisions

| ID | Decision | Rationale |
|---|---|---|
| D1 | **Automated Run-ID Provenance Injection in `scripts/ops/post.sh`.** When `scripts/ops/post.sh` is invoked with `--body-file <path>` and `--as <persona>` where `<persona>` is an authorized reviewer (`argus` or `atlas`), and the body file contains one or more review verdict blocks (`<!-- review-verdict:`), `post.sh` inspects the body file. If `GITHUB_RUN_ID` is present in the environment matching `^[1-9][0-9]*$`, `post.sh` automatically injects or overwrites `<!-- run-id:${GITHUB_RUN_ID} -->` into every review verdict block before posting to GitHub. If `<!-- run-id:[0-9]+ -->` already exists within a block, it is replaced in-place; if omitted, `<!-- run-id:${GITHUB_RUN_ID} -->` is inserted immediately following the `<!-- reviewed-head:[0-9a-f]{40} -->` line. Non-reviewer personas (e.g. `odyssey`, `daedalus`, `athena`) posting comments containing quoted verdict blocks do not trigger injection or validation. | Reviewers are inference models designed for diff review and contract verification. Delegating infrastructure provenance to runner scripts eliminates intermittent `run-id:0` failures without requiring brittle tool calls or model retraining. |
| D2 | **Fail-Closed Runner Guard for Unattended Reviews.** In `scripts/ops/post.sh`, if a comment containing a review verdict block is posted with `--as argus` or `--as atlas`, and `GITHUB_RUN_ID` is missing, empty, non-numeric, or `0`:<br>1. If executing in an unattended CI environment (`GITHUB_ACTIONS=true` or `POST_REQUIRE_RUN_ID=1`), `post.sh` fails closed immediately with exit status 1: `die "GITHUB_RUN_ID is unset or zero in unattended environment; refusing to post verdict block without authentic run-id"`. No comment is posted.<br>2. If executing outside CI (`GITHUB_ACTIONS` != `true`):<br>&nbsp;&nbsp;a. If `ALLOW_UNSAFE_RUN_ID=1` is exported, `post.sh` emits a warning to stderr (`post.sh: warning: posting review verdict with unvalidated run-id (ALLOW_UNSAFE_RUN_ID=1)`) and permits posting without modifying the body file.<br>&nbsp;&nbsp;b. If the body file already contains a non-zero `<!-- run-id:[1-9][0-9]* -->`, `post.sh` permits posting without rewriting.<br>&nbsp;&nbsp;c. Otherwise, `post.sh` exits status 1 with `die "GITHUB_RUN_ID is unset or 0; export GITHUB_RUN_ID or ALLOW_UNSAFE_RUN_ID=1 to post review verdicts locally"`. | Ensures zero invalid verdict blocks reach pull request threads in production CI while preserving hermetic testing and local developer workflows. |
| D3 | **Review Protocol Marker Documentation Update.** `personas/skills/review-protocol.md` and `REVIEW.md` are updated to state that `<!-- run-id:<n> -->` is an infrastructure-managed marker. Reviewer personas may emit `<!-- run-id:0 -->` or omit the marker entirely in their draft review bodies, as `scripts/ops/post.sh` automatically injects the authentic `GITHUB_RUN_ID` during comment publication. The verification protocol retains strict API provenance verification against `.github/workflows/unattended.yml`. | Reconciles reviewer persona instructions with runner posting capabilities, eliminating prompt ambiguity. |
| D4 | **Attributed Verdict Refusal Audit Notes in `scripts/ci/review_recorder.py`.** All verdict block refusal audit notes recorded in `audit_notes` must include explicit reviewer attribution using the uniform format `[refused: verdict block from @{reviewer}: <reason>]`. Specifically:<br>- Commit not in history: `[refused: verdict block from @{reviewer}: commit {reviewed_head} not in pull request history]`<br>- Missing reviewed head: `[refused: verdict block from @{reviewer}: missing reviewed-head marker]`<br>- Missing run id: `[refused: verdict block from @{reviewer}: missing run-id marker]`<br>- Head SHA mismatch: `[refused: verdict block from @{reviewer}: run {run_id} head_sha mismatch: expected {reviewed_head}, got {run_head_sha}]`<br>- Workflow path mismatch: `[refused: verdict block from @{reviewer}: run {run_id} workflow path mismatch: expected .github/workflows/unattended.yml, got {run_path}]`<br>- Repository mismatch: `[refused: verdict block from @{reviewer}: run {run_id} repository mismatch: expected {repo}, got {run_repo}]`<br>- Event mismatch: `[refused: verdict block from @{reviewer}: run {run_id} event mismatch: event must be pull_request or workflow_dispatch, got {run_event}]`<br>- Terminal failure / cancelled run: `[refused: verdict block from @{reviewer}: run {run_id} ended {run_concl}; verdict withdrawn]`<br>Additionally, every refusal must print a diagnostic line to stderr: `print(f"refused: verdict block from @{reviewer}: ...", file=sys.stderr)`. | Eliminates anonymous refusal messages in CI logs and ledger comments, allowing operators and tools to immediately identify which reviewer's verdict was rejected and why. |
| D5 | **Machine-Readable Refusal Markers in Consensus Ledger Block.** When `review_recorder.py` refuses a verdict block from `<reviewer>` for commit `<reviewed_head>`, it emits a machine-readable refusal marker inside the consensus block (`<!-- consensus-ledger:<pr> -->` ... `<!-- consensus-ledger-end -->`):<br>`<!-- refused-verdict:<reviewer>:<reviewed_head>:<reason_code> -->`<br>where `<reason_code>` is one of:<br>`commit-not-in-history`, `missing-reviewed-head`, `missing-run-id`, `run-head-sha-mismatch`, `run-workflow-path-mismatch`, `run-repo-mismatch`, `run-event-mismatch`, `run-terminal-failure`.<br>Retention policy: Markers are emitted for each unique `(reviewer, reviewed_head)` tuple with an unaccepted refusal. If `<reviewer>` subsequently posts an accepted verdict at `<reviewed_head>`, any refusal marker for `(reviewer, reviewed_head)` is cleared. If multiple refusal blocks occur for the same `(reviewer, reviewed_head)` without acceptance, the latest refusal reason code is emitted. Markers are omitted if `reviewed_head` is missing or not a 40-hex SHA. | Exposes machine-readable refusal state directly in the consensus ledger, enabling downstream tools (merge gate, VM poller) to inspect refusal causes without parsing unstructured audit strings or calling external APIs. |
| D6 | **Consensus Ledger Markdown Table and Notes Rendering.** In `review_recorder.py`, all unique attributed refusal audit notes are rendered under `#### Notes` in the consensus ledger Markdown comment. If no findings are recorded on the PR and all submitted review verdicts were refused, the findings table renders `|_No findings recorded._|||||` and notes prominently display the attributed refusal reasons. | Ensures visibility of rejected reviews on the PR thread without requiring developers to inspect Actions workflow logs. |
| D7 | **Explanatory Refused Verdict Diagnostics in Merge Gate Conjunct (3).** In `scripts/ci/merge_gate.sh`, when evaluating conjunct (3): If an assigned reviewer (`argus` or `atlas`) does not have an accepted verdict at `$HEAD` (`$ARGUS_HEAD != $HEAD` or `$ATLAS_HEAD != $HEAD`):<br>1. `merge_gate.sh` inspects the consensus ledger block in `$LEDGER_BODY` for a marker matching `^<!-- refused-verdict:<reviewer>:$HEAD:([a-z0-9-]+) -->$`.<br>2. If a refusal marker targeting `$HEAD` is present with reason `<reason_code>`, the gate reports the refusal in `WHY[3]`: `"<reviewer> verdict at $HEAD was refused by recorder (<reason_code>); ledger recorded head is ${RECORDED_HEAD:-none}"`.<br>3. If both reviewers have unaccepted verdicts at `$HEAD` and both carry refusal markers for `$HEAD`, `WHY[3]` reports both refusals separated by `; `.<br>4. If no refusal marker exists for `$HEAD`, `merge_gate.sh` retains its existing diagnostic: `"<reviewer> verdict is at ${RECORDED_HEAD:-none}, head is $HEAD"`.<br>If Atlas cannot carry forward and has a refusal marker targeting `$HEAD`, the refusal diagnostic takes precedence over missing verdict messages. | Distinguishes between pending reviews and rejected reviews at gate evaluation time, providing immediate root-cause feedback to operators and pollers. |
| D8 | **Contract and Regression Test Matrix.** Comprehensive automated tests must be added across repository test suites:<br>1. `scripts/ci/tests/review_recorder_test.sh`: Assert that all 8 refusal conditions output attributed notes (`[refused: verdict block from @<reviewer>: ...]`), emit `<!-- refused-verdict:<reviewer>:<head>:<reason-code> -->` markers in the ledger, clear refusal markers when superseded by an accepted verdict at that head, and log diagnostics to stderr.<br>2. `scripts/ci/tests/merge_gate_test.sh`: Assert that conjunct (3) diagnostics report refused verdicts at `$HEAD` for Argus, Atlas, and dual-refusal scenarios, preserving recorded head reporting.<br>3. `scripts/ci/tests/review_split_gate_contract_test.sh` (or `scripts/ops/tests/**`): Assert that `post.sh` overwrites `run-id:0`, inserts missing `run-id`, fails closed with status 1 when `GITHUB_ACTIONS=true` and `GITHUB_RUN_ID` is missing/zero, and permits bypass with `ALLOW_UNSAFE_RUN_ID=1` outside CI. | Enforces full test coverage and prevents future regressions of the PR #344 / PR #319 deadlock mode. |
| D9 | **Living Specification Synchronization (`docs/SPEC.md`).** During the implementation stage, `docs/SPEC.md` under `### review.policy` is updated to describe automated run-id injection, fail-closed posting validation, attributed refusal audit notes, machine-readable `refused-verdict` ledger markers, and merge gate conjunct (3) refusal diagnostics. | Keeps living documentation synchronized with production gate behavior per repository standards. |
| D10 | **Implementation Scope Boundary.** The implementing pull request for #353 may touch `scripts/ops/post.sh`, `scripts/ci/review_recorder.py`, `scripts/ci/merge_gate.sh`, `personas/skills/review-protocol.md`, `REVIEW.md`, `docs/SPEC.md`, `scripts/ci/tests/review_recorder_test.sh`, `scripts/ci/tests/merge_gate_test.sh`, `scripts/ci/tests/review_split_gate_contract_test.sh`, `intent/353-reviewer-verdict-with/intent.md`, and `intent/353-reviewer-verdict-with/spec.md`. It may not touch `.github/workflows/**`, `scripts/setup/**`, `scripts/auth/**`, other persona files under `personas/**`, or files outside `intent/353-reviewer-verdict-with/`. | Prevents unintended changes to workflow runners, credentials, or protected persona sources. |

## Acceptance

- **AT-353-1 (D1, D8)** In `post.sh` contract tests, posting a review comment with `--as argus` containing `<!-- review-verdict:argus:clean -->`, `<!-- reviewed-head:<sha> -->`, and `<!-- run-id:0 -->` when `GITHUB_RUN_ID=54321` replaces `<!-- run-id:0 -->` with `<!-- run-id:54321 -->` in the posted payload.
- **AT-353-2 (D1, D8)** In `post.sh` contract tests, posting a review comment with `--as atlas` containing a review verdict block omitting `<!-- run-id:... -->` when `GITHUB_RUN_ID=54321` inserts `<!-- run-id:54321 -->` immediately following `<!-- reviewed-head:<sha> -->` in the posted payload.
- **AT-353-3 (D2, D8)** In `post.sh` contract tests, posting a review verdict block when `GITHUB_ACTIONS=true` and `GITHUB_RUN_ID` is unset or `0` fails immediately with exit status 1 and emits `GITHUB_RUN_ID is unset or zero in unattended environment; refusing to post verdict block without authentic run-id` to stderr, writing nothing to GitHub.
- **AT-353-4 (D2, D8)** In `post.sh` contract tests, posting a review verdict block when `GITHUB_ACTIONS` is unset and `ALLOW_UNSAFE_RUN_ID=1` is exported succeeds with exit status 0 and emits warning `post.sh: warning: posting review verdict with unvalidated run-id (ALLOW_UNSAFE_RUN_ID=1)` to stderr.
- **AT-353-5 (D4, D8)** Run `bash scripts/ci/tests/review_recorder_test.sh`: passes with exit code 0, verifying that all refusal scenarios (head SHA mismatch, workflow path mismatch, repo mismatch, event mismatch, commit not in history, missing run-id, missing reviewed-head, terminal run failure) append attributed audit notes matching `^\[refused: verdict block from @(argus|atlas): .*\]$` to `$WRITES`.
- **AT-353-6 (D5, D8)** Run `bash scripts/ci/tests/review_recorder_test.sh`: passes with exit code 0, verifying that a refused verdict for commit `$H` emits `<!-- refused-verdict:<reviewer>:$H:<reason_code> -->` inside the consensus ledger block in `$WRITES`.
- **AT-353-7 (D5, D8)** Run `bash scripts/ci/tests/review_recorder_test.sh`: passes with exit code 0, verifying that when a refused verdict at `$H` is followed by an accepted verdict from the same reviewer at `$H`, the `refused-verdict` marker for `$H` is cleared from the consensus ledger block.
- **AT-353-8 (D6, D8)** Run `bash scripts/ci/tests/review_recorder_test.sh`: passes with exit code 0, verifying that unique attributed refusal audit notes are rendered under `#### Notes` in the ledger Markdown comment.
- **AT-353-9 (D7, D8)** Run `bash scripts/ci/tests/merge_gate_test.sh`: passes with exit code 0, verifying that when `$ARGUS_HEAD != $HEAD` and `<!-- refused-verdict:argus:$HEAD:run-head-sha-mismatch -->` exists in the ledger, conjunct (3) evaluates to 0 and `WHY[3]` contains `argus verdict at $HEAD was refused by recorder (run-head-sha-mismatch); ledger recorded head is`.
- **AT-353-10 (D7, D8)** Run `bash scripts/ci/tests/merge_gate_test.sh`: passes with exit code 0, verifying that when Atlas cannot carry forward and carries `<!-- refused-verdict:atlas:$HEAD:run-workflow-path-mismatch -->`, conjunct (3) evaluates to 0 and `WHY[3]` contains `atlas verdict at $HEAD was refused by recorder (run-workflow-path-mismatch); ledger recorded head is`.
- **AT-353-11 (D3)** Verify `personas/skills/review-protocol.md` and `REVIEW.md` document that `<!-- run-id:<n> -->` is an infrastructure-managed marker automatically injected by `scripts/ops/post.sh`.
- **AT-353-12 (D9)** Verify `docs/SPEC.md` under `### review.policy` specifies automated run-id injection, fail-closed posting validation, attributed refusal audit notes, machine-readable refusal markers, and merge gate conjunct (3) diagnostics.
- **AT-353-13 (D10)** Run `bash scripts/ci/sanitize_check.sh`, `bash scripts/ci/spec_check.sh origin/main`, and `python3 scripts/sync_agents.py --check`: all exit 0 with clean output.

## Concerns

- **Automated injection versus provenance integrity**: Automated injection in `post.sh` does not weaken provenance security because the consensus recorder (`review_recorder.py`) continues to verify the injected run ID against the GitHub Actions API for `head_sha`, `.github/workflows/unattended.yml`, repository name, and trigger event. Injection merely guarantees that authentic environment metadata reaches the comment payload.
- **Local test ergonomics**: Requiring `GITHUB_RUN_ID` could break local test suites or manual testing. Decision D2 addresses this by allowing `ALLOW_UNSAFE_RUN_ID=1` or pre-existing non-zero run IDs when running outside CI (`GITHUB_ACTIONS != true`), ensuring tests remain hermetic while CI remains strictly fail-closed.
- **Refusal marker lifecycle**: If a PR accumulates multiple commits, retaining refusal markers for historical commits that were never accepted could theoretically clutter the ledger. Scoping markers to unique `(reviewer, reviewed_head)` tuples and clearing markers when that head is subsequently accepted ensures the ledger reflects accurate historical state without redundant duplicates.

## Out of scope

- Modifying the four provenance predicates in #267 D3 and #318.
- Modifying review round counters, review funnel rules, or severity demotion rules (#354).
- Altering the single-writer ledger invariant (Themis remains the sole writer of the consensus ledger comment).
- Modifying poller fix-round discovery or dispatch policies (#337).

## Operator decisions

None required.

Open questions: none
