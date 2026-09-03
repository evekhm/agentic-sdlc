#!/usr/bin/env bash
# One measured launch per harness, against a live scratch issue
# (#43, intent/43-harness-agnostic-launch/spec.md D18, D19).
#
#   scripts/ops/smoke_launch.sh <scratch-issue>
#
# work_test.sh proves the launcher's LOGIC against stubs. Nothing a stub
# says can prove that agy actually loads `.agents/agents/<p>/agent.md`,
# that a minted App token actually authenticates a push, or that the
# `WORK-RESULT:` line actually survives a real harness's JSON. That is
# what this script is for: two real sessions, three named observables
# each, so a failure says WHICH one broke rather than "the smoke failed".
#
# It writes the scratch issue's body itself, so the instruction the two
# sessions read is part of this script and a re-run is identical to the
# first run. The body asks for a two-minute errand, not a stage: the
# point is one measured launch per harness. Each launch is still capped
# by the persona's own `limits.timeout_mins`, because work.sh caps it.
#
# Identity is NEVER checked with `gh api user`: an App token has no user
# and gets 403 (findings Q7). The token-side check is
# `GET /installation/repositories`; the outcome-side check is who
# authored the comment (odyssey) or the pushed commit (daedalus).
#
# D18/D19: three Apps are registered `issues: read`, so daedalus cannot
# claim or hand off until the human step in #47 lands. That half is
# written as "403 -> report BLOCKED ON #47 and keep going; 200/201 ->
# pass", never as "must be 403" — when the permission is granted this
# script starts passing it with no edit.
#
# Exit 0 = every required observable held. Exit 1 = one did not, or the
# inputs were unusable. A tolerated 403 is not a failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GITHUB_REPO="${GITHUB_REPO:-evekhm/agentic-sdlc}"
PUSH_URL="https://github.com/$GITHUB_REPO.git"

ISSUE="${1:-}"
case "$ISSUE" in
    ''|*[!0-9]*) echo "usage: scripts/ops/smoke_launch.sh <scratch-issue>" >&2; exit 1 ;;
esac

SMOKE_DIR="$REPO_ROOT/runs/smoke-$ISSUE"
SMOKE_BRANCH="smoke/$ISSUE-daedalus"

failures=0
blocked=0
ok()      { echo "  ok       $*"; }
bad()     { echo "  FAILED   $*"; failures=$((failures + 1)); }
tolerate(){ echo "  BLOCKED ON #47   $*"; blocked=$((blocked + 1)); }
note()    { echo "  note     $*"; }
banner()  { echo; echo "=== $*"; }

