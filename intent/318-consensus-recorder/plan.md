# Plan: Anchored Verdict Marker Parsing and Loud Declines in Consensus Recorder

**Issue:** #318 · **Spec:** `intent/318-consensus-recorder/spec.md` (Approved, Decisions D1–D9, Acceptance Criteria AT-318-1–AT-318-12)  
**Author:** daedalus (`evekhm-daedalus-app[bot]`)  
**Base commit:** `abfffecd70669ab9fbaa42cab7f28017e3564d41`  
**Target branch for implementation (Odyssey):** `odyssey/318-consensus-recorder-admits-verdict`

---

## 1. Executive Summary & Problem Statement

In the autonomous multi-agent software development lifecycle, PR merges are gated by the autonomous consensus of assigned review bots (Argus and Atlas) via structured machine-readable HTML comments. Historical production operation revealed three structural parser vulnerabilities and failure modes:

1. **Quoted Opening Marker Cross-Block Swallowing (PR #316, AT-318-3):** When Argus quoted a design document or prior review mentioning `> <!-- review-verdict:atlas:clean -->` without an explicit closing marker in the quote, the non-greedy regular expression `review-verdict:(argus|atlas)...review-verdict-end` paired the quoted Atlas marker with the closing `<!-- review-verdict-end -->` of Argus's authentic review findings block at the bottom of the comment. Because the regex extracted reviewer `atlas` while the comment author was `evekhm-argus-app[bot]`, the block was discarded as an author mismatch, completely dropping Argus's authentic findings from the consensus ledger.
2. **Silent Unprovenanced Finding Drops (PR #317, AT-318-4, AT-318-5):** When an unprovenanced review was posted (e.g. `run-id:0` or malformed `reviewed-head`), the recorder silently dropped the findings without recording a machine-readable refusal marker in the consensus ledger. The merge gate evaluated Conjunct (3) against the resulting clean ledger, creating a critical blind spot where posted review findings were silently ignored.
3. **Unanchored Mid-Line and Blockquoted Maintainer Retiers (PR #381, AT-318-8):** Maintainer directives such as `@argus retier <fid> normal` were matched unanchored anywhere in comment text, causing illustrative quotes and documentation examples to trigger finding severity demotions.

This plan specifies the implementation for:
- **Anchored Marker Parsing & Markdown Structure Exclusion (D1, D5):** Pre-processing comments to strip code fences, indented code blocks, and blockquotes, while anchoring verdict markers to line start (`^[[:space:]]*<!-- ... -->`).
- **Author-to-Reviewer Binding Prior to Block Matching (D2):** Deterministically binding the expected reviewer from authenticated comment author login (`evekhm-argus-app[bot]` -> `argus`, `evekhm-atlas-app[bot]` -> `atlas`) before regular expression matching, preventing foreign markers from opening matching blocks.
- **Loud Machine-Readable Refusal Markers Across All Declines (D3):** Ensuring every rejection (author mismatch, malformed/missing head, run provenance failure) emits both an attributed audit note and a machine-readable `<!-- refused-verdict:<reviewer>:<reviewed_head>:<reason_code> -->` in the consensus ledger.
- **Merge Gate Row Comparison for Ledger-Blindness Detection (D4):** Augmenting Conjunct (3) in `scripts/ci/merge_gate.sh` to compare posted findings at `$HEAD` from assigned reviewers against recorded ledger rows `CTUP`. If a posted finding has no ledger counterpart and no refusal marker, Conjunct (3) fails closed with an explicit ledger-blindness diagnostic.
- **Tracked Artifact Marker Sanitization Gate (D6):** Adding a fourth scan rule `marker` to `scripts/ci/sanitize_check.sh` and allowlist support in `scripts/ci/sanitize_allowlist.txt` to prevent live markers in tracked documentation and code.
- **Hermetic Historical Regression Suites (D7):** Preserving historical ledgers while validating PR #316, PR #317, and PR #381 in hermetic test suites.
- **Living Specification Upsert & Strict Scope Fences (D8, D9):** Updating `docs/SPEC.md` without modifying reviewer persona system prompts or GitHub Actions workflow trigger definitions.

---

## 2. Scope & Persona Boundaries

| Lifecycle Stage | Persona | Role & Authority Bounds |
| :--- | :--- | :--- |
| **design** | **Athena** | Authored and approved `intent/318-consensus-recorder/spec.md` with decisions D1–D9 and acceptance criteria AT-318-1–AT-318-12. |
| **build** | **Daedalus** *(current)* | Authors `plan.md` and contract test suites in `scripts/ci/tests/`. Strictly prohibited from modifying production scripts (`review_recorder.py`, `merge_gate.sh`, `sanitize_check.sh`, `sanitize_allowlist.txt`). |
| **implement** | **Odyssey** | Implements the committed plan, production scripts, documentation updates, and opens implementation PR. |
| **review** | **Argus / Atlas** | Performs dual code and policy review against spec and plan. |
| **gate** | **Themis** | Autonomous merge gate (`scripts/ci/merge_gate.sh`). |

### Deep Review Grant (Criteria DEEP-3, DEEP-5)
This change qualifies for the `deep-review` grant under two distinct criteria:
- **DEEP-3 (Irreversible or privileged operations):** Modifies `scripts/ci/merge_gate.sh` (which directly controls repository merge decisions) and `scripts/ci/review_recorder.py` (which issues GitHub API writes maintaining consensus state).
- **DEEP-5 (Escalated tier / high risk):** Tasks T2 and T4 modify state machines, consensus validation, and merge gate conjuncts.

**Application Mechanism:** Odyssey must apply the grant when opening the implementation pull request:
```bash
scripts/ops/post.sh <pr-number> --as odyssey --add-label deep-review
```

---

## 3. Detailed Architectural Calls

### P1: Line-Start Marker Anchoring & Markdown Structure Exclusion (D1)
- In `scripts/ci/review_recorder.py`, a comment body pre-processing function (`strip_markdown_structures(body: str) -> str`) runs before any marker scanning.
- Lines within code fences (opening and closing with ```` ``` ```` or `~~~`), indented code blocks (lines prefixed by 4 spaces or a tab), and blockquotes (lines starting with `>`) are stripped or replaced with empty lines (preserving line counting/positioning).
- All verdict marker regular expressions are anchored to line start: `^[[:space:]]*<!-- (review-verdict|reviewed-head|run-id|round|finding|failure-scenario|review-verdict-end)... -->`.

### P2: Comment Author-to-Reviewer Binding Prior to Block Matching (D2)
- In `scripts/ci/review_recorder.py`, `extract_verdict_blocks` maps the authenticated `comment.user.login` to the expected reviewer persona:
  - `evekhm-argus-app[bot]` -> `argus`
  - `evekhm-atlas-app[bot]` -> `atlas`
- If the author is neither, the comment cannot open a valid verdict block. If a verdict block is detected in an unauthorized comment, an author mismatch refusal is recorded.
- If the author matches a known reviewer, the search pattern matches solely opening markers for that reviewer:
  `^[[:space:]]*<!-- review-verdict:{expected_reviewer}:(clean|findings) -->`
  preventing foreign reviewer markers from opening blocks and resolving the PR #316 defect.

### P3: Loud Machine-Readable Refusal Markers Across All Declines (D3)
- In `scripts/ci/review_recorder.py`, `record_refusal(reviewer, reviewed_head, reason, code)` records machine-readable markers in the consensus ledger block:
  `<!-- refused-verdict:<reviewer>:<reviewed_head>:<reason_code> -->`
- Refusal reason codes:
  - `author-mismatch`: Comment author login does not match reviewer persona.
  - `missing-reviewed-head`: Verdict block omits `reviewed-head` marker or provides a malformed non-hex SHA.
  - `commit-not-in-history`: `reviewed_head` is not present in PR commit history.
  - `run-head-sha-mismatch`: Workflow run `head_sha` does not match `reviewed_head`.
  - `missing-run-id` / `malformed-run-id`: Invalid or missing `run-id`.
  - `run-ended-failure` / `run-ended-cancelled`: Provenance workflow run did not succeed.
- Attributed human-readable audit notes are appended under `#### Notes` in the ledger markdown.

### P4: Merge Gate Row Comparison & Ledger-Blindness Detection in Conjunct (3) (D4)
- In `scripts/ci/merge_gate.sh`, Conjunct (3) is augmented with an integrity verification step:
  1. Inspect `PR_COMMENTS` for comments authored by assigned reviewers (`ARGUS_LOGIN`, `ATLAS_LOGIN`) containing review verdict blocks outside markdown code fences and blockquotes.
  2. For reviews evaluating the current `$HEAD`, extract all posted finding identifiers: `<!-- finding:<fid>:... -->`.
  3. Compare each extracted `<fid>` against the parsed consensus ledger finding rows (`CTUP`).
  4. If a posted finding at `$HEAD` has no corresponding entry in `CTUP` and no refusal marker is recorded for that reviewer at `$HEAD`, Conjunct (3) evaluates false:
     ```bash
     C[3]=0
     WHY[3]="ledger blindness: reviewer <reviewer> posted finding <fid> at $HEAD with no ledger counterpart"
     ```
  5. If an explicit refusal marker is recorded (`<!-- refused-verdict:<reviewer>:$HEAD:<reason> -->`), the refusal diagnostic takes precedence:
     ```bash
     C[3]=0
     WHY[3]="<reviewer> verdict at $HEAD was refused by recorder (<reason>); ledger recorded head is <head>"
     ```

### P5: Line-Start Anchoring and Structure Exclusion for Retier Directives (D5)
- In `scripts/ci/review_recorder.py`, maintainer retier directives are scanned exclusively on stripped comment text (excluding code blocks and blockquotes) and anchored to line start:
  `^[[:space:]]*@(argus|atlas)\s+retier\s+([A-Za-z0-9@-]+)\s+([a-zA-Z0-9]+)[[:space:]]*$`
  preventing illustrative quotes and notes from demoting finding severities (PR #381).

### P6: Tracked Artifact Marker Sanitization Gate in `sanitize_check.sh` (D6)
- In `scripts/ci/sanitize_check.sh`, add rule `marker` alongside `home`, `secret`, and `vendor`.
- Rule `marker` flags unescaped live verdict markers:
  - `<!-- review-verdict:... -->`
  - `<!-- review-verdict-end -->`
  - `<!-- reviewed-head:... -->`
  - `<!-- run-id:... -->`
  - `<!-- round:... -->`
  - `<!-- finding:... -->`
  - `<!-- failure-scenario:... -->`
  - `<!-- consensus-ledger:... -->`
  - `<!-- consensus-ledger-end -->`
  - `<!-- loop-ledger:... -->`
  - `<!-- loop-ledger-row:... -->`
  - `<!-- loop-ledger-end -->`
  - `<!-- refused-verdict:... -->`
- Bracketed notation (e.g. `[review-verdict:...]`) is permitted in documentation without allowlisting.
- `scripts/ci/sanitize_allowlist.txt` supports `marker <path> # <reason>` exemptions for test suites and scanner sources.

### P7: Hermetic Historical Regression Suites (D7)
- Historical merged ledgers remain immutable.
- Defects PR #316, PR #317, and PR #381 are reproduced hermetically as test cases in `review_recorder_test.sh` and `merge_gate_test.sh`.

---

## 4. Micro-Stepped Tasks

### Task T1: Commit Contract Test Suites (Daedalus, build stage)
- **Files touched:**
  - `scripts/ci/tests/review_recorder_test.sh`
  - `scripts/ci/tests/merge_gate_test.sh`
  - `scripts/ci/tests/sanitize_check_test.sh`
- **Actions:**
  - Add 5 contract tests to `review_recorder_test.sh`:
    - `test_anchored_markers_and_markdown_exclusion` (AT-318-1, AT-318-2, D1, D7)
    - `test_author_to_reviewer_binding` (AT-318-3, D2, D7)
    - `test_unauthorized_author_refusal_marker` (AT-318-4, D2, D3)
    - `test_malformed_reviewed_head_refusal_marker` (AT-318-5, D3)
    - `test_anchored_maintainer_retier_directives` (AT-318-8, AT-318-9, D5, D7)
  - Add MG-50 and MG-51 scenarios to `merge_gate_test.sh`:
    - `MG-50` (AT-318-6, D4, D7)
    - `MG-51` (AT-318-7, D4, D7)
  - Add contract suite `sanitize_check_test.sh`:
    - `test_marker_rule_fails_on_live_verdict_marker` (AT-318-10, D6)
    - `test_bracketed_notation_passes_marker_rule` (AT-318-11, D6)
    - `test_marker_allowlist_exemption` (AT-318-10, D6)
    - `test_all_live_marker_variants_detected` (AT-318-10, D6)
- **Gate Check:** All new contract assertions fail cleanly on assertion logic (RED); existing baseline tests pass.

---

### Task T2: Implement Anchored Marker Parsing, Markdown Structure Exclusion, Author Binding, and Refusal Markers in `scripts/ci/review_recorder.py` (Odyssey, implement stage)
- **Risk:** High (`risk: high`, DEEP-3, DEEP-5)
- **Files touched:** `scripts/ci/review_recorder.py`
- **Actions:**
  1. Add `strip_markdown_structures(text: str) -> str` to strip lines within code blocks (```` ``` ````, `~~~`), indented blocks (4 spaces or tab), and blockquotes (`>`).
  2. Anchor all marker regular expressions to line start: `^[[:space:]]*<!-- ... -->`.
  3. In `extract_verdict_blocks(comments, pr_commits)`:
     - Map `comment.user.login` to expected reviewer.
     - Only search for `<!-- review-verdict:{expected_reviewer}:... -->`.
     - Reject unauthorized comments and emit code `author-mismatch`.
     - Reject missing or malformed `reviewed-head` and emit code `missing-reviewed-head`.
  4. In `record_refusal(reviewer, reviewed_head, reason, code)`:
     - Ensure machine-readable `<!-- refused-verdict:<reviewer>:<reviewed_head>:<reason_code> -->` is recorded in the consensus ledger comment.
- **Proof:**
  `bash scripts/ci/tests/review_recorder_test.sh -k test_anchored_markers_and_markdown_exclusion`  
  `bash scripts/ci/tests/review_recorder_test.sh -k test_author_to_reviewer_binding`  
  `bash scripts/ci/tests/review_recorder_test.sh -k test_unauthorized_author_refusal_marker`  
  `bash scripts/ci/tests/review_recorder_test.sh -k test_malformed_reviewed_head_refusal_marker`  
  All turn GREEN.

---

### Task T3: Implement Anchored Maintainer Retier Directives in `scripts/ci/review_recorder.py` (Odyssey, implement stage)
- **Risk:** Low
- **Files touched:** `scripts/ci/review_recorder.py`
- **Actions:**
  - In `scan_maintainer_retiers`, apply `strip_markdown_structures` and anchor directive regex:
    `^[[:space:]]*@(argus|atlas)\s+retier\s+([A-Za-z0-9@-]+)\s+([a-zA-Z0-9]+)[[:space:]]*$`
- **Proof:**
  `bash scripts/ci/tests/review_recorder_test.sh -k test_anchored_maintainer_retier_directives` turns GREEN.

---

### Task T4: Implement Conjunct (3) Ledger-Blindness Row Comparison in `scripts/ci/merge_gate.sh` (Odyssey, implement stage)
- **Risk:** High (`risk: high`, DEEP-3, DEEP-5)
- **Files touched:** `scripts/ci/merge_gate.sh`
- **Actions:**
  1. Define `ARGUS_LOGIN="${ARGUS_LOGIN:-evekhm-argus-app[bot]}"`.
  2. In Conjunct (3) evaluation:
     - Extract findings posted at `$HEAD` by assigned reviewers outside markdown code blocks and blockquotes.
     - Compare extracted `<fid>` against parsed ledger rows `CTUP`.
     - If a posted finding at `$HEAD` has no ledger counterpart and no refusal marker for that reviewer at `$HEAD`, fail Conjunct (3) with `WHY[3]="ledger blindness: reviewer <reviewer> posted finding <fid> at $HEAD with no ledger counterpart"`.
     - Ensure refusal markers take precedence over ledger blindness when a refusal is recorded.
- **Proof:**
  `bash scripts/ci/tests/merge_gate_test.sh` runs MG-50 and MG-51 GREEN; all scenarios pass.

---

### Task T5: Implement `marker` Rule in `scripts/ci/sanitize_check.sh` and Update `scripts/ci/sanitize_allowlist.txt` (Odyssey, implement stage)
- **Risk:** Low
- **Files touched:**
  - `scripts/ci/sanitize_check.sh`
  - `scripts/ci/sanitize_allowlist.txt`
- **Actions:**
  1. Add rule `marker` to allowlist parsing logic in `scripts/ci/sanitize_check.sh` (permitting `home`, `secret`, `vendor`, and `marker`).
  2. Implement `marker` scan rule in `scripts/ci/sanitize_check.sh` detecting unescaped HTML comment markers.
  3. Add necessary allowlist entries in `scripts/ci/sanitize_allowlist.txt` for files implementing or testing marker mechanics.
- **Proof:**
  `bash scripts/ci/tests/sanitize_check_test.sh` runs 4 passed out of 4 (GREEN).  
  `bash scripts/ci/sanitize_check.sh` passes with exit 0.

---

### Task T6: Living Specification Upsert in `docs/SPEC.md` and `CHANGELOG.md` (Odyssey, implement stage)
- **Risk:** Low (Documentation)
- **Files touched:**
  - `docs/SPEC.md`
  - `CHANGELOG.md`
- **Actions:**
  1. Upsert `### review.recorder` in `docs/SPEC.md` documenting line-start anchoring, markdown structure exclusion, author-to-reviewer binding, and machine-readable refusal markers.
  2. Upsert `### review.policy` in `docs/SPEC.md` documenting the merge gate ledger-blindness check in Conjunct (3).
  3. Append entry to `CHANGELOG.md`.
- **Proof:** `git diff docs/SPEC.md CHANGELOG.md` reflects D1–D8.

---

### Task T7: CI Gates and Full Regression Suite Verification (Odyssey, implement stage)
- **Risk:** Low
- **Actions:**
  Run the full repository validation suite:
  ```bash
  bash scripts/ci/sanitize_check.sh
  bash scripts/ci/tests/review_recorder_test.sh
  bash scripts/ci/tests/merge_gate_test.sh
  bash scripts/ci/tests/sanitize_check_test.sh
  ```
- **Proof:** All suites pass with exit 0.

---

## 5. Traceability Matrix

| Acceptance Criterion | Decision ID(s) | Contract Test / Scenario Proof | Implementing Task | Verification Proof |
| :--- | :--- | :--- | :--- | :--- |
| **AT-318-1** | D1, D7 | `review_recorder_test.sh::test_anchored_markers_and_markdown_exclusion` | T2 | Quoted / fenced / indented verdict blocks ignored; authentic findings recorded |
| **AT-318-2** | D1 | `review_recorder_test.sh::test_anchored_markers_and_markdown_exclusion` | T2 | Unanchored mid-line marker ignored; does not open verdict block |
| **AT-318-3** | D2, D7 | `review_recorder_test.sh::test_author_to_reviewer_binding` | T2 | PR #316 regression fixture: Argus quoting Atlas block does not trigger author mismatch; Argus findings recorded |
| **AT-318-4** | D2, D3 | `review_recorder_test.sh::test_unauthorized_author_refusal_marker` | T2 | Unauthorized comment author emits `refused-verdict:<reviewer>:<sha>:author-mismatch` |
| **AT-318-5** | D3 | `review_recorder_test.sh::test_malformed_reviewed_head_refusal_marker` | T2 | Missing/malformed reviewed-head emits `refused-verdict:<reviewer>:.*:missing-reviewed-head` |
| **AT-318-6** | D4, D7 | `merge_gate_test.sh::MG-50` | T4 | Conjunct (3) fails closed with ledger-blindness diagnostic when posted finding has no ledger counterpart |
| **AT-318-7** | D4, D7 | `merge_gate_test.sh::MG-51` | T4 | Conjunct (3) does not trigger ledger blindness when finding matches CTUP or refusal marker recorded |
| **AT-318-8** | D5, D7 | `review_recorder_test.sh::test_anchored_maintainer_retier_directives` | T3 | PR #381 regression fixture: Quoted retier directive does not alter finding severity |
| **AT-318-9** | D5 | `review_recorder_test.sh::test_anchored_maintainer_retier_directives` | T3 | Line-anchored maintainer retier outside code blocks updates finding severity |
| **AT-318-10** | D6 | `sanitize_check_test.sh::test_marker_rule_fails_on_live_verdict_marker` | T5 | Tracked live verdict markers trigger `marker` rule failure unless allowlisted |
| **AT-318-11** | D6 | `sanitize_check_test.sh::test_bracketed_notation_passes_marker_rule` | T5 | Documentation using bracketed notation passes `marker` scan with exit 0 |
| **AT-318-12** | D7 | All contract test suites | T1–T7 | All contract tests run hermetically without external network or API calls |

---

## 6. Handoff to Odyssey (Implement Stage)

Upon merge of this plan and contract tests PR, the issue advances to `status:implementing`.

**Branch:** `odyssey/318-consensus-recorder-admits-verdict`  
**Base Commit:** Pinned SHA of merged Daedalus PR  
**PR Title:** `feat(consensus): anchored verdict marker parsing and loud declines in review recorder (#318)`  
**PR Body Requirements:**
- Must include closing / referencing statement: `Refs #318` (autonomous merge gate merges PR).
- Must apply the deep review grant:
  ```bash
  scripts/ops/post.sh <pr-number> --as odyssey --add-label deep-review
  ```
- Must cite Decisions D1–D9 and Acceptance Criteria AT-318-1–AT-318-12.
- Must verify all test suites execute cleanly to green.
