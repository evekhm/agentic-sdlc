# Plan: a reviewer at a pull request is reviewing that pull request

**Issue:** #207 · **Spec:** spec.md (Approved, D1–D10, AT-1..AT-14) ·
**Author:** daedalus (`evekhm-daedalus-app[bot]`)

Seven tasks. Each names the files it touches, the steps in order, the
Decision rows it implements, the acceptance tests it makes pass, and
its done-when. **Implement on top of `origin/main` at the SHA the
dispatcher pins; this plan was verified at `bf69ca1`.** Every
`file:line` below was re-read at that commit, and where the spec's own
citation no longer matches the tree this plan says so and uses the
verified line.

Order: T1 (tests, all red) → T2 (`lib/github.sh`) → T3 (predicate and
retarget) → T4 ((g) pass-through) → T5 (prompt and report) → T6
(`docs/SPEC.md`) → T7 (gates). T2 through T5 each turn part of T1's
suite green and none of them is green alone; T6 commutes with T2–T5;
T7 needs all six.

**Three verified corrections to the spec's citations.** None changes a
decision.

1. **AT-3 has no existing scenario.** It cites `work_test.sh:596`,
   which is `run 2 "D5(f): --as naming a non-owner exits 2" -- 112
   --as odyssey` — odyssey at a **review** rung, the mirror image of
   the row AT-3 describes (argus at a **non-review** rung). T1 writes
   it as a new row.
2. **AT-4's existing scenario uses `--as atlas`, not `--as argus`**
   (`work_test.sh:609-611`). Atlas is equally an owner of `review`, so
   the row does prove the property; T1 adds the argus spelling beside
   it for exactness rather than editing the existing row.
3. **AT-1 has no existing scenario either.** The nearest is
   `work_test.sh:408-411`, which is a bare **issue** with no `--as`.
   AT-1 needs a pull request plus `--as odyssey`, so T1 writes it. The
   *message* it asserts is byte-identical to that row's, which is what
   "byte-identical to the existing scenario" means and all this plan
   holds the implementer to.

Everything else the spec cites was confirmed at `bf69ca1`, including
`lifecycle.json:59-67` / `:61` / `:66`, `work.sh:409-428` (g),
`:430-433` (h), `:692-709` the report, `:763-773` the multi-owner
block, and `docs/SPEC.md:451` and `:467-470`.

---

## The six calls this plan makes

The spec left these to the plan. Each is decided here; the
implementer does not re-open them.

**P1 · `head.repo.full_name` comes from the pulls read `branch_issue()`
already performs, hoisted.** In `resolve_issue()`, call
`branch_issue "$number"` unconditionally inside the `IS_PR=1` block
instead of only on the no-closing-keyword fallback, and extend
`branch_issue()` to set `PR_HEAD_REPO` from the same response.
Reason: it is one read on every pull-request path and **zero new
reads on the fallback path**, where today's read already happens; a
second `gh_json "repos/$GITHUB_REPO/pulls/$number"` call in
`resolve_issue()` would fetch the same object twice whenever the body
carries no closing keyword.

**P2 · The reviewer gets the number through a second literal that
overwrites `PROMPT` on the review path only.** `REVIEW_PROMPT` is
declared immediately after the `PROMPT=` assignment at `work.sh:547`,
and one guarded line copies it over `PROMPT` when
`REVIEW_DISPATCH=1`. Reason: the `PROMPT=` line stays byte-identical
(AT-14), and `launch_argv()` (`:611`, `:635`, `:653`) and the report
(`:705`) need no edit at all, so the prompt a launch uses and the
prompt the report prints cannot diverge.

**P3 · One predicate function, evaluated once, retargeting `stage`
before the lifecycle row is read.** `review_dispatch()` is evaluated
between the stage derivation (ending `work.sh:328`) and `row=`
(`:330`); on success it sets `REVIEW_DISPATCH=1` and `stage=review`,
and the existing `:330-354` block then derives `row`, `label`,
`brief`, `artifact` and `owners` from the `review` row through the jq
the code already uses. Reason: zero duplicated jq — the retarget is a
one-word change to an input, not a second copy of the derivation.

**P4 · The report names the retarget and prints the issue's own rung
label.** Exact text in T5. Reason: D10 forbids asserting a label the
issue does not carry, and the rung label is the one true label in
view.

