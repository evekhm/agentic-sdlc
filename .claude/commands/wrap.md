---
description: Close out this session, or refresh its handoff snapshot mid-flight. Writes ops/handoffs/handoff-<seat>-<date>.txt and prints the command that resumes from it. Prototype door for #85; when scripts/ops/wrap.sh exists this file calls it instead of prompting for the same work.
argument-hint: [<seat-or-slug>] [--snapshot]
allowed-tools: Bash(git *), Bash(gh *), Bash(scripts/ops/*), Bash(ops/harness/*), Bash(ops/waves/*), Bash(ls *), Bash(cat *), Bash(jq *), Read, Write, Edit, Grep, Glob
---

!`scripts/ops/wrap.sh "${CLAUDE_SESSION_ID:-session}" $ARGUMENTS || true`

## Modes

Read `$ARGUMENTS`.

- **`--snapshot`** — write or refresh the handoff and **keep working**. Steps 1,
  4, 5, 6 and the report are skipped. Use it whenever the statusline turns
  yellow, before a long or risky operation, and after any decision worth
  surviving a crash. A snapshot costs one file write; the state it protects
  costs a whole session.
- **no flag** — full close-out. Every step, then stop.

The two modes write the same file at the same path. A close-out is the last
snapshot plus the reconciliation, so running `--snapshot` often makes the final
`/wrap` cheap.

## Seat

The seat name is the resume token, so it must be stable for the life of the
work. Resolve it in this order and state which applied:

1. the argument, when one is given;
2. `$CLAUDE_SEAT`, for a session launched by `ops/waves/seat.sh`;
3. an existing `handoff-<slug>-<today>.txt` you already wrote this session;
4. otherwise **mint one**: a short kebab-case slug naming the work, not the
   session (`harness-statusline`, `poller-fix-round`). Say plainly that you
   minted it and that it is what resumes this work.

## State, gathered first

Cheap probes, both modes:

!`echo "seat arg: '$ARGUMENTS'   CLAUDE_SEAT: '${CLAUDE_SEAT:-}'   session: ${CLAUDE_SESSION_ID}"; F=~/.claude/context/${CLAUDE_SESSION_ID}.json; if [[ -r "$F" ]]; then jq -r '"context: \(.used_tokens)/\(.ceiling) (\(.pct)%)   spend: $\(.cost_usd)   cache: \(.cache.hit_pct)% \(.cache.ttl)"' "$F"; else echo "context: no side-channel file yet"; fi; R="$(git rev-parse --path-format=absolute --git-common-dir)/.."; git -C "$R" status --short --branch 2>&1 | head -20`

Network and worktree probes, close-out only — they cost seconds and kilobytes,
and a snapshot has no use for them:

!`case "$ARGUMENTS" in *--snapshot*) echo "[skipped: snapshot mode]";; *) git fetch origin --quiet 2>&1; echo "--- behind origin/main (empty = up to date):"; git log HEAD..origin/main --oneline 2>&1 | head -10; echo "--- my open PRs:"; GH_TOKEN="$(cat ~/.secrets/gh_odyssey_bot_pat)" gh pr list --author '@me' --state open --json number,headRefName,mergeable,title -q '.[] | "#\(.number) \(.headRefName) \(.mergeable) \(.title)"' 2>&1 | head -15; echo "--- worktrees:"; scripts/ops/worktrees.sh 2>&1 | tail -20; echo "--- recent handoffs:"; R="$(git rev-parse --path-format=absolute --git-common-dir)/.."; ls -t "$R/ops/handoffs" 2>/dev/null | head -6;; esac`

## Short-circuit

**Read the state above before doing anything else.** When it shows a clean tree,
no divergence, no open PRs of yours, and this session produced no decision, no
`runs/` artifact and no tracker change, there is nothing to hand off. Say so in
one line, write no file, and stop. Do not run further probes to confirm an
absence the state block already shows.

A session's handoff is worth its cost when a successor would be lost without
it. An empty session has no successor problem.

## Steps

Work through these in one pass. Batch independent shell checks into a single
call, and skip any step the state block already answered — re-deriving a fact
you have been handed is the main way this command gets expensive.

**1. Nothing in flight.** *(close-out only)* Any subagent, workflow or
background task of this session still running: wait for it or stop it. Never
write a close-out describing work whose result you have not seen.

**2. Pushed and synced.** Anything uncommitted or unpushed: push it as the bot
per CLAUDE.md and name the branch and PR. A deliberate exception gets stated
with its reason. If the divergence check above is non-empty, say so.

**3. Tracked, never only chatted.** Every decision, proposal and follow-up from
this session maps to an issue, a PR, or an explicit "deferred, no tracker" line
in the handoff. File what is missing now (`intent:new` for new work). This is
the check that matters most — chat is not a tracker.

**4. Dispositions.** *(close-out only)* Every `runs/` artifact you produced that
led to an action gets its footnote:
`--- Disposition (YYYY-MM-DD): filed as #<issue>; graduated to <path> via PR #<n>.`
or an explicit "deferred, no tracker".

**5. Claims and worktrees.** *(close-out only)* An issue you hold and did not
finish: comment that you are standing down and it is unclaimed, then remove
your own worktree. Never a peer's, and never one dirty, unpushed or locked.

**6. Spend.** Record the context size, spend and cache figures the state block
printed — they come from this session's own side-channel file, written by the
statusline. In close-out mode also run `scripts/ops/session_spend.sh` on this
session's transcript directory for the fuller picture: cache hit rate
`read/(read+write+fresh)` and tokens-per-message. Either alone hides the other.

A handoff that records "ended at 178K, $4.20, cache 71%" tells the operator
whether the seat was wrapped early enough. That is the feedback loop.

**7. Write the handoff.** Path, always **absolute** into the primary checkout
(a relative path written from a worktree dies with the worktree):

```text
<primary-checkout>/ops/handoffs/handoff-<seat>-<YYYY-MM-DD>[-n].txt
```

`-n` increments only when a *different* session already wrote today's file for
this seat. Your own snapshots overwrite your own file in place, so a session
leaves one handoff behind however many times it snapshots.

Write it for someone with zero context on this session:

- What you were doing and the exact point you stopped.
- Every issue and PR you touched, by number, with its state and head SHA.
- Open decisions the successor must make, with the options you already ruled
  out and why. A named open question beats a plausible guess.
- Traps, false failures and tooling gotchas you hit.
- Manual steps that remain the operator's.
- **FIRST ACTION**: the single next thing the successor should do.

In `--snapshot` mode, mark it `SNAPSHOT (session still running, written
<HH:MM>Z)` on the first line, so a successor knows it may be mid-thought. The
close-out replaces that line.

## Report

Always end with the resume command, verbatim and copyable:

```text
handoff:  <absolute path>
resume:   ops/waves/seat.sh <seat>
session:  ${CLAUDE_SESSION_ID}
```

`seat.sh` with a standing seat (`advisor`, `verifier`) loads that seat's role
prompt plus the handoff. With any other slug it treats the handoff as the whole
inherited state and refuses to start when no handoff for that slug exists, so a
typo cannot silently resume someone else's work. Either way the `SessionStart`
hook injects the file, so the successor opens already primed.

Nothing has to be remembered: `ops/waves/seat.sh --list` shows every resumable
seat newest first, and `ops/waves/seat.sh --last` resumes the newest handoff of
any seat. Say so in the report, so the operator never has to keep the slug.

**Resuming means a fresh session primed by the handoff.** `claude --resume`
replays the whole prior transcript into context and charges for it again on the
first turn; there is no cheap-resume mode. The session id is printed for
`session_spend.sh` and for finding the transcript, and it is the wrong thing to
start the successor with.

In `--snapshot` mode, print those two lines and continue working.

In close-out mode, add: tracked versus deferred, anything still unpushed, and
the operator's manual steps. Then stop.