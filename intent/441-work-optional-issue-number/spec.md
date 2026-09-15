# Spec: `/work` at the keyboard and handed off (#441)

**Issue:** #441 · **Stage:** design · **Status:** Approved (2026-09-15) ·
**Owner:** odyssey (`evekhm-odyssey-app[bot]`)

## Why this spec exists

#441 moved from its issue body to implementation with no intent.md, no
spec.md and no plan.md. The issue body served as the intent; the
operator's rescope comment of 2026-09-11 on the issue thread (PR #451,
commit 3e44ed0) withdrew `/next` and folded its scope into `/work`
without `--yolo`; PR #462 built it. Two reviewers (Argus, Atlas) found
on PR #462 that the only authorization the code cites is a README-spec
amendment (#35 D5), and a README decision cannot own a command's
behaviour. This spec is the implementer's record of the decisions that
were taken, under the owner-authorized fast-track (issue comment,
2026-09-11), written against PR #462's head on 2026-09-15; the human's
merge of PR #462 is the acceptance. Where the shipped code and a
decision below differ, the decision wins and the difference is a
fix-round item on PR #462, listed under Acceptance.

The issue's proposed outcome items 2, 3 and 4 (harness resolution
through the pins, dispatch to a persona, a bounded summary-and-link
return) are reversed by D1, with the reason. Its three open questions
are answered by D2 (first), D1 (second) and D4 (third).

## Relationships

- **refines #36** (`work.sh`): D7 (a number is the whole instruction),
  D8 (deterministic bash, refusals first), D9 (`--as`). None is
  reversed; D3 below keeps `work.sh` untouched.
- **refines #35 D5** (README text): D5 owns what README says about the
  doors; this spec owns what `/work` does. #35 D5's 2026-09-15
  ratification points here.
- **depends on #87** (`claim.sh`): the guided mode's claim, worktree
  and holder check are `claim.sh`'s.
- **refines #407 / #409** (`digest.sh`): the stop point is the digest
  those issues added.
- **refines #439** (`yolo`, `auto-close` labels): `--yolo` and
  `--auto-close` keep their meaning; this spec adds the mode without
  them.
- **supersedes** the issue body's items 2 to 4 and the `/next` name
  (operator rescope, 2026-09-11).

## Decisions

