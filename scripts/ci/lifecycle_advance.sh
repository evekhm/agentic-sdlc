#!/usr/bin/env bash
# The deterministic stage advancer (#4), run by
# .github/workflows/lifecycle.yml on every push to main and runnable
# locally with the same command CI runs.
#
# INTENT.md's lifecycle says the merge IS the state transition. This
# script is the part that makes the transition visible: it reads what a
# push ADDED under intent/<issue>-<slug>/ and mirrors the gate that
# merge passed into the issue's status:* label, plus one comment saying
# what the next stage owes. It decides nothing. There is no model call
# here, no API key, no prompt — a merged path and a `Status:` line are
# the whole input, which is why the same push always produces the same
# labels.
#
# One rung of the ladder owes no artifact: the implement rung's output
# is code, so it advances on a merged PULL REQUEST rather than on a
# merged file (#57, D1). Which rung does which is the `advances_on`
# column of personas/lifecycle.json, read the same way everything else
# here is; the pull requests of a range are found through
# `gh api --paginate repos/<repo>/commits/<sha>/pulls` over EVERY commit
# of the range in `--topo-order --reverse`, and a merged pull request is
# kept only when its `merge_commit_sha` is contained in that range.
#
# Which merged pull request is THE implementing one is a separate
# question from "was one merged at all", and #72 is the defect of
# answering only the second (#57, D15). A pull request is the
# implementing pull request of issue <n> when all three hold:
#   (1) its head branch parses as `<actor>/<n>-<slug>`;
#   (2) its own file list — `repos/<repo>/pulls/<n>/files`, the diff
#       GitHub computes from the pull request's own refs, so it is the
#       same set under a merge-commit, a squash and a rebase merge —
#       changes at least one path outside `intent/`;
#   (3) exactly one `intent/<n>-*/` directory exists in the <after>
#       tree and <slug> is its slug.
# A pull request from a fork never contends at all (D16), and a branch
# that parses but misses the slug is announced as a near miss rather
# than by silence (D17). There is no closing-keyword fallback: the
# implementing pull request is precisely the one that must NOT carry a
# closing keyword for its issue (D2 as amended, D9).
#
# WHICH label each merged artifact advances to, and the line posted when
# it does, are not written here (#36, D2). They are read from
# personas/lifecycle.json — the one table the compiler renders into
# prompts and scripts/ops/work.sh dispatches against — matched on the
# `artifact` column. Read that file for the ladder; this script only
# applies it, with one exception it owns: a merged spec.md whose status
# line is not `Status: Approved` advances nothing (see the Draft
# override below), because that is the ladder refusing to move rather
# than a rung of it.
#
# What this script writes: the `status:*` ladder end to end, up to and
# including `status:in-review`, and the removal of `intent:new` with the
# first status it writes — an item with a stage is an item somebody
# triaged (#57, D7).
#
# What it deliberately does NOT write: the `review:1..3` counter and
# `status:review-stuck`, which are review state and belong to the review
# automation (#8, #9) — a stage advancer that also guessed at review
# state would be two state machines racing over one label — and nothing
# here ever CLOSES an issue. The ladder ends at review; the human closes
# the item (D8).
#
# Invariants (#4, intent/4-labels/spec.md):
#   hold is absolute      an issue carrying `hold` is skipped, always,
#                         first — before state, before labels, before
#                         anything else the per-issue loop does. D9's
#                         closed-at-merge red is checked AFTER it, so a
#                         closed issue that also carries `hold` is one
#                         log line and exit 0, not a counted failure
#                         (#57, D5; #73 D9 amended, F4).
#                         The circuit breaker is worth nothing if
#                         automation gets a vote on it.
#   one status:*          more than one status:* label is a corrupted
#                         state machine: the script says so, applies
#                         `hold`, and stops touching that issue.
#   no backward transition a transition never walks down the ladder: the
#                         target must outrank the issue's current
#                         status:* label. Below or unranked is a no-op
#                         with one `::warning::`; equal is a plain log
#                         line; neither is a counted failure (#57, D19).
#   blocked is advisory    `blocked` is never read and never written by
#                         this script and never suppresses a transition
#                         — only `hold` halts it. Refusal on `blocked`
#                         lives with the actors, at dispatch (#57, D20).
#   furthest transition   a push adding two or three of the triple for
#                         one issue (bootstrap compression) applies the
#                         furthest transition only, in one comment.
#   idempotent writes     a label already present is not re-added; a
#                         comment whose marker is already in the thread
#                         is not re-posted. Re-running a range is a
#                         no-op, which is what makes a manual re-run
#                         safe after a partial failure.
#   draft does not advance a merged spec.md without `Status: Approved`
#                         warns and leaves the stage where it was.
#                         "Nothing is dispatched against a Draft."
#   merge is a rung       a pull request whose merge landed IN the pushed
#                         range and which is the implementing pull
#                         request of an issue whose current label is the
#                         `advances_on: "merge"` row advances that issue.
#                         A push carrying no such pull request advances
#                         nothing — there is no second trigger.
#   a near miss is loud   a merged pull request that names an issue at
#                         the merge rung but is not its implementing one
#                         gets one `::warning::` line, never silence and
#                         never a red (#57, D17).
#   closed at merge is red a closed issue still carrying the merge rung's
#                         label, with its implementing pull request
#                         merged in the range, is a counted failure and
#                         NOTHING is written to it: that pull request
#                         carried a closing keyword it must not carry,
#                         or a human closed it directly (#57, D9).
#   no read fails open     every lookup this script makes is checked. A
#                         failed per-issue read is a counted failure
#                         naming the issue; a failed range walk ends the
#                         run before any issue is read. DRY_RUN=1
#                         suppresses writes and nothing else — it never
#                         changes what a read answers (#57, D21).
#
# Usage:
#   scripts/ci/lifecycle_advance.sh <before-sha> <after-sha>
#   DRY_RUN=1 scripts/ci/lifecycle_advance.sh <before-sha> <after-sha>
#
# DRY_RUN=1 performs no writes: every gh mutation prints instead of
# running. Reads still happen, so the live guards (hold, multiple
# status labels, an already-posted comment) are exercised as they would
# be for real; a read that fails is reported exactly as it would be for
# real, never substituted (#57, D21) — the advancer is the same program
# under DRY_RUN=1 on every read path.
#
# Fail-closed on inputs, fail-soft per issue: an unusable range is an
# error, but one unreachable issue does not stop the others — it is
# logged, and the run exits 1 at the end so the push shows red.
#
# Exit 0 = every hit was processed or deliberately skipped;
# exit 1 = bad input, or at least one issue failed to process.

set -euo pipefail

GITHUB_REPO="${GITHUB_REPO:-${GITHUB_REPOSITORY:-evekhm/agentic-sdlc}}"
DRY_RUN="${DRY_RUN:-0}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

die() { echo "::error::lifecycle_advance: $*" >&2; exit 1; }
log() { echo "$*"; }

FAILURES=0
fail_issue() { # message — one issue lost, the run continues and ends red
  echo "::error::lifecycle_advance: $*" >&2
  FAILURES=$((FAILURES + 1))
}

# --- Preflight ----------------------------------------------------------------
[ "$#" -eq 2 ] || { echo "usage: $0 <before-sha> <after-sha>" >&2; exit 1; }
BEFORE="$1"
AFTER="$2"

