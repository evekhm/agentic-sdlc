# Intent: a live view of who owns which issue, at which rung

**Issue:** #68 · **Author:** athena (`evekhm-athena-app[bot]`) ·
**Status:** accepted on merge of this PR

## Problem

The operator, at the keyboard, on the record: *"I need a live view of
which agents are working on which tasks, which stage etc. Otherwise I
cannot follow or understand what is going on now and who owns what by
looking at the repo."*

AGENTS.md removed the status file deliberately and named its
replacement (AGENTS.md:154-160): *"Where do I pick up?" is always
answered by: tracker issue, first unchecked line whose issue is
claimable, its last handoff comment.* That procedure answers **what do
I pick up next**, for one reader taking one item. It does not answer
**what is happening right now**, across items — the question a
presenter has during a live run and an operator has while several
sessions run at once. Removing STATUS.md was right; the gap it left
has never been filled.

Nothing is missing. Every fact is already in GitHub or on this disk.
What is missing is the **join**: five sources, each correct on its
own, correlated nowhere. Measured on this repository on 2026-09-03,
while the operator was trying to follow it:

- 23 open issues. Three carry `in-progress` (#43, #44, #68), four
  carry a `status:*` (#25, #43, #44, #57), eight carry `intent:new`.
  Answering "who holds each of those" costs one comments API call per
  issue on top of the issue list, because the claim holder is the
  *author* of the last comment opening with `Claim`
  (`work.sh:293-298`) and nothing indexes it.
- `git worktree list` returns 21 entries on this host, and three
  harness sessions are live. Neither fact exists in GitHub at all, and
  nothing on either side says which of the 21 checkouts has anything
  behind it.
- Four open pull requests form a three-deep stack spanning two issues:
  #60 (`odyssey/43-harness-agnostic-launch` into `main`), then #62
  (`athena/44-repin-personas-to` into `odyssey/43-...`), then #63
  (`daedalus/44-repin-personas-to` into `athena/44-...`). #44 cannot
  reach `main` until #43 does. Neither issue's labels nor either
  thread says so; the dependency exists only in the `base` field of
  two pull requests.
- **#44 carries `intent:new`, `in-progress` and `status:planning`
  simultaneously**, while PR #62 already carries its intent.md *and*
  an Approved spec.md, and PR #63 carries its plan.md. The label says
  rung 1 is current; the artifacts say rung 3 is done. `work.sh 44`
  reads the label (`work.sh:206-222`) and resolves the **plan** rung —
  it would dispatch Athena to write an intent.md that is already in
  review three pull requests deep. Each source is individually
  correct; only the join is wrong, so only the join can show it.
- #25 carries `intent:new` alongside `status:implementing` — the
  defect #57's intent records as its open question 3 — and it sits on
  the tracker with nothing surfacing it.

Two costs follow. For the operator, the questions that matter most
(who is stuck, what contradicts what, which of 21 checkouts is dead)
are exactly the ones the current procedure is worst at, because they
are join questions and the procedure is a per-item walk. For the
workshop, INTENT.md:36-41 promises a live demo that drives one real
change through the entire loop while attendees watch, and *"which
agent is working right now, on which rung"* is precisely what an
audience watches for. Today it is on nobody's screen.

The repository does not lack state. Its state is five sources deep and
joined nowhere.

## Proposed outcome

One command, needing no argument, prints in one screen the answer to
"who owns what, at which rung, and where is it running" for every item
in flight — and needs no follow-up lookup to decide what to type next.

- **The join is the deliverable.** Every fact it shows exists today.
  The value is that labels, claims, pull requests, branches and (per
  Open question 2) local checkouts appear *correlated*, at one moment,
  on one screen.
- **Disagreement between sources is printed as disagreement, never
  resolved.** Tonight's #44 — label at rung 1, plan.md in review,
  claimed by a persona who does not own the labelled stage — appears
  as a named contradiction. A view that quietly picked a winner would
  be worse than the manual join, because it would launder the one
  failure the operator most needs to see. What is *done* about a
  contradiction is Open question 3.
- **It never disagrees with the dispatcher about the mutex.** The
  holder it names is the holder `work.sh` would refuse for — the same
  claim rule (`work.sh:295`) and the same login-to-persona mapping
  through `authority.identity` (`work.sh:249-260`). The operator's
  next action is `work.sh <n>`; a board naming a different holder is
  worse than no board.
- **It answers "what next", not only "what now".** Per item: the rung,
  the artifact that rung owes, and which persona owns it — derived
  from `personas/lifecycle.json` and the persona sources exactly as
  the dispatcher derives them, so the screen and the dispatcher cannot
  drift.
- **It is read-only and stateless.** No GitHub write of any kind: no
  label, no comment, no issue, no merge. Nothing it produces is
  committed. There is still no STATUS.md, and this must not become one
  by the back door.
- **It costs no model call.** Deterministic bash, `gh`, `jq` and
  `git` — the shape `work.sh` and `lifecycle_advance.sh` already hold
  — so the same command runs for anyone with a clone and a token.
- **It fails loudly and partially.** A source it cannot read (a
  permission the persona App lacks, `ps` unavailable, an unreadable
  worktree list) prints as *unknown* in that column while the rest of
  the screen still renders. An empty board and a broken board must
  never look alike (INTENT.md:351-352, "fail loudly").

Out of scope, named so they are not re-proposed: the history of one
issue (#71 `ops.trace`, which already draws this line — the board is
the present of every issue, the trace is the past of one); reviewer
verdicts and consensus as machine state (#8/#9); and acting on what is
seen (#64's merger, #11's watchers).

## Affected users and systems

- **The operator/presenter**, the primary user: README:3-6 casts them
  as the person whose whole job is typing a number and merging, and
  this is the screen that tells them which number.
- **Workshop attendees**, who watch the loop live (INTENT.md:327-331)
  and who, per Open question 2, may or may not be able to run it
  themselves.
- **Cassandra** (#11), whose control-band watchers would key on the
  same deviations this surfaces, and **#64's autonomous loop**, whose
  stated outcome already includes "one place shows, per item, which
  rung it is on" — this is that place, so its shape is #64's
  dependency and not only tonight's convenience.
- `scripts/ops/` — a new read-only sibling of `work.sh` and
  `session_spend.sh`, plus its hermetic test in `scripts/ops/tests/`.
- `personas/lifecycle.json` and `personas/*.yaml` — read inputs (the
  label/stage/artifact/owner relation, and `authority.identity`). No
  new field is added by this change; if the design finds it needs one,
  that is a shared contract with three existing readers
  (`personas.resume`) and must be argued at the spec.
- `scripts/ops/work.sh` — **not edited by this change**, but its claim
  rule becomes a shared contract rather than a private one, and #51
  (the mutex reads only the first 30 comments) becomes a defect in two
  readers instead of one.
- `docs/SPEC.md` — a new `ops.board` capability entry, upserted by the
  implementing PR, in the shape of `ops.spend` and `ops.dispatch`.
- `README.md` — see Open question 5. `docs.structure`
  (docs/SPEC.md:39-42) caps it at nine `##` sections, 150 lines, and
  **exactly one command shown as an instruction**. It is at 150 lines
  today.
- **#47** (App permissions): whatever the board reads must be inside
  what an identity already has. #71 records that persona Apps lack
  `checks:read`, so any check-run column is either operator-only or
  *unknown*.

## Constraints

- **Read-only toward GitHub, absolutely.** It observes the state
  machine; it is not part of it. In particular it is **not** a second
  writer of `hold`: `ops.dispatch` already settles that "the advancer
  is the single writer of the circuit breaker", and two writers is two
  circuit breakers.
- **Deterministic, no model call:** bash, `gh`, `jq` and `git`,
  `set -euo pipefail`, no Python, runnable by the same command in any
  clone.
- **One table, no fourth copy.** Rung, label, artifact and owner come
  from `personas/lifecycle.json`; identities from `personas/*.yaml`.
  No rung's label, artifact or owner is spelled out inside the script.
- **Claim resolution is `work.sh`'s, not a second implementation.**
  The holder is the *author* of the last comment opening with `Claim`,
  mapped through the identity table — never a name read out of a
  comment body, which is an unauthenticated string. Divergence between
  the two readers is a defect in this tool, whichever one is "right".
- **Nothing it produces is committed.** No status file, no generated
  report in the tree; `runs/` is gitignored scratch
  (INTENT.md:280-302).
- **Cost per invocation is a design constraint, not an afterthought.**
  The claim holder is one comments call per in-flight issue, so the
  screen is O(N) API calls, and a view refreshed during a demo
  multiplies that. Whatever shape is chosen states its call count and
  stays inside GitHub's secondary rate limits.
- **Hermetic test, house pattern:** stub `gh` first on `PATH` serving
  canned fixtures, a log that fails the test if any write is
  attempted, one `PASS:` line per assertion, non-zero exit on the
  first failure (`scripts/ops/tests/work_test.sh`).
- **Prior art, evidence and not design:** draft PR #69
  (`bot/68-board`, `scripts/ops/board.sh`, 403 lines plus a 289-line
  test) was built outside the ladder by the operator's assistant. It
  is admissible as evidence that the join is computable from the tools
  already required here, and as *one* possible shape. It is not the
  design, it settles none of the questions below, and how much of it
  is reused is the implement rung's call. Two facts from it are worth
  carrying: it needs one comments call per in-flight issue, and it
  adds 20 lines and a section to a README already at its cap.
- **Disjoint from** #71 (`ops.trace`, the past of one issue) and #64
  (acting on the state). **Related to** #51 (the shared claim-reading
  defect), #57 (the `intent:new`-beside-`status:*` state this will
  display), #47 (permissions), and #11 / #8 / #9 (later consumers).
- **Depends on**: nothing open.

## Open questions

These were to be put to the product owner during this stage; the
harness this session ran under could not reach them interactively, so
they are recorded in full rather than guessed at. Each is resolved at
the design gate, and none may be left open when the spec is Approved.

1. **Is a row an issue, or an actor?** (a) Issue-centric: one row per
   item in flight, with the holder as an attribute. (b) Actor-centric:
   one row per persona or session, with what it holds as an attribute
   — closer to the words the operator used ("which agents are working
   on which tasks"). The differing case is on the tracker tonight: #57
   carries `status:in-review`, owes findings from Argus and Atlas, and
   is claimed by nobody. Under (a) it has a row saying a rung is owed
   and unheld — arguably the most actionable line on the screen. Under
   (b) it has no row at all, because no actor holds it. The mirror
   case is a live harness session sitting in a worktree with no claim:
   a row under (b), invisible under (a) unless a separate section
   exists for it.

2. **Whose screen is it — this host's, or any clone's?** (a) The
   operator's terminal on the machine running the sessions: live
   processes and local checkouts are first-class columns and the
   command is honestly host-bound. (b) Any clone with a token: the
   GitHub-derived view is complete on its own and host facts are a
   clearly separate section that is simply empty elsewhere. The
   differing case is tonight's 21 checkouts and three sessions, which
   are the confusion that produced this issue: under (a) they are on
   the screen and "a checkout with nothing behind it" is a first-class
   finding; under (b) an attendee running the same command sees the
   same GitHub rows and an empty host section, and the 21-checkout
   problem is outside the board's scope by construction.

3. **When a contradiction is found, is printing it enough?** (a) Print
   only: read-only is absolute and the human (or later, Cassandra)
   acts. (b) Print, and record the deviation in the tracker as a
   comment on the affected issue, so it outlives the scrollback. The
   differing case is #44 tonight: under (a) the mismatch exists only
   as long as that terminal window does, and if the operator looks
   away it is rediscovered from scratch tomorrow; under (b) #44 gains
   a comment — and a tool that comments on an issue is a second writer
   on the very thread from which `work.sh` computes the mutex, so the
   "read-only" property above would have to be restated as "writes no
   label, but may comment". Applying `hold` is not a third reading:
   the constraint above rules it out.

4. **What counts as "in flight"?** (a) The labels are the filter:
   every open issue carrying a `status:*` or `in-progress`. (b) The
   evidence is the filter: anything with a claim, an open pull
   request, a live branch, or a status label — the union, precisely
   because the label is sometimes the thing that is wrong. The
   differing case is this issue two hours ago: #68 carried only
   `intent:new` while draft PR #69 was open against it on branch
   `bot/68-board`. Under (a) #68 is not in flight and the operator
   cannot see from the board that work exists on it; under (b) it is,
   and the board shows an open pull request on an issue at no rung —
   which is exactly the anomaly that a prototype was built off-ladder.

5. **Where does the operator learn the command exists?**
   `docs.structure` (docs/SPEC.md:39-42) caps README at nine `##`
   sections, 150 lines, and exactly one command shown as an
   instruction; README is at 150 lines and that one command is
   `scripts/ops/work.sh <n>`. (a) The cap holds: the board is
   documented in `docs/SPEC.md` `ops.board` and in its own `--help`,
   and README stays a one-command document. (b) This change amends the
   cap: README gains a section and shows two commands. The differing
   case is an attendee who clones the repository and reads only
   README, as README:3-6 invites them to — under (a) they never learn
   the board exists, so for them the problem is unsolved; under (b)
   they do, and README:5-6's "your entire job is two actions" is no
   longer true as written and must be reworded in the same pull
   request.

6. **What does "live" mean — a snapshot, or a screen left open?** (a)
   One-shot: each invocation is a full, fresh query and the tool holds
   no state between runs. (b) A redraw loop the operator leaves
   running through the demo. The differing case is a 45-minute live
   run: under (a) the screen is stale between merges and the operator
   re-types the command at each gate, with API cost equal to the
   number of times they ask; under (b) it is current without input but
   re-issues the full query set every interval, which forces a
   decision about caching or conditional requests and about what
   refresh interval is honest enough to call the thing "live".
