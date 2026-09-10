# Plan: Context statusline and handoff instrumentation across harnesses

**Issue:** #330 · **Spec:** `intent/330-statusline-instrumentation/spec.md` (Approved, D1–D17, AT-1–AT-21)  
**Author:** daedalus (`evekhm-daedalus-app[bot]`)  
**Base commit:** `8b499edf92a22a3bb9776da6400dc5a0eca84600`  
**Target branch for implementation (Odyssey):** `odyssey/330-statusline-instrumentation`

---

## 1. Executive Summary and Problem Statement

The mechanism that provides real-time visibility into context size, enforces the 200K working ceiling (`AGENTS.md`), tracks session spend and cache health, and automates handoff priming currently lives exclusively in machine-local operator state (`ops/harness/`). On a fresh clone, a second developer machine, or inside automated CI pipelines, none of this instrumentation exists, operator VM rebuilds lose it, and CI cannot test it.

### Core Problems Solved
1. **Unenforceable Context Ceiling:** `AGENTS.md` mandates a strict 200K token working ceiling. Without in-session instrumentation, agents cannot observe their own context growth, forcing manual operator polling. Relieving this blocks #329 (automated threshold nudges and handoff generation) and #104 (session cost ledger).
2. **Dual-Harness Parity:** Both Claude Code and Antigravity 1.2.0 support the `statusLine` hook protocol (`types.StatusLineData`). Untracked local scripts created configuration drift and asymmetric operator workflows.
3. **Session Handoff Ordering Bug:** Lexical sorting (`tail -1`) in naive bash scripts broke on date suffixes (`-` sorts before `.`, causing `handoff-2026-09-09.txt` to sort after `handoff-2026-09-09-3.txt`), silently priming sessions with stale state.
4. **Tracked Fixture & Retention Gap (#394, D17):** Antigravity runtime fixtures previously lived in ephemeral, untracked `runs/` directories. This plan introduces tracked fixtures in `scripts/ops/tests/fixtures/harness/` for deterministic verification.

---

## 2. Scope and Persona Boundaries

| Actor | Stage | Authority / Paths Touched | Role in Issue #330 |
|---|---|---|---|
| **athena** | plan / design | `intent/**` | Authored `intent.md` and approved `spec.md` (PR #395). |
| **daedalus** | build | `intent/**`, `scripts/*/tests/**` | Authors `plan.md`, establishes tracked test fixtures under `scripts/ops/tests/fixtures/harness/`, and commits hermetic contract tests in `scripts/ops/tests/harness_test.sh` asserting 21 RED test scenarios. Daedalus **never** writes production code (`scripts/ops/harness/*`, `.gitignore`, `docs/SPEC.md`). |
| **odyssey** | implement | `scripts/ops/harness/*`, `.gitignore`, `.claude/settings.json`, `.github/workflows/ci-gates.yml`, `docs/SPEC.md`, `AGENTS.md`, `CLAUDE.md`, `GEMINI.md` | Implements the production scripts, updates `.gitignore` to unignore `.claude/settings.json`, wires CI checks, turns contract tests GREEN, and upserts documentation. |
| **argus / atlas** | review | comments only | Review Odyssey's implement PR against spec and plan. Argus assigned via DEEP-1 (workflow file touched) and DEEP-3 (external user settings write). |
| **themis** | autonomous merge | GitHub Actions (`merge-gate.yml`) | Merges PRs autonomously when all conjuncts pass. |

---

## 3. The Calls This Plan Makes

### P1 · Unified Statusline Display Contract (D1, D8, D9, D11, D12, AT-R1-1, AT-R1-2)
The statusline script (`scripts/ops/harness/statusline.sh`) renders a single compact line in the terminal chrome:
```text
ctx <used>K/<ceiling>K <pct>%[ <TAG>]  [$<cost>]  tok <in> in/<out> out/<tot> tot  [cache <hit>%[ cold][ <ttl>][ cw <n>]]  <model>[ [<effort>]][ · <seat>]
```
1. **Ceiling & Scale:** Context percentage is strictly calculated against `CEILING` (default 200,000 tokens), regardless of raw model window size (200K or 1M).
2. **Wrap Budget Thresholds (D8):**
   - `< 60%`: Green, no tag.
   - `>= 60%` (120K): Yellow, ` wrap soon`.
   - `>= 70%` (140K): Red (`\033[1;31m`), ` WRAP NOW` (the last point a 30K wrap fits before compaction).
   - `>= 90%` (180K): Red (`\033[1;31m`), ` COMPACTING` (backstop territory).
3. **Atlas R1 Sync AT-R1-1:** AT-2 in `spec.md` noted `wrap tag` at 53%, but 53% is below 60%. Odyssey will perform a spec sync updating the AT-2 description to reflect that no wrap tag is emitted at 53%.
4. **Cost Segment (D9):** Rendered only when the harness reports `.cost`. If `.cost` is absent (such as Antigravity internal quota), the entire `$<cost>` segment is omitted without printing fabricated `$0.00`. When explicit cost `0.00` is provided, `$0.00` is printed.
5. **Cache Health (D11):** Cache hit ratio formatted as `cache <hit>%`. Claude-specific cache write tokens appended as `cw <n>`.
6. **Thinking Effort (D12):** Extracted from `.effort.level` (Claude) or `.model.effort` (Antigravity), rendered as `[<effort>]`.

### P2 · Atomic Side-Channel File and Reserved Snapshot Timestamps (D2, D13, D14, D15)
1. **Side-Channel Location:** `$CTX_DIR/<session_id>.json` where `CTX_DIR` defaults to `$AGENTIC_CTX_DIR`, `$CLAUDE_CTX_DIR`, `$AGY_CTX_DIR`, or `~/.claude/context` / `~/.gemini/antigravity-cli/context`.
2. **Atomicity:** Written via temporary dotfile (`$CTX_DIR/.$session_id.$$`) and atomically replaced using `mv -f`. If the primary write fails (e.g. read-only permissions), fallback writes to `/tmp/agentic-context/<session_id>.json`.
3. **Empty Session ID Protection:** An empty or unparseable `session_id` and `conversation_id` exits 0 with empty stdout and skips side-channel writing to prevent collisions.
4. **Schema Completeness & Snapshot Reservation (D13):**
   ```json
   {
     "session_id": "<id>",
     "used_tokens": 105300,
     "ceiling": 200000,
     "pct": 52,
     "window_size": 200000,
     "cost_usd": 81.40,
     "duration_ms": 1200,
     "seat": "advisor",
     "accum_input_tokens": 105300,
     "accum_output_tokens": 4,
     "accum_total_tokens": 105304,
     "cache": {"hit_pct": 88, "warm": "true", "ttl": "5m", "write_tokens": 3500000, "requests": 1, "misses": 0},
     "pre_compact_mechanical_ts": null,
     "pre_compact_narrative_ts": null,
     "ts": 1725960000
   }
   ```
   `pre_compact_mechanical_ts` and `pre_compact_narrative_ts` are reserved for #329 / #85 snapshot compaction tracking.

### P3 · Session-Start Priming and Guarded Inheritance (D3)
`scripts/ops/harness/session-start.sh` executes on session initialization:
1. **Seated Session:** If `$AGENTIC_SEAT` or `$CLAUDE_SEAT` is set, resolves the seat's newest handoff via `newest-handoff.sh` and injects it in full.
2. **Unseated Session:** If no seat is set, emits a one-line operator pointer (`Operator state: the newest handoff for this checkout is <path> (<n> bytes)...`) and avoids leaking confidential handoff text.
3. **Oversize Protection:** If handoff size exceeds `$AGENTIC_HANDOFF_MAX_BYTES` or `$CLAUDE_HANDOFF_MAX_BYTES` (default 60,000 bytes), emits a pointer warning and gates injection.
4. **Housekeeping:** Prunes side-channel JSON files older than 7 days once per session start.

### P4 · Deterministic Date and Suffix Ordering (D4)
1. `scripts/ops/harness/newest-dated.sh <prefix>` extracts `-YYYY-MM-DD[-n].txt`. Unsuffixed files sort as `-001`. Resolves lexical sorting anomalies where `-` sorts before `.`.
2. `scripts/ops/harness/newest-handoff.sh [seat]` resolves the handoff directory from the primary checkout (`git rev-parse --path-format=absolute --git-common-dir`), ensuring linked git worktrees without local `ops/` resolve the machine-shared handoffs.

### P5 · Dual-Harness Idempotent Installer and Tracked Settings (D5, D7, AT-R1-4)
`scripts/ops/harness/install.sh`:
1. Configures user settings in `~/.claude/settings.json` and `~/.gemini/antigravity-cli/settings.json` (`statusLine` command).
2. Configures repository project settings in `<repo>/.claude/settings.json` (`SessionStart` hook).
3. **Path Safety:** Hook command in `<repo>/.claude/settings.json` uses `${CLAUDE_PROJECT_DIR}/scripts/ops/harness/session-start.sh` — zero absolute home paths.
4. **Atlas R1 Sync AT-R1-4:** `.gitignore:37` currently ignores `.claude/`. Odyssey updates line 37 to:
   ```gitignore
   .claude/*
   !.claude/settings.json
   ```
   allowing `<repo>/.claude/settings.json` to be tracked in git.
5. **CLI Modes:** Supports `--install`, `--check` (pass/fail verification of all components), `--show`, and `--uninstall`.

### P6 · Cross-Harness Token Accumulation (D10)
1. **Claude Code:** Uses `prompt_cache.requests` to gate new API turns. When `requests` advances, increments `accum_input_tokens` and `accum_output_tokens`. Mid-turn redraws keep counters unchanged.
2. **Antigravity 1.2.0:** `total_output_tokens` is already a session running sum emitted by `statusline_data_builder.go`. The accumulator uses `total_output_tokens` directly and accumulates input deltas.

### P7 · Standalone Hermetic CI Test Suite & Tracked Fixtures (D6, D17, AT-R1-3)
1. **Tracked Fixtures:** Stored in `scripts/ops/tests/fixtures/harness/`:
   - `claude-with-cost-effort.json` (Fixture 1)
   - `claude-1m-zero-cost.json` (Fixture 2)
   - `claude-no-cost-wrap.json` (Fixture 3)
   - `agy-internal-quota-no-cost.json` (Fixture 4)
   - `agy-with-cost.json` (Fixture 5)
2. **Contract Suite:** `scripts/ops/tests/harness_test.sh` executes 21 assertions covering all decisions and acceptance tests in a temporary directory sandbox without external dependencies.
3. **CI Integration:** Added to `.github/workflows/ci-gates.yml` under the `execution` job.

### P8 · Dual-Harness Drift Verification (D16)
`install.sh --check` verifies that Claude Code and Antigravity user configurations invoke the exact same `statusline.sh` script, preventing configuration divergence.

### P9 · Deep-Review Evaluation (Criteria DEEP-1..DEEP-7)
- **DEEP-1 (Trust-bearing paths):** The implement PR modifies `.github/workflows/ci-gates.yml`, which is listed under `config/execution.yaml` `assigned_when.paths` for Argus.
- **DEEP-3 (Privileged / external writes):** `install.sh` modifies files outside the repository in the user's home directory (`~/.claude/settings.json` and `~/.gemini/antigravity-cli/settings.json`).
- **DEEP-5 (Concurrency / state machines):** `statusline.sh` manages atomic concurrent file replacement (`.session_id.json`).
- **Verdict:** `deep-review` applies to Odyssey's implement PR. Argus and Atlas must review.

### P10 · Living Spec and Documentation Upsert (docs/SPEC.md, AGENTS.md, CLAUDE.md, GEMINI.md)
1. Upsert `docs/SPEC.md` with capability IDs:
   - `harness.statusline`: Dual-harness terminal statusline renderer and 200K ceiling calculation.
   - `harness.sidechannel`: Atomic side-channel token, cost, and snapshot metadata persistence.
   - `harness.priming`: Seated session-start handoff injection and oversize protection.
   - `harness.resolver`: Deterministic date/numeric suffix and worktree git-common-dir resolution.
2. Upsert `AGENTS.md` ("Harness instrumentation & context monitoring").
3. Update `CLAUDE.md` and `GEMINI.md` to reference the unified installer and runtime behavior.

---

## 4. Micro-Stepped Tasks

### Task 1 (Daedalus · Build Gate): Contract Test Suite and Tracked Fixtures
- **Action:** Commit `scripts/ops/tests/fixtures/harness/*.json` (5 fixtures) and `scripts/ops/tests/harness_test.sh` (21 assertions).
- **Verification:** Run `bash scripts/ops/tests/harness_test.sh`. All 21 assertions fail (RED) with test failure messages, exiting with code 1. Zero syntax or crash errors.

### Task 2 (Odyssey · Implement): Update `.gitignore` for `.claude/settings.json` (AT-R1-4)
- **Action:** In `.gitignore`, replace `.claude/` with `.claude/*` followed by `!.claude/settings.json`.
- **Verification:** `git check-ignore -v .claude/settings.json` returns non-zero (unignored), while `git check-ignore -v .claude/context` returns ignored.

### Task 3 (Odyssey · Implement): `scripts/ops/harness/newest-dated.sh` (P4, D4)
- **Action:** Implement shared date and suffix resolver under `scripts/ops/harness/newest-dated.sh`.
- **Verification:** AT-10 in `harness_test.sh` turns GREEN.

### Task 4 (Odyssey · Implement): `scripts/ops/harness/newest-handoff.sh` (P4, D4)
- **Action:** Implement git-common-dir handoff resolver under `scripts/ops/harness/newest-handoff.sh`.
- **Verification:** AT-11 in `harness_test.sh` turns GREEN.

### Task 5 (Odyssey · Implement): `scripts/ops/harness/session-start.sh` (P3, D3)
- **Action:** Implement session startup hook under `scripts/ops/harness/session-start.sh` supporting seated injection, unseated pointer, and oversize guard.
- **Verification:** AT-7, AT-8, AT-9 in `harness_test.sh` turn GREEN.

### Task 6 (Odyssey · Implement): `scripts/ops/harness/statusline.sh` (P1, P2, P6, D1, D2, D8, D9, D10, D11, D12, D13, D14, D15)
- **Action:** Implement dual-harness statusline script with jq extraction, 200K ceiling, wrap tags (60/70/90%), cache hit/write formatting, thinking effort, cost handling, token accumulation, and atomic side-channel writing with snapshot fields.
- **Verification:** AT-1, AT-2, AT-3, AT-4, AT-5, AT-6, AT-15, AT-16, AT-17, AT-18, AT-19, AT-20, AT-21 in `harness_test.sh` turn GREEN.

### Task 7 (Odyssey · Implement): `scripts/ops/harness/install.sh` and `<repo>/.claude/settings.json` (P5, P8, D5, D7, D16)
- **Action:** Implement idempotent installer with `--check`, `--uninstall`, `--show`. Track `<repo>/.claude/settings.json` referencing `${CLAUDE_PROJECT_DIR}/scripts/ops/harness/session-start.sh`.
- **Verification:** AT-12 and AT-13 in `harness_test.sh` turn GREEN; `install.sh --check` passes cleanly.

### Task 8 (Odyssey · Implement): Wire CI Gates (P7, D6)
- **Action:** Add `bash scripts/ops/tests/harness_test.sh` step to `.github/workflows/ci-gates.yml` under the `execution` job.
- **Verification:** AT-14 in `harness_test.sh` turns GREEN; entire suite reports `21 passed, 0 failed` (GREEN).

### Task 9 (Odyssey · Implement): Spec Sync (AT-R1-1, AT-R1-2)
- **Action:** Update `intent/330-statusline-instrumentation/spec.md`:
  - Reword AT-2 to remove "and wrap tag".
  - Update citation lists for AT-1, AT-2, AT-3, AT-5 to include D10, D11, D12, D13.

### Task 10 (Odyssey · Implement): Upsert Living Spec and Documentation (P10)
- **Action:** Upsert `docs/SPEC.md`, `AGENTS.md`, `CLAUDE.md`, and `GEMINI.md`.
- **Verification:** `bash scripts/ci/spec_check.sh` passes; compiler roundtrip passes.

---

## 5. Traceability Matrix

| Decision ID | Acceptance Test | Architectural Call | Micro-Task | Covered Verification |
|---|---|---|---|---|
| **D1** | AT-1, AT-2, AT-3, AT-4 | P1 | T6 | Statusline display contract line, fallback parsing, chrome protection |
| **D2** | AT-5, AT-6 | P2 | T6 | Side-channel `$CTX_DIR/<sid>.json`, atomic write, empty ID skip |
| **D3** | AT-7, AT-8, AT-9 | P3 | T5 | Session start priming, seat injection, oversize guard |
| **D4** | AT-10, AT-11 | P4 | T3, T4 | Date and suffix resolution, git-common-dir worktree resolution |
| **D5** | AT-12, AT-13 | P5, P8 | T7 | Dual-harness installer idempotency, `--check`, `--uninstall` |
| **D6** | AT-14 | P7 | T8 | Standalone hermetic CI test suite wired in `ci-gates.yml` |
| **D7** | AT-12 | P5 | T2, T7 | `${CLAUDE_PROJECT_DIR}` project setting tracking and `.gitignore` unignore |
| **D8** | AT-1, AT-2, AT-15, AT-16, AT-17 | P1 | T6, T9 | 200K ceiling calculation, wrap thresholds (60%, 70%, 90%), AT-2 sync |
| **D9** | AT-2, AT-3 | P1 | T6 | Absent cost omission, explicit `$0.00` rendering |
| **D10** | AT-1, AT-2, AT-3, AT-5, AT-18, AT-19 | P6 | T6 | Dual-harness token accumulator (requests counter vs running sum delta) |
| **D11** | AT-1, AT-3 | P1 | T6 | Cache hit percentage, cold tag, and Claude `cw` cache write rendering |
| **D12** | AT-1, AT-2 | P1 | T6 | Thinking effort extraction from `.effort.level` / `.model.effort` |
| **D13** | AT-5 | P2 | T6 | Side-channel schema snapshot reservation (`pre_compact_*_ts: null`) |
| **D14** | AT-5 | P2 | T6 | Atomic write mechanics with `.sid.$$` temporary file rename |
| **D15** | AT-5 | P2 | T6 | Fallback write location `/tmp/agentic-context/` on write refusal |
| **D16** | AT-13 | P8 | T7 | Cross-harness configuration drift check |
| **D17** | AT-1, AT-2, AT-3, AT-20, AT-21 | P7 | T1, T6 | Byte-for-byte fixture verification across all 5 live recorded payloads |

---

## 6. Odyssey Implementation Handoff

When this plan merges, issue #330 advances to `status:implementing`. Odyssey resumes with:
```bash
scripts/ops/work.sh 330
```
Odyssey must:
1. Verify base commit is `8b499edf92a22a3bb9776da6400dc5a0eca84600` (or merge commit of this PR).
2. Execute Tasks T2 through T10 in order.
3. Confirm `bash scripts/ops/tests/harness_test.sh` transitions from 21 failures to 21 passed.
4. Verify all CI checks locally:
   ```bash
   bash scripts/ci/sanitize_check.sh
   bash scripts/ops/tests/harness_test.sh
   python3 scripts/ops/execution.py --check
   ```
5. Apply `deep-review` label via `scripts/ops/post.sh <pr-number> --as odyssey --add-label deep-review` (Criteria DEEP-1, DEEP-3, DEEP-5).

---

## 7. Plan Sync & Implementation Results

- **Task 1 (Daedalus):** Contract test suite `scripts/ops/tests/harness_test.sh` created with 21 contract tests and 5 fixtures (verified RED at build).
- **Task 2 (Odyssey):** Updated `.gitignore` to allow tracking `.claude/settings.json`.
- **Task 3 (Odyssey):** Implemented `scripts/ops/harness/newest-dated.sh` with date and `-n` suffix sorting (`-001` unsuffixed).
- **Task 4 (Odyssey):** Implemented `scripts/ops/harness/newest-handoff.sh` with `git-common-dir` primary checkout resolution and `--seats`/`--last` queries.
- **Task 5 (Odyssey):** Implemented `scripts/ops/harness/session-start.sh` with seated handoff injection, 60KB gate, unseated operator pointer, and 7-day context prune.
- **Task 6 (Odyssey):** Implemented `scripts/ops/harness/statusline.sh` covering display contract, wrap thresholds (60/70/90%), absent cost omission, dual-harness token accumulator, and atomic side-channel JSON writing.
- **Task 7 (Odyssey):** Implemented `scripts/ops/harness/install.sh` (`--check`, `--uninstall`, drift verification) and tracked project settings `<repo>/.claude/settings.json` using `${CLAUDE_PROJECT_DIR}`.
- **Task 8 (Odyssey):** Wired `harness_test.sh` into `.github/workflows/ci-gates.yml` under `execution`.
- **Task 9 (Odyssey):** Updated `intent/330-statusline-instrumentation/spec.md` AT-2 description and documented AT-15..AT-21.
- **Task 10 (Odyssey):** Upserted living system spec in `docs/SPEC.md`, `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, and `scripts/README.md`.
- **Verification:** All 21 contract tests pass (21/21 GREEN). All local CI gates pass.