for cmd in git gh jq; do
    command -v "$cmd" >/dev/null || die "$cmd is not installed"
done

git rev-parse --git-dir >/dev/null 2>&1 || die "not a git repository"

# The label <-> stage ladder is DATA, not a case statement in this file
# (#36, D2). Which label a merged artifact advances to, and the line
# posted when it does, are read from the one table every actor reads —
# the compiler renders it into prompts and scripts/ops/work.sh dispatches
# against it. A second copy here would be the drift this file exists to
# prevent.
LIFECYCLE_JSON="$(git rev-parse --show-toplevel)/personas/lifecycle.json"
[ -r "$LIFECYCLE_JSON" ] || die "cannot read $LIFECYCLE_JSON"

# A push that CREATED the branch reports an all-zero 'before'. There is
# no range to read, and treating it as one would diff against the empty
# tree and re-announce the entire history.
[ -n "$BEFORE" ] && [ -n "$AFTER" ] || die "before-sha and after-sha are required and must not be empty"
case "$BEFORE" in
    *[!0]*) ;;
    *) log "==> before-sha is all zeros (branch creation) — no range to read"; exit 0;;
esac

git cat-file -e "${BEFORE}^{commit}" 2>/dev/null \
    || die "before-sha $BEFORE is not a commit in this checkout (needs fetch-depth: 0)"
git cat-file -e "${AFTER}^{commit}" 2>/dev/null \
    || die "after-sha $AFTER is not a commit in this checkout"

# --- What the push added ------------------------------------------------------
# ADDED only: a later edit to a spec.md is not a gate crossing, and
# re-announcing one would spam the issue on every typo fix.
if ! added="$(git diff --name-status --diff-filter=A "$BEFORE".."$AFTER")"; then
    die "git diff --diff-filter=A $BEFORE..$AFTER failed; the pushed range is unknown"
fi

declare -A BEST_RANK   # issue -> rank of the furthest stage added
declare -A BEST_STAGE  # issue -> that stage's name
declare -A BEST_PATH   # issue -> that stage's file path
declare -A ALL_FILES   # issue -> space-separated basenames added
declare -A MERGE_PR    # issue -> the implementing pull request number (below)
declare -A MERGE_SHA   # issue -> that pull request's merge_commit_sha
declare -A MERGE_RANK  # issue -> that sha's index in the ordered range (D15)
declare -A SEEN_PR     # pull request number -> already examined in this range
declare -A NEAR_PR     # issue -> the near-miss pull request number (D17)
declare -A NEAR_HEAD   # issue -> that pull request's head branch
declare -A NEAR_EXPECT # issue -> the dispatch branch D15 expected instead

# Two discovery steps now feed ONE loop: files added under
# intent/<issue>-<slug>/ and pull requests merged in the range. The list
# of issues to process is a plain newline-delimited string and the count
# is a plain counter, deliberately — `${#arr[@]}` on a never-assigned
# associative array trips `set -u`'s unbound-variable check, and the
# merge path can leave BEST_STAGE entirely empty.
CANDIDATES=""
NEAR_LIST=""
n_candidates=0
n_near=0
while IFS=$'\t' read -r _status path; do
    [ -n "${path:-}" ] || continue
    [[ "$path" =~ ^intent/([0-9]+)-[^/]+/(intent|spec|plan)\.md$ ]] || continue
    # 10# so a zero-padded folder (intent/04-…) is decimal, not octal.
    issue="$((10#${BASH_REMATCH[1]}))"
    stage="${BASH_REMATCH[2]}"
    # Rank = position in the ladder's artifact column, so "furthest
    # transition wins" is the file's ordering and not a second one here.
    # An artifact the table does not name ranks 0 and never wins.
    rank="$(jq -r --arg a "$stage.md" \
        '([.stages[].artifact] | index($a) // -1) + 1' "$LIFECYCLE_JSON")"
    if [ -z "${ALL_FILES[$issue]:-}" ]; then
        n_candidates=$((n_candidates + 1))
        CANDIDATES="${CANDIDATES}${issue}"$'\n'
    fi
    ALL_FILES[$issue]="${ALL_FILES[$issue]:-}${ALL_FILES[$issue]:+ }${stage}.md"
    if [ "$rank" -gt "${BEST_RANK[$issue]:-0}" ]; then
        BEST_RANK[$issue]="$rank"
        BEST_STAGE[$issue]="$stage"
        BEST_PATH[$issue]="$path"
    fi
done <<<"$added"

# --- What the push merged -----------------------------------------------------
# The implement rung owes no artifact — what it owes is code — so the
# event that ends it is a merged pull request (D1). EVERY commit of the
# range is walked, not just its first parents: a pull request merged into
# a landing branch that later lands on the trunk reaches main on a second
# parent, and #42 — #35's own implementing pull request — is exactly that
# shape in this repository's history (D1 as amended, Argus F2).
#
# The order is `--topo-order --reverse`, which is a TOTAL order on the
# range containing each commit exactly once. Once the walk stopped being
# first-parent the range is a graph, so "oldest first" had to be given a
# definition; this one is deterministic for a given DAG, and the index of
# a commit in it is the integer D15's second-candidate rule ranks on.
#
# D21(b): materialise, check, then loop — matching the `git diff
# --diff-filter=A` guard above. An unchecked process substitution here
# would let a failed walk report zero candidates and exit 0; this ends
# the run before any issue is read, the same posture the artifact
# read already has.
if ! range_walk="$(git rev-list --topo-order --reverse "$BEFORE..$AFTER")"; then
    die "range walk (git rev-list --topo-order --reverse $BEFORE..$AFTER) failed; the pushed range is unknown"
fi
RANGE_SHAS=()
while read -r sha; do
    [ -n "$sha" ] || continue
    RANGE_SHAS+=("$sha")
done <<<"$range_walk"

declare -A RANGE_INDEX  # commit sha -> its position in that total order
range_pos=0
for sha in ${RANGE_SHAS[@]+"${RANGE_SHAS[@]}"}; do
    RANGE_INDEX["$sha"]="$range_pos"
    range_pos=$((range_pos + 1))
done

# D15 conjunct (3) reads the $AFTER TREE, never the checkout, so a
# historical range replays the same way on a laptop as it did in CI.
# One `git ls-tree` per issue number, memoised: a range can report the
# same pull request on many commits.
declare -A FOLDER_N     # issue -> how many intent/<issue>-*/ directories
declare -A FOLDER_SLUG  # issue -> the slug of the one directory, if one
declare -A FOLDER_LIST  # issue -> all of them, for the failure message
intent_folders() { # <issue>
    local n="$1" names
    [ -z "${FOLDER_N[$n]+set}" ] || return 0
    names="$(git ls-tree -d --name-only "${AFTER}:intent" 2>/dev/null \
               | grep -E "^0*${n}-" || true)"
    if [ -z "$names" ]; then
        FOLDER_N[$n]=0; FOLDER_SLUG[$n]=""; FOLDER_LIST[$n]=""
        return 0
    fi
    FOLDER_N[$n]="$(grep -c . <<<"$names")"
    FOLDER_LIST[$n]="$(sed 's|^|intent/|;s|$|/|' <<<"$names" | tr '\n' ' ')"
    FOLDER_SLUG[$n]="$(sed -E "s/^0*${n}-//" <<<"$names" | head -1)"
}

