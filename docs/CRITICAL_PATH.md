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

Status line: 2026-09-07, ~07:45 UTC. Live `gh issue list` state always
beats this file.

## Gate 1: one real unattended review exists

Exit criterion: one pull request whose reviewer job log shows a model
call succeeding and a review posted by the runner itself. Nothing
downstream can be trusted until this exists. Order matters.

| # | Issue | Why it is here | State |
|---|-------|----------------|-------|
| 1 | #207 | The claim mutex refuses every ladder PR's review for its whole open window, and the derived stage is never `review`. Two walls; everything below is measurable only after this lands. | spec PR #212 open; plan and implement rungs follow |
| 2 | #167 | atlas cannot see its model on the runner. The re-pin landed; sufficiency is measured by the next status-labelled PR's atlas log, which #207 unblocks. | open, in-progress |
| 3 | #169 | jsonschema is missing on the runner, so a persona cannot run the compiler gate. Independent of #207; prompt is written. | open |
| 4 | #168 | Permission posture for a persona on a CI runner: bypass or allowlist. An operator decision, not a build. | open, intent:new |
| 5 | #191 | Claims land under the bare human login. Identity as a hard claim-time parameter; needed before any board reading is trustworthy. | open |

## Gate 2: the trigger becomes a label and merge becomes a decision

Start once gate 1's exit criterion is met.

| # | Issue | Why it is here | State |
|---|-------|----------------|-------|
| 6 | #147 | `mode:autonomous` and per-issue override labels honored by work.sh, unattended.yml and the driver. The switch itself. | open, intent:new |
| 7 | #108 | Budget guard and unattended queue driver. Buildable now that #172 gave agy a post-hoc ceiling. | open, intent:new |
| 8 | #64 with #151 | Reviewer-consensus merge. The merge gate and escalation scripts do not exist yet; #151 holds two round-3 findings left open at spec merge. | #64 at status:build; #151 open |
| 9 | #148 | A deterministic closer after review. Removes the last by-hand step. | open, intent:new |

## Gate 3: issues dispatch-ready by construction

Needed for the demo story, not for the mechanism.

| # | Issue | Why it is here | State |
|---|-------|----------------|-------|
| 10 | #117 | Typed intake: issue forms and deterministic triage on open. | plan PR #202 open |
| 11 | #82 | Repair path through the one command. Today every bug fix gets zero unattended review by construction. Moved here from gate 1: it does not block the exit criterion. | open, intent:new |
| 12 | #89 | `/work <n>` drives the whole ladder from one session. | open, intent:new |

## Parallel track, any time

- **#181** — the wave-1 agy preamble into GEMINI.md numbered rules plus a
  tracked launch template. Both kickoff prompts are written. This is what
  makes the cheap-model story measurable; fire it as soon as a frontier
  session is free.
- **#198** — CI gate for `distinct_model_families`. A guard against
  regression, not a blocker; slides to whenever config is next touched.

## Standing seats

- **#199** (advisor persona `nestor`): plan PR #208 open. Its
  implementation dispatch waits behind #207 per the operator's direction.
- **#204** (verifier as the review stage of `argus`): spec PR #211 open.
  Blocks nothing above.

## Decisions only the operator can make

- #168 posture (blocks gate 1 after #207).
- Confirm #82 and #198 drop out of the gate-1 blocking set.
- When to fire #181.
