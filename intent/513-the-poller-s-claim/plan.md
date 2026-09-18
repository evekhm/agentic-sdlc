# Plan: Sound Poller Claim Lifecycle: Detached Dispatch, Claim Reaper, and Rung-Filtered Intake Concurrency

**Issue:** #513 · **Spec:** `intent/513-the-poller-s-claim/spec.md` (Approved, PR #523, D1–D10, AT-513-1–AT-513-10)  
**Author:** daedalus (`evekhm-daedalus-app[bot]`)  
**Base commit:** `8dd91e8cd02a1a45cff919f8ead61569cb3c7734` (`origin/main`, merge of spec PR #523)  
**Target branch for implementation (Odyssey):** `odyssey/513-the-poller-s-claim-lifecycle-is-unsound`

---

## 1. Executive Summary and Problem Statement

The continuous poller daemon (`scripts/placement/vm-local/poll.sh`) drives autonomous execution on operator infrastructure. Under its current implementation, three structural defects impede reliable unattended operation:

1. **Synchronous Runner Blocking:**
   Runner dispatches (`scripts/placement/vm-local/run.sh`) execute synchronously in the foreground across fix rounds, first-hop intake, and lifecycle ledger consumption. Long-running model sessions (such as 20-minute agent turns) block the poller loop entirely, stalling queue sweeps and preventing discovery of independent work.

2. **Unsound Process Attribution and Absence of a Claim Reaper:**
   When claiming issues before runner execution, `poll.sh` passes `CLAIM_SESSION="poll-$$"`. This records the parent poller process ID in GitHub tracker claim comments instead of the child worker process ID. When a worker process crashes, exits abnormally, or runs away, the claim remains stranded on the issue indefinitely. Without an automated reaper, stranded claims block subsequent lifecycle advancement until an operator intervenes manually.

3. **Intake Freeze from Unfiltered Concurrency Counting:**
   When evaluating candidate issues for first-hop intake (`intent:new` issues with `intake:auto`), `poll.sh` measures active concurrency by counting all open `in-progress` issues claimed by `evekhm-athena-app`. This count includes Athena sessions active on downstream `plan` (`stage: plan`) or `design` (`stage: design`) lifecycle rungs. Because `max_concurrent_first_hops` defaults to 1, any ongoing plan or design specification by Athena completely freezes first-hop intake for new issues.

4. **Lifecycle Branch Collisions on Re-Claim:**
   When an issue advances across lifecycle stages (such as progressing from `status:spec` to `status:build`), `claim.sh` refuses duplicate claims if the local git branch already exists. When previous stage branches have fully merged into `origin/main`, they must be safely pruned prior to claiming to prevent spurious collision refusals.

This plan specifies the micro-stepped implementation to resolve these defects:
- **Detached Background Dispatch (D1):** Detach `run.sh` into background executions across fix rounds, first-hop intake, and ladder consumption, redirecting standard output and standard error to dedicated per-dispatch log files (`${POLL_LOG_DIR:-${poll_state_dir}/logs}/dispatch-<issue>-<timestamp>.log`). The 30-second polling cadence continues without blocking.
- **Child Subshell Process Attribution (D2):** Attributable claims invoke `claim.sh` inside the spawned background child subshell using `CLAIM_SESSION="poll-$BASHPID"`, binding the claim to the actual worker process ID.
- **In-Band Claim Reaper (D3, D4):** Execute an in-band claim sweep at the start of each polling tick. Evaluate claims with session prefix `poll-`: reap claims if the recorded PID is dead (`! kill -0 "$pid"`) and elapsed grace period exceeds `claim_reaper_min_age_seconds` (default 60s), or if elapsed time exceeds `claim_reaper_max_age_seconds` (default 7200s). Interactive claims lacking a `poll-` prefix remain preserved.
- **Safe Worktree and Branch Reclamation (D5):** Check git ancestry during claim reaping. If a local branch has zero unmerged commits relative to `origin/main`, remove the worktree and delete the local branch. If unmerged commits exist, preserve the branch on disk for manual recovery while releasing the tracker label.
- **Pre-Claim Merged Branch Pruning (D6):** Prune worktrees and local branches whose commits are fully merged into `origin/main` (`git merge-base --is-ancestor refs/heads/$BRANCH origin/main`) prior to claiming advancing lifecycle stages, preventing branch collision refusals.
- **Stage-Filtered Intake Concurrency (D7):** Parse the declared lifecycle stage from claim comments. Count only active claims declaring `stage: intake` against `max_concurrent_first_hops`, unfreezing first-hop intake when Athena works on `plan` or `design` rungs.
- **Configuration Defaults and Schema Validation (D8):** Expose `claim_reaper_max_age_seconds` and `claim_reaper_min_age_seconds` under `loop:` in `config/execution.yaml` and validate positive integer bounds in `scripts/ops/execution.py`.
- **Living Spec and Changelog Updates (D9, D10):** Synchronize living architecture documentation in `docs/SPEC.md` and release notes in `CHANGELOG.md`.

---

## 2. Scope, Persona Boundaries, and Grants

### Persona Authority Boundaries

| Actor | Stage | Authority / Paths Touched | Role in Issue #513 |
|---|---|---|---|
| **athena** | intake, plan, design | `intent/**` | Authored `intent.md` and approved `spec.md` (merged in PR #523). |
| **daedalus** | build | `intent/**`, `scripts/*/tests/**` | Authors `plan.md` and commits contract test suite `scripts/ops/tests/poller_claim_lifecycle_contract_test.sh`. Daedalus does not edit production code. |
| **odyssey** | implement | `scripts/placement/vm-local/**`, `config/execution.yaml`, `scripts/ops/execution.py`, `scripts/ops/tests/poll_test.sh`, `docs/SPEC.md`, `CHANGELOG.md` | Executes Tasks T2 through T9 branching from the commit merging this plan, turns contract tests green, updates living documentation, and verifies all CI gates. |
| **themis** | autonomous merge | GitHub Actions (`merge-gate.yml`) | Autonomously gates and merges pull requests upon consensus. |
| **argus / atlas** | review | comments only | Review pull requests against spec and plan. |

### Deep Review Grant Assessment (DEEP-1, DEEP-3, DEEP-5)

- **Build PR (Daedalus):**
  - **DEEP-1 (trust-bearing paths):** Touches `scripts/ops/tests/poller_claim_lifecycle_contract_test.sh`.
  - **Action:** Daedalus applies `deep-review` label via `scripts/ops/post.sh <pr> --as daedalus --add-label deep-review`.
- **Implementation PR (Odyssey):**
  - **DEEP-1 (trust-bearing paths):** Touches `scripts/placement/vm-local/**`, `config/execution.yaml`, and `scripts/ops/execution.py`.
  - **DEEP-3 (privileged / irreversible operations):** Modifies poller automation that mutates labels (`gh issue edit --remove-label in-progress`), deletes branches (`git branch -D`), and removes worktrees (`git worktree remove`).
  - **DEEP-5 (escalated risk tier):** Task T2 and Task T3 alter concurrent process dispatch, claim mutex locking, and branch state machines. Marked `risk: high`.
  - **Action:** Odyssey applies the `deep-review` grant when opening the implementation PR per `scripts/ops/post.sh <pr> --as odyssey --add-label deep-review`.

### Living Spec and Changelog Obligations

- **Build PR (Daedalus):**
  - `Spec-impact: none: non-behavior-bearing path (intent/**, scripts/*/tests/** only)`
  - `Changelog: none: non-behavior-bearing path (intent/**, scripts/*/tests/** only)`
- **Implementation PR (Odyssey):**
  - Updates `docs/SPEC.md` under placement and continuous poller sections documenting detached runner execution, reaper intervals, safe branch reclamation, and stage-filtered intake concurrency (D9, AT-513-10).
  - Updates `CHANGELOG.md` documenting bug fixes for issue #513 (AT-513-10).

### Strict File Manifest Partitioning (D10)

The implementing change (Odyssey) is strictly confined to:
1. `scripts/placement/vm-local/poll.sh`
2. `scripts/placement/vm-local/run.sh`
3. `config/execution.yaml`
4. `scripts/ops/execution.py`
5. `scripts/ops/tests/poll_test.sh`
6. `docs/SPEC.md`
7. `CHANGELOG.md`
8. `intent/513-the-poller-s-claim/plan.md` (read-only reference; updated only if plan deviation occurs)
9. `intent/513-the-poller-s-claim/spec.md` (read-only reference)

**Forbidden Paths (Untouched per D10):**
- `.github/workflows/**`: GitHub Actions workflows remain untouched.
- `personas/**`: Persona definitions and compiled prompts remain untouched.
- `scripts/ci/merge_gate.sh`: Merge gate logic remains untouched.
- `scripts/ci/review_recorder.py`: Review recording logic remains untouched.
- `scripts/ops/claim.sh`: Core claim CLI interface and refusal ladder remain untouched.

Note on Contract Test Suite (`scripts/ops/tests/poller_claim_lifecycle_contract_test.sh`): Authored and committed in this Build PR by Daedalus under Daedalus authority (`scripts/*/tests/**`).

---

## 3. Detailed Architectural Calls

### P1 · Detached Background Runner Dispatch (D1, AT-513-1)
- In `scripts/placement/vm-local/poll.sh`, execute `run.sh` as an asynchronous background subshell (`( ... ) &`) across fix rounds, first-hop intake, and ladder consumption.
- Resolve the dispatch log path:
  ```bash
  local state_base="${XDG_STATE_HOME:-}"
  [ -z "$state_base" ] && state_base=~/.local/state
  local poll_state_dir="${POLL_STATE_DIR:-${state_base}/sdlc-poller}"
  local poll_log_dir="${POLL_LOG_DIR:-${poll_state_dir}/logs}"
  mkdir -p "$poll_log_dir" 2>/dev/null || true
  local ts
  ts="$(date +%s)"
  local log_file="${poll_log_dir}/dispatch-${item_id}-${ts}.log"
  ```
- Redirect both standard output and standard error of the child runner to `$log_file`:
  ```bash
  (
      "$RUN_SH" "$item_id" --as "$persona"
  ) > "$log_file" 2>&1 &
  ```
- The main polling loop proceeds immediately to candidate evaluation without waiting on child subshell termination.

### P2 · Child Subshell PID Attribution and Claim Session Binding (D2, AT-513-2)
- In `poll.sh`, when dispatching ladder consumption or first-hop intake, invoke `claim.sh` inside the background child subshell.
- Use `CLAIM_SESSION="poll-$BASHPID"` so the claim comment records the actual child process ID:
  ```bash
  (
      local child_pid="$BASHPID"
      if ! GH_TOKEN="$token" CLAIM_ACTOR="$persona" CLAIM_SESSION="poll-$child_pid" "$claim_cmd" "$issue_num"; then
          exit 1
      fi
      "$RUN_SH" "$issue_num" --as "$persona"
  ) > "$log_file" 2>&1 &
  ```
- This ensures the tracker claim comment records: `Claim: <persona> (poll-<pid>), stage: <stage>. Worktree: <path>`.

### P3 · In-Band Claim Reaper Execution (D3, D4, AT-513-3, AT-513-4, AT-513-5)
- In `poll.sh`, define and invoke `reap_stranded_claims` at the top of `poll_tick` before candidate discovery sweeps.
- Load configuration bounds via `scripts/ops/execution.py`:
  - `min_grace`: `python3 "$REPO_ROOT/scripts/ops/execution.py" --loop claim_reaper_min_age_seconds` (default: 60).
  - `max_age`: `python3 "$REPO_ROOT/scripts/ops/execution.py" --loop claim_reaper_max_age_seconds` (default: 7200).
- Query open issues carrying the `in-progress` label (`gh issue list --state open --label in-progress --json number,comments`).
- For each issue:
  1. Inspect the last comment matching `^[[:space:]]*[Cc]laim:`.
  2. Parse the session string `\((poll-[0-9]+)\)`. If missing or if the claim lacks the `poll-` prefix (interactive claim), preserve the claim untouched (D4, AT-513-5).
  3. Extract recorded `<pid>` and compute claim age from comment `createdAt` timestamp.
  4. Liveness check: execute `kill -0 "$pid" 2>/dev/null`.
  5. If `<pid>` is running and claim age < `max_age`, preserve the claim (D4, AT-513-4).
  6. If `<pid>` is dead and claim age >= `min_grace`, OR claim age >= `max_age`: mark claim as stranded and reap.
  7. Reaping: execute worktree/branch reclamation (P4), release the `in-progress` label, and post an explanatory tracking comment noting automated reaping.

### P4 · Safe Worktree and Unmerged Branch Reclamation (D5, AT-513-6)
- Inside the reaper when a stranded claim is reaped:
  1. Parse the declared worktree path and branch name from the claim comment.
  2. If the local branch exists (`git rev-parse --verify "refs/heads/$BRANCH" >/dev/null 2>&1`):
     - Check for unmerged commits: `unmerged_commits="$(git log "origin/main..refs/heads/$BRANCH" --oneline 2>/dev/null || true)"`.
     - If `unmerged_commits` is empty (zero unmerged commits):
       - If worktree exists, remove it: `git worktree remove --force "$wt_path" 2>/dev/null || true`.
       - Delete the local branch: `git branch -D "$BRANCH" 2>/dev/null || true`.
     - If `unmerged_commits` is non-empty:
       - Retain worktree and local branch on disk to preserve unpushed work.
       - Include notice in the posted tracking comment stating the branch was retained with unmerged commits.
  3. Release tracker claim: remove `in-progress` label via `gh issue edit "$issue_num" --remove-label in-progress`.

### P5 · Pre-Claim Merged Branch and Worktree Pruning (D6, AT-513-7)
- Before invoking `claim.sh` for an issue advancing across lifecycle stages:
  1. Determine candidate branch name (e.g. `<persona>/<issue>-<slug>`).
  2. If the local branch exists:
     - Check if branch is fully merged into `origin/main`: `git merge-base --is-ancestor "refs/heads/$BRANCH" "origin/main"`.
     - If true: prune existing worktree (`git worktree remove --force ...`) and delete local branch (`git branch -D "$BRANCH"`).
     - If false: leave branch untouched so `claim.sh` enforces collision refusal, preserving active unmerged review branches.

### P6 · Stage-Filtered First-Hop Intake Concurrency (D7, AT-513-8)
- In `poll.sh`, replace unfiltered Athena counting with claim comment stage parsing:
  ```bash
  active_count="$(jq '
    [
      .[]? |
      [ .comments[]? | select((.body // "") | test("^[[:space:]]*[Cc]laim:")) ] | last |
      select(. != null) |
      select(((.author.login // .user.login // "") | sub("\\[bot\\]$"; "")) == "evekhm-athena-app") |
      select((.body // "") | test("stage:[[:space:]]*intake\\b"; "i"))
    ] | length
  ' <<<"$in_progress_json" 2>/dev/null || echo 0)"
  ```
- Only claims where the last claim comment explicitly specifies `stage: intake` (case-insensitive) increment `active_count` against `max_concurrent_first_hops`. Athena claims on `plan` or `design` are excluded.

### P7 · Execution Configuration and Schema Validation (D8, AT-513-9)
- In `config/execution.yaml`, add keys under `loop:`:
  ```yaml
  loop:
    autonomous_merge: true
    max_rung_dispatches_per_issue: 12
    max_cost_usd_per_issue: 50.00
    max_concurrent_first_hops: 1
    claim_reaper_max_age_seconds: 7200
    claim_reaper_min_age_seconds: 60
  ```
- In `scripts/ops/execution.py`:
  - Update allowed keys set in `check()`:
    `{"autonomous_merge", "max_rung_dispatches_per_issue", "max_cost_usd_per_issue", "max_concurrent_first_hops", "claim_reaper_max_age_seconds", "claim_reaper_min_age_seconds"}`.
  - Add positive integer validations for both reaper keys.

---

## 4. Micro-Stepped Tasks

### Task T1: Commit Hermetic Contract Test Suite in `scripts/ops/tests/poller_claim_lifecycle_contract_test.sh`
- **Owner:** daedalus (Build stage)
- **Files touched:** `scripts/ops/tests/poller_claim_lifecycle_contract_test.sh`
- **Decisions implemented:** D1, D2, D3, D4, D5, D6, D7, D8, D9, D10
- **Acceptance criteria proven:** AT-513-1 through AT-513-10
- **Description:** Implement contract test suite asserting:
  1. Detached background dispatch and per-dispatch log path under `POLL_LOG_DIR`.
  2. Child process subshell PID attribution via `CLAIM_SESSION="poll-$BASHPID"`.
  3. In-band claim reaper execution releasing dead PID claims past min grace period.
  4. Reaper preservation of active claims when recorded PID is running.
  5. Preservation of interactive claims lacking `poll-` session prefix.
  6. Safe worktree and branch deletion for clean branches; preservation when unmerged commits exist.
  7. Pre-claim pruning of merged lifecycle branches.
  8. Stage-filtered intake concurrency ignoring Athena `plan` and `design` claims.
  9. Schema validation for reaper configuration keys in `execution.py` and `execution.yaml`.
  10. Living spec update in `docs/SPEC.md` and changelog entry in `CHANGELOG.md`.

### Task T2: Implement In-Band Claim Reaper and Branch Reclamation in `scripts/placement/vm-local/poll.sh`
- **Owner:** odyssey (Implement stage)
- **Files touched:** `scripts/placement/vm-local/poll.sh`
- **Decisions implemented:** D3, D4, D5
- **Acceptance criteria proven:** AT-513-3, AT-513-4, AT-513-5, AT-513-6
- **Risk tier:** `risk: high` (DEEP-3, DEEP-5: alters claim mutex state and branch deletion logic)
- **Description:** Implement `reap_stranded_claims` function in `poll.sh`. Query open `in-progress` issues, verify PID liveness using `kill -0 "$pid"` for `poll-` session prefixes, evaluate grace and max age bounds, perform safe worktree/branch deletion based on `origin/main` git ancestry, remove `in-progress` label, and post explanatory comment.

### Task T3: Implement Merged Branch and Worktree Pruning Prior to Claim
- **Owner:** odyssey (Implement stage)
- **Files touched:** `scripts/placement/vm-local/poll.sh`
- **Decisions implemented:** D6
- **Acceptance criteria proven:** AT-513-7
- **Risk tier:** `risk: high` (DEEP-3, DEEP-5: modifies pre-claim branch state machine)
- **Description:** Implement pre-claim branch check before invoking `claim.sh`. Check `git merge-base --is-ancestor refs/heads/$BRANCH origin/main`. If the branch has fully merged into `origin/main`, remove the worktree and delete the local branch to allow clean re-claim. Preserve unmerged branches to maintain `claim.sh` refusal.

### Task T4: Implement Detached Background Dispatch and Child PID Attribution
- **Owner:** odyssey (Implement stage)
- **Files touched:** `scripts/placement/vm-local/poll.sh`, `scripts/placement/vm-local/run.sh`
- **Decisions implemented:** D1, D2
- **Acceptance criteria proven:** AT-513-1, AT-513-2
- **Risk tier:** `risk: high` (DEEP-5: concurrency change, background process management)
- **Description:** Wrap `run.sh` invocations across fix rounds, first-hop intake, and ladder consumption into background subshells (`( ... ) &`), redirecting output to `${POLL_LOG_DIR:-${poll_state_dir}/logs}/dispatch-<issue>-<timestamp>.log`. Inside the child subshell, invoke `claim.sh` with `CLAIM_SESSION="poll-$BASHPID"`. Ensure the primary polling loop continues immediately without awaiting child completion.

### Task T5: Implement Stage-Filtered First-Hop Intake Concurrency
- **Owner:** odyssey (Implement stage)
- **Files touched:** `scripts/placement/vm-local/poll.sh`
- **Decisions implemented:** D7
- **Acceptance criteria proven:** AT-513-8
- **Description:** Update `active_count` jq filter in `poll.sh` intake evaluation to parse declared stage from last claim comment. Count only claims specifying `stage: intake` (case-insensitive). Exclude Athena claims on `plan` or `design` rungs.

### Task T6: Configure Reaper Limits in `config/execution.yaml` and Validate in `scripts/ops/execution.py`
- **Owner:** odyssey (Implement stage)
- **Files touched:** `config/execution.yaml`, `scripts/ops/execution.py`
- **Decisions implemented:** D8
- **Acceptance criteria proven:** AT-513-9
- **Description:** Add `claim_reaper_max_age_seconds: 7200` and `claim_reaper_min_age_seconds: 60` under `loop:` in `config/execution.yaml`. Update `check()` in `scripts/ops/execution.py` to allow and validate these keys as positive integers.

### Task T7: Add Unit and Regression Test Suite in `scripts/ops/tests/poll_test.sh`
- **Owner:** odyssey (Implement stage)
- **Files touched:** `scripts/ops/tests/poll_test.sh`
- **Decisions implemented:** D1, D2, D3, D4, D5, D6, D7
- **Acceptance criteria proven:** AT-513-1 through AT-513-8
- **Description:** Implement comprehensive unit and regression tests for `poll.sh`: testing detached background execution, child PID claim attribution, reaper liveness and grace timeout evaluation, safe worktree removal, unmerged branch retention, pre-claim merged branch pruning, and stage-filtered intake concurrency.

### Task T8: Update Living Spec in `docs/SPEC.md` and Changelog in `CHANGELOG.md`
- **Owner:** odyssey (Implement stage)
- **Files touched:** `docs/SPEC.md`, `CHANGELOG.md`
- **Decisions implemented:** D9, D10
- **Acceptance criteria proven:** AT-513-10
- **Description:** Update `docs/SPEC.md` documenting background poller execution, reaper semantics, branch pruning, and stage-filtered intake concurrency. Add entry to `CHANGELOG.md` describing bug fix for issue #513. Verify with `scripts/ci/spec_check.sh` and `scripts/ci/changelog_check.sh`.

### Task T9: Verify All CI Gates and Turn Contract Tests Green
- **Owner:** odyssey (Implement stage)
- **Files touched:** none
- **Decisions implemented:** all
- **Acceptance criteria proven:** AT-513-1 through AT-513-10
- **Description:** Execute `bash scripts/ops/tests/poller_claim_lifecycle_contract_test.sh` and verify all 10 assertions pass (green). Execute `scripts/ci/sanitize_check.sh`, `python3 scripts/ops/execution.py --check`, and regression suites. Open implementation PR with `deep-review` grant.
