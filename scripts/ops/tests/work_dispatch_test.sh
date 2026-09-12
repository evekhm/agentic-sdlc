#!/usr/bin/env bash
# Tests for scripts/ops/work_dispatch.sh (#441).
#
#   bash scripts/ops/tests/work_dispatch_test.sh
#
# Hermetic, fixture-tree technique from work_test.sh: work_dispatch.sh
# resolves its sibling scripts (resolve_work_target.sh, digest.sh,
# claim.sh, work.sh) by absolute path from its own location, so PATH
# cannot stub them; a whole scratch REPO_ROOT with stub siblings can.
# Only work_dispatch.sh itself is the real file under test; its
# siblings are one-line loggers so each scenario asserts exactly which
# ones ran, and in what mode.
#
# Exit 0 with a PASS line per assertion, non-zero on the first failure.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
REAL_DISPATCH="$REPO/scripts/ops/work_dispatch.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass() { echo "PASS: $*" >&2; }
fail() { echo "FAIL: $*" >&2; exit 1; }

FIXTURE="$WORK/fixture/scripts/ops"
mkdir -p "$FIXTURE"
cp "$REAL_DISPATCH" "$FIXTURE/work_dispatch.sh"
chmod +x "$FIXTURE/work_dispatch.sh"
DISPATCH="$FIXTURE/work_dispatch.sh"
CALLS="$WORK/calls.log"
: > "$CALLS"
export CALLS

# --- stub siblings, one-line loggers ---------------------------------------
# resolve_work_target.sh: RESOLVE_OUT / RESOLVE_RC drive its behaviour.
cat > "$FIXTURE/resolve_work_target.sh" <<'STUB'
#!/usr/bin/env bash
echo "resolve_work_target.sh $*" >> "$CALLS"
printf '%s' "${RESOLVE_OUT:-99}"
exit "${RESOLVE_RC:-0}"
STUB

cat > "$FIXTURE/digest.sh" <<'STUB'
#!/usr/bin/env bash
echo "digest.sh $*" >> "$CALLS"
echo "digest: #$1 stub"
STUB

cat > "$FIXTURE/claim.sh" <<'STUB'
#!/usr/bin/env bash
echo "claim.sh $*" >> "$CALLS"
echo "claimed #$1"
STUB

cat > "$FIXTURE/work.sh" <<'STUB'
#!/usr/bin/env bash
echo "work.sh HEADLESS=${HEADLESS:-} $*" >> "$CALLS"
echo "WORK-RESULT: ok #$1 stub launch"
STUB

chmod +x "$FIXTURE/resolve_work_target.sh" "$FIXTURE/digest.sh" "$FIXTURE/claim.sh" "$FIXTURE/work.sh"

export GITHUB_REPO="test/repo"

# --- stub gh, for the already-claimed check in the non-yolo path -----------
mkdir -p "$WORK/bin"
cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
if [ "$1 $2" = "issue view" ]; then
    printf '%s' "${ALREADY_CLAIMED:-null}"
    exit 0
fi
echo "stub gh: unexpected call: $*" >&2
exit 1
STUB
chmod +x "$WORK/bin/gh"
export PATH="$WORK/bin:$PATH"

reset_calls() { : > "$CALLS"; }

# --- 1. bare dispatch: resolves, digests, claims (not yet claimed) ---------
reset_calls
rc=0; out="$(RESOLVE_OUT=7 ALREADY_CLAIMED=null "$DISPATCH" 2>&1)" || rc=$?
[ "$rc" -eq 0 ] || fail "bare: expected exit 0, got $rc -- $out"
grep -q '^resolve_work_target.sh $' "$CALLS" || fail "bare: resolver not called with no args -- $(cat "$CALLS")"
grep -q '^digest.sh 7$' "$CALLS" || fail "bare: digest.sh not called with resolved number -- $(cat "$CALLS")"
grep -q '^claim.sh 7$' "$CALLS" || fail "bare: claim.sh not called -- $(cat "$CALLS")"
grep -q '^work.sh ' "$CALLS" && fail "bare: work.sh must never run without --yolo -- $(cat "$CALLS")"
pass "bare dispatch resolves, digests, and claims an unclaimed issue"

