# Plan: Gated and Bounded VM Poller Intake, Reviewer Trigger Isolation, and Lock Relocation

**Issue:** #295 · **Spec:** spec.md (Approved, D1–D11, SA-1..SA-11) ·
**Author:** daedalus (`evekhm-daedalus-app[bot]`) ·
**Base commit:** `f29067b`

Eight tasks. Each names the files it touches, the steps in order, the
Decision rows it implements, the acceptance tests it proves, and its
done-when. **Implement on top of `origin/main` at the SHA the dispatcher
pins; this plan was verified at `f29067b`.** Every `file:line` below was
re-read at that commit.

Order of work:
1. T1: Contract test suite updates in `scripts/ci/tests/e2e_chain_test.sh` (Build rung deliverable; all 3 new/modified scenarios red)
2. T2: Schema validation and configuration in `scripts/ops/execution.py`, `config/execution.yaml`, and `scripts/ops/tests/execution_test.sh`
3. T3: Tracker bootstrap label provisioning in `scripts/setup/bootstrap_tracker.sh` and `scripts/setup/issues/04-label-taxonomy.md`
4. T4: Master autonomy gate in `scripts/placement/vm-local/poll.sh`
5. T5: First-hop concurrency ceiling and backlog intake filter in `scripts/placement/vm-local/poll.sh`
6. T6: Fix-round state directory relocation and reviewer-only trigger in `scripts/placement/vm-local/poll.sh`
7. T7: Living spec alignment in `docs/SPEC.md`
8. T8: Integration verification and CI gate checks

The implement rung branch MUST be named `odyssey/295-poller-intake-gate`
because `lifecycle_advance.sh:27-34` matches candidate pull requests by
verifying that the head branch slug equals the intent folder slug
(`295-poller-intake-gate`).

---

## The Ten Calls This Plan Makes

The spec and review notes left these design details to the plan. Each is
decided here; the implementer does not re-open them.

**P1 · Master autonomy gate in `poll.sh` (D2, SA-3).**
At the beginning of each polling tick in `poll.sh` (before evaluating fix
rounds, first-hop intake, or ledger dispatch rows):
Check the autonomy setting via:
`python3 "$REPO_ROOT/scripts/ops/execution.py" --loop autonomous_merge`
If exit status is non-zero or stdout is not `"true"`:
Log `poll.sh: autonomous_merge is not true; idling queues` exactly once per
tick and return 0 / sleep until the next tick. When invoked with `--once`,
log the notice and exit 0 without processing any queues.

**P2 · Fleet concurrency ceiling for first-hop intake in `poll.sh` (D3, SA-5).**
Before discovering or launching candidate `intent:new` issues in `poll.sh`:
1. Read the ceiling value:
   `limit="$(python3 "$REPO_ROOT/scripts/ops/execution.py" --loop max_concurrent_first_hops 2>/dev/null || echo 1)"`
2. Query open issues carrying `in-progress`:
   `gh issue list --state open --label in-progress --json number,comments`
3. For each issue, inspect comments in chronological order to find the
   latest comment matching `^[[:space:]]*[Cc]laim:`.
4. Extract the author login using normalization:
   `(.author.login // .user.login // "")` with any trailing `[bot]` suffix
   stripped (`s/\[bot\]$//`).
5. Compare against `evekhm-athena-app`.
6. Count total matching active claims across all rungs (Verifier N6).
7. If active count >= limit: log
   `poll.sh: first-hop intake concurrency limit reached (<count>/<limit>), skipping intake`
   and skip first-hop intake for that tick.

**P3 · Opt-in backlog admission filter `intake:auto` (D4, SA-5).**
In `poll.sh`, candidate discovery for first-hop intake requires both
`intent:new` and `intake:auto`:
`gh issue list --state open --label "intent:new" --label "intake:auto" --json number,title,labels`
Issues carrying `intent:new` without `intake:auto` are never selected for
automated intake. When an issue is selected, `poll.sh` claims it via
`CLAIM_ACTOR=athena scripts/ops/claim.sh <n>` and launches
`run.sh <n> --as athena` without ledger rows.
`intake:auto` is provisioned in `scripts/setup/bootstrap_tracker.sh` with
color `#C2E0C6` and documented in `scripts/setup/issues/04-label-taxonomy.md`.

