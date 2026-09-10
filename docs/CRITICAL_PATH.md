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

Status line: 2026-09-10, revision fourteen (~20:10 UTC, main at
`019986c`).

Since revision thirteen: Gate S landed its implement rung. Odyssey's
PR #403 opened at 19:15Z and took three review rounds. Round 1 carried
one blocking row (R1-1 at `high`, against D4), and the VM-local poller
fired the fix round itself at 19:24Z; that round also rewrote the
first commit `80ef6a0` into `254c187` to drop a closing-keyword line
naming #330, a message-only change over an identical tree. Rounds 2
and 3 carried zero blocking rows and `review:merge-ready` went on at
~19:58Z. No gate run fired after Atlas's round-3 verdict: the only
run, at 19:57Z, declined on conjunct (2) because the atlas check was
still IN_PROGRESS. The advisor dispatched `merge-gate.yml` by hand at
20:05Z and Themis merged `019986c` at 20:06:06Z. The lifecycle moved
#330 to `status:in-review`, the terminal rung, so no dispatch row was
written, and released the claim; #330 stays open. The harness contract
suite is 21/21 on `main` in a clean shell, and 4 of those tests go red
when `CLAUDE_SEAT` is exported: the suite is not hermetic, and the
class is filed as #405.

Two things are still owed on #330, recorded in issue comment
5624478675. An odyssey fix PR owes the fixtures: the five under
`scripts/ops/tests/fixtures/harness/` are synthesized, and the round
replaces them with the recorded Antigravity payload as fixture 4 and
three Claude fixtures recorded live, drops fixture 5 as unrecorded,
and states provenance in the test header. Spec amendment round 2 by
athena owes the D12 normalization sentence, AT-2 provenance, the D17
directory and the AT-14 header rule. Argus's R3-1 and R3-2 (the D12
delta untested; the normalization rule in code and in the plan but in
no spec) are those same two items seen from the review side.

New intent, filed by the verifier as #405 (`intent:new`): nothing
proves a test suite's verdict comes from the code under test. It
references #330, #85, #244, #249 and #355, and names #244 as the first
sighting.

Two more merges since revision thirteen: #85's plan PR #365 merged as
`e4f2bc1` at 19:17Z, after the poller's self-directed fix round
`7045b7f`, and PR #400 (the README handoff paragraph, from a peer
session) merged as `61c7a7f` at 19:27Z.

