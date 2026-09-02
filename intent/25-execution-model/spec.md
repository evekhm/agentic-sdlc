# Spec: execution model for unattended personas

**Issue:** #25 · **Status:** Draft ·
**Author:** athena (`evekhm-athena-app[bot]`) ·
**Open questions:** 5 — nothing is dispatched against a Draft.

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

They are independent: a repository event can start a hosted job *or*
enqueue work a local runner picks up. Deciding placement per persona
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

| | Hosted (GitHub Actions) | VM-local (presenter's machine) |
|---|---|---|
| **Credentials** | each `*_APP_PRIVATE_KEY` becomes an Actions secret; model reached by workload identity federation, no cloud key at rest | keys stay in `~/.keys/`, the repo's secret store stays empty; model reached by local application-default credentials |
| **Observability from the presenter's seat** | run log is a shareable URL that streams live and survives the talk | a terminal, richest view of all, but only while that machine is the one on the projector |
| **`hold` interrupt** | label read at job start; stopping a run already going is `gh run cancel` | label read at dispatch; stopping a run already going is Ctrl-C |
| **Cost shape** | event-triggered, so idle costs nothing; per-run dollar cap enforced by the runner | free if a workflow pings the box; a poller pays a full cache write per pass even when nothing happened (AGENTS.md, "Cost of execution") |
| **Live demo-ability** | works with the laptop closed; an attendee can trigger it from their own seat | needs the machine up, unlocked and on the network — a conference wifi drop ends the demo |
| **Public-repo safety** | a fork pull request gets no secrets, so it gets no automated run; needs the federation attribute condition pinned to this repository | no cloud credential is ever exposed to CI; the blast radius is one box |

Hybrid means choosing per persona, which the config shape below
permits by construction.

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
| D2 | `config/execution.yaml` is keyed by persona name and carries, per persona with an unattended duty: `trigger` (one of `repo-event`, `scheduled`, `manual`), `placement` (one of `hosted`, `vm-local`), `events` (the GitHub event names, for `repo-event`), and `max_cost_usd`. A persona with no unattended duty has no entry. Testable: the file parses, every key is drawn from those enumerations, and every persona named in it exists in `personas/`. |
| D3 | Credentials move by NAME only. `config/execution.yaml` never names a secret value, a file path, or a home directory; the secret NAME already lives in the persona source (`authority.token`, #1 D6) and is not restated. Placement is expressed as `placement`, and the store follows from it. Testable: the sanitization gate (#6) passes on the new file with no allowlist entry. |
| D4 | An App being *registered* is not an App being *installed here*. Every unattended run's first step is a preflight asserting, against `GET /installation/repositories`, that the persona's App installation covers this repository; on failure the run writes nothing and exits non-zero with a named error. Grounds: an installation token mints successfully whether or not the installation's repository selection includes this repository, so without the preflight the failure surfaces at the first write, after the model has already been paid for. All six installations cover `evekhm/agentic-sdlc` today (session finding, 2026-09-02), but that is a property of one account's installation settings, not of the repository — a fork or take-home clone starts without it. |
| D5 | `hold` is checked first and it is absolute at dispatch. Every unattended run re-reads the labels of its target immediately before any model call; if `hold` is present it writes nothing, makes no model call, and exits 0 — a green exit, not an error. This mirrors `scripts/ci/lifecycle_advance.sh`, which checks `hold` before every other condition, and the trusted-posting skill's rule 5. Testable: with `hold` applied, a triggered run completes green and posts nothing. |
| D6 | No model-bearing unattended run receives unrestricted tools, and none receives a credential in its prompt. A hosted run declares an explicit tool allowlist or no tools at all; repository and thread data reach it as fenced, clearly-delimited untrusted input; the GitHub write goes through a repository posting script, never an API call composed inline by the model. Per the trusted-posting skill rules 1–2 and the predecessor's two review workflows, which both do exactly this. |
| D7 | Automated runs never trigger on `pull_request_target` and therefore never run against a fork's pull request; a fork pull request gets human review only. Grounds: `pull_request_target` runs fork code against the base repository's secrets, which is the exact exposure intent.md's public-repo constraint is about; the predecessor's Gemini-side workflow already restricts itself to same-repository heads. Testable: no workflow added under this decision uses `pull_request_target`. |
| D8 | Turn and time caps come from the persona source (`limits`, #1 D9); the dollar cap comes from `config/execution.yaml` (`max_cost_usd`, D2). Neither is written into a workflow file. Exceeding a cap is a green exit with a comment naming the cap, not a red run. Testable: no workflow literal duplicates a value already in `personas/*.yaml` or `config/execution.yaml`. |
| D9 | A `scheduled` duty is either deterministic with zero model calls, or it dispatches a fresh one-shot run per pass. A long-lived polling conversation is forbidden at any cadence. Grounds: AGENTS.md's cadence-versus-cache-TTL rule and the predecessor's measurement that a 15-minute loop on a 5-minute cache TTL consumed roughly 90% of one session's spend on cache writes that no read amortized. Testable: no unattended duty holds a model context across passes. |
| D10 | The unattended-execution decision does not change `personas/**`. Placement, trigger, events, and cost caps are all `config/` facts; a persona source that gained an execution field would fail the vendor-agnosticism rule it was written under (#1 D3/D4, #2 D2). Testable: the implementing PR's diff touches no file under `personas/`. |

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

## Open questions

Numbered so each resolution becomes the next Decision row. Nothing is
dispatched against this spec until the section is empty.

**Q1 — Placement for the two reviewers (#8 Argus, #9 Atlas).**
*Reading A:* both hosted. Actions carries the trigger and the model
call; `ARGUS_APP_PRIVATE_KEY` and `ATLAS_APP_PRIVATE_KEY` become
Actions secrets, executing the step #7 is holding.
*Reading B:* Actions captures the event only and the model-bearing run
happens on the presenter's box; no App key ever becomes an Actions
secret.
*The assertion that differs:* an attendee, from their own laptop,
opens a pull request against this repository at 14:02 while the
presenter's machine is asleep in a bag. Under A, two reviews are on
the pull request within minutes and the run logs are two URLs the room
can open. Under B, nothing is posted until the presenter wakes the
machine. Also observable without waiting: under A the repository's
secret list is non-empty, under B it stays empty as it is today.
*Note on decisiveness:* the evidence leans hard to A for #9 —
`docs/ATLAS_DEPLOYMENT_OPTIONS.md` weighed this exact pair for this
exact persona and chose Actions, for uptime reasons that apply more,
not less, to a conference room. I still put it to the product owner,
because the reason to prefer B is one the predecessor never had: this
repository is a demo, and "the model runs where the audience can see
it" is a product requirement, not an engineering one.

**Q2 — Placement for Athena's intake (#10).**
*Reading A:* hosted, same as the reviewers. An `intent:new` label
produces an intent pull request with no human in the loop, which is
#10's stated Done-when, and `ATHENA_APP_PRIVATE_KEY` becomes an
Actions secret with contents and pull-request write.
*Reading B:* the trigger is `manual` for v1 — the presenter dispatches
Athena in a live interactive session, and the automated label trigger
is deferred.
*The assertion that differs:* an attendee files an issue and applies
`intent:new` during the coffee break. Under A, `intent/<n>-<slug>/
intent.md` exists on a branch named `athena/<n>-<slug>` before the
break ends, authored by `evekhm-athena-app[bot]`. Under B, the issue
sits at `status:planning` with no branch until the presenter runs the
session on stage. The two readings also differ in blast radius: A puts
a contents-write private key for the only persona that can push
branches into a CI secret store; B does not.

**Q3 — Does `hold` reach a run already in flight?**
D5 settles the dispatch gate; this is the remainder of intent.md's
open question 4.
*Reading A:* `hold` is a dispatch gate only. A run that passed the
check finishes and posts, and the label governs the next dispatch.
This is what `lifecycle_advance.sh` does today and what the
predecessor's budget gate did.
*Reading B:* `hold` also cancels in flight. The run polls the label
between phases, or an on-labeled workflow cancels the in-progress run.
*The assertion that differs:* a review starts at 14:00 and takes four
minutes; a human applies `hold` at 14:01 because the pull request is
wrong. Under A a full review lands at 14:04 on a held pull request.
Under B nothing is posted. INTENT.md calls `hold` "the circuit breaker
halting all automation" and AGENTS.md calls it absolute; A is
defensible only if "absolute" is read as governing dispatch.

**Q4 — What does `hold` attach to for a pull-request-triggered run?**
*Reading A:* the run checks `hold` on the object that triggered it —
the pull request — and nothing else.
*Reading B:* the run checks `hold` on the pull request and on every
issue the pull request closes.
*The assertion that differs:* pull request #42 carries no labels; its
body says `Closes #25`; issue #25 carries `hold`. Under A both
reviewers review #42. Under B both write nothing. The label taxonomy
(#4) attaches `hold` to issues in practice — `lifecycle_advance.sh`
only ever reads issue labels — so the case is not hypothetical.

**Q5 — Where does a hosted run get its model identifier?**
*Reading A:* from `config/model_tiers.yaml`, resolved through the
compiled persona target, so the tier ladder is the single source and a
model swap is one edit in `config/`.
*Reading B:* from a repository variable read by the workflow, as the
predecessor did. `config/model_tiers.yaml`'s own header grants this:
"where a workflow pins a model in an env var, that pin wins over this
file until the compiler (#5) starts generating the workflows" — and
#5 landed generating persona targets, not workflows, so the grant is
still live by its literal terms.
*The assertion that differs:* an operator changes the reviewer tier's
model in `config/model_tiers.yaml` and merges. Under A the next review
runs on the new model. Under B it runs on the old one, because the
repository variable was never touched, and the distinct-model-families
constraint (#2 D4) is being checked against a file that no longer
describes what runs.

## Sources

Read for this spec:

- `intent/25-execution-model/intent.md`; issue #25 and its comments.
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
