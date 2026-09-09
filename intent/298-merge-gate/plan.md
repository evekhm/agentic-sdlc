# Plan: merge gate conjunct 2 and refs-only pull request resolution

**Issue:** #298 · **Spec:** spec.md (Approved, D1–D9, AT-1..AT-14) ·
**Author:** daedalus (`evekhm-daedalus-app[bot]`)

Eight tasks. Each names the files it touches, the steps in order, the
Decision rows it implements, the acceptance tests it makes pass, and
its done-when. **Implement on top of `origin/main` at the SHA the
dispatcher pins; this plan was verified at `696f516`.** Every
`file:line` below was re-read at that commit.

Order: T1 (tests, all red) → T2 (`merge-gate-evaluate.yml` + `merge-gate.yml`) →
T3 (`ci-gates.yml`) → T4 (`lib/github.sh`) → T5 (`merge_gate.sh` issue resolution) →
T6 (`merge_gate.sh` check deduplication) → T7 (`docs/SPEC.md`) → T8 (gates).
T2 through T6 each turn part of T1's suite green and none of them is green alone;
T7 commutes with T2–T6; T8 needs all seven.

---

## The six calls this plan makes

The spec left these to the plan. Each is decided here; the
implementer does not re-open them.

**P1 · Rollup deduplication in `scripts/ci/merge_gate.sh` queries `databaseId` on `CheckRun` and deduplicates by check name / context.**
In `read_merge_state()`, update `GRAPHQL_ROLLUP` to request `databaseId` on `CheckRun`:
`... on CheckRun{name conclusion status databaseId checkSuite{workflowRun{databaseId}}}`.
`CHECKS_TSV` extracts 5 tab-separated fields: `name`, `status/conclusion`, `workflow_run_id`, `database_id`, and `__typename`.
When evaluating conjunct 2:
1. Exclude the gate's own run by identity: filter out records where `workflow_run_id == GITHUB_RUN_ID` (D24).
2. For remaining foreign records, deduplicate by check name (or context for StatusContext): when multiple entries have the same name, select the entry with the highest numeric `database_id` (or the last entry in document order if `database_id` is empty), representing the latest run of that check.
3. Conjunct 2 evaluates the deduplicated set of latest checks: all must have conclusion/state `SUCCESS`. If empty, conjunct 2 fails (`mergeStateStatus $MERGE_STATE but no check besides the gate's own run`). If any check in the latest set is not `SUCCESS` (e.g. `CANCELLED`, `FAILURE`, `PENDING`), conjunct 2 is false.

**P2 · Strict single-issue union in `scripts/ops/lib/github.sh` (`resolve_issue`).**
In `scripts/ops/lib/github.sh`, define helper `issue_refs()` matching `(^|[^[:alnum:]])(refs?|references?|close[sd]?|fix(es|ed)?|resolve[sd]?)[[:space:]]+#[0-9]+`.
In `resolve_issue()`, extract all issue numbers mentioned in the body (via `issue_refs`) and the issue number from the head branch name (via `branch_issue`, matching `^[a-z][a-z-]*/([0-9]+)-`).
Union both sets of numbers (`sort -un`).
- If union count == 0: `return 2` (`cannot resolve PR #n to an issue`).
- If union count > 1: `die "PR #$number links more than one issue: $(sed 's/^/#/' <<<"$union" | tr '\n' ' ')— dispatch one of them by its own number"`.
- If union count == 1: `ISSUE` is the single issue number. `RESOLVED_VIA` is assigned:
  - `"Closes #$ISSUE in the body"` if matched closing keywords in body;
  - `"Refs #$ISSUE in the body"` if matched reference keywords in body;
  - `"the branch name $BRANCH_REF"` if derived solely from the branch name.

