# Spec: repin odyssey and cassandra to antigravity

**Issue:** #44 · **Status:** Approved (approval = merge of this PR) ·
**Author:** athena (`evekhm-athena-app[bot]`) ·
**Open questions:** none

Bootstrap compression per `intent/1-personas/spec.md` D10 applies here
too (as it did on #2): intent and spec land in one PR, recorded once,
not a precedent.

D1–D3 are the pins and the reviewer constraint, D4–D6 the compiled
targets and the model, D7–D9 the smoke test and the living spec,
D10 the cost measurement, D11 the issue's open question. D12–D16 came
out of the spec-adversary pass against this draft and are marked
*(adversary)*.

Every claim below about `agy` behaviour cites
`runs/2026-09-03_agy-headless/findings.md` (agy 1.1.24, probed
2026-09-03) or `config/tools.yaml`'s inline record of #43's smoke run
(agy 1.1.25). **Any row can be overruled by editing this file at the
merge gate** — the merge is the acceptance, so an edited row is the
decision, not a comment asking for one.

## What is being built

```text
config/deployments.yaml           2 pins flipped + 1 comment (D1, D2)
.claude/agents/odyssey.md         DELETED by the rebuild
.claude/agents/cassandra.md       DELETED by the rebuild
.agents/agents/odyssey/           NEW: agent.md + agent.json
.agents/agents/cassandra/         NEW: agent.md + agent.json
scripts/ops/smoke_launch.sh       the two arms follow the pins (D7, D14)
docs/SPEC.md                      ops.dispatch: one sentence (D9)
```

Not touched, deliberately: `personas/**` (no persona source changes, so
no new sanitize surface), `config/model_tiers.yaml` (unchanged — only
which column each persona resolves through changes, D3),
`config/tools.yaml`, `personas/lifecycle.json`, `scripts/ops/work.sh`
(it reads the pin; its behaviour changes without its text changing),
`config/execution.yaml` (#25 D19 binds *placements*, not harnesses),
`CLAUDE.md` (D11), and `scripts/auth/app_manifests.yaml` (#47's).

## The pins, before and after

| persona | before | after | tier → model after |
|---|---|---|---|
| athena | claude-code | **claude-code** (D1) | FRONTIER → `opus` |
| daedalus | antigravity | antigravity | FRONTIER → `gemini-3.1-pro-high` |
| odyssey | claude-code | **antigravity** | IMPLEMENTATION → `gemini-3.7-flash-high` |
| argus | claude-code | **claude-code** (D1) | REVIEW → `opus` |
| atlas | antigravity | antigravity | REVIEW → `gemini-3.1-pro-high` |
| cassandra | claude-code | **antigravity** | FAST → `gemini-3.7-flash-medium` |

## Decisions

| # | Decision |
|---|---|
| D1 | **`odyssey` and `cassandra` move to `antigravity`; `athena` and `argus` stay on `claude-code`, each for a stated reason.** `odyssey` moves because it is the highest-volume persona in the system — `IMPLEMENTATION` tier, `max_turns: 120`, `timeout_mins: 90`, the largest caps of any persona, spent on reading plans, writing code and running test suites. `cassandra` moves because she is the cheapest work on the most expensive billing relationship: `FAST`-tier watcher sweeps on a cadence, where a 1-sigma sweep that finds nothing still pays list rates for the context it re-reads. `athena` stays because plan and design are the two gates where words become commitments and the spec-adversary protocol is the highest-judgment work in the loop; moving it later is the same one-line edit (out of scope, below). `argus` stays because #2 D4 requires the two reviewers to resolve to different model families and `atlas` is on antigravity — after this change `argus` is the only persona left that can be the non-Gemini half. Testable: `config/deployments.yaml`'s `personas` block matches the after column of the table above, and the implementing PR's diff of that file changes exactly two `harness:` values. |
| D2 | **The reason `argus` stays is written into `config/deployments.yaml`, above the `constraints` block, not left in this spec.** Grounds: `docs/SPEC.md` states that which model family backs which reviewer "is a `config/` fact and appears nowhere in the policy", so the config file is the only place the fact may live — and after D1 it is a fact with no slack, because a later session repinning "everything else for price" would violate #2 D4 with a one-line edit and, until #6 lands, no error. The comment names `argus` as the last non-Gemini reviewer and cites #2 D4 and #44. A vendor-family name in a comment there is allowed: the sanitize gate's `vendor` rule scopes to `personas/**` (`scripts/ci/sanitize_check.sh`), and `config/` is by #2 D2 the layer where vendor strings belong. Testable: `scripts/ci/sanitize_check.sh` passes with no new allowlist entry, and the comment exists immediately above `constraints:`. |
| D3 | **The #2 D4 check is a resolution performed and recorded, not a confirmation asserted.** The procedure, for each name in `constraints.distinct_model_families`: read `personas.<name>.harness` from `config/deployments.yaml`, read `harnesses.<that harness>.REVIEW` from `config/model_tiers.yaml`, and compare the two resulting model IDs' vendor families. After D1 it resolves: `argus` → `claude-code` → `opus`; `atlas` → `antigravity` → `gemini-3.1-pro-high`; families `claude` and `gemini` differ, so the constraint holds. Two things this decision fixes that "confirm it still holds" leaves open. First, **the tier is `REVIEW` and only `REVIEW`**: `cassandra`'s `escalation_tier: REVIEW` resolving to `gemini-3.1-pro-high` after the move does not enter the check, because D4's list is exactly `[argus, atlas]` and an escalation tier is not a persona. Second, **the check is run even though its inputs are byte-identical before and after** — `model_tiers.yaml` is not edited and neither reviewer is repinned — because "the inputs did not change" is a claim about the diff, and the diff is what acceptance reads. Testable: the implementing PR records the four resolved values above; `git diff` of `config/model_tiers.yaml` is empty; the two `harness:` lines changed are `odyssey` and `cassandra` and no others. |
| D4 | **The moved personas' model pin is expressed exactly as #43 D8/D9 built it: never in `agent.md`, always in the `agent.json` sidecar that `work.sh` reads.** `.agents/agents/<p>/agent.md`'s frontmatter carries `name`, `description` and `tools` and no `model:` key — a `model:` key voids the whole agent, which then silently falls back to the stock agent (findings Q1b). The resolved model rides in `.agents/agents/<p>/agent.json` as `.model`, which `work.sh` reads with `jq` and passes as `agy --model`. Concretely after the rebuild: `jq -r .model .agents/agents/odyssey/agent.json` is `gemini-3.7-flash-high` (`antigravity.IMPLEMENTATION`) where the deleted `.claude/agents/odyssey.md` said `model: claude-sonnet-5`, and `jq -r .model .agents/agents/cassandra/agent.json` is `gemini-3.7-flash-medium` (`antigravity.FAST`) where the deleted `.claude/agents/cassandra.md` said `model: haiku`. Testable: those two `jq` values equal the corresponding `config/model_tiers.yaml` entries; `grep -c '^model:' .agents/agents/{odyssey,cassandra}/agent.md` is 0 for both. |
| D5 | **The rebuild is part of the same commit as the pin edit, and `scripts/sync_agents.py --check` is the gate.** Exactly four files appear and two disappear: `.agents/agents/{odyssey,cassandra}/{agent.md,agent.json}` added, `.claude/agents/{odyssey,cassandra}.md` deleted, and **no other file under `.claude/agents/` or `.agents/agents/` changes**. The sub-agent targets in particular are untouched: `coder`, `contract-writer`, `mechanic`, `explorer` and `scanner` are `kind: subagent`, carry no pin, and are already emitted for both harnesses (#2 D3, `scripts/sync_agents.py`), so repinning a persona adds no sub-agent file. Same commit rather than a follow-up: a commit in which `deployments.yaml` says `antigravity` and `.claude/agents/odyssey.md` still exists is a tree where `sync_agents.py --check` fails and `work.sh` preflights a target that does not exist (#43 D3, exit 1) — a state no bisect, no CI run and no cherry-pick should be able to land on. Testable: `scripts/sync_agents.py --check` and `scripts/ci/compiler_roundtrip.sh` both pass at the tip; `git show --stat` of the pin commit lists exactly those seven paths (`deployments.yaml` plus the six target changes). |
| D6 | **The acceptance for a moved persona's `tools:` block is a real `agy` launch, never an inspection of the file.** Grounds: `config/tools.yaml`'s own record of #43's smoke run (agy 1.1.25) — an unrecognised tool name in `agent.md`'s `tools:` block is a **hard** error (exit 1, `status: "ERROR"`, zero tokens, no session at all), and "every antigravity persona carrying `delegate` was unlaunchable" until that one line changed. Both moved personas carry `delegate`, which maps to `manage_subagents`. `odyssey`'s capabilities resolve to `view_file, grep_search, find_by_name, write_to_file, replace_file_content, run_command, manage_subagents`; `cassandra`'s to the same list minus the two write tools. Every one of those names is a measured name in `config/tools.yaml`, but the measurement that matters is a session that starts. Testable: the D7 smoke run of `odyssey` on antigravity returns a non-zero input-token count and a persona-shaped answer, not `status: "ERROR"` with zero tokens; for `cassandra`, D15's direct invocation does the same. |
| D7 | **`scripts/ops/smoke_launch.sh`'s two arms follow the pins: the `claude-code` arm becomes `athena`, the `antigravity` arm becomes `odyssey`.** #43 D19 fixed the arms as personas (`odyssey` for claude-code, `daedalus` for antigravity) because those were the pins at the time. Left alone through this repin, `run 1 · claude-code · odyssey` starts `agy`, both arms exercise the same harness, the script still exits 0, and #43's gate silently stops covering Claude Code — which is the exact class of failure (an expensive silent success) that #43 exists to prevent. `athena` for the claude-code arm rather than `argus`: the arm's observable is a comment authored by the persona on the scratch issue, and `argus`'s App is registered `issues: read` until #47 while `athena`'s has `issues: write` (`scripts/auth/app_manifests.yaml`). `odyssey` for the antigravity arm rather than keeping `daedalus`: the arm's job after this issue is to prove that *the moved persona* launches, and `odyssey`'s App has `contents: write` as well, so the commit observable #43 D19 chose still works unchanged. The arms' `relabel` targets move with them — `status:planning` for the `athena` arm (a stage `athena` owns), `status:implementing` for the `odyssey` arm — and the scratch-issue body's errand text is rewritten to name the two new personas. The script's own housekeeping identity stays `odyssey` (body write, relabel, comment counts): its App keeps `issues: write` regardless of which harness runs it. Testable: `scripts/ops/smoke_launch.sh <scratch>` prints `run 1 · claude-code · athena` and `run 2 · antigravity · odyssey`, exits 0, and asserts per arm the exit code, the artifact, and the author of the comment (`evekhm-athena-app[bot]`) or the commit (`evekhm-odyssey-app[bot]`). |
| D8 | **`cassandra` is not smoke-launched, and the reason is structural rather than a gap in this issue.** `cassandra`'s only stage is `maintain`, and `personas/lifecycle.json` states that `intake`, `deploy` and `maintain` "are stage-enum values with no rung and are absent by construction": no `status:*` label resolves to `maintain`, and `work.sh` validates `--as` against the owners of the stage the labels say is current (refusal (f)). So `work.sh <n> --as cassandra` refuses on every issue in the repository, before this change and after it. Her dispatch remains impossible until #11 decides her cadence and she gains an entry in `config/execution.yaml` (#25 D19 deliberately gives her none). What this issue owes for her is therefore the *harness* half, not the *dispatch* half — see D15 for the two observables. Testable: the spec, the PR body and the #44 handoff all say that `cassandra` is repinned but not dispatchable, and name #11 as the issue that changes that. |
| D9 | **The implementing PR upserts exactly one sentence of `docs/SPEC.md`, in `ops.dispatch`, and does not claim `Spec-impact: none`.** The entry currently reads that `smoke_launch.sh` gives "one real launch per harness — three named observables each, with the claim half of the Antigravity run reported as `BLOCKED ON #47` until that App's `issues: write` permission is granted". D7 changes which personas those runs are, and D14 changes what the `BLOCKED ON #47` line probes; the sentence as written becomes false. Nothing else in `docs/SPEC.md` needs to move: `config.bindings` describes the mechanism and deliberately does not enumerate pins, and the review entry deliberately says which family backs which reviewer "appears nowhere in the policy" — so the repin adds no new SPEC statement about who runs where, by design. `Spec-impact: none` is not available to this PR because `config/` and `scripts/` are behavior-bearing paths under `scripts/ci/spec_check.sh` and the behaviour genuinely changes. Testable: `scripts/ci/spec_check.sh <base>` passes on the implementing PR because the diff touches `docs/SPEC.md`; the diff of that file is one entry. |
| D10 | **The cost measurement is two `session_spend.sh` runs on the Claude side plus `agy`'s own `usage` on the other, and it never produces a single cross-vendor dollar figure.** `scripts/ops/session_spend.sh` reads Claude Code `*.jsonl` transcripts and prices them against the Anthropic rate table; a model that table does not know is reported `UNPRICED` by name with its tokens excluded from the USD columns. It therefore cannot price a Gemini session, and a "we saved $X" number spanning both vendors would be an invention. What is taken: (a) **before** — `scripts/ops/session_spend.sh <transcript-dir> --check` over the baseline session set of D13, recording the two numbers AGENTS.md requires together, cache hit rate `read/(read+write+fresh)` and tokens-per-message, plus the per-model USD roll-up; (b) **after** — the same command over the after set of D13, where the observable is that the `claude-sonnet-5` and `haiku` rows attributable to `odyssey` and `cassandra` fall to zero on that harness; (c) **the antigravity side** — the `usage` object from each launch's `--output-format json` (findings Q5), recorded per run as tokens, with the GCP bill named as the authority for dollars. Where it lands: a run folder `runs/<YYYY-MM-DD>_44-repin-cost/` per AGENTS.md, which is gitignored — so the numbers do not survive there. They are reported in a comment on #44 and summarised in the implementing PR body, and the run folder's `findings.md` carries the disposition footnote naming that comment. Testable: the #44 comment shows, for each of before and after, hit rate and tokens-per-message and the per-model USD table; it shows antigravity tokens with no USD column; the run folder carries a disposition footnote. |
| D11 | **CLAUDE.md's `IMPLEMENTATION_TIER` binding does not change, and the implementing PR does not touch CLAUDE.md.** The two readings: the note describes the tier for *the persona that runs at it* (so moving `odyssey` makes it stale prose), or it describes the tier *for sessions running on the Claude Code harness* (so a persona pin is orthogonal to it). The differing case: after the merge, `athena` — still on `claude-code` — dispatches the `coder` sub-agent while working a design stage. Under the first reading nothing tells that session which model `coder` runs at, because the only persona that used the binding has left the harness; under the second, `.claude/agents/coder.md` still carries `model: claude-sonnet-5` and the binding is exactly what produced it. The second reading is the correct one and it is structural, not a preference: AGENTS.md ("Subagent model tiers") makes the tier→model map a **per-harness** fact, `config/model_tiers.yaml` keeps a full `claude-code` column that this issue does not edit, and #2 D3 says a sub-agent carries no pin and resolves through its dispatcher's harness — so `coder` under `odyssey`-on-antigravity resolves `antigravity.IMPLEMENTATION` (`gemini-3.7-flash-high`) while `coder` under any claude-code dispatcher resolves `claude-code.IMPLEMENTATION` (`claude-sonnet-5`), and both compiled targets continue to exist because `kind: subagent` emits for every harness. The binding's live consumers after the move are `athena`, `argus`, and the presenter's own interactive sessions. Testable: after the rebuild `.claude/agents/coder.md` still exists and still says `model: claude-sonnet-5`; `jq -r .model .agents/agents/coder/agent.json` is still `gemini-3.7-flash-high`; `git diff` of `CLAUDE.md` is empty. |
| D12 *(adversary)* | **The pins, the rebuild, the smoke arms and the `docs/SPEC.md` sentence are one pull request, not a config-only PR plus a follow-up.** Two readings of "config-only" (#44's own wording): the implementing PR touches only `config/deployments.yaml` and the compiled targets, with D7's smoke change filed as a separate issue; or one PR carries all four. The differing case is the window between two PRs. During it, `scripts/ops/smoke_launch.sh <scratch>` launches `agy` twice, prints `run 1 · claude-code · odyssey`, asserts three observables, and **exits 0** — a green gate reporting coverage of a harness it did not touch, while `docs/SPEC.md` states a `BLOCKED ON #47` behaviour the script no longer has. One PR. "Config-only" survives as a statement about the *source* layer: `personas/**` is untouched and exactly one line of one config file decides the harness. |
| D13 *(adversary)* | **The cost baseline is a named set of sessions, not a calendar window.** Two readings of D10's "before": the N days of transcripts preceding the merge, or an explicitly listed set of sessions. The differing case: `odyssey` worked three implement stages in the week before this PR and none in the week after, because no issue reached `status:implementing`. Under the calendar reading the after-window shows near-zero Claude spend for `odyssey` and the report claims a saving the repin did not cause. Under the session reading the comparison is **the last three `odyssey` implement-stage sessions on `claude-code` before the merge, listed by transcript id, against the first three after** — and if fewer than three exist after, the report says how many it has and calls the number provisional rather than dividing by a week. `cassandra` is measured the same way by sweep, or reported as "no sessions yet" if #11 has not given her a cadence. A comparison whose denominator is time measures how busy the week was; this one measures what a session costs. |
| D14 *(adversary)* | **The `BLOCKED ON #47` probe survives the arm swap as a standalone `check_claim daedalus`, launching nothing.** Two readings of D7: the arms move and `check_claim` moves with them, or the arms move and the `#47` probe stays. The differing case: #47 is still ungranted on the day this merges. Under the first reading both arms now run personas whose Apps have `issues: write`, every `check_claim` passes, the string `BLOCKED ON #47` never appears again — and #43 D19's own testable property ("its `BLOCKED ON #47` line disappears once the permission is granted, with no edit to the script") is falsified, because the line disappeared for a completely different reason and the smoke output now reads as if #47 were done. Under the second, the script keeps one `check_claim daedalus` call outside both arms: one API call, one mint, no launch, no model tokens, and the line still means what `docs/SPEC.md` says it means. Second reading. This is what D9's sentence is reworded to describe. |
| D15 *(adversary)* | **`cassandra`'s acceptance is one positive harness check and one negative dispatch assertion, and the negative one is required.** Two readings of D8: her acceptance is only that the compiled target exists and `--check` passes, or it also asserts the refusal. The differing case: a future session repins `cassandra` back to `claude-code` and, finding no smoke coverage, concludes the antigravity target was never proven; or the reverse — a session sees `work.sh --as cassandra` fail and files it as a #44 regression. So both are asserted. Positive: the exact line `work.sh` would build for her, run by hand — `agy -p '<the D2-of-#43 prompt>' --agent cassandra --add-dir <repo root> --model gemini-3.7-flash-medium --output-format json --print-timeout 20m` — returns `status: "SUCCESS"` with a non-zero `usage` input count and an answer that shows the persona loaded (not the stock agent). Negative: `scripts/ops/work.sh <any labelled issue> --as cassandra` exits 2 naming the owners of that issue's stage, and the message does not mention a harness — proving the refusal comes from the stage machinery (`maintain` has no rung) and not from the repin. |
| D16 *(adversary)* | **`escalation_tier` becomes prose without a mechanism for both moved personas, and this issue accepts that rather than fixing it.** `odyssey` (`escalation_tier: FRONTIER`) and `cassandra` (`escalation_tier: REVIEW`) are the only two personas in `personas/**` that declare one, and this issue moves both — so the repin is the first time the compiled sentence "You may escalate to the … grade only when …" is emitted for a persona on antigravity. Two readings of what it then means. First: escalate = run at the higher model. The differing case: `odyssey` hits a genuinely hard bug 40 minutes into an implement stage. Under the first reading it must reach `gemini-3.1-pro-high`, and it cannot — `agy` takes one `--model` fixed at launch from the sidecar, headless print mode is the only mode #43 offers for this harness (#43 D5), and #36 D7 forbids a flag that names a model, so the only escalation path is a second `work.sh` invocation that resolves the same model again; the session stalls until the 90-minute wrapper kills it. Second: escalate = stop and hand the question back on the issue, which is what `odyssey`'s role text already requires for open design questions. Second reading, for antigravity. It is recorded here rather than fixed because fixing it means either a model-bearing flag (forbidden) or a second tier column consulted at launch, and both are `work.sh`/compiler changes that belong to whoever needs the escalation, not to a two-line repin. Testable: this row is cited by the #44 handoff as a known consequence; no `escalation_tier` handling is added to `work.sh` or `scripts/sync_agents.py` in the implementing PR. |

## Acceptance

Each item names the Decision it derives from; a contract test that
cannot cite one is a missed ambiguity and comes back here (the
spec-adversary skill's downstream contract).

1. `config/deployments.yaml` matches the after column of the pins
   table; the diff of that file changes exactly two `harness:` values
   (`odyssey`, `cassandra`) and adds one comment above `constraints:`
   naming `argus` as the last non-Gemini reviewer (D1, D2).
2. `scripts/ci/sanitize_check.sh` passes with no new allowlist entry
   (D2).
3. The D3 resolution is recorded with its four values — `argus` →
   `claude-code` → `opus`, `atlas` → `antigravity` →
   `gemini-3.1-pro-high` — and `git diff config/model_tiers.yaml` is
   empty (D3).
4. `jq -r .model .agents/agents/odyssey/agent.json` is
   `gemini-3.7-flash-high` and `.../cassandra/agent.json` is
   `gemini-3.7-flash-medium`; neither `agent.md` contains a line
   matching `^model:` (D4).
5. `scripts/sync_agents.py --check` and
   `scripts/ci/compiler_roundtrip.sh` pass; the pin commit's
   `--stat` lists exactly `config/deployments.yaml`, the two deleted
   `.claude/agents/*.md`, and the four new `.agents/agents/*` files,
   and no sub-agent target changed (D5).
6. `scripts/ops/smoke_launch.sh <scratch>` prints
   `run 1 · claude-code · athena` and `run 2 · antigravity · odyssey`,
   exits 0, and asserts per arm the exit code, the artifact, and the
   author of the produced comment (`evekhm-athena-app[bot]`) or commit
   (`evekhm-odyssey-app[bot]`) (D7).
7. The `odyssey` antigravity arm's session reports a non-zero input
   token count and does not exit with `status: "ERROR"` and zero
   tokens — the signature of an unrecognised `tools:` name (D6).
8. The same run still prints exactly one `BLOCKED ON #47` line, from a
   standalone `check_claim daedalus` that launches nothing, and that
   line disappears with no edit to the script once #47 lands (D14).
9. The hand-run `agy` line for `cassandra` returns `status: "SUCCESS"`
   with non-zero usage and a persona-loaded answer; `work.sh <n> --as
   cassandra` exits 2 naming the stage's owners, with no harness in the
   message (D8, D15).
10. `docs/SPEC.md`'s `ops.dispatch` entry is upserted for the new arms
    and the standalone `#47` probe; `scripts/ci/spec_check.sh <base>`
    passes because the diff touches it, not because of a marker (D9).
11. A comment on #44 reports before and after with, for each, cache hit
    rate and tokens-per-message and the per-model USD table for the
    Claude side, plus antigravity tokens from `usage` with no USD
    column; the baseline is named as a session list, not a date range;
    `runs/<date>_44-repin-cost/findings.md` carries a disposition
    footnote pointing at that comment (D10, D13).
12. `git diff CLAUDE.md` is empty; `.claude/agents/coder.md` still says
    `model: claude-sonnet-5` and
    `jq -r .model .agents/agents/coder/agent.json` is still
    `gemini-3.7-flash-high` (D11).
13. Everything above lands in one pull request (D12).

## Out of scope

- **Moving `athena` to antigravity.** It is the same one-line edit and
  the same rebuild this issue performs twice; it is deferred because
  plan and design are the highest-judgment stages, not because it is
  hard. Whoever makes it re-reads D1 and nothing else.
- **Repinning `argus`.** Not merely out of scope: after D1 it is a
  violation of #2 D4 unless `atlas` moves off antigravity in the same
  edit. D2 puts that warning where the edit happens.
- **#47.** Raising `daedalus`, `argus` and `atlas` to `issues: write`
  is a human action on github.com. This issue does not depend on it —
  both moved personas already have `issues: write` — and D14 keeps its
  signal alive rather than absorbing it.
- **`cassandra`'s cadence and dispatch.** `maintain` has no rung
  (D8); giving her a trigger belongs to #11 and an
  `config/execution.yaml` entry to #25, whose D19 deliberately gives
  her none.
- **#25's placements.** D19 binds `trigger` and `placement`, not
  harness; `odyssey` is already `trigger: manual, placement: vm-local`
  there and this change does not touch it.
- **Making `escalation_tier` reachable on antigravity** (D16). It needs
  a `work.sh` or compiler change and an owner who needs it.
- **Pricing Gemini sessions in `session_spend.sh`.** D10 works within
  the tool's single-vendor rate table rather than extending it; a
  cross-vendor pricer is a separate issue if the presenter wants one.

## Inputs

- `intent/43-harness-agnostic-launch/spec.md` D3, D5, D8, D9, D18, D19
  and PR #60 — the launch table, the antigravity target layout, the
  sidecar model, and the smoke test this issue re-points.
- `intent/2-config/spec.md` D1–D4 — the three config axes, the
  vendor-string rule, sub-agents carrying no pin, and the two-reviewer
  constraint.
- `personas/lifecycle.json` — the ladder, and the statement that
  `maintain` has no rung.
- `config/tools.yaml` — the `delegate` → `manage_subagents` mapping and
  its inline record that an unrecognised tool name is a hard error
  (agy 1.1.25, #43 smoke run).
- `runs/2026-09-03_agy-headless/findings.md` Q1b, Q5, Q7 — the
  `model:` key voiding an agent, the `usage` object in the JSON output,
  and why identity is never checked with `gh api user`.
- `scripts/ops/session_spend.sh` header — the Anthropic rate table, the
  `UNPRICED` behaviour, and the two numbers `--check` reports.
- `intent/25-execution-model/spec.md` D19 — the v1 placements, and
  `cassandra` having no entry.
- `scripts/auth/app_manifests.yaml` — `odyssey` and `cassandra` at
  `issues: write`; `daedalus`, `argus`, `atlas` at `issues: read`
  pending #47.
- #12 (tracker, Rung 2), #2, #11, #36, #43, #47.