# D15 conjunct (2). The pull request's OWN file list, from the API —
# the three-dot diff GitHub computes from its own refs, so it is the
# same set of paths under a merge-commit, a squash and a rebase merge.
# `git diff <msha>^ <msha>` is not: on a rebase merge `<msha>^` is the
# pull request's own second-to-last commit, and the plan sync AGENTS.md
# requires would then be the whole diff (R2-1). At least one path
# outside `intent/` is what separates an implementation from a plan or
# spec amendment. `--paginate` for the same reason the commits read
# carries it (#100).
#
# Sets PR_OUTSIDE to the first such path. 0 = there is one; 1 = the
# list never leaves `intent/`; 2 = the answer is UNREADABLE, which the
# caller makes red — an unparseable payload is not a fact about the
# pull request, and the sibling commits/pulls read is already red on
# it (R1-3, AT-2). It is a function because the near-miss path must
# consult it too, before recording (R1-2).
#
# D15 conjunct (2), corrected (#73 Argus R2-2, R1-4 ≡ Atlas AT-1). The
# answer is trusted only from a payload that PARSES AS A JSON ARRAY: a
# non-zero exit, an empty body, a body that will not parse, or a body
# that parses as anything other than an array (`{}`) is return 2 — the
# same counted failure as an outright read error, never the "changes
# nothing outside intent/" answer. A well-formed `[]` IS that answer
# and stays silent: a pull request that changes nothing changes nothing
# outside `intent/` either.
PR_OUTSIDE=""
pr_outside_intent() { # <pull-request-number>
    local raw list
    PR_OUTSIDE=""
    raw="$(gh api --paginate "repos/$GITHUB_REPO/pulls/$1/files" 2>/dev/null)" || return 2
    [ -n "$raw" ] || return 2
    jq -e 'type == "array"' <<<"$raw" >/dev/null 2>&1 || return 2
    list="$(jq -r '.[].filename' <<<"$raw" 2>/dev/null)" || return 2
    PR_OUTSIDE="$(printf '%s\n' "$list" | grep -vE '^intent/' | grep -v '^$' | head -1 || true)"
    [ -n "$PR_OUTSIDE" ]
}

