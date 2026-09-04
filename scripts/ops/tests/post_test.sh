#!/usr/bin/env bash
# Tests for scripts/ops/post.sh (#25, plan.md T7, T8).
#
#   bash scripts/ops/tests/post_test.sh
#
# Hermetic: a stub `gh` first on PATH answers every read from a canned
# fixture and records every write to $WRITES instead of making one. No
# network, no token.
#
# What is being pinned, in one sentence each:
#
#   D13  the labels the write is gated on are the labels AT THE MOMENT
#        OF THE WRITE. The stub can hand back a different answer on the
#        second read of the same path, which is the only way to write a
#        test for a race whose whole content is "someone labelled it
#        while the model was thinking".
#   D14  for a pull request the hold set is the pull request AND every
#        issue it closes — `hold` lives on issues in practice, so a
#        pull-request-only check leaks straight past the breaker.
#   D5   a suppressed post is GREEN. Exit 0, one line saying so. A red X
#        on every held pull request trains the room to ignore the signal.
#   D6   the body is a FILE. There is no --body flag and asking for one
#        is refused by name.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
POST="$REPO/scripts/ops/post.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FIXTURES="$WORK/fixtures"
WRITES="$WORK/writes.log"
READS="$WORK/reads.log"
COUNTS="$WORK/counts"
BODY="$WORK/body.md"
mkdir -p "$FIXTURES" "$COUNTS" "$WORK/bin"
printf 'A review body, composed as a file because a model composes files.\n' > "$BODY"

export GITHUB_REPO="test/repo"
export FIXTURES WRITES READS COUNTS
export PATH="$WORK/bin:$PATH"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }
banner() { printf '\n--- %s\n' "$*"; }

# --- the stub -----------------------------------------------------------------
# Reads come from $FIXTURES/<mangled-path>.json. If <mangled-path>.2.json
# exists it is served on the SECOND and every later read of that path —
# that is the whole apparatus for D13's race.
cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" != "api" ]; then
  echo "gh $*" >> "$WRITES"
  echo "stub gh: unexpected subcommand: $*" >&2
  exit 1
fi
method="GET"; path=""; body_file=""
shift
while [ "$#" -gt 0 ]; do
  case "$1" in
    -X) method="$2"; shift 2 ;;
    -F) case "$2" in body=@*) body_file="${2#body=@}" ;; esac; shift 2 ;;
    --jq) shift 2 ;;
    -*) shift ;;
    *) path="$1"; shift ;;
  esac
done
key="${path//\//_}"
if [ "$method" = "POST" ]; then
  printf '%s\t%s\n' "$path" "$(cat "$body_file")" >> "$WRITES"
  echo "https://github.com/$path/1"
  exit 0
fi
echo "$path" >> "$READS"
n=0
[ ! -f "$COUNTS/$key" ] || n="$(cat "$COUNTS/$key")"
n=$((n + 1))
echo "$n" > "$COUNTS/$key"
if [ "$n" -ge 2 ] && [ -f "$FIXTURES/$key.2.json" ]; then
  cat "$FIXTURES/$key.2.json"; exit 0
fi
[ -f "$FIXTURES/$key.json" ] || { echo "stub gh: no fixture for $path" >&2; exit 1; }
cat "$FIXTURES/$key.json"
STUB
chmod +x "$WORK/bin/gh"

