# Plan: typed intake — issue forms, triage, bug door

**Issue:** #117 · **Spec:** spec.md (Approved) · **Author:** daedalus (`evekhm-daedalus-app[bot]`)

Seven tasks. Each names the files it touches, the Decision rows it
satisfies, and the check that proves it. Line numbers cite HEAD on `origin/main`.

**Order.**
T1 (forms) → T2 (lifecycle row & bug bootstrap) → T3 (execution bindings)
→ T4 (triage script) → T5 (unattended workflow) → T6 (stage derivation)
→ T7 (test suite deltas & spec upsert).

---

## T1 · Issue forms and config in `.github/ISSUE_TEMPLATE/` — D22, D23, D24, D25

Touch: `.github/ISSUE_TEMPLATE/intent.yml`, `.github/ISSUE_TEMPLATE/bug.yml`, `.github/ISSUE_TEMPLATE/config.yml`

### Details
1. Create `config.yml`: `blank_issues_enabled: false` and no contact links.
2. Create `intent.yml`:
   - `labels: [intent:new]`
   - Intro markdown (renders nothing to body).
   - Textareas with matching labels (byte-for-byte heading match to `intent.md` sections): `Problem` (required: true), `Proposed outcome` (required: true), `Affected users and systems`, `Constraints`, `Open questions`.
   - No `title:` prefix, no checkboxes. Field ids are lowercased label strings with non-alphanumerics replaced by `-`.
3. Create `bug.yml`:
   - `labels: [bug]`
   - Intro markdown.
   - Textareas: `What happened` (required: true), `What you expected` (required: true), `Evidence` (mentioning sanitize rules).
   - Input: `Persona or script involved`.
   - Dropdown: `Severity` (required: true) with options `blocks the loop`, `degrades a rung`, `cosmetic`.
   - No `title:` prefix, no checkboxes. Field ids follow the same rule.

### Verification
Run `bash scripts/ci/sanitize_check.sh`.
Review forms in GitHub UI to ensure labels, requirements, and headings match spec.

---

## T2 · Lifecycle stage for bug and tracker bootstrap — D2, D3, D26

Touch: `personas/lifecycle.json`, `scripts/setup/bootstrap_tracker.sh`, `scripts/ci/compiler_roundtrip.sh`, `scripts/sync_agents.py`

### Details
1. Append the `maintain` row to `personas/lifecycle.json` (as the 6th row, after `status:in-review`): `stage: maintain`, `label: bug`, `dispatch_brief` per D2, and `artifact, advances_on, advances_to, advance_message` all `null`. Update `_comment` to explain `status:*` rows vs off-ladder rows.
2. In `scripts/setup/bootstrap_tracker.sh` (around line ~20): Add `ensure_label "bug" "d73a4a" "A reported defect in this system: routed to the maintainer; not a ladder rung"`.
3. In `scripts/sync_agents.py`: Modify `load_lifecycle()` (lines 210-325). Filter terminal-ness checking over rows where `label.startswith("status:")`. Require that off-ladder rows have `artifact`, `advances_on`, `advances_to` all null and sit after the last `status:*` row.
4. In `scripts/ci/compiler_roundtrip.sh` step 7: Append two test fixtures (asserting non-null advances_to off-ladder refusal, and position error refusal).

### Verification
- `jq -e '.stages | length == 6' personas/lifecycle.json` passes.
- `python3 scripts/sync_agents.py --check` passes and generated personas are updated.
- `scripts/ci/compiler_roundtrip.sh` passes.

---

## T3 · Execution bindings — D11, D12

Touch: `config/execution.yaml`

### Details
1. Update `athena` in `config/execution.yaml`: Set `trigger: repo-event` and `events: [issues]`.
2. Add `cassandra` binding: Set `trigger: repo-event` and `events: [issues]`.
(Keep placement/max_cost_usd values per user config, do not modify them).

### Verification
`python3 scripts/ops/execution.py --check` passes.
`python3 scripts/ops/execution.py --subscribers issues` outputs `athena` and `cassandra` sorted.

---

## T4 · Triage script — D13, D16, D17, D18, D19, D20, D21

Touch: `scripts/ci/intake_triage.sh`

### Details
1. Create `scripts/ci/intake_triage.sh` that takes exactly `<issue-number>`.
2. Handle reads (D13, D15, D16): Read issue using `gh issue view $NUMBER --json number,title,state,labels,comments,body`. If `state==CLOSED`, `hold` is present, or neither `intent:new` nor `bug` are present, exit 0 (D15, D19). Check comments for HTML marker `<!-- intake-triage:$NUMBER -->`. If found, exit 0 (D16).
3. Check required sections (D18):
   - For `intent:new`: check `Problem` and `Proposed outcome`.
   - For `bug`: check `What happened`, `What you expected`, `Severity`.
   - Apply `blocked` label via `gh issue edit $NUMBER --add-label blocked` if any are missing/empty. Formulate `Required sections:` string.
