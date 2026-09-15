# Intent: Unify slug derivation across claim.sh and work.sh

**Issue:** #463 · **Stage:** plan · **Author:** athena (`evekhm-athena-app[bot]`) · **Status:** accepted on merge of this PR

## Problem

`scripts/ops/claim.sh` and `scripts/ops/work.sh` each carry their own `derive_slug` implementation, and the two disagree. A single issue title yields two different slugs:

- `claim.sh` (line 194): lowercases the entire title, replaces each run of characters outside `[a-z0-9]` with a dash (`-`), and caps at 40 characters at the last dash.
- `work.sh` (line 527): cuts the title at the first colon (`:`) or semicolon (`;`), lowercases the remainder, replaces each run of characters outside `[a-z0-9]` with a dash (`-`), and caps at 24 characters at the last dash. This matches the rule documented in `personas/skills/resume-protocol.md` (step 5) and `docs/SPEC.md` (`ops.dispatch`).

### Reproduction

Title of #457: `README: add a worked /idea, /claim, /work walkthrough`.

- `claim.sh 457` derives `readme-add-a-worked-idea-claim-work` and creates branch `<actor>/457-readme-add-a-worked-idea-claim-work` and the worktree of the same name.
- `work.sh 457` on a cold start (no `intent/457-*/` folder) derives `readme`, creating folder `intent/457-readme/` and branch `<actor>/457-readme`.

### Consequences

1. **Branch mismatch:** A session that claims by hand (`/claim <n>`) and subsequently hands the issue to the autonomous loop (`/work <n>`) receives a second branch for the same issue and stage, with the claim worktree pointing to the first branch.
2. **Cold-start folder mismatch:** `work.sh` reuses an existing `intent/<n>-*/` directory when exactly one exists (line 555). The disagreement remains hidden once an intent folder exists, but surfaces prior to the first artifact landing on the planning rung.
3. **Lifecycle stall:** On 2026-09-10 PR #371 (#337, implement rung) merged from `odyssey/337-poller-fix-round-queue-selects-prs-by-a` (the `claim.sh` 40-character form), while the dispatch branch expected by `intent/337-poller-fix-round-queue/` was `odyssey/337-poller-fix-round-queue`. The lifecycle advancer (run 34452022371) matched nothing and wrote no stage transition; the advisor advanced the rung manually (#337, advisor note 2026-09-10T07:55Z).
4. **Resume-protocol drift:** The resume protocol in `personas/skills/resume-protocol.md` specifies the 24-character colon-cut rule. `claim.sh` implements a divergent rule, so compiled personas and operator command doors compute different names for the same issue.

## Proposed outcome

Establish one canonical `derive_slug` function and one deterministic rule, shared across all entry points:

1. **Single shared implementation:** Extract `derive_slug` into a shared module (such as `scripts/ops/lib/slug.sh`) sourced by `scripts/ops/claim.sh`, `scripts/ops/work.sh`, and `scripts/ops/resolve_work_target.sh`.
2. **Deterministic rule consensus:** Settle on one canonical rule for slug length and prefix cutting. The spec stage will formalize whether the 24-character colon-cut rule or the 40-character whole-title rule survives.
3. **Reconciled test suites:** Update `scripts/ops/tests/claim_test.sh` and `scripts/ops/tests/work_test.sh` to execute the same test assertions against the shared helper.
4. **Safe transition handling:** Specify how existing branches and worktrees resolve so active issues avoid lifecycle stalls during the transition.

## Affected users and systems

- `scripts/ops/claim.sh`, `scripts/ops/work.sh`, `scripts/ops/resolve_work_target.sh`: All three operational scripts will source the unified implementation.
- `scripts/ops/tests/claim_test.sh`, `scripts/ops/tests/work_test.sh`: Both test suites will validate the unified slug derivation.
- `personas/skills/resume-protocol.md`: The resume protocol text will align with the shared implementation.
- `docs/SPEC.md`: Living documentation under `ops.claim` and `ops.dispatch` will document the unified derivation rules.
- Operators and autonomous personas: Eliminates branch divergence between manual `/claim` and automated `/work`.

## Constraints

- **Single source of truth:** One shared shell function defines slug derivation for all callers.
- **Deterministic string manipulation:** Slug derivation relies on deterministic bash text processing without external service calls.
- **Spec-bearing surfaces aligned:**
  - `README.md`: Concept and vision check complete; `README.md` documents the `intent/<issue>-<slug>/` folder shape without prescribing length caps; no edits required.
  - `INTENT.md`: Founding statements check complete; `INTENT.md` mandates one folder per change without binding slug length; no amendment required.
  - `REVIEW.md`: Review protocol is respected; no edits required.
  - `docs/SPEC.md`: Living specification updates are owed under `ops.claim` and `ops.dispatch` during implementation.

## Relationships

- **refines #36:** Extends #36 D6 and D8 (`work.sh` slug derivation and dry-run display) by establishing a single shared implementation across tools.
- **refines #87:** Reconciles `scripts/ops/claim.sh` slug derivation with repository dispatch rules.
- **absorbs #337:** Addresses the lifecycle advancement stall observed during PR #371 where branch slug mismatched the intent directory name.
- **refines #441:** Aligns `scripts/ops/resolve_work_target.sh` branch parsing with unified slug formatting.
- **refines #404:** Supports Athena front-door intake consistency and the resume protocol's step 5 standard.
- **tracker searched:** 2026-09-15 via `scripts/ops/tracker_search.sh --decisions slug` and `--decisions derive_slug`.

## Open questions

### For DESIGN stage (`spec.md`)

1. **Surviving slug derivation rule:** Which rule survives as the single canonical standard:
   - Option A: The 24-character colon-cut form specified by #36 D6, `docs/SPEC.md` (`ops.dispatch`), and `personas/skills/resume-protocol.md` (step 5).
   - Option B: The 40-character whole-title form implemented in `scripts/ops/claim.sh` (#87).
   Concrete case where they differ: Issue #457 titled `README: add a worked /idea, /claim, /work walkthrough`. Option A yields slug `readme` (cut at colon). Option B yields slug `readme-add-a-worked-idea-claim-work` (full title lowercased, capped at 40 characters).
2. **Transition and migration policy:** How should existing active worktrees and branches named under either rule be treated:
   - Option A: Retain existing worktrees as valid and accept both slug forms on read during transition.
   - Option B: Require manual or scripted migration of existing active worktrees.
   Concrete case where they differ: An active worktree created under the 40-character format resumed by a session expecting the 24-character format.
3. **Shared helper structure:** Where should the unified `derive_slug` function reside:
   - Option A: A dedicated lightweight library file `scripts/ops/lib/slug.sh`.
   - Option B: An addition to the existing `scripts/ops/lib/github.sh`.
   Concrete case where they differ: Sourcing `claim.sh` in hermetic test environments that isolate GitHub API functions.

## Non-goals

- Renaming existing branches, worktrees, or intent folders created prior to this change.
- Altering input arguments accepted by `work.sh` (#36 D7; an issue number remains the whole instruction).
- Modifying lifecycle stage ladder definitions or transitions in `personas/lifecycle.json`.
- Modifying pull-request resolution mechanics in `scripts/ops/lib/github.sh`.
