#!/usr/bin/env bash
# Roundtrip proof for the persona compiler (scripts/sync_agents.py).
#
# One command takes the canonical sources all the way to working harness
# targets and back:
#
#   1. schema-check — every personas/*.yaml validates and compiles
#   2. determinism  — two independent builds are byte-identical
#   3. no drift     — the committed targets equal a fresh build
#   4. roundtrip    — the emitted targets are re-parsed from disk and
#                     asserted to carry the resolved model, the mapped
#                     tools, and the full text of every declared skill
#   5. new persona  — a throwaway source compiles end-to-end in a temp
#                     tree (pinned harness only, generated fallback for
#                     an optional capability the harness cannot map)
#   6. sanitizer    — a source carrying a home path is REFUSED
#   7. lifecycle    — invalid rungs, duplicate labels, and advances_on
#                     invariants are refused
#
# Exit 0 means the compiler is honest about its own output. This is the
# script CI (#6) runs; nothing here touches the working tree.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
COMPILER="$REPO/scripts/sync_agents.py"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/compiler-roundtrip.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

[ -f "$COMPILER" ] || { echo "ERROR: $COMPILER not found." >&2; exit 1; }
command -v python3 >/dev/null || { echo "ERROR: python3 is not installed." >&2; exit 1; }

step() { printf '\n=== %s\n' "$1"; }
fail() { echo "FAIL: $1" >&2; exit 1; }

# assert_in <needle> <file> <what>
assert_in() {
  grep -qF -- "$1" "$2" || fail "$3 (expected '$1' in ${2#"$TMP"/})"
  echo "  ok: $3"
}

# assert_not_in <regex> <file> <what>
# The `if` form rather than `grep … && fail`: under `set -e` a passing
# assertion would otherwise make the function return grep's 1 and kill
# the script.
assert_not_in() {
  if grep -q -- "$1" "$2"; then
    fail "$3 (found '$1' in ${2#"$TMP"/})"
  fi
  echo "  ok: $3"
}

# assert_absent <path> <what>
assert_absent() {
  if [ -e "$1" ]; then
    fail "$2 (${1#"$TMP"/} still exists)"
  fi
  echo "  ok: $2"
}

# --- 1. schema-check + full build --------------------------------------------
step "1. schema-check: all sources validate and compile"
python3 "$COMPILER" --root "$REPO" --out "$TMP/build-a" >/dev/null \
  || fail "sources do not compile"
count="$(find "$TMP/build-a/.claude/agents" "$TMP/build-a/.agents/agents" -type f | wc -l)"
echo "  ok: $count target files emitted from $(ls "$REPO"/personas/*.yaml | wc -l) sources"

# --- 2. determinism -----------------------------------------------------------
step "2. determinism: two builds are byte-identical"
python3 "$COMPILER" --root "$REPO" --out "$TMP/build-b" >/dev/null
diff -r "$TMP/build-a" "$TMP/build-b" || fail "two builds of the same sources differ"
echo "  ok: build-a and build-b are identical"

# --- 3. drift gate ------------------------------------------------------------
step "3. drift: committed targets match a fresh build"
python3 "$COMPILER" --check || fail "committed targets have drifted — rebuild and commit"

# --- 4. roundtrip: re-parse the emitted targets -------------------------------
step "4. roundtrip: emitted targets carry model, tools, and full skill text"
python3 "$COMPILER" --verify || fail "emitted targets lost a resolved fact"

# --- 5. a brand-new persona goes end-to-end -----------------------------------
step "5. new persona: a throwaway source compiles on its pinned harness"
SRC="$TMP/src"
mkdir -p "$SRC"
cp -r "$REPO/personas" "$REPO/config" "$SRC/"

cat > "$SRC/personas/throwaway.yaml" <<'YAML'
# Throwaway source created by scripts/ci/compiler_roundtrip.sh. Never
# committed: it exists only inside the test's temp tree.
name: throwaway
kind: persona
stage: [maintain]
tier: FAST

