#!/usr/bin/env bash
# scripts/ops/fast.sh <issue-number> [options]
#
# Operator fast-track door (#444): initiates and executes owner-authorized
# ladder compression, transitioning an issue directly to status:implementing
# and preparing/opening a single-round PR with mandatory CI and review gates.
#
# 1. Fail-closed: refuses closed issues, issues with hold/blocked, unattended runners,
#    unauthenticated callers, or contradictory stage labels. Caller write permissions required;
#    records caller or owner signature. (Bot restriction policy tracked in follow-up issue).
# 2. Stage transition: updates issue labels to status:implementing and posts the
#    owner authorization marker from a file, re-checking hold immediately prior.
# 3. Living spec obligation: enforces docs/SPEC.md upsert check before PR creation
#    (or explicit --spec-reason).
# 4. Changelog gate protection: validates CHANGELOG.md updates or requires an
#    explicit, substantive --changelog-reason marker.
# 5. Dual-reviewer consensus: PR is created targeting main, requiring independent
#    consensus from Argus and Atlas.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GITHUB_REPO="${GITHUB_REPO:-${GITHUB_REPOSITORY:-evekhm/agentic-sdlc}}"
DRY_RUN="${DRY_RUN:-0}"
AS_PERSONA="${AS_PERSONA:-odyssey}"
CHANGELOG_REASON=""
SPEC_REASON=""
SKIP_PR=0
NO_DISPATCH=0

usage() {
    cat <<'USAGE_EOF'
Usage: scripts/ops/fast.sh [<issue-number>] [options]

Operator fast-track door: initiates and executes owner-authorized ladder
compression, combining intent, spec, plan, and implementation into one round.

Arguments:
  <issue-number>             The GitHub issue number to fast-track (optional;
                             inferred from active worktree or branch if omitted).

Options:
  --as <persona>             Persona identity to dispatch (default: odyssey).
  --dry-run                  Preview mutations without modifying labels, threads, or opening PRs.
  --changelog-reason <text>  Substantive reason why no CHANGELOG.md entry is needed if touching behavior paths.
  --spec-reason <text>       Reason why no docs/SPEC.md update is needed if behavior is unchanged.
  --no-pr                    Perform issue transition and worktree setup only, without opening PR.
  --no-dispatch              Do not trigger automatic work.sh dispatch.
  --help, -h                 Print this help text and exit 0.

Environment:
  GITHUB_REPO                Target repo (default: evekhm/agentic-sdlc).
  DRY_RUN=1                  Same as --dry-run.
USAGE_EOF
}

die() { echo "fast.sh: $*" >&2; exit 1; }
refuse() { echo "refused: $*" >&2; exit 2; }

extract_issue_from_context() {
    local wt_top wt_name branch
    wt_top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
    if [ -n "$wt_top" ]; then
        wt_name="$(basename "$wt_top")"
        if [[ "$wt_name" =~ -([0-9]+)(-[^/]*)?$ ]]; then
            echo "${BASH_REMATCH[1]}"
            return 0
        elif [[ "$wt_name" =~ ^([0-9]+)(-[^/]*)?$ ]]; then
            echo "${BASH_REMATCH[1]}"
            return 0
        fi
    fi
    branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    if [ -n "$branch" ] && [ "$branch" != "HEAD" ] && [ "$branch" != "main" ]; then
        if [[ "$branch" =~ /([0-9]+)(-[^/]*)?$ ]]; then
            echo "${BASH_REMATCH[1]}"
            return 0
        elif [[ "$branch" =~ ^([0-9]+)(-[^/]*)?$ ]]; then
            echo "${BASH_REMATCH[1]}"
            return 0
        fi
    fi
    return 1
}

# Parse arguments
ISSUE=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --help|-h) usage; exit 0 ;;
        --dry-run) DRY_RUN=1; shift ;;
        --as) [ "$#" -gt 1 ] || die "--as requires a persona argument"; AS_PERSONA="$2"; shift 2 ;;
        --changelog-reason) [ "$#" -gt 1 ] || die "--changelog-reason requires a text argument"; CHANGELOG_REASON="$2"; shift 2 ;;
        --spec-reason) [ "$#" -gt 1 ] || die "--spec-reason requires a text argument"; SPEC_REASON="$2"; shift 2 ;;
        --no-pr) SKIP_PR=1; shift ;;
        --no-dispatch) NO_DISPATCH=1; shift ;;
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

