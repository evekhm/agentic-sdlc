#!/usr/bin/env bash
# Tests for scripts/ci/review_recorder.sh (#267).
#
#   bash scripts/ci/tests/review_recorder_test.sh [-k <filter>]
#
# Hermetic: a stub `gh` first on PATH answers reads from fixture files
# under $FX and records writes in $WRITES; a stub `python3` answers
# helper checks. No network, no live tokens.
#
# Each test asserts behaviors derived from numbered Decisions (D1-D12)
# and Acceptance criteria (AT-1..AT-18). Contract tests fail (RED)
# when scripts/ci/review_recorder.sh has not yet been implemented.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
RECORDER="$REPO/scripts/ci/review_recorder.sh"
GATE="$REPO/scripts/ci/merge_gate.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; }
banner() { printf '\n--- %s\n' "$*"; }

FILTER=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -k|--filter)
      [ "$#" -ge 2 ] || { echo "ERROR: -k requires a pattern" >&2; exit 1; }
      FILTER="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [-k <test_name_pattern>]"
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument '$1'" >&2
      exit 1
      ;;
  esac
done

FX="$WORK/fx"
WRITES="$WORK/writes.log"
INVOKES="$WORK/invokes.log"
mkdir -p "$WORK/bin" "$FX"
export PATH="$WORK/bin:$PATH"
export FX WRITES INVOKES
export GITHUB_REPOSITORY="evekhm/agentic-sdlc"
export DRY_RUN=0

THEMIS="evekhm-themis-app[bot]"
ARGUS="evekhm-argus-app[bot]"
ATLAS="evekhm-atlas-app[bot]"
ACTIONS="github-actions[bot]"
H="$(printf 'a%.0s' {1..40})"
H0="$(printf 'b%.0s' {1..40})"

# Stub tools that must never run live during hermetic tests
for tool in claude gemini agy curl; do
  printf '#!/usr/bin/env bash\necho "%s stub called" >&2\nexit 1\n' "$tool" > "$WORK/bin/$tool"
  chmod +x "$WORK/bin/$tool"
done

# Stub gh cli
cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "gh $*" >> "$INVOKES"
record_write() {
  printf '%s\n' "gh $*" >> "$WRITES"
  local prev=""
  for a in "$@"; do
    case "$prev" in
      --body-file|-F|--field)
        f="${a#body=@}"
        [ -f "$f" ] && cat "$f" >> "$WRITES"
        ;;
    esac
    prev="$a"
  done
}

case "${1:-} ${2:-}" in
  "pr view")
    n="$3"
    [ -f "$FX/pr-$n.json" ] && { cat "$FX/pr-$n.json"; exit 0; }
    echo "no pull request fixture $n" >&2; exit 1;;
  "issue view")
    n="$3"
    [ -f "$FX/issue-$n.json" ] && { cat "$FX/issue-$n.json"; exit 0; }
    echo '{"labels":[]}'; exit 0;;
  "pr merge"|"issue edit"|"issue comment")
    record_write "$@"; exit 0;;
  "api user")
    echo '{"message":"Resource not accessible by integration","documentation_url":"https://docs.github.com/rest/users/users#get-the-authenticated-user","status":"403"}'
    echo "gh: Resource not accessible by integration (HTTP 403)" >&2; exit 1;;
  "api graphql")
    if [[ "$*" == *"viewer { login }"* ]]; then
      login="$THEMIS"
      [ -f "$FX/viewer-login" ] && login="$(cat "$FX/viewer-login")"
      jq -nc --arg l "$login" '{data: {viewer: {login: $l}}}'; exit 0
    fi
    exit 0;;
esac

