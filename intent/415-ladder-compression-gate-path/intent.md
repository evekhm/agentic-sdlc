# Intent: Owner-Authorized Ladder Compression Gate Path and Protocol

**Issue:** #415 · **Author:** athena (`evekhm-athena-app[bot]`) · **Status:** Draft

## Problem

Under the autonomous software development lifecycle (`AGENTS.md`, `personas/lifecycle.json`, `docs/SPEC.md`), issues progress through an ordered ladder of lifecycle stages:
1. `plan` (`status:planning`, artifact: `intent.md`, owner: Athena)
2. `design` (`status:spec`, artifact: `spec.md`, owner: Athena)
3. `build` (`status:build`, artifact: `plan.md`, owner: Daedalus)
4. `implement` (`status:implementing`, artifact: null / code, owner: Odyssey)
5. `review` (`status:in-review`, artifact: reviewer consensus verdicts, owners: Argus & Atlas)

The stage transition is driven by pull request merges: `lifecycle_advance.sh` observes merged artifacts on the default branch and mirrors the stage transition into the issue's labels. Unattended pull request merges are governed by `scripts/ci/merge_gate.sh`, which evaluates eleven conjuncts including artifact existence at `$HEAD` (conjunct 9) and strictly monotonic stage rank progression (conjunct 10).

### The Incident: PR #409 (Refs #407)

During the interactive development of issue #407 (adding `/idea` and `/bug` intake doors and a `/work` pre-dispatch digest), the design and implementation details were agreed upon directly between the repository owner and the builder in an interactive session. The repository owner explicitly directed immediate implementation.

To avoid redundant ceremony and round-trips for an owner-directed design, Odyssey opened PR #409 combining `intent`, `spec`, `plan`, and `implement` into a single compressed round. The pull request body explicitly declared:
> "This single PR combines intent/spec/plan/implement into one round because the given design in #407 was reached directly with the repository owner, who directed immediate implementation. This is an explicit, owner-authorized compression rather than an autonomous shortcut through the ladder. Refs #407"

PR #409 was verified by both independent reviewers (`argus` and `atlas`), achieved clean verdicts (`consensus:agreed`, `review:merge-ready`), passed all required CI checks, and was ready to merge (`mergeStateStatus: CLEAN`).

However, PR #409 remained unmerged for over 18 minutes because `scripts/ci/merge_gate.sh` failed on every run with:
```text
conjunct (9): false — expected exactly one intent/407-*/ folder at 7627557120c37407027fdef4330c3be018c1beac, found: none
```

### Root Causes

1. **Gate Rung Resolution Stalls on `intent:new` for Compressed Pull Requests**:
   In `scripts/ci/merge_gate.sh` (lines 424-434), the merge gate extracts the linked issue's status label:
   ```bash
   STATUS="$(grep '^status:' <<<"$ISSUE_LABELS" || true)"
   idx="$(rung_of "$STATUS")"
   if [ -z "$STATUS" ] && grep -Fxq "intent:new" <<<"$ISSUE_LABELS"; then
       idx=0
   fi
   ```
   Because issue #407 was created as a fresh intake issue, it carried only `intent:new` and no `status:*` label. The gate resolved `idx=0` (`status:planning`, rung 1, which owes artifact `intent.md`). Because PR #409 was a compressed code implementation, no `intent/407-*/intent.md` existed at `$HEAD`. Conjunct 9 therefore failed closed, preventing the PR from merging autonomously.

2. **Absence of Workflow Triggers on GitHub Label Writes**:
   When an operator manually corrected issue #407 by removing `intent:new` and adding `status:implementing`, conjunct 9 (`status:implementing owes no artifact`) and conjunct 10 (`rung 4 > highest merged rung 0`) became mathematically satisfied.
   
   However, `.github/workflows/merge-gate.yml` does not trigger on `labeled` events (neither `issues: [labeled]` nor `pull_request: [labeled]`). It triggers only on `check_suite: [completed]`, `status`, `issue_comment: [created]`, and `workflow_dispatch`. As a result, applying the label by hand did not wake up the merge gate; the PR remained stuck until the operator manually dispatched the workflow via `gh workflow run merge-gate.yml -f pull_request=409`.

3. **Missing SDLC Policy and Mechanized Authorization for Ladder Compression**:
   The repository currently has no written policy in `AGENTS.md` or `docs/SPEC.md` defining:
   - Whether and when owner-authorized ladder compression is permissible.
   - Who holds the authority to authorize compression (exclusively the human repository owner / maintainer).
   - How owner authorization must be declared, verified, and audited so that autonomous agents cannot unilaterally skip rungs.
   - What label state the issue must carry during a compressed round to satisfy `merge_gate.sh` and `lifecycle_advance.sh`.

## Proposed outcome

1. **Formalize Owner-Authorized Ladder Compression Policy**:
   - Codify in `AGENTS.md` and `docs/SPEC.md` that ladder compression (skipping intermediate artifact PRs to deliver code directly) is permissible **only** when explicitly authorized by the repository owner or an authorized human maintainer.
   - Establish a strict fail-closed boundary: autonomous agents (`odyssey`, `daedalus`, `athena`) are strictly forbidden from unilaterally self-authorizing ladder compression or opening compressed PRs without prior, verifiable owner authorization.

