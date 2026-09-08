# Intent: track the wave launcher in the repository

**Issue:** #259 · **Author:** athena (`evekhm-athena-app[bot]`) ·
**Status:** accepted on merge of this PR

## Problem

Every wave since 2026-09-07, and the whole fast path in
`docs/CRITICAL_PATH.md`, was driven by two scripts that live only in
one machine's gitignored operator root, `ops/waves/` (AGENTS.md,
"Outputs go in timestamped run folders"):

- **`ops/waves/launch.sh`** carries an embedded row table
  (`key|issue|wave|persona|stage|slug|model|prompt|after|agy-agent`)
  and, per row: a preflight (prompt file readable; issue `OPEN`; no
  `in-progress`; the `after` issue carries no `in-progress`; branch
  `<persona>/<n>-<slug>` absent locally and on `origin`); the claim
  through `scripts/ops/claim.sh` under the persona's App token
  (`CLAIM_ACTOR=<persona> CLAIM_SESSION=agy-<key> CLAIM_STAGE=<stage>`),
  which posts the claim comment, sets `in-progress` and cuts the
  worktree; and a tmux window running `agy -i "<prompt>" --add-dir
  <worktree> --model <row model> [--agent <row agent>]`, with
  `--dangerously-skip-permissions` by default, stdout copied to
  `runs/<stamp>_agy-waves/agy-<key>.log`. The child's git config
  carries only `scripts/auth/git-credential-persona <persona>`; no
  token reaches the environment, argv or the log. `--status` prints
  the table joined to live tracker state; `--release <key>` runs
  `claim.sh --release` under the row's persona token.
