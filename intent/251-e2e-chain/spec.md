# Spec: wire the end-to-end autonomous chain across rung transitions

**Issue:** #251 · **Status:** Approved (approval = merge of this PR) ·
**Author:** athena (`evekhm-athena-app[bot]`) ·
**Open questions:** none

## What is being built

An end-to-end autonomous chain across ladder rung transitions between
the intake boundary at `intent:new` and the final review boundary at
`status:in-review`. The implementation resolves three operational gaps
identified in `intent.md`:

1. Automated claim release during ladder transitions:
   `scripts/ci/lifecycle_advance.sh` clears the `in-progress` label when
   the claim holder matches the owner of the merged stage, allowing the
   successor persona to claim the issue without collision.
2. Placement dispatch execution path: ladder persona execution targets
   `vm-local` placement, served by an operator VM-side poller that
   consumes D16 loop-ledger dispatch rows or label transitions. Defect
   #284 is resolved by passing `--as "$persona"` in adapter calls.
3. Persona credential security and operator enablement: key storage
   guidelines for local and hosted execution, Environment declarations
   in `scripts/auth/app_manifests.yaml`, and the step-by-step enablement
   sequence documented in `docs/SPEC.md ## Deployment status`.

### Manifest of files touched by the implementation rung

- `scripts/ci/lifecycle_advance.sh`: claim release on ladder advance,
  adapter dispatch call with `--as "$persona"`, and missing-key refusal
  logging.
- `scripts/ci/tests/lifecycle_advance_test.sh`: hermetic test cases for
  claim release, foreign claim withholding, and adapter argument
  passing.
- `scripts/placement/vm-local/run.sh`: delegation handling when executed
  inside GitHub Actions workflows.
- `scripts/placement/gh-actions/run.sh`: persona Environment secret
  handling.
- `config/execution.yaml`: ladder placement configuration and budget
  declarations.
- `scripts/auth/app_manifests.yaml`: Environment definitions for persona
  entries.
- `.github/workflows/unattended.yml`: dormant persona Environment
  wiring for hosted runner jobs.
- `docs/SPEC.md`: deployment status checklist and placement
  documentation updates.

## Decisions

