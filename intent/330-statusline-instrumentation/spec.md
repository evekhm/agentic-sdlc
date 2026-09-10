# Spec: Context Statusline and Handoff Instrumentation across Harnesses

**Issue:** #330 · **Status:** Approved (approval = merge of this PR) ·
**Author:** athena (`evekhm-athena-app[bot]`) ·
**Open questions:** none

## What is being built

This specification tracks the context statusline, side-channel token instrumentation, and session handoff priming mechanisms across both Claude Code and Antigravity harnesses.

Historically, harness integration scripts lived in machine-local operator directories (`ops/harness/`). On a fresh clone or alternative development VM, none of the instrumentation exists, CI cannot verify it, and agents cannot see their own context size, making the 200K token working ceiling in `AGENTS.md` unenforceable from the inside (#305, #314).

Earlier work assumed Antigravity required a distinct mechanism. Runtime measurements on VM `evekhm` (consolidated from #336) proved that Antigravity's statusline protocol (`types.StatusLineData`) was designed to mirror Claude Code's schema.

Amendment to founding intent: The constraint in the original intent stating machine-local settings stay out of git is superseded for `<repo>/.claude/settings.json`. Project-scope Claude settings are tracked in git using `${CLAUDE_PROJECT_DIR}` and the graduated location `scripts/ops/harness/`, with zero absolute paths. Antigravity settings remain machine-local because Antigravity has no in-repo project settings file.

This specification formalizes a single codebase under `scripts/ops/harness/` across seventeen binding decisions (D1 to D17):

1. **Unified Statusline Rendering (D1):** `statusline.sh` displays context token percentage against the absolute 200K working ceiling, optional spend, session running tokens (`tok <in> in/<out> out/<tot> tot`), prompt cache health with optional cache writes, model name with optional effort level, and active seat.
2. **Side-Channel State Contract (D2):** `statusline.sh` atomically writes `$CTX_DIR/<session_id>.json` on every render, providing the real-time token count and cost bridge required for automated ceiling enforcement (#329) and the spend ledger (#104).
3. **Session Priming Contract (D3):** `session-start.sh` primes Claude sessions with the newest handoff for their seat, gated on explicit seat identity to prevent state leakage, with oversize protection and 7-day retention housekeeping. Antigravity sessions are primed at dispatch.
4. **Ordering and Worktree Resolution (D4):** `newest-dated.sh` corrects date and numeric suffix ordering (`-` vs `.` sorting bug). `newest-handoff.sh` derives the primary checkout via git common directory so linked worktrees access machine-shared `ops/handoffs/`.
5. **Idempotent Dual-Harness Installer (D5):** `scripts/ops/harness/install.sh` detects active harnesses (`~/.gemini/antigravity-cli` and `~/.claude`), configures settings, and provides hermetic `--check` validation.
6. **Automated CI Test Suite and Scope Boundaries (D6):** `scripts/ops/tests/harness_test.sh` exercises all harness contracts in CI (`ci-gates.yml`). Updates living documentation in `AGENTS.md`, `GEMINI.md`, `CLAUDE.md`, and `docs/SPEC.md`.
7. **Project-Scope Settings Tracking (D7):** `<repo>/.claude/settings.json` is tracked at project scope, using `${CLAUDE_PROJECT_DIR}` without absolute paths.
8. **Wrap Tag Thresholds and Compaction Derivation (D8):** Tags trigger at 60% (`wrap soon`), 70% (`WRAP NOW`), and 90% (`COMPACTING`) of the 200K ceiling, derived from the 170K Antigravity compaction point minus a 30K close-out budget.
9. **Absent Cost Omission and Zero-Cost Display (D9):** When `.cost` is absent, the `$` segment is omitted. Fabricated `$0.00` output is forbidden. Present zero cost prints `$0.00`.
10. **Session Token Accumulator Contract (D10):** Displays running sums `tok <in> in/<out> out/<tot> tot`. The script maintains cumulative counters in the side channel.
11. **Session Cache Write Reporting (D11):** Appends `cw <n>` to the cache segment when supplied by the harness (Claude Code only).
12. **Reasoning Effort Segment (D12):** Model segment includes optional `[<effort>]` when supplied by the harness (`effort.level` in Claude, `model.effort` in Antigravity).
13. **Pre-Compaction State Fields in Side-Channel Schema (D13):** Side-channel schema reserves `pre_compact_mechanical_ts` and `pre_compact_narrative_ts` for #329.
14. **Harness Priming Paths (D14):** Claude Code uses `SessionStart` hook; Antigravity uses dispatch injection in `work.sh` and `seat.sh`.
15. **Compaction Configuration and Backstop (D15):** Claude Code tracks `autoCompactWindow: 180000`; Antigravity relies on server-side compaction at ~170K.
16. **Antigravity Configuration Placement (D16):** Antigravity configures user settings in `~/.gemini/antigravity-cli/settings.json`; `install.sh --check` verifies drift between harnesses.
17. **Live Fixture Suite and Deterministic Contract Tests (D17):** Test suite validates live captured payloads across Claude Code and Antigravity against expected outputs byte-for-byte.

```text
scripts/ops/harness/statusline.sh      # dual-harness statusline command and side-channel writer
scripts/ops/harness/session-start.sh   # session start hook and handoff priming
scripts/ops/harness/newest-dated.sh    # date + suffix ordering resolver
scripts/ops/harness/newest-handoff.sh  # worktree-aware handoff path resolver
scripts/ops/harness/install.sh         # idempotent harness installer and drift check
scripts/ops/tests/harness_test.sh      # hermetic CI test suite
.claude/settings.json                  # tracked project settings for Claude Code
.github/workflows/ci-gates.yml         # wires harness_test.sh into CI
AGENTS.md                              # protocol update under "Context ceiling"
GEMINI.md                              # Antigravity statusline binding
CLAUDE.md                              # Claude Code statusline binding
docs/SPEC.md                           # living spec update under harness.statusline
intent/330-statusline-instrumentation/spec.md # this specification
```

---

## Decisions

| ID | Decision | Rationale |
|---|---|---|
| D1 | **Unified Statusline Rendering and Display Contract.** `scripts/ops/harness/statusline.sh` accepts JSON on `stdin` and outputs a single line to `stdout`: `ctx <used>K/<ceiling>K <pct>%[ <TAG>]  [$<cost>]  tok <in> in/<out> out/<tot> tot  [cache <hit>%[ cold][ <ttl>][ cw <n>]]  <model>[ [<effort>]][ · <seat>]`. (1) `<used>` is context input tokens scaled as `X.XK`. (2) `<pct>%` is computed against the absolute 200K ceiling (`used * 100 / 200000`). (3) `<TAG>` follows D8: `wrap soon` at 60%, `WRAP NOW` at 70%, `COMPACTING` at 90%. (4) `[$<cost>]` formats `.cost.total_cost_usd // .cost.total_usd` as `$%.2f`; when cost is absent, the segment is omitted per D9; a reported cost of zero prints `$0.00`. (5) `tok <in> in/<out> out/<tot> tot` displays session running sums per D10, with `<tot> = <in> + <out>`, formatted via `fmt_tok`. (6) `cache` displays hit percentage from `.prompt_cache.hit_ratio` (Claude) or derived from `current_usage.cache_read_input_tokens * 100 / turn_input` (Antigravity), with optional `cw <n>` per D11. (7) `<model>[ [<effort>]][ · <seat>]` renders model name, optional effort level per D12, and seat name when set. (8) Unparseable input exits 0 with no output to avoid breaking terminal chrome. | Unifies terminal feedback across Claude Code and Antigravity. Enforces the economic 200K threshold where long-context repricing occurs, independent of underlying model window size limits. |
| D2 | **Side-Channel State Contract.** When `session_id` or `conversation_id` is non-empty, `statusline.sh` atomically writes `$CTX_DIR/<session_id>.json` via temporary dotfile and `mv -f`. The JSON schema contains: `session_id` (string), `used_tokens` (int), `output_tokens` (int), `total_tokens` (int), `accum_input_tokens` (int), `accum_output_tokens` (int), `accum_total_tokens` (int), `ceiling` (int, 200000), `pct` (int), `window_size` (int), `cost_usd` (float or null), `duration_ms` (int), `seat` (string), `cache` (`hit_pct`, `warm`, `ttl`, `write_tokens`, `requests`, `misses`), `pre_compact_mechanical_ts` (int or null), `pre_compact_narrative_ts` (int or null), and `ts` (unix timestamp). The raw incoming payload is archived to `$CTX_DIR/<session_id>.raw.json`. Empty session IDs resolve to `"unknown"` and do not emit side-channel files. `$CTX_DIR` defaults to `$AGENTIC_CTX_DIR`, `$CLAUDE_CTX_DIR`, `$AGY_CTX_DIR`, or home directory defaults (`~/.claude/context` or `~/.gemini/antigravity-cli/context`). | No harness hook receives a token count in its event payload. The side-channel file provides the sole real-time bridge for hooks, watchers, and #329 without requiring expensive transcript parsing. Atomic rename prevents concurrent readers from observing truncated JSON. |
| D3 | **Session Priming Contract.** `scripts/ops/harness/session-start.sh` primes Claude sessions with inherited state. (1) Drains `stdin` payload if present. (2) Resolves the newest handoff for `$SEAT` (`$AGENTIC_SEAT` / `$CLAUDE_SEAT`) via `newest-handoff.sh`. (3) If `$SEAT` is set and file size is within `$MAX_BYTES` (default 60,000 bytes), injects the full handoff content to `stdout`. (4) If `$SEAT` is set and file size exceeds `$MAX_BYTES`, emits a pointer line only (`too large to inject`). (5) If `$SEAT` is unset, emits an operator pointer line only, preventing one-off sessions from inheriting unrelated seat state. (6) On each invocation, prunes side-channel files older than 7 days from `$CTX_DIR` as built in the POC; retention policy evolution is delegated to #394. | Eliminates manual copying of handoffs when starting successor sessions. Guards against context window flooding from oversized handoffs. Gating on seat name prevents leaking specialized seat work into ad-hoc operator sessions. |
| D4 | **Ordering and Worktree Resolution.** (1) `scripts/ops/harness/newest-dated.sh <prefix>` lists matching `<prefix>-*.txt` files and sorts by parsed date (`YYYY-MM-DD`) and numeric suffix (`-n`). Unsuffixed filenames (`-YYYY-MM-DD.txt`) are normalized as suffix index 1 (`-001`), ensuring that `-3` sorts after the unsuffixed file. (2) `scripts/ops/harness/newest-handoff.sh [<seat>]` resolves the handoff directory from `AGENTIC_HANDOFF_DIR`, `CLAUDE_HANDOFF_DIR`, or the primary checkout's `ops/handoffs/`, derived via `git rev-parse --git-common-dir`. If the seat handoff does not exist, falls back to `handoff-plan-*.txt`. Exits 1 if no handoff exists. | Standard lexical sorting fails because `-` (0x2D) sorts before `.` (0x2E), causing `foo-2026-09-09.txt` to sort after `foo-2026-09-09-3.txt`. Linked worktrees have no local `ops/` directory; resolving git's common directory guarantees all sessions find shared operator handoffs regardless of worktree location. |
| D5 | **Idempotent Dual-Harness Installer.** `scripts/ops/harness/install.sh` manages harness settings: (1) Default or `--all` auto-detects installed harnesses based on directory presence (`~/.gemini/antigravity-cli` and `~/.claude`). Flags `--antigravity` and `--claude` restrict targets. (2) Configures `.statusLine = {type: "command", command: $STATUSLINE, padding: 0}` in user settings. (3) Configures `.hooks.SessionStart` in repository project settings (`<repo>/.claude/settings.json`) with a 10s timeout, deduplicating existing entries. (4) `--uninstall` removes statusline and hook configurations, preserving other keys. (5) `--show` prints configured keys. (6) `--check` verifies that tracked settings reference scripts that exist, executes contract scenarios, and runs the drift check per D16, exiting 0 on success. | Keeps user settings machine-local while making VM setup a single deterministic command. Deduplication prevents repeated installs from bloating hook lists. `--check` gives operators and CI instant verification of harness wiring. |
| D6 | **Automated CI Testing and Scope Boundaries.** (1) `scripts/ops/tests/harness_test.sh` ports `--check` into a standalone, hermetic test suite executing against a temporary tree without depending on user settings or network calls. (2) Wired into `.github/workflows/ci-gates.yml`. (3) Updates `AGENTS.md` ("Context ceiling"), `GEMINI.md` ("Statusline & context side channel"), `CLAUDE.md` ("Harness configuration"), and `docs/SPEC.md` (`harness.statusline`). Files `personas/**`, `scripts/ci/merge_gate.sh`, and `scripts/ci/review_recorder.py` are unchanged. | Integrates harness tooling into continuous verification, preventing regressions in date ordering or token calculations. Updates living specs in the same change per repository standards. |
| D7 | **Project-Scope Settings Tracking.** `<repo>/.claude/settings.json` is tracked at project scope in git, superseding the intent's machine-local constraint for that file. Script references inside it use `${CLAUDE_PROJECT_DIR}` and resolve to `scripts/ops/harness/`. Zero absolute paths are committed. Antigravity settings remain machine-local per D16. | Project settings ensure uniform hook and statusline wiring across checkouts on Claude Code without manual per-developer configuration. Using `${CLAUDE_PROJECT_DIR}` keeps configuration portable. |
| D8 | **Wrap Tag Thresholds and Compaction Derivation.** Tags trigger at 60% (`wrap soon`), 70% (`WRAP NOW`), and 90% (`COMPACTING`) of the 200K ceiling (120K, 140K, 180K tokens). Derivation: Antigravity 1.2.0 auto-compacts at ~170K unconfigurably (measured from task log: `preTokens 170371, postTokens 21515`). Subtracting a 30K close-out budget establishes the 140K (70%) wrap point. Claude Code tracks `autoCompactWindow: 180000` as a backstop. Both harnesses share identical tag thresholds because the economic 200K pricing boundary in AGENTS.md applies equally to both. | The wrap tags warn against the 200K token repricing boundary where Gemini and Claude rates increase. Aligning the trigger point with the auto-compaction budget prevents unexpected compaction during critical task phases. |
| D9 | **Absent Cost Omission and Zero-Cost Display.** When incoming payload carries no `.cost`, the `$` segment is omitted entirely. Outputting `$0.00` for an absent cost is prohibited as a fabricated value. When a cost object is present with a value of zero, `$0.00` is printed. In the side-channel schema, `cost_usd` is written as JSON `null` when cost is absent. | Internal-quota accounts report no cost object. Emitting `$0.00` when no cost was reported invents billing data. Preserving `$0.00` only for explicit zero costs distinguishes free runs from unmetered enterprise quota. |
| D10 | **Session Token Accumulator Contract.** The token segment displays session running sums: `tok <in> in/<out> out/<tot> tot` with `<tot> = <in> + <out>`. On Claude Code, input and output tokens are per-call snapshots; the script maintains cumulative input and output counters in the side-channel file, advanced once per completed call keyed on `prompt_cache.requests`. On Antigravity 1.2.0 (`statusline_data_builder.go:84-116`), `total_output_tokens` is already a session running sum, while `total_input_tokens` is the active context snapshot; Antigravity lacks a request counter in `types.StatusLineData`, so the accumulator uses a render counter fallback with token delta gating to prevent duplicate accumulation during rapid store updates. | Running token totals give operators a clear cumulative view of conversation volume across turns. Preserves consistency across harnesses despite differing payload counter semantics. |
| D11 | **Session Cache Write Reporting.** Claude Code appends `cw <n>` to the cache segment representing cumulative session cache write tokens (`prompt_cache.cache_write_tokens`, running sum). On Antigravity 1.2.0 (`statusline.go:170`, `statusline_data_builder.go:126`), only `current_usage.cache_read_input_tokens` is populated; cache creation and write tokens are not emitted. Therefore `cw` renders only when supplied by the harness and remains Claude-only. | Cache creation tokens represent significant session spend on Claude Code. Omitting `cw` on Antigravity avoids displaying empty or fabricated cache write figures where the runtime does not report them. |
| D12 | **Reasoning Effort Segment.** The model segment accepts an optional reasoning effort level badge: `<model>[ [<effort>]][ · <seat>]`. On Claude Code, populated from `effort.level`. On Antigravity 1.2.0 (`types/statusline.go:135`, `statusline_data_builder.go:61-63`), populated from `model.effort` when the base model provides multiple effort variants. The bracket is omitted when the harness payload does not carry an effort level. | Communicates active thinking effort without parsing model names. Honors runtime schema availability across both harnesses. |
| D13 | **Pre-Compaction State Fields in Side-Channel Schema.** To prepare for pre-compaction snapshots in #329 (R10 to R15), the side-channel JSON schema reserves two timestamp fields: `pre_compact_mechanical_ts` (integer or null) and `pre_compact_narrative_ts` (integer or null). Initial statusline emissions set these fields to `null`. Writing to these fields is delegated to #329. | Establishes the required schema surface area for pre-compaction snapshots without coupling this specification to snapshot generation logic. |
| D14 | **Harness Priming Paths.** Claude Code uses the `SessionStart` hook to inject the newest handoff into session context. Antigravity 1.2.0 exposes exactly five hook types (PreToolUse, PostToolUse, PreInvocation, PostInvocation, Stop) and provides no `SessionStart` hook. Antigravity session priming is executed at dispatch time by `work.sh` and `seat.sh`. Discovery verified that Antigravity's `PreInvocation` hook can inject text into turn context by outputting `{"inject_steps":[{"user_message":"..."}]}` on stdout (`third_party/jetski/cli/agentbox/qa_tests/cli/internal/hooks_preinvocation_firing/hooks_preinvocation_firing.md:50`). | Matches documented hook capabilities of each harness. Avoids relying on nonexistent hooks in Antigravity while verifying future extension possibilities. |
| D15 | **Compaction Configuration and Backstop.** Claude Code configures `autoCompactWindow: 180000` in tracked `<repo>/.claude/settings.json`. In Antigravity 1.2.0, context compaction is performed server-side at ~170K, is unconfigurable in the CLI, and provides no pre-compaction hook. | Documents harness compaction behavior and establishes the Claude Code backstop before the 200K economic boundary. |
| D16 | **Antigravity Configuration Placement.** In Antigravity 1.2.0, statusline is configured in user-scope `~/.gemini/antigravity-cli/settings.json` (`.statusLine = {type: "command", command: ...}`) and hooks are configured in user-scope `~/.gemini/config/hooks.json`. Antigravity has no project-scope settings file within git checkouts. `scripts/ops/harness/install.sh` writes user settings from a tracked template. A drift check in `install.sh --check` fails if the two harness configurations point to different statusline scripts. | Accommodates Antigravity's lack of in-repo configuration while ensuring automated consistency checks prevent divergence between harnesses. |
| D17 | **Live Fixture Suite and Deterministic Contract Tests.** Acceptance tests validate statusline rendering against recorded live payloads with byte-for-byte expected outputs. Fixtures comprise: (1) Claude 200K-window model with cost and effort (`runs/2026-09-10_330-agy-fixtures/` reference), (2) Claude 1M-window model with zero cost, (3) Claude payload without cost, (4) Antigravity internal quota without cost (`runs/2026-09-10_330-agy-fixtures/agy-internal-quota-no-cost.json`), and (5) Antigravity with cost (`runs/2026-09-10_330-agy-fixtures/agy-with-cost.json`). | Ensures regression-free rendering across diverse payloads, cost states, and model configurations on both harnesses. |

---

## Antigravity Discovery Answers

Every discovery question is answered below with evidence from source inspection or live captured payloads on VM `evekhm`:

- **Q1 Payload Schema:** The fields of `types.StatusLineData` in Antigravity 1.2.0 are defined in `third_party/jetski/cli/types/statusline.go:25-97`. Compatibility fields: `cwd` (string), `session_id` (string), `conversation_id` (string), `conversation_title` (string), `transcript_path` (string), `model` (`id`, `display_name`, `effort`), `workspace` (`current_dir`, `project_dir`), `version` (string), `context_window` (`total_input_tokens`, `total_output_tokens`, `context_window_size`, `used_percentage`, `remaining_percentage`, `current_usage`), `exceeds_200k_tokens` (bool), and `agent` (`name`). Extension fields: `product`, `quota`, `agent_state`, `vcs`, `cycle_mode`, `sandbox`, `subagents`, `artifact_count`, `plan_tier`, `email`, `pending_input_count`, `tool_confirmation_pending`, `task_count`, `terminal_width`, `battle`, `vim`, and `cost` (`total_usd`, `subagent_usd`, `estimated`). Live fixtures captured to `runs/2026-09-10_330-agy-fixtures/`: `agy-internal-quota-no-cost.json` (internal quota account `admin@evekhm.altostrat.com`, `.cost` absent) and `agy-with-cost.json` (cost present).
- **Q2 Running Sum vs Snapshot:** In Antigravity 1.2.0 (`third_party/jetski/cli/store/statusline_data_builder.go:84-116`), `total_output_tokens` is a session running sum across all conversation steps (`totalOutputTokens += int(u.GetOutputTokens())`). In contrast, `total_input_tokens` is the active context size snapshot (`contextWindow.TotalInputTokens = used`). Two consecutive live renders captured in `runs/2026-09-10_330-agy-fixtures/` (`consecutive-render-1.json` and `consecutive-render-2.json`) confirm this: `total_input_tokens` shifted from 59,793 to 107,087 while `total_output_tokens` accumulated from 5,163 to 45,175.
- **Q3 Request Counter:** Antigravity 1.2.0 emits no request counter field in `types.StatusLineData` (no equivalent to Claude's `prompt_cache.requests`). The accumulator uses a render-counter fallback in the side-channel file, with token delta gating to prevent duplicate counts during rapid non-turn store updates.
- **Q4 Cache Fields:** Antigravity 1.2.0 emits `context_window.current_usage.cache_read_input_tokens` (`types/statusline.go:170`, `statusline_data_builder.go:126`). `cache_creation_input_tokens` is unpopulated (zero), and no cache write tokens field exists. Therefore `cw` cache write reporting remains Claude-only.
- **Q5 Reasoning Effort:** Antigravity 1.2.0 emits `model.effort` (`types/statusline.go:135`, `statusline_data_builder.go:61-63`) populated from `ModelEffortDisplay` when the base model has multiple effort variants available (for example, "high"). It joins the model segment as `[<effort>]`.
- **Q6 Configuration Placement:** Antigravity reads statusline configuration from user-scope `~/.gemini/antigravity-cli/settings.json` (`.statusLine = {type: "command", command: ...}`) and hooks from user-scope `~/.gemini/config/hooks.json` (`third_party/jetski/cli/backend/server.go:435-443`). Antigravity has no project-scope settings file inside repository checkouts (`~/.gemini/config/projects/<id>.json` is stored centrally under the user home directory).
- **Q7 PreInvocation Capabilities:** An Antigravity `PreInvocation` hook can add text to the turn context by emitting `{"inject_steps":[{"user_message":"..."}]}` to `stdout`. Evidence: `third_party/jetski/cli/agentbox/qa_tests/cli/internal/hooks_preinvocation_firing/hooks_preinvocation_firing.md:50`.
- **Q8 Session ID Stability:** Populated in both `session_id` and `conversation_id` from `s.Conversation().ID` (`types/statusline.go:30-33`, `statusline_data_builder.go:29-30`). The value is an empty string before conversation start (`types/conversation.go:143`), resolving to `"unknown"` in `statusline.sh` which skips side-channel output. Once initialized, the ID remains stable across all turns of the conversation.
- **Q9 Render Cadence and Timeout:** Statusline execution is triggered asynchronously on store updates, debounced to a minimum 300ms interval (`statusLineDebounce = 300 * time.Millisecond`, `store/statusline_runner.go:20,73`). Hard process execution timeout is 5 seconds (`statusLineTimeout = 5 * time.Second`, `statusline_runner.go:22,140`). The runner auto-disables after 30 consecutive failures (`statusLineMaxConsecutiveFailures = 30`, `statusline_runner.go:25`). The single jq invocation completes in under 20ms, well inside the 5s ceiling.
- **Q10 Compaction Characteristics:** Compaction in Antigravity occurs server-side at ~170K tokens (`preTokens 170371, postTokens 21515`) and is not configurable in the client. Antigravity exposes five hook types (PreToolUse, PostToolUse, PreInvocation, PostInvocation, Stop) with no PreCompact hook. The 60/70/90% threshold tiers serve as economic boundaries against the 200K ceiling.

---

## Acceptance

- **AT-1 (D1, D8, D10):** `statusline.sh` given a Claude payload with 105.3K used tokens, $81.40 cost, 88% cache hit with 5m ttl and 3.5M cache write tokens, effort `high`, and seat `advisor` outputs:
  `ctx 105.3K/200K 52%  $81.40  tok 105.3K in/4 out/105.3K tot  cache 88% 5m cw 3.5M  Fable 5.1 [high] · advisor`
- **AT-2 (D1, D8, D9):** `statusline.sh` given an Antigravity payload with no `.cost` (`runs/2026-09-10_330-agy-fixtures/agy-internal-quota-no-cost.json`) omits the `$` segment and outputs tokens:
  `ctx 107.0K/200K 53%  tok 107.0K in/45.1K out/152.2K tot  cache 94%  Gemini 3.8 Flash [high]`
- **AT-3 (D1, D9):** `statusline.sh` given an explicit cost of zero prints `$0.00`:
  `ctx 12.0K/200K 6%  $0.00  tok 12.0K in/10 out/12.0K tot  cache 0% cold cw 11.0K  Opus 5`
- **AT-4 (D1):** `statusline.sh` given malformed or non-JSON input exits with code 0 and produces empty `stdout`.
- **AT-5 (D2):** `statusline.sh` writes a valid JSON file to `$CTX_DIR/<session_id>.json` matching schema with `accum_total_tokens`, `cost_usd`, and reserved snapshot fields; no temporary dotfiles remain.
- **AT-6 (D2):** `statusline.sh` given `"session_id": ""` and `"conversation_id": ""` exits 0 and does not write a side-channel file for `"unknown"`.
- **AT-7 (D3):** `session-start.sh` with `$AGENTIC_SEAT=verifier` outputs full handoff text when file size is below byte limit.
- **AT-8 (D3):** `session-start.sh` with seat unset outputs a one-line operator pointer and does not output handoff contents.
- **AT-9 (D3):** `session-start.sh` given a handoff exceeding `$MAX_BYTES` outputs a pointer line stating `too large to inject`.
- **AT-10 (D4):** `newest-dated.sh` given `x-2026-09-09.txt`, `x-2026-09-09-3.txt`, and `x-2026-09-10.txt` returns `x-2026-09-10.txt`; given only the first two, returns `x-2026-09-09-3.txt`.
- **AT-11 (D4):** `newest-handoff.sh` resolves handoffs from a linked git worktree that has no local `ops/` directory.
- **AT-12 (D5, D7):** `install.sh` running twice produces exactly one `statusLine` entry and one `SessionStart` hook entry; project settings `<repo>/.claude/settings.json` use `${CLAUDE_PROJECT_DIR}`.
- **AT-13 (D5, D16):** `install.sh --check` verifies that tracked settings reference existing files and that both harnesses resolve to the same `statusline.sh`.
- **AT-14 (D6, D17):** `bash scripts/ops/tests/harness_test.sh` executes all test scenarios and fixture comparisons, exiting with code 0; `ci-gates.yml` executes the test suite.
- **AT-15 (D8):** `statusline.sh` triggers yellow `wrap soon` tag at >= 60% context threshold.
- **AT-16 (D8):** `statusline.sh` triggers red `WRAP NOW` tag at >= 70% context threshold.
- **AT-17 (D8):** `statusline.sh` triggers `COMPACTING` tag at >= 90% context threshold.
- **AT-18 (D10):** `statusline.sh` Claude Code accumulator advances on `requests` change and ignores redraws.
- **AT-19 (D10):** `statusline.sh` Antigravity accumulator tracks running output tokens.
- **AT-20 (D17):** `statusline.sh` matches exact byte contract for Claude no-cost fixture (`claude-no-cost-wrap.json`).
- **AT-21 (D17):** `statusline.sh` matches exact byte contract for Antigravity with-cost fixture (`agy-with-cost.json`).

---

## Concerns

- **Terminal chrome stability:** Statusline commands run synchronously or in quick subshells in the terminal footer. Any unhandled error or stderr output corrupts terminal chrome. All scripts run under `set -uo pipefail` with `2>/dev/null` guards and silent exits on unparseable inputs.
- **Side-channel concurrency:** Multiple parallel sessions or subagents rendering statuslines simultaneously must not corrupt side-channel files. Atomic rename (`mv -f`) ensures single-turn readers never see truncated files.
- **Disk growth in context directory:** In long-running workflows, `$CTX_DIR` accumulates `.json` and `.raw.json` files. The 7-day prune in `session-start.sh` bounds disk usage without interfering with active sessions.
- **Double-counting in accumulator fallback:** On Antigravity where no per-request counter exists, rapid UI redraws could advance counters if delta gating is omitted. The accumulator must advance only when input or output token counts change.

---

## Implementation Reference (Excerpt)

The core payload extraction in `scripts/ops/harness/statusline.sh` executes as a single jq pass:

```bash
# Normalized extraction across both Antigravity and Claude schemas
IFS=$'\t' read -r sid model used tot_out window cost dur hit warm ttl cwrite creq cmiss effort < <(
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
      , (if .cost != null then (.cost.total_cost_usd // .cost.total_usd // 0) else "null" end)
      , (.cost.total_duration_ms // 0)
      , (if $pc.hit_ratio != null then ($pc.hit_ratio * 100 | floor)
         elif ($cu.cache_read_input_tokens != null and $turn_in > 0)
         then (($cu.cache_read_input_tokens * 100) / $turn_in | floor)
         else -1 end)
      , (if $pc.warm != null then ($pc.warm | tostring)
         elif $cu.cache_read_input_tokens != null then
           (if $cu.cache_read_input_tokens > 0 then "true" else "false" end)
         else "-" end)
      , ($pc.ttl // "-")
      , ($pc.cache_write_tokens // 0)
      , ($pc.requests // 0)
      , ($pc.misses // 0)
      , (.effort.level // .model.effort // "")
      ] | @tsv' 2>/dev/null
)
```

---

## Out of scope

- Automated enforcement or threshold nudges (delegated to #329).
- Permanent spend ledger ingestion and historical aggregation (delegated to #104).
- Session wrap command `/wrap` (delegated to #85).
- Side-channel retention and rotation policies beyond the 7-day POC cleanup (delegated to #394).

---

## Operator decisions

- Operator decision (2026-09-10): when payload carries no `.cost`, line switches to tokens only (no `$` segment).
- Operator decision (2026-09-10): one token segment on both harnesses showing session running sums `tok <in> in/<out> out/<tot> tot`.
- Operator decision (2026-09-10): Claude Code additionally appends `cw <n>` to cache segment when supplied.

---

## Open questions

none
