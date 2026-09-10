# Plan: Poller Fix-Round Candidate Discovery, Isolated Tracking Issue Resolution, and Multi-Rung Alignment

**Issue:** #337 · **Spec:** `intent/337-poller-fix-round-queue/spec.md` (Approved, D1–D10, AT-1–AT-11)  
**Author:** daedalus (`evekhm-daedalus-app[bot]`)  
**Base commit:** `2c5c263`  
**Target branch for implementation (Odyssey):** `odyssey/337-poller-fix-round-queue`

---

## 1. Executive Summary and Problem Statement

In `scripts/placement/vm-local/poll.sh`, section 2 ("Fix rounds on open pull requests at status:in-review", lines 126–147) queries candidate pull requests using:
```bash
prs_json="$(gh pr list --state open --label status:in-review --json number,title,labels,headRefName,isCrossRepository 2>/dev/null || echo '[]')"
```
and then checks:
```bash
has_in_review="$(jq -r '[.labels[]? | (.name // .)] | if index("status:in-review") != null then "yes" else "no" end' <<<"$pr_obj")"
[ "$has_in_review" = "yes" ] || continue
```

### Root Cause
1. **Pull requests never carry `status:*` labels.** In the agentic SDLC tracker model (AGENTS.md, `personas/lifecycle.json`, `docs/SPEC.md`), lifecycle `status:*` labels belong exclusively to tracking issues. PRs carry intent/feature labels, hold markers, or no labels at all. Consequently, `gh pr list --label status:in-review` evaluates to empty in production, starving all open pull requests with blocking reviewer findings and preventing automated fix rounds across all builder rungs.
2. **Missing draft filtering.** Section 2 of `poll.sh` does not pass `--draft=false` to `gh pr list`, nor does it query `isDraft` or inspect draft status, risking premature dispatch on draft pull requests.
3. **Missing tracking issue validation.** PR numbers are dispatched directly to `run.sh` without resolving candidate PRs to their underlying tracking issues. The poller never verifies whether the tracking issue is open, closed, review-stuck, or marked with `hold` or `blocked`.
4. **Single-rung coupling in `work.sh`.** In `scripts/ops/work.sh:399`, the resume protocol condition `[ "$status_labels" = "status:in-review" ]` restricts fix rounds to `status:in-review` issues, preventing fix rounds for Athena spec PRs on `status:spec` issues or Daedalus plan PRs on `status:build` issues.
5. **Synthetic test fixture drift.** In `scripts/ci/tests/e2e_chain_test.sh`, scenarios AT-13, AT-20, and AT-21 pass only because synthetic PR fixtures were given artificial `"labels": [{"name": "status:in-review"}]` fields, masking the production defect.

This plan establishes candidate PR discovery without status labels, isolated PR-to-issue resolution with subshell crash resilience, transient circuit breakers (`hold`, `blocked`), terminal refusal caching (`refuse-pr-*`), strict stage-to-author alignment for multi-rung fix rounds, and harmonized `work.sh` execution.

---

## 2. Scope and Persona Boundaries

