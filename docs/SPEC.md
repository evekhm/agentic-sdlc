# System spec (living)

What the system does today: present tense, merged behavior only.
Maintained by upsert per AGENTS.md ("The living spec"): any PR that
changes behavior updates this file in the same PR. Entries are keyed
by stable dotted capability IDs; entries added after this initial
version cite their PR inline.

## Deployment status

Bootstrap phase (Rung 0–1 of the pinned tracker, issue #12). CI
enforcement of this spec (spec check, drift, sanitization — #6) does
not exist yet: every rule below is convention-enforced. During
Rung 0, commits landed on `main` directly; this seed entry records
that state. From this file's first commit forward, behavior-bearing
changes go through PRs per the tracker workflow in AGENTS.md.

## Capabilities

### docs.structure
AGENTS.md is the canonical cross-harness standard (document map and
reading order, run-folder bookkeeping, living-spec rule, context and
cost discipline, five-tier ladder, session handoff, tracker
workflow). CLAUDE.md and GEMINI.md are thin harness adapters that add
only harness-specific mechanics. INTENT.md is the founding
system-level intent (change #0). Reference docs live in `docs/`
(BLOG.md, CONTEXT.md, this file), uppercase names throughout.

### tracker.workflow
Work is tracked as GitHub issues on `evekhm/agentic-sdlc`. Sessions
follow pick → claim → read → work → hand off → gate (AGENTS.md,
"Working the tracker"): the `in-progress` label is the claim mutex
and the issue is the unit of parallelism; handoff comments use the
Done/Decided/Next/Blocked format; the pinned tracker issue (#12)
indexes the bootstrap backlog by rung; the `hold` label halts all
automation while present. There is deliberately no STATUS.md.

### tracker.provisioning
`scripts/setup/bootstrap_tracker.sh` provisions the base labels and
the backlog issues idempotently from reviewable body files in
`scripts/setup/issues/` (`NN-slug.md`: Title/Labels header, body
after `---`). Issues are matched by exact title and reused; an
existing tracker issue's body is never overwritten (its checkboxes
are live state); `{{slug}}` cross-references resolve to issue
numbers, and a forward reference fails the run. Filenames define
dependency order.

### personas.sources
Every actor is defined once, canonically and vendor-agnostically, in
`personas/<name>.yaml` (#1, `intent/1-personas/`): six personas
(athena, daedalus, odyssey, argus, atlas, cassandra) and five
sub-agents (mechanic, coder, contract-writer, scanner, explorer).
Sources conform to `personas/schema.json` (JSON Schema 2020-12):
`kind` splits GitHub-identity personas from compiled sub-agents;
`tier` takes only the five semantic grades; tooling is abstract
`capabilities`; `authority` declares the GitHub write ladder
(`none` < `comments` < `issues` < `branch:<glob>`), path allowlist,
identity, GitHub App `app_id`/`installation_id` (public, once
registered), and token NAME only — never a credential value;
sub-agents carry no authority and
cannot spawn sub-agents. Shared protocol text lives once in
`personas/skills/` (`spec-adversary.md`, `review-protocol.md` —
which defers to root REVIEW.md — and `trusted-posting.md`) and is
inlined by the compiler in declared order. Validation is manual
until the compiler (#5) and CI (#6) enforce it.

### config.bindings
`config/` is the only layer where vendor, model, and tool names
appear (#2, `intent/2-config/`): `model_tiers.yaml` binds the five
semantic tiers to models per harness (claude-code, antigravity);
`deployments.yaml` pins each persona to a harness — sub-agents
inherit their dispatcher's harness — and carries the machine-checked
constraint that the two reviewers resolve to different model
families; `tools.yaml` maps abstract capabilities to concrete tools
per harness, with declared fallback text for optional capabilities a
harness cannot map. Swapping a vendor is an edit to these files,
never to a persona source.

### ops.spend
`scripts/ops/session_spend.sh <transcript-dir>` measures session
cost: cache hit rate `read/(read+write+fresh)` and
tokens-per-message. Tests: `scripts/ops/tests/session_spend_test.sh`.

## Agreed, not yet built

Each entry is on the record as a tracker issue; it moves into the
spec body when its implementing PR merges.

- **review.policy** — REVIEW.md, protocol v2 port (#3).
- **lifecycle.labels** — the full label state machine (#4).
- **personas.compiler** — `scripts/sync_agents.py` emitting
  `.claude/agents/` and `.agents/agents/` targets deterministically,
  with roundtrip validation (#5).
- **ci.gates** — drift check, sanitization scanners, spec check (#6).
- **identity.bots** — one GitHub App per persona for all six
  (Athena, Daedalus, Cassandra new; Odyssey, Argus, Atlas migrated
  off their PAT bot accounts), short-lived installation tokens minted
  by `scripts/auth/mint_app_token.py` (#7).
- **review.automation** — Argus workflow, Atlas sidecar, consensus
  (#8, #9).
- **intake.automation** — headless Athena on `intent:new` (#10).
- **maintain.watchers** — Cassandra, control bands, seeded incident
  (#11).
