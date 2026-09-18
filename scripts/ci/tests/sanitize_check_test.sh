#!/usr/bin/env bash
# Contract test suite for scripts/ci/sanitize_check.sh rule 'marker' (#318).
# Validates Decision D6 and Acceptance Tests AT-318-10, AT-318-11.
#
# Hermetic: tests run in an isolated git repository sandbox.
# No network access, no GitHub API calls, no external credentials.
#
# At the build rung (Daedalus), before scripts/ci/sanitize_check.sh implements
# the 'marker' rule and allowlist support, running this suite reports failures
# (not syntax/runtime errors) and exits 1.
# During the implement rung (Odyssey), once the 'marker' rule is implemented,
# all contract assertions pass green and this suite exits 0.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../../.." && pwd)"
SANITIZE_CHECK="$REPO/scripts/ci/sanitize_check.sh"
ALLOWLIST_SRC="$REPO/scripts/ci/sanitize_allowlist.txt"

TOTAL=0
PASSED=0
FAILED=0

banner() { printf '\n=== %s ===\n' "$*"; }

pass() {
  echo "PASS: $*"
  PASSED=$((PASSED + 1))
  TOTAL=$((TOTAL + 1))
}

fail() {
  echo "FAIL: $*" >&2
  FAILED=$((FAILED + 1))
  TOTAL=$((TOTAL + 1))
}

# String assembly to avoid raw marker detection in test source
_O="<"; _O+="!--"
_C="--"; _C+=">"

setup_sandbox() {
  local dir="$1"
  rm -rf "$dir"
  mkdir -p "$dir/scripts/ci"
  git -C "$dir" init -q -b main
  git -C "$dir" config user.name "Contract Test"
  git -C "$dir" config user.email "contract-test@example.com"
  cp "$SANITIZE_CHECK" "$dir/scripts/ci/sanitize_check.sh"
  cp "$ALLOWLIST_SRC" "$dir/scripts/ci/sanitize_allowlist.txt"
}

# AT-318-10 (D6): Live review verdict marker in tracked file triggers rule 'marker' failure
test_marker_rule_fails_on_live_verdict_marker() {
  local sandbox
  sandbox="$(mktemp -d)"
  setup_sandbox "$sandbox"

  mkdir -p "$sandbox/docs"
  printf '%s review-verdict:argus:clean %s\n' "$_O" "$_C" > "$sandbox/docs/example.md"
  git -C "$sandbox" add scripts/ci docs/example.md
  git -C "$sandbox" commit -q -m "Add tracked doc with live marker"

  local out rc=0
  out="$(bash "$sandbox/scripts/ci/sanitize_check.sh" 2>&1)" || rc=$?

  rm -rf "$sandbox"

  [ "$rc" -eq 1 ] || {
    fail "test_marker_rule_fails_on_live_verdict_marker: sanitize_check.sh did not exit 1 on live verdict marker (D6, AT-318-10); rc=$rc"
    return 1
  }

  echo "$out" | grep -q "docs/example.md:1: unescaped live verdict marker" || {
    fail "test_marker_rule_fails_on_live_verdict_marker: missing 'unescaped live verdict marker' diagnostic reporting docs/example.md (D6, AT-318-10)"
    return 1
  }

  pass "test_marker_rule_fails_on_live_verdict_marker (D6, AT-318-10)"
}

# AT-318-11 (D6): Bracketed notation in documentation passes the marker scan with exit 0
test_bracketed_notation_passes_marker_rule() {
  local sandbox
  sandbox="$(mktemp -d)"
  setup_sandbox "$sandbox"

  mkdir -p "$sandbox/docs"
  cat > "$sandbox/docs/spec_example.md" <<'SUB_EOF'
# Specification Example
Here are the expected markers:
- [review-verdict:argus:clean]
- [reviewed-head:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa]
- [run-id:1234]
- [finding:R1-1:high:open:none]
- [failure-scenario:R1-1]
- [consensus-ledger:100]
SUB_EOF
  git -C "$sandbox" add scripts/ci docs/spec_example.md
  git -C "$sandbox" commit -q -m "Add bracketed doc notation"

  local out rc=0
  out="$(bash "$sandbox/scripts/ci/sanitize_check.sh" 2>&1)" || rc=$?

  rm -rf "$sandbox"

  [ "$rc" -eq 0 ] || {
    fail "test_bracketed_notation_passes_marker_rule: sanitize_check.sh failed on bracketed notation (D6, AT-318-11); rc=$rc, out: $out"
    return 1
  }

  echo "$out" | grep -q "PASS: sanitize gate green" || {
    fail "test_bracketed_notation_passes_marker_rule: sanitize_check.sh missing green pass banner (D6, AT-318-11)"
    return 1
  }

  pass "test_bracketed_notation_passes_marker_rule (D6, AT-318-11)"
}

