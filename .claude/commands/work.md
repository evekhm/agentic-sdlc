---
description: Work a tracker issue — at the keyboard by default (resolve <n>, claim it if nobody has, and stop at its state and stage for this session to drive), or handed off with --yolo (headless dispatch of the owning persona, the pre-#441 behavior). Relative by design, so it runs the copy of the scripts in this session's working directory, not another checkout's (#43 D16, #441)
argument-hint: '[<issue-number>] [--as <persona>] [--yolo]'
allowed-tools: Bash(scripts/ops/work_dispatch.sh:*), Bash(cd:*), Bash(echo:*)
---

!`OUT="$(scripts/ops/work_dispatch.sh $ARGUMENTS)"; STATUS=$?; echo "$OUT"; echo "[work_dispatch.sh exit $STATUS]"; if [ "$STATUS" -eq 0 ] && ! echo "$OUT" | grep -q 'already carries in-progress'; then WT="$(echo "$OUT" | tail -1)"; [ -d "$WT" ] && cd "$WT" && echo "==> entered $WT"; fi`

If the output above starts with `NEEDS_PICK`, ask the user which numbered
issue to work from the list, then re-run this command with that number.

If the exit code is 1 (a bad argument, or `--as` given without
`--yolo` — guided mode has no dispatch to hand `--as` to), stop there
and relay the `work_dispatch.sh: ...` message plainly; do not retry on
your own guess of what was meant.

If the output above contains `refused:` (exit 2 — the issue carries
`hold`, carries `blocked`, is closed, or carries
`status:review-stuck`), stop there: tell the user the refusal reason
plainly and do not drive the stage. This is the circuit breaker; it
applies even when the issue already carries `in-progress` from an
earlier claim.

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

If a step writes or updates an artifact (intent.md, spec.md) whose
"Open questions" section is non-empty, that pause is not the generic
"what's next" — the same turn, before doing anything else (including
opening the PR), present each open question to the user by name and
ask for a decision. A question counts as resolved only once the user
has actually seen it and either answered it or explicitly said to
leave it open; it never resolves by default omission or by moving on.
