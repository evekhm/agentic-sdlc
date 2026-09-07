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
FAILURES=0
fail() { echo "FAIL: $*" >&2; FAILURES=$((FAILURES + 1)); }
banner() { printf '\n--- %s\n' "$*"; }

TRIAGE="${TRIAGE:-$REPO/scripts/ci/intake_triage.sh}"

cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "gh $*" >> "$INVOKES"
if [ "${1:-}" = "api" ]; then
  n=$(echo "$*" | grep -oE 'issues/[0-9]+' | cut -d/ -f2)
  if [ -n "$n" ] && [ -f "$FIXTURES/issue-$n.json" ]; then
    jq '.comments' "$FIXTURES/issue-$n.json"
    exit 0
  fi
  echo '[]'
  exit 0
fi
if [ "${1:-}" = "issue" ] && [ "${2:-}" = "view" ]; then
  n=""
  for arg in "$@"; do
    if [[ "$arg" =~ ^[0-9]+$ ]]; then n="$arg"; break; fi
  done
  if [ -z "$n" ]; then n="${3:-}"; fi
  if [ -f "$FIXTURES/issue-$n.json" ]; then
    cat "$FIXTURES/issue-$n.json"
    exit 0
  fi
  jq -nc --argjson n "${n:-1}" '{number: $n, title: "An issue", state: "OPEN", labels: [], comments: [], body: ""}'
  exit 0
fi
if [ "${1:-}" = "search" ] && [ "${2:-}" = "issues" ]; then
  if [ -f "$FIXTURES/search-issues-fail" ]; then exit 1; fi
  if [[ "$*" == *"--state"* ]]; then
     echo "search has state" >&2
     exit 1
  fi
  jq -nc '[{"url": "https://github.com/evekhm/agentic-sdlc/issues/999", "title": "A past issue", "state": "OPEN"}, {"url": "https://github.com/evekhm/agentic-sdlc/issues/998", "title": "A closed past issue", "state": "CLOSED"}]'
  exit 0
fi
if [ "${1:-}" = "search" ] && [ "${2:-}" = "prs" ]; then
  if [ -f "$FIXTURES/search-prs-fail" ]; then exit 1; fi
  jq -nc '[]'
  exit 0
fi
if [ "${1:-}" = "search" ] && [ "${2:-}" = "prs" ]; then
  if [ -f "$FIXTURES/search-fail" ]; then exit 1; fi
  jq -nc '[]'
  exit 0
fi
if [ "${1:-}" = "issue" ] && [ "${2:-}" = "comment" ]; then
  body=""
  for i in $(seq 1 $#); do
    if [ "${!i}" = "--body-file" ]; then
      j=$((i+1))
      body=$(cat "${!j}")
      break
    fi
  done
  printf '%s\n' "gh $*" >> "$WRITES"
  if [ -n "$body" ]; then
    printf '%s\n' "$body" >> "$WRITES"
  fi
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
  if [ ! -f "$TRIAGE" ]; then
    fail "$2 (script missing)"; return 0
  else
    OUT="$(cd "$WORK" && DRY_RUN=1 bash "$TRIAGE" "$1" 2>&1)"
    rc=$?
  fi
  set -e
  [ "$rc" -eq 0 ] || { printf '%s\n' "$OUT" >&2; fail "$2 (exit $rc)"; return 0; }
  pass "$2"
}
run_fail() {
  local rc=0
  set +e
  if [ ! -f "$TRIAGE" ]; then
    fail "$2 (script missing)"; return 0
  else
    OUT="$(cd "$WORK" && DRY_RUN=1 bash "$TRIAGE" "$1" 2>&1)"
    rc=$?
  fi
  set -e
  [ "$rc" -ne 0 ] || { printf '%s\n' "$OUT" >&2; fail "$2 (expected non-zero exit)"; return 0; }
  pass "$2"
}
run_write() {
  local rc=0
  set +e
  if [ ! -f "$TRIAGE" ]; then
    fail "$2 (script missing)"; return 0
  else
    OUT="$(cd "$WORK" && bash "$TRIAGE" "$1" 2>&1)"
    rc=$?
  fi
  set -e
  [ "$rc" -eq 0 ] || { printf '%s\n' "$OUT" >&2; fail "$2 (exit $rc)"; return 0; }
  pass "$2"
}
run_write_fail() {
  local rc=0
  set +e
  if [ ! -f "$TRIAGE" ]; then
    fail "$2 (script missing)"; return 0
  else
    OUT="$(cd "$WORK" && bash "$TRIAGE" "$1" 2>&1)"
    rc=$?
  fi
  set -e
  [ "$rc" -ne 0 ] || { printf '%s\n' "$OUT" >&2; fail "$2 (expected non-zero exit)"; return 0; }
  pass "$2"
}

