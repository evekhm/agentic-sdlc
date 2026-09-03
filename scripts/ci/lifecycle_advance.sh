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
# What this script deliberately does NOT write: `status:in-review` and
# the `review:1..3` counter. Those belong to the review automation
# (#8, #9); a stage advancer that also guessed at review state would be
# two state machines racing over one label.
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

# Plain counter: `${#BEST_STAGE[@]}` on a never-assigned associative
# array trips `set -u`'s unbound-variable check on an empty push, so
# count issues explicitly instead.
n_crossings=0
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
    [ -n "${ALL_FILES[$issue]:-}" ] || n_crossings=$((n_crossings + 1))
    ALL_FILES[$issue]="${ALL_FILES[$issue]:-}${ALL_FILES[$issue]:+ }${stage}.md"
    if [ "$rank" -gt "${BEST_RANK[$issue]:-0}" ]; then
        BEST_RANK[$issue]="$rank"
        BEST_STAGE[$issue]="$stage"
        BEST_PATH[$issue]="$path"
    fi
done <<<"$added"

if [ "$n_crossings" -eq 0 ]; then
    log "==> no intent/<issue>-<slug>/{intent,spec,plan}.md added in $BEFORE..$AFTER — nothing to advance"
    exit 0
fi

log "==> $GITHUB_REPO · range ${BEFORE:0:12}..${AFTER:0:12} · $n_crossings issue(s) with a gate crossing"
if [ "$DRY_RUN" = "1" ]; then
    log "==> DRY_RUN=1 — no write will be executed"
fi

# --- gh wrappers --------------------------------------------------------------
COMMENT_HEADER="_Posted by \`.github/workflows/lifecycle.yml\` (#4) — deterministic, no model call. \
This workflow writes only the \`status:planning\`→\`status:implementing\` ladder; \
\`status:in-review\` and the \`review:N\` counter get their writers with #8/#9._"

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
for issue in $(printf '%s\n' "${!BEST_STAGE[@]}" | sort -n); do
    stage="${BEST_STAGE[$issue]}"
    path="${BEST_PATH[$issue]}"
    files="${ALL_FILES[$issue]}"
    log "--> #$issue · added: $files · furthest: $stage.md"

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

    if [ "$issue_state" != "OPEN" ]; then
        log "    #$issue is $issue_state — skipping (a closed issue has no stage to advance)"
        continue
    fi

    # hold is absolute, and it is checked FIRST. Nothing below may run.
    if grep -Fxq "hold" <<<"$labels"; then
        log "    #$issue halted by hold — no label, no comment"
        continue
    fi

    current_status="$(grep '^status:' <<<"$labels" || true)"
    status_count="$(grep -c . <<<"${current_status}" || true)"
    [ -n "$current_status" ] || status_count=0

    if [ "$status_count" -gt 1 ]; then
        marker="<!-- lifecycle:corrupt:${AFTER} -->"
        if grep -Fq "$marker" <<<"$recent"; then
            log "    #$issue already flagged corrupted for this push — no re-post"
        else
            body="$COMMENT_HEADER

**Corrupted stage state — automation halted.** #$issue carries more than one \`status:*\` label:

$(printf '%s\n' "$current_status" | sed 's/^/  - /')

At most one \`status:*\` may be set at a time; a pair is not a stage, it is two state machines
disagreeing. \`hold\` has been applied and no stage transition was made for the push that added
\`$files\`. Fix: remove every \`status:*\` but the true one, then remove \`hold\` — the next
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

    # --- pick the transition (read, never decided) ------------------------------
    # The row keyed by the merged artifact carries both the label to write
    # and the line to post. A stage the table does not name is a failure,
    # not a guess — the old catch-all arm, now the jq lookup failing.
    if ! row="$(jq -ec --arg a "$stage.md" \
                  '.stages[] | select(.artifact == $a)' "$LIFECYCLE_JSON")"; then
        fail_issue "no lifecycle row for '$stage.md' (#$issue)"
        continue
    fi
    target="$(jq -r '.advances_to' <<<"$row")"
    message="$(jq -r '.advance_message' <<<"$row")"
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
    if [ "$stage" = "spec" ]; then
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

    compression=""
    if [ "$files" != "$stage.md" ]; then
        compression="

Bootstrap compression: this push added \`$files\` for #$issue. Only the furthest transition is applied, once — the earlier gates are recorded by the files themselves."
    fi

    # --- comment (idempotent by marker) ---------------------------------------
    marker="<!-- lifecycle:${marker_stage}:${AFTER} -->"
    if grep -Fq "$marker" <<<"$recent"; then
        log "    #$issue already carries $marker — no re-post"
    else
        body="$COMMENT_HEADER

$message

Trigger: \`$path\` added in ${AFTER:0:12}.$compression

$marker"
        post_comment "$issue" "$body" || { fail_issue "could not comment on #$issue"; continue; }
    fi

    # --- labels (idempotent; a Draft spec advances nothing) --------------------
    if [ -z "$target" ]; then
        log "    #$issue stage unchanged (${current_status:-no status label}) — Draft spec does not advance"
        continue
    fi
    if [ "$current_status" = "$target" ]; then
        log "    #$issue already at $target — no label write"
        continue
    fi
    edit_labels "$issue" "$target" "$current_status" \
        || { fail_issue "could not set $target on #$issue"; continue; }
done

if [ "$FAILURES" -gt 0 ]; then
    die "$FAILURES issue(s) could not be processed; the labels above are partially applied — re-run this range once the cause is fixed (every write is idempotent)"
fi

log "==> Done."
