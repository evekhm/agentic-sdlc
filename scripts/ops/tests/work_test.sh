#!/usr/bin/env bash
# Tests for scripts/ops/work.sh (#36, intent/36-dispatch/plan.md T9).
#
#   bash scripts/ops/tests/work_test.sh
#
# Hermetic: a stub `gh` first on PATH answers every read from a canned
# JSON fixture, and stub `claude` / `agy` fail loudly if anything is
# launched by a scenario that did not ask for it. No network, no token,
# and nothing is written to GitHub — the stubs log any attempt and the
# run fails on it.
#
# Each scenario names the spec row it pins. The refusals are the point:
# a dispatcher that guesses at a corrupted or claimed issue is worse
# than one that does nothing, so every D5 condition has a case here.
# Exit 0 with a PASS line per assertion, non-zero on the first failure.
#
# #43 adds three things the #36 suite could not express:
#
#   $LAUNCHES   every stub launch, with the GH_TOKEN the child saw.
#               Separate from $WRITES so a DELIBERATE launch does not
#               look like a forbidden one; $WRITES keeps its old
#               meaning, "something was attempted that must never be".
#   $MINTS      every call to the stub mint script, so a test can assert
#               ZERO token exchanges as cheaply as it asserts zero
#               writes (D11, D20).
#   fixture_tree  a temp REPO_ROOT owning its own copy of work.sh.
#               work.sh resolves the mint script by absolute path from
#               BASH_SOURCE (D24), so PATH cannot stub it; a whole tree
#               can. It is also the only way to test a persona pinned to
#               a harness with no launch row, now that every pinned
#               harness has one.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WORK_SH="$REPO/scripts/ops/work.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FIXTURES="$WORK/fixtures"
WRITES="$WORK/writes.log"
LAUNCHES="$WORK/launches.log"
MINTS="$WORK/mints.log"
mkdir -p "$FIXTURES" "$WORK/bin"
: > "$WRITES"; : > "$LAUNCHES"; : > "$MINTS"

export GITHUB_REPO="test/repo"
export FIXTURES WRITES LAUNCHES MINTS
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
# The two harness stubs. Unless a scenario sets LAUNCH_OK=1 they behave
# exactly as the #36 suite's stub claude did: record the attempt in
# $WRITES and fail loudly. With LAUNCH_OK=1 the scenario is deliberately
# launching, so they record what they saw — including the GH_TOKEN the
# child inherited, which is how D12 is proved — print whatever
# $CLAUDE_JSON / $AGY_JSON names, and exit $CLAUDE_RC / $AGY_RC.
cat > "$WORK/bin/claude" <<'STUB'
#!/usr/bin/env bash
echo "claude $*" >> "$LAUNCHES"
echo "claude-saw-GH_TOKEN=${GH_TOKEN:-none}" >> "$LAUNCHES"
echo "claude-saw-pwd=$PWD" >> "$LAUNCHES"
echo "claude-saw-helper-reset=${GIT_CONFIG_VALUE_1-unset}" >> "$LAUNCHES"
echo "claude-saw-helper=${GIT_CONFIG_VALUE_2:-none}" >> "$LAUNCHES"
echo "claude-saw-insteadOf=${GIT_CONFIG_VALUE_3:-none}" >> "$LAUNCHES"
if [ "${LAUNCH_OK:-0}" != "1" ]; then
  echo "claude $*" >> "$WRITES"
  echo "stub claude: a session was launched by a test that forbids it" >&2
  exit 1
fi
[ -z "${CLAUDE_JSON:-}" ] || cat "${CLAUDE_JSON}"
exit "${CLAUDE_RC:-0}"
STUB
cat > "$WORK/bin/agy" <<'STUB'
#!/usr/bin/env bash
echo "agy $*" >> "$LAUNCHES"
echo "agy-saw-GH_TOKEN=${GH_TOKEN:-none}" >> "$LAUNCHES"
echo "agy-saw-pwd=$PWD" >> "$LAUNCHES"
echo "agy-saw-helper-reset=${GIT_CONFIG_VALUE_1-unset}" >> "$LAUNCHES"
echo "agy-saw-helper=${GIT_CONFIG_VALUE_2:-none}" >> "$LAUNCHES"
echo "agy-saw-insteadOf=${GIT_CONFIG_VALUE_3:-none}" >> "$LAUNCHES"
if [ "${LAUNCH_OK:-0}" != "1" ]; then
  echo "agy $*" >> "$WRITES"
  echo "stub agy: a session was launched by a test that forbids it" >&2
  exit 1
