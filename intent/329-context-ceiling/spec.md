# Spec: Self-Enforcing Context Ceiling and Incremental Session Handoffs

**Issue:** #329 · **Status:** Approved (approval = merge of this PR) ·
**Author:** athena (`evekhm-athena-app[bot]`) ·
**Open questions:** none

## What is being built

This specification defines the self-enforcing context ceiling protocol, incremental dual-layer session handoffs, and pre-compaction telemetry across both Claude Code and Antigravity harnesses.

`AGENTS.md` ("Context ceiling", lines 492–508) establishes three fundamental operational rules:
1. **200K is the working ceiling for any single context** across all harnesses; crossing it reprices requests at a long-context premium and degrades reasoning quality.
2. **Warn before it gets expensive:** when a conversation grows large, the agent must proactively flag context size and suggest compacting or handing off to a fresh session.
3. **"Silence while the meter runs is a protocol violation, not politeness."**

Historically, nothing implemented this normative standard. Because an agent has no native access to its own context size, the rule was unenforceable from within the session. As a result, the human operator became the sole manual enforcement mechanism across four steps: notice turn cost, ask the agent for a handoff, wait while one is written, and prime a successor session manually. This matches the exact defect class catalogued across the repository (#305, #314): a normative claim in an artifact without enforcing code.

Three severe operational failures result from this defect:
1. **The terminal handoff anti-pattern:** Handoffs are authored at the worst possible moment — at peak context at session close-out, burning thousands of expensive tokens reconstructing state the session held for free hours earlier.
2. **State loss on crash or termination:** Because handoffs exist only after manual close-out, an abnormal termination (terminal closed, process killed, OOM) permanently destroys uncommitted findings and architectural reasoning.
3. **Silent, destructive context compaction across harnesses:** Compaction summarizes transcripts away and destroys granular reasoning:
   - **Claude Code:** `autoCompactWindow` is configured to `180000` (180K) in #330.
   - **Antigravity (agy 1.2.0):** Compaction is unconfigurable and triggers automatically at **~170K tokens** (`preTokens: 170371`, dropping to `21515` post-compaction tokens over 94.7 seconds of wall clock, silently dropping 292,539 cumulative tokens across unannounced events).

Issue #330 establishes the measurement foundation (`scripts/ops/harness/statusline.sh` atomically writing token, spend, and cache metrics to `$CTX_DIR/<session_id>.json`). Issue #329 builds the behavioral enforcement layer that consumes those metrics.

This specification formalizes the self-enforcing context ceiling architecture across ten binding decisions:

1. **Absolute Input Token Thresholding (D1):** Evaluates strictly against `used_tokens` (`total_input_tokens`) from the side-channel state file. Window percentages are prohibited. Pinned at the 140K `WRAP NOW` advisory tier, derived from Antigravity's earlier ~170K auto-compaction boundary minus the 30K budgeted close-out cost (`170K - 30K = 140K`).
2. **Turn-and-Delta Throttling & Hard Stop (D2):** Prevents disruptive prompt injection noise. Nudges fire at 140K, re-prompting only every 5 turns without a narrative refresh or at 10K token increments (150K). At 160K (Critical Tier), throttling is disabled and a mandatory hard stop directive fires on every turn.
3. **Mechanical Snapshot Deduplication (D3):** Unconditional per-turn execution via the `Stop` hook at millisecond latency. Checks git HEAD, dirty working tree status, and token delta; skips disk writes when state has not materially changed.
4. **Unified Delimited Handoff Format (D4):** Maintains a single authoritative file (`ops/handoffs/handoff-<seat>-<date>[-n].txt`) with structured delimiters (`<!-- BEGIN MECHANICAL SNAPSHOT -->` and `<!-- BEGIN NARRATIVE HANDOFF -->`), preserving seamless compatibility with `session-start.sh` and `seat.sh`.
5. **Line-1 Staleness Tracking (D5):** Structured line 1 header explicitly recording turn indexes and staleness: `snapshot: mechanical=turn <M> (<timestamp>), narrative=turn <N> (<K> turns stale) [status: <ACTIVE|WRAPPED|PRECOMPACT>]`.
6. **Pre-Compaction Safety Net & Telemetry Audit (D6):** Pre-compaction snapshot guarantee (R10–R15). In Claude Code, `PreCompact` executes an immediate snapshot with status `PRECOMPACT` and logs to `$CTX_DIR/compaction.log`. In Antigravity, the rolling `Stop` snapshot provides the per-turn guarantee. Post-compaction sessions are directed to terminate and yield to primed successors.
7. **Multi-Channel Nudge Delivery (D7):** `UserPromptSubmit` in Claude Code injects the prompt reminder via stdout. In Antigravity, `statusline.sh` displays `wrap up` / `HANDOFF` chrome tags and `PreInvocation` outputs the prompt reminder.
8. **Worktree Independence & Common-Dir Resolution (D8):** Handoffs always resolve to the shared primary repository checkout's `ops/handoffs/` via `git rev-parse --git-common-dir`, preventing file isolation inside ephemeral worktrees.
9. **Dual-Harness Installer Integration (D9):** `scripts/ops/harness/install.sh` configures `UserPromptSubmit`, `Stop`, and `PreCompact` hooks idempotently across user and project settings, with clean `--uninstall` and self-check validation.
10. **Automated CI Test Suite & Scope Boundaries (D10):** `scripts/ops/tests/context_ceiling_test.sh` exercises all contracts hermetically in CI (`ci-gates.yml`). Updates living documentation in `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, and `docs/SPEC.md`.

```text
scripts/ops/harness/nudge.sh               # threshold evaluator and throttled prompt injector
scripts/ops/harness/snapshot-mechanical.sh # per-turn mechanical snapshot and deduplication writer
scripts/ops/harness/install.sh             # installer wiring UserPromptSubmit, Stop, and PreCompact
scripts/ops/tests/context_ceiling_test.sh  # hermetic CI test suite covering all ceiling contracts
.github/workflows/ci-gates.yml             # registers context_ceiling_test.sh in CI
AGENTS.md                                  # normative ceiling rules under "Context ceiling"
CLAUDE.md                                  # Claude Code hook bindings and PreCompact configuration
GEMINI.md                                  # Antigravity hook bindings and PreInvocation configuration
docs/SPEC.md                               # living spec upsert under harness.context_ceiling
intent/329-context-ceiling/spec.md         # this specification
```

### Manifest of Files Touched by this PR (Athena)

- `intent/329-context-ceiling/spec.md`: This specification.
- `intent/329-context-ceiling/intent.md`: Status updated to Accepted.

### Manifest of Files Touched by the Implementation Rung (Daedalus / Odyssey)

- `scripts/ops/harness/nudge.sh`: Implements absolute token evaluation, turn-and-delta throttling, and critical hard stop prompt emission.
- `scripts/ops/harness/snapshot-mechanical.sh`: Implements deterministic git/token state extraction, deduplication check, delimited section replacement, line-1 staleness tracking, and PreCompact audit logging.
- `scripts/ops/harness/install.sh`: Extends dual-harness installer to register `UserPromptSubmit`, `Stop`, and `PreCompact` hooks in `<repo>/.claude/settings.json` and Antigravity configurations.
- `scripts/ops/tests/context_ceiling_test.sh`: Comprehensive test suite verifying threshold logic, throttling, deduplication, delimited file updating, line-1 formatting, and PreCompact logging.
- `.github/workflows/ci-gates.yml`: Registers `scripts/ops/tests/context_ceiling_test.sh` in the CI test job.
- `AGENTS.md`: Updates "Context ceiling" section with the 140K/160K protocol and dual-layer handoff rules.
- `CLAUDE.md`: Documents Claude Code hook mappings (`UserPromptSubmit`, `Stop`, `PreCompact`).
- `GEMINI.md`: Documents Antigravity hook mappings (`Stop`, `PreInvocation`, statusline chrome tags).
- `docs/SPEC.md`: Living spec upsert documenting `harness.context_ceiling`.
- `intent/329-context-ceiling/plan.md`: Build plan authored by Daedalus.

### Forbidden Files (Untouched)

- `scripts/ci/merge_gate.sh`
- `scripts/ci/review_recorder.py`
- `scripts/ops/work.sh`
- `scripts/ops/claim.sh`
- `personas/**`
- Any other `.github/workflows/**` files outside registering the test suite in `ci-gates.yml`.

---

## Decisions

| ID | Decision | Rationale |
|---|---|---|
| **D1** | **Absolute Input Token Thresholding and Metric Isolation.** Threshold evaluation is executed strictly against `used_tokens` (`total_input_tokens`) read from the side-channel state file `$CTX_DIR/<session_id>.json`. Evaluation against `used_percentage` is strictly prohibited because context window sizes vary from 200K (Opus/Fable) to 1M (Sonnet), causing percentage triggers to fire up to 5x too late. Cumulative `output_tokens` are excluded from threshold evaluation because harness auto-compaction triggers strictly on active context input tokens. The primary advisory threshold is pinned at 140,000 tokens (`140K`), derived from Antigravity's measured ~170K auto-compaction boundary minus the 30K budgeted close-out cost (`170K - 30K = 140K`). | Guarantees threshold invariance across heterogeneous model window sizes. Grounding the threshold in Antigravity's earlier 170K backstop provides a universal ceiling that protects sessions across both harnesses before auto-compaction destroys reasoning. |
| **D2** | **Turn-and-Delta Throttling and Critical Hard Stop.** Nudge delivery follows a strict hysteresis protocol: (1) At `140,000 <= used_tokens < 160,000` (Advisory Tier), `nudge.sh` fires on the turn where `used_tokens` crosses 140K. It re-fires if and only if 5 turns elapse without a narrative refresh OR if `used_tokens` increases by >= 10,000 tokens (e.g. at 150K). When the model executes a narrative refresh (updating the narrative turn counter), the 5-turn counter resets. (2) At `used_tokens >= 160,000` (Critical Tier, within 10K of Antigravity's 170K auto-compaction backstop), throttling is disabled and a mandatory `CRITICAL CONTEXT CEILING REACHED (>=160K)` directive fires on every turn instructing the session to stop work immediately and execute close-out. | Constant prompt injection on every turn past threshold adds disruptive token noise and interrupts multi-step workflows. Turn-and-delta throttling bounds prompt overhead while enforcing escalating urgency as context nears the hard compaction cliff. |
| **D3** | **Mechanical Snapshot Deduplication and Context-Growth Tracking.** `scripts/ops/harness/snapshot-mechanical.sh` executes unconditionally at every turn completion via the `Stop` hook in both Claude Code and Antigravity. Execution is bounded to < 50ms. To prevent disk I/O churn, the script inspects machine state: git HEAD commit SHA, status of modified/untracked files, and `used_tokens`. If git state is unchanged and `used_tokens` has shifted by less than 1,000 tokens since the last snapshot, file writing is skipped (no-op). If git state changed OR `used_tokens` shifted by >= 1,000 tokens, the mechanical snapshot updates in-place. | Ensures the mechanical state on disk is never more than 1 turn stale, guaranteeing survival across crashes, kills, and sudden compactions. Deduplication eliminates redundant disk writes during read-only tool iterations that consume minimal context. |
| **D4** | **Unified Delimited Handoff Format and Section Isolation.** Handoff state is maintained in a single authoritative file per seat (`<primary-checkout>/ops/handoffs/handoff-<seat>-<YYYY-MM-DD>[-n].txt`). The file contains two structured delimited sections: `<!-- BEGIN MECHANICAL SNAPSHOT --> ... <!-- END MECHANICAL SNAPSHOT -->` and `<!-- BEGIN NARRATIVE HANDOFF --> ... <!-- END NARRATIVE HANDOFF -->`. The mechanical hook updates only the mechanical section, never modifying narrative text. When narrative reasoning is authored or refreshed by the model (via `/wrap --snapshot` or `snapshot-mechanical.sh --narrative`), only the narrative section is updated. | Companion files (`.mechanical` and `.narrative`) would fracture handoff state and require rewriting `session-start.sh` and `ops/waves/seat.sh`. A single file with delimited blocks maintains 100% backward compatibility with existing session priming while isolating automated bash writes from cognitive reasoning. |
| **D5** | **Line-1 Staleness Tracking and Status Syntax.** Line 1 of the handoff file adheres to a strict machine-readable format: `snapshot: mechanical=turn <M> (<timestamp>), narrative=turn <N> (<K> turns stale) [status: <ACTIVE\|WRAPPED\|PRECOMPACT>]`. `mechanical=turn <M>` records the session turn index of the last mechanical snapshot. `narrative=turn <N> (<K> turns stale)` records the session turn index when narrative reasoning was last authored and the turn delta (`K = M - N`). When `K == 0`, `(fresh)` is rendered. `[status: ...]` indicates session state: `ACTIVE` during running sessions, `PRECOMPACT` when snapshotted immediately before context compaction, and `WRAPPED` upon terminal `/wrap`. | Alerts successor sessions immediately if narrative reasoning lags behind git state, preventing models from hallucinating alignment between stale design notes and new commits. Standardized syntax permits deterministic parsing by test suites and tooling. |
| **D6** | **Pre-Compaction Safety Net and Telemetry Audit (R10–R15).** In Claude Code, the `PreCompact` hook (matchers `manual`, `auto`) invokes `snapshot-mechanical.sh --precompact`, forcing an immediate mechanical snapshot with `[status: PRECOMPACT]`, updating line 1 staleness, and appending an entry to `$CTX_DIR/compaction.log`: `{"timestamp": ..., "trigger": "auto"|"manual", "pre_tokens": ..., "seat": ..., "narrative_age_turns": ...}`. In Antigravity, where no pre-compaction hook exists, the per-turn rolling `Stop` hook provides the guarantee (at most one turn stale) without inventing fictitious hooks. When compaction occurs in either harness, the post-compaction session is instructed to terminate and yield cleanly to a successor primed from the pre-compaction handoff rather than continuing over truncated context. | Fulfills requirement R10 across both harnesses. PreCompact provides auditability for Claude Code compactions, while rolling Stop provides equivalent data safety in Antigravity. Instructing sessions to yield post-compaction prevents subtle regressions caused by truncated context. |
| **D7** | **Multi-Channel Nudge Delivery across Harnesses.** (1) In Claude Code: `UserPromptSubmit` executes `scripts/ops/harness/nudge.sh` (timeout 10s), reading `$CTX_DIR/<session_id>.json` and injecting the nudge text onto `stdout`, which Claude Code presents to the model as a prompt prefix. (2) In Antigravity: `statusline.sh` displays `<tag>` (`wrap up` at 75–99%, `HANDOFF` at >=100%) in the terminal chrome. In headless or interactive execution where hooks are configured, `PreInvocation` runs `nudge.sh` and outputs the threshold reminder to `stdout` before model invocation. | Answers Open Question 1 from intent. Leverages native hook mechanisms in Claude Code while using multi-channel statusline and PreInvocation delivery in Antigravity to ensure visibility in both interactive and automated environments. |
| **D8** | **Worktree Independence and Primary Checkout Path Resolution.** Handoff files must reside in the machine-shared primary checkout `ops/handoffs/` to ensure persistence across worktree lifecycles. All scripts resolve the primary checkout root via `git rev-parse --git-common-dir`. If `git-common-dir` is `.git`, the primary checkout is `$PWD`. If `git-common-dir` points to an external path `<primary>/.git`, the primary checkout is `<primary>`. Writing to relative paths inside `.claude/worktrees/` is strictly forbidden. | Resolves the run-folder worktree trap. Sessions running inside ephemeral linked worktrees write to the single shared `ops/handoffs/` directory so handoffs survive worktree deletion and are immediately discoverable by successor sessions. |
| **D9** | **Dual-Harness Installer Integration and Verification.** `scripts/ops/harness/install.sh` (from #330) is extended to configure: (1) In `<repo>/.claude/settings.json`: `.hooks.UserPromptSubmit` (invoking `nudge.sh`, timeout 10s), `.hooks.Stop` (invoking `snapshot-mechanical.sh`, timeout 5s), and `.hooks.PreCompact` (invoking `snapshot-mechanical.sh --precompact`, timeout 10s). (2) In Antigravity settings: registers `Stop` and `PreInvocation` hooks where supported. (3) `--uninstall` cleanly removes these hooks while leaving `statusLine` and `SessionStart` intact unless `--all` is passed. `--check` validates end-to-end hook configuration. | Keeps machine-local configuration idempotent, automated, and reversible. Provides instant self-check diagnostics for operators configuring new development VMs. |
| **D10** | **CI Test Suite and Living Spec Scope Boundaries.** (1) `scripts/ops/tests/context_ceiling_test.sh` exercises all mechanics in a hermetic environment: threshold evaluation, window size invariance, turn-and-delta throttling, critical hard stop, snapshot deduplication, delimited file updates, line-1 staleness calculation, PreCompact audit logging, and worktree resolution. (2) Wired into `.github/workflows/ci-gates.yml`. (3) Updates `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, and `docs/SPEC.md`. | Integrates ceiling enforcement into automated CI verification, guaranteeing that threshold arithmetic and hook contracts do not drift. Updates living repository specifications per AGENTS.md. |

---

## Acceptance

Every acceptance test assertion cites the Decision ID it derives from and is checkable without model calls:

- **AT-1 (D1): Absolute Token Threshold Evaluation:** `nudge.sh` given `$CTX_DIR/<session_id>.json` with `used_tokens: 139999` and `output_tokens: 10000` (`total_tokens: 149999`) produces no nudge (exit 0, empty stdout); given `used_tokens: 140000`, produces the 140K `WRAP NOW` advisory nudge.
- **AT-2 (D1): Window Size Invariance:** `nudge.sh` given a 1M `context_window_size` with `used_tokens: 140000` (`used_percentage: 14%`) fires the nudge, proving evaluation is independent of `used_percentage`.
- **AT-3 (D2): Turn-and-Delta Throttling:** After firing at 140K on turn 10, `nudge.sh` produces empty stdout on turns 11, 12, 13, and 14; on turn 15 (5 turns elapsed without narrative refresh), it re-fires the advisory reminder.
- **AT-4 (D2): Narrative Refresh Hysteresis Reset:** If a narrative refresh occurs on turn 12 (updating narrative turn to 12), `nudge.sh` resets its turn counter and suppresses prompts until turn 17.
- **AT-5 (D2): Critical Threshold Hard Stop:** `nudge.sh` given `used_tokens: 160000` outputs the `CRITICAL CONTEXT CEILING REACHED (>=160K)` mandatory stop directive unconditionally on every turn.
- **AT-6 (D3): Mechanical Deduplication:** `snapshot-mechanical.sh` running twice consecutively with identical git HEAD, clean working tree, and unchanged `used_tokens` skips file writes (mtime of handoff file unchanged).
- **AT-7 (D3): Context-Growth Snapshot Trigger:** `snapshot-mechanical.sh` running with unchanged git state but `used_tokens` increased by >= 1,000 tokens updates the mechanical block and records the new token count and turn index.
- **AT-8 (D4): Unified File Delimitation:** `snapshot-mechanical.sh` updates the mechanical block between `<!-- BEGIN MECHANICAL SNAPSHOT -->` and `<!-- END MECHANICAL SNAPSHOT -->` while preserving existing text between `<!-- BEGIN NARRATIVE HANDOFF -->` and `<!-- END NARRATIVE HANDOFF -->`.
- **AT-9 (D5): Line-1 Staleness Header Syntax:** When mechanical turn is 25 and narrative turn is 20, line 1 of the handoff file reads: `snapshot: mechanical=turn 25 (...), narrative=turn 20 (5 turns stale) [status: ACTIVE]`. When mechanical and narrative turns are identical (turn 20), line 1 reads `snapshot: mechanical=turn 20 (...), narrative=turn 20 (fresh) [status: ACTIVE]`.
- **AT-10 (D6): PreCompact Hook Execution & Audit Log:** `snapshot-mechanical.sh --precompact` writes the handoff file with `[status: PRECOMPACT]` on line 1 and appends a valid JSON row to `$CTX_DIR/compaction.log` recording `trigger`, `pre_tokens`, `seat`, `narrative_age_turns`, and `timestamp`.
- **AT-11 (D7): Antigravity Multi-Channel Delivery:** In Antigravity environments, `statusline.sh` renders `wrap up` at 75–99% and `HANDOFF` at >=100%, and `PreInvocation` outputs the nudge to stdout.
- **AT-12 (D8): Worktree Independence:** `snapshot-mechanical.sh` executed from inside a linked git worktree resolves the shared primary checkout's `ops/handoffs/` via `git rev-parse --git-common-dir` and writes to `<primary-checkout>/ops/handoffs/`.
- **AT-13 (D9, D10): Installer and Test Suite Pass:** `install.sh` configures `UserPromptSubmit`, `Stop`, and `PreCompact` hooks; `bash scripts/ops/tests/context_ceiling_test.sh` executes all test cases and exits with code 0; `ci-gates.yml` executes `context_ceiling_test.sh`.

---

## Concerns

- **Hook Latency and Non-Blocking Execution:** Hooks run synchronously during session operation. `Stop` must not exceed 50ms, and `UserPromptSubmit` has a 30s timeout. All scripts are implemented in pure bash using fast built-ins, reading only the small side-channel JSON file (`< 1 KB`) without spawning expensive subprocesses or parsing transcript JSONL trees.
- **Disk I/O and Write Amplification:** Firing a hook on every turn creates potential I/O churn. The mechanical deduplication check (D3) computes state signatures in memory and skips file writes when git status and token metrics have not materially changed.
- **Prompt Injection Noise:** Repeatedly injecting warning text on every prompt past 140K pollutes LLM context and distracts from multi-turn code edits. Turn-and-delta throttling (D2) bounds injections to once every 5 turns or 10K token increments, escalating to per-turn warnings only at the 160K critical cliff.
- **Concurrency and Atomic Writes:** Concurrent sessions or subagents running on the same machine must not corrupt state files. All file writes use temporary dotfiles followed by atomic rename (`mv -f`).

---

## Out of Scope

- Modifying `scripts/ci/merge_gate.sh`, `scripts/ci/review_recorder.py`, `scripts/ops/work.sh`, or `scripts/ops/claim.sh`.
- Automated LLM generation of narrative reasoning within bash hooks (hooks execute bash only; reasoning is authored strictly by the model).
- Cross-session memory coordination or distributed network handoffs (handoffs remain machine-local in `ops/handoffs/`).

---

## Implementation Reference (Verified Prototype Scripts)

### `scripts/ops/harness/nudge.sh`

```bash
#!/usr/bin/env bash
# Copyright 2026 The Agentic SDLC Authors.
# SPDX-License-Identifier: Apache-2.0
#
# nudge.sh — Context ceiling threshold evaluator and prompt injector.
# Executed by UserPromptSubmit (Claude Code) and PreInvocation (Antigravity).
# Reads $CTX_DIR/<session_id>.json. Evaluates absolute input tokens against
# 140K (advisory) and 160K (critical) tiers with turn-and-delta throttling.
set -euo pipefail

CTX_DIR="${AGENTIC_CTX_DIR:-${CLAUDE_CTX_DIR:-${AGY_CTX_DIR:-~/.claude/context}}}"
eval CTX_DIR="$CTX_DIR"

payload="$(cat)"
session_id="$(printf '%s' "$payload" | jq -r '.session_id // .conversation_id // empty')"
[ -n "$session_id" ] || exit 0

ctx_file="$CTX_DIR/$session_id.json"
[ -f "$ctx_file" ] || exit 0

IFS=$'\t' read -r used_tokens seat < <(
  jq -r '[ (.used_tokens // 0), (.seat // "") ] | @tsv' "$ctx_file" 2>/dev/null || echo "0\t"
)

# Tier 1: 140K advisory; Tier 2: 160K critical
if [ "$used_tokens" -ge 160000 ]; then
  cat <<EOF
[CONTEXT CEILING CRITICAL: ${used_tokens}/200K tokens used]
You are within 10K of hard context compaction (~170K), which will destroy granular reasoning.
Stop work immediately and execute /wrap to cleanly close out this session.
