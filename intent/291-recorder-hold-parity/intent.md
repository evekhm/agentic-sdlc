# Intent: Consensus Recorder Hold Parity and Spec Reconciliation

**Issue:** #291 · **Author:** athena (`evekhm-athena-app[bot]`) · **Status:** Draft

## Problem

A specification and implementation mismatch exists between the consensus recorder and repository hold invariants. In pull request #285 (commit `9d81c76`), issue #267 merged `intent/267-severity-tiered-merge-gate-review-md/spec.md`. Decision D1 establishes that the recorder lives at `scripts/ci/review_recorder.sh`, runs in `.github/workflows/merge-gate.yml` under `environment: themis`, and writes directly via `gh api`: "The recorder performs writes directly via `gh api` using the minted Themis GitHub App token; this supersedes the constraint in `intent.md:76` because `scripts/ops/post.sh` requires persona YAML definitions (`post.sh:94-98`, `170-179`) whereas Themis is an infrastructure system identity." Decision D12 defines the scope boundary and mandates that the implementation "may not touch ... `scripts/ops/post.sh`". The merged spec mentions `hold` exactly once (`grep -n hold` yields 1 hit at `spec.md:163`), describing label synchronization while "removing stale labels while preserving unrelated issue labels such as `hold`".

This creates a parity gap with core repository execution rules:
- `REVIEW.md:44-46` establishes: "A human is the sole merge authority on every path, and the `hold` label halts all review automation while it is present anywhere the work points."
- `intent/25-execution-model/spec.md` D13 mandates: "**`hold` is a dispatch gate AND is re-read immediately before every write.** No in-flight cancellation is added: a run that passed dispatch is not killed mid-call. Instead, every run re-reads its target's labels immediately before each GitHub write; if `hold` is present it discards the output, posts nothing, and exits 0 (green)."
- `intent/25-execution-model/spec.md` D14 defines the target set: "**For a pull-request-triggered run, `hold` attaches to the pull request AND to every issue it closes** — any one of them carrying the label suppresses the write."

Because the recorder writes via `gh api` directly and bypasses `scripts/ops/post.sh`, it required explicit re-read logic to fulfill D13 and D14. Pull request #292 (merged at `80b741c9`) implemented this circuit breaker directly in `scripts/ci/review_recorder.sh`:
- A preflight check under `# Guard 2 (#291): Circuit breaker on hold` (lines 57-72) exits 0 and logs `hold present on #$PR, recorder writes nothing` or `hold present on #$iss, recorder writes nothing`.
- A write-time check under `# Guard 2 (#291, Smoke N6): Re-read hold immediately before the first write` (lines 607-621) re-fetches labels immediately before issuing `gh api` and `gh issue edit` calls.

The contract suite in `scripts/ci/tests/review_recorder_test.sh` pins this in `AT-10 (D5, D7, D8): Label synchronization via gh issue edit and hold circuit breaker (#291)`:
- Case (a) (lines 1019-1045) verifies a held pull request produces zero writes and logs the held object.
- Case (c) (lines 1098-1113) verifies a pull request closing a held issue produces zero writes and logs the held issue.
Consequently, the earlier issue note stating the suite lacks a `hold` scenario is stale; the breaker is implemented and pinned. Shipped in code and pinned in the contract suite; open in spec. The defect today is spec-versus-code: the behavior ships in production, but no Decision row in the #267 spec authorizes it.

