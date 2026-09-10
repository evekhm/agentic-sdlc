#!/usr/bin/env bash
# Contract test suite for scripts/ci/changelog_check.sh (#410).
# Validates Decisions D3, D4, D5, D11 and Acceptance Tests AT-2 through AT-8, AT-12.
#
# Hermetic: uses a temporary git repository fixture sandbox.
# No network access, no GitHub API calls, no external credentials.
#
# At the build rung (Daedalus), before scripts/ci/changelog_check.sh exists,
# running this suite reports failures (not syntax/runtime errors) and exits 1.
# During the implement rung (Odyssey), once scripts/ci/changelog_check.sh is written,
# all eight scenarios pass green and this suite exits 0.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
CHANGELOG_CHECK="$REPO/scripts/ci/changelog_check.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

SANDBOX="$WORK/repo"
mkdir -p "$SANDBOX"

# Initialize hermetic test repository fixture
git -C "$SANDBOX" init -q -b main
git -C "$SANDBOX" config user.name "Contract Test"
git -C "$SANDBOX" config user.email "contract-test@example.com"

# Setup base commit
echo "Initial base repository" > "$SANDBOX/README.md"
git -C "$SANDBOX" add README.md
git -C "$SANDBOX" commit -q -m "Initial commit"
BASE_COMMIT="$(git -C "$SANDBOX" rev-parse HEAD)"

# Fixture commits on branches
# 1. Non-behavior branch
git -C "$SANDBOX" checkout -q -b test/non-behavior "$BASE_COMMIT"
mkdir -p "$SANDBOX/docs" "$SANDBOX/intent/410-changelog-md-with-a"
echo "living spec" > "$SANDBOX/docs/SPEC.md"
echo "intent spec" > "$SANDBOX/intent/410-changelog-md-with-a/spec.md"
git -C "$SANDBOX" add docs/SPEC.md intent/410-changelog-md-with-a/spec.md
git -C "$SANDBOX" commit -q -m "Non-behavior docs update"
NON_BEHAVIOR_COMMIT="$(git -C "$SANDBOX" rev-parse HEAD)"

# 2. Behavior-bearing + CHANGELOG.md updated branch
git -C "$SANDBOX" checkout -q -b test/changelog-updated "$BASE_COMMIT"
mkdir -p "$SANDBOX/scripts/ci"
echo "#!/usr/bin/env bash" > "$SANDBOX/scripts/ci/some_script.sh"
echo "# Changelog" > "$SANDBOX/CHANGELOG.md"
git -C "$SANDBOX" add scripts/ci/some_script.sh CHANGELOG.md
git -C "$SANDBOX" commit -q -m "Behavior change with CHANGELOG.md"
CHANGELOG_UPDATED_COMMIT="$(git -C "$SANDBOX" rev-parse HEAD)"

# 3. Behavior-bearing missing CHANGELOG.md branch
git -C "$SANDBOX" checkout -q -b test/missing-changelog "$BASE_COMMIT"
mkdir -p "$SANDBOX/scripts/ci"
echo "#!/usr/bin/env bash" > "$SANDBOX/scripts/ci/some_script.sh"
git -C "$SANDBOX" add scripts/ci/some_script.sh
git -C "$SANDBOX" commit -q -m "Behavior change without CHANGELOG.md"
BEHAVIOR_COMMIT="$(git -C "$SANDBOX" rev-parse HEAD)"

# Body fixture files
EMPTY_BODY="$WORK/empty_body.txt"
touch "$EMPTY_BODY"

BODY_VALID_CHANGELOG="$WORK/body_valid_changelog.txt"
cat > "$BODY_VALID_CHANGELOG" <<'BODY'
Fixing minor typo in comments.

Changelog: none — pure refactor without behavioral change
BODY

BODY_VALID_CHANGELOG_IMPACT="$WORK/body_valid_changelog_impact.txt"
cat > "$BODY_VALID_CHANGELOG_IMPACT" <<'BODY'
Internal test suite update.

Changelog-impact: none — internal test additions only
BODY

BODY_MISSING_REASON="$WORK/body_missing_reason.txt"
cat > "$BODY_MISSING_REASON" <<'BODY'
Some description.

Changelog: none
BODY

BODY_FALSE_MATCH="$WORK/body_false_match.txt"
cat > "$BODY_FALSE_MATCH" <<'BODY'
Description with prefix match.

Changelog: nonetheless we proceed
BODY

PASSED=0
FAILED=0
TOTAL=0

banner() { printf '\n=== %s ===\n' "$*"; }

pass() {
    echo "PASS: $*"
    PASSED=$((PASSED + 1))
}

fail() {
    echo "FAIL: $*" >&2
    FAILED=$((FAILED + 1))
}

