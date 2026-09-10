# Critical path: the ordered plan to the autonomous loop

The goal: agents review and merge every rung, the human is only the
escalation path on failed consensus, demonstrated end to end on the
cheapest capable model. This file is the ordered list of issues that
stand between today and that goal, grouped by gate. It answers one
question: **what must land next, and what is waiting on what.**

The narrative of *why* the gates are shaped this way is
[PLAYBOOK.md](PLAYBOOK.md) ("Roadmap: from YOLO off to YOLO on"). This
file is the live ordering under it. The advisor seat owns both; update
this file whenever an issue in it merges, closes, or changes gate, and
carry the date on the status line. Live `gh issue list` state always
beats this file.

Status line: 2026-09-10, revision thirteen (~19:10 UTC, main at
`e9c987b`).

Since revision twelve: Gate S moved two rungs. The #330 spec amendment
round 1 merged by hand as PR #395 (`8b499ed`, 18:0xZ). Plan PR #398
(daedalus) opened at 18:41Z, took one review round with zero blocking
rows (Argus 10 rows, Atlas 1 row, all normal or suggestion), and Themis
merged it at 18:52:55Z as `e9c987b`. The lifecycle advanced #330 to
`status:implementing` and wrote dispatch rung 4 at 18:52:50Z. The
implement rung (odyssey, `gemini-3.8-flash-high`) was launched by hand
at 19:03Z because the serial poller was busy.

The verifier's post-merge smoke of PR #398 carries two findings. The
five D17 fixtures are synthesized; none was recorded from a live
session. The real Antigravity payload's `display_name` is
`Gemini 3.8 Flash (High)`, which puts AT-2's expected string out of
reach under the spec's own reference implementation. The resolution:
the implement rung applies a `display_name` normalization rule under
Spec-impact, and spec amendment round 2 is owed. Its instruction file
is `ops/waves/330-spec-amendment-2.md`, machine-local, to be authored
from the operator's second machine, which holds the recordings. Next
on this gate: the odyssey implement PR, its gate merge, then amendment
round 2 by hand.

New defect, filed as #397: the lifecycle advancer withholds the
dispatch ledger row when `in-progress` is held at the moment an
artifact PR merges, and nothing re-issues the row when the hold
clears. The rung then has no ledger row for the poller to claim, and
the issue sits silent. #330 sat at `status:build` from 05:04Z to
18:25Z for this reason, and its plan rung was launched by hand.

The poller picked up the #337 fix: `poll.service` restarted at
18:30:06Z running `poll.sh` at `0b30e64` and logging to
`ops/poller/poll.log`. At 18:53Z it fired its first self-directed fix
round, on PR #365 for #85 as daedalus. Outcome pending.

## Scope (operator directive, 2026-09-10)

Until the operator says otherwise, the loop is done when these four
things work, and nothing outside them is on the path:

1. **YOLO mode works end to end.** One issue goes from `intent:new` to
   closed through the poller, the runner reviewers and the merge actor,
   including at least one fix round and one resolved dispute, with zero
   human writes. Every defect that forces a hand on the merge button is
   in scope.
2. **Wrap and handoff on both harnesses.** A session on Claude Code or
   Antigravity reaches the wrap threshold, writes its handoff, and the
   successor session starts from it with no operator paste.
3. **One statusline on both harnesses.** Claude Code and Antigravity
   render the same context line from one script, proven by fixtures.
4. **Seat personas start on Antigravity too.** The advisor (and the
   verifier) open on either harness from one tracked launch line, and
   the configured harness can be overridden by a parameter.

Inventory rule: every persona the loop names lives in `personas/` and
compiles for its pinned harness. Today `nestor` does not.

## Gate Y: YOLO works end to end

The mechanism exists: Themis has merged autonomously since 2026-09-09
19:03Z and the poller (`poll.service`) claims dispatch rows on its own.
What still needs a human is the ledger, the fix-round path and a few
stage gaps. Ordered by what unblocks the most.

