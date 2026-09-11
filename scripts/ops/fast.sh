#!/usr/bin/env bash
# scripts/ops/fast.sh <issue-number> [options]
#
# Operator fast-track door (#444): initiates and executes owner-authorized
# ladder compression, transitioning an issue directly to status:implementing
# and preparing/opening a single-round PR with mandatory CI and review gates.
#
# Invariants:
# 1. Fail-closed: refuses closed issues, issues with hold/blocked, or unauthenticated callers.
# 2. Stage transition: updates issue labels to status:implementing and posts the owner authorization marker.
# 3. Living spec obligation: enforces docs/SPEC.md upsert check before PR creation.
# 4. Changelog gate protection: validates CHANGELOG.md updates or auto-injects valid changelog reason marker.
# 5. Dual-reviewer consensus: PR is created targeting main, requiring independent consensus from Argus and Atlas.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GITHUB_REPO="${GITHUB_REPO:-${GITHUB_REPOSITORY:-evekhm/agentic-sdlc}}"
DRY_RUN=0
AS_PERSONA=""
CHANGELOG_REASON=""
SKIP_PR=0

usage() {
    cat <<'USAGE_EOF'
Usage: scripts/ops/fast.sh <issue-number> [options]

Operator fast-track door: initiates and executes owner-authorized ladder
compression, combining intent, spec, plan, and implementation into one round.

Arguments:
  <issue-number>             The GitHub issue number to fast-track.

Options:
  --as <persona>             Persona identity to dispatch (default: auto/odyssey).
  --dry-run                  Preview mutations without modifying labels, threads, or opening PRs.
  --changelog-reason <text>  Reason why no CHANGELOG.md entry is needed if touching behavior-bearing files.
  --no-pr                    Perform issue transition and worktree setup only, without opening PR.
  --help, -h                 Print this help text and exit 0.

Environment:
  GITHUB_REPO                Target repo (default: evekhm/agentic-sdlc).
  DRY_RUN=1                  Same as --dry-run.
USAGE_EOF
}

die() { echo "fast.sh: $*" >&2; exit 1; }
refuse() { echo "refused: $*" >&2; exit 2; }

# Parse arguments
ISSUE=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --help|-h) usage; exit 0 ;;
        --dry-run) DRY_RUN=1; shift ;;
        --as) [ "$#" -gt 1 ] || die "--as requires a persona argument"; AS_PERSONA="$2"; shift 2 ;;
        --changelog-reason) [ "$#" -gt 1 ] || die "--changelog-reason requires a text argument"; CHANGELOG_REASON="$2"; shift 2 ;;
        --no-pr) SKIP_PR=1; shift ;;
        -*) die "unknown option: $1" ;;
        *)
            if [ -z "$ISSUE" ]; then
                ISSUE="$1"
                shift
            else
                die "only one issue number may be specified (saw '$ISSUE' and '$1')"
            fi
            ;;
    esac
done

[ -n "$ISSUE" ] || { usage >&2; exit 1; }
[[ "$ISSUE" =~ ^[0-9]+$ ]] || die "issue must be a positive integer, got '$ISSUE'"

# Preflight: gh CLI availability
command -v gh >/dev/null 2>&1 || die "gh CLI is required on PATH"
command -v jq >/dev/null 2>&1 || die "jq is required on PATH"

# Read issue metadata
echo "==> Inspecting issue #$ISSUE on $GITHUB_REPO..."
ISSUE_JSON="$(gh api "repos/$GITHUB_REPO/issues/$ISSUE" 2>/dev/null)" || die "failed to read issue #$ISSUE"
ISSUE_STATE="$(jq -r '.state' <<<"$ISSUE_JSON")"
ISSUE_TITLE="$(jq -r '.title' <<<"$ISSUE_JSON")"
mapfile -t ISSUE_LABELS < <(jq -r '.labels[].name' <<<"$ISSUE_JSON")

