#!/usr/bin/env bash
# Contract test suite for session close-out (/wrap) (#85).
# Spec: intent/85-session-close-out/spec.md (Approved, D1-D15, AT-1-AT-19)
#
# Cites Decisions D1-D15 and Acceptance Tests AT-1..AT-19.
# Every assertion cites its Decision ID and Acceptance Test ID.
# Under the baseline tree prior to implementation, assertions test unbuilt
# functionality and fail cleanly (red).
#
# The suite is hermetic: when testing an implementation, it operates in a
# self-contained sandbox with PATH shims over git, gh, and worktrees.sh,
# avoiding any mutation of the host checkout or reliance on backdoor env vars.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WRAP_SH="${WRAP_SH:-$REPO/scripts/ops/wrap.sh}"
CLAUDE_DOOR="$REPO/.claude/commands/wrap.md"
SPEC_MD="$REPO/docs/SPEC.md"
AGENTS_MD="$REPO/AGENTS.md"
CI_GATES="$REPO/.github/workflows/ci-gates.yml"

FAILURES=0

banner() { printf "\n=== %s ===\n" "$*"; }

pass() {
    echo "PASS: $*"
}

fail() {
    echo "FAIL: $*" >&2
    FAILURES=$((FAILURES + 1))
}

# --- Sandbox and Stub Infrastructure -----------------------------------------
SANDBOX=""
cleanup() {
    if [ -n "$SANDBOX" ] && [ -d "$SANDBOX" ]; then
        rm -rf "$SANDBOX"
    fi
}
trap cleanup EXIT

# Resolve real binaries dynamically from host PATH (outside any test shim)
REAL_GIT="$(command -v git || echo /usr/bin/git)"
REAL_GH="$(command -v gh || echo /usr/bin/gh)"
REAL_JQ="$(command -v jq || echo /usr/bin/jq)"
REAL_GAWK="$(command -v gawk || command -v awk || echo /usr/bin/gawk)"

setup_sandbox() {
    SANDBOX="$(mktemp -d)"
    SANDBOX_BIN="$SANDBOX/bin"
    FIXTURES="$SANDBOX/fixtures"
    CALLS_LOG="$SANDBOX/calls.log"
    WRITES_LOG="$SANDBOX/writes.log"
    mkdir -p "$SANDBOX_BIN" "$FIXTURES"
    : > "$CALLS_LOG"
    : > "$WRITES_LOG"

    # Export stub configuration so PATH shim processes inherit them (R1-2, R1-3)
    export SANDBOX
    export SANDBOX_BIN
    export FIXTURES
    export CALLS_LOG
    export WRITES_LOG
    export GITHUB_REPO="test/repo"
    export GITHUB_REPOSITORY="test/repo"

    # Git upstream bare repo and primary working checkout
    ORIGIN_REPO="$SANDBOX/origin.git"
    PRIMARY_REPO="$SANDBOX/primary"
    git init --bare -b main "$ORIGIN_REPO" >/dev/null 2>&1
    git clone "$ORIGIN_REPO" "$PRIMARY_REPO" >/dev/null 2>&1
    git -C "$PRIMARY_REPO" config user.name "Tester"
    git -C "$PRIMARY_REPO" config user.email "tester@example.com"
    git -C "$PRIMARY_REPO" config remote.origin.gh-repo "test/repo"
    (
        cd "$PRIMARY_REPO"
        mkdir -p ops/handoffs runs
        echo "# Test Repo" > README.md
        git add README.md
        git commit -m "initial commit" -q
        git push -q origin main
    )

    # PATH stub: gh
    cat > "$SANDBOX_BIN/gh" <<'STUB_GH'
#!/usr/bin/env bash
# Prepend command name so logged calls match anchors ^gh ... (R1-2)
printf 'gh %s
' "$*" >> "$CALLS_LOG"
if [[ "$*" =~ (POST|PATCH|DELETE) ]] || [[ "$*" =~ "pr create" ]] || [[ "$*" =~ "issue create" ]] || [[ "$*" =~ "label remove" ]] || [[ "$*" =~ "issue edit" ]]; then
    printf 'gh %s
' "$*" >> "$WRITES_LOG"
fi

if [ "${1:-}" = "repo" ] && [ "${2:-}" = "view" ]; then
    echo "test/repo"
    exit 0
fi

if [ "${1:-}" = "api" ]; then
    method="GET"
    endpoint=""
    shift
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --method|-X) method="$2"; shift 2 ;;
            -f|-F|--raw-field) shift 2 ;;
            --paginate) shift ;;
            -q|--jq) shift 2 ;;
            -*) shift ;;
            *) endpoint="$1"; shift ;;
        esac
    done
    clean_ep="${endpoint%%\?*}"
    clean_ep="${clean_ep#/}"
    clean_slug="${clean_ep//\//_}"
    clean_slug="${clean_slug//:/_}"

    if [ "$method" = "DELETE" ]; then
        exit 0
    fi

    # Match exact slugified endpoint
    if [ -f "$FIXTURES/${clean_slug}.json" ]; then
        cat "$FIXTURES/${clean_slug}.json"
        exit 0
    fi

    # Match short endpoint slug (stripping repos/<owner>/<repo>/ or repos/:owner/:repo/)
    short_slug="$(echo "$clean_slug" | sed -E 's/^repos_[^_]+_[^_]+_//')"
    if [ -f "$FIXTURES/${short_slug}.json" ]; then
        cat "$FIXTURES/${short_slug}.json"
        exit 0
    fi

    # Direct keyword matches for common GitHub API endpoints (R1-3)
    if [[ "$clean_ep" =~ issues/([0-9]+)/labels ]]; then
        num="${BASH_REMATCH[1]}"
        if [ -f "$FIXTURES/issues_${num}_labels.json" ]; then
            cat "$FIXTURES/issues_${num}_labels.json"
            exit 0
        fi
    fi
    if [[ "$clean_ep" =~ issues/([0-9]+)/comments ]]; then
        num="${BASH_REMATCH[1]}"
        if [ -f "$FIXTURES/issues_${num}_comments.json" ]; then
            cat "$FIXTURES/issues_${num}_comments.json"
            exit 0
        fi
    fi
    if [[ "$clean_ep" =~ issues/([0-9]+)$ ]]; then
        num="${BASH_REMATCH[1]}"
        if [ -f "$FIXTURES/issue_${num}.json" ]; then
            cat "$FIXTURES/issue_${num}.json"
            exit 0
        fi
    fi
    if [[ "$clean_ep" =~ (pulls|pull_requests) ]]; then
        if [ -f "$FIXTURES/pr_list.json" ]; then
            cat "$FIXTURES/pr_list.json"
            exit 0
        fi
    fi
    if [[ "$clean_ep" =~ issues$ ]]; then
        if [ -f "$FIXTURES/issue_list.json" ]; then
            cat "$FIXTURES/issue_list.json"
            exit 0
        fi
    fi

    echo "{}"
    exit 0