**P4 · State directory and lock relocation `POLL_STATE_DIR` (D5, SA-6).**
Relocate per-PR lock files and consumption key files to `POLL_STATE_DIR`:
```bash
local state_base="${XDG_STATE_HOME:-}"
[ -z "$state_base" ] && state_base=~/.local/state
local poll_state_dir="${POLL_STATE_DIR:-${state_base}/sdlc-poller}"
mkdir -p "$poll_state_dir" 2>/dev/null || true
```
Lock file path: `local lock_file="${poll_state_dir}/poll-pr-${pr_num}.lock"`
Key file path: `local key_file="${poll_state_dir}/pr-${pr_num}-${repo_hash}-${key}"`
No lock or key files are created in `/tmp`.
Note on cutover (Verifier N3): moving the key path from `/tmp` to
`POLL_STATE_DIR` causes each open PR to redispatch one fix round upon
restart. This is bounded and expected.

**P5 · Reviewer-only identity restriction for fix rounds (D6, SA-7, Advisor comment 5607980229, Verifier comment 5607944803).**
The D6 task implements the exact suffixed match (`evekhm-argus-app[bot]` or
`evekhm-atlas-app[bot]`), as `poll.sh:162-163` already does today, and cites
this row and comment 5607944803. The `(.author.login // .user.login // "")`
normalization with the suffix stripped stays confined to D3, whose surface
is `gh issue list --json comments` (GraphQL, no suffix). D3 and D6 read
different surfaces.
In `poll.sh`:
Remove author-agnostic matcher `select((.body // "") | contains("review findings: blocking"))`.
A comment triggers fix-round dispatch ONLY if:
1. `.user.login` is `"evekhm-argus-app[bot]"` or `"evekhm-atlas-app[bot]"`.
2. The body contains `"review findings: blocking"` OR matches structured
   verdict `<!-- review-verdict:...:findings -->` with open findings
   `<!-- finding:[^:]+:(security|high):open:`.
Comments from non-reviewer logins (e.g. `malicious-user` or unsuffixed
`evekhm-argus-app`) containing those strings are ignored.

**P6 · Independent lock contention verification in AT-20 (D7, SA-8).**
In `scripts/ci/tests/e2e_chain_test.sh` row AT-20:
Before tick 2, remove the consumption key `rm -f "$poll_state_dir"/pr-4242-*`.
Touch `$lock_file` and run tick 2.
Assert that the launch log is identical to tick 1, proving `lock_file`
independently prevents duplicate launches under contention even when no key
file is present.

**P7 · Grep option parsing portability in AT-13 (D8, SA-9).**
In `scripts/ci/tests/e2e_chain_test.sh:1310` (row AT-13):
Change `grep -q "--> odyssey" <<<"$out"` to
`grep -q -- "--> odyssey" <<<"$out"`, ensuring compatibility across GNU grep,
BSD grep, and ugrep.

**P8 · Central configuration and validation for `max_concurrent_first_hops` (D3, SA-4).**
In `config/execution.yaml`: add `max_concurrent_first_hops: 1` under `loop:`.
In `scripts/ops/execution.py`:
Amend the closed `loop:` allowlist:
`{"autonomous_merge", "max_rung_dispatches_per_issue", "max_cost_usd_per_issue", "max_concurrent_first_hops"}`.
Validate `max_concurrent_first_hops` as a positive integer:
`isinstance(mcfh, int) and not isinstance(mcfh, bool) and mcfh > 0`.
Add hermetic test scenarios to `scripts/ops/tests/execution_test.sh`.

