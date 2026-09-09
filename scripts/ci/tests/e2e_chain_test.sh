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
    [ -z "$FILTER" ] && return 0
    grep -qE "^($FILTER)( |$)" <<<"$1"
}

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FIXTURES="$WORK/fixtures"
WRITES="$WORK/writes.log"
INVOKES="$WORK/invocations.log"
LAUNCHES="$WORK/launches.log"
CLAIMS="$WORK/claims.log"
MINTS="$WORK/mints.log"
mkdir -p "$FIXTURES" "$WORK/bin"
: > "$WRITES"
: > "$INVOKES"
: > "$LAUNCHES"
: > "$CLAIMS"
: > "$MINTS"

export WORK FIXTURES WRITES INVOKES LAUNCHES CLAIMS MINTS
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
label_filter=""
json_fields=""
jq_expr=""
for (( idx=0; idx<${#args[@]}; idx++ )); do
    case "${args[$idx]}" in
        --label|-l)
            idx=$((idx + 1))
            label_filter="${args[$idx]:-}"
            ;;
        --label=*)
            label_filter="${args[$idx]#--label=}"
            ;;
        --json)
            idx=$((idx + 1))
            json_fields="${args[$idx]:-}"
            ;;
        --json=*)
            json_fields="${args[$idx]#--json=}"
            ;;
        --jq|-q)
            idx=$((idx + 1))
            jq_expr="${args[$idx]:-}"
            ;;
        --jq=*|-q=*)
            jq_expr="${args[$idx]#*=}"
            ;;
    esac
done

output_json() {
    local raw="$1"
    if [ -n "$jq_expr" ]; then
        "$REAL_JQ" -r "$jq_expr" <<<"$raw"
    else
        echo "$raw"
    fi
    exit 0
}

if [ "$cmd" = "issue" ] || [ "$cmd" = "pr" ] || [ "$cmd" = "search" ]; then
    subcmd="${args[1]:-}"
    target="${args[2]:-}"
    if [ "$subcmd" = "view" ]; then
        if [ -f "$FIXTURES/issue-$target.unreadable" ]; then
            exit 1
        fi
        content=""
        if [ -f "$FIXTURES/issue-$target.json" ]; then
            content="$(cat "$FIXTURES/issue-$target.json")"
        elif [ -f "$FIXTURES/repos_evekhm_agentic-sdlc_issues_${target}.json" ]; then
            content="$(cat "$FIXTURES/repos_evekhm_agentic-sdlc_issues_${target}.json")"
        else
            content="$("$REAL_JQ" -nc --argjson n "$target" '{number: $n, state: "open", labels: [], comments: []}')"
        fi
        if [ -n "$json_fields" ]; then
            fields_expr="$(echo "$json_fields" | sed 's/,/, /g')"
            content="$("$REAL_JQ" -c "{$fields_expr}" <<<"$content")"
        fi
        output_json "$content"
    fi

    if [ "$subcmd" = "list" ] || [ "$cmd" = "search" ]; then
        content="[]"
        if [ "$cmd" = "pr" ] || [ "$subcmd" = "prs" ]; then
            [ -f "$FIXTURES/pr-list.json" ] && content="$(cat "$FIXTURES/pr-list.json")"
        else
            [ -f "$FIXTURES/issue-list.json" ] && content="$(cat "$FIXTURES/issue-list.json")"
        fi
        if [ -n "$label_filter" ]; then
            content="$("$REAL_JQ" --arg l "$label_filter" '[.[] | select(.labels | if type == "array" then any(.[]; (.name // .) == $l) else false end)]' <<<"$content")"
        fi
        if [ -n "$json_fields" ]; then
            fields_expr="$(echo "$json_fields" | sed 's/,/, /g')"
            content="$("$REAL_JQ" -c "[.[] | {$fields_expr}]" <<<"$content")"
        fi
        output_json "$content"
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
        */issues/*/comments*|repos/*/issues/*/comments*)
            n="${clean_path#*issues/}"
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
        repos/*/issues/[0-9]*)
            n="${clean_path##*/}"
            if [ -f "$FIXTURES/issue-$n.json" ]; then
                cat "$FIXTURES/issue-$n.json"
                exit 0
            fi
            "$REAL_JQ" -nc --argjson n "$n" '{number: $n, state: "open", labels: [], comments: []}'
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
        repos/*/issues|repos/*/issues\?*|repos/*/pulls|repos/*/pulls\?*)
            content="[]"
            if [[ "$clean_path" == *"pulls"* ]]; then
                [ -f "$FIXTURES/pr-list.json" ] && content="$(cat "$FIXTURES/pr-list.json")"
            else
                [ -f "$FIXTURES/issue-list.json" ] && content="$(cat "$FIXTURES/issue-list.json")"
            fi
            if [ -n "$label_filter" ]; then
                content="$("$REAL_JQ" --arg l "$label_filter" '[.[] | select(.labels | if type == "array" then any(.[]; (.name // .) == $l) else false end)]' <<<"$content")"
            fi
            output_json "$content"
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
if [ "${2:-}" = "--binding" ]; then
    if [ -f "$FIXTURES/binding-${3:-}" ]; then
        cat "$FIXTURES/binding-$3"
        exit 0
    elif [ -f "$FIXTURES/binding-vm-local" ]; then
        cat "$FIXTURES/binding-vm-local"
        exit 0
    fi
fi
# Stub mint_app_token.py
for arg in "$@"; do
    case "$arg" in
        *mint_app_token.py*)
            echo "mint $*" >> "$MINTS"
            persona="${@: -1}"
            for p in "$@"; do
                case "$p" in
                    athena|odyssey|daedalus|themis|argus|atlas)
                        persona="$p"
                        ;;
                esac
            done
            if [ -n "${FAIL_MINT_PERSONA:-}" ] && [ "$persona" = "$FAIL_MINT_PERSONA" ]; then
                echo "stub mint: missing private key for $persona" >&2
                exit 1
            fi
            if [ "${FAIL_MINT:-0}" = "1" ]; then
                echo "stub mint: missing private key for $persona" >&2
                exit 1
            fi
            echo "mock-token-$persona"
            exit 0
            ;;
        *execution.py*--spend-ceiling*|*execution.py*--binding*)
            echo "50.00"
            exit 0
            ;;
    esac
