# Intent: a reviewer at a pull request is reviewing that pull request

**Issue:** #207 · **Author:** athena (`evekhm-athena-app[bot]`) ·
**Status:** accepted on merge of this PR

## Problem

The unattended reviewers cannot review a ladder pull request. Not
"do not yet", not "fail on a model id" — **cannot**, by the
construction of the dispatcher, and two independent refusals each
suffice. #207 reports the first; the second was found while
verifying that a fix for the first would be enough, and it is the
reason a one-line exemption is not.

- **Wall 1: the rung's own claim refuses its reviewers.** Refusal
  (g) of `scripts/ops/work.sh` (`:409-428`, rationale `:374-408`)
  reads `in-progress` from the union of the pull request's labels and
  the resolved issue's, resolves the holder as the author of the last
  structured claim comment, and refuses unless that holder is a
  resumer of the current stage. `AGENTS.md` "Working the tracker"
  says when the claim goes away: step 5 removes `in-progress` only
  *"if pausing rather than finishing"* (`AGENTS.md:180-183`), and
  step 6 states that *"a human merges. The merge **is** the state
  transition that makes the next stage claimable"* (`:184-186`).
  Finishing a rung is not pausing, so between "pull request opened"
  and "pull request merged" — the review window, exactly — the issue
  is claimed and both reviewers are refused. Three ladder pull
  requests with the run log read directly, one message each: PR #206
  (run 34092532238, *"in-progress on #204 is held by athena"*), PR
  #202 (run 34092067255, *"in-progress on #117 is held by athena"*),
  and PR #208 (run 34093092186, *"in-progress on #199 is held by
  daedalus"*). #207's own thread reports the same message on PR #201
  and PR #205, observed session-side. Every one of those runs
  concluded `success`: exit 2 is a refusal the workflow
  records and stays green over, by design (`.github/workflows/
  unattended.yml:371-375`).
- **Wall 2: the stage a reviewer is measured against is never
  `review`.** Hidden behind wall 1 and load-bearing. The stage is
  derived from the **issue's** `status:*` label alone
  (`scripts/ops/work.sh:311-328`); pull-request labels are
  deliberately excluded, because *"the state machine belongs to the
  unit of work and a `status:*` label on a pull request must not
  decide which rung the issue is on"* (`:238-245`, D9). Owners are
  derived from the `stage:` list in each `personas/*.yaml`
  (`:336-352`), and `argus` and `atlas` declare `stage: [review]` and
  nothing else (`personas/argus.yaml:4`, `personas/atlas.yaml:4`).
  But `personas/lifecycle.json` reaches `review` only through
  `status:in-review`, which is the `advances_to` of the **implement**
  rung (`:55`, `:60-64`) — it arrives when the last rung merges, at
  which point there is no open pull request left to review. So while
  a ladder pull request is open the derived stage is `plan`,
  `design`, `build` or `implement`, never `review`, and refusal (h)
  — *"`--as` must name an owner of the stage the labels say is
  current"* (`scripts/ops/work.sh:430-433`) — refuses the reviewer
  the moment (g) does not fire first. Five runs prove it fires on
  its own: on PR #196 (issue on `plan`), *"atlas does not own stage
  plan (owners: athena)"* (run 34089831190) and *"argus does not own
  stage plan"* (run 34045755472); on PR #193 (issue on `implement`),
  *"argus does not own stage implement (owners: odyssey)"* three
  times (runs 34020371446, 34020351592, 34020311332).
- **Consequence: the exit criterion is unreachable, not unmet.**
  `docs/PLAYBOOK.md`'s roadmap item 2 sets it — *"one PR whose
  reviewer job log shows a model call succeeding and a review posted
  by the runner itself"* (`:291-292`) — and now lists #207 first,
  ahead of the runner cluster (`:276-283`). The other causes are
  real and independently tracked: #167 (model access), #162 and #163
  (both fixed), #191 (claim identity). None of them touches this.
  With all four landed, a reviewer dispatched at a ladder pull
  request is still refused by (g), and if (g) were exempted alone it
  would still be refused by (h). The runner has never posted a review
  on a ladder pull request because it has never been permitted to try.

