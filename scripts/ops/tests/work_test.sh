#!/usr/bin/env bash
# Tests for scripts/ops/work.sh (#36, intent/36-dispatch/plan.md T9).
#
#   bash scripts/ops/tests/work_test.sh
#
# Hermetic: a stub `gh` first on PATH answers every read from a canned
# JSON fixture, and a stub `claude` fails loudly if anything is ever
# launched. No network, no token, and nothing is written to GitHub —
# the stubs log any attempt and the run fails on it.
#
# Each scenario names the spec row it pins. The refusals are the point:
# a dispatcher that guesses at a corrupted or claimed issue is worse
# than one that does nothing, so every D5 condition has a case here.
# Exit 0 with a PASS line per assertion, non-zero on the first failure.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WORK_SH="$REPO/scripts/ops/work.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FIXTURES="$WORK/fixtures"
WRITES="$WORK/writes.log"
mkdir -p "$FIXTURES" "$WORK/bin"
: > "$WRITES"

export GITHUB_REPO="test/repo"
export FIXTURES WRITES
export PATH="$WORK/bin:$PATH"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

# --- the stubs ----------------------------------------------------------------
cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
# Canned reads only. Anything that is not `gh api <path>` is a write
# attempt as far as this test is concerned, and is recorded.
if [ "${1:-}" != "api" ] || [ "$#" -ne 2 ]; then
  echo "gh $*" >> "$WRITES"
  echo "stub gh: refusing non-read call: $*" >&2
  exit 1
fi
file="$FIXTURES/${2//\//_}.json"
[ -f "$file" ] || { echo "stub gh: no fixture for $2" >&2; exit 1; }
cat "$file"
STUB
cat > "$WORK/bin/claude" <<'STUB'
#!/usr/bin/env bash
echo "claude $*" >> "$WRITES"
echo "stub claude: a session was launched by a test that forbids it" >&2
exit 1
STUB
chmod +x "$WORK/bin/gh" "$WORK/bin/claude"

# --- fixtures -----------------------------------------------------------------
# issue <n> <state> <labels-csv> <title>
issue() {
  jq -n --argjson n "$1" --arg state "$2" --arg labels "$3" --arg title "$4" \
    '{number: $n, state: $state, title: $title, body: "",
      labels: ($labels | if . == "" then [] else split(",") end | map({name: .}))}' \
    > "$FIXTURES/repos_test_repo_issues_$1.json"
  echo '[]' > "$FIXTURES/repos_test_repo_issues_$1_comments.json"
}
# pr <n> <body> <head-ref>
pr() {
  jq -n --argjson n "$1" --arg body "$2" \
    '{number: $n, state: "open", title: "a pull request", body: $body,
      labels: [], pull_request: {url: "x"}}' \
    > "$FIXTURES/repos_test_repo_issues_$1.json"
  jq -n --arg ref "$3" '{head: {ref: $ref}}' \
    > "$FIXTURES/repos_test_repo_pulls_$1.json"
}
# claim <n> <login> <body>
claim() {
  jq -n --arg l "$2" --arg b "$3" '[{user: {login: $l}, body: $b}]' \
    > "$FIXTURES/repos_test_repo_issues_$1_comments.json"
}

# run <expected-exit> <name> -- <args...>; stdout+stderr land in $OUT
OUT=""
run() {
  local want="$1" name="$2" rc=0
  shift 3  # drop want, name and the literal --
  set +e
  OUT="$(DRY_RUN="${DRY:-1}" "$WORK_SH" "$@" 2>&1)"
  rc=$?
  set -e
  if [ "$rc" -ne "$want" ]; then
    printf '%s\n' "$OUT" >&2
    fail "$name (expected exit $want, got $rc)"
  fi
  pass "$name (exit $rc)"
}
# has <literal> <name>
has() {
  if printf '%s\n' "$OUT" | grep -qF -- "$1"; then pass "$2"
  else printf '%s\n' "$OUT" >&2; fail "$2 (expected to find: $1)"; fi
}
# hasnt <literal> <name>
hasnt() {
  if printf '%s\n' "$OUT" | grep -qF -- "$1"; then
    printf '%s\n' "$OUT" >&2; fail "$2 (did not expect: $1)"
  else pass "$2"; fi
}

