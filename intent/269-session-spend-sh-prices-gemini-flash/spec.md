# Spec: Price Gemini Flash and Pro at Pinned 3.x Versions in session_spend and work.sh

**Issue:** #269 · **Status:** Approved (approval = merge of this PR) · **Author:** athena (`evekhm-athena-app[bot]`) · **Open questions:** none

## What is being built

This specification resolves issue #269 by updating Gemini token rate tiers in `scripts/ops/session_spend.sh` and `scripts/ops/work.sh` to match current Google Cloud Gemini platform pricing and the repository cost table in `README.md` Section 5.

Currently, `rate_tier()` in `scripts/ops/session_spend.sh` and the duplicate rate calculation in `scripts/ops/work.sh` price all Gemini Flash versions (1.5 through 3.8) at $0.15 base input, $0.1875 5-minute cache write, $0.30 1-hour cache write, $0.0375 cache read, and $0.60 output per million tokens (Decision #150 D2). All Gemini Pro versions (1.5 through 3.1) are priced at $1.25 base input, $1.5625 5-minute cache write, $2.50 1-hour cache write, $0.3125 cache read, and $5.00 output per million tokens (#150 D2).

These numbers reflect Gemini 1.5 legacy rates. The repository has pinned all Antigravity tiers to `gemini-3.8-flash-{low,medium,high}` (#271). In `README.md` Section 5 (PR #263, amended in PR #274 per #35 D3), Google Cloud Gemini Enterprise platform pricing is documented as $0.75 base input, $0.075 cache read, and $3.75 output per million tokens for Gemini 3.8 Flash, with automatic caching and no separate cache write charge. Gemini 3.1 Pro (Preview) list price is $2.00 base input, $0.20 cache read, and $12.00 output per million tokens for prompts at or below 200k tokens.

This specification:
1. Reverses Decision #150 D2 in part by updating `rate_tier()` in `scripts/ops/session_spend.sh` to price Gemini Flash 3.x models at `"0.75 0 0 0.075 3.75"` and Gemini Pro 3.1 at `"2.00 0 0 0.20 12.00"`.
2. Preserves legacy rates (`"0.15 0.1875 0.30 0.0375 0.60"` for Flash, `"1.25 1.5625 2.50 0.3125 5.00"` for Pro) for historical 1.5 and 2.x versions, avoiding breaking historical transcripts or test fixtures.
3. Sets cache write rates (`cw_5m`, `cw_1h`) to 0 for Gemini 3.x models, reflecting automatic caching without separate cache write surcharges.
4. Synchronizes the inline `awk` snippet in `scripts/ops/work.sh:1307-1329` to match `session_spend.sh`'s `rate_tier()`, ensuring accurate `WORK_MAX_USD` (#108) ceiling enforcement on Antigravity dispatches.
5. Keeps `rate_tier()` as a static model-string lookup, scheduling the 2027-01-01 rate increase ($1.50 input / $0.15 read / $7.50 output per `README.md`) for deployment via repository pull request when effective.
6. Re-affirms fail-closed handling (#150 D3): unrecognized Gemini versions or bare aliases return empty string, emit loud warnings, accumulate unpriced tokens, and cause scripts to fail closed.
7. Updates contract tests in `scripts/ops/tests/session_spend_test.sh` and `scripts/ops/tests/work_test.sh` to assert updated rate calculations and preserve legacy assertions.
8. Scopes living specification updates (`docs/SPEC.md` `ops.spend`) for the implementation rung.

### Manifest of Files Touched by the Implementation Rung

- `scripts/ops/session_spend.sh`: update `rate_tier()` Gemini Flash 3.x and Pro 3.1 rate tuples.
- `scripts/ops/work.sh`: synchronize inline awk `rate_tier()` with `session_spend.sh`.
- `scripts/ops/tests/session_spend_test.sh`: update test expectations for Gemini 3.8 Flash and Gemini 3.1 Pro, preserving 1.5 assertions.
- `scripts/ops/tests/work_test.sh`: update Antigravity envelope cost test expectations for Gemini 3.8 Flash while preserving legacy 1.5 Pro assertions.
- `docs/SPEC.md`: living spec update under `ops.spend` documenting updated Gemini rates effective 2026-09-08 per #269.
- `intent/269-session-spend-sh-prices-gemini-flash/plan.md`: ordered implementation plan authored by Daedalus.

### Manifest of Files Touched by this PR (Athena)

- `intent/269-session-spend-sh-prices-gemini-flash/spec.md`: this specification.
- `intent/269-session-spend-sh-prices-gemini-flash/intent.md`: update status to Accepted.
- `intent/150-session-spend-sh-prices/spec.md`: record forward amendment note for Decision D2 per product-coherence rule 4.

### Forbidden Files (Untouched)

- `personas/**`
- `config/model_tiers.yaml`
- `config/deployments.yaml`
- `scripts/ops/session_spend.sh` (implementation rung)
- `scripts/ops/work.sh` (implementation rung)
- `scripts/ops/tests/**` (implementation rung)
- `docs/SPEC.md` (implementation rung)
- `README.md` (already reflects $0.75/$3.75 rates referencing #269)

## Related Decisions and Prior Art

- **#150 D1:** `model_family()` and `model_version()` recognize Gemini model IDs and minor version numbers while returning empty string for bare aliases. Restated and preserved.
- **#150 D2:** Priced all Gemini Flash versions at $0.15/$0.60 and Pro versions at $1.25/$5.00. Reversed in part by D1 of this specification for Gemini 3.x versions.
- **#150 D3:** Unrecognized Gemini versions and aliases fail closed as unpriced with loud warnings. Restated and re-affirmed by D5.
- **#150 D4:** `work.sh` computes Antigravity dispatch costs from `.usage` and writes to `$WORK_COST_FILE`. Refined by D3 of this specification to synchronize updated 3.x rates.
- **#35 D3:** `README.md` Section 5 carries the tier rate table citing $0.75 / $0.075 / $3.75 for Gemini 3.8 Flash. Refined by D1 and D3 of this specification to bring offline metering into alignment with the documentation.
- **#108 D1:** `WORK_MAX_USD` spend ceiling enforcement in `work.sh`. Supported by accurate rate calculations in D3.
- **#271 D1:** Pinned all Antigravity tiers to `gemini-3.8-flash-{low,medium,high}` in `config/model_tiers.yaml`. Supported by D1.

## Decisions

| ID | Decision | Rationale |
|---|---|---|
| **D1** | **Rate tiers for Gemini Flash and Pro models (reverses #150 D2 in part).** In `scripts/ops/session_spend.sh` and `scripts/ops/work.sh`, `rate_tier(m)` returns rate tuples in the standard space-separated format: `input_base cw_5m cw_1h cache_read output` (USD per million tokens).<br>1. For Gemini Flash:<br>- Modern Flash versions (`3.5`, `3.6`, `3.7`, `3.8`): return `"0.75 0 0 0.075 3.75"`. Base input is $0.75, 5-minute cache write is $0.00, 1-hour cache write is $0.00, cache read is $0.075, and output is $3.75 per million tokens.<br>- Legacy Flash versions (`1.5`, `2.0`, `2.5`): return `"0.15 0.1875 0.30 0.0375 0.60"`, preserving historical rates for legacy transcripts.<br>2. For Gemini Pro:<br>- Modern Pro version (`3.1`): returns `"2.00 0 0 0.20 12.00"` (for prompts at or below 200k tokens). Base input is $2.00, 5-minute cache write is $0.00, 1-hour cache write is $0.00, cache read is $0.20, and output is $12.00 per million tokens.<br>- Legacy Pro versions (`1.5`, `2.5`): return `"1.25 1.5625 2.50 0.3125 5.00"`, preserving historical rates. | Reverses Decision #150 D2 for Gemini 3.x models. #150 D2 priced all Gemini Flash versions at Gemini 1.5 rates ($0.15 input / $0.60 output) and Pro at 1.5 rates ($1.25 input / $5.00 output). The published rates in `README.md` Section 5 (PR #263, amended in PR #274 per #35 D3) and official Google Cloud Gemini platform pricing document $0.75 input / $0.075 read / $3.75 output for Gemini 3.8 Flash and $2.00 input / $0.20 read / $12.00 output for Gemini 3.1 Pro. Legacy versions retain legacy pricing to preserve accurate historical accounting on archived transcripts. |
| **D2** | **Automatic cache write accounting.** In `rate_tier(m)`, cache write rates (`cw_5m` and `cw_1h`) for Gemini 3.x models are set to `0`. | As documented in `README.md` Section 5, Google Cloud Gemini caching is automatic with no separate write fee. Setting cache write fields to 0 accurately reflects that turns creating cache entries incur no surcharge beyond base input token processing. |
| **D3** | **Synchronization of `work.sh` Antigravity envelope cost computation.** The inline `awk` script inside `scripts/ops/work.sh:1307-1329` that computes USD cost from `.usage` for Antigravity envelopes implements the identical rate table as `scripts/ops/session_spend.sh`'s `rate_tier()`. | `work.sh` enforces the `WORK_MAX_USD` spend ceiling (#108). Under legacy rates, Antigravity dispatches were priced 5x too low on input and 6.25x too low on output, allowing sessions to exceed configured dollar ceilings. Synchronizing the rate table ensures that Antigravity sessions are metered against the true platform cost. |
| **D4** | **Static rate lookup and future scheduled price transitions.** `rate_tier(m)` remains a static lookup function dependent solely on model string `m`. The scheduled price adjustment for Gemini 3.8 Flash taking effect on 2027-01-01 ($1.50 input / $0.15 read / $7.50 output per `README.md` Section 5) will be applied via a standard repository pull request when effective. | Avoids adding clock or timestamp dependencies to `rate_tier(m)` across `session_spend.sh` and `work.sh`. Pure model string lookup maintains deterministic behavior and protects against system clock skew. |
| **D5** | **Fail-closed unpriced model handling (re-affirms #150 D3).** Any unrecognized Gemini model string, bare alias (`gemini`, `gemini-flash`, `gemini-pro`), or unsupported version returns `""` from `rate_tier()`. In `scripts/ops/session_spend.sh`, unpriced tokens accumulate into `unpriced[model]`, emit a loud warning to standard error, add $0.00 to calculated spend, suppress the `TOTAL` line, and cause `session_spend.sh` to exit with status 1. In `scripts/ops/work.sh`, an unpriced model leaves `$cost` empty, which empties `$WORK_COST_FILE` and triggers `exit 1` when `WORK_MAX_USD` is set. | Fail-closed error handling prevents unpriced or misconfigured models from silently running free or bypassing spend ceilings. |
| **D6** | **Contract test suite alignment.** Contract tests in `scripts/ops/tests/session_spend_test.sh` and `scripts/ops/tests/work_test.sh` assert the updated rates:<br>1. `session_spend_test.sh` tests:<br>- `gemini-3.8-flash-high` with 1M input, 1M cache read, 1M output prices at $4.58 (exact: 0.75 + 0.075 + 3.75 = 4.575, rounded to 4.58).<br>- `gemini-3.8-flash-medium` with 1M input prices at $0.75.<br>- `gemini-1.5-flash` with 1M input prices at $0.15.<br>- `gemini-3.1-pro-low-thinking` with 1M input, 1M cache read, 1M output prices at $14.20 (2.00 + 0.20 + 12.00).<br>- `gemini-1.5-pro` with 1M input prices at $1.25.<br>- Antigravity envelope with 1M input, 500k output, 500k thinking tokens on `gemini-3.8-flash-high` prices at $4.50.<br>2. `work_test.sh` tests:<br>- An Antigravity envelope with `gemini-3.8-flash-high` prices 1M input tokens at $0.75 and records `0.750000` to `$WORK_COST_FILE`.<br>- Legacy `gemini-1.5-pro-002` envelope continues pricing 1M input tokens at $1.25 and recording `1.250000` to `$WORK_COST_FILE`. | Contract test assertions verify that current pinned versions and legacy models both calculate expected costs without regression. |
| **D7** | **Living spec update scope.** `docs/SPEC.md` under `ops.spend` is updated in place during the implementation rung to document that `session_spend.sh` prices Gemini 3.x models at rates effective 2026-09-08 per #269. | Maintains living specification currency per AGENTS.md while respecting Athena's authority boundary (`intent/**`). |

## Acceptance

- **AT-269-1 (Flash 3.8 Rate Tuple in session_spend.sh):** Evaluating `rate_tier("gemini-3.8-flash-high")` in `scripts/ops/session_spend.sh` returns `"0.75 0 0 0.075 3.75"`.
  - Derives from: D1, D2.
  - Red condition: `rate_tier("gemini-3.8-flash-high")` returning `"0.15 0.1875 0.30 0.0375 0.60"` or any string not equal to `"0.75 0 0 0.075 3.75"`.
- **AT-269-2 (Flash 3.8 Session Spend Calculation):** In `scripts/ops/tests/session_spend_test.sh`, processing a transcript with 1M input tokens, 1M cache read tokens, and 1M output tokens for model `gemini-3.8-flash-high` yields `$4.58` in the Per model summary table.
  - Derives from: D1, D2, D6.
  - Red condition: Output summary evaluating to `$0.79` under legacy rates or any value other than `$4.58`.
- **AT-269-3 (Flash 3.8 Input-Only Calculation):** In `scripts/ops/tests/session_spend_test.sh`, processing a transcript with 1M input tokens and zero cache read or output tokens for model `gemini-3.8-flash-medium` yields `$0.75` in the Per model summary table.
  - Derives from: D1, D6.
  - Red condition: Output summary evaluating to `$0.15` under legacy rates or any value other than `$0.75`.
- **AT-269-4 (Legacy Flash 1.5 Rate Preservation):** In `scripts/ops/tests/session_spend_test.sh`, processing a transcript with 1M input tokens for model `gemini-1.5-flash` yields `$0.15` in the Per model summary table.
  - Derives from: D1, D6.
  - Red condition: `gemini-1.5-flash` returning empty string or evaluating to `$0.75`.
- **AT-269-5 (Pro 3.1 Rate Tuple and Calculation):** In `scripts/ops/tests/session_spend_test.sh`, processing a transcript with 1M input tokens, 1M cache read tokens, and 1M output tokens for model `gemini-3.1-pro-low-thinking` yields `$14.20` in the Per model summary table.
  - Derives from: D1, D2, D6.
  - Red condition: Output summary evaluating to `$6.56` under legacy rates or any value other than `$14.20`.
- **AT-269-6 (Legacy Pro 1.5 Rate Preservation):** In `scripts/ops/tests/session_spend_test.sh`, processing a transcript with 1M input tokens for model `gemini-1.5-pro` yields `$1.25` in the Per model summary table.
  - Derives from: D1, D6.
  - Red condition: `gemini-1.5-pro` returning empty string or evaluating to `$2.00`.
- **AT-269-7 (Antigravity Envelope Spend Calculation in session_spend.sh):** In `scripts/ops/tests/session_spend_test.sh`, processing an Antigravity dispatch JSON envelope containing 1M input tokens, 500k output tokens, and 500k thinking tokens for model `gemini-3.8-flash-high` yields `$4.50` in the Per model summary table.
  - Derives from: D1, D6.
  - Red condition: Output summary evaluating to `$0.75` under legacy rates or any value other than `$4.50`.
- **AT-269-8 (Flash 3.8 Rate Tuple in work.sh):** Evaluating `rate_tier("gemini-3.8-flash-high")` within `scripts/ops/work.sh` returns `"0.75 0 0 0.075 3.75"`.
  - Derives from: D1, D3.
  - Red condition: `work.sh` evaluating `gemini-3.8-flash-high` to `"0.15 0.1875 0.30 0.0375 0.60"` or empty string.
- **AT-269-9 (Antigravity Envelope Cost Recording in work_test.sh):** In `scripts/ops/tests/work_test.sh`, a headless Antigravity dispatch with model `gemini-3.8-flash-high` and 1M input tokens writes `0.750000` to line 1 of `$WORK_COST_FILE`.
  - Derives from: D1, D3, D6.
  - Red condition: Line 1 of `$WORK_COST_FILE` containing `0.150000`, empty file, or any value other than `0.750000`.
- **AT-269-10 (Legacy Pro Cost Recording in work_test.sh):** In `scripts/ops/tests/work_test.sh`, a headless Antigravity dispatch with model `gemini-1.5-pro-002` and 1M input tokens writes `1.250000` to line 1 of `$WORK_COST_FILE`.
  - Derives from: D1, D3, D6.
  - Red condition: Line 1 of `$WORK_COST_FILE` containing empty file or any value other than `1.250000`.
- **AT-269-11 (Unpriced Gemini Models Fail Closed):** Evaluating `rate_tier("gemini-9.9-flash")` or `rate_tier("gemini")` returns empty string `""` in both `scripts/ops/session_spend.sh` and `scripts/ops/work.sh`, triggering unpriced token warnings and exit code 1.
  - Derives from: D5.
  - Red condition: An unrecognized Gemini model version returning a fallback rate tuple and exiting 0.
- **AT-269-12 (Living Spec Synchronization):** `docs/SPEC.md` under `ops.spend` documents the updated Gemini 3.x rates effective 2026-09-08 referencing issue #269, and `scripts/ci/spec_check.sh origin/main` passes in the implementation PR.
  - Derives from: D7.
  - Red condition: `docs/SPEC.md` omitting Gemini 3.x rates or failing `spec_check.sh`.
