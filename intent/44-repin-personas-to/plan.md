# Plan: harness and model selection is configuration

**Issue:** #44 · **Spec:** spec.md (Approved, amendment r1, D1–D16,
Acceptance 1–14) · **Author:** daedalus (`evekhm-daedalus-app[bot]`)

## Amendment r1 (2026-09-04)

The presenter, this repository's human product owner, on 2026-09-03:

> the whole idea is to be able to re-pin and easily configure the harness
> and model selection! i do not want spec to hardcode or reference any
> choices!!!

`intent.md` and `spec.md` were amended accordingly and merged as **PR
#93**; every D-row is now a rule quantified over the configuration, and
the concrete pins are the operator's input, set directly in
`config/deployments.yaml` and `config/model_tiers.yaml`. This file — the
plan merged by PR #63 — was written against the struck rows: it named
three personas about seventy-seven times, wrote two pins into T1 as YAML
to paste, listed six target paths by name in T2, quoted four model IDs
as expected values, and gave T4 an after-table naming the two arms it
would produce. **All of it is rewritten here.**

What survives is the shape: one commit for the pin edit and the rebuild,
a resolution rather than an assertion for the reviewer constraint, a
launch rather than an inspection for the tools block, a session list
rather than a calendar window for the cost baseline, and one pull
request. What changed, task by task, is in the **Amended r1** line each
task carries.

