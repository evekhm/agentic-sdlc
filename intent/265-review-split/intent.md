# Intent: review split — Atlas on all PRs, Argus at the code gate

**Issue:** #265 · **Author:** athena (`evekhm-athena-app[bot]`) ·
**Status:** accepted on merge of this PR

## Problem

Both reviewers wake on every pull request event. In `config/execution.yaml`, `argus` and `atlas` bind to `trigger: repo-event`, `events: [pull_request]`, `placement: gh-actions`, and `max_cost_usd: 8.00`. In `.github/workflows/unattended.yml`, `pull_request` triggers on `types: [opened, synchronize, reopened]`, plus `workflow_dispatch`. The workflow filters neither by rung, nor by changed paths, nor by draft state, nor by ledger state. `REVIEW.md` line 8 specifies: "**In one line:** every PR gets one full review from both reviewers".

`REVIEW.md` section "## Asking for more — the deep-review grant" defines a deep round. The grant requires "a deep-review label applied by a repository admin" and specifies "(a grant applied by anyone else is refused, not consumed)". The repository has no `review:deep` label. `gh label list` shows `review:1`, `review:2`, `review:3`, and `status:review-stuck`. A persona identifying elevated risk cannot request a deep review. In `personas/lifecycle.json`, `status:implementing` maps to `stage: "implement"`.

