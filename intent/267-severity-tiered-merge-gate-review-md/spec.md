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
| D1 | **Recorder execution context and placement.** The recorder lives at `scripts/ci/review_recorder.sh` and runs in `.github/workflows/merge-gate.yml` inside a dedicated `record` job that executes prior to the `gate` job (`gate` declares `needs: record`). Both jobs run under `environment: themis` and share `concurrency: group: merge-gate`. The workflow triggers on events: `pull_request`, `issue_comment` (types: `[created]`), `check_suite` (types: `[completed]`), `status`, and `workflow_dispatch`. The `issue_comment` trigger retains `types: [created]` without adding `edited`. The `record` job runs under condition `if: github.event_name != 'pull_request' && (github.event_name != 'issue_comment' || github.event.issue.pull_request)`, while `evaluate` runs on `pull_request` events read-only with default tokens and `DRY_RUN=1`. Quoting `merge-gate.yml:6-15`: "a same-repo pull_request run executes the workflow file from the pull request's head, so nothing that can write or mint the merge actor's token may run on that trigger." On `check_suite` and `status` push events, the ledger is re-derived; markers advance and are never removed. The `record` job skips execution entirely when `github.event.sender.login` is the Themis App login (`evekhm-themis-app[bot]`). It skips the `PATCH` API request when the newly rendered ledger body equals the existing comment body byte for byte. When handling refused verdict blocks, the `record` job logs the refusal, appends an audit note `[refused: <id>: <reason>]` below the ledger table without creating rows, and exits 0 so that the `gate` job executes its evaluation and escalation logic. The recorder performs writes directly via `gh api` using the minted Themis GitHub App token; this supersedes the constraint in `intent.md:76` because `scripts/ops/post.sh` requires persona YAML definitions (`post.sh:94-98`, `170-179`) whereas Themis is an infrastructure system identity. `.github/workflows/unattended.yml` and `.github/workflows/lifecycle.yml` are unchanged. | Placing `record` before `gate` with explicit job dependencies ensures sequential execution on review events, ensuring ledger state is recorded before merge evaluation. Sharing the concurrency group serializes runs across the repository, while idempotency guards prevent recursive or redundant workflow dispatches. Exiting 0 on refused inputs ensures downstream merge-gate evaluations such as round-cap escalations are never suppressed. |
| D2 | **Reviewer verdict output contract.** Reviewers emit a structured verdict block in their pull request review comments: <br>`<!-- review-verdict:<reviewer>:<verdict> -->`<br>`<!-- reviewed-head:<full-oid> -->`<br>`<!-- run-id:<n> -->`<br>`<!-- round:<n> -->`<br>`<!-- finding:<id>:<severity>:<status>:<peer> -->`<br>`<!-- failure-scenario:<id> -->`<br>`<!-- review-verdict-end -->`<br>alongside human-readable review tables, where `<verdict>` is `clean` or `findings`. The `<id>` field carries `@<Dn>` when citing a spec Decision (such as `R1-1@D4`) or `@none` when uncited, matching `REVIEW.md:290-305`. Each `high` finding must be immediately accompanied by its sibling marker `<!-- failure-scenario:<id> -->`. The finding line matches regex `^<!-- finding:([A-Za-z0-9@-]+):(security\|high\|normal\|suggestion):(open\|fixed\|withdrawn):(pending\|agree\|dispute\|none) -->$`. The reviewer block provides `<!-- reviewed-head:<full-oid> -->`; the recorder qualifies this per reviewer when generating the ledger (`<!-- reviewed-head:argus:<40-hex> -->`, `<!-- reviewed-head:atlas:<40-hex> -->`) matching `scripts/ci/merge_gate.sh:268-269`. Reviewers update `REVIEW.md` and `personas/skills/review-protocol.md` to produce this block. Comments lacking this block are ignored. The recorder validates that `<full-oid>` exists in pull request commit history; verdicts referencing commits absent from the commit list are rejected. Evaluating whether a `high` finding belongs to the closed list in `REVIEW.md:102-111` is a reviewer protocol duty defined in `personas/skills/review-protocol.md`, outside parser responsibility. | Structured comment blocks allow deterministic parsing without NLP heuristics. Ignoring comments without markers preserves conversational thread comments and historical reviews. Checking the reviewed commit against pull request history prevents reviewers from recording findings against foreign commits. Placing the hyphen last in the ID character class prevents invalid range interpretation across shell tools. |
| D3 | **Reviewer identity and interim trust model.** The recorder verifies reviewer provenance using check-run and workflow-run validation. A verdict block is accepted only when the comment author is an authorized reviewer App (`evekhm-argus-app[bot]`, `evekhm-atlas-app[bot]`), `reviewed-head` exists in pull request commits, and the referenced `<!-- run-id:<n> -->` matches an authentic workflow run verified via `GET /repos/<repo>/actions/runs/<run_id>` meeting four predicates: `head_sha` equals the block's reviewed-head, workflow path is `.github/workflows/unattended.yml`, `head_repository.full_name` equals this repository, and `event` is in `{pull_request, workflow_dispatch}`. The recorder performs no conclusion check at `issue_comment` time because the reviewer run is in progress and posting from within the executing job. On subsequent `check_suite: completed` re-derivation, a cited run whose conclusion is `failure` or `cancelled` has its markers removed from the ledger, with the table recording `[run <n> ended <conclusion>; verdict withdrawn]`. A same-repo pull request branch run of `unattended.yml` satisfies all four provenance predicates; the run-from-main architecture in #251 and #265 closes this residual risk. | Validating the Actions run ID, head SHA, workflow path, repo ownership, and admitted triggers provides machine-checked provenance preventing forged review comments from unassociated runs. Deferring terminal conclusion checks accommodates in-flight comment posting while retaining retrospective invalidation for crashed or cancelled runs. Formal secret isolation moves to main-only Environments under #251 and #265. |
| D4 | **Single in-place consensus ledger comment and emitted wire format.** The consensus ledger exists as exactly one pull request comment authored by Themis. The recorder finds this comment by paginating pull request comments to exhaustive depth. If absent, it creates the comment via `POST /repos/<repo>/issues/<pr>/comments`. If present, it updates the comment via `PATCH /repos/<repo>/issues/comments/<id>`. The emitted comment body matches `scripts/ci/tests/merge_gate_test.sh:236-247` and `scripts/ci/merge_gate.sh:265-271` byte for byte: <br>`### Findings ledger for #<pr>`<br>`<!-- consensus-ledger:<pr> -->`<br>`<!-- assigned:<comma-separated reviewers> -->`<br>`<!-- reviewed-head:argus:<40-hex> -->`<br>`<!-- reviewed-head:atlas:<40-hex> -->`<br>`<!-- ledger-row:<id>:<severity>:<status>:<peer> -->`<br>`<!-- consensus-ledger-end -->`<br>followed by the human-readable markdown table. The `<!-- assigned:<comma-separated reviewers> -->` marker appears immediately after the `consensus-ledger:<pr>` line; its value derives from the assignment output of `unattended.yml`'s resolve step once #265 lands, and defaults to `argus,atlas` until then. The `scripts/ci/merge_gate.sh` reader for this assigned marker belongs to #265's implement rung. The recorder retains each reviewer's last accepted head marker whatever the current head is. It never deletes a marker, advancing a reviewer's head marker only when a newer verdict from that reviewer is accepted; `scripts/ci/merge_gate.sh` evaluates carry-forward rules under #64 D7. Finding IDs carry `@<Dn>` when cited in the review. | In-place updates preserve comment identity while ensuring downstream parsers read the exact markers and ledger rows required by the merge gate. Emitting the assigned marker prepares the ledger for single-reviewer pull request gating under #265. Retaining historical head markers provides the exact inputs required by the merge gate's Atlas carry-forward logic. |
| D5 | **Authoritative four-tier enum, loud refusal, and high demotion.** The authoritative severity enum is `security`, `high`, `normal`, `suggestion`. This replaces `low` outright in `scripts/ci/merge_gate.sh:28,271` and `scripts/ci/tests/merge_gate_test.sh` in the implementing pull request without a transition period. The regular expression in `scripts/ci/merge_gate.sh:271` is updated to `^<!-- ledger-row:([A-Za-z0-9@-]+:(security\|high\|normal\|suggestion):(open\|fixed\|withdrawn):(pending\|agree\|dispute\|none)) -->$`. Any finding specifying a severity outside these four values fails validation loudly: the recorder logs `finding <id>: severity <x> is not one of security\|high\|normal\|suggestion`, appends table note `[refused: <id>: invalid severity <x>]`, creates no ledger row, and exits 0 so that `gate` runs. Any finding marked `high` that lacks a sibling `<!-- failure-scenario:<id> -->` marker is demoted by the recorder to `normal` on the ledger row, with an explanatory note added to the ledger table: `[demoted from high: missing failure_scenario marker]`. | Settling on `suggestion` eliminates naming drift. Placing the hyphen last in `[A-Za-z0-9@-]` ensures valid syntax across `sed -nE` and shell pattern matchers. Logging refusals while exiting 0 ensures that malformed reviewer inputs do not suppress merge-gate execution or round-cap escalations. Mechanical demotion enforces concrete failure scenarios without manual intervention. |
| D6 | **Round derivation and admissibility funnel.** The recorder extracts the review round number from `<!-- round:<n> -->` and verifies it against prior rounds. In Round 1, all severity tiers are admissible. In Rounds 2 and 3, new blocking findings are governed by the admissibility rule quoting `REVIEW.md:144-145` ("scope is the open blocking rows plus the delta since the last reviewed head; NEW findings are admissible at security or high only"); new non-blocking observations are governed by quoting `REVIEW.md:168-170` ("Rounds 2 and 3 are verification rounds. Any other observation a reviewer cannot resist making is filed as `normal`: recorded, no verdict owed, and it neither opens nor extends a round"), creating tracking rows that owe no verdict and do not extend the round. Past Round 3, quoting `REVIEW.md:171-173` ("Past round 3 reviewers post verification comments only. The single exception is a new `security` finding, which may always be filed. The recorder demotes any other post-cap filing to `normal`"), new `security` findings are admitted while any other post-cap finding is recorded as `normal` with no verdict owed. | The round funnel prevents late non-critical findings from prolonging review cycles indefinitely while preserving visibility for non-blocking observations. Quoting REVIEW.md directly aligns row creation with post-merge issue tracking requirements. |
| D7 | **Peer consensus column and status transitions.** Argus findings use namespace `R<round>-<n>`; Atlas findings use namespace `AT-R<round>-<n>`. Peer states are `pending`, `agree`, `dispute`, `none`. `security` rows initialize with `peer=pending` and require explicit peer concurrence to reach `peer=agree`. In accordance with `REVIEW.md:258-260`, security findings require dual agreement twice: once on finding existence and once on fix verification. `high` rows carry `peer=none` unless explicitly disputed. An explicit dispute on any blocking row sets `peer=dispute`. Finding status transitions to `fixed` only when verified by the discovering reviewer on a newer commit, or to `withdrawn` when retracted by that reviewer. Pull request authors cannot close findings through author assertions. | Requiring two-party verification for security findings protects critical trust paths. Restricting finding resolution to the reporting reviewer prevents unilateral dismissal by authors. |
| D8 | **Label derivation by Themis and round counter ownership.** The recorder derives pull request labels from ledger state and updates them using the Themis token, adhering to the taxonomy in issue #4 (`scripts/setup/issues/04-label-taxonomy.md`): `argus:findings` (open blocking rows exist), `argus:suggestions` (open non-blocking rows exist), `consensus:agreed` (no open security rows awaiting peer, all security agreed, no dispute), `consensus:pending` (open security row awaiting peer verdict), `consensus:disputed` (dispute on any blocking row), `review:merge-ready` (no open blocking rows, consensus agreed, reviewed head matches pull request head), `review:verifying` (open blocking rows exist and pull request head is newer than reviewed head), and the round counter `review:1`, `review:2`, `review:3` (set from highest accepted round at head; exactly one present). Exact label color hex codes and descriptions from `scripts/setup/issues/04-label-taxonomy.md` are documented for the Build stage (`plan.md`, AT-R1-5). A ledger lacking a head marker earns neither head-pinned label, and a failed head probe freezes both per `REVIEW.md:346-348`. `status:review-stuck` remains written by `scripts/ci/escalate.sh` when `scripts/ci/merge_gate.sh:442-451` triggers on `review:3`; this completes the hand-off from `scripts/ci/lifecycle_advance.sh:56-57`. Labels are provisioned by `scripts/setup/bootstrap_tracker.sh --labels-only`. | Managing the round counter in the recorder ensures the merge gate's round-cap escalation operates as designed. Decoupling visual indicators from merge evaluation ensures the gate inspects ledger evidence directly. |
| D9 | **Owner retier verb.** Repository maintainers can override finding severities by posting `@argus retier <id> <severity>` or `@atlas retier <id> <severity>`. The recorder processes retier commands by checking that commenter `author_association` is one of `OWNER`, `MEMBER`, or `COLLABORATOR` (addressing AT-R1-2 by avoiding `administration:read` permissions under Themis) or validating permissions via `gh api repos/<repo>/collaborators/<user>/permission`. Commands from bot accounts or unauthorized users are ignored. An accepted retier command updates row severity, recalculates derived labels, and annotates the ledger table with `[retiered to <severity> by @<user>]`. | Human authority retains final arbitration over disputed or misclassified findings. Validating commenter association directly from the payload prevents permission escalation while respecting minimal token privileges. |
| D10 | **Treatment of unformatted comments and legacy reviews.** Comments lacking structured verdict markers are ignored by the recorder. Pull requests containing historical reviews without marker blocks (such as PR #280 and PR #283) remain in the state lacking a consensus ledger until a reviewer posts a compliant verdict block or a fresh review cycle runs. | Permitting non-compliant comments to pass unparsed preserves unstructured conversational comments and prevents unexpected build failures on older pull requests. |
| D11 | **Disposition of issue #238 gates.** Issue #238 retains ownership of G1 (pre-dispatch diff verification of repair claims) and G2 (convergence rate escalation). The recorder provides the ledger rows, round tracking, and open blocking tallies that G2 evaluates. G1 operates as an intake gate in `.github/workflows/unattended.yml`, while G2 operates within `scripts/ci/escalate.sh`. | Preserving G1 and G2 in issue #238 avoids overloading the recorder script and maintains modular responsibility between review execution, state recording, and escalation. |
| D12 | **Implementation scope boundary.** The implementing pull request may touch `scripts/ci/review_recorder.sh`, `scripts/ci/tests/review_recorder_test.sh`, `.github/workflows/merge-gate.yml`, `REVIEW.md`, `personas/skills/review-protocol.md`, `scripts/ci/merge_gate.sh`, `scripts/ci/tests/merge_gate_test.sh`, `scripts/setup/bootstrap_tracker.sh`, `scripts/setup/issues/04-label-taxonomy.md`, `docs/SPEC.md`, and compiled persona targets under `.claude/**` and `.agents/**` generated from `review-protocol.md` (AT-R1-3). It may not touch `.github/workflows/unattended.yml`, `.github/workflows/lifecycle.yml`, `scripts/ops/post.sh`, `personas/**` (outside `review-protocol.md`), `scripts/ci/escalate.sh`, or `scripts/ci/lifecycle_advance.sh`. | Clean scope boundaries prevent merge conflicts with concurrent issues and protect autonomous lifecycle advance workflows from unintended edits. Admitting compiled persona artifacts allows implementation changes to satisfy compiler drift checks. |

## Acceptance

- **AT-1 (D1)** Run `bash scripts/ci/tests/review_recorder_test.sh`: passes with
  exit code 0, exercising parser execution, idempotency short-circuiting, and
  API calls against a hermetic test stub.
- **AT-2 (D2)** Run `bash scripts/ci/tests/review_recorder_test.sh -k test_marker_parsing`:
  passes with exit code 0, verifying extraction of verdict, run-id, round,
  finding lines (including Decision-ID `@<Dn>` tags with character class
  `[A-Za-z0-9@-]`), and sibling `failure-scenario` markers.
- **AT-3 (D2, D3)** Run `bash scripts/ci/tests/review_recorder_test.sh -k test_provenance_validation`:
  passes with exit code 0, confirming acceptance of matching App logins, commit
  SHAs, repo ownership, `pull_request` events, and null in-progress conclusion at
  comment time.
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
  in the job log, appends ledger table note `[refused: <id>: invalid severity <x>]`,
  creates no ledger row, and exits 0.
- **AT-7 (D6)** Run `bash scripts/ci/tests/review_recorder_test.sh -k test_round_funnel`:
  passes with exit code 0, confirming that new non-blocking findings in Round 2
  or 3 are recorded as `normal` rows owing no verdict, and new non-security
  findings beyond Round 3 do not create blocking rows.
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
- **AT-11 (D5)** Run `printf '%s\n' '<!-- ledger-row:R1-1@D4:high:open:none -->' | sed -nE 's/^<!-- ledger-row:([A-Za-z0-9@-]+:(security|high|normal|suggestion):(open|fixed|withdrawn):(pending|agree|dispute|none)) -->$/OK[\1]/p'`:
  exits 0 and outputs `OK[R1-1@D4:high:open:none]`; run `bash scripts/ci/tests/merge_gate_test.sh`:
  passes with exit code 0, confirming that `merge_gate.sh` processes consensus
  ledger fixtures using Decision-tagged IDs and `suggestion` while rejecting legacy `low`.
- **AT-12 (D8)** Run `bash scripts/setup/bootstrap_tracker.sh --labels-only`:
  exits 0 and outputs provisioning confirmation for all seven review and
  consensus labels (`argus:findings`, `argus:suggestions`, `consensus:agreed`,
  `consensus:pending`, `consensus:disputed`, `review:merge-ready`,
  `review:verifying`).
- **AT-13 (D4, D5)** Run `bash scripts/ci/tests/review_recorder_test.sh -k test_merge_gate_round_trip`:
  passes with exit code 0, asserting that a recorder-emitted ledger with
  Decision-tagged IDs (such as `R1-1@D4`) parses through `sed -nE` at
  `scripts/ci/merge_gate.sh:271` emitting `OK[R1-1@D4:high:open:none]` under
  pattern replacement, and evaluates conjuncts 3, 4, 5, and 11 as true under its test stub.
- **AT-14 (D4)** Live run: one `Merge Gate` workflow execution on a pull request
  with both accepted reviewer verdict blocks evaluating conjuncts 3, 4, 5, and 11
  true, cited by Actions run ID, listed under NOT RUN until #64 acceptance 20.
- **AT-15 (D12)** Run `bash scripts/ci/spec_check.sh origin/main && bash scripts/ci/sanitize_check.sh`:
  exits 0 with no diff errors or sanitized term violations.
- **AT-16 (D4, D7)** Run `bash scripts/ci/tests/review_recorder_test.sh -k test_atlas_carry_forward`:
  passes with exit code 0; with Argus accepted at oid2 and Atlas accepted at oid1,
  the emitted ledger fed to `scripts/ci/merge_gate.sh` under its stub yields
  conjunct 3 true through the carry-forward branch with WHY[3] text
  `argus at $HEAD, atlas carries forward from $ATLAS_HEAD (D7)`.
- **AT-17 (D3)** Run `bash scripts/ci/tests/review_recorder_test.sh -k test_provenance_workflow_dispatch`:
  passes with exit code 0, confirming acceptance of a reviewer verdict block
  citing an authentic `unattended.yml` run triggered by `workflow_dispatch`.
- **AT-18 (D4)** Run `bash scripts/ci/tests/review_recorder_test.sh -k test_wire_format_assigned`:
  passes with exit code 0, confirming that the consensus ledger fixture in
  `scripts/ci/tests/merge_gate_test.sh:236-247` containing `<!-- assigned:argus,atlas -->`
  parses cleanly under `scripts/ci/merge_gate.sh`, evaluating conjuncts 3, 4, 5,
  and 11 as true.

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
  validates Actions run provenance via `<!-- run-id:<n> -->`. A same-repo
  pull request branch run of `unattended.yml` satisfies all four provenance
  predicates; the run-from-main architecture in #251 and #265 closes this
  residual risk.
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
  share `concurrency: group: merge-gate`. The `record` job runs under condition
  `if: github.event_name != 'pull_request'`, protecting the workflow because,
  quoting `merge-gate.yml:6-15`, "a same-repo pull_request run executes the
  workflow file from the pull request's head, so nothing that can write or
  mint the merge actor's token may run on that trigger." Idempotency guards
  skip execution when `github.event.sender.login` is Themis, and skip `PATCH`
  requests when the rendered body matches current comment content.
- **Comment payload volume.** GitHub issue comments have a size limit of
  65,536 characters. For pull requests with long review histories, the ledger
  table displays open findings and active disputes in detail while compacting
  historical resolved rounds into single summary counts.
- **Head marker retention and Atlas carry-forward.** `scripts/ci/merge_gate.sh:293-305`
  evaluates Atlas carry-forward under #64 D7 when Atlas has not reviewed the
  current head OID. The recorder advances reviewer head markers upon accepted
  verdicts and never removes historical markers on re-derivation, ensuring
  the merge gate receives the exact marker required for carry-forward evaluation.
- **Assigned marker integration.** Emitting `<!-- assigned:<reviewers> -->`
  supports issue #265 D5, enabling single-reviewer pull requests to satisfy
  conjunct 3 and skip conjunct 11 when Atlas is the sole assigned reviewer.
  The merge gate reader for this marker is implemented under #265.

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
