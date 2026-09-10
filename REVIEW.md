# Review policy — protocol v2, the severity funnel

The policy the two reviewer personas compile against. Persona sources
reference this file; they never restate it. Where a compiled persona,
a workflow prompt, or a posting script disagrees with this document,
the disagreement is a bug in the derived copy.

**In one line:** Atlas reviews every PR at every rung; Argus joins at the code gate, on trust-bearing paths, and on deep-review grants (config/execution.yaml); after that only security and high findings block, security alone needs both reviewers to agree, rounds cap at three; and a human can merge at any time, with anything still open becoming a follow-up issue instead of another round.

Scope: this file is the reviewer protocol only. What binds every
agent regardless of role is in [AGENTS.md](AGENTS.md); why the system
exists and who the personas are is in [INTENT.md](INTENT.md); what
the system does today is in [docs/SPEC.md](docs/SPEC.md).

**Automation status.** The enforcement points below name the
recorder (`scripts/ci/review_recorder.sh`), running in the `record` job
of `.github/workflows/merge-gate.yml`. The recorder is the trusted
step that validates reviewer output against schema and performs every
GitHub write directly.

## The two reviewers

- **Argus** (`evekhm-argus-app[bot]`) — the event-driven reviewer. Reviews on
  PR open, on pushes to a PR branch, and on mention. Owns the
  findings ledger and emits the review blocks that the recorder writes.
- **Atlas** (`evekhm-atlas-app[bot]`) — the independent second opinion,
  the reviewer that makes consensus mean something. Runs round 1 in
  full and afterwards only where the protocol requires it.
- Both are **comment-only**, with exactly one exception: applying the deep-review grant label through scripts/ops/post.sh --add-label deep-review on a pull request. Neither ever approves, requests changes, merges, closes, pushes, or edits any other label. Authority is a vocabulary: those verbs must not exist in the posting code, and prompt text is not the restraint.
- The two reviewers are **deployment-pinned to different model
  families (config fact)**. Which family backs which reviewer is not
  stated in a persona source, a prompt, or this document. A
  reviewer's identity is its role, its header, its finding namespace,
  and its bot account — never the model behind it.
- Both think at `REVIEW_TIER` (the ladder in AGENTS.md; the
  tier→model binding is a harness fact in `config/`).
- A human is the sole merge authority on every path, and the `hold`
  label halts all review automation while it is present anywhere the
  work points.

## The verification protocol

The per-rung verifier checklist executed across lifecycle gates:

- **plan:** at plan, the intent lost nothing from the issue;
- **design:** at design, no open question and every acceptance row runnable without a model;
- **build:** at build, the contract tests fail at the plan's base;
- **implement:** at implement, the gates re-run and the job log behind every green check says what the check claims.
- **code gate additions:** Argus adds the deep checks where it is assigned (code gate, trust-bearing paths, `deep-review`, open `security` row): mutation-test the tests, re-run the gates, read the full diff.

Atlas executes the checklist on every assigned PR; Argus executes the checklist plus deep checks at implement and wherever assigned.

## Design principles

1. **Full quality on first contact, declining scope after.** Round 1
   is as thorough as review ever gets, from both reviewers. Later
   rounds verify; they do not re-explore.
2. **Blocking is a closed definition, not reviewer judgment.** A
   finding blocks merge only if it matches an enumerated list, and
   the recorder — code, not prompts — enforces the match. This is the
   guard against severity inflation: the moment "high" blocks and
   "normal" does not, a model reviewer drifts toward "high" unless
   the tier is checkable.
3. **Each reviewer closes its own findings.** Dual sign-off is
   reserved for the one tier where a miss is unaffordable: security.
   Paying a second model family to re-verify fixes the first already
   verified is where cost doubles for nothing.
4. **Merging loses nothing.** A human can merge at any time, and the
   recorder converts whatever is still open into one follow-up issue.
   The protocol's job is to inform the merge decision, not to gate
   it.
5. **Minimal machinery.** The policing machinery is itself a
   round-generator. This protocol adds no new comment types and no
   new state files; it narrows the semantics of what already exists.
6. **The protocol bounds the machines, never the human.** Every cap
   here limits what runs *automatically*. An explicit human request
   always has a sanctioned path to exceed it: the deep-review grant
   for full-depth rounds, mentions for unmetered questions, retier
   for severity, merge for closure.

## Severity tiers

Four tiers. The first two block merge-ready; the last two never do.

| Tier | Blocks | Closed by |
|------|--------|-----------|
| `security` | yes | both reviewers, twice |
| `high` | yes | the filing reviewer |
| `normal` | no | the filing reviewer |
| `suggestion` | no | nobody (recorded once) |

