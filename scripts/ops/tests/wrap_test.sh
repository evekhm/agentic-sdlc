#!/usr/bin/env bash
# Contract test suite for session close-out (/wrap) (#85).
# Spec: intent/85-session-close-out/spec.md (Approved, D1-D15, AT-1-AT-19)
#
# Cites Decisions D1-D15 and Acceptance Tests AT-1..AT-19.
# Every assertion cites its Decision ID and Acceptance Test ID.
# Under the baseline tree prior to implementation, assertions test unbuilt
# functionality and fail cleanly (red).
#
# The suite is hermetic: it operates in a self-contained sandbox with PATH
# shims over git, gh, and worktrees.sh, avoiding any mutation of the host
# checkout or reliance on backdoor env vars.
#
# Set WRAP_SH to point the suite at a candidate implementation; it defaults to
# scripts/ops/wrap.sh in this repository.
#
# --- Contracts the assertions rely on ----------------------------------------
#
# C1 (R1-1, D12).  D12(c) short-circuits only when the session produced no
#    decisions, no runs/ artifacts and no tracker modifications.  Every
#    acceptance test that demands full close-out output therefore calls
#    seed_session_state, which gives the sandbox a runs/ artifact carrying its
#    disposition footnote (so Check 10 passes) and a tracker claim on issue #88
#    carrying a valid handoff comment (so Check 8 passes).  AT-17 is the only
#    test that keeps the pristine sandbox, so AT-1 and AT-17 are satisfiable by
#    one conforming implementation.
#
# C2 (R1-6, D1/D3).  wrap.sh takes a session NAME, not a PID (D2), so Check 1
#    attributes a process to the session when it is an active child of
#    wrap.sh's own parent process ($PPID), excluding wrap.sh itself and its
#    descendants, or when its PID is recorded live in a worktree lock file
#    owned by this session (plan.md P2).  AT-2 therefore spawns its child from
#    the same shell that invokes wrap.sh, and invokes wrap.sh directly rather
#    than through a command substitution, which would insert an extra forked
#    shell between the two and break the $PPID relation.
#
# C3 (AT-R1-1, D13).  An explicitly supplied seat token (CLI argument or
#    $CLAUDE_SEAT) resolves when it matches either a standing seat listed by
#    ops/waves/seat.sh --list or an existing ops/handoffs/handoff-<token>-*.txt
#    of any date.  A token matching neither is an unrecognised ad-hoc slug and
#    refuses with exit 2 ("exact match with no fallback", D13).  Minting a
#    fresh kebab-case slug is resolution step 4 and applies only when NO seat
#    token was supplied.  This sandbox ships no ops/waves/seat.sh, so the
#    standing-seat set is empty and every fixture below drives the
#    handoff-match branch.  Seat fixtures use a prior date, keeping resolution
#    step 1 and step 2 distinguishable from step 3.
#
# C4 (R1-2, R1-3).  Shim instrumentation is proved live, never assumed.
#    $CALLS_LOG, $WRITES_LOG and $FIXTURES are exported so the shim processes
#    can see them, and every shim line records the binary name followed by its
#    arguments.  Assertions that count gated probes or assert zero mutations
#    additionally require a control line in $CALLS_LOG, so a broken log makes
#    the test fail instead of passing vacuously.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WRAP_SH="${WRAP_SH:-$REPO/scripts/ops/wrap.sh}"
CLAUDE_DOOR="$REPO/.claude/commands/wrap.md"
SPEC_MD="$REPO/docs/SPEC.md"
AGENTS_MD="$REPO/AGENTS.md"
CI_GATES="$REPO/.github/workflows/ci-gates.yml"

# R1-8: resolve the real binaries from the host PATH before any shim is
# installed, never from a hardcoded /usr/bin path.
REAL_GIT="$(command -v git || :)"
REAL_JQ="$(command -v jq || :)"
export REAL_GIT
TODAY="$(date -u +%Y-%m-%d)"
PRIOR_DATE="2026-01-02"
export TODAY PRIOR_DATE

FAIL_LOG="$(mktemp "${TMPDIR:-/tmp}/wrap_test_fails.XXXXXX")"
export FAIL_LOG
FAILURES=0

banner() { printf '\n=== %s ===\n' "$*"; }

pass() {
    echo "PASS: $*"
}

fail() {
    echo "FAIL: $*" >&2
    echo "1" >> "$FAIL_LOG"
}

# Count log lines matching a regex. Yields 0 for "no matches" and for a
# missing log rather than an empty string that would break arithmetic.
count_calls() {
    local n
    n="$(grep -cE "$1" "$CALLS_LOG" 2>/dev/null)" || n=0
    [ -n "$n" ] || n=0
    printf '%s' "$n"
}

# --- Sandbox and Stub Infrastructure -----------------------------------------
SANDBOXES=()
cleanup() {
    local s
    for s in "${SANDBOXES[@]:-}"; do
        [ -n "$s" ] && [ -d "$s" ] && rm -rf "$s"
    done
    [ -n "${FAIL_LOG:-}" ] && [ -f "$FAIL_LOG" ] && rm -f "$FAIL_LOG"
}
trap cleanup EXIT

