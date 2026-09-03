# Intent: close the label ladder's last rung

**Issue:** #57 · **Author:** athena (`evekhm-athena-app[bot]`) ·
**Status:** accepted on merge of this PR

## Problem

The ladder cannot reach its own last rung. `.github/workflows/
lifecycle.yml` mirrors merges into the `status:*` label by running
`scripts/ci/lifecycle_advance.sh`, which reads the pushed range for
**added** files matching `intent/<issue>-<slug>/{intent,spec,plan}.md`
(`lifecycle_advance.sh:133`) and selects the transition with
`jq '.stages[] | select(.artifact == $a)'` (`lifecycle_advance.sh:
271-272`). The implement rung owes no such file — its `artifact` is
`null` (`personas/lifecycle.json:46-52`) because its output is code —
so merging the implementing PR matches nothing and `status:in-review`
has no writer at all. Both the script header
(`lifecycle_advance.sh:25-28`) and docs/SPEC.md's `lifecycle.labels`
(last sentence) say so plainly; this issue is that sentence coming due.

Two consequences are observable today:

- After the implementing PR merges, the item still carries
  `status:implementing`, so `scripts/ops/work.sh <n>` resolves it to
  the implement rung (`work.sh:206-210`) and would dispatch Odyssey
  again onto work already on `main`.
- `work.sh <n> --as argus` and `--as atlas` refuse, because the review
  rung is current only under `status:in-review`
  (`personas/lifecycle.json:53-60`) and nothing sets it. The review
  rung is unreachable through the one-argument dispatcher, which
  INTENT.md's lifecycle (stage 6) and `ops.dispatch` both assume is the
  way in.

A smaller gap sits in the same script. Nothing writes `status:planning`
and nothing removes `intent:new`: the advancer's first transition is
intent.md → `status:spec` (`personas/lifecycle.json:21-28`) and its
label write swaps only the previous `status:*`
(`lifecycle_advance.sh:333`). `work.sh` treats "`intent:new` and no
`status:*`" as the first rung (`work.sh:211-213`), so an item that has
passed the PLAN gate carries `intent:new` *and* `status:spec`. It is
cosmetic while the only reader is a human, but #10's intake automation
keys on `intent:new`, and a label nothing clears would re-trigger
intake on every item forever.

Two defects the ladder's own unreachability has been hiding, both
recorded on #52 as Atlas AT-4 and both live the moment the last rung
becomes reachable: `advances_to` is read with a plain `jq -r`
(`lifecycle_advance.sh:276`), so the review row's JSON `null` renders
as the string `null`, passes the `[ -z "$target" ]` guard at line 325,
and would be written as a label; `advance_message`
(`lifecycle_advance.sh:277`) has the same shape and would post the
literal `null` as the transition comment.

## Proposed outcome

One human-filed issue traverses all five rungs on nothing but
`work.sh <n>` and a human's merges.

- **The implement rung advances.** When the implementing work reaches
  `main`, the item carries exactly one status label, `status:in-review`,
  and `work.sh <n> --as argus` / `--as atlas` resolve to the review
  rung. Which event counts as "the implementing work reached `main`"
  is the design stage's to decide (Open question 1) — the outcome is
  that the transition exists, is deterministic, and fires once.
- **No item ever carries `intent:new` alongside a `status:*` label.**
  The mechanism is Open question 3; the invariant is not negotiable,
  because it is what makes #10's intake trigger safe to write.
