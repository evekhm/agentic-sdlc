# Intent: the loop runs itself; the human is the escalation path

**Issue:** #64 · **Author:** athena (`evekhm-athena-app[bot]`) ·
**Status:** accepted on merge of this PR

## Problem

Every rung of the ladder ends in a pull request that a human must
merge before the next rung can be dispatched. The merge is not a
formality — it *is* the state transition (AGENTS.md, "Working the
tracker", step 6: "A human merges. The merge *is* the state
transition that makes the next stage claimable"), so between any two
rungs the loop is stopped, waiting on one click.

Running #57 through the ladder priced that. The operator merged twice
in an hour and the loop stood still in between (#64). Their verdict
on the value of the gate they were performing is on the record:
judging an intent or a spec on paper is not a meaningful review for
them — "I would agree on anything just to see it working" — and a
per-rung merge click is friction, not judgement. What they want
reviewed, they want reviewed by the reviewers this repository already
has; what they want to be called about is a disagreement those
reviewers could not settle.

The gate is not, however, the only thing standing between the
existing parts and a closed loop — and the second thing is in scope
here, because without it this change buys nothing. Only the two
reviewers are bound to an unattended trigger: `argus` and `atlas` are
`repo-event`, while `athena`, `daedalus` and `odyssey` are
`trigger: manual` (#25, D19). Remove every merge click and the ladder
still halts after each rung, waiting on a dispatch instead of a
click. The predecessor named the reason it never crossed that line —
the implementer "was summoned by a human `@odyssey` mention, never by
a bot ('bot-summons-bot is a runaway loop')" (#64, prior art) — which
is the same hazard the caps below exist to bound, seen from the
trigger side rather than the merge side.

The verdict producer is specified
(REVIEW.md: severity tiers, the three-round funnel, per-finding IDs,
the ledger, consensus rules, and a `merge-ready` state defined as "no
open blocking rows, consensus agreed, and the reviewed head matches
the current head"). The unattended execution home is decided (#25,
D11/D19: both reviewers bind to an unattended placement in v1). The
label ladder reaches the review rung (#57). The predecessor
(`agentic-experiments-lab`) computed that same consensus
deterministically in bash and jq, derived `review:merge-ready` from
it, and then **merged nothing** — "Merge is the escape hatch": no
branch protection, no bot merge, no auto-merge, the label informing
the human's merge and never gating it (#64, prior art). The
definition of "this pull request is ready" has existed, computed and
recorded, for the whole life of both repositories. Nothing consumes
it.

This reverses two founding lines, deliberately and on the product
owner's decision: INTENT.md's constraint "Humans gate
merge/deploy/close on every path; agents never reach the default
branch" and the per-stage `GATE: ... human merges` lines in its
lifecycle, restated by README ("You are the sole merge authority on
every path") and by `docs/SPEC.md` `tracker.workflow` step 6 and
`review.policy`. The reversal is not relitigated here; this intent
records it and asks for the design.

Why it stopped short in the predecessor is the whole risk, and it was
economic rather than philosophical: that loop cost roughly $6,448 in
one week, one pull request ran 19 unattended rounds before any budget
gate existed, and at one point all nine open pull requests held
`consensus:agreed` while nothing could merge (#64, `COST_LESSONS.md`).
An autonomous loop without the caps that were retrofitted afterwards
is the same experiment run again.

And the caps that were retrofitted there do not, by themselves, cover
this. Every one of them binds a pull request or a run. In an
autonomous ladder the outermost loop is no longer the model sweep the
predecessor retired: it is merge → advance → dispatch → merge, a
cycle per *issue* that this change is precisely what creates. Nothing
in the record bounds it, and this repository has already written down
what that costs: "Every loop level needs its own budget, and the
budget on the outermost loop is the one that caps the bill"
(REVIEW.md:195-198). The concrete failure is available today rather
than hypothetical — #72 (merge discovery misidentifies the
implementing pull request) and #73 (the advancer fails open and its
guard chain has holes) are open `high` defects in
`scripts/ci/lifecycle_advance.sh`, the code every rung of an
autonomous loop walks. A misidentified merge writes a stage the issue
already passed, the trigger dispatches that rung again, a persona
opens a new pull request, two reviewers run, consensus merges, and
the advancer misidentifies again — with every per-pull-request and
per-run cap satisfied on every iteration.

## Proposed outcome

One `intent:new` issue traverses plan → design → build → implement →
review with no human action, and the human hears about it only when
the system cannot proceed on its own.

- **Each rung's pull request is merged by the system**, on a
  *recorded* consensus, and the lifecycle label advances exactly as
  it does today. Every merge is attributable: the reviewed head the
  consensus was recorded against equals the head that merged. A merge
  the ledger cannot account for is the failure mode this outcome is
  written to exclude.
- **The ladder advances itself.** A merged rung dispatches the next
  one; no human types a number between rungs. This is inseparable
  from the merge: the outcome above is a wall-clock property, and a
  loop that merges instantly and then waits for a dispatch has moved
  the stall rather than removed it. It is also the half that carries
  the runaway risk, so it ships with the bound below and not before
  it.
- **The loop the change creates is itself bounded.** Beyond the
  per-pull-request and per-run caps, an *issue* has a ceiling on how
  many rung dispatches it may consume before the system stops and
  contacts the human, and the ladder never re-dispatches a rung it
  has already merged — monotonic progress, so a mis-written stage
  label cannot become a cycle. Whether the bound is a rung-cycle
  count, a per-issue spend ceiling, or both, and what the number is,
  belong to the spec rung; that there is one, that it is evaluated
  outside any single run, and that tripping it stops the issue and
  escalates rather than failing silently, do not. This is the loop
  level REVIEW.md:195-198 says caps the bill, and `hold` does not
  cover it: `hold` is a human's act, and the case that matters is the
  one where no human is watching.
- **The human is contacted in a closed set of cases and no others:**
  reviewer consensus not reached within the round cap; a blocking
  finding still open when the round cap is reached (REVIEW.md's
  funnel already routes exactly this to a human at round 3 — "no open
  security rows --> a human resolves the open high rows: fix, retier,
  or merge", REVIEW.md:151-153 — and this outcome adopts that branch
  rather than inventing one, because a pull request whose only open
  row is an agreed `high` has consensus *agreed* under
  REVIEW.md:334-336 and would otherwise be a resting state with no
  exit); `hold` or `blocked` present; a budget gate tripped,
  including the per-issue bound above; a security-tier finding open
  at merge time. Each contact is one comment stating both
  positions and naming the decision being asked for — the
  predecessor's escalation shape (REVIEW.md, Consensus: "summarize
  both positions in two lines, tag the human owner, and stop. A
  well-summarized escalation is a good outcome").
- **The operator's surface does not grow.** Filing the issue and
  `work.sh <n>` remain the whole of it; a trigger supplies a number
  and nothing else (#25, D16). This change *removes* acts; it adds
  no flag, no dashboard to drive, and no new command to learn.
- **Four merge refusals are absolute.** The system never merges past
  a `hold`; never merges with a blocking finding open; never merges a
  pull request whose author persona is the merging identity; and
  never merges a head the recorded consensus does not cover. `hold`
  in particular is inherited unchanged from the execution model — a
  dispatch gate that is re-read immediately before every write, where
  a run whose output was computed before the label landed discards it
  and exits green (#25, D5/D13), and which attaches to the pull
  request and to every issue it closes (#25, D14). A merge is a
  write.
- **The cost caps are part of the capability, not a follow-up.** The
  round cap, the bot-to-bot exchange cap, a spend ledger, and
  fail-closed budget gates are defaults of the loop as shipped; the
  model sweep that was the predecessor's outermost cost loop is not
  reintroduced. A tripped cap is a green exit with a comment naming
  the cap, not a red run (#25, D8).
- **The consensus definition is consumed, not re-invented.**
  `merge-ready` already means no open blocking rows, consensus
  agreed, and reviewed head equal to current head; the consensus axis
  already keys on security rows only, and `disputed` already fires on
  an explicit dispute over any blocking row (REVIEW.md, Labels). The
  design rung wires that existing derivation to the merge write.
  Where the derivation has a gap — an abstention, a run that never
  posts — that gap is closed in the protocol, in one place, not
  worked around in the merger.
- **The run is watchable — on the surface #68/#69 are already
  building, not a second one.** `scripts/ops/board.sh` (#69, intent
  in flight on PR #75) renders per open item the stage, the claim
  holder, and the open pull requests with their reviewers and checks.
  This loop does not restate that; it adds the two columns an
  unattended ladder needs and a human-merged one does not — which
  reviewer verdicts landed for the current head, and where the item
  stands against its per-issue bound. The form is #68/#69's and the
  design rung's; the property is that an operator who was away can
  see where every item stands, and what it has spent, without
  reading threads.
- **The founding documents stop contradicting the loop.** Five
  documents assert the rule this reverses and are amended by the
  implementing pull request: **AGENTS.md**, which is the canonical
  cross-harness standard every actor compiles against and states it
  three times (`:43` "a bare push is not a delivery; a human merges";
  `:168` "A human merges. The merge *is* the state transition that
  makes the next stage claimable"; `:239-245`, the lifecycle mirror
  "because the merge is still the transition and the label is only
  its shadow"); **INTENT.md**'s human-merge constraint and per-stage
  GATE lines; **README.md**'s sole-merge-authority (`:102`) and
  reviewer-comment-only (`:112`) lines; **`docs/SPEC.md`**'s
  `tracker.workflow` step 6 and `review.policy`; and **REVIEW.md**'s
  "Merge is the escape hatch". Only the `docs/SPEC.md` edit is owed
  under the living-spec upsert rule, which AGENTS.md ("The living
  spec (docs/SPEC.md)") scopes to that file alone; the other four are
  owed for the plainer reason that this change makes their text false,
  and a PR that leaves the binding standard saying a human merges has
  not landed the capability. They are *not* amended
  here: Athena's authority is pull requests touching `intent/**`, and
  the issue body's request that this pull request carry the INTENT.md
  amendment exceeds it. Recorded so it is not dropped.

Explicitly **not** in this outcome: removing the human from intake
(filing the `intent:new` issue stays the human's act, and #64 notes
this makes intake the loop's front door rather than an
optimisation), and any change to the defect-repair path (#32).

## Affected users and systems

- **The operator (product owner).** Loses the per-rung merge click;
  keeps intake, `hold`, and the escalation inbox. Their acceptance
  signal moves from "I merged it" to "I did not stop it", which is
  the change they asked for and the one that most changes what a
  merge *means* in this repository.
- **Argus and Atlas.** Their verdict stops being advisory. Nothing in
  the protocol's content changes, but its consequences do: a
  `merge-ready` derivation that was informational becomes the trigger
  of an irreversible write, so its gaps (abstention, timeout, a run
  that dies mid-review) stop being cosmetic. Both are comment-only
  today (REVIEW.md, Labels; README:112), which is why the merge write
  cannot simply be handed to them without a policy amendment.
- **Athena, Daedalus, Odyssey.** Their pull requests merge without a
  human, so "the author never merges their own work" becomes a
  mechanically enforced property rather than a convention.
- **`AGENTS.md`** — the binding standard for every actor on every
  harness, and the document that states the reversed rule most often
  (`:43`, `:168`, `:239-245`). Its tracker loop ends "A human merges";
  after this it ends with a system merge and a human escalation path.
- **`REVIEW.md`** — the consensus and escalation sections gain the
  cases an advisory protocol never had to answer, and "Merge is the
  escape hatch" changes meaning: the human's merge becomes the
  override, not the norm.
- **`.github/workflows/lifecycle.yml` and
  `scripts/ci/lifecycle_advance.sh`** — unchanged in what they write,
  but they stop being driven by a human's merges and start being
  driven by the system's, and they stop having a human reading the
  result. The advancer is deterministic, idempotent and reads the
  pushed range, but it is not correct today: #72 (merge discovery
  misidentifies the implementing pull request) and #73 (the advancer
  fails open and its guard chain has holes) are open `high` defects,
  and #74 covers the test and doc gaps behind them. Under human
  merges a mis-written label costs one operator a puzzled minute;
  under this loop it is the cycle described in the Problem section.
  They move from "related" to load-bearing — see Constraints.
- **`personas/**` and `scripts/auth/app_manifests.yaml`** — reading
  (a) of Open question 2 posits a merging identity distinct from the
  six personas, which would need a persona source, an App manifest
  entry, an installation, and a line in INTENT.md's persona cast.
  Reading (b) needs none of them and needs branch-protection
  configuration instead. The two readings therefore differ in what
  they touch, not only in how they merge, which is part of what the
  design rung is choosing between.
- **The default branch's protection rules.** The merging identity
  needs `contents: write` and `pull_requests: write` on the default
  branch and nothing else (#64), and whatever protection exists must
  admit exactly that identity and no other agent. This is a **new**
  obligation of #64, not one inherited from #47: #47 closed
  completed on 2026-09-03 and its scope was `issues: write` for
  daedalus, argus and atlas so they could claim and hand off under
  the #36 protocol — a different permission for different personas.
- **`config/execution.yaml` and the placement registry (#25).** If
  the merger is a run rather than a platform feature, it is a persona
  with an unattended duty and therefore an entry there (D2), bound to
  an adapter that exists (D17). The same file carries the trigger
  change the self-advancing ladder needs: `athena`, `daedalus` and
  `odyssey` are `trigger: manual` today (D19), and D18 fixes the cost
  of moving a binding at one line each. (Note that the file does not
  exist on `main` yet — it arrives with #25's implementation.)
- **#8 and #9** — the boundary is the **recorder**, not a merge step:
  neither issue's "Done when" mentions merging (#8 ends at a posted
  protocol-v2 review, #9 at a disagreement resolved by evidence).
  What they build is the recorder — "the trusted posting step that
  validates reviewer output against a schema and performs every
  GitHub write itself … No recorder exists in this repository yet —
  it ports with issues #8 and #9" (REVIEW.md:19-25) — together with
  the ledger it maintains. #64 consumes the recorder's `merge-ready`
  derivation and adds the write; the "recorded consensus" every merge
  here depends on is the recorder's output. #8/#9 keep the review
  protocol, `review:1..3` and `status:review-stuck`.
- **#57** — closed 2026-09-03, delivered by PR #67; it supplied the
  `status:in-review` transition this builds on. Its Open question 2
  (who closes the item once the review rung is reached; the ladder
  ends with `advances_to: null`) was raised there and is inherited by
  this loop rather than created by it — and it stops being cosmetic
  here, because an issue that is never closed is an issue the
  per-issue bound must still account for.
- **#68 and #69** — the live board. They own the surface; this loop
  adds the reviewer-verdict and budget columns to it.
- **#10** — with autonomous merge, intake becomes the loop's front
  door.
- **The workshop demo.** The live act changes from "watch the human
  merge five times" to "watch it run, and watch the one escalation
  land". The failure mode also changes: an unattended loop that
  misbehaves on stage cannot be talked over, so `hold` and the caps
  are demo infrastructure, not just production hygiene.

## Constraints

- **The reversal itself is decided and is not reopened.** Per-rung
  human merge is the bottleneck; agents review and merge; the human
  is contacted only on failed consensus, `hold`/`blocked`, a tripped
  budget gate, or an open security finding; the operator's only
  surface is the one-argument dispatch (#64, product owner on the
  record).
- **`hold` is absolute, stated as a property rather than a
  mechanism: no merge occurs while `hold` is present at the moment of
  the write** — on the pull request or on any issue it closes (#25,
  D5/D13/D14; trusted-posting rule 5; `lifecycle_advance.sh`'s own
  ordering, which checks it before anything else). For a run that
  performs the write, the existing mechanism satisfies this
  unchanged: re-read the labels immediately before writing, discard
  and exit green if the label is there. A mechanism that does not
  re-read at the moment of the write — a platform feature that
  merges on a check result computed earlier — satisfies this
  constraint only if `hold` reaches it some other way, which is a
  cost of Open question 2's reading (b) and is named there rather
  than pre-decided here. `blocked` likewise stops the item.
- **No agent merges its own work.** The merging identity is never the
  authoring persona of the pull request it merges (#64).
- **No merge without an accounted consensus.** No open blocking rows,
  consensus agreed, and the recorded head equal to the merged head
  (REVIEW.md, Labels). A ledger with no head marker, or a failed head
  probe, freezes rather than guesses — the existing rule, now
  load-bearing.
- **Cost caps ship with the capability**, per Proposed outcome: round
  cap, bot-to-bot cap, spend ledger, fail-closed gates, no model
  sweep; turn and time caps from the persona source and the dollar
  cap from `config/execution.yaml`, never written into a workflow
  file (#25, D8). Fail-closed means a gate that cannot evaluate does
  not merge.
- **Every loop level carries its own budget, including the outermost
  one this change creates** (REVIEW.md:195-198). The per-issue bound
  and the monotonic-progress invariant in Proposed outcome are
  constraints on the design, not options it may trade away: a design
  in which the only caps bind a pull request or a run does not
  satisfy this intent, however cheap each iteration is. The bound is
  evaluated outside any single run — a run cannot be the thing that
  counts how many runs there have been — and tripping it stops the
  issue and contacts the human.
- **Self-dispatch never becomes self-trigger without a bound.** The
  ladder advancing itself is what makes the loop autonomous and is
  also the predecessor's stated reason for keeping a human in it
  ("bot-summons-bot is a runaway loop", #64). The two ship together
  or neither ships: no dispatch trigger lands before the bound above
  can stop it.
- **Determinism where determinism is possible.** The consensus
  computation and the merge decision are deterministic — the
  predecessor computed both in bash and jq, and this repository's
  ladder advancer is deterministic bash with no model call
  (`lifecycle.labels`). A model may produce findings; a model must
  not be the thing that decides a merge.
- **Trusted posting.** The merge, like every other GitHub write, goes
  through a vetted repository step, never an API call composed inline
  by a model, and credentials reach it by name (trusted-posting rules
  1–2; #25, D6).
- **Least privilege on the default branch.** `contents: write` and
  `pull_requests: write` for the merging identity, nothing else, and
  no other agent identity gains default-branch write (#64). This is
  #64's own obligation; #47 is closed and covered `issues: write` for
  three other personas.
- **Harness- and vendor-agnostic.** No persona source names a harness,
  a model family, or a model ID; which runtime backs which persona,
  and where it runs, are `config/` pins (INTENT.md, persona cast;
  #25, D10). This intent names none.
- **Reversible.** Turning the autonomy off must not require undoing
  the design: `hold` halts an item, and there must be a way to run
  the ladder with human merges again — the workshop demonstrates both
  the manual loop and the autonomous one.
- **Public repository.** Nothing here admits a fork's pull request to
  an automated path; automated runs never trigger on
  `pull_request_target` (#25, D7). An autonomous *merge* raises the
  stakes on that rule rather than changing it.
- **This pull request touches only `intent/64-autonomous-loop/`.**
  The document amendments listed in Proposed outcome are the
  implementing pull request's — the `docs/SPEC.md` entry under the
  living-spec upsert rule, and AGENTS.md, INTENT.md, README.md and
  REVIEW.md because the change makes their text false.
- **Dependencies, against the tracker as it stands today.**
  *Delivered:* #57 (closed 2026-09-03, PR #67 — the ladder reaches
  `status:in-review`) and #47 (closed 2026-09-03 — a different
  permission, see above). *Open and required:* #8 and #9 (the
  recorder and the ledger this consumes) and #25 (the execution home,
  and the `config/execution.yaml` this needs to exist). *Promoted to
  required:* **#72 and #73**. They are open `high` defects in the
  advancer, and an autonomous merger may not run ahead of their
  repair, because the loop this creates walks that code on every rung
  with nobody reading the result — the failure scenario in the
  Problem section is exactly #72 plus self-dispatch. #74 (their test
  and doc gaps) is required by the same argument if the fixes are to
  be trusted unattended, but is a sequencing call for the design
  rung. *Related:* #68/#69 (the board this reports onto), #10 (intake
  becomes the front door).

## Open questions

1. **Which rungs are reviewed, and under what protocol for prose?**
   (a) Every rung's pull request is reviewed and merged the same way,
   with REVIEW.md extended to prose artifacts — an intent or a spec
   gets findings, severities and a ledger like a diff does. (b) Only
   the code rung is reviewed; the prose rungs (intent.md, spec.md,
   plan.md) merge on a deterministic check — the artifact exists at
   the expected path, the spec carries `Status: Approved`, no Open
   questions remain — with no model verdict at all. The differing
   case: a spec.md that is well-formed, `Approved`, and internally
   contradictory. Under (b) it merges and the contradiction is found
   at the implement rung, if at all; under (a) a reviewer can block
   it, which also means a reviewer can block it wrongly and stall the
   plan rung behind a prose dispute. A sub-question either reading
   must answer: what severity tiers even mean for prose, given
   REVIEW.md's `high` list is a closed enumeration written for code.
2. **Who performs the merge write, and under what identity?** (a) A
   dedicated identity — a merger persona or an infrastructure
   identity distinct from all six personas — evaluates the recorded
   consensus and calls the merge API; the "never your own pull
   request" rule then holds by construction. (b) No agent calls
   merge: branch protection plus GitHub's auto-merge does the write,
   with the reviewers' consensus expressed as a required check or a
   required approving review, so the platform merges when the
   conditions go green. The differing case: a pull request reaches
   `merge-ready`, and thirty seconds later a new commit is pushed to
   its head. Under (b) auto-merge re-evaluates against the new head
   and the required check is stale-or-failing, so nothing merges
   until it re-runs; under (a) the merger must itself re-verify that
   the recorded head still equals the current head before writing, and
   the whole correctness of the loop rests on that one comparison. A
   second differing case: a required *approving review* under (b)
   means the reviewer identities stop being comment-only, which
   contradicts REVIEW.md's Labels rule and README:112 — so (b) forces
   a policy amendment that (a) does not. A third differing case, and
   the one the Constraints section defers here: `hold` is applied at
   14:00 to a pull request whose required checks went green at 13:59.
   Under (a) the merger re-reads labels immediately before the write
   and stops. Under (b) the platform holds no such rule — the label
   is not a check it re-evaluates — so the merge lands unless `hold`
   is itself expressed as a required check, or auto-merge is disarmed
   by the label event. Reading (b) is not excluded by that; it is
   charged for it, and the charge is part of what the design rung
   weighs.
3. **What is consensus when a reviewer abstains or never answers?**
   (a) Consensus requires both reviewers to have posted for the head
   under review: a missing verdict is not agreement, so a reviewer
   that dies, times out, or abstains blocks the merge and eventually
   escalates. (b) Consensus is the *absence of unresolved objection*
   within a bounded window: one clean verdict plus no dispute from the
   peer by the deadline is `agreed`, extending REVIEW.md's existing
   principle that "where nothing is in scope, require no consensus"
   and its warning that demanding a verdict on nothing is how clean
   items stick in pending forever. The differing case: Atlas's
   unattended run fails to start (its placement is down) on a pull
   request Argus reviewed clean. Under (a) the item waits and then
   escalates to the human — the safe answer that reproduces the
   predecessor's "nine pull requests agreed and nothing could merge".
   Under (b) it merges on one reviewer, which silently converts the
   dual-family design into a single-reviewer loop precisely when the
   second family is broken. Reading (b) also needs a deadline, but
   the clock is not the new part: every ledger row already records
   "the timestamp the row entered its pending state"
   (REVIEW.md:213-214), the stale-peer rule is written against that
   timestamp rather than the review marker precisely so a
   frequently-pushed pull request cannot dodge it (REVIEW.md:220-222),
   and the stale-peer check is already one of the two zero-token
   deterministic sweeps (REVIEW.md:404-408). What (b) adds is a
   deadline that *authorizes a merge* — a new authority granted to an
   existing clock. A sub-question inside this one, and the same
   question seen from the human's side: reviews are dispatched by,
   among other things, "an explicit reviewer mention, or manual
   dispatch" (REVIEW.md:403-404), so what does a human asking for a
   re-review do to a running deadline — reset it, extend it, or
   bypass it? The differing case is an operator who mentions the
   missing reviewer one minute before the deadline expires: reset,
   and the merge waits for the answer they asked for; bypass, and it
   merges while that review is still being written. The security tier
   is the one place
   REVIEW.md already answers this — security rows require both
   reviewers' explicit AGREE, twice — so whichever reading wins must
   not relax that row.
4. **What shape is an escalation, and what does it stop?** The label
   half is *not* open: AGENTS.md:239-240 already says "`review:3`
   escalates to `status:review-stuck`, where humans take over", and
   `docs/SPEC.md` `lifecycle.labels` provisions the label and assigns
   its writer to #8/#9. So the readings are (a) comment plus the
   existing label, the comment carrying the two-line summary of both
   positions that REVIEW.md's cap already requires; versus (b)
   comment only, which is a second reversal — it requires amending
   AGENTS.md:239-240 and `docs/SPEC.md` `lifecycle.labels`, and this
   intent proposes no such thing. The differing case, and the reason
   (a) is worth stating rather than assuming: an operator away for a
   day comes back to a tracker. Under (a) the escalated items are a
   label query and any board renders them; under (b) they are buried
   in notification history, and an item stuck for the fourth time
   looks exactly like an item stuck for the first. What is genuinely
   open under (a) is who *clears* the label: an escalation the human
   resolves by commenting, not by editing labels, leaves the item
   stuck forever — the same "every resting state needs a reachable
   exit" trap (REVIEW.md:353-355) one rung further out. Two readings
   there: the human clears it by hand as the act of taking the item
   back, or the next successful consensus on a new head clears it
   automatically; they differ on an item the human answers in a
   comment and then ignores, which stays stuck under the first and
   resumes under the second. There is also a scope question
   inside this one: does escalating stop only that pull request, or
   the whole issue's ladder? They differ when a plan-rung dispute
   escalates while the same issue has no other work in flight — the
   answers coincide — versus a repository running several items,
   where per-item stop is obviously right and a global stop is
   obviously wrong, which suggests the answer is per-item but does not
   decide what happens to a *dependent* item.
5. **How does a human's edit-in-the-pull-request override interact
   with an automatic merge?** Raised in #64 and not answered there.
   (a) A human push to the head branch is just another head change:
   the recorded consensus no longer covers the head, the reviewers
   re-review, and the system merges when they agree again — the human
   is a participant with no special standing in the merge decision.
   (b) A human edit is an override that ends the automation for that
   pull request: the item leaves the autonomous path and the human
   merges it themselves. The differing case: the operator fixes a
   typo in a spec.md at 14:00 on a pull request that was `merge-ready`
   at 13:59. Under (a) two model-bearing review runs are paid for to
   re-bless a typo fix, and the merge happens minutes later without
   them; under (b) the pull request stops dead until the human
   returns to merge it — which is the bottleneck this issue exists to
   remove, arriving through the back door every time the operator
   touches anything. A likely third position (a human edit re-triggers
   review but the human may also merge immediately) is *not* a
   separate reading, it is (a) plus REVIEW.md's existing
   merge-anytime escape hatch; the design rung should confirm that
   escape hatch survives, since it is the only remaining way to
   override a stuck loop other than `hold`.