#308's implement rung is still stalled. The poller refuses it every
cycle with `branch odyssey/308-merge-gate-yml-repository-wide already
exists`, left behind by a dead run whose worktree sits at `e946ce8`
with one unpushed commit. Removing the branch or pushing it is an
operator decision.

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
| Y4 | #337 | The poller only starts rungs; it cannot fire a fix round, so every reviewer finding waits for a human launch. | DONE from the builder side. Plan PR #359 merged autonomously 07:09Z after fix round 1 (`d177366`, closing keyword in the PR body, #245, fired by the seat); the implement rung landed and #337 is `status:in-review`, so the poller can fire a fix round. `poll.service` restarted 18:30:06Z on `poll.sh` at `0b30e64` with logging to `ops/poller/poll.log`; at 18:53Z it fired its first self-directed fix round, on PR #365 for #85 as daedalus (`7045b7f`, merged `e4f2bc1` 19:17Z), and at 19:24Z its second, on PR #403 for #330 as odyssey (`cdc9179`, merged `019986c` 20:06:06Z). Both fix rounds cleared their blocking rows without a human launch |
| Y5 | #353 | Argus wrote `run-id:0` on PR #344; the recorder refused the verdict into audit notes only, and the gate declined on a stale ledger with no visible reason. | DONE. Implement PR #388 merged by Themis 10:39:54Z as `4bdbc48` after Argus and Atlas round 1 on `e4fe14f`; the plan escalation before it was cleared by hand as PR #384 (`4fe132c`). Lifecycle run 34467240566 did not rank it (D17 slug miss, #382), so the seat advanced #353 to `status:in-review` by hand at 10:41Z. The verifier's smoke, live 33 seconds before the merge and carrying no gate weight, was BLOCK on one row: the merged diff deleted REVIEW.md's finding-line grammar bullet, the only statement of the enum `merge_gate.sh:305-309` declines against, with no task, decision or Plan Sync entry; follow-up PR #389 restored it and merged as `db9386e`, on `main` before revision thirteen. Two of the four by-hand merges on 2026-09-10 (PR #344, PR #319) were this defect alone |
| Y6 | #308, #312 | Concurrency group cancels gate and recorder runs across PRs; a stream-interrupted review reports FAILURE after posting. Both make clean heads look blocked. | #308 `status:implementing` (poller), #312 `status:in-review`; PR #362's three gate runs were cancelled by PR #364's on 06:37Z and never re-evaluated until a hand rerun (#308). #308's implement rung is stalled: the poller refuses it every cycle with `branch odyssey/308-merge-gate-yml-repository-wide already exists`, left by a dead run whose worktree sits at `e946ce8` with one unpushed commit; remove the branch or push it (operator decision below). `merge_gate_test.sh` aborts at MG-38 on `main` under the #308 contract, tracked as #386 |
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
| S1 | #330 | `scripts/ops/harness/statusline.sh`, the side-channel file, `session-start.sh`, `install.sh --check` for both harnesses, fixtures. | `status:in-review`, claim released, issue open. Intent merged (PR #343), spec merged (PR #352, `1f57021`) with none of the advisor ruling applied, amendment round 1 merged by hand as PR #395 (`8b499ed`, 18:0xZ), plan PR #398 merged by Themis 18:52:55Z as `e9c987b`. Implement PR #403 (odyssey) opened 19:15Z and took three rounds: round 1 one blocking row (R1-1 at `high`, against D4), the poller fired the fix round itself at 19:24Z and that round rewrote `80ef6a0` into `254c187` to drop a closing-keyword line naming #330 (message only, identical tree), rounds 2 and 3 zero blocking rows, `review:merge-ready` ~19:58Z. No gate run fired on the round-3 verdict (the 19:57Z run declined on conjunct (2), atlas still IN_PROGRESS), so `merge-gate.yml` was dispatched by hand at 20:05Z and Themis merged `019986c` at 20:06:06Z; the terminal rung writes no dispatch row. The contract suite is 21/21 on `main` in a clean shell and 4 red with `CLAUDE_SEAT` exported (#405). Still owed, per issue comment 5624478675: an odyssey fix PR for the fixtures (recorded Antigravity payload as fixture 4, three Claude fixtures recorded live, fixture 5 dropped as unrecorded, provenance in the test header) and spec amendment round 2 by athena (D12 normalization sentence, AT-2 provenance, D17 directory, AT-14 header rule), which are Argus's R3-1 and R3-2 restated; the amendment's instruction file `ops/waves/330-spec-amendment-2.md` is machine-local, authored from the operator's second machine, which holds the recordings |
| S2 | #356 | The remote session's gh writes land as `evekhm-atlas-bot` while its commits are the athena App; a peer deleted its live claim on that evidence. | `intent:new`; fix on the remote machine is the athena App token for gh writes; the ask is a login-versus-persona preflight shared by every launch path |

Exit criterion: the fixture test byte-compares every recorded payload
(two per harness, plus one with `effort.level`) to one expected line,
and `install.sh --check` runs in CI and fails when the two harness
configurations point at different scripts.

## Gate W: wrap and handoff on both harnesses

