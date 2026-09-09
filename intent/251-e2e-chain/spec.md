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
   the authenticated claim holder matches the owner of the merged stage,
   allowing the successor persona to claim the issue without collision.
2. Placement dispatch execution path: ladder persona execution targets
   `vm-local` placement, served by an operator VM poller that consumes
   D16 loop-ledger dispatch rows or review dispatches. Defect #284 is
   resolved by passing `--as "$persona"` in adapter calls.
3. Persona credential security and operator enablement: key storage
   guidelines for local execution, supervisor templates for background
   polling, and the step-by-step enablement sequence documented in
   `docs/SPEC.md ## Deployment status`.

### Manifest of files touched by the implementation rung

- `scripts/ci/lifecycle_advance.sh`: claim release on ladder advance,
  adapter dispatch call with `--as "$persona"`, and delegation handling
  for vm-local placement.
- `scripts/ci/tests/lifecycle_advance_test.sh`: unit test cases for
  claim release, foreign claim withholding, autonomy-off preservation,
  and adapter argument passing.
- `scripts/placement/vm-local/poll.sh`: bash poller looping on a fixed
  interval via gh and jq, consuming unconsumed dispatch rows and review
  dispatches, claiming before launching.
- `scripts/placement/vm-local/poll.sidecar.json`: Antigravity sidecar
  configuration template with command, args, env, and restart policy.
- `scripts/placement/vm-local/poll.service`: systemd user unit
  configuration template for the poller fallback.
- `scripts/placement/vm-local/run.sh`: preflight credential verification
  and delegation logging when executed inside GitHub Actions.
- `config/execution.yaml`: ladder placement configuration and budget
  declarations.
- `docs/SPEC.md`: deployment status enablement checklist, supervisor
  operational documentation, and line 841 stale table repair.

Forbidden files (untouched by this implementation):
- `scripts/ci/escalate.sh`: closed reason code set remains untouched.
- `.github/workflows/lifecycle.yml`: triggers and permissions remain
  untouched, holding no builder secrets.
- `scripts/ops/work.sh`: command dispatch preserved without edits.
- `scripts/ci/merge_gate.sh`, `intent/64-autonomous-loop/**`, and
  `personas/**`.

## Open questions mapping

| Open Question | Decision | Status and Chosen Alternative |
|---|---|---|
| OQ1: Claim release location and condition | D1 | Option A: `lifecycle_advance.sh` releases `in-progress` via `gh issue edit` during transition when claim comment author login matches completing stage persona. |
| OQ2: Sequencing of #252 vs #251 | D1 | Option B: #251 delivers claim release directly within ladder transition; closes #252 as incorporated. |
| OQ3: Runner dispatch mechanism without `actions: write` | D2 | Option B: Preserves #64 D23 permissions; VM-side poller consumes D16 dispatch rows from loop ledger. |
| OQ4: Default ladder placement target | D2 | Option B: Retains `placement: vm-local` for ladder personas, executed by VM poller under sidecar supervisor. |
| OQ5: Home for operator enablement checklist | D6 | Option A: Formalized in `docs/SPEC.md ## Deployment status`. |
| OQ6: First hop dispatch and ledger accrual | D5 | Option B: `poll.sh` launches first hop on `intent:new` with zero ledger accrual; accrual starts on merge of `intent.md`. |
| OQ7: Validation target for #64 Acceptance 20 | D7 | Option A: Full automated chain exercised on a dedicated synthetic throwaway issue. |
| OQ8: Missing credential handling | D4 | Option A modified: Missing key is install-time provisioning error; `poll.sh` logs and skips without escalating, leaving `escalate.sh` and `lifecycle.yml` untouched. |
| OQ9: Scope boundary regarding `scripts/ops/work.sh` | D8 | Option A: Inherits #64 D19 ban on editing `work.sh`; claim adjustments occur strictly in `lifecycle_advance.sh`. |

## Decisions