if [ -z "$ISSUE" ]; then
    INFERRED_ISSUE="$(extract_issue_from_context || true)"
    if [ -n "$INFERRED_ISSUE" ]; then
        ISSUE="$INFERRED_ISSUE"
        echo "==> Inferred target issue #$ISSUE from worktree/branch"
    else
        usage >&2
        die "no issue number specified and could not infer issue number from worktree or branch"
    fi
fi
[[ "$ISSUE" =~ ^[0-9]+$ ]] || die "issue must be a positive integer, got '$ISSUE'"

# Preflight: gh CLI availability
command -v gh >/dev/null 2>&1 || die "gh CLI is required on PATH"
command -v jq >/dev/null 2>&1 || die "jq is required on PATH"

if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
    refuse "fast-track cannot be initiated within GitHub Actions / unattended runner automation"
fi

REPO_OWNER="$(gh api "repos/$GITHUB_REPO" --jq '.owner.login // empty' 2>/dev/null || true)"
[ -n "$REPO_OWNER" ] || REPO_OWNER="${GITHUB_REPO%%/*}"

# Determine authenticated caller identity
CALLER_USER_JSON="$(gh api user 2>/dev/null || true)"
CALLER_LOGIN="$(jq -r '.login // empty' <<<"$CALLER_USER_JSON")"
CALLER_TYPE="$(jq -r '.type // empty' <<<"$CALLER_USER_JSON")"

# Record caller signature / owner authorization
OWNER_AUTH_COMMENT_ID="$(gh api "repos/$GITHUB_REPO/issues/$ISSUE/comments" --jq '
    [.[] | select(.user.login == "'"$REPO_OWNER"'" and (.body | test("(?i)(^|\\s)(/fast(-track)?|owner-authorized fast-track)")))] | last | .id // empty
' 2>/dev/null || true)"

if [ -n "$OWNER_AUTH_COMMENT_ID" ]; then
    OWNER_SIGNATURE="on-issue comment #$OWNER_AUTH_COMMENT_ID by @$REPO_OWNER"
elif [ -n "$CALLER_LOGIN" ]; then
    OWNER_SIGNATURE="caller @$CALLER_LOGIN"
else
    OWNER_SIGNATURE="local operator"
fi
echo "==> Caller signature: $OWNER_SIGNATURE"

# Verify caller has collaborator permission on target repo
CALLER_CHECK_LOGIN="${CALLER_LOGIN:-$REPO_OWNER}"
CALLER_PERM_JSON="$(gh api "repos/$GITHUB_REPO/collaborators/$CALLER_CHECK_LOGIN/permission" 2>/dev/null || true)"
CALLER_PERM="$(jq -r '.permission // empty' <<<"$CALLER_PERM_JSON")"
if [ "$CALLER_PERM" != "admin" ] && [ "$CALLER_PERM" != "write" ]; then
    refuse "user $CALLER_CHECK_LOGIN does not have write or admin permissions on $GITHUB_REPO (got: '$CALLER_PERM')"
fi

# Read issue metadata
echo "==> Inspecting issue #$ISSUE on $GITHUB_REPO..."
ISSUE_JSON="$(gh api "repos/$GITHUB_REPO/issues/$ISSUE" 2>/dev/null)" || die "failed to read issue #$ISSUE"
ISSUE_STATE="$(jq -r '.state' <<<"$ISSUE_JSON")"
ISSUE_TITLE="$(jq -r '.title' <<<"$ISSUE_JSON")"
mapfile -t ISSUE_LABELS < <(jq -r '.labels[].name' <<<"$ISSUE_JSON")

[ "$ISSUE_STATE" = "open" ] || refuse "issue #$ISSUE is $ISSUE_STATE, must be open"

