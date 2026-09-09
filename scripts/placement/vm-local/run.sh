#!/usr/bin/env bash
# The vm-local placement adapter (#25, D16, D17, D19).
#
#   scripts/placement/vm-local/run.sh <number> --as <persona>
#   DRY_RUN=1 scripts/placement/vm-local/run.sh <number> --as <persona>
#
# The presenter's machine, and the placement four of the five v1
# bindings use. Read scripts/placement/README.md first: it is the
# contract this file is checked against, and this header does not
# restate it.
#
# Everything here is preflight and one report line. The dispatch is the
# single `work.sh` line at the bottom, `exec`'d, so this process is
# gone by the time a model is reached and the session's exit status is
# work.sh's own (0 launched or printed, 2 a stated refusal, 1 unusable
# input). No prompt, no stage, no folder, no branch, no model appears
# anywhere in this file — a flag naming any of those would let a run
# work a rung the labels say is not current (D16, #36 D7).
#
# THE APP PRIVATE KEY IS NOT NAMED HERE, not even as a path. The
# preflight below calls scripts/auth/mint_app_token.py, whose existing
# lookup resolves the key from the environment variable the persona's
# authority.token names, else the operator's local key directory — so
# this file contains no file path and no home directory, and the
# sanitize gate's `home` rule passes with no allowlist entry (D3).
# The token the launched session posts with is minted by work.sh in the
# one step between the last refusal and the launch (`ops.identity`,
# #43); this adapter mints none and exports none. `--quiet` means the
# preflight's own token never reaches a shell variable either.

set -euo pipefail

PLACEMENT="vm-local"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

die() { echo "$PLACEMENT: $*" >&2; exit 1; }

NUMBER=""
PERSONA=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --as)
            [ "$#" -ge 2 ] || die "--as needs a persona name"
            PERSONA="$2"; shift 2 ;;
        --as=*) PERSONA="${1#--as=}"; shift ;;
        -*) die "unknown flag '$1'; the adapter takes <number> --as <persona> and nothing else" ;;
        *)
            [ -z "$NUMBER" ] || die "one number is one run; got '$NUMBER' and '$1'"
            NUMBER="${1#\#}"; shift ;;
    esac
done
[ -n "$NUMBER" ] || die "usage: run.sh <number> --as <persona>"
case "$NUMBER" in
    ''|*[!0-9]*) die "'$NUMBER' is not an issue or pull-request number" ;;
esac
[ -n "$PERSONA" ] || die "usage: run.sh <number> --as <persona>"

if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
    echo "$PLACEMENT: delegating #$NUMBER execution to operator VM poller"
    exit 0
fi

# The binding, from the ONE reader (D2). An adapter that parsed the
# YAML itself would be a second schema.
binding="$(python3 "$REPO_ROOT/scripts/ops/execution.py" --binding "$PERSONA")" \
    || die "$PERSONA has no execution binding in config/execution.yaml"
max_cost_usd="$(awk '{print $3}' <<<"$binding")"

# The declared budget becomes the enforced ceiling here (#108). This is
# the gap docs/SPEC.md named in its own words: "the remaining gap is
# that nothing yet carries `max_cost_usd` from this file into that
# ceiling". The adapter is where the carry belongs. work.sh stays blind
# to config/execution.yaml so that a launch is described by its flags
# and not by a file it reads behind the caller's back, and D2 keeps
# execution.py the single parser of that file.
#
# Fail-closed, and the reason is specific. execution.py --check already
# refuses a binding whose max_cost_usd is not a positive number, but
# --check runs in CI and this runs at launch. If a binding ever reached
# here unreadable, the export below would set WORK_MAX_USD to the empty
# string, and work.sh reads empty as "no ceiling" — a parse failure
# would silently buy an unlimited run. Re-testing the value here is
# what makes that impossible; the rule is the same one work.sh applies
# to the variable it receives.
grep -qE '^[0-9]+(\.[0-9]+)?$' <<<"$max_cost_usd" \
    || die "$PERSONA has max_cost_usd '$max_cost_usd', which is not a number; refusing to dispatch a run with no ceiling"
awk -v m="$max_cost_usd" 'BEGIN { exit (m > 0) ? 0 : 1 }' \
    || die "$PERSONA has max_cost_usd $max_cost_usd; a ceiling of zero cannot authorise a run"
# An explicit WORK_MAX_USD from the caller wins, so one run can be
# raised or lowered from the command line without editing the config
# every other run reads.
export WORK_MAX_USD="${WORK_MAX_USD:-$max_cost_usd}"

# D4's preflight, inside the only credential path so no adapter can
# forget it. Non-zero here is a 1: the environment cannot start the
# run, which is not a decision about the number (D8's 2 keeps meaning
# "not worked, by design").
python3 "$REPO_ROOT/scripts/auth/mint_app_token.py" "$PERSONA" --require-repo --quiet \
    || die "preflight failed for $PERSONA; nothing was dispatched"

echo "$PLACEMENT: #$NUMBER as $PERSONA (max_cost_usd $max_cost_usd)"

exec "$REPO_ROOT/scripts/ops/work.sh" "$NUMBER" --as "$PERSONA"
