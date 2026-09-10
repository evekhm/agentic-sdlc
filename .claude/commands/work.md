---
description: Work a tracker issue — a headless dispatch of the owning persona. Relative by design, so it runs the copy of work.sh in this session's working directory, not another checkout's (#43 D16)
argument-hint: <issue-number> [--as <persona>]
allowed-tools: Bash(HEADLESS=1 scripts/ops/work.sh:*), Bash(scripts/ops/work.sh:*), Bash(scripts/ops/digest.sh:*), Bash(echo:*)
---

!`scripts/ops/digest.sh $ARGUMENTS; echo "---"; HEADLESS=1 scripts/ops/work.sh $ARGUMENTS; echo "[work.sh exit $?]"`
