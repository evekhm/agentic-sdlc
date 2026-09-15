# Intent: claim.sh reads any prose containing "depends on" as a dependency line and refuses the claim

**Issue:** #372 · **Stage:** plan · **Author:** athena (`evekhm-athena-app[bot]`) · **Status:** Accepted

## Problem

`scripts/ops/claim.sh` derives an issue's dependencies by scanning the
whole issue body for any line matching `grep -Ei 'depends on'`
(`claim.sh:166`), then treats every `#n` found on a matching line as a
blocker that must be closed before the claim proceeds (`claim.sh:167-177`).
The scan has no anchor. A sentence that merely contains the words
"depends on," in prose, in a citation, or in a quotation of a prior
error, reads as an actual declaration.

Three live instances so far:

1. **2026-09-10, #353.** The body carried "Provenance verification
   stays in place (#318 depends on it). No closing keyword closes
   #245." claim.sh mis-read the sentence as a declaration and refused
   the claim, citing #245, which was only a citation to a rule, as
   still open. #353 was the operator's priority issue at the time;
   it could not be claimed until the sentence was reworded.
2. **2026-09-11, #404 (implement rung).** The intent body carried
   "Depends on nothing for the prompt change; #117 ..." and the poller
   refused the claim with `#404 depends on #117, which is still open`,
   even though the sentence's own leading words say the opposite.
3. **2026-09-15, #372's own body** (this issue). The evidence
   paragraph quoting the #353 sentence above itself contains "depends
   on" on the same physical line as `#245`, so claim.sh refused the
   claim on #372 with `#372 depends on #245, which is still open`.
   The bug report about the bug tripped the bug.

Beyond blocking individual claims, `scripts/placement/vm-local/poll.sh`
calls `claim.sh` for every dispatch row; a false match there is logged
as a refusal and silently stalls the poller's ladder for that issue on
every tick, with no operator watching for it in real time.

### Root cause runs deeper than an unanchored regex

Anchoring the parser to a leading `Depends on` line (the fix `claim.sh`'s
own header comment already documents, and the fix originally proposed
here) narrows the false-positive rate but does not remove the
underlying collision, because the phrase "depends on" is dual-purposed
in this repo's own filing convention:

- `.claude/commands/idea.md:28`, `.claude/commands/bug.md:35`,
  `personas/athena.yaml:15`, and `personas/skills/intake-protocol.md:25`
  all instruct the filer to name a related issue's relationship using
  one of four words ("absorbs, refines, depends on, supersedes") as
  descriptive prose in the Relationships section of an issue body.
- `claim.sh`'s dependency check searches the same body for the same
  phrase to derive a hard, machine-enforced blocker.

A Relationships-section bullet that opens with "Depends on #245 for
provenance context" (a description, following the documented filing
convention) and a genuine blocking declaration ("Depends on #245")
are the same shape at the start of a line. Anchoring the regex still
leaves this class of collision open; it only closes the mid-sentence
and quoted-citation cases already observed on #353, #404, and #372
itself.

## Proposed outcome

The operator has directed (2026-09-15) that prose parsing of "depends
on" be retired outright. Hardening the regex further was rejected
given the structural collision above. GitHub's native Issue
Dependencies (`blocked_by`/`blocking`, live and queryable on this
repo, verified via `gh api repos/evekhm/agentic-sdlc/issues/372`
returning `issue_dependencies_summary`, and via
`repos/.../issues/372/dependencies/blocked_by`) become the sole
mechanism for a machine-enforced dependency:

1. `claim.sh`'s dependency check no longer reads the issue body at
   all. It calls `repos/$GITHUB_REPO/issues/$NUMBER/dependencies/blocked_by`
   (each returned item already carries `.state`, per GitHub's response
   shape; no per-item follow-up fetch needed), filters to
   `.state == "open"`, and refuses the claim naming each still-open
   blocker by number and title. `claim.sh` already fetches the full
   issue payload into `view` (`claim.sh:104`), which includes
   `issue_dependencies_summary`, so a `total_blocked_by == 0` check can
   skip the extra API call when there is nothing to check.
2. The word "depends on" becomes machine-inert everywhere in an issue
   body, permanently. The Relationships-section convention in
   `idea.md`/`bug.md`/`athena.yaml`/`intake-protocol.md` keeps "depends
   on" as one of its four descriptive relationship words for naming
   prior art. `claim.sh` never reads it again.
3. When a filer needs a real hard dependency, they link it natively at
   file time:
   `gh api --method POST repos/$GITHUB_REPO/issues/<n>/dependencies/blocked_by -F issue_id=<blocker's database id>`
   (the database id comes from `gh api repos/.../issues/<blocker> --jq .id`).
   `.claude/commands/idea.md` and `bug.md`, and AGENTS.md's "Before
   filing an issue" step, gain this instruction and drop any mention of
   writing a "Depends on" line as a blocking declaration.