Underneath both walls, one mismatch. The design already says review
happens on the open pull request: #64's D1 requires that *"every
rung's pull request is reviewed under REVIEW.md unchanged"*
(`intent/64-autonomous-loop/spec.md:60`), and its D17 says in terms
that *"review happens on the open pull request, before the merge"*
(`:76`). The machinery says the opposite — that review is a rung the
issue arrives at afterwards. The dispatch path is built for the
first reading (`.github/workflows/unattended.yml:367` runs
`run.sh "$NUMBER" --as "$PERSONA"` with `NUMBER` the pull request
number, `:309`; `scripts/placement/gh-actions/run.sh:98` hands both
straight to `work.sh`), and the refusal ladder is built for the
second. The reviewers fall in the gap.

## Proposed outcome

**A reviewer dispatched at a pull request is reviewing that pull
request, not claiming the issue's work.** Two properties follow, both
narrow, both for the spec gate to ratify or replace:

1. **It is exempt from refusal (g).** The mutex exists to stop two
   sessions editing one issue's working tree (`scripts/ops/
   work.sh:393-399`; #36, Argus R1-1 and R2-1). A reviewer holds no
   worktree, writes no branch, and produces comments; the collision
   the mutex prevents cannot occur on that path. The refusal is not
   weakened for anything else.
2. **Refusal (h) is evaluated against the `review` stage for it.**
   Review is a property of an **open pull request at any rung**, not
   a rung the issue must first reach. This is what makes property 1
   sufficient rather than half a fix.

**Narrowness is the whole design.** A non-review persona dispatched
at a pull request gets neither property — nothing here creates a path
by which an implementer is launched onto a claimed issue. A review
persona dispatched at an issue number, with no pull request, is
refused exactly as today. D5's refusal order (`docs/SPEC.md:451-470`)
is untouched: the stage is already derived at `scripts/ops/
work.sh:311-328`, before (g) and (h) run, so both refusals read a
value they already had.

**Two alternatives, rejected with reasons, for the record.**

- **Release the claim at handoff rather than at merge.** It makes the
  review window unclaimed by construction, and it reintroduces the
  double-implementer race for the whole window between pull-request
  open and merge — an unclaimed issue with an open pull request is
  claimable by anyone. That is not hypothetical: on 2026-09-07 a
  second session was launched into the verifier seat because a stale
  handoff file named a session that had ended, and only a live peer
  check caught it before two verdicts existed on one pull request
  (`intent/204-verifier-stage/intent.md:37-40`).
- **A new "in review" label.** `status:in-review` already exists and
  arrives at merge — too late, by exactly the window in question
  (`personas/lifecycle.json:55`, `:60-61`). A second label for the
  same axis would also have to survive refusal (e), which refuses any
  issue carrying more than one `status:*` (`scripts/ops/
  work.sh:300-309`). If the spec prefers a signal to an exemption,
  the honest one is *"an open pull request from `<actor>/<n>-*`
  exists"*, which `work.sh` already knows when the number it was given
  is a pull request — no label, no new writer.

**Done when:** an unattended dispatch of `argus` or `atlas` at an open
ladder pull request whose issue carries `in-progress` and a non-review
`status:*` label resolves to the review stage and launches, rather
than exiting 2; a dispatch of any non-review persona at that same pull
request still refuses at (g); a dispatch of `argus` at a bare issue
number still refuses at (h); the eight refusals still run in D5's
order with the same messages for every case not named here; and
`docs/SPEC.md`'s dispatch section carries the upsert.

## Affected users and systems

- **Argus and Atlas** — the only actors that gain anything, and they
  gain no verb. Both compile from the review stage and both are
  comment-only; `REVIEW.md`'s invariant that a human is the sole
  merge authority is untouched.
- **The unattended workflow** — `.github/workflows/unattended.yml`
  dispatches reviewers with the pull request number today (`:309`,
  `:367`) and needs no new input for this. Its fork guard already
  restricts the whole matrix to same-repository heads (`:83`), so no
  fork pull request reaches the exempted path.
- `scripts/ops/work.sh` — the stage resolution and refusals (g) and
  (h), plus the tests that cover them; `docs/SPEC.md` §dispatch (the
  eight-refusals paragraph at `:451-470`); possibly
  `personas/lifecycle.json`'s `review` row, depending on open
  question 1. `scripts/placement/gh-actions/run.sh` passes its two
  arguments through unchanged (`:98`) and should stay that way.
- **#204's four ladder checks** — they run against an open pull
  request and consume this same dispatch path. #204 takes no position
  on the fix; this issue owes it a working path to arrive on.
- **#64/#151** — consensus merge assumes reviews actually run at the
  head being merged. Its D5 conjunct (3) requires both reviewers'
  verdicts to cover the current head OID
  (`intent/64-autonomous-loop/spec.md:64`), which no ladder pull
  request can satisfy while either wall stands.

## Constraints

- **No stage-enum change.** `personas/schema.json:19-26` carries a
  closed enum and `review` is already in it. Nothing here adds a
  rung, a label, or a persona.
- **D5's refusal order is preserved.** The order is specified prose
  (`docs/SPEC.md:451-470`) and (h) validating `--as` after (g) is
  called out as deliberate in the code (`scripts/ops/
  work.sh:390-392`). An exemption may change what a refusal
  *concludes*; it may not change when it runs.
- **Deterministic, no model call in the dispatcher.** `work.sh` never
  writes to GitHub (`:26`) and resolves everything from labels, the
  persona sources and the issue thread. Whether a number is a pull
  request is already known to it before the refusals run.
- **The fix must not create a path by which an implementer is
  launched onto a claimed issue.** This is the acceptance test the
  spec should write first, not a caveat: the mutex's purpose survives
  intact for every non-review dispatch, at an issue or at a pull
  request.
- **No `docs/SPEC.md` change in this pull request.** The living-spec
  upsert lands with the implementation, per the same rule #64's D19
  applied to its own spec pull request
  (`intent/64-autonomous-loop/spec.md:78`).
- **Specs never hardcode pins.** The exemption is stated as a
  property of the review path; it names no model, no harness and no
  tier (AGENTS.md; #1 D3).
- **Narrow before wide.** The non-ladder half of the same wall is
  #82's: a defect-repair issue carries only `bug`, derives no stage,
  and refuses at (f) with *"cannot derive a stage"* (`scripts/ops/
  work.sh:321-327`), so every fix pull request gets zero unattended
  review too. Same symptom, different cause, and it stays its own
  issue (`docs/PLAYBOOK.md:283-290`).

## Open questions

1. **What the `review` row of `personas/lifecycle.json` means once
   review is pull-request-scoped.** `status:in-review` is what #64's
   D17 calls the terminal state the ladder writes after the implement
   rung merges (`intent/64-autonomous-loop/spec.md:76`), and the board
   reads it. Keeping it as the post-implement state while also
   treating `review` as a per-pull-request property gives the word two
   meanings in one file. Decide in spec.md whether the row stays as
   written, gains a note, or splits.
2. **What the exemption keys on.** Either `--as` naming an owner of
   `review`, or the pull-request form of the number alone, or both
   conjoined. The first is the narrower gate and the one the code
   already leans on elsewhere — a broken atlas target must not stop
   `--as argus` (`scripts/ops/work.sh:723-728`, D20) — but it makes
   the exemption depend on a flag the caller supplies.
3. **Whether a reviewer dispatched with no `--as` should resolve at
   all.** A pull request at a two-owner stage prints both and launches
   neither (`scripts/ops/work.sh:763-773`, D4). Under the exemption
   that becomes the default outcome of a bare pull-request dispatch,
   which may be right and should be stated either way.
4. **Fork interplay.** `unattended.yml:83` already keeps the matrix to
   same-repository heads, so the exemption is currently unreachable
   from a fork. The spec should say whether `work.sh` must also refuse
   it independently, or whether the workflow guard is the single
   owner of that rule.
5. **Whether a reviewer resuming on its own claim needs anything.**
   (g) already admits a claim held by an owner of the current stage as
   that actor resuming (`scripts/ops/work.sh:387-390`). Under the
   exemption a reviewer never reaches that branch on a ladder pull
   request; whether the branch is now dead for review personas, and
   whether a reviewer should ever hold a claim of its own, is a spec
   question.
6. **Whether #204's four ladder checks assume anything about the
   mutex.** They are mechanized against an open pull request. If any
   of them reads the claim label or the claim comment, its behaviour
   under an exempted dispatch has to be stated in one of the two
   specs rather than discovered.
