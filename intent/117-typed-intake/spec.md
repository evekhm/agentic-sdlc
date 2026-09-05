# Spec: typed intake — two forms, one deterministic triage, a bug door

**Issue:** #117 · **Status:** Approved (approval = merge of this PR) ·
**Author:** athena (`evekhm-athena-app[bot]`) ·
**Open questions:** none

The accepted intent (`intent.md`, merged in b2e3369) carried three Open
questions. No human was live in the design session, so each is decided
below with its rationale grounded in the record rather than posed back,
together with the decisions the record showed the build needs and the
intent did not ask for. **Any row in this table can be overruled by
editing this file at the merge gate** — the merge is the acceptance, so
an edited row is the decision, not a comment asking for one.

Three rows refine the accepted intent rather than implement it as
written, and say so in place: D1 (where a confirmed bug enters), D15
(who writes the triage comment) and D7 (what the `issues` capture
deliberately does not subscribe to).

Two rows overrule a prior Approved spec in a named place and say so in
the row: D2 (#36 D2's "absent by construction" and its five-row
acceptance) and D14 (#25 D6's posting-script sentence, for the one job
that makes no model call).

## What is being built

```text
.github/ISSUE_TEMPLATE/intent.yml      NEW: the intent form (labels: intent:new)
.github/ISSUE_TEMPLATE/bug.yml         NEW: the bug form (labels: bug)
.github/ISSUE_TEMPLATE/config.yml      NEW: blank issues disabled, no contact links
.github/workflows/unattended.yml       the issues trigger, the triage job, the guards
.github/workflows/ci-gates.yml         the new suite joins the execution gate
config/execution.yaml                  athena + cassandra subscribe to `issues`
personas/lifecycle.json                NEW ROW: the off-ladder `maintain` rung
personas/skills/resume-protocol.md     one sentence: deriving an off-ladder stage
scripts/ci/intake_triage.sh            NEW: the deterministic triage
scripts/ci/tests/intake_triage_test.sh NEW: hermetic tests, stub gh, no network
scripts/ci/tests/lifecycle_advance_test.sh  one assertion + three prose lines: five rungs -> six
scripts/ops/smoke_launch.sh            two lifecycle-label joins filter to ladder rows (D28)
scripts/ops/tests/execution_test.sh    five lines in four scenarios follow the new bindings
scripts/ops/tests/work_test.sh         three #129 strings follow the third arm; D4 scenarios join
scripts/ops/work.sh                    a third arm in the stage derivation
scripts/setup/bootstrap_tracker.sh     provisions `bug` (14 labels -> 15)
.claude/agents/  .agents/agents/       REBUILT (drift gate)
docs/SPEC.md                           intake.triage + five amendments
```

`personas/*.yaml` are deliberately absent: stage ownership is derived
from each source's existing `stage` list (#36, D2), and
`personas/cassandra.yaml` already declares `maintain`.

## The triage comment, verbatim

One comment, whether or not there is a gap. Both halves always appear,
in this order, and the marker is always the last line.

