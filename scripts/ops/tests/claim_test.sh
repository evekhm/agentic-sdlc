#!/usr/bin/env bash
# Tests for scripts/ops/claim.sh (#87).
#
#   bash scripts/ops/tests/claim_test.sh
#
# Hermetic: a stub `gh` first on PATH answers every read from a canned
# JSON fixture and RECORDS every write to a log instead of performing
# it, and a temp bare repository plays origin for a clone that plays the
# primary checkout. No network, no token, no GitHub.
#
# The refusals are the point — a claim script that half-claims is worse
# than none — so each of the five has a case, and the DRY_RUN case
# asserts the write log stayed empty while the reads still ran.
# Exit 0 with a PASS line per assertion, non-zero on the first failure.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
CLAIM_SH="$REPO/scripts/ops/claim.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FIXTURES="$WORK/fixtures"
WRITES="$WORK/writes.log"
CALLS="$WORK/calls.log"
mkdir -p "$FIXTURES" "$WORK/bin"
: > "$WRITES"
: > "$CALLS"

export GITHUB_REPO="test/repo"
export FIXTURES WRITES CALLS
export PATH="$WORK/bin:$PATH"
export CLAIM_ACTOR=tester CLAIM_SESSION=test-session CLAIM_STAGE=implement
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

# --- the stub -------------------------------------------------------------------
cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
# `gh api <path>` is a read and is answered from a fixture. Anything
# else is a write: it is logged verbatim and reported as success, so a
# test can assert on exactly what would have reached GitHub.
printf '%s\n' "$*" >> "$CALLS"
if [ "${1:-}" = "api" ] && [ "$#" -eq 2 ]; then
  file="$FIXTURES/${2//\//_}.json"
  [ -f "$file" ] || { echo "stub gh: no fixture for $2" >&2; exit 1; }
  cat "$file"
  exit 0
fi
printf '%s\n' "$*" >> "$WRITES"
if [ "$1" = "api" ]; then
  if [[ "$*" == *"/comments"* && "$*" == *"--method POST"* ]]; then
    if [ -f "$FIXTURES/post_response.json" ]; then
      cat "$FIXTURES/post_response.json"
      exit 0
    fi
  fi
fi
echo '{}'
STUB
chmod +x "$WORK/bin/gh"

