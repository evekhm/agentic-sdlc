#!/usr/bin/env bash
# Tests for scripts/ops/smoke_launch.sh (#44, spec D7/D14; round-2
# regressions for Argus R1-1/R1-2/R1-4 and Atlas AT-2/AT-3/AT-5).
#
#   bash scripts/ops/tests/smoke_launch_test.sh
#
# Hermetic: no network, no App token, no launch. Two shapes of scenario.
#
#   DERIVATION  `DRY_RUN=1` against scratch `config/deployments.yaml`,
#               `scripts/auth/app_manifests.yaml` and `personas/` copies
#               under $WORK, through the three SMOKE_* overrides. Nothing
#               is minted or written on this path by construction — the
#               script exits above the mint block.
#   GUARD       the scratch-issue refusal, which runs AFTER the mint
#               helper is resolved, so it needs a fixture tree: a temp
#               REPO_ROOT owning a copy of the script, a stub mint that
#               prints a fake token, a stub work.sh that fails loudly if
#               a scenario launches it, and a stub `gh` that answers the
#               one read the guard makes and records every other call as
#               an attempted WRITE.
#
# Why these scenarios and not others: each one is a defect a reviewer
# measured on this script at head 3eaff89, so each must be red against
# that head and green now. The derivation half is where this gate's
# whole value sits — a parser that drops a pin makes the gate report
# coverage of a harness it never touched — and the guard half is the
# blast radius, since the first three writes land before any launch.
#
# Exit 0 with a PASS line per assertion, non-zero on the first failure.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SMOKE_SH="$REPO/scripts/ops/smoke_launch.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/bin" "$WORK/fixtures"
export PATH="$WORK/bin:$PATH"
export GITHUB_REPO="test/repo"

passes=0
pass() { passes=$((passes + 1)); echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

contains()  { case "$2" in *"$1"*) return 0 ;; *) return 1 ;; esac; }
refutes()   { case "$2" in *"$1"*) return 1 ;; *) return 0 ;; esac; }

# --- the fixture config ---------------------------------------------------------
# Six personas over two harnesses, the same shape the real file has, so a
# scenario changes exactly one thing and the rest is a control.
inline_pins() { cat > "$1" <<'YAML'
personas:
  athena:    { harness: claude-code }
  daedalus:  { harness: antigravity }
  odyssey:   { harness: claude-code }
  argus:     { harness: claude-code }
  atlas:     { harness: antigravity }
  cassandra: { harness: claude-code }
constraints:
  distinct_model_families: [argus, atlas]
YAML
}

# The SAME pins in block form. `yaml.safe_load` (sync_agents.py) and
# work.sh's `harness_of` both read this; the gate must agree with them.
block_pins() { cat > "$1" <<'YAML'
personas:
  athena:    { harness: claude-code }
  daedalus:
    harness: antigravity
  odyssey:   { harness: claude-code }
  argus:     { harness: claude-code }
  atlas:
    harness: antigravity
  cassandra: { harness: claude-code }
constraints:
  distinct_model_families: [argus, atlas]
YAML
}

manifests() { cat > "$1" <<'YAML'
athena:
  default_permissions:
    contents: write
    issues: write
    metadata: read
daedalus:
  default_permissions:
    contents: write
    issues: write
    metadata: read
odyssey:
  default_permissions:
    contents: write
    issues: write
    metadata: read
argus:
  default_permissions:
    issues: write
    metadata: read
atlas:
  default_permissions:
    issues: write
    metadata: read
cassandra:
  default_permissions:
    contents: write
    issues: write
    metadata: read
YAML
}

# A persona contract carrying only the three fields the selection reads.
persona_file() { # <dir> <name> <stages> <github_write>
    mkdir -p "$1"
    cat > "$1/$2.yaml" <<YAML
name: $2
kind: persona
stage: [$3]
authority:
  github_write: "$4"
  identity: "evekhm-$2-app[bot]"
YAML
}

persona_dir() { # <dir> — the real cast, with the real stage ownership
    local d="$1"
    persona_file "$d" athena    "plan, design"  "branch:athena/*"
    persona_file "$d" daedalus  "build"         "branch:daedalus/*"
    persona_file "$d" odyssey   "implement"     "branch:odyssey/*"
    persona_file "$d" argus     "review"        "comments"
    persona_file "$d" atlas     "review"        "comments"
    persona_file "$d" cassandra "maintain"      "branch:cassandra/*"
    cp "$REPO/personas/lifecycle.json" "$d/lifecycle.json"
}

