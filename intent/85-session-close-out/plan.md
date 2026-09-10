# Plan: Session Close-Out (/wrap)

**Issue:** #85 · **Spec:** `intent/85-session-close-out/spec.md` (Approved, D1–D14, AT-1–AT-20)  
**Author:** daedalus (`evekhm-daedalus-app[bot]`)  
**Base commit:** `c2c317a44f6fe2e098bb499d23335630e5d9d17f`  
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
The solution is a single user command, `/wrap`, typed by an operator in either harness (Claude Code or Antigravity) or invoked by automated runners:
1. Implemented once in a deterministic, harness-agnostic script: `scripts/ops/wrap.sh`.
2. Exposed through two tracked harness doors (`.claude/commands/wrap.md` and `.agents/workflows/wrap.md`) with CI drift gate enforcement.
3. Supporting two modes: `--snapshot` (refresh handoff mid-flight, keep working) and bare `/wrap` (close-out and stop).
4. Deriving verdicts via a strict three-way ownership rule (`pass`, `fail`, `warn`, `fixed`).
5. Enforcing a single auto-repair mutation (removing forgotten `in-progress` labels when a complete handoff comment exists; `DRY_RUN=1` prints would-fix and exits 2).
6. Short-circuiting clean, empty sessions immediately without writing unneeded handoff files.
7. Ending by writing `<primary-checkout>/ops/handoffs/handoff-<seat>-<YYYY-MM-DD>[-n].txt` and emitting a verbatim resume command (`ops/waves/seat.sh <seat>`).

---

## 2. Scope and Persona Boundaries