**P5 · Two `docs/SPEC.md` sentences, drafted verbatim in T6** so the
implementer pastes rather than writes.

**P6 · One new test block, inserted above the safety guard**
(`work_test.sh:746-750`). Reason: every new scenario is resolve-only
or a dry run, so placing them above the guard makes AT-12 free —
the guard already asserts `$WRITES`, `$LAUNCHES` and `$MINTS` are
empty for everything above it. The `#165` block sits *below* the
guard because it deletes fixtures the guard's own scenarios need; the
new block has no such need and belongs above.

---

## T1 · The acceptance suite, written first and all red — AT-1..AT-8, AT-11..AT-14

Touch: `scripts/ops/tests/work_test.sh`.

### 1a · `pr()` gains a head repository

Replace the `pr()` helper at `:260-269`. Its current second line is

```bash
  jq -n --arg ref "$3" '{head: {ref: $ref}}' \
    > "$FIXTURES/repos_test_repo_pulls_$1.json"
```

The helper's signature becomes
`pr <n> <body> <head-ref> [<labels-csv>] [<head-repo>]`, the comment
line above it is updated to match, and the second line becomes

```bash
  jq -n --arg ref "$3" --arg repo "${5:-test/repo}" \
    '{head: {ref: $ref, repo: {full_name: $repo}}}' \
    > "$FIXTURES/repos_test_repo_pulls_$1.json"
```

`test/repo` is the suite's `GITHUB_REPO` (`work_test.sh:63`), so every
existing `pr()` call keeps producing a same-repository head with no
edit. The stub `gh` maps `repos/test/repo/pulls/<n>` to
`$FIXTURES/repos_test_repo_pulls_<n>.json` by the path-to-fixture rule
at `:105`; that is the only fixture T2's new read needs, and `pr()`
has always written it.

### 1b · The new block

Insert as one block after the `D7` scenarios end at `:744` and
**before** the `banner "nothing above this line launched or wrote"` at
`:746`. Fixture numbers 207–215 are unused by the suite.

