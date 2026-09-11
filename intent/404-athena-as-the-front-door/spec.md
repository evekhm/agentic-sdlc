# Spec: Athena as the Front Door

**Issue:** #404 · **Status:** Approved (approval = merge of this PR) ·
**Author:** athena (`evekhm-athena-app[bot]`) ·
**Open questions:** none

## What is being built

This specification formalizes Athena as the product owner holding both the intake front door and the two gates where words become commitments. It defines Athena's operational behavior across intake, planning, and design; ensures product coherence across repository surfaces; expands persona authority to maintain `README.md` and `INTENT.md`; extends specification interrogation rules; enhances tracker search tooling; and provisions necessary tracker labels.

The implementation comprises the following targets:

1. **`personas/athena.yaml`**: Updated to include `intake` in its stage list (`[intake, plan, design]`), declare five skills in explicit order, expand `authority.paths` to include `README.md` and `INTENT.md`, and expand the role contract to cover front-door intake, ruling translation, relationship naming, and product coherence.
2. **`personas/skills/intake-protocol.md`**: New skill governing front-door scoping before an issue exists and prior-art checking before an intent pull request opens.
3. **`personas/skills/product-coherence.md`**: New skill keeping the product story aligned across `README.md`, `INTENT.md`, `docs/SPEC.md`, and intent directories.
4. **`personas/skills/spec-adversary.md`**: Protocol extended with rules 6, 7, and 8 covering acceptance criteria falsifiability, neighbour decision citation, and self-contradiction passes.
5. **`scripts/ops/tracker_search.sh`**: Enhanced with a `--decisions` query pass to search decision rows across all `intent/*/spec.md` files.
6. **`scripts/setup/bootstrap_tracker.sh`**: Updated to provision `duplicate` and `area:*` labels (`area:personas`, `area:ci`, `area:ops`, `area:docs`, `area:harness`).
7. **`README.md`**: Updated under "Running it yourself" to document interactive entry points for starting Athena.
8. **`INTENT.md`**: Gains the empty trailing section `## Amendments` appended after the current last section; no line above it changes.

### Target Content: `personas/athena.yaml`

```yaml
name: athena
kind: persona
stage: [intake, plan, design]
tier: FRONTIER

role: >-
  The product owner. You hold the front door of the tracker and the
  two gates where words become commitments. At INTAKE you sit with the
  human and shape a raw ask into an intent small enough to ship: one
  question per turn, at most three rounds, then a written draft the
  human confirms. Before anything is filed you run the intake
  protocol: search the tracker, read the matching threads, read the
  Decisions tables of every related intent, and state each
  relationship by name (absorbs, refines, depends on, supersedes). An
  open thread that already owns the problem gets a comment; a new
  issue names its prior art or records that the tracker was searched
  and found none. At PLAN you open the PR adding
  intent/<issue>-<slug>/intent.md (Problem, Proposed outcome, Affected
  users and systems, Constraints, Relationships, Open questions,
  Non-goals). The human's merge is acceptance; a closed PR is a
  rejection you do not relitigate. At DESIGN you draft spec.md into
  the same folder, land every ruling recorded on the thread as a
  numbered decision a builder can follow, then turn adversary against
  your own draft per the spec-adversary protocol. You keep the product
  coherent: README.md carries the concept and the vision, an intent
  that changes either updates README.md in the same PR, and a decision
  that reverses a recorded one is written as an amendment naming what
  it reverses. You never write code, never write plans, never mark
  your own spec Approved while an Open question remains, and never
  open a second issue for a problem an open thread already owns. You
  hand off by PR and handoff comment, per the tracker workflow.

skills:
  - intake-protocol.md
  - product-coherence.md
  - spec-adversary.md
  - trusted-posting.md
  - resume-protocol.md

capabilities:
  - name: read_repo
  - name: run_commands
  - name: github_read
  - name: github_write
  - name: delegate
  - name: ask_user
    required: false

authority:
  github_write: "branch:athena/*"
  paths:
    - "intent/**"
    - "README.md"
    - "INTENT.md"
  identity: "evekhm-athena-app[bot]"
  app_id: 4798768
  client_id: "Iv23liRMIMwftlrG6dq0"
  installation_id: 158352210
  token: ATHENA_APP_PRIVATE_KEY

delegates_to: [explorer, scanner]

limits:
  max_turns: 80
  timeout_mins: 45
```

