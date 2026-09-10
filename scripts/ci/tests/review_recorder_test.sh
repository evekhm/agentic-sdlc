#!/usr/bin/env bash
# Tests for scripts/ci/review_recorder.sh (#267).
#
#   bash scripts/ci/tests/review_recorder_test.sh [-k <filter>]
#
# Hermetic: a stub `gh` first on PATH answers reads from fixture files
# under $FX and records writes in $WRITES; a stub `python3` answers
# helper checks. No network, no live tokens.
#
# Each test asserts behaviors derived from numbered Decisions (D1-D10)
# and Acceptance criteria (AT-2..AT-18 for #267; AT-291-1..AT-291-11 for #291).
# Contract tests fail (RED) when required behavior has not yet been implemented.

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
export GITHUB_RUN_ID=999
export MERGE_STATE_RETRY_SLEEP=0

THEMIS="evekhm-themis-app[bot]"
ARGUS="evekhm-argus-app[bot]"
ATLAS="evekhm-atlas-app[bot]"
ACTIONS="github-actions[bot]"
H="$(printf 'a%.0s' {1..40})"
H0="$(printf 'b%.0s' {1..40})"
export THEMIS H

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
      --body-file|--input)
        [ -f "$a" ] && cat "$a" >> "$WRITES"
        ;;
      -F|--field)
        case "$a" in
          body=@*)
            f="${a#body=@}"
            [ -f "$f" ] && cat "$f" >> "$WRITES"
            ;;
          body=*)
            printf '%s\n' "${a#body=}" >> "$WRITES"
            ;;
        esac
        ;;
      -f)
        case "$a" in
          body=*)
            printf '%s\n' "${a#body=}" >> "$WRITES"
            ;;
        esac
        ;;
    esac
    case "$a" in
      --body-file=*)
        f="${a#--body-file=}"
        [ -f "$f" ] && cat "$f" >> "$WRITES"
        ;;
      --input=*)
        f="${a#--input=}"
        [ -f "$f" ] && cat "$f" >> "$WRITES"
        ;;
    esac
    prev="$a"
  done
}

case "${1:-} ${2:-}" in
  "pr view")
    n="$3"
    if [ -f "$FX/pr-$n.fail" ]; then
      echo "gh: API error (HTTP 500) fetching pull request #$n" >&2
      exit 1
    fi
    if [ -f "$FX/pr-$n.flip_hold" ]; then
      cnt_file="$FX/pr-$n.view_count"
      cnt=0
      [ -f "$cnt_file" ] && cnt="$(cat "$cnt_file")"
      echo $((cnt + 1)) > "$cnt_file"
      if [ "$cnt" -ge 1 ]; then
        jq '.labels = [{"name":"hold"}]' "$FX/pr-$n.json"
        exit 0
      fi
    fi
    [ -f "$FX/pr-$n.json" ] && { cat "$FX/pr-$n.json"; exit 0; }
    echo "no pull request fixture $n" >&2; exit 1;;
  "issue view")
    n="$3"
    if [ -f "$FX/issue-$n.fail" ]; then
      echo "gh: API error (HTTP 500) fetching issue #$n" >&2
      exit 1
    fi
    if [ -f "$FX/issue-$n.not_found" ]; then
      echo "GraphQL: Could not resolve to an issue or pull request with the number of $n. (repository.issue)" >&2
      exit 1
    fi
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
    pr=""
    args=("$@")
    for ((i = 0; i < ${#args[@]}; i++)); do
      if [ "${args[$i]}" = "-F" ] && [[ "${args[$((i + 1))]:-}" == pr=* ]]; then
        pr="${args[$((i + 1))]#pr=}"
      fi
    done
    [ -n "$pr" ] || { echo "gh stub: graphql call missing -F pr=" >&2; exit 1; }
    if [ -f "$FX/mergestate-$pr.unreadable" ]; then exit 1; fi
    if [ ! -f "$FX/mergestate-$pr.state" ]; then
      echo '{"data":{"repository":{"pullRequest":null}}}'; exit 0
    fi
    cnt_file="$FX/mergestate-$pr.count"
    n=0; [ -f "$cnt_file" ] && n="$(cat "$cnt_file")"
    echo $((n + 1)) > "$cnt_file"
    mapfile -t states < "$FX/mergestate-$pr.state"
    idx="$n"; [ "$idx" -lt "${#states[@]}" ] || idx=$((${#states[@]} - 1))
    state="${states[$idx]}"
    checks_json="[]"
    if [ -f "$FX/mergestate-$pr.checks" ]; then
      checks_json="$(while IFS='|' read -r ty name val runid; do
        [ -n "$ty" ] || continue
        if [ "$ty" = check ]; then
          if [ -n "$runid" ]; then
            jq -nc --arg n "$name" --arg c "$val" --argjson r "$runid" \
              '{__typename:"CheckRun", name:$n, conclusion:$c, checkSuite:{workflowRun:{databaseId:$r}}}'
          else
            jq -nc --arg n "$name" --arg c "$val" \
              '{__typename:"CheckRun", name:$n, conclusion:$c, checkSuite:{workflowRun:null}}'
          fi
        else
          jq -nc --arg n "$name" --arg s "$val" '{__typename:"StatusContext", context:$n, state:$s}'
        fi
      done < "$FX/mergestate-$pr.checks" | jq -s .)"
    fi
    jq -nc --arg ms "$state" --argjson checks "$checks_json" \
      '{data: {repository: {pullRequest: {mergeStateStatus: $ms, commits: {nodes: [{commit: {statusCheckRollup: {contexts: {nodes: $checks}}}}]}}}}}'
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
    repos/*/pulls/*/commits)
      n="${p#*/pulls/}"; n="${n%/commits}"
      if [ -f "$FX/commits-$n.json" ]; then cat "$FX/commits-$n.json"; else jq -nc --arg h "$H" '[{sha: $h}]'; fi
      exit 0;;
    repos/*/collaborators/*/permission)
      user="${p##*/}"
      user="${user%%\?*}"
      if [ -f "$FX/perm-$user.json" ]; then cat "$FX/perm-$user.json"; else echo '{"permission":"write"}'; fi
      exit 0;;
    *)
      echo '{}'; exit 0;;
  esac
fi

exit 0
STUB
chmod +x "$WORK/bin/gh"

# python3 stub for hermetic loop limits resolution
cat > "$WORK/bin/python3" <<'STUB'
#!/usr/bin/env bash
if [ "${2:-}" = "--loop" ]; then
  [ -f "$FX/loop-$3" ] || exit 1
  cat "$FX/loop-$3"; exit 0
fi
exec /usr/bin/python3 "$@"
STUB
chmod +x "$WORK/bin/python3"

# Fixture helpers
reset_state() {
  rm -rf "$FX"
  mkdir -p "$FX"
  : > "$WRITES"
  : > "$INVOKES"
}

loop_limits() { # <autonomous> <max-dispatch> <max-cost>
  printf '%s\n' "$1" > "$FX/loop-autonomous_merge"
  printf '%s\n' "$2" > "$FX/loop-max_rung_dispatches_per_issue"
  printf '%s\n' "$3" > "$FX/loop-max_cost_usd_per_issue"
}

pr_fixture() { # <number> <head_sha> [author] [commits_json] [closing_issues_json]
  local num="$1" head="${2:-$H}" author="${3:-evekhm-odyssey-app[bot]}"
  local commits_json
  if [ "$#" -ge 4 ] && [ -n "${4:-}" ]; then
    commits_json="$4"
  else
    commits_json="$(jq -nc --arg h "$head" '[{sha: $h}]')"
  fi
  local closing_json="${5:-[]}"
  jq -nc --argjson n "$num" --arg head "$head" --arg author "$author" \
    --arg hr "$GITHUB_REPOSITORY" --argjson commits "$commits_json" \
    --argjson closing "$closing_json" \
    '{number: $n, state: "OPEN", body: "Refs #267", author: {login: $author},
      headRefName: "odyssey/267-feature", headRefOid: $head,
      headRepository: {nameWithOwner: $hr}, baseRefName: "main",
      commits: $commits,
      labels: [],
      closingIssuesReferences: ($closing | map({number: .}))}' > "$FX/pr-$num.json"
  echo "$commits_json" > "$FX/commits-$num.json"
}

issue_fixture() { # <number> [label ...]
  local n="$1"; shift
  printf '%s\n' "$@" | jq -R 'select(length > 0) | {name: .}' | jq -sc --argjson n "$n" '{number: $n, labels: .}' > "$FX/issue-$n.json"
}

comment_item() { # <login> <body> <id> [association] [type]
  local l="$1" b="$2" i="$3" assoc="${4:-COLLABORATOR}" t="${5:-Bot}"
  jq -nc --arg l "$l" --arg b "$b" --argjson i "$i" --arg assoc "$assoc" --arg t "$t" \
    '{id: $i, user: {login: $l, type: $t}, body: $b, author_association: $assoc, created_at: "2026-09-09T08:00:00Z"}'
}

comments_fixture() { # <pr_number> <comment_json>...
  local pr="$1"; shift
  printf '%s\n' "$@" | jq -sc . > "$FX/comments-$pr.json"
}

run_fixture() { # <run_id> <actor> <head_sha> <event> <status> <conclusion> [workflow_path] [repo_full_name]
  local rid="$1" actor="$2" head="$3" ev="$4" status="$5" concl="$6"
  local wpath="${7:-.github/workflows/unattended.yml}"
  local rname="${8:-$GITHUB_REPOSITORY}"
  local c_val
  if [ "$concl" = "null" ]; then c_val="null"; else c_val="\"$concl\""; fi
  jq -nc --argjson rid "$rid" --arg actor "$actor" --arg head "$head" \
    --arg ev "$ev" --arg status "$status" --argjson concl "$c_val" \
    --arg hr "$rname" --arg p "$wpath" \
    '{id: $rid, name: "unattended", head_sha: $head, event: $ev, status: $status,
      conclusion: $concl, actor: {login: $actor}, path: $p,
      head_repository: {full_name: $hr}}' > "$FX/run-$rid.json"
}

mergestate_fixture() { # <pr> <state> [state ...]
  local pr="$1"; shift
  printf '%s\n' "$@" > "$FX/mergestate-$pr.state"
}

mergestate_checks() { # <pr> <row>...
  local pr="$1"; shift
  printf '%s\n' "$@" > "$FX/mergestate-$pr.checks"
}

row() { printf '%s|%s|%s|%s' "$1" "$2" "$3" "$4"; }

GREEN_CHECKS=(
  "$(row check merge-gate '' 999)"
  "$(row check 'execution bindings' SUCCESS 1001)"
  "$(row status 'argus via gh-actions' SUCCESS '')"
)

GREEN_LOOP_ROWS=(
  "dispatch rung:2 head-oid:$H0 event:e1 pr:11 at:2026-01-01T00:00:00Z cost:5.00"
  "dispatch rung:3 head-oid:$H0 event:e2 pr:12 at:2026-01-02T00:00:00Z cost:5.00"
  "dispatch rung:4 head-oid:$H0 event:e3 pr:13 at:2026-01-03T00:00:00Z cost:10.00"
)

loop_ledger() { # <issue> [row-text ...]
  local n="$1"; shift
  local out="### Loop ledger for #$n"$'\n'$'\n'"<!-- loop-ledger:$n -->"
  local r; for r in "$@"; do out="$out"$'\n'"- row <!-- loop-ledger-row: $r -->"; done
  printf '%s\n%s\n' "$out" "<!-- loop-ledger-end -->"
}

