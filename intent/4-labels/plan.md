# Plan: the label taxonomy and the stage advancer

**Issue:** #4 · single PR (bootstrap compression, see spec.md).
Stacked on #6 (the CI gates), which is stacked on #5 → #2 → #1.

1. `scripts/setup/bootstrap_tracker.sh` — extend the existing
   `ensure_label` section with the nine new labels (D10): the five
   `status:*` ladder steps in one darkening hue, `status:review-stuck`
   outside it, `review:1..3` in a second hue. Add `--labels-only`,
   parsed before the preflight so the mode does not require
   `scripts/setup/issues/`, and exiting immediately after the label
   block. While in there, cache the label listing once instead of
   re-listing per `ensure_label` — fourteen calls to learn one answer
   — with a failed listing an ERROR, never an empty tree.
2. `scripts/ci/lifecycle_advance.sh` — pure bash + `gh` + `jq`, header
   comment first, failure modes stated before behavior. Read the range
   with `git diff --name-status --diff-filter=A` (D7), match
   `intent/<N>-<slug>/(intent|spec|plan).md`, keep the furthest stage
   per issue (D3). Per issue, in this order: read state, labels and
   the last 20 comment bodies in ONE `gh issue view`; skip a closed or
   missing issue; `hold` first and absolute (D2); more than one
   `status:*` → comment, apply `hold`, stop (D1); then the transition,
   with `spec.md` gated on the Approved matcher (D5). Every write
   idempotent behind the `<!-- lifecycle:<stage>:<sha> -->` marker and
   a label-already-present check (D4). `DRY_RUN=1` prints mutations
   (D8); input errors die, per-issue errors accumulate and exit 1 (D9).
3. `.github/workflows/lifecycle.yml` — `on: push: branches: [main]`,
   `permissions: issues: write, contents: read`, default token (D6),
   `fetch-depth: 0`, SHAs through `env:` (D11), a non-cancelling
   concurrency group, actions pinned by major tag. Nothing but the
   call.
4. `AGENTS.md` — one paragraph in "Working the tracker" naming the
   five kept labels, the ladder and its one-status invariant, `hold`
   as the absolute circuit breaker, `review:N` → `status:review-stuck`,
   and that lifecycle.yml mirrors merge gates into the labels.
5. `docs/SPEC.md` — move `lifecycle.labels` out of "Agreed, not yet
   built" into Capabilities, citing #4 and `intent/4-labels/`.

Verification, before the push:

- `bash -n` on both scripts; `shellcheck` where available.
- `bash scripts/setup/bootstrap_tracker.sh --labels-only` run for real
  against the repository, then re-run to show the second pass creating
  nothing, then `gh label list` to confirm all 14.
- A throwaway local branch with three synthetic commits — add
  `intent/999-test/intent.md`; add an Approved `intent/999-test/spec.md`;
  add a Draft `intent/998-draft/spec.md` plus `intent/999-test/plan.md`
  — driven through `DRY_RUN=1` for each range and for the whole span
  (the compression case). Then the same span for REAL, to prove a
  nonexistent issue degrades to a log line and exit 0. Branch deleted
  afterwards; no test issue is ever filed and no real issue's labels
  are touched.
- The Approved matcher run against every existing `intent/*/spec.md`.
- The three #6 gates locally: `scripts/ci/sanitize_check.sh`,
  `sync_agents.py --check`, `spec_check.sh origin/bootstrap/6-ci-gates`.

Not in this change: the writers for `status:in-review` and `review:N`
(#8, #9), any label the intake agent sets (#10), and branch protection
— making anything here required is a repository setting a human
applies, not a file in the diff.
