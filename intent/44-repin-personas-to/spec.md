# Spec: harness and model selection is configuration

**Issue:** #44 · **Status:** Approved (approval = merge of this PR) ·
**Author:** athena (`evekhm-athena-app[bot]`) ·
**Open questions:** none

## Amendment r1 (2026-09-03)

The presenter, who is this repository's human product owner, on
2026-09-03:

> actually it is pretty easy to update the pins for the models, so I can
> change it. in the spec - I want to explicitly mention - that the whole
> idea is to be able to re-pin and easily configure the harness and model
> selection! i do not want spec to hardcode or reference any choices!!!
> that must be changed!

and, asked which pins they wanted: *"I want to specify my own pins now."*

**The idea, stated once, up front.** Which harness runs a persona, and
which model a semantic tier resolves to on that harness, are
**configuration**. Re-pinning any persona to any harness, or changing
which model a tier resolves to, is an edit to `config/deployments.yaml`
or `config/model_tiers.yaml` followed by the compiler rebuild committed
alongside it — and nothing else. **No persona source changes for a
repin, ever.** Every gate in the repository — `scripts/sync_agents.py
--check`, `scripts/ci/compiler_roundtrip.sh`, `scripts/ci/sanitize_check.sh`,
the `constraints.distinct_model_families` resolution, and the launch
smoke — is written to prove **whatever configuration is present**, not
one particular assignment. That property is the deliverable of #44. The
concrete pins are the operator's input, live only in `config/`, and are
read out of the diff at merge time.

**What this amendment changed.** Every row, table, acceptance item and
paragraph that stated a persona→harness choice or a persona→model choice
as a *decision* is rewritten as a rule quantified over the configuration:
over *each moved persona* (defined in D1), over *each harness present in
`config/deployments.yaml`*, or over *each name in
`constraints.distinct_model_families`*. Where a name was carrying the
mechanism rather than a choice, the rule now cites the config file as the
source of the value. The title, the "pins before and after" table, D1–D8,
D10, D11, D13–D16 and Acceptance 1–13 are all amended; the structural
invariants they protected are unchanged and are stated as invariants.

**Format**, per `intent/43-harness-agnostic-launch/spec.md`: a row
amended after approval keeps its ID and carries an **Amended
&lt;date&gt; (&lt;who&gt;, &lt;why&gt;)** note in place, quoting the
clause it replaces, so the row's history reads without a diff and the
Decision ID a contract test cites never moves. Acceptance items keep
their numbers; new ones are appended.

## Amendment r2 (2026-09-04)

Three escalations, three rows. Nothing else in this file is reopened,
and D1's constraint governs every word below: no rule names a persona,
a harness or a model, and each is quantified over the configuration as
it stands at the implementing PR's head commit.

- **D7** — Atlas's **AT-4** on PR #133. D7 was read two ways: the arm
  selection is a rule over facts read from `config/` alone, so the
  implementation's clause reading `personas/<persona>.yaml`
  `authority.github_write` is unauthorised drift; or it is a rule over
  *declared* facts wherever they are declared, the prohibition being on
  a persona **name** as a literal rather than on a directory. The
  second reading is normative. **The code on PR #133 head `ab53c5b`
  stands; Odyssey owes no code change on this row**, and round 3 can
  close AT-4 against this amendment.
- **D3** — Daedalus's **OQ-1** in `plan.md`: no source of truth for a
  model ID's vendor family. Ruled: the family is a **declared** fact
  carrying its evidence, recorded in D2's comment next to the
  constraint it serves, and never inferred from an ID's spelling.
- **D5** — Daedalus's **OQ-2** in `plan.md`: whether a tier re-bind
  counts under D5's `--stat`. Ruled: it does. A **re-bound tier** is
  defined the way D1 defines a moved persona, and the testable is
  quantified over both levers.

Acceptance items 3 and 5 are rewritten in place and keep their numbers;
item 15 is appended.

**Round 1 of PR #135's review (2026-09-08, Argus R1-1 to R1-4) is folded
into r2 before it merges**, so no r3 layer sits over an unmerged r2: D5's
`--stat` rule now admits `config/deployments.yaml` when a listed name's
D3 row changes with no persona moved (R1-1) and names the model-bearing
file per layout (R1-4); D3 records that clause (b) is unmet on `main`
and names the owner (R1-2); D7's record says the selection rule widened
(R1-3).

---

