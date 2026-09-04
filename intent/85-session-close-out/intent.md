# Intent: session close-out

**Issue:** #85 · **Stage:** plan · **Author:** athena
(`evekhm-athena-app[bot]`)

## Problem

A session has a start door and no end door. `scripts/ops/work.sh <n>`
(#36, #43) resolves a number to a stage, refuses six ways, claims,
mints and launches — one command, deterministic, in front of the
operator. Nothing corresponds to it at the other end. A session ends
when the operator closes the terminal, and whatever was open at that
moment is not finished, it is *abandoned*: a branch never pushed, a
decision that stayed in chat, an `in-progress` label with no handoff
under it, a run artifact with no disposition, a `docs/SPEC.md` section
a later merge quietly superseded, a subagent still burning tokens.

The residue is measurable. `git worktree list` on the primary checkout
at the time of writing returns **37 worktrees** beside the primary
one: 29 `agent-<hash>` subagent trees, 13 on a detached HEAD, and
several on branches whose issues merged days ago
(`odyssey/25-execution-model`, `athena/44-repin-personas-to`,
`odyssey/50-work-sh`). Not one of them is live work. On 2026-09-03 one
session left 11 worktrees and a locked one whose owner had exited;
another found the primary checkout on a foreign branch with a stale
`main`; a third had to ask every peer session "what in this checkout
is yours?".

Each individual omission has a rule against it already — AGENTS.md's
session checklist, the run-folder disposition footnote, the living-spec
upsert, #80's worktree cadence, #77's one-session-one-worktree. The
rules are not the gap. The gap is that **nothing checks them at the
one moment they can still be honoured cheaply**, and so compliance is
a matter of whether the operator remembered. A standard whose only
enforcement is memory is a standard that degrades every time a session
runs long or ends in a hurry — which is every session that mattered.

The failure this issue must prevent is not an error. It is a session
that *looks* finished.

## Proposed outcome

One command, `/wrap`, typed by the operator in either harness, that
runs the same deterministic close-out and **refuses to say "closed"
while anything is still open**.

1. **One implementation, `scripts/ops/wrap.sh`.** `git` and `gh` only,
   no model call, `DRY_RUN=1` prints instead of acting, and
   `work.sh`'s exit vocabulary: 0 closed, 1 the environment cannot run
   the checks, 2 refused — something is still open. Harness-agnostic,
   so CI and the #64 runner call the same script the operator does.
2. **"Closed" is a statement that can be false.** Every check reports a
   result the operator can read; a close-out that always prints
   "closed" is the same as no close-out. The checks group into the five
   families the intake names — nothing still in flight, pushed and
   synced, tracked not chatted, documentation and state obligations,
   hygiene — and the command ends with a handoff block a fresh session
   reads first: open PRs with head SHAs, claimed issues and their next
   rung, worktrees left behind and why, manual steps that remain the
   human's, deferred-with-no-tracker items by name.
3. **Two thin doors, one gated source.** A Claude Code door and an
   Antigravity door, each invoking the script in its harness's headless
   form and displaying the exit code without aborting the turn (#43's
   amended D16 is the precedent for the shape). The two doors are
   either emitted from one source or covered by a drift gate that fails
   when they diverge; D16 chose "no twin, because two hand-authored
   files with no gate is drift" and named this issue as its revisit —
   the answer here is the gate, not a second hand-authored file.
4. **Judgment stays with the session; determinism stays with the
   script.** Mapping decisions to trackers, reading which constraints a
   decision superseded, writing the handoff prose (checks 7, 13, 19)
   are the calling session's work, prompted by the script's output. The
   script produces the *lists* — the missing-tracker list, the handoff
   skeleton — and never invents an issue, never edits a doc, never
   writes prose.
5. **"This session" is derived, not asserted.** The script knows which
   worktrees, branches, pull requests and claimed issues are this
   session's from something machine-readable, so that a close-out
   cannot be passed by a session that simply forgot to mention its own
   open work.

The measure of success is negative and it is checkable: after `/wrap`
exits 0, a peer running #80's worktree report, the tracker's label
view, and `git log origin/main` finds nothing belonging to that
session that a human has to chase.

## Affected users and systems

- **The operator**, who gains a symmetric pair — `work.sh` opens,
  `wrap.sh` closes — and loses the end-of-day reconstruction of what
  the last four sessions left behind.
- **`scripts/ops/`** — a new `wrap.sh` that *composes* what already
  exists rather than reimplementing it: `worktrees.sh` (#80) is check
  15, `session_spend.sh` is check 16, `lib/github.sh` resolves a pull
  request to its issue, and `work.sh` owns the exit vocabulary and the
  `DRY_RUN` convention both scripts share.
- **The harness doors** — `.claude/commands/` (where `/work` already
  lives) and whatever Antigravity's equivalent proves to be — plus
  `scripts/sync_agents.py` if the doors are emitted or drift-gated
  there.
- **AGENTS.md** — the session checklist gains its terminal step, and
  the never-list gains "never end a session without it". The checklist
  itself lives in the script and in AGENTS.md, not in a new document.
- **The tracker** — #12's ticks and the `status:*` labels are read by
  check 9, and `docs/SPEC.md` by check 11.
- **#64** (the autonomous loop): the same checks are what an unattended
  runner must satisfy before it exits, which is why the logic cannot
  live in a harness door.
- **Peer sessions**, who are *read* by the close-out and never written
  by it: a peer's dirty worktree is named with its owner, not fixed.

## Constraints

- **Deterministic, and one implementation.** `git` + `gh` only, no
  model call, no LLM in the checking path; `DRY_RUN=1` prints and acts
  on nothing; exit codes in `work.sh`'s vocabulary (#36, #43 D23). The
  harness doors are thin — every line of logic they could hold is a
  line that has to be duplicated for the other harness.
- **The script never writes prose and never files a tracker item.** It
  may list what is missing; it may not decide what the missing thing
  says. Determinism ends exactly where judgment begins, and this is the
  boundary.
- **It is not a second writer of the ladder.** `.github/workflows/
  lifecycle.yml` is the single writer of `status:*`; a close-out that
  "corrects" a rung label is two state machines disagreeing (AGENTS.md,
  "The labels are the state machine"). `hold` is absolute here as
  everywhere: it is checked before anything, and it stops the write.
- **It never touches what is not its own.** Only `safe` worktrees this
  session created are pruned; `dirty`, `unpushed` and `locked` are
  reported with owner and reason and left alone (#80, AGENTS.md). The
  primary checkout is read-only reference — a close-out that "tidies"
  it is the failure mode it exists to prevent.
- **Every GitHub write goes through the vetted path.** `post.sh` with a
  body file, credentials by name, no token in argv, a log line, or a
  committed file (#25 D5/D6/D13, the trusted-posting skill).
- **No unverified runtime mechanism is written down.** Antigravity's
  headless form for a door is a *measurement* with a run folder behind
  it, not a guess: agy 1.1.24/1.1.25 needed `agent.md` + `--add-dir`
  and exits 0 even on refusal
  (`runs/2026-09-03_agy-headless/findings.md`). AGENTS.md forbids
  documenting a flag or mode that has not been run against that
  runtime.
- **No document sprawl.** The nineteen checks are the script and
  AGENTS.md's checklist; they do not become a twentieth markdown file
  restating them.
- **The close-out is not a gate on merge.** A human still merges; a
  session that refuses to close is a session with open work, not a
  blocked pull request.

## Open questions

1. **Which checks are hard `fail` and which are `warn`** — in
   particular the failures the session *cannot* fix: a peer's dirty
   worktree, red CI on a pull request it does not own, a 403 from a
   token scope (#47). Blocking on those makes `/wrap` unclosable;
   warning on them makes "closed" cheap. The answer decides whether
   exit 2 means "you have work left" or "somebody does".
2. **How the script derives "this session's" worktrees, branches, pull
   requests and claimed issues** — worktree lock metadata (#77/#80),
   branch author, the App identities, or a session marker written into
   the claim comment. If the answer is a marker, `work.sh` must write
   it, and this issue acquires a change to the *start* door; that
   coupling should be decided deliberately rather than discovered
   during implementation.
3. **Report-only, or is `fixed` a real result state** — and if it is,
   exactly which mutations are in the set (removing the session's own
   stale `in-progress`, pruning its own `safe` worktrees, deleting
   merged head branches, removing its `/tmp` body files). Every member
   of that set is a mutation the unattended #64 runner will also
   perform without an operator watching.
4. **Whether the Antigravity door ships in v1, and in what form** —
   answerable only by running it. If the measurement is not made, the
   alternative is one door plus a gate that fails the build when an
   ungated second one appears.
5. **What ships in v1 of the nineteen checks** — the named subset with
   the rest deferred by number, or an ordering principle that says
   which come first. "All nineteen at once" is the answer that produces
   a script nobody lands.
6. **What counts as one "session"** — a compaction, a resumed
   transcript, and one iteration of the #64 runner are three different
   boundaries, and check 1 (nothing still in flight) and check 16
   (spend measured) read differently under each.

These six are the design gate's work. Per the spec-adversary protocol,
`spec.md` in this folder resolves each as a numbered Decision, and this
issue's status does not move to Approved while any of them is open.
