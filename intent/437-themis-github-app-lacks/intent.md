# Intent: Themis GitHub App lacks workflows permission, blocking merge of PRs touching .github/workflows/*

**Issue:** #437 · **Author:** athena (`evekhm-athena-app[bot]`) · **Status:** accepted on merge of this PR

## Problem

When a pull request touches any file under `.github/workflows/`, the autonomous merge gate (`scripts/ci/merge_gate.sh`, running inside `.github/workflows/merge-gate.yml`) cannot merge the PR, even when all automated CI checks pass, all contract tests succeed, and reviewer consensus is reached (`consensus:agreed`, `review:merge-ready`).

This failure manifested concretely on PR #427 (implementing #410's `CHANGELOG.md` hard CI gate, which modifies `.github/workflows/ci-gates.yml`). Despite full reviewer approval and all CI runs succeeding, four separate `merge-gate.yml` workflow dispatches across ~13 minutes consistently failed at conjunct (2):
```text
conjunct (2): false — mergeStateStatus is BLOCKED
```
Reads of GitHub's GraphQL API using personal access tokens (bot PAT, plain GraphQL viewer) read `mergeStateStatus: CLEAN` and `mergeable: MERGEABLE` for the identical pull request head (`483ce811145cc763356d45d462db5e1b0d7bbb62`). Only Themis's own viewer credential consistently read `mergeStateStatus: BLOCKED`.

### Root Cause Analysis

1. **GitHub Platform Security Rule:** GitHub requires the `workflows: write` (or `Workflows: Read and write`) permission on any authentication token that creates, modifies, or merges changes to GitHub Actions workflow files (`.github/workflows/*.yml`).
2. **Missing Manifest Declaration:** In `scripts/auth/app_manifests.yaml`, Themis's manifest entry (`themis`) declares only:
   ```yaml
   default_permissions:
     contents: write
     pull_requests: write
     issues: write
     checks: read
     statuses: read
     metadata: read
   ```
   The `workflows` permission is absent.
3. **Actor-Specific Merge Evaluation:** Themis is the sole sanctioned merge actor for the autonomous loop (Decision D3, #64). `scripts/ci/merge_gate.sh` operates under Themis's GitHub App installation token (minted via `actions/create-github-app-token` from `environment: themis`). When GitHub evaluates `pullRequest.mergeStateStatus` for Themis's viewer, GitHub determines that Themis cannot merge the workflow-touching PR and returns `BLOCKED`.
4. **Fail-Closed Gate Design:** In `scripts/ci/merge_gate.sh`, Decision D24 dictates that `mergeStateStatus == BLOCKED` is treated as a deterministic, fail-closed signal with zero retries (only `UNKNOWN` retries). Thus, the merge gate terminates immediately without merging.

This defect is distinct from:
- #298 (skipped-job roll-up entries where `mergeStateStatus` is `CLEAN` but checks show pending/incomplete).
- #308 (concurrency-group cancellation races).
Here, the failure is purely an authorization gap in Themis's GitHub App configuration.

## Proposed outcome

1. **Update Manifest Source (`scripts/auth/app_manifests.yaml`):**
   - Add `workflows: write` under `themis.default_permissions`.
   - Ensure the repository's App manifest definition is accurate so that any newly created or re-provisioned Themis App automatically requests `workflows: write`.
2. **Grant Live App Permission & Installation Approval (Operator Action):**
   - The repository owner / App manager updates the live `evekhm-themis-app` GitHub App configuration in GitHub App settings to add `Workflows: Read and write`.
   - The repository owner approves / accepts the updated permissions on the repository installation (`evekhm/agentic-sdlc`).
3. **Verification & Unblocking:**
   - Confirm that Themis's token reads `mergeStateStatus: CLEAN` for PR #427.
   - Re-dispatch `merge-gate.yml` for PR #427 and confirm that conjunct (2) evaluates to `true` and autonomous merge completes.
4. **Living Spec Upsert (`docs/SPEC.md`):**
   - Update `docs/SPEC.md` under `### loop.autonomous` to document that Themis's required permissions include `workflows: write` in order to merge pull requests that alter workflow files.

## Affected users and systems

- **Themis GitHub App (`evekhm-themis-app[bot]`):** Receives the `workflows: write` permission on its GitHub App installation.
- **Autonomous Merge Gate (`scripts/ci/merge_gate.sh`, `.github/workflows/merge-gate.yml`):** Unblocked from autonomously merging pull requests touching `.github/workflows/*.yml`.
- **App Provisioning & Management (`scripts/auth/app_manifests.yaml`, `scripts/auth/create_all_apps.py`):** Manifest reflects the new permission requirement.
- **Implementers & Personas (`odyssey`, `coder`):** Future PRs introducing or fixing CI workflows (e.g. #410, #427) will not get stuck at the merge gate.
- **Living Spec & Governance (`docs/SPEC.md`):** Formal record of Themis permissions.

## Constraints

- **Least Privilege Isolation:** Only Themis (the deterministic system merge actor with no prompt, model, or goals) receives `workflows: write`. Persona Apps (`athena`, `daedalus`, `cassandra`, `odyssey`, `argus`, `atlas`) MUST NOT receive `workflows: write`.
- **Environment Protection:** Themis's private key and App ID remain strictly confined to the `themis` GitHub Environment with a deployment-branch policy admitting `main` only. Untrusted pull request runs from branches or forks cannot access Themis's token.
- **Fail-Closed Conjunct Integrity:** All 11 conjuncts in `scripts/ci/merge_gate.sh` remain inviolate. No special exemption or bypass is added to `merge_gate.sh` for workflow files; the fix provides the legitimate credential authority required by GitHub.
- **Operator Action Separation:** Granting permissions to an existing GitHub App requires web UI approval on GitHub.com; software automation cannot unilaterally elevate its own App permissions without human owner consent.
- **Standard 5-Rung SDLC Lifecycle:** At this PLAN stage, only `intent/437-themis-github-app-lacks/intent.md` is authored. Manifest edits, code changes, and live permission changes are deferred to DESIGN (`spec.md`), BUILD (`plan.md`), and IMPLEMENT stages.

## Relationships

- **Directly unblocks PR #427:** Implementing #410 (`CHANGELOG.md` with hard CI merge gate), currently blocked on `mergeStateStatus: BLOCKED`.
- **Extends #64 (Autonomous Loop):** Clarifies and completes the required GitHub App permissions for Themis as the autonomous merge actor.
- **Relies on #7 (`scripts/auth`):** GitHub App manifests and provisioning infrastructure.
- **Distinct from #298 and #308:** Resolves token-level authorization rather than CI job roll-up or concurrency cancellation.

## Open questions

1. **Operator Grant Procedure & Verification:** What is the exact sequence of clicks for the operator on GitHub.com to update `evekhm-themis-app` permissions and accept them on the repository? Can `create_all_apps.py --check` be extended to verify whether the live installation currently holds `workflows: write`?
2. **Permission Granularity:** Does GitHub offer any permission narrower than repository-level `Workflows: Read and write` for App tokens that merge workflow changes?
3. **Verification in IMPLEMENT stage:** How should the implementation test prove the fix? Is re-dispatching `merge-gate.yml` on PR #427 sufficient end-to-end evidence, or should a contract test/script verify Themis token capabilities directly?
4. **Persona Push Isolation:** Should `AGENTS.md` or `docs/SPEC.md` reaffirm that persona Apps continue to be denied `workflows: write` (and must use the bot PAT or human intervention if pushing workflow changes)?
5. **Living Spec Language:** What is the precise text diff for `docs/SPEC.md` under `### loop.autonomous`?
