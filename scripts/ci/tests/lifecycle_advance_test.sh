#!/usr/bin/env bash
# Tests for scripts/ci/lifecycle_advance.sh (#36, intent/36-dispatch/plan.md T9).
#
#   bash scripts/ci/tests/lifecycle_advance_test.sh
#
# Hermetic: a synthetic range in a throwaway git repository, a stub `gh`
# first on PATH that cannot read any issue (so DRY_RUN substitutes an
# open, unlabelled one) and records any write it is asked to make, and
# DRY_RUN=1 throughout. No network, no token, no issue is touched.
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
mkdir -p "$WORK/bin" "$WORK/fixtures"
FIXTURES="$WORK/fixtures"
export WRITES FIXTURES
export PATH="$WORK/bin:$PATH"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }
banner() { printf '\n--- %s\n' "$*"; }

cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
# The stub answers exactly the two READS the advancer makes, and only
# from files in $FIXTURES — no network, no token. A missing fixture
# falls through to the pre-#57 behaviour, so every scenario written
# before merge discovery existed still runs against an issue the stub
# cannot read and DRY_RUN substitutes an open, unlabelled one for.
# Anything else reaching gh in a dry run is a write that should never
# have been attempted, and is recorded as one.
if [ "${1:-}" = "issue" ] && [ "${2:-}" = "view" ]; then
  if [ -f "$FIXTURES/issue-${3:-}.json" ]; then
    cat "$FIXTURES/issue-${3:-}.json"
    exit 0
  fi
  exit 1
fi
if [ "${1:-}" = "api" ]; then
  case "${2:-}" in
    */commits/*/pulls)
      sha="${2#*/commits/}"
      sha="${sha%/pulls}"
      if [ -f "$FIXTURES/pulls-$sha.json" ]; then
        cat "$FIXTURES/pulls-$sha.json"
      else
        # A commit belonging to no pull request: an empty list, not an
        # error.
        echo '[]'
      fi
      exit 0;;
    repos/*)
      echo '{"default_branch":"main"}'
      exit 0;;
  esac
fi
echo "gh $*" >> "$WRITES"
exit 1
STUB
chmod +x "$WORK/bin/gh"

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

reset_fixtures() { rm -f "$FIXTURES"/*.json; }
issue_fixture() { # <number> <state> [label ...]
  local n="$1" state="$2" labels='[]'
  shift 2
  [ "$#" -eq 0 ] || labels="$(printf '%s\n' "$@" | jq -Rc '{name: .}' | jq -sc '.')"
  jq -nc --argjson n "$n" --arg s "$state" --argjson l "$labels" \
    '{number: $n, state: $s, labels: $l, comments: []}' > "$FIXTURES/issue-$n.json"
}
pulls_fixture() { # <sha> <pr-number> <head-ref> <body> [base-ref]
  jq -nc --argjson n "$2" --arg h "$3" --arg b "$4" --arg base "${5:-main}" \
    '[{number: $n, merged_at: "2026-01-01T00:00:00Z", state: "closed",
       base: {ref: $base}, head: {ref: $h}, body: $b}]' > "$FIXTURES/pulls-$1.json"
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

banner "S2 · D2 · a branch with no number falls back to the closing keyword"
reset_fixtures
pulls_fixture "$CM" 4243 hotfix-no-number "Emergency repair. Closes #999"
issue_fixture 999 OPEN status:implementing
run "$C4" "$CM" "S2: the keyword-resolved range exits 0"
has "--add-label $(lrow status:implementing advances_to)" "S2: the same transition is applied"
has "Trigger: pull request #4243 merged in" "S2: the trigger names the keyword-resolved pull request"

banner "S3 · D2 · branch and keyword disagreeing is a refusal, not a guess"
reset_fixtures
pulls_fixture "$CM" 4244 odyssey/999-test "Closes #998"
issue_fixture 999 OPEN status:implementing
run_fail "$C4" "$CM" "S3: the disagreement range ends red"
has "#999 by branch name" "S3: the failure names the branch's issue"
has "#998 by closing keyword" "S3: the failure names the keyword's issue"
has "not guessing" "S3: the failure says it is refusing rather than picking"
hasnt "--add-label" "S3: no label is written for a pull request that resolves to two issues"

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

reset_fixtures

banner "nothing was written"
[ ! -s "$WRITES" ] || { cat "$WRITES" >&2; fail "a gh write was attempted under DRY_RUN=1"; }
pass "no gh write was attempted in any scenario"

echo
echo "lifecycle_advance_test.sh: all scenarios passed"