| Actor | Stage | Authority / Files Touched | Role in Issue #85 |
|---|---|---|---|
| **athena** | plan / design | `intent/**` | Authored `intent.md` and approved `spec.md` (PR #346). |
| **daedalus** | build | `intent/**`, `scripts/*/tests/**` | Authors `plan.md` and commits hermetic contract tests in `scripts/ops/tests/wrap_test.sh`. Daedalus **never** writes production code (`scripts/ops/wrap.sh`, harness doors, or `docs/SPEC.md`). |
| **odyssey** | implement | `scripts/ops/wrap.sh`, `.claude/commands/wrap.md`, `.agents/workflows/wrap.md`, `scripts/ops/tests/wrap_test.sh`, `scripts/ci/compiler_roundtrip.sh` (or CI gate), `docs/SPEC.md`, `AGENTS.md` | Implements the plan at pinned base commit `c2c317a44f6fe2e098bb499d23335630e5d9d17f`, turning contract tests green, updating `docs/SPEC.md` (`ops.wrap`), updating `AGENTS.md`, and passing all CI gates. |
| **argus / atlas** | review | comments only | Review pull requests against spec and plan using independent models. |
| **themis** | autonomous merge | GitHub Actions (`merge-gate.yml`) | Evaluates conjuncts and autonomously merges pull requests upon consensus. |

---

## 3. The Calls This Plan Makes

### P1 · Three-Way Derivation Rule and Four Verdicts (D1, D6)
In `scripts/ops/wrap.sh`, every check evaluates to one of four states (`pass`, `fail`, `warn`, `fixed`) using an objective three-way partition:
1. **`fail`** (blocks close-out, exit 2): An anomaly in a resource owned and actionable by this session (e.g. unpushed commits on this session's branch, dirty primary checkout, child processes active, omitted learnings, credential leak).
2. **`warn`** (recorded in handoff, does not block close-out):
   - An anomaly in a foreign resource (a peer session's dirty worktree, an unmerged foreign PR).
   - An anomaly in a session-owned resource that is *not actionable* by this session due to an ambient environment defect (e.g. #167 runner infrastructure outages, unpriced model tiers in spend reporting).
3. **`fixed`** (auto-repaired, exit 0): An issue claimed by this session that carries a complete Done/Decided/Next/Blocked handoff comment where only the `in-progress` label was forgotten (triggers D4 auto-repair).
4. **`pass`**: Condition requirements are completely satisfied.

### P2 · Session Identity, Join Key, and Worktree Lock Fallback (D2, D3)
- The primary join key for identifying session-owned resources is the session name recorded in the structured claim comment (`Claim: <actor> (<session>), stage: <stage>...`, mandated by `claim.sh` #92).
- Worktree lock metadata (`.claude/worktrees/*/.lock` per #77/#80) acts as secondary fallback for child or transient worktrees.
- `wrap.sh` requires the session name as its first positional argument: `scripts/ops/wrap.sh <session-name> [seat-or-slug] [--snapshot]`.
- App identities and branch prefixes are explicitly rejected as join keys because parallel sessions share them.
- Session lifecycle scope (D3): A session bounds all actions under that session name from claim to close-out. Check 1 verifies child processes of that session context have exited. Check 16 rolls up spend metrics for transcripts generated during that session.

### P3 · Single Permitted Auto-Repair and DRY_RUN Contract (D4)
- `wrap.sh` executes exactly **one** automated mutation: removing a lingering `in-progress` label from an issue claimed by this session when a valid Done/Decided/Next/Blocked handoff comment already exists.
- In normal execution: calls GitHub REST API `DELETE repos/<repo>/issues/<n>/labels/in-progress`, prints `fixed: removed in-progress from #<n>`, and proceeds to exit 0.
- Under `DRY_RUN=1`: makes zero API write calls, prints `would: remove in-progress from #<n>`, reports `fail: #<n> carries in-progress (dry-run)`, and exits 2.
- All other mutations are strictly prohibited: `wrap.sh` never synthesizes missing handoff comments, never deletes branches, never prunes foreign worktrees, and never unclaims issues without handoffs.

### P4 · Mandatory Learnings Step (D5)
- Close-out evaluation includes a mandatory learnings check that cannot be bypassed silently.
- The outcome is binary: either a learning is persisted (demonstrated by a documentation change in the PR or an issue filed naming the target doc) OR the wrap input explicitly attests `learnings: no learnings to persist`.
- If neither is provided, `wrap.sh` reports `fail: learnings step omitted` and exits 2.

### P5 · V1 Check Selection and Ordering Principle (D6)
Shipped in v1 (12 checks + Learnings step):
- Check 1: In-flight child processes & subagents (close-out only)
- Check 3: Worktree branch synchronization (both modes)
- Check 4: Primary checkout on main & clean (close-out only)
- Check 5: Session PR status: merged or green (close-out only)
- Check 7: Decision accounting against tracker (both modes)
- Check 8: Claim release & handoff comment (close-out only)
- Check 10: Run artifact disposition footnotes (close-out only)
- Check 12: Compiler roundtrip & drift parity (close-out only)
- Check 15: Worktree hygiene report & session safe worktrees (close-out only)
- Check 16: Session spend measurement via side-channel (both modes)
- Check 17: Credential leak detection (both modes)
- Check 18: Temporary body file cleanup under `/tmp` (close-out only)
- Learnings Step: Mandatory operational knowledge harvest (both modes)

Deferred to post-v1 by number: Checks 2, 6, 9, 11, 13, 14, 19.

### P6 · Exit Code Vocabulary (D7)
- `0`: Clean / Closed (all session-owned checks pass or fixed via D4, foreign warnings reported, or clean short-circuit).
- `1`: Environment / input failure (missing `git`, `gh`, `jq`, `gawk`, unreadable repository, missing session name argument, or GitHub API network/auth failure).
- `2`: Refused / Not closed (one or more session-owned checks failed, or dry-run would-fix encountered).

### P7 · Dual Harness Doors, Parity, and CI Drift Gate (D8)
- Both doors ship tracked in the repository: `.claude/commands/wrap.md` for Claude Code and `.agents/workflows/wrap.md` for Antigravity.
- Tracked past `.gitignore` line 37 via `git add -f` (matching precedent of `.claude/commands/work.md`).
- Both doors invoke `scripts/ops/wrap.sh $ARGUMENTS` in their non-aborting headless execution forms; checklists remain prompts for semantic judgment, while deterministic checks execute in `wrap.sh`.
- A CI drift gate (in `scripts/ci/compiler_roundtrip.sh` or dedicated drift check) validates that both doors exist and invoke `wrap.sh`, failing the build if either diverges.

### P8 · Division of Labor: Script vs Session (D9)
- `wrap.sh` is strictly deterministic (bash + git + gh + jq, zero LLM calls).
- The script inventories resources, gathers check verdicts, formats the handoff block, and outputs candidate lists.
- Semantic tasks (Check 7 decision reconciliation, Check 10 artifact footnotes, handoff narrative composition, and Learnings evaluation) are prompted by the script and completed by the session.

### P9 · Scope Boundary Enforcement (D10)
- Permitted files for implementation PR: `scripts/ops/wrap.sh`, `.claude/commands/wrap.md`, `.agents/workflows/wrap.md`, `scripts/ops/tests/wrap_test.sh`, `scripts/ci/compiler_roundtrip.sh` (or CI gate), `docs/SPEC.md`, `AGENTS.md`.
- Untouched files: `scripts/ops/work.sh`, `scripts/ops/claim.sh`, `personas/**`, `config/**`, `.github/workflows/**`.

### P10 · Two Execution Modes and Overwrite-in-Place Mechanics (D11)
- `--snapshot`: writes/refreshes handoff file mid-flight, marks line 1 `SNAPSHOT (session still running, written HH:MMZ)`, skips close-out-only checks (Checks 1, 4, 5, 8 label removal, 10, 18), leaves session running, exits 0.
- Bare `/wrap`: runs full close-out across all 12 checks + Learnings, replaces snapshot header, outputs full report, and terminates the session.
- Destination: `<primary-checkout>/ops/handoffs/handoff-<seat>-<YYYY-MM-DD>[-n].txt`.
- Overwrites in place so a session leaves exactly one handoff file regardless of snapshot count. Suffix `-n` increments only if a *different* session previously wrote today's file for that seat.

### P11 · Mode-Gated Probes and Empty-Session Short-Circuit (D12)
- Cheap probes (`git status --short --branch`, side-channel context/spend line) run in both modes.
- Expensive network and worktree probes (`git fetch origin`, `git log HEAD..origin/main`, `gh pr list --author @me`, `scripts/ops/worktrees.sh`) run in close-out mode only.
- Short-circuit: If git status is clean, ref is up to date with `origin/main`, no session PRs exist, and no decisions, run artifacts, or tracker claims were created: outputs `nothing to hand off: session clean and produced no state`, writes zero handoff files, and exits 0 immediately.

### P12 · Seat Resolution Order, Verbatim Resume Block, and Priming Parity (D13, D14)
- Seat resolution order:
  1. CLI argument (`/wrap <seat-or-slug>`)
  2. `$CLAUDE_SEAT` (or environment seat variable)
  3. Existing `handoff-<slug>-<today>.txt` written by this session
  4. Minted short kebab-case slug naming the work (`harness-statusline`, `poller-fix-round`)
- Concludes by printing the verbatim copyable resume block:
  ```text
  handoff: <absolute-path>
  resume: ops/waves/seat.sh <seat>
  session: <session-id>
  ```
- Points to `ops/waves/seat.sh --list` and `ops/waves/seat.sh --last`.
- Cross-harness priming: Claude Code auto-injects via `SessionStart` hook; Antigravity injects via launcher dispatch prompt primer.
- Unified side-channel: Both harnesses read normalized metrics from `~/.claude/context/<session>.json`.

---

## 4. Micro-Stepped Tasks

### Task T1: Commit Hermetic Contract Test Suite
- **Owner:** daedalus (Build stage)
- **File touched:** `scripts/ops/tests/wrap_test.sh`
- **Decisions implemented:** D1–D14
- **Acceptance criteria proven:** AT-1 through AT-20
- **Description:** Implement the complete hermetic test suite covering all 20 acceptance test scenarios, with each assertion citing its Decision ID and Acceptance Test ID. Test runs red (failing assertions, zero runtime/syntax errors) against current unbuilt codebase.
- **Done when:** `bash scripts/ops/tests/wrap_test.sh` runs cleanly to completion, outputs expected failure lines for unimplemented features, and exits 1.

---

### Task T2: Implement `scripts/ops/wrap.sh` Core CLI, Arguments, and Seat Resolution
- **Owner:** odyssey (Implement stage)
- **File touched:** `scripts/ops/wrap.sh`
- **Decisions implemented:** D2, D7, D11, D12, D13
- **Acceptance criteria proven:** AT-13, AT-16, AT-17, AT-18, AT-19
- **Description:**
  1. Create `scripts/ops/wrap.sh` with `set -euo pipefail`.
  2. Validate required tools (`git`, `gh`, `jq`, `gawk`) and exit 1 if missing.
  3. Parse arguments: session name (required), seat/slug (optional), `--snapshot` flag, and `DRY_RUN` mode.
  4. Implement seat resolution order: CLI arg → `$CLAUDE_SEAT` → existing session handoff → minted kebab-case slug.
  5. Implement empty-session short-circuit: if git status is clean, HEAD equals `origin/main`, and no state was produced, output `nothing to hand off: session clean and produced no state`, write no files, and exit 0.
  6. Implement probe gating: run cheap probes under `--snapshot` and defer expensive network/worktree probes to close-out mode.

---

### Task T3: Implement Process, Branch Sync, Primary Checkout, and PR CI Checks
- **Owner:** odyssey (Implement stage)
- **File touched:** `scripts/ops/wrap.sh`
- **Decisions implemented:** D1, D3, D6
- **Acceptance criteria proven:** AT-2, AT-3, AT-4, AT-5
- **Description:**
  1. **Check 1 (In-flight processes):** Scan process table for active child processes or subagents spawned under this session's PID tree; report `fail` and exit 2 (`refused: child processes still running`) if any remain active.
  2. **Check 3 (Branch sync):** Check git status of worktrees belonging to this session; report `fail` and exit 2 (`refused: unpushed commits on <branch>`) if local HEAD diverges from remote HEAD.
  3. **Check 4 (Primary checkout):** Check primary checkout branch and git status; report `fail` and exit 2 (`refused: primary checkout dirty or behind origin/main`) if dirty or behind `origin/main`.
  4. **Check 5 (Session PRs):** Query `gh pr list --author @me`; apply three-way derivation rule: code defect fails and exits 2 (`refused: PR #<n> checks failing`); ambient environment defect (#167) reports `warn` and exits 0; foreign unmerged PR reports `warn`.

---

### Task T4: Implement Decision Accounting, Claim Release, Artifact Footnotes, and Compiler Drift
- **Owner:** odyssey (Implement stage)
- **File touched:** `scripts/ops/wrap.sh`
- **Decisions implemented:** D1, D4, D6, D9
- **Acceptance criteria proven:** AT-6, AT-7, AT-8, AT-9
- **Description:**
  1. **Check 7 (Decision accounting):** Output prompt inventory of material decisions for session reconciliation; verify all decisions map to an issue, PR, or explicit deferral.
  2. **Check 8 (Claim release & auto-repair):** Scan issues claimed by this session.
     - If Done/Decided/Next/Blocked handoff comment exists and `in-progress` remains: under normal execution, remove `in-progress` via GitHub REST API, print `fixed: removed in-progress from #<n>`, and proceed to exit 0. Under `DRY_RUN=1`, print `would: remove in-progress from #<n>`, report `fail: #<n> carries in-progress (dry-run)`, and exit 2.
     - If handoff comment is missing: report `fail: missing handoff comment on #<n>` and exit 2.
  3. **Check 10 (Artifact disposition):** Scan `runs/` for files created this session; verify each carries a disposition footnote or sidecar. Report `fail: artifact <path> missing disposition` and exit 2 if omitted.
  4. **Check 12 (Compiler drift):** Run `python3 scripts/sync_agents.py --check` on primary checkout; report `fail` and exit 2 if drift is detected.

---

### Task T5: Implement Worktree Hygiene, Spend Rollup, Credential Scan, Temp Cleanup, and Learnings Step
- **Owner:** odyssey (Implement stage)
- **File touched:** `scripts/ops/wrap.sh`
- **Decisions implemented:** D1, D5, D6, D14
- **Acceptance criteria proven:** AT-10, AT-11, AT-12
- **Description:**
  1. **Check 15 (Worktree hygiene):** Evaluate worktrees via `scripts/ops/worktrees.sh`. Report session-owned dirty worktrees as `fail` (exit 2). Report session-owned safe worktrees as `pass`. Report foreign dirty/locked worktrees as `warn` (included in handoff block without blocking exit 0).
  2. **Check 16 (Spend measurement):** Read normalized side-channel file `~/.claude/context/<session>.json` (D14) and compute spend metrics via `scripts/ops/session_spend.sh`.
  3. **Check 17 (Credential leak scan):** Scan session commits, staged diffs, and posted comments for secret shapes (using patterns from `sanitize_check.sh`). Report `fail: credential exposure detected` and exit 2 if found.
  4. **Check 18 (Temp file cleanup):** Check for and clean up temporary body files created by this session under `/tmp`.
  5. **Learnings Step (Mandatory):** Verify that wrap input carries a persisted learning reference (doc change in PR or issue filed) or explicit string `learnings: no learnings to persist`. If missing, report `fail: learnings step omitted` and exit 2.

---

### Task T6: Implement Handoff File Writing, Overwrite Mechanics, and Resume Block
- **Owner:** odyssey (Implement stage)
- **File touched:** `scripts/ops/wrap.sh`
- **Decisions implemented:** D11, D13
- **Acceptance criteria proven:** AT-1, AT-16, AT-19
- **Description:**
  1. Assemble handoff file at `<primary-checkout>/ops/handoffs/handoff-<seat>-<YYYY-MM-DD>[-n].txt`.
  2. In `--snapshot` mode: mark line 1 `SNAPSHOT (session still running, written HH:MMZ)` and exit 0.
  3. In close-out mode: write full close-out handoff, replace snapshot header, print `closed`, and output verbatim resume block:
     ```text
     handoff: <absolute-path>
     resume: ops/waves/seat.sh <seat>
     session: <session-id>
     ```
  4. Implement single-file overwrite: repeated calls from the same session overwrite in place without incrementing `-n`. Suffix `-n` increments only if a different session previously wrote today's file for that seat.

---

### Task T7: Implement Tracked Harness Doors and CI Drift Gate
- **Owner:** odyssey (Implement stage)
- **Files touched:** `.claude/commands/wrap.md`, `.agents/workflows/wrap.md`, `scripts/ci/compiler_roundtrip.sh` (or CI gate script)
- **Decisions implemented:** D8
- **Acceptance criteria proven:** AT-14
- **Description:**
  1. Author `.claude/commands/wrap.md` invoking `scripts/ops/wrap.sh $ARGUMENTS` in non-aborting execution format.
  2. Author `.agents/workflows/wrap.md` invoking `scripts/ops/wrap.sh $ARGUMENTS` in Antigravity non-aborting format.
  3. Force-add both doors past `.gitignore` line 37 via `git add -f`.
  4. Add drift check to `scripts/ci/compiler_roundtrip.sh` asserting both doors exist and invoke `scripts/ops/wrap.sh`.

---

### Task T8: Upsert Living Spec (`ops.wrap`) and Update Session Checklist in `AGENTS.md`
- **Owner:** odyssey (Implement stage)
- **Files touched:** `docs/SPEC.md`, `AGENTS.md`
- **Decisions implemented:** D10
- **Acceptance criteria proven:** AT-15
- **Description:**
  1. In `docs/SPEC.md`, add capability `ops.wrap` detailing `/wrap` behavior, dual modes, auto-repair, probe gating, and resume semantics.
  2. In `AGENTS.md`, update the Session checklist (Step 4 / 5) to include the terminal `/wrap` invocation.
  3. Verify `scripts/ci/spec_check.sh` and `scripts/ci/sanitize_check.sh` pass cleanly on the implementation diff.

---

### Task T9: Verify All Contract Tests Green and CI Gates Pass Cleanly
- **Owner:** odyssey (Implement stage)
- **Files touched:** none (validation only)
- **Decisions implemented:** D1–D14
- **Acceptance criteria proven:** AT-1 through AT-20
- **Description:**
  1. Execute `bash scripts/ops/tests/wrap_test.sh` and verify all 20 acceptance tests pass cleanly (`ALL TESTS PASSED`, exit 0).
  2. Execute `python3 scripts/sync_agents.py --check` and `bash scripts/ci/compiler_roundtrip.sh`.
  3. Execute `bash scripts/ci/sanitize_check.sh`.
  4. Execute `bash scripts/ci/spec_check.sh main`.

---

## 5. Traceability Matrix

| Decision ID | Summary | Acceptance Tests | Implementing Tasks |
|---|---|---|---|
| **D1** | Three-way ownership partition (`fail`, `warn`, `fixed`, `pass`) | AT-2, AT-3, AT-4, AT-5, AT-8, AT-9, AT-10, AT-12 | T1, T3, T4, T5 |
| **D2** | Session identity via claim comment join key & worktree lock fallback | AT-13, AT-19 | T1, T2 |
| **D3** | Session lifecycle boundary across processes and spend metrics | AT-2, AT-16 | T1, T3, T5 |
| **D4** | Single permitted auto-repair mutation (`in-progress` removal) & DRY_RUN | AT-6, AT-7 | T1, T4 |
| **D5** | Mandatory Learnings step (persisted vs attested) | AT-11 | T1, T5 |
| **D6** | V1 check selection (12 checks + Learnings; 7 deferred by number) | AT-1, AT-2, AT-3, AT-4, AT-5, AT-8, AT-9, AT-10, AT-11, AT-12, AT-16 | T1, T3, T4, T5 |
| **D7** | Exit code vocabulary (0 clean, 1 env error, 2 refused) | AT-1, AT-13 | T1, T2, T6 |
| **D8** | Tracked harness doors (`.claude/commands/wrap.md`, `.agents/workflows/wrap.md`) & CI drift gate | AT-14 | T1, T7 |
| **D9** | Division of labor: deterministic script vs prompted session judgment | AT-11 | T1, T4, T5 |
| **D10** | Scope boundary (permitted files and living spec update) | AT-15 | T1, T8 |
| **D11** | Two execution modes (`--snapshot` vs bare `/wrap`) & overwrite in place | AT-16 | T1, T2, T6 |
| **D12** | Mode-gated probe discipline & empty-session short-circuit | AT-17, AT-18 | T1, T2 |
| **D13** | Seat resolution order & verbatim copyable resume block | AT-19 | T1, T2, T6 |
| **D14** | Absorbed harness differences (launcher primer & unified side-channel) | AT-20 | T1, T5, T6 |

