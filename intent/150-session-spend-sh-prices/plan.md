# Plan: price Gemini models in session_spend and dispatch envelopes

**Issue:** #150 · **Spec:** spec.md (Approved) · **Author:** daedalus (`evekhm-daedalus-app[bot]`)

Six tasks. Each names the files it touches, the Decision rows it
satisfies, and the check that proves it. Line numbers cite HEAD on `origin/main`.

**Order.**
T1 (rate table and model parsing) → T2 (pipeline stdin fix) → T3 (envelope ingestion)
→ T4 (work.sh dispatch cost computation) → T5 (test suite coverage) → T6 (living spec).

---

## T1 · Rate table and model parsing in `scripts/ops/session_spend.sh` — D1, D2, D3

Touch: `scripts/ops/session_spend.sh`

### Details
1. Extend `model_family(m)`:
   Add `if (m ~ /gemini/) return "gemini"`.
2. Extend `model_version(m)`:
   Support Gemini version extraction:
   - Match `gemini-([0-9]+\.[0-9]+)` or `gemini-([0-9]+)`
   - Extract major.minor version string (e.g. `3.8`, `3.7`, `3.1`, `2.5`, `1.5`).
   - Bare aliases (`gemini`, `gemini-flash`, `gemini-pro`) without version return `""`.
3. Extend `rate_tier(m)`:
   - For `f == "gemini"`:
     - Flash versions (`1.5`, `2.0`, `2.5`, `3.5`, `3.6`, `3.7`, `3.8`): return `"0.15 0.1875 0.30 0.0375 0.60"` (Vertex AI list rates: $0.15 input, $0.1875 5m write, $0.30 1h write, $0.0375 cache read, $0.60 output).
     - Pro versions (`1.5`, `2.5`, `3.1`): return `"1.25 1.5625 2.50 0.3125 5.00"` (Vertex AI list rates: $1.25 input, $1.5625 5m write, $2.50 1h write, $0.3125 cache read, $5.00 output).
     - Any other version returns `""` (reaches `unpriced[model]` and prints warning in `usd()`).
4. Update header comments in `session_spend.sh` documenting Google Cloud Vertex AI effective pricing date.

### Verification
Run `gawk -f <(cat <<'GEOF' ... GEOF')` asserting:
- `rate_tier("gemini-3.8-flash-high") == "0.15 0.1875 0.30 0.0375 0.60"`
- `rate_tier("gemini-3.1-pro-high") == "1.25 1.5625 2.50 0.3125 5.00"`
- `rate_tier("gemini-9.9-flash") == ""`

---

## T2 · Fix pipeline stdin and SIGPIPE in `scripts/ops/session_spend.sh` — D6

Touch: `scripts/ops/session_spend.sh`

### Details
At line 360:
```bash
- }' "$TSV" | tee "$SUMMARY"
+ }' | tee "$SUMMARY"
```
Removing the positional file argument `"$TSV"` allows `awk` to consume the sorted stream piped from `sort -t$'\t' -k12,12 -k1,1 "$TSV"`. This prevents `sort` from receiving SIGPIPE 141 and restores correct chronological ordering for `--ttl-compare`.

### Verification
Run `scripts/ops/session_spend.sh` on a sample transcript under `bash -c 'set -euo pipefail; ...'` and assert exit code 0.

---

## T3 · Antigravity envelope ingestion in `scripts/ops/session_spend.sh` — D5

Touch: `scripts/ops/session_spend.sh`

### Details
In `emit_file()` or companion `emit_envelope()`:
When scanning JSON files (e.g. `*.json` or finding JSON objects in target files), recognize Antigravity dispatch envelopes:
`select(.usage != null and (.conversation_id != null or .status != null))`
Extract fields into the 12-column TSV format:
- `timestamp`: file modification time or current ISO timestamp or envelope date
- `date`: `timestamp[0:10]`
- `session`: `.conversation_id // base`
- `kind`: `main`
- `model`: `.model // "gemini-3.8-flash-high"`
- `input`: `.usage.input_tokens // 0`
- `cache_read`: `.usage.cache_read_tokens // 0`
- `cw_5m`: `0`
- `cw_1h`: `0`
- `cw_total`: `0`
- `output`: `(.usage.output_tokens // 0) + (.usage.thinking_tokens // 0)`
- `stream`: filename

### Verification
Run `session_spend.sh` against a synthetic Antigravity dispatch JSON envelope and verify that the output TSV and summary include the calculated cost and token metrics.

---

## T4 · Antigravity dispatch cost computation in `scripts/ops/work.sh` — D4

Touch: `scripts/ops/work.sh`

### Details
In lines 950–976 of `scripts/ops/work.sh`:
When `launch_harness=antigravity`:
1. Check if `.total_cost_usd` is present in the envelope.
2. If missing, check if `.usage.input_tokens` is present.
3. If `.usage` is present:
   - Extract `inp`, `out`, `cr` from `.usage` (`out` includes `thinking_tokens`).
   - Determine dispatch model: `$model` (from `model_of "$persona"` or `$WORK_MODEL`).
   - Calculate cost using the rates:
     - For flash models: `(inp*0.15 + cr*0.0375 + out*0.60) / 1000000`
     - For pro models: `(inp*1.25 + cr*0.3125 + out*5.00) / 1000000`
   - Format cost to 6 decimal places.
   - Write cost to line 1 and `$model` to line 2 of `$WORK_COST_FILE`.
4. If unpriced or `.usage` is missing, truncate `$WORK_COST_FILE` and echo warning to stderr.

### Verification
Simulate an Antigravity dispatch in `work.sh` with `WORK_COST_FILE` set; assert that the cost file contains non-zero cost on line 1 and the Gemini model name on line 2.

---

## T5 · Test suite additions — D1, D2, D3, D4, D5, D6

Touch: `scripts/ops/tests/session_spend_test.sh`, `scripts/ops/tests/work_test.sh`

### Details
1. In `scripts/ops/tests/session_spend_test.sh`:
   - Add scenario testing Gemini rate calculations (`gemini-3.8-flash-high`, `gemini-3.1-pro`).
   - Add scenario testing unpriced Gemini model behavior and warnings.
   - Add scenario verifying pipeline exit code under `pipefail`.
   - Add scenario testing Antigravity envelope ingestion.
2. In `scripts/ops/tests/work_test.sh`:
   - Add scenario asserting that Antigravity dispatches record calculated USD cost and model to `$WORK_COST_FILE`.

### Verification
Run `bash scripts/ops/tests/session_spend_test.sh` and `bash scripts/ops/tests/work_test.sh`. Both test suites must pass 100%.

---

## T6 · Living spec update in `docs/SPEC.md` — D7

Touch: `docs/SPEC.md`

### Details
Upsert `ops.spend` and `ops.dispatch`:
1. In `ops.spend`: document Gemini model pricing support, Vertex AI rate tiers, and Antigravity envelope ingestion. Cite PR inline.
2. In `ops.dispatch`: document that `antigravity` dispatches calculate USD cost from `.usage` and the resolved dispatch model to populate `$WORK_COST_FILE`. Cite PR inline.

### Verification
Run `bash scripts/ci/spec_check.sh origin/main`.
