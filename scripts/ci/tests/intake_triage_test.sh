#!/usr/bin/env bash
# Contract test for scripts/ci/intake_triage.sh

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

WRITES="$WORK/writes.log"
INVOKES="$WORK/invocations.log"
FIXTURES="$WORK/fixtures"
mkdir -p "$WORK/bin" "$FIXTURES"
export WRITES INVOKES FIXTURES
export PATH="$WORK/bin:$PATH"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }
banner() { printf '\n--- %s\n' "$*"; }

TRIAGE="$REPO/scripts/ci/intake_triage.sh"
[ -f "$TRIAGE" ] || fail "Missing intake_triage.sh script"

cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "gh $*" >> "$INVOKES"
if [ "${1:-}" = "issue" ] && [ "${2:-}" = "view" ]; then
  n="${3:-}"
  if [ -f "$FIXTURES/issue-$n.json" ]; then
    cat "$FIXTURES/issue-$n.json"
    exit 0
  fi
  jq -nc --argjson n "$n" '{number: $n, title: "An issue", state: "OPEN", labels: [], comments: [], body: ""}'
  exit 0
fi
if [ "${1:-}" = "search" ]; then
  if [ -f "$FIXTURES/search-fail" ]; then exit 1; fi
  echo '[]'
  exit 0
fi
printf '%s\n' "gh $*" >> "$WRITES"
exit 0
STUB
chmod +x "$WORK/bin/gh"

OUT=""
run() {
  local rc=0
  set +e
  OUT="$(DRY_RUN=1 bash "$TRIAGE" "$1" 2>&1)"
  rc=$?
  set -e
  [ "$rc" -eq 0 ] || { printf '%s\n' "$OUT" >&2; fail "$2 (exit $rc)"; }
  pass "$2"
}
run_fail() {
  local rc=0
  set +e
  OUT="$(DRY_RUN=1 bash "$TRIAGE" "$1" 2>&1)"
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || { printf '%s\n' "$OUT" >&2; fail "$2 (expected non-zero exit)"; }
  pass "$2"
}
has() {
  if printf '%s\n' "$OUT" | grep -qF -- "$1"; then pass "$2";
  else printf '%s\n' "$OUT" >&2; fail "$2 (expected: $1)"; fi
}
hasnt() {
  if printf '%s\n' "$OUT" | grep -qF -- "$1"; then fail "$2 (did not expect: $1)"; else pass "$2"; fi
}
not_invoked() {
  if grep -Eq -- "$1" "$INVOKES"; then fail "$2 (unexpected gh matching: $1)"; else pass "$2"; fi
}
invoked() {
  if grep -Eq -- "$1" "$INVOKES"; then pass "$2"; else fail "$2 (expected gh matching: $1)"; fi
}

reset_fixtures() { rm -f "$FIXTURES"/*; : > "$INVOKES"; : > "$WRITES"; }
issue_fixture() {
  jq -nc --argjson n "$1" --arg s "${2:-OPEN}" --arg t "${3:-Title}" --arg b "${4:-}" --argjson l "${5:-[]}" --argjson c "${6:-[]}" \
    '{number: $n, state: $s, title: $t, body: $b, labels: $l, comments: $c}' > "$FIXTURES/issue-$1.json"
}

banner "D19: Unlabelled issue is not triaged"
reset_fixtures
issue_fixture 1 OPEN "No label" "" "[]"
run 1 "D19: exits 0"
not_invoked "gh search" "D19: no search"
hasnt "blocked" "D19: no blocked label"

banner "D13, D19: Closed issue is not triaged"
reset_fixtures
issue_fixture 2 CLOSED "Closed issue" "" '[{"name":"intent:new"}]'
run 2 "D13: closed exits 0"
not_invoked "gh search" "D13: no search on closed"

banner "D15: Held issue is not triaged"
reset_fixtures
issue_fixture 3 OPEN "Held issue" "" '[{"name":"intent:new"},{"name":"hold"}]'
run 3 "D15: held exits 0"
not_invoked "gh search" "D15: no search on held"

banner "D16: Already triaged issue is not re-triaged"
reset_fixtures
issue_fixture 4 OPEN "Already triaged" "" '[{"name":"intent:new"}]' '[{"body":"<!-- intake-triage:4 -->"}]'
run 4 "D16: already triaged exits 0"
not_invoked "gh search" "D16: no search on already triaged"

banner "D18, D21: intent:new missing required sections gets blocked"
reset_fixtures
issue_fixture 5 OPEN "Missing problem" "### Proposed outcome\nHello" '[{"name":"intent:new"}]'
run 5 "D18: missing problem exits 0"
has "blocked" "D18: blocked label applied"
has "Missing or empty:" "D18: missing or empty clause"
has "Problem" "D18: names Problem as missing"

banner "D17: intent:new with required sections gets triaged"
reset_fixtures
issue_fixture 6 OPEN "All good" "### Problem\nBad\n### Proposed outcome\nGood" '[{"name":"intent:new"}]'
run 6 "D17: all good exits 0"
has "all present" "D17: reports all present"
hasnt "blocked" "D17: blocked is not applied"

banner "D20: search queries are derived from title"
reset_fixtures
issue_fixture 7 OPEN "Typed intake: issue forms for intent and bug, deterministic triage on issue open" "### Problem\nBad\n### Proposed outcome\nGood" '[{"name":"intent:new"}]'
run 7 "D20: search query"
invoked "gh search issues --repo.*typed OR intake OR issue OR forms OR intent OR deterministic" "D20: query is built from title"

banner "D20: search failures exit 1"
reset_fixtures
issue_fixture 8 OPEN "Search fail" "### Problem\nBad\n### Proposed outcome\nGood" '[{"name":"intent:new"}]'
touch "$FIXTURES/search-fail"
run_fail 8 "D20: fails if search fails"