**P3 · Harmonized issue extraction and single-issue union in `scripts/ci/merge_gate.sh`.**
In `scripts/ci/merge_gate.sh`, extract issue numbers from `closingIssuesReferences`, body matching the same regex `(^|[^[:alnum:]])(refs?|references?|close[sd]?|fix(es|ed)?|resolve[sd]?)[[:space:]]+#[0-9]+`, and head branch matching `^[a-z][a-z-]*/([0-9]+)-`.
Union all extracted numbers into `LINKED` (`sort -un`).
- If union count == 0: `finish "no linked issue on #$PR (no closing reference, no \`Refs #n\`, no <actor>/<n>-<slug> branch) — not a ladder pull request; nothing evaluated, nothing written"` (exit 0).
- If union count > 1: `decline "#$PR links two different issues ($(tr '\n' ' ' <<<"$LINKED" | sed 's/ $//' | sed 's/\([0-9][0-9]*\)/#\1/g')) — corrupted input, nothing written"` (exit 0, decline).
- If union count == 1: `ISSUE="$LINKED"`.

**P4 · Scoped concurrency group in `.github/workflows/ci-gates.yml`.**
Update line 41 of `.github/workflows/ci-gates.yml` to:
`group: ci-gates-${{ github.event.pull_request.number || github.ref }}-${{ github.event.pull_request.head.sha || github.sha }}`.
This ensures runs on older commit SHAs can be cancelled in progress without cancelling runs for new commit pushes.

**P5 · Workflow separation: `merge-gate-evaluate.yml` dedicated to pull requests.**
Extract the `evaluate` job from `.github/workflows/merge-gate.yml` into new workflow `.github/workflows/merge-gate-evaluate.yml`.
`.github/workflows/merge-gate.yml` removes `pull_request` from its `on:` triggers, leaving only `check_suite`, `status`, `issue_comment`, and `workflow_dispatch`.
The `evaluate` job is removed from `merge-gate.yml`.
Job conditions on `record` and `gate` in `merge-gate.yml` simplify to `github.event_name != 'issue_comment' || github.event.issue.pull_request`.
Zero skipped check runs are created on pull request heads.

**P6 · Verbatim `docs/SPEC.md` updates.**
Drafted verbatim in T7 for both `### loop.autonomous` and `### ops.dispatch`.

---

## T1 · The acceptance suite, written first and all red — AT-3..AT-6, AT-8..AT-13

Touch: `scripts/ci/tests/merge_gate_test.sh`, `scripts/ops/tests/work_test.sh`.

### 1a · Extend `scripts/ci/tests/merge_gate_test.sh` GraphQL stub for `databaseId`

In `scripts/ci/tests/merge_gate_test.sh`:
1. Update `row()` helper at line 265:
   ```bash
   row() { printf '%s|%s|%s|%s|%s' "$1" "$2" "$3" "$4" "${5:-}"; } # <type> <name> <val> <runid> [dbid]
   ```
2. Update GraphQL mock response builder around lines 133-146:
   ```bash
       if [ -f "$FX/mergestate-$pr.checks" ]; then
         checks_json="$(while IFS='|' read -r ty name val runid dbid; do
           [ -n "$ty" ] || continue
           if [ "$ty" = check ]; then
             if [ -n "$runid" ] && [ -n "$dbid" ]; then
               jq -nc --arg n "$name" --arg c "$val" --argjson r "$runid" --argjson d "$dbid" \
                 '{__typename:"CheckRun", name:$n, conclusion:$c, databaseId:$d, checkSuite:{workflowRun:{databaseId:$r}}}'
             elif [ -n "$runid" ]; then
               jq -nc --arg n "$name" --arg c "$val" --argjson r "$runid" \
                 '{__typename:"CheckRun", name:$n, conclusion:$c, databaseId:null, checkSuite:{workflowRun:{databaseId:$r}}}'
             elif [ -n "$dbid" ]; then
               jq -nc --arg n "$name" --arg c "$val" --argjson d "$dbid" \
                 '{__typename:"CheckRun", name:$n, conclusion:$c, databaseId:$d, checkSuite:{workflowRun:null}}'
             else
               jq -nc --arg n "$name" --arg c "$val" \
                 '{__typename:"CheckRun", name:$n, conclusion:$c, databaseId:null, checkSuite:{workflowRun:null}}'
             fi
           else
             jq -nc --arg n "$name" --arg s "$val" '{__typename:"StatusContext", context:$n, state:$s}'
           fi
         done < "$FX/mergestate-$pr.checks" | jq -s .)"
       fi
   ```