BASE="$WORK/base"
mkdir -p "$BASE"
inline_pins "$BASE/deployments.yaml"
block_pins  "$BASE/blockform.yaml"
manifests   "$BASE/manifests.yaml"
persona_dir "$BASE/personas"

dry() { # <deployments> [extra env assignments handled by caller] -> stdout+stderr
    SMOKE_DEPLOYMENTS="$1" \
    SMOKE_APP_MANIFESTS="$BASE/manifests.yaml" \
    SMOKE_PERSONA_DIR="${PERSONAS_OVERRIDE:-$BASE/personas}" \
    DRY_RUN=1 bash "$SMOKE_SH" 125 "${@:2}" 2>&1 || true
}

# --- derivation: the control ------------------------------------------------------
out="$(dry "$BASE/deployments.yaml")"
contains "run 1 · claude-code · athena"   "$out" || fail "control: arm 1 is not athena on claude-code: $out"
contains "run 2 · antigravity · daedalus" "$out" || fail "control: arm 2 is not daedalus on antigravity: $out"
pass "inline pins yield one arm per harness, in first-appearance order"

# --- AT-2: block-form pins ---------------------------------------------------------
# Red at 3eaff89: `harness:` was read only on the persona key's own line,
# so `antigravity` disappeared, ONE arm ran and the verdict still said
# "every pinned harness launched" — a green gate reporting coverage of a
# harness it never touched, which is what D7 and D14 forbid.
out="$(dry "$BASE/blockform.yaml")"
contains "run 1 · claude-code · athena"   "$out" || fail "AT-2: block form lost the claude-code arm: $out"
contains "run 2 · antigravity · daedalus" "$out" || fail "AT-2: block form silently dropped the antigravity arm: $out"
pass "AT-2 · a block-form pin yields its arm, so the gate covers every pinned harness"

# The same pins in the two forms must derive the SAME arms. This is the
# parity assertion: one reader, agreeing with the file's other readers.
a="$(dry "$BASE/deployments.yaml")"
b="$(dry "$BASE/blockform.yaml")"
[ "${a/deployments.yaml/PINS}" = "${b/blockform.yaml/PINS}" ] \
    || fail "AT-2: inline and block form derive different arms:
$a
---
$b"
pass "AT-2 · inline and block form of the same pins derive identical arms"

# --- AT-2 (the silent half): a persona key with no readable harness ----------------
cat > "$WORK/nopin.yaml" <<'YAML'
personas:
  athena:    { harness: claude-code }
  daedalus:
    notes: no harness here
YAML
out="$(dry "$WORK/nopin.yaml")"
contains "declares daedalus under personas: with no harness" "$out" \
    || fail "AT-2: an unreadable pin was dropped instead of refused: $out"
refutes "run 1 ·" "$out" || fail "AT-2: it derived arms from a pin list it had dropped a persona from: $out"
pass "AT-2 · a persona whose harness cannot be read is exit 1 naming it, never a shorter arm list"

# --- AT-3: comment lines inside `personas:` ----------------------------------------
# Red at 3eaff89: commenting a pin out while trying another invented a
# persona named `#` pinned to a harness nobody uses, and the run refused
# with "no persona pinned to openhands ... #: its App lacks issues: write".
cat > "$WORK/commented.yaml" <<'YAML'
personas:
# was:  athena:    { harness: openhands }
  athena:    { harness: claude-code }
  daedalus:  { harness: antigravity }
  odyssey:   { harness: claude-code }
  argus:     { harness: claude-code }
  atlas:     { harness: antigravity }
  cassandra: { harness: claude-code }
YAML
out="$(dry "$WORK/commented.yaml")"
refutes "openhands" "$out" || fail "AT-3: a commented-out pin became a harness: $out"
refutes "  #:"      "$out" || fail "AT-3: a comment line became a persona: $out"
contains "run 1 · claude-code · athena"   "$out" || fail "AT-3: $out"
contains "run 2 · antigravity · daedalus" "$out" || fail "AT-3: $out"
pass "AT-3 · a comment inside personas: is not a pin and does not reorder the arms"

