# Plan: execution model for unattended personas

**Issue:** #25 · **Spec:** spec.md (Approved) · **Author:** daedalus

Ten tasks; each names its files, the D-rows it satisfies, and the check
that proves it. Lines cite **a69f7f5** (`origin/odyssey/36-35-land`, the
landing PR #45 for #36/#35): `scripts/ops/work.sh`, the `ops.dispatch`
and `personas.resume` entries of `docs/SPEC.md` and `personas/lifecycle.json`
are on that branch and NOT on `main`, and every task below assumes them.
**#45 merges first.**

Order is most-tested-first: T1–T8 are provable by deterministic local
runs against a stub `gh`; T9 is the one step whose proof is a live run;
T10 is prose. Within that, T1→T2 (the reader needs the data shape), T3
before T4 and T5, T6 independent, T7 after #45, T8 after T1–T7.

Following #36's precedent, this build stage commits the plan only. The
contract tests are specified inside the tasks — file, scenarios, and the
D-row each scenario pins — and written by the implementer with the code
they prove; nothing under `tests/` is committed here.

**#43 owns four things this plan does not re-plan:** work.sh's
`antigravity` launch-table row, work.sh minting the owning persona's App
token for the child process, the thin `/work` skill, and the AGENTS.md
dispatch rule. T4 names #43 as the dependency it builds on.

## T1 · `config/execution.yaml` (NEW) — D1, D2, D3, D19

A new file, not a key in `deployments.yaml`: one axis per file, so a
placement swap edits exactly one place (D1). D19's bindings and no
others; `cassandra` has no entry because #11 owns her cadence.

```yaml
# Persona -> execution binding (#25). One axis per file (#2 D1):
# harness is config/deployments.yaml, placement is here. A persona with
# no unattended duty has no entry. No secret value, no file path and no
# home directory appears here (D3) — the private-key NAME already lives
# in personas/<name>.yaml authority.token and is not restated.

personas:
  argus:
    trigger: repo-event
    events: [pull_request]
    placement: gh-actions
    max_cost_usd: 2.00
  atlas:
    trigger: repo-event
    events: [pull_request]
    placement: gh-actions
    max_cost_usd: 2.00
  athena:    { trigger: manual, placement: vm-local, max_cost_usd: 5.00 }
  daedalus:  { trigger: manual, placement: vm-local, max_cost_usd: 5.00 }
  odyssey:   { trigger: manual, placement: vm-local, max_cost_usd: 10.00 }
```

**Proves it (Acceptance 1, 2, 7):** T2's `--check`; `sanitize_check.sh`
green with no new line in `scripts/ci/sanitize_allowlist.txt` (D3);
`grep -nE '^\s*(execution|trigger|placement):' config/deployments.yaml`
empty (D1). The `max_cost_usd` numbers are the one thing the spec does
not fix — see "Values the spec does not fix".

## T2 · `scripts/ops/execution.py` (NEW) — D2, D17

The ONE parser of the new axis; no adapter, workflow or shell script
re-reads the YAML. It does **not** live in `scripts/sync_agents.py`: the
compiler is deliberately harness-only and carries no deployment-target
knowledge (#25, comment 2026-09-02; D18), and teaching it placement
would break the very separation D18 prices at one line. `pyyaml` only —
the compiler's whole dependency budget (#5, D10).

- `--check` (the gate): top-level mapping with `personas:`; every key is
  a `personas/<name>.yaml` whose `kind` is `persona`; `trigger` is one of
  `repo-event`, `scheduled`, `manual`; `events` is present and non-empty
  exactly when `trigger` is `repo-event`; `max_cost_usd` is a positive
  number; any other key is an error. Every `placement` resolves to
  `scripts/placement/<name>/run.sh` or the run fails with D17's named
  error: `execution.yaml: persona 'atlas' names placement
  'cloud-run-worker', which has no adapter directory
  scripts/placement/cloud-run-worker/`. When any binding is
  `repo-event`, `.github/workflows/unattended.yml` must exist and its
  `on:` block must list every `events` value in the file (T9).
- `--subscribers <event>` — `<persona>\t<placement>` per `repo-event`
  binding carrying that event, sorted. The dispatcher's whole input.
- `--binding <persona>` — `trigger placement max_cost_usd`, for an
  adapter's report line.

**Proves it (Acceptance 7, and D17's round trip):** T8's
`execution_test.sh`, whose last scenario is D17 exactly — a fixture
binding `placement: cloud-run-worker` exits non-zero with the named
error, and the **same unchanged fixture** exits 0 once an empty
`scripts/placement/cloud-run-worker/run.sh` is created beside it.

## T3 · `scripts/placement/README.md` (NEW) — the registry — D16, D17

Not documentation about the adapters; the contract they are checked
against. It states: the directory name IS the value legal in
`config/execution.yaml`; every adapter is `scripts/placement/<name>/run.sh`,
called as `run.sh <number> --as <persona>` and taking nothing else; its
final line is `exec "$REPO_ROOT/scripts/ops/work.sh" "$n" --as "$persona"`
and no adapter composes a prompt, names a stage, folder, branch,
artifact or model (D16); `DRY_RUN=1` passes through unchanged, which is
how an adapter is validated without writing; exit codes are work.sh's,
unchanged (0 launched or printed, 2 a stated refusal, 1 unusable input).
It then spells the three reserved names with one line each on the
intended workload — `cloud-run-worker` (queue-consuming background
fleet), `cloud-run-instance` (always-on singleton loop) and
`agent-engine` (managed agent platform, intake's later target, D12) —
and states that a binding naming one fails T2's check until its
directory is merged.

**Proves it (Acceptance 9):** T8 greps every `scripts/placement/*/run.sh`
for exactly one `work.sh` invocation, no second dispatch path, and no
inline prompt (D16's testable).

## T4 · `scripts/placement/vm-local/run.sh` (NEW) — D16, D17, D19

The presenter's machine, and the placement four of the five bindings
use. `set -euo pipefail`; parse `<number> --as <persona>`; run T6's
preflight; print one report line
(`vm-local: #<n> as <persona> (max_cost_usd <x>)` from
`execution.py --binding`); `exec` work.sh.

The App private key is resolved by `scripts/auth/mint_app_token.py`'s
existing lookup — the environment variable named by `authority.token`,
else the operator's local key directory — so this file names neither a
path nor a home directory and the sanitize gate's `home` rule passes
with no allowlist entry (D3). The token for the launched session is
minted by work.sh (#43, item 2); this adapter mints none and exports
none. Until #43 merges the launched session posts as the ambient
identity: the adapter prints that as one named line rather than letting
it be a silent difference.

**Proves it (Acceptance 9):** T8's `placement_test.sh` —
`DRY_RUN=1 scripts/placement/vm-local/run.sh 25 --as daedalus` against
the stub `gh` yields work.sh's dry-run report, exit 0, zero writes.

## T5 · `scripts/placement/gh-actions/run.sh` (NEW) — D11, D16, D17

T4's shape with one difference: the private key arrives as an
environment variable **named by** the persona's `authority.token` (D3),
which T9's workflow sets from the Actions secret of the same name. The
adapter reads only the NAME out of `personas/<persona>.yaml`, asserts
the variable is non-empty, and exits 1 with `gh-actions:
ARGUS_APP_PRIVATE_KEY is not set in this environment` — it never prints,
logs, or writes the value (trusted-posting rule 2). Model access is
workload identity federation configured on the job, not here: no cloud
key at rest (spec, placement table).

**Proves it:** same test file — with the variable unset, exit 1 naming
it and no launch; with a dummy value and `DRY_RUN=1`, work.sh's report
and zero writes.

## T6 · `scripts/auth/mint_app_token.py` — the preflight — D4

Two flags on the script that already mints, not a new script.
`--require-repo` asserts, against a **paginated** `GET
/installation/repositories`, that `get_repo_info()`'s `<owner>/<repo>`
is in the installation's selection, exiting non-zero with
`daedalus: the evekhm-daedalus-app installation does not cover
evekhm/agentic-sdlc`. `--quiet` performs the check and prints nothing,
so an adapter preflights without a token ever reaching a shell variable.
Pagination is load-bearing: a truncated first page is exactly the misread
already on this thread (#25, correction comment 2026-09-02).

Building it into the minting path is the point of D4: the preflight is
every unattended run's first step, and a check that lives inside the
only credential path cannot be forgotten by an adapter. T4 and T5 call
`mint_app_token.py "$persona" --require-repo --quiet` before work.sh.

**Proves it (Acceptance 4):** T8, with a stubbed API returning a
selection that excludes this repository — exit non-zero, the named
error, empty stdout, no model call reached; and with a covering
selection — exit 0, empty stdout.

## T7 · `scripts/ops/post.sh` (NEW) + `scripts/ops/lib/github.sh` (NEW) — D5, D6, D13, D14

The one write path. `post.sh <number> --as <persona> --body-file <path>`:

- resolve the target as work.sh does, then build the hold set — the
  target, plus, for a pull request, every issue it closes (D14);
- re-read the labels of every member **immediately before the write**;
  any `hold` prints `held: #<n> carries hold; nothing posted`, writes
  nothing, and exits **0, green** (D5, D13);
- otherwise post the body from the FILE — never from an argument, never
  from a string a model composed into an API call (D6, trusted-posting
  rules 1–2). `GH_TOKEN` comes from the environment by name and is never
  printed.

So that D14's "the same way work.sh resolves it" is one implementation
and not two, move work.sh's PR→issue resolution (a69f7f5, 121–165) and
`has_label` (167–171) into `scripts/ops/lib/github.sh` and source it from
both. This is the ONLY edit this plan makes to work.sh; it does not
touch the launch table (357–390) or the report (392–431), which #43
owns. If #43 merges first, rebase and re-run both test files.

**Proves it (Acceptance 3, 10):** T8's `post_test.sh` — `hold` on the
pull request; `hold` on the closed issue only, the pull request
unlabelled, body `Closes #25` (D14's Observable verbatim); `hold` on
neither (one POST, exit 0); and `hold` appearing between dispatch and
write, the stub returning different labels on the second read (D13's
Observable). Each of the first, second and fourth asserts exit 0 and
zero POSTs. Plus `work_test.sh` unchanged and green — the extraction is
behaviour-preserving or it is wrong.

## T8 · tests and the fourth gate — D17, D18, and the Acceptance list

`scripts/ops/tests/execution_test.sh`, `placement_test.sh` and
`post_test.sh`, in the style of `scripts/ops/tests/work_test.sh` — a
stub `gh` first on `PATH`, `mktemp -d` fixtures, `set -euo pipefail`, a
banner per scenario naming the D-row it pins. Then a fourth job in
`.github/workflows/ci-gates.yml`, beside `drift`/`sanitize`/`spec-check`
(38–131), keeping `permissions: contents: read` (31–32) as the whole
grant — this gate reads files only:

```yaml
  execution:
    name: execution — every binding resolves to an adapter
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: '3.12' }
      - run: python3 -m pip install --disable-pip-version-check pyyaml
      - run: python3 scripts/ops/execution.py --check
      - run: bash scripts/ops/tests/execution_test.sh
```

**The two one-line moves (Acceptance 8) are performed once during
implementation and cited in the PR, not committed as tests:** flip
`argus`'s `placement` to `vm-local`, show `git diff --numstat` is
`1 1 config/execution.yaml` and nothing else, `--check` passes, and
`DRY_RUN=1` through the vm-local adapter still dispatches (D18); then
the same for `personas.atlas.harness` in `config/deployments.yaml`.
Capture both into `runs/<YYYY-MM-DD_HHMMSS>/` per AGENTS.md and cite the
folder in the PR body.

## T9 · `.github/workflows/unattended.yml` (NEW) — trigger only — D7, D11, D16

Event capture, not the runtime: it resolves subscribers and hands each
to its adapter, so moving a persona between placements changes this file
not at all (D18).

- `on: pull_request: [opened, synchronize, reopened]` — the union of the
  `events` in `config/execution.yaml`, which T2's `--check` holds to the
  config — plus `workflow_dispatch` (number, persona) for the smoke run.
  **Never `pull_request_target`** (D7), and the job exits early when
  `github.event.pull_request.head.repo.full_name != github.repository`:
  a fork pull request gets human review only.
- one job; `permissions: contents: read, pull-requests: read` — no write
  grant at all, because every write is a persona App's through T7.
- steps: `python3 scripts/ops/execution.py --subscribers pull_request`;
  for each subscriber whose placement is `gh-actions`, set the persona's
  key variable from `secrets[format('{0}_APP_PRIVATE_KEY', …)]` (by
  NAME, D3) and run `scripts/placement/gh-actions/run.sh "$n" --as
  "$persona"`; a subscriber whose placement this runner cannot host is
  one named skip line, never a silent drop.
- **exit 2 from an adapter is a refusal, not a failure** — recorded, job
  stays green (#36, D8). Exit 1 fails the job.
- no `model` variable, no tier literal, no cap literal appears in this
  file (D8, D15).

**Proves it (live):** a `workflow_dispatch` smoke run with `DRY_RUN=1`
on a scratch issue prints the resolved subscribers and each adapter's
dry-run report, writes nothing, and is green; `grep -rn
pull_request_target .github/workflows/` is empty (D7). D11's Observable
— two reviews on an attendee's pull request — is provable only once #8
and #9 wire the review duty and #7 loads `ARGUS_APP_PRIVATE_KEY` and
`ATLAS_APP_PRIVATE_KEY` as Actions secrets. This plan delivers the
substrate and names those as the two remaining preconditions.

## T10 · docs and the four contradictions — D15, spec §Contradictions

- **`docs/SPEC.md`** — one new entry, `execution.placement`, after
  `ops.dispatch` (277–321): the two axes, `config/execution.yaml`'s
  keys, the adapter registry and its reserved names, the preflight, the
  hold-before-every-write rule, and the one-line cost of a move. Three
  in-place amendments keeping their IDs: `identity.bots` (89–110) says
  WHICH private keys are Actions secrets — argus and atlas, no others,
  in v1 (D11, D12) — where it now offers both stores without choosing;
  `config.bindings` (111–122) gains `execution.yaml` as the fourth
  config file and the harness-vs-placement sentence; `ci.gates`
  (179–204) becomes four gates.
- **`config/model_tiers.yaml`** — delete lines 5–6, the sentence
  granting a workflow env-var pin precedence over the file (D15).
- **`INTENT.md`** — open question 3 (376–392) goes from PARTIALLY
  RESOLVED to RESOLVED for #8/#9/#10 citing D19, leaving #11's cadence
  open; the stakeholder line (324–325) says Actions workflows capture
  events rather than run the personas.
- **`docs/CONTEXT.md` §1** (11–15) — one clause recording that the
  predecessor's Atlas polling sidecar was retired in favour of a
  workflow (`docs/ATLAS_DEPLOYMENT_OPTIONS.md`), so it is not read as
  current.

**Proves it (Acceptance 6):** `spec_check.sh` — the diff touches
`docs/SPEC.md`, so the obligation is met by the entry and not by a
marker; `grep -n 'env var' config/model_tiers.yaml` empty; sanitize
green.

## Pull request

One PR, body carrying `Closes #25`, the plan sync, the two one-line-move
diffs from T8's run folder, and the T9 smoke-run URL. Gates: the four CI
gates; `bash -n` on every new script; `python3 -m py_compile` on the two
Python files; `work_test.sh`, `execution_test.sh`, `placement_test.sh`
and `post_test.sh` green. `personas/**` untouched, asserted by
`git diff --name-only origin/main...HEAD | grep '^personas/'` being
empty (D10, Acceptance 5).

## What this plan deliberately does not build

- work.sh's `antigravity` launch row, its token minting for the child,
  the `/work` skill, the AGENTS.md dispatch rule — **#43**, which T4
  builds on.
- the review duty and the `status:in-review` writer — **#8, #9**. The
  argus/atlas bindings in T1 are inert until then, which is what D19's
  staged rollout says.
- `personas/skills/trusted-posting.md` naming `scripts/ops/post.sh` as
  the posting script its rule 1 requires: D10 forbids this PR from
  touching `personas/**`, so it is a **named follow-up issue**, filed
  when this plan is dispatched.
- any adapter for the three reserved placements — T2's check makes a
  binding on one fail with a named error until its directory is merged
  (D17).

## Values the spec does not fix

Two, both flagged rather than decided, because a plan is not the place
to invent a commitment the Decisions table does not carry.

1. **`max_cost_usd` numbers.** D2 requires the key; no row fixes the
   figures. T1 proposes 2.00 for a review run, 5.00 for a design or
   planning run and 10.00 for an implementation run, read off the turn
   and time caps in `personas/*.yaml`. Each is a one-token edit; the
   product owner's number replaces it with no other change.
2. **The workflow's `on:` list repeats the `events` values.** D8's
   testable — no workflow literal duplicating a value already in
   `config/execution.yaml` — reads against it, and GitHub requires a
   static trigger list, so the duplication cannot be removed. T2's
   `--check` converts it from a second source of truth into a checked
   derivation: the gate fails if the workflow's `on:` omits an event any
   binding subscribes to. If the product owner reads D8 more strictly,
   the alternative is a single `repository_dispatch` type and an
   external forwarder, which trades the duplication for a component.
