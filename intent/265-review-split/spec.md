# Spec: two-tier review assignment and per-rung verification

**Issue:** #265 · **Status:** Approved (approval = merge of this PR) ·
**Author:** athena (`evekhm-athena-app[bot]`) ·
**Open questions:** none

## What is being built

The review process splits from "both reviewers read every pull request" into a
two-tier assignment model with a unified per-rung verification checklist. Atlas
runs on Antigravity (Gemini Flash, the fast tier) and reviews every pull
request at every rung. Argus runs on Claude Code (Sonnet, the frontier/review
tier) and joins at the code gate (`status:implementing`), on trust-bearing
paths, on an open `security` row, or upon an explicit `review:deep` grant.

The verifier stage (#204) is unified into this protocol as a rung-scoped
checklist in `REVIEW.md`, executed by Atlas at every gate and deepened by
Argus wherever assigned.

```text
config/execution.yaml                    # assigned_when block for argus
scripts/ops/execution.py                 # parse and validate assigned_when, context-aware subscribers filtering
scripts/ops/tests/execution_test.sh      # hermetic unit and contract tests for assignment and --check
.github/workflows/unattended.yml         # ready_for_review trigger, draft skip, assignment and deep review resolution
scripts/setup/bootstrap_tracker.sh       # review:deep label provisioning
scripts/setup/issues/04-label-taxonomy.md # review:deep label documentation
personas/skills/deep-review.md           # DEEP-1..DEEP-7 criteria and persona grant rules
personas/skills/review-protocol.md       # citation to verifier checklist in REVIEW.md
personas/*.yaml                          # declare deep-review.md skill where authorized
REVIEW.md                                # line 8 rewrite, verifier checklist, rewritten deep-review grant
docs/SPEC.md                             # living spec updates for execution.placement and review.policy
```

`personas/lifecycle.json`, `scripts/ops/work.sh`, `scripts/ops/claim.sh`,
`intent/204-verifier-stage/**`, and `intent/64-autonomous-loop/**` are NOT
touched (D8).

## Decisions

| ID | Decision | Rationale |
|----|----------|-----------|
| D1 | **Machine-readable assignment shape in `config/execution.yaml`.** A binding with `trigger: repo-event` and `events: [pull_request]` gains an optional `assigned_when` mapping. `BINDING_KEYS` in `scripts/ops/execution.py` expands to `{"trigger", "events", "placement", "max_cost_usd", "assigned_when"}`. For `atlas`, `assigned_when` is omitted: Atlas is assigned unconditionally to all `pull_request` events. For `argus`, `assigned_when` specifies four disjunctive categories (OR between categories): `status_labels` (`[status:implementing]`), `paths` (`[".github/workflows/**", "scripts/auth/**", "scripts/ops/post.sh", "scripts/ops/work.sh", "scripts/ci/**", "personas/**", "config/**", "REVIEW.md", "AGENTS.md"]`), `labels` (`[review:deep]`), and `open_ledger_tiers` (`[security]`). Within each category, any match satisfies that condition. The CLI called by `unattended.yml` resolve step is `python3 scripts/ops/execution.py --subscribers pull_request [--status-label <label>] [--paths <p1> ... \| --paths-file <file>] [--labels <l1> ...] [--open-ledger <t1> ...] [--action <action>]`. `--check` validates: `assigned_when` is allowed only on `repo-event` bindings with `pull_request` in `events`; only the four allowed sub-keys may appear; `status_labels` must contain valid stage labels from `personas/lifecycle.json`; `paths` and `labels` must be non-empty string lists; `open_ledger_tiers` must contain valid severity tiers from `REVIEW.md`. | Preserves `execution.py`'s monopoly as the single YAML parser (#25 D2) and its zero-dependency invariant (`pyyaml` only, no network, no `gh`). Evaluates entirely hermetically in unit tests and in CI. Disjunctive evaluation matches the intent's four independent entry points for Argus. Unconditional omission for Atlas enforces "Atlas reads every PR at every rung" without redundant configuration. |
| D2 | **Synchronize gating rule, draft skip, and OQ2 resolution in `unattended.yml`.** `.github/workflows/unattended.yml` adds `ready_for_review` to `on.pull_request.types` (`types: [opened, synchronize, reopened, ready_for_review]`). Draft PRs skip review dispatch entirely: `if: github.event.pull_request.draft == false` is evaluated by the `resolve` job, which emits an empty matrix when true, dispatching zero personas. On `synchronize`, a reviewer is dispatched if and only if: (a) the reviewer is assigned to the PR under D1; AND (b) that reviewer has an open blocking row (`security` or `high`) on the PR, or `review:deep` was applied on the PR since their last review round. **OQ2 resolution:** live suppression of `synchronize` runs based on open blocking rows is **deferred to the landing of the structured recorder (#8/#9) on main** (the named condition). Until recorder lands, `synchronize` on non-draft PRs dispatches all reviewers assigned to the PR under D1. In `scripts/ops/tests/execution_test.sh`, the contract is implemented and hermetically tested using simulated ledger inputs passed via `--open-ledger`. | PR comments prior to recorder (#8/#9) are unstructured LLM markdown prose lacking schema validation (REVIEW.md:441-445: "Every rule must exist in code before a prompt may describe it in the present tense... Until the recorder lands, rows marked *recorder* are prompt-enforced with a human backstop"). Regex scraping across free-form LLM prose risks false negatives that silently drop required verification reviews and stall merges. Deferring live suppression to recorder #8/#9 while enforcing D1 assignment filters on `synchronize` immediately cuts non-code PR costs safely. |
| D3 | **`review:deep` label provisioning and lifecycle.** `scripts/setup/bootstrap_tracker.sh` provisions `review:deep` under `--labels-only` and full runs: `ensure_label "review:deep" "5319E7" "Deep-review grant: triggers a full Argus review round out-of-band"`. Documented in `scripts/setup/issues/04-label-taxonomy.md`. `.github/workflows/unattended.yml` adds `pull_request.types: [labeled]`; when `github.event.label.name == 'review:deep'`, it resolves and dispatches Argus. Authorized grantors: repository administrators (via GitHub UI/API) and persona App identities (`daedalus`, `odyssey`, `atlas`, `argus`, `cassandra`) via `scripts/ops/post.sh`. An application by any other identity is refused: the label is removed and an explanation posted. When Argus is dispatched under the grant, `review:deep` is removed immediately so a standing label cannot re-arm the loop. **Limit: at most one grant per PR per rung.** If an actor attempts to apply a second grant on the same PR while on the same rung, the label is removed immediately and the following refusal comment posted: `Refused: PR #<n> already received a deep-review grant on the '<rung>' rung. Policy allows at most one deep-review grant per PR per rung (REVIEW.md, #265). Escalating to human.` | Idempotent label setup follows issue #4 taxonomy. App identities need the grant to escalate tricky changes without human intervention. One-grant-per-rung prevents runaway spend loops from repeated deep rounds. Consuming the label on use prevents re-triggering upon subsequent pushes. |
| D4 | **DEEP-1..DEEP-7 criteria, CI diff step, and `personas/skills/deep-review.md`.** The criteria are carried VERBATIM from the merged intent: <br>• **DEEP-1:** The change touches a trust-bearing path (`.github/workflows/**`, `scripts/auth/**`, `scripts/ops/post.sh`, `scripts/ops/work.sh`, `scripts/ci/**`, `personas/**`, `config/**`, `REVIEW.md`, `AGENTS.md`). <br>• **DEEP-2:** The diff is large (>400 lines outside generated files, tests, and `intent/` docs). <br>• **DEEP-3:** The PR introduces a new persona, a new tool, a new permission, or an external network dependency. <br>• **DEEP-4:** The PR deviates from its spec or plan in a way that requires an architectural judgment call. <br>• **DEEP-5:** The PR changes an interface between two personas or between a persona and a shared script. <br>• **DEEP-6:** Atlas requests depth: its own verification at the fast tier surfaced an ambiguity or a failure scenario it cannot resolve with confidence. <br>• **DEEP-7:** Review round 2 produced a disputed finding or an unresolved high finding. <br>Application: CI evaluates git diff for DEEP-1 (assigns Argus) and DEEP-2 (applies `review:deep`). Daedalus applies DEEP-3, DEEP-5, DEEP-7 (recorded in `plan.md`). Odyssey applies DEEP-3, DEEP-4, DEEP-5 upon PR creation or update. Atlas applies DEEP-6 after its review round. Cassandra or advisor applies DEEP-4, DEEP-7 on repair PRs. Skill file `personas/skills/deep-review.md` cites #265 and `REVIEW.md`, lists DEEP-1..DEEP-7, and is declared by `daedalus.yaml`, `odyssey.yaml`, `atlas.yaml`, `argus.yaml`, `cassandra.yaml`, compiled via `scripts/sync_agents.py`. | Verbatim inclusion ensures fidelity to accepted intent. Distributing responsibility across personas anchors depth at the precise lifecycle stage where risk appears. CI handles deterministic diff metrics, preserving model tokens. A single shared skill file compiled into persona prompts avoids documentation drift. |
| D5 | **Consensus follows assignment (interface to #64 merge gate).** The merge predicate (#64 D5 conjunct 3) requires recorded verdicts covering current head OID from **assigned reviewers only**. Where only Atlas was assigned (e.g. non-code, non-trust PRs without deep review), Atlas clean ledger at head + green CI satisfies merge eligibility; Argus's verdict is neither requested nor required. Where both reviewers are assigned, dual sign-off is required. Carry-forward (#64 D7) applies to Atlas only on multi-round PRs where Atlas was assigned; condition (v) of #64 D7 ("no deep-review grant is outstanding at this head") holds unchanged, ensuring an active `review:deep` grant invalidates carry-forward until verified. | Directly fulfills INTENT.md proposed outcome 4. Prevents non-code PRs from deadlocking while waiting for an unassigned reviewer. Preserves the dual-family consensus guarantee on all code and high-risk paths. |
| D6 | **Per-rung verifier checklist as ONE Decision with ONE home.** Reconciles #204 D2/D3: the verifier checklist lives in `REVIEW.md` under `## The verification protocol` (exactly once in the repository). `personas/skills/review-protocol.md` references `REVIEW.md` without duplicating checklist steps. The four rung checks from the amendment are carried word for word: <br>• **plan:** "at plan, the intent lost nothing from the issue;" <br>• **design:** "at design, no open question and every acceptance row runnable without a model;" <br>• **build:** "at build, the contract tests fail at the plan's base;" <br>• **implement:** "at implement, the gates re-run and the job log behind every green check says what the check claims." <br>• **code gate additions:** "Argus adds the deep checks where it is assigned (code gate, trust-bearing paths, `review:deep`, open `security` row): mutation-test the tests, re-run the gates, read the full diff." Atlas executes the checklist on every assigned PR; Argus executes the checklist plus deep checks at implement and wherever assigned. | Closes #204 into #265 without creating duplicate personas or competing sources of truth. Consolidating the protocol into `REVIEW.md` respects #204 D2, while referencing from `review-protocol.md` conforms to #204 D3. |
| D7 | **`REVIEW.md` rewrites.** Line 8 is replaced with: <br>`**In one line:** Atlas reviews every PR at every rung; Argus joins at the code gate, on trust-bearing paths, and on deep-review grants; after that only security and high findings block, security alone needs both reviewers to agree, rounds cap at three — and a human can merge at any time, with anything still open becoming a follow-up issue instead of another round.` <br>The section `## Asking for more — the deep-review grant` is replaced with: <br>```markdown<br>## Asking for more — the deep-review grant<br><br>The funnel bounds the automatic loop; it must never bound the human.<br>For a review that goes *beyond* the protocol — full depth, full tree,<br>every tier, regardless of round count — the sanctioned paths are:<br><br>- a **`review:deep` label** applied by a persona App identity<br>  (`daedalus`, `odyssey`, `atlas`, `argus`, `cassandra`) through<br>  `scripts/ops/post.sh` under criteria DEEP-1..DEEP-7, or by a<br>  repository admin, verified from the label event timeline and<br>  consumed on use, with a limit of one grant per PR per rung (a second<br>  grant on the same rung is refused and removed);<br>- a **deep manual dispatch** of the review workflow, which needs no<br>  label because the dispatch *is* the explicit request;<br>- an **explicit human request in the thread** (or a mention) for a<br>  deep or full review, which outranks Atlas's cadence and round-scope<br>  rules and gets a round-1-depth pass at the stated head;<br>- **mentions**, which remain unmetered for humans and admins:<br>  free-form questions, audits of a specific concern, and explanations<br>  happen there, off the ledger.<br><br>A deep round changes **discovery scope only**. It suspends the<br>round-cap demotion for that one run; it does not suspend the<br>failure-scenario requirement for `high` (a quality rule, not a cost<br>rule), and closure rules are unchanged — new blocking findings from a<br>deep round block until fixed and verified, and security still needs<br>both reviewers. Depth is a paid, explicit decision; it never reopens<br>the unbounded loop.<br>``` | Aligns the normative review policy with the two-tier reality. Explicitly quotes the required replacement text so implementers can perform an exact drop-in update. Maintains human override and budget bounds while enabling authorized personas to trigger depth. |
| D8 | **Scope boundary.** The implementing PR MAY touch: `config/execution.yaml`, `scripts/ops/execution.py`, `scripts/ops/tests/execution_test.sh`, `.github/workflows/unattended.yml`, `scripts/setup/bootstrap_tracker.sh`, `scripts/setup/issues/04-label-taxonomy.md`, `personas/argus.yaml`, `personas/atlas.yaml`, `personas/daedalus.yaml`, `personas/odyssey.yaml`, `personas/cassandra.yaml`, `personas/skills/deep-review.md`, `personas/skills/review-protocol.md`, `.claude/agents/*.md`, `.agents/agents/*.md`, `REVIEW.md`, and `docs/SPEC.md`. <br>The implementing PR may NOT touch: `personas/lifecycle.json` (ladder and rungs are unchanged), `scripts/ops/work.sh` (dispatcher door unchanged), `scripts/ops/claim.sh` (claim mutex unchanged), `intent/204-verifier-stage/**`, `intent/64-autonomous-loop/**`, and any file owned by #64's PR #257 while open (`scripts/ci/merge_gate.sh`, `scripts/ci/escalate.sh`, `scripts/ci/tests/merge_gate_test.sh`, `.github/workflows/merge-gate.yml`). | Guarantees clear demarcation between concurrent issues #64 and #265. Protects core dispatch and lifecycle machinery from unintended regressions. Keeps the implementation strictly focused on review assignment and verification protocol updates. |

## Acceptance

Every row is checkable without a model call, using hermetic test commands:

- **AT-1 (Execution schema check):** `python3 scripts/ops/execution.py --check` exits 0 against `config/execution.yaml`.
- **AT-2 (Execution schema negative tests):** In `scripts/ops/tests/execution_test.sh`:
  - An unknown key inside `assigned_when` exits non-zero with `ERROR: unknown key in assigned_when`.
  - An invalid status label inside `status_labels` (not in `personas/lifecycle.json`) exits non-zero with `ERROR: unknown status label`.
  - An invalid tier in `open_ledger_tiers` (not in `REVIEW.md`) exits non-zero with `ERROR: unknown severity tier`.
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
- **AT-6 (Label assignment via review:deep):** `python3 scripts/ops/execution.py --subscribers pull_request --status-label status:planning --paths intent/100-test/intent.md --labels review:deep` outputs:
  ```text
  argus	gh-actions
  atlas	gh-actions
  ```
- **AT-7 (Open security row assignment):** `python3 scripts/ops/execution.py --subscribers pull_request --status-label status:build --paths intent/100-test/plan.md --open-ledger security` outputs:
  ```text
  argus	gh-actions
  atlas	gh-actions
  ```
- **AT-8 (Synchronize with clean ledger):** `python3 scripts/ops/execution.py --subscribers pull_request --action synchronize --status-label status:implementing --paths src/code.py` (with no open blocking rows passed for reviewers) outputs an empty subscriber list for reviewers with no open blocking rows.
- **AT-9 (Draft PR skip):** A pull request payload with `draft: true` evaluated in `.github/workflows/unattended.yml` produces an empty matrix and dispatches zero jobs.
- **AT-10 (Ready for review dispatch):** A pull request payload with action `ready_for_review` and `draft: false` evaluates subscribers identically to `opened`.
- **AT-11 (Label provisioning):** `bash scripts/setup/bootstrap_tracker.sh --labels-only` executes idempotently and ensures `review:deep` exists with color `5319E7`.
- **AT-12 (Duplicate deep-review grant refusal):** Applying `review:deep` a second time to a PR that has already received a grant on its current rung removes the label and posts the refusal comment defined in D3.
- **AT-13 (Persona compiler synchronization):** `python3 scripts/sync_agents.py --check` exits 0, confirming `.claude/agents/*.md` and `.agents/agents/*.md` match `personas/*.yaml` and `personas/skills/*.md`.
- **AT-14 (Spec check gate):** `scripts/ci/spec_check.sh origin/main <pr-body>` exits 0.
- **AT-15 (Sanitization check):** `scripts/ci/sanitize_check.sh` exits 0.

## Concerns

- **Live synchronize filtering prior to recorder #8/#9.** As resolved in D2, live filtering of `synchronize` pushes on open blocking findings is deferred until the structured recorder (#8/#9) lands. In the interim, non-code PRs already skip Argus under D1, and Atlas runs on Gemini Flash at negligible cost.
- **Concurrent PR #257 (#64) in-flight.** Issue #64's PR #257 touches `merge_gate.sh` and related CI files. D8 strictly forbids the implementing PR of #265 from touching PR #257's files while it is open. Once PR #257 lands on `main`, the merge gate's consensus logic will naturally evaluate assigned reviewers per D5.

## Out of scope

- Autonomous merge gate execution script (`scripts/ci/merge_gate.sh`), merge App identity, and autonomous switch flag (#64, #251, #147).
- Changing persona model family assignments or pins in `config/deployments.yaml` or `config/model_tiers.yaml` (#271, #198).
- Redefining reviewer internal reasoning prompts beyond the verifier checklist and deep review criteria.
- Automated issue intake and backlog refilling (#150).
- Scheduled deterministic sweep passes for label self-healing (#104).
- Branch protection rules configuration (#148).
- Internal execution details of deep review passes (governed by `REVIEW.md`).
- Any remaining rows of #204 not superseded by #265.

## Operator decisions

None required by this spec. The design uses existing tokens, App identities, and model allocations.