banner() { printf '\n--- %s\n' "$*"; }

# ---------------------------------------------------------------------------
banner "D5(a) hold is absolute — checked before anything else"
issue 101 open "hold,status:implementing,blocked" "Held issue"
run 2 "D5(a): hold exits 2" -- 101
has "carries hold" "D5(a): the refusal names hold"
hasnt "carries blocked" "D5(a): no later condition is reported ahead of hold"

banner "D5(b) a closed issue and status:review-stuck are human territory"
issue 102 closed "status:implementing" "Closed issue"
run 2 "D5(b): a closed issue exits 2" -- 102
has "is closed" "D5(b): the refusal says closed"
issue 103 open "status:review-stuck" "Escalated issue"
run 2 "D5(b): status:review-stuck exits 2" -- 103
has "carries status:review-stuck" "D5(b): the refusal names the escalation label"

banner "D5(c) blocked is report-and-stop"
issue 104 open "blocked,status:implementing" "Blocked issue"
run 2 "D5(c): blocked exits 2" -- 104
has "carries blocked" "D5(c): the refusal names blocked"

banner "D5(d) two status labels is corrupted state — reported, never guessed"
issue 105 open "status:spec,status:build" "Corrupted issue"
run 2 "D5(d): two status:* labels exit 2" -- 105
has "more than one status:* label" "D5(d): the refusal names the condition"
has "status:spec" "D5(d): the labels found are listed"
has "status:build" "D5(d): both labels are listed"
hasnt "hold" "D5(d): the dispatcher never applies hold — one circuit breaker, one writer"

banner "D5(e) in-progress held by another actor stops; held by the owner resumes"
issue 106 open "in-progress,status:implementing" "Claimed by someone else"
claim 106 "evekhm-athena-app[bot]" "Claim: DESIGN stage — athena."
run 2 "D5(e): a claim by another actor exits 2" -- 106
has "is held by athena" "D5(e): the refusal names the holder"
issue 107 open "in-progress,status:implementing" "Claimed by its own owner"
claim 107 "evekhm-odyssey-app[bot]" "Claim: IMPLEMENT stage — odyssey."
run 0 "D5(e): a claim by the stage's own owner is a resume and proceeds" -- 107
has "held by odyssey" "D5(e): the resumed claim is reported, not refused"

banner "D8 a clean issue prints every resolved field and writes nothing"
issue 108 open "status:implementing" "Deterministic dispatch: one number in"
run 0 "D8: a clean issue exits 0" -- 108
has "#108" "D8: the resolved number is printed"
has "stage:    implement" "D8: the stage is printed"
has "label:    status:implementing" "D8: the label is printed"
has "owner:    odyssey" "D8: the owner is printed"
has "folder:   intent/108-deterministic-" "D8: the folder is printed"
has "branch:   odyssey/108-deterministic-" "D8: the branch is printed"
has "harness:  claude-code" "D8: the harness is printed"
has 'command:  claude --agent odyssey "#108"' "D8: the exact command line is printed"
has "nothing was launched and nothing was written" "D8: the dry run says so"

banner "D9 a PR resolves to its issue, by Closes and by branch name"
pr 109 "Implements the thing.\n\nCloses #108" "odyssey/108-deterministic"
run 0 "D9: a PR with Closes #<n> exits 0" -- 109
has "resolved from #109 via Closes #108" "D9: the Closes line resolves the issue"
has "==> #108" "D9: the issue, not the PR, is the unit of work"
pr 110 "No trailer at all." "odyssey/108-deterministic"
run 0 "D9: a PR with no Closes falls back to the branch name" -- 110
has "resolved from #110 via the branch name odyssey/108-deterministic" \
  "D9: the branch name resolves the issue"
