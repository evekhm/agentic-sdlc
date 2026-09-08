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
product owner, see D1, from an operator walkthrough into an
introduction to the system — what it is, what it demonstrates, how it
was and is being built, and what it adds to the playbook):

1. **What this repository is** — the story of one change through the
   loop, the diagram, and the self-building premise.
2. **The goal: an orchestrator with a YOLO switch** — the end state
   (labeling an issue is the entire human act), the three seats that
   make it trustworthy (advisor, verifier, maintainer), and the
   tracker items that are the pieces of the switch.
3. **The playbook, and what this adds to it** — the six-stage loop as
   the article states it, and the five additions this repository
   makes on top of it.
4. **The loop, stage by stage** — plan, design, build, implement,
   review and maintain in prose (D7), the deterministic transition,
   the halt labels and the defect path (D10).
5. **The cast** — the personas built and the seats agreed, the
   sub-agents, tiers, the compiler.
6. **Distrust is structural** — the mechanisms that hold without
   anyone's attention, and the field notes they came from.
7. **How it built itself, and where it stands** — the bootstrap
   ladder, the critical-path gates, and today's position between YOLO
   off and on.
8. **What it costs, and how we know** — the cost discipline and the
   measurement subsystem, built and agreed.
9. **Running it yourself** — prerequisites (D11), who may file (D9),
   the one command (D5), what a merge means (D8).
10. **Where the rules actually live** — the document map (D3).

Every issue or pull request README cites is a link to its tracker
page, not a bare number (product owner, 2026-09-08).

(#68 / PR #69 adds a read-only board section, "See who is doing what",
after 9 when it lands; that PR extends this list.)

## Decisions