- **The transition is read, not written.** It stays driven by
  `personas/lifecycle.json`, the one table the advancer, the dispatcher
  and the compiler all read (`personas.resume`, #36). No fourth copy of
  the ladder appears, and no rung's label is spelled out inside the
  script.
- **It stays deterministic and idempotent.** Bash + `gh` + `jq`, no
  model call, no API key, `DRY_RUN=1` printing every mutation, and
  re-running a range remains a no-op — the properties `lifecycle.labels`
  states and `scripts/ci/tests/lifecycle_advance_test.sh` pins.
- **AT-4 does not regress.** `advances_to` and `advance_message` are
  read so that a JSON `null` is an absent value, not the string `null`,
  with the last rung's no-op covered by a test. Whether that repair
  lands here or in #52's own fix PR is a sequencing call for the design
  stage, but it may not be left undone by a change that makes the null
  row reachable.
- **The retired claim is retired.** `lifecycle.labels`' closing
  sentence, and the header line the workflow posts on every transition
  (`lifecycle_advance.sh:162-164`), both currently assert that this
  workflow writes only `status:planning`→`status:implementing` and that
  `status:in-review`'s writer arrives with #8/#9. Both statements
  become false and are updated by the implementing PR.

`review:1..3` and `status:review-stuck` stay out. They are review state,
not stage state, and #8/#9 keep them: a stage advancer that also guessed
at review counters would be two state machines racing over one issue —
the reason the script header names them as what it deliberately does not
write.

## Affected users and systems

- **The presenter.** INTENT.md:40-41 promises the live demo drives one
  real change through the entire loop; today the loop dead-ends at rung
  4, which is a demo that cannot finish.
- **Argus and Atlas**, whose rung is unreachable from a bare number, and
  **Odyssey**, who would be re-dispatched onto merged work.
- `scripts/ci/lifecycle_advance.sh` — the transition selector, the label
  write, the comment header, and the null-safe reads.
- `personas/lifecycle.json` — the implement row gains whatever the
  advancer must match on; three readers parse this file, so its shape is
  a shared contract, not a local detail.
- `scripts/ci/tests/lifecycle_advance_test.sh` — the new transition and
  the last rung's no-op need hermetic cases.
- `.github/workflows/lifecycle.yml` — untouched if the transition can be
  derived from the pushed range; if the chosen event needs a second
  trigger or a wider token scope, this is where that cost lands, and the
  workflow's `issues: write, contents: read` / no-secrets posture is the
  budget.
- `docs/SPEC.md` — `lifecycle.labels` and `personas.resume` are upserted
  by the implementing PR, per the living-spec rule.
- **#10** (intake automation) gains a clean `intent:new` contract;
  **#8/#9** keep `review:N` and `status:review-stuck` and inherit a
  `status:in-review` they no longer have to write; **#52** shares the
  file and the AT-4 finding.

## Constraints

- Deterministic bash + `gh` + `jq`, no model call, runnable locally by
  the same command CI runs, with `DRY_RUN=1` performing no writes
  (`lifecycle.labels`; `lifecycle_advance.sh:49-58`).
- `hold` is checked before anything else and is absolute; more than one
  `status:*` is corrupted state — comment, apply `hold`, stop; every
  write is idempotent by label presence and by the
  `<!-- lifecycle:<stage>:<sha> -->` comment marker
  (`lifecycle_advance.sh:30-47`). A new transition inherits all of it.
- At most one `status:*` label at a time (AGENTS.md, "The labels are the
  state machine"). The new write swaps, never adds.
- One table, no fourth copy: the label a transition writes and the line
  it posts are read from `personas/lifecycle.json`, and the tests assert
  that by pulling expected strings out of the JSON at run time rather
  than hardcoding them (`lifecycle_advance_test.sh:11-17`). A copy of
  the ladder hidden in the script must keep failing that case.
- Tests stay hermetic: throwaway git repository, stub `gh` first on
  `PATH`, `DRY_RUN=1`, no network and no issue touched
  (`lifecycle_advance_test.sh:6-9`).
- The advancer never writes `review:1..3` or `status:review-stuck`
  (`lifecycle_advance.sh:25-28`).
- **Refines #8 and #9**: `lifecycle.labels` says the `status:in-review`
  and `review:N` writers "arrive with #8/#9", and those are the
  Actions-hosted review pipelines that depend on #25 for where a model
  runs. The label transition needs no model runtime, so this issue
  carves it out and lets the manual loop close before Rung 3 lands;
  #8/#9 keep `review:N` and `status:review-stuck`.
- **Related #52**: same script, and its AT-4 finding (a JSON `null`
  `advances_to` rendering as the string `null`) must not regress — it
  may be folded in or sequenced, but not ignored.
- **Disjoint from #43** (in flight): #43 changes `work.sh`, the compiler
  and auth; this change touches `lifecycle_advance.sh`,
  `personas/lifecycle.json` and their tests. Any behaviour this needs
  from `work.sh` is a consequence of the label, not an edit to that
  script.
- **Depends on**: nothing open.

## Open questions

1. **What event constitutes "the implementing PR merged"?** The rung's
   artifact is code, so there is no path to match. Defensible readings:
   (a) the merged branch name `odyssey/<n>-*`, read from the merge
   commit; (b) the pull request associated with the push, resolved
   through its closing keyword and same-repo `#<n>` reference — the
   convention `ops.dispatch` already implements for PR→issue
   resolution; (c) an explicit marker the implementing PR or plan.md
   declares, in the shape of the existing `Spec-impact:` line. They
   differ observably on a squash merge (no merge commit and no branch
   name survives, so (a) is silent while (b) and (c) fire) and on a
   human hotfix pushed from an `odyssey/57-*` branch with no PR (where
   (a) fires and (b) does not). Whichever is chosen also decides the
   shape of the implement row in `personas/lifecycle.json`, since the
   advancer's current selector is the `artifact` column and that column
   is `null` for this rung — a new key read by the script, or a second
   selector, is the same decision seen from the data side.
2. **What is the review rung's exit — who or what closes the issue once
   both reviewers have posted?** `personas/lifecycle.json:57` ends the
   ladder with `advances_to: null`, so nothing advances past
   `status:in-review` by construction, but nothing states who closes
   the item either. Two readings: (a) the ladder simply ends and closure
   is the human's, carried by `Closes #<n>` on the merged pull request;
   (b) a terminal transition closes the issue once the review rung's
   condition is met. Reading (a) has a concrete collision that the
   design stage must answer either way: AGENTS.md:121-122 says a PR
   carries `Closes #<n>` only when it completes the issue's final stage,
   yet `lifecycle_advance.sh:225-226` skips any issue that is not
   `OPEN` — so if the implementing PR carries `Closes #57`, the very
   push that should write `status:in-review` finds a closed issue and
   skips it, and the review rung is entered by nobody.
3. **How is `intent:new` cleared, and does `status:planning` gain a
   writer?** (Surfaced here, not in the issue body.) Both readings
   satisfy the invariant above. (a) The advancer removes `intent:new`
   whenever it writes any `status:*`; `status:planning` then remains a
   label in the taxonomy that nothing ever writes, and `work.sh`'s
   "`intent:new` means rung 1" special case (`work.sh:211-213`) stays
   load-bearing forever. (b) Intake writes `status:planning` and removes
   `intent:new` when the issue is filed, so the first rung is real, the
   ladder has five written labels rather than four, and that special
   case becomes dead code. The differing case is a freshly filed issue
   carrying `intent:new` and no `status:*`: under (b) it is at
   `status:planning` before anyone dispatches it, under (a) it never is.
   The choice also fixes what #10 may assume about the label it triggers
   on.