What each tier means:

- `security` — exploitable vulnerability; secret, credential, token,
  or local-path leak; execution of untrusted or unpinned code in a
  privileged context; injection into trusted state (the ledger,
  labels, dispatch inputs).
- `high` — a defect on the closed list below, carrying a named
  concrete failure scenario.
- `normal` — any other real defect: documentation drift, stale
  numbers, comment accuracy, minor edge cases, error-message quality.
- `suggestion` — an improvement that is not a defect.

The closed `high` list. A finding is `high` if and only if it
describes at least one of:

- data loss or corruption (repository state, ledger state, run
  artifacts);
- a money-spend, quota, or rate gate failing open;
- silent failure of a security or spend gate (the gate runs, decides
  nothing, and reports success);
- breakage of a documented demo, setup, or pipeline path;
- an unbounded loop, redispatch, or self-trigger.

Everything else that is still a defect is `normal` by definition —
including every class that stretches rounds: doc-number drift, prose
precision, same-class-elsewhere instances outside the diff, missing
polish on error paths that gate neither money nor security.

Enforcement (recorder execution via scripts/ci/review_recorder.sh):

- Severity must be one of the four enum values; anything else fails
  validation.
- A `high` row must carry a `failure_scenario` field naming concrete
  input or state and the concrete damage. A `high` row without one is
  recorded as `normal`, and the demotion is noted in the ledger row —
  loudly, never silently.
- A human can retier any finding with one comment verb
  (`@argus retier <id> <severity>` or `@atlas retier <id> <severity>`,
  e.g. `@argus retier R2-1 normal`); the recorder records the override
  and recomputes labels. Human overrides are not debatable by either
  reviewer.

## The round funnel

```text
PR opened / manual dispatch
       |
       v
ROUND 1 - full review by BOTH reviewers: whole diff, full tree
          for existence claims, all four tiers recorded
       |
       +-- no open blocking rows --> MERGE-READY
       |
       v  open blocking rows: author pushes one batch of fixes
ROUND 2 - verification: scope is the open blocking rows plus the
          delta since the last reviewed head; NEW findings are
          admissible at security or high only
       |
       +-- no open blocking rows --> MERGE-READY
       |
       v  author pushes one batch of fixes
ROUND 3 - same scope rules as round 2
       |
       +-- no open security rows --> a human resolves the open high
       |                             rows: fix, retier, or merge
       v
    open security row: escalated to a human; verification
    comments only past this point, no new findings
       |
       v
AUTONOMOUS LOOP MERGES WHEN CONSENSUS IS REACHED (a human merge is the escape hatch available at any time)
       |
       v
the recorder files ONE follow-up issue listing every still-open
row, then closes the ledger
```

- **Round 1** is the only round where `normal` and `suggestion` rows
  are expected to be filed at all.
- **Rounds 2 and 3** are verification rounds. Any other observation a
  reviewer cannot resist making is filed as `normal`: recorded, no
  verdict owed, and it neither opens nor extends a round.
- **Past round 3** reviewers post verification comments only. The
  single exception is a new `security` finding, which may always be
  filed. The recorder demotes any other post-cap filing to `normal`.
