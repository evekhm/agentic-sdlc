---
description: Release a claimed issue (drops the in-progress label, the pause case) and return the session to the primary checkout
argument-hint: <issue-number>
allowed-tools: Bash(scripts/ops/claim.sh:*), Bash(git worktree list:*), Bash(git rev-parse:*), Bash(cd:*), Bash(echo:*)
---

!`OUT="$(scripts/ops/claim.sh --release $ARGUMENTS)"; STATUS=$?; echo "$OUT"; if [ "$STATUS" -eq 0 ]; then PRIMARY="$(git worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2; exit}')"; ROOT="$(git -C "$PRIMARY" rev-parse --show-toplevel)"; cd "$ROOT" && echo "==> back at $ROOT"; else echo "[claim.sh exit $STATUS]"; fi`