if [ "${1:-}" = api ]; then
  method=GET path="" prevflag="" skip=0
  for a in "${@:2}"; do
    if [ "$skip" = 1 ]; then skip=0; [ "$prevflag" = -X ] && method="$a"; continue; fi
    case "$a" in
      -X|-F|-f|--field|--input|-q|--jq) prevflag="$a"; skip=1;;
      -*) ;;
      *) [ -n "$path" ] || path="$a";;
    esac
  done

  p="${path%%\?*}"
  if [ "$method" != GET ]; then
    record_write "$@"
    case "$p" in
      repos/*/issues/*/comments)
        echo '{"id":5001}'
        exit 0;;
      repos/*/issues/comments/*)
        echo '{"id":5001}'
        exit 0;;
      *)
        echo '{"ok":true}'
        exit 0;;
    esac
  fi

  case "$p" in
    repos/*/issues/*/comments)
      n="${p#*/issues/}"; n="${n%/comments}"
      if [ -f "$FX/comments-$n.json" ]; then cat "$FX/comments-$n.json"; else echo '[]'; fi
      exit 0;;
    repos/*/issues/comments/*)
      cid="${p##*/}"
      if [ -f "$FX/comment-$cid.json" ]; then cat "$FX/comment-$cid.json"; else echo '{"id":5001,"body":""}'; fi
      exit 0;;
    repos/*/actions/runs/*)
      rid="${p##*/}"
      if [ -f "$FX/run-$rid.json" ]; then cat "$FX/run-$rid.json"; else echo '{}'; fi
      exit 0;;
    *)
      echo '{}'; exit 0;;
  esac
fi

exit 0
STUB
chmod +x "$WORK/bin/gh"

# Fixture helpers
reset_state() {
  rm -rf "$FX"
  mkdir -p "$FX"
  : > "$WRITES"
  : > "$INVOKES"
}

pr_fixture() { # <number> <head_sha> [author]
  local num="$1" head="${2:-$H}" author="${3:-evekhm-odyssey-app[bot]}"
  jq -nc --argjson n "$num" --arg head "$head" --arg author "$author" \
    --arg hr "$GITHUB_REPOSITORY" \
    '{number: $n, state: "OPEN", body: "Refs #267", author: {login: $author},
      headRefName: "odyssey/267-feature", headRefOid: $head,
      headRepository: {nameWithOwner: $hr}, baseRefName: "main",
      labels: []}' > "$FX/pr-$num.json"
}

comment_item() { # <login> <body> <id> [association]
  local l="$1" b="$2" i="$3" assoc="${4:-COLLABORATOR}"
  jq -nc --arg l "$l" --arg b "$b" --argjson i "$i" --arg assoc "$assoc" \
    '{id: $i, user: {login: $l, type: "Bot"}, body: $b, author_association: $assoc, created_at: "2026-09-09T08:00:00Z"}'
}

comments_fixture() { # <pr_number> <comment_json>...
  local pr="$1"; shift
  printf '%s\n' "$@" | jq -sc . > "$FX/comments-$pr.json"
}

run_fixture() { # <run_id> <actor> <head_sha> <event> <status> <conclusion>
  local rid="$1" actor="$2" head="$3" ev="$4" status="$5" concl="$6"
  local c_val
  if [ "$concl" = "null" ]; then c_val="null"; else c_val="\"$concl\""; fi
  jq -nc --argjson rid "$rid" --arg actor "$actor" --arg head "$head" \
    --arg ev "$ev" --arg status "$status" --argjson concl "$c_val" \
    --arg hr "$GITHUB_REPOSITORY" \
    '{id: $rid, name: "unattended", head_sha: $head, event: $ev, status: $status,
      conclusion: $concl, actor: {login: $actor},
      head_repository: {full_name: $hr}}' > "$FX/run-$rid.json"
}

# --- Test Scenarios ---

# AT-2 (D2): Marker parsing, Decision-ID @<Dn> extraction, sibling failure-scenario
test_marker_parsing() {
  reset_state
  pr_fixture 101 "$H"
  run_fixture 2001 "$ARGUS" "$H" "pull_request" "completed" "success"

  local rev_body
  rev_body="$(cat <<EOF
### Argus review
<!-- reviewer:argus -->
<!-- run-id:2001 -->
<!-- round:1 -->
<!-- finding:R1-1@D4:high:open:none -->
<!-- failure-scenario:R1-1@D4 -->
State machine deadlocks when worker receives shutdown signal
<!-- review-verdict-end -->
EOF
)"
  comments_fixture 101 "$(comment_item "$ARGUS" "$rev_body" 3001)"

  if [ ! -f "$RECORDER" ]; then
    fail "test_marker_parsing: $RECORDER does not exist (D2, AT-2)"
    return 1
  fi

  bash "$RECORDER" 101 || { fail "test_marker_parsing: recorder failed (D2)"; return 1; }
  grep -q "ledger-row:R1-1@D4:high:open:none" "$WRITES" || { fail "test_marker_parsing: row with @D4 not written (D2, D5)"; return 1; }
  grep -q "reviewed-head:argus:$H" "$WRITES" || { fail "test_marker_parsing: argus head not recorded (D2, D4)"; return 1; }
  pass "test_marker_parsing (D2, AT-2)"
}

