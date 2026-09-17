# Plan: Price Gemini Flash and Pro at Pinned 3.x Versions in session_spend and work.sh

**Issue:** #269 · **Spec:** `intent/269-session-spend-sh-prices-gemini-flash/spec.md` (Approved, PR #519, D1–D7, AT-269-1–AT-269-12)  
**Author:** daedalus (`evekhm-daedalus-app[bot]`)  
**Base commit:** `c4fc19f4fb23020ac08fee952f6b8c2ea878285d` (`origin/main`, merge of PR #522)  
**Target branch for implementation (Odyssey):** `odyssey/269-session-spend-sh-prices-gemini-flash`

---

## 1. Executive Summary and Problem Statement

`scripts/ops/session_spend.sh` and `scripts/ops/work.sh` currently price all Gemini Flash models (1.5 through 3.8) at $0.15 base input, $0.1875 5-minute cache write, $0.30 1-hour cache write, $0.0375 cache read, and $0.60 output per million tokens (Decision #150 D2). All Gemini Pro models (1.5 through 3.1) are priced at $1.25 base input, $1.5625 5-minute cache write, $2.50 1-hour cache write, $0.3125 cache read, and $5.00 output per million tokens (#150 D2).

These rates reflect Gemini 1.5 legacy pricing. The repository pinned all Antigravity tiers to `gemini-3.8-flash-{low,medium,high}` in PR #271. In `README.md` Section 5 (PR #263, amended in PR #274 per #35 D3), Google Cloud Gemini Enterprise platform pricing is documented as:
- **Gemini 3.8 Flash:** $0.75 base input, $0.00 cache write, $0.075 cache read, and $3.75 output per million tokens.
- **Gemini 3.1 Pro:** $2.00 base input, $0.00 cache write, $0.20 cache read, and $12.00 output per million tokens.

Under legacy pricing:
1. `scripts/ops/session_spend.sh` under-reports Antigravity session spend by approximately 5x on input and 6.25x on output.
2. `scripts/ops/work.sh:1307-1329` computes Antigravity dispatch costs against legacy rates when writing to `$WORK_COST_FILE`, enabling runs to bypass configured `WORK_MAX_USD` (#108) ceilings.

This plan details the implementation to:
1. Update `rate_tier()` in `scripts/ops/session_spend.sh` for modern Flash (`3.5`, `3.6`, `3.7`, `3.8`) to `"0.75 0 0 0.075 3.75"` and modern Pro (`3.1`) to `"2.00 0 0 0.20 12.00"`, while preserving legacy rates for 1.5 and 2.x versions (D1, D2).
2. Synchronize the inline `awk` snippet in `scripts/ops/work.sh` to match `session_spend.sh` (D3).
3. Keep static model string lookups without turn timestamp branching (D4).
4. Preserve fail-closed handling for unpriced or unrecognized Gemini versions (D5).
5. Align test suites in `scripts/ops/tests/session_spend_test.sh` and `scripts/ops/tests/work_test.sh` (D6).
6. Update living specification in `docs/SPEC.md` under `ops.spend` (D7).

---

## 2. Scope, Persona Boundaries, and Grants

### Persona Authority Boundaries

| Actor | Stage | Authority / Paths Touched | Role in Issue #269 |
|---|---|---|---|
| **athena** | intake, plan, design | `intent/**` | Authored `intent.md` and approved `spec.md` (merged in PR #519). |
| **daedalus** | build | `intent/**`, `scripts/*/tests/**` | Authors `plan.md` and commits contract test suite `scripts/ops/tests/session_spend_gemini_pricing_contract_test.sh`. Daedalus **never** edits production code. |
| **odyssey** | implement | `scripts/ops/session_spend.sh`, `scripts/ops/work.sh`, `scripts/ops/tests/session_spend_test.sh`, `scripts/ops/tests/work_test.sh`, `docs/SPEC.md` | Executes Tasks T1 through T7 branching from the commit merging this plan, turns contract tests green, updates living spec, and verifies all CI gates. |
| **themis** | autonomous merge | GitHub Actions (`merge-gate.yml`) | Autonomously gates and merges pull requests upon consensus. |
| **argus / atlas** | review | comments only | Review pull requests against spec and plan. |

### Deep Review Grant Assessment (DEEP-1..DEEP-7)

- **Build PR (Daedalus):**
  - **DEEP-1 (trust-bearing paths):** Touches `scripts/ops/tests/session_spend_gemini_pricing_contract_test.sh`, which falls under `config/execution.yaml` `assigned_when.paths` (`scripts/ops/**`). Argus is assigned by CI and round-scope cap is lifted.
- **Implementation PR (Odyssey):**
  - **DEEP-1 (trust-bearing paths):** Touches `scripts/ops/session_spend.sh` and `scripts/ops/work.sh` (under `scripts/ops/**`).
  - **DEEP-3 / DEEP-5:** Rate calculation does not touch credentials, GitHub writes, or concurrency state machines; full regression test suites exist for both touched files. `risk: high` is not required.
  - **Action:** Odyssey applies the `deep-review` grant when opening the PR per `scripts/ops/post.sh <pr> --as odyssey --add-label deep-review`.

### Living Spec and Changelog Obligations

- **Build PR (Daedalus):**
  - `Spec-impact: none — build stage contract tests and plan only; living spec upsert is task of implementation PR`
  - `Changelog: none — build stage contract tests and plan only; changelog entry is task of implementation PR`
- **Implementation PR (Odyssey):**
  - Updates `docs/SPEC.md` under `### ops.spend` documenting updated Gemini 3.x rates effective 2026-09-08 per #269 (D7, AT-269-12).
  - Updates `CHANGELOG.md` under the current release / unreleased section documenting the pricing correction.

### Strict File Manifest Partitioning

The implementing change is strictly confined to:
1. `scripts/ops/session_spend.sh`
2. `scripts/ops/work.sh`
3. `scripts/ops/tests/session_spend_test.sh`
4. `scripts/ops/tests/work_test.sh`
5. `docs/SPEC.md`
6. `CHANGELOG.md`
7. `intent/269-session-spend-sh-prices-gemini-flash/plan.md` (read-only reference; updated only if plan sync occurs)

**Forbidden Paths (Untouched):**
- `personas/**`
- `config/model_tiers.yaml`
- `config/deployments.yaml`
- `scripts/ci/**`
- `.github/workflows/**`

---

## 3. Order of Work

```
T1 (session_spend.sh rate_tier) 
  → T2 (work.sh rate_tier sync)
  → T3 (session_spend_test.sh updates)
  → T4 (work_test.sh updates)
  → T5 (Contract test suite verification)
  → T6 (docs/SPEC.md living spec update)
  → T7 (Full regression verification & CI gate checks)
```

---

## 4. Micro-Stepped Tasks

### T1 · Update `rate_tier()` in `scripts/ops/session_spend.sh` — D1, D2, D4, D5
- **Files touched:** `scripts/ops/session_spend.sh`
- **Decisions satisfied:** D1, D2, D4, D5
- **Acceptance criteria satisfied:** AT-269-1, AT-269-2, AT-269-3, AT-269-4, AT-269-5, AT-269-6, AT-269-7, AT-269-11
- **Details:**
  1. In `scripts/ops/session_spend.sh:250-262`, update `rate_tier(m)` for `f == "gemini"`:
     - For Flash versions:
       - Match modern versions: `if (v == "3.5" || v == "3.6" || v == "3.7" || v == "3.8")` return `"0.75 0 0 0.075 3.75"` ($0.75 base input, $0 cw_5m, $0 cw_1h, $0.075 cache read, $3.75 output per MTok).
       - Match legacy versions: `if (v == "1.5" || v == "2.0" || v == "2.5")` return `"0.15 0.1875 0.30 0.0375 0.60"`.
       - All other versions return `""`.
     - For Pro versions:
       - Match modern version: `if (v == "3.1")` return `"2.00 0 0 0.20 12.00"` ($2.00 base input, $0 cw_5m, $0 cw_1h, $0.20 cache read, $12.00 output per MTok).
       - Match legacy versions: `if (v == "1.5" || v == "2.5")` return `"1.25 1.5625 2.50 0.3125 5.00"`.
       - All other versions return `""`.
  2. Update header comments in `session_spend.sh:7-8, 18-20` citing Google Cloud Gemini Enterprise platform pricing effective 2026-09-08 per #269.
- **Verification:**
  - `awk -f <(awk '/function model_family\(m\)/,/function usd\(model,/ { if ($0 !~ /function usd\(model,/) print }' scripts/ops/session_spend.sh) -e 'BEGIN { print rate_tier("gemini-3.8-flash-high"); exit 0 }'` returns `0.75 0 0 0.075 3.75`.
  - `awk -f <(awk '/function model_family\(m\)/,/function usd\(model,/ { if ($0 !~ /function usd\(model,/) print }' scripts/ops/session_spend.sh) -e 'BEGIN { print rate_tier("gemini-3.1-pro-low-thinking"); exit 0 }'` returns `2.00 0 0 0.20 12.00`.
  - `awk -f <(awk '/function model_family\(m\)/,/function usd\(model,/ { if ($0 !~ /function usd\(model,/) print }' scripts/ops/session_spend.sh) -e 'BEGIN { print rate_tier("gemini-1.5-flash"); exit 0 }'` returns `0.15 0.1875 0.30 0.0375 0.60`.

---

### T2 · Synchronize `rate_tier()` in `scripts/ops/work.sh` — D1, D2, D3, D4, D5
- **Files touched:** `scripts/ops/work.sh`
- **Decisions satisfied:** D1, D2, D3, D4, D5
- **Acceptance criteria satisfied:** AT-269-8, AT-269-9, AT-269-10, AT-269-11
- **Details:**
  1. In `scripts/ops/work.sh:1307-1323`, update the inline awk `rate_tier(m)` definition to mirror `session_spend.sh`:
     ```awk
     function rate_tier(m,   f, v) {
       f = model_family(m)
       if (f != "gemini") return ""
       v = model_version(m)
       if (m ~ /flash/) {
         if (v == "3.5" || v == "3.6" || v == "3.7" || v == "3.8")
           return "0.75 0 0 0.075 3.75"
         if (v == "1.5" || v == "2.0" || v == "2.5")
           return "0.15 0.1875 0.30 0.0375 0.60"
         return ""
       }
       if (m ~ /pro/) {
         if (v == "3.1")
           return "2.00 0 0 0.20 12.00"
         if (v == "1.5" || v == "2.5")
           return "1.25 1.5625 2.50 0.3125 5.00"
         return ""
       }
       return ""
     }
     ```
- **Verification:**
  - `awk -f <(awk '/function model_family\(m\)/,/BEGIN \{/ { if ($0 !~ /BEGIN \{/) print }' scripts/ops/work.sh) -e 'BEGIN { print rate_tier("gemini-3.8-flash-high"); exit 0 }'` returns `0.75 0 0 0.075 3.75`.
  - `awk -f <(awk '/function model_family\(m\)/,/BEGIN \{/ { if ($0 !~ /BEGIN \{/) print }' scripts/ops/work.sh) -e 'BEGIN { print rate_tier("gemini-1.5-pro-002"); exit 0 }'` returns `1.25 1.5625 2.50 0.3125 5.00`.

---

### T3 · Update Test Expectations in `scripts/ops/tests/session_spend_test.sh` — D6
- **Files touched:** `scripts/ops/tests/session_spend_test.sh`
- **Decisions satisfied:** D6
- **Acceptance criteria satisfied:** AT-269-2, AT-269-3, AT-269-4, AT-269-5, AT-269-6, AT-269-7, AT-269-11
- **Details:**
  1. In section 10 (`# 10. Gemini models`):
     - Update `gemini-3.8-flash-high` expectation: 1M input ($0.75) + 1M output ($3.75) + 1M cache read ($0.075) = $4.575 -> rounded `$4.58` (line 330).
     - Update `gemini-3.8-flash-medium` expectation: 1M input = `$0.75` (line 331).
     - Preserve `gemini-1.5-flash` expectation: 1M input = `$0.15` (line 332).
     - Update `gemini-3.1-pro-low-thinking` expectation: 1M input ($2.00) + 1M output ($12.00) + 1M cache read ($0.20) = `$14.20` (line 333).
     - Preserve `gemini-1.5-pro` expectation: 1M input = `$1.25` (line 334).
  2. In section 11 (`# 11. Antigravity dispatch envelopes`):
     - Envelope with 1M input, 500k output, 500k thinking tokens (total output 1M) on `gemini-3.8-flash-high`: 1M * 0.75 + 1M * 3.75 = `$4.50`. Update expectation at line 349 from `0.75` to `4.50`.
- **Verification:**
  - Run `bash scripts/ops/tests/session_spend_test.sh` asserting all scenarios pass (exit code 0).

---

### T4 · Update Test Expectations in `scripts/ops/tests/work_test.sh` — D6
- **Files touched:** `scripts/ops/tests/work_test.sh`
- **Decisions satisfied:** D6
- **Acceptance criteria satisfied:** AT-269-9, AT-269-10
- **Details:**
  1. In banner `#150 Antigravity dispatch writes cost and model to WORK_COST_FILE`:
     - Update token rate comments to reflect Flash 3.8 rates:
       - Input: $0.75, cache read: $0.075, output: $3.75.
       - Token counts: 100,000 input, 20,000 cache read, 15,000 output+thinking (10,000 + 5,000).
       - Cost calculation: `(100000 * 0.75 + 20000 * 0.075 + 15000 * 3.75) / 1000000 = (75000 + 1500 + 56250) / 1000000 = 132750 / 1000000 = 0.132750`.
     - Update line 1165 assertion from `0.024750` to `0.132750`.
  2. Add legacy Pro envelope scenario testing `gemini-1.5-pro-002`:
     - Dispatch with 1M input tokens on model `gemini-1.5-pro-002` computes `1.250000` to line 1 of `$WORK_COST_FILE` (AT-269-10).
- **Verification:**
  - Run `bash scripts/ops/tests/work_test.sh` asserting all scenarios pass (exit code 0).

---

### T5 · Verify Contract Test Suite `session_spend_gemini_pricing_contract_test.sh` — D1–D7
- **Files touched:** none (verification only)
- **Decisions satisfied:** D1, D2, D3, D4, D5, D6, D7
- **Acceptance criteria satisfied:** AT-269-1 through AT-269-12
- **Details:**
  - Run `bash scripts/ops/tests/session_spend_gemini_pricing_contract_test.sh`.
  - Assert that all 12 contract assertions pass cleanly (100% green, exit code 0).
- **Verification:**
  - `bash scripts/ops/tests/session_spend_gemini_pricing_contract_test.sh` prints:
    ```
    === Contract Test Summary ===
    Total assertions: 12
    Passed:           12
    Failed:           0
    ALL TESTS PASSED
    ```

---

### T6 · Update Living Specification in `docs/SPEC.md` — D7
- **Files touched:** `docs/SPEC.md`
- **Decisions satisfied:** D7
- **Acceptance criteria satisfied:** AT-269-12
- **Details:**
  1. In `docs/SPEC.md` under `### ops.spend`:
     - Update the rate documentation to record that Gemini 3.x models are priced at updated rates effective 2026-09-08 per #269:
       - Gemini 3.8 Flash: $0.75 base input, $0.00 cache write, $0.075 cache read, $3.75 output per MTok.
       - Gemini 3.1 Pro: $2.00 base input, $0.00 cache write, $0.20 cache read, $12.00 output per MTok.
       - Automatic cache write accounting: cache write fees are $0.00.
       - Legacy 1.5/2.x rates are preserved for historical transcripts.
     - Cite PR inline per living-spec conventions.
  2. Run `scripts/ci/spec_check.sh origin/main`.
- **Verification:**
  - `bash scripts/ci/spec_check.sh origin/main` exits 0.

---

### T7 · Full Regression Verification and CI Gate Checks
- **Files touched:** `CHANGELOG.md`
- **Details:**
  1. Add entry in `CHANGELOG.md` under unreleased section noting the pricing correction for Gemini Flash 3.x and Pro 3.1.
  2. Run the repository CI check suite:
     - `bash scripts/ops/tests/session_spend_test.sh`
     - `bash scripts/ops/tests/work_test.sh`
     - `bash scripts/ops/tests/session_spend_gemini_pricing_contract_test.sh`
     - `python3 scripts/sync_agents.py --check`
     - `bash scripts/ci/compiler_roundtrip.sh`
     - `bash scripts/ci/sanitize_check.sh`
     - `python3 scripts/ops/execution.py --check`
     - `bash scripts/ci/changelog_check.sh origin/main`
     - `bash scripts/ci/spec_check.sh origin/main`
- **Verification:**
  - All test suites and gate checks exit with status 0.
