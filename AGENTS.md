# Shared standards for all agents

Everything in this file applies to EVERY agent working in this
repository, regardless of harness or model family (Claude Code,
Antigravity/Gemini, or anything added later). Agents are
model-agnostic roles; which model family backs a given agent is a
deployment pin that can change without changing these standards.

Harness-specific configuration — verified model tiers, cache and cost
mechanics, context ceilings, session behavior rules — lives in
[CLAUDE.md](CLAUDE.md) (Claude Code) and [GEMINI.md](GEMINI.md)
(Gemini/Antigravity); both defer to this file for everything below.
Keep one source of truth: a rule that applies to all agents belongs
here, never duplicated per harness file.

Persona-specific standards (reviewer protocols, implementer rules,
authority levels) are NOT in this file: they belong to the canonical
persona definitions under `personas/` and are compiled per harness.
This file carries only what binds every agent equally.

## Session checklist

The tracker loop (detailed under "Working the tracker" below), in the
order it happens. Every session, every harness, before the first
edit. The never-list at the end is absolute.

1. **Claim and create worktree.** Run
   `CLAIM_ACTOR=<persona> CLAIM_SESSION=<name> scripts/ops/claim.sh <issue> [<slug>]`.
   This verifies the issue is claimable, posts the claim comment, and creates
   your worktree. Pass the `<slug>` explicitly if an `intent/<issue>-<slug>/`
   folder exists. **By-hand fallback** (if the script fails):
   - *Verify:* The issue must be open, have no `in-progress`, no `hold`, and
     closed dependencies. Pointed at a closed issue? It is not a work item:
     file a follow-up ("Before filing an issue" below) and work that. Never
     reuse a closed issue's number.
   - *Claim:* Add `in-progress` and post the one-line claim comment: who,
     which session, which stage, which worktree path.
   - *Worktree:* Create it from `origin/main` on `<actor>/<issue>-<slug>`.
     If an `intent/<issue>-*/` folder exists, the branch slug MUST be that
     folder's slug. Do every edit and commit there. The primary checkout is
     read-only reference — except its `runs/`, which is the one shared run
     root for every session ("Outputs go in timestamped run folders" below);
     never write `runs/` inside a worktree.
2. **Read the chain.** AGENTS.md → INTENT.md → docs/SPEC.md → the
   issue thread bottom-up.
3. **Produce the stage's artifact, commit by path, open a PR.** A
   bare push is not a delivery; a human merges. After a workflow-file
   change merges, failed PR checks need a rebase onto main, never
   `gh run rerun` (a `pull_request` run executes against the head+base
   merge ref, so the stale ref reruns identically). When committing your
   work as a persona, author the commit explicitly as your persona App identity
   (e.g. `git -c user.name="<identity>" -c user.email="<bot_user_id>+<identity>@users.noreply.github.com" commit ...`), deriving the ID via `gh api users/<identity> -q .id` — do not rely on push credentials.
4. **Hand off.** Done/Decided/Next/Blocked comment on the issue; if
   pausing, drop `in-progress`; after the merge, remove your worktree.

Never: commit, stage, stash or checkout in the primary checkout; work
an issue that is closed or that you have not claimed; push a branch
without opening a PR; document a runtime mechanism (a flag, a tool, a
workspace mode) you have not verified against that runtime.

## Document map and reading order

Every session starts by walking the same chain, in this order. Each
document answers one question; do not look for an answer in the wrong
document.

1. **AGENTS.md** (this file) — *how every agent works here.* Binding
   on all agents. The harness entry point (CLAUDE.md or GEMINI.md)
   loads alongside it and adds only harness mechanics: verified model
   bindings, cache pricing, context ceilings.
2. **INTENT.md** — *why the system exists and where it is going.*
   The founding intent, the persona cast, the lifecycle every change
   follows, and the open questions. Read it before proposing
   anything, so you don't re-open what is already decided or settled
   as out of scope.
3. **docs/SPEC.md** — *what the system does right now.* The living
   spec, upserted by every behavior-changing PR. Trust it over
   memory, chat history, or intuition about earlier sessions. Until
   it exists, INTENT.md's Proposed outcome is the nearest truth.
