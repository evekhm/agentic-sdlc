---
description: "Fast-track an issue through owner-authorized ladder compression (combining intent, spec, plan, and implementation into a single round)"
argument-hint: "<issue-number> [--as <persona>] [--dry-run]"
allowed-tools: Bash(scripts/ops/fast.sh:*), Bash(scripts/ops/digest.sh:*), Bash(echo:*)
---

!`scripts/ops/digest.sh $ARGUMENTS; echo "---"; scripts/ops/fast.sh $ARGUMENTS; echo "[fast.sh exit $?]"`
