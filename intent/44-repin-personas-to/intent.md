# Intent: harness and model selection is configuration

**Issue:** #44 · **Stage:** plan · **Author:** athena
(`evekhm-athena-app[bot]`)

## Amendment r1 (2026-09-03)

The presenter, who is this repository's human product owner, on
2026-09-03:

> actually it is pretty easy to update the pins for the models, so I can
> change it. in the spec - I want to explicitly mention - that the whole
> idea is to be able to re-pin and easily configure the harness and model
> selection! i do not want spec to hardcode or reference any choices!!!
> that must be changed!

and, asked which pins they wanted: *"I want to specify my own pins now."*

**The idea, stated once, up front.** Which harness runs a persona, and
which model a semantic tier resolves to on that harness, are
**configuration**. Re-pinning any persona to any harness, or changing
which model a tier resolves to, is an edit to `config/deployments.yaml`
or `config/model_tiers.yaml` followed by the compiler rebuild committed
alongside it — and nothing else. **No persona source changes for a
repin, ever.** Every gate in the repository proves whatever
configuration is present rather than one particular assignment. That
property, demonstrated end to end, is the deliverable of #44; the pins
themselves are the operator's input and live only in `config/`.

**What this amendment changed.** The original intent argued *for* a
particular repin — two named personas to one named harness, two named
personas staying, each with a defence — and its Proposed outcome quoted
the resulting YAML. All of that is struck. The problem is restated as
the property that was never demonstrated, the outcome as the demonstration,
and every affected system is named by its role rather than by the
persona whose pin happens to change. `spec.md` in this folder carries
the same amendment row by row; `plan.md` is Daedalus's and is re-synced
after this merges.

---

## Problem

