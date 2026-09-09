# Intent: Amend #64 D16 for VM Poller Dispatch Consumption and Adapter --as Argument

**Issue:** #288 · **Author:** athena (`evekhm-athena-app[bot]`) · **Status:** Draft

## Problem

`intent/64-autonomous-loop/spec.md` Decision D16 specifies: "The ladder dispatches its own next rung from inside the transition that writes the label: `lifecycle_advance.sh`, immediately after a successful `status:*` write and its comment, invokes the D17 placement adapter for the new stage's owner with the issue number and nothing else (#25, D16). No second workflow, no `issues: labeled` trigger, no new event."

Three discrepancies exist between the merged #64 specification and the codebase on `main` at base SHA `696f516239efaa8d9c63592354a08fc398b410f4`:

### 1. Adapter argument contract

D16 binds the advancer to pass "with the issue number and nothing else". Both placement adapters (`scripts/placement/vm-local/run.sh:52,56` and `scripts/placement/gh-actions/run.sh:48,52`) enforce `<number> --as <persona>`, exiting with `usage: run.sh <number> --as <persona>`, and refusing unknown flags with `unknown flag '$1'; the adapter takes <number> --as <persona> and nothing else`. Both adapters conclude with `exec "$REPO_ROOT/scripts/ops/work.sh" "$NUMBER" --as "$PERSONA"`.

In `scripts/ci/lifecycle_advance.sh:1159`, the advancer executes `bash "$REPO_ROOT/scripts/placement/$placement/run.sh" "$issue" --as "$persona"`, preceded by line 1156 (`log "    DRY-RUN scripts/placement/$placement/run.sh $issue --as $persona"`). This invocation was landed by PR #294 for issue #251. Defect #284 was filed for the original discrepancy where the advancer called adapters with the number alone; #284 remains open with label `bug`. Line 1076 of `scripts/ci/lifecycle_advance.sh`, cited in the #288 issue body, now extracts claim author login rather than invoking adapters.

This is a text gap: the implementation passes `--as "$persona"`, but D16 text still specifies "with the issue number and nothing else".

### 2. Dispatch row consumption and VM poller delegation

D16 defines the advancer as the sole dispatcher. In contrast, `intent/251-e2e-chain/spec.md` D2 and D5 establish that an external VM poller daemon (`scripts/placement/vm-local/poll.sh`) consumes `dispatch` ledger rows for `vm-local` placements.

Inside GitHub Actions, `scripts/placement/vm-local/run.sh:58-61` executes a record-and-return early exit before reading credentials:
```bash
if [ "${GITHUB_ACTIONS:-}" = "true" ] && [ "${DRY_RUN:-0}" != "1" ]; then
    echo "$PLACEMENT: delegating #$NUMBER execution to operator VM poller"
    exit 0
fi
```
The advancer appends the `dispatch` row to the issue loop ledger and calls the adapter. On hosted runners, the adapter logs delegation and returns 0. The external VM poller consumes the unconsumed row, acquires an issue claim, and runs the local dispatch. `intent/251-e2e-chain/spec.md` commits this amendment three times:
- D2: "Amendment r5 to #64 D16 (tracked under issue #288, 'Amend #64 D16 for VM poller dispatch consumption and adapter --as argument', with owner athena) permits the external VM poller to consume D16 dispatch rows and authorizes passing `--as \"$persona\"` to placement adapters."
- D8: "Amendment r5 to #64 D16 (tracked under issue #288, 'Amend #64 D16 for VM poller dispatch consumption and adapter --as argument', with owner athena) permits the external VM poller to consume D16 dispatch rows and authorizes passing `--as \"$persona\"` to placement adapters."
- `## Out of scope`: "Dedicated pull request for Amendment r5 to #64 D16: Owned by Athena, amending `intent/64-autonomous-loop/spec.md` line 151 to record consumption of dispatch rows by external VM poller and adapter `--as` arguments, tracked under issue #288."

