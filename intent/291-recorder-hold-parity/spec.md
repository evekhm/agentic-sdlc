# Spec: Consensus Recorder Hold Parity and Spec Reconciliation

**Issue:** #291 · **Status:** Approved (approval = merge of this PR) ·
**Author:** athena (`evekhm-athena-app[bot]`) ·
**Open questions:** none

## What is being built

This specification establishes parity between the consensus recorder (`scripts/ci/review_recorder.sh`, running in `.github/workflows/merge-gate.yml` under `environment: themis`) and repository-wide execution model invariants defined in `intent/25-execution-model/spec.md` (#25 D13 and #25 D14). It resolves specification gaps identified during the implementation and review of issue #267 across ten binding decisions:

1. **Write-time hold circuit breaker parity (#25 D13)**: The recorder re-reads `hold` immediately before its GitHub write sequence. If `hold` is present on the pull request or any linked issue, all writes are aborted, one log line is emitted, and the process exits 0.
2. **Linked issue resolution scope (#25 D14)**: The target set checked for `hold` encompasses the pull request itself and all linked issues resolved from GraphQL closing references, pull request body closing/reference keywords, and head branch names.
3. **Idempotent label synchronization**: Synchronization of managed review and consensus labels preserves unmanaged labels (such as `bootstrap`).
4. **Finding ID attribution in demotion notes (#267 D5)**: High-severity findings lacking failure scenarios append `on <id>` to demotion audit notes, preventing deduplication collapse.
5. **Demotion exemptions for withdrawn and disputed findings (#267 D5)**: High-severity findings marked `withdrawn` or `dispute` are exempted from failure-scenario demotion.
6. **Non-blocking observation classification (#267 D6)**: Historical suggestions from prior rounds retain `suggestion` status, while new observations in Rounds 2 and 3 land as `normal` with `peer=none`.
7. **Monotonic round counter progression (#267 D8)**: The `review:1..3` label counter progresses monotonically and does not decrement on re-derivation.
8. **Python engine extraction (docs/PLAYBOOK.md:521)**: Extracts the embedded Python heredoc from `scripts/ci/review_recorder.sh` into `scripts/ci/review_recorder.py`.
9. **Historical ledger immutability**: Amended rules apply to new executions and do not rewrite historical pull request comments.
10. **Scope boundary**: Bounded strictly to recorder files, test suites, living spec, and the #267 amendment reference.

```text
scripts/ci/review_recorder.sh            # shell entrypoint, preflight, hold re-read, CLI orchestration
scripts/ci/review_recorder.py            # standalone Python engine for review parsing, ledger generation, action plan
scripts/ci/tests/review_recorder_test.sh # contract test suite asserting AT-291-1 through AT-291-11
docs/SPEC.md                             # living spec updates for recorder hold parity and demotion rules
intent/267-severity-tiered-merge-gate-review-md/spec.md # cross-reference amendment note
intent/291-recorder-hold-parity/spec.md  # this specification
```

Workflows `unattended.yml` and `lifecycle.yml`, posting wrapper `post.sh`,
persona definitions under `personas/**`, `scripts/ci/escalate.sh`, and
`scripts/ci/lifecycle_advance.sh` are not touched.

## Decisions

| ID | Decision | Rationale |
|---|---|---|
| D1 | **Hold circuit breaker write-time re-read invariant (#25 D13 parity).** The `record` job re-reads `hold` on the pull request and on its #25 D14 linked issue set immediately before entering its GitHub write sequence (before its first write). If `hold` is present anywhere in that set, it writes nothing, logs one line naming the held object (`hold present on #<target>, recorder writes nothing`), and exits 0 (green). All subsequent writes within that recorder execution (ledger comment POST/PATCH and label synchronization) execute together in that write sequence. Any write operation added outside this contiguous write sequence must independently re-read `hold` immediately before execution. | Satisfies the operator directive verbatim while maintaining parity with #25 D13 and REVIEW.md:44-46. Grouping comment and label writes behind a single atomic pre-write check prevents partial ledger updates where a comment posts but labels fail to synchronize. |
| D2 | **Linked issue resolution scope for hold checking (#25 D14 parity).** The linked issue set for the recorder's `hold` circuit breaker is the union of: (a) GitHub GraphQL `closingIssuesReferences`; (b) issue references in the pull request body matching `\b(close[sd]?\|fix(es\|ed)?\|resolve[sd]?\|refs?)\s+#[0-9]+` case-insensitively; and (c) issue numbers extracted from the pull request head branch matching `^([a-zA-Z0-9_-]+/)?([0-9]+)-`. If the pull request itself or any issue in this union carries `hold`, the recorder performs zero writes and exits 0. | Pull requests in the autonomous loop frequently link to issues via `Refs #n` (such as ladder PRs under #245 and operator PRs under #298 D5). Restricting the check to strict `Closes` keywords would allow automation writes on pull requests whose referenced tracking issue is on `hold`. |
| D3 | **Label preservation and synchronization idempotency.** When `hold` is absent, the recorder synchronizes managed review labels (`argus:findings`, `argus:suggestions`, `consensus:agreed`, `consensus:pending`, `consensus:disputed`, `review:merge-ready`, `review:verifying`, `review:1`, `review:2`, `review:3`) via `gh issue edit`. Unmanaged labels (such as `bootstrap`, `hold`, or foreign workflow labels) are strictly preserved and never removed. When `hold` is present, the circuit breaker halts before label modification, ensuring zero writes. | Preserves manual operator interventions and bootstrap categorization while keeping automated review indicators synchronized with the latest ledger state. |
| D4 | **Finding ID attribution in failure scenario demotion notes (#267 D5 amendment).** When a `high` severity finding lacks a sibling `<!-- failure-scenario:<id> -->` marker, the demotion audit note appended to the ledger table must explicitly identify the finding: `[demoted from high: missing failure_scenario marker] on <id>`. This prevents note deduplication from collapsing distinct demotions into a single line, adhering to `REVIEW.md:119-122`. | `REVIEW.md:121-122` requires that demotion is noted in the ledger row loudly and never silently. Without finding ID attribution, deduplicating audit notes collapses multiple demotions into a single entry, hiding which findings were demoted. |
| D5 | **Exemption from failure scenario demotion for withdrawn and disputed findings (#267 D5 amendment).** A `high` severity finding lacking a sibling `<!-- failure-scenario:<id> -->` marker is exempted from demotion to `normal` if its status is `withdrawn` (the discovering reviewer retracted the finding) or its peer consensus state is `dispute` (the finding is actively contested by a peer reviewer). Only active, undisputed `high` findings (`status != 'withdrawn'` and `peer != 'dispute'`) without failure scenario markers are demoted to `normal`. | Retracted findings are inactive and require no scenario proof. Contested findings must preserve their disputed severity tier for merge-gate evaluation and peer dispute resolution. |
| D6 | **Non-blocking finding classification and round admissibility (#267 D6 amendment).** In verification rounds (Rounds 2 and 3), historical suggestions carried forward from earlier rounds (where the finding round parsed from prefix `R<n>-` or `AT-R<n>-` is strictly less than the effective round) retain their recorded severity (`suggestion` stays `suggestion`). New non-blocking observations filed in Rounds 2 and 3 (where finding round is greater than or equal to the effective round) are recorded as `normal` with `peer=none` per `REVIEW.md:166-168`. Both tiers emit `argus:suggestions` without blocking merge. | Reconciles `REVIEW.md:166-168` with contract tests. Historical suggestions keep their non-actionable status, whereas new observations in verification rounds convert to `normal` so they receive closure ownership under `REVIEW.md:214-220`. |
| D7 | **Monotonic round counter progression (#267 D8 amendment).** The round counter label (`review:1`, `review:2`, `review:3`) progresses monotonically. The recorder sets `review:<target>` where `target = min(effective_round, 3)`. If the target round is strictly less than an existing `review:<n>` label already attached to the pull request, the higher existing label is preserved. Exactly one `review:<n>` label is present once reviews commence. | Transient parsing or re-evaluations must never decrement the round counter, ensuring merge-gate round cap escalations (such as escalation to `review:3`) operate reliably. |
| D8 | **Python engine extraction to `scripts/ci/review_recorder.py` (docs/PLAYBOOK.md:521 compliance).** The embedded Python heredoc inside `scripts/ci/review_recorder.sh` is extracted into a standalone Python file `scripts/ci/review_recorder.py`. `scripts/ci/review_recorder.sh` acts as the outer shell entrypoint (preflight, viewer login query, pre-write hold checks, and invocation of `python3 scripts/ci/review_recorder.py`), while `scripts/ci/review_recorder.py` performs review parsing, ledger generation, action plan derivation, and write execution. This satisfies `docs/PLAYBOOK.md:521-524`. | Embedding a large Python script inside a shell heredoc violates `docs/PLAYBOOK.md:521` by obscuring logic from execution transcripts and static analysis. |
| D9 | **Historical ledger immutability and event-driven updates.** Amended recording rules apply strictly on subsequent recorder executions triggered by workflow events (`pull_request`, `issue_comment`, `check_suite`, `status`, `workflow_dispatch`). Historical consensus comments posted prior to this amendment are not retroactively modified. | Preserves audit trail integrity on merged and historical pull requests. |
| D10 | **Implementation scope boundary.** The implementing pull request for #291 may touch `scripts/ci/review_recorder.sh`, `scripts/ci/review_recorder.py` (new), `scripts/ci/tests/review_recorder_test.sh`, `docs/SPEC.md`, `intent/267-severity-tiered-merge-gate-review-md/spec.md`, and `intent/291-recorder-hold-parity/spec.md`. It may not touch `.github/workflows/unattended.yml`, `.github/workflows/lifecycle.yml`, `scripts/ops/post.sh`, `personas/**`, `scripts/ci/escalate.sh`, or `scripts/ci/lifecycle_advance.sh`. | Establishes strict scope fences preventing interference with concurrent workflow tasks and protected persona configurations. |

## Acceptance

- **AT-291-1 (D1, D2)** Run `bash scripts/ci/tests/review_recorder_test.sh -k test_label_sync`: passes with exit code 0, verifying in case (a) that a pull request carrying label `hold` produces zero writes, logs `hold present on #109, recorder writes nothing`, and exits 0.
- **AT-291-2 (D1, D2)** Run `bash scripts/ci/tests/review_recorder_test.sh -k test_label_sync`: passes with exit code 0, verifying in case (c) that a pull request closing an issue carrying label `hold` produces zero writes, logs `hold present on #209, recorder writes nothing`, and exits 0.
- **AT-291-3 (D3)** Run `bash scripts/ci/tests/review_recorder_test.sh -k test_label_sync`: passes with exit code 0, verifying in case (b) that unrelated labels such as `bootstrap` are preserved while `review:1` is replaced with `review:2` and derived labels `argus:findings`, `argus:suggestions`, and `consensus:disputed` synchronize.
- **AT-4 (D4) / AT-291-4 (D4)** Run `bash scripts/ci/tests/review_recorder_test.sh -k test_high_failure_scenario_demotion`: passes with exit code 0, verifying that a `high` finding lacking a sibling `failure-scenario` marker is demoted to `normal` with audit note `[demoted from high: missing failure_scenario marker] on <id>`.
- **AT-291-5 (D5)** Run `bash scripts/ci/tests/review_recorder_test.sh -k test_label_sync`: passes with exit code 0, asserting that `high` findings bearing `peer=dispute` or `status=withdrawn` lacking sibling `failure-scenario` markers survive as `high` and are not demoted.
- **AT-291-6 (D6)** Run `bash scripts/ci/tests/review_recorder_test.sh -k test_round_funnel`: passes with exit code 0, proving that historical suggestions carried forward from earlier rounds retain `suggestion` while new observations filed in Round 2 or 3 land as `normal` with `peer=none`.
- **AT-291-7 (D7)** Run `bash scripts/ci/tests/review_recorder_test.sh -k test_label_sync`: passes with exit code 0, asserting that the round counter progresses monotonically (case d) and does not decrement existing higher round labels.
- **AT-291-8 (D8)** Run `bash scripts/ci/tests/review_recorder_test.sh -k test_python_engine_extraction`: passes with exit code 0, asserting that `scripts/ci/review_recorder.sh` invokes the extracted `scripts/ci/review_recorder.py` engine as a standalone script.
- **AT-291-9 (D1, D2)** Run `bash scripts/ci/tests/review_recorder_test.sh -k test_write_time_hold_reread`: passes with exit code 0, asserting observable write-time hold re-read behavior: when `hold` is added dynamically after initial action plan derivation, the re-read halts all writes, logs `hold present on #<target>, recorder writes nothing`, and exits 0 with zero writes recorded.
- **AT-291-10 (D10)** Run `bash scripts/ci/sanitize_check.sh`, `bash scripts/ci/spec_check.sh origin/main`, and `python3 scripts/sync_agents.py --check`: all exit 0 with clean output.
- **AT-291-11 (D1, D2)** Run `bash scripts/ci/tests/review_recorder_test.sh -k test_hold_probe_fail_closed`: passes with exit code 0, asserting fail-closed behavior when probing hold status fails with an API error (logs probe error, performs zero writes, exits non-zero).

## Concerns

- **Atomic write sequence versus multi-check overhead.** Checking `hold` before each individual write call (`PATCH` comment, then `gh issue edit`) would introduce potential race conditions where a comment updates but label edits abort. Consolidating all writes into a single contiguous block guarded by an immediate re-read provides consistency.
- **Deduplication of demotion audit notes.** Appending `on <id>` prevents Markdown table deduplication from hiding multiple demotions under one note.
- **Extraction of Python heredoc.** Extracting the Python script simplifies testing, syntax checking, and linting, fully satisfying `docs/PLAYBOOK.md:521`.

## Out of scope

- Modifying reviewer triggering or dispatch policies in `.github/workflows/unattended.yml`.
- Modifying merge gate conjunct evaluation in `scripts/ci/merge_gate.sh`.
- Retroactively altering historical ledger comments on merged pull requests.

## Operator decisions

None required.

Open questions: none
