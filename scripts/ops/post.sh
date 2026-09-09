#!/usr/bin/env bash
# The ONE write path to GitHub for an unattended run (#25, D5, D6, D13, D14).
#
#   scripts/ops/post.sh <number> --as <persona> --body-file <path>
#
# Two rules, and this script exists so that neither can be forgotten by
# whoever writes the next duty:
#
#   D13  `hold` is re-read IMMEDIATELY BEFORE the write, not only at
#        dispatch. A review that starts at 14:00 and finishes at 14:04
#        against a pull request a human held at 14:01 is computed and
#        paid for, and then posts nothing. The run is GREEN — exit 0,
#        not an error: the circuit breaker did its job.
#   D14  For a pull request the hold set is the pull request AND every
#        issue it closes, resolved the same way scripts/ops/work.sh
#        resolves a pull request to its issue (scripts/ops/lib/github.sh
#        is that one implementation). The label taxonomy attaches `hold`
#        to issues in practice, so a pull-request-only check leaks past
#        the breaker.
#
# THE BODY COMES FROM A FILE and never from an argument (D6,
# trusted-posting rules 1-2). A model composes a file; a model does not
# compose an API call. A body on the command line is world-readable in
# argv, is mangled by whatever quoting the caller guessed at, and is the
# exact shape of an inline call this repository's posting discipline
# forbids.
#
# GH_TOKEN reaches this script through the environment BY NAME and is
# never printed, written or passed in an argument. `gh` reads it itself;
# nothing here touches its value.
#
# Exit codes:
#   0  posted, or deliberately did not post because `hold` was present
#   1  unusable input (a number that does not resolve, a missing body
#      file, a persona that does not exist), a failed write, or a write
#      the API attributed to an identity other than the one
#      personas/<persona>.yaml names (see "Who actually posted" below)

set -euo pipefail

GITHUB_REPO="${GITHUB_REPO:-${GITHUB_REPOSITORY:-evekhm/agentic-sdlc}}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GITHUB_LIB="$REPO_ROOT/scripts/ops/lib/github.sh"
PERSONA_DIR="$REPO_ROOT/personas"

usage() {
    cat <<'USAGE'
usage: scripts/ops/post.sh <number> --as <persona> --body-file <path>

Posts one comment on <number>, unless `hold` is on it or on any issue it
closes — in which case nothing is posted and the exit is 0.

The body is always a FILE. There is deliberately no --body flag.
USAGE
}

die() { echo "post.sh: $*" >&2; exit 1; }

for cmd in gh jq; do
    command -v "$cmd" >/dev/null || die "$cmd is not installed"
done
[ -r "$GITHUB_LIB" ] || die "cannot read $GITHUB_LIB"
# shellcheck source=lib/github.sh
. "$GITHUB_LIB"

# --- Arguments ----------------------------------------------------------------
NUMBER=""
AS=""
BODY_FILE=""
ADD_LABEL=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --as)
            [ "$#" -ge 2 ] || die "--as needs a persona name"
            AS="$2"; shift 2 ;;
        --as=*) AS="${1#--as=}"; shift ;;
        --body-file)
            [ "$#" -ge 2 ] || die "--body-file needs a path"
            BODY_FILE="$2"; shift 2 ;;
        --body-file=*) BODY_FILE="${1#--body-file=}"; shift ;;
        --add-label)
            [ "$#" -ge 2 ] || { echo "post.sh: --add-label accepts only deep-review on a pull request" >&2; exit 2; }
            ADD_LABEL="$2"; shift 2 ;;
        --add-label=*) ADD_LABEL="${1#--add-label=}"; shift ;;
        --body|--body=*)
            die "the body is always a file: use --body-file <path> (D6)" ;;
        -*) usage >&2; die "unknown flag '$1'" ;;
        *)
            [ -z "$NUMBER" ] || die "one number is one post; got '$NUMBER' and '$1'"
            NUMBER="${1#\#}"; shift ;;
    esac
done
[ -n "$NUMBER" ] || { usage >&2; exit 1; }
case "$NUMBER" in
    ''|*[!0-9]*) die "'$NUMBER' is not an issue or pull-request number" ;;
esac
[ -n "$AS" ] || die "--as <persona> is required: a post has an actor"
case "$AS" in
    *[!a-z-]*) die "--as '$AS' is not a persona name" ;;
esac
[ -f "$PERSONA_DIR/$AS.yaml" ] || die "no persona source at personas/$AS.yaml"