# --- fixtures -------------------------------------------------------------------
# issue <n> <state> <labels-csv> <title> [<body>]
issue() {
  jq -n --argjson n "$1" --arg state "$2" --arg labels "$3" --arg title "$4" \
        --arg body "${5:-}" \
    '{number: $n, state: $state, title: $title, body: $body,
      labels: ($labels | if . == "" then [] else split(",") end | map({name: .}))}' \
    > "$FIXTURES/repos_test_repo_issues_$1.json"
  echo '[]' > "$FIXTURES/repos_test_repo_issues_$1_comments.json"
}
# comments <n> <login> <body> [<login> <body> ...]  — the thread, in order
comments() {
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
  OUT="$(cd "$PRIMARY" && DRY_RUN="${DRY:-1}" bash "$CLAIM_SH" "$@" 2>&1)"
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
no_writes() { # <name>
  if [ -s "$WRITES" ]; then
    cat "$WRITES" >&2; fail "$1 (GitHub was written to)"
  else pass "$1"; fi
}

banner() { printf '\n--- %s\n' "$*"; }

# --- the repository the claim enters --------------------------------------------
git init -q --bare -b main "$WORK/origin.git"
git clone -q "$WORK/origin.git" "$WORK/repo" 2>/dev/null
PRIMARY="$WORK/repo"
cd "$PRIMARY"
git checkout -q -b main
echo base > base.txt
printf '.claude/\n' > .gitignore   # as in the real repo: worktrees are not tracked
git add base.txt .gitignore && git commit -q -m base && git push -q -u origin main
WT="$PRIMARY/.claude/worktrees"

# ---------------------------------------------------------------------------
banner "a closed issue is not a work item"
issue 101 closed "" "Closed issue"
run 2 "closed exits 2" -- 101
has "not a work item" "closed: the refusal says what to do instead"
has 'AGENTS.md "Before filing an issue"' "closed: the refusal names the AGENTS.md section"
no_writes "closed: nothing was written"

banner "hold is the circuit breaker, checked before the rest"
issue 102 open "hold,in-progress" "Held issue" "Depends on #101"
run 2 "hold exits 2" -- 102
has "carries hold" "hold: the refusal names hold"
hasnt "depends on" "hold: no later condition is reported ahead of hold"
no_writes "hold: nothing was written"

banner "in-progress names its holder"
issue 103 open "in-progress" "Claimed issue"
comments 103 someone "Not a claim, just prose about the PR." \
              peer-bot "Claim: peer (agentic-sdlc-9), stage: implement. Worktree: .claude/worktrees/peer-103-x
second line that must not be printed"
run 2 "in-progress exits 2" -- 103
has "carries in-progress" "in-progress: the refusal names the label"
has "peer-bot: Claim: peer (agentic-sdlc-9)" "in-progress: the holder is the claim comment's author"
hasnt "second line" "in-progress: only the first line of the claim is printed"
no_writes "in-progress: nothing was written"

banner "in-progress with no structured claim still refuses"
issue 104 open "in-progress" "Claimed by nobody"
comments 104 someone "just prose"
run 2 "unnamed claim exits 2" -- 104
has "no comment opens with a structured claim line" "unnamed claim: the mutex names nobody"

banner "an open dependency blocks the claim"
issue 105 open "" "Dependent issue" "Body text.

Depends on #101, #106 (land the docs first)."
issue 106 open "" "The dependency"
run 2 "open dependency exits 2" -- 105
has "depends on #106, which is still open" "dependency: the refusal names the open issue"
hasnt "depends on #101" "dependency: a closed dependency is not reported"
no_writes "dependency: nothing was written"

banner "an existing branch or worktree is a collision, refused before the claim"
issue 107 open "" "Colliding issue"
# The path alone collides: the worktree is on a branch of another name.
git worktree add -q -b other/107 "$WT/tester-107-colliding-issue" main
run 2 "existing worktree path exits 2" -- 107
has ".claude/worktrees/tester-107-colliding-issue already exists" "collision: the refusal names the path"
has "never reuse a worktree you did not create" "collision: the refusal says why"
no_writes "collision: no claim was left dangling"
git worktree remove "$WT/tester-107-colliding-issue"
git branch -q -D other/107
# The branch alone collides: nothing is checked out on it.
git branch -q tester/107-colliding-issue main
run 2 "existing branch exits 2" -- 107
has "branch tester/107-colliding-issue already exists" "collision: the branch alone is enough"
no_writes "collision: the branch case wrote nothing either"
git branch -q -D tester/107-colliding-issue

# ---------------------------------------------------------------------------
banner "DRY_RUN=1 previews all four mutations and performs none"
issue 108 open "" "Claim script"
run 0 "DRY_RUN happy path exits 0" -- 108
has "would: gh api --method POST repos/test/repo/issues/108/labels -f labels[]=in-progress" \
    "DRY_RUN: the label add is previewed"
has "would: gh api --method POST repos/test/repo/issues/108/comments -f body=Claim: tester (test-session), stage: implement. Worktree: .claude/worktrees/tester-108-claim-script" \
    "DRY_RUN: the claim comment is previewed verbatim"
has "would: git -C $PRIMARY fetch -q origin" "DRY_RUN: the fetch is previewed"
has "would: git -C $PRIMARY worktree add -q -b tester/108-claim-script .claude/worktrees/tester-108-claim-script origin/main" \
    "DRY_RUN: the worktree add is previewed"
[ "$(printf '%s\n' "$OUT" | grep -c '^would: ')" = 4 ] \
  && pass "DRY_RUN: exactly four mutations, no more" \
  || { printf '%s\n' "$OUT" >&2; fail "DRY_RUN: unexpected number of would: lines"; }
[ "$(printf '%s\n' "$OUT" | tail -1)" = "$WT/tester-108-claim-script" ] \
  && pass "DRY_RUN: the last line is the path to cd into" \
  || { printf '%s\n' "$OUT" >&2; fail "DRY_RUN: last line is not the worktree path"; }
hasnt "warning: primary checkout" "DRY_RUN: a clean primary on main draws no warning"
no_writes "DRY_RUN: GitHub was not written to"
[ ! -e "$WT/tester-108-claim-script" ] \
  && pass "DRY_RUN: no worktree was created" || fail "DRY_RUN created a worktree"
! git show-ref -q --verify refs/heads/tester/108-claim-script \
  && pass "DRY_RUN: no branch was created" || fail "DRY_RUN created a branch"

banner "the slug argument overrides the derived one"
run 0 "explicit slug exits 0" -- 108 My_Slug
has "would: git -C $PRIMARY worktree add -q -b tester/108-my-slug .claude/worktrees/tester-108-my-slug origin/main" \
    "explicit slug: kebab-cased and used for both branch and path"

banner "a long title is cut to 40 characters on a word boundary"
issue 112 open "" "Abcdefghij klmnopqrst uvwxyz0123 456789ab cdefgh"
run 0 "long title exits 0" -- 112
has "-b tester/112-abcdefghij-klmnopqrst-uvwxyz0123 " "long title: the slug stops at the last full word under 40"

# ---------------------------------------------------------------------------
banner "a real claim writes both halves of the mutex and creates the worktree"
issue 109 open "" "Claimable issue"
DRY=0 run 0 "claim exits 0" -- 109
grep -qF 'api --method POST repos/test/repo/issues/109/labels -f labels[]=in-progress' "$WRITES" \
  && pass "claim: in-progress was added" || { cat "$WRITES" >&2; fail "claim: no label add"; }
grep -qF 'api --method POST repos/test/repo/issues/109/comments -f body=Claim: tester (test-session), stage: implement. Worktree: .claude/worktrees/tester-109-claimable-issue' "$WRITES" \
  && pass "claim: the one-line claim comment was posted" || { cat "$WRITES" >&2; fail "claim: no comment"; }
[ -d "$WT/tester-109-claimable-issue" ] \
  && pass "claim: the worktree exists" || fail "claim: no worktree"
[ "$(git -C "$WT/tester-109-claimable-issue" branch --show-current)" = tester/109-claimable-issue ] \
  && pass "claim: the worktree is on <actor>/<issue>-<slug>" || fail "claim: wrong branch"
[ "$(printf '%s\n' "$OUT" | tail -1)" = "$WT/tester-109-claimable-issue" ] \
  && pass "claim: the last line is the path to cd into" || fail "claim: last line is not the path"

banner "the second session to reach a claimed issue is refused, not queued"
issue 109 open "in-progress" "Claimable issue"
comments 109 tester-bot "Claim: tester (test-session), stage: implement. Worktree: .claude/worktrees/tester-109-claimable-issue"
: > "$WRITES"
run 2 "re-claiming exits 2" -- 109
has "tester-bot: Claim: tester (test-session)" "re-claim: the first session is named"
no_writes "re-claim: nothing was written"

banner "a dirty primary checkout is reported, never touched"
echo peer-work > "$PRIMARY/peer.txt"
issue 110 open "" "Another claimable issue"
run 0 "a dirty primary does not stop the claim" -- 110
has "warning: primary checkout" "dirty primary: the warning is printed"
has "left untouched" "dirty primary: the warning says it was left alone"
[ -f "$PRIMARY/peer.txt" ] && pass "dirty primary: the peer's file survived" || fail "peer file lost"
rm -f "$PRIMARY/peer.txt"

# ---------------------------------------------------------------------------
banner "--release drops the label and posts nothing"
: > "$WRITES"
DRY=0 run 0 "--release exits 0" -- --release 109
grep -qF 'api --method DELETE repos/test/repo/issues/109/labels/in-progress' "$WRITES" \
  && pass "--release: the label was removed" || { cat "$WRITES" >&2; fail "--release: no label delete"; }
! grep -qF '/comments' "$WRITES" \
  && pass "--release: no comment was posted (the handoff is the session's)" \
  || { cat "$WRITES" >&2; fail "--release posted a comment"; }
has "handoff comment is yours" "--release: the caller is told to post the handoff"

banner "--release on an unclaimed issue fails"
issue 111 open "" "Unclaimed issue"
: > "$WRITES"
DRY=0 run 2 "--release without the label exits 2" -- --release 111
has "there is no claim to release" "--release: the refusal says why"
no_writes "--release: nothing was written"

banner "argument handling"
run 1 "an unknown flag is refused" -- --bogus 108
run 1 "a non-numeric issue is refused" -- not-a-number
: > "$WRITES"
run 1 "a missing issue number is refused" --
no_writes "bad arguments never reach GitHub"

echo
echo "claim_test.sh: all scenarios passed"

banner "identity tests: human fallback is silent and skips read-back"
mkdir -p "$PRIMARY/personas"
rm -f "$PRIMARY/personas/tester.yaml"
issue 113 open "" "Human issue"
: > "$WRITES"
: > "$CALLS"
DRY=0 run 0 "human fallback is silent" -- 113
hasnt "warning: no persona credentials" "human fallback: no warning"
if grep -qF "api user" "$CALLS"; then
  cat "$CALLS" >&2; fail "human fallback: user API call made"
else
  pass "human fallback: no user API call"
fi

banner "identity tests: author mismatch fails closed"
cat > "$PRIMARY/personas/tester.yaml" <<'YAML'
authority:
  identity: "expected-bot"
YAML
echo '{"user": {"login": "wrong-bot"}, "html_url": "https://github.com/test/repo/issues/114#issuecomment-123"}' > "$FIXTURES/post_response.json"
issue 114 open "" "Mismatch issue"
: > "$WRITES"
DRY=0 run 1 "mismatch fails closed" -- 114
has "the comment on #114 was posted by 'wrong-bot', but CLAIM_ACTOR says 'tester', whose personas/tester.yaml names 'expected-bot'" "mismatch: fails with expected message"
has "remove the in-progress label" "mismatch: instructions name the label"

banner "identity tests: persona path posts as the App identity"
echo '{"user": {"login": "expected-bot"}, "html_url": "https://github.com/test/repo/issues/115#issuecomment-124"}' > "$FIXTURES/post_response.json"
issue 115 open "" "Match issue"
: > "$WRITES"
DRY=0 run 0 "match succeeds" -- 115
grep -qF 'api --method POST repos/test/repo/issues/115/comments -f body=Claim: tester (test-session), stage: implement. Worktree: .claude/worktrees/tester-115-match-issue' "$WRITES" \
  && pass "match: comment was posted" || fail "match: comment was not posted"
