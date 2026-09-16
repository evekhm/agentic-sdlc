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

Status line: 2026-09-16, revision fifteen (main at `05619e2`).

Since revision fourteen: six days, 60 merge commits and 31 merged PRs
carried `main` from `019986c` to `05619e2`. The tracker holds 124 open
issues and 8 open PRs.

What landed, by ladder: #410 (CHANGELOG.md with a hard CI merge gate)
walked all four rungs, PR #414, #419, #426 and #427. #416 (slash
commands compiled cross-harness from canonical sources in `commands/`)
walked all four, PR #420, #422, #442 and #473. #404 (Athena as the
front door) walked all four, PR #429, #432, #435 and #440, and closed
2026-09-11T17:07:13Z. #425 (invalid YAML frontmatter in
`.claude/commands/`) walked all four and closed 2026-09-11T06:27:04Z.
Gate W's #85 landed its implement rung: PR #406 merged
2026-09-10T23:55:54Z after three rounds. The operator's own doors
landed too: #444's `/fast` (PR #447), #441's `/work` plumbing (PR
#462), #459's `claim.sh` stage label (PR #460), #466's identity
plumbing (PR #468), #470's open-questions surfacing (PR #471), #407's
intake doors (PR #409), and the prose-style ban in AGENTS.md (PR
#450). #372 (native Issue Dependencies replacing prose-parsed
`depends on`) has its intent (PR #472) and spec (PR #476) on `main`.
Two Gate Y rows closed: #337 at 2026-09-15T22:07:43Z and #354 at
2026-09-15T22:10:45Z.

`poll.service` stayed up the whole interval: `enabled`,
`Restart=always`, active since 2026-09-10 18:30:06 UTC, PID 3847103.
It completed 24 dispatched runs, all Antigravity, for 20,193,937 fresh
input tokens (841K per run), 191,691,158 cache reads, 1,374,388 output
and 751,314 thinking, at a cache-read ratio of min 0.688, median
0.913, mean 0.894, about $37.50 at Flash rates. The 841K per run is
the cost lever now filed as #482.

For those same six days the poller also refused three rows on every
30-second tick: the residue branch
`odyssey/308-merge-gate-yml-repository-wide` (0 unique commits vs
main) and dead `in-progress` claims on #415 (claimed
2026-09-10T22:10:43Z) and #329 (claimed 2026-09-10T07:00:22Z). All
three were cleared by hand on 2026-09-16, the branch deleted and both
claims released; the loop resumed with no code change. That reaping
gap is now filed as #483.

#328 has been the wall for every spec and plan PR for the whole
interval. PR #369 (#329 spec) and PR #421 (#415 spec) are OPEN, CLEAN
and `consensus:agreed`, untouched since 2026-09-10. A merge-gate
dispatch on 2026-09-16 06:24Z declined both on `conjunct (3): false —
argus verdict is at none` and `conjunct (11): false — the ledger
carries no reviewed-head marker`, which is #328 exactly: the recorder
hardcodes the assigned reviewer set, so #265's Atlas-alone branch is
unreachable. PR #369 also carries a verifier BLOCK from 2026-09-10:
`intent/329-context-ceiling/spec.md` is truncated mid-heredoc at line
170.

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
| Y1 | #321 | Conjuncts 9 and 10 read a ranked status label; `intent:new` issues carry none, so every intent-stage PR needs a by-hand merge (PR #342 and #343 today). | DONE. Live 2026-09-16: #321 is CLOSED (2026-09-10T07:34:52Z), last label `status:in-review`. Intent-stage PRs have merged autonomously ever since; the intent rungs of #410, #416, #404, #425, #467 and #372 all landed in this interval |
| Y2 | #331, #324, #328, #354, #361 | The consensus recorder. #331: a dispute flag is write-once, so every gate run replays it and re-escalates the issue (PR #327 needed a by-hand merge; PR #319 was re-labelled `status:review-stuck` 40 seconds after a hand clear, twice today, because a fix report comment re-ran the gate). #324: a `high` row is demoted when its failure-scenario sibling omits the `@Dn` anchor. #328: the assigned reviewer set is hardcoded, so #265's split gate branch is unreachable. #354: the demotion is conditional on the sibling marker dropping the `@Dn` suffix (Argus's habit), the same fragments #324 cites; PR #349 merged on three demoted rows. #361: the recorder never updates the severity of a finding ID it has already seen, so a corrected or retiered row stays as first written. | Live 2026-09-16: #354 DONE, CLOSED 2026-09-15T22:10:45Z, last label `status:in-review`. #361 open at `status:in-review` (implement PR #387 merged); its ratchet N-1 spec amendment is an operator decision below. #331, #324 and #328 all still `intent:new`, six days with no rung. #328 is the wall: the merge-gate dispatch of 2026-09-16 06:24Z declined PR #369 and PR #421 on `conjunct (3): false — argus verdict is at none` and `conjunct (11): false — the ledger carries no reviewed-head marker`. A sibling recorder issue joined the set: #318 (unanchored verdict markers, quoted prose poisoned a real ledger on PR #316) is `in-progress,status:planning` with intent PR #475 OPEN CLEAN `consensus:agreed`. #390 (recorder observability residue from #361) is `intent:new`. Advisor recommendation stands: retire #324 as superseded by #354; promote #328 ahead of #331 as its own rung |
| Y3 | #265 | The review split: Atlas on every PR, Argus at the code gate, `deep-review` as a one-shot grant. Cuts review spend per round. | Live 2026-09-16: #265 open at `status:in-review`; implement PR #319 merged 2026-09-10 as `b3f86aa`. The Atlas-alone branch it created is still unreachable in the recorder, which is #328. Rounds 1-7 normal and suggestion rows have no follow-up issue yet |
| Y4 | #337 | The poller only starts rungs; it cannot fire a fix round, so every reviewer finding waits for a human launch. | DONE. Live 2026-09-16: #337 is CLOSED (2026-09-15T22:07:43Z), last label `status:in-review`. `poll.service` has been `enabled`, `Restart=always` and active since 2026-09-10 18:30:06 UTC (PID 3847103) and completed 24 dispatched runs in the interval |
| Y5 | #353 | Argus wrote `run-id:0` on PR #344; the recorder refused the verdict into audit notes only, and the gate declined on a stale ledger with no visible reason. | DONE from the builder side; implement PR #388 merged 2026-09-10 as `4bdbc48` and the REVIEW.md restore PR #389 as `db9386e`. Live 2026-09-16: #353 is open at `in-progress,status:in-review` — the claim is still held six days after the merge, the #252 class. Its AT-353-9/10 exit-0 form against the #308 contract (#386) is still an operator decision below |
| Y6 | #308, #312 | Concurrency group cancels gate and recorder runs across PRs; a stream-interrupted review reports FAILURE after posting. Both make clean heads look blocked. | Live 2026-09-16: #308 open at `status:implementing`, #312 open at `status:in-review`. The stale branch that refused #308's rung on every tick for six days was deleted by hand on 2026-09-16; the rung relaunched and implement PR #477 (`odyssey/308-merge-gate-yml`, per-pull-request concurrency for the merge gate) is OPEN, CLEAN, `consensus:agreed` and `review:merge-ready` with `deep-review`. `merge_gate_test.sh` aborting at MG-38 under the #308 contract is #386, still `intent:new` |
| Y7 | #339 | Who may remove a label or post a refusal. Today the workflow token does it; the persona layer has no verb. Draft guard in `post.sh` belongs here (Argus, PR #319 round 4). | `intent:new` as of 2026-09-16, no rung in six days. The adjacent #467 (authority boundary on issue writes) was filed, specced and closed as designed on 2026-09-15 (PR #469, PR #474), so the label-and-refusal authority question stays with #339 alone |
| Y8 | #252, #251 | The advancer never releases the finished rung's `in-progress`; the chain's checklist. | Live 2026-09-16: #252 `bug`, #251 `in-progress,status:in-review`. #252 is now named as the first of three prior sightings in #483, the liveness class in Gate H |
| Y9 | #148 | Deterministic close after the last rung merges; the last by-hand step of a clean run. | `intent:new` as of 2026-09-16. Its cost is visible in the table above: #265, #312, #330, #337, #353, #361 and #407 all sit at `status:in-review` with their implement rungs merged |
| Y10 | #147 | `mode:autonomous` and per-issue `pin:`/`tier:` labels resolved in `work.sh`. The switch, and the home of the harness override that gate P needs. | `intent:new` as of 2026-09-16, no rung in six days |
| Y11 | #245 | The closing-keyword check misses commit bodies; a "Closes" in a non-final rung closed #308 and #312 one rung early. | `intent:new` as of 2026-09-16, no rung in six days |
| Y12 | #345 | A fork ignored a prose read-only instruction and launched live work under this seat's name; no tool-level enforcement exists. | `intent:new` as of 2026-09-16, no rung in six days |
| Y13 | #363, #366 | The poller's own bookkeeping: #363 dispatches from a stale ledger rung and keeps the claim when `work.sh` refuses; #366 writes `stage: implement` in every claim comment because nothing sets `CLAIM_STAGE`. | both `intent:new` as of 2026-09-16. #363 is the second of the three prior sightings #483 names; the six-day stall on #415 and #329 is that defect held for six days |
| Y14 | #376 | `extensions.worktreeConfig` is unset, so `git config --local` in a linked worktree writes the primary's shared `.git/config`, which holds the daedalus App identity; `work.sh` sets no author identity. Every persona commit from a poller worktree is authored as daedalus, so the timeline attributes autonomous work to the wrong persona. | Live 2026-09-16: #376 `intent:new`, no rung in six days; the fix is still an operator decision below. Two neighbours in the same class did land: #413 (persona commit identity leaking through the shared `.git/config`) closed 2026-09-10T20:22:46Z, and #466 (guided `/work` claiming and posting under the wrong identity) closed 2026-09-15T22:05:39Z on PR #468, which also specced `ops.dispatch` so a claim posts as the stage-owning persona |
| Y15 | #397 | The lifecycle advancer withholds the dispatch ledger row when `in-progress` is held at the moment an artifact PR merges, and nothing re-issues the row once the hold clears. The rung has no ledger row for the poller to claim, so the issue stalls with no marker saying why. | `intent:new` as of 2026-09-16, no rung in six days. Filed 2026-09-10 after #330 sat at `status:build` from 05:04Z to 18:25Z on this defect with its plan rung launched by hand |

Exit criterion: one issue, poller-driven from `intent:new`, with a fix
round fired by #337 and a dispute resolved by the recorder, merged by
Themis at every rung and closed by #148, and the issue timeline shows
no human actor.

## Gate H: the handover contract holds without a human

Gate Y assumes the handover between rungs works. Six days of poller
logs say it holds only while every dispatch exits cleanly and every
artifact is read by a human. Three dead resources stopped the loop
from 2026-09-10 to 2026-09-16 and an operator cleared them by hand;
the twenty-four runs that did complete each paid 841K fresh input
tokens rediscovering a job the contract already knows. This gate makes
the contract carry its own state, its own liveness and its own
visibility. All four rows were filed on 2026-09-16.

| # | Issue | Why it is here | State |
|---|-------|----------------|-------|
| H1 | #482 | Dispatch carries no state. The unattended prompt (`scripts/ops/work.sh:637`) names an issue number and nothing else: no stage, no intent folder path, no artifact paths, no prior findings; a fix round hands over a bare PR number (`scripts/placement/vm-local/poll.sh:351`). The agent discovers its own rung by reading the issue, the labels, the ledger, the folder and every comment, and that discovery is the largest controllable cost in the system. The proposal puts stage, rung number, intent folder path, existing artifacts and reviewer finding IDs into the dispatch, and replaces the grepped `WORK-RESULT:` prose with a structured marker. `scripts/ops/digest.sh` already assembles most of it for the interactive `/work` door. | Filed 2026-09-16T06:30:51Z, `intent:new`. Evidence on the issue: 24 poller runs over six days, 20,193,937 fresh input (841K per run), 191,691,158 cache reads, 1,374,388 output, 751,314 thinking; cache-read ratio min 0.688, median 0.913, mean 0.894, tracking run duration, so the whole cache economy sits inside one rung and the 841K survives no rung boundary |
| H2 | #483 | No contract resource has a liveness check. The `in-progress` label and its `Claim:` comment, the dispatch branch and the worktree can each be held by a process that no longer exists, and nothing reaps any of them, so a crashed dispatch becomes a permanent stop. The poller already implements this pattern for its own local PR lock files (`scripts/placement/vm-local/poll.sh:244-262`, `POLL_LOCK_MAX_AGE=7200`, removes the lock when the recorded PID is dead); none of the three shared resources gets it. | Filed 2026-09-16T06:30:52Z, `intent:new`. Evidence: `poll.service` refused the same three rows on every 30-second tick for six days — the `odyssey/308-merge-gate-yml-repository-wide` branch at 0 unique commits vs main, #415's claim from 2026-09-10T22:10:43Z and #329's from 2026-09-10T07:00:22Z — while PR #421 and PR #369 sat OPEN, CLEAN and `consensus:agreed` the whole time. Cleared by hand 2026-09-16 and the loop resumed with no code change. Prior sightings named on the issue: #252, #363, #383, all three still open |
| H3 | #484 | The machine-readable state every rung reads is stated in bash comments. The loop ledger row schema lives in `scripts/ci/merge_gate.sh:32-44` and is duplicated in `scripts/ci/lifecycle_advance.sh:560-591`; the consensus ledger schema lives in `scripts/ci/merge_gate.sh:18-30`. docs/SPEC.md covers the loop behaviourally without stating the grammars, so a third harness has to read bash to implement the contract. The ask is a `contract.handover` capability in docs/SPEC.md carrying the whole table, with the scripts citing it and the drift check covering the grammar. | Filed 2026-09-16T06:30:53Z, `intent:new` |
| H4 | #481 | The observability gap. Dispatch already stops in well-defined places — `work_dispatch.sh`'s `refused:` circuit breaker, a headless `WORK-RESULT: blocked`, a non-empty "Open questions" section — and every one of them is prose buried in a diff, a comment or a log line. An operator who lets a batch run unattended has no single place to see what waits on a human. The ask is a `status:needs-input` label in the circuit-breaker family, an `ESCALATION: #<n> kind=… stage=…` marker in the handoff comment, an `/escalations` command compiled from `commands/` alongside `/work`, `/idea` and `/bug`, and a one-time alignment sweep over escalation states that predate the design. | Filed 2026-09-16T06:02:55Z, `enhancement,in-progress,status:planning` — the only Gate H row with a rung under way |

Exit criterion: a dispatch killed mid-run self-heals within a bounded
interval — the claim, the branch and the worktree are released by a
sweeper reading a liveness signal, and the rung relaunches with no
operator touch — and one command shows an operator the whole loop's
live state: every issue waiting on a human decision, the reason, and
the stage it stopped at.

## Gate S: one statusline on both harnesses (#330)

| # | Issue | Why it is here | State |
|---|-------|----------------|-------|
| S1 | #330 | `scripts/ops/harness/statusline.sh`, the side-channel file, `session-start.sh`, `install.sh --check` for both harnesses, fixtures. | Live 2026-09-16: #330 open at `status:in-review`, unchanged for six days. All four rungs are on `main` — intent PR #343, spec PR #352, amendment round 1 PR #395, plan PR #398, implement PR #403 merged 2026-09-10T20:06:06Z as `019986c`. Both owed items are still owed: no PR has touched `scripts/ops/tests/fixtures/harness/` since the #330 plan commit `75783d0`, and no `330` branch has opened since PR #403, so the fixtures fix PR (recorded Antigravity payload as fixture 4, three Claude fixtures recorded live, fixture 5 dropped as unrecorded, provenance in the test header) and spec amendment round 2 (D12 normalization sentence, AT-2 provenance, D17 directory, AT-14 header rule) both remain open, per issue comment 5624478675. The amendment's instruction file `ops/waves/330-spec-amendment-2.md` is machine-local on the operator's second machine, which holds the recordings |
| S2 | #356 | The remote session's gh writes land as `evekhm-atlas-bot` while its commits are the athena App; a peer deleted its live claim on that evidence. | `intent:new` as of 2026-09-16, no rung in six days. The fix on the remote machine is the athena App token for gh writes; the ask is a login-versus-persona preflight shared by every launch path. The local half of the same class closed on 2026-09-15 as #466 (PR #468), which makes a guided `/work` claim post as the stage-owning persona |

Exit criterion: the fixture test byte-compares every recorded payload
(two per harness, plus one with `effort.level`) to one expected line,
and `install.sh --check` runs in CI and fails when the two harness
configurations point at different scripts.

## Gate W: wrap and handoff on both harnesses

| # | Issue | Why it is here | State |
|---|-------|----------------|-------|
| W1 | #85 | `scripts/ops/wrap.sh` writes the dated handoff and runs the close-out; the `/wrap` door is Claude Code only by the operator's scope cut of 2026-09-10 (spec D8 on PR #357, per #43 D16: no `.agents/workflows/` twin in v1). An Antigravity seat calls the script from its brief or Stop hook; the agy door is a follow-up intent that D8 must name. | DONE from the builder side. Live 2026-09-16: #85 open at `in-progress,status:in-review`; the implement rung landed as PR #406, merged 2026-09-10T23:55:54Z after three review rounds with `consensus:agreed` and `review:merge-ready`. The claim has been held six days past that merge, the #252 class. The agy door for `/wrap` is still the follow-up intent D8 must name, unfiled as of 2026-09-16 |
| W2 | #330 amendment | Claude Code injects the newest handoff from the `SessionStart` hook; Antigravity has no such hook, so `work.sh` and the seat launcher inject it at dispatch. The merged spec has no Decision for this yet; the amendment round numbers it. | DONE, landed with S1's implement rung as this row predicted. Decided in the advisor ruling on #330 and shipped in PR #403: `scripts/ops/harness/session-start.sh` and `newest-handoff.sh` are on `main` at `019986c`, and the `SessionStart` hook in `.claude/settings.json` points at `session-start.sh` |
| W3 | #329 | The ceiling enforces itself: threshold nudges at 60/70/90 percent from the side-channel file, compaction backstop `autoCompactWindow: 180000`. Consumes S1's file format. | Live 2026-09-16: #329 open at `hold,status:spec`. Its intent merged as PR #362 on 2026-09-10. Spec PR #369 has been OPEN, CLEAN and `consensus:agreed` since 2026-09-10 and the merge-gate dispatch of 2026-09-16 06:24Z declined it on conjuncts (3) and (11), which is #328. PR #369 also carries a verifier BLOCK from 2026-09-10: `intent/329-context-ceiling/spec.md` is truncated mid-heredoc at line 170, so the BLOCK stands and a fix round is owed before any merge. The dead claim from 2026-09-10T07:00:22Z was released by hand at 06:23:36Z on 2026-09-16, the poller re-claimed the issue for athena 36 seconds later, and the operator swapped `in-progress` for `hold` at 06:37:31Z with the reason on the issue: merge-gate conjunct (6) honours `hold`, and the truncated spec must not reach the gate while the recorder cluster (#328) can clear conjuncts (3) and (11) under it. The same round exposed a second recorder defect — the verifier's BLOCK with two `high` rows never reached the findings ledger, which holds only `AT-R1-1@D2:normal:open`, so conjunct (4) evaluates true against a spec the verifier blocked; tracked in the #328 cluster |

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
| P1 | #199 | `nestor` as a compiled persona: `personas/nestor.yaml`, the charter as `personas/skills/advisor-session.md`, spec D15's one launch line shared with the verifier, plan T3's pin `nestor: { harness: <OPERATOR-SET> }` in `config/deployments.yaml`. The seat launch without an issue number belongs in this plan (advisor recommendation; operator decision below). | `status:implementing` as of 2026-09-16, unclaimed, no PR, unchanged for six days. `personas/nestor.yaml` is still absent from the repo |
| P2 | #204 | The verifier as the review stage of `argus`; same launch line. | `in-progress,status:build` as of 2026-09-16, no PR; the claim has been held since before revision fourteen, a candidate for #483's sweeper |
| P3 | #259 | Track `launch.sh` and `watch-then-launch.sh`; the spec must name `seat.sh` too, as a `work.sh` form or a sibling that inherits harness, model and handoff injection from it. | `in-progress,status:spec` as of 2026-09-16, no PR; same held-claim pattern as P2 |
| P4 | #147 | The harness override: `--harness <name>` (and `WORK_HARNESS`) resolved at the same point in `work.sh` as the `pin:` label, one mechanism for issue dispatch and seats. Reverses `work.sh` D7, so the spec says so. | `intent:new` as of 2026-09-16. #433 (documenting the `DEPLOYMENTS` environment override) closed 2026-09-11T17:43:31Z on PR #445, which gives the operator a local harness override at the config layer; the per-issue label override in #147 is untouched |
| P5 | #43, #181, #122 | Harness-agnostic launch already merged for issue work (#43 at `status:in-review`); the agy preamble into `GEMINI.md` numbered rules (#181); operational scripts as dual-harness skills (#122). Supporting, none blocking. | Live 2026-09-16: #43 `in-progress,status:in-review`, #181 `intent:new`, #122 `enhancement,status:spec`. #416 shipped the adjacent piece on 2026-09-15: slash commands now compile cross-harness from canonical sources in `commands/` (PR #473, issue closed 2026-09-15T23:15:01Z), with #479 open at `in-progress,status:planning` to bring `wrap`, `claim`, `fast` and `release` into the same compiler and #478 open for the spec amendments that review owed |

Personas in the repo on 2026-09-16 (`personas/*.yaml`): argus, athena,
atlas, cassandra, coder, contract-writer, daedalus, explorer,
mechanic, odyssey, scanner. Bound in `config/deployments.yaml`: argus
and cassandra on claude-code, athena, atlas, daedalus and odyssey on
antigravity. Unbound (Claude-only subagents): coder, contract-writer,
explorer, mechanic, scanner. Missing: `nestor`, six days after
revision fourteen said the same. The verifier is a stage of argus
(#204), so it adds no file.

Exit criterion: one tracked line opens the advisor on the harness
pinned in `config/deployments.yaml`, and the same line with the
override opens it on the other harness; both start from the newest
handoff.

## Order of landing

1. PR #350 merges (Y1). DONE 2026-09-10; #321 closed the same day and
   every intent-stage PR since has merged on its own.
2. #354 and #361 recorder rungs. DONE; #354 closed 2026-09-15T22:10:45Z,
   #361 sits at `status:in-review` with PR #387 merged.
3. PR #319 merges (Y3). DONE 2026-09-10 as `b3f86aa`.
4. #337 implement (Y4), so the poller fires its own fix rounds. DONE;
   #337 closed 2026-09-15T22:07:43Z and `poll.service` has run
   continuously since 2026-09-10 18:30:06 UTC.
5. #353 implement (Y5). DONE; PR #388 merged as `4bdbc48` and the
   REVIEW.md restore PR #389 as `db9386e`.
6. #330 through implement (S1, W2). DONE; PR #403 merged
   2026-09-10T20:06:06Z as `019986c`. The fixtures fix PR and spec
   amendment round 2 are still owed, with no branch opened for either.
7. #85 implement (W1). DONE; PR #406 merged 2026-09-10T23:55:54Z after
   three review rounds.
8. **#328 as its own rung.** This is the next thing that must land and
   the only reason the two oldest spec PRs are still open. Until the
   recorder writes the dispatched reviewer set, the gate's Atlas-alone
   branch stays unreachable and every spec and plan PR needs a by-hand
   merge with the holding conjunct named on the PR. The set to walk
   with it: #331, #324 (retire as superseded by #354), #318 (intent PR
   #475 open), #390.
9. **Gate H, H2 first (#483).** A sweeper that reaps a dead claim, a
   dead branch and a dead worktree turns the six-day stall class into
   a bounded one. #252, #363 and #383 fold into it.
10. **Gate H, H1 (#482).** State-carrying dispatch, the 841K-per-run
    cost lever. H3 (#484) states the schemas the dispatch would carry,
    so it walks alongside.
11. **Gate H, H4 (#481).** Already at `status:planning`; it makes the
    remaining stalls visible from one command.
12. #369 fix round: the truncated `spec.md` heredoc at line 170 clears
    the verifier BLOCK, then #329's spec merges once #328 lands (W3).
    #421 (#415 spec) merges on #328 alone.
13. PR #477 merges (#308, Y6) — it is CLEAN, `consensus:agreed` and
    `review:merge-ready` today.
14. #148 (Y9). Seven issues sit at `status:in-review` with their
    implement rungs merged, so the close rung is now the largest
    standing pile of human writes.
15. #199 implement (P1): `nestor.yaml`, the seat launch, the pin.
16. #259 spec amended for `seat.sh` (P3), then its rungs.
17. #147 (Y10, P4).
18. #312, #339, #245, #345, #376, #397, #382, #386, #391 as the poller
    reaches them.

Everything else in the tracker is deferred under this scope: #10, #89,
#104, #107, #117, #82, #168, #190, #191, #225, #244, #254, #269, #320
and the older wave rows. None is closed by this file; each stays where
it is until the scope changes. The tracker held 124 open issues and 8
open PRs on 2026-09-16, so the deferred set is now much larger than
the named rows above; the operator's scope directive is what keeps it
off the path.

## Decisions only the operator can make

Each item ends as an issue, a PR, or an explicit "deferred, no
tracker"; the advisor's recommendation is stated where it has one.

- **Home of the seat launch without an issue number.** Under #199's
  plan (recommended: D15 already owns the launch convention) or a new
  issue that #199 and #204 cite.
- **Recorder set.** #324 fold: retire #324 as superseded by #354
  (recommended, #354 closed 2026-09-15). #331 and #328 as one intent
  (recommended). #328 promoted to its own rung ahead of the others
  (recommended, and now with six days of evidence: it declined PR #369
  and PR #421 again on 2026-09-16 06:24Z). #318's intent PR #475 is
  open and belongs in the same set, with #390. #361 ratchet N-1:
  whether the spec is amended for it. This whole item has carried
  forward unresolved since revision fourteen.
- **Gate H ordering.** Whether #483's reaping sweeper is promoted
  ahead of #328. Recommendation: yes. #328 costs a by-hand merge per
  spec PR; #483 cost six idle days across #415, #329 and #308 with no
  signal that anything was wrong.
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
- **`delete_branch_on_merge=true`** on the repository. Still open:
  `gh api repos/evekhm/agentic-sdlc` returns
  `delete_branch_on_merge=false` on 2026-09-16. It is the fix for the
  stacked-PR stale-base trap and it is half the fix for #483's
  surviving dispatch branches (#383).
- **#353's AT-353-9/10 exit-0 form** against the #308 contract that
  #386 tracks.
- **Duplicate audit note: which spec to amend, #267 D3 or #353 D4
  (#391).** Both are merged and both bind the terminal-failure branch,
  so the ledger renders the withdrawal note twice and no rung can
  repair it under the two contracts as written.
- **PR #369.** The BLOCK stands; do not merge. Confirmed open and
  untouched on 2026-09-16: `intent/329-context-ceiling/spec.md` is
  still truncated mid-heredoc at line 170, so a fix round is owed
  before #328 even matters for this PR.
- **PR #421 (#415 spec).** OPEN, CLEAN, `consensus:agreed`, untouched
  since 2026-09-10, declined by the 2026-09-16 06:24Z gate dispatch on
  #328 alone. A by-hand merge citing conjuncts (3) and (11) is
  available today.
- **PR #365 and PR #406 (#85).** DONE. The plan merged as `e4f2bc1`
  and the implement rung as PR #406 on 2026-09-10T23:55:54Z.
- **#308's stale implement branch.** DONE 2026-09-16:
  `odyssey/308-merge-gate-yml-repository-wide` carried 0 unique
  commits against main and was deleted by hand. The rung relaunched
  and PR #477 is open, CLEAN and `review:merge-ready`.
- **The two dead claims.** DONE 2026-09-16: #415 (claimed
  2026-09-10T22:10:43Z) and #329 (claimed 2026-09-10T07:00:22Z) were
  released by hand. #415 now reads `status:spec`; #329 still carries
  an `in-progress` label alongside `status:spec`, so one label removal
  is outstanding.
- **poll.service.** Running: `enabled`, `Restart=always`, active since
  2026-09-10 18:30:06 UTC, PID 3847103, 24 completed runs over the
  interval. No restart is owed.
- **#330 spec amendment round 2.** Still owed on 2026-09-16, with no
  branch opened and no commit under
  `scripts/ops/tests/fixtures/harness/` since the #330 plan. The
  instruction file `ops/waves/330-spec-amendment-2.md` is machine-local
  and the round is authored from the operator's second machine, which
  holds the recordings the D17 fixtures need. The fixtures fix PR
  (odyssey) is owed alongside it, per issue comment 5624478675.
- **Intake of #382, #383, #386, #390, #391, #397 and #405.** All seven
  are still open on 2026-09-16 and six of them are still `intent:new`,
  six days after revision fourteen asked for this. #405 (nothing
  proves a test suite's verdict comes from the code under test, first
  sighted on #244) is `intent:new,in-progress` with intent PR #423
  OPEN and UNSTABLE.
- **Intake of the Gate H set: #481, #482, #483, #484.** Filed
  2026-09-16. #481 is already at `status:planning`; #482, #483 and
  #484 are `intent:new` and need a rung.
- **Intake of the doors backlog filed since revision fourteen:** #454,
  #456, #463, #464, #465, #478, #479. #464 and #465 carry no labels at
  all, so no stage owns them.
- **nestor's harness pin** in `config/deployments.yaml` (plan T3 of
  #199). Antigravity is the stated goal; the pin is the operator's
  line to write.
- **#339 authority**: which identity removes labels and posts
  refusals. The workflow token does it today under `issues: write`.
- **Stale processes**: the tmux and `agy` residue named in revision
  fourteen is unverified as of 2026-09-16. The kill is the operator's
  alone; a seat has no authority to issue it. #483 is the durable form
  of this item.
- **Reopen #321.** Still CLOSED on 2026-09-16, closed
  2026-09-10T07:34:52Z by a closing reference inside PR #368's body, a
  sentence listing operator decisions, the #245 trap; the advisor note
  on the issue at 07:42Z records it. Its implement is merged and its
  last label was `status:in-review`, so reopen until #148, or leave it
  closed.
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
- **Revision fifteen, 2026-09-16 (main `05619e2`).** Six days, 60
  merge commits, 31 merged PRs; #410, #416, #404 and #425 walked all
  four rungs and #85 landed its implement rung, while #328 walled
  PR #369 and PR #421 for the whole interval and three dead handover
  resources held #308, #415 and #329 idle until an operator cleared
  them by hand. Gate H opened with #482, #483, #484 and #481.
