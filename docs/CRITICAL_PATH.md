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

Status line: 2026-09-10, revision ten (~05:20 UTC, main at `1f57021`).
The operator reset the scope this morning to four capabilities and one
inventory rule (the "Scope" section); the gates below are rewritten
around them and the earlier gates are folded into "History". Since
revision nine: sixteen autonomous merges under `evekhm-themis-app` on
2026-09-09 and three more today (PR #349, #351, #352); PR #344 (#337
spec) merged by hand because Argus wrote `run-id:0` (#353), PR #342
and #343 by hand because of #321. The poller runs the plan rungs of
#337, #308 and #312 on its own. Open and moving: PR #350 (#321
implement, fix round 2 at `618e982`, Argus round 3 clean apart from
one suggestion, Atlas round 3 running, label `consensus:disputed`
left by a replayed dispute flag), PR #319 (#265 implement, fix round
6 at `82857d7`, Atlas clean at `9482c37`, Argus re-run after the
fourth hand clear of `status:review-stuck` on #265), and the #330
spec amendment the remote Athena session owes (the merged spec
skipped the advisor ruling; `in-progress` on #330 holds the plan rung
until the amendment lands). Filed today: #353 (a `run-id:0` verdict
is refused silently), #356 (a persona session writing as the wrong
login), #360 (conjunct 10 declines every spec amendment).

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

| # | Issue | Why it is here | State |
|---|-------|----------------|-------|
| Y1 | #321 | Conjuncts 9 and 10 read a ranked status label; `intent:new` issues carry none, so every intent-stage PR needs a by-hand merge (PR #342 and #343 today). | PR #350 open, fix round 2 at `618e982`; Argus round 3: every row fixed or a suggestion; Atlas round 3 running; label `consensus:disputed` and a `dispute` peer flag on a row Atlas closed in round 2, the #331 replay. Authorized test corrections recorded on #321 (comment 5613393316) |
| Y2 | #331, #324, #328 | The consensus recorder. #331: a dispute flag is write-once, so every gate run replays it and re-escalates the issue (PR #327 needed a by-hand merge; PR #319 was re-labelled `status:review-stuck` 40 seconds after a hand clear, twice today, because a fix report comment re-ran the gate). #324: a `high` row is demoted when its failure-scenario sibling omits the `@Dn` anchor. #328: the assigned reviewer set is hardcoded, so #265's split gate branch is unreachable. | all three `intent:new`, no rung launched. Advisor recommendation: one intent covering the recorder, three Decision IDs, so the rungs run once |
| Y3 | #265 | The review split: Atlas on every PR, Argus at the code gate, `deep-review` as a one-shot grant. Cuts review spend per round. | PR #319 open at `82857d7` plus empty commit `9482c37`; six fix rounds; Argus R1-3@D3 fixed in round 6 (label consumed where honoured, refused on drafts). #265 was re-labelled `status:review-stuck` by the replay four times today and cleared by hand each time; Atlas at `9482c37` has every high row fixed, Argus re-run in progress. Merges by hand if Y2 holds it |
| Y4 | #337 | The poller only starts rungs; it cannot fire a fix round, so every reviewer finding waits for a human launch. | spec merged (PR #344, `2c5c263`), `status:build`, plan rung claimed by the poller |
| Y5 | #353 | Argus wrote `run-id:0` on PR #344; the recorder refused the verdict into audit notes only, and the gate declined on a stale ledger with no visible reason. | `intent:new` |
| Y6 | #308, #312 | Concurrency group cancels gate and recorder runs across PRs; a stream-interrupted review reports FAILURE after posting. Both make clean heads look blocked. | #308 `status:implementing` (poller), #312 `status:in-review` |
| Y7 | #339 | Who may remove a label or post a refusal. Today the workflow token does it; the persona layer has no verb. Draft guard in `post.sh` belongs here (Argus, PR #319 round 4). | `intent:new` |
| Y8 | #252, #251 | The advancer never releases the finished rung's `in-progress`; the chain's checklist. | #252 `bug`; #251 `status:in-review` |
| Y9 | #148 | Deterministic close after the last rung merges; the last by-hand step of a clean run. | `intent:new` |
| Y10 | #147 | `mode:autonomous` and per-issue `pin:`/`tier:` labels resolved in `work.sh`. The switch, and the home of the harness override that gate P needs. | `intent:new` |
| Y11 | #245 | The closing-keyword check misses commit bodies; a "Closes" in a non-final rung closed #308 and #312 one rung early. | `intent:new` |
| Y12 | #345 | A fork ignored a prose read-only instruction and launched live work under this seat's name; no tool-level enforcement exists. | `intent:new` |

