#!/usr/bin/env bash
# One measured launch per harness, against a live scratch issue
# (#43, intent/43-harness-agnostic-launch/spec.md D18, D19).
#
#   scripts/ops/smoke_launch.sh <scratch-issue> [persona ...]
#
# work_test.sh proves the launcher's LOGIC against stubs. Nothing a stub
# says can prove that a harness actually loads the compiled target, that
# a minted App token actually authenticates a push, or that the
# `WORK-RESULT:` line actually survives a real harness's JSON. That is
# what this script is for: one real session per harness, three named
# observables each, so a failure says WHICH one broke rather than "the
# smoke failed".
#
# NO PERSONA NAME IS WRITTEN IN THIS FILE (#44, spec D7). Which harnesses
# run and which persona runs each are DERIVED from config, so flipping a
# pin changes what this gate covers with no edit here:
#
#   the harnesses  every distinct `personas.*.harness` value in
#                  config/deployments.yaml, in first-appearance order
#   the arm for a  the FIRST persona, in that file's own declaration
#   harness        order, pinned to that harness whose App in
#                  scripts/auth/app_manifests.yaml grants every
#                  permission this arm's observables need — `issues:
#                  write` to comment, `contents: write` to push — and
#                  which owns a stage that some rung of
#                  personas/lifecycle.json labels, since `work.sh --as`
#                  refuses a persona that does not own the current stage,
#                  and whose own contract declares a branch surface of
#                  the form `branch:<prefix>*` to push on
#   its relabel    the label of such a rung, from the same join
#   housekeeping   the first persona in declaration order granting both
#                  permissions, any harness: writing the issue body,
#                  relabelling and reading comments makes no model call
#
# A harness with NO qualifying persona is exit 1 naming the harness and
# what is missing — never a skipped arm, and never exit 0 having covered
# some other harness twice (#44, spec D14). That is the whole of the
# tolerate mechanism: an observable an arm's persona cannot produce is
# rejected at selection, not excused at assertion time. The verdict's
# tolerated count stays and now prints 0.
#
# Identity is NEVER checked with `gh api user`: an App token has no user
# and gets 403 (findings Q7). The token-side check is
# `GET /installation/repositories`; the outcome-side check is who
# authored the comment and the pushed commit, compared against the
# persona's own `authority.identity`.
#
# Environment (argv stays closed to everything but the arms, as in
# work.sh):
#   DRY_RUN=1              resolve and print the arms, launch nothing,
#                          mint nothing, write nothing.
#   SMOKE_DEPLOYMENTS      read the pins from another file, so a scratch
#                          copy with one pin flipped proves the arms
#                          follow config and not this script.
#   SMOKE_APP_MANIFESTS    read the App permissions from another file,
#                          so a scratch copy proves the exit-1 branch.
#   SMOKE_PERSONA_DIR      read the contracts (and lifecycle.json) from
#                          another directory, so the two selection
#                          clauses that read `personas/` — the rung and
#                          the branch surface — are reachable in a test
#                          instead of only through whatever the real
#                          tree happens to contain.
#
# The issue must be a SCRATCH issue: this script's first writes overwrite
# the body, delete `in-progress` (the only mutex this system has) and
# rewrite the stage label, so pointing it at a real unit of work
# corrupts tracker state before anything is launched.
#
# ONE fact earns those writes and nothing else does: the body already
# carries this script's own marker, `SMOKE TEST — not a unit of work.`
# — written there by a previous run of this script, or typed by the
# operator into the body of the fresh issue they open for the purpose:
#
#   gh issue create --repo <repo> --title 'smoke fixture' \
#       --body 'SMOKE TEST — not a unit of work.'
#
# That is the opt-in, and it is deliberately a fact ON THE ISSUE rather
# than a flag in the invoking shell: the next reader of the tracker can
# see which numbers this script is allowed to destroy, and a number
# nobody opted in cannot be opted in by a hurried command line. Absence
# of labels is NOT an opt-in — a freshly filed, untriaged issue carries
# none and is somebody's unit of work from the moment it is opened.
#
# A PULL REQUEST is refused outright, before anything else is looked at:
# `/repos/{owner}/{repo}/issues/{n}` serves pull requests too, `gh issue
# edit` resolves a pull-request number without a warning, and a pull
# request's body is exactly the kind of record — the review ledger, the
# acceptance table — whose loss this guard exists to prevent. The check
# is first because a pull request whose body QUOTES the marker (a review
# comment, a ledger row, this paragraph) would otherwise pass it.
#
# See `scratch_refusal`.
#
# Trailing arguments name the arms explicitly: each persona binds to the
# harness ITS OWN pin names and replaces that harness's derived arm. A
# name that is not a persona, two names resolving to one harness, or a
# name whose App or rung does not qualify is exit 1 — the override picks
# a different arm, it does not switch the selection rule off.
#
# Exit 0 = every required observable held. Exit 1 = one did not, or the
# inputs were unusable.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GITHUB_REPO="${GITHUB_REPO:-evekhm/agentic-sdlc}"
PUSH_URL="https://github.com/$GITHUB_REPO.git"
DRY_RUN="${DRY_RUN:-0}"

DEPLOYMENTS="${SMOKE_DEPLOYMENTS:-$REPO_ROOT/config/deployments.yaml}"
APP_MANIFESTS="${SMOKE_APP_MANIFESTS:-$REPO_ROOT/scripts/auth/app_manifests.yaml}"
PERSONA_DIR="${SMOKE_PERSONA_DIR:-$REPO_ROOT/personas}"
LIFECYCLE_JSON="$PERSONA_DIR/lifecycle.json"

ISSUE="${1:-}"
case "$ISSUE" in
    ''|*[!0-9]*)
        echo "usage: scripts/ops/smoke_launch.sh <scratch-issue> [persona ...]" >&2
        exit 1 ;;
esac
shift
OVERRIDES=("$@")