### 1b · Add scenarios MG-31 through MG-36 to `scripts/ci/tests/merge_gate_test.sh`

Add test scenarios at the end of `scripts/ci/tests/merge_gate_test.sh`:

```bash
banner "MG-31 · D3 · check roll-up deduplication: superseded CANCELLED check superseded by newer SUCCESS passes conjunct 2"
mk_green
mergestate_checks 123 \
  "$(row check merge-gate '' 999 500)" \
  "$(row check 'execution — bindings' CANCELLED 1001 2001)" \
  "$(row check 'execution — bindings' SUCCESS 1002 2002)" \
  "$(row status 'argus via gh-actions' SUCCESS '' '')"
run "MG-31: exits 0" 123
has "conjunct (2): true" "MG-31: superseded cancelled check resolved by newer success passes (2)"
merged "MG-31: and the merge proceeds"

banner "MG-32 · D3 · check roll-up deduplication: superseded SUCCESS check superseded by newer FAILURE fails conjunct 2"
mk_green
mergestate_checks 123 \
  "$(row check merge-gate '' 999 500)" \
  "$(row check 'execution — bindings' SUCCESS 1001 2001)" \
  "$(row check 'execution — bindings' FAILURE 1002 2002)" \
  "$(row status 'argus via gh-actions' SUCCESS '' '')"
run "MG-32: exits 0" 123
has "conjunct (2): false" "MG-32: superseded success check overridden by newer failure fails (2)"
has "execution — bindings=FAILURE" "MG-32: names the failing check"
not_merged "MG-32"

banner "MG-33 · D3 · check roll-up deduplication: pending check in roll-up fails conjunct 2"
mk_green
mergestate_checks 123 \
  "$(row check merge-gate '' 999 500)" \
  "$(row check 'execution — bindings' '' 1001 2001)" \
  "$(row status 'argus via gh-actions' SUCCESS '' '')"
run "MG-33: exits 0" 123
has "conjunct (2): false" "MG-33: pending check fails (2)"
has "execution — bindings=PENDING" "MG-33: names the pending check"
not_merged "MG-33"

banner "MG-34 · D3 · gate's own run excluded by workflow run id, foreign check named merge-gate counts"
mk_green
mergestate_checks 123 \
  "$(row check merge-gate SUCCESS 999 500)" \
  "$(row check merge-gate FAILURE 1001 2003)" \
  "$(row check 'execution — bindings' SUCCESS 1002 2002)"
run "MG-34: exits 0" 123
has "conjunct (2): false" "MG-34: foreign check named merge-gate counts and fails"
has "merge-gate=FAILURE" "MG-34: names the failing foreign check"
not_merged "MG-34"

banner "MG-35 · D6 · pull request linking conflicting issues declines as corrupted input"
mk_green
PR_BODY="Refs #100"
PR_HEADREF="odyssey/200-slug"
pr_fixture 123
run "MG-35: exits 0" 123
has "corrupted input, nothing written" "MG-35: conflicting issues declines"
has "#100" "MG-35: names first conflicting issue"
has "#200" "MG-35: names second conflicting issue"
not_merged "MG-35"

banner "MG-36 · D7 · unlinked pull request exits 0 without evaluation or writes"
mk_green
PR_BODY="Routine maintenance with no issue references"
PR_HEADREF="ops/routine-maintenance"
pr_fixture 123
run "MG-36: exits 0" 123
has "not a ladder pull request; nothing evaluated, nothing written" "MG-36: unlinked PR skips cleanly"
not_merged "MG-36"
```

### 1c · Add test scenarios to `scripts/ops/tests/work_test.sh`

In `scripts/ops/tests/work_test.sh`, immediately following line 534:

