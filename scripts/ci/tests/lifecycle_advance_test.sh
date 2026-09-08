#!/usr/bin/env bash
# Tests for scripts/ci/lifecycle_advance.sh (#36, intent/36-dispatch/plan.md T9).
#
#   bash scripts/ci/tests/lifecycle_advance_test.sh
#
# Hermetic: a synthetic range in a throwaway git repository, a stub `gh`
# first on PATH that answers an issue view from a fixture when one names
# the issue and otherwise with an OPEN, unlabelled issue carrying no
# comments (D13(c) — the default the advancer itself no longer
# fabricates, per D21), records any write it is asked to make, and
# DRY_RUN=1 throughout. A `git` stub sits beside it, a pass-through to
# the real `git` except for one fault a scenario can arm by environment
# variable (D13(d)). No network, no token, no issue is touched.
#
# What these pin is the #36 change and nothing else: the label a merged
# artifact advances to, and the line posted when it does, are READ from
# personas/lifecycle.json rather than written in the script. So the
# expected strings below are not literals — they are pulled out of the
# JSON with jq at run time, and the last scenario edits the JSON and
# asserts the output follows it. A copy of the ladder hidden in the
# script would fail that one.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
ADVANCER="$REPO/scripts/ci/lifecycle_advance.sh"
LADDER="$REPO/personas/lifecycle.json"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

WRITES="$WORK/writes.log"
: > "$WRITES"
# The INVOCATION log is separate from the write log and records every
# `gh` call, reads included (D13 as amended). It is what lets an item
# assert that a read did NOT happen (item 26) and that a read carried
# `--paginate` (item 20); the write log keeps its own meaning, so
# "anything else reaching gh is an attempted write" is untouched.
INVOKES="$WORK/invocations.log"
: > "$INVOKES"
mkdir -p "$WORK/bin" "$WORK/fixtures"
FIXTURES="$WORK/fixtures"
TESTREPO="evekhm/agentic-sdlc"
export WRITES INVOKES FIXTURES
export GITHUB_REPO="$TESTREPO"
# Captured before $WORK/bin goes on PATH below, so this resolves the
# real binary structurally — not merely because the stub file does not
# exist yet on the next line (#73 Argus R1-6).
REAL_GIT="$(command -v git)"
export PATH="$WORK/bin:$PATH"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }
banner() { printf '\n--- %s\n' "$*"; }

cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
# The stub answers exactly the READS the advancer makes, and only from
# files in $FIXTURES — no network, no token. Anything else reaching gh
# in a dry run is a write that should never have been attempted, and is
# recorded as one.
#
# Every invocation — reads included — is appended to $INVOKES first
# (D13 as amended). $WRITES keeps its own, narrower meaning.
printf '%s\n' "gh $*" >> "$INVOKES"
if [ "${1:-}" = "issue" ] && [ "${2:-}" = "view" ]; then
  n="${3:-}"
  # An armed unreadable-issue fault (D13(c), D21(a)/AT-2) — the stub
  # answers non-zero for this one number regardless of any fixture.
  if [ -f "$FIXTURES/issue-$n.unreadable" ]; then
    exit 1
  fi
  if [ -f "$FIXTURES/issue-$n.json" ]; then
    cat "$FIXTURES/issue-$n.json"
    exit 0
  fi
  # D13(c): the default answer for an issue no fixture names is an
  # OPEN, unlabelled issue with no comments — the substitution D21
  # deletes from the advancer itself moves here, so every scenario
  # written before this repair still runs unchanged.
  jq -nc --argjson n "$n" '{number: $n, state: "OPEN", labels: [], comments: []}'
  exit 0
fi
if [ "${1:-}" = "api" ]; then
  # `gh api --paginate <path>` puts the flag first, so scan the argv for
  # the path rather than assuming $2.
  path=""
  for a in "$@"; do
    case "$a" in
      api|--paginate) ;;
      -*) ;;
      *) [ -n "$path" ] || path="$a";;
    esac
  done
  case "$path" in
    */commits/*/pulls)
      sha="${path#*/commits/}"
      sha="${sha%/pulls}"
      if [ -f "$FIXTURES/pulls-$sha.json" ]; then
        cat "$FIXTURES/pulls-$sha.json"
      else
        # A commit belonging to no pull request: an empty list, not an
        # error.
        echo '[]'
      fi
      exit 0;;
    */pulls/*/files)
      # D15 conjunct (2): the pull request's OWN file list. A fixture
      # is required — a pull request nobody described has no file list
      # to judge, and answering [] silently would hide the omission.
      n="${path#*/pulls/}"
      n="${n%/files}"
      if [ -f "$FIXTURES/files-$n.json" ]; then
        cat "$FIXTURES/files-$n.json"
        exit 0
      fi
      echo "no files fixture for pull request $n" >&2
      exit 1;;
    repos/*)
      echo '{"default_branch":"main"}'
      exit 0;;
  esac
fi
printf '%s\n' "gh $*" >> "$WRITES"
exit 1
STUB
chmod +x "$WORK/bin/gh"

# D13(d): a `git` stub, first on PATH beside the `gh` one, is a
# pass-through to the real `git` except for one fault a scenario arms by
# environment variable: `rev-list` exits non-zero. It is the only way
# D21(b)'s range-walk failure is reachable hermetically — the
# advancer's own `git cat-file -e` preflight rejects every bad sha a
# fixture could supply, so the walk cannot be made to fail through its
# inputs. $REAL_GIT is resolved above, before $WORK/bin joined PATH.
cat > "$WORK/bin/git" <<GITSTUB
#!/usr/bin/env bash
if [ "\${1:-}" = "rev-list" ] && [ "\${LIFECYCLE_TEST_GIT_REV_LIST_FAIL:-0}" = "1" ]; then
  echo "simulated rev-list failure (LIFECYCLE_TEST_GIT_REV_LIST_FAIL=1)" >&2
  exit 1
fi
exec "$REAL_GIT" "\$@"
GITSTUB
chmod +x "$WORK/bin/git"

# --- the synthetic range (the #4 fixture) --------------------------------------
SANDBOX="$WORK/repo"
mkdir -p "$SANDBOX/personas" "$SANDBOX/intent/999-test" "$SANDBOX/intent/998-draft"
cp "$LADDER" "$SANDBOX/personas/lifecycle.json"
cd "$SANDBOX"
git init -q .
git config user.email test@example.com
git config user.name test

echo seed > seed.txt
git add -A
git commit -qm seed
C0="$(git rev-parse HEAD)"
MAIN="$(git rev-parse --abbrev-ref HEAD)"

printf '# Intent\n' > intent/999-test/intent.md
git add -A
git commit -qm intent
C1="$(git rev-parse HEAD)"

printf '# Spec\n\n**Issue:** #999 · **Status:** Approved (approval = merge of this PR)\n' \
  > intent/999-test/spec.md
git add -A
git commit -qm spec
C2="$(git rev-parse HEAD)"

printf '# Spec\n\n**Status:** Draft\n' > intent/998-draft/spec.md
printf '# Plan\n' > intent/999-test/plan.md
git add -A
git commit -qm 'draft spec and plan'
C3="$(git rev-parse HEAD)"

# The merge-rung fixtures (#57). C4 is a plain commit on the trunk — the
# squash shape, one commit and no merge commit — and CM is a real merge
# commit. Both are "the pushed range" for the scenarios below; which
# pull request each belongs to is a fixture file, not the git history,
# because the advancer learns that from the API and never from the
# commit message.
echo note > note.txt
git add -A
git commit -qm 'a commit with no artifact'
C4="$(git rev-parse HEAD)"

git checkout -q -b side
echo side > side.txt
git add -A
git commit -qm 'side work'
git checkout -q -
git merge -q --no-ff -m 'Merge pull request #4242' side
CM="$(git rev-parse HEAD)"

# C5 adds an artifact AND is a merge-rung candidate: the two discovery
# steps contesting one issue.
mkdir -p intent/997-both
printf '# Plan\n' > intent/997-both/plan.md
git add -A
git commit -qm 'plan for 997'
C5="$(git rev-parse HEAD)"

# --- #72's fixtures -----------------------------------------------------------
# The landing-branch shape (D1 as amended, Argus F2). #42 — #35's own
# implementing pull request in this repository — reached main exactly
# like MF does: merged into a branch that later landed, so it is on a
# merge's SECOND parent and a --first-parent walk never sees it.
#
#   main   C5 ─────────────── ML
#            \               /
#   land      L0 ───── MF ──/
#                    /
#   landfeat        LF
git checkout -q -b land "$C5"
echo land > land.txt
git add -A
git commit -qm 'landing branch base'
L0="$(git rev-parse HEAD)"
git checkout -q -b landfeat "$L0"
echo implementation > implementation.txt
git add -A
git commit -qm 'the implementation'
git checkout -q land
git merge -q --no-ff -m 'Merge pull request #4260' landfeat
MF="$(git rev-parse HEAD)"
git checkout -q "$MAIN"
git merge -q --no-ff -m 'Merge the landing branch' land
ML="$(git rev-parse HEAD)"

# The REBASE shape (D15 conjunct (2) as amended, Argus R2-1). R2 is the
# pull request's own last commit and its parent R1 is the same pull
# request's second-to-last, so `git diff R2^ R2` is one plan-sync file
# under intent/ while the pull request itself changed seven paths
# outside it. Only the API file list can tell those apart.
echo rebased > rebase-code.txt
git add -A
git commit -qm 'rebased commit 1: the code'
R1="$(git rev-parse HEAD)"
printf '# Plan\n\nplan sync\n' > intent/999-test/plan.md
git add -A
git commit -qm 'rebased commit 2: the plan sync'
R2="$(git rev-parse HEAD)"

# No intent/ directory at all in the AFTER tree (D15 conjunct (3), item
# 23). Built off C0 and left unchecked-out, so the working checkout
# still holds intent/999-test/ while the tree being read does not.
git checkout -q -b nofolder "$C0"
echo none > nofolder.txt
git add -A
git commit -qm 'a tree with no intent folders'
NF="$(git rev-parse HEAD)"
git checkout -q "$MAIN"

# TWO intent/999-*/ directories: corrupted state, not a slug mismatch.
# notes.md is deliberately not one of the ladder's artifacts, so this
# adds a folder without adding an artifact candidate.
git checkout -q -b twofolders "$R2"
mkdir -p intent/999-dup
printf 'notes\n' > intent/999-dup/notes.md
git add -A
git commit -qm 'a second 999 folder'
TF="$(git rev-parse HEAD)"
git checkout -q "$MAIN"

