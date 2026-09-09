# Intent: Gated and Bounded VM Poller Intake and Lock Relocation

**Issue:** #295 · **Author:** athena (`evekhm-athena-app[bot]`) · **Status:** Draft

## Problem

At base commit `696f516239efaa8d9c63592354a08fc398b410f4` on 2026-09-09, the implementation of #251 (merged in PR #294 at `dc0010bd`) and the autonomy flip (merged in PR #297 at `6c7d71c`) leave seven operational gaps across `scripts/placement/vm-local/poll.sh`, `scripts/ci/tests/e2e_chain_test.sh`, and `intent/251-e2e-chain/spec.md`. Gaps that turn frozen contract rows red require a spec-owner pull request because the implement rung cannot alter its own acceptance criteria.

### 1. Intake ungated by `loop.autonomous_merge`
- **State:** Open in code and in the contract suite.
- In `scripts/placement/vm-local/poll.sh`, `loop.autonomous_merge` is never read (`grep -n autonomous_merge scripts/placement/vm-local/poll.sh` returns no hits).
- In `config/execution.yaml:35`, `loop.autonomous_merge: true` is armed following PR #297.
- Because `poll.sh` lacks flag evaluation logic, intake runs regardless of the flag setting, including when an operator sets `loop.autonomous_merge: false`.
- In `scripts/ci/tests/e2e_chain_test.sh`, rows AT-8, AT-15, and AT-20 provide no `loop-autonomous_merge` fixture and copy no `config/` directory. Gating `poll.sh` directly on `loop.autonomous_merge` turns all three rows red.

### 2. Intake lacks concurrency bounds and backlog filtering
- **State:** Open in code.
- In `scripts/placement/vm-local/poll.sh:240`, `poll.sh` queries `gh issue list --state open --label "intent:new" --json number,title,labels` and launches `run.sh` for every unclaimed issue.
- In `intent/251-e2e-chain/spec.md` D5, `poll.sh` "scans for open, unclaimed `intent:new` issues", and AT-15 asserts a single launch for a discovery list of one.
- The live backlog contains 38 open `intent:new` issues (`gh issue list --label intent:new --state open --limit 100 --json number --jq 'length'` returned 38).
- Existing keys in `config/execution.yaml` (`max_rung_dispatches_per_issue`, `max_cost_usd_per_issue`) constrain per-issue expenditure without bounding concurrent fleet dispatches.

### 3. Fix-round lock path frozen in `/tmp`
- **State:** Open in code and in the contract suite.
- In `scripts/placement/vm-local/poll.sh:188`, `poll_state_dir` defaults to `"${POLL_STATE_DIR:-${TMPDIR:-/tmp}/sdlc-poller}"`. Line 195 hardcodes `local lock_file="${TMPDIR}/poll-pr-${pr_num}.lock"`.
- In `scripts/ci/tests/e2e_chain_test.sh:1608`, AT-20 hardcodes `local lock_file="${TMPDIR:-/tmp}/poll-pr-4242.lock"`.
- Relocating the lock inside `poll.sh` to a user state directory causes AT-20 to fail.

### 4. AT-13 assertion fails under GNU grep
- **State:** Open in the contract suite only.
- In `scripts/ci/tests/e2e_chain_test.sh:1310`, AT-13 asserts `grep -q "--> odyssey" <<<"$out"`.
- GNU grep interprets `-->` as an option flag and exits with an error. The required fix is `grep -q -- "--> odyssey"`.
- Local `grep --version` reports `ugrep 7.8.4` (or ugrep execution), which accepts `-->` without `--`. The failure cannot be reproduced on this VM, while GitHub Actions runners execute GNU grep and fail.

### 5. Fix-round trigger predicate is author-agnostic
- **State:** Open in code and in the contract suite.
- In `scripts/placement/vm-local/poll.sh:157`, the trigger selects `select((.body // "") | contains("review findings: blocking"))` from any comment author. Lines 164-165 restrict recorder markers to `((.user.login // "") == "evekhm-argus-app[bot]" or (.user.login // "") == "evekhm-atlas-app[bot]")`.
- In `scripts/ci/tests/e2e_chain_test.sh:1584`, the AT-20 fixture defines a comment containing `review findings: blocking` without a reviewer author login.