fi

if [ "${1:-}" = "pr" ] && [ "${2:-}" = "list" ]; then
    if [ -f "$FIXTURES/pr_list.json" ]; then
        cat "$FIXTURES/pr_list.json"
    else
        echo "[]"
    fi
    exit 0
fi

if [ "${1:-}" = "issue" ] && [ "${2:-}" = "list" ]; then
    if [ -f "$FIXTURES/issue_list.json" ]; then
        cat "$FIXTURES/issue_list.json"
    else
        echo "[]"
    fi
    exit 0
fi

if [ "${1:-}" = "issue" ] && [ "${2:-}" = "view" ]; then
    issue_num="${3:-}"
    if [ -f "$FIXTURES/issue_${issue_num}.json" ]; then
        cat "$FIXTURES/issue_${issue_num}.json"
    else
        echo "{}"
    fi
    exit 0
fi

exit 0
STUB_GH
    chmod +x "$SANDBOX_BIN/gh"

    # PATH stub: worktrees.sh
    cat > "$SANDBOX_BIN/worktrees.sh" <<'STUB_WT'
#!/usr/bin/env bash
printf 'worktrees.sh %s
' "$*" >> "$CALLS_LOG"
if [ -f "$FIXTURES/worktrees.txt" ]; then
    cat "$FIXTURES/worktrees.txt"
else
    echo "primary  main  -  0  0 M  safe"
fi
exit 0
STUB_WT
    chmod +x "$SANDBOX_BIN/worktrees.sh"

    # PATH stub: git wrapper (logs commands, delegates to real git) (R1-2, R1-8)
    cat > "$SANDBOX_BIN/git" <<STUB_GIT
#!/usr/bin/env bash
printf 'git %s
' "\$*" >> "\$CALLS_LOG"
exec "$REAL_GIT" "\$@"
STUB_GIT
    chmod +x "$SANDBOX_BIN/git"
}

# Fixture helper for non-empty sessions that produced state (R1-1)
# Establishes a valid run artifact with disposition so Check 10 passes
# and D12(c) short-circuit is not triggered during close-out tests.
setup_session_with_state() {
    setup_sandbox
    (
        cd "$PRIMARY_REPO"
        mkdir -p runs ops/handoffs
        cat > runs/session-artifact.md <<'EOF'
# Session Artifact
Artifact produced during test-session.
<!-- disposition: kept for audit -->
EOF
        git add runs/session-artifact.md
        git commit -m "record test session artifact" -q
        git push -q origin main
    )
}

# --- AT-1 (D7, Exit 0): Clean session close-out -------------------------------
banner "AT-1 (D7, Exit 0): Clean session close-out"
if [ ! -x "$WRAP_SH" ]; then
    fail "AT-1 (D7): $WRAP_SH does not exist or is not executable"
else
    # Non-empty session that produced state must close out cleanly (R1-1)
    setup_session_with_state
    (
        cd "$PRIMARY_REPO"
        export PATH="$SANDBOX_BIN:$PATH"
        export WRAP_LEARNINGS="none"
        rc=0
        out="$("$WRAP_SH" test-session 2>&1)" || rc=$?
        handoff_count="$(find "$PRIMARY_REPO/ops/handoffs" -maxdepth 1 -name "handoff-*.txt" 2>/dev/null | wc -l || :)"
        if [ "$rc" -eq 0 ] && grep -qE '^(status: )?closed$' <<<"$out" && ! grep -q "not closed" <<<"$out" && grep -q "handoff:" <<<"$out" && [ "$handoff_count" -ge 1 ]; then
            pass "AT-1 (D7): wrap.sh prints closed, outputs handoff block, and exits 0"
        else
            fail "AT-1 (D7): wrap.sh failed clean close-out check (rc=$rc, handoffs=$handoff_count, out=$out)"
        fi
    )
