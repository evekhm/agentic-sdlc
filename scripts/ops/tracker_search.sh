#!/usr/bin/env bash
# scripts/ops/tracker_search.sh [--files <path>...] [--terms <term>...] [--decisions <term>...]
#
# Deterministic prior-art check, run before `gh issue create` and again
# immediately before `gh pr create` (AGENTS.md, "Before filing an
# issue"). Two independent passes:
#
#   1. File-scoped, identity-agnostic: which OPEN pull requests already
#      touch these exact paths. Catches a sibling PR regardless of its
#      wording, and regardless of who authored it — every session here
#      writes under one of a handful of shared bot identities, so
#      authorship carries no signal (agentic-sdlc #130/PR #132 duplicated
#      #126/PR #127 this way; #141 duplicated #129/PR #138 the same way,
#      twice in one session, even with this rule already written down —
#      the check has to actually run, not just exist).
#   2. Keyword, over open issues and PRs — catches a report of the same
#      problem that hasn't become a PR yet.
#
# Exit code mirrors this repo's refusal convention: 0 is genuinely
# clear (nothing found — the line to paste is printed), 2 is "something
# matched, look before you file" (a refusal to proceed blind, not an
# error), 1 is unusable input (no repo, bad arguments, gh not
# available).
set -euo pipefail

REPO="${GITHUB_REPO:-${GITHUB_REPOSITORY:-evekhm/agentic-sdlc}}"
FILES=()
TERMS=()
DECISIONS=()
mode=""
for arg in "$@"; do
    case "$arg" in
        --files) mode="files"; continue ;;
        --terms) mode="terms"; continue ;;
        --decisions) mode="decisions"; continue ;;
    esac
    case "$mode" in
        files) FILES+=("$arg") ;;
        terms) TERMS+=("$arg") ;;
        decisions) DECISIONS+=("$arg") ;;
        *) echo "usage: $0 [--files <path>...] [--terms <term>...] [--decisions <term>...]" >&2; exit 1 ;;
    esac
done
if [ "${#FILES[@]}" -eq 0 ] && [ "${#DECISIONS[@]}" -eq 0 ]; then
    echo "usage: $0 [--files <path>...] [--terms <term>...] [--decisions <term>...]" >&2
    exit 1
fi

found=0

if [ "${#DECISIONS[@]}" -gt 0 ]; then
    # R1-2: resolve the repo root from BASH_SOURCE (same pattern as
    # scripts/ops/work.sh and scripts/ops/tests/athena_front_door_contract_test.sh)
    # so this pass finds intent/*/spec.md regardless of the caller's cwd,
    # instead of silently reporting clear when run from elsewhere.
    repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    spec_glob="intent/*/spec.md"
    if ! (cd "$repo_root" && compgen -G "$spec_glob" >/dev/null); then
        echo "tracker_search: no $spec_glob found under $repo_root" >&2
        exit 1
    fi
    decision_matches="$(cd "$repo_root" && grep -E -n -i '^\|[[:space:]]*D[0-9]+[[:space:]]*\|' $spec_glob 2>/dev/null || true)"
    for term in "${DECISIONS[@]}"; do
        # R1-1: filter the row body (after the `grep -n` path:line: prefix)
        # only, so a term that happens to appear in a spec's path (e.g.
        # "intake" in intent/117-typed-intake/spec.md) doesn't pull in
        # every row of that file.
        decision_matches="$(grep -E -i -- "^[^:]*:[0-9]+:.*($term)" <<<"$decision_matches" || true)"
    done
    decision_matches="$(grep -v '^$' <<<"$decision_matches" || true)"
    if [ -n "$decision_matches" ]; then
        found=1
        if [ "${#FILES[@]}" -gt 0 ]; then
            echo "== decisions: matching rows =="
        fi
        echo "$decision_matches"
    fi
fi

if [ "${#FILES[@]}" -eq 0 ]; then
    if [ "$found" -eq 1 ]; then
        echo "REFUSING to say this is clear: something above matches. Read it before filing." >&2
        exit 2
    fi
    exit 0
fi

command -v gh >/dev/null || { echo "tracker_search: gh is not on PATH" >&2; exit 1; }
command -v jq >/dev/null || { echo "tracker_search: jq is not on PATH" >&2; exit 1; }

echo "== file-scoped: open PRs already touching ${FILES[*]} =="
pr_json="$(gh pr list --repo "$REPO" --state open --json number,title,files)"
hits="$(jq -r --argjson files "$(printf '%s\n' "${FILES[@]}" | jq -R . | jq -s .)" '
    .[] as $pr
    | ($pr.files | map(.path)) as $pr_files
    | ($files - ($files - $pr_files)) as $overlap
    | select(($overlap | length) > 0)
    | "#\($pr.number)\t\($pr.title)\t\($overlap | join(", "))"
' <<<"$pr_json")"
if [ -n "$hits" ]; then
    found=1
    printf '%s\n' "$hits" | while IFS=$'\t' read -r num title overlap; do
        echo "  $num $title  [touches: $overlap]"
    done
else
    echo "  none"
fi

if [ "${#TERMS[@]}" -gt 0 ]; then
    echo "== keyword: open issues/PRs matching: ${TERMS[*]} =="
    query="$(printf '%s ' "${TERMS[@]}")"
    for kind in issues prs; do
        matches="$(gh search "$kind" --repo "$REPO" --state open $query --json number,title 2>/dev/null || echo '[]')"
        count="$(jq 'length' <<<"$matches")"
        if [ "$count" -gt 0 ]; then
            found=1
            echo "  $kind:"
            jq -r '.[] | "    #\(.number) \(.title)"' <<<"$matches"
        fi
    done
fi

echo
if [ "$found" -eq 1 ]; then
    echo "REFUSING to say this is clear: something above matches. Read it before filing." >&2
    exit 2
fi
echo "tracker searched, no prior art: files=${FILES[*]}${TERMS:+ terms=${TERMS[*]}}${DECISIONS:+ decisions=${DECISIONS[*]}}"
exit 0
