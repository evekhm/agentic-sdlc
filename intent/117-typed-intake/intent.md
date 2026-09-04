# Intent: typed intake — issue forms, deterministic triage, a bug path

**Issue:** #117 · **Author:** athena (`evekhm-athena-app[bot]`) ·
**Status:** accepted on merge of this PR

## Problem

Every item enters the tracker the same way today: a human writes a
free-form issue and applies `intent:new` by hand. Three things are
missing at that door.

- **Nothing types the body.** The PLAN stage needs a problem, a
  proposed outcome, affected users and systems, constraints and open
  questions (AGENTS.md, "The work item"; INTENT.md's lifecycle). A
  bare title reaches Athena as easily as a complete brief, and the
  first persona run is spent asking what the second sentence should
  have said. #29 named this ("button broken") and proposed a validated
  intermediate representation; the presenter folded that into #10 as
  an open question. It is still open.
- **Nothing looks for prior art before tokens are spent.** AGENTS.md
  ("Before filing an issue") binds every persona to search the tracker
  first, but the search is a discipline, not a mechanism: the first
  automated step on a new issue is a model run, and a duplicate is
  discovered inside it, after the spend.
- **A bug has no door at all.** `bug` exists on this repository only
  as a GitHub default label; `scripts/setup/bootstrap_tracker.sh`
  provisions 14 labels and `bug` is not one of them, no rung of
  `personas/lifecycle.json` reads it, and no persona subscribes to
  it. A human who has seen the system misbehave has nowhere to say so
  that the automation can see.

Underneath all three: the automation is deaf to issues. The three
Actions workflows capture `pull_request` and `push`; no workflow
listens to `issues` events, so an opened issue is invisible until a
human types its number into `scripts/ops/work.sh`. #36's intent noted
that GitHub emits `issues: labeled` events "which is the repo-event
trigger shape #25 defines" — the shape exists, and nothing uses it.

## Proposed outcome

An issue filed by a human arrives **typed, searched and routed** with
no human action between the form and the first persona run.

1. **Two issue forms** under `.github/ISSUE_TEMPLATE/`, with blank
   issues disabled so every human-filed issue passes through one.
   - The **intent form** has exactly the five sections of the
     intent.md template and applies `intent:new`. The form *is* the
     validated intake representation #29 asked for: the fields are
     the schema, GitHub enforces "required", and Athena's intake PR
     (#10) becomes a near-mechanical transcription of the issue body
     into `intent/<n>-<slug>/intent.md`.
   - The **bug form** asks what happened, what was expected, the
     evidence (a run folder, a PR, a log excerpt), the persona or
     script involved, and the severity, and applies `bug`. `bug`
     joins the provisioned set in `bootstrap_tracker.sh` with a
     description the lifecycle owns.
   - A form applies one fixed label set, which is why there are two
     forms and not one form with a type dropdown. Issues filed by API
     (Cassandra's proposals, #11) bypass the forms and carry their own
     labels, as they do today.
2. **A deterministic triage step on issue open**, bash + `gh` + `jq`,
   no model call, in the failure-mode-first style of the CI scripts
   and runnable locally with `DRY_RUN=1` exactly like
   `scripts/ci/lifecycle_advance.sh`. It verifies the required
   sections are present and non-empty (if not: `blocked`, plus one
   comment naming the gap); searches open **and closed** issues and
   PRs on the title's terms; greps the `intent/*/` folders for a
   matching slug; and posts **one** comment listing the candidates
   with their state. A duplicate is closable by the human before any
   persona spends anything. This step is the mechanical half of
   AGENTS.md's "Before filing an issue", run by the machine at the
   moment it matters.
3. **Two persona subscriptions on the `issues` event**, declared in
   `config/execution.yaml` and captured by
   `.github/workflows/unattended.yml` through the same subscriber
   resolution Argus and Atlas use for `pull_request` today.
   - `intent:new` → **Athena**: this is #10 as written, with one
     addition — she reads the triage comment first and either
     brainstorms in the thread and opens the intent PR, or applies
     `duplicate`, closes with a pointer, and stops.
   - `bug` → **Cassandra**: a human bug report is an incident
     arriving from outside the control bands (#11). Her existing duty
     already fits — diagnose read-only, correlate with recent merges
     and run artifacts, and if the defect is real propose the fix as
     an `intent:new` issue — so no new duty and no seventh persona.
   - The binding *values* (trigger, placement, budget) are the
     human's to set in config; this intent names the subscription,
     not the pin (AGENTS.md, "Specs never hardcode pins").

**Done when:** filing either form produces a labeled issue with one
triage comment and no human action in between; an intent filed
through the form reaches Athena and a bug filed through the form
reaches Cassandra through `execution.py --subscribers issues`; a
missing required section yields `blocked` and a comment, not a
persona run; and `execution.py --check` passes with `issues` present
in both the workflow's `on:` block and the bindings file.

## Affected users and systems

- **Presenter and anyone filing an issue** — the forms replace the
  blank editor; the triage comment is the first thing they see.
- **Athena** (#10 depends on this): intake starts from a typed body
  and a prior-art list. **Cassandra** (#11): gains `bug` as a second
  input alongside her watchers.
- `.github/ISSUE_TEMPLATE/` (new: two forms and `config.yml`),
  `.github/workflows/unattended.yml` (adds the `issues` trigger and
  its own same-repo guard), `config/execution.yaml` (two
  subscriptions), `scripts/ops/execution.py` (`--check` already
  cross-checks the two files; nothing new to teach it),
  `scripts/setup/bootstrap_tracker.sh` (provisions `bug`), one new
  triage script beside `lifecycle_advance.sh`, `docs/SPEC.md`
  (`lifecycle.labels`, `intake.automation`, a new triage entry).
- `personas/lifecycle.json` **only if** the spec decides a bug enters
  the ladder at a different rung than an intent (open question 1).

## Constraints

- **Deterministic before model.** The triage step makes no model
  call. Semantic judgment (is #117 really #29?) belongs to the persona
  that reads the comment, not to the script that writes it.
- **No write grant on the workflow.** `unattended.yml` keeps
  `contents: read`; the triage comment and any label it applies go
  through `scripts/ops/post.sh` under a persona App's token (#25 D5,
  D6, D13, D14), so `hold` is honored at the moment of the write.
- **No trigger loops.** Issues authored by a persona App do not
  re-trigger triage; Cassandra's `intent:new` proposals enter the
  ladder as they do today. `hold` stops everything, as everywhere.
- **Two files, one PR.** `execution.py --check` fails when the
  bindings name an event the workflow does not capture, so the
  `issues` trigger and the two subscriptions land together.
- **One label set per form.** No dropdown that pretends to route; the
  form's fixed labels are the route.
- **No new documents** beyond the two forms, the triage script and the
  SPEC entries (AGENTS.md, "No document sprawl"). No vendor or model
  names in persona sources (#1 D3).
- **Refines** #4 (labels), #25 (execution model) and #10 (which now
  depends on this). **Absorbs** the #29 question carried on #10: the
  representation is the form, not a JSON schema.

## Open questions

1. **Where a confirmed bug enters the ladder.** Proposed default: a
   bug Cassandra confirms skips PLAN and enters at `status:spec` with
   the reproduction as its contract test, i.e. the failing test is
   the spec. The alternative is that her `intent:new` proposal simply
   restarts the five-rung flow. The first is faster and needs a
   `lifecycle.json` row; the second needs nothing. Decide in spec.md.
2. **Which persona authors the triage comment.** The script has no
   identity of its own; `post.sh` needs an `--as`. Candidates: the
   persona that will next own the issue (Athena for `intent:new`,
   Cassandra for `bug`), or a single tracker identity. The first keeps
   the thread's author trail honest; the second is one token to mint.
   Decide in spec.md.
3. **Whether the triage step edits the body.** GitHub renders form
   fields as `### Heading` blocks. If Athena's transcription is to be
   mechanical, the heading names must match the intent.md template
   exactly; the form owns that, and the spec states the mapping.
