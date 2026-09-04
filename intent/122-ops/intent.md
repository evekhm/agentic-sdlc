# Intent: operational scripts as dual-harness skills

**Issue:** #122 · **Author:** athena (`evekhm-athena-app[bot]`) ·
**Status:** accepted on merge of this PR

## Problem

The deterministic half of this repository's operations already exists
and already documents itself. `scripts/ops/work.sh`, `post.sh`,
`worktrees.sh`, `session_spend.sh`, `smoke_launch.sh` and
`execution.py` each carry a header that is the source of truth for
their flags, their environment variables and — for the three that
matter most — an explicit exit-code contract in which `2` means *the
thing was deliberately not done*, not *the thing broke*.

Nothing routes an agent to them at the moment of need.

The only skill mechanism the compiler has is **inlining**:
`personas/skills/*.md` is pasted verbatim into every compiled prompt
(`scripts/sync_agents.py:422`), in declared order, and
`compiler_roundtrip.sh` asserts the full text is present. Two costs
follow. First, every persona pays for every skill on every call,
whether or not the moment arrives. Second, the prose is a second copy
of a contract that already lives in a script header, and the copies
have already drifted apart:

- `personas/skills/resume-protocol.md` names `work.sh` for steps 1,
  2, 3 and 5, then re-states those steps and all six refusals in
  prose that must be kept in step with `work.sh` and
  `scripts/ops/lib/github.sh` by hand.
- `personas/skills/trusted-posting.md` states `post.sh`'s contract —
  vetted step, body never in argv, `hold` absolute — without ever
  naming `post.sh`. That gap is filed separately as #98.
- `AGENTS.md:207-213` restates `worktrees.sh`'s entire flag surface
  and verdict vocabulary next to the cadence policy that genuinely
  belongs there.
- `scripts/README.md:42-52` is an invocation table that is already
  stale: it lists three ops scripts and omits `post.sh`,
  `smoke_launch.sh`, `execution.py` and `lib/github.sh`.

When the copy drifts, the agent improvises — ad-hoc `git` and `gh`
instead of the vetted path, which is the failure #86 and #98 record.
And neither harness has a compiled bridge from *the moment* to *run
exactly this script, with these arguments, and read its exit 2 as a
refusal to report rather than an error to retry*. The single
exception, `.claude/commands/work.md`, is hand-authored and
deliberately sits outside the compiler's target directories
(docs/SPEC.md:582), so it is outside the drift gate too.

## Proposed outcome

One canonical **skill per operational script**, written once, compiled
to both harnesses, and covered by the same ownership marker, prune
rule and CI drift gate as the compiled personas. Each skill states
four things and no more: the **activation trigger** (the moment the
agent must reach for it), the **exact command** with its arguments and
modes, the **exit-code contract** (`0` done or deliberately not done,
`2` a refusal by design — report the reason, never retry, `1`
unusable input or fatal), and the **capability** through which the
command runs, resolved per harness from `config/tools.yaml`
(`run_commands` → `Bash` / `run_command`) rather than named in the
source.

That implies three pieces of work:

1. **Canonical skill sources with machine-readable metadata** (`name`,
   `description` at minimum), so a harness that supports on-demand
   loading can index them and load one at the moment it applies
   instead of carrying all of them always.
2. **Compilation in `scripts/sync_agents.py`** to the harness-native
   locations, added to `TARGET_DIRS` so `--check` sees them and stale
   files are pruned, with `--verify` assertions of their own. A
   compiled artifact that the gate cannot see is a compiled artifact
   that will drift.
3. **Prose defers to the skill.** Every passage the packaging
   supersedes is cut or reduced to a pointer in the same change:
   `resume-protocol.md`, `trusted-posting.md` (which is where #98's
   ask lands), the `AGENTS.md` worktree passage — keeping the cadence
   policy, dropping the flag table — and `scripts/README.md`. The
   living spec is upserted once, not turned into a fourth copy.

