# Critical path: the ordered plan to the autonomous loop

The goal: agents review and merge every rung, the human is only the
escalation path on failed consensus, demonstrated end to end on the
cheapest capable model. This file is the ordered list of issues that
stand between today and that goal, grouped by gate. It answers one
question: **what must land next, and what is waiting on what.**

The four-item narrative of *why* the gates are shaped this way is
[PLAYBOOK.md](PLAYBOOK.md) ("Roadmap: from YOLO off to YOLO on"). This
file is the live ordering under it. The advisor seat owns both; update
this file whenever an issue in it merges, closes, or changes gate, and
carry the date on the status line.

Status line: 2026-09-08, revision six (~20:15 UTC): step 3's PR #257 hit
Argus's round-3 cap at head `b5d978ca` with a `security` row still open
(R1-1) and one partly-fixed with an open residual (R1-2), plus four
open `high` rows (two new this round). Per REVIEW.md's funnel an open
`security` row at round 3 escalates to a human; Argus writes no more
labels and no merge from here. Atlas has not re-reviewed past round 1's
`900b4408` head. Live `gh issue list` state always beats this file.

## Fast path to the demo (operator directive, 2026-09-08 06:40 UTC)

The operator's call: cut corners, skip review rounds, get the loop
working end to end. Until they say otherwise the verifier merges on a
smoke check (deterministic checks green at the head, the diff matches
the body, no leaks), nobody writes fix-round prompts, and the gates
below are read as priority order, not ceremony. The demo is one issue
going from its build rung to merged with the runner reviewers
reviewing and the loop merging, no human write in between. Steps, in
order:

1. Merge PR #235 (#64 plan), PR #237 (#216 fix) and PR #232 (#108
   ceiling) on smoke.
2. #242: give atlas the review-dispatch exemption in
   `personas/skills/resume-protocol.md` (refusals 5 and 6), recompile,
   one small PR, merge on smoke, so a ladder PR can have two reviewer
   voices.
