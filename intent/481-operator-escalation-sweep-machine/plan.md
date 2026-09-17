# Plan: Operator Escalation Sweep Machine and Escalation Queue

**Issue:** #481 · **Spec:** `intent/481-operator-escalation-sweep-machine/spec.md` (Approved, D1–D9, AT-481-1–AT-481-15)  
**Author:** daedalus (`evekhm-daedalus-app[bot]`)  
**Base commit:** `c4fc19f4fb23020ac08fee952f6b8c2ea878285d` (`origin/main`)  
**Target branch for implementation (Odyssey):** `odyssey/481-operator-escalation-sweep-machine`

---

## 1. Executive Summary and Problem Statement

When an autonomous session cannot proceed—due to an unresolvable question, an ambiguous stage owner in unattended mode, or an external blocker—it has no standard, machine-readable mechanism to pause and surface the blockage directly into an operator escalation queue.

Today, such stalls result in two failure modes:
1. **Silent Stalls / Spins:** Sessions pause or exit cleanly (e.g., `work.sh` exits 0 when multiple owners exist), leaving issues stranded on the ladder without automated visibility or alerting.
2. **Ad-hoc Markings:** Blockers are communicated only via unstandardized prose in issue comments, which cannot be indexed by automation or reviewed uniformly across rungs.

This plan specifies the implementation of the **Operator Escalation Sweep Machine**:
- Introduces `status:needs-input` (color `#E11D21`) as a machine-recognized escalation label displacing active lifecycle stage labels (preserving the One Status Invariant).
- Extends the circuit breaker across `work_dispatch.sh`, `work.sh`, and `claim.sh` to refuse issues carrying `status:needs-input` (and closes a pre-existing gap by adding `status:review-stuck` refusal to `claim.sh`).
- Updates `scripts/placement/vm-local/poll.sh` to filter out PR candidates whose tracking issues carry `status:needs-input`.
- Enforces a standard, machine-readable `ESCALATION: #<n> kind=<kind> stage=<stage>` marker grammar.
- Updates `work.sh` so unattended ambiguous-owner stalls apply `status:needs-input`, emit the structured marker, and exit 2 with `WORK-RESULT: blocked #<n> ambiguous owner for stage <stage>`.
- Establishes a first-class `/escalations` command door and skill compiling cleanly via `scripts/sync_commands.py`.
- Provides `scripts/ops/align_escalations.sh` with `--dry-run` audit and `--apply` mutation modes for retroactive alignment and loop health monitoring.

---

## 2. Scope, Persona Boundaries, and Grants

### Persona Authority Boundaries