consensus_ledger() { # <pr> <argus-oid|-> <atlas-oid|-> [row ...]
  local pr="$1" a="$2" b="$3"; shift 3
  local out="### Findings ledger for #$pr"$'\n'"<!-- consensus-ledger:$pr -->"
  out="$out"$'\n'"<!-- assigned:argus,atlas -->"
  [ "$a" = - ] || out="$out"$'\n'"<!-- reviewed-head:argus:$a -->"
  [ "$b" = - ] || out="$out"$'\n'"<!-- reviewed-head:atlas:$b -->"
  local r; for r in "$@"; do out="$out"$'\n'"<!-- ledger-row:$r -->"; done
  printf '%s\n%s\n' "$out" "<!-- consensus-ledger-end -->"
}

run_gate() { # <pr_number>
  local pr="$1"
  loop_limits true 12 50.00
  mergestate_fixture "$pr" CLEAN
  mergestate_checks "$pr" "${GREEN_CHECKS[@]}"
  issue_fixture 267 status:implementing
  comments_fixture 267 "$(comment_item "$THEMIS" "$(loop_ledger 267 "${GREEN_LOOP_ROWS[@]}")" 700 "COLLABORATOR" "Bot")"
  bash "$GATE" "$pr" 2>&1
}

# --- Test Scenarios ---

# AT-2 (D2, D10): Marker parsing, Decision-ID @<Dn> extraction, sibling failure-scenario
test_marker_parsing() {
  reset_state
  pr_fixture 101 "$H"
  run_fixture 2001 "$ARGUS" "$H" "pull_request" "completed" "success"
  run_fixture 2002 "$ATLAS" "$H" "pull_request" "completed" "success"

  local argus_rev atlas_rev human_comment bot_comment
  argus_rev="$(cat <<EOF
### Argus review
<!-- review-verdict:argus:findings -->
<!-- reviewed-head:$H -->
<!-- run-id:2001 -->
<!-- round:1 -->
<!-- finding:R1-1@D4:high:open:none -->
<!-- failure-scenario:R1-1@D4 -->
State machine deadlocks when worker receives shutdown signal
<!-- review-verdict-end -->
EOF
)"
  atlas_rev="$(cat <<EOF
### Atlas review
<!-- review-verdict:atlas:clean -->
<!-- reviewed-head:$H -->
<!-- run-id:2002 -->
<!-- round:1 -->
<!-- review-verdict-end -->
EOF
)"
  human_comment="LGTM! Please verify the test output before merging."
  bot_comment="Workflow run completed successfully. Artifacts available for download."

  comments_fixture 101 \
    "$(comment_item "$ARGUS" "$argus_rev" 3001)" \
    "$(comment_item "$ATLAS" "$atlas_rev" 3002)" \
    "$(comment_item "alice" "$human_comment" 3003 "CONTRIBUTOR" "User")" \
    "$(comment_item "$ACTIONS" "$bot_comment" 3004 "NONE" "Bot")"

  if [ ! -f "$RECORDER" ]; then
    fail "test_marker_parsing: $RECORDER does not exist (D2, D10, AT-2)"
    return 1
  fi

  bash "$RECORDER" 101 || { fail "test_marker_parsing: recorder failed (D2, D10)"; return 1; }
  grep -q "ledger-row:R1-1@D4:high:open:none" "$WRITES" || { fail "test_marker_parsing: row with @D4 not written (D2, D5)"; return 1; }
  grep -q "reviewed-head:argus:$H" "$WRITES" || { fail "test_marker_parsing: argus head not recorded (D2, D4)"; return 1; }
  grep -q "reviewed-head:atlas:$H" "$WRITES" || { fail "test_marker_parsing: atlas head not recorded (D2, D4)"; return 1; }

  # Commit validation refusal scenario: reviewed-head absent from PR commits list
  local invalid_head_rev
  invalid_head_rev="$(cat <<EOF
### Argus review
<!-- review-verdict:argus:findings -->
<!-- reviewed-head:$H0 -->
<!-- run-id:2001 -->
<!-- round:1 -->
<!-- finding:R1-2@D4:high:open:none -->
<!-- failure-scenario:R1-2@D4 -->
Foreign commit issue
<!-- review-verdict-end -->
EOF
)"
  : > "$WRITES"
  comments_fixture 101 "$(comment_item "$ARGUS" "$invalid_head_rev" 3005)"
  bash "$RECORDER" 101 || { fail "test_marker_parsing: recorder must exit 0 on foreign commit refusal (D2)"; return 1; }
  grep -q "\[refused:.*\]" "$WRITES" || { fail "test_marker_parsing: foreign commit audit note missing (D2)"; return 1; }
  grep -q "reviewed-head:argus:$H0" "$WRITES" && { fail "test_marker_parsing: foreign commit head marker was written (D2)"; return 1; }

  pass "test_marker_parsing (D2, D10, AT-2)"
}

# AT-3 (D2, D3): Provenance validation, action pinning, marker withdrawal
test_provenance_validation() {
  reset_state
  pr_fixture 102 "$H"

  local valid_rev
  valid_rev="$(cat <<EOF
### Argus review
<!-- review-verdict:argus:findings -->
<!-- reviewed-head:$H -->
<!-- run-id:2010 -->
<!-- round:1 -->
<!-- finding:R1-1@D4:high:open:none -->
<!-- failure-scenario:R1-1@D4 -->
Deadlock scenario
<!-- review-verdict-end -->
EOF
)"

  if [ ! -f "$RECORDER" ]; then
    fail "test_provenance_validation: $RECORDER does not exist (D3, AT-3)"
    return 1
  fi

  # Case 1: Accepting case
  run_fixture 2010 "$ARGUS" "$H" "pull_request" "in_progress" "null"
  comments_fixture 102 "$(comment_item "$ARGUS" "$valid_rev" 3010)"
  bash "$RECORDER" 102 || { fail "test_provenance_validation: authentic run should succeed (D3)"; return 1; }
  grep -q "ledger-row:R1-1@D4:high:open:none" "$WRITES" || { fail "test_provenance_validation: authentic row missing (D3)"; return 1; }

  # Case 2a: Refusal - head_sha mismatch
  : > "$WRITES"
  run_fixture 2011 "$ARGUS" "$H0" "pull_request" "in_progress" "null"
  local rev_mismatch_sha
  rev_mismatch_sha="$(cat <<EOF
### Argus review
<!-- review-verdict:argus:findings -->
<!-- reviewed-head:$H -->
<!-- run-id:2011 -->
<!-- round:1 -->
<!-- finding:R1-2@D4:high:open:none -->
<!-- failure-scenario:R1-2@D4 -->
Mismatched head sha
<!-- review-verdict-end -->
EOF
)"
  comments_fixture 102 "$(comment_item "$ARGUS" "$rev_mismatch_sha" 3011)"
  bash "$RECORDER" 102 || { fail "test_provenance_validation: recorder should exit 0 on head_sha mismatch (D3)"; return 1; }
  grep -q "ledger-row:R1-2@D4" "$WRITES" && { fail "test_provenance_validation: mismatched head_sha row accepted (D3)"; return 1; }
  grep -q "\[refused:.*\]" "$WRITES" || { fail "test_provenance_validation: head_sha mismatch audit note missing (D3)"; return 1; }

  # Case 2b: Refusal - workflow path mismatch
  : > "$WRITES"
  run_fixture 2012 "$ARGUS" "$H" "pull_request" "in_progress" "null" ".github/workflows/other.yml"
  local rev_mismatch_path
  rev_mismatch_path="$(cat <<EOF
### Argus review
<!-- review-verdict:argus:findings -->
<!-- reviewed-head:$H -->
<!-- run-id:2012 -->
<!-- round:1 -->
<!-- finding:R1-3@D4:high:open:none -->
<!-- failure-scenario:R1-3@D4 -->
Mismatched workflow path
<!-- review-verdict-end -->
EOF
)"
  comments_fixture 102 "$(comment_item "$ARGUS" "$rev_mismatch_path" 3012)"
  bash "$RECORDER" 102 || { fail "test_provenance_validation: recorder should exit 0 on path mismatch (D3)"; return 1; }
  grep -q "ledger-row:R1-3@D4" "$WRITES" && { fail "test_provenance_validation: mismatched path row accepted (D3)"; return 1; }
  grep -q "\[refused:.*\]" "$WRITES" || { fail "test_provenance_validation: path mismatch audit note missing (D3)"; return 1; }

  # Case 2c: Refusal - head_repository full_name mismatch
  : > "$WRITES"
  run_fixture 2013 "$ARGUS" "$H" "pull_request" "in_progress" "null" ".github/workflows/unattended.yml" "fork-org/agentic-sdlc"
  local rev_mismatch_repo
  rev_mismatch_repo="$(cat <<EOF
### Argus review
<!-- review-verdict:argus:findings -->
<!-- reviewed-head:$H -->
<!-- run-id:2013 -->
<!-- round:1 -->
<!-- finding:R1-4@D4:high:open:none -->
<!-- failure-scenario:R1-4@D4 -->
Mismatched repository
<!-- review-verdict-end -->
EOF
)"
  comments_fixture 102 "$(comment_item "$ARGUS" "$rev_mismatch_repo" 3013)"
  bash "$RECORDER" 102 || { fail "test_provenance_validation: recorder should exit 0 on repo mismatch (D3)"; return 1; }
  grep -q "ledger-row:R1-4@D4" "$WRITES" && { fail "test_provenance_validation: mismatched repo row accepted (D3)"; return 1; }
  grep -q "\[refused:.*\]" "$WRITES" || { fail "test_provenance_validation: repo mismatch audit note missing (D3)"; return 1; }

  # Case 2d: Refusal - event mismatch
  : > "$WRITES"
  run_fixture 2014 "$ARGUS" "$H" "push" "completed" "success"
  local rev_mismatch_event
  rev_mismatch_event="$(cat <<EOF
### Argus review
<!-- review-verdict:argus:findings -->
<!-- reviewed-head:$H -->
<!-- run-id:2014 -->
<!-- round:1 -->
<!-- finding:R1-5@D4:high:open:none -->
<!-- failure-scenario:R1-5@D4 -->
Mismatched event trigger
<!-- review-verdict-end -->
EOF
)"
  comments_fixture 102 "$(comment_item "$ARGUS" "$rev_mismatch_event" 3014)"
  bash "$RECORDER" 102 || { fail "test_provenance_validation: recorder should exit 0 on event mismatch (D3)"; return 1; }
  grep -q "ledger-row:R1-5@D4" "$WRITES" && { fail "test_provenance_validation: mismatched event row accepted (D3)"; return 1; }
  grep -q "\[refused:.*\]" "$WRITES" || { fail "test_provenance_validation: event mismatch audit note missing (D3)"; return 1; }

  # Case 3: Marker withdrawal on check_suite completed with failure or cancelled
  local existing_ledger
  existing_ledger="$(cat <<EOF
### Findings ledger for #102
<!-- consensus-ledger:102 -->
<!-- assigned:argus,atlas -->
<!-- reviewed-head:argus:$H0 -->
<!-- ledger-row:R1-1@D4:high:open:none -->
<!-- consensus-ledger-end -->
EOF
)"
  # Withdrawal on failure
  run_fixture 2015 "$ARGUS" "$H" "pull_request" "completed" "failure"
  local rev_failed_run
  rev_failed_run="$(cat <<EOF
