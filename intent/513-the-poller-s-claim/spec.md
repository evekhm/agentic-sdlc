# Spec: Sound Poller Claim Lifecycle: Detached Dispatch, Claim Reaper, and Rung-Filtered Intake Concurrency

**Issue:** #513 · **Status:** Approved (approval = merge of this PR) · **Author:** athena (`evekhm-athena-app[bot]`) · **Open questions:** none

## What is being built

This specification defines a sound claim lifecycle for the continuous poller (`scripts/placement/vm-local/poll.sh`). It resolves three structural defects that stall autonomous operation: synchronous blocking execution during runner dispatches, permanent claim stranding upon process death, and false intake concurrency throttling caused by unfiltered claim counts.

### Core Capabilities

1. **Detached Background Dispatch (`poll.sh`):**
   - The poller dispatches runner invocations (`run.sh`) in the background across all candidate execution paths: pull request fix rounds, first-hop intake, and lifecycle ladder consumption.
   - Standard output and standard error from each dispatch are captured in dedicated log files located under `${POLL_LOG_DIR:-${poll_state_dir}/logs}/dispatch-<issue>-<timestamp>.log`.
   - The primary polling loop continues immediately while runner execution proceeds in the background, maintaining a responsive 30-second polling cadence and regular ledger sweeps.

2. **Process Attribution in Claim Mutex (`claim.sh`):**
   - When spawned by `poll.sh`, the background subshell records its own process identifier (`poll-$BASHPID`) in the claim session metadata.
   - The claim comment posted to the tracker explicitly identifies the executing background process: `Claim: <persona> (poll-<pid>), stage: <stage>. Worktree: <path>`.

3. **In-Band Claim Reaper (`poll.sh`):**
   - The continuous poller executes a claim sweep at the start of each polling cycle.
   - The sweep identifies issues carrying `in-progress` whose last claim comment specifies a poller session prefix (`poll-`).
   - Using process table inspection (`kill -0 <pid>`), the reaper verifies whether the recorded owning process is still alive.
   - Claims whose recorded process is dead and whose claim age exceeds the minimum grace period (`claim_reaper_min_age_seconds`, default 60s) are classified as stranded.
   - A configurable upper limit (`claim_reaper_max_age_seconds`, default 7200s) acts as an absolute runaway ceiling.
   - Interactive claims lacking a `poll-` prefix remain untouched by the automated poller reaper.

4. **Safe Worktree and Branch Reclamation:**
   - When releasing a stranded claim, the reaper inspects the local branch associated with the worktree.
   - If the branch contains no unmerged commits relative to `origin/main` (`git log origin/main..refs/heads/$BRANCH` is empty), the worktree is removed and the local branch is deleted.
   - If unmerged commits are detected on the branch, the worktree and branch remain on disk to preserve unpushed work, while the tracker's `in-progress` label is released alongside an explanatory tracking comment.
   - Worktrees and local branches corresponding to prior rungs that have fully merged into `origin/main` are pruned before fresh claims, preventing branch collision refusals on subsequent lifecycle stages.

5. **Stage-Filtered First-Hop Intake Concurrency:**
   - In `poll.sh`, candidate evaluation for first-hop intake measures active concurrency by parsing the declared lifecycle stage from recent claim comments.
   - Only active claims whose last claim comment specifies `stage: intake` increment the first-hop counter against `max_concurrent_first_hops`.
   - Claims held by Athena at the `plan` or `design` lifecycle rungs are excluded from the first-hop counter, allowing new `intent:new` issues to enter intake without delay.

6. **Execution Configuration Parameters:**
   - `config/execution.yaml` supports optional reaper tuning parameters under the `loop:` section:
     - `claim_reaper_max_age_seconds`: maximum elapsed claim duration before runaway reaping (default: 7200).
     - `claim_reaper_min_age_seconds`: grace period before dead process reaping (default: 60).
   - `scripts/ops/execution.py` validates these settings in `--check`.

### Manifest of Files Touched by the Implementation Rung

- `scripts/placement/vm-local/poll.sh`: background runner dispatch, child PID attribution, in-band claim reaper, and stage-filtered intake concurrency.
- `scripts/placement/vm-local/run.sh`: runner handling and execution pass-through.
- `config/execution.yaml`: reaper configuration defaults under `loop:`.
- `scripts/ops/execution.py`: schema validation for reaper configuration keys.
- `scripts/ops/tests/poll_test.sh`: unit and regression tests for reaper logic, background dispatch, and concurrency counting.
- `docs/SPEC.md`: living spec updates for poller concurrency, claim reaping, and lifecycle branch cleanup.
- `CHANGELOG.md`: changelog entry.

### Manifest of Files Touched by this PR (Athena)