```bash
banner "#207 a reviewer at a same-repo pull request reviews that pull request"
# The ladder issue is claimed by the rung's author for the whole review
# window (AGENTS.md step 5-6), which is wall 1, and its rung is never
# `review`, which is wall 2. Both fall for a review dispatch and for
# nothing else.
issue 207 open "in-progress,status:build" "Review mutex"
claim 207 "evekhm-daedalus-app[bot]" "Claim: BUILD stage — daedalus."
pr 208 "Closes #207" "daedalus/207-review-mutex"

# AT-1 (D7): a NON-review persona at that pull request is unchanged.
run 2 "#207 AT-1: --as odyssey at a ladder PR still refuses at (g)" -- 208 --as odyssey
has "in-progress on #207 is held by daedalus" \
  "#207 AT-1: today's (g) message, unchanged"
hasnt "stage:    review" "#207 AT-1: no retarget for a non-review persona"

# AT-2 (D3 + D2) and AT-8 (D10) and AT-14 (D8): argus passes (g)
# without reading the thread, is measured against `review`, and is told
# the pull request number.
run 0 "#207 AT-2: --as argus at the same PR reaches the launch step" -- 208 --as argus
has "stage:    review (pull request #208; #207 is on build)" \
  "#207 AT-8: the report names the retarget and the rung it displaced"
hasnt "label:    status:in-review" \
  "#207 AT-8: no line asserts a label the issue does not carry"
has "label:    status:build" "#207 AT-8: the label line is the issue's own rung"
has "prompt:   Review pull request #208 for issue #207" \
  "#207 AT-14: the reviewer is told the pull request number"
has "==> DRY_RUN=1" "#207 AT-2: it reaches the launch step"

# AT-11 (D1b): atlas gets the property on the same terms.
run 0 "#207 AT-11: --as atlas at the same PR reaches the launch step" -- 208 --as atlas
has "--> atlas" "#207 AT-11: the second reviewer is dispatched"
has "stage:    review (pull request #208; #207 is on build)" \
  "#207 AT-11: one reviewer's presence does not gate the other's"

# AT-3 (D1b): a review persona at a BARE ISSUE number is refused as
# today — the pull-request form is a conjunct, not a convenience.
issue 209 open "status:build" "A build rung with nobody holding it"
run 2 "#207 AT-3: --as argus at a bare issue on a non-review rung exits 2" -- 209 --as argus
has "argus does not own stage build" "#207 AT-3: (h) refuses it by the stage it owns"

# AT-4 (D2, refusal f): the retarget happens AFTER the rung is derived,
# so a repair-path pull request still refuses at (f). #82's, not this
# issue's. The atlas spelling of this row already exists at :609-611.
run 2 "#207 AT-4: --as argus at a repair-path PR still refuses at (f)" -- 141 --as argus
has "refused: cannot derive a stage for #140" \
  "#207 AT-4: (f) precedes the retarget"

# AT-5 (D1c): a fork head takes the ORDINARY path, fail-closed.
pr 210 "Closes #207" "daedalus/207-review-mutex" "" "somebody-else/agentic-sdlc"
run 2 "#207 AT-5: a fork-head PR takes the ordinary path and refuses" -- 210 --as argus
has "in-progress on #207 is held by daedalus" "#207 AT-5: (g) refuses it as it refuses anyone"
hasnt "stage:    review" "#207 AT-5: no retarget for a fork head"

# AT-6 (D6): a bare pull-request dispatch is unchanged in both shapes.
pr 211 "Closes #112" "odyssey/112-under-review"
DRY=0 run 0 "#207 AT-6: a bare PR at a two-owner stage launches neither" -- 211
has "printing both and launching neither" "#207 AT-6: #2 D4 is untouched"
pr 212 "Closes #209" "daedalus/209-a-build-rung"
run 0 "#207 AT-6: a bare PR at a one-owner stage takes the ordinary path" -- 212
has "stage:    build" "#207 AT-6: no --as, no retarget"

# AT-7 (D3 order): (a)-(f) still precede the pass-through.
pr 213 "Closes #207" "daedalus/207-review-mutex" "hold"
run 2 "#207 AT-7: hold on the pull request refuses a review dispatch at (a)" -- 213 --as argus
has "#213 (the pull request) carries hold" "#207 AT-7: (a) still runs first and names the side"

# AT-13 (D3): the pass-through is unconditional on the thread, and the
# thread is not read — not even to discover that it names no holder.
issue 214 open "in-progress,status:build" "Held, with an empty thread"
pr 215 "Closes #214" "daedalus/214-held-no-claim"
run 0 "#207 AT-13: a review dispatch over an unnamed mutex exits 0" -- 215 --as argus
hasnt "the mutex names no holder" "#207 AT-13: the claim is not read at all"

# AT-14 (D8), second half: every non-review prompt is byte-identical to
# today's literal. The source-level guard at :682-695 already forbids a
# second `Work issue #$ISSUE` literal; this asserts the rendered line.
run 0 "#207 AT-14: an ordinary dispatch still prints today's prompt" -- 108
has "prompt:   Work issue #108 in this repository. Follow your persona instructions and the repository's AGENTS.md; when you finish or refuse, print one final line WORK-RESULT: <ok|refused|blocked> #108 <one-line reason>." \
  "#207 AT-14: the ordinary prompt literal is unchanged, byte for byte"
```

**Decisions:** D1, D2, D3, D5, D6, D7, D8, D10.
**Acceptance:** AT-1..AT-8, AT-11, AT-13, AT-14; **AT-12** comes free
from the guard at `:747-749` because the whole block sits above it.
**Done when:** `bash scripts/ops/tests/work_test.sh` fails, and every
failure is one of the new rows. If any row that this plan does not
name starts failing, stop and report: `pr()`'s new field has broken an
existing scenario, which it must not.

---

## T2 · `head.repo.full_name` reaches the dispatcher — D1(c), D9

Touch: `scripts/ops/lib/github.sh`.

1. Extend `branch_issue()` (`:57-82`). Add `PR_HEAD_REPO` to its
   header contract beside `BRANCH_ISSUE` and `BRANCH_REF`; add
   `PR_HEAD_REPO=""` beside the two existing resets at `:74-75`; and
   after the `head_ref` assignment at `:77` add

   ```bash
   PR_HEAD_REPO="$(jq -r '.head.repo.full_name // ""' <<<"$pr_view")"
   ```

   The `// ""` and the `return 1` already at `:76` are the whole of
   fail-closed: an unreadable pulls response leaves `PR_HEAD_REPO`
   empty, and empty is never equal to `$GITHUB_REPO`.

