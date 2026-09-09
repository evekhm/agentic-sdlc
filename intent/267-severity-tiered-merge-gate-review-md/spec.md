# Spec: Severity-tiered review recorder and consensus ledger

**Issue:** #267 · **Status:** Approved (approval = merge of this PR) ·
**Author:** athena (`evekhm-athena-app[bot]`) ·
**Open questions:** none

## What is being built

The consensus ledger recorder bridges automated code review and autonomous
pull request merge gating. When review personas post review comments, the
recorder parses structured review verdicts emitted by Argus and Atlas,
enforces severity rules and the round admissibility funnel, updates an
authoritative consensus ledger comment on the pull request as Themis, and
derives lifecycle review labels.

```text
scripts/ci/review_recorder.sh            # review parsing, commit validation, demotions, ledger updates, labels
scripts/ci/tests/review_recorder_test.sh # hermetic test suite with stubbed GitHub API
.github/workflows/merge-gate.yml         # record job before gate under environment: themis
REVIEW.md                                # marker block syntax, demotions, round funnel, retier commands
personas/skills/review-protocol.md       # reviewer requirement to emit structured verdict blocks
scripts/ci/merge_gate.sh                 # severity enum comment and regex update for suggestion
scripts/ci/tests/merge_gate_test.sh      # consensus ledger fixtures and enum tests aligned with suggestion
scripts/setup/bootstrap_tracker.sh       # idempotent provisioning for review and consensus labels
scripts/setup/issues/04-label-taxonomy.md # taxonomy documentation for review and consensus labels
docs/SPEC.md                             # living spec updates for recorder behavior, ledger, and labels
```

Workflows `unattended.yml` and `lifecycle.yml`, the posting wrapper `post.sh`,
and persona definitions under `personas/**` (outside
`personas/skills/review-protocol.md`) are not touched.

## Decisions

