#!/usr/bin/env bash
# session-start.sh — Claude Code SessionStart hook. Primes a new session with
# the newest handoff so step 4 of the handover (start and prime a successor by
# hand) disappears. Covers every entry point, not just seat.sh: `claude`,
# `claude -w`, `--resume`, `--continue`, `/clear` and post-`/compact`.
#
# stdin: SessionStart payload (session_id, cwd, source, transcript_path).
# stdout on exit 0 is injected into the session as context.
#
# Two modes, deliberately:
#   $AGENTIC_SEAT / $CLAUDE_SEAT set -> inject the seat's newest handoff in full (seat.sh
#                        exports it; that is the explicit "I am the successor"
#                        signal).
#   unset             -> print a pointer only. A one-off session in this repo
#                        must not silently inherit the verifier's open work.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
user_root=~
CTX_DIR="${AGENTIC_CTX_DIR:-${CLAUDE_CTX_DIR:-${AGY_CTX_DIR:-$user_root/.claude/context}}}"
MAX_BYTES="${AGENTIC_HANDOFF_MAX_BYTES:-${CLAUDE_HANDOFF_MAX_BYTES:-60000}}"
SEAT="${AGENTIC_SEAT:-${CLAUDE_SEAT:-}}"

cat >/dev/null   # drain stdin; nothing here needs the payload yet

# Housekeeping: one prune per session, not per statusline render.
[[ -d "$CTX_DIR" ]] && find "$CTX_DIR" -maxdepth 1 -name '*.json' -mtime +7 -delete 2>/dev/null || true

path="$("$HERE/newest-handoff.sh" "$SEAT" 2>/dev/null)" || exit 0
[[ -r "$path" ]] || exit 0
bytes="$(wc -c <"$path")"

if [[ -z "$SEAT" ]]; then
  printf 'Operator state: the newest handoff for this checkout is %s (%s bytes). Read it before acting on anything session-scoped; it is not loaded.\n' \
    "$path" "$bytes"
  exit 0
fi

if (( bytes > MAX_BYTES )); then
  printf 'Seat %s: handoff %s is %s bytes, too large to inject. Read it now, in full, before anything else.\n' \
    "$SEAT" "$path" "$bytes"
  exit 0
fi

printf 'Handoff for the %s seat, from %s. This is your inherited state; treat it as the first thing you read.\n\n' \
  "$SEAT" "$path"
cat "$path"
