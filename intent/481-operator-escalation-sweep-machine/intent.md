# Intent: Operator escalation sweep: machine-readable queue for open questions, blocked runs, and ambiguous owners

**Issue:** #481 · **Stage:** plan · **Author:** athena (`evekhm-athena-app[bot]`) · **Status:** accepted on merge of this PR

## Problem

Autonomous dispatch halts at several well-defined boundaries:
1. The `refused:` circuit breaker in `scripts/ops/work_dispatch.sh` and `scripts/ops/work.sh` (refusing on `hold`, `blocked`, closed state, and `status:review-stuck`).
2. Headless runs halting on unresolvable tasks or judgment calls with `WORK-RESULT: blocked`.
3. Non-empty Open questions sections in `intent.md` and `spec.md` artifacts requiring operator resolution before gating.
4. Ambiguous-owner stalls where a stage has multiple persona owners (for example, `status:in-review` owned by both `argus` and `atlas`) but dispatch is invoked without `--as` or an active pull request, causing `work.sh` to print informational messages and exit 0 without work being launched or tracked.

Currently, these escalation signals exist only as unstructured prose buried inside file diffs, git commit logs, task output streams, or issue comment threads. No unified query mechanism allows an operator to inspect the backlog across issues to identify everything waiting on human decision. An operator managing unattended batches must manually review pull requests and issue threads one by one to detect stalled or blocked progress.

## Proposed outcome

