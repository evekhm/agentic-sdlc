# Intent: Update Finding Severity from Reviewer Verdict Blocks in Consensus Recorder

**Issue:** #361 · **Author:** athena (`evekhm-athena-app[bot]`) · **Status:** Accepted

## Problem

Under the autonomous review architecture (`REVIEW.md`, #267, #291; `docs/SPEC.md:544-630`), pull request reviews run unattended rounds using independent reviewers (`argus` and `atlas`). Reviewers evaluate changes and post structured review verdict blocks:

```markdown
<!-- review-verdict:<reviewer>:<verdict> -->
<!-- reviewed-head:<full-oid> -->
<!-- run-id:<n> -->
<!-- round:<n> -->
<!-- finding:<id>:<severity>:<status>:<peer> -->
<!-- failure-scenario:<id> -->
<!-- review-verdict-end -->
```

The consensus recorder (`scripts/ci/review_recorder.py`) parses these comments, derives the authoritative consensus ledger comment (`<!-- consensus-ledger:<pr> -->`) authored by Themis (`evekhm-themis-app[bot]`), and synchronizes PR lifecycle review labels (`review:merge-ready`, `consensus:agreed`, etc.). The autonomous merge gate (`scripts/ci/merge_gate.sh`) evaluates conjunct 4: whether any `security` or `high` finding in the consensus ledger remains in an `open` status.

### The Defect

In `scripts/ci/review_recorder.py`, finding severity is write-once from its initial observation. When a finding ID is re-encountered in a later review round, its severity is never updated from the reviewer's verdict block.

Specifically:
1. `review_recorder.py:118-135` seeds the dictionary `rows` from existing `<!-- ledger-row:<fid>:<severity>:<status>:<peer> -->` markers in the ledger comment.
2. In Pass 2 (lines 254-276), maintainer retier directives (`@argus retier <fid> <severity>`) from human maintainers are processed, which updates `rows[rfid]["severity"] = rsev`.
3. In Pass 2 verdict block processing (lines 277-363), for each finding in an accepted verdict block:
   - For non-security findings (`lines 356-363`):
     ```python
     else:
         if fid not in rows:
             rows[fid] = {"severity": fsev, "status": fst, "peer": fpr if fpr == "dispute" else "none"}
         else:
             if reviewer == discoverer:
                 rows[fid]["status"] = fst
             if fpr == "dispute":
                 rows[fid]["peer"] = "dispute"
     ```
   - For security findings (`lines 330-355`):
     If `fid in rows` and `reviewer == discoverer`, `rows[fid]["status"]` is updated (e.g. to `fixed`), but `rows[fid]["severity"]` is never touched.

Once a finding ID has been recorded into `rows`, `rows[fid]["severity"]` is completely immutable from subsequent reviewer verdict blocks. If the discovering reviewer lowers the severity of a finding in a subsequent round (e.g. from `high` to `normal` after author explanations, fix commits, or re-scoping), the recorder ignores the new severity in the footer marker and preserves the original severity indefinitely.

Furthermore, `review_recorder.py:267` restricts maintainer retier directives to human non-bot maintainers:
```python
is_authorized = (author_assoc in ("OWNER", "MEMBER", "COLLABORATOR") and user_type != "Bot")
```
Reviewer bots (`evekhm-argus-app[bot]`, `evekhm-atlas-app[bot]`) cannot emit `@argus retier` directives because the recorder explicitly rejects bot commands as unauthorized (`[refused: retier by @...: unauthorized]`).

### Production Evidence

This defect blocked PR #319 (implementing #265 review split) on 2026-09-10:
1. Argus round 2 (2026-09-09 20:59Z) recorded `finding:R2-1@D5:high:open:none`.
2. In subsequent rounds 3, 4, and 5 (04:42Z, 04:56Z, and 05:30Z on 2026-09-10), Argus re-evaluated the finding as non-blocking and recorded `finding:R2-1@D5:normal:open:none`.
3. At reviewed head `9482c37`, both Argus and Atlas emitted clean/approve verdicts with 0 open blocking findings.
4. However, the consensus ledger comment updated by Themis (at 05:31:31Z) still carried `<!-- ledger-row:R2-1@D5:high:open:none -->`.
5. Actions merge gate run 34441378531 failed with:
   ```text
   conjunct (4): false — blocking set: R2-1@D5
   ```
6. Because the ledger and the reviewer verdicts disagreed, autonomous merge was halted. Unblocking PR #319 required a human collaborator to post `@argus retier R2-1@D5 normal` on the PR thread.

### Systemic Impact on YOLO Autonomous Operation

Reviewers are stateless between runs (`REVIEW.md:252`). They evaluate current head commits and diffs and re-emit carried findings with their current assessment. When a reviewer concludes that a finding previously marked `high` should be downgraded to `normal` (or `suggestion`), emitting the updated severity in the structured footer marker is their standard communication mechanism.

Ignoring this update creates a persistent disagreement between reviewer verdicts and the consensus ledger. The merge gate evaluates conjunct 4 against the stale ledger, resulting in a false block that requires manual human intervention. This directly violates the operator requirement for YOLO Gate Y (zero human writes in the autonomous loop).

### Relationship to Adjacent Consensus Recorder Issues

Issue #361 belongs to the family of consensus recorder state machine defects identified in `docs/CRITICAL_PATH.md`:
- **#331**: Peer consensus state is write-once toward `dispute`; a reviewer's explicit withdrawal cannot clear it.
- **#324 / #354**: Sibling failure-scenario marker matching demotes `high` findings when decision citations (`@<Dn>`) differ in syntax.
- **#328**: Hardcoded assigned reviewer set prevents single-reviewer gating under #265.
- **#361** (this issue): Severity of a seen finding ID is write-once from its initial observation.

## Proposed outcome

1. **Enable Discovering Reviewer Severity Updates in `scripts/ci/review_recorder.py`**:
   - In Pass 2 of `review_recorder.py`, when processing an accepted verdict block for an existing finding ID (`fid in rows`):
     - If `reviewer == discoverer`, update `rows[fid]["severity"]` to the finding line's stated severity (`fsev`), subject to failure-scenario demotion and round funnel rules.
     - If `reviewer != discoverer`, the peer reviewer cannot alter the severity of the discovering reviewer's row.
2. **Preserve Funnel & Failure-Scenario Invariants**:
   - If the updated severity is `high`, verify presence of a matching sibling `<!-- failure-scenario:<id> -->` marker (applying base ID normalization per #354). If missing, mechanically demote to `normal` with the audit note `[demoted from high: missing failure_scenario marker] on <fid>`.
   - If a finding is lowered from `high` to `normal` or `suggestion`, it is removed from the gate's blocking set (`BLOCKING`), allowing conjunct 4 to evaluate cleanly.
   - Downward retiers (`high` -> `normal` -> `suggestion`) are admissible in all verification rounds as they narrow blocking scope. Upward retiers must comply with the round funnel rules in `REVIEW.md:171-176`.
3. **Transparent Audit Trail**:
   - When the discovering reviewer updates finding severity in a subsequent round, record an audit note in the ledger table (e.g. `[severity updated from <old> to <new> by @<reviewer>]` or diagnostic logging) so that severity changes are transparent and verifiable.
4. **Comprehensive Contract & Regression Test Suite**:
   - Add test cases in `scripts/ci/tests/review_recorder_test.sh`:
     - Re-encountering an existing `high` finding as `normal` from the discovering reviewer updates the ledger row severity to `normal`, removes it from the blocking set, and allows conjunct 4 to pass.
     - Peer reviewer attempting to emit a different severity for a discovering reviewer's finding does not alter the row's severity.
     - Re-encountering a finding as `high` validates failure-scenario presence and applies demotion if absent.
     - Integration with downstream `merge_gate.sh` asserting conjunct 4 succeeds when all open blocking rows are downgraded to `normal`.
5. **Living Specification Synchronization (`docs/SPEC.md`)**:
   - Upsert `docs/SPEC.md` under `review.policy` and `review.recorder` to formalize that finding severity is mutable across rounds by the discovering reviewer.

## Affected users and systems

- **Autonomous Reviewers (`argus`, `atlas`)**: Can re-tier or downgrade carried findings across rounds via standard footer markers without requiring human maintainer intervention.
- **Themis Consensus Ledger (`scripts/ci/review_recorder.py`)**: Consensus ledger rows remain synchronized with reviewer verdicts across multiple rounds.
- **Merge Gate (`scripts/ci/merge_gate.sh`)**: Evaluates conjunct 4 against accurate ledger severities; does not falsely block on findings that reviewers have downgraded to non-blocking tiers.
- **Autonomous Builders (`odyssey`, `daedalus`, `athena`) & Poller (`poll.service`)**: Changes with downgraded findings can progress and merge autonomously without manual human retier commands.
- **Contract Test Suite (`scripts/ci/tests/review_recorder_test.sh`)**: Authoritative test suite verifying severity lifecycle transitions across rounds.
- **Living Specification (`docs/SPEC.md`)**: Specifies `review.recorder` and `review.policy` severity mutability behavior.

## Constraints

- **Discoverer Exclusivity**: Only the discovering reviewer (or an authorized human maintainer via `@<reviewer> retier`) may alter a finding's severity. Peer reviewers may not alter another reviewer's finding severity.
- **Strict Demotion Guard**: Any finding transitioning to or remaining at `high` must satisfy the sibling failure-scenario marker requirement, or be demoted to `normal`.
- **Review Round Funnel Compliance**: Upward severity transitions across rounds must respect the round admissibility funnel (`REVIEW.md:171-176`).
- **Security Tier Invariants**: Transitioning findings to or from `security` must adhere to dual-agreement consensus rules (`REVIEW.md:283-285`).
- **Authority Bounds**: Athena authors only `intent/**`. Code, workflow, and test implementation belong to Daedalus (plan) and Odyssey (implementation) in subsequent stages.

## Open questions

1. **Upward Severity Retiers in Late Rounds**: If a discovering reviewer attempts to elevate an existing finding (e.g. `normal` -> `high`) in round 4 or later, should the recorder demote or refuse the elevation per `REVIEW.md:174-176` ("Past round 3 reviewers post verification comments only. The single exception is a new security finding..."), or treat existing findings as eligible for re-evaluation?
2. **Audit Note Formulation**: Should reviewer-driven severity transitions add an audit note below the ledger table (e.g. `[severity updated to normal by @argus on R2-1@D5]`), or should the transition be recorded in diagnostic logs to keep the ledger table compact?
3. **Security Tier Transitions**: Does a discovering reviewer have unilateral authority to downgrade a finding previously recorded as `security` to `high` or `normal`, or does a `security` tier finding require explicit peer concurrence or a human maintainer override to be downgraded?
4. **Coordination with Peer State Updates (#331)**: Issue #331 addresses peer state write-once behavior (`dispute` cannot be cleared by retraction). Should the severity update logic in #361 share the same pass-2 update structure in `review_recorder.py`, or remain completely orthogonal?