# Two accepted pull requests for one issue in one range (D15's
# second-candidate rule, item 24). MB is topologically LATER than MA and
# its commits are the OLDER ones by date — the re-created dispatch
# branch cut from an older base that D15's rationale names.
#
#   main   R2 ── MA ─────────── ML2
#           \   /              /
#   pr-a     A1           land2
#             \            /
#   pr-b       (from MA) B1 ── MB
git checkout -q -b pr-a "$R2"
echo a > a.txt
git add -A
GIT_AUTHOR_DATE='2030-01-01T00:00:00Z' GIT_COMMITTER_DATE='2030-01-01T00:00:00Z' \
  git commit -qm 'pull request A: the code'
git checkout -q "$MAIN"
GIT_AUTHOR_DATE='2030-01-02T00:00:00Z' GIT_COMMITTER_DATE='2030-01-02T00:00:00Z' \
  git merge -q --no-ff -m 'Merge pull request #4290' pr-a
MA="$(git rev-parse HEAD)"
git checkout -q -b land2 "$MA"
git checkout -q -b pr-b "$MA"
echo b > b.txt
git add -A
GIT_AUTHOR_DATE='2020-01-01T00:00:00Z' GIT_COMMITTER_DATE='2020-01-01T00:00:00Z' \
  git commit -qm 'pull request B: the code'
git checkout -q land2
GIT_AUTHOR_DATE='2020-01-02T00:00:00Z' GIT_COMMITTER_DATE='2020-01-02T00:00:00Z' \
  git merge -q --no-ff -m 'Merge pull request #4291' pr-b
MB="$(git rev-parse HEAD)"
git checkout -q "$MAIN"
GIT_AUTHOR_DATE='2031-01-01T00:00:00Z' GIT_COMMITTER_DATE='2031-01-01T00:00:00Z' \
  git merge -q --no-ff -m 'Merge the second landing branch' land2
ML2="$(git rev-parse HEAD)"

OUT=""
run() { # <before> <after> <name>
  local rc=0
  set +e
  OUT="$(DRY_RUN=1 bash "$ADVANCER" "$1" "$2" 2>&1)"
  rc=$?
  set -e
  [ "$rc" -eq 0 ] || { printf '%s\n' "$OUT" >&2; fail "$3 (exit $rc)"; }
  pass "$3 (exit 0)"
}
has() { # <literal> <name>
  if printf '%s\n' "$OUT" | grep -qF -- "$1"; then pass "$2"
  else printf '%s\n' "$OUT" >&2; fail "$2 (expected to find: $1)"; fi
}
hasnt() { # <literal> <name>
  if printf '%s\n' "$OUT" | grep -qF -- "$1"; then
    printf '%s\n' "$OUT" >&2; fail "$2 (did not expect: $1)"
  else pass "$2"; fi
}
run_fail() { # <before> <after> <name> — the run MUST end red
  local rc=0
  set +e
  OUT="$(DRY_RUN=1 bash "$ADVANCER" "$1" "$2" 2>&1)"
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || { printf '%s\n' "$OUT" >&2; fail "$3 (expected a non-zero exit)"; }
  pass "$3 (exit $rc)"
}
# row <artifact> <key> -> the value the script must be reading
row() { jq -r --arg a "$1" ".stages[] | select(.artifact == \$a) | .$2" \
          "$SANDBOX/personas/lifecycle.json"; }
# lrow <label> <key> -> the value the script must read for a merge rung
lrow() { jq -r --arg l "$1" ".stages[] | select(.label == \$l) | .$2" \
           "$SANDBOX/personas/lifecycle.json"; }