fi

# --- AT-2 (D1, Check 1): Active child processes -------------------------------
banner "AT-2 (D1, Check 1): Active child processes and subagents"
if [ ! -x "$WRAP_SH" ]; then
    fail "AT-2 (D1): $WRAP_SH does not exist or is not executable"
else
    setup_sandbox
    (
        cd "$PRIMARY_REPO"
        export PATH="$SANDBOX_BIN:$PATH"
        # Spawn an active child process belonging to this subshell process group ($PPID tree) (R1-6)
        sleep 5 &
        child_pid=$!
        rc=0
        out="$("$WRAP_SH" test-session 2>&1)" || rc=$?
        kill "$child_pid" 2>/dev/null || :
        wait "$child_pid" 2>/dev/null || :
        if [ "$rc" -eq 2 ] && grep -q "refused: child processes still running" <<<"$out"; then
            pass "AT-2 (D1): wrap.sh reports fail on Check 1 and exits 2 when child processes are active"
        else
            fail "AT-2 (D1): wrap.sh did not refuse with exit 2 when child processes were active (rc=$rc, out=$out)"
        fi
    )
fi

# --- AT-3 (D1, Check 3): Unpushed worktree branch commits ---------------------
banner "AT-3 (D1, Check 3): Unpushed worktree branch commits"
if [ ! -x "$WRAP_SH" ]; then
    fail "AT-3 (D1): $WRAP_SH does not exist or is not executable"
else
    setup_sandbox
    (
        cd "$PRIMARY_REPO"
        export PATH="$SANDBOX_BIN:$PATH"
        # Create a branch with an unpushed commit belonging to this session
        git checkout -b test-branch -q
        echo "unpushed change" >> README.md
        git commit -am "unpushed commit" -q
        rc=0
        out="$("$WRAP_SH" test-session 2>&1)" || rc=$?
        if [ "$rc" -eq 2 ] && grep -qE "refused: unpushed commits on test-branch" <<<"$out"; then
            pass "AT-3 (D1): wrap.sh reports fail on Check 3 and exits 2 on unpushed commits"
        else
            fail "AT-3 (D1): wrap.sh did not refuse with exit 2 on unpushed branch commits (rc=$rc, out=$out)"
        fi
    )
fi

# --- AT-4 (D1, Check 4): Primary checkout dirty or behind origin/main ---------
banner "AT-4 (D1, Check 4): Primary checkout dirty or behind origin/main"
if [ ! -x "$WRAP_SH" ]; then
    fail "AT-4 (D1): $WRAP_SH does not exist or is not executable"
else
    setup_sandbox
    (
        cd "$PRIMARY_REPO"
        export PATH="$SANDBOX_BIN:$PATH"
        # Make working directory dirty with an uncommitted edit
        echo "dirty modification" >> README.md
        rc=0
        out="$("$WRAP_SH" test-session 2>&1)" || rc=$?
        if [ "$rc" -eq 2 ] && grep -q "refused: primary checkout dirty or behind origin/main" <<<"$out"; then
            pass "AT-4 (D1): wrap.sh reports fail on Check 4 and exits 2 when primary is dirty"
        else
            fail "AT-4 (D1): wrap.sh did not refuse with exit 2 when primary is dirty (rc=$rc, out=$out)"
        fi
    )
fi

# --- AT-5 (D1, Check 5): PR CI check status (code defect vs ambient outage) ---
banner "AT-5 (D1, Check 5): PR CI check status (code defect vs ambient outage)"
if [ ! -x "$WRAP_SH" ]; then
    fail "AT-5 (D1): $WRAP_SH does not exist or is not executable"
else
    setup_sandbox
    (
        cd "$PRIMARY_REPO"
        export PATH="$SANDBOX_BIN:$PATH"
        export WRAP_LEARNINGS="none"
        # Case A: Code defect failure on session PR #42
        cat > "$FIXTURES/pr_list.json" <<'JSON'
[{"number":42,"headRefName":"odyssey/test","statusCheckRollup":[{"conclusion":"FAILURE","name":"test-code","detailsUrl":"job/1"}]}]
JSON
        rc=0
        out="$("$WRAP_SH" test-session 2>&1)" || rc=$?
        if [ "$rc" -eq 2 ] && grep -qE "refused: PR #42 checks failing" <<<"$out"; then
            pass "AT-5 (D1): wrap.sh reports fail and exits 2 on code-defect PR check failure"
        else
            fail "AT-5 (D1): wrap.sh did not refuse with exit 2 on code-defect PR check failure (rc=$rc, out=$out)"
        fi

        # Case B: Ambient runner failure (#167-class infrastructure defect)
        cat > "$FIXTURES/pr_list.json" <<'JSON'
[{"number":42,"headRefName":"odyssey/test","statusCheckRollup":[{"conclusion":"STARTUP_FAILURE","name":"infrastructure-runner","detailsUrl":"job/2"}]}]
JSON
        rc=0
        out="$("$WRAP_SH" test-session 2>&1)" || rc=$?
        if [ "$rc" -eq 0 ] && grep -qi "warn" <<<"$out"; then
            pass "AT-5 (D1): wrap.sh reports warn and exits 0 on ambient environment defect"
        else
            fail "AT-5 (D1): wrap.sh did not warn and exit 0 on ambient environment defect (rc=$rc, out=$out)"
        fi
    )
