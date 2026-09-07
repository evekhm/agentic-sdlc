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
Run `bash scripts/ci/tests/unattended_issues_test.sh` to automatically verify forms match spec (D22, D23, D24, D25).

---

## T2 · Lifecycle stage for bug and tracker bootstrap — D2, D3, D26

Touch: `personas/lifecycle.json`, `scripts/setup/bootstrap_tracker.sh`, `scripts/ci/compiler_roundtrip.sh`, `scripts/sync_agents.py`, `.claude/agents/**`, `.agents/agents/**`

### Details
1. Append the `maintain` row to `personas/lifecycle.json` (as the 6th row, after `status:in-review`): `stage: maintain`, `label: bug`, `dispatch_brief` per D2, and `artifact, advances_on, advances_to, advance_message` all `null`. Update `_comment` to explain `status:*` rows vs off-ladder rows.
2. In `scripts/setup/bootstrap_tracker.sh` (lines 103-107): Add `ensure_label "bug" "d73a4a" "A reported defect in this system: routed to the maintainer; not a ladder rung"`.
3. In `scripts/sync_agents.py`: Modify `load_lifecycle()` (lines 210-325). Filter terminal-ness checking over rows where `label.startswith("status:")`. Require that off-ladder rows have `artifact`, `advances_on`, `advances_to` all null and sit after the last `status:*` row.
4. In `scripts/ci/compiler_roundtrip.sh` step 7: Append two test fixtures (asserting non-null advances_to off-ladder refusal, and position error refusal).

### Verification
- `jq -e '.stages | length == 6' personas/lifecycle.json` passes.
- Run `python3 scripts/sync_agents.py`, commit the targets, then verify `python3 scripts/sync_agents.py --check` passes. (D3: Two consecutive builds are byte-identical, and sync_agents.py is changed in exactly one function, load_lifecycle, and its renderer is untouched)
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
- Verify removing the `issues:` key from `unattended.yml` makes `execution.py --check` exit 1 with a message naming `issues` (D11).
- Verify parsed bindings for `athena` and `cassandra` have key sets that are subsets of `{trigger, events, placement, max_cost_usd}` (D12).

---

## T4 · Triage script — D13, D16, D17, D18, D19, D20, D21

Touch: `scripts/ci/intake_triage.sh`

### Details
1. Create `scripts/ci/intake_triage.sh` that takes exactly `<issue-number>`.
2. Handle reads (D13, D15, D16): Read issue using `gh issue view $NUMBER --json labels,state`. If `state==CLOSED`, `hold` is present, or neither `intent:new` nor `bug` are present, exit 0 (D13, D15, D19). Fetch comments with `gh api repos/{owner}/{repo}/issues/{number}/comments --paginate` and check for HTML marker `<!-- intake-triage:$NUMBER -->`. If found, exit 0 (D16).
3. Check required sections (D18):
   - For `intent:new`: check `Problem` and `Proposed outcome`.
   - For `bug`: check `What happened`, `What you expected`, `Severity`.
   - Formulate `Required sections:` string for any missing sections.
4. Search prior art (D20): Derive query terms from title by lowercasing, replacing non-alphanumerics with space, dropping words under 4 characters and stopwords, deduplicating (keeping first occurrence), capping at 6 terms, and joining with ` OR `. Stopword list must live on one line in the script.
   - If zero terms are yielded, no searches run, exit 0, and write D17's third form verbatim: `**Prior art:** not searched — the title yielded no term of 4 characters or more.`
   - Run `gh search issues` and `gh search prs` without `--state` flag, with `--limit 10`. Tag output matches `(open)` or `(closed)`.
   - Grep `intent/*/` where a directory matches if its slug shares at least one hyphen-separated component with a term. Exclude the triaged issue's own number.
   - Exit 1 with no write if any of the three sources fails (D13, D20).
   - Format `Prior art:` string.