reset_fixtures() { rm -f "$FIXTURES"/*.json "$FIXTURES"/*.unreadable; : > "$INVOKES"; }
issue_fixture() { # <number> <state> [label ...]
  local n="$1" state="$2" labels='[]'
  shift 2
  [ "$#" -eq 0 ] || labels="$(printf '%s\n' "$@" | jq -Rc '{name: .}' | jq -sc '.')"
  jq -nc --argjson n "$n" --arg s "$state" --argjson l "$labels" \
    '{number: $n, state: $s, labels: $l, comments: []}' > "$FIXTURES/issue-$n.json"
}
# issue_fixture_comment <number> <state> <comment-body> [label ...] —
# same as issue_fixture but with one comment in the thread, for AT-10's
# reconstructed partial-write residue (item 30).
issue_fixture_comment() {
  local n="$1" state="$2" comment="$3" labels='[]'
  shift 3
  [ "$#" -eq 0 ] || labels="$(printf '%s\n' "$@" | jq -Rc '{name: .}' | jq -sc '.')"
  jq -nc --argjson n "$n" --arg s "$state" --argjson l "$labels" --arg c "$comment" \
    '{number: $n, state: $s, labels: $l, comments: [{body: $c}]}' > "$FIXTURES/issue-$n.json"
}
# issue_unreadable <number> — arms the gh stub to exit non-zero for
# `issue view <number>` regardless of any fixture (D13(c), item 32).
issue_unreadable() { : > "$FIXTURES/issue-$1.unreadable"; }
# <sha> <pr-number> <head-ref> <body> [merge-commit-sha] [head-repo|null] [base-ref]
#
# merge_commit_sha defaults to the commit the pull request is reported
# on, which is the merge-commit and the squash shape both; head.repo
# defaults to this repository, and `null` writes a JSON null for the
# deleted-fork case (D16). base.ref is settable so a scenario can prove
# it is NOT filtered on any more (D1 as amended).
#
# A default file list is written alongside — one path outside `intent/`,
# so a pull request the scenario does not describe passes D15 conjunct
# (2) the way an ordinary implementing pull request does. files_fixture
# overrides it.
pulls_fixture() {
  local repo_json
  case "${6:-$TESTREPO}" in
    null) repo_json='null';;
    *) repo_json="$(jq -nc --arg r "${6:-$TESTREPO}" '{full_name: $r}')";;
  esac
  jq -nc --argjson n "$2" --arg h "$3" --arg b "$4" --arg base "${7:-main}" \
    --arg m "${5:-$1}" --argjson repo "$repo_json" \
    '[{number: $n, merged_at: "2026-01-01T00:00:00Z", state: "closed",
       merge_commit_sha: $m, base: {ref: $base},
       head: {ref: $h, repo: $repo}, body: $b}]' > "$FIXTURES/pulls-$1.json"
  [ -f "$FIXTURES/files-$2.json" ] || files_fixture "$2" scripts/ci/lifecycle_advance.sh
}
files_fixture() { # <pr-number> <path>...
  local n="$1"
  shift
  printf '%s\n' "$@" | jq -Rc '{filename: .}' | jq -sc '.' > "$FIXTURES/files-$n.json"
}
# files_fixture_raw <pr-number> <raw-body> — writes the file-list
# response verbatim, for the three-way separation D15 conjunct (2) now
# makes (item 31): an empty body, a body that is not JSON, and a body
# that parses as something other than a JSON array (`{}`).
files_fixture_raw() { printf '%s' "$2" > "$FIXTURES/files-$1.json"; }
invoked() { # <extended-regex> <name>
  if grep -Eq -- "$1" "$INVOKES"; then pass "$2"
  else cat "$INVOKES" >&2; fail "$2 (no gh invocation matching: $1)"; fi
}
not_invoked() { # <extended-regex> <name>
  if grep -Eq -- "$1" "$INVOKES"; then
    cat "$INVOKES" >&2; fail "$2 (unexpected gh invocation matching: $1)"
  else pass "$2"; fi
}

# ---------------------------------------------------------------------------
banner "D1 the ladder file itself: five rungs, real labels, declarable stages"
jq -e '.stages | length == 5' "$LADDER" >/dev/null \
  || fail "D1: personas/lifecycle.json does not carry exactly five rungs"
pass "D1: the ladder carries exactly five rungs"
while read -r lifecycle_label; do
  grep -Fq "ensure_label \"$lifecycle_label\"" "$REPO/scripts/setup/bootstrap_tracker.sh" \
    || fail "D1: '$lifecycle_label' is not a label scripts/setup/bootstrap_tracker.sh creates"
done < <(jq -r '.stages[].label' "$LADDER")
pass "D1: every label on the ladder is one the tracker provisioner creates"
while read -r lifecycle_stage; do
  jq -e --arg s "$lifecycle_stage" \
    '[.properties.stage.items.enum[]] | index($s) != null' \
    "$REPO/personas/schema.json" >/dev/null \
    || fail "D1: '$lifecycle_stage' is not a stage personas/schema.json lets a source declare"
done < <(jq -r '.stages[].stage' "$LADDER")
pass "D1: every rung is a stage a persona source is allowed to declare"

banner "D2 a merged intent.md advances by the row the ladder file carries"
run "$C0" "$C1" "D2: the intent.md range exits 0"
has "$(row intent.md advance_message)" \
  "D2: the posted body is the advance_message jq reads from personas/lifecycle.json"
has "--add-label $(row intent.md advances_to)" \
  "D2: the label written is the row's advances_to"
has "<!-- lifecycle:$(row intent.md advances_to | sed 's/^status://'):$C1 -->" \
  "D2: the idempotency marker is derived from the same row"

banner "D2 a merged spec.md marked Approved advances by its own row"
run "$C1" "$C2" "D2: the spec.md range exits 0"
has "$(row spec.md advance_message)" "D2: the design row's message is posted"
has "--add-label $(row spec.md advances_to)" "D2: the design row's label is written"

banner "D2 a merged plan.md advances to the implement rung"
run "$C2" "$C3" "D2: the plan.md range exits 0"
has "$(row plan.md advance_message)" "D2: the build row's message is posted"
has "--add-label $(row plan.md advances_to)" "D2: the build row's label is written"

banner "the Draft override is a condition this script owns, not a rung"
has "Warning: a spec.md merged without" "Draft: the warning is posted for #998"
has "intent/998-draft/spec.md" "Draft: the warning names the file that landed"
has "Draft spec does not advance" "Draft: the stage is left where it was"
hasnt "gh issue edit 998" "Draft: no label write is even printed for the draft"

banner "bootstrap compression applies the furthest transition only, once"
run "$C0" "$C3" "compression: the whole range exits 0"
has "added: intent.md plan.md spec.md · furthest: plan.md" \
  "compression: all three artifacts are seen, the furthest one wins"
has "Bootstrap compression: this push added" "compression: the note is posted"
has "--add-label $(row plan.md advances_to)" "compression: only the furthest label is written"
hasnt "--add-label $(row intent.md advances_to)" \
  "compression: the earlier gates are not re-announced"

banner "the ladder file is the source: edit it and the output follows"
jq '(.stages[] | select(.artifact == "plan.md") | .advances_to) = "status:elsewhere"' \
  "$SANDBOX/personas/lifecycle.json" > "$WORK/patched.json"
cp "$WORK/patched.json" "$SANDBOX/personas/lifecycle.json"
run "$C2" "$C3" "D2: the patched range exits 0"
has "--add-label status:elsewhere" \
  "D2: the advancer writes whatever the file says — no second copy of the ladder"
cp "$LADDER" "$SANDBOX/personas/lifecycle.json"

banner "no status -> stage table survives in the script itself"
if grep -q 'status:spec' "$ADVANCER"; then
  grep -n 'status:spec' "$ADVANCER" >&2
  fail "D2: the advancer still names a status label the ladder file owns"
fi
pass "D2: the advancer carries no status:spec literal"
if ! grep -q 'personas/lifecycle.json' "$ADVANCER"; then
  fail "D2: the advancer does not read personas/lifecycle.json"
fi
pass "D2: the advancer reads personas/lifecycle.json"

# ---------------------------------------------------------------------------
# #57 — the merge rung. Everything below is still hermetic: the stub
# answers `commits/<sha>/pulls` and `issue view` from files under
# $FIXTURES and nothing else, and every expected label and message is
# read out of the fixture ladder with `lrow`, never written as a literal.
# ---------------------------------------------------------------------------

count() { printf '%s\n' "$OUT" | grep -cF -- "$1" || true; }
exactly() { # <literal> <n> <name>
  local got; got="$(count "$1")"
  if [ "$got" -eq "$2" ]; then pass "$3"
  else printf '%s\n' "$OUT" >&2; fail "$3 (expected $2 × '$1', got $got)"; fi
}

banner "S1 · D1 D4 D6 D11 · a merged pull request advances the implement rung by branch name"
reset_fixtures
pulls_fixture "$CM" 4242 odyssey/999-test "Implements the plan. See #999."
issue_fixture 999 OPEN status:implementing
run "$C4" "$CM" "S1: the merge range exits 0"
has "--> #999 · merged pull request #4242" "S1: the candidate is announced as a merged pull request"
has "--add-label $(lrow status:implementing advances_to)" \
  "S1: the label written is the implement row's advances_to"
has "--remove-label status:implementing" "S1: the previous status label is removed"
has "$(lrow status:implementing advance_message)" \
  "S1: the posted body is the advance_message jq reads from personas/lifecycle.json"
has "<!-- lifecycle:in-review:$CM -->" "S1: the idempotency marker is derived from the same row"
has "Trigger: pull request #4242 merged in ${CM:0:12}" \
  "S1: the trigger clause names the pull request and the commit it was found on"
hasnt "Bootstrap compression" "S1: a merge candidate adds no files, so there is nothing to compress"

banner "S2 · item 3 · D2 as amended · a branch that does not parse yields no candidate, whatever the body says"
reset_fixtures
pulls_fixture "$CM" 4243 hotfix-no-number "Emergency repair. Closes #999"
issue_fixture 999 OPEN status:implementing
run "$C4" "$CM" "S2: the unparseable-branch range exits 0"
has "is not on an issue dispatch branch" "S2: the pull request is named and dropped"
hasnt "--add-label" "S2: a closing keyword no longer resolves anything"
hasnt "gh issue comment" "S2: and posts nothing"
hasnt "by closing keyword" "S2: the keyword vocabulary appears nowhere in the output"

banner "S3 · item 3 · D2 as amended · the keyword path is gone from the script, not merely unused"
if grep -q 'kw_count' "$ADVANCER"; then
  grep -n 'kw_count' "$ADVANCER" >&2
  fail "S3: the advancer still carries the closing-keyword counter"
fi
pass "S3: the identifier kw_count appears nowhere in the advancer"
if grep -q 'by closing keyword' "$ADVANCER"; then
  grep -n 'by closing keyword' "$ADVANCER" >&2
  fail "S3: the advancer still reports a closing-keyword resolution"
fi
pass "S3: the string 'by closing keyword' appears nowhere in the advancer"

banner "S4 · D1 · the squash shape: one ordinary commit, no merge commit"
reset_fixtures
pulls_fixture "$C4" 4245 odyssey/999-test "Squashed."
issue_fixture 999 OPEN status:implementing
run "$C3" "$C4" "S4: the squash-shaped range exits 0"
has "--add-label $(lrow status:implementing advances_to)" \
  "S4: a squashed pull request advances the rung exactly as a merge commit does"

banner "S5 · D1 · a push carrying no pull request advances nothing"
reset_fixtures
issue_fixture 999 OPEN status:implementing
run "$C3" "$C4" "S5: the pull-request-less range exits 0"
has "nothing to advance" "S5: the range reports that it found neither an artifact nor a pull request"
hasnt "--add-label" "S5: nothing is written"

banner "S6 · D9 · a closed issue still at the merge rung is red and is not written to"
reset_fixtures
pulls_fixture "$CM" 4246 odyssey/999-test "Implements the plan."
issue_fixture 999 CLOSED status:implementing
run_fail "$C4" "$CM" "S6: the closed-at-the-merge-rung range ends red"
has "::error::" "S6: the run reports an error"
has "#999 is CLOSED but still carries status:implementing" "S6: the failure names the issue and its label"
has "must not carry a closing keyword" "S6: the failure names the cause"
hasnt "--add-label" "S6: no label is written to a closed issue"
hasnt "gh issue comment" "S6: no comment is posted to a closed issue"

banner "S7 · D9 · a closed issue with no status label keeps the quiet skip"
reset_fixtures
pulls_fixture "$CM" 4247 odyssey/999-test "Implements the plan."
issue_fixture 999 CLOSED
run "$C4" "$CM" "S7: the closed-and-unlabelled range exits 0"
has "#999 is CLOSED — skipping" "S7: the issue is skipped quietly"
hasnt "--add-label" "S7: nothing is written"

banner "S8 · D5 · hold is absolute for a merge candidate too"
reset_fixtures
pulls_fixture "$CM" 4248 odyssey/999-test "Implements the plan."
issue_fixture 999 OPEN status:implementing hold
run "$C4" "$CM" "S8: the held range exits 0"
has "halted by hold" "S8: hold stops the merge candidate"
hasnt "--add-label" "S8: no label is written"
hasnt "gh issue comment" "S8: no comment is posted"

banner "S9 · D5 · two status labels on a merge candidate is corrupted state"
reset_fixtures
pulls_fixture "$CM" 4249 odyssey/999-test "Implements the plan."
issue_fixture 999 OPEN status:implementing status:build
run "$C4" "$CM" "S9: the corrupted range exits 0"
has "Corrupted stage state — automation halted." "S9: the corrupted-state body is the artifact path's own"
has "At most one \`status:*\` may be set at a time" "S9: its wording is unchanged"
has "no stage transition was made for pull request #4249 merged in" \
  "S9: only the trigger clause differs from the artifact path's body"
has "--add-label hold" "S9: hold is applied"
hasnt "--add-label $(lrow status:implementing advances_to)" "S9: no stage transition is made"

banner "S10 · D5 · an artifact and a merge for one issue: the furthest rung wins, once"
reset_fixtures
pulls_fixture "$C5" 4250 odyssey/997-both "Implements the plan."
issue_fixture 997 OPEN status:implementing
run "$CM" "$C5" "S10: the contested range exits 0"
exactly "--add-label" 1 "S10: exactly one label write"
exactly "DRY-RUN gh issue comment" 1 "S10: exactly one comment"
has "--add-label $(lrow status:implementing advances_to)" \
  "S10: the label written is the merge rung's, not the artifact rung's"
hasnt "--add-label $(row plan.md advances_to)" "S10: the earlier rung is not re-announced"

banner "S11 · D6 · re-running an advanced issue produces no candidate at all"
reset_fixtures
pulls_fixture "$CM" 4251 odyssey/999-test "Implements the plan."
issue_fixture 999 OPEN status:in-review
run "$C4" "$CM" "S11: the already-advanced range exits 0"
hasnt "--add-label" "S11: no label is written a second time"
hasnt "gh issue comment" "S11: no comment is posted a second time"

banner "S12 · D7 · the first status written clears intent:new, in one edit"
reset_fixtures
pulls_fixture "$CM" 4252 odyssey/999-test "Implements the plan."
issue_fixture 999 OPEN status:implementing intent:new
run "$C4" "$CM" "S12: the intent:new range exits 0"
exactly "DRY-RUN gh issue edit" 1 "S12: one gh issue edit, not two"
has "--add-label $(lrow status:implementing advances_to) --remove-label status:implementing,intent:new" \
  "S12: the one edit carries the new status and removes both the old status and intent:new"

banner "S13 · D7 · intent:new is cleared even when the status label is already the target"
reset_fixtures
jq '(.stages[] | select(.artifact == "plan.md") | .advances_to) = "status:in-review"' \
  "$SANDBOX/personas/lifecycle.json" > "$WORK/patched.json"
cp "$WORK/patched.json" "$SANDBOX/personas/lifecycle.json"
issue_fixture 999 OPEN status:in-review intent:new
run "$C2" "$C3" "S13: the already-at-target range exits 0"
has "--remove-label intent:new" "S13: intent:new is cleared on its own"
hasnt "--add-label status:in-review" "S13: the status label already present is not re-added"
cp "$LADDER" "$SANDBOX/personas/lifecycle.json"

banner "S14 · D7 · a Draft spec writes no status, so it clears nothing"
reset_fixtures
issue_fixture 998 OPEN status:spec intent:new
run "$C2" "$C3" "S14: the Draft range exits 0"
has "Draft spec does not advance" "S14: the Draft is still refused"
hasnt "--remove-label" "S14: nothing is removed when nothing is written"

banner "S15 · D8 D10 · a row with no advances_to and no advance_message is inert"
reset_fixtures
jq '(.stages[] | select(.label == "status:in-review") | .advances_on) = "merge"' \
  "$SANDBOX/personas/lifecycle.json" > "$WORK/patched.json"
cp "$WORK/patched.json" "$SANDBOX/personas/lifecycle.json"
pulls_fixture "$CM" 4253 odyssey/999-test "Implements the plan."
issue_fixture 999 OPEN status:in-review
run "$C4" "$CM" "S15: the last rung's range exits 0"
has "has no advance_message for this row — no comment" "S15: no comment is posted"
has "has no advances_to for this row" "S15: no label is written"
hasnt "--add-label null" "S15: a JSON null never reaches gh as the word null"
hasnt "gh issue comment" "S15: nothing is posted"
cp "$LADDER" "$SANDBOX/personas/lifecycle.json"

banner "S16 · D11 · the comment header states what this workflow now writes"
reset_fixtures
pulls_fixture "$CM" 4254 odyssey/999-test "Implements the plan."
issue_fixture 999 OPEN status:implementing
run "$C4" "$CM" "S16: the header range exits 0"
has 'This workflow writes the `status:*` ladder up to and including `status:in-review`' \
  "S16: the header says the ladder is written end to end"
has 'clears `intent:new` with the first status it writes' "S16: the header says intent:new is cleared"
hasnt "get their writers with #8/#9" "S16: the old dead-end sentence is gone"
if grep -q 'get their writers with #8/#9' "$ADVANCER"; then
  fail "S16: the advancer still claims status:in-review has no writer"
fi
pass "S16: the advancer no longer claims status:in-review has no writer"
if grep -q 'status:planning' "$ADVANCER"; then
  grep -n 'status:planning' "$ADVANCER" >&2
  fail "S16: the advancer names a status label the ladder file owns"
fi
pass "S16: the advancer carries no status:planning literal either"

# ---------------------------------------------------------------------------
# #72 — the repair. Every scenario below fails against 1ea5a97 (the
# script as PR #67 shipped it) and passes after the fix; the acceptance
# item each one pins is named in its banner. Same hermetic rules: the
# throwaway repository, DRY_RUN=1, the stub first on PATH, and every
# expected label and message read out of the fixture ladder.
# ---------------------------------------------------------------------------

banner "S17 · item 15 · D15 · AT-1: the typo branch does not consume the transition"
reset_fixtures
pulls_fixture "$CM" 4260 odyssey/999-typo "A typo fix."
issue_fixture 999 OPEN status:implementing
run "$C4" "$CM" "S17: the typo-branch range exits 0"
hasnt "--add-label" "S17: the wrong pull request advances nothing"
hasnt "gh issue comment" "S17: and posts nothing"
has "is not #999's dispatch branch" "S17: the branch is rejected by name"

reset_fixtures
pulls_fixture "$CM" 4261 odyssey/999-test "The real implementation."
issue_fixture 999 OPEN status:implementing
run "$C4" "$CM" "S17: the real implementation's range exits 0"
has "--add-label $(lrow status:implementing advances_to)" \
  "S17: the label the typo did not consume is still there for the real pull request"
has "Trigger: pull request #4261 merged in" "S17: and the trigger names the right pull request"

banner "S18 · item 16 · D2 · F1 ≡ AT-5: a body full of closing keywords is not a red run"
reset_fixtures
pulls_fixture "$CM" 4262 odyssey/999-test "Closes #36, Closes #35, close #36"
issue_fixture 999 OPEN status:implementing
run "$C4" "$CM" "S18: PR #45's body shape exits 0"
exactly "--add-label" 1 "S18: exactly one transition"
has "--add-label $(lrow status:implementing advances_to)" "S18: and it is the implement rung's"
hasnt "::error::" "S18: no error anywhere in the run"
hasnt "#36" "S18: the run never mentions #36"
hasnt "#35" "S18: the run never mentions #35"

reset_fixtures
pulls_fixture "$CM" 4263 odyssey/999-test "Implements the plan for #999. This also fixes #12 in passing."
issue_fixture 999 OPEN status:implementing
run "$C4" "$CM" "S18: Atlas's prose body exits 0"
exactly "--add-label" 1 "S18: exactly one transition for the prose body too"
hasnt "::error::" "S18: no error for ordinary prose"
hasnt "#12" "S18: the run never mentions #12"

banner "S19 · item 17 · D1 · F2: a pull request that reached main on a second parent"
reset_fixtures
pulls_fixture "$MF" 4264 odyssey/999-test "Merged into the landing branch." "$MF" "$TESTREPO" land
issue_fixture 999 OPEN status:implementing
run "$C5" "$ML" "S19: the landing-branch range exits 0"
has "--add-label $(lrow status:implementing advances_to)" \
  "S19: a pull request merged into a non-default base still advances the rung"
has "Trigger: pull request #4264 merged in ${MF:0:12}" \
  "S19: the trigger names the pull request and its own merge commit"

banner "S19 · item 17 · D1 · a merge commit outside the range is not this push's event"
reset_fixtures
pulls_fixture "$L0" 4265 odyssey/999-test "Merged long ago." "$C1"
issue_fixture 999 OPEN status:implementing
run "$C5" "$ML" "S19: the out-of-range merge exits 0"
has "which is outside" "S19: the pull request is named and dropped"
hasnt "--add-label" "S19: nothing is written for a merge this push did not carry"

banner "S19 · item 17 · D1 · a merge commit the checkout does not contain is red, never silent"
reset_fixtures
pulls_fixture "$L0" 4266 odyssey/999-test "Merged somewhere this clone cannot see." \
  0000000000000000000000000000000000000042
issue_fixture 999 OPEN status:implementing
run_fail "$C5" "$ML" "S19: the unreachable merge commit ends red"
has "::error::" "S19: it is a counted failure"
has "pull request #4266" "S19: the failure names the pull request"
has "fetch-depth: 0" "S19: and names the likely cause"
hasnt "--add-label" "S19: nothing is written"

banner "S20 · item 18 · D15 · AT-6: the right number, the wrong slug"
reset_fixtures
pulls_fixture "$CM" 4267 odyssey/999-998-land "Landing #998's work."
issue_fixture 999 OPEN status:implementing
run "$C4" "$CM" "S20: the landing-style branch exits 0"
hasnt "--add-label" "S20: a branch whose slug is not #999's advances nothing"
hasnt "gh issue comment" "S20: and posts nothing"

banner "S21 · item 21 · D17 · the near miss is announced, exactly once"
exactly "::warning::lifecycle_advance:" 1 "S21: exactly one warning line"
has "::warning::lifecycle_advance: #999 is at status:implementing" "S21: it names the issue and its rung"
has "pull request #4267" "S21: it names the rejected pull request"
has "odyssey/999-998-land" "S21: it names the branch that merged"
has "odyssey/999-test" "S21: and the dispatch branch D15 expected instead"

reset_fixtures
pulls_fixture "$CM" 4268 odyssey/999-998-land "Landing #998's work."
issue_fixture 999 OPEN status:in-review
run "$C4" "$CM" "S21: the same merge with the rung already past exits 0"
hasnt "::warning::lifecycle_advance:" "S21: an issue that is not at the merge rung draws no warning"

reset_fixtures
pulls_fixture "$CM" 4269 odyssey/999-test "The real implementation."
issue_fixture 999 OPEN status:implementing
run "$C4" "$CM" "S21: an ordinary advance exits 0"
hasnt "::warning::lifecycle_advance:" "S21: an issue with no near miss never warns"

banner "S22 · item 19 · D16 · F9: a fork's branch name is not an identity claim"
reset_fixtures
pulls_fixture "$CM" 4270 odyssey/999-test "A drive-by contribution." "$CM" someone-else/agentic-sdlc
issue_fixture 999 OPEN status:implementing
run "$C4" "$CM" "S22: the fork range exits 0"
has "pull request #4270 is from a fork" "S22: the skip is logged by number"
hasnt "--add-label" "S22: no label is written"
hasnt "gh issue comment" "S22: no comment is posted"
hasnt "::warning::lifecycle_advance:" "S22: and no near miss is recorded for a fork"

reset_fixtures
pulls_fixture "$CM" 4271 odyssey/999-test "The fork was deleted." "$CM" null
issue_fixture 999 OPEN status:implementing
run "$C4" "$CM" "S22: the deleted-fork range exits 0"
has "pull request #4271 is from a fork" "S22: a null head.repo behaves identically"
hasnt "--add-label" "S22: still nothing is written"

banner "S23 · item 20 · D1 · F11: the commits/pulls lookup is paginated"
reset_fixtures
pulls_fixture "$CM" 4272 odyssey/999-test "The implementation."
issue_fixture 999 OPEN status:implementing
run "$C4" "$CM" "S23: the paginated range exits 0"
invoked '^gh api --paginate repos/[^ ]+/commits/[0-9a-f]+/pulls$' \
  "S23: every commits/pulls read carries --paginate"
not_invoked '^gh api repos/[^ ]+/commits/' \
  "S23: no unpaginated commits/pulls read is made at all"
invoked '^gh api --paginate repos/[^ ]+/pulls/4272/files$' \
  "S23: the file-list read is paginated too"

banner "S23 · R1-7 · --paginate answers in concatenated arrays, and both reads parse them"
reset_fixtures
pulls_fixture "$CM" 4281 odyssey/999-test "The implementation."
# What `gh --paginate` actually emits for an answer past the 30-item
# default page: one JSON array per page, concatenated. Page 1 here is
# 30 paths under intent/, page 2 the single path outside it, so
# conjunct (2) is decided only if the SECOND array is parsed at all.
# The flag is pinned by the invocation log above; this pins the parse.
{ seq 1 30 | sed 's|.*|intent/999-test/notes-&.md|' | jq -Rc '{filename: .}' | jq -sc '.'
  jq -nc '[{filename: "scripts/ci/lifecycle_advance.sh"}]'; } > "$FIXTURES/files-4281.json"
# The same shape on the sibling read: an empty first page, then the
# page that carries the pull request.
{ jq -nc '[]'; cat "$FIXTURES/pulls-$CM.json"; } > "$WORK/two-page.json"
cp "$WORK/two-page.json" "$FIXTURES/pulls-$CM.json"
issue_fixture 999 OPEN status:implementing
run "$C4" "$CM" "S23: the two-page range exits 0"
has "--add-label $(lrow status:implementing advances_to)" \
  "S23: a 31-path answer split across two pages still resolves conjunct (2)"
has "Trigger: pull request #4281 merged in" \
  "S23: and a pull request on the second page of commits/pulls is still found"

banner "S23 · item 20 · D2 · AT-14: a zero-padded number in the BODY is not a disagreement"
reset_fixtures
pulls_fixture "$CM" 4273 odyssey/999-test "Closes #0999"
issue_fixture 999 OPEN status:implementing
run "$C4" "$CM" "S23: the zero-padded-keyword range exits 0"
exactly "--add-label" 1 "S23: exactly one transition"
hasnt "::error::" "S23: and no false disagreement"

banner "S24 · item 22 · D15 conjunct (2) · an intent-only pull request is not an implementation"
reset_fixtures
pulls_fixture "$CM" 4274 odyssey/999-test "A spec amendment."
files_fixture 4274 intent/999-test/spec.md
issue_fixture 999 OPEN status:implementing
run "$C4" "$CM" "S24: the intent-only range exits 0"
hasnt "--add-label" "S24: a pull request that changes nothing outside intent/ advances nothing"
hasnt "gh issue comment" "S24: and posts nothing"
hasnt "::warning::lifecycle_advance:" "S24: a wrong-file-list merge is not a near miss (D17(a))"
has "changes nothing outside intent/" "S24: the reason is logged"

reset_fixtures
pulls_fixture "$CM" 4275 odyssey/999-test "The implementation."
files_fixture 4275 intent/999-test/spec.md scripts/ci/lifecycle_advance.sh
issue_fixture 999 OPEN status:implementing
run "$C4" "$CM" "S24: the same pull request with one path outside intent/ exits 0"
has "--add-label $(lrow status:implementing advances_to)" \
  "S24: one path outside intent/ is the whole difference"

banner "S24 · item 22 · D15 conjunct (2) · the rebase shape is judged on the file list, not on msha^"
reset_fixtures
pulls_fixture "$R2" 4276 odyssey/999-test "Rebase-merged." "$R2"
files_fixture 4276 intent/999-test/plan.md scripts/ci/lifecycle_advance.sh \
  scripts/ci/tests/lifecycle_advance_test.sh docs/SPEC.md AGENTS.md README.md \
  personas/lifecycle.json
issue_fixture 999 OPEN status:implementing
run "$ML" "$R2" "S24: the rebase-shaped range exits 0"
has "--add-label $(lrow status:implementing advances_to)" \
  "S24: a rebase merge whose last commit is only a plan sync still advances"

banner "S24 · R1-3 AT-2 · an unreadable file list is red, never a quiet intent-only skip"
reset_fixtures
pulls_fixture "$CM" 4279 odyssey/999-test "The implementation."
printf 'not json at all\n' > "$FIXTURES/files-4279.json"
issue_fixture 999 OPEN status:implementing
run_fail "$C4" "$CM" "S24: the malformed file list ends red"
has "::error::" "S24: it is a counted failure"
has "pull request #4279" "S24: the failure names the pull request"
hasnt "changes nothing outside intent/" \
  "S24: an unreadable answer is not reported as a spec amendment"
hasnt "--add-label" "S24: nothing is written"

banner "S24 · R1-2 · D17(a) · an intent-only merge on a mismatched slug is not a near miss"
reset_fixtures
pulls_fixture "$CM" 4280 athena/999-spec-amend "A spec amendment landing while #999 implements."
files_fixture 4280 intent/999-test/spec.md
issue_fixture 999 OPEN status:implementing
run "$C4" "$CM" "S24: the mismatched intent-only range exits 0"
hasnt "::warning::lifecycle_advance:" \
  "S24: ordinary plan and spec traffic draws no warning, whatever its slug (D17(a))"
hasnt "--add-label" "S24: and advances nothing"
has "ordinary intent traffic" "S24: the reason is logged instead"

banner "S25 · item 23 · D15 conjunct (3) · no intent folder in the AFTER tree, and none is a warning"
reset_fixtures
pulls_fixture "$NF" 4277 odyssey/999-test "The implementation." "$NF"
issue_fixture 999 OPEN status:implementing
[ -d "$SANDBOX/intent/999-test" ] || fail "S25: the working checkout should still hold intent/999-test"
run "$C0" "$NF" "S25: the folderless range exits 0"
has "has no intent/999-*/ directory" "S25: the reason is logged"
hasnt "--add-label" "S25: nothing is written"
hasnt "::warning::lifecycle_advance:" \
  "S25: zero folders is not a near miss — the read is of the tree, not of the checkout"

banner "S25 · item 23 · D15 conjunct (3) · two intent folders is corrupted state"
reset_fixtures
pulls_fixture "$TF" 4278 odyssey/999-test "The implementation." "$TF"
issue_fixture 999 OPEN status:implementing
run_fail "$R2" "$TF" "S25: the two-folder range ends red"
has "::error::" "S25: it is a counted failure"
has "intent/999-dup/" "S25: the failure names both folders"
has "intent/999-test/" "S25: the failure names both folders (the second)"
hasnt "--add-label" "S25: nothing is written"

banner "S26 · item 24 · D15 · two accepted pull requests: the topologically later one wins"
reset_fixtures
pulls_fixture "$MA" 4290 odyssey/999-test "The first attempt." "$MA"
pulls_fixture "$MB" 4291 odyssey/999-test "The one that landed last." "$MB" "$TESTREPO" land2
issue_fixture 999 OPEN status:implementing
run "$R2" "$ML2" "S26: the two-candidate range exits 0"
exactly "--add-label" 1 "S26: exactly one transition"
has "Trigger: pull request #4291 merged in ${MB:0:12}" \
  "S26: the transition names the pull request whose merge commit is later in topo order"
hasnt "Trigger: pull request #4290" "S26: and not the one whose commits are newer by date"

banner "S27 · item 25 · D17 · a near miss never reaches D5's chain or D9's rule"
reset_fixtures
pulls_fixture "$CM" 4292 odyssey/999-998-land "Landing #998's work."
issue_fixture 999 OPEN status:implementing status:build
run "$C4" "$CM" "S27: the near miss on a two-status issue exits 0"
hasnt "--add-label hold" "S27: hold is NOT applied by a near miss"
hasnt "Corrupted stage state" "S27: no corrupted-state comment is posted"
hasnt "gh issue comment" "S27: nothing is posted at all"

reset_fixtures
pulls_fixture "$CM" 4293 odyssey/999-998-land "Landing #998's work."
issue_fixture 999 CLOSED status:implementing
run "$C4" "$CM" "S27: the near miss on a closed issue at the merge rung exits 0"
hasnt "::error::" "S27: D9's red does not fire on a near miss"
hasnt "--add-label" "S27: and nothing is written"

banner "S28 · item 26 · D18 · the defect-repair path is never read and never an error"
reset_fixtures
pulls_fixture "$CM" 4294 odyssey/50-work-sh "Fixes the dispatcher. Closes #50"
issue_fixture 50 CLOSED
issue_fixture 999 OPEN status:implementing
run "$C4" "$CM" "S28: the repair merge exits 0"
hasnt "--add-label" "S28: nothing is written"
hasnt "::error::" "S28: GitHub's own close on the keyword is an ordinary fact"
hasnt "::warning::lifecycle_advance:" "S28: and draws no near miss either"
not_invoked 'issue view 50' "S28: #50 is never fetched — asserted from the invocation log"

reset_fixtures
pulls_fixture "$CM" 4295 odyssey/50-work-sh "Fixes the dispatcher. Closes #50"
issue_fixture 50 OPEN status:implementing
run "$C4" "$CM" "S28: the same merge with #50 open at the merge rung exits 0"
hasnt "--add-label" "S28: a hand-labelled folderless issue still advances nothing"
hasnt "::warning::lifecycle_advance:" "S28: and still draws no warning"
not_invoked 'issue view 50' "S28: #50 is still never fetched"

banner "S29 · item 27 · D12 D14 · the repair's living-spec upsert is observable"
LIFECYCLE_ENTRY="$(awk '/^### lifecycle\.labels$/{f=1;next} /^### /{f=0} f' "$REPO/docs/SPEC.md")"
[ -n "$LIFECYCLE_ENTRY" ] || fail "S29: docs/SPEC.md has no lifecycle.labels entry"
# The entry is hard-wrapped at ~70 columns, so a sentence that spans a
# line break matches no one-line literal and the assertion below would
# be vacuous for it (R1-4). Flatten first: one line, single spaces.
LIFECYCLE_FLAT="$(printf '%s\n' "$LIFECYCLE_ENTRY" | tr '\n' ' ' | tr -s ' ')"
while IFS= read -r dead; do
  [ -n "$dead" ] || continue
  if printf '%s\n' "$LIFECYCLE_FLAT" | grep -qF -- "$dead"; then
    fail "S29: lifecycle.labels still says '$dead'"
  fi
done <<'DEAD'
those merged into the default branch
first-parent commits
BRANCH NAME
The two signals disagreeing is a counted failure, not a guess
carried a closing keyword it must not carry
DEAD
pass "S29: none of the five sentences #72 falsified survives in lifecycle.labels"
for alive in "dispatch branch" "fork" "::warning::"; do
  printf '%s\n' "$LIFECYCLE_ENTRY" | grep -qF -- "$alive" \
    || fail "S29: lifecycle.labels does not describe '$alive'"
done
pass "S29: lifecycle.labels describes the identity test, the fork gate and the near-miss warning"
printf '%s\n' "$LIFECYCLE_ENTRY" | grep -qE '\(PR #[0-9]+\)' \
  || fail "S29: lifecycle.labels carries no (PR #<n>) citation"
pass "S29: lifecycle.labels cites the pull request that changed it"
# Acceptance 27 asks that the section SET be unchanged — that this
# repair added and removed none. A literal count is not that property:
# it is the count at whatever commit the assertion was written against,
# and it goes red the moment an unrelated entry lands on main (R1-1).
# Comparing against `origin/main` made the check skip itself silently
# whenever the checkout had no such remote — a hermeticity leak this
# suite is not supposed to have (D13) and a silent no-op this repair
# exists to close everywhere else (#73 R2-1). The baseline lives IN
# this file instead: the section headers docs/SPEC.md carried before
# any of #72/#73 touched it. No git history, no network, and a missing
# or empty baseline is a hard `fail`, never a skip.
SPEC_SECTIONS_BASELINE="$(sort <<'BASELINE'
### docs.structure
### tracker.workflow
### tracker.provisioning
### personas.sources
### identity.bots
### config.bindings
### personas.compiler
### personas.resume
### ci.gates
### lifecycle.labels
### review.policy
### ops.spend
### ops.dispatch
### ops.identity
### execution.placement
### loop.autonomous
BASELINE
)"
[ -n "$SPEC_SECTIONS_BASELINE" ] || fail "S29: the section-set baseline in this test is empty"
spec_now="$(grep '^### ' "$REPO/docs/SPEC.md" | sort)"
[ "$SPEC_SECTIONS_BASELINE" = "$spec_now" ] \
  || { diff <(printf '%s\n' "$SPEC_SECTIONS_BASELINE") <(printf '%s\n' "$spec_now") >&2 || true
       fail "S29: docs/SPEC.md's section set no longer matches this test's own baseline — update both together"; }
