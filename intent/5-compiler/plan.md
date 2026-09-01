# Plan: the persona compiler (scripts/sync_agents.py)

**Issue:** #5 · single PR (bootstrap compression, see spec.md).
Stacked on #2 (`config/`), which is stacked on #1 (`personas/`).

1. `scripts/sync_agents.py`, one file, five stages in the order the
   spec names them:
   - **load** — `load_personas()` validates every `personas/*.yaml`
     against `personas/schema.json` (jsonschema, Draft 2020-12) and
     checks `name` against the filename; `load_skills()` reads each
     declared skill file verbatim (D5).
   - **resolve** — `Resolver` holds the three `config/` lookups:
     `model()` (tier→model), `harness_for()` (pin, or both harnesses
     for a sub-agent, D2), `tools()` (capability→tools, returning the
     generated fallbacks for optional unmapped capabilities, D4).
   - **assemble** — `render_body()` emits the fixed section order of
     D3 at 72 columns, with skills inlined unwrapped.
   - **emit** — `ClaudeEmitter` and `AntigravityEmitter`, one `emit()`
     each returning `{relpath: content}`; adding a harness is adding
     a class (D10).
   - **sanitize** — `sanitize()` runs on every file BEFORE anything is
     written; `compile_all()` completes in memory first, so a refusal
     leaves the filesystem untouched (D8). Site-specific literals come
     from `SYNC_AGENTS_DENY` at run time, never from the source (D8a).
   Failure mode first throughout: one `BuildError` per bad source,
   naming the file, the field, and the fix; non-zero exit.
2. Modes in `main()`: default build (write + prune orphaned marked
   files), `--check` (drift report, exit 1), `--verify` (re-parse from
   disk), `--root`/`--out` for alternate trees (D9).
3. Run the build; commit the 30 emitted targets under
   `.claude/agents/` and `.agents/agents/`.
4. `scripts/ci/compiler_roundtrip.sh` — the six checks the spec's
   Acceptance section lists, in order, each printing what it proved.
   The throwaway persona is pinned to the harness WITHOUT a native
   `ask_user` tool, so step 5 exercises the generated-fallback path
   that no committed source currently reaches. The negative fixtures
   are assembled at run time, so no literal home path is ever
   committed by the test that tests for home paths.
5. `docs/SPEC.md` — move `personas.compiler` out of "Agreed, not yet
   built" and upsert it into Capabilities, citing #5 and
   `intent/5-compiler/`.

Verification: `bash scripts/ci/compiler_roundtrip.sh` green; a manual
home-path and token-shape grep over the whole diff; `git status` clean
under `personas/` (sources untouched).

Not in this change: the launcher (#8/#10), CI wiring of these scripts
(#6), and IDE emitters (a later emitter class, zero source edits).