### Argus review
<!-- review-verdict:argus:findings -->
<!-- reviewed-head:$H -->
<!-- run-id:2015 -->
<!-- round:1 -->
<!-- finding:R1-1@D4:high:open:none -->
<!-- failure-scenario:R1-1@D4 -->
Failure scenario
<!-- review-verdict-end -->
EOF
)"
  : > "$WRITES"
  comments_fixture 102 \
    "$(comment_item "$THEMIS" "$existing_ledger" 5001)" \
    "$(comment_item "$ARGUS" "$rev_failed_run" 3015)"
  bash "$RECORDER" 102 || { fail "test_provenance_validation: withdrawal on failure failed"; return 1; }
  grep -q "reviewed-head:argus:$H0" "$WRITES" || { fail "test_provenance_validation: head marker did not revert to $H0 on failure (D3)"; return 1; }
  grep -q "ledger-row:R1-1@D4:high:open:none" "$WRITES" || { fail "test_provenance_validation: row did not survive withdrawal (D3)"; return 1; }
  grep -q "\[run 2015 ended failure; verdict withdrawn\]" "$WRITES" || { fail "test_provenance_validation: failure withdrawal note missing (D3)"; return 1; }
  grep -q "gh issue edit 102.*--add-label.*review:verifying" "$WRITES" || { fail "test_provenance_validation: review:verifying label not added when PR head is newer than reviewed head (D8)"; return 1; }

  # Withdrawal on cancelled
  run_fixture 2016 "$ARGUS" "$H" "pull_request" "completed" "cancelled"
  local rev_cancelled_run
  rev_cancelled_run="$(cat <<EOF
### Argus review
<!-- review-verdict:argus:findings -->
<!-- reviewed-head:$H -->
<!-- run-id:2016 -->
<!-- round:1 -->
<!-- finding:R1-1@D4:high:open:none -->
<!-- failure-scenario:R1-1@D4 -->
Failure scenario
<!-- review-verdict-end -->
EOF
)"
  : > "$WRITES"
  comments_fixture 102 \
    "$(comment_item "$THEMIS" "$existing_ledger" 5001)" \
    "$(comment_item "$ARGUS" "$rev_cancelled_run" 3016)"
  bash "$RECORDER" 102 || { fail "test_provenance_validation: withdrawal on cancelled failed"; return 1; }
  grep -q "reviewed-head:argus:$H0" "$WRITES" || { fail "test_provenance_validation: head marker did not revert to $H0 on cancelled (D3)"; return 1; }
  grep -q "ledger-row:R1-1@D4:high:open:none" "$WRITES" || { fail "test_provenance_validation: row did not survive withdrawal on cancelled (D3)"; return 1; }
  grep -q "\[run 2016 ended cancelled; verdict withdrawn\]" "$WRITES" || { fail "test_provenance_validation: cancelled withdrawal note missing (D3)"; return 1; }

  pass "test_provenance_validation (D2, D3, AT-3)"
}

# AT-4 (D1, D4): Single consensus ledger comment lifecycle (POST, idempotent no-op, then PATCH)
test_ledger_comment_lifecycle() {
  reset_state
  pr_fixture 103 "$H"
  run_fixture 2003 "$ARGUS" "$H" "pull_request" "completed" "success"

  local rev_body
  rev_body="$(cat <<EOF
### Argus review
<!-- review-verdict:argus:findings -->
<!-- reviewed-head:$H -->
<!-- run-id:2003 -->
<!-- round:1 -->
<!-- finding:R1-1@D4:normal:open:none -->
<!-- review-verdict-end -->
EOF
)"
  comments_fixture 103 "$(comment_item "$ARGUS" "$rev_body" 3003)"

  if [ ! -f "$RECORDER" ]; then
    fail "test_ledger_comment_lifecycle: $RECORDER does not exist (D1, D4, AT-4)"
    return 1
  fi

  # Pass 1: initial creation calls POST
  bash "$RECORDER" 103 || { fail "test_ledger_comment_lifecycle: pass 1 failed"; return 1; }
  grep -q "gh api.*POST.*repos/.*/issues/103/comments" "$WRITES" || { fail "test_ledger_comment_lifecycle: POST not called on initial creation (D4)"; return 1; }

  # Pass 2a: Byte-identical re-derivation skips PATCH on the ledger comment (D1 idempotency guard). Comment writes and label writes are separate streams; label synchronization may execute while comment PATCH is skipped.
  local ledger_comment
  ledger_comment="$(awk '/^### Findings ledger for #103/ {f = 1} /^gh / {if (f) exit} f' "$WRITES")"
  [ -n "$ledger_comment" ] || ledger_comment="$(cat <<EOF
### Findings ledger for #103
<!-- consensus-ledger:103 -->
<!-- assigned:argus,atlas -->
<!-- reviewed-head:argus:$H -->
<!-- ledger-row:R1-1@D4:normal:open:none -->
<!-- consensus-ledger-end -->
EOF
)"
  comment_item "$THEMIS" "$ledger_comment" 5001 > "$FX/comment-5001.json"
  comments_fixture 103 \
    "$(comment_item "$THEMIS" "$ledger_comment" 5001)" \
    "$(comment_item "$ARGUS" "$rev_body" 3003)"

  : > "$WRITES"
  bash "$RECORDER" 103 || { fail "test_ledger_comment_lifecycle: pass 2a failed"; return 1; }
  grep -q "^gh api.*PATCH.*repos/.*/issues/comments/5001" "$WRITES" && { fail "test_ledger_comment_lifecycle: PATCH must not be called when body is byte-identical (D1)"; return 1; }

  # Pass 2b: Differing render executes exactly one PATCH call (D4)
  local stale_ledger_comment
  stale_ledger_comment="$(cat <<EOF
### Findings ledger for #103
<!-- consensus-ledger:103 -->
<!-- assigned:argus,atlas -->
<!-- reviewed-head:argus:$H0 -->
<!-- consensus-ledger-end -->
EOF
)"
  comment_item "$THEMIS" "$stale_ledger_comment" 5001 > "$FX/comment-5001.json"
  comments_fixture 103 \
    "$(comment_item "$THEMIS" "$stale_ledger_comment" 5001)" \
    "$(comment_item "$ARGUS" "$rev_body" 3003)"

  : > "$WRITES"
  bash "$RECORDER" 103 || { fail "test_ledger_comment_lifecycle: pass 2b failed"; return 1; }
  local patch_count
  patch_count="$(grep -c "^gh api.*PATCH.*repos/.*/issues/comments/5001" "$WRITES" || true)"
  [ "$patch_count" -eq 1 ] || { fail "test_ledger_comment_lifecycle: expected exactly 1 PATCH call on differing render, got $patch_count (D4)"; return 1; }

  # Guard 3: Sender is Themis App login -> skip execution entirely (D1)
  : > "$WRITES"
  GITHUB_EVENT_SENDER_LOGIN="$THEMIS" bash "$RECORDER" 103 || { fail "test_ledger_comment_lifecycle: themis sender guard failed"; return 1; }
  [ ! -s "$WRITES" ] || { fail "test_ledger_comment_lifecycle: writes attempted when sender is themis (D1)"; return 1; }

  pass "test_ledger_comment_lifecycle (D1, D4, AT-4)"
}

# AT-5 (D5) / AT-291-4 (D4): High finding without failure_scenario demoted to normal with finding ID attribution
test_high_failure_scenario_demotion() {
  reset_state
  pr_fixture 104 "$H"
  run_fixture 2004 "$ARGUS" "$H" "pull_request" "completed" "success"

  local rev_body
  rev_body="$(cat <<EOF
### Argus review
<!-- review-verdict:argus:findings -->
<!-- reviewed-head:$H -->
<!-- run-id:2004 -->
<!-- round:1 -->
<!-- finding:R1-2@D5:high:open:none -->
This finding lacks the required failure-scenario marker
<!-- review-verdict-end -->
EOF
)"
  comments_fixture 104 "$(comment_item "$ARGUS" "$rev_body" 3004)"

  if [ ! -f "$RECORDER" ]; then
    fail "test_high_failure_scenario_demotion: $RECORDER does not exist (D5, AT-5, AT-291-4)"
    return 1
  fi

  bash "$RECORDER" 104 || { fail "test_high_failure_scenario_demotion: recorder execution failed"; return 1; }
  grep -q "ledger-row:R1-2@D5:normal:open:none" "$WRITES" || { fail "test_high_failure_scenario_demotion: high was not demoted to normal (D5)"; return 1; }
  grep -q "\[demoted from high: missing failure_scenario marker\] on R1-2@D5" "$WRITES" || { fail "test_high_failure_scenario_demotion: audit note missing finding ID attribution (D4, AT-291-4)"; return 1; }
  pass "test_high_failure_scenario_demotion (D5, AT-5, AT-291-4)"
}

# AT-6 (D5): Non-enum severity refusal (critical, low) logs and creates no row
test_non_enum_severity_refusal() {
  reset_state
  pr_fixture 105 "$H"
  run_fixture 2005 "$ARGUS" "$H" "pull_request" "completed" "success"

  local rev_body
  rev_body="$(cat <<EOF
### Argus review
<!-- review-verdict:argus:findings -->
<!-- reviewed-head:$H -->
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
  grep -q "\[refused: R1-4@D5: invalid severity low\]" "$WRITES" || { fail "test_non_enum_severity_refusal: low audit note missing"; return 1; }
  pass "test_non_enum_severity_refusal (D5, AT-6)"
}

# AT-7 (D6) / AT-291-6 (D6): Round funnel enforcement (rounds 2-3 tracking rows; past round 3 demotion)
test_round_funnel() {
  reset_state
  pr_fixture 106 "$H"
  run_fixture 2006 "$ARGUS" "$H" "pull_request" "completed" "success"

  if [ ! -f "$RECORDER" ]; then
    fail "test_round_funnel: $RECORDER does not exist (D6, AT-7)"
    return 1
  fi

  local prior_ledger
  prior_ledger="$(cat <<EOF
### Findings ledger for #106
<!-- consensus-ledger:106 -->
<!-- assigned:argus,atlas -->
<!-- reviewed-head:argus:$H -->
<!-- reviewed-head:atlas:$H -->
<!-- ledger-row:R1-1@D4:normal:open:none -->
<!-- consensus-ledger-end -->
EOF
)"

  # Round 2: non-blocking observation recorded as normal row with peer none
  comment_item "$THEMIS" "$prior_ledger" 5001 > "$FX/comment-5001.json"
  local rev_r2
  rev_r2="$(cat <<EOF
### Argus review
<!-- review-verdict:argus:findings -->
<!-- reviewed-head:$H -->
<!-- run-id:2006 -->
<!-- round:2 -->
<!-- finding:R2-1:normal:open:none -->
<!-- finding:R2-2:suggestion:open:none -->
<!-- review-verdict-end -->
EOF
)"
  comments_fixture 106 \
    "$(comment_item "$THEMIS" "$prior_ledger" 5001)" \
    "$(comment_item "$ARGUS" "$rev_r2" 3006)"
  bash "$RECORDER" 106 || { fail "test_round_funnel: round 2 recording failed"; return 1; }
  grep -q "ledger-row:R1-1@D4:normal:open:none" "$WRITES" || { fail "test_round_funnel: round 1 row missing from round 2 ledger (D6)"; return 1; }
  grep -q "ledger-row:R2-1:normal:open:none" "$WRITES" || { fail "test_round_funnel: round 2 normal row missing (D6)"; return 1; }
  grep -q "ledger-row:R2-2:normal:open:none" "$WRITES" || { fail "test_round_funnel: round 2 suggestion row did not land as normal tracking row (D6)"; return 1; }

  # Round 3: new high row admitted, new normal observation recorded, suggestion lands normal
  local rev_r3
  rev_r3="$(cat <<EOF