done
exec "$REAL_PYTHON3" "$@"
PYSTUB
chmod +x "$WORK/bin/python3"

# --- Harness and dispatch stubs -----------------------------------------------
cat > "$WORK/bin/claude" <<'CLAUDETESTUB'
#!/usr/bin/env bash
echo "claude $*" >> "$LAUNCHES"
echo "WORK-RESULT: ok"
exit 0
CLAUDETESTUB
chmod +x "$WORK/bin/claude"

cat > "$WORK/bin/agy" <<'AGYSTUB'
#!/usr/bin/env bash
echo "agy $*" >> "$LAUNCHES"
echo "WORK-RESULT: ok"
exit 0
AGYSTUB
chmod +x "$WORK/bin/agy"

cat > "$WORK/bin/run.sh" <<'RUNSTUB'
#!/usr/bin/env bash
echo "run.sh $*" >> "$LAUNCHES"
exit 0
RUNSTUB
chmod +x "$WORK/bin/run.sh"

cat > "$WORK/bin/claim.sh" <<'CLAIMSTUB'
#!/usr/bin/env bash
if [ ! -f "$WORK/.first_claim_checked" ]; then
    touch "$WORK/.first_claim_checked"
    if grep -qE 'gh (issue list.*(--label|-l)|api.*repos/[^/]+/[^/]+/issues\?.*labels=)' "$INVOKES" 2>/dev/null; then
        touch "$WORK/.first_claim_had_list_query"
    fi
fi
echo "claim.sh CLAIM_ACTOR=${CLAIM_ACTOR:-} CLAIM_SESSION=${CLAIM_SESSION:-} $*" >> "$CLAIMS"
issue="${1:-}"
issue="${issue#\#}"
if [ -f "$FIXTURES/issue-$issue.json" ]; then
    if "$REAL_JQ" -e '.labels[]? | select((.name // .) == "in-progress")' "$FIXTURES/issue-$issue.json" >/dev/null 2>&1; then
        echo "already claimed" >&2
        exit 1
    fi
fi
exit 0
CLAIMSTUB
chmod +x "$WORK/bin/claim.sh"