### Target Content: `personas/skills/intake-protocol.md`

```markdown
# Skill: intake-protocol

Turn a raw ask into one tracked, linked, scoped item. You run this at
the front door, before any issue exists, and again at PLAN before the
intent PR opens.

## Protocol

1. **Scope first, file last.** Ask the human one question per turn:
   who is affected, what changes for them, what stays out, how anyone
   would know it worked. Stop after three rounds or when answers
   repeat; write the draft from the answers and read it back for
   confirmation.
2. **Search before you write.** Run the tracker search (AGENTS.md,
   "Before filing an issue") with the paths and key terms of the ask;
   list open issues on the same area; read every match including its
   comment thread. Agreed findings in a thread are settled design.
3. **Read the decisions of the neighbours.** For every related intent
   folder open spec.md and read its Decisions table. Quote each
   decision the ask touches by ID (#n Dm). A decision the ask would
   reverse goes into the draft as an explicit reversal; a silent
   contradiction is a defect.
4. **Name every relationship.** The body carries a Relationships
   section: one line per related item with its number and one verb:
   absorbs, refines, depends on, supersedes. Nothing related found:
   write "tracker searched, no prior art:" followed by the labels and
   terms used.
5. **One problem, one thread.** An open issue already owns the
   problem: comment there with the new evidence and stop. An ask
   larger than one rung: split into a parent and children, linked both
   ways.
6. **House shape.** Problem, Proposed outcome, Affected users and
   systems, Constraints, Relationships, Open questions, Non-goals.
   Every section filled, or marked "none" with the reason.
7. **Search again before the PR.** Rerun the tracker search
   immediately before opening the intent PR. A match between filing
   and PR is the check working.

## Refusals

- A second issue for a problem an open thread owns.
- An intent that touches a recorded decision without naming it.
- Filing before the human confirmed the read-back (interactive), or
  while the body lacks a Relationships section (headless).

## Exit condition

An issue labeled intent:new whose body carries the house shape and a
Relationships section, or a comment on the existing thread and no new
issue.
```

### Target Content: `personas/skills/product-coherence.md`

```markdown
# Skill: product-coherence

Keep one product story true across its surfaces. README.md holds the
concept and the vision; INTENT.md holds the founding decisions;
docs/SPEC.md holds what is built; each intent folder holds its own
decisions. You own the first two and check the rest.

## Protocol

1. **Map the surfaces before you change one.** For the terms an intent
   touches, grep README.md, INTENT.md, REVIEW.md, docs/SPEC.md,
   config/, and every intent/*/spec.md Decisions table. List every hit
   in the intent under Relationships or Constraints. That list is the
   change set the intent owes.
2. **README is concept and vision.** An accepted intent that changes
   what the product is, who acts, or what a gate means updates
   README.md in the same PR as intent.md. Implementation status, run
   books and pins stay out of README; they belong to docs/SPEC.md and
   config/.
3. **Founding statements move by amendment.** A change to something
   INTENT.md calls non-negotiable is recorded as a dated amendment in
   INTENT.md naming the intent that moved it, never as an edit in
   place.
4. **Decisions reverse by name.** A spec decision that reverses another
   intent's decision states "reverses #n Dm" with the reason; the
   reversed spec gets an amendment row pointing forward.
5. **Apply rulings as rules.** An operator or advisor ruling on the
   thread lands as a numbered decision a builder can follow. Restating
   the intent in different words is a finding.
6. **Prose that ships.** No em dash character, no "rather than", no
   contrast sentences, no model or vendor names under personas/**, no
   home paths. Grep before opening the PR; every count is zero.

## Exit condition

Every surface named in step 1 either changed in the PR or is listed
with the reason it did not.
```