LAST_OUT=""
LAST_RC=0

run_ci_check() { # <base-sha> <head-sha> <body-file>
    local base="$1" head="$2" body="$3"
    LAST_OUT=""
    LAST_RC=0
    if [ ! -f "$CHANGELOG_CHECK" ]; then
        LAST_OUT="scripts/ci/changelog_check.sh does not exist (implementation pending)"
        LAST_RC=127
        return 127
    fi
    set +e
    LAST_OUT="$(cd "$SANDBOX" && BASE_SHA="$base" HEAD_SHA="$head" PR_BODY_FILE="$body" bash "$CHANGELOG_CHECK" 2>&1)"
    LAST_RC=$?
    set -e
    return "$LAST_RC"
}

run_local_check() { # <base-ref> [body-file]
    local base_ref="$1"
    local body="${2:-}"
    LAST_OUT=""
    LAST_RC=0
    if [ ! -f "$CHANGELOG_CHECK" ]; then
        LAST_OUT="scripts/ci/changelog_check.sh does not exist (implementation pending)"
        LAST_RC=127
        return 127
    fi
    set +e
    if [ -n "$body" ]; then
        LAST_OUT="$(cd "$SANDBOX" && bash "$CHANGELOG_CHECK" "$base_ref" "$body" 2>&1)"
    else
        LAST_OUT="$(cd "$SANDBOX" && bash "$CHANGELOG_CHECK" "$base_ref" 2>&1)"
    fi
    LAST_RC=$?
    set -e
    return "$LAST_RC"
}

# --- Scenario 1: Non-behavior-bearing path changes exit 0 ---------------------
banner "Scenario 1 (D3, D4 / AT-2): Non-behavior-bearing path changes exit 0"
TOTAL=$((TOTAL + 1))
run_ci_check "$BASE_COMMIT" "$NON_BEHAVIOR_COMMIT" "$EMPTY_BODY" || true
expected_s1="::notice::changelog check: no behavior-bearing paths changed; no changelog obligation"
if [ "$LAST_RC" -eq 0 ] && [[ "$LAST_OUT" == *"$expected_s1"* ]]; then
    pass "D3, D4 / AT-2: non-behavior-bearing path changes exit 0 with notice"
else
    fail "D3, D4 / AT-2: non-behavior-bearing path changes failed (rc=$LAST_RC, expected 0; out='$LAST_OUT')"
fi

# --- Scenario 2: Behavior-bearing changes with CHANGELOG.md updated exit 0 ----
banner "Scenario 2 (D3, D4 / AT-3): Behavior-bearing changes with CHANGELOG.md updated exit 0"
TOTAL=$((TOTAL + 1))
run_ci_check "$BASE_COMMIT" "$CHANGELOG_UPDATED_COMMIT" "$EMPTY_BODY" || true
expected_s2="::notice::changelog check: CHANGELOG.md is updated in this PR; reviewers verify its entry against the diff"
if [ "$LAST_RC" -eq 0 ] && [[ "$LAST_OUT" == *"$expected_s2"* ]]; then
    pass "D3, D4 / AT-3: behavior-bearing changes with CHANGELOG.md updated exit 0 with notice"
else
    fail "D3, D4 / AT-3: behavior-bearing changes with CHANGELOG.md updated failed (rc=$LAST_RC, expected 0; out='$LAST_OUT')"
fi

# --- Scenario 3: Behavior-bearing changes missing CHANGELOG.md and marker exit 1
banner "Scenario 3 (D3, D4, D5 / AT-4): Behavior-bearing changes missing CHANGELOG.md and marker exit 1"
TOTAL=$((TOTAL + 1))
run_ci_check "$BASE_COMMIT" "$BEHAVIOR_COMMIT" "$EMPTY_BODY" || true
expected_s3="::error::changelog_check: this PR changes behavior-bearing paths but neither updates CHANGELOG.md nor declares no changelog impact"
if [ "$LAST_RC" -eq 1 ] && [[ "$LAST_OUT" == *"$expected_s3"* ]]; then
    pass "D3, D4, D5 / AT-4: behavior-bearing changes missing CHANGELOG.md and marker exit 1 with error"
else
    fail "D3, D4, D5 / AT-4: behavior-bearing changes missing CHANGELOG.md and marker failed (rc=$LAST_RC, expected 1; out='$LAST_OUT')"
fi

# --- Scenario 4: Valid Changelog: none — <reason> exits 0 ---------------------
banner "Scenario 4 (D3, D5 / AT-5): Valid Changelog: none — <reason> exits 0"
TOTAL=$((TOTAL + 1))
run_ci_check "$BASE_COMMIT" "$BEHAVIOR_COMMIT" "$BODY_VALID_CHANGELOG" || true
expected_s4="::notice::changelog check: declared no changelog impact — pure refactor without behavioral change"
if [ "$LAST_RC" -eq 0 ] && [[ "$LAST_OUT" == *"$expected_s4"* ]]; then
    pass "D3, D5 / AT-5: valid 'Changelog: none — <reason>' marker exits 0 with notice"
