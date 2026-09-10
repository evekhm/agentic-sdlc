# Spec: session close-out

**Issue:** #85 · **Status:** Approved (approval = merge of this PR) ·
**Author:** athena (`evekhm-athena-app[bot]`) ·
**Open questions:** none

## What is being built

A single command, `/wrap`, typed by the operator in Claude Code, executing a
deterministic session close-out or refreshing a live handoff snapshot mid-flight,
refusing to declare a session closed while anything remains open, stranded,
unpushed, or unaccounted for.

The close-out logic is implemented once in `scripts/ops/wrap.sh` and exposed
through one tracked harness door (`.claude/commands/wrap.md`). Cross-harness
parity for Antigravity is dropped per #43 D16 and deferred to a follow-up
intent. The command enforces the repository lifecycle, hygiene, sync, and
accounting standards at the exact moment work is completed or snapshotted.
The command supports two modes: `--snapshot` (refresh handoff and keep working)
and bare `/wrap` (full close-out and stop). Every check reports `pass`, `fail`,
`warn`, or `fixed`. An empty session short-circuits cleanly without writing a
handoff file. A non-empty session terminates by writing
`<primary-checkout>/ops/handoffs/handoff-<seat>-<YYYY-MM-DD>[-n].txt` and
printing a verbatim resume command using `ops/waves/seat.sh <seat>`.

```text
scripts/ops/wrap.sh               # deterministic close-out script, git + gh only, exit 0/1/2, supporting --snapshot and short-circuit
.claude/commands/wrap.md          # tracked Claude Code door ($ARGUMENTS passed, non-aborting turn)
scripts/ops/tests/wrap_test.sh    # hermetic test suite covering all exit codes, modes, short-circuit, and auto-repair
.github/workflows/ci-gates.yml    # CI workflow permitting solely the wrap_test.sh execution step
scripts/ci/compiler_roundtrip.sh  # CI gate script carrying the wrap door tracking check
docs/SPEC.md                      # ops.wrap capability specification upsert
AGENTS.md                         # session checklist gains the terminal /wrap step
```

`scripts/ops/work.sh`, `scripts/ops/claim.sh`, `personas/**`, `config/**`, any
other `.github/workflows/**` files, and any other edits to `ci-gates.yml` are
strictly forbidden (D10, D15). No code is written in this design PR; this PR
introduces `intent/85-session-close-out/spec.md` alone.

## Decisions

