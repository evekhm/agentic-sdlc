# Spec: session close-out

**Issue:** #85 · **Status:** Approved (approval = merge of this PR) ·
**Author:** athena (`evekhm-athena-app[bot]`) ·
**Open questions:** none

## What is being built

A single command, `/wrap`, typed by the operator in either harness
(Claude Code or Antigravity/Gemini), that executes a deterministic
session close-out and refuses to declare a session closed while anything
remains open, stranded, unpushed, or unaccounted for.

The close-out logic is implemented once in `scripts/ops/wrap.sh` and
exposed through two thin harness doors. It enforces the repository's
lifecycle, hygiene, sync, and accounting standards at the exact moment
work is being completed. Every check reports `pass`, `fail`, `warn`, or
`fixed`; the command terminates by generating a structured handoff block
ready for the next session.

```text
scripts/ops/wrap.sh               # deterministic close-out script, git + gh only, exit 0/1/2
.claude/commands/wrap.md          # thin Claude Code door ($ARGUMENTS passed, non-aborting turn)
.agents/workflows/wrap.md         # thin Antigravity door (empirically probed in implementation)
scripts/ops/tests/wrap_test.sh    # hermetic test suite covering all exit codes and auto-repair
scripts/ci/compiler_roundtrip.sh  # or CI gate verifying wrap door drift parity
docs/SPEC.md                      # ops.wrap capability specification upsert
AGENTS.md                         # session checklist gains the terminal /wrap step
```

`scripts/ops/work.sh`, `scripts/ops/claim.sh`, `personas/**`, and
`.github/workflows/**` are **not** touched (D10). No code is written in
this design PR; this PR introduces `intent/85-session-close-out/spec.md`
alone.

## Decisions

