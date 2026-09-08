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
system-level intent (change #0). `README.md` is the operator-facing
entry point (#35, `intent/35-readme/`): it addresses one reader, the
operator at the keyboard, and never an agent — no compiled prompt
points an agent at it. It explains and never duplicates, so every
rule it mentions that is normative elsewhere is at most one sentence
plus a link to its owner, it is normative for nothing itself, and
wherever it and a document it links disagree the other one wins. It
is bounded by construction: a fixed, ordered section list that grows
only by a deliberate edit to that list, at most one diagram, and
exactly one command shown as an instruction (`scripts/ops/work.sh
<n>`). There is no line or section-count cap (the 150-line, nine-
section ceiling of #35 D2/D4 was lifted by the product owner on
2026-09-03).
Reference docs live in `docs/` (BLOG.md, CONTEXT.md, this file),
uppercase names throughout.

### tracker.workflow
Work is tracked as GitHub issues on `evekhm/agentic-sdlc`. Sessions
follow pick → claim → read → work → hand off → gate (AGENTS.md,
"Working the tracker"): the `in-progress` label is the claim mutex
and the issue is the unit of parallelism; handoff comments use the
Done/Decided/Next/Blocked format; the pinned tracker issue (#12)
indexes the bootstrap backlog by rung; the `hold` label halts all
automation while present. A session is started from a number and
nothing else — `scripts/ops/work.sh <issue-or-pr>` resolves the
stage, owner, folder and branch from the labels and the repository
(`ops.dispatch`), so the tracker, not the operator, says what is
current. There is deliberately no STATUS.md.

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
secret, and WHERE it lives follows the persona's placement
(`execution.placement`, #25): a persona placed at `gh-actions` needs
its key as a repository Actions secret named `<PERSONA>_APP_PRIVATE_KEY`
— in v1 that is argus and atlas and no others — and a persona placed at
`vm-local` reads a local
`~/.keys/<slug>.<date>.private-key.pem` file. Nothing is hardcoded to
one owner: `_github_app.py:get_repo_info()` derives `(owner, repo)`
from the checkout's `origin` remote, so forking the repo and
re-running `create_all_apps.py` registers independently-named Apps
with no script edits. Every App's manifest grants `issues: write`
(PR #58, #47): the dispatch protocol (`ops.dispatch`, `personas.resume`)
has each persona add `in-progress`, post the `Claim:` line, and post its
handoff on the issue it works, and an App with `issues: read` gets 403
on all three. `contents` and `pull_requests` still vary per persona —
argus and atlas are comment-only and hold `contents: read`. Editing the
manifest changes only Apps registered afterwards; an already-registered
App's permissions are changed on github.com and re-accepted on its
installation. A dispatched session never carries the operator's
credentials: `scripts/ops/work.sh` mints the launched persona's token
in the one step between the last refusal and the launch and hands it
to the child alone (`ops.identity`).

Cloud model access is a second credential axis, and the two harnesses
do not share one (`ops.model-credential`, #167). claude-code calls
Vertex, where a federated service account is sufficient and stays
least-privilege, so an unattended runner reaches it by workload
identity federation with no key at rest. antigravity cannot use that
credential at all: `agy` holds no built-in model list and fetches its
catalog from Google's Cloud Code private endpoint, which serves that
catalog per Antigravity ENTITLEMENT of the calling identity — not per
project and not per IAM role. A service account holds no entitlement,
receives an empty catalog, and `agy` then rejects every model id it is
given, which no re-pin and no role grant can repair. An antigravity
persona therefore requires a user-entitled credential, provisioned as
a repository secret. The launcher is the only component that resolves
this, because it is the only component that knows which harness is
about to run: it substitutes that credential for the federated one on
the antigravity branch and nowhere else, and an absent credential
degrades that persona alone rather than failing the dispatch. Because
the credential is user-entitled and long-lived, no dispatch that does
not need it may retain it, and withholding must be by DESTRUCTION
rather than by concealment — a value placed in the environment of the
process that hosts a session cannot be withdrawn from it, so the
credential is carried to the launcher as a path to a file readable
only by its owner and never written inside the checkout, and the
launcher deletes that file before any session exists whenever the
harness it resolved is not the one entitled to it, and on its own exit
whatever the outcome when it is. It belongs to a dedicated account
rather than an operator's own.

### config.bindings
`config/` is the only layer where vendor, model, and tool names
appear (#2, `intent/2-config/`): `model_tiers.yaml` binds the five
semantic tiers to models per harness (claude-code, antigravity);
`deployments.yaml` pins each persona to a harness — sub-agents
inherit their dispatcher's harness — and carries the machine-checked
constraint that the two reviewers resolve to different model
families; `tools.yaml` maps abstract capabilities to concrete tools
per harness, with declared fallback text for optional capabilities a
harness cannot map; `execution.yaml` pins each persona's trigger and
placement (`execution.placement`, #25). Harness and placement are two
axes and two files: WHICH runtime interprets a persona is
`deployments.yaml`, WHERE that runtime runs is `execution.yaml`, and
neither file carries the other's key — so moving a persona between a
laptop and a hosted runner cannot silently change its model. Swapping a
vendor is an edit to these files, never to a persona source.
Re-pinning a persona to another harness, or re-binding a tier to
another model, is that same edit plus the compiler rebuild committed
with it — no persona source changes for a repin — and the gates are
written to prove whatever configuration is present rather than one
particular assignment: the drift gate recompiles the pins as they
stand, the sanitize gate holds because no vendor string moves into
`personas/`, and the reviewer constraint is resolved against the pins
at the commit that changes them (#44, PR #93).

### personas.compiler
`scripts/sync_agents.py` compiles `personas/` + `config/` into every
harness target (#5, `intent/5-compiler/`): `.claude/agents/<name>.md`
for Claude Code and `.agents/agents/<name>/{agent.md,agent.json}` for
Antigravity, all committed. Antigravity reads only `agent.md`: YAML
frontmatter carrying `name`, `description` and `tools` (mapped to that
harness's own tool names) above the assembled body, with the
generated-file marker as a frontmatter comment. A `model:` key there
voids the agent — the harness silently falls back to its stock agent —
so the resolved model and the sub-agent flag ride in the sidecar
`agent.json`, which the harness ignores and `scripts/ops/work.sh` reads
(#43, `ops.dispatch`). The build is pure
and deterministic — no timestamps, no machine state — so the drift
gate is a plain rebuild-and-diff. Five stages: validate every source
against `personas/schema.json`; resolve tier→model, persona→harness
and capability→tools from `config/`; assemble one instruction body
(role, skills inlined verbatim in declared order, authority and
bounds, execution caps, a pointer to AGENTS.md, fallbacks
GENERATED from `tools.yaml` for optional capabilities the harness
cannot map — a required one fails the build — and, for a target
whose source declares the `resume-protocol.md` skill, a
`## Lifecycle stages` block GENERATED from
`personas/lifecycle.json` whose owner line per rung is derived from
the `stage` lists of the persona sources); emit through one
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

### personas.resume
`personas/lifecycle.json` is the single source of the label↔stage
relation (#36, `intent/36-dispatch/`): five rungs — plan, design,
build, implement, review — each row carrying `stage`, `label`,
`artifact`, `advances_on`, `advances_to`, `advance_message` and
`dispatch_brief`.
Ownership is deliberately not a column: who works a stage is DERIVED
from the `stage` list of every `kind: persona` source, so adding an
owner is an edit to that persona and to nothing else. It has three
readers and no fourth copy — `scripts/ci/lifecycle_advance.sh`
matches on `advances_on`, then on `artifact` or on the issue's
current `label`, to pick a transition (`lifecycle.labels`),
`scripts/ops/work.sh` matches on `label` to pick a stage
(`ops.dispatch`), and the compiler renders the whole ladder, with
each rung's derived owners, into a generated `## Lifecycle stages`
block in every target whose source declares the
`personas/skills/resume-protocol.md` skill (all six personas, no
sub-agent). That skill is the resume protocol itself and holds no
copy of the ladder: a number is the whole instruction, and a session
handed one reads the issue, derives the stage from its single
`status:*` label, reuses or derives the intent folder, claims with
`in-progress` plus one comment, works only the current stage's
artifact, hands off in the Done/Decided/Next/Blocked format, and
refuses in six stated conditions rather than guessing. Tests:
`scripts/ci/tests/lifecycle_advance_test.sh`.

### ci.gates
`.github/workflows/ci-gates.yml` runs four deterministic gates on
every pull request — and all but spec-check also on pushes to `main` —
as four independent jobs, so one push returns all four verdicts (#6,
`intent/6-ci-gates/`; the fourth added by #25). **Drift:** `python3 scripts/sync_agents.py
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
good. **Execution:** `python3 scripts/ops/execution.py --check` plus
`scripts/ops/tests/{execution,placement,post}_test.sh`; a binding on a
placement with no adapter directory, on an event
`.github/workflows/unattended.yml` does not trigger on, or on a persona
with no source fails here rather than at 03:00 in a run nobody is
watching (`execution.placement`, #25). All four are scripts runnable
locally by the same command CI runs; the workflow needs no secrets and
grants only `contents: read`.

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
of executing it). WHAT fires each rung is the `advances_on` column of
`personas/lifecycle.json` (`personas.resume`, #36), read and never
inferred (PR #67). Three rungs advance on an added file: the script
reads the pushed range for ADDED files matching
`intent/<issue>-<slug>/{intent,spec,plan}.md` and mirrors the merge
gate into the label — intent.md → `status:spec`, spec.md →
`status:build`, plan.md → `status:implementing`. The implement rung
owes no file, because what it owes is code, so it advances on a
merged PULL REQUEST — and specifically on **the implementing** one
(PR #102). Every commit of the range is walked in `git rev-list
--topo-order --reverse`, a total order that contains each commit
exactly once, and `gh api --paginate
repos/<repo>/commits/<sha>/pulls` says which pull requests each
belongs to. A merged pull request is kept when its
`merge_commit_sha` is contained in that range; the base branch is
not filtered on, because containment is the trunk test and a pull
request merged into a landing branch that later lands reaches `main`
on a second parent. A `merge_commit_sha` this checkout does not hold
is a counted failure naming the pull request, never a silent drop.
A surviving pull request is #`<n>`'s **implementing** pull request
only when three conjuncts hold (PR #102): its head branch parses as
`<actor>/<n>-<slug>`; its own file list, read from
`gh api --paginate repos/<repo>/pulls/<n>/files` — the diff GitHub
computes from the pull request's own refs, hence the same set under
a merge-commit, a squash and a rebase merge — changes at least one
path outside `intent/`; and exactly one `intent/<n>-*/` directory
exists in the after-tree with `<slug>` as its slug. Every read this
script makes fails closed, never open (#73): `gh api
--paginate repos/<repo>/commits/<sha>/pulls` failing — a non-zero
exit or a payload that will not parse — is a counted failure naming
the COMMIT, because no pull request is identified yet to name; the
pull request's own file list at `.../pulls/<n>/files` is trusted
only from a payload that parses as a JSON array — a non-zero exit,
an empty body, unparseable text and a payload that parses as
something other than an array (`{}`) are all the same counted
failure naming the PULL REQUEST, and only a well-formed `[]` is the
silent "changes nothing outside intent/" answer, because a pull
request that changes nothing changes nothing outside `intent/`
either. Two folders is a
counted failure, zero yields no candidate, and there is no
closing-keyword fallback at all: the implementing pull request is
precisely the one that must not carry a closing keyword for its
issue, so a branch that does not parse resolves to nothing whatever
the body says. A pull request whose head repository is not this one
is skipped, logged by number and never read as an identity claim —
the fork gate (PR #102). A merge that names an issue sitting at the
merge rung but is **not** its implementing pull request, because the
branch's slug is not the intent folder's, is announced with exactly
one `::warning::lifecycle_advance:` line naming the issue, the
rejected pull request, its branch and the dispatch branch expected
instead (PR #102) — never silence, and never a red, which stays
reserved for a ladder that is provably broken. A slug mismatch whose
file list never leaves `intent/` is an ordinary plan or spec
amendment landing while the issue waits, and draws no warning at all.
A near miss is not a
candidate: it never applies `hold`, never comments and never fails
the run. When one range carries two implementing pull requests for
one issue — a shape a re-created dispatch branch produces — the one
whose `merge_commit_sha` is later in that total order is the one
applied and named. A commit belonging to no pull request advances
nothing. An issue with both an artifact and a merged pull request in
one range takes the furthest rung of the two, ranked by position in
the ladder file. WHICH label a rung advances to, and the line posted
when it does, are likewise not written in the script but read from the
same row — one comment per transition naming what the next stage owes.
A row with no `advances_to` writes no label and a row with no
`advance_message` posts no comment, so the last rung is inert by
data rather than by a special case. The first `status:*` this
workflow writes also removes `intent:new` on the same edit: an item
with a stage is an item somebody triaged. The one exception the
script owns is the Draft
override, which is the ladder refusing to move rather than a rung of
it: a merged spec.md advances **only if it carries `Status:
Approved`**, and otherwise gets a warning comment and no advance.
`hold` is checked first and halts the issue absolutely; more than one
`status:*` is treated as corrupted state —
the script comments, applies `hold`, and stops processing that issue;
a push adding several of the triple for one issue applies only the
furthest transition, in one comment. Every write is idempotent (a
label already present is not re-added; a comment whose
`<!-- lifecycle:<stage>:<sha> -->` marker is already in the thread is
not re-posted), so re-running a range is a no-op; the merge rung needs
no marker of its own for this, because once the label has advanced no
row matches it again. A missing issue is logged and skipped, and so is
a closed one — with one exception: a CLOSED issue still carrying the
merge rung's label, whose implementing pull request merged in the
range, is a red counted failure that writes nothing at all: the ladder
cannot advance a closed issue, and the human is told to reopen it and
re-run the range (PR #67, PR #102). A transition never walks the
ladder backward (D19): rank is the row's position in
`personas/lifecycle.json`'s own label order, the same list the merge
rung's guards already read, so nothing here keeps a second ordering.
An issue with no `status:*` label ranks below every rung and any
first transition is forward; a `status:*` label the ladder does not
name at all (`status:review-stuck` is one) has no rank either. A
trigger that would move the issue below its current rank, or a
current label that cannot be ranked, is a no-op with exactly one
`::warning::` line naming the issue, its current status and the rung
the trigger would otherwise have written — never a counted failure,
because a folder rename or a revert-and-reland is an ordinary event
on a healthy ladder, not evidence of a broken one. A trigger that
would leave the issue at its current rank writes no label and posts
no comment, but still clears a stray `intent:new` in its own edit.
`blocked` is advisory only: this script never reads it and never
writes it, and it neither halts a transition nor taints one — the
refusal it signals belongs to the actors at dispatch, not to the
ladder (D20; only `hold` halts this script, checked first as
always). Every read this script makes fails closed end to end
(D21): the merge-candidate reads above were already this way; the
per-issue `gh issue view` that decides whether an issue advances is
now the same — a non-zero exit is a counted failure naming the
issue, with no `DRY_RUN` substitution of a fabricated open,
unlabelled issue (that default now lives only in the test harness,
never in this script, so a dry run and a real run answer a bad read
identically); and the range walk itself, `git rev-list --topo-order
--reverse before..after`, is checked before any candidate is
discovered or any issue is read — its failure is a counted,
run-ending error naming the range walk, before a single `gh` call is
made. The one deliberate exception is the near-miss report's own
read (D17): it is not a candidate and buys at most one warning, so a
failed read there stays quiet rather than turning the run red over a
line that was never going to write anything (#73, PR #111). The
workflow uses the default `GITHUB_TOKEN` and posts as
`github-actions[bot]` — infrastructure, not a persona — with
`issues: write, contents: read, pull-requests: read` and no secrets.
The ladder is written end to end here; `review:1..3` and
`status:review-stuck` are review state and remain #8/#9's.

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
tokens-per-message. It prices both Claude and Gemini models against
official list rates (Anthropic and Google Cloud Vertex AI rates effective
2026-09-04), ingests Antigravity dispatch JSON envelopes alongside
Claude transcript logs, and reports unpriced models with explicit
warnings and non-zero unpriced token counts, suppresses the TOTAL spend
line, and exits with a non-zero status to fail loudly (PR #177).
Tests: `scripts/ops/tests/session_spend_test.sh`.

### ops.dispatch
`scripts/ops/work.sh <issue-or-pr-number> [--as <persona>]` starts a
session from a number (#36, `intent/36-dispatch/`). Deterministic
bash + `gh` + `jq`, no model call: the tracker's labels, the merged
folder layout and three committed data files are the whole input, so
the same number always resolves the same way. It resolves a pull
request to its issue by a closing keyword and a same-repo `#<n>` in
the body — any of the ones GitHub honours (`close`, `fix`, `resolve`
and their `-s`/`-d` forms, case-insensitively), with two distinct
references an exit 1 naming both rather than a guess — and then by
the `<actor>/<n>-<slug>` branch name; the stage from the single
`status:*` label — or the first rung when the issue is `intent:new` —
through `personas/lifecycle.json` (`personas.resume`); the owners
from the persona sources; the folder by reusing `intent/<n>-*/` when
one exists and otherwise deriving a slug from the title (cut at the
first `:` or `;`, lowercased, runs of other characters to `-`, ≤24
characters at a word boundary); the branch `<persona>/<n>-<slug>`;
and the harness from `config/deployments.yaml`. There is deliberately
no flag naming a stage, folder, artifact or branch — one would let a
session work a stage the labels say is not current. Preflight verifies
the environment can support a run — GitHub read access and a base
object (so a reviewer can compute a diff) — exiting 1 if not (#165).
Eight refusals, checked in order before anything is dispatched and each
exiting 2 with the condition named: `hold`; a dispatch targeting any issue in
the session's dispatch chain (re-entrant self-dispatch, #134);
closed, or `status:review-stuck`; `blocked`; more than one
`status:*` (reported, never guessed, and never `hold`-ed — the
advancer is the single writer of the circuit breaker); a number on no
rung at all — no `status:*` and no `intent:new`, which is every
defect-repair issue, whose fix pull request is the final stage and has
no reviewer rung before merge (#129; it was an error before, one red
reviewer check per fix pull request); `in-progress` claimed by another
actor — with one documented pass-through, a review dispatch, which
is not measured against the claim at all and for which neither the
label nor the thread is read (#207, D3); and `--as` naming a persona
that does not own the stage. When
the number given is a pull request, those refusals read the UNION of the
pull request's own labels and the resolved issue's — a `hold` on either
side refuses, and the message names the side that carries it, or both
sides when both do, because the circuit breaker is placed where the
operator is looking and resolving to the issue must not discard it (#50,
Atlas AT-1, PR #95; both sides, PR #99). The stage is not part of that
union:
it is derived from the issue's labels alone, since the state machine
belongs to the unit of work and a `status:*` label on a pull request
must not decide which rung the issue is on. One exception, and it is
not a label: a **review dispatch** — the number given resolved as a
pull request whose head is in THIS repository, and `--as` names a
persona that declares the `review` stage — is dispatched at `review`
rather than at the issue's rung (#207, D1, D2). The issue's rung is
still derived first and from its own label alone, so a pull request
whose issue is on no rung still refuses; the retarget then reads the
`review` row of `personas/lifecycle.json` for its owners, brief and
artifact, `--as` passes the eighth refusal by construction, and the
report names both the retarget and the rung it displaced. Nothing is
written and no label moves: the issue keeps its own `status:*` and
its claim, held by the rung's author for the whole review window
(#207, D5). A pull request whose head is a fork takes the ordinary
path with its ordinary refusals; the workflow's same-repository
guard remains the authoritative owner of that rule. The claim's holder is the
*author* of the last comment that opens with `Claim` (AGENTS.md,
"Working the tracker", step 2), mapped through the persona identity
table — never a name read out of a comment body, which is an
unauthenticated string, and never prose that merely contains the
word. A login no identity names is a foreign claim, refused by that
login, and a thread with no claim line at all — or one that cannot be
read — refuses too: the label is the mutex, and one naming nobody is
still held. A claim by an owner of the current stage is that actor
resuming and proceeds; when `--as` names one owner, the mutex binds
against that actor alone, so one reviewer's claim stops the other.
That thread is the issue's, and the WHOLE of it: the API answers a
list read thirty items at a time, and a mutex that read only the
first page would take a claim already handed back for the current
one and launch a second session onto an issue another actor holds
(#51, Atlas AT-2, PR #99). So `in-progress` on a pull request refuses
too, naming the side that carries the label and the issue whose
thread was read — a claim is only ever posted on the unit of work
(PR #95, Argus R1-1; PR #99).
The script never writes to GitHub: the claim belongs to the session it
launches, not to the launcher. A stage with several owners (review)
prints both instructions and launches neither unless `--as` names one.

Both harnesses launch (#43, `intent/43-harness-agnostic-launch/`).
Claude Code is started `claude --agent <persona>`; Antigravity is
started `agy -p … --agent <persona> --add-dir <repo root> --model
<the sidecar's model> --output-format json --print-timeout <n>m`, and
`--add-dir` is not optional because print mode ignores the working
directory. Claude Code has no such flag and takes its working
directory as the project, so the launcher `cd`s to the repository root
it resolved before starting either child: without that, `work.sh`
invoked by absolute path from another clone reads one checkout's
labels and personas and hands the session a different one — measured,
and the session reports success having edited the wrong tree.
Both are given one prompt literal, and both are wrapped in
`timeout` at the persona's own `limits.timeout_mins` plus a minute. The
extra minute is for `agy`, which is also given `--print-timeout <n>m`
and so reports its own timeout before the wrapper kills it; Claude Code
takes no such flag, and for it the wrapper is the only cap. A persona
whose compiled target is missing is exit 1 before anything is minted —
a launch against a target that is not there is a session running as the
harness's stock agent under a persona's name — and so is a harness
binary, or `timeout` itself, that is not on `PATH`.

An unattended runner has no interactive login, so it authenticates
`agy` by ADC (`AGY_ADC_AUTH=true`), and `agy` does not carry a model
list: it FETCHES its catalog at startup from
`cloudcode-pa.googleapis.com`, an API distinct from the Vertex
endpoint the models themselves are served on. Both must therefore
work, and today only one does. The runner's federated service account
holds `aiplatform.endpoints.predict`, which is why argus runs; the
catalog call returns `403 SERVICE_DISABLED` because Cloud Code Private
API is not enabled on the project, `agy` reports `timed out waiting
for available models`, and with an empty catalog it rejects EVERY
`--model` value as "not recognized as a known model or custom model in
settings". That is why atlas died in seventeen seconds on every review
round it was ever dispatched for (#167), and no pin fixes it: with no
catalog there is no id that resolves. Enabling that API is a human
action — it needs `servicemanagement.services.bind`, which neither the
runner nor a maintainer account here holds.

The pin still matters, for the case where the catalog is reachable:
`agy` serves a narrower list under ADC than under an account login,
and where it answers at all it offers exactly one Pro-tier id, so an
antigravity binding in `config/model_tiers.yaml` that names anything
else resolves on a laptop and not on a runner. Both properties are
invisible to every gate short of one that actually launches the
harness — a schema check sees a well-formed string, and a placement
check sees no model literal — so an antigravity re-pin is verified by
a live dispatch or it is not verified.

Every MODE is an environment variable, for the same reason argv is
closed: `DRY_RUN=1` prints the resolved launch command instead of
executing it (the reads and every guard still run, and nothing is
minted), and `HEADLESS=1` captures the session's JSON instead of
handing over the terminal. Antigravity is always headless. The
interactive row is not `exec`'d: the child runs in the foreground and
inherits stdin, stdout, stderr and the terminal, and the launcher waits
and maps, so *every* exit of `work.sh` is 0, 1 or 2. Its wrapper is
`timeout --foreground`, which is load-bearing rather than cosmetic:
`timeout` otherwise calls `setpgid(0,0)` and the harness lands in a
process group that is not the terminal's, where reading the terminal
raises SIGTTIN and setting raw mode — the first thing an interactive
TUI does — raises SIGTTOU, stopping the session with a live token
already minted until the cap fires. The headless rows keep the plain
wrapper: they touch no terminal, and group-wide signalling is what
should end a runaway non-interactive harness and its children. That map
is
two-valued — child 0 → 0, anything non-zero → 1 with the raw status
named on stderr, and 124 also naming the cap — because `exec timeout …`
would otherwise hand a caller 124, 125, 126 or 127, codes outside the
contract, and would let a harness that exits 2 for a reason of its own
read as a designed refusal. Interactive 0 means the session ran to
completion, not that the work was done. The interactive row also
requires a terminal: with no tty on stdin or stdout the launcher exits
1 naming `HEADLESS=1`, before minting anything and without starting a
child — the same class as a missing binary, an environment that cannot
start the row rather than a decision about the number.
Four further environment variables exist for the case the MODEs do not
cover — a launch with no operator watching it — and each is opt-in, so
an unset variable leaves argv and behaviour exactly as an attended run
has them. Opt-in is the launcher's contract, not the system's: the
placement adapters always supply the spend ceiling from the persona's
binding (#108), so no dispatch that goes through one is uncapped, and
"unset" describes a launcher invoked directly and by hand. The spend
ceiling requires two enforcement paths (PR #184):
Claude Code enforces the ceiling pre-emptively during execution, while
for Antigravity the dispatcher reads the run's final `.usage` report and
exits 1 if the session exceeded the ceiling. A permission mode is passed
through, because the default mode denies a persona the file and tracker
writes its stage exists to make, and an unattended persona that cannot
act spends its whole prompt preamble to say so. The run's own reported
cost is written to a caller-named file, which is what lets a driver
meter a queue. And a model may be named for one dispatch, which is how
a run is re-tiered without a compiler run — a flag on the launch and
not an environment variable, because the environment variable does not
override the `model:` line `personas.compiler` writes into the agent
file, so a dispatch re-tiered that way bills in full to the compiled
pin while appearing to have moved.

That last failure is why the cost file also names the model the run
actually billed to, taken from the envelope rather than echoed back
from what the caller asked for. A ledger that records the request
cannot show a re-tiering that did not happen, and a cost-control
mechanism whose own records cannot distinguish an intended saving from
a real one is not a control.

That cost is taken from the run's result envelope and not by reading
transcripts back, because transcripts are stored per working directory:
a dispatch inside a worktree records its usage in a tree that a caller
scanning the main project directory never sees, so a ceiling metered
that way never trips and the run reads as free. The envelope travels
with the run and is therefore correct wherever the run happened. For
Claude Code sessions the cost is read from `.total_cost_usd`; for
Antigravity sessions the cost is computed directly from `.usage`
(`input_tokens`, `output_tokens`, `thinking_tokens`, `cache_read_tokens`)
at Vertex AI list rates for the resolved model (PR #161). It is
written before any exit path, because a dispatch that refused, timed
out or crashed still spent money and a meter that sees only successes
cannot hold a budget; and when the envelope carries no cost or the model
is unpriced the file is emptied rather than set to zero, so a caller must
refuse rather than record a run it cannot price as free. For the same reason
the count of permission denials is reported: a run can exit 0 having been
stopped from doing anything.

A headless launch is read for a final `WORK-RESULT: <ok|refused|blocked>
#<n> <reason>` line, taken from the decoded response text (the raw
JSON escapes the newline) with the last such line winning: `ok` exits
0, `refused` and `blocked` exit 2, and a session that crashed, timed
out or exited cleanly without the line exits 1 — an outcome nobody
observed is not a success. Exit 2 therefore now covers both a launcher
refusal and a launched persona's refusal: one code, because a caller
asks whether the number was worked, not which layer declined. Exit 2 is
produced, never forwarded — a child's own status of 2 maps to 1 like
any other non-zero. Exit 1 is unusable input, an environment that
cannot start the row, or an unobservable outcome; exit 0 is
launched-and-ok or printed. The `/work` door is a hand-authored
`.claude/commands/work.md` whose body is exactly
`` !`HEADLESS=1 scripts/ops/work.sh $ARGUMENTS; echo "[work.sh exit
$?]"` ``, in the `` !`…` `` form that runs it rather than describing
it, with `allowed-tools` widened to match the mode-prefixed line so it
runs without a prompt: a command body is otherwise injected as a prompt
and whether the script runs at all is the model's discretion. The door
names the mode because its body runs in the harness's own non-TTY bash
before the turn, where the interactive row cannot start; the trailing
`echo` makes the body exit 0 whatever the script returned, so a
designed exit 2 prints its own refusal text and its code instead of
surfacing as a failed tool call. `.claude/commands/` is outside the
compiler's target directories, so this is not a drift-gate bypass. The
door invokes a relative path by design, so `/work` resolves against the
session's working directory and a session sitting in a worktree gets
that worktree's copy; an operator who wants their terminal to *be* the
session runs `scripts/ops/work.sh <n>` from a terminal, which is not a
thing a slash command can be.
Tests: `scripts/ops/tests/work_test.sh` and
`scripts/ops/tests/smoke_launch_test.sh` against stubs, and
`scripts/ops/smoke_launch.sh <scratch-issue>` for one real launch per
harness present in `config/deployments.yaml` — three named observables
each. Which persona runs an arm is not written in the script: it is
selected by a rule over config facts, the first persona in that file's
own declaration order pinned to that harness whose App in
`scripts/auth/app_manifests.yaml` grants every permission the
observables need, which owns a stage some rung of
`personas/lifecycle.json` labels, and whose own contract in `personas/`
declares a branch surface of the form `branch:<prefix>*` to push — with
that rung's label as the arm's relabel target and that surface's glob,
not a name of the gate's invention, as the branch it is asked to push,
so a persona reading its contract and refusing is never recorded as a
persona that failed to load. The glob's shape is part of the rule
because the gate and the errand each derive the branch from it: only
`<prefix>*` makes the two derivations agree, and any other shape yields
a ref outside the declared surface (or an invalid one), whose push
failure would be misreported as a persona that did not load. A harness
for which the rule yields no persona fails the run, naming the harness
and what is missing, rather than being skipped or covered twice — an arm
silently dropped is a gate reporting coverage it does not have. That
extends to the pin list itself: the gate reads
`config/deployments.yaml` in one place, agreeing with the file's other
readers on both the inline and the block form and treating no comment
line as a pin, and a persona key whose harness it cannot read fails the
run naming that persona instead of shortening the arm list. Trailing
arguments override an arm with another persona, each binding to the
harness its own pin names, and are held to the same rule.
The gate's first writes are destructive — it overwrites the issue body
with the errand, deletes `in-progress`, and rewrites the stage label —
so the number has to earn them, and exactly one fact does: the body
already carries the errand's own marker, written either by a previous
run of the gate or by the operator opening the fixture issue. The
opt-in is a line on the issue rather than a flag in the invoking shell,
so the tracker itself records which numbers the gate may destroy.
Absence of labels is not an opt-in: an untriaged issue carries none and
is somebody's unit of work from the moment it is filed. A pull-request
number is refused first and on its own, before the marker is looked at,
because the issues endpoint serves pull requests, `gh issue edit`
resolves one silently, and a pull request's body is exactly where the
marker gets quoted. Nothing is written before either refusal. After the
arms run the gate re-reads each ref whose push it verified: a ref that
moved is a failure, because evidence a session the gate did not launch
has since overwritten is not evidence — and a re-read that could not be
performed after three attempts is reported as a failed read rather than
as a moved ref, so a transient API error is not misreported as an
overwrite.

### ops.identity
A dispatched session runs as its own persona, never as the operator
(#43). `scripts/ops/work.sh` mints the launched persona's App token in
the one step between the last refusal and the launch, for that persona
only, and a run that launches nothing — a dry run, a multi-owner
stage, a harness with no row — mints nothing. A mint that fails is
fatal: the launcher refuses rather than falling back to whatever
credentials the shell carries. `scripts/ops/claim.sh` enforces the same
discipline: it reads back the created comment, and fails if the author
mismatches the expected persona (PR #183). The token reaches the child through the
environment of a subshell that `export`s it and then `exec`s — never an
argument (`env VAR=… ` would put it in a world-readable argv), never a
file, never a log line — and it overwrites `GH_TOKEN`/`GITHUB_TOKEN`
rather than inheriting them. Bash's own xtrace is the one log that
would otherwise catch it: `set -x` expands both the mint's command
substitution and every assignment of the value, so `bash -x
scripts/ops/work.sh <n>` used to write the live installation token to
stderr, and a Claude Code session captures tool stderr verbatim into an
on-disk transcript. The launcher therefore suppresses xtrace for the
window between the mint and the launch and restores the caller's
setting the moment the child returns; the suppression is a no-op when
xtrace is off, and a hermetic scenario runs the fixture launch under
`bash -x` on both rows and fails if the stub token appears.
`git` cannot read those variables at all, so it is pointed at
`scripts/auth/git-credential-persona <persona>`, a credential helper
that mints afresh on every `get` — a snapshot taken at launch expires
before a ninety-minute cap, at the one moment the work is finished and
about to be lost. The helper is installed through
`GIT_CONFIG_COUNT`/`GIT_CONFIG_KEY_n`/`GIT_CONFIG_VALUE_n` in the
child's environment only, so a crashed session leaves no credential
configuration behind and the operator's own config is untouched. The
four entries are appended at whatever `GIT_CONFIG_COUNT` the caller
already carries rather than written at index 0, so a caller that
installs `http.proxy` or `safe.directory` that way keeps its own
entries; with none inherited the offset is 0. Two of those entries are
empty resets. Git collects every matching
`credential.helper` and `credential.<url>.helper` into one ordered
list and tries them in turn; an empty value clears whatever has
accumulated, and a later entry appends to it, so without a reset an
operator's global helper answers the push first. Both keys are reset
rather than one as belt and braces — the resets are idempotent, and
they make the persona's helper the only one in the list however the
operator configured theirs. A fourth entry rewrites
`git@github.com:` to `https://github.com/`, because an SSH remote
never consults a credential helper at all.

### execution.placement
WHERE a persona runs is a second axis, orthogonal to which harness runs
it (#25, `intent/25-execution-model/`). `config/deployments.yaml` pins
persona→harness and `config/execution.yaml` pins persona→trigger and
persona→placement; neither file carries the other's key, so a move
between machines never edits a harness pin and never touches a persona
source. A binding is four keys and no others: `trigger`
(`repo-event`, `scheduled` or `manual`), `events` (required for
`repo-event`, forbidden otherwise), `placement`, and `max_cost_usd`.
That last key is **enforced** (#108). The gate checks it is a positive
number and the adapter prints it in its report line, so the intended
budget is stated in one place and visible in every run log; the adapter
then exports it as `WORK_MAX_USD` before it execs `ops.dispatch`, which
is what turns the number into a ceiling the machine holds. Both
enforcement paths already existed and were already tested — pre-emptive
for Claude Code via `--max-budget-usd`, post-hoc from the result
envelope for Antigravity, which takes no ceiling flag — so what #108
closed was the carry between the two halves, not either half. Until it
closed, `unattended.yml` set no ceiling and every unattended dispatch
ran uncapped while a config file declared a budget for it.

The carry lives in the adapter rather than in `ops.dispatch`, so that a
launch stays described by its flags rather than by a file the launcher
reads behind the caller's back, and so that D2's single parser of
`config/execution.yaml` keeps its monopoly. It is fail-closed in a
specific sense: a binding whose `max_cost_usd` is unreadable or not
positive **refuses the dispatch**, because the alternative — exporting
an empty value, which the launcher reads as "no ceiling" — would let a
parse failure silently buy an unlimited run. An explicit `WORK_MAX_USD`
from the caller still wins, so one run can be retuned from a command
line without editing the file every other run reads.

A ceiling that stops a run is a **runaway stop and not a budget**, and
the difference decides the numbers. Crossing it truncates the session:
under Claude Code the run dies mid-work and the persona posts nothing,
so the ceiling is paid for and nothing is delivered. Tuning one to the
median therefore buys half-finished reviews at full price. The
reviewers' declared 2.00 was set while the number was decorative and
was already below five of the six argus reviews measured through
2026-09-07 (the one under it, the gate-1a review on PR #188, finished
at $1.16) — which is the general hazard in switching a declared number
to an enforced one: it was never true, and nothing failed, because
nothing read it. v1 binds five personas — argus and atlas on
`pull_request` at `gh-actions`, athena, daedalus and odyssey `manual`
at `vm-local`; cassandra carries no binding, because her cadence is
#11's.

`scripts/ops/execution.py` is the only reader of that file, in every
context that needs it: `--check` is the gate, `--subscribers <event>`
prints the `persona<TAB>placement` pairs an event wakes, and
`--binding <persona>` prints one `trigger placement max_cost_usd` line
an adapter reports. A placement is legal exactly when
`scripts/placement/<name>/run.sh` exists — the directory name IS the
value, so reserving a name is merging a directory and nothing else, and
a binding on an unbuilt placement fails the gate naming the missing
directory rather than failing at run time. v1 ships `vm-local` and
`gh-actions`; `cloud-run-worker`, `cloud-run-instance` and
`agent-engine` are reserved by name only.

Every adapter has the same shape and is checked against it: it takes
`<number> --as <persona>` and no other flag, reads its binding from
`execution.py`, runs the D4 preflight, prints one report line, and
dispatches through the single `exec scripts/ops/work.sh <number> --as
<persona>` line — so a placement changes where a session runs and
nothing about what it does. The preflight is
`scripts/auth/mint_app_token.py <persona> --require-repo --quiet`,
which asserts the App's installation covers this checkout's repository
before any model is reached; the read is paginated, because an
installation on dozens of repositories answers its first page without
the one being asked about, and `--quiet` keeps the preflight's own
token out of every shell variable. The `gh-actions` adapter additionally
requires the private key to be present under the NAME the persona's
`authority.token` gives, and refuses by that name when it is not.

`.github/workflows/unattended.yml` is the trigger and never the
runtime. It notices an event, asks `--subscribers` who wants it, and
hands each pair to its adapter through a matrix — a matrix rather than
a loop because `secrets[format('{0}_APP_PRIVATE_KEY', matrix.upper)]`
can only be indexed by a matrix value, and because one openable run log
per reviewer is what makes an unattended review observable. A subscriber
placed somewhere a GitHub-hosted runner cannot host is one named skip
line, never a silent drop; the workflow's whole grant is
`contents: read, pull-requests: read`, every GitHub write being a
persona App's own; a fork pull request is excluded at the resolve job
and gets human review only; and the fork-secrets variant of the
pull-request trigger appears nowhere under `.github/workflows/`. The
`on:` list necessarily repeats the `events` values because GitHub
requires a static trigger list, so the `execution` gate holds the
workflow TO the config — a subscribed event the list omits fails the
gate, which makes the duplication a checked derivation rather than a
second source of truth.

The runner the trigger hands a pair to starts with neither harness
binary and no model credential, and a workflow that reached the adapter
in that state put a red check on every pull request (#146). Both are
the job's to supply, the same way for every persona, so that the
workflow stays blind to which harness a persona is pinned to: it
installs BOTH binaries through `scripts/ci/install_harness.sh` (one
script with `resolve`, `install` and `check`, cached by version, the
same command an operator runs on a new machine) and it authenticates
through workload identity federation — the job's one grant beyond read
is `id-token: write`, no cloud key is stored, and the credential file
the auth step writes is moved out of the checkout.

A persona launched on a runner runs with its harness's permission gate
bypassed, because a gate whose only answer is a prompt has nobody to
prompt and denies every read the persona was dispatched to make — down
to the `hold` re-read that trusted posting requires before any write,
so a gated reviewer cannot review AND must not post. What bounds the
persona is therefore not the gate but what the runner holds: the job's
own token cannot write, the App installation token is the single write
credential and lives an hour, and the placement is the boundary of the
grant — the bypass is the `gh-actions` adapter's, never `HEADLESS`'s,
because a headless session on an operator's machine has a human at the
keyboard.

Two things a bypassed session can reach anyway, both stated because
they are measured rather than feared. The cloud credential file is
moved out of the checkout as a defence against the workspace, not
against the persona: a bypassed session reads any path the runner can,
and the file's value is that it is short-lived and predict-only, not
that it is hidden. The persona's App private key is unset before the
launch, so the session does not INHERIT it — but `/proc/<pid>/environ`
is fixed at `exec` and no later unset can reach it, so the key stays
readable from the launcher's own live process for as long as it runs.
Withholding it in full needs the mint to happen in a process that has
exited before the session starts; until it does, the bound on the key
is the runner's lifetime, and this paragraph does not claim otherwise.

Federation is provisioned once per repository by
`scripts/setup/wif_setup.sh` (pool, provider, least-privilege service
account, predict-only role, the repository-scoped impersonation binding,
and the repository variables the workflow reads), idempotently and with
`--check` and `--dry-run`; until it has been run the job reports the
missing variable by name and stays green, the same treatment a missing
App key gets. The adapter and its contract are unchanged: the toolchain
and the credential are the environment an adapter runs in, never a
second dispatcher.

`scripts/ops/post.sh <number> --as <persona> --body-file <path>` is the
one write path an unattended run has. The body is always a file and
there is deliberately no `--body` flag. `hold` is re-read IMMEDIATELY
BEFORE the write, not only at dispatch: a review that starts against an
unheld pull request and finishes four minutes after a human held it is
computed, paid for, and posts nothing. For a pull request the hold set
is the pull request AND every issue it closes, resolved by the same
code `ops.dispatch` resolves on (`scripts/ops/lib/github.sh`, sourced by
both, so the two cannot disagree) — every closing reference, not the
first, because suppressing a post is never the ambiguous half of that
rule. A suppressed post is GREEN: exit 0 and one line naming the held
number, since a red X on every held pull request trains the room to
ignore the signal. Tests: `scripts/ops/tests/execution_test.sh`,
`placement_test.sh` and `post_test.sh`, all three run by the
`execution` gate (`ci.gates`).

## Agreed, not yet built

Each entry is on the record as a tracker issue; it moves into the
spec body when its implementing PR merges.

- **review.automation** — the review duty itself and the
  `status:in-review` writer (#8, #9); the argus and atlas bindings in
  `config/execution.yaml` are inert until then, which is what #25's
  staged rollout intends.
- **intake.automation** — headless Athena on `intent:new` (#10).
- **maintain.watchers** — Cassandra, control bands, seeded incident
  (#11).
