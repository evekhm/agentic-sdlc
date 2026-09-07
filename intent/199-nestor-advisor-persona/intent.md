# Intent: Nestor — the advisor seat as a tracked persona

**Issue:** #199 · **Author:** athena (`evekhm-athena-app[bot]`) ·
**Status:** accepted on merge of this PR

## Problem

The backlog-closeout exercise runs on two standing session seats. One
of them, the advisor, exists today only as a prompt file on one
machine (`~/persona-advisor.txt`), outside the repo, outside the
persona compiler, outside every gate.

- **The seat is folklore.** Its charter (judgment, not volume:
  process decisions, dispatch-prompt authoring, spec-gate work,
  unblocking, stewardship of docs/PLAYBOOK.md; never implement,
  never review PRs, never merge except as a decision being resolved)
  has been paid for in shipped defects across two waves, and nothing
  in the repo records it. A new machine, a new operator, or a lost
  home directory loses the seat.
- **It has no tier binding.** The seat runs on the most expensive
  model in the system, and that choice is a local habit, not a
  `tier:` on a persona that config/model_tiers.yaml resolves. The
  tier table's own comment records FRONTIER as "spec gate only"
  (#105); the advisor seat is a second FRONTIER consumer that the
  decision never saw.
- **It has no compiled brief.** Every other role in the cast is a
  `personas/<name>.yaml` compiled into per-harness targets that the
  drift gate keeps honest. The advisor is launched from a hand-edited
  text file, so the standing truths it carries (never trust a
  summary, a PR body, a green check or an exit code; the prompt
  author is a fabrication risk; explicit model flags in every launch
  line) drift on every copy.
- **Session turnover is a convention nobody wrote down.** The seat
  survives context turnover by orienting from PLAYBOOK, the newest
  dated handoff file, and the live tracker, and by writing a new
  dated handoff at close. The order and the close-out obligations live
  in the local file only. The handoff written on 2026-09-07 named a
  verifier session that was already dead and caused a double launch:
  a documented "verify seat holders live, never from a file" rule
  would have prevented it.

This intent covers the advisor seat only. The verifier seat (the
issue's "Seat 2": review stage executed by the existing reviewer
persona plus separable process powers, or a persona of its own) is a
different decision with a different owner and is split out to its own
issue; see "Open questions" 7.

## Proposed outcome

A first-class advisor persona, working name **Nestor**, in the
persona system:

- **One source, compiled like the rest.** `personas/nestor.yaml`,
  validated by personas/schema.json, compiled by the existing
  compiler into the same per-harness targets every other persona
  gets. No hand-edited brief anywhere; the local charter file is
  retired once a session launched from the compiled brief can orient
  without it.
- **Tier: FRONTIER, and the decision says so.** The persona binds to
  the FRONTIER tier through the normal `tier:` field; no model name
  appears in the persona source. The #105 decision and the tier
  table's comment are amended from "spec gate only" to name the two
  FRONTIER seats and the argument they share: both do judgment, not
  volume, and neither runs per PR round.
- **Judgment-only capabilities.** The brief and the capability list
  express the boundary the charter already enforces: read, decide,
  author (prompt files, intents, PLAYBOOK, handoffs), delegate to
  lower tiers; no implementation, no PR review, no merge except as
  the resolution of a decision the seat owns.
- **The session protocol is the brief's content.** Orient order
  (docs/PLAYBOOK.md on main, then the newest dated handoff, then the
  live tracker and live peer sessions), the operator protocol (the
  operator launches implementer sessions by hand and cannot paste
  multi-line text: every authored prompt is a file on disk handed
  over as a full path plus one launch line with an explicit model
  flag), and the mandatory close-out (new dated handoff, PLAYBOOK
  status snapshot, every decision reconciled to an issue, a PR or an
  explicit "deferred, no tracker").
- **Interactive only.** Nestor is a seat a human opens, never a
  dispatch target of the unattended workflow and never a stage owner
  on the ladder by default.

**Done when:** `personas/nestor.yaml` exists and passes the schema,
compiler roundtrip and drift gates; its compiled targets are present
for every harness the compiler emits; every document that enumerates
the cast lists the new persona; the FRONTIER comment in
config/model_tiers.yaml and the #105 record name both FRONTIER seats;
and one advisor session, launched with the compiled brief and an
explicit model flag, orients and closes out per the brief with no
reference to `~/persona-advisor.txt`.

## Affected users and systems

- **The operator**, who launches every seat by hand and gets one
  tracked launch line per seat instead of a local file to keep in
  sync across machines.
- **The persona compiler and the drift gate**, which gain one more
  source and its targets; nothing else in the compiler changes.
- **config/model_tiers.yaml and decision #105**, whose "spec gate
  only" wording stops being true.
- **athena**, the product-owner gate: the spec must draw the line
  between "spec-gate work" as the advisor does it (authoring the
  kickoff prompts, unblocking, judgment on routing) and the gate
  itself, which stays athena's.
- **The verifier seat**, Nestor's standing peer, whose own tracking
  issue decides stage-versus-persona; the two must agree on one
  launch-line convention.
- **docs/PLAYBOOK.md**, which the seat owns; the brief must say so.
- **The verifier's evidence log and the #181 launch-template work**,
  which are where the seat's standing truths were earned; the brief
  cites, never duplicates.

## Constraints

- **The ladder applies to this change.** intent (this PR) → spec →
  plan → implementation → review; no prototype shipped ahead of the
  spec.
- **D3 holds.** No vendor or model name in the persona source; the
  tier table is the only place a model is chosen. The brief tells the
  operator to pass an explicit model flag and to read the binding
  from the tier table, not which model that is.
- **One persona, one yaml, compiled targets never hand-edited.** The
  persona is added the way the existing eleven were; if the schema
  lacks a way to say "delegates, never implements" or "interactive
  only", the spec decides whether that is a schema change or brief
  prose, and the schema change rides this ladder.
- **Delegation-first is a cost rule, not a style.** The seat is the
  most expensive context in the system; the brief must bind the
  repo's subagent tier table and the 200K working ceiling as hard
  limits, not preferences.
- **Nothing here changes who merges.** The advisor's "merge only as a
  decision being resolved" is narrower than the verifier's interim
  merge authority and is not a second merge path; reviewer-consensus
  merge (#64/#151) is unaffected.
- **Dated artifacts stay out of the persona.** Handoff files, wave
  state, and PR numbers live in handoffs and run folders; the brief
  is durable and carries none of them.

## Open questions

1. **New persona or athena absorbs the role?** Recommendation: new.
   athena owns the two gates where words become commitments; giving
   that persona dispatch authorship, PLAYBOOK stewardship and
   unblocking would make the gate its own process owner. Decide in
   spec.md.
2. **Stage ownership.** Does Nestor own any ladder stage? Today the
   seat claims as athena when it writes an intent (this PR is an
   instance). Recommendation: no stage; the seat acts as athena at
   the gate and as itself everywhere else, and the brief says exactly
   that. Decide in spec.md.
3. **How the #105 amendment is recorded.** Comment edit in
   config/model_tiers.yaml plus a decision row in docs/SPEC.md, or a
   new numbered decision? Decide in spec.md.
4. **Home of the dated handoff file.** It is local today
   (`~/handoff-plan-<date>.txt`) and run folders are gitignored.
   Options: keep it local and make PLAYBOOK's status snapshot the
   tracked half; or track handoffs in the repo. This touches the
   session close-out convention already under #85; the spec must
   reconcile the two rather than define a second convention. Decide
   in spec.md.
5. **Where the operator protocol lives.** "The operator cannot paste
   multi-line text; every prompt is a file on disk" is a fact about
   this deployment, not about the persona. Persona brief, deployment
   config, or PLAYBOOK, with the brief pointing at it? Decide in
   spec.md.
6. **Capability vocabulary.** Whether personas/schema.json's existing
   capability and tool fields can express judgment-only plus
   delegation, or a field is missing. The spec answers this from the
   schema as it is, not from memory.
7. **The verifier issue.** Seat 2 of #199 is filed separately (issue
   number recorded on the #199 thread when it exists). The spec for
   Nestor must name the one launch-line convention both seats share
   and must not decide the verifier's stage-versus-persona question.