Clearing an escalation by hand is now verified twice, on the plans of
#353 and #361. Check that the verifier smoke is CLEAN and that
`closingIssuesReferences` is 0. Remove `status:review-stuck` and
restore the DISPLACED label named in the escalation marker
(`status:build`), which is what the gate's D10 self-clear would
restore. Merge with `--delete-branch` as the bot. The lifecycle run
then advances the label and writes the dispatch rung, and the VM
poller claims and launches the next rung itself within about a
minute. The root cause this works around: the unattended reviewer
workflow refuses a PR whose issue carries `status:review-stuck`, so no
reviewer re-verifies and D10 self-clear can never fire. The retier
verb `@argus retier` needs a non-Bot OWNER or MEMBER, so a bot cannot
take the retier path.

| # | Issue | Why it is here | State |
|---|-------|----------------|-------|
| Y1 | #321 | Conjuncts 9 and 10 read a ranked status label; `intent:new` issues carry none, so every intent-stage PR needs a by-hand merge (PR #342 and #343 today). | DONE. PR #350 merged by hand 05:33Z (`1158acd`, conjunct 5 alone, the #331 replay). Confirmed 06:52Z when PR #362 and PR #364 merged autonomously. #321 is `status:in-review`; closing it is the operator's call or #148's job |
| Y2 | #331, #324, #328, #354, #361 | The consensus recorder. #331: a dispute flag is write-once, so every gate run replays it and re-escalates the issue (PR #327 needed a by-hand merge; PR #319 was re-labelled `status:review-stuck` 40 seconds after a hand clear, twice today, because a fix report comment re-ran the gate). #324: a `high` row is demoted when its failure-scenario sibling omits the `@Dn` anchor. #328: the assigned reviewer set is hardcoded, so #265's split gate branch is unreachable. #354: the demotion is conditional on the sibling marker dropping the `@Dn` suffix (Argus's habit), the same fragments #324 cites; PR #349 merged on three demoted rows. #361: the recorder never updates the severity of a finding ID it has already seen, so a corrected or retiered row stays as first written. | #354 DONE, merged earlier today. #361 DONE: implement PR #387 merged by Themis 10:20Z as `51d0ebf` after one autonomous review round, `status:in-review`; its ratchet N-1 spec amendment is an operator decision below. #331, #324, #328 `intent:new`. Advisor recommendation: retire #324 as superseded by #354; #331 and #328 as one recorder intent. #328 is still the wall for every spec and plan PR (PR #367, PR #365 on 2026-09-10); advisor recommendation: promote #328 ahead of #331 as its own rung |
| Y3 | #265 | The review split: Atlas on every PR, Argus at the code gate, `deep-review` as a one-shot grant. Cuts review spend per round. | DONE. PR #319 merged by hand 06:14Z as `b3f86aa`; conjunct 3 alone (#353). #265 is `status:in-review`. Rounds 1-7 normal and suggestion rows have no follow-up issue yet |
| Y4 | #337 | The poller only starts rungs; it cannot fire a fix round, so every reviewer finding waits for a human launch. | DONE from the builder side. Plan PR #359 merged autonomously 07:09Z after fix round 1 (`d177366`, closing keyword in the PR body, #245, fired by the seat); the implement rung landed and #337 is `status:in-review`, so the poller can fire a fix round. `poll.service` restarted 18:30:06Z on `poll.sh` at `0b30e64` with logging to `ops/poller/poll.log`; at 18:53Z it fired its first self-directed fix round, on PR #365 for #85 as daedalus, outcome pending |
| Y5 | #353 | Argus wrote `run-id:0` on PR #344; the recorder refused the verdict into audit notes only, and the gate declined on a stale ledger with no visible reason. | DONE. Implement PR #388 merged by Themis 10:39:54Z as `4bdbc48` after Argus and Atlas round 1 on `e4fe14f`; the plan escalation before it was cleared by hand as PR #384 (`4fe132c`). Lifecycle run 34467240566 did not rank it (D17 slug miss, #382), so the seat advanced #353 to `status:in-review` by hand at 10:41Z. The verifier's smoke, live 33 seconds before the merge and carrying no gate weight, was BLOCK on one row: the merged diff deleted REVIEW.md's finding-line grammar bullet, the only statement of the enum `merge_gate.sh:305-309` declines against, with no task, decision or Plan Sync entry; follow-up PR #389 restores it and is in a reviewer round. Two of the four by-hand merges on 2026-09-10 (PR #344, PR #319) were this defect alone |
| Y6 | #308, #312 | Concurrency group cancels gate and recorder runs across PRs; a stream-interrupted review reports FAILURE after posting. Both make clean heads look blocked. | #308 `status:implementing` (poller), #312 `status:in-review`; PR #362's three gate runs were cancelled by PR #364's on 06:37Z and never re-evaluated until a hand rerun (#308). `merge_gate_test.sh` aborts at MG-38 on `main` under the #308 contract, tracked as #386 |
| Y7 | #339 | Who may remove a label or post a refusal. Today the workflow token does it; the persona layer has no verb. Draft guard in `post.sh` belongs here (Argus, PR #319 round 4). | `intent:new` |
| Y8 | #252, #251 | The advancer never releases the finished rung's `in-progress`; the chain's checklist. | #252 `bug`; #251 `status:in-review` |
| Y9 | #148 | Deterministic close after the last rung merges; the last by-hand step of a clean run. | `intent:new` |
| Y10 | #147 | `mode:autonomous` and per-issue `pin:`/`tier:` labels resolved in `work.sh`. The switch, and the home of the harness override that gate P needs. | `intent:new` |
| Y11 | #245 | The closing-keyword check misses commit bodies; a "Closes" in a non-final rung closed #308 and #312 one rung early. | `intent:new` |
| Y12 | #345 | A fork ignored a prose read-only instruction and launched live work under this seat's name; no tool-level enforcement exists. | `intent:new` |
| Y13 | #363, #366 | The poller's own bookkeeping: #363 dispatches from a stale ledger rung and keeps the claim when `work.sh` refuses; #366 writes `stage: implement` in every claim comment because nothing sets `CLAIM_STAGE`. | both `intent:new` |
| Y14 | #376 | `extensions.worktreeConfig` is unset, so `git config --local` in a linked worktree writes the primary's shared `.git/config`, which holds the daedalus App identity; `work.sh` sets no author identity. Every persona commit from a poller worktree is authored as daedalus, so the timeline attributes autonomous work to the wrong persona. | hit on PR #387 (`d96e1c8`) and PR #388 (`f26d367`), both re-authored by hand with `--reset-author` and a force-with-lease push as the odyssey App; the fix is an operator decision below |
| Y15 | #397 | The lifecycle advancer withholds the dispatch ledger row when `in-progress` is held at the moment an artifact PR merges, and nothing re-issues the row once the hold clears. The rung has no ledger row for the poller to claim, so the issue stalls with no marker saying why. | filed 2026-09-10; #330 sat at `status:build` from 05:04Z to 18:25Z on this defect and its plan rung was launched by hand |

