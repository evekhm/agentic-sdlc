---
description: Work a tracker issue — at the keyboard by default (resolve <n>, claim it if nobody has, and stop at its state and stage for this session to drive), or handed off with --yolo (headless dispatch of the owning persona, the pre-#441 behavior). Relative by design, so it runs the copy of the scripts in this session's working directory, not another checkout's (#43 D16, #441)
argument-hint: '[<issue-number>] [--as <persona>] [--yolo]'
allowed-tools: Bash(scripts/ops/work_dispatch.sh:*), Bash(echo:*)
---

!`scripts/ops/work_dispatch.sh $ARGUMENTS; echo "[work_dispatch.sh exit $?]"`

If the output above starts with `NEEDS_PICK`, ask the user which numbered
issue to work from the list, then re-run this command with that number.

Otherwise, once the digest is printed, before doing anything else tell
the user, in one short message: the issue number and title, its
current stage, who owns that stage, and what artifact you're about to
produce or change. Then stop and wait for them to say go.

From there, drive the stage one step at a time, in this session — you
are the "guide me step by step" this command exists for, not an
unattended dispatch. After each concrete step (a file written, a
command run, a decision made), say what you did and what's next, and
pause for the user before continuing to the next step. Do not shell
out to `scripts/ops/work.sh` in this mode; it stays reserved for
`--yolo`'s unattended, headless dispatch.
