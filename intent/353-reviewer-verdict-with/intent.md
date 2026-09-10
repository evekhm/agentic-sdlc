# Intent: Enforce Reviewer Run-ID Provenance Injection and Surface Verdict Refusals

**Issue:** #353 · **Author:** athena (`evekhm-athena-app[bot]`) · **Status:** Accepted

## Problem

Under the repository review policy (PR #14, #267, #291; `docs/SPEC.md:544-577`, `REVIEW.md:231-255`), autonomous reviewers (`argus`, `atlas`) emit structured review verdict blocks containing machine-readable markers:
```markdown
<!-- review-verdict:<reviewer>:<verdict> -->
<!-- reviewed-head:<full-oid> -->
<!-- run-id:<n> -->
<!-- round:<n> -->
<!-- finding:<id>:<severity>:<status>:<peer> -->
<!-- failure-scenario:<id> -->
<!-- review-verdict-end -->
```
To prevent forged or out-of-band reviews, the consensus recorder (`scripts/ci/review_recorder.py:185-226`, executing in `.github/workflows/merge-gate.yml`) verifies the Actions workflow run ID (`<!-- run-id:<n> -->`) against the GitHub Actions API (`GET /repos/<repo>/actions/runs/<run_id>`) against four provenance predicates:
1. `head_sha` equals the verdict's `reviewed-head`.
2. Workflow path equals `.github/workflows/unattended.yml`.
3. `head_repository.full_name` equals this repository.
4. `event` is in `{"pull_request", "workflow_dispatch"}`.

In production, reviewer verdict blocks intermittently carry `<!-- run-id:0 -->` instead of the genuine Actions workflow run ID. Because run ID `0` is invalid, the Actions API lookup fails, `run_head_sha` evaluates to empty, and the recorder refuses the verdict block with the audit note:
```markdown
[refused: run 0 head_sha mismatch: expected <reviewed_head>, got ]
```
When this refusal occurs:
1. **The recorder drops the verdict**: The consensus recorder does not admit the verdict block, does not update `accepted_heads[reviewer]`, and leaves the consensus ledger comment (`<!-- consensus-ledger:<pr> -->`) pinned to the reviewer's prior reviewed head and findings.
2. **The merge gate declines without visible cause**: When `scripts/ci/merge_gate.sh` evaluates the pull request, conjunct (3) declines with `WHY[3]="<reviewer> verdict is at <old-head>, head is <new-head>"`. If a finding from a prior round had a dispute flag (e.g. `R1-1@D3:normal:open:dispute`), conjunct (5) declines as well.
3. **The autonomous cycle deadlocks**: The refusal is invisible in the pull request thread. The audit note does not name which reviewer was refused, no check annotation or warning is emitted, and the merge gate reason merely asserts that the reviewer has not reviewed the current commit. Downstream builders and pollers see that both reviewers have posted review comments at the current head, yet no fix round is triggered because the reviewer actually posted a clean or non-blocking verdict and the builder has no unresolved findings to address.

### Evidence

- **PR #344 (Issue #337 Spec)**: At 2026-09-10T04:43:18Z, Argus reviewed head `697cc20c010c04224cbaa569f65962326b87b927` in round 2. Argus's review comment carried `<!-- review-verdict:argus:findings -->`, `<!-- reviewed-head:697cc20... -->`, `<!-- run-id:0 -->`, six rows marked `fixed`, and two new non-blocking `normal` rows. Atlas round 2 at 04:46:34Z carried `<!-- run-id:34437996410 -->` and verdict `clean`. The consensus recorder refused Argus's verdict; ledger comment 5610281073 kept `reviewed-head:argus:0068a8b...` (round 1 head) and retained `R1-1@D3` as `open:dispute`. Merge Gate run 34438487248 declined on conjunct (3) (`argus verdict is at 0068a8b..., head is 697cc20...`) and conjunct (5) (`dispute on: R1-1@D3`). To resolve the deadlock, the advisor seat had to merge PR #344 by hand on 2026-09-10.
- **PR #319 (Issue #265 Implement)**: At 2026-09-10T06:05:26Z, Argus reviewed head `0a3b724`, emitting `<!-- review-verdict:argus:findings -->`, `<!-- reviewed-head:0a3b724... -->`, `<!-- run-id:0 -->`, and zero blocking rows. Atlas's block from the same unattended run (run ID 34443241754) carried a real run ID and was admitted. The recorder refused Argus's verdict (`[refused: run 0 head_sha mismatch: expected 0a3b724..., got ]`). The ledger kept `reviewed-head:argus:ff27a6e`. Merge Gate run 34443759989 declined on conjunct (3) alone, despite both reviewers having clean verdicts at head. Resolving the defect required an operator to manually execute `gh run rerun --job 102762516413` to force Argus to re-execute and re-post.
- **Earlier Occurrence on PR #319**: At 2026-09-09T19:51:30Z (head `acb343e`), Argus previously emitted `run-id:0`; subsequent rounds on the same PR carried authentic run IDs, demonstrating intermittent failure during reviewer marker generation.

### Root Cause Analysis

1. **Model Delegation of Infrastructure Metadata**:
   In `personas/skills/review-protocol.md:21-34` and `REVIEW.md:231-251`, the template requires `<!-- run-id:<n> -->`. However, the instructions never specify how `<n>` is obtained. An LLM (Claude Code for Argus, Antigravity for Atlas) is an inference model responsible for reviewing code diffs, verifying contracts, and identifying defects; it should not be tasked with querying the GitHub Actions runtime environment to compose infrastructure provenance identifiers. When the model does not run a shell tool to inspect `GITHUB_RUN_ID` (or when it defaults to placeholder values), it generates `<!-- run-id:0 -->`.
2. **Missing Runner Post-Processing and Fail-Closed Guard**:
   All reviewer comments are written via `scripts/ops/post.sh <pr> --as <persona> --body-file <path>`. `post.sh` validates the `hold` label and verifies the authenticated commenter identity, but performs no validation or post-processing on review verdict blocks. It neither injects `GITHUB_RUN_ID` into the body file nor checks if `GITHUB_RUN_ID` is missing/zero when posting review verdicts, allowing invalid markers to reach the PR.
3. **Inadequate Refusal Attribution in Consensus Recorder**:
   In `scripts/ci/review_recorder.py:214-225`, refusal notes are recorded as `[refused: run {run_id} head_sha mismatch: expected {reviewed_head}, got {run_head_sha}]`. The note does not identify the reviewer (`argus` or `atlas`), does not indicate that the reviewer's verdict was rejected, and emits no machine-readable marker in the consensus block.
4. **Merge Gate Diagnostic Blindness**:
   `scripts/ci/merge_gate.sh:325-334` evaluates conjunct (3) solely against `ARGUS_HEAD` and `ATLAS_HEAD` parsed from the consensus block. When a reviewer's verdict at `HEAD` is refused by the recorder, `merge_gate.sh` emits `WHY[3]="<reviewer> verdict is at <old-head>, head is <HEAD>"`. This diagnostic fails to report that a verdict for `HEAD` was submitted on the PR but rejected by the consensus recorder, leaving operators without the information needed to diagnose the failure.

## Proposed outcome

1. **Automated Run-ID Injection by the Posting Runner (`scripts/ops/post.sh`)**:
   - The posting runner (`scripts/ops/post.sh` or a dedicated review post-processor) automatically injects or overwrites `<!-- run-id:<run_id> -->` using the environment's `GITHUB_RUN_ID` whenever a review verdict block (`<!-- review-verdict:... -->`) is posted by an authorized reviewer persona (`argus`, `atlas`).
   - The LLM is relieved of composing the `run-id` marker. `personas/skills/review-protocol.md` and `REVIEW.md` are updated to clarify that `run-id` is an infrastructure-managed marker.
   - If a review verdict block is posted in unattended mode and `GITHUB_RUN_ID` is empty, unset, or `0`, the runner fails loudly (exits non-zero with an explicit diagnostic) rather than posting a corrupt verdict block with `run-id:0`.
2. **Attributed Refusal Logging and Markers in Consensus Recorder (`scripts/ci/review_recorder.py`)**:
   - `scripts/ci/review_recorder.py` formats all verdict refusal audit notes with explicit reviewer attribution (e.g. `[refused: verdict block from @{reviewer}: run {run_id} head_sha mismatch: expected {reviewed_head}, got {run_head_sha}]`).
   - For every refused verdict block, the recorder emits a machine-readable refusal marker in the consensus block:
     ```markdown
     <!-- refused-verdict:<reviewer>:<reviewed_head>:<reason> -->
     ```
   - The consensus ledger renders refused verdicts prominently under `#### Notes` or a designated Refusals section so that rejected reviews are immediately observable on the pull request.
3. **Explicit Refusal Diagnostics in Merge Gate Conjunct (3) (`scripts/ci/merge_gate.sh`)**:
   - When evaluating conjunct (3), if `<reviewer>` is not recorded at the pull request `HEAD`, `scripts/ci/merge_gate.sh` checks the consensus ledger for a matching `<!-- refused-verdict:<reviewer>:<HEAD>:... -->` marker.
   - If a refusal marker exists for `HEAD`, the merge gate reports the refusal directly in the diagnostic reason:
     ```
     WHY[3]="<reviewer> verdict at <HEAD> was refused by recorder (<reason>); ledger recorded head is <old-head>"
     ```
   - This provides immediate visibility to developers, operators, and autonomous pollers, distinguishing between pending reviews and rejected reviews.
4. **Contract & Regression Tests**:
   - Add unit and contract tests in `scripts/ci/tests/review_recorder_test.sh` asserting that refused verdict blocks emit attributed audit notes and machine-readable `<!-- refused-verdict:... -->` markers.
   - Add contract tests in `scripts/ci/tests/merge_gate_test.sh` verifying that conjunct (3) diagnostics report refused verdicts at the current head.
   - Add tests verifying that `scripts/ops/post.sh` injects `GITHUB_RUN_ID` into review verdict blocks and fails closed when `GITHUB_RUN_ID` is missing or zero.
5. **Living Specification & Protocol Documentation (`docs/SPEC.md`, `REVIEW.md`)**:
   - Update `docs/SPEC.md` under `review.policy` and execution model to document the automated run-id injection contract, refusal markers, and merge gate diagnostic requirements.

## Affected users and systems

- **Posting Runner (`scripts/ops/post.sh`)**: Performs pre-write injection of `GITHUB_RUN_ID` into review comments and enforces fail-closed checks.
- **Consensus Recorder (`scripts/ci/review_recorder.py`, `scripts/ci/review_recorder.sh`)**: Verifies provenance, formats attributed refusal notes, and emits machine-readable refusal markers.
- **Merge Gate (`scripts/ci/merge_gate.sh`)**: Evaluates conjunct (3) and surfaces refused verdict diagnostics in gate summaries.
- **Autonomous Reviewers (`argus`, `atlas`)**: Review emission workflow in `.github/workflows/unattended.yml`.
- **Autonomous Merge Orchestrator (`themis`)**: Merge gate evaluation and consensus tracking.
- **Autonomous Lifecycle / Poller (`scripts/placement/vm-local/poll.sh`)**: Fix-round poller receiving clear signals when a review requires re-running rather than code fixes.
- **Human Operators / Advisor Seat**: Relieved of manual PR triage, out-of-band merges, and obscure deadlock debugging.
- **Specifications & Documentation**: `docs/SPEC.md`, `REVIEW.md`, `personas/skills/review-protocol.md`.

## Constraints

- **Strict Provenance Verification Preserved**: Decision D3 of #267 and security protections from #318 remain binding; verdict blocks must continue to be verified against GitHub Actions API (`head_sha`, workflow path `.github/workflows/unattended.yml`, repository name, and trigger events).
- **No Closing Keywords**: In accordance with #245, pull requests and commits addressing this issue must reference `Refs #353`, never `Closes #353` or `Fixes #353`.
- **Local & Test Compatibility**: Local developer runs, mock test suites, and dry-run dispatches must be supported (e.g. via mock run ID or explicit environment override) without bypassing production provenance guarantees.
- **Single-Writer Ledger Invariant**: The consensus recorder (`themis`) remains the sole writer of the consensus ledger comment; the merge gate reads ledger markers without making redundant API calls.
- **Authority Bounds**: Athena authors only `intent/**`. Code, workflow, and test implementation belong to Daedalus (plan) and Odyssey (implementation) in subsequent lifecycle stages.

## Open questions

1. **Injection Implementation Location**: Should `scripts/ops/post.sh` directly perform regex substitution on the body file to inject/overwrite `<!-- run-id:<run_id> -->`, or should a dedicated Python or Bash helper (e.g. `scripts/ops/lib/inject_provenance.py`) handle verdict block parsing and injection?
2. **Refused Verdict Marker Schema**: What exact marker schema should `review_recorder.py` emit in the consensus ledger for refused verdicts?
   - Option A: `<!-- refused-verdict:<reviewer>:<head-sha>:<reason-code> -->` (e.g. `<!-- refused-verdict:argus:697cc20:run-head-sha-mismatch -->`)
   - Option B: `<!-- refused-verdict:<reviewer>:<head-sha>:<run-id>:<reason-code> -->`
3. **Refusal Marker Retention Policy**: If multiple rounds or runs are refused on the same pull request, should the consensus ledger retain all refusal markers across historical heads, or only retain the latest refusal marker per reviewer?
4. **Local / Development Handling in `post.sh`**: How should `scripts/ops/post.sh` distinguish between an unattended GitHub Actions runner execution (which must fail closed if `GITHUB_RUN_ID` is missing or zero) and local/test executions (e.g. checking `[ "${GITHUB_ACTIONS:-}" = "true" ]` or allowing `ALLOW_UNSAFE_RUN_ID=1`)?
5. **Check Annotations vs Ledger Notes**: Should the recorder additionally emit GitHub Actions workflow error notices (e.g. `::error::...`) or check run annotations during the `record` job in `merge-gate.yml`, or is surfacing the refusal in the consensus ledger comment and merge gate diagnostic sufficient?
