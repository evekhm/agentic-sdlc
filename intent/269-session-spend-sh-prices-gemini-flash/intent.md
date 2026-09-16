# Intent: price Gemini Flash and Pro at current pinned versions in session_spend and work.sh

**Issue:** #269 · **Stage:** plan · **Author:** athena (`evekhm-athena-app[bot]`)

## Problem

`scripts/ops/session_spend.sh` measures session cost by pricing transcript and envelope token usage against list rates (`docs/SPEC.md` `ops.spend`). Currently, `rate_tier()` in `scripts/ops/session_spend.sh:250-264` prices all Gemini Flash versions (`1.5`, `2.0`, `2.5`, `3.5`, `3.6`, `3.7`, `3.8`) at Gemini 1.5's legacy rate of $0.15 base input, $0.1875 5-minute cache write, $0.30 1-hour cache write, $0.0375 cache read, and $0.60 output per million tokens (recorded in Decision #150 D2). Similarly, all Gemini Pro versions (`1.5`, `2.5`, `3.1`) are priced at Gemini 1.5 Pro's legacy rate of $1.25 base input, $1.5625 5-minute cache write, $2.50 1-hour cache write, $0.3125 cache read, and $5.00 output per million tokens (#150 D2).

The repository has pinned its Antigravity tiers across all roles to `gemini-3.8-flash-{low,medium,high}` (#271). In `README.md` (section 5, lines 630-645, added in PR #263 and amended in PR #274 per Decision #35 D3), the cost thesis explicitly cites Google Cloud's Gemini Enterprise / Agent Platform price of $0.75 input, $0.075 cache read, and $3.75 output per million tokens for Gemini 3.8 Flash. The table notes automatic caching with no separate write charge in that data, and notes that Flash's rate rises to $1.50 input, $0.15 cache read, and $7.50 output on 2027-01-01.

Because `session_spend.sh` still uses the 1.5 rates ($0.15 input, $0.60 output), offline spend reports understate actual spend by 5x on input and more than 6x on output. In addition, `scripts/ops/work.sh:1312-1320` embeds a duplicate copy of `rate_tier()` to measure cost for Antigravity dispatch envelopes; running with the outdated rates allows the `WORK_MAX_USD` spend ceiling (#108) to admit 5x more spend than configured. Finally, Gemini 3.1 Pro (Preview) list price is $2.00 input and $12.00 output for prompts at or under 200k tokens, which differs from the legacy 1.5 Pro rate of $1.25 input and $5.00 output.

## Proposed outcome

1. **Update Gemini Flash and Pro rates in `session_spend.sh`:**
   Modify `rate_tier()` in `scripts/ops/session_spend.sh` to price Gemini 3.8 Flash (and Gemini 3.1 Pro) at their current rates, bringing the script into alignment with `README.md` and current platform pricing.

2. **Synchronize `work.sh` Antigravity pricing:**
   Update the Antigravity envelope pricing calculation in `scripts/ops/work.sh` to match `session_spend.sh`, ensuring that `WORK_MAX_USD` bounds enforce the correct spend limits during automated dispatches.

3. **Reconcile test suites:**
   Update test expectations in `scripts/ops/tests/session_spend_test.sh` and `scripts/ops/tests/work_test.sh` to assert against the updated rate tuples.

4. **Document decisions and living spec updates:**
   Record numbered decisions in `spec.md` that explicitly reverse or refine Decision #150 D2. Update `docs/SPEC.md` under `ops.spend` to document the effective date and rates for Gemini 3.x models.

## Affected users and systems

- **`scripts/ops/session_spend.sh`**: Offline session spend meter (`docs/SPEC.md` `ops.spend`).
- **`scripts/ops/work.sh`**: Dispatch runner and `WORK_MAX_USD` ceiling enforcement for Antigravity sessions (`docs/SPEC.md` `ops.dispatch`).
- **`scripts/ops/tests/session_spend_test.sh`**: Contract test verifying rate tiers and envelope ingestion.
- **`scripts/ops/tests/work_test.sh`**: Contract test verifying Antigravity envelope cost computation.
- **`docs/SPEC.md`**: Living specification under `ops.spend`.
- **`README.md`**: Section 5 cost table (already documents $0.75 / $0.075 / $3.75 referencing #269).

## Constraints

- Strict five-rung lifecycle: At this PLAN stage, only `intent.md` is authored. No scripts, tests, or configurations are modified.
- Worktree isolation: All commits occur on the dedicated branch `athena/269-session-spend-sh-prices-gemini-flash` inside `.claude/worktrees/athena-269-session-spend-sh-prices-gemini-flash`.
- Decision integrity: Any rate change reversing #150 D2 must be explicitly cited as reversing or refining #150 D2 in `spec.md`.
- Fail-closed pricing: Unrecognized Gemini models or bare aliases must continue to return empty string and fail closed with a warning.

## Relationships

- Refines #150 D2: Replaces the Gemini 1.5 rate tuple for Gemini 3.8 Flash ($0.75/$3.75 vs $0.15/$0.60) and Gemini 3.1 Pro ($2.00/$12.00 vs $1.25/$5.00).
- Depends on #271: Repinned all five Antigravity tiers to Gemini 3.8 Flash.
- Refines #35 D3: Aligns the offline spend meter with README section 5's rate table.
- Relates to #104: Provides accurate cost calculation for session spend markers and BigQuery views.

## Open questions

1. **Price basis and source of truth:**
   Should `rate_tier()` encode the Gemini Developer API list price ($0.75 input / $3.75 output for 3.8 Flash; $2.00 input / $12.00 output for 3.1 Pro) as published in `README.md`, or should the rates wait for an operator-provided Vertex AI console export if enterprise contractual billing differs?
   - Option A: Developer API list price ($0.75 / $3.75), matching `README.md`.
   - Option B: Signed-in Google Cloud Vertex AI enterprise rate provided by operator.
   - Differing case: A session consuming 1M input tokens and 1M output tokens on `gemini-3.8-flash-high` prices at $4.50 under Option A. Under legacy rates it prices at $0.75, and under custom enterprise discount schedules it may differ.

2. **Cache multipliers and cache write pricing:**
   In `session_spend.sh`, `rate_tier()` returns five values: `input_base cw_5m cw_1h cache_read output`. For Gemini, caching is automatic with no separate write charge in Antigravity. What values should be returned for `cw_5m` and `cw_1h`?
   - Option A: Set cache write rates to $0.00 (`0.75 0 0 0.075 3.75`).
   - Option B: Retain Claude-style multipliers (1.25x / 2.0x input) for compatibility with scripts expecting non-zero values (`0.75 0.9375 1.50 0.075 3.75`).
   - Differing case: A transcript reporting cache creation tokens on a Gemini model charges non-zero under Option B and zero under Option A.

3. **Historical version retention:**
   Should legacy Gemini versions (`gemini-1.5-flash`, `gemini-1.5-pro`, `gemini-2.0-flash`, `gemini-2.5-flash`) remain priced at their historical $0.15 / $0.60 and $1.25 / $5.00 rates, or should only 3.x models be supported?
   - Option A: Keep version branch in `rate_tier()` pricing 1.5/2.x at legacy rates and 3.x at modern rates.
   - Option B: Only price versions pinned in `config/model_tiers.yaml` (3.8 Flash and 3.1 Pro), marking earlier versions unpriced.
   - Differing case: Analyzing an archived transcript containing `gemini-1.5-flash` messages exits 0 and computes cost under Option A, but prints an unpriced warning and exits non-zero under Option B.

4. **Future scheduled rate increase (2027-01-01):**
   `README.md` documents that Gemini 3.8 Flash rates increase to $1.50 input / $0.15 cache read / $7.50 output on 2027-01-01. Should the implementation handle this transition dynamically by comparing turn timestamps against 2027-01-01T00:00:00Z, or keep static rates updated when the date arrives?
   - Option A: Static rate tuple ($0.75 / $3.75); schedule updated via future PR when effective.
   - Option B: Timestamp-aware rate selection based on assistant message timestamp.
   - Differing case: Repricing a simulated 2027 transcript prices at $0.75 under Option A and $1.50 under Option B.

5. **Deduplication across `session_spend.sh` and `work.sh`:**
   Should DESIGN extract Gemini token pricing into a shared helper script (e.g. `scripts/ops/price_tokens.sh`) or keep the inline `awk` snippet in `work.sh` synchronized with `session_spend.sh`?

## Non-goals

- Re-pinning persona models or modifying `config/model_tiers.yaml`.
- Changing CLI arguments or summary reporting format of `scripts/ops/session_spend.sh`.
- Pricing models from non-Gemini, non-Anthropic providers.