role: >-
  A disposable actor that exists only so the compiler roundtrip can
  prove a brand-new source reaches working harness targets without a
  single hand edit. It reads the repository, asks the human when a
  choice is genuinely open, and does nothing else at all.

skills:
  - trusted-posting.md
  - resume-protocol.md

capabilities:
  - name: read_repo
  - name: ask_user
    required: false

authority:
  github_write: "none"
  identity: "TBD"
  token: THROWAWAY_BOT_TOKEN

limits:
  max_turns: 1
  timeout_mins: 1
YAML

# Pin it to the harness that has NO native ask_user tool, so the build
# must generate the fallback instruction from config/tools.yaml.
sed -i '/^personas:/a\  throwaway: { harness: antigravity }' "$SRC/config/deployments.yaml"

python3 "$COMPILER" --root "$SRC" --out "$TMP/new" >/dev/null \
  || fail "the throwaway persona did not compile"

AGENT="$TMP/new/.agents/agents/throwaway"
[ -d "$AGENT" ] || fail "no antigravity target emitted for the throwaway persona"
if [ -f "$TMP/new/.claude/agents/throwaway.md" ]; then
  fail "throwaway is pinned to one harness but was emitted for both"
fi
echo "  ok: emitted for the pinned harness only"

# The model is a config value, not a constant. Resolve it from the same
# source tree the compiler just read, so re-pinning a tier in
# config/model_tiers.yaml never turns into a failing test here.
FAST_MODEL="$(awk '/^  antigravity:/ {inh=1; next}
                   /^  [a-z]/        {inh=0}
                   inh && /^    FAST:/ {print $2; exit}' \
              "$SRC/config/model_tiers.yaml")"
[ -n "$FAST_MODEL" ] \
  || fail "could not resolve the antigravity FAST tier from config/model_tiers.yaml"
assert_in "\"model\": \"$FAST_MODEL\"" "$AGENT/agent.json" \
  "agent.json carries the FAST-tier model ($FAST_MODEL) for the pinned harness"
assert_in '  - view_file' "$AGENT/agent.md" \
  "agent.md carries the tools mapped from read_repo, as a YAML block list"
assert_in '# Skill: trusted-posting' "$AGENT/agent.md" \
  "agent.md inlines the declared skill"
assert_in '## Lifecycle stages' "$AGENT/agent.md" \
  "agent.md carries the ladder generated from personas/lifecycle.json"
assert_in '### review' "$AGENT/agent.md" \
  "the generated ladder carries a section per rung of the ladder"
assert_in '- Owner: argus, atlas' "$AGENT/agent.md" \
  "the generated ladder derives multi-owner stages, sorted"
assert_in '### ask_user' "$AGENT/agent.md" \
  "agent.md carries a generated fallback section"
assert_in 'No interactive question tool is available' "$AGENT/agent.md" \
  "the fallback text comes from config/tools.yaml, not a hand edit"
assert_in 'GENERATED by scripts/sync_agents.py' "$AGENT/agent.json" \
  "agent.json carries the generated-file marker"
assert_in '# GENERATED by scripts/sync_agents.py' "$AGENT/agent.md" \
  "agent.md carries the marker as a frontmatter comment (#43 probe P1)"

# The two negatives that make the new layout real. A `model:` key voids
# the agent for agy — it falls back to the stock agent and still exits 0
# (#43 D8), so the compiler must never emit one; and the three-file
# layout must be gone rather than merely unread (#43 D10).
assert_not_in '^model:' "$AGENT/agent.md" \
  "agent.md carries no model key — one would silently void the agent"
assert_absent "$AGENT/config.yaml" \
  "the superseded config.yaml is not emitted"
assert_absent "$AGENT/instructions.md" \
  "the superseded instructions.md is not emitted"

python3 "$COMPILER" --root "$SRC" --out "$TMP/new" --verify \
  || fail "the throwaway targets did not roundtrip"