# AT-3 (D2, D3): Provenance validation, action pinning, marker withdrawal
test_provenance_validation() {
  reset_state
  pr_fixture 102 "$H"
  # Mismatched actor (forged review comment)
  run_fixture 2002 "untrusted-user" "$H" "pull_request" "completed" "success"

  local rev_body
  rev_body="$(cat <<EOF
### Argus review
<!-- reviewer:argus -->
<!-- run-id:2002 -->
<!-- round:1 -->
<!-- finding:R1-1@D4:high:open:none -->
<!-- review-verdict-end -->
EOF
)"
  comments_fixture 102 "$(comment_item "untrusted-user" "$rev_body" 3002)"

  if [ ! -f "$RECORDER" ]; then
    fail "test_provenance_validation: $RECORDER does not exist (D3, AT-3)"
    return 1
  fi

  bash "$RECORDER" 102 || { fail "test_provenance_validation: recorder should exit 0 on refusal (D1, D3)"; return 1; }
  grep -q "ledger-row:R1-1@D4" "$WRITES" && { fail "test_provenance_validation: forged row was accepted (D3)"; return 1; }
  grep -q "\[refused:.*\]" "$WRITES" || { fail "test_provenance_validation: audit note not written (D3)"; return 1; }
  pass "test_provenance_validation (D2, D3, AT-3)"
}

# AT-4 (D4): Single consensus ledger comment lifecycle (POST then PATCH)
test_ledger_comment_lifecycle() {
  reset_state
  pr_fixture 103 "$H"
  run_fixture 2003 "$ARGUS" "$H" "pull_request" "completed" "success"

  local rev_body
  rev_body="$(cat <<EOF
### Argus review
<!-- reviewer:argus -->
<!-- run-id:2003 -->
<!-- round:1 -->
<!-- finding:R1-1@D4:normal:open:none -->
<!-- review-verdict-end -->
EOF
)"
  comments_fixture 103 "$(comment_item "$ARGUS" "$rev_body" 3003)"

  if [ ! -f "$RECORDER" ]; then
    fail "test_ledger_comment_lifecycle: $RECORDER does not exist (D4, AT-4)"
    return 1
  fi

  # Pass 1: initial creation calls POST
  bash "$RECORDER" 103 || { fail "test_ledger_comment_lifecycle: pass 1 failed"; return 1; }
  grep -q "gh api.*POST.*repos/.*/issues/103/comments" "$WRITES" || { fail "test_ledger_comment_lifecycle: POST not called on initial creation (D4)"; return 1; }

  # Pass 2: subsequent update calls PATCH
  local ledger_comment
  ledger_comment="$(cat <<EOF
### Findings ledger for #103
<!-- consensus-ledger:103 -->
<!-- assigned:argus,atlas -->
<!-- reviewed-head:argus:$H -->
<!-- ledger-row:R1-1@D4:normal:open:none -->
<!-- consensus-ledger-end -->
EOF
)"
  echo "$ledger_comment" > "$FX/comment-5001.json"
  comments_fixture 103 \
    "$(comment_item "$THEMIS" "$ledger_comment" 5001)" \
    "$(comment_item "$ARGUS" "$rev_body" 3003)"

  : > "$WRITES"
  bash "$RECORDER" 103 || { fail "test_ledger_comment_lifecycle: pass 2 failed"; return 1; }
  grep -q "gh api.*PATCH.*repos/.*/issues/comments/5001" "$WRITES" || { fail "test_ledger_comment_lifecycle: PATCH not called for in-place update (D4)"; return 1; }
  pass "test_ledger_comment_lifecycle (D4, AT-4)"
}

