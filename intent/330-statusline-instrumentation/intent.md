# Intent: context statusline and handoff instrumentation across harnesses

**Issue:** #330 · **Author:** athena (`evekhm-athena-app[bot]`) ·
**Status:** accepted on merge of this PR

## Problem

The mechanism that provides real-time visibility into context size, enforces the
200K working ceiling (`AGENTS.md`), tracks session spend and cache health, and
automates handoff priming currently lives in machine-local operator state
(`ops/harness/`). On a fresh clone or a second machine, none of this
instrumentation exists, CI cannot test it, and operator VM rebuilds lose it.

Three specific failures stem from this being untracked:

1. **The 200K context ceiling is unenforceable from the inside.** `AGENTS.md`
   defines a strict 200K token working ceiling, yet agents cannot see their own
   context size. The operator must manually monitor turn spend, request a
   handoff, wait for it to be written, and prime a successor. This is the exact
   normative-claim-without-enforcing-code defect class tracked across the repo
   (#305, #314). Unblocking #329 (automated threshold nudges and handoff writing)
   requires the instrumentation supplying the token metrics to exist in the
   repository.
2. **Untracked dual-harness reality.** Issue #330 was initially filed under the
   assumption that Antigravity had no statusline equivalent. Live runtime
   measurements on VM `evekhm` (consolidated from #336) proved that Antigravity
   implements the exact same statusline protocol (`types.StatusLineData`) and
   uses the identical user settings configuration. Leaving this untracked or
   asymmetric creates divergent, unmaintainable operator workflows.
3. **Session handoff friction and ordering bugs.** Successor sessions must
   inherit the newest handoff for their seat. The naive lexical sorting
   previously used (`tail -1`) failed on date suffixes (`-` sorts before `.`, so
   `handoff-2026-09-09.txt` sorted after `handoff-2026-09-09-3.txt`), silently
   priming sessions with the oldest file of the day.

## Proposed outcome

A fresh clone runs one tracked installer (`scripts/ops/harness/install.sh`) and
wires dual-harness statusline instrumentation and session priming without
modifying tracked repository code:

1. **Tracked scripts under `scripts/ops/harness/`:**
   - `statusline.sh`: Unified renderer across Antigravity and Claude Code.
     Displays context size against the absolute 200K ceiling, spend, total
     tokens consumed across the session, and cache hit percentage. Atomically
     writes `$CTX_DIR/<session_id>.json`.
   - `session-start.sh`: Session start hook (Claude Code) and priming script
     (Antigravity launcher dispatch) that injects the newest seat handoff,
     guarded against unseated leakage and oversize handoffs.
   - `newest-dated.sh`: Shared date and numeric suffix ordering resolver.
   - `newest-handoff.sh`: Resolves the newest seat handoff from the primary
     checkout's `ops/handoffs/` across linked worktrees.
   - `install.sh`: Idempotent installer that detects active harnesses
     (`~/.gemini/antigravity-cli` and/or `~/.claude`), configures machine-local
     settings, and provides comprehensive self-checking (`--check`).
2. **Automated CI test suite:**
   - `scripts/ops/tests/harness_test.sh` exercises all scripts against
     synthetic payloads, real dumps, edge cases (200K vs 1M window ceiling
     calculations, missing usage, corrupt input, date ordering), wired into
     `.github/workflows/ci-gates.yml`.
3. **Unblocks #329 and feeds #104:**
   - The statusline side-channel file provides the real-time token count and
     cost bridge required for automated ceiling enforcement (#329) and the
     cost ledger (#104).
4. **Living spec and documentation:**
   - `AGENTS.md` (harness-agnostic protocol), `GEMINI.md` (Antigravity binding),
     `CLAUDE.md` (Claude binding), and `docs/SPEC.md` updated to document the
     statusline and side-channel contract.

## Affected users and systems

- **Operators & Sessions:** Real-time visibility into context token growth,
  spend, and cache health across both Antigravity and Claude sessions.
- **`scripts/ops/work.sh` & `ops/waves/seat.sh`:** Resolves dated prompts and
  handoffs through tracked resolvers and passes seat identifiers.
- **#329 (context ceiling enforcement):** Consumes the `$CTX_DIR/<session_id>.json`
  side-channel file to trigger automated handoff warnings.
- **#104 (cost ledger):** Consumes per-session spend and token records.
- **CI Gates:** New test target in `.github/workflows/ci-gates.yml`.

## Constraints

- **Standard 5-rung lifecycle:** This PR touches `intent/**` only. The spec
  follows on acceptance; code and tests follow the approved spec and plan.
- **One factory (Zero duplicate scripts):** A single set of scripts in
  `scripts/ops/harness/` serves both Antigravity and Claude Code.
- **Machine-local settings stay out of Git:** Settings files (`~/.claude/`,
  `~/.gemini/antigravity-cli/`, `<repo>/.claude/settings.json`) remain
  machine-local and gitignored.
- **Absolute 200K working ceiling:** Context percentage is calculated against
  the 200K token boundary defined in `AGENTS.md`, never against the model's
  raw `context_window_size` (which varies from 200K to 1M).
- **Atomic side-channel writes:** Readers must never see partial or corrupt JSON
  files. Writes use temporary dotfiles followed by atomic rename (`mv -f`).
- **Verified mechanics only:** Document only runtime behaviors verified against
  live payloads and source code.

## Relationships

- **Consolidates #336:** Incorporates all measured Antigravity runtime evidence,
  cache read calculations, and dual-harness installer logic into master #330.
- **Unblocks #329:** Supplies the side-channel token counter and spend file.
- **Feeds #104:** Supplies real-time spend records in `$CTX_DIR/<session_id>.json`.
- **Aligns with #85, #199, #204, #259, #122.**

## Open questions

1. **Side-channel file lifecycle and retention:** `session-start.sh` performs a
   prune of files older than 7 days on startup. Should `statusline.sh` or a
   separate housekeeping cron manage disk growth under heavy parallel waves?
2. **Antigravity lifecycle hook evolution:** Antigravity currently lacks a native
   `SessionStart` hook in `hooks.json`. Does `work.sh` / `seat.sh` dispatch
   suffice, or should a `PreInvocation` single-turn gate be explored in the spec?
3. **Internal vs. External spend rendering:** When `.cost` is omitted on
   internal Vertex quota accounts, should the statusline continue rendering
   `$0.00 (XXX.XK tot)` or switch to a token-only format when cost is absent?
