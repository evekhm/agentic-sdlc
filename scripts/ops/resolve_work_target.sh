#!/usr/bin/env bash
# scripts/ops/resolve_work_target.sh [<issue-number>] (#441)
#
# Resolves the number `/work` acts on when the operator does not type one,
# so the command can be the bare `/work` the D5 amendment describes rather
# than failing on a missing argument. This is a resolution layer in front
# of scripts/ops/work.sh, not a change to it: work.sh keeps its #36 D7
# contract ("a number is the whole instruction, nothing else is an
# argument") untouched.
#
# Order, first match wins:
#   1. an explicit argument
#   2. the current worktree's branch — claim.sh names it
#      "<actor>/<number>-<slug>", so the number is already sitting in
#      `git branch --show-current`
#   3. the last issue this session resolved, from a small per-session
#      state file (skipped if the session id is unknown, or if that
#      issue is no longer open)
#   4. neither: print the operator's open, unclaimed candidates and exit
#      3 so the caller asks which one, instead of failing on a bare
#      "no issue number" error
#
# Deterministic bash + git + gh + jq. No model call. On a successful
# resolution (1-3) the number is written back to the state file as the
# new "last touched", so a second bare `/work` right after a pick keeps
# working from the same session.
#
# State file location follows the harness side-channel convention
# (scripts/ops/harness/statusline.sh: $AGENTIC_CTX_DIR, else
# $CLAUDE_CTX_DIR, else ~/.claude/context, else /tmp/agentic-context) but
# is its own file, keyed by session id, so it never races that JSON.
#
# Exit codes:
#   0  resolved; the number is the only line on stdout
#   1  unusable input: the explicit argument is not a positive integer
#   3  no resolution; a NEEDS_PICK header and the candidate list (one
#      "<number>\t<title>" per line) are printed instead

set -euo pipefail

GITHUB_REPO="${GITHUB_REPO:-${GITHUB_REPOSITORY:-evekhm/agentic-sdlc}}"

die() { echo "resolve_work_target.sh: $*" >&2; exit 1; }

EXPLICIT="${1:-}"

if [ -n "$EXPLICIT" ]; then
    case "$EXPLICIT" in
        ''|*[!0-9]*) die "'$EXPLICIT' is not an issue number" ;;
    esac
fi

# --- Session state file location, matching the harness side-channel dir ----
SESSION_ID="${CLAUDE_CODE_SESSION_ID:-}"
user_root=~
CTX_DIR="${AGENTIC_CTX_DIR:-${CLAUDE_CTX_DIR:-$user_root/.claude/context}}"
[ -d "$CTX_DIR" ] && [ -w "$CTX_DIR" ] || CTX_DIR="/tmp/agentic-context"
STATE_FILE=""
[ -n "$SESSION_ID" ] && STATE_FILE="$CTX_DIR/${SESSION_ID}.work-last-issue"

record_last() { # <number>
    [ -n "$STATE_FILE" ] || return 0
    mkdir -p "$CTX_DIR" 2>/dev/null || return 0
    local tmp
    tmp="$(mktemp "$CTX_DIR/.work-last-issue.XXXXXX" 2>/dev/null)" || return 0
    printf '%s\n' "$1" > "$tmp" && mv -f "$tmp" "$STATE_FILE"
}

resolve() {
    if [ -n "$EXPLICIT" ]; then
        echo "resolve_work_target.sh: source: explicit argument" >&2
        printf '%s\n' "$EXPLICIT"
        return 0
    fi

    local branch number
    branch="$(git branch --show-current 2>/dev/null || true)"
    if [[ "$branch" =~ ^[^/]+/([0-9]+)- ]]; then
        number="${BASH_REMATCH[1]}"
        echo "resolve_work_target.sh: source: current worktree branch '$branch'" >&2
        printf '%s\n' "$number"
        return 0
    fi

    if [ -n "$STATE_FILE" ] && [ -f "$STATE_FILE" ]; then
        number="$(tr -d '[:space:]' < "$STATE_FILE" 2>/dev/null || true)"
        if [[ "$number" =~ ^[0-9]+$ ]]; then
            local state
            state="$(gh issue view "$number" --repo "$GITHUB_REPO" --json state -q '.state' 2>/dev/null || true)"
            if [ "$state" = "OPEN" ]; then
                echo "resolve_work_target.sh: source: last issue this session touched (#$number)" >&2
                printf '%s\n' "$number"
                return 0
            fi
        fi
    fi

    return 1
}

if NUMBER="$(resolve)"; then
    record_last "$NUMBER"
    printf '%s\n' "$NUMBER"
    exit 0
fi

echo "NEEDS_PICK"
gh issue list --repo "$GITHUB_REPO" --state open --json number,title,labels \
    --jq '.[] | select([.labels[].name] | index("in-progress") | not) | "\(.number)\t\(.title)"'
exit 3