pr 111 "No trailer at all." "not-a-work-branch"
run 1 "D9: a PR that resolves to no issue exits 1" -- 111
has "cannot resolve PR #111 to an issue" "D9: it says so rather than guessing"

banner "D9 a multi-owner stage prints both and launches neither"
issue 112 open "status:in-review" "Under review"
DRY=0 run 0 "D9: status:in-review with no --as exits 0 without launching" -- 112
has "--> argus" "D9: the first reviewer's instruction is printed"
has "--> atlas" "D9: the second reviewer's instruction is printed"
has "printing both and launching neither" "D9: it says it launched nothing"
[ ! -s "$WRITES" ] || { cat "$WRITES" >&2; fail "D9: something was launched or written"; }
pass "D9: no session was launched and no write was attempted"
run 0 "D9: --as picks exactly one owner" -- 112 --as argus
has "--> argus" "D9: --as argus dispatches argus"
hasnt "--> atlas" "D9: --as argus dispatches nobody else"
run 2 "D5(f): --as naming a non-owner exits 2" -- 112 --as odyssey
has "odyssey does not own stage review" "D5(f): the refusal names the stage"

banner "D10 an unlaunchable harness is a supported outcome, not an error"
issue 113 open "status:build" "Plan the thing"
DRY=0 run 0 "D10: a harness this script cannot start exits 0" -- 113
has "harness:  antigravity" "D10: the pinned harness is printed"
has ".agents/agents/daedalus/instructions.md" "D10: the compiled target is printed"
has "#113" "D10: the one-line prompt is printed"
[ ! -s "$WRITES" ] || { cat "$WRITES" >&2; fail "D10: something was launched"; }
pass "D10: nothing was launched for an unlaunchable harness"

banner "D6 the slug rule is deterministic, cut at the first : or ;, and <= 24 chars"
issue 114 open "status:implementing" \
  "One-argument dispatch: personas resolve the stage from labels"
issue 115 open "status:implementing" \
  "README.md: operator walkthrough of the loop from the product owner's seat"
issue 116 open "status:implementing" \
  "Execution model for unattended personas (#8/#9/#10); where does it run?"
for n in 114 115 116; do
  run 0 "D6: #$n resolves a folder" -- "$n"
  first="$(printf '%s\n' "$OUT" | sed -n 's/^    folder:   //p')"
  run 0 "D6: #$n resolves a folder again" -- "$n"
  second="$(printf '%s\n' "$OUT" | sed -n 's/^    folder:   //p')"
  [ "$first" = "$second" ] \
    || fail "D6: #$n derived '$first' then '$second' — the rule is not deterministic"
  slug="${first#intent/$n-}"
  slug="${slug%%/*}"
  [ -n "$slug" ] || fail "D6: #$n derived an empty slug"
  [ "${#slug}" -le 24 ] \
    || fail "D6: #$n derived a ${#slug}-character slug ('$slug'), over the 24 cap"
  pass "D6: #$n derives '$slug' twice, ${#slug} characters"
done
has "intent/116-execution-model-for" "D6: the title is cut at the first ';'"

banner "D6 an existing folder is reused and never derived"
issue 36 open "status:implementing" "A title that would derive something else"
run 0 "D6: an issue with a folder exits 0" -- 36
has "folder:   intent/36-dispatch/ (existing)" "D6: the existing folder is reused"
has "branch:   odyssey/36-dispatch" "D6: the branch follows the reused folder"

banner "D7 nothing but the number and --as is an input"
run 1 "D7: a second positional exits 1" -- 108 109
has "one number is one run" "D7: it says why"
run 1 "D7: an unknown flag exits 1" -- 108 --stage implement
has "unknown flag" "D7: a flag naming a stage is refused outright"
run 1 "D7: a non-numeric argument exits 1" -- not-a-number
has "is not an issue or pull-request number" "D7: it says why"

banner "the whole run wrote nothing"
[ ! -s "$WRITES" ] || { cat "$WRITES" >&2; fail "a write or launch was attempted"; }
pass "no GitHub write and no launch was attempted in any scenario"

echo
echo "work_test.sh: all scenarios passed"