Exit criterion: one issue, poller-driven from `intent:new`, with a fix
round fired by #337 and a dispute resolved by the recorder, merged by
Themis at every rung and closed by #148, and the issue timeline shows
no human actor.

## Gate S: one statusline on both harnesses (#330)

| # | Issue | Why it is here | State |
|---|-------|----------------|-------|
| S1 | #330 | `scripts/ops/harness/statusline.sh`, the side-channel file, `session-start.sh`, `install.sh --check` for both harnesses, fixtures. | `status:implementing`. Intent merged (PR #343), spec merged (PR #352, `1f57021`) with none of the advisor ruling applied, amendment round 1 merged by hand as PR #395 (`8b499ed`, 18:0xZ). Plan PR #398 (daedalus) opened 18:41Z and merged by Themis 18:52:55Z as `e9c987b` after one review round with zero blocking rows (Argus 10, Atlas 1, all normal or suggestion); the lifecycle advanced the label and wrote dispatch rung 4 at 18:52:50Z. The implement rung (odyssey, `gemini-3.8-flash-high`) was launched by hand 19:03Z because the serial poller was busy. The verifier's post-merge smoke of PR #398 found the five D17 fixtures synthesized with none recorded from a live session, and the real Antigravity `display_name` `Gemini 3.8 Flash (High)` putting AT-2's expected string out of reach under the spec's own reference implementation; the implement rung carries a `display_name` normalization rule under Spec-impact and spec amendment round 2 is owed (`ops/waves/330-spec-amendment-2.md`, machine-local, authored from the operator's second machine, which holds the recordings) |
| S2 | #356 | The remote session's gh writes land as `evekhm-atlas-bot` while its commits are the athena App; a peer deleted its live claim on that evidence. | `intent:new`; fix on the remote machine is the athena App token for gh writes; the ask is a login-versus-persona preflight shared by every launch path |

