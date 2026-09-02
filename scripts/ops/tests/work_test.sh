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
# claim <n> <login> <body> [<login> <body> ...]  — the thread, in order
claim() {
  local n="$1" thread='[]'
  shift
  while [ "$#" -ge 2 ]; do
    thread="$(jq -c --argjson t "$thread" --arg l "$1" --arg b "$2" \
      -n '$t + [{user: {login: $l}, body: $b}]')"
    shift 2
  done
  printf '%s\n' "$thread" > "$FIXTURES/repos_test_repo_issues_${n}_comments.json"
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

banner "D5(e) the holder is the comment's AUTHOR, never its text (Argus R1-1)"
# Fail-open direction: a drive-by comment naming this persona must not
# unlock an issue another actor genuinely holds.
issue 117 open "in-progress,status:implementing" "Held, then talked about"
claim 117 "evekhm-athena-app[bot]" "Claim: IMPLEMENT stage — athena." \
  "drive-by-user" "I claim this for odyssey."
run 2 "D5(e): a drive-by body naming this persona does not unlock the issue" -- 117
has "held by athena" "D5(e): the holder is the real claimant, not the name in the prose"
hasnt "command:" "D5(e): nothing is dispatched over a foreign claim"
# A structured claim by a login no identity table names is a foreign
# claim, not this persona: fail closed and say whose login it is.
issue 125 open "in-progress,status:implementing" "Claimed by an unknown login"
claim 125 "drive-by-user" "Claim: IMPLEMENT stage — odyssey."
run 2 "D5(e): a claim by an unknown login exits 2" -- 125
has "held by drive-by-user" "D5(e): the refusal names the login, not the persona it mentions"
has "no persona identity names" "D5(e): it says why the login is not an actor"
# Prose containing the word is not a claim line: the thread then names
# no holder, and a mutex that names nobody stops the dispatch (R2-1).
issue 118 open "in-progress,status:implementing" "Held with prose in the thread"
claim 118 "some-random-person" "The PR claims it is byte-identical."
run 2 "D5(e): prose containing 'claims' is not a claim" -- 118
has "no comment opens with a structured claim line" \
  "D5(e): the refusal is 'no claim', not a holder read out of the prose"
hasnt "held by some-random-person" "D5(e): the commenter is never made the holder"
# The last CLAIM wins, not the last comment mentioning the word.
issue 119 open "in-progress,status:implementing" "Claimed, then discussed"
claim 119 "evekhm-odyssey-app[bot]" "Claim: IMPLEMENT stage — odyssey." \
  "some-random-person" "Nobody claims this is finished yet."
run 0 "D5(e): later prose does not displace the claim" -- 119
has "held by odyssey" "D5(e): the holder is still the last structured claim's author"

banner "D5(e) in-progress with no structured claim fails closed (Argus R2-1)"
# The label is the mutex. A thread that claims in prose, or does not
# claim at all, leaves it naming nobody — and a mutex naming nobody is
# still held. Removing in-progress is how a session hands the issue back.
issue 127 open "in-progress,status:implementing" "Held, claimed in prose only"
claim 127 "evekhm-odyssey-app[bot]" "Picking this up — athena."
run 2 "D5(e): in-progress with an unstructured claim exits 2" -- 127
has "the mutex names no holder" "D5(e): the refusal says the claim is unreadable"
has "in-progress on #127 is set" "D5(e): it names the label that stopped it"
hasnt "command:" "D5(e): nothing is dispatched on an unnamed mutex"
issue 128 open "in-progress,status:implementing" "Held with an empty thread"
run 2 "D5(e): in-progress with no comments at all exits 2" -- 128
has "no comment opens with a structured claim line" "D5(e): an empty thread claims nothing"
issue 129 open "in-progress,status:implementing" "Held, thread unreadable"
rm -f "$FIXTURES/repos_test_repo_issues_129_comments.json"
run 2 "D5(e): a thread that cannot be read exits 2" -- 129
has "cannot be read" "D5(e): an unverifiable mutex is a held mutex"

banner "D5(e) --as narrows the mutex before it is checked (Argus R1-2)"
issue 120 open "in-progress,status:in-review" "Claimed by one of two reviewers"
claim 120 "evekhm-atlas-app[bot]" "Claim: REVIEW stage — atlas."
run 2 "D5(e): --as argus against an atlas claim exits 2" -- 120 --as argus
has "held by atlas" "D5(e): the other reviewer is a different actor"
run 0 "D5(e): --as atlas against an atlas claim is a resume" -- 120 --as atlas
has "held by atlas" "D5(e): the holder resuming proceeds"

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
pr 109 "Implements the thing.

Closes #108" "odyssey/108-deterministic"
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

banner "D9 every closing keyword GitHub honours resolves (Argus R1-3)"
for kw in Fixes fixed FIX Resolves resolved Resolve Close Closed; do
  pr 121 "$kw #108" "not-a-work-branch"
  run 0 "D9: '$kw #108' resolves the issue" -- 121
  has "resolved from #121 via Closes #108" "D9: '$kw' is a closing keyword"
done
pr 126 "Discloses #107 — a word that merely ends in one." \
  "odyssey/108-deterministic"
run 0 "D9: a word ending in a keyword is not a keyword" -- 126
has "via the branch name" "D9: 'Discloses' does not close #107"
pr 122 "See evekhm/other#9 and https://github.com/evekhm/other/issues/9." \
  "odyssey/108-deterministic"
run 0 "D9: a cross-repo reference is not a closing reference" -- 122
has "via the branch name" "D9: cross-repo and URL forms fall through to the branch"

banner "D9 two closing references are two units of work, never a guess (Argus R1-4)"
pr 123 "Closes #108
Fixes #107" "odyssey/108-deterministic"
run 1 "D9: a PR closing two issues exits 1" -- 123
has "closes more than one issue" "D9: it says why"
has "#107" "D9: the discarded issue is named"
has "#108" "D9: both issues are named"
pr 124 "Closes #108, and again: closes #108." "not-a-work-branch"
run 0 "D9: the same issue named twice is still one issue" -- 124
has "resolved from #124 via Closes #108" "D9: distinct numbers, not occurrences"

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
