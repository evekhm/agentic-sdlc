#!/usr/bin/env bash
# Tests for end-to-end autonomous loop chain (#251, intent/251-e2e-chain/spec.md).
#
# Usage:
#   bash scripts/ci/tests/e2e_chain_test.sh [-k <pattern>]
#
# Hermetic contract test suite covering Decisions D1 through D8 and Acceptance
# Criteria AT-1 through AT-20 (the sixteen executable scenarios).
#
# Stub helpers copied from:
# - scripts/ci/tests/lifecycle_advance_test.sh:57-63, 73-178, 187-195
# - scripts/ops/tests/work_test.sh:72-84, 86-131, 138-160
#
# Stubs gh, git, python3, claude, and agy on PATH within a temporary workspace.
# No network calls, no live tokens, and no real issues are touched.
# Exit 0 if all tests pass; non-zero if any contract test fails.

set -uo pipefail

FILTER=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        -k)
            [ "$#" -ge 2 ] || { echo "error: -k requires a pattern" >&2; exit 2; }
            FILTER="$2"; shift 2 ;;
        -k=*)
            FILTER="${1#-k=}"; shift ;;
        *)
            echo "error: unknown argument: $1" >&2; exit 2 ;;
    esac
done

should_run() {
    [ -z "$FILTER" ] || grep -qE "$FILTER" <<<"$1"
}

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FIXTURES="$WORK/fixtures"
WRITES="$WORK/writes.log"
INVOKES="$WORK/invocations.log"
LAUNCHES="$WORK/launches.log"
mkdir -p "$FIXTURES" "$WORK/bin"
: > "$WRITES"
: > "$INVOKES"
: > "$LAUNCHES"

export FIXTURES WRITES INVOKES LAUNCHES
export GITHUB_REPO="evekhm/agentic-sdlc"
export GITHUB_REPOSITORY="evekhm/agentic-sdlc"
REAL_GIT="$(command -v git)"
REAL_PYTHON3="$(command -v python3)"
REAL_JQ="$(command -v jq)"
export REAL_GIT REAL_PYTHON3 REAL_JQ
export PATH="$WORK/bin:$PATH"

# Merger actor identity for lifecycle tests (#64 D30)
export MERGER='evekhm-themis-app[bot]'

FAILED=0
TOTAL=0
PASSED=0

pass() {
    PASSED=$((PASSED + 1))
    echo "PASS: $*"
}

fail() {
    FAILED=$((FAILED + 1))
    echo "FAIL: $*" >&2
}

banner() {
    printf '\n--- %s\n' "$*"
}

# --- Minimal stub git --------------------------------------------------------
# Copied from scripts/ops/tests/work_test.sh:72-84 and
# scripts/ci/tests/lifecycle_advance_test.sh:187-195
cat > "$WORK/bin/git" <<'GITSTUB'
#!/usr/bin/env bash
if [ -n "${LIFECYCLE_TEST_GIT_REV_LIST_FAIL:-}" ] && [ "${1:-}" = "rev-list" ]; then
    echo "simulated rev-list failure (LIFECYCLE_TEST_GIT_REV_LIST_FAIL=1)" >&2
    exit 1
fi
if [ "${1:-}" = "-C" ] && [ "${3:-}" = "cat-file" ] && [ "${4:-}" = "-e" ]; then
    if [ "${5:-}" = "origin/does-not-exist^{commit}" ]; then exit 1; fi
    exit 0
fi
if [ "${1:-}" = "cat-file" ] && [ "${2:-}" = "-e" ]; then
    if [ "${3:-}" = "origin/does-not-exist^{commit}" ]; then exit 1; fi
    exit 0
fi
exec "$REAL_GIT" "$@"
GITSTUB
chmod +x "$WORK/bin/git"

# --- Minimal stub gh ---------------------------------------------------------
# Copied from scripts/ci/tests/lifecycle_advance_test.sh:73-178 and
# scripts/ops/tests/work_test.sh:86-131
cat > "$WORK/bin/gh" <<'GHSTUB'
#!/usr/bin/env bash
printf '%s\n' "gh $*" >> "$INVOKES"
args=()
paginate=0
for a in "$@"; do
    case "$a" in
        --paginate) paginate=1 ;;
        *) args+=("$a") ;;
    esac
done

cmd="${args[0]:-}"
if [ "$cmd" = "issue" ] || [ "$cmd" = "pr" ]; then
    subcmd="${args[1]:-}"
    target="${args[2]:-}"
    if [ "$subcmd" = "view" ]; then
        if [ -f "$FIXTURES/issue-$target.unreadable" ]; then
            exit 1
        fi
        if [ -f "$FIXTURES/issue-$target.json" ]; then
            cat "$FIXTURES/issue-$target.json"
            exit 0
        fi
        if [ -f "$FIXTURES/repos_evekhm_agentic-sdlc_issues_${target}.json" ]; then
            cat "$FIXTURES/repos_evekhm_agentic-sdlc_issues_${target}.json"
            exit 0
        fi
        "$REAL_JQ" -nc --argjson n "$target" '{number: $n, state: "OPEN", labels: [], comments: []}'
        exit 0
    fi
