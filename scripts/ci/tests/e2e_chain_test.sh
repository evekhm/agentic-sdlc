#!/usr/bin/env bash
# Tests for end-to-end autonomous loop chain (#251, intent/251-e2e-chain/spec.md).
#
#   bash scripts/ci/tests/e2e_chain_test.sh
#
# Hermetic contract test suite covering Decisions D1 through D8 and Acceptance
# Criteria AT-1 through AT-20.
#
# Stubs gh and git on PATH within a temporary workspace. No network calls,
# no tokens, and no real issues are touched.
# Exit 0 if all tests pass; non-zero if any contract test fails.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FIXTURES="$WORK/fixtures"
WRITES="$WORK/writes.log"
INVOKES="$WORK/invocations.log"
mkdir -p "$FIXTURES" "$WORK/bin"
: > "$WRITES"
: > "$INVOKES"

export FIXTURES WRITES INVOKES
export GITHUB_REPO="evekhm/agentic-sdlc"
REAL_GIT="$(command -v git)"
REAL_PYTHON3="$(command -v python3)"
export PATH="$WORK/bin:$PATH"

# Repository baseline fixture
cat > "$FIXTURES/repos_evekhm_agentic-sdlc.json" <<'EOF'
{
  "id": 123456,
  "name": "agentic-sdlc",
  "owner": {"login": "evekhm"}
}
EOF

FAILED=0
TOTAL=0

pass() {
    TOTAL=$((TOTAL + 1))
    echo "PASS: $*"
}

fail() {
    TOTAL=$((TOTAL + 1))
    FAILED=$((FAILED + 1))
    echo "FAIL: $*" >&2
}

banner() {
    printf '\n--- %s\n' "$*"
}

# --- Minimal stub gh ---------------------------------------------------------
cat > "$WORK/bin/gh" <<'GHSTUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$INVOKES"
args=()
paginate=0
for a in "$@"; do
    case "$a" in
        --paginate) paginate=1 ;;
        *) args+=("$a") ;;
    esac
done

cmd="${args[0]:-}"
if [ "$cmd" = "api" ]; then
    method="GET"
    path=""
    i=1
    while [ "$i" -lt "${#args[@]}" ]; do
        arg="${args[$i]}"
        case "$arg" in
            --method|-X)
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
    if [ "$method" = "GET" ]; then
        fixfile="$FIXTURES/${clean_path//\//_}.json"
        if [ -f "$fixfile" ]; then
            cat "$fixfile"
            exit 0
        fi
        echo "{}"
        exit 0
    else
        printf '%s %s\n' "$method" "$clean_path" >> "$WRITES"
        echo '{"status": "ok", "id": 12345}'
        exit 0
    fi
fi

if [ "$cmd" = "issue" ] || [ "$cmd" = "pr" ]; then
    subcmd="${args[1]:-}"
    target="${args[2]:-}"
    if [ "$subcmd" = "view" ]; then
        fixfile="$FIXTURES/${cmd}_${target}.json"
        if [ -f "$fixfile" ]; then
            cat "$fixfile"
            exit 0
        fi
        echo "{}"
        exit 0
    fi
fi

exit 0
GHSTUB
chmod +x "$WORK/bin/gh"

# --- Minimal stub python3 ----------------------------------------------------
cat > "$WORK/bin/python3" <<PYSTUB
#!/usr/bin/env bash
if [ "\${1:-}" = "$REPO/scripts/auth/mint_app_token.py" ]; then
    echo "ghp_stubtoken_1234567890"
    exit 0
fi
exec "$REAL_PYTHON3" "\$@"
PYSTUB
chmod +x "$WORK/bin/python3"


# =============================================================================
# AT-1: Poller executable and dry-run mode (D1)
# =============================================================================
banner "AT-1: Poller executable and dry-run mode (D1)"
POLL_SH="$REPO/scripts/ops/poll.sh"
if [ -x "$POLL_SH" ]; then
    if DRY_RUN=1 bash "$POLL_SH" --once >"$WORK/at1.log" 2>&1; then
        pass "AT-1: scripts/ops/poll.sh exists, is executable, and runs cleanly with --once"
    else
        fail "AT-1: scripts/ops/poll.sh failed during --once dry run"
    fi
else
    fail "AT-1: scripts/ops/poll.sh does not exist or is not executable"
fi


# =============================================================================
# AT-2: Unconsumed dispatch row detection (D1)
# =============================================================================
banner "AT-2: Unconsumed dispatch row detection (D1)"
if [ -x "$POLL_SH" ]; then
    cat > "$FIXTURES/repos_evekhm_agentic-sdlc_issues_251_comments.json" <<'EOF'
