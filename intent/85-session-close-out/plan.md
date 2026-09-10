# Plan: Session Close-Out (/wrap)

**Issue:** #85 · **Spec:** `intent/85-session-close-out/spec.md` (Approved, D1–D15, AT-1–AT-19)  
**Author:** daedalus (`evekhm-daedalus-app[bot]`)  
**Base commit:** `e9c987baa08701de0e223bf8410ec6be0e8432d7` (spec's base: `04c0abdc64829ffc56c22f4c1bc61cb306afa087`)  
**Target branch for implementation (Odyssey):** `odyssey/85-session-close-out`

---

## 1. Executive Summary and Problem Statement

A session currently has no defined end. It concludes unpredictably when an operator closes a terminal window or when an autonomous execution completes. Whatever remains in flight at that moment is either lost or discovered later by accident:
- Subagents, background jobs, or child processes left running in background process tables.
- Working branches in worktrees created but never pushed to remotes.
- Decisions reached in conversation or transcripts that never transitioned into an issue, a pull request, or an explicit tracker deferral.
- Claimed issues with stale `in-progress` labels and missing Done / Decided / Next / Blocked handoff comments.
- Run artifacts under `runs/` generated without disposition footnotes or sidecars.
- Unpruned safe worktrees and dirty or unpushed worktrees left without accounting.
- Stale `main` branches and drift across primary checkouts.

While `scripts/ops/work.sh <n>` exists as the one door for starting a stage, there is no corresponding door for finishing a session.

### The Solution: `/wrap`
The solution is a single user command, `/wrap`, typed by an operator in Claude Code or invoked by automated runners:
1. Implemented once in a deterministic script: `scripts/ops/wrap.sh`.
2. Exposed through a single tracked harness door (`.claude/commands/wrap.md`) taking the tested prototype from issue comment 5610016589 as-is, with CI roundtrip gate enforcement. (Antigravity harness support is dropped per #43 D16 and D8).
3. Supporting two modes: `--snapshot` (refresh handoff mid-flight, keep working) and bare `/wrap` (close-out and stop).
4. Deriving verdicts via a strict three-way ownership rule (`pass`, `fail`, `warn`, `fixed`).
5. Enforcing a single auto-repair mutation (removing forgotten `in-progress` labels when a complete handoff comment exists; `DRY_RUN=1` prints would-fix, reports fail, and exits 2).
6. Short-circuiting clean, empty sessions immediately without writing unneeded handoff files.
7. Ending by writing `<primary-checkout>/ops/handoffs/handoff-<seat>-<YYYY-MM-DD>[-n].txt` and emitting a verbatim resume command (`ops/waves/seat.sh <seat>`).

---

## 2. Scope and Persona Boundaries

| Actor | Stage | Authority / Files Touched | Role in Issue #85 |
|---|---|---|---|
| **athena** | plan / design | `intent/**` | Authored `intent.md` and approved `spec.md` (PR #346, amended via PR #357). |
| **daedalus** | build | `intent/**`, `scripts/*/tests/**` | Authors `plan.md` and commits hermetic contract tests in `scripts/ops/tests/wrap_test.sh`. Daedalus never writes production code (`scripts/ops/wrap.sh`, harness doors, or `docs/SPEC.md`). |
| **odyssey** | implement | `scripts/ops/wrap.sh`, `.claude/commands/wrap.md`, `scripts/ops/tests/wrap_test.sh`, `.github/workflows/ci-gates.yml` (solely to wire `wrap_test.sh` per D15), `scripts/ci/compiler_roundtrip.sh`, `docs/SPEC.md`, `AGENTS.md`, `intent/85-session-close-out/spec.md` | Implements the plan at base commit `e9c987baa08701de0e223bf8410ec6be0e8432d7` (spec's base: `04c0abdc64829ffc56c22f4c1bc61cb306afa087`), turning contract tests green, updating `docs/SPEC.md` (`ops.wrap`), updating `AGENTS.md`, and passing all CI gates. |
| **argus / atlas** | review | comments only | Review pull requests against spec and plan using independent models. |
| **themis** | autonomous merge | GitHub Actions (`merge-gate.yml`) | Evaluates conjuncts and autonomously merges pull requests upon consensus. |

### Deep-Review Criteria for Implementation
Per `deep-review.md`:
- Task T4 touches GitHub label state machines and mutexes (DEEP-3, DEEP-5 `risk: high`).
- Task T8 modifies workflow file `.github/workflows/ci-gates.yml` to register the contract test suite (DEEP-1, DEEP-5 `risk: high`).
- Consequently, Odyssey will inherit the `deep-review` grant when opening the implementation pull request.

---

## 3. The Calls This Plan Makes

### P1 · Three-Way Derivation Rule and Four Verdicts (D1, D6)
In `scripts/ops/wrap.sh`, every check evaluates to one of four states (`pass`, `fail`, `warn`, `fixed`) using an objective three-way partition:
1. **`fail`** (blocks close-out, exit 2): An anomaly in a resource owned and actionable by this session (e.g. unpushed commits on this session's branch, dirty primary checkout, child processes active, omitted learnings, credential leak).
2. **`warn`** (recorded in handoff, does not block close-out):
   - An anomaly in a foreign resource (a peer session's dirty worktree, an unmerged foreign PR).
   - An anomaly in a session-owned resource that is unserviceable by this session due to an ambient environment defect (e.g. #167 runner infrastructure outages, unpriced model tiers in spend reporting).
3. **`fixed`** (auto-repaired, exit 0): An issue claimed by this session that carries a complete Done/Decided/Next/Blocked handoff comment where only the `in-progress` label was forgotten (triggers D4 auto-repair).
4. **`pass`**: Condition requirements are completely satisfied.

### P2 · Session Identity, Join Key, and Worktree Lock Fallback (D2, D3)
- The primary join key for identifying session-owned resources is the session name recorded in the structured claim comment (`Claim: <actor> (<session>), stage: <stage>...`, mandated by `claim.sh` #92).
- Worktree lock metadata at `$GIT_COMMON_DIR/worktrees/<name>/locked` (per `scripts/ops/worktrees.sh:79`) acts as secondary fallback for child or transient worktrees.
- `wrap.sh` requires the session name as its first positional argument: `scripts/ops/wrap.sh <session-name> [seat-or-slug] [--snapshot]`.
- App identities and branch prefixes are rejected as join keys because parallel sessions share them.
- Session lifecycle scope (D3): A session bounds all actions under that session name from claim to close-out. Check 1 verifies child processes of that session context have exited. Check 16 rolls up spend metrics for transcripts generated during that session.
- **Process attribution rule for Check 1 (D1, D3):** Active processes are attributed to the session if: (a) in an interactive or subshell invocation, they are active child processes belonging to the caller's process tree (children of `$PPID`, excluding `wrap.sh` itself `$$` and its direct subshell pipeline children), or (b) their PID is recorded as active in a worktree lock file (`$GIT_COMMON_DIR/worktrees/<name>/locked` per `scripts/ops/worktrees.sh:81-83`) for a worktree owned by this session. Any active process matching either condition triggers `fail: child processes still running` and exits 2.

### P3 · Single Permitted Auto-Repair and DRY_RUN Contract (D4)
- `wrap.sh` executes exactly **one** automated mutation: removing a lingering `in-progress` label from an issue claimed by this session when a valid Done/Decided/Next/Blocked handoff comment already exists.
- In normal execution: calls GitHub REST API `DELETE repos/<repo>/issues/<n>/labels/in-progress`, prints `fixed: removed in-progress from #<n>`, and proceeds to exit 0.
- Under `DRY_RUN=1`: makes zero API write calls (asserted via PATH shim over `gh`), prints `would: remove in-progress from #<n>`, reports `fail: #<n> carries in-progress (dry-run)`, and exits 2.
- All other mutations are prohibited: `wrap.sh` never synthesizes missing handoff comments, never deletes branches, never prunes foreign worktrees, and never unclaims issues without handoffs.

### P4 · Mandatory Learnings Step (D5)
- Close-out evaluation includes a mandatory learnings check that cannot be bypassed silently.
- Evaluated via environment variable `WRAP_LEARNINGS`.
- In close-out mode: `WRAP_LEARNINGS` must be provided with `none`, `learnings: no learnings to persist`, or a persisted learning identifier (such as a doc update in the PR or an issue reference). If `WRAP_LEARNINGS` is unset or empty, `wrap.sh` reports `fail: learnings step omitted` and exits 2.
- In `--snapshot` mode: the Learnings check is skipped.

### P5 · V1 Check Selection and Ordering Principle (D6)
Shipped in v1 (12 checks + Learnings step):
- Check 1: In-flight child processes & subagents (close-out only)
- Check 3: Worktree branch synchronization (both modes)
- Check 4: Primary checkout on main & clean (close-out only)
- Check 5: Session PR status: merged or green (close-out only)
- Check 7: Decision accounting against tracker (both modes)
- Check 8: Claim release & handoff comment (close-out only)
- Check 10: Run artifact disposition footnotes (close-out only)
- Check 12: Compiler roundtrip & drift parity (close-out only). Requires running BOTH `python3 scripts/sync_agents.py --check` AND `bash scripts/ci/compiler_roundtrip.sh` on the primary checkout.
- Check 15: Worktree hygiene report & session safe worktrees (close-out only)
- Check 16: Session spend measurement via side-channel (both modes)
- Check 17: Credential leak detection (both modes)
- Check 18: Temporary body file cleanup under `/tmp` (close-out only)
- Learnings Step: Mandatory operational knowledge harvest (close-out only)

Deferred to post-v1 by number: Checks 2, 6, 9, 11, 13, 14, 19.

### P6 · Exit Code Vocabulary (D7)
- `0`: Clean / Closed (all session-owned checks pass or fixed via D4, foreign warnings reported, or clean short-circuit).
- `1`: Environment / input failure (missing `git`, `gh`, `jq`, `gawk`, unreadable repository, missing session name argument, or GitHub API network/auth failure).
- `2`: Refused / Not closed (one or more session-owned checks failed, or dry-run would-fix encountered).

### P7 · Claude Code Door Tracking and Tested Prototype (D8)
- Scope cut: Claude Code only. Antigravity twin door (`.agents/workflows/wrap.md`) is dropped per #43 D16 and D8.
- `.claude/commands/wrap.md` takes the tested prototype from issue comment 5610016589 as-is:
  - Allowed-tools frontmatter (`Bash(git *)`, `Bash(gh *)`, `Bash(scripts/ops/*)`, `Bash(ops/harness/*)`, `Bash(ops/waves/*)`, etc.)
  - Two batched `!` probe lines with the `case "$ARGUMENTS" in *--snapshot*)` gating structure
  - Short-circuit section for empty clean sessions
  - Seven-step checklist (processes, branches, decisions, dispositions, claims, spend, handoff)
  - Report section with `--list` / `--last` pointers and explicit rejection of `claude --resume`
- Tracked past `.gitignore` line 37 via `git add -f` (matching precedent of `.claude/commands/work.md`).
- A CI gate check in `scripts/ci/compiler_roundtrip.sh` validates that `.claude/commands/wrap.md` exists and invokes `scripts/ops/wrap.sh`.

### P8 · Division of Labor: Script vs Session (D9)
- `wrap.sh` is strictly deterministic (bash + git + gh + jq, zero LLM calls).
- The script inventories resources, gathers check verdicts, formats the handoff block, and outputs candidate lists.
- Semantic tasks (Check 7 decision reconciliation, Check 10 artifact footnotes, handoff narrative composition, and Learnings evaluation) are prompted by the script and completed by the session.

### P9 · Scope Boundary Enforcement (D10, D15)
- Permitted files for implementation PR: `scripts/ops/wrap.sh`, `.claude/commands/wrap.md`, `scripts/ops/tests/wrap_test.sh`, `.github/workflows/ci-gates.yml` (solely to wire `wrap_test.sh`), `scripts/ci/compiler_roundtrip.sh`, `docs/SPEC.md`, `AGENTS.md`, `intent/85-session-close-out/spec.md`.
- Untouched files: `scripts/ops/work.sh`, `scripts/ops/claim.sh`, `personas/**`, `config/**`, any other workflow file.

### P10 · Two Execution Modes and Overwrite-in-Place Mechanics (D11)
- `--snapshot`: writes/refreshes handoff file mid-flight, marks line 1 `SNAPSHOT (session still running, written HH:MMZ)`, skips close-out-only checks (Checks 1, 4, 5, 8 label removal, 10, 18, and Learnings), leaves session running, exits 0.
- Bare `/wrap`: runs full close-out across all 12 checks + Learnings, replaces snapshot header, outputs full report, and terminates the session.
- Destination: `<primary-checkout>/ops/handoffs/handoff-<seat>-<YYYY-MM-DD>[-n].txt`.
- Overwrites in place so a session leaves exactly one handoff file regardless of snapshot count. Suffix `-n` increments only if a different session previously wrote today's file for that seat.

### P11 · Mode-Gated Probes and Empty-Session Short-Circuit (D12)
- Cheap probes (`git status --short --branch`, side-channel context/spend line) run in both modes.
- Expensive network and worktree probes (`git fetch origin`, `git log HEAD..origin/main`, `gh pr list --author @me`, `scripts/ops/worktrees.sh`) run in close-out mode only. Under `--snapshot`, network and worktree probe calls are strictly zero (proven by contract test PATH shims).
- Short-circuit: If git status is clean, ref is up to date with `origin/main`, no session PRs exist, and no decisions, run artifacts, or tracker claims were created: outputs `nothing to hand off: session clean and produced no state`, writes zero handoff files under `ops/handoffs/`, and exits 0 immediately.

### P12 · Seat Resolution Order, Verbatim Resume Block, and Priming Scope Handoff (D13, D14)
- Seat resolution order:
  1. CLI argument (`/wrap <seat-or-slug>`)
  2. `$CLAUDE_SEAT` (for sessions launched via `seat.sh`)
  3. Existing `handoff-<slug>-<today>.txt` written by this session
  4. Minted short kebab-case slug naming the work (`harness-statusline`, `poller-fix-round`)
- An ad-hoc slug that does not match an existing handoff refuses with exit 2 to prevent silent resumption of unrelated work.
- Concludes by printing the verbatim copyable resume block:
  ```text
  handoff:  <absolute-path>
  resume:   ops/waves/seat.sh <seat>
  session:  ${CLAUDE_SESSION_ID}
  ```
- Points to `ops/waves/seat.sh --list` and `ops/waves/seat.sh --last`.
- Explicitly rejects `claude --resume` as improper because it replays prior transcripts into context at high cost.
- Scope handoff to #330 (D14): Issue #85 owns writing and reading handoffs; issue #330 owns successor priming injection via `SessionStart` hooks in `.claude/settings.json`.
- Untracked dependency convention: live inspection of `ops/waves/seat.sh` and `ops/harness/newest-handoff.sh` confirms the handoff path format is `<primary-checkout>/ops/handoffs/handoff-<seat>-<YYYY-MM-DD>[-n].txt`.

---

## 4. Micro-Stepped Tasks

### Task T1: Commit Hermetic Contract Test Suite
- **Owner:** daedalus (Build stage)
- **File touched:** `scripts/ops/tests/wrap_test.sh`
- **Decisions implemented:** D1–D15
- **Acceptance criteria proven:** AT-1 through AT-19
- **Description:** Implement the complete hermetic test suite covering all 19 acceptance test scenarios, with each assertion citing its Decision ID and Acceptance Test ID. Eliminates all backdoor environment variables in favor of hermetic sandbox fixtures and PATH stubs over `git`, `gh`, and `worktrees.sh`. Resets `rc=0` before each capture. Test suite runs red (clean assertion failures, zero runtime or syntax errors) against current unbuilt codebase.
- **Done when:** `bash scripts/ops/tests/wrap_test.sh` runs cleanly to completion, outputs expected failure lines for unimplemented features, and exits 1.

---

### Task T2: Implement `scripts/ops/wrap.sh` CLI Interface, Gated Probes, and Short-Circuit
- **Owner:** odyssey (Implement stage)
- **File touched:** `scripts/ops/wrap.sh`
- **Decisions implemented:** D2, D7, D12
- **Acceptance criteria proven:** AT-13, AT-17, AT-18
- **Description:**
  1. Create `scripts/ops/wrap.sh` with `set -euo pipefail`.
  2. Validate required tools (`git`, `gh`, `jq`, `gawk`) and verify execution inside a git repository; exit 1 if requirements are missing.
  3. Parse positional arguments: session name (required), seat/slug (optional), `--snapshot` flag, and `DRY_RUN` mode.
  4. Implement mode-gated probe discipline: execute cheap local status probes in both modes; gate expensive network calls (`git fetch`, `gh pr list`) and worktree scans (`scripts/ops/worktrees.sh`) to close-out mode only.
  5. Implement empty-session short-circuit: if git status is clean, HEAD equals `origin/main`, and no decisions, artifacts, or tracker claims were produced, output `nothing to hand off: session clean and produced no state`, write zero files to `ops/handoffs/`, and exit 0 immediately.

---

### Task T3: Implement Process, Branch Sync, Primary Checkout, and PR CI Checks
- **Owner:** odyssey (Implement stage)
- **File touched:** `scripts/ops/wrap.sh`
- **Decisions implemented:** D1, D3, D6
- **Acceptance criteria proven:** AT-2, AT-3, AT-4, AT-5
- **Description:**
  1. **Check 1 (In-flight processes):** Scan process table for active child processes or subagents belonging to the session: (a) active child processes spawned under the harness/caller PID tree (`$PPID`, excluding `wrap.sh` and its direct subshell pipeline children), and (b) active PIDs recorded in worktree lock files (`$GIT_COMMON_DIR/worktrees/<name>/locked`). If any active process remains running, report `fail` and exit 2 (`refused: child processes still running`).
  2. **Check 3 (Branch sync):** Check git status of worktrees belonging to this session; report `fail` and exit 2 (`refused: unpushed commits on <branch>`) if local HEAD diverges from remote HEAD.
  3. **Check 4 (Primary checkout):** Check primary checkout branch and git status; report `fail` and exit 2 (`refused: primary checkout dirty or behind origin/main`) if dirty or behind `origin/main`.
  4. **Check 5 (Session PRs):** Query `gh pr list --author @me`; apply three-way derivation rule: code defect fails and exits 2 (`refused: PR #<n> checks failing`); ambient environment defect (#167) reports `warn` and exits 0; foreign unmerged PR reports `warn`.

---

### Task T4: Implement Decision Accounting, Claim Release & Auto-Repair, Artifact Disposition, and Compiler Integrity Checks (`risk: high`)
- **Owner:** odyssey (Implement stage)
- **File touched:** `scripts/ops/wrap.sh`
- **Decisions implemented:** D1, D4, D6, D9
- **Acceptance criteria proven:** AT-6, AT-7, AT-8, AT-9
- **Risk:** High (touches issue label state machines and mutexes; triggers DEEP-3 / DEEP-5).
- **Description:**
  1. **Check 7 (Decision accounting):** Output prompt inventory of material decisions for session reconciliation; verify all decisions map to an issue, PR, or explicit deferral.
  2. **Check 8 (Claim release & auto-repair):** Scan issues claimed by this session.
     - Fallback lock path: query `$GIT_COMMON_DIR/worktrees/<name>/locked` per `scripts/ops/worktrees.sh:79`.
     - If Done/Decided/Next/Blocked handoff comment exists and `in-progress` remains: under normal execution, remove `in-progress` via GitHub REST API `DELETE repos/<repo>/issues/<n>/labels/in-progress`, print `fixed: removed in-progress from #<n>`, and proceed to exit 0. Under `DRY_RUN=1`, print `would: remove in-progress from #<n>`, report `fail: #<n> carries in-progress (dry-run)`, make zero API write calls, and exit 2.
     - If handoff comment is missing: report `fail: missing handoff comment on #<n>` and exit 2.
  3. **Check 10 (Artifact disposition):** Scan `runs/` for files created this session; verify each carries a disposition footnote or sidecar. Report `fail: artifact <path> missing disposition` and exit 2 if omitted.
  4. **Check 12 (Compiler drift):** Run BOTH `python3 scripts/sync_agents.py --check` AND `bash scripts/ci/compiler_roundtrip.sh` on primary checkout; report `fail` and exit 2 if drift is detected.

---

### Task T5: Implement Worktree Hygiene, Spend Rollup, Credential Scan, Temp Cleanup, and Mandatory Learnings Step
- **Owner:** odyssey (Implement stage)
- **File touched:** `scripts/ops/wrap.sh`
- **Decisions implemented:** D1, D5, D6
- **Acceptance criteria proven:** AT-10, AT-11, AT-12
- **Description:**
  1. **Check 15 (Worktree hygiene):** Evaluate worktrees via `scripts/ops/worktrees.sh`. Report session-owned dirty worktrees as `fail` (exit 2). Report session-owned safe worktrees as `pass`. Report foreign dirty/locked worktrees as `warn` (included in handoff block without blocking exit 0).
  2. **Check 16 (Spend measurement):** Read side-channel file `~/.claude/context/<session>.json` and compute spend metrics via `scripts/ops/session_spend.sh`.
  3. **Check 17 (Credential leak scan):** Scan session commits, staged diffs, and posted comments for secret shapes (using patterns from `sanitize_check.sh`). Report `fail: credential exposure detected` and exit 2 if found.
  4. **Check 18 (Temp file cleanup):** Check for and clean up temporary body files created by this session under `/tmp`.
  5. **Learnings Step (Mandatory):** In close-out mode, verify that `WRAP_LEARNINGS` is provided with `none`, `learnings: no learnings to persist`, or a persisted learning identifier. If unset or empty, report `fail: learnings step omitted` and exit 2. In snapshot mode, skip the check.

---

### Task T6: Implement Seat Resolution Order, Handoff File Writing, Overwrite Mechanics, and Resume Block
- **Owner:** odyssey (Implement stage)
- **File touched:** `scripts/ops/wrap.sh`
- **Decisions implemented:** D11, D13
- **Acceptance criteria proven:** AT-1, AT-16, AT-19
- **Description:**
  1. Implement seat resolution order: argument -> `$CLAUDE_SEAT` -> existing session handoff -> minted kebab-case slug. Refuse unrecognized ad-hoc slugs with exit 2.
  2. Assemble handoff file at `<primary-checkout>/ops/handoffs/handoff-<seat>-<YYYY-MM-DD>[-n].txt`.
  3. In `--snapshot` mode: mark line 1 `SNAPSHOT (session still running, written HH:MMZ)` and exit 0. Repeated snapshot calls from the same session overwrite in place without incrementing suffix `-n`.
  4. In close-out mode: write full close-out handoff, replace snapshot header, print exact status line `closed` (or `status: closed`), and output verbatim resume block:
     ```text
     handoff:  <absolute-path>
     resume:   ops/waves/seat.sh <seat>
     session:  ${CLAUDE_SESSION_ID}
     ```
  5. Print pointers to `ops/waves/seat.sh --list` and `ops/waves/seat.sh --last`, and reject `claude --resume`.

---

### Task T7: Track Tested Claude Code Door and Add Compiler Roundtrip Door Check
- **Owner:** odyssey (Implement stage)
- **Files touched:** `.claude/commands/wrap.md`, `scripts/ci/compiler_roundtrip.sh`
- **Decisions implemented:** D8
- **Acceptance criteria proven:** AT-14
- **Description:**
  1. Author `.claude/commands/wrap.md` taking the tested prototype from issue comment 5610016589 as-is:
     - Allowed-tools frontmatter
     - Two batched `!` probe lines with `case "$ARGUMENTS" in *--snapshot*)`
     - Short-circuit section
     - Seven-step checklist
     - Report section with resume block, pointers, and `claude --resume` rejection
     - Non-aborting execution format so exit code 2 does not abort turn
  2. Force-add `.claude/commands/wrap.md` past `.gitignore` line 37 via `git add -f`.
  3. Add tracking assertion in `scripts/ci/compiler_roundtrip.sh` verifying `.claude/commands/wrap.md` exists, is tracked in git, and invokes `scripts/ops/wrap.sh`.

---

### Task T8: Register CI Test Suite, Upsert Living Spec (`ops.wrap`), and Update Session Checklist (`risk: high`)
- **Owner:** odyssey (Implement stage)
- **Files touched:** `.github/workflows/ci-gates.yml`, `docs/SPEC.md`, `AGENTS.md`
- **Decisions implemented:** D10, D15
- **Acceptance criteria proven:** AT-15
- **Risk:** High (modifies CI workflow file `.github/workflows/ci-gates.yml`; triggers DEEP-1 / DEEP-5).
- **Description:**
  1. In `.github/workflows/ci-gates.yml`, add execution step for `bash scripts/ops/tests/wrap_test.sh` to the CI test job per D15.
  2. In `docs/SPEC.md`, add capability `ops.wrap` detailing `/wrap` behavior, dual modes, auto-repair, probe gating, and resume semantics.
  3. In `AGENTS.md`, update the Session checklist (Step 4 / 5) to include the terminal `/wrap` invocation.
  4. Verify `scripts/ci/spec_check.sh origin/main` and `scripts/ci/sanitize_check.sh` pass cleanly on the implementation diff.

---

### Task T9: Verify All Acceptance Tests Green, Verify Untracked Resolvers by Hand, and Pass All CI Gates
- **Owner:** odyssey (Implement stage)
- **Files touched:** none (validation only)
- **Decisions implemented:** D1–D15
- **Acceptance criteria proven:** AT-1 through AT-19
- **Description:**
  1. Verify handoff path and filename resolution manually against untracked `ops/waves/seat.sh` and `ops/harness/newest-handoff.sh`.
  2. Execute `bash scripts/ops/tests/wrap_test.sh` and verify all 19 acceptance tests pass cleanly (`ALL TESTS PASSED`, exit 0).
  3. Execute `python3 scripts/sync_agents.py --check` and `bash scripts/ci/compiler_roundtrip.sh`.
  4. Execute `bash scripts/ci/sanitize_check.sh`.
  5. Execute `bash scripts/ci/spec_check.sh origin/main`.

---

## 5. Traceability Matrix

| Decision ID | Summary | Acceptance Tests | Implementing Tasks |
|---|---|---|---|
| **D1** | Three-way ownership partition (`fail`, `warn`, `fixed`, `pass`) | AT-2, AT-3, AT-4, AT-5, AT-8, AT-9, AT-10, AT-12 | T1, T3, T4, T5 |
| **D2** | Session identity via claim comment join key & worktree lock fallback | AT-13 | T1, T2, T4 |
| **D3** | Session lifecycle boundary across processes and spend metrics | AT-2 | T1, T3 |
| **D4** | Single permitted auto-repair mutation (`in-progress` removal) & DRY_RUN | AT-6, AT-7 | T1, T4 |
| **D5** | Mandatory Learnings step (`WRAP_LEARNINGS` env interface) | AT-11 | T1, T5 |
| **D6** | V1 check selection (12 checks + Learnings; 7 deferred by number; Check 12 twin run) | AT-1, AT-2, AT-3, AT-4, AT-5, AT-8, AT-9, AT-10, AT-11, AT-12 | T1, T3, T4, T5 |
| **D7** | Exit code vocabulary (0 clean, 1 env error, 2 refused) | AT-1, AT-13 | T1, T2, T6 |
| **D8** | Tracked Claude door taking prototype in comment 5610016589 as-is & CI check | AT-14 | T1, T7 |
| **D9** | Division of labor: deterministic script vs prompted session judgment | AT-8, AT-9 | T1, T4 |
| **D10** | Scope boundary (permitted files and living spec update) | AT-15 | T1, T8 |
| **D11** | Two execution modes (`--snapshot` vs bare `/wrap`) & overwrite in place | AT-1, AT-16 | T1, T6 |
| **D12** | Mode-gated probe discipline & empty-session short-circuit | AT-17, AT-18 | T1, T2 |
| **D13** | Seat resolution order & verbatim copyable resume block | AT-19 | T1, T6 |
| **D14** | Priming scope handoff to #330 | AT-19 | T1, T6 |
| **D15** | CI test suite registration in `.github/workflows/ci-gates.yml` | AT-15 | T1, T8 |

---

## 6. Verification of Untracked Dependencies

The handoff file written by `wrap.sh` is consumed by untracked scripts in `ops/` (`.gitignore:35` excludes `ops/`):
- `ops/waves/seat.sh`
- `ops/harness/newest-handoff.sh`
- `ops/harness/newest-dated.sh`

Direct inspection of these files confirms the naming contract:
```text
<primary-checkout>/ops/handoffs/handoff-<seat>-<YYYY-MM-DD>[-n].txt
```
where `<seat>` can contain internal hyphens, `<YYYY-MM-DD>` is the ISO calendar date, and optional suffix `-n` disambiguates multiple distinct sessions writing on the same day for that seat.

---

## 7. Plan Deviation (Implement Rung, 2026-09-10)

Contract test failure accounting correction in `scripts/ops/tests/wrap_test.sh` under operator authorization ([comment 5624183049](https://github.com/evekhm/agentic-sdlc/issues/85#issuecomment-5624183049)):
- The merged contract suite `scripts/ops/tests/wrap_test.sh` at head 2a6f142 incremented shell variable `FAILURES` inside `( ... )` subshell test bodies, causing the parent shell counter to remain 0 and exit 0 against a stub `wrap.sh` whose body was `exit 0` once AT-14/AT-15 passed.
- Corrected failure accounting by recording failures to a temporary log file (`$FAIL_LOG`) created at suite startup and cleaned up on EXIT trap, with `fail()` appending `1` to `$FAIL_LOG` and the summary block computing `FAILURES=$(wc -l < "$FAIL_LOG")`. No assertion, fixture, AT body or Decision citation was changed.
- Acceptance proven: with `WRAP_SH` pointing at a stub whose body is `exit 0`, the suite exits nonzero (exit 1) and its reported count equals its FAIL lines.

