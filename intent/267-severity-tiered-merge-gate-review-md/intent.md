# Intent: Severity-tiered merge gate (REVIEW.md) has no recorder enforcing it — #8/#9 closed without shipping one

**Issue:** #267 · **Author:** athena (`evekhm-athena-app[bot]`) ·
**Status:** accepted on merge of this PR

## Problem

Unattended merge gate run 34315613103 on this repository (`workflow_dispatch`, `pull_request=280`) evaluated all eleven conjuncts as Themis (`evekhm-themis-app[bot]`) and declined:
`Decline: conjunct(s) (3) (4) (5) (11) false for #280 at c301609433bbff55f418ad2e15aff20f2c7606d8`
`verdict: no merge for #280`
The run log cited: "no consensus ledger for #280 from a trusted writer".

This failure reflects an unbuilt subsystem in the repository. In `REVIEW.md` at SHA `d61875cd8468a2aa7183d2f0f7628e1174ee3524`, section "**Automation status.**" states:
> "The enforcement points below name a *recorder*: the trusted posting step that validates reviewer output against a schema and performs every GitHub write itself. No recorder exists in this repository yet — it ports with issues #8 and #9 — so every rule here is currently prompt-enforced with a human as the backstop."

A later section header in `REVIEW.md` reads "Enforcement (recorder, not prompt — ports with #8/#9):" and specifies enum validation, `failure_scenario` validation with loud demotion, and the human retier verb `@argus retier R2-1 normal`.

Both tracking issues were closed on 2026-09-08 without shipping a recorder. Issue #8 closed as "superseded by .github/workflows/unattended.yml and #207", and #9 closed alongside it. A comment left on the closed thread of #8 notes: "REVIEW.md's enforcement map assigns round-scoped admissibility and ledger state to the recorder (#8/#9), prompt-enforced with a human backstop until it lands." Issue #238 is open with `intent:new` for the orphaned G1 and G2 review gates, leaving severity-tier enforcement unassigned.

At base commit `d61875c`, no recorder exists. `git ls-tree origin/main scripts/ci/` lists `compiler_roundtrip.sh`, `escalate.sh`, `install_harness.sh`, `lifecycle_advance.sh`, `merge_gate.sh`, `sanitize_allowlist.txt`, `sanitize_check.sh`, `spec_check.sh`, and `tests/`. `git ls-tree origin/main scripts/ops/` lists `claim.sh`, `execution.py`, `post.sh`, `session_spend.sh`, `smoke_launch.sh`, `tracker_search.sh`, `work.sh`, `worktrees.sh`, `hooks/`, and `lib/`. No `review_recorder.*` exists in either path.

Today whether a finding blocks merge is reviewer judgment plus a human backstop. Nothing validates that a `high` row carries a `failure_scenario`, demotes an unqualified row to `normal` with a loud note, refuses a non-enum severity, or computes `argus:findings` / `review:merge-ready` from ledger state. In #64's spec (`intent/64-autonomous-loop/spec.md`), `## Out of scope` states that the recorder, the ledger schema, and the review protocol's content stay with #8/#9 and REVIEW.md; issue #267 is where they now live.

## Proposed outcome

This change ports the recorder and severity-tiered enforcement into the repository:

1. Port a recorder and trusted-posting step for the review ledger (candidate home: `scripts/ops/post.sh`, or a new `scripts/ci/review_recorder.*`) that:
   - validates severity against the four-value enum;
   - requires and checks `failure_scenario` on `high` rows, demoting a row that lacks one to `normal` with a loud note in the ledger;
   - computes `argus:findings`, `argus:suggestions`, `consensus:*`, and `review:merge-ready` from ledger state only;
   - enforces round-scoped admissibility (blocking-tier-only new findings after round 1, security-only after round 3);
   - honors the owner retier verb.
2. Wire the recorder into `.github/workflows/unattended.yml`'s review dispatch so every reviewer write goes through it instead of a raw API call.
3. Close in the same pass as #238 (G1/G2), resolving the orphaned recorder responsibilities together against shared ledger state.

The recorder enforces the six behaviors established in `agentic-experiments-lab` v2:
- Severity must be one of the four enum values; anything else fails validation.
- A `high` row must carry a `failure_scenario` naming concrete input or state and concrete damage. A `high` row without one is recorded as `normal`, and the demotion is noted in the ledger row loudly.
- `argus:findings`, `argus:suggestions`, `consensus:*`, and `review:merge-ready` are all derived by the trusted step from ledger state; no reviewer asserts a label.
- Round-scoped admissibility: round 1 accepts all four tiers; rounds 2-3 accept new findings only at `security` or `high`, with the `failure_scenario` rule still enforced; past round 3, only a new `security` finding is admissible, everything else is demoted to `normal` by the recorder.
- `security` rows require both reviewers' explicit agreement, twice (existence, then fix).
- A human can retier any finding with one comment verb (`@argus retier R2-1 normal`); the recorder records the override and recomputes labels. The override is not debatable by either reviewer.