4. **The work item** — *what this session is for.* The GitHub issue
   being worked, its labels (the lifecycle state), its thread (the
   handoff trail), and its `intent/<issue>-<slug>/` folder: intent.md
   (what was asked), spec.md (what was decided, with the Decisions
   table), plan.md (how to build it) — read whichever the completed
   stage gates have produced.
5. **The persona file**, when acting as one — *who you are in this
   session.* The persona's compiled instructions for this harness
   govern role behavior (protocol, authority, tier); this file still
   binds everything else.
6. **docs/PLAYBOOK.md** — *how the current backlog-closeout exercise
   is run and where to pick up.* The operating loop (dispatch prompt
   files, independent verification, fix rounds), which issues to pick
   when resuming, the YOLO on/off target, and the field notes behind
   the rules. Read it before choosing work in any session joining the
   exercise. Not the same document as docs/BLOG.md below: BLOG.md is
   the design narrative this system implements; PLAYBOOK.md is the
   hands-on operating guide.

Reference material, read on demand rather than at session start:
docs/BLOG.md (the playbook this system implements) and
docs/CONTEXT.md (prior art and adopted conventions) inform design
sessions; implementation sessions rarely need them. Never treat
compiled targets (`.claude/agents/`, `.agents/agents/`) as sources —
the canonical definitions live in `personas/`, and CI fails the build
if the two drift.

## Sessions are ephemeral — state lives in the tracker

No fact may live only in a session. A transcript is gone (or too
expensive to carry) by the next session, and the next session may be
a different harness, model, persona, or person. Handoff between
sessions therefore has exactly one mechanism: the GitHub issue.

- **One session, one work item.** A session serves one issue at one
  lifecycle stage (the one-session-per-phase rule above, made
  concrete). Name the issue at session start; every artifact the
  session produces traces to it.
- **The issue thread is the session's memory.** Decisions, state, and
  pointers to artifacts land in the issue thread and the committed
  files it references — never only in chat. Lifecycle state lives in
  the issue's labels, never in prose.
- **Every session ends with a handoff comment** on its issue, in this
  shape:

  ```text
  Done:    what changed, with artifact paths and PR links
  Decided: each decision on one line (or "none")
  Next:    the single next action, concrete enough to start cold
  Blocked: what needs a human, or "nothing"
  ```

  The bar: a stranger on a different harness resumes from the
  handoff comment plus the document chain above, without the
  transcript. If they couldn't, the handoff is not done.
- **Session-end reconciliation** (extends the run-folder bookkeeping
  above): before ending, every decision discussed is an issue, a PR,
  or an explicit "deferred, no tracker" line in the handoff; every
  run artifact carries its disposition; uncommitted or unpushed work
  is named in the handoff, not left implicit.
- **Bootstrap exception:** until the GitHub repo and its issues
  exist, INTENT.md is the tracker of record and handoffs append to
  its disposition footnote. This exception ends the day the first
  issue is filed.

## Working the tracker: pick, claim, work, hand off

The repository is `github.com/evekhm/agentic-sdlc`. This is the
session workflow — the same loop whether the session is a human
driving a harness, a compiled persona, or (later) an automated
workflow. It is what makes parallel sessions safe and any session
resumable cold.

1. **Pick.** Open the pinned **tracker issue** — the index of all
   work, grouped by bootstrap rung, one checklist line per issue. An
   issue is *claimable* when: it is open, it has no `in-progress`
   label, every issue named in its "Depends on" line is closed, and
   no `hold` label is present anywhere it points. A closed issue is
   never a work item, whoever or whatever pointed you at it: search
   the tracker ("Before filing an issue"), file the follow-up naming
   the closed issue as the one it extends, and work the follow-up.
2. **Claim and create worktree.** Run
   `CLAIM_ACTOR=<persona> CLAIM_SESSION=<name> scripts/ops/claim.sh <issue> [<slug>]`
   to claim the issue and create your worktree. The claim is the mutex: **the
   issue is the unit of parallelism** — two sessions never work the same issue,
   and any number of sessions may work different claimable issues
   concurrently. Scope issues to disjoint paths so parallel PRs don't
   collide.