# --- 6. the sanitizer refuses unsafe output -----------------------------------
step "6. sanitizer: a source carrying a home path is refused"
POISON="$TMP/poison"
mkdir -p "$POISON"
cp -r "$SRC/personas" "$SRC/config" "$POISON/"
rm -f "$POISON/personas/throwaway.yaml"

# Assembled from parts so that no literal absolute home path is ever
# committed to this repository — the fixture only exists at runtime.
LEAK_DIR=home
LEAK_PATH="/${LEAK_DIR}/someone/secrets-file"

cat > "$POISON/personas/leaky.yaml" <<YAML
name: leaky
kind: subagent
tier: FAST

role: >-
  A source that leaks an absolute home path into its own contract, which
  the compiler must refuse to emit rather than bake into a prompt that
  ships. It reads ${LEAK_PATH} and reports whatever it finds there.

capabilities:
  - name: read_repo
YAML

if python3 "$COMPILER" --root "$POISON" --out "$TMP/poisoned" >"$TMP/poison.log" 2>&1; then
  fail "the compiler emitted a target containing a home path"
fi
grep -q "REFUSING TO WRITE" "$TMP/poison.log" \
  || fail "build failed, but not with the sanitizer's refusal message"
if [ -d "$TMP/poisoned" ]; then
  fail "the refused build still wrote output"
fi
echo "  ok: refused, and nothing was written"

# The site-specific deny list is supplied at run time, never committed.
# A word that is perfectly innocent by default must be refused once the
# operator names it.
if SYNC_AGENTS_DENY="disposable actor" \
     python3 "$COMPILER" --root "$SRC" --out "$TMP/denied" >"$TMP/deny.log" 2>&1; then
  fail "SYNC_AGENTS_DENY did not stop a denied string from being emitted"
fi
grep -q "denied local string" "$TMP/deny.log" \
  || fail "build failed, but not because of the run-time deny list"
echo "  ok: SYNC_AGENTS_DENY refuses site-specific strings at run time"

# --- 7. lifecycle validation: invalid rungs and advances_on invariants are refused ---
step "7. lifecycle: invalid stages, duplicate labels, and advances_on invariants are refused"
LIFECYCLE_TEST_DIR="$TMP/lifecycle-test"
mkdir -p "$LIFECYCLE_TEST_DIR"
cp -r "$REPO/personas" "$REPO/config" "$LIFECYCLE_TEST_DIR/"
LF_JSON="$LIFECYCLE_TEST_DIR/personas/lifecycle.json"

assert_lifecycle_refused() {
  local what="$1"
  local needle="$2"
  if python3 "$COMPILER" --root "$LIFECYCLE_TEST_DIR" --check >"$TMP/lc.log" 2>&1; then
    fail "lifecycle validation: compiler succeeded unexpectedly for $what"
  fi
  grep -qF "$needle" "$TMP/lc.log" \
    || fail "lifecycle validation: $what failed, but error did not match '$needle'. Output: $(cat "$TMP/lc.log")"
  echo "  ok: refused $what ('$needle')"
}

# 1. invalid stage name not in schema.json's stage enum
python3 -c '
import json
p = "'"$LF_JSON"'"
d = json.loads(open(p).read())
d["stages"][0]["stage"] = "bogus_stage"
open(p, "w").write(json.dumps(d))
'
assert_lifecycle_refused "invalid stage name" "stage 'bogus_stage' is not one of"

# 2. duplicate stage label
python3 -c '
import json
p = "'"$LF_JSON"'"
d = json.loads(open(p).read())
d["stages"][0]["stage"] = "plan"
d["stages"][1]["label"] = d["stages"][0]["label"]
open(p, "w").write(json.dumps(d))
'
assert_lifecycle_refused "duplicate stage label" "duplicate label rows"

# 3. missing advances_on
python3 -c '
import json
p = "'"$LF_JSON"'"
d = json.loads(open(p).read())
d["stages"][1]["label"] = "status:spec"
del d["stages"][0]["advances_on"]
open(p, "w").write(json.dumps(d))
'
assert_lifecycle_refused "missing advances_on" "missing advances_on"