Exit criterion: one issue, poller-driven from `intent:new`, with a fix
round fired by #337 and a dispute resolved by the recorder, merged by
Themis at every rung and closed by #148, and the issue timeline shows
no human actor.

## Gate S: one statusline on both harnesses (#330)

| # | Issue | Why it is here | State |
|---|-------|----------------|-------|
| S1 | #330 | `scripts/ops/harness/statusline.sh`, the side-channel file, `session-start.sh`, `install.sh --check` for both harnesses, fixtures. | intent merged (PR #343), spec merged (PR #352, `1f57021`) with none of the advisor ruling applied; amendment round 1 owed by the remote Athena session (instruction on #330, 05:15Z); `in-progress` holds the plan rung until it merges (the gate declines a spec PR at `status:build` on conjunct 9, so the amendment merges by hand) |
| S2 | #356 | The remote session's gh writes land as `evekhm-atlas-bot` while its commits are the athena App; a peer deleted its live claim on that evidence. | `intent:new`; fix on the remote machine is the athena App token for gh writes; the ask is a login-versus-persona preflight shared by every launch path |

Exit criterion: the fixture test byte-compares every recorded payload
(two per harness, plus one with `effort.level`) to one expected line,
and `install.sh --check` runs in CI and fails when the two harness
configurations point at different scripts.

## Gate W: wrap and handoff on both harnesses

| # | Issue | Why it is here | State |
|---|-------|----------------|-------|
| W1 | #85 | `scripts/ops/wrap.sh` writes the dated handoff and runs the close-out; the `/wrap` door is Claude Code only by the operator's scope cut of 2026-09-10 (spec D8 on PR #357, per #43 D16: no `.agents/workflows/` twin in v1). An Antigravity seat calls the script from its brief or Stop hook; the agy door is a follow-up intent that D8 must name. | spec amendment round 2 open as PR #357 (athena, `0be054d`); plan PR #349 superseded by it |
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

1. PR #350 merges (Y1). From then on intent-stage PRs merge on their
   own.
2. Y2 recorder intent filed and walked (one issue or three, operator
   call); until it merges, a held clean head is merged by hand with the
   holding conjunct named on the PR.
3. PR #319 merges (Y3), by hand if Y2 is still open.
4. #330 amendment merges by hand, `in-progress` comes off, the poller
   runs the plan and implement rungs (S1, W2).
5. #337 implement (Y4), so the next fix round is fired by the poller.
6. #199 implement (P1): `nestor.yaml`, the seat launch, the pin.
7. #259 spec amended for `seat.sh` (P3), then its rungs.
8. #85 and #329 (W1, W3) once S1 is on main.
9. #147 (Y10, P4).
10. #353, #308, #312, #339, #252, #148, #245, #345 as the poller reaches
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
- **Recorder trio as one rung or three.** #331, #324 and #328 touch one
  script; recommended: one intent, three Decision IDs.
- **nestor's harness pin** in `config/deployments.yaml` (plan T3 of
  #199). Antigravity is the stated goal; the pin is the operator's
  line to write.
- **#339 authority**: which identity removes labels and posts
  refusals. The workflow token does it today under `issues: write`.
- **Stale processes**: the idle agy REPL in tmux `waves:265i-odyssey`
  since 2026-09-09 19:08 and any verifier process older than a day;
  the operator kills, never a seat.
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
  a refused `run-id:0` verdict, #353), PR #346 (#85 spec round 1).
  Every one is recorded on its PR with the holding conjunct.
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