### 6. AT-20 does not test lock contention
- **State:** Open in the contract suite only.
- In `scripts/placement/vm-local/poll.sh:221-228`, dispatch creates a consumption key file `key_file`.
- In `scripts/ci/tests/e2e_chain_test.sh:1624-1631`, AT-20 touches `lock_file` on tick 2 to simulate lock contention. Tick 2 encounters the existing `key_file` and skips dispatch before checking `lock_file`.
- As a consequence, `lock_prevented=1` passes regardless of whether the lock functions.

### 7. Spec D1 text names `.user.login` while reader accepts `.author.login`
- **State:** Open in spec text only.
- In `scripts/ci/lifecycle_advance.sh:1076`, the claim reader extracts `(.author.login // .user.login // "")`, supporting both GraphQL and REST payload shapes.
- In `intent/251-e2e-chain/spec.md:84`, D1 text specifies that the claim holder "is derived by extracting the comment author login (`.user.login`)".

## Proposed outcome

### Originator proposals
1. **Proposal D5a (Gap 1):** `poll.sh` reads `loop.autonomous_merge` through `scripts/ops/execution.py --loop autonomous_merge` and idles dispatch rows, fix rounds, and intake when the value is anything other than `true`, logging one notice per tick. Rows AT-8, AT-15, and AT-20 receive a `loop-autonomous_merge` fixture set to `true`. A new test row asserts zero dispatches when the flag is `false`.
2. **Proposal D5b (Gap 2):** Intake enforces a concurrency limit `loop.max_concurrent_first_hops` (default 1) counted across open `in-progress` issues whose latest claim comment author is `athena`. Intake requires an opt-in label `intake:auto` to arm issues individually. Both parameters are defined in `config/execution.yaml`.
   *Dependency note:* `scripts/ops/execution.py:137-140` enforces an allowlist of three keys under `loop:` (`{"autonomous_merge", "max_rung_dispatches_per_issue", "max_cost_usd_per_issue"}`) and fails on unknown keys. Modifying `execution.py` requires editing a file outside `intent/251-e2e-chain/spec.md` D8's manifest. Additionally, the label `intake:auto` does not exist in the repository (`gh label list -L 100` confirmed live).
3. **Proposal D2a (Gap 3):** The fix-round lock and consumption keys reside under `POLL_STATE_DIR` (default `${XDG_STATE_HOME:-~/.local/state}/sdlc-poller`). Row AT-20 resolves the lock path from `POLL_STATE_DIR`.
4. **Proposal D6a (Gap 1 / D6):** The checklist in `docs/SPEC.md ## Deployment status` moves supervisor startup after the autonomy flip, or documents that D5a makes early supervisor startup safe.
5. **Proposal D8a (Gap 4):** The contract suite remains outside the implement rung's manifest. Contract test defects are repaired by a spec-owner pull request citing the acceptance row, keeping acceptance criteria and implementation separated. Row AT-13 updates to `grep -q -- "--> odyssey"`.

### Additional proposals
6. **Proposal for Gap 5:** Restrict fix-round triggers to verified reviewer identities (`evekhm-argus-app[bot]`, `evekhm-atlas-app[bot]`) and drop the author-agnostic literal phrase `review findings: blocking` from D2 and `poll.sh`. Update the AT-20 test fixture in `scripts/ci/tests/e2e_chain_test.sh` to include a verified reviewer login.
7. **Proposal for Gap 6:** Update AT-20 in `scripts/ci/tests/e2e_chain_test.sh` to clear the consumption key before tick 2, or introduce a separate test row that tests lock contention directly.
8. **Proposal for Gap 7:** Update D1 text in `intent/251-e2e-chain/spec.md` to describe claim holder derivation as `(.author.login // .user.login // "")`, matching `scripts/ci/lifecycle_advance.sh:1076`.

All proposed outcomes are verifiable without model calls.

## Affected users and systems

- **Users:**
  - Operator executing the D6 checklist in `docs/SPEC.md ## Deployment status`.
  - Personas (`athena`, `daedalus`, `odyssey`) dispatched by the VM poller.
  - Reviewers (`argus`, `atlas`) posting review findings read by fix-round triggers.
- **Systems (confirmed present at base SHA `696f516`):**
  - `scripts/placement/vm-local/poll.sh`: consumption queues, lock paths, intake gates, and trigger predicates.
  - `scripts/ci/tests/e2e_chain_test.sh`: contract suite containing rows AT-8, AT-13, AT-15, and AT-20.
  - `scripts/ci/lifecycle_advance.sh`: claim reader supporting `.author.login` and `.user.login`.
  - `scripts/ops/execution.py`: validator and accessor for `config/execution.yaml`.
  - `config/execution.yaml`: loop configuration and placement bindings.
  - `docs/SPEC.md ## Deployment status`: operator enablement checklist.
  - `intent/251-e2e-chain/spec.md`: normative specification amended by this issue.

