# Intent: the persona compiler (scripts/sync_agents.py)

**Issue:** #5 · **Status:** accepted on merge of this PR

## Problem

`personas/` holds eleven canonical, vendor-agnostic sources (#1) and
`config/` holds the three lookups that bind them to real deployments
(#2) — and nothing reads either. Every harness still needs a
hand-written agent file, which is the anti-pattern the whole system
exists to refute: the moment a role is authored twice, the two copies
diverge and "one persona, every harness" is a claim rather than a
demonstration. Until a build exists, the personas are wizard-of-Oz.

## Proposed outcome

One deterministic build, `scripts/sync_agents.py`, that compiles
`personas/ + config/` into every harness target — `.claude/agents/`
for Claude Code, `.agents/agents/<name>/` for Antigravity — with
byte-identical output for identical inputs, so the drift gate (#6) is
just "rebuild and diff". Capability fallbacks are generated from
config, never hand-written. The compiled targets are committed, so a
session can start *as* a compiled persona on either harness.

## Affected users and systems

CI (#6) runs the build in `--check` mode as the drift gate and the
roundtrip script as the compiler's test. The launcher (#8/#10) reads
the same deployment pins to dispatch a persona headlessly. Presenters
edit one persona or one pin in the workshop and rebuild to show every
harness change at once.

## Constraints

- Pure and deterministic: no timestamps, no machine state, no network.
- Vendor names enter only through `config/`; `personas/` is untouched
  by this change.
- No secrets and no local paths in anything emitted — the compiler
  refuses to write them.
- Third-party dependencies stop at pyyaml and jsonschema.
- The launcher is out of scope; it lands with #8/#10.

## Open questions

None — resolved in [spec.md](spec.md).
