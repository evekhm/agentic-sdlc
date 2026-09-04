# Intent: the session has an end door

**Issue:** #85 · **Author:** athena (`evekhm-athena-app[bot]`) ·
**Status:** accepted on merge of this PR

## Problem

`scripts/ops/work.sh <n>` is the one door for *starting* a stage: a
number resolves deterministically to a stage, an owner, a folder, a
branch and a set of refusals, and the same number always resolves the
same way. There is no matching door for *finishing*.

A session therefore ends when the operator closes the terminal, and
whatever was open at that moment survives only if someone remembers
it. AGENTS.md already names every obligation — push before the PR,
Done/Decided/Next/Blocked on the issue, drop `in-progress` when
pausing, remove your own worktree after the merge, a disposition
footnote on every run artifact, upsert `docs/SPEC.md`, reconcile
decisions into trackers — but each is checked by memory, at the exact
moment a session has the least context budget left to spend on it.

The cost is on the record from 2026-09-03: one session left eleven
worktrees behind plus a locked one whose owner had exited; another
found the primary checkout on a foreign branch with a stale `main`; a
third had to ask every peer "what in this checkout is yours?". None of
those is a rule that was missing. Every one is a rule nothing
verified.

The gap widens as the loop closes. #64 makes an unattended runner walk
rungs with no human between them; a runner that exits without the same
close-out leaves the same debris, unattended and faster.

## Proposed outcome

The operator types **`/wrap`** in either harness at the end of a
session, and gets one deterministic answer: closed, or not closed and
exactly why.

- **One implementation, `scripts/ops/wrap.sh`** — git and `gh` only,
  no model call, `DRY_RUN=1` prints instead of acting. It is
  harness-agnostic, so CI, cron and #64's runner call the same thing
  the operator does.
- **Exit codes in `work.sh`'s vocabulary**: `0` closed, `1` the
  environment cannot run the checks, `2` refused — something is still
  open. Refusing is the point: a close-out that reports "closed" while
  a branch is unpushed is worse than no close-out, because it is
  believed.
- **One line per check**, each `pass`, `fail`, `warn` or `fixed`,
  naming the object it is about (the branch, the PR, the issue, the
  worktree path) so the line is actionable without a second command.
  The check set is the one filed on #85, in its five groups: nothing
  still in flight; pushed and synced; tracked, not chatted;
  documentation and state obligations; hygiene.
- **It verifies existing obligations and adds none.** Every check
  restates a rule AGENTS.md already binds every session to. `/wrap`
  is an enforcement door, not a new standard — with one possible
  exception, named in the open questions: knowing which work was
  *this* session's may require sessions to leave a marker they do not
  leave today.
- **Judgement stays with the session.** Mapping decisions to trackers,
  reading which constraints a decision superseded, writing the handoff
  prose (filed checks 7, 13, 19) are the calling session's work,
  prompted by the script's output. The script may build the
  "missing tracker" list and the handoff skeleton; it never invents an
  issue, never edits a document, never writes prose.
- **It reuses the tools that exist** rather than re-deriving them:
  `scripts/ops/worktrees.sh` for the worktree report and its
  `safe`/`dirty`/`unpushed`/`locked` verdicts, `session_spend.sh` for
  hit rate and tokens-per-message, `scripts/sync_agents.py --check`
  for compiler drift, `scripts/ops/post.sh` for anything it posts.
- **The handoff block is the last thing printed**: open PRs with head
  SHAs, claimed issues and the rung each sits at, worktrees left
  behind with the reason and the owner, manual steps that remain the
  human's, and deferred-with-no-tracker items by name. A fresh session
  reads that block first and needs nothing else.
- **Two doors, one implementation.** A Claude Code door and an
  Antigravity door, each invoking the script in its harness's headless
  form and showing the exit code without aborting the turn — the
  `/work` door's amended D16 form is the precedent. #43's D16 accepted
  a Claude-only door because "two hand-authored files with no gate is
  drift"; this issue is the revisit that decision named, and an
  ungated hand-authored twin remains unacceptable.

## Affected users and systems

- **The operator** — the only typist, and the direct beneficiary; the
  eleven-worktree session was theirs to clean up by hand.
- **Every session, every persona, both harnesses** — the obligations
  checked are already theirs; what changes is that a session can be
  told it is not finished.