pass "S29: the section set of docs/SPEC.md is unchanged by this pull request"

# ---------------------------------------------------------------------------
# #73 — fail closed on every read, and a transition never walks backward.
# ---------------------------------------------------------------------------

banner "S30 · item 28 · F3 · D19 · a backward transition is refused, not applied"
reset_fixtures
issue_fixture 999 OPEN status:in-review
run "$C2" "$C3" "S30: the plan.md range against a further-along issue still exits 0"
exactly "::warning::lifecycle_advance:" 1 "S30: exactly one warning line"
has "::warning::lifecycle_advance: #999 is at status:in-review" \
  "S30: the warning names the issue and its current rung"
has "would move it to status:implementing" \
  "S30: and names the rung the trigger would otherwise have written"
has "plan.md\` added in" "S30: and names the trigger that would have moved it (Acceptance 28's fourth thing)"
has "does not advance the ladder" "S30: and states why nothing happened (D19)"
hasnt "--add-label" "S30: no label is written for a backward transition"
hasnt "--remove-label" "S30: and nothing is removed either"
hasnt "gh issue comment 999" "S30: and no comment is posted for #999"

banner "S30 · item 28 · D19 · a forward transition still lands"
reset_fixtures
issue_fixture 999 OPEN status:build
run "$C2" "$C3" "S30: the plan.md range against a lower rung exits 0"
hasnt "::warning::lifecycle_advance:" "S30: a forward transition draws no D19 warning"
has "--add-label $(row plan.md advances_to)" \
  "S30: the build row's label is still written when the transition is forward"
