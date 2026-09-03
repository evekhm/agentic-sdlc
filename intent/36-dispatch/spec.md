# Spec: one-argument dispatch

**Issue:** #36 · **Status:** Approved (approval = merge of this PR) ·
**Author:** athena (`evekhm-athena-app[bot]`) ·
**Open questions:** none

The three questions filed on #36 were directed to be decided, not
posed back (#36, Presenter direction; claim comment 2026-09-02). They
land below as D1 (where the source lives), D6 (slug derivation) and
D9 (a PR number). **Any row in this table can be overruled by editing
this file at the merge gate** — the merge is the acceptance, so an
edited row is the decision, not a comment asking for one.

## What is being built

```text
personas/lifecycle.json           NEW: the label <-> stage source of truth
personas/skills/resume-protocol.md NEW: the shared protocol, one copy
personas/*.yaml (6 personas)      the skill added to each skills list
scripts/sync_agents.py            renders the generated ladder block
scripts/ci/lifecycle_advance.sh   inline case DELETED; reads the source
scripts/ops/work.sh               NEW: deterministic one-argument dispatch
.claude/agents/  .agents/agents/  REBUILT (drift gate)
docs/SPEC.md                      ops.dispatch + personas.resume + 3 edits
```

## The source file

`personas/lifecycle.json` is an ordered array under key `stages`, one
object per rung of the ladder, in ladder order:

| Key | Meaning |
|-----|---------|
| `stage` | a value from `schema.json`'s `stage` enum — the join key to `personas/*.yaml` |
| `label` | the single `status:*` label meaning this stage is current |
| `artifact` | the file this stage owes, or `null` where the output is code or a review |
| `advances_to` | the label written when `artifact` merges, or `null` at the end of the ladder |
| `advance_message` | the one line the advancer posts on that transition |
| `dispatch_brief` | the one line a session owning this stage is handed |

Five rows: `plan`/`status:planning`/`intent.md`, `design`/
`status:spec`/`spec.md`, `build`/`status:build`/`plan.md`,
`implement`/`status:implementing`, `review`/`status:in-review`.
`intake`, `deploy` and `maintain` are stage-enum values with no rung
and are absent by construction. Owner is **not** a key — see D2.

## Decisions

| ID | Decision |
|----|----------|
| D1 | **The source lives at `personas/lifecycle.json`.** Stage ownership is a persona-domain fact, and `config/` was reserved for deployment bindings — which harness, which model family, which tool (#2, D1/D2); a ladder that is identical on every deployment is not a binding. JSON, not YAML, for three reasons: the compiler's source glob is `personas/*.yaml`, so a `.json` file cannot be mistaken for an eleventh actor and the loader needs no exclusion list; it sits beside `schema.json`, the directory's other machine-readable non-actor file; and its two bash readers already depend on `jq` (#4, D8) but on no YAML parser. |
| D2 | **One table, no owner column.** `personas/lifecycle.json` is the only place the label ↔ stage relation is written. The advancer's inline `case` is deleted and it looks the row up by the added `artifact`, taking `advances_to` and `advance_message` from the file; the compiler reads it with the JSON stdlib; `work.sh` reads it with `jq`. Ownership is *derived*, never stored: the owning persona of a stage is every `personas/*.yaml` whose `stage` list contains it. Moving a stage between personas therefore edits exactly one YAML file and nothing else. |
| D3 | **The skill is inlined verbatim; the ladder is a generated block.** `personas/skills/resume-protocol.md` states the stage-independent protocol and is inlined byte for byte like every other skill (#5, D5 unchanged). The compiler appends one section, `## Lifecycle stages`, rendered from `personas/lifecycle.json` joined against every source's `stage` field — the same mechanism as generated capability fallbacks (#5, D4), deterministic and sorted (#5, D1). It is emitted only into targets whose source declares the skill. Hand-authoring that table into the markdown is forbidden: it would be the second copy D2 exists to prevent. |
| D4 | **The resume protocol is seven ordered steps.** (1) Read the issue: open/closed, labels, and the thread bottom-up to the last handoff comment. (2) Apply D5's refusals, in D5's order, before any write. (3) Derive the stage from the single `status:*` label; an issue carrying `intent:new` and no `status:*` is stage `plan`. (4) Claim: add `in-progress` and post the one-line claim (AGENTS.md, "Working the tracker", step 2). (5) Resolve the folder per D6 and the branch as `<persona>/<n>-<slug>`. (6) Produce the stage's `artifact`. (7) Hand off by PR plus the Done/Decided/Next/Blocked comment; remove `in-progress` if pausing rather than finishing. The steps cite AGENTS.md and do not restate it. |
| D5 | **Six refusal conditions, checked in this order, before any write.** (a) `hold` present — write nothing at all, not even the claim (#4, D2; trusted-posting rule 5). (b) issue closed, or labelled `status:review-stuck` — humans have taken over. (c) `blocked` — report and stop. (d) more than one `status:*` — corrupted state; report the labels found and stop **without** guessing and **without** applying `hold`, because the advancer is the single writer of the circuit breaker and two writers is two circuit breakers (#4, D1). (e) `in-progress` present and the last claim comment names a *different* actor — stop and name the holder; the same label with a claim naming *this* persona is a resume of its own work and proceeds. (f) the derived stage is not in this persona's `stage` list — name the owner(s) from the generated block and stop. A refusal is a report, never a partial claim. |
| D6 | **Folder: reuse, else derive from the title.** If exactly one `intent/<n>-*/` directory exists, use it. If none exists, `slug` = the issue title cut at the first `:` or `;`, lowercased, every run of characters outside `[a-z0-9]` replaced by `-`, leading and trailing `-` trimmed, then truncated to at most 24 characters at the last `-` that leaves a non-empty slug. If more than one exists, that is corrupted state: refuse and name them, per D5(d)'s never-guess rule. Deterministic beats named-in-a-comment because two sessions on the same cold issue must land on the same path without reading each other. This change's own folder predates the rule and is reused under the first branch; the derivation binds only where no folder exists, and the presenter may rename at the merge gate. |
| D7 | **A number is the whole instruction.** `work.sh` and the protocol accept the issue-or-PR number and nothing that carries work content. `DRY_RUN` and `--as <persona>` (D9) are the only other inputs. There is deliberately **no** flag naming a stage, a folder, an artifact or a branch: such a flag would let a session work a stage the labels say is not current, which is precisely the drift the labels-are-the-state-machine rule exists to stop (#4; #36, Presenter direction, item 2). |
| D8 | **`work.sh` is deterministic bash + `gh` + `jq`, no model call, failure-mode first.** Order: resolve the number → refusals in D5's order → owner set → harness pin → launch. `DRY_RUN=1` prints the resolved issue number, stage, label, owner(s), folder (existing or derived), branch, harness and the exact command line, then exits 0 having written nothing to GitHub; dry runs still READ, so the live guards are exercised (#4, D8). Exit codes: `0` launched or printed, `2` refused (a stated D5 condition — expected, not a bug), `1` unusable input (unreadable number, missing pin, unparsable source). Fail-closed on input, fail-soft never: one number is one run (#4, D9). |
| D9 | **A PR number resolves to its issue; a multi-owner stage prints and launches nothing.** Resolution: `Closes #<n>` in the PR body, else the `<actor>/<n>-<slug>` branch name, else exit 1 — the PR is not the unit of work, the issue is. If the resolved stage has more than one owner — which today is `review`, owned by both reviewers — `work.sh` prints both personas' full instructions and launches neither, unless `--as <persona>` names one of them. Auto-picking would silently halve a policy whose whole content is that two independent reviewers on different model families both look (#2, D4). This is the general multi-owner rule, not a review special case. |
| D10 | **The harness comes from the pin, the launch table from the script.** `work.sh` reads `config/deployments.yaml` → `personas.<owner>.harness`. For a harness it knows how to start, it launches the compiled persona with the initial prompt `#<n>`; for any other harness it prints the persona, the target and that same one-line prompt and exits 0 — an unlaunchable harness is a supported outcome, an owner with no pin is exit 1. No vendor, harness or model name appears in `personas/**` or in `personas/lifecycle.json` (#1, D3; #2, D2); the model is whatever the harness resolves for the compiled target. |
| D11 | **The living-spec upsert is part of the implementing PR.** Two new entries: `ops.dispatch` (arguments, resolution order, refusals and their exit codes, `DRY_RUN`) and `personas.resume` (the source file's keys, the seven steps, the generated block). Three amendments: `tracker.workflow` reworded to say the number is the whole instruction; `lifecycle.labels` to say the advancer reads `personas/lifecycle.json` instead of an inline case; `personas.compiler` to record the generated ladder block. Entry IDs are stable and dotted, matching the existing set. |
| D12 | **The skill goes to personas only, and the drift gate sees it.** `resume-protocol.md` is added to the `skills` list of all six `kind: persona` sources and to no sub-agent: a sub-agent has no `stage`, no identity and no authority to claim an issue, and handing it a tracker protocol invites exactly the write its authority forbids. All six compiled persona targets across the two live harnesses therefore change, and the implementing PR must include the rebuild — `python3 scripts/sync_agents.py --check` exiting 0 is the gate, and hand-editing any target fails it (#5, D7; #6). |
| D13 | **No new labels and no new documents.** The taxonomy is unchanged (#4): this change reads labels, it does not add one. The only new prose is the skill; the only new data is `personas/lifecycle.json`; `work.sh` is a script, not a document (AGENTS.md, "No document sprawl"). |
| D14 | Bootstrap compression per intent/1-personas/spec.md D10 applies: PLAN, DESIGN and BUILD artifacts land in one PR. Not a precedent. |

## Acceptance

- `jq -e '.stages | length == 5' personas/lifecycle.json` passes, and
  every `label` in it is one the label provisioner creates and every
  `stage` is a value in `schema.json`'s `stage` enum (D1, D2).
- No `status:*` → stage mapping table exists outside
  `personas/lifecycle.json`: `grep -rn 'status:spec' scripts/` matches
  only reads of that file (D2).
- For all three transitions the advancer's posted comment text is
  byte-identical to the text it posts today, verified by
  `DRY_RUN=1 scripts/ci/lifecycle_advance.sh <before> <after>` over
  the #4 synthetic range, including the Draft-spec warning, which
  stays a condition in the script and not a row in the file (D2).
- `python3 scripts/sync_agents.py --check` exits 0 only after the
  rebuild; all six persona targets differ from their pre-change form
  and no sub-agent target differs (D3, D12).
- Two consecutive builds are byte-identical, and the generated
  `## Lifecycle stages` block lists `review` with both reviewers,
  sorted (D3, D9).
- `DRY_RUN=1 scripts/ops/work.sh <n>` on an open, singly-labelled
  issue prints stage, owner, folder, branch, harness and command, and
  exits 0 having written nothing (D8).
- Each D5 condition, given a fixture issue, exits 2 with a message
  naming the condition and writes nothing: `hold`, closed,
  `status:review-stuck`, `blocked`, two `status:*`, and `in-progress`
  claimed by another actor — while `in-progress` claimed by the owner
  itself proceeds (D5).
- `work.sh` on a PR number resolves through `Closes #<n>`, and with
  the branch-name fallback when the body has none; on a stage at
  `status:in-review` it prints two instructions and launches nothing,
  and `--as <reviewer>` launches exactly one (D9).
- The slug rule, run against three real issue titles, yields the same
  slug twice in a row and never exceeds 24 characters; an issue with
  an existing folder reuses it and never derives (D6).
- `bash -n` passes on both scripts; `bash scripts/ci/spec_check.sh`,
  `bash scripts/ci/sanitize_check.sh` and
  `bash scripts/ci/compiler_roundtrip.sh` exit 0 (D11, D12).