- `intent/513-the-poller-s-claim/intent.md`: update status to Accepted.
- `intent/513-the-poller-s-claim/spec.md`: this specification.

### Forbidden Files (Untouched)

- `.github/workflows/**`: GitHub Actions workflows remain untouched.
- `personas/**`: Persona definitions and boundaries remain untouched.
- `scripts/ci/merge_gate.sh`: Merge gate conjuncts remain untouched.
- `scripts/ci/review_recorder.py`: Review recording logic remains untouched.
- `scripts/ops/claim.sh`: Core claim CLI interface and refusal ladder remain untouched.

## Relationships

- **absorbs #498**: Resolves the first-hop intake freeze caused by counting plan and design rungs against `max_concurrent_first_hops`.
- **absorbs #499**: Resolves the synchronous foreground runner execution in `poll.sh` that stalled polling cycles.
- **refines #251** (D2, D5): Extends poller architecture by introducing background process management and stage-aware queue limits.
- **refines #295** (D2): Replaces unfiltered Athena login counting with stage-specific claim inspection.
- **depends on #372**: Assumes native issue dependency checks established in `claim.sh`.
- **refines #383**: Coordinates local worktree and branch pruning for merged rungs prior to claiming.
- **refines #363**: Preserves poller recovery and dispatch logging when child invocations exit non-zero.
- **refines #377**: Maintains candidate discovery hygiene across polling loops.
- **refines #397**: Aligns poller claim handling with lifecycle advancer states.

## Decisions