1. **Machine-Readable Escalation Label (`status:needs-input`):**
   - Introduce `status:needs-input` into the repository label taxonomy.
   - Wire `status:needs-input` into the circuit breaker refusal logic in `scripts/ops/work_dispatch.sh` (refusal family) and `scripts/ops/work.sh` (refusal check alongside `status:review-stuck`).
   - Wire `status:needs-input` into `scripts/ops/claim.sh` refusal checks, preventing any session from claiming an escalated issue before input is supplied.
   - Wire `status:needs-input` into `scripts/placement/vm-local/poll.sh` candidate discovery, ensuring the continuous poller skips issues carrying this label.
   - To preserve the One Status Invariant (#4 D1: at most one `status:*` label per issue), applying `status:needs-input` displaces the current stage label (following #64 D9 and `scripts/ci/escalate.sh` displacing the stage label for `status:review-stuck`), recording the displaced stage in the structured marker. Clearing the escalation restores the displaced stage label.

2. **Structured Escalation Marker:**
   - Define a structured machine-readable marker:
     `ESCALATION: #<n> kind=<open-question|blocked|ambiguous-owner> stage=<stage>`
   - Emitted in the issue handoff comment (adjacent to `WORK-RESULT:`), allowing operators and automated sweeps to discover and classify escalations via `gh issue list --label status:needs-input` and parse markers without cloning branches.

3. **Unified `/escalations` Command Door:**
   - Add a canonical command source `commands/escalations.md` compiled via `scripts/sync_commands.py` into `.claude/commands/escalations.md` and `.agents/skills/escalations/SKILL.md`.
   - The `/escalations` command:
     - Queries all open issues carrying `status:needs-input`.
     - Parses the structured marker and issue details.
     - Presents each escalation item to the operator, including questions, context, and a proposed resolution with rationale.
     - Awaits operator approval or modification.
     - Records the operator decision (either as a numbered `D<n>` Decision in the artifact or as a structured ruling comment on the thread).
     - Removes `status:needs-input`, restores the displaced lifecycle stage label, and drops `in-progress` if held.

4. **One-Time Retrofit Migration Script:**
   - Deliver `scripts/ops/align_escalations.sh` to inspect existing open issues and pull requests for pre-existing escalation conditions (such as open intent/spec PRs with non-empty Open questions, stalled ambiguous-owner states, or `blocked` handoff comments).
   - Provides a dry-run mode reporting findings and an apply mode applying `status:needs-input` and emitting the structured marker, bringing existing backlog into the queue on day one.

5. **Living Spec and Governance Updates:**
   - Update `docs/SPEC.md` with capability entries for `status:needs-input`, `ESCALATION:`, the `/escalations` command, and circuit breaker extensions.

## Affected users and systems

- `scripts/ops/work_dispatch.sh` (circuit breaker refusal family).
- `scripts/ops/work.sh` (refusal ladder and multiple-owner handling).
- `scripts/ops/claim.sh` (refusal check before claim).
- `scripts/placement/vm-local/poll.sh` (skip condition for candidate discovery and PR filtering).
- `commands/escalations.md` (canonical command definition) and compiled targets in `.claude/commands/` and `.agents/skills/`.
- `scripts/sync_commands.py` (compiler roundtrip and drift gate).
- `scripts/ops/align_escalations.sh` (one-time retrofit alignment script).
- `docs/SPEC.md` (living spec capability upsert for escalation queue, label, marker, and command).
- Operators and persona sessions interacting with the escalation queue.

## Constraints

- **One Status Invariant (#4 D1):** At most one `status:*` label per issue at any time. When `status:needs-input` is applied, it displaces the active stage label and records it in the structured marker. When cleared, the displaced stage label is restored.
- **Fail-Closed Circuit Breaker (#36 D5, #441 D4):** `status:needs-input` joins the circuit breaker family. It halts dispatch and claim; it never weakens existing checks (`hold`, `blocked`, closed, `status:review-stuck`).
- **Harness Symmetry (#416 D1, D2):** The `/escalations` command must be authored once in `commands/escalations.md` and compiled identically for Claude Code and Antigravity via `scripts/sync_commands.py`.
- **Prose Standards:** No em dash characters, no contrast sentences, no model or vendor names under personas/**, no home paths.
- **Standard 5-Rung SDLC Lifecycle:** At the PLAN gate, only `intent/<issue>-<slug>/intent.md` is authored and committed. No code, command files, or scripts are edited in this PR. Living spec updates and script implementations belong to subsequent rungs.

## Relationships

- **refines #4** (D1, D10): Extends the label taxonomy with `status:needs-input` under the machine-driven escalation family while preserving the One Status Invariant (#4 D1).
- **refines #36** (D5): Adds `status:needs-input` to `work.sh` refusal checks alongside `status:review-stuck`.
- **refines #64** (D9, D10): Adopts the displaced-label swap pattern used by `scripts/ci/escalate.sh` for `status:review-stuck` and applies it to operator judgment escalations.
- **refines #87** / `claim.sh`: Adds `status:needs-input` to `claim.sh` refusal checks before any claim mutation.
- **refines #251** (D2, D4, D5): Updates `poll.sh` to treat `status:needs-input` as a candidate skip condition.
- **refines #404**: Formalizes the machine-readable escalation mechanism for Open questions surfacing at intake, PLAN, and DESIGN.
- **refines #416** (D1, D2): Adds `commands/escalations.md` to canonical command sources compiled by `scripts/sync_commands.py`.
- **refines #441** (D4): Extends `work_dispatch.sh` circuit breaker to refuse on `status:needs-input`.
- **absorbs #353**: Replaces manual ad-hoc escalation clearance procedures with a structured sweep workflow.
- **absorbs #354**: Replaces silent exit 0 ambiguous-owner stalls with explicit `kind=ambiguous-owner` escalations.
- **absorbs #361**: Provides standardized operator decision recording for stalled runs.
- **depends on #463**: Consistent slug derivation between `claim.sh` and `work.sh` ensures escalation markers match branch and folder paths.
- **Surface change audit:** Grepped `README.md`, `INTENT.md`, `REVIEW.md`, `docs/SPEC.md`, `config/`, and `intent/*/spec.md`. `README.md` and `INTENT.md` describe core concepts and vision which remain intact; detailed operational mechanisms belong to `docs/SPEC.md` upon implementation.

## Open questions

1. **Stage Label Preservation and Restoration**:
   When an issue is escalated with `status:needs-input`, how should the issue prior lifecycle stage be tracked and restored upon clearance?
   - Option A: Label Swap (matching #64 D9 and `escalate.sh`): Displace the current `status:<stage>` label and apply `status:needs-input` so that the One Status Invariant (#4 D1) is preserved. Record the displaced stage in the structured marker (`stage=<stage>`), and restore it when `/escalations` clears the escalation.
   - Option B: Auxiliary Non-Status Label: Name the label `needs-input` or `escalation:needs-input` outside the `status:*` prefix, allowing it to coexist with `status:<stage>` without violating #4 D1.
   - Differing case: An issue at `status:planning` hits an unanswerable open question. Under Option A, `status:planning` is removed and replaced by `status:needs-input`. Any tool querying `gh issue list --label status:planning` sees 0 results. Under Option B, the issue retains `status:planning` and gains `needs-input`; tools querying `status:planning` still find it unless explicitly updated to exclude `needs-input`.

2. **Decision Recording Channel for `/escalations`**:
   When `/escalations` resolves an escalation with an operator decision, how is the decision applied?
   - Option A: Direct Artifact Mutation: The `/escalations` command directly checks out the issue branch or worktree, appends the decision to the spec Decisions table as `D<n>`, commits, pushes, and removes `status:needs-input`.
   - Option B: Thread Ruling with Stage Handoff: The `/escalations` command posts a structured ruling comment (for example, `Decision: ...`) to the issue thread, clears `status:needs-input`, and restores the stage label so the owning persona consumes the ruling into the artifact on resume per AGENTS.md.
   - Differing case: If an issue at `status:spec` has an open question, under Option A `/escalations` directly commits to `athena/<issue>-<slug>`, requiring git credentials and branch write authority. Under Option B, `/escalations` only needs issue comment and label edit permissions, leaving artifact drafting to the stage-owning persona.

3. **Ambiguous Owner Resolution Behavior**:
   When `work.sh` encounters a stage with multiple owners (for example, `status:in-review` with `argus` and `atlas`) and no `--as` flag or active PR:
   - Option A: Immediate Escalation: `work.sh` automatically applies `status:needs-input` and posts `ESCALATION: #<n> kind=ambiguous-owner stage=<stage>` so the operator can pick the reviewer via `/escalations`.
   - Option B: Poller Multi-Dispatch: The poller dispatches both owners sequentially or in parallel, leaving `status:needs-input` for cases where manual human selection is strictly required.
   - Differing case: For automated review rungs under `vm-local/poll.sh`, Option A stops unattended execution and waits for human input, whereas Option B retains autonomous dual-review execution without human intervention.

4. **Alignment Script Scope and Idempotency**:
   How should the one-time alignment script (`scripts/ops/align_escalations.sh`) identify and retrofit legacy escalations?
   - Option A: Live Backlog Inspection: Scan open issues and PRs, parsing existing handoff comments for `WORK-RESULT: blocked` and open intent/spec PRs for non-empty Open questions, adding `status:needs-input` and posting structured `ESCALATION:` markers.
   - Option B: Dry-Run Audit Default: Provide a `--dry-run` flag by default that reports candidate issues without mutating labels or posting comments until an explicit `--apply` flag is passed.
   - Differing case: Running `align_escalations.sh` in CI or locally in audit mode inspects without mutating live GitHub tracker state under Option B, preventing unexpected notifications or state changes.

## Non-goals

- Not a general-purpose notification or push paging system. The escalation sweep is a pull-based tool run by the operator at checkpoints.
- Not a replacement or redesign of the stage and owner lifecycle model in `personas/lifecycle.json`. Ambiguous-owner resolution surfaces choices to the operator; it does not change persona ownership mappings.
- Not a replacement for the existing circuit breakers (`hold`, `blocked`, `status:review-stuck`). `status:needs-input` joins the circuit breaker family as an additional check.
