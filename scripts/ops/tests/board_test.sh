#!/usr/bin/env bash
# Tests for scripts/ops/board.sh.
#
#   bash scripts/ops/tests/board_test.sh
#
# Hermetic, following the pattern of work_test.sh: a stub `gh` first on
# PATH answers every read (issues list, issue comments, pr list) from
# canned JSON fixtures, and logs+refuses anything that looks like a
# write (gh api -X/--method/-f/-F, gh issue edit, gh pr merge, gh issue
# comment, or any gh subcommand other than the three reads above). The
# run fails if that log is non-empty at the end.
#
# git for-each-ref, git worktree list, ps and /proc/<pid>/cwd are left
# to hit the real repository (board.sh's SESSIONS/branches/worktree
# rendering reads local, read-only state) — nothing here asserts on
# that output beyond "the script exits 0".
#
# Exit 0 with a PASS line per assertion, non-zero on the first failure.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
BOARD_SH="$REPO/scripts/ops/board.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FIXTURES="$WORK/fixtures"
WRITES="$WORK/writes.log"
mkdir -p "$FIXTURES" "$WORK/bin"
: > "$WRITES"

export GITHUB_REPO="test/repo"
export BOARD_STALE_HOURS=6
export FIXTURES WRITES
export PATH="$WORK/bin:$PATH"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