The scripts themselves are **not redesigned here**. This issue
packages contracts that already exist; it does not author them. Where
a script does not exist yet — `claim.sh` (#87) and `wrap.sh` (#85) are
both named in this issue's body but are absent from the tree and from
`intent/**` — its skill is written against whatever contract that
issue's own spec settles, or is left out of the first cut entirely.

Success is observable, not asserted: a measured change in what a
session carries and in whether it reaches the script instead of raw
`git`/`gh`, plus a green drift gate proving both harnesses carry the
same content.

## Affected users and systems

- **The operator and every persona session** — the direct
  beneficiaries; a session that finds the script stops improvising.
- **`personas/skills/`** (4 protocol skills today) and the `skills:`
  array in the 6 full persona sources; the 5 sub-agent sources
  (`coder`, `contract-writer`, `explorer`, `mechanic`, `scanner`)
  declare no skills at all today.
- **`scripts/sync_agents.py`** — `TARGET_DIRS`, the marker and prune
  rules, `render_body()`'s inlining, and `--verify`.
- **The drift gate** — `scripts/ci/compiler_roundtrip.sh` and
  `.github/workflows/ci-gates.yml`; its step 5 currently asserts a
  skill's *inlined* text, which any move to on-demand loading
  invalidates.
- **`config/tools.yaml`** — the capability the skills bind through.
- **`.claude/commands/work.md`** — hand-authored today; if the
  compiler takes over the commands directory, docs/SPEC.md:582 must
  be rewritten.
- **`AGENTS.md`, `scripts/README.md`, `docs/SPEC.md`** — the prose
  copies being reduced.
- **The ops scripts** — behaviour unchanged; their headers become the
  cited source rather than a thing to paraphrase.

## Constraints

- **Verify before documenting.** AGENTS.md forbids documenting a
  runtime mechanism not verified against that runtime. No skill file
  may claim a loading behaviour that has not been probed on the
  harness it targets, the way #43 probed frontmatter (P1/P1a/P2). If
  Antigravity has no on-demand skill loader today, the spec states the
  fallback rather than assuming parity.
- **Compiled targets are generated, never hand-edited** (#5, D7). Any
  new artifact kind enters `TARGET_DIRS` and the gate in the same
  change, or it escapes both.
- **No vendor names or model IDs in canonical sources** (#1, D3);
  harness-specific tool names resolve through `config/tools.yaml`.
- **No document sprawl.** A skill must name the passage it
  supersedes; adding one without removing its prose twin makes the
  problem worse, not better.
- **Token cost is a claim to be measured**, per AGENTS.md's cost
  discipline — moving text from one file to another is not the
  outcome.
- **`wrap.sh` stays #85's design** (operator, 2026-09-04): a packaging
  need that would force a shape onto it goes back to #85 as a
  comment, never decided here.
- **Trusted-posting remains binding**: a skill routes to a vetted
  script; it never teaches an inline API call.

## Relationships

**Depends on #85** (wrap.sh's interface, exit codes and check
taxonomy). **Builds on #87** (claim.sh) and on #97/#98 (post.sh as
the one write path). **Extends #5** (the compiler and its targets).
**Relates to** #36 and #43 (work.sh and the `/work` door), #89 (one
session drives the ladder), #31 (Rung 5 plugin packaging), #123 (a
live `worktrees.sh` defect — the skill documents the contract, it does
not fix the bug).

## Open questions

1. **Where do canonical skills live** — flat `personas/skills/<name>.md`
   as today, or `skills/<name>/SKILL.md`? And do operational skills
   share a namespace with the protocol skills (`spec-adversary`,
   `review-protocol`), or is "operational" a distinct kind with
   distinct compilation?
2. **Inlined, on-demand, or both?** Progressive disclosure saves
   tokens but risks a skill that never loads at the moment it was
   written for; inlining guarantees presence and pays always. Is the
   choice global or per skill — and if a skill is both inlined and
   emitted as a file, what stops it being paid for twice?
3. **Does Antigravity support on-demand skills at all** in the agy
   version this repo pins? If not, does #122 ship harness-asymmetric
   output (files on Claude Code, inlining on Antigravity), and does
   the drift gate then assert equivalence of *content* rather than of
   files?
4. **Does the compiler take over `.claude/commands/`**, making the
   `/work` door generated and gated, and what is the Antigravity
   equivalent of a slash command?
5. **Scope of the first cut** — only the scripts that exist
   (`work.sh`, `post.sh`, `worktrees.sh`, and possibly
   `session_spend.sh`), with `claim.sh` and `wrap.sh` skills landing
   inside #87 and #85 as those scripts land? Or does #122 wait?
6. **Do the five sub-agent sources gain skills**, and which? They
   inherit nothing today.
7. **`config/tools.yaml`**: a dedicated capability for operational
   scripts, or continue through `run_commands`?
8. **Does #122 absorb #98**, or does #98 land first as the one-line
   fix it is, with #122 building on it?
9. **What evidence closes this** — a measured prompt-token delta, a
   `smoke_launch.sh`-style run showing the skill's command executed,
   or the drift gate alone?