```bash
banner "D5/D8 a PR with Refs #n in body resolves to its issue"
pr 130 "Refs #108" "ops/flip-flag"
run 0 "D5/D8: 'Refs #108' resolves the issue on an operator branch" -- 130
has "resolved from #130 via Refs #108" "D5/D8: Refs #n resolves the issue"
has "==> #108" "D5/D8: the referenced issue is the unit of work"

banner "D5 review dispatch on ladder PR with Refs #n in body"
issue 131 open "status:build" "Ladder issue"
pr 132 "Refs #131" "athena/131-slug"
run 0 "D5: review dispatch on ladder PR with Refs #131 succeeds" -- 132 --as argus
has "stage:    review" "D5: reviewer dispatches at review stage"
has "#131" "D5: resolves to issue 131"

banner "D6 a PR linking conflicting issues fails as corrupted input"
pr 133 "Refs #100" "odyssey/200-slug"
run 1 "D6: conflicting body and branch issues exits 1" -- 133
has "links more than one issue" "D6: conflicting issues fails as corrupted input"
has "#100" "D6: names body issue"
has "#200" "D6: names branch issue"

banner "D6/D8 an unlinked PR on an operator branch exits 2"
pr 134 "No issue references anywhere" "ops/no-issue"
run 2 "D6/D8: unlinked operator branch exits 2" -- 134
has "refused: cannot resolve PR #134 to an issue" "D6/D8: refusal condition named"
```

Done when: Running `bash scripts/ci/tests/merge_gate_test.sh` and `bash scripts/ops/tests/work_test.sh` fails on the new test scenarios (red), confirming the absence of behavior before implementation.

---

## T2 · Dedicated evaluate workflow and merge gate trigger clean-up (D1, D2, AT-1, AT-2)

Touch: `.github/workflows/merge-gate-evaluate.yml` (new file), `.github/workflows/merge-gate.yml`.

### 2a · Create `.github/workflows/merge-gate-evaluate.yml`

Create `.github/workflows/merge-gate-evaluate.yml` with contents:

```yaml
# Merge Gate Evaluate (#298, D1): read-only dry-run evaluation on pull request events.
# Runs with the default token, read-only, DRY_RUN=1. Creates exactly one check run
# `merge-gate (evaluate)` with conclusion SUCCESS. Zero skipped check runs on PR head.
name: Merge Gate Evaluate

on:
  pull_request:
    types: [opened, synchronize, reopened]

permissions: {}

jobs:
  evaluate:
    name: merge-gate (evaluate)
    runs-on: ubuntu-latest
    timeout-minutes: 10
    permissions:
      contents: read
      pull-requests: read
      issues: read
      checks: read
      statuses: read
    steps:
      - name: Fail closed unless the base is the default branch
        env:
          BASE_REF: ${{ github.base_ref }}
        run: |
          if [ "$BASE_REF" != "main" ]; then
            echo "::error::merge-gate: the pull request's base is '$BASE_REF'; only main is gated (D5 conjunct 1)"
            exit 1
          fi

      - name: Checkout the default branch
        uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4
        with:
          ref: main
          fetch-depth: 1

      - name: Evaluate the eleven conjuncts (dry run, no writes)
        env:
          GH_TOKEN: ${{ github.token }}
          DRY_RUN: "1"
          TARGET: ${{ github.event.pull_request.number }}
        run: |
          if [ ! -f scripts/ci/merge_gate.sh ]; then
            echo "scripts/ci/merge_gate.sh is not on main — nothing to evaluate"
            exit 0
          fi
          bash scripts/ci/merge_gate.sh "$TARGET"
```

### 2b · Update `.github/workflows/merge-gate.yml`

In `.github/workflows/merge-gate.yml`:
1. Remove `pull_request` trigger from `on:` (lines 25-26).
2. Remove the `evaluate` job entirely (lines 42-80).
3. Update `record` job condition (line 83) to:
   ```yaml
   if: github.event_name != 'issue_comment' || github.event.issue.pull_request
   ```
4. Update `gate` job condition (line 147) to:
   ```yaml
   if: ${{ always() && (github.event_name != 'issue_comment' || github.event.issue.pull_request) }}
   ```
5. Update header comments (lines 6-13) to document that `evaluate` lives in `.github/workflows/merge-gate-evaluate.yml` and `merge-gate.yml` runs mutating jobs on main-ref events only.