# R1-2: Inspect labels and refuse invalid/conflicting states
STATUS_LABELS=()
for lbl in "${ISSUE_LABELS[@]}"; do
    [ "$lbl" != "hold" ] || refuse "issue #$ISSUE carries hold label"
    [ "$lbl" != "blocked" ] || refuse "issue #$ISSUE carries blocked label"
    [ "$lbl" != "status:review-stuck" ] || refuse "issue #$ISSUE carries status:review-stuck; humans have taken over and automated state changes are forbidden."
    [ "$lbl" != "status:in-review" ] || refuse "issue #$ISSUE carries status:in-review; active review is in progress."
    if [[ "$lbl" =~ ^status: ]]; then
        STATUS_LABELS+=("$lbl")
    fi
done

if [ "${#STATUS_LABELS[@]}" -gt 1 ]; then
    refuse "issue #$ISSUE carries contradictory status labels (${STATUS_LABELS[*]}); state machine corrupted"
fi

echo "==> Target issue: #$ISSUE · $ISSUE_TITLE"
ISSUE_BODY="$(jq -r '.body // empty' <<<"$ISSUE_JSON")"
if [ -n "$ISSUE_BODY" ]; then
    ISSUE_DESC="$(printf '%s\n' "$ISSUE_BODY" | grep -v '^[[:space:]]*$' | head -n 3 | paste -sd ' ' - || true)"
    if [ -n "$ISSUE_DESC" ]; then
        if [ "${#ISSUE_DESC}" -gt 140 ]; then
            ISSUE_DESC="${ISSUE_DESC:0:137}..."
        fi
        echo "==> Description:  $ISSUE_DESC"
    fi
fi
echo "==> Verified owner authorization: $OWNER_SIGNATURE"

# Helper: re-read hold immediately before writing (D13/D14, fail-closed on API error R2-1)
verify_not_held() {
    local fresh_labels
    fresh_labels="$(gh api "repos/$GITHUB_REPO/issues/$ISSUE" --jq '.labels[].name')" || die "failed to query labels on issue #$ISSUE immediately before write (fail-closed)"
    if grep -q '^hold$' <<<"$fresh_labels"; then
        refuse "issue #$ISSUE carries hold label (re-checked immediately before write)"
    fi
}

# Determine stage transition needs
HAS_IMPLEMENTING=0
for lbl in "${ISSUE_LABELS[@]}"; do
    [ "$lbl" != "status:implementing" ] || HAS_IMPLEMENTING=1
done

if [ "$HAS_IMPLEMENTING" -eq 0 ]; then
    echo "==> Transitioning issue #$ISSUE to status:implementing (owner-authorized fast-track)..."
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "would: remove obsolete intake/authoring labels and add status:implementing"
        echo "would: post fast-track initiation comment to issue #$ISSUE"
    else
        verify_not_held
        # Remove only earlier authoring phase/status labels
        for old_lbl in "intent:new" "status:planning" "status:spec" "status:build"; do
            gh api -X DELETE "repos/$GITHUB_REPO/issues/$ISSUE/labels/$old_lbl" >/dev/null 2>&1 || true
        done
        verify_not_held
        gh api "repos/$GITHUB_REPO/issues/$ISSUE/labels" -f "labels[]=status:implementing" >/dev/null

        # Post authorization comment from file (trusted posting)
        COMMENT_TMP="$(mktemp)"
        echo "Owner-authorized fast-track initiated by @${CALLER_LOGIN:-$REPO_OWNER} (Signature: $OWNER_SIGNATURE): lifecycle stage set to \`status:implementing\` for single-round execution." > "$COMMENT_TMP"
        verify_not_held
        gh api "repos/$GITHUB_REPO/issues/$ISSUE/comments" -F body=@"$COMMENT_TMP" >/dev/null
        rm -f "$COMMENT_TMP"
    fi
else
    echo "==> Issue #$ISSUE is already at status:implementing"
fi

# Locate existing worktree with strict matching (R1-7)
WT_PATH="$(git worktree list --porcelain | awk -v issue="$ISSUE" '
    $1 == "worktree" {
        path = $2
        if (path ~ ("/" issue "(-[^/]+)?$") || path ~ ("/[^/]+-" issue "(-[^/]+)?$")) {
            print path
            exit
        }
    }
