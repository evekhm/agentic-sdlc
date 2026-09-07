# Spec: a reviewer at a pull request is reviewing that pull request

**Issue:** #207 · **Status:** Approved (approval = merge of this PR) ·
**Author:** athena (`evekhm-athena-app[bot]`) ·
**Open questions:** none

## What is being built

One dispatch path gains one property: a review persona dispatched at a
same-repository pull request is dispatched at the **review** stage and
is not measured against the issue's claim. Everything else about
`scripts/ops/work.sh` — the resolver, the refusal order, the eight
conditions, the owner derivation, the launch table — stands.

```text
scripts/ops/work.sh              # the review-dispatch predicate, (g), the stage retarget, the report
scripts/ops/lib/github.sh        # expose head.repo.full_name (D1c; see the Concerns)
scripts/ops/tests/work_test.sh   # the acceptance rows below
docs/SPEC.md                     # ops.dispatch: the eight-refusals paragraph and the "labels alone" sentence
```

`personas/**` and `personas/lifecycle.json` are **not** touched (D4).
No new label, no new persona, no new stage value, no new flag: the
number and `--as` remain the whole instruction (`scripts/ops/work.sh:8-15`).

## Decisions

| ID | Decision | Rationale |
|----|----------|-----------|
| D1 | **A dispatch is a REVIEW DISPATCH iff all three hold:** (a) the number given resolved as a pull request — the resolver's `IS_PR=1` (`scripts/ops/lib/github.sh:95-134`, set at `:111`); (b) `--as` names a persona whose `stage:` list contains `review` — today `argus` (`personas/argus.yaml:4`) and `atlas` (`personas/atlas.yaml:4`); (c) the pull request's head repository equals the repository being worked, `head.repo.full_name == $GITHUB_REPO`. Anything else is an ordinary dispatch and **nothing in this spec applies to it**. | The narrowest gate decidable from data the dispatcher already holds or can read on the path it already takes. Keying on `--as` is what the code leans on elsewhere — a broken atlas target must not stop `--as argus` (`scripts/ops/work.sh:723-729`, #43 D20) — and it is the narrower of the two gates the intent offers. A fork head falls through to the **ordinary** path and its ordinary refusals rather than adding a ninth refusal: the workflow guard (`.github/workflows/unattended.yml:80-83`) stays the outer owner of the fork rule, as `intent/25-execution-model/spec.md:83` (D7) states it, and the merge gate reads the same field as its first conjunct (`intent/64-autonomous-loop/spec.md:64`). Answers intent Open questions 2 and 4. **Correction to the premise:** `head.repo.full_name` is *not* present in `PR_JSON` today — the resolver reads `repos/<repo>/issues/<n>` (`lib/github.sh:103`) and keeps that response as `PR_JSON` (`:112`), and the issues endpoint carries only a `pull_request` URL stub. The pulls response is read at `lib/github.sh:76`, inside `branch_issue()`, into a *local* variable and only on the no-closing-keyword fallback. So D1(c) requires exposing the field; see D9 and the Concerns. |
| D2 | **Stage retarget, after the issue's rung is derived.** The issue's rung is derived exactly as today, from the issue's `status:*` label alone (`scripts/ops/work.sh:311-328`), so refusals (e) multi-status (`:300-309`) and (f) no-rung (`:320-327`) still fire unchanged. **Then**, for a review dispatch only, the dispatch's stage becomes `review` — the `review` row of `personas/lifecycle.json` (`:59-67`) — and `owners` (`work.sh:352`), `brief` (`:333`) and `artifact` (`:334`) derive from that row. A repair-path pull request whose issue carries only `bug` still refuses at (f) and remains #82's. | This is the second wall, and property 1 without it is half a fix. The `review` row is the DEFINITION of the review stage, now reached through the pull-request form as well as through the label; its `dispatch_brief` already reads *"Review the open pull request against its spec and plan; post findings and a verdict, never a merge."* (`personas/lifecycle.json:66`) — written for exactly this call. `status:in-review` remains the terminal record #64 D17 describes: *"review happens on the open pull request, before the merge, so `status:in-review` after a system merge is a state with no work owed"* (`intent/64-autonomous-loop/spec.md:76`). Refusing the repair path here is the intent's "narrow before wide" constraint. Answers Open question 1 in part. |
| D3 | **Refusal (g) is not evaluated for a review dispatch.** The eight refusals keep their order and their count (`docs/SPEC.md:451-470`); at (g)'s position (`work.sh:409-428`) a review dispatch is passed through **without reading the claim** — no label read, no thread read, none of (g)'s four messages. (a)-(f) still apply to it: `hold` (`:272-275`), re-entrancy (`:277-285`), closed and `status:review-stuck` (`:287-293`), `blocked` (`:295-298`), multi-status, no-rung. (h) (`:430-433`) then evaluates `--as` against the owners of `review` and passes **by construction of D1(b)** — that is the mechanism, not an exemption of (h). | The mutex protects one issue's working tree (`work.sh:374-408`; #36 Argus R1-1 and R2-1). A review dispatch writes no branch and holds no worktree, so the collision it prevents cannot occur on that path. Both walls of the intent fall: (g) by this decision, (h) by D2. Passing through rather than re-deciding (g) is what keeps the refusal's meaning for every other caller intact — an exemption that still read the thread would still have to answer "held by whom", and the answer is always "the rung's author" (D5). |
| D4 | **No new label, no persona change, no stage-enum change.** `personas/**` and `personas/lifecycle.json` are not touched. | `review` is already in the closed stage enum (`personas/schema.json:19-26`, the enum at `:22`), both reviewers already declare it, and the `review` row already carries the brief this path needs. A second `status:*` for the review window would also have to survive refusal (e), which refuses any issue carrying more than one (`work.sh:300-309`). Answers the remainder of Open question 1. |
| D5 | **Reviewers never claim.** A review dispatch writes nothing: no label, no claim comment. `work.sh` never writes to GitHub at all (`work.sh:25-30`) and reviewer authority is comments-only (`personas/argus.yaml:33-34`). The issue's claim stays held by the rung's author for the whole review window. The resume branch of (g) — a claim by an owner of the current stage is that actor resuming (`work.sh:387-392`, `:426-427`) — is simply never reached by a review dispatch, and is otherwise unchanged for every other caller. | Anything reading the claim sees exactly what it sees today, so the four ladder checks #204 mechanizes (one closing keyword, the persona branch, the claim identity, the commit author — `intent/204-verifier-stage/intent.md:77-79`, `:105-107`) are unaffected by this issue: none of them changes meaning when a reviewer is dispatched, because a reviewer changes nothing they read. Keeping the claim held is also what makes releasing it at handoff unnecessary — the alternative the intent rejects, because an unclaimed issue with an open pull request is claimable by anyone. Answers Open questions 5 and 6. |
| D6 | **A bare pull-request dispatch (no `--as`) is unchanged.** It is an ordinary dispatch by D1(b): it derives the issue's rung, runs all eight refusals including (g), and at a multi-owner stage prints both owners and launches neither (`work.sh:763-773`, #2 D4). | The unattended workflow always supplies `--as` — `run.sh "$NUMBER" --as "$PERSONA"` (`.github/workflows/unattended.yml:367`) and `scripts/placement/gh-actions/run.sh:98` hands both through unchanged — so no runner path is a bare dispatch and nothing is lost by leaving it alone. Making the pull-request form alone sufficient would widen the gate to every persona at every pull request, which is the one thing the intent's narrowness constraint forbids. Answers Open question 3. |
| D7 | **A non-review persona dispatched at a pull request is unchanged in every respect**, all eight refusals included, (g) among them. | This is the acceptance test written first (AT-1), not a caveat: no path created here launches an implementer onto a claimed issue. The intent states it as a constraint and the spec states it as the first row of the suite. |
| D8 | **The reviewer is told the pull request number.** Today it is not: the launched persona's whole first message is the one literal `PROMPT` at `work.sh:547` — *"Work issue #$ISSUE in this repository…"* — which names the resolved ISSUE and nothing else, deliberately (`:537-547`). The lifecycle row's `brief` is read at `:333` and only **printed** to the operator at `:746`; it never reaches the launched session. For a review dispatch the launched persona MUST receive the pull request number it is reviewing. How — a review-dispatch variant of the prompt line, or the brief carried into it — is the plan's call; that the number appears in what the reviewer receives is the spec's requirement. | Without it the reviewer is told to "work issue #M" while the artifact under review is pull request #N, and must re-derive #N from the issue — the exact guess the resolver exists to prevent (`lib/github.sh:92-94`). The rule the prompt literal protects is that a launch must not name a stage the labels say is not current (`work.sh:8-15`, D7); a review dispatch's stage IS current by D2, and a pull-request number is not a stage, a folder, an artifact or a branch. |
| D9 | **Scope boundary.** The implementing change MAY touch: `scripts/ops/work.sh`; `scripts/ops/tests/work_test.sh` (the only test file that covers the dispatcher; its `pr()` fixture helper at `:261-269` writes `head.ref` only and gains `head.repo.full_name`); `docs/SPEC.md` (the eight-refusals paragraph, `:451-470`, and the "derived from the issue's labels alone" sentence, `:467-470`, which gains this one exception); and `scripts/ops/lib/github.sh`, **because the field D1(c) reads is not exposed today** (D1). It may NOT touch `personas/**`, `scripts/ops/claim.sh`, `.github/workflows/**`, or `scripts/placement/**`. This spec's own pull request carries `Spec-impact: none`; the `docs/SPEC.md` upsert rides the implementation pull request. | The same rule #64's D19 applied to its own spec pull request (`intent/64-autonomous-loop/spec.md:78`); `scripts/ci/spec_check.sh:84-89` makes `scripts/**` behavior-bearing, so the implementation diff carries the spec entry or the marker, and it will carry the entry. The library carve-out is stated rather than discovered: an implementer who found the field missing would otherwise either widen scope silently or fake the check. |
| D10 | **Observability: the dispatch report names the retarget.** The report block at `work.sh:692-709` prints `stage:` (`:698`), `label:` (`:699`), `artifact:` (`:700`) and `owner:` (`:701`). For a review dispatch the `stage:` line must name both the retarget and the rung it displaced — for example `stage: review (pull request #N; issue #M is on build)` — and the `label:` line must not assert that the issue carries `status:in-review`, because it does not. | A job log is the only place a reader can tell a review dispatch from a rung dispatch, and PLAYBOOK's operating rule is to read the job log behind every green check (`docs/PLAYBOOK.md:87`) — the exit criterion for this whole cluster is a reviewer job log (`:291-292`). The `label:` clause is not cosmetic: the review row's label IS `status:in-review` (`personas/lifecycle.json:61`), so a naive retarget prints a label the issue does not carry, next to a claim the issue does. |

## Acceptance

Every row is checkable without a model call, in the existing harness:
`scripts/ops/tests/work_test.sh` is hermetic — a stub `gh` answers from
canned JSON fixtures (`:85-132`, the path-to-fixture mapping at `:105`),
`issue()` / `pr()` / `claim()` build
them (`:252-280`), `run <expected-exit> <name> -- <args>` invokes the
dispatcher with `DRY_RUN=1` by default and captures stdout and stderr
(`:299-313`), and any attempted write or unasked launch is recorded and
fails the run. `pr()` gains `head.repo.full_name` for AT-5.

- **AT-1 (D7)** A non-review persona (`--as odyssey`) at a ladder pull
  request whose issue carries `in-progress` and a claim by another
  actor exits 2 with today's (g) message, `in-progress on … is held by
  …`, byte-identical to the existing scenario.
- **AT-2 (D3 + D2)** `--as argus` at that same pull request, issue on
  `status:build`, exits 0: it passes (g) without reading the thread,
  reports `stage: review`, passes (h), and reaches the launch step
  (`==> DRY_RUN=1 …` under the suite's default mode).
- **AT-3 (D1b)** `--as argus` at a **bare issue** number on a non-review
  rung exits 2 with `argus does not own stage <rung> (owners: …)` — the
  existing scenario at `work_test.sh:596`, unchanged.
- **AT-4 (D2, refusal f)** `--as argus` at a pull request whose issue
  carries only `bug` exits 2 with `cannot derive a stage for #…` — the
  existing scenario at `work_test.sh:610`, unchanged.
- **AT-5 (D1c)** `--as argus` at a pull request whose
  `head.repo.full_name` differs from `$GITHUB_REPO` takes the ordinary
  path: it exits 2 at (g) or at (h) as the labels dictate, and nothing
  is launched.
- **AT-6 (D6)** A bare pull-request dispatch with no `--as` behaves as
  today: at a two-owner stage it prints both owners and exits 0 having
  launched neither; at a one-owner stage it takes the ordinary path.
- **AT-7 (D3 order)** `hold` on the **pull request** plus `--as argus`
  exits 2 at (a), naming the pull-request side — proving (a)-(f) still
  precede the review-dispatch pass-through.
- **AT-8 (D10)** In AT-2's output the `stage:` line names the retarget
  and the displaced rung, and no line asserts a `status:in-review`
  label the issue does not carry.
- **AT-9 (D9)** The implementing pull request updates `docs/SPEC.md`
  and `bash scripts/ci/spec_check.sh origin/main <body-file>` exits 0
  on it.
- **AT-10 (D4, D9)** `git diff --name-only` of the implementing pull
  request touches no path under `personas/`, `.github/workflows/`,
  `scripts/placement/`, and not `scripts/ops/claim.sh`.
- **AT-11 (D1b)** `--as atlas` at AT-2's pull request exits 0 the same
  way argus does: both owners of `review` get the property, and one
  reviewer's presence does not gate the other's.
- **AT-12 (D5)** Across AT-2 and AT-11 the suite's `$WRITES` and
  `$MINTS` logs stay empty: a review dispatch claims nothing, labels
  nothing and exchanges no token.
- **AT-13 (D3)** `--as argus` at a pull request whose issue carries
  `in-progress` and whose thread contains **no** structured claim
  comment exits 0 rather than refusing with *"the mutex names no
  holder"* — the pass-through is unconditional on the thread, and the
  thread is not read.
- **AT-14 (D8)** The prompt the review dispatch would launch with names
  the pull request number, and the prompt for every non-review dispatch
  is byte-identical to today's literal.

## Concerns

- **The count says eight; one entry's text changes.** `docs/SPEC.md:451`
  opens *"Eight refusals, checked in order…"* and `work.sh:60` names
  *"the eight refusal conditions"*. The count is preserved and the
  order is preserved — (g) still occupies its position and still
  refuses every non-review dispatch — but (g)'s prose gains a clause,
  and a reader who scans for the number will not see that the seventh
  entry now has a documented pass-through. The upsert must edit the
  entry, not the count.
- **`head.repo.full_name` is not in `PR_JSON`** (D1). The resolver's
  pull-request response is the *issues* endpoint's (`lib/github.sh:103`,
  `:112`); the pulls read at `:76` is local to `branch_issue()` and
  happens only when the body carries no closing keyword. D1(c)
  therefore costs either one extra read or a refactor of the resolver
  to keep the pulls response it sometimes already fetches. The decision
  stands; the scope boundary (D9) is written to permit it. Whichever
  shape the plan picks, it must fail **closed**: a pulls read that
  fails is not a same-repository head.