| ID | Decision | Rationale |
|----|----------|-----------|
| D1 | **Claim release on ladder advance.** Upon a ladder rung advance, `lifecycle_advance.sh` reads the latest `Claim:` comment on the issue thread. If the recorded claim actor matches the persona owning the merged stage (derived from `personas/*.yaml` stage lists), `lifecycle_advance.sh` deletes the `in-progress` label as the merge actor before dispatching the successor persona, logging `released claim of <actor> on #<n> (rung <stage> merged)`. If the claim is held by any other persona, or if no valid claim comment exists while `in-progress` is set, `lifecycle_advance.sh` preserves the label, withholds dispatch, and logs a named notice. If `in-progress` is absent, no release call is made. Issue #252 closes as incorporated in #251. `scripts/ops/work.sh` remains unchanged. | The stage owner finishes their role once their rung artifact or pull request merges to `main`. Having `lifecycle_advance.sh` release the mutex enables the next persona to claim the issue immediately upon dispatch. Verifying claim authorship against the merged stage prevents clearing claims held by concurrent peer sessions. Incorporating #252 into #251 avoids external dependency delays and ensures ladder transitions and claim release are tested together without modifying `work.sh` (preserving #64 D19). |
| D2 | **Dispatch path and placement target.** The three ladder personas (`athena`, `daedalus`, `odyssey`) target `vm-local` placement in `config/execution.yaml`. When `lifecycle_advance.sh` runs on GitHub Actions, it writes the D16 loop-ledger dispatch row and invokes `scripts/placement/vm-local/run.sh "$issue" --as "$persona"` (fixing defect #284). When executed inside GitHub Actions, `scripts/placement/vm-local/run.sh` logs delegation to the VM poller and exits 0. A VM-side poller running on the operator VM monitors the repository for new D16 dispatch rows or `status:*` transitions and executes `scripts/placement/vm-local/run.sh` locally. Switching a persona to hosted Actions execution is accomplished by setting `placement: gh-actions` in `config/execution.yaml` without script edits. #64 D16 ("No second workflow, no issues: labeled trigger, no new event") is amended to permit the external VM poller to consume D16 dispatch rows while keeping `lifecycle.yml` permissions unchanged. | Follows the operator directive prioritising the shortest path to an end-to-end working loop: reviewers, lifecycle, gate, and Themis run on Actions, while builders run from the operator VM. Serving builders locally avoids moving private keys into GitHub Actions before necessary and avoids adding `actions: write` to `lifecycle.yml` (preserving #64 D23). Passing `--as "$persona"` resolves defect #284 across both placement adapters. |
| D3 | **Persona credential storage and Environment security.** On the operator VM, persona private keys reside in local key files under `~/.keys/`. For cloud-hosted execution in GitHub Actions, persona private keys must be stored in dedicated GitHub Environments named after each persona (`athena`, `daedalus`, `odyssey`) with a `main`-only deployment-branch policy (following the Themis model in PR #257, D31), never in repository secrets. The implementing pull request adds Environment declarations to `scripts/auth/app_manifests.yaml` and prepares `.github/workflows/unattended.yml` in a dormant state, activated only when the operator provisions the Environments and flips the placement pin in `config/execution.yaml`. | "Repository secrets are readable by any same-repo PR-branch workflow run, so a PR could mint a builder persona and forge spec approvals, plan commits or pushes; D23's trusted-writer rule and merge-gate conjunct (7) rest on author login." Storing keys in `main`-only Environments ensures pull-request runs cannot access builder identities. Shipping manifest definitions in a dormant state allows configuration readiness without forcing premature key migration. |
| D4 | **Missing credential handling.** If a placement adapter encounters missing credentials or an unconfigured harness in its runtime environment, the advancer records a loop-ledger refusal row with `reason-code: missing-key` and logs `refusal reason-code: missing-key on #<issue> (missing credential for <persona>)`. The workflow then invokes `scripts/ci/escalate.sh "$issue" --reason missing-key --head "$head"`, swapping the active `status:*` label for `status:review-stuck` and posting an escalation comment. | An unconfigured credential is an abnormal condition that blocks unattended progress. Leaving an issue at its current stage without notification creates an invisible stall. Transitioning the issue to `status:review-stuck` with `reason-code: missing-key` makes the blockage visible on the tracker board and alerts the operator to provision the necessary credentials or harness. |
| D5 | **First hop dispatch and ledger accounting.** The initial hop from `intent:new` to `status:planning` (the plan rung) is launched by the operator VM launcher (`scripts/ops/work.sh` or `ops/waves/launch.sh`) or by the VM poller targeting open `intent:new` issues. Loop-ledger accrual starts on the first ladder transition executed by `lifecycle_advance.sh` upon the merge of `intent.md`, which advances the issue to `status:spec` and writes the first dispatch row. The first hop records zero loop-ledger dispatches, preserving the entire quota of `max_rung_dispatches_per_issue` (default 12) for subsequent automated ladder rungs. | Issue intake remains a human responsibility outside the autonomous loop (#64 Out of scope). `lifecycle_advance.sh` executes on `push` to `main` following artifact or pull request merges, without triggering on issue creation. Launching the first hop from the VM launcher simplifies triage and ensures ledger tracking begins when the first approved artifact lands on `main`. |
| D6 | **Operator enablement checklist.** The enablement checklist lives in `docs/SPEC.md ## Deployment status`. The checklist specifies six ordered steps with exact commands: (1) verify Themis provisioning via `python3 scripts/auth/create_all_apps.py --check`; (2) provision persona Environments via `python3 scripts/auth/create_all_apps.py --only <persona>` for `athena`, `daedalus`, and `odyssey` if Actions placement is selected; (3) verify branch protection on `main` via `gh api repos/evekhm/agentic-sdlc/branches/main/protection/required_status_checks` and `.../protection`; (4) verify placement settings via `python3 scripts/ops/execution.py --check`; (5) merge the autonomy flip pull request setting `loop.autonomous_merge: true` in `config/execution.yaml` and documenting P1 and P2 evidence (#64 acceptance 28); (6) launch the first hop on the target issue from `intent:new`. | `docs/SPEC.md ## Deployment status` is the established canonical location for deployment prerequisites and verified evidence. Placing the checklist in `docs/SPEC.md` maintains a single source of truth for repository operational state and avoids document sprawl. |
| D7 | **End-to-end validation.** Validation of the autonomous chain is conducted on a dedicated synthetic throwaway issue per #64 acceptance 20. The operator starts the first hop on the synthetic issue after the autonomy flip pull request merges. The validation run captures and records: (1) the synthetic issue number; (2) all four dispatch rows plus the terminal row in the loop ledger; (3) workflow run IDs for `lifecycle.yml` and `merge-gate.yml` across each transition; (4) merge commit SHAs matching `Reviewed-head` recorded in consensus ledgers; (5) final issue state showing `status:in-review` and removal of `in-progress`. | Using a synthetic throwaway issue prevents test artifacts or aborted attempts from polluting the active backlog or living spec documentation, fulfilling the explicit requirement of #64 acceptance 20. |
| D8 | **Scope boundary.** The implementation pull request may modify `scripts/ci/lifecycle_advance.sh`, `scripts/ci/tests/lifecycle_advance_test.sh`, `scripts/placement/vm-local/run.sh`, `scripts/placement/gh-actions/run.sh`, `config/execution.yaml`, `scripts/auth/app_manifests.yaml`, `.github/workflows/unattended.yml`, and `docs/SPEC.md`. It may not modify `scripts/ops/work.sh`, `scripts/ops/claim.sh` internals (beyond invoking `--release`), `.github/workflows/lifecycle.yml` permissions block, `scripts/ci/merge_gate.sh`, `intent/64-autonomous-loop/**`, `intent/265-review-split/**`, `intent/267-*/**`, or files in `personas/**`. | Strict boundaries isolate changes to transition mechanics, preventing regressions in merge gate evaluation or review protocols and adhering to #64 D19. |

## Acceptance

Every row is checkable without a model call:

- **AT-1 (D1)** In `lifecycle_advance_test.sh`, a merged pull request
  advancing a ladder rung on an issue whose latest claim comment was
  authored by the owner of the completing stage releases `in-progress`
  and invokes the placement adapter.
- **AT-2 (D1)** In `lifecycle_advance_test.sh`, an issue carrying
  `in-progress` where the latest claim comment was authored by a
  different persona preserves `in-progress`, withholds placement
  adapter dispatch, and outputs a notice naming the holder.
- **AT-3 (D1)** In `lifecycle_advance_test.sh`, an issue carrying
  `in-progress` with no structured claim comment preserves
  `in-progress`, withholds placement adapter dispatch, and outputs a
  notice indicating that the claim holder cannot be established.
- **AT-4 (D2, #284)** In `lifecycle_advance_test.sh`, every placement
  adapter dispatch invocation passes the issue number followed by
  `--as "$persona"`.
- **AT-5 (D2)** Executing `scripts/placement/vm-local/run.sh <issue>
  --as <persona>` with `GITHUB_ACTIONS=true` set prints the delegation
  notice and exits 0.
- **AT-6 (D2)** `python3 scripts/ops/execution.py --check` passes with
  `vm-local` placement bindings and passes when re-pinned to
  `gh-actions`.
- **AT-7 (D3)** `scripts/auth/app_manifests.yaml` validates cleanly
  under `python3 scripts/auth/create_all_apps.py --check`.
- **AT-8 (D4)** Missing credentials in an adapter execution environment
  generate a `missing-key` loop-ledger refusal row and execute
  `scripts/ci/escalate.sh` with reason code `missing-key`.
- **AT-9 (D5)** Initiating the first hop via the VM launcher produces no
  loop-ledger rows prior to the first transition executed by
  `lifecycle_advance.sh`.
- **AT-10 (D6)** `docs/SPEC.md ## Deployment status` contains the
  complete six-step enablement checklist with runnable verification
  commands.
- **AT-11 (D7)** Acceptance evidence for #64 acceptance 20 defines the
  synthetic issue number, four dispatch rows, one terminal row,
  workflow run IDs, and attributable merge SHAs.
- **AT-12 (D8)** Pre-merge validation checks exit 0:
  `bash scripts/ci/spec_check.sh origin/main <(echo "Spec-impact: none - intent/** only, not a behavior-bearing path")`
  and `bash scripts/ci/sanitize_check.sh`.

## Concerns

- **Key exposure across execution tiers.** Repository secrets are
  accessible to any pull-request branch workflow run within the same
  repository. Storing builder persona credentials as repository
  secrets would allow untrusted code in a pull request to mint tokens
  and forge approvals or commits. Maintaining builder credentials
  exclusively in local files on the VM or in `main`-only GitHub
  Environments prevents credential exposure.
- **Preservation of lifecycle workflow permissions.** Expanding
  `.github/workflows/lifecycle.yml` permissions to include `actions:
  write` would weaken the security boundary established by #64 D23.
  Serving `vm-local` placement through the external VM poller allows
  unattended execution without altering workflow permissions.
- **Claim release synchronization.** Clearing `in-progress` must
  happen strictly before dispatching the successor persona. If the
  release call fails or the claim belongs to another actor, withholding
  dispatch prevents dual-session execution conflicts on the same
  worktree.
- **Hermetic test coverage for defect #284.** Defect #284 arose
  because `lifecycle_advance.sh` called `run.sh` without the `--as`
  flag, which both placement adapters require. AT-4 ensures that unit
  test fixtures assert the presence of `--as "$persona"` on all adapter
  calls.
- **Fail-closed credential verification.** If an adapter encounters an
  environment where the required credentials or harness binaries are
  absent, triggering an escalation with `missing-key` ensures that the
  blockage is immediately visible on the tracker board instead of
  silently stalling the issue.

## Out of scope

- Activating autonomous merging: setting `loop.autonomous_merge: true`
  belongs exclusively to the follow-up flip pull request (#64
  acceptance 28).
- Daemon service management scripts (systemd service units or
  supervisord configs) for the VM-side poller.
- Changes to review consensus schemas, reviewer personas, or reviewer
  protocols.
- Automated creation or triage of `intent:new` issues from external
  webhooks.

## Operator decisions

None required by this spec. The implementation dispatch proceeds to the
builder persona, and the operator runs the enablement checklist prior
to the autonomy flip pull request.

Open questions: none
