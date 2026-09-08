#!/usr/bin/env bash
# The gh-actions placement adapter (#25, D11, D16, D17).
#
#   scripts/placement/gh-actions/run.sh <number> --as <persona>
#   DRY_RUN=1 scripts/placement/gh-actions/run.sh <number> --as <persona>
#
# A GitHub-hosted runner, and the placement both reviewers bind to in
# v1 (D11). Read scripts/placement/README.md first: it is the contract
# this file is checked against, and this header does not restate it.
#
# vm-local's shape with ONE difference: the App private key arrives as
# an environment variable NAMED BY the persona's authority.token (D3),
# which .github/workflows/unattended.yml sets from the Actions secret
# of the same name. This adapter reads only the NAME out of
# personas/<persona>.yaml and asserts the variable is non-empty; it
# never prints, logs, or writes the value (trusted-posting rule 2), and
# a run log that recorded the key would have published it. The
# assertion is worth its lines because the failure it catches is
# otherwise silent-then-expensive: with the secret unset the key lookup
# falls through to a local key directory that does not exist on a
# runner, and the run dies after the event has already been consumed.
#
# Model access is workload identity federation configured on the job,
# not here: no cloud key at rest (spec, placement table). Nothing in
# this file names a model, a tier or a cost literal (D8, D15).

set -euo pipefail

PLACEMENT="gh-actions"
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
#
# On this placement the point is sharper than on vm-local: nobody is
# watching. Before this line every unattended dispatch ran uncapped,
# because unattended.yml sets no WORK_MAX_USD and work.sh's ceiling is
# opt-in.
grep -qE '^[0-9]+(\.[0-9]+)?$' <<<"$max_cost_usd" \
    || die "$PERSONA has max_cost_usd '$max_cost_usd', which is not a number; refusing to dispatch a run with no ceiling"
awk -v m="$max_cost_usd" 'BEGIN { exit (m > 0) ? 0 : 1 }' \
    || die "$PERSONA has max_cost_usd $max_cost_usd; a ceiling of zero cannot authorise a run"
# An explicit WORK_MAX_USD from the caller wins, so one run can be
# raised or lowered from the command line without editing the config
# every other run reads.
export WORK_MAX_USD="${WORK_MAX_USD:-$max_cost_usd}"

# The NAME, never the value. `authority.token` is the one place the
# secret's name is written (#1, D6) and D3 forbids restating it in
# config/execution.yaml, so it is read back out of the persona source
# here.
key_var="$(sed -n '/^authority:/,/^[^[:space:]#]/p' \
    "$REPO_ROOT/personas/$PERSONA.yaml" \
    | sed -n 's/^[[:space:]][[:space:]]*token:[[:space:]]*\([A-Za-z_][A-Za-z0-9_]*\).*/\1/p' \
    | head -1)"
[ -n "$key_var" ] \
    || die "personas/$PERSONA.yaml names no authority.token, so this runner cannot be told which secret to carry"
# Indirect expansion, so the VALUE is only ever tested for emptiness and
# never assigned to anything this script can print.
#
# A missing key is normally a 1: the environment cannot start the run
# (README, "the contract"). UNSET_CREDENTIAL_IS_SKIP=1 says the caller
# has decided otherwise for this environment, and it exists for exactly
# one situation: the trigger workflow ships before a human has loaded
# the Apps' private keys as repository Actions secrets (#7). Without it,
# every pull request in the repository carries two red checks for as
# long as that step is pending, which is the failure mode `hold` and
# exit 2 already exist to avoid — a red X the room learns to ignore
# (Argus R1-1). The exit is 2, the code that already means "not worked,
# by design", so the workflow's existing map turns it into one notice
# and a green job; the line names the secret, so the skip can never be
# silent. The DECISION lives with the caller and the NAME lives here,
# where it is read from the persona source rather than assumed from a
# convention.
if [ -z "${!key_var:-}" ]; then
    if [ "${UNSET_CREDENTIAL_IS_SKIP:-0}" = "1" ]; then
        echo "$PLACEMENT: skipped #$NUMBER as $PERSONA — the repository secret $key_var is not set; load it (#7) to enable unattended runs. Nothing was dispatched."
        exit 2
    fi
    die "$key_var is not set in this environment"
fi

python3 "$REPO_ROOT/scripts/auth/mint_app_token.py" "$PERSONA" --require-repo --quiet \
    || die "preflight failed for $PERSONA; nothing was dispatched"

echo "$PLACEMENT: #$NUMBER as $PERSONA (max_cost_usd $max_cost_usd)"

exec "$REPO_ROOT/scripts/ops/work.sh" "$NUMBER" --as "$PERSONA"