# `runs/` is ONE directory per machine — the primary checkout's — and
# not whatever worktree this run started from (AGENTS.md, "Outputs go in
# timestamped run folders"). It is gitignored, so a run folder written
# inside a worktree never travels with the branch and dies with the
# worktree; every session in every harness resolves the root this way
# before writing. The launched persona therefore puts its artifact
# there, and this observable has to read the same place: looking under
# $REPO_ROOT instead reports "left no artifact" for a file that exists,
# which is a false negative for every session working the way this
# repository tells sessions to work.
git_common_dir="$(git -C "$REPO_ROOT" rev-parse --git-common-dir 2>/dev/null || echo '')"
case "$git_common_dir" in
    '')  RUNS_ROOT="$REPO_ROOT/runs" ;;
    /*)  RUNS_ROOT="$(cd "$git_common_dir/.." && pwd)/runs" ;;
    *)   RUNS_ROOT="$(cd "$REPO_ROOT/$git_common_dir/.." && pwd)/runs" ;;
esac
SMOKE_DIR="$RUNS_ROOT/smoke-$ISSUE"

failures=0
blocked=0
ok()      { echo "  ok       $*"; }
bad()     { echo "  FAILED   $*"; failures=$((failures + 1)); }
note()    { echo "  note     $*"; }
banner()  { echo; echo "=== $*"; }
die()     { echo "smoke_launch: $*" >&2; exit 1; }

# --- reading the config the arms are derived from -------------------------------
# ONE parse of the pins for this whole script. It is a shell reader of a
# YAML subset, not a YAML parser, so the claim it makes is bounded and
# measured rather than universal: on the forms this repository's schema
# actually uses — the inline `{ harness: x }` form, the two-line block
# form, comment lines, and extra keys inside a persona's own mapping —
# it agrees with the repository's other two readers,
# `scripts/sync_agents.py`'s `yaml.safe_load` and `scripts/ops/work.sh`'s
# `harness_of`. Outside that set it must fail CLOSED, never quietly
# differently, and one input is known to sit outside it: a quoted scalar
# (`harness: "claude-code"`) is not unquoted here, and is not unquoted by
# `work.sh harness_of` either — so the two shell readers agree with each
# other, both diverge from `yaml.safe_load`, and the divergence is exit 1
# ("with no harness this script can read") rather than a wrong arm
# (Argus R2-15). Unquoting here alone would be worse than the refusal: it
# would derive an arm that the launcher then cannot resolve.
#
# The first version of this function read
# `harness:` only when it sat on the SAME line as the persona key, so a
# pin written in the block form
#
#   daedalus:
#     harness: antigravity
#
# — valid YAML, the form work.sh goes out of its way to support, and the
# operator's routine edit (#44, D1) — vanished. The gate then ran ONE arm
# and printed "every pinned harness launched": a green gate reporting
# coverage of a harness it never touched, which is the exact silent
# success D7 and D14 exist to forbid. Three properties are load-bearing
# and each has a scenario in `scripts/ops/tests/smoke_launch_test.sh`:
#
#   both forms   inline `{ harness: x }` and the two-line block form.
#   comments     a line whose first non-blank character is `#` is never
#                a pin. Commenting a pin out while trying another used
#                to invent a persona named `#` on a harness nobody
#                pinned, and could reorder the arms.
#   indentation  a persona key is a line at the FIRST indent seen inside
#                `personas:`; anything deeper is that persona's own
#                mapping, so a block-form persona carrying keys besides
#                `harness:` does not turn one of them into a persona.
#   depth        within a persona's own mapping, `harness:` counts only
#                at that mapping's OWN indent — the first indent seen
#                inside it — never deeper. Taking the first `harness:` at
#                any depth read a `harness:` nested inside some other key
#                of the persona (`overrides: { harness: … }`) as the
#                persona's pin, and that is the one divergence from
#                `yaml.safe_load` that failed OPEN: a third arm on a
#                harness nobody pinned, silently (Atlas AT-R2-11, Argus
#                R2-15). A persona whose only `harness:` is nested now
#                yields `-` and is exit 1 naming it, like every other pin
#                this reader cannot read.
#
# A persona key whose harness cannot be read prints `-` rather than
# disappearing, and the startup check below turns that into exit 1
# naming the persona. Dropping a pin silently is the failure mode; the
# whole point is that this reader cannot do it quietly.
pins() { # -> "<persona> <harness>", declaration order; harness `-` if unreadable
    awk '
        /^[[:space:]]*(#|$)/ { next }
        { ind = match($0, /[^[:space:]]/) - 1 }
        $1 == "personas:" && ind == 0 { inside = 1; keyind = -1; subind = -1; pend = ""; next }
        ind == 0 { if (pend != "") { print pend, "-"; pend = "" } inside = 0 }
        !inside { next }
        keyind < 0 && $1 ~ /:$/ { keyind = ind }
        ind > keyind && pend != "" {
            if (subind < 0) subind = ind
            if (ind == subind && $1 == "harness:") {
                v = $2; gsub(/[,}]/, "", v)
                print pend, (v == "" ? "-" : v); pend = ""
            }
            next
        }
        ind > keyind { next }
        $1 ~ /:$/ {
            if (pend != "") print pend, "-"
            n = $1; sub(/:$/, "", n); pend = n; subind = -1
            for (k = 2; k <= NF; k++)
                if ($k == "harness:") {
                    v = $(k + 1); gsub(/[,}]/, "", v)
                    print n, (v == "" ? "-" : v); pend = ""; next
                }
        }
        END { if (pend != "") print pend, "-" }
    ' "$DEPLOYMENTS"
}

harness_of() { # <persona> -> its pinned harness, or empty
    pins | awk -v want="$1" '$1 == want { print $2; exit }'
}

# The App permission block, read from the manifest source. `contents`
# and `pull_requests` vary per persona (reviewers are comment-only and
# never push), which is exactly what makes the selection a real test.
grant_of() { # <persona> <permission> -> the granted value, or empty
    awk -v want="$1" -v key="$2" '
        /^[a-z][a-z0-9_-]*:[[:space:]]*$/ {
            p = $1; sub(/:$/, "", p); inperm = 0; next
        }
        /^  default_permissions:[[:space:]]*$/ { inperm = 1; next }
        /^  [^ ]/ { inperm = 0 }
        inperm && p == want && $1 == key ":" { print $2; exit }
    ' "$APP_MANIFESTS"
}

# The label of a rung this persona owns. `work.sh --as` refuses a persona
# that does not own the stage the labels say is current (refusal (f)), so
# a relabel target that is not derived from the same join is a refusal
# waiting to happen. A persona all of whose stages are rungless — the
# stage-enum values lifecycle.json records as "absent by construction" —
# yields nothing here and can never be an arm.
relabel_of() { # <persona> -> the status:* label to put on the scratch issue, or empty
    local persona="$1" file stages stage label
    file="$PERSONA_DIR/$persona.yaml"
    [ -f "$file" ] || return 0
    stages="$(awk '$1 == "stage:" { gsub(/[][,]/, " "); $1 = ""; print }' "$file")"
    for stage in $stages; do
        label="$(jq -r --arg s "$stage" \
            '.stages[] | select(.stage == $s) | .label' "$LIFECYCLE_JSON")"
        [ -n "$label" ] && { printf '%s\n' "$label"; return 0; }
    done
    return 0
}

identity_of() { # <persona> -> the App login it acts as, or empty
    local file="$PERSONA_DIR/$1.yaml"
    [ -f "$file" ] || return 0
    sed -n 's/^[[:space:]]*identity:[[:space:]]*"\(.*\)".*/\1/p' "$file" | head -1
}

