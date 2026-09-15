---
description: "Fast-track an issue through owner-authorized ladder compression (combining intent, spec, plan, and implementation into a single round)"
argument-hint: '<issue-number> [--as <persona>] [--changelog-reason <text>] [--spec-reason <text>] [--no-pr] [--no-dispatch] [--dry-run]'
allowed-tools: Bash(scripts/ops/fast.sh:*), Bash(scripts/ops/digest.sh:*), Bash(echo:*)
---

!`scripts/ops/digest.sh $ARGUMENTS; echo "---"; scripts/ops/fast.sh $ARGUMENTS; echo "[fast.sh exit $?]"`

Once the commands above finish, tell the user in one short message:
the issue number and title (from the digest), what `fast.sh` did (or
would do, on `--dry-run`), and the resulting branch/PR if one was
created. If it refused instead, state the refusal reason plainly.
