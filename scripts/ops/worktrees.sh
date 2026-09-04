#!/usr/bin/env bash
# Worktree hygiene report and prune (#80; CLAUDE.md "Parallel sessions").
#
#   scripts/ops/worktrees.sh                 # report only, read-only
#   scripts/ops/worktrees.sh --prune         # remove `safe` worktrees and
#                                            # local branches merged into
#                                            # origin/main
#   scripts/ops/worktrees.sh --prune-remote  # also delete remote branches
#                                            # merged into origin/main
#   DRY_RUN=1 scripts/ops/worktrees.sh --prune[-remote]
#
# One line per worktree (the primary checkout is listed first and never
# pruned), then a verdict that answers "what would deleting this lose?":
#
#   locked    .git/worktrees/<n>/locked exists. Claude Code writes it as
#             "claude agent <id> (pid N ...)" when it spawns a worktree
#             subagent; the report says whether that pid is still alive.
#             A lock only stops `git worktree remove/prune`; it is not a
#             sign of activity by itself.
#   dirty     uncommitted or untracked files. The only thing a worktree
#             removal can destroy, and the reason `--force` is never used.
#   unpushed  commits reachable from HEAD that no remote branch has.
#             Removing the worktree keeps them on the local branch, but
#             they become findable only by name, so the entry is kept.
#   safe      clean, nothing unpushed. Merged (M) or not, every commit is
#             on the remote already; removing loses nothing.
#
# Deterministic git only: no gh, no model, no token. Fetches origin with
# --prune first unless NO_FETCH=1 (the tests set it against a local bare
# origin). Dirty, unpushed and locked entries are NEVER pruned by this
# script: each is resumed or explicitly discarded by whoever owns it.

set -euo pipefail

MODE="report"
case "${1:-}" in
  "") ;;
  --prune) MODE="prune" ;;
  --prune-remote) MODE="prune-remote" ;;
  -h|--help) sed -n '2,33p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) echo "worktrees.sh: unknown argument '$1' (see --help)" >&2; exit 2 ;;
esac

DRY_RUN="${DRY_RUN:-0}"
REMOTE="${REMOTE:-origin}"
BASE="${BASE:-$REMOTE/main}"

# All git commands run against the common repository, whichever worktree
# the script is invoked from.
GIT_COMMON="$(git rev-parse --git-common-dir)"
# Read the whole stream: an awk that exits on the first match leaves git
# writing into a closed pipe, and under `set -o pipefail` that SIGPIPE is
# the script's exit status as soon as the list is long enough to matter.
PRIMARY="$(git worktree list --porcelain | awk '/^worktree / && !p { print $2; p = 1 }')"

if [ "${NO_FETCH:-0}" != 1 ]; then
  git fetch -q --prune "$REMOTE"
fi
git rev-parse -q --verify "$BASE" >/dev/null || {
  echo "worktrees.sh: base ref '$BASE' not found" >&2; exit 2; }

run() {
  if [ "$DRY_RUN" = 1 ]; then echo "DRY_RUN: $*"; else "$@"; fi
}

# --- report ------------------------------------------------------------------

SAFE=()
printf '%-40s %-40s %-14s %5s %8s %-3s %s\n' \
  WORKTREE BRANCH LOCK DIRTY UNPUSHED MRG VERDICT

while IFS= read -r path; do
  name="$(basename "$path")"
  branch="$(git -C "$path" branch --show-current 2>/dev/null || true)"
  [ -n "$branch" ] || branch="(detached)"
  head="$(git -C "$path" rev-parse HEAD)"

  lock="-"
  lockfile="$GIT_COMMON/worktrees/$name/locked"
  if [ "$path" != "$PRIMARY" ] && [ -f "$lockfile" ]; then
    pid="$(grep -o 'pid [0-9]*' "$lockfile" 2>/dev/null | awk '{print $2}' || true)"
    if [ -n "$pid" ]; then
      if kill -0 "$pid" 2>/dev/null; then lock="locked:pid-live"; else lock="locked:pid-dead"; fi
    else
      lock="locked"
    fi
  fi

  dirty="$(git -C "$path" status --short 2>/dev/null | wc -l | tr -d ' ')"
  unpushed="$(git rev-list --count "$head" --not --remotes 2>/dev/null || echo '?')"
  merged="-"
  git merge-base --is-ancestor "$head" "$BASE" 2>/dev/null && merged="M"

  if [ "$path" = "$PRIMARY" ]; then verdict="primary"
  elif [ "$lock" != "-" ]; then verdict="locked"
  elif [ "$dirty" != 0 ]; then verdict="dirty"
  elif [ "$unpushed" != 0 ]; then verdict="unpushed"
  else verdict="safe"; SAFE+=("$path"); fi

  printf '%-40s %-40s %-14s %5s %8s %-3s %s\n' \
    "$name" "$branch" "$lock" "$dirty" "$unpushed" "$merged" "$verdict"
done < <(git worktree list --porcelain | awk '/^worktree /{print $2}')

[ "$MODE" != "report" ] || exit 0

# --- prune: safe worktrees, then local branches merged into BASE ------------

echo
for path in "${SAFE[@]}"; do
  # Re-check at removal time; no --force, so git refuses if anything
  # changed between the report and now.
  run git worktree remove "$path" && echo "removed worktree $path"
done

# `git branch -d` judges "merged" against the current HEAD, which in a
# stale primary checkout is behind BASE and would refuse. The filter
# below is the proof of merge, so -D is safe on exactly this set.
while IFS= read -r b; do
  [ -n "$b" ] || continue
  if run git branch -D "$b" 2>/dev/null; then echo "deleted local branch $b"
  else echo "kept local branch $b (checked out in a remaining worktree)"; fi
done < <(git branch --merged "$BASE" --format='%(refname:short)' | grep -vx main)

[ "$MODE" = "prune-remote" ] || exit 0

# --- prune-remote: remote branches merged into BASE --------------------------

mapfile -t REMOTE_MERGED < <(git branch -r --merged "$BASE" --format='%(refname:short)' \
  | grep -vxE "$REMOTE/(main|HEAD)" | sed "s#^$REMOTE/##")
if [ "${#REMOTE_MERGED[@]}" -eq 0 ]; then
  echo "no remote branches merged into $BASE"; exit 0
fi
run git push -q "$REMOTE" --delete "${REMOTE_MERGED[@]}"
for b in "${REMOTE_MERGED[@]}"; do echo "deleted remote branch $b"; done
[ "$DRY_RUN" = 1 ] || git fetch -q --prune "$REMOTE"