# The branch surface the persona's OWN contract declares, as
# `authority.github_write: "branch:<glob>"`. The push observable used a
# name of this script's invention, `smoke/<issue>-<persona>`, which is
# outside every persona's glob — so an arm that reads its contract and
# refuses is doing exactly what the contract says, and the gate recorded
# that correct refusal as "the persona did not load". The branch is
# derived from the glob instead: its `*` replaced by `smoke-<issue>`.
# A persona that declares no write surface cannot push at all and is
# therefore not an arm — same rule, one more input.
branch_glob_of() { # <persona> -> the glob after `branch:`, or empty
    local file="$PERSONA_DIR/$1.yaml"
    [ -f "$file" ] || return 0
    sed -n 's/^[[:space:]]*github_write:[[:space:]]*"branch:\(.*\)".*/\1/p' "$file" | head -1
}

# The branch name is `${glob%\*}smoke-$ISSUE`, which is only inside the
# glob when the glob is `<prefix>*` — one `*`, and it is the last
# character. That shape is ALSO what the errand's own wording produces
# ("that glob with `smoke-$ISSUE` in place of its `*`"), so constraining
# the input here is what makes the two derivations one: the gate and the
# arm cannot compute different branches, because a glob on which they
# would differ is not an arm.
#
# The shapes that used to slip through, both of them a false negative
# rather than an honest refusal: `branch:release` (no `*`) asks the arm
# to push `releasesmoke-125`, outside the surface its contract declares,
# so a persona that reads its contract correctly refuses and the gate
# records that as `check_pushed_artifact`'s "the persona did not load, or
# the token did not authenticate" — the exact misattribution this script
# exists to remove; `branch:a*/b` yields a ref containing a literal `*`,
# which git refuses, reported the same wrong way.
branch_glob_ok() { # <glob> -> 0 if exactly one `*` and it is last
    case "$1" in
        '')       return 1 ;;
        *'*'*'*') return 1 ;;
        *'*')     return 0 ;;
        *)        return 1 ;;
    esac
}

smoke_branch_of() { # <persona> -> the branch its own authority admits, or empty
    local glob
    glob="$(branch_glob_of "$1")"
    branch_glob_ok "$glob" || return 0
    printf '%s\n' "${glob%\*}smoke-$ISSUE"
}

# Why this persona cannot be an arm, or empty if it can. Each half is
# named rather than collapsed into "does not qualify", because the
# operator's fix differs: a permission is granted on github.com, a rung
# is given by #11 or #25, a write surface is declared in personas/.
disqualifies() { # <persona> -> the reason, or empty
    local glob
    [ "$(grant_of "$1" issues)"   = write ] || { echo "its App lacks issues: write";   return 0; }
    [ "$(grant_of "$1" contents)" = write ] || { echo "its App lacks contents: write"; return 0; }
    [ -n "$(relabel_of "$1")" ]             || { echo "it owns no stage any rung labels"; return 0; }
    glob="$(branch_glob_of "$1")"
    [ -n "$glob" ] || { echo "its contract declares no branch: write surface"; return 0; }
    branch_glob_ok "$glob" \
        || { echo "its branch: write surface is \"$glob\", not <prefix>* — no smoke branch is inside it"; return 0; }
    return 0
}

arm_for() { # <harness> -> the selected persona; exits 1 naming the harness if none
    local harness="$1" persona why reasons=""
    while read -r persona _; do
        [ "$(harness_of "$persona")" = "$harness" ] || continue
        why="$(disqualifies "$persona")"
        [ -z "$why" ] && { printf '%s\n' "$persona"; return 0; }
        reasons="$reasons
  $persona: $why"
    done < <(pins)
    [ -n "$reasons" ] || reasons="
  (no persona is pinned to it at all)"
    echo "smoke_launch: no persona pinned to $harness can produce this arm's observables.$reasons" >&2
    echo "smoke_launch: an arm needs issues: write to comment, contents: write and a declared branch surface to push, plus a stage some rung labels; $harness has no such persona, so the run fails rather than skipping it or covering another harness twice." >&2
    exit 1
}

