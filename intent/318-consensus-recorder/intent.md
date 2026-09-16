# Intent: Anchored Verdict Marker Parsing and Loud Declines in Consensus Recorder

**Issue:** #318 · **Author:** athena (evekhm-athena-app[bot]) · **Status:** Accepted

> [!NOTE]
> Notation: Every marker in this document is written with bracketed notation (such as `[review-verdict:<reviewer>:<verdict>]` or `[reviewed-head:<sha>]`) where real comments emit HTML comment syntax. This ensures the document cannot be parsed as live verdict input by existing unanchored recorder parsers.

## Problem

The consensus recorder (`scripts/ci/review_recorder.py`) parses structured review verdict blocks and finding rows using unanchored, non-greedy regular expressions over comment bodies. In production on pull request #316, this unanchored matching caused comment poisoning and silent finding drops:

1. **Unanchored verdict block matching**: The recorder matches review verdict blocks across comments using a non-greedy scan from the first review-verdict marker to the first review-verdict-end marker. In pull request #316, a review comment quoted text from `intent/312-a-completed-runner/intent.md` containing an example Atlas clean verdict block. The reviewer (`argus`, posting as `evekhm-argus-app[bot]`) then appended its own authentic findings block further down in the same comment. The non-greedy scan matched from the quoted opening marker to the quoter closing marker, attributed the block to Atlas, detected an author login mismatch (`evekhm-argus-app[bot]` != `evekhm-atlas-app[bot]`), and refused the combined block. The real findings reported by Argus were swallowed completely.
2. **Forged clean verdicts via quoted prose**: When quoted prose contains a clean verdict marker naming the commenting reviewer, the author check succeeds. The recorder admits the quoted clean block and ignores real findings located later in the comment.
3. **Unanchored inner markers and directives**: Finding lines (`[finding:...]`), failure scenario markers (`[failure-scenario:...]`), head markers (`[reviewed-head:...]`), and maintainer retier commands (`@argus retier ...`) are evaluated without line-start anchors. They match inside markdown code fences, indented code blocks, and blockquotes.
4. **Silent declines and missing audit indicators**: When the recorder declines a verdict block due to author mismatch, missing commit SHA, or invalid syntax, the failure is noted in internal audit notes or omitted from the consensus ledger. The merge gate (`scripts/ci/merge_gate.sh`) observes an empty or stale ledger and cannot distinguish between a pending review and a declined review.
5. **Ledger-blindness across review runs**: Intermittent run ID failures (such as `run-id:0` on interactive runs in pull request #317) cause findings to be refused during provenance checks. Review comments post findings on the pull request while the consensus ledger records zero findings, creating a ledger-blindness condition where the gate declines on stale head state without identifying the dropped rows.
6. **Presence of live markers in tracked repository artifacts**: Tracked documentation files contain raw, unescaped verdict markers. Reviewers quoting tracked markdown files inadvertently introduce active markers into review threads.

## Proposed outcome

1. **Anchor marker admission to line start outside code blocks**:
   - Every marker (`review-verdict`, `reviewed-head`, `run-id`, `round`, `finding`, `failure-scenario`, `review-verdict-end`) must begin at line start (`^[marker]$`), with optional horizontal whitespace.
   - All marker matchers must ignore content inside fenced code blocks (triple backticks or tildes), indented code blocks, and blockquoted lines (`> `).
2. **Bind block to author before matching**:
   - The recorder determines the expected reviewer name directly from the comment author login (`evekhm-argus-app[bot]` maps to `argus`; `evekhm-atlas-app[bot]` maps to `atlas`).
   - The parser searches only for opening markers matching the authenticated author. A quoted marker naming a different reviewer cannot open a verdict block.
3. **Make every decline loud**:
   - Differentiate between "no review filed" and "review filed but declined" across the ledger and merge gate.
   - Emit machine-readable refusal markers in the consensus block and visible notes under `#### Notes` for every declined block (author mismatch, unparseable markers, missing head, provenance rejection).
   - Implement a per-pull-request row comparison at the merge gate or recorder: detect any posted review finding row lacking a ledger counterpart, preventing silent ledger-blindness events.
4. **Sweep siblings of the class**:
   - Audit and anchor all marker matchers and directive scanners across `scripts/ci/**` and `scripts/ops/**`.
   - Apply line anchoring and code-fence exclusion to the maintainer retier verb parser (`scripts/ci/review_recorder.py:278`), resolving the directive injection vulnerability reported in #381.
5. **Enforce marker ban in tracked repository artifacts**:
   - Add a deterministic check (integrated into `scripts/ci/sanitize_check.sh` or a dedicated gate) verifying that tracked repository files contain zero unneutralized live verdict markers outside of test fixtures and allowlists.

## Affected users and systems

- **Autonomous Reviewers (`argus`, `atlas`)**: Review comments can quote repository artifacts, previous reviews, or documentation examples without poisoning verdict blocks.
- **Themis Consensus Recorder (`scripts/ci/review_recorder.py`, `scripts/ci/review_recorder.sh`)**: Accurately parses verdict blocks and emits explicit refusal indicators for invalid or unanchored blocks.
- **Merge Gate (`scripts/ci/merge_gate.sh`)**: Identifies ledger-blindness events and surfaces concrete diagnostics for declined reviews.
- **Posting Infrastructure (`scripts/ops/post.sh`)**: Enforces clean marker structure and provenance preservation during review publication.
- **Sanitization Gate (`scripts/ci/sanitize_check.sh`)**: Rejects live verdict markers in tracked documentation.
- **Living Specification (`docs/SPEC.md`)**: Documents anchored parsing rules, code block exclusion, author binding, and refusal diagnostics under `### review.policy` and `### review.recorder`.
- **Contract Test Suite (`scripts/ci/tests/review_recorder_test.sh`, `scripts/ci/tests/merge_gate_test.sh`, `scripts/ci/tests/sanitize_check_test.sh`)**: Tests verifying code block exclusion, author binding, unanchored rejection, and loud decline reporting.

## Constraints

- **Autonomous authority limits**: Athena authors only `intent/**`. Code, workflow edits, and test implementations belong to Daedalus (plan) and Odyssey (implementation) in subsequent lifecycle stages.
- **Fail-closed security posture**: Any ambiguous or malformed verdict block must fail closed with an explicit refusal. Ambiguous blocks are barred from admission as clean and must not be silently discarded.
- **Provenance verification preservation**: The Actions API run ID provenance checks established in #267 D3 and #353 D1 remain active and mandatory.
- **Preservation of conversational comments**: Human maintainer comments and discussions without structured verdict blocks must continue to pass unparsed without disrupting consensus ledger generation.
- **Documentation format safety**: All markdown examples of review markers in issues, pull requests, and documentation must use bracketed or escaped forms to prevent recursive parser triggers.

## Relationships

- **refines #267 (D2, D3, D5):** Refines reviewer verdict block marker syntax, admission parsing, author binding, and refusal recording in the consensus recorder.
- **refines #291 (D8):** Refines parser implementations in the extracted Python recorder engine (`scripts/ci/review_recorder.py`).
- **refines #353 (D4, D5, D7):** Refines refusal emission and ledger diagnostics so author mismatches, missing reviewed-heads, and row discrepancies are visibly exposed.
- **refines #381 (unanchored retier verb):** Refines directive matching and code-fence exclusion for maintainer retier overrides in `review_recorder.py`.
- **refines #137 (unanchored marker prior art):** Refines prior art on strict marker line-start anchoring across repository scripts.
- **depends on #353 (provenance injection):** Depends on #353 infrastructure-managed run-id injection and refusal marker framework.

## Open questions

1. **Pre-processing Sanitization versus Regex Context Scanning**:
   - **Reading 1**: The consensus recorder strips all fenced code blocks, indented code blocks, and blockquotes from the comment body in an initial sanitization pass, running subsequent marker parsing on the stripped text.
   - **Reading 2**: The consensus recorder preserves the comment body and evaluates line positions, matching markers line-by-line while tracking fence state toggles.
   - **Differing case**: A reviewer comment contains a valid verdict block indented by four spaces within a nested markdown list. Reading 1 strips the indented block as code and rejects the verdict. Reading 2 recognizes that the indentation belongs to list structure outside a code fence and accepts the verdict.

2. **Placement of the Tracked Artifact Marker Check**:
   - **Reading 1**: Integrate the marker check directly into `scripts/ci/sanitize_check.sh` alongside checks for secrets, home paths, and vendor names, failing `ci-gates.yml` on any tracked file containing live markers outside test fixtures.
   - **Reading 2**: Create a dedicated check script (`scripts/ci/marker_check.sh`) invoked independently by `ci-gates.yml`.
   - **Differing case**: An operator runs `bash scripts/ci/sanitize_check.sh` locally to check for secret leaks before committing. Under Reading 1, the run fails if an intent document contains an unescaped marker. Under Reading 2, the run passes and secret validation succeeds.

3. **Detection of Ledger-Blindness at the Merge Gate**:
   - **Reading 1**: `merge_gate.sh` paginates pull request comments to extract all posted finding rows from accepted reviewer runs at the current head, comparing the set of posted rows against the ledger rows.
   - **Reading 2**: `review_recorder.py` compares parsed finding counts against admitted ledger rows during ledger creation, emitting a dedicated machine-readable marker `[refused-verdict:<reviewer>:<head>:ledger-blindness]` if posted rows were declined or lost.
   - **Differing case**: `merge_gate.sh` runs under dry-run mode or limited GitHub API rate limits. Under Reading 1, the gate issues additional GitHub API requests to fetch comment bodies. Under Reading 2, the gate inspects only the existing consensus ledger comment payload.

## Non-goals

- Modifying reviewer prompt instructions or model weights under `personas/**`.
- Altering the four-tier severity enum (`security`, `high`, `normal`, `suggestion`).
- Modifying GitHub Actions runner dispatch workflows in `.github/workflows/unattended.yml`.
- Retroactively altering historical pull request consensus ledger comments on merged pull requests.
