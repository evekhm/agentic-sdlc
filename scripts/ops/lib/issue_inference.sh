# Shared issue-number inference for the ops scripts (#454, Argus R1-4).
#
# SOURCED, never executed. It exists because two scripts have to answer
# "which issue does this call belong to, when the caller didn't say?"
# identically: scripts/ops/fast.sh refuses to guess wrong (fail-closed),
# and scripts/ops/digest.sh only ever prints a summary (fail-open) —
# but the inference rule itself, worktree directory name first, then
# git branch name, must be the same rule in both places, or the two
# doors can silently disagree about which issue is "current" (Argus
# R1-4 on PR #455).
#
# Contract for the caller, checked by nothing but stated once here:
#
#   * `git` is on PATH and the caller is inside a git worktree.
#   * infer_issue_from_context() prints the inferred issue number on
#     stdout and returns 0, or prints nothing and returns 1 if neither
#     the worktree directory name nor the branch name yields a number,
#     or returns 1 with a diagnostic on stderr if the two disagree.
#
# Two naming conventions are in play (see AGENTS.md): worktree
# directories are `<actor>-<n>-<slug>` (hyphen before the digits),
# branches are `<actor>/<n>-<slug>` (slash before the digits). The two
# helpers below keep those two anchors distinct on purpose — collapsing
# them into one pattern silently breaks whichever convention doesn't
# match it.

_issue_from_wt_name() {
    local wt_name="$1"
    if [[ "$wt_name" =~ -([0-9]+)(-[^/]*)?$ ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    elif [[ "$wt_name" =~ ^([0-9]+)(-[^/]*)?$ ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi
    return 1
}

_issue_from_branch() {
    local branch="$1"
    if [[ "$branch" =~ /([0-9]+)(-[^/]*)?$ ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    elif [[ "$branch" =~ ^([0-9]+)(-[^/]*)?$ ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi
    return 1
}

# infer_issue_from_context: cross-checks the worktree directory name
# against the branch name (Argus R1-1). Either source alone can be
# stale — a worktree left over from a renamed branch, a branch
# checked out into someone else's worktree directory — so when both
# yield a number and they disagree, this refuses; it never picks
# one silently.
infer_issue_from_context() {
    local wt_top wt_name branch from_wt from_branch
    wt_top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
    from_wt=""
    if [ -n "$wt_top" ]; then
        wt_name="$(basename "$wt_top")"
        from_wt="$(_issue_from_wt_name "$wt_name" || true)"
    fi

    branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    from_branch=""
    if [ -n "$branch" ] && [ "$branch" != "HEAD" ] && [ "$branch" != "main" ]; then
        from_branch="$(_issue_from_branch "$branch" || true)"
    fi

    if [ -n "$from_wt" ] && [ -n "$from_branch" ]; then
        if [ "$from_wt" != "$from_branch" ]; then
            echo "issue inference: worktree name suggests #$from_wt but branch name suggests #$from_branch; refusing to guess" >&2
            return 1
        fi
        echo "$from_wt"
        return 0
    fi

    if [ -n "$from_wt" ]; then
        echo "$from_wt"
        return 0
    fi

    if [ -n "$from_branch" ]; then
        echo "$from_branch"
        return 0
    fi

    return 1
}