# --- the derivation ---------------------------------------------------------------
command -v jq >/dev/null || die "jq is not on PATH; the arms cannot be derived without it"
[ -r "$DEPLOYMENTS" ]   || die "$DEPLOYMENTS is not readable"
[ -r "$APP_MANIFESTS" ] || die "$APP_MANIFESTS is not readable"

# Every persona declared under `personas:` must yield a harness. A key
# this reader cannot resolve is exit 1 naming it, never a shorter arm
# list: a dropped pin is the one failure that would let this gate report
# coverage of a harness it did not touch (#44, D7, D14).
unreadable=""
while read -r persona harness; do
    [ "$harness" = "-" ] && unreadable="$unreadable $persona"
done < <(pins)
[ -z "$unreadable" ] || die "$DEPLOYMENTS declares$unreadable under personas: with no harness this script can read; the arms cannot be derived from a pin list it drops"

HARNESSES=()
while read -r harness; do HARNESSES+=("$harness"); done < <(pins | awk '!seen[$2]++ { print $2 }')
[ "${#HARNESSES[@]}" -gt 0 ] || die "$DEPLOYMENTS pins no persona to any harness"

# Trailing arguments override the derived arm for the harness their own
# pin names. Validated before anything is written: an unusable override
# discovered after the issue was relabelled is the failure the preflight
# below exists to prevent.
declare -A OVERRIDE_ARM=()
for persona in ${OVERRIDES+"${OVERRIDES[@]}"}; do
    harness="$(harness_of "$persona")"
    [ -n "$harness" ] || die "$persona is not a persona pinned in $DEPLOYMENTS"
    [ -z "${OVERRIDE_ARM[$harness]:-}" ] \
        || die "$persona and ${OVERRIDE_ARM[$harness]} both resolve to $harness; one arm per harness"
    why="$(disqualifies "$persona")"
    [ -z "$why" ] || die "$persona cannot be the $harness arm: $why"
    OVERRIDE_ARM[$harness]="$persona"
done

ARMS=()
for harness in "${HARNESSES[@]}"; do
    if [ -n "${OVERRIDE_ARM[$harness]:-}" ]; then
        ARMS+=("$harness ${OVERRIDE_ARM[$harness]}")
    else
        # `|| exit 1` and not `set -e`: arm_for's exit 1 ends the command
        # substitution's subshell, so without this the run would carry on
        # with an empty arm — the silent success D14 forbids.
        persona="$(arm_for "$harness")" || exit 1
        ARMS+=("$harness $persona")
    fi
done

HOUSEKEEPER=""
while read -r persona _; do
    [ "$(grant_of "$persona" issues)"   = write ] || continue
    [ "$(grant_of "$persona" contents)" = write ] || continue
    HOUSEKEEPER="$persona"; break
done < <(pins)
[ -n "$HOUSEKEEPER" ] \
    || die "no persona's App grants both issues: write and contents: write, so the run has no housekeeping identity"

banner "derived from $(basename "$DEPLOYMENTS") + $(basename "$APP_MANIFESTS")"
n=0
for arm in "${ARMS[@]}"; do
    n=$((n + 1))
    set -- $arm
    note "run $n · $1 · $2 · relabel $(relabel_of "$2") · push $(smoke_branch_of "$2") · as $(identity_of "$2")"
done
note "housekeeping identity: $HOUSEKEEPER ($(identity_of "$HOUSEKEEPER"))"

if [ "$DRY_RUN" = "1" ]; then
    echo
    echo "smoke_launch: DRY_RUN=1 — arms resolved above; nothing launched, minted or written."
    exit 0
fi

# --- identity, in-band ----------------------------------------------------------
# This script used to shell out to `ghp`, a wrapper that exists only in
# its author's ~/.local/bin and is named nowhere in this repository. The
# one artifact in #43 whose entire purpose is reproducibility was the one
# nobody else could run: it would have died on the first observable with
# `ghp: command not found`, having already relabelled the scratch issue.
# It now mints exactly the way work.sh does, from this checkout's own
# copy of mint_app_token.py, and calls plain `gh`.
#
# The token never reaches argv, a file or a log: it is a shell variable
# and an assignment prefix on the single `gh` call that needs it. Minted
# once per persona and reused, because a smoke run makes a dozen reads
# and an installation token is good for an hour.
MINT="$REPO_ROOT/scripts/auth/mint_app_token.py"
declare -A SMOKE_TOKENS=()
gh_as() { # <persona> <gh args...> — one gh call as that persona's App
    local persona="$1"; shift
    if [ -z "${SMOKE_TOKENS[$persona]:-}" ]; then
        SMOKE_TOKENS[$persona]="$("$MINT" "$persona")" || {
            echo "smoke_launch: cannot mint an App token for $persona" >&2
            return 1
        }
    fi
    GH_TOKEN="${SMOKE_TOKENS[$persona]}" GITHUB_TOKEN="${SMOKE_TOKENS[$persona]}" \
        gh "$@"
}

# --- preflight --------------------------------------------------------------------
# Name every missing prerequisite up front, all of them in one pass.
# Discovering one at the third observable — with the scratch issue
# already relabelled and a live persona launch already spent — is how a
# smoke test becomes worse than no smoke test.
prereq_missing=0
for cmd in gh jq claude agy; do
    command -v "$cmd" >/dev/null || {
        echo "smoke_launch: $cmd is not on PATH; smoking both harnesses needs both installed" >&2
        prereq_missing=1
    }
done
for prog in "$MINT" "$REPO_ROOT/scripts/ops/work.sh"; do
    [ -x "$prog" ] || {
        echo "smoke_launch: $prog is missing or not executable" >&2
        prereq_missing=1
    }
done
[ "$prereq_missing" -eq 0 ] || exit 1