if [ -n "$ADD_LABEL" ] && [ "$ADD_LABEL" != "deep-review" ]; then
    echo "post.sh: --add-label accepts only deep-review on a pull request" >&2
    exit 2
fi

[ -n "$BODY_FILE" ] || [ -n "$ADD_LABEL" ] || die "either --body-file <path> or --add-label <label> is required"
if [ -n "$BODY_FILE" ]; then
    [ -r "$BODY_FILE" ] || die "cannot read the body file $BODY_FILE"
    [ -s "$BODY_FILE" ] || die "the body file $BODY_FILE is empty; there is nothing to post"
fi

# --- The hold set (D14) ---------------------------------------------------------
# The target, plus — for a pull request — every issue it closes. Built
# from the SAME resolver work.sh dispatches on, so the two cannot
# disagree about which issue a pull request belongs to.
target_view=""
target_view="$(gh_json "repos/$GITHUB_REPO/issues/$NUMBER")" \
    || die "cannot read #$NUMBER from $GITHUB_REPO"

is_pr="$(jq -r 'if .pull_request then "pr" else "issue" end' <<<"$target_view")"
if [ -n "$ADD_LABEL" ] && [ "$is_pr" != "pr" ]; then
    echo "post.sh: --add-label accepts only deep-review on a pull request" >&2
    exit 2
fi

HOLD_SET=( "$NUMBER" )
if [ "$is_pr" = "pr" ]; then
    closes="$(closing_refs "$(jq -r '.body // ""' <<<"$target_view")")"
    if [ -n "$closes" ]; then
        # EVERY closing reference, not the first: work.sh refuses to
        # dispatch a pull request that closes two issues, but a hold on
        # either of them still has to stop this write. Suppressing a
        # post is never the ambiguous half of that rule.
        while read -r n; do
            [ -n "$n" ] || continue
            HOLD_SET+=( "$n" )
        done <<<"$closes"
    else
        branch_issue "$NUMBER" 2>/dev/null || true
        [ -z "$BRANCH_ISSUE" ] || HOLD_SET+=( "$BRANCH_ISSUE" )
    fi
fi

# --- Re-read the labels, immediately before the write (D5, D13) -----------------
# This read is the last thing that happens before the POST. Caching it,
# or reusing the labels a dispatcher read minutes ago, is exactly the
# window D13 exists to close.
for n in "${HOLD_SET[@]}"; do
    labels="$(labels_of "$n")" \
        || die "cannot read the labels of #$n; refusing to post without checking hold"
    if has_label "hold"; then
        # Green. The circuit breaker is not an error condition.
        echo "held: #$n carries hold; nothing posted"
        exit 0
    fi
done

# --- The write ------------------------------------------------------------------
# `-F body=@<path>` hands gh the file: the body never becomes an
# argument, a shell variable or a log line. GH_TOKEN is read by gh from
# the environment and is not referenced here at all.
if [ -n "$BODY_FILE" ]; then
    response=""
    response="$(gh api -X POST "repos/$GITHUB_REPO/issues/$NUMBER/comments" \
        -F "body=@$BODY_FILE")" \
        || die "the comment on #$NUMBER was not posted"

    # --- Who actually posted (Argus R1-3) --------------------------------------------
    expected="$(sed -n '/^authority:/,/^[^[:space:]#]/p' "$PERSONA_DIR/$AS.yaml" \
        | sed -n 's/^[[:space:]][[:space:]]*identity:[[:space:]]*//p' \
        | head -1 | tr -d '"' | sed 's/[[:space:]]*$//')"
    actual="$(jq -r '.user.login // ""' <<<"$response")"
    url="$(jq -r '.html_url // ""' <<<"$response")"
    echo "$url"
    if [ -n "$expected" ] && [ -n "$actual" ] && [ "$expected" != "$actual" ]; then
        die "the comment on #$NUMBER was posted by '$actual', but --as says '$AS', whose personas/$AS.yaml names '$expected'; GH_TOKEN does not belong to that persona. Delete $url and re-run with the right credential"
    fi
    echo "posted: #$NUMBER as $AS${actual:+ ($actual)}"
fi

if [ -n "$ADD_LABEL" ]; then
    gh api "repos/$GITHUB_REPO/issues/$NUMBER/labels" \
        -X POST -f "labels[]=deep-review" >/dev/null \
        || die "the label on #$NUMBER was not applied"
    echo "labelled: #$NUMBER with $ADD_LABEL as $AS"
fi