- The round counter is the ledger's own round field, and finding IDs
  already carry the round, so the recorder needs no new state to
  enforce round-scoped rules. How the counter surfaces as a lifecycle
  label — and the escalation label that hands a stuck review to a
  human — belongs to the label state machine (issue #4).
- Underneath the funnel sits a budget gate that bounds the *number*
  of rounds: three event-driven rounds, then one consumed-on-use
  grant label per extra round, honored only when a repository admin
  applied it and verified from the label event timeline (an
  unverifiable applier is refused). Manual dispatch is always
  allowed. A daily run brake and a dispute cap of three exchanges sit
  beside it. The funnel is what the gate was missing: the gate bounds
  round count, the funnel bounds round *scope*. The recorder
  (`scripts/ci/review_recorder.sh`) enforces the funnel on every review round.

Why both bounds are needed, from the predecessor repo
(`agentic-experiments-lab`): with an automated fixer as PR author and
no gate, one PR ran nineteen unattended review rounds in a little
over three hours and had not converged. Adding a round budget alone
did not fix it — a granted round was still a full review that could
file documentation drift as a blocking bug. The late rounds were not
noise; the findings stayed real but descended in altitude, so value
per round decayed while cost per round stayed flat. Every loop level
needs its own budget, and the budget on the outermost loop is the one
that caps the bill.

## Finding IDs and the ledger

- Finding IDs are namespaced by reviewer so reconciliation is
  unambiguous: Argus files `R<round>-<n>` on PR rounds (`R1-3`) and
  `R<issue>-<n>` on issues (`R13-2`); Atlas files `AT<item>-<n>` on
  issues (`AT74-3`) and `AT-R<round>-<n>` on pull requests (`AT-R1-3`).
- An ID is **stable from its first appearance** and is never reused
  or renumbered, so both reviewers can reference it across rounds.
- The shared memory is a single ledger comment per PR or issue. It
  renders a human-readable table and embeds machine state. Each row
  carries: the ID, the source reviewer, the severity, the finding
  text, a **Status** owned by the filing reviewer's fix-tracking
  (`open` → `fixed` when commits address it, or `withdrawn` when it
  concedes), a separate **peer verdict** column owned by the other
  reviewer (`pending` → `agree` or `dispute`), the fixing commit, the
  outcome, and the timestamp the row entered its pending state.
- Fix-tracking and verdict-tracking are deliberately separate ledgers
  of truth. Marking a finding "fixed" closes one reviewer's
  bookkeeping while the peer's verdict remains its own record;
  consensus gates count findings in any status, or fixed-but-
  unverdicted security rows slide through to agreed.
- Pending age belongs to the row, not to the last review marker: a
  marker's age resets on every push, so a PR receiving a commit every
  23 hours would never trip a 24-hour stale-peer alert.
- The head a review refers to and machine-readable review findings are
  carried in a structured review verdict block emitted alongside the
  human-facing markdown review tables:

  ```markdown
  <!-- review-verdict:<reviewer>:<verdict> -->
  <!-- reviewed-head:<full-oid> -->
  <!-- run-id:<n> -->
  <!-- round:<n> -->
  <!-- finding:<id>:<severity>:<status>:<peer> -->
  <!-- failure-scenario:<id> -->
  <!-- review-verdict-end -->
  ```

  Where:
  - `<reviewer>` is `argus` or `atlas`.
  - `<verdict>` is `clean` or `findings`. A clean review emits zero
    `<!-- finding:... -->` lines between the round line and the
    `<!-- review-verdict-end -->` trailer.
  - `<full-oid>` is the full 40-hex commit SHA of the reviewed head.
  - `<run-id>` is the integer Actions run ID from `.github/workflows/unattended.yml`.
  - `<round>` is the integer review round counter (`1`, `2`, `3`, ...).
  - Each finding line matches `^<!-- finding:([A-Za-z0-9@-]+):(security|high|normal|suggestion):(open|fixed|withdrawn):(pending|agree|dispute|none) -->$`.
  - Findings citing spec decisions use format `<id>@<Dn>` (e.g. `R1-1@D4`) or `<id>@none` when uncited.
  - Each `high` finding must be immediately accompanied by its sibling marker `<!-- failure-scenario:<id> -->`.
- Both reviewers are stateless between runs. Every conversational
  comment is therefore self-contained: the finding IDs, the head it
  refers to, and the evidence. The thread is the only memory.

## Signature convention

- Every comment and review a reviewer posts is signed, so a reader
  knows which reviewer is speaking without relying on the account
  name or the avatar.
- The **header** identifies the reviewer — a role, stable across
  model changes: `### Argus` (`### Argus review` for a PR review,
  `### Argus findings ledger` for the ledger) and `### Atlas`.
- The **trailer** begins `— Argus · ` or `— Atlas · ` and names the
  runtime fact the deployment pins. It is written from configuration,
  never from the model's self-report, and it is not stated in this
  document or in any persona source — it is a `config/` fact
  resolved at deploy time. An instance may append `via <runtime>` to
  identify which runtime produced the comment.
- Runtime does not change identity. The same reviewer keeps the same
  header, the same finding namespace, and the same bot account
  whichever runtime posts.

## Consensus

- Both reviewers run round 1 in full and **independently**. Never let
  the peer's findings become your starting point; cross-reviewer
  discovery is where the two-family design earns its cost, and in the
  predecessor repo the two finding sets barely overlapped.
- From round 2 on, no peer verdict is owed or requested for `high`,
  `normal`, or `suggestion` rows. Each reviewer verifies its own open
  blocking rows.
- `security` rows always require both reviewers' explicit AGREE,
  twice: once on existence, once on the fix. This is the guardrail
  the funnel never relaxes.
- Atlas therefore runs: round 1 in full; afterwards only to verify
  its own open blocking `AT-*` rows, to co-sign a security fix, or to
  answer an explicit dispute or mention. It does not re-review deltas
  containing neither.
- **Evidence arbitrates, never identity.** Do not defer to the other
  reviewer and do not converge to be agreeable: conceding or agreeing
  without new evidence is a protocol violation.
- **Verification outranks argument.** When a claim can be executed —
  a command, a reproduction, a line reference at a stated head — run
  it and post the actual output. Existence claims are checked against
  the full tree, never the diff: a function untouched by a PR never
  appears in its diff.
- Hallucinated findings are priced in. The protocol metabolizes them:
  executable evidence, independent re-verification, explicit
  concession, a recorded dispute.
- **Verdict format** — one line per plain AGREE (finding ID plus one
  line of verification evidence). Full prose only for disputes,
  amendments, and new findings. AGREE/DISPUTE verdicts are required
  and are not acknowledgment-only comments; acknowledgments *of*
  acknowledgments are, and are never posted. No reviewer asserts
  ledger or label state.
- **Dispute cap** — exchange tags are per thread: N = 1 + the highest
  tag anywhere in the thread, whoever posted it, never reused. A
  dispute caps at three exchanges; past that, summarize both
  positions in two lines, tag the human owner, and stop. A
  well-summarized escalation is a good outcome.
- **Silence after full agreement is the success signal.** Never post
  acknowledgment-only comments.

## Consensus keyed to Decision IDs

This repository's specs carry a numbered **Decisions table** (the
Design gate in INTENT.md: every resolved ambiguity becomes a numbered
row, and every contract assertion cites the Decision ID it derives
from). Where the change under review has one, consensus keys to those
IDs rather than to diff hunks:

