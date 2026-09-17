# Spec: Unified Slug Derivation Across claim.sh and work.sh

**Issue:** #463
**Status:** Approved (approval = merge of this PR)
**Author:** athena (`evekhm-athena-app[bot]`)
**Open questions:** none

## What is being built

`scripts/ops/claim.sh` and `scripts/ops/work.sh` historically maintained separate implementations of slug derivation.
`claim.sh` derived slugs from the full issue title with a 40-character limit, without cutting at colons or semicolons, and without checking whether an `intent/<issue>-<slug>/` folder already existed.
`work.sh` implemented the canonical rule specified in #36 D6, `docs/SPEC.md` (`ops.dispatch`), and `personas/skills/resume-protocol.md`: cutting at the first colon or semicolon, lowercasing, replacing non-alphanumeric characters with hyphens, and capping at 24 characters on a word boundary; furthermore, `work.sh` prioritized folder reuse (`reuse beats derive`).

This disagreement caused four operational issues:
1. **Branch divergence:** An operator or automated session claiming an issue via `claim.sh` received a worktree on `<actor>/<n>-<40-char-slug>`, while `work.sh` and the intent folder used `<actor>/<n>-<24-char-slug>`.
2. **Lifecycle advance stalls and near-misses:** When pull requests opened from 40-character branches merged, `scripts/ci/lifecycle_advance.sh` detected that the head branch slug differed from the existing `intent/<n>-<folder_slug>/` directory on main. This triggered a near-miss failure under #57 D17 and refused to advance the stage ladder. Documented incidents include PR #371 on #337 (advanced manually by the advisor), #410 with PR #427 (stalled at `status:implementing`), and #44.
3. **Cold-start divergence:** Two sessions claiming or dispatching on the same cold issue before an intent directory existed derived different directory names and branch targets.
4. **Duplicated code:** `derive_slug` logic was defined independently in multiple scripts.

This specification establishes:
1. **Shared Library Module:** A dedicated library `scripts/ops/lib/slug.sh` defining pure-bash helper functions `derive_slug` and `resolve_issue_slug`.
2. **Consolidated Canonical Derivation Rule:** Consolidation on the canonical 24-character colon/semicolon-cut rule from #36 D6 and `personas/skills/resume-protocol.md` as the single system standard.
3. **Folder-Reuse Enforcement in `claim.sh`:** Before deriving from a title, `claim.sh` inspects the repository for an existing `intent/<n>-*/` directory. If exactly one directory exists, its slug is reused. If more than one exists, `claim.sh` refuses with exit code 2. If an explicit slug argument conflicts with an existing directory, `claim.sh` refuses with exit code 2.
4. **Transition Compatibility:** In-flight branches and worktrees remain valid without forced renaming. `issue_inference.sh` continues to resolve issue numbers from both legacy and new worktree and branch names.
5. **Consolidated Test Coverage:** `claim_test.sh` and `work_test.sh` assert consistent slug derivation and folder reuse, supported by a hermetic unit test `scripts/ops/tests/slug_test.sh`.
6. **Living Documentation:** `docs/SPEC.md` updated under `ops.claim` and `ops.dispatch` to document the unified behavior.

### Manifest of Files Touched by the Implementation Rung

- `scripts/ops/lib/slug.sh`: New shared library implementing `derive_slug` and `resolve_issue_slug`.
- `scripts/ops/claim.sh`: Sources `slug.sh`, removes duplicate `derive_slug`, and enforces folder reuse.
- `scripts/ops/work.sh`: Sources `slug.sh` and removes duplicate `derive_slug`.
- `scripts/ops/tests/claim_test.sh`: Asserts folder reuse and unified 24-character colon-cut derivation.
- `scripts/ops/tests/work_test.sh`: Asserts delegation to unified derivation.
- `scripts/ops/tests/slug_test.sh`: New hermetic unit test suite for `derive_slug` and `resolve_issue_slug`.
- `docs/SPEC.md`: Updates `ops.claim` and `ops.dispatch` with unified slug derivation and folder reuse rules.
- `CHANGELOG.md`: Records unified slug derivation and folder reuse in `claim.sh`.
- `intent/463-claim-sh-and-work-sh/plan.md`: Implementation plan authored by Daedalus.
- `intent/463-claim-sh-and-work-sh/spec.md`: This specification.

### Manifest of Files Touched by this PR (Athena)