setup_sandbox() {
    SANDBOX="$(mktemp -d)"
    SANDBOXES+=("$SANDBOX")
    SANDBOX_BIN="$SANDBOX/bin"
    FIXTURES="$SANDBOX/fixtures"
    CALLS_LOG="$SANDBOX/calls.log"
    WRITES_LOG="$SANDBOX/writes.log"
    ORIGIN_REPO="$SANDBOX/origin.git"
    PRIMARY_REPO="$SANDBOX/primary"
    # C4: the shims are separate processes, so every name they read must be
    # exported or their redirects land on the empty string.
    export SANDBOX SANDBOX_BIN FIXTURES CALLS_LOG WRITES_LOG
    export ORIGIN_REPO PRIMARY_REPO
    # R1-3: the sandbox origin is a local bare path with no GitHub owner or
    # name, so give the implementation a repository slug to resolve against.
    export GH_REPO="test/repo"
    export GITHUB_REPOSITORY="test/repo"

    mkdir -p "$SANDBOX_BIN" "$FIXTURES"
    : > "$CALLS_LOG"
    : > "$WRITES_LOG"

    "$REAL_GIT" init --bare -b main "$ORIGIN_REPO" >/dev/null 2>&1
    "$REAL_GIT" clone "$ORIGIN_REPO" "$PRIMARY_REPO" >/dev/null 2>&1
    "$REAL_GIT" -C "$PRIMARY_REPO" config user.name "Tester"
    "$REAL_GIT" -C "$PRIMARY_REPO" config user.email "tester@example.com"

    mkdir -p "$PRIMARY_REPO/ops/handoffs" "$PRIMARY_REPO/runs" \
             "$PRIMARY_REPO/scripts/ops" "$PRIMARY_REPO/scripts/ci"

    # ops/ and runs/ are ignored in the sandbox exactly as they are in the real
    # repository, so seeded session state never dirties the tree and Check 4
    # stays honest.
    printf '%s\n' "ops/" "runs/" > "$PRIMARY_REPO/.gitignore"
    echo "# Test Repo" > "$PRIMARY_REPO/README.md"

    # Check 12 twin run (D6): both resolvers exist in the sandbox and pass.
    printf '%s\n' 'import sys' 'sys.exit(0)' > "$PRIMARY_REPO/scripts/sync_agents.py"
    printf '%s\n' '#!/usr/bin/env bash' 'exit 0' \
        > "$PRIMARY_REPO/scripts/ci/compiler_roundtrip.sh"
    chmod +x "$PRIMARY_REPO/scripts/ci/compiler_roundtrip.sh"

    # Check 16 spend rollup resolver (D6).
    printf '%s\n' '#!/usr/bin/env bash' 'echo "spend: 0.00 usd, tokens: 0"' 'exit 0' \
        > "$PRIMARY_REPO/scripts/ops/session_spend.sh"
    chmod +x "$PRIMARY_REPO/scripts/ops/session_spend.sh"

    # Check 15 and AT-18 worktree probe. Installed in the repo, because D12
    # names scripts/ops/worktrees.sh by path, and on PATH, logging identically.
    cat > "$PRIMARY_REPO/scripts/ops/worktrees.sh" <<'STUB_WT'
#!/usr/bin/env bash
printf 'worktrees.sh %s\n' "$*" >> "$CALLS_LOG"
if [ -f "$FIXTURES/worktrees.txt" ]; then
    cat "$FIXTURES/worktrees.txt"
else
    echo "primary  main  -  0  0 M  safe"
fi
exit 0
STUB_WT
    chmod +x "$PRIMARY_REPO/scripts/ops/worktrees.sh"
    cp "$PRIMARY_REPO/scripts/ops/worktrees.sh" "$SANDBOX_BIN/worktrees.sh"

    (
        cd "$PRIMARY_REPO" || exit 1
        "$REAL_GIT" add -A
        "$REAL_GIT" commit -m "initial commit" -q
        "$REAL_GIT" push -q origin main
    )

    # PATH stub: gh. R1-2: logs "gh <args>" so AT-18's ^gh anchors can match.
    # R1-3: serves fixtures keyed on the endpoint with any repos/<owner>/<name>/
    # prefix stripped, so fixtures stay reachable however the implementation
    # chooses to spell the endpoint.
    cat > "$SANDBOX_BIN/gh" <<'STUB_GH'
#!/usr/bin/env bash
printf 'gh %s\n' "$*" >> "$CALLS_LOG"
if [[ "$*" =~ (POST|PATCH|DELETE|PUT) ]] \
   || [[ "$*" =~ "pr create" ]] || [[ "$*" =~ "pr edit" ]] \
   || [[ "$*" =~ "issue create" ]] || [[ "$*" =~ "issue edit" ]] \
   || [[ "$*" =~ "issue comment" ]] || [[ "$*" =~ "label remove" ]]; then
    printf 'gh %s\n' "$*" >> "$WRITES_LOG"
fi

serve() {
    if [ -f "$FIXTURES/$1.json" ]; then
        cat "$FIXTURES/$1.json"
    else
        printf '%s\n' "$2"
    fi
    exit 0
}

if [ "${1:-}" = "api" ]; then
    method="GET"
    endpoint=""
    shift
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --method|-X) method="$2"; shift 2 ;;
            -f|-F|--raw-field|-q|--jq|-H) shift 2 ;;
            --paginate|--silent) shift ;;
            -*) shift ;;
            *) endpoint="$1"; shift ;;
        esac
    done
    if [ "$method" != "GET" ]; then
        exit 0
    fi
    key="${endpoint%%\?*}"
    key="${key#/}"
    case "$key" in
        repos/*/*/*) key="${key#repos/}"; key="${key#*/}"; key="${key#*/}" ;;
    esac
    key="${key//\//_}"
    key="${key//:/_}"
    case "$key" in
        *comments) serve "$key" "[]" ;;
        *labels)   serve "$key" "[]" ;;
        pulls*)    serve "pr_list" "[]" ;;
        issues)    serve "issue_list" "[]" ;;
        *)         serve "$key" "{}" ;;
    esac
fi

if [ "${1:-}" = "repo" ] && [ "${2:-}" = "view" ]; then
    if [[ "$*" =~ json ]]; then
        echo '{"nameWithOwner":"test/repo","owner":{"login":"test"},"name":"repo"}'
    else
        echo "test/repo"
    fi
    exit 0
fi

if [ "${1:-}" = "pr" ] && [ "${2:-}" = "list" ]; then
    serve "pr_list" "[]"
fi

if { [ "${1:-}" = "issue" ] && [ "${2:-}" = "list" ]; } \
   || { [ "${1:-}" = "search" ] && [ "${2:-}" = "issues" ]; }; then
    serve "issue_list" "[]"
fi

if [ "${1:-}" = "issue" ] && [ "${2:-}" = "view" ]; then
    serve "issue_${3:-}" "{}"