has "--remove-label status:build" "S30: and the previous rung is removed"

banner "S30 · item 28 · D19 · an issue already at the target rank writes nothing"
reset_fixtures
issue_fixture 999 OPEN status:implementing
run "$C2" "$C3" "S30: the plan.md range against an issue already at the target rank exits 0"
hasnt "--add-label" "S30: no label is written when the target equals the current rank"
hasnt "--remove-label status:implementing" "S30: and the current label is not removed either"
hasnt "gh issue comment 999" "S30: and no comment is posted for #999"
hasnt "::warning::lifecycle_advance:" "S30: and no warning is drawn — this is equal, not below"

reset_fixtures
issue_fixture 999 OPEN status:implementing intent:new
run "$C2" "$C3" "S30: the same equal-rank case with intent:new still exits 0"
has "gh issue edit 999 --repo $TESTREPO --remove-label intent:new" \
  "S30: intent:new is still cleared in its own edit, even though the rung is unchanged"
hasnt "--add-label" "S30: and no rung label rides along with it"

banner "S30 · item 28 · D19 · an unranked current status is refused like a backward one"
reset_fixtures
issue_fixture 999 OPEN status:review-stuck
run "$C2" "$C3" "S30: the plan.md range against an unranked status exits 0"
has "::warning::lifecycle_advance: #999 is at status:review-stuck" \
  "S30: the warning names the issue and its unranked status"