fi

# --- AT-6 (D4, Check 8 auto-repair): in-progress label removal -----------------
banner "AT-6 (D4, Check 8 auto-repair): in-progress label removal"
if [ ! -x "$WRAP_SH" ]; then
    fail "AT-6 (D4): $WRAP_SH does not exist or is not executable"
else
    setup_sandbox
    (
        cd "$PRIMARY_REPO"
        export PATH="$SANDBOX_BIN:$PATH"
        export WRAP_LEARNINGS="none"
        # Issue #88 claimed by test-session has in-progress label AND a valid handoff comment (R1-3)
        labels_json='[{"name":"in-progress"},{"name":"status:implementing"}]'
        comments_json='[
  {"body":"Claim: odyssey (test-session), stage: implementing."},
  {"body":"Done: completed work
Decided: D1
Next: review
Blocked: none"}
]'
        echo "$labels_json" > "$FIXTURES/repos_test_repo_issues_88_labels.json"
        echo "$labels_json" > "$FIXTURES/issues_88_labels.json"
        echo "$comments_json" > "$FIXTURES/repos_test_repo_issues_88_comments.json"
        echo "$comments_json" > "$FIXTURES/issues_88_comments.json"
        cat > "$FIXTURES/issue_list.json" <<'JSON'
[{"number":88,"title":"issue 88","labels":[{"name":"in-progress"},{"name":"status:implementing"}]}]
JSON
        : > "$WRITES_LOG"
        rc=0
        out="$("$WRAP_SH" test-session 2>&1)" || rc=$?
        if [ "$rc" -eq 0 ] && grep -qE "fixed: removed in-progress from #88" <<<"$out" && grep -qE "(DELETE.*labels/in-progress|label remove in-progress)" "$WRITES_LOG"; then
            pass "AT-6 (D4): wrap.sh removes in-progress, reports fixed, and exits 0"
        else
            fail "AT-6 (D4): wrap.sh did not auto-repair stale in-progress label (rc=$rc, out=$out)"
        fi
    )
fi

# --- AT-7 (D4, DRY_RUN contract): dry-run would-fix refusal -------------------
banner "AT-7 (D4, DRY_RUN contract): dry-run would-fix refusal"
if [ ! -x "$WRAP_SH" ]; then
    fail "AT-7 (D4): $WRAP_SH does not exist or is not executable"
else
    setup_sandbox
    (
        cd "$PRIMARY_REPO"
        export PATH="$SANDBOX_BIN:$PATH"
        export WRAP_LEARNINGS="none"
        labels_json='[{"name":"in-progress"},{"name":"status:implementing"}]'
        comments_json='[
  {"body":"Claim: odyssey (test-session), stage: implementing."},
  {"body":"Done: completed work
Decided: D1
Next: review
Blocked: none"}
]'
        echo "$labels_json" > "$FIXTURES/repos_test_repo_issues_88_labels.json"
        echo "$labels_json" > "$FIXTURES/issues_88_labels.json"
        echo "$comments_json" > "$FIXTURES/repos_test_repo_issues_88_comments.json"
        echo "$comments_json" > "$FIXTURES/issues_88_comments.json"
        cat > "$FIXTURES/issue_list.json" <<'JSON'
[{"number":88,"title":"issue 88","labels":[{"name":"in-progress"},{"name":"status:implementing"}]}]
JSON
        : > "$WRITES_LOG"
        : > "$CALLS_LOG"
        rc=0
        out="$(DRY_RUN=1 "$WRAP_SH" test-session 2>&1)" || rc=$?
        # Non-empty CALLS_LOG proves gh was queried; empty WRITES_LOG proves zero mutation calls (R1-3)
        if [ "$rc" -eq 2 ] && grep -qE "would: remove in-progress from #88" <<<"$out" && grep -qE "fail: #88 carries in-progress \(dry-run\)" <<<"$out" && [ ! -s "$WRITES_LOG" ] && [ -s "$CALLS_LOG" ]; then
            pass "AT-7 (D4): wrap.sh prints would-fix, reports fail, exits 2, and makes zero write calls under DRY_RUN=1"
        else
            fail "AT-7 (D4): wrap.sh failed DRY_RUN contract on would-fix scenario (rc=$rc, out=$out)"
        fi
    )
fi

# --- AT-8 (D1, Check 8 refusal): missing handoff comment ----------------------
banner "AT-8 (D1, Check 8 refusal): missing handoff comment"
if [ ! -x "$WRAP_SH" ]; then
    fail "AT-8 (D1): $WRAP_SH does not exist or is not executable"
