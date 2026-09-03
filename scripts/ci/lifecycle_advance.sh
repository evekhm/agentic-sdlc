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
# `gh api repos/<repo>/commits/<sha>/pulls` over its first-parent
# commits, and each is resolved to at most one issue by its branch name
# first and a closing keyword second (D2).
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
#                         before any other check. The circuit breaker is
#                         worth nothing if automation gets a vote on it.
#   one status:*          more than one status:* label is a corrupted
#                         state machine: the script says so, applies
#                         `hold`, and stops touching that issue.
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
#   merge is a rung       a pull request merged into the default branch
#                         and resolving to an issue whose current label
#                         is the `advances_on: "merge"` row advances that
#                         issue. A push carrying no pull request advances
#                         nothing — there is no second trigger.
#   closed at merge is red a closed issue still carrying the merge rung's
#                         label, with its pull request merged in the
#                         range, is a counted failure and NOTHING is
#                         written to it: the implementing pull request
#                         carried a closing keyword it must not carry
#                         (#57, D9).
#
# Usage:
#   scripts/ci/lifecycle_advance.sh <before-sha> <after-sha>
#   DRY_RUN=1 scripts/ci/lifecycle_advance.sh <before-sha> <after-sha>
#
# DRY_RUN=1 performs no writes: every gh mutation prints instead of
# running. Reads still happen, so the live guards (hold, multiple
# status labels, an already-posted comment) are exercised as they would
# be for real; if the issue cannot be read, a dry run substitutes an
# assumed-open, unlabelled issue and says so, so the transition logic
# stays demonstrable against synthetic input.
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
declare -A MERGE_PR    # issue -> the merged pull request number (filled below)
declare -A MERGE_SHA   # issue -> the first-parent commit it was found on
declare -A SEEN_PR     # pull request number -> already resolved in this range

# Two discovery steps now feed ONE loop: files added under
# intent/<issue>-<slug>/ and pull requests merged in the range. The list
# of issues to process is a plain newline-delimited string and the count
# is a plain counter, deliberately — `${#arr[@]}` on a never-assigned
# associative array trips `set -u`'s unbound-variable check, and the
# merge path can leave BEST_STAGE entirely empty.
CANDIDATES=""
n_crossings=0
n_candidates=0
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
        n_crossings=$((n_crossings + 1))
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
# event that ends it is a merged pull request (D1). Walk the range's
# first-parent commits OLDEST FIRST, so that when two pull requests in
# one range resolve to the same issue the later one wins, and ask the
# API which pull requests each commit belongs to. A commit that belongs
# to none yields nothing and is not an error: a commit pushed straight
# to the trunk with no pull request advances nothing, deliberately.
default_branch="$(gh api "repos/$GITHUB_REPO" 2>/dev/null | jq -r '.default_branch // empty' || true)"
[ -n "$default_branch" ] || default_branch="main"

