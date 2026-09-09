# Skill: deep-review

Policy and criteria for applying the `deep-review` grant (#265, [REVIEW.md](../../REVIEW.md)).
The grant brings Argus into review before the code gate or lifts the round-scope cap for a comprehensive evaluation.

## When to apply: Criteria DEEP-1..DEEP-7

- **DEEP-1, trust-bearing paths.** The diff touches any path listed under `config/execution.yaml` `assigned_when.paths` for argus (workflow files, credentials, sync scripts, setup scripts, review policies, lifecycle definitions). In addition to forcing Argus assignment, the deep grant lifts the round-scope cap for that run.
- **DEEP-2, size.** More than 400 changed lines outside `tests/` and generated targets, or more than 12 files.
- **DEEP-3, irreversible or privileged operations.** The change adds or alters code that merges, closes, labels, deletes, force-pushes, mints or handles a credential, or writes outside the repository (GitHub API writes, external system calls).
- **DEEP-4, plan deviation or spec-changing repair.** The PR body carries a "Plan sync" or "Plan deviation" section, or the repair changes a `docs/SPEC.md` entry (#32's second half).
- **DEEP-5, escalated tier.** The implementing session recorded a tier escalation for this rung (#107), or the plan marked a task `risk: high`. The architect sets `risk: high` at build time on a task that meets DEEP-3, touches concurrency or state machines (labels, claims, locks), or has no regression suite covering the file it edits.
- **DEEP-6, review history.** The PR is at `review:2` or later, or a prior round on this PR had a `security` row.
- **DEEP-7, compiler blast radius.** The change alters `scripts/sync_agents.py`, a skill under `personas/skills/`, or anything whose regenerated output touches two or more compiled targets.

## Who applies which

- **Daedalus** at build: DEEP-3, DEEP-5, DEEP-7, written into `plan.md` so the implement PR inherits it.
- **Odyssey** when opening or updating the PR: DEEP-3, DEEP-4, DEEP-5.
- **Atlas** after its own round when it finds a case for depth: DEEP-6 and anything it cannot verify at its tier.
- **Cassandra** or the advisor on a reopened or repaired PR.
- **CI** for DEEP-1 and DEEP-2.

Applying the grant is never a defect; a missing grant on a change that met a criterion is a finding.

## Application mechanism

Apply the grant label via:
```bash
scripts/ops/post.sh <pr-number> --as <persona> --add-label deep-review
```
Policy allows at most one `deep-review` grant per PR per rung. A duplicate grant on the same rung is refused.
