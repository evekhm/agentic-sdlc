# Spec: Gated and Bounded VM Poller Intake, Reviewer Trigger Isolation, and Lock Relocation

**Issue:** #295 · **Status:** Approved (approval = merge of this PR) ·
**Author:** athena (`evekhm-athena-app[bot]`) ·
**Open questions:** none

## What is being built

Operational experience following the merge of #251 (PR #294 at `dc0010bd`) and the
autonomy flip (PR #297 at `6c7d71c`) exposed seven operational defects and test gaps
in `scripts/placement/vm-local/poll.sh`, `scripts/ci/tests/e2e_chain_test.sh`, and the
normative text of #251 (`intent/251-e2e-chain/spec.md`). This specification resolves
all seven gaps while maintaining strict separation of concerns, fail-closed safety,
and the repository-wide single-source-of-truth configuration architecture:

1. **Master autonomy gate for poller queues (Gap 1):** `poll.sh` checks the master
   switch `loop.autonomous_merge` via `scripts/ops/execution.py --loop autonomous_merge`
   at the beginning of every polling tick. When the flag is anything other than `true`
   (e.g. `false`, missing key, unreadable file), `poll.sh` logs one notice per tick and
   idles all queues (dispatch rows, fix rounds, and first-hop intake).
2. **First-hop fleet concurrency ceiling (Gap 2):** `poll.sh` enforces a concurrency
   limit `loop.max_concurrent_first_hops` (default 1) defined in `config/execution.yaml`
   and validated by `scripts/ops/execution.py`. Concurrency is measured directly from the
   issue tracker by counting open issues carrying `in-progress` whose latest claim
   comment was authored by Athena (login normalized via `(.author.login // .user.login // "")`
   with any trailing `[bot]` suffix stripped, matching `evekhm-athena-app`).
3. **Opt-in backlog intake filter (Gap 2):** To prevent unbounded intake across the
   existing backlog of 37+ `intent:new` issues, `poll.sh` restricts first-hop triage to
   issues carrying both `intent:new` and an opt-in label `intake:auto`. Backlog items
   are armed individually or in controlled batches by adding `intake:auto`.
4. **State directory and fix-round lock relocation (Gap 3):** Fix-round locks and
   consumption keys are moved out of `/tmp` into a dedicated state directory
   `POLL_STATE_DIR`, defaulting to the XDG state directory (`XDG_STATE_HOME` when set, otherwise `~/.local/state` expanded by the shell) with `/sdlc-poller` appended.
   Contract test row AT-20 resolves the lock path from the same environment variable.
5. **Contract test grep option parsing portability (Gap 4):** In row AT-13 of
   `scripts/ci/tests/e2e_chain_test.sh`, `grep -q "--> odyssey"` is updated to
   `grep -q -- "--> odyssey"`. Under POSIX and GNU grep, leading dashes in pattern
   arguments are parsed as option flags unless explicitly preceded by `--`.
6. **Reviewer-only identity restriction for fix rounds (Gap 5):** `poll.sh` removes the
   author-agnostic literal matcher for `review findings: blocking`. Fix-round dispatches
   are triggered strictly by comments whose author login normalized via
   `(.author.login // .user.login // "")` with any trailing `[bot]` suffix stripped matches
   an authorized reviewer identity (`evekhm-argus-app` or `evekhm-atlas-app`). Comments from
   foreign authors carrying the phrase or verdict markers are ignored.
7. **Independent verification of lock contention in AT-20 (Gap 6):** In row AT-20 of
   `scripts/ci/tests/e2e_chain_test.sh`, the consumption key generated on tick 1 is
   cleared before tick 2, proving that `lock_file` actively prevents duplicate dispatch
   under contention rather than passing vacuously due to consumption keys.
8. **Enablement checklist sequencing alignment (Gap 1 / D6):** Step 2 of the seven-step
   checklist in `docs/SPEC.md ## Deployment status` is clarified: starting the VM
   supervisor before the autonomy flip pull request is safe because `poll.sh` idles
   all queues while `loop.autonomous_merge: false`.
9. **Claim reader dual-field specification alignment (Gap 7):** Normative text in
   `docs/SPEC.md` and spec documentation is aligned with
   `scripts/ci/lifecycle_advance.sh:1076`, documenting that claim holder login is derived
   via `(.author.login // .user.login // "")`, supporting both GraphQL and REST payload shapes.

### Manifest of files touched by the implementation rung

```text
scripts/placement/vm-local/poll.sh        # loop.autonomous_merge check, fleet ceiling, intake:auto, POLL_STATE_DIR, reviewer-only trigger
scripts/ops/execution.py                  # allowlist and integer validation for loop.max_concurrent_first_hops
config/execution.yaml                     # define loop.max_concurrent_first_hops: 1
scripts/ci/tests/e2e_chain_test.sh        # AT-8, AT-13 (grep --), AT-15, AT-20 (POLL_STATE_DIR, foreign author, lock isolation), AT-21, AT-22
scripts/ops/tests/execution_test.sh       # test scenarios for max_concurrent_first_hops validation
scripts/setup/bootstrap_tracker.sh        # provision intake:auto label
scripts/setup/issues/04-label-taxonomy.md # documentation for intake:auto label
docs/SPEC.md                              # living spec updates for deployment checklist, poller intake gate, and execution config
intent/295-poller-intake-gate/plan.md     # build rung plan artifact
```

Forbidden files (untouched by this implementation):
- `scripts/ci/escalate.sh`: escalation reason codes remain closed; no new reason code added.
- `.github/workflows/lifecycle.yml`: triggers and permissions remain untouched.
- `scripts/ci/merge_gate.sh`: merge gating logic is not modified.
- `scripts/ops/claim.sh`: claim script mechanics remain untouched.
- `scripts/ops/work.sh`: single-argument dispatch interface remains untouched.
- `personas/**`: persona source files remain untouched.

## Decisions

| ID | Decision | Rationale |
|---|---|---|
| D1 | **Amendment target and supersession structure.** This specification forms the normative design for issue #295 and amends the merged specification of #251 (`intent/251-e2e-chain/spec.md`) and Decision D20 of #64 (`intent/64-execution-binding-loop-limits/spec.md`). Specifically, Decision D20 of #64 is amended to add `max_concurrent_first_hops` to the closed `loop:` key allowlist in `scripts/ops/execution.py`, keeping loop-level ceilings co-located under the central execution configuration schema; Decision D2 of #251 is superseded regarding fix-round trigger predicates (restricting to verified reviewer logins) and lock path location (relocating into `POLL_STATE_DIR`); Decision D5 of #251 is superseded regarding intake arming (gated on `loop.autonomous_merge`), intake concurrency bounding (`loop.max_concurrent_first_hops`), and backlog admission (`intake:auto`); Decision D6 of #251 is amended in documentation regarding supervisor startup safety; Decision D1 of #251 is clarified regarding claim author derivation (`.author.login // .user.login`); and Decision D8 of #251 (manifest of touched files) is updated to admit the files touched by this implementation rung. | Formalizing amendments as a dedicated specification with explicit supersessions preserves historical fidelity of merged specifications while establishing unambiguous, binding rules for the new implementation rung. |
| D2 | **Master autonomy gate across all poller queues (Gap 1).** At the start of each polling tick, `scripts/placement/vm-local/poll.sh` checks the autonomy master switch using `python3 "$REPO_ROOT/scripts/ops/execution.py" --loop autonomous_merge`. If `execution.py` exits non-zero or prints anything other than `true` (such as `false`, absent key, unparseable file), `poll.sh` logs `poll.sh: autonomous_merge is not true; idling queues` exactly once per tick and immediately returns, skipping all three queues: fix rounds on open pull requests, first-hop intake on `intent:new`, and ledger dispatch row consumption on ladder issues. When executed with `--once`, `poll.sh` logs the notice and exits 0. Contract rows AT-8, AT-15, and AT-20 in `scripts/ci/tests/e2e_chain_test.sh` provide a fixture `config/execution.yaml` with `loop.autonomous_merge: true`. A new contract row (AT-21) verifies that with `loop.autonomous_merge: false`, `poll.sh --once` logs the notice and performs zero dispatches across all queues. | Per #64 D18 and D20, `loop.autonomous_merge` is the repository-wide master switch for autonomous agent operations. Halting all poller queues when the flag is false prevents premature or unauthorized unattended agent dispatches and provides a single, instant kill-switch for operators. |
| D3 | **Fleet concurrency ceiling for first-hop intake (Gap 2) and amendment to #64 D20.** In `config/execution.yaml`, the `loop:` block defines `max_concurrent_first_hops: 1`. In `scripts/ops/execution.py`, this specification amends Decision D20 of #64 (`intent/64-execution-binding-loop-limits/spec.md`) by expanding the closed `loop:` key allowlist from `{"autonomous_merge", "max_rung_dispatches_per_issue", "max_cost_usd_per_issue"}` to `{"autonomous_merge", "max_rung_dispatches_per_issue", "max_cost_usd_per_issue", "max_concurrent_first_hops"}`; `max_concurrent_first_hops` is validated as a positive integer (`int`, > 0, not boolean). Amending #64 D20 co-locates all loop-level execution limits and concurrency ceilings within the single repository-wide execution configuration namespace. In `poll.sh`, before evaluating candidate intake issues, the poller measures active first-hop concurrency against the tracker: it queries `gh issue list --state open --label in-progress --json number,comments` (paginating if necessary) and counts open issues where the latest comment starting with `Claim:` (case-insensitive) has an author matching Athena. Because GitHub CLI surfaces differ in payload shape (`gh issue list` returns GraphQL-shaped comments where `.author.login` lacks a `[bot]` suffix, whereas REST-shaped payloads like `poll.sh:152` return `.user.login` with the `[bot]` suffix), the author match is defined using the normalization `(.author.login // .user.login // "")` (as in `scripts/ci/lifecycle_advance.sh:1076`) with any trailing `[bot]` suffix stripped, compared against `evekhm-athena-app`. This normalization covers both GraphQL and REST payload shapes. If this count equals or exceeds `loop.max_concurrent_first_hops` (read via `python3 "$REPO_ROOT/scripts/ops/execution.py" --loop max_concurrent_first_hops 2>/dev/null || echo 1`), `poll.sh` logs `poll.sh: first-hop intake concurrency limit reached (<count>/<limit>), skipping intake` and skips the first-hop intake queue for that tick. | First-hop intake launches Athena sessions that consume model quotas and compute budget. Bounding concurrent Athena sessions prevents runaway fleet billing while respecting tracker state as the canonical source of truth across all sessions and harnesses. Normalizing author logins across GraphQL and REST payloads prevents the ceiling from failing open. |
| D4 | **Opt-in backlog admission filter (`intake:auto`) (Gap 2).** In `scripts/placement/vm-local/poll.sh`, first-hop intake candidate discovery queries open issues carrying BOTH `intent:new` AND `intake:auto`: `gh issue list --state open --label "intent:new" --label "intake:auto" --json number,title,labels`. Issues carrying `intent:new` without `intake:auto` are skipped by automated intake. When an issue carrying both labels is claimed and dispatched, `poll.sh` claims it under `CLAIM_ACTOR=athena` via `claim.sh`. The label `intake:auto` (description: "Opt-in for automated first-hop poller intake", color: `#C2E0C6`) is registered in `scripts/setup/issues/04-label-taxonomy.md` and provisioned by `scripts/setup/bootstrap_tracker.sh`. | With over 37 historical `intent:new` issues in the repository backlog, automated polling without backlog filtering would instantly dispatch sessions on the entire backlog. Requiring `intake:auto` ensures human operators control exactly which issues enter autonomous processing. |
| D5 | **Relocation of fix-round lock files and consumption keys to `POLL_STATE_DIR` (Gap 3).** In `scripts/placement/vm-local/poll.sh`, the lock file path and consumption key path are relocated into `POLL_STATE_DIR`, defaulting to the XDG state directory (`XDG_STATE_HOME` when set, otherwise `~/.local/state` expanded by the shell): e.g. `local state_base="${XDG_STATE_HOME:-}"; [ -z "$state_base" ] && state_base=~/.local/state; local poll_state_dir="${POLL_STATE_DIR:-${state_base}/sdlc-poller}"`, `mkdir -p "$poll_state_dir" 2>/dev/null || true`, `local lock_file="${poll_state_dir}/poll-pr-${pr_num}.lock"`, and `local key_file="${poll_state_dir}/pr-${pr_num}-${repo_hash}-${key}"`. In `scripts/ci/tests/e2e_chain_test.sh`, row AT-20 resolves `lock_file` from `${POLL_STATE_DIR:-${TMPDIR:-/tmp}/sdlc-poller}/poll-pr-4242.lock` instead of hardcoding `${TMPDIR:-/tmp}/poll-pr-4242.lock`. | Placing runtime state and locks in standard XDG user state directories (`~/.local/state/sdlc-poller`) isolates daemon state per user, avoids multi-user permission collisions in shared `/tmp`, and preserves hermetic test isolation in sandboxes. |
| D6 | **Reviewer-only identity restriction for fix-round trigger comments (Gap 5).** In `scripts/placement/vm-local/poll.sh`, the author-agnostic matcher `select((.body // "") | contains("review findings: blocking"))` is removed. A pull request comment can trigger a fix-round dispatch ONLY if its author login normalized via `(.author.login // .user.login // "")` with any trailing `[bot]` suffix stripped matches an authorized reviewer identity (`evekhm-argus-app` or `evekhm-atlas-app`, covering both GraphQL and REST payload shapes). Any comment from a non-reviewer author containing `review findings: blocking` or structured verdict markers is ignored. When an authorized reviewer comment contains `review findings: blocking` or an open blocking finding (`<!-- finding:[^:]+:(security|high):open:`), the fix round triggers. | Author-agnostic phrase matching permits any commenter on GitHub to trigger unattended Odyssey fix-round sessions simply by posting the literal words "review findings: blocking". Restricting trigger parsing to Argus and Atlas prevents spoofed or conversational review triggers. |
| D7 | **Independent verification of lock contention in AT-20 (Gap 6).** In `scripts/ci/tests/e2e_chain_test.sh`, row AT-20 tests lock contention on tick 2 by clearing or removing the consumption `key_file` generated on tick 1 (`rm -f "$poll_state_dir"/pr-4242-*`) prior to creating `lock_file` and executing tick 2. With `key_file` absent on tick 2, tick 2 would proceed to launch UNLESS `lock_file` prevents it. Thus, asserting `$(cat "$LAUNCHES") == "$launches_first"` verifies that `lock_file` actively prevents dispatch under contention, rather than passing vacuously due to consumption keys. | In the poller execution sequence, the lock check precedes the consumption key check (`poll.sh:196` vs `:221`). However, if a regression disabled lock evaluation, tick 2 would still skip dispatch because `key_file` was written on tick 1. Clearing `key_file` before tick 2 isolates and tests the lock mechanism directly. |
| D8 | **Portability of grep option parsing in contract tests (Gap 4).** In `scripts/ci/tests/e2e_chain_test.sh:1310` (row AT-13), the pattern match `grep -q "--> odyssey" <<<"$out"` is changed to `grep -q -- "--> odyssey" <<<"$out"`. Under POSIX and GNU grep, command-line arguments beginning with a hyphen are treated as option flags; `-->` is parsed as invalid option `->`, causing test failure. Adding `--` terminates option processing portably across GNU grep, BSD grep, and ugrep. | Standardizing option separation with `--` prevents platform-dependent test failures on GitHub Actions Ubuntu runners executing GNU grep. |
| D9 | **Enablement checklist sequencing and early startup safety (Gap 1 / D6).** In `docs/SPEC.md ## Deployment status`, step 2 of the seven-step enablement checklist remains in place (supervisor configuration prior to the autonomy flip), annotated with the guarantee that early supervisor startup is completely safe because `poll.sh` idles all queues whenever `loop.autonomous_merge: false` (per Decision D2). Step 6 remains the sole activation event that arms unattended operations. | Documenting the safety invariant in `docs/SPEC.md` maintains a simple, linear checklist for human operators without requiring reordering or split phases. |
| D10 | **Normative specification of dual GraphQL and REST claim author fields (Gap 7).** In `docs/SPEC.md` and spec documentation, Decision D1 of #251 is amended to reflect that `scripts/ci/lifecycle_advance.sh:1076` derives claim holder identity via `(.author.login // .user.login // "")` mapped through persona identities. Both GraphQL payload shapes (`author.login`) and REST payload shapes (`user.login`) are normatively supported. | Eliminates documentation discrepancy between specification text and production advancer code while guaranteeing robustness across GitHub GraphQL and REST API responses. |
| D11 | **Implementation scope boundary and manifest.** The implementing pull request for #295 may touch: `scripts/placement/vm-local/poll.sh`, `scripts/ops/execution.py`, `config/execution.yaml`, `scripts/ci/tests/e2e_chain_test.sh`, `scripts/ops/tests/execution_test.sh`, `scripts/setup/bootstrap_tracker.sh`, `scripts/setup/issues/04-label-taxonomy.md`, `docs/SPEC.md`, and `intent/295-poller-intake-gate/plan.md`. It may NOT touch `scripts/ci/escalate.sh`, `.github/workflows/lifecycle.yml`, `scripts/ci/merge_gate.sh`, `scripts/ops/claim.sh`, `scripts/ops/work.sh`, or files under `personas/**`. | Tight manifest boundaries protect merge gate and escalation invariants from accidental modifications while allowing the necessary poller, configuration, and contract test updates. |

## Acceptance

Every acceptance test assertion cites the Decision ID it derives from and is checkable without model calls:

- **SA-1 (D1, D11)** Pre-merge validation checks exit 0:
  `BODY_FILE="$(mktemp)"; echo "Spec-impact: none - intent/** only, not a behavior-bearing path" > "$BODY_FILE"; bash scripts/ci/spec_check.sh origin/main "$BODY_FILE"; rm -f "$BODY_FILE"`
  and `bash scripts/ci/sanitize_check.sh`.
- **SA-2 (D2)** Executing `bash -n scripts/placement/vm-local/poll.sh` exits 0. In `scripts/ci/tests/e2e_chain_test.sh`, rows AT-8, AT-15, and AT-20 set up a fixture `config/execution.yaml` with `loop.autonomous_merge: true` and pass with exit 0.
- **SA-3 (D2)** In `scripts/ci/tests/e2e_chain_test.sh` (row AT-21), running `scripts/placement/vm-local/poll.sh --once` with `loop.autonomous_merge: false` (or key absent) logs `poll.sh: autonomous_merge is not true; idling queues`, performs zero dispatches across dispatch rows, fix rounds, and intake, and exits 0.
- **SA-4 (D3, D11)** In `scripts/ops/tests/execution_test.sh`, `python3 scripts/ops/execution.py --check` passes on `config/execution.yaml` containing `loop.max_concurrent_first_hops: 1`. It fails with exit 1 if `max_concurrent_first_hops` is 0, negative, non-integer, or if unknown keys are present in `loop:`. Running `python3 scripts/ops/execution.py --loop max_concurrent_first_hops` outputs `1` and exits 0.
- **SA-5 (D3, D4)** In `scripts/ci/tests/e2e_chain_test.sh` (row AT-22), executing `scripts/placement/vm-local/poll.sh --once` on candidate `intent:new` issues:
  (a) an issue carrying `intent:new` without `intake:auto` is skipped with zero claims and zero launches;
  (b) an issue carrying both `intent:new` and `intake:auto` is claimed and launched when active Athena claims count is below `max_concurrent_first_hops`;
  (c) active Athena claim count measurement normalizes claim comment authors via `(.author.login // .user.login // "")` with any trailing `[bot]` suffix stripped against `evekhm-athena-app`, tested against fixtures in both shapes (GraphQL shape with `.author.login` lacking `[bot]` and REST shape with `.user.login` carrying `[bot]`), asserting that in each case the returned count matches the true number of active claims;
  (d) when the active Athena claim count equals or exceeds `max_concurrent_first_hops`, intake launch is refused and `poll.sh: first-hop intake concurrency limit reached` is logged, asserting that the ceiling refuses a launch when the count equals the ceiling.
- **SA-6 (D5)** In `scripts/ci/tests/e2e_chain_test.sh`, row AT-20 creates its fix-round lock file under `${POLL_STATE_DIR:-...}/poll-pr-4242.lock` where `POLL_STATE_DIR` points to a test sandbox directory, and no lock file is created in `/tmp`.
- **SA-7 (D6)** In `scripts/ci/tests/e2e_chain_test.sh`, an open PR at `status:in-review` carrying a comment with `review findings: blocking` authored by a non-reviewer login (e.g. `malicious-user`) triggers zero calls to `run.sh` and no claim bypass.
- **SA-8 (D7)** In `scripts/ci/tests/e2e_chain_test.sh`, row AT-20 removes the consumption `key_file` before tick 2, and asserts that `$(cat "$LAUNCHES") == "$launches_first"` under `touch "$lock_file"`, verifying that lock contention independently prevents duplicate launches.
- **SA-9 (D8)** In `scripts/ci/tests/e2e_chain_test.sh:1310` (row AT-13), `grep -q -- "--> odyssey" <<<"$out"` executes and passes with exit 0 under GNU grep and ugrep.
- **SA-10 (D9)** In `docs/SPEC.md ## Deployment status`, step 2 of the enablement checklist documents that early supervisor startup is safe because `poll.sh` idles all queues whenever `loop.autonomous_merge: false`.
- **SA-11 (D10)** `docs/SPEC.md` records that claim holder derivation in `scripts/ci/lifecycle_advance.sh:1076` derives author identity via `(.author.login // .user.login // "")`.

## Concerns

- **Tracker API rate limits during intake concurrency checks:** Measuring active Athena claims queries `gh issue list --state open --label in-progress`. With fewer than 20 concurrent in-progress issues typically open, this check requires one API call per 30-second tick, well within GitHub's 8,300 requests-per-hour App installation token quota.
- **Backlog arming ergonomics:** Requiring `intake:auto` prevents unintentional runaway dispatches across the 37+ backlog issues. When operators desire batch processing, `gh issue edit <n> --add-label intake:auto` provides safe, deliberate activation.
- **Lock staleness vs state directory lifespan:** State directory `~/.local/state/sdlc-poller` persists across reboots on some Linux configurations. The 2-hour staleness and PID liveness cleanup introduced in #251 (`poll.sh:197-217`) prevents dead locks from permanently stalling fix rounds.

## Out of scope

- Direct implementation of code, test suites, or configuration files (owned by Daedalus at BUILD and Odyssey at IMPLEMENT).
- Modification of `scripts/ci/escalate.sh` reason codes or escalation routing.
- Modifications to `.github/workflows/lifecycle.yml` or `.github/workflows/merge-gate.yml`.
- Changes to reviewer persona prompt definitions, review schemas, or consensus ledger generation.
- Triage of external webhook events or automatic label generation.

## Open questions

none
