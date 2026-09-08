#!/usr/bin/env bash
# Tests for scripts/ops/execution.py (#25, intent/25-execution-model/plan.md T8).
#
#   bash scripts/ops/tests/execution_test.sh
#
# Hermetic: every scenario that needs a broken binding runs against a
# FIXTURE TREE — a temp directory carrying its own personas/, config/,
# scripts/ and .github/ — because execution.py resolves every path from
# its own location (parents[2]), which is the property that stops a run
# in one checkout validating another. No network, no token, nothing
# written outside the temp tree.
#
# Each scenario names the Decision row it pins. The last one is D17
# exactly: the SAME UNCHANGED fixture fails and then passes, with the
# only difference an adapter directory appearing beside it.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
EXEC_PY="$REPO/scripts/ops/execution.py"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }
banner() { printf '\n--- %s\n' "$*"; }

OUT=""
# run <expected-exit> <name> -- <script> <args...>
run() {
  local want="$1" name="$2" rc=0
  shift 3
  set +e
  OUT="$(python3 "$@" 2>&1)"
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

# fixture_tree -> a temp root owning its own copy of everything
# execution.py reads. personas/ and .github/ are COPIED rather than
# symlinked so a scenario can break one without touching the checkout.
fixture_tree() {
  local t
  t="$(mktemp -d "$WORK/tree.XXXX")"
  mkdir -p "$t/scripts/ops" "$t/.github/workflows"
  cp -r "$REPO/personas" "$REPO/config" "$t/"
  cp -r "$REPO/scripts/placement" "$t/scripts/"
  cp "$EXEC_PY" "$t/scripts/ops/execution.py"
  cp "$REPO/.github/workflows/unattended.yml" "$t/.github/workflows/"
  printf '%s\n' "$t"
}

# write_config <tree> <heredoc-on-stdin>
write_config() { cat > "$1/config/execution.yaml"; }

# ---------------------------------------------------------------------------
banner "D2/D19 the committed file is the one the gate passes"
run 0 "D2: --check on the repository's own config exits 0" -- "$EXEC_PY" --check
has "PASS: execution gate green" "D2: the gate says so"
has "5 binding(s)" "D19: exactly the five v1 bindings are present"

# D19's testable, asserted against the file rather than the reader: the
# entries are exactly argus, atlas, athena, daedalus, odyssey — and
# cassandra is absent, because #11 owns her cadence.
bindings="$(sed -n '/^personas:/,$p' "$REPO/config/execution.yaml" \
  | sed -n 's/^  \([a-z][a-z0-9-]*\):.*/\1/p' | sort | tr '\n' ' ')"
[ "$bindings" = "argus athena atlas daedalus odyssey " ] \
  || fail "D19: config/execution.yaml binds '$bindings', not D19's five"
pass "D19: the bindings are exactly argus athena atlas daedalus odyssey"

banner "D1 the placement axis is in its own file and nowhere else"
if grep -nE '^\s*(execution|trigger|placement):' "$REPO/config/deployments.yaml"; then
  fail "D1: deployments.yaml carries an execution-axis key; one axis, one file"
fi
pass "D1: config/deployments.yaml carries no execution, trigger or placement key"

banner "D2 --subscribers is the dispatcher's whole input, sorted"
OUT="$(python3 "$EXEC_PY" --subscribers pull_request)"
[ "$OUT" = "$(printf 'argus\tgh-actions\natlas\tgh-actions')" ] \
  || { printf '%s\n' "$OUT" >&2; fail "D2: --subscribers pull_request is not the two reviewers"; }
pass "D2: --subscribers pull_request lists argus and atlas with their placements"
OUT="$(python3 "$EXEC_PY" --subscribers issues)"
[ -z "$OUT" ] || { printf '%s\n' "$OUT" >&2; fail "D2: an unsubscribed event listed somebody"; }
pass "D2: an event nothing subscribes to lists nobody"

banner "D2 --binding is one line an adapter can report"
run 0 "D2: --binding odyssey exits 0" -- "$EXEC_PY" --binding odyssey
has "ladder vm-local" "D2: the trigger and placement are printed"
run 1 "D2: --binding on a persona with no entry exits 1" -- "$EXEC_PY" --binding cassandra
has "has no execution binding" "D2: it says why — #11 owns cassandra's cadence"

# ===========================================================================
# Everything below runs against a fixture tree.
# ===========================================================================
banner "D2 the schema rejects every shape it does not accept"
T="$(fixture_tree)"
CHECK="$T/scripts/ops/execution.py"

write_config "$T" <<'YAML'
personas:
  odyssey: { trigger: manual, placement: vm-local, max_cost_usd: 1.0 }
harnesses:
  odyssey: nonsense
YAML
run 1 "D2: an unknown top-level key exits 1" -- "$CHECK" --check
has "unknown top-level key(s) harnesses" "D2: the stray key is named"

write_config "$T" <<'YAML'
personas:
  odyssey: { trigger: manual, placement: vm-local, max_cost_usd: 1.0, model: opus }
YAML
run 1 "D2: an unknown binding key exits 1" -- "$CHECK" --check
has "unknown key(s) model" "D2: an unread key is a commitment nobody honours"

write_config "$T" <<'YAML'
personas:
  odyssey: { trigger: whenever, placement: vm-local, max_cost_usd: 1.0 }
YAML
run 1 "D2: a trigger outside the enumeration exits 1" -- "$CHECK" --check
has "which is not one of repo-event, scheduled, manual, ladder" "D2: the four shapes are named"

write_config "$T" <<'YAML'
personas:
  argus: { trigger: repo-event, placement: vm-local, max_cost_usd: 1.0 }
YAML
run 1 "D2: repo-event with no events exits 1" -- "$CHECK" --check
has "must carry a non-empty 'events' list" "D2: a repo-event binding names its events"

write_config "$T" <<'YAML'
personas:
  odyssey:
    trigger: manual
    events: [pull_request]
    placement: vm-local
    max_cost_usd: 1.0
YAML
run 1 "D2: a non-repo-event binding carrying events exits 1" -- "$CHECK" --check
has "only repo-event subscribes to an event" "D2: events belong to exactly one trigger shape"

write_config "$T" <<'YAML'
personas:
  odyssey: { trigger: manual, placement: vm-local, max_cost_usd: 0 }
YAML
run 1 "D2: max_cost_usd of zero exits 1" -- "$CHECK" --check
has "which is not a positive number" "D2: a cap of nothing is not a cap"

write_config "$T" <<'YAML'
personas:
  nobody: { trigger: manual, placement: vm-local, max_cost_usd: 1.0 }
YAML
run 1 "D2: a persona with no source exits 1" -- "$CHECK" --check
has "has no personas/nobody.yaml of kind: persona" "D2: a binding for nobody can never run"

write_config "$T" <<'YAML'
personas:
  mechanic: { trigger: manual, placement: vm-local, max_cost_usd: 1.0 }
YAML
run 1 "D2: a subagent source is not a persona" -- "$CHECK" --check
has "of kind: persona" "D2: kind is checked, not just the filename"

banner "D8 the workflow's on: block is held TO the config, not trusted"
write_config "$T" <<'YAML'
personas:
  argus:
    trigger: repo-event
    events: [pull_request, issue_comment]
    placement: gh-actions
    max_cost_usd: 1.0
YAML
run 1 "D8: an event the workflow does not capture exits 1" -- "$CHECK" --check
has "does not trigger on issue_comment" "D8: the uncaptured event is named"
# And the same file passes once the trigger list covers it — the
# duplication is a checked derivation, not a second source of truth.
sed -i '0,/^  pull_request:/s//  issue_comment:\n    types: [created]\n  pull_request:/' \
  "$T/.github/workflows/unattended.yml"
grep -q '^  issue_comment:' "$T/.github/workflows/unattended.yml" \
  || fail "D8: the fixture edit to the workflow's on: block did not take"
run 0 "D8: adding the trigger to the workflow makes the same config pass" -- "$CHECK" --check
cp "$REPO/.github/workflows/unattended.yml" "$T/.github/workflows/unattended.yml"

banner "D17 a reserved placement fails by name, and the SAME file passes once the adapter is merged"
# THE round trip. Reserving a name spells the name and nothing more: a
# binding on one must not be shippable until its directory exists.
write_config "$T" <<'YAML'
personas:
  atlas:
    trigger: repo-event
    events: [pull_request]
    placement: cloud-run-worker
    max_cost_usd: 2.00
YAML
[ ! -e "$T/scripts/placement/cloud-run-worker" ] \
  || fail "D17: the fixture already has the adapter the scenario is about to add"
run 1 "D17: placement: cloud-run-worker fails the gate today" -- "$CHECK" --check
has "persona 'atlas' names placement 'cloud-run-worker', which has no adapter directory scripts/placement/cloud-run-worker/" \
  "D17: the error names the persona, the placement and the missing directory"
config_before="$(cat "$T/config/execution.yaml")"
mkdir -p "$T/scripts/placement/cloud-run-worker"
: > "$T/scripts/placement/cloud-run-worker/run.sh"
run 0 "D17: the unchanged file passes once the adapter directory is merged" -- "$CHECK" --check
[ "$config_before" = "$(cat "$T/config/execution.yaml")" ] \
  || fail "D17: the config was edited between the two runs — that is not the round trip"
pass "D17: the config file is byte-identical across the failing and the passing run"

banner "D16/D18/D20 loop block and ladder trigger"
write_config "$T" <<'YAML'
loop:
  autonomous_merge: true
  max_rung_dispatches_per_issue: 10
  max_cost_usd_per_issue: 100.0
personas:
  atlas:
    trigger: ladder
    placement: gh-actions
    max_cost_usd: 2.00
YAML
run 0 "D16: trigger: ladder passes with no events" -- "$CHECK" --check
OUT="$(python3 "$CHECK" --loop max_rung_dispatches_per_issue)"
[ "$OUT" = "10" ] || fail "D20: --loop did not print the int value 10"
pass "D20: --loop prints values"

write_config "$T" <<'YAML'
loop:
  autonomous_merge: true
  max_rung_dispatches_per_issue: -1
  max_cost_usd_per_issue: 100.0
personas:
  atlas:
    trigger: ladder
    placement: gh-actions
    max_cost_usd: 2.00
YAML
run 1 "D20: max_rung_dispatches_per_issue must be positive integer" -- "$CHECK" --check
has "must be positive integer" "D20: error caught negative int"

write_config "$T" <<'YAML'
loop:
  autonomous_merge: true
  max_rung_dispatches_per_issue: 10
  max_cost_usd_per_issue: 100.0
personas:
  atlas:
    trigger: ladder
    events: [pull_request]
    placement: gh-actions
    max_cost_usd: 2.00
YAML
run 1 "D16: trigger: ladder rejects events" -- "$CHECK" --check
has "only repo-event subscribes to an event" "D16: trigger: ladder must not carry events"

echo
echo "execution_test.sh: all scenarios passed"