')"

if [ -z "$WT_PATH" ]; then
    echo "==> No active worktree found for issue #$ISSUE."
    echo "    Create one using: CLAIM_ACTOR=${AS_PERSONA:-odyssey} CLAIM_SESSION=fast scripts/ops/claim.sh $ISSUE"
    exit 0
fi

echo "==> Active worktree: $WT_PATH"
WT_BRANCH="$(git -C "$WT_PATH" rev-parse --abbrev-ref HEAD)"
echo "==> Branch: $WT_BRANCH"

if [ "$SKIP_PR" -eq 1 ]; then
    echo "==> --no-pr requested. Fast-track setup complete."
    if [ "$NO_DISPATCH" -eq 0 ] && [ -n "$AS_PERSONA" ]; then
        echo "==> Dispatching $AS_PERSONA..."
        "$REPO_ROOT/scripts/ops/work.sh" "$ISSUE" --as "$AS_PERSONA"
    fi
    exit 0
fi

# Preflight: fetch latest origin/main before checking ahead-count and diffs (R1-6)
BASE_REF="origin/main"
if git -C "$WT_PATH" remote get-url origin >/dev/null 2>&1; then
    echo "==> Fetching origin main..."
    git -C "$WT_PATH" fetch origin main >/dev/null 2>&1 || die "failed to fetch origin main"
elif git -C "$WT_PATH" rev-parse --verify main >/dev/null 2>&1; then
    BASE_REF="main"
fi

# Check commits ahead of base using three-dot notation (R1-6, R1-7)
AHEAD_COUNT="$(git -C "$WT_PATH" rev-list --count "$BASE_REF...HEAD")" || die "failed to compute ahead count against $BASE_REF"
echo "==> Commits ahead of $BASE_REF: $AHEAD_COUNT"

if [ "$AHEAD_COUNT" -eq 0 ]; then
    echo "==> No commits ahead of origin/main in $WT_PATH yet."
    echo "    Implement the changes in the worktree, run tests, commit, and re-run fast.sh."
    exit 0
fi

# Check if a PR is already open for this branch (R1-7: honors -R)
EXISTING_PR="$(gh pr list --repo "$GITHUB_REPO" --head "$WT_BRANCH" --json number -q '.[0].number')"
if [ -n "$EXISTING_PR" ]; then
    echo "==> Pull request #$EXISTING_PR is already open for branch $WT_BRANCH:"
    echo "    https://github.com/$GITHUB_REPO/pull/$EXISTING_PR"
    echo ""
    echo "Next steps for independent review:"
    echo "  scripts/ops/work.sh $EXISTING_PR --as argus"
    echo "  scripts/ops/work.sh $EXISTING_PR --as atlas"
    exit 0
fi

# Prepare PR body and check behavior-bearing files for CHANGELOG requirement (R1-3, R1-6)
BEHAVIOR_PATHS_REGEX='^(scripts/|personas/|config/|\.github/workflows/|AGENTS\.md|REVIEW\.md)'
CHANGED_FILES="$(git -C "$WT_PATH" diff --name-only "$BASE_REF...HEAD")"

TOUCHES_BEHAVIOR=0
TOUCHES_CHANGELOG=0
TOUCHES_SPEC=0
while IFS= read -r f; do
    [ -n "$f" ] || continue
    if [[ "$f" =~ $BEHAVIOR_PATHS_REGEX ]]; then
        TOUCHES_BEHAVIOR=1
    fi
    if [ "$f" = "CHANGELOG.md" ]; then
        TOUCHES_CHANGELOG=1
    fi
    if [ "$f" = "docs/SPEC.md" ]; then
        TOUCHES_SPEC=1
    fi
done <<<"$CHANGED_FILES"

