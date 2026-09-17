# Spec: Operator Escalation Sweep Machine

**Issue:** #481 · **Status:** Approved (approval = merge of this PR) · **Author:** athena (`evekhm-athena-app[bot]`) · **Open questions:** none

## What is being built

This specification defines a machine-readable escalation queue and sweep mechanism for unattended and autonomous dispatch. When execution halts at an unresolvable boundary (an open question requiring human judgment, a blocked headless run, or an ambiguous stage owner in unattended mode), the system marks the issue with `status:needs-input` and emits a structured machine-readable marker. The displaced lifecycle stage label is preserved and restored upon clearance. An operator sweep command (`/escalations`) and an alignment script (`scripts/ops/align_escalations.sh`) provide visibility across the backlog, present escalations and stalled resources, and record operator rulings.

### Core Capabilities

1. **Escalation Label (`status:needs-input`):**
   - Added to repository label taxonomy in `scripts/setup/bootstrap_tracker.sh` with color `#E11D21` (matching the escalation hue family).
   - Preserves the One Status Invariant (#4 D1): at most one `status:*` label is present on an issue at any time. Applying `status:needs-input` displaces the active lifecycle stage label (`status:planning`, `status:spec`, `status:build`, or `status:implementing`).
   - The displaced stage is recorded in the structured marker (`stage=<stage>`). Clearing the escalation removes `status:needs-input` and restores the displaced stage label.

2. **Circuit Breaker Integration:**
   - `status:needs-input` joins the circuit breaker refusal family alongside `hold`, closed state, `status:review-stuck`, and `blocked`.
   - `scripts/ops/work_dispatch.sh` checks for `status:needs-input` after `status:review-stuck` and before claim evaluation, exiting 2 with `work_dispatch.sh: refused: #<n> carries status:needs-input`.
   - `scripts/ops/work.sh` checks for `status:needs-input` under step (c) of its refusal ladder, exiting 2 with `refused: <label_side> carries status:needs-input`.
   - `scripts/ops/claim.sh` checks for `status:needs-input` and `status:review-stuck` before any mutation, exiting 2 with `refused: #<n> carries status:needs-input`.
   - `commands/work.md` documents `status:needs-input` as part of the circuit breaker refusal conditions.

3. **Candidate Filtering in the Continuous Poller (`poll.sh`):**
   - `scripts/placement/vm-local/poll.sh` checks tracking issue labels during pull request candidate filtering. Pull requests whose tracking issue carries `status:needs-input` are skipped, logging `poll.sh: skipping PR #<pr> (tracking issue #<issue> carries status:needs-input)`.
   - Displaced lifecycle issues carrying `status:needs-input` are naturally excluded from ladder candidate discovery (`ladder_labels`).

4. **Structured Escalation Marker Grammar:**
   - Emitted in the issue handoff comment adjacent to `WORK-RESULT:` using the format:
     `ESCALATION: #<n> kind=<open-question|blocked|ambiguous-owner> stage=<stage>`
   - Permitted `kind` values: `open-question`, `blocked`, `ambiguous-owner`.
   - Permitted `stage` values: `intake`, `plan`, `design`, `build`, `implement`, `review`.

5. **Ambiguous Owner Escalation in Headless Dispatch (`work.sh`):**
   - Interactive mode: `scripts/ops/work.sh` prints the owner list and exits 0 with instructions to specify `--as <persona>`.
   - Unattended mode (`HEADLESS=1`): `scripts/ops/work.sh` applies `status:needs-input`, posts an issue comment containing `ESCALATION: #<n> kind=ambiguous-owner stage=<stage>`, and exits 2 with `WORK-RESULT: blocked #<n> ambiguous owner for stage <stage>`.

6. **Unified `/escalations` Command Door:**
   - Authored in `commands/escalations.md` and compiled via `scripts/sync_commands.py` into `.claude/commands/escalations.md` and `.agents/skills/escalations/SKILL.md`.
   - Queries open issues carrying `status:needs-input`, parses structured markers, presents each escalation to the operator, and solicits an operator decision.
   - Records the decision as a structured comment on the thread (`Decision: <ruling>`), clears `status:needs-input`, restores the displaced stage label, and releases `in-progress` if held.
   - Inspects and reports stalled loop resources (dead claims, residue branches with zero unique commits against main, consensus-agreed unmerged PRs), providing loop visibility for Gate H / H4. Automated reaping remains owned by #483.

7. **Retrofit Alignment Script (`scripts/ops/align_escalations.sh`):**
   - Standalone script supporting audit mode by default (`--dry-run`) to inspect open issues and PRs without mutations.
   - Supports mutation mode (`--apply`) to apply `status:needs-input` and emit the structured `ESCALATION:` marker for qualifying candidate issues.

### Manifest of Files Touched by the Implementation Rung

- `scripts/setup/bootstrap_tracker.sh`: add `status:needs-input` label definition.
- `scripts/ops/work_dispatch.sh`: add `status:needs-input` to circuit breaker refusal family.
- `scripts/ops/work.sh`: add `status:needs-input` to refusal ladder; in headless mode, escalate ambiguous-owner stall with `status:needs-input` and marker.
- `scripts/ops/claim.sh`: add `status:needs-input` and `status:review-stuck` to refusal ladder.
- `scripts/placement/vm-local/poll.sh`: add `status:needs-input` to PR candidate filtering.
- `commands/work.md`: document `status:needs-input` in circuit breaker refusal text.
- `commands/escalations.md`: canonical command definition for `/escalations`.
- `.claude/commands/work.md`, `.claude/commands/escalations.md`, `.agents/skills/work/SKILL.md`, `.agents/skills/escalations/SKILL.md`: compiled targets from `scripts/sync_commands.py`.
- `scripts/ops/align_escalations.sh`: standalone escalation sweep and alignment script.
- `scripts/ops/tests/work_dispatch_test.sh`, `scripts/ops/tests/claim_test.sh`, `scripts/ci/tests/escalation_queue_test.sh`: regression and contract tests.
- `docs/SPEC.md`: living spec updates for escalation queue, label, marker, and command.
- `CHANGELOG.md`: document the new escalation queue and `/escalations` door.

### Manifest of Files Touched by this PR (Athena)

- `intent/481-operator-escalation-sweep-machine/spec.md`: this specification.

### Forbidden Files (Untouched)

- `.github/workflows/**`: GitHub Actions workflow files are preserved unchanged.
- `personas/**`: Persona definitions and instructions are preserved unchanged.
- `config/**`: Execution configurations and harness pins are preserved unchanged.
- `scripts/ci/review_recorder.py`: Consensus ledger derivation is preserved unchanged.
- `scripts/ci/merge_gate.sh`: Merge gate conjuncts are preserved unchanged.

## Relationships

- **refines #4** (D1): Extends the label taxonomy with `status:needs-input` under the machine-driven escalation family while preserving the One Status Invariant (at most one `status:*` label per issue).
- **refines #36** (D5, D7): Adds `status:needs-input` to `work.sh` refusal checks and preserves the single-number CLI interface.
- **refines #64** (D9, D10): Adopts the displaced-label swap pattern used by `scripts/ci/escalate.sh` for `status:review-stuck` and applies it to `status:needs-input`.
- **refines #87** (`claim.sh`): Adds `status:needs-input` and `status:review-stuck` to `claim.sh` refusal checks before any claim mutation.
- **refines #251** (D5): Updates `poll.sh` to treat `status:needs-input` as a candidate skip condition. Reconciles tension with Decision #251 D4 by establishing that `kind=<...>` is an issue-level queue classification for operator judgment, distinct from installation-time runner credential error codes.
- **absorbs #354**: Replaces silent exit 0 ambiguous-owner stalls in headless dispatch with explicit `status:needs-input` escalation and `kind=ambiguous-owner` markers.
- **refines #404**: Formalizes the machine-readable escalation mechanism for open questions surfaced at intake, plan, and design rungs.
- **refines #416** (D1, D2): Adds `commands/escalations.md` to canonical command sources compiled by `scripts/sync_commands.py`.
- **refines #441** (D3, D4): Extends `work_dispatch.sh` circuit breaker to refuse on `status:needs-input` and cites Decision #441 D3 for dispatch delegation and D4 for guided circuit breaker enforcement.
- **depends on #463**: Aligns slug derivation between `claim.sh` and `work.sh` ensuring consistent issue and branch identification.
- **complements #483**: Provides the operator sweep view for escalated and stalled loop resources, while resource reaping and automated remediation remain with #483.

## Decisions

| ID | Decision | Rationale |
|---|---|---|
| **D1** | **Label taxonomy and displacement semantics (`status:needs-input`).** `status:needs-input` joins the label taxonomy in `scripts/setup/bootstrap_tracker.sh` with color `#E11D21` (matching the escalation hue family). In accordance with Decision #4 D1, at most one `status:*` label is present on an issue at any time. When `status:needs-input` is applied, it displaces the active lifecycle stage label (`status:planning`, `status:spec`, `status:build`, or `status:implementing`). The displaced stage is recorded in the structured marker (`stage=<stage>`). When cleared, `status:needs-input` is removed and the displaced stage label is restored. | *Adversary analysis:* Two defensible readings: (1) Introduce an auxiliary label such as `needs-input` outside `status:*` so both labels coexist; (2) Use `status:needs-input` and displace the active stage label per Decision #64 D9 and `scripts/ci/escalate.sh`. Differing case: An issue at `status:planning` hits an unresolvable question. Under Reading 1, `status:planning` remains on the issue; automation querying `gh issue list --label status:planning` still matches it unless patched across every script, violating fail-closed safety. Under Reading 2, `status:planning` is removed, so standard stage queries automatically exclude it without requiring queries across every script to be updated. Reading 2 is adopted. |
| **D2** | **Circuit breaker integration across dispatch, execution, and claim.** `status:needs-input` joins the circuit breaker refusal family. In `scripts/ops/work_dispatch.sh`, it is checked immediately after `status:review-stuck` and before claim evaluation, exiting 2 with `work_dispatch.sh: refused: #<n> carries status:needs-input`. In `scripts/ops/work.sh`, it is checked under refusal step (c), exiting 2 with `refused: <label_side> carries status:needs-input`. In `scripts/ops/claim.sh`, it is checked alongside `status:review-stuck` before any mutation, exiting 2 with `refused: #<n> carries status:needs-input`. In `commands/work.md` (and compiled targets), the circuit breaker documentation lists `status:needs-input`. | *Adversary analysis:* Two defensible readings: (1) Enforce refusal solely at the dispatch layer in `work_dispatch.sh`; (2) Enforce refusal across `work_dispatch.sh`, `work.sh`, and `claim.sh`. Differing case: A session runs `claim.sh <n>` directly on an issue marked `status:needs-input`. Under Reading 1, `claim.sh` succeeds and creates a worktree for an escalated issue. Under Reading 2, `claim.sh` refuses with exit 2 before mutating labels or comments. Reading 2 is adopted. Circuit breaker checks must fail closed across all direct script entry points. |
| **D3** | **Candidate filtering in continuous poller (`poll.sh`).** In `scripts/placement/vm-local/poll.sh`, candidate evaluation for open pull requests skips PRs whose tracking issue carries `status:needs-input`, logging `poll.sh: skipping PR #<pr> (tracking issue #<issue> carries status:needs-input)`. Candidate discovery on lifecycle ladder stages (`ladder_labels`) naturally skips displaced issues because their stage label has been replaced with `status:needs-input`. | *Adversary analysis:* Two defensible readings: (1) Skip candidate issues during issue ladder discovery only; (2) Skip candidates during both pull request evaluation and issue ladder discovery. Differing case: A pull request is open while its tracking issue carries `status:needs-input`. Under Reading 1, `poll.sh` dispatches review runs for the pull request. Under Reading 2, `poll.sh` skips the pull request until operator input is supplied. Reading 2 is adopted. An escalated issue must halt automated processing on its pull requests. |
| **D4** | **Structured escalation marker grammar.** The machine-readable escalation marker syntax is: `ESCALATION: #<n> kind=<open-question|blocked|ambiguous-owner> stage=<stage>`. The marker is emitted on its own line in the issue handoff comment adjacent to `WORK-RESULT:`. Permitted `kind` values are `open-question`, `blocked`, and `ambiguous-owner`. Permitted `stage` values are the lifecycle stage names (`intake`, `plan`, `design`, `build`, `implement`, `review`). | *Adversary analysis:* Two defensible readings: (1) Free-form prose or optional key-value pairs; (2) Strict line format matching regex `^ESCALATION: #([0-9]+) kind=(open-question|blocked|ambiguous-owner) stage=([a-z-]+)$`. Differing case: A parser in `align_escalations.sh` or `/escalations` processes an escalation comment. Under Reading 1, free-text variations require heuristic regexes and cause parsing errors. Under Reading 2, deterministic extraction ensures robust programmatic parsing. Reading 2 is adopted. |
| **D5** | **Ambiguous owner escalation in headless dispatch (`work.sh`).** When a stage has multiple persona owners and `--as` is omitted: (a) In interactive mode, `scripts/ops/work.sh` preserves its current behavior: prints the owner names and exits 0 with instructions to rerun with `--as <persona>`. (b) In unattended mode (`HEADLESS=1`), `scripts/ops/work.sh` applies `status:needs-input`, emits an issue comment containing `ESCALATION: #<n> kind=ambiguous-owner stage=<stage>`, and exits 2 with `WORK-RESULT: blocked #<n> ambiguous owner for stage <stage>`. | *Adversary analysis:* Two defensible readings: (1) Both interactive and headless modes escalate immediately to `status:needs-input`; (2) Interactive mode preserves the exit 0 informational message, and headless mode escalates to `status:needs-input`. Differing case: An operator runs `work.sh 211` at a terminal. Under Reading 1, the issue is escalated to `status:needs-input` requiring clearance. Under Reading 2, the terminal output prompts the operator, who immediately reruns with `--as atlas`. Reading 2 is adopted. |
| **D6** | **Autonomous `/escalations` command door and loop stalled view.** Defined in canonical source `commands/escalations.md` and compiled via `scripts/sync_commands.py` into `.claude/commands/escalations.md` and `.agents/skills/escalations/SKILL.md`. The command: (1) Queries all open issues carrying `status:needs-input`. (2) Parses the `ESCALATION:` marker to determine `kind` and displaced `stage`. (3) Presents each item to the operator. (4) Awaits operator decision. (5) Posts a structured ruling comment to the issue thread (`Decision: <ruling>`). (6) Removes `status:needs-input` and restores the displaced lifecycle stage label (`status:<stage>`). (7) Drops `in-progress` if held. (8) Inspects and displays stalled loop items (dead claims, residue branches with zero commits against main, consensus-agreed unmerged PRs) as an informational report, satisfying Gate H / H4 loop visibility. Automated reaping remains with #483. | *Adversary analysis:* Two defensible readings: (1) `/escalations` checks out git branches directly and commits changes to markdown files; (2) `/escalations` posts ruling comments to the issue thread and restores the stage label. Differing case: An operator resolves an open question on an issue at `status:spec`. Under Reading 1, `/escalations` must manage worktrees across arbitrary persona branches. Under Reading 2, `/escalations` operates via GitHub API comments and labels, and the stage persona resumes and incorporates the ruling under its declared bounds. Reading 2 is adopted. |
| **D7** | **Retrofit alignment script (`scripts/ops/align_escalations.sh`).** A standalone script `scripts/ops/align_escalations.sh` inspects the repository backlog for pre-existing escalation conditions and stalled resources. Defaults to `--dry-run` (audit mode), printing findings without mutating tracker state. When invoked with `--apply`, it applies `status:needs-input` and posts the structured `ESCALATION:` marker for matching candidate issues. | *Adversary analysis:* Two defensible readings: (1) Mutate tracker state by default; (2) Audit by default and require `--apply` to mutate. Differing case: The script is run in an automated CI check or by an operator exploring the queue. Under Reading 1, issues are mutated unexpectedly. Under Reading 2, candidate issues are listed without tracker modifications. Reading 2 is adopted. |
| **D8** | **Living spec and changelog update obligations.** The implementing pull request updates `docs/SPEC.md` under operational tooling and lifecycle states, documenting `status:needs-input`, `ESCALATION:` syntax, circuit breaker extensions, poller candidate filtering, and the `/escalations` command. `CHANGELOG.md` records the enhancement. | *Adversary analysis:* Two defensible readings: (1) Treat the command and scripts as operational utilities requiring no living spec update; (2) Require a living spec update describing the escalation queue and circuit breaker additions. Differing case: `spec_check.sh` validates the implementation pull request. Under Reading 1, `spec_check.sh` allows `Spec-impact: none`. Under Reading 2, `spec_check.sh` enforces living spec updates. Reading 2 is adopted. |
| **D9** | **Scope boundaries and file manifest.** The implementing change touches only the files listed in the implementation manifest. Workflows, reviewer scoring scripts, and core lifecycle automation remain untouched. | *Adversary analysis:* Two defensible readings: (1) Allow edits to `lifecycle.yml` to automate `status:needs-input` clearance; (2) Confine label restoration to `/escalations` and `align_escalations.sh`. Differing case: An operator clears an escalation by hand on GitHub. Under Reading 1, `lifecycle.yml` triggers on label events. Under Reading 2, label restoration follows the established `/escalations` command workflow without introducing new GitHub Actions webhooks. Reading 2 is adopted. |

## Acceptance

- **AT-481-1 (D1):** In `scripts/setup/bootstrap_tracker.sh`, `ensure_label "status:needs-input" "E11D21"` is defined. A tracker query confirms `status:needs-input` exists.
- **AT-481-2 (D1):** On an issue carrying `status:planning`, applying `status:needs-input` removes `status:planning`. Clearing `status:needs-input` restores `status:planning`.
- **AT-481-3 (D2):** When `scripts/ops/work_dispatch.sh <issue>` is executed against an open issue carrying `status:needs-input`, it exits 2 with stderr containing `work_dispatch.sh: refused: #<issue> carries status:needs-input`.
- **AT-481-4 (D2):** When `scripts/ops/work.sh <issue>` is executed against an open issue carrying `status:needs-input`, it exits 2 with stderr containing `carries status:needs-input`.
- **AT-481-5 (D2):** When `scripts/ops/claim.sh <issue>` is executed against an open issue carrying `status:needs-input`, it exits 2 with stderr containing `refused: #<issue> carries status:needs-input`.
- **AT-481-6 (D2):** When `scripts/ops/claim.sh <issue>` is executed against an open issue carrying `status:review-stuck`, it exits 2 with stderr containing `refused: #<issue> carries status:review-stuck`.
- **AT-481-7 (D3):** In `scripts/placement/vm-local/poll.sh`, candidate evaluation skips pull requests whose tracking issue carries `status:needs-input`, emitting `poll.sh: skipping PR #<pr> (tracking issue #<issue> carries status:needs-input)`.
- **AT-481-8 (D4):** An escalation handoff comment containing `ESCALATION: #481 kind=open-question stage=plan` matches regex `^ESCALATION: #([0-9]+) kind=(open-question|blocked|ambiguous-owner) stage=([a-z-]+)$`.
- **AT-481-9 (D5):** In `scripts/ops/work.sh`, when invoked under `HEADLESS=1` on an issue with multiple owners without `--as`, the script applies `status:needs-input`, posts an issue comment containing `ESCALATION: #<issue> kind=ambiguous-owner stage=<stage>`, and exits 2 with `WORK-RESULT: blocked #<issue> ambiguous owner for stage <stage>`.
- **AT-481-10 (D6):** `commands/escalations.md` compiles byte-identically via `scripts/sync_commands.py` into `.claude/commands/escalations.md` and `.agents/skills/escalations/SKILL.md`, and `python3 scripts/sync_commands.py --check` exits 0.
- **AT-481-11 (D6):** The `/escalations` command lists open issues carrying `status:needs-input`, records the operator ruling comment `Decision: ...`, removes `status:needs-input`, and restores the displaced lifecycle stage label.
- **AT-481-12 (D6, D7):** `scripts/ops/align_escalations.sh` without arguments runs in audit mode, printing candidate escalations and stalled resources without mutating labels or posting comments, exiting 0.
- **AT-481-13 (D7):** `scripts/ops/align_escalations.sh --apply` applies `status:needs-input` and emits the structured `ESCALATION:` marker on qualifying candidate issues.
- **AT-481-14 (D8):** `docs/SPEC.md` documents `status:needs-input`, `ESCALATION:` syntax, `/escalations`, and circuit breaker extensions, passing `scripts/ci/spec_check.sh`.
- **AT-481-15 (D9):** The implementation pull request diff modifies only the files specified in the implementation manifest.

## Open questions

none