3. **Read.** Walk the document chain (above), then the issue thread
   bottom-up: the last handoff comment says exactly where to resume.
4. **Work.** In your own worktree (below), on a branch named
   `<actor>/<issue>-<slug>`, produce the
   artifact the current lifecycle stage owes (see INTENT.md's
   lifecycle: intent.md → spec.md → plan.md → code+tests). Everything
   reaches `main` by PR; the PR body carries `Closes #<n>` only when
   it completes the issue's final stage — in the five-rung flow the
   final rung produces a review and not a pull request, so no PR in
   that flow carries `Closes #<n>` and the human closes the item; the
   defect-repair path (#32) is unchanged, because there the fix PR
   *is* the final stage.
5. **Hand off.** End with the Done/Decided/Next/Blocked comment on
   the issue (format above). If pausing rather than finishing, remove
   `in-progress` so another session can claim. Tick the tracker
   issue's checklist line when an issue closes.
6. **Gate.** A human merges. The merge *is* the state transition that
   makes the next stage claimable — state advances only through the
   tracker and `main`, never through anyone's memory.

**One session, one worktree, one issue.** The claim is the mutex at
the tracker; the filesystem must match it, or sessions that honor the
claim still collide in one working tree: uncommitted edits from one
session appear in another's reads, and branch switches clobber work.
Several sessions, on more than one harness, run against this repo on
one machine at the same time. Git worktrees are the mechanism on
every harness; only the tooling around them differs, and the harness
file names it.

- **Look before claiming.** `scripts/ops/claim.sh` will refuse to claim if a
  peer already holds the issue. If claiming by hand, run `git worktree list` (a
  locked or dirty worktree is someone's live work) and read the issue's last
  claim comment; the harness file adds its own peer check. If a peer already
  holds the issue, stand down and report instead of duplicating.
- **The primary checkout** (the directory the repo was cloned into,
  wherever that is on the machine) is read-only reference and stays
  on a clean `main`: never edit, stash, checkout, commit or stage
  there. If you find it dirty, report it and leave the changes alone —
  they are a peer's. Prose is not enough to catch this reliably (it
  was violated three times in one session on 2026-09-04, once
  destroying a peer's uncommitted work): run `scripts/ops/hooks/install.sh`
  once per machine to install a `pre-commit` hook, shared by the
  primary checkout and every linked worktree, that refuses any commit
  whose working tree is the primary checkout. It is a last-line check
  on the one moment that's interceptable — the commit itself — not a
  substitute for entering a worktree before the first edit.
- **Enter your own worktree before the first edit**. `scripts/ops/claim.sh`
  creates the worktree for you. If doing it by hand, create it from
  `origin/main`: `git fetch origin && git worktree add -b <actor>/<n>-<slug>
  .claude/worktrees/<actor>-<n>-<slug> origin/main`. The `.claude/worktrees/`
  location is shared by every harness so one report covers them all.
- **Work only there.** All reads for editing, all commits, and the
  push, PR and merge for the issue happen from your worktree and
  touch only files your issue owns. Commit by path, never `git add .`
  or `commit -a`, so a stray file can't ride along. Fetching is always
  allowed anywhere.
- **Finish the circle.** After the PR merges: post the handoff
  comment, `git worktree remove <path>` for your own worktree, delete
  the local branch, and confirm with `git worktree list` that it is
  gone. Never remove a worktree you did not create; a dirty one is a
  peer's live work and only the human prunes stale ones.

**Worktree hygiene cadence.** `scripts/ops/worktrees.sh` is the one
tool for this: it lists every worktree with lock (and whether the
lock's pid is alive), dirty count, unpushed commits, merged state and a
verdict (`safe`, `dirty`, `unpushed`, `locked`); `--prune` removes only
`safe` worktrees and local branches merged into `origin/main`;
`--prune-remote` also deletes merged remote branches; `DRY_RUN=1`
previews. The cadence:

- **Every session, at start:** run the report (read-only). If it shows
  `safe` entries, or a `locked:pid-dead` one, tell the user in the
  first message; do not prune on your own.
- **The human, or a session the human explicitly asks:** run
  `--prune-remote` at the end of each working day and right after a PR
  stack lands (deleting merged head branches is also what retargets
  stacked children). Preview with `DRY_RUN=1` first when peers are
  busy.
- **`dirty`, `unpushed`, `locked` are never pruned by the script.**
  Each is resolved by its owner: resume it, land it, or discard it by
  hand. A `locked:pid-dead` entry is a crashed session or subagent;
  its owner unlocks it (`git worktree unlock <path>`) after checking
  the diff.

**The labels are the state machine** (#4, `intent/4-labels/`). Five
are human-facing and filed by people: `intent:new` (intake),
`in-progress` (the claim mutex above), `hold`, `blocked`, and
`bootstrap`. The lifecycle stage is a single `status:*` label — the
ladder `status:planning` → `status:spec` → `status:build` →
`status:implementing` → `status:in-review` — and **at most one is set
at a time**: a pair is not a stage, it is two state machines
disagreeing, so automation that finds one applies `hold` and stops.
`hold` is the circuit breaker and it is absolute: while it is present
no automation touches the issue, checked before anything else.
Reviewers count their rounds with `review:1`/`review:2`/`review:3`;
`review:3` escalates to `status:review-stuck`, where humans take over.
Nobody sets a stage label by hand as a way of moving work:
`.github/workflows/lifecycle.yml` mirrors the merge gates into the
ladder (intent.md merged → `status:spec`, an *Approved* spec.md →
`status:build`, plan.md → `status:implementing`), deterministically
and with no model call, because the merge is still the transition and
the label is only its shadow.

### Dispatch has one door

`scripts/ops/work.sh <issue>` is how a stage starts. It reads the
issue, derives the stage and its owner from the labels above, and
either prints the dispatch or launches that persona's session with its
own identity — so the choice of who works an issue is made by the
table, once, in front of the operator, and not by whoever happens to be
at a keyboard.

No session acts as a persona it is not. A sub-agent spawned inside a
session is the acting persona's own helper, drawn from its
`delegates_to` list, and it works under that persona's name and
credentials; it never becomes a second persona at a stage.

A bootstrap dispatch — a persona launched by hand because the door is
what is being built or repaired — is allowed only when the claim
comment of step 2 declares it on its first line, naming the persona and
the reason. An undeclared bootstrap is indistinguishable from a session
working out of turn.

### GitHub writes from a bot identity go through REST

A persona's App installation token and the operator bot's PAT carry
repository permissions only — no organization read (`read:org` on a
PAT, organization Members on an App). Some `gh` porcelain commands run
a GraphQL query over organization fields *before* they write, so they
fail on scope even though the write itself is permitted and every
persona already holds the repository permission it needs
(`scripts/auth/app_manifests.yaml`). Known on 2026-09-04: `gh pr edit`
(team `login`/`name`/`slug` fields, PR #106) and `gh issue view`
(projectCards). The rule (#112):

- A scope error on a `gh` porcelain command is not a missing App
  grant: on a user-owned repository an App has no organization
  permission to widen, and its repository permissions already cover
  the write. Use the REST endpoint through `gh api`, which asks for
  exactly the permission the write needs. (The operator bot's classic
  PAT is the one place `read:org` can be added; the account belongs to
  no organization, so the scope is inert and is a convenience for
  interactive sessions only — it does nothing for personas.)
- Edit a pull request body:
  `gh api -X PATCH repos/<owner>/<repo>/pulls/<n> -F body=@<file>`.
- Read an issue or a pull request:
  `gh api repos/<owner>/<repo>/issues/<n>` (a pull request is an
  issue for reads), never `gh issue view`.
- `gh pr create`, `gh issue create`, `gh issue comment`,
  `gh issue edit --add-label` are verified on these tokens and stay
  in use; personas comment through `scripts/ops/post.sh`.

**There is no STATUS.md.** Status in a committed file goes stale the
moment two sessions run in parallel, and every update costs a
commit/PR that can conflict. The pinned tracker issue plus per-issue
handoff comments carry the same information append-only and
conflict-free. "Where do I pick up?" is always answered by: tracker
issue → first unchecked line whose issue is claimable → its last
handoff comment.

## Outputs go in timestamped run folders

- All experiment, eval, analysis, and working outputs go in
  `runs/YYYY-MM-DD_<slug>/` (e.g. `runs/2026-09-01_intent-draft/`) —
  never loose files in the repo root that get overwritten by the next
  session.
- `runs/` is local scratch and is gitignored. Anything worth keeping
  graduates from a run folder into a real, reviewed location (`docs/`,
  a script, a PR) — sanitized first.
- **One `runs/` per machine: the primary checkout's.** Worktrees are
  for code; artifacts are shared across sessions and read by the human
  from the primary checkout (the one open in their IDE). Because
  `runs/` is gitignored, a run folder written inside a worktree never
  travels with the branch and is deleted with the worktree. So every
  session, in every harness and worktree, resolves the run root to
  the primary checkout before writing:

  ```bash
  RUNS_ROOT="$(cd "$(git rev-parse --git-common-dir)/.." && pwd)/runs"
  ```

  From the primary checkout this is `./runs`; from any worktree it is
  the same directory. A `runs/` that appears inside a worktree is a
  bug: move its contents to the shared root before the worktree is
  removed.
- **Bookkeeping: every run artifact records its disposition.** By the
  time a session ends, every artifact the session produced carries a
  disposition naming what became of it: the issue or PR it turned
  into, the doc it graduated into, or an explicit "deferred, no
  tracker". Record it at the moment the action happens; artifacts
  still disposition-less at session end get reconciled then (that is
  when "deferred, no tracker" is written, so no artifact ends the
  session unaccounted). For prose and text artifacts, append the
  disposition as a footnote at the end of the file. For
  machine-readable artifacts (JSON, CSV, JSONL — anything a parser
  consumes), never append to the file itself: put the same line in a
  sidecar `<name>.disposition.md` next to it. Reading an artifact (or
  its sidecar) must answer "was this accounted for?" without
  searching. Format:

  ```text
  ---
  Disposition (YYYY-MM-DD): filed as #<issue>; graduated to <path> via PR #<n>.
  ```

## No document sprawl

- Consolidate into existing docs; do not create a new doc when an
  existing one covers the topic. Before creating any file, search for
  an existing one that already serves the purpose.
- Never generate derivative twins of a document (summaries, HTML
  exports, `_v2` copies) as checked-in files.

## The living spec (docs/SPEC.md)

[docs/SPEC.md](docs/SPEC.md) specifies what the system does. It is
maintained by the PRs that change behavior — never regenerated
wholesale — and this discipline binds every implementer that opens a
PR here (agent or human), regardless of harness:

- **Any PR that changes system behavior updates docs/SPEC.md in the
  same PR**: add entries for new behavior, reword superseded entries
  in place, move an *Agreed, not yet built* entry into the spec body
  when its implementing PR opens, and delete entries a revert
  removes. Upsert, never append duplicates; git history is the
  archive.
- Entries are keyed by stable dotted capability IDs
  (`component.capability`). An ID survives rewording and changes
  only when the capability itself is replaced. An entry added or
  changed after the spec's initial version cites its PR inline:
  `(PR #123)`.
- Statements are present tense and describe merged code only. Where
  behavior is shipped-but-broken, disabled, or prompt-only rather
  than code-enforced, the entry or the Deployment status section
  says so plainly. Planned work goes only to *Agreed, not yet
  built*, and only when an explicit material decision is on the
  record (issue or thread reference required) — never filler.
- A PR that touches behavior-bearing paths without changing behavior
  (refactor, comments, test-only) declares that in the PR body with
  the machine marker line `Spec-impact: none — <reason>`. This is a
  literal, grep-matched prefix (`scripts/ci/spec_check.sh`), not a
  sentence to paraphrase: "no spec impact", "documentation-only" or
  any other wording that merely states the same thing in prose fails
  the check. Write the line exactly as shown, verbatim, including the
  em dash before the reason.
- CI enforces this: `scripts/ci/spec_check.sh`, run by the
  `spec-check` job in `.github/workflows/ci-gates.yml`, fails a PR
  that touches behavior-bearing paths unless the diff touches
  docs/SPEC.md or the body carries the marker. Run it before you push
  — `bash scripts/ci/spec_check.sh <base-ref>` — rather than
  discovering it as a red X. The check verifies that the choice was
  made; whether the entry or the reason is *good* stays with the
  reviewers.
- Spec entries are claims and are reviewed like claims: reviewers
  verify each added or changed statement against the diff that ships
  it, and flag spec statements the diff does not support.

## Context and cost discipline

Long sessions on large-context models burn money through cache reads:
every API call re-reads the entire accumulated context. Keep the main
conversation lean.

- Delegate implementation-heavy work to subagents where the harness
  supports them: multi-file greps, batch edits, running test suites,
  reading large files or diffs. The subagent's tool output stays out
  of the main context; only its summary returns. The main loop is for
  decisions, design discussion, and review of results — not for
  running 100+ shell/edit calls directly.
- Never pull large tool output into the main conversation. Pipe
  through `head`/`grep`/`jq`, read file excerpts rather than whole
  files, or delegate the reading to a search subagent. A large dump
  is re-read (and re-billed) on every later call in the session.
- **200K is the working ceiling for any single context** — main
  session or subagent, on every harness. Crossing it either re-prices
  the whole request at a long-context premium (both vendors) or
  degrades quality, usually both. When a session approaches the
  ceiling, compact or hand off to a fresh session; the harness file
  states the exact mechanics and pricing for its vendor.
- One session per phase. When work shifts phase (design →
  implementation, implementation → review) or scope changes
  materially, say so and recommend ending the session and starting
  fresh from the spec or issue instead of carrying the transcript
  forward.
- **Warn before it gets expensive.** When the conversation has grown
  very large (deep into a long multi-hour session), the agent
  proactively flags that the context is expensive — stating the
  approximate accumulated context size — and suggests compacting or a
  fresh session with a short handoff. Silence while the meter runs is
  a protocol violation, not politeness.
- Route mechanical, fully specified subagent work (batch edits from a
  spec, greps/searches, running tests, formatting sweeps) to a cheaper
  model tier than the main conversation, where the harness supports
  per-agent models. The harness file (CLAUDE.md / GEMINI.md) names the
  tiers verified for that harness. Reserve the frontier tier for
  design, review, and debugging that genuinely needs it.

## Before filing an issue

Search the tracker first, every time, before creating a new issue:

1. List open issues carrying the relevant `area:*` label
   (e.g. `gh issue list --state open --label area:personas`).
2. Search open issues and PRs by the feature's key terms in title and
   body (e.g. `gh search issues --repo <owner>/<repo> --state open
   "<term>"` and the same query via `gh search prs`).
3. If the issue concerns specific file(s) — nearly always true for a
   defect you just diagnosed rather than a feature you're proposing —
   also run a **file-scoped** check, identity-agnostic since every
   session's writes land under the same handful of shared bot
   identities: `scripts/ops/tracker_search.sh --files <path>...
   [--terms <term>...]` wraps both this and step 2 in one command
   (`gh pr list --json number,title,files` filtered to those paths,
   plus the keyword search) and exits 2 the moment anything matches —
   read its output before filing anything. A keyword search alone
   misses a PR whose title and body don't happen to use your words;
   the file-scoped pass catches it regardless of phrasing. Run it
   again immediately before `gh pr create`, not only when you filed
   the issue — minutes are enough for a peer's fix to land
   (agentic-sdlc #130/PR #132 duplicated #126/PR #127 this way on
   2026-09-04: same defect, independently diagnosed, 19 minutes apart,
   because the search ran once at issue-filing time and was never
   repeated at PR time — and #141 duplicated #129/PR #138 the same
   way in the same session, even with this rule already written down,
   because writing the rule down did not make the check run. If the
   tool reports a match, that is the point of the check working, not
   an obstacle to route around).
4. Read the matches — including their comment threads. Agreed findings
   in an existing thread are settled design; do not re-propose what a
   thread has already killed.

Then act on what you found:

- A matching open issue exists → comment on it or extend its plan; do
  not open a duplicate.
- Related issues exist but none covers the ask → the new issue must
  name each related issue and state the relationship explicitly:
  absorbs, refines, depends on, or proposes superseding. Import their
  agreed findings as constraints.
- Nothing related exists → say so in the new issue ("tracker searched,
  no prior art: <labels/terms searched>").

A new issue that ignores an existing thread duplicates tracking,
splits the discussion, and burns reviewer rounds re-litigating
settled findings. This applies even to a defect you found incidentally
while working something else, under direct pressure to "just fix it
now": the defect-repair path (#32) skips the claim ceremony, not this
search.

## Subagent model tiers

Per the context and cost discipline above, mechanical subagent work
runs on a cheaper model tier. The tier ladder is semantic and shared
across harnesses — five grades, each defined by the work it is
trusted with:

- `FAST_TIER` — deterministic sweeps, trivial lookups and searches,
  routing, wrapping a deterministic script and reporting its result.
- `MECHANICAL_TIER` — mechanical, fully specified work: batch edits
  from an explicit spec, multi-file greps/searches, running test
  suites and reporting results, formatting sweeps, applying a
  reviewer's named fixes. No decisions.
- `IMPLEMENTATION_TIER` — spec-driven implementation: a
  dispatch-ready spec (target SHA, file-level steps, test plan,
  acceptance criteria) with no open design decisions.
- `REVIEW_TIER` — evidence-based review and analysis: reading a diff
  against a protocol, diagnosing from logs and metrics.
- `FRONTIER_TIER` — design, architecture, adversarial spec grilling,
  tricky debugging.

Which model serves each tier is a harness fact, not a shared
standard: [CLAUDE.md](CLAUDE.md) binds the tiers for interactive
Claude Code sessions, [GEMINI.md](GEMINI.md) for Gemini/Antigravity
sessions. Never hardcode vendor model IDs in persona instructions or
shared specs — personas name a semantic tier; the tier→model mapping
lives in one central config per harness (`config/model_tiers.yaml`
once the compiler exists). Adjacent tiers may share one model on a
given harness; the ladder still holds, because the tier names the
task contract (what the agent may decide), not just the price.
Workflow-driven agents without a subagent tool are exempt: they run
single-loop on the model their workflow pins.

## Cost of execution

The harness never reports what a strategy costs at the moment it is
chosen; the only feedback channel is the invoice, days later. These
rules substitute for the missing signal, on every harness. The
numbers cited were measured in the predecessor repo
(`agentic-experiments-lab`, docs/COST_LESSONS.md there).

- Before any read-many task (N threads, N files, N logs), ask whether
  item N needs item N−1's context. If not, fan out to parallel
  subagents. Reading N items sequentially in one context is O(N²):
  item 40 re-sends items 1–39 alongside it. Measured: 102 review
  threads read by 15 subagents cost $121.66 ($0.27/message); the
  undelegated slice of the same session ran $1.44/message.
- Spawning subagents is not delegating. If the parent still reads the
  raw material, the fan-out bought nothing — the parent must receive
  summaries and never the source.
- **Looping and polling: match the cadence to the prompt-cache TTL,
  and pick both together.** An interval longer than the TTL turns
  every pass into a full cache write with no read to amortize it.
  The TTLs, knobs, and prices are harness facts — see the harness
  file. A 15-minute loop on a 5-minute default TTL cost ~$952 of one
  session's $1,057.
- Long-lived contexts only grow. Finish a task, start a fresh
  session. Every tool result is permanent context: dump a 5,000-line
  file once and it is re-sent on every remaining turn. A high cache
  hit rate does not fix this — one session ran at 95% and still cost
  $2,576, because it averaged 441K tokens per message.
- Rank spend in dollars, never in tokens. Cache writes cost a
  multiple of base input while reads cost a fraction, so a token
  ranking and a dollar ranking of the same week name different
  culprits. Measure with the harness's spend tooling (the harness
  file names it) and read two numbers: hit rate
  `read/(read+write+fresh)` for price, and tokens-per-message for
  volume. Both, always — either one alone hides the other.
