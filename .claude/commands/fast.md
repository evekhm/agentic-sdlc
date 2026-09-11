---
description: "Fast-track an issue through owner-authorized ladder compression (combining intent, spec, plan, and implementation into a single round)"
argument-hint: '[<issue-number>] [--as <persona>] [--changelog-reason <text>] [--spec-reason <text>] [--no-pr] [--no-dispatch] [--dry-run]'
allowed-tools: Bash(scripts/ops/fast.sh:*), Bash(scripts/ops/digest.sh:*), Bash(echo:*)
---

!`scripts/ops/digest.sh $ARGUMENTS; echo "---"; scripts/ops/fast.sh $ARGUMENTS; echo "[fast.sh exit $?]"`

## Instructions

1. When `<issue-number>` is omitted, `fast.sh` and `digest.sh` automatically infer the target issue number from the active worktree directory name or git branch.
2. Confirm the inferred issue number, title, and description summary to the user in your response.
3. Do not prompt the user for confirmation or pause for keyboard input — proceed directly with the execution and next steps.