Bootstrap compression per `intent/1-personas/spec.md` D10 applies here
too (as it did on #2): intent and spec land in one PR, recorded once,
not a precedent.

D1–D3 are the property and the reviewer constraint, D4–D6 the compiled
targets and the model, D7–D9 the smoke test and the living spec,
D10 the cost measurement, D11 the issue's open question. D12–D16 came
out of the spec-adversary pass against this draft and are marked
*(adversary)*.

Every claim below about `agy` behaviour cites
`runs/2026-09-03_agy-headless/findings.md` (agy 1.1.24, probed
2026-09-03) or `config/tools.yaml`'s inline record of #43's smoke run
(agy 1.1.25). **Any row can be overruled by editing this file at the
merge gate** — the merge is the acceptance, so an edited row is the
decision, not a comment asking for one.

## What is being built

```text
config/deployments.yaml           the operator's pins + the constraint
                                  comment (D1, D2)
compiled targets                  for each moved persona: the target of
                                  its OLD harness deleted, the target of
                                  its NEW harness added, by the rebuild
                                  in the same commit (D4, D5)
scripts/ops/smoke_launch.sh       arms derived from the pins, no persona
                                  name hard-wired (D7, D14)
docs/SPEC.md                      ops.dispatch: the derived arms (D9)
```

**Amended 2026-09-03 (athena, presenter's direction).** The block
enumerated six specific paths — `.claude/agents/odyssey.md` and
`.claude/agents/cassandra.md` `DELETED by the rebuild`,
`.agents/agents/odyssey/` and `.agents/agents/cassandra/` `NEW`, and
`config/deployments.yaml  2 pins flipped`. A file list that names the
moved personas is the same hardcoded choice as a D-row that names them.
The list is now the *shape* of the change; which files it resolves to is
read from the implementing PR's own diff of `config/deployments.yaml`.
`docs/SPEC.md`'s `config.bindings` sentence is added by **this**
amendment PR rather than by the implementing PR, because the property it
states is already true of merged code (D9).

Not touched, deliberately: `personas/**` — a repin never changes a
persona source, which is the whole point (D1) and is also why it adds no
sanitize surface; `config/tools.yaml`; `personas/lifecycle.json`;
`scripts/ops/work.sh` (it reads the pin, so its behaviour changes without
its text changing); `config/execution.yaml` (#25 D19 binds *placements*,
not harnesses); and `CLAUDE.md` (D11). `config/model_tiers.yaml` is
touched only if the operator re-binds a tier; a pure repin leaves it
byte-identical and D3 is run anyway.

## Where the pins live

`config/deployments.yaml`, and only there. This spec deliberately does
not reproduce them: a copy here would be a second source of truth that
goes stale the first time the operator edits the file, and reading it
would tell a builder what the pins *were* rather than what they *are*.
The implementing PR reads them from the file at its own head commit.

**Amended 2026-09-03 (athena, presenter's direction).** This section
replaces a table titled *"The pins, before and after"* with six rows —
one per persona, a `before` column, an `after` column with three values
bolded as changes, and a `tier → model after` column naming
`opus`, `gemini-3.1-pro-high`, `gemini-3.7-flash-high` and
`gemini-3.7-flash-medium`. Struck in full. It stated the operator's
choice as a spec fact, and it stated it twice over — harness *and*
resolved model — so a later repin would have falsified two columns of an
Approved spec that no gate reads.

## Decisions

| # | Decision |
|---|---|
| D1 | **Which harness backs a persona is configuration; this spec states the property and never a pin.** The pins live in `config/deployments.yaml` (`personas.<name>.harness`), the tier→model bindings in `config/model_tiers.yaml` (`harnesses.<harness>.<TIER>`). Re-pinning a persona, or re-binding a tier, is an edit to one of those two files plus the compiler rebuild committed with it (D5) — no persona source changes, no script changes, no spec change. Every rule below is quantified over **a moved persona**: a persona whose `harness:` value differs between the implementing PR's base commit and its head commit, read out of that diff and out of nothing else. Where a rule needs a model ID it resolves it through `config/model_tiers.yaml` at the head commit; where it needs a harness it enumerates the harnesses actually present in `config/deployments.yaml`. Testable: the implementing PR's diff of `config/deployments.yaml` changes only `harness:` values and comments; `git diff personas/` is empty; the PR body lists the moved personas and their before/after harnesses as read from its own diff, and this file names none of them. **Amended 2026-09-03 (athena, presenter's direction).** The row read: *"`odyssey` and `cassandra` move to `antigravity`; `athena` and `argus` stay on `claude-code`, each for a stated reason"*, with grounds naming `odyssey` "the highest-volume persona in the system — `IMPLEMENTATION` tier, `max_turns: 120`, `timeout_mins: 90`", `cassandra` "the cheapest work on the most expensive billing relationship", `athena` staying "because plan and design are the two gates where words become commitments", and `argus` staying as "the only persona left that can be the non-Gemini half"; its testable was *"`config/deployments.yaml`'s `personas` block matches the after column of the table above, and the implementing PR's diff of that file changes exactly two `harness:` values"*. Struck in full. Those grounds were true observations about which work is expensive, but they are arguments **for** a choice, and the choice is the operator's: the presenter sets the pins in `config/deployments.yaml` themselves, and a spec that names them turns a one-line config edit into a spec amendment. The one clause that was never a preference — the reviewer pair — survives as D3's procedure and as D2's comment, quantified over whatever pins exist. |
| D2 | **The one constraint a pin can violate is recorded next to the data it constrains, in `config/deployments.yaml`, not in this spec.** Grounds: `docs/SPEC.md` states that which model family backs which reviewer "is a `config/` fact and appears nowhere in the policy", so the config file is the only place the fact may live — and it is a fact with no slack, because a session repinning "everything else for price" can violate #2 D4 with a one-line edit and, until #6's check lands, no error. The implementing PR writes or refreshes one comment immediately above the `constraints:` block recording, for the pins present at its head commit, the resolved family behind each name in `constraints.distinct_model_families` and the rule that repinning either name without repinning the other in the same edit is a violation. Persona and vendor names belong in that comment: the sanitize gate's `vendor` rule scopes to `personas/**` (`scripts/ci/sanitize_check.sh`), and `config/` is by #2 D2 the layer where such strings live. Testable: `scripts/ci/sanitize_check.sh` passes with no new allowlist entry; the comment exists immediately above `constraints:` and its values equal the D3 resolution run at the same commit. **Amended 2026-09-03 (athena, presenter's direction).** The row read *"The reason `argus` stays is written into `config/deployments.yaml`"* and its comment content was specified as *"names `argus` as the last non-Gemini reviewer"*. The mechanism is unchanged and the comment is still required; which name it carries is now derived from the configuration at merge time rather than fixed here. |
| D3 | **The #2 D4 check is a resolution performed and recorded, not a confirmation asserted.** The procedure, for each name in `config/deployments.yaml`'s `constraints.distinct_model_families`: read `personas.<name>.harness`; read `harnesses.<that harness>.REVIEW` from `config/model_tiers.yaml`; take the resulting model ID's vendor family. The constraint holds when the families are pairwise distinct across the list, and the implementing PR **records the resolved `(name, harness, model, family)` row for every name in the list**, as read at its own head commit. Two things this fixes that "confirm it still holds" leaves open. First, **the tier is `REVIEW` and only `REVIEW`**: a persona's `escalation_tier` never enters the check, because the list contains personas and an escalation tier is not one. Second, **the check is run even when its inputs are byte-identical before and after** — even when `model_tiers.yaml` is untouched and no name in the list was repinned — because "the inputs did not change" is a claim about the diff, and the diff is what acceptance reads. If the resolution fails, the implementing PR does not proceed: it reports the violating pair and hands the pin choice back to the operator. Testable: the recorded rows exist, one per name; each model ID equals the value at the cited path in `config/model_tiers.yaml` at that commit; the families are pairwise distinct. **Amended 2026-09-03 (athena, presenter's direction).** The row carried a worked resolution — *"After D1 it resolves: `argus` → `claude-code` → `opus`; `atlas` → `antigravity` → `gemini-3.1-pro-high`; families `claude` and `gemini` differ, so the constraint holds"* — and a testable naming `odyssey` and `cassandra` as "the two `harness:` lines changed". Both struck: the worked example is exactly the resolution the procedure produces, so writing it here freezes an output the procedure exists to compute. The failure branch is new: the old row assumed the resolution would pass. **Amended 2026-09-04 (athena, plan OQ-1).** Daedalus's OQ-1: this row's step three says "take the resulting model ID's vendor family" and names no source, and no file in the repository maps an ID to a family. Ruled, as a property rather than a table: **a model ID's vendor family is a declared fact, never an inferred one.** It is not derivable inside this repository — which organisation built a model is a fact about the world — and any in-repo rule that reads it off the ID's spelling is a guess that passes *silently* when it is wrong, which is the one failure mode a constraint protecting reviewer independence cannot have. So, four clauses. (a) **Declared where it is used, next to the data it constrains:** D2's comment immediately above `constraints:` in `config/deployments.yaml`, which this spec already requires the implementing PR to write or refresh at its own head commit, is the single source of truth for the family behind each name in `constraints.distinct_model_families`; no second home is created for it, and D2's testable already binds that comment's values to this row's resolution at the same commit. (b) **With evidence:** each declared family carries, in the same comment and in the recorded row, the ground for it — the vendor's own published naming for that model — so the declaration is checkable by the next reader instead of merely asserted. (c) **Never inferred:** no script added by this issue may classify a family by pattern-matching a model ID (a prefix `case`, a substring test, a regex over the ID). That is a fourth place a vendor fact would live, it is the one place no gate reads, and it is wrong exactly when a newly bound ID does not follow the spelling the pattern was written for. (d) **An ID whose family cannot be declared with evidence stops the run** (plan P3): the implementing PR reports the ID on #44 and hands the pin choice back to the operator, and never guesses. **No `family:` key is added to `config/model_tiers.yaml` by this issue:** that file binds tiers to IDs, the same ID appears in more than one cell, and a per-cell family restates one fact once per cell so that the copies go stale independently. Whether #6's automated check later promotes the declaration from a comment to a machine-readable key **in the same file, adjacent to the constraint it serves**, is #6's call and needs no amendment here — the property fixed by this row is *declared next to the constraint, with its evidence, never inferred from the ID's spelling*, and both spellings satisfy it. Testable, amended: the recorded rows are `(name, harness, model, family, evidence)`, one per name; each model ID equals the value at the cited path in `config/model_tiers.yaml` at that commit; the families are pairwise distinct; and the implementing PR's diff introduces no prefix, substring or regex test over a model ID that yields a family. **Recorded 2026-09-08 (athena, round-1 review of PR #135: R1-2).** Clause (b) is unmet on `main`. PR #133 recorded `(name, harness, model, family)` rows with no evidence column, and D2's comment carries a vendor and a family per name with nothing offered as the ground for either; commit `11b88aa` later re-bound a `REVIEW` cell and refreshed the rows in that same shape. Acceptance 3 is therefore **unmet while #44 sits at `status:in-review`**, and this amendment is unable to meet it, since it touches `intent/**` only. **Owner and vehicle:** the implement stage's actor, in one follow-up PR under #44 whose diff of `config/deployments.yaml` is comment-only (Acceptance 1) and whose body records the five-column rows on #44; #44 stays open until it lands. **The shape of the evidence, so the item is checkable:** the fifth column is the model's name as the vendor's own published model list spells it, written into the same comment row — of the form `<id> -> <family>, published as "<vendor's model name>"`. Where the cell holds a harness alias in place of a vendor ID, the evidence is the vendor model that harness documents the alias as resolving to, spelled the same way. A vendor name and a family name on their own (the shape on `main` today) are the assertion and do not satisfy (b).
 |
| D4 | **A persona's resolved model reaches its harness the way that harness's target layout carries it — and never as a `model:` key in an Antigravity `agent.md`.** For a target under `.agents/agents/<p>/`, the model rides in the sidecar `agent.json` as `.model`, which the harness ignores and `scripts/ops/work.sh` reads with `jq` and passes as `agy --model`; `agent.md`'s frontmatter carries `name`, `description` and `tools` and no `model:` key, because a `model:` key voids the whole agent, which then silently falls back to the stock agent (#43 D8/D9, findings Q1b). For a target under `.claude/agents/<p>.md` the model is the frontmatter `model:` key. Testable, for **each moved persona**: the model its new target carries equals `config/model_tiers.yaml`'s `harnesses.<the persona's new harness>.<the persona's tier>` at that commit; and tree-wide, no `.agents/agents/*/agent.md` contains a line matching `^model:`. **Amended 2026-09-03 (athena, presenter's direction).** The row named the values: *"`jq -r .model .agents/agents/odyssey/agent.json` is `gemini-3.7-flash-high` (`antigravity.IMPLEMENTATION`) where the deleted `.claude/agents/odyssey.md` said `model: claude-sonnet-5`"*, and the same sentence for `cassandra` at `gemini-3.7-flash-medium`. Struck: those are four model IDs and two persona names that a tier re-binding in `config/model_tiers.yaml` — the presenter's other config lever — falsifies without touching a persona or a pin. The rule is unchanged; the values are resolved, not quoted. |
| D5 | **The rebuild is part of the same commit as the pin edit, and `scripts/sync_agents.py --check` is the gate.** For each moved persona, exactly two things happen to the compiled tree: the target its **old** harness emitted disappears, and the target its **new** harness emits appears — the whole layout of each, per `personas.compiler`. **No other compiled file changes**: sub-agent targets in particular are untouched, because `kind: subagent` sources carry no pin and are already emitted for every harness (#2 D3, `scripts/sync_agents.py`), so repinning a persona adds and removes no sub-agent file. Same commit rather than a follow-up: a commit in which `deployments.yaml` names one harness and the other harness's target still exists is a tree where `sync_agents.py --check` fails and `work.sh` preflights a target that does not exist (#43 D3, exit 1) — a state no bisect, no CI run and no cherry-pick should be able to land on. Testable: `scripts/sync_agents.py --check` and `scripts/ci/compiler_roundtrip.sh` both pass at the tip; the pin commit's `git show --stat` lists `config/deployments.yaml` and exactly the target paths the moved personas' old and new harnesses account for, and nothing else. **Amended 2026-09-03 (athena, presenter's direction).** The row read *"Exactly four files appear and two disappear: `.agents/agents/{odyssey,cassandra}/{agent.md,agent.json}` added, `.claude/agents/{odyssey,cassandra}.md` deleted"*, and its testable counted *"exactly those seven paths"*. Struck: the counts and the paths are functions of how many personas moved and in which direction. The invariant — the rebuild is in the pin commit, and nothing outside the moved personas' targets moves — is what mattered and is what remains. **Amended 2026-09-04 (athena, plan OQ-2).** Daedalus's OQ-2: D1 makes `config/model_tiers.yaml` the operator's second lever, but this row's testable named only `config/deployments.yaml` and the targets *"the moved personas' old and new harnesses account for"*, and its body says sub-agent targets *"in particular are untouched"* — so a **pure tier re-bind**, which moves no pin and changes the model-bearing line in every target on that harness bound to that tier, sub-agent targets included, fails the testable and Acceptance 5 while doing exactly what D1 licenses. It counts. Confirmed as the plan's T2 procedure, restated here as a property and quantified the way D1 quantifies a moved persona. **Definition, alongside D1's:** a **re-bound tier** is a `harnesses.<harness>.<TIER>` cell in `config/model_tiers.yaml` whose value differs between the implementing PR's base commit and its head commit, read out of that diff and out of nothing else. **The rule:** the commit's `git show --stat` lists exactly — `config/deployments.yaml` if any persona moved, `config/model_tiers.yaml` if any tier was re-bound, and exactly the compiled targets those two edits account for, and nothing else. A moved persona accounts for its old harness's target disappearing and its new harness's target appearing. A re-bound tier accounts for the model-bearing line changing in **every** target on that harness that binds that tier — **including sub-agent targets**, because #2 D3 makes a sub-agent carry no pin and resolve through its dispatcher's harness, so one sub-agent source has one target per harness and each carries that harness's own resolution (D11). Neither lever being exercised is a vacuous case, not a pass: a commit that moved no persona and re-bound no tier has nothing for this row to gate. **Scoped, not struck:** the *"sub-agent targets in particular are untouched"* clause is true of a **pure repin** — the case this row was written about — and only of it; a re-bind of a tier that some sub-agent binds necessarily moves those targets, and a commit that re-bound such a tier and left them alone is precisely the drift `scripts/sync_agents.py --check` exists to fail. Everything else in this row is unchanged: the rebuild is in the same commit as the config edit, for the same bisect reason, and `--check` plus `scripts/ci/compiler_roundtrip.sh` pass at the tip. **Amended 2026-09-08 (athena, round-1 review of PR #135: R1-1, R1-4).** R1-1: the rule above admits `config/deployments.yaml` only *if any persona moved*, while D2 binds that file's comment rows to the D3 resolution at the same commit — so re-binding a `REVIEW` cell on a harness that some name in `constraints.distinct_model_families` is pinned to changes those rows with no persona moved, and the rule as written failed exactly that commit. `main` already carries one: `11b88aa` re-bound one `REVIEW` cell, refreshed two comment lines in `config/deployments.yaml`, and touched no pin. **The rule, corrected:** the commit's `git show --stat` lists exactly — `config/deployments.yaml` if any persona moved **or if the D3 row of any listed name differs between base and head**, `config/model_tiers.yaml` if any tier was re-bound, and the compiled targets those edits account for, and nothing else. When `config/deployments.yaml` appears on the second ground alone, its diff is D2's comment and nothing else (Acceptance 1 already admits comments). A `config/deployments.yaml` line in the `--stat` of a commit that moved no persona and changed no listed name's D3 row is unaccounted for and fails the item. The two conditions are read from the same diff D1 reads: a moved persona from `harness:` values, a listed name's D3 row by running the D3 procedure at base and at head. R1-4: "the model-bearing line" is one file per layout, per D4 — the frontmatter `model:` line of `.claude/agents/<p>.md`, and the `.model` line of `.agents/agents/<p>/agent.json`; `agent.md` carries no model and is absent from a re-bind's `--stat`. A "target" in this row's accounting is the file set D4 gives the layout: a moved persona accounts for the whole set appearing or disappearing, a re-bound tier for the model-bearing file of that set alone.
 |
| D6 | **The acceptance for a moved persona's `tools:` block is a real launch on its new harness, never an inspection of the file.** Grounds: `config/tools.yaml`'s own record of #43's smoke run (agy 1.1.25) — an unrecognised tool name in `agent.md`'s `tools:` block is a **hard** error (exit 1, `status: "ERROR"`, zero tokens, no session at all), and "every antigravity persona carrying `delegate` was unlaunchable" until that one line changed. Every capability a persona declares resolves through `config/tools.yaml`'s column for its new harness, and a capability that column cannot map is either a declared fallback or a build failure (`personas.compiler`) — but the measurement that matters is a session that starts. Testable, for each moved persona: the launch D7 or D15 performs returns a non-zero input-token count and a persona-shaped answer, not `status: "ERROR"` with zero tokens. **Amended 2026-09-03 (athena, presenter's direction).** The row enumerated the resolved capability lists — *"`odyssey`'s capabilities resolve to `view_file, grep_search, find_by_name, write_to_file, replace_file_content, run_command, manage_subagents`; `cassandra`'s to the same list minus the two write tools"* — and named the two personas as the ones carrying `delegate`. Struck: those lists are `config/tools.yaml` joined with two persona sources, computed by the compiler, and they change with the pin. The grounds and the "a session that starts is the proof" rule are unchanged. |
| D7 | **`scripts/ops/smoke_launch.sh` derives its arms from `config/deployments.yaml`; no persona name is hard-wired in the script or in this spec.** One arm per harness that appears as a `personas.*.harness` value. The arm's persona for a harness is selected by a rule over config facts only: **the first persona, in `config/deployments.yaml`'s own `personas` declaration order, pinned to that harness, whose entry in `scripts/auth/app_manifests.yaml` grants every permission that arm's observables need** — `issues: write` for the comment observable, `contents: write` for the commit-and-push observable and for #43 D19's persona-only marker. If no persona pinned to a harness qualifies, the run **exits 1 naming the harness and the missing permission**; it never skips an arm and never exits 0 having exercised one harness twice. Each arm's `relabel` target is derived the same way: the label of a rung the selected persona owns, from `personas/lifecycle.json` joined with that persona's `stage` list — because `work.sh --as` refuses a persona that does not own the current stage (#36 D8). The scratch issue's errand text names no persona: it already reads "your persona, your harness and the UTC time", and it stays that way. The script's own housekeeping identity (writing the body, relabelling, counting comments) is likewise derived — the first persona in declaration order whose App grants `issues: write` and `contents: write`, regardless of harness, since housekeeping makes no model call. An operator who wants a different arm may name personas as trailing arguments, each binding to the harness its own pin names; a name that is not a persona, or two names resolving to the same harness, is exit 1. Testable: with the pins as they stand at merge time, `scripts/ops/smoke_launch.sh <scratch>` prints one `run N · <harness> · <persona>` banner per harness in `config/deployments.yaml`, the persona on each line is the one the selection rule yields for that harness, and no persona name appears as a literal in the script; flipping a pin in a scratch copy of `config/deployments.yaml` changes the banners with no edit to the script. **Amended 2026-09-03 (athena, presenter's direction).** The row read *"the two arms follow the pins: the `claude-code` arm becomes `athena`, the `antigravity` arm becomes `odyssey`"*, chose `athena` over `argus` on an `issues: write` argument that #47 has since closed, chose `odyssey` over `daedalus` because "the arm's job after this issue is to prove that *the moved persona* launches", fixed the relabel targets at `status:planning` and `status:implementing`, fixed the housekeeping identity at `odyssey`, and asserted the two comment/commit authors by literal login. Struck in full and replaced by the derivation. The failure the row existed to prevent is unchanged and is now stated as an invariant: an arm that silently runs the wrong harness — `#43`'s gate exiting 0 while covering one harness twice — is the exact class of expensive silent success #43 exists to prevent, and the "exits 1 naming the harness" clause is what forbids it for **any** pinning, not just for the one this issue happened to make. **Amended 2026-09-04 (athena, round-1 review of PR #133: AT-4).** Two readings of this row were live. **First:** the selection is a rule over facts read from `config/` alone — the row says "over config facts only" and its enumeration stops at `scripts/auth/app_manifests.yaml` — so the implementation's clause reading `personas/<persona>.yaml`'s `authority.github_write` is a fourth clause the Approved spec does not authorise, and `docs/SPEC.md` and this spec disagree about what the gate does. **Second:** the selection is a rule over *declared* facts, wherever the repository declares them, and the prohibition this row carries is on a persona **name** appearing as a literal — not on a directory. **The differing case**, which the live run produced: a persona pinned to some harness whose App grants both permissions and which owns a labelled rung, but whose own contract declares no `authority.github_write` of the form `branch:<prefix>*`. Under the first reading it is selected as that harness's arm; the push observable then asks it to push a branch outside the surface its own contract declares; the arm reads its contract and correctly refuses; and `check_pushed_artifact` records that correct refusal as *"the persona did not load, or the token did not authenticate"* — the misattributed failure #43's smoke exists to remove, on an arm the operator cannot fix because nothing in the output names the cause. Under the second reading that persona is disqualified at selection with its own reason named, the next qualifying persona in declaration order becomes the arm, and a harness left with none is exit 1 naming the harness and the missing clause (D14). **The second reading is normative.** The spec follows the code: the implementation on PR #133 head `ab53c5b` is what this row now says, **Odyssey owes no code change on this row**, and `docs/SPEC.md`'s `ops.dispatch` entry as that PR upserts it is correct as written. **Struck:** the words *"over config facts only"*, and the enumeration that ended at the App manifest. **Replaced by:** the arm for a harness is the first persona, in `config/deployments.yaml`'s own `personas` declaration order, pinned to that harness, that satisfies **all three** of — **(i)** its entry in `scripts/auth/app_manifests.yaml` grants every permission that arm's observables need; **(ii)** it owns a stage that some rung of `personas/lifecycle.json` labels, since `work.sh --as` refuses a persona that does not own the current stage (#36 D8), which is also where the arm's `relabel` target comes from; **(iii)** its own contract in `personas/<persona>.yaml` declares `authority.github_write` as `branch:<prefix>*` — exactly one `*`, and it is the last character — which is both the surface the pushed artifact must land inside and the only shape on which the gate's derivation and the errand's own wording ("that glob with `smoke-<issue>` in place of its `*`") cannot compute different branches. Each clause names its own disqualification reason rather than collapsing into "does not qualify", because the operator's fix differs per clause: a permission is granted on github.com, a rung comes from #11 or #25, a write surface is declared in `personas/`. **The rule the struck phrase was carrying is unchanged, restated without the false locative:** no persona name is a literal in this script or in this spec, and every input the selection reads is a **declared fact read from a file at the head commit** — so flipping a pin, granting a permission, giving a persona a rung, or widening a write surface changes what this gate covers with no edit to the script and no edit to this spec. `personas/**` was never excluded in full: the pre-amendment row already read `personas/lifecycle.json` joined with the persona's own `stage` list — downstream of selection, to derive the already-selected persona's `relabel` target. **This amendment widens the selection rule.** That join is promoted into clause (ii), so a persona whose App grants both permissions and which owns no labelled rung was *selected* before (with an underivable `relabel` target) and is *disqualified* now, handing the arm to the next persona in declaration order; and clause (iii) is new. "Config facts only" was inaccurate on the day it was approved, and the rule that replaces it is wider than the one it replaces (recorded 2026-09-08, round-1 review of PR #135: R1-3).
 Testable, extended: with a scratch persona directory in which every persona pinned to some harness fails clause (ii) or clause (iii), the script exits 1 naming that harness and that clause's reason and launches nothing; and each selected arm's push ref is `<prefix>smoke-<issue>` derived from that persona's own glob, with no branch name of the script's invention. |
| D8 | **A persona whose only stage has no rung is repinned but not dispatchable, and that is structural rather than a gap in this issue.** `personas/lifecycle.json` states that `intake`, `deploy` and `maintain` "are stage-enum values with no rung and are absent by construction": no `status:*` label resolves to them, and `work.sh` validates `--as` against the owners of the stage the labels say is current (refusal (f)). So for any persona all of whose stages have no rung, `work.sh <n> --as <that persona>` refuses on every issue in the repository, before a repin and after it. What this issue owes such a persona is the *harness* half, not the *dispatch* half — see D15 for the two observables. Testable: for each moved persona with no dispatchable rung, this spec, the implementing PR body and the #44 handoff say it is repinned but not dispatchable, and name the issue that would give it a trigger (#11 for a cadence, #25 for an `config/execution.yaml` entry). **Amended 2026-09-03 (athena, presenter's direction).** The row was written about `cassandra` by name throughout — *"`cassandra`'s only stage is `maintain`"*, *"`work.sh <n> --as cassandra` refuses on every issue"*, *"Her dispatch remains impossible until #11 decides her cadence"*. The rule is unchanged and now applies to whichever persona the configuration puts in that position, if any; the two tracker issues stay named because they are issues, not pins. |
| D9 | **The living spec is upserted in two places, and neither PR claims `Spec-impact: none` falsely.** (a) **This amendment PR** upserts one sentence into `docs/SPEC.md`'s `config.bindings`, stating the property D1 states: re-pinning a persona or re-binding a tier is an edit to those config files plus the rebuild committed with it, no persona source changes, and the drift, sanitize and reviewer-constraint gates prove whatever configuration is present. That sentence describes **merged code** and so belongs in the entry body rather than in *Agreed, not yet built* (AGENTS.md, "The living spec"). (b) **The implementing PR** upserts `ops.dispatch`, whose current text — "one real launch per harness — three named observables each, with the claim half of the Antigravity run reported as `BLOCKED ON #47` until that App's `issues: write` permission is granted" — is falsified twice by D7 and D14: the arms are derived rather than fixed, and the `#47` clause is retired. Nothing else in `docs/SPEC.md` moves: `config.bindings` deliberately does not enumerate pins, and the review entry deliberately says which family backs which reviewer "appears nowhere in the policy". The implementing PR touches behavior-bearing paths (`config/`, `scripts/`) and genuinely changes behaviour, so `Spec-impact: none` is not available to it. Testable: `scripts/ci/spec_check.sh <base>` passes on the implementing PR because its diff touches `docs/SPEC.md`, not because of a marker; the `config.bindings` sentence exists at the tip and names no persona and no model. **Amended 2026-09-03 (athena, presenter's direction).** The row assigned the whole upsert to the implementing PR and described the `ops.dispatch` change as "D7 changes which personas those runs are". Amended because the property itself now needs stating in the living spec — the presenter's point is that the system is re-pinnable, and a spec silent on it leaves the property undocumented until the implementation lands — and because a sentence about which personas the arms are would be the same hardcoding one layer down. **Bounds note:** `docs/SPEC.md` is outside `athena`'s declared path bounds (`intent/**`) and the living-spec upsert is normally the implementer's (`AGENTS.md`); clause (a) is taken on the operator's explicit direction for this amendment and is flagged in the PR body, so a reviewer can route it back to the implementing PR by dropping one hunk. |
| D10 | **The cost measurement is a procedure run for whatever moved, and it never produces a single cross-vendor dollar figure.** `scripts/ops/session_spend.sh` reads Claude Code `*.jsonl` transcripts and prices them against the Anthropic rate table; a model that table does not know is reported `UNPRICED` by name with its tokens excluded from the USD columns. It therefore cannot price a Gemini session, and a "we saved $X" number spanning both vendors would be an invention. For **each moved persona**, the procedure is: (a) **before** — `scripts/ops/session_spend.sh <transcript-dir> --check` over that persona's baseline session set (D13), recording the two numbers AGENTS.md requires together, cache hit rate `read/(read+write+fresh)` and tokens-per-message, plus the per-model USD roll-up; (b) **after** — the same command over the after set, where the observable is that the rows attributable to that persona on its **old** harness fall to zero; (c) **the other side** — for a harness whose sessions the tool cannot price, the launcher's own reported `usage` (for `agy`, the `usage` object in `--output-format json`, findings Q5), recorded per run as tokens, with the vendor's bill named as the authority for dollars. Where it lands: a run folder `runs/<YYYY-MM-DD>_44-repin-cost/` per AGENTS.md, which is gitignored — so the numbers do not survive there. They are reported in a comment on #44 and summarised in the implementing PR body, and the run folder's `findings.md` carries the disposition footnote naming that comment. Testable: the #44 comment shows, per moved persona, before and after with hit rate, tokens-per-message and the per-model USD table for the priceable side, and tokens with no USD column for the other; the run folder carries a disposition footnote. **Amended 2026-09-03 (athena, presenter's direction).** The row was written as one comparison of `odyssey` and `cassandra` moving from Anthropic to Gemini — *"the `claude-sonnet-5` and `haiku` rows attributable to `odyssey` and `cassandra` fall to zero"*, *"the antigravity side"* as a fixed heading. Struck: the measurement is per moved persona and symmetric in direction, since a repin can also move work **onto** the priceable harness, in which case the "before" side is the one the tool cannot price. |
| D11 | **A harness's tier→model note describes the tier for sessions on that harness, not for the persona that happens to run at it, so a pin never makes it stale; the implementing PR does not touch `CLAUDE.md`.** The two readings: the note describes the tier for *the persona that runs at it* (so moving that persona makes it stale prose), or it describes the tier *for sessions running on that harness* (so a persona pin is orthogonal to it). The differing case: after any repin that moves the last persona off a harness's tier, a persona still on that harness dispatches a sub-agent bound to it. Under the first reading nothing tells that session which model the sub-agent runs at; under the second, the compiled sub-agent target still carries the model the harness's column resolves, and the binding is exactly what produced it. The second reading is correct and structural, not a preference: AGENTS.md ("Subagent model tiers") makes the tier→model map a **per-harness** fact, `config/model_tiers.yaml` keeps a full column per harness, and #2 D3 says a sub-agent carries no pin and resolves through its dispatcher's harness — so one sub-agent source yields one compiled target per harness, each carrying that harness's resolution, and both continue to exist whatever the pins are. Testable: for every `kind: subagent` source, a target exists for every harness after the rebuild, each carrying its own harness's tier resolution from `config/model_tiers.yaml`; `git diff CLAUDE.md` is empty. **Amended 2026-09-03 (athena, presenter's direction).** The row was written as `CLAUDE.md`'s `IMPLEMENTATION_TIER` note versus `odyssey`'s move, with a differing case naming `athena` dispatching `coder`, and a testable asserting *"`.claude/agents/coder.md` still says `model: claude-sonnet-5`"* and *"`jq -r .model .agents/agents/coder/agent.json` is still `gemini-3.7-flash-high`"*. Struck: two model IDs and one sub-agent name that a tier re-binding falsifies. The rule — a pin is orthogonal to a per-harness tier binding — is unchanged and is now stated for any harness and any tier. |
| D12 *(adversary)* | **The pins, the rebuild, the smoke change and the `docs/SPEC.md` sentence are one pull request, not a config-only PR plus a follow-up.** Two readings of "config-only" (#44's own wording): the implementing PR touches only `config/deployments.yaml` and the compiled targets, with D7's smoke change filed as a separate issue; or one PR carries all of it. The differing case is the window between two PRs. During it, `scripts/ops/smoke_launch.sh <scratch>` launches twice against arms the pins no longer justify and **exits 0** — a green gate reporting coverage of a harness it did not touch, while `docs/SPEC.md` states behaviour the script no longer has. One PR. "Config-only" survives as a statement about the *source* layer: `personas/**` is untouched and one line of one config file decides the harness. |
| D13 *(adversary)* | **The cost baseline is a named set of sessions, not a calendar window.** Two readings of D10's "before": the N days of transcripts preceding the merge, or an explicitly listed set of sessions. The differing case: a moved persona worked three stages in the week before the PR and none in the week after, because no issue reached its rung. Under the calendar reading the after-window shows near-zero spend for it and the report claims a saving the repin did not cause. Under the session reading the comparison is, **per moved persona, the last three sessions it ran on its old harness before the merge, listed by transcript id, against the first three on its new harness after** — and if fewer than three exist after, the report says how many it has and calls the number provisional rather than dividing by a week. A moved persona with no dispatchable rung (D8) is reported as "no sessions yet", naming the issue that would give it a trigger. A comparison whose denominator is time measures how busy the week was; this one measures what a session costs. **Amended 2026-09-03 (athena, presenter's direction).** The row's differing case and its last clause were written about `odyssey`'s implement stages and `cassandra`'s sweeps by name; the rule and the three-session shape are unchanged. |
| D14 *(adversary)* | **An observable an arm's persona cannot produce is never silently skipped: the arm selection rejects such a persona up front, and a harness with no qualifying persona fails the run.** Two readings of D7: the arms are chosen for the pins and any permission gap is tolerated at assertion time with a note, or the permission requirement is part of the selection and a gap is a hard failure. The differing case: a harness all of whose pinned personas' Apps lack `contents: write`. Under the first reading the run prints a tolerated note, asserts what it can, and **exits 0** — a gate reporting a harness as covered when its persona-load proof (#43 D19's marker, which rides in a pushed commit) never ran. Under the second the run exits 1 naming the harness and the permission, and the operator either grants it or repins. Second reading: D7's selection rule reads `scripts/auth/app_manifests.yaml` and the "exits 1 naming the harness and the missing permission" clause is the whole of the tolerate mechanism. Testable: with a scratch `app_manifests.yaml` in which every persona pinned to one harness lacks `contents: write`, the script exits 1 naming that harness and that permission, and launches nothing. **Amended 2026-09-03 (athena, presenter's direction, and #47 closed).** The row read *"The `BLOCKED ON #47` probe survives the arm swap as a standalone `check_claim daedalus`, launching nothing"*, and its grounds turned on #43 D19's property that "its `BLOCKED ON #47` line disappears once the permission is granted, with no edit to the script". #47 closed on 2026-09-03 and `scripts/auth/app_manifests.yaml` now records `issues: write` for every persona, with the file's own header stating that the dispatch protocol requires it of all six — so the probe has nothing left to probe, and a standalone `check_claim <a named persona>` would be a hardcoded persona kept alive for a closed issue. Retired, and the general rule it was a special case of is stated instead. The verdict line's tolerated-observable count stays in the script and now prints 0. |
| D15 *(adversary)* | **For a moved persona with no dispatchable rung, acceptance is one positive harness check and one negative dispatch assertion, and the negative one is required.** Two readings of D8: such a persona's acceptance is only that the compiled target exists and `--check` passes, or it also asserts the refusal. The differing case: a future session repins that persona back and, finding no launch coverage, concludes the target was never proven; or the reverse — a session sees `work.sh --as <it>` fail and files it as a #44 regression. So both are asserted. **Positive:** the exact line `work.sh` would build for that persona on its new harness, resolved from `config/deployments.yaml`, `config/model_tiers.yaml` and the compiled sidecar at that commit, run by hand, returns success with a non-zero input-token count and an answer that shows the persona loaded rather than the harness's stock agent. **Negative:** `scripts/ops/work.sh <any labelled issue> --as <that persona>` exits 2 naming the owners of that issue's stage, and the message does not mention a harness — proving the refusal comes from the stage machinery (its stage has no rung) and not from the repin. **Amended 2026-09-03 (athena, presenter's direction).** The row was `cassandra`'s, and the positive observable was quoted as a literal command line — *"`agy -p '<the D2-of-#43 prompt>' --agent cassandra --add-dir <repo root> --model gemini-3.7-flash-medium --output-format json --print-timeout 20m`"*. Struck: that line hardcodes a persona, a harness, a model and a timeout, all four of which are config values. "The exact line `work.sh` would build, resolved at that commit" is the same assertion with no value copied out of config, and `DRY_RUN=1 scripts/ops/work.sh` prints it. |
| D16 *(adversary)* | **On a harness with no runtime model switch, `escalation_tier` means "hand the question back on the issue", not "raise the model" — and this issue records that rather than fixing it.** It applies to **any persona declaring `escalation_tier` in `personas/**` that is pinned to a harness whose launcher takes one model, fixed at launch**. Two readings of what the compiled sentence "You may escalate to the … grade only when …" then means. First: escalate = run at the higher model. The differing case: such a persona hits a genuinely hard problem mid-stage. Under the first reading it must reach the higher tier's model and cannot — `agy` takes one `--model` fixed at launch from the sidecar, headless print mode is the only mode #43 offers for that harness (#43 D5), and #36 D7 forbids a flag that names a model, so the only escalation path is a second `work.sh` invocation that resolves the same model again; the session stalls until the wrapper's cap kills it. Second: escalate = stop and hand the question back on the issue, which is what the persona's own role text already requires for open design questions. Second reading, for any harness in that position. It is recorded rather than fixed because fixing it means either a model-bearing flag (forbidden) or a second tier column consulted at launch, and both are `work.sh`/compiler changes that belong to whoever needs the escalation, not to a pin edit. Testable: the #44 handoff cites this row for each moved persona it applies to, naming them from the diff; no `escalation_tier` handling is added to `work.sh` or `scripts/sync_agents.py` in the implementing PR. **Amended 2026-09-03 (athena, presenter's direction).** The row read *"`escalation_tier` becomes prose without a mechanism for both moved personas"* and named *"`odyssey` (`escalation_tier: FRONTIER`) and `cassandra` (`escalation_tier: REVIEW`) … the only two personas in `personas/**` that declare one"*. The counting and the two names are struck; which personas declare an `escalation_tier` is a fact of `personas/**` and which are affected is a fact of the pins, both read at merge time. |

## Acceptance

Each item names the Decision it derives from; a contract test that
cannot cite one is a missed ambiguity and comes back here (the
spec-adversary skill's downstream contract). Items 1–13 were rewritten
by amendment r1 (2026-09-03) and keep their numbers; item 14 is
appended. Items 3 and 5 were rewritten by amendment r2 (2026-09-04) and
keep their numbers; item 15 is appended.

"Moved persona" is D1's definition throughout: a persona whose
`harness:` value differs between the implementing PR's base and head.

1. The implementing PR's diff of `config/deployments.yaml` changes only
   `harness:` values and comments; `git diff personas/` is empty; the
   PR body lists the moved personas and their before/after harnesses
   as read from that diff (D1).
2. `scripts/ci/sanitize_check.sh` passes with no new allowlist entry,
   and one comment immediately above `constraints:` in
   `config/deployments.yaml` records the resolved family behind each
   name in `constraints.distinct_model_families` and the rule that
   repinning one without the other is a violation (D2).
3. The D3 resolution is recorded as one `(name, harness, model,
   family, evidence)` row per name in
   `constraints.distinct_model_families`, read at the PR's head commit;
   the families are pairwise distinct; each family's evidence is the
   model's name as the vendor's own published model list spells it (for
   a harness alias, the vendor model the harness documents it as
   resolving to), and the same row appears in D2's comment above
   `constraints:`; and the diff introduces no prefix, substring or regex
   test over a model ID that yields a family (D3, amended r2). *Status
   recorded 2026-09-08: unmet on `main` — PR #133 recorded four-column
   rows and D2's comment carries no evidence; owed by the implement
   stage's follow-up PR under #44 before #44 closes (D3).*
4. For each moved persona, the model its new target carries equals
   `config/model_tiers.yaml`'s binding for its tier on its new
   harness; tree-wide, no `.agents/agents/*/agent.md` contains a line
   matching `^model:` (D4).
5. `scripts/sync_agents.py --check` and
   `scripts/ci/compiler_roundtrip.sh` pass; the commit's `--stat` lists
   `config/deployments.yaml` if any persona moved or if the D3 row of
   any name in `constraints.distinct_model_families` differs between
   base and head (on that second ground alone, the file's diff is D2's
   comment and nothing else), `config/model_tiers.yaml` if any tier was
   re-bound, and exactly the compiled targets those edits account for
   and nothing else — a moved persona accounting for its old-harness
   target's file set deleted and its new-harness target's file set
   added, a re-bound tier accounting for the model-bearing file
   (`model:` in `.claude/agents/<p>.md`; `.model` in
   `.agents/agents/<p>/agent.json`, with `agent.md` unchanged) changing
   in every target on that harness that binds that tier, sub-agent
   targets included (D5, amended r2).
6. `scripts/ops/smoke_launch.sh <scratch>` prints one
   `run N · <harness> · <persona>` banner per harness present in
   `config/deployments.yaml`, each persona being the one D7's selection
   rule yields; the script contains no persona name as a literal; and
   editing a pin in a scratch copy of `config/deployments.yaml` changes
   the banners with no edit to the script (D7).
7. Each arm's session reports a non-zero input token count and does not
   exit with an error status and zero tokens — the signature of an
   unrecognised `tools:` name (D6).
8. With a scratch `app_manifests.yaml` in which no persona pinned to
   some harness grants an observable's permission,
   `scripts/ops/smoke_launch.sh` exits 1 naming that harness and that
   permission and launches nothing; no `BLOCKED ON #47` line remains in
   the script (D14).
9. For each moved persona with no dispatchable rung: the hand-run
   launch line — the one `DRY_RUN=1 scripts/ops/work.sh` resolves at
   that commit — returns success with non-zero usage and a
   persona-loaded answer; and `work.sh <n> --as <that persona>` exits 2
   naming the stage's owners, with no harness in the message (D8, D15).
10. `docs/SPEC.md`'s `ops.dispatch` entry is upserted for the derived
    arms and the retired `#47` clause; `scripts/ci/spec_check.sh <base>`
    passes because the diff touches it, not because of a marker (D9).
11. A comment on #44 reports, per moved persona, before and after with
    cache hit rate and tokens-per-message and the per-model USD table
    for the priceable side, plus tokens with no USD column for the
    other; the baseline is named as a session list, not a date range;
    `runs/<date>_44-repin-cost/findings.md` carries a disposition
    footnote pointing at that comment (D10, D13).
12. `git diff CLAUDE.md` is empty; after the rebuild every `kind:
    subagent` source has a target for every harness, each carrying that
    harness's own tier resolution from `config/model_tiers.yaml` (D11).
13. Everything above lands in one pull request (D12).
14. `docs/SPEC.md`'s `config.bindings` entry states the re-pin property
    — a repin is a config edit plus the rebuild committed with it, no
    persona source changes, and the gates prove whatever configuration
    is present — and names no persona and no model (D9, clause (a);
    satisfied by the amendment r1 PR, not by the implementing PR).
15. With a scratch persona directory in which every persona pinned to
    some harness fails D7's clause (ii) — owns no stage any rung of
    `personas/lifecycle.json` labels — or its clause (iii) — declares
    no `authority.github_write` of the form `branch:<prefix>*` —
    `scripts/ops/smoke_launch.sh` exits 1 naming that harness and that
    clause's own reason, and launches nothing; and each selected arm's
    push ref is `<prefix>smoke-<issue>` derived from that persona's own
    glob, with no branch name of the script's invention (D7 as amended
    r2, D14).

## Out of scope

- **Choosing the pins.** They are the operator's, set directly in
  `config/deployments.yaml` and `config/model_tiers.yaml`. This spec
  does not propose, defend or record a pin; the implementing PR applies
  whatever is there and proves the properties above against it.
  *(Amended 2026-09-03: this item replaces three that argued specific
  choices — "Moving `athena` to antigravity", deferred "because plan and
  design are the highest-judgment stages"; "Repinning `argus`", called
  "a violation of #2 D4 unless `atlas` moves off antigravity in the same
  edit"; and #47's grant. The `argus`/`atlas` warning is not lost — it is
  D2's comment in `config/deployments.yaml`, quantified over whatever
  names the constraint lists, which is where the next editor will read
  it.)*
- **#6's automated reviewer-constraint check.** D3 is performed and
  recorded by hand until #6 lands; making it a build failure is #6's.
- **`config/execution.yaml` triggers and cadences.** Giving a persona a
  rung or a schedule belongs to #11 and #25 (whose D19 binds
  *placements*, not harnesses); a repin neither causes nor fixes a
  persona's undispatchability (D8).
- **Making `escalation_tier` reachable on a harness with no runtime
  model switch** (D16). It needs a `work.sh` or compiler change and an
  owner who needs it.
- **Pricing a second vendor's sessions in `session_spend.sh`.** D10
  works within the tool's single-vendor rate table rather than
  extending it; a cross-vendor pricer is a separate issue if the
  presenter wants one.

## Inputs

- `intent/43-harness-agnostic-launch/spec.md` D3, D5, D8, D9, D18, D19
  and PR #60 — the launch table, the per-harness target layout, the
  sidecar model, and the smoke test this issue re-points; also the
  amendment format this file follows.
- `intent/2-config/spec.md` D1–D4 — the three config axes, the
  vendor-string rule, sub-agents carrying no pin, and the two-reviewer
  constraint.
- `personas/lifecycle.json` — the ladder, and the statement that
  `intake`, `deploy` and `maintain` have no rung.
- `config/tools.yaml` — the capability→tool mapping and its inline
  record that an unrecognised tool name is a hard error (agy 1.1.25,
  #43 smoke run).
- `runs/2026-09-03_agy-headless/findings.md` Q1b, Q5, Q7 — the
  `model:` key voiding an agent, the `usage` object in the JSON output,
  and why identity is never checked with `gh api user`.
- `scripts/ops/session_spend.sh` header — the rate table, the
  `UNPRICED` behaviour, and the two numbers `--check` reports.
- `scripts/auth/app_manifests.yaml` — the per-persona App permissions
  D7's selection rule reads, and its header's record that `issues:
  write` is mandatory for every persona (#47, closed 2026-09-03).
- `docs/SPEC.md` `config.bindings`, `personas.compiler`, `ops.dispatch`
  — the property, the emitter, and the entry the implementing PR
  upserts.
- `personas/<persona>.yaml` `authority.github_write` — the branch
  surface D7 clause (iii) reads, and the glob the arm's push ref is
  derived from (added by amendment r2).
- PR #133 head `ab53c5b` and its round-1 reviews (Atlas AT-4, AT-5) —
  the implementation the amended D7 follows, and the live run that
  produced its differing case (added by amendment r2).
- `intent/44-repin-personas-to/plan.md` "Open questions for Athena"
  OQ-1 and OQ-2 — the two rulings amendment r2 records into D3 and D5.
- PR #135 round-1 review (Argus R1-1 to R1-5) and commit `11b88aa` on
  `main` — the pure `REVIEW` re-bind whose D2 comment refresh D5's
  corrected `--stat` rule accounts for (added 2026-09-08, in r2 before
  merge).
- #12 (tracker, Rung 2), #2, #6, #11, #25, #36, #43.