- **`ops/waves/watch-then-launch.sh <head-branch> <release-key>
  <launch-key> [max-hours]`** polls `gh pr list --head` every 120 s
  until that head's pull request is `MERGED`, then runs `launch.sh
  --release <release-key>` and `launch.sh <launch-key>`. It finds the
  prompt column by grepping `launch.sh`'s source.

Four consequences follow from those two files being untracked.

1. **A wave is not reproducible.** A second machine or a fresh clone
   has `scripts/ops/work.sh`, `claim.sh` and the placement adapters,
   and cannot run `launch.sh 98p 68p`, the line `docs/CRITICAL_PATH.md`,
   `docs/PLAYBOOK.md` ("Wave-launcher facts") and the dated handoffs
   all name. AGENTS.md's own `ops/` passage lists `launch.sh` as
   operator state, and the operator's `git clean -x` would delete it
   with no copy anywhere.
2. **It is a second dispatcher.** `scripts/ops/work.sh` resolves the
   stage from the labels, the owner set from `personas/*.yaml`, the
   harness from `config/deployments.yaml`, the model from the persona's
   tier in `config/model_tiers.yaml`, preflights the compiled target,
   and mints the token in the one step before launch (#36 D7, #43).
   The launcher's row asserts all of those as columns. Two of them are
   live disagreements with the committed configuration today:
   `deployments.yaml` pins `athena` and `odyssey` to `claude-code`, and
   every athena and odyssey row launches `agy`; `model_tiers.yaml`
   binds `FRONTIER` to `gemini-3.1-pro-low-thinking`, and rows `98`,
   `68`, `85` and `265` run athena's design and plan rungs on
   `gemini-3.8-flash-high`. The table comment says its models "follow"
   the tiers file; they are a copy of it, and the copy has drifted.
3. **Its checks overlap three scripts and one is nowhere else.**
   `claim.sh` already refuses on closed, `hold`, `in-progress`, an
   open "Depends on" issue, and a branch or worktree collision.
   `work.sh` refuses on `hold`, closed, `status:review-stuck`,
   `blocked`, two `status:*` labels, a foreign claim, a stage the
   actor does not own, and re-entrant dispatch. `launch.sh` re-checks
   `OPEN`, `in-progress` and the branch, and adds one check that
   exists in no tracked script: the cross-issue, rung-level `after`
   gate (row `251` fires only once `#64`'s implement rung has merged,
   long before `#64` closes). Neither `claim.sh` nor the launcher
   verifies that the row's `stage` is the stage the issue's labels
   say is current; a `265d|athena|design` row launches whatever
   `#265` is labelled.
4. **It carries policy the repository decided elsewhere.**
   `--dangerously-skip-permissions` by default with no spend ceiling,
   where `work.sh` has `WORK_PERMISSION_MODE` (#167) and
   `WORK_MAX_USD` under `config/execution.yaml`'s per-persona
   `max_cost_usd` (#25); a `--status` view beside the `#68` board; an
   `agy -i` interactive session where `work.sh`'s header still states
   that an interactive Antigravity session is untested and refuses it,
   after some twenty measured interactive sessions since 2026-09-07.

`#64` D16 makes `lifecycle_advance.sh` dispatch the next rung of the
same issue through the placement adapter the moment it writes the new
`status:*` label. That covers `watch-then-launch.sh`'s same-issue case
once it lands and `loop.autonomous_merge` is on; it covers neither the
first hop (an operator starting an issue from `intent:new`), the
cross-issue `after` case, the claim release the watcher performs
(`docs/PLAYBOOK.md`: "claims outlive sessions"; `lifecycle_advance`
does not release `in-progress` on merge), nor a wave with
`loop.autonomous_merge: false`, which is the shipped default (D18).

## Proposed outcome

An operator on a fresh clone, holding the App keys and a local
`ops/waves/` of prompt files, runs one tracked command against a row
table and gets what the untracked script produces today: the claim
under the persona's identity, the worktree on `<persona>/<n>-<slug>`,
the session in a tmux window, the log under `runs/`, and `DRY_RUN=1`
printing every mutation without writing one. The watcher's job (fire
the next row when a named head merges, release the finished rung's
claim) is tracked the same way, or is stated to be `#64`'s and
retired. No document in the repository names a file that is not in
the repository.

The shape is the design stage's decision (Open question 1); the
properties are fixed here:

- **One claim path.** `scripts/ops/claim.sh` is the claim; the
  launcher composes it and re-implements none of it (`docs/PLAYBOOK.md`,
  "Wave-launcher facts").
- **One resolver.** Harness, model default, compiled target and stage
  ownership come from where `work.sh` already reads them. A row may
  carry an explicit operator override (the model column exists for
  the wave where odyssey was moved to a Pro tier by hand); an override
  is visible as one and the default is never a copied value.
- **A number is the whole instruction stays true** (#36 D7). Whatever
  the launcher passes, `work.sh` gains no flag naming a stage, folder,
  branch or artifact, and a row whose `stage` disagrees with the
  issue's labels is a refusal, printed, before any claim.
- **The table is data.** Row content is dated operator state (which
  issues, which wave, which prompt); the schema, the reader and its
  check are code. Where the live table lives is Open question 3.
- **The checks are stated once.** The spec names, for each of the
  launcher's preflights, whether it is deleted as a duplicate of
  `claim.sh` or `work.sh`, or moves into `work.sh` for every
  placement, or stays launcher-only with the reason (the ask's
  explicit requirement).
- **No path around the ceilings.** A launched session runs under the
  same permission-mode vocabulary and the same per-persona spend
  ceiling as a `work.sh` dispatch, or the spec says why an
  interactive window is exempt and what bounds it instead.
- **The same-change rule.** The pull request that lands the launcher
  repoints `docs/PLAYBOOK.md`, `docs/CRITICAL_PATH.md`, the AGENTS.md
  `ops/` passage and `scripts/README.md`, upserts `docs/SPEC.md`
  `ops.dispatch`, and corrects `work.sh`'s interactive-Antigravity
  claim if the launcher keeps that row. Prose that still names
  `ops/waves/launch.sh` after the merge is a defect of that PR.

Success is a `DRY_RUN=1` launch of the committed table from a second
checkout printing the same mutation list the primary prints, a
stub-based test in `scripts/ops/tests/` for the launcher's refusals
in the style of `work_test.sh` and `claim_test.sh`, and one live
launch of one row recorded in a run folder.

## Affected users and systems

- **The operator** — the only user of both scripts today; the advisor
  and verifier seats, whose handoffs (`ops/handoffs/`) and briefs
  (`docs/CRITICAL_PATH.md`) are written as launch lines.
- **A second machine, a fresh clone, the workshop presenter** — the
  users the ask exists for.
- **`scripts/ops/work.sh`** — its refusal set, `model_of()`, the
  harness launch rows (the `antigravity` interactive question), and
  `WORK_PERMISSION_MODE` / `WORK_MAX_USD`. `#64` D19 forbids `#64`'s
  implementing change from touching this file; sequencing is Open
  question 10.
- **`scripts/ops/claim.sh`** — `CLAIM_STAGE`, `--release`, the
  collision check; possibly a stage-versus-label refusal.
- **`scripts/placement/vm-local/run.sh` and
  `scripts/placement/README.md`** — the contract says the portable
  unit is the one `exec work.sh` line and nothing else dispatches; a
  launcher is either a front-end to that line or a stated exception.
- **`config/model_tiers.yaml`, `config/deployments.yaml`,
  `config/execution.yaml`** — read, never copied; possibly a new data
  file beside them.
- **`scripts/ops/tests/`**, **`scripts/ci/sanitize_check.sh`** — the
  untracked scripts carry `$HOME/.secrets/...` and `~/projects/...`
  literals that the sanitize gate's `home` rule rejects; the tracked
  form resolves the operator PAT and the repo root the way `claim.sh`
  and `work.sh` do.
- **`scripts/ci/lifecycle_advance.sh`** (`#64` D16/D17) — the
  watcher's overlap, and the owner of the claim-release-on-merge gap
  if it moves there.
- **`scripts/ops/board.sh`** (`#68`) — `--status` overlap.
- **`docs/PLAYBOOK.md`, `docs/CRITICAL_PATH.md`, AGENTS.md,
  `scripts/README.md`, `docs/SPEC.md`** — every place that names the
  untracked path.
- **`ops/waves/`** — stays gitignored; the prompt files stay there.

## Constraints

- **Through the ladder.** This PR touches `intent/**` only. The spec
  follows on acceptance; code follows the plan.
- **`claim.sh` is the one claim path** and `work.sh` is the one
  resolver; the launcher composes, and duplicates neither.
- **#36 D7 and the placement contract are not amended here.** No flag
  on `work.sh` names a stage, folder, branch or artifact; no adapter
  gains a second dispatch line. A design that needs either goes back
  to `#36` or `#25` as a comment, never decided in `#259`.
- **Trusted posting and `ops.identity` (#43 D11).** Persona App tokens
  are minted by name in the step before the write and reach the child
  by `export` in a subshell or by the credential helper; the operator
  PAT is read for tracker reads only; nothing prints, files or passes
  a token in argv. The sanitize gate must pass with no new allowlist
  entry.
- **Specs state properties, never pins.** The tracked form defaults
  model and harness from the config files and marks a row's value as
  an override; no persona-to-model or persona-to-harness choice is
  written into the launcher.
- **No path around `config/execution.yaml`'s per-persona ceiling or
  `WORK_PERMISSION_MODE`** without a stated, bounded exception.
- **Verify before documenting** (AGENTS.md). The interactive
  Antigravity row is measured by the waves' run folders; whichever
  script ends up owning that row, its header states what was measured
  and when. Nothing is documented that a fresh `DRY_RUN=1` cannot
  exercise.
- **`ops/` stays gitignored and prompt files stay dated operator
  state.** A prompt that stops being dated graduates into a persona,
  a skill or a doc by its own issue; this issue does not move prose.
- **No document sprawl.** The launcher is documented in its header
  and in the existing `docs/SPEC.md` `ops.dispatch` entry; no new
  guide.
- **Every doc that names `ops/waves/launch.sh` is repointed in the
  same PR that lands the tracked script.**

## Relationships

**Refs #64** (D16 same-issue dispatch, D17 adapter, D18 the default
`autonomous_merge: false`, D19 the `work.sh` exclusion) and **#199**
(the advisor recommendation this issue records). **Builds on #36**
(`work.sh`, D7/D8), **#43** (harness-agnostic launch, `HEADLESS`,
`smoke_launch.sh`, `ops.identity`), **#87** (`claim.sh`), **#25**
(placements, `execution.yaml`), **#167** (`WORK_PERMISSION_MODE`).
**Relates to #68** (`--status` versus the board), **#151** (claims
outlive sessions), **#122** (a skill per ops script; the launcher
would be one), **#265** (the review split changes which persona a
later table row names for review rungs).

## Open questions

1. **Shape.** An extension of `scripts/ops/work.sh` (a `--wave` or
   `--table` mode), a sibling `scripts/ops/launch.sh` plus
   `scripts/ops/watch_then_launch.sh`, or a front-end that runs the
   `vm-local` adapter's one line N times, each in a tmux window? D7
   closes `work.sh`'s argv on purpose, and a table row names a stage,
   a branch and a model.
2. **What runs in the window.** `work.sh <n>` (fixed one-line prompt,
   compiled persona, config-resolved harness and model), or `agy -i`
   with the 7–24 KB operator brief the waves used? If the brief is
   load-bearing, where does it go: an environment-variable mode on
   `work.sh` that carries context and names no stage, the issue's own
   handoff comment (which the resume protocol already says the session
   reads), or a launcher-only path?
3. **Where the table lives and which columns survive.** Tracked
   (`config/waves.yaml` with a schema check in `execution.py`'s
   style) or local under `ops/waves/` with a tracked schema, reader
   and example? `stage`, `slug`, `model`, `agy-agent` and the harness
   are all derivable from labels, the title rule, the tiers file, the
   compiled targets and `deployments.yaml`; `key`, `wave`, `prompt`,
   `after` and an explicit model override are operator input. Which
   derivable columns stay, as overrides?
4. **Which checks move into `work.sh` for every placement.** The ask
   names three: claim held, branch absent, `after`. `claim.sh` owns
   the branch collision; `work.sh` refuses a foreign claim and treats
   no claim as the launched session's to make; nothing tracked owns
   `after`. For each of the launcher's five preflights: delete,
   move, or keep, and why?
5. **`after` semantics.** Today the code checks that the `after`
   issue carries no `in-progress` and then asks the operator to
   confirm a merge in a 5-second window; this issue's body says
   "closed"; the watcher's trigger is "the head's pull request is
   MERGED". Which is the rule, and is rung-level cross-issue
   sequencing a tracker fact (a "Depends on" line that can name a
   rung) or a launcher fact (a table column)?
6. **The watcher after `#64` D16.** Keep `watch-then-launch.sh` for
   the cross-issue case and for `autonomous_merge: false`, retire it
   once D16 lands, or both — and is the same-issue poll a stand-in
   that must refuse when D16 is armed, so an issue is never dispatched
   twice?
7. **Claim release on merge.** The watcher releases the finished
   rung's `in-progress`; `lifecycle_advance.sh` does not; `#64` D19
   closes that script to `#64`'s own change. Where does the release
   land — the watcher, the advancer under a new issue, or a
   `claim.sh` mode — and is there already an issue for the gap?
8. **Interactive Antigravity.** `work.sh` refuses it as unmeasured;
   the waves measured it. Does the launcher keep `agy -i` as its own
   launch row with `work.sh`'s header corrected, or go headless
   through `work.sh` and lose attach-and-watch?
9. **Ceiling and permission mode.** How does an interactive window
   honour `max_cost_usd` (post-hoc for Antigravity per `work.sh`) and
   `WORK_PERMISSION_MODE`, and what replaces `AGY_FLAGS`?
10. **Sequencing against `#64`.** `#64` D19 excludes `work.sh` from
    `#64`'s implementing change and that change is still open. Does
    `#259`'s `work.sh` edit wait for it, or does the first cut confine
    itself to `launch.sh`, `claim.sh` and the data file, with the
    `work.sh` moves as a second PR?
11. **`--status`.** Retire in favour of `scripts/ops/board.sh`
    (`#68`), or keep a table-scoped view that calls the board?
12. **Evidence.** Which of the three named in "Proposed outcome" —
    the second-checkout `DRY_RUN=1` diff, the stub test, the one live
    row — are required to close, and which run folder records the
    live one?