Six additional reconciliation items arose during PR #292 review rounds:
1. **D5 demotion note finding ID (spec text gap)**: Spec D5 specifies the note `[demoted from high: missing failure_scenario marker]`. `REVIEW.md:121-122` requires that demotion "is noted in the ledger row — loudly, never silently". `review_recorder.sh:376` appends `f"[demoted from high: missing failure_scenario marker] on {fid}"` to avoid note deduplication collapsing distinct demotions into one line. Shipped in code; open in spec.
2. **Embedded Python heredoc (architectural constraint)**: `scripts/ci/review_recorder.sh` is 639 lines containing a Python heredoc (`python3 - ... <<'PYEOF'`). `docs/PLAYBOOK.md:521-524` states: "Never embed Python in a shell command, not even for a one-line edit; ... it hides logic from the transcript and from sanitize_check." `scripts/ci/review_recorder.py` does not exist, and D12 omits `.py` from its may-touch list. Open in both code and spec.
3. **D5 demotion dispute and withdrawn exemption (contract conflict)**: Spec D5 states failure scenario demotion unconditionally. `scripts/ci/tests/review_recorder_test.sh:1066-1067` supplies `R1-6:high:open:dispute` and `R1-7:high:withdrawn:none` without sibling failure markers, and lines 1086-1087 assert they survive as `high`. `review_recorder.sh:373` exempts `dispute` and `withdrawn` from demotion, contradicting spec D5. Shipped in code; open in spec.
4. **ID prefix exemption for round 2 suggestions (contract conflict)**: `scripts/ci/tests/review_recorder_test.sh:798` asserts `R2-2:suggestion` lands as `normal`, while lines 1065 and 1085 assert `R1-5@D5:suggestion:open:none` survives as `suggestion`. `review_recorder.sh:388-390` checks finding prefix round against effective round. The practical effect is nil because both `normal` and `suggestion` emit `argus:suggestions` without blocking merge, but the spec omits this rule. Shipped in code; open in spec.
5. **Round counter derivation and monotonicity (spec text gap)**: Spec D8 states the round label is "set from highest accepted round at head; exactly one present", while D6 governs round derivation. In `review_recorder.sh:527-535`, the round counter enforces monotonicity against existing `review:<n>` labels and prior ledgers. Shipped in code; open in spec.
6. **Review label taxonomy alignment (verified complete)**: All eleven review, consensus, and circuit breaker labels (`argus:findings`, `argus:suggestions`, `consensus:agreed`, `consensus:pending`, `consensus:disputed`, `review:merge-ready`, `review:verifying`, `review:1`, `review:2`, `review:3`, and `hold`) are provisioned and present in repository taxonomy. Closed in both code and taxonomy.

## Proposed outcome

1. **Codify the hold circuit breaker decision**: Upsert a binding Decision row into the #267 spec incorporating the operator directive verbatim:
   - "The `record` job re-reads `hold` on the pull request, and on every issue the pull request closes (D14 object set), immediately before its first write. With `hold` present anywhere in that set it writes nothing, logs one line naming the held object, and exits 0. The label-preservation rule at :163 stays as written for labels other than `hold`. The build-rung suite asserts both halves: a held pull request produces zero writes; an unrelated label such as `bootstrap` plus a stale `review:1` produces one removal of `review:1` and no removal of `bootstrap`."
2. **Reconcile D5 demotion note wording**: Amend D5 to include the finding ID in the ledger note (`[demoted from high: missing failure_scenario marker] on <id>`), preventing deduplication loss and aligning D5 with `REVIEW.md:121-122`.
3. **Extract Python engine**: Permit extracting the inline Python heredoc from `scripts/ci/review_recorder.sh` into `scripts/ci/review_recorder.py`. Update D1 and add the path to D12's may-touch list to satisfy `docs/PLAYBOOK.md:521-524`.
4. **Codify D5 demotion exemptions**: Amend D5 to specify that `high` findings bearing status `withdrawn` or peer state `dispute` without a sibling `<!-- failure-scenario:<id> -->` marker remain `high`, reconciling D5 with contract test AT-10.
5. **Clarify suggestion tier round rules**: Reconcile D6 and the test suite regarding non-blocking findings across rounds 2 and 3, formalizing the prefix behavior where historical suggestions carried forward retain `suggestion` while newly filed observations record as `normal`.
6. **Harmonize round counter ownership**: Clarify D6 and D8 to document monotonic progression of `review:1`, `review:2`, and `review:3` against existing pull request labels.
7. **Document acceptance criteria for hold**: Add a formal acceptance row to the spec reflecting AT-10 cases (a) and (c) in `scripts/ci/tests/review_recorder_test.sh`.

## Affected users and systems

