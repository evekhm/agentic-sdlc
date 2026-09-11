# Plan: Fix Invalid YAML Frontmatter in .claude/commands/bug.md and wrap.md

**Issue:** #425 · **Spec:** `intent/425-bug/spec.md` (Approved, PR #431, D1–D7, AT-425-1–AT-425-9)  
**Author:** daedalus (`evekhm-daedalus-app[bot]`)  
**Base commit:** `023ca1776ff5ddfc72cf146b82e848493c469361` (origin/main, merge of spec PR #431)  
**Target branch for implementation (Odyssey):** `odyssey/425-bug-claude-commands-bug-md-has-invalid` (or `odyssey/425-bug`)

---

## 1. Executive Summary and Problem Statement

Two slash command definitions in `.claude/commands/` on `main` currently contain syntax errors in their YAML frontmatter:
1. `.claude/commands/bug.md` (line 3): defines `argument-hint` as an unquoted plain scalar containing an unescaped colon-space (`bug: repro`). Under YAML 1.2 rules, this is interpreted as a mapping value within an unquoted scalar, raising `yaml.scanner.ScannerError: mapping values are not allowed here`.
2. `.claude/commands/wrap.md` (line 3): defines `argument-hint` as an unquoted plain scalar starting with a bracket (`[`). Under YAML 1.2 rules, this is parsed as an unclosed flow sequence, raising `yaml.parser.ParserError: while parsing a block mapping ... expected <block end>, but found '['`.

While Claude Code's native frontmatter reader currently tolerates these lines during interactive slash command execution, strict YAML parsers (such as Python's `yaml.safe_load`) fail immediately. This pre-existing syntax error directly blocks issue #416 (PR #422, D14), which compiles slash commands cross-harness from canonical sources in `commands/` and requires byte-identical round-trip verification against `origin/main`.

This plan details the micro-stepped implementation to:
- Enclose `argument-hint` in `.claude/commands/bug.md` and `.claude/commands/wrap.md` in single quotes (`'...'`), eliminating syntax errors without requiring backslash escapes and preserving exact parsed string values (D1, D2).
- Restrict changes to surgical single-line edits modifying only line 3 in both command files (D6).
- Commit a hermetic contract test script (`scripts/ci/tests/command_frontmatter_test.sh`) verifying frontmatter validity and argument-hint extraction across all command files, including negative tests against simulated malformed commands (D3).
- Wire `scripts/ci/tests/command_frontmatter_test.sh` into `scripts/ci/compiler_roundtrip.sh` as a permanent CI regression gate (D3).

---

## 2. Scope and Persona Boundaries

