# Spec: price Gemini models in session_spend and dispatch envelopes

**Issue:** #150 · **Status:** Approved (approval = merge of this PR) ·
**Author:** agy (Gemini 3.8 Flash High) ·
**Open questions:** none

This specification settles the rate table, token usage calculation,
envelope ingestion, and pipeline reliability for Gemini models across
`session_spend.sh` and `work.sh`.

## What is being built

```text
scripts/ops/session_spend.sh        model_family(), model_version(), and rate_tier()
                                    support for Gemini; Antigravity envelope ingestion;
                                    fix pipeline argument at line 360 (SIGPIPE 141)
scripts/ops/work.sh                 calculate USD cost from .usage for Antigravity
                                    dispatches and write to $WORK_COST_FILE
scripts/ops/tests/session_spend_test.sh  pricing regression tests for Gemini models,
                                    unpriced version warnings, and pipeline exit codes
scripts/ops/tests/work_test.sh      test asserting Antigravity envelope pricing into
                                    $WORK_COST_FILE
docs/SPEC.md                        ops.spend and ops.dispatch spec updates
```

Not touched, deliberately: `personas/**` (no persona definitions change),
`config/model_tiers.yaml` (the existing model pins remain unchanged).

## Decisions

| # | Decision |
|---|---|
| D1 | **`model_family()` and `model_version()` recognize Gemini model IDs.** `model_family(m)` returns `"gemini"` when `m ~ /gemini/`. `model_version(m)` extracts the generation and minor version (e.g. `gemini-3.8-flash-high` → `3.8`, `gemini-3.7-flash` → `3.7`, `gemini-3.1-pro` → `3.1`, `gemini-2.5-flash` → `2.5`, `gemini-1.5-flash` → `1.5`). Bare aliases (`gemini`, `gemini-flash`, `gemini-pro`) return `""` to prevent guessing unpinned pricing tiers. |
| D2 | **Gemini rates are priced per official Google Cloud Vertex AI list rates (USD per million tokens).** In `rate_tier(m)`, rate tuples are returned in the standard space-separated format: `input_base cw_5m cw_1h cache_read output`. Flash models (`1.5`, `2.0`, `2.5`, `3.5`, `3.6`, `3.7`, `3.8`) are priced at base input $0.15, 5m cache write $0.1875, 1h cache write $0.30, cache read $0.0375, output $0.60 (`"0.15 0.1875 0.30 0.0375 0.60"`). Pro models (`1.5`, `2.5`, `3.1`) are priced at base input $1.25, 5m cache write $1.5625, 1h cache write $2.50, cache read $0.3125, output $5.00 (`"1.25 1.5625 2.50 0.3125 5.00"`). |
| D3 | **Unknown Gemini model versions and aliases are reported as unpriced and warned loudly.** Following the table discipline of #105 and R1-4, any Gemini version not explicitly listed in `rate_tier()` returns `""`. In `usd()`, this accumulates into `unpriced[model]` and issues a loud warning with $0.00 calculated cost, never silently falling back to an adjacent tier. |
| D4 | **`work.sh` calculates Antigravity dispatch cost from `.usage` and records it to `$WORK_COST_FILE`.** When `launch_harness=antigravity`, `agy` emits raw token counts in `.usage` without `.total_cost_usd`. `work.sh` reads `.usage.input_tokens`, `.usage.output_tokens`, `.usage.thinking_tokens`, and `.usage.cache_read_tokens` from the envelope, calculates the USD cost using the resolved dispatch model (from `model_of "$persona"` or `$WORK_MODEL`), and writes the calculated cost to line 1 and the model name to line 2 of `$WORK_COST_FILE`. This activates `WORK_MAX_USD` (#108) cost ceilings for Antigravity dispatches. If `.usage` is missing or unpriced, `$WORK_COST_FILE` is truncated so callers refuse rather than proceeding. |
| D5 | **`session_spend.sh` ingests Antigravity dispatch envelopes.** In addition to Claude Code `*.jsonl` assistant messages, `session_spend.sh` parses JSON envelopes (e.g. `*.json` or envelope records containing `.conversation_id` and `.usage`). For each envelope, it extracts timestamp, conversation ID, model, and token metrics, emitting a row into `$TSV`. This enables unified spend reports across both harnesses. |
| D6 | **The redundant `$TSV` file argument to `awk` at line 360 of `session_spend.sh` is removed.** Line 160 pipes sorted TSV from `sort` into `awk`. Passing `"$TSV"` as an argument at line 360 caused `awk` to ignore standard input and read the file argument unsorted, closing standard input prematurely and triggering SIGPIPE (exit code 141) on `sort`. Removing the argument restores standard input reading and chronological sorting. |
| D7 | **Living spec updates for `ops.spend` and `ops.dispatch`.** `docs/SPEC.md` is updated in place: `ops.spend` documents support for Gemini models and envelope ingestion; `ops.dispatch` documents Antigravity cost computation in `work.sh`. |

## Acceptance

1. `rate_tier()` in `session_spend.sh` returns `"0.15 0.1875 0.30 0.0375 0.60"` for `gemini-3.8-flash-high`, `gemini-3.8-flash-medium`, `gemini-3.7-flash`, and `"1.25 1.5625 2.50 0.3125 5.00"` for `gemini-3.1-pro` (D1, D2).
2. An unrecognized Gemini model (e.g. `gemini-9.9-flash`) returns unpriced, accumulates into unpriced tokens, outputs a warning, and adds $0.00 to total spend (D3).
3. Running `session_spend.sh` on an Antigravity dispatch JSON envelope extracts `.usage` tokens, prices them with the specified model, and outputs valid summary TSV lines (D4, D5).
4. Running `session_spend.sh` with `set -eo pipefail` on a large transcript tree exits 0 with no SIGPIPE 141 (D6).
5. When `work.sh` runs an `antigravity` dispatch in headless mode, `$WORK_COST_FILE` contains the computed dollar cost on line 1 and the model name on line 2 (D4).
6. When `work.sh` encounters an unpriced or broken envelope, `$WORK_COST_FILE` is emptied and a warning is printed to stderr (D4).
7. `scripts/ci/spec_check.sh origin/main` passes with the updated living spec entries in `docs/SPEC.md` (D7).