fi
[ -z "${AGY_JSON:-}" ] || cat "${AGY_JSON}"
exit "${AGY_RC:-0}"
STUB
chmod +x "$WORK/bin/gh" "$WORK/bin/claude" "$WORK/bin/agy"

# fixture_tree -> a temp REPO_ROOT owning its own copy of work.sh.
# personas/ and config/ are COPIED rather than symlinked so a scenario
# can repin a persona with sed, exactly as compiler_roundtrip.sh does;
# the compiled targets come along because the D3 preflight reads them;
# intent/ is symlinked so the folder-reuse rule answers the same way.
fixture_tree() {
  local t
  t="$(mktemp -d "$WORK/tree.XXXX")"
  cp -r "$REPO/personas" "$REPO/config" "$REPO/scripts" "$REPO/.agents" "$t/"
  mkdir -p "$t/.claude"
  cp -r "$REPO/.claude/agents" "$t/.claude/"
  ln -s "$REPO/intent" "$t/intent"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'echo "mint $*" >> "$MINTS"' \
    'if [ "${MINT_FAIL:-0}" = "1" ]; then' \
    '  echo "stub mint: no private key for $1" >&2' \
    '  exit 1' \
    'fi' \
    'echo "stub-token-for-$1"' \
    > "$t/scripts/auth/mint_app_token.py"
  # Deliberately NOT chmod +x. `cp -r` above preserved the real file's
  # mode and `>` does not change it, so the stub is executable exactly
  # when the tracked file is. A chmod here would make the fixture
  # structurally blind to the defect that stopped both first smoke
  # launches — mint_app_token.py committed 100644 — and every scenario
  # below would keep passing while no real launch could mint at all.
  # The direct assertion on the real files is a few lines down.
  printf '%s\n' "$t"
}

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