| ID | Decision | Rationale |
|----|----------|-----------|
| D1 | **Ownership Rule (OQ1): Three-way derivation rule (resolving Verifier V1).** Every check evaluates to one of four states (`pass`, `fail`, `warn`, `fixed`) derived from an exhaustive three-way partition: (1) An anomaly in a resource owned and actionable by this session evaluates to **`fail`** and blocks close-out (exit 2). (2) An anomaly in a foreign resource (a peer session's dirty worktree, an unmerged foreign PR) evaluates to **`warn`**, is recorded with its owner in the handoff block, and does not block close-out. (3) An anomaly in a resource owned by this session but non-actionable due to an ambient environment defect (e.g. an infrastructure-red check such as #167-class runner outages, or an unpriced model tier in spend reporting) evaluates to **`warn`**, is recorded with its cause in the handoff block, and does not block close-out. A session-claimed issue with a complete handoff comment but lingering `in-progress` label triggers the D4 auto-repair and evaluates to **`fixed`**. | A binary fail/warn rule leaves ambient environment failures undefined. If an environment failure on a session PR hard-fails, sessions cannot wrap during infrastructure outages (#167). The three-way partition establishes an exhaustive derivation rule covering ambient failures cleanly. Answers OQ1 and Verifier V1. |
| D2 | **Session Identity and Join Key (OQ2).** The session name in the claim comment (`Claim: <actor> (<session>), stage: <stage>...`) is the authoritative join key. Worktree lock metadata (#77/#80) is the secondary source for worktrees that never claimed. `wrap.sh` takes the session name as its required argument (`scripts/ops/wrap.sh <session-name>`). No new claim marker is added; no `work.sh` change enters this issue's file set. Branch author and GitHub App identity are rejected as join keys because parallel sessions share those identities. | `claim.sh` (#92) mandates and records `CLAIM_SESSION` in the claim comment, creating an unambiguous machine-readable identifier on GitHub issues. App identities and branch prefixes (`athena/*`, `odyssey/*`) are shared across concurrent sessions running the same persona, making them unusable for isolating work. Worktree lock files contain PID and agent metadata from the harness, serving as a reliable fallback for unclaimed or transient child worktrees. Answers OQ2. |
| D3 | **Session Lifecycle Boundary (Intake OQ).** A session is defined by the lifetime of a single claim and dispatch lifecycle bound to a specific session name, from claim creation to handoff and close-out (`/wrap`). (a) For interactive sessions (Claude Code), in-turn context compactions or multi-turn continuations do not break session identity; all actions under the session name accumulate towards the close-out obligations. (b) A resumed transcript continuing under the same claim and session name is part of that same session lifecycle; a new claim starts a distinct session. (c) For the unattended runner (#64), each runner dispatch iteration is an isolated session with its own unique session name (e.g. `runner-<id>`); Check 1 asserts that all child processes of that runner iteration have terminated, and Check 16 measures token/spend rollups for transcripts generated during that runner iteration. | Resolves the intake ambiguity regarding compaction vs resume vs runner iterations. Without an explicit definition of session boundaries, process checks (Check 1) and spend checks (Check 16) cannot establish their temporal or process scope. |
| D4 | **Mutation Boundary (OQ3): The Single Auto-Repair and DRY_RUN Contract (resolving Verifier V2).** `wrap.sh` executes exactly one auto-repair mutation: when an issue claimed by this session carries a valid Done/Decided/Next/Blocked handoff comment and only the `in-progress` label was forgotten, `wrap.sh` removes `in-progress` via GitHub REST API and reports `fixed`. Every other mutation is strictly forbidden: `wrap.sh` never posts handoff comments, never prunes foreign worktrees, never edits documentation files, and never un-claims issues lacking handoffs. Under `DRY_RUN=1`, `wrap.sh` executes all read validations, prints `would: remove in-progress from #<n>` without modifying GitHub API state, reports `fail: #<n> carries in-progress (dry-run)`, and exits 2. Broader auto-repair (such as pruning safe worktrees or deleting merged remote branches) is deferred. | Automatic mutations in close-out tools risk data loss: synthesizing missing handoff comments would invent unverified narrative, and auto-deleting branches or pruning worktrees risks clobbering peer work. The forgotten `in-progress` label with an already-complete handoff comment is safe and mechanically verifiable. In dry-run mode, because no mutation occurs, the session remains unclosed and must exit 2. Answers OQ3 and Verifier V2. |
| D5 | **Mandatory Learnings Step and Interface.** `/wrap` includes a mandatory learnings evaluation step that cannot be bypassed silently during close-out. The evaluation interface is the `WRAP_LEARNINGS` environment variable: (a) If `WRAP_LEARNINGS` is unset or empty during close-out mode, `wrap.sh` reports `fail: learnings step omitted` and exits 2. (b) If `WRAP_LEARNINGS` is set to `none` or `no learnings to persist`, this explicitly attests that the session identified no durable operational discoveries; `wrap.sh` reports `pass: learnings accounted for`. (c) If `WRAP_LEARNINGS` contains a persisted learning identifier (such as a documentation file modified in the pull request or an issue reference naming the target document), `wrap.sh` reports `pass: learnings accounted for`. In `--snapshot` mode, evaluation of `WRAP_LEARNINGS` is skipped because the session remains active. AT-1 supplies an explicit attestation (`WRAP_LEARNINGS="none"`) to pass close-out, aligning AT-1 and AT-11 without contradiction. | Operational knowledge and environmental traps (such as the branch-slug/intent-folder rule #44 near-miss, merge-ref rebase vs rerun #135/#160, and work.sh keyword refusals) were repeatedly lost to ephemeral session memory until operators swept them by hand into #92. Embedding a mandatory learnings check in `/wrap` guarantees that sessions either harvest their operational discoveries or consciously attest that none occurred. |
| D6 | **V1 Check Selection and Ordering Principle.** We name the explicit v1 subset of twelve checks plus the Learnings step and establish the selection and ordering principle, deferring remaining checks by number. Principle: v1 prioritizes checks that (a) prevent immediate repository corruption, stranded work, or orphaned mutexes; (b) are fully verifiable using deterministic local git, GitHub CLI REST API, and existing repo ops tools; and (c) do not require cross-session messaging protocols, human tracker board consensus, or deep semantic reasoning across documentation history. Shipped in v1 (12 checks + Learnings step): Check 1 (child processes), Check 3 (branches pushed/synced), Check 4 (primary checkout on main), Check 5 (session PRs merged or green), Check 7 (prompted decision tracker list), Check 8 (handoff comment present & stale in-progress resolved), Check 10 (run artifact disposition footnotes), Check 12 (compiler roundtrip and drift clean on primary: both `python3 scripts/sync_agents.py --check` and `bash scripts/ci/compiler_roundtrip.sh` must pass), Check 15 (worktree hygiene report & session safe worktrees), Check 16 (session spend measured), Check 17 (credential leak scan), Check 18 (temporary body file cleanup), plus Learnings Step. Deferred to post-v1 by number: Check 2 (peer messaging), Check 6 (merged branch deletion), Check 9 (tracker #12 checklist sync), Check 11 (cross-merge SPEC.md semantic audit), Check 13 (superseded constraint document amendments), Check 14 (lifecycle Actions run verification on main), Check 19 (cross-session memory notes). | 19 checks at once would create an unwieldy implementation. Partitioning into a high-leverage v1 core while deferring complex, protocol-dependent checks allows shipping reliable close-out enforcement immediately. Check 12 requires both the drift check and the full roundtrip suite to prove compiler integrity. |
| D7 | **Exit Code Vocabulary.** Exit codes strictly conform to `work.sh`'s established contract: `0` (Closed / Clean: all session-owned checks passed or were fixed via D4, foreign warnings reported, or short-circuited clean); `1` (Environment failure: missing dependencies `git`/`gh`/`jq`/`gawk`, missing required arguments, unreadable repository, or GitHub API authentication/network failures); `2` (Refused / Not closed: one or more session-owned checks failed, or dry-run would-fix encountered). | Consistency with `scripts/ops/work.sh` (#36, #43 D23) and `claim.sh` ensures automated callers (such as the #64 autonomous loop runner and CI) distinguish between designed refusal (uncompleted work) and execution/environmental failure. |
| D8 | **Harness Door: Claude Code Only (Reversal of Cross-Harness Parity per #43 D16).** The scope of #85 is Claude Code only. All Antigravity implementation obligations are dropped, reversing earlier cross-harness parity requirements. #43 D16 established that `.agents/workflows/` is an explicit non-goal for v1 ("The `.agents/workflows/` twin is an explicit non-goal for v1: dispatch is driven from the operator's interactive session, and two hand-authored files with no gate between them is the drift the compiler exists to prevent. Revisit when the presenter dispatches from the IDE", with acceptance clause "no file under `.agents/workflows/` is added"). Furthermore, `.agents/workflows/` does not exist in the repository, is excluded from compiler target directories (`scripts/sync_agents.py:751`), and has no demonstrated mechanism for `$ARGUMENTS` interpolation or pre-turn `!` bash execution. Antigravity support is deferred to a follow-up intent pending #43 D16 revisit. The single door is `.claude/commands/wrap.md`, tracked in git past `.gitignore:37 .claude/` via `git add -f`, following the precedent of `.claude/commands/work.md`. The door body takes the tested POC from issue comment 5610016589 as-is. A CI check in `scripts/ci/compiler_roundtrip.sh` (or CI gate script) verifies that `.claude/commands/wrap.md` exists and invokes `scripts/ops/wrap.sh`. | Reconciles #85 with merged decision #43 D16. Tracked doors with a CI check prevent door removal or broken invocation. Using the tested POC comment as the verbatim source ensures tested functionality is preserved. Answers R5 and resolves door parity scope. |
| D9 | **Division of Labor: Script vs Session (Prompting Judgment).** `wrap.sh` is strictly deterministic (git + gh + bash, no LLM invocations). The script produces structured data, inventories, and check verdicts; it never drafts prose, synthesizes decisions, edits documentation, or files issues. For tasks requiring judgment (Check 7 decision reconciliation, Check 10 artifact disposition, handoff narrative composition, and D5 Learnings step), the script outputs candidate lists and a structured handoff template; the calling session is responsible for composing the text, filing necessary follow-ups, or editing documents. | Determinism ends where semantic judgment begins. Allowing a close-out script to fabricate handoff prose or guess whether a discussion in chat constituted a binding decision would violate honest traceability. |
| D10 | **Scope Boundary.** The implementing PR is permitted to touch: `scripts/ops/wrap.sh`, `.claude/commands/wrap.md`, `scripts/ops/tests/wrap_test.sh`, `.github/workflows/ci-gates.yml` (permitted solely to add the wrap_test.sh step, per D15), `scripts/ci/compiler_roundtrip.sh` (or CI gate script adding the wrap door check), `docs/SPEC.md` (upserting capability `ops.wrap`), `AGENTS.md` (updating the session checklist to include `/wrap`), and `intent/85-session-close-out/spec.md`. Forbidden paths: `scripts/ops/work.sh`, `scripts/ops/claim.sh`, `personas/**`, `config/**`, any other `.github/workflows/**` files, and any other edits to `ci-gates.yml`. This design PR touches `intent/85-session-close-out/spec.md` alone. | Clean containment prevents regression of existing dispatch, claiming, persona compilation, and workflow mechanisms. |
| D11 | **Two Execution Modes: Snapshot vs Close-Out (R2).** `/wrap` supports exactly two modes: (a) **`--snapshot`**: writes or refreshes the handoff file mid-flight and allows the session to keep working. It marks line 1 of the file: `SNAPSHOT (session still running, written HH:MMZ)`, and skips close-out-only steps (Check 1 background processes, Check 4 primary main check, Check 5 PR checks, Check 8 label removal, Check 10 artifact footnotes, Check 18 tmp file cleanup, D5 Learnings step, and the exit report). (b) **bare `/wrap`**: executes the full close-out across all 12 checks plus Learnings, replaces the snapshot header on line 1, outputs the full report, and terminates the session. Both modes write to the exact same file path (`<primary-checkout>/ops/handoffs/handoff-<seat>-<YYYY-MM-DD>[-n].txt`). A close-out is the final snapshot plus reconciliation. Snapshots overwrite the session's own file in place; a session leaves exactly one handoff file behind regardless of snapshot frequency. Suffix `-n` increments only if a different session previously wrote today's file for that seat. | Session state is vulnerable before a crash or unplanned termination. Snapshotting frequently allows cheap checkpointing without incurring close-out teardown overhead. Overwriting in place prevents file sprawl while guaranteeing a single authoritative handoff per session. Answers R2. |
| D12 | **Mode-Gated Probes and Empty-Session Short-Circuit (R3).** Deterministic probes are strictly gated on execution mode to enforce cost discipline: (a) Cheap probes (`git status --short --branch`, side-channel context/spend line) run in both modes. (b) Expensive network and worktree probes (`git fetch origin`, `git log HEAD..origin/main`, `gh pr list --author @me`, `scripts/ops/worktrees.sh`, recent handoff scans) run in close-out mode only. (c) **Short-circuit**: If the state probes show a clean tree, no ref divergence from `origin/main`, no open PRs authored by this session, and the session produced no decisions, no `runs/` artifacts, and no tracker modifications, `/wrap` outputs a single-line summary (`nothing to hand off: session clean and produced no state`), **writes no handoff file**, and exits 0 immediately. `wrap.sh` must not re-derive facts already gathered in the state probe. Acceptance tests assert exact probe invocation counts via a PATH shim over `git`, `gh`, and `worktrees.sh` logging to an invocation file. | Measured on an empty session (`44579d00`), ungated probes added 12 tool calls, 16,355 tokens, and $0.41 to close out a session that did nothing. Gating dropped snapshot probes from 3.90s / 6,605 bytes to 0.00s / 24 bytes. Short-circuiting empty sessions eliminates wasteful handoff files for sessions that have no successor problem. Answers R3. |
| D13 | **Seat Resolution Order, Resume Loop, and Path Contract (R4).** Handoff path is always absolute into the primary checkout: `<primary-checkout>/ops/handoffs/handoff-<seat>-<YYYY-MM-DD>[-n].txt` (a relative path written from a worktree dies if the worktree is removed). The seat name is the authoritative resume token. Seat resolution order: (1) CLI argument (`/wrap <seat-or-slug>`), (2) `$CLAUDE_SEAT` (or environment seat variable), (3) existing `handoff-<slug>-<today>.txt` written by this session, (4) otherwise mint a short kebab-case slug naming the work (`harness-statusline`, `poller-fix-round`). Ad-hoc slugs resolve by exact match with no fallback (typo refuses). The command concludes by printing the verbatim copyable resume command: `handoff: <absolute-path>\nresume: ops/waves/seat.sh <seat>\nsession: <session-id>`. The report points to `ops/waves/seat.sh --list` and `ops/waves/seat.sh --last` (#259). Resuming means launching a fresh session primed with the handoff; `claude --resume` is rejected because it replays full transcripts into context and incurs first-turn token charges. | Absolute paths ensure survival across worktree lifecycles. Stable seat tokens ensure exact work resumption without remembering file paths. Fresh sessions primed with handoff files eliminate full transcript replay costs. Answers R4. |
| D14 | **Successor Priming Scope Handoff to #330.** Successor priming via the `SessionStart` hook in `.claude/settings.json` is owned by #330. That configuration path is outside D10's permitted list, so the priming half is unbuildable within this issue's scope boundary. #85 owns writing and reading the handoff artifact; #330 owns injecting it into successor sessions. | Preserves clear architectural boundaries and prevents scope creep into harness configuration files. Resolves the unbuildable priming requirement cleanly. |
| D15 | **CI Test Suite Registration (Resolving D10 Workflow Gap).** D10 is widened by exactly one path: `.github/workflows/ci-gates.yml`, permitted solely to wire the execution of `scripts/ops/tests/wrap_test.sh` into the test job. | `.github/workflows/ci-gates.yml` enumerates test suites explicitly without globs. Without this narrow addition, `wrap_test.sh` would remain unregistered in CI, reducing acceptance test passage to unverified local assertions and reintroducing silent regression risk. All other workflow files and any other edits to `ci-gates.yml` remain strictly forbidden. |

## Related Dependencies (Verification Requirement)

`ops/waves/seat.sh` and `newest-handoff.sh` are untracked since `.gitignore:35`
excludes `ops/`. They resolve the handoff filename that `wrap.sh` writes. If the
convention drifts, resume breaks silently and no CI test can catch it. During
the implement stage, the implementer must execute a verification step by hand
once against the real `seat.sh` to confirm filename resolution compatibility.

## Derivation of Check Verdicts

Per D1, verdicts are derived from the three-way ownership principle:
1. An anomaly detected in a resource **owned and actionable by this session**
   evaluates to **`fail`** and blocks close-out (exit 2).
2. An anomaly detected in a resource that is **foreign to this session**
   (a peer's worktree, another session's PR) evaluates to **`warn`**, is
   recorded with its owner in the handoff block, and does not block close-out.
3. An anomaly detected in a resource owned by this session that is **non-actionable
   due to an ambient environment defect** (e.g. #167-class infrastructure check
   failures, unpriced model tiers) evaluates to **`warn`**, is recorded in the
   handoff block, and does not block close-out.
4. An anomaly where a session-claimed issue has a complete handoff comment but
   lingering `in-progress` label triggers the D4 permitted mutation, removes
   the label, and evaluates to **`fixed`**.
5. A check condition whose requirements are completely satisfied evaluates to
   **`pass`**.

In `--snapshot` mode (D11), checks marked *(close-out only)* are skipped to
minimize overhead and latency.

The derivations for the v1 shipped checks:

- **Check 1: Background processes and subagents (In flight)** *(close-out only)*
  *Condition:* No child processes, subagents, or background tasks spawned
  by this session remain running.
  *Derivation:* Processes spawned under this session's PID or session context
  are session-owned. If any remain active, the verdict is **`fail`** (blocks
  close-out). If all have exited, the verdict is **`pass`**.
- **Check 3: Worktree branch synchronization (Pushed and synced)** *(both modes)*
  *Condition:* Every git branch in worktrees associated with this session
  is pushed and its local HEAD equals remote HEAD.
  *Derivation:* Branches in worktrees registered under this session's name
  are session-owned. If unpushed commits or divergent refs exist, the verdict
  is **`fail`** (blocks close-out). If all session branches are fully synced,
  the verdict is **`pass`**.
- **Check 4: Primary checkout status (Pushed and synced)** *(close-out only)*
  *Condition:* The primary checkout is on clean `main` and not behind
  `origin/main`.
  *Derivation:* The primary checkout is the shared reference for all sessions
  on the machine. Uncommitted modifications or stale branches left in the
  primary checkout violate repository safety for all peers. If dirty or
  behind `origin/main`, the verdict is **`fail`** (blocks close-out). If clean
  and up to date on `main`, the verdict is **`pass`**.
- **Check 5: Session pull request status (Pushed and synced)** *(close-out only)*
  *Condition:* Every pull request opened by this session is merged, or open
  with passing CI checks and base ref `main`.
  *Derivation:* PRs originating from this session's branches are session-owned.
  If a session PR has failing CI checks due to test failures or merge conflicts,
  the verdict is **`fail`** (blocks close-out). If a PR check is failing due to
  a documented ambient environment defect (such as #167 runner infrastructure),
  it is non-actionable by this session and evaluates to **`warn`** with root
  cause recorded in the handoff. If merged or open with green checks on `main`,
  the verdict is **`pass`**. Observed PRs belonging to other sessions that are
  unmerged are foreign-owned; their status evaluates to **`warn`** and is
  recorded in the handoff block.
- **Check 7: Decision accounting (Tracked decisions)** *(both modes)*
  *Condition:* All material decisions reached in the session map to an issue,
  a PR, or an explicit "deferred, no tracker" entry in the handoff.
  *Derivation:* Session deliberations and commitments are session-owned. If
  decisions remain unrecorded or unaccounted for, the verdict is **`fail`**
  (blocks close-out). When all decisions are mapped or explicitly deferred,
  the verdict is **`pass`**.
- **Check 8: Claim release and handoff comment (Tracked mutexes)** *(close-out only)*
  *Condition:* Every issue claimed under this session's name carries a valid
  Done / Decided / Next / Blocked handoff comment and no stale `in-progress`
  label.
  *Derivation:* Issues claimed by this session are session-owned mutexes.
  (a) If a valid handoff comment exists and only `in-progress` was left set,
  it meets the D4 criteria: `wrap.sh` removes the label, the verdict evaluates
  to **`fixed`**, and close-out proceeds. (b) If no valid handoff comment
  exists, it is an unresolved session-owned omission: the verdict is
  **`fail`** (blocks close-out). (c) If a valid handoff exists and `in-progress`
  is already cleared, the verdict is **`pass`**.
- **Check 10: Run artifact bookkeeping (Tracked artifacts)** *(close-out only)*
  *Condition:* Every run artifact generated under `runs/` during this session
  carries a disposition footnote (or a `<name>.disposition.md` sidecar for
  structured machine-readable files).
  *Derivation:* Artifacts created during this session are session-owned. If
  any artifact lacks a disposition footnote or sidecar, the verdict is
  **`fail`** (blocks close-out). When all session artifacts are reconciled,
  the verdict is **`pass`**.
- **Check 12: Persona compiler and drift parity (Documentation and state)** *(close-out only)*
  *Condition:* `scripts/sync_agents.py --check` and `scripts/ci/compiler_roundtrip.sh`
  both pass on the primary checkout.
  *Derivation:* Persona and prompt compilation is an absolute repository
  invariant. Both checks must execute and succeed. If source files or compiled
  targets drift, or if compiler roundtrip checks fail, the verdict is
  **`fail`** (blocks close-out). If both pass cleanly, the verdict is **`pass`**.
- **Check 15: Worktree hygiene (Hygiene)** *(close-out only)*
  *Condition:* Worktrees evaluated via `scripts/ops/worktrees.sh` conform to
  hygiene rules.
  *Derivation:* Partitioned strictly by ownership:
  (a) Worktrees created by this session that are dirty or unpushed when
  attempting close-out are session-owned: the verdict is **`fail`** (blocks
  close-out).
  (b) Worktrees created by this session that are `safe` evaluate to **`pass`**
  and are reported as safe for pruning.
  (c) Worktrees belonging to peer sessions that are dirty, unpushed, or locked
  are foreign-owned: the verdict is **`warn`**, and they are listed in the
  handoff block with owner and status without blocking close-out.
- **Check 16: Session spend measurement (Hygiene)** *(both modes)*
  *Condition:* Session spend and token metrics are gathered from the side-channel
  file `~/.claude/context/<session>.json` and, in close-out mode, computed via
  `scripts/ops/session_spend.sh` across transcripts generated during this session.
  *Derivation:* If transcript usage data is successfully processed, the
  verdict is **`pass`**. If transcript logs are missing or unpriced model
  tiers are encountered, the condition reflects an environmental limitation:
  the verdict is **`warn`** (recorded with lower bound metrics in the handoff)
  and does not block close-out.
- **Check 17: Credential leak detection (Hygiene)** *(both modes)*
  *Condition:* No secret tokens, App private keys, or credentials appear in
  command arguments, committed diffs, or posted comment bodies.
  *Derivation:* Changes and comment bodies generated by this session are
  session-owned. If a credential pattern is discovered, the verdict is
  **`fail`** (blocks close-out). If clean, the verdict is **`pass`**.
- **Check 18: Temporary body file cleanup (Hygiene)** *(close-out only)*
  *Condition:* Temporary body files written by this session under `/tmp`
  are removed.
  *Derivation:* Temporary files authored by this session are session-owned.
  If temporary body files remain on disk, the verdict is **`fail`** (blocks
  close-out). If removed, the verdict is **`pass`**.
- **Learnings Step: Operational knowledge harvest (Mandatory)** *(close-out only)*
  *Condition:* The session explicitly evaluates and records operational
  learnings via the `WRAP_LEARNINGS` interface.
  *Derivation:* Operational findings are session-owned intellectual outputs.
  If `WRAP_LEARNINGS` is unset or empty during close-out, the verdict is
  **`fail`** (blocks close-out). If `WRAP_LEARNINGS="none"` (or `no learnings to persist`)
  is provided, or if a persisted learning identifier is supplied, the verdict
  is **`pass`**.

## Acceptance

Every row is checkable without a model call in the hermetic test suite
`scripts/ops/tests/wrap_test.sh` and CI validation scripts:

- **AT-1 (D7, Exit 0)** When all session-owned checks pass (or are fixed
  via D4) and `WRAP_LEARNINGS="none"` is attested, `wrap.sh` prints exact
  status token `closed` on its own line (`^closed$` or `status: closed`),
  outputs the complete handoff block, and exits 0. Asserted via exact regex
  match that rejects substrings such as `not closed`.
- **AT-2 (D1, Check 1)** If a child process or background subagent belonging
  to the session PID tree is active, `wrap.sh` reports `fail` on Check 1 and
  exits 2 (`refused: child processes still running`).
- **AT-3 (D1, Check 3)** If a git branch in this session's worktree contains
  unpushed commits, `wrap.sh` reports `fail` on Check 3 and exits 2
  (`refused: unpushed commits on <branch>`).
- **AT-4 (D1, Check 4)** If the primary checkout has uncommitted changes or
  is behind `origin/main`, `wrap.sh` reports `fail` on Check 4 and exits 2
  (`refused: primary checkout dirty or behind origin/main`).
- **AT-5 (D1, Check 5)** If a pull request opened by this session has failing
  CI checks due to code defects, `wrap.sh` reports `fail` on Check 5 and
  exits 2 (`refused: PR #<n> checks failing`). If the failure is an ambient
  environment failure (#167-class), it reports `warn` and exits 0 if all
  other session checks pass.
- **AT-6 (D4, Check 8 auto-repair)** When an issue claimed by this session
  carries a valid Done/Decided/Next/Blocked handoff comment but `in-progress`
  was left set: `wrap.sh` calls the GitHub REST API to remove `in-progress`,
  prints `fixed: removed in-progress from #<n>`, and proceeds to exit 0.
- **AT-7 (D4, DRY_RUN contract)** In the scenario of AT-6, running with
  `DRY_RUN=1` prints `would: remove in-progress from #<n>`, reports
  `fail: #<n> carries in-progress (dry-run)`, and exits 2. Asserted via a
  `PATH` shim over `gh` logging invocations to verify zero mutating GitHub
  REST API calls (`POST`, `PATCH`, `DELETE`).
- **AT-8 (D1, Check 8 refusal)** When an issue claimed by this session lacks
  a valid Done/Decided/Next/Blocked handoff comment, `wrap.sh` makes no label
  modifications, reports `fail: missing handoff comment on #<n>`, and exits 2.
- **AT-9 (D1, Check 10)** If a run artifact under `runs/` generated during
  the session lacks a disposition footnote (or sidecar), `wrap.sh` reports
  `fail: artifact <path> missing disposition` and exits 2.
- **AT-10 (D1, Check 15 peer warning)** If a peer session's worktree is
  dirty, locked, or unpushed, `wrap.sh` outputs `warn: peer worktree <path>
  held by <peer>`, includes it in the handoff block, and exits 0 if all
  session-owned checks pass.
- **AT-11 (D5 Learnings requirement)** In close-out mode, if `WRAP_LEARNINGS`
  is unset or empty, `wrap.sh` reports `fail: learnings step omitted` and
  exits 2. When `WRAP_LEARNINGS` is provided with `none` or a persisted learning
  identifier, `wrap.sh` reports `pass: learnings accounted for`.
- **AT-12 (D1, Check 17 security)** If a secret token or private key pattern
  is detected in session commits, staged files, or posted comment bodies,
  `wrap.sh` reports `fail: credential exposure detected` and exits 2.
- **AT-13 (D7, Exit 1 environment)** If required binaries (`git`, `gh`, `jq`,
  `gawk`) are missing (tested via a `PATH` shim omitting the binary), or if
  `wrap.sh` is invoked outside a git repository (tested in a non-git directory),
  or invoked with missing required arguments, it prints an actionable error and
  exits 1.
- **AT-14 (D8 Claude Door)** `.claude/commands/wrap.md` is tracked in the
  repository past gitignore (`git ls-files .claude/commands/wrap.md` succeeds);
  it invokes `scripts/ops/wrap.sh $ARGUMENTS` in its non-aborting execution
  form; the turn is not aborted on exit 2; and the CI door tracking check
  succeeds.
- **AT-15 (D10 Scope and CI)** The implementing PR updates `docs/SPEC.md`
  with capability `ops.wrap`, updates `AGENTS.md`, and adds the `wrap_test.sh`
  execution step to `.github/workflows/ci-gates.yml` per D15;
  `scripts/ci/spec_check.sh` and `scripts/ci/sanitize_check.sh` pass cleanly on
  the diff.
- **AT-16 (D11 Snapshot Mode)** Invoking `/wrap --snapshot` runs cheap probes,
  skips close-out-only checks (Checks 1, 4, 5, 8 label removal, 10, 18, and
  Learnings), writes or refreshes
  `<primary-checkout>/ops/handoffs/handoff-<seat>-<date>[-n].txt`, leaves
  the session running, and exits 0. The test resolves, opens, and reads the
  handoff file from disk to assert line 1 begins with
  `SNAPSHOT (session still running, written `. A second snapshot invocation in
  the same session overwrites the file in place without incrementing suffix `-n`.
- **AT-17 (D12 Short-Circuit on Empty Session)** When `/wrap` runs against an
  empty session where git status is clean, ref is up to date with `origin/main`,
  no session PRs exist, and no decisions, run artifacts, or tracker claims
  were produced: `wrap.sh` outputs a single-line summary and exits 0. Asserted
  via filesystem verification that zero handoff files are written under
  `ops/handoffs/`.
- **AT-18 (D12 Probe Gating Count)** Under `--snapshot`, network probes (`git fetch`,
  `gh pr list`) and worktree enumeration (`scripts/ops/worktrees.sh`) do not
  execute. Asserted via a `PATH` shim over `git`, `gh`, and `worktrees.sh`
  logging to an execution file, verifying probe counts match the minimal snapshot
  budget.
- **AT-19 (D13 Seat Resolution and Resume Block)** Resolves the seat in priority
  order (arg -> `$CLAUDE_SEAT` -> existing handoff -> minted kebab-case slug);
  an ad-hoc slug that does not match an existing handoff refuses with exit 2;
  terminating output prints the verbatim resume block with absolute path,
  `ops/waves/seat.sh <seat>`, and session ID; report points to
  `ops/waves/seat.sh --list` and `ops/waves/seat.sh --last`. Asserted across all
  four resolution paths and output pointers.

## Concerns

- **Authoritative join key consistency:** `wrap.sh` relies on `CLAIM_SESSION`
  recorded in the claim comment by `claim.sh`. If a session was claimed by
  hand without a structured claim comment, `wrap.sh` falls back to worktree
  lock metadata or prompts the operator for the explicit issue number, failing
  closed if ownership cannot be verified.
- **Narrowness of the auto-repair mutation:** D4 strictly limits mutation
  to removing `in-progress` when a valid handoff comment exists. The script
  never synthesizes missing handoff text or guesses next rungs; unrecorded
  handoffs remain hard refusals.
- **CI test suite wiring scope restriction:** D15 widens D10 solely to wire
  `wrap_test.sh` in `.github/workflows/ci-gates.yml`. Modifying any other workflow
  or adding additional edits to `ci-gates.yml` is forbidden.
- **Handoff file resolution drift verification:** Because `ops/waves/seat.sh`
  and `newest-handoff.sh` are untracked in `ops/`, implementers must manually
  verify handoff path and filename resolution against the live script to prevent
  untested drift.
- **Primary checkout read-only safety:** `wrap.sh` verifies that the primary
  checkout is clean and on `main`, but never executes `git reset`, `git checkout`,
  or file deletions on the primary checkout or peer worktrees.

## Out of scope

- **Antigravity harness support:** Dropped per #43 D16; deferred to a follow-up
  intent.
- **Successor priming injection:** `SessionStart` hook configuration in
  `.claude/settings.json` is owned by #330.
- **Deferred checks:** Checks 2, 6, 9, 11, 13, 14, and 19 are deferred to
  future issues and are excluded from v1 close-out verification.
- **Broader automated mutations:** Automated worktree deletion, remote branch
  pruning, and tracker #12 checkbox ticking are excluded from v1.
- **Changes to start doors:** `scripts/ops/work.sh` and `scripts/ops/claim.sh`
  remain unchanged.
- **Automated merging:** `wrap.sh` checks pull request status; human approval
  and human merge remain required to advance the repository state.
- **Automated snapshot triggers:** Automatic background snapshot cadence
  without operator typing `/wrap` is owned by #329 and excluded from this issue.

## Operator decisions

Open questions: none

All open questions and requirements were resolved by the operator across the
initial spec review (2026-09-05), amendment requirements R1 through R5 (2026-09-10),
and the amendment round 2 brief and addendum (2026-09-10):
- **Scope Cut (Claude Code only):** Dropped all Antigravity implementation
  obligations, reversing earlier cross-harness parity requirements. Aligns with
  merged decision #43 D16 (which designated `.agents/workflows/` an explicit
  non-goal for v1). Antigravity support is deferred to a follow-up intent (D8).
- **OQ1 (fail vs warn):** Resolved as the comprehensive three-way ownership
  derivation rule covering owned actionable, foreign, and ambient environment
  defects (D1).
- **OQ2 (this session's):** Resolved as session name in claim comment with
  worktree lock fallback (D2).
- **OQ3 (fix vs report):** Resolved as single auto-repair for stale
  `in-progress` with handoff; DRY_RUN prints would-be fix and exits 2 (D4).
- **OQ4 (harness door):** Resolved as single tracked door `.claude/commands/wrap.md`
  taking tested POC in comment 5610016589 as-is, tracked past gitignore via
  `git add -f` (D8).
- **Learnings step interface:** Resolved by defining `WRAP_LEARNINGS` environment
  interface, requiring explicit attestation in close-out mode (`none` or persisted
  learning) and refusing unset values with exit 2, while skipping evaluation in
  snapshot mode (D5).
- **Intake questions (V1 subset & session boundary):** Resolved by naming
  the 12-check v1 subset with ordering principle and deferring 7 checks by
  number (D6), and defining the session lifecycle boundary across interactive,
  resumed, and runner contexts (D3). Check 12 requires both `sync_agents.py --check`
  and `compiler_roundtrip.sh` (D6).
- **Operator Requirement R2 (Two modes):** Resolved as `--snapshot` and bare
  `/wrap`, sharing identical path, overwriting in place, and marking line 1
  with snapshot timestamp (D11).
- **Operator Requirement R3 (Probe gating & short-circuit):** Resolved as
  mode-gated probes (cheap probes in snapshot, expensive in close-out) and
  zero-file short-circuit for empty clean sessions (D12).
- **Operator Requirement R4 (Resume command):** Resolved as verbatim
  copyable resume block using `ops/waves/seat.sh <seat>`, stable seat resolution
  order, and pointers to `seat.sh --list`/`--last`, rejecting transcript replay
  resume commands (D13).
- **Operator Requirement R5 (Door tracking):** Resolved by tracking
  `.claude/commands/wrap.md` in repository past gitignore via `git add -f` (D8).
- **Successor Priming:** Handoff of priming scope to #330; #85 owns writing and
  reading handoffs, while #330 owns hook injection (D14).
- **CI Test Suite Registration:** Widened D10 by `.github/workflows/ci-gates.yml`
  solely to wire `wrap_test.sh` in the CI test job, preventing unverified
  laptop claims (D15).
