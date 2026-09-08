Refs #64

**Implementation details (Fix Round):**
- **Trusted Ref Execution (D3 / R1-2):** `.github/workflows/merge-gate.yml` now checks out the trusted base branch (`${{ github.base_ref || 'main' }}`) to execute `scripts/ci/merge_gate.sh`, keeping the execution environment safe from untrusted code in the PR head. It uses the `actions/create-github-app-token` action to mint the privileged token for the `merge-actor` App and exports it as `GH_TOKEN`.
- **D5 Conjuncts 1-11 (R1-1, R1-6):** Implemented in `scripts/ci/merge_gate.sh`. The script fetches the pull request and issue, fails closed if the 11 conjuncts cannot be evaluated, and explicitly checks for the consensus ledger marker. If missing, it fails closed (Conjuncts 3, 4, 5, 11). `hold` and `blocked` labels on the PR and the issue immediately halt the gate with a green exit 0.
- **Loop Bounds (R1-5):** Exceeding `max_rung_dispatches_per_issue` or `max_cost_usd_per_issue` (calculated by paginating the issue loop ledger) immediately halts the script with a green exit 0, writes a `refusal:budget` row, and invokes `escalate.sh` to transition the issue to `status:review-stuck`.
- **Monotonic Progress (D14):** In `scripts/ci/lifecycle_advance.sh`, we exhaustively paginate the loop ledger and evaluate `target_rank` against the real `HIGHEST_MERGED_RANK`. If the target label doesn't advance the state or repeats an old head OID, it's flagged as a monotonic violation, refusing the merge and escalating it.
- **Dynamic Persona Resolution (R2-1):** `lifecycle_advance.sh` scans `personas/*.yaml` to find which persona owns the NEW target stage (derived from `lifecycle.json`) to invoke it autonomously.
- **Escalation Pagination & Checks (R1-7, AT-3):** `scripts/ci/escalate.sh` exhaustively paginates comments to ensure idempotency and accurately evaluates label states on both the PR and issue to prevent looping.
- **Error Propagation (R2-4):** `.github/workflows/lifecycle.yml` now preserves the exit code of `lifecycle_advance.sh` and errors out accurately on `set -e` aborts.

All automated check suites (`work_test.sh`, `merge_gate_test.sh`, `lifecycle_advance_test.sh`, `execution_test.sh`) pass successfully with these fixes.