for sha in ${RANGE_SHAS[@]+"${RANGE_SHAS[@]}"}; do
    # `--paginate`: a commit can belong to more than one page of pull
    # requests and the default page is 30 (#100). jq reads the
    # concatenated pages as a stream of arrays, so `.[]` still walks
    # every object.
    if ! prs_raw="$(gh api --paginate "repos/$GITHUB_REPO/commits/$sha/pulls" 2>/dev/null)"; then
        fail_issue "cannot list pull requests for $sha"
        continue
    fi
    # Merged only. The base branch is deliberately NOT filtered on: the
    # trunk test is containment of the merge commit in this range, below,
    # which holds identically for a merge-commit, a squash and a rebase
    # merge and does not care what branch the pull request merged into
    # on its way here (D1 as amended).
    if ! prs="$(jq -c '.[] | select(.merged_at != null)
                     | {number,
                        head: .head.ref,
                        repo: (.head.repo.full_name // ""),
                        msha: (.merge_commit_sha // "")}' <<<"$prs_raw")"; then
        fail_issue "unreadable pull request list for $sha"
        continue
    fi
    while IFS= read -r pr; do
        [ -n "$pr" ] || continue
        pr_number="$(jq -r '.number' <<<"$pr")"
        # One pull request can be reported for several commits of the
        # range; examine it once.
        [ -z "${SEEN_PR[$pr_number]:-}" ] || continue
        SEEN_PR[$pr_number]=1
        pr_head="$(jq -r '.head' <<<"$pr")"
        pr_repo="$(jq -r '.repo' <<<"$pr")"
        pr_msha="$(jq -r '.msha' <<<"$pr")"

        # D16, the fork gate, BEFORE the identity test: on a fork the
        # head branch is a string authored outside this repository, and
        # D15 would otherwise read it as a claim about which issue to
        # label. Quiet, because a merged fork pull request is a
        # legitimate event this ladder has no rung for — but logged by
        # number, so the skip is findable from the run.
        if [ "$pr_repo" != "$GITHUB_REPO" ]; then
            log "    pull request #$pr_number is from a fork (${pr_repo:-head repository deleted}) — no merge candidate"
            continue
        fi

        # D15 conjunct (1). `0*` then `10#` so odyssey/0999- and
        # odyssey/999- key one issue and no zero-padded string reaches a
        # comparison (AT-14). No `<actor>` capture: no conjunct reads it.
        [[ "$pr_head" =~ ^[a-z][a-z-]*/0*([0-9]+)-(.+)$ ]] || {
            log "    pull request #$pr_number (\`$pr_head\`) is not on an issue dispatch branch — no merge candidate"
            continue
        }
        resolved="$((10#${BASH_REMATCH[1]}))"
        pr_slug="${BASH_REMATCH[2]}"

        # The trunk test (D1 as amended): the merge is an event of THIS
        # range when its merge_commit_sha is in the range. A sha the
        # checkout does not contain is a counted failure naming the pull
        # request, never a silent drop — `fetch-depth: 0` is this
        # workflow's stated requirement and a shallow clone is the
        # likeliest, not the only, cause.
        if [ -z "$pr_msha" ] || ! git cat-file -e "${pr_msha}^{commit}" 2>/dev/null; then
            fail_issue "pull request #$pr_number reports merge commit ${pr_msha:-<none>}, which this checkout does not contain — re-run the range from a full clone (fetch-depth: 0)"
            continue
        fi
        pr_msha="$(git rev-parse "${pr_msha}^{commit}")"
        merge_pos="${RANGE_INDEX[$pr_msha]:-}"
        if [ -z "$merge_pos" ]; then
            log "    pull request #$pr_number merged as ${pr_msha:0:12}, which is outside $BEFORE..$AFTER — no merge candidate"
            continue
        fi

        # D15 conjunct (3), the cheap local one, before the extra API
        # read. Zero folders yields no candidate and no near miss: by
        # D18 the merge rung cannot legitimately reach such an issue.
        intent_folders "$resolved"
        if [ "${FOLDER_N[$resolved]}" -eq 0 ]; then
            log "    pull request #$pr_number names #$resolved, which has no intent/$resolved-*/ directory at ${AFTER:0:12} — no merge candidate"
            continue
        fi
        if [ "${FOLDER_N[$resolved]}" -gt 1 ]; then
            fail_issue "#$resolved has more than one intent folder at ${AFTER:0:12} — ${FOLDER_LIST[$resolved]}— the slug of pull request #$pr_number cannot be checked against a corrupted state"
            continue
        fi
        if [ "$pr_slug" != "${FOLDER_SLUG[$resolved]}" ]; then
            # D17(a) excludes "a merge whose file list never leaves
            # `intent/` — a plan or spec amendment landing while the
            # issue waits at status:implementing". That exclusion is
            # only real if the file list is consulted before the near
            # miss is recorded, so the slug-mismatch path pays for the
            # conjunct-(2) read here (R1-2). No other path does.
            conj2=0; pr_outside_intent "$pr_number" || conj2=$?
            if [ "$conj2" -eq 2 ]; then
                fail_issue "cannot read the file list of pull request #$pr_number; whether it is #$resolved's implementation is unknown"
                continue
            fi
            if [ "$conj2" -eq 1 ]; then
                log "    pull request #$pr_number (\`$pr_head\`) changes nothing outside intent/ — ordinary intent traffic for #$resolved, no merge candidate and no near miss"
                continue
            fi
            # D17, the near miss. NOT a candidate: it must never reach
            # D5's guard chain (which writes `hold`) or D9's red. It
            # buys exactly one read-only issue view and at most one
            # ::warning:: line, after the per-issue loop.
            if [ -z "${NEAR_PR[$resolved]:-}" ]; then
                n_near=$((n_near + 1))
                NEAR_LIST="${NEAR_LIST}${resolved}"$'\n'
            fi
            NEAR_PR[$resolved]="$pr_number"
            NEAR_HEAD[$resolved]="$pr_head"
            NEAR_EXPECT[$resolved]="${pr_head%%/*}/${resolved}-${FOLDER_SLUG[$resolved]}"
            log "    pull request #$pr_number (\`$pr_head\`) is not #$resolved's dispatch branch — no merge candidate, near miss recorded"
            continue
        fi

        # D15 conjunct (2), the last test and the only remote one.
        conj2=0; pr_outside_intent "$pr_number" || conj2=$?
        if [ "$conj2" -eq 2 ]; then
            fail_issue "cannot read the file list of pull request #$pr_number; whether it is #$resolved's implementation is unknown"
            continue
        fi
        if [ "$conj2" -eq 1 ]; then
            log "    pull request #$pr_number changes nothing outside intent/ — not #$resolved's implementation, no merge candidate"
            continue
        fi

        if [ -z "${BEST_STAGE[$resolved]:-}${MERGE_PR[$resolved]:-}" ]; then
            n_candidates=$((n_candidates + 1))
            CANDIDATES="${CANDIDATES}${resolved}"$'\n'
        fi
        # Two accepted pull requests for one issue in one range is a
        # legitimate landing shape, not a failure: the one whose merge
        # commit is LATER in the ordered range wins (D15). Discovery
        # order is not used — a re-created dispatch branch can branch
        # from an older base and still merge last.
        if [ -n "${MERGE_PR[$resolved]:-}" ] && [ "$merge_pos" -le "${MERGE_RANK[$resolved]}" ]; then
            log "    pull request #$pr_number is #$resolved's implementation but merged before #${MERGE_PR[$resolved]} — superseded"
            continue
        fi
        # PROVISIONAL. The `advances_on` gate needs the issue's current
        # label, which is only known after the `gh issue view` below;
        # the per-issue loop accepts or discards this candidate.
        MERGE_PR[$resolved]="$pr_number"
        MERGE_SHA[$resolved]="$pr_msha"
        MERGE_RANK[$resolved]="$merge_pos"
    done <<<"$prs"
done

# The FAILURES conjunct is load-bearing: a failed lookup can be the only
# event in a range, and an unconditional `exit 0` here would swallow it.
# So can a near miss (D17), whose whole point is that it is announced.
# With no candidate but one of those recorded, execution falls through an
# empty loop to the near-miss report and the FAILURES check at the end.
if [ "$n_candidates" -eq 0 ] && [ "$FAILURES" -eq 0 ] && [ "$n_near" -eq 0 ]; then
    log "==> nothing to advance in $BEFORE..$AFTER — no intent/<issue>-<slug>/{intent,spec,plan}.md added and no implementing pull request found"
    exit 0
fi

log "==> $GITHUB_REPO · range ${BEFORE:0:12}..${AFTER:0:12} · $n_candidates issue(s) with a gate crossing"
if [ "$DRY_RUN" = "1" ]; then
    log "==> DRY_RUN=1 — no write will be executed"
fi

# --- gh wrappers --------------------------------------------------------------
COMMENT_HEADER="_Posted by \`.github/workflows/lifecycle.yml\` (#4) — deterministic, no model call. \
This workflow writes the \`status:*\` ladder up to and including \`status:in-review\`, and clears \
\`intent:new\` with the first status it writes. The \`review:1..3\` counter and \
\`status:review-stuck\` are review state and belong to the review automation (#8/#9)._"

post_comment() { # issue-number body
    local n="$1" body="$2" f
    if [ "$DRY_RUN" = "1" ]; then
        log "    DRY-RUN gh issue comment $n --repo $GITHUB_REPO --body-file - <<'BODY'"
        printf '%s\n' "$body" | sed 's/^/    | /'
        log "    BODY"
        return 0
    fi
    f="$(mktemp)"
    printf '%s\n' "$body" >"$f"
    if gh issue comment "$n" --repo "$GITHUB_REPO" --body-file "$f" >/dev/null; then
        rm -f "$f"
        log "    commented on #$n"
        return 0
    fi
    rm -f "$f"
    return 1
}

edit_labels() { # issue-number add-csv remove-csv (either may be empty)
    local n="$1" add="$2" remove="$3"
    local -a args=("issue" "edit" "$n" "--repo" "$GITHUB_REPO")
    if [ -n "$add" ]; then args+=("--add-label" "$add"); fi
    if [ -n "$remove" ]; then args+=("--remove-label" "$remove"); fi
    if [ -z "$add" ] && [ -z "$remove" ]; then
        log "    labels already correct on #$n — no write"
        return 0
    fi
    if [ "$DRY_RUN" = "1" ]; then
        log "    DRY-RUN gh ${args[*]}"
        return 0
    fi
    gh "${args[@]}" >/dev/null || return 1
    log "    labels on #$n: +[${add:-}] -[${remove:-}]"
}

# --- loop ledger (#64 D13, D22) ------------------------------------------------
# One container comment per issue, `<!-- loop-ledger:<n> -->` ...
# `<!-- loop-ledger-end -->`, read only when a trusted writer posted it
# (D22): the merge actor App or github-actions[bot]. Three row kinds and
# no others — dispatch (rung entered, merged head, event, pr, at, cost),
# terminal (the review rung), refusal:<reason>. A row that will not
# parse makes the whole ledger unreadable, and unreadable is never
# absent. The same reader lives in scripts/ci/merge_gate.sh; D19 permits
# no new shared file.
MERGE_ACTOR="${MERGE_ACTOR_LOGIN:-evekhm-merge-actor-app[bot]}"
TRUSTED_WRITERS="$(jq -nc --arg a "$MERGE_ACTOR" '[$a, "github-actions[bot]"]')"
LEDGER_ROW_RE='^<!-- loop-ledger-row: (dispatch|terminal|refusal:[a-z-]+) rung:[0-9]+ head-oid:[0-9a-f]{40}( [a-z-]+:[^ ]+)* -->$'
LEDGER_ID=""; LEDGER_BODY=""; LEDGER_ROWS=""

read_ledger() { # <issue> — sets LEDGER_*; returns 1 unreadable thread, 2 unparseable row
    local n="$1" all mark any ok
    LEDGER_ID=""; LEDGER_BODY=""; LEDGER_ROWS=""
    all="$(gh api --paginate "repos/$GITHUB_REPO/issues/$n/comments?per_page=100" 2>/dev/null | jq -s 'add // []')" || return 1
    jq -e 'type == "array"' <<<"$all" >/dev/null 2>&1 || return 1
    mark="<!-- loop-ledger:$n -->"
    LEDGER_ID="$(jq -r --argjson t "$TRUSTED_WRITERS" --arg m "$mark" \
        '[.[] | select(((.user.login // "") | sub("^app/"; "")) as $l | $t | index($l) != null)
              | select((.body // "") | contains($m))] | sort_by(.id) | .[0].id // empty' <<<"$all")"
    [ -n "$LEDGER_ID" ] || return 0
    LEDGER_BODY="$(jq -r --argjson i "$LEDGER_ID" '.[] | select(.id == $i) | .body' <<<"$all")"
    LEDGER_ROWS="$(grep -oE '<!-- loop-ledger-row: [^>]*-->' <<<"$LEDGER_BODY" || true)"
    any="$(grep -c 'loop-ledger-row' <<<"$LEDGER_BODY" || true)"
    ok="$(grep -cE "$LEDGER_ROW_RE" <<<"$LEDGER_ROWS" || true)"
    [ "$any" = "$ok" ] || return 2
    return 0
}
ledger_rows() { grep -E "^<!-- loop-ledger-row: $1 " <<<"$LEDGER_ROWS" || true; }

ledger_append() { # <issue> <kind> <rung> <head-oid> <pr> [extra-field ...] — idempotent on (kind, rung, head)
    local n="$1" kind="$2" rung="$3" head="$4" pr="$5"; shift 5
    local now row key line f
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    row="<!-- loop-ledger-row: $kind rung:$rung head-oid:$head pr:$pr at:$now${*:+ $*} -->"
    key="<!-- loop-ledger-row: $kind rung:$rung head-oid:$head "
    line="- \`$kind\` · rung $rung · head \`${head:0:12}\` · pr $pr · $now $row"
    if grep -qF "$key" <<<"$LEDGER_BODY"; then
        log "    loop ledger on #$n already carries ($kind, rung $rung, ${head:0:12}) — no write"
        return 0
    fi
    if [ "$DRY_RUN" = "1" ]; then
        log "    DRY-RUN loop-ledger append on #$n${LEDGER_ID:+ (comment $LEDGER_ID)}: $row"
        return 0
    fi
    f="$(mktemp)"
    if [ -n "$LEDGER_ID" ]; then
        awk -v l="$line" '/<!-- loop-ledger-end -->/ { print l } { print }' <<<"$LEDGER_BODY" >"$f"
        gh api -X PATCH "repos/$GITHUB_REPO/issues/comments/$LEDGER_ID" -F body=@"$f" >/dev/null \
            || { rm -f "$f"; return 1; }
    else
        printf '### Loop ledger for #%s\n\n<!-- loop-ledger:%s -->\n%s\n<!-- loop-ledger-end -->\n' \
            "$n" "$n" "$line" >"$f"
        gh api -X POST "repos/$GITHUB_REPO/issues/$n/comments" -F body=@"$f" >/dev/null \
            || { rm -f "$f"; return 1; }
    fi
    rm -f "$f"
    LEDGER_BODY="$LEDGER_BODY
$line"
    log "    loop ledger on #$n: appended $kind row for rung $rung at ${head:0:12}"
}

# The loop bounds and the flag come from config/execution.yaml through the
# one parser (D20). An unreadable bound fails the guard closed; an
# unreadable flag reads as false (D18).
read_loop() { python3 "$REPO_ROOT/scripts/ops/execution.py" --loop "$1" 2>/dev/null; }
LOOP_LIMITS_OK=1
MAX_DISPATCH="$(read_loop max_rung_dispatches_per_issue)" || LOOP_LIMITS_OK=0
MAX_COST="$(read_loop max_cost_usd_per_issue)" || LOOP_LIMITS_OK=0
AUTONOMOUS_MERGE="$(read_loop autonomous_merge || true)"
[ "$AUTONOMOUS_MERGE" = "true" ] || AUTONOMOUS_MERGE=false

# --- Per issue ----------------------------------------------------------------
# `|| true` is required: grep exits 1 on an empty candidate list, and
# set -e would abort on exactly the case that must fall through to the
# FAILURES check below.
for issue in $(printf '%s\n' "$CANDIDATES" | grep -E '^[0-9]+$' | sort -nu || true); do
    target_rank=0
    stage="${BEST_STAGE[$issue]:-}"
    path="${BEST_PATH[$issue]:-}"
    files="${ALL_FILES[$issue]:-}"
    if [ -n "$files" ]; then
        log "--> #$issue · added: $files · furthest: $stage.md"
    else
        log "--> #$issue · merged pull request #${MERGE_PR[$issue]}"
    fi

    # Read state and the recent thread in ONE call: state and labels
    # decide whether to act, the comment bodies decide whether the
    # comment is already there. D21(a): a failed read is a counted
    # failure naming the issue, never a silent skip and never
    # substituted — under DRY_RUN=1 or for real, this is the same
    # program on this path. The default a dry run needs for an issue no
    # fixture describes lives in the test harness now (D13(c)), not
    # here.
    if view="$(gh issue view "$issue" --repo "$GITHUB_REPO" \
                 --json number,state,labels,comments 2>/dev/null)"; then
        issue_state="$(jq -r '.state' <<<"$view")"
        labels="$(jq -r '.labels[].name' <<<"$view")"
        recent="$(jq -r '.comments | .[-20:] | .[].body' <<<"$view")"
    else
        fail_issue "cannot read #$issue; whether it advances is unknown (#57, D21(a))"
        continue
    fi

    current_status="$(grep '^status:' <<<"$labels" || true)"
    status_count="$(grep -c . <<<"${current_status}" || true)"
    [ -n "$current_status" ] || status_count=0

    # hold is absolute, and it is checked FIRST — before state, before
    # labels, before anything else this loop does (#4 D2; #57 D5 reuses
    # this chain unchanged). A closed issue that also carries hold is
    # one log line and exit 0, not D9's red below: hold is the manual
    # override for every other decision here too, and a breaker with an
    # exception for one issue shape is not a breaker (Amended D9, #73
    # F4 ≡ Argus R1-6).
    if grep -Fxq "hold" <<<"$labels"; then
        log "    #$issue halted by hold — no label, no comment"
        continue
    fi

    if [ "$issue_state" != "OPEN" ]; then
        # D9. A closed issue still carrying the merge rung's label, with
        # a pull request for it merged in this range, means the
        # implementing pull request carried a closing keyword it must
        # not carry — or a human closed the issue while its real
        # implementing pull request was merging in this range (#73 F5,
        # message widened, rule unchanged). That is red, and NOTHING is
        # written to the issue — no label, no comment, no reopen. Every
        # other non-OPEN case keeps today's quiet skip: an artifact
        # candidate, no status label at all, more than one of them
        # (never guess on two status labels, #4 D1 — no row can be
        # identified), or a row whose trigger is not a merge.
        if [ -n "${MERGE_PR[$issue]:-}" ] && [ "$status_count" -eq 1 ] \
           && jq -e --arg l "$current_status" \
                '[.stages[] | select(.label == $l and .advances_on == "merge")] | length == 1' \
                "$LIFECYCLE_JSON" >/dev/null 2>&1; then
            fail_issue "#$issue is $issue_state but still carries $current_status, and pull request #${MERGE_PR[$issue]} merged in the range — the ladder cannot advance a closed issue. Likely cause: the implementing pull request must not carry a closing keyword for #$issue (#57, D9); it is also possible a human closed #$issue directly while that pull request was merging. Reopen #$issue if it should still advance, drop any closing keyword, and re-run this range."
            continue
        fi
        log "    #$issue is $issue_state — skipping (a closed issue has no stage to advance)"
        continue
    fi

    # ONE trigger string, shared by every comment shape below, so the two
    # candidate kinds differ in that clause and in nothing else. It is
    # provisional here — the corrupted-state comment is posted before a
    # candidate kind is resolved — and is set definitively from `kind`
    # once the contest below is decided.
    if [ -n "$files" ]; then
        trigger_desc="\`$path\` added in ${AFTER:0:12}"
    else
        trigger_desc="pull request #${MERGE_PR[$issue]} merged in ${MERGE_SHA[$issue]:0:12}"
    fi

    if [ "$status_count" -gt 1 ]; then
        marker="<!-- lifecycle:corrupt:${AFTER} -->"
        if grep -Fq "$marker" <<<"$recent"; then
            log "    #$issue already flagged corrupted for this push — no re-post"
        else
            body="$COMMENT_HEADER

**Corrupted stage state — automation halted.** #$issue carries more than one \`status:*\` label:

$(printf '%s\n' "$current_status" | sed 's/^/  - /')

At most one \`status:*\` may be set at a time; a pair is not a stage, it is two state machines
disagreeing. \`hold\` has been applied and no stage transition was made for $trigger_desc.
Fix: remove every \`status:*\` but the true one, then remove \`hold\` — the next
merge advances the stage, or re-run \`scripts/ci/lifecycle_advance.sh $BEFORE $AFTER\` locally.

$marker"
            post_comment "$issue" "$body" || { fail_issue "could not comment on #$issue"; continue; }
        fi
        if grep -Fxq "hold" <<<"$labels"; then
            log "    hold already present on #$issue — no write"
        else
            edit_labels "$issue" "hold" "" || { fail_issue "could not apply hold to #$issue"; continue; }
        fi
        continue
    fi

    # --- which candidate wins ---------------------------------------------------
    # An issue can have BOTH an artifact candidate and a merge candidate
    # in one range. "Furthest transition wins" is settled the same way it
    # is for two artifacts: by position in the ladder file, so the
    # ordering lives in personas/lifecycle.json and not in a second place
    # here (D5).
    artifact_rank="${BEST_RANK[$issue]:-0}"
    merge_rank=0
    if [ -n "${MERGE_PR[$issue]:-}" ] && [ -n "$current_status" ]; then
        # One jq, gate and rank together: rank = position in .stages plus
        # one, emitted ONLY when the row for the issue's current label
        # declares `advances_on == "merge"`. No match emits nothing, so
        # merge_rank stays 0 and the provisional candidate is discarded —
        # which is also the whole idempotency mechanism for the merge
        # rung: once the label has advanced, no row matches it again.
        merge_rank="$(jq -r --arg l "$current_status" '
            [.stages[] | .label] as $labels
            | (.stages[] | select(.label == $l and .advances_on == "merge"))
            | ($labels | index($l)) + 1
        ' "$LIFECYCLE_JSON" 2>/dev/null || true)"
        [ -n "$merge_rank" ] || merge_rank=0
    fi

    if [ "$merge_rank" -gt "$artifact_rank" ]; then
        kind="merge"
    elif [ "$artifact_rank" -gt 0 ]; then
        kind="artifact"
    else
        log "    #$issue has no rung to advance for this range — nothing to do"
        continue
    fi
    if [ "$kind" = "merge" ]; then
        trigger_desc="pull request #${MERGE_PR[$issue]} merged in ${MERGE_SHA[$issue]:0:12}"
    else
        trigger_desc="\`$path\` added in ${AFTER:0:12}"
    fi

    # --- pick the transition (read, never decided) ------------------------------
    # The row carries both the label to write and the line to post — keyed
    # by the merged artifact for an artifact candidate, and by the issue's
    # current label plus a `merge` trigger for a merge candidate. A stage
    # the table does not name is a failure, not a guess.
    if [ "$kind" = "merge" ]; then
        row_ok=0
        row="$(jq -ec --arg l "$current_status" \
                 '.stages[] | select(.label == $l and .advances_on == "merge")' \
                 "$LIFECYCLE_JSON")" && row_ok=1
        if [ "$row_ok" -ne 1 ]; then
            fail_issue "no lifecycle row with advances_on=merge for '$current_status' (#$issue)"
            continue
        fi
    elif ! row="$(jq -ec --arg a "$stage.md" \
                    '.stages[] | select(.artifact == $a)' "$LIFECYCLE_JSON")"; then
        fail_issue "no lifecycle row for '$stage.md' (#$issue)"
        continue
    fi
    # `// empty` and not `-r` alone: a JSON null must reach bash as the
    # empty string, never as the four-character word `null`, or the
    # inert rungs of the ladder would write `--add-label null` and post
    # a body with the word null where the sentence belongs (#52 AT-4,
    # #57 D10).
    target="$(jq -r '.advances_to // empty' <<<"$row")"
    message="$(jq -r '.advance_message // empty' <<<"$row")"
    marker_stage="${target#status:}"

    # The Draft override stays a CONDITION in this script and is not a row
    # in the table: it is not a rung of the ladder, it is the ladder
    # refusing to move. Grep the MERGED file, not the working tree: what
    # advanced the gate is what landed. Case-sensitive, and the line may
    # carry more than the status — the house style is `**Issue:** #6 ·
    # **Status:** Approved (approval = merge of this PR)`, so the marker
    # is mid-line and the label is bold. Markdown emphasis around
    # `Status:` is tolerated for exactly that reason; the word Approved
    # is not.
    if [ "$kind" = "artifact" ] && [ "$stage" = "spec" ]; then
        if ! spec_body="$(git show "${AFTER}:${path}")"; then
            fail_issue "cannot read $path at $AFTER; #$issue left untouched"
            continue
        fi
        if ! grep -Eq '(^|[^[:alnum:]_])\*{0,2}Status:\*{0,2}[[:space:]]+Approved([^[:alnum:]_]|$)' \
               <<<"$spec_body"; then
            target=""
            marker_stage="spec-draft"
            message="**Warning: a spec.md merged without \`Status: Approved\`.** \`$path\` landed in this push but its status line is not Approved, so the DESIGN gate did NOT advance and the stage label is unchanged. Nothing is dispatched against a Draft (INTENT.md, stage 3): resolve the spec's Open questions, set \`Status: Approved\`, and the next merge advances it."
        fi
    fi

    # --- D19: an issue already at the target label is not an event -------------
    # Checked BEFORE any rank is read, and independent of whether the
    # ladder can rank $target at all: index() is a bijection over the
    # ladder's own label list, so two DIFFERENT labels can never share a
    # rank — the only way the block below could ever see "equal" is for
    # $current_status to already equal $target, which is exactly this
    # case. Base's unconditional `[ "$current_status" = "$target" ]`
    # short-circuit lived here; deleting it without a rank-independent
    # replacement was #73's own regression (Argus R1-1): an issue already
    # carrying a label the ladder cannot rank (a hand-edited or typo'd
    # personas/lifecycle.json) fell through to a self-cancelling
    # `--add-label X --remove-label X` instead of a no-op.
    if [ -n "$target" ] && [ "$current_status" = "$target" ]; then
        log "    #$issue is already at $target for $trigger_desc — no stage transition (D19)"
        if grep -Fxq "intent:new" <<<"$labels"; then
            edit_labels "$issue" "" "intent:new" \
                || { fail_issue "could not clear intent:new on #$issue"; continue; }
        fi
        continue
    fi

    # --- D19: a transition never walks down the ladder -------------------------
    # Rank is the row's 1-based position in `[.stages[].label]` — the
    # same list D5's contest already ranks on, so no second ordering is
    # written anywhere. No status:* label ranks 0, so a first transition
    # is always forward; a single status:* label that names no rung
    # (e.g. status:review-stuck) has no rank either, and a transition
    # against it cannot be shown to be forward. Below or unranked is a
    # no-op with one ::warning::, never a counted failure — a folder
    # rename or a revert-and-reland is an ordinary act on a healthy
    # ladder, not a broken one (#57, D19). Skipped when target is empty:
    # the Draft override and the last, inert rung are not transitions to
    # rank at all. The equal-rank case cannot occur below: it is the
    # same-label case the short-circuit above already caught.
    #
    # tgt_idx="null" — the row's own advances_to is not one of the
    # ladder's five labels at all (reachable only by hand-editing
    # personas/lifecycle.json, as the "ladder file is the source" test
    # below does) — is outside what D19 ranks; such a target is neither
    # shown backward nor forward, so it is let through unranked rather
    # than refused on data D19 was never told how to order. A `jq`
    # failure while reading either rank is its own counted failure
    # (Argus R1-2): this row's thesis is that no read here fails open,
    # and silently treating an unreadable rank as "unranked" would be
    # exactly that.
    if [ -n "$target" ]; then
        if ! tgt_idx="$(jq -r --arg l "$target" '[.stages[].label] | index($l)' "$LIFECYCLE_JSON")"; then
            fail_issue "could not rank $target on the ladder for #$issue"
            continue
        fi
        if [ "$tgt_idx" != "null" ]; then
            target_rank=$((tgt_idx + 1))
            current_rank=0
            current_unranked=0
            if [ -n "$current_status" ]; then
                if ! cur_idx="$(jq -r --arg l "$current_status" '[.stages[].label] | index($l)' "$LIFECYCLE_JSON")"; then
                    fail_issue "could not rank $current_status on the ladder for #$issue"
                    continue
                fi
                if [ "$cur_idx" = "null" ]; then
                    current_unranked=1
                else
                    current_rank=$((cur_idx + 1))
                fi
            fi

            if [ "$current_unranked" -eq 1 ] || [ "$target_rank" -lt "$current_rank" ]; then
                echo "::warning::lifecycle_advance: #$issue is at ${current_status:-no status label} and $trigger_desc would move it to $target, which does not advance the ladder — no stage transition was made (#57, D19)."
                continue
            fi
        fi
    fi

    # --- D13 / D14 guards on the label write (#64) ---------------------------
    # Both run in either flag setting (D18). The ratchet (D14) refuses a
    # transition into a rung the ledger already records: no label, no
    # comment, one refusal row, and the run ends red so the workflow's
    # escalate step fires. A bound already reached (D13) refuses the same
    # way in green. This script calls no escalation itself (D19).
    if [ -n "$target" ] && [ "${target_rank:-0}" -gt 0 ]; then
        guard_pr="${MERGE_PR[$issue]:-none}"
        ledger_rc=0
        read_ledger "$issue" || ledger_rc=$?
        if [ "$ledger_rc" -eq 1 ]; then
            fail_issue "cannot read the #$issue thread to find its loop ledger — unreadable is not absent (D13)"
            continue
        elif [ "$ledger_rc" -eq 2 ]; then
            fail_issue "the loop ledger on #$issue carries a row this advancer cannot parse — unreadable is not absent (D13)"
            continue
        fi
        highest_entered="$(ledger_rows '(dispatch|terminal)' | sed -nE 's/.* rung:([0-9]+) .*/\1/p' | sort -n | tail -1)"
        : "${highest_entered:=0}"
        at_head=0
        ! ledger_rows '(dispatch|terminal)' | grep -qE " rung:$target_rank head-oid:$AFTER " || at_head=1
        if [ "$target_rank" -lt "$highest_entered" ] \
           || { [ "$target_rank" -eq "$highest_entered" ] && [ "$at_head" -eq 0 ]; }; then
            echo "::error::lifecycle_advance: refusal reason-code: non-monotonic for #$issue — $trigger_desc would enter rung $target_rank ($target) while the loop ledger already records rung $highest_entered" >&2
            FAILURES=$((FAILURES + 1))
            ledger_append "$issue" "refusal:non-monotonic" "$target_rank" "$AFTER" "$guard_pr" \
                || fail_issue "could not record the refusal row on #$issue"
            continue
        elif [ "$target_rank" -eq "$highest_entered" ]; then
            log "    #$issue already recorded at rung $target_rank for ${AFTER:0:12} — idempotent, no write (D14)"
            continue
        fi
        if [ "$LOOP_LIMITS_OK" != 1 ]; then
            fail_issue "cannot read the loop bounds for #$issue (execution.py --loop) — failing closed (D13)"
            continue
        fi
        dispatch_count="$(ledger_rows dispatch | grep -c . || true)"
        costed="$(ledger_rows dispatch | grep -cE ' cost:[0-9]+(\.[0-9]+)? ' || true)"
        if [ "$dispatch_count" != "$costed" ]; then
            fail_issue "a dispatch row on #$issue carries no cost — the ledger is the only source of spend (D13)"
            continue
        fi
        summed_cost="$(ledger_rows dispatch | sed -nE 's/.* cost:([0-9.]+) .*/\1/p' | awk '{ s += $1 } END { printf "%.2f", s }')"
        over=""
        if [ "$dispatch_count" -ge "$MAX_DISPATCH" ]; then
            over="max_rung_dispatches_per_issue reached ($dispatch_count/$MAX_DISPATCH)"
        elif ! awk -v s="$summed_cost" -v m="$MAX_COST" 'BEGIN { exit !(s + 0 < m + 0) }'; then
            over="max_cost_usd_per_issue reached ($summed_cost/$MAX_COST)"
        fi
        if [ -n "$over" ]; then
            echo "::notice::lifecycle_advance: refusal reason-code: budget for #$issue — $over; no label written, the workflow escalates (D13)" >&2
            log "    refusal reason-code: budget for #$issue — $over"
            ledger_append "$issue" "refusal:budget" "$target_rank" "$AFTER" "$guard_pr" \
                || fail_issue "could not record the refusal row on #$issue"
            continue
        fi
    fi

    # Bootstrap compression is an artifact-path note: a merge candidate
    # adds no files, so there is nothing to compress.
    compression=""
    if [ -n "$files" ] && [ "$files" != "$stage.md" ]; then
        compression="

Bootstrap compression: this push added \`$files\` for #$issue. Only the furthest transition is applied, once — the earlier gates are recorded by the files themselves."
    fi

    # --- comment (idempotent by marker) ---------------------------------------
    # A row with no advance_message posts nothing at all: an empty
    # message would otherwise render a body with a blank line where the
    # sentence belongs (D10).
    if [ "$kind" = "merge" ]; then
        marker="<!-- lifecycle:${marker_stage}:${MERGE_SHA[$issue]} -->"
    else
        marker="<!-- lifecycle:${marker_stage}:${AFTER} -->"
    fi
    if [ -z "$message" ]; then
        log "    #$issue has no advance_message for this row — no comment"
    elif grep -Fq "$marker" <<<"$recent"; then
        log "    #$issue already carries $marker — no re-post"
    else
        body="$COMMENT_HEADER

$message

Trigger: $trigger_desc.$compression

$marker"
        post_comment "$issue" "$body" || { fail_issue "could not comment on #$issue"; continue; }
    fi

    # --- labels (idempotent; a Draft spec advances nothing) --------------------
    if [ -z "$target" ]; then
        # A Draft spec and the last rung both land here, and neither
        # removes anything: `intent:new` is cleared by the first status
        # this workflow WRITES, and nothing is written here (D7).
        if [ "$kind" = "artifact" ] && [ "$stage" = "spec" ]; then
            log "    #$issue stage unchanged (${current_status:-no status label}) — Draft spec does not advance"
        else
            log "    #$issue has no advances_to for this row — stage unchanged (${current_status:-no status label})"
        fi
        continue
    fi

    # `intent:new` marks an item nobody has triaged. The first status
    # label this workflow writes IS the triage, so the two must never be
    # carried together (D7). It rides along on the same `gh issue edit`.
    # D19's rank check above already ended this issue's processing when
    # target ranked at or below current_status, so by construction
    # target strictly outranks it here — this is always a forward write.
    remove="$current_status"
    if grep -Fxq "intent:new" <<<"$labels"; then
        remove="${remove:+$remove,}intent:new"
    fi

    edit_labels "$issue" "$target" "$remove" \
        || { fail_issue "could not set $target on #$issue"; continue; }

    # --- the rung after the label (#64 D16, D17, D18) --------------------------
    [ "${target_rank:-0}" -gt 0 ] || continue
    if [ -z "$(jq -r --arg t "$target" '.stages[] | select(.label == $t) | .advances_to // empty' "$LIFECYCLE_JSON")" ]; then
        # D17: the last rung is terminal — one terminal row, no dispatch.
        ledger_append "$issue" terminal "$target_rank" "$AFTER" "${MERGE_PR[$issue]:-none}" \
            || fail_issue "could not record the terminal row on #$issue"
        log "    #$issue is at the last rung ($target) — terminal, no dispatch"
        continue
    fi
    if [ "$AUTONOMOUS_MERGE" != "true" ]; then
        log "    autonomous_merge is false — no dispatch for #$issue (D18)"
        continue
    fi
    new_stage="$(jq -r --arg t "$target" '.stages[] | select(.label == $t) | .stage // empty' "$LIFECYCLE_JSON")"
    persona=""
    for p_file in "$REPO_ROOT"/personas/*.yaml; do
        grep -q '^kind: persona$' "$p_file" 2>/dev/null || continue
        if grep -qE "^stage: \[( *[a-z]+,)* *$new_stage( *, *[a-z]+)* *\]" "$p_file"; then
            persona="$(basename "$p_file" .yaml)"
            break
        fi
    done
    if [ -z "$persona" ]; then
        log "    no persona declares stage '$new_stage' — no dispatch for #$issue"
        continue
    fi
    if ! binding="$(python3 "$REPO_ROOT/scripts/ops/execution.py" --binding "$persona" 2>/dev/null)"; then
        fail_issue "cannot read the execution binding for $persona — no dispatch for #$issue"
        continue
    fi
    read -r trigger placement cap <<<"$binding"
    if [ "$trigger" != "ladder" ]; then
        log "    $persona's trigger is '$trigger' — only ladder bindings dispatch from here (D16)"
        continue
    fi
    # D15: hold or blocked is re-read immediately before the dispatch.
    if ! fresh="$(gh issue view "$issue" --repo "$GITHUB_REPO" --json labels 2>/dev/null)"; then
        fail_issue "cannot re-read #$issue before dispatch (D15) — no dispatch"
        continue
    fi
    if jq -e '[.labels[].name] | (index("hold") != null) or (index("blocked") != null)' <<<"$fresh" >/dev/null; then
        log "    #$issue carries hold or blocked — no dispatch (D15)"
        continue
    fi
    # The dispatch row is the count and the spend the bounds are judged
    # on (D13); it is written before the adapter so a crashed dispatch
    # still counts.
    ledger_append "$issue" dispatch "$target_rank" "$AFTER" "${MERGE_PR[$issue]:-none}" \
        "event:${GITHUB_RUN_ID:-local}" "cost:$cap" \
        || { fail_issue "could not record the dispatch row on #$issue — no dispatch"; continue; }
    if [ "$DRY_RUN" = "1" ]; then
        log "    DRY-RUN scripts/placement/$placement/run.sh $issue"
    else
        log "    dispatching $persona via $placement for #$issue"
        bash "$REPO_ROOT/scripts/placement/$placement/run.sh" "$issue" \
            || fail_issue "placement $placement could not dispatch $persona for #$issue"
    fi
done

# --- Near misses (D17) --------------------------------------------------------
# A merge at the implement rung is never reported by silence alone. This
# loop runs OUTSIDE the per-issue chain above on purpose: a near miss is
# not a candidate, so it can neither apply `hold`, nor post a
# corrupted-state comment, nor turn the trunk red. Its only two outcomes
# are one `::warning::` line or nothing at all, and the only call it
# makes is a read.
merge_rung_label="$(jq -r 'first(.stages[] | select(.advances_on == "merge") | .label) // empty' \
                      "$LIFECYCLE_JSON")"
for issue in $(printf '%s\n' "$NEAR_LIST" | grep -E '^[0-9]+$' | sort -nu || true); do
    # The issue gained a real candidate after all — the rung moved (or
    # was deliberately not moved) for a reason the loop above already
    # reported. Nothing to warn about.
    [ -z "${MERGE_PR[$issue]:-}${BEST_STAGE[$issue]:-}" ] || continue
    [ -n "$merge_rung_label" ] || continue
    if ! near_view="$(gh issue view "$issue" --repo "$GITHUB_REPO" \
                        --json number,labels 2>/dev/null)"; then
        log "    #$issue had a near miss but is not readable — no warning"
        continue
    fi
    near_labels="$(jq -r '.labels[].name' <<<"$near_view")"
    if ! grep -Fxq "$merge_rung_label" <<<"$near_labels"; then
        log "    #$issue had a near miss but is not at $merge_rung_label — no warning"
        continue
    fi
    echo "::warning::lifecycle_advance: #$issue is at $merge_rung_label and pull request #${NEAR_PR[$issue]} merged from \`${NEAR_HEAD[$issue]}\`, which is not its dispatch branch \`${NEAR_EXPECT[$issue]}\` — no stage transition was made. If that pull request is #$issue's implementation, the branch name is wrong and the rung must be advanced by hand."
done

if [ "$FAILURES" -gt 0 ]; then
    die "$FAILURES issue(s) could not be processed; the labels above are partially applied — re-run this range once the cause is fixed (every write is idempotent)"
fi

log "==> Done."
