# Spec: two-tier review assignment and per-rung verification

**Issue:** #265 · **Status:** Approved (approval = merge of this PR) ·
**Author:** athena (`evekhm-athena-app[bot]`) ·
**Open questions:** none

## What is being built

The review process splits from "both reviewers read every pull request" into a
two-tier assignment model with a unified per-rung verification checklist. Atlas
runs at the fast tier and reviews every pull request at every rung. Argus
runs at the review tier and joins at the code gate (`status:implementing`), on
trust-bearing paths, on an open `security` row, or upon an explicit `deep-review`
grant.

The verifier stage (#204) is unified into this protocol as a rung-scoped
checklist in `REVIEW.md`, executed by Atlas at every gate and deepened by
Argus wherever assigned.

```text
config/execution.yaml                    # assigned_when block for argus
scripts/ops/execution.py                 # parse and validate assigned_when, context-aware subscribers filtering, grant check, diff rules
scripts/ops/tests/execution_test.sh      # hermetic unit and contract tests for assignment, --check, --check-grant, --diff-rules
scripts/ops/post.sh                      # trusted label application behind hold re-read, scoped strictly to deep-review
scripts/ops/tests/post_test.sh           # hermetic tests for post.sh --add-label deep-review and refusal of other labels
scripts/ci/merge_gate.sh                 # scoped strictly to conjuncts (3) and (11) reading assigned set
scripts/ci/tests/merge_gate_test.sh      # hermetic tests for single-reviewer and dual-reviewer consensus
.github/workflows/unattended.yml         # ready_for_review trigger, draft skip, assignment and deep review resolution
.github/workflows/ci-gates.yml           # deterministic evaluation for DEEP-1 and DEEP-2
scripts/setup/bootstrap_tracker.sh       # deep-review label provisioning
scripts/setup/issues/04-label-taxonomy.md # deep-review label documentation
personas/skills/deep-review.md           # DEEP-1..DEEP-7 criteria and persona grant rules
personas/skills/review-protocol.md       # citation to verifier checklist in REVIEW.md
personas/*.yaml                          # declare deep-review.md skill where authorized
REVIEW.md                                # line 8 rewrite, comment-only exception for deep-review, verifier checklist, deep-review grant
docs/SPEC.md                             # living spec updates for execution.placement and review.policy
```

`personas/lifecycle.json`, `scripts/ops/work.sh`, `scripts/ops/claim.sh`,
`intent/204-verifier-stage/**`, and `intent/64-autonomous-loop/**` are excluded
from changes (D8).

## Decisions

| ID | Decision | Rationale |
|----|----------|-----------|
| D1 | **Machine-readable assignment shape in `config/execution.yaml`.** A binding with `trigger: repo-event` and `events: [pull_request]` gains an optional `assigned_when` mapping. `BINDING_KEYS` in `scripts/ops/execution.py` expands to `{"trigger", "events", "placement", "max_cost_usd", "assigned_when"}`. For `atlas`, `assigned_when` is omitted: Atlas is assigned unconditionally to all `pull_request` events. For `argus`, `assigned_when` specifies four disjunctive categories (OR between categories): `status_labels` (`[status:implementing]`), `paths` (`[".github/workflows/**", "scripts/auth/**", "scripts/ops/post.sh", "scripts/ops/work.sh", "scripts/ci/**", "scripts/sync_agents.py", "scripts/setup/**", "personas/**", "config/**", "REVIEW.md", "AGENTS.md"]`), `labels` (`[deep-review]`), and `open_ledger_tiers` (`[security]`). Within each category, any match satisfies that condition. When `--status-label` is missing, empty, unrecognized, or the linked issue carries no `status:*` label, `execution.py` fails closed: no assignment shortcut is granted and Argus is assigned alongside Atlas. The CLI called by workflow steps is: (a) subscribers mode: `python3 scripts/ops/execution.py --subscribers pull_request [--status-label <label>] [--paths <p1> ... \| --paths-file <file>] [--labels <l1> ...] [--open-ledger <t1> ...] [--action <action>] [--draft]`; (b) grant check mode: `python3 scripts/ops/execution.py --check-grant --pr <n> --rung <rung> [--existing-grants <g1> ...]`; (c) diff rules evaluation mode: `python3 scripts/ops/execution.py --diff-rules [--lines <n>] [--files <count>] [--paths <p1> ... \| --paths-file <file>]`. `--check` validates: `assigned_when` is allowed only on `repo-event` bindings with `pull_request` in `events`; only the four allowed sub-keys may appear; `status_labels` must contain valid stage labels from `personas/lifecycle.json`; `paths` and `labels` must be non-empty string lists; `open_ledger_tiers` must contain valid severity tiers from `REVIEW.md`. | Preserves `execution.py`'s monopoly as the single YAML parser (#25 D2) and its zero-dependency invariant (`pyyaml` only, no network, no `gh`). Evaluates entirely hermetically in unit tests and in CI. Disjunctive evaluation matches the intent's four independent entry points for Argus. Unconditional omission for Atlas enforces "Atlas reads every PR at every rung" without redundant configuration. Fail-closed rung resolution ensures no PR bypasses code gate review through unconfigured or missing rung lookups. Extending CLI enumeration with `--check-grant` and `--diff-rules` keeps all grant check and diff evaluation logic in the single parser. |
| D2 | **Synchronize gating rule, draft skip, and OQ1/OQ2 resolution in `unattended.yml`.** `.github/workflows/unattended.yml` configures `on.pull_request.types: [opened, synchronize, reopened, ready_for_review, labeled]`. Draft PRs skip review dispatch entirely: when `github.event.pull_request.draft == true`, the `resolve` job emits an empty matrix, dispatching zero personas. On `synchronize`, a reviewer is dispatched if and only if: (a) the reviewer is assigned to the PR under D1; AND (b) that reviewer has an open blocking row (`security` or `high`) on the PR, or `deep-review` was applied on the PR since their last review round. **OQ1 resolution (fail-closed rung lookup):** `unattended.yml` resolves the linked issue via the PR head branch `<actor>/<n>-<slug>` (and `Refs #n` in PR body, using `scripts/ci/lifecycle_advance.sh` logic), and reads its `status:*` label via GitHub API (`gh api repos/$GITHUB_REPO/issues/$ISSUE`). If the branch does not resolve to an issue, or the issue carries no `status:*` label, or multiple status labels, or API query fails, rung resolution fails closed: `--status-label` is omitted, the resolve step logs the notice `Rung resolution failed closed: <reason>; assigning all reviewers`, and both reviewers are dispatched. **OQ2 resolution:** live suppression of `synchronize` runs based on open blocking rows is deferred to the landing of the structured recorder (#8/#9) on main. Until recorder lands, `synchronize` on non-draft PRs dispatches all reviewers assigned to the PR under D1. In `scripts/ops/tests/execution_test.sh`, the contract is implemented and hermetically tested using simulated ledger inputs passed via `--open-ledger`. | PR comments prior to recorder (#8/#9) are unstructured LLM markdown prose lacking schema validation (REVIEW.md:441-445). Regex scraping across free-form LLM prose risks false negatives that silently drop required verification reviews and stall merges. Deferring live suppression to recorder #8/#9 while enforcing D1 assignment filters on `synchronize` immediately cuts non-code PR costs safely. Making rung lookup mandatory and fail-closed prevents unlinked or mislabeled PRs from bypassing Argus. |
| D3 | **`deep-review` label provisioning and lifecycle.** `scripts/setup/bootstrap_tracker.sh` provisions `deep-review` under `--labels-only` and full runs: `ensure_label "deep-review" "5319E7" "Deep-review grant: triggers a full Argus review round out-of-band"`. Documented in `scripts/setup/issues/04-label-taxonomy.md`. `.github/workflows/unattended.yml` listens for `pull_request.types` including `labeled` (cited from D2); when `github.event.label.name == 'deep-review'`, it resolves and dispatches Argus. Authorized grantors: repository administrators (via GitHub UI/API) and persona App identities (`daedalus`, `odyssey`, `atlas`, `argus`, `cassandra`) via `scripts/ops/post.sh --add-label deep-review`. `scripts/ops/post.sh` gains `--add-label <label>` behind immediate hold verification. The `--add-label` flag is restricted strictly to the literal label `deep-review` on a pull request. Passing any other label value or targeting an issue exits with code 2 and prints `post.sh: --add-label accepts only deep-review on a pull request`. An application by any other identity is refused: the label is removed and an explanation posted. When Argus is dispatched under the grant, `deep-review` is removed immediately so a standing label cannot re-arm the loop. If a session halts before posting a review (for example crossing `max_cost_usd`), the recovery path is an explicit operator action: an administrator re-applies `deep-review` (admin grants bypass the per-rung persona limit) or triggers a manual deep dispatch. **Limit: at most one persona grant per PR per rung.** Manual deep dispatch (`workflow_dispatch`) is an unmetered out-of-band path for operators and repository administrators: it does not consume the rung's single persona `deep-review` label allocation. Duplicate grant verification is evaluated via `python3 scripts/ops/execution.py --check-grant --pr <n> --rung <rung> [--existing-grants ...]`. If an actor attempts to apply a second persona grant on the same PR while on the same rung, the label is removed immediately and the following refusal comment posted: `Refused: PR #<n> already received a deep-review grant on the '<rung>' rung. Policy allows at most one deep-review grant per PR per rung (REVIEW.md, #265). Escalating to human.` | Idempotent label setup follows issue #4 taxonomy. App identities need the grant to escalate tricky changes without human intervention. Scoping `--add-label` strictly to `deep-review` on pull requests prevents unauthorized writes to state-machine labels (`hold`, `in-progress`, `status:*`). One-grant-per-rung prevents runaway spend loops from repeated deep rounds. Consuming the label on dispatch prevents re-triggering upon subsequent pushes while operator re-grant provides a recovery hatch. Out-of-band manual dispatch preserves human oversight. |
| D4 | **DEEP-1..DEEP-7 criteria, CI diff step, and `personas/skills/deep-review.md`.** The criteria are carried byte for byte from the merged intent:<br><br>- **DEEP-1, trust-bearing paths.** The diff touches any path in the list under outcome 2. (Also forces Argus's assignment; the deep grant additionally lifts the round-scope cap for that run.)<br>- **DEEP-2, size.** More than 400 changed lines outside `tests/` and generated targets (`.claude/agents/**`, `.agents/agents/**`), or more than 12 files.<br>- **DEEP-3, irreversible or privileged operations.** The change adds or alters code that merges, closes, labels, deletes, force-pushes, mints or handles a credential, or writes outside the repository (GitHub API writes, cloud calls).<br>- **DEEP-4, plan deviation or spec-changing repair.** The PR body carries a "Plan sync" or "Plan deviation" section, or the repair changes a `docs/SPEC.md` entry (#32's second half).<br>- **DEEP-5, escalated tier.** The implementing session recorded a tier escalation for this rung (#107), or the plan marked a task `risk: high`. The architect sets `risk: high` at build time on a task that meets DEEP-3, touches concurrency or state machines (labels, claims, locks), or has no regression suite covering the file it edits.<br>- **DEEP-6, review history.** The PR is at `review:2` or later, or a prior round on this PR had a `security` row.<br>- **DEEP-7, compiler blast radius.** The change alters `scripts/sync_agents.py`, a skill under `personas/skills/`, or anything whose regenerated output touches two or more compiled targets.<br><br>Who applies which: Daedalus at build (DEEP-3, DEEP-5, DEEP-7, written into plan.md so the implement PR inherits it), Odyssey when opening or updating the PR (DEEP-3, DEEP-4, DEEP-5), Atlas after its own round when it finds a case for depth (DEEP-6 and anything it cannot verify at its tier), Cassandra or the advisor on a reopened or repaired PR, CI for DEEP-1 and DEEP-2. Applying the grant is never a defect; a missing grant on a change that met a criterion is a finding.<br><br>The list "under outcome 2" is realized as `config/execution.yaml` `assigned_when.paths` for argus, the single machine-readable list the code evaluates, and D1's two additions from R1-9 (`scripts/sync_agents.py`, `scripts/setup/**`) extend that list; the compiled skill text carries the same sentence so no reader meets a dangling pointer.<br><br>In `.github/workflows/ci-gates.yml`, a step evaluates git diff metrics via `python3 scripts/ops/execution.py --diff-rules`: lines outside tests/generated targets (>400 lines) or files (>12 files) applies `deep-review` (DEEP-2); trust-bearing paths apply `deep-review` and force Argus assignment (DEEP-1). Skill file `personas/skills/deep-review.md` cites #265 and `REVIEW.md`, lists DEEP-1..DEEP-7, and is declared by `daedalus.yaml`, `odyssey.yaml`, `atlas.yaml`, `argus.yaml`, `cassandra.yaml`, compiled via `scripts/sync_agents.py`. | Exact inclusion ensures fidelity to accepted intent. Clarifying the machine-readable path list aligns DEEP-1 with D1 without dangling document pointers. Distributing responsibility across personas anchors depth at the precise lifecycle stage where risk appears. CI handles deterministic diff metrics via `execution.py --diff-rules`, preserving model tokens. A single shared skill file compiled into persona prompts avoids documentation drift. |
| D5 | **Consensus follows assignment and merge gate implementation (interface to #64 merge gate).** In `scripts/ci/merge_gate.sh` (merged on main via PR #257 at d61875c), conjunct (11) (`if [ -n "$ARGUS_HEAD" ]; then C[11]=1; WHY[11]="ledger carries reviewed-head:argus and the head probe read $HEAD"`) and conjunct (3) (`if [ "$ARGUS_HEAD" != "$HEAD" ]; then WHY[3]="argus verdict is at ${ARGUS_HEAD:-none}, head is $HEAD"` and `elif [ "$ATLAS_HEAD" = "$HEAD" ]; then C[3]=1; WHY[3]="argus and atlas both recorded at $HEAD"`) evaluate consensus strictly against Argus. Consensus follows assignment: The merge predicate requires recorded verdicts covering current head OID from assigned reviewers only. Where only Atlas was assigned (non-code, non-trust PRs without deep review), Atlas clean ledger at head + green CI satisfies merge eligibility; Argus's verdict is neither requested nor required. Where both reviewers are assigned, dual sign-off is required. Carry-forward applies to Atlas only on multi-round PRs where Atlas was assigned; condition (v) of #64 D7 ("no deep-review grant is outstanding at this head") holds unchanged. The gate learns the assigned set via a marker in the consensus ledger comment, `<!-- assigned:<reviewers> -->` (for example `<!-- assigned:atlas -->` or `<!-- assigned:argus,atlas -->`), which #267's recorder emits from the assignment output (`python3 scripts/ops/execution.py --subscribers pull_request ...`); cite #267 as writer and this spec as reader. Interface ownership: The #265 implement rung owns updating conjuncts (3) and (11) in `scripts/ci/merge_gate.sh`. In conjunct (3), when the ledger carries `<!-- assigned:atlas -->`, `ATLAS_HEAD = HEAD` satisfies conjunct (3) (`C[3]=1; WHY[3]="atlas recorded at $HEAD (atlas-only assignment)"`). In conjunct (11), when only Atlas is assigned, conjunct (11) is skipped (`C[11]=1; WHY[11]="atlas-only assignment skips argus requirement"`). All other logic in `scripts/ci/merge_gate.sh` remains unchanged. The #265 implement rung provides two hermetic test rows in `scripts/ci/tests/merge_gate_test.sh`: (1) an Atlas-only PR merges on an Atlas-clean ledger at head; (2) a two-reviewer PR still requires both reviewer heads to merge. | Fulfills INTENT.md proposed outcome 4 and closes the ownership gap identified in Argus R2-2. Moving the scoped gate conjuncts into #265 ensures the merge gate implements the assignment semantics without deadlocking non-code PRs, while preserving dual-family consensus on code and trust-bearing paths. Using the recorder's marker provides clean decoupling where #267 writes and #265 reads. Keeping the grant label name `deep-review` leaves condition (v) unchanged. |
| D6 | **Per-rung verifier checklist as ONE Decision with ONE home.** Reconciles #204 D2/D3: the verifier checklist lives in `REVIEW.md` under `## The verification protocol` (exactly once in the repository). `personas/skills/review-protocol.md` references `REVIEW.md` without duplicating checklist steps. The four rung checks from the amendment are carried word for word: <br>• **plan:** "at plan, the intent lost nothing from the issue;" <br>• **design:** "at design, no open question and every acceptance row runnable without a model;" <br>• **build:** "at build, the contract tests fail at the plan's base;" <br>• **implement:** "at implement, the gates re-run and the job log behind every green check says what the check claims." <br>• **code gate additions:** "Argus adds the deep checks where it is assigned (code gate, trust-bearing paths, `deep-review`, open `security` row): mutation-test the tests, re-run the gates, read the full diff." Atlas executes the checklist on every assigned PR; Argus executes the checklist plus deep checks at implement and wherever assigned. | Closes #204 into #265 without creating duplicate personas or competing sources of truth. Consolidating the protocol into `REVIEW.md` respects #204 D2, while referencing from `review-protocol.md` conforms to #204 D3. |
| D7 | **`REVIEW.md` rewrites.** The paragraph at REVIEW.md:8-12 is replaced with: <br>`**In one line:** Atlas reviews every PR at every rung; Argus joins at the code gate, on trust-bearing paths, and on deep-review grants (config/execution.yaml); after that only security and high findings block, security alone needs both reviewers to agree, rounds cap at three; and a human can merge at any time, with anything still open becoming a follow-up issue instead of another round.` <br>The paragraph at REVIEW.md:36-39 is replaced with: <br>`- Both are **comment-only**, with exactly one exception: applying the deep-review grant label through scripts/ops/post.sh --add-label deep-review on a pull request. Neither ever approves, requests changes, merges, closes, pushes, or edits any other label. Authority is a vocabulary: those verbs must not exist in the posting code, and prompt text is not the restraint.` <br>The section heading at REVIEW.md:373 is renamed to `## Asking for more: the deep-review grant`, replacing the em dash with a colon to follow repository style. The section is replaced with: <br>```markdown<br>## Asking for more: the deep-review grant<br><br>The funnel bounds the automatic loop; it must never bound the human.<br>For a review that goes *beyond* the protocol (full depth, full tree,<br>every tier, regardless of round count), the sanctioned paths are:<br><br>- a **`deep-review` label** applied by a persona App identity<br>  (`daedalus`, `odyssey`, `atlas`, `argus`, `cassandra`) through<br>  `scripts/ops/post.sh` under criteria DEEP-1..DEEP-7, or by a<br>  repository admin, verified from the label event timeline and<br>  consumed on use, with a limit of one grant per PR per rung (a second<br>  grant on the same rung is refused and removed);<br>- a **deep manual dispatch** of the review workflow, which needs no<br>  label because the dispatch *is* the explicit request;<br>- an **explicit human request in the thread** (or a mention) for a<br>  deep or full review, which outranks Atlas's cadence and round-scope<br>  rules and gets a round-1-depth pass at the stated head;<br>- **mentions**, which remain unmetered for humans and admins:<br>  free-form questions, audits of a specific concern, and explanations<br>  happen there, off the ledger.<br><br>A deep round changes **discovery scope only**. It suspends the<br>round-cap demotion for that one run; it does not suspend the<br>failure-scenario requirement for `high` (a quality rule instead of a cost<br>rule), and closure rules are unchanged: new blocking findings from a<br>deep round block until fixed and verified, and security still needs<br>both reviewers. Depth is a paid, explicit decision; it never reopens<br>the unbounded loop.<br>``` | Aligns normative review policy with two-tier review assignment and the scoped label grant exception in `post.sh`. Replaces REVIEW.md:8-12 and REVIEW.md:36-39 at paragraph granularity, avoiding partial-sentence corruption. Renames the section heading to colon format and updates deep-review grant documentation. Maintains human override and budget bounds while enabling authorized personas to trigger depth. |
| D8 | **Scope boundary.** The implementing PR MAY touch: `config/execution.yaml`, `scripts/ops/execution.py`, `scripts/ops/tests/execution_test.sh`, `scripts/ops/post.sh`, `scripts/ops/tests/post_test.sh`, `scripts/ci/merge_gate.sh` (scoped strictly to conjuncts (3) and (11) reading the assigned set; everything else in the gate is forbidden), `scripts/ci/tests/merge_gate_test.sh` (two hermetic tests for single-reviewer and dual-reviewer consensus), `.github/workflows/unattended.yml`, `.github/workflows/ci-gates.yml`, `scripts/setup/bootstrap_tracker.sh`, `scripts/setup/issues/04-label-taxonomy.md`, `personas/argus.yaml`, `personas/atlas.yaml`, `personas/daedalus.yaml`, `personas/odyssey.yaml`, `personas/cassandra.yaml`, `personas/skills/deep-review.md`, `personas/skills/review-protocol.md`, `.claude/agents/*.md`, `.agents/agents/*.md`, `REVIEW.md`, and `docs/SPEC.md`. <br>The implementing PR may NOT touch: `personas/lifecycle.json` (ladder and rungs are unchanged), `scripts/ops/work.sh` (dispatcher door unchanged), `scripts/ops/claim.sh` (claim mutex unchanged), `intent/204-verifier-stage/**`, `intent/64-autonomous-loop/**`, and `scripts/ci/merge_gate.sh` outside conjuncts (3) and (11). | Guarantees clear demarcation while giving the implement rung the files required to implement the assigned-set consensus semantics in `merge_gate.sh` and its test suite. Protects core dispatch and lifecycle machinery from unintended regressions. Keeps the implementation strictly focused on review assignment and verification protocol updates. |

## Acceptance

Every row is checkable without a model call, using hermetic test commands:

- **AT-1 (Execution schema check):** `python3 scripts/ops/execution.py --check` exits 0 against `config/execution.yaml`.
- **AT-2 (Execution schema negative tests):** In `scripts/ops/tests/execution_test.sh`:
  - An unknown key inside `assigned_when` exits non-zero with `ERROR: unknown key in assigned_when`.
  - An invalid status label inside `status_labels` (outside `personas/lifecycle.json`) exits non-zero with `ERROR: unknown status label`.
  - An invalid tier in `open_ledger_tiers` (outside `REVIEW.md`) exits non-zero with `ERROR: unknown severity tier`.
  - `assigned_when` on a persona with `trigger: manual` or without `events: [pull_request]` exits non-zero with `ERROR: assigned_when allowed only for pull_request repo-events`.
- **AT-3 (Doc PR assignment):** `python3 scripts/ops/execution.py --subscribers pull_request --status-label status:spec --paths intent/265-review-split/spec.md` outputs:
  ```text
  atlas	gh-actions
  ```
  (`argus` is absent).
- **AT-4 (Code PR assignment):** `python3 scripts/ops/execution.py --subscribers pull_request --status-label status:implementing --paths src/code.py` outputs:
  ```text
  argus	gh-actions
  atlas	gh-actions
  ```
- **AT-5 (Trust-bearing path assignment):** `python3 scripts/ops/execution.py --subscribers pull_request --status-label status:spec --paths .github/workflows/unattended.yml` outputs:
  ```text
  argus	gh-actions
  atlas	gh-actions
  ```
- **AT-6 (Label assignment via deep-review):** `python3 scripts/ops/execution.py --subscribers pull_request --status-label status:planning --paths intent/100-test/intent.md --labels deep-review` outputs:
  ```text
  argus	gh-actions
  atlas	gh-actions
  ```
- **AT-7 (Open security row assignment):** `python3 scripts/ops/execution.py --subscribers pull_request --status-label status:build --paths intent/100-test/plan.md --open-ledger security` outputs:
  ```text
  argus	gh-actions
  atlas	gh-actions
  ```
- **AT-8 (Synchronize pre-recorder assignment):** `python3 scripts/ops/execution.py --subscribers pull_request --action synchronize --status-label status:implementing --paths src/code.py` outputs:
  ```text
  argus	gh-actions
  atlas	gh-actions
  ```
  (Until recorder #8/#9 lands, synchronize dispatches all reviewers assigned under D1).
- **AT-9 (Draft PR skip):** `python3 scripts/ops/execution.py --subscribers pull_request --draft --status-label status:implementing --paths src/code.py` outputs:
  ```text

  ```
  (empty output, 0 subscribers dispatched).
- **AT-10 (Ready for review dispatch):** `python3 scripts/ops/execution.py --subscribers pull_request --action ready_for_review --status-label status:implementing --paths src/code.py` outputs:
  ```text
  argus	gh-actions
  atlas	gh-actions
  ```
- **AT-11 (Fail-closed rung resolution):** `python3 scripts/ops/execution.py --subscribers pull_request --paths intent/265-review-split/spec.md` outputs:
  ```text
  argus	gh-actions
  atlas	gh-actions
  ```
  (When `--status-label` is omitted, empty, or unknown, execution.py fails closed and assigns both reviewers).
- **AT-12 (Label provisioning script):** `grep -F 'ensure_label "deep-review" "5319E7"' scripts/setup/bootstrap_tracker.sh` outputs:
  ```text
  ensure_label "deep-review" "5319E7" "Deep-review grant: triggers a full Argus review round out-of-band"
  ```
- **AT-13 (Label taxonomy documentation):** `grep -A 1 '### `deep-review`' scripts/setup/issues/04-label-taxonomy.md` outputs:
  ```text
  ### `deep-review`
  Deep-review grant: triggers a full Argus review round out-of-band
  ```
- **AT-14 (Duplicate deep-review grant refusal):** In `scripts/ops/tests/execution_test.sh`:
  `python3 scripts/ops/execution.py --check-grant --pr 100 --rung design --existing-grants design` outputs:
  ```text
  Refused: PR #100 already received a deep-review grant on the 'design' rung. Policy allows at most one deep-review grant per PR per rung (REVIEW.md, #265). Escalating to human.
  ```
- **AT-15 (CI diff evaluation for DEEP-1 and DEEP-2):** In `scripts/ops/tests/execution_test.sh`:
  - `python3 scripts/ops/execution.py --diff-rules --lines 401 --paths src/code.py` outputs:
    ```text
    deep-review
    ```
  - `python3 scripts/ops/execution.py --diff-rules --lines 50 --paths scripts/auth/mint_app_token.py` outputs:
    ```text
    deep-review
    ```
  - `python3 scripts/ops/execution.py --diff-rules --lines 50 --paths intent/265-review-split/spec.md` outputs empty output.
- **AT-16 (Persona compiler synchronization):** `python3 scripts/sync_agents.py --check` exits 0, confirming `.claude/agents/*.md` and `.agents/agents/*.md` match `personas/*.yaml` and `personas/skills/*.md`.
- **AT-17 (Spec check gate):** `scripts/ci/spec_check.sh origin/main <pr-body>` exits 0.
- **AT-18 (Sanitization check):** `scripts/ci/sanitize_check.sh` exits 0.
- **AT-19 (Scoped label verb refusal):** In `scripts/ops/tests/post_test.sh`:
  `bash scripts/ops/post.sh 100 --as argus --add-label hold` exits 2 and outputs:
  ```text
  post.sh: --add-label accepts only deep-review on a pull request
  ```
- **AT-20 (Scoped label verb accept):** In `scripts/ops/tests/post_test.sh`:
  `bash scripts/ops/post.sh 100 --as argus --add-label deep-review` exits 0 and applies the label.
- **AT-21 (Atlas-only consensus merge gate evaluation):** In `scripts/ci/tests/merge_gate_test.sh`:
  An Atlas-only PR with `<!-- assigned:atlas -->` in the consensus ledger and Atlas verdict at head OID satisfies conjunct (3) with Atlas alone, skips conjunct (11), and exits with `CONSENSUS_OK=1`.
- **AT-22 (Dual-reviewer consensus merge gate evaluation):** In `scripts/ci/tests/merge_gate_test.sh`:
  A dual-assigned PR with `<!-- assigned:argus,atlas -->` in the consensus ledger and only Atlas verdict at head OID leaves `C[3]=0` and `C[11]=0`, exiting with `CONSENSUS_OK=0`.

## Concerns

- **Live synchronize filtering prior to recorder #8/#9.** As resolved in D2, live filtering of `synchronize` pushes on open blocking findings is deferred until the structured recorder (#8/#9) lands. In the interim, non-code PRs skip Argus under D1, and Atlas runs at the fast tier.
- **Merge gate alignment with consensus follows assignment.** #64 D7 stays as written for two-reviewer PRs; D5 narrows it for Atlas-only PRs by reading the assigned set marker from the ledger. Scoped changes to conjuncts (3) and (11) in `scripts/ci/merge_gate.sh` and two hermetic test cases in `scripts/ci/tests/merge_gate_test.sh` are owned directly by the #265 implement rung. No edit to `intent/64-**` is planned.

## Out of scope

- Autonomous merge gate execution script (`scripts/ci/merge_gate.sh`) outside conjuncts (3) and (11), merge App identity, and autonomous switch flag (#64, #251, #147).
- Changing persona model family assignments or pins in `config/deployments.yaml` or `config/model_tiers.yaml` (#271, #198).
- Redefining reviewer internal reasoning prompts beyond the verifier checklist and deep review criteria.
- Automated issue intake and backlog refilling (#150).
- Scheduled deterministic sweep passes for label self-healing (#104).
- Branch protection rules configuration (#148).
- Internal execution details of deep review passes (governed by `REVIEW.md`).
- Any rows of #204 outside #265's scope.

## Operator decisions

None required by this spec. The design uses existing tokens, App identities, and model allocations.
