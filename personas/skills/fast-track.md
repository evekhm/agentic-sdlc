# Skill: fast-track

How an actor executes an owner-authorized ladder compression (fast-track).
Ladder compression accelerates authoring rungs (intent, spec, plan,
implement) into a single execution round (#415, #444) while keeping
living-spec, changelog, test, and dual-review consensus gates fully intact.

## The Six Invariants

1. **Owner authorization and caller boundary.** Fast-track records the caller or
   owner authorization signature (supporting on-issue owner comments `/fast-track`).
   Calls within unattended GitHub Actions runners are strictly refused. Policies
   and restrictions on autonomous bot self-authorization remain open for exploration
   in a follow-up issue.
2. **Issue state is `status:implementing`.** Ladder compression transitions the
   issue directly to `status:implementing` (clearing intake and earlier authoring
   labels `intent:new`, `status:planning`, `status:spec`, `status:build`) and posts
   the authorization comment to the issue thread. It strictly refuses issues with
   `hold`, `blocked`, `status:review-stuck` (where humans have taken over),
   `status:in-review` (active PR review in flight), or multiple contradictory
   stage labels.
3. **Living spec obligation.** Fast-track PRs do not produce an `intent/`
   folder, but living documentation obligations remain binding: if system or
   user-facing behavior changes, `docs/SPEC.md` MUST be upserted in the PR diff.
   If behavior is unchanged, an explicit `Spec-impact: none — <reason>` must be given.
4. **Changelog obligation.** If diff touches behavior-bearing paths (`scripts/`,
   `personas/`, `config/`, `.github/workflows/`, `AGENTS.md`, `REVIEW.md`),
   the PR must either update `CHANGELOG.md` or declare an explicit substantive reason in
   the PR body: `Changelog: none — <reason>`. A boilerplate restatement of the door
   is invalid.
5. **Automated test proof.** Fast-tracked code changes must be accompanied by
   passing automated tests proving the change works and prevents regression.
6. **Inviolable dual-review consensus.** Fast-tracking compresses authoring,
   never review. Every fast-track PR must be independently reviewed and agreed
   by both Argus and Atlas before the autonomous merge gate merges it.

## Execution Steps

1. **Verify Authorization.** Check the issue thread for the owner-authorized
   fast-track comment and verify the author is a human repository collaborator/owner,
   not an autonomous bot. If unverified, refuse and follow the regular ladder rungs.
2. **Enter Worktree.** Create and switch to the issue's isolated worktree:
   `CLAIM_ACTOR=<actor> CLAIM_SESSION=fast scripts/ops/claim.sh <issue>`
   When already inside the issue's worktree, `<issue>` is optional for `/fast` and `scripts/ops/fast.sh` (inferred from worktree or branch).
3. **Implement Code, Tests, and Living Spec.**
   - Implement the solution in the worktree.
   - Upsert `docs/SPEC.md` if behavior changes.
   - Run tests (`sanitize_check.sh`, `spec_check.sh`, and local test suites).
4. **Prepare PR with Mandatory Header and Changelog Marker.**
   The PR body must open with:
   ```text
   Owner-authorized ladder compression: combines intent/spec/plan/implement into one round (Refs #<n>).
   ```
   If behavior-bearing paths were modified without updating `CHANGELOG.md`, include:
   ```text
   Changelog: none — <why this diff does not change user-facing or system behavior>
   ```
   End with `Closes #<n>`.
5. **Open PR and Dispatch Independent Reviewers.**
   Create the PR targeting `main`. Independent reviewers evaluate the diff
   under the fast-track criteria (substantive code quality, tests, and spec
   accuracy without requiring intermediate ladder artifacts).