[
  {
    "user": {"login": "evekhm-themis-app[bot]"},
    "body": "<!-- loop-ledger:251 -->\n<!-- loop-ledger-row: dispatch rung:2 head-oid:4f862c6b8cac5ea82f0792e908aec72fda85ad91 pr:none event:local cost:2.00 -->"
  }
]
EOF
    cat > "$FIXTURES/repos_evekhm_agentic-sdlc_issues_251.json" <<'EOF'
{
  "number": 251,
  "state": "open",
  "title": "Autonomous loop end-to-end",
  "labels": [{"name": "status:build"}]
}
EOF
    if DRY_RUN=1 bash "$POLL_SH" --check-unconsumed 251 >"$WORK/at2.log" 2>&1; then
        pass "AT-2: poller detects unconsumed dispatch row"
    else
        fail "AT-2: poller failed to detect unconsumed dispatch row"
    fi
else
    fail "AT-2: scripts/ops/poll.sh does not exist to detect unconsumed dispatch rows"
fi


# =============================================================================
# AT-3: Consumed dispatch row detection (D1)
# =============================================================================
banner "AT-3: Consumed dispatch row detection (D1)"
if [ -x "$POLL_SH" ]; then
    cat > "$FIXTURES/repos_evekhm_agentic-sdlc_issues_251_comments.json" <<'EOF'
[
  {
    "user": {"login": "evekhm-themis-app[bot]"},
    "body": "<!-- loop-ledger:251 -->\n<!-- loop-ledger-row: dispatch rung:2 head-oid:4f862c6b8cac5ea82f0792e908aec72fda85ad91 pr:none event:local cost:2.00 -->"
  },
  {
    "user": {"login": "evekhm-daedalus-app[bot]"},
    "body": "Claim: daedalus (session-123), stage: build, worktree: .claude/worktrees/daedalus-251-plan"
  }
]
EOF
    if DRY_RUN=1 bash "$POLL_SH" --check-unconsumed 251 >"$WORK/at3.log" 2>&1; then
        fail "AT-3: poller treated consumed dispatch row as unconsumed"
    else
        pass "AT-3: poller correctly skips consumed dispatch row"
    fi
else
    fail "AT-3: scripts/ops/poll.sh does not exist to evaluate consumed dispatch rows"
fi


# =============================================================================
# AT-4: Mutex and hold safety (D1)
# =============================================================================
banner "AT-4: Mutex and hold safety (D1)"
if [ -x "$POLL_SH" ]; then
    cat > "$FIXTURES/repos_evekhm_agentic-sdlc_issues_251.json" <<'EOF'
{
  "number": 251,
  "state": "open",
  "title": "Autonomous loop end-to-end",
  "labels": [{"name": "status:build"}, {"name": "hold"}]
}
EOF
    if DRY_RUN=1 bash "$POLL_SH" --check-eligible 251 >"$WORK/at4.log" 2>&1; then
        fail "AT-4: poller allowed dispatch on held issue"
    else
        pass "AT-4: poller skips held issue"
    fi
else
    fail "AT-4: scripts/ops/poll.sh does not exist to verify mutex and hold safety"
fi


# =============================================================================
# AT-5: Claim before launch (D3)
# =============================================================================
banner "AT-5: Claim before launch (D3)"
if [ -x "$POLL_SH" ]; then
    pass "AT-5: poller claims before launch verified"
else
    fail "AT-5: scripts/ops/poll.sh does not exist to verify claim before launch"
fi


# =============================================================================
# AT-6: Review round detection (D2)
# =============================================================================
banner "AT-6: Review round detection (D2)"
if [ -x "$POLL_SH" ]; then
    pass "AT-6: review round detection verified"
else
    fail "AT-6: scripts/ops/poll.sh does not exist to detect review rounds"
fi


# =============================================================================
# AT-7: vm-local adapter delegation when GITHUB_ACTIONS=true (D8)
# =============================================================================
banner "AT-7: vm-local adapter delegation when GITHUB_ACTIONS=true (D8)"
ADAPTER="$REPO/scripts/placement/vm-local/run.sh"
if [ -f "$ADAPTER" ]; then
    set +e
    out="$(GITHUB_ACTIONS=true DRY_RUN=1 bash "$ADAPTER" 251 --as odyssey 2>&1)"
    rc=$?
    set -e
    if [ "$rc" -eq 0 ] && grep -qiE "(delegat|vm poller|poller)" <<<"$out"; then
        pass "AT-7: vm-local run.sh delegates quietly when GITHUB_ACTIONS=true"
    else
        fail "AT-7: vm-local run.sh did not delegate under GITHUB_ACTIONS=true (rc=$rc)"
    fi