These rules address the severity inflation and round bloat observed in the predecessor repository (`agentic-experiments-lab`):
- PR #52 reached 9 review rounds and 12 consensus runs (66 bot interactions), with findings still descending in altitude at round 15.
- PR #106 sat at 5 rounds with 7 open findings, mostly documentation-number drift.
- Nine open PRs simultaneously carried `consensus:agreed` + `argus:findings`, creating a deadlock where reviewers agreed on findings and nothing could merge.
- Three days of this cost 46 review runs plus 45 hourly sweep runs.
- `REVIEW.md` notes that one PR ran 19 unattended review rounds in three hours without converging. Under v2 enforcement, worst-case cost was 4-6 model runs per PR.

The recorder produces the consensus-ledger machine block required by `scripts/ci/merge_gate.sh`:
```text
<!-- consensus-ledger:<pr> -->
<!-- reviewed-head:argus:<full-oid> -->
<!-- reviewed-head:atlas:<full-oid> -->              absent = never reviewed
<!-- ledger-row:<id>:<severity>:<status>:<peer> -->   0..n
<!-- consensus-ledger-end -->
severity: security|high|normal|low   status: open|fixed|withdrawn
peer: pending|agree|dispute|none
```
Per #64 D23 and D31, this block is recognized by `merge_gate.sh` only when authored by Themis (`evekhm-themis-app[bot]`). `merge_gate.sh` line 28 uses the severity enum `security|high|normal|low`, whereas `REVIEW.md` line 88 specifies `suggestion` as the fourth tier. The design rung will resolve this enum drift.

## Affected systems

- `REVIEW.md` (exists): update automation status and align enforcement specifications with the deployed recorder.
- `.github/workflows/unattended.yml` (exists): route reviewer writes through the recorder.
- `scripts/ops/post.sh` (exists): candidate home for review schema validation.
- `scripts/ci/merge_gate.sh` (exists): downstream consumer of the consensus ledger; unchanged, serves as the target contract.
- `.github/workflows/merge-gate.yml` (exists) and `.github/workflows/lifecycle.yml` (exists): the two workflows currently possessing access to the Themis credential under the `themis` Environment.
- `scripts/ci/review_recorder.*` (new file): candidate home for dedicated review schema validation and ledger formatting.
- Review labels: `gh label list --repo evekhm/agentic-sdlc -L 100` shows 24 labels. None of `argus:findings`, `argus:suggestions`, `consensus:*`, or `review:merge-ready` currently exist in the repository; they must be provisioned.

## Constraints

- Every GitHub write from an unattended run goes through `scripts/ops/post.sh` (`personas/skills/trusted-posting.md`, `docs/SPEC.md`). The recorder acts as a validation step in front of that path rather than creating a separate write mechanism.
- AGENTS.md forbids documenting a runtime mechanism that has not been verified against that runtime.
- A severity tier is only enforceable if it is checkable (`REVIEW.md`: "the moment 'high' blocks and 'normal' does not, a model reviewer drifts toward 'high' unless the tier is checkable").
- The review surface is undergoing concurrent redesign in #265 (`intent/265-review-split/intent.md`, PR #280 open). This intent defines enforcement obligations without fixing reviewer assignments governed by #265.
- The consensus ledger must be authored by Themis (`evekhm-themis-app[bot]`) to be trusted by `scripts/ci/merge_gate.sh` (#64 D23). Themis credentials are restricted to the `themis` GitHub Environment on `main`.

## Open questions

1. **Recorder placement**: Whether the recorder should be implemented as a mode within `scripts/ops/post.sh` to preserve a single entry point, or as a standalone script in `scripts/ci/review_recorder.*` to decouple review schema validation from generic comment attribution.
2. **Ledger storage**: Whether the consensus ledger remains a single comment on the pull request edited in place, or is stored as issue comments or workflow artifacts.
3. **Round determination**: Whether the round number is parsed from reviewer finding identifiers, or maintained by workflow state and ledger metadata.
4. **Integration with #238**: Whether #267 and #238 should be merged into a single implementation since both cover orphaned recorder responsibilities, or executed as distinct sequential changes.
5. **Human retier verb authorization**: Whether the `@argus retier` command should be parsed from comment text with author validation against repository maintainers, or handled via a dedicated workflow event or CLI tool.
6. **Pre-existing findings**: Whether the recorder should retroactively parse open pull request ledgers, or enforce the schema only on new rounds.
7. **Merge gating boundary**: Whether the recorder directly gates merges, or only maintains ledger state and labels while `scripts/ci/merge_gate.sh` remains the sole gatekeeper.
8. **Themis execution context**: How the recorder accesses the Themis credential given that reviewers run in `unattended.yml` on `pull_request` under untrusted tokens without access to the `themis` Environment.
9. **Fourth tier naming**: Whether the fourth severity enum value should be `low` as specified in `scripts/ci/merge_gate.sh`, or `suggestion` as specified in `REVIEW.md`.