2. Hoist the call in `resolve_issue()` (`:95-134`). Add
   `PR_HEAD_REPO=""` to the reset block at `:97-101`, and immediately
   after `PR_JSON="$view"` at `:112` add

   ```bash
   # #207 D1(c): the head repository is a conjunct of the review-dispatch
   # predicate, and this is the read that already answers it on the
   # fallback path below. Non-fatal here: a pulls read that fails leaves
   # PR_HEAD_REPO empty, which is not a same-repository head, and the
   # fallback's own `[ -n "$BRANCH_ISSUE" ] || die` still reports an
   # unresolvable pull request with the message it always did.
   branch_issue "$number" || true
   ```

3. In the `else` arm at `:125-130`, delete the now-redundant
   `branch_issue "$number" || die "cannot resolve PR #$number to an
   issue"` at `:126` and keep `:127-129` exactly as written. The
   `die` message is unchanged for the caller: `:127` already carries
   the identical string.

4. Add `PR_HEAD_REPO` to the `resolve_issue` header comment block
   (`:84-89`), one line in the same style: *"the head repository of
   the input when `IS_PR=1`, empty when it could not be read"*.

`scripts/ops/post.sh:124` calls `branch_issue "$NUMBER" || true` and
is unaffected: it gains an unused variable and nothing else. Do not
touch it.

**Decisions:** D1(c), D9 (this file is inside the scope boundary
precisely because of this task).
**Acceptance:** makes AT-5 reachable; alone it makes nothing pass.
**Done when:** `bash scripts/ops/tests/work_test.sh` shows the same
failures as after T1 and no new ones — in particular `:494-503` (the
`Closes` path, the branch-name fallback, and `PR #111 resolves to no
issue`) still pass, which is what proves the hoist did not change
resolution.

---

## T3 · The predicate and the stage retarget — D1, D2, D4

Touch: `scripts/ops/work.sh`.

1. **Move `owners_of()` above the stage derivation.** Cut the block
   at `:336-350` — the `# --- Owners: derived from the sources, never
   stored (D2)` header, its two comment lines, and the whole
   `owners_of()` definition — and paste it immediately **above** the
   `# --- Stage, from the label, through the one table (D2, D4)`
   header at `:311`. Nothing else moves: `owners="$(owners_of
   "$stage")"` and its `die` stay where they are at `:352-354`. A
   function definition has no side effects, so this is a pure
   relocation; it is needed because the predicate reads `owners_of
   review` and must run before `row=` at `:330`.

2. **Insert the predicate** between the close of the stage
   derivation at `:328` and `row=` at `:330`:

   ```bash
   # --- The review dispatch (#207, D1, D2) ----------------------------------------
   # A reviewer dispatched at a pull request of THIS repository is
   # reviewing that pull request, not claiming the issue's work. All
   # three conjuncts, and nothing else is a review dispatch: the number
   # resolved as a pull request; --as names a persona that declares the
   # review stage; and the head repository is this one. The third is a
   # fail-closed duplicate of a rule .github/workflows/unattended.yml
   # already owns for the unattended path — work.sh is also invoked by
   # hand, where no workflow guard stands in front of it, and if the two
   # ever disagree the workflow is right and this is a bug (D1c).
   #
   # It is evaluated HERE, after (e) and (f): the issue's rung is still
   # derived from its own status:* label alone, so a repair-path pull
   # request whose issue carries only `bug` still refuses at (f) and
   # stays #82's. The retarget then feeds the rung table below, so
   # `label`, `brief`, `artifact` and `owners` all come from the review
   # row of personas/lifecycle.json through the same jq as every other
   # stage — no second derivation, no new label, no new stage value (D4).
   review_dispatch() {
       [ "$IS_PR" = "1" ] || return 1
       [ -n "$AS" ] || return 1
       grep -Fxq "$AS" <<<"$(owners_of review)" || return 1
       [ -n "$PR_HEAD_REPO" ] && [ "$PR_HEAD_REPO" = "$GITHUB_REPO" ]
   }
   RUNG_STAGE="$stage"
   RUNG_LABEL="$status_labels"
   REVIEW_DISPATCH=0
   if review_dispatch; then
       REVIEW_DISPATCH=1
       stage="review"
   fi
   ```

`RUNG_LABEL` is `$status_labels` (`:304`), which is the issue's single
`status:*` label or empty when the issue reached a stage through
`intent:new`. Both are what T5's report prints.