5. Apply writes: Re-read labels (D13) immediately before writes. Apply `blocked` label via `gh issue edit $NUMBER --add-label blocked` if sections missing (D18). Format comment per verbatim spec, add marker `<!-- intake-triage:$NUMBER -->` to the end, post via `gh issue comment $NUMBER --body-file` (D16, D17, D21).
   - Exit table (D13): 0 = triaged or deliberately did nothing; 1 = unusable input, failed read, failed write.
   - Respect `DRY_RUN=1` (parity required: every read in the invocation log is identical to the non-dry run's).

### Verification
Run `bash scripts/ci/tests/intake_triage_test.sh` (emitted contract tests).

---

## T5 · Unattended workflow modifications — D6, D8, D9, D10, D14, D15

Touch: `.github/workflows/unattended.yml`, `.github/workflows/ci-gates.yml`

### Details
1. In `.github/workflows/unattended.yml`:
   - `on:` Add `issues: types: [opened]` (D6, D7).
   - Add `triage` job (D14): `if: github.event_name == 'issues' && github.event.issue.user.type != 'Bot'` (D9). Set permissions `contents: read`, `issues: write` (D14). Env: `NUMBER: ${{ github.event.pull_request.number || github.event.issue.number || inputs.number }}`. Step: `bash scripts/ci/intake_triage.sh "$NUMBER"`. No `${{` in `run:` body.
   - Modify `resolve` job: add `needs: triage`. Set `"!cancelled() && ( (github.event_name == 'issues' && github.event.issue.user.type != 'Bot' && needs.triage.result == 'success') || (github.event_name != 'issues' && (github.event_name == 'workflow_dispatch' || github.event.pull_request.head.repo.full_name == github.repository)) )"` (D8, D14).
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
- Verify no literal `bug`-to-stage mapping exists in `scripts/` (provable by editing that row's label in a fixture copy of the JSON and watching derivation follow it) (D2, D4).

---

## T7 · Test suite deltas and SPEC.md upsert — D1, D27

Touch: `scripts/ci/tests/lifecycle_advance_test.sh`, `scripts/ops/tests/execution_test.sh`, `scripts/ops/tests/work_test.sh`, `docs/SPEC.md`

### Details
1. `lifecycle_advance_test.sh`: Line 403 `== 5` becomes `== 6`. Update banner (:402), fail message (:404), and pass line (:405) to mention six rungs.
2. `execution_test.sh`: Update lines ~69, ~76, ~91-93, ~98-99 to expect 6 bindings, list `cassandra` and `athena` in issues output, and expect exit 0 / printed binding instead of exit 1 for cassandra.
3. `work_test.sh`: Update the #129 block (:599-611) strings. Replace "refused: cannot derive a stage for #140" with D5(f) refusal strings for argus/atlas, replace "no status:* label and no intent:new" with owner clause "owners: cassandra". Add D4 scenarios (bug derives maintain, bug+spec derives design, two off-ladder refuse, no label refuse). Add D1 scenario: DRY_RUN=1 scripts/ops/work.sh <pr> --as argus on a bug issue exits 2 green naming cassandra as owner (D1).
4. `docs/SPEC.md`: Upsert `intake.triage` per spec. Amend `lifecycle.labels` (15 labels), `tracker.provisioning` (count), `ops.dispatch` (nine refusals) at `docs/SPEC.md:451`, `personas.resume` (five rungs) at `docs/SPEC.md:194`, and `execution.placement` (cassandra cadence) at `docs/SPEC.md:736` and `:757-759`.
5. Include `Spec-impact: docs/SPEC.md: added intake.triage, amended intent, intent.new, issue.state, deterministic (D27)` in the implementing PR.

### Verification
`bash scripts/ci/tests/lifecycle_advance_test.sh` passes.
`bash scripts/ops/tests/execution_test.sh` passes.
`bash scripts/ops/tests/work_test.sh` passes.
`bash scripts/ci/spec_check.sh origin/main` passes.
