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
   D16 loop-ledger dispatch rows, review dispatches, or scans open
   `intent:new` issues. Defect #284 is resolved by passing `--as "$persona"`
   in adapter calls, and fix-round review dispatches under `--as <persona>`
   are supported in `scripts/ops/work.sh`.
3. Persona credential security and operator enablement: key storage
   guidelines for local execution, supervisor templates for background
   polling, and the step-by-step enablement sequence documented in
   `docs/SPEC.md ## Deployment status`.

### Manifest of files touched by the implementation rung

- `scripts/ops/work.sh`: narrow interface change for fix rounds under
  `status:in-review` where `--as <persona>` matches PR head author.
- `scripts/ops/tests/work_test.sh`: unit test case for the fix-round
  dispatch path without refusal (h).
- `scripts/ci/lifecycle_advance.sh`: claim release on ladder advance and
  terminal review rung under GITHUB_TOKEN, adapter dispatch call with
  `--as "$persona"`, and delegation handling for vm-local placement.
- `scripts/ci/tests/lifecycle_advance_test.sh`: unit test cases for
  claim release (including terminal rung), foreign claim withholding,
  autonomy-off preservation, and adapter argument passing.
- `scripts/placement/vm-local/poll.sh`: bash poller looping on 30-second
  interval via gh and jq, consuming unconsumed dispatch rows, review
  dispatches, and open `intent:new` issues, claiming under minted
  persona token before launching.
- `scripts/placement/vm-local/poll.sidecar.json`: Antigravity sidecar
  configuration template with command, args, env, and restart policy.
- `scripts/placement/vm-local/poll.service`: systemd user unit
  configuration template for the poller fallback.
- `scripts/placement/vm-local/run.sh`: preflight credential verification
  and delegation logging when executed inside GitHub Actions.
- `docs/SPEC.md`: deployment status enablement checklist, supervisor
  operational documentation, and line 841 stale table repair.

Forbidden files (untouched by this implementation):
- `scripts/ci/escalate.sh`: closed reason code set remains untouched;
  no new reason code added.
- `.github/workflows/lifecycle.yml`: triggers and permissions remain
  untouched, holding no builder secrets.
- `scripts/ops/claim.sh`: claim release executed directly by
  `lifecycle_advance.sh`; claim.sh remains untouched.
- `scripts/ci/merge_gate.sh`, `intent/64-autonomous-loop/**`,
  `intent/265-review-split/**`, `intent/267-*/**`, and `personas/**`.

## Open questions mapping

| Open Question | Decision | Status and Chosen Alternative |
|---|---|---|
| OQ1: Claim release location and condition | D1 | Option A: `lifecycle_advance.sh` releases `in-progress` directly via `gh api` under `GITHUB_TOKEN` during transition when claim comment author login matches completing stage persona. |
| OQ2: Sequencing of #252 vs #251 | D1 | Option B: #251 delivers claim release directly within ladder transition; closes #252 as incorporated. |
| OQ3: Runner dispatch mechanism without `actions: write` | D2 | Option D: VM-side poller reading the advancer's dispatch ledger, chosen by the operator on 2026-09-09; preserves #64 D23 permissions. |
| OQ4: Default ladder placement target | D2 | Option B: Retains `placement: vm-local` for ladder personas, executed by VM poller under sidecar supervisor. |
| OQ5: Home for operator enablement checklist | D6 | Option A: Formalized in `docs/SPEC.md ## Deployment status`. |
| OQ6: First hop dispatch and ledger accrual | D5 | Option B: `poll.sh` launches first hop on `intent:new` with zero ledger accrual; accrual starts on merge of `intent.md`. |
| OQ7: Validation target for #64 Acceptance 20 | D7 | Option A: Full automated chain exercised on a dedicated synthetic throwaway issue. |
| OQ8: Missing credential handling | D4 | Option A modified: Missing key is install-time provisioning error; `poll.sh` logs and skips without escalating; no new reason code added, leaving `escalate.sh` and `lifecycle.yml` untouched. |
| OQ9: Scope boundary regarding `scripts/ops/work.sh` | D8 | Option C: #64 D19 scopes #64's own files; D8 permits one narrow interface change to `scripts/ops/work.sh` (tested in `scripts/ops/tests/work_test.sh`) to support fix-round dispatches for the PR author under `status:in-review`, leaving `review_dispatch` unchanged for reviewers. |