3. #64 implementation rung on agy (odyssey; prompt
   `ops/waves/w4-64-odyssey.txt`, launch line `ops/waves/launch.sh 64i`).
   Launched by the operator 2026-09-08 06:50:36 UTC as agy-64i (worktree
   odyssey-64-autonomous-loop, branch odyssey/64-autonomous-loop); #246
   (lifecycle_advance_test.sh run by no workflow) and #245 (no closing
   keyword in any commit body) reached the session through the #64 thread
   because the launch preceded the prompt amendment. **Not merged on
   smoke after all**: PR #257 (head 900b4408, two rounds) shipped a
   "Completed" table contradicted by the diff (#258), two open `security`
   rows from Argus (an unauthenticated merge-eligibility grep; the merge
   actor's key handed to code the PR under review authored) plus four
   open `high` from Argus and open `AT-*` rows from Atlas (dead ladder
   dispatch; the D13/D14 ledger and ratchet unimplemented; `hold`/
   `blocked` failing open; deterministic conjuncts skipped;
   `merge_gate_test.sh` exiting 0 regardless; comment pagination
   missing; no author identity check on state comments). Argus, Atlas
   and the verifier independently converged and refused across two
   rounds; smoke-merge was withdrawn for this PR specifically by the
   verifier 15:00 UTC and the advisor agreed. agy-64i went idle ~12h
   with no further push and is treated as dead. Fix round 2026-09-08
   ~19:15 UTC: agy-64ii, prompt `ops/waves/w4-64ii-odyssey.txt`, launch
   line `ops/waves/launch.sh 64ii`, resets onto and pushes back to the
   same branch so PR #257 stays the one PR; merges `origin/main` mid-round
   to absorb a README.md conflict from PR #260. **Round 3 (Argus,
   19:59 UTC, head `b5d978ca`): escalated to a human.** R1-1 (security,
   the unauthenticated merge-eligibility grep) is still open; R1-2
   (security, the merge actor's key) is partly fixed with an open
   residual (the trusted-ref checkout does not protect the workflow
   *file* itself, and `github.base_ref` is attacker-controlled); two new
   `high` rows landed this round (R3-1, a YAML indentation bug in
   `lifecycle.yml` that breaks the ladder repo-wide if merged; R3-2, an
   `issue_comment` handler that evaluates the wrong pull request). Per
   REVIEW.md's funnel, an open `security` row at the round-3 cap
   escalates to a human — Argus writes no more labels and no merge from
   here; Atlas has not re-reviewed past round 1's `900b4408` head.
   Cheapest fixes named by Argus: R3-1 (one line of indentation) and
   R3-2 (one `if` guard).
4. #251 + #252, the end-to-end chain after #64. Retired: the #147
   label-trigger slice — the merged #64 spec D16 reads "No second
   workflow, no `issues: labeled` trigger, no new event" and flips
   athena/daedalus/odyssey to `trigger: ladder`, so the chain exists
   once #64 lands. What is missing (none of it in the #64 plan): (a)
   #252 — the advancer never releases the finished rung's
   `in-progress`, and work.sh refusal (g) keys on the persona
   changing, so a run from intent:new advances one rung
   (intent→spec, athena resumes herself), writes status:build and
   stalls with the board looking advanced; fix = the transition
   releases the claim only when its holder owns the rung just merged,
   any other holder keeps the loop stopped with a named notice; (b)
   #251 gap 2 — the D16 dispatch runs the placement adapter in place
   inside lifecycle.yml (gh-actions/run.sh:128 execs work.sh), which
   has no harness and no persona key, so it prints a green skip; fix =
   start unattended.yml through workflow_dispatch (GITHUB_TOKEN may,
   with actions: write), lifecycle.yml stays secret-free; (c) #251 gap
   3, the operator's one-time checklist: loop.autonomous_merge true,
   placement gh-actions for the three personas, the Themis App
   installed with its key in the `themis` Environment (D23, P1;
   `create_all_apps.py --only themis` provisions it),
   ATHENA/DAEDALUS/ODYSSEY_APP_PRIVATE_KEY secrets loaded (names
   only), first hop stays a human dispatch of athena. Delivery: one PR
   after the #64 implementation merges, `ops/waves/launch.sh 251`
   (prompt `ops/waves/w4-251-odyssey.txt`), merged on smoke.
5. Demo run: the operator launches one rung by hand with the one-line
   prompt ("work issue #98"), and from there the loop carries it: PR,
   runner reviews, #64 merge, advancer flips the label, the runner
   dispatches the next persona, until the issue is done. The job logs
   and the issue thread are the evidence, and the verifier's job on
   that run is to watch and write down what broke, not to gate it. The
   operator launched 98p (daedalus plan rung) at ~06:44 UTC alongside
   68p, so the demo on #98 may start at the implement rung; either way
   it needs step 4 complete, including the operator checklist.

Deferred until after the demo: #239, #236, #238, #148, #191, the
other wave-3 rows, and the old verifier queue (#185, #135, #202,
#69). Also deferred: #244 (WORK_MAX_USD guard in placement_test.sh
not hermetic); #249 (eight of eleven hermetic suites, 4,689 lines,
run by no workflow; verifier authors one PR after #64 merges adding
all eight to ci-gates.yml plus a glob row; advisor clears it since
the author cannot verify their own change; the operator should know
the verifier seat is authoring); #250 (#233 residue: SPEC.md:516 vs
:477, :499 half wrong, two unfailable work_test rows, work.sh:248
reads issue state not PR state).

PR #237 was merged by squash with branch auto-delete at 06:44:04 UTC —
the web-UI shape, neither advisor nor verifier; two seats plus at
least one other hand share the operator-bot login, so merge
attribution survives only in the run record.

## Gate 1: unattended review runs on every rung — MET 2026-09-08

Two exit criteria, in order.

**1a, met:** one pull request whose reviewer job log shows a model call
succeeding and a review posted by the runner itself. Evidence: run
34093599471 on PR #188, job "argus via gh-actions", success,
07:03:34 to 07:12:04 UTC on 2026-09-07; the log ends in a real
`end_turn` result and the round-1 review comment is by
`evekhm-argus-app[bot]` at 07:11:23. The loop also closes: run
34096818383 on the same PR (argus job 07:43:01 to 07:47:27) posted the
round-2 verdict at 07:46:50, "no open blocking rows, merge-ready from my
side", the first unattended AGREE. Atlas failed in both runs with
"invalid model selection" on the dead pin; the atlas BLOCK on PR #211
at 07:44 came from a local session holding the app token, not from the
runner (no runner job on that branch produced it), so atlas has not yet
reviewed unattended.

