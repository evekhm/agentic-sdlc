# Plan: Commands Single Source of Truth and Cross-Harness Compiler with Drift Gate

**Issue:** #416 · **Spec:** `intent/416-commands-work-idea-bug/spec.md` (Approved, PR #422, D1–D14, AT-416-1–AT-416-13)  
**Author:** daedalus (`evekhm-daedalus-app[bot]`)  
**Base commit:** `1103cd0da0b6b331ac7fd6816a099999a75d49af` (`origin/main`, merge of spec PR #422)  
**Target branch for implementation (Odyssey):** `odyssey/416-commands-work-idea-bug`

---

## 1. Executive Summary and Problem Statement

Slash commands in this repository (`/work`, `/idea`, `/bug`, and `/wrap`) were originally hand-authored as bespoke markdown files directly within `.claude/commands/`. While personas have long enjoyed canonical YAML authoring under `personas/`, multi-harness compilation to `.claude/agents/` and `.agents/agents/` via `scripts/sync_agents.py`, and CI roundtrip drift protection, slash commands remained:
1. **Harness-Asymmetric:** Existing commands were Claude Code only. Google Antigravity (`agy`) users and agents had no access to `/work`, `/idea`, or `/bug`, despite `agy 1.2.0` natively discovering workspace skills at `.agents/skills/<name>/SKILL.md`. Issue #43 D16 previously deferred cross-harness command generation because Claude's pre-turn `!` execution was operator-typed rather than model-composed; with #416 introducing the compiler infrastructure, #43 D16 is explicitly amended under a hardened trust model (D5).
2. **Without a Canonical Source:** Target files in `.claude/commands/` served as their own sources without frontmatter linting, schema validation, or secret scanning.
3. **Without Continuous Drift Enforcement:** Modifications, deletions, or harness desynchronizations were undetected by continuous integration.

### Scope and Landed Prerequisite Resolution

Issue #416 establishes a single source of truth for repository slash commands under `commands/<name>.md`, introduces a deterministic multi-target compiler `scripts/sync_commands.py`, generates pristine byte-identical Claude Code targets (`.claude/commands/`) and hardened native Antigravity skills (`.agents/skills/`), adds Step 9 ("Commands compiler roundtrip and drift gate") to `scripts/ci/compiler_roundtrip.sh`, and adds `commands/*` to behavior-bearing paths in `scripts/ci/spec_check.sh`.

- **Prerequisite Defect Resolution (PR #425 / D14):** In the unpatched repository on `main`, `.claude/commands/bug.md` contained an unquoted colon scalar in `argument-hint:`, which failed standard YAML parsers. PR #425 has landed on `origin/main` (commit `5134e95`), quoting `argument-hint` in single quotes. Consequently, all three commands (`work.md`, `idea.md`, and `bug.md`) are valid YAML and are ready for canonical migration in this issue.
- **Decoupling with Issue #85 / PR #406 (`wrap.md` / D12, D14):** `/wrap` is owned by Issue #85 (`intent/85-session-close-out/`, PR #406). PR #406 merged `wrap.md` to `main`, and PR #425 quoted its `argument-hint`. Per D12 and D14, #416 does **not** migrate `commands/wrap.md`; `.claude/commands/wrap.md` remains in `sync_commands.py`'s explicit allowlist and is exempt from drift and pruning until Issue #85 performs its canonical migration.

---

## 2. Scope, Persona Boundaries, and Grants

### Persona Authority Boundaries

| Actor | Stage | Authority / Paths Touched | Role in Issue #416 |
|---|---|---|---|
| **athena** | intake, plan, design | `intent/**` | Authored `intent.md` and approved `spec.md` (merged in PR #422). |
| **daedalus** | build | `intent/**`, `scripts/*/tests/**` | Authors `plan.md` and commits contract test suite `scripts/ci/tests/sync_commands_test.py`. Daedalus **never** writes production code, targets, or compiler scripts. |
| **odyssey** | implement | `commands/**`, `scripts/sync_commands.py`, `.claude/commands/**`, `.agents/skills/**`, `scripts/ci/compiler_roundtrip.sh`, `scripts/ci/spec_check.sh`, `docs/SPEC.md`, `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, `intent/43-harness-agnostic-launch/spec.md` | Implements canonical sources, compiler script, targets, CI gate extensions, documentation, and turns all contract tests green. |
| **themis** | autonomous merge | GitHub Actions (`merge-gate.yml`) | Merges pull requests when consensus is reached. |
| **argus / atlas** | review | comments only | Reviews PRs against spec, plan, and security criteria. |

### Deep Review Grant Assessment (DEEP-1, DEEP-5, DEEP-7)

- **Build PR (Daedalus):**
  - **DEEP-1 (trust-bearing paths):** Touches `scripts/ci/tests/sync_commands_test.py`, falling under `config/execution.yaml` `assigned_when.paths` for Argus (`scripts/ci/**`).
  - **Action:** Daedalus applies `deep-review` label via `scripts/ops/post.sh <pr> --as daedalus --add-label deep-review`.
- **Implementation PR (Odyssey):**
  - **DEEP-1 (trust-bearing paths):** Touches `scripts/sync_commands.py`, `scripts/ci/compiler_roundtrip.sh`, and `scripts/ci/spec_check.sh`.
  - **DEEP-5 (escalated tier / task risk):** Tasks T3 and T6 are marked `risk: high` and `risk: medium` (touches compiler plumbing and core CI roundtrip gates).
  - **DEEP-7 (compiler blast radius):** Introducing `scripts/sync_commands.py` touches multi-harness compiled targets across `.claude/commands/` and `.agents/skills/`.
  - **Action:** Odyssey applies the `deep-review` grant when opening the PR per `scripts/ops/post.sh <pr> --as odyssey --add-label deep-review`.

### Living Spec Obligation (D11, D13)

- The implementation PR introduces cross-harness slash command compilation and target generation, which is a behavioral addition to the repository.
- Odyssey updates `docs/SPEC.md` under `### commands.compiler` (D11, D13).
- Daedalus build PR body carries:
  `Spec-impact: none — build stage contract tests and plan only`

### Strict File Manifest Partitioning (D13)

The implementing pull request is strictly confined to:
- `commands/work.md`
- `commands/idea.md`
- `commands/bug.md`
- `scripts/sync_commands.py`
- `.claude/commands/work.md`
- `.claude/commands/idea.md`
- `.claude/commands/bug.md`
- `.agents/skills/work/SKILL.md`
- `.agents/skills/idea/SKILL.md`
- `.agents/skills/bug/SKILL.md`
- `scripts/ci/compiler_roundtrip.sh`
- `scripts/ci/spec_check.sh`
- `docs/SPEC.md`
- `AGENTS.md`
- `CLAUDE.md`
- `GEMINI.md`
- `intent/43-harness-agnostic-launch/spec.md`
- `intent/416-commands-work-idea-bug/**`

**Changelog Handling (D13, R2-2):**
`CHANGELOG.md` is excluded from the implementing PR manifest per Decision D13 (which was approved against a base prior to #410 landing). To satisfy the changelog merge gate (`scripts/ci/changelog_check.sh`), the implementing pull request body carries the bypass marker:
`Changelog: none — commands compiler infrastructure, targets, and documentation (CHANGELOG.md excluded by D13 manifest)`

**Standing CI Gates (R1-5, R2-1):**
`scripts/ci/compiler_roundtrip.sh` Step 9 serves as the standing CI gate for the slash commands compiler, determinism, target parity, and drift detection, wired permanently into `.github/workflows/ci-gates.yml` under the `drift` job. Step 9 also executes `scripts/ci/tests/sync_commands_test.py`, ensuring continuous regression testing of all contract assertions on every commit without modifying GitHub Actions workflows. The step and suite operate ref-free (`test_d2` gates `origin/main` queries on ref availability and falls back to committed targets when the remote ref is absent, supporting shallow CI checkouts).

**Forbidden Paths (Untouched per D13):**
- Operational scripts: `scripts/ops/digest.sh`, `scripts/ops/work.sh`, `scripts/ops/intake.sh`, and `scripts/ops/tracker_search.sh` must **not** have their execution logic modified.
- Persona definitions: `personas/**` and `scripts/sync_agents.py` remain untouched.
- Configuration: `config/**` remains untouched.
- Closing out `/wrap`: `commands/wrap.md` is **not** touched (reserved for Issue #85).

---

## 3. Detailed Architectural Calls

### P1 · Canonical Source Directory Standard (`commands/<name>.md`) (D1)
- Source files reside in `commands/<name>.md`.
- Each source file begins with YAML frontmatter delimited by `---` containing:
  - `description`: mandatory non-empty string describing command purpose.
  - `argument-hint`: optional string describing parameter syntax (single-quoted if containing special characters).
  - `allowed-tools`: optional string or list of strings describing tool grants (Claude Code specific).
- Content following the closing `---` delimiter is the exact Markdown body.

### P2 · Byte-Identical Emission on Claude Code (D2)
- Target: `.claude/commands/<name>.md`.
- Frontmatter keys are emitted verbatim without YAML reflow (`yaml.safe_dump`), line wrapping of long scalars, or unicode escaping (matching the discipline of `sync_agents.py:688-695`).
- Emitted `.claude/commands/{work,idea,bug}.md` must match `origin/main` byte-for-byte (`git diff .claude/commands/` is clean).
- In particular, **NO** `# GENERATED...` comment line is inserted into Claude target frontmatter, preserving exact syntax compatibility with Claude Code's parser.

### P3 · Execution Mode Derivation (`exec` vs `prompt`) (D3)
- Emitter inspects the first non-whitespace line of the command body:
  - If it begins with `!` (backtick-enclosed shell command, e.g. `!\`scripts/ops/...\``), classified as `kind: exec`.
  - Otherwise, classified as `kind: prompt`.
- No redundant `kind:` or `type:` field in canonical frontmatter.

### P4 · Native Antigravity Target Structure in `.agents/skills/<name>/SKILL.md` (D4)
- Target: `.agents/skills/<name>/SKILL.md` relative to workspace root (verified native workspace discovery in `agy 1.2.0`).
- Target begins with `---` at byte 0.
- Line 2 (first line inside frontmatter block) contains provenance comment:
  `# GENERATED by scripts/sync_commands.py — edit commands/, not this file`
- Frontmatter contains `name: <name>` and `description: <description>`.

### P5 · Antigravity Hardened Execution Semantics for `/work` (D5, Amending #43 D16)
- Amends #43 D16: Antigravity executes tools inside the model loop via `run_command` rather than Claude Code's pre-turn shell hook. Bare prompt variable interpolation (`$ARGUMENTS`) into bash is unsafe.
- For `exec` commands (`/work`), the Antigravity emitter unwraps the `!` expression and generates imperative Agent Skill instructions:
  1. Validate that input matches `<number> [--as <persona>]` where `<number>` contains only digits.
  2. Strictly reject input containing shell metacharacters: `;`, `&`, `|`, `` ` ``, `$`, `(`, `)`, `<`, `>`, `\n`.
  3. Invoke `HEADLESS=1 scripts/ops/work.sh <number> [--as <persona>]` via `run_command` and report output.

### P6 · Antigravity Intake Semantics and `allowed-tools` Omission (D6)
- For `prompt` commands (`/idea`, `/bug`), the Antigravity emitter retains the canonical conversational intake prompt.
- Includes a usage header specifying that `$ARGUMENTS` represents raw user input following the slash command.
- `allowed-tools` is Claude-only (`agy` has no per-skill tool grant field); emitter intentionally omits `allowed-tools` from `.agents/skills/<name>/SKILL.md`.

### P7 · Dedicated Compiler Script `scripts/sync_commands.py` (D7)
- Standalone Python script executable with stdlib + `pyyaml`.
- CLI interface:
  - `python3 scripts/sync_commands.py`: default compilation into workspace targets.
  - `python3 scripts/sync_commands.py --check`: in-memory build and diff against disk; exits 0 on clean tree, 1 on drift with per-file diff summary.
  - `--root DIR`: custom root directory for input sources and target trees.
  - `--out DIR`: custom output directory for isolated roundtrip tests.
- Processes commands in deterministic lexicographical order.

### P8 · Complete Secret Leak and Path Sanitizer Parity (D8)
- Enforces exact parity with `sync_agents.py`'s 10-pattern sanitizer (`SECRET_PATTERNS`):
  1. Absolute home directory paths.
  2. Users directory paths.
  3. Home-variable references or home-relative dotfile paths.
  4. `gh[pousr]_` GitHub personal access tokens.
  5. `github_pat_` GitHub fine-grained PATs.
  6. `AKIA` AWS access key IDs.
  7. `sk-` OpenAI secret keys.
  8. `xox[baprs]-` Slack tokens.
  9. `-----BEGIN ... PRIVATE KEY-----` private key blocks.
  10. Inline credential values (credential key followed by secret-like value).
- If any emitted target matches a pattern, compilation aborts with exit code 1, prints `REFUSING TO WRITE <relpath>`, and writes nothing.

### P9 · Target Ownership, Scoped Pruning, and `wrap.md` Allowlist (D9, D12, D14)
- Managed target directories: `.claude/commands/` and `.agents/skills/`.
- Pruning in `.claude/commands/` is strictly scoped to `*.md` files directly under `.claude/commands/`.
- Pruning in `.agents/skills/` is scoped to directories matching skills generated from canonical commands.
- **Allowlist:** `.claude/commands/wrap.md` is explicitly allowlisted in `sync_commands.py`:
  - `sync_commands.py --check` ignores `.claude/commands/wrap.md` (does not flag as drift).
  - `sync_commands.py` does not prune `.claude/commands/wrap.md`.
- Unmanaged extraneous files (e.g. `.claude/commands/orphan.md`) trigger exit 1 under `--check` and are pruned during regular compilation.

### P10 · Ref-Free CI Roundtrip Gate (`compiler_roundtrip.sh`) (D10, R2-1)
- `scripts/ci/compiler_roundtrip.sh` is extended with Step 9 ("Commands compiler roundtrip and drift gate") following Step 8 (frontmatter validation added by #425).
- Standing CI gate: `compiler_roundtrip.sh` is wired into `.github/workflows/ci-gates.yml` under the `drift` job, providing standing regression and drift prevention.
- Step 9 also executes `scripts/ci/tests/sync_commands_test.py` post-implementation (R1-5).
- Entirely ref-free: `scripts/ci/compiler_roundtrip.sh` Step 9 contains no git invocations or remote ref requirements; standing contract test `test_d2` gates remote `origin/main` queries on ref availability and falls back to committed targets when the ref is absent (supporting shallow CI checkouts per R2-1).
- Checks:
  1. `COMPILER_COMMANDS="$REPO/scripts/sync_commands.py"`
  2. `python3 "$COMPILER_COMMANDS" --check` exits 0.
  3. Emitted `.agents/skills/{work,idea,bug}/SKILL.md` exist and match sources.
  4. Standing contract suite: `python3 "$REPO/scripts/ci/tests/sync_commands_test.py"` exits 0 (ref-free in shallow CI).
  5. Two consecutive compiles in a temp tree produce byte-identical file trees.
  6. Throwaway command in temp tree compiles to both targets.
  7. Source containing home path or secret pattern triggers sanitizer refusal.

### P11 · Living Spec Protection (`spec_check.sh`) (D11)
- `commands/*` is added to the behavior-bearing path regex in `scripts/ci/spec_check.sh`:
  `case "$f" in .github/workflows/*|scripts/*|personas/*|config/*|commands/*)`
- Pull requests modifying `commands/*` must update `docs/SPEC.md` or carry `Spec-impact: none — <reason>`.

### P12 · Decoupled Scope with Issue #85 / PR #406 (`wrap.md`) (D12)
- Authoring and canonical delivery of `/wrap` is owned by Issue #85 (`intent/85-session-close-out/`).
- Issue #416 does not touch `commands/wrap.md`. `.claude/commands/wrap.md` remains allowlisted until Issue #85 performs canonical migration.

### P13 · Clean Ingestion of Landed Prerequisite Fix (PR #425) (D14)
- PR #425 has merged to `main`, quoting `argument-hint` in `.claude/commands/bug.md`.
- Canonical migration copies `.claude/commands/bug.md` to `commands/bug.md`, achieving byte-identical compilation against `origin/main` without syntax errors.

---

## 4. Micro-Stepped Tasks

### Task T1: Commit Hermetic Contract Test Suite in `scripts/ci/tests/sync_commands_test.py`
- **Owner:** daedalus (Build stage)
- **Files touched:** `scripts/ci/tests/sync_commands_test.py`
- **Decisions implemented:** D1–D14
- **Acceptance criteria proven:** AT-416-1 through AT-416-13
- **Description:** Implement `scripts/ci/tests/sync_commands_test.py` containing 12 unit and contract test methods covering canonical sources, byte-identical Claude emission, Antigravity execution hardening, Antigravity intake prompt semantics, `--check` drift detection, 10-pattern secret sanitizer refusal, scoped pruning and `wrap.md` allowlist, CI roundtrip wiring, `spec_check.sh` inclusion, and living spec documentation.
- **Done-When:**
  Running `python3 scripts/ci/tests/sync_commands_test.py` against the unpatched baseline reports 12 clean test failures (`FAILED (failures=12)`), exits with code 1, and reports 0 errors.

---

### Task T2: Establish Canonical Command Sources in `commands/{work,idea,bug}.md`
- **Owner:** odyssey (Implement stage)
- **Files touched:**
  - `commands/work.md`
  - `commands/idea.md`
  - `commands/bug.md`
- **Decisions implemented:** D1, D2, D14
- **Acceptance criteria proven:** AT-416-1
- **Step-by-step diff description:**
  1. Create directory `commands/`.
  2. Copy `.claude/commands/work.md` to `commands/work.md`.
  3. Copy `.claude/commands/idea.md` to `commands/idea.md`.
  4. Copy `.claude/commands/bug.md` to `commands/bug.md` (inheriting single-quoted `argument-hint` from PR #425).
  5. Verify all three files begin with `---`, contain valid YAML frontmatter with `description`, and contain the non-empty markdown body.
- **Done-When:**
  `python3 -c "import yaml; [yaml.safe_load(open(f'commands/{f}').read().split('---\n', 2)[1]) for f in ['work.md', 'idea.md', 'bug.md']]"` exits 0.

---

### Task T3: Implement Standalone Command Compiler `scripts/sync_commands.py`
- **Owner:** odyssey (Implement stage)
- **Risk:** high (core compiler plumbing)
- **Files touched:** `scripts/sync_commands.py`
- **Decisions implemented:** D1, D2, D3, D4, D5, D6, D7, D8, D9, D14
- **Acceptance criteria proven:** AT-416-2, AT-416-3, AT-416-4, AT-416-5, AT-416-6, AT-416-7, AT-416-8, AT-416-13
- **Step-by-step diff description:**
  1. Author `scripts/sync_commands.py` (executable `chmod +x`).
  2. Implement CLI argument parsing: `--check`, `--root DIR`, `--out DIR`.
  3. Implement frontmatter parser reading `commands/*.md`.
  4. Implement `kind: exec` vs `kind: prompt` derivation based on leading `!` in body (D3).
  5. Implement `ClaudeEmitter`:
     - Emits `.claude/commands/<name>.md`.
     - Preserves verbatim frontmatter formatting (`description`, `argument-hint`, `allowed-tools`).
     - Inserts **no** `# GENERATED` marker in frontmatter (D2).
  6. Implement `AntigravityEmitter`:
     - Emits `.agents/skills/<name>/SKILL.md`.
     - Emits frontmatter with `# GENERATED by scripts/sync_commands.py — edit commands/, not this file` on line 2, followed by `name:` and `description:` (D4).
     - For `exec` mode (`/work`), emits hardened argument validation instructions (`<number> [--as <persona>]`, metacharacter rejection `; & | ` $`, `HEADLESS=1 scripts/ops/work.sh`, `run_command`) (D5).
     - For `prompt` mode (`/idea`, `/bug`), emits intake prompt instructions with `$ARGUMENTS` parameter usage and omits `allowed-tools` (D6).
  7. Implement 10-pattern secret and path sanitizer (`SECRET_PATTERNS` / `sanitize()`) matching `sync_agents.py` (D8).
  8. Implement scoped target pruning:
     - Scoped to `*.md` files in `.claude/commands/`.
     - Scoped to generated skill folders in `.agents/skills/`.
     - Allowlist: explicitly exempt `.claude/commands/wrap.md` from drift check and pruning (D9, D12, D14).
- **Done-When:**
  `python3 scripts/sync_commands.py` compiles all targets cleanly and `python3 scripts/sync_commands.py --check` exits 0.

---

### Task T4: Compile Claude Code Targets and Verify Byte-Identity
- **Owner:** odyssey (Implement stage)
- **Files touched:**
  - `.claude/commands/work.md`
  - `.claude/commands/idea.md`
  - `.claude/commands/bug.md`
- **Decisions implemented:** D2
- **Acceptance criteria proven:** AT-416-2
- **Step-by-step diff description:**
  1. Run `python3 scripts/sync_commands.py`.
  2. Run `git diff .claude/commands/` and assert output is completely empty.
  3. Assert no `# GENERATED` comment exists in `.claude/commands/*.md`.
- **Done-When:**
  `git diff --exit-code .claude/commands/` exits 0.

---

### Task T5: Compile Antigravity Native Skill Targets
- **Owner:** odyssey (Implement stage)
- **Files touched:**
  - `.agents/skills/work/SKILL.md`
  - `.agents/skills/idea/SKILL.md`
  - `.agents/skills/bug/SKILL.md`
- **Decisions implemented:** D4, D5, D6
- **Acceptance criteria proven:** AT-416-3, AT-416-4, AT-416-5
- **Step-by-step diff description:**
  1. Verify `.agents/skills/work/SKILL.md` carries hardened validation:
     - literal `<number> [--as <persona>]`
     - forbidden metacharacters `;`, `&`, `|`, `` ` ``, `$`
     - literal `HEADLESS=1 scripts/ops/work.sh` and `run_command`
  2. Verify `.agents/skills/idea/SKILL.md` and `bug/SKILL.md` contain `tracker_search.sh`, `intake.sh`, and `$ARGUMENTS`.
  3. Verify all three skills carry `# GENERATED by scripts/sync_commands.py — edit commands/, not this file` on line 2, and omit `allowed-tools`.
- **Done-When:**
  Contract tests for D4, D5, D6 in `scripts/ci/tests/sync_commands_test.py` pass green.

---

### Task T6: Extend `scripts/ci/compiler_roundtrip.sh` with Ref-Free Commands Roundtrip Gate
- **Owner:** odyssey (Implement stage)
- **Risk:** medium (touches CI gate script)
- **Files touched:** `scripts/ci/compiler_roundtrip.sh`
- **Decisions implemented:** D10
- **Acceptance criteria proven:** AT-416-9
- **Step-by-step diff description:**
  1. In `scripts/ci/compiler_roundtrip.sh`, define Step 9 after Step 8:
     ```bash
     # --- 9. commands compiler roundtrip and drift gate ----------------------------
     step "9. commands: compiler roundtrip, determinism, and drift gate"
     COMPILER_COMMANDS="$REPO/scripts/sync_commands.py"
     python3 "$COMPILER_COMMANDS" --check \
       || fail "commands compiler --check failed against committed targets"

     assert_file "$REPO/.agents/skills/work/SKILL.md" "emitted work skill exists"
     assert_file "$REPO/.agents/skills/idea/SKILL.md" "emitted idea skill exists"
     assert_file "$REPO/.agents/skills/bug/SKILL.md" "emitted bug skill exists"

     # Standing contract suite execution in CI (R1-5, R2-1: ref-free in shallow CI clones)
     python3 "$REPO/scripts/ci/tests/sync_commands_test.py" \
       || fail "sync_commands_test.py contract suite failed"

     # Determinism test in temp directory
     CMD_TMP="$TMP/commands-determinism"
     mkdir -p "$CMD_TMP"
     python3 "$COMPILER_COMMANDS" --root "$REPO" --out "$CMD_TMP/out1"
     python3 "$COMPILER_COMMANDS" --root "$REPO" --out "$CMD_TMP/out2"
     diff -r "$CMD_TMP/out1" "$CMD_TMP/out2" || fail "commands compiler is non-deterministic"

     # Throwaway command test
     THROW_DIR="$TMP/throwaway-command"
     mkdir -p "$THROW_DIR/commands"
     cat > "$THROW_DIR/commands/ping.md" <<'CMD'
---
description: Ping test command
---
Ping body
CMD
     python3 "$COMPILER_COMMANDS" --root "$THROW_DIR" --out "$THROW_DIR/out"
     assert_file "$THROW_DIR/out/.claude/commands/ping.md" "throwaway claude target emitted"
     assert_file "$THROW_DIR/out/.agents/skills/ping/SKILL.md" "throwaway antigravity target emitted"

     # Sanitizer test (assembled to prevent repo scanner tripping)
     LEAK_DIR=home
     POISON_CMD="$TMP/poison-command"
     mkdir -p "$POISON_CMD/commands"
     cat > "$POISON_CMD/commands/leak.md" <<CMD
---
description: Leaky command
---
Path: /${LEAK_DIR}/user/secret
CMD
     if python3 "$COMPILER_COMMANDS" --root "$POISON_CMD" --out "$POISON_CMD/out" >/dev/null 2>&1; then
       fail "commands compiler emitted target containing home path"
     fi
     ```
  2. Update line 323 of `scripts/ci/compiler_roundtrip.sh` from `(8 checks)` to `(9 checks)`:
     `pass "compiler roundtrip green ($targets target files, 9 checks)."`
- **Done-When:**
  `bash scripts/ci/compiler_roundtrip.sh` runs all 9 steps green and prints `PASS: compiler roundtrip green (... target files, 9 checks).` with exit code 0.

---

### Task T7: Extend `scripts/ci/spec_check.sh` with `commands/*` in Behavior-Bearing Paths
- **Owner:** odyssey (Implement stage)
- **Files touched:** `scripts/ci/spec_check.sh`
- **Decisions implemented:** D11
- **Acceptance criteria proven:** AT-416-10
- **Step-by-step diff description:**
  In `scripts/ci/spec_check.sh`, update the behavior-bearing case match:
  ```diff
  --- a/scripts/ci/spec_check.sh
  +++ b/scripts/ci/spec_check.sh
  @@ -85 +85 @@
  -        .github/workflows/*|scripts/*|personas/*|config/*)
  +        .github/workflows/*|scripts/*|personas/*|config/*|commands/*)
  ```
- **Done-When:**
  Modifying a file in `commands/` without updating `docs/SPEC.md` causes `scripts/ci/spec_check.sh` to exit 1 if no bypass marker is present.

---

### Task T8: Record Amendment Note for D16 in `intent/43-harness-agnostic-launch/spec.md`
- **Owner:** odyssey (Implement stage)
- **Files touched:** `intent/43-harness-agnostic-launch/spec.md`
- **Decisions implemented:** D5, D12, D13
- **Acceptance criteria proven:** D5/D12/D13 contract
- **Step-by-step diff description:**
  In `intent/43-harness-agnostic-launch/spec.md`, append an amendment note to Decision D16:
  `*Amendment Note (Issue #416, 2026-09-11):* Amends D16's Claude-only hand-authored scope. Slash commands are now compiled cross-harness from canonical sources in commands/ via scripts/sync_commands.py. Antigravity receives a native Agent Skill at .agents/skills/work/SKILL.md with hardened input validation (checking <number> [--as <persona>] with digits-only numbers and rejecting shell metacharacters) before invoking run_command.`
- **Done-When:**
  Grep for `Amendment Note (Issue #416` in `intent/43-harness-agnostic-launch/spec.md` matches.

---

### Task T9: Update Living Spec `docs/SPEC.md` under `### commands.compiler`
- **Owner:** odyssey (Implement stage)
- **Files touched:** `docs/SPEC.md`
- **Decisions implemented:** D11, D13
- **Acceptance criteria proven:** AT-416-12
- **Step-by-step diff description:**
  In `docs/SPEC.md`, add section `### commands.compiler` documenting:
  - Canonical sources in `commands/<name>.md`.
  - Deterministic compilation via `scripts/sync_commands.py`.
  - Emitted Claude targets in `.claude/commands/<name>.md` (byte-identical, no frontmatter comment).
  - Emitted Antigravity skills in `.agents/skills/<name>/SKILL.md` (hardened execution model, `$ARGUMENTS` prompt intake, `allowed-tools` omission).
  - Ref-free CI roundtrip gate in `scripts/ci/compiler_roundtrip.sh` Step 9.
  - Inclusion under living-spec gate in `scripts/ci/spec_check.sh`.
  - Scoped pruning and `.claude/commands/wrap.md` allowlist.
- **Done-When:**
  `grep -q '### commands.compiler' docs/SPEC.md` exits 0.

---

### Task T10: Update Cross-Harness Documentation in `AGENTS.md`, `CLAUDE.md`, and `GEMINI.md`
- **Owner:** odyssey (Implement stage)
- **Files touched:**
  - `AGENTS.md`
  - `CLAUDE.md`
  - `GEMINI.md`
- **Decisions implemented:** D11, D13
- **Acceptance criteria proven:** AT-416-12
- **Step-by-step diff description:**
  1. `AGENTS.md`: Add slash command compilation overview explaining that commands are authored in `commands/` and compiled to `.claude/commands/` and `.agents/skills/` via `scripts/sync_commands.py`.
  2. `CLAUDE.md`: Reference `scripts/sync_commands.py` for `/work`, `/idea`, and `/bug`.
  3. `GEMINI.md`: Reference `scripts/sync_commands.py` and document native skill availability at `.agents/skills/`.
  4. Note on `CHANGELOG.md` (R2-2): `CHANGELOG.md` is excluded from the D13 file manifest. To satisfy `scripts/ci/changelog_check.sh`, the implement PR description carries the bypass header:
     `Changelog: none — commands compiler infrastructure, targets, and documentation (CHANGELOG.md excluded by D13 manifest)`
- **Done-When:**
  Grep for `sync_commands.py` in `AGENTS.md`, `CLAUDE.md`, and `GEMINI.md` all return matches.

---

### Task T11: Run Full Verification Suite, Contract Tests, and Open Implementation PR
- **Owner:** odyssey (Implement stage)
- **Acceptance criteria proven:** AT-416-1 through AT-416-13
- **Step-by-step verification commands:**
  1. Contract tests:
     `python3 scripts/ci/tests/sync_commands_test.py`
     Exits 0 (`OK`, 12 tests passed, 0 failures, 0 errors).
  2. Compiler drift check:
     `python3 scripts/sync_commands.py --check`
     Exits 0.
  3. Claude target byte-identity:
     `git diff --exit-code .claude/commands/`
     Exits 0.
  4. Compiler roundtrip CI gate:
     `bash scripts/ci/compiler_roundtrip.sh`
     Exits 0 with all 9 steps green.
  5. Sanitize gate:
     `bash scripts/ci/sanitize_check.sh`
     Exits 0 with 0 findings.
  6. Living spec check:
     `bash scripts/ci/spec_check.sh origin/main`
     Exits 0.
  7. Changelog obligation gate (R1-7, R2-2):
     `bash scripts/ci/changelog_check.sh origin/main <(echo "Changelog: none — commands compiler infrastructure, targets, and documentation (CHANGELOG.md excluded by D13 manifest)")`
     Exits 0 (`::notice::changelog check: declared no changelog impact — commands compiler infrastructure, targets, and documentation (CHANGELOG.md excluded by D13 manifest)`).
  8. Verify operational scripts remain untouched (AT-416-11):
     `git diff origin/main -- scripts/ops/digest.sh scripts/ops/work.sh scripts/ops/intake.sh scripts/ops/tracker_search.sh`
     Outputs empty diff.
  9. Commit explicitly authored as Odyssey App identity:
     `git -c user.name="evekhm-odyssey-app[bot]" -c user.email="323814131+evekhm-odyssey-app[bot]@users.noreply.github.com" commit ...`
  10. Push branch `odyssey/416-commands-work-idea-bug` (exact match to intent folder slug `416-commands-work-idea-bug` so `lifecycle_advance.sh` advances automatically on merge) and open PR targeting `main` with `Closes #416`.
  11. Apply `deep-review` grant:
      `scripts/ops/post.sh <pr> --as odyssey --add-label deep-review`.

---

## 5. Traceability Matrix

| Decision | Acceptance Criteria | Plan Section | Micro-Stepped Task | Contract Assertion |
|---|---|---|---|---|
| **D1** (Canonical sources `commands/<name>.md`) | AT-416-1 | Section 3 (P1) | T2, T3 | `test_d1_d14_at_416_1_canonical_sources_exist` |
| **D2** (Byte-identical Claude emission) | AT-416-2 | Section 3 (P2) | T3, T4 | `test_d2_at_416_2_claude_targets_byte_identity` |
| **D3** (`exec` vs `prompt` derivation) | AT-416-4, AT-416-5 | Section 3 (P3) | T3 | `test_d3_d5_at_416_4_antigravity_work_skill_hardening` |
| **D4** (Antigravity skill structure in `.agents/skills/`) | AT-416-3 | Section 3 (P4) | T3, T5 | `test_d4_at_416_3_antigravity_skills_structure` |
| **D5** (Hardened execution semantics, amending #43 D16) | AT-416-4 | Section 3 (P5) | T3, T5, T8 | `test_d3_d5_at_416_4_antigravity_work_skill_hardening`, `test_d12_d13_amendment_note_for_issue_43_d16` |
| **D6** (Antigravity prompt semantics & `allowed-tools` omission) | AT-416-5 | Section 3 (P6) | T3, T5 | `test_d6_at_416_5_antigravity_prompt_skills_and_allowed_tools` |
| **D7** (Dedicated compiler `scripts/sync_commands.py`) | AT-416-6 | Section 3 (P7) | T3, T11 | `test_d7_at_416_6_compiler_cli_and_drift_detection` |
| **D8** (10-pattern sanitizer parity) | AT-416-8 | Section 3 (P8) | T3 | `test_d8_at_416_8_sanitizer_refuses_forbidden_patterns` |
| **D9** (Scoped pruning & `wrap.md` allowlist) | AT-416-7, AT-416-13 | Section 3 (P9) | T3 | `test_d9_d14_at_416_7_at_416_13_pruning_and_wrap_allowlist` |
| **D10** (Ref-free CI roundtrip gate) | AT-416-9 | Section 3 (P10) | T6 | `test_d10_at_416_9_compiler_roundtrip_includes_commands_gate` |
| **D11** (Living spec gate in `spec_check.sh`) | AT-416-10, AT-416-12 | Section 3 (P11) | T7, T9 | `test_d11_at_416_10_spec_check_includes_commands_path`, `test_d11_d13_at_416_12_living_spec_and_documentation_parity` |
| **D12** (Decoupled scope with PR #406 / Issue #85) | AT-416-13 | Section 3 (P12) | T3, T11 | `test_d9_d14_at_416_7_at_416_13_pruning_and_wrap_allowlist` |
| **D13** (Implementation manifest boundary: scripts/ops untouched) | AT-416-11 | Section 2, Section 3 | T11 (step 8) | Reviewer-verified (`git diff origin/main -- scripts/ops/{digest,work,intake,tracker_search}.sh` in T11) |
| **D13** (Implementation manifest boundary: documentation & living spec) | AT-416-12 | Section 2, Section 3 | T8, T9, T10 | `test_d11_d13_at_416_12_living_spec_and_documentation_parity`, `test_d12_d13_amendment_note_for_issue_43_d16` |
| **D14** (Prerequisite defect resolution from PR #425) | AT-416-1, AT-416-2 | Section 1, Section 3 (P13) | T2, T3, T4 | `test_d1_d14_at_416_1_canonical_sources_exist`, `test_d9_d14_at_416_7_at_416_13_pruning_and_wrap_allowlist` |