| ID | Decision | Rationale |
|---|---|---|
| **D1** | **Detached background runner dispatch in `poll.sh`.** `poll.sh` dispatches runner invocations (`run.sh`) in the background across pull request fix rounds, first-hop intake, and ladder consumption. Standard output and standard error are redirected to `${POLL_LOG_DIR:-${poll_state_dir}/logs}/dispatch-<issue>-<timestamp>.log`. The main polling loop continues its 30-second cadence while background executions proceed. | *Adversary analysis:* Two defensible readings: (1) Run `run.sh` in the foreground with an execution timeout. (2) Detach `run.sh` into a background process redirecting output to a dedicated log file. Differing case: A runner executes a 20-minute agent session while independent pull requests and ladder issues are waiting in the queue. Under Reading 1, the entire poller blocks for 20 minutes, snapshot data becomes stale, and independent tasks cannot be processed until the session finishes. Under Reading 2, the poller spawns the run in the background, immediately continues the queue sweep, and dispatches other non-conflicting tasks on subsequent ticks. Reading 2 is adopted. |
| **D2** | **Child process PID attribution and claim session binding.** When `poll.sh` dispatches a run, `claim.sh` is invoked with `CLAIM_SESSION="poll-$BASHPID"` inside the spawned background child subshell. The claim comment on GitHub records `Claim: <persona> (poll-<pid>), stage: <stage>`. | *Adversary analysis:* Two defensible readings: (1) Parent poller executes `claim.sh` with `CLAIM_SESSION="poll-$$"` in the foreground before spawning the runner in the background. (2) Background child subshell executes `claim.sh` with `CLAIM_SESSION="poll-$BASHPID"` immediately before invoking `run.sh`. Differing case: The parent poller runs continuously with PID 1000. It dispatches an agent session in the background that crashes after 2 minutes. Under Reading 1, the claim records `poll-1000`. The reaper checks `kill -0 1000`. The parent poller is alive, so the reaper treats the crashed session as active and leaves the stranded claim unreleased. Under Reading 2, the claim records the child subshell PID (such as `poll-1050`). When the child crashes, `kill -0 1050` fails, allowing the reaper to detect the dead process and release the stranded claim. Reading 2 is adopted. |
| **D3** | **In-band claim reaper execution in `poll.sh`.** The claim reaper executes in-band at the start of each polling tick inside `poll.sh`. The reaper inspects open issues carrying the `in-progress` label and examines claims matching session prefix `poll-`. | *Adversary analysis:* Two defensible readings: (1) Implement the reaper as an external background timer or separate cron service. (2) Execute the reaper in-band inside `poll.sh` at the beginning of each polling cycle. Differing case: An operator or container environment starts `scripts/placement/vm-local/poll.sh` without configuring secondary supervisor daemons or crontabs. Under Reading 1, stranded claims remain unreleased unless the operator remembers to configure and start the auxiliary daemon. Under Reading 2, the poller self-heals automatically on every cycle without requiring multi-process orchestration. Reading 2 is adopted. |
| **D4** | **Dual-condition reaper liveness evaluation (PID check and grace age).** A poller claim (`poll-<pid>`) is eligible for reaping if its age exceeds `claim_reaper_min_age_seconds` (default 60s) AND the recorded PID is dead (`! kill -0 "$pid"`), or if its age exceeds `claim_reaper_max_age_seconds` (default 7200s). Interactive claims lacking a `poll-` session prefix remain untouched by the automated poller reaper. | *Adversary analysis:* Two defensible readings: (1) Reap claims based solely on elapsed age exceeding a fixed duration. (2) Reap claims based on PID death (`kill -0`) past a short startup grace period, with an age ceiling fallback. Differing case: A runner crashes 90 seconds after dispatch. Under Reading 1 (age alone with a 7200s threshold), the issue remains stranded and blocked from re-dispatch for nearly two hours. Under Reading 2, the reaper confirms the PID is dead and the 60s grace period has elapsed, reclaiming the issue on the next polling tick. Reading 2 is adopted. |
| **D5** | **Safe worktree and unmerged branch reaper cleanup.** When releasing a stranded claim, the reaper inspects the local worktree and branch associated with the claim. If the branch contains no unmerged commits relative to `origin/main` (`git log origin/main..refs/heads/$BRANCH` is empty), the reaper removes the worktree and deletes the local branch. If unmerged commits exist on the branch, the reaper releases the `in-progress` label and posts an explanatory comment, but preserves the branch locally. | *Adversary analysis:* Two defensible readings: (1) Unconditionally delete the local branch and worktree upon reaping a claim. (2) Inspect git ancestry and delete the branch only if it contains zero unmerged commits relative to `origin/main`, preserving branches with unmerged commits. Differing case: A runner was killed mid-flight after having committed progress locally that was not yet pushed to a remote pull request. Under Reading 1, deleting the branch permanently destroys the unpushed commits. Under Reading 2, the unmerged branch is preserved locally for manual recovery, while clean branches created by aborted starts are safely pruned. Reading 2 is adopted. |
| **D6** | **Merged branch and worktree pruning prior to claim.** `poll.sh` maintains `claim.sh`'s strict refusal on existing local branches (`refs/heads/$BRANCH`). To prevent collisions when an issue advances across lifecycle stages, the reaper and pre-claim checks prune safe worktrees and branches that have already been fully merged into `origin/main` (`git merge-base --is-ancestor refs/heads/$BRANCH origin/main`). Active branches with unmerged pull requests in review are preserved, and `claim.sh` refuses duplicate claims on them. | *Adversary analysis:* Two defensible readings: (1) Add a `--resume` flag to `claim.sh` allowing checkout of existing branches. (2) Keep `claim.sh` refusing on existing branches, and prune local branches/worktrees that have fully merged into `origin/main`. Differing case: An issue has a branch with a pull request currently undergoing review. `poll.sh` attempts to claim the issue. Under Reading 1, `claim.sh --resume` attaches to the active branch, clobbering the review branch with new checkouts or uncoordinated edits. Under Reading 2, `claim.sh` refuses with exit 2 because the branch exists and is not merged, protecting the in-flight review. Issues whose previous stage PR has merged into `origin/main` have their old branches pruned and proceed cleanly. Reading 2 is adopted. |
| **D7** | **Stage-filtered first-hop intake concurrency.** In `scripts/placement/vm-local/poll.sh`, the first-hop concurrency counter parses the stage declared in the claim comment (`stage: <stage>`) of each active `in-progress` issue. Only claims where the last claim comment specifies `stage: intake` (case-insensitive) count against `max_concurrent_first_hops`. Athena claims on `plan` (`stage: plan`) and `design` (`stage: design`) stages are excluded from the first-hop count. | *Adversary analysis:* Two defensible readings: (1) Count all in-progress issues claimed by Athena regardless of lifecycle stage. (2) Parse the claim comment body and count only issues where the claim stage is explicitly `intake`. Differing case: Athena is working on a specification (`status:spec`, `stage: design`) for issue #513. A new user idea arrives as `intent:new` with `intake:auto`. Under Reading 1, Athena's active design claim causes `active_count >= max_concurrent_first_hops (1 >= 1)`, stalling the new intake issue indefinitely. Under Reading 2, the counter checks the claim stage, recognizes that #513 is at `stage: design`, and counts 0 active intake hops, allowing the new `intent:new` issue to be claimed for intake immediately. Reading 2 is adopted. |
| **D8** | **Execution configuration and schema validation.** `config/execution.yaml` loop section supports optional keys `claim_reaper_max_age_seconds` (integer, default 7200) and `claim_reaper_min_age_seconds` (integer, default 60). `scripts/ops/execution.py` validates these keys under `check()`, ensuring positive integer values. | *Adversary analysis:* Two defensible readings: (1) Hardcode reaper intervals and timeout constants as shell script variables inside `poll.sh`. (2) Expose reaper configuration parameters in `config/execution.yaml` and validate them in `execution.py`. Differing case: An operator needs to adjust the reaper timeout on a dedicated staging machine or CI environment. Under Reading 1, modifying the value requires editing shell script source code. Under Reading 2, the value is centrally managed in `execution.yaml` and validated by CI gates (`execution.py --check`). Reading 2 is adopted. |
| **D9** | **Living spec and changelog update obligations.** The implementing pull request updates `docs/SPEC.md` under placement and continuous poller operations, detailing detached background dispatch, reaper semantics, branch pruning, and stage-filtered intake concurrency. `CHANGELOG.md` documents the improvements to loop reliability and intake unfreezing. | *Adversary analysis:* Two defensible readings: (1) Omit living spec updates, treating poller changes as internal deployment scripts. (2) Update `docs/SPEC.md` and `CHANGELOG.md` with explicit capability entries. Differing case: `scripts/ci/spec_check.sh` and `scripts/ci/changelog_check.sh` evaluate the implementation pull request. Under Reading 1, CI gates fail or require bypass markers that obscure architectural changes. Under Reading 2, the living spec accurately reflects poller concurrency and claim lifecycles, and CI gates pass cleanly. Reading 2 is adopted. |
| **D10** | **Scope boundaries and file manifest.** The implementing change is constrained to the files specified in the implementation manifest (`scripts/placement/vm-local/poll.sh`, `scripts/placement/vm-local/run.sh`, `config/execution.yaml`, `scripts/ops/execution.py`, test scripts, `docs/SPEC.md`, `CHANGELOG.md`). Workflows (`.github/workflows/**`), persona prompts (`personas/**`), merge gate logic (`merge_gate.sh`), and review recorder logic remain untouched. | *Adversary analysis:* Two defensible readings: (1) Modify `claim.sh` to add auto-reap and auto-cleanup flags. (2) Confine reaper, backgrounding, and intake filtering logic to `poll.sh` and execution configuration, leaving `claim.sh` untouched. Differing case: PR #500 recently refactored `claim.sh`. Under Reading 1, edits to `claim.sh` risk regressions in CLI claim workflows across all personas and manual operator sessions. Under Reading 2, `claim.sh` preserves its strict core contract, and placement-specific lifecycle management stays isolated within `scripts/placement/vm-local/`. Reading 2 is adopted. |