- A finding about specified behavior carries the Decision ID it
  concerns (`Decision: D4`). A finding about behavior no Decision
  covers carries `Decision: none` — and that absence is itself worth
  reading, because unspecified behavior in an implementation PR is
  usually a missed ambiguity. Findings cite decisions in machine
  markers using format `<id>@<Dn>` (e.g. `R1-1@D4`) or `<id>@none`
  when uncited.
- Peer verdicts are recorded **per Decision ID**, not per diff hunk.
  When both reviewers file findings against the same Decision, they
  reconcile into one verdict on that Decision instead of two parallel
  threads about the same disagreement.
- A finding claiming the diff contradicts a Decision must quote the
  Decision row it contradicts. If the diff and the Decision are
  genuinely irreconcilable, that is a **spec defect, not an
  implementation defect**: it returns to the Design gate as a new
  ambiguity for the product owner to resolve into a new Decision row.
  Two reviewers must not settle between themselves what the spec
  never decided.
- Keying to Decision IDs changes routing and reconciliation, never
  severity. The closed lists above remain the only tier definitions;
  contradicting a Decision does not by itself make a finding
  blocking.
- Where the change has no Decisions table (documentation changes,
  bootstrap PRs, anything filed straight to `main`'s backlog),
  findings key to their own IDs and everything else in this protocol
  is unchanged.

## Labels

Labels are **derived from ledger state by the recorder**. No reviewer
ever adds, removes, or asserts one. The label *names* below are the
predecessor's; the taxonomy that wins here is settled by issue #4
(INTENT.md open question 4), and these rules bind whatever names it
picks.

- The findings label is present if and only if open **blocking** rows
  exist (security or high). Open `normal` rows never hold it.
- The suggestions label is present if and only if open non-blocking
  rows exist (`normal` or `suggestion`). Purely informational.
- The consensus axis keys on **security rows only**: pending while a
  security row awaits the peer's verdict, agreed otherwise —
  including every item with no security rows at all. Disputed fires
  on an explicit dispute over ANY blocking row, because a contested
  high finding must stay visible even though it needs no routine peer
  verdict.
- Merge-ready means: no open blocking rows, consensus agreed, and the
  reviewed head matches the current head. It is silent about CI,
  which is GitHub's own signal.
- Verifying means: open blocking rows exist AND the head is newer
  than the reviewed head — fixes are pushed and the verification
  round has not run.
- A ledger with no head marker earns neither head-pinned label, and a
  failed head probe freezes both rather than guessing.

Two rules learned the hard way, both worth keeping in the ported
code:

- **Where nothing is in scope, require no consensus.** Demanding a
  verdict on nothing is how clean items stick in pending forever.
  Every resting state needs a reachable exit.
- **Prefer self-healing to cleanup.** A deterministic pass that
  re-derives labels from the recorded ledger — zero model tokens by
  construction — retro-corrects stuck items and caps how far state
  can drift. Never gate state recording on model etiquette: if a
  correct action by one agent leaves shared state wrong, the state
  machine is the bug.

## Merge is the escape hatch

The system merges when consensus is reached. A human can merge or close any PR at any time as an escape hatch, at any label state.
When a PR merges or closes with open ledger rows of any tier, the
recorder files exactly **one** follow-up issue — `Post-merge findings
from PR #<n>` — containing the open rows with their severities,
evidence links, and the final ledger snapshot, then marks the ledger
closed. Open `security` rows in such an issue are tagged to a human.
Merging early loses no recorded finding.

## Asking for more: the deep-review grant

The funnel bounds the automatic loop; it must never bound the human.
For a review that goes *beyond* the protocol (full depth, full tree,
every tier, regardless of round count), the sanctioned paths are:

- a **`deep-review` label** applied by a persona App identity
  (`daedalus`, `odyssey`, `atlas`, `argus`, `cassandra`) through
  `scripts/ops/post.sh` under criteria DEEP-1..DEEP-7, or by a
  repository admin, verified from the label event timeline and
  consumed on use, with a limit of one grant per PR per rung (a second
  grant on the same rung is refused and removed);
- a **deep manual dispatch** of the review workflow, which needs no
  label because the dispatch *is* the explicit request;
- an **explicit human request in the thread** (or a mention) for a
  deep or full review, which outranks Atlas's cadence and round-scope
  rules and gets a round-1-depth pass at the stated head;
- **mentions**, which remain unmetered for humans and admins:
  free-form questions, audits of a specific concern, and explanations
  happen there, off the ledger.

A deep round changes **discovery scope only**. It suspends the
round-cap demotion for that one run; it does not suspend the
failure-scenario requirement for `high` (a quality rule instead of a cost
rule), and closure rules are unchanged: new blocking findings from a
deep round block until fixed and verified, and security still needs
both reviewers. Depth is a paid, explicit decision; it never reopens
the unbounded loop.

## Dispatch policy

Automation runs in the record job via scripts/ci/review_recorder.sh; the rules bind it directly.

- Reviews are dispatched by: PR opened, push to a PR branch (through
  the budget gate), an explicit reviewer mention, or manual dispatch.
- **A scheduled sweep never dispatches a model review.** Its only
  jobs are the zero-token deterministic passes: label self-heal
  (pure re-derivation from the ledger) and the stale-peer check.
  Anything a sweep would catch by re-reviewing is caught by the push
  trigger or by a human mention.
- Discovery filters must match each query's purpose. "Recently
  updated" is the wrong lens for finding abandoned items: an
  abandoned PR has, by definition, no recent updates, so a freshness
  window excludes exactly what a stale-peer scan exists to find.
- Every runtime a reviewer can run from reads the same canonical
  prompt, so the tiers, cadence, and override rules apply regardless
  of which runtime posts. Per AGENTS.md, that prompt is compiled from
  the canonical persona source and never hand-edited.
- Post-merge cleanup (the follow-up issue) runs from the merge or
  close event, not from a sweep.
- Fork PRs are gated out of the automatic recording path, and every
  new trigger re-checks the fork gate: a collaborator's author
  association reads the same on a fork PR, and a new event type does
  not inherit the old event's gate. State-carrying comments are
  matched by author, or anyone can pre-plant forged state for
  unattended automation to consume.

## Cost envelope

Worst case per PR: three Argus review runs, one full Atlas run, plus
short Atlas verifications scoped to its own rows and security
co-signs — roughly four to six model runs. Suggestions and normal
findings cost one filing each and zero exchanges, ever. The expensive
failure mode is not two agents arguing; the exchange cap and the
escalation rule bound that. It is the round count, which is why the
funnel exists.

## Enforcement map

Prompts state the rules so the reviewers aim correctly; the recorder
(`scripts/ci/review_recorder.sh`) enforces them in the `record` job so
a drifting model cannot break the budget. Every rule exists in code
before a prompt describes it in the present tense. The rows marked
*recorder* are enforced by `scripts/ci/review_recorder.sh`.

- Severity enum, the `high` failure-scenario requirement, and loud
  demotion — *recorder*, through schema validation.
- Round-scoped admissibility (blocking-only after round 1,
  security-only after round 3) — *recorder*, keyed on the ledger's
  round counter.
- Labels derived from ledger state, security-only consensus axis —
  *recorder* label derivation.
- Decision-ID keying of findings and verdicts — *recorder*, against
  the spec's Decisions table.
- The single post-merge follow-up issue: *merge actor* (#64 D16), on
  the merge event.
- Budget gate, daily brake, dispute cap — deterministic gates that
  run ahead of any model call.
- Round-1 thoroughness, verification scope discipline, verdict format
  — reviewer prompts, compiled from `personas/`.
- The human retier verb — *recorder*, on the mention path.