while read -r sha; do
    [ -n "$sha" ] || continue
    if ! prs_raw="$(gh api "repos/$GITHUB_REPO/commits/$sha/pulls" 2>/dev/null)"; then
        fail_issue "cannot list pull requests for $sha"
        continue
    fi
    # Merged only, and merged into the default branch: a pull request
    # still open, or one merged into some other branch, is not a gate
    # crossing on the trunk.
    if ! prs="$(jq -c --arg b "$default_branch" \
                  '.[] | select(.merged_at != null and .base.ref == $b)
                       | {number, head: .head.ref, body: (.body // "")}' <<<"$prs_raw")"; then
        fail_issue "unreadable pull request list for $sha"
        continue
    fi
    while IFS= read -r pr; do
        [ -n "$pr" ] || continue
        pr_number="$(jq -r '.number' <<<"$pr")"
        # One pull request can be reported for several commits of the
        # range; resolve it once.
        [ -z "${SEEN_PR[$pr_number]:-}" ] || continue
        SEEN_PR[$pr_number]=1
        pr_head="$(jq -r '.head' <<<"$pr")"
        pr_body="$(jq -r '.body' <<<"$pr")"

        # BRANCH FIRST, keyword second — the reverse of work.sh's order
        # (D2). An implementing pull request must NOT carry a closing
        # keyword for its issue (D9), so the branch name is the signal
        # that is always there and the keyword is the fallback for a
        # branch that carries no number. Both regexes are work.sh's
        # (`:136`, `:155`) verbatim, so no new convention appears here.
        by_branch=""
        if [[ "$pr_head" =~ ^[a-z][a-z-]*/([0-9]+)- ]]; then
            by_branch="$((10#${BASH_REMATCH[1]}))"
        fi
        by_keyword="$(grep -Eoi '\b(close[sd]?|fix(es|ed)?|resolve[sd]?)[[:space:]]+#[0-9]+' \
                        <<<"$pr_body" | grep -Eo '[0-9]+$' | sort -un || true)"
        kw_count=0
        [ -z "$by_keyword" ] || kw_count="$(grep -c . <<<"$by_keyword")"

        resolved=""
        conflict=""
        if [ "$kw_count" -gt 1 ]; then
            conflict="closing keywords naming more than one issue — $(sed 's/^/#/' <<<"$by_keyword" | tr '\n' ' ')"
        elif [ -n "$by_branch" ] && [ -n "$by_keyword" ] && [ "$by_branch" != "$by_keyword" ]; then
            conflict="#$by_branch by branch name, #$by_keyword by closing keyword"
        elif [ -n "$by_branch" ]; then
            resolved="$by_branch"
        elif [ -n "$by_keyword" ]; then
            resolved="$by_keyword"
        fi
        if [ -n "$conflict" ]; then
            fail_issue "pull request #$pr_number resolves to two different issues: $conflict — not guessing"
            continue
        fi
        # Neither signal: nothing to advance, and nothing is wrong.
        [ -n "$resolved" ] || continue

        if [ -z "${BEST_STAGE[$resolved]:-}${MERGE_PR[$resolved]:-}" ]; then
            n_candidates=$((n_candidates + 1))
            CANDIDATES="${CANDIDATES}${resolved}"$'\n'
        fi
        # PROVISIONAL. The `advances_on` gate needs the issue's current
        # label, which is only known after the `gh issue view` below;
        # the per-issue loop accepts or discards this candidate.
        MERGE_PR[$resolved]="$pr_number"
        MERGE_SHA[$resolved]="$sha"
    done <<<"$prs"
done < <(git rev-list --first-parent --reverse "$BEFORE..$AFTER")

# The FAILURES conjunct is load-bearing: a resolution disagreement can be
# the only event in a range, and an unconditional `exit 0` here would
# swallow it. With no candidate but a failure recorded, execution falls
# through an empty loop to the FAILURES check at the end and the run
# ends red.
if [ "$n_candidates" -eq 0 ] && [ "$FAILURES" -eq 0 ]; then
    log "==> nothing to advance in $BEFORE..$AFTER — no intent/<issue>-<slug>/{intent,spec,plan}.md added and no merged pull request found"
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

# --- Per issue ----------------------------------------------------------------
# `|| true` is required: grep exits 1 on an empty candidate list, and
# set -e would abort on exactly the case that must fall through to the
# FAILURES check below.
for issue in $(printf '%s\n' "$CANDIDATES" | grep -E '^[0-9]+$' | sort -nu || true); do
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
    # comment is already there.
    if view="$(gh issue view "$issue" --repo "$GITHUB_REPO" \
                 --json number,state,labels,comments 2>/dev/null)"; then
        issue_state="$(jq -r '.state' <<<"$view")"
        labels="$(jq -r '.labels[].name' <<<"$view")"
        recent="$(jq -r '.comments | .[-20:] | .[].body' <<<"$view")"
    elif [ "$DRY_RUN" = "1" ]; then
        log "    #$issue is not readable — DRY_RUN substitutes an open, unlabelled issue"
        issue_state="OPEN"; labels=""; recent=""
    else
        log "    #$issue does not exist or is not visible — skipping"
        continue
    fi

    # A pure move: the status labels are read before the state check
    # because the closed-issue rule below needs them. No guard changes
    # position relative to another guard — `hold` is still first among
    # the guards that act on an open issue.
    current_status="$(grep '^status:' <<<"$labels" || true)"
    status_count="$(grep -c . <<<"${current_status}" || true)"
    [ -n "$current_status" ] || status_count=0

    if [ "$issue_state" != "OPEN" ]; then
        # D9. A closed issue still carrying the merge rung's label, with
        # a pull request for it merged in this range, means the
        # implementing pull request carried a closing keyword it must
        # not carry. That is red, and NOTHING is written to the issue —
        # no label, no comment, no reopen. Every other non-OPEN case
        # keeps today's quiet skip: an artifact candidate, no status
        # label at all, more than one of them (never guess on two
        # status labels, #4 D1 — no row can be identified), or a row
        # whose trigger is not a merge.
        if [ -n "${MERGE_PR[$issue]:-}" ] && [ "$status_count" -eq 1 ] \
           && jq -e --arg l "$current_status" \
                '[.stages[] | select(.label == $l and .advances_on == "merge")] | length == 1' \
                "$LIFECYCLE_JSON" >/dev/null 2>&1; then
            fail_issue "#$issue is $issue_state but still carries $current_status, and pull request #${MERGE_PR[$issue]} merged in the range — the ladder cannot advance a closed issue. The implementing pull request must not carry a closing keyword for #$issue (#57, D9); reopen #$issue, drop the keyword, and re-run this range."
            continue
        fi
        log "    #$issue is $issue_state — skipping (a closed issue has no stage to advance)"
        continue
    fi

    # hold is absolute, and it is checked FIRST. Nothing below may run.
    if grep -Fxq "hold" <<<"$labels"; then
        log "    #$issue halted by hold — no label, no comment"
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
    marker="<!-- lifecycle:${marker_stage}:${AFTER} -->"
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
    remove="$current_status"
    if grep -Fxq "intent:new" <<<"$labels"; then
        remove="${remove:+$remove,}intent:new"
    fi

    if [ "$current_status" = "$target" ]; then
        if [ "$remove" = "$current_status" ]; then
            log "    #$issue already at $target — no label write"
            continue
        fi
        # Already at the target but still flagged new: clear the flag and
        # leave the status where it is.
        edit_labels "$issue" "" "intent:new" \
            || { fail_issue "could not clear intent:new on #$issue"; continue; }
        continue
    fi
    edit_labels "$issue" "$target" "$remove" \
        || { fail_issue "could not set $target on #$issue"; continue; }
done

if [ "$FAILURES" -gt 0 ]; then
    die "$FAILURES issue(s) could not be processed; the labels above are partially applied — re-run this range once the cause is fixed (every write is idempotent)"
fi

log "==> Done."
