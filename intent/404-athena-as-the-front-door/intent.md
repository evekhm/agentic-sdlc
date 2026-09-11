# Intent: Athena as the front door: intake protocol, prior art, linking, decision lookup, README as the product story

**Issue:** #404 · **Stage:** plan · **Author:** athena (`evekhm-athena-app[bot]`) · **Status:** accepted on merge of this PR

## Problem

Athena was conceived as the product owner who owns the two gates where words become commitments (PLAN and DESIGN). In practice, Athena has functioned exclusively downstream on issues filed by a human or peer bot: drafting `intent.md` at PLAN from an existing issue, and drafting `spec.md` at DESIGN from an accepted intent. The front-door use case -- where a person interacts with Athena to shape a raw ask, search prior art, verify recorded decisions, file the issue, and maintain the product story -- has never run.

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
   - Expand `authority.paths` to include `README.md` and `INTENT.md`.

2. **Add two new policy skills under `personas/skills/`:**
   - `intake-protocol.md`:
     - Scope first, file last: one question per turn, maximum three rounds or repeating answers, read-back confirmation before filing.
     - Search before writing: run tracker search across paths and keywords; inspect open threads for settled design.
     - Read neighbours' decisions: inspect Decisions tables in `intent/*/spec.md`, cite by `#n Dm`, and declare reversals explicitly.
     - Name every relationship: require a Relationships section with one verb per related item (`absorbs`, `refines`, `depends on`, `supersedes`), or state "tracker searched, no prior art:" followed by search terms.
     - One problem, one thread: post evidence to an existing open thread if the problem is already tracked; split oversized asks into parent and child items.
     - House shape: structure issues with Problem, Proposed outcome, Affected users and systems, Constraints, Relationships, Open questions, and Non-goals.
     - Search again before PR: rerun tracker search immediately prior to opening the intent pull request.
     - Document explicit refusals and exit conditions.
   - `product-coherence.md`:
     - Map surfaces before changing one: grep terms across `README.md`, `INTENT.md`, `REVIEW.md`, `docs/SPEC.md`, `config/`, and every `intent/*/spec.md` Decisions table.
     - Keep `README.md` as concept and vision: update `README.md` in the same pull request as `intent.md` whenever product concept changes. Implementation status belongs in `docs/SPEC.md`.
     - Founding statements move by amendment: changes to founding decisions in `INTENT.md` land as dated amendments naming the amending intent, never as in-place edits.
     - Decisions reverse by name: reversals state `reverses #n Dm` with rationale; the reversed spec gains an amendment row pointing forward.
     - Apply rulings as rules: convert operator and advisor rulings into numbered rules for builders.
     - Prose that ships: enforce prose standards (no em dash character, no comparative exclusion phrasing, vendor neutrality in persona files, no absolute home directory paths).
     - Document explicit exit conditions.

3. **Amend `personas/skills/spec-adversary.md`:**
   - Rule 6 (Every acceptance row can fail): require naming the input that makes each acceptance test row fail; drop rows that pass unconditionally.
   - Rule 7 (Neighbours first): list decisions from related intents before round one; cite restatements and state reversals explicitly.
   - Rule 8 (Self-contradiction pass): read the Decisions table against acceptance tests once before opening the pull request to catch conflicting conditions.

4. **Enhance tracker search tooling:**
   - Add a `--decisions` pass to `scripts/ops/tracker_search.sh` that greps `| Dn |` rows across `intent/*/spec.md`, enabling unified search across issues, pull requests, and decisions in one invocation.

5. **Document interactive entry points in README:**
   - Update `README.md` under "Running it yourself" to document interactive entry points across supported harnesses (`claude --agent athena` on Claude Code; compiled `.agents/agents/athena` on Antigravity).

6. **Tracker label provisioning:**
   - Provision missing `area:*` and `duplicate` labels in tracker setup tooling to support intake categorization and duplicate resolution.

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
- **Lifecycle phase boundary:** At the PLAN gate, only `intent/<issue>-<slug>/intent.md` is authored and committed. Persona updates, skill files, and code changes are executed during the IMPLEMENT stage following approved spec and plan artifacts.

## Relationships

- **Refines #10 (headless intake on `intent:new`):** #10 automates the event trigger; this issue defines Athena's behavior once triggered, both interactively and headlessly.
- **Depends on: none (for prompt and skill changes):** #117 (typed intake, status:implementing) provides the complementary deterministic hook layer.
- **Refines #35 (README walkthrough):** #35 authored the initial operator walkthrough; this issue establishes Athena as the ongoing owner and updater of `README.md`.
- **Related to #254 (evals) and #255 (hooks):** Rules established here define the requirements for future evals and checkable pre-commit hooks.
- **Absorbs missing label provisioning:** Provisions `area:*` and `duplicate` labels if not claimed by another active issue.

## Open questions

### Settled by Operator Rulings (2026-09-10)

1. **Compiler support for `intake`:** Settled. `scripts/sync_agents.py` already supports stages with no lifecycle rung by joining `personas/lifecycle.json` against persona `stage` lists (identical to Cassandra's `maintain` stage).
2. **Authority for `INTENT.md` amendments:** Settled. Athena drafts the amendment; operator merge of the intent pull request constitutes acceptance under standard single-reviewer review rules (#265). No countersign seat is required.

### Open Questions for DESIGN Stage (`spec.md`)

1. **Output format for `tracker_search.sh --decisions`:** Should decision search results be presented as raw grep matches, formatted markdown table rows, or structured JSON objects?
2. **Structure of dated amendments in `INTENT.md`:** Should amendments be collected in a dedicated `## Amendments` section at the bottom of `INTENT.md`, or placed inline within the relevant founding sections?
3. **Spec-adversary protocol structure:** Should rules 6, 7, and 8 be appended sequentially to `personas/skills/spec-adversary.md`, or organized into explicit phases (pre-adversary context assembly, adversary interrogation, post-adversary self-contradiction check)?
4. **Provisioning mechanism for missing labels:** Should `area:*` and `duplicate` labels be provisioned directly via `scripts/setup/bootstrap_tracker.sh`, or via a standalone tracker configuration step?

## Non-goals

- Implementation of issue forms and deterministic triage bot (#117).
- Implementation of automated evaluation suites (#254).
- Implementation of committed git hooks (#255).
- Building an indexed database or cache for decisions beyond the grep search pass.
