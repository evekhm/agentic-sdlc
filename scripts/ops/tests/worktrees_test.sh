#!/usr/bin/env bash
# Tests for scripts/ops/worktrees.sh (#80).
#
#   bash scripts/ops/tests/worktrees_test.sh
#
# Hermetic: a temp bare repository plays origin, a clone of it is the
# primary checkout, and four worktrees are built to hit each verdict.
# No network, no gh, no token. Exit 0 with a PASS line per assertion,
# non-zero on the first failure.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPT="$REPO/scripts/ops/worktrees.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

export NO_FETCH=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# --- fixture ------------------------------------------------------------------
git init -q --bare -b main "$WORK/origin.git"
git clone -q "$WORK/origin.git" "$WORK/repo" 2>/dev/null
cd "$WORK/repo"
git checkout -q -b main
echo base > base.txt && git add base.txt && git commit -q -m base && git push -q -u origin main

WT="$WORK/repo/.claude/worktrees"
mkdir -p "$WT"

# safe: branch merged into origin/main, clean
git worktree add -q -b feat/safe "$WT/safe" main
(cd "$WT/safe" && echo s > s.txt && git add s.txt && git commit -q -m safe && git push -q -u origin feat/safe)
git merge -q --no-ff feat/safe -m "merge safe" && git push -q origin main

# pushed-not-merged: clean, every commit on the remote, not in main
git worktree add -q -b feat/pushed "$WT/pushed" main
(cd "$WT/pushed" && echo p > p.txt && git add p.txt && git commit -q -m pushed && git push -q -u origin feat/pushed)

# dirty: merged branch but an uncommitted file
git worktree add -q -b feat/dirty "$WT/dirty" main
echo d > "$WT/dirty/d.txt"

# unpushed: clean but a commit no remote has
git worktree add -q -b feat/unpushed "$WT/unpushed" main
(cd "$WT/unpushed" && echo u > u.txt && git add u.txt && git commit -q -m unpushed)

# locked: clean and merged, but locked with a dead pid
git worktree add -q -b feat/locked "$WT/locked" main
git worktree lock --reason "claude agent test (pid 4000000 start 1)" "$WT/locked"

# stale local branch merged into origin/main, checked out nowhere
git branch -q old/merged main

# remote branch merged into origin/main, no local branch
git push -q origin main:refs/heads/old/remote-merged

git fetch -q origin

# --- report ------------------------------------------------------------------
REPORT="$(bash "$SCRIPT")"
[ -n "$REPORT" ] && pass "the report prints something at all" || fail "empty report"
verdict() { echo "$REPORT" | awk -v n="$1" '$1==n{print $NF}'; }

[ "$(verdict safe)" = safe ]         && pass "merged clean worktree is safe"       || fail "safe: $(verdict safe)"
[ "$(verdict pushed)" = safe ]       && pass "pushed unmerged clean worktree is safe" || fail "pushed: $(verdict pushed)"
[ "$(verdict dirty)" = dirty ]       && pass "uncommitted file -> dirty"          || fail "dirty: $(verdict dirty)"
[ "$(verdict unpushed)" = unpushed ] && pass "local-only commit -> unpushed"      || fail "unpushed: $(verdict unpushed)"
[ "$(verdict locked)" = locked ]     && pass "lock file -> locked"                || fail "locked: $(verdict locked)"
echo "$REPORT" | grep -q 'locked:pid-dead' && pass "dead pid in lock reason is reported" || fail "pid liveness missing"
[ "$(verdict repo)" = primary ]      && pass "primary checkout is listed as primary" || fail "primary: $(verdict repo)"
echo "$REPORT" | awk '$1=="safe"{print $6}' | grep -qx M && pass "merged column set for merged head" || fail "merged column"

# --- report is read-only; dry run acts on nothing ----------------------------
DRY_RUN=1 bash "$SCRIPT" --prune-remote >/dev/null
[ -d "$WT/safe" ] && pass "DRY_RUN removes nothing" || fail "DRY_RUN removed a worktree"
git show-ref -q refs/heads/old/merged && pass "DRY_RUN deletes no local branch" || fail "DRY_RUN deleted a branch"

# --- prune -------------------------------------------------------------------
bash "$SCRIPT" --prune >/dev/null
[ ! -d "$WT/safe" ]   && pass "--prune removed the safe worktree"     || fail "safe worktree still present"
[ ! -d "$WT/pushed" ] && pass "--prune removed the pushed worktree"   || fail "pushed worktree still present"
[ -d "$WT/dirty" ]    && pass "--prune kept the dirty worktree"       || fail "dirty worktree removed"
[ -d "$WT/unpushed" ] && pass "--prune kept the unpushed worktree"    || fail "unpushed worktree removed"
[ -d "$WT/locked" ]   && pass "--prune kept the locked worktree"      || fail "locked worktree removed"
[ -f "$WT/dirty/d.txt" ] && pass "dirty file survived"                || fail "dirty file lost"
! git show-ref -q refs/heads/old/merged && pass "--prune deleted merged local branch" || fail "old/merged still exists"
! git show-ref -q refs/heads/feat/safe  && pass "--prune deleted merged branch of removed worktree" || fail "feat/safe still exists"
git show-ref -q refs/heads/feat/pushed  && pass "--prune kept unmerged local branch" || fail "feat/pushed deleted"
git show-ref -q refs/heads/feat/dirty   && pass "--prune kept branch checked out in dirty worktree" || fail "feat/dirty deleted"
git ls-remote -q --exit-code origin refs/heads/old/remote-merged >/dev/null \
  && pass "--prune leaves remote branches alone" || fail "--prune touched the remote"

# --- prune-remote ------------------------------------------------------------
bash "$SCRIPT" --prune-remote >/dev/null
! git ls-remote -q --exit-code origin refs/heads/old/remote-merged >/dev/null \
  && pass "--prune-remote deleted merged remote branch" || fail "old/remote-merged still on origin"
! git ls-remote -q --exit-code origin refs/heads/feat/safe >/dev/null \
  && pass "--prune-remote deleted merged feat/safe on origin" || fail "feat/safe still on origin"
git ls-remote -q --exit-code origin refs/heads/feat/pushed >/dev/null \
  && pass "--prune-remote kept unmerged remote branch" || fail "feat/pushed deleted from origin"
git ls-remote -q --exit-code origin refs/heads/main >/dev/null \
  && pass "--prune-remote never touches main" || fail "main deleted from origin"

# --- no early exit on the worktree list (#157) --------------------------------
# `git worktree list | awk '{print; exit}'` kills git with SIGPIPE the moment
# the list is long enough that git is still writing, and under `pipefail` that
# is the script's exit status — the whole report vanished on a host with 47
# worktrees. The race cannot be provoked reliably in a fresh temp repo, so the
# invariant is asserted on the source: whoever reads that list reads all of it.
for s in "$SCRIPT" "$REPO/scripts/ops/claim.sh"; do
  grep -q "git worktree list --porcelain.*awk.*exit}" "$s" \
    && fail "$(basename "$s") exits awk early on the worktree list" \
    || pass "$(basename "$s") consumes the whole worktree list"
done

# --- argument handling -------------------------------------------------------
bash "$SCRIPT" --bogus >/dev/null 2>&1 && fail "unknown flag accepted" || pass "unknown flag is refused"

echo "worktrees_test.sh: all scenarios passed"