has() {
  if printf '%s\n' "$OUT" | grep -qF -- "$1"; then pass "$2";
  else printf '%s\n' "$OUT" >&2; fail "$2 (expected: $1)"; return 0; fi
}

write_has() {
  if grep -qF -- "$1" "$WRITES"; then pass "$2";
  else fail "$2 (expected in writes: $1)"; return 0; fi
}
write_hasnt() {
  if grep -qF -- "$1" "$WRITES"; then fail "$2 (did not expect in writes: $1)"; return 0; else pass "$2"; fi
}
hasnt() {
  if printf '%s\n' "$OUT" | grep -qF -- "$1"; then fail "$2 (did not expect: $1)"; return 0; else pass "$2"; fi
}
not_invoked() {
  if grep -Eq -- "$1" "$INVOKES"; then fail "$2 (unexpected gh matching: $1)"; return 0; else pass "$2"; fi
}
invoked() {
  if grep -Eq -- "$1" "$INVOKES"; then pass "$2"; else fail "$2 (expected gh matching: $1)"; return 0; fi
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
issue_fixture 5 OPEN "Missing problem" "$(printf '### Proposed outcome\nHello')" '[{"name":"intent:new"}]'
run 5 "D18: missing problem exits 0"
has "blocked" "D18: blocked label applied"
has "Missing or empty:" "D18: missing or empty clause"
has "Problem" "D18: names Problem as missing"

banner "D17: intent:new with required sections gets triaged"
reset_fixtures
issue_fixture 6 OPEN "All good" "$(printf '### Problem\nBad\n### Proposed outcome\nGood')" '[{"name":"intent:new"}]'
run 6 "D17: all good exits 0"
has "all present" "D17: reports all present"
hasnt "blocked" "D17: blocked is not applied"

banner "D20: search queries are derived from title"
reset_fixtures
issue_fixture 7 OPEN "Typed intake: issue forms for intent and bug, deterministic triage on issue open" "$(printf '### Problem
Bad
### Proposed outcome
Good')" '[{"name":"intent:new"}]'
run 7 "D20: search query"
STOPWORDS="$(grep -m1 -oE 2>/dev/null '^STOPWORDS=.*' "$TRIAGE" | cut -d'"' -f2 || echo "a an the")"
EXPECTED_QUERY=$(python3 -c "
import sys, re
title = sys.argv[1].lower()
title = re.sub(r'[^a-z0-9]', ' ', title)
words = title.split()
stopwords = sys.argv[2].split()
res = []
for w in words:
    if len(w) >= 4 and w not in stopwords and w not in res:
        res.append(w)
print(' OR '.join(res[:6]))
" "Typed intake: issue forms for intent and bug, deterministic triage on issue open" "$STOPWORDS")
invoked "gh search issues --repo.*$EXPECTED_QUERY" "D20: query is built from title"


banner "D20: search failures exit 1 and write nothing"

reset_fixtures
issue_fixture 8 OPEN "Search fail" "$(printf '### Problem
Bad
### Proposed outcome
Good')" '[{"name":"intent:new"}]'
touch "$FIXTURES/search-issues-fail"
run_write_fail 8 "D20: fails if search issues fails"
if [ ! -s "$WRITES" ]; then pass "D20: writes nothing on search issues fail"; else fail "D20: writes not empty"; fi

reset_fixtures
issue_fixture 8 OPEN "Search fail" "$(printf '### Problem
Bad
### Proposed outcome
Good')" '[{"name":"intent:new"}]'
touch "$FIXTURES/search-prs-fail"
run_write_fail 8 "D20: fails if search prs fails"
if [ ! -s "$WRITES" ]; then pass "D20: writes nothing on search prs fail"; else fail "D20: writes not empty"; fi

reset_fixtures
issue_fixture 8 OPEN "Search fail" "$(printf '### Problem
Bad
### Proposed outcome
Good')" '[{"name":"intent:new"}]'
touch "$FIXTURES/intent-list-fail"
run_write_fail 8 "D20: fails if intent listing fails"
if [ ! -s "$WRITES" ]; then pass "D20: writes nothing on intent list fail"; else fail "D20: writes not empty"; fi


banner "D16: Comment ends with marker line"
reset_fixtures
issue_fixture 9 OPEN "Valid issue" "$(printf '### Problem\nBadddd\n### Proposed outcome\nGood')" '[{"name":"intent:new"}]'
run_write 9 "D16: write run exits 0"
if grep -qF "<!-- intake-triage:9 -->" "$WRITES"; then pass "D16: marker written"; else fail "D16: marker missing in WRITES"; fi

banner "D17: Zero-term title produces zero searches and exact 'nothing matched' form"
reset_fixtures
issue_fixture 10 OPEN "a an the" "$(printf '### Problem\nBadddd\n### Proposed outcome\nGood')" '[{"name":"intent:new"}]'
run_write 10 "D17: zero-term exits 0"
not_invoked "gh search" "D17: no searches performed"
write_has "**Prior art:** not searched — the title yielded no term of 4 characters or more." "D17: exact nothing matched form"

banner "D18: bug form missing Severity applies blocked"
reset_fixtures
issue_fixture 11 OPEN "Bug issue" "$(printf '### What happened\nBad\n### What you expected\nGood')" '[{"name":"bug"}]'
run_write 11 "D18: bug missing severity exits 0"
write_has "blocked" "D18: bug blocked label applied"
write_has "Severity" "D18: names Severity as missing"

banner "D18: intent:new missing Problem does NOT name Constraints"
reset_fixtures
issue_fixture 12 OPEN "Missing problem" "$(printf '### Proposed outcome\nGood')" '[{"name":"intent:new"}]'
run_write 12 "D18: intent missing problem exits 0"
write_has "blocked" "D18: blocked label applied"
write_has "Problem" "D18: names Problem as missing"
write_hasnt "Constraints" "D18: does NOT name Constraints as missing"

banner "D20: stub returning open and closed matches lists both, tagged (open) and (closed)"
reset_fixtures
issue_fixture 13 OPEN "A past issue" "$(printf '### Problem\nBad\n### Proposed outcome\nGood')" '[{"name":"intent:new"}]'
run 13 "D20: search with results exits 0"
has "(open)" "D20: open match tagged"
has "(closed)" "D20: closed match tagged"

banner "D20: candidate list matching an intent/*/ folder excludes the triaged issue"
reset_fixtures
mkdir -p "intent/14-past-issue"
issue_fixture 14 OPEN "Past issue" "$(printf '### Problem\nBad\n### Proposed outcome\nGood')" '[{"name":"intent:new"}]'
run 14 "D20: intent list excludes self"
hasnt "14-past-issue" "D20: self excluded from candidate list"
rm -rf "intent/14-past-issue"

banner "D20: gh search prs, --limit 10, no --state"
reset_fixtures
issue_fixture 15 OPEN "Search args" "$(printf '### Problem\nBad\n### Proposed outcome\nGood')" '[{"name":"intent:new"}]'
run 15 "D20: args check exits 0"
invoked "gh search prs" "D20: search prs invoked"
invoked "--limit 10" "D20: --limit 10 invoked"
not_invoked "--state" "D20: no --state invoked"


banner "D13, D15: invocation log holds exactly two labels-and-state reads surrounding the marker read in order"
reset_fixtures
issue_fixture 16 OPEN "Valid issue" "$(printf '### Problem
Bad
### Proposed outcome
Good')" '[{"name":"intent:new"}]'
run 16 "D13: invocation order exits 0"
# Filter and normalize invocations to just the command bases
awk '{
  if ($0 ~ /gh issue view/) print "view";
  else if ($0 ~ /gh api.*comments/) print "marker";
  else if ($0 ~ /gh search issues/) print "search_issues";
  else if ($0 ~ /gh search prs/) print "search_prs";
}' "$INVOKES" > "$WORK/actual_order"

cat << 'SEQ' > "$WORK/expected_order"
view
marker
search_issues
search_prs
view
SEQ

if cmp -s "$WORK/expected_order" "$WORK/actual_order"; then
    pass "D13: sequence is view, marker, search_issues, search_prs, view"
else
    fail "D13: sequence mismatch. Expected:"
    cat "$WORK/expected_order" >&2
    echo "Got:" >&2
    cat "$WORK/actual_order" >&2
fi

banner "D20: query derivation is identical on two consecutive runs, one real title"
reset_fixtures
issue_fixture 17 OPEN "Add tests for user authentication" "$(printf '### Problem
Bad
### Proposed outcome
Good')" '[{"name":"intent:new"}]'
run 17 "D20: title 1 run 1"
Q1=$(grep -oE "gh search issues --repo.*" "$INVOKES" | head -n1)
: > "$INVOKES"
run 17 "D20: title 1 run 2"
Q2=$(grep -oE "gh search issues --repo.*" "$INVOKES" | head -n1)
if [ "$Q1" = "$Q2" ] && [ -n "$Q1" ]; then pass "D20: query is identical on two runs"; else fail "D20: query mismatch"; fi


if [ "$FAILURES" -gt 0 ]; then
  echo "Total failures: $FAILURES" >&2
  exit 1
fi