### Argus review
<!-- review-verdict:argus:findings -->
<!-- reviewed-head:$H -->
<!-- run-id:2006 -->
<!-- round:3 -->
<!-- finding:R3-1:high:open:none -->
<!-- failure-scenario:R3-1 -->
Deadlock on termination signal
<!-- finding:R3-2:normal:open:none -->
<!-- finding:R3-3:suggestion:open:none -->
<!-- review-verdict-end -->
EOF
)"
  : > "$WRITES"
  comments_fixture 106 \
    "$(comment_item "$THEMIS" "$prior_ledger" 5001)" \
    "$(comment_item "$ARGUS" "$rev_r3" 3007)"
  bash "$RECORDER" 106 || { fail "test_round_funnel: round 3 recording failed"; return 1; }
  grep -q "ledger-row:R1-1@D4:normal:open:none" "$WRITES" || { fail "test_round_funnel: round 1 row missing from round 3 ledger (D6)"; return 1; }
  grep -q "ledger-row:R3-1:high:open:none" "$WRITES" || { fail "test_round_funnel: round 3 high row refused (D6)"; return 1; }
  grep -q "ledger-row:R3-2:normal:open:none" "$WRITES" || { fail "test_round_funnel: round 3 normal row missing (D6)"; return 1; }
  grep -q "ledger-row:R3-3:normal:open:none" "$WRITES" || { fail "test_round_funnel: round 3 suggestion row did not land as normal tracking row (D6)"; return 1; }

  # Round 4: past round 3, high is demoted to normal; security is admitted
  : > "$WRITES"
  local rev_r4
  rev_r4="$(cat <<EOF
### Argus review
<!-- review-verdict:argus:findings -->
<!-- reviewed-head:$H -->
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
  comments_fixture 106 \
    "$(comment_item "$THEMIS" "$prior_ledger" 5001)" \
    "$(comment_item "$ARGUS" "$rev_r4" 3008)"
  bash "$RECORDER" 106 || { fail "test_round_funnel: round 4 execution failed"; return 1; }
  grep -q "ledger-row:R1-1@D4:normal:open:none" "$WRITES" || { fail "test_round_funnel: round 1 row missing from round 4 ledger (D6)"; return 1; }
  grep -q "ledger-row:R4-1:normal:open:none" "$WRITES" || { fail "test_round_funnel: high finding past round 3 not demoted (D6)"; return 1; }
  grep -q "ledger-row:R4-2:security:open:pending" "$WRITES" || { fail "test_round_funnel: security finding past round 3 refused (D6)"; return 1; }

  pass "test_round_funnel (D6, AT-7, AT-291-6)"
}

# AT-8 (D7): Security dual agreement requirement (existence and fix verification)
test_security_dual_agreement() {
  reset_state
  pr_fixture 107 "$H"
  run_fixture 2007 "$ARGUS" "$H" "pull_request" "completed" "success"
  run_fixture 2008 "$ATLAS" "$H" "pull_request" "completed" "success"

  if [ ! -f "$RECORDER" ]; then
    fail "test_security_dual_agreement: $RECORDER does not exist (D7, AT-8)"
    return 1
  fi

  # Negative Case 1: Initial security finding initializes with peer=pending
  local argus_init
  argus_init="$(cat <<EOF
### Argus review
<!-- review-verdict:argus:findings -->
<!-- reviewed-head:$H -->
<!-- run-id:2007 -->
<!-- round:1 -->
<!-- finding:R1-10:security:open:pending -->
Credential leak in debug log
<!-- review-verdict-end -->
EOF
)"
  comments_fixture 107 "$(comment_item "$ARGUS" "$argus_init" 3007)"
  bash "$RECORDER" 107 || { fail "test_security_dual_agreement: initial security finding recording failed"; return 1; }
  grep -q "ledger-row:R1-10:security:open:pending" "$WRITES" || { fail "test_security_dual_agreement: security row must initialize with peer=pending (D7)"; return 1; }

  # Negative Case 2: Authoring reviewer asserting agree on own finding leaves it pending
  local argus_self_agree
  argus_self_agree="$(cat <<EOF
### Argus review
<!-- review-verdict:argus:findings -->
<!-- reviewed-head:$H -->
<!-- run-id:2007 -->
<!-- round:1 -->
<!-- finding:R1-10:security:open:agree -->
Self agreed finding
<!-- review-verdict-end -->
EOF
)"
  : > "$WRITES"
  comments_fixture 107 "$(comment_item "$ARGUS" "$argus_self_agree" 3008)"
  bash "$RECORDER" 107 || { fail "test_security_dual_agreement: self agree check failed"; return 1; }
  grep -q "ledger-row:R1-10:security:open:pending" "$WRITES" || { fail "test_security_dual_agreement: self agree must leave peer=pending (D7)"; return 1; }

  # Negative Case 3: Author comment asserting fix changes nothing
  : > "$WRITES"
  comments_fixture 107 \
    "$(comment_item "$ARGUS" "$argus_init" 3007)" \
    "$(comment_item "evekhm-odyssey-app[bot]" "I fixed this security vulnerability" 3009 "COLLABORATOR" "Bot")"
  bash "$RECORDER" 107 || { fail "test_security_dual_agreement: author assertion check failed"; return 1; }
  grep -q "ledger-row:R1-10:security:open:pending" "$WRITES" || { fail "test_security_dual_agreement: author comment must not resolve security finding (D7)"; return 1; }

  # Positive Case 1: Peer concurrence on existence advances row to agree
  local atlas_agree_existence
  atlas_agree_existence="$(cat <<EOF
### Atlas review
<!-- review-verdict:atlas:findings -->
<!-- reviewed-head:$H -->
<!-- run-id:2008 -->
<!-- round:1 -->
<!-- finding:R1-10:security:open:agree -->
<!-- review-verdict-end -->
EOF
)"
  : > "$WRITES"
  comments_fixture 107 \
    "$(comment_item "$ARGUS" "$argus_init" 3007)" \
    "$(comment_item "$ATLAS" "$atlas_agree_existence" 3010)"
  bash "$RECORDER" 107 || { fail "test_security_dual_agreement: peer agreement on existence failed"; return 1; }
  grep -q "ledger-row:R1-10:security:open:agree" "$WRITES" || { fail "test_security_dual_agreement: peer concurrence did not advance finding to agree (D7)"; return 1; }

  # Positive Case 2: Fix verification requires dual agreement on fix
  local argus_fix atlas_fix
  argus_fix="$(cat <<EOF
### Argus review
<!-- review-verdict:argus:findings -->
<!-- reviewed-head:$H -->
<!-- run-id:2007 -->
<!-- round:2 -->
<!-- finding:R1-10:security:fixed:pending -->
<!-- review-verdict-end -->
EOF
)"
  atlas_fix="$(cat <<EOF
### Atlas review
<!-- review-verdict:atlas:clean -->
<!-- reviewed-head:$H -->
<!-- run-id:2008 -->
<!-- round:2 -->
<!-- finding:R1-10:security:fixed:agree -->
<!-- review-verdict-end -->
EOF
)"
  : > "$WRITES"
  comments_fixture 107 \
    "$(comment_item "$ARGUS" "$argus_fix" 3011)" \
    "$(comment_item "$ATLAS" "$atlas_fix" 3012)"
  bash "$RECORDER" 107 || { fail "test_security_dual_agreement: fix verification recording failed"; return 1; }
  grep -q "ledger-row:R1-10:security:fixed:agree" "$WRITES" || { fail "test_security_dual_agreement: security dual agreement fix not recorded (D7)"; return 1; }

  pass "test_security_dual_agreement (D7, AT-8)"
}

# AT-9 (D9): Maintainer retier command verification and unauthorized refusal
test_owner_retier() {
  reset_state
  pr_fixture 108 "$H"
  run_fixture 2009 "$ARGUS" "$H" "pull_request" "completed" "success"

  local rev_body
  rev_body="$(cat <<EOF
### Argus review
<!-- review-verdict:argus:findings -->
<!-- reviewed-head:$H -->
<!-- run-id:2009 -->
<!-- round:1 -->
<!-- finding:R1-1@D4:high:open:none -->
<!-- failure-scenario:R1-1@D4 -->
Flaky timeout
<!-- review-verdict-end -->
EOF
)"

  if [ ! -f "$RECORDER" ]; then
    fail "test_owner_retier: $RECORDER does not exist (D9, AT-9)"
    return 1
  fi

  # Authorized retier from OWNER
  local owner_retier_cmd="@argus retier R1-1@D4 normal"
  comments_fixture 108 \
    "$(comment_item "$ARGUS" "$rev_body" 3009)" \
    "$(comment_item "evekhm" "$owner_retier_cmd" 3010 "OWNER" "User")"

  bash "$RECORDER" 108 || { fail "test_owner_retier: recorder execution failed"; return 1; }
  grep -q "ledger-row:R1-1@D4:normal:open:none" "$WRITES" || { fail "test_owner_retier: retier command did not update row severity (D9)"; return 1; }
  grep -q "\[retiered to normal by @evekhm\]" "$WRITES" || { fail "test_owner_retier: retier audit note missing (D9)"; return 1; }

  # Unauthorized retier from non-maintainer
  local unauth_retier_cmd="@argus retier R1-1@D4 suggestion"
  : > "$WRITES"
  comments_fixture 108 \
    "$(comment_item "$ARGUS" "$rev_body" 3009)" \
    "$(comment_item "evekhm" "$owner_retier_cmd" 3010 "OWNER" "User")" \
    "$(comment_item "untrusted-user" "$unauth_retier_cmd" 3011 "NONE" "User")"

  bash "$RECORDER" 108 || { fail "test_owner_retier: unauthorized retier should exit 0 (D9)"; return 1; }
  grep -q "ledger-row:R1-1@D4:suggestion:open:none" "$WRITES" && { fail "test_owner_retier: unauthorized retier updated row severity (D9)"; return 1; }
  grep -q "\[refused:.*untrusted-user.*\]" "$WRITES" || { fail "test_owner_retier: unauthorized retier audit note missing login (D9)"; return 1; }

  pass "test_owner_retier (D9, AT-9)"
}

# AT-10 (D5, D7, D8) / AT-291-1, AT-291-2, AT-291-3, AT-291-5, AT-291-7: Label synchronization via gh issue edit and hold circuit breaker (#291)
test_label_sync() {
  reset_state

  if [ ! -f "$RECORDER" ]; then
    fail "test_label_sync: $RECORDER does not exist (D5, D7, D8, AT-10)"
    return 1
  fi

  # Case (a): PR carrying hold produces zero writes and one log line naming held object (#291, REVIEW.md D13/D14)
  pr_fixture 109 "$H"
  jq '.labels = [{"name":"hold"}]' "$FX/pr-109.json" > "$FX/pr-109.json.tmp"
  mv "$FX/pr-109.json.tmp" "$FX/pr-109.json"
  issue_fixture 109 "hold"

  run_fixture 2010 "$ARGUS" "$H" "pull_request" "completed" "success"
  local rev_body_hold
  rev_body_hold="$(cat <<EOF
### Argus review
<!-- review-verdict:argus:findings -->
<!-- reviewed-head:$H -->
<!-- run-id:2010 -->
<!-- round:2 -->
<!-- finding:R2-1:high:open:none -->
<!-- failure-scenario:R2-1 -->
Crash on invalid utf8 input
<!-- review-verdict-end -->
EOF
)"
  comments_fixture 109 "$(comment_item "$ARGUS" "$rev_body_hold" 3011)"

  local out_a
  out_a="$(bash "$RECORDER" 109 2>&1)" || { fail "test_label_sync: recorder execution failed on held PR (D8, #291)"; return 1; }
  [ ! -s "$WRITES" ] || { fail "test_label_sync: writes attempted when hold label is present (#291)"; return 1; }
  echo "$out_a" | grep -Fq "hold present on #109, recorder writes nothing" || { fail "test_label_sync: log missing held object line for #109 (#291)"; return 1; }

  # Case (b): PR carrying bootstrap and stale review:1 updates labels and preserves bootstrap
  reset_state
  pr_fixture 109 "$H"
  jq '.labels = [{"name":"bootstrap"},{"name":"review:1"}]' "$FX/pr-109.json" > "$FX/pr-109.json.tmp"
  mv "$FX/pr-109.json.tmp" "$FX/pr-109.json"
  issue_fixture 109 "bootstrap" "review:1"

  run_fixture 2010 "$ARGUS" "$H" "pull_request" "completed" "success"

  local rev_body
  rev_body="$(cat <<EOF
