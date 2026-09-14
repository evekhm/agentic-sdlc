---
description: Work a tracker issue — at the keyboard by default (resolve <n>, claim it if nobody has, and stop at its state and stage for this session to drive), or handed off with --yolo (headless dispatch of the owning persona, the pre-#441 behavior). Relative by design, so it runs the copy of the scripts in this session's working directory, not another checkout's (#43 D16, #441)
argument-hint: '[<issue-number>] [--as <persona>] [--yolo]'
allowed-tools: Bash(scripts/ops/work_dispatch.sh:*), Bash(echo:*)
---

!`scripts/ops/work_dispatch.sh $ARGUMENTS; echo "[work_dispatch.sh exit $?]"`

If the output above starts with `NEEDS_PICK`, ask the user which numbered
issue to work from the list, then re-run this command with that number.

Otherwise, once the digest is printed, drive the issue's current stage
yourself in this session — you are the "guide me step by step" this
command exists for. Do not shell out to `scripts/ops/work.sh` in this
mode; it stays reserved for `--yolo`'s unattended, headless dispatch.
