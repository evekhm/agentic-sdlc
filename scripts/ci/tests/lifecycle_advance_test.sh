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
mkdir -p "$WORK/bin"
export WRITES
export PATH="$WORK/bin:$PATH"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }
banner() { printf '\n--- %s\n' "$*"; }

cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
# `issue view` is a read and is allowed to fail: DRY_RUN substitutes an
# open, unlabelled issue, which is what makes the synthetic range
# testable. Anything else reaching gh in a dry run is a write that
# should never have been attempted.
if [ "${1:-}" = "issue" ] && [ "${2:-}" = "view" ]; then
  exit 1
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
# row <artifact> <key> -> the value the script must be reading
row() { jq -r --arg a "$1" ".stages[] | select(.artifact == \$a) | .$2" \
          "$SANDBOX/personas/lifecycle.json"; }

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

banner "nothing was written"
[ ! -s "$WRITES" ] || { cat "$WRITES" >&2; fail "a gh write was attempted under DRY_RUN=1"; }
pass "no gh write was attempted in any scenario"

echo
echo "lifecycle_advance_test.sh: all scenarios passed"