### Argus review
<!-- review-verdict:argus:findings -->
<!-- reviewed-head:$H -->
<!-- run-id:2010 -->
<!-- round:2 -->
<!-- finding:R2-1:high:open:none -->
<!-- failure-scenario:R2-1 -->
Crash on invalid utf8 input
<!-- finding:R1-5@D5:suggestion:open:none -->
<!-- finding:R1-6:high:open:dispute -->
<!-- finding:R1-7:high:withdrawn:none -->
<!-- review-verdict-end -->
EOF
)"
  comments_fixture 109 "$(comment_item "$ARGUS" "$rev_body" 3011)"

  bash "$RECORDER" 109 || { fail "test_label_sync: recorder execution failed"; return 1; }

  # Assert labels updated and stale review:1 removed
  grep -q "gh issue edit 109.*--add-label.*argus:findings" "$WRITES" || { fail "test_label_sync: argus:findings label not added (D8)"; return 1; }
  grep -q "gh issue edit 109.*--add-label.*argus:suggestions" "$WRITES" || { fail "test_label_sync: argus:suggestions label not added (D8)"; return 1; }
  grep -q "gh issue edit 109.*--add-label.*review:2" "$WRITES" || { fail "test_label_sync: review:2 round label not added (D8)"; return 1; }
  grep -q "gh issue edit 109.*--remove-label.*review:1" "$WRITES" || { fail "test_label_sync: stale review:1 not removed (D8)"; return 1; }

  # Assert preservation of unrelated labels such as bootstrap
  grep -E "gh issue edit 109.*--remove-label.*bootstrap" "$WRITES" && { fail "test_label_sync: bootstrap label was removed by recorder (D8)"; return 1; }

  # Assert D5 suggestion, dispute, and withdrawn rows present
  grep -q "ledger-row:R1-5@D5:suggestion:open:none" "$WRITES" || { fail "test_label_sync: suggestion row missing (D5)"; return 1; }
  grep -q "ledger-row:R1-6:high:open:dispute" "$WRITES" || { fail "test_label_sync: dispute row missing (D7)"; return 1; }
  grep -q "ledger-row:R1-7:high:withdrawn:none" "$WRITES" || { fail "test_label_sync: withdrawn row missing (D7)"; return 1; }

  # Assert dispute blocks consensus:agreed and sets consensus:disputed
  grep -q "gh issue edit 109.*--add-label.*consensus:disputed" "$WRITES" || { fail "test_label_sync: consensus:disputed label missing on dispute (D8)"; return 1; }
  grep -q "gh issue edit 109.*--add-label.*consensus:agreed" "$WRITES" && { fail "test_label_sync: consensus:agreed added despite dispute (D8)"; return 1; }

  # review:verifying is absent because the PR head ($H) matches the reviewed head ($H); it only triggers when PR head is newer.
  # review:merge-ready is absent because open blocking findings exist and consensus is disputed.
  grep -q "gh issue edit 109.*--add-label.*review:merge-ready" "$WRITES" && { fail "test_label_sync: review:merge-ready added despite open blocking findings and dispute (D8)"; return 1; }
  grep -q "gh issue edit 109.*--add-label.*review:verifying" "$WRITES" && { fail "test_label_sync: review:verifying added when PR head equals reviewed head (D8)"; return 1; }

  # Case (c): PR without hold closing an issue that carries hold produces zero writes and logs held issue (#291, REVIEW.md D13/D14)
  reset_state
  pr_fixture 109 "$H" "" "" '[209]'
  jq '.body = "Closes #209"' "$FX/pr-109.json" > "$FX/pr-109.json.tmp"
  mv "$FX/pr-109.json.tmp" "$FX/pr-109.json"
  issue_fixture 109 "bootstrap"
  issue_fixture 209 "hold"

  run_fixture 2010 "$ARGUS" "$H" "pull_request" "completed" "success"
  comments_fixture 109 "$(comment_item "$ARGUS" "$rev_body_hold" 3011)"

  local out_c
  out_c="$(bash "$RECORDER" 109 2>&1)" || { fail "test_label_sync: recorder execution failed on PR closing held issue (D8, #291)"; return 1; }
  [ ! -s "$WRITES" ] || { fail "test_label_sync: writes attempted when closed issue carries hold (#291)"; return 1; }
  echo "$out_c" | grep -Fq "hold present on #209, recorder writes nothing" || { fail "test_label_sync: log missing held object line for #209 (#291)"; return 1; }

  # Case (d): Monotonic round counter progression (D7, AT-291-7)
  # When PR already has review:2, an earlier round review (round:1) does not decrement review:2 to review:1.
  reset_state
  pr_fixture 110 "$H"
  jq '.labels = [{"name":"review:2"}]' "$FX/pr-110.json" > "$FX/pr-110.json.tmp"
  mv "$FX/pr-110.json.tmp" "$FX/pr-110.json"
  issue_fixture 110 "review:2"

  run_fixture 2011 "$ARGUS" "$H" "pull_request" "completed" "success"
  local rev_body_r1
  rev_body_r1="$(cat <<EOF
### Argus review
<!-- review-verdict:argus:clean -->
<!-- reviewed-head:$H -->
<!-- run-id:2011 -->
<!-- round:1 -->
<!-- review-verdict-end -->
EOF
)"
  comments_fixture 110 "$(comment_item "$ARGUS" "$rev_body_r1" 3012)"

  bash "$RECORDER" 110 || { fail "test_label_sync: recorder execution failed on monotonic round check (D7, AT-291-7)"; return 1; }
  grep -E "gh issue edit 110.*--remove-label.*review:2" "$WRITES" && { fail "test_label_sync: higher round label review:2 was decremented (D7, AT-291-7)"; return 1; }
  grep -E "gh issue edit 110.*--add-label.*review:1" "$WRITES" && { fail "test_label_sync: lower round label review:1 was added over review:2 (D7, AT-291-7)"; return 1; }

  pass "test_label_sync (D5, D7, D8, AT-10, AT-291-1..3, AT-291-5, AT-291-7)"
}

# AT-13 (D4, D5): Merge gate round trip evaluation of Decision-tagged ID
test_merge_gate_round_trip() {
  reset_state
  pr_fixture 110 "$H"
  run_fixture 2011 "$ARGUS" "$H" "pull_request" "completed" "success"
  run_fixture 2012 "$ATLAS" "$H" "pull_request" "completed" "success"

  local argus_rev atlas_rev
  argus_rev="$(cat <<EOF
### Argus review
<!-- review-verdict:argus:findings -->
<!-- reviewed-head:$H -->
<!-- run-id:2011 -->
<!-- round:1 -->
<!-- finding:R1-1@D4:high:fixed:none -->
<!-- failure-scenario:R1-1@D4 -->
Resource leak under concurrency
<!-- review-verdict-end -->
EOF
)"
  atlas_rev="$(cat <<EOF
### Atlas review
<!-- review-verdict:atlas:clean -->
<!-- reviewed-head:$H -->
<!-- run-id:2012 -->
<!-- round:1 -->
<!-- review-verdict-end -->
EOF
)"
  comments_fixture 110 \
    "$(comment_item "$ARGUS" "$argus_rev" 3012)" \
    "$(comment_item "$ATLAS" "$atlas_rev" 3013)"

  if [ ! -f "$RECORDER" ]; then
    fail "test_merge_gate_round_trip: $RECORDER does not exist (D4, D5, AT-13)"
    return 1
  fi

  bash "$RECORDER" 110 || { fail "test_merge_gate_round_trip: recorder execution failed"; return 1; }

  local emitted_ledger
  emitted_ledger="$(awk '/### Findings ledger for #110/ {f = 1} f; /<!-- consensus-ledger-end -->/ {f = 0; exit}' "$WRITES")"
  [ -n "$emitted_ledger" ] || { fail "test_merge_gate_round_trip: emitted ledger not captured in writes (D4)"; return 1; }
  grep -q "gh issue edit 110.*--add-label.*review:merge-ready" "$WRITES" || { fail "test_merge_gate_round_trip: review:merge-ready label not added on clean consensus at current head (D8)"; return 1; }

  # Seed emitted ledger comment and evaluate merge gate hermetically
  comments_fixture 110 "$(comment_item "$THEMIS" "$emitted_ledger" 5001 "COLLABORATOR" "Bot")"
  local gate_out
  gate_out="$(run_gate 110)"
  echo "$gate_out" | grep -q "conjunct (3): true" || { fail "test_merge_gate_round_trip: conjunct 3 not true in gate output"; return 1; }
  echo "$gate_out" | grep -q "conjunct (4): true" || { fail "test_merge_gate_round_trip: conjunct 4 not true in gate output"; return 1; }
  echo "$gate_out" | grep -q "conjunct (5): true" || { fail "test_merge_gate_round_trip: conjunct 5 not true in gate output"; return 1; }
  echo "$gate_out" | grep -q "conjunct (11): true" || { fail "test_merge_gate_round_trip: conjunct 11 not true in gate output"; return 1; }

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
<!-- review-verdict:argus:clean -->
<!-- reviewed-head:$H -->
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

  local emitted_ledger
  emitted_ledger="$(awk '/### Findings ledger for #111/ {f = 1} f; /<!-- consensus-ledger-end -->/ {f = 0; exit}' "$WRITES")"
  [ -n "$emitted_ledger" ] || { fail "test_atlas_carry_forward: emitted ledger not captured in writes (D4)"; return 1; }

  comments_fixture 111 \
    "$(comment_item "$THEMIS" "$emitted_ledger" 5002 "COLLABORATOR" "Bot")" \
    "$(comment_item "$ATLAS" "Atlas previous review" 3001 "COLLABORATOR" "Bot")"
  local gate_out
  gate_out="$(run_gate 111)"
  echo "$gate_out" | grep -q "conjunct (3): true" || { fail "test_atlas_carry_forward: conjunct 3 not true in gate output (D7)"; return 1; }
  echo "$gate_out" | grep -q "argus at $H, atlas carries forward from $H0 (D7)" || { fail "test_atlas_carry_forward: WHY[3] carry forward text missing (D7)"; return 1; }

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
<!-- review-verdict:argus:findings -->
<!-- reviewed-head:$H -->
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

  # Negative Case: Refusal when workflow_dispatch head_sha does not match PR head
  : > "$WRITES"
  run_fixture 2014 "$ARGUS" "$H0" "workflow_dispatch" "completed" "success"
  local rev_mismatch_sha
  rev_mismatch_sha="$(cat <<EOF
### Argus review
<!-- review-verdict:argus:findings -->
<!-- reviewed-head:$H -->
<!-- run-id:2014 -->
<!-- round:1 -->
<!-- finding:R1-2@D4:normal:open:none -->
<!-- review-verdict-end -->
EOF
)"
  comments_fixture 112 "$(comment_item "$ARGUS" "$rev_mismatch_sha" 3015)"
  bash "$RECORDER" 112 || { fail "test_provenance_workflow_dispatch: recorder execution failed on mismatched head_sha (D3)"; return 1; }
  grep -q "ledger-row:R1-2@D4" "$WRITES" && { fail "test_provenance_workflow_dispatch: mismatched head_sha row accepted for workflow_dispatch (D3)"; return 1; }
  grep -q "\[refused:.*\]" "$WRITES" || { fail "test_provenance_workflow_dispatch: head_sha mismatch audit note missing for workflow_dispatch (D3)"; return 1; }

  pass "test_provenance_workflow_dispatch (D3, AT-17)"
}

