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
[ -n "${!key_var:-}" ] || die "$key_var is not set in this environment"

python3 "$REPO_ROOT/scripts/auth/mint_app_token.py" "$PERSONA" --require-repo --quiet \
    || die "preflight failed for $PERSONA; nothing was dispatched"

echo "$PLACEMENT: #$NUMBER as $PERSONA (max_cost_usd $max_cost_usd)"

exec "$REPO_ROOT/scripts/ops/work.sh" "$NUMBER" --as "$PERSONA"