# Setup synthetic git ranges for lifecycle tests (Decision B, NB 3)
SANDBOX="$WORK/repo"
mkdir -p "$SANDBOX/personas" "$SANDBOX/scripts"
cp "$REPO/personas/lifecycle.json" "$SANDBOX/personas/lifecycle.json"
cp "$REPO"/personas/*.yaml "$SANDBOX/personas/"
cp -r "$REPO/scripts/ci" "$SANDBOX/scripts/"
cp -r "$REPO/scripts/ops" "$SANDBOX/scripts/"
cp -r "$REPO/scripts/placement" "$SANDBOX/scripts/"

cat > "$SANDBOX/scripts/ops/claim.sh" <<'SANDBOXCLAIM'
#!/usr/bin/env bash
if [ ! -f "$WORK/.first_claim_checked" ]; then
    touch "$WORK/.first_claim_checked"
    if grep -qE 'gh (issue list.*(--label|-l)|api.*repos/[^/]+/[^/]+/issues\?.*labels=)' "$INVOKES" 2>/dev/null; then
        touch "$WORK/.first_claim_had_list_query"
    fi
fi
echo "claim.sh CLAIM_ACTOR=${CLAIM_ACTOR:-} CLAIM_SESSION=${CLAIM_SESSION:-} $*" >> "$CLAIMS"
issue="${1:-}"
issue="${issue#\#}"
if [ -f "$FIXTURES/issue-$issue.json" ]; then
    if "$REAL_JQ" -e '.labels[]? | select((.name // .) == "in-progress")' "$FIXTURES/issue-$issue.json" >/dev/null 2>&1; then
        echo "already claimed" >&2
        exit 1
    fi
fi
exit 0
SANDBOXCLAIM
chmod +x "$SANDBOX/scripts/ops/claim.sh"

cat > "$SANDBOX/scripts/placement/vm-local/run.sh" <<'SANDBOXRUN'
#!/usr/bin/env bash
echo "run.sh $*" >> "$LAUNCHES"
exit 0
SANDBOXRUN
chmod +x "$SANDBOX/scripts/placement/vm-local/run.sh"

(
    cd "$SANDBOX" || exit 1
    "$REAL_GIT" init -q .
    "$REAL_GIT" config user.email test@example.com
    "$REAL_GIT" config user.name test
    echo seed > seed.txt
    "$REAL_GIT" add -A
    "$REAL_GIT" commit -qm seed
    C_BASE="$("$REAL_GIT" rev-parse HEAD)"

    # Range 1 (intent): adds intent/999-test/intent.md
    "$REAL_GIT" checkout -qb intent-br "$C_BASE"
    mkdir -p intent/999-test
    printf '# Intent\n' > intent/999-test/intent.md
    "$REAL_GIT" add -A
    "$REAL_GIT" commit -qm intent
    C_INTENT="$("$REAL_GIT" rev-parse HEAD)"

    # Range 2 (spec): adds intent/999-test/spec.md
    "$REAL_GIT" checkout -qb spec-br "$C_INTENT"
    printf '# Spec\n\n**Issue:** #999 · **Status:** Approved (approval = merge of this PR)\n' \
      > intent/999-test/spec.md
    "$REAL_GIT" add -A
    "$REAL_GIT" commit -qm spec
    C_SPEC="$("$REAL_GIT" rev-parse HEAD)"

    # Range 3 (implement-pr): merge commit merging branch odyssey/999-test
    "$REAL_GIT" checkout -qb odyssey/999-test "$C_SPEC"
    mkdir -p scripts/ci/tests
    echo "echo test" > scripts/ci/tests/dummy_test.sh
    "$REAL_GIT" add -A
    "$REAL_GIT" commit -qm "imp-code"
    C_IMP_HEAD="$("$REAL_GIT" rev-parse HEAD)"

    "$REAL_GIT" checkout -qb main-br "$C_SPEC"
    "$REAL_GIT" merge -qm "merge PR 4242" --no-ff "$C_IMP_HEAD"
    C_IMP_MERGE="$("$REAL_GIT" rev-parse HEAD)"

    echo "$C_BASE" > "$WORK/c_base"
    echo "$C_INTENT" > "$WORK/c_intent"
    echo "$C_SPEC" > "$WORK/c_spec"
    echo "$C_IMP_HEAD" > "$WORK/c_imp_head"
    echo "$C_IMP_MERGE" > "$WORK/c_imp_merge"
)
C_BASE="$(cat "$WORK/c_base")"
C_INTENT="$(cat "$WORK/c_intent")"
C_SPEC="$(cat "$WORK/c_spec")"
C_IMP_HEAD="$(cat "$WORK/c_imp_head")"
C_IMP_MERGE="$(cat "$WORK/c_imp_merge")"

get_range() {
    local kind="$1"
    case "$kind" in
        intent)
            RANGE_BEFORE="$C_BASE"
            RANGE_AFTER="$C_INTENT"
            ;;
        spec)
            RANGE_BEFORE="$C_INTENT"
            RANGE_AFTER="$C_SPEC"
            ;;
        implement-pr)
            RANGE_BEFORE="$C_SPEC"
            RANGE_AFTER="$C_IMP_MERGE"
            ;;
        *)
            echo "unknown range kind: $kind" >&2
            return 1
            ;;
    esac
}

reset_fixtures() {
    rm -f "$FIXTURES"/*.json "$FIXTURES"/*.unreadable "$FIXTURES"/loop-* "$FIXTURES"/binding-*
    rm -f "$WORK/.first_claim_checked" "$WORK/.first_claim_had_list_query"
    : > "$WRITES"
    : > "$INVOKES"
    : > "$LAUNCHES"
    : > "$CLAIMS"
    : > "$MINTS"
    unset FAIL_MINT_PERSONA
    unset FAIL_MINT
}

ADVANCER="$SANDBOX/scripts/ci/lifecycle_advance.sh"

# =============================================================================
# AT-1 (D1): Ladder rung transition releases claim when claim author login matches completing stage persona
# =============================================================================
run_at1() {
    local name="AT-1"
    should_run "$name" || return 0
    TOTAL=$((TOTAL + 1))
    banner "$name (D1): Claim release on ladder advance"
    reset_fixtures

    get_range "intent"

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
    cat > "$FIXTURES/pulls-$RANGE_AFTER.json" <<EOF
[
  {
    "number": 4242,
    "merged_at": "2026-01-01T00:00:00Z",
    "state": "closed",
    "merge_commit_sha": "$RANGE_AFTER",
    "base": {"ref": "main"},
    "head": {"ref": "athena/999-test", "repo": {"full_name": "evekhm/agentic-sdlc"}},
    "body": "Fixes #999"
  }
]
EOF
    cat > "$FIXTURES/files-4242.json" <<'EOF'
[{"filename": "intent/999-test/intent.md"}]
EOF
    echo "true" > "$FIXTURES/loop-autonomous_merge"
    echo "10" > "$FIXTURES/loop-max_rung_dispatches_per_issue"
    echo "50.00" > "$FIXTURES/loop-max_cost_usd_per_issue"
    echo "ladder vm-local 50.00" > "$FIXTURES/binding-vm-local"

    local out=""
    out="$(cd "$SANDBOX" && bash "$ADVANCER" "$RANGE_BEFORE" "$RANGE_AFTER" 2>&1 || true)"
    local res_line=""
    res_line="$(grep -E '^--> #999' <<<"$out" || true)"
    [ -z "$res_line" ] || echo "    $res_line"

    local has_rel=0 has_del=0 has_launch=0
    grep -qF "released claim of athena on #999 (rung plan merged)" <<<"$out" && has_rel=1
    grep -qF "DELETE labels 999 in-progress" "$WRITES" && has_del=1
    grep -qE "999 --as athena" "$LAUNCHES" && has_launch=1

    if [ "$has_rel" -eq 1 ] && [ "$has_del" -eq 1 ] && [ "$has_launch" -eq 1 ]; then
        pass "AT-1 (D1): lifecycle_advance.sh released claim of athena on #999 and dispatched successor"
    else
        fail "AT-1 (D1): lifecycle_advance.sh failed claim release (missing DELETE labels 999 in-progress: del=$has_del, rel=$has_rel, launch=$has_launch)"
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

    get_range "intent"

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
    cat > "$FIXTURES/pulls-$RANGE_AFTER.json" <<EOF
[
  {
    "number": 4242,
    "merged_at": "2026-01-01T00:00:00Z",
    "state": "closed",
    "merge_commit_sha": "$RANGE_AFTER",
    "base": {"ref": "main"},
    "head": {"ref": "athena/999-test", "repo": {"full_name": "evekhm/agentic-sdlc"}},
    "body": "Fixes #999"
  }
]
EOF
    cat > "$FIXTURES/files-4242.json" <<'EOF'
[{"filename": "intent/999-test/intent.md"}]
EOF
    echo "true" > "$FIXTURES/loop-autonomous_merge"
    echo "10" > "$FIXTURES/loop-max_rung_dispatches_per_issue"
    echo "50.00" > "$FIXTURES/loop-max_cost_usd_per_issue"
    echo "ladder vm-local 50.00" > "$FIXTURES/binding-vm-local"

    local out=""
    out="$(cd "$SANDBOX" && bash "$ADVANCER" "$RANGE_BEFORE" "$RANGE_AFTER" 2>&1 || true)"
    local res_line=""
    res_line="$(grep -E '^--> #999' <<<"$out" || true)"
    [ -z "$res_line" ] || echo "    $res_line"

    if grep -qF "withholding dispatch: in-progress held by odyssey" <<<"$out" \
       && ! grep -qF "DELETE labels 999 in-progress" "$WRITES" \
       && [ ! -s "$LAUNCHES" ]; then
        pass "AT-2 (D1): lifecycle_advance.sh withheld dispatch for claim held by different persona"
    else
        fail "AT-2 (D1): lifecycle_advance.sh did not withhold dispatch or deleted claim"
    fi
}
run_at2

# =============================================================================
# AT-3 (D1): Ladder advance withholds dispatch when in-progress held by foreign login or unparseable
# =============================================================================
run_at3() {
    local name="AT-3"
    should_run "$name" || return 0
    TOTAL=$((TOTAL + 1))
    banner "$name (D1): Withhold dispatch when claim held by foreign login or unparseable"
    reset_fixtures

    get_range "intent"

    # Sub-case A: foreign login
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
    cat > "$FIXTURES/pulls-$RANGE_AFTER.json" <<EOF
[
  {
    "number": 4242,
    "merged_at": "2026-01-01T00:00:00Z",
    "state": "closed",
    "merge_commit_sha": "$RANGE_AFTER",
    "base": {"ref": "main"},
    "head": {"ref": "athena/999-test", "repo": {"full_name": "evekhm/agentic-sdlc"}},
    "body": "Fixes #999"
  }
]
EOF
    cat > "$FIXTURES/files-4242.json" <<'EOF'
[{"filename": "intent/999-test/intent.md"}]
EOF
    echo "true" > "$FIXTURES/loop-autonomous_merge"
    echo "10" > "$FIXTURES/loop-max_rung_dispatches_per_issue"
    echo "50.00" > "$FIXTURES/loop-max_cost_usd_per_issue"
    echo "ladder vm-local 50.00" > "$FIXTURES/binding-vm-local"

    local out_a="" pass_a=0
    out_a="$(cd "$SANDBOX" && bash "$ADVANCER" "$RANGE_BEFORE" "$RANGE_AFTER" 2>&1 || true)"
    local res_line_a=""
    res_line_a="$(grep -E '^--> #999' <<<"$out_a" || true)"
    [ -z "$res_line_a" ] || echo "    $res_line_a"

    if grep -qE "withholding dispatch: in-progress held by (foreign login|foreign-user)" <<<"$out_a" \
       && ! grep -qF "DELETE labels 999 in-progress" "$WRITES" \
       && [ ! -s "$LAUNCHES" ]; then
        pass_a=1
    fi

    # Sub-case B: unparseable / missing claim comment
    reset_fixtures
    cat > "$FIXTURES/issue-999.json" <<'EOF'
{
  "number": 999,
  "state": "OPEN",
  "labels": [{"name": "status:planning"}, {"name": "in-progress"}],
  "comments": []
}
EOF
    cat > "$FIXTURES/pulls-$RANGE_AFTER.json" <<EOF
[
  {
    "number": 4242,
    "merged_at": "2026-01-01T00:00:00Z",
    "state": "closed",
    "merge_commit_sha": "$RANGE_AFTER",
    "base": {"ref": "main"},
    "head": {"ref": "athena/999-test", "repo": {"full_name": "evekhm/agentic-sdlc"}},
    "body": "Fixes #999"
  }
]
EOF
    cat > "$FIXTURES/files-4242.json" <<'EOF'
[{"filename": "intent/999-test/intent.md"}]
EOF
    echo "true" > "$FIXTURES/loop-autonomous_merge"
    echo "10" > "$FIXTURES/loop-max_rung_dispatches_per_issue"
    echo "50.00" > "$FIXTURES/loop-max_cost_usd_per_issue"
    echo "ladder vm-local 50.00" > "$FIXTURES/binding-vm-local"

    local out_b="" pass_b=0
    out_b="$(cd "$SANDBOX" && bash "$ADVANCER" "$RANGE_BEFORE" "$RANGE_AFTER" 2>&1 || true)"

    if grep -qE "withholding dispatch: in-progress held without a readable claim|unparseable claim" <<<"$out_b" \
       && ! grep -qF "DELETE labels 999 in-progress" "$WRITES" \
       && [ ! -s "$LAUNCHES" ]; then
        pass_b=1
    fi

    if [ "$pass_a" -eq 1 ] && [ "$pass_b" -eq 1 ]; then
        pass "AT-3 (D1): lifecycle_advance.sh withheld dispatch for foreign login and unparseable claim"
    else
        fail "AT-3 (D1): lifecycle_advance.sh failed foreign login check ($pass_a) or unparseable claim check ($pass_b)"
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

    get_range "intent"

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
    cat > "$FIXTURES/pulls-$RANGE_AFTER.json" <<EOF
[
  {
    "number": 4242,
    "merged_at": "2026-01-01T00:00:00Z",
    "state": "closed",
    "merge_commit_sha": "$RANGE_AFTER",
    "base": {"ref": "main"},
    "head": {"ref": "athena/999-test", "repo": {"full_name": "evekhm/agentic-sdlc"}},
    "body": "Fixes #999"
  }
]
EOF
    cat > "$FIXTURES/files-4242.json" <<'EOF'
[{"filename": "intent/999-test/intent.md"}]
EOF
    echo "false" > "$FIXTURES/loop-autonomous_merge"
    echo "10" > "$FIXTURES/loop-max_rung_dispatches_per_issue"
    echo "50.00" > "$FIXTURES/loop-max_cost_usd_per_issue"
    echo "ladder vm-local 50.00" > "$FIXTURES/binding-vm-local"

    local out=""
    out="$(cd "$SANDBOX" && bash "$ADVANCER" "$RANGE_BEFORE" "$RANGE_AFTER" 2>&1 || true)"
    local res_line=""
    res_line="$(grep -E '^--> #999' <<<"$out" || true)"
    [ -z "$res_line" ] || echo "    $res_line"

    if grep -qF "released claim of athena on #999" <<<"$out" || grep -qF "DELETE labels 999 in-progress" "$WRITES"; then
        fail "AT-4 (D1): lifecycle_advance.sh released claim despite autonomous_merge: false"
    elif grep -q "autonomous_merge is false" <<<"$out" && grep -q "no dispatch for #999 (D18)" <<<"$out" && [ ! -s "$LAUNCHES" ]; then
        pass "AT-4 (D1): claim release correctly skipped under autonomous_merge: false"
    else
        fail "AT-4 (D1): lifecycle_advance.sh did not print 'autonomous_merge is false' and 'no dispatch for #999 (D18)'"
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

    get_range "implement-pr"

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
    cat > "$FIXTURES/pulls-$RANGE_AFTER.json" <<EOF
[
  {
    "number": 4242,
    "merged_at": "2026-01-01T00:00:00Z",
    "state": "closed",
    "merge_commit_sha": "$RANGE_AFTER",
    "base": {"ref": "main"},
    "head": {"ref": "odyssey/999-test", "repo": {"full_name": "evekhm/agentic-sdlc"}},
    "body": "Fixes #999"
  }
]
EOF
    cat > "$FIXTURES/pulls-$C_IMP_HEAD.json" <<EOF
[
  {
    "number": 4242,
    "merged_at": "2026-01-01T00:00:00Z",
    "state": "closed",
    "merge_commit_sha": "$RANGE_AFTER",
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
    out="$(cd "$SANDBOX" && bash "$ADVANCER" "$RANGE_BEFORE" "$RANGE_AFTER" 2>&1 || true)"
    local res_line=""
    res_line="$(grep -E '^--> #999' <<<"$out" || true)"
    [ -z "$res_line" ] || echo "    $res_line"

    local has_rel=0 has_del=0
    grep -qF "released claim of odyssey on #999 (rung implement merged)" <<<"$out" && has_rel=1
    grep -qF "DELETE labels 999 in-progress" "$WRITES" && has_del=1

    if [ "$has_rel" -eq 1 ] && [ "$has_del" -eq 1 ]; then
        pass "AT-5 (D1): lifecycle_advance.sh released claim of odyssey on terminal review rung"
    else
        fail "AT-5 (D1): lifecycle_advance.sh failed claim release (missing DELETE labels 999 in-progress: del=$has_del, rel=$has_rel)"
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

    get_range "spec"

    cat > "$FIXTURES/issue-999.json" <<'EOF'
{
  "number": 999,
  "state": "OPEN",
  "labels": [{"name": "status:spec"}],
  "comments": []
}
EOF
    cat > "$FIXTURES/pulls-$RANGE_AFTER.json" <<EOF
[
  {
    "number": 4242,
    "merged_at": "2026-01-01T00:00:00Z",
    "state": "closed",
    "merge_commit_sha": "$RANGE_AFTER",
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
    out="$(cd "$SANDBOX" && bash "$ADVANCER" "$RANGE_BEFORE" "$RANGE_AFTER" 2>&1 || true)"
    local res_line=""
    res_line="$(grep -E '^--> #999' <<<"$out" || true)"
    [ -z "$res_line" ] || echo "    $res_line"

    if grep -q "dispatching daedalus via vm-local for #999" <<<"$out" \
       && grep -qE "999 --as daedalus" "$LAUNCHES"; then
        pass "AT-6 (D2, #284): adapter invocation passed 999 --as daedalus without DRY-RUN prefix"
    else
        fail "AT-6 (D2, #284): adapter invocation did not dispatch daedalus or pass 999 --as daedalus"
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
    # Issue 251: status:planning, unclaimed, ledger dispatch row for rung:1 (athena)
    cat > "$FIXTURES/issue-251.json" <<'EOF'
{
  "number": 251,
  "title": "Issue 251",
  "state": "open",
  "labels": [{"name": "status:planning"}],
  "comments": [
    {
      "user": {"login": "evekhm-themis-app[bot]"},
      "body": "<!-- loop-ledger:251 -->\n<!-- loop-ledger-row: dispatch rung:1 head-oid:4f862c6b8cac5ea82f0792e908aec72fda85ad91 pr:none event:local cost:2.00 -->"
    }
  ]
}
EOF
    cat > "$FIXTURES/repos_evekhm_agentic-sdlc_issues_251.json" <<'EOF'
{
  "number": 251,
  "title": "Issue 251",
  "state": "open",
  "labels": [{"name": "status:planning"}]
}
EOF
    cat > "$FIXTURES/comments-251.json" <<'EOF'
[
  {
    "user": {"login": "evekhm-themis-app[bot]"},
    "body": "<!-- loop-ledger:251 -->\n<!-- loop-ledger-row: dispatch rung:1 head-oid:4f862c6b8cac5ea82f0792e908aec72fda85ad91 pr:none event:local cost:2.00 -->"
  }
]
EOF

    # Issue 252: status:planning, in-progress, held by daedalus
    cat > "$FIXTURES/issue-252.json" <<'EOF'
{
  "number": 252,
  "title": "Issue 252",
  "state": "open",
  "labels": [{"name": "status:planning"}, {"name": "in-progress"}],
  "comments": [
    {
      "user": {"login": "evekhm-daedalus-app[bot]"},
      "body": "Claim: daedalus (session-1) stage:plan path:.claude/worktrees/daedalus-252-test"
    },
    {
      "user": {"login": "evekhm-themis-app[bot]"},
      "body": "<!-- loop-ledger:252 -->\n<!-- loop-ledger-row: dispatch rung:1 head-oid:4f862c6b8cac5ea82f0792e908aec72fda85ad91 pr:none event:local cost:2.00 -->"
    }
  ]
}
EOF
    cat > "$FIXTURES/repos_evekhm_agentic-sdlc_issues_252.json" <<'EOF'
{
  "number": 252,
  "title": "Issue 252",
  "state": "open",
  "labels": [{"name": "status:planning"}, {"name": "in-progress"}]
}
EOF
    cat > "$FIXTURES/comments-252.json" <<'EOF'
[
  {
    "user": {"login": "evekhm-daedalus-app[bot]"},
    "body": "Claim: daedalus (session-1) stage:plan path:.claude/worktrees/daedalus-252-test"
  },
  {
    "user": {"login": "evekhm-themis-app[bot]"},
    "body": "<!-- loop-ledger:252 -->\n<!-- loop-ledger-row: dispatch rung:1 head-oid:4f862c6b8cac5ea82f0792e908aec72fda85ad91 pr:none event:local cost:2.00 -->"
  }
]
EOF

    # Issue list fixture for work discovery
    cat > "$FIXTURES/issue-list.json" <<'EOF'
[
  {
    "number": 251,
    "title": "Issue 251",
    "state": "open",
    "labels": [{"name": "status:planning"}],
    "comments": [
      {
        "user": {"login": "evekhm-themis-app[bot]"},
        "body": "<!-- loop-ledger:251 -->\n<!-- loop-ledger-row: dispatch rung:1 head-oid:4f862c6b8cac5ea82f0792e908aec72fda85ad91 pr:none event:local cost:2.00 -->"
      }
    ]
  },
  {
    "number": 252,
    "title": "Issue 252",
    "state": "open",
    "labels": [{"name": "status:planning"}, {"name": "in-progress"}],
    "comments": [
      {
        "user": {"login": "evekhm-daedalus-app[bot]"},
        "body": "Claim: daedalus (session-1) stage:plan path:.claude/worktrees/daedalus-252-test"
      },
      {
        "user": {"login": "evekhm-themis-app[bot]"},
        "body": "<!-- loop-ledger:252 -->\n<!-- loop-ledger-row: dispatch rung:1 head-oid:4f862c6b8cac5ea82f0792e908aec72fda85ad91 pr:none event:local cost:2.00 -->"
      }
    ]
  }
]
EOF
    echo '[]' > "$FIXTURES/pr-list.json"

    cp "$poll_sh" "$SANDBOX/scripts/placement/vm-local/poll.sh"
    chmod +x "$SANDBOX/scripts/placement/vm-local/poll.sh"

    local out="" rc=0
    out="$(cd "$SANDBOX" && RUN_SH="$WORK/bin/run.sh" bash "scripts/placement/vm-local/poll.sh" --once 2>&1)" || rc=$?

    local has_mint=0 has_claim=0 has_launch=0 no_claimed_dispatch=0
    grep -qE "mint_app_token\.py.*athena" "$MINTS" && has_mint=1
    grep -qE 'claim\.sh CLAIM_ACTOR=athena CLAIM_SESSION=poll-[0-9]+ 251( |$)' "$CLAIMS" && has_claim=1
    grep -qE "run\.sh 251 --as athena" "$LAUNCHES" && has_launch=1
    if ! grep -q "252" "$LAUNCHES"; then
        no_claimed_dispatch=1
    fi

    if [ "$rc" -eq 0 ] && [ "$has_mint" -eq 1 ] && [ "$has_claim" -eq 1 ] && [ "$has_launch" -eq 1 ] && [ "$no_claimed_dispatch" -eq 1 ]; then
        pass "AT-8 (D2): poll.sh --once claimed and dispatched unconsumed row with token mint and claim verification"
    else
        fail "AT-8 (D2): poll.sh --once failed observables (rc=$rc mint=$has_mint claim=$has_claim launch=$has_launch skipped_claimed=$no_claimed_dispatch)"
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
  "state": "open",
  "title": "PR 108",
  "labels": [{"name": "status:implementing"}]
}
EOF

    # 1. Antigravity fixture
    cat > "$fixture_dep" <<'EOF'
personas:
  odyssey:
    harness: antigravity
EOF
    : > "$LAUNCHES"
    LAUNCH_OK=1 HEADLESS=1 DRY_RUN=0 DEPLOYMENTS="$fixture_dep" bash "$work_sh" 108 --as odyssey >/dev/null 2>&1 || true

    local agy_1=0
    grep -q "agy" "$LAUNCHES" 2>/dev/null && agy_1=1

    # 2. Update fixture to claude-code
    cat > "$fixture_dep" <<'EOF'
personas:
  odyssey:
    harness: claude-code
EOF
    : > "$LAUNCHES"
    LAUNCH_OK=1 HEADLESS=1 DRY_RUN=0 DEPLOYMENTS="$fixture_dep" bash "$work_sh" 108 --as odyssey >/dev/null 2>&1 || true

    local claude_pass=0
    grep -qE "claude -p .* --agent odyssey --output-format json" "$LAUNCHES" 2>/dev/null && claude_pass=1

    # 3. Restore antigravity fixture
    cat > "$fixture_dep" <<'EOF'
personas:
  odyssey:
    harness: antigravity
EOF
    : > "$LAUNCHES"
    LAUNCH_OK=1 HEADLESS=1 DRY_RUN=0 DEPLOYMENTS="$fixture_dep" bash "$work_sh" 108 --as odyssey >/dev/null 2>&1 || true

    local agy_2=0
    grep -q "agy" "$LAUNCHES" 2>/dev/null && agy_2=1

    if [ "$agy_1" -eq 1 ] && [ "$claude_pass" -eq 1 ] && [ "$agy_2" -eq 1 ]; then
        pass "AT-12 (D2): re-pin property verified (antigravity -> claude-code -> antigravity)"
    else
        fail "AT-12 (D2): re-pin check failed (agy_1=$agy_1, claude=$claude_pass, agy_2=$agy_2)"
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
    if [ "$rc" -eq 0 ] && ! grep -q "does not own stage review" <<<"$out" \
       && grep -q -- "--> odyssey" <<<"$out" && grep -qE "branch:.*odyssey/107-fix" <<<"$out"; then
        pass "AT-13 (D2, D8): work.sh proceeded under fix-round resume protocol"
    else
        fail "AT-13 (D2, D8): work.sh did not proceed under resume protocol (rc=$rc): $out"
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
    cat > "$FIXTURES/issue-251.json" <<'EOF'
{
  "number": 251,
  "state": "open",
  "labels": [{"name": "status:planning"}],
  "comments": [
    {
      "user": {"login": "evekhm-themis-app[bot]"},
      "body": "<!-- loop-ledger:251 -->\n<!-- loop-ledger-row: dispatch rung:1 head-oid:4f862c6b8cac5ea82f0792e908aec72fda85ad91 pr:none event:local cost:2.00 -->"
    }
  ]
}
EOF
    cat > "$FIXTURES/comments-251.json" <<'EOF'
[
  {
    "user": {"login": "evekhm-themis-app[bot]"},
    "body": "<!-- loop-ledger:251 -->\n<!-- loop-ledger-row: dispatch rung:1 head-oid:4f862c6b8cac5ea82f0792e908aec72fda85ad91 pr:none event:local cost:2.00 -->"
  }
]
EOF

    cat > "$FIXTURES/issue-252.json" <<'EOF'
{
  "number": 252,
  "title": "Issue 252",
  "state": "open",
  "labels": [{"name": "status:build"}],
  "comments": [
    {
      "user": {"login": "evekhm-themis-app[bot]"},
      "body": "<!-- loop-ledger:252 -->\n<!-- loop-ledger-row: dispatch rung:3 head-oid:4f862c6b8cac5ea82f0792e908aec72fda85ad91 pr:none event:local cost:2.00 -->"
    }
  ]
}
EOF
    cat > "$FIXTURES/comments-252.json" <<'EOF'
[
  {
    "user": {"login": "evekhm-themis-app[bot]"},
    "body": "<!-- loop-ledger:252 -->\n<!-- loop-ledger-row: dispatch rung:3 head-oid:4f862c6b8cac5ea82f0792e908aec72fda85ad91 pr:none event:local cost:2.00 -->"
  }
]
EOF

    cat > "$FIXTURES/issue-list.json" <<'EOF'
[
  {
    "number": 251,
    "title": "Issue 251",
    "state": "open",
    "labels": [{"name": "status:planning"}],
    "comments": [
      {
        "user": {"login": "evekhm-themis-app[bot]"},
        "body": "<!-- loop-ledger:251 -->\n<!-- loop-ledger-row: dispatch rung:1 head-oid:4f862c6b8cac5ea82f0792e908aec72fda85ad91 pr:none event:local cost:2.00 -->"
      }
    ]
  },
  {
    "number": 252,
    "title": "Issue 252",
    "state": "open",
    "labels": [{"name": "status:build"}],
    "comments": [
      {
        "user": {"login": "evekhm-themis-app[bot]"},
        "body": "<!-- loop-ledger:252 -->\n<!-- loop-ledger-row: dispatch rung:3 head-oid:4f862c6b8cac5ea82f0792e908aec72fda85ad91 pr:none event:local cost:2.00 -->"
      }
    ]
  }
]
EOF
    echo '[]' > "$FIXTURES/pr-list.json"

    cp "$poll_sh" "$SANDBOX/scripts/placement/vm-local/poll.sh"
    chmod +x "$SANDBOX/scripts/placement/vm-local/poll.sh"

    local out="" rc=0
    out="$(cd "$SANDBOX" && FAIL_MINT_PERSONA="athena" RUN_SH="$WORK/bin/run.sh" bash "scripts/placement/vm-local/poll.sh" --once 2>&1)" || rc=$?
    if [ "$rc" -eq 0 ] && grep -qF "missing key for athena, skipping its rows" <<<"$out" \
       && ! grep -q "251" "$LAUNCHES" \
       && grep -qE "run\.sh 252 --as daedalus" "$LAUNCHES"; then
        pass "AT-14 (D4): poll.sh logged missing key notice, skipped persona rows, and continued remaining rows"
    else
        fail "AT-14 (D4): poll.sh failed missing key handling (rc=$rc)"
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
    cat > "$FIXTURES/issue-300.json" <<'EOF'
{
  "number": 300,
  "title": "Issue 300",
  "state": "open",
  "labels": [{"name": "intent:new"}],
  "comments": []
}
EOF
    cat > "$FIXTURES/repos_evekhm_agentic-sdlc_issues_300.json" <<'EOF'
{
  "number": 300,
  "title": "Issue 300",
  "state": "open",
  "labels": [{"name": "intent:new"}]
}
EOF
    cat > "$FIXTURES/comments-300.json" <<'EOF'
[]
EOF

    # Issue list fixture for work discovery contains only issue 300 (Decision D)
    cat > "$FIXTURES/issue-list.json" <<'EOF'
[
  {
    "number": 300,
    "title": "Issue 300",
    "state": "open",
    "labels": [{"name": "intent:new"}],
    "comments": []
  }
]
EOF
    echo '[]' > "$FIXTURES/pr-list.json"

    cp "$poll_sh" "$SANDBOX/scripts/placement/vm-local/poll.sh"
    chmod +x "$SANDBOX/scripts/placement/vm-local/poll.sh"

    local out="" rc=0
    out="$(cd "$SANDBOX" && RUN_SH="$WORK/bin/run.sh" bash "scripts/placement/vm-local/poll.sh" --once 2>&1)" || rc=$?

    local has_claim=0 single_launch=0 no_ledger=0 clean_worktree=0
    local launch_in_discovery=0 has_list_query=0
    local launched_num=""
    if [ "$(wc -l < "$LAUNCHES")" -eq 1 ]; then
        launched_num="$(awk '{print $2}' "$LAUNCHES" 2>/dev/null || true)"
        if [ -n "$launched_num" ] && grep -qE "^run\.sh $launched_num --as athena$" "$LAUNCHES"; then
            single_launch=1
        fi
    fi
    if [ -n "$launched_num" ] && "$REAL_JQ" -e --argjson n "$launched_num" '.[] | select(.number == $n)' "$FIXTURES/issue-list.json" >/dev/null 2>&1; then
        launch_in_discovery=1
    fi
    if [ -n "$launched_num" ] && grep -qE "claim\.sh CLAIM_ACTOR=athena CLAIM_SESSION=poll-[0-9]+ $launched_num( |$)" "$CLAIMS"; then
        has_claim=1
    fi
    if [ -f "$WORK/.first_claim_had_list_query" ] && grep -qE 'gh (issue list.*(--label|-l)|api.*repos/[^/]+/[^/]+/issues\?.*labels=)' "$INVOKES"; then
        has_list_query=1
    fi
    if ! grep -q "loop-ledger" "$WRITES"; then
        no_ledger=1
    fi
    local sandbox_status=""
    sandbox_status="$("$REAL_GIT" -C "$SANDBOX" status --porcelain 2>/dev/null || true)"
    if [ -z "$sandbox_status" ] && ! ls -d "$REPO/.claude/worktrees/"*300* >/dev/null 2>&1; then
        clean_worktree=1
    fi

    if [ "$rc" -eq 0 ] && [ "$has_claim" -eq 1 ] && [ "$single_launch" -eq 1 ] && [ "$launch_in_discovery" -eq 1 ] && [ "$has_list_query" -eq 1 ] && [ "$no_ledger" -eq 1 ] && [ "$clean_worktree" -eq 1 ]; then
        pass "AT-15 (D5): first hop claimed and dispatched discovered open intent:new issue with single launch, zero ledger writes, and clean worktree"
    else
        fail "AT-15 (D5): poll.sh did not claim/dispatch discovered open intent:new issue or wrote ledger row (rc=$rc claim=$has_claim launch=$single_launch in_disc=$launch_in_discovery list_query=$has_list_query no_ledger=$no_ledger clean=$clean_worktree)"
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

    if grep -qF "## Deployment status" "$spec_doc" && [ "$steps" -eq 7 ] && [ "$manual_count" -eq 0 ] && [ "$ladder_count" -eq 1 ]; then
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
    cat > "$FIXTURES/issue-4242.json" <<'EOF'
{
  "number": 4242,
  "state": "open",
  "title": "PR 4242",
  "labels": [{"name": "status:in-review"}],
  "pull_request": {"url": "https://api.github.com/repos/evekhm/agentic-sdlc/pulls/4242"},
  "comments": [
    {
      "user": {"login": "evekhm-argus-app[bot]"},
      "body": "review findings: blocking"
    }
  ]
}
EOF
    cat > "$FIXTURES/repos_evekhm_agentic-sdlc_pulls_4242.json" <<'EOF'
{
  "head": {
    "ref": "odyssey/4241-fix",
    "repo": {"full_name": "evekhm/agentic-sdlc"}
  }
}
EOF
    cat > "$FIXTURES/comments-4242.json" <<'EOF'
[
  {
    "user": {"login": "evekhm-argus-app[bot]"},
    "body": "review findings: blocking"
  }
]
EOF

    cat > "$FIXTURES/pr-list.json" <<'EOF'
[
  {
    "number": 4242,
    "title": "PR 4242",
    "state": "open",
    "labels": [{"name": "status:in-review"}],
    "headRefName": "odyssey/4241-fix"
  }
]
EOF
    echo '[]' > "$FIXTURES/issue-list.json"

    cp "$poll_sh" "$SANDBOX/scripts/placement/vm-local/poll.sh"
    chmod +x "$SANDBOX/scripts/placement/vm-local/poll.sh"

    local lock_file="${TMPDIR:-/tmp}/poll-pr-4242.lock"
    rm -f "$lock_file"

    local rc1=0
    (cd "$SANDBOX" && RUN_SH="$WORK/bin/run.sh" bash "scripts/placement/vm-local/poll.sh" --once >/dev/null 2>&1) || rc1=$?

    local has_launch1=0 no_claim=0
    grep -qE "^run\.sh 4242 --as odyssey$" "$LAUNCHES" && has_launch1=1
    if [ ! -s "$CLAIMS" ]; then
        no_claim=1
    fi

    local launches_first=""
    launches_first="$(cat "$LAUNCHES")"

    # Simulate active lock
    touch "$lock_file"
    local rc2=0
    (cd "$SANDBOX" && RUN_SH="$WORK/bin/run.sh" bash "scripts/placement/vm-local/poll.sh" --once >/dev/null 2>&1) || rc2=$?

    local lock_prevented=0
    if [ "$(cat "$LAUNCHES")" = "$launches_first" ]; then
        lock_prevented=1
    fi
    rm -f "$lock_file"

    if [ "$rc1" -eq 0 ] && [ "$rc2" -eq 0 ] && [ "$has_launch1" -eq 1 ] && [ "$no_claim" -eq 1 ] && [ "$lock_prevented" -eq 1 ]; then
        pass "AT-20 (D2): fix-round claim bypass and per-PR lock verified"
    else
        fail "AT-20 (D2): poll.sh failed fix-round claim bypass or locking (rc1=$rc1 rc2=$rc2 launch=$has_launch1 no_claim=$no_claim lock_prevented=$lock_prevented)"
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
