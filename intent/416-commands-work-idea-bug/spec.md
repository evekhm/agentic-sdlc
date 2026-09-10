# Spec: Commands Single Source of Truth and Cross-Harness Compiler with Drift Gate

**Issue:** #416 · **Status:** Approved (approval = merge of this PR) ·
**Author:** athena (`evekhm-athena-app[bot]`) ·
**Open questions:** none

## What is being built

This specification resolves issue #416 by establishing a single source of truth for repository slash commands (`/work`, `/idea`, `/bug`, and future commands like `/wrap`), introducing a deterministic multi-target compiler (`scripts/sync_commands.py`), generating native targets for both Claude Code (`.claude/commands/`) and Google Antigravity (`.agents/skills/`), enforcing a mechanical drift gate in continuous integration (`scripts/ci/compiler_roundtrip.sh`), and protecting command sources under the living-spec gate (`scripts/ci/spec_check.sh`).

### Background and Motivation

In the current codebase, slash commands are authored directly as bespoke Markdown files in the Claude-specific directory `.claude/commands/`:
- `.claude/commands/work.md`: Invokes `scripts/ops/digest.sh` and headless `scripts/ops/work.sh` via Claude Code's pre-turn `!` shell execution.
- `.claude/commands/idea.md`: Conversational intake prompt directing Claude to search the tracker via `scripts/ops/tracker_search.sh` and file an `intent:new` issue via `scripts/ops/intake.sh`.
- `.claude/commands/bug.md`: Conversational intake prompt directing Claude to search the tracker and file an `intent:new` + `bug` issue.

This architecture exhibits three core deficiencies:
1. **Harness Asymmetry:** Commands exist exclusively for Claude Code. Operators and autonomous assistants running on Google Antigravity (`agy`) lack access to these operational doors, despite `agy` supporting workspace skill and slash-command expansion via `.agents/skills/<name>/SKILL.md` (verified in `agy 1.2.0` and `1.1.25+`). Previously, issue #43 D16 intentionally left `.claude/commands/work.md` hand-authored and Claude-only because there was no compiler infrastructure and Claude's pre-turn `!` syntax relied on operator typing rather than a model-composed trust boundary. With #416 introducing the compiler plumbing, #43 D16 is amended to support cross-harness command emission under a hardened trust model.
2. **Missing Source of Truth:** Unlike personas (which are authored canonically in `personas/` and compiled to `.claude/agents/` and `.agents/agents/` via `scripts/sync_agents.py`), commands are hand-edited directly inside their target directories. There is no schema validation, frontmatter linting, or single source of truth.
3. **No Drift Enforcement:** Target command files are not verified by CI. A developer or agent can modify or delete a command file without detection, or introduce drift between harnesses.

### Proposed Architecture

This specification establishes an end-to-end command compilation pipeline mirroring the persona compiler architecture:

```text
                        ┌──────────────────────────────────────────────┐
                        │              Canonical Sources               │
                        │             commands/<name>.md               │
                        │ (work.md, idea.md, bug.md, [future wrap.md]) │
                        └──────────────────────┬───────────────────────┘
                                               │
                                               ▼
                                ┌───────────────────────────────┐
                                │   scripts/sync_commands.py    │
                                │   - Frontmatter validation    │
                                │   - Verbatim scalar emission  │
                                │   - Exec vs Prompt derivation │
                                │   - Complete secret sanitizer │
                                │   - Scoped pruning + allowlist│
                                └───────┬───────────────┬───────┘
                                        │               │
                                        │               │
                      ┌─────────────────┘               └─────────────────┐
                      ▼                                                   ▼
        ┌───────────────────────────┐                       ┌───────────────────────────┐
        │     Claude Code Target    │                       │     Antigravity Target    │
        │ .claude/commands/<name>.md│                       │.agents/skills/<name>/SKILL│
        │(Byte-identical at branch) │                       │ (Hardened native skill)   │
        └───────────────────────────┘                       └───────────────────────────┘
```

1. **Canonical Source Directory (`commands/`):**
   Canonical commands are stored in `commands/<name>.md`. Each source file contains a YAML frontmatter block delimited by `---` with metadata (`description`, optional `argument-hint`, optional `allowed-tools`), followed by the command body.
