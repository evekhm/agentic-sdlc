# Intent: Fix invalid YAML frontmatter in .claude/commands/bug.md

**Issue:** #425 · **Stage:** plan · **Author:** athena (`evekhm-athena-app[bot]`) · **Status:** Accepted

## Problem

The slash command `.claude/commands/bug.md` contains invalid YAML frontmatter. Specifically, line 3 defines `argument-hint` as an unquoted plain scalar containing an unescaped colon-space (`: `):

```yaml
argument-hint: <free text describing the bug: repro, expected vs actual; may include "Given design:", "Given spec:", or "Given code:" sections>
```

Under YAML 1.2 specifications, an unquoted plain scalar cannot contain a mapping indicator (`: `). When parsed by standard YAML parsers (such as Python's PyYAML `yaml.safe_load`), the parser expects a mapping value and fails immediately:

```text
$ python3 -c "import yaml; yaml.safe_load(open('.claude/commands/bug.md').read().split('---\n',2)[1])"
yaml.scanner.ScannerError: mapping values are not allowed here
  in "<unicode string>", line 2, column 45:
     ... t: <free text describing the bug: repro, expected vs actual; may ... 
                                         ^
```

While Claude Code's native frontmatter reader currently tolerates or splits this line without throwing a fatal runtime error during interactive `/bug` usage, strict YAML parsers reject it completely.

### The Downstream Blocker for Issue #416

This defect is pre-existing on `main` (introduced when `/bug` landed in PR #409) and was uncovered during independent review of PR #422 (the design specification for #416, Commands single source of truth and cross-harness compiler, finding `R1-1@D1`). 

Under #416, command source files are ingested from `commands/*.md` and compiled into target formats (`.claude/commands/` and `.agents/skills/`). Furthermore, #416 D2 requires that the compiler emit Claude Code target files that are byte-for-byte identical to baseline on `origin/main`. Because `.claude/commands/bug.md` cannot be ingested by a strict YAML compiler, #416's spec Decision D14 was forced to defer migrating `bug.md` into the compiler source tree until this syntax defect is resolved independently on `main`.

### Sibling Defect in `.claude/commands/wrap.md`

As surfaced by Odyssey's verifier check on issue #425, `.claude/commands/wrap.md` (which landed on `main` via PR #406) exhibits an identical class of YAML frontmatter syntax failure on its `argument-hint` field:

```yaml
argument-hint: [<seat-or-slug>] [--snapshot]
```

In YAML, a plain scalar starting with `[` is interpreted as a flow sequence indicator. The parser reads `[<seat-or-slug>]` as a flow sequence and then encounters a subsequent bracket on the same line, throwing `yaml.parser.ParserError: expected <block end>, but found '['`. Like `bug.md`, `wrap.md` parses in Claude Code today but fails any strict YAML parser and faces the same compiler ingestion blocker.

## Proposed outcome

1. **Strictly Valid YAML Frontmatter:**
   - Format the `argument-hint` scalar in `.claude/commands/bug.md` so that it parses cleanly under strict YAML parsers (e.g. `yaml.safe_load` exits cleanly with code 0).
   - Ensure the parsed value of `argument-hint` evaluates to the exact intended string scalar without alteration of meaning or prompt semantics.

2. **Zero Functional or Behavioral Regression in Claude Code:**
   - The `/bug` slash command must continue to display its argument hint correctly and function identically in interactive Claude Code sessions.

3. **Unblock Command Compiler Migration (#416):**
   - Provide a clean, strictly-valid baseline for `bug.md` on `main`, enabling #416 (or its subsequent follow-ups) to migrate `bug.md` into `commands/` under byte-identical generation requirements.

4. **Automated Verification:**
   - Include automated contract tests or verification commands ensuring `python3 -c "import yaml; yaml.safe_load(...)"` passes for `bug.md`.

## Affected users and systems

- **Command Users & Operators:** Users invoking `/bug` (and `/wrap` if addressed) in Claude Code.
- **Cross-Harness Command Compiler (#416):** Ingests command frontmatter to emit per-harness files; requires valid YAML metadata.
- **CI Gates & Linters:** Any current or future YAML frontmatter linting or roundtrip checks in `scripts/ci/`.
- **Repository Documentation & Governance:** `docs/SPEC.md` if command frontmatter parsing rules are formalized.

## Constraints

- **Semantic Invariance:** The text of `argument-hint` seen by the user must not change; only quoting or escaping necessary to conform to YAML syntax may be applied.
- **Fail-Closed Verification:** Verification must assert clean exit code from a strict YAML parser (`yaml.safe_load`).
- **Standard 5-Rung SDLC Lifecycle:** At this PLAN stage, only `intent/<issue>-<slug>/intent.md` is authored. No code, command files, or scripts are edited in this PR.

## Relationships

- **Prerequisite for #416 (Commands Compiler):** Resolves the blocking dependency cited in #416 Decision D14 and Argus review finding `R1-1@D1` on PR #422.
- **Extends PR #409 (Manual Intake Doors):** Fixes the frontmatter defect introduced in `.claude/commands/bug.md` when PR #409 merged.
- **Related to PR #406 / Issue #85 (Session Close-Out):** `.claude/commands/wrap.md` introduced in PR #406 has a sibling frontmatter parsing failure.
- **Supersedes Issue #424:** Closed as duplicate of #425.

## Open questions

1. **Scope Boundary (bug.md alone vs. all command files):**
   Should this issue remain strictly bounded to `.claude/commands/bug.md` as originally titled and filed (rapidly unblocking #416 D14), or should DESIGN and BUILD expand the scope to also fix the sibling frontmatter failure in `.claude/commands/wrap.md`?
2. **Quoting Style for YAML Scalar:**
   Should the `argument-hint` value be enclosed in double quotes with internal escaped double quotes (`argument-hint: "<free text describing the bug: repro, expected vs actual; may include \"Given design:\", \"Given spec:\", or \"Given code:\" sections>"`), single quotes, or a folded block scalar (`argument-hint: >-`)?
3. **Mechanical Frontmatter CI Gate:**
   Should the repository introduce a permanent CI lint step (e.g. in `scripts/ci/compiler_roundtrip.sh` or a dedicated script) that verifies all `.claude/commands/*.md` and `commands/*.md` files have valid YAML frontmatter, preventing unquoted syntax errors from landing in future commands?
4. **Living Spec Upsert Obligation:**
   Does updating frontmatter quoting in `.claude/commands/` constitute a behavior-bearing change requiring an update to `docs/SPEC.md` (e.g., under command syntax specifications), or is it a non-behavior-bearing bug fix that satisfies `Spec-impact: none`?