## Acceptance

- **AT-513-1 (D1):** When `poll.sh` dispatches a candidate work item (fix round, intake, or ladder rung), `run.sh` executes as a background process with standard output and standard error redirected to `${POLL_LOG_DIR:-${poll_state_dir}/logs}/dispatch-<issue>-<timestamp>.log`. The main polling loop continues its cycle without awaiting `run.sh` termination.
- **AT-513-2 (D2):** When a run is dispatched by `poll.sh`, the claim comment created by `claim.sh` carries a session string matching `poll-[0-9]+` corresponding to the background child process identifier.
- **AT-513-3 (D3, D4):** When `poll.sh` encounters an `in-progress` issue whose claim comment specifies a `poll-<pid>` session where `<pid>` is no longer running (`kill -0 <pid>` fails) and whose claim age exceeds `claim_reaper_min_age_seconds`, the reaper releases the `in-progress` label and posts an issue comment noting the release.
- **AT-513-4 (D4):** When an `in-progress` issue has a claim whose owning process identifier is still active and whose age is below `claim_reaper_max_age_seconds`, the reaper preserves the claim.
- **AT-513-5 (D4):** When an `in-progress` issue carries an interactive claim lacking a `poll-` session prefix, the automated reaper preserves the claim.
- **AT-513-6 (D5):** When a stranded claim is reaped and its local branch has zero unmerged commits relative to `origin/main`, the reaper removes the worktree and deletes the local branch. If the branch has unmerged commits, the branch remains on disk.
- **AT-513-7 (D6):** When an issue has advanced across lifecycle stages and its previous local branch has been merged into `origin/main`, the merged local branch and worktree are pruned prior to claiming, allowing `claim.sh` to claim the issue without a branch collision.
- **AT-513-8 (D7):** In `poll.sh`, an issue claimed by Athena carrying `stage: plan` or `stage: design` does not increment `active_count` for first-hop intake. With an active Athena plan or design claim and `max_concurrent_first_hops: 1`, an unclaimed `intent:new` issue with `intake:auto` is claimed for intake.
- **AT-513-9 (D8):** `config/execution.yaml` validates under `python3 scripts/ops/execution.py --check` with `claim_reaper_max_age_seconds` and `claim_reaper_min_age_seconds` configured under `loop:`.
- **AT-513-10 (D9, D10):** `docs/SPEC.md` and `CHANGELOG.md` receive corresponding updates, passing `scripts/ci/spec_check.sh` and `scripts/ci/changelog_check.sh`.

## Open questions

none
