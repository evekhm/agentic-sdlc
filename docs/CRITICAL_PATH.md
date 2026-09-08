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

Status line: 2026-09-08. Live `gh issue list` state always beats this
file.

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
review ran, and counted, on #207's own open PR.

| # | Issue | Why it is here | State |
|---|-------|----------------|-------|
| 1 | #207 | The claim mutex refuses every ladder PR's review for its whole open window, and the derived stage is never `review`. Two walls; 1b is measurable only after this lands. | implementation PR #233 merged ec18f8d; issue at status:in-review; the agy-207 claim (in-progress) still on the issue at write time, to be released by the operator |
| 2 | #167 | atlas cannot see its model on the runner: every atlas job fails at launch with "invalid model selection (--model gemini-3.1-pro-low-thinking)", last measured in run 34096818383 at 07:43. The re-pin is already on main (11b88aa, 056ff96); PR #215 is a no-op, to be closed. The live fix is PR #221 (fix/167-agy-adc-credential), mergeable, argus round 1 posted 2026-09-07 16:40 UTC; it and #233 both edit scripts/ops/work.sh, so #221 needs a rebase. Gate 1a stands on argus alone until this merges and a status-labelled PR's atlas log shows a model call. | open, in-progress; PR #221 open (rebase needed), PR #215 open as a no-op to be closed |
| 3 | #169 | jsonschema is missing on the runner, so a persona cannot run the compiler gate. | done: PR #214 merged 07:50, issue closed |
| 4 | #168 | Permission posture for a persona on a CI runner: bypass or allowlist. An operator decision, not a build. | open, intent:new |
| 5 | #191 | Claims land under the bare human login. Identity as a hard claim-time parameter; needed before any board reading is trustworthy. | open |

## Gate 2: the trigger becomes a label and merge becomes a decision

Start once gate 1's criterion 1b is met — met 2026-09-08 (above); this
gate is open.

**Agy wave dispatched 2026-09-08 04:06–04:08 UTC:** PR #228 (#151
amendment r1 of the #64 spec, resolves R3-1, R3-2), PR #229 (#98
spec), PR #230 (#68 spec), PR #231 (#85 spec) — all open, verifier
queue in that order after #233. The #64 plan rung launches after #228
merges. Model facts, stated plainly: the #207 implementation and the
#98/#68/#85 specs were produced on gemini-3.8-flash-high, the #151
amendment on gemini-3.1-pro-low-thinking, each in under ten minutes of
wall clock; verdicts pending.

| # | Issue | Why it is here | State |
|---|-------|----------------|-------|
| 6 | #147 | `mode:autonomous` and per-issue override labels honored by work.sh, unattended.yml and the driver. The switch itself. | open, intent:new |
| 7 | #108 | Budget guard and unattended queue driver. Buildable now that #172 gave agy a post-hoc ceiling. | PR #232 open 2026-09-08 04:15 (operator bot login), carries `max_cost_usd` into scripts/placement/gh-actions/run.sh and vm-local/run.sh; the gate-1b run (34186361378) is the datum showing the ceiling is printed but not enforced on a gh-actions claude launch |
| 8 | #64 with #151 | Reviewer-consensus merge. The merge gate and escalation scripts do not exist yet; #151 amendment r1 (PR #228) resolves R3-1 and R3-2. | #64 at status:build; PR #228 open, verifier queue after #233 |
| 9 | #148 | A deterministic closer after review. Removes the last by-hand step. | open, intent:new |

## Gate 3: issues dispatch-ready by construction

Needed for the demo story, not for the mechanism.

| # | Issue | Why it is here | State |
|---|-------|----------------|-------|
| 10 | #117 | Typed intake: issue forms and deterministic triage on open. | plan PR #202 open |
| 11 | #82 | Repair path through the one command. Today every bug fix gets zero unattended review by construction: both reviewers refused PR #214 with "cannot derive a stage for #169", and it merged knowingly unreviewed. Moved here from gate 1: it does not block 1a or 1b, but it is the coverage hole after them. | open, intent:new |
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
  refusal the workflow expects. A bug, kept separate from #82. Now
  unblocked; launch pending (operator, `~/waves/launch.sh 216`).

## Standing seats

- **#199** (advisor persona `nestor`): plan merged (PR #208), issue at
  `status:implementing`, claim released. Its implementation dispatch
  waits behind #207 per the operator's direction and needs nestor's
  harness pin posted on the issue first (plan T3).
- **#204** (verifier as the review stage of `argus`): spec PR #211 open.
  Blocks nothing above.

## Decisions only the operator can make

- #168 posture (blocks gate 1 after #207).
- Confirm #82 and #198 drop out of the gate-1 blocking set.
- When to fire #181.
