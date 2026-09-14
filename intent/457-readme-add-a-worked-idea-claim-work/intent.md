# Intent: README worked walkthrough of /idea, /claim, /work

**Issue:** #457 · **Stage:** plan · **Author:** athena
(`evekhm-athena-app[bot]`)

## Problem

README's "What it solves" section lists the seven doors (`/idea`,
`/bug`, `/claim`, `/release`, `/work`, `/fast`, `/wrap`) as one
paragraph of prose each (PR #451's text, carried on this branch). No
part of README shows one issue moving through `/idea`, `/claim` and
`/work` with what those commands print. A reader takes the doors list
on faith, and the doors are the whole typed input to the loop, so the
one thing README asks a reader to do is the one thing it never shows
being done. The repository set the precedent for itself: #35 D12 kept
README on the full ladder so its own `intent/35-readme/` folder would
be a worked example. The doors have no such example.

## Proposed outcome

One worked walkthrough, in prose, inside "What it solves" directly
after the doors list, following this issue, #457, from filing to the
plan rung:

1. `/idea <text>` runs the tracker search first, reports what matched
   (here PR #451 and #35), files the issue with `intent:new`, and
   replies with the number, the URL and each related issue with its
   state.
2. `/claim 457` verifies the issue, posts the claim comment, prints the
   worktree path as its last line and moves the session into that
   worktree on branch `<actor>/457-<slug>`.
3. `/work` with no number resolves `457` from the worktree's branch,
   prints the digest (stage `plan`, owner athena, artifact
   `intent.md`) and stops so the session drives the stage.

Each step names the command once, then states in a sentence or two
what it printed, quoting short fragments inline (the issue line, the
worktree path with the home prefix redacted, the digest's stage line).
There is no fenced block of output. The example is self-referential
on purpose: the issue the walkthrough follows is the issue that added
the walkthrough, and its issue link is the currency marker #35 D1
allows.

## Affected users and systems

- Readers of README.md, the one audience #35 D1 names.
- `README.md`, section "What it solves", the only file the
  implementing change touches.
- `intent/35-readme/spec.md`: read, not amended. Every #35 decision the
  walkthrough touches is honoured as written (Constraints below).
- Unchanged: `.claude/commands/*.md`, `scripts/ops/*.sh`,
  `docs/SPEC.md`, `personas/**`.

## Constraints

1. **Output fidelity.** Every quoted fragment comes from running the
   commands as they exist on this branch (`scripts/ops/intake.sh`,
   `scripts/ops/claim.sh`, `scripts/ops/work_dispatch.sh`,
   `scripts/ops/digest.sh`) and pasting the result, then redacting the
   home prefix from any path (#35 D6(b); `scripts/ci/sanitize_check.sh`
   must pass). The behaviour described is this branch's: `/work`
   without `--yolo` prints the digest and stops for the session to
   drive the stage (`.claude/commands/work.md`, #441). It does not
   dispatch a persona.
2. **#35 D5 stays as written** (operator ruling 2026-09-14). No fenced
   block carries command output; every fenced block in README remains
   a `text` diagram; `/wrap` is not mentioned by the walkthrough, so
   `grep -c '/wrap' README.md` stays 1; `/work <n>` may recur inside
   "What it solves" as D5's PR #451 amendment allows.
3. **#35 D2.** No new `##` heading. The walkthrough is a bold-led
   paragraph group inside the existing section, so the section list
   in `intent/35-readme/spec.md` is unchanged.
4. **#35 D1.** No status narration: no "today", "currently", "not yet".
   The walkthrough states what the commands printed for #457 as fact
   and links the issue.
5. **#35 D3.** The walkthrough supplements the doors list. It does not
   restate what a door is for; each command appears as an action
   followed by what it printed.
6. **#35 D6(c).** No persona procedure: the walkthrough stops at the
   digest and names stage, actor and artifact. How athena then works
   the plan rung stays in the compiled resume protocol.
7. **Real issue, real transcript** (operator ruling 2026-09-14): the
   example uses #457 itself. When a later change to a door alters what
   it prints, the walkthrough is refreshed in the same PR, the same
   way #35 D6 orders `config/` first and README second.
8. **Prose style** per AGENTS.md "Prose style", checked with its grep
   before the PR opens; every count is zero.
9. **Delivery** (coordinator decision 2026-09-14): the README edit
   ships in the single PR from this branch under #441, together with
   PR #451's doors text and #441's plumbing. PR #451 is superseded by
   that PR and closed by hand after the merge.

## Relationships

- **refines #35** (README.md; open). #35's spec owns every decision
  this intent touches: D1, D2, D3, D5, D6. None is reversed.
- **depends on #441** (`/work` with an optional number, stops at the
  stage without `--yolo`): the walkthrough describes that behaviour
  and ships in #441's PR.
- **supersedes PR #451 as a standalone landing**: the doors list the
  walkthrough follows is #451's text, carried on this branch.
- **extends #87** (closed): `/claim <n>` is #87's `claim.sh` wrapped
  by PR #451's command file.
- **refines #409** (merged): `/idea` and the pre-dispatch digest are
  #409's.
- **#416** (open, review-stuck): once the compiled command source
  lands, the walkthrough's command syntax is re-checked against it.
- Tracker searched 2026-09-14 with
  `scripts/ops/tracker_search.sh --files README.md --terms walkthrough
  "worked example"`: matched PR #451 (file-scoped) and #35 (keyword),
  both named above. No other prior art.

## Open questions

- Bare `/work` (shows #441's branch resolution) or `/work 457` (one
  fewer thing to explain) in step 3. Decided at design; the default
  if unruled is bare `/work`, since the doors list already states the
  number is optional and the walkthrough is the one place that shows
  it.

## Non-goals

- Any change to command or script behaviour.
- A walkthrough of `/bug`, `/release`, `/fast` or `/wrap`.
- A fenced transcript block, or any amendment to #35 D1, D2, D4 or D5.
- A second copy of the walkthrough anywhere else (`docs/`, AGENTS.md,
  the command files).
- Rewording the doors list itself.
- Waiting for #416's compiled commands before landing.
