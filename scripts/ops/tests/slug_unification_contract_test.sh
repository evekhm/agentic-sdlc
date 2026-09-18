#!/usr/bin/env bash
# Contract test suite for unified slug derivation and folder reuse (#463).
# Cites Decisions D1, D2, D3, D4, D5, D6, D7, D8
# and Acceptance Tests AT-463-1 through AT-463-11.
# Spec: intent/463-claim-sh-and-work-sh/spec.md (Approved)
#
# Hermetic: tests run locally without network access.
# Under the baseline tree before Odyssey's implementation, all assertions
# for updated behavior must FAIL (red) cleanly without errors, while legacy
# preservation assertions pass, proving behavior is not smuggled.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
CLAIM_SH="$REPO/scripts/ops/claim.sh"
WORK_SH="$REPO/scripts/ops/work.sh"
SPEC_MD="$REPO/docs/SPEC.md"
SLUG_LIB="$REPO/scripts/ops/lib/slug.sh"
ISSUE_INF="$REPO/scripts/ops/lib/issue_inference.sh"

TOTAL=0
PASSED=0
FAILURES=0

banner() { printf '\n=== %s ===\n' "$*"; }

pass() {
    TOTAL=$((TOTAL + 1))
    PASSED=$((PASSED + 1))
    echo "PASS: $*"
}

fail() {
    TOTAL=$((TOTAL + 1))
    FAILURES=$((FAILURES + 1))
    echo "FAIL: $*" >&2
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FIXTURES="$WORK/fixtures"
mkdir -p "$FIXTURES" "$WORK/bin"

export GITHUB_REPO="test/repo"
export FIXTURES
export PATH="$WORK/bin:$PATH"
export CLAIM_ACTOR=tester CLAIM_SESSION=test-session CLAIM_STAGE=implement
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# --- stub gh ------------------------------------------------------------------
cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = "api" ] && [ "$#" -ge 2 ]; then
    file="$FIXTURES/${2//\//_}.json"
    if [ -f "$file" ]; then
        cat "$file"
        exit 0
    fi
    echo "{}"
    exit 0
fi
if [ "${1:-}" = "issue" ] && [ "${2:-}" = "view" ]; then
    issue_num="$3"
    file="$FIXTURES/repos_test_repo_issues_${issue_num}.json"
    if [ -f "$file" ]; then
        cat "$file"
        exit 0
    fi
fi
exit 0
STUB
chmod +x "$WORK/bin/gh"

# Stub claude and agy so work.sh dry-run never complains
cat > "$WORK/bin/claude" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
cat > "$WORK/bin/agy" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
chmod +x "$WORK/bin/claude" "$WORK/bin/agy"

# Helper to register an issue fixture
fixture_issue() {
    local n="$1" state="$2" labels="$3" title="$4"
    jq -n --argjson n "$n" --arg state "$state" --arg labels "$labels" --arg title "$title" \
        '{number: $n, state: $state, title: $title, body: "",
          issue_dependencies_summary: {total_blocked_by: 0},
          labels: ($labels | if . == "" then [] else split(",") end | map({name: .}))}' \
        > "$FIXTURES/repos_test_repo_issues_${n}.json"
    echo '[]' > "$FIXTURES/repos_test_repo_issues_${n}_comments.json"
}

# --- hermetic test repository -------------------------------------------------
git init -q --bare -b main "$WORK/origin.git"
git clone -q "$WORK/origin.git" "$WORK/repo" 2>/dev/null
PRIMARY="$WORK/repo"
(
    cd "$PRIMARY"
    git checkout -q -b main
    echo "base" > base.txt
    printf '.claude/\n' > .gitignore
    mkdir -p personas
    cat > personas/lifecycle.json <<'JSON'
{"stages":[
  {"stage":"plan","label":"status:planning"},
  {"stage":"design","label":"status:spec"},
  {"stage":"build","label":"status:build"},
  {"stage":"implement","label":"status:implementing"},
  {"stage":"review","label":"status:in-review"}
]}
JSON
    git add base.txt .gitignore personas/lifecycle.json
    git commit -q -m "initial commit"
    git push -q -u origin main
)