| # | Issue | Why it is here | State |
|---|-------|----------------|-------|
| W1 | #85 | `scripts/ops/wrap.sh` writes the dated handoff and runs the close-out; the `/wrap` door is Claude Code only by the operator's scope cut of 2026-09-10 (spec D8 on PR #357, per #43 D16: no `.agents/workflows/` twin in v1). An Antigravity seat calls the script from its brief or Stop hook; the agy door is a follow-up intent that D8 must name. | spec round 2 merged 06:24Z (PR #357, Claude Code only per the operator); plan PR #365 merged as `e4f2bc1` at 19:17Z, after the poller fired its first self-directed fix round on it as daedalus at 18:53Z (`7045b7f`). It had been reviewer-stalled since 06:44Z behind #328, with `hold` off from 08:11:06Z and a CLEAN verifier smoke. Next: the implement rung |
| W2 | #330 amendment | Claude Code injects the newest handoff from the `SessionStart` hook; Antigravity has no such hook, so `work.sh` and the seat launcher inject it at dispatch. The merged spec has no Decision for this yet; the amendment round numbers it. | DONE, landed with S1's implement rung as this row predicted. Decided in the advisor ruling on #330 and shipped in PR #403: `scripts/ops/harness/session-start.sh` and `newest-handoff.sh` are on `main` at `019986c`, and the `SessionStart` hook in `.claude/settings.json` points at `session-start.sh` |
| W3 | #329 | The ceiling enforces itself: threshold nudges at 60/70/90 percent from the side-channel file, compaction backstop `autoCompactWindow: 180000`. Consumes S1's file format. | `intent:new`; S1's implement is on `main` as of 20:06:06Z (`019986c`), so its design rung is unblocked |

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
   runs the plan and implement rungs (S1, W2). DONE through implement:
   amendment round 1 as PR #395 by hand (`8b499ed`), plan PR #398 by
   Themis 18:52:55Z as `e9c987b`, implement PR #403 by Themis
   20:06:06Z as `019986c` on a by-hand gate dispatch. Both the plan
   and the implement rung were launched by hand, the plan because #397
   withheld its ledger row and the implement because the serial poller
   was busy. The fixtures fix PR and amendment round 2 are still owed.
7. #337 implement (Y4), so the next fix round is fired by the poller.
   DONE, `status:in-review`, and proven twice the same evening on PR
   #365 and PR #403.
8. #353 implement (Y5). DONE, PR #388 merged by Themis 10:39:54Z as
   `4bdbc48`, with the label advanced by hand (#382). The last piece,
   PR #389 (the REVIEW.md grammar-line restore plus the owed Plan Sync
   paragraph), merged as `db9386e`, so this rung is complete.
9. #199 implement (P1): `nestor.yaml`, the seat launch, the pin.
10. #259 spec amended for `seat.sh` (P3), then its rungs.
11. #85 and #329 (W1, W3) once S1 is on main. S1 merged 20:06:06Z;
    #85's plan is merged (`e4f2bc1`) and its implement rung is next,
    #329's design rung is unblocked.
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
  is authored as daedalus. The committer half needs a maintainer
  ruling of its own: the poller's fix round on PR #403 produced
  `cdc9179` authored by the odyssey App but committed by
  `evekhm-daedalus-app[bot]`, which is R1-8 on that PR
  (`ci-gates.yml` pushed under a substituted credential), and no gate
  conjunct reads the committer.
- **`delete_branch_on_merge=true`** on the repository. Still open; it
  is the fix for the stacked-PR stale-base trap.
- **#353's AT-353-9/10 exit-0 form** against the #308 contract that
  #386 tracks.
- **Duplicate audit note: which spec to amend, #267 D3 or #353 D4
  (#391).** Both are merged and both bind the terminal-failure branch,
  so the ledger renders the withdrawal note twice and no rung can
  repair it under the two contracts as written.
- **PR #369.** The BLOCK stands; do not merge.
- **PR #365.** DONE, merged as `e4f2bc1` at 19:17Z after the poller's
  fix round; `hold` had been off since 08:11Z and the verifier was
  CLEAN.
- **#308's stale implement branch.** `odyssey/308-merge-gate-yml-repository-wide`
  already exists, so the poller refuses the rung every cycle; the dead
  run's worktree sits at `e946ce8` with one unpushed commit. Remove
  the branch or push it.
- **poll.service restart** to pick up the logging change. DONE
  18:30:06Z, on `poll.sh` at `0b30e64` with the #337 fix and logging
  to `ops/poller/poll.log`.
- **#330 spec amendment round 2.** The instruction file
  `ops/waves/330-spec-amendment-2.md` is machine-local and the round
  is authored from the operator's second machine, which holds the
  recordings the D17 fixtures need. The fixtures fix PR (odyssey) is
  owed alongside it, per issue comment 5624478675.
- **Intake of #382, #383, #386, #390, #391, #397 and #405.** #405 is
  the verifier's intent that nothing proves a test suite's verdict
  comes from the code under test, first sighted on #244.
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
