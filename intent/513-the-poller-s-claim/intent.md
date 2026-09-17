# Intent: Sound Poller Claim Lifecycle: Detached Dispatch, Claim Reaper, and Rung-Filtered Intake Concurrency

**Issue:** #513 · **Stage:** plan · **Author:** athena (`evekhm-athena-app[bot]`) · **Status:** Draft

## Problem

The VM-local poller holds a claim mutex it can neither account for nor release. Three defects share one root cause, and together they stop the autonomous loop dead. Measured on 2026-09-17: the poller (pid 304637) refused every row it examined for roughly fourteen hours.

1. **Dispatch is synchronous and unsupervised.** `scripts/placement/vm-local/poll.sh` calls the runner in the foreground at three sites (`:350-352`, `:415`, `:498`), and `scripts/placement/vm-local/run.sh:103` is `exec "$REPO_ROOT/scripts/ops/work.sh" "$NUMBER" --as "$PERSONA"`. The whole poll cycle blocks for the length of an agent session, so `POLL_INTERVAL` (default 30s, `poll.sh:27`) carries no meaning and one slow run serializes the fleet. The snapshots taken at `:135`, `:362` and `:425` go stale while the poller waits.

2. **A dead dispatch strands its claim forever.** The claim is written first (`:409` then `:415`; `:493` then `:498`), and `|| true` swallows every nonzero exit. No trap, no rollback, no heartbeat, and no call to `claim.sh --release` exists anywhere in `poll.sh`. When a run dies, the `in-progress` label, the claim comment, the branch and the worktree all survive with no owner. The only staleness logic in the file is the PR fix-round lock at `:244-268`; issue claims have no reaper at all. This defect is established from the code path. No verified stranding instance is on record yet: the long-held claims on #318 and #372 are claims correctly retained while their pull requests (#507, #500) sit in review, so they are not instances of it.

3. **The first-hop count measures the wrong thing, so intake freezes.** `poll.sh:362-374` counts every open `in-progress` issue whose last claim comment was authored by athena, with no stage or rung filter. `personas/athena.yaml:4` gives athena `stage: [intake, plan, design]`, so an issue she touched at any of three rungs scores as an in-flight first hop. `config/execution.yaml:38` sets `max_concurrent_first_hops: 1`. One lingering athena claim therefore short-circuits intake at `:376-377` permanently. Issue #498 recorded 1060 consecutive skips and zero intakes across fifteen hours.

Defect 2 feeds defect 3: a stranded athena claim is exactly the condition that freezes intake, and nothing can clear it.

A fourth symptom sits downstream in `scripts/ops/claim.sh:252-253`, which refuses on `refs/heads/$BRANCH` existing locally. The check reads local refs only, there is no `--resume` flag (`:65-77` accepts `--release` and `-h`), and `--release` (`:117-124`) drops the label while leaving the branch and worktree in place. The slug is derived deterministically from the issue title (`:194`, `:208`) and the poller always omits it (`:409`, `:493`), so it recomputes the same branch name forever. One leftover local branch blocks that issue's re-dispatch for good. Two issues sat permanently jammed this way on 2026-09-17, #481 and #269, both owing spec.md at the design rung while their intent-rung branch survived locally after merging. An operator cleared both by hand at 21:05Z by removing the worktree and deleting the branch. Two further refusals on the same message, #415 and #405, were correct: their branches carry pull requests #421 and #506 still in review.

## Proposed outcome

The poller's claim lifecycle becomes sound: a claim is held only while a live process owns it, and the loop keeps turning when a dispatch dies.

1. **Detached dispatch:** Dispatch runs detached in the background, so one agent session no longer blocks the poll cycle or the rest of the ledger sweep.
2. **Claim reaper:** A reaper releases claims whose owning process is gone, past a configurable age threshold, and cleans up the branch and worktree it created so re-dispatch succeeds.
3. **Rung-filtered first-hop count:** The first-hop count measures first hops. The claim comment already carries the rung (`claim.sh:297` writes `stage: $STAGE`), so the count filters on `stage: intake` and stops counting athena's plan and design rungs.

Acceptance is behavioural: kill a dispatched run mid-flight, and within one reaper interval the issue is claimable again with no leftover branch, no leftover worktree and no `in-progress` label. Separately, with an athena claim open at the plan or design rung, a fresh `intent:new` issue still gets its first hop.

## Affected users and systems

- `scripts/placement/vm-local/poll.sh`: detached background dispatch, reaper invocation, and stage-filtered intake concurrency check.
- `scripts/placement/vm-local/run.sh`: detached runner handling and process isolation.
- `scripts/ops/claim.sh`: branch and worktree lifecycle alignment and conflict prevention.
- `config/execution.yaml`: execution parameters for reaper timeout and concurrency.
- `docs/SPEC.md`: living spec updates for poller claim lifecycle and concurrency controls.
- Personas dispatched by the poller (`athena`, `daedalus`, `odyssey`) and operators monitoring autonomous loop health.