run_claim_slug() {
    local issue_num="$1"
    local explicit_slug="${2:-}"
    local out=""
    out="$(cd "$PRIMARY" && DRY_RUN=1 bash "$CLAIM_SH" "$issue_num" ${explicit_slug:+"$explicit_slug"} 2>&1 || true)"
    printf '%s\n' "$out" | sed -n "s/.*-b [^/]*\/${issue_num}-\\([^ ]*\\).*/\\1/p" | head -n 1
}

run_claim_exit() {
    local issue_num="$1"
    local explicit_slug="${2:-}"
    local rc=0
    (cd "$PRIMARY" && DRY_RUN=1 bash "$CLAIM_SH" "$issue_num" ${explicit_slug:+"$explicit_slug"} >/dev/null 2>&1) || rc=$?
    echo "$rc"
}

run_work_slug() {
    local issue_num="$1"
    local out=""
    out="$(cd "$PRIMARY" && DRY_RUN=1 bash "$WORK_SH" "$issue_num" 2>&1 || true)"
    printf '%s\n' "$out" | sed -n "s/.*folder:[[:space:]]*intent\/${issue_num}-\\([^/]*\\)\/.*/\\1/p" | head -n 1
}

# ==============================================================================
# Assertion 1: D1, D2 / AT-463-1: Cold Derivation Equality
# ==============================================================================
banner "D1, D2 / AT-463-1: Cold Derivation Equality between claim.sh and work.sh"
fixture_issue 457 "open" "status:implementing" "README: add a worked /idea, /claim, /work walkthrough"
claim_slug_457="$(run_claim_slug 457)"
work_slug_457="$(run_work_slug 457)"

if [ -n "$claim_slug_457" ] && [ -n "$work_slug_457" ] && [ "$claim_slug_457" = "$work_slug_457" ] && [ "$claim_slug_457" = "readme" ]; then
    pass "D1, D2 / AT-463-1: claim.sh and work.sh derive identical cold slug '$claim_slug_457'"
else
    fail "D1, D2 / AT-463-1: cold slug mismatch: claim.sh derived '${claim_slug_457:-<empty>}', work.sh derived '${work_slug_457:-<empty>}' (expected both 'readme')"
fi

# ==============================================================================
# Assertion 2: D2 / AT-463-2: Colon Cutting in Slug Derivation
# ==============================================================================
banner "D2 / AT-463-2: Colon Cutting in Slug Derivation"
fixture_issue 114 "open" "status:implementing" "ops: claim.sh -- one command"
claim_slug_114="$(run_claim_slug 114)"
if [ "$claim_slug_114" = "ops" ]; then
    pass "D2 / AT-463-2: claim.sh cuts title at first colon to 'ops'"
else
    fail "D2 / AT-463-2: claim.sh expected 'ops', got '${claim_slug_114:-<empty>}'"
fi

# ==============================================================================
# Assertion 3: D2 / AT-463-3: Semicolon Cutting in Slug Derivation
# ==============================================================================
banner "D2 / AT-463-3: Semicolon Cutting in Slug Derivation"
fixture_issue 116 "open" "status:implementing" "Execution model; where does it run?"
claim_slug_116="$(run_claim_slug 116)"
if [ "$claim_slug_116" = "execution-model" ]; then
    pass "D2 / AT-463-3: claim.sh cuts title at first semicolon to 'execution-model'"
else
    fail "D2 / AT-463-3: claim.sh expected 'execution-model', got '${claim_slug_116:-<empty>}'"
fi

# ==============================================================================
# Assertion 4: D2 / AT-463-4: Length Cap at 24 Characters on Word Boundary
# ==============================================================================
banner "D2 / AT-463-4: Length Cap at 24 Characters on Word Boundary"
fixture_issue 112 "open" "status:implementing" "Abcdefghij klmnopqrst uvwxyz0123 456789ab cdefgh"
claim_slug_112="$(run_claim_slug 112)"
if [ -n "$claim_slug_112" ] && [ "${#claim_slug_112}" -le 24 ] && [ "$claim_slug_112" = "abcdefghij-klmnopqrst" ]; then
    pass "D2 / AT-463-4: claim.sh caps slug at 24 characters on word boundary ('$claim_slug_112')"
