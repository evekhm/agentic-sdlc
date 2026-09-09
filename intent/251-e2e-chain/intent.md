# Intent: wire the end-to-end autonomous chain across rung transitions

**Issue:** #251 · **Author:** athena (`evekhm-athena-app[bot]`) ·
**Status:** accepted on merge of this PR

## Problem

The autonomous loop delivered in #64 aims to achieve the core demo goal:
"dispatch agy on issue N, it goes end to end" from intake through spec,
plan, implementation, review, and autonomous merge without human intervention
unless consensus fails. At base `d61875cd8468a2aa7183d2f0f7628e1174ee3524`,
three operational gaps prevent the chain from executing past the first rung:

1. **Gap 1: Prior rung's claim halts next dispatch.**
   In `scripts/ops/work.sh:467-485`, refusal (g) enforces that `in-progress`
   can only be resumed by the persona holding the claim:
   `grep -Fxq "$claim_holder" <<<"$resumers" || refuse "in-progress on $held_on is held by $claim_holder"`.
   When a rung merges and the ladder advances to a stage owned by a different
   persona (e.g. `status:spec` owned by athena advancing to `status:build`
   owned by daedalus), the advancer writes the label but leaves `in-progress`
   intact (`scripts/ci/lifecycle_advance.sh` has zero occurrences of
   `in-progress`). `claim.sh --release` exists but has no callers.
   Consequently, the successor persona refuses with (g).
   Gap 1 was split to #252; #251's follow-up implements #252's preferred
   option: release `in-progress` on ladder advance only when held by the
   persona that authored the merged rung.

2. **Gap 2: Advancer dispatch lacks harness and credentials.**
   In `scripts/ci/lifecycle_advance.sh:1059-1078`, the D16 dispatch step resolves
   the persona binding and runs `scripts/placement/<placement>/run.sh "$NUMBER"`.
   Both `scripts/placement/vm-local/run.sh` and `gh-actions/run.sh:128` end with
   `exec "$REPO_ROOT/scripts/ops/work.sh" "$NUMBER" --as "$PERSONA"`. Inside
   GitHub Actions on `push` to `main` (`.github/workflows/lifecycle.yml`),
   the environment lacks persona private keys and CLI harnesses (`claude`, `agy`),
   so `work.sh` exits via `UNSET_CREDENTIAL_IS_SKIP=1` or fails.
   The proposed fix to dispatch `.github/workflows/unattended.yml` via
   `workflow_dispatch` collides with #64 D23, which explicitly dictates that
   `lifecycle.yml` "keeps its `permissions:` block to what it holds today"
   (`issues: write`, `contents: read`, `pull-requests: read` — no `actions: write`).

3. **Gap 3: Enablement prerequisites remain unconfigured.**
   Autonomous execution remains disarmed until operator setup is complete:
   the Themis App is not registered/provisioned (`THEMIS_APP_PRIVATE_KEY` /
   `THEMIS_APP_ID`), persona App private keys (`ATHENA`, `DAEDALUS`, `ODYSSEY`)
   are absent from repository secrets (currently under deliberate HOLD per
   operator comment `2026-09-08T07:05:25Z`), `config/execution.yaml` keeps
   `loop.autonomous_merge: false` and `placement: vm-local`, and branch
   protection on `main` requires verification.

While #64 closed schema support (`trigger: ladder` in `config/execution.yaml`)
and D16 ledger cost recording (`cost:$cap` in `lifecycle_advance.sh`), the
chain stalls immediately upon transition.

## Proposed outcome

1. **Automated claim handoff across ladder stages:**
   `scripts/ci/lifecycle_advance.sh` releases `in-progress` during a ladder
   transition if and only if the current claim is held by the persona that
   authored the newly merged rung. If held by any other actor, the claim is
   preserved, dispatch is withheld, and a named notice is logged.

2. **Functional unattended execution dispatch:**
   Ladder transitions invoke placement adapters that successfully launch
   the next persona in an environment equipped with appropriate credentials
   and harnesses (e.g. via `unattended.yml` matrix jobs), resolving the
   permission and credential boundary between `lifecycle.yml` and unattended
   runners without violating #64 D23 security guarantees.

3. **Codified operator return checklist:**
   A comprehensive checklist is documented in `docs/SPEC.md` under
   `Deployment status` defining the exact procedure for operator activation:
   provisioning Themis (`create_all_apps.py --only themis`), populating
   secrets, verifying branch protection (P2), updating placement and
   activating `loop.autonomous_merge: true` (P1/acceptance 28), with the first
   hop initiated by human dispatch.

## Affected systems