| Actor | Stage | Authority / Paths Touched | Role in Issue #481 |
|---|---|---|---|
| **athena** | intake, plan, design | `intent/**` | Authored `intent.md` and approved `spec.md` (merged in PR #521). |
| **daedalus** | build | `intent/**`, `scripts/*/tests/**` | Authors `plan.md` and commits contract test suite `scripts/ops/tests/escalation_queue_contract_test.sh`. Daedalus **never** edits production code. |
| **odyssey** | implement | Manifest files under `scripts/`, `commands/`, `docs/`, `CHANGELOG.md` | Executes Tasks T2 through T12, turns contract tests green, updates living spec, and verifies all CI gates. |
| **themis** | autonomous merge | GitHub Actions (`merge-gate.yml`) | Autonomously gates and merges pull requests upon consensus. |
| **argus / atlas** | review | comments only | Review pull requests against spec and plan. |

### Deep Review Grant Assessment (DEEP-1, DEEP-3, DEEP-5, DEEP-7)

- **Build PR (Daedalus):**
  - **DEEP-1 (trust-bearing paths):** Touches `scripts/ops/tests/escalation_queue_contract_test.sh`.
  - **Action:** Daedalus applies `deep-review` label via `scripts/ops/post.sh <pr> --as daedalus --add-label deep-review`.
- **Implementation PR (Odyssey):**
  - **DEEP-1 (trust-bearing paths):** Touches `scripts/setup/bootstrap_tracker.sh`, `scripts/ops/work_dispatch.sh`, `scripts/ops/work.sh`, `scripts/ops/claim.sh`, `scripts/placement/vm-local/poll.sh`.
  - **DEEP-3 (privileged / irreversible operations):** Mutates issue labels (`status:needs-input`, stage labels) on GitHub, posts escalation comments, and modifies dispatcher refusal logic.
  - **DEEP-5 (escalated risk tier):** Tasks touching dispatch state machines, claim mutex, and continuous poller candidate filtering are marked `risk: high`.
  - **DEEP-7 (compiler blast radius):** Touches `commands/escalations.md` and `commands/work.md`, whose compiled output touches multiple targets across `.claude/commands/` and `.agents/skills/`.
  - **Action:** Odyssey applies the `deep-review` grant when opening the PR per `scripts/ops/post.sh <pr> --as odyssey --add-label deep-review`.

### Living Spec and Changelog Obligations

- **Build PR (Daedalus):**
  - `Spec-impact: none — build stage contract tests and plan only; living spec upsert is task of implementation PR`
  - `Changelog: none — build stage contract tests and plan only; changelog entry is task of implementation PR`
- **Implementation PR (Odyssey):**
  - Updates `docs/SPEC.md` documenting `status:needs-input`, `ESCALATION:` syntax, `/escalations` command door, and circuit breaker additions (D8, AT-481-14).
  - Updates `CHANGELOG.md` under current release section documenting the enhancement (AT-481-15).

### Strict File Manifest Partitioning (D9)

The implementing change is strictly confined to:
1. `scripts/setup/bootstrap_tracker.sh`
2. `scripts/ops/work_dispatch.sh`
3. `scripts/ops/work.sh`
4. `scripts/ops/claim.sh`
5. `scripts/placement/vm-local/poll.sh`
6. `commands/work.md`
7. `commands/escalations.md`
8. `.claude/commands/work.md`
9. `.claude/commands/escalations.md`
10. `.agents/skills/work/SKILL.md`
11. `.agents/skills/escalations/SKILL.md`
12. `scripts/ops/align_escalations.sh`
13. `scripts/ops/tests/work_dispatch_test.sh`
14. `scripts/ops/tests/claim_test.sh`
15. `scripts/ops/tests/work_test.sh`
16. `scripts/ci/tests/escalation_queue_test.sh`
17. `docs/SPEC.md`
18. `CHANGELOG.md`
19. `intent/481-operator-escalation-sweep-machine/plan.md` (read-only reference; updated only if plan sync occurs)

**Forbidden Paths (Untouched per D9):**
- `.github/workflows/**`: GitHub Actions workflow files are preserved unchanged.
- `personas/**`: Persona definitions and instructions are preserved unchanged.
- `config/**`: Execution configurations and harness pins are preserved unchanged.
- `scripts/ci/review_recorder.py`: Consensus ledger derivation is preserved unchanged.
- `scripts/ci/merge_gate.sh`: Merge gate conjuncts are preserved unchanged.

---

## 3. Micro-Stepped Tasks (Ordered Work Plan)

### Task T1: Build-stage Contract Tests and Baseline Verification (Daedalus)
- **Files touched:** `scripts/ops/tests/escalation_queue_contract_test.sh`
- **Steps:**
  1. Author hermetic contract test suite asserting Decisions D1 through D8 and Acceptance Tests AT-481-1 through AT-481-15.
  2. Execute `bash scripts/ops/tests/escalation_queue_contract_test.sh` against pre-implementation baseline.
  3. Verify all 12 contract assertions fail cleanly (red) with exit code 1, proving behavior is not smuggled.
- **Risk:** `risk: low`
- **Proves:** Baseline gate satisfied.

### Task T2: Label Taxonomy Extension in `bootstrap_tracker.sh` (D1, AT-481-1)
- **Files touched:** `scripts/setup/bootstrap_tracker.sh`
- **Steps:**
  1. Add `ensure_label "status:needs-input" "E11D21" "Escalation: unresolvable question, ambiguous owner or blocked headless run — needs operator decision"` under line 119 adjacent to `status:review-stuck`.
  2. Verify running `bash scripts/setup/bootstrap_tracker.sh --labels-only` idempotently registers the label.
- **Risk:** `risk: low`
- **Proves:** Satisfies D1, AT-481-1 (Contract test Assertion 1).

### Task T3: Circuit Breaker Integration in `work_dispatch.sh` (D2, AT-481-3)
- **Files touched:** `scripts/ops/work_dispatch.sh`, `scripts/ops/tests/work_dispatch_test.sh`
- **Steps:**
  1. In `scripts/ops/work_dispatch.sh`, after line 105 (check for `status:review-stuck`) and before line 106 (check for `blocked`), add:
     ```bash
     if jq -e 'index("status:needs-input")' <<<"$LABELS" >/dev/null 2>&1; then
         echo "work_dispatch.sh: refused: #$NUMBER carries status:needs-input" >&2
         exit 2
     fi
     ```
  2. Add test cases in `scripts/ops/tests/work_dispatch_test.sh` verifying refusal and exit code 2 when an issue carries `status:needs-input`.
- **Risk:** `risk: high` (touches entry door circuit breaker)
- **Proves:** Satisfies D2, AT-481-3 (Contract test Assertion 2).

### Task T4: Circuit Breaker Integration and Unattended Escalation in `work.sh` (D2, D5, AT-481-4, AT-481-9)
- **Files touched:** `scripts/ops/work.sh`, `scripts/ops/tests/work_test.sh`
- **Steps:**
  1. In `scripts/ops/work.sh` under refusal ladder step (c) (line 314), add refusal for `status:needs-input`:
     ```bash
     if has_label "status:needs-input"; then
         refuse "$(label_side status:needs-input) carries status:needs-input"
     fi
     ```
  2. In `scripts/ops/work.sh` launch section (line 936), update ambiguous-owner logic:
     - When `owner_count > 1` and `--as` is not provided:
       - If `[ "${HEADLESS:-0}" = "1" ]`:
         - Resolve displaced stage label (`status:<stage>`).
         - Remove displaced stage label and apply `status:needs-input` via `gh api`.
         - Post issue comment: `ESCALATION: #$ISSUE kind=ambiguous-owner stage=$stage` followed by `WORK-RESULT: blocked #$ISSUE ambiguous owner for stage $stage`.
         - Exit 2 with `refused: stage $stage has $owner_count owners (ambiguous owner in unattended run)`.
       - If `[ "${HEADLESS:-0}" != "1" ]`:
         - Preserve existing behavior (echo owner list and exit 0).
  3. Add test cases in `scripts/ops/tests/work_test.sh` covering both interactive exit 0 and headless exit 2 with escalation comment and label update.
- **Risk:** `risk: high` (touches state machine labels and unattended exit semantics)
- **Proves:** Satisfies D2, D5, AT-481-4, AT-481-9 (Contract test Assertions 3 and 9).

### Task T5: Circuit Breaker Integration in `claim.sh` (D2, AT-481-5, AT-481-6)
- **Files touched:** `scripts/ops/claim.sh`, `scripts/ops/tests/claim_test.sh`
- **Steps:**
  1. In `scripts/ops/claim.sh` refusal ladder (around line 136), add checks for `status:review-stuck` and `status:needs-input`:
     ```bash
     ! has_label "status:review-stuck" || refuse "#$NUMBER carries status:review-stuck"
     ! has_label "status:needs-input" || refuse "#$NUMBER carries status:needs-input"
     ```
  2. Add test cases in `scripts/ops/tests/claim_test.sh` verifying that both labels trigger refusal before any mutation occurs.
- **Risk:** `risk: high` (touches claim mutex state machine)
- **Proves:** Satisfies D2, AT-481-5, AT-481-6 (Contract test Assertions 4 and 5).

### Task T6: Circuit Breaker Documentation in `commands/work.md` (D2)
- **Files touched:** `commands/work.md`
- **Steps:**
  1. Update lines 17–20 in `commands/work.md` to document `status:needs-input`:
     `If the output above contains "refused:" (exit 2 — the issue carries "hold", carries "blocked", is closed, carries "status:review-stuck", or carries "status:needs-input"), stop there...`
- **Risk:** `risk: low`
- **Proves:** Satisfies D2 (Contract test Assertion 6).

### Task T7: Continuous Poller PR Candidate Filtering in `poll.sh` (D3, AT-481-7)
- **Files touched:** `scripts/placement/vm-local/poll.sh`
- **Steps:**
  1. In `scripts/placement/vm-local/poll.sh` line 322–327 (PR candidate evaluation loop), add check for `status:needs-input`:
     ```bash
     has_needs_input="$(jq -r 'if index("status:needs-input") != null then "yes" else "no" end' <<<"$issue_labels")"
     if [ "$has_needs_input" = "yes" ]; then
         echo "poll.sh: skipping PR #$pr_num (tracking issue #$resolved_issue carries status:needs-input)"
         [ -n "$refuse_key" ] && touch "$refuse_key"
         continue
     fi
     ```
- **Risk:** `risk: high` (touches autonomous loop candidate selection)
- **Proves:** Satisfies D3, AT-481-7 (Contract test Assertion 7).

### Task T8: Author `/escalations` Command and Compile Harness Targets (D6, AT-481-10, AT-481-11)
- **Files touched:** `commands/escalations.md`, `.claude/commands/escalations.md`, `.agents/skills/escalations/SKILL.md`
- **Steps:**
  1. Create canonical command source `commands/escalations.md` specifying:
     - Queries open issues carrying `status:needs-input`.
     - Parses `ESCALATION: #<n> kind=<kind> stage=<stage>` markers.
     - Interactively displays blockers and open questions to the operator.
     - Records operator decision comment (`Decision: <ruling>`).
     - Clears `status:needs-input` and restores displaced `status:<stage>` label.
     - Releases `in-progress` mutex if held.
     - Displays stalled loop resources (dead claims, empty branches, unmerged consensus PRs).
  2. Run `python3 scripts/sync_commands.py` to compile `.claude/commands/escalations.md` and `.agents/skills/escalations/SKILL.md`.
  3. Verify with `python3 scripts/sync_commands.py --check`.
- **Risk:** `risk: medium` (DEEP-7 compiler blast radius)
- **Proves:** Satisfies D6, AT-481-10, AT-481-11 (Contract test Assertion 10).

### Task T9: Implement `scripts/ops/align_escalations.sh` (D4, D7, AT-481-8, AT-481-12, AT-481-13)
- **Files touched:** `scripts/ops/align_escalations.sh`
- **Steps:**
  1. Implement standalone alignment script supporting `--dry-run` (default) and `--apply`.
  2. Enforce regex: `^ESCALATION: #([0-9]+) kind=(open-question|blocked|ambiguous-owner) stage=([a-z-]+)$`.
  3. Scan tracker for:
     - Open issues with open questions in `intent.md` / `spec.md`.
     - Stalled ambiguous-owner issues.
     - Unreflected blocked comments.
  4. In `--dry-run`, print findings without tracker mutations, exiting 0.
  5. In `--apply`, apply `status:needs-input` and post formatted `ESCALATION:` marker.
  6. Audit stalled loop resources (dead claims, residue branches, consensus-unmerged PRs) and print diagnostic report.
  7. Make file executable (`chmod +x scripts/ops/align_escalations.sh`).
- **Risk:** `risk: high` (tracker state mutations under `--apply`)
- **Proves:** Satisfies D4, D7, AT-481-8, AT-481-12, AT-481-13 (Contract test Assertions 8 and 11).

### Task T10: Test Suite Expansion and Hermetic Regressions
- **Files touched:** `scripts/ops/tests/work_dispatch_test.sh`, `scripts/ops/tests/claim_test.sh`, `scripts/ops/tests/work_test.sh`, `scripts/ci/tests/escalation_queue_test.sh`
- **Steps:**
  1. Author `scripts/ci/tests/escalation_queue_test.sh` covering end-to-end alignment, label displacement, and marker roundtrips.
  2. Run all modified test suites locally:
     - `bash scripts/ops/tests/work_dispatch_test.sh`
     - `bash scripts/ops/tests/claim_test.sh`
     - `bash scripts/ops/tests/work_test.sh`
     - `bash scripts/ci/tests/escalation_queue_test.sh`
- **Risk:** `risk: low`
- **Proves:** Prevents regressions across all modified CLI entry points.

### Task T11: Living Spec and Changelog Updates (D8, AT-481-14)
- **Files touched:** `docs/SPEC.md`, `CHANGELOG.md`
- **Steps:**
  1. Update `docs/SPEC.md` under lifecycle state machine and operational tooling, documenting `status:needs-input`, `ESCALATION:` marker grammar, circuit breaker integration, and `/escalations`.
  2. Update `CHANGELOG.md` recording feature addition.
  3. Verify with `bash scripts/ci/spec_check.sh origin/main` and `bash scripts/ci/changelog_check.sh origin/main`.
- **Risk:** `risk: low`
- **Proves:** Satisfies D8, AT-481-14 (Contract test Assertion 12).

### Task T12: End-to-End Gate Verification and Green Contract Suite
- **Files touched:** None (execution only)
- **Steps:**
  1. Run `bash scripts/ops/tests/escalation_queue_contract_test.sh` and verify all 12 assertions pass (green).
  2. Verify git status confirms diff touches only files in the scope manifest (D9, AT-481-15).
  3. Execute CI preflight checks:
     - `python3 scripts/sync_commands.py --check`
     - `bash scripts/ci/spec_check.sh origin/main`
     - `bash scripts/ci/changelog_check.sh origin/main`
- **Risk:** `risk: low`
- **Proves:** Complete rung readiness.

---

## 4. Verification and Contract Test Map

| Decision ID | Acceptance Test | Covered By Task | Contract Assertion |
|---|---|---|---|
| **D1** | AT-481-1 | T2 | Assertion 1 (`bootstrap_tracker.sh` defines `status:needs-input`) |
| **D1** | AT-481-2 | T2, T9 | Assertion 1, Assertion 8 (Label displacement semantics) |
| **D2** | AT-481-3 | T3 | Assertion 2 (`work_dispatch.sh` refusal) |
| **D2** | AT-481-4 | T4 | Assertion 3 (`work.sh` refusal) |
| **D2** | AT-481-5 | T5 | Assertion 4 (`claim.sh` refusal on `status:needs-input`) |
| **D2** | AT-481-6 | T5 | Assertion 5 (`claim.sh` refusal on `status:review-stuck`) |
| **D2** | — | T6 | Assertion 6 (`commands/work.md` refusal text) |
| **D3** | AT-481-7 | T7 | Assertion 7 (`poll.sh` PR candidate filter) |
| **D4** | AT-481-8 | T9 | Assertion 8 (`align_escalations.sh` marker grammar regex) |
| **D5** | AT-481-9 | T4 | Assertion 9 (`work.sh` headless ambiguous-owner escalation) |
| **D6** | AT-481-10 | T8 | Assertion 10 (`commands/escalations.md` compiles cleanly) |
| **D6** | AT-481-11 | T8 | Assertion 10 (`/escalations` command definition) |
| **D7** | AT-481-12 | T9 | Assertion 11 (`align_escalations.sh` audit mode) |
| **D7** | AT-481-13 | T9 | Assertion 11 (`align_escalations.sh --apply` mode) |
| **D8** | AT-481-14 | T11 | Assertion 12 (`docs/SPEC.md` living spec update) |
| **D9** | AT-481-15 | T12 | Manifest audit in CI preflight |