**Pinned input.** This plan reads the tree at `52f49db` (merge of PR
#93) on `main`. Every `file:line` below is that commit's. `#43` (PR #60)
and `#108` have both landed since PR #63 was written: `work.sh` and
`smoke_launch.sh` on `main` are post-#60, and `work.sh` has gained
`WORK_MAX_USD`, `WORK_PERMISSION_MODE`, `WORK_COST_FILE` and
`WORK_MODEL` (`scripts/ops/work.sh:78-88`, `:114-131`, `:575-591`,
`:950-972`). The implementer branches from `origin/main` at dispatch
time and records that SHA in the PR body; where a cited line has moved,
the surrounding function name is the anchor.

---

## The one thing this plan may not contain

No task below names a persona→harness pin or a persona→model binding as
an input. Where a task needs such a value it **computes** it, and the
computation is written out as a step whose output goes in the PR body.
A reviewer checking this plan against the spec should be able to grep it
for a persona name and find hits only in (a) the derivation recipes,
where the name is a variable, (b) `constraints.distinct_model_families`
read out of config, and (c) the note to Odyssey about a stale branch.

## The derived sets — T0 computes them, every later task consumes them

Every task is quantified over one of these. They are computed once, at
the head commit, and pasted into the PR body.

| set | definition | source |
|---|---|---|
| `BASE` | the PR's merge-base with `origin/main` | `git merge-base` |
| `MOVED` | `(persona, old harness, new harness)` for each persona whose `harness:` differs between `BASE` and `HEAD` | D1; `config/deployments.yaml:7-13` |
| `RETIERED` | `(harness, tier, old model, new model)` for each cell of `config/model_tiers.yaml` that differs between `BASE` and `HEAD` | D1; `config/model_tiers.yaml:11-27` |
| `HARNESSES` | each distinct value of `personas.*.harness`, in first-appearance order in the `personas:` block | D7 |
| `ARM(h)` | the first persona in `personas:` declaration order pinned to `h` whose `default_permissions` in `scripts/auth/app_manifests.yaml` grant **both** `issues: write` and `contents: write` | D7, D14 |
| `RELABEL(p)` | the `label` of the one rung in `personas/lifecycle.json` whose `stage` appears in `personas/<p>.yaml`'s `stage:` list | D7; `personas/lifecycle.json:22-68` |
| `HOUSEKEEPER` | the first persona in declaration order (any harness) whose App grants `issues: write` and `contents: write` | D7 |
| `IDENTITY(p)` | `personas/<p>.yaml`'s `identity:` value | `scripts/ops/work.sh:737-741` |
| `MODEL(p)` | `config/model_tiers.yaml`'s `harnesses.<p's harness>.<personas/<p>.yaml's tier:>` | D4 |
| `UNDISPATCHABLE` | each `p` in `MOVED` for which `RELABEL(p)` is empty — its stages are all rungless (`personas/lifecycle.json:19-20`) | D8, D15 |

**Amended r1.** These sets did not exist. The old plan wrote their
values into the prose instead — the two moved personas, the six target
paths, the four model IDs, the two arm personas and their relabel
targets. Every one of those was a choice the operator now makes in
`config/`, so the plan holds the derivation and the PR body holds the
values.

## Order

    T0 (derive) ──┬─→ T1 ─┬─(one commit)─→ T3
                  │       └─ T2 ──────────┬─→ T6
                  └─→ T4 ─→ T5 ───────────┼─→ T7 ─→ T9
                       T8a (any time) ────┘
                       T8b (after T5/T6)

T0 is read-only and comes first; nothing below can be scoped without it.
T1 (the reviewer comment) and T2 (the rebuild) are **one commit** (D5).
T3 is a resolution over the committed tree and needs T1. T4 edits the
launch gate whose arms the pins decide, so it follows T1+T2; T5 is T4's
acceptance run. T6 exists only if `UNDISPATCHABLE` is non-empty. T7
describes what T4 built. T8's *before* half reads transcripts that
already exist. T9 is the assembly pass.

## Probes

Five, each cheap, each gating a task, each with the branch to take on
either outcome. Raw output goes in the run folder
`runs/<YYYY-MM-DD>_44-repin-cost/` (D10's folder; one for the issue) and
is cited in the PR body.

**Amended r1.** P1/P3 were two probes asking whether two named personas
loaded on a named harness at a named model; they are now one probe
quantified over the arms and over `MOVED`. P5 asked what shape
`smoke_launch.sh` was in after #60's in-flight review fixes; #60 has
merged, so it is replaced by P0, which asks whether the arm-selection
rule has a persona to select at all.

| # | gates | question | (a) | (b) |
|---|---|---|---|---|
| P0 | T1, T4 | for every `h` in `HARNESSES` at the operator's pins, is `ARM(h)` non-empty? | proceed | empty for some `h` → **stop before editing anything**: D14's exit-1 condition is already true of the operator's pins. Report the harness and the missing permission on #44 and hand the pin choice back (D3's failure branch, same shape) |
| P1 | T5, T6 | did the harness load the persona, or silently fall back to its stock agent? | `status` is `SUCCESS`, launcher-reported input tokens in the *loaded* range, no `Agent "<p>" not found` in `~/.gemini/antigravity-cli/cli.log` | error status with zero tokens → an unrecognised `tools:` name (`config/tools.yaml`'s inline record, agy 1.1.25): name the token on #44 and **stop**, the fix is a `config/tools.yaml` line the spec lists as not touched. `not found` in the log, or a stock-shaped answer at stock token volume → compiler fault, report on #44 |
| P2 | T5, T6, T8c | what is the launcher's usage field for input tokens? | use it consistently for Acceptance 7 and 9 | absent on this build → the token half of Acceptance 7/9 is unmeasurable; the observable degrades to the log check plus a persona-shaped answer, and the PR body says so plainly. Never substitute a turn count |
| P3 | T3 | does every model ID in the D3 resolution classify into a vendor family? | proceed | an ID the classifier cannot place → **OQ-1**: stop, name the ID on #44, do not guess a family |
| P4 | T8 | how many attributable baseline sessions exist per persona in `MOVED`? | ≥3 → newest three by transcript id | 1–2 → take them, state the count and the word *provisional* (D13). 0 → the before column is "no dispatch recorded as its own session"; report the after column alone and state **no saving**. `p` in `UNDISPATCHABLE` → "no sessions yet", naming the tracker issue that would give it a trigger |

## Contract tests

As in #36's and #43's plans, each task states its own checks and the
implementer runs or writes them with the change; no contract-writer
sub-agent was dispatched, because eight of the ten tasks are proved by a
live launch or by a deterministic script that already exists. The one
new committed assertion is T6's `work_test.sh` scenario (R3).

## The file set

The tasks below touch exactly `config/deployments.yaml` (the comment;
the pins are the operator's, T0), the compiled targets the rebuild
accounts for, `scripts/ops/smoke_launch.sh`, `docs/SPEC.md`, and — by
one recorded reading (R3) — `scripts/ops/tests/work_test.sh`.
`personas/**`, `config/tools.yaml`, `personas/lifecycle.json`,
`scripts/ops/work.sh`, `scripts/sync_agents.py`, `config/execution.yaml`,
`CLAUDE.md` and `scripts/auth/app_manifests.yaml` are **not** edited; T9
asserts it. `config/model_tiers.yaml` is the operator's too and is
touched only if they re-bind a tier.

---

## T0 · derive the sets — no file changes — D1

The pin edit itself is **the operator's**, not this PR's task. It goes
in `config/deployments.yaml`'s `personas:` block
(`config/deployments.yaml:7-13`, one `harness:` value per persona) and,
if they also re-bind a tier, in `config/model_tiers.yaml`'s per-harness
columns (`config/model_tiers.yaml:11-27`). Odyssey applies whatever is
there at its head commit and proves the properties against it; it
proposes no pin and defends none (spec, *Out of scope*, first item).

**Step 0a — establish `BASE` and dump both sides of the pins.**

```bash
BASE=$(git merge-base origin/main HEAD)
git show "$BASE:config/deployments.yaml" > /tmp/44-pins-base.yaml
git show "$BASE:config/model_tiers.yaml" > /tmp/44-tiers-base.yaml
```

**Step 0b — `MOVED`.** One parse, the same shape `work.sh`'s
`harness_of` uses (`scripts/ops/work.sh:441-455`), so the plan does not
introduce a second reading of the file:

```bash
pins() {  # <file> -> "<persona> <harness>", declaration order
  awk '$1=="personas:"{i=1;next} /^[^[:space:]#]/{i=0} !i{next}
       {n=$1; sub(/:$/,"",n);
        for(k=2;k<=NF;k++) if($k=="harness:"){v=$(k+1);gsub(/[,}]/,"",v);print n,v}}' "$1"
}
pins /tmp/44-pins-base.yaml       | sort > /tmp/44-pins.base
pins config/deployments.yaml      | sort > /tmp/44-pins.head
join /tmp/44-pins.base /tmp/44-pins.head | awk '$2 != $3'   # MOVED: name old new
```

**Step 0c — `RETIERED`.** `diff /tmp/44-tiers-base.yaml
config/model_tiers.yaml`, read as `(harness, tier, old, new)` rows.

**Step 0d — `HARNESSES`.** `pins config/deployments.yaml | awk
'!seen[$2]++{print $2}'` — first-appearance order, which is also the
order T4's arms run in (R2).

**Step 0e — `ARM(h)` and `HOUSEKEEPER`.** Read
`scripts/auth/app_manifests.yaml`'s per-persona `default_permissions:`
block (`scripts/auth/app_manifests.yaml:33-37, 45-49, 58-61, 70-74,
82-86, 94-98`; its header at `:16-24` records that `issues: write` is
mandatory for every persona since #47, and that `contents` still varies
— reviewers are comment-only and never push). For each `h`, walk the
personas in declaration order and take the first whose entry grants both
`issues: write` and `contents: write`. `HOUSEKEEPER` is the same walk
with the harness filter dropped.

**Step 0f — `RELABEL(p)` and `UNDISPATCHABLE`.**

```bash
jq -r --arg s "$stage" '.stages[]|select(.stage==$s)|.label' personas/lifecycle.json
```

for each `stage` in `personas/<p>.yaml`'s `stage:` list. A persona all of
whose stages return nothing is in `UNDISPATCHABLE` — `intake`, `deploy`
and `maintain` are "stage-enum values with no rung and are absent by
construction" (`personas/lifecycle.json:19-20`).

**If `MOVED` is empty.** This is a real outcome, not an error, and the
spec answers it without a new decision. `MOVED` empty means D4, D5(the
target half), D6, D8, D10, D13, D15 and D16 quantify over an empty set
and are **vacuously satisfied**; the implementing PR still owes,
unconditionally: D2's comment (T1), D3's resolution — which D3 requires
"even when its inputs are byte-identical before and after, because 'the
inputs did not change' is a claim about the diff, and the diff is what
acceptance reads" (T3), D7/D14's derived arms and their live run (T4,
T5), D9(b)'s `ops.dispatch` upsert (T7), D11's per-harness sub-agent
targets (T2's check, T9), and D12's one PR (T9). Acceptance 1's "the PR
body lists the moved personas" is satisfied by listing **none**,
explicitly and in those words; Acceptance 11's cost comment says "no
persona moved, so there is no before/after to take" rather than
producing a table. Odyssey does **not** invent a pin to make the diff
non-empty, and does not ask the operator to.

**Proves it.** The four dumps above, pasted into the PR body as the
"derived at `<head>`" block: `MOVED`, `RETIERED`, `HARNESSES` with
`ARM(h)` and `RELABEL(ARM(h))` per harness, `HOUSEKEEPER`,
`UNDISPATCHABLE`.

**Amended r1.** New task. The old plan had no derivation step because
its T1 opened with two `harness: antigravity` lines to paste.

## T1 · `config/deployments.yaml` — the reviewer comment — D1, D2

The pins are already in the file when this task starts (T0). What this
PR adds is **one comment immediately above `constraints:`**, i.e.
inserted before `config/deployments.yaml:15`, distinct from the comment
*inside* that block at `:16-19` (which says what the constraint is; this
one says why the pins under it may not move independently).

The comment records, for the pins at the head commit and in this order:

1. one line per name in `constraints.distinct_model_families`
   (`config/deployments.yaml:20`) giving the `(name, harness, model,
   family)` row T3 resolves;
2. the rule that repinning one of those names without repinning the
   other in the same edit is a violation of the constraint below (#2
   D4), which until #6's check lands produces **no error**.

Its values are produced by T3 and must equal T3's output at the same
commit — write the comment *after* running T3's resolution, even though
the comment ships in T1's commit.

Vendor-family words are allowed here and only here: the sanitize gate's
`vendor` rule is scoped by the `personas/*)` case arm at
`scripts/ci/sanitize_check.sh:148-152`, and `config/` is by #2 D2 the
layer where vendor strings live.

**Proves it (Acceptance 1, 2).**

```bash
git diff "$BASE" -- config/deployments.yaml   # only harness: values + comments
git diff "$BASE" -- personas/                 # empty
bash scripts/ci/sanitize_check.sh             # exit 0
git diff "$BASE" -- scripts/ci/sanitize_allowlist.txt   # empty
```

plus: the comment exists immediately above `constraints:`, and its rows
are byte-equal to T3's output.

**Do not commit T1 alone** — see T2.

**Amended r1.** The old T1 *was* the pin edit: two YAML lines to paste,
an assertion that the other four personas stayed byte-identical, and a
six-line proposed comment naming one persona as "the LAST persona pinned
to a non-Gemini family" and another as the one to move instead. The pin
edit moved to the operator (T0); the comment's *content* is now
generated by T3 from whatever `constraints.distinct_model_families`
lists.

## T2 · the rebuild — the compiled targets — D4, D5, D11

`python3 scripts/sync_agents.py`, never a hand-edit, committed **with
T1**. For each `p` in `MOVED`, exactly two things happen to the compiled
tree: the target `p`'s old harness emitted disappears and the target its
new harness emits appears, in the layout `personas.compiler` gives each
(`.claude/agents/<p>.md` for Claude Code — `ClaudeEmitter`,
`scripts/sync_agents.py:583-606`; `.agents/agents/<p>/{agent.md,agent.json}`
for Antigravity — `AntigravityEmitter`, `:607-668`).

The deletions are the compiler's, not a `git rm`: the removed files
carry the generated marker, so `write()`'s stale set prunes them
(`scripts/sync_agents.py:754-775`, stale computed at `:756` against
`existing_generated`, `:735-752`) once `Resolver.harness_for`
(`:296-313`) stops returning the old harness for that name.

**No sub-agent target changes.** `harness_for` returns *every* harness
for a `kind: subagent` source (`:299-300`, over `harnesses()` at
`:278-279`), so a persona pin adds and removes no sub-agent file (D5, #2
D3). If `RETIERED` is non-empty the sub-agent targets *do* change — their
`model` lines only, for the re-bound cells — and that is D11 working, not
a violation; see OQ-2.

**Proves it (Acceptance 4, 5, 12).** All of these, pasted:

```bash
python3 scripts/sync_agents.py --check       # exit 0  (check(), :778-799)
python3 scripts/sync_agents.py --verify      # exit 0  (verify(), :820+)
bash    scripts/ci/compiler_roundtrip.sh     # exit 0
git show --stat <pin-commit>
git diff "$BASE" -- CLAUDE.md                # empty (D11)
grep -rlE '^model:' .agents/agents/*/agent.md   # no output, tree-wide (D4)
```

and, **per `p` in `MOVED`**, one row: the model its new target carries —
`jq -r .model .agents/agents/<p>/agent.json` for an Antigravity target,
the frontmatter `model:` for a Claude Code one — equals `MODEL(p)`, the
value `Resolver.model` would return (`scripts/sync_agents.py:281-294`)
for `personas/<p>.yaml`'s `tier:` on `p`'s new harness.

and, for D11: after the rebuild, **every** `kind: subagent` source has a
target under every harness, each carrying that harness's own tier
resolution. Enumerate the sources rather than listing them here:
`grep -l 'kind: subagent' personas/*.yaml`.

`git show --stat` must list `config/deployments.yaml`, plus
`config/model_tiers.yaml` if `RETIERED` is non-empty, plus exactly the
target paths those two edits account for, and nothing else. A sub-agent
target in the `--stat` with an empty `RETIERED` is a **stop**: either a
persona source changed (it must not have) or `harness_for` does not
behave as recorded here, and both are findings for #44 rather than
things to commit.

Same commit as T1, not a follow-up: a tree where `deployments.yaml`
names one harness and the other harness's target still exists fails
`--check` and makes `work.sh` preflight a target that is not there (#43
D3, exit 1) — a state no bisect, no CI run and no cherry-pick should be
able to land on (D5).

**Mechanic-tier task.** Fully specified, no decision: run the compiler,
run the three gates, run the per-`MOVED` and per-sub-agent assertions,
report verbatim.

**Amended r1.** The old T2 listed six target paths by name as an
`added`/`deleted` block, asserted "seven paths, exactly" in the
`--stat`, and quoted two expected model IDs and two unchanged ones as
literal `jq` expectations. All four values are functions of the pins and
of `model_tiers.yaml`; the counts are functions of how many personas
moved and in which direction.

## T3 · the #2 D4 resolution, performed and recorded — D3

No file changes. The check is a **resolution**, and D3 requires it be run
even when both inputs are byte-identical before and after.

The procedure, for each name in `constraints.distinct_model_families`
(`config/deployments.yaml:20` — read the list, never hard-code it):

1. read `personas.<name>.harness` from `config/deployments.yaml`;
2. read `harnesses.<that harness>.REVIEW` from
   `config/model_tiers.yaml` (`:11-27`) — **`REVIEW` and only
   `REVIEW`**: a persona's `escalation_tier` never enters the check,
   because the list contains personas and an escalation tier is not one;
3. classify the resulting model ID into a vendor family (see P3/OQ-1);
4. the constraint holds when the families are pairwise distinct across
   the whole list.

The recorded output is one `(name, harness, model, family)` row per name
plus the verdict, and it is what T1's comment carries. **It is not
committed as a script**: automating the check is #6's, the spec's file
set contains no CI script, and adding a permanent gate here would be
building #6 inside #44 (spec, *Out of scope*, second item).

**On failure**, the implementing PR does **not** proceed: it reports the
violating pair — both rows, both families — on #44 and hands the pin
choice back to the operator (D3). It does not repin anything to make the
check pass.

**Proves it (Acceptance 3).** The rows and the verdict, pasted into the
PR body, the run folder and the #44 comment; each model ID equal to the
value at the cited path in `config/model_tiers.yaml` at that commit; the
families pairwise distinct.

**Mechanic-tier task** once P3 has answered: run it, paste it.

**Amended r1.** The old T3 shipped a 30-line bash snippet with a
`family_of()` `case` statement enumerating vendor prefixes, and printed
an *expected output* block naming two personas, two harnesses, two model
IDs and two families — the exact resolution the procedure exists to
compute. Struck; the procedure stays, the worked answer goes in the PR
body. The `case` statement's assumption is now OQ-1.

## T4 · `scripts/ops/smoke_launch.sh` — arms derived from config — D7, D14

One arm per `h` in `HARNESSES`, each running `ARM(h)`. **No persona name
appears as a literal anywhere in the script after this task.** Today
they appear in eleven places, and each is a separate edit:

| line(s) | what is hard-wired | becomes |
|---|---|---|
| `:19-23`, `:25-29` | header prose naming two personas as the comment/commit authors, and the whole `#47` paragraph | prose describing the derivation; the `#47` paragraph is deleted (D14) |
| `:46` | `SMOKE_BRANCH="smoke/$ISSUE-daedalus"` | one branch per arm, `smoke/$ISSUE-<ARM(h)>` |
| `:52` | `tolerate()` prints `BLOCKED ON #47` | deleted; the verdict line's tolerated count (`:295`) stays and now prints 0 (D14) |
| `:107-143` | the errand body's `If you are **<p>**` branches, the worktree recipe's branch name, and the `-c user.name=` bot login at `:132-133` | one branch per arm, keyed on the arm's persona; the login is `IDENTITY(p)` (`scripts/ops/work.sh:737-741`), never a literal |
| `:146` | `gh_as odyssey issue edit` — the body write | `gh_as "$HOUSEKEEPER"` |
| `:166-176` | `check_claim` | deleted with the `#47` probe (D14, R1) |
| `:182` | `count_comments` mints as `odyssey` | `HOUSEKEEPER` |
| `:193, :196` | `relabel` mints as `odyssey` | `HOUSEKEEPER` |
| `:225` | `check_pushed_artifact` reads as `odyssey` | `HOUSEKEEPER` |
| `:235-253` | run 1: banner, `check_token odyssey`, `relabel status:implementing`, `launch odyssey`, the literal `evekhm-odyssey-app[bot]` at `:248`, `check_claim odyssey` | the loop body below |
| `:255-291` | run 2: banner, `check_token daedalus`, `relabel status:build`, the branch delete at `:262`, `launch daedalus`, the literal at `:283`, `check_claim daedalus` | the same loop body |

**The shape after the change.** One loop over `HARNESSES`, index `N`
from 1, and per iteration:

```
banner "run $N · $h · $p · #$ISSUE"
check_token   "$p"
relabel       "$(RELABEL "$p")"
launch        "$p"                        # work.sh, exit 0 required
observable 1: runs/smoke-$ISSUE/$p.md is non-empty
observable 2: the newest comment on #ISSUE is authored by IDENTITY($p)
observable 3: smoke/$ISSUE-$p exists on origin, its head commit is
              authored by IDENTITY($p), and carries SMOKE-$ISSUE.md
```

Three observables per arm, uniform across arms — which is what makes
`ARM(h)`'s permission test (`issues: write` for 2, `contents: write` for
3) the right test, and what `ops.dispatch`'s existing "three named
observables each" already says. See **R1** for why the arms are no
longer asymmetric and what it costs to overrule.

**Five ways this goes wrong.**

1. **The relabel target must be derived, not carried over.** `work.sh`
   refuses at refusal (f) — `"$AS does not own stage $stage (owners:
   …)"`, `scripts/ops/work.sh:390` — if the label's stage is not one the
   arm's persona owns. `RELABEL(p)` is the join of
   `personas/<p>.yaml`'s `stage:` list with
   `personas/lifecycle.json:22-68`. A persona owning a stage with
   several owners (`review`, `:60-61`) is fine: `--as` narrows it
   (`work_test.sh:556-558`).
2. **`ARM(h)` may be empty** and that is D14's exit 1: name the harness
   and the missing permission, launch nothing, do not skip the arm and
   do not exit 0 having covered another harness twice. P0 asks this
   before any edit.
3. **A persona in `UNDISPATCHABLE` can never be `ARM(h)`** — it has no
   `RELABEL`, so `relabel` has nothing to write. The selection rule must
   skip it and move to the next persona in declaration order; a harness
   whose only qualifying personas are undispatchable is the same exit 1
   as (2), naming the harness and "no persona with a dispatchable rung".
4. **The errand body is written by this script** (`:107-148`) and must
   stay that way: `work.sh` has exactly one prompt literal for both
   harnesses (`scripts/ops/work.sh:505`), so a smoke test needing a
   second one would test something `work.sh` does not do. Rewrite the
   body so its instruction is keyed on the reader's own persona rather
   than on an `If you are **<name>**` branch per literal; the errand text
   already names "your persona, your harness and the UTC time" and stays
   that way (D7).
5. **The trailing-argument override** (D7): an operator may name
   personas as trailing arguments, each binding to the harness *its own
   pin* names. A name that is not a persona, or two names resolving to
   the same harness, is exit 1. So is a named persona whose App lacks an
   observable's permission, or one in `UNDISPATCHABLE` — the override
   picks a different arm, it does not switch the selection rule off
   (D14).

**Proves it (Acceptance 6, 8).**

```bash
bash -n scripts/ops/smoke_launch.sh
grep -n 'BLOCKED ON #47' scripts/ops/smoke_launch.sh          # no output
grep -nwF -f <(pins config/deployments.yaml | awk '{print $1}') \
    scripts/ops/smoke_launch.sh                               # no output
```

plus the pin-flip test, which is Acceptance 6's second half and D7's
whole point: copy `config/deployments.yaml` to a scratch path, flip one
pin, point the script at the copy, and confirm the banners change with
**no edit to the script**. And D14's negative: with a scratch
`app_manifests.yaml` in which no persona pinned to some harness grants
`contents: write`, the script exits 1 naming that harness and that
permission and launches nothing.

Both scratch-file tests need the script to read its two config files
through overridable paths. Add environment overrides (defaulting to the
repo's own copies) rather than a flag — argv stays closed, as in
`work.sh` (`scripts/ops/work.sh:74`, `:85-88`). This is the only new
input surface the task adds.

**Deviation 2026-09-04 (odyssey, implementing).** The task adds a
**third** environment variable, `DRY_RUN`, alongside
`SMOKE_DEPLOYMENTS` and `SMOKE_APP_MANIFESTS`. Grounds: the two
overrides alone do not make the pin-flip test runnable. Pointing the
script at a scratch `deployments.yaml` and letting it proceed spends
one live launch per harness *per assertion about the banners* — and
launches personas against a real scratch issue with the pins deliberately
wrong, which is the one thing the arms are supposed to prevent. `DRY_RUN=1`
resolves and prints the arms and exits before the first mint, write or
launch, exactly as `scripts/ops/work.sh:74` does with the same variable
name, so the new surface is a spelling this repository already has
rather than a concept. The D14 negative needs no such help — selection
precedes every write by construction — but it is run under `DRY_RUN=1`
too, so the whole T4 proof set is one non-mutating command per case.
Argv stays closed: the trailing-argument override remains the only
thing `smoke_launch.sh` reads from argv besides the issue number.

**Deviation 2026-09-04 (odyssey, implementing) — two further behaviours
this plan did not describe.** Both are in the shipped diff and neither
is in T4's site table or its notes, so they are recorded here rather
than left for a later reader to find by diffing the code against the
plan.

1. **A fourth selection clause: the branch surface.** T4 names three
   inputs to the arm rule — the pin, the App permission, the labelled
   rung. The implementation adds a fourth: the persona's own
   `authority.github_write` must declare a branch surface, and the arm's
   push branch is derived from that glob rather than from a name of the
   gate's invention. Grounds: the live run proved an App grant is not
   sufficient. The old branch, `smoke/<issue>-<persona>`, is outside
   every persona's declared glob, so an arm that read its contract and
   refused to push was recorded as a persona that did not load — the
   exact misattribution D14's *"the arm selection rejects such a persona
   up front"* exists to prevent. D14 is the authority for adding a
   selection input; whether the Approved D7's enumeration ("a rule over
   config facts only") should name a `personas/**` fact is a spec
   question raised on #44 for the product owner, not settled here.
2. **`clear_claim`.** New; the base script had no such function. It
   removes `in-progress` between arms and verifies the removal. Grounds:
   the errand tells every arm that claiming is not part of it, but an
   arm that claims anyway — or dies between the claim and the handoff —
   leaves the mutex set, and `work.sh` then refuses the NEXT arm on a
   claim this very run produced (refusal (e), exit 2), reporting one
   arm's accident as another harness's failure.

**Deviation 2026-09-04 (odyssey, review round 2).** Answering the round-1
findings changed five more things in the same file, plus one new file.
None changes what the gate proves; each removes a way it could prove it
wrongly.

1. **One reader for `config/deployments.yaml`** (Atlas AT-2, AT-3). The
   first `pins()` read `harness:` only on the persona key's own line, so
   a block-form pin — valid YAML that `sync_agents.py` and
   `work.sh harness_of` both accept — vanished and the gate ran one arm
   while printing "every pinned harness launched". It now reads both
   forms, treats no comment line as a pin, keys on indentation, and a
   persona key whose harness it cannot read is exit 1 naming that
   persona instead of a shorter arm list.
2. **The branch glob must be `<prefix>*`** (Argus R1-1, Atlas AT-5).
   Stripping a *trailing* `*` only meant `branch:release` asked an arm
   to push `releasesmoke-<issue>`, outside its declared surface. The
   shape is now its own named disqualification reason, which is also
   what makes the gate's derivation and the errand's wording one rule.
3. **A scratch-issue guard** (Argus R1-4). The three destructive writes
   — body overwrite, `in-progress` deletion, `status:*` rewrite — all
   landed before any launch, for any run of digits. The gate now refuses
   any issue that is neither marked by a previous run of itself nor
   fresh and unlabelled, before writing.
4. **No repo-wide `git worktree prune`** (Argus R1-5), and the pre-run
   ref reset covers every pinned persona's `<persona>/smoke-<issue>`
   rather than only the current arms' (Argus R1-9).
5. **`relabel()` derives its label list from `lifecycle.json`** (Atlas
   AT-7), and each verified push ref is re-read after the run: a ref
   that moved is a failure, because evidence a session the gate did not
   launch has overwritten is not evidence (Atlas AT-1's in-file half;
   the launcher-side re-entrancy refusal is a `work.sh` change, out of
   this plan's file set and tracked on **#134**).
6. **New file: `scripts/ops/tests/smoke_launch_test.sh`.** T4's proof
   set was a list of commands run by hand. Each round-1 finding above
   has a hermetic scenario there instead — no network, no mint, no
   launch — so the next reader re-runs the proof rather than trusting
   this note.

**Deviation 2026-09-04 (odyssey, review round 3).** Round 2 left one
blocking defect and three normal ones in the same file. Four changes,
all inside T4's own file set (`scripts/ops/smoke_launch.sh`, its test
file, `docs/SPEC.md`); no new file and no new input surface.

1. **The scratch guard's acceptance rule is now ONE explicit opt-in**
   (Argus **R2-2**, Atlas **AT-R2-5**, both high; this closes R1-4's
   third shape). The round-2 guard accepted an issue that carried *no
   labels*, and two things were measured through that: `gh api
   /repos/{o}/{r}/issues/{n}` also serves **pull requests**, every pull
   request in this repository carries zero labels, and `gh issue edit`
   resolves a pull-request number without a warning — so
   `smoke_launch.sh <a PR number>` passed the guard and the first write
   replaced that pull request's body, stripped `in-progress`, rewrote
   the stage label and launched two live personas at it; and any
   freshly filed, untriaged issue is zero-label by definition and is
   somebody's unit of work from the moment it is opened. Both are
   closed by two conditions. **(a)** A response carrying
   `.pull_request` is refused **first**, before the marker is looked
   at — first because a pull request's body is precisely where the
   marker gets quoted (a ledger row, a finding, a paragraph about this
   guard). **(b)** The *"no labels"* acceptance is gone; the only fact
   that earns the writes is the errand's own marker, `SMOKE TEST — not
   a unit of work.`, already in the body. That is not a new contract —
   it is the contract a second run against the same fixture already
   relied on, now the whole of the rule — and first use opts in by the
   operator typing the marker into the body of the issue they open:
   `gh issue create --title 'smoke fixture' --body 'SMOKE TEST — not a
   unit of work.'`, which the refusal message prints. **No bypass
   flag**, for the reason the script already gave about an off switch,
   plus one more: a marker in the body is a fact the tracker keeps and
   the next reader can audit, and a flag in a shell is not. Documented
   in the script header, at the guard, and in `docs/SPEC.md`'s
   `ops.dispatch`.
2. **`pins()` reads `harness:` only at the persona mapping's own
   indent** (Argus **R2-15**, Atlas **AT-R2-11**). It took the first
   `harness:` at any depth inside a persona's block, so a `harness:`
   nested under another key of that persona was read as the pin. Alone
   among the reader's divergences from `yaml.safe_load` this one failed
   **open** — an extra arm on a harness nobody pinned, silently, which
   is AT-2's class. A persona whose only `harness:` is nested now
   yields `-` and is exit 1 naming it. The header's parity claim is
   softened to the forms actually covered, and records the quoted-scalar
   divergence explicitly: `work.sh harness_of` does not unquote either,
   so the two shell readers agree and the case is exit 1 — unquoting
   here alone would derive an arm the launcher then could not resolve.
3. **`clear_smoke_refs` no longer swallows a refused delete** (Argus
   **R2-14**). A delete that fails for any reason other than "no such
   ref" is now a `note`, so the litter R1-9 named cannot persist in
   silence. The cross-namespace half is answered rather than changed,
   and the reason is recorded at the function: the housekeeper is the
   script's own hands, not a persona doing persona work, and it already
   writes the body, strips labels and deletes each arm's own ref; a
   `branch:` glob bounds what the agent it belongs to may push while
   working an issue, not who may reset a fixture ref. It stays a `note`
   and not a failure because leftover fixture refs are housekeeping,
   not an observable.
4. **`recheck_verified_refs` distinguishes a failed read from a deleted
   ref** (Atlas **AT-R2-12**). `--jq '.object.sha' || true` yielded the
   empty string on a transient 5xx, a rate limit or an expired token
   exactly as it did on a deleted ref, and the row then printed
   `-> deleted` and failed the run. The read is retried up to three
   times and, if it still fails, reported as a **failed read** —
   evidence unverified, not known stale. Still a failure, because a
   re-read that did not happen is not a re-read that passed.

Not changed, and why. **AT-4** needed no code change: Athena's
amendment r2 (PR **#135**) rules D7's second reading normative and says
so in as many words — *"the code on PR #133 head `ab53c5b` stands;
Odyssey owes no code change on this row"* — and appends Acceptance 15
for D7's clauses (ii) and (iii), which the `SMOKE_PERSONA_DIR`
scenarios in `smoke_launch_test.sh` already exercise. **R2-1 /
AT-R2-1's residual** — the re-read is a detector, not a bound, and a
force-push landing *after* the gate exits is still invisible — is
`scripts/ops/work.sh`'s launcher-side refusal, on both this plan's and
the spec's do-not-edit list, and remains **#134**.

**Amended r1.** The old T4 was an arm *swap*: a before/after table
naming two personas, two relabel labels, two artifact paths and two bot
logins, five numbered notes about the swap, and an instruction to keep
the `BLOCKED ON #47` tolerate behaviour with only its argument changed
to a third persona name. The swap is gone, the `#47` probe is retired
(D14), and the five notes are re-aimed at the derivation.

## T5 · the smoke run — the `tools:` block proved by launching — D6, D7

`scripts/ops/smoke_launch.sh <scratch-issue>` against a live scratch
issue. This is the only acceptance D6 accepts: an unrecognised name in a
compiled `tools:` block is a **hard** error on Antigravity — exit 1,
error status, zero tokens, no session at all — recorded inline in
`config/tools.yaml` from #43's smoke run (agy 1.1.25), where "every
antigravity persona carrying `delegate` was unlaunchable" until one line
changed. Reading the file proves nothing.

Run P2 on the first launch (record the usage field name into the run
folder and use it consistently), then P1 on every arm.

**Proves it (Acceptance 6, 7, 8).** One run, exit 0, output pasted: one
`run N · <harness> · <persona>` banner per harness in
`config/deployments.yaml`, each persona the one `ARM(h)` yields; per arm
the `work.sh` exit code and the three observables with their authors;
P1's signals per arm; and the verdict line reporting **0** tolerated
observables. Identity is never checked with `gh api user` — an App token
gets 403 there (findings Q7); the token-side check is
`GET /installation/repositories`, which `check_token`
(`scripts/ops/smoke_launch.sh:155-162`) already does.

**Amended r1.** The old T5 named the two arms' personas and their bot
logins, listed each one's expected resolved tool list from
`config/tools.yaml`, and required "exactly one `BLOCKED ON #47` line".
All struck; the run is now quantified over the derived arms and the
`#47` line must be absent.

## T6 · `UNDISPATCHABLE` — one positive check, one negative assertion — D8, D15

Runs once per `p` in `UNDISPATCHABLE`. If the set is empty, the task is
skipped and the PR body says so in one line.

Such a persona is repinned but **not dispatchable**, and the reason is
structural rather than a gap in this issue: all its stages are rungless
(`personas/lifecycle.json:19-20`), no `status:*` label resolves to them,
and `work.sh` validates `--as` against the owners of the stage the
labels say is current (`scripts/ops/work.sh:390`) — so it refuses on
every issue in the repository, before the repin and after it. Both
halves are asserted, because a future session must be able to tell
"never proven" from "proven not to apply" (D15).

**Positive — the line `work.sh` would build, run by hand.** Do not
retype it and do not copy any value out of config: `DRY_RUN=1
scripts/ops/work.sh <any issue> --as <p>` prints the resolved command
(`scripts/ops/work.sh:744-748`) — except that the same refusal being
asserted below fires first, so take the argv from `launch_argv`'s row
for `p`'s new harness (`scripts/ops/work.sh:551-615`), with
`timeout_mins_of` (`:468-478`) and, for Antigravity, `model_of` reading
the committed sidecar (`:484-493`). Run it by hand and apply P1: success
status, non-zero input tokens (P2's field), and an answer that shows the
persona loaded rather than the harness's stock agent — compare against
the distinctive part of `personas/<p>.yaml`'s own role text, which the
stock agent has no way to produce.

**Negative — the refusal is asserted, and asserts its own cause.** One
new scenario in `scripts/ops/tests/work_test.sh`, using the existing
harness (`run()` at `:263-276`, `issue()` at `:217-223`, `has`/`hasnt`
at `:303-312`), modelled on the D5(f) scenario already there at
`:559-560`:

- `--as <p>` against a stubbed issue carrying any single `status:*`
  label exits **2**;
- the message matches `"<p> does not own stage <stage>"` and names that
  stage's real owners (`scripts/ops/work.sh:390`);
- the message contains **neither** harness name nor the word `harness` —
  proving the refusal comes from the stage machinery and not from the
  repin (D15);
- `$WRITES`, `$LAUNCHES` and `$MINTS` are all empty
  (`work_test.sh:41-48`) — the refusal precedes every mint.

Repeat the exit-2 assertion for a second `status:*` label so the
scenario shows the refusal is not specific to one rung. No
`fixture_tree` is needed: the refusal happens before any launch.

**Proves it (Acceptance 9).** The hand-run JSON (argv shown in full,
prompt elided if long) plus `bash scripts/ops/tests/work_test.sh` exit 0
with the new scenario named in its output.

**Note the PR body and the #44 handoff both owe (D8).** For each `p` in
`UNDISPATCHABLE`, in so many words: repinned but not dispatchable, and
the tracker issue that would change it — **#11** for a cadence, **#25**
for a `config/execution.yaml` entry. A handoff that leaves this out is
the failure D8 describes.

**Amended r1.** The old T6 was written about one named persona
throughout, quoted her stage, her timeout and her resolved model ID as
literals in a hand-typed `agy` command line, and identified her role
text's distinctive feature by name. The task is now quantified over
`UNDISPATCHABLE`, which may be empty.

## T7 · `docs/SPEC.md` — the `ops.dispatch` upsert — D9(b)

One entry, `ops.dispatch`, one sentence — the `Tests:` sentence at
`docs/SPEC.md:597-601`, which currently reads:

> Tests: `scripts/ops/tests/work_test.sh` against stubs, and
> `scripts/ops/smoke_launch.sh <scratch-issue>` for one real launch per
> harness — three named observables each, with the claim half of the
> Antigravity run reported as `BLOCKED ON #47` until that App's
> `issues: write` permission is granted, rather than asserted to fail.

It is falsified twice by T4: the arms are derived rather than fixed, and
the `#47` clause is retired (D9, D14). Replace it with a sentence saying:
one real launch per harness **present in `config/deployments.yaml`**,
the persona for each **selected by a rule over config facts** — first in
declaration order pinned to that harness whose App grants the
observables' permissions — three named observables each, and a harness
with no qualifying persona failing the run rather than being skipped.
**Name no persona and no harness-to-persona assignment**: that would be
the same hardcoding one layer down (D9's own grounds for amending).

Keep the entry ID and the sentence's position; upsert, never append
(AGENTS.md, "The living spec").

**Nothing else in `docs/SPEC.md` moves.** `config.bindings`
(`:128-151`) already carries the re-pin property — added by the
amendment PR #93 at `:144-151`, which is Acceptance 14 and is **already
satisfied**; this PR must not touch it. The both-harnesses paragraph at
`:482-501` describes the launch table and is unaffected by a pin. Re-run
a grep for persona and harness names over `docs/SPEC.md` at the
implementing SHA and confirm the repin adds no new statement about who
runs where.

`Spec-impact: none` is **not available** to this PR: `config/` and
`scripts/` are behavior-bearing under `scripts/ci/spec_check.sh:80-91`
(the `.github/workflows/*|scripts/*|personas/*|config/*` arm at `:85`)
and the behaviour genuinely changes (D9).

**Proves it (Acceptance 10).** `bash scripts/ci/spec_check.sh "$BASE"`
exits 0 *because the diff touches `docs/SPEC.md`* — confirm by checking
that the PR body carries no `Spec-impact:` line; `git diff "$BASE" --
docs/SPEC.md` is one entry, and does not touch `config.bindings`.

**Amended r1.** The old T7 wrote the replacement sentence out with two
persona names in it ("`athena` on Claude Code and `odyssey` on
Antigravity, following the pins") and kept a standalone `#47` claim
probe for a third. Both struck. It also asserted a four-hit grep result
at a specific SHA; that is re-run rather than quoted.

## T8 · the cost measurement, per moved persona — D10, D13

Runs once per `p` in `MOVED`; skipped with one line in the PR body if
`MOVED` is empty. **No single cross-vendor dollar figure is produced**,
and the report says why: `scripts/ops/session_spend.sh` reads Claude
Code `*.jsonl` transcripts and prices them against the Anthropic rate
table, reporting a model that table does not know as `UNPRICED` by name
with its tokens excluded from the USD columns
(`scripts/ops/session_spend.sh:11-20`). A "we saved $X" number spanning
both vendors would be an invention (D10).

**The baseline is a named set of sessions, not a calendar window**
(D13): per `p`, the last three sessions it ran on its **old** harness
before the merge, listed by transcript id, against the first three on
its **new** harness after. Fewer than three after → say how many and
call the number provisional. A comparison whose denominator is time
measures how busy the week was; this one measures what a session costs.
P4 answers the count.

**The direction is not assumed.** A repin can move work *onto* the
priceable harness as easily as off it, in which case the *before* side
is the one the tool cannot price (D10, as amended). Which side is which
is read from `MOVED`'s old/new columns, per persona.

**(a) the priceable side.** `scripts/ops/session_spend.sh
<transcript-dir> --check` over that side's session set, recording the
two numbers AGENTS.md requires **together** — cache hit rate
`read/(read+write+fresh)` and tokens-per-message
(`scripts/ops/session_spend.sh:26-29`) — plus the per-model USD
roll-up. Either number alone hides the other. The observable on the
after side is that the rows attributable to `p` on its old harness fall
to zero.

Transcripts live per working directory
(`~/.claude/projects/<mangled-checkout-path>/*.jsonl`), so a dispatch
that ran in a worktree has its own directory; enumerate accordingly.
Where a tier binds the same model to two roles on one harness, a
per-model row cannot separate `p` from a sub-agent it dispatches — which
is exactly why D13's unit is *a session dispatched for `p`*, inside
which those rows are `p` plus its own sub-agents. A per-model roll-up
taken across the repository instead would be meaningless, and taking one
is the mistake to avoid.

**(b) the side the tool cannot price.** The launcher's own reported
usage, recorded per run as **tokens**, with the vendor's bill named as
the authority for dollars. No USD column. For Antigravity that is the
`usage` object in `--output-format json` (findings Q5; P2 pins the field
name). Two runs of this issue already produce such envelopes — T5's arm
and T6's positive check — and `work.sh` now writes the run's own
observed cost and the model it billed to when `WORK_COST_FILE` is set
(`scripts/ops/work.sh:81-83`, `:950-968`), which is a better source than
scanning transcripts back and is worth using where the after-side runs
are dispatched through `work.sh`.

**Where it lands.** Run folder `runs/<YYYY-MM-DD>_44-repin-cost/` per
AGENTS.md — gitignored, so the numbers do not survive there. They are
reported in a **comment on #44** and summarised in the PR body, and the
run folder's `findings.md` carries the disposition footnote naming that
comment:

```text
---
Disposition (YYYY-MM-DD): reported in the cost comment on #44; summarised in PR #<n>.
```

**Proves it (Acceptance 11).** The #44 comment shows, per `p` in
`MOVED`, before and after with hit rate **and** tokens-per-message
**and** the per-model USD table for the priceable side, and tokens with
no USD column for the other; the baseline is named as a session list,
not a date range; the run folder carries the footnote.

**Amended r1.** The old T8 was one comparison in one direction, naming
two personas, the two model rows expected to fall to zero, and "the
antigravity side" as a fixed heading. It is now per moved persona and
symmetric in direction. The `WORK_COST_FILE` source did not exist when
it was written (#108).

## T9 · assembly — one PR and the negative assertions — D11, D12, D16

Not a code task; the pass that makes the PR honest.

**One pull request (D12).** The comment, the pins the operator set, the
rebuild, the smoke change and the `docs/SPEC.md` sentence ship together.
Splitting them opens a window in which `smoke_launch.sh` launches
against arms the pins no longer justify and **exits 0** — a green gate
reporting coverage of a harness it did not touch, while `docs/SPEC.md`
states behaviour the script no longer has (D12). "Config-only" survives
as a statement about the *source* layer: `personas/**` is untouched and
one line of one config file decides the harness.

**The negative assertions**, each a command whose empty output is the
evidence:

```bash
git diff "$BASE" -- CLAUDE.md                                    # empty (D11)
git diff "$BASE" -- personas/ config/tools.yaml \
    personas/lifecycle.json scripts/ops/work.sh \
    scripts/sync_agents.py scripts/auth/app_manifests.yaml \
    config/execution.yaml                                        # empty
grep -rn 'escalation_tier' scripts/                              # no hit (D16)
```

`config/model_tiers.yaml` is deliberately **not** in that list: it is the
operator's second lever and may legitimately have changed (`RETIERED`).

**D16, recorded not fixed.** For each `p` in `MOVED` that declares an
`escalation_tier` in `personas/**` **and** is now pinned to a harness
whose launcher takes one model fixed at launch, the compiled sentence
"You may escalate to the … grade only when …" has no mechanism: `agy`
takes one `--model` from the sidecar at launch
(`scripts/ops/work.sh:609-612`), print mode is the only mode #43 offers
for that harness (#43 D5), and #36 D7 forbids a flag naming a model — so
*escalate* there means stop and hand the question back on the issue,
which is what the persona's own role text already requires for open
design questions. Enumerate the affected personas from the diff (`grep
-l escalation_tier personas/*.yaml` joined with `MOVED`) and cite this
row for each in the #44 handoff. Add no `escalation_tier` handling to
`work.sh` or `scripts/sync_agents.py`: fixing it means either a
model-bearing flag (forbidden) or a second tier column consulted at
launch, and both belong to whoever needs the escalation (spec, *Out of
scope*).

`work.sh`'s `WORK_MODEL` (`scripts/ops/work.sh:84`, `:590-591`) is **not**
that mechanism and must not be presented as one: it re-tiers a whole
dispatch from the outside before launch, not a running session from the
inside, and it exists on the Claude Code row only.

**The handoff owes three sentences** it is easy to drop: each `p` in
`UNDISPATCHABLE` is repinned but not dispatchable, with #11 named (D8);
`escalation_tier` is prose without a mechanism for each persona D16
covers, accepted (D16); and the cost report is two single-vendor
measurements, never one number (D10).

**Amended r1.** The old T9 named the two moved personas and their
escalation tiers, called them "the only two personas in `personas/**`
that declare one", and listed `config/model_tiers.yaml` among the files
whose diff must be empty. The count and the names are computed; the
model-tiers line is removed because a tier re-bind is the operator's
other lever.

---

## Acceptance → task

| # | derives from | task |
|---|---|---|
| 1 | D1 | T0, T1 |
| 2 | D2 | T1 (values from T3) |
| 3 | D3 | T3 (P3) |
| 4 | D4 | T2 |
| 5 | D5 | T2 |
| 6 | D7 | T4, T5 |
| 7 | D6 | T5 (P1, P2) |
| 8 | D14 | T4 (the scratch-manifest test), T5 |
| 9 | D8, D15 | T6 (P1, P2) |
| 10 | D9(b) | T7 |
| 11 | D10, D13 | T8 (P4) |
| 12 | D11 | T2, T9 |
| 13 | D12 | T9 |
| 14 | D9(a) | **none — already satisfied** by PR #93 (`docs/SPEC.md:144-151`); T7 asserts this PR does not touch it |

Every decision is reached: D1 → T0/T1; D2 → T1; D3 → T3; D4/D5 → T2;
D6 → T5; D7 → T4/T5; D8/D15 → T6; D9(a) → PR #93, D9(b) → T7; D10/D13 →
T8; D11 → T2/T9; D12 → T9; D14 → T4/T5; D16 → T9.

No acceptance item is unreached. Item 14 is the only one with no task in
this plan, and by its own text ("satisfied by the amendment r1 PR, not
by the implementing PR") that is correct.

## Readings taken

Three places where the amended spec admits more than one implementation
and this plan chose. Each is cheap to overrule by editing the row.

**R1. The arms become symmetric: every arm produces the same three
observables.** D7 selects `ARM(h)` as the first persona "whose entry in
`app_manifests.yaml` grants every permission that arm's observables
need — `issues: write` for the comment observable, `contents: write` for
the commit-and-push observable and for #43 D19's persona-only marker",
and D14's differing case is "a harness all of whose pinned personas'
Apps lack `contents: write`". Both sentences require every arm to need
both permissions, which is only true if every arm produces both
observables. Today's arms are asymmetric — the Claude Code arm writes a
local file and comments, the Antigravity arm pushes
(`scripts/ops/smoke_launch.sh:209-233`) — and the split is a property of
*which arm ran second*, which is not a config fact and therefore cannot
survive derivation. So each arm now does all three: local artifact,
comment, pushed commit. The count stays at three, which is what
`ops.dispatch` already says. Cost of overruling: assign the observables
per arm index instead, and D14's permission test becomes per-index too —
at which point flipping a pin can move an observable to a persona whose
App cannot produce it, which is the failure D14 exists to prevent.
Second cost of this reading: every arm now pushes a branch, so the run
leaves one scratch ref per harness instead of one; the script deletes
them before each run the way it already deletes one
(`scripts/ops/smoke_launch.sh:262`).

**R2. Arms run in first-appearance order of the harness in the
`personas:` block.** D7 fixes the *set* of arms and the banner format
but not the order. First-appearance order is derived from the same file
the arms are, is stable under an edit that does not reorder the block,
and makes the banner sequence a visible consequence of the config. Cost
of overruling: sort the harness names instead — which is what
`Resolver.harnesses()` does (`scripts/sync_agents.py:278-279`) and would
be the more consistent choice if a reviewer prefers it; one line, no
behaviour change beyond the order.

**R3. D15's negative assertion is a committed scenario in
`scripts/ops/tests/work_test.sh`, not a hand-run recorded in the PR.**
The spec's "What is being built" block does not list that file, which
argues for a hand-run; but D15 says the refusal is *asserted*, and its
differing case is explicitly about a **future** session that misreads
the absence of coverage — which a hand-run in a closed PR does not
serve. The file is on neither the built list nor the
deliberately-not-touched list, and the scenario adds no behaviour, only
an assertion about behaviour that already exists unchanged. Cost of
overruling: delete the scenario, run the same two commands by hand,
paste them into the PR body and the #44 comment; the observable is
identical and only its durability is lost. *(Carried over from PR #63's
R2 unchanged. PR #63's R1 — whether the per-arm `check_claim` calls
survive alongside the standalone `#47` probe — is moot: D14 as amended
retires the probe entirely.)*

## Open questions for Athena

Two, both recorded rather than resolved here, per the plan stage's
contract: an assertion the plan cannot derive from a Decision row is a
missed ambiguity, not a judgment call.

**OQ-1 — D3 names no source for a model ID's vendor family.** The
procedure is "read `harnesses.<harness>.REVIEW`; take the resulting
model ID's vendor family", and no file in the repository maps a model ID
to a family: `config/model_tiers.yaml` holds bare IDs
(`config/model_tiers.yaml:11-27`), `docs/SPEC.md`'s review policy
deliberately says which family backs which reviewer "appears nowhere in
the policy", and PR #63's plan met this by hard-coding a prefix `case`
in a throwaway snippet — a fourth place a vendor fact would live, and
one no gate reads. It matters now rather than later: issue #105 is open
to re-bind tier cells to model IDs whose family a prefix rule may not
place. **The plan's working procedure** is that the implementing PR
states the family for each row *and the evidence for it* (the vendor's
own published naming for that model), and that an ID it cannot place
stops the run (P3) and is reported on #44 — never guessed, because a
wrong family silently passes a constraint the whole review policy rests
on. Athena's call: is that enough, or does D3 owe a `family:` key in
`config/model_tiers.yaml` (which would be #6's data, arriving early)?

**OQ-2 — D5's `--stat` testable does not account for a tier re-bind.**
D1 makes both files the operator's levers, but D5's testable reads: "the
pin commit's `git show --stat` lists `config/deployments.yaml` and
exactly the target paths the moved personas' old and new harnesses
account for, and nothing else", and Acceptance 5 repeats it. A pure tier
re-bind changes **no** pin and **every** target on that harness that
binds the re-bound tier — including sub-agent targets, which D5 says in
so many words are "in particular untouched". Under the literal text such
a commit fails Acceptance 5 while doing exactly what D1 licenses.
**The plan's working procedure** is T2's: the `--stat` must list
`config/deployments.yaml` (if `MOVED` is non-empty),
`config/model_tiers.yaml` (if `RETIERED` is non-empty), and exactly the
targets those two edits account for — a pin move accounting for a target
appearing and another disappearing, a tier re-bind accounting for a
`model` line changing in every target of that harness bound to that
tier. Athena's call: confirm, or restate D5's testable.

## Note for Odyssey — the stale work-in-progress branch

A partial implementation of the **old** assignment exists on
`odyssey/44-repin-personas-to`: unpushed commit `eeefa83`, plus
uncommitted target moves for two personas in the worktree
`.claude/worktrees/agent-a5e6d580255ad76b2`. It is **83 commits behind
`origin/main`**, and `eeefa83` itself is not #44 work at all — its
`--stat` is `.claude/commands/work.md`, `docs/SPEC.md`,
`intent/43-*/{plan,spec}.md`, `scripts/ops/smoke_launch.sh`,
`scripts/ops/tests/work_test.sh` and `scripts/ops/work.sh`: a merge of
#43's round-2 review fixes, all of which landed on `main` with PR #60.

**Start fresh from `origin/main`.** Nothing on that branch is
salvageable:

- `eeefa83`'s content is already on `main`, and re-landing it would
  revert #60's round-3 fixes and #108.
- the uncommitted target moves are the *output of the compiler* for two
  specific pins, which the operator has not necessarily chosen —
  reusing them would be re-hardcoding the choice this amendment
  removed, and D5 requires the rebuild to be produced by
  `scripts/sync_agents.py` in the pin commit anyway (T2), which takes
  one command.
- the branch predates `smoke_launch.sh`'s current shape, so a rebase of
  any T4-equivalent edit would conflict across the whole file.

Delete the branch and remove the worktree after checking the diff for
anything unexpected; that is its owner's call, not this plan's. Also
note **issue #105** is open and `in-progress` against
`config/model_tiers.yaml` — if it lands first, `RETIERED` will be
non-empty at implementation time and OQ-2's working procedure applies.

## Delegation

`MECHANICAL_TIER` (fully specified, no decision): **T0**'s derivation
steps, **T2** (run the compiler, run the three gates, run the per-set
assertions, report verbatim), **T3** once P3 has answered, **T9**'s
three negative-assertion commands, and the static half of **T4**
(`bash -n`, the two greps).

Not delegable below `IMPLEMENTATION_TIER`: **T1** (the comment's wording
is a judgment), **T4**'s edit (eleven literal sites and five ways it
goes wrong), **T6**'s test scenario, **T7** (a spec sentence is a claim
reviewers verify against the diff).

Not delegable at all — they read a live outcome and decide whether it
means success: **T5**, **T6**'s positive check, **T8**, and every probe
branch. So is any decision about the pins, which is the operator's.

## Pull request

One PR (D12) against `main`, and:

- the T0 derivation block: `MOVED`, `RETIERED`, `HARNESSES` with
  `ARM(h)` and `RELABEL(ARM(h))`, `HOUSEKEEPER`, `UNDISPATCHABLE` — or
  an explicit "no persona moved" if `MOVED` is empty;
- the pin diff, and the D3 resolution's rows and verdict;
- `git show --stat` of the pin+rebuild commit, with the per-`MOVED`
  model assertions and the per-sub-agent D11 assertion;
- the T5 smoke output: one banner per harness, three observables per
  arm with their authors, P1's signals, and the verdict line reporting
  0 tolerated observables;
- T6's hand-run argv and its JSON status per `UNDISPATCHABLE` persona,
  plus the sentence that each is repinned but not dispatchable and #11
  owns the change;
- the cost summary and a link to the #44 comment carrying the tables;
- the probe outcomes P0–P4, each with the branch taken;
- T9's negative assertions, and D16 cited for each persona it covers;
- **no** `Spec-impact:` line (D9).

Gates, all run before pushing: `python3 scripts/sync_agents.py --check`
and `--verify`, `bash scripts/ci/compiler_roundtrip.sh`, `bash
scripts/ci/sanitize_check.sh`, `bash scripts/ci/spec_check.sh "$BASE"`,
`bash -n scripts/ops/smoke_launch.sh`, and `bash
scripts/ops/tests/work_test.sh`.