| ID | Decision | Rationale |
|----|----------|-----------|
| D1 | **Ownership Rule (OQ1): Single fail-or-warn derivation rule.** Anything this session owns and can act on — its branches, PRs, claimed issues, run artifacts, tmp files, credential exposure, child processes — hard-fails and blocks "closed" (exit 2). Anything observed but foreign — a peer's dirty worktree, an environment-red check (e.g. #167-class), another session's unmerged PR — warns and is listed in the handoff with its owner named. Each check's fail/warn status is derived from this rule, so new checks do not reopen it. | A per-check policy table requires renegotiation for every newly discovered check or runtime quirk. The ownership boundary is clean and objective: a session cannot fix another session's dirty worktree or an environment-wide red check without violating worktree isolation, so failing on foreign states makes `/wrap` impossible to exit cleanly; conversely, allowing session-owned unpushed commits or unreleased claims to pass as warnings degrades repository discipline and strands work. Answers OQ1. |
| D2 | **Session Identity and Join Key (OQ2).** The session name in the claim comment (`Claim: <actor> (<session>), stage: <stage>...`) is the authoritative join key. Worktree lock metadata (#77/#80) is the secondary source for worktrees that never claimed. `wrap.sh` takes the session name as its required argument (`scripts/ops/wrap.sh <session-name>`). No new claim marker is added; no `work.sh` change enters this issue's file set. Branch author and GitHub App identity are explicitly rejected as join keys because parallel sessions share those identities. | `claim.sh` (#92) already mandates and records `CLAIM_SESSION` in the claim comment, creating an unambiguous machine-readable identifier on GitHub issues. App identities and branch prefixes (`athena/*`, `odyssey/*`) are shared across concurrent sessions running the same persona, making them unusable for isolating work. Worktree lock files contain PID and agent metadata from the harness, serving as a reliable fallback for unclaimed or transient child worktrees. Answers OQ2. |
| D3 | **Session Lifecycle Boundary (Intake OQ).** A session is defined by the lifetime of a single claim and dispatch lifecycle bound to a specific session name, from claim creation to handoff and close-out (`/wrap`). (a) For interactive sessions (Claude Code or Antigravity/Gemini), in-turn context compactions or multi-turn continuations do not break session identity; all actions under the session name accumulate towards the close-out obligations. (b) A resumed transcript that continues under the same claim and session name is part of that same session lifecycle; a new claim starts a distinct session. (c) For the unattended runner (#64), each runner dispatch iteration is an isolated session with its own unique session name (e.g. `runner-<id>`); Check 1 asserts that all child processes of that runner iteration have terminated, and Check 16 measures token/spend rollups for transcripts generated during that runner iteration. | Resolves the intake ambiguity regarding compaction vs resume vs runner iterations. Without an explicit definition of session boundaries, process checks (Check 1) and spend checks (Check 16) cannot know their time or process scope. |
| D4 | **Mutation Boundary (OQ3): The Single Auto-Repair and DRY_RUN Contract.** `wrap.sh` executes exactly one auto-repair mutation: when an issue claimed by this session carries a valid Done/Decided/Next/Blocked handoff comment and only the `in-progress` label was forgotten, `wrap.sh` removes `in-progress` via GitHub REST API and reports `fixed`. Every other mutation is strictly forbidden: `wrap.sh` never posts handoff comments, never prunes foreign worktrees, never edits documentation files, and never un-claims issues lacking handoffs. When `DRY_RUN=1` is passed, `wrap.sh` executes all read validations, prints `would: remove in-progress from #<n>` for the permitted mutation without calling GitHub API, and reports the would-be fix without altering tracker state. Broader auto-repair (such as pruning safe worktrees or deleting merged remote branches) is deferred. | Automatic mutations in close-out tools are dangerous: synthesizing missing handoff comments would invent unverified human/agent narrative, and auto-deleting branches or pruning worktrees risks clobbering peer work. The forgotten `in-progress` label with an already-complete handoff comment is unambiguous, safe, and mechanically verifiable. Answers OQ3. |
| D5 | **Mandatory Learnings Step (Operator Requirement).** `/wrap` includes a mandatory learnings evaluation step that cannot be bypassed or skipped silently. Candidates for learnings: rules intended to bind future sessions (in AGENTS.md, GEMINI.md, or CLAUDE.md), verified runtime/environment facts (such as measured flags or harness behaviors), traps hit during execution, or durable operational recipes. The outcome is binary and recorded: either the learning is persisted (demonstrated by a docs modification included in the session's pull request or an issue filed referencing the target document), or `/wrap` output explicitly records `learnings: no learnings to persist`. | Operational knowledge and environmental traps (such as the branch-slug/intent-folder rule #44 near-miss, merge-ref rebase vs rerun #135/#160, and work.sh keyword refusals) were repeatedly lost to ephemeral session memory until operators swept them by hand into #92. Embedding a mandatory learnings check in `/wrap` guarantees that sessions either harvest their operational discoveries or consciously attest that none occurred. |
| D6 | **V1 Check Selection and Ordering Principle.** We name the explicit v1 subset of twelve checks plus the Learnings step and establish the selection and ordering principle, deferring remaining checks by number. Principle: v1 prioritizes checks that (a) prevent immediate repository corruption, stranded work, or orphaned mutexes; (b) are fully verifiable using deterministic local git, GitHub CLI REST API, and existing repo ops tools; and (c) do not require cross-session messaging protocols, human tracker board consensus, or deep semantic reasoning across documentation history. Shipped in v1 (12 checks + Learnings step): Check 1 (child processes), Check 3 (branches pushed/synced), Check 4 (primary checkout on main), Check 5 (session PRs merged or green), Check 7 (prompted decision tracker list), Check 8 (handoff comment present & stale in-progress resolved), Check 10 (run artifact disposition footnotes), Check 12 (compiler roundtrip/drift clean on primary), Check 15 (worktree hygiene report & session safe worktrees), Check 16 (session spend measured), Check 17 (credential leak scan), Check 18 (temporary body file cleanup), plus Learnings Step. Deferred to post-v1 by number: Check 2 (peer messaging), Check 6 (merged branch deletion), Check 9 (tracker #12 checklist sync), Check 11 (cross-merge SPEC.md semantic audit), Check 13 (superseded constraint document amendments), Check 14 (lifecycle Actions run verification on main), Check 19 (cross-session memory notes). | 19 checks at once would create an unwieldy, brittle implementation. Partitioning into a high-leverage v1 core while deferring complex, protocol-dependent checks allows shipping reliable close-out enforcement immediately. |
| D7 | **Exit Code Vocabulary.** Exit codes strictly conform to `work.sh`'s established contract: `0` (Closed: all session-owned checks passed or were fixed via D4, and foreign warnings reported); `1` (Environment failure: missing dependencies `git`/`gh`/`jq`/`gawk`, missing required arguments, unreadable repository, or GitHub API authentication/network failures); `2` (Refused / Not closed: one or more session-owned checks failed). | Consistency with `scripts/ops/work.sh` (#36, #43 D23) and `claim.sh` ensures automated callers (such as the #64 autonomous loop runner and CI) can distinguish between designed refusal (uncompleted work) and execution/environmental failure. |
| D8 | **Harness Doors and Drift Gate (OQ4).** `/wrap` is exposed through two thin doors: `.claude/commands/wrap.md` for Claude Code and `.agents/workflows/wrap.md` for Antigravity (Gemini). Both doors invoke `scripts/ops/wrap.sh` passing through arguments and display the exit code without aborting the conversational turn (matching the precedent of #43 amended D16). No unverified Antigravity runtime flag or wrapper syntax is committed in this spec; the exact Antigravity wrapper invocation is determined by empirical measurement (#43-style probe) during implementation. A drift gate in CI ensures that the two doors invoke the exact same underlying script and exit convention, failing the build if either door diverges or hand-authors independent checking logic. | Re-opens and resolves #43 D16's revisit clause. Having two separate hand-authored doors without a drift gate guarantees divergence; enforcing that both delegate to a single script and gating their parity in CI guarantees cross-harness equivalence. Answers OQ4. |
| D9 | **Division of Labor: Script vs Session (Prompting Judgment).** `wrap.sh` is strictly deterministic (git + gh + bash, no LLM invocations). The script produces structured data, inventories, and check verdicts; it never drafts prose, synthesizes decisions, edits documentation, or files issues. For tasks requiring judgment (Check 7 decision reconciliation, Check 10 artifact disposition, and D5 Learnings step), the script outputs candidate lists and a structured handoff template; the calling session is responsible for composing the text, filing necessary follow-ups, or editing documents. | Determinism ends where semantic judgment begins. Allowing a close-out script to fabricate handoff prose or guess whether a discussion in chat constituted a binding decision would violate the core tenet of honest traceability. |
| D10 | **Scope Boundary.** The implementing PR is permitted to touch: `scripts/ops/wrap.sh`, `.claude/commands/wrap.md`, `.agents/workflows/wrap.md`, `scripts/ops/tests/wrap_test.sh`, `scripts/ci/compiler_roundtrip.sh` (or CI gate script adding the wrap door drift check), `docs/SPEC.md` (upserting capability `ops.wrap`), and `AGENTS.md` (updating the session checklist to include `/wrap`). Forbidden paths: `scripts/ops/work.sh`, `scripts/ops/claim.sh`, `personas/**`, `config/**`, `.github/workflows/**`. This design PR touches `intent/85-session-close-out/spec.md` alone. | Clean containment prevents regression of existing dispatch, claiming, persona compilation, and workflow mechanisms. |

## Derivation of Check Verdicts

Per D1, verdicts are not assigned by a fixed policy table. Instead, every
shipped check derives its status from the single ownership principle:
1. An anomaly detected in a resource **owned by this session** (joined by
   session name) that the session has the power to resolve evaluates to
   **`fail`** and blocks close-out (exit 2).
2. An anomaly detected in a resource that is **foreign to this session**
   (a peer's worktree, another session's PR, or an ambient environment
   defect) evaluates to **`warn`**, is recorded with its owner in the
   handoff block, and does not block close-out.
3. An anomaly where a session-claimed issue has a complete handoff
   comment but lingering `in-progress` label triggers the D4 permitted
   mutation, removes the label, and evaluates to **`fixed`**.
4. A check condition whose requirements are completely satisfied evaluates
   to **`pass`**.

The derivations for the v1 shipped checks:

- **Check 1: Background processes and subagents (In flight)**
  *Condition:* No child processes, subagents, or background tasks spawned
  by this session remain running.
  *Derivation:* Processes spawned under this session's PID/session context
  are session-owned. If any remain active, the verdict is **`fail`** (blocks
  close-out). If all have exited, the verdict is **`pass`**.
- **Check 3: Worktree branch synchronization (Pushed and synced)**
  *Condition:* Every git branch in worktrees associated with this session
  is pushed and its local HEAD equals remote HEAD.
  *Derivation:* Branches in worktrees registered under this session's name
  are session-owned. If unpushed commits or divergent refs exist, the verdict
  is **`fail`** (blocks close-out). If all session branches are fully synced,
  the verdict is **`pass`**.
- **Check 4: Primary checkout status (Pushed and synced)**
  *Condition:* The primary checkout is on clean `main` and not behind
  `origin/main`.
  *Derivation:* The primary checkout is the shared reference for all sessions
  on the machine. Uncommitted modifications or stale branches left in the
  primary checkout violate repository safety for all peers. If dirty or
  behind `origin/main`, the verdict is **`fail`** (blocks close-out). If clean
  and up to date on `main`, the verdict is **`pass`**.
- **Check 5: Session pull request status (Pushed and synced)**
  *Condition:* Every pull request opened by this session is merged, or open
  with passing CI checks and base ref `main`.
  *Derivation:* PRs originating from this session's branches are session-owned.
  If a session PR has failing CI, merge conflicts, or targets a non-main base,
  the verdict is **`fail`** (blocks close-out). If merged or open with green
  checks on `main`, the verdict is **`pass`**. Observed PRs belonging to other
  sessions that are unmerged are foreign-owned; their status evaluates to
  **`warn`** and is recorded in the handoff block.
- **Check 7: Decision accounting (Tracked, not chatted)**
  *Condition:* All material decisions reached in the session map to an issue,
  a PR, or an explicit "deferred, no tracker" entry in the handoff.
  *Derivation:* Session deliberations and commitments are session-owned. If
  decisions remain unrecorded or unaccounted for, the verdict is **`fail`**
  (blocks close-out). When all decisions are mapped or explicitly deferred,
  the verdict is **`pass`**.
- **Check 8: Claim release and handoff comment (Tracked, not chatted)**
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
- **Check 10: Run artifact bookkeeping (Tracked, not chatted)**
  *Condition:* Every run artifact generated under `runs/` during this session
  carries a disposition footnote (or a `<name>.disposition.md` sidecar for
  structured machine-readable files).
  *Derivation:* Artifacts created during this session are session-owned. If
  any artifact lacks a disposition footnote or sidecar, the verdict is
  **`fail`** (blocks close-out). When all session artifacts are reconciled,
  the verdict is **`pass`**.
- **Check 12: Persona compiler and drift parity (Documentation and state)**
  *Condition:* `scripts/sync_agents.py --check` and compiler roundtrip pass
  on the primary checkout.
  *Derivation:* Persona and prompt compilation is an absolute repository
  invariant. If source files or compiled targets drift, the verdict is
  **`fail`** (blocks close-out). If clean and validated, the verdict is
  **`pass`**.
- **Check 15: Worktree hygiene (Hygiene)**
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
- **Check 16: Session spend measurement (Hygiene)**
  *Condition:* Session spend and token metrics are computed via
  `scripts/ops/session_spend.sh` across transcripts generated during this
  session and summarized in the handoff.
  *Derivation:* If transcript usage data is successfully processed, the
  verdict is **`pass`**. If transcript logs are missing or unpriced model
  tiers are encountered, the condition reflects an environmental limitation
  rather than stranded code: the verdict is **`warn`** (recorded as a lower
  bound in the handoff) and does not block close-out.
- **Check 17: Credential leak detection (Hygiene)**
  *Condition:* No secret tokens, App private keys, or credentials appear in
  command arguments, committed diffs, or posted comment bodies.
  *Derivation:* Changes and comment bodies generated by this session are
  session-owned. If a credential pattern is discovered, the verdict is
  **`fail`** (blocks close-out). If clean, the verdict is **`pass`**.
- **Check 18: Temporary body file cleanup (Hygiene)**
  *Condition:* Temporary body files written by this session under `/tmp`
  are removed.
  *Derivation:* Temporary files authored by this session are session-owned.
  If temporary body files remain on disk, the verdict is **`fail`** (blocks
  close-out). If removed, the verdict is **`pass`**.
- **Learnings Step: Operational knowledge harvest (Mandatory)**
  *Condition:* The session explicitly evaluates and records operational
  learnings.
  *Derivation:* Operational findings are session-owned intellectual outputs.
  If the session attempts to close without recording a learning outcome, the
  verdict is **`fail`** (blocks close-out). If a learning is persisted (via a
  documentation change in the PR or an issue filed naming the target doc) OR
  if the wrap output explicitly records `learnings: no learnings to persist`,
  the verdict is **`pass`**.

## Acceptance

Every row is checkable without a model call in the hermetic test suite
`scripts/ops/tests/wrap_test.sh` and CI validation scripts:

- **AT-1 (D7, Exit 0)** When all session-owned checks pass (or are fixed
  via D4), `wrap.sh` prints `closed`, outputs the complete handoff block,
  and exits 0.
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
  CI checks or a merge conflict, `wrap.sh` reports `fail` on Check 5 and
  exits 2 (`refused: PR #<n> checks failing`).
- **AT-6 (D4, Check 8 auto-repair)** When an issue claimed by this session
  carries a valid Done/Decided/Next/Blocked handoff comment but `in-progress`
  was left set: `wrap.sh` calls the GitHub REST API to remove `in-progress`,
  prints `fixed: removed in-progress from #<n>`, and proceeds to exit 0.
- **AT-7 (D4, DRY_RUN contract)** In the scenario of AT-6, running with
  `DRY_RUN=1` prints `would: remove in-progress from #<n>`, makes zero
  GitHub API write calls, reports `fail: #<n> carries in-progress (dry-run)`,
  and exits 2.
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
- **AT-11 (D5 Learnings requirement)** If the session wrap input contains
  neither a persisted learning identifier nor `learnings: no learnings to persist`,
  `wrap.sh` reports `fail: learnings step omitted` and exits 2. If either
  is provided, it reports `pass: learnings accounted for`.
- **AT-12 (D1, Check 17 security)** If a secret token or private key pattern
  is detected in session commits, staged files, or posted comment bodies,
  `wrap.sh` reports `fail: credential exposure detected` and exits 2.
- **AT-13 (D7, Exit 1 environment)** If required binaries (`git`, `gh`, `jq`,
  `gawk`) are missing, or if `wrap.sh` is invoked outside a git repository
  or with invalid arguments, it prints an actionable error and exits 1.
- **AT-14 (D8 Doors and Drift)** `.claude/commands/wrap.md` and
  `.agents/workflows/wrap.md` invoke `scripts/ops/wrap.sh $ARGUMENTS` in
  their respective headless wrapper forms; the turn is not aborted on
  exit 2; CI drift check fails if either door diverges from delegating to
  `scripts/ops/wrap.sh`.
- **AT-15 (D10 Scope and CI)** The implementing PR updates `docs/SPEC.md`
  with capability `ops.wrap` and updates `AGENTS.md`; `scripts/ci/spec_check.sh`
  and `scripts/ci/sanitize_check.sh` pass cleanly on the diff.

## Concerns

- **Authoritative join key consistency:** `wrap.sh` relies on `CLAIM_SESSION`
  recorded in the claim comment by `claim.sh`. If a session was claimed by
  hand without a structured claim comment, `wrap.sh` must fall back cleanly
  to worktree lock metadata or prompt the operator for the explicit issue
  number, failing closed if ownership cannot be verified.
- **Narrowness of the auto-repair mutation:** D4 strictly limits mutation
  to removing `in-progress` when a valid handoff comment exists. The script
  must never attempt to synthesize missing handoff text or guess next rungs;
  unrecorded handoffs must remain hard refusals.
- **Headless door verification:** Per D8 and OQ4, the Antigravity workflow
  door cannot be assumed or copied from untested patterns. It must be
  empirically verified with a probe during implementation before merging.
- **Primary checkout read-only safety:** `wrap.sh` verifies that the primary
  checkout is clean and on `main`, but must never execute `git reset`, `git checkout`,
  or file deletions on the primary checkout or peer worktrees.

## Out of scope

- **Deferred checks:** Checks 2, 6, 9, 11, 13, 14, and 19 are deferred to
  future issues and are not part of v1 close-out verification.
- **Broader automated mutations:** Automated worktree deletion, remote branch
  pruning, and tracker #12 checkbox ticking are excluded from v1.
- **Changes to start doors:** `scripts/ops/work.sh` and `scripts/ops/claim.sh`
  remain unchanged.
- **Automated merging:** `wrap.sh` checks pull request status; human approval
  and human merge remain required to advance the repository state.

## Operator decisions

Open questions: none

All open questions were resolved by the operator on 2026-09-05:
- **OQ1 (fail vs warn):** Resolved as the single ownership derivation rule (D1).
- **OQ2 (this session's):** Resolved as session name in claim comment with
  worktree lock fallback (D2).
- **OQ3 (fix vs report):** Resolved as single auto-repair for stale
  `in-progress` with handoff comment, DRY_RUN prints would-be fix (D4).
- **OQ4 (agy door):** Resolved as one script, two thin doors, CI drift gate,
  with agy wrapper line verified by probe during implementation (D8).
- **Operator Requirement (Learnings step):** Resolved as mandatory binary
  learnings check in close-out (D5).
- **Intake questions (V1 subset & session boundary):** Resolved by naming
  the 12-check v1 subset with ordering principle and deferring 7 checks by
  number (D6), and defining the session lifecycle boundary across interactive,
  resumed, and runner contexts (D3).