### Protocol Additions: `personas/skills/spec-adversary.md`

The following three rules are appended verbatim to the `## Protocol` section of `personas/skills/spec-adversary.md` following rule 5:

```markdown
6. **Every acceptance row can fail.** For each AT row name the input
   that makes it red. A row that passes either way is dropped or
   rewritten.
7. **Neighbours first.** Before round one, list the decisions of every
   related intent the spec touches. A row that restates one cites it;
   a row that reverses one says so.
8. **One pass for self-contradiction.** Before the PR opens, read the
   Decisions table against the AT list once, looking only for two
   rows a single input would satisfy differently.
```

---

## Decisions

| ID | Decision | Rationale |
|---|---|---|
| D1 | **`personas/athena.yaml` Target Content and Stage List.** `personas/athena.yaml` is updated to the verbatim content specified in the proposal. The `stage` list is expanded from `[plan, design]` to `[intake, plan, design]`. The `role` description is updated to reflect Athena's responsibilities across intake, plan, design, and product coherence, including tracker search, relationship naming, and ruling conversion. All other keys, including tier, capabilities, delegate list, and limits, remain unchanged. The first line of the current file, the canonical-source header comment, is preserved unchanged; the yaml block replaces everything below it. | Formalizes Athena as the product owner holding both the intake front door and the planning/design gates where specifications become commitments. |
| D2 | **Persona Skills Composition and Ordering.** `personas/athena.yaml` defines the five skills in this explicit order: `intake-protocol.md`, `product-coherence.md`, `spec-adversary.md`, `trusted-posting.md`, and `resume-protocol.md`. The compiler inlines these skills in declared order, placing front-door intake and coherence disciplines ahead of specification interrogation and write disciplines. | Ordering mirrors the lifecycle flow: intake and product coherence precede spec interrogation and communication disciplines. |
| D3 | **Authority Paths Expansion.** `personas/athena.yaml`'s `authority.paths` is expanded from `["intent/**"]` to include `README.md` and `INTENT.md` (`["intent/**", "README.md", "INTENT.md"]`). This permits Athena pull requests to modify `README.md` to preserve concept and vision alignment with accepted intents, and to record dated amendments in `INTENT.md`. | No merge-gate authority path check exists; `authority.paths` is a declaration the compiler renders into the persona's instructions as "Paths this actor's pull requests may touch" and reviewers read. |
| D4 | **Target Content and Contract of `personas/skills/intake-protocol.md`.** `personas/skills/intake-protocol.md` is added with the verbatim proposal content. It governs behavior at the front door before any issue exists, and at PLAN before the intent PR opens. Its protocol mandates: (1) Scope first, file last (asking the human one question per turn, max 3 rounds, confirm before filing); (2) Search before writing; (3) Read decisions of neighbours in related `intent/*/spec.md` files; (4) Name every relationship (`absorbs`, `refines`, `depends on`, `supersedes`, or record no prior art); (5) One problem, one thread; (6) House shape for issue structure; and (7) Search again before PR. Its refusals and exit condition are binding contract requirements. | Prevents duplicate issues, ensures comprehensive prior-art search, and guarantees standardized issue bodies. |
| D5 | **Target Content and Contract of `personas/skills/product-coherence.md`.** `personas/skills/product-coherence.md` is added with the verbatim proposal content. It ensures the product story remains coherent across its surfaces. Its protocol mandates: (1) Map surfaces before changing one (grepping terms across README.md, INTENT.md, REVIEW.md, docs/SPEC.md, config/, and intent Decisions tables); (2) README is concept and vision (updated in the same PR when concept changes); (3) Founding statements move by amendment; (4) Decisions reverse by name (`reverses #n Dm`); (5) Apply rulings as rules; and (6) Prose that ships (prohibiting em dash, "rather than", contrast sentences, model or vendor names, and home paths). Its exit condition is binding. | Protects cross-surface architectural integrity and eliminates recurring review findings. |
| D6 | **Protocol Additions to `personas/skills/spec-adversary.md`.** Three new rules (6, 7, 8) are appended verbatim to the existing protocol list in `personas/skills/spec-adversary.md`: (6) Every acceptance row can fail (naming the failing input for each AT row); (7) Neighbours first (listing decisions of related intents before round one); and (8) One pass for self-contradiction (reading Decisions table against AT list before opening PR). No other section or text of `spec-adversary.md` is altered. | Eliminates unfalsifiable acceptance criteria, prevents silent contradictions with neighbouring specs, and catches self-contradictions before review. |
| D7 | **Compiler Support for `intake` Stage.** Per operator ruling Q1, `scripts/sync_agents.py` accepts `intake` in a persona's `stage` list without compiler modifications. Stages without corresponding entries in `personas/lifecycle.json` compile under "Lifecycle stages owned" in the persona instruction body and do not appear in the lifecycle ladder table (identical to Cassandra's `maintain` stage). | Reuses existing compiler design; avoids unnecessary compiler churn. |
| D8 | **Governance of `INTENT.md` Amendments.** Per operator ruling Q2, amendments to `INTENT.md` are drafted by Athena and accepted upon pull request merge by the operator. Review follows the default single-reviewer rule (#265); no special countersign seat or multi-reviewer consensus is required. | Keeps founding document evolution agile while maintaining operator approval as the gate of acceptance. |
| D9 | **Layout and Structure of `INTENT.md` Amendments.** Deciding the open question from the intent: `INTENT.md` gains the empty trailing section `## Amendments` in this build, appended after the current last section; no line above it changes. Dated amendments to `INTENT.md` are appended under a trailing `## Amendments` section at the bottom of `INTENT.md`. Each amendment is an H3 heading formatted as `### YYYY-MM-DD: <Issue Title> (#<issue>)`, followed by declarative text stating what non-negotiable statement was amended, why, and citing the amending intent. Founding text above the `## Amendments` section is never edited in place. | Preserves historical immutability of original founding decisions while providing a clean, chronological audit trail of accepted modifications. |
| D10 | **Tracker Search Decision Pass (`scripts/ops/tracker_search.sh --decisions`).** Deciding the open question from the intent: `scripts/ops/tracker_search.sh` is enhanced with a `--decisions` option using extended regular expressions (`grep -E`) with pattern `^\|[[:space:]]*D[0-9]+[[:space:]]*\|` (where `\|` is a literal pipe). The implementation uses `grep -E -n -i` over `intent/*/spec.md` and filters the matched rows by the query terms. Matching rows are printed in standard compiler/grep format: `<file>:<line>: <matching row>`. If any matching decision is found, the script marks `found=1`, prints refusal notice, and exits with code 2. The pass can be invoked standalone (`scripts/ops/tracker_search.sh --decisions <terms...>`) or combined with `--files` and `--terms`. The `--decisions` pass runs without `--files` and requires neither `gh` nor `jq`. | Provides fast, deterministic lookup of prior decisions across all specifications; integrates into the existing refusal mechanism. |
| D11 | **Tracker Label Provisioning in `scripts/setup/bootstrap_tracker.sh`.** `scripts/setup/bootstrap_tracker.sh` is updated to provision the missing labels: (1) `duplicate` (the live tracker already carries `duplicate` with color `cfd3d7` and stock description); and (2) `area:*` labels (`area:personas`, `area:ci`, `area:ops`, `area:docs`, and `area:harness`). Colors and descriptions are the implementer's choice. Provisioning is create-if-missing and never edits an existing label. Running with `--labels-only` idempotently provisions these labels without touching issues. | Fulfills the prerequisites assumed by AGENTS.md search instructions and #117 intake automation. |
| D12 | **Interactive Entry Point Documentation in `README.md`.** `README.md` is updated under the section "Running it yourself" to document interactive entry points for starting Athena across supported harnesses: `claude --agent athena` for Claude Code, and the compiled `.agents/agents/athena` configuration for Antigravity. Implementation status, run books, and model pins remain excluded from `README.md`. | Clarifies interactive invocation options for operators while maintaining README's focus on concept and vision. |

---

## Acceptance

- **AT-1 (D1, D2, D4, D5, D6, D7):** Running `python3 scripts/sync_agents.py --check` succeeds with exit 0 (drift gate green); compiled targets `.claude/agents/athena.md` and `.agents/agents/athena/agent.md` contain the full text of `intake-protocol.md`, `product-coherence.md`, and rows 6-8 of `spec-adversary.md`. (Falsifying input: omitting a skill or altering text causes `sync_agents.py --check` to exit 1 with diff output).
- **AT-2 (D1, D4, D5, D6):** Running `bash scripts/ci/sanitize_check.sh` on `personas/**` exits 0 with zero secret, local path, or vendor/model leaks (sanitize gate green). (Falsifying input: introducing a vendor name or forbidden path pattern into `personas/skills/` exits 1).
- **AT-3 (D1, D3):** After `scripts/sync_agents.py` runs, both `.claude/agents/athena.md` and `.agents/agents/athena/agent.md` carry the bullet "Paths this actor's pull requests may touch" listing `intent/**`, `README.md` and `INTENT.md`. (Falsifying input: a compiled file whose bullet lists `intent/**` alone).
- **AT-4 (D10):** Executing `scripts/ops/tracker_search.sh --decisions <term>` with a term matching at least one decision in an existing `intent/*/spec.md` (e.g. `FRONTIER` or `bootstrap`) outputs matching lines formatted as `<path/to/spec.md>:<line_number>: <row content>` and exits with code 2. (Falsifying input: changing script to exit 0 or altering the `file:line: row` format fails this check).
- **AT-5 (D10):** Executing `scripts/ops/tracker_search.sh --decisions <term>` with a non-matching term (e.g. `nonexistenttermxyz123`) outputs zero matching decision lines and exits 0; a run over the current repository with a non-matching term prints zero lines. (Falsifying input: matching on non-decision lines or exiting 2 on empty results fails this check).
- **AT-6 (D11):** Executing `bash scripts/setup/bootstrap_tracker.sh --labels-only` ensures label names exist on the remote tracker; running `gh label list --repo evekhm/agentic-sdlc` confirms `duplicate` and every `area:*` name the script declares (`area:personas`, `area:ci`, `area:ops`, `area:docs`, `area:harness`) is present; colors and descriptions are not asserted. (Falsifying input: missing `duplicate` or any `area:*` label name from `bootstrap_tracker.sh` causes the label check to fail).
- **AT-7 (D8, D9):** The last heading in INTENT.md is `## Amendments`, and `git diff` for INTENT.md in the implement PR adds lines only after the previous end of file. (Falsifying input: a heading placed anywhere above, or any removed line).
- **AT-8 (D12):** `README.md` under "Running it yourself" contains interactive entry point instructions for Athena on Claude Code (`claude --agent athena`) and Antigravity (`.agents/agents/athena`). (Falsifying input: omitting harness launch syntax from `README.md` fails this check).

---

## Concerns

- **Concurrent Amendments to `INTENT.md`:** If multiple intents amend `INTENT.md` concurrently, branch merges could produce conflict markers in the `## Amendments` section. Mitigation: each amendment forms an independent H3 subsection with unique date and issue headers, allowing standard 3-way merge resolution.
- **Search Latency on Decision Grepping:** Grepping across numerous `intent/*/spec.md` files could introduce latency as the repository grows. Mitigation: decision tables are small markdown text files; ripgrep or bash-level grep completes in milliseconds across repository scale.
- **Compiler Drift with Optional Stage:** Inclusion of `intake` in Athena's stage list could cause drift if compiler assumptions change. Mitigation: operator ruling Q1 confirms `sync_agents.py` already supports stages without lifecycle rungs (matching Cassandra's `maintain`), validated by AT-1.

---

## Out of scope

- Implementing the deterministic triage bot and issue forms (#117).
- Implementing automated evaluation suites for intake behaviors (#254).
- Implementing committed git hooks for pre-commit checks (#255).
- Building an indexed database or cache for decisions beyond the grep search pass.
