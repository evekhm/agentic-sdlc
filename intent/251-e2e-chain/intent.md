# Intent: wire the end-to-end autonomous chain across rung transitions

**Issue:** #251 · **Author:** athena (`evekhm-athena-app[bot]`) ·
**Status:** accepted on merge of this PR

## Problem

The autonomous loop delivered in #64 aims to achieve the core demo goal:
"dispatch agy on issue N, it goes end to end" from intake through spec,
plan, implementation, review, and autonomous merge without human intervention
unless consensus fails. Wiring this chain makes #64 acceptance 20 runnable.
The issue body notes that nothing in the demo needs #147's per-issue override
labels (`pin:`, `tier:`, `mode:autonomous`), leaving them out of scope.
At base `d61875cd8468a2aa7183d2f0f7628e1174ee3524`, three operational gaps
prevent the chain from executing past the first rung:

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
   Gap 1 was split to #252. The issue originator proposes releasing
   `in-progress` on ladder advance when held by the persona that authored
   the merged rung, while open questions 1 and 2 leave the release location
   and sequencing to the design rung.

2. **Gap 2: Advancer dispatch lacks harness and credentials.**
   In `scripts/ci/lifecycle_advance.sh:1059-1078`, the D16 dispatch step resolves
   the persona binding and invokes the placement adapter using the exact line:
   `bash "$REPO_ROOT/scripts/placement/$placement/run.sh" "$issue"`.
   Both `scripts/placement/vm-local/run.sh` and `gh-actions/run.sh:128` end with
   `exec "$REPO_ROOT/scripts/ops/work.sh" "$NUMBER" --as "$PERSONA"`. Inside
   GitHub Actions on `push` to `main` (`.github/workflows/lifecycle.yml`),
   the environment lacks persona private keys and CLI harnesses (`claude`, `agy`).
   When persona credentials are unset, the skip logic in the placement adapter
   `scripts/placement/gh-actions/run.sh:116` (`UNSET_CREDENTIAL_IS_SKIP=1`)
   exits with code 2. Furthermore, in `.github/workflows/unattended.yml:38-53`
   at SHA `bea8e6a84a2fcb23a7559c872af5195bfb4f7f6e`, `workflow_dispatch`
   declares inputs `number`, `persona`, and `dry_run` with `dry_run` defaulting
   to `true`, so a bare `gh workflow run unattended.yml -f number=<n> -f persona=<p>`
   writes nothing. The proposed fix to dispatch `.github/workflows/unattended.yml`
   via `workflow_dispatch` collides with #64 D23, which dictates that `lifecycle.yml`
   keeps its `permissions:` block to what it holds today (`issues: write`,
   `contents: read`, `pull-requests: read`, with no `actions: write`).

3. **Gap 3: Enablement prerequisites remain unconfigured.**
   Autonomous execution remains disarmed until operator setup is complete.
   Themis registration and provisioning were reported complete by the operator
   on 2026-09-09 (`scripts/auth/create_all_apps.py --check` exit 0, Environment
   `themis`, secrets `THEMIS_APP_ID` and `THEMIS_APP_PRIVATE_KEY`), not read in
   this session because `--check` needs repository admin. The deliberate HOLD per
   operator comment `2026-09-08T07:05:25Z` applies to the three persona keys
   `ATHENA_APP_PRIVATE_KEY`, `DAEDALUS_APP_PRIVATE_KEY`, and
   `ODYSSEY_APP_PRIVATE_KEY` only; repository secrets reported present are
   `ANTIGRAVITY_ADC_JSON`, `ARGUS_APP_PRIVATE_KEY`, and `ATLAS_APP_PRIVATE_KEY`.
   Branch protection on `main` was reported applied on 2026-09-09 05:48 UTC
   (four ci-gates jobs required, strict false, enforce_admins false), with
   evidence recorded at `runs/2026-09-09_054800/p1-p2-evidence.md` outside the tree,
   citing line 13: `{"allow_deletions":false,"allow_force_pushes":false,"enforce_admins":false,"required_pull_request_reviews":null,"restrictions":null}`.
   `config/execution.yaml` keeps `loop.autonomous_merge: false` and `placement: vm-local`.

While #64 closed schema support (`trigger: ladder` in `config/execution.yaml`)
and D16 ledger cost recording (`cost:$cap` in `lifecycle_advance.sh`), ensuring
that the merge gate decline ("a dispatch row on #<n> carries no cost") is not
triggered by the D16 path because the row already carries `cost:$cap`, the
chain stalls immediately upon transition.

## Proposed outcome

1. **Automated claim handoff across ladder stages (originator proposal):**
   `in-progress` is released during ladder transitions when held by the persona
   that authored the newly merged rung, enabling the successor persona to claim
   without refusal (g). The exact release mechanism and #252 sequencing remain
   open for the design rung under open questions 1 and 2.

2. **Functional unattended execution dispatch (originator proposal):**
   Ladder transitions invoke placement adapters that launch the next persona
   in an environment equipped with necessary credentials and harnesses,
   resolving the credential and execution boundary without violating #64 D23
   guarantees. The dispatch trigger mechanism and placement target remain open
   for the design rung under open questions 3 and 4.

3. **Codified operator return checklist (originator proposal):**
   A checklist is documented for operator activation (candidate home:
   `docs/SPEC.md` `Deployment status`; the design rung decides against
   `docs/PLAYBOOK.md` under open question 5), covering Themis provisioning,
   populating secrets, verifying branch protection (P2), updating placement,
   and activating `loop.autonomous_merge: true` (P1/acceptance 28). The first
   hop dispatch mechanism remains open under open question 6.

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
  trigger or `issues: labeled` event. The merge gate decline ("a dispatch row
  on #<n> carries no cost") is not triggered by the D16 path because the row
  already carries `cost:$cap`.
- **#64 D18 (Fail-closed autonomy disarm):** `loop.autonomous_merge: false`
  disarms merge and next-rung dispatch; safety stops and ratchets are never disarmed.
- **#64 D23 (Trusted writer & credential boundary):** Merge actor (`themis`) is
  the sole trusted writer for state comments. `lifecycle.yml` permissions
  and token exposures must not grant untrusted or escalated access.
- **Single status writer:** `scripts/ci/lifecycle_advance.sh` remains the sole
  writer of `status:*` ladder labels.
- **Trusted posting:** All comments and state markers obey repository posting
  scripts (`scripts/ops/post.sh`) and identity checks (`personas/skills/trusted-posting.md`).
- **Operator deliberate HOLD:** Secret injection and branch protection remain
  operator-managed manual preconditions; credentials are never committed.
- **Rung-by-rung lifecycle:** The ladder advances strictly rung-by-rung per
  operator directive of 2026-09-09, superseding the 2026-09-08 fast-path note.
- **Scope boundary (#147, #64 acceptance 20):** Wiring this chain makes #64
  acceptance 20 runnable. The issue body records that nothing in the demo
  needs #147's per-issue override labels (`pin:`, `tier:`, `mode:autonomous`),
  and they are not decided here. Refs #64, #147, #246.

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
   - *Option A:* An intake dispatch passes `dry_run=false` to
     `.github/workflows/unattended.yml` from `intent:new`, recording initial
     budget against `max_rung_dispatches_per_issue`.
   - *Option B:* The operator's launcher (`ops/waves/launch.sh` on the VM) initiates
     the first hop, accruing 0 cost in GitHub Actions until the first automated transition.

7. **Validation target for #64 Acceptance 20:**
   - *Option A:* Exercise the full automated ladder on a dedicated synthetic test
     issue to prove end-to-end traversal safely.
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
