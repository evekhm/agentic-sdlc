# Intent: auto-resolution of transient conjunct (2) merge gate declines

**Issue:** #514 · **Author:** athena (evekhm-athena-app[bot]) · **Status:** Draft

## Problem

The merge gate (`scripts/ci/merge_gate.sh`, running from `.github/workflows/merge-gate.yml`) evaluates once upon receiving a qualifying event and never re-evaluates automatically. When a decline is triggered by a transient condition, the pull request remains stranded indefinitely in a declined state. Autonomous forward progress ceases until a human operator spots the stall and manually triggers a workflow rerun.

### Measured Instances

1. **Pull Request #512 (Build rung of #508, 2026-09-17):**
   - 17:32:06Z: Atlas posts round 1 review.
   - 17:32:20Z: Themis writes consensus ledger comment.
   - 17:33:24Z: Argus posts round 1 review.
   - 17:33:28Z: Merge gate run 35253466278 begins evaluation (4 seconds after Argus comment).
   - 17:34:05Z: Gate declines: `Decline: conjunct(s) (2) false for #512 at b24e9e48; verdict: no merge for #512`.
   - Conjunct (2) failed because Argus's review comment fired the gate before Argus's own check run concluded. The gate read an in-flight check (`IN_PROGRESS`) in `statusCheckRollup`. All other conjuncts held true, including (9), (10), and (11).
   - The pull request sat `CLEAN`, `consensus:agreed`, `review:merge-ready`, with every check green, for 3 hours and 28 minutes. No further event occurred because reviewers were done and the commit head was settled.
   - At 21:01Z: An operator manually executed `gh run rerun 35253466278` against the identical SHA without code changes or comments. All eleven conjuncts evaluated true, and Themis merged the pull request at 21:01:46Z.

2. **Pull Request #515 (Implement rung of #508, 2026-09-17):**
   - 21:18:06Z: Gate run 35275832870 declines on (2), (3), (11): `argus via gh-actions=IN_PROGRESS`.
   - 21:18:31Z: Gate run 35275858424 declines on (2), (3), (11): `argus via gh-actions=IN_PROGRESS`.
   - 21:18:58Z: Gate run 35275898305 declines on (2): `resolve - which personas subscribe to this event=QUEUED`.
   - Within approximately one minute, every check on the commit head reached `SUCCESS`.
   - 21:21:41Z: An operator ran `gh run rerun 35275898305` without code changes or comments. The gate merged #515 at 21:21:48Z.
   - This instance proves that transient checks include infrastructure workflow jobs (such as `resolve`) in addition to reviewer persona jobs. It also demonstrates that rapid event arrival during check startup does not rescue the pull request once events cease.

### Autonomy Impact

The unattended lifecycle is designed to run without operator supervision. A transient decline silently breaks autonomy: it generates no red CI check on the commit, leaves no alert comment on the pull request, and leaves pull request labels indicating readiness to merge. Only manual operator log audits currently recover the pull request.

## Proposed outcome

A transient merge gate decline resolves autonomously without human intervention, requiring no empty commits, rebase pushes, or manual comments on the thread.

Design options for DESIGN stage resolution:
1. **In-gate bounded polling wait:** When conjunct (2) encounters foreign checks in transient states (`IN_PROGRESS`, `QUEUED`, `PENDING`) or `mergeStateStatus: UNKNOWN` while other merge preconditions are satisfied, `merge_gate.sh` polls check status with bounded retries before issuing a final verdict.
2. **Scheduled sweep workflow or poller daemon:** Open pull requests whose last gate evaluation declined on conjunct (2) with unchanged head SHA are periodically scanned. When all checks reach `SUCCESS`, the gate is re-triggered via `workflow_dispatch`.
3. **Event completion trigger:** An event-driven mechanism triggering on check suite or workflow run completion re-fires the merge gate when running checks conclude.

Acceptance is behavioral: triggering the merge gate while foreign checks on the head commit remain in flight results in autonomous merge once checks succeed, without operator action or new thread events.

## Affected users and systems