hasnt "--add-label" "S30: no label is written when the current status cannot be ranked"

banner "S30 · item 28 · Argus R1-1 · D19 · already at an UNRANKED target label writes nothing at all"
# The same patch the "ladder file is the source" test above makes: an
# advances_to the ladder's own five labels do not list, reachable only
# by hand-editing or typo'ing personas/lifecycle.json. #999 already
# carries that exact label, so this is the equal case — but on a target
# D19's rank gate cannot rank. Base's unconditional same-label
# short-circuit covered this; gating D19 entirely on a RANKED target
# without restoring it let this case fall through to a self-cancelling
# `--add-label status:elsewhere --remove-label status:elsewhere`.
jq '(.stages[] | select(.artifact == "plan.md") | .advances_to) = "status:elsewhere"' \
  "$SANDBOX/personas/lifecycle.json" > "$WORK/patched.json"
cp "$WORK/patched.json" "$SANDBOX/personas/lifecycle.json"
reset_fixtures
issue_fixture 999 OPEN status:elsewhere
run "$C2" "$C3" "S30: the patched-ladder range against an issue already at the unranked target exits 0"
hasnt "gh issue edit 999" "S30: no edit at all is attempted — not even a self-cancelling add-and-remove of the same label"
hasnt "::warning::lifecycle_advance:" "S30: and this is not shown as a refusal either — it is already there"
cp "$LADDER" "$SANDBOX/personas/lifecycle.json"