**1b, met 2026-09-08:** by run 34186361378 (job 101935396240) on PR
#233 itself, the #207 implementation, merged as ec18f8d 05:41 UTC. The
job log shows "stage: review (pull request #233; #207 is on
implement)" and "claim: in-progress on #207, not read — a review
dispatch is not measured against it (#207, D3)", then a full argus
round-1 review posted under `evekhm-argus-app[bot]` (comment
5579181753), claude-opus-5, 9m48s, `total_cost_usd` 2.75 against a
printed `max_cost_usd` 2.0 with the check green — that overrun is
#108's gap, and PR #232 is its fix. Correction to this file's own
earlier framing: the "not met" text above implied 1b would be
measured only after #207 *lands* (merges), but `unattended.yml` checks
out the PR head, so a work.sh fix decides its own review dispatch —
"after it merges" was the wrong horizon for that class of change; the
review ran, and counted, on #207's own open PR. Confirmed on a PR
other than the fixing one: run 34194196957, job 101958310240, on PR
#235 (the #64 plan, cut after #233 merged) logs the same stage and
claim lines, a claude `end_turn` at 2.33 USD, and the round-1 argus
comment 5580331864 at 06:27:45 inside the job window.

| # | Issue | Why it is here | State |
|---|-------|----------------|-------|
| 1 | #207 | The claim mutex refuses every ladder PR's review for its whole open window, and the derived stage is never `review`. Two walls; 1b is measurable only after this lands. | implementation PR #233 merged ec18f8d 05:41 UTC 2026-09-08; issue at status:in-review, claim released. Nothing closes it unattended yet (that is #148), so the operator closes it by hand |
| 2 | #167 | atlas could not see its model on the runner; every atlas job died at launch until the credential path was repaired. | done: PR #221 (fix/167-agy-adc-credential) merged 06:09 UTC 2026-09-08, issue closed, PR #215 closed as superseded. Datum: atlas job 101933518377 on PR #221 itself succeeded with a real model call (agy, gemini-3.1-pro-low-thinking, round-3 comment 04:07:40 under evekhm-atlas-app), so both runner reviewers now run unattended. Atlas has since refused the ladder PR #235 at the persona layer (#242), so 'both reviewers run unattended' holds on argus for ladder PRs and on atlas only for PRs whose issue carries no claim |
| 3 | #169 | jsonschema is missing on the runner, so a persona cannot run the compiler gate. | done: PR #214 merged 07:50, issue closed |
| 4 | #168 | Permission posture for a persona on a CI runner: bypass or allowlist. An operator decision, not a build. | open, intent:new |
| 5 | #191 | Claims land under the bare human login. Identity as a hard claim-time parameter; needed before any board reading is trustworthy. | open |

## Gate 2: the trigger becomes a label and merge becomes a decision

Start once gate 1's criterion 1b is met — met 2026-09-08 (above); this
gate is open.

**Agy waves 1 and 2 (dispatched 2026-09-08 04:06–04:08 UTC) are fully
merged as of 06:09:** PR #233 (#207 implementation), #228 (#151
amendment r1 of the #64 spec), #229 (#98 spec), #230 (#68 spec), #231
(#85 spec), plus #221 (#167 fix) and #234 (this file, revision three).
Every wave PR passed the verifier seat and merged; #151 was closed by
the operator because the Refs-only amendment left it at intent:new
with no first status for the advancer to move. Model facts, stated
plainly: the #207 implementation and the #98/#68/#85 specs were
produced on gemini-3.8-flash-high, the #151 amendment on
gemini-3.1-pro-low-thinking, each in under ten minutes of wall clock.
That is the first measured datum for the cheap-model story.

**Gate-2 keystone: PR #235**, the #64 plan
(daedalus/64-autonomous-loop-plan, head 09d1bc1, opened 06:27 UTC by
evekhm-daedalus-app on gemini-3.1-pro-low-thinking, one file,
intent/64-autonomous-loop/plan.md, +158). Argus posted round 1
unattended at 06:27 (reviewed-head 09d1bc1 against the plan's own base
pin bf78de9); the atlas check is green but the job (101958310297) is a refusal at
the persona layer: the compiled resume protocol's refusals 5 (mutex
held by daedalus) and 6 (stage owned by daedalus) fire even though
work.sh bypassed the claim, so only one runner reviewer can reach this
PR and the verifier's own review is the second voice under #204. That
defect is filed as #242. Merged on smoke under the fast path; it is the
plan under which merge becomes a decision.

**Blocker ahead of the wave-3 plan rungs: #239** (filed by the
verifier 2026-09-08 06:24, intent:new). #207 bypassed one of four
refusals. Refusals (c) closed or review-stuck and (d) blocked fire at
scripts/ops/work.sh:288-296, eighty-two lines before REVIEW_DISPATCH is
computed at :373, so no retarget reaches them: a pull request whose
issue carries status:review-stuck can never be reviewed unattended,
which is exactly the state where a review is most needed. Observed
live: both reviewers refused PR #223 (docs, resolves to #202) with
"carries status:review-stuck", and PR #202 (#117 plan, review:3) is
stuck in it today. Ahead in priority, not in sequence: the wave-3 plan
rungs for #98 and #68 (`ops/waves/launch.sh 98p 68p`, prompts
w3-98-daedalus.txt and w3-68-daedalus.txt) touch intent/** only and can
launch now; #239 is deferred under the fast path; it bites only once
an issue escalates to review-stuck. #236 (below) edits the same file;
whichever merges second rebases.

| # | Issue | Why it is here | State |
|---|-------|----------------|-------|
| 6 | #147 | `mode:autonomous` and per-issue override labels honored by work.sh, unattended.yml and the driver. The switch itself. | open, intent:new |
| 7 | #108 | Budget guard and unattended queue driver. Buildable now that #172 gave agy a post-hoc ceiling. | PR #232 open (evekhm-odyssey-bot, odyssey/108-ci-spend-ceiling), head 77501a8 after three follow-ups (ceiling header, the docs/SPEC.md twin, the measured-run count). Verifier escalated 06:18 (comment 5580232140); advisor ruling: merges after the B1 clause fix, a rebase and real reviews, and the 8.00 ceiling is the operator's number (not objected to). Three overrun data live on it: 2.75 (argus on PR #233, run 34186361378), 2.28 (argus on PR #221) and 2.33 (argus on PR #235, run 34194196957) against the declared 2.0; across six measured argus runs the ceiling has never bound. Argus refused the PR at 06:26 because #108 is intent:new with no review stage to derive (the #82 class), so under the #221 precedent the verifier's own review under the argus seat (#204 D15) is the review of record |
| 8 | #64 with #151 | Reviewer-consensus merge. The merge gate and escalation scripts do not exist yet; #151 amendment r1 (PR #228) resolves R3-1 and R3-2. | #64 at `status:implementing`; plan PR #235 merged. Implementation PR #257 open, escalated to a human at round 3 (keystone paragraph above). #151 closed; PR #228 merged 05:45 UTC 2026-09-08 |
| 9 | #148 | A deterministic closer after review. Removes the last by-hand step. Today's by-hand closes (#207 at status:in-review with its PR merged) are exactly what it removes. | open, intent:new |

## Gate 3: issues dispatch-ready by construction

Needed for the demo story, not for the mechanism.

| # | Issue | Why it is here | State |
|---|-------|----------------|-------|
| 10 | #117 | Typed intake: issue forms and deterministic triage on open. | plan PR #202 open at review:3, status:review-stuck since the round-3 escalation; unreviewable unattended until #239 lands. The G1/G2 gates its stall produced were orphaned when #8 closed as superseded and now live on #238 |
| 11 | #82 | Repair path through the one command. Today every bug fix gets zero unattended review by construction: both reviewers refused PR #214 with "cannot derive a stage for #169", and it merged knowingly unreviewed. Moved here from gate 1: it does not block 1a or 1b, but it is the coverage hole after them. Confirmed again 2026-09-08 on PR #237 (the #216 fix, bug label only) and PR #232 (#108 at intent:new): reviewer checks green, no review posted. | open, intent:new |
| 12 | #89 | `/work <n>` drives the whole ladder from one session. | open, intent:new |

## Parallel track, any time

- **#181** — the wave-1 agy preamble into GEMINI.md numbered rules plus a
  tracked launch template. Both kickoff prompts are written. This is what
  makes the cheap-model story measurable; fire it as soon as a frontier
  session is free.
- **#198** — CI gate for `distinct_model_families`. A guard against
  regression, not a blocker; slides to whenever config is next touched.
- **#216** — a pull request with no resolvable issue dies with exit 1 in
  the resolver, so the runner check goes red instead of the exit-2
  refusal the workflow expects. Fix PR #237 open (evekhm-odyssey-app,
  odyssey/216-resolver-refusal, head f657d3e, opened 06:23 UTC
  2026-09-08 on gemini-3.8-flash-high; four files: work.sh,
  lib/github.sh, work_test.sh, docs/SPEC.md). Deterministic checks
  green; reviewer checks green with no review posted (#82 class).
  Verifier queue after #235 and #232.
- **#236** — filed by the verifier 2026-09-08 06:20. work.sh now holds
  two prompt literals (#207 added REVIEW_PROMPT at
  scripts/ops/work.sh:598) and the #43 D2 guard in
  work_test.sh:684-696 still passes, so the one-literal invariant is
  enforced by nothing. intent:new. Same file as #239; sequence the
  two.
- **#238** — filed by the verifier 2026-09-08 06:24. Gates G1 (verify
  the repair ledger against the delta before a round starts) and G2
  (count convergence) were filed on #8 and orphaned when the operator
  closed #8 as superseded; PLAYBOOK now points at #238 for them.
  intent:new. Lesson recorded in PLAYBOOK: check what an old thread
  accumulated before closing it as superseded.

## Standing seats

- **#199** (advisor persona `nestor`): plan merged (PR #208), issue at
  `status:implementing`, claim released. Its implementation dispatch
  waits on the operator posting nestor's harness pin on the issue
  (plan T3); until then the seat runs by hand from a local charter
  file on claude-fable-5-1.
- **#204** (verifier as the review stage of `argus`): spec PR #211
  merged 27bf420c 06:30 UTC 2026-09-08. Blocks nothing above.

## Decisions only the operator can make

Each item ends as an issue, a PR, or an explicit "deferred, no
tracker"; the advisor's recommendation is stated where it has one.

- **#168 posture** (bypass or allowlist for a persona on a CI
  runner). No longer gates gate 1; it decides how a persona runs on a
  runner before unattended merges at gate 3. Advisor recommendation:
  bypass on the ephemeral gh-actions runner with the App token's
  scope as the boundary, allowlist on the vm-local placement; #164
  deferred one security row here.
- **ops/waves/launch.sh into the repo** (filed as #259). Advisor position: yes in
  substance, through the ladder: an intent:new issue first, scoped as
  an extension of scripts/ops/work.sh or a sibling under
  scripts/ops/ with the issue table and the prompts as data files,
  not hardcoded, and the overlap with #64 (the unattended loop)
  stated in the intent. Waiting on the operator's go; recorded here
  as pending, not deferred.
- **nestor's harness pin on #199** (plan T3): post it on the issue
  before the implementation dispatch. The seat runs on claude /
  claude-fable-5-1 today; the pin is the operator's config call.
- **Fast-forward cadence for the primary checkout.** DECIDED by the
  operator 2026-09-08: the operator never pulls; whoever merges a
  pull request fast-forwards the primary with `git pull --ff-only`
  (AGENTS.md "Whoever merges fast-forwards the primary checkout").
- **Operator-bot login stem.** The operator's alone; it decides which
  login the ops PRs (#232, #234, this one) are attributed to.
- **Who runs `scripts/ops/worktrees.sh --prune`.** Twice on
  2026-09-07 a seat's worktree vanished under it. Advisor
  recommendation: the operator only, on a cadence they announce;
  never a seat. Confirm, and it becomes a PLAYBOOK mechanic.
- **Closes by hand:** #207 (PR #233 merged, issue at status:in-review)
  once the verifier confirms; #25, #150, #9 if still open (verify
  live before acting).
- **Wave 3:** `ops/waves/launch.sh 98p 68p`. #85 sits at status:build
  with no plan-rung row in the launcher; advisor recommendation: add
  an 85p row by the same recipe.
- Confirm #82 and #198 stay out of the gate-2 blocking set; when to
  fire #181.
