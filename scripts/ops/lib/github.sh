# Shared GitHub READ helpers for the ops scripts (#25, D14).
#
# SOURCED, never executed. It exists because two scripts have to answer
# "which issue does this pull request belong to?" identically:
# scripts/ops/work.sh dispatches on the answer, and scripts/ops/post.sh
# builds a `hold` set from it (D14 — "the same way work.sh resolves
# it"). Two implementations of that sentence is two answers, and the
# one that disagrees is the one that leaks past the circuit breaker.
#
# Contract for the caller, checked by nothing but stated once here:
#
#   * GITHUB_REPO names <owner>/<repo>.
#   * die() is defined and exits non-zero. It is the caller's, so the
#     message keeps the caller's prefix — the sentences below are the
#     ones scripts/ops/tests/work_test.sh already pins.
#   * `gh` and `jq` are on PATH.
#
# Every call to GitHub goes through gh_json(), so a test can put a stub
# `gh` first on PATH and the whole caller becomes hermetic.

# The ONE read path to GitHub. Every call goes through it, so a test can
# put a stub `gh` first on PATH and the whole caller becomes hermetic.
#
# `--paginate` is the caller's choice, and for a LIST read it is not
# optional: the API answers 30 items per page, so a plain `gh api
# .../comments` returns the OLDEST thirty comments and nothing else. On
# a thread longer than that the last claim is on a page nobody asked
# for, the mutex reads a stale holder — or no holder at all — and
# D5(e) can pass while another session is holding the issue (#51, Atlas
# AT-2). `gh api --paginate` emits one JSON array per page; `jq -s add`
# rejoins them into the single array every caller here expects, and
# `// []` keeps a thread with no comments an empty array rather than
# null. `per_page=100` is the API's maximum and only reduces the number
# of round trips — correctness comes from `--paginate`, not from it.
gh_json() { # <api-path> [--paginate]
    if [ "${2:-}" = "--paginate" ]; then
        gh api --paginate "$1?per_page=100" | jq -s 'add // []'
    else
        gh api "$1"
    fi
}

# closing_refs <pr-body>  — distinct same-repo issue numbers this body
# closes, one per line, sorted.
#
# Every closing keyword GitHub honours, case-insensitively: `Fixes #205`
# closes #205 on merge whether or not a script reads the word, and a
# reader that only knows `closes` sends the session — or the hold check
# — to the wrong unit of work. Cross-repo `owner/repo#9` and URL forms
# deliberately do not match: they close an issue that is not in this
# tracker.
closing_refs() {
    grep -Eoi '\b(close[sd]?|fix(es|ed)?|resolve[sd]?)[[:space:]]+#[0-9]+' <<<"$1" \
        | grep -Eo '[0-9]+$' | sort -un || true
}

# issue_refs <pr-body> — distinct same-repo issue numbers extracted from
# closing keywords and reference mentions, one per line, sorted.
issue_refs() {
    grep -Eoi '(^|[^[:alnum:]])(refs?|references?|close[sd]?|fix(es|ed)?|resolve[sd]?)[[:space:]]+#[0-9]+' <<<"$1" \
        | grep -Eo '[0-9]+$' | sort -un || true
}

# branch_issue <pr-number>
#   sets BRANCH_ISSUE  the issue number in an <actor>/<n>-<slug> head
#                      branch, or empty when the branch does not match
#        BRANCH_REF    that head branch, or empty
#        PR_HEAD_REPO  the full name of the head repository, or empty
#   returns non-zero only when the pull request cannot be READ
#
# The fallback when a pull-request body carries no closing keyword; one
# implementation of the pattern, because a hold check that read the
# branch differently from the dispatcher would gate a different issue.
#
# It sets variables instead of printing the number because the caller
# needs BOTH the number and the branch it came from — a message saying
# "resolved via the branch name" with the name missing is the failure
# this shape avoids, and `x="$(branch_issue …)"` would run the function
# in a subshell where the second assignment is thrown away.
branch_issue() {
    local pr_view head_ref
    BRANCH_ISSUE=""
    BRANCH_REF=""
    PR_HEAD_REPO=""
    pr_view="$(gh_json "repos/$GITHUB_REPO/pulls/$1")" || return 1
    head_ref="$(jq -r '.head.ref // ""' <<<"$pr_view")"
    PR_HEAD_REPO="$(jq -r '.head.repo.full_name // ""' <<<"$pr_view")"
    if [[ "$head_ref" =~ ^[a-z][a-z-]*/([0-9]+)- ]]; then
        BRANCH_REF="$head_ref"
        BRANCH_ISSUE="${BASH_REMATCH[1]}"
    fi
}

