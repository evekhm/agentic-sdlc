# Intent: repin odyssey and cassandra to antigravity

**Issue:** #44 · **Stage:** plan · **Author:** athena
(`evekhm-athena-app[bot]`)

## Problem

Four of the six personas — `athena`, `odyssey`, `argus`, `cassandra` —
are pinned to `claude-code` in `config/deployments.yaml`; only
`daedalus` and `atlas` are on `antigravity`. The presenter's direction
(2026-09-02, recorded on #44) is the opposite balance: run as much of
the loop as possible on antigravity for price, and keep on the other
harness only the personas whose duty makes it necessary.

Two of those four are on `claude-code` for no reason anyone recorded —
they were pinned there in #2 because that was the harness that worked:

- **`odyssey`** is the highest-volume persona in the system. It runs at
  `IMPLEMENTATION` tier with `limits: {max_turns: 120, timeout_mins:
  90}` — the largest cap of any persona — and its stage is the one that
  reads plans, writes code, and runs test suites. Every token the
  implement stage spends is spent on `claude-sonnet-5` today.
- **`cassandra`** runs at `FAST` tier on a cadence: watcher sweeps that
  compare metrics to control bands and, at 1 sigma, only log. That is
  the cheapest possible work on the most expensive available billing
  relationship — a sweep that finds nothing still pays Anthropic list
  rates for the context it re-reads.

Until #43 the pin decided nothing at launch time, so moving them would
have been moving them into a harness `scripts/ops/work.sh` could not
start. #43 (PR #60) closes that: both harnesses now launch, the
antigravity target is `.agents/agents/<name>/agent.md`, and the model
reaches `agy` as `--model` from the compiled sidecar. The repin is
therefore now a real change of where work runs rather than a
config-file edit with no observable.

Left alone, the balance also degrades on its own. `docs/SPEC.md` says
the two reviewers are pinned to different model families and that
"which family backs which reviewer is a `config/` fact"; today
`argus` is the *only* thing keeping that true, and nothing in the
repository says so out loud. A later session repinning "everything
else" for price would break the review policy with a one-line edit
and no error.

## Proposed outcome

`config/deployments.yaml` reads:

```yaml
  odyssey:   { harness: antigravity }
  cassandra: { harness: antigravity }
```

and a compiler rebuild follows the pins: `.claude/agents/odyssey.md`
and `.claude/agents/cassandra.md` disappear, `.agents/agents/odyssey/`
and `.agents/agents/cassandra/` appear with the `{agent.md,
agent.json}` layout #43 landed. `scripts/sync_agents.py --check` is the
gate that the checked-in targets match the pins; a rebuild that leaves
either stale file behind fails it.

Four of six personas then run on antigravity. Two stay, each for a
stated reason rather than by inertia:

- **`athena` stays.** Plan and design are the two gates where words
  become commitments, and the spec-adversary protocol is the highest-
  judgment work in the loop. Moving it later is the same one-line edit
  this issue makes; making it now would change the harness of the
  persona writing this sentence in the same PR that changes it.
- **`argus` stays, and this is a constraint, not a preference.** #2 D4
  makes the two reviewers a machine-checkable pair —
  `constraints.distinct_model_families: [argus, atlas]` — and `atlas`
  is on antigravity. Exactly one reviewer must therefore remain off the
  Gemini family, and after this issue `argus` is the only persona on
  `claude-code` that could be it.

Alongside the pins, three things the repin makes true and that must
move with it:

1. **The smoke test's two arms.** `scripts/ops/smoke_launch.sh` runs
   `odyssey` for the claude-code arm and `daedalus` for the antigravity
   arm. After the repin, "run 1 · claude-code · odyssey" launches
   `agy`, the run still exits 0, and #43's gate silently stops covering
   the Claude harness at all. The arms must follow the pins.
2. **A before/after cost measurement.** `scripts/ops/session_spend.sh`
   is the repository's spend tool and the reason the presenter asked
   for this move is price, so the move owes a number rather than a
   belief. What that tool can and cannot measure across two vendors is
   itself a decision (see Constraints).
3. **The standing guard.** After this move the D4 pair has no slack:
   the file must say, where the next session will read it, that
   repinning `argus` is a violation and not a cost optimisation.

## Affected users and systems

- `config/deployments.yaml` — two lines. The only source edit.
- `.claude/agents/{odyssey,cassandra}.md` — deleted by the rebuild.
- `.agents/agents/{odyssey,cassandra}/{agent.md,agent.json}` — created
  by the rebuild. `agent.md` carries `name`, `description`, `tools` and
  never `model` (#43 D8); the resolved model rides in `agent.json`
  (#43 D9).
- `scripts/ops/work.sh` — not edited. It reads the pin, so its
  behaviour changes without its text changing: an implement stage now
  starts `agy` and reads `.agents/agents/odyssey/agent.json`.
- `scripts/ops/smoke_launch.sh` — its two arms are persona names, and
  the repin invalidates both.
- `docs/SPEC.md` — the `ops.dispatch` entry states that the antigravity
  smoke run's claim half is `BLOCKED ON #47`; that becomes false if the
  antigravity arm moves to a persona whose App already has
  `issues: write`.
- **The presenter**, whose bill this is, and the room watching the
  demo: four of six personas running on Gemini is also the visible
  claim that the personas are harness-agnostic.
- **Not affected:** `personas/**` (no persona source changes, so no new
  sanitize surface), `config/model_tiers.yaml` (unchanged; only which
  column each persona resolves through changes), `config/tools.yaml`,
  `personas/lifecycle.json`, and `config/execution.yaml` — #25 D19's
  bindings name *placements*, not harnesses, and every v1 antigravity
  binding is already `placement: vm-local`.

## Constraints

- **Config-only at the source layer.** Which harness backs a persona is
  one edit to `config/deployments.yaml` and nothing else (#2 D1/D2).
  Vendor and model names never enter `personas/**`; the sanitize gate
  enforces it, and this issue gives it no new surface.
- **The compiled targets are derived, never hand-edited.**
  `scripts/sync_agents.py --check` is the gate (#5, #43 D10). A repin
  whose rebuild is not committed is drift, and a hand-made
  `agent.md` is the same failure.
- **#2 D4 is non-negotiable.** The two reviewers resolve to different
  model families at `REVIEW` tier. It is data in
  `config/deployments.yaml`, and until #6 automates it the check is
  performed and recorded by hand.
- **Depends on #43 (PR #60).** A persona pinned to a harness
  `work.sh` cannot start is unlaunchable from the one door AGENTS.md
  allows. This issue branches from that PR and merges after it.
- **Does not depend on #47.** #47 raises `daedalus`, `argus` and
  `atlas` from `issues: read` to `issues: write`. Both personas moving
  here already have `issues: write` in
  `scripts/auth/app_manifests.yaml` (`odyssey`: contents, pull
  requests, issues, all write; `cassandra`: `issues: write`), so
  neither the claim nor the handoff half of a moved persona's run is
  blocked.
- **The cost tool is single-vendor.** `scripts/ops/session_spend.sh`
  reads Claude Code `*.jsonl` transcripts and prices them against the
  Anthropic rate table; a model the table does not know is reported
  `UNPRICED` by name. `agy` reports its own `usage` object in
  `--output-format json` (findings Q5). There is no one number that
  spans both, and the measurement must say so rather than produce a
  cross-vendor dollar figure the tool cannot support.
- **`cassandra` owns stage `maintain`, which has no rung.**
  `personas/lifecycle.json` states it: `intake`, `deploy` and
  `maintain` "are stage-enum values with no rung and are absent by
  construction". No `status:*` label resolves to `maintain`, and
  `work.sh` validates `--as` against the current stage's owners — so
  `cassandra` cannot be launched by `work.sh <n>` before or after this
  change, and the repin neither causes nor fixes that.

## Open questions

One, filed on the issue, and it is settled in `spec.md` in this same
folder rather than left for the builder:

- **Does CLAUDE.md's `IMPLEMENTATION_TIER` note — "sonnet-5 via a
  dedicated agent definition … a repo-local compiled `coder` will bind
  this tier" — change when `odyssey` moves?** Two readings are
  available: the note describes the tier for *the persona that runs at
  it*, in which case moving `odyssey` makes it stale prose; or it
  describes the tier *for sessions running on the Claude Code harness*,
  in which case the persona pin is orthogonal to it. `spec.md` decides
  it with the differing case.

Both artifacts land in one pull request under the bootstrap-compression
precedent (`intent/1-personas/spec.md` D10, reused by
`intent/2-config/spec.md`): recorded once, not a precedent.