fi

exit 0
STUB_GH
    chmod +x "$SANDBOX_BIN/gh"

    # PATH stub: git wrapper. R1-2: logs "git <args>". R1-8: delegates to the
    # resolved real git rather than a hardcoded /usr/bin/git.
    cat > "$SANDBOX_BIN/git" <<'STUB_GIT'
#!/usr/bin/env bash
printf 'git %s\n' "$*" >> "$CALLS_LOG"
exec "$REAL_GIT" "$@"
STUB_GIT
    chmod +x "$SANDBOX_BIN/git"
}

# C1 (R1-1): make the sandbox a NON-empty session so D12(c) cannot fire.
# The artifact carries its disposition footnote and the claimed issue carries a
# valid handoff comment, so Check 10 and Check 8 both pass on this fixture.
seed_session_state() {
    mkdir -p "$PRIMARY_REPO/runs/test-session"
    printf '%s\n' \
        "session run notes" \
        "" \
        "--- Disposition (2026-09-10): filed as #85." \
        > "$PRIMARY_REPO/runs/test-session/notes.md"

    cat > "$FIXTURES/issue_list.json" <<'JSON'
[{"number":88,"title":"seeded claim","labels":[{"name":"status:implementing"}]}]
JSON
    cat > "$FIXTURES/issues_88_labels.json" <<'JSON'
[{"name":"status:implementing"}]
JSON
    cat > "$FIXTURES/issues_88_comments.json" <<'JSON'
[
  {"user":{"login":"evekhm-odyssey-app[bot]"},"body":"Claim: odyssey (test-session), stage: implementing."},
  {"user":{"login":"evekhm-odyssey-app[bot]"},"body":"Done: seeded work\nDecided: none\nNext: review\nBlocked: none"}
]
JSON
    cat > "$FIXTURES/issue_88.json" <<'JSON'
{"number":88,"title":"seeded claim","labels":[{"name":"status:implementing"}]}
JSON
}

# Overwrite the seeded tracker fixture so issue #88 carries a stale
# in-progress label (the D4 auto-repair input for AT-6 and AT-7).
seed_stale_in_progress() {
    cat > "$FIXTURES/issue_list.json" <<'JSON'
[{"number":88,"title":"seeded claim","labels":[{"name":"in-progress"},{"name":"status:implementing"}]}]
JSON
    cat > "$FIXTURES/issues_88_labels.json" <<'JSON'
[{"name":"in-progress"},{"name":"status:implementing"}]
JSON
    cat > "$FIXTURES/issue_88.json" <<'JSON'
{"number":88,"title":"seeded claim","labels":[{"name":"in-progress"},{"name":"status:implementing"}]}
JSON
}

# --- AT-1 (D7, Exit 0): Clean session close-out -------------------------------
banner "AT-1 (D7, Exit 0): Clean session close-out"
if [ ! -x "$WRAP_SH" ]; then
    fail "AT-1 (D7): $WRAP_SH does not exist or is not executable"