# --- the instruction the two sessions will read -------------------------------
# Written into the issue body rather than into the prompt: work.sh has
# exactly one prompt literal for both harnesses (D6), and a smoke test
# that needed a second one would be testing something work.sh does not do.
body="$(cat <<BODY
**SMOKE TEST — not a unit of work.** Created by
\`scripts/ops/smoke_launch.sh\` for #43 (spec D19). Do the errand below
and nothing else: do not open a pull request, do not modify a tracked
file on this branch, do not touch any other issue.

If you are **odyssey**:

1. Create \`runs/smoke-$ISSUE/odyssey.md\` containing one line naming
   your persona, your harness and the UTC time.
2. Post that same line as a comment on this issue, using
   \`ghp odyssey issue comment $ISSUE --repo $GITHUB_REPO --body-file <a file>\`.
3. Print \`WORK-RESULT: ok #$ISSUE smoke launch completed\`.

If you are **daedalus**:

1. Push a commit carrying one line naming your persona, your harness and
   the UTC time, WITHOUT changing the branch this worktree is on — use a
   temporary worktree:
   \`\`\`
   git worktree add -b $SMOKE_BRANCH /tmp/smoke-$ISSUE-daedalus HEAD
   # write /tmp/smoke-$ISSUE-daedalus/SMOKE-$ISSUE.md with the same line
   git -C /tmp/smoke-$ISSUE-daedalus add SMOKE-$ISSUE.md
   git -C /tmp/smoke-$ISSUE-daedalus \\
       -c user.name='evekhm-daedalus-app[bot]' \\
       -c user.email='evekhm-daedalus-app[bot]@users.noreply.github.com' \\
       commit -m 'smoke: daedalus launched by work.sh (#43)'
   git -C /tmp/smoke-$ISSUE-daedalus push $PUSH_URL $SMOKE_BRANCH
   \`\`\`
   Your git is already configured with a credential helper that mints
   your App token, so the push needs no token from you.
2. Print \`WORK-RESULT: ok #$ISSUE smoke launch completed\`.

Claiming this issue is not part of the errand.
BODY
)"

printf '%s\n' "$body" > "/tmp/smoke-$ISSUE-body.md"
ghp odyssey issue edit "$ISSUE" --repo "$GITHUB_REPO" \
    --body-file "/tmp/smoke-$ISSUE-body.md" >/dev/null \
    || { echo "smoke_launch: cannot write the scratch issue body" >&2; exit 1; }

# --- shared checks -------------------------------------------------------------

# The token-side identity check. `gh api user` is 403 for an App token
# and would prove nothing either way; this endpoint is what an
# installation token IS for.
check_token() { # <persona>
    local persona="$1" n
    if n="$(ghp "$persona" api /installation/repositories --jq '.total_count' 2>/dev/null)"; then
        ok "$persona's App token authenticates ($n repository/ies in the installation)"
    else
        bad "$persona's App token could not read /installation/repositories"
    fi
}

# D18/D19: the half that #47 gates. Written as a capability probe, not
# as an assertion about the current permission set.
check_claim() { # <persona>
    local persona="$1"
    if ghp "$persona" issue edit "$ISSUE" --repo "$GITHUB_REPO" \
           --add-label in-progress >/dev/null 2>&1; then
        ok "$persona can claim (issues: write is granted)"
        ghp "$persona" issue edit "$ISSUE" --repo "$GITHUB_REPO" \
            --remove-label in-progress >/dev/null 2>&1 || true
    else
        tolerate "$persona cannot add a label — its App is registered issues: read"
    fi
}

# `gh api` prints the error body on stdout, so every read below is
# shape-checked rather than trusted: a 404's JSON is not a count.
count_comments() {
    local n
    n="$(ghp odyssey api "/repos/$GITHUB_REPO/issues/$ISSUE/comments" \
             --jq 'length' 2>/dev/null || true)"
    case "$n" in ''|*[!0-9]*) n=-1 ;; esac
    printf '%s\n' "$n"
}

relabel() { # <status-label>
    local want="$1" have
    for have in status:planning status:spec status:build status:implementing \
                status:in-review status:done; do
        [ "$have" = "$want" ] && continue
        ghp odyssey issue edit "$ISSUE" --repo "$GITHUB_REPO" \
            --remove-label "$have" >/dev/null 2>&1 || true
    done
    ghp odyssey issue edit "$ISSUE" --repo "$GITHUB_REPO" \
        --add-label "$want" >/dev/null \
        || { echo "smoke_launch: cannot put $want on #$ISSUE" >&2; exit 1; }
}

launch() { # <persona>; -> exit code of work.sh on stdout's last line
    local persona="$1" rc=0
    echo "  --- launching $persona (capped by its own limits.timeout_mins)"
    HEADLESS=1 "$REPO_ROOT/scripts/ops/work.sh" --as "$persona" "$ISSUE" || rc=$?
    echo "  --- work.sh exited $rc"
    return "$rc"
}

# The stage's own artifact is a whole stage's worth of work; this run is
# deliberately one launch, not a stage, so the observable is the errand's
# artifact, and it is a different file per harness because the errand is:
# odyssey writes locally under runs/ (gitignored, so a smoke run leaves
# the tree clean), daedalus writes into the commit it pushes — asking it
# for a second local copy would prove nothing the pushed file does not.
check_local_artifact() { # <persona>
    local persona="$1"
    if [ -s "$SMOKE_DIR/$persona.md" ]; then
        ok "$persona wrote runs/smoke-$ISSUE/$persona.md: $(head -1 "$SMOKE_DIR/$persona.md")"
    else
        bad "$persona left no artifact at runs/smoke-$ISSUE/$persona.md"
    fi
}
check_pushed_artifact() { # <persona> <ref>
    local persona="$1" ref="$2" size
    size="$(ghp odyssey api \
                "/repos/$GITHUB_REPO/contents/SMOKE-$ISSUE.md?ref=$ref" \
                --jq '.size' 2>/dev/null || true)"
    case "$size" in
        ''|*[!0-9]*) bad "$persona pushed no SMOKE-$ISSUE.md on $ref" ;;
        0)           bad "$persona pushed an empty SMOKE-$ISSUE.md on $ref" ;;
        *)           ok "$persona's commit carries SMOKE-$ISSUE.md ($size bytes)" ;;
    esac
}

# --- run 1: claude-code / odyssey ---------------------------------------------
banner "run 1 · claude-code · odyssey · #$ISSUE"
rm -rf "$SMOKE_DIR"
check_token odyssey
relabel status:implementing
before="$(count_comments)"
rc=0; launch odyssey || rc=$?
[ "$rc" = "0" ] && ok "work.sh exited 0 (the session reported WORK-RESULT: ok)" \
                || bad "work.sh exited $rc, not 0"
check_local_artifact odyssey
after_author="$(ghp odyssey api "/repos/$GITHUB_REPO/issues/$ISSUE/comments" \
                    --jq '.[-1].user.login' 2>/dev/null || echo '')"
after_count="$(count_comments)"
if [ "$after_count" -gt "$before" ] && [ "$after_author" = "evekhm-odyssey-app[bot]" ]; then
    ok "the newest comment on #$ISSUE is authored by evekhm-odyssey-app[bot]"
else
    bad "expected a new comment by evekhm-odyssey-app[bot]; newest author is '${after_author:-none}'"
fi
check_claim odyssey

# --- run 2: antigravity / daedalus --------------------------------------------
banner "run 2 · antigravity · daedalus · #$ISSUE"
check_token daedalus
relabel status:build
# Cleared through the API, not through the launcher's own git: this
# script must never push with whatever credentials the operator's shell
# happens to carry — that is the identity confusion #43 exists to end.
ghp odyssey api -X DELETE "/repos/$GITHUB_REPO/git/refs/heads/$SMOKE_BRANCH" \
    >/dev/null 2>&1 || true
rc=0; launch daedalus || rc=$?
[ "$rc" = "0" ] && ok "work.sh exited 0 (the session reported WORK-RESULT: ok)" \
                || bad "work.sh exited $rc, not 0"
# The push is the token-handoff proof: agy's stock fallback agent has no
# instruction to push anything, so a scratch branch on origin means the
# persona loaded AND its minted token authenticated.
# Shape-checked, not just non-empty: `gh api` prints the error body on
# stdout for a 404, so `|| true` alone would hand a JSON blob to the
# assertion and call a missing branch a pass.
pushed="$(ghp odyssey api "/repos/$GITHUB_REPO/git/ref/heads/$SMOKE_BRANCH" \
              --jq '.object.sha' 2>/dev/null || true)"
case "$pushed" in
    [0-9a-f][0-9a-f]*) [ "${#pushed}" = "40" ] || pushed="" ;;
    *) pushed="" ;;
esac
if [ -n "$pushed" ]; then
    ok "$SMOKE_BRANCH exists on origin ($pushed)"
    author="$(ghp odyssey api "/repos/$GITHUB_REPO/commits/$pushed" \
                  --jq '.commit.author.name' 2>/dev/null || echo '')"
    [ "$author" = "evekhm-daedalus-app[bot]" ] \
        && ok "its head commit is authored by evekhm-daedalus-app[bot]" \
        || bad "its head commit is authored by '${author:-unknown}'"
    check_pushed_artifact daedalus "$SMOKE_BRANCH"
else
    bad "daedalus left no artifact — there is no branch to read one from"
    bad "daedalus pushed no $SMOKE_BRANCH — the persona did not load, or the token did not authenticate"
fi
check_claim daedalus

# --- verdict -------------------------------------------------------------------
banner "verdict"
note "$blocked observable(s) reported BLOCKED ON #47 and are not failures"
if [ "$failures" -gt 0 ]; then
    echo "smoke_launch: $failures observable(s) failed."
    exit 1
fi
echo "smoke_launch: both harnesses launched; every required observable held."