- **The launched reviewer does not receive the pull request number
  today** (D8). This is a change to the one prompt literal that
  `work.sh:537-547` documents as deliberately minimal, and it is the
  only place this spec puts a new sentence in front of a model. The
  plan should keep the non-review prompt byte-identical (AT-14) so the
  literal's rule — no stage, no folder, no artifact, no branch — is
  visibly intact for every other dispatch.
- **#64/#151's merge gate will one day read what this path produces.**
  Its `merge-eligible` conjunct (3) requires both reviewers' verdicts
  to cover the current head OID (`intent/64-autonomous-loop/spec.md:64`).
  Nothing here writes a verdict marker, records a review, or advances a
  label; #64's recorder remains the sole owner of that. This issue only
  makes the reviews exist.
- **#82 is deliberately not fixed.** A defect-repair pull request
  resolves to an issue carrying only `bug`, derives no stage, and
  refuses at (f) before any of this applies (`work.sh:320-327`;
  `docs/PLAYBOOK.md:283-290`). Same symptom, different cause, its own
  issue.
- **D1(c) duplicates a rule the workflow already owns.** The matrix is
  already restricted to same-repository heads
  (`.github/workflows/unattended.yml:80-83`), so the duplicate can
  never fire in the unattended path. It is acceptable because it is a
  fail-closed reader of data the dispatcher can hold, and because
  `work.sh` is also invoked by hand, where no workflow guard stands in
  front of it. The workflow guard remains authoritative: if the two
  ever disagree, the workflow is right and the dispatcher is a bug.
- **The report prints a branch a reviewer will not create.** `work.sh:745`
  prints `branch: <persona>/<issue>-<slug>` for every owner, including a
  reviewer that writes nothing (D5). Left alone: it is a printed
  derivation, not an instruction, and suppressing it for one dispatch
  kind would make the report's shape depend on the caller.

## Out of scope

- **#82** — repair-path pull requests and their missing reviews.
- **#191** — claim identity as a hard claim-time parameter.
- **#167** — runner model access for the reviewers.
- **#64 / #151** — consensus merge, verdict recording, the merge gate.
- **Any change to the claim protocol**, to `scripts/ops/claim.sh`, or to
  AGENTS.md steps 5 and 6. The claim is still released the way it is
  released today.
- **#204's four ladder checks.** D5 states that they are unaffected;
  their design is that issue's.

## Operator decisions

None are required by this spec. For the record: the implementation
dispatch goes to the odyssey rung after the plan, and no pin, secret or
GitHub App changes.

Open questions: none