## Constraints

- **Contract Suite Authority:** The frozen contract suite defines completion for #251's implement rung. Spec-owner pull requests remain the sole vehicle for modifying contract assertions.
- **Single Config Parser:** `scripts/ops/execution.py` is the single parser for `config/execution.yaml` (#64 D20, #25 D2). Introducing new loop keys requires updating the parser allowlist.
- **Autonomy Gate Semantics:** Per #64 D18, safety stops operate independently of the autonomy flag. Gating intake on `loop.autonomous_merge` controls unattended dispatch arming while preserving independent safety stops.
- **Zero Model Overhead:** `poll.sh` operates via bash, gh, and jq on a 30-second interval without model calls (#251 D2). Concurrency ceilings must evaluate exclusively through tracker reads.
- **Runtime Verification:** AGENTS.md prohibits documenting runtime mechanics that have not been verified against the target runtime.
- **Neighbour Boundaries:**
  - Issue #288 governs amending #64 D16 for VM poller dispatch consumption and adapter `--as` arguments; #295 defines no D16 changes.
  - Issue #291 governs amending #267 for review recorder `hold` parity; #295 makes no changes to recorder `hold` semantics.
  - Issue #284 (adapter `--as` defect) was resolved in code by PR #294.
  - Issue #252 (claim release on advance) was incorporated into #251 by D1.
  - Issue #251 remains open at `status:in-review` with held claim; #295 does not modify #251's claim, labels, or pull requests.

## Open questions

1. **Amendment document structure:**
   - Reading 1: The amendment lands as an `## Amendment rN` section inside `intent/251-e2e-chain/spec.md`, following the structure in `intent/64-autonomous-loop/spec.md`.
   - Reading 2: The amendment lands as a dedicated `spec.md` within `intent/295-poller-intake-gate/` that supersedes named decisions of #251.
2. **Intake arming switch:**
   - Reading 1: Intake is gated directly on `loop.autonomous_merge: true`, pausing when false.
   - Reading 2: Intake is gated on a dedicated configuration flag such as `loop.intake_enabled: true`, separating first-hop intake from autonomous merge.
3. **Fleet concurrency accounting:**
   - Reading 1: Concurrency counts open `in-progress` issues whose latest claim author is `athena`.
   - Reading 2: Concurrency counts active process executions tracked locally in `POLL_STATE_DIR`.
4. **Backlog admission mechanism:**
   - Reading 1: Backlog issues require an explicit label `intake:auto` created in GitHub.
   - Reading 2: Backlog issues are selected by an issue allowlist defined in `config/execution.yaml`.
5. **Fix-round lock path location:**
   - Reading 1: The lock moves into `POLL_STATE_DIR`, and contract row AT-20 is updated to resolve that directory.
   - Reading 2: The lock remains in `${TMPDIR:-/tmp}` with timestamp staleness pruning, leaving AT-20 unchanged.
6. **AT-20 lock contention verification:**
   - Reading 1: AT-20 clears the consumption key before tick 2 to verify lock contention.
   - Reading 2: A dedicated acceptance test row is added to contend the lock directly while AT-20 tests consumption keys.
7. **Literal fix-round trigger retention:**
   - Reading 1: The literal phrase `review findings: blocking` is dropped from D2 and `poll.sh`, requiring structured reviewer markers.
   - Reading 2: The literal trigger is retained while restricting author identity to `evekhm-argus-app[bot]` or `evekhm-atlas-app[bot]`.
8. **Enablement checklist sequencing:**
   - Reading 1: Step 2 of the checklist moves after step 6 so the supervisor starts after the autonomy flip.
   - Reading 2: Step 2 remains in place with documentation explaining that D5a makes early supervisor startup safe.
9. **Contract suite manifest inclusion:**
   - Reading 1: The contract suite remains outside the implement rung manifest, requiring spec-owner pull requests for repairs.
   - Reading 2: `scripts/ci/tests/e2e_chain_test.sh` is added to D8's manifest for the amendment implement rung.
10. **Claim reader specification alignment:**
    - Reading 1: D1 is updated as a text correction stating that claim holder identity is derived from `(.author.login // .user.login // "")`.
    - Reading 2: D1 is amended as a normative requirement that the advancer must accept both GraphQL and REST login fields.