| ID | Decision | Rationale |
|---|---|---|
| D1 | **Recorder execution context and placement.** The recorder lives at `scripts/ci/review_recorder.sh` and runs in `.github/workflows/merge-gate.yml` inside a dedicated `record` job that executes prior to the `gate` job. It runs under `environment: themis` on `issue_comment` (types: created, edited), `check_suite` (types: completed), and `workflow_dispatch` events. The recorder performs writes directly via `gh api` using the minted Themis GitHub App token. `scripts/ops/post.sh` is excluded because it requires a persona YAML definition in `personas/`, whereas Themis is an infrastructure system identity. `.github/workflows/unattended.yml` and `.github/workflows/lifecycle.yml` are unchanged. | Placing the recorder in `merge-gate.yml` before `gate` guarantees sequential execution on review events, ensuring ledger state is recorded before merge evaluation. A separate workflow would run concurrently and introduce race conditions against the merge gate. |
| D2 | **Reviewer verdict output contract.** Reviewers emit a structured verdict block in their pull request review comments: <br>`<!-- review-verdict:<reviewer> -->`<br>`<!-- reviewed-head:<full-oid> -->`<br>`<!-- round:<n> -->`<br>`<!-- finding:<id>:<severity>:<status>:<peer> -->`<br>`<!-- review-verdict-end -->`<br>alongside human-readable review tables. The finding line matches regex `^<!-- finding:([A-Za-z0-9-]+):(security\|high\|normal\|suggestion):(open\|fixed\|withdrawn):(pending\|agree\|dispute\|none) -->$`. Reviewers update `REVIEW.md` and `personas/skills/review-protocol.md` to produce this block. Comments lacking this block are ignored. The recorder validates that `<full-oid>` exists in the pull request commit history; verdicts referencing commits absent from the commit list are rejected. | Structured comment blocks allow deterministic parsing without NLP heuristics. Ignoring comments without markers preserves conversational thread comments and historical reviews. Checking the reviewed commit against pull request history prevents reviewers from recording findings against foreign commits. |
| D3 | **Reviewer identity and trust model.** The recorder validates that comment author logins match authorized reviewer App identities (`evekhm-argus-app[bot]`, `evekhm-atlas-app[bot]`) and verifies that `reviewed-head` exists in pull request commits. The known residual risk is that same-repo pull request workflows have access to `ARGUS_APP_PRIVATE_KEY` and `ATLAS_APP_PRIVATE_KEY` repository secrets. Target state migration of reviewer keys to main-only Environments and run-from-main workflows is owned by #251 and #265. The recorder wire format remains unchanged across that migration. | Restricting parsing to verified App logins and validated commit SHAs establishes defensible provenance under current infrastructure. Formal secret isolation is delegated to the architecture defined in #251. |
| D4 | **Single in-place consensus ledger comment.** The consensus ledger exists as exactly one pull request comment carrying `<!-- consensus-ledger:<pr> -->`, authored by Themis. The recorder locates this comment by paginating pull request comments to exhaustive depth. If present, the recorder updates the existing comment in place via `PATCH /repos/<repo>/issues/comments/<id>`. If absent, the recorder creates it via `POST /repos/<repo>/issues/<pr>/comments`. | `scripts/ci/merge_gate.sh:262` reads `sort_by(.id) \| .[0]`, selecting the earliest matching comment. Creating append-only comments would cause the merge gate to read a stale initial comment indefinitely. In-place modification guarantees the gate always evaluates the current state. |
| D5 | **Authoritative four-tier enum and high demotion.** The authoritative severity enum is `security`, `high`, `normal`, `suggestion`. This resolves naming drift between `REVIEW.md:88` (`suggestion`) and `scripts/ci/merge_gate.sh:28,271` (`low`). The regular expression in `scripts/ci/merge_gate.sh:271` and test fixtures in `scripts/ci/tests/merge_gate_test.sh` are updated to support `suggestion`. Any finding marked `high` that fails to match the closed list in `REVIEW.md:102-111` or lacks a concrete `failure_scenario` is demoted by the recorder to `normal` on the ledger row, with an explanatory note added to the human-readable table: `[demoted from high: not on closed list / missing failure_scenario]`. | Settling on `suggestion` aligns the codebase with `REVIEW.md`. Automatic demotion of invalid high findings enforces rigor mechanically without halting the pipeline on ungrounded blocking claims. |
| D6 | **Round derivation and admissibility funnel.** The recorder extracts the review round number from `<!-- round:<n> -->` and verifies it against prior rounds. In Round 1, all severity tiers are admissible. In Rounds 2 and 3, new findings are accepted only if classified as `security` or valid `high`; new `normal` or `suggestion` findings are demoted to non-blocking status with note `[late finding: non-blocking per round funnel]`. Beyond Round 3, only new `security` findings are accepted; all other new findings are demoted. | The round funnel prevents late non-critical findings from prolonging review cycles indefinitely, converting an informal guideline into an enforced mechanical gate. |
| D7 | **Peer consensus column and status transitions.** Argus findings use namespace `R<round>-<n>`; Atlas findings use namespace `AT-R<round>-<n>`. Peer states are `pending`, `agree`, `dispute`, `none`. `security` rows initialize with `peer=pending` and require explicit peer concurrence to reach `peer=agree`. In accordance with `REVIEW.md:257-259`, security findings require dual agreement twice: once on finding validity and once on fix verification. `high` rows carry `peer=none` unless explicitly disputed. An explicit dispute on any blocking row sets `peer=dispute`. Finding status transitions to `fixed` only when verified by the discovering reviewer on a newer commit, or to `withdrawn` when retracted by that reviewer. Pull request authors cannot close findings through author assertions. | Requiring two-party verification for security findings protects critical trust paths. Restricting finding resolution to the reporting reviewer prevents unilateral dismissal by authors. |
| D8 | **Label derivation by Themis.** The recorder derives pull request labels from ledger state and updates them using the Themis token: `argus:findings` (open blocking rows exist), `argus:suggestions` (open non-blocking rows exist), `consensus:agreed` (no open security rows awaiting peer, all security agreed, no dispute), `consensus:pending` (open security row awaiting peer verdict), `consensus:disputed` (dispute on any blocking row), `review:merge-ready` (no open blocking rows, consensus agreed, reviewed head matches pull request head), and `review:verifying` (open blocking rows exist and pull request head is newer than reviewed head). `scripts/ci/merge_gate.sh` evaluates the ledger block directly. Labels are provisioned by `scripts/setup/bootstrap_tracker.sh --labels-only`. | Labels provide immediate visual feedback on pull request status across developer interfaces. Decoupling label display from merge gate evaluation ensures the gate depends directly on cryptographic and ledger evidence. |
| D9 | **Owner retier verb.** Repository maintainers can override finding severities by posting `@argus retier <id> <severity>` or `@atlas retier <id> <severity>`. The recorder processes retier commands only from accounts with `admin` or `write` collaborator permissions, verified via `gh api repos/<repo>/collaborators/<user>/permission`. Commands from bot accounts or unauthorized users are ignored. An accepted retier command updates the row severity, recalculates derived labels, and annotates the ledger table with `[retiered to <severity> by @<user>]`. | Human authority retains final arbitration over disputed or misclassified findings. Restricting retier parsing to verified human collaborators blocks unauthorized severity manipulation. |
| D10 | **Treatment of unformatted comments and legacy reviews.** Comments lacking structured verdict markers are ignored by the recorder. Pull requests containing historical reviews without marker blocks (such as PR #280 and PR #283) remain in the state lacking a consensus ledger until a reviewer posts a compliant verdict block or a fresh review cycle runs. | Permitting non-compliant comments to pass unparsed preserves unstructured conversational comments and prevents unexpected build failures on older pull requests. |
| D11 | **Disposition of issue #238 gates.** Issue #238 retains ownership of G1 (pre-dispatch diff verification of repair claims) and G2 (convergence rate escalation). The recorder provides the ledger rows, round tracking, and open blocking tallies that G2 evaluates. G1 operates as an intake gate in `.github/workflows/unattended.yml`, while G2 operates within `scripts/ci/escalate.sh`. | Preserving G1 and G2 in issue #238 avoids overloading the recorder script and maintains modular responsibility between review execution, state recording, and escalation. |
| D12 | **Implementation scope boundary.** The implementing pull request may touch `scripts/ci/review_recorder.sh`, `scripts/ci/tests/review_recorder_test.sh`, `.github/workflows/merge-gate.yml`, `REVIEW.md`, `personas/skills/review-protocol.md`, `scripts/ci/merge_gate.sh`, `scripts/ci/tests/merge_gate_test.sh`, `scripts/setup/bootstrap_tracker.sh`, `scripts/setup/issues/04-label-taxonomy.md`, and `docs/SPEC.md`. It may not touch `.github/workflows/unattended.yml`, `.github/workflows/lifecycle.yml`, `scripts/ops/post.sh`, `personas/**` (outside `review-protocol.md`), `scripts/ci/escalate.sh`, or `scripts/ci/lifecycle_advance.sh`. | Clean scope boundaries prevent merge conflicts with concurrent issues and protect autonomous lifecycle advance workflows from unintended edits. |

## Acceptance

- **AT-1 (D1)** `bash scripts/ci/tests/review_recorder_test.sh` executes
  hermetically with a stubbed `gh` capturing API writes, exercising parser
  scenarios and exit codes without network dependencies.
- **AT-2 (D2)** The parser extracts finding ID, severity, status, and peer
  values from valid `<!-- finding:... -->` tags, ignoring surrounding
  markdown headings and explanatory body text.
- **AT-3 (D2, D3)** When `reviewed-head` matches a commit in the pull request
  commit history, the verdict is processed; an unlisted commit SHA causes the
  recorder to log a rejection and refuse updates.
- **AT-4 (D4)** When no consensus ledger comment exists, the recorder posts a
  new comment via `POST /repos/<repo>/issues/<pr>/comments`; on subsequent
  executions, it modifies the comment via `PATCH /repos/<repo>/issues/comments/<id>`,
  preserving the comment ID.
- **AT-5 (D5)** High findings outside the five items in `REVIEW.md:102-111` or
  lacking a concrete `failure_scenario` are demoted to `normal` on wire rows
  and annotated in the markdown table.
- **AT-6 (D6)** New `normal` and `suggestion` findings in Round 2 or Round 3
  are recorded as non-blocking; new non-security findings beyond Round 3 are
  demoted to `normal`.
- **AT-7 (D7)** A `security` row remains `peer=pending` until explicit peer
  agreement is parsed; both finding validity and fix verification require
  dual explicit agreement before reaching clean state.
- **AT-8 (D9)** An explicit `@argus retier <id> <severity>` comment by a user
  holding write permissions updates row severity; identical comments from bot
  identities or read-only users are ignored.
- **AT-9 (D8)** Derived labels (`argus:findings`, `argus:suggestions`,
  `consensus:*`, `review:merge-ready`, `review:verifying`) are synchronized via
  `gh issue edit` to match computed ledger state.
- **AT-10 (D5)** `bash scripts/ci/tests/merge_gate_test.sh` passes with
  consensus ledger fixtures containing `suggestion` rows, confirming parser
  alignment.
- **AT-11 (D8)** `bash scripts/setup/bootstrap_tracker.sh --labels-only`
  idempotently provisions all seven review and consensus labels with designated
  colors and descriptions.
- **AT-12 (D12)** `bash scripts/ci/spec_check.sh origin/main` and
  `bash scripts/ci/sanitize_check.sh` pass cleanly on the implementation branch.
- **AT-13 (D9)** An accepted retier command adds an audit annotation
  `[retiered to <severity> by @<user>]` to the ledger table while preserving
  the finding description and identifier.
- **AT-14 (D7)** A security finding with peer agreement, followed by a fix
  attempt on a newer commit, requires the discovering reviewer to mark status
  as `fixed` and the peer to post agreement on the fix before clearance.

## Concerns

- **In-place comment updates vs append-only log.**
  `scripts/ci/merge_gate.sh:262` reads `sort_by(.id) | .[0]` (the earliest
  comment). If the recorder appended a new comment on each run, the merge gate
  would read the stale first comment indefinitely. Editing the existing comment
  via `PATCH /repos/<repo>/issues/comments/<id>` guarantees the gate reads
  current state. Pagination to exhaustive depth guarantees that an existing
  comment is located reliably.
- **Severity enum drift.** `REVIEW.md:88` specifies `suggestion` while
  `scripts/ci/merge_gate.sh:28,271` uses `low`. Reconciling this drift requires
  an interface change in `merge_gate.sh:271` to accept `suggestion`. The
  implementation PR must update this regex and its associated tests in
  `merge_gate_test.sh` simultaneously. During transition, accepting both
  `suggestion` and `low` maintains backward compatibility with older branches.
- **Reviewer secret isolation and interim trust.** Reviewer credentials
  currently reside in repository secrets accessible to pull request branch
  workflows. The interim mitigation verifies comment author logins and
  cross-references `reviewed-head` against pull request commit history. Full
  isolation is achieved when reviewer keys migrate to main-only Environments
  under #251 and #265. The recorder wire format remains unchanged when that
  architecture lands.
- **Separation of recorder mechanics from G1/G2 gates.** Issue #238 defines
  G1 (pre-dispatch diff verification) and G2 (convergence rate escalation). The
  recorder provides the ledger rows and round counts required by G2, but
  pre-dispatch validation belongs in `unattended.yml` and convergence
  escalation belongs in `escalate.sh`. Keeping them in #238 avoids overloading
  the recorder script with dispatch and escalation logic.
- **Legacy reviews and unformatted comments.** Historical pull requests such
  as PR #280 and PR #283 lack structured machine blocks. The recorder ignores
  unformatted comments, leaving those pull requests without a consensus ledger
  until compliant verdicts are posted. This prevents unintended parse failures
  on conversational threads.
- **Label synchronization idempotency.** Label derivation must synchronize
  labels without conflicting with manual operator interventions. The recorder
  reconciles the seven derived labels on each execution, adding required labels
  and removing stale labels while preserving unrelated issue labels such as
  `hold` or `bootstrap`.
- **Serialized execution and gate concurrency.** The recorder executes inside
  `.github/workflows/merge-gate.yml` in a job preceding `gate`. Because both
  jobs share the `merge-gate` concurrency group, recording completes before
  merge gating begins, avoiding race conditions between ledger generation and
  merge evaluation.
- **Comment payload volume.** GitHub issue comments have a size limit of
  65,536 characters. For pull requests with long review histories, the ledger
  table displays open findings and active disputes in detail while compacting
  historical resolved rounds into single summary counts.

## Out of scope

- Modifying reviewer triggering, dispatch, or assignment policies in
  `.github/workflows/unattended.yml` (#265).
- Moving reviewer App credentials to main-only GitHub Environments (#251).
- Convergence rate escalation logic and pre-dispatch diff verification (#238).
- Modifying autonomous loop merge predicates or escalation scripts (#64).

## Operator decisions

None are required by this spec. For the record: the implementation dispatch
goes to the odyssey rung after the plan, and no secret or GitHub App changes
are required.

Open questions: none
