# Spec: execution model for unattended personas

**Issue:** #25 · **Status:** Approved ·
**Author:** athena (`evekhm-athena-app[bot]`) ·
**Open questions:** none.

Q1–Q5 were answered by the product owner on PR #34 (presenter
direction, 2026-09-02) and land below as D11–D15; the four structural
edits requested alongside them land as D16–D19. The governing
principle stated there: **stages** — get the loop working end to end
first, then add or move deployment options, and keep every move cheap.

Answers `intent/25-execution-model/intent.md` and nothing wider.
Cassandra (#11) appears only where the shape differs; INTENT.md open
question 3 defers her cadence to when #11 is picked up, and this spec
does not take it back.

## What is being decided

Two things that intent.md ran together and that turn out to be
orthogonal:

- **Trigger shape** — what wakes the run.
- **Placement** — whose machine the model-bearing process runs on,
  and therefore where the credential sits.

They are independent: a repository event can start a `gh-actions` job
*or* enqueue work a local runner picks up. Deciding placement per persona
does not decide the trigger, and vice versa. Both are deployment
facts, so both are `config/` data (#2 D2) and neither touches a
persona source (#1 D3/D4).

## The three trigger shapes

| Shape | Fires on | Runs without a session | Used by |
|---|---|---|---|
| **repo-event** | a GitHub webhook event (`pull_request`, `issues`, `issue_comment`, `push`) | yes | #8, #9, #10 |
| **in-session hook** | a harness event inside a live interactive session (Claude Code `PreToolUse`/`PostToolUse`/`Stop`, plugin monitors) | no — dies with the session | none of #8–#11 |
| **scheduled watcher** | a clock, with no external event | yes | #11 |

The middle shape is the one #23's "Triggers & Rules" pillar describes
and it is the one none of the Rung 3 duties can use: every one of them
must fire when no human has a session open (session finding,
2026-09-02).

## Placement options weighed

| | `gh-actions` (GitHub Actions) | `vm-local` (presenter's machine) |
|---|---|---|
| **Credentials** | each `*_APP_PRIVATE_KEY` becomes an Actions secret; model reached by workload identity federation, no cloud key at rest | keys stay in `~/.keys/`, the repo's secret store stays empty; model reached by local application-default credentials |
| **Observability from the presenter's seat** | run log is a shareable URL that streams live and survives the talk | a terminal, richest view of all, but only while that machine is the one on the projector |
| **`hold` interrupt** | label read at job start; stopping a run already going is `gh run cancel` | label read at dispatch; stopping a run already going is Ctrl-C |
| **Cost shape** | event-triggered, so idle costs nothing; per-run dollar cap enforced by the runner | free if a workflow pings the box; a poller pays a full cache write per pass even when nothing happened (AGENTS.md, "Cost of execution") |
| **Live demo-ability** | works with the laptop closed; an attendee can trigger it from their own seat | needs the machine up, unlocked and on the network — a conference wifi drop ends the demo |
| **Public-repo safety** | a fork pull request gets no secrets, so it gets no automated run; needs the federation attribute condition pinned to this repository | no cloud credential is ever exposed to CI; the blast radius is one box |

Hybrid means choosing per persona, which the config shape below
permits by construction. These two are v1's adapters, not the whole
set: D17 makes `placement` a registry, so the columns above are the
first two entries in it rather than an enumeration.

The predecessor tried both and moved. Its Atlas began as a polling
sidecar on a workstation and was retired in favour of an Actions
workflow because polling needed host uptime and lock files
(`docs/ATLAS_DEPLOYMENT_OPTIONS.md`). Its Odyssey is still a local
bash watcher polling every 120 seconds that dispatches a fresh
one-shot headless run per mention, and its measured cost lessons rank
the polling loop as the single largest avoidable line item. That
history bears on #8 and #9 directly; it says less about #10, whose
value in this workshop is partly that the presenter and the room watch
Athena think.

## Decisions

| ID | Decision |
|----|----------|
| D1 | Execution placement is a new axis and lands in a new file, `config/execution.yaml` — not a key inside `deployments.yaml`. Per #2 D1, one axis per file so a swap edits exactly one place; harness (which framework reads the persona) and placement (whose machine runs it) change independently. Testable: `deployments.yaml` contains no `execution`, `trigger`, or `placement` key. |
| D2 | `config/execution.yaml` is keyed by persona name and carries, per persona with an unattended duty: `trigger` (one of `repo-event`, `scheduled`, `manual`), `placement` (**an adapter name from the D17 registry**, not a value from a fixed enum — `gh-actions` and `vm-local` in v1), `events` (the GitHub event names, for `repo-event`), and `max_cost_usd`. A persona with no unattended duty has no entry. Testable: the file parses; `trigger` is drawn from its enumeration; every `placement` resolves to an adapter directory (D17); every persona named in it exists in `personas/`. |
| D3 | Credentials move by NAME only. `config/execution.yaml` never names a secret value, a file path, or a home directory; the secret NAME already lives in the persona source (`authority.token`, #1 D6) and is not restated. Placement is expressed as `placement`, and the store follows from it. Testable: the sanitization gate (#6) passes on the new file with no allowlist entry. |
| D4 | An App being *registered* is not an App being *installed here*. Every unattended run's first step is a preflight asserting, against `GET /installation/repositories`, that the persona's App installation covers this repository; on failure the run writes nothing and exits non-zero with a named error. Grounds: an installation token mints successfully whether or not the installation's repository selection includes this repository, so without the preflight the failure surfaces at the first write, after the model has already been paid for. All six installations cover `evekhm/agentic-sdlc` today (session finding, 2026-09-02), but that is a property of one account's installation settings, not of the repository — a fork or take-home clone starts without it. |
| D5 | `hold` is checked first and it is absolute at dispatch. Every unattended run re-reads the labels of its target immediately before any model call; if `hold` is present it writes nothing, makes no model call, and exits 0 — a green exit, not an error. This mirrors `scripts/ci/lifecycle_advance.sh`, which checks `hold` before every other condition, and the trusted-posting skill's rule 5. Testable: with `hold` applied, a triggered run completes green and posts nothing. |
| D6 | No model-bearing unattended run receives unrestricted tools, and none receives a credential in its prompt. A run under any adapter declares an explicit tool allowlist or no tools at all; repository and thread data reach it as fenced, clearly-delimited untrusted input; the GitHub write goes through a repository posting script, never an API call composed inline by the model. Per the trusted-posting skill rules 1–2 and the predecessor's two review workflows, which both do exactly this. |
| D7 | Automated runs never trigger on `pull_request_target` and therefore never run against a fork's pull request; a fork pull request gets human review only. Grounds: `pull_request_target` runs fork code against the base repository's secrets, which is the exact exposure intent.md's public-repo constraint is about; the predecessor's Gemini-side workflow already restricts itself to same-repository heads. Testable: no workflow added under this decision uses `pull_request_target`. |
| D8 | Turn and time caps come from the persona source (`limits`, #1 D9); the dollar cap comes from `config/execution.yaml` (`max_cost_usd`, D2). Neither is written into a workflow file. Exceeding a cap is a green exit with a comment naming the cap, not a red run. Testable: no workflow literal duplicates a value already in `personas/*.yaml` or `config/execution.yaml`. |
| D9 | A `scheduled` duty is either deterministic with zero model calls, or it dispatches a fresh one-shot run per pass. A long-lived polling conversation is forbidden at any cadence. Grounds: AGENTS.md's cadence-versus-cache-TTL rule and the predecessor's measurement that a 15-minute loop on a 5-minute cache TTL consumed roughly 90% of one session's spend on cache writes that no read amortized. Testable: no unattended duty holds a model context across passes. |
| D10 | The unattended-execution decision does not change `personas/**`. Placement, trigger, events, and cost caps are all `config/` facts; a persona source that gained an execution field would fail the vendor-agnosticism rule it was written under (#1 D3/D4, #2 D2). Testable: the implementing PR's diff touches no file under `personas/`. |
| D11 | **Both reviewers (#8 Argus, #9 Atlas) bind to `gh-actions` in v1** — Actions carries the event *and* the model-bearing run, and `ARGUS_APP_PRIVATE_KEY`/`ATLAS_APP_PRIVATE_KEY` become Actions secrets, releasing the step #7 is holding. Grounds: PR #34, presenter direction, 2026-09-02 — App keys as Actions secrets are acceptable for comment-only personas with D6 and D7 in force; and `docs/ATLAS_DEPLOYMENT_OPTIONS.md` weighed this exact pair for this exact persona and chose Actions on uptime grounds. `v1` is part of the decision, not a hedge: the binding is staged (D19) and a later move costs one line (D18). Atlas's `antigravity` pin does not block this — headless invocation of that harness is confirmed (#25, comment 2026-09-02) — so the `gh-actions` adapter must be able to start **either** pinned harness non-interactively (D16). Observable: an attendee opens a pull request at 14:02 with the presenter's machine asleep in a bag; two reviews are posted within minutes and the two run logs are URLs the room can open; the repository's Actions secret list is non-empty where it is empty today. |
| D12 | **Athena's intake (#10) is `trigger: manual` in v1**, dispatched through the one-argument tooling (D16), and no Athena App key becomes an Actions secret in v1. The recorded later target placement for intake is **`agent-engine`** (D17, reserved) — intake is the most user-facing persona and is the first to move once that adapter exists. Grounds: PR #34, presenter direction, 2026-09-02; B's blast radius argument stands — v1 does not put a contents-write private key for the only branch-pushing persona into a CI secret store. Observable: an attendee files an issue and applies `intent:new` during the coffee break; the issue sits at `status:planning` with no `athena/<n>-<slug>` branch until the presenter dispatches on stage, and the Actions secret list contains no Athena key. |
| D13 | **`hold` is a dispatch gate AND is re-read immediately before every write.** No in-flight cancellation is added: a run that passed dispatch is not killed mid-call. Instead, every run re-reads its target's labels immediately before each GitHub write; if `hold` is present it discards the output, posts nothing, and exits 0 (green). This extends D5 from one check to one check per write. Grounds: PR #34, presenter direction, 2026-09-02 (Reading A plus that rule). Observable: a review starts at 14:00 and finishes at 14:04; a human applies `hold` at 14:01. The review is computed and paid for, nothing is posted, and the run is green — the held pull request never receives the comment that Reading A alone would have landed at 14:04. |
| D14 | **For a pull-request-triggered run, `hold` attaches to the pull request AND to every issue it closes** — any one of them carrying the label suppresses the write. Closure links resolve the same way `work.sh` resolves a pull request to its issue: `Closes #<n>` in the body, else the `<actor>/<n>-<slug>` branch name (#36, D9). Grounds: PR #34, presenter direction, 2026-09-02; the label taxonomy (#4) attaches `hold` to issues in practice, so a pull-request-only check would leak past the circuit breaker. Observable: pull request #42 carries no labels, its body says `Closes #25`, and #25 carries `hold` — both reviewers write nothing and exit green. |
| D15 | **A run's model identifier comes from `config/model_tiers.yaml`, resolved through the compiled persona target for the harness pinned in `config/deployments.yaml`** — never from a repository, platform or runner variable. `config/model_tiers.yaml`'s header grant ("where a workflow pins a model in an env var, that pin wins") is retired by this row and is deleted by the implementing PR. Grounds: PR #34, presenter direction, 2026-09-02 — "a runner that reads a platform variable cannot move"; and the distinct-model-families constraint (#2, D4) is checked against `model_tiers.yaml`, so a runner-side pin makes CI verify a file that no longer describes what runs. Observable: an operator changes the reviewer tier's model in `config/model_tiers.yaml` and merges; the next review runs on the new model with no other edit anywhere. |
| D16 | **The portable unit of execution is one line: `scripts/ops/work.sh <n> --as <persona>`** (#36, D7–D10). Every placement runs that line and nothing else, and a trigger supplies only the number — never a stage, folder, branch, artifact, prompt or model, because a flag naming any of those lets a run work a stage the labels say is not current (#36, D7). An adapter must be able to run it non-interactively for either pinned harness: headless invocation is confirmed for `antigravity` (#25, comment 2026-09-02), and where a harness cannot be started `work.sh` prints the persona, target and prompt and exits 0 — a supported outcome, not an adapter failure (#36, D10). Adapters are validated with `DRY_RUN=1`, which reads and refuses exactly as a live run would and writes nothing to GitHub (#36, D8). Testable: each adapter's launch step is that single command; a grep across the adapters finds no second dispatch path and no inline prompt. |
| D17 | **`placement` is a registry of runner adapters, not a two-value enum.** One adapter per directory, `scripts/placement/<name>/`, whose entrypoint invokes D16's line; the directory name IS the value legal in `config/execution.yaml`. v1 ships **`gh-actions`** and **`vm-local`**. Reserved names — documented, no adapter yet — are **`cloud-run-worker`** (queue-consuming background fleet for reviewers and builders), **`cloud-run-instance`** (always-on singleton loop, the shape a continuous watcher needs) and **`agent-engine`** (managed agent platform; intake's later target, D12). Reserved means the name is spelled and nothing more: **validation fails on any binding naming a placement with no adapter directory**, with a named error — reserving a name must not become a way to ship a binding that cannot run. Grounds: PR #34, presenter direction, 2026-09-02, with #40 as input to this row rather than a separate track; the topologies and their intended workloads are #40's. Testable: `placement: cloud-run-worker` fails the config gate today with a named error, and the same unchanged file passes once the adapter directory is merged. |
| D18 | **Cost of a move is fixed and it is one line each.** Moving a persona between placements is one edit to its `placement` value in `config/execution.yaml`, plus an adapter that is already merged — nothing else. Moving a persona between harnesses is one edit to `personas.<name>.harness` in `config/deployments.yaml` — nothing else. Neither move touches `personas/**`, `scripts/ops/work.sh`, another adapter, or the compiler: the compiler is deliberately harness-only and carries no deployment-target knowledge, so execution is an adapter layered on the compiled artifacts (#25, comment 2026-09-02; #5; #2, D2; D10 above). Both are Acceptance checks below. |
| D19 | **Staged rollout — the v1 bindings written into `config/execution.yaml`.** `argus` (#8): `trigger: repo-event`, `placement: gh-actions`. `atlas` (#9): `trigger: repo-event`, `placement: gh-actions`. `athena` intake (#10): `trigger: manual`, `placement: vm-local`. Every other persona with a duty in v1 — `daedalus`, `odyssey` — is `trigger: manual`, `placement: vm-local`. `cassandra` gets no entry: her cadence is #11's to decide (INTENT.md open question 3), and D2 says a persona with no unattended duty has no entry. Grounds: PR #34, presenter direction, 2026-09-02 (item 4), under the stages principle — the loop works end to end on two adapters before a third is built. Testable: `config/execution.yaml` at the end of the implementing PR contains exactly these entries and no others. |

## Acceptance

- `config/execution.yaml` parses, satisfies D2, and passes the
  sanitization gate with no new allowlist entry (D3).
- `deployments.yaml` is unchanged except, at most, a comment pointing
  at the new file (D1).
- With `hold` applied to the target, each wired duty completes green
  and posts nothing (D5).
- Against an installation whose repository selection excludes this
  repository, each wired duty fails preflight before any model call
  (D4). The six installations cover it today, so this is exercised by
  pointing the preflight at a repository outside the selection.
- `personas/**` is untouched by the implementing PR (D10).
- The living spec (`docs/SPEC.md`) gains an `execution.placement`
  entry in the same PR, and `identity.bots` is amended to say which
  private keys are Actions secrets, since it currently offers both
  stores without choosing.
- `config/execution.yaml` contains exactly D19's bindings (D19), and
  every `placement` in it resolves to a directory under
  `scripts/placement/` (D17).
- **A placement move is one line.** Changing `argus`'s `placement`
  from `gh-actions` to `vm-local` (an adapter that already exists)
  produces a one-line diff, in `config/execution.yaml` only, and the
  duty still runs (D18).
- **A harness move is one line.** Changing `personas.atlas.harness`
  in `config/deployments.yaml` produces a one-line diff, in that file
  only, and the duty still runs (D18).
- A binding naming a reserved placement with no adapter directory
  fails the config gate with a named error, and passes unchanged once
  the adapter is merged (D17).
- Every adapter's launch step is exactly
  `scripts/ops/work.sh <n> --as <persona>`, and `DRY_RUN=1` through
  each adapter reads, refuses correctly and writes nothing (D16).
- With `hold` applied after dispatch but before the write, the run
  completes green and posts nothing (D13); with `hold` on an issue a
  triggered pull request closes, the run posts nothing (D14).

## Contradictions

Passages elsewhere in the repository that these decisions falsify.
Each is fixed by the implementing PR or filed as a named follow-up;
none is left to be discovered by a builder reading the wrong file.

- **`INTENT.md` and `docs/` should say GitHub Actions is *event
  capture*, not the runtime.** Under D17 Actions is one adapter among
  several, and for a `vm-local` binding it is only the thing that
  notices the event. Text that reads "the automation runs in Actions"
  makes D18's one-line move look like a rewrite and quietly re-couples
  the trigger axis to the placement axis that "What is being decided"
  separates.
- `docs/CONTEXT.md` §1 describes the predecessor's Atlas polling
  sidecar as if it were current; it was retired in favour of a
  workflow (`docs/ATLAS_DEPLOYMENT_OPTIONS.md`).
- `config/model_tiers.yaml`'s header grants a workflow env-var pin
  precedence over the file. D15 retires that grant; the implementing
  PR deletes the sentence rather than leaving it live.
- `docs/SPEC.md` `identity.bots` offers both credential stores without
  choosing. D11 and D12 choose: the two reviewer keys become Actions
  secrets, the Athena key does not.

## Open questions

none.

## Sources

Read for this spec:

- **PR #34, presenter direction, 2026-09-02** — the answers to Q1–Q5
  and the four structural edits; the citable authority for D11–D19.
- `intent/25-execution-model/intent.md`; issue #25 and its comments,
  including the 2026-09-02 comment recording that headless invocation
  is confirmed for the second harness, that the compiler (#5) is
  deliberately harness-only with no deployment-target knowledge, and
  that INTENT.md open question 3 already holds the orthogonality
  principle this spec operationalizes.
- `intent/36-dispatch/spec.md` D7–D10 and `scripts/ops/work.sh` — the
  one-argument contract, `--as`, `DRY_RUN=1`, the exit codes and the
  print-instead-of-launch rule that D16 and D17's adapters invoke.
- Issue #40 — the two Cloud Run agent topologies and the managed
  agent platform, read as input to D17's reserved names.
- `INTENT.md` — lifecycle, persona cast, identity/auth separation,
  open question 3, Constraints.
- `docs/SPEC.md` — `identity.bots`, `config.bindings`,
  `lifecycle.labels`, `ci.gates`, `personas.compiler`, "Agreed, not
  yet built"; `docs/CONTEXT.md` §1.
- `AGENTS.md` — "Cost of execution"; `hold` as circuit breaker.
- `intent/1-personas/spec.md` and `intent/2-config/spec.md` (D1–D6),
  used as format and as cited authority.
- `config/deployments.yaml`, `config/model_tiers.yaml`,
  `config/tools.yaml`; `personas/{athena,argus,atlas,cassandra}.yaml`
  authority and limits blocks; `personas/schema.json`.
- `scripts/auth/README.md`; `scripts/ci/lifecycle_advance.sh` header
  and its `hold` branch; `.github/workflows/ci-gates.yml`,
  `.github/workflows/lifecycle.yml`.
- Issues #2, #7 (per-persona App permissions; the note that no App
  private key becomes an Actions secret until this decision lands),
  #8, #9, #10, and #23's "Triggers & Rules" pillar.
- Predecessor `agentic-experiments-lab`, read from the local checkout
  because the GitHub repository returns 404 to this session's token:
  `.github/workflows/claude-pr-review.yml`, `agy-pr-review.yml`,
  `claude-hourly-sweep.yml`, `docs/ATLAS_DEPLOYMENT_OPTIONS.md`,
  `docs/ATLAS_SIDECAR_SETUP.md`, `scripts/odyssey/`,
  `docs/COST_LESSONS.md`.
- Session findings, 2026-09-02: all six persona App installations
  cover this repository, confirmed by a paginated read of
  `/installation/repositories`; the repository's Actions secret and
  variable lists are both empty; the repository is currently private.
