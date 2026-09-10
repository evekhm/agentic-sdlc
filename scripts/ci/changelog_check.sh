#!/usr/bin/env bash
# The changelog gate (#410), run by .github/workflows/ci-gates.yml.
#
# It enforces the choice AGENTS.md ("The changelog") puts on every PR
# that touches behavior-bearing paths: either the diff updates
# CHANGELOG.md, or the PR body carries the machine marker
# `Changelog: none — <reason>` (or `Changelog-impact: none — <reason>`).
# It never judges the CONTENT of a changelog entry or of a reason —
# reviewers do that; this step only makes the choice explicit and
# mechanical.
#
# Behavior-bearing means a SOURCE of behavior: scripts/, personas/,
# config/, .github/workflows/, AGENTS.md, REVIEW.md. Compiled targets
# (.claude/agents/, .agents/) are deliberately NOT in the list — they
# are derived from personas/ + config/, the drift gate owns them, and
# a hand edit there must fail as drift rather than as a missing entry.
#
# Env contract (CI; all required, all validated):
#   BASE_SHA      merge-base / PR base commit
#   HEAD_SHA      PR head commit
#   PR_BODY_FILE  path to a file holding the PR body verbatim. An
#                 EMPTY file is a valid (empty) body; a MISSING file
#                 is an error — never a body without the marker.
#
# Local use (no env needed):
#   scripts/ci/changelog_check.sh <base-ref> [body-file]
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

CHANGELOG_PATH="CHANGELOG.md"

die() { echo "::error::changelog_check: $*"; exit 1; }

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
        die "$var is unset or empty; refusing to guess the changelog obligation"
    fi
done
[ -f "$PR_BODY_FILE" ] || die "PR_BODY_FILE does not exist: $PR_BODY_FILE"
[ -r "$PR_BODY_FILE" ] || die "PR_BODY_FILE is not readable: $PR_BODY_FILE"

# A failure here (bad SHA, shallow clone missing the base) is
# indeterminate, not "no files changed".
if ! changed=$(git diff --name-only "$BASE_SHA" "$HEAD_SHA"); then
    die "git diff --name-only $BASE_SHA $HEAD_SHA failed; changed files are unknown"
fi

changelog_touched=0
behavior=()
while IFS= read -r f; do
    [ -n "$f" ] || continue
    if [ "$f" = "$CHANGELOG_PATH" ]; then changelog_touched=1; continue; fi
    case "$f" in
        .github/workflows/*|scripts/*|personas/*|config/*)
            behavior+=("$f") ;;
        AGENTS.md|REVIEW.md)
            behavior+=("$f") ;;
    esac
done <<<"$changed"

if [ "${#behavior[@]}" -eq 0 ]; then
    echo "::notice::changelog check: no behavior-bearing paths changed; no changelog obligation"
    exit 0
fi

if [ "$changelog_touched" -eq 1 ]; then
    echo "::notice::changelog check: CHANGELOG.md is updated in this PR; reviewers verify its entry against the diff"
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
    [[ "$line" =~ ^[[:space:]]*[Cc]hangelog(-[Ii]mpact)?:[[:space:]]*[Nn]one(.*)$ ]] || continue
    rest="${BASH_REMATCH[2]}"
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
    echo "::notice::changelog check: declared no changelog impact — $reason"
    exit 0
fi

if [ "$marker_found" -eq 1 ]; then
    echo "::error::changelog_check: the Changelog marker needs a reason: write 'Changelog: none — <why this diff does not change user-facing or system behavior>'"
else
    echo "::error::changelog_check: this PR changes behavior-bearing paths but neither updates $CHANGELOG_PATH nor declares no changelog impact"
fi
echo "behavior-bearing files in this diff:"
printf '  %s\n' "${behavior[@]}"
echo "satisfy the check one of two ways (AGENTS.md, 'The changelog'):"
echo "  1. update $CHANGELOG_PATH in this PR with a curated entry under today's date heading;"
echo "  2. or, if the diff genuinely has no user-facing or system behavior impact, add this line to the PR"
echo "     body: Changelog: none — <reason>"
exit 1