else
    fail "D2 / AT-463-4: claim.sh expected 'abcdefghij-klmnopqrst' (<=24 chars), got '${claim_slug_112:-<empty>}' (${#claim_slug_112} chars)"
fi

# ==============================================================================
# Assertion 5: D3 / AT-463-5: Existing Folder Reuse in claim.sh
# ==============================================================================
banner "D3 / AT-463-5: Existing Folder Reuse in claim.sh"
mkdir -p "$PRIMARY/intent/463-claim-sh-and-work-sh"
fixture_issue 463 "open" "status:build" "claim.sh and work.sh derive different slugs from one issue title"
claim_slug_463="$(run_claim_slug 463)"
if [ "$claim_slug_463" = "claim-sh-and-work-sh" ]; then
    pass "D3 / AT-463-5: claim.sh reuses existing intent folder slug 'claim-sh-and-work-sh'"
else
    fail "D3 / AT-463-5: claim.sh expected existing folder slug 'claim-sh-and-work-sh', got '${claim_slug_463:-<empty>}'"
fi

# ==============================================================================
# Assertion 6: D3 / AT-463-6: Conflicting Explicit Slug Refusal in claim.sh
# ==============================================================================
banner "D3 / AT-463-6: Conflicting Explicit Slug Refusal in claim.sh"
# intent/463-claim-sh-and-work-sh exists; passing explicit conflicting slug "conflicting-slug" must refuse with exit code 2
claim_rc_conflict="$(run_claim_exit 463 "conflicting-slug")"
if [ "$claim_rc_conflict" -eq 2 ]; then
    pass "D3 / AT-463-6: claim.sh refuses conflicting explicit slug with exit code 2"
else
    fail "D3 / AT-463-6: claim.sh expected exit code 2 for conflicting explicit slug, got $claim_rc_conflict"
fi

# ==============================================================================
# Assertion 7: D3 / AT-463-7: Multiple Folder Detection in claim.sh
# ==============================================================================
banner "D3 / AT-463-7: Multiple Folder Detection in claim.sh"
mkdir -p "$PRIMARY/intent/999-folder-alpha" "$PRIMARY/intent/999-folder-beta"
fixture_issue 999 "open" "status:implementing" "Multiple folders issue"
claim_rc_multiple="$(run_claim_exit 999)"
if [ "$claim_rc_multiple" -eq 2 ]; then
    pass "D3 / AT-463-7: claim.sh refuses multiple intent folders with exit code 2"
else
    fail "D3 / AT-463-7: claim.sh expected exit code 2 for multiple intent folders, got $claim_rc_multiple"
fi

# ==============================================================================
# Assertion 8: D4 / AT-463-8: Preserved In-Flight Worktree and Branch Compatibility
# ==============================================================================
banner "D4 / AT-463-8: Preserved In-Flight Worktree and Branch Compatibility"
# shellcheck source=/dev/null
. "$ISSUE_INF"
wt1="$(_issue_from_wt_name "odyssey-410-changelog-md-with-a-hard-ci-merge-gate" || true)"
wt2="$(_issue_from_wt_name "daedalus-463-claim-sh-and-work-sh-derive-different" || true)"
wt3="$(_issue_from_wt_name "athena-463-claim-sh-and-work-sh" || true)"
br1="$(_issue_from_branch "odyssey/410-changelog-md-with-a-hard-ci-merge-gate" || true)"
br2="$(_issue_from_branch "daedalus/463-claim-sh-and-work-sh-derive-different" || true)"
br3="$(_issue_from_branch "athena/463-claim-sh-and-work-sh" || true)"

