# Spec: persona schema and canonical sources

**Issue:** #1 · **Status:** Approved (approval = merge of this PR) ·
**Open questions:** none

## What is being built

`personas/` — the canonical, vendor-agnostic definition of every
actor in the system:

```text
personas/
  schema.json          # JSON Schema (2020-12) all sources validate against
  athena.yaml daedalus.yaml odyssey.yaml     # kind: persona
  argus.yaml atlas.yaml cassandra.yaml       # kind: persona
  mechanic.yaml coder.yaml contract-writer.yaml
  scanner.yaml explorer.yaml                 # kind: subagent
  skills/
    spec-adversary.md      # Athena's grilling protocol
    review-protocol.md     # reviewer procedure; defers to root REVIEW.md
    trusted-posting.md     # GitHub-write discipline for all posting actors
```

Each source carries: `name`, `kind`, `stage`, `tier`, `role` (the
behavioral contract), `skills` (list of skill file names),
`capabilities` (abstract), `authority` (personas only), `delegates_to`
(personas only), `limits`.

## Decisions

| ID | Decision |
|----|----------|
| D1 | One canonical YAML per actor in `personas/`; shared protocol text lives once in `personas/skills/` and is referenced by name. |
| D2 | `kind: persona \| subagent` splits GitHub-identity actors from compiled workers. Sub-agents carry no identity and no `authority` block. |
| D3 | `tier` takes only the five semantic grades from AGENTS.md (FAST/MECHANICAL/IMPLEMENTATION/REVIEW/FRONTIER, with optional `escalation_tier`). Vendor model IDs anywhere under `personas/**` fail validation. |
| D4 | Tooling is declared as abstract `capabilities` (e.g. `read_repo`, `run_commands`, `github_comment`); the capability→tool map is a harness fact in `config/tools.yaml` (#2). A `required` capability a harness cannot map fails compilation; an optional one compiles to a generated fallback instruction. |
| D5 | Skills are markdown files inlined by the compiler in declared order. A skill may point at a root doc (REVIEW.md) for shared substance instead of duplicating it. |
| D6 | `authority` declares `github_write` mode (`comment-only \| issue-only \| branch:<glob> \| none`), optional `paths` allowlist, `identity` (GitHub login), and `token` (secret NAME only, never a value or path). Declared here so compiled prompts state their bounds; enforced mechanically by branch protection, merge-gate path checks, and token scopes. |
| D7 | Only personas have `delegates_to`; sub-agents may not spawn sub-agents. |
| D8 | Machine validation ships as `personas/schema.json` in this change; enforcement (validate on build, in CI) lands with #5 and #6. |
| D9 | `limits` (`max_turns`, `timeout_mins`) are required for personas, optional for sub-agents (harness defaults apply). |
| D10 | Bootstrap compression: this change lands PLAN/DESIGN/BUILD artifacts in one PR and IMPLEMENT in a second, recorded here once. Post-automation changes return to one PR per gate. Not a precedent. |

## Acceptance

- All 11 sources parse as YAML and conform to `schema.json`
  (spot-verified by hand until #5 automates it — D8).
- `grep -riE 'claude|gemini|sonnet|opus|haiku|flash|gpt' personas/`
  returns nothing.
- No secrets, token values, or `/home` paths anywhere under
  `personas/`.
- `docs/SPEC.md` gains `personas.sources` in the same implementation
  PR (the living-spec upsert rule).