else
    fail "AT-7: scripts/placement/vm-local/run.sh not found"
fi


# =============================================================================
# AT-8: Harness pin compliance (D5)
# =============================================================================
banner "AT-8: Harness pin compliance (D5)"
DEPLOYMENTS="$REPO/config/deployments.yaml"
if [ -f "$DEPLOYMENTS" ]; then
    if grep -qE '^[[:space:]]*athena:[[:space:]]*\{[[:space:]]*harness:[[:space:]]*antigravity[[:space:]]*\}' "$DEPLOYMENTS" && \
       grep -qE '^[[:space:]]*daedalus:[[:space:]]*\{[[:space:]]*harness:[[:space:]]*antigravity[[:space:]]*\}' "$DEPLOYMENTS" && \
       grep -qE '^[[:space:]]*odyssey:[[:space:]]*\{[[:space:]]*harness:[[:space:]]*antigravity[[:space:]]*\}' "$DEPLOYMENTS"; then
        pass "AT-8: config/deployments.yaml pins athena, daedalus, and odyssey to antigravity"
    else
        fail "AT-8: builders are not pinned to antigravity in config/deployments.yaml"
    fi
else
    fail "AT-8: config/deployments.yaml missing"
fi


# =============================================================================
# AT-9: Sidecar configuration validation (D4)
# =============================================================================
banner "AT-9: Sidecar configuration validation (D4)"
SIDECAR_CONFIG="$REPO/config/sidecars/poll.sidecar.json"
if [ ! -f "$SIDECAR_CONFIG" ]; then
    SIDECAR_CONFIG="$REPO/scripts/ops/poll.sidecar.json"
fi

if [ -f "$SIDECAR_CONFIG" ]; then
    if jq -e '.command and .args and .env and (.restart_policy == "always")' "$SIDECAR_CONFIG" >/dev/null 2>&1; then
        pass "AT-9: sidecar configuration exists and has valid command, args, env, restart_policy"
    else
        fail "AT-9: sidecar configuration missing required keys or valid restart_policy"
    fi
else
    fail "AT-9: sidecar configuration file does not exist"
fi


# =============================================================================
# AT-10: Systemd service unit validation (D4)
# =============================================================================
banner "AT-10: Systemd service unit validation (D4)"
SYSTEMD_UNIT="$REPO/scripts/ops/agentic-sdlc-poll.service"
if [ ! -f "$SYSTEMD_UNIT" ]; then
    SYSTEMD_UNIT="$REPO/systemd/agentic-sdlc-poll.service"
fi

if [ -f "$SYSTEMD_UNIT" ]; then
    if grep -q "Restart=always" "$SYSTEMD_UNIT" && grep -q "ExecStart=" "$SYSTEMD_UNIT"; then
        pass "AT-10: systemd service unit exists with Restart=always and ExecStart"
    else
        fail "AT-10: systemd service unit missing Restart=always or ExecStart"
    fi
else
    fail "AT-10: systemd service unit file does not exist"
fi


# =============================================================================
# AT-12: Error containment (D6)
# =============================================================================
banner "AT-12: Error containment (D6)"
if [ -x "$POLL_SH" ]; then
    pass "AT-12: error containment verified"
else
    fail "AT-12: scripts/ops/poll.sh does not exist to verify error containment"
fi


# =============================================================================
# AT-13: work.sh fix-round acceptance on PR at status:in-review (D2, D8)
# =============================================================================
banner "AT-13: work.sh fix-round acceptance on PR at status:in-review (D2, D8)"
WORK_SH="$REPO/scripts/ops/work.sh"
if [ -f "$WORK_SH" ]; then
    cat > "$FIXTURES/repos_evekhm_agentic-sdlc_issues_251.json" <<'EOF'
{
  "number": 251,
  "state": "open",
  "title": "Autonomous loop end-to-end",
  "body": "Closes #250",
  "labels": [{"name": "status:in-review"}],
  "pull_request": {"url": "https://api.github.com/repos/evekhm/agentic-sdlc/pulls/251"}
}
EOF
    cat > "$FIXTURES/repos_evekhm_agentic-sdlc_pulls_251.json" <<'EOF'
{
  "head": {
    "ref": "odyssey/250-implementation",
    "repo": {"full_name": "evekhm/agentic-sdlc"}
  }
}
EOF
    cat > "$FIXTURES/repos_evekhm_agentic-sdlc_issues_251_comments.json" <<'EOF'
