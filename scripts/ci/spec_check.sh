#!/usr/bin/env bash
# The living-spec gate (#6), run by .github/workflows/ci-gates.yml.
# Ported from the predecessor repository's spec check; the mechanism is
# unchanged, the repository-specific details are this repository's.
#
# It enforces the choice AGENTS.md ("The living spec") puts on every PR
# that touches behavior-bearing paths: either the diff updates
# docs/SPEC.md, or the PR body carries the machine marker
# `Spec-impact: none — <reason>`. It never judges the CONTENT of a spec
# entry or of a reason — reviewers do that; this step only makes the
# choice explicit and mechanical.
#
# Behavior-bearing means a SOURCE of behavior: scripts/, personas/,
# config/, .github/workflows/, AGENTS.md, REVIEW.md. Compiled targets
# (.claude/agents/, .agents/) are deliberately NOT in the list — they
# are derived from personas/ + config/, the drift gate owns them, and
# a hand edit there must fail as drift rather than as a missing spec
# entry.
#
# Env contract (CI; all required, all validated):
#   BASE_SHA      merge-base / PR base commit
#   HEAD_SHA      PR head commit
#   PR_BODY_FILE  path to a file holding the PR body verbatim. An
#                 EMPTY file is a valid (empty) body; a MISSING file
#                 is an error — never a body without the marker.
#
# Local use (no env needed):
#   scripts/ci/spec_check.sh <base-ref> [body-file]
# The base ref is resolved to a merge base with HEAD; with no body file
# the check runs against an empty body, which is what an unwritten PR
# description amounts to.
#
# Fail-closed: an unset input, an unreadable body file, or a failed
# `git diff` exits 1 rather than being read as "nothing changed" or "no
# marker". Only a git diff that SUCCEEDS with no output is an empty
# result. No `|| true`, no `2>/dev/null` on decision data.
#
# Exit 0 = obligation satisfied or not incurred; exit 1 = failed or
# indeterminate.

set -euo pipefail

SPEC_PATH="docs/SPEC.md"

die() { echo "::error::spec_check: $*"; exit 1; }

# --- local invocation ---------------------------------------------------------
if [ "$#" -gt 0 ]; then
    [ -z "${BASE_SHA:-}${HEAD_SHA:-}${PR_BODY_FILE:-}" ] \
        || die "pass EITHER the env contract (CI) OR positional arguments (local), not both"
    base_ref="$1"
    HEAD_SHA="$(git rev-parse HEAD)" || die "cannot resolve HEAD"
    BASE_SHA="$(git merge-base "$base_ref" "$HEAD_SHA")" \
        || die "no merge base between '$base_ref' and HEAD"
    if [ "$#" -ge 2 ]; then
        PR_BODY_FILE="$2"
    else
        PR_BODY_FILE="$(mktemp)"
        trap 'rm -f "$PR_BODY_FILE"' EXIT
        echo "note: no body file given; checking against an empty PR body"
    fi
    export BASE_SHA HEAD_SHA PR_BODY_FILE
fi

for var in BASE_SHA HEAD_SHA PR_BODY_FILE; do
    if [ -z "${!var:-}" ]; then
        die "$var is unset or empty; refusing to guess the spec obligation"
    fi
done
[ -f "$PR_BODY_FILE" ] || die "PR_BODY_FILE does not exist: $PR_BODY_FILE"
[ -r "$PR_BODY_FILE" ] || die "PR_BODY_FILE is not readable: $PR_BODY_FILE"

# A failure here (bad SHA, shallow clone missing the base) is
# indeterminate, not "no files changed".
if ! changed=$(git diff --name-only "$BASE_SHA" "$HEAD_SHA"); then
    die "git diff --name-only $BASE_SHA $HEAD_SHA failed; changed files are unknown"
fi

spec_touched=0
behavior=()
while IFS= read -r f; do
    [ -n "$f" ] || continue
    if [ "$f" = "$SPEC_PATH" ]; then spec_touched=1; continue; fi
    case "$f" in
        .github/workflows/*|scripts/*|personas/*|config/*)
            behavior+=("$f") ;;
        AGENTS.md|REVIEW.md)
            behavior+=("$f") ;;
    esac
done <<<"$changed"

if [ "${#behavior[@]}" -eq 0 ]; then
    echo "::notice::spec check: no behavior-bearing paths changed; no spec obligation"
    exit 0
fi

if [ "$spec_touched" -eq 1 ]; then
    echo "::notice::spec check: $SPEC_PATH is updated in this PR; reviewers verify its entries against the diff"
    exit 0
fi

# Marker scan. Pure bash over the body's lines: no grep, so there is
# no rc=1 (no match) vs rc>=2 (error) ambiguity to get wrong. GitHub
# bodies arrive CRLF-terminated.
if ! body=$(tr -d '\r' < "$PR_BODY_FILE"); then
    die "failed to read PR_BODY_FILE: $PR_BODY_FILE"
fi

ltrim() { local s="$1"; printf '%s' "${s#"${s%%[![:space:]]*}"}"; }
rtrim() { local s="$1"; printf '%s' "${s%"${s##*[![:space:]]}"}"; }

marker_found=0
reason=""
while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*[Ss]pec-[Ii]mpact:[[:space:]]*[Nn]one(.*)$ ]] || continue
    rest="${BASH_REMATCH[1]}"
    # Guard against words that merely start with "none" (nonetheless…):
    # the marker ends there, or a separator/whitespace follows it.
    case "$rest" in
        ''|[[:space:]]*|-*|:*|'('*|'—'*) marker_found=1 ;;
        *) continue ;;
    esac
    reason="$(ltrim "$rest")"
    case "$reason" in
        '—'*) reason="${reason#—}" ;;
        -*)   reason="${reason#-}" ;;
        :*)   reason="${reason#:}" ;;
        '('*) reason="${reason#(}"; reason="$(rtrim "$reason")"; reason="${reason%)}" ;;
    esac
    reason="$(rtrim "$(ltrim "$reason")")"
    break
done <<<"$body"

if [ "$marker_found" -eq 1 ] && [ -n "$reason" ]; then
    echo "::notice::spec check: declared no spec impact — $reason"
    exit 0
fi

if [ "$marker_found" -eq 1 ]; then
    echo "::error::spec_check: the Spec-impact marker needs a reason: write 'Spec-impact: none — <why this diff changes no behavior>'"
else
    echo "::error::spec_check: this PR changes behavior-bearing paths but neither updates $SPEC_PATH nor declares no spec impact"
fi
echo "behavior-bearing files in this diff:"
printf '  %s\n' "${behavior[@]}"
echo "satisfy the check one of two ways (AGENTS.md, 'The living spec'):"
echo "  1. update $SPEC_PATH in this PR: add entries for new behavior, reword"
echo "     superseded ones in place keeping their capability ID, retract what a"
echo "     revert removes;"
echo "  2. or, if the diff genuinely changes no behavior, add this line to the PR"
echo "     body: Spec-impact: none — <reason>"
exit 1