Done when: `git diff .github/workflows/` shows `merge-gate-evaluate.yml` added and `merge-gate.yml` stripped of `pull_request` triggers and `evaluate` job; YAML syntax is valid.

---

## T3 · Concurrency scoping in CI gates workflow (D4, AT-7)

Touch: `.github/workflows/ci-gates.yml`.

Update line 41 of `.github/workflows/ci-gates.yml` from:
```yaml
concurrency:
  group: ci-gates-${{ github.event.pull_request.number || github.ref }}
  cancel-in-progress: true
```
to:
```yaml
concurrency:
  group: ci-gates-${{ github.event.pull_request.number || github.ref }}-${{ github.event.pull_request.head.sha || github.sha }}
  cancel-in-progress: true
```

Done when: `.github/workflows/ci-gates.yml` concurrency group includes the head commit SHA.

---

## T4 · Issue resolution in ops library (`lib/github.sh`) (D5, D6, D8, AT-8, AT-9, AT-10, AT-12)

Touch: `scripts/ops/lib/github.sh`.

In `scripts/ops/lib/github.sh`:
1. Add `issue_refs()` function replacing or alongside `closing_refs()`:
   ```bash
   # issue_refs <pr-body> — distinct same-repo issue numbers extracted from
   # closing keywords and reference mentions, one per line, sorted.
   issue_refs() {
       grep -Eoi '(^|[^[:alnum:]])(refs?|references?|close[sd]?|fix(es|ed)?|resolve[sd]?)[[:space:]]+#[0-9]+' <<<"$1" \
           | grep -Eo '[0-9]+$' | sort -un || true
   }
   ```
2. In `resolve_issue()` (lines 125-142), rewrite issue extraction to union body references and branch name:
   ```bash
       branch_issue "$number" || true
       local body_refs branch_refs union union_count
       body_refs="$(issue_refs "$(jq -r '.body // ""' <<<"$view")")"
       branch_refs=""
       [ -z "$BRANCH_ISSUE" ] || branch_refs="$BRANCH_ISSUE"
       union="$(printf '%s\n%s\n' "$body_refs" "$branch_refs" | grep -E '^[0-9]+$' | sort -un || true)"
       union_count=0
       [ -z "$union" ] || union_count="$(grep -c . <<<"$union")"

       if [ "$union_count" -gt 1 ]; then
           die "PR #$number links more than one issue: $(sed 's/^/#/' <<<"$union" | tr '\n' ' ')— dispatch one of them by its own number"
       fi
       if [ "$union_count" -eq 0 ]; then
           return 2
       fi

       ISSUE="$union"
       closes="$(closing_refs "$(jq -r '.body // ""' <<<"$view")")"
       if grep -qxE "$ISSUE" <<<"$closes"; then
           RESOLVED_VIA="Closes #$ISSUE in the body"
       elif grep -qxE "$ISSUE" <<<"$body_refs"; then
           RESOLVED_VIA="Refs #$ISSUE in the body"
       else
           RESOLVED_VIA="the branch name $BRANCH_REF"
       fi
   ```

Done when: `bash scripts/ops/tests/work_test.sh` passes scenarios D5/D8, D5, D6, and D6/D8 green.

---

## T5 · Harmonized issue resolution in merge gate (`merge_gate.sh`) (D6, D7, AT-11, AT-13)

Touch: `scripts/ci/merge_gate.sh`.