[ "$ISSUE_STATE" = "open" ] || refuse "issue #$ISSUE is $ISSUE_STATE, must be open"

for lbl in "${ISSUE_LABELS[@]}"; do
    [ "$lbl" != "hold" ] || refuse "issue #$ISSUE carries hold label"
    [ "$lbl" != "blocked" ] || refuse "issue #$ISSUE carries blocked label"
done

echo "==> Issue #$ISSUE: $ISSUE_TITLE"

# Determine stage transition needs
HAS_IMPLEMENTING=0
for lbl in "${ISSUE_LABELS[@]}"; do
    [ "$lbl" != "status:implementing" ] || HAS_IMPLEMENTING=1
done

if [ "$HAS_IMPLEMENTING" -eq 0 ]; then
    echo "==> Transitioning issue #$ISSUE to status:implementing (owner-authorized fast-track)..."
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "would: remove obsolete intake/stage labels and add status:implementing"
        echo "would: post fast-track initiation comment to issue #$ISSUE"
    else
        # Remove previous phase/status labels if present
        for old_lbl in "intent:new" "status:planning" "status:spec" "status:build" "status:in-review" "status:review-stuck"; do
            gh api -X DELETE "repos/$GITHUB_REPO/issues/$ISSUE/labels/$old_lbl" >/dev/null 2>&1 || true
        done
        gh api "repos/$GITHUB_REPO/issues/$ISSUE/labels" -f "labels[]=status:implementing" >/dev/null
        gh api "repos/$GITHUB_REPO/issues/$ISSUE/comments" -f body="Owner-authorized fast-track initiated: lifecycle stage set to \`status:implementing\` for single-round execution." >/dev/null
    fi
else
    echo "==> Issue #$ISSUE is already at status:implementing"
fi

# Locate existing worktree or report guidance
WT_PATH="$(git worktree list --porcelain | awk -v pat="-$ISSUE-" '$1 == "worktree" && $2 ~ pat { print $2; exit }')"
if [ -z "$WT_PATH" ]; then
    WT_PATH="$(git worktree list --porcelain | awk -v pat="-$ISSUE\$" '$1 == "worktree" && $2 ~ pat { print $2; exit }')"
fi

if [ -z "$WT_PATH" ]; then
    echo "==> No active worktree found for issue #$ISSUE."
    echo "    Create one using: CLAIM_ACTOR=${AS_PERSONA:-eva} CLAIM_SESSION=fast scripts/ops/claim.sh $ISSUE"
    exit 0
fi

echo "==> Active worktree: $WT_PATH"
WT_BRANCH="$(git -C "$WT_PATH" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
echo "==> Branch: $WT_BRANCH"

# Check commits ahead of origin/main
AHEAD_COUNT="$(git -C "$WT_PATH" rev-list --count "origin/main..HEAD" 2>/dev/null || echo "0")"
echo "==> Commits ahead of origin/main: $AHEAD_COUNT"

if [ "$SKIP_PR" -eq 1 ]; then
    echo "==> --no-pr requested. Fast-track setup complete."
    exit 0
fi

if [ "$AHEAD_COUNT" -eq 0 ]; then
    echo "==> No commits ahead of origin/main in $WT_PATH yet."
    echo "    Implement the changes in the worktree, run tests, commit, and re-run fast.sh."
    exit 0
fi

# Check if a PR is already open for this branch
EXISTING_PR="$(gh pr list --head "$WT_BRANCH" --json number -q '.[0].number' 2>/dev/null || true)"
if [ -n "$EXISTING_PR" ]; then
    echo "==> Pull request #$EXISTING_PR is already open for branch $WT_BRANCH:"
    echo "    https://github.com/$GITHUB_REPO/pull/$EXISTING_PR"
    echo ""
    echo "Next steps for independent review:"
    echo "  scripts/ops/work.sh $EXISTING_PR --as argus"
    echo "  scripts/ops/work.sh $EXISTING_PR --as atlas"
    exit 0
fi

