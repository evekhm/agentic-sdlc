# Intent: self-enforcing context ceiling and incremental session handoffs

**Issue:** #329 · **Author:** athena (`evekhm-athena-app[bot]`) · **Status:** Draft

## Problem

`AGENTS.md` ("Context ceiling", lines 492–508) defines three strict rules governing context spend:
1. **200K is the working ceiling for any single context** across all harnesses; crossing it reprices requests at a long-context premium and degrades reasoning quality.
2. **Warn before it gets expensive:** when a conversation grows large, the agent must proactively flag the context size and suggest compacting or handing off to a fresh session.
3. **"Silence while the meter runs is a protocol violation, not politeness."**

Today, nothing implements this normative rule. **The agent has no native access to its own context size**, making the ceiling unenforceable from within the session. As a result, the operator has become the sole manual enforcement mechanism across four tedious steps: notice turn cost, ask the agent for a handoff, wait while one is written, and prime a successor session manually. This belongs to the exact defect class catalogued across the repository (#305, #314): a normative claim in an artifact without the code to enforce it.

Three severe failures result from this missing mechanism:

1. **The terminal handoff anti-pattern:**
   Handoffs are currently written at the worst possible moment — at the very end of a session when context is at its absolute maximum. The agent is forced to reconstruct state it held for free hours earlier, burning thousands of expensive tokens at peak context rates.
2. **State loss on crash, termination, or kill:**
   Because handoffs exist only after manual close-out, an abnormal termination (terminal closed, process killed, OOM, power loss) destroys all volatile context, uncommitted findings, and architectural reasoning.
3. **Silent, destructive context compaction across harnesses:**
   Compaction summarizes transcripts away and destroys granular reasoning. Live measurements across both harnesses reveal distinct compaction boundaries:
   - **Claude Code:** `autoCompactWindow` is configured to `180000` (180K) in #330.
   - **Antigravity (agy 1.2.0):** Compaction is unconfigurable and triggers automatically at **~170K tokens** (`preTokens: 170371`, dropping to `21515` post-compaction tokens). Compaction takes 94.7 seconds of wall clock, rewrites the cache, and silently drops context (`cumulativeDroppedTokens: 292539` across multiple unannounced compactions).
   If a session compacts before writing a handoff, the reasoning is permanently lost.

Issue #330 ships the measurement mechanism (`scripts/ops/harness/statusline.sh` writing atomic token, spend, and cache metrics to `$CTX_DIR/<session_id>.json`). Issue #329 provides the behavioral enforcement layer that consumes those metrics.

## Proposed outcome

A dual-harness, self-enforcing context ceiling protocol that warns sessions at defined token thresholds, maintains a continuously updated handoff on disk, and guarantees handoff survival prior to compaction:

1. **Two-Layer Incremental Snapshot Architecture:**
   Because hooks execute bash without invoking the model, handoffs are split cleanly into two layers with distinct producers:
   - **Mechanical snapshot (deterministic bash, zero model tokens):**
     Captures machine state: git branch, HEAD commit SHA, status of uncommitted/unpushed files, open PRs, claimed issue number, context token count, turn spend, and cache hit metrics from `$CTX_DIR/<session_id>.json`. Executed unconditionally by the `Stop` hook at every turn end in both Claude Code and Antigravity. It runs in milliseconds, costs nothing in LLM billing, and ensures machine state on disk is never more than one turn stale — surviving sudden crashes, kills, and unannounced compactions.
   - **Narrative snapshot (model-authored reasoning):**
     Captures cognitive state: task progress, architectural decisions made, rejected hypotheses, and the immediate FIRST ACTION for a successor. Authored by the model when triggered by a threshold nudge or `/wrap` (`--snapshot`).
   - **Line-1 Staleness Tracking (R14):**
     The handoff artifact explicitly indicates the freshness of both layers on line 1 (e.g. `snapshot: mechanical=turn 42, narrative=turn 38 (4 turns old)`). If the mechanical state has updated while narrative reasoning is older, successors are alerted not to assume identical temporal alignment between reasoning and git state.

2. **Automated Threshold Nudges:**
   - **140K `WRAP NOW` Tier:**
     Because Antigravity auto-compacts at ~170K (earlier than Claude's 180K window), the binding threshold across harnesses is derived from the earlier backstop minus the budgeted close-out cost (30K): `170K - 30K = 140K`.
   - **Absolute Token Evaluation:**
     Evaluated strictly against `total_input_tokens` from the side-channel file. Percentage triggers are prohibited because `context_window_size` varies from 200K (Opus/Fable) to 1M (Sonnet).
   - **Harness Injection:**
     - In Claude Code: `UserPromptSubmit` reads the side-channel file (guarded under 30s timeout) and injects a refresh instruction when the session crosses 140K.
     - In Antigravity: `PreInvocation` or dispatch wrapper injects the prompt nudge when crossing threshold.
   - **Nudge Throttling:**
     The nudge fires at the threshold boundary and is throttled to prevent token-wasting repetitive prompt injection.

3. **Pre-Compaction Safety Net and Telemetry (R10–R15):**
   - **R10:** A snapshot must exist on disk before compaction can run, in both harnesses.
   - **R11 & R15 (Claude Code):** Install the `PreCompact` hook (matchers `manual`, `auto`). It fires the mechanical snapshot and records compaction event metadata (trigger, pre/post tokens, duration, age of narrative reasoning) to an audit log.
   - **R12 (Antigravity):** The per-turn `Stop` hook provides the rolling guarantee (at most one turn stale) without requiring an invented or non-existent pre-compaction hook.
   - **R13:** The rolling `Stop` snapshot runs in Claude Code as well, providing crash and abnormal termination coverage that `PreCompact` cannot provide.

4. **Integration with Existing Repositories and Tooling:**
   - **Handoff Location:** Saved to `ops/handoffs/handoff-<seat>-<date>[-n].txt` in the primary checkout, resolved via git common directory (`git rev-parse --git-common-dir`) so sessions in linked worktrees write to the shared root.
   - **Format Alignment:** Shares the handoff format with #85 (`/wrap`). `/wrap` remains the operator-typed terminal close-out; #329 provides the ambient mid-session incremental refresh.
   - **Handoff Consumption:** Consumed seamlessly by `scripts/ops/harness/session-start.sh` (#330) and `ops/waves/seat.sh` (#259).
   - **Living Spec & Documentation:** Upserts `AGENTS.md` (harness-agnostic rules), `CLAUDE.md` and `GEMINI.md` (harness-specific bindings), and `docs/SPEC.md`.

## Affected users and systems

- **Autonomous Personas & Operators:** Interactive sessions and unattended runners (`work.sh`) across Claude Code and Antigravity receive proactive context warnings and maintain continuous recovery state.
- **Harness Hooks:**
  - Claude Code: `UserPromptSubmit`, `Stop`, `PreCompact` (`.claude/settings.json`, `~/.claude/settings.json`).
  - Antigravity: `Stop`, `PreInvocation` (`hooks.json`).
- **Tooling & Scripts:**
  - `scripts/ops/harness/statusline.sh` and `$CTX_DIR/<session_id>.json` (supplied by #330).
  - `scripts/ops/wrap.sh` and `/wrap` command (#85).
  - `scripts/ops/harness/session-start.sh` and `ops/waves/seat.sh`.
- **Repository Standards:** `AGENTS.md` ("Context ceiling", "Session checklist"), `CLAUDE.md`, `GEMINI.md`, and `docs/SPEC.md`.

## Constraints

- **Standard 5-rung lifecycle:** This PR touches `intent/**` only. Spec, plan, and code follow on subsequent rungs.
- **Absolute token thresholds:** Never trigger on `used_percentage`, which measures against varying window sizes (1M vs 200K). All triggers evaluate absolute `total_input_tokens`.
- **Derived from earliest backstop:** Because Antigravity auto-compacts at ~170K, all shared tiers derive from 170K, not Claude's 180K.
- **Strict Hook Performance:** Hooks must be fast and non-blocking:
  - `UserPromptSubmit` has a 30s timeout and must only stat and read the small side-channel JSON file.
  - `Stop` runs at every turn end and must complete within milliseconds. If git state and side-channel metrics have not changed, file writes must be skipped.
- **Model vs Bash Boundary:** Deterministic bash writes machine state; only the model writes narrative reasoning. A hook never invokes an LLM or fabricates reasoning.
- **Worktree Independence:** Handoff file paths must be resolved to the primary repository checkout's `ops/handoffs/` via `git rev-parse --git-common-dir`, preventing file isolation inside ephemeral worktrees.

## Relationships

- **Enforces:** `AGENTS.md` "Context ceiling" / "Warn before it gets expensive", and `CLAUDE.md`'s 200K compaction trigger.
- **Depends on #330:** Consumes the statusline side-channel file (`$CTX_DIR/<session_id>.json`) for live `total_input_tokens` and spend data.
- **Coordinates with #85 (`/wrap`):** `/wrap` is the manual close-out door typed by the operator; #329 is the automated mid-session trigger nobody types. Both share the handoff block format.
- **Feeds #104 (cost ledger) & #259 (waves / seats):** Provides continuous session spend telemetry and seat-based handoff continuity.
- **Defect Class:** Normative claim with no enforcing code (#305, #314).

## Open questions

1. **Antigravity Nudge Delivery Mechanism:**
   Claude Code supports prompt injection via `UserPromptSubmit`. For Antigravity, which mechanism delivers the nudge (e.g. `PreInvocation` injection, system reminder, or statusline display)?
2. **Nudge Frequency and Hysteresis:**
   Once a session crosses the 140K threshold, how often should the nudge fire? If it fires every turn, it adds token noise and disrupts complex multi-step execution. Should it fire once at 140K, or once every N turns until a narrative refresh is recorded?
3. **Narrative vs Mechanical Merging:**
   When the model refreshes narrative reasoning, does it write to a separate companion file (e.g. `handoff-<seat>.narrative.txt`) that the mechanical `Stop` hook merges, or does the session update the full handoff block directly using a slash command / helper script?
4. **Compaction Recovery Protocol:**
   When compaction occurs in either harness (and drops context back down to ~20K), should the session continue using the surviving summary, or should the system actively instruct the session to terminate and yield to a successor primed with the pre-compaction handoff?
