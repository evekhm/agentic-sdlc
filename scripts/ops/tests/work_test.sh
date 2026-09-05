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

# Hermetic against the launcher this suite tests. `launch_child()`
# exports GIT_CONFIG_COUNT and GIT_CONFIG_KEY/VALUE_0..3 into every
# session it starts, so a persona running these tests from inside a
# launched session hands the stub child an OFFSET install and the
# fixed-name assertions miss — one spurious `FAIL: D13: the credential
# helper was not installed in the child`, for a difference in the
# caller's environment rather than in the tree (Argus #164 R2-1). That
# is now the normal way this suite runs: the runner work reviewers do
# starts by running the repository's own gates. The AT-7 scenario sets
# these deliberately and is unaffected — it exports them itself, after
# this scrub.
unset GIT_CONFIG_COUNT
for _i in 0 1 2 3 4 5 6 7; do unset "GIT_CONFIG_KEY_$_i" "GIT_CONFIG_VALUE_$_i"; done
unset _i

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
# Canned reads only. Anything that is not `gh api [--paginate] <path>`
# is a write attempt as far as this test is concerned, and is recorded.
paginate=0
args=()
for a in "$@"; do
  case "$a" in
    --paginate) paginate=1 ;;
    *) args+=("$a") ;;
  esac
done
if [ "${args[0]:-}" != "api" ] || [ "${#args[@]}" -ne 2 ]; then
  echo "gh $*" >> "$WRITES"
  echo "stub gh: refusing non-read call: $*" >&2
  exit 1
fi
path="${args[1]%%\?*}"
query=""
[ "${args[1]}" = "$path" ] || query="${args[1]#*\?}"
file="$FIXTURES/${path//\//_}.json"
[ -f "$file" ] || { echo "stub gh: no fixture for $path" >&2; exit 1; }
# PAGINATION IS MODELLED, because the truncation IS the defect (#51,
# Atlas AT-2). The real API answers a LIST read one page at a time —
# 30 items by default, `per_page` up to 100 — and a caller that does
# not paginate gets the first page and no hint that there is another.
# A stub that always returned the whole fixture would make a
# regression test for the 31st comment vacuous: it would pass against
# the unfixed script too. Object fixtures (an issue, a pull request)
# are not lists and are returned whole.
if ! jq -e 'type == "array"' "$file" >/dev/null 2>&1; then
  cat "$file"
  exit 0
fi
per_page=30
case "$query" in
  *per_page=*) per_page="${query##*per_page=}"; per_page="${per_page%%&*}" ;;
esac
if [ "$paginate" = "1" ]; then
  # One JSON array per page, exactly as `gh api --paginate` emits them.
  jq -c --argjson n "$per_page" \
    'if length == 0 then [] else [range(0; length; $n) as $i | .[$i:$i+$n]][] end' "$file"
else
  jq -c --argjson n "$per_page" '.[0:$n]' "$file"
fi
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
# D15's "inherits … the terminal", made measurable (PR #60, R2-1). An
# interactive harness does two things this stub otherwise never did: it
# asks the terminal who its foreground process group is, and it puts the
# terminal in raw mode. The second is a `tcsetattr`, which every
# interactive TUI performs at startup and which from a BACKGROUND
# process group raises SIGTTOU — what `timeout` without `--foreground`
# produces, because it calls `setpgid(0,0)`.
#
# The raw-mode probe is GUARDED by the group comparison, and the guard
# is not politeness: the kernel sends SIGTTOU to the whole process
# GROUP, so a probe that ran anyway would stop this stub, `timeout` and
# every helper with it — an unkillable-from-inside group stop that hangs
# until the wrapper's 91-minute cap. Measured: it does exactly that.
# So the deterministic assertion is the group comparison, which fails in
# milliseconds, and the tcsetattr runs only once the group is known to
# be the foreground one — where it is a real `tcsetattr` against a real
# pty, not a simulation. Recorded here, asserted by the scenario below.
if [ -t 0 ] && [ -t 1 ]; then
  _pgid="$(ps -o pgid= -p $$ | tr -d ' ')"
  _tpgid="$(ps -o tpgid= -p $$ | tr -d ' ')"
  echo "claude-saw-pgid=$_pgid" >> "$LAUNCHES"
  echo "claude-saw-tpgid=$_tpgid" >> "$LAUNCHES"
  if [ -n "$_pgid" ] && [ "$_pgid" = "$_tpgid" ]; then
    _saved="$(stty -g </dev/tty 2>/dev/null || true)"   # tcgetattr: safe either way
    if stty raw </dev/tty >/dev/null 2>&1; then
      [ -z "$_saved" ] || stty "$_saved" </dev/tty >/dev/null 2>&1 || true
      echo "claude-saw-stty=ok" >> "$LAUNCHES"
    else
      echo "claude-saw-stty=fail" >> "$LAUNCHES"
    fi
  else
    echo "claude-saw-stty=skipped-background-process-group" >> "$LAUNCHES"
  fi