In `scripts/ci/merge_gate.sh` (lines 102-115), rewrite issue resolution to enforce single-issue union:
```bash
# --- which issue this pull request belongs to (#245, #298) -------------------------
# GitHub's own closing references, closing keywords and `refs` in the body,
# and the <actor>/<n>-<slug> branch name are unioned. More than one issue is
# corrupted input; zero is a pull request outside the ladder (exit 0).
HEAD_REF="$(prq '.headRefName // ""')"
BRANCH_LINKED=""
if [[ "$HEAD_REF" =~ ^[a-z][a-z-]*/([0-9]+)- ]]; then BRANCH_LINKED="${BASH_REMATCH[1]}"; fi

LINKED="$( { prq '[.closingIssuesReferences[]?.number] | .[]';
             prq '.body // ""' | grep -Eoi '(^|[^[:alnum:]])(refs?|references?|close[sd]?|fix(es|ed)?|resolve[sd]?)[[:space:]]+#[0-9]+' | grep -Eo '[0-9]+$';
             printf '%s\n' "$BRANCH_LINKED"; } | grep -E '^[0-9]+$' | sort -un || true)"
n_linked="$(grep -c . <<<"$LINKED" || true)"
if [ "$n_linked" -gt 1 ]; then
    decline "#$PR links two different issues ($(tr '\n' ' ' <<<"$LINKED" | sed 's/ $//' | sed 's/\([0-9][0-9]*\)/#\1/g')) — corrupted input, nothing written"
fi
if [ "$n_linked" -eq 0 ]; then
    finish "no linked issue on #$PR (no closing reference, no \`Refs #n\`, no <actor>/<n>-<slug> branch) — not a ladder pull request; nothing evaluated, nothing written"
fi
ISSUE="$LINKED"
```

Done when: `bash scripts/ci/tests/merge_gate_test.sh` scenarios MG-35 and MG-36 pass green.

---

## T6 · Check rollup deduplication in merge gate (`merge_gate.sh`) (D3, AT-3, AT-4, AT-5, AT-6)

Touch: `scripts/ci/merge_gate.sh`.

In `scripts/ci/merge_gate.sh`:
1. In `GRAPHQL_ROLLUP` (line 235), query `databaseId` on `CheckRun`:
   ```bash
   GRAPHQL_ROLLUP='query($owner:String!,$repo:String!,$pr:Int!){repository(owner:$owner,name:$repo){pullRequest(number:$pr){mergeStateStatus commits(last:1){nodes{commit{statusCheckRollup{contexts(first:100){nodes{__typename ... on CheckRun{name conclusion status databaseId checkSuite{workflowRun{databaseId}}} ... on StatusContext{context state}}}}}}}}}}'
   ```
2. In `read_merge_state()` (lines 241-244), extract `databaseId` into `CHECKS_TSV`:
   ```bash
       CHECKS_TSV="$(jq -r '.data.repository.pullRequest.commits.nodes[0].commit.statusCheckRollup.contexts.nodes[]? |
           if .__typename == "CheckRun" then [(.name // "?"), ((.conclusion // .status) // ""), ((.checkSuite.workflowRun.databaseId) // ""), ((.databaseId) // "")]
           else [(.context // "?"), (.state // ""), "", ""] end | @tsv' <<<"$out")"
   ```
3. In conjunct 2 evaluation (lines 403-418), exclude self-run by workflowRun id and deduplicate foreign checks by check name / context selecting the highest databaseId:
   ```bash
   elif [ "$MERGE_STATE" = "CLEAN" ] || [ "$MERGE_STATE" = "UNSTABLE" ]; then
       RUN_ID="${GITHUB_RUN_ID:-}"
       # Exclude gate's own run by workflowRun databaseId (D24)
       OTHER="$(awk -F'\t' -v id="$RUN_ID" '$3 == "" || $3 != id' <<<"$CHECKS_TSV")"
       # Deduplicate foreign checks by name ($1): sort by name then numeric databaseId ($4),
       # keeping the latest entry for each name.
       DEDUPED="$(awk -F'\t' '{
           name = $1; st = ($2 == "" ? "PENDING" : toupper($2)); dbid = ($4 == "" ? 0 : $4 + 0);
           if (!(name in seen) || dbid >= max_dbid[name]) {
               seen[name] = st;
               max_dbid[name] = dbid;
           }
       } END {
           for (name in seen) printf "%s\t%s\n", name, seen[name];
       }' <<<"$OTHER")"
       n_other="$(grep -c . <<<"$DEDUPED" || true)"
       failing="$(awk -F'\t' '$2 != "SUCCESS" { printf " %s=%s", $1, $2 }' <<<"$DEDUPED")"
       if [ "$n_other" -eq 0 ]; then
           WHY[2]="mergeStateStatus $MERGE_STATE but no check besides the gate's own run"
       elif [ -n "$failing" ]; then
           WHY[2]="checks not success:$failing"
           ledger_append "refusal:checks" "$RUNG"
       else
           C[2]=1
           WHY[2]="mergeStateStatus $MERGE_STATE, foreign checks ($n_other) success"
       fi
   ```

