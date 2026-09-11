# Spec: Fix invalid YAML frontmatter in .claude/commands/bug.md and wrap.md

**Issue:** #425 · **Status:** Approved (approval = merge of this PR) · **Author:** athena (`evekhm-athena-app[bot]`) · **Open questions:** none

## What is being built

This specification resolves issue #425 by correcting the invalid YAML 1.2 frontmatter present in Claude Code command files on `main`.

Specifically, two slash command definitions in `.claude/commands/` contain syntax errors in their `argument-hint` fields:
1. `.claude/commands/bug.md` (line 3):
   ```yaml
   argument-hint: <free text describing the bug: repro, expected vs actual; may include "Given design:", "Given spec:", or "Given code:" sections>
   ```
   An unquoted colon-space (`bug: repro`) inside the plain scalar is parsed by YAML 1.2 parsers as an illegal mapping value inside a scalar key, raising:
   `yaml.scanner.ScannerError: mapping values are not allowed here`
2. `.claude/commands/wrap.md` (line 3):
   ```yaml
   argument-hint: [<seat-or-slug>] [--snapshot]
   ```
   The unquoted leading bracket (`[`) initiates a YAML flow sequence rather than a plain string scalar, raising:
   `yaml.parser.ParserError: while parsing a block mapping ... expected <block end>, but found '['`

While Claude Code's internal markdown parser tolerates these unquoted strings during interactive slash command execution, strict YAML parsers (such as Python's `yaml.safe_load`) fail immediately. This defect directly blocks issue #416 (PR #422, D14), which compiles slash commands from canonical sources in `commands/` across both Claude Code and Antigravity runtimes, requiring valid frontmatter and byte-identical round-trip verification.

This specification:
1. Encloses the `argument-hint` values in `.claude/commands/bug.md` and `.claude/commands/wrap.md` in single quotes (`'...'`), eliminating syntax errors without requiring backslash escape sequences and preserving the exact string value byte-for-byte upon parsing.
2. Preserves every other line of both files byte-identically (surgical single-line edits).
3. Introduces a hermetic contract test script (`scripts/ci/tests/command_frontmatter_test.sh`) that verifies all `.claude/commands/*.md` (and `commands/*.md` once created) parse cleanly with `yaml.safe_load` and accurately extract expected fields.
4. Registers this contract test in `scripts/ci/compiler_roundtrip.sh`, establishing a permanent CI regression gate.

### Manifest of Files Touched by the Implementation Rung

- `.claude/commands/bug.md`: Quote line 3 `argument-hint` with single quotes.
- `.claude/commands/wrap.md`: Quote line 3 `argument-hint` with single quotes.
- `scripts/ci/tests/command_frontmatter_test.sh`: Hermetic contract test asserting YAML frontmatter validity and argument hint extraction across command files.
- `scripts/ci/compiler_roundtrip.sh`: Register `command_frontmatter_test.sh` as an automated gate.
- `intent/425-bug/plan.md`: Ordered implementation plan authored by Daedalus.

### Manifest of Files Touched by this PR (Athena)

- `intent/425-bug/intent.md`: Intent artifact updated to `Status: Accepted`.
- `intent/425-bug/spec.md`: This specification.

### Forbidden Files (Untouched)

- `commands/**`: Reserved for issue #416.
- `scripts/sync_commands.py`: Reserved for issue #416.
- `personas/**`: Persona definitions are unaffected.
- `config/**`: Configuration is unaffected.
- `docs/SPEC.md`: Non-behavior-bearing syntax fix (`Spec-impact: none`).
- `scripts/ops/work.sh`, `scripts/ops/claim.sh`: Workflow operations unaffected.

## Decisions

