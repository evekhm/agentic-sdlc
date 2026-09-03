# Plan: close the label ladder's last rung

**Issue:** #57 · **Spec:** `spec.md` (Approved, merged in 3d21db5) ·
**Author:** daedalus (`evekhm-daedalus-app[bot]`) ·
**Target SHA:** `3d21db59ddd002f8c19a7fc6e213b2f9604cc6c9` (`origin/main`)

Thirteen tasks. Every line number cites the target SHA. Each task names
the exact files it touches, the change in enough detail to be executed
without design authority, the Decision IDs it lands, and the check that
proves it. **T1 is probes and runs first** — it is already run and its
results are recorded below, so the implementer re-runs it only to
confirm nothing moved under the pin.

Order: T1 → T2, T3 (data and workflow, independent of each other) →
T4 → T5 → T6 → T7 → T8 → T9 (all five in `lifecycle_advance.sh`, in
this order, because each builds on the previous one's structure) →
T10 (tests, after the script is whole) → T11, T12 (docs) → T13 (gates
and the end-to-end).

**Contract tests.** This plan is committed with no test code. Daedalus's
compiled authority lists `tests/**` as a writable path, but no such
directory exists — the real suites live under `scripts/*/tests/`
(`scripts/ci/tests/`, `scripts/ops/tests/`). That glob is wrong and is
#54's to fix; writing to `scripts/ci/tests/` from this stage would be
outside the declared surface either way. So the failing-test obligation
is discharged as a specification: T10 names every scenario, its fixture
and its assertion, and Odyssey writes them in the implementing PR
before the script changes are green.

---

## T1 · Probes — the three mechanism assumptions (no files)

D1 and D3 rest on facts about the runtime, not about this repository's
code. Confirm all three before writing anything; a failure here changes
the plan, not the implementation.

- **P1 — history depth.** D1 needs `git rev-list --first-parent
  <before>..<after>` to resolve inside the workflow's checkout.
  `.github/workflows/lifecycle.yml:47-50` already sets `fetch-depth: 0`
  with the comment "a shallow clone has neither of them", and
  `lifecycle_advance.sh:110-113` already fails closed if `BEFORE` is
  absent. **Verified at the pin: no change needed.**
- **P2 — the API shape.** `gh api repos/<repo>/commits/<sha>/pulls`
  must return `number`, `merged_at`, `state`, `base.ref`, `head.ref`
  and `body`. **Verified at the pin** against
  `commits/3d21db59ddd002f8c19a7fc6e213b2f9604cc6c9/pulls`, which
  returned exactly one object: `number 61`, `merged_at
  2026-09-03T18:53:01Z`, `state closed`, `base main`, `head
  athena/57-lifecycle-ladder-dead`, `body` present. Re-run:

  ```bash
  gh api repos/evekhm/agentic-sdlc/commits/3d21db5/pulls \
    --jq '.[] | {number, merged_at, base: .base.ref, head: .head.ref}'
  ```

- **P3 — the scope the endpoint needs.** The endpoint is a
  pull-request read, which is why D3 adds `pull-requests: read` and
  nothing else. Confirm after T3 by reading the job's
  `X-Accepted-Github-Permissions` on a real run, or simply by the run
  going green: a missing scope is a 403 the advancer turns into a
  counted failure, so it cannot pass silently.
- **Note, not a blocker.** Discovery costs one `gh api` call per
  first-parent commit in the range. Real pushes to `main` are one to
  three commits; no cap is specified and none is added here. The call
  is unpaginated (30 per page) — a commit belonging to more than 30
  pull requests does not occur and is not handled.

## T2 · `personas/lifecycle.json` — the trigger column — D4, D11

1. Add `"advances_on"` to every row, after `"artifact"`:
   plan `"artifact"`, design `"artifact"`, build `"artifact"`,
   implement `"merge"`, review `null`.
2. The implement row's `"artifact"` stays `null`. Its
   `"advance_message"` becomes, verbatim from D11:

   ```text
   Implementation merged (IMPLEMENT gate). Next: two independent reviewers read the change and post findings — dispatch each with `scripts/ops/work.sh <issue> --as argus` and `--as atlas`. This is the last rung: nothing advances past it, and closing the issue is the human's.
   ```

3. The review row keeps `advances_to: null` and
   `advance_message: null` (D8).
4. The `_comment` key list (`personas/lifecycle.json:12-17`) gains
   `advances_on` in the sentence that enumerates the keys, described as
   *what event fires this rung: the row's artifact being added, a
   merged pull request, or nothing.*

**Proves it (Acceptance 1):**
`jq -e '[.stages[].advances_on] == ["artifact","artifact","artifact","merge",null]' personas/lifecycle.json`,
`jq -e '.stages[3].artifact == null and .stages[3].advance_message != null' personas/lifecycle.json`,
and `jq -r '._comment | join(" ")' personas/lifecycle.json | grep -q advances_on`.
Also `python3 scripts/sync_agents.py --check` exits 0 with no compiled
target in the diff: the compiler renders `stage`/`label`/`artifact`/
`advances_to`/`dispatch_brief` only, so neither the new column nor the
new message reaches a target (D14).

## T3 · `.github/workflows/lifecycle.yml` — one scope — D3

Change the `permissions:` block (lines 29-31) to:

```yaml
permissions:
  issues: write
  contents: read
  # The implement rung advances on a merged pull request found through
  # `gh api repos/<repo>/commits/<sha>/pulls` (#57, D1/D3). This is the
  # only new scope; there is no second trigger, no second job and no
  # secret.
  pull-requests: read
```

Nothing else in the file changes: `on: push: branches: [main]` stays,
the single `run:` line stays, `fetch-depth: 0` stays.

**Proves it (Acceptance 10):**
`git diff origin/main -- .github/workflows/lifecycle.yml` shows added
lines only inside `permissions:`;
`grep -c 'pull_request:' .github/workflows/lifecycle.yml` is 0 and
`grep -c 'secrets\.' .github/workflows/lifecycle.yml` is 0.

## T4 · `scripts/ci/lifecycle_advance.sh` — null-safe reads — D10 (#52 AT-4)

Do this first among the script tasks: it is the smallest change and
every later task depends on `target`/`message` being *empty* rather
than the four-character string `null`.

1. Lines 276-277 become:

   ```bash
   target="$(jq -r '.advances_to // empty' <<<"$row")"
   message="$(jq -r '.advance_message // empty' <<<"$row")"
   ```

2. Add a guard so an empty message posts no comment at all. Wrap the
   comment block (lines 309-322) so it is entered only when
   `[ -n "$message" ]`, and log `    #$issue has no advance_message for
   this row — no comment` otherwise. Today an empty message would post a
   body with a blank line where the sentence belongs.
3. The empty-target guard at lines 325-328 is unchanged — it becomes
   reachable for the first time. Its log line stays worded for the
   Draft case; add `${target:+}`-free wording: keep the existing
   `Draft spec does not advance` message only when `$stage` is `spec`,
   and otherwise log `    #$issue has no advances_to for this row —
   stage unchanged (${current_status:-no status label})`. The Draft
   override keeps its own message and its own warning comment,
   unchanged.

**Proves it (Acceptance 9), asserted by T10:** the fixture is patched so
the review row's `advances_on` is `"merge"`, a merge candidate lands on
an issue at `status:in-review`, and the output contains neither
`--add-label null` nor a comment body; `hasnt "--add-label null"` and
`hasnt "gh issue comment"`.

## T5 · `scripts/ci/lifecycle_advance.sh` — one candidate list — D5

Structural only: after this task the artifact path behaves exactly as
it does at the pin, and the loop can carry a second kind of candidate.

1. Keep `BEST_RANK`, `BEST_STAGE`, `BEST_PATH`, `ALL_FILES` and the
   `while` loop at lines 122-149 untouched.
2. Add, beside them, `declare -A MERGE_PR` and `declare -A MERGE_SHA`
   (filled by T6), a plain newline-delimited `CANDIDATES=""` string
   that every discovery step appends its issue number to, and a plain
   `n_candidates=0` counter incremented alongside it. Do **not** expand
   associative-array keys to build the loop list and do **not** use
   `${#arr[@]}` to count: the file already documents (lines 127-129)
   that an empty associative array trips `set -u`, and the merge path
   can now leave `BEST_STAGE` entirely empty. In the artifact loop,
   append at the same point `n_crossings` is incremented (line 142);
   `n_candidates` counts distinct issues across both discovery steps
   (guard with `[ -n "${BEST_STAGE[$issue]:-}${MERGE_PR[$issue]:-}" ]`
   before incrementing, as line 142 already does for `ALL_FILES`).
3. Replace the early exit at lines 151-154 with:

   ```bash
   if [ "$n_candidates" -eq 0 ] && [ "$FAILURES" -eq 0 ]; then
       log "==> nothing to advance in $BEFORE..$AFTER — no intent/<issue>-<slug>/{intent,spec,plan}.md added and no merged pull request found"
       exit 0
   fi
   ```

   The `FAILURES` conjunct matters: D2's disagreement failure (T6) can
   be the only event in a range, and the old unconditional `exit 0`
   would swallow it. When `n_candidates` is 0 but `FAILURES` is not,
   execution falls through an empty loop to the `FAILURES` check at
   lines 337-339 and the run ends red.
4. Line 203 becomes
   `for issue in $(printf '%s\n' "$CANDIDATES" | grep -E '^[0-9]+$' | sort -nu || true); do`
   — the `|| true` is required: `grep` exits 1 on an empty list and
   `set -e` would abort the run on the very case that must fall through
   to the `FAILURES` check,
   and the head of the loop body (lines 204-207) becomes:

   ```bash
   stage="${BEST_STAGE[$issue]:-}"
   path="${BEST_PATH[$issue]:-}"
   files="${ALL_FILES[$issue]:-}"
   ```

   with the `log "--> #$issue …"` line stating `added: $files ·
   furthest: $stage.md` only when `$files` is non-empty, and
   `--> #$issue · merged pull request #${MERGE_PR[$issue]}` otherwise.
5. Move the `current_status` / `status_count` computation (lines
   236-238) up to immediately after `labels` is read — before the
   `issue_state != OPEN` check at line 225 — because T7's closed-issue
   rule needs it. This is a pure move: no check changes position
   relative to another check, `hold` is still first among the guards
   that act.

**Proves it (Acceptance 6, first three clauses):** `bash -n`, plus T10
re-running every pre-existing scenario unchanged — the artifact path's
output must be byte-identical to the pin over the same ranges. Capture
`DRY_RUN=1` output at 3d21db5 and after T5 over `C0..C3` into
`runs/<YYYY-MM-DD_HHMMSS>/`, diff, cite the empty diff in the PR.

## T6 · `scripts/ci/lifecycle_advance.sh` — merge discovery — D1, D2

New block, placed after the artifact `while` loop and **before** the
early exit from T5.

1. For each commit, oldest first, so the last merged pull request in
   the range wins for a given issue:

   ```bash
   while read -r sha; do
       [ -n "$sha" ] || continue
       prs="$(gh api "repos/$GITHUB_REPO/commits/$sha/pulls" \
                --jq '[.[] | select(.merged_at != null) | {number, head: .head.ref, body: (.body // "")}]' 2>/dev/null)" \
           || { fail_issue "cannot list pull requests for $sha"; continue; }
       ...
   done < <(git rev-list --first-parent --reverse "$BEFORE..$AFTER")
   ```

   Filter to `base.ref == <default branch>` inside the same `--jq`
   using the repository default read once before the loop
   (`gh api "repos/$GITHUB_REPO" --jq .default_branch`, falling back to
   `main` on failure), and de-duplicate by `number` across commits with
   a `SEEN_PR` associative array. A commit that belongs to no pull
   request yields nothing and is not an error. A commit pushed straight
   to a branch with no pull request therefore never advances anything —
   deliberate, per D1.
2. Resolve each surviving pull request to at most one issue, **branch
   first, keyword second** (D2, the reverse of `work.sh`'s order):

   ```bash
   by_branch=""
   [[ "$head" =~ ^[a-z][a-z-]*/([0-9]+)- ]] && by_branch="$((10#${BASH_REMATCH[1]}))"
   by_keyword="$(grep -Eoi '\b(close[sd]?|fix(es|ed)?|resolve[sd]?)[[:space:]]+#[0-9]+' <<<"$body" \
                   | grep -Eo '[0-9]+' | sort -un || true)"
   ```

   The two regexes are copied from `scripts/ops/work.sh:136` and
   `:155` verbatim so no new convention appears. Then:
   - both empty → no candidate;
   - exactly one signal → that issue;
   - both present and equal → that issue;
   - both present and different, or more than one distinct keyword
     number → `fail_issue "pull request #$n resolves to two different
     issues: #$by_branch by branch name, #<k> by closing keyword — not
     guessing"`, and no candidate is produced for that pull request.
3. For each resolved issue: `MERGE_PR[$issue]="$n"`,
   `MERGE_SHA[$issue]="$sha"`, and append `$issue` to `CANDIDATES`.
   The `advances_on` gate is **not** applied here — it needs the
   issue's current label, which is only known after the `gh issue
   view` inside the loop (T7). Discovery produces a *provisional*
   candidate; T7 accepts or discards it.

**Proves it (Acceptance 2, 3, 4), asserted by T10:** the merge-branch
scenario, the keyword-fallback scenario, the disagreement scenario
(exit 1, both numbers named, empty write log), the squash-shaped range
(one commit, no merge commit) and the no-pull-request range (exit 0 via
the T5 early exit).

*Amended in implementation (odyssey):* two mechanical readings, neither
touching a Decision. (a) The default-branch read is
`gh api "repos/$GITHUB_REPO"` piped into `jq -r '.default_branch //
empty'` rather than `gh api --jq`, so the answer the T10 stub is
specified to give — the object `{"default_branch":"main"}` — is the
shape the script actually parses, and the file keeps one convention:
fetch raw, filter with `jq`. (b) The per-pull-request filter is a
separate `jq -c --arg b "$default_branch"` step over the raw response
for the same reason (`gh api --jq` takes no `--arg`), and the keyword
regex is work.sh's anchored `grep -Eo '[0-9]+$'` (`:137`) rather than
the plan's unanchored transcription of it — "verbatim from work.sh" was
the instruction and the anchored form is what work.sh carries.

## T7 · `scripts/ci/lifecycle_advance.sh` — the merge candidate in the contest — D5, D6, D9

All inside the per-issue loop.

1. **Closed issue (D9).** Replace lines 225-228 with: if
   `issue_state != OPEN`, then when the issue has a `MERGE_PR` entry,
   `status_count` is exactly 1, and the row whose `label` equals
   `current_status` has `advances_on == "merge"`:

   ```bash
   fail_issue "#$issue is $issue_state but still carries $current_status, and pull request #${MERGE_PR[$issue]} merged in the range — the ladder cannot advance a closed issue. The implementing pull request must not carry a closing keyword for #$issue (#57, D9); reopen #$issue, drop the keyword, and re-run this range."
   continue
   ```

   Nothing is written to that issue: no label, no comment, no reopen.
   Every other non-OPEN case — an artifact candidate, no `status:*`
   label, more than one `status:*` label, a row whose `advances_on` is
   not `"merge"` — keeps today's quiet `log … skipping` and `continue`.
2. **Pick the candidate kind**, after the corrupted-state block (which
   is unchanged and still `continue`s):

   ```bash
   artifact_rank="${BEST_RANK[$issue]:-0}"
   merge_rank=0
   if [ -n "${MERGE_PR[$issue]:-}" ] && [ -n "$current_status" ]; then
       # Rank = position in .stages plus one, and 0 unless this row's
       # trigger is "merge" — one jq, gate and rank together.
       merge_rank="$(jq -r --arg l "$current_status" '
           [.stages[] | .label] as $labels
           | (.stages[] | select(.label == $l and .advances_on == "merge"))
           | ($labels | index($l)) + 1
       ' "$LIFECYCLE_JSON" 2>/dev/null || true)"
       [ -n "$merge_rank" ] || merge_rank=0
   fi
   ```

   `jq` emits nothing when no row matches both conditions, so
   `merge_rank` falls back to 0; the `|| true` and the `-n` guard keep
   `set -e` and `set -u` satisfied. The rank formula is the same one
   the artifact path uses (lines 140-141), so "furthest transition
   wins" is still the ladder file's ordering and not a second one. An
   issue with no `status:*` label, or one whose row's `advances_on` is
   not `"merge"`, keeps `merge_rank=0` and yields no merge candidate.
3. **Resolve.** `kind="artifact"` when `artifact_rank >= merge_rank`
   and `artifact_rank > 0`; `kind="merge"` when
   `merge_rank > artifact_rank`; when both are 0, `continue` (the
   provisional merge candidate is discarded). Ranks are never equal for
   a real pair: the artifact and merge rows of one issue are different
   rungs by construction.
4. **Row pick** (replacing lines 271-275) branches on `kind`:
   `select(.artifact == $a)` for artifact, and
   `select(.label == $l and .advances_on == "merge")` for merge.
   `target`, `message` and `marker_stage` are read exactly as in T4;
   `marker_stage` for the implement row is `in-review`, so the marker
   is `<!-- lifecycle:in-review:$AFTER -->` (D6). No new idempotency
   mechanism: once the label is `status:in-review`, step 2's gate can
   never produce a candidate for that pull request again.
5. **The Draft override** (lines 289-300) runs only when
   `[ "$kind" = "artifact" ] && [ "$stage" = "spec" ]`.
6. **One trigger string, used by both comment shapes.** Introduce
   `trigger_desc` immediately after the kind is resolved:

   ```bash
   if [ "$kind" = "merge" ]; then
       trigger_desc="pull request #${MERGE_PR[$issue]} merged in ${MERGE_SHA[$issue]:0:12}"
   else
       trigger_desc="\`$path\` added in ${AFTER:0:12}"
   fi
   ```

   Line 318 becomes `Trigger: $trigger_desc.$compression`, which for an
   artifact candidate renders byte-identically to the pin. The
   corrupted-state body (line 253) replaces `for the push that added
   \`$files\`` with `for $trigger_desc`; see *Readings and deviations*
   below. `compression` (lines 302-307) stays artifact-only: it is
   skipped when `$files` is empty.

**Proves it (Acceptance 2, 5, 6, 7), asserted by T10.**

*Amended in implementation (odyssey):* `trigger_desc` cannot be
introduced "immediately after the kind is resolved" as step 6 says,
because the corrupted-state comment (step 2's block, which the plan
leaves in place ahead of the contest) needs it. It is therefore set
**twice**: provisionally before the corrupted-state block, keyed on
whether the range added files for the issue, and definitively from
`kind` once the contest is decided. The two agree in every case except
an issue that has both candidates, where only the definitive one is
reached. Consequently deviation 3 below is narrowed: the *corrupted*
body is no longer byte-identical to the pin for an artifact candidate
either — its one varying clause now reads ``for `intent/<n>-<slug>/
plan.md` added in <sha12>`` where the pin read ``for the push that
added `intent.md plan.md` ``. Acceptance 6's actual requirement, one
body shared by both paths differing only in that clause, holds and is
asserted by S9; the pin's exact wording could not be kept without
either a second body or a `Trigger:` line that no longer says
`added in`, which S1/S16 assert.

## T8 · `scripts/ci/lifecycle_advance.sh` — clear `intent:new` — D7

In the label block (lines 324-334), build the removal list before
writing:

```bash
remove="$current_status"
if grep -Fxq "intent:new" <<<"$labels"; then
    remove="${remove:+$remove,}intent:new"
fi
```

Then:

- empty `target` → `continue` unchanged (a Draft spec, and the review
  row, remove nothing);
- `current_status` equals `target` → **do not** short-circuit when
  `intent:new` is present: call `edit_labels "$issue" "" "intent:new"`
  and log it; only when `intent:new` is absent does the existing
  `already at $target — no label write` line stand;
- otherwise `edit_labels "$issue" "$target" "$remove"` — one
  `gh issue edit`, both labels.

`edit_labels` already passes its remove argument straight to
`--remove-label` (line 189) and `gh` accepts a comma-separated list, so
the helper needs no change. `status:planning` gains no writer here and
`scripts/ops/work.sh` is not touched (D14).

**Proves it (Acceptance 8), asserted by T10** plus
`grep -c 'status:planning' scripts/ci/lifecycle_advance.sh` returning 0
(true only after T9 rewrites the header, which is the last place that
literal survives) and `git diff origin/main --stat -- scripts/ops/work.sh`
being empty.

## T9 · `scripts/ci/lifecycle_advance.sh` — the header and the header block — D11

1. `COMMENT_HEADER` (lines 162-164) becomes, verbatim from D11:

   ```text
   _Posted by `.github/workflows/lifecycle.yml` (#4) — deterministic, no model call. This workflow writes the `status:*` ladder up to and including `status:in-review`, and clears `intent:new` with the first status it writes. The `review:1..3` counter and `status:review-stuck` are review state and belong to the review automation (#8/#9)._
   ```

2. The script's own header block, lines 25-28 ("What this script
   deliberately does NOT write: `status:in-review` and the
   `review:1..3` counter…"), is reworded to the same two-part shape:
   what this script writes (the whole ladder, plus the `intent:new`
   clearing) and what it deliberately does not (the `review:N` counter,
   `status:review-stuck`, and closing the issue — D8).
3. Lines 6-23 gain one sentence: the implement rung advances on a
   merged pull request found through `gh api
   repos/<repo>/commits/<sha>/pulls`, selected by the row's
   `advances_on` column, and the ladder still lives in
   `personas/lifecycle.json`.
4. Add the two new invariants to the block at lines 30-47:
   *merge is a rung* (a merged pull request resolving to an issue at
   the `"merge"` row advances it; a push with no pull request advances
   nothing) and *a closed issue at the merge rung is red* (D9).

**Proves it (Acceptance 11), asserted by T10:**
`grep -c 'get their writers with #8/#9' scripts/ci/lifecycle_advance.sh`
is 0; every scenario's output contains the new header; a merge
candidate's body contains `Trigger: pull request #` and an artifact
candidate's contains `added in`. The pre-existing assertion that the
advancer carries no `status:spec` literal (test lines 167-171) still
passes — `status:in-review` and `status:*` do not match it.

*Amended in implementation (odyssey):* step 2's reworded header block
must not name `status:planning` either, or T8's proving check
(`grep -c 'status:planning' … = 0`) fails on the very sentence that
replaces the dead-end one. It reads "the `status:*` ladder end to end,
up to and including `status:in-review`" — D11's own phrasing for
`COMMENT_HEADER` — and S16 now asserts both greps.

## T10 · `scripts/ci/tests/lifecycle_advance_test.sh` — the proof — D13

Hermetic throughout: throwaway git repository, `DRY_RUN=1`, stub `gh`
first on `PATH`, no network, no token, and the final
`[ ! -s "$WRITES" ]` assertion (line 178) unchanged. Every expected
label and message is read from the fixture copy of
`personas/lifecycle.json` with `jq` — never a literal. Add a second
helper beside `row()` (line 102):

```bash
# lrow <label> <key> -> the value the script must read for a merge rung
lrow() { jq -r --arg l "$1" ".stages[] | select(.label == \$l) | .$2" \
           "$SANDBOX/personas/lifecycle.json"; }
```

**Stub.** The stub (lines 37-49) learns to answer from fixture files in
`$WORK/fixtures/`, and keeps recording everything else as an attempted
write that fails the run:

- `gh api repos/*/commits/<sha>/pulls` → `cat
  "$WORK/fixtures/pulls-<sha>.json"` if it exists, else `echo '[]'`.
- `gh api repos/*` (the default-branch read) → `{"default_branch":"main"}`.
- `gh issue view <n> …` → `cat "$WORK/fixtures/issue-<n>.json"` if it
  exists, else `exit 1` — which preserves today's "DRY_RUN substitutes
  an open, unlabelled issue" path for every pre-existing scenario, so
  none of them changes.
- anything else → appended to `$WRITES` and `exit 1`, unchanged.

  This is a deviation from D13's "exactly one new answer"; see
  *Readings and deviations*.

**Scenarios**, each with a banner naming its D-rows:

| # | Scenario | Fixture | Asserts |
|---|----------|---------|---------|
| S1 | merge by branch name (D1, D4, D6, D11) | `pulls-<C4>.json` with `merged_at` set, `base.ref main`, `head.ref odyssey/999-test`; `issue-999.json` OPEN, labels `[status:implementing]` | `--add-label $(lrow status:implementing advances_to)`, `--remove-label status:implementing`, the message from `lrow status:implementing advance_message`, `<!-- lifecycle:in-review:<C4> -->`, `Trigger: pull request #` |
| S2 | keyword fallback (D2) | same, `head.ref hotfix-no-number`, body `Closes #999` | identical transition to S1 |
| S3 | disagreement (D2) | `head.ref odyssey/999-test`, body `Closes #998` | exit 1, output names `#999` and `#998`, `$WRITES` empty |
| S4 | squash shape (D1) | one non-merge commit on the trunk whose sha has a `pulls-*.json` | the S1 transition |
| S5 | no pull request (D1) | no `pulls-*.json` | exit 0, `nothing to advance` in the output, no `--add-label` |
| S6 | closed at the merge rung (D9) | `issue-999.json` `state CLOSED`, labels `[status:implementing]` | exit 1, `::error::` naming `#999`, `$WRITES` empty, no `--add-label`, no `gh issue comment` |
| S7 | closed, no status (D9) | `state CLOSED`, labels `[]` | exit 0, `skipping` in the output |
| S8 | `hold` on a merge candidate (D5) | labels `[status:implementing, hold]` | no `--add-label`, no comment |
| S9 | two `status:*` on a merge candidate (D5) | labels `[status:implementing, status:build]` | the corrupted-state body, `--add-label hold`, and the body's wording identical to the artifact path's apart from its `Trigger` clause |
| S10 | artifact + merge for one issue (D5) | range adds `intent/999-test/plan.md` **and** carries a merged pull request for #999 at `status:implementing` | exactly one `--add-label`, exactly one comment body, and the label is `status:in-review` |
| S11 | re-run / already advanced (D6) | `issue-999.json` labels `[status:in-review]` | no candidate at all, no `--add-label`, no comment |
| S12 | `intent:new` cleared (D7) | labels `[status:implementing, intent:new]` | one `gh issue edit` carrying both `--add-label status:in-review` and `--remove-label` containing `intent:new` |
| S13 | `intent:new` at the target label (D7) | labels `[status:in-review, intent:new]` on an **artifact** candidate whose row targets `status:in-review` | `--remove-label intent:new` still printed |
| S14 | Draft removes nothing (D7) | the existing #998 Draft range with `issue-998.json` carrying `intent:new` | no `--remove-label` |
| S15 | review row is inert (D8, D10) | fixture patched with `jq` so review's `advances_on` is `"merge"`, issue at `status:in-review` | no `--add-label`, no comment, and `hasnt "--add-label null"`, `hasnt "null"` as a body line |
| S16 | header (D11) | any transition | the new `COMMENT_HEADER` present; `hasnt "get their writers with #8/#9"` |

Keep every pre-existing scenario (test lines 106-175) unchanged and
passing; they are the regression proof that the artifact path did not
move.

**Proves it:** `bash scripts/ci/tests/lifecycle_advance_test.sh` exits
0 with an empty write log.

*Amended in implementation (odyssey):* the fixtures the table calls for
need three commits the #4 fixture does not have, so the sandbox gains
`C4` (a plain commit on the trunk — the squash shape), `CM` (a real
`--no-ff` merge commit) and `C5` (a commit adding
`intent/997-both/plan.md`, for S10's contested issue). Four helpers
carry them: `run_fail` (S3 and S6 must end red, and `run` asserts exit
0), `issue_fixture` / `pulls_fixture` (write the two fixture shapes
with `jq -n`, never a heredoc literal) and `count` / `exactly` (S10 and
S12 assert *how many* writes, not just which). S13's "artifact
candidate whose row targets `status:in-review`" is produced with the
same `jq` fixture patch the pre-existing last scenario uses, so no
literal label is introduced.

## T11 · `docs/SPEC.md` — the living-spec upsert — D12

Two entries, both **upserted in place**, both citing `(PR #<n>)`. No
entry is added, none is deleted, and the section count is unchanged.

- **`lifecycle.labels`** (lines 206-246). Reword to state: the
  merge-driven transition and how a pull request resolves to an issue
  (D1, D2); `advances_on` as the trigger column the script reads and
  never infers (D4); the `intent:new` clearing on the first status
  written (D7); the workflow's third scope `pull-requests: read` (D3);
  a closed issue still carrying the merge rung's label being a red
  counted failure that writes nothing (D9); the null-safe reads, so a
  row with no `advances_to` writes no label and a row with no
  `advance_message` posts no comment (D10). **The exact sentence being
  replaced** is the entry's closing one, lines 245-246: "`status:in-review`
  and the `review:N` counter exist in the taxonomy but are not written
  by this workflow; their writers arrive with #8/#9." Its replacement
  says the ladder is written end to end here, and that `review:N` and
  `status:review-stuck` remain #8/#9's.
- **`personas.resume`** (lines 155-177). Two edits: the key list at
  lines 158-159 gains `advances_on`; and the reader sentence at lines
  163-165, "`scripts/ci/lifecycle_advance.sh` matches on `artifact` to
  pick a transition (`lifecycle.labels`)", becomes "matches on
  `advances_on`, then on `artifact` or on the issue's current `label`".
- `review.policy` (lines 268-270) already points at `lifecycle.labels`
  for the taxonomy and needs no edit.

**Proves it (Acceptance 12):**
`grep -c 'their writers arrive with #8/#9' docs/SPEC.md` is 0;
`grep -c 'advances_on' docs/SPEC.md` is at least 2;
`grep -c '^### ' docs/SPEC.md` is unchanged from `origin/main`;
`bash scripts/ci/spec_check.sh origin/main` exits 0 with the diff
touching `docs/SPEC.md`.

## T12 · `AGENTS.md` and `README.md` — one clause each — D9, D8

- **`AGENTS.md:122`** — "the PR body carries `Closes #<n>` only when it
  completes the issue's final stage." Add the clarifying clause: in the
  five-rung flow the final rung (review) produces a review and not a
  pull request, so no pull request in that flow carries `Closes #<n>`
  and the human closes the item; the defect-repair path (#32) is
  unchanged, because its fix pull request *is* the final stage.
- **`README.md:90-92`** — "**Review.** Two reviewers read the change
  and post findings; this rung ends the ladder." Add one clause: when
  the review is done the human closes the item — nothing in the
  automation closes an issue.

Both are one clause; no section is added, moved or renamed. Both files
are behaviour-bearing to `spec_check.sh`
(`AGENTS.md` is on its list; `README.md` is not), which T11 already
satisfies.

**Proves it (D8, D9):**
`grep -n 'final stage' AGENTS.md` shows the new clause;
`grep -n 'ends the ladder' README.md` shows the new clause;
`bash scripts/ci/sanitize_check.sh` exits 0.

## T13 · Gates and the end-to-end — Acceptance 13, 14

Run, all from the repository root, all exit 0:

```bash
bash -n scripts/ci/lifecycle_advance.sh
bash scripts/ci/tests/lifecycle_advance_test.sh
bash scripts/ci/spec_check.sh origin/main
bash scripts/ci/sanitize_check.sh
python3 scripts/sync_agents.py --check
git diff origin/main --name-only | grep -E '^(\.claude/agents/|\.agents/agents/)' && exit 1 || true
```

**Acceptance 14 is proved by this change's own merge and is verified
after it, not in CI.** #57 sits at `status:implementing` the moment the
plan PR merges; the implementing pull request is therefore the first
real specimen of D1. After it merges, confirm on #57:

```bash
gh api repos/evekhm/agentic-sdlc/issues/57 --jq '[.labels[].name]'
DRY_RUN=1 scripts/ops/work.sh 57 --as argus
```

Expected: exactly one `status:*` label, `status:in-review`, no
`intent:new`; `work.sh` resolves the review rung and exits 0. Record
the two outputs in the handoff comment on #57. If the workflow run is
red instead, that is the D9 path or a missing scope (T1/P3) and the
repair is a follow-up commit on the same issue, not a new one.

---

## Acceptance → task

| Acceptance | Task(s) | Proving check |
|---|---|---|
| 1 | T2 | the three `jq -e` invocations in T2 |
| 2 | T6, T7 | T10 S1 |
| 3 | T6 | T10 S2, S3 |
| 4 | T6, T5 | T10 S4, S5 |
| 5 | T7 | T10 S6, S7 |
| 6 | T5, T7 | T10 S8, S9, S10 |
| 7 | T7 | T10 S11 + re-running any earlier scenario's range |
| 8 | T8, T9 | T10 S12, S13, S14 + `grep -c 'status:planning' scripts/ci/lifecycle_advance.sh` = 0 + empty `work.sh` diff |
| 9 | T4 | T10 S15 |
| 10 | T3 | the `git diff` and two `grep -c` in T3 |
| 11 | T9 | T10 S16 + the `Trigger:` assertions in S1 and the artifact scenarios |
| 12 | T11 | the four `grep -c` in T11 |
| 13 | T13 | the six commands in T13 |
| 14 | T13 | post-merge on #57: the label read and the `work.sh` dry run |

## Readings and deviations

Three places where the spec cannot be executed exactly as written. Each
names the evidence and the smallest deviation; none re-opens a
decision.

1. **D13's "the stub learns exactly one new answer" cannot hold.**
   `scripts/ci/tests/lifecycle_advance_test.sh:43-45` makes `gh issue
   view` fail on purpose, so `lifecycle_advance.sh:217-219` substitutes
   an open, **unlabelled** issue. Acceptance 2 requires "#999 at
   `status:implementing`", 5 requires it CLOSED and labelled, 6
   requires `hold` and a double `status:*`, and 8 requires
   `intent:new` — none of which the substitute can express.
   **Smallest deviation:** the stub learns *two* answers, `api
   repos/*/commits/*/pulls` and `issue view`, both from fixture files,
   with a missing fixture falling through to today's `exit 1`. Every
   property D13 names survives: hermetic, offline, `DRY_RUN=1`, no
   token, and any other `gh` invocation still recorded as an attempted
   write. No pre-existing scenario changes behaviour.
2. **Acceptance 6's "byte-identical" corrupted-state comment.** The
   body at `lifecycle_advance.sh:253` ends "…no stage transition was
   made for the push that added `$files`", and a merge candidate has no
   `$files`. **Smallest deviation:** the one varying clause becomes
   `$trigger_desc` (T7 step 6), so the corrupted body is literally
   shared between the two paths and renders byte-identically to the pin
   for an artifact candidate. Everything else in that comment is
   unchanged.
3. **D11's `Trigger: pull request #<pr> merged in <sha12>` — which
   sha.** The artifact form uses `${AFTER:0:12}` and so does the
   idempotency marker. For a merge candidate `AFTER` may be a later
   commit than the one that carried the pull request, which would make
   the sentence false. **Reading taken:** `<sha12>` is the first-parent
   commit the pull request was found on (`MERGE_SHA[$issue]`); the
   marker still uses `AFTER`, unchanged, because D6 pins it there.

Two smaller readings, recorded so the implementer does not re-decide
them: (a) D9 does not say what a *closed* issue with more than one
`status:*` does — T7 gives it the quiet skip, because "never guess on
two status labels" (#4 D1) outranks the red failure and no row can be
identified; (b) when discovery finds two merged pull requests resolving
to the same issue in one range, the later one (by first-parent order)
wins — hence `git rev-list --reverse` in T6.

## Out of scope

- **`review:1`/`review:2`/`review:3` and `status:review-stuck`** stay
  with #8 and #9. This change gives them a `status:in-review` they no
  longer have to write.
- **The review pipelines themselves** — Argus's workflow, Atlas's
  sidecar, consensus — are #8/#9 and depend on #25.
- **#52's AT-3**, validating `personas/lifecycle.json` against a schema
  in `scripts/sync_agents.py --check`, stays on #52, whose job now also
  covers `advances_on` (D10). Only AT-4, the null-safe reads, lands
  here (T4).
- **`scripts/ops/work.sh`, `scripts/sync_agents.py`,
  `scripts/auth/**`, `personas/schema.json`, `personas/*.yaml`,
  `config/**`** and every compiled target under `.claude/agents/` or
  `.agents/agents/` are untouched (D14). `work.sh`, the compiler and
  auth are #43's this week.
- **`scripts/ops/post.sh`** (#25's merged plan, T7) is unbuilt; this
  change keeps posting through `post_comment`/`edit_labels` and takes
  no dependency on it.
- **Anything that closes an issue.** D8 fixes that the ladder ends at
  review and the human closes; no automation for it is proposed here.
- **Daedalus's `tests/**` authority glob**, which names a directory
  that does not exist, is #54's.

## Pull request rules for the implementing PR

- **Reference `#57`. No `Closes #57`, no closing keyword of any form.**
  That is D9 and it is load-bearing twice over: this pull request is
  not the issue's final stage, and a closed #57 at the merge rung is
  exactly the red failure T7 adds. The human closes #57 after review.
- The spec obligation is met by T11's `docs/SPEC.md` upsert, so the
  body carries **no** `Spec-impact:` marker — the diff touches
  `docs/SPEC.md`, which is what `scripts/ci/spec_check.sh` checks for.
- The body carries the plan sync (any task amended during
  implementation is annotated in this file, in the style
  `intent/36-dispatch/plan.md` uses: *Amended in implementation
  (odyssey): …*), the T13 gate results, and the `runs/` diff evidence
  from T5 showing the artifact path unchanged.
- One pull request, pinned to target SHA
  `3d21db59ddd002f8c19a7fc6e213b2f9604cc6c9`.
- No AI attribution anywhere: no `Co-Authored-By`, no "Generated with"
  line, in any commit message or body.