2. **Dedicated Compiler Script (`scripts/sync_commands.py`):**
   A standalone Python script compiled with standard library modules plus `pyyaml` (and `jsonschema` when available). Supports standard compiler CLI flags: default build, `--check` (dry-run drift verification), and `--root DIR --out DIR` (isolated tree compilation for tests).
3. **Claude Code Emitter:**
   Emits `.claude/commands/<name>.md`. To prevent regressions and satisfy byte-identity requirements, emitted files contain no generated header comments in their frontmatter, and frontmatter keys are emitted verbatim without YAML reflow, matching existing merged targets byte-for-byte upon migration.
4. **Antigravity Emitter (Amending #43 D16):**
   Emits `.agents/skills/<name>/SKILL.md` relative to the workspace root. Frontmatter contains standard `name:` and `description:` along with a `# GENERATED by scripts/sync_commands.py` comment. For `exec` commands (such as `/work`), the emitter translates the `!` shell syntax into an imperative Agent Skill with hardened argument validation (verifying `<number> [--as <persona>]` and rejecting all shell metacharacters before executing `run_command`). For conversational intake prompts (`/idea`, `/bug`), the emitter preserves prompt instructions and argument variables.
5. **CI Drift Gate (`scripts/ci/compiler_roundtrip.sh`):**
   `scripts/ci/compiler_roundtrip.sh` is extended with Step 8 ("Commands compiler roundtrip and drift gate"), asserting ref-free checks:
   - `python3 scripts/sync_commands.py --check` passes against committed targets.
   - Emitted `.agents/skills/{work,idea,bug}/SKILL.md` exist and match canonical sources.
   - Determinism: two consecutive builds produce byte-identical file trees.
   - Throwaway command compilation succeeds in temporary trees.
   - Complete secret/path sanitizer fails closed on source files containing any of the 10 forbidden credential patterns or absolute user home paths.
6. **Scoped Pruning and PR #406 Allowlist:**
   `scripts/sync_commands.py` prunes unmanaged `*.md` files directly under `.claude/commands/` and unmanaged skill directories under `.agents/skills/`. To prevent conflicts with concurrent PR #406 (#85 implement), `.claude/commands/wrap.md` is explicitly allowlisted until its canonical migration occurs.
7. **Living Spec Protection (`scripts/ci/spec_check.sh`):**
   `commands/*` is added to the list of behavior-bearing source paths in `scripts/ci/spec_check.sh`.

### File Manifest

```text
commands/work.md                                  # canonical source for /work command
commands/idea.md                                  # canonical source for /idea command
commands/bug.md                                   # canonical source for /bug command
scripts/sync_commands.py                          # deterministic commands compiler script
.claude/commands/work.md                          # compiled Claude Code target (byte-identical)
.claude/commands/idea.md                          # compiled Claude Code target (byte-identical)
.claude/commands/bug.md                           # compiled Claude Code target (byte-identical)
.agents/skills/work/SKILL.md                      # compiled Antigravity Agent Skill target (hardened)
.agents/skills/idea/SKILL.md                      # compiled Antigravity Agent Skill target
.agents/skills/bug/SKILL.md                       # compiled Antigravity Agent Skill target
scripts/ci/compiler_roundtrip.sh                  # extended with Step 8 commands roundtrip check (ref-free)
scripts/ci/spec_check.sh                          # commands/* added to behavior-bearing paths
docs/SPEC.md                                      # living spec update under commands.compiler
AGENTS.md                                         # cross-harness slash command usage documentation
CLAUDE.md                                         # Claude-specific slash command reference
GEMINI.md                                         # Antigravity-specific slash command & skill reference
scripts/ci/tests/sync_commands_test.py            # contract & unit tests for command compiler
intent/416-commands-work-idea-bug/intent.md       # intent artifact
intent/416-commands-work-idea-bug/spec.md         # this specification
intent/43-harness-agnostic-launch/spec.md         # amendment note recording D16's amendment (D5)
```

## Decisions

| ID | Decision | Rationale |
|---|---|---|
| D1 | **Canonical Command Sources in `commands/<name>.md` with YAML Frontmatter.** Canonical command sources live in `commands/<name>.md`. The filename stem `<name>` defines the command's canonical identifier (e.g., `work`, `idea`, `bug`). Each source file begins with a YAML frontmatter block delimited by `---` containing: mandatory `description` (non-empty string), optional `argument-hint` (string describing parameter syntax), and optional `allowed-tools` (string or list of strings). The content following the closing `---` constitutes the command body. | Markdown with YAML frontmatter is the native format for prompt templates and instructions across both harnesses. It avoids string escaping, newline manipulation, and quote indentation errors associated with embedding multi-line markdown prompts inside pure YAML files. |
| D2 | **Zero-Regression Byte-Identical Emission on Claude Code.** When emitting `.claude/commands/<name>.md`, `scripts/sync_commands.py` formats frontmatter deterministically as literal key-value strings following `sync_agents.py:688-695` (avoiding `yaml.safe_dump` reflowing, line-wrapping of long scalars, or escaping of em-dashes), followed by the exact body text. The emitted `.claude/commands/<name>.md` files for `work.md`, `idea.md`, and `bug.md` MUST match their counterparts on `main` at the implementation head byte-for-byte (`git diff .claude/commands/` is empty). Specifically, NO `# GENERATED...` comment line is inserted into the Claude target frontmatter, preserving pristine compatibility with Claude Code's command parser. | Prevents silent parse failures or unintended behavior changes in Claude Code. Preserving byte-identity guarantees zero regression during migration without pinning to an ephemeral commit SHA. |
| D3 | **Execution Mode Derivation (`exec` vs `prompt`).** The compiler automatically determines command execution mode by inspecting the first non-whitespace line of the command body: if it begins with `!` (backtick-enclosed shell invocation, e.g. `!\`scripts/ops/...\``), the command is classified as `kind: exec`; otherwise, it is classified as `kind: prompt`. No redundant `type:` or `kind:` field is required in frontmatter. | Deriving execution mode directly from body syntax respects established Claude conventions while eliminating boilerplate. |
| D4 | **Antigravity Target Structure in `.agents/skills/<name>/SKILL.md`.** For each canonical command `commands/<name>.md`, the compiler emits an Antigravity Agent Skill target at `.agents/skills/<name>/SKILL.md` relative to the workspace root, verified against Antigravity workspace skills discovery (`agy 1.2.0`). The frontmatter contains, as its first line inside the opening `---`, the provenance comment `# GENERATED by scripts/sync_commands.py — edit commands/, not this file`, followed by `name: <name>` and `description: <description>` — matching `scripts/sync_agents.py:685-689`'s precedent, where the marker sits inside the frontmatter block because `---` must be at byte 0. | Antigravity discovery (`agy`) natively parses `.agents/skills/<name>/SKILL.md` in the workspace root for slash commands and skill expansion. |
| D5 | **Antigravity Execution Semantics and Trust Hardening (Amending #43 D16).** Issue #43 D16 previously kept `.claude/commands/work.md` hand-authored and Claude-only because `$ARGUMENTS` in Claude's pre-turn `!` execution was operator-typed rather than model-composed, and there was no compiler. With #416 establishing the compiler, #43 D16 is explicitly amended: `/work` receives a native Antigravity skill target at `.agents/skills/work/SKILL.md` under a hardened trust model. Because Antigravity executes tools inside the model inference loop via `run_command`, the emitted skill MUST NOT pass raw unescaped prompt text into a shell. The Antigravity emitter unwraps the `!` shell expression and generates strict instructions: (1) validate that the input argument matches `<number> [--as <persona>]` where `<number>` contains only digits; (2) strictly reject any input containing shell metacharacters (`;`, `&`, `|`, `` ` ``, `$`, `(`, `)`, `<`, `>`, `\n`, etc.); (3) invoke `HEADLESS=1 scripts/ops/work.sh <number> [--as <persona>]` via `run_command` and report output. | Bridges the architectural gap between Claude Code's pre-turn shell hook and Antigravity's model-driven tool execution. This is defense-in-depth, not a new security boundary: Antigravity's model already holds `run_command` and could invoke it directly regardless of skill wording, so the emitted validation instructions constrain how the model is guided to use a capability it already has, addressing the shell-injection framing raised in #43 D16 without claiming to eliminate the underlying risk. |
| D6 | **Antigravity Intake Semantics for `prompt` Commands, and `allowed-tools` Scope.** For `prompt` commands (such as `/idea` and `/bug`), the Antigravity emitter retains the canonical prompt instructions. In `.agents/skills/<name>/SKILL.md`, it includes a usage header specifying the command usage and explaining that `$ARGUMENTS` represents the user's raw input following the slash command. `allowed-tools` is Claude-only: `agy`'s Agent Skill frontmatter has no per-skill tool-grant field to map it onto, so the Antigravity emitter intentionally omits `allowed-tools` from the emitted `SKILL.md` frontmatter for every command, including `/idea` and `/bug`. | Ensures Gemini has the full context required to execute tracker searches and invoke `scripts/ops/intake.sh`. Explicitly resolves intent.md's open question 5 (tool-permission mapping) instead of leaving it implicit. |
| D7 | **Dedicated Compiler Script (`scripts/sync_commands.py`).** Command compilation is implemented in a dedicated script `scripts/sync_commands.py`, separate from `scripts/sync_agents.py`. The script accepts `--check` (rebuilds in memory and diffs against disk without writing; exits 0 on match, exit 1 on drift), `--root DIR` (custom repository root), and `--out DIR` (custom output root for testing). Input files are processed in lexicographical order. Output files are formatted deterministically. | Keeps `scripts/sync_agents.py` focused exclusively on personas, model tiers, and subagents. Slash commands have different lifecycles, targets, and execution models. |
| D8 | **Complete Secret Leak and Path Sanitizer Parity.** `scripts/sync_commands.py` incorporates the identical secret and path sanitizer patterns (`SECRET_PATTERNS` and `sanitize()`) as `scripts/sync_agents.py`, either by importing them directly from `scripts/sync_agents.py` or sharing the module. All 10 patterns are checked: `/home/`, `/Users/`, a literal reference to the `HOME` environment variable, `~/.`, `gh[pousr]_`, `github_pat_`, `AKIA`, `sk-`, `xox[baprs]-`, private key blocks, and inline credential values. If any emitted target contains a forbidden pattern, compilation aborts with exit status 1 and writes nothing. | Prevents credential leaks and non-hermetic machine path pollution in committed command targets, guaranteeing zero sanitizer drift between compilers. |
| D9 | **Target Directory Ownership, Scoped Pruning, and `wrap.md` Allowlist.** The target directories `.claude/commands/` and `.agents/skills/` are managed by `scripts/sync_commands.py`. Pruning in `.claude/commands/` is strictly scoped to `*.md` files directly in `.claude/commands/` (excluding non-.md files and subdirectories). Pruning in `.agents/skills/` is scoped to directories matching skills created by canonical commands. **Allowlist:** To prevent collisions with concurrent PR #406 (#85 implement), `.claude/commands/wrap.md` is explicitly allowlisted: `sync_commands.py` will not prune it and `sync_commands.py --check` will not flag it as drift, pending migration under issue #85. Under `--check`, any non-allowlisted extraneous or orphaned file in target directories triggers a drift error (exit 1). | Eliminates stale or orphaned commands while cleanly decoupling parallel development of `/wrap` in PR #406. |
| D10 | **Ref-Free Compiler Roundtrip and CI Gate Integration.** `scripts/ci/compiler_roundtrip.sh` is extended with Step 8 ("Commands compiler roundtrip and drift gate"). Step 8 is entirely ref-free (contains no `git` invocations and does not depend on fetching `origin/main`), asserting: (1) `python3 scripts/sync_commands.py --check` exits 0; (2) emitted `.agents/skills/{work,idea,bug}/SKILL.md` exist and match canonical sources; (3) two consecutive compiles in a temp tree produce byte-identical trees; (4) a throwaway command in a temporary tree compiles to both targets; (5) a command source containing an absolute home directory or token pattern fails the sanitizer. (Byte-identity against baseline is verified during migration in AT-416-2 at the implementation head). | Guarantees mechanical enforcement of compiler determinism and drift prevention in CI without fragile git ref dependencies. |
| D11 | **Living Spec Gate Protection (`scripts/ci/spec_check.sh`).** `scripts/ci/spec_check.sh` is updated to include `commands/*` under behavior-bearing paths (`.github/workflows/*|scripts/*|personas/*|config/*|commands/*`). Any pull request altering files in `commands/` must update `docs/SPEC.md` or provide a `Spec-impact: none` marker. | Ensures all command behavior changes are tracked in the living specification per repository standards. |
| D12 | **Scope Boundary, Ordering Dependency, and Migration with PR #406 (#85).** Issue #416 migrates only existing merged commands: `work`, `idea`, and `bug`. Authoring and delivering `/wrap` remains strictly scoped to issue #85 (`intent/85-session-close-out/`, PR #406), whose committed plan (`intent/85-session-close-out/plan.md:124`) does not permit touching `commands/wrap.md` and cannot be widened by this spec. If #416 lands first, D9's allowlist protects PR #406 from drift failures and `wrap.md` stays allowlisted; #416's implement rung does NOT migrate `wrap.md` on #406's behalf. If PR #406 lands first, #416's implement rung performs the mechanical migration of `.claude/commands/wrap.md` into `commands/wrap.md` byte-identically and removes it from D9's allowlist. Either way, migrating `wrap.md` while #406 is still open is a follow-up issue under #85, not a task either PR performs on the other's files. So the allowlist obligation is not silently indefinite, #416's implement rung files that follow-up issue under #85 and updates D9's allowlist comment to cite its number. | Prevents circular dependencies, broken gates, and scope creep across parallel feature tracks, without assuming #406 can widen its own committed plan. |
| D13 | **Implementation Scope Boundary.** The implementing pull request for #416 may touch `commands/**`, `scripts/sync_commands.py`, `.claude/commands/**`, `.agents/skills/**`, `scripts/ci/compiler_roundtrip.sh`, `scripts/ci/spec_check.sh`, `scripts/ci/tests/**`, `docs/SPEC.md`, `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, `intent/43-harness-agnostic-launch/spec.md` (solely to record D16's amendment note per D5), and `intent/416-commands-work-idea-bug/**`. It may NOT modify the behavioral logic of `scripts/ops/digest.sh`, `scripts/ops/work.sh`, `scripts/ops/intake.sh`, or `scripts/ops/tracker_search.sh`. | Strictly fences implementation diff to compilation plumbing, living specs, and cross-harness documentation. |
| D14 | **Pre-Existing `bug.md` Frontmatter Defect and Migration Prerequisite.** `.claude/commands/bug.md` on `main` today contains an unescaped `: ` inside its `argument-hint` plain scalar (line 3), which is not valid YAML and cannot satisfy D1's frontmatter validation: migrating it verbatim fails parsing (AT-416-1), and rewording it to parse breaks D2's byte-identity clause (AT-416-2). This defect is pre-existing and independent of #416's design — fixing `.claude/commands/bug.md` (quoting the `argument-hint` scalar) is out of Athena's `intent/**` authority for this design rung and is filed as #425, a separate, narrowly-scoped issue against the existing file, not part of #416's diff. #416's implement rung migrates `commands/bug.md` only once that prerequisite fix has landed on `main`, measuring AT-416-1/AT-416-2 byte-identity against the corrected content. If the prerequisite has not landed by the time #416 implements, the implement rung migrates `work.md` and `idea.md` and adds `bug.md` to D9's allowlist mechanism (same treatment as `wrap.md`) until the prerequisite merges, rather than blocking the whole PR on an unrelated pre-existing bug. | Keeps the D1/D2 contradiction visible as a Decision instead of leaving an implementer to invent a resolution mid-implementation (Argus R1-1); scopes the actual code fix outside this design rung's authority, consistent with D13. |

## Acceptance

- **AT-416-1 (D1, D7, D14)** Verify canonical command sources exist in `commands/`: `commands/work.md` and `commands/idea.md` always; `commands/bug.md` once D14's prerequisite fix has landed on `main` (otherwise `bug.md` is exempt via D9's allowlist mechanism, per D14). Each present file contains valid YAML frontmatter with a non-empty `description` field.
- **AT-416-2 (D2, D7, D14)** Run `python3 scripts/sync_commands.py`: emitted files `.claude/commands/work.md` and `.claude/commands/idea.md` are byte-for-byte identical to the baseline versions on `main` (`git diff .claude/commands/` is empty at implementation head). For `.claude/commands/bug.md`, byte-identity is measured against `main`'s content after D14's prerequisite fix lands; until then `bug.md` is exempt per D14. Frontmatter scalars are emitted verbatim without `yaml.safe_dump` re-wrapping or unicode escaping.
- **AT-416-3 (D4, D7, D14)** Run `python3 scripts/sync_commands.py`: emitted files `.agents/skills/work/SKILL.md` and `.agents/skills/idea/SKILL.md` always exist and carry YAML frontmatter containing `name`, `description`, and the generated comment `# GENERATED by scripts/sync_commands.py — edit commands/, not this file`; `.agents/skills/bug/SKILL.md` exists under the same terms as `commands/bug.md` per D14.
- **AT-416-4 (D3, D5)** In `.agents/skills/work/SKILL.md`, mechanically grep for: (1) the literal substring `<number> [--as <persona>]` describing the accepted argument shape; (2) an explicit list of forbidden shell metacharacters containing `;`, `&`, `|`, `` ` ``, and `$`; (3) the literal substring `HEADLESS=1 scripts/ops/work.sh` and `run_command`. No model reading is required.
- **AT-416-5 (D3, D6)** In `.agents/skills/idea/SKILL.md` and `.agents/skills/bug/SKILL.md`, the body contains intake search instructions (`tracker_search.sh`) and issue creation instructions (`intake.sh`), preserving the conversational intake flow.
- **AT-416-6 (D7, D10)** Run `python3 scripts/sync_commands.py --check`: exits 0 against the repository state. Modifying any character in `.claude/commands/work.md` causes `--check` to exit 1 with a per-file drift summary.
- **AT-416-7 (D9, D10)** Creating an extraneous file `.claude/commands/orphan.md` causes `python3 scripts/sync_commands.py --check` to exit 1. Running `python3 scripts/sync_commands.py` prunes `.claude/commands/orphan.md`.
- **AT-416-8 (D8, D10)** Creating a temporary command source in a temp directory containing any of the 10 forbidden credential patterns or an absolute user home path causes `scripts/sync_commands.py` to refuse compilation with exit status 1.
- **AT-416-9 (D10)** Run `bash scripts/ci/compiler_roundtrip.sh`: exits 0, with Step 8 operating without any git invocation or remote ref, proving command compilation determinism, throwaway command roundtrip, and sanitizer refusal.
- **AT-416-10 (D11)** In `scripts/ci/spec_check.sh`, verify that modifying a file in `commands/` without modifying `docs/SPEC.md` causes `spec_check.sh` to report a spec obligation and exit 1 if no `Spec-impact: none` marker is present.
- **AT-416-11 (D12, D13)** Verify that `scripts/ops/digest.sh`, `scripts/ops/work.sh`, `scripts/ops/intake.sh`, and `scripts/ops/tracker_search.sh` are not modified.
- **AT-416-12 (D11, D13)** Mechanically grep, no model reading required: `docs/SPEC.md` contains the literal heading `### commands.compiler`, and the terms `commands/<name>.md`, `.agents/skills/`, and `sync_commands.py` all appear somewhere under it; `AGENTS.md`, `CLAUDE.md`, and `GEMINI.md` each contain the literal substring `sync_commands.py`.
- **AT-416-13 (D9, D12)** Verify that creating a hand-authored `.claude/commands/wrap.md` does not cause `python3 scripts/sync_commands.py --check` to fail, and running `python3 scripts/sync_commands.py` does not prune it, satisfying the D9 allowlist pending migration of issue #85.

## Concerns

- **Claude Code Frontmatter Sensitivity:** Claude Code's slash-command loader parses YAML frontmatter in `.claude/commands/*.md`. Any unexpected keys or comments could cause command registration to fail. Decision D2 addresses this by preserving exact frontmatter keys (`description`, `argument-hint`, `allowed-tools`), formatting scalars verbatim (avoiding pyyaml reflow/escaping issues), and omitting header comments in `.claude/commands/`, guaranteeing byte-identity.
- **Antigravity Execution Parity & Injection Protection:** Claude Code's `!` prefix executes shell commands outside the model's inference loop. In Antigravity, tools run inside the model loop via `run_command`. Decision D5 addresses this by amending #43 D16 to establish a hardened trust model: rather than interpolating unquoted shell variables into a bash command, the Antigravity skill explicitly enforces argument structure (digits-only issue number, valid persona flag) and rejects shell metacharacters before calling `run_command`.
- **Target Pruning and Parallel Feature Tracks:** If a user or parallel branch stores non-command files in `.claude/commands/`, automated pruning could delete them. Decision D9 strictly scopes pruning to `*.md` files directly under `.claude/commands/` and skill directories under `.agents/skills/`. Furthermore, Decision D9 and D12 explicitly allowlist `.claude/commands/wrap.md` to cleanly decouple from PR #406 (#85 implement), ensuring neither PR blocks or breaks the other regardless of merge order.
- **Secret Leakage in Prompts:** Slash command bodies could inadvertently embed user-specific paths or environment details. Decision D8 enforces full parity with `sync_agents.py`, checking all 10 secret and path patterns.
- **Ref-Free CI Gate:** Step 8 in `scripts/ci/compiler_roundtrip.sh` is strictly ref-free (contains no `git diff origin/main` checks), preventing false-positive CI failures across branches and allowing deliberate command updates in future PRs.

## Out of scope

- Redesigning the underlying implementation or behavior of `scripts/ops/work.sh`, `digest.sh`, `intake.sh`, or `tracker_search.sh`.
- Authoring or delivering `/wrap` (owned by issue #85 / PR #406).
- Modifying persona definitions or compiler logic in `scripts/sync_agents.py`.
- Adding interactive GUI or web interfaces for slash commands.

## Operator decisions

All open questions from `intent.md` and adversarial interrogation findings have been resolved by numbered decisions in this specification:
1. *Canonical Source Format:* Resolved by D1. Markdown with YAML frontmatter (`commands/<name>.md`).
2. *Antigravity Target Format:* Resolved by D4. Native Agent Skills in `.agents/skills/<name>/SKILL.md` discovered at workspace root (`agy 1.2.0`).
3. *Execution Model, Argument Substitution & Trust Hardening:* Resolved by D3, D5, and D6. Automatic derivation of `exec` vs `prompt` based on leading `!` syntax. D5 explicitly amends #43 D16, replacing bare shell interpolation in Antigravity with strict parameter validation and metacharacter refusal before invoking `run_command`.
4. *Compiler Architecture & Complete Sanitizer:* Resolved by D7 and D8. Dedicated standalone script `scripts/sync_commands.py` with full 10-pattern sanitizer parity with `sync_agents.py`.
5. *Tool Permissions Mapping & Claude Frontmatter Formatting:* Resolved by D2 and D6. Verbatim scalar formatting without YAML reflow preserves byte-identity on Claude Code; `allowed-tools` is intentionally Claude-only and omitted from the Antigravity target, since `agy`'s skill format has no per-skill tool-grant field to map it onto.
6. *Parallel Feature Decoupling (/wrap & PR #406):* Resolved by D9, D12, and AT-416-13. Explicit allowlisting of `.claude/commands/wrap.md` prevents pruning or drift failures regardless of whether PR #406 or PR #422 merges first.
7. *Ref-Free CI Gate:* Resolved by D10. Step 8 of `scripts/ci/compiler_roundtrip.sh` is entirely ref-free, ensuring determinism and hermetic CI execution.
8. *Pre-Existing `bug.md` Frontmatter Defect:* Resolved by D14. `.claude/commands/bug.md`'s invalid YAML on `main` is a pre-existing bug outside this design rung's authority; migrating `bug.md` is deferred to a separate prerequisite fix landing first, with `bug.md` exempt via D9's allowlist mechanism until then.

Open questions: none