# AT-5 (D5): High finding without failure_scenario demoted to normal
test_high_failure_scenario_demotion() {
  reset_state
  pr_fixture 104 "$H"
  run_fixture 2004 "$ARGUS" "$H" "pull_request" "completed" "success"

  local rev_body
  rev_body="$(cat <<EOF
### Argus review
<!-- reviewer:argus -->
<!-- run-id:2004 -->
<!-- round:1 -->
<!-- finding:R1-2@D5:high:open:none -->
This finding lacks the required failure-scenario marker
<!-- review-verdict-end -->
EOF
)"
  comments_fixture 104 "$(comment_item "$ARGUS" "$rev_body" 3004)"

  if [ ! -f "$RECORDER" ]; then
    fail "test_high_failure_scenario_demotion: $RECORDER does not exist (D5, AT-5)"
    return 1
  fi

  bash "$RECORDER" 104 || { fail "test_high_failure_scenario_demotion: recorder execution failed"; return 1; }
  grep -q "ledger-row:R1-2@D5:normal:open:none" "$WRITES" || { fail "test_high_failure_scenario_demotion: high was not demoted to normal (D5)"; return 1; }
  grep -q "\[demoted from high: missing failure_scenario marker\]" "$WRITES" || { fail "test_high_failure_scenario_demotion: audit note missing (D5)"; return 1; }
  pass "test_high_failure_scenario_demotion (D5, AT-5)"
}

# AT-6 (D5): Non-enum severity refusal (critical, low) logs and creates no row
test_non_enum_severity_refusal() {
  reset_state
  pr_fixture 105 "$H"
  run_fixture 2005 "$ARGUS" "$H" "pull_request" "completed" "success"

  local rev_body
  rev_body="$(cat <<EOF
### Argus review
<!-- reviewer:argus -->
<!-- run-id:2005 -->
<!-- round:1 -->
<!-- finding:R1-3@D5:critical:open:none -->
<!-- finding:R1-4@D5:low:open:none -->
<!-- review-verdict-end -->
EOF
)"
  comments_fixture 105 "$(comment_item "$ARGUS" "$rev_body" 3005)"

  if [ ! -f "$RECORDER" ]; then
    fail "test_non_enum_severity_refusal: $RECORDER does not exist (D5, AT-6)"
    return 1
  fi

  local out
  out="$(bash "$RECORDER" 105 2>&1)" || { fail "test_non_enum_severity_refusal: must exit 0 on refused findings (D1, D5)"; return 1; }
  echo "$out" | grep -q "finding R1-3@D5: severity critical is not one of security|high|normal|suggestion" || { fail "test_non_enum_severity_refusal: critical refusal log missing"; return 1; }
  echo "$out" | grep -q "finding R1-4@D5: severity low is not one of security|high|normal|suggestion" || { fail "test_non_enum_severity_refusal: low refusal log missing"; return 1; }
  grep -q "ledger-row:R1-3@D5" "$WRITES" && { fail "test_non_enum_severity_refusal: critical row created in ledger (D5)"; return 1; }
  grep -q "ledger-row:R1-4@D5" "$WRITES" && { fail "test_non_enum_severity_refusal: low row created in ledger (D5)"; return 1; }
  grep -q "\[refused: R1-3@D5: invalid severity critical\]" "$WRITES" || { fail "test_non_enum_severity_refusal: critical audit note missing"; return 1; }
  pass "test_non_enum_severity_refusal (D5, AT-6)"
}

