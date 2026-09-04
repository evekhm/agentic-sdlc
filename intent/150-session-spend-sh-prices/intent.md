# Intent: price Gemini models in session_spend and dispatch envelopes

**Issue:** #150 · **Stage:** plan · **Author:** agy (Gemini 3.8 Flash High)

## Problem

`scripts/ops/session_spend.sh` is the offline spend meter this repository runs (`docs/SPEC.md` `ops.spend`). Today, its rate table (`rate_tier()` in `scripts/ops/session_spend.sh:207`) prices Anthropic models only (`fable`, `mythos`, `opus`, `sonnet`, `haiku`). Any Gemini model ID returns unpriced (`""`), producing $0.00 spend. For a system whose architecture relies on a cheap Gemini tier for volume and a frontier tier for judgment, half the ledger is missing and all Gemini runs appear free.

Furthermore, dispatch-level cost tracking for Antigravity is broken:
1. **Antigravity emits raw tokens without dollar calculations:** When `agy -p ... --output-format json` runs, its output envelope contains `.usage` (`input_tokens`, `output_tokens`, `thinking_tokens`, `cache_read_tokens`, `total_tokens`), but does not contain `.total_cost_usd` or `.modelUsage`.
2. **Antigravity transcripts lack token metadata:** On-disk transcripts at `~/.gemini/antigravity-cli/brain/<conversation-id>/.system_generated/logs/transcript.jsonl` record message steps, but do not record per-turn token usage.
3. **Dispatch cost tracking fails silently:** Because `scripts/ops/work.sh:958` extracts `.total_cost_usd` directly from the process envelope, Antigravity dispatches result in an empty `$WORK_COST_FILE`. The `WORK_MAX_USD` spend ceiling (#108) cannot hold on Antigravity runs.
4. **Pipeline SIGPIPE in `session_spend.sh`:** At line 360 of `scripts/ops/session_spend.sh`, `"$TSV"` is passed both on standard input via `sort` and as a positional argument to `awk`. Because `awk` reads the file argument directly, it closes its standard input pipe without reading from `sort`, causing `sort` to receive SIGPIPE (exit code 141) on transcript trees larger than the OS pipe buffer.

## Proposed outcome

1. **Vertex AI Gemini pricing tiers:**
   Add explicit Gemini rate tiers to `rate_tier()` in `scripts/ops/session_spend.sh` (and a shared pricing routine) based on official Google Cloud Vertex AI pricing:
   - `gemini-3.8-flash`: input, cache read, output rates.
   - `gemini-3.7-flash`: input, cache read, output rates.
   - `gemini-3.6-flash`: input, cache read, output rates.
   - `gemini-3.5-flash`: input, cache read, output rates.
   - `gemini-3.1-pro`: input, cache read, output rates.
   Maintain table discipline: unknown versions and bare aliases are reported as unpriced rather than guessed or assigned neighboring rates.

2. **Antigravity dispatch pricing in `work.sh`:**
   Extend `scripts/ops/work.sh` to handle `launch_harness=antigravity`. When `agy` produces its JSON envelope, calculate USD from `.usage` using the model requested for the dispatch (from `--model` or `config/model_tiers.yaml`), and record both the cost and model into `$WORK_COST_FILE`. This enforces `WORK_MAX_USD` bounds across both harnesses.

3. **Envelope ingestion for multi-harness session spend:**
   Allow `session_spend.sh` to ingest run envelope records (e.g. from `runs/**/envelope.json` or run logs) so that Antigravity sessions can be analyzed alongside Claude Code transcript trees, displaying per-day, per-session, and per-model breakdowns.

4. **Fix pipeline exit code in `session_spend.sh`:**
   Remove the redundant `"$TSV"` argument to `awk` at line 360, allowing `awk` to read sorted input from `sort` on standard input, preventing exit code 141 and ensuring chronological sort order for `--ttl-compare`.

## Affected users and systems

- **`scripts/ops/session_spend.sh`** and **`scripts/ops/tests/session_spend_test.sh`**: Rate table extension, envelope ingestion, pipeline fix, and synthetic test scenarios for Gemini models.
- **`scripts/ops/work.sh`**: Harness-specific cost calculation from `.usage` when `.total_cost_usd` is not provided natively.
- **`docs/SPEC.md`**: Updates to `ops.spend` and `ops.dispatch` reflecting Gemini rate support and envelope pricing semantics.
- **Cost ledger (#104)**: Provides the foundation for recording normalized spend across both harnesses.

## Constraints

- **List rates from Vertex AI**: Pricing must match official Vertex AI list pricing and cite effective dates in code comments.
- **Fail-safe on unknown models**: Unknown versions or model names must report warnings and zero USD rather than guessing adjacent rates.
- **Worktree isolation**: All implementation and test verification happens inside the dedicated worktree.

## Open questions

1. Should `work.sh` delegate token-to-dollar pricing to a standalone helper script (`scripts/ops/price_tokens.sh`) shared with `session_spend.sh` to avoid duplicating Vertex pricing logic between bash and awk?
2. Where should unattended Antigravity session envelopes be archived so `session_spend.sh` can scan them consistently without scanning transient worktree paths?