**Decisions:** D1, D2, D4, and D6 by omission — the `[ -n "$AS" ]`
conjunct is what leaves a bare pull-request dispatch alone.
**Acceptance:** with T4 and T5 it makes AT-2, AT-5, AT-6, AT-11 pass.
**Done when:** `--as argus` at a same-repository ladder pull request
reaches (g) with `stage` equal to `review` and `owners` equal to
`argus atlas`; `bash scripts/ops/tests/work_test.sh` still fails on
the (g) rows only.

---

## T4 · Refusal (g) passes a review dispatch through — D3, D5

Touch: `scripts/ops/work.sh`.

One edit. At `:410`, replace

```bash
if has_label "in-progress"; then
```

with

```bash
if [ "$REVIEW_DISPATCH" != 1 ] && has_label "in-progress"; then
```

and add to the rationale block above it (`:374-408`), as its last
paragraph, before `claim_holder=""` at `:409`:

```
#     A REVIEW DISPATCH is passed through here without reading the
#     claim at all — no label read, no thread read, none of the four
#     messages above (#207, D3). The mutex protects one issue's working
#     tree; a review dispatch writes no branch, holds no worktree and
#     produces comments, so the collision this refusal prevents cannot
#     occur on that path. Everything else about (g) is unchanged, for
#     every other caller, at an issue or at a pull request: it keeps its
#     position in D5's order, it keeps its count, and it keeps its
#     meaning — passing through rather than re-deciding is what makes
#     that true. The claim itself is untouched and stays held by the
#     rung's author for the whole review window (D5).
```

`claim_holder=""` at `:409` stays exactly where it is: it is what T5's
report branch tests against, and a review dispatch leaves it empty by
construction.

Refusal (h) at `:430-433` is **not** edited. It passes by construction
of D1(b) — `--as` names an owner of `review`, and `owners` is now the
owners of `review`. That is the mechanism, not an exemption.

**Decisions:** D3, D5.
**Acceptance:** AT-2, AT-11, AT-13; leaves AT-1, AT-5, AT-7 passing,
which is the point — they are the rows that prove nothing else moved.
**Done when:** the `#207` rows that expect exit 0 exit 0, and every
pre-existing `D5(e)` row from `:407` to `:472` still passes.

---

## T5 · The prompt and the report — D8, D10

Touch: `scripts/ops/work.sh`.

### 5a · `REVIEW_PROMPT`

Leave the `PROMPT=` assignment at `:547` and its comment block at
`:537-546` **byte-identical**. Immediately after `:547` add:

```bash
# THE REVIEW PROMPT (#207, D8). A reviewer told to "work issue #M" while
# the artifact under review is pull request #N has to re-derive #N from
# the issue — the exact guess the resolver exists to prevent. This
# literal is used only when the review-dispatch predicate holds, and it
# mirrors PROMPT's WORK-RESULT sentence unchanged. The rule PROMPT
# protects is intact: a pull-request number is not a stage, a folder, an
# artifact or a branch, and a review dispatch's stage IS current (D2).
REVIEW_PROMPT="Review pull request #$NUMBER for issue #$ISSUE in this repository. Follow your persona instructions and the repository's AGENTS.md; when you finish or refuse, print one final line WORK-RESULT: <ok|refused|blocked> #$ISSUE <one-line reason>."
[ "$REVIEW_DISPATCH" != 1 ] || PROMPT="$REVIEW_PROMPT"
```

**The literal must not contain the substring `Work issue #$ISSUE`.**
`work_test.sh:687-689` counts occurrences of that string in `work.sh`
and fails unless there is exactly one; `:691-693` additionally forbids
the line carrying it from naming a stage, plan, spec or branch. The
text above satisfies both, and neither existing assertion is edited.

`launch_argv()` (`:611`, `:635`, `:653`) and the report's `prompt:`
line (`:705`) read `$PROMPT` and need no change.

### 5b · The report

Replace `work.sh:698-699`

```bash
echo "    stage:    $stage"
echo "    label:    $label"
```

with