Consequences observed on 2026-09-08:
- An intent PR, a plan PR, and a README PR each drew two full reviews. PR #260 had eleven pushes; each push woke both reviewers.
- Argus runs at REVIEW tier (Claude Opus) with an $8.00 ceiling per run. Every push to any PR can spend up to that ceiling on depth only needed at the code gate.
- Wall clock delays accumulate. Each early rung waits for two reviewer rounds before merge, on artifacts where one reviewer suffices.
- The verifier seat (#204) was specified as "the review stage given depth" and assigned to Argus. Today Argus spends its budget on breadth across every rung.

## Proposed outcome

1. **Atlas reads every pull request.** Every rung, every path. Atlas runs on Antigravity (Gemini), the cheap seat. Round 1 full, later rounds per the existing funnel.
2. **Argus joins at the code gate and on trust-bearing paths.** Argus is assigned when any of these holds:
   - the PR's issue is at `status:implementing` (the implement rung: the code PR);
   - the diff touches a trust-bearing path: `.github/workflows/**`, `scripts/auth/**`, `scripts/ops/post.sh`, `scripts/ops/work.sh`, `scripts/ci/**`, `personas/**`, `config/**`, `REVIEW.md`, `AGENTS.md`;
   - the PR carries `review:deep`;
   - the PR's ledger has an open `security` row (security already needs both reviewers; unchanged).
   Argus at the code gate carries the verifier duties of #204: re-run the gates, mutation-test the tests, read the job log behind every green check. #204 is resolved by this: the verifier is Argus's protocol at the code gate, and it gets no separate name or identity.
3. **A push re-triggers a review only when there is something to verify.** `synchronize` wakes a reviewer only when that reviewer has an open blocking row on the PR, or when `review:deep` was applied after its last round. A push to a PR with a clean ledger gets CI and nothing else. `opened`, `reopened` and `ready_for_review` always trigger the assigned set. Draft PRs trigger nothing.
4. **Consensus follows assignment.** Where only Atlas is assigned, consensus is Atlas's clean ledger plus green CI. Where both are assigned, the existing rules hold: independent round 1, dual sign-off on `security`, the distinct-family constraint (#198). The merge identity (#64, #251) merges on that consensus in autonomous mode; in manual mode the owner merges.
5. **`review:deep` is a grant a persona may apply.** A persona applies it through the trusted posting path (`scripts/ops/post.sh`, hold re-read before the write) with a comment that names the criterion id from the list below. The grant is consumed on use: the reviewer workflow removes the label after the deep round is posted, so a standing label cannot re-arm the loop. One deep grant per PR per rung. The existing admin path and the manual dispatch path stay.
6. **Deterministic criteria are applied by a workflow step, with no model in it.** The path and size criteria below are computed from the diff and apply the label themselves. Judgment criteria are applied by a persona.

### `review:deep` criteria

A persona applies `review:deep` when at least one of these holds, and names the id in the grant comment. DEEP-1 and DEEP-2 are computed and applied by CI; a persona may still cite them.

- **DEEP-1, trust-bearing paths.** The diff touches any path in the list under outcome 2. (Also forces Argus's assignment; the deep grant additionally lifts the round-scope cap for that run.)
- **DEEP-2, size.** More than 400 changed lines outside `tests/` and generated targets (`.claude/agents/**`, `.agents/agents/**`), or more than 12 files.
- **DEEP-3, irreversible or privileged operations.** The change adds or alters code that merges, closes, labels, deletes, force-pushes, mints or handles a credential, or writes outside the repository (GitHub API writes, cloud calls).
- **DEEP-4, plan deviation or spec-changing repair.** The PR body carries a "Plan sync" or "Plan deviation" section, or the repair changes a `docs/SPEC.md` entry (#32's second half).
- **DEEP-5, escalated tier.** The implementing session recorded a tier escalation for this rung (#107), or the plan marked a task `risk: high`. The architect sets `risk: high` at build time on a task that meets DEEP-3, touches concurrency or state machines (labels, claims, locks), or has no regression suite covering the file it edits.
- **DEEP-6, review history.** The PR is at `review:2` or later, or a prior round on this PR had a `security` row.
- **DEEP-7, compiler blast radius.** The change alters `scripts/sync_agents.py`, a skill under `personas/skills/`, or anything whose regenerated output touches two or more compiled targets.

Who applies which: Daedalus at build (DEEP-3, DEEP-5, DEEP-7, written into plan.md so the implement PR inherits it), Odyssey when opening or updating the PR (DEEP-3, DEEP-4, DEEP-5), Atlas after its own round when it finds a case for depth (DEEP-6 and anything it cannot verify at its tier), Cassandra or the advisor on a reopened or repaired PR, CI for DEEP-1 and DEEP-2. Applying the grant is never a defect; a missing grant on a change that met a criterion is a finding.

## Affected systems

- `config/execution.yaml` (exists) — subscriber assignment rules and conditions.
- `scripts/ops/execution.py` (exists) — subscriber query and configuration validation.
- `.github/workflows/unattended.yml` (exists) — triggers, draft skipping, ledger-aware synchronize filtering.
- `.github/workflows/ci-gates.yml` (exists) — deterministic evaluation for DEEP-1 and DEEP-2.
- `REVIEW.md` (exists) — line 8 assignment policy and persona deep-review grant rules.
- `personas/skills/` (new file: criteria skill) and persona sources declaring it (`personas/daedalus.yaml`, `personas/odyssey.yaml`, `personas/atlas.yaml`, `personas/argus.yaml`, `personas/cassandra.yaml`).
- compiled targets under `.claude/agents/` and `.agents/agents/` (exist) — compiler output.
- `scripts/setup/` (`scripts/setup/bootstrap_tracker.sh` exists) — idempotent provisioning for `review:deep`.
- `docs/SPEC.md` (exists) — living spec updates for `review.policy` and `execution.*`.
- merge gate from #64 (new file) — consensus derivation based on assigned reviewers.
- `README.md` (exists) — reviewer cast and workflow documentation.

## Constraints

- One machine-readable home for assignment rules in `config/execution.yaml` alongside persona execution bindings, validated by `scripts/ops/execution.py --check`. `REVIEW.md` states the rule in prose and cites configuration.
- The PR rung is read from the issue's `status:*` label via `personas/lifecycle.json`, using the PR-to-issue resolution in `scripts/ci/lifecycle_advance.sh`.
- The `hold` circuit breaker, claim mutex (#207), and trusted posting mechanisms remain unchanged.
- Distinct model families remain required whenever both reviewers are assigned (#198).
- `security` findings require dual sign-off; an open `security` row triggers Argus assignment.
- Cost ceilings per run remain unchanged; savings come from fewer runs.
- No new persona or identity; the verifier role is Argus's protocol at the code gate (#204 resolves into this).
- Skills are harness-agnostic and compiled by `scripts/sync_agents.py` (`AGENTS.md`). The criteria skill is declared by five personas and compiled across harnesses.
- Every GitHub write from an unattended run goes through `scripts/ops/post.sh` (`docs/SPEC.md`, `personas/skills/trusted-posting.md`). Applying `review:deep` uses this path.

## Open questions

1. **How does the resolve step discover a PR's lifecycle rung?** Either the resolve job resolves the linked issue via `scripts/ci/lifecycle_advance.sh` and reads its `status:*` label, or the label is mirrored directly onto the PR.
2. **Where does the synchronize trigger read the findings ledger before recorder (#8/#9) lands?** Either it queries existing PR review comments for unverified blocking findings, or it skips `synchronize` filtering until the structured recorder is active.
3. **Do DEEP-2 diff thresholds count compiled agent targets?** Either generated files under `.claude/agents/**` and `.agents/agents/**` are excluded alongside `tests/`, or the threshold counts all non-test diff lines.
4. **When may Atlas apply the `review:deep` grant?** Either Atlas may apply `review:deep` on the current PR during its own review to escalate the active rung, or Atlas applies it exclusively as a recommendation for the subsequent rung's PR.
5. **How is the deep review criteria skill structured?** Either the criteria live in a dedicated skill file under `personas/skills/` referenced by five personas, or the criteria are placed directly in `personas/skills/review-protocol.md`.
6. **When is the `review:deep` label consumed and cleared?** Either the workflow step removes the label immediately upon dispatch to prevent re-entrant runs, or the reviewer removes the label only after posting a completed deep review.
7. **How do manual deep dispatches interact with the per-rung grant limit?** Either a manual deep dispatch consumes the rung's single `review:deep` allocation, or manual dispatch remains an unmetered out-of-band path.
