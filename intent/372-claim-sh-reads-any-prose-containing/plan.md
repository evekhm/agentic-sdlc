# Plan: Native Issue Dependencies replace prose-parsed depends-on in claim.sh

**Issue:** #372 · **Spec:** `intent/372-claim-sh-reads-any-prose-containing/spec.md` (Approved, PR #476, D1–D8, AT-372-1–AT-372-10)  
**Author:** daedalus (`evekhm-daedalus-app[bot]`)  
**Base commit:** `9e19fa183556ce2608093f164d4798bffb6e582c` (base of this build/plan PR; implementation branches from the commit merging this plan)  
**Target branch for implementation (Odyssey):** `odyssey/372-claim-sh-reads-any-prose-containing`

---

## 1. Executive Summary and Problem Statement

`scripts/ops/claim.sh` historically derived issue dependencies by executing a case-insensitive regex search (`grep -Ei 'depends on'`) across the raw markdown body of an issue (`claim.sh:166`) and refusing the claim if any `#<number>` on a matching line was still open (`claim.sh:167-177`).

This prose-parsing approach suffered from severe systemic defects:
1. **False-Positive Refusals on Descriptive Prose:** Ordinary prose mentions, commit messages, citations, error logs, and issue descriptions containing the words "depends on" were falsely interpreted as machine-enforced blocking dependencies (live instances observed on #353, #404, and #372's own description).
2. **Structural Collision with Filing Standards:** Repository issue-filing templates (`.claude/commands/idea.md`, `.claude/commands/bug.md`), role definitions (`personas/athena.yaml`), and intake documentation (`personas/skills/intake-protocol.md`) explicitly instructed filers to describe relationships using the relationship words "absorbs, refines, depends on, supersedes" in free descriptive prose, directly colliding with `claim.sh`'s brittle grep.

This plan details the implementation to replace body-text scanning entirely with GitHub's native Issue Dependencies API (`repos/:owner/:repo/issues/:number/dependencies/blocked_by`). Under this architecture, the issue body is never read for dependency purposes. When an issue's `issue_dependencies_summary.total_blocked_by` is `0` (available directly in the issue payload already fetched by `claim.sh:104`), `claim.sh` short-circuits with zero extra network round trips. When non-zero, `claim.sh` queries the native `blocked_by` endpoint and refuses the claim if any blocking issue remains open, formatting the refusal clearly with the blocker number and title.

Before the implementation PR merges, an operational backfill migrates the six active pairs of issues relying on prose dependencies to native links, ensuring no gap in dependency enforcement.

---

## 2. Scope and Persona Boundaries

| Actor | Stage | Authority / Files Touched | Role in Issue #372 |
|---|---|---|---|
| **athena** | plan / design | `intent/**` | Authored `intent.md` and approved `spec.md` (merged as PR #476). |
| **daedalus** | build | `intent/**`, `scripts/*/tests/**` | Authors `plan.md` and commits contract test suite `scripts/ops/tests/claim_native_dependencies_contract_test.sh`. Daedalus **never** edits production code. |
| **odyssey** | implement | `scripts/ops/claim.sh`, `scripts/ops/tests/claim_test.sh`, `AGENTS.md`, `commands/idea.md`, `commands/bug.md`, `docs/SPEC.md`, `CHANGELOG.md` | Executes Tasks T2 through T9 branching from the commit merging this plan, creates native dependency links on live tracker (D7), turns contract tests green, updates living spec, and verifies all CI gates. |
| **themis** | autonomous merge | GitHub Actions (`merge-gate.yml`) | Autonomously gates and merges pull requests upon consensus. |
| **argus / atlas** | review | comments only | Review pull requests against spec and plan. |

### Deep Review Grant (DEEP-1, DEEP-3, DEEP-5)
- **Criteria Met on Build PR:**
  - **DEEP-1 (trust-bearing paths):** Touches `scripts/ops/tests/claim_native_dependencies_contract_test.sh`, which falls under `config/execution.yaml` `assigned_when.paths` (`scripts/ops/**`). Applied to this PR via `scripts/ops/post.sh <pr> --as daedalus --add-label deep-review`.
- **Criteria Met on Implementation PR:**
  - **DEEP-1 (trust-bearing paths):** The implementation diff touches multiple paths listed under `config/execution.yaml` `assigned_when.paths` for argus: `scripts/ops/claim.sh`, `scripts/ops/tests/claim_test.sh`, and `AGENTS.md`.
  - **DEEP-3 (privileged / mutation operations):** Modifies `scripts/ops/claim.sh`, the single entry point governing repository-wide issue claims, worktree creation, and the `in-progress` mutex.
  - **DEEP-5 (escalated risk tier):** Task T2 (`claim.sh`) touches the core claim mutex and state machine. Marked `risk: high`.
- **Action:** Odyssey applies the `deep-review` grant when opening the PR per `scripts/ops/post.sh <pr> --as odyssey --add-label deep-review`.

---

## 3. Detailed Architectural Calls

### P1 · Native Dependency Querying & Short-Circuit Optimization (D1, D3)
- `scripts/ops/claim.sh` fetches the primary issue payload at line 104 into variable `view`:
  ```bash
  view="$(gh_json "repos/$GITHUB_REPO/issues/$NUMBER")"
  ```
- The REST API response for GitHub Issues includes the object `issue_dependencies_summary`:
  ```json
  "issue_dependencies_summary": {
    "total_blocked_by": 0,
    "total_blocking": 0
  }
  ```
- `claim.sh` extracts `total_blocked_by="$(jq -r '.issue_dependencies_summary.total_blocked_by // 0' <<<"$view")"`.
- **Short-circuit (D3):** If `"$total_blocked_by"` equals `0`, `claim.sh` skips the dependency check entirely without performing any additional API call. This ensures that the common case (issues with no dependencies) incurs zero additional API overhead.
- **Lookup when non-zero (D1):** If `"$total_blocked_by"` is greater than `0`, `claim.sh` queries:
  ```bash
  gh_json "repos/$GITHUB_REPO/issues/$NUMBER/dependencies/blocked_by"
  ```
- No fallback to body parsing: `grep -Ei 'depends on'` and all regex scanning of `body` are deleted permanently from `claim.sh`. Body text containing "Depends on" has zero mechanical effect.

### P2 · Refusal Format and Multiple Blocker Joining (D2)
- When querying `dependencies/blocked_by`, GitHub returns an array of issue objects:
  ```json
  [
    {
      "number": 106,
      "state": "open",
      "title": "Prerequisite task"
    }
  ]
  ```
- Filter the list to items where `.state == "open"`.
- If zero open items exist (e.g. all blocking issues have `.state == "closed"`), the check succeeds and `claim.sh` proceeds past the dependency check (D1, AT-372-4).
- If one or more open items exist, construct the refusal string:
  - Each item formats as `#<number> (open): <title>`.
  - Multiple items join with `; ` (semicolon and space).
  - The refusal output produced via `refuse` is:
    ```
    refused: #<NUMBER> is blocked by #<m> (open): <title>
    ```
    or for multiple:
    ```
    refused: #<NUMBER> is blocked by #<m1> (open): <title1>; #<m2> (open): <title2>
    ```
  - `refuse` prints to `stderr` and exits 2, matching existing tracker refusal protocol.

### P3 · Documentation and Governance Alignment (D4, D5)
- **`claim.sh` header docstring (`claim.sh:21`):** Replace line 21 with:
  ```
  #   blocked by    an issue blocking this one in native dependencies is still open
  ```
- **`AGENTS.md` Claimable definition (`AGENTS.md:167-168`):** The sentence reads "An issue is *claimable* when: it is open, it has no `in-progress` label, every issue named in its 'Depends on' line is closed, and no `hold` label is present anywhere it points." Update the clause "every issue named in its 'Depends on' line is closed" to "all blocking issues in GitHub Issue Dependencies (`blocked_by`) are closed".
- **Filing commands (`commands/idea.md` and `commands/bug.md`, the compiled source; `.claude/commands/idea.md` and `.claude/commands/bug.md` are generated from these by `scripts/sync_commands.py` and must not be edited directly):**
  - Retain the prose relationship convention for context ("absorbs, refines, depends on, supersedes").
  - Explicitly document the two-command native-linking sequence for hard blocking dependencies:
    ```bash
    BLOCKER_ID="$(gh api repos/evekhm/agentic-sdlc/issues/<blocker> --jq .id)"
    gh api --method POST repos/evekhm/agentic-sdlc/issues/<n>/dependencies/blocked_by -F issue_id="$BLOCKER_ID"
    ```
  - Instruct filers that prose in the body does not create an enforcement block; native linking is required.

### P4 · Live Operational Migration for Active Issues (D7)
- Before the implementation PR merges, Odyssey executes native dependency linking on the live tracker for the six active dependency pairs identified during design and audit:
  1. #408 is blocked by #85
  2. #31 is blocked by #11
  3. #399 is blocked by #85 and #330
  4. #148 is blocked by #64 and #147
  5. #147 is blocked by #44
  6. #44 is blocked by #43
- Odyssey verifies immediately before backfill whether any newly filed issues carry prose dependencies, creates the links using the two-command sequence, and confirms via `gh api repos/evekhm/agentic-sdlc/issues/<n>/dependencies/blocked_by` that all links are registered with `state: open`.
- Executing migration prior to merging ensures continuous, zero-gap enforcement across the transition.

### P5 · Test Suite Modernization (D6)
- In `scripts/ops/tests/claim_test.sh`:
  - Delete lines 196–204 ("an open dependency blocks the claim" testing body parsing).
  - Update `issue()` helper to accept optional `total_blocked_by` parameter and populate `.issue_dependencies_summary.total_blocked_by`.
  - Add `blocked_by()` fixture helper creating `repos_test_repo_issues_<n>_dependencies_blocked_by.json`.
  - Add test case: native open blocker refuses claim and names it per D2.
  - Add test case: native blockers that are all closed do not refuse claim.
  - Add test case: issue whose body contains leading `Depends on #<n>` with open blocker but `total_blocked_by == 0` is NOT refused (regression guard proving body is never read).
- In `scripts/ops/tests/claim_native_dependencies_contract_test.sh`:
  - Dedicated hermetic contract test suite validating AT-372-1 through AT-372-10 against Decisions D1–D8.

### P6 · Living Spec and Changelog Obligations (D8)
- Update `docs/SPEC.md` under `tracker.workflow` documenting native-only dependency enforcement.
- Add an entry in `CHANGELOG.md` under today's date documenting the behavior change, why it was made, and operator impact.

---

## 4. Micro-Stepped Tasks

### Task T1: Commit Hermetic Contract Test Suite in `scripts/ops/tests/claim_native_dependencies_contract_test.sh`
- **Owner:** daedalus (Build stage)
- **Files touched:** `scripts/ops/tests/claim_native_dependencies_contract_test.sh`
- **Decisions implemented:** D1, D2, D3, D4, D5, D6, D8
- **Acceptance criteria proven:** AT-372-1 through AT-372-10
- **Description:** Implement standalone, hermetic contract test script `scripts/ops/tests/claim_native_dependencies_contract_test.sh`. It sets up an isolated temporary git repository and stub `gh` binary, constructing fixtures for `issue_dependencies_summary` and `dependencies/blocked_by`. Asserts all 12 contractual conditions.
- **Done-When:**
  Running `bash scripts/ops/tests/claim_native_dependencies_contract_test.sh` runs all 12 scenarios, reports clean assertion failures (`Total: 12, Passed: 0, Failed: 12`) rather than syntax errors, and exits with code 1.

---

### Task T2: Replace Body Scan with Native GitHub API Lookup in `scripts/ops/claim.sh`
- **Owner:** odyssey (Implement stage)
- **Risk:** high (DEEP-3, DEEP-5: alters core repository claim and mutex script)
- **Files touched:** `scripts/ops/claim.sh`
- **Decisions implemented:** D1, D2, D3, D4
- **Acceptance criteria proven:** AT-372-1, AT-372-2, AT-372-3, AT-372-4, AT-372-5, AT-372-7
- **Step-by-step diff description:**
  1. In `scripts/ops/claim.sh`, update docstring at line 21:
     Change `#   depends on    an issue named on a "Depends on" line is still open` to:
     `#   blocked by    an issue blocking this one in native dependencies is still open`.
  2. In `scripts/ops/claim.sh`, delete lines 163–178: the comment block at 163–165 documenting the body scan and the `dep_lines` grep-and-loop code at 166–178 that implements it.
  3. Replace with the native lookup block:
     ```bash
     # GitHub native Issue Dependencies API: if total_blocked_by is non-zero,
     # verify every blocking issue is closed.
     total_blocked_by="$(jq -r '.issue_dependencies_summary.total_blocked_by // 0' <<<"$view")"
     if [ "$total_blocked_by" -gt 0 ]; then
         blocked_by_json="$(gh_json "repos/$GITHUB_REPO/issues/$NUMBER/dependencies/blocked_by")" \
             || die "failed to read dependencies for #$NUMBER from $GITHUB_REPO"
         open_blockers="$(jq -r '
             [.[] | select(.state == "open") | "#\(.number) (open): \(.title)"]
             | join("; ")' <<<"$blocked_by_json")"
         [ -z "$open_blockers" ] \
             || refuse "#$NUMBER is blocked by $open_blockers"
     fi
     ```
  4. Ensure `claim.sh` is executable (`chmod +x scripts/ops/claim.sh`).
- **Done-When:**
  `grep -c "grep -Ei 'depends on'" scripts/ops/claim.sh` returns `0`, and contract test assertions 1, 2, 3, 4, 5, 6, and 7 pass.

---

### Task T3: Update Test Suite in `scripts/ops/tests/claim_test.sh`
- **Owner:** odyssey (Implement stage)
- **Files touched:** `scripts/ops/tests/claim_test.sh`
- **Decisions implemented:** D6
- **Acceptance criteria proven:** AT-372-6
- **Step-by-step diff description:**
  1. In `scripts/ops/tests/claim_test.sh`, update `issue()` fixture helper (line 71) to accept optional `total_blocked_by`:
     ```bash
     issue() {
       local n="$1" state="$2" labels="$3" title="$4" body="${5:-}" total_blocked_by="${6:-0}"
       jq -n --argjson n "$n" --arg state "$state" --arg labels "$labels" --arg title "$title" \
             --arg body "$body" --argjson total_blocked_by "$total_blocked_by" \
         '{number: $n, state: $state, title: $title, body: $body,
           issue_dependencies_summary: {total_blocked_by: $total_blocked_by},
           labels: ($labels | if . == "" then [] else split(",") end | map({name: .}))}' \
         > "$FIXTURES/repos_test_repo_issues_$n.json"
       echo '[]' > "$FIXTURES/repos_test_repo_issues_${n}_comments.json"
     }
     ```
  2. Add `blocked_by()` fixture helper:
     ```bash
     blocked_by() {
       local n="$1" json="$2"
       printf '%s\n' "$json" > "$FIXTURES/repos_test_repo_issues_${n}_dependencies_blocked_by.json"
     }
     ```
  3. Remove the body-text dependency test banner and test block at lines 196–204:
     ```bash
     banner "an open dependency blocks the claim"
     issue 105 open "" "Dependent issue" "Body text.
     ...
     no_writes "dependency: nothing was written"
     ```
  4. Add new native dependency test cases:
     ```bash
     banner "an open native dependency blocks the claim"
     issue 105 open "" "Dependent issue" "Body text" 1
     blocked_by 105 '[{"number": 106, "state": "open", "title": "The blocker"}]'
     run 2 "open native dependency exits 2" -- 105
     has "#105 is blocked by #106 (open): The blocker" "dependency: refusal names open blocker"
     no_writes "dependency: nothing was written"

     banner "a closed native dependency does not block the claim"
     issue 105 open "status:implementing" "Dependent issue" "" 1
     blocked_by 105 '[{"number": 106, "state": "closed", "title": "Done blocker"}]'
     run 0 "closed dependency proceeds" -- 105
     has "would: gh api --method POST repos/test/repo/issues/105/labels -f labels[]=in-progress" "dependency: claim proceeds"

     banner "prose 'Depends on #open' is ignored when total_blocked_by is 0"
     issue 106 open "" "Open issue" "" 0
     issue 105 open "status:implementing" "Issue with prose" "Depends on #106 (docs only)" 0
     run 0 "prose dependency ignored" -- 105
     has "would: gh api --method POST repos/test/repo/issues/105/labels -f labels[]=in-progress" "dependency: prose ignored"
     ```
- **Done-When:**
  `bash scripts/ops/tests/claim_test.sh` exits 0 with all scenarios passing.

---

### Task T4: Update Tracker Standards in `AGENTS.md`
- **Owner:** odyssey (Implement stage)
- **Files touched:** `AGENTS.md`
- **Decisions implemented:** D4
- **Acceptance criteria proven:** AT-372-7
- **Step-by-step diff description:**
  1. In `AGENTS.md` under "Working the tracker" step 1 (lines 167–168), the sentence reads: "An issue is *claimable* when: it is open, it has no `in-progress` label, every issue named in its 'Depends on' line is closed, and no `hold` label is present anywhere it points."
  2. Replace the clause "every issue named in its 'Depends on' line is closed" with "all blocking issues in GitHub Issue Dependencies (`blocked_by`) are closed".
- **Done-When:**
  Contract test assertion 8 passes.

---

### Task T5: Update Issue Filing Templates in `commands/idea.md` and `commands/bug.md`
- **Owner:** odyssey (Implement stage)
- **Files touched:** `commands/idea.md`, `commands/bug.md` (the compiled source files). After editing, run `python3 scripts/sync_commands.py` to regenerate `.claude/commands/idea.md` and `.claude/commands/bug.md`; do not edit the generated `.claude/commands/*` files directly, since `scripts/ci/compiler_roundtrip.sh` runs `scripts/sync_commands.py --check` and fails the build on any drift between source and generated copy.
- **Decisions implemented:** D5
- **Acceptance criteria proven:** AT-372-8
- **Step-by-step diff description:**
  1. In `commands/idea.md` (around line 28), where relationships are documented, add instruction for hard dependencies:
     ```markdown
     If this issue is strictly blocked by another issue that must be resolved first, link it via GitHub's native Issue Dependencies API:
     ```bash
     BLOCKER_ID="$(gh api repos/evekhm/agentic-sdlc/issues/<blocker> --jq .id)"
     gh api --method POST repos/evekhm/agentic-sdlc/issues/<n>/dependencies/blocked_by -F issue_id="$BLOCKER_ID"
     ```
     (Note: prose in the issue body does not enforce dependencies; use the native API).
     ```
  2. In `commands/bug.md` (around line 35), add the identical native-linking instructions.
  3. Run `python3 scripts/sync_commands.py` to regenerate the compiled `.claude/commands/idea.md` and `.claude/commands/bug.md` from the edited sources.
  4. In both `commands/idea.md` and `commands/bug.md`, add `Bash(gh api:*)` to the `allowed-tools` frontmatter, needed for the two-command native-linking sequence documented above.
- **Done-When:**
  Contract test assertions 9 and 10 pass, and `python3 scripts/sync_commands.py --check` exits 0.

---

### Task T6: Live Operational Migration of Open Dependency Pairs
- **Owner:** odyssey (Implement stage, operational tracker action)
- **Files touched:** None (live GitHub API mutation)
- **Decisions implemented:** D7
- **Acceptance criteria proven:** AT-372-9
- **Step-by-step diff description:**
  1. Audit live tracker to verify the 6 pairs from D7:
     - #408 → #85
     - #31 → #11
     - #399 → #85 and #330
     - #148 → #64 and #147
     - #147 → #44
     - #44 → #43
  2. For each pair `<issue>` and `<blocker>`:
     ```bash
     BLOCKER_ID="$(gh api "repos/evekhm/agentic-sdlc/issues/<blocker>" --jq .id)"
     gh api --method POST "repos/evekhm/agentic-sdlc/issues/<issue>/dependencies/blocked_by" -F issue_id="$BLOCKER_ID"
     ```
  3. Verify with `gh api repos/evekhm/agentic-sdlc/issues/<issue>/dependencies/blocked_by` that each blocker appears with `state: open`.
- **Done-When:**
  Live API reads for each issue confirm native links exist before the implementation PR merges.

---

### Task T7: Living Specification Update in `docs/SPEC.md`
- **Owner:** odyssey (Implement stage)
- **Files touched:** `docs/SPEC.md`
- **Decisions implemented:** D8
- **Acceptance criteria proven:** AT-372-10
- **Step-by-step diff description:**
  1. In `docs/SPEC.md`, add documentation under `### tracker.workflow` (or a dedicated `### ops.claim` section):
     Document that issue claimability is governed by GitHub Issue Dependencies API (`blocked_by`). If `issue_dependencies_summary.total_blocked_by` is zero, claims proceed with zero extra calls. If non-zero, all blockers in `dependencies/blocked_by` must have `state == "closed"`. Issue body text is never parsed for dependency declarations.
- **Done-When:**
  `bash scripts/ci/spec_check.sh origin/main` passes with a real `docs/SPEC.md` diff.

---

### Task T8: Record Entry in `CHANGELOG.md`
- **Owner:** odyssey (Implement stage)
- **Files touched:** `CHANGELOG.md`
- **Decisions implemented:** D8
- **Acceptance criteria proven:** AT-372-10
- **Step-by-step diff description:**
  1. In `CHANGELOG.md`, under today's date heading (`## YYYY-MM-DD`), add an H3 entry:
     ```markdown
     ### [PR #<pr>](https://github.com/evekhm/agentic-sdlc/pull/<pr>): Native Issue Dependencies replace prose parsing in claim.sh ([#372](https://github.com/evekhm/agentic-sdlc/issues/372))

     Replaces regex body scanning for "Depends on" in claim.sh with GitHub's native Issue Dependencies API. Eliminates false-positive claim refusals caused by descriptive prose while preserving hard dependency gating via issue_dependencies_summary and blocked_by. Migrates existing active tracker dependencies to native links.
     ```
- **Done-When:**
  `bash scripts/ci/changelog_check.sh origin/main` passes.

---

### Task T9: Wire Contract Test into CI, Verify Gates, and Merge Readiness
- **Owner:** odyssey (Implement stage)
- **Files touched:** `.github/workflows/ci-gates.yml`
- **Decisions implemented:** All (D1–D8)
- **Acceptance criteria proven:** AT-372-1 through AT-372-10
- **Description:**
  1. In `.github/workflows/ci-gates.yml`, add `bash scripts/ops/tests/claim_native_dependencies_contract_test.sh` and `bash scripts/ops/tests/claim_test.sh` to the same step that runs the sibling contract suites (`review_split_contract_test.sh`, `athena_front_door_contract_test.sh`), so the regression guard for #353/#404's false-positive runs on every PR, not just locally.
  2. Run all test suites locally:
     - `bash scripts/ops/tests/claim_native_dependencies_contract_test.sh` (must be 12 passed, 0 failed, exit 0).
     - `bash scripts/ops/tests/claim_test.sh` (must exit 0).
     - `python3 scripts/sync_agents.py --check` (must exit 0).
     - `python3 scripts/sync_commands.py --check` (must exit 0, per T5).
     - `bash scripts/ci/compiler_roundtrip.sh` (must exit 0).
     - `bash scripts/ci/sanitize_check.sh` (must exit 0).
     - `python3 scripts/ops/execution.py --check` (must exit 0).
     - Verify PR status, post handoff comment, and apply `deep-review` grant.
- **Done-When:**
  All tests and CI gates pass green, including the newly wired contract suites in `ci-gates.yml`.

---

## 5. Verification and Traceability Matrix

| Decision ID | Acceptance Test | Implementation Task(s) | Contract Test Assertion |
|---|---|---|---|
| **D1** | AT-372-1 | T2 | `scripts/ops/tests/claim_native_dependencies_contract_test.sh` (Assertion 1) |
| **D1, D3** | AT-372-2 | T2 | `scripts/ops/tests/claim_native_dependencies_contract_test.sh` (Assertion 2) |
| **D1, D2** | AT-372-3 | T2 | `scripts/ops/tests/claim_native_dependencies_contract_test.sh` (Assertions 3, 4) |
| **D1** | AT-372-4 | T2 | `scripts/ops/tests/claim_native_dependencies_contract_test.sh` (Assertion 5) |
| **D1, D6c** | AT-372-5 | T2, T3 | `scripts/ops/tests/claim_native_dependencies_contract_test.sh` (Assertion 6) |
| **D6** | AT-372-6 | T3 | `scripts/ops/tests/claim_native_dependencies_contract_test.sh` (Assertion 11) & `claim_test.sh` |
| **D4** | AT-372-7 | T2, T4 | `scripts/ops/tests/claim_native_dependencies_contract_test.sh` (Assertions 7, 8) |
| **D5** | AT-372-8 | T5 | `scripts/ops/tests/claim_native_dependencies_contract_test.sh` (Assertions 9, 10) |
| **D7** | AT-372-9 | T6 | Live API read across {408, 31, 399, 148, 147, 44} |
| **D8** | AT-372-10 | T7, T8 | `scripts/ops/tests/claim_native_dependencies_contract_test.sh` (Assertion 12) & `spec_check.sh`, `changelog_check.sh` |

---

## 6. Plan Sync (Deviations)

- **Task T5 / T9 Sync (sync_commands_test.py):** Updating `commands/idea.md` and `commands/bug.md` and regenerating `.claude/commands/` exposed that `scripts/ci/tests/sync_commands_test.py` (`test_d2_at_416_2_claude_targets_byte_identity`) was comparing emitted `.claude/commands/*` against `origin/main` rather than checking drift against committed targets in `REPO_ROOT`. In issue #416 D10, the commands compiler roundtrip was specified to be ref-free without `git` invocations against `origin/main`. `scripts/ci/tests/sync_commands_test.py` was updated to compare emitted targets against committed targets in `REPO_ROOT` (drift check) and verify no `GENERATED` comments exist in frontmatter, making it ref-free and allowing command sources in `commands/` to evolve as intended.
- **Task T9 Sync (.github/workflows/ci-gates.yml):** Task T9 specified wiring `claim_native_dependencies_contract_test.sh` and `claim_test.sh` into `.github/workflows/ci-gates.yml`. However, pushes modifying `.github/workflows/*.yml` are mechanically rejected by GitHub for GitHub App tokens lacking the `workflows` permission (`refusing to allow a GitHub App to create or update workflow without workflows permission`). Per trusted-posting rules (Rule 3/4: stay inside declared authority, never retry by switching identities), the workflow modification cannot be pushed by Odyssey App bot and is omitted from this PR. Both `claim_native_dependencies_contract_test.sh` (12/12 passing) and `claim_test.sh` are fully verified locally and can be wired into CI by a maintainer / followup with workflow scopes.
