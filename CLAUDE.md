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
  `model="claude-fable-5-1"` on the Agent call, the exact ID, same
  convention as MECHANICAL. This is the spec gate's tier only:
  `REVIEW_TIER` stays on opus because review runs every PR round and
  Fable is 2x the Opus rate (#105). An interactive session that
  already runs on Fable inherits it by omitting the override.

# Parallel sessions

Several Claude Code sessions run against this repo on one machine at
the same time, alongside Gemini sessions. The rule and the process —
one session, one worktree, one issue; primary checkout read-only;
work, PR and cleanup from your own worktree; the
`scripts/ops/worktrees.sh` cadence — are in AGENTS.md ("Working the
tracker"). This harness adds the tooling:

- **Peer check:** ListAgents (busy peers are named `agentic-sdlc-*`),
  on top of `git worktree list` and the issue's claim comment. If a
  peer already holds the issue, SendMessage that session and stand
  down; report to the user instead of duplicating.
- **Claim and worktree:** run `CLAIM_ACTOR=<persona> CLAIM_SESSION=<name>
  scripts/ops/claim.sh <issue> [<slug>]`. This verifies the issue, claims it
  (include your session name from ListAgents so peers can find and message
  you), and creates your worktree. **By-hand fallback:** launch the session
  with `claude -w <name>`, call EnterWorktree, or run the by-hand command
  from AGENTS.md. Subagents
  dispatched with `isolation: "worktree"` get their own worktree
  automatically; do not point them at yours. A subagent's worktree
  shows as `locked:pid-live` in the report while it runs and
  `locked:pid-dead` if it crashed; the dispatching session unlocks and
  cleans up its own.
- **Run artifacts:** `claude -w` and EnterWorktree make the worktree
  the cwd, so a relative `runs/...` path lands inside the worktree and
  dies with it. Resolve the shared root per AGENTS.md ("Outputs go in
  timestamped run folders") before writing, and tell subagents the
  absolute path — a subagent in its own worktree has the same trap.

# Context ceiling & harness instrumentation

Per AGENTS.md, 200K tokens is the working ceiling for any single
context. On this harness that is a hard economic line, not a
preference: on 1M-context Claude deployments, a request whose input
crosses 200K is re-priced at the long-context premium for the ENTIRE
request, and compaction itself is a full cache re-write.

Harness instrumentation (`scripts/ops/harness/`, #330):
- **statusLine command:** configured in `~/.claude/settings.json` via
  `scripts/ops/harness/install.sh`, running `scripts/ops/harness/statusline.sh`.
  Tracks context usage against 200K ceiling, displaying graduated tags
  (`wrap soon` at 60%, `WRAP NOW` at 70%, `COMPACTING` at 90%), list spend,
  token accumulation in/out/tot, and cache health (`cw <n>`). Writes atomic
  side-channel metrics to `~/.claude/context/<session_id>.json`.
- **SessionStart hook:** configured in `<repo>/.claude/settings.json` via
  `${CLAUDE_PROJECT_DIR}/scripts/ops/harness/session-start.sh` with
  `autoCompactWindow: 180000`. Primes seated sessions (`CLAUDE_SEAT` or `AGENTIC_SEAT`)
  with the newest handoff (gated at 60KB max) and outputs an operator pointer
  for unseated sessions.

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