else
    setup_sandbox
    (
        cd "$PRIMARY_REPO"
        export PATH="$SANDBOX_BIN:$PATH"
        # Issue #88 claimed by test-session has in-progress but NO handoff comment
        labels_json='[{"name":"in-progress"}]'
        comments_json='[{"body":"Claim: odyssey (test-session), stage: implementing."}]'
        echo "$labels_json" > "$FIXTURES/repos_test_repo_issues_88_labels.json"
        echo "$labels_json" > "$FIXTURES/issues_88_labels.json"
        echo "$comments_json" > "$FIXTURES/repos_test_repo_issues_88_comments.json"
        echo "$comments_json" > "$FIXTURES/issues_88_comments.json"
        cat > "$FIXTURES/issue_list.json" <<'JSON'
[{"number":88,"title":"issue 88","labels":[{"name":"in-progress"}]}]
JSON
        : > "$WRITES_LOG"
        : > "$CALLS_LOG"
        rc=0
        out="$("$WRAP_SH" test-session 2>&1)" || rc=$?
        if [ "$rc" -eq 2 ] && grep -qE "fail: missing handoff comment on #88" <<<"$out" && [ ! -s "$WRITES_LOG" ] && [ -s "$CALLS_LOG" ]; then
            pass "AT-8 (D1): wrap.sh reports fail on missing handoff comment, makes no modifications, and exits 2"
        else
            fail "AT-8 (D1): wrap.sh did not refuse with exit 2 when handoff comment was missing (rc=$rc, out=$out)"
        fi
    )
fi

# --- AT-9 (D1, Check 10): run artifact missing disposition --------------------
banner "AT-9 (D1, Check 10): run artifact missing disposition"
if [ ! -x "$WRAP_SH" ]; then
    fail "AT-9 (D1): $WRAP_SH does not exist or is not executable"
else
    setup_sandbox
    (
        cd "$PRIMARY_REPO"
        export PATH="$SANDBOX_BIN:$PATH"
        # Create an undispositioned artifact in runs/
        mkdir -p runs/test-session
        echo "some artifact content without disposition footnote" > runs/test-session/out.txt
        rc=0
        out="$("$WRAP_SH" test-session 2>&1)" || rc=$?
        if [ "$rc" -eq 2 ] && grep -qE "fail: artifact .*out\.txt missing disposition" <<<"$out"; then
            pass "AT-9 (D1): wrap.sh reports fail on missing artifact disposition and exits 2"
        else
            fail "AT-9 (D1): wrap.sh did not refuse with exit 2 on missing artifact disposition (rc=$rc, out=$out)"
        fi
    )
fi

# --- AT-10 (D1, Check 15): peer worktree anomaly warning ----------------------
banner "AT-10 (D1, Check 15): peer worktree anomaly warning"
if [ ! -x "$WRAP_SH" ]; then
    fail "AT-10 (D1): $WRAP_SH does not exist or is not executable"
else
    # Peer worktree anomaly evaluated on a session with state (R1-1)
    setup_session_with_state
    (
        cd "$PRIMARY_REPO"
        export PATH="$SANDBOX_BIN:$PATH"
        export WRAP_LEARNINGS="none"
        # worktrees.sh outputs peer dirty worktree
        cat > "$FIXTURES/worktrees.txt" <<'TXT'
primary          main         -  0  0 M  safe
peer-worktree    peer-branch  -  0  1 -  dirty
TXT
        rc=0
        out="$("$WRAP_SH" test-session 2>&1)" || rc=$?
        if [ "$rc" -eq 0 ] && grep -qE "warn: peer worktree .* held by " <<<"$out"; then
            pass "AT-10 (D1): wrap.sh reports warn on peer worktree and exits 0"
        else
            fail "AT-10 (D1): wrap.sh did not warn and exit 0 on peer worktree anomaly (rc=$rc, out=$out)"
        fi
    )
fi

# --- AT-11 (D5): Mandatory Learnings step verification ------------------------
banner "AT-11 (D5): Mandatory Learnings step verification"
if [ ! -x "$WRAP_SH" ]; then
    fail "AT-11 (D5): $WRAP_SH does not exist or is not executable"
else
    # Case A: WRAP_LEARNINGS unset on non-empty session (R1-1)
    setup_session_with_state
    (
        cd "$PRIMARY_REPO"
        export PATH="$SANDBOX_BIN:$PATH"
        rc=0
        out="$(unset WRAP_LEARNINGS; "$WRAP_SH" test-session 2>&1)" || rc=$?
        if [ "$rc" -eq 2 ] && grep -q "fail: learnings step omitted" <<<"$out"; then
            pass "AT-11 (D5): wrap.sh refuses with exit 2 when learnings step is omitted"
        else
            fail "AT-11 (D5): wrap.sh did not refuse when learnings step was omitted (rc=$rc, out=$out)"
        fi
    )

    # Case B: WRAP_LEARNINGS attested as none on non-empty session (R1-1)
    setup_session_with_state
    (
        cd "$PRIMARY_REPO"
        export PATH="$SANDBOX_BIN:$PATH"
        rc=0
        out="$(WRAP_LEARNINGS="none" "$WRAP_SH" test-session 2>&1)" || rc=$?
        if [ "$rc" -eq 0 ] && grep -q "pass: learnings accounted for" <<<"$out"; then
            pass "AT-11 (D5): wrap.sh passes when learnings attestation is provided"
        else
            fail "AT-11 (D5): wrap.sh did not pass when learnings attestation was provided (rc=$rc, out=$out)"
        fi
    )
fi