else
    fail "D3, D5 / AT-5: valid 'Changelog: none — <reason>' marker failed (rc=$LAST_RC, expected 0; out='$LAST_OUT')"
fi

# --- Scenario 5: Valid Changelog-impact: none — <reason> exits 0 --------------
banner "Scenario 5 (D3, D5 / AT-6): Valid Changelog-impact: none — <reason> exits 0"
TOTAL=$((TOTAL + 1))
run_ci_check "$BASE_COMMIT" "$BEHAVIOR_COMMIT" "$BODY_VALID_CHANGELOG_IMPACT" || true
expected_s5="::notice::changelog check: declared no changelog impact — internal test additions only"
if [ "$LAST_RC" -eq 0 ] && [[ "$LAST_OUT" == *"$expected_s5"* ]]; then
    pass "D3, D5 / AT-6: valid 'Changelog-impact: none — <reason>' marker exits 0 with notice"
else
    fail "D3, D5 / AT-6: valid 'Changelog-impact: none — <reason>' marker failed (rc=$LAST_RC, expected 0; out='$LAST_OUT')"
fi

# --- Scenario 6: Marker missing reason exits 1 --------------------------------
banner "Scenario 6 (D3, D5 / AT-7): Marker missing reason exits 1"
TOTAL=$((TOTAL + 1))
run_ci_check "$BASE_COMMIT" "$BEHAVIOR_COMMIT" "$BODY_MISSING_REASON" || true
expected_s6="::error::changelog_check: the Changelog marker needs a reason: write 'Changelog: none — <why this diff does not change user-facing or system behavior>'"
if [ "$LAST_RC" -eq 1 ] && [[ "$LAST_OUT" == *"$expected_s6"* ]]; then
    pass "D3, D5 / AT-7: marker missing reason exits 1 with error"
else
    fail "D3, D5 / AT-7: marker missing reason failed (rc=$LAST_RC, expected 1; out='$LAST_OUT')"
fi

# --- Scenario 7: Marker prefix false matches exit 1 ---------------------------
banner "Scenario 7 (D3, D5 / AT-8): Marker prefix false match exits 1"
TOTAL=$((TOTAL + 1))
run_ci_check "$BASE_COMMIT" "$BEHAVIOR_COMMIT" "$BODY_FALSE_MATCH" || true
expected_s7="::error::changelog_check: this PR changes behavior-bearing paths but neither updates CHANGELOG.md nor declares no changelog impact"
if [ "$LAST_RC" -eq 1 ] && [[ "$LAST_OUT" == *"$expected_s7"* ]]; then
    pass "D3, D5 / AT-8: marker prefix false match exits 1 with error"
else
    fail "D3, D5 / AT-8: marker prefix false match failed (rc=$LAST_RC, expected 1; out='$LAST_OUT')"
fi

# --- Scenario 8: Positional CLI arguments function identically to CI env ------
banner "Scenario 8 (D3, D11 / AT-12): Positional CLI arguments function identically to CI env"
TOTAL=$((TOTAL + 1))
# Run inside SANDBOX on test/missing-changelog branch against main
git -C "$SANDBOX" checkout -q test/missing-changelog

# Subcase 8a: Local positional invocation with body file containing valid marker -> exit 0
run_local_check "main" "$BODY_VALID_CHANGELOG" || true
subcase_8a_ok=0
if [ "$LAST_RC" -eq 0 ] && [[ "$LAST_OUT" == *"$expected_s4"* ]]; then
    subcase_8a_ok=1
fi

# Subcase 8b: Local positional invocation without body file (defaults to empty) -> exit 1
run_local_check "main" || true
subcase_8b_ok=0
if [ "$LAST_RC" -eq 1 ] && [[ "$LAST_OUT" == *"$expected_s3"* ]]; then
    subcase_8b_ok=1
fi

if [ "$subcase_8a_ok" -eq 1 ] && [ "$subcase_8b_ok" -eq 1 ]; then
    pass "D3, D11 / AT-12: positional CLI arguments function identically to CI environment variables"
else
    fail "D3, D11 / AT-12: positional CLI arguments check failed (8a_ok=$subcase_8a_ok, 8b_ok=$subcase_8b_ok, out='$LAST_OUT')"
fi

# --- Test Summary -------------------------------------------------------------
printf '\n=== Test Summary ===\n'
echo "Total: $TOTAL, Passed: $PASSED, Failed: $FAILED"

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi

exit 0