banner "S31 · item 29 · AT-7 · D20 · blocked is advisory: it never stops or taints a legitimate transition"
reset_fixtures
pulls_fixture "$CM" 4296 odyssey/999-test "Implements the plan."
issue_fixture 999 OPEN status:implementing blocked
run "$C4" "$CM" "S31: the merge range with blocked also carried exits 0"
has "--add-label $(lrow status:implementing advances_to)" \
  "S31: blocked does not refuse the transition — the label is still written"
has "--remove-label status:implementing" "S31: and the previous rung is still removed"
has "$(lrow status:implementing advance_message)" "S31: and the advance comment is still posted"
hasnt "blocked" "S31: the string blocked never appears in a label write, a comment, or a warning"

banner "S32 · item 30 · AT-10 · D6 · the comment is written before the label, in that order"
reset_fixtures
pulls_fixture "$CM" 4297 odyssey/999-test "Implements the plan."
issue_fixture 999 OPEN status:implementing
run "$C4" "$CM" "S32: the ordinary merge range exits 0"
comment_line="$(printf '%s\n' "$OUT" | grep -nF -- "DRY-RUN gh issue comment 999" | head -1 | cut -d: -f1)"
edit_line="$(printf '%s\n' "$OUT" | grep -nF -- "DRY-RUN gh issue edit 999" | head -1 | cut -d: -f1)"
if [ -n "$comment_line" ] && [ -n "$edit_line" ] && [ "$comment_line" -lt "$edit_line" ]; then
  pass "S32: the comment line precedes the label edit line, so a crash between them leaves the comment as the only trace (D6)"