- `scripts/ops/`: a new `wrap.sh`, calling the existing `worktrees.sh`,
  `session_spend.sh` and `post.sh`; `work.sh` is untouched but is the
  shape wrap.sh copies (failure-mode first, refusals before any write,
  modes as environment variables).
- The harness doors: `.claude/commands/` (which today holds `work.md`
  and nothing else) and `.agents/workflows/` (today empty), plus
  whatever emits or gates them — `scripts/sync_agents.py` and the
  drift gate in `.github/workflows/ci-gates.yml`.
- `AGENTS.md` — the session checklist gains "run the end door" at step
  6; the obligations themselves are not restated, and `docs/SPEC.md`
  gains the entry for the new mechanism.
- **#64**, whose unattended runner must satisfy the same checks before
  it exits, and **#12**, whose tracker reconciliation is one of them.
- Depends on **#80** (the worktree report and its verdict vocabulary,
  closed) and **#77** (one session, one worktree, one issue — which is
  what makes "this session's worktree" a meaningful phrase at all).

## Constraints

- Deterministic and cheap. This runs at the end of every session; a
  close-out that takes minutes, or that costs a model call, is a
  close-out the operator will skip. Bounded `gh` calls, no unbounded
  scan of every PR in the repository.
- Same conventions as the start door (#36, #43): `DRY_RUN=1`, modes as
  environment variables rather than flags, refusals evaluated before
  anything is written, and no token ever in argv, in a file, or in a
  printed line (trusted-posting).
- Destructive by exception only. `worktrees.sh` already refuses to
  prune anything but `safe`; `/wrap` inherits that and never touches a
  peer's worktree, branch or label. A peer's dirty worktree is not
  this session's to fix and must not be able to block its close-out.
- The primary checkout stays read-only reference: `/wrap` may be run
  from it, and must write nothing into it.
- No new document (AGENTS.md, "No document sprawl"). The handoff
  format stays AGENTS.md's Done/Decided/Next/Blocked, unchanged and
  uncopied.
- No vendor name, model ID or harness assumption inside anything
  compiled from `personas/` (#1, D3); harness specifics live in the
  door files and in `config/`.
- Nothing about a runtime — an Antigravity workflow door's headless
  form, a harness's ability to run a command from a door file — is
  written down until it has been verified against that runtime
  (AGENTS.md, the never-list).

## Open questions

1. **What is "this session's" work?** Three answers, and they decide
   whether the filed checks 7, 8, 10 and 16–19 can be asserted at all
   or only advised: a marker each session persists as it works (the
   session id the cost ledger #104 already carries is a candidate); an
   after-the-fact derivation from worktree lock metadata (#77/#80),
   branch prefix, App identity and claim comments; or no scoping —
   `/wrap` reports the whole checkout and names an owner per finding.
2. **Which checks block, and which only report?** The taxonomy needs a
   rule, not a per-check opinion: an open PR waiting on a human merge,
   an `in-progress` label on a deliberately paused issue, and a peer's
   unpushed branch are all "open" and none of them is the closing
   session's fault.
3. **May `/wrap` write, and as whom?** Removing the session's own
   `in-progress` label, deleting merged remote branches, pruning its
   own `safe` worktrees and posting the handoff comment are each
   defensible as "fixed" and each defensible as "report only" — and if
   it writes to GitHub, it does so as some identity, which the answer
   must name.
4. **Emitted or gated?** The two doors are either generated from one
   source by `scripts/sync_agents.py` — in which case the existing
   drift gate (#6) already covers them — or hand-authored twice under
   a new drift check written for them. This is the D16 revisit and it
   needs deciding, not deferring again.
5. **Is filed check 11 deterministic?** "`docs/SPEC.md` sections
   touched by this session's merges still describe `main`" may have no
   machine form, since CI's spec-check only ever sees one PR. Either
   there is a deterministic reduction of it, or it degrades to listing
   the sections a human must re-read — and a check that cannot fail
   should say so rather than print `pass`.
6. **One session or many?** Several sessions run against this
   checkout at once. If each runs `/wrap` at its own end, every one of
   them sees the others' live work. Whether `/wrap` is a per-session
   act (and therefore must be peer-blind by construction) or a
   per-day operator act (and therefore may demand a quiet machine)
   changes what half these checks even mean.
