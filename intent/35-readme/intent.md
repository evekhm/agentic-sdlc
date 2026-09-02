# Intent: README operator walkthrough

**Issue:** #35 · **Author:** athena (`evekhm-athena-app[bot]`) ·
**Status:** accepted on merge of this PR

## Problem

The loop is documented for agents and a cold agent can follow it:
AGENTS.md ("Working the tracker"), INTENT.md's lifecycle, `docs/SPEC.md`
`tracker.workflow` / `lifecycle.labels` / `review.policy`, and the
compiled persona prompts. It is not documented for the human who owns
the gates. There is no `README.md` in this repository at all —
INTENT.md's layout still lists it as a flagship doc to come — so the
first thing an attendee opens is either a standard written for
machines or nothing.

Concretely, nothing in the repo answers, from the operator's seat:
what the human does at each gate and what each merge causes (AGENTS.md
gives it one line); what the human types to advance an item; how
review runs by hand while #8/#9 do not exist; which path a defect
repair takes (open on #32); and what happens to an idea that arrives
outside the loop. The walkthrough the presenter needed was delivered
in a chat transcript — the one place this repo says state must never
live.

## Proposed outcome

A root `README.md` written from the operator's seat: the loop in one
picture, then one short section per thing the operator actually does —
file, type, watch the gates, merge, review, recover — closing with a
map of where each rule really lives. It explains the system and is
normative for nothing: every rule it mentions is one sentence and a
link to the document that owns it (`docs.structure`, AGENTS.md "No
document sprawl").

Three properties make it cheap to keep true, and they are the
substance of [spec.md](spec.md):

- **One command.** The operator types `scripts/ops/work.sh <n>` and
  nothing else (#36, Presenter direction item 1; #36 spec D7/D8).
  Harness launch lines are output of that script (#36 D10), never
  instructions in the README, so the README needs no re-verification
  when a harness pin changes.
- **No second copy.** The label ladder, the review protocol, the
  severity tiers and the persona bounds stay in their own documents;
  the README names them and links. Where it and they disagree, they
  win, and the README says so once.
- **A hard ceiling.** A bounded section list and a line limit, so the
  document that welcomes an attendee cannot grow into a fourth
  standard.

## Affected users and systems

- Workshop attendees and the presenter — the only readers.
- `docs/SPEC.md` `docs.structure`, amended by the implementing PR to
  name README's role in the document chain; INTENT.md's layout, where
  README stops being "to come".
- Nothing executable. The README ships no script and changes no
  behaviour, so `scripts/ci/spec_check.sh` will not force the
  `docs.structure` upsert; it is owed anyway.

## Constraints

- **Depends on #36.** This planning PR is branched from
  `athena/36-dispatch` and must merge after #36's planning PR; the
  README's implementing PR must merge after #36's implementing PR,
  because `scripts/ops/work.sh` — the one command the walkthrough
  teaches — does not exist until then.
- No duplication of AGENTS.md / INTENT.md / `docs/SPEC.md` /
  REVIEW.md content: link, do not restate.
- No vendor names, model IDs or model-family names; no absolute home
  paths. `scripts/ci/sanitize_check.sh` scans every tracked file for
  home paths and credential shapes and must pass.
- No per-persona procedure text: how a persona works its stage is the
  compiled resume protocol (#36 D3/D4), not prose in the README.
- The defect-repair route is open on #32 and is not guessed at here.

## Open questions

None. The presenter directed that decisions be made rather than posed
back (#36, Presenter direction, applied here by the claim on #35).
The two questions filed on #35 — whether README carries the take-home
setup, and whether it is the live-demo change — are decided as D11 and
D12 in [spec.md](spec.md). Every row there can be overruled by editing
the file at the merge gate.