# resolve_issue <number>
#   sets ISSUE          the issue that IS the unit of work
#        RESOLVED_VIA   how, when the input was a pull request; empty otherwise
#        ISSUE_JSON     the issue's API response
#        IS_PR          1 when the input number was a pull request, else 0
#        PR_JSON        the input's own API response when IS_PR=1
#        PR_HEAD_REPO   the head repository of the input when IS_PR=1, empty when it could not be read
#   returns 2 when the input is a pull request that cannot be resolved to an issue
#
# A pull request is not the unit of work; the issue is (#36, D9). A
# closing keyword and a same-repo `#<n>` in the body first, then the
# <actor>/<n>-<slug> branch name, then give up: guessing which issue a
# pull request belongs to is how two sessions end up on one issue.
resolve_issue() {
    local number="$1" view closes closes_count
    ISSUE="$number"
    RESOLVED_VIA=""
    ISSUE_JSON=""
    IS_PR=0
    PR_JSON=""
    PR_HEAD_REPO=""

    if ! view="$(gh_json "repos/$GITHUB_REPO/issues/$number")"; then
        die "cannot read #$number from $GITHUB_REPO"
    fi
    if [ "$(jq -r 'if .pull_request then "pr" else "issue" end' <<<"$view")" != "pr" ]; then
        ISSUE_JSON="$view"
        return 0
    fi

    IS_PR=1
    PR_JSON="$view"
    # #207 D1(c): the head repository is a conjunct of the review-dispatch
    # predicate, and this is the read that already answers it on the
    # fallback path below. Non-fatal here: a pulls read that fails leaves
    # PR_HEAD_REPO empty, which is not a same-repository head, and the
    # fallback's own `[ -n "$BRANCH_ISSUE" ] || return 2` signals an
    # unresolvable pull request to the caller (#216).
    branch_issue "$number" || true
    local body_refs branch_refs union union_count
    closes="$(closing_refs "$(jq -r '.body // ""' <<<"$view")")"
    closes_count=0
    [ -z "$closes" ] || closes_count="$(grep -c . <<<"$closes")"
    if [ "$closes_count" -gt 1 ]; then
        die "PR #$number closes more than one issue: $(sed 's/^/#/' <<<"$closes" \
            | tr '\n' ' ')— dispatch one of them by its own number"
    fi

    body_refs="$(issue_refs "$(jq -r '.body // ""' <<<"$view")")"
    branch_refs=""
    [ -z "$BRANCH_ISSUE" ] || branch_refs="$BRANCH_ISSUE"
    union="$(printf '%s\n%s\n' "$body_refs" "$branch_refs" | grep -E '^[0-9]+$' | sort -un || true)"
    union_count=0
    [ -z "$union" ] || union_count="$(grep -c . <<<"$union")"

    if [ "$union_count" -gt 1 ]; then
        die "PR #$number links more than one issue: $(sed 's/^/#/' <<<"$union" | tr '\n' ' ')— dispatch one of them by its own number"
    fi
    if [ "$union_count" -eq 0 ]; then
        return 2
    fi

    ISSUE="$union"
    if grep -qxE "$ISSUE" <<<"$closes"; then
        RESOLVED_VIA="Closes #$ISSUE in the body"
    elif grep -qxE "$ISSUE" <<<"$body_refs"; then
        RESOLVED_VIA="Refs #$ISSUE in the body"
    else
        RESOLVED_VIA="the branch name $BRANCH_REF"
    fi
    if ! ISSUE_JSON="$(gh_json "repos/$GITHUB_REPO/issues/$ISSUE")"; then
        die "PR #$number resolves to #$ISSUE, which cannot be read"
    fi
}

# labels_of <number>  — one label name per line, read FRESH.
# Never cached by this function: D13's whole content is that the labels
# a write is gated on are the labels at the moment of the write.
labels_of() {
    local view
    view="$(gh_json "repos/$GITHUB_REPO/issues/$1")" || return 1
    jq -r '.labels[].name' <<<"$view"
}

# has_label <label>  — against the caller's own $labels, one name per
# line. Kept as a closure over that variable rather than taking the list
# as an argument: that is how scripts/ops/work.sh has always spelled it,
# and this extraction is behaviour-preserving or it is wrong.
has_label() {
    grep -Fxq "$1" <<<"$labels"
}