# AT-7 (D6): Round funnel enforcement (round 2-3 normal/suggestion; past round 3 demotion)
test_round_funnel() {
  reset_state
  pr_fixture 106 "$H"
  run_fixture 2006 "$ARGUS" "$H" "pull_request" "completed" "success"

  local rev_body
  rev_body="$(cat <<EOF
### Argus review
<!-- reviewer:argus -->
<!-- run-id:2006 -->
<!-- round:4 -->
<!-- finding:R4-1:high:open:none -->
<!-- failure-scenario:R4-1 -->
Buffer overflow on large input
<!-- finding:R4-2:security:open:pending -->
Remote code execution vector
<!-- review-verdict-end -->
EOF
)"
  comments_fixture 106 "$(comment_item "$ARGUS" "$rev_body" 3006)"

  if [ ! -f "$RECORDER" ]; then
    fail "test_round_funnel: $RECORDER does not exist (D6, AT-7)"
    return 1
  fi

  bash "$RECORDER" 106 || { fail "test_round_funnel: recorder execution failed"; return 1; }
  # Past round 3, high is demoted to normal
  grep -q "ledger-row:R4-1:normal:open:none" "$WRITES" || { fail "test_round_funnel: high finding past round 3 not demoted (D6)"; return 1; }
  # Security finding is admitted
  grep -q "ledger-row:R4-2:security:open:pending" "$WRITES" || { fail "test_round_funnel: security finding past round 3 refused (D6)"; return 1; }
  pass "test_round_funnel (D6, AT-7)"
}

# AT-8 (D7): Security dual agreement requirement (existence and fix)
test_security_dual_agreement() {
  reset_state
  pr_fixture 107 "$H"
  run_fixture 2007 "$ARGUS" "$H" "pull_request" "completed" "success"
  run_fixture 2008 "$ATLAS" "$H" "pull_request" "completed" "success"

  local argus_rev atlas_rev
  argus_rev="$(cat <<EOF
### Argus review
<!-- reviewer:argus -->
<!-- run-id:2007 -->
<!-- round:1 -->
<!-- finding:R1-10:security:fixed:pending -->
Credential leak in debug log
<!-- review-verdict-end -->
EOF
)"
  atlas_rev="$(cat <<EOF
### Atlas review
<!-- reviewer:atlas -->
<!-- run-id:2008 -->
<!-- round:1 -->
<!-- finding:R1-10:security:fixed:agree -->
<!-- review-verdict-end -->
EOF
)"
  comments_fixture 107 \
    "$(comment_item "$ARGUS" "$argus_rev" 3007)" \
    "$(comment_item "$ATLAS" "$atlas_rev" 3008)"

  if [ ! -f "$RECORDER" ]; then
    fail "test_security_dual_agreement: $RECORDER does not exist (D7, AT-8)"
    return 1
  fi

  bash "$RECORDER" 107 || { fail "test_security_dual_agreement: recorder execution failed"; return 1; }
  grep -q "ledger-row:R1-10:security:fixed:agree" "$WRITES" || { fail "test_security_dual_agreement: security dual agreement row not recorded (D7)"; return 1; }
  pass "test_security_dual_agreement (D7, AT-8)"
}

# AT-9 (D9): Maintainer retier command verification
test_owner_retier() {
  reset_state
  pr_fixture 108 "$H"
  run_fixture 2009 "$ARGUS" "$H" "pull_request" "completed" "success"

  local rev_body
  rev_body="$(cat <<EOF
### Argus review
<!-- reviewer:argus -->
<!-- run-id:2009 -->
<!-- round:1 -->
<!-- finding:R1-1@D4:high:open:none -->
<!-- failure-scenario:R1-1@D4 -->
Flaky timeout
<!-- review-verdict-end -->
EOF
)"
  local retier_cmd="@argus retier R1-1@D4 normal"

  comments_fixture 108 \
    "$(comment_item "$ARGUS" "$rev_body" 3009)" \
    "$(comment_item "evekhm" "$retier_cmd" 3010 "OWNER")"

  if [ ! -f "$RECORDER" ]; then
    fail "test_owner_retier: $RECORDER does not exist (D9, AT-9)"
    return 1
  fi

  bash "$RECORDER" 108 || { fail "test_owner_retier: recorder execution failed"; return 1; }
  grep -q "ledger-row:R1-1@D4:normal:open:none" "$WRITES" || { fail "test_owner_retier: retier command did not update row severity (D9)"; return 1; }
  grep -q "\[retiered to normal by @evekhm\]" "$WRITES" || { fail "test_owner_retier: retier audit note missing (D9)"; return 1; }
  pass "test_owner_retier (D9, AT-9)"
}

