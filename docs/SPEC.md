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
is bounded by construction: exactly nine `##` sections in a fixed
order, at most 150 lines, at most one diagram, and exactly one
command shown as an instruction (`scripts/ops/work.sh <n>`) — a tenth
topic is a link from its last section, never a tenth section.
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
secret — an Actions secret or a local
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
of executing it). WHAT fires each rung is the `advances_on` column of
`personas/lifecycle.json` (`personas.resume`, #36), read and never
inferred (PR #67). Three rungs advance on an added file: the script
reads the pushed range for ADDED files matching
`intent/<issue>-<slug>/{intent,spec,plan}.md` and mirrors the merge
gate into the label — intent.md → `status:spec`, spec.md →
`status:build`, plan.md → `status:implementing`. The implement rung
owes no file, because what it owes is code, so it advances on a
merged PULL REQUEST: the range's first-parent commits are walked
oldest first, `gh api repos/<repo>/commits/<sha>/pulls` says which
pull requests each belongs to, those merged into the default branch
are kept, and each resolves to at most one issue by its BRANCH NAME
first and a closing keyword second — the reverse of `ops.dispatch`'s
order, because an implementing pull request must not carry a closing
keyword at all. The two signals disagreeing is a counted failure, not
a guess, and a commit belonging to no pull request advances nothing.
An issue with both an artifact and a merged pull request in one range
takes the furthest rung of the two, ranked by position in the ladder
file. WHICH label a rung advances to, and the line posted when it
does, are likewise not written in the script but read from the same
row — one comment per transition naming what the next stage owes. A
row with no `advances_to` writes no label and a row with no
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
merge rung's label, whose pull request merged in the range, is a red
counted failure that writes nothing at all, because the implementing
pull request carried a closing keyword it must not carry (PR #67). The
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
tokens-per-message. Tests: `scripts/ops/tests/session_spend_test.sh`.

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
session work a stage the labels say is not current. Six refusals,
checked in order before anything is dispatched and each exiting 2
with the condition named: `hold`; closed, or `status:review-stuck`;
`blocked`; more than one `status:*` (reported, never guessed, and
never `hold`-ed — the advancer is the single writer of the circuit
breaker); `in-progress` claimed by another actor; and `--as` naming a
persona that does not own the stage. When the number given is a pull
request, those refusals read the UNION of the pull request's own labels
and the resolved issue's — a `hold` on either side refuses, and the
message names the side that carries it, or both sides when both do,
because the circuit breaker is
placed where the operator is looking and resolving to the issue must
not discard it (#50, Atlas AT-1, PR #95; both sides, PR #99). The
stage is not part of that
union:
it is derived from the issue's labels alone, since the state machine
belongs to the unit of work and a `status:*` label on a pull request
must not decide which rung the issue is on. The claim's holder is the
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
Tests: `scripts/ops/tests/work_test.sh` against stubs, and
`scripts/ops/smoke_launch.sh <scratch-issue>` for one real launch per
harness — three named observables each, with the claim half of the
Antigravity run reported as `BLOCKED ON #47` until that App's
`issues: write` permission is granted, rather than asserted to fail.

### ops.identity
A dispatched session runs as its own persona, never as the operator
(#43). `scripts/ops/work.sh` mints the launched persona's App token in
the one step between the last refusal and the launch, for that persona
only, and a run that launches nothing — a dry run, a multi-owner
stage, a harness with no row — mints nothing. A mint that fails is
fatal: the launcher refuses rather than falling back to whatever
credentials the shell carries. The token reaches the child through the
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

## Agreed, not yet built

Each entry is on the record as a tracker issue; it moves into the
spec body when its implementing PR merges.

- **review.automation** — Argus workflow, Atlas sidecar, consensus
  (#8, #9).
- **intake.automation** — headless Athena on `intent:new` (#10).
- **maintain.watchers** — Cassandra, control bands, seeded incident
  (#11).
- **loop.autonomous** — the system merges each rung and dispatches the
  next; the human is the escalation path (#64,
  `intent/64-autonomous-loop/`). A deterministic merge gate — bash +
  `gh` + `jq`, no model call, `DRY_RUN=1` honoured — merges a pull
  request only when eleven recorded facts all hold, among them green
  required checks, both reviewers' verdicts against the current head
  OID, an empty blocking set, no `hold` or `blocked`, and a merging
  identity that is not the author; it writes under a GitHub App
  installation distinct from every persona and from `GITHUB_TOKEN`,
  holding `contents: write` and `pull_requests: write` and nothing
  else. The transition that writes the `status:*` label dispatches the
  next rung in the same run. Every issue carries a rung-dispatch
  ceiling and a spend ceiling counted in a per-issue loop-ledger
  comment, and a ratchet on that ledger keeps the ladder monotonic.
  Anything else escalates: the single `status:*` label is swapped for
  `status:review-stuck` and one comment names both positions and the
  decision asked for. Autonomy is one fail-closed config value, so the
  same design runs with human merges. Reverses the human-merge rule in
  AGENTS.md, INTENT.md, README.md, `tracker.workflow` and
  `review.policy`, which the implementing PR amends. Depends on #8,
  #9, #25, #72, #73 and #74.
