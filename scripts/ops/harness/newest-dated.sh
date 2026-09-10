#!/usr/bin/env bash
# newest-dated.sh — print the newest file matching <prefix>-YYYY-MM-DD[-n].txt.
#
#   newest-dated.sh ~/projects/agentic-sdlc/ops/waves/advisor
#   newest-dated.sh ~/projects/agentic-sdlc/ops/handoffs/handoff-verifier
#
# Exists because a plain lexical sort gets this convention wrong: '-' (0x2D)
# sorts before '.' (0x2E), so `foo-2026-09-09.txt` lands AFTER
# `foo-2026-09-09-3.txt` and `tail -1` returns the oldest file of that day.
# Every dated ops/ artifact uses this convention, so both seat.sh (prompts)
# and newest-handoff.sh (handoffs) resolve through here.
#
# Exits 1 with no output when nothing matches.
set -euo pipefail

PREFIX="${1:?usage: newest-dated.sh <path-prefix>}"

pick() {
  local f base
  while IFS= read -r f; do
    base="${f##*/}"; base="${base%.txt}"
    [[ "$base" =~ -([0-9]{4}-[0-9]{2}-[0-9]{2})(-([0-9]+))?$ ]] || continue
    # unsuffixed is the first of its day, so it sorts as -001
    printf '%s-%03d\t%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[3]:-1}" "$f"
  done | sort | tail -1 | cut -f2-
}

path="$({ ls -1 "$PREFIX"-*.txt 2>/dev/null || :; } | pick)"
[[ -n "$path" ]] || exit 1
printf '%s\n' "$path"
