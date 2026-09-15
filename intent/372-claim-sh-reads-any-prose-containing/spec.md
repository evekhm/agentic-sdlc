# Spec: claim.sh reads any prose containing "depends on" as a dependency line and refuses the claim

**Issue:** #372 · **Status:** Approved (approval = merge of this PR) · **Author:** athena (`evekhm-athena-app[bot]`) · **Open questions:** none

## What is being built

`scripts/ops/claim.sh` currently derives an issue's dependencies by
scanning the whole issue body for `grep -Ei 'depends on'`
(`claim.sh:166`) and refusing the claim if any `#n` found on a
matching line is still open (`claim.sh:167-177`). This false-positives
on ordinary prose, citations, and quoted error messages (#353, #404,
#372's own body), and structurally collides with this repo's own
filing convention: `idea.md`, `bug.md`, `athena.yaml`, and
`intake-protocol.md` all tell filers to write "depends on" as free
descriptive prose in an issue's Relationships section.

This specification replaces the body-text scan with GitHub's native
Issue Dependencies API as the sole mechanism, per `intent.md`'s
Proposed outcome:

1. `claim.sh`'s dependency check reads `view.issue_dependencies_summary.total_blocked_by`
   (already present in the issue payload it fetches at `claim.sh:104`);
   when it is `0`, the check ends with no further API call. When it is
   greater than `0`, `claim.sh` calls
   `repos/$GITHUB_REPO/issues/$NUMBER/dependencies/blocked_by`, filters
   the returned items to `.state == "open"`, and refuses the claim,
   naming each still-open blocker by number and title.
2. The issue body is never read for dependency purposes again. No
   anchored regex, no fallback: the word "depends on" has zero machine
   effect anywhere in a body from this point on.
3. `AGENTS.md`'s claimable definition (`AGENTS.md:164-165`) and
   `claim.sh`'s own header docstring (`claim.sh:21`) are rewritten to
   describe the native mechanism.
4. `.claude/commands/idea.md` and `.claude/commands/bug.md` gain the
   two-command native-linking sequence at issue-filing time, replacing
   any instruction to write a "Depends on" line as a blocking
   declaration.
5. Five open issues that currently carry a genuine leading "Depends
   on" line pointing to a still-open blocker (checked 2026-09-15, none
   hold a native link yet) get that link created before this change
   merges, so none of them loses live protection at cutover: #408→#85,
   #31→#11, #399→#85 and #330, #148→#64 and #147, #147→#44.
6. `docs/SPEC.md` gains a paragraph documenting the native-only
   enforcement, satisfying the living-spec obligation for a behavior
   change to `claim.sh`'s claimable rule.

### Manifest of Files Touched by the Implementation Rung

- `scripts/ops/claim.sh`: replace the dependency-check block
  (`claim.sh:163-177`) with the native lookup described in D1; update
  the header docstring line describing the "depends on" refusal
  (`claim.sh:21`).
- `scripts/ops/tests/claim_test.sh`: remove the body-text dependency
  case (`claim_test.sh:196-204`); add the fixture support and cases
  described in D6.
- `AGENTS.md`: rewrite the claimable definition at lines 164-165 to
  describe the native dependency check.
- `.claude/commands/idea.md` (line 28) and `.claude/commands/bug.md`
  (line 35): add the two-command native-linking sequence at the point
  each currently names "depends on" as one of the relationship words;
  the relationship-word convention itself is unchanged (intent.md
  Non-goals).
