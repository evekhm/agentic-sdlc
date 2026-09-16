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

Status line: 2026-09-16, revision fifteen (~07:35 UTC, main at
`9e19fa1`).

Since revision fourteen, six days passed and the loop dispatched
nothing. This revision is mostly the account of why, and the ordering
that comes out of it.

**The loop was jammed from 2026-09-10 to 2026-09-16.** Poller pid
3847103 started 2026-09-10 18:30 and wrote 40,755 lines to
`ops/poller/poll.log` without dispatching a single rung. About 37,000
of those lines are four refusals repeating every 30 seconds:

| Refusals | Cause |
|---|---|
| 9,645 | `branch odyssey/308-merge-gate-yml-repository-wide already exists` — a stale local branch with zero unique commits; the real work was PR #477 |
| 9,646 | `#329 carries in-progress` — a claim held by dead poller pid `poll-575894` |
| 9,461 | `#415 carries in-progress` — same, another dead pid |
| 9,486 | `first-hop intake concurrency limit reached` |

The fourth is the one that matters, because it is not a stuck branch
or a stuck issue but the design working as written. `poll.sh:357-384`
counts open issues whose last `Claim:` comment was written by
`evekhm-athena-app` and compares that to
`max_concurrent_first_hops`, which is `1`. Twelve of the eighteen
`in-progress` claims were stale, five of them athena's (#415, #405,
#329, #259, #204). **Any single one of those five held first-hop
intake shut for the whole six days.** Nothing in the system releases a
claim when the process holding it dies; that gap is #252 and #148. A
121-issue backlog accumulated for that reason alone. No single defect
in the ladder explains it.

