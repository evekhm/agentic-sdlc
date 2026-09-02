# Spec: the label taxonomy and the stage advancer

**Issue:** #4 · **Status:** Approved (approval = merge of this PR) ·
**Open questions:** none

Bootstrap compression per intent/1-personas/spec.md D10 applies:
planning artifacts and implementation land in one PR, recorded once,
not a precedent.

## What is being built

```text
scripts/setup/bootstrap_tracker.sh   EXTENDED: the taxonomy + --labels-only
scripts/ci/lifecycle_advance.sh      the deterministic stage advancer
.github/workflows/lifecycle.yml      the thin trigger: push to main
AGENTS.md                            the taxonomy named in the tracker section
docs/SPEC.md                         lifecycle.labels moves into Capabilities
```

## The taxonomy

Decided on #4 (proposal comment, then "Decision: adopted as proposed",
2026-09-01); recorded here, not re-opened.

```text
human-facing, filed by people, honoured by automation
  intent:new           intake: a proposed change entering the lifecycle
  in-progress          the session claim mutex (AGENTS.md, "Working the tracker")
  hold                 circuit breaker: halts ALL automation while present
  blocked              needs a human or an unmet dependency
  bootstrap            rung-ladder work; retired after Rung 4

machine-driven stage state — at most ONE at a time, per issue
  status:planning  →  status:spec  →  status:build  →
  status:implementing  →  status:in-review

escalation and its counter
  review:1 / review:2 / review:3     reviewer iteration (predecessor convention)
  status:review-stuck                review:3 trips it; humans take over
```

Rejected: the predecessor's `argus:*` namespace (a reviewer-named
label leaks a deployment fact into the state machine, and personas are
meant to be swappable) and agent-farm's full seven-phase set verbatim
(its `needs-tpm`/`pm-review` phases are stages we do not run, and
adopting a name for a stage that does not exist invites drift).

## The three transitions

Only ADDED files count, and only in an `intent/<N>-<slug>/` folder
where `N` is the issue number:

```text
intent.md added   →  status:spec           "PLAN gate passed"
spec.md added     →  status:build          "DESIGN gate passed"  — Approved only
plan.md added     →  status:implementing   "BUILD gate passed"
```

`status:planning` and `status:in-review` are in the taxonomy but are
not written here: planning is the state an issue is in before this
workflow ever sees it, and in-review plus the `review:N` counter
belong to the review automation (#8, #9).

## Decisions

| ID | Decision |
|----|----------|
| D1 | **One status invariant.** At most one `status:*` label per issue. More than one is not a stage, it is two state machines disagreeing, so it is treated as corrupted state: the advancer comments naming the labels it found, applies `hold`, and stops processing that issue. It never guesses which one is true — guessing is how a corrupted state machine becomes a confidently wrong one. |
| D2 | **hold is absolute.** The `hold` check runs FIRST, before state, before labels, before anything. An issue carrying `hold` gets no label and no comment, only a log line. A circuit breaker automation gets a vote on is not a circuit breaker; this is also the manual override for every other decision in this table. |
| D3 | **Furthest transition only.** A push that adds two or three of the triple for one issue (bootstrap compression — this very PR does it) applies the furthest transition, ranked plan > spec > intent, and says so in the single comment it posts. Replaying the intermediate stages would post three comments describing a history the folder already records. |
| D4 | **Idempotent writes.** A label already present is not re-added; the whole label write is skipped when the issue is already at the target. Each comment embeds `<!-- lifecycle:<stage>:<after-sha> -->` and the advancer scans the last 20 comments for that exact marker before posting. Re-running a range is therefore a no-op, which is the property that makes a manual re-run safe after a partial failure — and partial failure is the normal failure here, since a push can name several issues. |
| D5 | **A Draft spec does not advance.** A merged `spec.md` advances the DESIGN gate only if it carries `Status: Approved`; otherwise the advancer comments a warning and leaves the stage exactly where it was. INTENT.md's rule is "nothing is dispatched against a Draft", and a gate that advances on a merge alone would dispatch against one. Markdown emphasis around the label is tolerated (`**Status:** Approved` is the house style, and the marker sits mid-line); the word `Approved` is matched case-sensitively. |
| D6 | **Infrastructure token, not a persona token.** The workflow uses the default `GITHUB_TOKEN` and posts as `github-actions[bot]` with `issues: write, contents: read` and nothing else. The six personas (INTENT.md) are named actors with their own identities and their own authority (#7); a label mover has no opinions to sign, and giving it a persona's identity would put a persona's name on a decision no persona made. |
| D7 | ADDED files only (`git diff --name-status --diff-filter=A`). A later edit to a merged `spec.md` is not a gate crossing; announcing one on every typo fix would train everyone to mute the issue. |
| D8 | All logic lives in `scripts/ci/lifecycle_advance.sh`, runnable locally as `lifecycle_advance.sh <before> <after>` with a `DRY_RUN=1` mode that prints every mutation instead of running it. The workflow is the thin trigger, per the same rule the CI gates follow (#6, D1): a workflow nobody can reproduce on a laptop is a workflow nobody debugs. Dry runs still READ, so the live guards are exercised; an unreadable issue in a dry run is substituted with an assumed-open, unlabelled one and said out loud, so synthetic input stays demonstrable. |
| D9 | **Fail-closed on input, fail-soft per issue.** An unusable range (a `before` that is not in the checkout, a failed diff) is an error, because reading it as "nothing changed" would silently skip real transitions. One unreachable, closed, or nonexistent issue is logged and skipped; if any issue actually FAILED to process, the run exits 1 so the push shows red. An all-zero `before` (branch creation) is a clean exit 0, not a diff against the empty tree. |
| D10 | Provisioning extends `scripts/setup/bootstrap_tracker.sh` with a `--labels-only` mode that exits before anything touches an issue, and does not even require `scripts/setup/issues/` to exist. The taxonomy will grow long after those issue bodies have drifted; growing it must never depend on the issue half of that script still being accurate. `status:*` share one hue family darkening along the ladder, `review:*` another, and `status:review-stuck` is deliberately outside both. |
| D11 | Event data reaches the script through `env:`, never through `${{ }}` interpolated into a `run` body (#6, D10). The two fields are SHAs today; the habit is what protects the next field someone adds. Concurrency queues rather than cancels: two close pushes are two different ranges, and cancelling the older one loses its transitions permanently. |
| D12 | Bootstrap compression per intent/1-personas/spec.md D10: this change lands PLAN/DESIGN/BUILD artifacts and the implementation in one PR. Not a precedent — and the advancer's own compression handling (D3) is what will report it. |

## Acceptance

- `bash scripts/setup/bootstrap_tracker.sh --labels-only` provisions
  all 14 labels on a fresh repo, is a no-op on the second run, and
  files no issue in either case.
- `bash -n` passes on both scripts.
- Against synthetic commits in a throwaway branch, `DRY_RUN=1
  scripts/ci/lifecycle_advance.sh <before> <after>` prints exactly one
  transition per issue: `intent.md` → `status:spec`, an Approved
  `spec.md` → `status:build`, `plan.md` → `status:implementing`, a
  Draft `spec.md` → a warning and no label write, and a range adding
  all three → `status:implementing` with the compression note.
- The same range run for real against issue numbers that do not exist
  logs "does not exist or is not visible — skipping" and exits 0,
  writing nothing.
- The Approved matcher accepts the house-style line
  (`**Status:** Approved (…)`) — verified against every existing
  `intent/*/spec.md`.
- The three CI gates (#6) pass on this branch, and `docs/SPEC.md`
  gains `lifecycle.labels` in the same PR.
