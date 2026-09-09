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
| D1 | **Recorder execution context and placement.** The recorder lives at `scripts/ci/review_recorder.sh` and runs in `.github/workflows/merge-gate.yml` inside a dedicated `record` job that executes prior to the `gate` job (`gate` declares `needs: record`). Both jobs run under `environment: themis` and share `concurrency: group: merge-gate`. The workflow triggers on existing events: `issue_comment` (types: `[created]`), `check_suite` (types: `[completed]`), `status`, and `workflow_dispatch`. The `issue_comment` trigger retains `types: [created]` without adding `edited`. On `check_suite` and `status` push events, the ledger is re-derived and stale head markers are dropped. The `record` job skips execution entirely when `github.event.sender.login` is the Themis App login (`evekhm-themis-app[bot]`). It skips the `PATCH` API request when the newly rendered ledger body equals the existing comment body byte for byte. The recorder performs writes directly via `gh api` using the minted Themis GitHub App token; this supersedes the constraint in `intent.md:76` because `scripts/ops/post.sh` requires persona YAML definitions (`post.sh:94-98`, `170-179`) whereas Themis is an infrastructure system identity. `.github/workflows/unattended.yml` and `.github/workflows/lifecycle.yml` are unchanged. | Placing `record` before `gate` with explicit job dependencies ensures sequential execution on review events, ensuring ledger state is recorded before merge evaluation. Sharing the concurrency group serializes runs across the repository, while idempotency guards prevent recursive or redundant workflow dispatches. |
| D2 | **Reviewer verdict output contract.** Reviewers emit a structured verdict block in their pull request review comments: <br>`<!-- review-verdict:<reviewer>:<verdict> -->`<br>`<!-- reviewed-head:<full-oid> -->`<br>`<!-- run-id:<n> -->`<br>`<!-- round:<n> -->`<br>`<!-- finding:<id>:<severity>:<status>:<peer> -->`<br>`<!-- failure-scenario:<id> -->`<br>`<!-- review-verdict-end -->`<br>alongside human-readable review tables, where `<verdict>` is `clean` or `findings`. The `<id>` field carries `@<Dn>` when citing a spec Decision (such as `R1-1@D4`) or `@none` when uncited, matching `REVIEW.md:290-305`. Each `high` finding must be immediately accompanied by its sibling marker `<!-- failure-scenario:<id> -->`. The finding line matches regex `^<!-- finding:([A-Za-z0-9-@]+):(security\|high\|normal\|suggestion):(open\|fixed\|withdrawn):(pending\|agree\|dispute\|none) -->$`. The reviewer block provides `<!-- reviewed-head:<full-oid> -->`; the recorder qualifies this per reviewer when generating the ledger (`<!-- reviewed-head:argus:<40-hex> -->`, `<!-- reviewed-head:atlas:<40-hex> -->`) matching `scripts/ci/merge_gate.sh:268-269`. Reviewers update `REVIEW.md` and `personas/skills/review-protocol.md` to produce this block. Comments lacking this block are ignored. The recorder validates that `<full-oid>` exists in pull request commit history; verdicts referencing commits absent from the commit list are rejected. Evaluating whether a `high` finding belongs to the closed list in `REVIEW.md:102-111` is a reviewer protocol duty defined in `personas/skills/review-protocol.md`, outside parser responsibility. | Structured comment blocks allow deterministic parsing without NLP heuristics. Ignoring comments without markers preserves conversational thread comments and historical reviews. Checking the reviewed commit against pull request history prevents reviewers from recording findings against foreign commits. |
| D3 | **Reviewer identity and interim trust model.** The recorder verifies reviewer provenance using check-run and workflow-run validation. A verdict block is accepted only when the comment author is an authorized reviewer App (`evekhm-argus-app[bot]`, `evekhm-atlas-app[bot]`), `reviewed-head` exists in pull request commits, and the referenced `<!-- run-id:<n> -->` matches an authentic workflow run verified via `GET /repos/<repo>/actions/runs/<run_id>` (matching `head_sha`, workflow path `.github/workflows/unattended.yml`, event `pull_request`, and conclusion `success`). Residual risk: a pull request branch workflow run can name its own run ID; what it cannot forge is the run being a main-ref run, which the run-from-main architecture in #251 and #265 closes. | Validating the Actions run ID, head SHA, workflow path, and conclusion provides machine-checked provenance preventing forged review comments from unassociated runs. Formal secret isolation moves to main-only Environments under #251 and #265. |
| D4 | **Single in-place consensus ledger comment and emitted wire format.** The consensus ledger exists as exactly one pull request comment authored by Themis. The recorder finds this comment by paginating pull request comments to exhaustive depth. If absent, it creates the comment via `POST /repos/<repo>/issues/<pr>/comments`. If present, it updates the comment via `PATCH /repos/<repo>/issues/comments/<id>`. The emitted comment body matches `scripts/ci/tests/merge_gate_test.sh:236-247` and `scripts/ci/merge_gate.sh:265-271` byte for byte: <br>`### Findings ledger for #<pr>`<br>`<!-- consensus-ledger:<pr> -->`<br>`<!-- reviewed-head:argus:<40-hex> -->`<br>`<!-- reviewed-head:atlas:<40-hex> -->`<br>`<!-- ledger-row:<id>:<severity>:<status>:<peer> -->`<br>`<!-- consensus-ledger-end -->`<br>followed by the human-readable markdown table. The `reviewed-head:argus:<40-hex>` and `reviewed-head:atlas:<40-hex>` lines are included only when that reviewer's verdict for the current head commit was accepted. Finding IDs carry `@<Dn>` when cited in the review. | `scripts/ci/merge_gate.sh:262` selects the earliest matching comment via `sort_by(.id) \| .[0]`. In-place updates preserve comment identity while ensuring downstream parsers read the exact markers and ledger rows required by the merge gate. |
| D5 | **Authoritative four-tier enum, loud refusal, and high demotion.** The authoritative severity enum is `security`, `high`, `normal`, `suggestion`. This replaces `low` outright in `scripts/ci/merge_gate.sh:28,271` and `scripts/ci/tests/merge_gate_test.sh` in the implementing pull request without a transition period. The regular expression in `scripts/ci/merge_gate.sh:271` is updated to `^<!-- ledger-row:([A-Za-z0-9-@]+:(security\|high\|normal\|suggestion):(open\|fixed\|withdrawn):(pending\|agree\|dispute\|none)) -->$`. Any finding specifying a severity outside these four values fails validation loudly: the recorder logs `finding <id>: severity <x> is not one of security\|high\|normal\|suggestion` and refuses the entire verdict block without updating the ledger. Any finding marked `high` that lacks a sibling `<!-- failure-scenario:<id> -->` marker is demoted by the recorder to `normal` on the ledger row, with an explanatory note added to the ledger table: `[demoted from high: missing failure_scenario marker]`. | Settling on `suggestion` eliminates naming drift. Immediate loud refusal prevents invalid severities from entering ledger state. Mechanical demotion enforces concrete failure scenarios without manual intervention. |
| D6 | **Round derivation and admissibility funnel.** The recorder extracts the review round number from `<!-- round:<n> -->` and verifies it against prior rounds. In Round 1, all severity tiers are admissible. In Rounds 2 and 3, new findings are accepted only if classified as `security` or valid `high`; new `normal` or `suggestion` findings are recorded as late informational notes (`[late finding: inadmissible after round 1]`) and do not create tracking rows. Beyond Round 3, only new `security` findings are accepted; other new findings are recorded with `[late finding: inadmissible after round 3]` and do not create blocking rows. | The round funnel prevents late non-critical findings from prolonging review cycles indefinitely, converting an informal guideline into an enforced mechanical gate. |
| D7 | **Peer consensus column and status transitions.** Argus findings use namespace `R<round>-<n>`; Atlas findings use namespace `AT-R<round>-<n>`. Peer states are `pending`, `agree`, `dispute`, `none`. `security` rows initialize with `peer=pending` and require explicit peer concurrence to reach `peer=agree`. In accordance with `REVIEW.md:258-260`, security findings require dual agreement twice: once on finding existence and once on fix verification. `high` rows carry `peer=none` unless explicitly disputed. An explicit dispute on any blocking row sets `peer=dispute`. Finding status transitions to `fixed` only when verified by the discovering reviewer on a newer commit, or to `withdrawn` when retracted by that reviewer. Pull request authors cannot close findings through author assertions. | Requiring two-party verification for security findings protects critical trust paths. Restricting finding resolution to the reporting reviewer prevents unilateral dismissal by authors. |
| D8 | **Label derivation by Themis and round counter ownership.** The recorder derives pull request labels from ledger state and updates them using the Themis token, adhering to the taxonomy in issue #4 (`scripts/setup/issues/04-label-taxonomy.md`): `argus:findings` (open blocking rows exist), `argus:suggestions` (open non-blocking rows exist), `consensus:agreed` (no open security rows awaiting peer, all security agreed, no dispute), `consensus:pending` (open security row awaiting peer verdict), `consensus:disputed` (dispute on any blocking row), `review:merge-ready` (no open blocking rows, consensus agreed, reviewed head matches pull request head), `review:verifying` (open blocking rows exist and pull request head is newer than reviewed head), and the round counter `review:1`, `review:2`, `review:3` (set from highest accepted round at head; exactly one present). A ledger lacking a head marker earns neither head-pinned label, and a failed head probe freezes both per `REVIEW.md:346-348`. `status:review-stuck` remains written by `scripts/ci/escalate.sh` when `scripts/ci/merge_gate.sh:442-451` triggers on `review:3`; this completes the hand-off from `scripts/ci/lifecycle_advance.sh:56-57`. Labels are provisioned by `scripts/setup/bootstrap_tracker.sh --labels-only`. | Managing the round counter in the recorder ensures the merge gate's round-cap escalation operates as designed. Decoupling visual indicators from merge evaluation ensures the gate inspects ledger evidence directly. |
| D9 | **Owner retier verb.** Repository maintainers can override finding severities by posting `@argus retier <id> <severity>` or `@atlas retier <id> <severity>`. The recorder processes retier commands only from accounts with `admin` or `write` collaborator permissions, verified via `gh api repos/<repo>/collaborators/<user>/permission`. Commands from bot accounts or unauthorized users are ignored. An accepted retier command updates row severity, recalculates derived labels, and annotates the ledger table with `[retiered to <severity> by @<user>]`. | Human authority retains final arbitration over disputed or misclassified findings. Restricting retier parsing to verified human collaborators blocks unauthorized severity manipulation. |
| D10 | **Treatment of unformatted comments and legacy reviews.** Comments lacking structured verdict markers are ignored by the recorder. Pull requests containing historical reviews without marker blocks (such as PR #280 and PR #283) remain in the state lacking a consensus ledger until a reviewer posts a compliant verdict block or a fresh review cycle runs. | Permitting non-compliant comments to pass unparsed preserves unstructured conversational comments and prevents unexpected build failures on older pull requests. |
| D11 | **Disposition of issue #238 gates.** Issue #238 retains ownership of G1 (pre-dispatch diff verification of repair claims) and G2 (convergence rate escalation). The recorder provides the ledger rows, round tracking, and open blocking tallies that G2 evaluates. G1 operates as an intake gate in `.github/workflows/unattended.yml`, while G2 operates within `scripts/ci/escalate.sh`. | Preserving G1 and G2 in issue #238 avoids overloading the recorder script and maintains modular responsibility between review execution, state recording, and escalation. |
| D12 | **Implementation scope boundary.** The implementing pull request may touch `scripts/ci/review_recorder.sh`, `scripts/ci/tests/review_recorder_test.sh`, `.github/workflows/merge-gate.yml`, `REVIEW.md`, `personas/skills/review-protocol.md`, `scripts/ci/merge_gate.sh`, `scripts/ci/tests/merge_gate_test.sh`, `scripts/setup/bootstrap_tracker.sh`, `scripts/setup/issues/04-label-taxonomy.md`, and `docs/SPEC.md`. It may not touch `.github/workflows/unattended.yml`, `.github/workflows/lifecycle.yml`, `scripts/ops/post.sh`, `personas/**` (outside `review-protocol.md`), `scripts/ci/escalate.sh`, or `scripts/ci/lifecycle_advance.sh`. | Clean scope boundaries prevent merge conflicts with concurrent issues and protect autonomous lifecycle advance workflows from unintended edits. |

## Acceptance

- **AT-1 (D1)** Run `bash scripts/ci/tests/review_recorder_test.sh`: passes with
  exit code 0, exercising parser execution, idempotency short-circuiting, and
  API calls against a hermetic test stub.
- **AT-2 (D2)** Run `bash scripts/ci/tests/review_recorder_test.sh -k test_marker_parsing`:
  passes with exit code 0, verifying extraction of verdict, run-id, round,
  finding lines (including Decision-ID `@<Dn>` tags), and sibling `failure-scenario`
  markers.
- **AT-3 (D2, D3)** Run `bash scripts/ci/tests/review_recorder_test.sh -k test_provenance_validation`:
  passes with exit code 0, confirming acceptance of matching App logins, commit
  SHAs, and successful `unattended.yml` workflow runs, and refusal of unlisted
  commits or invalid run IDs.
- **AT-4 (D4)** Run `bash scripts/ci/tests/review_recorder_test.sh -k test_ledger_comment_lifecycle`:
  passes with exit code 0, confirming `POST` creation on initial review and
  in-place `PATCH` on subsequent reviews, preserving comment ID.
- **AT-5 (D5)** Run `bash scripts/ci/tests/review_recorder_test.sh -k test_high_failure_scenario_demotion`:
  passes with exit code 0, asserting that a `high` finding lacking a sibling
  `failure-scenario` marker is demoted to `normal` on the wire row with ledger
  table note `[demoted from high: missing failure_scenario marker]`.
- **AT-6 (D5)** Run `bash scripts/ci/tests/review_recorder_test.sh -k test_non_enum_severity_refusal`:
  passes with exit code 0, verifying that an invalid severity such as `critical`
  or legacy `low` outputs `finding <id>: severity <x> is not one of security|high|normal|suggestion`
  and causes the recorder to exit with non-zero status.
- **AT-7 (D6)** Run `bash scripts/ci/tests/review_recorder_test.sh -k test_round_funnel`:
  passes with exit code 0, confirming that new non-blocking findings in Round 2
  or 3 and new non-security findings beyond Round 3 do not create blocking rows.
- **AT-8 (D7)** Run `bash scripts/ci/tests/review_recorder_test.sh -k test_security_dual_agreement`:
  passes with exit code 0, proving a security finding requires explicit peer
  concurrence on both finding validity and fix verification before clearance
  per `REVIEW.md:258-260`.
- **AT-9 (D9)** Run `bash scripts/ci/tests/review_recorder_test.sh -k test_owner_retier`:
  passes with exit code 0, verifying that an authorized maintainer comment
  `@argus retier <id> <severity>` updates finding severity with audit note
  `[retiered to <severity> by @<user>]` while unauthorized commands are ignored.
- **AT-10 (D8)** Run `bash scripts/ci/tests/review_recorder_test.sh -k test_label_sync`:
  passes with exit code 0, asserting derived labels (`argus:findings`,
  `argus:suggestions`, `consensus:*`, `review:merge-ready`, `review:verifying`,
  and `review:1..3`) synchronize via `gh issue edit`.
- **AT-11 (D5)** Run `bash scripts/ci/tests/merge_gate_test.sh`: passes with
  exit code 0, confirming that `merge_gate.sh` processes consensus ledger
  fixtures using `suggestion` and rejects legacy `low`.
- **AT-12 (D8)** Run `bash scripts/setup/bootstrap_tracker.sh --labels-only`:
  exits 0 and outputs provisioning confirmation for all seven review and
  consensus labels (`argus:findings`, `argus:suggestions`, `consensus:agreed`,
  `consensus:pending`, `consensus:disputed`, `review:merge-ready`,
  `review:verifying`).
- **AT-13 (D4)** Run `bash scripts/ci/tests/review_recorder_test.sh -k test_merge_gate_round_trip`:
  passes with exit code 0, asserting that a recorder-emitted ledger fed to
  `scripts/ci/merge_gate.sh` under its test stub evaluates conjuncts 3, 4, 5,
  and 11 as true.
- **AT-14 (D4)** Live run: one `Merge Gate` workflow execution on a pull request
  with both accepted reviewer verdict blocks evaluating conjuncts 3, 4, 5, and 11
  true, cited by Actions run ID, listed under NOT RUN until #64 acceptance 20.
- **AT-15 (D12)** Run `bash scripts/ci/spec_check.sh origin/main && bash scripts/ci/sanitize_check.sh`:
  exits 0 with no diff errors or sanitized term violations.

## Concerns

- **In-place comment updates vs append-only log.**
  `scripts/ci/merge_gate.sh:262` reads `sort_by(.id) | .[0]` (the earliest
  comment). If the recorder appended a new comment on each run, the merge gate
  would read the stale first comment indefinitely. Editing the existing comment
  via `PATCH /repos/<repo>/issues/comments/<id>` guarantees the gate reads
  current state. Pagination to exhaustive depth guarantees that an existing
  comment is located reliably.
- **Severity enum drift.** `REVIEW.md:88` specifies `suggestion` while
  `scripts/ci/merge_gate.sh:28,271` previously used `low`. The implementing
  pull request updates `merge_gate.sh:28,271` and test fixtures in
  `merge_gate_test.sh` to enforce `suggestion` outright without a transition
  period.
- **Reviewer secret isolation and interim trust.** Reviewer credentials
  currently reside in repository secrets accessible to pull request branch
  workflows. The interim mitigation verifies comment author logins,
  cross-references `reviewed-head` against pull request commit history, and
  validates Actions run provenance via `<!-- run-id:<n> -->`. Residual risk: a
  pull request branch run can name its own run ID; what it cannot forge is the
  run being a main-ref run, which the run-from-main design in #251 and #265
  closes.
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
  reconciles derived labels on each execution, adding required labels and
  removing stale labels while preserving unrelated issue labels such as `hold`
  or `bootstrap`.
- **Serialized execution and job ordering.** The recorder executes inside
  `.github/workflows/merge-gate.yml` in a `record` job preceding `gate` (`gate`
  specifies `needs: record`). Both jobs run under `environment: themis` and
  share `concurrency: group: merge-gate`. Idempotency guards skip execution
  when `github.event.sender.login` is Themis, and skip `PATCH` requests when
  the rendered body matches current comment content, preventing self-trigger
  loops.
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
- The single post-merge follow-up issue filing and closing the ledger upon pull
  request merge (#148).

## Operator decisions

None are required by this spec. For the record: the implementation dispatch
goes to the odyssey rung after the plan, and no secret or GitHub App changes
are required.

Open questions: none
