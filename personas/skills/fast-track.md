# Skill: fast-track

How an actor executes an owner-authorized ladder compression (fast-track).
Ladder compression accelerates authoring rungs (intent, spec, plan,
implement) into a single execution round (#415, #444) while keeping
living-spec, changelog, test, and dual-review consensus gates fully intact.

## The Six Invariants

1. **Owner authorization is explicit and human.** Autonomous bots cannot
   self-authorize fast-tracks or skip lifecycle rungs on their own. Fast-track
   is initiated only by the repository owner or operator via `/fast <issue>`
   or `scripts/ops/fast.sh <issue>`.
2. **Issue state is `status:implementing`.** Ladder compression transitions the
   issue directly to `status:implementing` (removing intake or earlier stage
   labels) and posts the authorization comment to the issue thread:
   `Owner-authorized fast-track initiated: lifecycle stage set to \`status:implementing\` for single-round execution.`
3. **Living spec obligation.** Fast-track PRs do not produce an `intent/`
   folder, but living documentation obligations remain binding: if system or
   user-facing behavior changes, `docs/SPEC.md` MUST be upserted in the PR diff.
4. **Changelog obligation.** If diff touches behavior-bearing paths (`scripts/`,
   `personas/`, `config/`, `.github/workflows/`, `AGENTS.md`, `REVIEW.md`),
   the PR must either update `CHANGELOG.md` or declare an explicit reason in
   the PR body: `Changelog: none — <reason>`.
5. **Automated test proof.** Fast-tracked code changes must be accompanied by
   passing automated tests proving the change works and prevents regression.
6. **Inviolable dual-review consensus.** Fast-tracking compresses authoring,
   never review. Every fast-track PR must be independently reviewed and agreed
   by both Argus and Atlas before the autonomous merge gate merges it.

## Execution Steps

1. **Verify Authorization.** Check the issue thread for the owner-authorized
   fast-track comment or verify that `/fast` / `scripts/ops/fast.sh` was
   invoked. If unverified, refuse and follow the regular ladder rungs.
2. **Enter Worktree.** Create and switch to the issue's isolated worktree:
   `CLAIM_ACTOR=<actor> CLAIM_SESSION=fast scripts/ops/claim.sh <issue>`
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