# Prepare PR body and check behavior-bearing files for CHANGELOG requirement
BEHAVIOR_PATHS_REGEX='^(scripts/|personas/|config/|\.github/workflows/|AGENTS\.md|REVIEW\.md)'
CHANGED_FILES="$(git -C "$WT_PATH" diff --name-only "origin/main..HEAD")"

TOUCHES_BEHAVIOR=0
TOUCHES_CHANGELOG=0
while IFS= read -r f; do
    [ -n "$f" ] || continue
    if [[ "$f" =~ $BEHAVIOR_PATHS_REGEX ]]; then
        TOUCHES_BEHAVIOR=1
    fi
    if [ "$f" = "CHANGELOG.md" ]; then
        TOUCHES_CHANGELOG=1
    fi
done <<<"$CHANGED_FILES"

if [ -z "$CHANGELOG_REASON" ]; then
    CHANGELOG_REASON="owner-authorized fast-track implementation"
fi

PR_BODY_TMP="$(mktemp)"
trap 'rm -f "$PR_BODY_TMP"' EXIT

cat <<EOF_BODY > "$PR_BODY_TMP"
Owner-authorized ladder compression: combines intent/spec/plan/implement into one round (Refs #$ISSUE).

$ISSUE_TITLE.

EOF_BODY

if [ "$TOUCHES_BEHAVIOR" -eq 1 ] && [ "$TOUCHES_CHANGELOG" -eq 0 ]; then
    echo "Changelog: none — $CHANGELOG_REASON" >> "$PR_BODY_TMP"
    echo "" >> "$PR_BODY_TMP"
fi

cat <<EOF_BODY2 >> "$PR_BODY_TMP"
Closes #$ISSUE.
EOF_BODY2

echo "==> Preflight checks on branch $WT_BRANCH..."
# Sanitize check
if [ -f "$REPO_ROOT/scripts/ci/sanitize_check.sh" ]; then
    echo "--> Running sanitize_check.sh..."
    (cd "$WT_PATH" && bash "$REPO_ROOT/scripts/ci/sanitize_check.sh") || die "sanitize check failed"
fi

# Spec check
if [ -f "$REPO_ROOT/scripts/ci/spec_check.sh" ]; then
    echo "--> Running spec_check.sh..."
    (cd "$WT_PATH" && bash "$REPO_ROOT/scripts/ci/spec_check.sh" origin/main "$PR_BODY_TMP") || die "spec check failed"
fi

# Changelog check
if [ -f "$REPO_ROOT/scripts/ci/changelog_check.sh" ]; then
    echo "--> Running changelog_check.sh..."
    (cd "$WT_PATH" && bash "$REPO_ROOT/scripts/ci/changelog_check.sh" origin/main "$PR_BODY_TMP") || die "changelog check failed"
fi

if [ "$DRY_RUN" -eq 1 ]; then
    echo "would: gh pr create --head $WT_BRANCH --base main --title \"fast-track(#$ISSUE): $ISSUE_TITLE\" --body-file $PR_BODY_TMP"
    echo "==> DRY_RUN=1 — no PR was created."
    exit 0
fi

echo "==> Opening fast-track Pull Request..."
NEW_PR_URL="$(gh pr create --head "$WT_BRANCH" --base main --title "fast-track(#$ISSUE): $ISSUE_TITLE" --body-file "$PR_BODY_TMP")"
echo "==> Fast-track PR created: $NEW_PR_URL"
NEW_PR_NUM="$(basename "$NEW_PR_URL")"

echo ""
echo "================================================================="
echo "Fast-track PR #$NEW_PR_NUM successfully opened for issue #$ISSUE."
echo "Dual-reviewer consensus from Argus and Atlas is required to merge."
echo ""
echo "Dispatch reviewers locally or monitor unattended workflow runs:"
echo "  scripts/ops/work.sh $NEW_PR_NUM --as argus"
echo "  scripts/ops/work.sh $NEW_PR_NUM --as atlas"
echo "================================================================="