if [ "$wt1" = "410" ] && [ "$wt2" = "463" ] && [ "$wt3" = "463" ] && \
   [ "$br1" = "410" ] && [ "$br2" = "463" ] && [ "$br3" = "463" ]; then
    pass "D4 / AT-463-8: issue_inference.sh resolves legacy and unified worktrees and branches correctly"
else
    fail "D4 / AT-463-8: issue_inference.sh failed to infer issues from worktree/branch names (wt: $wt1, $wt2, $wt3; br: $br1, $br2, $br3)"
fi

# ==============================================================================
# Assertion 9: D1, D5, D6 / AT-463-9: Hermetic Shared Library scripts/ops/lib/slug.sh
# ==============================================================================
banner "D1, D5, D6 / AT-463-9: Hermetic Shared Library scripts/ops/lib/slug.sh"
if [ -f "$SLUG_LIB" ]; then
    # Test sourcing and function availability in a clean environment without gh on PATH
    slug_test_out="$(PATH="/usr/bin:/bin" bash -c ". '$SLUG_LIB' && type derive_slug && type resolve_issue_slug" 2>&1 || true)"
    if [[ "$slug_test_out" == *"derive_slug is a function"* ]] && [[ "$slug_test_out" == *"resolve_issue_slug is a function"* ]]; then
        pass "D1, D5, D6 / AT-463-9: scripts/ops/lib/slug.sh exists and exports derive_slug and resolve_issue_slug hermetically"
    else
        fail "D1, D5, D6 / AT-463-9: scripts/ops/lib/slug.sh missing required functions: $slug_test_out"
    fi
else
    fail "D1, D5, D6 / AT-463-9: scripts/ops/lib/slug.sh does not exist"
fi

# ==============================================================================
# Assertion 10: D7 / AT-463-10: Living Spec Documentation in docs/SPEC.md
# ==============================================================================
banner "D7 / AT-463-10: Living Spec Documentation in docs/SPEC.md"
has_ops_claim=0
has_claim_463=0
has_dispatch_463=0

if grep -q '^### ops\.claim' "$SPEC_MD"; then
    has_ops_claim=1
fi
if awk '/^### ops\.claim/,/^### ops\.[^c]/' "$SPEC_MD" | grep -Eq '(#463|463)'; then
    has_claim_463=1
fi
if awk '/^### ops\.dispatch/,/^### ops\.[^d]/' "$SPEC_MD" | grep -Eq '(#463|463|slug\.sh)'; then
    has_dispatch_463=1
fi

if [ "$has_ops_claim" -eq 1 ] && [ "$has_claim_463" -eq 1 ] && [ "$has_dispatch_463" -eq 1 ]; then
    pass "D7 / AT-463-10: docs/SPEC.md documents ops.claim and ops.dispatch referencing #463"
else
    fail "D7 / AT-463-10: docs/SPEC.md missing required living spec updates (ops.claim: $has_ops_claim, claim #463: $has_claim_463, dispatch #463/slug.sh: $has_dispatch_463)"
fi

# ==============================================================================
# Assertion 11: D8 / AT-463-11: Strict Scope Boundary Enforcement
# ==============================================================================
banner "D8 / AT-463-11: Strict Scope Boundary Enforcement"
forbidden_changes="$(git -C "$REPO" diff --name-only origin/main | grep -E '^personas/|^\.claude/agents/|^\.agents/|^\.github/workflows/' || true)"
if [ -z "$forbidden_changes" ]; then
    pass "D8 / AT-463-11: No changes detected in forbidden directories (personas, agents, workflows)"
else
    fail "D8 / AT-463-11: Detected changes in forbidden paths: $forbidden_changes"
fi

# ==============================================================================
# Summary
# ==============================================================================
banner "Contract Test Summary"
echo "Total assertions: $TOTAL"
echo "Passed:           $PASSED"
echo "Failed:           $FAILURES"

if [ "$FAILURES" -gt 0 ]; then
    echo "Total failures: $FAILURES (EXPECTED RED at build rung)" >&2
    exit 1
fi

echo "ALL TESTS PASSED"
exit 0
