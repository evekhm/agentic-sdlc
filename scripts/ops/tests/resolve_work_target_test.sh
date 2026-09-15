#!/usr/bin/env bash
# Tests for scripts/ops/resolve_work_target.sh (#441).
#
#   bash scripts/ops/tests/resolve_work_target_test.sh
#
# Hermetic, same stubbing technique as digest_test.sh / work_test.sh:
# stub `gh` and `git` first on PATH answer every call from env-controlled
# fixtures; an unrecognised call is a loud failure rather than a silent
# one. The state-file directory is a scratch dir per scenario, never the
# operator's real home directory's .claude/context.
#
# Exit 0 with a PASS line per assertion, non-zero on the first failure.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
RESOLVE="$REPO/scripts/ops/resolve_work_target.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass() { echo "PASS: $*" >&2; }
fail() { echo "FAIL: $*" >&2; exit 1; }

mkdir -p "$WORK/bin" "$WORK/ctx"
export GITHUB_REPO="test/repo"
export AGENTIC_CTX_DIR="$WORK/ctx"

# --- stub git ---------------------------------------------------------------
# BRANCH controls `git branch --show-current`; empty means detached/none.
cat > "$WORK/bin/git" <<'STUB'
#!/usr/bin/env bash
if [ "$1 $2" = "branch --show-current" ]; then
    printf '%s\n' "${BRANCH:-}"
    exit 0
fi
echo "stub git: unexpected call: $*" >&2
exit 1
STUB
chmod +x "$WORK/bin/git"

# --- stub gh ------------------------------------------------------------
# ISSUE_STATE controls `gh issue view <n> --json state -q '.state'`.
cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
case "$1 $2" in
    "issue view")
        # real `gh ... -q '.state'` unwraps to the bare value; match that.
        printf '%s\n' "${ISSUE_STATE:-OPEN}"
        exit 0
        ;;
    "issue list")
        # real `gh ... --jq '...'` applies the filter itself; match its
        # output directly rather than the raw --json payload.
        printf '9\tNine\n5\tFive\n'
        exit 0
        ;;
    *)
        echo "stub gh: unexpected call: $*" >&2
        exit 1
        ;;
esac
STUB
chmod +x "$WORK/bin/gh"
export PATH="$WORK/bin:$PATH"

# --- 1. explicit argument wins, even with a branch that would resolve too --
rc=0; out="$(BRANCH="eva/9-something" CLAUDE_CODE_SESSION_ID="s1" "$RESOLVE" 7 2>/dev/null)" || rc=$?
[ "$rc" -eq 0 ] || fail "explicit arg: expected exit 0, got $rc"
[ "$out" = "7" ] || fail "explicit arg: expected '7', got '$out'"
pass "explicit argument wins over branch"

# --- 2. bad explicit argument exits 1 ---------------------------------------
rc=0; out="$("$RESOLVE" abc 2>/dev/null)" || rc=$?
[ "$rc" -eq 1 ] || fail "bad arg: expected exit 1, got $rc (out: $out)"
pass "non-numeric explicit argument exits 1"

# --- 3. current worktree branch resolves when no explicit argument ----------
rc=0; out="$(BRANCH="eva/441-work-optional-issue-number" CLAUDE_CODE_SESSION_ID="s2" "$RESOLVE" 2>/dev/null)" || rc=$?
[ "$rc" -eq 0 ] || fail "branch: expected exit 0, got $rc"
[ "$out" = "441" ] || fail "branch: expected '441', got '$out'"
pass "current worktree branch resolves the number"

# --- 4. no branch match, session state file names an open issue ------------
SID="s3-$$"
printf '12\n' > "$WORK/ctx/${SID}.work-last-issue"
rc=0; out="$(BRANCH="" ISSUE_STATE="OPEN" CLAUDE_CODE_SESSION_ID="$SID" "$RESOLVE" 2>/dev/null)" || rc=$?
[ "$rc" -eq 0 ] || fail "session state: expected exit 0, got $rc"
[ "$out" = "12" ] || fail "session state: expected '12', got '$out'"
pass "last issue this session touched resolves when still open"

# --- 5. session state names a CLOSED issue -> falls through to NEEDS_PICK ---
SID="s4-$$"
printf '12\n' > "$WORK/ctx/${SID}.work-last-issue"
rc=0; out="$(BRANCH="" ISSUE_STATE="CLOSED" CLAUDE_CODE_SESSION_ID="$SID" "$RESOLVE" 2>/dev/null)" || rc=$?
[ "$rc" -eq 3 ] || fail "closed session state: expected exit 3, got $rc"
echo "$out" | grep -q '^NEEDS_PICK$' || fail "closed session state: missing NEEDS_PICK header -- got:\n$out"
pass "a closed session-state issue is not reused; falls through to a pick"

# --- 6. nothing resolves -> NEEDS_PICK with candidates ----------------------
SID="s5-$$"
rc=0; out="$(BRANCH="" CLAUDE_CODE_SESSION_ID="$SID" "$RESOLVE" 2>/dev/null)" || rc=$?
[ "$rc" -eq 3 ] || fail "no resolution: expected exit 3, got $rc"
echo "$out" | grep -q '^NEEDS_PICK$' || fail "no resolution: missing NEEDS_PICK header -- got:\n$out"
echo "$out" | grep -q '^9	Nine$' || fail "no resolution: missing candidate '9\\tNine' -- got:\n$out"
pass "no resolution prints NEEDS_PICK and the candidate list, exit 3"

# --- 7. a successful resolution records the state file for next time -------
SID="s6-$$"
BRANCH="eva/23-thing" CLAUDE_CODE_SESSION_ID="$SID" "$RESOLVE" >/dev/null 2>&1
[ "$(cat "$WORK/ctx/${SID}.work-last-issue" 2>/dev/null)" = "23" ] \
    || fail "state write: expected state file to record '23'"
pass "a successful resolution records the state file for the next bare call"

echo "resolve_work_target_test.sh: all assertions passed" >&2