# --- R1-1 / AT-5: the branch surface must be `<prefix>*` ----------------------------
# Red at 3eaff89: `smoke_branch_of` stripped a TRAILING `*` only, so a
# glob without one (`branch:release`) produced `releasesmoke-125` —
# outside the surface the contract declares — and a glob whose `*` is not
# final produced a ref containing a literal `*`, which git refuses. Both
# then surfaced as `check_pushed_artifact`'s "the persona did not load, or
# the token did not authenticate": the misattributed failure this whole
# script exists to remove.
for bad_glob in "branch:release" "branch:a*/b" "branch:x*y*"; do
    d="$WORK/personas-bad-$RANDOM"
    persona_dir "$d"
    persona_file "$d" athena "plan, design" "$bad_glob"
    out="$(PERSONAS_OVERRIDE="$d" dry "$BASE/deployments.yaml")"
    refutes "· athena ·" "$out" \
        || fail "R1-1/AT-5: $bad_glob was accepted as an arm's push surface: $out"
    contains "run 1 · claude-code · odyssey" "$out" \
        || fail "R1-1/AT-5: selection did not fall through to the next qualifying persona: $out"
done
pass "R1-1/AT-5 · a glob that is not <prefix>* takes the persona out of the running"

# And when it is the LAST candidate, the refusal names that reason on its
# own line, distinct from the permission and the rung reasons, because
# the operator's fix differs: this one is an edit to personas/.
d="$WORK/personas-allbad"
persona_dir "$d"
persona_file "$d" athena    "plan, design" "branch:release"
persona_file "$d" odyssey   "implement"    "branch:a*/b"
persona_file "$d" cassandra "plan"         "branch:x*y*"
out="$(PERSONAS_OVERRIDE="$d" dry "$BASE/deployments.yaml")"
contains 'athena: its branch: write surface is "release", not <prefix>*'  "$out" || fail "R1-1/AT-5: $out"
contains 'odyssey: its branch: write surface is "a*/b", not <prefix>*'    "$out" || fail "R1-1/AT-5: $out"
contains 'cassandra: its branch: write surface is "x*y*", not <prefix>*'  "$out" || fail "R1-1/AT-5: $out"
contains "argus: its App lacks contents: write" "$out" || fail "R1-1/AT-5: the other reasons stopped being named: $out"
pass "R1-1/AT-5 · the glob shape is its own named disqualification reason"

d="$WORK/personas-ok"
persona_dir "$d"
out="$(PERSONAS_OVERRIDE="$d" dry "$BASE/deployments.yaml")"
contains "push athena/smoke-125"   "$out" || fail "R1-1/AT-5: $out"
contains "push daedalus/smoke-125" "$out" || fail "R1-1/AT-5: $out"
pass "R1-1/AT-5 · a valid glob derives a branch inside the persona's own declared surface"

# --- R1-2: the two personas/ clauses are reachable through the override -------------
# At 3eaff89 PERSONA_DIR was fixed at the repository's own tree, so the
# rung clause and the branch-surface clause could only be reached through
# whatever personas/ happened to contain — and the branch-surface clause
# was unreachable in EVERY permutation of the shipped config.
d="$WORK/personas-rungless"
persona_dir "$d"
persona_file "$d" athena   "maintain" "branch:athena/*"
persona_file "$d" odyssey  "maintain" "branch:odyssey/*"
persona_file "$d" argus    "maintain" "branch:argus/*"
persona_file "$d" cassandra "maintain" "branch:cassandra/*"
out="$(PERSONAS_OVERRIDE="$d" dry "$BASE/deployments.yaml")"
contains "it owns no stage any rung labels" "$out" \
    || fail "R1-2: the rung clause is not reachable through SMOKE_PERSONA_DIR: $out"
contains "no persona pinned to claude-code" "$out" || fail "R1-2: $out"
pass "R1-2 · SMOKE_PERSONA_DIR reaches the rung clause and the branch-surface clause"

# --- the fixture tree, for the scenarios that run past DRY_RUN ---------------------
TREE="$WORK/tree"
mkdir -p "$TREE/scripts/ops" "$TREE/scripts/auth" "$TREE/config"
cp "$SMOKE_SH" "$TREE/scripts/ops/smoke_launch.sh"
chmod +x "$TREE/scripts/ops/smoke_launch.sh"
inline_pins "$TREE/config/deployments.yaml"
manifests   "$TREE/scripts/auth/app_manifests.yaml"
persona_dir "$TREE/personas"

GHLOG="$WORK/gh.log"
WRITES="$WORK/writes.log"
LAUNCHES="$WORK/launches.log"
MINTS="$WORK/mints.log"
ISSUE_JSON="$WORK/issue.json"
export GHLOG WRITES LAUNCHES MINTS ISSUE_JSON