```bash
if [ "$REVIEW_DISPATCH" = 1 ]; then
    # A job log is the only place a reader can tell a review dispatch
    # from a rung dispatch, and the operating rule is to read the job
    # log behind every green check (#207, D10). The label line prints
    # the issue's OWN rung label, never the review row's: the issue does
    # not carry that one, and printing it next to a claim the issue does
    # carry would assert a state that does not exist.
    echo "    stage:    $stage (pull request #$NUMBER; #$ISSUE is on $RUNG_STAGE)"
    echo "    label:    ${RUNG_LABEL:--} (#$ISSUE's rung; a review dispatch carries no label of its own)"
else
    echo "    stage:    $stage"
    echo "    label:    $label"
fi
```

Then replace the claim block at `:706-709` with

```bash
if has_label "in-progress"; then
    if [ "$REVIEW_DISPATCH" = 1 ]; then
        # (g) was passed through, so no holder was established and none
        # was looked for. Say that, rather than printing an empty name.
        echo "    claim:    in-progress on $(label_side in-progress), not read — a review dispatch is not measured against it (#207, D3)"
    else
        # Reaching here with `in-progress` means (g) established a holder.
        echo "    claim:    in-progress, held by $claim_holder"
    fi
fi
```

**This last edit is not named by the spec and is required by it.** D3
says the claim is not read; `claim_holder` is therefore empty; the
unguarded line at `:708` would print `claim: in-progress, held by`
with nothing after it, which is exactly the kind of assertion-about-a-
state-that-does-not-exist D10 forbids on the neighbouring line.

The `artifact:` line (`:700`) needs no change — the `review` row's
`artifact` is `null`, so `:334`'s default renders it. The `branch:`
line (`:745`) is left alone deliberately: it is a printed derivation,
not an instruction, and suppressing it for one dispatch kind would
make the report's shape depend on the caller (spec, Concerns).

**Decisions:** D8, D10, D5.
**Acceptance:** AT-8, AT-14, and the `stage:`/`prompt:` assertions of
AT-2 and AT-11.
**Done when:** `bash scripts/ops/tests/work_test.sh` exits 0.

---

## T6 · The living-spec upsert — D9, AT-9

Touch: `docs/SPEC.md`, `§ops.dispatch`. Both sentences below are
verbatim at `bf69ca1`; verify the line numbers before editing and
anchor on the quoted text if it has moved. **Edit the entries, not the
count** — "Eight refusals" at `:451` and "the eight refusal
conditions" at `work.sh:60` both stay as written, because (g) keeps
its position and still refuses every non-review dispatch.

### 6a · The (g) entry — `docs/SPEC.md:460-461`

**Now:**

> `in-progress` claimed by another
> actor; and `--as` naming a persona that does not own the stage.

**Becomes:**