# AT-10 (D8): Label synchronization via gh issue edit
test_label_sync() {
  reset_state
  pr_fixture 109 "$H"
  run_fixture 2010 "$ARGUS" "$H" "pull_request" "completed" "success"

  local rev_body
  rev_body="$(cat <<EOF
### Argus review
<!-- reviewer:argus -->
<!-- run-id:2010 -->
<!-- round:2 -->
<!-- finding:R2-1:high:open:none -->
<!-- failure-scenario:R2-1 -->
Crash on invalid utf8 input
<!-- review-verdict-end -->
EOF
)"
  comments_fixture 109 "$(comment_item "$ARGUS" "$rev_body" 3011)"

  if [ ! -f "$RECORDER" ]; then
    fail "test_label_sync: $RECORDER does not exist (D8, AT-10)"
    return 1
  fi

  bash "$RECORDER" 109 || { fail "test_label_sync: recorder execution failed"; return 1; }
  grep -q "gh issue edit 109.*--add-label.*argus:findings" "$WRITES" || { fail "test_label_sync: argus:findings label not added (D8)"; return 1; }
  grep -q "gh issue edit 109.*--add-label.*review:2" "$WRITES" || { fail "test_label_sync: review:2 round label not added (D8)"; return 1; }
  pass "test_label_sync (D8, AT-10)"
}

# AT-13 (D4, D5): Merge gate round trip evaluation of Decision-tagged ID
test_merge_gate_round_trip() {
  reset_state
  pr_fixture 110 "$H"
  run_fixture 2011 "$ARGUS" "$H" "pull_request" "completed" "success"

  local rev_body
  rev_body="$(cat <<EOF
### Argus review
<!-- reviewer:argus -->
<!-- run-id:2011 -->
<!-- round:1 -->
<!-- finding:R1-1@D4:high:open:none -->
<!-- failure-scenario:R1-1@D4 -->
Resource leak under concurrency
<!-- review-verdict-end -->
EOF
)"
  comments_fixture 110 "$(comment_item "$ARGUS" "$rev_body" 3012)"

  if [ ! -f "$RECORDER" ]; then
    fail "test_merge_gate_round_trip: $RECORDER does not exist (D4, D5, AT-13)"
    return 1
  fi

  bash "$RECORDER" 110 || { fail "test_merge_gate_round_trip: recorder execution failed"; return 1; }

  # Extract emitted ledger and verify regex matching
  local ledger
  ledger="$(grep -A 20 "consensus-ledger:110" "$WRITES" || true)"
  local parsed
  parsed="$(sed -nE 's/^<!-- ledger-row:([A-Za-z0-9@-]+:(security|high|normal|suggestion):(open|fixed|withdrawn):(pending|agree|dispute|none)) -->$/\1/p' <<<"$ledger")"
  [ "$parsed" = "R1-1@D4:high:open:none" ] || { fail "test_merge_gate_round_trip: pattern replacement failed to emit R1-1@D4:high:open:none"; return 1; }
  pass "test_merge_gate_round_trip (D4, D5, AT-13)"
}

# AT-16 (D4, D7): Atlas carry forward marker retention across commits
test_atlas_carry_forward() {
  reset_state
  pr_fixture 111 "$H"
  # Argus reviewed at H, Atlas previously reviewed at H0
  run_fixture 2012 "$ARGUS" "$H" "pull_request" "completed" "success"

  local existing_ledger
  existing_ledger="$(cat <<EOF
### Findings ledger for #111
<!-- consensus-ledger:111 -->
<!-- assigned:argus,atlas -->
<!-- reviewed-head:atlas:$H0 -->
<!-- consensus-ledger-end -->
EOF
)"
  local argus_rev
  argus_rev="$(cat <<EOF