- `scripts/ci/lifecycle_advance.sh` (claim release check and dispatch invocation)
- `scripts/ci/tests/lifecycle_advance_test.sh` (claim release tests)
- `scripts/placement/gh-actions/run.sh` and `vm-local/run.sh` (dispatch execution)
- `.github/workflows/lifecycle.yml` (dispatch triggering and permissions)
- `.github/workflows/unattended.yml` (input handling and matrix execution)
- `config/execution.yaml` (`loop.autonomous_merge` and persona `placement`)
- `scripts/ops/claim.sh` (claim release interface)
- `scripts/ops/work.sh` (refusal (g) semantics; subject to D19 boundary)
- `docs/SPEC.md` (`### lifecycle.labels`, `### execution.placement`, `Deployment status`)
- `intent/64-autonomous-loop/spec.md` (amendment to D23 if permissions change)

## Constraints

- **#64 D16 (Same-run dispatch):** Advancer dispatches the next rung
  immediately from the transition writing the label; no secondary workflow
  trigger or `issues: labeled` event.
- **#64 D18 (Fail-closed autonomy disarm):** `loop.autonomous_merge: false`
  disarms merge and next-rung dispatch; safety stops and ratchets are never disarmed.
- **#64 D23 (Trusted writer & credential boundary):** Merge actor (`themis`) is
  the sole trusted writer for state comments. `lifecycle.yml` permissions
  and token exposures must not grant untrusted or escalated access.
- **Single status writer:** `scripts/ci/lifecycle_advance.sh` remains the sole
  writer of `status:*` ladder labels.
- **Trusted posting:** All comments and state markers obey repository posting
  scripts and identity checks (`personas/skills/trusted-posting.md`).
- **Operator deliberate HOLD:** Secret injection and branch protection remain
  operator-managed manual preconditions; credentials are never committed.
- **Rung-by-rung lifecycle:** The ladder advances strictly rung-by-rung per
  operator directive of 2026-09-09, superseding the 2026-09-08 fast-path note.

## Open questions

1. **Claim release location and condition:**
   - *Option A:* `lifecycle_advance.sh` drops `in-progress` via `gh issue edit`
     during the transition, solely when held by the preceding rung's persona.
   - *Option B:* `claim.sh --release` is invoked by the preceding persona's
     session or commit hook prior to PR merge.

2. **Sequencing of #252 vs #251:**
   - *Option A:* #252 lands first as an isolated defect repair to claim mechanics,
     and #251 adopts it as an external dependency.
   - *Option B:* #251 delivers the claim release directly within the ladder
     transition, closing #252 as incorporated.

3. **Runner dispatch mechanism without `actions: write`:**
   - *Option A:* Amend #64 D23 to grant `actions: write` to `lifecycle.yml`,
     allowing `GITHUB_TOKEN` to call `workflow_dispatch` on `unattended.yml`.
   - *Option B:* Preserve D23 permissions strictly; dispatch via an external
     webhook, repository dispatch, or merge-actor App token with actions scope.

4. **Default ladder placement target:**
   - *Option A:* Default ladder personas to `placement: gh-actions` in
     `config/execution.yaml` for cloud-hosted autonomous runs.
   - *Option B:* Retain `placement: vm-local` as default, requiring an operator-hosted
     daemon or local worker for unattended execution.

5. **Home for operator enablement checklist:**
   - *Option A:* Formalized in `docs/SPEC.md` under `Deployment status` alongside
     P1 and P2 verification criteria.
   - *Option B:* Documented in `docs/PLAYBOOK.md` as an operational procedure
     independent of normative system specifications.

6. **First hop dispatch and ledger accrual:**
   - *Option A:* The initial rung is always dispatched manually by an operator,
     accruing 0 cost until the first automated transition.
   - *Option B:* An intake workflow or script dispatches the first rung from
     `intent:new`, recording initial budget against `max_rung_dispatches_per_issue`.

7. **Validation target for #64 Acceptance 20:**
   - *Option A:* Exercise the full automated ladder on a dedicated synthetic/throwaway
     test issue to prove end-to-end traversal safely.
   - *Option B:* Execute Acceptance 20 on an active backlog issue (e.g. #98) to
     produce real repository artifacts.

8. **Missing credential handling:**
   - *Option A:* Skip dispatch silently or with a log notice (`UNSET_CREDENTIAL_IS_SKIP=1`),
     leaving the issue at the current stage without escalating.
   - *Option B:* Invoke `escalate.sh` with a dedicated reason code (e.g. `missing-key`),
     marking the issue `status:review-stuck` to alert the operator.

9. **Scope boundary regarding `scripts/ops/work.sh` (#64 D19 ban):**
   - *Option A:* #251 inherits #64 D19's prohibition on modifying `work.sh`,
     requiring claim adjustments to occur strictly within `lifecycle_advance.sh`.
   - *Option B:* #251 establishes its own scope boundary permitting adjustments
     to `work.sh` refusal (g) to accommodate autonomous handoffs.