> `in-progress` claimed by another
> actor — with one documented pass-through, a review dispatch, which
> is not measured against the claim at all and for which neither the
> label nor the thread is read (#207, D3); and `--as` naming a persona
> that does not own the stage.

### 6b · The "labels alone" sentence — `docs/SPEC.md:467-471`

**Now:**

> The stage is not part of that
> union:
> it is derived from the issue's labels alone, since the state machine
> belongs to the unit of work and a `status:*` label on a pull request
> must not decide which rung the issue is on.

**Becomes** (the existing sentence is unchanged; three sentences are
appended to it, in the same paragraph):

> The stage is not part of that
> union:
> it is derived from the issue's labels alone, since the state machine
> belongs to the unit of work and a `status:*` label on a pull request
> must not decide which rung the issue is on. One exception, and it is
> not a label: a **review dispatch** — the number given resolved as a
> pull request whose head is in THIS repository, and `--as` names a
> persona that declares the `review` stage — is dispatched at `review`
> rather than at the issue's rung (#207, D1, D2). The issue's rung is
> still derived first and from its own label alone, so a pull request
> whose issue is on no rung still refuses; the retarget then reads the
> `review` row of `personas/lifecycle.json` for its owners, brief and
> artifact, `--as` passes the eighth refusal by construction, and the
> report names both the retarget and the rung it displaced. Nothing is
> written and no label moves: the issue keeps its own `status:*` and
> its claim, held by the rung's author for the whole review window
> (#207, D5). A pull request whose head is a fork takes the ordinary
> path with its ordinary refusals; the workflow's same-repository
> guard remains the authoritative owner of that rule.

**Decisions:** D9.
**Acceptance:** AT-9.
**Done when:** `docs/SPEC.md` is in the diff and
`bash scripts/ci/spec_check.sh origin/main <body-file>` exits 0.
`scripts/ci/spec_check.sh:84-89` makes every path under `scripts/`
behavior-bearing, so the `Spec-impact: none` marker is not available
to this pull request and this task is what discharges the obligation.

---

## T7 · Gates, and the forbidden-path audit — AT-9, AT-10

Every command from the repository root, on the working tree with
T1–T6 applied.

| # | Command | Expected | Proves |
|---|---|---|---|
| 1 | `bash scripts/ops/tests/work_test.sh` | exit 0, every `#207` row passing and no pre-existing row newly failing | AT-1..AT-8, AT-11..AT-14 |
| 2 | `bash scripts/ci/sanitize_check.sh` | exit 0, `PASS`, and `scripts/ci/sanitize_allowlist.txt` gains no line | house rule |
| 3 | `bash scripts/ci/spec_check.sh origin/main <body-file>` | exit 0 | AT-9 |
| 4 | `git diff --name-only origin/main` | no path under `personas/`, `.github/workflows/` or `scripts/placement/`, and not `scripts/ops/claim.sh` | AT-10 |
| 5 | `bash scripts/ops/tests/execution_test.sh` and `bash scripts/ops/tests/placement_test.sh` | exit 0 | nothing else regressed |

The whole diff is exactly four files:
`scripts/ops/work.sh`, `scripts/ops/lib/github.sh`,
`scripts/ops/tests/work_test.sh`, `docs/SPEC.md`. Step 4 failing means
the scope boundary was crossed; fix the diff, never the assertion.

**Done when:** all five are green and step 4 lists those four paths
and nothing else.

---

## What must NOT change

Audit before opening the pull request.

| Path or line | Why it must not move |
|---|---|
| `personas/**`, `personas/lifecycle.json` | D4. No new label, no new persona, no new stage-enum value; the `review` row already carries the brief this path needs. |
| `scripts/ops/claim.sh` | D9, and the claim protocol is out of scope entirely. |
| `.github/workflows/**` | D9. The fork guard at `unattended.yml:80-83` stays the authoritative owner of the fork rule. |
| `scripts/placement/**` | D9. `gh-actions/run.sh:98` passes its two arguments through unchanged and must keep doing so. |
| `scripts/ops/post.sh` | Its `branch_issue` call at `:124` is already `|| true` and gains only an unused variable. |
| `work.sh:547`, the `PROMPT=` line | AT-14. Byte-identical, and `work_test.sh:687-689` counts it. |
| `work.sh:430-433`, refusal (h) | D3. It passes by construction, not by exemption. |
| `docs/SPEC.md:451`, "Eight refusals" | Spec, Concerns. The count is preserved; one entry's text changes. |
| `work.sh:745`, the `branch:` line | Spec, Concerns. A printed derivation, left alone on purpose. |
| `work_test.sh:746-750`, the safety guard | AT-12 is that guard. The new block goes above it, not through it. |

---

## Branch, commit, pull request

- **Branch:** `odyssey/207-review-mutex`. The convention is
  `<actor>/<n>-<slug>` in one place, `scripts/ops/claim.sh`, and the
  implement-stage actor is odyssey.
- **Commits:** one for the tests (T1), one for the behavior (T2–T5),
  one for the living spec (T6). Three is a convenience; one is
  acceptable.
- **Closing keyword: none.** The body carries `Refs #207` and must not
  carry `Closes #207`. The implementing pull request of a five-rung
  issue is identified by its `<actor>/<n>-<slug>` head branch plus a
  file changed outside `intent/`, and its merge is what advances the
  issue; a closing keyword on it is the one thing
  `scripts/ci/lifecycle_advance.sh` calls out as forbidden.
- **`docs/SPEC.md` must be in the diff.** T6 satisfies this; the
  `Spec-impact: none` marker is not available.
- **Body** names the four changed files, the T7 table with each
  command's actual exit code, and the `stage:` line the suite observed
  for AT-8, quoted.

## Out of scope (carried from the spec)

- **#82** — repair-path pull requests and their missing reviews. AT-4
  is the row that keeps it out.
- **#191** — claim identity as a hard claim-time parameter.
- **#167** — runner model access for the reviewers.
- **#64 / #151** — consensus merge, verdict recording, the merge gate.
  Nothing here writes a verdict marker or records a review; this issue
  only makes the reviews exist.
- **#204's four ladder checks.** D5 states they are unaffected.
- Any change to the claim protocol or to AGENTS.md steps 5 and 6.

Open questions: none
