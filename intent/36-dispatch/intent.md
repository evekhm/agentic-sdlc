# Intent: one-argument dispatch

**Issue:** #36 · **Author:** athena (`evekhm-athena-app[bot]`) ·
**Status:** accepted on merge of this PR

## Problem

The shortest correct instruction to a persona session today is a
paragraph: the stage, the folder, the artifact, the handoff format.
AGENTS.md ("Working the tracker") already tells every persona to read
the labels and the last handoff, but no single place states the
mapping *status label → owning persona → artifact owed*, so a session
handed a bare number cannot reliably infer what it is for.

That mapping exists implicitly three times — as prose in INTENT.md's
lifecycle, as a path→next-label rule inside
`scripts/ci/lifecycle_advance.sh`, and as the `stage` field on each
`personas/*.yaml`. Three copies of one table is three chances to
drift, and the automation rungs still to come (#8, #9, #10) would each
add a fourth.

## Proposed outcome

A human types **only an issue number or a PR number** (#36, Presenter
direction, item 1); everything else is derived.

- **One machine-readable source** for the label ↔ stage relation,
  from which the owning persona is derived through the `stage` field
  already carried by `personas/*.yaml` — no second copy of the table
  anywhere. `lifecycle_advance.sh`, the dispatcher, and the compiler
  all read that one file.
- **A resume protocol compiled into every persona** as a shared skill
  rendered by `scripts/sync_agents.py` from that source: given `#<n>`,
  read labels and thread; check `hold`; determine the stage; if this
  persona does not own it, name who does and stop; if `in-progress` is
  held by someone else, stop; otherwise claim, reuse the existing
  `intent/<n>-*/` folder or derive the slug deterministically, produce
  the stage's artifact, and hand off in Done/Decided/Next/Blocked.
- **`scripts/ops/work.sh <issue-or-pr>`** — deterministic bash, `gh`
  and `jq`, no model call. Resolves a PR number to its issue, reads
  the labels, picks the owning persona from that same source, reads
  the harness pin from `config/deployments.yaml`, and launches (or,
  for a harness it cannot launch, prints the equivalent instruction).
  `DRY_RUN=1` prints instead of launching. Refuses on `hold`, on a
  foreign `in-progress`, and on a stage with no owner.
- `docs/SPEC.md` gains entries for the dispatcher and the resume
  protocol; `tracker.workflow` is reworded to say the number is the
  whole instruction.

The hand-off signal stays the **label**, not a git tag (#36, Presenter
direction, item 2): labels are already the state machine (#4) and
GitHub emits `issues: labeled` events, which is the repo-event trigger
shape #25 defines. Tags mark commits, not issues; a tag-based hand-off
would be a second state machine. Until #8/#9/#10 automate the
hand-off, one command replaces the typed prompt (item 3).

## Affected users and systems

- Presenter — the only typist, and the direct beneficiary.
- All 11 persona sources and every compiled target on both harnesses:
  the resume protocol is a shared skill, so the drift gate (#6) sees
  every target change.
- `scripts/sync_agents.py` (renders the skill), `scripts/ci/
  lifecycle_advance.sh` (reads the shared source instead of its inline
  mapping), `config/deployments.yaml` (read-only), `docs/SPEC.md`.
- Later: #8, #9, #10 consume the same source instead of re-deriving
  it; #35 (README walkthrough) documents the result and lands after.

## Constraints

- No vendor names or model IDs in persona sources or in the skill
  (#1, D3); anything harness-specific lives in the script and comes
  from `config/`.
- No new documents beyond the skill and the machine-readable source
  (AGENTS.md, "No document sprawl").
- The script follows the failure-mode-first style of the existing CI
  scripts and is runnable locally in dry run (#4, D8).
- Compiled targets are regenerated, never hand-edited (#5, D7).
- Refines #4 and #5; independent of #25, which decides where an
  automated run executes, not what a run does once it has a number.

## Open questions

None — the presenter directed that the three questions filed on #36
be decided rather than posed back. They are resolved as D1 (source
location), D6 (slug derivation) and D9 (PR-number behaviour) in
[spec.md](spec.md), each overrulable by editing at the merge gate.