| ID | Decision | Rationale |
|---|---|---|
| **D1** | **Scope of frontmatter corrections encompasses `.claude/commands/bug.md` and `.claude/commands/wrap.md`.** The implementing pull request fixes both `.claude/commands/bug.md` and `.claude/commands/wrap.md`. | *Adversary analysis:* Two defensible readings of scope: (1) restrict strictly to `bug.md` (the file named in #425's title); (2) include `wrap.md` (the sibling command merged via PR #406 exhibiting the same class of YAML syntax failure). Differing case: run `python3 -c "import yaml; [yaml.safe_load(open(f).read().split('---\n', 2)[1]) for f in ['.claude/commands/bug.md', '.claude/commands/wrap.md']]"` at the implementation head. Under Reading 1, `wrap.md` fails with `ParserError` and a second prerequisite issue must be filed before #416 can compile commands; under Reading 2, the command exits 0 and all command frontmatters across the repository parse cleanly. Resolving both in #425 cleanly eliminates all frontmatter syntax errors in one pass. |
| **D2** | **Single quotes (`'...'`) for `argument-hint` scalars.** Enclose the `argument-hint` scalar in single quotes: `argument-hint: '<free text describing the bug: repro, expected vs actual; may include "Given design:", "Given spec:", or "Given code:" sections>'` in `bug.md`, and `argument-hint: '[<seat-or-slug>] [--snapshot]'` in `wrap.md`. | *Adversary analysis:* Two defensible readings of quoting style: (1) double quotes with internal backslash escapes (`\"Given design:\"`); (2) single quotes enclosing the literal string. Differing case: compare the raw file content and parser behavior. Under Reading 1, backslashes must be maintained in the source file, which can be misread or mangled by regex-based re-writers. Under Reading 2, double quotes inside the string remain verbatim without any escape characters, matching the existing quoting style in `.claude/commands/idea.md`. In Python's `yaml.safe_load`, both produce the identical parsed string: `<free text describing the bug: repro, expected vs actual; may include "Given design:", "Given spec:", or "Given code:" sections>`. Single quoting is cleaner and less error-prone. |
| **D3** | **Hermetic contract test and permanent CI gate.** Add `scripts/ci/tests/command_frontmatter_test.sh` asserting that every file matching `.claude/commands/*.md` (and `commands/*.md` when present) contains valid YAML frontmatter that parses cleanly via Python's `yaml.safe_load`, and that the parsed `argument-hint` and `description` keys are non-empty strings. Wire this test into `scripts/ci/compiler_roundtrip.sh`. | *Adversary analysis:* Two defensible readings: (1) manual review-time verification only; (2) automated test script wired into CI. Differing case: a future PR adds `.claude/commands/new.md` containing an unquoted colon in `argument-hint`. Under Reading 1, CI stays green and merges the broken file; under Reading 2, CI fails with exit 1 before merge. Mechanical verification guarantees long-term frontmatter syntax integrity. |
| **D4** | **Living spec impact is none (`Spec-impact: none`).** Updating frontmatter quoting in `.claude/commands/` fixes YAML syntax conformance and does not modify command behavior, arguments, execution logic, or system capabilities. The living spec obligation is satisfied by declaring `Spec-impact: none — frontmatter YAML syntax fix with zero behavioral change to command capabilities` in the pull request body. | Satisfies AGENTS.md and `scripts/ci/spec_check.sh` requirements for PRs touching `scripts/` (for D3's test) without cluttering `docs/SPEC.md` with syntax-only bug fix descriptions. |
| **D5** | **Strict file manifest partitioning.** The implementing pull request is restricted to: `.claude/commands/bug.md`, `.claude/commands/wrap.md`, `scripts/ci/tests/command_frontmatter_test.sh`, `scripts/ci/compiler_roundtrip.sh`, and `intent/425-bug/**`. No files in `commands/**` or `scripts/sync_commands.py` may be touched. | *Adversary analysis:* Two defensible readings: (1) implementer touches only pre-existing files and test scripts; (2) implementer attempts to pre-create `commands/` or modify compilation scripts from #416. Differing case: implementer edits `scripts/sync_commands.py`. Under Reading 2, merge conflicts arise with PR #422; under Reading 1, #425 cleanly unblocks #416 without interfering with parallel in-flight work. |
| **D6** | **Surgical single-line edit preservation.** In both `.claude/commands/bug.md` and `.claude/commands/wrap.md`, only line 3 (`argument-hint:`) is modified. All other lines (lines 1-2, lines 4-5, and markdown body lines 6+) must remain byte-for-byte identical to `origin/main`. | *Adversary analysis:* Two defensible readings: (1) surgical single-line edit; (2) re-formatting or re-wrapping frontmatter keys or markdown prose. Differing case: `git diff -U0 .claude/commands/bug.md` shows changes to `description:` or `allowed-tools:`. Under Reading 2, tool permission patterns or description strings risk unintentional mutation; under Reading 1, `git diff` shows exactly one line changed per command file. |
| **D7** | **Downstream decoupling with issue #416.** Issue #425 merges independently to `main`. Once merged, `origin/main` satisfies #416 D14's prerequisite, allowing #416's implementer to migrate `.claude/commands/bug.md` (and `wrap.md`) byte-for-byte into `commands/` without allowlisting exemptions. | Eliminates circular dependencies between pull requests. #425 does not depend on #416, and #416 can rebase or consume #425's fix once landed. |

## Acceptance

- **AT-425-1 (D1, D2, D6):** In `.claude/commands/bug.md`, line 3 `argument-hint` is formatted as `'<free text describing the bug: repro, expected vs actual; may include "Given design:", "Given spec:", or "Given code:" sections>'`. All other lines in `.claude/commands/bug.md` are byte-identical to `origin/main`.
- **AT-425-2 (D1, D2, D6):** In `.claude/commands/wrap.md`, line 3 `argument-hint` is formatted as `'[<seat-or-slug>] [--snapshot]'`. All other lines in `.claude/commands/wrap.md` are byte-identical to `origin/main`.
- **AT-425-3 (D1, D2):** Running `python3 -c "import yaml; yaml.safe_load(open('.claude/commands/bug.md').read().split('---\n', 2)[1])"` exits 0 and returns a dictionary whose `argument-hint` equals `<free text describing the bug: repro, expected vs actual; may include "Given design:", "Given spec:", or "Given code:" sections>`.
- **AT-425-4 (D1, D2):** Running `python3 -c "import yaml; yaml.safe_load(open('.claude/commands/wrap.md').read().split('---\n', 2)[1])"` exits 0 and returns a dictionary whose `argument-hint` equals `[<seat-or-slug>] [--snapshot]`.
- **AT-425-5 (D3):** Every file matching `.claude/commands/*.md` in the repository parses without error using Python's `yaml.safe_load`.
- **AT-425-6 (D3):** Running `bash scripts/ci/tests/command_frontmatter_test.sh` exits 0 against the repository state, and exits 1 when executed against a simulated command file containing an unquoted colon in `argument-hint`.
- **AT-425-7 (D3):** Running `bash scripts/ci/compiler_roundtrip.sh` executes `scripts/ci/tests/command_frontmatter_test.sh` and exits 0.
- **AT-425-8 (D4):** `bash scripts/ci/spec_check.sh origin/main <(echo "Spec-impact: none — frontmatter YAML syntax fix")` exits 0.
- **AT-425-9 (D5):** `git diff --name-only origin/main` in the implementing PR is strictly a subset of the permitted manifest in D5.

## Open questions

none