# --- the scratch-issue guard ----------------------------------------------------
# Argv accepts any run of digits, and this script's first three writes are
# destructive and land before a single arm is launched: it overwrites the
# issue BODY with the errand, deletes `in-progress` — the only mutex this
# system has (AGENTS.md, "Working the tracker") — and strips every
# `status:*` label to put its own on. `scripts/ops/smoke_launch.sh 44`
# instead of `125` therefore replaces a real issue's body with "SMOKE TEST
# — not a unit of work", releases the mutex out from under whoever holds
# it, rewrites the stage, and launches two live personas against it. That
# is tracker-state corruption plus a released mutex, which is how two
# sessions end up on one issue.
#
# So the number has to earn the writes, and exactly one fact earns them:
# the body already carries this script's own marker. That covers both
# legitimate uses with one rule — an issue this script has run against
# before carries the marker because this script wrote it, and a fresh
# fixture carries it because the operator typed it when opening the
# issue. It is an explicit, visible OPT-IN, which "carries no labels"
# never was: a freshly filed issue nobody has triaged yet has no labels
# and is somebody's unit of work from the moment it is opened, so the
# old acceptance admitted every untriaged number in the tracker (Argus
# R2-2, Atlas AT-R2-5, closing R1-4's third shape).
#
# Refusing a pull request is a SEPARATE and EARLIER condition, not a
# consequence of the marker rule. `/repos/{o}/{r}/issues/{n}` serves
# pull requests as well as issues, `gh issue edit` resolves a
# pull-request number silently, and every pull request in this
# repository carries zero labels — so under the old rule
# `smoke_launch.sh <this PR's number>` passed the guard and the first
# write replaced the pull request's body. It is checked FIRST because a
# pull request's body is precisely where the marker is likely to be
# quoted: a review ledger row, a finding, or a paragraph like this one.
SCRATCH_MARKER='SMOKE TEST — not a unit of work.'

scratch_refusal() { # <is-pull-request: 1|0> <labels, one per line> <body> -> the reason, or empty
    local is_pr="$1" labels="$2" body="$3" found
    if [ "$is_pr" = "1" ]; then
        echo "it is a PULL REQUEST, not an issue — the issues endpoint serves both and \`gh issue edit\` resolves a pull-request number, so this would have overwritten the pull request's own body"
        return 0
    fi
    case "$body" in
        *"$SCRATCH_MARKER"*) return 0 ;;
    esac
    found="$(printf '%s\n' "$labels" | sed '/^$/d' | tr '\n' ' ' | sed 's/ $//')"
    if [ -n "$found" ]; then
        echo "it carries labels ($found) and its body has no \"$SCRATCH_MARKER\" marker, so it is a unit of work, not a fixture"
    else
        echo "its body has no \"$SCRATCH_MARKER\" marker, so nothing on it opts it in; carrying no labels is not an opt-in, because a freshly filed issue nobody has triaged yet carries none either"
    fi
}

require_scratch_issue() {
    local json is_pr labels body why
    json="$(gh_as "$HOUSEKEEPER" api "/repos/$GITHUB_REPO/issues/$ISSUE")" \
        || die "cannot read #$ISSUE to check that it is a scratch issue; nothing was written"
    is_pr="$(printf '%s' "$json" | jq -r 'if .pull_request then "1" else "0" end')"
    labels="$(printf '%s' "$json" | jq -r '.labels[].name')"
    body="$(printf '%s' "$json" | jq -r '.body // ""')"
    why="$(scratch_refusal "$is_pr" "$labels" "$body")"
    [ -z "$why" ] || die "#$ISSUE is not a scratch issue: $why. Pass an issue this script has run against before, or open a fresh one that opts in — \`gh issue create --repo $GITHUB_REPO --title 'smoke fixture' --body '$SCRATCH_MARKER'\`. Nothing was written."
}

# No bypass variable: a guard with an off switch is the guard the hurried
# operator turns off, and the one accepted shape already covers every
# legitimate use — the opt-in is a line in the issue body, which costs
# the operator the same keystrokes and leaves the decision on the record.
require_scratch_issue

