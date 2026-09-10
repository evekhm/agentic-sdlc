# Intent: Commands single source of truth and cross-harness compiler with drift gate

**Issue:** #416 · **Stage:** plan · **Author:** athena (`evekhm-athena-app[bot]`) · **Status:** accepted on merge of this PR

## Problem

Slash commands in this repository (`/work`, `/idea`, `/bug`, and the upcoming `/wrap` from #85) are currently hand-authored Markdown files stored directly inside `.claude/commands/`.

This setup exhibits three major issues:

1. **Claude-Only Asymmetry (Harness Drift):** None of the current commands have an Antigravity (`agy`) equivalent. An operator or automated session interacting with Antigravity has no slash command or skill doors for intake (`/idea`, `/bug`) or execution dispatch (`/work`). Every command added to date is Claude-only, drifting the exact same way persona prompts drifted before `scripts/sync_agents.py` existed (#5, #6).
2. **Direct Hand-Authoring in Target Locations:** Command files are authored directly in their deployment destination (`.claude/commands/`). For personas, the repository established that target directories (`.claude/agents/`, `.agents/agents/`) are derived build artifacts, while `personas/*.yaml` and `config/*.yaml` are the single source of truth. Commands currently violate this principle, with no canonical source definition or schema.
3. **Absence of a Mechanical Drift Gate:** Because commands have no canonical source and compiler, there is no CI check verifying that command definitions match across harnesses or remain synchronized with repository standards. Any future command (such as `/wrap` from #85 or new workflow triggers) must either be manually duplicated across harness formats without mechanical validation, or risk never being ported to Antigravity at all.

## Proposed outcome

1. **Canonical Source-of-Truth for Commands:**
   - Establish a dedicated source directory (e.g. `commands/`, sibling to `personas/`), containing one canonical definition per command (e.g., `commands/<name>.md` with frontmatter or `commands/<name>.yaml`).
   - Define command metadata (name, description, argument hints, required tool permissions) and execution instructions/script calls in a harness-neutral representation.
2. **Harness-Agnostic Compiler:**
   - Extend the compiler pipeline (either within `scripts/sync_agents.py` or via a modular sibling compiler `scripts/sync_commands.py`) to compile each canonical command into per-harness targets:
     - **Claude Code:** `.claude/commands/<name>.md` with frontmatter (`description`, `argument-hint`, `allowed-tools`) and body verbatim.
     - **Antigravity / Gemini:** The native Antigravity equivalent (e.g. `.agents/skills/<name>/SKILL.md` or `.agents/workflows/<name>.md` or generated command rules in `GEMINI.md`) enabling slash-command and skill expansion in `agy`.
3. **Byte-Identical Migration of Existing Commands:**
   - Migrate currently committed Claude Code commands (`work.md`, `idea.md`, `bug.md`) into the new canonical format.
   - Verify that the compiler generates outputs for Claude Code that are byte-identical to the currently committed files, ensuring zero operational regression.
4. **Hard CI Drift Gate Enforcement:**
   - Wire a "rebuild and diff" drift gate into `.github/workflows/ci-gates.yml` (and `scripts/ci/compiler_roundtrip.sh`), mirroring the persona drift check.
   - Any manual edit to `.claude/commands/` or `.agents/` or failure to commit compiled artifacts will fail CI closed.
5. **Living Spec and Governance Updates:**
   - Upsert `docs/SPEC.md` under the compiler and command capability sections to specify the canonical source location, compilation pipeline, target paths, and drift gate rules.
   - Update `AGENTS.md`, `CLAUDE.md`, and `GEMINI.md` to document command authoring practices and cross-harness command usage.

## Affected users and systems

- **Interactive Operators & Sessions:** Can invoke the full command suite (`/work`, `/idea`, `/bug`, `/wrap`) with consistent syntax and behavior whether working in Claude Code or Antigravity.
- **Implementers & Authors:** Define commands once in `commands/`; never hand-edit files in target directories like `.claude/commands/`.
- **Compiler Pipeline (`scripts/sync_agents.py` / `scripts/sync_commands.py`):** Extended to parse command definitions and emit per-harness targets.
- **CI Gates (`.github/workflows/ci-gates.yml`, `scripts/ci/compiler_roundtrip.sh`):** Enforces mechanical drift checks across all command targets.
- **Merge Gate & Spec Check (`scripts/ci/spec_check.sh`, `merge_gate.sh`):** Recognizes `commands/**` as behavior-bearing source files requiring spec updates on change.
- **Repository Standards:** `docs/SPEC.md`, `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`.

## Constraints

- **Byte-Identical Output on Claude Code:** The compiler must emit `.claude/commands/work.md`, `idea.md`, and `bug.md` byte-identical to current `main` upon initial migration.
- **Plumbing Scope Boundary:** This issue delivers the compilation plumbing, source location, and drift gate. It does NOT redesign the behavior of `/work`, `/idea`, or `/bug`, and does NOT implement `/wrap` (which remains scoped to #85).
- **Harness-Neutral Sources:** Canonical sources must not contain hardcoded harness-specific leakage without appropriate abstraction.
- **Fail-Closed Drift Check:** CI must fail closed if target files are hand-edited or drift from canonical sources.
- **Standard 5-Rung SDLC Lifecycle:** At the PLAN gate, only `intent/<issue>-<slug>/intent.md` is authored and committed. Design choices (e.g. source format, Antigravity expansion mechanism) remain open questions for the DESIGN stage (spec.md).

## Relationships

- **Mirrors #5 & #6 (Persona Compiler & CI Drift Gate):** Adopts the proven single-source-of-truth + rebuild-and-diff architecture established for personas.
- **Extends #407 / PR #409 (Manual Intake Doors):** Migrates the intake commands (`/idea`, `/bug`) and the `/work` pre-dispatch digest into the compiled workflow.
- **Unblocks #85 (Session Close-Out /wrap):** Provides the compilation and drift infrastructure required for `/wrap` to ship simultaneously on both harnesses.
- **Aligns with #43 (Harness-Agnostic Launch):** Ensures command doors exist and operate symmetrically across all supported execution harnesses.

## Open questions

1. **Canonical Source Format (YAML vs Markdown):** Should canonical command sources be pure YAML files (e.g. `commands/<name>.yaml`, validated against a JSON schema like `personas/schema.json`) or Markdown files with YAML frontmatter (e.g. `commands/<name>.md`)?
2. **Antigravity Delivery Target:** What is the idiomatic target format for Antigravity commands? Does `agy` expand slash commands via `.agents/skills/<name>/SKILL.md` (Agent Skills spec), `.agents/workflows/<name>.md`, or through a generated section in `GEMINI.md`?
3. **Execution Model & Argument Substitution:** Claude Code uses `$ARGUMENTS` in prompt markdown and supports immediate shell execution via `!` in `work.md`. How should non-conversational shell execution vs conversational intake prompts be modeled across harnesses?
4. **Compiler Architecture:** Should command compilation be integrated into `scripts/sync_agents.py` (broadening its scope and `TARGET_DIRS`) or split into a dedicated `scripts/sync_commands.py` called by a unified build/check runner?
5. **Tool Permissions Mapping:** Claude Code commands specify `allowed-tools: Bash(...)`. How should tool authorizations and permission grants be declared in canonical command sources and mapped to Antigravity runtime settings?