else
    setup_sandbox
    seed_session_state
    (
        cd "$PRIMARY_REPO" || exit 1
        export PATH="$SANDBOX_BIN:$PATH"
        export WRAP_LEARNINGS="none"
        rc=0
        out="$("$WRAP_SH" test-session 2>&1)" || rc=$?
        handoff_count="$(find ops/handoffs -maxdepth 1 -name 'handoff-*.txt' 2>/dev/null | wc -l)"
        if [ "$rc" -eq 0 ] \
           && grep -qE '^(status: )?closed$' <<<"$out" \
           && ! grep -q "not closed" <<<"$out" \
           && grep -q "handoff:" <<<"$out" \
           && [ "$handoff_count" -ge 1 ]; then
            pass "AT-1 (D7): wrap.sh prints closed, writes a handoff, and exits 0 on a session that produced state"
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
    seed_session_state
    (
        cd "$PRIMARY_REPO" || exit 1
        export PATH="$SANDBOX_BIN:$PATH"
        export WRAP_LEARNINGS="none"
        # C2 (R1-6): the child is spawned by this subshell and wrap.sh is
        # invoked directly by the same subshell, so the child is a sibling of
        # wrap.sh and a child of wrap.sh's $PPID, which is the attribution rule
        # Check 1 uses. Output goes through a file, because a command
        # substitution would place wrap.sh under an extra forked shell and
        # break that relation.
        sleep 5 &
        child_pid=$!
        rc=0
        "$WRAP_SH" test-session > "$SANDBOX/at2.out" 2>&1 || rc=$?
        out="$(cat "$SANDBOX/at2.out")"
        kill "$child_pid" 2>/dev/null || :
        wait "$child_pid" 2>/dev/null || :
        if [ "$rc" -eq 2 ] && grep -q "refused: child processes still running" <<<"$out"; then
            pass "AT-2 (D1): wrap.sh reports fail on Check 1 and exits 2 when a sibling child of the session shell is active"
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
    seed_session_state
    (
        cd "$PRIMARY_REPO" || exit 1
        export PATH="$SANDBOX_BIN:$PATH"
        export WRAP_LEARNINGS="none"
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
    seed_session_state
    (
        cd "$PRIMARY_REPO" || exit 1
        export PATH="$SANDBOX_BIN:$PATH"
        export WRAP_LEARNINGS="none"
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
    seed_session_state
    (
        cd "$PRIMARY_REPO" || exit 1
        export PATH="$SANDBOX_BIN:$PATH"
        export WRAP_LEARNINGS="none"
        # Case A: Code defect failure on session PR #42
        cat > "$FIXTURES/pr_list.json" <<'JSON'
[{"number":42,"headRefName":"odyssey/test","author":{"login":"tester"},"statusCheckRollup":[{"conclusion":"FAILURE","name":"test-code","detailsUrl":"job/1"}]}]
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
[{"number":42,"headRefName":"odyssey/test","author":{"login":"tester"},"statusCheckRollup":[{"conclusion":"STARTUP_FAILURE","name":"infrastructure-runner","detailsUrl":"job/2"}]}]
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

# --- AT-6 (D4, Check 8 auto-repair): in-progress label removal ----------------
banner "AT-6 (D4, Check 8 auto-repair): in-progress label removal"
if [ ! -x "$WRAP_SH" ]; then
    fail "AT-6 (D4): $WRAP_SH does not exist or is not executable"
else
    setup_sandbox
    seed_session_state
    seed_stale_in_progress
    (
        cd "$PRIMARY_REPO" || exit 1
        export PATH="$SANDBOX_BIN:$PATH"
        export WRAP_LEARNINGS="none"
        : > "$WRITES_LOG"
        : > "$CALLS_LOG"
        rc=0
        out="$("$WRAP_SH" test-session 2>&1)" || rc=$?
        ho_file="$(find ops/handoffs -name "handoff-*.txt" | head -1)"
        has_claimed_in_ho=0
        if [ -n "$ho_file" ] && grep -A 2 "## Claimed Issues" "$ho_file" 2>/dev/null | grep -q "#88"; then
            has_claimed_in_ho=1
        fi

        if [ "$rc" -eq 0 ] \
           && grep -qE "fixed: removed in-progress from #88" <<<"$out" \
           && grep -qE "(DELETE.*labels/in-progress|label remove in-progress)" "$WRITES_LOG" \
           && [ "$has_claimed_in_ho" -eq 1 ]; then
            pass "AT-6 (D4): wrap.sh removes in-progress, reports fixed, populates Claimed Issues in handoff, and exits 0"
        else
            fail "AT-6 (D4): wrap.sh did not auto-repair stale in-progress label or populate handoff (rc=$rc, writes=$(wc -l < "$WRITES_LOG"), ho_claimed=$has_claimed_in_ho, out=$out)"
        fi
    )

    # Mutation test 1 (R1-1/R1-9/R2-2): auto-repair MUST NOT execute when any check fails
    setup_sandbox
    seed_session_state
    seed_stale_in_progress
    (
        cd "$PRIMARY_REPO" || exit 1
        export PATH="$SANDBOX_BIN:$PATH"
        : > "$WRITES_LOG"
        : > "$CALLS_LOG"
        rc=0
        # Omit WRAP_LEARNINGS so Check Learnings fails with exit 2
        out="$(unset WRAP_LEARNINGS; "$WRAP_SH" test-session 2>&1)" || rc=$?
        writes="$(wc -l < "$WRITES_LOG")"
        if [ "$rc" -eq 2 ] && [ "$writes" -eq 0 ]; then
            pass "AT-6 (D4, mutation 1): auto-repair suppressed when close-out check fails (rc=2, writes=0)"
        else
            fail "AT-6 (D4, mutation 1): auto-repair executed despite check failure (rc=$rc, writes=$writes, out=$out)"
        fi
    )
fi

# --- AT-7 (D4, DRY_RUN contract): dry-run would-fix refusal -------------------
banner "AT-7 (D4, DRY_RUN contract): dry-run would-fix refusal"
if [ ! -x "$WRAP_SH" ]; then
    fail "AT-7 (D4): $WRAP_SH does not exist or is not executable"
else
    setup_sandbox
    seed_session_state
    seed_stale_in_progress
    (
        cd "$PRIMARY_REPO" || exit 1
        export PATH="$SANDBOX_BIN:$PATH"
        export WRAP_LEARNINGS="none"
        : > "$WRITES_LOG"
        : > "$CALLS_LOG"
        rc=0
        out="$(DRY_RUN=1 "$WRAP_SH" test-session 2>&1)" || rc=$?
        # C4 (R1-3): the zero-mutation clause only carries meaning once the
        # shim is proved live, so a gh read call must be on record before an
        # empty write log counts as evidence.
        gh_reads="$(count_calls '^gh ')"
        writes="$(wc -l < "$WRITES_LOG")"
        if [ "$rc" -eq 2 ] \
           && grep -qE "would: remove in-progress from #88" <<<"$out" \
           && grep -qE "fail: #88 carries in-progress \(dry-run\)" <<<"$out" \
           && [ "$gh_reads" -gt 0 ] && [ ! -s "$WRITES_LOG" ]; then
            pass "AT-7 (D4): wrap.sh prints would-fix, reports fail, exits 2, and makes zero write calls under DRY_RUN=1 (gh calls observed: $gh_reads)"
        else
            fail "AT-7 (D4): wrap.sh failed DRY_RUN contract on would-fix scenario (rc=$rc, gh_calls=$gh_reads, writes=$writes, out=$out)"
        fi
    )

    # Mutation test 2 (R1-2/R2-2): DRY_RUN=true case parsing
    setup_sandbox
    seed_session_state
    seed_stale_in_progress
    (
        cd "$PRIMARY_REPO" || exit 1
        export PATH="$SANDBOX_BIN:$PATH"
        export WRAP_LEARNINGS="none"
        : > "$WRITES_LOG"
        : > "$CALLS_LOG"
        rc=0
        out="$(DRY_RUN=true "$WRAP_SH" test-session 2>&1)" || rc=$?
        writes="$(wc -l < "$WRITES_LOG")"
        if [ "$rc" -eq 2 ] \
           && grep -qE "would: remove in-progress from #88" <<<"$out" \
           && [ "$writes" -eq 0 ]; then
            pass "AT-7 (D4, mutation 2): DRY_RUN=true parsed correctly, zero mutations executed"
        else
            fail "AT-7 (D4, mutation 2): DRY_RUN=true parsing failed (rc=$rc, writes=$writes, out=$out)"
        fi
    )
fi

# --- AT-8 (D1, Check 8 refusal): missing handoff comment & claim isolation ----
banner "AT-8 (D1, Check 8 refusal): missing handoff comment & claim isolation"
if [ ! -x "$WRAP_SH" ]; then
    fail "AT-8 (D1): $WRAP_SH does not exist or is not executable"
else
    # Case A: Missing handoff comment
    setup_sandbox
    seed_session_state
    seed_stale_in_progress
    (
        cd "$PRIMARY_REPO" || exit 1
        export PATH="$SANDBOX_BIN:$PATH"
        export WRAP_LEARNINGS="none"
        # Issue #88 is claimed by test-session and carries no handoff comment
        cat > "$FIXTURES/issues_88_comments.json" <<'JSON'
[
  {"user":{"login":"evekhm-odyssey-app[bot]"},"body":"Claim: odyssey (test-session), stage: implementing."}
]
JSON
        : > "$WRITES_LOG"
        : > "$CALLS_LOG"
        rc=0
        out="$("$WRAP_SH" test-session 2>&1)" || rc=$?
        gh_reads="$(count_calls '^gh ')"
        writes="$(wc -l < "$WRITES_LOG")"
        if [ "$rc" -eq 2 ] \
           && grep -qE "fail: missing handoff comment on #88" <<<"$out" \
           && [ "$gh_reads" -gt 0 ] && [ ! -s "$WRITES_LOG" ]; then
            pass "AT-8 (D1): wrap.sh reports fail on missing handoff comment, makes no modifications, and exits 2"
        else
            fail "AT-8 (D1): wrap.sh did not refuse with exit 2 when handoff comment was missing (rc=$rc, gh_calls=$gh_reads, writes=$writes, out=$out)"
        fi
    )

    # Mutation test 3 (R1-1/R2-2): Anchored session regex prevents peer claim match
    setup_sandbox
    seed_session_state
    seed_stale_in_progress
    (
        cd "$PRIMARY_REPO" || exit 1
        export PATH="$SANDBOX_BIN:$PATH"
        export WRAP_LEARNINGS="none"
        # Issue #88 claimed by test-session-2 (peer), not test-session
        cat > "$FIXTURES/issues_88_comments.json" <<'JSON'
[
  {"user":{"login":"evekhm-odyssey-app[bot]"},"body":"Claim: odyssey (test-session-2), stage: implementing."},
  {"user":{"login":"evekhm-odyssey-app[bot]"},"body":"Done: work\nDecided: none\nNext: review\nBlocked: none"}
]
JSON
        : > "$WRITES_LOG"
        rc=0
        out="$("$WRAP_SH" test-session 2>&1)" || rc=$?
        writes="$(wc -l < "$WRITES_LOG")"
        if [ "$rc" -eq 0 ] && [ "$writes" -eq 0 ] && ! grep -q "from #88" <<<"$out"; then
            pass "AT-8 (D1, mutation 3): anchored session regex prevents match against peer session prefix (writes=0)"
        else
            fail "AT-8 (D1, mutation 3): peer session claim matched or mutated (rc=$rc, writes=$writes, out=$out)"
        fi
    )

    # Case B (R1-1): Unauthenticated author / drive-by user is rejected
    setup_sandbox
    seed_session_state
    seed_stale_in_progress
    (
        cd "$PRIMARY_REPO" || exit 1
        export PATH="$SANDBOX_BIN:$PATH"
        export WRAP_LEARNINGS="none"
        cat > "$FIXTURES/issues_88_comments.json" <<'JSON'
[
  {"user":{"login":"random-drive-by-user"},"body":"Claim: odyssey (test-session), stage: implementing.\nDone: work\nDecided: none\nNext: review\nBlocked: none"}
]
JSON
        : > "$WRITES_LOG"
        rc=0
        out="$("$WRAP_SH" test-session 2>&1)" || rc=$?
        writes="$(wc -l < "$WRITES_LOG")"
        if [ "$rc" -eq 0 ] && [ "$writes" -eq 0 ] && ! grep -q "from #88" <<<"$out"; then
            pass "AT-8 (D1, R1-1): unauthenticated author comment ignored, no auto-repair triggered"
        else
            fail "AT-8 (D1, R1-1): unauthenticated comment triggered auto-repair (rc=$rc, writes=$writes, out=$out)"
        fi
    )

    # Case C (R1-1): Superseding claim by peer prevents auto-repair
    setup_sandbox
    seed_session_state
    seed_stale_in_progress
    (
        cd "$PRIMARY_REPO" || exit 1
        export PATH="$SANDBOX_BIN:$PATH"
        export WRAP_LEARNINGS="none"
        cat > "$FIXTURES/issues_88_comments.json" <<'JSON'
[
  {"user":{"login":"evekhm-odyssey-app[bot]"},"body":"Claim: odyssey (test-session), stage: implementing."},
  {"user":{"login":"evekhm-odyssey-app[bot]"},"body":"Done: work\nDecided: none\nNext: review\nBlocked: none"},
  {"user":{"login":"evekhm-odyssey-app[bot]"},"body":"Claim: odyssey (test-session-2), stage: implementing."}
]
JSON
        : > "$WRITES_LOG"
        rc=0
        out="$("$WRAP_SH" test-session 2>&1)" || rc=$?
        writes="$(wc -l < "$WRITES_LOG")"
        if [ "$rc" -eq 0 ] && [ "$writes" -eq 0 ] && ! grep -q "from #88" <<<"$out"; then
            pass "AT-8 (D1, R1-1): superseding peer claim respected, no auto-repair on re-claimed issue"
        else
            fail "AT-8 (D1, R1-1): auto-repair deleted label on re-claimed issue (rc=$rc, writes=$writes, out=$out)"
        fi
    )
fi

# --- AT-9 (D1, Check 10): run artifact missing disposition --------------------
banner "AT-9 (D1, Check 10): run artifact missing disposition"
if [ ! -x "$WRAP_SH" ]; then
    fail "AT-9 (D1): $WRAP_SH does not exist or is not executable"
else
    setup_sandbox
    seed_session_state
    (
        cd "$PRIMARY_REPO" || exit 1
        export PATH="$SANDBOX_BIN:$PATH"
        export WRAP_LEARNINGS="none"
        # Alongside the seeded artifact that does carry a footnote, an
        # undispositioned artifact under runs/
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
    setup_sandbox
    seed_session_state
    (
        cd "$PRIMARY_REPO" || exit 1
        export PATH="$SANDBOX_BIN:$PATH"
        export WRAP_LEARNINGS="none"
        # worktrees.sh reports a dirty peer worktree
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
    # Case A: WRAP_LEARNINGS unset on a session that produced state (C1)
    setup_sandbox
    seed_session_state
    (
        cd "$PRIMARY_REPO" || exit 1
        export PATH="$SANDBOX_BIN:$PATH"
        rc=0
        out="$(unset WRAP_LEARNINGS; "$WRAP_SH" test-session 2>&1)" || rc=$?
        if [ "$rc" -eq 2 ] && grep -q "fail: learnings step omitted" <<<"$out"; then
            pass "AT-11 (D5): wrap.sh refuses with exit 2 when learnings step is omitted"
        else
            fail "AT-11 (D5): wrap.sh did not refuse when learnings step was omitted (rc=$rc, out=$out)"
        fi
    )

    # Case B: WRAP_LEARNINGS attested, on a fresh sandbox carrying the same state
    setup_sandbox
    seed_session_state
    (
        cd "$PRIMARY_REPO" || exit 1
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

# --- AT-12 (D1, Check 17 & Check 18): Credential leak detection & temp isolation
banner "AT-12 (D1, Check 17 & Check 18): Credential leak detection & temp isolation"
if [ ! -x "$WRAP_SH" ]; then
    fail "AT-12 (D1): $WRAP_SH does not exist or is not executable"
else
    # Case A: Staged credential exposure
    setup_sandbox
    seed_session_state
    (
        cd "$PRIMARY_REPO" || exit 1
        export PATH="$SANDBOX_BIN:$PATH"
        export WRAP_LEARNINGS="none"
        tok_pfx="ghp_"; echo "${tok_pfx}123456789012345678901234567890123456" > secret.txt
        git add secret.txt
        rc=0
        out="$("$WRAP_SH" test-session 2>&1)" || rc=$?
        if [ "$rc" -eq 2 ] && grep -q "fail: credential exposure detected" <<<"$out"; then
            pass "AT-12 (D1): wrap.sh refuses with exit 2 when staged credential exposure is detected"
        else
            fail "AT-12 (D1): wrap.sh did not refuse with exit 2 on staged credential exposure (rc=$rc, out=$out)"
        fi
    )

    # Case B (R2-1): Committed credential exposure on branch
    setup_sandbox
    seed_session_state
    (
        cd "$PRIMARY_REPO" || exit 1
        export PATH="$SANDBOX_BIN:$PATH"
        export WRAP_LEARNINGS="none"
        tok_pfx="ghp_"; echo "${tok_pfx}999999999012345678901234567890123456" > secret.txt
        git add secret.txt
        git commit -m "add credential commit" >/dev/null 2>&1
        rc=0
        out="$("$WRAP_SH" test-session 2>&1)" || rc=$?
        if [ "$rc" -eq 2 ] && grep -q "fail: credential exposure detected" <<<"$out"; then
            pass "AT-12 (D1, R2-1): wrap.sh refuses with exit 2 when committed credential is on branch"
        else
            fail "AT-12 (D1, R2-1): wrap.sh did not detect committed credential on branch (rc=$rc, out=$out)"
        fi
    )

    # Case C (R2-1): Clean run reports pass: credential scan clean
    setup_sandbox
    seed_session_state
    (
        cd "$PRIMARY_REPO" || exit 1
        export PATH="$SANDBOX_BIN:$PATH"
        export WRAP_LEARNINGS="none"
        rc=0
        out="$("$WRAP_SH" test-session 2>&1)" || rc=$?
        if [ "$rc" -eq 0 ] && grep -q "pass: credential scan clean" <<<"$out"; then
            pass "AT-12 (D1, R2-1): wrap.sh reports pass: credential scan clean on clean scan"
        else
            fail "AT-12 (D1, R2-1): wrap.sh missing pass: credential scan clean (rc=$rc, out=$out)"
        fi
    )

    # Case D (R2-4): Check 18 temp file cleanup isolates session and preserves peer files
    setup_sandbox
    seed_session_state
    (
        cd "$PRIMARY_REPO" || exit 1
        export PATH="$SANDBOX_BIN:$PATH"
        export WRAP_LEARNINGS="none"
        peer_f1="/tmp/argus-review-test-session-2-body.md"
        peer_f2="/tmp/test-session-2-body.tmp"
        my_f="/tmp/test-session-body.tmp"
        touch "$peer_f1" "$peer_f2" "$my_f"
        rc=0
        out="$("$WRAP_SH" test-session 2>&1)" || rc=$?
        my_cleaned=0
        peer_preserved=0
        [ ! -f "$my_f" ] && my_cleaned=1
        [ -f "$peer_f1" ] && [ -f "$peer_f2" ] && peer_preserved=1
        rm -f "$peer_f1" "$peer_f2" "$my_f" 2>/dev/null || true
        if [ "$rc" -eq 0 ] && [ "$my_cleaned" -eq 1 ] && [ "$peer_preserved" -eq 1 ]; then
            pass "AT-12 (D6, R2-4): Check 18 cleans session temp files while preserving peer session temp files"
        else
            fail "AT-12 (D6, R2-4): Check 18 failed isolation (rc=$rc, my_cleaned=$my_cleaned, peer_preserved=$peer_preserved)"
        fi
    )
fi

# --- AT-13 (D7, Exit 1): Environment and argument failure ---------------------
banner "AT-13 (D7, Exit 1): Environment and argument failure"
if [ ! -x "$WRAP_SH" ]; then
    fail "AT-13 (D7): $WRAP_SH does not exist or is not executable"
else
    setup_sandbox
    seed_session_state
    (
        cd "$PRIMARY_REPO" || exit 1
        export PATH="$SANDBOX_BIN:$PATH"
        export WRAP_LEARNINGS="none"
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

        # Case C: Missing required binary (jq). R1-8: link only binaries that
        # resolve on this host, so the case can never pass on a dangling
        # symlink, and refuse to score the case if the fixture is unsound.
        RESTRICTED_BIN="$SANDBOX/restricted_bin"
        mkdir -p "$RESTRICTED_BIN"
        dangling=0
        for util in env bash sh git gh gawk awk sed grep cat cut head tail ls wc \
                    sort uniq tr date mktemp mkdir rm cp mv dirname basename find \
                    xargs readlink realpath id ps python3 stat touch chmod tee diff; do
            u_path="$(command -v "$util" 2>/dev/null || :)"
            [ -n "$u_path" ] || continue
            ln -sf "$u_path" "$RESTRICTED_BIN/$util" 2>/dev/null || :
            [ -e "$RESTRICTED_BIN/$util" ] || dangling=1
        done
        # jq is deliberately withheld from RESTRICTED_BIN.
        if [ -n "$REAL_JQ" ] && [ ! -e "$RESTRICTED_BIN/jq" ] && [ "$dangling" -eq 0 ]; then
            rc=0
            out="$(PATH="$RESTRICTED_BIN" "$WRAP_SH" test-session 2>&1)" || rc=$?
            if [ "$rc" -eq 1 ]; then
                pass "AT-13 (D7): wrap.sh exits 1 when a required binary is missing from PATH"
            else
                fail "AT-13 (D7): wrap.sh did not exit 1 on missing binary (rc=$rc, out=$out)"
            fi
        else
            fail "AT-13 (D7): restricted PATH fixture is unsound (dangling=$dangling, host jq resolved=${REAL_JQ:-none})"
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

    # Assert non-aborting execution format so exit 2 does not abort the turn
    if grep -qE '(\|\| true|wrap\.sh.*\|\|)' "$CLAUDE_DOOR"; then
        pass "AT-14 (D8): .claude/commands/wrap.md uses non-aborting execution format"
    else
        fail "AT-14 (D8): .claude/commands/wrap.md lacks non-aborting execution format"
    fi
else
    fail "AT-14 (D8): .claude/commands/wrap.md file does not exist"
fi

# Assert the CI compiler roundtrip gate checks Claude door tracking
if grep -q '\.claude/commands/wrap\.md' "$REPO/scripts/ci/compiler_roundtrip.sh" 2>/dev/null; then
    pass "AT-14 (D8): scripts/ci/compiler_roundtrip.sh validates Claude door tracking"
else
    fail "AT-14 (D8): scripts/ci/compiler_roundtrip.sh missing Claude door tracking check"
fi

# --- AT-15 (D10, D15): Living spec upsert, checklist obligation, CI gate ------
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
    seed_session_state
    (
        cd "$PRIMARY_REPO" || exit 1
        export PATH="$SANDBOX_BIN:$PATH"
        # C3: my-seat is an established seat in this sandbox, evidenced by a
        # prior-day handoff, so the supplied seat token resolves by exact match.
        echo "prior snapshot" > "ops/handoffs/handoff-my-seat-${PRIOR_DATE}.txt"
        rc=0
        out="$("$WRAP_SH" test-session my-seat --snapshot 2>&1)" || rc=$?
        handoff_file="ops/handoffs/handoff-my-seat-${TODAY}.txt"
        if [ "$rc" -eq 0 ] && [ -f "$handoff_file" ]; then
            first_line="$(head -n 1 "$handoff_file")"
            if grep -qE '^SNAPSHOT \(session still running, written [0-9]{2}:[0-9]{2}Z\)' <<<"$first_line"; then
                pass "AT-16 (D11): handoff file line 1 matches SNAPSHOT marker"
            else
                fail "AT-16 (D11): handoff file line 1 does not match SNAPSHOT marker (got: $first_line)"
            fi

            # A second snapshot in the same session overwrites in place without
            # incrementing the suffix, so only one file bears today's date.
            rc=0
            out2="$("$WRAP_SH" test-session my-seat --snapshot 2>&1)" || rc=$?
            count="$(find ops/handoffs -maxdepth 1 -name "handoff-my-seat-${TODAY}*.txt" 2>/dev/null | wc -l)"
            if [ "$rc" -eq 0 ] && [ "$count" -eq 1 ]; then
                pass "AT-16 (D11): repeated snapshot overwrites in place without incrementing suffix count"
            else
                fail "AT-16 (D11): repeated snapshot failed in-place overwrite (count=$count, rc=$rc, out=$out2)"
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
    # C1: the only test that keeps the pristine sandbox. No seed_session_state.
    setup_sandbox
    (
        cd "$PRIMARY_REPO" || exit 1
        export PATH="$SANDBOX_BIN:$PATH"
        export WRAP_LEARNINGS="none"
        rc=0
        out="$("$WRAP_SH" test-session 2>&1)" || rc=$?
        file_count="$(find ops/handoffs -maxdepth 1 -type f 2>/dev/null | wc -l)"
        if [ "$rc" -eq 0 ] \
           && grep -q "nothing to hand off: session clean and produced no state" <<<"$out" \
           && [ "$file_count" -eq 0 ]; then
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
    seed_session_state
    (
        cd "$PRIMARY_REPO" || exit 1
        export PATH="$SANDBOX_BIN:$PATH"
        echo "prior snapshot" > "ops/handoffs/handoff-my-seat-${PRIOR_DATE}.txt"
        : > "$CALLS_LOG"
        rc=0
        out="$("$WRAP_SH" test-session my-seat --snapshot 2>&1)" || rc=$?

        # Probes D12(b) gates under --snapshot: git fetch, gh pr list, worktrees.sh
        network_git="$(count_calls '^git fetch')"
        network_gh="$(count_calls '^gh pr list')"
        wt_calls="$(count_calls '^worktrees\.sh')"
        total_gated=$((network_git + network_gh + wt_calls))
        # C4 (R1-2): the cheap probe D12(a) mandates in BOTH modes is the
        # control that proves the shim log is live. Without it a zero count
        # carries no information.
        control="$(count_calls '^git status')"

        if [ "$rc" -eq 0 ] && [ "$control" -gt 0 ] && [ "$total_gated" -eq 0 ]; then
            pass "AT-18 (D12): wrap.sh gates network and worktree probes under --snapshot (gated: 0, control git status calls: $control)"
        else
            fail "AT-18 (D12): probe gating unproven under --snapshot (git_fetch=$network_git, gh_pr=$network_gh, wt=$wt_calls, control_git_status=$control, rc=$rc, out=$out)"
        fi
    )
fi

# --- AT-19 (D13): Seat resolution order, resume block, and pointers -----------
banner "AT-19 (D13): Seat resolution order, resume block, and pointers"
if [ ! -x "$WRAP_SH" ]; then
    fail "AT-19 (D13): $WRAP_SH does not exist or is not executable"
else
    setup_sandbox
    seed_session_state
    (
        cd "$PRIMARY_REPO" || exit 1
        export PATH="$SANDBOX_BIN:$PATH"
        export WRAP_LEARNINGS="none"

        # Case 5 (AT-R1-1, D13 no fallback): an ad-hoc slug matching neither a
        # standing seat nor an existing handoff refuses. Run first, against an
        # empty ops/handoffs, so no fixture can make it resolve.
        rm -f ops/handoffs/*.txt
        rc=0
        out_typo="$("$WRAP_SH" test-session non-existent-adhoc 2>&1)" || rc=$?
        typo_refused=0
        if [ "$rc" -eq 2 ] && grep -qi "refused" <<<"$out_typo"; then
            typo_refused=1
        fi

        # Case 4 (D13 step 4): no seat token anywhere, so wrap.sh mints a
        # kebab-case slug and writes that seat's handoff.
        rm -f ops/handoffs/*.txt
        rc=0
        out_mint="$(unset CLAUDE_SEAT; "$WRAP_SH" test-session 2>&1)" || rc=$?
        minted=0
        if [ "$rc" -eq 0 ] && grep -qE "resume:[[:space:]]+ops/waves/seat\.sh [a-z0-9]+(-[a-z0-9]+)*$" <<<"$out_mint"; then
            minted=1
        fi

        # Case 1 (D13 step 1): the CLI argument wins over $CLAUDE_SEAT. Both
        # seats are established by prior-day handoffs, so only precedence is
        # under test.
        rm -f ops/handoffs/*.txt
        echo "prior" > "ops/handoffs/handoff-custom-seat-${PRIOR_DATE}.txt"
        echo "prior" > "ops/handoffs/handoff-env-seat-${PRIOR_DATE}.txt"
        rc=0
        out_arg="$(CLAUDE_SEAT=env-seat "$WRAP_SH" test-session custom-seat 2>&1)" || rc=$?
        has_arg_resume=0
        if [ "$rc" -eq 0 ] && grep -qE "resume:[[:space:]]+ops/waves/seat\.sh custom-seat$" <<<"$out_arg"; then
            has_arg_resume=1
        fi

        # Case 2 (D13 step 2): $CLAUDE_SEAT resolves when no argument is given.
        rm -f ops/handoffs/*.txt
        echo "prior" > "ops/handoffs/handoff-env-seat-${PRIOR_DATE}.txt"
        rc=0
        out_env="$(CLAUDE_SEAT=env-seat "$WRAP_SH" test-session 2>&1)" || rc=$?
        has_env_resume=0
        if [ "$rc" -eq 0 ] && grep -qE "resume:[[:space:]]+ops/waves/seat\.sh env-seat$" <<<"$out_env"; then
            has_env_resume=1
        fi

        # Case 3 (D13 step 3): today's handoff written by this session resolves
        # the seat when neither an argument nor $CLAUDE_SEAT is supplied.
        rm -f ops/handoffs/*.txt
        printf '%s\n' "closed" "session: test-session" > "ops/handoffs/handoff-prior-seat-${TODAY}.txt"
        rc=0
        out_prior="$(unset CLAUDE_SEAT; "$WRAP_SH" test-session 2>&1)" || rc=$?
        has_prior_resume=0
        if [ "$rc" -eq 0 ] && grep -qE "resume:[[:space:]]+ops/waves/seat\.sh prior-seat$" <<<"$out_prior"; then
            has_prior_resume=1
        fi

        # Terminating output format (D13): absolute handoff path, seat.sh
        # pointers, and the session line of the resume block.
        has_abs_path=0
        if grep -qE "handoff:[[:space:]]+/.+/ops/handoffs/handoff-" <<<"$out_arg"; then
            has_abs_path=1
        fi
        has_pointers=0
        if grep -q "ops/waves/seat.sh --list" <<<"$out_arg" && grep -q "ops/waves/seat.sh --last" <<<"$out_arg"; then
            has_pointers=1
        fi
        has_session_line=0
        if grep -qE "^session:[[:space:]]+[^[:space:]]+" <<<"$out_arg"; then
            has_session_line=1
        fi

        if [ "$has_arg_resume" -eq 1 ] && [ "$has_env_resume" -eq 1 ] \
           && [ "$has_prior_resume" -eq 1 ] && [ "$minted" -eq 1 ] \
           && [ "$typo_refused" -eq 1 ] && [ "$has_abs_path" -eq 1 ] \
           && [ "$has_pointers" -eq 1 ] && [ "$has_session_line" -eq 1 ]; then
            pass "AT-19 (D13): all four seat resolution paths, ad-hoc refusal, resume block format, and pointers verified"
        else
            fail "AT-19 (D13): failed seat resolution or resume report (arg=$has_arg_resume, env=$has_env_resume, existing=$has_prior_resume, minted=$minted, typo=$typo_refused, abs=$has_abs_path, ptr=$has_pointers, session=$has_session_line)"
        fi
    )
fi

# --- Summary ------------------------------------------------------------------
banner "Wrap Contract Test Summary"
FAILURES=$(wc -l < "$FAIL_LOG" 2>/dev/null | tr -d ' ')
FAILURES="${FAILURES:-0}"
if [ "$FAILURES" -gt 0 ]; then
    echo "Total contract test failures: $FAILURES (EXPECTED RED at build rung)" >&2
    exit 1
fi

echo "ALL TESTS PASSED"
exit 0