This is a text gap: record-and-return delegation and poller consumption operate in code, but D16 text still describes the advancer as the sole dispatcher. With `loop.autonomous_merge: true` in `config/execution.yaml` (PR #297), this dispatch path is active.

### 3. Scope boundary interpretation of D19

`intent/64-autonomous-loop/spec.md` Decision D19 states that the implementing change "may **not** touch `personas/**` (D4, D17; #25 D10), `personas/lifecycle.json`, `intent/25-execution-model/spec.md` (D20), `scripts/ops/work.sh`, or any compiled target under `.claude/agents/` or `.agents/agents/`."

Two facts contradict a global reading of this prohibition:
1. `intent/251-e2e-chain/spec.md` D8 explicitly authorizes its implementing pull request to modify `scripts/ops/work.sh` for PR author fix rounds.
2. PR #294 modified `scripts/ops/work.sh` (commits `cf10e0b`, `4959b07`, `855c28a`, `8769335`).

This is a text gap: D19 bounds only #64's own implementing pull request, but lacks a clarifying sentence confirming that subsequent issues are not bound by its file restrictions.

## Proposed outcome

Amendment r5 to `intent/64-autonomous-loop/spec.md`, owned by athena on the design rung of this issue, establishes three updates:

1. **Authorize `--as "$persona"`**:
   - D16 authorizes passing `--as "$persona"` to placement adapters (the adapter's own contract already requires it).
   - Resolves the text gap behind defect #284.

2. **Record VM poller consumption and record-and-return**:
   - D16 records that for `vm-local` placements the advancer writes the dispatch row and returns (record-and-return), and the external VM poller consumes the row.
   - `lifecycle.yml` keeps its triggers and permissions (#64 D23, D25, D26).

3. **Clarify D19 scope**:
   - D19's scope note gains the sentence the #251 spec D8 relies on: D19 lists #64's own files and bans nothing for other issues.

What the amendment leaves unchanged:
- No second workflow.
- No new GitHub Actions event.
- No `issues: labeled` trigger.
- No change to triggers or permissions in `.github/workflows/lifecycle.yml` (push to main only, no `actions: write`).
- No change to token boundaries (`MERGE_ACTOR_TOKEN` on ledger row writes and `escalate.sh`; `status:*` label swap on `github.token`).
- Issue intake remains a human act (#64 Out of scope).

## Affected users and systems

- **Operators**: Reading D16 to understand the autonomous dispatch path, running the external VM poller daemon, and inspecting loop ledgers.
- **Builders**: Persona sessions (`athena`, `daedalus`, `odyssey`) launched by the VM poller from consumed dispatch rows.
- **Specification**: `intent/64-autonomous-loop/spec.md` amended with `## Amendment r5`.
- **Scripts and Workflows**:
  - `scripts/ci/lifecycle_advance.sh`: Writes loop-ledger rows and calls adapters with `--as "$persona"`.
  - `scripts/placement/vm-local/run.sh`: Performs Actions-side record-and-return and local launches.
  - `scripts/placement/gh-actions/run.sh`: Validates `--as <persona>`.
  - `scripts/placement/vm-local/poll.sh`: Consumes `dispatch` ledger rows on the operator VM.
  - `scripts/ops/work.sh`: Launch door referenced in D19's negative list and modified by #251.
  - `docs/SPEC.md`: Living spec documenting the continuous poller architecture.

## Constraints

- **D16 Prohibitions**: Dispatch must remain within the same transition that writes the `status:*` label; no second workflow, no `issues: labeled` trigger, no new event.
- **D17 Terminal Review Rung**: The review rung (`status:in-review`) remains terminal after merge and owes no next-rung dispatch.
- **D18 Autonomous Scope**: `loop.autonomous_merge` controls unattended merge and dispatch only; guards (D13, D14, D15) remain active regardless of flag setting.
- **D20 Single Parser**: `scripts/ops/execution.py` remains the single parser of `config/execution.yaml`; `trigger: ladder` remains required for ladder dispatches.
- **D23 Single Trusted Writer and Permissions**: Themis remains sole trusted writer for state comments; `.github/workflows/lifecycle.yml` retains its existing permissions block (`contents: write`, `issues: write`, `pull-requests: write`; no `actions: write`).
- **D25/D26 Token Boundaries**: `MERGE_ACTOR_TOKEN` is restricted to ledger row writes and `escalate.sh`; label swaps and comments stay on `GITHUB_TOKEN`.
- **Out of Scope Intake**: Issue intake remains a human action (#64 Out of scope).
- **Amendment Structure Precedent**: Merged specifications are amended by appending dated sections (`## Amendment r5`), preserving historical decision rows.
- **Verified Runtime Mechanics**: Only runtime behavior verified against the codebase may be documented (AGENTS.md).

## Open questions

1. **Amendment section vs in-place edit**: Should r5 append a dedicated `## Amendment r5` section with new decision rows superseding D16/D19 clauses, or edit D16 and D19 text directly?
   - Reading A: Append `## Amendment r5` with new decision IDs (e.g. D32, D33), following r1–r4 precedent and preserving historical decision text.
   - Reading B: Edit D16 and D19 in place with inline revision notes (similar to r2 notes in D9 and D19), keeping the core decision table unified.

2. **Placement adapter vs advancer responsibility**: Should record-and-return be stated as a property of the `vm-local` adapter or as a branch in D16 itself?
   - Reading A: State record-and-return as an internal property of `scripts/placement/vm-local/run.sh`, leaving D16's invocation uniform across placements.
   - Reading B: State in D16 that the advancer branches its expectations based on placement type.

3. **Level of poller description in #64**: Should the poller's consumption be described in #64's spec, or left to #251 with #64 carrying only a pointer?
   - Reading A: Include only a minimal statement in #64 that external pollers may consume dispatch ledger rows, pointing to #251 for daemon specifications.
   - Reading B: Specify the poller consumption protocol and ledger row lifecycle directly in #64 Amendment r5.

4. **D19 scope clarification scope**: Should D19's scope note gain a general sentence about other issues or an explicit exception naming #251?
   - Reading A: Add a general sentence stating that D19 defines the scope boundary solely for issue #64's implementing pull request.
   - Reading B: Add an explicit exception noting that subsequent issues, including #251, may modify `scripts/ops/work.sh`.

5. **Defect #284 disposition**: Does Amendment r5 close defect #284, or does #284 close on its own implementation evidence?
   - Reading A: Amendment r5 closes #284 because updating the spec text resolves the specification defect.
   - Reading B: #284 was resolved in code by PR #294 and closes on implementation evidence independently of the spec amendment.

6. **Contract parity for `gh-actions` adapter**: Should `scripts/placement/gh-actions/run.sh` retain the `--as <persona>` argument requirement when nothing consumes a row for it?
   - Reading A: Retain identical CLI signatures across both adapters for interface consistency.
   - Reading B: Require `--as <persona>` only on adapters whose execution targets support persona-specific delegation.

7. **Acceptance criteria placement**: Does the amendment owe an acceptance row, and where does it live given that #64's implement rung has already merged?
   - Reading A: Add acceptance rows in `## Amendment r5` verifying the amended text and adapter argument validation.
   - Reading B: Omit acceptance rows from #64 because the implementing pull request (PR #257) has merged, and verify purely via documentation checks.

8. **Living spec upsert**: Does `docs/SPEC.md` need a matching upsert alongside Amendment r5?
   - Reading A: Update `docs/SPEC.md` under `loop.autonomous` to document `--as "$persona"` and record-and-return delegation.
   - Reading B: Leave `docs/SPEC.md` as-is, since lines 1153–1170 already describe the continuous poller and `--as <persona>` dispatch.
