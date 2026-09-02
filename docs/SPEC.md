# System spec (living)

What the system does today: present tense, merged behavior only.
Maintained by upsert per AGENTS.md ("The living spec"): any PR that
changes behavior updates this file in the same PR. Entries are keyed
by stable dotted capability IDs; entries added after this initial
version cite their PR inline.

## Deployment status

Bootstrap phase (Rung 0–2 of the pinned tracker, issue #12). CI
enforcement of this spec arrives with `ci.gates` below (#6): from the
merge of that PR, the drift, sanitization and spec checks run on every
pull request, so the living-spec rule and the generated-target rule
are machine-enforced rather than convention-enforced. Making the three
checks *required* to merge is a branch-protection setting a human
applies to `main`; until it is applied, a red check is visible but not
blocking. Every other rule in this file remains convention-enforced.
During Rung 0, commits landed on `main` directly; this seed entry
records that state. From this file's first commit forward,
behavior-bearing changes go through PRs per the tracker workflow in
AGENTS.md.

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
inlined by the compiler in declared order. Every source is validated
against the schema on every build (`personas.compiler`); the drift
gate runs that build on every pull request (`ci.gates`).

### identity.bots
Each of the six personas (athena, daedalus, cassandra, odyssey,
argus, atlas) is its own GitHub App — no shared App, no PAT-backed
bot users (#7; migrates the three carry-overs, odyssey/argus/atlas,
off their prior PAT accounts). Names are uniformly
`<owner>-<persona>-app`: App slugs and GitHub usernames share one
namespace, so `-app` avoids colliding with an existing account.
`personas/<name>.yaml`'s `authority` block carries the public
identifiers (`identity`, `app_id`, `client_id`, `installation_id`);
the private key never lives in the repo or a persona source.
`scripts/auth/create_all_apps.py` registers all six through GitHub's
Manifest flow, skipping any persona that already has an `app_id`;
`scripts/auth/mint_app_token.py <persona>` signs a JWT with the
persona's private key and exchanges it for a ~1-hour installation
token, usable directly as `GH_TOKEN`. The private key is the only
secret — an Actions secret or a local
`~/.keys/<slug>.<date>.private-key.pem` file. Nothing is hardcoded to
one owner: `_github_app.py:get_repo_info()` derives `(owner, repo)`
from the checkout's `origin` remote, so forking the repo and
re-running `create_all_apps.py` registers independently-named Apps
with no script edits.

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

### personas.compiler
`scripts/sync_agents.py` compiles `personas/` + `config/` into every
harness target (#5, `intent/5-compiler/`): `.claude/agents/<name>.md`
for Claude Code and `.agents/agents/<name>/{agent.json,config.yaml,
instructions.md}` for Antigravity, all committed. The build is pure
and deterministic — no timestamps, no machine state — so the drift
gate is a plain rebuild-and-diff. Five stages: validate every source
against `personas/schema.json`; resolve tier→model, persona→harness
and capability→tools from `config/`; assemble one instruction body
(role, skills inlined verbatim in declared order, authority and
bounds, execution caps, a pointer to AGENTS.md, and fallbacks
GENERATED from `tools.yaml` for optional capabilities the harness
cannot map — a required one fails the build); emit through one
emitter per harness; sanitize before write, refusing any output
carrying a home path, a token shape, an inline credential value, or a
site-specific string named at run time in `SYNC_AGENTS_DENY` (never
committed — hard-coding what you are hiding is the leak itself).
A persona is emitted only for its pinned harness; a sub-agent is
emitted for every harness, because it inherits its dispatcher's.
Every emitted file carries a generated-file marker, which is also how
the build prunes targets no source emits. Modes: default builds,
`--check` reports drift and exits 1, `--verify` re-parses the emitted
targets and asserts each carries its resolved model, mapped tools and
full skill text. Proof: `scripts/ci/compiler_roundtrip.sh` (schema
check, determinism, drift, roundtrip, a throwaway persona compiled
end-to-end, sanitizer refusal). Both run on every pull request as the
drift gate (`ci.gates`).

### ci.gates
`.github/workflows/ci-gates.yml` runs three deterministic gates on
every pull request — and the first two also on pushes to `main` — as
three independent jobs, so one push returns all three verdicts (#6,
`intent/6-ci-gates/`). **Drift:** `python3 scripts/sync_agents.py
--check` plus `scripts/ci/compiler_roundtrip.sh`; a hand-edited or
stale compiled target under `.claude/agents/` or `.agents/` fails.
**Sanitization:** `scripts/ci/sanitize_check.sh` scans every tracked
file for absolute home-directory paths and home-variable references,
credential shapes (GitHub token and fine-grained PAT, AWS access key
id, `sk-` key, Slack token, private-key block) and, inside
`personas/**` only, vendor/model/family names — which is how the
vendor-agnostic rule for persona sources is enforced. All-caps secret
NAMES stay allowed. The matched text is never printed, only
`path:line: <label>`; exemptions live in
`scripts/ci/sanitize_allowlist.txt`, each scoped to one rule and one
exact path with its reason inline. **Spec check:**
`scripts/ci/spec_check.sh` fails a PR that touches behavior-bearing
paths (`scripts/**`, `personas/**`, `config/**`,
`.github/workflows/**`, `AGENTS.md`, `REVIEW.md` — compiled targets
excluded, the drift gate owns those) unless the same diff touches this
file or the PR body carries `Spec-impact: none — <reason>`; it checks
that the choice was made, never whether the entry or the reason is
good. All three are scripts runnable locally by the same command CI
runs; the workflow needs no secrets and grants only
`contents: read`.

### lifecycle.labels
Lifecycle state lives in GitHub issue labels (#4,
`intent/4-labels/`). Five labels are human-facing — `intent:new`,
`in-progress`, `hold`, `blocked`, `bootstrap` — and the stage is a
single `status:*` label on the ladder `status:planning` →
`status:spec` → `status:build` → `status:implementing` →
`status:in-review`, with **at most one set at a time**. `review:1`,
`review:2` and `review:3` count reviewer iterations; `review:3`
escalates to `status:review-stuck`. All 14 are provisioned
idempotently by `scripts/setup/bootstrap_tracker.sh`, whose
`--labels-only` mode runs the label section and exits before anything
reads or files an issue. `.github/workflows/lifecycle.yml` writes the
ladder on every push to `main` by running
`scripts/ci/lifecycle_advance.sh <before-sha> <after-sha>`, which is
deterministic bash + `gh` + `jq` with no model call and is runnable
locally by the same command (`DRY_RUN=1` prints every mutation instead
of executing it). It reads the pushed range for ADDED files matching
`intent/<issue>-<slug>/{intent,spec,plan}.md` and mirrors the merge
gate into the label: intent.md → `status:spec`, spec.md →
`status:build` **only if the merged file carries `Status: Approved`**
(a Draft spec gets a warning comment and no advance), plan.md →
`status:implementing`; each transition posts one comment naming what
the next stage owes. `hold` is checked first and halts the issue
absolutely; more than one `status:*` is treated as corrupted state —
the script comments, applies `hold`, and stops processing that issue;
a push adding several of the triple for one issue applies only the
furthest transition, in one comment. Every write is idempotent (a
label already present is not re-added; a comment whose
`<!-- lifecycle:<stage>:<sha> -->` marker is already in the thread is
not re-posted), so re-running a range is a no-op. A closed or missing
issue is logged and skipped. The workflow uses the default
`GITHUB_TOKEN` and posts as `github-actions[bot]` — infrastructure,
not a persona — with `issues: write, contents: read` and no secrets.
`status:in-review` and the `review:N` counter exist in the taxonomy
but are not written by this workflow; their writers arrive with #8/#9.

### review.policy
`REVIEW.md` is the review protocol the reviewer personas compile
against (PR #14). It defines: four severity tiers
(`security`/`high`/`normal`/`suggestion`) with a closed `high` list
and a failure-scenario requirement; the three-round funnel (round 1
full from both reviewers, rounds 2–3 verification with blocking-only
new findings, security-only past round 3); per-reviewer finding ID
namespaces (`R<round>-<n>`, `R<issue>-<n>`, `AT-<n>`) stable from
first appearance; the ledger row fields and the header/trailer
signature convention; consensus rules (independent round 1, dual
sign-off on `security` only, evidence arbitrates, verdict format,
three-exchange dispute cap); consensus keyed to Decision IDs where
the spec under review has a Decisions table; label derivation from
ledger state; merge-anytime with one post-merge follow-up issue; and
the deep-review grant. The two reviewers are deployment-pinned to
different model families; which family backs which reviewer is a
`config/` fact and appears nowhere in the policy. The document is
normative for the ported automation: no recorder, workflow, or
scheduled sweep exists yet (#8, #9), so every rule is currently
prompt-enforced with a human backstop; the label names it references
(findings/suggestions/escalation) now resolve to the concrete
taxonomy landed in `lifecycle.labels` (#4) — `status:review-stuck` is
the escalation label.

### ops.spend
`scripts/ops/session_spend.sh <transcript-dir>` measures session
cost: cache hit rate `read/(read+write+fresh)` and
tokens-per-message. Tests: `scripts/ops/tests/session_spend_test.sh`.

## Agreed, not yet built

Each entry is on the record as a tracker issue; it moves into the
spec body when its implementing PR merges.

- **review.automation** — Argus workflow, Atlas sidecar, consensus
  (#8, #9).
- **intake.automation** — headless Athena on `intent:new` (#10).
- **maintain.watchers** — Cassandra, control bands, seeded incident
  (#11).
