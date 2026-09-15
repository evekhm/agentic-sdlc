# Intent: Authority boundary on issue writes: claim mutex and stage ownership gate comment posting

**Issue:** #467 · **Stage:** plan · **Author:** athena (`evekhm-athena-app[bot]`) · **Status:** accepted on merge of this PR

## Problem

Live dogfooding on issue #372 surfaced a structural gap in tracker write authority: the claim mutex in `scripts/ops/claim.sh` gates only `claim.sh` re-claims. Nothing prevents a persona or an autonomous sidecar from posting a persona-authored comment to an issue currently claimed by another actor, or at a stage that persona does not own.

On issue #372, while the issue was claimed (`in-progress`, `status:planning`, owned by `athena` per `personas/athena.yaml`), a comment authored by `evekhm-atlas-app[bot]` appeared on the thread proposing an alternative design. `personas/atlas.yaml` lists only `stage: [review]`. Issue #372 was at the planning stage and Atlas was never dispatched against it.

Currently, `scripts/ops/post.sh` is the single comment write path for unattended runs per #25 D5 and #98 D1. While `post.sh` verifies `hold` labels, reviewer run-ids, and App token attribution, it performs zero validation of stage ownership or claim mutex state. A persona possessing a valid App token can post to any open issue regardless of who holds the claim or what lifecycle stage is active.

## Proposed outcome

Establish an authority boundary on persona comment writes:

1. **Gate comment posting on stage ownership and claim status**:
   Before posting a comment to an issue, verify that the acting persona holds authority on that issue:
   - When the issue is claimed (`in-progress`), the acting persona must be the current claim holder established by the latest structured claim comment.
   - When the issue is unclaimed, the acting persona must own the stage indicated by the issue's current `status:*` label per `personas/lifecycle.json` and `personas/<persona>.yaml`.
2. **Preserve pull request review workflows**:
   Ensure pull requests continue to admit review comments from authorized reviewers (`argus`, `atlas`) per #207 D1 and D5, as well as author updates from the PR head branch author, while preventing unsolicited commentary on core issue threads.
3. **Fail closed on unauthorized writes**:
   An attempted comment write by a persona lacking stage ownership or claim holder status is refused with an explicit error and exits non-zero, preventing out-of-turn writes from reaching GitHub threads.
4. **Enforce through vetted posting tooling**:
   Implement the authority boundary within `scripts/ops/post.sh`, ensuring all unattended and persona-authored comments are checked mechanically at write time.

## Affected users and systems

- **`scripts/ops/post.sh`**: Evaluates stage ownership and claim holder status before comment publication.
- **`scripts/ops/tests/post_test.sh`**: Hermetic tests verifying write refusals for out-of-stage and non-holder personas.
- **`personas/skills/trusted-posting.md`**: Documents the authority boundary and write preconditions.
- **`docs/SPEC.md`**: Living spec updates under `ops.post` documenting comment authorization rules.
- **Autonomous sidecars and personas**: Background services (such as poller sidecars or review watchers) are bounded to their declared stages and assigned tasks.

## Constraints

- **Single write path**: All persona comments continue through `scripts/ops/post.sh` per #25 D5 and #98 D1.
- **Deterministic and hermetic**: Stage ownership derives from `personas/lifecycle.json` and `personas/<persona>.yaml` without ad-hoc hardcoding.
- **Fail closed**: Unreadable issue metadata, corrupted label state, or mismatched claim authorship aborts the post and prints a clear diagnostic.
- **Pull request compatibility**: Review dispatch (#207) and pull request reviews remain functional.
- **Surface mapping**:
  - `README.md`: Concept and vision check complete; README.md states authority is enforced mechanically by checks, which this change upholds; no edits required.
  - `INTENT.md`: Founding statements check complete; INTENT.md mandates mechanical enforcement of authority; no amendment required.
  - `REVIEW.md`: Review protocol is respected; no edits required.
  - `docs/SPEC.md`: Implementation diff owes living spec updates.

## Relationships

- **refines #25**: Extends the single comment write path (`scripts/ops/post.sh`, #25 D5) with stage ownership and claim mutex validation.
- **refines #36**: Reuses lifecycle stage ownership definitions (`personas/lifecycle.json`, #36 D1, D2) and dispatch refusal rules at comment posting time.
- **refines #43**: Enforces persona authority boundaries declared in `personas/*.yaml` against comment writes.
- **refines #87**: Extends claim mutex protection from session checkout into comment publication on claimed issues.
- **refines #98**: Connects trusted-posting discipline (Rule 1, #98 D1) to runtime comment authority enforcement.
- **refines #207**: Respects review dispatch boundaries (#207 D3, D5) on pull requests while closing unauthorized comments on claimed issues.
- **refines #372**: Addresses the structural vulnerability discovered when Atlas commented out of stage on a claimed planning issue.

## Open questions

### For DESIGN stage (`spec.md`)

1. **Enforcement scope on pull requests**: Should `post.sh` apply the stage ownership check exclusively to issues, or should pull request targets also require the acting persona to be either an assigned reviewer or the branch author?
2. **Unclaimed issue comment policy**: When an issue is unclaimed, should comment writes be permitted for any persona owning the active stage, or restricted to a specific transition handoff format?
3. **Refusal exit code**: Should an authority boundary refusal in `post.sh` exit with code 1 or code 2?

## Non-goals

- Modifying `scripts/ops/claim.sh` dependency validation or worktree management logic.
- Changing lifecycle stage definitions or transitions in `personas/lifecycle.json`.
- Restricting human operator comments or administrative actions in the GitHub web interface.
- Modifying consensus recording logic in `scripts/ci/review_recorder.sh`.