# --- AT-12 (D1, Check 17): Credential leak detection --------------------------
banner "AT-12 (D1, Check 17): Credential leak detection"
if [ ! -x "$WRAP_SH" ]; then
    fail "AT-12 (D1): $WRAP_SH does not exist or is not executable"
else
    setup_sandbox
    (
        cd "$PRIMARY_REPO"
        export PATH="$SANDBOX_BIN:$PATH"
        # Introduce a credential pattern in a staged file
        tok_pfx="ghp_"; echo "${tok_pfx}123456789012345678901234567890123456" > secret.txt
        git add secret.txt
        rc=0
        out="$("$WRAP_SH" test-session 2>&1)" || rc=$?
        if [ "$rc" -eq 2 ] && grep -q "fail: credential exposure detected" <<<"$out"; then
            pass "AT-12 (D1): wrap.sh refuses with exit 2 when credential exposure is detected"
        else
            fail "AT-12 (D1): wrap.sh did not refuse with exit 2 on credential exposure (rc=$rc, out=$out)"
        fi
    )
fi

# --- AT-13 (D7, Exit 1): Environment and argument failure ---------------------
banner "AT-13 (D7, Exit 1): Environment and argument failure"
if [ ! -x "$WRAP_SH" ]; then
    fail "AT-13 (D7): $WRAP_SH does not exist or is not executable"
else
    setup_sandbox
    (
        cd "$PRIMARY_REPO"
        export PATH="$SANDBOX_BIN:$PATH"
        # Case A: Missing required session argument
        rc=0
        out="$("$WRAP_SH" 2>&1)" || rc=$?
        if [ "$rc" -eq 1 ]; then
            pass "AT-13 (D7): wrap.sh exits 1 when invoked without required arguments"
        else
            fail "AT-13 (D7): wrap.sh did not exit 1 on missing arguments (rc=$rc, out=$out)"
        fi

        # Case B: Outside a git repository
        NON_GIT="$SANDBOX/non-git"
        mkdir -p "$NON_GIT"
        rc=0
        out="$(cd "$NON_GIT" && "$WRAP_SH" test-session 2>&1)" || rc=$?
        if [ "$rc" -eq 1 ]; then
            pass "AT-13 (D7): wrap.sh exits 1 when invoked outside a git repository"
        else
            fail "AT-13 (D7): wrap.sh did not exit 1 outside a git repository (rc=$rc, out=$out)"
        fi

        # Case C: Missing required binary (e.g. jq missing from PATH) (R1-8)
        RESTRICTED_BIN="$SANDBOX/restricted_bin"
        mkdir -p "$RESTRICTED_BIN"
        for util in bash sh env sed grep cat date mktemp rm; do
            u_path="$(command -v "$util" 2>/dev/null || :)"
            [ -n "$u_path" ] && [ -x "$u_path" ] && ln -sf "$u_path" "$RESTRICTED_BIN/$util"
        done
        [ -n "$REAL_GIT" ] && [ -x "$REAL_GIT" ] && ln -sf "$REAL_GIT" "$RESTRICTED_BIN/git"
        [ -n "$REAL_GH" ] && [ -x "$REAL_GH" ] && ln -sf "$REAL_GH" "$RESTRICTED_BIN/gh"
        [ -n "$REAL_GAWK" ] && [ -x "$REAL_GAWK" ] && ln -sf "$REAL_GAWK" "$RESTRICTED_BIN/gawk"
        # Verify valid non-dangling symlinks
        [ -x "$RESTRICTED_BIN/bash" ] && [ -x "$RESTRICTED_BIN/git" ] && [ -x "$RESTRICTED_BIN/gh" ] && [ -x "$RESTRICTED_BIN/gawk" ]
        # Note: jq is omitted
        rc=0
        out="$(PATH="$RESTRICTED_BIN" "$WRAP_SH" test-session 2>&1)" || rc=$?
        if [ "$rc" -eq 1 ]; then
            pass "AT-13 (D7): wrap.sh exits 1 when a required binary is missing from PATH"
        else
            fail "AT-13 (D7): wrap.sh did not exit 1 on missing binary (rc=$rc, out=$out)"
        fi
    )
fi

# --- AT-14 (D8): Claude door tracking and non-aborting format -----------------
banner "AT-14 (D8): Claude door tracking and non-aborting format"
if git -C "$REPO" ls-files --error-unmatch "$CLAUDE_DOOR" >/dev/null 2>&1; then
    pass "AT-14 (D8): .claude/commands/wrap.md is tracked past gitignore"
else
    fail "AT-14 (D8): .claude/commands/wrap.md is missing or untracked"
fi

if [ -f "$CLAUDE_DOOR" ]; then
    if grep -q 'scripts/ops/wrap.sh' "$CLAUDE_DOOR" && grep -q '\$ARGUMENTS' "$CLAUDE_DOOR"; then
        pass "AT-14 (D8): .claude/commands/wrap.md invokes scripts/ops/wrap.sh with \$ARGUMENTS"
    else
        fail "AT-14 (D8): .claude/commands/wrap.md does not invoke scripts/ops/wrap.sh \$ARGUMENTS"
    fi

    # Assert non-aborting execution format (e.g. || true or explicit exit handling so exit 2 does not abort turn)
    if grep -qE '(\|\| true|wrap\.sh.*\|\|)' "$CLAUDE_DOOR"; then
        pass "AT-14 (D8): .claude/commands/wrap.md uses non-aborting execution format"
    else
        fail "AT-14 (D8): .claude/commands/wrap.md lacks non-aborting execution format"
    fi