| Actor | Stage | Authority / Files Touched | Role in Issue #425 |
|---|---|---|---|
| **athena** | plan / design | `intent/**` | Authored `intent.md` and approved `spec.md` (merged in PR #431). |
| **daedalus** | build | `intent/**`, `scripts/*/tests/**` | Authors `plan.md` and commits contract test suite `scripts/ci/tests/command_frontmatter_test.sh`. Daedalus **never** writes production code. |
| **odyssey** | implement | `.claude/commands/bug.md`, `.claude/commands/wrap.md`, `scripts/ci/compiler_roundtrip.sh` | Implements surgical single-line quotes in `bug.md` and `wrap.md`, wires contract test into `compiler_roundtrip.sh`, verifies all contract tests pass green, and opens PR. |
| **themis** | autonomous merge | GitHub Actions (`merge-gate.yml`) | Autonomously gates and merges pull requests upon consensus. |
| **argus / atlas** | review | comments only | Reviews pull requests against spec and plan. |

### Deep Review Grant (DEEP-1, DEEP-5, DEEP-7)

- **Criteria Met on Build PR (Daedalus):**
  - **DEEP-1 (trust-bearing paths):** The build PR touches `scripts/ci/tests/command_frontmatter_test.sh`, which falls under `config/execution.yaml` `assigned_when.paths` for Argus (`scripts/ci/**`).
  - **Action:** Apply `deep-review` label via `scripts/ops/post.sh <pr> --as daedalus --add-label deep-review`.
- **Criteria Met on Implementation PR (Odyssey):**
  - **DEEP-1 (trust-bearing paths):** The implementation diff touches `scripts/ci/compiler_roundtrip.sh`, which falls under `scripts/ci/**`.
  - **DEEP-5 (escalated tier / risk):** Task T4 edits `compiler_roundtrip.sh`, a core gate script evaluated by CI gates.
  - **Action:** Odyssey applies the `deep-review` grant when opening the PR per `scripts/ops/post.sh <pr> --as odyssey --add-label deep-review`.

### Living Spec Obligation (D4)

- Updating frontmatter quoting fixes YAML syntax conformance without modifying command execution logic, capabilities, or arguments.
- Per Decision D4, living spec impact is none:
  `Spec-impact: none — frontmatter YAML syntax fix with zero behavioral change to command capabilities`
- Daedalus build PR body carries:
  `Spec-impact: none — build stage contract tests and plan only`

### Strict File Manifest Partitioning (D5)

The implementation pull request is strictly confined to:
- `.claude/commands/bug.md`
- `.claude/commands/wrap.md`
- `scripts/ci/tests/command_frontmatter_test.sh`
- `scripts/ci/compiler_roundtrip.sh`
- `intent/425-bug/**`

**Forbidden paths (untouched):**
- `commands/**`: Reserved for issue #416.
- `scripts/sync_commands.py`: Reserved for issue #416.
- `personas/**`: Persona definitions are unaffected.
- `config/**`: Configuration is unaffected.
- `docs/SPEC.md`: Non-behavior-bearing syntax fix.
- `scripts/ops/work.sh`, `scripts/ops/claim.sh`: Operations unaffected.

---

## 3. Detailed Architectural Calls

### P1 · Scope of Corrections Encompasses Both bug.md and wrap.md (D1)
- Frontmatter corrections fix `.claude/commands/bug.md` (the filed defect) and `.claude/commands/wrap.md` (the sibling defect introduced in PR #406).
- Eliminates all frontmatter YAML syntax errors across the repository in a single unified pass, unblocking #416 D14.

### P2 · Single Quotes for Argument-Hint Scalars (D2)
- In `.claude/commands/bug.md`, line 3:
  ```yaml
  argument-hint: '<free text describing the bug: repro, expected vs actual; may include "Given design:", "Given spec:", or "Given code:" sections>'
  ```
- In `.claude/commands/wrap.md`, line 3:
  ```yaml
  argument-hint: '[<seat-or-slug>] [--snapshot]'
  ```
- Rationale: Single quotes preserve internal double quotes (`"Given design:"`) verbatim without backslash escaping (`\"`), matching the convention already established in `.claude/commands/idea.md`.
- In `yaml.safe_load`, the parsed scalar values are identical to the unquoted intent:
  - `bug.md`: `<free text describing the bug: repro, expected vs actual; may include "Given design:", "Given spec:", or "Given code:" sections>`
  - `wrap.md`: `[<seat-or-slug>] [--snapshot]`

### P3 · Hermetic Contract Test and CI Gate (D3)
- Standalone script: `scripts/ci/tests/command_frontmatter_test.sh` (executable `chmod +x`).
- Dual-mode operation:
  1. Default mode (`no args`): runs the full contract test suite asserting:
     - Negative tests on simulated command fixtures (unquoted colon, unquoted brackets, missing description, missing argument-hint).
     - Positive test on simulated command fixture with valid single-quoted hint.
     - Concrete assertions on `.claude/commands/bug.md` line 3 format, parsed value, and surrounding lines.
     - Concrete assertions on `.claude/commands/wrap.md` line 3 format, parsed value, and surrounding lines.
     - Repository-wide scan across all `.claude/commands/*.md` (and `commands/*.md` if present).
  2. Direct validator mode (`scripts/ci/tests/command_frontmatter_test.sh <file|dir>...`): validates specified files/directories; exits 0 if all valid, 1 if any invalid.
- Wired into `scripts/ci/compiler_roundtrip.sh` as Step 8, ensuring permanent automated regression protection on every build.

### P4 · Surgical Single-Line Edits (D6)
- In both `.claude/commands/bug.md` and `.claude/commands/wrap.md`, only line 3 (`argument-hint:`) is modified.
- All other lines (lines 1-2, lines 4-5, markdown body) remain byte-for-byte identical to `origin/main`.

### P5 · Downstream Decoupling with Issue #416 (D7)
- Issue #425 lands independently on `main`. Once merged, `origin/main` provides the valid YAML baseline that allows #416 D14 to compile and migrate commands byte-for-byte without special allowlist exemptions.

---

## 4. Micro-Stepped Tasks

### Task T1: Commit Hermetic Contract Test Suite in `scripts/ci/tests/command_frontmatter_test.sh`
- **Owner:** daedalus (Build stage)
- **File touched:** `scripts/ci/tests/command_frontmatter_test.sh`
- **Decisions implemented:** D1, D2, D3, D6
- **Acceptance criteria proven:** AT-425-1, AT-425-2, AT-425-3, AT-425-4, AT-425-5, AT-425-6
- **Description:** Implement `scripts/ci/tests/command_frontmatter_test.sh`. It implements both full contract test suite mode and direct file validator mode.
- **Done-When:**
  Running `bash scripts/ci/tests/command_frontmatter_test.sh` against the current unpatched repository state reports clean assertion failures on the unfixed commands (`Total: 11, Passed: 8, Failed: 3`), exits 1 with no python syntax errors or unhandled exceptions, and simulated negative tests pass.

---

### Task T2: Surgical Single-Line Frontmatter Fix for `.claude/commands/bug.md`
- **Owner:** odyssey (Implement stage)
- **File touched:** `.claude/commands/bug.md`
- **Decisions implemented:** D1, D2, D6
- **Acceptance criteria proven:** AT-425-1, AT-425-3
- **Step-by-step diff description:**
  In `.claude/commands/bug.md`, edit line 3 to enclose the scalar in single quotes:
  ```diff
  --- a/.claude/commands/bug.md
  +++ b/.claude/commands/bug.md
  @@ -3 +3 @@
  -argument-hint: <free text describing the bug: repro, expected vs actual; may include "Given design:", "Given spec:", or "Given code:" sections>
  +argument-hint: '<free text describing the bug: repro, expected vs actual; may include "Given design:", "Given spec:", or "Given code:" sections>'
  ```
  Lines 1-2, 4-5, and markdown body lines 6+ must remain completely untouched.
- **Done-When:**
  `python3 -c "import yaml; data = yaml.safe_load(open('.claude/commands/bug.md').read().split('---\n', 2)[1]); assert data['argument-hint'] == '<free text describing the bug: repro, expected vs actual; may include \"Given design:\", \"Given spec:\", or \"Given code:\" sections>'"` exits 0.

---

### Task T3: Surgical Single-Line Frontmatter Fix for `.claude/commands/wrap.md`
- **Owner:** odyssey (Implement stage)
- **File touched:** `.claude/commands/wrap.md`
- **Decisions implemented:** D1, D2, D6
- **Acceptance criteria proven:** AT-425-2, AT-425-4
- **Step-by-step diff description:**
  In `.claude/commands/wrap.md`, edit line 3 to enclose the scalar in single quotes:
  ```diff
  --- a/.claude/commands/wrap.md
  +++ b/.claude/commands/wrap.md
  @@ -3 +3 @@
  -argument-hint: [<seat-or-slug>] [--snapshot]
  +argument-hint: '[<seat-or-slug>] [--snapshot]'
  ```
  Lines 1-2, 4-5, and markdown body lines 6+ must remain completely untouched.
- **Done-When:**
  `python3 -c "import yaml; data = yaml.safe_load(open('.claude/commands/wrap.md').read().split('---\n', 2)[1]); assert data['argument-hint'] == '[<seat-or-slug>] [--snapshot]'"` exits 0.

---

### Task T4: Wire `command_frontmatter_test.sh` into `scripts/ci/compiler_roundtrip.sh`
- **Owner:** odyssey (Implement stage)
- **Risk:** medium (touches core CI roundtrip gate)
- **File touched:** `scripts/ci/compiler_roundtrip.sh`
- **Decisions implemented:** D3
- **Acceptance criteria proven:** AT-425-6, AT-425-7
- **Step-by-step diff description:**
  In `scripts/ci/compiler_roundtrip.sh`, register Step 8 after Step 7:
  ```bash
  # --- 8. command frontmatter validation ----------------------------------------
  step "8. command frontmatter: all command files contain valid YAML frontmatter"
  bash "$REPO/scripts/ci/tests/command_frontmatter_test.sh" \
    || fail "command frontmatter validation failed"
  ```
  Update the final pass summary message line from `(7 checks)` to `(8 checks)`.
- **Done-When:**
  Running `bash scripts/ci/compiler_roundtrip.sh` executes Step 8, tests all command frontmatters, and outputs `PASS: compiler roundtrip green (... target files, 8 checks).` with exit code 0.

---

### Task T5: Run Full Verification Suite and Open Implementation PR
- **Owner:** odyssey (Implement stage)
- **Acceptance criteria proven:** AT-425-1 through AT-425-9
- **Step-by-step verification commands:**
  1. `bash scripts/ci/tests/command_frontmatter_test.sh` exits 0 with `Total: 11, Passed: 11, Failed: 0`.
  2. `bash scripts/ci/compiler_roundtrip.sh` exits 0 with all 8 steps green.
  3. Spec check:
     `bash scripts/ci/spec_check.sh origin/main <(echo "Spec-impact: none — frontmatter YAML syntax fix with zero behavioral change to command capabilities")`
     exits 0.
  4. Manifest validation:
     `git diff --name-only origin/main` matches exactly:
     - `.claude/commands/bug.md`
     - `.claude/commands/wrap.md`
     - `scripts/ci/compiler_roundtrip.sh`
     - `scripts/ci/tests/command_frontmatter_test.sh`
     - `intent/425-bug/plan.md`
  5. Commit author: author commit explicitly as Odyssey App identity:
     `git -c user.name="evekhm-odyssey-app[bot]" -c user.email="323814131+evekhm-odyssey-app[bot]@users.noreply.github.com" commit ...`
  6. Push branch and open PR targeting `main` with body containing:
     `Spec-impact: none — frontmatter YAML syntax fix with zero behavioral change to command capabilities`
     and `Closes #425`.
  7. Apply `deep-review` grant:
     `scripts/ops/post.sh <pr> --as odyssey --add-label deep-review`.

---

## 5. Traceability Matrix

| Decision | Acceptance Criteria | Plan Section | Micro-Stepped Task | Contract Assertion |
|---|---|---|---|---|
| **D1** (Scope bug.md + wrap.md) | AT-425-1, AT-425-2, AT-425-5 | Section 3 (P1) | T2, T3 | Assertions 6, 8, 10 in `command_frontmatter_test.sh` |
| **D2** (Single quotes) | AT-425-1, AT-425-2, AT-425-3, AT-425-4 | Section 3 (P2) | T2, T3 | Assertions 5, 6, 8 in `command_frontmatter_test.sh` |
| **D3** (Contract test & CI gate) | AT-425-5, AT-425-6, AT-425-7 | Section 3 (P3) | T1, T4 | Assertions 1–5, 10, 11 in `command_frontmatter_test.sh` |
| **D4** (Spec-impact: none) | AT-425-8 | Section 2 | T5 | Verified in Task T5 |
| **D5** (File manifest partitioning) | AT-425-9 | Section 2 | T5 | Verified in Task T5 |
| **D6** (Surgical single-line edit) | AT-425-1, AT-425-2 | Section 3 (P4) | T2, T3 | Assertions 7, 9 in `command_frontmatter_test.sh` |
| **D7** (Decoupling from #416) | AT-425-5 | Section 3 (P5) | T5 | Assertion 11 in `command_frontmatter_test.sh` |