else
  printf '%s\n' "$OUT" >&2
  fail "S32: expected the comment line before the label edit line (comment=$comment_line edit=$edit_line)"
fi

banner "S32 · item 30 · AT-10 · D6 · a marker already on the thread means the comment half already landed — only the label is retried"
reset_fixtures
issue_fixture_comment 999 OPEN "<!-- lifecycle:in-review:$CM -->" status:implementing
pulls_fixture "$CM" 4298 odyssey/999-test "Implements the plan."
run "$C4" "$CM" "S32: the reconstructed partial-write range exits 0"
has "--add-label $(lrow status:implementing advances_to)" \
  "S32: the label half is still written on retry"
hasnt "DRY-RUN gh issue comment" "S32: the comment half is not re-posted — its marker is already on the thread"

banner "S33 · item 31 · R2-2 · D15 conjunct (2) · an empty file-list body is a counted failure, not a quiet skip"
reset_fixtures
pulls_fixture "$CM" 4299 odyssey/999-test "Implements the plan."
files_fixture_raw 4299 ""
issue_fixture 999 OPEN status:implementing
run_fail "$C4" "$CM" "S33: the empty file-list body ends red"
has "::error::" "S33: it is a counted failure"
has "pull request #4299" "S33: the failure names the pull request"
hasnt "--add-label" "S33: nothing is written"
hasnt "::warning::lifecycle_advance:" "S33: and it is not mistaken for a near miss either"

banner "S33 · item 31 · D15 conjunct (2) · a file-list body that is not JSON is the same counted failure"
reset_fixtures
pulls_fixture "$CM" 4300 odyssey/999-test "Implements the plan."
files_fixture_raw 4300 "not json at all"
issue_fixture 999 OPEN status:implementing
run_fail "$C4" "$CM" "S33: the non-JSON file-list body ends red"
has "::error::" "S33: it is a counted failure"
has "pull request #4300" "S33: the failure names the pull request"
hasnt "--add-label" "S33: nothing is written"
hasnt "::warning::lifecycle_advance:" "S33: and it is not mistaken for a near miss either"

banner "S33 · item 31 · D15 conjunct (2) · a file-list body that parses as an object, not an array, is the same counted failure"
reset_fixtures
pulls_fixture "$CM" 4301 odyssey/999-test "Implements the plan."
files_fixture_raw 4301 "{}"
issue_fixture 999 OPEN status:implementing
run_fail "$C4" "$CM" "S33: the {} file-list body ends red"
has "::error::" "S33: it is a counted failure"
has "pull request #4301" "S33: the failure names the pull request"
hasnt "--add-label" "S33: nothing is written"
hasnt "::warning::lifecycle_advance:" "S33: and it is not mistaken for a near miss either"

banner "S33 · item 31 · D15 conjunct (2) · a well-formed empty array is still the silent negative answer"
reset_fixtures
pulls_fixture "$CM" 4302 odyssey/999-test "Implements the plan."
files_fixture_raw 4302 "[]"
issue_fixture 999 OPEN status:implementing
run "$C4" "$CM" "S33: the [] file-list body exits 0"
hasnt "::error::" "S33: an empty array is not a counted failure"
hasnt "::warning::lifecycle_advance:" "S33: and not a near miss either"
hasnt "--add-label" "S33: nothing is written — the pull request touched nothing outside intent/"

banner "S34 · item 32 · AT-2 · D21(a) · an unreadable issue is a counted failure, never silent and never substituted"
reset_fixtures
pulls_fixture "$CM" 4303 odyssey/999-test "Implements the plan."
issue_fixture 999 OPEN status:implementing
issue_unreadable 999
run_fail "$C4" "$CM" "S34: the merge range against an unreadable issue ends red"
has "::error::" "S34: it is a counted failure"
has "cannot read #999" "S34: the failure names the issue"
hasnt "--add-label" "S34: nothing is written"
hasnt "DRY-RUN gh issue comment" "S34: no comment is posted"
hasnt "DRY-RUN gh issue edit" "S34: no label edit is attempted"
hasnt "==> Done." "S34: the run never reports a completed pass"

banner "S34 · item 32 · AT-2 · D21 · the near-miss read stays quiet on the same fault — an intentional exception, not a hole"
reset_fixtures
pulls_fixture "$CM" 4304 odyssey/999-998-land "Landing #998's work."
issue_fixture 999 OPEN status:implementing
issue_unreadable 999
run "$C4" "$CM" "S34: the near-miss range with #999 unreadable still exits 0"
invoked "issue view 999" "S34: the excepted read did happen — this pins a quiet failure, not a skipped read"
hasnt "::error::" "S34: the near-miss read failing is not a counted failure (#57, D21)"
hasnt "::warning::lifecycle_advance:" "S34: and draws no warning — an unreadable issue cannot be shown to be at the merge rung"

banner "S35 · item 33 · AT-11 · D21(b) · a failed range walk is a counted, run-ending failure before any issue is read"
reset_fixtures
pulls_fixture "$CM" 4305 odyssey/999-test "Implements the plan."
issue_fixture 999 OPEN status:implementing
export LIFECYCLE_TEST_GIT_REV_LIST_FAIL=1
run_fail "$C4" "$CM" "S35: the range walk fault ends red"
unset LIFECYCLE_TEST_GIT_REV_LIST_FAIL
has "::error::" "S35: it is a counted failure"
has "range walk" "S35: the failure names the range walk"
hasnt "--add-label" "S35: nothing is written"
hasnt "DRY-RUN gh issue comment" "S35: no comment is posted"
not_invoked 'issue view' "S35: no issue is read — the range walk fails before any candidate is discovered"

reset_fixtures

banner "nothing was written"
[ ! -s "$WRITES" ] || { cat "$WRITES" >&2; fail "a gh write was attempted under DRY_RUN=1"; }
pass "no gh write was attempted in any scenario"

echo
echo "lifecycle_advance_test.sh: all scenarios passed"