Two structural causes sit underneath the accumulation, and neither is
a bug in a script. First, intake admits an issue only when it carries
BOTH `intent:new` and `intake:auto` (`poll.sh:381`); of 72 `intent:new`
issues, exactly one (#269) carried `intake:auto`, so the front door was
open to one issue in seventy-two. Second, nothing closes a finished
issue: the close rung (#148) was specified and never built, so an issue
whose last rung merged sits at `status:in-review` forever. Most of the
backlog was not unfinished work. It was finished work nobody swept up.

**Full backlog triage, 2026-09-16** — every open issue read against the
tree, written up in `runs/2026-09-16_062144_backlog-triage/triage.md`.
Of 121 open issues, **40 needed no engineering at all**: 27 already
delivered on `main`, 13 duplicates of another issue, 2 epics
misfiled as work. 39 of those were closed the same morning with their
commit citations (the 27th, #410, is corrected below). Open count went
121 → 85; the delta from 82 is #482, #483 and #484, filed that morning.

**PR #477 merged autonomously** at `0d5f0dd`, all eleven conjuncts
true, landing #308's per-PR concurrency fix and retiring the largest
jam. The poller restarted at ~06:58Z and made its first self-directed
dispatch in six days (athena on #415, via PR #421) within ninety
seconds.

**#328 has a working route around it; the defect itself remains.** `deep-review` is in argus's
`assigned_when.labels` (`config/execution.yaml:67`), so labelling a PR
makes argus genuinely assigned and `unattended.yml`'s `labeled`
trigger dispatches it. Applied to PR #480, #475 and #421; on PR #480
the ledger took both `reviewed-head` markers and the gate returned
**conjunct (3) true** for the first time. Argus performs a genuine
review on this path, and no clean head has to wait on #328 any more. Worth
recording for whoever fixes #328: the gate already resolves the
assigned set correctly at `merge_gate.sh:297-303` via
`execution.py --subscribers`; that path is simply unreachable, because
it is guarded on the `assigned:` marker being *absent* and
`review_recorder.py:415` writes it unconditionally. The fix is to make
the recorder call the same resolver in place of the hardcoded string.

**#410 was scored CLOSE-DONE by the triage and that verdict was
wrong.** Branch protection on `main` requires exactly `drift`,
`execution`, `sanitize` and `spec-check`. The `changelog-check` job
exists and runs (`ci-gates.yml:210`), but it is not required, which is
precisely the "merely a red X" the issue says is insufficient — Themis
will merge a PR that skipped its changelog. The flip is one line of
repo config and is deliberately deferred: PR #421, #369 and #423 carry
no `changelog-check` run at all, and #423's fix is a PR-body edit,
which fires no `pull_request` run, so requiring the check now would
strand it permanently. #410 stays open until the flip lands.

**#269 is larger than it reads.** `session_spend.sh:249-262` prices
every Gemini Flash version 1.5 through 3.8 at Gemini 1.5 Flash's rate,
and every pinned tier is `gemini-3.8-flash-*`, so 100% of antigravity
spend this repo has ever reported is roughly 5x low in and 6x low out.
That is not only a reporting error: `config/execution.yaml` gates
dispatch on USD ceilings measured by this same function, so a ceiling
meant to stop a runaway agy loop currently permits about five times the
intended spend. Fixing the rates tightens live ceilings, so runs that
pass today may start being refused. The choice of price basis is an
operator decision, below.

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

#308's implement rung is DONE as of 2026-09-16. The stale branch
`odyssey/308-merge-gate-yml-repository-wide` held zero unique commits
and is gone; the real work was PR #477, which Themis merged at
`0d5f0dd` on all eleven conjuncts. #308 itself stays open at
`status:in-review`, waiting on #148 like every other finished issue.

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

**State correction, 2026-09-16.** The `State` column below was written
on 2026-09-10 and the rows are left as they stood, so the history reads
straight. Live state has moved; `gh issue list` beats both. Closed
since revision fourteen: **#321, #324, #354, #361, #265, #337, #353,
#312, #252, #251, #366, #376, #330, #85** — of which #324 retired as
superseded by #354, and #376 folded into #412. Still open: **#331,
#328, #339, #148, #147, #245, #345, #363, #397**, all `intent:new`, and
**#308** at `status:in-review` with its implement rung merged. The
practical effect on this gate is that Y1, Y3, Y4, Y5, Y8 and the #366
half of Y13 are finished, Y6 is finished on the #308 side, Y14 is
folded elsewhere, and what remains of Gate Y is the recorder pair
(#331, #328), the housekeeping set (#148, #397, #363) and the policy
items (#339, #147, #245, #345).

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

## Gate H: the handover contract holds without a human

Gate Y assumes the handover between rungs works. Six days of poller
logs say it holds only while every dispatch exits cleanly and every
artifact is read by a human. This gate makes the contract carry its
own state, its own liveness and its own visibility. All four rows were
filed on 2026-09-16; they are the three-issue gap between the triage's
projected open count and the measured one. The peer session that
diagnosed them holds PR #485 for the `process.handover` capability.

| # | Issue | Why it is here | State |
|---|-------|----------------|-------|
| H1 | #482 | Dispatch carries no state. The unattended prompt (`scripts/ops/work.sh:637`) names an issue number and nothing else: no stage, no intent folder path, no artifact paths, no prior findings; a fix round hands over a bare PR number (`scripts/placement/vm-local/poll.sh:351`). The agent discovers its own rung by reading, and that discovery is the largest controllable cost in the system. The proposal puts stage, rung number, intent folder path, existing artifacts and reviewer finding IDs into the dispatch, and replaces the grepped `WORK-RESULT:` prose with a structured marker. `scripts/ops/digest.sh` already assembles most of it for the interactive `/work` door. | Filed 2026-09-16T06:30:51Z, `intent:new`. Evidence on the issue: 24 poller runs over six days, 20,193,937 fresh input (841K per run), 191,691,158 cache reads, 1,374,388 output, 751,314 thinking; cache-read ratio min 0.688, median 0.913, mean 0.894, tracking run duration, so the whole cache economy sits inside one rung and the 841K survives no rung boundary |
| H2 | #483 | No contract resource has a liveness check. The `in-progress` label and its `Claim:` comment, the dispatch branch and the worktree can each be held by a process that no longer exists, and nothing reaps any of them, so a crashed dispatch becomes a permanent stop. The poller already implements this pattern for its own local PR lock files (`poll.sh:244-262`, `POLL_LOCK_MAX_AGE=7200`, removes the lock when the recorded PID is dead); none of the three shared resources gets it. This is the same defect the six-day jam ran on, seen from the process side: five athena claims outlived their processes and `max_concurrent_first_hops: 1` counted every one of them. | Filed 2026-09-16T06:30:52Z, `intent:new`. Prior sightings named on the issue: #252, #363, #383, all three still open. One live instance as of 2026-09-16, reported by a peer session and confirmed here with `ps`: pid 1737758, `bash runs/2026-09-10_050016_agy-waves/run-350f.sh`, child agy pid 1737762 holding a FIX ROUND 1 prompt for #321 on PR #350, elapsed 6-02:03:54 and still running. PR #350 merged on 2026-09-10 at 05:33Z, so the prompt has been stale since roughly three minutes after it started. Revision fourteen flagged tmux and agy residue as unverified; this is the confirmed instance. Killing it is an operator decision below |
| H3 | #484 | The machine-readable state every rung reads is stated in bash comments. The loop ledger row schema lives in `scripts/ci/merge_gate.sh:32-44` and is duplicated in `scripts/ci/lifecycle_advance.sh:560-591`; the consensus ledger schema lives in `merge_gate.sh:18-30`. docs/SPEC.md covers the loop behaviourally without stating the grammars, so a third harness has to read bash to implement the contract. PR #485 lands a `process.handover` capability holding the resource table; #484 is the grammars themselves plus drift coverage. | Filed 2026-09-16T06:30:53Z, `intent:new` |
| H4 | #481 | The observability gap. Dispatch stops in well-defined places — `work_dispatch.sh`'s `refused:` circuit breaker, a headless `WORK-RESULT: blocked`, a non-empty "Open questions" section — and every one is prose buried in a diff, a comment or a log line. This is also the home the triage proposed for the ~25 unfiled agent open questions. | Filed 2026-09-16T06:02:55Z, `enhancement,in-progress,status:planning`. Athena's intent landed as PR #487 at 06:47Z: `status:needs-input` label, `ESCALATION: #<n> kind=… stage=…` marker, `/escalations` compiled door. The only Gate H row with a rung under way |

Exit criterion: a dispatch killed mid-run self-heals within a bounded
interval — the claim, the branch and the worktree are released by a
sweeper reading a liveness signal, and the rung relaunches with no
operator touch — and one command shows an operator the whole loop's
live state: every issue waiting on a human decision, the reason, and
the stage it stopped at.

## Order of landing

Revisions ten through fourteen ordered by dependency. Revision fifteen
re-orders by **what stops the loop from running unattended**, because
the six-day jam showed the binding constraint is not the ladder's
capability but its housekeeping: claims that outlive their process,
issues nothing closes, a front door open to one issue in seventy-two.
The 2026-09-16 triage is the evidence; the gates below are its output.

### Gate 3 — the loop stops needing a human

Nothing here is new capability. Each item is a place the loop stalls
silently and waits for a person who does not know they are needed.

1. **#148** — the close rung. It was specified and has never been
   built. Without it every
   finished issue sits at `status:in-review` forever, which is most of
   what the 121-issue backlog actually was. Highest leverage item in
   the file.
2. **#483 (H2), with #252 / #251 re-verified under it** — release a
   claim when its holder dies. #252 and #251 are closed as delivered,
   and the six-day jam happened anyway, so the delivered fix does not
   cover a poller process that dies without unwinding. #483 was filed
   the same morning from the process side and is the live home for
   this; re-verify the delivered fix against it and leave the closed
   issues closed.
3. **#397** — the withheld dispatch row. An artifact PR that merges
   while `in-progress` is held produces no ledger row, and nothing
   re-issues it, so the rung stalls with no marker saying why.
4. **#363** — the poller dispatches from a stale ledger rung and keeps
   the claim when `work.sh` refuses. Same class: a refusal that leaves
   state dirtier than it found it.
5. **#239** — give the review-dispatch refusals the same
   `REVIEW_DISPATCH != 1` guard the fast-track door already has at
   `work.sh:497`. XS, and it removes the review-stuck deadlock.
6. **#386** — `merge_gate_test.sh` red on `main` at MG-38 under the
   #308 contract. #308's implement landed, so re-run before assuming
   this is still true.
7. **#489** — a PR that links more than one issue dies at
   `scripts/ops/lib/github.sh:149-151` with `die` (exit 1), so both
   reviewer checks go red permanently. The zero-issue branch three
   lines below already returns 2, the refusal contract `unattended.yml`
   honours by exiting 0 with a stated reason. #216 fixed the
   zero-issue half and closed; this is the sibling it left behind.
   Filed 2026-09-16 from PR #423, which sat red for six days on it
   because the fix was a body edit and a body edit fires no
   `pull_request` run. An earlier revision of this line said a by-hand
   `workflow_dispatch` clears such a red. That is wrong, and #491 below
   is why. A red required check is the one stall in this loop that no
   agent can clear, which is why it belongs in Gate 3; its diff size
   alone would have put it in the XS batch.
8. **#490** — a Vertex `RESOURCE_EXHAUSTED` (429) costs a reviewer run
   its entire window. Filed 2026-09-16 from PR #480's atlas job. The
   retry loop does exist, and the first reading of this issue said
   otherwise: PR #480's tail reads `attempt 1` while PR #458's reads
   `attempt 6`, so `agy` retries. The defect is that the loop has no
   terminal state of its own. It runs until `--print-timeout 30m` ends
   it, so the attempt count it reaches is arbitrary and a saturated
   quota always bills the full window before anything downstream learns
   the turn was refused. A measured cohort, all `atlas` on
   gemini-3.8-flash-high, all launched inside six minutes on
   2026-09-16:

   | run | PR | attempt at failure | duration | input | cache read |
   |---|---|---|---|---|---|
   | 35064689660 | #480 | 1 | 1762s | 421,032 | 537,465 |
   | 35064696473 | #421 | 2 | 1762s | 445,970 | 602,644 |
   | 35065046628 | #458 | 6 | 1791s | 645,403 | 1,373,400 |
   | 35065153132 | #486 | 1 | 1358s | 248,680 | 314,445 |

   1,761,085 fresh input and 2,827,954 cache read for four empty
   responses, four permanently red required checks and about 100
   minutes of runner time. The fix is a terminal state: give up after a
   bounded number of attempts and exit distinctly enough that the layer
   above can tell a quota refusal from a review verdict. Distinct from
   #312, which is a *completed* review whose stream was interrupted;
   here the API refused the turn and no work exists. Same consequence
   as #489 — the check goes red for a reason that carries no opinion
   about the PR, and today only a human clears it. Feeder for #481's
   escalation queue and a candidate for #483's sweeper.

   The quota refuses **intermittently**, which matters more than the
   raw failure count. `argus` succeeded throughout the same window and
   an `atlas` run at 07:03 (35066601100, PR #485) succeeded, so any
   release condition phrased as "one round came back clean" can pass on
   luck while the underlying condition is unchanged.
9. **#491** — the gate's conjunct (2) reads a stale reviewer check
   context that a by-hand re-dispatch can never replace, so #489 and
   #490 have no by-hand escape hatch. Filed 2026-09-16 while verifying
   a peer session's unrelated claim about conjunct (2). Gate run
   35068510323 on PR #423 at head `9cacb10` prints two lines that
   contradict each other:

   ```
   conjunct (2): false — mergeStateStatus CLEAN but check(s) not success: argus via gh-actions=FAILURE atlas via gh-actions=FAILURE
   conjunct (11): true — ledger carries reviewed-head:argus and the head probe read 9cacb109...
   ```

   (11) is right. The commit's REST check-run list carries
   `103073609411 argus via gh-actions failure` from Sep 10 alongside
   `104698079394 argus via gh-actions success` from the re-dispatch that
   morning. The GraphQL `statusCheckRollup` the gate reads at
   `merge_gate.sh:263` returns 15 of the 22 check runs on that SHA, and
   for each reviewer name it returns one context — the Sep-10 failure.
   The success never enters `CHECKS_TSV`, so the dedupe-by-highest-
   `databaseId` at `merge_gate.sh:492-516` has nothing to act on. Both
   `workflow_dispatch` suites report `pull_requests` length 1 on the
   PR's own branch, so the link is sound and the omission is per
   check-run name; contexts from those same suites do appear in the
   rollup under other names. The consequence is the reason this sits in
   Gate 3: **a re-dispatch clears conjuncts (3), (4) and (11) and can
   never clear (2)**, so the documented unstick recipe cannot finish the
   job, and only a push or a `synchronize` replaces the context. GitHub's
   own `mergeStateStatus` on #423 reads CLEAN, so conjunct (2)'s rollup
   half is stricter than the branch protection it mirrors. #298 built
   that dedupe and the SKIPPED allowlist; this is the case the machinery
   cannot reach. Land it before #489 and #490, because it is what makes
   their fixes verifiable without an operator.

   The rollup returns the **oldest** run for a reviewer name, and three
   successive green dispatches across two names all failed to enter it
   (`104696161088` argus 06:55:52Z, `104696335134` atlas 06:56:22Z,
   `104698079394` argus 07:08:01Z). That rules out a race or one unlucky
   suite. **#491 and #490 compound**: #490 turns a reviewer check red
   for an infrastructure reason, #491 makes that red unclearable by the
   loop, and neither alone strands a PR permanently. PR #480 and PR #458
   both took a 429 within about ninety seconds of each other on
   2026-09-16 and both now hold an `atlas via gh-actions=FAILURE` that
   no dispatch can replace. An empty commit on each branch is the only
   mechanic, and it is an operator decision.

   A second conjunct (2) hypothesis was tested and dropped. A CANCELLED
   context that is newest for its name would count as failing under the
   allowlist at `merge_gate.sh:513`, and the concurrency group looked
   like a way to produce one. It is not: the evicted run 35066559069 on
   PR #423 reports `completed/cancelled` with an empty `jobs` array, so
   a run evicted while queued starts nothing and registers no check
   context. The 22 check runs on `9cacb10` are 19 success, 2 failure, 1
   skipped and 1 in progress, with no cancelled among them. Reaching
   that state needs a run whose jobs start and are then cancelled by
   hand or by timeout; until someone produces one it stays out of this
   list.

### Gate 4 — the fast-track batch

Roughly eighteen XS fixes, one `/fast` PR each, batched by theme so a
reviewer reads one coherent diff in place of eighteen unrelated ones.
The identity-and-slug theme runs first because it is self-contained and
several other issues fold into it: **#224 → #227 → #236 → #463 → #203
→ #465b**.

**This gate is held as of 2026-09-16, and the reason belongs in the
plan.** Model quota is the binding constraint on the day; agent time
is free by comparison. #490 records a reviewer run that took a Vertex 429 on turn one,
never retried, burned its full 30-minute window and billed roughly
960K tokens for an empty response. Eighteen fast-track rounds each
carry two reviewer dispatches, so opening the batch into a quota that
is already refusing turns converts a scheduling decision into a wave
of red checks that only a human can clear, which is exactly the class
#489 and #490 describe. Two conditions release the gate. The second is
phrased against the loop's behaviour, because the quota refuses
intermittently and any condition satisfied by a single clean round can
be met by luck: **(a)** #490's terminal state lands,
so a quota refusal ends in bounded time and reports itself as a
refusal; **(b)** an infrastructure-red check is re-runnable by the loop
itself, with no operator in the path. (b) now has a named blocker:
**#491**, which proves that a re-dispatched reviewer check stays red at
the gate no matter how it finishes. Until #491 lands, (b) is
unreachable by construction, so this is the single change that opens
Gate 4. #481 and #483 build the queue and the sweeper on top of it, and
until all three hold, every red check this batch produces is a
human-only stall however few of them there are. Sequencing note for whoever
opens it — #227 and #489
touch the same resolver in `scripts/ops/lib/github.sh`, so they are one
diff or two strictly ordered ones, and #463 already carries a live
`status:planning` rung, so it stays on the ladder and out of this
batch.

### Gate 5 — the real work

Everything that needs a spec: #355, #82, #405, #417, #479,
#104/#108/#190, #356, #318, #11, #117, #481, #482, #484. Ordered inside
the gate by whichever unblocks another item. Size does not set the
order here. #481, #482 and #484 are Gate H rows H4, H1 and H3; H1 pays
for itself in cache economy the moment it lands, so run it early in
this gate.

Two cautions carried from the triage, both of which would cost a wasted
round if missed:

- **#356's proposed preflight cannot work as written.** It suggests
  `gh api user` to assert the acting identity, which returns 403 for a
  GitHub App token (`smoke_launch.sh:43,641`). The preflight has to
  resolve the App slug instead.
- **`personas/nestor.yaml` does not exist**, so nothing under #199 can
  land until it does. #199 is now an epic; the child that creates the
  file is the one that unblocks the rest.

### Superseded ordering (revisions ten to fourteen)

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

Opened by the 2026-09-16 triage, newest first:

- **#269: which price basis `rate_tier()` encodes.** Either the Gemini
  Developer API list price (3.8 Flash \$0.75/\$3.75, 3.1 Pro
  \$2.00/\$12.00, already in the issue) or the real Vertex/Enterprise
  rate. The Vertex pricing page renders its tables client-side and
  returns no table body to an unauthenticated fetch — tried twice, on
  2026-09-08 and again on 2026-09-16, same result — so only a
  signed-in console read settles it. Recommended: land the list price
  now with the source and date written above the table, and treat the
  Vertex reconciliation as a follow-up. A number that is 5x low is a
  worse failure than a number that is right for the wrong price book.
  Secondary, unanswered either way: Gemini's cache multipliers. The
  write-5m/write-1h/cache-read columns currently apply Claude's
  1.25x/2x/0.1x to the Gemini base, which nobody has verified.
- **When to make `changelog-check` a required context (#410).**
  Recommended: immediately after PR #421, #369 and #423 are resolved.
  Doing it sooner strands #423, whose fix fires no `pull_request` run.
- **Whether the #252/#251 claim release actually covers a dead poller
  process.** Both issues are closed as delivered and the jam happened
  regardless. If the gap is real it wants a new issue; the delivered
  behaviour is correct and simply narrower than the failure it met.
- **103 stale git worktrees** are on the VM. Cleanup is not proposed
  here; it is noted so the number is not a surprise later.
- **PR #369 must not merge in its current state.** Its
  `intent/329-context-ceiling/spec.md` is truncated at line 170 inside
  an unterminated heredoc; the verifier returned BLOCK with two `high`
  rows, and **those rows were never written to the ledger**, which
  holds only `AT-R1-1@D2:normal:open`. Conjunct (4) therefore reads
  true, so clearing (3) and (11) would merge a truncated spec. #329
  carries `hold` for this reason, which the poller honours
  (`poll.sh:300`). Athena owes a full redraft. The ledger-versus-verdict
  divergence is itself a recorder defect and belongs with #328.

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
  REPL in `waves:350f-odyssey`; the kill is the operator's call alone.
  Updated 2026-09-16: the #350 row is still alive and `ps` puts it at
  elapsed 6-02:03:54 — pid 1737758 running
  `runs/2026-09-10_050016_agy-waves/run-350f.sh` with child agy pid
  1737762 on a FIX ROUND 1 prompt for #321. PR #350 merged at 05:33Z
  on 2026-09-10, three minutes after that prompt started, so nothing
  it does can land. It is the verified instance of the class #483 (H2)
  describes, and no agent will reap it, because reaping is exactly the
  behaviour #483 asks for. agy launches carry no per-token cost here,
  so the harm is a held slot and a confused timeline. Recommended:
  kill both pids now and let #483 make it automatic.
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