| ID | Decision |
|----|----------|
| D1 | **One reader: a person arriving at the repository.** *Amended 2026-09-08 by the product owner: the reader is no longer "the operator at the keyboard" and README no longer opens by addressing them.* README introduces the system to anyone who lands on it — an attendee, an engineer evaluating the approach, the presenter — as a story of what the system is, what it demonstrates and how it is being built, and never an agent. Agents are pointed at AGENTS.md by their compiled prompts and must never be told to read README; a document with two audiences acquires two voices and then two truths. README describes the system as conceived, so seats and rungs that are agreed on the tracker but not yet built appear in it, each marked as such with its issue. Testable: the opening does not address the reader by role, no sentence in the file instructs an agent, and every capability README names as not yet built cites an issue. |
| D2 | **The section list above is ordered, and grows only by editing it.** *Amended 2026-09-03 by the product owner together with D4: the fixed count of nine is lifted.* Headings appear in the listed order and none is nested deeper than `###`; a new topic is either a link from the last section or a deliberate addition to the list above in the same change — never a drop-in section the list does not name, which is the mechanism that stops the welcome document from becoming a fourth standard (AGENTS.md, "No document sprawl"). Testable: every `## ` heading in README.md appears in the list above, in order. |
| D3 | **Explains, never duplicates; and loses every disagreement.** Every rule README mentions that is stated normatively elsewhere appears as at most one sentence plus a link to its owner: AGENTS.md (the cross-harness standard), INTENT.md (why the system exists), `docs/SPEC.md` (what is built today), REVIEW.md (the review protocol), `docs/CONTEXT.md` (prior art), `scripts/auth/README.md` and `scripts/setup/` (setup). README is normative for nothing and says so in one line: where it and any of those differ, the other wins (`docs.structure`). Testable: README contains no table (`grep -c '^|' README.md` is 0), no label-semantics list, and no severity-tier list; every rule sentence is followed by a link. |
| D4 | **At most one diagram.** *Superseded in part 2026-09-03 by the product owner: the original 150-line ceiling and 25-line section limit are lifted; no line or section-length cap applies.* Original rationale, kept for the record: a walkthrough an attendee will not finish is a transcript with a filename. Testable now: exactly one fenced diagram block. |
| D5 | **Exactly one command appears as an instruction: `/work <n>`, typed inside a harness session.** *Amended 2026-09-08 by the product owner: the instruction is the harness command, never the shell script. The product owner does not run `scripts/ops/work.sh` by hand (#89); the script is the command's implementation (#43 D16) and README may name it only as such, never as something to type.* That is the whole typed input for every stage of every item (#36 D7, D8), so the walkthrough teaches one thing and cannot drift as stages change. Harness launch lines are *output* of the command (#36 D10) and never appear in README. Setup commands are not instructions here either — README links `scripts/auth/README.md` (D11). Testable: exactly two fenced blocks exist, the diagram (D4) and one whose only line is `/work <n>`; no fenced block contains `scripts/ops/work.sh`. |
| D6 | **Forbidden: vendor names, home paths, per-persona procedure.** (a) No vendor, product, harness or model-family name and no model ID anywhere — the reviewers are "two different model families" and which family is a `config/` fact (`review.policy`, #2 D4). This is stricter than CI on purpose: `scripts/ci/sanitize_check.sh` enforces the vendor rule only inside `personas/**`, so README's compliance is a merge-gate reading, not a green check. (b) No absolute home path and no credential shape — that part `sanitize_check.sh` does enforce on every tracked file, and it must pass. (c) No per-persona procedure text: how a persona claims, resolves its folder and hands off is the compiled resume protocol (#36 D3, D4). README names the stage, the actor and the artifact and stops. |
| D7 | **The gate section is prose over the five rungs, not a rendering of the ladder.** For each of plan, design, build, implement, review, one short paragraph: which persona acts, which artifact lands in a PR, and — in words, not a mapping — that merging it moves the item to the next stage. The label ↔ stage ↔ artifact relation has exactly one machine-readable home, `personas/lifecycle.json` (#36 D1, D2); a second copy in prose would be the third. Testable: README names the five stages in ladder order and contains no `status:* → status:*` mapping. |
| D8 | **The merge is the acceptance, stated once and applied to every gate.** README says: a merged PR is the human product owner's acceptance of that artifact; a closed PR is a rejection and is not relitigated; and editing a Decision row in the PR *is* the decision — no comment asking for a change is needed. That is the single sentence that tells an operator what their one action means at all five gates. Testable: section 6 contains all three clauses and appears once in the file. |
| D9 | **The intake rule lives in section 3, with filing, and names Atlas.** Humans file; personas do not file intake issues — Atlas in particular, whose sidecar findings belong in the PR thread, never as new issues (this is the correction for #27/#28/#29). Every issue that enters the loop is opened with `intent:new` and no `status:*`, which is exactly what makes it stage `plan` to a cold session (#36 D4). It sits in the filing section rather than a trailing section because it is a rule about filing and an operator reads it at the moment they would break it; AGENTS.md, "Before filing an issue", is the link. Testable: section 3 states both clauses and links AGENTS.md. |
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
- `grep -c '^|' README.md` is 0; README contains no per-label
  semantics (except the halt labels required by D10), no severity-tier list, and no `status:*` → `status:*`
  mapping; it names all five stages in ladder order (D3, D7).
- Exactly one fenced command block exists and its only line is
  `/work <n>`; no fenced block contains `scripts/ops/work.sh`; no
  harness executable, vendor, product, model-family name or model ID
  appears anywhere in the file (D5, D6).
- `bash scripts/ci/sanitize_check.sh` exits 0 with README tracked, and
  README contains no absolute home path (D6).
- Section 9 states that humans file, that no persona — Atlas included
  — files intake issues, and that every issue starts `intent:new` with
  no `status:*`; it links AGENTS.md (D9). (Section numbers in this
  list follow the 2026-09-08 section list.)
- Section 9 states all three clauses: merge is acceptance, a closed PR
  is a rejection not relitigated, and an edit at the gate is the
  decision (D8).
- Sections 3 and 5 describe two independent reviewers on different
  model families without naming either family, and section 9 states
  the manual path as running the one command on the PR number, which
  launches neither reviewer without a named persona (#36 D9).
- Section 4 states the ratified repair path (spec-unchanged repair
  skips the triple; spec-changing repair re-enters at plan), cites #32
  and links INTENT.md (D10).
- Section 10 links AGENTS.md, INTENT.md, `docs/SPEC.md`, REVIEW.md and
  `docs/CONTEXT.md`, one sentence each, and states that README loses
  any disagreement with them (D3).
- Every `#<n>` in README is a markdown link to that issue or pull
  request on the tracker; `grep -E '(^|[^/[])#[0-9]+' README.md`
  matches nothing.
- The same PR amends `docs/SPEC.md` `docs.structure` to name README
  and corrects INTENT.md's layout line (D13).
- The README PR's base contains `scripts/ops/work.sh` (D14).