- `intent/463-claim-sh-and-work-sh/spec.md`: This specification.

### Forbidden Files (Untouched)

- `personas/**`: Persona definitions remain untouched.
- `.claude/agents/*`: Compiled persona targets remain untouched.
- `.agents/*`: Compiled persona targets remain untouched.
- `.github/workflows/*`: Workflow definitions remain untouched.
- `config/**`: Execution configurations remain untouched.
- `scripts/ci/lifecycle_advance.sh`: Lifecycle advancer logic remains untouched.
- `scripts/ci/merge_gate.sh`: Merge gate logic remains untouched.

## Decisions

| ID | Decision | Rationale |
|---|---|---|
| **D1** | **Dedicated Shared Library at `scripts/ops/lib/slug.sh` (Resolves Open Question 3).** Slug derivation and folder-slug resolution functions are extracted into a dedicated library `scripts/ops/lib/slug.sh`. The library contains pure-bash functions without dependencies on the `gh` CLI, git remote operations, or external network services. `scripts/ops/claim.sh` and `scripts/ops/work.sh` source this file. | *Adversary analysis:* Two defensible readings: (1) Add slug functions to `scripts/ops/lib/github.sh`. (2) Create a dedicated lightweight library `scripts/ops/lib/slug.sh`. Differing case: Hermetic unit testing or offline execution of slug functions without the `gh` binary or network connectivity. Reading 1 introduces GitHub API dependencies and mock requirements into pure string processing. Reading 2 executes deterministically in pure bash with zero external dependencies. |
| **D2** | **Surviving Canonical Slug Derivation Rule: 24-Character Colon/Semicolon-Cut Standard (Resolves Open Question 1, Affirms #36 D6).** For cold starts where no `intent/<n>-*/` directory exists, `derive_slug "$title"` implements the following deterministic procedure: (a) cut the title at the first colon (`:`) or semicolon (`;`); (b) lowercase the resulting text; (c) replace every run of characters outside `[a-z0-9]` with a single hyphen (`-`); (d) trim leading and trailing hyphens; (e) if the string exceeds 24 characters, truncate to at most 24 characters at the last hyphen that leaves a non-empty string. If no hyphen exists within the first 24 characters, truncate to 24 characters and trim any trailing hyphen. | *Adversary analysis:* Two defensible readings: (1) Standardize on the 40-character whole-title rule from `claim.sh` (#87). (2) Standardize on the 24-character colon/semicolon-cut rule from #36 D6 and `personas/skills/resume-protocol.md`. Differing case: Issue #457 titled `README: add a worked /idea, /claim, /work walkthrough`. Under Reading 1, the cold derived slug is `readme-add-a-worked-idea-claim-work`, which reverses #36 D6, contradicts `docs/SPEC.md`, and requires recompiling all persona prompts across harnesses. Under Reading 2, the cold derived slug is `readme`, preserving alignment with #36 D6, `docs/SPEC.md`, and existing compiled persona instructions without drift. |
| **D3** | **Folder Reuse Precedence in `claim.sh` (Reuse Beats Derive, Resolves #382 and #443).** In `scripts/ops/claim.sh`, before deriving a slug from the issue title, the script inspects the repository root for directories matching `intent/<n>-*/`: (a) If exactly one matching directory exists, its slug is reused as `SLUG` (stripping the `<n>-` prefix), matching `work.sh` line 555 and AGENTS.md line 42; (b) If more than one matching directory exists, `claim.sh` refuses execution with exit code 2 naming the corrupted directories; (c) If no matching directory exists, `claim.sh` derives `SLUG` via `derive_slug "$title"`. If a caller passes an explicit slug positional argument `$2` when an `intent/<n>-*/` directory already exists, and the explicit slug differs from the existing folder slug, `claim.sh` refuses execution with exit code 2. | *Adversary analysis:* Two defensible readings: (1) Allow an explicit slug argument on `claim.sh` to override an existing `intent/<n>-<folder_slug>/` directory. (2) Enforce that an existing intent folder slug strictly overrides or rejects a conflicting explicit slug on `claim.sh`. Differing case: Issue #337 has existing directory `intent/337-poller-fix-round-queue/`. An operator runs `claim.sh 337 poller-fix-round-queue-selects-prs-by-a`. Under Reading 1, `claim.sh` creates a branch with the 40-character slug. When the pull request merges, `lifecycle_advance.sh` detects a slug mismatch and halts stage advancement. Under Reading 2, `claim.sh` detects the mismatch and refuses execution with exit code 2, preventing branch divergence. |
| **D4** | **Transition and Migration Policy: In-Flight Worktrees and Branches Preserved (Resolves Open Question 2).** Active branches and worktrees created prior to this unification remain valid and are not retroactively renamed or migrated. `scripts/ops/lib/issue_inference.sh` continues to infer the issue number from any conforming `<actor>-<n>-<slug>` worktree directory or `<actor>/<n>-<slug>` branch regardless of slug length or rule origin. | *Adversary analysis:* Two defensible readings: (1) Require automated migration or renaming of active branches and worktrees to conform to the 24-character colon-cut standard. (2) Preserve existing active branches and worktrees without renaming, enforcing the unified derivation only on new claims and cold starts. Differing case: An active session operates in worktree `.claude/worktrees/odyssey-410-changelog-md-with-a-hard-ci-merge-gate`. Under Reading 1, automated migration scripts rename the worktree and branch, invalidating in-flight editor states and open pull request references. Under Reading 2, the existing worktree and branch proceed to completion undisturbed, while new work items follow the unified derivation. |
| **D5** | **Sourcing and Integration Across Operational Scripts.** `scripts/ops/claim.sh` and `scripts/ops/work.sh` both source `scripts/ops/lib/slug.sh` and delegate slug derivation to `derive_slug`. The inline duplicate implementations of `derive_slug` in `scripts/ops/claim.sh` and `scripts/ops/work.sh` are deleted. | *Adversary analysis:* Two defensible readings: (1) Maintain separate inline implementations in `claim.sh` and `work.sh` kept in sync by convention. (2) Source a single shared implementation from `scripts/ops/lib/slug.sh`. Differing case: A character sanitization adjustment is made to handle specific punctuation. Under Reading 1, updating one script leaves the other untouched, causing subtle slug divergence. Under Reading 2, the update is made once in `slug.sh` and applies identically to all entry points. |
| **D6** | **Hermetic Unit Testing and Test Suite Consolidation.** `scripts/ops/tests/slug_test.sh` is introduced as a hermetic unit test validating `derive_slug` and `resolve_issue_slug` across title variants (colons, semicolons, special characters, length boundaries, consecutive dashes). `scripts/ops/tests/claim_test.sh` is updated to assert folder reuse and 24-character colon-cut derivation. `scripts/ops/tests/work_test.sh` is updated to verify sourcing from `slug.sh`. | *Adversary analysis:* Two defensible readings: (1) Rely solely on integration tests in `claim_test.sh` and `work_test.sh`. (2) Introduce `scripts/ops/tests/slug_test.sh` for fast, hermetic unit tests alongside updated integration tests. Differing case: A developer executes tests to verify slug trimming logic on edge cases. Under Reading 1, execution requires running full integration suites with mock environments. Under Reading 2, `slug_test.sh` executes directly in milliseconds. |
| **D7** | **Living Specification Updates in `docs/SPEC.md`.** `docs/SPEC.md` is updated under `ops.claim` and `ops.dispatch` to document: (a) existing folder reuse in `claim.sh`; (b) cold slug derivation using the canonical 24-character colon/semicolon-cut rule from `scripts/ops/lib/slug.sh`; (c) refusal of conflicting explicit slugs when an intent folder exists. | *Adversary analysis:* Two defensible readings: (1) Update only `ops.dispatch` in `docs/SPEC.md`. (2) Update both `ops.claim` and `ops.dispatch` in `docs/SPEC.md` to document folder reuse and unified derivation. Differing case: An operator consults `docs/SPEC.md` to check how `claim.sh` handles existing folders. Under Reading 1, `docs/SPEC.md` omits `claim.sh` folder reuse behavior. Under Reading 2, `docs/SPEC.md` provides explicit documentation of `claim.sh` folder reuse and slug derivation. |
| **D8** | **Strict Scope Boundary Enforcement.** The implementation rung is permitted to modify: `scripts/ops/lib/slug.sh`, `scripts/ops/claim.sh`, `scripts/ops/work.sh`, `scripts/ops/tests/claim_test.sh`, `scripts/ops/tests/work_test.sh`, `scripts/ops/tests/slug_test.sh`, `docs/SPEC.md`, `CHANGELOG.md`, `intent/463-claim-sh-and-work-sh/plan.md`, and `intent/463-claim-sh-and-work-sh/spec.md`. Persona sources (`personas/**`), compiled targets (`.claude/agents/*`, `.agents/*`), and workflow files (`.github/workflows/*`) remain strictly untouched. | *Adversary analysis:* Two defensible readings: (1) Permit modifying workflow files and persona prompt definitions. (2) Restrict modifications strictly to operational scripts, tests, living documentation, changelog, and intent files. Differing case: Scope audit of the implementing pull request. Under Reading 1, changes touch `personas/**` and `.github/workflows/**`, requiring elevated permissions and compiler synchronization. Under Reading 2, the diff remains strictly bounded to ops scripts, tests, `docs/SPEC.md`, `CHANGELOG.md`, and `intent/463-claim-sh-and-work-sh/*`. |

## Acceptance

- **AT-463-1 (D1, D2):** Cold derivation equality. For any issue title, `claim.sh` and `work.sh` produce identical slugs on cold start.
  - *Red input:* Supplying issue title `README: add a worked /idea, /claim, /work walkthrough` on a cold start produces different slugs in `claim.sh` and `work.sh`.
- **AT-463-2 (D2):** Colon cutting in slug derivation. An issue title with a colon derives a slug cut at the first colon.
  - *Red input:* Supplying title `ops: claim.sh -- one command` yields slug `ops-claim-sh`, failing to cut at the colon.
- **AT-463-3 (D2):** Semicolon cutting in slug derivation. An issue title with a semicolon derives a slug cut at the first semicolon.
  - *Red input:* Supplying title `Execution model; where does it run?` yields a slug containing words after the semicolon.
- **AT-463-4 (D2):** Length cap at 24 characters on word boundary. A title whose sanitized prefix exceeds 24 characters is truncated at the last hyphen at or before character 24.
  - *Red input:* Supplying title `A very long title that exceeds twenty-four characters` yields a slug longer than 24 characters.
- **AT-463-5 (D3):** Existing folder reuse in `claim.sh`. When an issue has an existing `intent/<n>-<folder_slug>/` directory, `claim.sh <n>` reuses `<folder_slug>` for the worktree and branch name.
  - *Red input:* An existing folder `intent/463-claim-sh-and-work-sh/` exists, but running `claim.sh 463` creates branch `actor/463-claim-sh-and-work-sh-derive-different`.
- **AT-463-6 (D3):** Conflicting explicit slug refusal in `claim.sh`. When an issue has `intent/<n>-<folder_slug>/` and the caller executes `claim.sh <n> <different_slug>`, `claim.sh` exits 2 without creating a worktree or modifying labels.
  - *Red input:* Executing `claim.sh 463 custom-slug` when `intent/463-claim-sh-and-work-sh/` exists creates a worktree and exits 0.
- **AT-463-7 (D3):** Multiple folder detection in `claim.sh`. When an issue has more than one `intent/<n>-*/` directory, `claim.sh` exits 2 naming the corrupted directories.
  - *Red input:* An issue with two intent folders succeeds or creates a worktree and exits 0.
- **AT-463-8 (D4):** Preserved in-flight worktree compatibility. `scripts/ops/lib/issue_inference.sh` resolves issue numbers correctly from existing worktrees created under both 24-character and 40-character formats.
  - *Red input:* A worktree named `.claude/worktrees/odyssey-410-changelog-md-with-a-hard-ci-merge-gate` fails issue inference.
- **AT-463-9 (D5, D6):** Hermetic library execution. `scripts/ops/tests/slug_test.sh` passes without `gh` CLI or network dependencies.
  - *Red input:* Removing `gh` from PATH causes `slug_test.sh` to fail.
- **AT-463-10 (D7):** Living spec update. `docs/SPEC.md` contains updated descriptions of folder reuse and slug derivation under `ops.claim` and `ops.dispatch`.
  - *Red input:* Omitting updates to `docs/SPEC.md` causes `scripts/ci/spec_check.sh` to fail.
- **AT-463-11 (D8):** Scope boundary enforcement. The implementing pull request diff touches only permitted files, leaving `personas/**`, `.claude/agents/*`, `.agents/*`, and `.github/workflows/*` untouched.
  - *Red input:* A diff modifying any file in `personas/**` turns this assertion red.

## Open questions

none