- `docs/SPEC.md`: add a paragraph under `tracker.workflow` (or a new
  `ops.claim` section, implementer's choice) documenting native-only
  dependency enforcement.
- `CHANGELOG.md`: entry for the behavior change.
- Native dependency links created via `gh api` for the five pairs in
  D7 (an operational action against the live tracker; it touches zero
  files in this repository).
- `intent/372-claim-sh-reads-any-prose-containing/plan.md`: ordered
  implementation plan authored by Daedalus.

### Manifest of Files Touched by this PR (Athena)

- `intent/372-claim-sh-reads-any-prose-containing/intent.md`: Status
  updated to `Accepted`.
- `intent/372-claim-sh-reads-any-prose-containing/spec.md`: this
  specification.

### Forbidden Files (Untouched)

- `personas/athena.yaml`, `personas/skills/intake-protocol.md`: the
  "absorbs, refines, depends on, supersedes" relationship-word
  convention is unchanged (intent.md Non-goals); no edit needed since
  neither file instructs writing a body-parsed blocking declaration.
- `scripts/ops/work.sh`, `scripts/ops/poll.sh` and the rest of
  `scripts/placement/**`: these consume only `claim.sh`'s exit code
  and stay unaffected by the mechanism swap inside it.
- `config/**`: no configuration surface for this change.

## Decisions

| ID | Decision | Rationale |
|---|---|---|
| **D1** | **Native dependency check replaces the body-text scan entirely.** `claim.sh:163-177` becomes: read `issue_dependencies_summary.total_blocked_by` from the already-fetched `view`; if `0`, skip; otherwise call `repos/$GITHUB_REPO/issues/$NUMBER/dependencies/blocked_by`, filter to `.state == "open"`, and refuse naming each. No regex against `body` remains anywhere in the file. | *Adversary analysis:* Two defensible readings: (1) keep an anchored regex as a fallback for issues without a native link (Atlas's original review comment on #372); (2) drop body parsing entirely. Differing case: an issue writes "Depends on #64 for the autonomy switch" in its Relationships section, following the documented filing convention, with no intent to declare a hard blocker. Under Reading 1, that sentence still risks being read as a declaration whenever it opens a line, since the filing convention and the parser share the exact same trigger phrase. Under Reading 2, that sentence has zero effect regardless of wording or position, because nothing reads the body anymore. The operator selected Reading 2 directly (2026-09-15) for this reason. |
| **D2** | **Refusal names the blocker by number and title, one line per claim.** Format: `#<n> is blocked by #<m> (open): <title>`; multiple open blockers join on the same call with `; ` between them. | *Adversary analysis:* Two defensible readings: (1) quote the matched body text, as the current refusal does; (2) name the blocking issue directly, since native links carry `.number` and `.title` with no need to quote anything. Reading 1 has no body text to quote once D1 lands. Reading 2 is strictly more informative: the operator sees which issue blocks the claim and its title in one line, resolved by the operator directly (2026-09-15). |
| **D3** | **`total_blocked_by` short-circuits the extra API call.** When `issue_dependencies_summary.total_blocked_by` is `0`, `claim.sh` never calls `dependencies/blocked_by`. | *Adversary analysis:* Two defensible readings: (1) always call `dependencies/blocked_by` and check for an empty list; (2) trust the summary count already present in `view` to skip the call when it is `0`. Differing case: `claim.sh` runs against an issue with no dependencies at all, which is the common case. Under Reading 1, every claim costs a second API round trip; under Reading 2, the common case costs zero extra calls, since `view` is already fetched at `claim.sh:104`. The summary count serves only as a zero/non-zero gate; the list call is still made whenever it is non-zero, and each item's own `.state` is what the refusal checks (`claim_test.sh` covers a case where the summary count is non-zero but every listed item is closed). |
| **D4** | **`AGENTS.md`'s claimable definition and `claim.sh`'s header docstring describe the native mechanism.** `AGENTS.md:164-165` ("every issue named in its 'Depends on' line is closed") and `claim.sh:21` ("depends on: an issue named on a 'Depends on' line is still open") are rewritten to name `blocked_by` and the native API. | *Adversary analysis:* Two defensible readings: (1) leave the prose descriptions as-is since they only document behavior; (2) rewrite them to match the new mechanism. Differing case: a future contributor reads `AGENTS.md` to understand what makes an issue claimable and finds a description of a mechanism that no longer exists in the code. Under Reading 1, the documentation actively misleads; under Reading 2, it matches the implementation. |
| **D5** | **`idea.md`/`bug.md` document the native-linking two-command sequence at filing time; no new helper script.** `gh api repos/.../issues/<blocker> --jq .id`, then `gh api --method POST repos/.../issues/<n>/dependencies/blocked_by -F issue_id=<id>`. | *Adversary analysis:* Two defensible readings: (1) add a wrapper script (e.g. `scripts/ops/link-dependency.sh`) to reduce the two-command sequence to one; (2) document the two commands inline with no new script. The operator resolved this directly (2026-09-15) in favor of Reading 2: the sequence is rare enough (one link per real hard dependency, out of the many issues filed) that a dedicated script is unwarranted maintenance surface. |
| **D6** | **Test suite drops all body-parsing dependency cases and gains native-dependency cases.** `claim_test.sh:196-204` ("an open dependency blocks the claim") is removed. The `issue()` fixture helper gains an optional `total_blocked_by` argument that writes `issue_dependencies_summary.total_blocked_by` into the issue fixture; a new `blocked_by()` fixture helper writes `repos_test_repo_issues_<n>_dependencies_blocked_by.json`. New cases: (a) a native open blocker refuses the claim and names it; (b) a native blocker whose only links are closed does not refuse; (c) an issue whose body contains a leading "Depends on #<n>" line pointing to a still-open issue, with `total_blocked_by == 0`, is **not** refused, proving the body is never read. | *Adversary analysis:* Two defensible readings: (1) keep some body-parsing test cases as regression coverage in case a future change reintroduces body reading by accident; (2) remove them entirely, since asserting the *absence* of a behavior via cases that exercise a mechanism no longer under test proves nothing. Reading 2 is correct for the removed mechanism; case (c) above is the actual regression guard, since it exercises the exact false-positive shape from #353/#404/#372 and asserts the new code does not repeat it. |
| **D7** | **Migration to native links is a one-time operational step, executed before this PR's merge.** For each of the five pairs (#408→#85, #31→#11, #399→#85 and #330, #148→#64 and #147, #147→#44), the implementing session runs the two-command sequence from D5 against the live repository and verifies via a read of `dependencies/blocked_by` that each link now shows `state: open`, before the PR removing body parsing is merged. | *Adversary analysis:* Two defensible readings: (1) merge the `claim.sh` change first and backfill links afterward; (2) backfill first, verify, then merge. Differing case: between merge and backfill, a session claims #408 while #85 is still open. Under Reading 1, nothing refuses the claim: neither the old (removed) body scan nor the new (not-yet-linked) native check catches it, and the dependency silently stops being enforced for a real window. Under Reading 2, the native link exists before the old scan is removed, so the two mechanisms overlap and enforcement never lapses. This list is current as of 2026-09-15; the implementing session re-checks it immediately before executing the backfill in case a newly filed issue added a sixth pair meanwhile. |
| **D8** | **Living spec update: `docs/SPEC.md` gains a paragraph on native-only dependency enforcement.** This is a real behavior change to `claim.sh`'s claimable rule (a claim that would have been refused for a body-text reason before this change can now succeed, and vice versa for issues gaining native links), so `scripts/ci/spec_check.sh` requires a live `docs/SPEC.md` diff to pass, and a `Spec-impact: none` declaration on its own fails the check. | AGENTS.md's living-spec obligation requires `docs/SPEC.md` to reflect user- or system-visible behavior changes; the claimable rule is exactly that. |

## Acceptance

- **AT-372-1 (D1):** `grep -c "grep -Ei 'depends on'" scripts/ops/claim.sh` returns `0`; no reference to scanning `body` for dependency purposes remains in the file.
- **AT-372-2 (D1, D3):** For an issue whose `view.issue_dependencies_summary.total_blocked_by` is `0`, `claim.sh`'s call log (per `claim_test.sh`'s `$CALLS` fixture) does not contain a call to `dependencies/blocked_by`.
- **AT-372-3 (D1, D2):** For an issue whose `dependencies/blocked_by` list contains at least one item with `.state == "open"`, `claim.sh` exits 2 and its output matches `is blocked by #<n> (open): <title>` for each such item.
- **AT-372-4 (D1):** For an issue whose `dependencies/blocked_by` list contains only items with `.state == "closed"`, `claim.sh` proceeds past the dependency check.
- **AT-372-5 (D1, D6c):** For an issue whose body contains a leading `Depends on #<n>` line naming a still-open issue, and whose `issue_dependencies_summary.total_blocked_by` is `0`, `claim.sh` proceeds past the dependency check; the claim is not refused.
- **AT-372-6 (D6):** `bash scripts/ops/tests/claim_test.sh` exits 0, including the new cases from D6 and none of the removed cases.
- **AT-372-7 (D4):** `AGENTS.md`'s claimable definition and `claim.sh`'s header docstring name the native dependency mechanism; neither mentions a "Depends on" body line as the enforcement path.
- **AT-372-8 (D5):** `.claude/commands/idea.md` and `.claude/commands/bug.md` each document the two-command native-linking sequence; neither instructs writing a "Depends on" line as a blocking declaration.
- **AT-372-9 (D7):** Before this PR merges, `gh api repos/evekhm/agentic-sdlc/issues/<n>/dependencies/blocked_by` for each of `n` in `{408, 31, 399, 148, 147}` includes every paired blocker from D7 with `state: open`.
- **AT-372-10 (D8):** `bash scripts/ci/spec_check.sh` passes on the strength of an actual `docs/SPEC.md` diff, and `bash scripts/ci/changelog_check.sh` passes with a `CHANGELOG.md` entry present.

## Open questions

none
