# Plan: CHANGELOG.md with Hard CI Merge Gate, Full-History Bootstrap, and Process Update

**Issue:** #410 · **Spec:** `intent/410-changelog-md-with-a/spec.md` (Approved, PR #419, D1–D12, AT-1–AT-12)  
**Author:** daedalus (`evekhm-daedalus-app[bot]`)  
**Base commit:** `d8c46df8a885f228d9dcfec8eb79ca0cbfb295c3`  
**Target branch for implementation (Odyssey):** `odyssey/410-changelog-md-with-a`

---

## 1. Executive Summary and Problem Statement

Historically, this repository maintained three living documentation systems that appeared to record system progress but served fundamentally different purposes:
1. `docs/SPEC.md` is a living specification structured around permanent capability IDs and written in the present tense to describe what the system does today. It intentionally does not provide a chronological narrative of when features landed or why changes were made.
2. `docs/CRITICAL_PATH.md` is an operational tracking log maintained by the advisor seat to monitor in-flight progress toward the autonomous loop milestone. It is not gated by CI, not curated for general human readership, and not designed as a permanent historical log of shipped functionality.
3. `README.md` is specified (#35) to describe the target architecture and design vision; it explicitly excludes release chronology and build status.

Consequently, neither human operators nor automated actors have an accessible, plain-English chronological trail of what was built and why. Substantial behaviors (such as PR #406) have merged into `main` without human-readable summaries anywhere in the repository.

This plan details the implementation to formalize `CHANGELOG.md` at the repository root, accompanied by a fail-closed continuous integration gate (`scripts/ci/changelog_check.sh` running in `.github/workflows/ci-gates.yml`), governance updates across repository standards (`AGENTS.md`, `REVIEW.md`, `personas/odyssey.yaml`), a curated historical backfill covering substantive changes since repository inception, and an audit of `README.md` to eliminate factual drift.

---

## 2. Scope and Persona Boundaries

| Actor | Stage | Authority / Files Touched | Role in Issue #410 |
|---|---|---|---|
| **athena** | plan / design | `intent/**` | Authored `intent.md` and approved `spec.md` (merged as PR #419). |
| **daedalus** | build | `intent/**`, `scripts/*/tests/**` | Authors `plan.md` and commits contract test suite `scripts/ci/tests/changelog_check_test.sh`. Daedalus **never** edits production code. |
| **odyssey** | implement | `CHANGELOG.md`, `scripts/ci/changelog_check.sh`, `.github/workflows/ci-gates.yml`, `AGENTS.md`, `REVIEW.md`, `README.md`, `personas/odyssey.yaml`, `docs/SPEC.md`, compiled targets | Implements tasks T2 through T8 at pinned base commit `d8c46df8a885f228d9dcfec8eb79ca0cbfb295c3`, turning contract tests green, updating living spec, and verifying all CI gates. |
| **themis** | autonomous merge | GitHub Actions (`merge-gate.yml`) | Autonomously gates and merges pull requests upon consensus. |
| **argus / atlas** | review | comments only | Review pull requests against spec and plan. |

### Deep Review Grant (DEEP-1, DEEP-5, DEEP-7)
- **Criteria Met:**
  - **DEEP-1 (trust-bearing paths):** The implementation diff touches multiple paths listed under `config/execution.yaml` `assigned_when.paths` for argus: `.github/workflows/ci-gates.yml`, `scripts/ci/changelog_check.sh`, `personas/odyssey.yaml`, `AGENTS.md`, and `REVIEW.md`.
  - **DEEP-5 (escalated risk tier):** Task T2 (`changelog_check.sh`) introduces a brand new fail-closed CI gate script, and Task T3 (`ci-gates.yml`) edits core workflow files that directly govern merge gating. Both tasks are marked `risk: high`.
  - **DEEP-7 (compiler blast radius):** The implementation modifies `personas/odyssey.yaml`. Regenerating compiled output via `scripts/sync_agents.py` touches compiled agent targets across multiple locations (`.agents/agents/odyssey/**` and `.claude/agents/odyssey.md`).
- **Action:** Odyssey applies the `deep-review` grant when opening the PR per `scripts/ops/post.sh <pr> --as odyssey --add-label deep-review`.

---

## 3. Detailed Architectural Calls

### P1 · CHANGELOG Placement, Header, and Sectioning (D1, D2)
- `CHANGELOG.md` is placed at repository root.
- The file opens with the H1 `# Changelog` and an explanatory header declaring that notable behavioral and user-facing changes are documented here in reverse-chronological order.
- Top-level sections are date headers: `## YYYY-MM-DD`. Multiple entries for the same calendar day are grouped under a single `## YYYY-MM-DD` header.
- Each entry is an H3 subsection:
  `### [PR #<n>](https://github.com/evekhm/agentic-sdlc/pull/<n>): <Descriptive Title> ([#<issue>](https://github.com/evekhm/agentic-sdlc/issues/<issue>))`
  (Fallback plain text `### PR #<n>: <Descriptive Title> (#<issue>)` is valid).
- The body of each entry consists of exactly 1 to 3 concise, declarative sentences explaining:
  1. What capability or behavior changed;
  2. Why the change was made (the motivating problem or requirement);
  3. The operational or user-visible impact on operators, personas, or workflows.
- Forbidden in changelog entries: raw commit SHAs, file lists, diff snippets, and author vanity attributions.

### P2 · Dedicated Standalone CI Gate Script (D3)
- `scripts/ci/changelog_check.sh` is an executable bash script mirroring the dual-mode CLI and environment interface of `scripts/ci/spec_check.sh`:
  1. Local usage: `scripts/ci/changelog_check.sh <base-ref> [body-file]`
     - `<base-ref>` resolves to merge base with `HEAD`.
     - Omitted `body-file` defaults to an empty file via `mktemp`.
  2. CI usage: requires `BASE_SHA`, `HEAD_SHA`, and `PR_BODY_FILE` environment variables.
- Fail-closed behavior: unset variables, missing or unreadable body files, or a failing `git diff` exit 1 immediately.
- Exit 0 indicates the changelog obligation is satisfied or not incurred.

### P3 · Behavior-Bearing Path Parity (D4)
- `scripts/ci/changelog_check.sh` matches the exact path filtering rules of `scripts/ci/spec_check.sh`:
  - Behavior-bearing: `.github/workflows/*`, `scripts/*`, `personas/*`, `config/*`, `AGENTS.md`, and `REVIEW.md`.
  - Excluded paths: compiled targets (`.claude/agents/*`, `.agents/*`), intermediate lifecycle artifacts (`intent/**`), test runs (`runs/**`), operator state (`ops/**`), and documentation files (`docs/**`, `README.md`).
- If diff contains zero behavior-bearing files: exits 0 with notice:
  `::notice::changelog check: no behavior-bearing paths changed; no changelog obligation`
- If `CHANGELOG.md` is present in the diff: exits 0 with notice:
  `::notice::changelog check: CHANGELOG.md is updated in this PR; reviewers verify its entry against the diff`

### P4 · Machine Bypass Marker Syntax and Parsing Discipline (D5)
- Canonical bypass marker: `Changelog: none — <reason>`
- Symmetrical alias: `Changelog-impact: none — <reason>`
- Pure bash regex parsing matching `^[[:space:]]*[Cc]hangelog(-[Ii]mpact)?:[[:space:]]*[Nn]one(.*)$`.
- Supported separators: em dash (`—`), hyphen (`-`), colon (`:`), or matching parentheses (`(...)`).
- Mandatory non-empty reason: trimmed reason string must be non-empty.
- If marker detected without reason: exits 1 with error:
  `::error::changelog_check: the Changelog marker needs a reason: write 'Changelog: none — <why this diff does not change user-facing or system behavior>'`
- False match protection: words that merely start with "none" (e.g. `nonetheless`) do not trigger the marker and are ignored.
- If behavior-bearing paths changed, `CHANGELOG.md` not touched, and no valid marker found: exits 1 with error:
  `::error::changelog_check: this PR changes behavior-bearing paths but neither updates CHANGELOG.md nor declares no changelog impact`

### P5 · Parallel GitHub Actions CI Job (D6)
- In `.github/workflows/ci-gates.yml`, define a new job `changelog-check` (`changelog-check — CHANGELOG.md obligation`).
- Runs in parallel alongside `spec-check`, `drift`, `sanitize`, and `execution`.
- Event triggers: `pull_request` on `[opened, synchronize, reopened, edited]`.
- Triggering on `edited` ensures PR body marker adjustments re-trigger CI immediately without requiring dummy git commits.
- Materializes PR body into a temporary file and runs `bash scripts/ci/changelog_check.sh`.

### P6 · Autonomous Merge Gate and Branch Protection Enforcement (D7)
- `scripts/ci/merge_gate.sh` is **not modified**.
- Conjunct 2 (`mergeStateStatus` and check suite evaluation) automatically checks that all check runs in the pull request's check suite succeed. If `changelog-check` fails, Conjunct 2 evaluates to `false` and blocks autonomous merge.
- Required status check in GitHub branch protection for `main` includes `changelog-check`.

### P7 · Process Standards and Persona Governance Updates (D8)
- `AGENTS.md`: add section "The changelog (CHANGELOG.md)" immediately following "The living spec (docs/SPEC.md)".
- `REVIEW.md`: update implementer checklist under "The verification protocol" requiring reviewers (`argus`, `atlas`) to verify that `CHANGELOG.md` entries are accurate, concise, and aligned with diff, and that bypass reasons are valid.
- `personas/odyssey.yaml`: update role description to list `CHANGELOG.md` update (or bypass marker) as the fourth required delivery artifact on implementation pull requests.

### P8 · Curated Full-History Bootstrap Backfill (D9)
- Odyssey performs a one-time curated backfill in `CHANGELOG.md` spanning from PR #1 through PR #414.
- Curates substantive historical PRs: new capabilities, compiler and workflow additions, security and credential model upgrades, harness statusline tooling, and significant behavioral bug fixes.
- Excludes maintenance churn, typo fixes, reformatting, and intermediate review fixes.

### P9 · README.md Fact Audit and Gate Count Sync (D10)
- Update line 153 of `README.md` to state that **five** CI gates run on every pull request: drift, sanitize, execution, spec-check, and changelog-check.
- Repair any other drifted facts regarding persona roles or dispatch mechanisms to align with `docs/SPEC.md`.

### P10 · Hermetic CI Contract Test Suite (D11)
- `scripts/ci/tests/changelog_check_test.sh` exercises 8 discrete scenarios hermetically:
  1. Non-behavior-bearing path changes exit 0;
  2. Behavior-bearing changes with `CHANGELOG.md` updated exit 0;
  3. Behavior-bearing changes missing `CHANGELOG.md` and missing marker exit 1;
  4. Valid `Changelog: none — <reason>` exits 0;
  5. Valid `Changelog-impact: none — <reason>` exits 0;
  6. Marker missing reason exits 1;
  7. Marker prefix false matches exit 1;
  8. Positional CLI arguments function identically to CI environment variables.

### P11 · Living Spec Upsert (D12)
- Upsert `docs/SPEC.md` under `### ci.gates` and add `### process.changelog`.
- Confine PR scope to the declared files; do not touch `merge_gate.sh`, `review_recorder.sh`, `work.sh`, or `personas/lifecycle.json`.

---

## 4. Micro-Stepped Tasks

### Task T1: Commit Hermetic Contract Test Suite in `scripts/ci/tests/changelog_check_test.sh`
- **Owner:** daedalus (Build stage)
- **File touched:** `scripts/ci/tests/changelog_check_test.sh`
- **Decisions implemented:** D3, D4, D5, D11
- **Acceptance criteria proven:** AT-2, AT-3, AT-4, AT-5, AT-6, AT-7, AT-8, AT-12
- **Description:** Implement standalone, hermetic contract test script `scripts/ci/tests/changelog_check_test.sh`. It sets up an isolated temporary git repository sandbox, builds fixture branches (`test/non-behavior`, `test/changelog-updated`, `test/missing-changelog`), constructs body fixture files, and exercises all 8 contractual scenarios.
- **Done-When:**
  Running `bash scripts/ci/tests/changelog_check_test.sh` runs all 8 scenarios, reports clean assertion failures (`Total: 8, Passed: 0, Failed: 8`) rather than syntax errors or aborts, and exits with code 1.

---

### Task T2: Implement Standalone CI Gate Script `scripts/ci/changelog_check.sh`
- **Owner:** odyssey (Implement stage)
- **Risk:** high (DEEP-5: introduces core fail-closed CI gate script)
- **File touched:** `scripts/ci/changelog_check.sh`
- **Decisions implemented:** D3, D4, D5
- **Acceptance criteria proven:** AT-2, AT-3, AT-4, AT-5, AT-6, AT-7, AT-8, AT-12
- **Step-by-step diff description:**
  Create executable `scripts/ci/changelog_check.sh`:
  1. Header and preamble with `set -euo pipefail`.
  2. Implement dual-mode invocation handling: local positional arguments (`<base-ref> [body-file]`) vs CI environment variables (`BASE_SHA`, `HEAD_SHA`, `PR_BODY_FILE`).
  3. Validate environment variables and existence of `PR_BODY_FILE`.
  4. Run `git diff --name-only "$BASE_SHA" "$HEAD_SHA"`.
  5. Check behavior-bearing path filter matching `.github/workflows/*`, `scripts/*`, `personas/*`, `config/*`, `AGENTS.md`, and `REVIEW.md`.
  6. If no behavior-bearing paths changed: output notice and exit 0.
  7. If `CHANGELOG.md` in diff: output notice and exit 0.
  8. Read `$PR_BODY_FILE`, strip `\r`, and parse lines for regex `^[[:space:]]*[Cc]hangelog(-[Ii]mpact)?:[[:space:]]*[Nn]one(.*)$`.
  9. Extract and trim reason following `—`, `-`, `:`, or `(...)`.
  10. If valid marker with non-empty reason found: output notice and exit 0.
  11. If marker found without reason: output error and exit 1.
  12. If no valid marker found: output error, list behavior-bearing changed files, and exit 1.
  13. Make executable via `chmod +x scripts/ci/changelog_check.sh`.
- **Done-When:**
  `bash scripts/ci/tests/changelog_check_test.sh` runs all 8 scenarios and reports `Total: 8, Passed: 8, Failed: 0` with exit code 0.

---

### Task T3: Wire `changelog-check` Job into `.github/workflows/ci-gates.yml`
- **Owner:** odyssey (Implement stage)
- **Risk:** high (DEEP-5: alters core GitHub Actions workflow controlling merge gating)
- **File touched:** `.github/workflows/ci-gates.yml`
- **Decisions implemented:** D6, D7, D11
- **Acceptance criteria proven:** AT-9, AT-12
- **Step-by-step diff description:**
  In `.github/workflows/ci-gates.yml`:
  1. Update pull_request types to include `edited` if not already present, or verify trigger types for gate jobs.
  2. Add job `changelog-check`:
     ```yaml
     changelog-check:
       name: changelog-check — CHANGELOG.md obligation
       if: github.event_name == 'pull_request'
       runs-on: ubuntu-latest
       steps:
         - uses: actions/checkout@v4
           with:
             fetch-depth: 0
         - name: Run changelog contract test suite
           run: bash scripts/ci/tests/changelog_check_test.sh
         - name: Verify CHANGELOG.md obligation
           env:
             BASE_SHA: ${{ github.event.pull_request.base.sha }}
             HEAD_SHA: ${{ github.event.pull_request.head.sha }}
           run: |
             PR_BODY_FILE="$(mktemp)"
             printf '%s\n' "${{ github.event.pull_request.body }}" > "$PR_BODY_FILE"
             PR_BODY_FILE="$PR_BODY_FILE" bash scripts/ci/changelog_check.sh
             rm -f "$PR_BODY_FILE"
     ```
- **Done-When:**
  YAML parses cleanly and `changelog-check` job runs hermetic test suite and gate check.

---

### Task T4: Update Governance Documents & Re-sync Agents
- **Owner:** odyssey (Implement stage)
- **Files touched:**
  - `AGENTS.md`
  - `REVIEW.md`
  - `personas/odyssey.yaml`
  - `.agents/agents/odyssey/**` (compiled via `sync_agents.py`)
  - `.claude/agents/odyssey.md` (compiled via `sync_agents.py`)
- **Decisions implemented:** D8
- **Acceptance criteria proven:** AT-10
- **Step-by-step diff description:**
  1. In `AGENTS.md`: add "The changelog (CHANGELOG.md)" standard section following "The living spec (docs/SPEC.md)" documenting the reverse-chronological requirement, formatting, and bypass marker rules.
  2. In `REVIEW.md`: add changelog entry verification to the implementer checklist, specifying that reviewers check entry accuracy and bypass reasons.
  3. In `personas/odyssey.yaml`: add `CHANGELOG.md` entry as a required delivery artifact on implementation pull requests.
  4. Run `python3 scripts/sync_agents.py` to regenerate agent definitions.
- **Done-When:**
  `python3 scripts/sync_agents.py --check` exits 0 with zero drift, and governance documents reflect changelog discipline.

---

### Task T5: Bootstrap `CHANGELOG.md` with Curated Historical Entries (PR #1 to #414)
- **Owner:** odyssey (Implement stage)
- **File touched:** `CHANGELOG.md`
- **Decisions implemented:** D1, D2, D9
- **Acceptance criteria proven:** AT-1
- **Step-by-step diff description:**
  Create root `CHANGELOG.md`:
  1. Title `# Changelog` and explanatory preamble.
  2. Curate substantive PRs from repository inception (PR #1) through PR #414.
  3. Organize reverse-chronologically by merge date under `## YYYY-MM-DD` headers.
  4. Each entry formatted with `### [PR #<n>](...): <Title> ([#<issue>](...))` and 1 to 3 declarative sentences covering what, why, and impact.
  5. Exclude noise, typo fixes, and review churning.
- **Done-When:**
  `CHANGELOG.md` exists at repository root, conforms to D1/D2 structure, and provides complete historical context from PR #1 through PR #414.

---

### Task T6: Audit and Update `README.md` Gate Count
- **Owner:** odyssey (Implement stage)
- **File touched:** `README.md`
- **Decisions implemented:** D10
- **Acceptance criteria proven:** AT-11
- **Step-by-step diff description:**
  1. Update line 153 of `README.md` from four CI gates to five CI gates (`drift`, `sanitize`, `execution`, `spec-check`, and `changelog-check`).
  2. Review nearby context to ensure alignment with `docs/SPEC.md`.
- **Done-When:**
  `README.md` line 153 reflects five CI gates and factual alignment with `docs/SPEC.md`.

---

### Task T7: Update Living Spec in `docs/SPEC.md`
- **Owner:** odyssey (Implement stage)
- **File touched:** `docs/SPEC.md`
- **Decisions implemented:** D12
- **Acceptance criteria proven:** AT-12
- **Step-by-step diff description:**
  In `docs/SPEC.md`:
  1. Under `### ci.gates`, record capability `ci.gates.changelog`: fail-closed changelog verification gate running in parallel on PR events, evaluating behavior-bearing diffs for `CHANGELOG.md` updates or `Changelog: none — <reason>` bypass markers.
  2. Add section `### process.changelog`: document repository changelog placement at root, reverse-chronological `## YYYY-MM-DD` grouping, H3 entry syntax, 1–3 sentence content rule, and reviewer verification protocol.
- **Done-When:**
  `bash scripts/ci/spec_check.sh origin/main` exits 0 on the implementation PR branch.

---

### Task T8: Integration Verification of All CI Gates
- **Owner:** odyssey (Implement stage)
- **Files touched:** none
- **Decisions implemented:** D1–D12
- **Acceptance criteria proven:** AT-1 through AT-12
- **Verification steps:**
  1. `bash scripts/ci/tests/changelog_check_test.sh` -> PASS (8/8 scenarios passed)
  2. `python3 scripts/sync_agents.py --check` -> PASS (0 drift)
  3. `bash scripts/ci/sanitize_check.sh` -> PASS
  4. `bash scripts/ci/spec_check.sh origin/main` -> PASS
  5. `bash scripts/ci/changelog_check.sh origin/main` -> PASS
  6. `python3 scripts/ops/execution.py --check` -> PASS
  7. `bash scripts/ops/tests/execution_test.sh` -> PASS
  8. `bash scripts/ci/tests/merge_gate_test.sh` -> verify no regressions
- **Done-When:**
  All checks exit 0 with clean diagnostics.

---

## 5. Traceability Matrix

| Acceptance Test | Decision IDs | Category | Test Scenario / Verification Method | Implementing Task | Verification Proof |
|---|---|---|---|---|---|
| **AT-1** | D1, D2, D9 | **NEW-DOC** | Inspection of `CHANGELOG.md` | T5 | Reverse-chronological entries under `## YYYY-MM-DD` from PR #1 through PR #414 with 1-3 sentences on what/why/impact |
| **AT-2** | D3, D4 | **RED-NOW** | Scenario 1 in `changelog_check_test.sh` | T1 (test), T2 (code) | Diff touching only non-behavior-bearing paths exits 0 with notice |
| **AT-3** | D3, D4 | **RED-NOW** | Scenario 2 in `changelog_check_test.sh` | T1 (test), T2 (code) | Behavior-bearing change with `CHANGELOG.md` updated exits 0 with notice |
| **AT-4** | D3, D4, D5 | **RED-NOW** | Scenario 3 in `changelog_check_test.sh` | T1 (test), T2 (code) | Behavior-bearing change missing `CHANGELOG.md` and missing marker exits 1 with error |
| **AT-5** | D3, D5 | **RED-NOW** | Scenario 4 in `changelog_check_test.sh` | T1 (test), T2 (code) | Valid `Changelog: none — <reason>` marker exits 0 with notice |
| **AT-6** | D3, D5 | **RED-NOW** | Scenario 5 in `changelog_check_test.sh` | T1 (test), T2 (code) | Valid `Changelog-impact: none — <reason>` marker exits 0 with notice |
| **AT-7** | D3, D5 | **RED-NOW** | Scenario 6 in `changelog_check_test.sh` | T1 (test), T2 (code) | Marker missing reason exits 1 with error |
| **AT-8** | D3, D5 | **RED-NOW** | Scenario 7 in `changelog_check_test.sh` | T1 (test), T2 (code) | Marker prefix false match (`nonetheless`) exits 1 with error |
| **AT-9** | D6, D7 | **CI-WORKFLOW** | Inspection & execution of `.github/workflows/ci-gates.yml` | T3 | `changelog-check` job runs on `[opened, synchronize, reopened, edited]` in parallel |
| **AT-10** | D8 | **GOVERNANCE** | Inspection of `AGENTS.md`, `REVIEW.md`, `personas/odyssey.yaml` | T4 | Standards reflect changelog obligation, reviewer verification, and persona delivery requirements |
| **AT-11** | D10 | **DOCS-AUDIT** | Inspection of `README.md` | T6 | Line 153 states five CI gates run on pull requests |
| **AT-12** | D11 | **RED-NOW** | `bash scripts/ci/tests/changelog_check_test.sh` | T1 (test), T2 (code) | All 8 contractual scenarios pass hermetically with exit 0 |

---

## 6. Handoff to Odyssey (Implement Stage)

- **Branch:** `odyssey/410-changelog-md-with-a`
- **Base commit:** SHA of the commit merging this plan
- **PR Title:** `implement(ci): CHANGELOG.md with hard CI merge gate, bootstrap, and governance (#410)`
- **PR Body Requirements:**
  - Reference: `Refs #410` (no closing keywords in PR body, commit messages, or comments).
  - Deep Review grant: Odyssey must apply the `deep-review` grant label (`scripts/ops/post.sh <pr> --as odyssey --add-label deep-review`) per DEEP-1, DEEP-5, DEEP-7.
  - Plan sync / Summary of implemented tasks T2 through T7.
  - Evidence that `bash scripts/ci/tests/changelog_check_test.sh` runs green (8 passed, 0 failed).
  - Evidence that `python3 scripts/sync_agents.py --check` reports zero drift.
  - Evidence that `bash scripts/ci/spec_check.sh origin/main` and all CI gate scripts pass cleanly.