fi
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
# Every GIT_CONFIG_* the child actually inherited, so an offset install
# (AT-7) can be asserted by index rather than by the fixed names above.
env | grep '^GIT_CONFIG_' | sed 's/^/agy-saw-env-/' >> "$LAUNCHES" || true
# NAMES only, never values: the point of the assertion is that no App
# private key reached the child, and a stub that echoed one would put a
# PEM in a test log to prove a PEM should not be in a session.
env | sed -n 's/^\([A-Z_]*_APP_PRIVATE_KEY\)=.*/agy-saw-key-\1/p' >> "$LAUNCHES" || true
if [ "${LAUNCH_OK:-0}" != "1" ]; then
  echo "agy $*" >> "$WRITES"
  echo "stub agy: a session was launched by a test that forbids it" >&2
  exit 1
fi
[ -z "${AGY_JSON:-}" ] || cat "${AGY_JSON}"
exit "${AGY_RC:-0}"
STUB
chmod +x "$WORK/bin/gh" "$WORK/bin/claude" "$WORK/bin/agy"

# util-linux's `script` is the pty for run_tty below. Checked here so a
# machine without it fails with a sentence rather than at the first
# interactive scenario.
command -v script >/dev/null \
  || fail "util-linux's 'script' is required: the interactive-row scenarios need a pty"

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
# pr <n> <body> <head-ref> [<labels-csv>]
pr() {
  jq -n --argjson n "$1" --arg body "$2" --arg labels "${4:-}" \
    '{number: $n, state: "open", title: "a pull request", body: $body,
      labels: ($labels | if . == "" then [] else split(",") end | map({name: .})),
      pull_request: {url: "x"}}' \
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
# pad_thread <n> <count> — <count> ordinary comments inserted BEFORE the
# last comment of #<n>'s thread, which pushes that last comment past the
# API's 30-item first page. A dispatcher that reads only page one sees
# the claims before the padding and never the one after it (#51).
pad_thread() {
  local file="$FIXTURES/repos_test_repo_issues_$1_comments.json" padded
  padded="$(jq -c --argjson c "$2" \
    '.[0:-1]
       + [range(0; $c) | {user: {login: "drive-by-user"}, body: "just a comment"}]
       + .[-1:]' "$file")"
  printf '%s\n' "$padded" > "$file"
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
  OUT="$(DRY_RUN="${DRY:-1}" HEADLESS="${HL:-0}" WORK_COST_FILE="${WORK_COST_FILE:-}" \
    "${TREE:-$REPO}/scripts/ops/work.sh" "$@" 2>&1)"
  rc=$?
  set -e
  if [ "$rc" -ne "$want" ]; then
    printf '%s\n' "$OUT" >&2
    fail "$name (expected exit $want, got $rc)"
  fi
  pass "$name (exit $rc)"
}
# run_tty <expected-exit> <name> -- <args...>; the same as run(), through
# a pty. The interactive row REFUSES when stdin or stdout is not a
# terminal (#43 D16 as amended, clause (c); Acceptance 14), so every
# interactive scenario needs one. `script -qec` allocates the pty, runs
# the command, merges the child's stderr into the captured stream and
# returns the command's own exit status; the pty's \r is stripped so the
# assertions stay line-oriented. Variables the caller set as an
# assignment prefix on run_tty (LAUNCH_OK, CLAUDE_RC, CLAUDE_JSON …) are
# already in this process's environment and reach the child unaided.
run_tty() {
  local want="$1" name="$2" rc=0 cmd a
  shift 3  # drop want, name and the literal --
  cmd="DRY_RUN=${DRY:-1} HEADLESS=${HL:-0} $(printf '%q' "${TREE:-$REPO}/scripts/ops/work.sh")"
  for a in "$@"; do cmd="$cmd $(printf '%q' "$a")"; done
  set +e
  OUT="$(script -qec "$cmd" /dev/null 2>&1)"
  rc=$?
  set -e
  OUT="$(printf '%s' "$OUT" | tr -d '\r')"
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
has "command:  timeout --foreground 5460 claude --agent odyssey" \
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

banner "D5(a)/D9 hold on the PULL REQUEST refuses too (#50, Atlas AT-1)"
# Resolving a PR to its issue must not throw the PR's own labels away:
# the circuit breaker is placed where the operator is looking, and on a
# pull request that is the pull request. The refusals therefore read the
# UNION of both label sets, and the message names the side that carries
# the label so the operator knows which one to clear.
pr 127 "Closes #108" "odyssey/108-deterministic" "hold"
run 2 "D5(a): hold on the PR exits 2 even though #108 is clean" -- 127
has "carries hold" "D5(a): the refusal names hold"
has "#127" "D5(a): the refusal names the pull request that carries it"
pr 128 "Closes #108" "odyssey/108-deterministic" "blocked"
run 2 "D5(c): blocked on the PR exits 2" -- 128
has "carries blocked" "D5(c): the refusal names blocked"
pr 129 "Closes #101" "odyssey/101-held"
run 2 "D5(a): hold on the ISSUE still refuses through a clean PR" -- 129
has "#101 carries hold" "D5(a): the issue's own labels are still read"
pr 130 "Closes #108" "odyssey/108-deterministic"
run 0 "D9: a PR carrying no labels still dispatches its issue" -- 130
has "==> #108" "D9: the union adds nothing when the PR is unlabelled"

banner "D5(e) the mutex reads the WHOLE thread, not its first page (#51, Atlas AT-2)"
# THE FAIL-OPEN DIRECTION, which is why AT-2 is high: odyssey claimed
# this issue, handed it back in prose, and athena claimed it again 31
# comments later. The API answers 30 comments a page, so a mutex that
# reads one page sees odyssey's stale claim, calls it a resume of its
# own work, and launches a SECOND session onto an issue athena is
# holding. Reading the whole thread is what makes "the last comment
# opening with Claim" (docs/SPEC.md, `ops.dispatch`) true of a thread
# longer than thirty.
issue 131 open "in-progress,status:implementing" "Handed over late in a long thread"
claim 131 "evekhm-odyssey-app[bot]" "Claim: IMPLEMENT stage — odyssey." \
  "evekhm-athena-app[bot]" "Claim: DESIGN stage — athena."
pad_thread 131 30
run 2 "D5(e): a claim on comment 32 still holds the issue" -- 131
has "is held by athena" "D5(e): the holder is read past the API's first page"
hasnt "command:" "D5(e): nothing is dispatched over a claim on page two"

banner "D5(e)/D5(a) a unioned refusal names the side that carries it (PR #95 review)"
# R1-1: `in-progress` joined the union, but its four messages still
# asserted the label of the issue. An operator who set it on the pull
# request was sent to a clean number they could not clear it from. The
# thread read stays the issue's — that is where a claim is posted — so
# both numbers appear, each doing its own job.
pr 132 "Closes #108" "odyssey/108-deterministic" "in-progress"
run 2 "D5(e): in-progress on the PR exits 2 even though #108 is clean" -- 132
has "in-progress on #132 (the pull request)" \
  "D5(e): the refusal names the side that carries the label"
# R1-2: when BOTH sides carry it, naming only the issue makes the
# operator clear one number, re-run, and be refused by the other.
pr 133 "Closes #101" "odyssey/101-held" "hold"
run 2 "D5(a): hold on both sides exits 2" -- 133
has "#101 (and #133, the pull request) carries hold" \
  "D5(a): both sides are named in one refusal"

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

banner "#129 a number on no rung is a refusal, not an error"
# A defect-repair issue carries `bug` and no status:* (its fix PR is the
# final stage); on a pull_request event the reviewers used to die on it,
# one red check per reviewer on every fix PR. It is a stated refusal.
issue 140 open "bug" "unattended.yml: preflight cannot sign RS256"
run 2 "#129: a bug issue with no status:* exits 2" -- 140 --as argus
has "refused: cannot derive a stage for #140" "#129: it is a refusal with the condition named"
has "no status:* label and no intent:new" "#129: the sentence says which labels are missing"
[ ! -s "$WRITES" ] || { cat "$WRITES" >&2; fail "#129: something was launched or written"; }
pass "#129: no session was launched and no write was attempted"
pr 141 "Closes #140" "eva/140-unattended-cryptography"
run 2 "#129: the fix pull request resolves to the bug issue and exits 2" -- 141 --as atlas
has "refused: cannot derive a stage for #140" "#129: the refusal names the resolved issue, not the pull request"

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
# Read the expected model out of the sidecar itself: this assertion is
# about where work.sh gets the model, not about which model is pinned,
# and a literal here would fail every time config/model_tiers.yaml is
# re-pinned.
sidecar_model="$(sed -n 's/.*"model": "\([^"]*\)".*/\1/p' \
                 "$REPO/.agents/agents/daedalus/agent.json")"
[ -n "$sidecar_model" ] || fail "D9: no model in daedalus's compiled sidecar"
has " --model $sidecar_model " "D9: the model comes from the compiled sidecar"
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
has "command:  timeout --foreground 5460 claude --agent odyssey " "D5: the interactive form"
hasnt " -p " "D5: the interactive row does not use print mode"
HL=1 run 0 "D5: HEADLESS=1 resolves the print row" -- 130
has "command:  timeout 5460 claude -p " "D5: the headless form"
hasnt "timeout --foreground" \
  "R2-1: the headless row does NOT get --foreground — it touches no terminal"
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

banner "#43 N1 the WRAPPER binary is preflighted too, not just the harness"
# The other half of the loop above, and the branch the scenario above
# cannot reach: it narrows PATH to a directory plus /usr/bin:/bin, and
# /usr/bin supplies `timeout`, so ${LAUNCH[0]} is always present there
# and its failure arm never runs (PR #60, round-2 finding R2-3 — the
# round-2 ledger claimed this coverage and did not have it).
#
# $WORK/bin-notimeout is every /usr/bin and /bin entry symlinked, MINUS
# `timeout`, plus the gh and agy stubs — a whole-of-PATH mirror rather
# than a whitelist, so a run that fails here fails for the reason under
# test and not because some unrelated utility went missing. The named
# assertion below is what makes that non-vacuous.
mkdir -p "$WORK/bin-notimeout"
for _p in /usr/bin/* /bin/*; do
  ln -sf "$_p" "$WORK/bin-notimeout/" 2>/dev/null || true
done
# Anything work.sh needs that lives outside /usr/bin and /bin (a jq in
# /usr/local/bin is the common one) is pulled in by name.
for _b in bash env jq sed grep head tr cat mktemp ps stty python3; do
  _p="$(command -v "$_b" 2>/dev/null)" || continue
  [ -e "$WORK/bin-notimeout/$_b" ] || ln -sf "$_p" "$WORK/bin-notimeout/$_b"
done
# `rm -f` first: these three are symlinks into /usr/bin at this point,
# and `cp` would follow them and try to overwrite the REAL binaries.
rm -f "$WORK/bin-notimeout/timeout" "$WORK/bin-notimeout/gh" \
      "$WORK/bin-notimeout/agy" "$WORK/bin-notimeout/claude"
cp "$WORK/bin/gh" "$WORK/bin/agy" "$WORK/bin/claude" "$WORK/bin-notimeout/"
for _b in bash env jq gh agy; do
  [ -e "$WORK/bin-notimeout/$_b" ] \
    || fail "N1: the mirrored PATH is missing $_b — the fixture, not the code"
done
[ ! -e "$WORK/bin-notimeout/timeout" ] || fail "N1: the fixture still has a timeout on PATH"
: > "$WRITES"; : > "$LAUNCHES"; : > "$MINTS"
saved_path="$PATH"
PATH="$WORK/bin-notimeout"
TREE="$T" DRY=0 HL=1 LAUNCH_OK=1 \
  run 1 "N1: the timeout wrapper missing from PATH exits 1" -- 113
PATH="$saved_path"
has "timeout is not installed" "N1: the refusal names the wrapper, not the harness"
has "nothing was minted" "N1: it says no token was exchanged"
[ ! -s "$MINTS" ] || { cat "$MINTS" >&2; fail "N1: a token was minted with no wrapper to run the child under"; }
[ ! -s "$LAUNCHES" ] || { cat "$LAUNCHES" >&2; fail "N1: something was launched without its wrapper"; }
pass "N1: zero mints and zero launches behind a missing timeout"

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

banner "#150 Antigravity dispatch writes cost and model to WORK_COST_FILE"
: > "$LAUNCHES"; : > "$MINTS"
cost_file="$WORK/cost.txt"
# 100,000 input, 10,000 output, 5,000 thinking, 20,000 cache read
# on daedalus (pinned to antigravity, model: gemini-3.1-pro-high).
# Pro rates: input: 1.25, cache_read: 0.3125, output: 5.00
# cost = (100000 * 1.25 + 20000 * 0.3125 + (10000 + 5000) * 5.00) / 1000000
# cost = (125000 + 6250 + 75000) / 1000000 = 206250 / 1000000 = 0.206250
printf '%s\n' '{"status":"SUCCESS","response":"done\nWORK-RESULT: ok #113 plan committed","usage":{"input_tokens":100000,"output_tokens":10000,"thinking_tokens":5000,"cache_read_tokens":20000,"total_tokens":135000}}' \
  > "$WORK/agy_cost.json"
TREE="$T" DRY=0 HL=1 LAUNCH_OK=1 AGY_JSON="$WORK/agy_cost.json" \
  WORK_COST_FILE="$cost_file" \
  run 0 "#150: Antigravity dispatch writes cost and model to WORK_COST_FILE" -- 113
cost_line1="$(sed -n '1p' "$cost_file")"
cost_line2="$(sed -n '2p' "$cost_file")"
[ "$cost_line1" = "0.206250" ] || fail "#150: expected cost 0.206250, got '$cost_line1'"
pass "#150: Antigravity dispatch calculates list-rate cost from .usage"
[ "$cost_line2" = "gemini-3.1-pro-high" ] || fail "#150: expected model gemini-3.1-pro-high, got '$cost_line2'"
pass "#150: Antigravity dispatch writes resolved model to line 2"

# Missing usage truncates WORK_COST_FILE
unpriced_cost_file="$WORK/unpriced_cost.txt"
echo "stale" > "$unpriced_cost_file"
printf '%s\n' '{"status":"SUCCESS","response":"done\nWORK-RESULT: ok #113 plan committed"}' \
  > "$WORK/agy_no_usage.json"
TREE="$T" DRY=0 HL=1 LAUNCH_OK=1 AGY_JSON="$WORK/agy_no_usage.json" \
  WORK_COST_FILE="$unpriced_cost_file" \
  run 0 "#150: Missing usage truncates WORK_COST_FILE" -- 113
[ ! -s "$unpriced_cost_file" ] || fail "#150: WORK_COST_FILE should be empty when usage missing"
pass "#150: Missing usage truncates WORK_COST_FILE"

banner "#43 D16(c)/Acceptance 14 the interactive row refuses when there is no terminal"
# run() captures stdout through a command substitution, so it is exactly
# the non-TTY caller this guard is about — the /work door, cron, a CI
# step, a subagent's bash. The refusal is BEFORE the mint: a session that
# cannot start must not leave a live one-hour credential behind (D11).
: > "$WRITES"; : > "$LAUNCHES"; : > "$MINTS"
TREE="$T" DRY=0 LAUNCH_OK=1 \
  run 1 "D16(c): the interactive row with no tty exits 1" -- 130
has "HEADLESS=1" "D16(c): the refusal names the mode that would work"
has "no terminal" "D16(c): it says what is missing"
[ ! -s "$MINTS" ] || { cat "$MINTS" >&2; fail "D16(c): a token was minted for a row that cannot start"; }
[ ! -s "$LAUNCHES" ] || { cat "$LAUNCHES" >&2; fail "D16(c): a session was launched with no terminal"; }
pass "D16(c): zero mints and zero launches behind the no-tty refusal"
# Exit 1, not 2: this is an environment that cannot start the row, not a
# decision about the number, so 2 keeps meaning "not worked, by design".
printf '%s\n' '{"type":"result","subtype":"success","is_error":false,"result":"WORK-RESULT: ok #130 implemented"}' \
  > "$WORK/cc_ok.json"
TREE="$T" DRY=0 HL=1 LAUNCH_OK=1 CLAUDE_JSON="$WORK/cc_ok.json" \
  run 0 "D16(c): the same stage under HEADLESS=1 launches" -- 130

banner "#43 D15/D23 amended: the interactive row is not exec'd, and it MAPS"
# Four scenarios through a pty. The mapping is the proof that `exec` is
# gone: an exec'd child's status would arrive unmapped, so a stub exiting
# 3 could not come back as 1.
: > "$LAUNCHES"
TREE="$T" DRY=0 LAUNCH_OK=1 CLAUDE_RC=0 \
  run_tty 0 "D15: an interactive child that exits 0 maps to 0" -- 130
grep -qF "claude --agent odyssey" "$LAUNCHES" \
  || { cat "$LAUNCHES" >&2; fail "D15: the interactive form was not the one launched"; }
pass "D15: the interactive row ran (no -p, no --output-format)"
# D15's "inherits stdin, stdout, stderr and the terminal", asserted
# rather than assumed (PR #60, round-2 finding R2-1). The scenario above
# already proves the exit maps; these three lines prove the child could
# have USED the terminal it inherited. Without `timeout --foreground`
# the harness runs in a process group that is not the terminal's
# foreground group, so its first `tcsetattr` — raw mode, which every
# interactive TUI sets at startup — raises SIGTTOU and stops it with a
# live token already minted. Remove `--foreground` from work.sh's
# LAUNCH_ARGV and both assertions below go red.
cpgid="$(sed -n 's/^claude-saw-pgid=//p' "$LAUNCHES" | tail -1)"
ctpgid="$(sed -n 's/^claude-saw-tpgid=//p' "$LAUNCHES" | tail -1)"
[ -n "$cpgid" ] && [ -n "$ctpgid" ] \
  || { cat "$LAUNCHES" >&2; fail "R2-1: the child recorded no process group — it saw no tty"; }
[ "$cpgid" = "$ctpgid" ] \
  || { cat "$LAUNCHES" >&2
       fail "R2-1: the child ran in a background process group (pgid $cpgid, terminal's foreground pgid $ctpgid)"; }
pass "R2-1: the interactive child IS the terminal's foreground process group (pgid $cpgid)"
grep -qx "claude-saw-stty=ok" "$LAUNCHES" \
  || { cat "$LAUNCHES" >&2; fail "R2-1: the child could not put the terminal in raw mode"; }
pass "R2-1: the interactive child can reconfigure the terminal it inherited"
TREE="$T" DRY=0 LAUNCH_OK=1 CLAUDE_RC=3 \
  run_tty 1 "D15: an interactive child that exits 3 maps to 1" -- 130
has "exit 3" "D15: the raw status is named"
has "did not complete" "D15: it says the session did not finish"
# The row that #36 D8 and D23 could not both survive: a harness exiting 2
# for a reason of its own must NOT be read as a designed refusal.
TREE="$T" DRY=0 LAUNCH_OK=1 CLAUDE_RC=2 \
  run_tty 1 "D23: an interactive child that exits 2 maps to 1, not 2" -- 130
has "exit 2" "D23: the raw status is named rather than forwarded"
# 124 is what `timeout` returns when the cap fires. The stub returns it
# directly: a child that genuinely outlived the wrapper would take
# odyssey's 90 minutes plus a minute, and the code path under test is the
# mapping of the status, not coreutils' clock.
TREE="$T" DRY=0 LAUNCH_OK=1 CLAUDE_RC=124 \
  run_tty 1 "D15: a fired cap (124) maps to 1" -- 130
has "exit 124" "D15: the raw status is named"
has "90-minute cap" "D15: 124 also names the cap"
# Every exit of this script is now 0, 1 or 2 — nothing above returned 3,
# 124 or any other harness code.
pass "D15: the interactive row's whole vocabulary is 0 and 1"

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

banner "#43 D11 amended / Acceptance 16 the minted token never reaches bash -x"
# D11's third clause used to be a claim about the code that nothing ran,
# and it was false: bash's xtrace expands both `tok="$(mint …)"` and every
# `GH_TOKEN="$tok"` assignment, so a debugging `bash -x scripts/ops/work.sh
# <n>` wrote the live installation token to stderr — and a Claude Code
# session captures tool stderr verbatim into an on-disk transcript, a file
# and a log, the two places D11 says the token never reaches. Both rows are
# covered: the interactive one now returns rather than being exec'd away,
# so it needs the guard too.
: > "$LAUNCHES"; : > "$MINTS"
set +e
xt_out="$(DRY_RUN=0 HEADLESS=1 LAUNCH_OK=1 AGY_JSON="$WORK/agy_ok.json" \
  bash -x "$T/scripts/ops/work.sh" 113 2>&1)"
xt_rc=$?
set -e
[ "$xt_rc" -eq 0 ] \
  || { printf '%s\n' "$xt_out" >&2; fail "D11: the traced headless launch did not exit 0"; }
printf '%s\n' "$xt_out" | grep -q '^+' \
  || { printf '%s\n' "$xt_out" >&2; fail "D11: nothing was traced, so the assertion below is vacuous"; }
pass "D11: the headless launch really ran under xtrace"
if printf '%s\n' "$xt_out" | grep -qF 'stub-token-for-'; then
  fail "D11: the minted token appears in the headless row's bash -x output"
fi
pass "D11: the headless row's stdout+stderr under bash -x carries no token"
grep -qF "agy-saw-GH_TOKEN=stub-token-for-daedalus" "$LAUNCHES" \
  || { cat "$LAUNCHES" >&2; fail "D11: the child never got the token, so nothing was proved"; }
pass "D11: the token was suppressed in the trace, not withheld from the child"
# A window, not a switch: `set -x` is back in force the moment the child
# returns, so everything after the launch is traced as the caller asked.
printf '%s\n' "$xt_out" | grep -qE '^\+.*reported' \
  || { printf '%s\n' "$xt_out" >&2; fail "D11: xtrace was not restored after the launch"; }
pass "D11: xtrace is restored once the child returns"
# The interactive row, through the same pty run_tty uses.
: > "$LAUNCHES"; : > "$MINTS"
xt_cmd="DRY_RUN=0 HEADLESS=0 bash -x $(printf '%q' "$T/scripts/ops/work.sh") 130"
set +e
xt_out="$(LAUNCH_OK=1 CLAUDE_RC=0 script -qec "$xt_cmd" /dev/null 2>&1)"
xt_rc=$?
set -e
xt_out="$(printf '%s' "$xt_out" | tr -d '\r')"
[ "$xt_rc" -eq 0 ] \
  || { printf '%s\n' "$xt_out" >&2; fail "D11: the traced interactive launch did not exit 0"; }
printf '%s\n' "$xt_out" | grep -q '^+' \
  || { printf '%s\n' "$xt_out" >&2; fail "D11: nothing was traced on the interactive row"; }
pass "D11: the interactive launch really ran under xtrace"
if printf '%s\n' "$xt_out" | grep -qF 'stub-token-for-'; then
  fail "D11: the minted token appears in the interactive row's bash -x output"
fi
pass "D11: the interactive row's stdout+stderr under bash -x carries no token"
grep -qF "claude-saw-GH_TOKEN=stub-token-for-odyssey" "$LAUNCHES" \
  || { cat "$LAUNCHES" >&2; fail "D11: the interactive child never got the token"; }
pass "D11: the interactive child got the token too, and the trace did not"

banner "#43 AT-7 an inherited GIT_CONFIG_* set is extended, not overwritten"
# A caller that already installs `http.proxy` or `safe.directory` through
# GIT_CONFIG_* had its entries silently replaced by a fixed COUNT=4, and
# the symptom was a push failing for an unrelated reason.
: > "$LAUNCHES"; : > "$MINTS"
TREE="$T" DRY=0 HL=1 LAUNCH_OK=1 AGY_JSON="$WORK/agy_ok.json" \
  GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="http.proxy" \
  GIT_CONFIG_VALUE_0="http://proxy.invalid" \
  run 0 "AT-7: a launch under an inherited GIT_CONFIG set exits 0" -- 113
grep -qxF "agy-saw-env-GIT_CONFIG_KEY_0=http.proxy" "$LAUNCHES" \
  || { cat "$LAUNCHES" >&2; fail "AT-7: the caller's own entry was overwritten"; }
pass "AT-7: the caller's entry survives at its own index"
grep -qxF "agy-saw-env-GIT_CONFIG_COUNT=5" "$LAUNCHES" \
  || { cat "$LAUNCHES" >&2; fail "AT-7: the count was replaced rather than extended"; }
pass "AT-7: the count is the caller's plus this launcher's four"
grep -qxF "agy-saw-env-GIT_CONFIG_VALUE_3=$T/scripts/auth/git-credential-persona daedalus" "$LAUNCHES" \
  || { cat "$LAUNCHES" >&2; fail "AT-7: the helper was not installed at the caller's offset"; }
pass "AT-7: the re-minting helper lands at the caller's offset and still wins"
[ -z "${GIT_CONFIG_COUNT:-}" ] \
  || fail "AT-7: GIT_CONFIG_COUNT leaked out of the scenario"
pass "AT-7: nothing leaked back into the parent"

banner "#164 R1-1 the App private key does not reach the launched session"
# Argus found itself holding a live 1678-character RSA key in its own
# environment on a runner, where the harness permission gate is bypassed
# (#163) and an unrestricted shell can therefore read it. The mint has
# already happened by launch time, so the key has no remaining use in
# the child: it inherits the one-hour repository-scoped token instead of
# an App whose rotation is a human clicking in the GitHub UI.
: > "$LAUNCHES"; : > "$MINTS"
# Exported rather than passed as a prefix to `run`: bash restores a
# prefix assignment when the function returns, which would make the
# "the parent still has its key" assertion below pass for the wrong
# reason.
export DAEDALUS_APP_PRIVATE_KEY="stub-pem-value-that-must-not-travel"
TREE="$T" DRY=0 HL=1 LAUNCH_OK=1 AGY_JSON="$WORK/agy_ok.json" \
  run 0 "R1-1: a launch with the App key in the environment exits 0" -- 113
grep -qF "agy-saw-GH_TOKEN=stub-token-for-daedalus" "$LAUNCHES" \
  || { cat "$LAUNCHES" >&2; fail "R1-1: the child got no token, so nothing was proved"; }
pass "R1-1: the child still receives the minted installation token"
grep -q '^agy-saw-key-' "$LAUNCHES" \
  && { grep '^agy-saw-key-' "$LAUNCHES" >&2
       fail "R1-1: an App private key reached the launched session"; }
pass "R1-1: no App private key reached the launched session"
[ -n "${DAEDALUS_APP_PRIVATE_KEY:-}" ] \
  || fail "R1-1: the unset escaped the child and cleared the parent's key"
pass "R1-1: the parent's own environment is untouched"
unset DAEDALUS_APP_PRIVATE_KEY

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