# AT-18 (D4): Wire format assigned reviewers marker verification
test_wire_format_assigned() {
  reset_state
  pr_fixture 113 "$H"
  run_fixture 2014 "$ARGUS" "$H" "pull_request" "completed" "success"
  run_fixture 2015 "$ATLAS" "$H" "pull_request" "completed" "success"

  local argus_rev atlas_rev
  argus_rev="$(cat <<EOF
### Argus review
<!-- review-verdict:argus:clean -->
<!-- reviewed-head:$H -->
<!-- run-id:2014 -->
<!-- round:1 -->
<!-- review-verdict-end -->
EOF
)"
  atlas_rev="$(cat <<EOF
### Atlas review
<!-- review-verdict:atlas:clean -->
<!-- reviewed-head:$H -->
<!-- run-id:2015 -->
<!-- round:1 -->
<!-- review-verdict-end -->
EOF
)"
  comments_fixture 113 \
    "$(comment_item "$ARGUS" "$argus_rev" 3015)" \
    "$(comment_item "$ATLAS" "$atlas_rev" 3016)"

  if [ ! -f "$RECORDER" ]; then
    fail "test_wire_format_assigned: $RECORDER does not exist (D4, AT-18)"
    return 1
  fi

  bash "$RECORDER" 113 || { fail "test_wire_format_assigned: recorder execution failed"; return 1; }
  grep -q "<!-- assigned:argus,atlas -->" "$WRITES" || { fail "test_wire_format_assigned: assigned marker missing in emitted ledger (D4)"; return 1; }

  local emitted_ledger
  emitted_ledger="$(awk '/### Findings ledger for #113/ {f = 1} f; /<!-- consensus-ledger-end -->/ {f = 0; exit}' "$WRITES")"
  [ -n "$emitted_ledger" ] || { fail "test_wire_format_assigned: emitted ledger not captured in writes (D4)"; return 1; }

  comments_fixture 113 "$(comment_item "$THEMIS" "$emitted_ledger" 5003 "COLLABORATOR" "Bot")"
  local gate_out
  gate_out="$(run_gate 113)"
  echo "$gate_out" | grep -q "conjunct (3): true" || { fail "test_wire_format_assigned: conjunct 3 not true in gate output (D4)"; return 1; }
  echo "$gate_out" | grep -q "conjunct (4): true" || { fail "test_wire_format_assigned: conjunct 4 not true in gate output (D4)"; return 1; }
  echo "$gate_out" | grep -q "conjunct (5): true" || { fail "test_wire_format_assigned: conjunct 5 not true in gate output (D4)"; return 1; }
  echo "$gate_out" | grep -q "conjunct (11): true" || { fail "test_wire_format_assigned: conjunct 11 not true in gate output (D4)"; return 1; }

  pass "test_wire_format_assigned (D4, AT-18)"
}

# AT-291-9 (D1, D2): Observable write-time hold re-read halts execution and prevents writes
test_write_time_hold_reread() {
  reset_state
  pr_fixture 114 "$H"
  touch "$FX/pr-114.flip_hold"
  run_fixture 2016 "$ARGUS" "$H" "pull_request" "completed" "success"

  local rev_body
  rev_body="$(cat <<EOF
### Argus review
<!-- review-verdict:argus:findings -->
<!-- reviewed-head:$H -->
<!-- run-id:2016 -->
<!-- round:1 -->
<!-- finding:R1-1@D1:high:open:none -->
<!-- failure-scenario:R1-1@D1 -->
Concrete failure scenario
<!-- review-verdict-end -->
EOF
)"
  comments_fixture 114 "$(comment_item "$ARGUS" "$rev_body" 3016)"

  if [ ! -f "$RECORDER" ]; then
    fail "test_write_time_hold_reread: $RECORDER does not exist (D1, D2, AT-291-9)"
    return 1
  fi

  local out
  out="$(bash "$RECORDER" 114 2>&1)" || { fail "test_write_time_hold_reread: recorder execution failed"; return 1; }

  [ ! -s "$WRITES" ] || { fail "test_write_time_hold_reread: writes attempted after write-time hold was applied (D1, D2, AT-291-9)"; return 1; }
  echo "$out" | grep -Fq "hold present on #114, recorder writes nothing" || { fail "test_write_time_hold_reread: log missing held object line for #114 (D1, D2, AT-291-9)"; return 1; }

  pass "test_write_time_hold_reread (D1, D2, AT-291-9)"
}

# AT-291-11 (D1, D2, Argus R1-3): Hold probe failure must fail closed (zero writes, exit 1)
test_hold_probe_fail_closed() {
  reset_state
  pr_fixture 115 "$H" "" "" '[215]'
  jq '.body = "Closes #215"' "$FX/pr-115.json" > "$FX/pr-115.json.tmp"
  mv "$FX/pr-115.json.tmp" "$FX/pr-115.json"
  issue_fixture 115 "bootstrap"
  touch "$FX/issue-215.fail"

  run_fixture 2017 "$ARGUS" "$H" "pull_request" "completed" "success"
  local rev_body
  rev_body="$(cat <<EOF
### Argus review
<!-- review-verdict:argus:clean -->
<!-- reviewed-head:$H -->
<!-- run-id:2017 -->
<!-- round:1 -->
<!-- review-verdict-end -->
EOF
)"
  comments_fixture 115 "$(comment_item "$ARGUS" "$rev_body" 3017)"

  if [ ! -f "$RECORDER" ]; then
    fail "test_hold_probe_fail_closed: $RECORDER does not exist (D1, D2, AT-291-11)"
    return 1
  fi

  local out
  if out="$(bash "$RECORDER" 115 2>&1)"; then
    fail "test_hold_probe_fail_closed: recorder exited 0 despite hold probe failure (fail-open violation; D1, D2, AT-291-11)"
    return 1
  fi

  [ ! -s "$WRITES" ] || { fail "test_hold_probe_fail_closed: writes attempted when hold probe failed (D1, D2, AT-291-11)"; return 1; }
  echo "$out" | grep -Eiq "error|fail" || { fail "test_hold_probe_fail_closed: log missing error diagnostic on failed hold probe (D1, D2, AT-291-11)"; return 1; }

  pass "test_hold_probe_fail_closed (D1, D2, AT-291-11)"
}

# AT-291-8 (D8): Python engine extraction to scripts/ci/review_recorder.py (PLAYBOOK.md:521)
test_python_engine_extraction() {
  reset_state
  local py_script="$REPO/scripts/ci/review_recorder.py"

  if [ ! -f "$py_script" ]; then
    fail "test_python_engine_extraction: $py_script does not exist (D8, AT-291-8)"
    return 1
  fi

  if [ ! -x "$py_script" ]; then
    fail "test_python_engine_extraction: $py_script is not executable (D8, AT-291-8)"
    return 1
  fi

  if ! grep -Eq 'python3\s+.*review_recorder\.py' "$RECORDER"; then
    fail "test_python_engine_extraction: $RECORDER does not invoke review_recorder.py (D8, AT-291-8)"
    return 1
  fi

  # Direct test of the python engine standalone CLI contract
  local test_workdir="$WORK/py_test"
  mkdir -p "$test_workdir"
  pr_fixture 116 "$H"
  local pr_json
  pr_json="$(cat "$FX/pr-116.json")"

  run_fixture 2018 "$ARGUS" "$H" "pull_request" "completed" "success"
  local rev_body
  rev_body="$(cat <<EOF
### Argus review
<!-- review-verdict:argus:clean -->
<!-- reviewed-head:$H -->
<!-- run-id:2018 -->
<!-- round:1 -->
<!-- review-verdict-end -->
EOF
)"
  comments_fixture 116 "$(comment_item "$ARGUS" "$rev_body" 3018)"

  python3 "$py_script" "116" "$GITHUB_REPOSITORY" "$pr_json" "$test_workdir" "$THEMIS" || {
    fail "test_python_engine_extraction: standalone review_recorder.py invocation failed (D8, AT-291-8)"
    return 1
  }

  [ -f "$test_workdir/action_plan.json" ] || { fail "test_python_engine_extraction: action_plan.json not generated (D8, AT-291-8)"; return 1; }
  [ -f "$test_workdir/new_body.md" ] || { fail "test_python_engine_extraction: new_body.md not generated (D8, AT-291-8)"; return 1; }
  jq -e '.comment_action == "POST"' "$test_workdir/action_plan.json" >/dev/null || { fail "test_python_engine_extraction: action_plan.json missing POST action (D8, AT-291-8)"; return 1; }

  pass "test_python_engine_extraction (D8, AT-291-8)"
}

# AT-291-12 (Argus R1-2, D2): Non-issue numbers in hold set treated as not held
test_non_issue_reference_not_held() {
  reset_state
  pr_fixture 117 "$H"
  # PR body referencing non-issue 99991
  jq '.body = "Refs #99991"' "$FX/pr-117.json" > "$FX/pr-117.json.tmp"
  mv "$FX/pr-117.json.tmp" "$FX/pr-117.json"
  touch "$FX/issue-99991.not_found"

  run_fixture 2019 "$ARGUS" "$H" "pull_request" "completed" "success"
  local rev_body
  rev_body="$(cat <<EOF
### Argus review
<!-- review-verdict:argus:clean -->
<!-- reviewed-head:$H -->
<!-- run-id:2019 -->
<!-- round:1 -->
<!-- review-verdict-end -->
EOF
)"
  comments_fixture 117 "$(comment_item "$ARGUS" "$rev_body" 3019)"

  local out
  out="$(bash "$RECORDER" 117 2>&1)" || { fail "test_non_issue_reference_not_held: recorder failed on non-issue reference"; return 1; }

  echo "$out" | grep -Fq "note: #99991 is not an issue, treating as not held" || {
    fail "test_non_issue_reference_not_held: missing logged note for non-issue #99991"
    return 1
  }
  [ -s "$WRITES" ] || { fail "test_non_issue_reference_not_held: writes should have proceeded"; return 1; }

  pass "test_non_issue_reference_not_held (Argus R1-2, D2)"
}