Exit criterion: the fixture test byte-compares every recorded payload
(two per harness, plus one with `effort.level`) to one expected line,
and `install.sh --check` runs in CI and fails when the two harness
configurations point at different scripts.

## Gate W: wrap and handoff on both harnesses

| # | Issue | Why it is here | State |
|---|-------|----------------|-------|
| W1 | #85 | `scripts/ops/wrap.sh` writes the dated handoff and runs the close-out; the `/wrap` door is Claude Code only by the operator's scope cut of 2026-09-10 (spec D8 on PR #357, per #43 D16: no `.agents/workflows/` twin in v1). An Antigravity seat calls the script from its brief or Stop hook; the agy door is a follow-up intent that D8 must name. | spec round 2 merged 06:24Z (PR #357, Claude Code only per the operator), plan PR #365 open; the seat removed `hold` at 08:11:06Z once #354's fix was on `main`, the verifier smoked it CLEAN, and it has been reviewer-stalled since 06:44Z behind #328 (Atlas alone at conjunct (3)); merging it is the operator's call (decision below). At 18:53Z the restarted poller fired its first self-directed fix round on this PR as daedalus, outcome pending |
| W2 | #330 amendment | Claude Code injects the newest handoff from the `SessionStart` hook; Antigravity has no such hook, so `work.sh` and the seat launcher inject it at dispatch. The merged spec has no Decision for this yet; the amendment round numbers it. | decided in the advisor ruling on #330, lands with S1's implement rung |
| W3 | #329 | The ceiling enforces itself: threshold nudges at 60/70/90 percent from the side-channel file, compaction backstop `autoCompactWindow: 180000`. Consumes S1's file format. | `intent:new`; its design rung starts after S1's implement merges |

Exit criterion: a session on each harness crosses the wrap threshold,
writes the handoff, and its successor on the other harness opens with
that handoff as its first input, no paste by the operator.

## Gate P: seat personas start on Antigravity, harness overridable

Today the advisor starts from `ops/waves/seat.sh`, a gitignored script
in the primary checkout that runs the Claude command line only. The
tracked launcher `scripts/ops/work.sh` knows both harnesses but takes an
issue number and refuses a harness override by design (its D7).

| # | Issue | Why it is here | State |
|---|-------|----------------|-------|
| P1 | #199 | `nestor` as a compiled persona: `personas/nestor.yaml`, the charter as `personas/skills/advisor-session.md`, spec D15's one launch line shared with the verifier, plan T3's pin `nestor: { harness: <OPERATOR-SET> }` in `config/deployments.yaml`. The seat launch without an issue number belongs in this plan (advisor recommendation; operator decision below). | `status:implementing`, unclaimed, no PR |
| P2 | #204 | The verifier as the review stage of `argus`; same launch line. | `status:build` with a live claim |
| P3 | #259 | Track `launch.sh` and `watch-then-launch.sh`; the spec must name `seat.sh` too, as a `work.sh` form or a sibling that inherits harness, model and handoff injection from it. | `status:spec` with a live claim |
| P4 | #147 | The harness override: `--harness <name>` (and `WORK_HARNESS`) resolved at the same point in `work.sh` as the `pin:` label, one mechanism for issue dispatch and seats. Reverses `work.sh` D7, so the spec says so. | `intent:new` |
| P5 | #43, #181, #122 | Harness-agnostic launch already merged for issue work (#43 at `status:in-review`); the agy preamble into `GEMINI.md` numbered rules (#181); operational scripts as dual-harness skills (#122, `status:spec`). Supporting, none blocking. | as stated |

