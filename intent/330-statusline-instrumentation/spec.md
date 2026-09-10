# Spec: Context Statusline and Handoff Instrumentation across Harnesses

**Issue:** #330 · **Status:** Approved (approval = merge of this PR) ·
**Author:** athena (`evekhm-athena-app[bot]`) ·
**Open questions:** none

## What is being built

This specification tracks the context statusline, side-channel token instrumentation, and session handoff priming mechanisms across both Claude Code and Antigravity harnesses.

Historically, harness integration scripts lived in machine-local operator directories (`ops/harness/`). On a fresh clone or alternative development VM, none of the instrumentation exists, CI cannot verify it, and agents cannot see their own context size, making the 200K token working ceiling in `AGENTS.md` unenforceable from the inside (#305, #314).

Furthermore, earlier work assumed Antigravity required a distinct, asymmetric mechanism. Runtime measurements on VM `evekhm` (consolidated from #336) proved that Antigravity's statusline protocol (`types.StatusLineData`) was designed to mirror Claude Code's schema.

This specification formalizes a single, unified codebase under `scripts/ops/harness/` across six binding decisions:

1. **Unified Statusline Rendering (D1):** `statusline.sh` displays context token percentage against the absolute 200K working ceiling, spend, cumulative session tokens (`tok <in> in/<out> out`), prompt cache health, model name, and active seat.
2. **Side-Channel State Contract (D2):** `statusline.sh` atomically writes `$CTX_DIR/<session_id>.json` on every render, providing the real-time token count and cost bridge required for automated ceiling enforcement (#329) and the spend ledger (#104).
3. **Session Priming Contract (D3):** `session-start.sh` primes sessions with the newest handoff for their seat, gated on explicit seat identity to prevent state leakage, with oversize protection and 7-day retention housekeeping.
4. **Ordering & Worktree Resolution (D4):** `newest-dated.sh` corrects date and numeric suffix ordering (`-` vs `.` sorting bug). `newest-handoff.sh` derives the primary checkout via git common directory so linked worktrees access machine-shared `ops/handoffs/`.
5. **Idempotent Dual-Harness Installer (D5):** `scripts/ops/harness/install.sh` detects active harnesses (`~/.gemini/antigravity-cli` and/or `~/.claude`), configures machine-local user and project settings, and provides hermetic `--check` validation.
6. **Automated CI Test Suite & Scope Boundaries (D6):** `scripts/ops/tests/harness_test.sh` exercises all harness contracts in CI (`ci-gates.yml`). Updates living documentation in `AGENTS.md`, `GEMINI.md`, `CLAUDE.md`, and `docs/SPEC.md`.

```text
scripts/ops/harness/statusline.sh      # dual-harness statusline command and side-channel writer
scripts/ops/harness/session-start.sh   # session start hook and handoff priming
scripts/ops/harness/newest-dated.sh    # date + suffix ordering resolver
scripts/ops/harness/newest-handoff.sh  # worktree-aware handoff path resolver
scripts/ops/harness/install.sh         # idempotent harness installer and self-check
scripts/ops/tests/harness_test.sh      # hermetic CI test suite
.github/workflows/ci-gates.yml         # wires harness_test.sh into CI
AGENTS.md                              # protocol update under "Context ceiling"
GEMINI.md                              # Antigravity statusline binding
CLAUDE.md                              # Claude Code statusline binding
docs/SPEC.md                           # living spec update under harness.statusline
intent/330-statusline-instrumentation/spec.md # this specification
```

Settings files (`~/.claude/settings.json`, `~/.gemini/antigravity-cli/settings.json`, `<repo>/.claude/settings.json`) remain machine-local and gitignored.

---

## Decisions

| ID | Decision | Rationale |
|---|---|---|
| D1 | **Unified Statusline Rendering and Output Format.** `scripts/ops/harness/statusline.sh` accepts JSON on `stdin` and outputs a single line to `stdout`: `ctx <used>/200K <pct>%[ <tag>]  $<cost>  tok <in> in/<out> out[  cache <hit>%[ <cold>][ <ttl>]]  <model>[ · <seat>]`. (1) `<used>` is context input tokens scaled as `X.XK`. (2) `<pct>%` is computed against the absolute 200K ceiling (`used * 100 / 200000`), regardless of whether `context_window_size` is 200K or 1M. (3) `<tag>` is empty below 75%, `wrap up` at 75–99%, and `HANDOFF` at ≥100%. (4) `<cost>` formats `.cost.total_cost_usd // .cost.total_usd // 0` as `$%.2f`. When cost is 0 (internal quota), `$0.00` is displayed. (5) `tok <in> in/<out> out` displays active context input and cumulative generated output (`total_output_tokens`), formatted with `K` or `M` scaling via `fmt_tok`. (6) `cache` displays hit percentage extracted from `.prompt_cache.hit_ratio` (Claude) or derived from `current_usage.cache_read_input_tokens * 100 / turn_input` (Antigravity). (7) Unparseable input exits 0 with no output to avoid breaking terminal chrome. | Matches the measured format across Claude Code and Antigravity. Enforces the economic 200K threshold where long-context repricing occurs, rather than model-dependent window sizes. Unifies token volume and cache health reporting across harnesses. |
| D2 | **Side-Channel State Contract.** When `session_id` or `conversation_id` is non-empty, `statusline.sh` atomically writes `$CTX_DIR/<session_id>.json` (via temporary dotfile and `mv -f`). The JSON schema contains: `session_id` (string), `used_tokens` (int), `output_tokens` (int), `total_tokens` (int, `used + output`), `ceiling` (int, 200000), `pct` (int), `window_size` (int), `cost_usd` (float), `duration_ms` (int), `seat` (string), `cache` (`hit_pct`, `warm`, `ttl`, `write_tokens`, `requests`, `misses`), and `ts` (unix timestamp). The raw incoming payload is archived to `$CTX_DIR/<session_id>.raw.json`. Empty-string session IDs resulting from unauthenticated or initializing states resolve to `"unknown"` and do not emit side-channel files. `$CTX_DIR` defaults to `$AGENTIC_CTX_DIR`, `$CLAUDE_CTX_DIR`, `$AGY_CTX_DIR`, or home directory defaults (`~/.claude/context` or `~/.gemini/antigravity-cli/context`). | No harness hook receives a token count in its event payload. The side-channel file provides the sole real-time bridge for hooks, watchers, and #329 without requiring expensive transcript JSONL parsing. Atomic rename prevents concurrent readers from observing truncated JSON. |
| D3 | **Session Priming Contract.** `scripts/ops/harness/session-start.sh` primes new sessions with inherited state. (1) Drains `stdin` payload if present. (2) Resolves the newest handoff for `$SEAT` (`$AGENTIC_SEAT` / `$CLAUDE_SEAT` / `$AGY_SEAT`) via `newest-handoff.sh`. (3) If `$SEAT` is set and file size is ≤ `$MAX_BYTES` (default 60,000 bytes), injects the full handoff content to `stdout`. (4) If `$SEAT` is set and file size exceeds `$MAX_BYTES`, emits a pointer line only (`too large to inject`). (5) If `$SEAT` is unset, emits an operator pointer line only, preventing one-off sessions from inheriting unrelated seat state. (6) On each invocation, prunes side-channel files older than 7 days from `$CTX_DIR`. | Eliminates manual copy-pasting of handoffs when starting successor sessions. Guards against context window flooding from oversized handoffs. Gating on seat name prevents leaking specialized seat work into ad-hoc operator sessions. |
| D4 | **Ordering and Worktree Resolution.** (1) `scripts/ops/harness/newest-dated.sh <prefix>` lists matching `<prefix>-*.txt` files and sorts by parsed date (`YYYY-MM-DD`) and numeric suffix (`-n`). Unsuffixed filenames (`-YYYY-MM-DD.txt`) are normalized as suffix index 1 (`-001`), ensuring that `-3` sorts after the unsuffixed file. (2) `scripts/ops/harness/newest-handoff.sh [<seat>]` resolves the handoff directory from `AGENTIC_HANDOFF_DIR`, `CLAUDE_HANDOFF_DIR`, or the primary checkout's `ops/handoffs/`, derived via `git rev-parse --git-common-dir`. If the seat handoff does not exist, falls back to `handoff-plan-*.txt`. Exits 1 if no handoff exists. | Standard lexical sorting fails because `-` (0x2D) sorts before `.` (0x2E), causing `foo-2026-09-09.txt` to sort after `foo-2026-09-09-3.txt`. Linked worktrees have no `ops/` directory; resolving git's common directory guarantees all sessions find the shared operator handoffs regardless of where they run. |
| D5 | **Idempotent Dual-Harness Installer.** `scripts/ops/harness/install.sh` manages harness settings: (1) Default or `--all` auto-detects installed harnesses based on directory presence (`~/.gemini/antigravity-cli` and/or `~/.claude`). Flags `--antigravity` and `--claude` restrict targets. (2) Configures `.statusLine = {type: "command", command: $STATUSLINE, padding: 0}` in user settings. (3) Configures `.hooks.SessionStart` in repository project settings (`<repo>/.claude/settings.json`) with a 10s timeout, deduplicating existing entries. (4) `--uninstall` cleanly removes statusline and hook configurations, preserving other keys. (5) `--show` prints configured keys. (6) `--check` executes 14 end-to-end scenarios covering rendering, ceiling calculation, Antigravity spend/cache, and resolver ordering, exiting 0 on success. | Keeps settings machine-local while making VM setup a single deterministic command. Deduplication prevents repeated installs from bloating hook lists. `--check` gives operators and CI instant verification of harness wiring. |
| D6 | **Automated CI Testing and Scope Boundaries.** (1) `scripts/ops/tests/harness_test.sh` ports `--check` into a standalone, hermetic test suite executing against a temporary tree without depending on user settings or network calls. (2) Wired into `.github/workflows/ci-gates.yml`. (3) Updates `AGENTS.md` ("Context ceiling"), `GEMINI.md` ("Statusline & context side channel"), `CLAUDE.md` ("Harness configuration"), and `docs/SPEC.md` (`harness.statusline`). Files `personas/**`, `scripts/ci/merge_gate.sh`, and `scripts/ci/review_recorder.py` are not modified. | Integrates harness tooling into continuous verification, preventing regressions in date ordering or token calculations. Updates living specs in the same change per repository standards. |

---

## Acceptance

- **AT-1 (D1):** `statusline.sh` given a payload with 168,000 input tokens, a 1M `context_window_size`, and cost `$1.50` outputs `ctx 168.0K/200K 84% wrap up  $1.50  tok 168.0K in/0.0K out  Check 1 · selfcheck`, verifying the percentage is computed against the 200K ceiling.
- **AT-2 (D1):** `statusline.sh` given an Antigravity payload with `current_usage.cache_read_input_tokens: 103825` and `input_tokens: 6464` outputs `cache 94%`.
- **AT-3 (D1):** `statusline.sh` given malformed or non-JSON input exits with code 0 and produces empty `stdout`.
- **AT-4 (D2):** `statusline.sh` writes a valid JSON file to `$CTX_DIR/<session_id>.json` matching the schema; no temporary dotfiles remain after execution.
- **AT-5 (D2):** `statusline.sh` given `"session_id": ""` and `"conversation_id": ""` exits 0 and does not write a side-channel file for `"unknown"`.
- **AT-6 (D3):** `session-start.sh` with `$AGENTIC_SEAT=verifier` outputs the full handoff text when file size is below the byte limit.
- **AT-7 (D3):** `session-start.sh` with seat unset outputs a one-line operator pointer and does not output handoff contents.
- **AT-8 (D3):** `session-start.sh` given a handoff exceeding `$MAX_BYTES` outputs a pointer line stating `too large to inject`.
- **AT-9 (D4):** `newest-dated.sh` given `x-2026-09-09.txt`, `x-2026-09-09-3.txt`, and `x-2026-09-10.txt` returns `x-2026-09-10.txt`; given only the first two, returns `x-2026-09-09-3.txt`.
- **AT-10 (D4):** `newest-handoff.sh` resolves handoffs from a linked git worktree that has no local `ops/` directory.
- **AT-11 (D5):** `install.sh` running twice produces exactly one `statusLine` entry and one `SessionStart` hook entry; `--uninstall` removes both without touching unrelated keys.
- **AT-12 (D6):** `bash scripts/ops/tests/harness_test.sh` executes all 14 scenarios and exits with code 0; `ci-gates.yml` executes the test suite.

---

## Concerns

- **Terminal chrome stability:** Statusline commands run synchronously or in quick subshells in the terminal footer. Any unhandled error or stderr output corrupts terminal chrome. All scripts run under `set -uo pipefail` with `2>/dev/null` guards and silent exits on unparseable inputs.
- **Side-channel concurrency:** Multiple parallel sessions or subagents rendering statuslines simultaneously must not corrupt side-channel files. Atomic rename (`mv -f`) ensures single-turn readers never see truncated files.
- **Disk growth in context directory:** In long-running or high-throughput workflows, `$CTX_DIR` accumulates `.json` and `.raw.json` files. The 7-day prune in `session-start.sh` bounds disk usage without interfering with active sessions.

---

## Out of scope

- Automated enforcement or threshold nudges (delegated to #329).
- Permanent spend ledger ingestion and historical aggregation (delegated to #104).
- Session wrap command `/wrap` (delegated to #85).

---

## Operator decisions

None required.

---

## Open questions

none
