# Plan: Athena as the Front Door

**Issue:** #404  
**Spec:** `intent/404-athena-as-the-front-door/spec.md` (Approved, D1-D12, AT-1-AT-8)  
**Author:** daedalus (`evekhm-daedalus-app[bot]`)  
**Target commit:** `2764617be086758524091c1af980c7e14d1b4810` (`origin/main`)  
**Reviewer default:** One reviewer (`atlas`), a second only on request (#265)  

---

## 1. Summary and Scope

This plan operationalizes the Approved specification for Issue #404 (`intent/404-athena-as-the-front-door/spec.md`). It formalizes Athena as the product owner holding both the intake front door and the planning/design gates where specifications become commitments.

The plan carries the spec into file-level implementation steps in dependency order. It adds no design and drops none.

### Persona Boundaries and Grants

| Actor | Stage | Authority / Paths Touched | Role in Issue #404 |
|---|---|---|---|
| **athena** | intake, plan, design | `intent/**`, `README.md`, `INTENT.md` | Authored `intent.md` (PR #429) and approved `spec.md` (PR #432). |
| **daedalus** | build | `intent/**`, `scripts/*/tests/**` | Authors `plan.md`, applies spec amendments (AR-R2-1 to AR-R2-4), and commits failing contract tests in `scripts/ops/tests/athena_front_door_contract_test.sh`. Daedalus never edits production code or persona definitions. |
| **odyssey** | implement | `personas/athena.yaml`, `personas/skills/**`, `scripts/ops/tracker_search.sh`, `scripts/setup/bootstrap_tracker.sh`, `README.md`, `INTENT.md`, `docs/SPEC.md`, compiled targets | Implements the plan at target commit `2764617`, turning contract tests green, syncing compiled agents, updating `docs/SPEC.md`, and passing all CI gates. |
| **atlas** | review | comments only | Reviews pull requests against spec and plan. |
| **argus** | review | comments only | Joins on second round or on `deep-review` grant. |

### Deep Review Grant Assessment

- **Plan PR (Daedalus):** touches `scripts/ops/tests/**`, which is under argus's `assigned_when` paths in `config/execution.yaml`, so DEEP-1 is met and CI resolves both argus and atlas for this PR.
- **Implement PR (Odyssey):** Inherits `deep-review` grant:
  - **DEEP-1 (trust-bearing paths):** Touches `scripts/setup/bootstrap_tracker.sh`.
  - **DEEP-3 (privileged operations):** Label provisioning in tracker bootstrap.
  - **DEEP-7 (compiler blast radius):** Edits `personas/skills/spec-adversary.md` and creates `personas/skills/intake-protocol.md` and `personas/skills/product-coherence.md`, regenerating compiled targets across `.claude/` and `.agents/`.
  - **Action:** Odyssey applies the `deep-review` grant via `scripts/ops/post.sh <pr> --as odyssey --add-label deep-review`.

---

## 2. Order of Work

The work proceeds in strict dependency order across thirteen discrete steps:

### Step 1: Spec Amendments (AR-R2-1 to AR-R2-4)

- **File:** `intent/404-athena-as-the-front-door/spec.md`
- **Exact edit:**
  1. **AR-R2-1 (D3, AT-3):** D3 rationale rewritten to clarify that `authority.paths` is a declaration rendered by the compiler into persona instructions as "Paths this actor's pull requests may touch" for reviewers to verify. AT-3 rewritten to verify that compiled targets `.claude/agents/athena.md` and `.agents/agents/athena/agent.md` carry the bullet listing `intent/**`, `README.md`, and `INTENT.md`. Falsifying input: a compiled target listing `intent/**` alone.
  2. **AR-R2-2 (D10, AT-4, AT-5):** D10 updated to name the regex dialect (`grep -E`) and pattern `^\|[[:space:]]*D[0-9]+[[:space:]]*\|` over `intent/*/spec.md` with case-insensitive filtering. AT-5 updated to state that executing with a non-matching query over the repository prints zero lines.
  3. **AR-R2-3 (D11, AT-6):** D11 updated to note that `duplicate` already exists on the tracker with color `cfd3d7`; label provisioning is create-if-missing and never edits existing labels. AT-6 updated to assert label names only (`duplicate` and `area:*` prefix); colors and descriptions are not asserted.
  4. **AR-R2-4 (D9, AT-7):** Target list item 8 added for `INTENT.md`. D9 and AT-7 updated to specify that `INTENT.md` gains an empty trailing section `## Amendments` appended after the current last section, with no line above it modified.
- **Check that proves it:** Plan PR review confirmation against Argus Round 2 findings.

### Step 2: Update `personas/athena.yaml` (D1, D2, D3)

- **File:** `personas/athena.yaml`
- **Exact edit:**
  - Preserve the first line canonical-source header comment on line 1 unchanged.
  - Replace lines 2 to 50 below the header comment by copying the verbatim YAML block from `intent/404-athena-as-the-front-door/spec.md` under heading `### Target Content: personas/athena.yaml`.
  - Resulting configuration declares:
    - `stage: [intake, plan, design]`
    - `role`: Expanded role contract covering front-door intake, ruling translation, relationship naming, and product coherence.
    - `skills`: Exactly five skills in declared order (`intake-protocol.md`, `product-coherence.md`, `spec-adversary.md`, `trusted-posting.md`, `resume-protocol.md`).
    - `authority.paths`: Expanded to `["intent/**", "README.md", "INTENT.md"]`.
- **Checks that prove it:**
  - **AT-1:** Schema check and compiler roundtrip succeed.
  - **AT-2:** `scripts/ci/sanitize_check.sh` exits 0 with zero findings.
  - **AT-3:** Persona authority paths carry `intent/**`, `README.md`, and `INTENT.md`.
  - **Contract test:** Assertions 1, 2, 3, and 4 in `scripts/ops/tests/athena_front_door_contract_test.sh`.

### Step 3: Create `personas/skills/intake-protocol.md` (D4)

- **File:** `personas/skills/intake-protocol.md`
- **Exact edit:**
  - Create `personas/skills/intake-protocol.md`.
  - Copy verbatim, byte for byte, the markdown block from `intent/404-athena-as-the-front-door/spec.md` under heading `### Target Content: personas/skills/intake-protocol.md`.
  - Contains sections `# Skill: intake-protocol`, `## Protocol` (rules 1 to 7), `## Refusals`, and `## Exit condition`.
- **Checks that prove it:**
  - **AT-1:** Inlined by `scripts/sync_agents.py` into compiled targets without error.
  - **AT-2:** `scripts/ci/sanitize_check.sh` exits 0 (zero home paths, credentials, vendor/model names).
  - **Contract test:** Assertion 5 in `scripts/ops/tests/athena_front_door_contract_test.sh`.

### Step 4: Create `personas/skills/product-coherence.md` (D5)

- **File:** `personas/skills/product-coherence.md`
- **Exact edit:**
  - Create `personas/skills/product-coherence.md`.
  - Copy verbatim, byte for byte, the markdown block from `intent/404-athena-as-the-front-door/spec.md` under heading `### Target Content: personas/skills/product-coherence.md`.
  - Contains sections `# Skill: product-coherence`, `## Protocol` (rules 1 to 6), and `## Exit condition`.
- **Checks that prove it:**
  - **AT-1:** Inlined by `scripts/sync_agents.py` into compiled targets without error.
  - **AT-2:** `scripts/ci/sanitize_check.sh` exits 0 (zero home paths, credentials, vendor/model names).
  - **Contract test:** Assertion 6 in `scripts/ops/tests/athena_front_door_contract_test.sh`.

### Step 5: Append Rules 6 to 8 to `personas/skills/spec-adversary.md` (D6)

- **File:** `personas/skills/spec-adversary.md`
- **Exact edit:**
  - Leave lines 1 to 25 unchanged.
  - After rule 5 ("5. **Contradictions count.** ..."), append verbatim the three rules from `intent/404-athena-as-the-front-door/spec.md` under heading `### Protocol Additions: personas/skills/spec-adversary.md`:
    - `6. **Every acceptance row can fail.** ...`
    - `7. **Neighbours first.** ...`
    - `8. **One pass for self-contradiction.** ...`
  - Leave all subsequent sections (`## Exit condition`, `## Downstream contract`) untouched.
- **Checks that prove it:**
  - **AT-1:** Compiled targets contain rules 6 to 8 of `spec-adversary.md`.
  - **AT-2:** `scripts/ci/sanitize_check.sh` exits 0.
  - **Contract test:** Assertion 7 in `scripts/ops/tests/athena_front_door_contract_test.sh`.

### Step 6: Append Trailing `## Amendments` Section to `INTENT.md` (D8, D9)

- **File:** `INTENT.md`
- **Exact edit:**
  - Append an empty trailing section `## Amendments` at the end of `INTENT.md`.
  - Leave every line above the appended section untouched.
- **Checks that prove it:**
  - **AT-7:** The last heading in `INTENT.md` is `## Amendments`, and `git diff origin/main...HEAD INTENT.md` adds lines only after the previous end of file.
  - **Contract test:** Assertion 9 in `scripts/ops/tests/athena_front_door_contract_test.sh`.

### Step 7: Add `--decisions` Option to `scripts/ops/tracker_search.sh` (D10)

- **File:** `scripts/ops/tracker_search.sh`
- **Exact edit:**
  - Add option parsing for `--decisions` to accept query terms.
  - When `--decisions` is invoked:
    - Search all `intent/*/spec.md` files for decision rows matching extended regular expression pattern `^\|[[:space:]]*D[0-9]+[[:space:]]*\|` (where `\|` is a literal pipe).
    - Filter matched rows case-insensitively by the query terms using `grep -E -n -i`.
    - Output matching rows formatted as `<file>:<line>: <matching row>`.
    - If one or more matching rows are found, set `found=1`, print refusal notice to stderr, and exit with status 2.
    - If zero matching rows are found, print zero lines and exit with status 0.
    - Support running `--decisions` standalone without `--files` and without requiring `gh` or `jq`.
- **Checks that prove it:**
  - **AT-4:** `scripts/ops/tracker_search.sh --decisions FRONTIER` outputs matching lines in `<file>:<line>: <row>` format and exits 2.
  - **AT-5:** `scripts/ops/tracker_search.sh --decisions nonexistenttermxyz123` prints zero lines and exits 0.
  - **Contract test:** Assertions 10 and 11 in `scripts/ops/tests/athena_front_door_contract_test.sh`.

### Step 8: Provision `duplicate` and `area:*` Labels in `scripts/setup/bootstrap_tracker.sh` (D11)

- **File:** `scripts/setup/bootstrap_tracker.sh`
- **Exact edit:**
  - Colors and descriptions below are illustrative; the implementer chooses them per D11, and provisioning is create-if-missing through the existing `ensure_label` helper.
  - Add label provisioning calls using existing `ensure_label` helper:
    - `ensure_label "duplicate" "CFD3D7" "Duplicate: closed as duplicate of an existing issue or thread"`
    - `ensure_label "area:personas" "C5DEF5" "Issues and changes touching personas and agent definitions"`
    - `ensure_label "area:ci" "C5DEF5" "Issues and changes touching CI workflows and merge gates"`
    - `ensure_label "area:ops" "C5DEF5" "Issues and changes touching operational scripts and tooling"`
    - `ensure_label "area:docs" "C5DEF5" "Issues and changes touching documentation and specifications"`
    - `ensure_label "area:harness" "C5DEF5" "Issues and changes touching execution harnesses and runtime"`
  - Provisioning is create-if-missing and never edits an existing label.
- **Checks that prove it:**
  - **AT-6:** Running `scripts/setup/bootstrap_tracker.sh --labels-only` verifies that label names `duplicate` and each `area:*` name are present.
  - **Contract test:** Assertion 12 in `scripts/ops/tests/athena_front_door_contract_test.sh`.

### Step 9: Document Interactive Athena Entry Points in `README.md` (D12)

- **File:** `README.md`
- **Exact edit:**
  - Under the section "Running it yourself", add one sentence naming how to start an intent conversation with Athena interactively across supported harnesses: `claude --agent athena` for Claude Code and the compiled `.agents/agents/athena` configuration for Antigravity.
  - Implementation status, run books and model pins stay out of README.md.
- **Checks that prove it:**
  - **AT-8:** `README.md` contains entry point references for `claude --agent athena` and `.agents/agents/athena`.
  - **Contract test:** Assertion 13 in `scripts/ops/tests/athena_front_door_contract_test.sh`.

### Step 10: Regenerate Compiled Targets via `scripts/sync_agents.py` (D7)

- **Files:**
  - `.claude/agents/athena.md`
  - `.agents/agents/athena/agent.md`
  - `.agents/agents/athena/agent.json`
- **Exact edit:**
  - Execute `python3 scripts/sync_agents.py` to recompile persona targets.
  - No compiler script modifications are required: `sync_agents.py` accepts `intake` in Athena's stage list and renders it under "Lifecycle stages owned" without lifecycle ladder entries.
  - Inlines the new skills (`intake-protocol.md`, `product-coherence.md`, updated `spec-adversary.md`).
  - Updates the authority path bullet to: `Paths this actor's pull requests may touch: `intent/**`, `README.md`, `INTENT.md``.
- **Checks that prove it:**
  - **AT-1:** `python3 scripts/sync_agents.py --check` exits 0 (drift gate green).
  - **AT-3:** Compiled agent instructions carry the expanded authority path bullet listing `intent/**`, `README.md`, and `INTENT.md`.
  - **Contract test:** Assertion 8 in `scripts/ops/tests/athena_front_door_contract_test.sh`.

### Step 11: Wire the Contract Suite into CI (AT-1 to AT-8 (execution of the suite))

- **File:** `.github/workflows/ci-gates.yml`
- **Exact edit:**
  - Add `bash scripts/ops/tests/athena_front_door_contract_test.sh` to the same step block that runs `scripts/ops/tests/review_split_contract_test.sh`, so both suites execute on every PR.
  - GitHub blocks App identities from pushing workflow files, so this one hunk is pushed with the repository bot credential; commit authorship stays the implementer's.
- **Checks that prove it:**
  - **AT-1 to AT-8:** CI runs `athena_front_door_contract_test.sh` on every PR and reports its pass/fail count in the job log.

### Step 12: Living Spec Upsert in `docs/SPEC.md` (Standing obligation from AGENTS.md "The living spec", enforced by scripts/ci/spec_check.sh; it serves no D-row of #404.)

- **File:** `docs/SPEC.md`
- **Exact edit:**
  - Update `docs/SPEC.md` to reflect the operational state introduced by #404:
    - Update `lifecycle.labels` subsection to document `duplicate` and the five `area:*` labels.
    - Update Athena entry in persona taxonomy to reflect stage list `[intake, plan, design]`, expanded role, and expanded path authority.
    - Document `tracker_search.sh --decisions` in `ops.dispatch` tooling reference.
- **Checks that prove it:**
  - `bash scripts/ci/spec_check.sh origin/main <pr_body_file>` passes with valid spec citation.

### Step 13: Model-Free Verification and Test Plan

Odyssey executes the complete suite of deterministic, model-free verification checks before opening the implementation PR:

1. **Sanitize Gate:**
   ```bash
   bash scripts/ci/sanitize_check.sh
   ```
   Asserts exit code 0 and zero findings across tracked files. (AT-2)

2. **Compiler Drift Gate:**
   ```bash
   python3 scripts/sync_agents.py --check
   ```
   Asserts exit code 0; all 33 compiled targets match persona sources and configuration. (AT-1)

3. **Compiler Roundtrip Suite:**
   ```bash
   bash scripts/ci/compiler_roundtrip.sh
   ```
   Asserts exit code 0 across all 7 roundtrip checks. (AT-1, D7)

4. **Execution Config Gate:**
   ```bash
   python3 scripts/ops/execution.py --check
   ```
   Asserts exit code 0; execution bindings remain valid.

5. **Tracker Search Decision Matching Check:**
   ```bash
   bash scripts/ops/tracker_search.sh --decisions FRONTIER
   ```
   Asserts exit code 2 and formatted `<file>:<line>: <row>` output. (AT-4)

6. **Tracker Search Decision Non-Matching Check:**
   ```bash
   bash scripts/ops/tracker_search.sh --decisions nonexistenttermxyz123
   ```
   Asserts exit code 0 and zero output lines. (AT-5)

7. **Bootstrap Tracker Labels Check:**
   ```bash
   bash scripts/setup/bootstrap_tracker.sh --labels-only
   ```
   Asserts exit code 0 and presence of `duplicate` and all `area:*` labels. (AT-6)

8. **Compiled Authority Path Check:**
   ```bash
   # Both compiled targets contain the authority bullet (accounting for compiler line-wrapping)
   python3 -c "
   import sys
   expected = \"Paths this actor's pull requests may touch: `intent/**`, `README.md`, `INTENT.md`\"
   for p in ['.claude/agents/athena.md', '.agents/agents/athena/agent.md']:
       with open(p) as f:
           text = ' '.join(f.read().split())
       if ' '.join(expected.split()) not in text:
           sys.exit(1)
   sys.exit(0)
   "
   ```
   Asserts presence in both compiled agent markdown files. (AT-3)

9. **INTENT.md Heading and Append Check:**
   ```bash
   [ "$(grep -E '^## ' INTENT.md | tail -1)" = "## Amendments" ]
   git diff origin/main...HEAD INTENT.md
   ```
   Asserts last heading is `## Amendments` and diff adds lines only after previous EOF. (AT-7)

10. **README Entry Point Check:**
    ```bash
    grep -q "claude --agent athena" README.md
    grep -q "\.agents/agents/athena" README.md
    ```
    Asserts presence of entry point text. (AT-8)

11. **Contract Test Suite:**
    ```bash
    bash scripts/ops/tests/athena_front_door_contract_test.sh
    ```
    Asserts exit code 0, 13 passed assertions, 0 failures.

12. **Prose Quality Gate:**
    ```bash
    # No em dashes in added lines across the touched surface
    git diff origin/main...HEAD -- personas/ README.md INTENT.md | grep -P '^\+' | grep -Pc '\x{2014}'
    # Prohibited phrase in added lines, excluding the quoted token in product-coherence rule 6
    git diff origin/main...HEAD -- personas/ README.md INTENT.md | grep -P '^\+' | grep -v '"rather than"' | grep -Pic 'rather than'
    # Whole-file pass on the two new skill files only
    grep -Pc '\x{2014}' personas/skills/intake-protocol.md personas/skills/product-coherence.md
    # No vendor or model names in personas/**
    ! grep -Pin '(claude|anthropic|openai|gpt|gemini|antigravity)' personas/athena.yaml personas/skills/intake-protocol.md personas/skills/product-coherence.md
    ```
    Asserts all counts are zero. Pre-existing counts in INTENT.md, personas/athena.yaml line 1 and the untouched skill files are out of scope; D1, D6 and D9 forbid editing those lines.

---

## 3. Traceability Matrix

| Decision ID | Acceptance Test | Implementation Task | Verification Proof |
|---|---|---|---|
| **D1** | AT-1, AT-2 | Step 2 (`personas/athena.yaml`) | `sync_agents.py --check`, `sanitize_check.sh`, Contract Assertions 1 & 2 |
| **D2** | AT-1 | Step 2 (`personas/athena.yaml`) | `sync_agents.py --check`, Contract Assertion 3 |
| **D3** | AT-3 | Step 2, Step 10 (`athena.yaml`, compiled targets) | Compiled authority bullet check, Contract Assertions 4 & 8 |
| **D4** | AT-1, AT-2 | Step 3 (`personas/skills/intake-protocol.md`) | `sync_agents.py --check`, `sanitize_check.sh`, Contract Assertion 5 |
| **D5** | AT-1, AT-2 | Step 4 (`personas/skills/product-coherence.md`) | `sync_agents.py --check`, `sanitize_check.sh`, Contract Assertion 6 |
| **D6** | AT-1, AT-2 | Step 5 (`personas/skills/spec-adversary.md`) | `sync_agents.py --check`, `sanitize_check.sh`, Contract Assertion 7 |
| **D7** | AT-1, AT-3 | Step 10 (compiled targets) | `sync_agents.py --check`, `compiler_roundtrip.sh`, Contract Assertion 8 |
| **D8** | AT-7 | Step 6 (`INTENT.md`) | Review and operator merge gate |
| **D9** | AT-7 | Step 6 (`INTENT.md`) | `git diff` append-only check, Contract Assertion 9 |
| **D10** | AT-4, AT-5 | Step 7 (`scripts/ops/tracker_search.sh`) | `tracker_search.sh --decisions` matching/non-matching checks, Contract Assertions 10 & 11 |
| **D11** | AT-6 | Step 8 (`scripts/setup/bootstrap_tracker.sh`) | `bootstrap_tracker.sh --labels-only`, Contract Assertion 12 |
| **D12** | AT-8 | Step 9 (`README.md`) | `grep` check in `README.md`, Contract Assertion 13 |
| N/A | AT-1 to AT-8 | Step 11 (`.github/workflows/ci-gates.yml`) | CI job log shows `athena_front_door_contract_test.sh` executed on every PR |
