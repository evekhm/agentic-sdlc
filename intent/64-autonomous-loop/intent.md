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

The gate is also, today, the *only* thing standing between the
existing parts and a closed loop. The verdict producer is specified
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
- **The human is contacted in a closed set of cases and no others:**
  reviewer consensus not reached within the round cap; `hold` or
  `blocked` present; a budget gate tripped; a security-tier finding
  open at merge time. Each contact is one comment stating both
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
- **The run is watchable.** One place shows, per item, which rung it
  is on and which reviewer verdicts landed. `scripts/ops/` has no
  such surface today. The form is the design rung's; the property is
  that an operator who was away can see where every item stands
  without reading threads.
- **The founding documents stop contradicting the loop.** INTENT.md's
  human-merge constraint and per-stage GATE lines, README's
  sole-merge-authority and reviewer-comment-only lines, `docs/SPEC.md`
  `tracker.workflow` step 6 and `review.policy`, and REVIEW.md's
  "Merge is the escape hatch" are amended by the implementing pull
  request under the living-spec upsert rule. They are *not* amended
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
- **`REVIEW.md`** — the consensus and escalation sections gain the
  cases an advisory protocol never had to answer, and "Merge is the
  escape hatch" changes meaning: the human's merge becomes the
  override, not the norm.
- **`.github/workflows/lifecycle.yml` and
  `scripts/ci/lifecycle_advance.sh`** — unchanged in what they write,
  but they stop being driven by a human's merges and start being
  driven by the system's. The advancer already tolerates this (it is
  deterministic, idempotent, and reads the pushed range), and its
  open defects therefore matter more: #72, #73 and #74 are on the
  path an autonomous loop walks every rung.
- **The default branch's protection rules and #47.** The merging
  identity needs `contents: write` and `pull_requests: write` on the
  default branch and nothing else (#64). Whatever protection exists
  must admit exactly that identity and no other agent.
- **`config/execution.yaml` and the placement registry (#25).** If
  the merger is a run rather than a platform feature, it is a persona
  with an unattended duty and therefore an entry there (D2), bound to
  an adapter that exists (D17).
- **#8 and #9** — this issue absorbs the merge step from their "Done
  when"; they keep the review protocol, `review:1..3` and
  `status:review-stuck`.
- **#57** — supplies the `status:in-review` transition this depends
  on, and its Open question 2 (who closes the item once the review
  rung is reached; the ladder ends with `advances_to: null`) is
  inherited by this loop rather than created by it.
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
- **`hold` is absolute and inherited unchanged** — checked before
  anything else, re-read immediately before every write, attaching to
  the pull request and to every issue it closes, with suppression
  being a green exit (#25 D5/D13/D14; trusted-posting rule 5;
  `lifecycle_advance.sh`'s own ordering). `blocked` likewise stops
  the item.
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
  no other agent identity gains default-branch write (#64; #47).
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
  implementing pull request's, under the living-spec upsert rule.
- **Depends on:** #8, #9, #25, #57 (#12, tracker line for #64).
  Constrained by #47. Related: #72/#73/#74 (defects in the advancer
  this loop would exercise on every rung).

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
   a policy amendment that (a) does not.
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
   second family is broken. Note that reading (b) also needs a
   *timeout*, and a timeout is a wall-clock fact that nothing in the
   current protocol carries. The security tier is the one place
   REVIEW.md already answers this — security rows require both
   reviewers' explicit AGREE, twice — so whichever reading wins must
   not relax that row.
4. **What shape is an escalation, and what does it stop?** (a) A
   comment that mentions the human, per REVIEW.md's existing cap
   ("summarize both positions in two lines, tag the human owner, and
   stop"), leaving the item's labels alone. (b) A label —
   `status:review-stuck` already exists for exactly this, and
   `lifecycle.labels` assigns it to #8/#9 — with the comment as its
   payload. The differing case: an operator who is away for a day and
   comes back to a tracker. Under (b) the escalated items are a label
   query and any board renders them; under (a) they are buried in
   notification history, and an item stuck for the fourth time looks
   exactly like an item stuck for the first. The converse case: an
   escalation that the human resolves by commenting rather than by
   removing a label leaves (b)'s item stuck forever, so (b) owes an
   answer for who clears the label. There is also a scope question
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