## Decisions

| ID | Decision | Rationale |
|---|---|---|
| D1 | **Claim release on ladder advance.** Upon a ladder rung advance, `lifecycle_advance.sh` reads the latest `Claim:` comment on the issue thread. The claim holder is derived by extracting the comment author login (`.user.login`) and mapping it through the persona identity table, exactly matching `scripts/ops/work.sh:475-482` and resume-protocol Refusal 5, without parsing unauthenticated comment body text. If the mapped claim persona matches the persona owning the completed stage (derived from `personas/*.yaml` stage lists), `lifecycle_advance.sh` deletes the `in-progress` label directly via `gh api` under `GITHUB_TOKEN` before dispatching the successor persona, logging `released claim of <actor> on #<n> (rung <stage> merged)`. Upon advancing to the terminal review rung (`advances_to: null`, `status:in-review`), `lifecycle_advance.sh` also releases the claim held by the completing stage persona (`odyssey`) under the same authenticated check, logging the same release line. If the claim is held by any other persona, or by a foreign author outside the persona mapping, or if `in-progress` is present with no structured claim comment, `lifecycle_advance.sh` preserves `in-progress`, withholds dispatch, and logs a named notice. If `loop.autonomous_merge: false` (or key absent), `lifecycle_advance.sh` leaves `in-progress` intact and skips release. If `in-progress` is absent, no release call is made. Issue #252 closes as incorporated in #251. `scripts/ops/claim.sh` remains untouched. | The stage owner finishes their role once their rung artifact or pull request merges to `main`. Having `lifecycle_advance.sh` release the mutex directly under `GITHUB_TOKEN` enables the next persona to claim the issue immediately upon dispatch, adhering to #64 D25 and D26 token boundaries. Releasing on the terminal transition prevents leaving `in-progress` permanently set on the final review stage. Verifying claim authorship against author login prevents clearing claims held by concurrent peer sessions or foreign authors. Incorporating #252 into #251 avoids external dependency delays and ensures ladder transitions and claim release are tested together. |
| D2 | **Dispatch path, supervisor process tree, and placement target.** The three ladder personas (`athena`, `daedalus`, `odyssey`) target `vm-local` placement in `config/execution.yaml`. The supervisor is an Antigravity sidecar with `restart_policy: always`, and a `systemd --user` unit is the documented fallback (constraint 5, binding point 5). The process hierarchy is detailed below. When `lifecycle_advance.sh` runs inside GitHub Actions, it writes the D16 loop-ledger dispatch row and invokes `scripts/placement/vm-local/run.sh "$issue" --as "$persona"` (fixing defect #284, binding point 3). When executed inside GitHub Actions (`GITHUB_ACTIONS=true`), `scripts/placement/vm-local/run.sh` logs delegation to the VM poller and exits 0. `poll.sh` runs bash + gh + jq on a 30-second interval with zero model calls (binding point 2). `poll.sh` consumes unconsumed `dispatch` ledger rows on issues, scans for open `intent:new` intake issues, and consumes blocking review rows on pull requests authored by vm-local personas. Before launching a run, `poll.sh` claims through `CLAIM_ACTOR=<persona> CLAIM_SESSION=poll-<pid> scripts/ops/claim.sh <n>` under `GH_TOKEN="$(python3 scripts/auth/mint_app_token.py <persona>)"` minted per claim, so the claim comment author login matches the persona App identity and satisfies D1's release predicate. If `claim.sh` refuses because the issue is already claimed, `poll.sh` skips the item; if `claim.sh` refuses due to token mismatch or missing keys, `poll.sh` logs and skips that persona. Review rounds are dispatches too (binding point 4): blocking rows from a runner review on a pull request authored by a vm-local persona lead `poll.sh` to run `scripts/placement/vm-local/run.sh <pr> --as <author persona>` under the resume protocol. To support this without refusal (h), `scripts/ops/work.sh` takes a fix-round path when `--as <persona>` names the author of the PR head branch (`<persona>/<n>-*`) and the issue is at `status:in-review`, leaving stage as the authoring rung and leaving `review_dispatch` unchanged for argus and atlas. The re-pin property governs harness choice on `vm-local` (binding point 7): `config/deployments.yaml:8-10` on `origin/main` pins all three builders (`athena`, `daedalus`, `odyssey`) to `antigravity`. Re-pinning a persona switches the harness for the next launch without script edits. Amendment r5 to #64 D16 (tracked under the operator follow-up `intent:new` issue "Amend #64 D16 for VM poller dispatch consumption and adapter --as argument", with owner athena) permits the external VM poller to consume D16 dispatch rows and authorizes passing `--as "$persona"` to placement adapters. | Follows the operator directive prioritising the shortest path to an end-to-end working loop: reviewers, lifecycle, gate, and Themis run on Actions, while builders run from the operator VM. Serving builders locally avoids moving private keys into GitHub Actions and avoids adding `actions: write` to `lifecycle.yml` (preserving #64 D23). Passing `--as "$persona"` resolves defect #284 across placement adapters. A resident agent conversation that polls is rejected because of cost per tick, single identity, and stale stage state against the labels-at-launch rule (binding point 2). Sidecar configuration paths (`~/.gemini/config/sidecars/<id>/sidecar.json`) and log paths (`~/.gemini/antigravity/sidecar_data/<id>/logs/`) as well as headless execution stability under xvfb-run were reported by the operator on #251, comment 5597497232 (binding point 6). |
| D3 | **Persona credential storage and security boundary.** On the operator VM, persona private keys reside in local key files under `~/.keys/` (binding point 1). HELD keys close because the keys are not needed on GitHub (constraint 1, binding point 1). Builder persona keys remain strictly on the VM and never enter GitHub Actions repository secrets or environments. Unattended reviewer personas (`argus`, `atlas`) and Themis keep their existing secret layout in GitHub Actions: `ARGUS_APP_PRIVATE_KEY` and `ATLAS_APP_PRIVATE_KEY` remain repository secrets, and `MERGE_ACTOR_APP_PRIVATE_KEY` resides in the dedicated `themis` Environment (`main`-only branch policy per #64 D23 / #257 D31). | "Repository secrets are readable by any same-repo PR-branch workflow run, so a PR could mint a builder persona and forge spec approvals, plan commits or pushes; D23's trusted-writer rule and merge-gate conjunct (7) rest on author login." Keeping builder credentials on the operator VM prevents exposure to pull request workflows. |
| D4 | **Missing credential handling at installation time.** No new reason code (such as `missing-key`) is added to escalation schemas. With builder keys kept on the operator VM (D3), missing credentials represent an install-time provisioning error. Step 5 of the enablement checklist (D6) executes `python3 scripts/auth/mint_app_token.py <persona> --require-repo --quiet` for each vm-local persona (`athena`, `daedalus`, `odyssey`). At startup and on each polling tick, `poll.sh` runs the same token mint preflight; if a key is missing or unreadable, `poll.sh` logs `missing key for <persona>, skipping its rows` and continues polling the remaining personas. Exiting non-zero is rejected because under `restart_policy: always` an exit would trigger a continuous restart loop. `scripts/ci/escalate.sh` and `.github/workflows/lifecycle.yml` stay completely untouched. | Keeping `escalate.sh` reason codes aligned with normative #64 D9 definitions avoids schema inflation. Logging and skipping unprovisioned personas prevents poller restart crashes while preserving autonomous processing for available personas. |
| D5 | **First hop dispatch and queue accounting.** `scripts/placement/vm-local/poll.sh` is the single actor for dispatch execution. The primary queue for autonomous ladder progression is the loop ledger `dispatch` row written by `lifecycle_advance.sh` (per #64 D13). In `lifecycle_advance.sh:1022-1078` (the D16 block), the first `dispatch` row for an issue is written upon the `push` event to `main` that merges `intent.md`, advancing the issue to `status:spec` (rank 2, design stage, owner athena). For an issue filed at `intent:new`, no merge commit exists on `main`, and `.github/workflows/lifecycle.yml` triggers only on `push` to `main`, so no event produces a dispatch row for `intent:new` prior to that merge. `poll.sh` serves as the single actor: it scans for open, unclaimed `intent:new` issues, posts the claim comment under minted token for `athena` via `claim.sh`, and launches `scripts/placement/vm-local/run.sh <issue> --as athena` (where `scripts/ops/work.sh:347-349` derives stage `plan`). The initial hop records zero loop-ledger dispatches, preserving the entire quota of `max_rung_dispatches_per_issue` (default 12) for automated ladder transitions. If the initial hop were required to be driven by a dispatch row, `.github/workflows/lifecycle.yml` would need an `issues: labeled` trigger and `lifecycle_advance.sh` an intake dispatch branch, but `lifecycle.yml` remains untouched per D4 and D8. | Issue intake remains outside the autonomous loop (#64 Out of scope). `lifecycle_advance.sh` executes on `push` to `main` following artifact or pull request merges. Having `poll.sh` handle intake issues directly avoids adding complex event triggers to `lifecycle.yml` while ensuring strict accounting begins when the first approved artifact lands on `main`. |
| D6 | **Operator enablement checklist.** The enablement checklist lives in `docs/SPEC.md ## Deployment status`. The checklist specifies seven ordered steps with exact commands: (1) verify Themis provisioning via `python3 scripts/auth/create_all_apps.py --only themis --check` (exit 0); (2) configure VM supervisor via `scripts/placement/vm-local/poll.sidecar.json` into `~/.gemini/config/sidecars/sdlc-poller/sidecar.json` (or install `poll.service` into `~/.config/systemd/user/`); (3) verify branch protection on `main` via `gh api repos/evekhm/agentic-sdlc/branches/main/protection` (confirming four required checks, strict false, enforce_admins false); (4) verify placement bindings via `python3 scripts/ops/execution.py --check` (exit 0); (5) preflight vm-local persona credentials via `python3 scripts/auth/mint_app_token.py <persona> --require-repo --quiet` for athena, daedalus, and odyssey; (6) submit and merge the autonomy flip pull request setting `loop.autonomous_merge: true` in `config/execution.yaml` and documenting P1 and P2 evidence (#64 acceptance 28); (7) launch first hop or verify poller intake on target issue. | `docs/SPEC.md ## Deployment status` is the established canonical location for deployment prerequisites and verified evidence. Placing the checklist in `docs/SPEC.md` maintains a single source of truth for repository operational state and avoids document sprawl. |
| D7 | **End-to-end validation.** Validation of the autonomous chain is conducted on a dedicated synthetic throwaway issue per #64 acceptance 20. The operator starts the first hop on the synthetic issue after the autonomy flip pull request merges. The validation run captures and records: (1) the synthetic issue number; (2) all four dispatch rows plus the terminal row in the loop ledger; (3) workflow run IDs for `lifecycle.yml` and `merge-gate.yml` across each transition; (4) merge commit SHAs matching `Reviewed-head` recorded in consensus ledgers; (5) final issue state showing `status:in-review` and removal of `in-progress`. | Using a synthetic throwaway issue prevents test artifacts or aborted attempts from polluting the active backlog or living spec documentation, fulfilling the explicit requirement of #64 acceptance 20. |
| D8 | **Scope boundary and Amendment r5 to #64 D16.** The implementation pull request may modify `scripts/ops/work.sh` (narrow interface change for PR author fix rounds under `status:in-review`), `scripts/ops/tests/work_test.sh`, `scripts/ci/lifecycle_advance.sh`, `scripts/ci/tests/lifecycle_advance_test.sh`, `scripts/placement/vm-local/poll.sh`, `scripts/placement/vm-local/poll.sidecar.json`, `scripts/placement/vm-local/poll.service`, `scripts/placement/vm-local/run.sh`, and `docs/SPEC.md` (deployment status checklist and line 841 stale table repair). It may not modify `scripts/ci/escalate.sh`, `.github/workflows/lifecycle.yml`, `scripts/ops/claim.sh` (claim release executed directly by `lifecycle_advance.sh`), `scripts/ci/merge_gate.sh`, `intent/64-autonomous-loop/**`, `intent/265-review-split/**`, `intent/267-*/**`, or files in `personas/**`. Amendment r5 to #64 D16 (tracked under the operator follow-up `intent:new` issue "Amend #64 D16 for VM poller dispatch consumption and adapter --as argument", with owner athena) permits the external VM poller to consume D16 dispatch rows and authorizes passing `--as "$persona"` to placement adapters. | Strict boundaries isolate changes to transition and local dispatch mechanics, preventing regressions in merge gate evaluation or review protocols. Modifying `work.sh` narrowly to support fix rounds preserves the resume protocol without breaking review dispatches. |

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

Every hermetic unit and integration row is checkable without a model call; rows AT-11, AT-16, and AT-18 are marked as operator-discharged preconditions:

- **AT-1 (D1)** In `bash scripts/ci/tests/lifecycle_advance_test.sh`, a ladder rung transition on an issue whose latest claim comment author login maps to the completing stage persona prints `released claim of <actor> on #<n> (rung <stage> merged)`, deletes `in-progress` under `GITHUB_TOKEN`, and invokes the placement adapter.
- **AT-2 (D1)** In `bash scripts/ci/tests/lifecycle_advance_test.sh`, an issue carrying `in-progress` where the latest claim comment author login maps to a different persona prints `withholding dispatch: in-progress held by <holder>`, preserves `in-progress`, and withholds adapter dispatch.
- **AT-3 (D1)** In `bash scripts/ci/tests/lifecycle_advance_test.sh`, an issue carrying `in-progress` where the latest claim comment author is foreign (outside persona mapping) or missing prints `withholding dispatch: in-progress held by foreign login` (or unparseable claim), preserves `in-progress`, and withholds adapter dispatch.
- **AT-4 (D1)** In `bash scripts/ci/tests/lifecycle_advance_test.sh`, when `loop.autonomous_merge: false` (or key absent), ladder advance prints `autonomous_merge is false - no dispatch for #<n> (D18)`, leaves `in-progress` intact, and skips claim release.
- **AT-5 (D1)** In `bash scripts/ci/tests/lifecycle_advance_test.sh`, advancing to the terminal review rung (`advances_to: null`, `status:in-review`) prints `released claim of odyssey on #<n> (rung implement merged)` and removes `in-progress`.
- **AT-6 (D2, #284)** In `bash scripts/ci/tests/lifecycle_advance_test.sh`, every placement adapter dispatch invocation passes `<issue> --as <persona>` in its argv string.
- **AT-7 (D2)** Executing `GITHUB_ACTIONS=true scripts/placement/vm-local/run.sh 251 --as athena` prints `delegating #251 execution to operator VM poller` and exits 0.
- **AT-8 (D2)** Executing `bash -n scripts/placement/vm-local/poll.sh` exits 0. In a mock ledger test, executing `scripts/placement/vm-local/poll.sh --once` finds unconsumed rows, invokes `CLAIM_ACTOR=<persona> CLAIM_SESSION=poll-<pid> scripts/ops/claim.sh <n>` under minted token, verifies the posted claim comment carries `.user.login` matching the persona App identity, and skips already-claimed rows.
- **AT-9 (D2)** Running `python3 -m json.tool scripts/placement/vm-local/poll.sidecar.json >/dev/null` exits 0, and `jq -e '.command and .args and .env and (.restart_policy == "always")' scripts/placement/vm-local/poll.sidecar.json` prints `true`.
- **AT-10 (D2)** Running `grep -E '^(Type=simple|Restart=always|ExecStart=)' scripts/placement/vm-local/poll.service` outputs matching unit configuration lines and exits 0.
- **AT-11 (D2, Live supervisor check - NOT RUN, operator precondition)** Live verification with UI closed: supervisor process is active and running `poll.sh`. Verification command: `pgrep -fa 'bash.*poll.sh'` prints running PID, and log at `~/.gemini/antigravity/sidecar_data/sdlc-poller/logs/sidecar.log` (or `journalctl --user -u poll.service -n 20`) contains `poller active, interval: 30s` (Constraint 5, binding point 5; reported by the operator on #251, comment 5597497232).
- **AT-12 (D2)** Re-pin property: In a hermetic test in `scripts/ops/tests/work_test.sh`, using a fixture `deployments.yaml`, updating a persona pin from `antigravity` to `claude-code`, running stub `work.sh <issue> --as <persona>`, asserts `claude` is invoked with expected flags, and restoring the fixture returns to `antigravity`.
- **AT-13 (D2, D8)** Hermetic fix-round dispatch: In `scripts/ops/tests/work_test.sh`, a stub PR authored by odyssey at `status:in-review` dispatched with `scripts/ops/work.sh <pr> --as odyssey` does not refuse (h), does not print `odyssey does not own stage review (owners: argus atlas )`, and proceeds under the resume protocol.
- **AT-14 (D4)** Missing credential handling: Running `python3 scripts/auth/mint_app_token.py <persona> --require-repo --quiet` preflights keys on VM; when a key is absent, `poll.sh` logs `missing key for <persona>, skipping its rows` and continues without exiting.
- **AT-15 (D5)** First hop ledger check: Running `scripts/placement/vm-local/poll.sh --once` on an open `intent:new` issue runs claim and dispatch, and `gh api repos/evekhm/agentic-sdlc/issues/<n>/comments --jq '.[].body | select(test("<!-- loop-ledger"))'` outputs empty string (zero loop-ledger rows prior to merge of `intent.md`).
- **AT-16 (D6, Step 1 check - operator precondition)** Running `python3 scripts/auth/create_all_apps.py --only themis --check` exits 0 with `themis: OK`.
- **AT-17 (D6, D8)** Running `grep -F "## Deployment status" docs/SPEC.md` finds the section, `sed -n '/## Deployment status/,/##/p' docs/SPEC.md | grep -c '^[0-9]\. '` outputs `7`, and `sed -n '841p' docs/SPEC.md` outputs `ladder` in place of `manual`.
- **AT-18 (D7, Synthetic validation - operator precondition)** Dedicated synthetic issue run produces verification output: four dispatch rows, one terminal row, workflow run IDs, attributable merge SHAs, and final `status:in-review` without `in-progress`.
- **AT-19 (D8)** Pre-merge validation checks exit 0:
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
  comment 5597017135, binding point 8).
- Dedicated pull request for Amendment r5 to #64 D16: Owned by Athena,
  amending `intent/64-autonomous-loop/spec.md` line 151 to record
  consumption of dispatch rows by external VM poller and adapter `--as`
  arguments, tracked under the follow-up `intent:new` issue to be filed
  by the operator: "Amend #64 D16 for VM poller dispatch consumption and adapter --as argument".
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