4. `AGENTS.md` ("Working the tracker", step 1: "every issue named in
   its 'Depends on' line is closed") is rewritten to describe the
   native mechanism.
5. `scripts/ops/tests/claim_test.sh` drops every "Depends on"
   line-parsing test case (there is nothing left in `claim.sh` to
   parse) and gains cases for: a native open blocker refuses the claim
   and names it; a native blocker whose only links are closed leaves
   the claim alone; a body containing "depends on" anywhere at all
   (prose, citation, or a leading Relationships-section "Depends on
   #n" bullet) never affects the claim, regardless of what native
   links exist.
6. **Migration.** Five open issues currently carry a genuine leading
   "Depends on" line pointing to a still-open blocker, and none of
   them hold a native link yet (checked 2026-09-15):
   `issue_dependencies_summary.total_blocked_by == 0` on each. Cutover
   creates the matching native link for each pair before `claim.sh`
   stops reading body text, so no issue loses its live protection at
   the switch:
   - #408 → #85
   - #31 → #11
   - #399 → #85, #330
   - #148 → #64, #147
   - #147 → #44
   The plan/spec stage re-checks this list immediately before cutover,
   since new prose-form dependencies can appear on newly filed issues
   between now and then.

## Affected users and systems

- **`scripts/ops/claim.sh`**: the dependency check (`claim.sh:163-177`)
  is replaced with a native-dependency lookup; no body-text scan
  remains.
- **`scripts/ops/tests/claim_test.sh`**: line-parsing cases removed,
  native-dependency cases added.
- **`scripts/placement/vm-local/poll.sh`**: calls `claim.sh` for
  every dispatch row; removing the body scan removes this entire class
  of false-positive stall.
- **`AGENTS.md`** ("Working the tracker" step 1) and
  **`.claude/commands/idea.md`, `bug.md`** (filing instructions):
  updated to point filers at the native link.
- **`personas/athena.yaml`, `personas/skills/intake-protocol.md`**:
  the "absorbs, refines, depends on, supersedes" Relationships wording
  stays as descriptive prose; a note that it has no enforcement effect
  helps future filers avoid assuming otherwise.
- **#408, #31, #399, #148, #147**: the five open issues named in the
  migration step above, each needing a native link created at cutover.
- **Operators and personas filing/claiming issues**: declare a real
  dependency once, natively, at file time. Free-text mentions of
  "depends on" anywhere in a body have zero effect on any claim.

## Constraints

- Fail-closed: a genuine open native blocker must still refuse the
  claim, naming it.
- This intent departs from #372's originally stated constraints ("No
  new flags on claim.sh. The declaration form stays what AGENTS.md
  documents") on direct operator instruction, given the root-cause
  finding above: hardening the prose form leaves a real collision with
  this repo's own Relationships-section filing convention in place.
  No new *flag* is added to `claim.sh`; the declared form itself is
  what changes, deliberately.

## Relationships

- **Refs #353, #404** (live instances of the defect that motivated
  this issue, cited above as evidence) and **#363** (named in the
  issue body as related tracker plumbing; a separate poller defect,
  not another live instance of this one).
- **Comment from Atlas (evekhm-atlas-app)** on this issue proposed
  native Issue Dependencies as a fallback-backed alternative: check
  `total_blocked_by > 0` first, and fall back to an anchored regex
  (`^[[:space:]]*Depends on:?[[:space:]]+#[0-9]`) for issues without a
  native link. That anchored fallback is correct and would have closed
  the three reported false positives; it was verified against the live
  API and against `claim.sh`'s existing `view` fetch during this
  intent's drafting. This intent goes further than Atlas's proposal
  per the operator's direction above: it drops the regex fallback,
  since a fallback still leaves the Relationships-section collision
  open for any issue that never gets a native link.

## Open questions

Both resolved by the operator (2026-09-15):

1. **Refusal message shape.** Resolved: name the blocking issue(s) by
   number and title (already available on each
   `/dependencies/blocked_by` item), e.g. `#372 is blocked by #245
   (open): <title>`.
2. **Filing ergonomics for the database-id lookup.** Resolved: no new
   helper script. `idea.md`/`bug.md` document the two-command sequence
   inline: `gh api repos/.../issues/<blocker> --jq .id`, then `gh api
   --method POST repos/.../issues/<n>/dependencies/blocked_by -F
   issue_id=<id>`.

## Non-goals

- No new CLI helper or wrapper script for linking native dependencies.
  The two-command `gh api` sequence above is the whole mechanism.
- No use of GitHub's separate "sub-issues" feature. This intent covers
  the `blocked_by`/`blocking` dependency relationship only.
- No change to the Relationships-section filing convention itself.
  `idea.md`, `bug.md`, `athena.yaml`, and `intake-protocol.md` keep
  "absorbs, refines, depends on, supersedes" as descriptive prose;
  only its machine effect on `claim.sh` is removed.
- No `claim.sh` code change in this stage. This document is the plan
  stage's artifact; the file-level implementation steps belong to the
  plan.md/spec.md that follow.