else
    fail "AT-14 (D8): .claude/commands/wrap.md file does not exist"
fi

# Assert CI compiler roundtrip gate checks Claude door tracking
if grep -q '\.claude/commands/wrap\.md' "$REPO/scripts/ci/compiler_roundtrip.sh" 2>/dev/null; then
    pass "AT-14 (D8): scripts/ci/compiler_roundtrip.sh validates Claude door tracking"
else
    fail "AT-14 (D8): scripts/ci/compiler_roundtrip.sh missing Claude door tracking check"
fi

# --- AT-15 (D10, D15): Living spec upsert, checklist obligation, and CI registration ---
banner "AT-15 (D10, D15): Living spec upsert, checklist obligation, and CI registration"
if grep -q 'ops\.wrap' "$SPEC_MD" 2>/dev/null; then
    pass "AT-15 (D10): docs/SPEC.md defines capability ops.wrap"
else
    fail "AT-15 (D10): docs/SPEC.md missing capability ops.wrap"
fi

if sed -n '/## Session checklist/,/## Document map/p' "$AGENTS_MD" 2>/dev/null | grep -q '/wrap'; then
    pass "AT-15 (D10): AGENTS.md includes /wrap in session checklist"
else
    fail "AT-15 (D10): AGENTS.md session checklist missing /wrap step"
fi

if grep -q 'scripts/ops/tests/wrap_test\.sh' "$CI_GATES" 2>/dev/null; then
    pass "AT-15 (D15): .github/workflows/ci-gates.yml registers wrap_test.sh execution step"
else
    fail "AT-15 (D15): .github/workflows/ci-gates.yml missing wrap_test.sh execution step"
fi

# --- AT-16 (D11): Snapshot mode execution and overwrite in place --------------
banner "AT-16 (D11): Snapshot mode execution and overwrite in place"
if [ ! -x "$WRAP_SH" ]; then
    fail "AT-16 (D11): $WRAP_SH does not exist or is not executable"
else
    setup_sandbox
    (
        cd "$PRIMARY_REPO"
        export PATH="$SANDBOX_BIN:$PATH"
        rc=0
        out="$("$WRAP_SH" test-session my-seat --snapshot 2>&1)" || rc=$?
        handoff_file="$(ls -1 ops/handoffs/handoff-my-seat-*.txt 2>/dev/null | head -1 || :)"
        if [ "$rc" -eq 0 ] && [ -n "$handoff_file" ] && [ -f "$handoff_file" ]; then
            first_line="$(head -n 1 "$handoff_file")"
            if grep -qE '^SNAPSHOT \(session still running, written [0-9]{2}:[0-9]{2}Z\)' <<<"$first_line"; then
                pass "AT-16 (D11): handoff file line 1 matches SNAPSHOT marker"
            else
                fail "AT-16 (D11): handoff file line 1 does not match SNAPSHOT marker (got: $first_line)"
            fi

            # Second snapshot invocation in same session: must overwrite in place without incrementing suffix
            rc=0
            out2="$("$WRAP_SH" test-session my-seat --snapshot 2>&1)" || rc=$?
            count="$(ls -1 ops/handoffs/handoff-my-seat-*.txt 2>/dev/null | wc -l)"
            if [ "$rc" -eq 0 ] && [ "$count" -eq 1 ]; then
                pass "AT-16 (D11): repeated snapshot overwrites in place without incrementing suffix count"
            else
                fail "AT-16 (D11): repeated snapshot failed in-place overwrite (count=$count, rc=$rc)"
            fi
        else
            fail "AT-16 (D11): wrap.sh --snapshot did not write handoff file or exited non-zero (rc=$rc, out=$out)"
        fi
    )
fi

# --- AT-17 (D12): Empty session short-circuit ---------------------------------
banner "AT-17 (D12): Empty session short-circuit"
if [ ! -x "$WRAP_SH" ]; then
    fail "AT-17 (D12): $WRAP_SH does not exist or is not executable"
else
    # Pristine clean sandbox with zero session state (R1-1)
    setup_sandbox
    (
        cd "$PRIMARY_REPO"
        export PATH="$SANDBOX_BIN:$PATH"
        rc=0
        out="$("$WRAP_SH" test-session 2>&1)" || rc=$?
        file_count="$(ls -1 ops/handoffs 2>/dev/null | wc -l)"
        if [ "$rc" -eq 0 ] && grep -q "nothing to hand off: session clean and produced no state" <<<"$out" && [ "$file_count" -eq 0 ]; then
            pass "AT-17 (D12): wrap.sh short-circuits empty clean session with exit 0 and zero files written"
        else
            fail "AT-17 (D12): wrap.sh did not short-circuit empty clean session (rc=$rc, files=$file_count, out=$out)"
        fi
    )
fi

# --- AT-18 (D12): Mode-gated probe counts under snapshot ----------------------
banner "AT-18 (D12): Mode-gated probe counts under snapshot"
if [ ! -x "$WRAP_SH" ]; then
    fail "AT-18 (D12): $WRAP_SH does not exist or is not executable"
