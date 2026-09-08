# Plan: trusted-posting rule 1 names the posting script

**Issue:** #98 · **Spec:** spec.md (Approved, D1–D4, AT-1..AT-6) ·
**Author:** daedalus (`evekhm-daedalus-app[bot]`)

Three tasks. Each names the files it touches, the steps in order, the Decision rows it implements, the acceptance tests it makes pass, and its done-when. **Implement on top of `origin/main` at the SHA the dispatcher pins; this plan was verified at `dfe7d56`.**

**One verified correction to the spec's citations.**
The spec cites `docs/SPEC.md:853-867` for the `post.sh` capability at both D4 and Out of scope. At `dfe7d56`, that section is `docs/SPEC.md:932-947`.

**Resolution to build rung tension:** The build rung typically produces failing contract tests in `scripts/ops/tests/` to prove behavior. However, D4 explicitly forbids touching `tests/**` or writing new test files. Consequently, no new test files are written. The acceptance criteria (AT-1 through AT-6) are deterministic shell assertions (e.g. `grep` and the agent compiler) run directly against the tree.

Order: T1 (skill file edit) → T2 (compiler sync) → T3 (gates and boundaries). T1 and T2 must happen in order because T2 compiles the result of T1. T3 runs last because it checks the final tree.

---

## T1 · Update Rule 1 text — D1, D2, D3

Touch: `personas/skills/trusted-posting.md`

1. **Verify D2 (Rule 4 unchanged).** Before any edits, ensure Rule 4 is exactly as verified at `dfe7d56` (`personas/skills/trusted-posting.md:22-26`):
   ```markdown
   4. **Degrade gracefully.** If the preferred write fails
      (permissions, API), fall down the ladder — full review →
      comment with inline detail → summary comment → issue comment —
      and report which rung you landed on. Never retry by switching
      identities.
   ```
   Do not modify this text.

2. **Replace Rule 1.** Replace lines 9-11 with the exact verbatim text from D3, wrapped as needed as long as the content matches exactly. The spec's exact replacement text is:
   ```markdown
   1. **Vetted steps only.** All comment posting on issues and pull requests goes through `scripts/ops/post.sh <number> --as <persona> --body-file <path>`, never ad-hoc API calls composed inline. The body is always a file (there is deliberately no `--body` flag). `hold` is re-read immediately before the write across the target and any closed issues (#25 D13/D14); a hold-suppressed post exits 0 with a notice and must not be retried. The script owns authentication, attribution verification, and escaping.
   ```

**Decisions:** D1, D2, D3.
**Acceptance:** AT-1. Before this task, `grep -F "scripts/ops/post.sh <number> --as <persona> --body-file <path>" personas/skills/trusted-posting.md` exits 1 (fails). After this task, it exits 0 (passes).
**Done when:** The `grep` assertion above succeeds, and Rule 4 remains untouched.

---

## T2 · Compiler synchronization — D4

Touch: `.claude/agents/*.md`, `.agents/agents/*/agent.md`

1. **Regenerate compiled targets.** Run `python3 scripts/sync_agents.py` to propagate the modified `trusted-posting.md` into the compiled persona profiles.

**Decisions:** D4.
**Acceptance:** AT-4. Before this task, `grep -F "scripts/ops/post.sh" .claude/agents/argus.md` exits 1. After this task, the updated rule 1 text is present in all six compiled persona targets that declare `trusted-posting.md`:
- `.claude/agents/argus.md`
- `.claude/agents/athena.md`
- `.agents/agents/atlas/agent.md`
- `.claude/agents/cassandra.md`
- `.agents/agents/daedalus/agent.md`
- `.claude/agents/odyssey.md`

**Done when:** The rule 1 text is verified across all six files above.

---

## T3 · Gates and the forbidden-path audit — D4, AT-2, AT-3, AT-5, AT-6

Every command from the repository root, on the working tree with T1–T2 applied.

| # | Command | Expected | Proves |
|---|---|---|---|
| 1 | `python3 scripts/sync_agents.py --check` | exit 0 | AT-2 (no compiler drift) |
| 2 | `bash scripts/ci/compiler_roundtrip.sh` | exit 0 | AT-3 |
| 3 | `bash scripts/ci/sanitize_check.sh` | exit 0 | AT-6 |
| 4 | `git diff --name-only origin/main` | Only touches `personas/skills/trusted-posting.md` and compiled files under `.claude/agents/` and `.agents/agents/`. No files under `scripts/`, `tests/`, `config/`, `.github/workflows/`, or `docs/SPEC.md` are touched. | AT-5 (scope boundary) |

**Decisions:** D4.
**Done when:** All four commands output their expected values. If step 4 lists forbidden paths, fix the diff, never the assertion.

---

## Branch, commit, pull request

- **Branch:** `odyssey/98-trusted-posting-plan`. The convention is `<actor>/<n>-<slug>`, and the implement-stage actor is odyssey.
- **Commits:** One for the skill edit and compiler output.
- **Closing keyword: none.** The body carries `Refs #98` and must not carry `Closes #98`.
- **Spec-impact:** Since `personas/skills/trusted-posting.md` is modified and is a behavior-bearing path, but D4 forbids editing `docs/SPEC.md` (because the capability is already documented), the pull request body MUST carry the marker `Spec-impact: none - D4 specifies docs/SPEC.md is unchanged because post.sh is already documented at docs/SPEC.md:932-947`. Paste the output of `bash scripts/ci/spec_check.sh origin/main <body-file>` (using a file containing the PR body text) to prove the check passes. Paste `sanitize_check.sh` output as well.


## Out of scope (carried from the spec)

- Any edits to `scripts/ops/post.sh` or `scripts/ops/tests/post_test.sh` (already shipped on `main` in PR #97).
- Any edits to `docs/SPEC.md` (`post.sh` capability is already specified in `docs/SPEC.md:932-947`).
- Any modifications to rules 2, 3, or 5 of `personas/skills/trusted-posting.md`.
- Rewriting rule 4 of `personas/skills/trusted-posting.md`.
- Adding or modifying persona definitions in `personas/*.yaml` or lifecycle stages in `personas/lifecycle.json`.
- Hand edits to `.claude/agents/` or `.agents/agents/`.

Open questions: none