2. **Provide a Deterministic, Automatable Mechanism for Compressed Rounds**:
   Evaluate and adopt one of the following mechanisms (or a complementary combination) so that manual label hotfixing and manual workflow dispatches are eliminated:
   - **Mechanism A (Pre-Applied Target Status Label)**:
     - When the owner directs ladder compression on an issue, the operator or authorized intake mechanism applies the target status label (e.g. `status:implementing`) directly to the issue before the implementing PR is created, replacing `intent:new`.
     - When Odyssey opens the PR against the pre-labeled issue, the gate evaluates `STATUS="status:implementing"`, where `ARTIFACT=""`. Conjunct 9 (`status:implementing owes no artifact`) and conjunct 10 (`rung 4 > highest merged rung 0`) evaluate to true automatically.
     - PR checks and reviewer comments naturally trigger `merge-gate.yml`, allowing autonomous merge without manual intervention.
   - **Mechanism B (Authorized Maintainer Command Directive, e.g. `@themis compress status:implementing`)**:
     - Modeled after the maintainer retier directive in `scripts/ci/review_recorder.py` (`@argus retier <fid> <sev>`), an authorized human maintainer (`OWNER`, `MEMBER`, `COLLABORATOR`, non-bot) can post a command comment on the PR or issue:
       `@themis compress status:implementing`
     - Because `issue_comment: [created]` triggers `merge-gate.yml`, a step in the workflow verifies the author association, applies the status label via Themis, and evaluates `merge_gate.sh` in the same execution run.
   - **Mechanism C (PR Body Marker with Maintainer Verification)**:
     - The PR body contains a structured marker (e.g. `<!-- ladder-compression: status:implementing -->`).
     - `merge_gate.sh` verifies that the PR author is an authorized maintainer, or that an authorized maintainer has posted an approving comment or review.

3. **Address the Workflow Event Trigger Gap**:
   - Ensure that any post-creation adjustment to an issue or PR label can re-evaluate the merge gate without requiring manual `workflow_dispatch`.
   - Consider adding guarded `pull_request: [labeled]` or `issues: [labeled]` triggers to `.github/workflows/merge-gate.yml`, or standardizing a comment-driven re-gate trigger (e.g. `@themis gate`).

4. **Add Contract Test Coverage in `scripts/ci/tests/merge_gate_test.sh`**:
   - Add explicit test scenarios verifying:
     - An issue carrying pre-applied `status:implementing` with no intermediate `intent/` folder passes conjunct 9 (`status:implementing owes no artifact`) and conjunct 10 (`rung 4 > highest merged rung 0`), and merges cleanly when other conjuncts hold.
     - An uncompressed or unauthorized PR missing artifacts at `intent:new` continues to fail conjunct 9 fail-closed.
     - Loop ledger accounting and monotonicity invariants remain intact during compressed merges.

5. **Update Living Specifications**:
   - Update `docs/SPEC.md` and `AGENTS.md` to document the compression rules, verification constraints, and operational workflow.

## Affected users and systems

- **Repository Owner / Maintainers**: Gain a documented, reliable method to fast-track features or fixes without manual gate intervention.
- **Autonomous Builders (`odyssey`, `daedalus`)**: Can execute owner-authorized compressed tasks with clear labeling and declaration standards.
- **Autonomous Reviewers (`argus`, `atlas`)**: Review compressed pull requests with clear expectations regarding artifact requirements.
- **Themis Merge Gate (`scripts/ci/merge_gate.sh`, `.github/workflows/merge-gate.yml`)**: Evaluates compressed PRs autonomously without stalling on conjuncts 9/10.
- **Lifecycle Advancer (`scripts/ci/lifecycle_advance.sh`)**: Accurately records stage progression and advances issues upon merge of compressed PRs.
- **Contract Tests (`scripts/ci/tests/merge_gate_test.sh`)**: Protects against regressions in ladder compression and normal ladder gating.

## Constraints

- **Fail-Closed Security**: Autonomous bots must never possess unilateral authority to bypass the lifecycle ladder. Without authentic owner authorization, missing artifacts must always fail conjunct 9.
- **Preserve Monotonicity (D14 / Conjunct 10)**: Compression must move forward on the ladder; it must never permit backwards or circular stage regression.
- **Zero Inline Secrets & Credential Integrity**: Any label mutation or gate execution must adhere to repository trusted-posting disciplines, running under vetted steps with proper App tokens.
- **Deterministic and Reproducible**: The merge gate evaluation must remain fully deterministic and testable hermetically via local test fixtures.
- **Persona Role Boundary**: Athena authors only intent and spec artifacts (`intent/**`). Implementation of shell scripts, workflows, and tests belongs to Daedalus and Odyssey in downstream stages.

## Open questions

1. **Primary Authorization Mechanism**:
   Should the primary mechanism for owner-authorized ladder compression be:
   - (a) Operator pre-application of `status:implementing` on the issue prior to PR creation?
   - (b) A maintainer comment directive (e.g. `@themis compress status:implementing`) processed by the merge-gate workflow?
   - (c) A structured PR body marker verified by maintainer review or maintainer authorship?

2. **Workflow Trigger Extension**:
   Should `.github/workflows/merge-gate.yml` add `pull_request: [labeled]` (and/or `issues: [labeled]`) as an event trigger, or should we rely on comment events (`issue_comment: [created]`) to prevent unnecessary workflow concurrency?

3. **Post-Merge Stage Advance Behavior**:
   When PR #409 merged at `status:implementing`, did `lifecycle_advance.sh` cleanly advance #407 to `status:in-review`, and did it write the expected loop ledger row? Are any adjustments needed in `lifecycle_advance.sh` for multi-rung jumps?

4. **Intake Door Integration**:
   Should operator intake tools (such as `/work` or `/idea`) accept an explicit flag (e.g. `--stage implement`) when invoked by the repository owner to pre-set the target status label on issue creation?