fi

if [ "$cmd" = "api" ]; then
    if [ "${args[1]:-}" = "graphql" ] && [[ "$*" == *"viewer { login }"* ]]; then
        [ -f "$FIXTURES/viewer-unreadable" ] && exit 1
        login="$MERGER"
        [ -f "$FIXTURES/viewer-login" ] && login="$(cat "$FIXTURES/viewer-login")"
        "$REAL_JQ" -nc --arg l "$login" '{data: {viewer: {login: $l}}}'
        exit 0
    fi

    for a in "${args[@]}"; do
        case "$a" in
            -X|-f|-F|--method|--input)
                printf '%s\n' "gh $*" >> "$WRITES"
                ;;
        esac
    done

    # Parse path and check method
    path=""
    method="GET"
    i=1
    while [ "$i" -lt "${#args[@]}" ]; do
        arg="${args[$i]}"
        case "$arg" in
            -X|--method)
                i=$((i + 1))
                method="${args[$i]}"
                ;;
            -f|-F|--jq)
                i=$((i + 1))
                ;;
            -*)
                ;;
            *)
                if [ -z "$path" ]; then
                    path="$arg"
                fi
                ;;
        esac
        i=$((i + 1))
    done

    clean_path="${path%%\?*}"
    fixfile="$FIXTURES/${clean_path//\//_}.json"
    if [ "$method" = "GET" ] && [ -f "$fixfile" ]; then
        cat "$fixfile"
        exit 0
    fi
    case "$clean_path" in
        repos/*/issues/[0-9]*)
            n="${clean_path##*/}"
            if [ -f "$FIXTURES/issue-$n.json" ]; then
                cat "$FIXTURES/issue-$n.json"
                exit 0
            fi
            "$REAL_JQ" -nc --argjson n "$n" '{number: $n, state: "OPEN", labels: [], comments: []}'
            exit 0
            ;;
        repos/*/commits/*/pulls)
            sha="${clean_path#*/commits/}"
            sha="${sha%/pulls}"
            if [ -f "$FIXTURES/pulls-$sha.json" ]; then
                cat "$FIXTURES/pulls-$sha.json"
                exit 0
            fi
            echo '[]'
            exit 0
            ;;
        repos/*/pulls/*/files)
            n="${clean_path#*/pulls/}"
            n="${n%/files}"
            if [ -f "$FIXTURES/files-$n.json" ]; then
                cat "$FIXTURES/files-$n.json"
                exit 0
            fi
            echo '[]'
            exit 0
            ;;
        */issues/*/comments*|repos/*/issues/*/comments*)
            n="${clean_path#*/issues/}"
            n="${n%%/*}"
            if [ "$method" = "POST" ]; then
                printf 'POST comments %s\n' "$n" >> "$WRITES"
                echo '{"status": "ok", "id": 9999}'
                exit 0
            fi
            if [ -f "$FIXTURES/comments-$n.json" ]; then
                cat "$FIXTURES/comments-$n.json"
                exit 0
            fi
            if [ -f "$FIXTURES/repos_evekhm_agentic-sdlc_issues_${n}_comments.json" ]; then
                cat "$FIXTURES/repos_evekhm_agentic-sdlc_issues_${n}_comments.json"
                exit 0
            fi
            echo '[]'
            exit 0
            ;;
        */issues/*/labels/in-progress|repos/*/issues/*/labels/in-progress)
            n="${clean_path#*/issues/}"
            n="${n%%/*}"
            printf '%s labels %s in-progress\n' "$method" "$n" >> "$WRITES"
            echo '{"status": "ok"}'
            exit 0
            ;;
        repos/*)
            if [ "$method" != "GET" ]; then
                printf '%s %s\n' "$method" "$clean_path" >> "$WRITES"
                echo '{"status": "ok"}'
                exit 0
            fi
            echo '{"default_branch":"main"}'
            exit 0
            ;;
    esac
fi

exit 0
GHSTUB
chmod +x "$WORK/bin/gh"

# --- Minimal stub python3 ----------------------------------------------------
# Copied from scripts/ci/tests/lifecycle_advance_test.sh:57-63
cat > "$WORK/bin/python3" <<'PYSTUB'
#!/usr/bin/env bash
if [ "${2:-}" = "--loop" ] && [ -f "$FIXTURES/loop-${3:-}" ]; then
    cat "$FIXTURES/loop-$3"
    exit 0
fi
if [ "${2:-}" = "--binding" ] && [ -f "$FIXTURES/binding-${3:-}" ]; then
    cat "$FIXTURES/binding-$3"
    exit 0
fi
# Stub mint_app_token.py
for arg in "$@"; do
    case "$arg" in
        *mint_app_token.py)
            if [ -n "${FAIL_MINT:-}" ]; then
                echo "error: mint failure simulated" >&2
                exit 1
            fi
            echo "stub-token-not-a-credential"
            exit 0
            ;;
    esac
done
exec "$REAL_PYTHON3" "$@"
PYSTUB
chmod +x "$WORK/bin/python3"

# --- Harness stubs: claude and agy -------------------------------------------
# Copied from scripts/ops/tests/work_test.sh:138-160
cat > "$WORK/bin/claude" <<'CLAUDETESTUB'
#!/usr/bin/env bash
echo "claude $*" >> "$LAUNCHES"
exit 0
CLAUDETESTUB
chmod +x "$WORK/bin/claude"

cat > "$WORK/bin/agy" <<'AGYSTUB'
#!/usr/bin/env bash
echo "agy $*" >> "$LAUNCHES"
exit 0
AGYSTUB
chmod +x "$WORK/bin/agy"

# Setup synthetic git range for lifecycle tests
SANDBOX="$WORK/repo"
mkdir -p "$SANDBOX/personas" "$SANDBOX/intent/999-test"
cp "$REPO/personas/lifecycle.json" "$SANDBOX/personas/lifecycle.json"
(
    cd "$SANDBOX" || exit 1
    "$REAL_GIT" init -q .
    "$REAL_GIT" config user.email test@example.com
    "$REAL_GIT" config user.name test
    echo seed > seed.txt
    "$REAL_GIT" add -A
    "$REAL_GIT" commit -qm seed
    C0="$("$REAL_GIT" rev-parse HEAD)"

    printf '# Intent\n' > intent/999-test/intent.md
    "$REAL_GIT" add -A
    "$REAL_GIT" commit -qm intent
    C1="$("$REAL_GIT" rev-parse HEAD)"

    printf '# Spec\n\n**Issue:** #999 · **Status:** Approved (approval = merge of this PR)\n' \
      > intent/999-test/spec.md
    "$REAL_GIT" add -A
    "$REAL_GIT" commit -qm spec
    C2="$("$REAL_GIT" rev-parse HEAD)"

    echo "$C0" > "$WORK/c0"
    echo "$C1" > "$WORK/c1"
    echo "$C2" > "$WORK/c2"
)
C0="$(cat "$WORK/c0")"
C1="$(cat "$WORK/c1")"
C2="$(cat "$WORK/c2")"

reset_fixtures() {
    rm -f "$FIXTURES"/*.json "$FIXTURES"/*.unreadable "$FIXTURES"/loop-* "$FIXTURES"/binding-*
    : > "$WRITES"
    : > "$INVOKES"
    : > "$LAUNCHES"
}

ADVANCER="$REPO/scripts/ci/lifecycle_advance.sh"

# =============================================================================
# AT-1 (D1): Ladder rung transition releases claim when claim author login matches completing stage persona
# =============================================================================
run_at1() {
    local name="AT-1"
    should_run "$name" || return 0
    TOTAL=$((TOTAL + 1))
    banner "$name (D1): Claim release on ladder advance"
    reset_fixtures

    cat > "$FIXTURES/issue-999.json" <<'EOF'
{
  "number": 999,
  "state": "OPEN",
  "labels": [{"name": "status:planning"}, {"name": "in-progress"}],
  "comments": [
    {
      "user": {"login": "evekhm-athena-app[bot]"},
      "body": "Claim: athena (session-1) stage:plan path:.claude/worktrees/athena-999-test"
    }
  ]
}
EOF
    cat > "$FIXTURES/pulls-$C2.json" <<EOF
[
  {
    "number": 4242,
    "merged_at": "2026-01-01T00:00:00Z",
    "state": "closed",
    "merge_commit_sha": "$C2",
    "base": {"ref": "main"},
    "head": {"ref": "athena/999-test", "repo": {"full_name": "evekhm/agentic-sdlc"}},
    "body": "Fixes #999"
  }
]
EOF
    cat > "$FIXTURES/files-4242.json" <<'EOF'
[{"filename": "intent/999-test/spec.md"}]
EOF
    echo "true" > "$FIXTURES/loop-autonomous_merge"
    echo "10" > "$FIXTURES/loop-max_rung_dispatches_per_issue"
    echo "50.00" > "$FIXTURES/loop-max_cost_usd_per_issue"
    echo "ladder vm-local 50.00" > "$FIXTURES/binding-vm-local"

    local out=""
    out="$(cd "$SANDBOX" && DRY_RUN=1 bash "$ADVANCER" "$C1" "$C2" 2>&1 || true)"
    if grep -qF "released claim of athena on #999 (rung plan merged)" <<<"$out"; then
        pass "AT-1 (D1): lifecycle_advance.sh released claim of athena on #999"
    else
        fail "AT-1 (D1): lifecycle_advance.sh did not print 'released claim of athena on #999 (rung plan merged)'"
    fi
}
run_at1

# =============================================================================
# AT-2 (D1): Ladder advance withholds dispatch when in-progress held by different persona
# =============================================================================
run_at2() {
    local name="AT-2"
    should_run "$name" || return 0
    TOTAL=$((TOTAL + 1))
    banner "$name (D1): Withhold dispatch when claim held by different persona"
    reset_fixtures

    cat > "$FIXTURES/issue-999.json" <<'EOF'
{
  "number": 999,
  "state": "OPEN",
  "labels": [{"name": "status:planning"}, {"name": "in-progress"}],
  "comments": [
    {
      "user": {"login": "evekhm-odyssey-app[bot]"},
      "body": "Claim: odyssey (session-1) stage:implement path:.claude/worktrees/odyssey-999-test"
    }
  ]
}
EOF
    cat > "$FIXTURES/pulls-$C2.json" <<EOF
[
  {
    "number": 4242,
    "merged_at": "2026-01-01T00:00:00Z",
    "state": "closed",
    "merge_commit_sha": "$C2",
    "base": {"ref": "main"},
    "head": {"ref": "athena/999-test", "repo": {"full_name": "evekhm/agentic-sdlc"}},
    "body": "Fixes #999"
  }
]
EOF
    cat > "$FIXTURES/files-4242.json" <<'EOF'
[{"filename": "intent/999-test/spec.md"}]
EOF
    echo "true" > "$FIXTURES/loop-autonomous_merge"
    echo "10" > "$FIXTURES/loop-max_rung_dispatches_per_issue"
    echo "50.00" > "$FIXTURES/loop-max_cost_usd_per_issue"
    echo "ladder vm-local 50.00" > "$FIXTURES/binding-vm-local"

    local out=""
    out="$(cd "$SANDBOX" && DRY_RUN=1 bash "$ADVANCER" "$C1" "$C2" 2>&1 || true)"
    if grep -qF "withholding dispatch: in-progress held by odyssey" <<<"$out"; then
        pass "AT-2 (D1): lifecycle_advance.sh withheld dispatch for claim held by different persona"
    else
        fail "AT-2 (D1): lifecycle_advance.sh did not print 'withholding dispatch: in-progress held by odyssey'"
    fi
}
run_at2

# =============================================================================
# AT-3 (D1): Ladder advance withholds dispatch when in-progress held by foreign login
# =============================================================================
run_at3() {
    local name="AT-3"
    should_run "$name" || return 0
    TOTAL=$((TOTAL + 1))
    banner "$name (D1): Withhold dispatch when claim held by foreign login"
    reset_fixtures

    cat > "$FIXTURES/issue-999.json" <<'EOF'
{
  "number": 999,
  "state": "OPEN",
  "labels": [{"name": "status:planning"}, {"name": "in-progress"}],
  "comments": [
    {
      "user": {"login": "foreign-user"},
      "body": "Claim: foreign (session-1) stage:plan path:.claude/worktrees/foreign-999-test"
    }
  ]
}
EOF
    cat > "$FIXTURES/pulls-$C2.json" <<EOF
[
  {
    "number": 4242,
    "merged_at": "2026-01-01T00:00:00Z",
    "state": "closed",
    "merge_commit_sha": "$C2",
    "base": {"ref": "main"},
    "head": {"ref": "athena/999-test", "repo": {"full_name": "evekhm/agentic-sdlc"}},
    "body": "Fixes #999"
  }
]
EOF
    cat > "$FIXTURES/files-4242.json" <<'EOF'
[{"filename": "intent/999-test/spec.md"}]
EOF
    echo "true" > "$FIXTURES/loop-autonomous_merge"
    echo "10" > "$FIXTURES/loop-max_rung_dispatches_per_issue"
    echo "50.00" > "$FIXTURES/loop-max_cost_usd_per_issue"
    echo "ladder vm-local 50.00" > "$FIXTURES/binding-vm-local"

    local out=""
    out="$(cd "$SANDBOX" && DRY_RUN=1 bash "$ADVANCER" "$C1" "$C2" 2>&1 || true)"
    if grep -q "withholding dispatch: in-progress held by foreign login" <<<"$out"; then
        pass "AT-3 (D1): lifecycle_advance.sh withheld dispatch for foreign login"
    else
        fail "AT-3 (D1): lifecycle_advance.sh did not print 'withholding dispatch: in-progress held by foreign login'"
    fi
}
run_at3

# =============================================================================
# AT-4 (D1): Ladder advance skips claim release and leaves in-progress intact when autonomous_merge is false
# =============================================================================
run_at4() {
    local name="AT-4"
    should_run "$name" || return 0
    TOTAL=$((TOTAL + 1))
    banner "$name (D1): Skip claim release when autonomous_merge is false"
    reset_fixtures

    cat > "$FIXTURES/issue-999.json" <<'EOF'
{
  "number": 999,
  "state": "OPEN",
  "labels": [{"name": "status:planning"}, {"name": "in-progress"}],
  "comments": [
    {
      "user": {"login": "evekhm-athena-app[bot]"},
      "body": "Claim: athena (session-1) stage:plan path:.claude/worktrees/athena-999-test"
    }
  ]
}
EOF
    cat > "$FIXTURES/pulls-$C2.json" <<EOF
[
  {
    "number": 4242,
    "merged_at": "2026-01-01T00:00:00Z",
    "state": "closed",
    "merge_commit_sha": "$C2",
    "base": {"ref": "main"},
    "head": {"ref": "athena/999-test", "repo": {"full_name": "evekhm/agentic-sdlc"}},
    "body": "Fixes #999"
  }
]
EOF
    cat > "$FIXTURES/files-4242.json" <<'EOF'
[{"filename": "intent/999-test/spec.md"}]
EOF
    echo "false" > "$FIXTURES/loop-autonomous_merge"
    echo "10" > "$FIXTURES/loop-max_rung_dispatches_per_issue"
    echo "50.00" > "$FIXTURES/loop-max_cost_usd_per_issue"
    echo "ladder vm-local 50.00" > "$FIXTURES/binding-vm-local"

    local out=""
    out="$(cd "$SANDBOX" && DRY_RUN=1 bash "$ADVANCER" "$C1" "$C2" 2>&1 || true)"
    if grep -qF "released claim of athena on #999" <<<"$out"; then
        fail "AT-4 (D1): lifecycle_advance.sh released claim despite autonomous_merge: false"
    elif grep -q "autonomous_merge is false" <<<"$out" && grep -q "no dispatch for #999 (D18)" <<<"$out" && grep -q "skipping claim release" <<<"$out"; then
        pass "AT-4 (D1): claim release correctly skipped under autonomous_merge: false"
    else
        fail "AT-4 (D1): lifecycle_advance.sh did not handle claim release skipping under autonomous_merge: false"
    fi
}
run_at4

# =============================================================================
# AT-5 (D1): Advance to terminal review rung releases claim of odyssey and removes in-progress
# =============================================================================
run_at5() {
    local name="AT-5"
    should_run "$name" || return 0
    TOTAL=$((TOTAL + 1))
    banner "$name (D1): Claim release on terminal review rung advance"
    reset_fixtures

    cat > "$FIXTURES/issue-999.json" <<'EOF'
{
  "number": 999,
  "state": "OPEN",
  "labels": [{"name": "status:implementing"}, {"name": "in-progress"}],
  "comments": [
    {
      "user": {"login": "evekhm-odyssey-app[bot]"},
      "body": "Claim: odyssey (session-1) stage:implement path:.claude/worktrees/odyssey-999-test"
    }
  ]
}
EOF
    cat > "$FIXTURES/pulls-$C2.json" <<EOF
[
  {
    "number": 4242,
    "merged_at": "2026-01-01T00:00:00Z",
    "state": "closed",
    "merge_commit_sha": "$C2",
    "base": {"ref": "main"},
    "head": {"ref": "odyssey/999-test", "repo": {"full_name": "evekhm/agentic-sdlc"}},
    "body": "Fixes #999"
  }
]
EOF
    cat > "$FIXTURES/files-4242.json" <<'EOF'
[{"filename": "scripts/ci/tests/dummy_test.sh"}]
EOF
    echo "true" > "$FIXTURES/loop-autonomous_merge"
    echo "10" > "$FIXTURES/loop-max_rung_dispatches_per_issue"
    echo "50.00" > "$FIXTURES/loop-max_cost_usd_per_issue"
    echo "ladder vm-local 50.00" > "$FIXTURES/binding-vm-local"

    local out=""
    out="$(cd "$SANDBOX" && DRY_RUN=1 bash "$ADVANCER" "$C1" "$C2" 2>&1 || true)"
    if grep -qF "released claim of odyssey on #999 (rung implement merged)" <<<"$out"; then
        pass "AT-5 (D1): lifecycle_advance.sh released claim of odyssey on terminal review rung"
    else
        fail "AT-5 (D1): lifecycle_advance.sh did not print 'released claim of odyssey on #999 (rung implement merged)'"
    fi
}
run_at5

# =============================================================================
# AT-6 (D2, #284): Placement adapter dispatch invocation passes <issue> --as <persona> in argv
# =============================================================================
run_at6() {
    local name="AT-6"
    should_run "$name" || return 0
    TOTAL=$((TOTAL + 1))
    banner "$name (D2, #284): Placement adapter invocation passes <issue> --as <persona>"
    reset_fixtures

    cat > "$FIXTURES/issue-999.json" <<'EOF'
{
  "number": 999,
  "state": "OPEN",
  "labels": [{"name": "status:planning"}],
  "comments": []
}
EOF
    cat > "$FIXTURES/pulls-$C2.json" <<EOF
[
  {
    "number": 4242,
    "merged_at": "2026-01-01T00:00:00Z",
    "state": "closed",
    "merge_commit_sha": "$C2",
    "base": {"ref": "main"},
    "head": {"ref": "athena/999-test", "repo": {"full_name": "evekhm/agentic-sdlc"}},
    "body": "Fixes #999"
  }
]
EOF
    cat > "$FIXTURES/files-4242.json" <<'EOF'
[{"filename": "intent/999-test/spec.md"}]
EOF
    echo "true" > "$FIXTURES/loop-autonomous_merge"
    echo "10" > "$FIXTURES/loop-max_rung_dispatches_per_issue"
    echo "50.00" > "$FIXTURES/loop-max_cost_usd_per_issue"
    echo "ladder vm-local 50.00" > "$FIXTURES/binding-vm-local"

    local out=""
    out="$(cd "$SANDBOX" && DRY_RUN=1 bash "$ADVANCER" "$C1" "$C2" 2>&1 || true)"
    if grep -qE "scripts/placement/[a-z-]+/run\.sh 999 --as athena" <<<"$out"; then
        pass "AT-6 (D2, #284): adapter invocation passed 999 --as athena"
    else
        fail "AT-6 (D2, #284): adapter invocation argv did not contain '999 --as athena'"
    fi
}
run_at6

# =============================================================================
# AT-7 (D2): GITHUB_ACTIONS=true run.sh --as athena delegates to VM poller and exits 0
# =============================================================================
run_at7() {
    local name="AT-7"
    should_run "$name" || return 0
    TOTAL=$((TOTAL + 1))
    banner "$name (D2): GITHUB_ACTIONS delegation in vm-local run.sh"
    local run_sh="$REPO/scripts/placement/vm-local/run.sh"

    local out="" rc=0
    out="$(GITHUB_ACTIONS=true bash "$run_sh" 251 --as athena 2>&1)" || rc=$?
    if [ "$rc" -eq 0 ] && grep -qF "delegating #251 execution to operator VM poller" <<<"$out"; then
        pass "AT-7 (D2): run.sh delegated execution to operator VM poller"
    else
        fail "AT-7 (D2): run.sh did not print 'delegating #251 execution to operator VM poller' and exit 0 (rc=$rc)"
    fi
}
run_at7

# =============================================================================
# AT-8 (D2): poll.sh syntax check and unconsumed row dispatch under minted token
# =============================================================================
run_at8() {
    local name="AT-8"
    should_run "$name" || return 0
    TOTAL=$((TOTAL + 1))
    banner "$name (D2): poll.sh executable validation and mock ledger dispatch"
    local poll_sh="$REPO/scripts/placement/vm-local/poll.sh"

    if [ ! -f "$poll_sh" ]; then
        fail "AT-8 (D2): scripts/placement/vm-local/poll.sh does not exist"
        return 0
    fi

    if ! bash -n "$poll_sh"; then
        fail "AT-8 (D2): bash -n scripts/placement/vm-local/poll.sh exited non-zero"
        return 0
    fi

    reset_fixtures
    cat > "$FIXTURES/repos_evekhm_agentic-sdlc_issues_251.json" <<'EOF'
{
  "number": 251,
  "state": "open",
  "labels": [{"name": "status:spec"}]
}
EOF
    cat > "$FIXTURES/comments-251.json" <<'EOF'
[
  {
    "user": {"login": "evekhm-themis-app[bot]"},
    "body": "<!-- loop-ledger:251 -->\n<!-- loop-ledger-row: dispatch rung:2 head-oid:4f862c6b8cac5ea82f0792e908aec72fda85ad91 pr:none event:local cost:2.00 -->"
  }
]
EOF

    local out="" rc=0
    out="$(bash "$poll_sh" --once 2>&1)" || rc=$?
    if [ "$rc" -eq 0 ] && grep -qF "CLAIM_ACTOR=" "$WRITES" 2>/dev/null; then
        pass "AT-8 (D2): poll.sh --once claimed and dispatched unconsumed row"
    else
        fail "AT-8 (D2): poll.sh --once failed to claim or dispatch unconsumed ledger row"
    fi
}
run_at8

# =============================================================================
# AT-9 (D2): poll.sidecar.json configuration and restart_policy validation
# =============================================================================
run_at9() {
    local name="AT-9"
    should_run "$name" || return 0
    TOTAL=$((TOTAL + 1))
    banner "$name (D2): poll.sidecar.json validation"
    local sidecar="$REPO/scripts/placement/vm-local/poll.sidecar.json"

    if [ ! -f "$sidecar" ]; then
        fail "AT-9 (D2): scripts/placement/vm-local/poll.sidecar.json does not exist"
        return 0
    fi

    if ! "$REAL_PYTHON3" -m json.tool "$sidecar" >/dev/null 2>&1; then
        fail "AT-9 (D2): poll.sidecar.json is not valid JSON"
        return 0
    fi

    if "$REAL_JQ" -e '.command and .args and .env and (.restart_policy == "always")' "$sidecar" >/dev/null 2>&1; then
        pass "AT-9 (D2): poll.sidecar.json carries valid command, args, env, and restart_policy"
    else
        fail "AT-9 (D2): poll.sidecar.json missing required command, args, env, or restart_policy always"
    fi
}
run_at9

# =============================================================================
# AT-10 (D2): poll.service systemd unit configuration validation
# =============================================================================
run_at10() {
    local name="AT-10"
    should_run "$name" || return 0
    TOTAL=$((TOTAL + 1))
    banner "$name (D2): poll.service systemd unit validation"
    local service="$REPO/scripts/placement/vm-local/poll.service"

    if [ ! -f "$service" ]; then
        fail "AT-10 (D2): scripts/placement/vm-local/poll.service does not exist"
        return 0
    fi

    if grep -E '^(Type=simple|Restart=always|ExecStart=)' "$service" >/dev/null 2>&1; then
        pass "AT-10 (D2): poll.service carries required systemd unit configuration"
    else
        fail "AT-10 (D2): poll.service missing Type=simple, Restart=always, or ExecStart="
    fi
}
run_at10

# =============================================================================
# AT-12 (D2): Re-pin property from antigravity to claude-code and back
# =============================================================================
run_at12() {
    local name="AT-12"
    should_run "$name" || return 0
    TOTAL=$((TOTAL + 1))
    banner "$name (D2): Re-pin property in stub"
    local work_sh="$REPO/scripts/ops/work.sh"
    local fixture_dep="$WORK/fixture-deployments.yaml"

    reset_fixtures
    cat > "$FIXTURES/issue-108.json" <<'EOF'
{
  "number": 108,
  "state": "OPEN",
  "labels": [{"name": "status:implementing"}]
}
EOF

    # Write fixture with antigravity pin
    cat > "$fixture_dep" <<'EOF'
personas:
  odyssey:
    harness: antigravity
EOF

    # Run stub work.sh with fixture deployments
    LAUNCH_OK=1 HEADLESS=1 DRY_RUN=0 DEPLOYMENTS="$fixture_dep" bash "$work_sh" 108 --as odyssey >/dev/null 2>&1 || true

    # Update fixture to claude-code
    cat > "$fixture_dep" <<'EOF'
personas:
  odyssey:
    harness: claude-code
EOF
    : > "$LAUNCHES"
    LAUNCH_OK=1 HEADLESS=1 DRY_RUN=0 DEPLOYMENTS="$fixture_dep" bash "$work_sh" 108 --as odyssey >/dev/null 2>&1 || true

    if grep -q "claude -p .* --agent odyssey --output-format json" "$LAUNCHES" 2>/dev/null; then
        pass "AT-12 (D2): re-pin property verified"
    else
        fail "AT-12 (D2): updating fixture deployments.yaml did not invoke 'claude -p ... --agent odyssey --output-format json'"
    fi
}
run_at12

# =============================================================================
# AT-13 (D2, D8): Fix-round dispatch work.sh on PR authored by odyssey under status:in-review
# =============================================================================
run_at13() {
    local name="AT-13"
    should_run "$name" || return 0
    TOTAL=$((TOTAL + 1))
    banner "$name (D2, D8): Fix-round dispatch on PR at status:in-review"
    local work_sh="$REPO/scripts/ops/work.sh"

    reset_fixtures
    cat > "$FIXTURES/issue-107.json" <<'EOF'
{
  "number": 107,
  "state": "open",
  "title": "Issue 107",
  "labels": [{"name": "status:in-review"}],
  "comments": []
}
EOF
    cat > "$FIXTURES/issue-108.json" <<'EOF'
{
  "number": 108,
  "state": "open",
  "title": "PR 108",
  "body": "Fixes #107",
  "labels": [{"name": "status:in-review"}],
  "pull_request": {"url": "https://api.github.com/repos/evekhm/agentic-sdlc/pulls/108"},
  "comments": []
}
EOF
    cat > "$FIXTURES/repos_evekhm_agentic-sdlc_pulls_108.json" <<'EOF'
{
  "head": {
    "ref": "odyssey/107-fix",
    "repo": {"full_name": "evekhm/agentic-sdlc"}
  }
}
EOF

    local out="" rc=0
    out="$(DRY_RUN=1 HEADLESS=1 bash "$work_sh" 108 --as odyssey 2>&1)" || rc=$?
    if [ "$rc" -eq 2 ] && grep -q "does not own stage review" <<<"$out"; then
        fail "AT-13 (D2, D8): work.sh rejected fix-round with refusal (h): $out"
    elif [ "$rc" -eq 0 ] && ! grep -q "does not own stage review" <<<"$out"; then
        pass "AT-13 (D2, D8): work.sh proceeded under fix-round resume protocol"
    else
        fail "AT-13 (D2, D8): work.sh exited with unexpected status $rc: $out"
    fi
}
run_at13

# =============================================================================
# AT-14 (D4): Missing persona credential handling logs missing key and continues
# =============================================================================
run_at14() {
    local name="AT-14"
    should_run "$name" || return 0
    TOTAL=$((TOTAL + 1))
    banner "$name (D4): Missing credential handling"
    local poll_sh="$REPO/scripts/placement/vm-local/poll.sh"

    if [ ! -f "$poll_sh" ]; then
        fail "AT-14 (D4): scripts/placement/vm-local/poll.sh does not exist"
        return 0
    fi

    reset_fixtures
    cat > "$FIXTURES/repos_evekhm_agentic-sdlc_issues_251.json" <<'EOF'
{
  "number": 251,
  "state": "open",
  "labels": [{"name": "status:planning"}]
}
EOF

    local out="" rc=0
    out="$(FAIL_MINT=1 bash "$poll_sh" --once 2>&1)" || rc=$?
    if [ "$rc" -eq 0 ] && grep -qF "missing key for athena, skipping its rows" <<<"$out" && [ ! -s "$LAUNCHES" ]; then
        pass "AT-14 (D4): poll.sh logged missing key notice, skipped launch, and exited 0"
    else
        fail "AT-14 (D4): poll.sh failed to log 'missing key for <persona>, skipping its rows' or exited non-zero"
    fi
}
run_at14

# =============================================================================
# AT-15 (D5): First hop on open intent:new issue claims then dispatches with zero ledger rows
# =============================================================================
run_at15() {
    local name="AT-15"
    should_run "$name" || return 0
    TOTAL=$((TOTAL + 1))
    banner "$name (D5): First hop on open intent:new issue"
    local poll_sh="$REPO/scripts/placement/vm-local/poll.sh"

    if [ ! -f "$poll_sh" ]; then
        fail "AT-15 (D5): scripts/placement/vm-local/poll.sh does not exist"
        return 0
    fi

    reset_fixtures
    cat > "$FIXTURES/repos_evekhm_agentic-sdlc_issues_300.json" <<'EOF'
{
  "number": 300,
  "state": "open",
  "labels": [{"name": "intent:new"}]
}
EOF
    cat > "$FIXTURES/comments-300.json" <<'EOF'
[]
EOF

    local out="" rc=0
    out="$(bash "$poll_sh" --once 2>&1)" || rc=$?
    if [ "$rc" -eq 0 ] && grep -qF "scripts/ops/claim.sh 300" "$INVOKES" 2>/dev/null; then
        pass "AT-15 (D5): first hop claimed and dispatched open intent:new issue"
    else
        fail "AT-15 (D5): poll.sh did not claim and dispatch open intent:new issue"
    fi
}
run_at15

# =============================================================================
# AT-17 (D6, D8): Living spec deployment status section carries 7 steps and odyssey ladder table row
# =============================================================================
run_at17() {
    local name="AT-17"
    should_run "$name" || return 0
    TOTAL=$((TOTAL + 1))
    banner "$name (D6, D8): Living spec deployment status verification"
    local spec_doc="$REPO/docs/SPEC.md"

    if [ ! -f "$spec_doc" ]; then
        fail "AT-17 (D6, D8): docs/SPEC.md does not exist"
        return 0
    fi

    local steps=0 manual_count=0 ladder_count=0
    steps="$(sed -n '/## Deployment status/,/##/p' "$spec_doc" | grep -c '^[0-9]\. ' || true)"
    manual_count="$(grep -c 'odyssey `manual`' "$spec_doc" || true)"
    ladder_count="$(grep -c 'odyssey `ladder`' "$spec_doc" || true)"

    if [ "$steps" -eq 7 ] && [ "$manual_count" -eq 0 ] && [ "$ladder_count" -eq 1 ]; then
        pass "AT-17 (D6, D8): docs/SPEC.md deployment status section and table updated"
    else
        fail "AT-17 (D6, D8): docs/SPEC.md missing 7-step checklist or odyssey ladder update (steps: $steps, manual: $manual_count, ladder: $ladder_count)"
    fi
}
run_at17

# =============================================================================
# AT-20 (D2): Fix-round claim bypass and per-PR lock duplicate prevention
# =============================================================================
run_at20() {
    local name="AT-20"
    should_run "$name" || return 0
    TOTAL=$((TOTAL + 1))
    banner "$name (D2): Fix-round claim bypass and per-PR lock"
    local poll_sh="$REPO/scripts/placement/vm-local/poll.sh"

    if [ ! -f "$poll_sh" ]; then
        fail "AT-20 (D2): scripts/placement/vm-local/poll.sh does not exist"
        return 0
    fi

    reset_fixtures
    cat > "$FIXTURES/issue-108.json" <<'EOF'
{
  "number": 108,
  "state": "open",
  "labels": [{"name": "status:in-review"}],
  "pull_request": {"url": "https://api.github.com/repos/evekhm/agentic-sdlc/pulls/108"}
}
EOF
    cat > "$FIXTURES/comments-108.json" <<'EOF'
[
  {
    "user": {"login": "evekhm-argus-app[bot]"},
    "body": "review findings: blocking"
  }
]
EOF

    local out="" rc=0
    out="$(bash "$poll_sh" --once 2>&1)" || rc=$?
    if [ "$rc" -eq 0 ] && [ ! -s "$WRITES" ]; then
        pass "AT-20 (D2): fix-round claim bypass and locking verified"
    else
        fail "AT-20 (D2): poll.sh failed fix-round claim bypass or locking"
    fi
}
run_at20

# =============================================================================
# Summary
# =============================================================================
banner "Summary"
echo "e2e_chain_test.sh results: $PASSED passed, $FAILED failed out of $TOTAL run"

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
exit 0