| ID | Decision | Rationale |
|---|---|---|
| D1 | **Claim release on ladder advance.** Upon a ladder rung advance, `lifecycle_advance.sh` reads the latest `Claim:` comment on the issue thread. The claim holder is derived by extracting the comment author login (`.user.login`) and mapping it through the persona identity table, exactly matching `scripts/ops/work.sh:475-482` and resume-protocol Refusal 5, without parsing unauthenticated comment body text. If the mapped claim persona matches the persona owning the completed stage (derived from `personas/*.yaml` stage lists), `lifecycle_advance.sh` deletes the `in-progress` label as the merge actor before dispatching the successor persona, logging `released claim of <actor> on #<n> (rung <stage> merged)`. If the claim is held by any other persona, or by a foreign author outside the persona mapping, or if `in-progress` is present with no structured claim comment, `lifecycle_advance.sh` preserves `in-progress`, withholds dispatch, and logs a named notice. If `loop.autonomous_merge: false` (or key absent), `lifecycle_advance.sh` leaves `in-progress` intact and skips release. If `in-progress` is absent, no release call is made. Issue #252 closes as incorporated in #251. `scripts/ops/work.sh` remains unchanged. | The stage owner finishes their role once their rung artifact or pull request merges to `main`. Having `lifecycle_advance.sh` release the mutex enables the next persona to claim the issue immediately upon dispatch. Verifying claim authorship against author login prevents clearing claims held by concurrent peer sessions or foreign authors. Incorporating #252 into #251 avoids external dependency delays and ensures ladder transitions and claim release are tested together without modifying `work.sh` (preserving #64 D19). |
| D2 | **Dispatch path, supervisor process tree, and placement target.** The three ladder personas (`athena`, `daedalus`, `odyssey`) target `vm-local` placement in `config/execution.yaml`. The supervisor is an Antigravity sidecar with `restart_policy: always`, and a `systemd --user` unit is the documented fallback (constraint 5). The process hierarchy is detailed below. When `lifecycle_advance.sh` runs inside GitHub Actions, it writes the D16 loop-ledger dispatch row and invokes `scripts/placement/vm-local/run.sh "$issue" --as "$persona"` (fixing defect #284). When executed inside GitHub Actions (`GITHUB_ACTIONS=true`), `scripts/placement/vm-local/run.sh` logs delegation to the VM poller and exits 0. `poll.sh` runs bash + gh + jq on a fixed interval with zero model calls. `poll.sh` consumes unclaimed `dispatch` ledger rows on issues and blocking review rows on pull requests authored by vm-local personas. Before launching a run, `poll.sh` posts the claim comment to GitHub to prevent double launch across restarts or concurrent polling ticks. Review rounds are dispatches too: blocking rows from a runner review on a pull request authored by a vm-local persona lead `poll.sh` to run `run.sh <pr> --as <author persona>` under the resume protocol. The re-pin property governs harness choice on `vm-local`: `config/deployments.yaml` pins athena and odyssey to `claude-code`, daedalus to `antigravity`. Re-pinning a persona switches the harness for the next launch without script edits. Amendment r5 to #64 D16 (as declared here; tracked in Out of scope with owner athena) permits the external VM poller to consume D16 dispatch rows and authorizes passing `--as "$persona"` to placement adapters. | Follows the operator directive prioritising the shortest path to an end-to-end working loop: reviewers, lifecycle, gate, and Themis run on Actions, while builders run from the operator VM. Serving builders locally avoids moving private keys into GitHub Actions and avoids adding `actions: write` to `lifecycle.yml` (preserving #64 D23). Passing `--as "$persona"` resolves defect #284 across both placement adapters. A resident agent conversation that polls is rejected because of cost per tick, single identity, and stale stage state against the labels-at-launch rule. Sidecar configuration facts live at `~/.gemini/config/sidecars/<id>/sidecar.json` with logs in `~/.gemini/antigravity/sidecar_data/<id>/logs/`, and headless execution stability under xvfb-run for 20 days was reported by the operator on #251, comment 5597497232. |
| D3 | **Persona credential storage and security boundary.** On the operator VM, persona private keys reside in local key files under `~/.keys/`. Builder persona keys remain strictly on the VM and never enter GitHub Actions repository secrets or environments. Unattended reviewer personas (`argus`, `atlas`) and Themis keep their existing secret layout in GitHub Actions: `ARGUS_APP_PRIVATE_KEY` and `ATLAS_APP_PRIVATE_KEY` remain repository secrets, and `MERGE_ACTOR_APP_PRIVATE_KEY` resides in the dedicated `themis` Environment (`main`-only branch policy per #64 D23 / #257 D31). | "Repository secrets are readable by any same-repo PR-branch workflow run, so a PR could mint a builder persona and forge spec approvals, plan commits or pushes; D23's trusted-writer rule and merge-gate conjunct (7) rest on author login." Keeping builder credentials on the operator VM prevents exposure to pull request workflows. |
| D4 | **Missing credential handling at installation time.** Reason code `missing-key` is dropped from escalation schemas. With builder keys kept on the operator VM (D3), missing credentials represent an install-time provisioning error instead of a runtime workflow failure. Step 5 of the enablement checklist (D6) executes `python3 scripts/auth/mint_app_token.py <persona> --require-repo --quiet` for each vm-local persona (`athena`, `daedalus`, `odyssey`). At startup and on each polling tick, `poll.sh` runs the same token mint preflight; if a key is missing or unreadable, `poll.sh` logs `missing key for <persona>, skipping its rows` and continues polling the remaining personas. Exiting non-zero is rejected because under `restart_policy: always` an exit would trigger a continuous restart loop. `scripts/ci/escalate.sh` and `.github/workflows/lifecycle.yml` stay completely untouched. | Treating missing keys as install-time provisioning errors keeps `escalate.sh` reason codes aligned with normative #64 D9 definitions. Logging and skipping unprovisioned personas prevents poller restart crashes while preserving autonomous processing for available personas. |
| D5 | **First hop dispatch and queue accounting.** `scripts/placement/vm-local/poll.sh` is the single actor for dispatch execution. The primary queue for autonomous ladder progression is the loop ledger `dispatch` row written by `lifecycle_advance.sh` (per #64 D13). In `lifecycle_advance.sh:1022-1078` (the D16 block), the first `dispatch` row for an issue is written upon the `push` event to `main` that merges `intent.md`, advancing the issue to `status:spec` (rank 2, design stage, owner athena). For an issue filed at `intent:new`, no merge commit exists on `main`, and `.github/workflows/lifecycle.yml` triggers only on `push` to `main`, so no event produces a dispatch row for `intent:new` prior to that merge. `poll.sh` serves as the single actor: it scans for open, unclaimed `intent:new` issues and launches `scripts/placement/vm-local/run.sh <issue> --as athena` (where `scripts/ops/work.sh:347-349` derives stage `plan`). The initial hop records zero loop-ledger dispatches, preserving the entire quota of `max_rung_dispatches_per_issue` (default 12) for automated ladder transitions. If the initial hop were required to be driven by a dispatch row, `.github/workflows/lifecycle.yml` would need an `issues: labeled` trigger and `lifecycle_advance.sh` an intake dispatch branch, but `lifecycle.yml` remains untouched per D4 and D8. | Issue intake remains outside the autonomous loop (#64 Out of scope). `lifecycle_advance.sh` executes on `push` to `main` following artifact or pull request merges. Having `poll.sh` handle intake issues directly avoids adding complex event triggers to `lifecycle.yml` while ensuring strict accounting begins when the first approved artifact lands on `main`. |
| D6 | **Operator enablement checklist.** The enablement checklist lives in `docs/SPEC.md ## Deployment status`. The checklist specifies seven ordered steps with exact commands: (1) verify Themis provisioning via `python3 scripts/auth/create_all_apps.py --only themis --check` (exit 0); (2) configure VM supervisor via `scripts/placement/vm-local/poll.sidecar.json` into `~/.gemini/config/sidecars/sdlc-poller/sidecar.json` (or install `poll.service` into `~/.config/systemd/user/`); (3) verify branch protection on `main` via `gh api repos/evekhm/agentic-sdlc/branches/main/protection` (confirming four required checks, strict false, enforce_admins false); (4) verify placement bindings via `python3 scripts/ops/execution.py --check` (exit 0); (5) preflight vm-local persona credentials via `python3 scripts/auth/mint_app_token.py <persona> --require-repo --quiet` for athena, daedalus, and odyssey; (6) submit and merge the autonomy flip pull request setting `loop.autonomous_merge: true` in `config/execution.yaml` and documenting P1 and P2 evidence (#64 acceptance 28); (7) launch first hop or verify poller intake on target issue. | `docs/SPEC.md ## Deployment status` is the established canonical location for deployment prerequisites and verified evidence. Placing the checklist in `docs/SPEC.md` maintains a single source of truth for repository operational state and avoids document sprawl. |
| D7 | **End-to-end validation.** Validation of the autonomous chain is conducted on a dedicated synthetic throwaway issue per #64 acceptance 20. The operator starts the first hop on the synthetic issue after the autonomy flip pull request merges. The validation run captures and records: (1) the synthetic issue number; (2) all four dispatch rows plus the terminal row in the loop ledger; (3) workflow run IDs for `lifecycle.yml` and `merge-gate.yml` across each transition; (4) merge commit SHAs matching `Reviewed-head` recorded in consensus ledgers; (5) final issue state showing `status:in-review` and removal of `in-progress`. | Using a synthetic throwaway issue prevents test artifacts or aborted attempts from polluting the active backlog or living spec documentation, fulfilling the explicit requirement of #64 acceptance 20. |
| D8 | **Scope boundary and Amendment r5 to #64 D16.** The implementation pull request may modify `scripts/ci/lifecycle_advance.sh`, `scripts/ci/tests/lifecycle_advance_test.sh`, `scripts/placement/vm-local/poll.sh`, `scripts/placement/vm-local/poll.sidecar.json`, `scripts/placement/vm-local/poll.service`, `scripts/placement/vm-local/run.sh`, `config/execution.yaml`, and `docs/SPEC.md` (deployment status checklist and line 841 stale table repair). It may not modify `scripts/ci/escalate.sh`, `.github/workflows/lifecycle.yml`, `scripts/ops/work.sh`, `scripts/ops/claim.sh` internals (beyond invoking `--release`), `scripts/ci/merge_gate.sh`, `intent/64-autonomous-loop/**`, `intent/265-review-split/**`, `intent/267-*/**`, or files in `personas/**`. Amendment r5 to #64 D16 (as declared in D2; tracked in Out of scope with owner athena) permits the external VM poller to consume D16 dispatch rows and authorizes passing `--as "$persona"` to placement adapters. | Strict boundaries isolate changes to transition mechanics, preventing regressions in merge gate evaluation or review protocols and adhering to #64 D19. |

### Process hierarchy (D2)

The execution tree below is adopted verbatim from operator comment 5597497232:

```text
supervisor (Antigravity sidecar, restart_policy: always; systemd --user unit is the documented fallback)
  └── poll.sh            bash, loops forever, gh + jq, no model
        └── scripts/placement/vm-local/run.sh <number> --as <persona>
              └── scripts/ops/work.sh <number> --as <persona>
                    └── claude -p ... | agy -p ...   (whatever config/deployments.yaml pins; one fresh headless run per rung, exits when its PR is open)
```

## Acceptance

Every row is checkable without a model call:

- **AT-1 (D1)** In `lifecycle_advance_test.sh`, a ladder rung transition
  on an issue whose latest claim comment author login maps to the
  completing stage persona releases `in-progress` and invokes the
  placement adapter.
- **AT-2 (D1)** In `lifecycle_advance_test.sh`, an issue carrying
  `in-progress` where the latest claim comment author login maps to a
  different persona preserves `in-progress`, withholds adapter
  dispatch, and logs a named notice.
- **AT-3 (D1)** In `lifecycle_advance_test.sh`, an issue carrying
  `in-progress` where the latest claim comment author is foreign
  (outside persona mapping) or missing preserves `in-progress`,
  withholds adapter dispatch, and logs a notice.
- **AT-4 (D1)** In `lifecycle_advance_test.sh`, when
  `loop.autonomous_merge: false` (or key absent), ladder advance leaves
  `in-progress` intact and does not release the claim.
- **AT-5 (D2, #284)** In `lifecycle_advance_test.sh`, every placement
  adapter dispatch invocation passes `<issue> --as <persona>`.
- **AT-6 (D2)** Executing `scripts/placement/vm-local/run.sh <issue>
  --as <persona>` with `GITHUB_ACTIONS=true` prints the delegation
  notice and exits 0.
- **AT-7 (D2)** Executing `bash -n scripts/placement/vm-local/poll.sh`
  passes syntax validation, and running with mock ledger data finds
  unconsumed dispatch rows and review dispatches, issuing the claim
  comment prior to invocation.
- **AT-8 (D2)** `scripts/placement/vm-local/poll.sidecar.json` contains
  valid JSON declaring `command`, `args`, `env`, and
  `restart_policy: always`.
- **AT-9 (D2)** `scripts/placement/vm-local/poll.service` conforms to
  systemd service unit syntax declaring `Type=simple`, `Restart=always`,
  and valid `ExecStart`.
- **AT-10 (D2, Live supervisor check - NOT RUN)** Live verification with
  UI closed: supervisor process is active and running `poll.sh`.
  Verification command: `pgrep -fa 'bash.*poll.sh'` prints running PID,
  and log at
  `~/.gemini/antigravity/sidecar_data/sdlc-poller/logs/sidecar.log` (or
  `journalctl --user -u poll.service -n 20`) contains `poller active,
  interval: 30s`. (Constraint 5; reported by the operator on #251,
  comment 5597497232).
- **AT-11 (D2)** Re-pin property: In a hermetic test, updating `athena`
  in `config/deployments.yaml` to `antigravity`, running stub
  `work.sh <issue> --as athena`, asserts `agy` is invoked with expected
  flags, and reverting leaves `claude-code` active.
- **AT-12 (D4)** Missing credential handling:
  `python3 scripts/auth/mint_app_token.py <persona> --require-repo --quiet`
  preflights keys on VM; when a key is absent, `poll.sh` logs
  `missing key for <persona>, skipping its rows` and continues without
  crashing or exiting.
- **AT-13 (D5)** Initiating the first hop via `poll.sh` on an
  `intent:new` issue produces zero loop-ledger rows prior to the first
  transition executed by `lifecycle_advance.sh` upon the merge of
  `intent.md`.
- **AT-14 (D6)** Step 1 check:
  `python3 scripts/auth/create_all_apps.py --only themis --check`
  exits 0.
- **AT-15 (D6, D8)** `docs/SPEC.md ## Deployment status` contains the
  seven-step enablement checklist with runnable commands, and line 841
  stale table entry is updated from `manual` to `ladder`.
- **AT-16 (D7)** Synthetic issue validation evidence captures synthetic
  issue number, four dispatch rows, one terminal row, workflow run IDs,
  attributable merge SHAs, and final `status:in-review`.
- **AT-17 (D8)** Pre-merge validation checks exit 0:
  `BODY_FILE="$(mktemp)"; echo "Spec-impact: none - intent/** only, not a behavior-bearing path" > "$BODY_FILE"; bash scripts/ci/spec_check.sh origin/main "$BODY_FILE"; rm -f "$BODY_FILE"`
  and `bash scripts/ci/sanitize_check.sh`.

## Concerns

- **Key isolation and trust boundaries.** Builder keys remain on the VM
  in `~/.keys/`. Repository secrets are accessible to same-repo pull
  request runs, which would allow arbitrary branch runs to forge author
  signatures.
- **Supervisor lifecycle and headless stability.** Running `poll.sh`
  under an Antigravity sidecar (`restart_policy: always`) or systemd
  user unit ensures the poller survives UI disconnects and IDE restarts.
- **Claim authentication integrity.** Using `.user.login` mapped
  through persona identity tables prevents comment body spoofing.
- **Loop ledger quota preservation.** Starting loop-ledger accrual on the
  first transition ensures that the initial triage hop does not deplete
  the 12-dispatch budget.
- **Fail-safe credential skipping.** Preflighting credentials in
  `poll.sh` and skipping unprovisioned personas prevents endless restart
  cycles under persistent supervisor policies.

## Out of scope

- Activating autonomous merging: setting `loop.autonomous_merge: true`
  belongs exclusively to the follow-up flip pull request (#64 acceptance
  28; successor pull request citing operator comment 5597497232 and #64
  comment 5597017135).
- Dedicated pull request for Amendment r5 to #64 D16: Owned by Athena,
  amending `intent/64-autonomous-loop/spec.md` line 151 to record
  consumption of dispatch rows by external VM poller and adapter `--as`
  arguments.
- Active backlog issues (#267, #265, #148, #147, #104, #108) by number.
- Automated creation or triage of `intent:new` issues from external
  webhooks.
- Changes to review consensus schemas, reviewer personas, or reviewer
  protocols.

## Operator decisions

Binding operator design decisions on issue #251: comment 5597356948
(06:46 UTC, constraints 1 to 6) and comment 5597497232 (06:53 UTC,
binding points 1 to 8).

The operator executes the seven-step enablement checklist in D6 prior to
launching the autonomy flip pull request:

1. Verify Themis provisioning:
   Run `python3 scripts/auth/create_all_apps.py --only themis --check`.
   Must exit 0 with Environment `themis` present and secrets populated.
2. Configure VM supervisor:
   Copy `scripts/placement/vm-local/poll.sidecar.json` to
   `~/.gemini/config/sidecars/sdlc-poller/sidecar.json` and enable in
   `~/.gemini/config/config.json`. Alternatively, copy
   `scripts/placement/vm-local/poll.service` to
   `~/.config/systemd/user/poll.service` and run `systemctl --user daemon-reload && systemctl --user enable --now poll.service`.
3. Verify branch protection on `main`:
   Run `gh api repos/evekhm/agentic-sdlc/branches/main/protection` and
   verify required status checks with strict false and enforce_admins false.
4. Verify execution bindings:
   Run `python3 scripts/ops/execution.py --check` and verify exit 0.
5. Preflight vm-local persona credentials:
   Run `python3 scripts/auth/mint_app_token.py <persona> --require-repo --quiet`
   for athena, daedalus, and odyssey; all must exit 0.
6. Submit and merge the autonomy flip pull request:
   Open the pre-approved autonomy flip pull request setting
   `loop.autonomous_merge: true` in `config/execution.yaml` with P1 and P2
   evidence (#64 acceptance 28).
7. Initiate issue processing:
   Verify poller intake on target issue or trigger first hop.

Open questions: none
