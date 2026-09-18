# Plan: Unified Slug Derivation and Folder Reuse (#463)

- **Issue:** #463 (`claim.sh and work.sh derive different slugs from one issue title`)
- **Spec:** `intent/463-claim-sh-and-work-sh/spec.md` (Approved, PR #524)
- **Decisions:** D1, D2, D3, D4, D5, D6, D7, D8
- **Acceptance Criteria:** AT-463-1 through AT-463-11
- **Architect (Author):** Daedalus (`evekhm-daedalus-app[bot]`)
- **Base Commit:** `8dd91e8cd02a1a45cff919f8ead61569cb3c7734` (`origin/main`, merge of PR #524)
- **Implementation Persona:** Odyssey (`evekhm-odyssey-app[bot]`)
- **Target Branch for Implementation:** `odyssey/463-claim-sh-and-work-sh`

---

## 1. Executive Summary & Problem Statement

`scripts/ops/claim.sh` and `scripts/ops/work.sh` currently maintain separate, diverging implementations of issue slug derivation:
1. `claim.sh` (lines 190–202) uses a 40-character cap on word boundaries with no colon/semicolon trimming.
2. `work.sh` (lines 527–542) cuts titles at the first colon (`:`) or semicolon (`;`) and caps length at 24 characters on word boundaries (#36 D6 / `personas/skills/resume-protocol.md`).
3. On cold dispatch (e.g. issue #457 `README: add a worked /idea, /claim, /work walkthrough`), `claim.sh 457` creates branch `tester/457-readme-add-a-worked-idea-claim-work`, while `work.sh 457` resolves folder `intent/457-readme/` and branch `odyssey/457-readme`.
4. Furthermore, `claim.sh` does not inspect existing `intent/<n>-*/` directories before deriving from title, allowing branch names to diverge from committed intent directories.

This plan unifies slug derivation into a shared, pure-bash library `scripts/ops/lib/slug.sh`, standardizes on the canonical 24-character colon/semicolon-cut rule, introduces folder reuse in `claim.sh`, updates integration tests, and aligns the living specification in `docs/SPEC.md`.

---

## 2. Scope, Persona Boundaries, and Review Grants

### Persona Authority Boundaries

| Persona | Lifecycle Stage | Permitted Write Surface | Bounds & Responsibilities |
|---|---|---|---|
| **Athena** | `plan`, `design` | `intent/**` | Produced `intent.md` and `spec.md` (Approved in PR #524). |
| **Daedalus** | `build` | `intent/**`, `scripts/*/tests/**` | Commits `plan.md` and red contract test suite `scripts/ops/tests/slug_unification_contract_test.sh`. Never touches production code (`scripts/ops/*.sh`, `scripts/ops/lib/*.sh`). |
| **Odyssey** | `implement` | `scripts/ops/**`, `docs/SPEC.md`, `CHANGELOG.md` | Implements `scripts/ops/lib/slug.sh`, updates `claim.sh`, `work.sh`, unit and integration tests, living spec, and changelog. |
| **Atlas / Argus** | `review` | PR review comments, labels | Evaluates implementation against spec and plan; assigns review verdicts. |
| **Themis** | Advancer / Gate | Stage labels, merges | Verifies CI gates, fast-forward merges PR, advances lifecycle label. |

### Deep Review Grant Assessment

Policy and criteria for applying the `deep-review` grant (`personas/skills/deep-review.md`):

- **DEEP-1 (Trust-bearing paths):** **MET.** The diff modifies `scripts/ops/claim.sh`, `scripts/ops/work.sh`, `scripts/ops/lib/slug.sh`, and `scripts/ops/tests/**`, which are paths under `config/execution.yaml` `assigned_when.paths` for Argus. Forces Argus assignment and lifts the round-scope cap.
- **DEEP-2 (Size):** Not met (diff is ~200 lines outside tests).
- **DEEP-3 (Irreversible or privileged operations):** Not met (no external writes, credential minting, or irreversible mutations).
- **DEEP-4 (Plan deviation or spec-changing repair):** Not met.
- **DEEP-5 (Escalated tier / risk: high):** **MET.** Task T2 modifies `scripts/ops/claim.sh` (worktree and branch mutex logic), marked `risk: high`.
- **DEEP-6 (Review history):** Not met at build time.
- **DEEP-7 (Compiler blast radius):** Not met (no persona source or compiler skill touched).

**Grant Assignment:** Daedalus designates the implementation PR under **DEEP-1** and **DEEP-5**. Odyssey must inherit and ensure the `deep-review` grant is recorded.

### Living Spec and Changelog Obligations

- **Living Spec (`docs/SPEC.md`):** Updated under `### ops.claim` (new section) and `### ops.dispatch` to document unified slug derivation, existing folder reuse in `claim.sh`, and refusal of conflicting explicit slugs (Decision D7, AT-463-10).
- **Changelog (`CHANGELOG.md`):** Updated under unreleased entries with a clear summary referencing #463 and PR #524.

### Strict File Manifest Partitioning

- **Permitted for Build Stage (Daedalus):**
  - `intent/463-claim-sh-and-work-sh/plan.md`
  - `scripts/ops/tests/slug_unification_contract_test.sh`
- **Permitted for Implement Stage (Odyssey):**
  - `scripts/ops/lib/slug.sh` (new)
  - `scripts/ops/claim.sh`
  - `scripts/ops/work.sh`
  - `scripts/ops/tests/slug_test.sh` (new)
  - `scripts/ops/tests/claim_test.sh`
  - `scripts/ops/tests/work_test.sh`
  - `docs/SPEC.md`
  - `CHANGELOG.md`
- **Strictly Forbidden Paths (Both personas):**
  - `personas/**`
  - `.claude/agents/*`
  - `.agents/*`
  - `.github/workflows/*`

---

## 3. Order of Work

```
  +-------------------------------------------------------------+
  | T1: Author scripts/ops/lib/slug.sh (D1, D2, D3)             |
  +-------------------------------------------------------------+
                                 |
                                 v
  +-------------------------------------------------------------+
  | T2: Update scripts/ops/claim.sh (D1, D2, D3, D5) [HIGH RISK]|
  +-------------------------------------------------------------+
                                 |
                                 v
  +-------------------------------------------------------------+
  | T3: Update scripts/ops/work.sh (D1, D2, D5)                 |
  +-------------------------------------------------------------+
                                 |
                                 v
  +-------------------------------------------------------------+
  | T4: Author hermetic unit test scripts/ops/tests/slug_test.sh|
  +-------------------------------------------------------------+
                                 |
                                 v
  +-------------------------------------------------------------+
  | T5: Update integration tests (claim_test.sh, work_test.sh)  |
  +-------------------------------------------------------------+
                                 |
                                 v
  +-------------------------------------------------------------+
  | T6: Verify contract test slug_unification_contract_test.sh  |
  +-------------------------------------------------------------+
                                 |
                                 v
  +-------------------------------------------------------------+
  | T7: Update docs/SPEC.md (ops.claim, ops.dispatch) (D7)       |
  +-------------------------------------------------------------+
                                 |
                                 v
  +-------------------------------------------------------------+
  | T8: CHANGELOG.md and Full CI Gate Regression Suite          |
  +-------------------------------------------------------------+
```

---

## 4. Micro-Stepped Tasks

### Task T1: Shared Library `scripts/ops/lib/slug.sh` (D1, D2, D3)
- **Target:** `scripts/ops/lib/slug.sh` (new file)
- **Decisions Satisfied:** D1, D2, D3
- **Acceptance Criteria:** AT-463-1, AT-463-2, AT-463-3, AT-463-4, AT-463-9
- **Details:**
  1. Create `scripts/ops/lib/slug.sh` with header explaining its role as a pure-bash sourced library without `gh` CLI, git remote, or network dependencies.
  2. Implement `derive_slug()`:
     - Input: `$1` (title or text).
     - Cut at the first colon (`:`) or semicolon (`;`) using bash parameter expansion (`${s%%:*}`; `${s%%;*}`).
     - Lowercase the string via `tr '[:upper:]' '[:lower:]'`.
     - Replace any characters outside `[a-z0-9]` with hyphens via `tr -cs 'a-z0-9' '-'`.
     - Trim leading and trailing hyphens.
     - If length > 24 characters:
       - Truncate to 24 characters (`cut="${s:0:24}"`).
       - Truncate at the last hyphen (`trimmed="${cut%-*}"`).
       - If `trimmed` is non-empty and not equal to `cut`, use `trimmed`; else use `cut` with trailing hyphen trimmed (`${cut%-}`).
     - Return the sanitized slug on stdout.
  3. Implement `resolve_issue_slug()`:
     - Signature: `resolve_issue_slug <repo_root> <issue_num> [<explicit_slug>] [<issue_title>]`
     - Inspect `$repo_root/intent/$issue_num-*/`.
     - If count == 0:
       - If `explicit_slug` is non-empty, return `derive_slug "$explicit_slug"`.
       - Else if `issue_title` is non-empty, return `derive_slug "$issue_title"`.
       - Else emit error on stderr and return 1.
     - If count == 1:
       - Extract folder slug (`basename`, strip `$issue_num-`).
       - If `explicit_slug` is non-empty:
         - Derive `norm_explicit="$(derive_slug "$explicit_slug")"`.
         - If `norm_explicit != folder_slug`: emit diagnostic to stderr `slug: conflicting explicit slug '$explicit_slug' does not match existing intent folder '$folder_slug' for #$issue_num` and return 2.
       - Return `folder_slug`.
     - If count > 1:
       - Emit diagnostic to stderr `#$issue_num has more than one intent folder: ...` and return 2.
- **Verification:**
  ```bash
  bash -c '. scripts/ops/lib/slug.sh && [ "$(derive_slug "README: add walkthrough")" = "readme" ] && echo OK'
  ```

---

### Task T2: Update `scripts/ops/claim.sh` for Sourcing and Folder Reuse (D1, D2, D3, D5) [risk: high]
- **Target:** `scripts/ops/claim.sh`
- **Decisions Satisfied:** D1, D2, D3, D5
- **Acceptance Criteria:** AT-463-1, AT-463-2, AT-463-3, AT-463-4, AT-463-5, AT-463-6, AT-463-7
- **Details:**
  1. In `scripts/ops/claim.sh`, source `scripts/ops/lib/slug.sh` after defining or discovering `$SCRIPT_DIR` or relative to `$ROOT`.
     ```bash
     # shellcheck source=lib/slug.sh
     . "$ROOT/scripts/ops/lib/slug.sh" || . "$SCRIPT_DIR/lib/slug.sh"
     ```
  2. Remove inline definition of `derive_slug` (lines 190–202).
  3. Replace the slug assignment logic (around lines 204–214):
     - Call `resolve_issue_slug "$ROOT" "$NUMBER" "$SLUG" "$title"`.
     - Check exit status: if rc == 2, refuse with the emitted diagnostic and exit 2 (satisfying AT-463-6 and AT-463-7).
     - Set `SLUG` to the resolved slug.
     - Validate that `[ -n "$SLUG" ]`, else `die "cannot derive a worktree slug for #$NUMBER"`.
  4. Ensure existing worktree and branch creation logic uses this unified `SLUG`.
- **Verification:**
  ```bash
  DRY_RUN=1 scripts/ops/claim.sh 463
  # Verify output branch matches the existing intent folder slug intent/463-claim-sh-and-work-sh/
  ```

---

### Task T3: Update `scripts/ops/work.sh` to Source `slug.sh` (D1, D2, D5)
- **Target:** `scripts/ops/work.sh`
- **Decisions Satisfied:** D1, D2, D5
- **Acceptance Criteria:** AT-463-1, AT-463-2, AT-463-3, AT-463-4
- **Details:**
  1. In `scripts/ops/work.sh`, source `scripts/ops/lib/slug.sh` using `$REPO_ROOT/scripts/ops/lib/slug.sh`.
  2. Remove the inline `derive_slug` definition (lines 527–542).
  3. Ensure `folder` and `slug` resolution delegates to `resolve_issue_slug` or uses the sourced `derive_slug`.
  4. Maintain existing fix-round override (`pr_head_slug`) intact (lines 564–566).
- **Verification:**
  ```bash
  DRY_RUN=1 scripts/ops/work.sh 463
  # Verify derived output matches folder intent/463-claim-sh-and-work-sh/
  ```

---

### Task T4: Hermetic Unit Test Suite `scripts/ops/tests/slug_test.sh` (D1, D2, D6)
- **Target:** `scripts/ops/tests/slug_test.sh` (new file)
- **Decisions Satisfied:** D1, D2, D6
- **Acceptance Criteria:** AT-463-1, AT-463-2, AT-463-3, AT-463-4, AT-463-9
- **Details:**
  1. Author `scripts/ops/tests/slug_test.sh` following the hermetic test harness standard.
  2. Implement unit tests covering all edge cases:
     - Title with colon: `ops: claim.sh -- one command` -> `ops`
     - Title with semicolon: `Execution model; where does it run?` -> `execution-model`
     - Title with non-alphanumeric chars: `Fix #123: bad (really bad!) bug` -> `fix`
     - Title <= 24 characters: `clean short title` -> `clean-short-title`
     - Title > 24 chars truncated at word boundary: `Abcdefghij klmnopqrst uvwxyz0123 456789ab` -> `abcdefghij-klmnopqrst` (<=24 chars)
     - Long single word without hyphens: `Supercalifragilisticexpialidocious` -> 24-char cut
     - Leading/trailing symbols and repeated dashes: `---Test...Slug---` -> `test-slug`
     - Empty string / no usable alphanumeric chars -> returns empty / error
     - `resolve_issue_slug` with 0 folders -> derives from title
     - `resolve_issue_slug` with 1 folder -> reuses folder slug
     - `resolve_issue_slug` with 1 folder and conflicting explicit slug -> exits 2
     - `resolve_issue_slug` with 1 folder and matching explicit slug -> exits 0, returns folder slug
     - `resolve_issue_slug` with 2 folders -> exits 2
  3. Ensure script runs hermetically without `gh` or network dependencies (`PATH="/usr/bin:/bin"` clean environment).
- **Verification:**
  ```bash
  bash scripts/ops/tests/slug_test.sh
  ```

---

### Task T5: Update Integration Tests in `claim_test.sh` and `work_test.sh` (D3, D6)
- **Target:** `scripts/ops/tests/claim_test.sh`, `scripts/ops/tests/work_test.sh`
- **Decisions Satisfied:** D3, D6
- **Acceptance Criteria:** AT-463-4, AT-463-5, AT-463-6, AT-463-7
- **Details:**
  1. In `scripts/ops/tests/claim_test.sh`:
     - Update banner `"a long title is cut to 40 characters on a word boundary"` (lines 270–274):
       Change expected slug from 40 characters (`tester/112-abcdefghij-klmnopqrst-uvwxyz0123`) to 24 characters (`tester/112-abcdefghij-klmnopqrst`).
     - Add test: Title with colon cuts at colon (`ops: claim.sh` -> `ops`).
     - Add test: Title with semicolon cuts at semicolon (`Execution model; where` -> `execution-model`).
     - Add test: Existing folder reuse in `claim.sh` (`intent/113-my-folder/` exists -> slug is `my-folder`).
     - Add test: Conflicting explicit slug when intent folder exists refuses with exit 2.
     - Add test: Multiple intent folders refuse with exit 2.
  2. In `scripts/ops/tests/work_test.sh`:
     - Confirm all existing tests pass under the sourced `scripts/ops/lib/slug.sh`.
     - In `fixture_tree()` (lines 227–252), ensure `scripts/ops/lib` is copied into the fixture tree so `work.sh` can source `slug.sh`.
- **Verification:**
  ```bash
  bash scripts/ops/tests/claim_test.sh
  bash scripts/ops/tests/work_test.sh
  ```

---

### Task T6: Verification of Contract Test Suite (D1–D8, AT-463-1 through AT-463-11)
- **Target:** `scripts/ops/tests/slug_unification_contract_test.sh`
- **Decisions Satisfied:** D1, D2, D3, D4, D5, D6, D7, D8
- **Acceptance Criteria:** AT-463-1 through AT-463-11
- **Details:**
  1. Run `bash scripts/ops/tests/slug_unification_contract_test.sh`.
  2. Verify all 11 assertions turn from RED (failures at build rung) to GREEN (11 passed, 0 failures, exit code 0).
- **Verification:**
  ```bash
  bash scripts/ops/tests/slug_unification_contract_test.sh
  ```

---

### Task T7: Update Living Specification in `docs/SPEC.md` (D7)
- **Target:** `docs/SPEC.md`
- **Decisions Satisfied:** D7
- **Acceptance Criteria:** AT-463-10
- **Details:**
  1. Add `### ops.claim` section to `docs/SPEC.md` documenting:
     - `scripts/ops/claim.sh <issue> [<slug>]` claims an issue, creates a worktree, and writes labels/comments.
     - Slug resolution order (#463): inspects `intent/<n>-*/` first; reuses existing folder slug if exactly one exists; refuses with exit 2 if multiple exist; derives via `derive_slug` from title if none exist.
     - Refuses with exit 2 if caller supplies an explicit slug that contradicts an existing intent folder slug.
     - Canonical derivation rule: 24-character colon/semicolon-cut rule provided by `scripts/ops/lib/slug.sh`.
     - Refusal codes and ordering.
     - Tests: `scripts/ops/tests/claim_test.sh`, `scripts/ops/tests/slug_test.sh`.
  2. Update `### ops.dispatch` section in `docs/SPEC.md`:
     - Reference `scripts/ops/lib/slug.sh` for unified slug derivation (#463).
     - State that `claim.sh` and `work.sh` share the identical derivation rules.
  3. Validate living spec consistency using `scripts/ci/spec_check.sh`.
- **Verification:**
  ```bash
  bash scripts/ci/spec_check.sh origin/main
  ```

---

### Task T8: CHANGELOG.md and Full CI Gate Regression Suite (D8)
- **Target:** `CHANGELOG.md`, full repository test suite
- **Decisions Satisfied:** D8
- **Acceptance Criteria:** AT-463-11
- **Details:**
  1. Add an entry under `## [Unreleased]` in `CHANGELOG.md`:
     - Describe unification of slug derivation across `claim.sh` and `work.sh` into `scripts/ops/lib/slug.sh` (#463).
     - Note the canonical 24-character colon/semicolon-cut rule and intent folder reuse in `claim.sh`.
  2. Verify changelog formatting: `bash scripts/ci/changelog_check.sh origin/main`.
  3. Execute full gate verification suite (see Section 5 below).
  4. Ensure zero diff in forbidden paths (`personas/**`, `.claude/agents/*`, `.agents/*`, `.github/workflows/*`).

---

## 5. Verification Commands and Expected Results

Odyssey must run and verify the following commands before opening the implementation pull request:

```bash
# 1. Hermetic unit tests for slug library
bash scripts/ops/tests/slug_test.sh
# Expected: Exit code 0, all assertions pass

# 2. Integration test for claim.sh
bash scripts/ops/tests/claim_test.sh
# Expected: Exit code 0, all assertions pass

# 3. Integration test for work.sh
bash scripts/ops/tests/work_test.sh
# Expected: Exit code 0, all assertions pass

# 4. Contract test for slug unification (#463)
bash scripts/ops/tests/slug_unification_contract_test.sh
# Expected: Total assertions: 11, Passed: 11, Failed: 0, ALL TESTS PASSED, exit 0

# 5. Suite integrity proof
bash scripts/ops/tests/suite_integrity_test.sh
# Expected: ALL SUITE INTEGRITY PROOFS PASSED, exit 0

# 6. Living spec check
bash scripts/ci/spec_check.sh origin/main
# Expected: Exit code 0

# 7. Changelog format check
bash scripts/ci/changelog_check.sh origin/main
# Expected: Exit code 0

# 8. Sanitize check
bash scripts/ci/sanitize_check.sh
# Expected: Exit code 0

# 9. Execution config check
python3 scripts/ops/execution.py --check
# Expected: Exit code 0

# 10. Scope boundary audit
git diff --name-only origin/main | grep -E '^personas/|^\.claude/agents/|^\.agents/|^\.github/workflows/' && exit 1 || echo "Scope boundary clean"
# Expected: "Scope boundary clean", exit code 0
```