| ID | Decision |
|----|----------|
| D1 | **One command, two modes; guided mode is the session at the keyboard.** `/work [<n>]` without `--yolo` resolves `<n>` (D2), applies the circuit breaker (D4), claims when nobody holds the issue (D5), prints the digest and stops (D6). From there the operator's own session drives the current stage, step by step, as the persona that owns it, under the compiled resume protocol. `/work [<n>] --yolo` resolves `<n>` the same way and then runs `HEADLESS=1 scripts/ops/work.sh <n> [--as <persona>]`, the pre-#441 path, unchanged. `/next` is withdrawn and never ships. **Reverses the issue's proposed outcome items 2, 3 and 4** (harness resolution, persona dispatch, bounded summary return) for the guided mode. Reason (operator, 2026-09-11): the value of the guided mode is the human present at each step, reading and answering as the artifact is produced; a persona dispatched out of the session with a summary coming back is what `--yolo` plus the Done/Decided/Next/Blocked handoff comment already provides. The issue's second open question (how the session waits on a headless `agy` call) is void: guided mode starts no subprocess that outlives the command, and `--yolo` returns when `work.sh` returns, as before. An in-session dispatch with a bounded return, if wanted later, is a new intent that refines this one. Testable: `work_dispatch.sh <n>` with no `--yolo` exits without invoking `work.sh`; with `--yolo` it execs `work.sh` under `HEADLESS=1`; `grep -rc '/next' README.md .claude/commands` is 0 for every file. |
| D2 | **Resolution order for `<n>`, first match wins.** (1) An explicit argument: a positive integer, with or without a leading `#`. (2) The current branch when it matches `<actor>/<n>-<slug>`, the shape `claim.sh` (#87) writes. (3) The last issue this session resolved, read from a per-session state file under the harness side-channel directory (`$AGENTIC_CTX_DIR`, else `$CLAUDE_CTX_DIR`, else `$AGY_CTX_DIR`, else `~/.claude/context`, else `/tmp/agentic-context`), keyed by the session id and used only while that issue is open; with no session id this step is skipped. (4) None of those: the resolver prints `NEEDS_PICK` and the open issues carrying no `in-progress`, one `<number>\t<title>` per line, and exits 3; the command asks the operator which one and reruns with the number. Every successful resolution (1 to 3) is written back as the new last-touched issue. Any other first argument (free text, a second number) is exit 1 with a message; `/idea <text>` is the door for text. This answers the issue's first open question: the number is optional and defaults to the issue the session is already on. Testable: each of the four sources has a fixture in `scripts/ops/tests/resolve_work_target_test.sh`; a closed last-touched issue falls through to (4); `work_dispatch.sh 441 442` exits 1. |
| D3 | **`work.sh` is untouched; the new logic sits in front of it.** #36 D7 stands: `work.sh` takes the number and `--as` and nothing else. `scripts/ops/resolve_work_target.sh` and `scripts/ops/work_dispatch.sh` decide which number reaches it and whether it is called. `--as <persona>` is a dispatch override (#36 D9) and is forwarded only under `--yolo`; without `--yolo` there is no dispatch to override, so `--as` is refused with exit 1 and a message naming `--yolo`. Testable: `git diff main -- scripts/ops/work.sh` is empty on PR #462; `work_dispatch.sh 441 --as argus` exits 1 before any digest line; `work_dispatch.sh 441 --as argus --yolo` reaches `work.sh` with `--as argus`. |
| D4 | **The circuit breaker applies to guided mode, before any claim, whatever `in-progress` says.** After resolution and before `claim.sh` is consulted, guided mode refuses with exit 2 and a `refused:` line when the issue carries `hold`, carries `blocked`, is closed, or carries `status:review-stuck`: the same set `work.sh` refuses at its steps (a), (c) and (d), in that order. An existing `in-progress` label does not bypass the check, because the branch that leaves an existing claim in place (D5) skips `claim.sh`, the only other component that refuses. On a refusal the command prints the reason and the session does not drive the stage. This answers the issue's third open question: guided mode refuses on `hold` and on `status:review-stuck` the same way every other writer does; a human at the keyboard is why the reason is printed plainly. Testable: one fixture per condition, each with `in-progress` also present, exits 2 and prints `refused:`; `scripts/ops/tests/work_dispatch_test.sh` carries all four. |
| D5 | **Claim once; take nothing from a holder.** In guided mode, when the issue carries no `in-progress`, the command runs `claim.sh <n>` (#87): claim comment, `in-progress`, worktree, and the session moves into that worktree as `/claim` does. When `in-progress` is present the command leaves the claim exactly as it is, prints that it did so, and stops; the digest's last-comment line shows the holder. The command removes no claim and posts none over another. The operator, reading the digest, decides whether this session continues (their own earlier claim, or a stale claim they take over by hand) and says so. Testable: an issue without `in-progress` gains the claim comment and the label and the session's cwd becomes the new worktree; an issue with `in-progress` gains no comment, keeps its label, and the output contains `already carries in-progress`. |
| D6 | **The stop point is the digest; the session's first move is a report, then a wait.** Guided mode ends when `digest.sh <n>` (#407) has printed and the claim rule (D5) has run. The command file (`.claude/commands/work.md`) then binds the session: one short message naming the issue and title, the stage, the persona that owns it and the artifact about to be produced or changed (`personas/lifecycle.json` is the source for stage, owner and artifact); then a wait for the operator's go; then one step at a time, reporting after each and pausing. In this mode the session never calls `scripts/ops/work.sh`. The artifact, the branch, the pull request and the handoff comment are the owning persona's, per the compiled resume protocol; guided mode changes who is at the keyboard, and the rung's output is unchanged. Testable: `work.md` states the report, the wait, the step-by-step rule and the `work.sh` exclusion; `work_dispatch.sh` prints the digest lines before the claim output. |
| D7 | **README and the living spec say what D1 to D6 say.** README describes `/work` in three places (the "At the keyboard" paragraph, the two-ways diagram, the doors line), and each describes the guided mode as D1: after the digest the session drives the stage; no sentence has `/work <n>` without `--yolo` starting a persona on its pinned harness or handing back a summary. `docs/SPEC.md` carries the `/work` door with both modes, the four resolution sources and the four refusal conditions, upserted in PR #462 (AGENTS.md, "The living spec"). #35 D5 governs README's shape (no fenced command, seven doors inline) and its 2026-09-15 ratification points here for the behaviour. Testable: no line of README's "At the keyboard" paragraph contains `pinned harness`; `docs/SPEC.md` names `work_dispatch.sh`, `resolve_work_target.sh`, the four resolution sources and the four refusal conditions. |

## Acceptance

Each row names the decision it derives from and the input that turns
it red. Rows marked **fix-round** are red at PR #462's head on
2026-09-15 and are owed by the implementer on that PR.

- `work_dispatch.sh 441` (no `--yolo`) prints the digest and exits
  without invoking `work.sh`; red if `work.sh` runs (D1).
- `work_dispatch.sh 441 --yolo` execs `work.sh 441` under `HEADLESS=1`;
  red if `HEADLESS` is unset or a digest is printed first (D1).
- Bare `/work` on branch `athena/441-x` resolves 441; on `main` with a
  state file naming an open issue it resolves that issue; with a state
  file naming a closed issue it prints `NEEDS_PICK` and exits 3; red if
  any of the three resolves differently (D2).
- `resolve_work_target.sh '#441'` prints `441`; `resolve_work_target.sh
  foo` exits 1 (D2).
- `git diff main -- scripts/ops/work.sh` is empty on PR #462 (D3).
- `work_dispatch.sh 441 --as argus` exits 1 before any digest line; red
  if it prints a digest or silently drops `--as` (D3). **Fix-round:**
  the shipped script accepts `--as` in guided mode and drops it.
- For each of `hold`, `blocked`, closed state and `status:review-stuck`,
  with `in-progress` also present, guided mode exits 2 with a
  `refused:` line and posts nothing (D4). **Fix-round:** the shipped
  script checks `hold` and `blocked`; closed and `status:review-stuck`
  are checked only inside `claim.sh`, which the `in-progress` branch
  skips.
- An unclaimed issue gains one claim comment and `in-progress`; a
  claimed issue gains nothing and the output contains `already carries
  in-progress` (D5).
- `.claude/commands/work.md` contains the report-then-wait rule, the
  step-by-step rule and the `work.sh` exclusion (D6).
- README's "At the keyboard" paragraph describes the guided mode as the
  session driving the stage after the digest; red while it says
  `/work <n>` "starts the owning persona on its pinned harness and
  hands you back a short summary" (D7). **Fix-round:** the paragraph
  says exactly that at PR #462's head; the doors line and the diagram
  already match D1.
- `docs/SPEC.md` names both modes, the four resolution sources and the
  four refusal conditions (D7).

## Open questions

None. The issue's three are answered in D2, D1 and D4.

## Non-goals

- Any change to `scripts/ops/work.sh`, `personas/lifecycle.json` or
  `config/deployments.yaml`.
- Resolving free text to an issue; `/idea` owns that door.
- An in-session persona dispatch with a bounded summary return; that is
  a future intent refining this one.
- The advisor's batch scheduling across the backlog (#446).