# 4. invalid advances_on value
python3 -c '
import json
p = "'"$LF_JSON"'"
d = json.loads(open(p).read())
d["stages"][0]["advances_on"] = "invalid_trigger"
open(p, "w").write(json.dumps(d))
'
assert_lifecycle_refused "invalid advances_on" 'invalid advances_on "invalid_trigger"'

# 5. artifact mismatch (advances_on=artifact but artifact=null)
python3 -c '
import json
p = "'"$LF_JSON"'"
d = json.loads(open(p).read())
d["stages"][0]["advances_on"] = "artifact"
d["stages"][0]["artifact"] = None
open(p, "w").write(json.dumps(d))
'
assert_lifecycle_refused "artifact null when advances_on is artifact" "advances_on is 'artifact' but artifact is null"

# 6. artifact mismatch (advances_on!=artifact but artifact non-null)
python3 -c '
import json
p = "'"$LF_JSON"'"
d = json.loads(open(p).read())
d["stages"][0]["artifact"] = "intent.md"
d["stages"][3]["artifact"] = "unexpected.md"
open(p, "w").write(json.dumps(d))
'
assert_lifecycle_refused "artifact non-null when advances_on is merge" 'advances_on is "merge" but artifact is non-null'

# 7. non-terminal null advances_on
python3 -c '
import json
p = "'"$LF_JSON"'"
d = json.loads(open(p).read())
d["stages"][3]["artifact"] = None
d["stages"][0]["advances_on"] = None
d["stages"][0]["artifact"] = None
open(p, "w").write(json.dumps(d))
'
assert_lifecycle_refused "non-terminal null advances_on" "non-terminal rung cannot have advances_on null"

# 8. terminal non-null advances_on
python3 -c '
import json
p = "'"$LF_JSON"'"
d = json.loads(open(p).read())
d["stages"][0]["advances_on"] = "artifact"
d["stages"][0]["artifact"] = "intent.md"
d["stages"][4]["advances_on"] = "merge"
open(p, "w").write(json.dumps(d))
'
assert_lifecycle_refused "terminal non-null advances_on" "last rung must have advances_on null"

# 9. non-terminal null advances_to
python3 -c '
import json
p = "'"$LF_JSON"'"
d = json.loads(open(p).read())
d["stages"][4]["advances_on"] = None
d["stages"][0]["advances_to"] = None
open(p, "w").write(json.dumps(d))
'
assert_lifecycle_refused "non-terminal null advances_to" "non-terminal rung cannot have advances_to null"

# 10. terminal non-null advances_to
python3 -c '
import json
p = "'"$LF_JSON"'"
d = json.loads(open(p).read())
d["stages"][0]["advances_to"] = "status:spec"
d["stages"][4]["advances_to"] = "status:done"
open(p, "w").write(json.dumps(d))
'
assert_lifecycle_refused "terminal non-null advances_to" "last rung must have advances_to null"

# 11. multiple merges
python3 -c '
import json
p = "'"$LF_JSON"'"
d = json.loads(open(p).read())
d["stages"][4]["advances_to"] = None
d["stages"][0]["advances_on"] = "merge"
d["stages"][0]["artifact"] = None
open(p, "w").write(json.dumps(d))
'
assert_lifecycle_refused "multiple merges" "expected exactly one rung with advances_on 'merge', found 2"

# 12. zero merges
python3 -c '
import json
p = "'"$LF_JSON"'"
d = json.loads(open(p).read())
d["stages"][0]["advances_on"] = "artifact"
d["stages"][0]["artifact"] = "intent.md"
d["stages"][3]["advances_on"] = "artifact"
d["stages"][3]["artifact"] = "code.patch"
open(p, "w").write(json.dumps(d))
'
assert_lifecycle_refused "zero merges" "expected exactly one rung with advances_on 'merge', found 0"

printf '\nPASS: compiler roundtrip green (%s target files, 7 checks).\n' "$count"