# AT-354-1..4, AT-354-7 (D1, D2, D4, D8): Symmetric syntax matrix and shared base ID
test_failure_scenario_symmetric_syntax_matrix() {
  reset_state
  pr_fixture 118 "$H"
  run_fixture 2020 "$ARGUS" "$H" "pull_request" "completed" "success"

  local rev_body
  rev_body="$(cat <<EOF
### Argus review
<!-- review-verdict:argus:findings -->
<!-- reviewed-head:$H -->
<!-- run-id:2020 -->
<!-- round:1 -->
<!-- finding:R1-1@D7:high:open:none -->
<!-- failure-scenario:R1-1 -->
<!-- finding:R1-2@D7:high:open:none -->
<!-- failure-scenario:R1-2@D7 -->
<!-- finding:R1-3:high:open:none -->
<!-- failure-scenario:R1-3 -->
<!-- finding:R1-4:high:open:none -->
<!-- failure-scenario:R1-4@D7 -->
<!-- finding:R1-5@D1:high:open:none -->
<!-- finding:R1-5@D2:high:open:none -->
<!-- failure-scenario:R1-5 -->
Verifying symmetric failure-scenario marker syntax and shared base ID presence
<!-- review-verdict-end -->
EOF
)"
  comments_fixture 118 "$(comment_item "$ARGUS" "$rev_body" 3018)"

  if [ ! -f "$RECORDER" ]; then
    fail "test_failure_scenario_symmetric_syntax_matrix: $RECORDER does not exist (D1, D2, D4, D8)"
    return 1
  fi

  bash "$RECORDER" 118 || { fail "test_failure_scenario_symmetric_syntax_matrix: recorder execution failed"; return 1; }

  # Suffix finding + bare marker (AT-354-1, D1, D2)
  grep -q "ledger-row:R1-1@D7:high:open:none" "$WRITES" || { fail "test_failure_scenario_symmetric_syntax_matrix: suffixed finding with bare marker demoted (D1, D2, AT-354-1)"; return 1; }

  # Suffix finding + suffixed marker (AT-354-2, D1, D2)
  grep -q "ledger-row:R1-2@D7:high:open:none" "$WRITES" || { fail "test_failure_scenario_symmetric_syntax_matrix: suffixed finding with suffixed marker demoted (D1, D2, AT-354-2)"; return 1; }

  # Bare finding + bare marker (AT-354-3, D1, D2)
  grep -q "ledger-row:R1-3:high:open:none" "$WRITES" || { fail "test_failure_scenario_symmetric_syntax_matrix: bare finding with bare marker demoted (D1, D2, AT-354-3)"; return 1; }

  # Bare finding + suffixed marker (AT-354-4, D1, D2)
  grep -q "ledger-row:R1-4:high:open:none" "$WRITES" || { fail "test_failure_scenario_symmetric_syntax_matrix: bare finding with suffixed marker demoted (D1, D2, AT-354-4)"; return 1; }

  # Shared base ID multiple findings satisfied by single marker (AT-354-7, D4)
  grep -q "ledger-row:R1-5@D1:high:open:none" "$WRITES" || { fail "test_failure_scenario_symmetric_syntax_matrix: shared base ID finding R1-5@D1 demoted (D4, AT-354-7)"; return 1; }
  grep -q "ledger-row:R1-5@D2:high:open:none" "$WRITES" || { fail "test_failure_scenario_symmetric_syntax_matrix: shared base ID finding R1-5@D2 demoted (D4, AT-354-7)"; return 1; }

  # Zero demotion audit notes for properly paired findings (D1, D2, D4)
  grep -q "\[demoted from high: missing failure_scenario marker\]" "$WRITES" && { fail "test_failure_scenario_symmetric_syntax_matrix: unexpected demotion audit note written (D1, D2, D4)"; return 1; }

  pass "test_failure_scenario_symmetric_syntax_matrix (D1, D2, D4, D8, AT-354-1..4, AT-354-7)"
}

# AT-354-5, AT-354-6 (D1, D3, D5, D8): Demotion attribution, full finding ID preservation, and diagnostic stdout logging
test_failure_scenario_demotion_attribution_and_logging() {
  reset_state
  pr_fixture 119 "$H"
  run_fixture 2021 "$ARGUS" "$H" "pull_request" "completed" "success"

  local rev_body
  rev_body="$(cat <<EOF
### Argus review
<!-- review-verdict:argus:findings -->
<!-- reviewed-head:$H -->
<!-- run-id:2021 -->
<!-- round:1 -->
<!-- finding:R1-1@D7:high:open:none -->
<!-- finding:R1-2:high:open:none -->
<!-- finding:R1-3@D7:high:open:none -->
<!-- failure-scenario:R1-99 -->
Testing demotion on missing and mismatched markers
<!-- review-verdict-end -->
EOF
)"
  comments_fixture 119 "$(comment_item "$ARGUS" "$rev_body" 3019)"

  if [ ! -f "$RECORDER" ]; then
    fail "test_failure_scenario_demotion_attribution_and_logging: $RECORDER does not exist (D1, D3, D5, D8)"
    return 1
  fi

  local out
  out="$(bash "$RECORDER" 119 2>&1)" || { fail "test_failure_scenario_demotion_attribution_and_logging: recorder execution failed"; return 1; }

  # Suffixed finding demoted to normal with full ID in audit note (AT-354-5, D1, D3)
  grep -q "ledger-row:R1-1@D7:normal:open:none" "$WRITES" || { fail "test_failure_scenario_demotion_attribution_and_logging: suffixed finding not demoted to normal (D1, D3, AT-354-5)"; return 1; }
  grep -q "\[demoted from high: missing failure_scenario marker\] on R1-1@D7" "$WRITES" || { fail "test_failure_scenario_demotion_attribution_and_logging: audit note missing full suffixed ID R1-1@D7 (D3, AT-354-5)"; return 1; }
  echo "$out" | grep -q "finding R1-1@D7: demoted from high to normal: missing failure_scenario marker" || { fail "test_failure_scenario_demotion_attribution_and_logging: stdout missing diagnostic log for R1-1@D7 (D5, AT-354-5)"; return 1; }

  # Bare finding demoted to normal with bare ID in audit note (AT-354-6, D1, D3)
  grep -q "ledger-row:R1-2:normal:open:none" "$WRITES" || { fail "test_failure_scenario_demotion_attribution_and_logging: bare finding not demoted to normal (D1, D3, AT-354-6)"; return 1; }
  grep -q "\[demoted from high: missing failure_scenario marker\] on R1-2" "$WRITES" || { fail "test_failure_scenario_demotion_attribution_and_logging: audit note missing bare ID R1-2 (D3, AT-354-6)"; return 1; }
  echo "$out" | grep -q "finding R1-2: demoted from high to normal: missing failure_scenario marker" || { fail "test_failure_scenario_demotion_attribution_and_logging: stdout missing diagnostic log for R1-2 (D5, AT-354-6)"; return 1; }

  # Mismatched marker does not prevent demotion (D1, D8)
  grep -q "ledger-row:R1-3@D7:normal:open:none" "$WRITES" || { fail "test_failure_scenario_demotion_attribution_and_logging: mismatched marker prevented demotion (D1, D8)"; return 1; }
  grep -q "\[demoted from high: missing failure_scenario marker\] on R1-3@D7" "$WRITES" || { fail "test_failure_scenario_demotion_attribution_and_logging: audit note missing ID for mismatched marker (D3, D8)"; return 1; }
  echo "$out" | grep -q "finding R1-3@D7: demoted from high to normal: missing failure_scenario marker" || { fail "test_failure_scenario_demotion_attribution_and_logging: stdout missing diagnostic log for mismatched marker R1-3@D7 (D5, D8)"; return 1; }

  pass "test_failure_scenario_demotion_attribution_and_logging (D1, D3, D5, D8, AT-354-5, AT-354-6)"
}

# AT-354-8 (D7, D8): Exemption preservation for dispute and withdrawn high findings
test_failure_scenario_exemptions_preservation() {
  reset_state
  pr_fixture 120 "$H"
  run_fixture 2022 "$ARGUS" "$H" "pull_request" "completed" "success"

  local rev_body
  rev_body="$(cat <<EOF
### Argus review
<!-- review-verdict:argus:findings -->
<!-- reviewed-head:$H -->
<!-- run-id:2022 -->
<!-- round:1 -->
<!-- finding:R1-1@D7:high:open:dispute -->
<!-- finding:R1-2@D7:high:withdrawn:none -->
Findings lacking failure-scenario markers but exempted under D7
<!-- review-verdict-end -->
EOF
)"
  comments_fixture 120 "$(comment_item "$ARGUS" "$rev_body" 3020)"

  if [ ! -f "$RECORDER" ]; then
    fail "test_failure_scenario_exemptions_preservation: $RECORDER does not exist (D7, D8)"
    return 1
  fi

  bash "$RECORDER" 120 || { fail "test_failure_scenario_exemptions_preservation: recorder execution failed"; return 1; }

  # Dispute exemption preserved (AT-354-8, D7)
  grep -q "ledger-row:R1-1@D7:high:open:dispute" "$WRITES" || { fail "test_failure_scenario_exemptions_preservation: dispute finding was demoted (D7, AT-354-8)"; return 1; }
  grep -q "\[demoted from high: missing failure_scenario marker\] on R1-1@D7" "$WRITES" && { fail "test_failure_scenario_exemptions_preservation: dispute finding audit note written (D7, AT-354-8)"; return 1; }

  # Withdrawn exemption preserved (AT-354-8, D7)
  grep -q "ledger-row:R1-2@D7:high:withdrawn:none" "$WRITES" || { fail "test_failure_scenario_exemptions_preservation: withdrawn finding was demoted (D7, AT-354-8)"; return 1; }
  grep -q "\[demoted from high: missing failure_scenario marker\] on R1-2@D7" "$WRITES" && { fail "test_failure_scenario_exemptions_preservation: withdrawn finding audit note written (D7, AT-354-8)"; return 1; }

  pass "test_failure_scenario_exemptions_preservation (D7, D8, AT-354-8)"
}

# AT-361-1, AT-361-2 (D1, D6, D7, D8): Discoverer severity downgrade and downstream merge gate unblocking
test_discoverer_severity_downgrade_and_unblock() {
  reset_state
  pr_fixture 121 "$H"
  run_fixture 2023 "$ARGUS" "$H" "pull_request" "completed" "success"
  run_fixture 2024 "$ATLAS" "$H" "pull_request" "completed" "success"

  local prior_ledger
  prior_ledger="$(cat <<EOF
### Findings ledger for #121
<!-- consensus-ledger:121 -->
<!-- assigned:argus,atlas -->
<!-- reviewed-head:argus:$H -->
<!-- reviewed-head:atlas:$H -->
<!-- ledger-row:R2-1@D5:high:open:none -->
<!-- consensus-ledger-end -->
EOF
)"

  comment_item "$THEMIS" "$prior_ledger" 5001 > "$FX/comment-5001.json"

  local argus_rev atlas_rev
  argus_rev="$(cat <<EOF
### Argus review
<!-- review-verdict:argus:findings -->
<!-- reviewed-head:$H -->
<!-- run-id:2023 -->
<!-- round:3 -->
<!-- finding:R2-1@D5:normal:open:none -->
<!-- review-verdict-end -->
EOF
)"

  atlas_rev="$(cat <<EOF
### Atlas review
<!-- review-verdict:atlas:clean -->
<!-- reviewed-head:$H -->
<!-- run-id:2024 -->
<!-- round:3 -->
<!-- review-verdict-end -->
EOF
)"

  comments_fixture 121 \
    "$(comment_item "$THEMIS" "$prior_ledger" 5001)" \
    "$(comment_item "$ARGUS" "$argus_rev" 3023)" \
    "$(comment_item "$ATLAS" "$atlas_rev" 3024)"

  local out
  out="$(bash "$RECORDER" 121 2>&1)" || { fail "test_discoverer_severity_downgrade_and_unblock: recorder failed (D1, D8)"; return 1; }

  grep -q "ledger-row:R2-1@D5:normal:open:none" "$WRITES" || { fail "test_discoverer_severity_downgrade_and_unblock: finding severity not updated to normal (D1, D8, AT-361-1)"; return 1; }
  grep -q "\[severity updated to normal by @argus on R2-1@D5\]" "$WRITES" || { fail "test_discoverer_severity_downgrade_and_unblock: audit note missing for severity update (D6, D8, AT-361-1)"; return 1; }
  echo "$out" | grep -q "finding R2-1@D5: severity updated from high to normal by @argus" || { fail "test_discoverer_severity_downgrade_and_unblock: stdout missing diagnostic log (D6, D8, AT-361-1)"; return 1; }
  grep -q "gh issue edit 121.*--add-label.*review:merge-ready" "$WRITES" || { fail "test_discoverer_severity_downgrade_and_unblock: review:merge-ready label missing on clean consensus (D7, D8, AT-361-1)"; return 1; }

  local emitted_ledger
  emitted_ledger="$(awk '/### Findings ledger for #121/ {f = 1} f; /<!-- consensus-ledger-end -->/ {f = 0; exit}' "$WRITES")"
  [ -n "$emitted_ledger" ] || { fail "test_discoverer_severity_downgrade_and_unblock: emitted ledger not captured in writes (D7, AT-361-2)"; return 1; }

  comments_fixture 121 "$(comment_item "$THEMIS" "$emitted_ledger" 5001 "COLLABORATOR" "Bot")"
  local gate_out
  gate_out="$(run_gate 121)"
  echo "$gate_out" | grep -q "conjunct (4): true" || { fail "test_discoverer_severity_downgrade_and_unblock: conjunct 4 not true after downgrade to normal (D7, D8, AT-361-2)"; return 1; }
  echo "$gate_out" | grep -q "blocking set empty" || { fail "test_discoverer_severity_downgrade_and_unblock: WHY[4] blocking set empty missing (D7, D8, AT-361-2)"; return 1; }

  pass "test_discoverer_severity_downgrade_and_unblock (D1, D6, D7, D8, AT-361-1, AT-361-2)"
}