### Argus review
<!-- reviewer:argus -->
<!-- run-id:2012 -->
<!-- round:1 -->
<!-- review-verdict-end -->
EOF
)"
  comments_fixture 111 \
    "$(comment_item "$THEMIS" "$existing_ledger" 5002)" \
    "$(comment_item "$ARGUS" "$argus_rev" 3013)"

  if [ ! -f "$RECORDER" ]; then
    fail "test_atlas_carry_forward: $RECORDER does not exist (D4, D7, AT-16)"
    return 1
  fi

  bash "$RECORDER" 111 || { fail "test_atlas_carry_forward: recorder execution failed"; return 1; }
  grep -q "reviewed-head:argus:$H" "$WRITES" || { fail "test_atlas_carry_forward: argus head at $H missing"; return 1; }
  grep -q "reviewed-head:atlas:$H0" "$WRITES" || { fail "test_atlas_carry_forward: atlas carry-forward head $H0 was dropped (D4, D7)"; return 1; }
  pass "test_atlas_carry_forward (D4, D7, AT-16)"
}

# AT-17 (D3): Workflow dispatch provenance validation
test_provenance_workflow_dispatch() {
  reset_state
  pr_fixture 112 "$H"
  run_fixture 2013 "$ARGUS" "$H" "workflow_dispatch" "completed" "success"

  local rev_body
  rev_body="$(cat <<EOF
### Argus review
<!-- reviewer:argus -->
<!-- run-id:2013 -->
<!-- round:1 -->
<!-- finding:R1-1@D4:normal:open:none -->
<!-- review-verdict-end -->
EOF
)"
  comments_fixture 112 "$(comment_item "$ARGUS" "$rev_body" 3014)"

  if [ ! -f "$RECORDER" ]; then
    fail "test_provenance_workflow_dispatch: $RECORDER does not exist (D3, AT-17)"
    return 1
  fi

  bash "$RECORDER" 112 || { fail "test_provenance_workflow_dispatch: recorder execution failed"; return 1; }
  grep -q "ledger-row:R1-1@D4:normal:open:none" "$WRITES" || { fail "test_provenance_workflow_dispatch: workflow_dispatch review was refused (D3)"; return 1; }
  pass "test_provenance_workflow_dispatch (D3, AT-17)"
}

# AT-18 (D4): Wire format assigned reviewers marker verification
test_wire_format_assigned() {
  reset_state
  pr_fixture 113 "$H"
  run_fixture 2014 "$ARGUS" "$H" "pull_request" "completed" "success"

  local rev_body
  rev_body="$(cat <<EOF
### Argus review
<!-- reviewer:argus -->
<!-- run-id:2014 -->
<!-- round:1 -->
<!-- review-verdict-end -->
EOF
)"
  comments_fixture 113 "$(comment_item "$ARGUS" "$rev_body" 3015)"

  if [ ! -f "$RECORDER" ]; then
    fail "test_wire_format_assigned: $RECORDER does not exist (D4, AT-18)"
    return 1
  fi

  bash "$RECORDER" 113 || { fail "test_wire_format_assigned: recorder execution failed"; return 1; }
  grep -q "<!-- assigned:argus,atlas -->" "$WRITES" || { fail "test_wire_format_assigned: assigned marker missing in emitted ledger (D4)"; return 1; }
  pass "test_wire_format_assigned (D4, AT-18)"
}

# --- Test Runner ---

TESTS=(
  test_marker_parsing
  test_provenance_validation
  test_ledger_comment_lifecycle
  test_high_failure_scenario_demotion
  test_non_enum_severity_refusal
  test_round_funnel
  test_security_dual_agreement
  test_owner_retier
  test_label_sync
  test_merge_gate_round_trip
  test_atlas_carry_forward
  test_provenance_workflow_dispatch
  test_wire_format_assigned
)

TOTAL=0
PASSED=0
FAILED=0

for t in "${TESTS[@]}"; do
  if [ -n "$FILTER" ] && [[ "$t" != *"$FILTER"* ]]; then
    continue
  fi
  TOTAL=$((TOTAL + 1))
  banner "$t"
  if "$t"; then
    PASSED=$((PASSED + 1))
  else
    FAILED=$((FAILED + 1))
  fi
done

echo
echo "review_recorder_test.sh results: $PASSED passed, $FAILED failed out of $TOTAL run"

if [ "$TOTAL" -eq 0 ]; then
  echo "ERROR: no tests matched filter '$FILTER'" >&2
  exit 1
fi

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi

exit 0