Personas in the repo today (`personas/*.yaml`): argus, athena, atlas,
cassandra, coder, contract-writer, daedalus, explorer, mechanic,
odyssey, scanner. Bound in `config/deployments.yaml`: argus and
cassandra on claude-code, athena, atlas, daedalus and odyssey on
antigravity. Unbound (Claude-only subagents): coder, contract-writer,
explorer, mechanic, scanner. Missing: `nestor`. The verifier is a stage
of argus (#204), so it adds no file.

Exit criterion: one tracked line opens the advisor on the harness
pinned in `config/deployments.yaml`, and the same line with the
override opens it on the other harness; both start from the newest
handoff.

## Order of landing

1. PR #350 merges (Y1). DONE 05:33Z, confirmed 06:52Z. From then on
   intent-stage PRs merge on their own.
2. Y2 recorder intent filed and walked (one issue or three, operator
   call); until it merges, a held clean head is merged by hand with the
   holding conjunct named on the PR.
3. #328 as its own rung (recorder writes the dispatched reviewer set;
   the gate's Atlas-alone branch becomes reachable). Until it lands
   every spec and plan PR merges by hand, citing #328 on the PR.
4. #354 plan and implement rungs. DONE, merged earlier today; the
   `hold` on PR #365 is now the operator's call. #361 walked the same
   path and is DONE, implement PR #387 merged by Themis 10:20Z.
5. PR #319 merges (Y3), by hand if Y2 is still open. DONE 06:14Z, by
   hand (#353).
6. #330 amendment merges by hand, `in-progress` comes off, the poller
   runs the plan and implement rungs (S1, W2). Amendment round 1 and
   the plan are DONE: PR #395 by hand (`8b499ed`), plan PR #398 by
   Themis 18:52:55Z as `e9c987b`. Both the plan and the implement rung
   were launched by hand, the plan because #397 withheld its ledger
   row and the implement because the serial poller was busy. Amendment
   round 2 is still owed.
7. #337 implement (Y4), so the next fix round is fired by the poller.
   DONE, `status:in-review`.
8. #353 implement (Y5). DONE, PR #388 merged by Themis 10:39:54Z as
   `4bdbc48`, with the label advanced by hand (#382). The remaining
   piece is PR #389, the REVIEW.md grammar-line restore plus the owed
   Plan Sync paragraph.
9. #199 implement (P1): `nestor.yaml`, the seat launch, the pin.
10. #259 spec amended for `seat.sh` (P3), then its rungs.
11. #85 and #329 (W1, W3) once S1 is on main.
12. #147 (Y10, P4).
13. #308, #312, #339, #252, #148, #245, #345 as the poller reaches
    them.

Everything else in the tracker is deferred under this scope: #10, #89,
#104, #107, #117, #82, #168, #190, #191, #225, #244, #254, #269, #320
and the older wave rows. None is closed by this file; each stays where
it is until the scope changes.

## Decisions only the operator can make

Each item ends as an issue, a PR, or an explicit "deferred, no
tracker"; the advisor's recommendation is stated where it has one.

- **Home of the seat launch without an issue number.** Under #199's
  plan (recommended: D15 already owns the launch convention) or a new
  issue that #199 and #204 cite.
- **Recorder set.** #324 fold: retire #324 as superseded by #354
  (recommended, #354 is merged) or fold #354 into #324. #331 and #328
  as one intent (recommended). #328 promoted to its own rung ahead of
  the others (recommended, it walls every spec and plan PR). #361
  ratchet N-1: whether the spec is amended for it.
- **Commit identity in poller worktrees (#376).** Either
  `git config extensions.worktreeConfig true` plus a per-worktree
  identity, or `work.sh` and `claim.sh` exporting `GIT_AUTHOR_*` and
  `GIT_COMMITTER_*` from `--as`. Until one lands, every poller commit
  is authored as daedalus.
- **`delete_branch_on_merge=true`** on the repository. Still open; it
  is the fix for the stacked-PR stale-base trap.
- **#353's AT-353-9/10 exit-0 form** against the #308 contract that
  #386 tracks.
- **Duplicate audit note: which spec to amend, #267 D3 or #353 D4
  (#391).** Both are merged and both bind the terminal-failure branch,
  so the ledger renders the withdrawal note twice and no rung can
  repair it under the two contracts as written.
- **PR #369.** The BLOCK stands; do not merge.
- **PR #365.** `hold` is already off (08:11Z) and the verifier is CLEAN; merge it by hand or leave it stalled behind #328. The operator's queue.
- **poll.service restart** to pick up the logging change. DONE
  18:30:06Z, on `poll.sh` at `0b30e64` with the #337 fix and logging
  to `ops/poller/poll.log`.
- **#330 spec amendment round 2.** The instruction file
  `ops/waves/330-spec-amendment-2.md` is machine-local and the round
  is authored from the operator's second machine, which holds the
  recordings the D17 fixtures need.
- **Intake of #382, #383, #386, #390, #391 and #397.**
- **nestor's harness pin** in `config/deployments.yaml` (plan T3 of
  #199). Antigravity is the stated goal; the pin is the operator's
  line to write.
- **#339 authority**: which identity removes labels and posts
  refusals. The workflow token does it today under `issues: write`.
- **Stale processes**: a bare `agy` process 204 hours old, the #265
  REPL in tmux `waves:265i-odyssey` (11 hours), the #350 fix-round
  REPL in `waves:350f-odyssey` (1 hour); the operator kills, never a
  seat.
- **Reopen #321.** Closed by accident at 07:34:52Z by a closing
  reference inside PR #368's body, a sentence listing operator
  decisions, the #245 trap; the advisor note on the issue at 07:42Z
  records it. Its implement is merged and it sat at
  `status:in-review`, so reopen until #148, or leave it closed.
- **#269 and #245** stay deferred under this scope unless the operator
  promotes them.
- **Fast-forward cadence for the primary checkout.** DECIDED
  2026-09-08: the operator never pulls; whoever merges fast-forwards
  the primary with `git pull --ff-only`.
- **Who runs `scripts/ops/worktrees.sh --prune`.** Recommendation
  stands: the operator only, on an announced cadence.

## History

The full status lines of revisions three to nine are in this file's
git history. The facts they carried, compressed:

- **Gate 1 (unattended review on every rung) met 2026-09-08.** Argus
  run 34093599471 on PR #188 (1a); PR #233 (#207 implementation)
  reviewed unattended on its own head (1b); atlas's first real runner
  call on PR #221 after the #167 credential fix.
- **Gate 2 (merge becomes a decision).** #64 implementation PR #257
  merged 2026-09-09 05:35Z as `d61875c` after seven rounds; spec
  amendment r4 named the merge actor's App `Themis`; branch protection
  on `main` from 05:48Z; recorder PR #292 (#267), chain PR #294 (#251),
  flip PR #297 (`loop.autonomous_merge: true`), and #298's fix PR #310
  for the gate's skipped `pull_request` jobs.
- **First autonomous merge** 2026-09-09 19:03:35Z: PR #309 (#291 spec)
  by `evekhm-themis-app`, run 34392659988, all eleven conjuncts true.
  Sixteen autonomous merges that day; the poller went live 21:50Z as
  `poll.service` and claimed #308 twelve seconds later.
- **By-hand merges and why:** PR #327 (held by #331), PR #322, #315,
  #316, #342, #343 (intent-stage PRs, held by #321), PR #344 (held by
  a refused `run-id:0` verdict, #353), PR #346 (#85 spec round 1),
  PR #367 (#354 spec, held by #328), PR #384 and PR #385 (the #353 and
  #361 plans, held by a round-3 `status:review-stuck` escalation that
  D10 cannot self-clear). Every one is recorded on its PR with the
  holding conjunct.
- **Fast path directive 2026-09-08:** merge on smoke, skip review
  rounds. Withdrawn for PR #257 by the verifier on evidence, then the
  ladder ran with both runner reviewers on every head.
- **Lessons carried into PLAYBOOK:** a fork's prose read-only
  instruction is not enforced (#345); an advisor ruling on a thread is
  advisory to the runner reviewers, so its items must become blocking
  review rows or a checklist the reviewers hold, or the gate merges
  the un-amended artifact (PR #352, 2026-09-10); a comment on a PR
  re-runs the gate and the recorder replays every old dispute (#331),
  so clear an escalation, push, and stay silent until the reviews
  land.