- **Operator**: Applies `hold` to halt review automation across open pull requests and linked issues.
- **Reviewers (`argus`, `atlas`)**: Emit verdict blocks parsed by the recorder into ledger rows.
- **Themis (`evekhm-themis-app[bot]`)**: Runs the `record` job in `.github/workflows/merge-gate.yml` under `environment: themis`.
- **Merge Gate (`scripts/ci/merge_gate.sh`)**: Consumes the consensus ledger comment and derived labels for conjunct evaluation.
- **Recorder scripts**:
  - `scripts/ci/review_recorder.sh`: Shell entrypoint running preflight checks, hold re-reads, and execution wrappers.
  - `scripts/ci/review_recorder.py`: Target standalone engine file (new file, does not exist).
- **Test suites**: `scripts/ci/tests/review_recorder_test.sh` asserting AT-1 through AT-18.
- **Specifications**:
  - `intent/267-severity-tiered-merge-gate-review-md/spec.md`: Living spec receiving amendment rows.
  - `intent/25-execution-model/spec.md`: Source specification for D13 and D14 hold semantics.
  - `REVIEW.md`: Authoritative source for hold constraints and finding demotion visibility.
  - `docs/PLAYBOOK.md`: Source standard for script structure forbidding embedded Python.
- **Neighboring issues**:
  - #295: Amends #251 regarding poller intake gate, fleet ceilings, and lock paths; independent of recorder logic.
  - #288: Amends #64 D16 for runner placement and VM poller dispatch; separate scope.
  - #238: Retains ownership of G1 and G2 review gates referenced in #267 D11.
  - #265: Manages reviewer assignment and economics; spec PR #280 merged at `696f516` into `status:build`, so assignment moves independently.

## Constraints

- **Execution Model Invariants**: #25 D13 and D14 govern all unattended writes across the repository. The recorder operates within this policy rather than outside it.
- **Isolation from posting wrappers**: #267 D12 excludes `scripts/ops/post.sh` from the recorder scope. Parity must be achieved within the recorder entrypoint.
- **Environment Isolation**: Themis credentials remain accessible only within jobs declaring `environment: themis` on runs from `main` (#64 D23).
- **Contract Suite Authority**: The contract suite in `review_recorder_test.sh` constitutes the authoritative definition of done. Changes require spec alignment or explicit spec-owner contract updates.
- **Code Style Invariants**: `docs/PLAYBOOK.md:521` prohibits embedding Python inside shell scripts.
- **Verification Rule**: AGENTS.md prohibits documenting unverified runtime mechanisms.
- **Scope Boundary**: This stage delivers `intent/291-recorder-hold-parity/intent.md` only; no code, workflow, or existing spec files are modified.

## Open questions

1. **Amendment structure**: Should the amendment be incorporated directly as an amendment section inside `intent/267-severity-tiered-merge-gate-review-md/spec.md`, or should this issue maintain its own `spec.md` superseding specific rows?
2. **Placement of hold decision**: Should the hold circuit breaker become a standalone Decision row (e.g., D13) or extend D1?
3. **Linked issue resolution scope**: Should the D14 object set follow the closure logic of `work.sh` (`Closes #<n>` and branch name), or use the recorder's broader `get_linked_issues` parser which also checks `Refs #n`?
4. **Demotion note formatting**: Should the finding ID appear inside the bracketed note `[demoted from high: missing failure_scenario marker] on <id>`, or as a distinct column in the markdown table row?
5. **Python engine extraction**: Should the Python script extraction into `scripts/ci/review_recorder.py` land with this amendment, or remain deferred to a dedicated refactoring issue?
6. **Demotion exemption policy**: Should D5 formally exempt `dispute` and `withdrawn` findings from failure scenario demotion, or should `scripts/ci/tests/review_recorder_test.sh:1066` be modified to require failure scenarios on all `high` rows?
7. **Suggestion classification in round 2**: Should the spec codify that `R<n>-` prefixes distinguish carried-forward suggestions from new round observations, or should all round 2/3 suggestions convert to `normal`?
8. **Round counter authority**: Does D6 or D8 maintain primary authority over the round counter, and how should "highest accepted round at head" interact with monotonic increments?
9. **Acceptance row format**: Should the merged AT-10 test cases be documented as an amendment to AT-10 in the #267 spec or given a distinct acceptance row ID?
10. **Historical ledger migration**: Should existing consensus comments posted prior to this amendment be re-derived, or do amended rules apply only to new executions?