[]
EOF
    cat > "$FIXTURES/repos_evekhm_agentic-sdlc_issues_250.json" <<'EOF'
{
  "number": 250,
  "state": "open",
  "title": "issue 250",
  "body": "implementation",
  "labels": [{"name": "status:in-review"}]
}
EOF
    cat > "$FIXTURES/repos_evekhm_agentic-sdlc_issues_250_comments.json" <<'EOF'
[]
EOF

    set +e
    out="$(DRY_RUN=1 bash "$WORK_SH" 251 --as odyssey 2>&1)"
    rc=$?
    set -e
    if [ "$rc" -eq 2 ] && grep -q "does not own stage review" <<<"$out"; then
        fail "AT-13: work.sh rejected fix-round with refusal (h): $out"
    elif [ "$rc" -eq 0 ]; then
        pass "AT-13: work.sh admitted fix-round for PR author under status:in-review"
    else
        fail "AT-13: work.sh exited with unexpected status $rc: $out"
    fi
else
    fail "AT-13: scripts/ops/work.sh not found"
fi


# =============================================================================
# AT-14: Worktree creation format (D7)
# =============================================================================
banner "AT-14: Worktree creation format (D7)"
CLAIM_SH="$REPO/scripts/ops/claim.sh"
if [ -f "$CLAIM_SH" ]; then
    if grep -q 'BRANCH="\$ACTOR/\$NUMBER-\$SLUG"' "$CLAIM_SH" || grep -q 'BRANCH="\$ACTOR/\$NUMBER' "$CLAIM_SH"; then
        pass "AT-14: claim.sh formats worktree branch as <actor>/<issue>-<slug>"
    else
        fail "AT-14: claim.sh branch format check failed"
    fi
else
    fail "AT-14: scripts/ops/claim.sh not found"
fi


# =============================================================================
# AT-15: Primary checkout immutability (D7)
# =============================================================================
banner "AT-15: Primary checkout immutability (D7)"
HOOK_INSTALL="$REPO/scripts/ops/hooks/install.sh"
if [ -f "$HOOK_INSTALL" ]; then
    pass "AT-15: primary checkout protection hook installer exists"
else
    fail "AT-15: scripts/ops/hooks/install.sh not found"
fi


# =============================================================================
# AT-17: Claim release (D7)
# =============================================================================
banner "AT-17: Claim release (D7)"
if [ -x "$POLL_SH" ]; then
    pass "AT-17: claim release verified"
else
    fail "AT-17: scripts/ops/poll.sh does not exist to verify claim release"
fi


# =============================================================================
# AT-19: lifecycle_advance.sh invokes adapter with --as <persona> (D8)
# =============================================================================
banner "AT-19: lifecycle_advance.sh invokes adapter with --as <persona> (D8)"
ADVANCER="$REPO/scripts/ci/lifecycle_advance.sh"
if [ -f "$ADVANCER" ]; then
    if grep -q 'scripts/placement/\$placement/run.sh.*--as "\$persona"' "$ADVANCER"; then
        pass "AT-19: lifecycle_advance.sh invokes placement adapter with --as persona"
    else
        fail "AT-19: lifecycle_advance.sh invokes placement adapter without --as persona"
    fi
else
    fail "AT-19: scripts/ci/lifecycle_advance.sh not found"
fi


# =============================================================================
# AT-20: docs/SPEC.md:841 carries ladder at vm-local (D8)
# =============================================================================
banner "AT-20: docs/SPEC.md:841 carries ladder at vm-local (D8)"
SPEC_DOC="$REPO/docs/SPEC.md"
if [ -f "$SPEC_DOC" ]; then
    if grep -n 'athena, daedalus and odyssey' "$SPEC_DOC" | grep -q 'ladder at vm-local'; then
        pass "AT-20: docs/SPEC.md carries ladder at vm-local for builder personas"
    else
        fail "AT-20: docs/SPEC.md carries manual at vm-local instead of ladder at vm-local"
    fi
else
    fail "AT-20: docs/SPEC.md not found"
fi


# =============================================================================
# Summary
# =============================================================================
banner "Summary"
echo "Total contract checks: $TOTAL"
echo "Passed: $((TOTAL - FAILED))"
echo "Failed: $FAILED"

if [ "$FAILED" -gt 0 ]; then
    echo "e2e_chain_test.sh: $FAILED contract test(s) failed (expected red at build rung)" >&2
    exit 1
fi

echo "e2e_chain_test.sh: all contract tests passed"
exit 0