**P9 · Living spec alignment (D9, D10, SA-10, SA-11).**
In `docs/SPEC.md ## Deployment status`:
Annotate step 2 of the 7-step checklist to record that supervisor startup
prior to the autonomy flip is safe because `poll.sh` idles all queues
whenever `loop.autonomous_merge: false`.
In `docs/SPEC.md ### lifecycle.labels`:
Document that claim holder login derivation in
`scripts/ci/lifecycle_advance.sh:1076` derives author identity via
`(.author.login // .user.login // "")` supporting both GraphQL and REST shapes.
In `docs/SPEC.md ### loop.autonomous`:
Document poller intake gate, first-hop concurrency ceiling, and state dir.
In `docs/SPEC.md ### config.execution`:
Document `max_concurrent_first_hops`.

**P10 · Manifest of touched files and strict boundaries (D11, SA-1).**
Strict file manifest for the implementation PR:
- `scripts/placement/vm-local/poll.sh`
- `scripts/ops/execution.py`
- `config/execution.yaml`
- `scripts/ci/tests/e2e_chain_test.sh`
- `scripts/ops/tests/execution_test.sh`
- `scripts/setup/bootstrap_tracker.sh`
- `scripts/setup/issues/04-label-taxonomy.md`
- `docs/SPEC.md`
- `intent/295-poller-intake-gate/plan.md`
The following files are strictly prohibited from modification:
`scripts/ci/escalate.sh`, `.github/workflows/lifecycle.yml`,
`scripts/ci/merge_gate.sh`, `scripts/ops/claim.sh`, `scripts/ops/work.sh`,
`personas/**`.

---

## Traceability Matrix

### Decision Rows

