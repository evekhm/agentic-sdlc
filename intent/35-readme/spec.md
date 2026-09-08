# Spec: README operator walkthrough

**Issue:** #35 · **Status:** Approved (approval = merge of this PR) ·
**Author:** athena (`evekhm-athena-app[bot]`) ·
**Open questions:** none

The presenter directed that decisions be made, not posed back (#36,
"Presenter direction"; #35 claim comment). The two questions filed on
#35 land as D11 and D12. **Any row in this table can be overruled by
editing this file at the merge gate** — the merge is the acceptance,
so an edited row is the decision, not a comment asking for one.

## What is being built

```text
README.md        NEW: the only operator-facing document, at the repo root
docs/SPEC.md     docs.structure amended to name README's role (D13)
INTENT.md        layout line: README stops being "to come" (D13)
```

There is no `README.md` today (INTENT.md, "Repository layout
(target)", lists it as a flagship doc to come), so nothing is
replaced, migrated or deleted. This is the first version.

## Section list

These `##` sections, in this order (D2; the fixed count was lifted
2026-09-03, see D2/D4; the list was rewritten 2026-09-08 by the
product owner, see D1, and cut the same day to eight sections that
describe the system as designed: the actors, the flow, the
orchestrator, the harnesses, the playbook mapping, how to run it):

1. **What this is** — the two kinds of actors (persona, owner), the
   five rungs and what a merge means, the diagram, the self-building
   premise.
2. **The cast** — one line per persona and seat, the owner, the
   sub-agents, the tiers and their model bindings.
3. **The flow, rung by rung** — plan, design, build, implement,
   review, close and maintain in prose (D7), the deterministic
   transition, the halt labels and the defect path (D10).
4. **The orchestrator** — label in, merged code out; the one door
   `/work <n>`; the stop conditions; the self-improving loop.
5. **Two harnesses, two model families** — the concrete harnesses,
   pins, the reviewer family split, the cost thesis (D6).
6. **The playbook, and what this adds** — stages and plays, the
   mapping onto the rungs, the five additions.
7. **Running it yourself** — prerequisites (D11), who may file (D9),
   the one command (D5), what a merge means (D8).
8. **Where the rules live** — the document map (D3).

Every issue or pull request README cites is a link to its tracker
page (product owner, 2026-09-08). README describes the target design
and does not narrate build status; status lives in
`docs/CRITICAL_PATH.md` and the pinned tracker (product owner,
2026-09-08, second correction).

(#68 / PR #69 adds a read-only board section, "See who is doing what",
after 7 when it lands; that PR extends this list.)

## Decisions

| ID | Decision |
|----|----------|
| D1 | **One reader: a person arriving at the repository.** *Amended 2026-09-08 by the product owner: the reader is no longer "the operator at the keyboard" and README no longer opens by addressing them.* README introduces the system to anyone who lands on it — an attendee, an engineer evaluating the approach, the presenter — as a story of what the system is, what it demonstrates and how it is being built, and never an agent. Agents are pointed at AGENTS.md by their compiled prompts and must never be told to read README; a document with two audiences acquires two voices and then two truths. README describes the system as conceived, so seats and rungs that are agreed on the tracker but not yet built appear in it, each marked as such with its issue. *Amended again 2026-09-08 by the product owner: README describes the target design only. It does not say what is built today, what is open, or that a person merges today; the issue link on a part is its only status marker. Build status lives in `docs/CRITICAL_PATH.md` and the pinned tracker.* Testable: the opening does not address the reader by role, no sentence in the file instructs an agent, every seat or rung that lives on the tracker cites its issue, and the file contains no "today", "open" or "unbuilt" status narration. |
| D2 | **The section list above is ordered, and grows only by editing it.** *Amended 2026-09-03 by the product owner together with D4: the fixed count of nine is lifted.* Headings appear in the listed order and none is nested deeper than `###`; a new topic is either a link from the last section or a deliberate addition to the list above in the same change — never a drop-in section the list does not name, which is the mechanism that stops the welcome document from becoming a fourth standard (AGENTS.md, "No document sprawl"). Testable: every `## ` heading in README.md appears in the list above, in order. |
| D3 | **Explains, never duplicates; and loses every disagreement.** Every rule README mentions that is stated normatively elsewhere appears as at most one sentence plus a link to its owner: AGENTS.md (the cross-harness standard), INTENT.md (why the system exists), `docs/SPEC.md` (what is built today), REVIEW.md (the review protocol), `docs/CONTEXT.md` (prior art), `scripts/auth/README.md` and `scripts/setup/` (setup). README is normative for nothing and says so in one line: where it and any of those differ, the other wins (`docs.structure`). Testable: README contains no table (`grep -c '^|' README.md` is 0), no label-semantics list, and no severity-tier list; every rule sentence is followed by a link. *Amended 2026-09-08 by the product owner (#263 R1-1): the no-table test is narrowed to what it was guarding. A table README must never carry is a second rendering of a relation the repository owns normatively — the label ladder (`personas/lifecycle.json`), label semantics, the severity tiers (REVIEW.md) — because a second rendering is a second truth. The tier rate table D6(a) calls for is a read-out of the current bindings and their list rates, one row per tier, each cell owned by a file README links (`config/model_tiers.yaml`, `config/deployments.yaml`, `scripts/ops/session_spend.sh`). Staleness is its only failure mode, and D6 orders the refresh: `config/` first, README second. Exactly one such table is allowed and it lives in section 5. Testable now: `grep -c '^|---' README.md` is 1; every line matching `^|` lies between the section 5 heading and the section 6 heading; the file still contains no label-semantics list and no severity-tier list; every rule sentence is followed by a link.* |
| D4 | **At most one diagram.** *Superseded in part 2026-09-03 by the product owner: the original 150-line ceiling and 25-line section limit are lifted; no line or section-length cap applies.* Original rationale, kept for the record: a walkthrough an attendee will not finish is a transcript with a filename. Testable now: exactly one fenced diagram block. |
| D5 | **Exactly one command appears as an instruction: `/work <n>`, typed inside a harness session.** *Amended 2026-09-08 by the product owner: the instruction is the harness command. The product owner does not run `scripts/ops/work.sh` by hand (#89). The script is the command's implementation (#43 D16), and README may name it only in that role.* That is the whole typed input for every stage of every item (#36 D7, D8), so the walkthrough teaches one thing and cannot drift as stages change. Harness launch lines are *output* of the command (#36 D10) and never appear in README. Setup commands are not instructions here either — README links `scripts/auth/README.md` (D11). Testable: exactly two fenced blocks exist, the diagram (D4) and one whose only line is `/work <n>`; no fenced block contains `scripts/ops/work.sh`. |
| D6 | **Forbidden: home paths, per-persona procedure; vendor names allowed as concrete facts.** (a) *Amended 2026-09-08 by the product owner: the original ban on vendor, harness and model names in README is withdrawn. The product owner asked for the two harnesses and two model families to be concrete.* README may name the harnesses, the model families and the current tier bindings as facts of today, and each such statement points at the `config/` file that owns it (`config/deployments.yaml`, `config/model_tiers.yaml`). `config/` stays the only normative home; a model or harness change edits `config/` first and README second. `scripts/ci/sanitize_check.sh` enforces the vendor rule only inside `personas/**`, and that scope is unchanged. (b) No absolute home path and no credential shape — that part `sanitize_check.sh` does enforce on every tracked file, and it must pass. (c) No per-persona procedure text: how a persona claims, resolves its folder and hands off is the compiled resume protocol (#36 D3, D4). README names the stage, the actor and the artifact and stops. *Clarified 2026-09-08 by the product owner (#263 R1-2): "facts of today" names a property — the binding `config/` holds at the commit — and the `config/` link is the only currency marker README carries; the word "today" and its kin stay out of the file, per D1's second amendment.* |
| D7 | **The gate section is prose over the five rungs, not a rendering of the ladder.** For each of plan, design, build, implement, review, one short paragraph: which persona acts, which artifact lands in a PR, and — in words, not a mapping — that merging it moves the item to the next stage. The label ↔ stage ↔ artifact relation has exactly one machine-readable home, `personas/lifecycle.json` (#36 D1, D2); a second copy in prose would be the third. Testable: README names the five stages in ladder order and contains no `status:* → status:*` mapping. |
| D8 | **The merge is the acceptance, stated once and applied to every gate.** README says: a merged PR is the human product owner's acceptance of that artifact; a closed PR is a rejection and is not relitigated; and editing a Decision row in the PR *is* the decision — no comment asking for a change is needed. That is the single sentence that tells an operator what their one action means at all five gates. Testable: section 6 contains all three clauses and appears once in the file. |
| D9 | **The intake rule lives in the running section, with filing: anyone files, and the system files its own.** *Amended 2026-09-08 by the product owner: the original "humans file; personas do not file intake issues" is withdrawn — it contradicted the maintainer's charter (a 3σ proposal is an `intent:new` issue, #11) and the self-improving loop, in which the verifier and the advisor file every observed gap as a tracked issue that moves a rule into the repository ("one scar, one rule", docs/PLAYBOOK.md; "one scar, one rule, one eval", #254).* What survives of the #27/#28/#29 correction is narrower and applies to every filer: a reviewer keeps its findings on the pull request under review in that pull request's thread; and the tracker is searched before any filing (AGENTS.md, "Before filing an issue"). Every issue that enters the loop is opened with `intent:new` and no `status:*`, which is exactly what makes it stage `plan` to a cold session (#36 D4). Testable: the running section states that the system files its own issues and names the maintainer's watchers and the loop's failures as sources, states the reviewer-findings rule and links AGENTS.md. *Amended 2026-09-08 by the product owner (#263 R1-3): the `intent:new` clause may be carried by the diagram; section 7 need not repeat it.* |
| D10 | **The defect path states only what is ratified, and points at its owner for the rest.** *Amended 2026-09-03 by the product owner once #32 was ratified: the re-entry rule is now settled, so README states it in one sentence, cites #32, and links its normative home, INTENT.md "Defect repair".* README's section 11 carries the halt behaviour already in the spec: `hold` halts all automation absolutely while present, `blocked` stops and reports, more than one `status:*` is corrupted state, and `review:3` escalates to `status:review-stuck` (`lifecycle.labels`, `review.policy`). The ratified repair path (#32): a repair whose `docs/SPEC.md` entry is unchanged skips the intent/spec/plan triple — issue, fix PR with a regression check, review, human merge — and a spec-changing repair re-enters at plan. Original rationale, kept for the record: while the route was open, a guessed route in the attendee's first document was worse than a named gap. Testable: the defect section states both halves of the ratified rule, cites #32 and links INTENT.md. |
| D11 | **Take-home setup stays out of README (#35 OQ1).** Section 2 names the three prerequisites in one sentence each — a clone, the six App private keys, `gh` and `jq` — and links `scripts/auth/README.md` and `scripts/setup/`. Those instructions are already written and exercised where the scripts live; a second copy at the root would drift the first time an App is re-registered, and D3 forbids it. Testable: README contains no App-registration or label-provisioning step, only links. |
| D12 | **README is built before the workshop, not the live-demo change (#35 OQ2).** It is the attendee's entry point and must exist when the session opens; making the map also the demo is one failure away from a session with no map. It still walks the full loop — this intent, this spec, then the README PR — so the presenter can point at its own `intent/35-readme/` folder as a worked example, which is the demo value without the risk. The live-demo change is chosen separately and is not scoped here. |
| D13 | **The implementing PR owes two documentation edits.** `docs/SPEC.md` `docs.structure` is amended to name README.md as the operator-facing entry point: its audience (D1), that it explains and never duplicates and loses every disagreement (D3), and its bounds (D2, D4). No new capability ID — README joins the existing document-map entry. INTENT.md's layout line is corrected so README is no longer "to come" (REVIEW.md already landed, so that half of the annotation goes too). README.md is not a behaviour-bearing path, so `scripts/ci/spec_check.sh` will not force this; it is owed regardless, per AGENTS.md, "The living spec". Testable: the PR diff touches `docs/SPEC.md` and `INTENT.md`, and `docs.structure` names README. |
| D14 | **Ordering against #36 is a hard dependency, both ways.** This planning PR is branched from `athena/36-dispatch` and merges *after* #36's planning PR. The README implementing PR merges *after* #36's implementing PR, because `scripts/ops/work.sh` — the one command in D5 — and the two-reviewer dispatch in D5/section 7 do not exist until then. If #36 is overruled at its gate, this spec's D5 and D7 are re-opened before README is written. Testable: `scripts/ops/work.sh` exists at the README PR's base commit, and the README PR body cites #36's implementing PR. |
| D15 | **The ladder is walked in full — no bootstrap compression.** Unlike #36, this change has no cross-cutting rebuild forcing one PR: PLAN and DESIGN land here, BUILD produces `plan.md` normally, and the README lands in its own implementing PR. The chain of small PRs on one issue is itself the artifact section 5 describes, so compressing it would cost the walkthrough its own worked example (intent/1-personas/spec.md D10 is not invoked). |

## Acceptance

- `README.md` exists at the repository root; every `## ` heading
  appears in D2's list, in order, with no `####` (D2, count cap lifted
  2026-09-03).
- Exactly one fenced diagram block (D4; the line and section-length
  caps were lifted 2026-09-03).
- Exactly one markdown table: `grep -c '^|---' README.md` is 1 and
  every line matching `^|` falls between the section 5 and section 6
  headings (D3, amended 2026-09-08). README contains no per-label
  semantics (except the halt labels required by D10), no severity-tier list, and no `status:*` → `status:*`
  mapping; it names all five stages in ladder order (D3, D7).
- Exactly one fenced command block exists and its only line is
  `/work <n>`; no fenced block contains `scripts/ops/work.sh` (D5).
  Harness, vendor and model names appear only as facts of the current
  bindings and each points at the `config/` file that owns it (D6,
  amended 2026-09-08).
- `bash scripts/ci/sanitize_check.sh` exits 0 with README tracked, and
  README contains no absolute home path (D6).
- Section 7 states that anyone files and the system files its own
  issues (the maintainer's watchers, the loop's failures), that a
  reviewer's findings on the PR under review stay in that thread, and
  links AGENTS.md; the diagram or section 7 states that every issue
  starts `intent:new` with no `status:*` (D9; carrier widened to the
  diagram 2026-09-08 by the product owner, #263 R1-3). (Section
  numbers in this list follow the eight-section list of 2026-09-08.)
- Section 7 states all three clauses: merge is acceptance, a closed PR
  is a rejection not relitigated, and an edit at the gate is the
  decision (D8).
- Sections 2 and 5 describe two independent reviewers on different
  model families and name which family each reads on, pointing at
  `config/deployments.yaml` (D6).
- Section 3 states the ratified repair path (spec-unchanged repair
  skips the triple; spec-changing repair re-enters at plan), cites #32
  and links INTENT.md (D10).
- Section 8 links AGENTS.md, INTENT.md, `docs/SPEC.md`, REVIEW.md and
  `docs/CONTEXT.md`, one sentence each, and states that README loses
  any disagreement with them (D3).
- README contains no build-status narration: `grep -n -i -E
  '\btoday\b|unbuilt|is open|not yet' README.md` matches nothing (D1,
  second amendment).
- Every `#<n>` in README is a markdown link to that issue or pull
  request on the tracker; `grep -E '(^|[^/[])#[0-9]+' README.md`
  matches nothing.
- The same PR amends `docs/SPEC.md` `docs.structure` to name README
  and corrects INTENT.md's layout line (D13).
- The README PR's base contains `scripts/ops/work.sh` (D14).