if [ "$TOUCHES_BEHAVIOR" -eq 1 ] && [ "$TOUCHES_CHANGELOG" -eq 0 ]; then
    if [ -z "$CHANGELOG_REASON" ]; then
        refuse "behavior-bearing files changed without a CHANGELOG.md update; you must either update CHANGELOG.md or provide an explicit --changelog-reason '<reason>'."
    fi
    CHANGELOG_REASON_CLEAN="$(tr '[:upper:]' '[:lower:]' <<<"${CHANGELOG_REASON//[._-]/ }" | xargs)"
    if [[ "$CHANGELOG_REASON_CLEAN" =~ ^(owner authorized fast track|fast track|urgent|n/a|none|no behavior change|test)$ ]] || [ "${#CHANGELOG_REASON}" -lt 10 ]; then
        refuse "boilerplate changelog reason is not permitted; provide a substantive reason explaining why no changelog entry is needed (minimum 10 characters)."
    fi
fi

if [ "$TOUCHES_SPEC" -eq 0 ] && [ -n "$SPEC_REASON" ]; then
    echo "==> Note: docs/SPEC.md untouched; using provided --spec-reason."
fi

PR_BODY_TMP="$(mktemp)"
trap 'rm -f "$PR_BODY_TMP"' EXIT

cat <<EOF_BODY > "$PR_BODY_TMP"
Owner-authorized ladder compression: combines intent/spec/plan/implement into one round (Refs #$ISSUE) [Signature: $OWNER_SIGNATURE].

$ISSUE_TITLE.

EOF_BODY

if [ "$TOUCHES_BEHAVIOR" -eq 1 ] && [ "$TOUCHES_CHANGELOG" -eq 0 ]; then
    echo "Changelog: none — $CHANGELOG_REASON" >> "$PR_BODY_TMP"
    echo "" >> "$PR_BODY_TMP"
fi

if [ "$TOUCHES_SPEC" -eq 0 ] && [ -n "$SPEC_REASON" ]; then
    echo "Spec-impact: none — $SPEC_REASON" >> "$PR_BODY_TMP"
    echo "" >> "$PR_BODY_TMP"
fi

cat <<EOF_BODY2 >> "$PR_BODY_TMP"
Closes #$ISSUE.
EOF_BODY2

echo "==> Preflight checks on branch $WT_BRANCH using worktree gate scripts..."
# Sanitize check (R1-6: use worktree's own copy, R2-2: fail-closed if missing)
[ -f "$WT_PATH/scripts/ci/sanitize_check.sh" ] || die "missing preflight script: $WT_PATH/scripts/ci/sanitize_check.sh"
echo "--> Running sanitize_check.sh..."
(cd "$WT_PATH" && bash "$WT_PATH/scripts/ci/sanitize_check.sh") || die "sanitize check failed"

# Spec check
[ -f "$WT_PATH/scripts/ci/spec_check.sh" ] || die "missing preflight script: $WT_PATH/scripts/ci/spec_check.sh"
echo "--> Running spec_check.sh..."
(cd "$WT_PATH" && bash "$WT_PATH/scripts/ci/spec_check.sh" "$BASE_REF" "$PR_BODY_TMP") || die "spec check failed"

# Changelog check
[ -f "$WT_PATH/scripts/ci/changelog_check.sh" ] || die "missing preflight script: $WT_PATH/scripts/ci/changelog_check.sh"
echo "--> Running changelog_check.sh..."
(cd "$WT_PATH" && bash "$WT_PATH/scripts/ci/changelog_check.sh" "$BASE_REF" "$PR_BODY_TMP") || die "changelog check failed"

if [ "$DRY_RUN" -eq 1 ]; then
    echo "would: gh pr create --repo $GITHUB_REPO --head $WT_BRANCH --base main --title \"fast-track(#$ISSUE): $ISSUE_TITLE\" --body-file $PR_BODY_TMP"
    echo "==> DRY_RUN=1 — no PR was created."
    exit 0
fi

echo "==> Opening fast-track Pull Request..."
NEW_PR_URL="$(gh pr create --repo "$GITHUB_REPO" --head "$WT_BRANCH" --base main --title "fast-track(#$ISSUE): $ISSUE_TITLE" --body-file "$PR_BODY_TMP")"
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