4. Search prior art (D20): Extract query words >= 4 chars, remove stopwords. Run `gh search issues` and `gh search prs` without `--state`. Grep `intent/*/`. Format `Prior art:` string. Exit 1 if any `gh search` fails.
5. Create comment text (D17, D21): Format comment per verbatim spec, add marker, post via `gh issue comment $NUMBER --body-file`. Re-read labels before writing (D15). Respect `DRY_RUN=1`.

### Verification
Run `bash scripts/ci/tests/intake_triage_test.sh` (emitted contract tests).

---

## T5 · Unattended workflow modifications — D6, D8, D9, D10, D14, D15

Touch: `.github/workflows/unattended.yml`, `.github/workflows/ci-gates.yml`

### Details
1. In `.github/workflows/unattended.yml`:
   - `on:` Add `issues: types: [opened]` (D6, D7).
   - Add `triage` job (D14): `if: github.event_name == 'issues' && github.event.issue.user.type != 'Bot'` (D9). Set permissions `contents: read`, `issues: write` (D15). Env: `NUMBER: ${{ github.event.issue.number }}`. Step: `bash scripts/ci/intake_triage.sh "$NUMBER"`. No `${{` in `run:` body.
   - Modify `resolve` job: add `needs: triage`. Set `if: !cancelled() && ( (github.event_name == 'issues' && github.event.issue.user.type != 'Bot' && needs.triage.result == 'success') || (github.event_name != 'issues' && (github.event_name == 'workflow_dispatch' || github.event.pull_request.head.repo.full_name == github.repository)) )` (D8, D14).
   - Update `NUMBER` env and `concurrency.group` to check `github.event.issue.number` (D10).
2. In `.github/workflows/ci-gates.yml`: Add `scripts/ci/tests/intake_triage_test.sh` and `scripts/ci/tests/unattended_issues_test.sh` to the `execution` job run scripts.

### Verification
Run `bash scripts/ci/tests/unattended_issues_test.sh`.

---

## T6 · Stage derivation in tools — D4, D5, D28

Touch: `personas/skills/resume-protocol.md`, `scripts/ops/work.sh`, `scripts/ops/smoke_launch.sh`

### Details
1. In `scripts/ops/work.sh`: Add a third arm to stage derivation (D4). If exactly one off-ladder label matches a lifecycle row, use that stage. Two off-ladder labels refuse, zero off-ladder labels refuse with "and no label naming an off-ladder rung".
2. In `scripts/ops/smoke_launch.sh`: Update the two `.stages[]` `jq` queries (lines ~257-272, ~691-700) to `select(.label | startswith("status:"))` (D28). Update the comment at 258-260 to explain exclusion by filter instead of "absent by construction".
3. In `personas/skills/resume-protocol.md`: Add sentence to step 3: "An issue carrying no `status:*` label and exactly one label that a lifecycle row names off the ladder is at that row's stage." (D5).

### Verification
`bash scripts/ops/tests/smoke_launch_test.sh` passes.
`python3 scripts/sync_agents.py --check` passes after rebuild.

---

## T7 · Test suite deltas and SPEC.md upsert — D27

Touch: `scripts/ci/tests/lifecycle_advance_test.sh`, `scripts/ops/tests/execution_test.sh`, `scripts/ops/tests/work_test.sh`, `docs/SPEC.md`

### Details
1. `lifecycle_advance_test.sh`: Line 403 `== 5` becomes `== 6`. Update banner (:402), fail message (:404), and pass line (:405) to mention six rungs.
2. `execution_test.sh`: Update lines ~69, ~76, ~91-93, ~98-99 to expect 6 bindings, list `cassandra` and `athena` in issues output, and expect exit 0 / printed binding instead of exit 1 for cassandra.
3. `work_test.sh`: Update the #129 block (:599-611) strings. Replace "refused: cannot derive a stage for #140" with D5(f) refusal strings for argus/atlas, replace "no status:* label and no intent:new" with owner clause "owners: cassandra". Add D4 scenarios (bug derives maintain, bug+spec derives design, two off-ladder refuse, no label refuse).
4. `docs/SPEC.md`: Upsert `intake.triage` per spec. Amend `lifecycle.labels` (15 labels), `tracker.provisioning` (count), `ops.dispatch` (nine refusals), `personas.resume`, and `execution.placement`. Keep `intake.automation` in Agreed/not yet built.

### Verification
`bash scripts/ci/tests/lifecycle_advance_test.sh` passes.
`bash scripts/ops/tests/execution_test.sh` passes.
`bash scripts/ops/tests/work_test.sh` passes.
`bash scripts/ci/spec_check.sh origin/main` passes.