# --- 2. bare dispatch: already claimed -> claim.sh is skipped --------------
reset_calls
rc=0; out="$(RESOLVE_OUT=7 ALREADY_CLAIMED=1 "$DISPATCH" 2>&1)" || rc=$?
[ "$rc" -eq 0 ] || fail "already claimed: expected exit 0, got $rc -- $out"
grep -q '^claim.sh' "$CALLS" && fail "already claimed: claim.sh must not run -- $(cat "$CALLS")"
echo "$out" | grep -q 'already carries in-progress' || fail "already claimed: missing notice -- $out"
pass "an already-claimed issue is not reclaimed"

# --- 3. explicit argument reaches the resolver ------------------------------
reset_calls
"$DISPATCH" 42 >/dev/null 2>&1 || true
grep -q '^resolve_work_target.sh 42$' "$CALLS" || fail "explicit arg: resolver not called with '42' -- $(cat "$CALLS")"
pass "an explicit numeric argument is forwarded to the resolver"

# --- 4. NEEDS_PICK (resolver exit 3) is relayed, work.sh never runs --------
reset_calls
rc=0; out="$(RESOLVE_OUT="NEEDS_PICK
9	Nine" RESOLVE_RC=3 "$DISPATCH" 2>&1)" || rc=$?
[ "$rc" -eq 3 ] || fail "needs pick: expected exit 3, got $rc -- $out"
echo "$out" | grep -q '^NEEDS_PICK$' || fail "needs pick: header not relayed -- $out"
echo "$out" | grep -q '^9	Nine$' || fail "needs pick: candidate not relayed -- $out"
grep -q '^digest.sh' "$CALLS" && fail "needs pick: digest.sh must not run -- $(cat "$CALLS")"
grep -q '^claim.sh' "$CALLS" && fail "needs pick: claim.sh must not run -- $(cat "$CALLS")"
pass "a resolver NEEDS_PICK is relayed verbatim, exit 3, nothing else runs"

# --- 5. --yolo: resolves, then hands straight to work.sh HEADLESS=1 -------
reset_calls
rc=0; out="$(RESOLVE_OUT=7 "$DISPATCH" --yolo 2>&1)" || rc=$?
[ "$rc" -eq 0 ] || fail "yolo: expected exit 0, got $rc -- $out"
grep -q '^work.sh HEADLESS=1 7$' "$CALLS" || fail "yolo: work.sh not called headless with '7' -- $(cat "$CALLS")"
grep -q '^digest.sh' "$CALLS" && fail "yolo: digest.sh must not run in --yolo mode -- $(cat "$CALLS")"
grep -q '^claim.sh' "$CALLS" && fail "yolo: claim.sh must not run in --yolo mode (work.sh owns its own claim) -- $(cat "$CALLS")"
pass "--yolo resolves and dispatches straight to headless work.sh, unchanged from before #441"

# --- 6. --as <persona> is forwarded to work.sh in --yolo mode -------------
reset_calls
RESOLVE_OUT=7 "$DISPATCH" 7 --yolo --as athena >/dev/null 2>&1 || true
grep -q '^work.sh HEADLESS=1 7 --as athena$' "$CALLS" || fail "as passthrough: work.sh not called with --as athena -- $(cat "$CALLS")"
pass "--as <persona> reaches work.sh under --yolo"

# --- 7. a non-numeric, non-flag token is refused, exit 1 -------------------
reset_calls
rc=0; out="$("$DISPATCH" a-description-not-a-number 2>&1)" || rc=$?
[ "$rc" -eq 1 ] || fail "bad token: expected exit 1, got $rc -- $out"
grep -q '^resolve_work_target.sh' "$CALLS" && fail "bad token: resolver must not run on unusable input -- $(cat "$CALLS")"
pass "a free-text token is refused before the resolver runs, exit 1"

# --- 8. two numbers in one call is refused, exit 1 --------------------------
rc=0; out="$("$DISPATCH" 7 8 2>&1)" || rc=$?
[ "$rc" -eq 1 ] || fail "two numbers: expected exit 1, got $rc -- $out"
pass "more than one number in a single dispatch is refused"

echo "work_dispatch_test.sh: all assertions passed" >&2
