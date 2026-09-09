#!/usr/bin/env bash
# Contract tests for merge gate consensus and post.sh label step (#265).
# Cites Decisions D3, D5 and Acceptance Tests AT-12, AT-13, AT-19, AT-20, AT-21, AT-22, plus Argus R3-1.
#
# Hermetic: tests run locally without network access.
# Under the baseline tree at 696f516239efaa8d9c63592354a08fc398b410f4, every assertion
# must FAIL (red) because the production implementation has not been written yet.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
POST_SH="$REPO/scripts/ops/post.sh"
MERGE_GATE="$REPO/scripts/ci/merge_gate.sh"
BOOTSTRAP_SH="$REPO/scripts/setup/bootstrap_tracker.sh"
LABEL_TAXONOMY="$REPO/scripts/setup/issues/04-label-taxonomy.md"

FAILURES=0

banner() { printf '\n=== %s ===\n' "$*"; }

pass() {
    echo "PASS: $*"
}

fail() {
    echo "FAIL: $*" >&2
    FAILURES=$((FAILURES + 1))
}

# --- D3 / AT-12, AT-13: Label provisioning and taxonomy ---------------------------
banner "D3 / AT-12, AT-13: deep-review label provisioning and taxonomy"

if grep -F 'ensure_label "deep-review" "5319E7"' "$BOOTSTRAP_SH" >/dev/null 2>&1; then
    pass "D3 / AT-12: bootstrap_tracker.sh provisions deep-review label"
else
    fail "D3 / AT-12: bootstrap_tracker.sh missing deep-review label provisioning"
fi

if grep -A 1 '### `deep-review`' "$LABEL_TAXONOMY" 2>/dev/null | grep -q 'Deep-review grant'; then
    pass "D3 / AT-13: 04-label-taxonomy.md documents deep-review label"
else
    fail "D3 / AT-13: 04-label-taxonomy.md missing '### \`deep-review\`' documentation"
fi

# --- D3 / AT-19, AT-20: post.sh --add-label verb enforcement -----------------------
banner "D3 / AT-19, AT-20: post.sh --add-label verb enforcement"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin"

# AT-19: post.sh --add-label hold exits 2 and outputs expected rejection
out19=""
rc19=0
out19="$("$POST_SH" 100 --as argus --add-label hold 2>&1)" || rc19=$?
expected_msg="post.sh: --add-label accepts only deep-review on a pull request"

if [ "$rc19" -eq 2 ] && [[ "$out19" == *"$expected_msg"* ]]; then
    pass "D3 / AT-19: post.sh --add-label hold exits 2 and outputs '$expected_msg'"
else
    fail "D3 / AT-19: post.sh --add-label hold did not exit 2 with expected message (rc=$rc19, out: $out19)"
fi

# AT-20: post.sh --add-label deep-review on a PR succeeds and applies label
# Hermetic test with stub gh in PATH
cat <<'STUB_GH' > "$WORK/bin/gh"
#!/usr/bin/env bash
if [ "$1" = "api" ]; then
    case "$2" in
        repos/*/*/issues/100)
            printf '{"number": 100, "pull_request": {"url": "https://api.github.com/repos/test/repo/pulls/100"}, "labels": []}\n'
            exit 0
            ;;
        repos/*/*/issues/100/labels)
            echo "$@" >> "$WRITES_LOG"
            exit 0
            ;;
    esac
fi
echo "stub gh: unhandled $@" >&2
exit 1
STUB_GH
chmod +x "$WORK/bin/gh"

WRITES_LOG="$WORK/writes.log"
touch "$WRITES_LOG"

rc20=0
out20=""
out20="$(PATH="$WORK/bin:$PATH" WRITES_LOG="$WRITES_LOG" GITHUB_REPO="test/repo" "$POST_SH" 100 --as argus --add-label deep-review 2>&1)" || rc20=$?

if [ "$rc20" -eq 0 ] && grep -q 'deep-review' "$WRITES_LOG" 2>/dev/null; then
    pass "D3 / AT-20: post.sh --add-label deep-review exits 0 and applies label"
else
    fail "D3 / AT-20: post.sh --add-label deep-review did not succeed (rc=$rc20, out: $out20)"
fi

# --- D5 / AT-21, AT-22, R3-1: merge_gate.sh consensus evaluation ------------------
banner "D5 / AT-21, AT-22, R3-1: merge_gate.sh consensus evaluation"

# Source the hermetic test harness from merge_gate_test.sh
source <(sed -e "s|^REPO=.*|REPO=\"$REPO\"|" -e '/^# ---*$/q' "$REPO/scripts/ci/tests/merge_gate_test.sh")

# Ensure fail increments the suite-level failure counter without exiting immediately
fail() {
    echo "FAIL: $*" >&2
    FAILURES=$((FAILURES + 1))
}
pass() {
    echo "PASS: $*"
}

# Wrap python3 stub to record invocations into $INVOKES so R3-1 can observe subscriber dispatch
cat > "$WORK/bin/python3" <<STUB
#!/usr/bin/env bash
printf '%s\n' "python3 \$*" >> "\$INVOKES"
if [ "\${2:-}" = "--loop" ]; then
  [ -f "\$FX/loop-\$3" ] || exit 1
  cat "\$FX/loop-\$3"; exit 0
fi
exec /usr/bin/python3 "\$@"
STUB
chmod +x "$WORK/bin/python3"

# AT-21: Atlas-only PR with assigned:atlas and Atlas verdict at head
mk_green
comments_fixture 123 "$(comment "$MERGER" "$(consensus_ledger 123 - "$H" atlas)")"
run "D5 / AT-21: Atlas-only PR with assigned:atlas exits 0" 123
has "conjunct (3): true" "D5 / AT-21: conjunct (3) reports true for Atlas-only assignment"
has "conjunct (11): true" "D5 / AT-21: conjunct (11) reports true for Atlas-only assignment"
merged "D5 / AT-21: single-reviewer Atlas consensus merges"

# AT-22: Dual-assigned PR with assigned:argus,atlas must NOT regress when AT-21 lands
mk_green
comments_fixture 123 "$(comment "$MERGER" "$(consensus_ledger 123 - "$H" argus,atlas)")"
run "D5 / AT-22: dual-assigned PR with only Atlas verdict exits 0" 123
has "conjunct (3): false" "D5 / AT-22 (must not regress): conjunct (3) reports false when Argus verdict missing"
not_merged "D5 / AT-22 (must not regress): dual-assigned PR does not merge without Argus"

# R3-1: Absent assigned marker fallback to execution.py --subscribers
mk_green
comments_fixture 123 "$(comment "$MERGER" "$(consensus_ledger 123 - "$H" -)")"
run "D5 / R3-1: absent assigned marker exits 0" 123
if grep -Eq -- 'execution\.py.*--subscribers' "$INVOKES" 2>/dev/null; then
    pass "D5 / R3-1: merge_gate.sh resolves assigned set through execution.py --subscribers"
else
    fail "D5 / R3-1: merge_gate.sh does not resolve assigned set through execution.py --subscribers"
fi

banner "Merge Gate Contract Test Summary"
if [ "$FAILURES" -gt 0 ]; then
    echo "Total failures: $FAILURES (EXPECTED RED at build rung)" >&2
    exit 1
fi

echo "ALL TESTS PASSED"
exit 0
