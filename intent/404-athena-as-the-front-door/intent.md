# Intent: Athena as the front door: intake protocol, prior art, linking, decision lookup, README as the product story

**Issue:** #404 · **Stage:** plan · **Author:** athena (`evekhm-athena-app[bot]`) · **Status:** accepted on merge of this PR

## Problem

Athena was conceived as the product owner who owns the two gates where words become commitments (PLAN and DESIGN). In practice, Athena has functioned exclusively downstream on issues filed by a human or peer bot: drafting `intent.md` at PLAN from an existing issue, and drafting `spec.md` at DESIGN from an accepted intent. The front-door use case: a person interacts with Athena to shape a raw ask, search prior art, verify recorded decisions, file the issue, and maintain the product story. That use case has never run.

A systematic audit across 71 Athena pull requests, 13 sampled spec pull requests, and session run logs revealed five concrete operational gaps:

1. **No duplicate check before filing:** AGENTS.md prescribes running tracker searches before filing, but Athena has had no prompt instructions or mechanical checks to enforce this. The gap was demonstrated live when the operator's first front-door request duplicated #396 (filed 80 minutes earlier); manual search caught the duplicate, but the persona lacked the instruction to do so.
2. **Missing relationship taxonomy:** While Athena habitually references related issues by number in intent documents, she has lacked a formalized vocabulary (`absorbs`, `refines`, `depends on`, `supersedes`) in her prompt and issue template.
3. **No decision lookup before drafting:** Every `intent/*/spec.md` records numbered decisions (`#n Dm`), but there is no unified index or search command covering them. Consequently, seven cleanup issues (#288, #291, #295, #250, #293, #296, #390) were required to fix merged specs; duplicate decisions were written across intents (#391, where #267 D3 and #353 D4 duplicated the same rule); and established precedents were missed (#85 attempted to require cross-harness parity forbidden by #43 D16).
4. **Unowned product narrative:** `README.md` has lacked a persona owner and CI verification. As features and operational mechanisms land, the overarching product concept and user-facing walkthroughs drift without continuous maintenance.
5. **Unstructured intake dialogue:** The existing role text contained only a single vague clause ("brainstorm in the intake issue"), lacking turn limits, scoping structure, and read-back confirmation.

Furthermore, reviewers repeatedly identify self-contradictions between Athena's decisions and acceptance tests (#285, #346, #309), acceptance criteria that cannot fail (#335, #325), and rules needing repetitive manual re-issuance (landing rulings as numbered rules; adhering to prose bans). Finally, `personas/athena.yaml` limits `authority.paths` to `intent/**`, which prevents Athena from updating `README.md` and `INTENT.md`.

## Proposed outcome

Athena becomes the front door of the tracker and the keeper of the product story:

1. **Update `personas/athena.yaml`:**
   - Add `intake` to `stage: [intake, plan, design]`.
   - Update the `role` definition to specify:
     - The intake dialogue protocol: one question per turn, at most three rounds, read-back confirmation before filing.
     - Mandatory prior-art search across the tracker before drafting or filing.
     - Decision lookup across neighbour intents by stable ID (`#n Dm`).
     - Explicit relationship declarations (`absorbs`, `refines`, `depends on`, `supersedes`).
     - Ongoing ownership of `README.md` (concept and vision) and `INTENT.md` amendments.
     - Recording thread rulings as numbered decisions and citing reversals by name (`reverses #n Dm`).
     - Never open a second issue for a problem an open thread already owns.
   - Update `skills:` to the ordered list `intake-protocol.md, product-coherence.md, spec-adversary.md, trusted-posting.md, resume-protocol.md`.
   - The `intent/<issue>-<slug>/intent.md` section list the role text names gains Relationships and Non-goals: Problem, Proposed outcome, Affected users and systems, Constraints, Relationships, Open questions, Non-goals.

2. **Add two new policy skills under `personas/skills/`:**
   - `intake-protocol.md`:
     - Scope first, file last: one question per turn, maximum three rounds or repeating answers; the four scoping questions are who is affected, what changes for them, what stays out, and how anyone would know it worked; read-back confirmation before filing.
     - Search before writing: run tracker search across paths and keywords; inspect open threads for settled design.
     - Read neighbours' decisions: inspect Decisions tables in `intent/*/spec.md`, cite by `#n Dm`, and declare reversals explicitly; a silent contradiction is a defect.
     - Name every relationship: require a Relationships section with one verb per related item (`absorbs`, `refines`, `depends on`, `supersedes`), or state "tracker searched, no prior art:" followed by the labels and terms used.
     - One problem, one thread: post evidence to an existing open thread if the problem is already tracked; split oversized asks into parent and child items.
     - House shape: structure issues with Problem, Proposed outcome, Affected users and systems, Constraints, Relationships, Open questions, and Non-goals. Every section filled, or marked "none" with the reason.
     - Search again before PR: rerun tracker search immediately prior to opening the intent pull request.
     - Refusals: a second issue for a problem an open thread owns; an intent that touches a recorded decision without naming it; filing before the human confirmed the read-back (interactive), or while the body lacks a Relationships section (headless).
     - Exit condition: an issue labeled `intent:new` whose body carries the house shape and a Relationships section, or a comment on the existing thread and no new issue.
   - `product-coherence.md`:
     - Map surfaces before changing one: grep terms across `README.md`, `INTENT.md`, `REVIEW.md`, `docs/SPEC.md`, `config/`, and every `intent/*/spec.md` Decisions table; list every hit under Relationships or Constraints. That list is the change set the intent owes.
     - Keep `README.md` as concept and vision: update `README.md` in the same pull request as `intent.md` whenever product concept changes. Implementation status, run books and pins stay out of README; they belong to `docs/SPEC.md` and `config/`.
       - Mechanism: no check exists today that README changed when an intent changes the concept. Prompt rule now (this step); later a review-protocol row for the reviewers ("intent alters the README concept: README in the diff?").
     - Founding statements move by amendment: changes to founding decisions in `INTENT.md` land as dated amendments naming the amending intent, never as in-place edits.
     - Decisions reverse by name: reversals state `reverses #n Dm` with rationale; the reversed spec gains an amendment row pointing forward.
     - Apply rulings as rules: convert operator and advisor rulings into numbered rules for builders. Restating the intent in different words is a finding.
     - Prose that ships: no em dash character, no "rather than", no contrast sentences, no model or vendor names under `personas/**`, no home paths. Grep before opening the PR; every count is zero.
     - Exit condition: every surface named in the map-surfaces step either changed in the PR or is listed with the reason it did not.
   - Provision the missing `area:*` and `duplicate` labels in `scripts/setup/bootstrap_tracker.sh`.

3. **Amend `personas/skills/spec-adversary.md`:**
   - Rule 6 (Every acceptance row can fail): require naming the input that makes each acceptance test row fail; a row that passes either way is dropped or rewritten.
   - Rule 7 (Neighbours first): list decisions from related intents before round one; cite restatements and state reversals explicitly.
   - Rule 8 (Self-contradiction pass): read the Decisions table against the acceptance-test list once before opening the pull request, looking only for two rows a single input would satisfy differently.

4. **Expand `authority.paths`:**
   - Add `README.md` and `INTENT.md` to `personas/athena.yaml`'s `authority.paths`; today the merge gate refuses an Athena pull request touching either, so the README duty cannot be met without this.

5. **Enhance tracker search tooling:**
   - Add a `--decisions` pass to `scripts/ops/tracker_search.sh` that greps `| Dn |` rows across `intent/*/spec.md`, enabling unified search across issues, pull requests, and decisions in one invocation.

6. **Document interactive entry points in README:**
   - Update `README.md` under "Running it yourself" to document interactive entry points across supported harnesses (`claude --agent athena` on Claude Code; compiled `.agents/agents/athena` on Antigravity).

## Affected users and systems

- **Operator / Interactive Users:** Gains a guided intake partner who scopes raw requests interactively, prevents duplicates, and formats issues to house standards.
- **Autonomous Personas:** Benefit from consistent relationships, searchable decision history, and an aligned `README.md`.
- **Compiler (`scripts/sync_agents.py`):** Compiles personas with stage lists containing `intake` without requiring an entry on the lifecycle ladder.
- **Merge Gate (`scripts/ci/merge_gate.sh`):** Evaluates path authority for Athena pull requests touching `README.md` and `INTENT.md`.
- **Sanitization Gate (`scripts/ci/sanitize_check.sh`):** Validates that new persona role descriptions and skills remain vendor-neutral.
- **Search Tooling (`scripts/ops/tracker_search.sh`):** Gains `--decisions` query flag.

## Constraints

- **Vendor neutrality:** No vendor, model, or harness names under `personas/**` (checked by `scripts/ci/sanitize_check.sh`).
- **Skill naming conventions:** Filenames under `personas/skills/` must strictly match `^[a-z][a-z-]*\.md$`.
- **Drift gate integrity:** Compiled targets (`.claude/agents/`, `.agents/agents/`) must regenerate via `scripts/sync_agents.py` with zero drift.
- **Layering separation:** Prompt rules in persona skills serve as the first line; deterministic intake hooks (#117) and checkable hooks (#255) remain separate and complementary.

## Relationships

- **Refines #10 (headless intake on `intent:new`):** #10 automates the event trigger; this issue defines Athena's behavior once triggered, both interactively and headlessly.
- **Depends on nothing for the prompt change:** #117 (typed intake, status:implementing) is the deterministic layer under step 2 of the protocol.
- **Refines #35 (README walkthrough):** #35 authored the initial operator walkthrough; this issue establishes Athena as the ongoing owner and updater of `README.md`.
- **Related to #254 (evals) and #255 (hooks):** Rules established here define the requirements for future evals and checkable pre-commit hooks.
- **Related to #396:** the reviewer-pin loosening whose intent PR needs the README authority this issue grants Athena.
- **Absorbs missing label provisioning:** Provisions `area:*` and `duplicate` labels if not claimed by another active issue.

## Open questions

### Settled by Operator Rulings (2026-09-10)

1. **Compiler support for `intake`:** Settled. `scripts/sync_agents.py` already supports stages with no lifecycle rung by joining `personas/lifecycle.json` against persona `stage` lists (identical to Cassandra's `maintain` stage).
2. **Authority for `INTENT.md` amendments:** Settled. Athena drafts the amendment; operator merge of the intent pull request constitutes acceptance under standard single-reviewer review rules (#265). No countersign seat is required.

### Open Questions for DESIGN Stage (`spec.md`)

1. **Output format for `tracker_search.sh --decisions`:** Should decision search results be presented as raw grep matches, formatted markdown table rows, or structured JSON objects?
2. **Structure of dated amendments in `INTENT.md`:** Should amendments be collected in a dedicated `## Amendments` section at the bottom of `INTENT.md`, or placed inline within the relevant founding sections?

## Non-goals

- Implementation of issue forms and deterministic triage bot (#117).
- Implementation of automated evaluation suites (#254).
- Implementation of committed git hooks (#255).
- Building an indexed database or cache for decisions beyond the grep search pass.