# --- the stub -------------------------------------------------------------
# Only three calls are legitimate reads for board.sh:
#   gh api --paginate repos/<repo>/issues?state=open&per_page=100
#   gh api --paginate repos/<repo>/issues/<n>/comments
#   gh pr list --repo <repo> --state open --limit 100 --json ...
# Anything else (including `gh api` without exactly --paginate + one
# path, which is how a write like -X/-f/-F/--method would show up) is
# logged and refused.
cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = "api" ]; then
  shift
  if [ "${1:-}" != "--paginate" ] || [ "$#" -ne 2 ]; then
    echo "gh api $*" >> "$WRITES"
    echo "stub gh: refusing api call: $*" >&2
    exit 1
  fi
  path="$2"
  case "$path" in
    repos/*/issues\?state=open*)
      cat "$FIXTURES/issues.json" ;;
    repos/*/issues/*/comments*)
      n="$(echo "$path" | sed -n 's#.*issues/\([0-9]*\)/comments.*#\1#p')"
      f="$FIXTURES/comments_${n}.json"
      if [ -f "$f" ]; then cat "$f"; else echo '[]'; fi ;;
    *)
      echo "stub gh: no fixture for $path" >&2
      exit 1 ;;
  esac
  exit 0
fi
if [ "${1:-}" = "pr" ] && [ "${2:-}" = "list" ]; then
  cat "$FIXTURES/prs.json"
  exit 0
fi
echo "gh $*" >> "$WRITES"
echo "stub gh: refusing non-read call: $*" >&2
exit 1
STUB
chmod +x "$WORK/bin/gh"

# --- fixtures ---------------------------------------------------------------
ISSUES_NDJSON="$WORK/issues.ndjson"
: > "$ISSUES_NDJSON"

# issue <n> <labels-csv> <title> <updated_at>
issue() {
  jq -nc --argjson n "$1" --arg labels "$2" --arg title "$3" \
    --arg created "2026-09-01T00:00:00Z" --arg updated "$4" \
    '{number:$n, title:$title,
      labels: ($labels | if . == "" then [] else split(",") end | map({name: .})),
      user: {login:"someone"}, created_at:$created, updated_at:$updated}' \
    >> "$ISSUES_NDJSON"
}
finalize_issues() { jq -s '.' "$ISSUES_NDJSON" > "$FIXTURES/issues.json"; }

# comments <n> <login> <body> [<login> <body> ...] — thread, in order
comments() {
  local n="$1" thread='[]' i=0
  shift
  while [ "$#" -ge 2 ]; do
    thread="$(jq -c --argjson t "$thread" --arg l "$1" --arg b "$2" --argjson i "$i" \
      -n '$t + [{user:{login:$l}, created_at:("2026-09-03T0" + ($i|tostring) + ":00:00Z"), body:$b}]')"
    i=$((i + 1))
    shift 2
  done
  printf '%s\n' "$thread" > "$FIXTURES/comments_${n}.json"
}

# --- issue fixtures (#36 personas/lifecycle.json: status:implementing ==
# stage implement, owned by odyssey; status:planning == stage plan,
# owned by athena) -----------------------------------------------------------

issue 101 "status:implementing,in-progress" \
  "Scenario 1: last structured claim wins" "2026-09-03T15:00:00Z"
comments 101 \
  "evekhm-athena-app[bot]" "Claim: athena picking up design stage." \
  "evekhm-odyssey-app[bot]" "Claim: odyssey (resume) implement stage." \
  "some-random-person" "The PR claims to already handle this."

issue 102 "status:planning,in-progress" \
  "Scenario 2: claim/stage mismatch" "2026-09-03T14:00:00Z"
comments 102 "evekhm-odyssey-app[bot]" "Claim: odyssey picking up plan stage."

issue 103 "in-progress" \
  "Scenario 3: in-progress, no structured claim" "2026-09-03T13:00:00Z"
comments 103

issue 104 "status:spec,status:build" \
  "Scenario 4: corrupt, two status labels" "2026-09-03T12:00:00Z"
comments 104

issue 105 "intent:new" \
  "Scenario 5: intake only, no status" "2026-09-03T11:00:00Z"

issue 106 "status:implementing" \
  "Scenario 6+8: stale claim, operator-bot attribution" "2026-09-03T10:00:00Z"
comments 106 \
  "evekhm-odyssey-app[bot]" "Claim: odyssey picking up implement stage." \
  "evekhm-odyssey-bot" "_Posted by the operator bot on behalf of daedalus, since the App identity cannot comment yet._"

finalize_issues

# --- PR fixtures (scenario 7) ------------------------------------------------
cat > "$FIXTURES/prs.json" <<'JSON'
[
  {"number":201,"title":"Implement thing for #101","body":"","headRefName":"odyssey/101-foo","baseRefName":"main","isDraft":false,
   "author":{"login":"app/evekhm-odyssey-app"},
   "reviews":[{"author":{"login":"evekhm-argus-app"},"state":"COMMENTED","submittedAt":"2026-09-03T08:00:00Z"},
              {"author":{"login":"evekhm-argus-app"},"state":"APPROVED","submittedAt":"2026-09-03T09:00:00Z"}],
   "statusCheckRollup":[{"name":"ci","status":"COMPLETED","conclusion":"SUCCESS"}],
   "updatedAt":"2026-09-03T09:30:00Z","mergeable":"MERGEABLE"},
  {"number":202,"title":"Build stage output for #102","body":"","headRefName":"daedalus/102-bar","baseRefName":"athena/102-bar","isDraft":false,
   "author":{"login":"app/evekhm-daedalus-app"},
   "reviews":[],
   "statusCheckRollup":[{"name":"ci","status":"COMPLETED","conclusion":"FAILURE"}],
   "updatedAt":"2026-09-03T09:00:00Z","mergeable":"CONFLICTING"},
  {"number":203,"title":"Spec for #102","body":"","headRefName":"athena/102-bar","baseRefName":"main","isDraft":false,
   "author":{"login":"app/evekhm-athena-app"},
   "reviews":[],
   "statusCheckRollup":[],
   "updatedAt":"2026-09-03T08:00:00Z","mergeable":"MERGEABLE"}
]
JSON

# --- run helpers --------------------------------------------------------------
# run <expected-exit> <name> -- <args...>; stdout+stderr land in $OUT.
# stdout is captured via command substitution, so `[ -t 1 ]` in board.sh
# is false and no ANSI codes are emitted — nothing to strip here.
OUT=""
run() {
  local want="$1" name="$2" rc=0
  shift 3  # drop want, name and the literal --
  set +e
  OUT="$("$BOARD_SH" "$@" 2>&1)"
  rc=$?
  set -e
  if [ "$rc" -ne "$want" ]; then
    printf '%s\n' "$OUT" >&2
    fail "$name (expected exit $want, got $rc)"
  fi
  pass "$name (exit $rc)"
}
# has/hasnt <literal> <name> — substring anywhere in $OUT.
has() {
  if printf '%s\n' "$OUT" | grep -qF -- "$1"; then pass "$2"
  else printf '%s\n' "$OUT" >&2; fail "$2 (expected to find: $1)"; fi
}
hasnt() {
  if printf '%s\n' "$OUT" | grep -qF -- "$1"; then
    printf '%s\n' "$OUT" >&2; fail "$2 (did not expect: $1)"
  else pass "$2"; fi
}
# hasline <anchored-regex> <name> — a whole line starting with the pattern.
hasline() {
  if printf '%s\n' "$OUT" | grep -qE -- "^$1"; then pass "$2"
  else printf '%s\n' "$OUT" >&2; fail "$2 (expected a line starting with: $1)"; fi
}
hasnotline() {
  if printf '%s\n' "$OUT" | grep -qE -- "^$1"; then
    printf '%s\n' "$OUT" >&2; fail "$2 (did not expect a line starting with: $1)"
  else pass "$2"; fi
}
# block <n> — sets $BLOCK to the #<n> issue block, header up to (not
# including) the next #<number> header line.
BLOCK=""
block() {
  local n="$1"
  BLOCK="$(awk -v tgt="#$n" '
    $0 ~ ("^" tgt "[^0-9]") { p = 1 }
    p && $0 ~ /^#[0-9]+/ && $0 !~ ("^" tgt "[^0-9]") { exit }
    p { print }
  ' <<<"$OUT")"
  [ -n "$BLOCK" ] || { printf '%s\n' "$OUT" >&2; fail "block #$n: no such header in output"; }
}
blockhas() {
  if printf '%s\n' "$BLOCK" | grep -qF -- "$1"; then pass "$2"
  else printf '%s\n' "$BLOCK" >&2; fail "$2 (expected in block: $1)"; fi
}
blockhasnt() {
  if printf '%s\n' "$BLOCK" | grep -qF -- "$1"; then
    printf '%s\n' "$BLOCK" >&2; fail "$2 (did not expect in block: $1)"
  else pass "$2"; fi
}

banner() { printf '\n--- %s\n' "$*"; }

# ---------------------------------------------------------------------------
banner "the full board renders every scenario at once, writing nothing"
run 0 "board.sh --no-fetch exits 0" -- --no-fetch

banner "1: the LAST structured claim wins; prose containing 'claims' does not count"
block 101
blockhas "claim     odyssey" "1: the last structured claim's author is the holder"
blockhasnt "mismatch" "1: odyssey owns implement, so no drift is reported"

banner "2: a claim by an actor who does not own the current stage is a mismatch"
block 102
blockhas "mismatch" "2: the mismatch line is present"
blockhas "claimed by odyssey, but stage plan is owned by athena" \
  "2: it names the claimant, the stage and the true owner"

banner "3: in-progress with no structured claim in the thread"
block 103
blockhas "in-progress set but no structured Claim comment" \
  "3: the mutex is reported as naming nobody"

banner "4: two status:* labels is reported as corrupt, never guessed"
block 104
blockhas "CORRUPT: two status labels" "4: the corruption is flagged"

banner "5: intent:new with no status goes to INTAKE, never IN FLIGHT"
hasline "#101" "5 (control): #101 does have an IN FLIGHT header"
hasnotline "#105" "5: #105 has no IN FLIGHT header (only an indented INTAKE row)"
has "#105" "5: #105 is named somewhere (the INTAKE row)"
has "INTAKE waiting" "5: the INTAKE section header is present"

banner "6: status:implementing with no in-progress and an old claim is unclaimed"
block 106
blockhas "unclaimed  (last claim was odyssey" \
  "6: unclaimed, with the last claim's author reported for context"

banner "7: PR mapping — checks, reviewers, stacking, conflicts"
block 101
blockhas "PR #201" "7: PR #201 is listed under its issue"
blockhas "by odyssey" "7: the author's app/ login is mapped through the identity table"
blockhas "checks ok" "7: all-SUCCESS checks roll up to ok"
blockhas "evekhm-argus-app x2 (last: APPROVED)" "7: reviewers are grouped with a last-state"
block 102
blockhas "stacked on athena/102-bar (#203)" "7: a PR based on another PR's branch is marked stacked"
blockhas "CHECKS FAILING" "7: a FAILURE conclusion rolls up to CHECKS FAILING"
blockhas "CONFLICTS" "7: a CONFLICTING mergeable state is flagged"
blockhas "no reviews" "7: an empty reviews array is reported as no reviews"

banner "8: a comment posted by the operator bot on behalf of a persona is attributed to it"
block 106
blockhas "last      daedalus (via evekhm-odyssey-bot)" \
  "8: the operator-bot comment is attributed to the persona it names, marked via the login"

banner "9: selecting by number prints only that issue's block"
run 0 "board.sh --no-fetch 102 exits 0" -- --no-fetch 102
hasline "#102" "9: #102's header is printed"
hasnotline "#101" "9: #101's header is not printed"

banner "10: the whole run wrote nothing to GitHub"
[ ! -s "$WRITES" ] || { cat "$WRITES" >&2; fail "10: a write or non-read call was attempted"; }
pass "10: no GitHub write was attempted in any scenario"

echo
echo "board_test.sh: all scenarios passed"