- **D1**: Amendment target and supersession structure (amends #251 and #64 D20).
  - Tasks: T1, T2, T8
- **D2**: Master autonomy gate via `execution.py --loop autonomous_merge`.
  - Tasks: T1, T4, T8
- **D3**: Fleet concurrency ceiling `max_concurrent_first_hops` and Athena claim counting.
  - Tasks: T1, T2, T5, T8
- **D4**: Opt-in backlog admission filter `intake:auto`.
  - Tasks: T1, T3, T5, T8
- **D5**: Relocation of lock and key files to `POLL_STATE_DIR`.
  - Tasks: T1, T6, T8
- **D6**: Reviewer-only identity restriction for fix-round trigger comments.
  - Tasks: T1, T6, T8
- **D7**: Independent verification of lock contention in AT-20.
  - Tasks: T1, T6, T8
- **D8**: Portability of grep option parsing in AT-13 (`grep -q -- "--> odyssey"`).
  - Tasks: T1, T8
- **D9**: Enablement checklist update in `docs/SPEC.md ## Deployment status`.
  - Tasks: T1, T7, T8
- **D10**: Normative specification of dual GraphQL/REST claim author fields in `docs/SPEC.md`.
  - Tasks: T1, T7, T8
- **D11**: Scope boundary and manifest.
  - Tasks: T1 through T8

### Acceptance Criteria

- **SA-1 (D1, D11)**: Pre-merge validation checks exit 0 (`spec_check.sh`, `sanitize_check.sh`).
  - Tasks: T8
- **SA-2 (D2)**: `bash -n scripts/placement/vm-local/poll.sh` exits 0; AT-8, AT-15, AT-20 pass with `autonomous_merge: true`.
  - Tasks: T1, T4, T8
- **SA-3 (D2)**: AT-21: `poll.sh --once` with `loop.autonomous_merge: false` logs idling notice, performs zero dispatches across all queues, and exits 0.
  - Tasks: T1, T4, T8
- **SA-4 (D3, D11)**: `execution.py --check` passes with `loop.max_concurrent_first_hops: 1`, fails on invalid values, and `--loop max_concurrent_first_hops` outputs `1`.
  - Tasks: T2, T8
- **SA-5 (D3, D4)**: AT-22: `intent:new` without `intake:auto` skipped (a); `intent:new` with `intake:auto` claimed and launched below ceiling (b); GraphQL claim normalization (c); REST claim normalization (c); ceiling refusal logged and launch skipped (d).
  - Tasks: T1, T3, T5, T8
- **SA-6 (D5)**: AT-20 creates lock file under `${POLL_STATE_DIR:-...}` and no lock in `/tmp`.
  - Tasks: T1, T6, T8
- **SA-7 (D6)**: AT-20: comment with `review findings: blocking` from non-reviewer login (`malicious-user` or unsuffixed `evekhm-argus-app`) triggers zero calls to `run.sh`.
  - Tasks: T1, T6, T8
- **SA-8 (D7)**: AT-20 removes `key_file` before tick 2; `touch "$lock_file"` independently prevents duplicate launches.
  - Tasks: T1, T6, T8
- **SA-9 (D8)**: AT-13: `grep -q -- "--> odyssey"` passes under GNU grep and ugrep.
  - Tasks: T1, T8
- **SA-10 (D9)**: `docs/SPEC.md ## Deployment status` documents early supervisor startup safety under step 2.
  - Tasks: T7, T8
- **SA-11 (D10)**: `docs/SPEC.md` records dual-surface claim author normalization `(.author.login // .user.login // "")`.
  - Tasks: T7, T8

---

## Detailed Implementation Tasks

### T1 · Hermetic Contract Tests (Build Rung Deliverable)
- **Files touched:** `scripts/ci/tests/e2e_chain_test.sh`
- **Decisions:** D1, D2, D3, D4, D5, D6, D7, D8, D11
- **Acceptance:** SA-2, SA-3, SA-5, SA-6, SA-7, SA-8, SA-9
- **Description:**
  1. Update `gh` stub in `e2e_chain_test.sh` to handle multiple `--label` options in `issue list` queries, matching issues having all requested labels.
  2. Fix AT-13 grep portability at line 1310: change `grep -q "--> odyssey"` to `grep -q -- "--> odyssey"` (D8, SA-9).
  3. Update existing fixtures in AT-8, AT-14, AT-15, and AT-20 to provide `echo "true" > "$FIXTURES/loop-autonomous_merge"`, and add `intake:auto` label to the candidate issue in AT-15 (D2, D4, SA-2).
  4. Update AT-20:
     - Relocate lock and key files to `$poll_state_dir` via `POLL_STATE_DIR` (D5, SA-6).
     - Verify no lock file is created in `/tmp` (D5, SA-6).
     - Clear consumption key before tick 2: `rm -f "$poll_state_dir"/pr-4242-*` and touch `$lock_file` to independently verify lock contention prevents duplicate launch (D7, SA-8).
     - Add sub-cases asserting that comments with `review findings: blocking` from non-reviewer logins (`malicious-user` and unsuffixed `evekhm-argus-app`, citing comment 5607944803) trigger zero launches and zero claims (D6, SA-7).
  5. Add AT-21 scenario asserting master autonomy gate:
     - Set `loop.autonomous_merge: false`.
     - Seed candidate work across all three queues: fix round candidate PR 4242, first-hop candidate issue 300 (with `intent:new` and `intake:auto`), and ledger dispatch candidate issue 251.
     - Execute `poll.sh --once`.
     - Assert exit 0, stdout contains `poll.sh: autonomous_merge is not true; idling queues`, zero dispatches occur in `$LAUNCHES`, and zero claims occur in `$CLAIMS` (D2, SA-3).
  6. Add AT-22 scenario asserting first-hop backlog intake filter and fleet concurrency ceiling:
     - Sub-case (a): candidate issue with `intent:new` lacking `intake:auto` produces zero claims and zero launches (D4, SA-5).
     - Sub-case (b): candidate issue with both `intent:new` and `intake:auto` under ceiling produces single claim and launch for athena (D4, SA-5).
     - Sub-case (c): active Athena claim counting normalizes GraphQL shape `.author.login` without `[bot]`, and REST shape `.user.login` with `[bot]`; when active Athena claim equals `max_concurrent_first_hops: 1`, candidate intake launch is refused, logging `first-hop intake concurrency limit reached` (D3, SA-5).
- **Done when:** `bash scripts/ci/tests/e2e_chain_test.sh` runs cleanly without syntax errors and reports: `15 passed, 3 failed out of 18 run` (AT-20, AT-21, and AT-22 failing cleanly due to absence of implementation code).

### T2 · Execution Schema Allowlist & Validation (D1, D3, SA-4)
- **Files touched:** `scripts/ops/execution.py`, `config/execution.yaml`, `scripts/ops/tests/execution_test.sh`
- **Decisions:** D1, D3, D11
- **Acceptance:** SA-4
- **Description:**
  1. In `scripts/ops/execution.py`:
     - In `check(config)` at line 137, add `"max_concurrent_first_hops"` to the `loop:` allowed keys set:
       `unknown = sorted(set(loop) - {"autonomous_merge", "max_rung_dispatches_per_issue", "max_cost_usd_per_issue", "max_concurrent_first_hops"})`
     - Validate `max_concurrent_first_hops`:
       ```python
       mcfh = loop.get("max_concurrent_first_hops")
       if mcfh is not None:
           if isinstance(mcfh, bool) or not isinstance(mcfh, int) or mcfh <= 0:
               fail("loop.max_concurrent_first_hops must be positive integer")
       ```
  2. In `config/execution.yaml`:
     - Under `loop:`, add `max_concurrent_first_hops: 1`.
  3. In `scripts/ops/tests/execution_test.sh`:
     - Add test scenarios verifying:
       - `python3 scripts/ops/execution.py --check` passes on committed `config/execution.yaml`.
       - `python3 scripts/ops/execution.py --loop max_concurrent_first_hops` prints `1` with exit 0.
       - A fixture with `max_concurrent_first_hops: 0`, `-1`, or `"non-int"` fails `--check` with exit 1 and expected error message.
- **Done when:** `bash scripts/ops/tests/execution_test.sh` exits 0 with all scenarios passing.

### T3 · Backlog Admission Label Provisioning (D4, SA-5)
- **Files touched:** `scripts/setup/bootstrap_tracker.sh`, `scripts/setup/issues/04-label-taxonomy.md`
- **Decisions:** D4, D11
- **Acceptance:** SA-5
- **Description:**
  1. In `scripts/setup/bootstrap_tracker.sh`:
     - Add `intake:auto` to the label provisioning list with color `#C2E0C6` and description `"Opt-in for automated first-hop poller intake"`.
  2. In `scripts/setup/issues/04-label-taxonomy.md`:
     - Document the `intake:auto` label under intake and poller controls.
- **Done when:** `bash -n scripts/setup/bootstrap_tracker.sh` exits 0 and `grep -q "intake:auto" scripts/setup/issues/04-label-taxonomy.md` exits 0.

### T4 · Master Autonomy Gate in VM Poller (D2, SA-3)
- **Files touched:** `scripts/placement/vm-local/poll.sh`
- **Decisions:** D2, D11
- **Acceptance:** SA-2, SA-3
- **Description:**
  1. At the beginning of each polling tick in `scripts/placement/vm-local/poll.sh` (before any candidate discovery across fix rounds, first hops, or ledger dispatch rows):
     ```bash
     local auto_merge
     auto_merge="$(python3 "$REPO_ROOT/scripts/ops/execution.py" --loop autonomous_merge 2>/dev/null || echo false)"
     if [ "$auto_merge" != "true" ]; then
         echo "poll.sh: autonomous_merge is not true; idling queues"
         return 0
     fi
     ```
  2. When invoked with `--once`, the poller performs this check, prints the notice if false, and exits 0 without querying GitHub or launching tasks.
- **Done when:** `bash -n scripts/placement/vm-local/poll.sh` exits 0 and AT-21 in `e2e_chain_test.sh` turns green.

### T5 · First-Hop Concurrency Ceiling & Backlog Filter in VM Poller (D3, D4, SA-5)
- **Files touched:** `scripts/placement/vm-local/poll.sh`
- **Decisions:** D3, D4, D11
- **Acceptance:** SA-5
- **Description:**
  1. Update candidate issue discovery in `scripts/placement/vm-local/poll.sh`:
     Filter by both labels `intent:new` and `intake:auto`:
     `gh issue list --repo "$GITHUB_REPO" --state open --label "intent:new" --label "intake:auto" --json number,title,labels`
  2. Before launching candidate `intent:new` issues, query open issues carrying `in-progress`:
     `gh issue list --repo "$GITHUB_REPO" --state open --label "in-progress" --json number,comments`
  3. For each open issue, inspect comments in chronological order to find the latest claim comment:
     Extract author login via `(.author.login // .user.login // "")` with any trailing `[bot]` suffix stripped (`s/\[bot\]$//`).
     If matching `evekhm-athena-app`, increment the active Athena claim count.
  4. Compare active Athena count against ceiling:
     `limit="$(python3 "$REPO_ROOT/scripts/ops/execution.py" --loop max_concurrent_first_hops 2>/dev/null || echo 1)"`
     If `active_count >= limit`:
     Log `poll.sh: first-hop intake concurrency limit reached ($active_count/$limit), skipping intake` and skip first-hop processing for that tick.
- **Done when:** AT-22 in `e2e_chain_test.sh` turns green.

### T6 · State Directory Relocation & Reviewer-Only Trigger in VM Poller (D5, D6, D7, SA-6, SA-7, SA-8)
- **Files touched:** `scripts/placement/vm-local/poll.sh`
- **Decisions:** D5, D6, D7, D11
- **Acceptance:** SA-6, SA-7, SA-8
- **Description:**
  1. In `scripts/placement/vm-local/poll.sh`:
     Define state directory:
     ```bash
     local state_base="${XDG_STATE_HOME:-}"
     [ -z "$state_base" ] && state_base=~/.local/state
     local poll_state_dir="${POLL_STATE_DIR:-${state_base}/sdlc-poller}"
     mkdir -p "$poll_state_dir" 2>/dev/null || true
     ```
     Relocate lock file:
     `local lock_file="${poll_state_dir}/poll-pr-${pr_num}.lock"`
     Relocate consumption key file:
     `local key_file="${poll_state_dir}/pr-${pr_num}-${repo_hash}-${key}"`
     Ensure no references to `/tmp/poll-pr-*.lock` or `/tmp/pr-*.key` remain.
  2. Implement reviewer-only trigger restriction:
     The D6 task implements the exact suffixed match (`evekhm-argus-app[bot]` or
     `evekhm-atlas-app[bot]`), as `poll.sh:162-163` already does today, and cites
     this row and comment 5607944803. The `(.author.login // .user.login // "")`
     normalization with the suffix stripped stays confined to D3, whose surface
     is `gh issue list --json comments` (GraphQL, no suffix). D3 and D6 read
     different surfaces.
     In `poll.sh`, replace the trigger selection jq expression with:
     ```jq
     [
       .[]? |
       select(
         ((.user.login // "") == "evekhm-argus-app[bot]" or (.user.login // "") == "evekhm-atlas-app[bot]") and
         (
           ((.body // "") | contains("review findings: blocking")) or
           (
             ((.body // "") | test("<!-- review-verdict:[^:]+:findings -->")) and
             ((.body // "") | test("<!-- finding:[^:]+:(security|high):open:"))
           )
         )
       )
     ] | last | .body // empty
     ```
     This strictly ignores any comment authored by non-reviewer logins (e.g.
     `malicious-user` or unsuffixed `evekhm-argus-app`).
- **Done when:** AT-20 in `e2e_chain_test.sh` turns green.

### T7 · Living Spec Alignment (D9, D10, SA-10, SA-11)
- **Files touched:** `docs/SPEC.md`
- **Decisions:** D9, D10, D11
- **Acceptance:** SA-10, SA-11
- **Description:**
  1. In `docs/SPEC.md ## Deployment status`:
     Update step 2 of the 7-step checklist to record that supervisor startup
     prior to the autonomy flip is safe because `poll.sh` idles all queues
     whenever `loop.autonomous_merge: false`.
  2. In `docs/SPEC.md ### lifecycle.labels`:
     Document that claim holder login derivation in
     `scripts/ci/lifecycle_advance.sh:1076` derives author identity via
     `(.author.login // .user.login // "")` supporting both GraphQL and REST shapes.
  3. In `docs/SPEC.md ### loop.autonomous`:
     Document poller intake gating (`intent:new` + `intake:auto`), first-hop
     concurrency ceiling (`loop.max_concurrent_first_hops`), and state directory
     relocation (`POLL_STATE_DIR`).
  4. In `docs/SPEC.md ### config.execution`:
     Document `max_concurrent_first_hops` under the `loop:` block.
- **Done when:** `grep -q "max_concurrent_first_hops" docs/SPEC.md` exits 0.

### T8 · Integration Verification & Pre-Merge Gate Checks (D1–D11, SA-1..SA-11)
- **Files touched:** none (validation only)
- **Decisions:** D1 through D11
- **Acceptance:** SA-1 through SA-11
- **Description:**
  Run the complete verification suite:
  1. `bash scripts/ci/tests/e2e_chain_test.sh` (all 18 scenarios PASS).
  2. `python3 scripts/ops/execution.py --check` exits 0.
  3. `bash scripts/ops/tests/execution_test.sh` exits 0.
  4. `bash scripts/ci/sanitize_check.sh` exits 0.
  5. `BODY_FILE="$(mktemp)"; echo "Spec-impact: docs/SPEC.md updated for poller intake gate" > "$BODY_FILE"; bash scripts/ci/spec_check.sh origin/main "$BODY_FILE"; rm -f "$BODY_FILE"` exits 0.
- **Done when:** All test suites and pre-merge checks exit 0.

---

## Gates Table

| Gate / Test Suite | Command | Scope | Build Rung Status | Implement Rung Expectation |
|---|---|---|---|---|
| Contract Suite | `bash scripts/ci/tests/e2e_chain_test.sh` | Acceptance AT-1..AT-10, AT-12..AT-15, AT-17, AT-20, AT-21, AT-22 | FAIL (15 passed, 3 failed out of 18 run) | PASS (all 18 scenarios pass) |
| Execution Gate | `python3 scripts/ops/execution.py --check` | Central execution configuration validation | PASS | PASS |
| Execution Suite | `bash scripts/ops/tests/execution_test.sh` | Execution model schema and flag validation | PASS | PASS (includes SA-4 ceiling scenarios) |
| Advancer Suite | `bash scripts/ci/tests/lifecycle_advance_test.sh` | Lifecycle state transitions | PASS | PASS |
| Work Suite | `bash scripts/ops/tests/work_test.sh` | Dispatch and stage resolution | PASS | PASS |
| Claim Suite | `bash scripts/ops/tests/claim_test.sh` | Mutex and claim validation | PASS | PASS |
| Sanitize Gate | `bash scripts/ci/sanitize_check.sh` | Security and secret scan | PASS | PASS |
| Spec Gate | `bash scripts/ci/spec_check.sh origin/main <body-file>` | Living spec impact check | PASS (`Spec-impact: none - intent/** only, not a behavior-bearing path`) | PASS (`Spec-impact: docs/SPEC.md updated...`) |
| Shellcheck | `shellcheck -S warning scripts/ci/tests/e2e_chain_test.sh` | Shell script static analysis | PASS | PASS |

Note: At the build rung, AT-20, AT-21, and AT-22 in `e2e_chain_test.sh` fail
cleanly because the implementation code in `poll.sh` and `execution.py` has not
yet been introduced. No errors or broken test setups occur.

---

## Implementation Sync

Implemented by Odyssey under issue #295 with two deviations:
- Task T1 was delivered at the build rung by Daedalus rather than during the implementation phase.
- Task T7 diverged from SA-11 in the initial push by attributing dual-shape normalization to work.sh instead of citing lifecycle_advance.sh:1076.
- Master autonomy gate idles queues when `loop.autonomous_merge` is false (D2).
- First-hop intake gated on `intake:auto` and capped by `max_concurrent_first_hops` (D3, D4).
- Lock and consumption key paths relocated to `POLL_STATE_DIR` without `/tmp` access (D5).
- Fix-round triggers strictly isolate suffixed reviewer App logins `evekhm-argus-app[bot]` and `evekhm-atlas-app[bot]` (D6).
- All 19 contract scenarios in `e2e_chain_test.sh` pass.
