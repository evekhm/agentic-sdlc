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

## Implementation Reference (Verified Prototype Scripts)

### `scripts/ops/harness/statusline.sh`

```bash
#!/usr/bin/env bash
# Copyright 2026 The Agentic SDLC Authors.
# SPDX-License-Identifier: Apache-2.0
#
# statusline.sh — Statusline command for Antigravity and Claude Code harnesses.
# Two jobs:
#   1. Display context size against the 200K working ceiling (AGENTS.md
#      "Context ceiling") and session spend, so the operator never has to
#      ask an agent how expensive it has become.
#   2. Write the same numbers to a side-channel file, because no hook event
#      receives a token count. Hooks and watchers read the file; this script is
#      the only place the harness hands the number over.
#
# stdin: StatusLine JSON payload (from Claude Code or Antigravity/Jetski).
# stdout: one line, rendered in the terminal chrome.
#
# Env:
#   AGENTIC_CONTEXT_CEILING / CLAUDE_CONTEXT_CEILING  working ceiling (default 200000)
#   AGENTIC_CTX_DIR / CLAUDE_CTX_DIR / AGY_CTX_DIR    side-channel directory
#   AGENTIC_SEAT / CLAUDE_SEAT                        seat name, shown in the line
set -uo pipefail

CEILING="${AGENTIC_CONTEXT_CEILING:-${CLAUDE_CONTEXT_CEILING:-200000}}"

# Default context dir: check AGENTIC_CTX_DIR, CLAUDE_CTX_DIR, AGY_CTX_DIR,
# or default based on home directory structure.
if [[ -n "${AGENTIC_CTX_DIR:-}" ]]; then
  CTX_DIR="$AGENTIC_CTX_DIR"
elif [[ -n "${CLAUDE_CTX_DIR:-}" ]]; then
  CTX_DIR="$CLAUDE_CTX_DIR"
elif [[ -n "${AGY_CTX_DIR:-}" ]]; then
  CTX_DIR="$AGY_CTX_DIR"
elif [[ -d "$HOME/.gemini/antigravity-cli" ]]; then
  CTX_DIR="$HOME/.gemini/antigravity-cli/context"
elif [[ -d "$HOME/.gemini" ]]; then
  CTX_DIR="$HOME/.gemini/context"
else
  CTX_DIR="$HOME/.claude/context"
fi

SEAT="${AGENTIC_SEAT:-${CLAUDE_SEAT:-${AGY_SEAT:-}}}"

payload="$(cat)"

# One jq pass; the rest is pure bash so a render costs a single subprocess.
# Normalized extraction across both Antigravity and Claude schemas:
# - session_id: .session_id // .conversation_id (non-empty filter prevents IFS whitespace collapse)
# - model: .model.display_name // .model.id
# - used: total_input_tokens with current_usage fallback (tolerates null usage after compaction)
# - tot_out: total_output_tokens (cumulative output generated in session)
# - cost: .cost.total_cost_usd (Claude) // .cost.total_usd (Antigravity) // 0
# - dur: .cost.total_duration_ms // 0
# - cache: .prompt_cache fields (Claude), or current_usage.cache_read_input_tokens (Antigravity)
IFS=$'\t' read -r sid model used tot_out window cost dur hit warm ttl cwrite creq cmiss < <(
  printf '%s' "$payload" | jq -r '
    (.context_window // {}) as $cw
    | ($cw.current_usage // {}) as $cu
    | (.prompt_cache // {}) as $pc
    | ((($cu.input_tokens // 0) + ($cu.cache_read_input_tokens // 0) + ($cu.cache_creation_input_tokens // 0))) as $turn_in
    | [ ((.session_id | select(. != null and . != "")) // (.conversation_id | select(. != null and . != "")) // "unknown")
      , ((.model.display_name | select(. != null and . != "")) // (.model.id | select(. != null and . != "")) // "model")
      , ( $cw.total_input_tokens // $turn_in )
      , ($cw.total_output_tokens // 0)
      , ($cw.context_window_size // 0)
      , (.cost.total_cost_usd // .cost.total_usd // 0)
      , (.cost.total_duration_ms // 0)
      # Absent reads as -1 / "-", never "". Tab is an IFS whitespace char.
      # Support both Claude .prompt_cache and Antigravity current_usage.cache_read_input_tokens
      , (if $pc.hit_ratio != null then ($pc.hit_ratio * 100 | floor)
         elif ($cu.cache_read_input_tokens != null and $turn_in > 0)
         then (($cu.cache_read_input_tokens * 100) / $turn_in | floor)
         else -1 end)
      , (if $pc.warm != null then ($pc.warm | tostring)
         elif $cu.cache_read_input_tokens != null then
           (if $cu.cache_read_input_tokens > 0 then "true" else "false" end)
         else "-" end)
      , ($pc.ttl // "-")
      , ($pc.cache_write_tokens // $cu.cache_creation_input_tokens // 0)
      , ($pc.requests // 0)
      , ($pc.misses // 0)
      ] | @tsv' 2>/dev/null
)
[[ -n "${sid:-}" ]] || exit 0   # unparseable payload: print nothing, never break chrome
[[ "$warm" == "-" ]] && warm=""
[[ "$ttl"  == "-" ]] && ttl=""

pct=$(( CEILING > 0 ? used * 100 / CEILING : 0 ))
tot_tokens=$(( used + tot_out ))

# Side channel for hooks/watchers. Atomic so reader never sees partial file.
if [[ "$sid" != "unknown" ]]; then
  mkdir -p "$CTX_DIR" 2>/dev/null
  tmp="$CTX_DIR/.$sid.$$"
  printf '{"session_id":"%s","used_tokens":%s,"output_tokens":%s,"total_tokens":%s,"ceiling":%s,"pct":%s,"window_size":%s,"cost_usd":%s,"duration_ms":%s,"seat":"%s","cache":{"hit_pct":%s,"warm":"%s","ttl":"%s","write_tokens":%s,"requests":%s,"misses":%s},"ts":%s}\n' \
    "$sid" "$used" "$tot_out" "$tot_tokens" "$CEILING" "$pct" "$window" "$cost" "$dur" "$SEAT" \
    "$hit" "$warm" "$ttl" "$cwrite" "$creq" "$cmiss" "$(printf '%(%s)T' -1)" \
    > "$tmp" 2>/dev/null && mv -f "$tmp" "$CTX_DIR/$sid.json" 2>/dev/null
  printf '%s' "$payload" > "$CTX_DIR/$sid.raw.json" 2>/dev/null
fi

D=$'\033[0m'; DIM=$'\033[2m'
if   (( pct >= 100 )); then C=$'\033[1;31m'; TAG=" HANDOFF"       # past ceiling
elif (( pct >= 75  )); then C=$'\033[33m';   TAG=" wrap up"
else                        C=$'\033[32m';   TAG=""
fi

CACHE=""
if (( hit >= 0 )); then
  if   [[ "$warm" == false ]]; then CC=$'\033[33m'; SUFFIX=" cold"
  elif (( hit < 80 ));         then CC=$'\033[33m'; SUFFIX=""
  else                              CC="$DIM";      SUFFIX=""
  fi
  CACHE="$(printf '  %scache %s%%%s%s%s' "$CC" "$hit" "$SUFFIX" "${ttl:+ $ttl}" "$D")"
fi

fmt_tok() {
  local n="${1:-0}"
  if (( n >= 1000000 )); then
    printf '%d.%dM' "$(( n / 1000000 ))" "$(( n % 1000000 / 100000 ))"
  else
    printf '%d.%dK' "$(( n / 1000 ))" "$(( n % 1000 / 100 ))"
  fi
}

TOK="$(printf '%stok %s in/%s out%s' "$DIM" "$(fmt_tok "$used")" "$(fmt_tok "$tot_out")" "$D")"

printf '%sctx %s.%sK/%sK %s%%%s%s  %s$%.2f%s  %s%s  %s%s%s%s\n' \
  "$C" "$(( used / 1000 ))" "$(( used % 1000 / 100 ))" "$(( CEILING / 1000 ))" "$pct" "$TAG" "$D" \
  "$DIM" "$cost" "$D" \
  "$TOK" "$CACHE" \
  "$DIM" "$model" "${SEAT:+ · $SEAT}" "$D"
```

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
