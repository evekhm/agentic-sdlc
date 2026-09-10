#!/usr/bin/env bash
# newest-handoff.sh — print the path of the newest handoff for a seat.
# The one resolver: seat.sh, session-start.sh, and the harness hooks all call this,
# so the launcher and the harness can never disagree about which file is the state.
#
#   newest-handoff.sh verifier      # newest ops/handoffs/handoff-verifier-*.txt
#   newest-handoff.sh               # uses $AGENTIC_SEAT / $CLAUDE_SEAT, else the shared plan handoff
#   newest-handoff.sh --seats       # every seat that has a handoff: <seat> <path>
#   newest-handoff.sh --last        # the newest handoff of any seat, for "resume
#                                   #   whatever I was last doing"
#
# --seats and --last exist because a handoff is worth writing for an arbitrary
# conversation, and the operator should not have to remember a name to get back
# to one. A seat name may itself contain hyphens (harness-statusline), so the
# seat is everything between "handoff-" and the trailing -YYYY-MM-DD[-n].
#
# Falls back to handoff-plan-*.txt, which is the operator-wide state (see
# ops/README.md). Exits 1 with no output when nothing exists.
#
# Env: AGENTIC_HANDOFF_DIR / CLAUDE_HANDOFF_DIR to point elsewhere. The default
# is ops/handoffs in the PRIMARY checkout, derived from git's common dir so a
# session running in a linked worktree still finds it — a worktree has no ops/
# of its own, and handoffs are machine-local state shared by every worktree of
# this repo. That also makes this file position-independent: it works wherever
# it is installed.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEAT="${1:-${AGENTIC_SEAT:-${CLAUDE_SEAT:-}}}"

primary_checkout() {
  local common
  common="$(git -C "$HERE" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || git -C "$HERE" rev-parse --git-common-dir 2>/dev/null)" || return 1
  if [[ "$common" != /* ]]; then
    common="$(cd "$HERE" && cd "$common" && pwd)"
  fi
  dirname "$common"
}
HANDOFFS="${AGENTIC_HANDOFF_DIR:-${CLAUDE_HANDOFF_DIR:-$(primary_checkout)/ops/handoffs}}"

newest() { "$HERE/newest-dated.sh" "$HANDOFFS/handoff-$1" 2>/dev/null || :; }

# Every seat that has at least one handoff, one per line, no duplicates.
seats() {
  local f base
  while IFS= read -r f; do
    base="${f##*/}"; base="${base%.txt}"; base="${base#handoff-}"
    # strip the trailing -YYYY-MM-DD or -YYYY-MM-DD-n; what is left is the seat
    [[ "$base" =~ ^(.+)-[0-9]{4}-[0-9]{2}-[0-9]{2}(-[0-9]+)?$ ]] || continue
    printf '%s\n' "${BASH_REMATCH[1]}"
  done < <({ ls -1 "$HANDOFFS"/handoff-*.txt 2>/dev/null || :; }) | sort -u
}

case "${1:-}" in
  --seats)
    found=no
    while IFS= read -r s; do
      [[ -n "$s" ]] || continue
      printf '%s\t%s\n' "$s" "$(newest "$s")"; found=yes
    done < <(seats)
    [[ "$found" == yes ]] || exit 1
    exit 0 ;;
  --last)
    # newest per seat, then the newest of those; mtime settles a same-day tie
    best=""
    while IFS= read -r s; do
      [[ -n "$s" ]] || continue
      p="$(newest "$s")"
      [[ -n "$p" ]] || continue
      [[ -z "$best" || "$p" -nt "$best" ]] && best="$p"
    done < <(seats)
    [[ -n "$best" ]] || exit 1
    printf '%s\n' "$best"
    exit 0 ;;
esac

path=""
[[ -n "$SEAT" && "$SEAT" != "plan" ]] && path="$(newest "$SEAT")"
[[ -n "$path" ]] || path="$(newest plan)"
[[ -n "$path" ]] || exit 1

printf '%s\n' "$path"