Done when: All scenarios in `scripts/ci/tests/merge_gate_test.sh` (MG-31 through MG-34, along with MG-1 through MG-30b) pass green.

---

## T7 · Living spec upsert in `docs/SPEC.md` (D9, AT-14)

Touch: `docs/SPEC.md`.

### 7a · Update `### ops.dispatch`

In `docs/SPEC.md` around lines 580-586, update the pull request resolution description to document recognition of `Refs #n` and the strict single-issue union:

```markdown
It resolves a pull
request to its issue by extracting same-repo issue references from the
body — any closing keywords GitHub honours (`close`, `fix`, `resolve`
and their `-s`/`-d` forms, case-insensitively) as well as reference
keywords (`refs`, `ref`, `references`, `reference`) — unioned with the
issue number from the `<actor>/<n>-<slug>` head branch name (#298). A
pull request that resolves to more than one distinct issue exits 1
naming them rather than a guess; a pull request that resolves to no
issue exits 2 with the condition named (#216).
```

### 7b · Update `### loop.autonomous`

In `docs/SPEC.md` around lines 1077-1113, document the dedicated evaluate workflow on `pull_request` and the rollup check deduplication under conjunct 2:

```markdown
`scripts/ci/merge_gate.sh <pr>` is the one merger. On pull request events,
`.github/workflows/merge-gate-evaluate.yml` runs a read-only evaluation
(`DRY_RUN=1`) producing check run `merge-gate (evaluate)` with no skipped
checks on the head commit (#298). On main-ref events (`check_suite`, `status`,
`issue_comment`, `workflow_dispatch`), `.github/workflows/merge-gate.yml` runs
under `environment: themis` on default branch `main`.
```

and:

```markdown
CI (conjunct 2) is read from the pull request's own `mergeStateStatus`
rather than reconstructed from a required-checks list: `CLEAN` or
`UNSTABLE` with every foreign check run and commit status on the head —
excluding the gate's own run by identity (`checkSuite.workflowRun.databaseId`),
and deduplicating multiple check runs sharing the same name by latest database ID
(#298) — passing with `SUCCESS`, and at least one such check existing.
```

Done when: `bash scripts/ci/spec_check.sh origin/main <pr-body-file>` exits 0.

---

## T8 · Verification gates and forbidden-path audit (AT-14, D9)

Run verification gates across the worktree:
1. `bash scripts/ci/spec_check.sh origin/main <pr-body-file>`: PASS
2. `bash scripts/ci/sanitize_check.sh`: PASS
3. `python3 scripts/sync_agents.py --check`: PASS
4. `bash scripts/ci/tests/merge_gate_test.sh`: all scenarios pass.
5. `bash scripts/ops/tests/work_test.sh`: all scenarios pass.
6. Forbidden-path audit (D9): Verify diff touches ONLY allowed paths:
   - `.github/workflows/merge-gate-evaluate.yml` (new)
   - `.github/workflows/merge-gate.yml`
   - `.github/workflows/ci-gates.yml`
   - `scripts/ci/merge_gate.sh`
   - `scripts/ci/tests/merge_gate_test.sh`
   - `scripts/ops/lib/github.sh`
   - `scripts/ops/tests/work_test.sh`
   - `docs/SPEC.md`
   And touches NO forbidden paths (`personas/**`, `personas/lifecycle.json`, `scripts/ops/claim.sh`, `scripts/ops/work.sh` outside library sourcing, `scripts/ci/escalate.sh`, or `scripts/ci/lifecycle_advance.sh`).

Done when: All verification gates exit 0 and forbidden-path audit confirms zero violations.