| Actor | Stage | Authority / Files Touched | Role in Issue #337 |
|---|---|---|---|
| **athena** | plan / design | `intent/**` | Authored `intent.md` and approved `spec.md` (PR #344). |
| **daedalus** | build | `intent/**`, `scripts/*/tests/**` | Authors `plan.md` and commits modernized failing contract tests (AT-13, AT-20, AT-21, AT-24..AT-27) in `scripts/ci/tests/e2e_chain_test.sh`. Daedalus **never** edits production code (`poll.sh`, `work.sh`, or `docs/SPEC.md`). |
| **odyssey** | implement | `scripts/placement/vm-local/poll.sh`, `scripts/ops/work.sh`, `docs/SPEC.md` | Implements the plan at pinned base commit `2c5c263`, turning contract tests green, updating `docs/SPEC.md`, and passing all CI gates. |
| **themis** | autonomous merge | GitHub Actions (`merge-gate.yml`) | Evaluates conjuncts and autonomously merges pull requests. |
| **argus / atlas** | review | comments only | Review pull requests against spec and plan. |

---

## 3. The Eight Calls This Plan Makes

### P1 · Candidate Discovery Without PR Status Labels & Draft Filtering (D2, AT-1)
In `scripts/placement/vm-local/poll.sh`:
- Drop `--label status:in-review` from `gh pr list`.
- Add `--draft=false` to `gh pr list`.
- Query open pull requests using:
  ```bash
  gh pr list --state open --draft=false --json number,title,labels,headRefName,headRefOid,isCrossRepository,isDraft --limit 300
  ```
- Drop the `has_in_review` check.
- Filter out pull requests where `isCrossRepository == true`, `isDraft == true`, or `headRefName` is empty.
- Extract `author_persona="${head_ref%%/*}"` and ensure it belongs to the closed set of builder personas: `athena|daedalus|odyssey`. Any other prefix is skipped.

### P2 · Reviewer Trigger Predicate & Resolution Ordering (D2, D3, AT-2)
To conserve API quota, PR-to-issue resolution must not run eagerly on all open pull requests.
- First, verify that `author_persona` is not skipped (due to missing keys).
- Second, check if a terminal refusal key `${poll_state_dir}/refuse-pr-${pr_num}-${repo_hash}-${head_oid}` exists; if so, skip immediately.
- Third, fetch PR comments (`repos/$GITHUB_REPO/issues/$pr_num/comments`) and evaluate the trigger predicate (blocking findings from `evekhm-argus-app[bot]` or `evekhm-atlas-app[bot]`). If no blocking findings exist, skip without resolving the tracking issue.
- Fourth, compute the trigger key (`key_file`). If `[ -f "$key_file" ]`, the finding was already dispatched; skip without resolving the tracking issue.
- Only when an unconsumed blocking review finding exists does `poll.sh` proceed to PR-to-issue resolution.

### P3 · Subshell-Isolated PR-to-Issue Resolution & Daemon Contract (D3, AT-3)
- Source `scripts/ops/lib/github.sh` in `poll.sh`.
- Define `die() { echo "poll.sh: $*" >&2; exit 1; }` prior to sourcing `github.sh`, fulfilling caller contract in `github.sh:13`.
- Invoke `resolve_issue "$pr_num"` within a subshell wrapper:
  ```bash
  res_json="$( ( resolve_issue "$pr_num" && jq -nc --arg issue "$ISSUE" --argjson issue_json "$ISSUE_JSON" '{issue: $issue, issue_json: $issue_json}' ) 2>/dev/null )"
  rc=$?
  ```
- If `$rc -ne 0` or `res_json` is empty, log:
  ```
  poll.sh: skipping PR #$pr_num (could not resolve to tracking issue)
  ```
  and proceed to the next candidate PR without writing `key_file`. The supervisor daemon survives any `die()` call or network error.
- Verify `$ISSUE` is a non-empty integer (`[[ "$ISSUE" =~ ^[0-9]+$ ]]`) and `ISSUE_JSON` is valid JSON.

### P4 · Tracking Issue State Validation & Transient Refusals (D4, AT-4)
Before dispatching a fix round, validate the state of the resolved tracking issue:
- Check `state="$(jq -r '.state // empty' <<<"$ISSUE_JSON")"`.
- Check labels on issue: `has_hold="$(jq -r '[.labels[]? | (.name // .)] | if index("hold") != null then "yes" else "no" end' <<<"$ISSUE_JSON")"`.
- Check labels on issue: `has_blocked="$(jq -r '[.labels[]? | (.name // .)] | if index("blocked") != null then "yes" else "no" end' <<<"$ISSUE_JSON")"`.
- Check labels on candidate PR: `pr_has_hold="$(jq -r '[.labels[]? | (.name // .)] | if index("hold") != null then "yes" else "no" end' <<<"$pr_obj")"`.
- If `has_hold == "yes"`: log `poll.sh: skipping PR #$pr_num (issue #$ISSUE carries hold)` and continue.
- If `has_blocked == "yes"`: log `poll.sh: skipping PR #$pr_num (issue #$ISSUE carries blocked)` and continue.
- If `pr_has_hold == "yes"`: log `poll.sh: skipping PR #$pr_num (PR #$pr_num carries hold)` and continue.
- Transient refusals do NOT touch any key file or refusal file.

### P5 · Terminal Refusal Caching & Negative Key Invalidation (D5, AT-5)
Conditions deemed terminal (cannot self-heal without operator intervention or a new commit):
1. Resolved tracking issue is closed (`state != "open"`).
2. Resolved tracking issue carries `status:review-stuck`.
3. Resolved tracking issue stage mismatches author persona per D6.
- When a terminal condition is met:
  - Log refusal reason (e.g. `poll.sh: skipping PR #$pr_num (tracking issue #$ISSUE is closed)`).
  - Touch negative refusal key:
    `${poll_state_dir}/refuse-pr-${pr_num}-${repo_hash}-${head_oid}`
  - Do NOT touch dispatch `key_file`.
  - Continue to next candidate PR.
- In subsequent polling ticks, `[ -f "$refuse_key" ]` checks short-circuit evaluation before querying comments or resolving issues, logging:
  `poll.sh: skipping PR #$pr_num (terminal refusal cached at $head_oid)`
- Pushing a new commit updates `headRefOid`, which automatically produces a distinct refusal path and invalidates the cache.

### P6 · Strict Stage-to-Author Alignment for Multi-Rung Fix Rounds (D6, AT-6, AT-7)
Extract tracking issue status labels:
```bash
status_label="$(jq -r '[.labels[]? | (.name // .) | select(startswith("status:"))] | .[0] // empty' <<<"$ISSUE_JSON")"
```
Verify stage matches `author_persona`:
- `athena` requires `status_label == "status:spec"`
- `daedalus` requires `status_label == "status:build"`
- `odyssey` requires `status_label == "status:implementing"`
If status label does not match the builder persona's expected stage:
- Log `poll.sh: skipping PR #$pr_num (author persona $author_persona does not match issue #$ISSUE stage ${status_label:-none})`
- Treat as terminal refusal under P5 (touch `$refuse_key` and continue).
If matched:
- Touch `key_file`.
- Acquire `lock_file`.
- Execute `"$RUN_SH" "$pr_num" --as "$author_persona"`.
- Release `lock_file`.

### P7 · Harmonization of `is_fix_round` and Branch Slug in `work.sh` (D7, AT-8)
In `scripts/ops/work.sh`:
- Update line 399:
  ```bash
  if [ "$IS_PR" = "1" ] && [ -n "$AS" ] && [ -n "$pr_head_author" ] && [ "$AS" = "$pr_head_author" ] && [ -n "$PR_HEAD_REPO" ] && [ "$PR_HEAD_REPO" = "$GITHUB_REPO" ]; then
      is_fix_round=1
      if [ "$status_labels" = "status:in-review" ]; then
          stage="implement"
      fi
  fi
  ```
- When `status_labels` is not `status:in-review`, `stage` preserves the stage derived from the tracking issue (`design` for `status:spec`, `build` for `status:build`, `implement` for `status:implementing`).
- In line 556:
  ```bash
  if [ "${is_fix_round:-0}" -eq 1 ] && [ -n "$pr_head_slug" ]; then
      slug="$pr_head_slug"
  fi
  ```
  executes for all builder fix rounds, ensuring worktree and branch correctly target `<author>/<n>-<pr_head_slug>`.

### P8 · Living Spec Synchronization in `docs/SPEC.md` (D9, AT-10)
In `docs/SPEC.md`, update sections documenting:
- Poller candidate PR query without status filter and draft exclusion.
- PR-to-issue resolution and tracking issue state checks.
- Negative refusal caching (`refuse-pr-*`) and automatic invalidation on new commit SHA.
- Multi-rung fix-round dispatch for Athena, Daedalus, and Odyssey.
- `work.sh` fix-round branch targeting for all builder personas.

---

## 4. Micro-Stepped Tasks

### Task T1: Commit Contract Test Scenarios in `scripts/ci/tests/e2e_chain_test.sh`
- **Owner:** daedalus (Build stage)
- **File touched:** `scripts/ci/tests/e2e_chain_test.sh`
- **Decisions implemented:** D2, D3, D4, D5, D6, D7, D8
- **Acceptance criteria proven:** AT-1, AT-2, AT-3, AT-4, AT-5, AT-6, AT-7, AT-8, AT-9
- **Description:**
  1. In stub `gh`, support `--draft=false` filtering, unreadable issue exits (`$FIXTURES/issue-$n.unreadable`), and pull request responses.
  2. Modernize AT-13: remove `status:*` labels from PR fixture `issue-108.json`, set `issue-107.json` to `status:implementing`, and add multi-rung test cases proving `work.sh` derives stage `design` for Athena and `build` for Daedalus targeting `<author>/<n>-<slug>`.
  3. Modernize AT-20 and AT-21: remove `status:in-review` from `pr-list.json` and PR fixtures across all sub-cases, and provide tracking issue fixture `issue-4241.json` at `status:implementing`.
  4. Add scenario `AT-24` (D2, D6): Multi-rung fix-round dispatches in `poll.sh` for Athena (`athena/5000-spec` on issue 5000 at `status:spec`) and Daedalus (`daedalus/5002-plan` on issue 5002 at `status:build`).
  5. Add scenario `AT-25` (D3): Daemon-safe subshell error handling in `poll.sh` when `gh` fails on issue read or PR links multiple issues.
  6. Add scenario `AT-26` (D4): Transient circuit breakers (`hold` on issue, `blocked` on issue, `hold` on PR) prevent dispatch without negative caching.
  7. Add scenario `AT-27` (D5, D6): Terminal refusals (closed issue, `status:review-stuck`, stage mismatch) write negative refusal keys and short-circuit subsequent ticks.
- **Verification / Done-When:**
  Running `bash scripts/ci/tests/e2e_chain_test.sh` against unmodified `poll.sh` and `work.sh` completes execution without syntax errors and reports assertion failures on the un-implemented behavior (exit code 1, failures not errors, proving tests are RED).

---

### Task T2: Implement Candidate PR Query and Draft Exclusion in `poll.sh`
- **Owner:** odyssey (Implement stage)
- **File touched:** `scripts/placement/vm-local/poll.sh`
- **Decisions implemented:** D2
- **Acceptance criteria proven:** AT-1 (AT-20, AT-24)
- **Step-by-step diff:**
  In `scripts/placement/vm-local/poll.sh`, replace lines 126–147:
  ```diff
  -    # 2. Fix rounds on open pull requests at status:in-review (D2, AT-20)
  -    local prs_json="[]"
  -    prs_json="$(gh pr list --state open --label status:in-review --json number,title,labels,headRefName,isCrossRepository 2>/dev/null || echo '[]')"
  -    if [ -n "$prs_json" ] && [ "$prs_json" != "[]" ]; then
  -        local pr_count
  -        pr_count="$(jq '. | length' <<<"$prs_json" 2>/dev/null || echo 0)"
  -        for (( idx=0; idx<pr_count; idx++ )); do
  -            local pr_obj
  -            pr_obj="$(jq -c ".[$idx]" <<<"$prs_json")"
  -            local pr_num
  -            pr_num="$(jq -r '.number // empty' <<<"$pr_obj")"
  -            [ -n "$pr_num" ] || continue
  -
  -            # C1: Skip cross-repository (fork) PRs; missing field defaults to false
  -            local is_cross
  -            is_cross="$(jq -r '.isCrossRepository // false' <<<"$pr_obj")"
  -            [ "$is_cross" = "true" ] && continue
  -
  -            local has_in_review
  -            has_in_review="$(jq -r '[.labels[]? | (.name // .)] | if index("status:in-review") != null then "yes" else "no" end' <<<"$pr_obj")"
  -            [ "$has_in_review" = "yes" ] || continue
  +    # 2. Fix rounds on open builder pull requests (D2, D6, AT-20, AT-24)
  +    local prs_json="[]"
  +    prs_json="$(gh pr list --state open --draft=false --json number,title,labels,headRefName,headRefOid,isCrossRepository,isDraft --limit 300 2>/dev/null || echo '[]')"
  +    if [ -n "$prs_json" ] && [ "$prs_json" != "[]" ]; then
  +        local pr_count
  +        pr_count="$(jq '. | length' <<<"$prs_json" 2>/dev/null || echo 0)"
  +        for (( idx=0; idx<pr_count; idx++ )); do
  +            local pr_obj
  +            pr_obj="$(jq -c ".[$idx]" <<<"$prs_json")"
  +            local pr_num
  +            pr_num="$(jq -r '.number // empty' <<<"$pr_obj")"
  +            [ -n "$pr_num" ] || continue
  +
  +            local is_cross is_draft head_ref head_oid
  +            is_cross="$(jq -r '.isCrossRepository // false' <<<"$pr_obj")"
  +            [ "$is_cross" = "true" ] && continue
  +            is_draft="$(jq -r '.isDraft // false' <<<"$pr_obj")"
  +            [ "$is_draft" = "true" ] && continue
  +            head_ref="$(jq -r '.headRefName // empty' <<<"$pr_obj")"
  +            [ -n "$head_ref" ] || continue
  +            head_oid="$(jq -r '.headRefOid // empty' <<<"$pr_obj")"
  ```
- **Done-When:** `poll.sh` queries open non-draft PRs without status filter and extracts `headRefName` and `headRefOid`.

---

### Task T3: Source `github.sh` and Implement Subshell-Isolated Resolution in `poll.sh`
- **Owner:** odyssey (Implement stage)
- **File touched:** `scripts/placement/vm-local/poll.sh`
- **Decisions implemented:** D3
- **Acceptance criteria proven:** AT-2, AT-3 (AT-25)
- **Step-by-step diff:**
  In `scripts/placement/vm-local/poll.sh`:
  1. Define `die()` and source `scripts/ops/lib/github.sh` near top of script:
     ```bash
     die() {
         echo "poll.sh: $*" >&2
         exit 1
     }
     source "$REPO_ROOT/scripts/ops/lib/github.sh"
     ```
  2. Defer resolution until after comment trigger check and key check.
  3. Execute subshell resolution:
     ```bash
     local res_json="" rc_res=0
     res_json="$( ( resolve_issue "$pr_num" && jq -nc --arg issue "$ISSUE" --argjson issue_json "$ISSUE_JSON" '{issue: $issue, issue_json: $issue_json}' ) 2>/dev/null )" || rc_res=$?
     if [ "$rc_res" -ne 0 ] || [ -z "$res_json" ]; then
         echo "poll.sh: skipping PR #$pr_num (could not resolve to tracking issue)"
         continue
     fi
     local resolved_issue issue_obj
     resolved_issue="$(jq -r '.issue // empty' <<<"$res_json")"
     issue_obj="$(jq -c '.issue_json // empty' <<<"$res_json")"
     if ! [[ "$resolved_issue" =~ ^[0-9]+$ ]] || [ -z "$issue_obj" ] || [ "$issue_obj" = "null" ]; then
         echo "poll.sh: skipping PR #$pr_num (could not resolve to tracking issue)"
         continue
     fi
     ```
- **Done-When:** Scenario AT-25 passes; `poll.sh` recovers from subshell exit 1 and unresolvable PRs without process crash.

---

### Task T4: Implement Tracking Issue Validation and Circuit Breakers in `poll.sh`
- **Owner:** odyssey (Implement stage)
- **File touched:** `scripts/placement/vm-local/poll.sh`
- **Decisions implemented:** D4
- **Acceptance criteria proven:** AT-4 (AT-26)
- **Step-by-step diff:**
  In `scripts/placement/vm-local/poll.sh`, after resolving `issue_obj`:
  ```bash
  local issue_labels pr_labels has_issue_hold has_issue_blocked has_pr_hold
  issue_labels="$(jq -r '[.labels[]? | (.name // .)]' <<<"$issue_obj")"
  pr_labels="$(jq -r '[.labels[]? | (.name // .)]' <<<"$pr_obj")"

  has_issue_hold="$(jq -r 'if index("hold") != null then "yes" else "no" end' <<<"$issue_labels")"
  has_issue_blocked="$(jq -r 'if index("blocked") != null then "yes" else "no" end' <<<"$issue_labels")"
  has_pr_hold="$(jq -r 'if index("hold") != null then "yes" else "no" end' <<<"$pr_labels")"

  if [ "$has_issue_hold" = "yes" ]; then
      echo "poll.sh: skipping PR #$pr_num (issue #$resolved_issue carries hold)"
      continue
  fi
  if [ "$has_issue_blocked" = "yes" ]; then
      echo "poll.sh: skipping PR #$pr_num (issue #$resolved_issue carries blocked)"
      continue
  fi
  if [ "$has_pr_hold" = "yes" ]; then
      echo "poll.sh: skipping PR #$pr_num (PR #$pr_num carries hold)"
      continue
  fi
  ```
- **Done-When:** Scenario AT-26 passes; transient circuit breakers skip dispatch without writing key or refusal files.

---

### Task T5: Implement Terminal Refusal Caching and Negative Key Checks in `poll.sh`
- **Owner:** odyssey (Implement stage)
- **File touched:** `scripts/placement/vm-local/poll.sh`
- **Decisions implemented:** D5
- **Acceptance criteria proven:** AT-5 (AT-27)
- **Step-by-step diff:**
  In `scripts/placement/vm-local/poll.sh`:
  1. Define refusal key path:
     ```bash
     local refuse_key=""
     if [ -n "$head_oid" ]; then
         refuse_key="${poll_state_dir}/refuse-pr-${pr_num}-${repo_hash}-${head_oid}"
         if [ -f "$refuse_key" ]; then
             echo "poll.sh: skipping PR #$pr_num (terminal refusal cached at $head_oid)"
             continue
         fi
     fi
     ```
  2. Check terminal conditions (closed issue, `status:review-stuck`):
     ```bash
     local issue_state has_review_stuck
     issue_state="$(jq -r '.state // empty' <<<"$issue_obj")"
     if [ "$issue_state" != "open" ]; then
         echo "poll.sh: skipping PR #$pr_num (tracking issue #$resolved_issue is closed)"
         [ -n "$refuse_key" ] && touch "$refuse_key"
         continue
     fi

     has_review_stuck="$(jq -r 'if index("status:review-stuck") != null then "yes" else "no" end' <<<"$issue_labels")"
     if [ "$has_review_stuck" = "yes" ]; then
         echo "poll.sh: skipping PR #$pr_num (tracking issue #$resolved_issue carries status:review-stuck)"
         [ -n "$refuse_key" ] && touch "$refuse_key"
         continue
     fi
     ```
- **Done-When:** Scenario AT-27 passes; negative refusal keys prevent redundant API queries.

---

### Task T6: Implement Stage-to-Author Alignment and Multi-Rung Dispatch in `poll.sh`
- **Owner:** odyssey (Implement stage)
- **File touched:** `scripts/placement/vm-local/poll.sh`
- **Decisions implemented:** D6
- **Acceptance criteria proven:** AT-6, AT-7 (AT-20, AT-24, AT-27)
- **Step-by-step diff:**
  In `scripts/placement/vm-local/poll.sh`:
  ```bash
  local status_label expected_status=""
  status_label="$(jq -r '[.labels[]? | (.name // .) | select(startswith("status:"))] | .[0] // empty' <<<"$issue_obj")"

  case "$author_persona" in
      athena) expected_status="status:spec" ;;
      daedalus) expected_status="status:build" ;;
      odyssey) expected_status="status:implementing" ;;
  esac

  if [ -z "$expected_status" ] || [ "$status_label" != "$expected_status" ]; then
      echo "poll.sh: skipping PR #$pr_num (author persona $author_persona does not match issue #$resolved_issue stage ${status_label:-none})"
      [ -n "$refuse_key" ] && touch "$refuse_key"
      continue
  fi

  # Check consumed keys (C3)
  if [ -f "$key_file" ]; then
      echo "#$pr_num: review at $key already dispatched"
      continue
  fi

  # Touch key file and dispatch under lock
  touch "$key_file"
  echo "$$" > "$lock_file"
  (
      "$RUN_SH" "$pr_num" --as "$author_persona"
  ) || true
  rm -f "$lock_file"
  ```
- **Done-When:** Scenarios AT-20 and AT-24 pass green; Athena, Daedalus, and Odyssey fix rounds dispatch correctly under matching rungs.

---

### Task T7: Harmonize `is_fix_round` and Branch Slug Resolution in `scripts/ops/work.sh`
- **Owner:** odyssey (Implement stage)
- **File touched:** `scripts/ops/work.sh`
- **Decisions implemented:** D7
- **Acceptance criteria proven:** AT-8 (AT-13)
- **Step-by-step diff:**
  In `scripts/ops/work.sh`:
  1. Update lines 398–405:
     ```diff
     -is_fix_round=0
     -if [ "$IS_PR" = "1" ] && [ "$status_labels" = "status:in-review" ] && [ -n "$AS" ] && [ -n "$pr_head_author" ] && [ "$AS" = "$pr_head_author" ] && [ -n "$PR_HEAD_REPO" ] && [ "$PR_HEAD_REPO" = "$GITHUB_REPO" ]; then
     -    is_fix_round=1
     -    author_stage="$(jq -r '.stages[] | select(.advances_to == "status:in-review") | .stage // empty' "$LIFECYCLE_JSON")"
     -    [ -n "$author_stage" ] || author_stage="$(sed -n 's/^stage:[[:space:]]*\[\(.*\)\].*/\1/p' "$PERSONA_DIR/$AS.yaml" 2>/dev/null | tr -d ' ')"
     -    stage="${author_stage:-implement}"
     -fi
     +is_fix_round=0
     +if [ "$IS_PR" = "1" ] && [ -n "$AS" ] && [ -n "$pr_head_author" ] && [ "$AS" = "$pr_head_author" ] && [ -n "$PR_HEAD_REPO" ] && [ "$PR_HEAD_REPO" = "$GITHUB_REPO" ]; then
     +    is_fix_round=1
     +    if [ "$status_labels" = "status:in-review" ]; then
     +        stage="implement"
     +    fi
     +fi
     ```
  2. Confirm line 556 retains:
     ```bash
     if [ "${is_fix_round:-0}" -eq 1 ] && [ -n "$pr_head_slug" ]; then
         slug="$pr_head_slug"
     fi
     ```
- **Done-When:** Scenario AT-13 passes green for Athena, Daedalus, and Odyssey; branch names resolve to `<author>/<n>-<slug>`.

---

### Task T8: Update Living Spec in `docs/SPEC.md`
- **Owner:** odyssey (Implement stage)
- **File touched:** `docs/SPEC.md`
- **Decisions implemented:** D9
- **Acceptance criteria proven:** AT-10
- **Step-by-step diff:**
  In `docs/SPEC.md`, under `### loop.autonomous` and `### placement.vm-local`:
  Document candidate PR query without status filter, draft exclusion, subshell-isolated resolution to tracking issue, transient circuit breakers (`hold`, `blocked`), terminal refusal caching (`refuse-pr-*`), multi-rung fix-round stage alignment, and harmonized `work.sh` resume execution.
- **Done-When:** `bash scripts/ci/spec_check.sh origin/main <pr-body-file>` exits 0.

---

### Task T9: Integration Testing and CI Gates Verification
- **Owner:** odyssey (Implement stage)
- **Files touched:** none
- **Decisions implemented:** D1–D10
- **Acceptance criteria proven:** AT-1 through AT-11
- **Step-by-step verification commands:**
  1. `bash scripts/ci/tests/e2e_chain_test.sh` -> PASS (all 23 scenarios passed)
  2. `python3 scripts/ops/execution.py --check` -> PASS
  3. `bash scripts/ops/tests/execution_test.sh` -> PASS
  4. `bash scripts/ops/tests/placement_test.sh` -> PASS
  5. `bash scripts/ops/tests/post_test.sh` -> PASS
  6. `bash scripts/ops/tests/work_test.sh` -> PASS
  7. `bash scripts/ci/tests/lifecycle_advance_test.sh` -> PASS
  8. `bash scripts/ci/tests/merge_gate_test.sh` -> PASS
  9. `python3 scripts/sync_agents.py --check` -> PASS
  10. `bash scripts/ci/sanitize_check.sh` -> PASS
  11. `bash scripts/ci/spec_check.sh origin/main <pr-body-file>` -> PASS
- **Done-When:** All CI checks and local test suites pass with zero warnings and zero failures.

---

## 5. Traceability Matrix

| Acceptance Test | Decision IDs | Test Scenario | Implementing Task | Verification Proof |
|---|---|---|---|---|
| **AT-1** | D2 | `AT-20`, `AT-24` in `e2e_chain_test.sh` | T1 (test), T2 (code) | Poller discovers open PRs lacking status labels, excludes drafts and forks |
| **AT-2** | D3 | `AT-25` in `e2e_chain_test.sh` | T1 (test), T3 (code) | PRs without unconsumed blocking review findings cause 0 issue resolution calls |
| **AT-3** | D3 | `AT-25` in `e2e_chain_test.sh` | T1 (test), T3 (code) | Subshell isolates `die()` on unreadable PR or multi-issue link; daemon survives |
| **AT-4** | D4 | `AT-26` in `e2e_chain_test.sh` | T1 (test), T4 (code) | `hold` or `blocked` skips dispatch without writing key or refusal file |
| **AT-5** | D5 | `AT-27` in `e2e_chain_test.sh` | T1 (test), T5 (code) | Closed issue or `status:review-stuck` writes refusal key; tick 2 skips before comments |
| **AT-6** | D5, D6 | `AT-27` in `e2e_chain_test.sh` | T1 (test), T5, T6 (code) | Stage-to-author mismatch writes refusal key and skips dispatch |
| **AT-7** | D6 | `AT-20`, `AT-24` in `e2e_chain_test.sh` | T1 (test), T6 (code) | Athena on `status:spec`, Daedalus on `status:build`, Odyssey on `status:implementing` dispatch |
| **AT-8** | D7 | `AT-13` in `e2e_chain_test.sh` | T1 (test), T7 (code) | `work.sh` derives stage and branch `<author>/<n>-<slug>` across Athena, Daedalus, Odyssey |
| **AT-9** | D8 | All scenarios in `e2e_chain_test.sh` | T1 (test), T2–T7 (code) | Full test suite passes 23 scenarios green with exit 0 |
| **AT-10** | D9 | N/A | T8 (living spec), T9 | `docs/SPEC.md` updated and `spec_check.sh` passes |
| **AT-11** | D10 | N/A | T9 (verification) | Pre-merge CI checks pass |

---

## 6. Handoff to Odyssey (Implement Rung)

- **Branch:** `odyssey/337-poller-fix-round-queue`
- **Base commit:** `2c5c263` (or the commit merging this plan)
- **PR Title:** `fix(#337): poller fix-round discovery, isolated issue resolution, and multi-rung alignment`
- **PR Body Requirements:**
  - Closing keyword: `Refs #337` or `Closes #337`
  - Living spec sync: diff includes `docs/SPEC.md` update
  - Summary of implemented tasks T2–T8
  - Proof that all 23 scenarios in `scripts/ci/tests/e2e_chain_test.sh` pass green
