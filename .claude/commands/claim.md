---
description: Claim a tracker issue and enter its worktree — wraps claim.sh, then cd's the session there (#87)
argument-hint: <issue-number> [<slug>]
allowed-tools: Bash(scripts/ops/claim.sh:*), Bash(cd:*), Bash(echo:*)
---

!`OUT="$(scripts/ops/claim.sh $ARGUMENTS)"; STATUS=$?; echo "$OUT"; if [ "$STATUS" -eq 0 ]; then WT="$(echo "$OUT" | tail -1)"; cd "$WT" && echo "==> entered $WT"; else echo "[claim.sh exit $STATUS]"; fi`

Once the command above finishes, tell the user in one short message:
the issue number and title, the stage just claimed, and the
branch/worktree the session is now in. If it refused instead, state
the refusal reason plainly and stop.