## Constraints

- Sequence with PR #500: `claim.sh` is under active change on PR #500 (Refs #372), which replaces body parsing with native issue dependencies. This work builds on that merged state and must avoid conflicting edits to the same paths.
- Isolation: The claim remains the unit of isolation (AGENTS.md, "Working the tracker"). A reaper releases a claim whose owner is demonstrably gone; it never preempts a live process.
- Output recovery: Backgrounding must keep each dispatch's output recoverable, since `work.sh` reports through `WORK-RESULT:` and the operator reads those logs.
- Safe branch removal: Deleting a branch is destructive. The reaper removes only a branch it can prove the claim created and that carries no unmerged commits.
- Prose standards: Zero em dash characters, zero instances of comparative exclusion phrasing, zero contrast sentences, and zero machine home paths.
- Surface mapping audit:
  - `README.md`: Concept and vision describe the 30-second poller and claim mechanics generally (lines 493-505); no edits required.
  - `INTENT.md`: Core founding principles remain intact; no edits required.
  - `REVIEW.md`: Review protocol and gates remain intact; no edits required.
  - `docs/SPEC.md`: Living spec updates owed during implementation under poller operations.
  - `config/execution.yaml`: Configuration parameters for reaper thresholds added during implementation.
  - `intent/251-e2e-chain/spec.md`: Decision #251 D2 and D5 refined in implementation; no retrospective edits required.
  - `intent/295-poller-intake-gate/spec.md`: Decision #295 D2 refined in implementation; no retrospective edits required.

## Relationships

- `absorbs #498`: First-hop intake freeze caused by counting plan and design rungs against `max_concurrent_first_hops`.
- `absorbs #499`: Synchronous foreground dispatch in `poll.sh` stalling poll cycles and queue sweeps.
- `refines #251`: Refines Decision #251 D2 (foreground poller dispatch) and Decision #251 D5 (first-hop queue handling).
- `refines #295`: Refines Decision #295 D2 (athena claim concurrency counting across all rungs).
- `depends on #372`: Implementation builds upon native issue dependencies in `claim.sh` introduced in PR #500.
- `refines #383`: Shares surface on cleanup of branches and worktrees surviving after autonomous transitions.
- `refines #363`: Shares surface on poller dispatch handling when `work.sh` refuses.
- `refines #377`: Shares surface on poller discovery and lock key hygiene.
- `refines #397`: Shares surface on advancer and poller coordination during held claims.

## Open questions

1. **Reaper liveness detection mechanism**:
   Does the reaper key liveness on the pid recorded in the claim session name (`poll-304637`), on claim age, or on both?
   - Option A: Key liveness on both `kill -0` checking the recorded PID and an elapsed claim age threshold (`POLL_LOCK_MAX_AGE`), matching the precedent set by the PR fix-round lock in `poll.sh:244-268`.
   - Option B: Key liveness on claim age alone, releasing any claim that exceeds a configured maximum duration.
   - Differing case: A dispatched session crashes and the operating system recycles its PID to an unrelated active process before the reaper runs. Under Option A, `kill -0` sees the PID as active and retains the claim until max age expires. Under Option B, the claim is reaped once the age threshold is crossed regardless of PID reuse.

2. **Reaper ownership and execution topology**:
   Who owns the reaper: the poller itself each cycle, or a separate timer?
   - Option A: In-band reaper execution inside `poll.sh` at the start of each polling tick.
   - Option B: A separate timer or supervisor unit running independently from `poll.sh`.
   - Differing case: The poller itself is killed or crashes mid-cycle. Under Option A, claims left behind cannot be reaped until the poller is restarted. Under Option B, the independent timer continues to reap stranded claims while the poller is inactive.

3. **Existing branch handling on re-dispatch**:
   Should `claim.sh` gain `--resume` for the branch-exists case, or should the reaper's cleanup make the refusal unreachable in practice?
   - Option A: Add an explicit `--resume` flag to `claim.sh` that allows checkout of an existing local branch when re-dispatching an issue.
   - Option B: Keep `claim.sh` refusing on existing local branches, relying on the reaper and post-merge lifecycle steps to clean up branches before re-dispatch occurs.
   - Differing case: An issue merges at the plan stage, leaving a local branch, and the poller claims the issue for the design stage before cleanup runs. Under Option A, `claim.sh --resume` succeeds and attaches to the branch. Under Option B, `claim.sh` refuses with a branch collision until cleanup completes.

## Non-goals

- Fix-round discovery logic modifications (#377).
- Handling stale ledger rungs (#363).
- Modifying lifecycle advancer withholding behavior (#397).
- General post-merge branch cleanup after autonomous merges (#383).