# AT-361-3 (D5, D8): Peer reviewer non-interference on finding severity
test_peer_severity_non_interference() {
  reset_state
  pr_fixture 122 "$H"
  run_fixture 2025 "$ATLAS" "$H" "pull_request" "completed" "success"

  local prior_ledger
  prior_ledger="$(cat <<EOF
### Findings ledger for #122
<!-- consensus-ledger:122 -->
<!-- assigned:argus,atlas -->
<!-- reviewed-head:argus:$H -->
<!-- reviewed-head:atlas:$H -->
<!-- ledger-row:R2-1@D5:high:open:none -->
<!-- consensus-ledger-end -->
EOF
)"

  comment_item "$THEMIS" "$prior_ledger" 5001 > "$FX/comment-5001.json"

  local atlas_rev
  atlas_rev="$(cat <<EOF
### Atlas review
<!-- review-verdict:atlas:findings -->
<!-- reviewed-head:$H -->
<!-- run-id:2025 -->
<!-- round:3 -->
<!-- finding:R2-1@D5:normal:open:none -->
<!-- review-verdict-end -->
EOF
)"

  comments_fixture 122 \
    "$(comment_item "$THEMIS" "$prior_ledger" 5001)" \
    "$(comment_item "$ATLAS" "$atlas_rev" 3025)"

  local out
  out="$(bash "$RECORDER" 122 2>&1)" || { fail "test_peer_severity_non_interference: recorder failed (D5, D8)"; return 1; }

  grep -q "ledger-row:R2-1@D5:high:open:none" "$WRITES" || { fail "test_peer_severity_non_interference: peer modified discoverer finding severity (D5, D8, AT-361-3)"; return 1; }
  grep -q "ledger-row:R2-1@D5:normal" "$WRITES" && { fail "test_peer_severity_non_interference: peer updated finding to normal (D5, D8, AT-361-3)"; return 1; }
  grep -q "severity updated" "$WRITES" && { fail "test_peer_severity_non_interference: severity update audit note written on peer review (D5, D8, AT-361-3)"; return 1; }
  echo "$out" | grep -q "severity updated" && { fail "test_peer_severity_non_interference: stdout logged severity update on peer review (D5, D8, AT-361-3)"; return 1; }

  pass "test_peer_severity_non_interference (D5, D8, AT-361-3)"
}

# AT-361-4 (D3, D8): Re-encounter of high severity finding without sibling failure-scenario marker
test_re_encounter_high_missing_failure_scenario() {
  reset_state
  pr_fixture 123 "$H"
  run_fixture 2026 "$ARGUS" "$H" "pull_request" "completed" "success"

  local prior_ledger
  prior_ledger="$(cat <<EOF
### Findings ledger for #123
<!-- consensus-ledger:123 -->
<!-- assigned:argus,atlas -->
<!-- reviewed-head:argus:$H -->
<!-- reviewed-head:atlas:$H -->
<!-- ledger-row:R2-1@D5:high:open:none -->
<!-- consensus-ledger-end -->
EOF
)"

  comment_item "$THEMIS" "$prior_ledger" 5001 > "$FX/comment-5001.json"

  local argus_rev
  argus_rev="$(cat <<EOF
### Argus review
<!-- review-verdict:argus:findings -->
<!-- reviewed-head:$H -->
<!-- run-id:2026 -->
<!-- round:3 -->
<!-- finding:R2-1@D5:high:open:none -->
Reasserting high finding without sibling failure-scenario marker
<!-- review-verdict-end -->
EOF
)"

  comments_fixture 123 \
    "$(comment_item "$THEMIS" "$prior_ledger" 5001)" \
    "$(comment_item "$ARGUS" "$argus_rev" 3026)"

  local out
  out="$(bash "$RECORDER" 123 2>&1)" || { fail "test_re_encounter_high_missing_failure_scenario: recorder failed (D3, D8)"; return 1; }

  grep -q "ledger-row:R2-1@D5:normal:open:none" "$WRITES" || { fail "test_re_encounter_high_missing_failure_scenario: high finding without marker was not demoted to normal (D3, D8, AT-361-4)"; return 1; }
  grep -q "\[demoted from high: missing failure_scenario marker\] on R2-1@D5" "$WRITES" || { fail "test_re_encounter_high_missing_failure_scenario: demotion audit note missing full ID (D3, D8, AT-361-4)"; return 1; }
  echo "$out" | grep -q "finding R2-1@D5: demoted from high to normal: missing failure_scenario marker" || { fail "test_re_encounter_high_missing_failure_scenario: stdout missing diagnostic log (D3, D8, AT-361-4)"; return 1; }

  pass "test_re_encounter_high_missing_failure_scenario (D3, D8, AT-361-4)"
}

# AT-361-5, AT-361-7 (D4, D8): Security tier protection against footer downgrade & maintainer retier
test_security_tier_footer_downgrade_protection() {
  reset_state
  pr_fixture 124 "$H"
  run_fixture 2027 "$ARGUS" "$H" "pull_request" "completed" "success"

  local prior_ledger
  prior_ledger="$(cat <<EOF
### Findings ledger for #124
<!-- consensus-ledger:124 -->
<!-- assigned:argus,atlas -->
<!-- reviewed-head:argus:$H -->
<!-- reviewed-head:atlas:$H -->
<!-- ledger-row:R1-1:security:open:pending -->
<!-- consensus-ledger-end -->
EOF
)"

  comment_item "$THEMIS" "$prior_ledger" 5001 > "$FX/comment-5001.json"

  # Case 1 (AT-361-5, D4): Footer downgrade attempt from security to normal
  local argus_rev
  argus_rev="$(cat <<EOF
### Argus review
<!-- review-verdict:argus:clean -->
<!-- reviewed-head:$H -->
<!-- run-id:2027 -->
<!-- round:2 -->
<!-- finding:R1-1:normal:open:none -->
<!-- review-verdict-end -->
EOF
)"

  comments_fixture 124 \
    "$(comment_item "$THEMIS" "$prior_ledger" 5001)" \
    "$(comment_item "$ARGUS" "$argus_rev" 3027)"

  local out
  out="$(bash "$RECORDER" 124 2>&1)" || { fail "test_security_tier_footer_downgrade_protection: recorder failed (D4, D8)"; return 1; }

  grep -q "ledger-row:R1-1:security:open:pending" "$WRITES" || { fail "test_security_tier_footer_downgrade_protection: security row downgraded by verdict block (D4, D8, AT-361-5)"; return 1; }
  grep -q "ledger-row:R1-1:normal" "$WRITES" && { fail "test_security_tier_footer_downgrade_protection: normal row recorded for security finding (D4, D8, AT-361-5)"; return 1; }
  grep -q "\[severity updated" "$WRITES" && { fail "test_security_tier_footer_downgrade_protection: severity update audit note written for security footer downgrade (D4, D8, AT-361-5)"; return 1; }
  echo "$out" | grep -q "finding R1-1: footer severity change from security to normal ignored; security rows require maintainer retier" || { fail "test_security_tier_footer_downgrade_protection: stdout missing security footer downgrade diagnostic log (D4, D8, AT-361-5)"; return 1; }

  # Case 2 (AT-361-7, D4): Maintainer retier directive retiers security finding
  : > "$WRITES"
  local owner_cmd="@argus retier R1-1 normal"
  comments_fixture 124 \
    "$(comment_item "$THEMIS" "$prior_ledger" 5001)" \
    "$(comment_item "evekhm" "$owner_cmd" 3028 "OWNER" "User")"

  bash "$RECORDER" 124 >/dev/null || { fail "test_security_tier_footer_downgrade_protection: recorder failed on maintainer retier (D4, D8, AT-361-7)"; return 1; }
  grep -q "ledger-row:R1-1:normal:open:pending" "$WRITES" || { fail "test_security_tier_footer_downgrade_protection: maintainer retier did not retier security row (D4, D8, AT-361-7)"; return 1; }
  grep -q "\[retiered to normal by @evekhm\]" "$WRITES" || { fail "test_security_tier_footer_downgrade_protection: retier audit note missing (D4, D8, AT-361-7)"; return 1; }

  pass "test_security_tier_footer_downgrade_protection (D4, D8, AT-361-5, AT-361-7)"
}

# AT-361-6 (D2, D8): Post-round-3 funnel cap prevents upward escalation of existing finding to high
test_late_round_funnel_elevation_cap() {
  reset_state
  pr_fixture 125 "$H"
  run_fixture 2028 "$ARGUS" "$H" "pull_request" "completed" "success"

  local prior_ledger
  prior_ledger="$(cat <<EOF
### Findings ledger for #125
<!-- consensus-ledger:125 -->
<!-- assigned:argus,atlas -->
<!-- reviewed-head:argus:$H -->
<!-- reviewed-head:atlas:$H -->
<!-- ledger-row:R1-5:normal:open:none -->
<!-- consensus-ledger-end -->
EOF
)"

  comment_item "$THEMIS" "$prior_ledger" 5001 > "$FX/comment-5001.json"

  local argus_rev
  argus_rev="$(cat <<EOF
### Argus review
<!-- review-verdict:argus:findings -->
<!-- reviewed-head:$H -->
<!-- run-id:2028 -->
<!-- round:4 -->
<!-- finding:R1-5:high:open:none -->
<!-- failure-scenario:R1-5 -->
Escalating existing finding in late round
<!-- review-verdict-end -->
EOF
)"

  comments_fixture 125 \
    "$(comment_item "$THEMIS" "$prior_ledger" 5001)" \
    "$(comment_item "$ARGUS" "$argus_rev" 3028)"

  local out
  out="$(bash "$RECORDER" 125 2>&1)" || { fail "test_late_round_funnel_elevation_cap: recorder execution failed (D2, D8)"; return 1; }

  grep -q "ledger-row:R1-5:normal:open:none" "$WRITES" || { fail "test_late_round_funnel_elevation_cap: late round elevation to high was not demoted to normal (D2, D8, AT-361-6)"; return 1; }
  grep -q "ledger-row:R1-5:high" "$WRITES" && { fail "test_late_round_funnel_elevation_cap: late round elevation to high was accepted (D2, D8, AT-361-6)"; return 1; }

  pass "test_late_round_funnel_elevation_cap (D2, D8, AT-361-6)"
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
  test_write_time_hold_reread
  test_hold_probe_fail_closed
  test_python_engine_extraction
  test_non_issue_reference_not_held
  test_failure_scenario_symmetric_syntax_matrix
  test_failure_scenario_demotion_attribution_and_logging
  test_failure_scenario_exemptions_preservation
  test_discoverer_severity_downgrade_and_unblock
  test_peer_severity_non_interference
  test_re_encounter_high_missing_failure_scenario
  test_security_tier_footer_downgrade_protection
  test_late_round_funnel_elevation_cap
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
