# Intent: execution model for unattended personas

**Issue:** #25 · **Status:** accepted on merge of this PR

## Problem

Rung 3 gives three personas unattended duties: Argus reviews PRs on
open/synchronize (#8), Atlas rides sidecar (#9), Athena drafts
intent.md from `intent:new` issues (#10). The predecessor runs all of
this as GitHub-hosted Actions workflows, but this repo has decided
nothing about unattended execution: `config/deployments.yaml` (#2)
pins every persona to an *interactive* harness and no further axis
exists. The gap already blocks work — #7 holds the six App private
keys out of Actions secrets until execution placement is a decision,
not an assumption inherited from whatever a ported workflow happens
to need.

## Proposed outcome

A recorded decision — in config/ as data, per #2's one-axis-per-file
rule — of where each unattended persona executes, with the credential
placement that follows from it. The candidate shapes the spec must
weigh:

- **Hosted:** the model runs inside GitHub-hosted Actions
  (predecessor pattern: model gets no tools, nonce-fenced thread
  data, trusted post steps, WIF/ADC to the model API). App keys
  become Actions secrets.
- **VM-local:** Actions does only deterministic event capture; the
  model-bearing run executes on the presenter's machine (poller or
  presenter-triggered). App keys never leave the box.
- **Hybrid:** the placement is chosen per persona, as a config/
  binding alongside the harness pin.

## Affected users and systems

#8/#9/#10 build directly on the decision; #7's remaining step
(Actions secrets or not) executes it; the compiler (#5) may need to
emit for a headless target; the presenter's live-demo seat must keep
unattended runs observable and interruptible (`hold` is absolute).

## Constraints

- Vendor and infrastructure names stay in config/; persona sources
  do not change (#1 D3/D4).
- Whatever placement is chosen, credentials move by NAME through
  secrets stores — a private key never appears in a workflow file,
  argv, or log.
- The workshop is presenter-driven: unattended activity must be
  demonstrable live, not only by reading logs afterwards.
- Spend discipline applies: an always-on poller pays cache-write
  economics (AGENTS.md, cost of execution) and must justify itself
  against event-triggered alternatives.

## Open questions

1. Where does each of #8/#9/#10 execute — hosted, VM-local, or per
   persona? (The core decision.)
2. Does unattended execution become a new binding in
   `deployments.yaml` or a new config/ file?
3. Do hosted runs reach the model API via WIF like the predecessor,
   and is that acceptable for a workshop repo that may go public?
4. What is the interrupt path — does `hold` stop a run already in
   flight, or only the next dispatch?
