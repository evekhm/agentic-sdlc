# Claude Code harness configuration

Everything that binds agents regardless of harness lives in
[AGENTS.md](AGENTS.md): the shared practices (run folders, no document
sprawl, the living spec, context and cost discipline, subagent model
tiers, cost of execution). Read and follow AGENTS.md first; this file
adds only what is specific to the Claude Code harness and its Vertex
deployment.

# Subagent model tiers

Bindings for the shared task taxonomy in AGENTS.md ("Subagent model
tiers"), for sessions whose harness exposes subagent spawning
(interactive Claude Code sessions with the Agent tool); workflow-driven
agents without a subagent tool are exempt per that section:

- `FAST_TIER` (deterministic sweeps, trivial lookups, routing):
  `model="haiku"` on the Agent call.
- `MECHANICAL_TIER` (batch edits from a spec, greps, test runs,
  formatting, named fixes): the `mechanic` agent
  (`~/.claude/agents/mechanic.md`, runs claude-sonnet-5; a repo-local
  compiled copy will replace it once the persona compiler exists).
  Never pass `model="sonnet"` — on this Vertex deployment that alias
  resolves to sonnet-4.5, which is NOT enabled; sonnet-5 itself is
  enabled and works.
- `IMPLEMENTATION_TIER` (dispatch-ready spec, no open design
  decisions): sonnet-5 via a dedicated agent definition (the
  predecessor's `.agents/agents/coder.md` is the template; a
  repo-local compiled `coder` will bind this tier). Same
  model-alias caveat as MECHANICAL.
- `REVIEW_TIER` (evidence-based review/analysis): `model="opus"`.
- `FRONTIER_TIER` (design, adversarial grilling, tricky debugging):
  `model="opus"`, or omit the override only when the subagent
  genuinely needs the main model's frontier reasoning — inheriting
  it costs more per token.

# Parallel sessions

Several Claude Code sessions run against this repo on one machine at
the same time. AGENTS.md makes the issue the unit of parallelism (the
`in-progress` claim is the mutex); the filesystem must match it, or
sessions that honor the claim still collide in one working tree. The
rule is **one session, one worktree, one issue**, and the process is:

1. **Look before claiming.** Run ListAgents (busy peers are named
   `agentic-sdlc-*`), `git worktree list` (a locked or dirty worktree is
   someone's live work), and read the issue's last claim comment. If a
   peer already holds the issue, SendMessage that session and stand
   down; report to the user instead of duplicating.
2. **Claim with your name.** Add `in-progress` and post the one-line
   claim per AGENTS.md, including your session name from ListAgents and
   the worktree path you are about to create, so peers can find and
   message you.
3. **Enter your own worktree before the first edit.** The primary
   checkout (the directory the repo was cloned into, wherever that is
   on this machine) is read-only reference and stays on a clean `main`:
   never edit, stash, checkout, commit or stage there. If you find it
   dirty, report it and leave the changes alone — they are a peer's.
   Create the worktree from `origin/main` on a `<actor>/<issue>-<slug>`
   branch, either by launching the session with `claude -w <name>`,
   by calling EnterWorktree, or by hand:
   `git fetch origin && git worktree add -b <actor>/<n>-<slug>
   .claude/worktrees/<actor>-<n>-<slug> origin/main`.
   Subagents dispatched with `isolation: "worktree"` get their own
   worktree automatically; do not point them at yours.
4. **Work only there.** All reads for editing, all commits, and the
   push, PR and merge for the issue happen from your worktree and
   touch only files your issue owns. Commit by path, never `git add .`
   or `commit -a`, so a stray file can't ride along. Fetching is always
   allowed anywhere.
5. **Finish the circle.** After the PR merges: post the handoff comment
   (AGENTS.md format), `git worktree remove <path>` for your own
   worktree, delete the local branch, and confirm with
   `git worktree list` that it is gone. Never remove a worktree you did
   not create; a dirty one is a peer's live work and only the human
   prunes stale ones.

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
  stacked children, see the stacked-PR procedure). Preview with
  `DRY_RUN=1` first when peers are busy.
- **`dirty`, `unpushed`, `locked` are never pruned by the script.**
  Each is resolved by its owner: resume it, land it, or discard it by
  hand. A `locked:pid-dead` entry is a crashed subagent; its owner
  unlocks it (`git worktree unlock <path>`) after checking the diff.

# Context ceiling

Per AGENTS.md, 200K tokens is the working ceiling for any single
context. On this harness that is a hard economic line, not a
preference: on 1M-context Claude deployments, a request whose input
crosses 200K is re-priced at the long-context premium for the ENTIRE
request, and compaction itself is a full cache re-write. Therefore:

- Treat 200K as the compaction trigger: when the session approaches
  it, say so, state the approximate context size, and compact
  (`/compact`) or hand off to a fresh session with a short handoff —
  before crossing, not after.
- Keep subagent contexts under the same ceiling: scope their prompts
  so they never need to hold more than they summarize.

# Cache and spend

The concrete numbers behind AGENTS.md's "Cost of execution" rules, for
the Anthropic/Vertex pricing this harness runs on:

- Cache writes are 1.25× (5-minute TTL) and 2× (1-hour TTL) base
  input; cache reads are 0.1×. For a polling loop, set
  `ENABLE_PROMPT_CACHING_1H=1` in the loop's environment (the 1-hour
  write is worth it the moment one read lands on it) or shorten the
  interval below 5 minutes.
- Measure sessions with `scripts/ops/session_spend.sh
  <transcript-dir>` and read two numbers: hit rate
  `read/(read+write+fresh)` for price, and tokens-per-message for
  volume. Both, always — either one alone hides the other.