- `scripts/ci/merge_gate.sh`: Conjunct (2) evaluation, GraphQL `statusCheckRollup` reading, and retry loops.
- `.github/workflows/merge-gate.yml`: Workflow triggers, concurrency grouping, and job pre-runner conditions.
- `docs/SPEC.md`: Living specification for merge gate evaluation and check rollup handling.
- Personas (Odysseus, Daedalus, Athena) and operators whose pull requests enter the merge gate.

## Constraints

- **Strict wait bounds:** Any polling loop inside the gate must enforce a deterministic maximum timeout (well below the 10-minute GitHub Actions job limit, such as 90 to 120 seconds) to prevent hung runner slots.
- **Idempotency:** Re-evaluation must remain idempotent under the consensus recorder (#331 D1) and loop ledger (#64 D10). Repeated evaluation must avoid resurrecting cleared state or corrupting ledger markers.
- **Merge authority preservation:** The merge gate executing under `environment: themis` on `main` remains the sole authorized merger (#64 D3, #298 D2). Re-evaluation must adhere to all authorization checks.
- **Fail-closed security:** Persistent check failures (`FAILURE`, `CANCELLED`, `TIMED_OUT`) and unresolvable states must continue to decline strictly.
- **Living spec synchronization:** Conjunct (2) updates must be reflected in `docs/SPEC.md`.

## Relationships

- `refines #64`: D3 (merge gate trigger enumeration), D24 (conjunct (2) `mergeStateStatus` and foreign check roll-up evaluation, bounded retry on `UNKNOWN`).
- `refines #298`: D3 (check roll-up deduplication by check name / context selecting the latest `databaseId`).
- `refines #308`: D1, D3, D5 (workflow-level concurrency group and check suite pre-runner filtering skipping non-PR check suites).
- `refines #312`: D3, D4 (foreign check runs on head commit admitted, retry mechanisms).
- `refines #331`: D1 (consensus recorder ledger replay idempotency on successive gate runs).
- `refines #481`: Gate H / operator escalation sweep machine and stalled pull request visibility.
- `depends on #491`: Distinguishes active in-flight checks from stale failure context rollups surviving re-runs.
- `related to #448`: Escalation and gate timing when one reviewer verdict arrives while another run is in flight.
- `related to #501`: Reviewer check going green without recording a verdict.
- `related to #483`: Autonomous reaper and stalled contract resources.

## Open questions

1. **Re-evaluation architecture:**
   - Option A: In-gate bounded polling wait in `scripts/ci/merge_gate.sh`.
   - Option B: Scheduled sweep workflow or poller daemon.
   - Option C: Event-driven trigger on check completion.
   - *Differing case:* A reviewer comment fires the gate while the reviewer check is in flight. Both checks complete 45 seconds later. Under Option A, the gate polls for 45 seconds and merges in the same workflow run. Under Option B, the gate declines immediately and the pull request waits up to the sweep interval (several minutes) to merge. Under Option C, completion fires a new workflow run, but foreign checks from other workflows are not captured.

2. **In-gate timeout bound and failure disposition:**
   - Option A: 90-second bound (9 attempts at 10-second intervals), declining with a transient-specific reason if checks remain in flight.
   - Option B: 180-second bound.
   - *Differing case:* A slow CI check finishes 110 seconds after review posting. Under Option A, the gate declines at 90 seconds. Under Option B, the gate waits and merges at 110 seconds.

3. **Gate decline categorization:**
   - Option A: Explicitly distinguish transient decline from settled decline in the gate log and ledger (for example, `Decline: conjunct (2) transient: in-flight checks [resolve=QUEUED]`).
   - Option B: Maintain existing uniform decline output (`Decline: conjunct(s) (2) false for #<pr> at <head>`), leaving transient classification to live check inspection.
   - *Differing case:* An automated sweep scans gate logs. Under Option A, the sweeper filters directly for transient decline markers without querying GitHub check statuses for every declined PR. Under Option B, the sweeper must query GraphQL check statuses for every declined PR.

## Non-goals

- Severity and dispute semantics of conjunct (5) (#503, #508).
- Reviewer verdict recording gaps of conjunct (3) and conjunct (11) (#501).
- Stale check roll-up context defects (#491).
- Escalation on stale reviewed head (#448).
- Modifying branch protection requirements or GitHub Actions runner infrastructure.