# run <expected-exit> <name> -- <args...>; stdout+stderr land in $OUT.
# $DRY and $HL set the two modes; $TREE picks a fixture_tree's own copy
# of work.sh over the repository's.
OUT=""
TREE=""
run() {
  local want="$1" name="$2" rc=0
  shift 3  # drop want, name and the literal --
  set +e
  OUT="$(DRY_RUN="${DRY:-1}" HEADLESS="${HL:-0}" \
    "${TREE:-$REPO}/scripts/ops/work.sh" "$@" 2>&1)"
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
banner "#43 D11/D13 the executables the launcher runs directly are executable"
# Two files are invoked as programs rather than handed to an
# interpreter: work.sh runs mint_app_token.py, and git runs
# git-credential-persona. Their mode bit is part of the contract, and
# the first real smoke run died at `Permission denied` because
# mint_app_token.py had been committed 100644 — every caller until then
# had run it as `python3 <path>`. No scenario below can catch that:
# fixture_tree writes its own stub over the copy. Assert the real files,
# in the working tree AND in the index, so a re-add or a patch that
# drops the mode fails here, loudly, instead of at push time with the
# work already done.
for prog in scripts/auth/mint_app_token.py scripts/auth/git-credential-persona; do
  [ -x "$REPO/$prog" ] || fail "$prog is not executable; the launcher cannot run it"
  pass "$prog is executable in the working tree"
done
if git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
  for prog in scripts/auth/mint_app_token.py scripts/auth/git-credential-persona; do
    mode="$(git -C "$REPO" ls-files -s -- "$prog" | awk '{print $1}')"
    [ "$mode" = "100755" ] \
      || fail "$prog is $mode in the index, not 100755; a fresh clone cannot launch"
    pass "$prog is recorded 100755 in the index"
  done
else
  pass "not a git checkout — index modes not checked"
fi

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
has ".claude/agents/odyssey.md" "D8: the compiled target is printed"
has "command:  timeout 5460 claude --agent odyssey" \
  "D8: the exact command line is printed, wrapped at the persona's cap"
has "nothing was launched, nothing was written, and no token was minted" \
  "D8: the dry run says so"

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

banner "#43 D1/D5/D6/D9 the antigravity row is real, and always headless"
# The #36 suite used this stage as its "unlaunchable harness" case.
# There IS a row now, so the scenario splits: this half asserts the row,
# and the fixture_tree half further down keeps the *) arm reachable.
issue 113 open "status:build" "Plan the thing"
run 0 "D1: a status:build issue resolves the antigravity row" -- 113
has "harness:  antigravity" "D1: the pinned harness is printed"
has ".agents/agents/daedalus/agent.md" "D3: the compiled target is the file agy reads"
has "command:  timeout 2760 agy -p " "D6: the child is wrapped at 45m + a minute"
has " --agent daedalus " "D1: the persona reaches agy as --agent"
has " --add-dir $REPO " "D1/D24: --add-dir is the checkout that owns this script"
has " --model gemini-3.1-pro-high " "D9: the model comes from the compiled sidecar"
has " --output-format json " "D14: the outcome has to be machine-readable"
has " --print-timeout 45m" "D6: the timeout comes from personas/daedalus.yaml"
has "prompt:   Work issue #113 in this repository." "D2: the prompt names the number"
has "WORK-RESULT: <ok|refused|blocked> #113" "D2: the prompt asks for the result line"
hasnt 'agy -p \#113 ' "D2: a bare #<n> is never the prompt"
HL=1 run 0 "D5: antigravity under HEADLESS=1 resolves the same row" -- 113
has "command:  timeout 2760 agy -p " "D5: antigravity has one row, not two"

banner "#43 D5 claude-code is interactive by default and headless on demand"
issue 130 open "status:implementing" "Implement the thing"
run 0 "D5: no HEADLESS resolves the interactive row" -- 130
has "command:  timeout 5460 claude --agent odyssey " "D5: the interactive form"
hasnt " -p " "D5: the interactive row does not use print mode"
HL=1 run 0 "D5: HEADLESS=1 resolves the print row" -- 130
has "command:  timeout 5460 claude -p " "D5: the headless form"
has " --output-format json" "D14: headless output has to be parseable"
hasnt "--print-timeout" "D6: claude-code does not take agy's print timeout"

banner "#43 D2 one prompt literal, both harnesses, both modes"
# The launcher must not be able to tell a session WHICH RUNG to work:
# that is the same rule that closes argv (#36 D7), applied at the prompt
# boundary. Asserted against the script's source, not its output, so a
# second literal added later cannot hide in a mode this suite skips.
prompt_lines="$(grep -c 'Work issue #\$ISSUE' "$WORK_SH")"
[ "$prompt_lines" = "1" ] \
  || fail "D2: expected exactly one prompt literal in work.sh, found $prompt_lines"
pass "D2: work.sh holds exactly one prompt literal"
if grep 'Work issue #\$ISSUE' "$WORK_SH" | grep -qE 'stage|plan|spec|branch'; then
  fail "D2: the prompt names a stage, plan, spec or branch"
fi
pass "D2: the prompt names a number and nothing else"

banner "#43 D11 a dry run prints the identity and mints nothing"
: > "$MINTS"
run 0 "D11: a dry run of a single-owner stage exits 0" -- 113
has "identity: evekhm-daedalus-app[bot] (token minted at launch; not printed)" \
  "D11: the identity is named and the token is not"
has "root:     $REPO" "D24: the checkout a session will edit is printed"
if printf '%s\n' "$OUT" | grep -qE '[A-Za-z0-9_]{36,}'; then
  fail "D11: the output contains a token-shaped string"
fi
pass "D11: nothing token-shaped was printed"
[ ! -s "$MINTS" ] || { cat "$MINTS" >&2; fail "D11: a dry run minted a token"; }
pass "D11: a dry run exchanged no token"

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

banner "nothing above this line launched or wrote"
[ ! -s "$WRITES" ] || { cat "$WRITES" >&2; fail "a write or launch was attempted"; }
[ ! -s "$LAUNCHES" ] || { cat "$LAUNCHES" >&2; fail "a session was launched"; }
[ ! -s "$MINTS" ] || { cat "$MINTS" >&2; fail "a token was minted"; }
pass "no GitHub write, no launch and no token exchange in any resolve-only scenario"

# =============================================================================
# #43 — the launching half. Everything below runs against a fixture_tree:
# work.sh resolves the mint script by absolute path from BASH_SOURCE, so
# a tree is the only way to stub it, and a tree is also the only way to
# take a compiled target away or pin a persona to a harness with no row.
# =============================================================================
T="$(fixture_tree)"

banner "#43 T4/D10 a harness with no launch row still prints and exits 0"
# Every pinned harness has a row now, so the *) arm of launch_argv would
# be dead code without this. It stays reachable and stays tested.
sed -i 's/^  daedalus:  { harness: antigravity }/  daedalus:  { harness: nonesuch }/' \
  "$T/config/deployments.yaml"
grep -q 'harness: nonesuch' "$T/config/deployments.yaml" \
  || fail "T4: the fixture repin did not take"
: > "$WRITES"; : > "$LAUNCHES"; : > "$MINTS"
TREE="$T" DRY=0 run 0 "D10: a harness this script cannot start exits 0" -- 113
has "harness:  nonesuch" "D10: the pinned harness is printed"
has "(no compiled target known for harness nonesuch)" \
  "D10: an unknown harness has no target to preflight"
has "is not one this script starts" "D10: it says why nothing ran"
[ ! -s "$LAUNCHES" ] || { cat "$LAUNCHES" >&2; fail "D10: something was launched"; }
[ ! -s "$MINTS" ] || { cat "$MINTS" >&2; fail "D10: a token was minted for a harness with no row"; }
pass "D10: nothing was launched and nothing was minted for an unlaunchable harness"
sed -i 's/^  daedalus:  { harness: nonesuch }/  daedalus:  { harness: antigravity }/' \
  "$T/config/deployments.yaml"

banner "#43 D3 a missing compiled target is exit 1, before any model call"
# agy's failure mode for a missing agent file is SILENT: it runs its
# stock agent and exits 0. Before the process starts is the only cheap
# place to notice.
mv "$T/.agents/agents/daedalus/agent.md" "$T/.agents/agents/daedalus/agent.md.away"
: > "$WRITES"; : > "$LAUNCHES"; : > "$MINTS"
TREE="$T" DRY=0 run 1 "D3: a missing agent.md exits 1" -- 113
has ".agents/agents/daedalus/agent.md" "D3: the refusal names the missing path"
has "sync_agents.py" "D3: it says how to fix it"
[ ! -s "$LAUNCHES" ] || { cat "$LAUNCHES" >&2; fail "D3: a session was launched anyway"; }
[ ! -s "$MINTS" ] || { cat "$MINTS" >&2; fail "D3: a token was minted for a launch that never happened"; }
pass "D3: no model call and no token exchange behind a missing target"
# D20: for an owner that is only being PRINTED the same condition is a
# marker, not an exit — a broken atlas target must never stop --as argus.
mv "$T/.agents/agents/atlas/agent.md" "$T/.agents/agents/atlas/agent.md.away"
TREE="$T" DRY=0 run 0 "D20: a two-owner stage with a broken target still exits 0" -- 112
has "(missing)" "D20: the broken target is marked, not fatal"
has "--> argus" "D20: the other reviewer is still printed"
TREE="$T" run 0 "D20: --as argus is unaffected by atlas's broken target" -- 112 --as argus
hasnt "(missing)" "D20: argus's own target is intact"
mv "$T/.agents/agents/atlas/agent.md.away" "$T/.agents/agents/atlas/agent.md"
mv "$T/.agents/agents/daedalus/agent.md.away" "$T/.agents/agents/daedalus/agent.md"

banner "#43 D20 a two-owner stage mints nothing at all"
: > "$MINTS"
TREE="$T" DRY=0 run 0 "D20: status:in-review launches neither owner" -- 112
has "printing both and launching neither" "D20: it says it launched nothing"
[ ! -s "$MINTS" ] || { cat "$MINTS" >&2; fail "D20: a two-owner stage exchanged a token"; }
pass "D20: two owners printed, zero tokens minted"

banner "#43 D3/D8 a harness binary that is not installed is exit 1, before any mint"
# The sibling of the missing-target refusal above, and the one refusal
# that cannot be made in the generic preflight: which binary is needed
# is unknown until the persona, its harness and any --as narrowing have
# resolved. Without it the run mints a one-hour credential and then
# execs a program that does not exist — 127, outside D8's 0/1/2
# contract, with a live token abandoned.
#
# PATH is narrowed rather than the stub moved aside: this machine has a
# REAL agy on PATH, and a test that reaches it would spend a live
# persona launch. $WORK/bin-noharness carries the gh stub and nothing
# else, and /usr/bin:/bin supplies jq, timeout and env.
mkdir -p "$WORK/bin-noharness"
cp "$WORK/bin/gh" "$WORK/bin-noharness/gh"
: > "$WRITES"; : > "$LAUNCHES"; : > "$MINTS"
saved_path="$PATH"
PATH="$WORK/bin-noharness:/usr/bin:/bin"
TREE="$T" DRY=0 HL=1 LAUNCH_OK=1 \
  run 1 "D3: a harness binary that is not installed exits 1" -- 113
PATH="$saved_path"
has "agy is not installed" "D3: the refusal names the binary that is missing"
has "nothing was minted" "D3: it says no token was exchanged"
[ ! -s "$MINTS" ] || { cat "$MINTS" >&2; fail "D11: a token was minted for a launch that could not start"; }
[ ! -s "$LAUNCHES" ] || { cat "$LAUNCHES" >&2; fail "D3: something was launched without its binary"; }
pass "D11: zero mints and zero launches behind a missing harness binary"

banner "#43 D12 a failed mint is fatal and nothing is launched"
: > "$WRITES"; : > "$LAUNCHES"; : > "$MINTS"
TREE="$T" DRY=0 MINT_FAIL=1 LAUNCH_OK=1 \
  run 1 "D12: a mint that fails exits 1" -- 113
has "cannot mint an App token for daedalus" "D12: the refusal names the persona"
has "refusing to launch as somebody else" "D12: it says why it will not fall back"
[ ! -s "$LAUNCHES" ] || { cat "$LAUNCHES" >&2; fail "D12: a session was launched without an identity"; }
pass "D12: no session ran without an attributable identity"

banner "#43 D12/D13 the child gets the MINTED token, never the ambient one"
: > "$WRITES"; : > "$LAUNCHES"; : > "$MINTS"
# Snapshotted, not asserted absent: this machine's ~/.gitconfig already
# carries a credential helper, which is precisely why D13's reset exists.
# What must hold is that work.sh CHANGED nothing here.
git_config_before="$(git config --list 2>/dev/null | sort)"
printf '%s\n' '{"status":"SUCCESS","response":"done\nWORK-RESULT: ok #113 plan committed"}' \
  > "$WORK/agy_ok.json"
TREE="$T" DRY=0 HL=1 LAUNCH_OK=1 AGY_JSON="$WORK/agy_ok.json" \
  GH_TOKEN="ambient-not-this-one" GITHUB_TOKEN="ambient-not-this-one" \
  run 0 "D14: WORK-RESULT: ok maps to exit 0" -- 113
grep -qF "agy-saw-GH_TOKEN=stub-token-for-daedalus" "$LAUNCHES" \
  || { cat "$LAUNCHES" >&2; fail "D12: the child did not see the minted token"; }
pass "D12: the child saw the minted token, not the operator's ambient one"
grep -qF "agy-saw-helper=$T/scripts/auth/git-credential-persona daedalus" "$LAUNCHES" \
  || { cat "$LAUNCHES" >&2; fail "D13: the credential helper was not installed in the child"; }
pass "D13: the child's git is pointed at the re-minting credential helper"
# Exact line, empty value: `credential.https://github.com.helper` is a
# DIFFERENT key from `credential.helper` with its own list, and git
# appends helpers. Resetting only the generic key leaves an operator's
# URL-specific global helper ahead of ours, so the child would push as
# the operator — measured. The empty entry at index 1 is the reset.
grep -qxF "agy-saw-helper-reset=" "$LAUNCHES" \
  || { cat "$LAUNCHES" >&2; fail "D13: the URL-specific helper list was not reset"; }
pass "D13: the operator's own https://github.com helper is reset out of the way"
grep -qF "agy-saw-insteadOf=git@github.com:" "$LAUNCHES" \
  || { cat "$LAUNCHES" >&2; fail "D13: the SSH insteadOf rewrite was not installed"; }
pass "D13: an SSH origin is rewritten so the helper is consulted at all"
[ "$(grep -c '^mint ' "$MINTS")" = "1" ] \
  || { cat "$MINTS" >&2; fail "D11: expected exactly one mint for one launch"; }
pass "D11: exactly one token was minted, for the one persona launched"
# The parent shell is left exactly as it was found: the whole install is
# environment-only, so a crashed session leaves no credential config.
[ "$(git config --list 2>/dev/null | sort)" = "$git_config_before" ] \
  || fail "D13: the launcher changed the parent's git config"
pass "D13: the parent shell's git config is byte-identical before and after"
[ -z "${GIT_CONFIG_COUNT:-}" ] \
  || fail "D13: the launcher exported GIT_CONFIG_* into the parent shell"
pass "D13: the install reached the child's environment and nothing else"

banner "#43 the child starts in the checkout work.sh came from"
: > "$LAUNCHES"; : > "$MINTS"
# Run the fixture's work.sh from a directory that is NOT the fixture:
# claude-code has no --add-dir, it takes $PWD as the project, so a
# launcher invoked by absolute path from elsewhere would otherwise hand
# the session a different checkout than the one it just resolved.
( cd /tmp && TREE="$T" DRY=0 HL=1 LAUNCH_OK=1 AGY_JSON="$WORK/agy_ok.json" \
    run 0 "the launch happens with the resolved root as \$PWD" -- 113 )
grep -qxF "agy-saw-pwd=$T" "$LAUNCHES" \
  || { cat "$LAUNCHES" >&2; fail "the child inherited the caller's directory, not the repo root"; }
pass "the child's \$PWD is the checkout work.sh resolved, not the caller's"

banner "#43 D14 the four headless outcomes map to three exit codes"
printf '%s\n' '{"status":"SUCCESS","response":"REFUSED\nWORK-RESULT: refused #113 hold label present"}' \
  > "$WORK/agy_refused.json"
printf '%s\n' '{"status":"SUCCESS","response":"WORK-RESULT: blocked #113 waiting on #47"}' \
  > "$WORK/agy_blocked.json"
printf '%s\n' '{"status":"ERROR","response":"","error":"timeout waiting for response"}' \
  > "$WORK/agy_error.json"
printf '%s\n' '{"status":"SUCCESS","response":"I did some things and stopped talking."}' \
  > "$WORK/agy_silent.json"
TREE="$T" DRY=0 HL=1 LAUNCH_OK=1 AGY_JSON="$WORK/agy_refused.json" \
  run 2 "D14: WORK-RESULT: refused maps to exit 2" -- 113
has "daedalus reported: refused" "D14: the verdict is reported"
has "REFUSED" "D14: the raw session output is echoed, not swallowed"
TREE="$T" DRY=0 HL=1 LAUNCH_OK=1 AGY_JSON="$WORK/agy_blocked.json" \
  run 2 "D14/D23: WORK-RESULT: blocked maps to exit 2, the same code as a launcher refusal" -- 113
TREE="$T" DRY=0 HL=1 LAUNCH_OK=1 AGY_JSON="$WORK/agy_error.json" AGY_RC=1 \
  run 1 "D14: status ERROR maps to exit 1" -- 113
has "did not complete" "D14: it says the session did not finish"
TREE="$T" DRY=0 HL=1 LAUNCH_OK=1 AGY_JSON="$WORK/agy_silent.json" \
  run 1 "D14: SUCCESS with no WORK-RESULT line maps to exit 1" -- 113
has "printed no WORK-RESULT line" "D14: it says the outcome was not observed"
has "I did some things" "D14: what the session did say is still printed"

banner "#43 D14 the result line is read from the DECODED text, not the raw JSON"
# A JSON string escapes the newline, so grepping '^WORK-RESULT:' over
# the raw bytes silently never matches. This fixture has the line on a
# second line of the response and nowhere else.
grep -q '\\n' "$WORK/agy_ok.json" || fail "D14: the fixture does not exercise an escaped newline"
pass "D14: the ok fixture carries the result line behind an escaped newline"

banner "#43 D14 the LAST WORK-RESULT line wins"
printf '%s\n' '{"status":"SUCCESS","response":"WORK-RESULT: blocked #113 first thought\nchanged my mind\nWORK-RESULT: ok #113 done after all"}' \
  > "$WORK/agy_last.json"
TREE="$T" DRY=0 HL=1 LAUNCH_OK=1 AGY_JSON="$WORK/agy_last.json" \
  run 0 "D14: the last result line decides" -- 113
has "daedalus reported: ok" "D14: the later verdict wins"

banner "#43 D15 interactive claude-code is exec'd and its exit code is NOT mapped"
: > "$LAUNCHES"
TREE="$T" DRY=0 LAUNCH_OK=1 CLAUDE_RC=7 \
  run 7 "D15: the harness's own exit code survives unmapped" -- 130
grep -qF "claude --agent odyssey" "$LAUNCHES" \
  || { cat "$LAUNCHES" >&2; fail "D15: the interactive form was not the one launched"; }
pass "D15: the interactive row ran and its own code came back"
# 7 is neither 0, 1 nor 2 — proof the headless mapping did not touch it.
TREE="$T" DRY=0 HL=1 LAUNCH_OK=1 CLAUDE_RC=7 CLAUDE_JSON=/dev/null \
  run 1 "D15: the same code under HEADLESS=1 IS mapped" -- 130
pass "D15: the mapping applies to headless launches only"

banner "#43 D14/P4 the claude-code JSON shape is parsed by its own key names"
printf '%s\n' '{"type":"result","subtype":"success","is_error":false,"result":"WORK-RESULT: ok #130 implemented"}' \
  > "$WORK/cc_ok.json"
printf '%s\n' '{"type":"result","subtype":"error","is_error":true,"result":""}' \
  > "$WORK/cc_err.json"
TREE="$T" DRY=0 HL=1 LAUNCH_OK=1 CLAUDE_JSON="$WORK/cc_ok.json" \
  run 0 "P4: .result carries the response text for claude-code" -- 130
has "odyssey reported: ok" "P4: the verdict is read out of .result"
TREE="$T" DRY=0 HL=1 LAUNCH_OK=1 CLAUDE_JSON="$WORK/cc_err.json" \
  run 1 "P4: is_error true is the claude-code spelling of status ERROR" -- 130

banner "#43 D13 the credential helper mints on get and no-ops on store/erase"
HELPER="$T/scripts/auth/git-credential-persona"
[ -x "$HELPER" ] || fail "D13: $HELPER is not executable"
: > "$MINTS"
helper_out="$(printf 'protocol=https\nhost=github.com\n\n' \
  | "$HELPER" daedalus get 2>"$WORK/helper.err")"
grep -qx "username=x-access-token" <<<"$helper_out" \
  || { printf '%s\n' "$helper_out" >&2; fail "D13: no username line"; }
grep -qx "password=stub-token-for-daedalus" <<<"$helper_out" \
  || { printf '%s\n' "$helper_out" >&2; fail "D13: the password is not the minted token"; }
pass "D13: get prints the two credential lines"
[ ! -s "$WORK/helper.err" ] \
  || { cat "$WORK/helper.err" >&2; fail "D13: the helper wrote to stderr"; }
pass "D13: nothing reached stderr, so no token can leak into a log"
"$HELPER" daedalus store </dev/null >/dev/null 2>&1 \
  || fail "D13: store must be a no-op that exits 0, or the push fails"
"$HELPER" daedalus erase </dev/null >/dev/null 2>&1 \
  || fail "D13: erase must be a no-op that exits 0, or the push fails"
pass "D13: store and erase are no-ops that exit 0"
[ "$(grep -c '^mint ' "$MINTS")" = "1" ] \
  || { cat "$MINTS" >&2; fail "D13: store/erase minted a token"; }
pass "D13: only the get minted — one call, one token"
# Two gets mint twice: that is the whole reason for a helper rather than
# a snapshot, since an installation token dies before a 90-minute cap.
"$HELPER" daedalus get </dev/null >/dev/null 2>&1
[ "$(grep -c '^mint ' "$MINTS")" = "2" ] \
  || { cat "$MINTS" >&2; fail "D13: a second get did not re-mint"; }
pass "D13: a second get mints a second time"

banner "#43 D4 work.sh reads no log file and names no home directory"
# The home-path fragments are ASSEMBLED from pieces, the same trick
# scripts/ci/sanitize_check.sh uses on itself: the home-variable
# reference written out literally here would make this test file its own
# sanitize finding.
_h='hom'; _u='Users'
if grep -nE "\.gemini|antigravity-cli|/(${_h}e|${_u})/|[\$]${_h^^}E|~/" "$WORK_SH"; then
  fail "D4: work.sh reaches for a machine-local path"
fi
pass "D4: work.sh opens no CLI log and names no home directory"

echo
echo "work_test.sh: all scenarios passed"
