# Plan: the loop merges itself; the human is the escalation path

**Issue:** #64 · **Spec:** spec.md (Approved, D1-D22, AT-1..AT-24) · **Author:** daedalus (`evekhm-daedalus-app[bot]`)

Eight tasks. Each names the files it touches, the steps in order, the Decision rows it implements, the acceptance tests it makes pass, and its done-when. **Implement on top of `origin/main` at the SHA the dispatcher pins; this plan was verified at `bf78de9`.** Every `file:line` below was re-read at that commit.

Order: T1 (tests, all red) → T2 (config and parser) → T3 (permissions and workflow) → T4 (escalation script) → T5 (merge gate) → T6 (lifecycle advancer) → T7 (doc repairs) → T8 (gates).

## The calls this plan makes

**P1 · Merge gate ledger dependency:** As D5 conjuncts (3), (4), (5), and (11) rely on the recorder (#8/#9) which is not yet merged, `merge_gate.sh` parses `gh issue comments` for the loop ledger and `review-stuck` marker, but explicitly fails closed for the consensus ledger if it's missing (which it will be until #8/#9 lands).

## T1 · The acceptance suite

Touch: `scripts/ci/tests/merge_gate_test.sh`, `scripts/ops/tests/execution_test.sh`

1. **`merge_gate_test.sh`**: Create a new hermetic test file with a stub `gh` (to avoid network) and stubs for `claude`, `gemini`, `agy`, `curl` that exit 1 if called. Add scenarios for:
   - Dry-run mode avoiding mutations.
   - All 11 D5 conjuncts holding producing a merge call.
   - Each conjunct failing producing a distinct decline reason.
   - Unevaluable conjuncts fail closed.
   - Fork head check.
   - Reviewer verdicts covering older heads failing.
   - `Status: Draft` failing for prose artifacts, and `implement` rung passing vacuously.
   - Identical logic for prose vs code rungs.
   - Stale peer escalating.
   - Human mention resets deadline once.
   - Escalation idempotent swapping `status:*` and writing exactly one comment.
   - Restore of displaced label when consensus reached.
   - Escalation per item (no dependencies touched).
   - `hold` and `blocked` preventing merge immediately.
   - Loop bounds logic (`max_rung_dispatches`, `max_cost_usd_per_issue`) failing cleanly.
   - Monotonic progress violation producing `non-monotonic` refusal row and calling `escalate.sh` once in the same run.
   - Adapter invoked exactly once.
   - Flag `loop.autonomous_merge: false` skips merge and dispatch.
2. **`execution_test.sh`**: Add scenarios checking that `loop:` top-level block is parsed correctly, `max_rung_dispatches_per_issue` must be positive integer, `trigger: ladder` requires no events.

**Decisions:** D3, D5-D18.
**Acceptance:** AT-1 to AT-16, AT-18, AT-23, AT-24.
**Done when:** Both test files fail on the new logic, with no existing tests regressing.

## T2 · Config Schema and Parser

Touch: `config/execution.yaml`, `scripts/ops/execution.py`

1. **`config/execution.yaml`**:
   - Add `loop:` block with `autonomous_merge: false`, `max_rung_dispatches_per_issue: 12`, `max_cost_usd_per_issue: 50.00`.
   - Change `trigger: manual` to `trigger: ladder` for `athena`, `daedalus`, `odyssey`.
2. **`scripts/ops/execution.py`**:
   - `load()`: allow `loop` top-level key alongside `personas`.
   - `check()`: validate `loop:` block keys and types.
   - `TRIGGERS`: add `"ladder"`.
   - Ensure `"ladder"` binding carries no `events`.
   - Add `--loop <key>` argument to print the specified loop config value.
   - Document the D20 supersession in the docstring.

**Decisions:** D20, D13, D16, D18.
**Acceptance:** AT-17, AT-24.
**Done when:** `execution_test.sh` passes completely.

## T3 · Permissions and Workflow

Touch: `scripts/auth/app_manifests.yaml`, `.github/workflows/merge-gate.yml`

1. **`scripts/auth/app_manifests.yaml`**:
   - Add an entry for `merge-actor` (not a persona) with `MERGE_ACTOR_APP_PRIVATE_KEY` mapping to `contents: write`, `pull_requests: write`, `issues: write`, `checks: read`, `statuses: read`.
2. **`.github/workflows/merge-gate.yml`**:
   - Create workflow triggering on `pull_request`, `check_suite: completed`, `status`, `issue_comment: created`, `workflow_dispatch`.
   - Request the 5 required permissions.
   - Action runs `scripts/ci/merge_gate.sh` passing `MERGE_ACTOR_APP_PRIVATE_KEY`.

**Decisions:** D3, D4.
**Acceptance:** AT-19.
**Done when:** The workflow parses correctly and YAML is valid.

## T4 · Escalation Writer

Touch: `scripts/ci/escalate.sh`

1. **`scripts/ci/escalate.sh`**:
   - Create script parsing args: `<issue> --reason <reason-code> --head <oid> [--pr <n>]`.
   - Fetches comments. If a marker `<!-- escalation:<displaced-label>:<reason-code>:<head-oid> -->` exists, exit 0 green (idempotent).
   - If issue carries `status:review-stuck`, `<displaced-label>` in new marker is empty.
   - Else, `<displaced-label>` is the current `status:*` label.
   - Runs `gh issue edit` to swap the old `status:*` label for `status:review-stuck` in one call.
   - Posts comment with summary and marker.

**Decisions:** D8, D9, D10, D22.
**Acceptance:** AT-10 (part).
**Done when:** `escalate.sh` successfully swaps labels and posts correct marker.

## T5 · Merge Gate

Touch: `scripts/ci/merge_gate.sh`

1. **`scripts/ci/merge_gate.sh`**:
   - Create script checking the 11 D5 conjuncts deterministically (no model calls, supports `DRY_RUN=1`).
   - Retrieves loop limits via `execution.py --loop max_rung_dispatches_per_issue` and `--loop max_cost_usd_per_issue`. Fails closed if missing/unreadable.
   - Fetches review state, check suites, PR labels. Immediately aborts if `hold` or `blocked` are present on PR or its issue (D15).
   - Evaluates escalation self-clearing (D10) by checking live markers.
   - If D5 conjuncts pass and `execution.py --loop autonomous_merge` is `true`: calls merge API, writes loop-ledger row.
   - If `autonomous_merge` is `false`: writes loop-ledger row but skips merge API call.
   - If consensus times out or blocks, delegates to `scripts/ci/escalate.sh` (D9, D8).
   - Checks trusted writers (D22) when reading the ledger.

**Decisions:** D1-D3, D5-D8, D10-D13, D15, D18, D22.
**Acceptance:** AT-1..9, AT-11..14, AT-18.
**Done when:** `merge_gate_test.sh` passes all scenarios related to the merge gate.

## T6 · Lifecycle Advancer

Touch: `scripts/ci/lifecycle_advance.sh`, `.github/workflows/lifecycle.yml`

1. **`scripts/ci/lifecycle_advance.sh`**:
   - Read bounds via `execution.py --loop`. Fail closed if invalid.
   - Read loop-ledger to assert monotonic progress (D14). If the new transition index is strictly less than the ledger's highest merged index, write a refusal row with `reason-code: non-monotonic` to the ledger, skip writing `status:*`, and echo a recognizable failure message to stderr to trigger escalation.
   - Do NOT run dispatch if `execution.py --loop autonomous_merge` is `false` (D18) or if `trigger` is not `ladder` (D16).
   - If allowed, use `scripts/ops/execution.py --binding <persona>` to find adapter and run `scripts/placement/<name>/run.sh <issue>`.
   - Do not dispatch for the review rung (D17).
2. **`.github/workflows/lifecycle.yml`**:
   - Update permissions to include `issues: write`.
   - Add a step to invoke `scripts/ci/escalate.sh` when `lifecycle_advance.sh` exits reporting a non-monotonic refusal.

**Decisions:** D14, D16-D18.
**Acceptance:** AT-15, AT-16, AT-23.
**Done when:** `merge_gate_test.sh` passes all remaining scenarios.

## T7 · Doc Repairs

Touch: `docs/SPEC.md`, `AGENTS.md`, `INTENT.md`, `README.md`, `REVIEW.md`

1. **`docs/SPEC.md`**: Add `loop.autonomous` bullet citing this issue's PR. Re-word `lifecycle.labels` stating the ladder is driven by system merges. Record D20's supersession.
2. **`AGENTS.md`**:
   - `:47`: "a bare push is not a delivery; a human merges" -> "a bare push is not a delivery; the system merges it."
   - `:190`: "A human merges. The merge *is* the state transition" -> "The system merges. The merge *is* the state transition".
   - `:239-245`: Adjust text to remove "human merges" as the default.
3. **`INTENT.md`**: Remove the `GATE: human merges` and human merge constraint text.
4. **`README.md`**: `:14`, `:80`, `:220`: Remove references to the human being the sole merge authority and reviewer comment-only.
5. **`REVIEW.md`**: Rewrite the "Merge is the escape hatch" section to state the system merges and human merge is the escape hatch.

**Decisions:** D19, D20.
**Acceptance:** AT-22.
**Done when:** All files are updated and no "human merges" text remains unmodified.

## T8 · Gates Check

Commands to run from the root of the tree:

| # | Command | Expected | Proves |
|---|---|---|---|
| 1 | `bash scripts/ci/tests/merge_gate_test.sh` | exit 0 | AT-1..16, AT-18, AT-23 |
| 2 | `bash scripts/ops/tests/execution_test.sh` | exit 0 | AT-17, AT-24 |
| 3 | `bash scripts/ci/sanitize_check.sh` | exit 0, `PASS` | house rule |
| 4 | `bash scripts/ci/spec_check.sh origin/main <body-file>` | exit 0 | AT-21 |
| 5 | `python3 scripts/sync_agents.py --check` | exit 0 | AT-21 |
| 6 | `python3 scripts/ops/execution.py --check` | exit 0 | AT-21, AT-24 |

**Done when:** All six checks pass green.
