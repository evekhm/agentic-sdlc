# Spec: nestor — the advisor seat as a tracked persona

**Issue:** #199 · **Status:** Approved (approval = merge of this PR) ·
**Author:** athena (`evekhm-athena-app[bot]`) ·
**Open questions:** none

## What is being built

The advisor seat becomes a persona source like every other actor, and
the local charter file that carries it today is retired.

```text
personas/nestor.yaml               # new source, kind: persona
personas/skills/advisor-session.md # new skill: orient, report, close out
personas/skills/advisor-truths.md  # new skill: the standing truths
config/deployments.yaml            # one added pin line (value: operator's)
config/model_tiers.yaml            # FRONTIER comment amended (D4)
<compiled target(s) for the pinned harness>   # generated, committed
docs/SPEC.md, README.md            # enumerators and counts (D12)
```

`config/execution.yaml` is deliberately **not** touched: a persona with
no unattended duty has no entry (`config/execution.yaml:3`), and that
absence is the whole expression of "interactive only" (D2).

## Decisions

| ID | Decision | Rationale |
|----|----------|-----------|
| D1 | A new persona, `personas/nestor.yaml`, `kind: persona`. The product owner does not absorb the role. | The product owner owns the two gates where words become commitments. Handing the same actor dispatch-prompt authorship, PLAYBOOK stewardship and unblocking would make the gate its own process owner. Answers intent Open question 1. |
| D2 | `stage: [intake]`. No entry in `config/execution.yaml`. | `intake` is in the schema's stage enum (`personas/schema.json:23`) and `personas/lifecycle.json:19` states it has no rung "by construction". No rung means no `status:*` label, so the dispatcher can never resolve to it: `scripts/ops/work.sh:311-331` derives the stage from the issue's single `status:*` label through that table and dies otherwise. The smoke launcher's arm filter rejects a persona that "owns no stage any rung labels" (`scripts/ops/smoke_launch.sh:336`). The unattended workflow names no persona; its matrix comes from `scripts/ops/execution.py --subscribers` over `execution.yaml`. Verified: all three dispatchers pass. Answers Open question 2. |
| D3 | nestor owns no ladder rung. When the seat itself authors an intent or a spec, it claims and commits as the product-owner persona, as this very issue did. The skill says so in one line. | The seat's gate work is the gate's, and the gate has an identity, a branch surface and an App. A second actor writing gate artifacts under its own name would split the record of who committed the repository to what. |
| D4 | `tier: FRONTIER`. The comment at `config/model_tiers.yaml:20-21` is amended to name two FRONTIER consumers rather than one. It reads today, verbatim: `# Spec gate only: REVIEW stays opus, Fable is` / `# 2x its rate and review runs every PR round (#105)`. | Both consumers do judgment, not volume, and neither runs per pull-request round, which is the argument the existing comment already makes; "spec gate only" was a scope statement, not part of that argument, and it stopped being true. Answers the intent's tier claim. |
| D5 | The #105 amendment is recorded as an amendment to the existing decision, not a new number: the comment edit in `config/model_tiers.yaml` plus one amended sentence in the `config.bindings` section of `docs/SPEC.md`. | The decision itself (which tier costs what, and why review does not get the frontier grade) is unchanged; only its scope statement was too narrow. A new number would imply the pricing argument was revisited. Answers Open question 3. |
| D6 | Charter prose lives in two skill files under `personas/skills/`, declared in nestor's `skills:` list: `advisor-session.md` (orient order, reporting, close-out) and `advisor-truths.md` (the standing truths). `role` is the one-paragraph charter. | `personas/schema.json:37-41` requires skill filenames matching `^[a-z][a-z-]*\.md$` in that directory; `scripts/sync_agents.py:509-510` inlines each declared skill verbatim in declared order, and `--verify` asserts the full text survived (`sync_agents.py:980-983`). Two files split a durable protocol from a list of earned truths, which change on different schedules. `role` has `minLength: 80` (`schema.json:32-36`). Answers Open question 6 in part. |
| D7 | nestor does **not** declare `resume-protocol.md`. | That skill turns one issue number into a claimed stage artifact or a refusal. nestor never claims a rung (D3), so declaring it would render a ladder into the brief that the seat is forbidden to walk. Consequence: the sentence at `docs/SPEC.md:208` must be reworded (D12). |
| D8 | nestor declares `trusted-posting.md`. | The seat comments on issues and pull requests, and that skill is the write discipline every posting actor carries. |
| D9 | Capabilities, all from the seven names the tool map already defines (`config/tools.yaml:8-52`): `read_repo`, `run_commands`, `github_read`, `github_write`, `delegate`, and `ask_user` with `required: false`. No `write_repo`. | Omitting `write_repo` is how "judgment only, never implements" is expressed in the vocabulary that exists; the seat authors files through the harness it is opened in, not through a granted repository-write capability. No new capability name is invented, so no schema or tool-map change rides this issue. `delegates_to: [explorer, mechanic, scanner]` — the three read-only and mechanical sub-agents that exist (`personas/explorer.yaml`, `personas/mechanic.yaml`, `personas/scanner.yaml`, all `kind: subagent`). Answers the rest of Open question 6. |
| D10 | `limits: { max_turns: 80, timeout_mins: 45 }`, copied from the product-owner persona. The spec records that these bind only under dispatch, which never happens for nestor. | `schema.json:108-117` requires both for every `kind: persona`, both `minimum: 1`. There is no honest value for a seat a human holds open, so the values are borrowed from the closest-shaped persona and their inertness is stated rather than hidden behind an arbitrary number. |
| D11 | `authority.identity: "TBD"`, `authority.token: NESTOR_APP_PRIVATE_KEY`, `authority.github_write: "branch:nestor/*"`. Interim rule, stated in `advisor-session.md`: at a ladder gate the seat acts as the product-owner persona via the claim script; everywhere else it pushes and comments under the operator-designated bot until a nestor App exists. | The schema permits the literal `"TBD"` until an App is registered (`schema.json:79-81`) and requires the token to be a NAME, never a value (`schema.json:96-100`). The branch surface records what the seat already does: PLAYBOOK pull requests are pushed from `nestor/*`. Verified safe against the smoke launcher: `disqualifies()` rejects nestor at its first check, because no App manifest grants it `issues: write` (`smoke_launch.sh:334`), and again at the stage check, so the branch surface does not make it eligible to become a smoke arm. Answers Open question 7. |
| D12 | Documentation edits: `docs/SPEC.md` at `personas.sources` (line 71), `identity.bots` (91), `personas.resume` (192), `ops.dispatch` (429), `execution.placement` (736), and `config.bindings` (128) for D5; the four count phrases at `docs/SPEC.md:73`, `92`, `101` and `208`; the two at `README.md:66` and `README.md:144`; one pin line in `config/deployments.yaml`. `docs/SPEC.md:208` currently reads "(all six personas, no sub-agent)" and becomes true again by naming the exception rather than by changing the number's meaning. `INTENT.md`'s counts are left alone as a historical record. The plan lists the edits; this spec lists the files. | `scripts/ci/spec_check.sh:84-89` makes any change under `personas/` or `config/` behavior-bearing, so `docs/SPEC.md` must move in the same diff. A new persona changes behavior, so the `Spec-impact: none` marker is not available. |
| D13 | The dated handoff file stays local, at `ops/handoffs/handoff-plan-<date>.txt`. The tracked half of continuity is the status snapshot in `docs/PLAYBOOK.md`, which the seat owns. The brief names both. Close-out obligations are a list in `advisor-session.md`; #85 (session close-out, `/wrap`) is the mechanization of that list and this spec defines no second convention. | Handoffs carry dated state, live pull-request numbers and operator-specific paths — exactly what the intent's "dated artifacts stay out of the persona" constraint keeps out of a durable source, and what a tracked file would rot into. The sanitizer does not block the `~/`-relative form: `scripts/ci/sanitize_check.sh:22-30` states that `~/`-relative paths carry no account name and are deliberately out of scope. Answers Open question 4. Amended 2026-09-08: the local root is the primary checkout's gitignored `ops/` (AGENTS.md "Outputs go in timestamped run folders"), so the repo names the file by a repo-relative path and nothing is dumped flat in the home directory. |
| D14 | The operator protocol — every authored prompt is a file on disk, handed over as a full path plus one launch line carrying an explicit model flag — is a standing truth in `advisor-truths.md`. The reason it exists (this deployment's operator cannot paste multi-line text into a terminal chat) stays in `docs/PLAYBOOK.md`, and the skill cites PLAYBOOK for it. | The rule binds the persona; the reason is a fact about one deployment and belongs with the other deployment facts. PLAYBOOK already states it (`docs/PLAYBOOK.md:45-49`). Answers Open question 5. |
| D15 | One launch convention, shared with the verifier seat split from #199 (issue #204, which records that the compiled persona brief IS the tracked launch template and that #181 generalizes implementer preambles, so neither spec invents a second template home): the operator opens the seat with the harness's interactive command-line client and an explicit model flag whose value is the FRONTIER binding for that harness in `config/model_tiers.yaml`, then sends exactly one line — `Follow the instructions in <path to the compiled brief> exactly.` The compiled brief is whatever the compiler emits for the harness the operator pins nestor to in `config/deployments.yaml`; a persona is emitted only for its pinned harness (`scripts/sync_agents.py:27-31`), and the plan names the path from the pin as it stands at plan time. This spec does not choose the harness. The same convention applies to whichever brief the verifier issue lands on; this spec does not decide that seat's stage-versus-persona question. | Ambient model pins have silently swapped models before, which is why the flag is explicit and its value is read from the tier table rather than written into a persona. One line is what the operator can send. Answers Open question 8. |

## The compiled brief's content

`role` is the one-paragraph charter: a standing judgment seat that does
process decisions, dispatch-prompt authoring, spec-gate support,
unblocking, and keeping the written record true; that never implements,
never reviews pull requests, and never merges except as the resolution
of a decision it owns; and that delegates everything mechanical to
lower tiers per the repository's tier table, keeping its own context
lean.

`advisor-session.md` carries:

- **Orient, in order.** `docs/PLAYBOOK.md` on the default branch —
  mission, operating loop, fabrication catalog, roadmap; the seat owns
  this document and keeps its status snapshot and lessons current.
  Then the newest dated handoff in the operator's home directory, for
  execution state and the ordered plan left by the predecessor; live
  tracker state always beats it. Then the live peer sessions, found
  from the harness's session list, never from a name written in a file
  — a handoff once named a verifier session that was already dead and
  caused a double launch.
- **The cast.** Implementer sessions do the volume and are launched by
  hand. A verifier session reviews everything, re-runs the gates,
  mutation-tests, merges on agreement, and writes fix-round prompts;
  its evidence log is the observations file named in the current
  handoff. The seat itself decides, authors, specs, unblocks, records.
- **Identity.** The interim rule from D11, in one line.
- **Reporting.** Short, plain-language status to the operator: what
  merged, what is blocked on whom, which prompt files are ready to fire
  as full paths, and which decisions are the operator's alone. Flag
  those explicitly; recommend, never decide, on scope and product
  calls.
- **Close-out, mandatory.** Write a new dated handoff for the successor
  (current state, ordered next steps, open operator decisions), update
  the PLAYBOOK status snapshot if reality moved, and reconcile every
  decision made this session against the tracker. This list is what
  #85's `/wrap` would automate; the skill states the obligations, #85
  states the command.

`advisor-truths.md` carries, each one paid for with a shipped defect:

- Never trust an implementer summary, a pull-request body, a green
  check, or an exit code. Fabrication happens at three layers — the
  model, the prompt author, the environment — and the catalog with
  countermeasures is in `docs/PLAYBOOK.md`.
- The seat is itself a fabrication risk. Any factual claim it puts in a
  dispatch prompt — an interface, a derivation, a path, an existing
  behavior — is verified against the live repository first or phrased
  as a discovery step for the implementer.
- Every launch instruction handed to the operator carries an explicit
  model flag, read from `config/model_tiers.yaml`. Ambient pins have
  silently swapped models before.
- Every authored prompt is a file on disk, handed over as a full path
  plus one launch line (D14; PLAYBOOK holds the reason).
- One closing keyword per pull-request body. After a workflow file
  merges, rebase, never re-run. A fix round is a fresh implementer
  session pointed at a self-contained prompt file on the same branch;
  never argue with a stalled session.
- A harness that obeys numbered rules is given numbered rules, in the
  file that harness reads, not prose in a shared one.
- Every decision ends as an issue, a pull request, or an explicit
  "deferred, no tracker" — never only chat. When a defect appears,
  classify it (prompt gap, rules gap, model limitation) and land the
  fix in the layer that owns it.
- Delegation and the context ceiling are cost rules, not style: the
  seat is the most expensive context in the system, so the tier table
  and the 200K working ceiling in AGENTS.md bind as hard limits.

No vendor name, model name or harness name appears in either skill or
in `nestor.yaml`: the vendor rule is enforced inside `personas/**` by
`scripts/ci/sanitize_check.sh:77`.

## Acceptance

- AT-1 `personas/nestor.yaml` validates against `personas/schema.json`
  and `python3 scripts/sync_agents.py --check` exits 0 with the
  committed targets in the tree.
- AT-2 `bash scripts/ci/compiler_roundtrip.sh` exits 0. In particular
  step 5's `- Owner: argus, atlas` assertion is unchanged, because
  nestor joins no rung (D2).
- AT-3 `bash scripts/ci/sanitize_check.sh` exits 0 with no new
  allowlist entry: no home path anywhere, and no vendor, model or
  harness name under `personas/**`.
- AT-4 The compiled target(s) for nestor's pinned harness exist and
  are committed, and the build emits nothing for nestor under any
  other harness's target directory.
- AT-5 `python3 scripts/sync_agents.py --verify` confirms the brief
  carries the FRONTIER-resolved model, the mapped tool list, and the
  full text of both declared skills; it carries no `## Lifecycle
  stages` block, because `resume-protocol.md` is not declared (D7).
- AT-6 `config/execution.yaml` is byte-identical to its pre-change
  state, and `bash scripts/ops/tests/execution_test.sh` and
  `python3 scripts/ops/execution.py --check` both pass unchanged. The
  test's assertion that exactly five bindings are present still holds.
- AT-7 `bash scripts/ops/tests/work_test.sh` and
  `bash scripts/ops/tests/placement_test.sh` pass; they copy the live
  `personas/` and `config/` into their fixtures, so they exercise the
  new source.
- AT-8 The FRONTIER comment in `config/model_tiers.yaml` names two
  FRONTIER consumers and the shared argument, and the `config.bindings`
  section of `docs/SPEC.md` records the amendment to #105.
- AT-9 No sentence in `docs/SPEC.md` or `README.md` states a persona
  count that is false after this change. Specifically, `docs/SPEC.md`
  lines 73, 92, 101 and 208 and `README.md` lines 66 and 144 are
  updated, and `docs/SPEC.md`'s `execution.placement` and `ops.dispatch`
  sections state that nestor is deliberately unbound and owns no rung.
- AT-10 One advisor session, opened per D15 from the compiled brief
  with an explicit model flag, orients in the order the skill states
  (PLAYBOOK, then the newest dated handoff, then the live tracker and
  live peer sessions) and closes out (new dated handoff, PLAYBOOK
  snapshot updated, every decision reconciled to an issue, a pull
  request or an explicit "deferred, no tracker") **without reading
  `ops/charters/persona-advisor.txt`**.
- AT-11 After AT-10 passes, the operator deletes `ops/charters/persona-advisor.txt`
  from the machine that holds it. This is an operator action, not a
  repository change.

## Concerns

- **The claim script hard-fails for an identity of `"TBD"`.**
  `scripts/ops/claim.sh:252-262` posts the claim comment first, then
  compares `authority.identity` in `personas/<actor>.yaml` against the
  login that actually posted, and dies on mismatch — leaving the label
  and the comment behind. So `CLAIM_ACTOR=nestor` is a broken path for
  as long as D11 holds. D3 already forbids claiming as nestor, so the
  spec is self-consistent, but the failure is loud and destructive
  rather than a clean refusal. Not fixed here; filed as #203.
- **`limits` are decorative for this persona (D10).** The schema
  requires them of every `kind: persona` and nothing reads them for a
  seat that is never dispatched. The spec states the values are inert
  instead of pretending they bind.
- **`stage: [intake]` overloads an enum value.** It reads as "the seat
  works at intake", which is nearly true but not the reason it was
  chosen. A dedicated `advise` value would be more honest, at the cost
  of a schema edit that the drift gate and the roundtrip's lifecycle
  step both exercise. D2 takes the cheaper option deliberately; if a
  later persona needs the same trick, add the value then.

## Out of scope

- The verifier seat's own design (stage versus persona). Its issue
  owns that; this spec fixes only the shared launch convention.
- A GitHub App for nestor. Registering one is an operator decision (see
  below); until then `identity: "TBD"` and the interim rule in D11
  stand, and `scripts/auth/app_manifests.yaml` gains no entry.
- Mechanizing close-out. #85 owns `/wrap`; D13 makes the skill's list
  its specification, not a competing implementation.
- Graduating the shared dispatch preamble into the repository (#181).
- Any change to who merges. The seat's "merge only as a decision being
  resolved" is narrower than the verifier's interim authority and adds
  no second merge path; reviewer-consensus merge (#64, #151) is
  untouched.

## Operator decisions

1. **Does nestor get its own GitHub App?** If yes, a manifest entry, a
   registration run and a private key follow, and `identity.bots` in
   `docs/SPEC.md` becomes "seven". If no, D11's interim rule is the
   permanent answer and that section gets an explicit carve-out.
2. **Deleting `ops/charters/persona-advisor.txt`** once AT-10 passes (AT-11).
3. **The harness pin** for nestor in `config/deployments.yaml`. The
   spec states the re-pin property (D15: the brief follows the pin);
   the value is set in config by the operator, never in a spec.