# --- the instruction every arm will read ----------------------------------------
# Written into the issue body rather than into the prompt: work.sh has
# exactly one prompt literal for both harnesses (#43 D6), and a smoke
# test that needed a second one would be testing something work.sh does
# not do. ONE errand for every arm, keyed on the reader's own persona
# rather than branching per name: which personas read it is a fact of
# the pins, so a branch per name would be a hardcoded arm in the one
# place the arms are supposed to be derived (#44 D7). It is also why
# every arm now produces all three observables — which arm pushed and
# which arm only commented used to be a property of the order they ran
# in, and that is not a config fact.
#
# The first line carries $SCRATCH_MARKER because the guard above reads it
# back: the marker is what makes a second run against the same scratch
# issue legal, and writing it from the same variable is what keeps the
# guard and the errand from drifting into disagreement.
body="$(cat <<BODY
**$SCRATCH_MARKER** Created by
\`scripts/ops/smoke_launch.sh\` for #43 (spec D19) and #44 (spec D7). Do
the errand below and nothing else: do not open a pull request, do not
modify a tracked file on this branch, do not touch any other issue.

Throughout, **YOU** is your own persona name — the agent you were
launched as — and **YOUR LOGIN** is the App login your persona
instructions give under *Acts as GitHub identity*. The errand is the
same for every persona; nothing in it is keyed to a particular one.

Write one line naming your persona, your harness and the UTC time. Call
it **THE LINE**, and deliver it three times:

1. Create \`smoke-$ISSUE/YOU.md\` under the shared run root containing
   THE LINE. The run root is the PRIMARY checkout's \`runs/\`, never this
   worktree's — AGENTS.md, *Outputs go in timestamped run folders*:
   \`RUNS_ROOT="\$(cd "\$(git rev-parse --git-common-dir)/.." && pwd)/runs"\`.
2. Post THE LINE as a comment on this issue, using
   \`gh issue comment $ISSUE --repo $GITHUB_REPO --body-file <a file>\`.
   Your \`GH_TOKEN\` is already your own App's; plain \`gh\` posts as you.
3. Push THE LINE as a commit on **YOUR BRANCH**, which is the branch
   YOUR OWN contract already admits and not a name this errand invented:
   \`personas/YOU.yaml\` declares \`authority.github_write\` as
   \`branch:<glob>\`, and YOUR BRANCH is that glob with \`smoke-$ISSUE\`
   in place of its \`*\` — so for a glob \`YOU/*\` it is
   \`YOU/smoke-$ISSUE\`. Push nothing outside your glob; if the errand
   ever seems to ask you to, your contract wins and this step is what is
   wrong. Do it WITHOUT changing the branch this worktree is on:
   \`\`\`
   git worktree add -b YOUR-BRANCH /tmp/smoke-$ISSUE-YOU HEAD
   # write /tmp/smoke-$ISSUE-YOU/SMOKE-$ISSUE.md containing THE LINE
   git -C /tmp/smoke-$ISSUE-YOU add SMOKE-$ISSUE.md
   git -C /tmp/smoke-$ISSUE-YOU \\
       -c user.name='YOUR LOGIN' \\
       -c user.email='YOUR LOGIN@users.noreply.github.com' \\
       commit -m 'smoke: YOU launched by work.sh (#$ISSUE)'
   git -C /tmp/smoke-$ISSUE-YOU push $PUSH_URL YOUR-BRANCH
   \`\`\`
   Your git is already configured with a credential helper that mints
   your App token, so the push needs no token from you.

Then print \`WORK-RESULT: ok #$ISSUE smoke launch completed\`.

Claiming this issue is not part of the errand. Neither is dispatching:
you are ALREADY the session \`scripts/ops/work.sh\` launched for this
issue, so running \`scripts/ops/work.sh\` (or any other launcher) here
launches a copy of yourself on the issue you are already working, and
that copy does the same. Do not run it. (This paragraph is prose, and
prose is not a restraint: the launcher-side refusal that would actually
stop it is tracked on #134.)
BODY
)"

printf '%s\n' "$body" > "/tmp/smoke-$ISSUE-body.md"
gh_as "$HOUSEKEEPER" issue edit "$ISSUE" --repo "$GITHUB_REPO" \
    --body-file "/tmp/smoke-$ISSUE-body.md" >/dev/null \
    || { echo "smoke_launch: cannot write the scratch issue body" >&2; exit 1; }

# --- shared checks -------------------------------------------------------------

# The token-side identity check. `gh api user` is 403 for an App token
# and would prove nothing either way; this endpoint is what an
# installation token IS for.
check_token() { # <persona>
    local persona="$1" n
    if n="$(gh_as "$persona" api /installation/repositories --jq '.total_count' 2>/dev/null)"; then
        ok "$persona's App token authenticates ($n repository/ies in the installation)"
    else
        bad "$persona's App token could not read /installation/repositories"
    fi
}

# The clock the comment observable is measured against. A scratch issue
# is reused run after run, so "is there a comment by this persona" is
# always true after the first run and proves nothing; only "is there one
# created after this arm was launched" does.
#
# It is a TIMESTAMP and not a count on purpose. Counting was the obvious
# reading and it is wrong: `/issues/N/comments` paginates at 30 by
# default, so once a scratch issue passes thirty comments the count
# freezes at 30 and `.[-1]` names the thirtieth-oldest author. Both
# assertions then fail on arms that did comment — a green run reported
# red, naming the wrong persona. `since` plus an explicit `per_page` and
# `--paginate` reads the whole thread; `select(.created_at > ...)` is
# because `since` filters on `updated_at`, and an edited old comment is
# not a new one.
now_utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# `gh api` prints the error body on stdout, so this is a list of logins
# or nothing: a 404's JSON has no `.[].user.login` and yields empty.
comment_authors() { # <iso-8601> -> the login behind every comment created after it
    gh_as "$HOUSEKEEPER" api --paginate \
        "/repos/$GITHUB_REPO/issues/$ISSUE/comments?per_page=100&since=$1" \
        --jq ".[] | select(.created_at > \"$1\") | .user.login" 2>/dev/null || true
}

# A scratch issue is a fixture, not a unit of work, and the errand tells
# every arm that claiming is not part of it. An arm that claims anyway —
# or whose session dies between the claim and the handoff — leaves
# `in-progress` behind, and work.sh's mutex then refuses the NEXT arm on
# a claim this very run produced (refusal (e), exit 2). Clearing it per
# arm is what keeps one arm's accident from being reported as another
# harness's failure; it removes the label only, never a comment, so the
# thread still records what happened.
# It VERIFIES rather than fires and hopes: `|| true` on the edit would
# hide both a failed removal and GitHub serving the label list from
# before it, and either one surfaces two steps later as work.sh refusing
# the arm on a mutex the operator can see is gone — a failure report
# naming the wrong cause, which is the one thing this gate must not do.
clear_claim() {
    local attempt
    for attempt in 1 2 3 4 5 6 7 8 9 10; do
        gh_as "$HOUSEKEEPER" api \
            -X DELETE "/repos/$GITHUB_REPO/issues/$ISSUE/labels/in-progress" \
            >/dev/null 2>&1 || true
        gh_as "$HOUSEKEEPER" api "/repos/$GITHUB_REPO/issues/$ISSUE" \
            --jq '[.labels[].name] | index("in-progress") // "gone"' 2>/dev/null \
            | grep -qx gone && return 0
        sleep 2
    done
    note "in-progress is still on #$ISSUE after 10 attempts; work.sh's mutex will refuse this arm"
    return 0
}

# The labels to strip come from the same join `relabel_of` reads, not
# from a list beside it: a hand-written enumeration in a script whose
# whole subject is deriving these facts drifts the moment a rung is added
# or renamed, and the one it carried already named a `status:done` that
# `personas/lifecycle.json` does not have.
relabel() { # <status-label>
    local want="$1" have
    for have in $(jq -r '.stages[].label' "$LIFECYCLE_JSON"); do
        [ "$have" = "$want" ] && continue
        gh_as "$HOUSEKEEPER" issue edit "$ISSUE" --repo "$GITHUB_REPO" \
            --remove-label "$have" >/dev/null 2>&1 || true
    done
    gh_as "$HOUSEKEEPER" issue edit "$ISSUE" --repo "$GITHUB_REPO" \
        --add-label "$want" >/dev/null \
        || { echo "smoke_launch: cannot put $want on #$ISSUE" >&2; exit 1; }
}

launch() { # <persona>; -> exit code of work.sh
    local persona="$1" rc=0
    echo "  --- launching $persona (capped by its own limits.timeout_mins)"
    HEADLESS=1 "$REPO_ROOT/scripts/ops/work.sh" --as "$persona" "$ISSUE" || rc=$?
    echo "  --- work.sh exited $rc"
    return "$rc"
}

# Observable 1. runs/ is gitignored, so a smoke run leaves the tree clean.
check_local_artifact() { # <persona>
    local persona="$1"
    if [ -s "$SMOKE_DIR/$persona.md" ]; then
        ok "$persona wrote $SMOKE_DIR/$persona.md: $(head -1 "$SMOKE_DIR/$persona.md")"
    else
        bad "$persona left no artifact at $SMOKE_DIR/$persona.md"
    fi
}

# Observable 2. Authorship, not content: the comment proves the minted
# token reached the session as its own identity.
check_comment() { # <persona> <iso-8601-before-the-launch>
    local persona="$1" since="$2" want authors
    want="$(identity_of "$persona")"
    authors="$(comment_authors "$since")"
    if printf '%s\n' "$authors" | grep -qxF "$want"; then
        ok "#$ISSUE carries a comment by $want posted after $since"
    else
        bad "no comment by $want on #$ISSUE after $since (authors since: $(printf '%s' "${authors:-none}" | tr '\n' ' '))"
    fi
}

# Observable 3. The push is the token-handoff proof: a harness's stock
# fallback agent has no instruction to push anything, so a scratch branch
# on origin means the persona loaded AND its minted token authenticated.
# Shape-checked, not just non-empty: `gh api` prints the error body on
# stdout for a 404, so `|| true` alone would hand a JSON blob to the
# assertion and call a missing branch a pass.
declare -A VERIFIED_REF=()
check_pushed_artifact() { # <persona> <ref>
    local persona="$1" ref="$2" pushed want author size
    pushed="$(gh_as "$HOUSEKEEPER" api "/repos/$GITHUB_REPO/git/ref/heads/$ref" \
                  --jq '.object.sha' 2>/dev/null || true)"
    case "$pushed" in
        [0-9a-f][0-9a-f]*) [ "${#pushed}" = "40" ] || pushed="" ;;
        *) pushed="" ;;
    esac
    if [ -z "$pushed" ]; then
        bad "$persona pushed no $ref — the persona did not load, or the token did not authenticate"
        return
    fi
    ok "$ref exists on origin ($pushed)"
    VERIFIED_REF["$ref"]="$pushed"
    want="$(identity_of "$persona")"
    author="$(gh_as "$HOUSEKEEPER" api "/repos/$GITHUB_REPO/commits/$pushed" \
                  --jq '.commit.author.name' 2>/dev/null || echo '')"
    [ "$author" = "$want" ] \
        && ok "its head commit is authored by $want" \
        || bad "its head commit is authored by '${author:-unknown}'"
    size="$(gh_as "$HOUSEKEEPER" api \
                "/repos/$GITHUB_REPO/contents/SMOKE-$ISSUE.md?ref=$ref" \
                --jq '.size' 2>/dev/null || true)"
    case "$size" in
        ''|*[!0-9]*) bad "$persona pushed no SMOKE-$ISSUE.md on $ref" ;;
        0)           bad "$persona pushed an empty SMOKE-$ISSUE.md on $ref" ;;
        *)           ok "$persona's commit carries SMOKE-$ISSUE.md ($size bytes)" ;;
    esac
}

# Deriving the branch from the persona's own contract moved the fixture
# refs out of a dedicated `smoke/*` namespace and into each persona's
# real one, next to its work branches. Collecting only the CURRENT arms'
# refs therefore leaves `<other-persona>/smoke-<issue>` on origin
# indefinitely after a pin flip or a trailing-argument override, and
# `worktrees.sh --prune-remote` never takes them because it collects
# merged branches and these are never merged. So the reset is over every
# pinned persona's smoke ref for THIS issue, not over this run's arms.
#
# It deletes those refs as the HOUSEKEEPER, which means one persona's
# minted token deleting a ref inside another persona's `branch:<glob>`
# namespace, and that is deliberate rather than an oversight (Argus
# R2-14). The housekeeping identity is not a persona doing a persona's
# work — it is this script's own hands, defined by making no model call,
# and it already writes the issue body, strips every `status:*` label and
# deletes each arm's own ref below. A `branch:` glob bounds what the
# AGENT it belongs to may push while working an issue; it is not a
# per-namespace lock on the repository, and re-minting a second, third
# and fourth token to delete four fixture refs would buy no authority
# the housekeeper's App does not already hold. What was an oversight is
# the silence: `|| true` swallowed a refused delete, so the litter R1-9
# named would persist with nothing in the run saying so. A delete that
# fails for any reason other than "there is no such ref" is now said out
# loud. It stays a `note` and not a failure: leftover fixture refs are
# housekeeping, not an observable.
clear_smoke_refs() {
    local persona branch out
    while read -r persona _; do
        branch="$(smoke_branch_of "$persona")"
        [ -n "$branch" ] || continue
        out="$(gh_as "$HOUSEKEEPER" api -X DELETE \
                   "/repos/$GITHUB_REPO/git/refs/heads/$branch" 2>&1)" && continue
        case "$out" in
            *404*|*"Not Found"*|*"does not exist"*) : ;;   # nothing there to reset
            *) note "could not delete the stale fixture ref $branch as $HOUSEKEEPER: ${out%%$'\n'*}" ;;
        esac
    done < <(pins)
}

# The evidence this gate produces has to be evidence at the moment it is
# read, not only at the moment it was taken. On the first live run,
# sessions this script did not launch force-pushed over BOTH arms'
# branches minutes after the observables were verified and the run had
# exited 0: the SHAs in the transcript were no longer the SHAs on origin,
# so the central proof was unreproducible and nothing said so. Re-reading
# each verified ref at the end costs one API call per arm and converts a
# silent divergence into a named failure. It does not FIX re-entrant
# dispatch — that is a launcher-side refusal in `scripts/ops/work.sh`,
# out of this file's set and tracked on #134 — it stops this gate from
# reporting a green it can no longer stand behind.
#
# "The read failed" and "the ref is gone" are DIFFERENT outcomes and are
# reported differently (Atlas AT-R2-12). `--jq '.object.sha' || true`
# collapsed them: a transient 5xx, a rate limit or an expired
# installation token yields the empty string exactly as a deleted ref
# does, and the row then printed `-> deleted` and failed the run — a
# false FAILED on the one observable whose whole point is trustworthy
# evidence. A failed read is retried, because that is what makes a 5xx
# transient rather than fatal, and if it still cannot be read the row
# says so in its own words. It is still a failure — a re-read that did
# not happen is not a re-read that passed — but it names a failed read,
# so the operator retries instead of hunting a session that overwrote
# nothing.
recheck_verified_refs() {
    local ref now attempt read_ok
    [ "${#VERIFIED_REF[@]}" -gt 0 ] || { note "no push observable held, so there is none to re-read"; return 0; }
    for ref in "${!VERIFIED_REF[@]}"; do
        read_ok=0
        for attempt in 1 2 3; do
            if now="$(gh_as "$HOUSEKEEPER" api "/repos/$GITHUB_REPO/git/ref/heads/$ref" \
                          --jq '.object.sha' 2>/dev/null)"; then
                read_ok=1; break
            fi
            [ "$attempt" = "3" ] || sleep 2
        done
        if [ "$read_ok" = "0" ]; then
            bad "could not re-read $ref after 3 attempts, so this run cannot confirm it still points at ${VERIFIED_REF[$ref]}. This is a FAILED READ, not a moved ref: the evidence above is unverified rather than known stale."
            continue
        fi
        if [ "$now" = "${VERIFIED_REF[$ref]}" ]; then
            ok "$ref still points at the commit this run verified (${VERIFIED_REF[$ref]})"
        else
            bad "$ref moved after this run verified it: ${VERIFIED_REF[$ref]} -> ${now:-deleted}. A session this gate did not launch wrote over the observable, so the evidence above is not reproducible."
        fi
    done
}

# --- the runs -------------------------------------------------------------------
rm -rf "$SMOKE_DIR"
clear_smoke_refs
n=0
for arm in "${ARMS[@]}"; do
    n=$((n + 1))
    set -- $arm
    harness="$1"; persona="$2"
    branch="$(smoke_branch_of "$persona")"

    banner "run $n · $harness · $persona · #$ISSUE"
    check_token "$persona"
    clear_claim
    relabel "$(relabel_of "$persona")"
    # Cleared through the API, not through the launcher's own git: this
    # script must never push with whatever credentials the operator's
    # shell happens to carry — that is the identity confusion #43 exists
    # to end.
    gh_as "$HOUSEKEEPER" api -X DELETE "/repos/$GITHUB_REPO/git/refs/heads/$branch" \
        >/dev/null 2>&1 || true
    # The local side of the same reset. The errand has the arm push from a
    # throwaway worktree at /tmp/smoke-<issue>-<persona> on a branch of
    # that name; both survive the run, and on the NEXT run against the
    # same scratch issue `git worktree add -b` fails on each of them. The
    # arm then produces no commit and the push observable reports "the
    # persona did not load" — a second run of a gate failing for no
    # reason but the first run's litter.
    git -C "$REPO_ROOT" worktree remove --force "/tmp/smoke-$ISSUE-$persona" \
        >/dev/null 2>&1 || true
    rm -rf "/tmp/smoke-$ISSUE-$persona"
    # NO `git worktree prune` here. It is repo-wide and silent: it runs
    # against the common git dir, so a peer session's unlocked worktree
    # whose directory is momentarily absent loses its registration
    # during a smoke run and the peer's next git command there fails
    # with "not a git repository", with `2>&1 || true` swallowing any
    # word of it. AGENTS.md puts pruning behind `scripts/ops/worktrees.sh`
    # and the rule "never remove a worktree you did not create". It was
    # near-redundant anyway: `worktree remove --force` above already
    # deregisters this run's own worktree.
    git -C "$REPO_ROOT" branch -D "$branch" >/dev/null 2>&1 || true
    before="$(now_utc)"

    rc=0; launch "$persona" || rc=$?
    [ "$rc" = "0" ] && ok "work.sh exited 0 (the session reported WORK-RESULT: ok)" \
                    || bad "work.sh exited $rc, not 0"
    check_local_artifact  "$persona"
    check_comment         "$persona" "$before"
    check_pushed_artifact "$persona" "$branch"
done

# --- verdict -------------------------------------------------------------------
banner "the observables are still the observables"
recheck_verified_refs

banner "verdict"
note "$blocked observable(s) tolerated and are not failures"
if [ "$failures" -gt 0 ]; then
    echo "smoke_launch: $failures observable(s) failed."
    exit 1
fi
echo "smoke_launch: every pinned harness launched; every required observable held."