cat > "$TREE/scripts/auth/mint_app_token.py" <<'STUB'
#!/usr/bin/env bash
echo "mint $*" >> "$MINTS"
echo "ghs_stub_token_not_a_real_credential"
STUB
chmod +x "$TREE/scripts/auth/mint_app_token.py"

cat > "$TREE/scripts/ops/work.sh" <<'STUB'
#!/usr/bin/env bash
echo "work.sh $*" >> "$LAUNCHES"
echo "stub work.sh: a scenario launched a persona; no scenario here may" >&2
exit 1
STUB
chmod +x "$TREE/scripts/ops/work.sh"

# The stub `gh`. It answers exactly one read — the guard's issue fetch —
# from $ISSUE_JSON. EVERY other call is recorded in $WRITES and refused,
# so "the guard refused before any write" is an assertion about a file
# and not about reading the script.
cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
echo "gh $*" >> "$GHLOG"
if [ "${1:-}" = "api" ] && [ "$#" -eq 2 ] && [ -z "${2##/repos/*/issues/[0-9]*}" ]; then
    cat "$ISSUE_JSON"
    exit 0
fi
echo "gh $*" >> "$WRITES"
echo "stub gh: refusing $*" >&2
exit 1
STUB
chmod +x "$WORK/bin/gh"

for stub in claude agy; do
    printf '#!/usr/bin/env bash\necho "%s $*" >> "$LAUNCHES"\nexit 1\n' "$stub" > "$WORK/bin/$stub"
    chmod +x "$WORK/bin/$stub"
done

run_guard() { # <issue-json> -> stdout+stderr of a non-DRY_RUN invocation
    printf '%s' "$1" > "$ISSUE_JSON"
    : > "$WRITES"; : > "$LAUNCHES"; : > "$MINTS"; : > "$GHLOG"
    ( cd "$TREE" && SMOKE_PERSONA_DIR="$TREE/personas" \
        bash "$TREE/scripts/ops/smoke_launch.sh" 999 2>&1 ) || true
}

# --- R1-4: the destructive writes must earn the number -----------------------------
# Red at 3eaff89: argv accepted any run of digits and the first three
# writes — body overwrite, `in-progress` deletion, `status:*` rewrite —
# all landed before a single launch. `smoke_launch.sh 44` instead of
# `125` therefore replaced a real issue's body with the errand, released
# the only mutex this system has out from under its holder, and rewrote
# the stage label, then launched two live personas at it.
out="$(run_guard '{"body":"Repin the personas to their harnesses.","labels":[{"name":"status:build"},{"name":"intent:new"}]}')"
contains "#999 is not a scratch issue" "$out" || fail "R1-4: a labelled issue was accepted: $out"
contains "status:build"                "$out" || fail "R1-4: the refusal does not name the labels it found: $out"
[ ! -s "$WRITES" ]   || fail "R1-4: the guard wrote before refusing: $(cat "$WRITES")"
[ ! -s "$LAUNCHES" ] || fail "R1-4: the guard launched before refusing: $(cat "$LAUNCHES")"
pass "R1-4 · a labelled issue is refused, with nothing written and nothing launched"

# A fresh scratch issue carries no labels: accepted, and the proof is
# that the run gets as far as the body write (which the stub refuses).
out="$(run_guard '{"body":"","labels":[]}')"
refutes "is not a scratch issue" "$out" || fail "R1-4: a fresh unlabelled issue was refused: $out"
grep -q "issue edit" "$WRITES" || fail "R1-4: an accepted issue did not reach the body write: $(cat "$WRITES")"
pass "R1-4 · a fresh unlabelled issue is accepted"

# And so is one this script has already run against: its body carries the
# marker the script itself writes, which is why a second run is legal.
out="$(run_guard '{"body":"**SMOKE TEST — not a unit of work.** Created by scripts/ops/smoke_launch.sh","labels":[{"name":"status:planning"},{"name":"in-progress"}]}')"
refutes "is not a scratch issue" "$out" \
    || fail "R1-4: an issue carrying the errand marker was refused, so no second run is possible: $out"
grep -q "issue edit" "$WRITES" || fail "R1-4: a marked issue did not reach the body write: $(cat "$WRITES")"
pass "R1-4 · an issue carrying the errand's own marker is accepted, so re-running against it works"

echo "smoke_launch_test.sh: all $passes scenarios passed"
