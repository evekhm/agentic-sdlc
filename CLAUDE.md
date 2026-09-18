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

A tier resolves to a model through `config/model_tiers.yaml` under
`harnesses.claude-code.<TIER>`, keyed by the tier name with its `_TIER`
suffix dropped (`FAST_TIER` reads `harnesses.claude-code.FAST`). That
table is the one place in the repository where a model ID is written by
hand. A compiled persona in `.claude/agents/`
already carries its resolved model in frontmatter, emitted by
`scripts/sync_agents.py` and drift-gated by `ci-gates.yml`, so
dispatching one needs no model override. Pass `model=` on an Agent call
only for a generic agent with no compiled definition, and pass the ID
from that table verbatim.

- `FAST_TIER`: deterministic sweeps, trivial lookups, routing.
- `MECHANICAL_TIER`: batch edits from a spec, greps, test runs,
  formatting, named fixes. Dispatch the compiled `mechanic` agent
  (`.claude/agents/mechanic.md`).
- `IMPLEMENTATION_TIER`: a dispatch-ready spec with no open design
  decisions. Dispatch the compiled `coder` agent
  (`.claude/agents/coder.md`).
- `REVIEW_TIER`: evidence-based review and analysis.
- `FRONTIER_TIER`: design, adversarial grilling, tricky debugging.
  This is the spec gate's tier alone. `REVIEW_TIER` stays a rung below
  it because review runs every PR round and the frontier model bills at
  2x the review model's rate (#105). An interactive session already
  running the frontier model inherits it by omitting the override.

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
  from AGENTS.md.
- **The unit of isolation is the claim** (AGENTS.md, "Working the
  tracker"). A subagent dispatched to work the issue this session
  already claimed runs in this worktree, on this branch: give it the
  absolute path and dispatch it WITHOUT `isolation: "worktree"`.
  Reserve `isolation: "worktree"` for work that belongs off the claim's
  branch — a different issue, or a throwaway experiment whose only
  output is a summary. The harness names its own worktrees
  `.claude/worktrees/agent-<hex>`, a path `claim.sh` never created and
  cannot see, so nothing refuses a second worktree for a claimed issue
  and `scripts/ops/worktrees.sh` is what surfaces one. A dispatched
  subagent's worktree shows as `locked:pid-live` in the report while it
  runs and `locked:pid-dead` if it crashed; the dispatching session
  unlocks and cleans up its own.
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
  (`wrap soon` at 60%, `WRAP NOW` at 70%, `COMPACTING` at 90%), list-rate spend,
  token accumulation in/out/tot, cache health (with Claude cache-write tokens `cw <n>`),
  and the session's location (#529) — `⑂ <branch>` in a claimed worktree,
  `📂 <folder> ⎇ <branch>` in a normal checkout — so parallel sessions are
  told apart at a glance.
  Writes atomic side-channel metrics to `$AGENTIC_CTX_DIR/<session_id>.json`
  (defaulting to `$CLAUDE_CTX_DIR` or `~/.claude/context/<session_id>.json`, with fallback to `/tmp/agentic-context/`).
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

# Slash commands

Claude Code slash commands in `.claude/commands/` (`/work`, `/idea`, `/bug`) are compiled targets generated from canonical sources in `commands/` via `scripts/sync_commands.py`. Do not edit `.claude/commands/` directly (except allowlisted standalone commands like `wrap.md`); modify the source in `commands/` and run `python3 scripts/sync_commands.py`.