reset() { : > "$WRITES"; : > "$READS"; rm -f "$COUNTS"/*; }

# issue <n> <labels-csv> [suffix]
issue() {
  jq -n --argjson n "$1" --arg labels "$2" \
    '{number: $n, state: "open", title: "an issue", body: "",
      labels: ($labels | if . == "" then [] else split(",") end | map({name: .}))}' \
    > "$FIXTURES/repos_test_repo_issues_$1${3:-}.json"
}
# pr <n> <labels-csv> <body> [suffix]
pr() {
  jq -n --argjson n "$1" --arg labels "$2" --arg body "$3" \
    '{number: $n, state: "open", title: "a pull request", body: $body,
      pull_request: {url: "https://api.github.com/x"},
      labels: ($labels | if . == "" then [] else split(",") end | map({name: .}))}' \
    > "$FIXTURES/repos_test_repo_issues_$1${4:-}.json"
}
# pr_head <n> <branch>
pr_head() {
  jq -n --arg ref "$2" '{head: {ref: $ref}}' \
    > "$FIXTURES/repos_test_repo_pulls_$1.json"
}

posts() { grep -c . "$WRITES" || true; }

# run <expected-exit> <name> -- <args...>
OUT=""
run() {
  local want="$1" name="$2" rc=0
  shift 3
  set +e
  OUT="$("$POST" "$@" 2>&1)"
  rc=$?
  set -e
  if [ "$rc" -ne "$want" ]; then
    printf '%s\n' "$OUT" >&2
    fail "$name (expected exit $want, got $rc)"
  fi
  pass "$name (exit $rc)"
}
has() {
  if printf '%s\n' "$OUT" | grep -qF -- "$1"; then pass "$2"
  else printf '%s\n' "$OUT" >&2; fail "$2 (expected to find: $1)"; fi
}
no_post() {
  local n; n="$(posts)"
  [ "$n" = "0" ] || { cat "$WRITES" >&2; fail "$1 — $n comment(s) were posted"; }
  pass "$1"
}

# ---------------------------------------------------------------------------
banner "D6 the body is a file, and only a file"
issue 25 ""
reset
run 1 "D6: --body is refused" -- 25 --as argus --body "inline"
has "the body is always a file: use --body-file <path> (D6)" \
  "D6: the refusal names the flag that does exist"
no_post "D6: nothing was posted"
run 1 "D6: a body file that does not exist is refused" -- 25 --as argus --body-file "$WORK/nope.md"
has "cannot read the body file" "D6: it says which file"
: > "$WORK/empty.md"
run 1 "D6: an empty body file is refused" -- 25 --as argus --body-file "$WORK/empty.md"
has "is empty; there is nothing to post" "D6: an empty comment is not a review"
run 1 "D5: --as is required" -- 25 --body-file "$BODY"
has "--as <persona> is required" "D5: a post has an actor"
run 1 "D5: a persona with no source is refused" -- 25 --as nobody --body-file "$BODY"
has "no persona source at personas/nobody.yaml" "D5: the actor must exist in personas/"
no_post "D5: none of the refusals wrote anything"

banner "no hold anywhere: exactly one comment is posted"
reset
issue 25 "status:in-review"
run 0 "the clear path exits 0" -- 25 --as argus --body-file "$BODY"
has "posted: #25 as argus" "the run says what it did and as whom"
[ "$(posts)" = "1" ] || { cat "$WRITES" >&2; fail "expected exactly one POST"; }
pass "exactly one comment was posted"
grep -qF "repos/test/repo/issues/25/comments" "$WRITES" \
  || fail "the POST did not go to the target's comments"
grep -qF "A review body, composed as a file" "$WRITES" \
  || fail "the file's contents did not reach the API"
pass "the body reached the API from the file, unmangled"

banner "D13/D5 hold on the target: nothing posted, and the run is GREEN"
reset
issue 25 "status:in-review,hold"
run 0 "a held issue exits 0, not 1" -- 25 --as argus --body-file "$BODY"
has "held: #25 carries hold; nothing posted" "D5: the suppression is stated, not silent"
no_post "D13: the held issue got no comment"

banner "D14 hold on the ISSUE the pull request closes, not on the pull request"
# The label taxonomy attaches `hold` to issues; a pull-request-only
# check posts straight past the breaker. This is that exact shape.
reset
pr 60 "status:in-review" "Implements the thing.

Closes #25"
issue 25 "hold"
run 0 "a pull request whose issue is held exits 0" -- 60 --as argus --body-file "$BODY"
has "held: #25 carries hold; nothing posted" "D14: the HELD issue is named, not the pull request"
no_post "D14: nothing was posted on the pull request either"

banner "D14 every closing reference is checked, not the first"
# work.sh refuses to DISPATCH a pull request that closes two issues.
# Suppressing a post is never the ambiguous half of that rule: a hold on
# either one still has to stop the write.
reset
pr 61 "" "Closes #25
Fixes #26"
issue 25 ""
issue 26 "hold"
run 0 "a hold on the SECOND closing reference still stops the write" -- 61 --as argus --body-file "$BODY"
has "held: #26 carries hold" "D14: the second reference was checked too"
no_post "D14: nothing was posted"

banner "D14 with no closing keyword the hold set comes from the branch name"
reset
pr 62 "" "No keyword in this body at all."
pr_head 62 "odyssey/25-execution-model"
issue 25 "hold"
run 0 "the branch-derived issue is in the hold set" -- 62 --as argus --body-file "$BODY"
has "held: #25 carries hold" "D14: <actor>/<n>-<slug> resolved to the held issue"
no_post "D14: nothing was posted"
grep -qF "repos/test/repo/pulls/62" "$READS" \
  || fail "D14: the branch was never read; the resolver did not run"
pass "D14: the same resolver work.sh dispatches on was used"

banner "D14 a pull request with no hold anywhere still posts"
reset
pr 63 "status:in-review" "Closes #25"
issue 25 "status:implementing"
run 0 "an unheld pull request posts" -- 63 --as argus --body-file "$BODY"
has "posted: #63 as argus" "the comment goes on the pull request, not the issue"
[ "$(posts)" = "1" ] || { cat "$WRITES" >&2; fail "expected exactly one POST"; }
grep -qF "repos/test/repo/issues/63/comments" "$WRITES" \
  || fail "the comment did not go to #63"
pass "exactly one comment, on the number that was dispatched"

banner "D13 THE RACE — hold appears between resolving and writing"
# The scenario the decision exists for: a review starts at 14:00 against
# an unheld pull request, a human holds it at 14:01, the model finishes
# at 14:04. post.sh reads the target TWICE — once to build the hold set,
# once as the gate immediately before the POST — and the `.2.json`
# fixture is those four minutes passing between them. A script that
# reused the first read would post.
reset
pr 64 "status:in-review" "Closes #25"
pr 64 "status:in-review,hold" "Closes #25" ".2"
issue 25 "status:implementing"
run 0 "the write is abandoned mid-run, greenly" -- 64 --as argus --body-file "$BODY"
has "held: #64 carries hold; nothing posted" "D13: the label added mid-run was seen"
no_post "D13: the computed, paid-for review posted nothing"
reads_of_64="$(grep -c '^repos/test/repo/issues/64$' "$READS" || true)"
[ "$reads_of_64" -ge 2 ] \
  || { cat "$READS" >&2; fail "D13: #64 was read $reads_of_64 time(s); the gate reused an earlier read"; }
pass "D13: the labels were re-read ($reads_of_64 reads) rather than cached"

banner "D13 the same race on a plain issue"
reset
issue 27 "status:in-review"
issue 27 "status:in-review,hold" ".2"
run 0 "a hold landing between the two reads is caught" -- 27 --as argus --body-file "$BODY"
has "held: #27 carries hold" "D13: the gate read, not the first read, decides"
no_post "D13: nothing was posted"

banner "D13 the gate read happens AFTER the hold set is built"
# Ordering on a pull request: the closed issue's labels are read last,
# after the resolver has already read the pull request — so a hold that
# lands on the issue during the resolve is still seen.
reset
pr 65 "status:in-review" "Closes #25"
issue 25 "hold"
run 0 "the closed issue's labels are read after the resolve" -- 65 --as argus --body-file "$BODY"
has "held: #25 carries hold" "D14: the issue read came after the pull-request read"
[ "$(tail -1 "$READS")" = "repos/test/repo/issues/25" ] \
  || { cat "$READS" >&2; fail "D13: the last read was not the held issue's labels"; }
pass "D13: the hold-set members are read last, in order, and the first hold stops the run"

banner "the last read before the POST is a label read"
# Ordering, not just presence: a check that runs early and a write that
# runs late is the bug D13 names, and only the order of the log shows it.
reset
issue 28 "status:in-review"
run 0 "the clear path posts" -- 28 --as argus --body-file "$BODY"
last_read="$(tail -1 "$READS")"
[ "$last_read" = "repos/test/repo/issues/28" ] \
  || { cat "$READS" >&2; fail "the last read before the POST was '$last_read'"; }
pass "the final read before the write is the target's labels"

echo
echo "post_test.sh: all scenarios passed"