# AT-318-10 (D6): Allowlisted file exempt from marker rule
test_marker_allowlist_exemption() {
  local sandbox
  sandbox="$(mktemp -d)"
  setup_sandbox "$sandbox"

  mkdir -p "$sandbox/tests"
  printf '%s review-verdict:argus:clean %s\n' "$_O" "$_C" > "$sandbox/tests/fixture.md"
  echo "marker tests/fixture.md  # allowed test fixture" >> "$sandbox/scripts/ci/sanitize_allowlist.txt"

  git -C "$sandbox" add scripts/ci tests/fixture.md
  git -C "$sandbox" commit -q -m "Add allowlisted fixture"

  local out rc=0
  out="$(bash "$sandbox/scripts/ci/sanitize_check.sh" 2>&1)" || rc=$?

  rm -rf "$sandbox"

  [ "$rc" -eq 0 ] || {
    fail "test_marker_allowlist_exemption: sanitize_check.sh failed on allowlisted marker file (D6, AT-318-10); rc=$rc, out: $out"
    return 1
  }

  pass "test_marker_allowlist_exemption (D6, AT-318-10)"
}

# AT-318-10 (D6): Comprehensive coverage of live marker forms (reviewed-head, run-id, round, finding, failure-scenario, consensus-ledger, loop-ledger, refused-verdict)
test_all_live_marker_variants_detected() {
  local sandbox
  sandbox="$(mktemp -d)"
  setup_sandbox "$sandbox"

  mkdir -p "$sandbox/docs"
  cat > "$sandbox/docs/markers.md" <<SUB_EOF
Line 1: ${_O} reviewed-head:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa ${_C}
Line 2: ${_O} run-id:1234 ${_C}
Line 3: ${_O} round:1 ${_C}
Line 4: ${_O} finding:R1-1:high:open:none ${_C}
Line 5: ${_O} failure-scenario:R1-1 ${_C}
Line 6: ${_O} consensus-ledger:100 ${_C}
Line 7: ${_O} consensus-ledger-end ${_C}
Line 8: ${_O} loop-ledger:100 ${_C}
Line 9: ${_O} loop-ledger-row: dispatch rung:1 head-oid:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa pr:100 at:2026-01-01T00:00:00Z cost:5.00 ${_C}
Line 10: ${_O} loop-ledger-end ${_C}
Line 11: ${_O} refused-verdict:argus:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa:author-mismatch ${_C}
Line 12: ${_O} review-verdict-end ${_C}
SUB_EOF

  git -C "$sandbox" add scripts/ci docs/markers.md
  git -C "$sandbox" commit -q -m "Add file with 12 marker variants"

  local out rc=0
  out="$(bash "$sandbox/scripts/ci/sanitize_check.sh" 2>&1)" || rc=$?

  rm -rf "$sandbox"

  [ "$rc" -eq 1 ] || {
    fail "test_all_live_marker_variants_detected: sanitize_check.sh did not exit 1 on 12 marker variants (D6, AT-318-10); rc=$rc"
    return 1
  }

  local count
  count="$(echo "$out" | grep -c "unescaped live verdict marker" || true)"
  [ "$count" -eq 12 ] || {
    fail "test_all_live_marker_variants_detected: expected 12 marker findings, got $count (D6, AT-318-10)"
    return 1
  }

  pass "test_all_live_marker_variants_detected (D6, AT-318-10)"
}

banner "test_marker_rule_fails_on_live_verdict_marker"
test_marker_rule_fails_on_live_verdict_marker || true

banner "test_bracketed_notation_passes_marker_rule"
test_bracketed_notation_passes_marker_rule || true

banner "test_marker_allowlist_exemption"
test_marker_allowlist_exemption || true

banner "test_all_live_marker_variants_detected"
test_all_live_marker_variants_detected || true

echo
echo "sanitize_check_test.sh results: $PASSED passed, $FAILED failed out of $TOTAL run"

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi

exit 0