`config/deployments.yaml` pins each persona to a harness and
`config/model_tiers.yaml` binds each semantic tier to a model per
harness. That is the whole design (#2 D1/D2): one axis per file, so
swapping a vendor or a harness edits exactly one place, and vendor and
model names never enter `personas/**`.

The design is real but it has never been **exercised**. Every pin in the
file is the one #2 set on the day the persona was written, chosen
because that harness was the one that worked; no persona has ever
changed harness, so nothing in the repository has ever demonstrated
that changing one is the two-file edit the design claims. Three things
are therefore unproven:

- **That a repin is config-only.** Until #43 the pin decided nothing at
  launch time, so moving a persona would have moved it into a harness
  `scripts/ops/work.sh` could not start. #43 (PR #60) closes that: both
  harnesses launch, each has a compiled target layout, and the resolved
  model reaches the launcher from the compiled artifact. A repin is now
  a real change of where work runs — and the first one is what shows
  that the persona sources, the scripts and the spec all sit still while
  it happens.
- **That the gates prove *whatever* configuration is present.** The
  drift gate and the sanitize gate are already written that way. The
  launch smoke is not: `scripts/ops/smoke_launch.sh` names its two arms
  as persona literals, which were correct when they were written and
  which any repin silently invalidates — the run keeps exiting 0 while
  covering one harness twice. A gate that only holds for one pinning is
  not a gate on the property.
- **That the one constraint a pin can violate is guarded where the pin
  is edited.** `docs/SPEC.md` says the two reviewers are pinned to
  different model families and that "which family backs which reviewer
  is a `config/` fact". Nothing in `config/deployments.yaml` says so out
  loud, so a session repinning "everything else" for price can break the
  review policy with a one-line edit and, until #6's check lands, no
  error.

*(Amended 2026-09-03. The Problem previously read that "four of the six
personas … are pinned to `claude-code`" against a presenter direction of
2026-09-02 for "the opposite balance", and argued two specific moves:
`odyssey` as "the highest-volume persona in the system … `limits:
{max_turns: 120, timeout_mins: 90}`", and `cassandra` as "the cheapest
possible work on the most expensive available billing relationship".
Struck. Those are arguments for a choice, and the choice is the
operator's to make in `config/`; the problem this issue exists to fix is
that the repository cannot yet demonstrate the choice is cheap to make
or safe to change.)*

## Proposed outcome

The operator sets the pins they want in `config/deployments.yaml`, and
the model cells they want in `config/model_tiers.yaml`. Everything else
follows mechanically and is proven to follow:

1. **The rebuild follows the pins, in the same commit.** For each
   persona whose pin changed, the target its old harness emitted
   disappears and the target its new harness emits appears.
   `scripts/sync_agents.py --check` is the gate; a rebuild that leaves
   a stale target behind fails it, and so does a hand-edited one.
2. **The resolved model follows the tier table.** Each rebuilt target
   carries the model `config/model_tiers.yaml` binds to that persona's
   tier on its new harness — in the place that harness's layout puts it,
   never as a `model:` key in an Antigravity `agent.md`, which voids the
   agent (#43 D8/D9).
3. **The launch smoke derives its arms from the pins.** One arm per
   harness present in `config/deployments.yaml`, the persona for each
   selected by a rule over config facts, with no persona name written
   into the script. Flipping a pin changes which personas run, with no
   edit to the script; a harness with no persona that can produce the
   arm's observables fails the run rather than being skipped.
4. **The reviewer constraint is resolved and recorded, not asserted.**
   For each name in `constraints.distinct_model_families`, the harness
   and the `REVIEW`-tier model are read and the families compared, at
   the merge commit, whatever the pins are — and the result is written
   into `config/deployments.yaml` beside the constraint, where the next
   editor will read it.
5. **The move is measured.** The presenter's reason for re-pinning is
   price, so a repin owes a number rather than a belief: a before/after
   session-spend comparison per moved persona, within what the tools can
   honestly measure across two vendors (see Constraints).

*(Amended 2026-09-03. The outcome previously opened with a YAML block
pinning two named personas to a named harness, then defended two
personas staying — `athena` because "plan and design are the two gates
where words become commitments", `argus` because "#2 D4 makes the two
reviewers a machine-checkable pair … and `atlas` is on antigravity".
Struck as choices. The `argus`/`atlas` reasoning is not lost: it is
point 4, quantified over whatever names the constraint lists.)*

## Affected users and systems

- `config/deployments.yaml` and `config/model_tiers.yaml` — the
  operator's input, and the only sources edited.
- **The compiled targets** — derived, never hand-edited: for each moved
  persona, one harness's target deleted and another's added by the
  rebuild in the same commit.
- `scripts/ops/work.sh` — not edited. It reads the pin, so its behaviour
  changes without its text changing: a stage now starts the harness the
  file names and reads that harness's compiled artifact.
- `scripts/ops/smoke_launch.sh` — its arms are persona literals today,
  and any repin invalidates them; they become derived.
- `docs/SPEC.md` — `config.bindings` gains one sentence stating the
  re-pin property; `ops.dispatch` describes the smoke's arms as fixed
  personas and as blocked on a now-closed issue, and is upserted by the
  implementing PR.
- **The presenter**, whose bill this is, and the room watching the demo:
  a persona that changes harness with a one-line edit is the visible
  claim that the personas are harness-agnostic, and it is the claim the
  demo makes.
- **Not affected:** `personas/**` — a repin never touches a persona
  source, which is the property itself and is also why it adds no
  sanitize surface; `config/tools.yaml`; `personas/lifecycle.json`;
  `config/execution.yaml` (#25 D19's bindings name *placements*, not
  harnesses); `CLAUDE.md`.

## Constraints

- **Config-only at the source layer.** Which harness backs a persona is
  one edit to `config/deployments.yaml` and nothing else (#2 D1/D2).
  Vendor and model names never enter `personas/**`; the sanitize gate
  enforces it, and this issue gives it no new surface.
- **The compiled targets are derived, never hand-edited.**
  `scripts/sync_agents.py --check` is the gate (#5, #43 D10). A repin
  whose rebuild is not committed is drift, and a hand-made target is the
  same failure.
- **#2 D4 is non-negotiable.** The names in
  `constraints.distinct_model_families` must resolve to different model
  families at `REVIEW` tier. It is data in `config/deployments.yaml`,
  and until #6 automates it the check is performed and recorded by hand
  — for whatever pins are present, including when the pins did not
  change.
- **Depends on #43 (PR #60).** A persona pinned to a harness `work.sh`
  cannot start is unlaunchable from the one door AGENTS.md allows.
- **The spec states no pin.** No decision, acceptance item, table or
  paragraph in this folder may state a persona→harness or persona→model
  choice; each is a rule quantified over the configuration, testable
  against the config as it stands at merge time. A spec that names a pin
  turns the operator's one-line edit into a spec amendment, which is
  precisely the friction this issue exists to remove.
- **The cost tool is single-vendor.** `scripts/ops/session_spend.sh`
  reads Claude Code `*.jsonl` transcripts and prices them against the
  Anthropic rate table; a model the table does not know is reported
  `UNPRICED` by name. `agy` reports its own `usage` object in
  `--output-format json` (findings Q5). There is no one number that
  spans both, and the measurement must say so rather than produce a
  cross-vendor dollar figure the tool cannot support.
- **A persona whose only stage has no rung cannot be dispatched at all.**
  `personas/lifecycle.json` states that `intake`, `deploy` and
  `maintain` "are stage-enum values with no rung and are absent by
  construction", and `work.sh` validates `--as` against the current
  stage's owners. Repinning such a persona changes its harness and not
  its dispatchability, before or after.
- **The App permissions are config too.** `scripts/auth/app_manifests.yaml`
  records what each persona's App may do, and the smoke's arm selection
  reads it: an observable a persona's App cannot produce is a reason not
  to select that persona, never a tolerated skip.

## Open questions

None. The one filed on the issue — whether `CLAUDE.md`'s
`IMPLEMENTATION_TIER` note goes stale when the persona that ran at that
tier changes harness — is settled in `spec.md` D11 with its differing
case, and is settled generically: a harness's tier→model note describes
the tier for sessions on that harness, not for whichever persona happens
to run at it, so no pin can make it stale.

Both artifacts land in one pull request under the bootstrap-compression
precedent (`intent/1-personas/spec.md` D10, reused by
`intent/2-config/spec.md`): recorded once, not a precedent.