else
    setup_sandbox
    (
        cd "$PRIMARY_REPO"
        export PATH="$SANDBOX_BIN:$PATH"
        : > "$CALLS_LOG"
        rc=0
        out="$("$WRAP_SH" test-session my-seat --snapshot 2>&1)" || rc=$?

        # Verify network probes (git fetch, gh pr list) and worktree enumeration (worktrees.sh) did NOT run (R1-2)
        network_git="$(grep -E '^git fetch' "$CALLS_LOG" | wc -l || :)"
        network_gh="$(grep -E '^gh pr list' "$CALLS_LOG" | wc -l || :)"
        wt_calls="$(grep -E '^worktrees\.sh' "$CALLS_LOG" | wc -l || :)"
        total_gated=$((network_git + network_gh + wt_calls))

        # Verify that cheap probes ran, proving calls.log logging is active (R1-2)
        cheap_calls="$(grep -E '^git status' "$CALLS_LOG" | wc -l || :)"

        if [ "$rc" -eq 0 ] && [ "$total_gated" -eq 0 ] && [ "$cheap_calls" -ge 1 ]; then
            pass "AT-18 (D12): wrap.sh gates expensive network and worktree probes under --snapshot (gated: 0, cheap: $cheap_calls)"
        else
            fail "AT-18 (D12): wrap.sh probe gating failed under --snapshot (git_fetch=$network_git, gh_pr=$network_gh, wt=$wt_calls, cheap=$cheap_calls, rc=$rc)"
        fi
    )
fi

# --- AT-19 (D13): Seat resolution order, resume block, and pointers -----------
banner "AT-19 (D13): Seat resolution order, resume block, and pointers"
if [ ! -x "$WRAP_SH" ]; then
    fail "AT-19 (D13): $WRAP_SH does not exist or is not executable"
else
    # Seat resolution evaluated on a session with state (R1-1)
    setup_session_with_state
    (
        cd "$PRIMARY_REPO"
        export PATH="$SANDBOX_BIN:$PATH"
        export WRAP_LEARNINGS="none"

        # Pre-seed existing handoff files so custom-seat and env-seat resolve as established seats (D13)
        today="$(date +%Y-%m-%d)"
        touch "$PRIMARY_REPO/ops/handoffs/handoff-custom-seat-${today}.txt"
        touch "$PRIMARY_REPO/ops/handoffs/handoff-env-seat-${today}.txt"

        # 1. Argument seat resolution (matching existing handoff)
        rc=0
        out_arg="$("$WRAP_SH" test-session custom-seat 2>&1)" || rc=$?
        has_arg_resume=0
        if [ "$rc" -eq 0 ] && grep -qE "resume:[[:space:]]+ops/waves/seat\.sh custom-seat" <<<"$out_arg"; then
            has_arg_resume=1
        fi

        # 2. $CLAUDE_SEAT resolution
        rc=0
        out_env="$(CLAUDE_SEAT=env-seat "$WRAP_SH" test-session 2>&1)" || rc=$?
        has_env_resume=0
        if [ "$rc" -eq 0 ] && grep -qE "resume:[[:space:]]+ops/waves/seat\.sh env-seat" <<<"$out_env"; then
            has_env_resume=1
        fi

        # 3. Typo refusal: ad-hoc slug without existing handoff refuses with exit 2 (D13, AT-19)
        rc=0
        out_typo="$("$WRAP_SH" test-session non-existent-adhoc 2>&1)" || rc=$?
        typo_refused=0
        if [ "$rc" -eq 2 ] && grep -qi "refused" <<<"$out_typo"; then
            typo_refused=1
        fi

        # 4. Terminating output format assertions (absolute handoff path, pointers, claude --resume rejection)
        has_abs_path=0
        if grep -qE "handoff:[[:space:]]+/.+/ops/handoffs/handoff-" <<<"$out_arg"; then
            has_abs_path=1
        fi
        has_pointers=0
        if grep -q "ops/waves/seat.sh --list" <<<"$out_arg" && grep -q "ops/waves/seat.sh --last" <<<"$out_arg"; then
            has_pointers=1
        fi
        rejects_claude_resume=0
        if grep -q "claude --resume" <<<"$out_arg"; then
            rejects_claude_resume=1
        fi

        if [ "$has_arg_resume" -eq 1 ] && [ "$has_env_resume" -eq 1 ] && [ "$typo_refused" -eq 1 ] && [ "$has_abs_path" -eq 1 ] && [ "$has_pointers" -eq 1 ] && [ "$rejects_claude_resume" -eq 1 ]; then
            pass "AT-19 (D13): seat resolution order, resume block format, and pointers verified"
        else
            fail "AT-19 (D13): failed seat resolution or resume report (arg=$has_arg_resume, env=$has_env_resume, typo=$typo_refused, abs=$has_abs_path, ptr=$has_pointers, reject_resume=$rejects_claude_resume)"
        fi
    )
fi

# --- Summary ------------------------------------------------------------------
banner "Wrap Contract Test Summary"
if [ "$FAILURES" -gt 0 ]; then
    echo "Total contract test failures: $FAILURES (EXPECTED RED at build rung)" >&2
    exit 1
fi

echo "ALL TESTS PASSED"
exit 0