```text
_Posted by `.github/workflows/unattended.yml` (#117) — deterministic, no
model call. Triage does not judge: it checks the form's required sections
and lists what the tracker already has. The persona that picks this issue
up decides._

**Required sections:** all present.

**Prior art** (searched `typed OR intake OR issue OR forms OR intent OR deterministic`; open and closed
issues, pull requests, and `intent/*/` folders):

- #29 (closed) — Validated intake representation
- #10 (open) — Headless Athena on intent:new
- `intent/10-headless-athena/`

<!-- intake-triage:117 -->
```

The query shown is D20's derivation of this issue's own title (`Typed
intake: issue forms for intent and bug, deterministic triage on issue
open`) with no stopword removed: `for`, `and`, `bug` and `on` fall to the
4-character rule, the second `issue` to de-duplication, and `triage` and
`open` to the cap of six. The script's stopword list may shorten it
further; D17 pins none of the terms, only the fixed strings around them.

The variable lines, in their other forms. Required sections, when a
required block is missing or empty:

```text
**Required sections: incomplete.** `blocked` applied. Missing or empty:
`Problem`, `Proposed outcome`. Fill them in and remove `blocked`.
```

Prior art, when the search ran and matched nothing:

```text
**Prior art:** nothing matched `typed OR intake OR issue OR forms OR intent OR deterministic`.
```

Prior art, when the title yielded no searchable term at all (title
`Fix the bug`: every word is shorter than 4 characters or a stopword) —
no search is issued:

```text
**Prior art:** not searched — the title yielded no term of 4 characters
or more.
```

## Decisions

### The bug path and the ladder

| ID | Decision |
|----|----------|
| D1 | **A confirmed bug takes the ratified defect-repair path; neither branch of the intent's open question is adopted.** INTENT.md ("Defect repair", ratified on #32) already answers this, and its answer is neither of the two the intent offered: a bug in merged work whose `docs/SPEC.md` entry is unchanged does not owe the intent/spec/plan triple — it goes issue, then fix PR with a regression check, then REVIEW, then human merge, with the issue citing the capability it repairs; a repair that would change a spec entry is a change and re-enters at PLAN. This spec does not amend that, and a feature spec that quietly reversed a system-level intent would be the worse defect. Cassandra's output is therefore unchanged and stays read-only: she diagnoses, and when the defect would change a spec entry she files the one `intent:new` proposal her persona already describes (re-enters at PLAN), and when it would not she says so in the thread and the bug issue itself is the defect-repair issue whose fix PR is the final stage. She never writes the fix. Nothing seeds `status:spec`, nothing is added to the five rungs, and the intent's proposed default is rejected because it would give a maintainer's confirmation the force of the product owner's acceptance for exactly the class INTENT.md says re-enters at PLAN. |
| D2 | **The bug REPORT gets a stage so the diagnosis can be dispatched: `bug` names `maintain`.** `personas/lifecycle.json` gains a sixth row, appended after `review`: `stage` `maintain`, `label` `bug`, and `artifact`, `advances_on`, `advances_to`, `advance_message` all `null`, with a `dispatch_brief` of one line — diagnose the reported defect read-only, reproduce from the evidence, correlate with recent merges and run artifacts, and then either file the one `intent:new` proposal or report in the thread that no spec entry changes (D1) or that it does not reproduce. The row is required, not optional: `scripts/ops/work.sh` today refuses a `bug`-labelled issue with "cannot derive a stage" — the comment there names `bug` explicitly (#129) — so without it nothing can dispatch Cassandra and outcome 3 of the intent cannot be built. `personas/lifecycle.json` is the ONLY place the label-to-stage relation may be written (#36, D2), so the alternative, a `bug` case inside `work.sh`, is forbidden. What #129 protected is preserved: a fix pull request must not put a red check on the repository, and it still cannot, because a reviewer dispatched against an issue at stage `maintain` refuses on "not this actor's stage" (#36, D5(f), exit 2, green) instead of on "no rung at all" — the message changes, the colour does not. An issue carrying no label at all still refuses exactly as it does today. The row is inert to the advancer: `bug` is no row's `advances_to`, its `artifact` is `null` so no merged file matches it, and appending it places its entry in the `[.stages[].label]` rank list after `status:in-review`, where no `status:*` comparison reaches it. **This OVERRULES #36 D2 and its surrounding text in two named places, and keeps the rest.** Kept and relied on: the file is the only place the label-to-stage relation is written, and ownership stays derived. Reversed, for `maintain` alone: #36's statement that `intake`, `deploy` and `maintain` "are stage-enum values with no rung and are absent by construction" (intent/36-dispatch/spec.md:45, repeated in the file's `_comment`) — D3 rewrites that sentence. Broken, knowingly: #36's acceptance row "`jq -e '.stages | length == 5' personas/lifecycle.json` passes" (intent/36-dispatch/spec.md:68) fails once the row exists and is superseded by the `== 6` row in Acceptance below, together with the four lines in `scripts/ci/tests/lifecycle_advance_test.sh` that encode it (the banner at :402, the assertion at :403, the `fail` message at :404 and the `pass` line at :405). What that row protected — the ladder the advancer walks is exactly five rungs — is preserved by D3's definition: the sixth row is not a rung of the ladder, and the rank list the advancer compares is unchanged. |
| D3 | **A row is off-ladder exactly when its `label` is not a `status:*` label, and the file says so.** The `_comment` in `personas/lifecycle.json` gains: rows whose `label` is a `status:*` label are the ladder, in ladder order; a row whose label is not `status:*` is an off-ladder rung — a dispatcher may derive its stage from that label, the advancer never writes it, and it is appended after the ladder so the rank list is unchanged. The existing sentence "intake, deploy and maintain are stage-enum values with no rung and are absent by construction" becomes the same sentence about `intake` and `deploy`. `maintain` is already in `schema.json`'s stage enum and already declared by `personas/cassandra.yaml`. Accepted cosmetic consequence, stated so nobody edits the renderer to chase it: `scripts/sync_agents.py` is NOT changed, so the generated block renders both `review` and `maintain` with "Last rung: nothing advances past it automatically" — each row's own bullets (its label, its artifact, its owner) already say which is which. |
| D4 | **`work.sh` derives a stage from one off-ladder label, in a third arm.** Order, unchanged at the top: a single `status:*` label wins, so a bug a human promoted onto the ladder is on the ladder; else `intent:new` is the first rung; else — NEW — exactly one of the issue's labels equals the `label` of a lifecycle row whose label is not `status:*`, and that row's stage is the stage; else the existing refusal, whose message gains "and no label naming an off-ladder rung". Two or more off-ladder labels on one issue is corrupted state: refuse and name them, never guess (the rule of #36, D5(d)). Every outcome here keeps exit 2 — a refusal, not an error. |
| D5 | **`resume-protocol.md` gains one sentence and the six personas are rebuilt.** Step 3 today reads "An issue carrying `intent:new` and no `status:*` label is at the first rung of the ladder"; it gains "An issue carrying no `status:*` label and exactly one label that a lifecycle row names off the ladder is at that row's stage." The skill is inlined verbatim into every persona (#5, D5), so all six compiled targets under `.claude/agents/` and `.agents/agents/` change and the implementing PR carries the rebuild; `python3 scripts/sync_agents.py --check` exiting 0 is the gate. |

### Capturing the event

| ID | Decision |
|----|----------|
| D6 | **`unattended.yml` captures `issues` with `types: [opened]` and nothing else.** Not `edited` — every body edit would re-dispatch work already done. Not `reopened` — the thread already carries its triage and its handoffs. Not `assigned`/`unassigned` — not lifecycle facts. Not `labeled` — see D7. |
| D7 | **`issues: labeled` for `status:*` is OUT of scope, and the reason is mechanical rather than editorial.** The product owner asked how the next rung could be dispatched automatically when a merge advances the label. This subscription cannot do it: the advance is written by `.github/workflows/lifecycle.yml` using the Actions `GITHUB_TOKEN` (`permissions: issues: write`, `GH_TOKEN: ${{ github.token }}`), and GitHub does not start a workflow run from an event that a `GITHUB_TOKEN` write produced. A `labeled` subscription would therefore capture a human hand-labelling an issue and never a lifecycle advance — precisely the case being asked for. Making it work needs either a second credential on the label write or a `workflow_run` chain off `lifecycle.yml`: new machinery and a second dispatch path. It belongs to #64 (the loop merges itself) and is named there, not built here. |
| D8 | **The fork guard admits the event by name, because an issue has no fork — on `resolve` only.** The `resolve` job's `if:` gains an `issues` arm alongside the existing `workflow_dispatch` and same-repo head alternatives (the exact expression is in D14). `github.event.issue` carries no head repository, so the fork-secrets exposure #25 D7 closes does not exist on this event and the pull-request test would evaluate false forever. The three-way alternative belongs to `resolve` and to no other job: it is a DISJUNCTION, true on every same-repo pull request, and a job that must run only on `issues` (the `triage` job, D14) cannot borrow it — its guard is a conjunction on the event name. |
| D9 | **An issue authored by a bot is neither triaged nor dispatched.** One condition, `github.event.issue.user.type != 'Bot'`, on both guards — the whole of `triage`'s second conjunct, and inside `resolve`'s `issues` arm (D14); on a `pull_request` or `workflow_dispatch` payload `github.event.issue` is null and neither guard consults it. It covers every persona App and the Actions bot with a fact carried in the payload, which a workflow that cannot read `personas/*.yaml` could not otherwise establish. Accepted and stated consequence: Cassandra's `intent:new` proposals do not auto-dispatch Athena — they enter the ladder by hand, "as they do today" (intent, Constraints). Reversing that is a loop question and belongs with #64. |
| D10 | **The number and the concurrency group learn about issues.** `NUMBER` becomes the three-term expression `github.event.pull_request.number` then `github.event.issue.number` then `inputs.number`, and `concurrency.group` takes the same three terms. Without the middle term an `issues` run groups under the bare string `unattended-`, shared with every other issue in the repository, and dispatches with an empty number. |
| D11 | **The two subscriptions are a SHAPE; the values stay the human's.** `athena` and `cassandra` each carry `trigger: repo-event` and `events: [issues]` in `config/execution.yaml`. This spec names no `placement` and no `max_cost_usd` for either, and naming one later is not a spec edit: those values, and every change of them, are the human's at the merge gate (AGENTS.md, "Specs never hardcode pins"). Two constraints bind whatever is chosen: `execution.py --check` requires `max_cost_usd` to be a positive number and `placement` to resolve to an adapter directory, and a placement no GitHub-hosted runner can host yields the named skip line `unattended.yml` already prints instead of a run. `athena`'s existing binding changes its trigger only; `cassandra` has no binding today and gains one. Five lines across four scenarios in `scripts/ops/tests/execution_test.sh` encode today's absence and move with this change, and no others: the summary count `has "5 binding(s)"` at :69, which reads the `--check` pass line and becomes `6 binding(s)`; the bindings string at :76; the empty `--subscribers issues` output at :91-93; and the `run`/`has` pair at :98-99 — `--binding cassandra` exiting 1 at :98 because "#11 owns cassandra's cadence", and its partner `has "has no execution binding"` at :99, which fails the moment :98 flips because cassandra then has a binding and that string is never printed, so it becomes an assertion on the printed binding (`has "repo-event"`, the one value of that line this spec fixes). Nothing else in the suite reads the committed config: `--subscribers pull_request` at :87-90 is untouched because athena's events are `issues`, and every scenario from :101 on runs against a fixture tree. |
| D12 | **Routing is by refusal, not by a filter in the bindings.** Every captured `issues` event resolves to BOTH subscribers, and the one that does not own the derived stage refuses inside `work.sh` before any model is launched (#36, D5(f): exit 2, green, one named line). No `labels:` key is added to a binding and `execution.py`'s `BINDING_KEYS` set is unchanged — a per-label subscription would be a second copy of the label-to-stage relation #36 D2 exists to prevent, living in the file furthest from `personas/lifecycle.json`. The price is one hosted-runner job per issue that ends in a refusal, with no model tokens spent. |

### The triage step

| ID | Decision |
|----|----------|
| D13 | **`scripts/ci/intake_triage.sh <issue-number>`, beside the advancer.** Deterministic bash plus `gh` and `jq`, no model call, failure-mode first, one number as its whole input and no other argument. `DRY_RUN=1` prints every write instead of performing it and changes nothing about any read, so the live guards are exercised exactly as they would be for real (#57, D21). Exit codes: `0` = triaged, or deliberately did nothing (`hold`, closed, already triaged, no triage-able label); `1` = unusable input, a failed read, or a failed write. Its tests are `scripts/ci/tests/intake_triage_test.sh` in the style of `scripts/ci/tests/lifecycle_advance_test.sh` — hermetic, a stub `gh` first on `PATH` answering from fixtures, a write log and an invocation log, `DRY_RUN=1`, no network and no token — and they are wired into the `execution` gate job of `.github/workflows/ci-gates.yml` beside the three suites it already runs, because the triage script is the other half of the `issues` capture that gate checks. The read order is part of the contract and is pinned by the invocation log: ONE labels-and-state read first, which serves the routing check (D19) and the `hold`/closed short-circuit together, so a held or unlabelled issue costs zero searches; then the thread read for the marker (D16); then the three prior-art sources (D20); then a SECOND labels read immediately before the first write (D15). |
| D14 | **Triage is a job inside `unattended.yml`, ordered BEFORE the dispatch, and it is the only job in that file with a GitHub write grant** (the `dispatch` job's `id-token: write` is an OIDC token for cloud federation, not a GitHub write). A new first job `triage` carries `permissions:` of `contents: read` plus `issues: write`, and its `if:` is exactly the conjunction `github.event_name == 'issues' && github.event.issue.user.type != 'Bot'` — never the three-way alternative of D8, which is a disjunction and is true on every same-repo pull request. On a `pull_request` or `workflow_dispatch` payload `triage` is therefore SKIPPED, not run-and-failed. `resolve` gains `needs: triage`, and its `if:` becomes `!cancelled() && ( (github.event_name == 'issues' && github.event.issue.user.type != 'Bot' && needs.triage.result == 'success') || (github.event_name != 'issues' && (github.event_name == 'workflow_dispatch' || github.event.pull_request.head.repo.full_name == github.repository)) )`. The two arms are deliberately asymmetric. The `issues` arm demands a triage that RAN AND PASSED: a failed triage (the required-section check did not run) and a skipped one (a bot author) both dispatch nobody — fail-closed. The non-`issues` arm does not mention `needs.triage.result` at all, so no outcome of triage — failure, skip, or a future defect in it — can suppress the reviewers on a pull request; `!cancelled()` is what keeps a skipped need from skipping `resolve` by default. The issue number reaches the triage step the way every event field reaches every other step in this file and in `lifecycle.yml` (#6, D10): as an `env:` entry `NUMBER` bound to D10's expression and passed to the script as `"$NUMBER"` — the step's `run:` body contains no `${{` at all. A separate workflow on the same event was the alternative and is rejected: it would race the dispatch, and the whole value of the `blocked` path is that it lands before a persona spends. The invariant the file's header states is preserved in the form that carries the security, and is restated there — **the job that launches a model has no GitHub write grant, and the job that writes makes no model call.** **This OVERRULES #25 D6's sentence "the GitHub write goes through a repository posting script, never an API call composed inline"** for this one job, and says why: #25 D6's subject is a model-bearing run ("No model-bearing unattended run receives …"), and the sentence exists so that a model never composes a GitHub write; `triage` makes no model call, and its two writes are composed by a committed script whose exact output the tests pin (D17). No acceptance row of #25 breaks: `hold` at the moment of the write (#25 D5, D13) is carried by D13 and D15 here, and the model-launching job's grants are unchanged. |
| D15 | **The triage comment and the `blocked` label are written by the workflow's own `GITHUB_TOKEN`, as `github-actions[bot]` — not by a persona through `post.sh`.** This overrules the intent's constraint, for three reasons. (1) Triage must add a LABEL, and `post.sh` posts one comment and does nothing else; routing a label write through it means adding a capability to the one write path whose narrowness is its entire value. (2) `.github/workflows/lifecycle.yml` is the standing precedent for a deterministic tracker write, and its comment opens by naming the workflow that wrote it — a truer attribution than a persona's name over a comment no persona composed, at a step whose defining property is that no model ran. (3) A `GITHUB_TOKEN` write starts no further workflow run, so the `blocked` label cannot re-trigger anything; under a persona App's token it would fire `issues: labeled` and the loop guard would become one more thing to get right. The property the intent was protecting — `hold` honoured at the moment of the write and not merely at dispatch (#25, D13) — is kept by the script itself: the target's labels are re-read immediately before each write, and a `hold` found there means nothing is written and the exit is 0. |
| D16 | **One comment, one marker, one triage per issue.** The comment's last line is the HTML comment `intake-triage:<issue-number>`, in the style of the advancer's `lifecycle:` marker. Before writing anything the script reads the thread with `--paginate` and, if any comment body contains that marker, writes nothing and exits 0. Re-running is a no-op; the comment is never edited and never re-posted, including after the body is edited. `blocked`, once applied, is removed by a human or by the persona that resolves the gap — triage never removes a label. |
| D17 | **The comment's shape is the block under "The triage comment, verbatim" above, and nothing else.** Both halves always appear, in that order; only the two variable lines change, each to one of the alternative forms shown there — two required-sections forms (all present, incomplete) and three prior-art forms (matches, searched and nothing matched, no terms to search). The disclaimer's prose, the two heading labels and the marker are fixed strings the test pins. |
| D18 | **Which sections are required, and what "empty" means.** For `intent:new`: `Problem` and `Proposed outcome` are required; `Affected users and systems`, `Constraints` and `Open questions` are optional. For `bug`: `What happened`, `What you expected` and `Severity` are required; `Evidence` and `Persona or script involved` are optional. A section is PRESENT when a line matching `^### <label>$` exists in the body, and EMPTY when the text between that line and the next `^### ` (or the end of the body) is blank after trimming whitespace, or is exactly `_No response_` — what GitHub renders for a skipped optional field. Only two of the five intent sections are required because the filer is not the author of the intent, Athena is: demanding five prose sections at the door produces filler in three of them, while the form's own `required: true` already makes a gap unreachable for anyone filing through the form. The gap path exists for issues filed by API and for bodies edited after filing, and those are what its test fixtures are. |
| D19 | **An issue carrying neither `intent:new` nor `bug` is not triaged.** Exit 0, one named line, no comment and no label. Which sections are required is chosen by the label; with no label there is no schema to check, and a prior-art list on an issue nobody typed is noise. A bot-authored issue never reaches the script at all (D9). |
| D20 | **The search: the terms come from the title, they are joined by `OR`, and all three sources run every time.** Terms are derived deterministically from the issue TITLE only: lowercase it; replace every character outside `[a-z0-9]` with a space; drop words shorter than 4 characters; drop a fixed stopword list that lives on one line in the script and is pinned by the test; drop duplicates keeping the first occurrence; take the first 6 that remain. The query is those terms joined by ` OR ` — space-joining them would AND the terms and return almost nothing, which is the failure mode of a prior-art list nobody can tell from an empty one. Zero terms is not an error: no source runs at all, the comment carries the "nothing matched" line naming the empty term list, and the exit is 0. The three sources are `gh search issues --repo <repo> "<query>" --limit 10`, `gh search prs --repo <repo> "<query>" --limit 10`, and the `intent/*/` directories of the checkout, where a directory matches when its slug shares at least one hyphen-separated component with a term. Neither search passes `--state`: `gh search` accepts only `open` or `closed` there, and omitting the flag is the only way to get both, which is what the intent asks for. The triaged issue itself is excluded from the list. Any one of the three failing is exit 1 with a named error and NO comment: a prior-art list that quietly lost a source is worse than none (#57, D21, "no read fails open"). |
| D21 | **Triage never judges and never closes.** It applies exactly one label, `blocked`, and only for a missing or empty required section. It removes no label, closes nothing, applies no `duplicate`, opens nothing and never edits the issue body. Whether a listed candidate IS the same work is a reading, and readings belong to the persona (intent, "Deterministic before model"): `duplicate`, the close and the pointer are Athena's, posted from her own identity after she has read the thread. |

### The forms

| ID | Decision |
|----|----------|
| D22 | **Two forms, each with one fixed label set.** `.github/ISSUE_TEMPLATE/intent.yml` (`labels: [intent:new]`) has, in order: a `markdown` intro that renders nothing into the body; `textarea` **Problem** (required); `textarea` **Proposed outcome** (required); `textarea` **Affected users and systems**; `textarea` **Constraints**; `textarea` **Open questions**. `.github/ISSUE_TEMPLATE/bug.yml` (`labels: [bug]`) has: a `markdown` intro; `textarea` **What happened** (required); `textarea` **What you expected** (required); `textarea` **Evidence**, whose description names a run folder under `runs/`, an issue or PR number or a log excerpt, and repeats AGENTS.md's sanitize rules (no tokens, no absolute home paths); `input` **Persona or script involved**; `dropdown` **Severity** (required) with exactly three options — `blocks the loop`, `degrades a rung`, `cosmetic`. Neither form sets a `title:` prefix, so the title stays the filer's own sentence and the slug derivation (#36, D6) reads it unchanged. No dropdown routes anything: the form's fixed labels are the route. Field `id`s are the label lowercased with each run of non-alphanumeric characters replaced by `-`. |
| D23 | **The transcription mapping is the identity map.** Every field `label` above is byte-for-byte the heading GitHub renders (`### <label>`), the string `scripts/ci/intake_triage.sh` matches on, and the section name in `intent.md`. Athena's PLAN transcription is therefore: the `## <label>` section of `intent.md` takes the text of the `### <label>` block, verbatim, in the order the form declares; a block that is empty or exactly `_No response_` is dropped and she writes that section herself. There is no translation table anywhere, because a table would be a third place the five names have to agree. The bug form's headings map to no `intent.md` section at all — a bug report is not an intent (D1) — and Cassandra reads them as evidence. |
| D24 | **`config.yml`: `blank_issues_enabled: false`, and no contact links.** A contact link is a third door, and a door the automation cannot see is exactly the gap this issue closes. The two forms are the whole human intake surface; an API filing (Cassandra's proposals, #11) is deliberately not a door a human walks through. |
| D25 | **No "I searched the tracker" checkbox on either form.** The triage step IS that search, mechanised (AGENTS.md, "Before filing an issue"). A checkbox asking a human to promise what the machine now does is the discipline this change set out to replace, and a promise nobody can check is worse than no field. |

### Provisioning and the record

| ID | Decision |
|----|----------|
| D26 | **`bug` is provisioned, in the human-facing block, and the count becomes 15.** `scripts/setup/bootstrap_tracker.sh` gains `ensure_label "bug" "d73a4a" "A reported defect in this system: routed to the maintainer; not a ladder rung"` alongside `bootstrap`, `intent:new`, `in-progress`, `hold` and `blocked`. `d73a4a` is GitHub's own default colour for `bug`, which already exists on this repository, so the first run reports "exists — kept" and the line is the taxonomy declaring what it owns rather than a create. The description states both facts a reader needs: who it routes to, and that it is not a `status:*`. |
| D27 | **The living-spec upsert is exactly one new entry and five amendments.** New: `intake.triage` — the two forms and their fixed labels, the identity mapping, the triage script's arguments, exit codes, `DRY_RUN`, failure modes, the one-comment marker and the three search sources, and its test file. Amended: `lifecycle.labels` (15 labels; `bug` human-facing and explicitly off the ladder); `tracker.provisioning` where it counts labels; `ops.dispatch`, whose count "Seven refusals" becomes eight (D4's two-off-ladder-labels refusal) and whose refusal list today reads "a number on no rung at all — no `status:*` and no `intent:new`, which is every defect-repair issue" and must now say that a `bug`-labelled issue derives stage `maintain` while an unlabelled one still refuses, plus the third derivation arm; `personas.resume` (the added sentence, and its opening "five rungs — plan, design, build, implement, review", which becomes five ladder rungs plus one off-ladder row, `maintain`/`bug`, that the advancer never writes); and `execution.placement` (docs/SPEC.md:694 — the entry that lists captured events and whose sentence at :715 says cassandra carries no binding: `issues` joins `pull_request`, with the two subscriptions and the triage job's job-scoped write grant). `intake.automation` STAYS under "Agreed, not yet built": that entry is #10, headless Athena, and this change does not build it — it supplies the typed body and the prior-art comment #10 will read. INTENT.md is NOT amended: D1 implements its ratified defect-repair paragraph rather than changing it. The implementing PR touches `.github/`, `scripts/`, `personas/` and `config/`, so it carries a `Spec-impact:` marker. |
| D28 | **`smoke_launch.sh` joins persona stages against LADDER rows only, so the sixth row creates no smoke arm.** `scripts/ops/smoke_launch.sh` reads lifecycle labels in two places — `relabel_of` (:257-272), which turns a persona's `stage` list into the label to put on the scratch issue, and `relabel` (:691-700), which strips every other lifecycle label first — and both today read every row. With D2's row, `relabel_of cassandra` would return `bug`, and cassandra would become an arm whose relabel puts a non-`status:*` label on the scratch issue, against the function's own comment. Both jq reads gain `select(.label | startswith("status:"))`, the filter D3 defines as the ladder; `relabel_of cassandra` stays empty and the five ladder personas' results are unchanged. The comment above `relabel_of` at :258-260 is rewritten with the reads: it justifies the empty result with "the stage-enum values lifecycle.json records as 'absent by construction'", the sentence D3 retires, and after this change `relabel_of cassandra` is empty for a different reason — every stage cassandra declares is an off-ladder row the filter excludes — so the comment says that instead. The proof of the row is `scripts/ops/tests/smoke_launch_test.sh`, which copies the real `personas/lifecycle.json` (:137) and whose R1-2 regression fixture puts athena at stage `maintain` (:303-308): with D2's sixth row and without this filter, that fixture's athena relabel resolves to `bug` and the assertion at :310 goes red; with the filter, the suite passes with no edit and a PASS set byte-identical to the one before the row. That suite is absent from the file list on purpose. Cassandra as a smoke arm is rejected rather than accepted because the smoke's subject is the ladder: a `maintain` dispatch is proved by `work_test.sh` (D4) and by the live `issues` capture, not by relabelling a scratch issue. |

## Acceptance

Every assertion cites the Decision it derives from; an assertion a
contract-writer cannot derive from a Decision is a missed ambiguity and
comes back here rather than being guessed at.

- `jq -e '.stages | length == 6' personas/lifecycle.json` passes; the
  sixth row is `stage` `maintain` and `label` `bug`, with `artifact`,
  `advances_on`, `advances_to` and `advance_message` all `null`; it is
  the LAST element; and `maintain` is a value in `schema.json`'s stage
  enum (D2, D3).
- `scripts/ci/tests/lifecycle_advance_test.sh` passes with the sixth
  row present after exactly one assertion change — `.stages | length ==
  5` becomes `== 6` at :403 — and three prose lines in the same block:
  the banner at :402, the `fail` message at :404 ("does not carry
  exactly five rungs") and the `pass` line at :405; no other line of
  the suite changes. Its label-to-`ensure_label` loop and its stage-to-enum loop
  pass unmodified, because D26 provisions `bug` and `maintain` is
  already in `personas/schema.json`'s stage enum. `DRY_RUN=1
  scripts/ci/lifecycle_advance.sh <before> <after>` over that suite's
  synthetic ranges produces byte-identical output before and after the
  row is added (D2, D26).
- `DRY_RUN=1 scripts/ops/work.sh <n>` on an open issue labelled `bug`
  and nothing else prints stage `maintain`, owner `cassandra` and that
  row's `dispatch_brief`, and exits 0 having written nothing; the same
  issue additionally labelled `status:spec` prints stage `design` and
  owner `athena` (D4).
- `DRY_RUN=1 scripts/ops/work.sh <n>` on an issue carrying two
  off-ladder labels (against a fixture copy of the ladder carrying a
  second off-ladder row — the committed file has one) exits 2 naming
  both; on an issue carrying no
  `status:*`, no `intent:new` and no off-ladder label it exits 2 with a
  message naming the absence of all three (D4).
- `DRY_RUN=1 scripts/ops/work.sh <pr> --as argus`, where the pull
  request resolves to an issue labelled `bug` and nothing else, exits 2
  green with a message naming `cassandra` as the owner of stage
  `maintain` — not a red check, and not the "no rung at all" message it
  prints today (D1, D2).
- No literal `bug`-to-stage mapping exists in `scripts/`: the third arm
  resolves through `personas/lifecycle.json` and nowhere else, provable
  by editing that row's `label` in a fixture copy of the JSON and
  watching the derivation follow it (D2, D4).
- `bash scripts/ops/tests/work_test.sh` passes and is the suite that
  carries the five `work.sh` rows above. Its #129 block (:563-574)
  keeps `issue 140 open "bug"`, both `run 2` exit codes and the
  empty-writes check unmodified, and exactly three `has` strings
  change: :568 and :574 from `refused: cannot derive a stage for #140`
  to the D5(f) refusal (`argus does not own stage maintain` and `atlas
  does not own stage maintain`), and :569 from `no status:* label and
  no intent:new` to the owner clause `owners: cassandra`. The suite
  gains the D4 scenarios: `bug` alone derives `maintain`; `bug` plus
  `status:spec` derives `design`; two off-ladder labels refuse naming
  both; no label at all refuses naming all three absences (D2, D4).
- `python3 scripts/sync_agents.py --check` exits 0 only after the
  rebuild; all six persona targets differ from their pre-change form,
  the generated ladder block gains a `maintain` section naming `bug`
  with cassandra as owner, and no sub-agent target differs (D3, D5).
- Two consecutive builds are byte-identical, and `sync_agents.py` is
  itself unmodified by this change (D3).
- `python3 scripts/ops/execution.py --check` exits 0, and
  `--subscribers issues` prints exactly `athena` and `cassandra`, one
  per line, sorted, each with its placement (D11).
- Removing only the `issues:` key from `unattended.yml`'s `on:` block
  makes `execution.py --check` exit 1 with a message naming `issues`
  (D11).
- The parsed bindings for `athena` and `cassandra` have key sets that
  are subsets of `{trigger, events, placement, max_cost_usd}`: no new
  binding key was introduced (D12).
- `bash scripts/ops/tests/execution_test.sh` passes after exactly five
  line updates across four scenarios, and no others: `has "5 binding(s)"`
  at :69 becomes `has "6 binding(s)"`; the bindings string at :76 becomes
  `argus athena atlas cassandra daedalus odyssey ` (with the comment and
  pass line that name five); `--subscribers issues` at :91-93 expects the
  two names instead of empty output; and the `run`/`has` pair at :98-99 —
  `--binding cassandra` expects exit 0 with a printed binding instead of
  exit 1, and `has "has no execution binding"` becomes
  `has "repo-event"` (D11).
- `.github/workflows/unattended.yml`'s `on:` block lists `issues` with
  `types: [opened]` exactly — no `labeled`, `edited`, `reopened` or
  `assigned` (D6, D7).
- The `triage` job's `permissions:` block is exactly `contents: read`
  plus `issues: write`; the `dispatch` job's block contains no `write`
  other than `id-token`; the file-level block is unchanged (D14, D15).
- The `triage` job's `if:` is exactly `github.event_name == 'issues' &&
  github.event.issue.user.type != 'Bot'`: on a `pull_request` payload
  and on a `workflow_dispatch` payload the job is SKIPPED — it never
  runs, so it never fails — and on an `issues` payload whose
  `user.type` is `User` it runs (D9, D14).
- `resolve` declares `needs: triage` and its `if:` is D14's expression:
  on a same-repo `pull_request` payload it evaluates true for every
  value of `needs.triage.result` — `skipped`, `success` and `failure`
  alike — and does not read that value; on a `workflow_dispatch`
  payload likewise; on an `issues` payload it evaluates true only with
  `success`, and false with `failure` and with `skipped` (D14).
- The `triage` step that invokes `scripts/ci/intake_triage.sh` binds
  `NUMBER` in its `env:` and passes `"$NUMBER"`; that step's `run:` body
  contains no `${{` (D10, D14).
- A `pull_request` event still resolves `argus` and `atlas`, and a fork
  pull request is still skipped: the existing guard's behaviour on
  `pull_request` is unchanged by the added `issues` alternative (D8).
- With a payload whose `issue.user.type` is `Bot`, both `triage` and
  `resolve` are skipped; with `User`, both run (D9).
- The `NUMBER` env value and the `concurrency.group` expression each
  contain `github.event.issue.number` between the pull-request term and
  the `inputs.number` term (D10).
- `bash -n scripts/ci/intake_triage.sh` passes, and
  `bash scripts/ci/tests/intake_triage_test.sh` passes with no network
  and no token, using a stub `gh` first on `PATH` (D13).
- `.github/workflows/ci-gates.yml`'s `execution` job runs
  `scripts/ci/tests/intake_triage_test.sh` (D13).
- Triage on an `intent:new` fixture whose `### Problem` block is
  `_No response_` and whose `### Constraints` block is absent makes
  exactly one `blocked` label write and exactly one comment, and the
  comment names `Problem` and does NOT name `Constraints` as missing
  (D18, D21).
- Triage on an `intent:new` fixture with both required blocks filled
  makes no label write at all and exactly one comment whose
  required-sections line is the "all present" form of D17 (D17, D18,
  D21).
- Triage on a `bug` fixture missing `### Severity` applies `blocked`
  and names `Severity`; a `bug` fixture whose `### Evidence` is
  `_No response_` but whose three required blocks are filled gets no
  label write (D18).
- Every comment the script writes ends with the `intake-triage:<n>`
  marker line, and a second run against a thread already containing
  that marker performs zero writes and exits 0 (D16).
- The script performs zero writes and exits 0 when the issue carries
  `hold`, when it is closed, and when it carries neither `intent:new`
  nor `bug`; in each of those three cases the invocation log holds the
  one early labels-and-state read and NO `gh search` call at all (D13,
  D15, D19).
- On an issue that IS triaged, the invocation log holds exactly two
  labels-and-state reads — the early one before any search, and the
  `hold` re-read immediately before the first write — with the marker
  read and the three prior-art sources between them, in that order
  (D13, D15).
- The script exits 1 and writes nothing when `gh search issues` fails,
  when `gh search prs` fails, and when the `intent/*/` listing cannot
  be read (D20).
- Neither recorded `gh search` invocation carries a `--state` flag, and
  a fixture whose stub returns one open and one closed match lists
  both, tagged `(open)` and `(closed)` (D20).
- The query string passed to both `gh search` calls is the derived
  terms joined by ` OR `, byte-for-byte (D20).
- A fixture whose title yields zero terms — every word shorter than 4
  characters, or a stopword — produces zero `gh search` invocations, no
  `intent/*/` listing, and the third prior-art form of D17, and still
  exits 0 (D17, D20).
- Terms derived from the title `Typed intake: issue forms for intent
  and bug, deterministic triage on issue open` are identical on two
  consecutive runs, number at most 6, and contain no word shorter than
  4 characters and no stopword; the derivation is exercised against at
  least three real issue titles (D20).
- The candidate list for a fixture whose title terms match an existing
  folder contains that folder in the `intent/<n>-<slug>/` form, and
  does NOT contain the triaged issue's own number (D20).
- `DRY_RUN=1` on any of the above prints the label write and the
  comment it would have made and performs neither, while every read in
  the invocation log is identical to the non-dry run's (D13).
- `.github/ISSUE_TEMPLATE/config.yml` sets `blank_issues_enabled: false`
  and declares no `contact_links` (D24).
- Both forms parse as GitHub issue-form YAML; the intent form's five
  `textarea` labels are exactly `Problem`, `Proposed outcome`,
  `Affected users and systems`, `Constraints`, `Open questions`, in
  that order, with `required: true` on the first two only; the bug
  form's labels are exactly `What happened`, `What you expected`,
  `Evidence`, `Persona or script involved`, `Severity`, with
  `required: true` on the first two and on `Severity`, whose options
  are exactly the three of D22 (D18, D22).
- The intent form's five labels are string-identical to the five `## `
  section names of `intent/117-typed-intake/intent.md` and to the five
  section names the triage script matches on — one comparison proves
  all three agree (D23).
- Neither form sets `title:`, and neither carries a `checkboxes` field
  (D22, D25).
- `bash scripts/ci/sanitize_check.sh` exits 0 with the forms and the
  script tracked: no absolute home path, no credential and no vendor or
  model name in any new file (D22).
- `bash scripts/setup/bootstrap_tracker.sh --labels-only` against a
  repository where `bug` already exists prints that it exists and was
  kept and creates nothing; against one where it does not, it creates
  `bug` with colour `d73a4a`; the script now names 15 labels (D26).
- `docs/SPEC.md` carries an `intake.triage` entry and the five
  amendments of D27; `lifecycle.labels` says 15 and names `bug` as
  human-facing and off the ladder; `personas.resume` enumerates the
  five ladder rungs AND the off-ladder `maintain` row and no longer
  says "five rungs" alone; `ops.dispatch` says "Eight refusals" and
  names the third derivation arm; `execution.placement` lists `issues`
  beside `pull_request` and no longer says cassandra carries no
  binding; `intake.automation` is still under
  "Agreed, not yet built"; `bash scripts/ci/spec_check.sh` exits 0 and
  the implementing PR carries a `Spec-impact:` marker (D27).
- With the sixth row present, `relabel_of cassandra` in
  `scripts/ops/smoke_launch.sh` prints nothing, `relabel_of` for each
  of the five ladder personas prints the same label as before the row,
  both jq reads of `.stages[]` in that file carry
  `startswith("status:")`, and the comment at :258-260 no longer says
  "absent by construction"; `bash scripts/ops/tests/smoke_launch_test.sh`
  passes with no edit to that suite and a PASS set byte-identical to the
  one before the row — the proof being that without the filter the R1-2
  fixture (:303-308) turns athena's relabel into `bug` and the assertion
  at :310 goes red (D28).

## Open questions

None. The three the intent carried are decided by D1 (where a confirmed
bug enters the ladder), D15 (who authors the triage comment) and D23
(the form-heading to intent.md mapping).
