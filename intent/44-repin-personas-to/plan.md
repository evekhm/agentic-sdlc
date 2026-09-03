# Plan: repin odyssey and cassandra to antigravity

**Issue:** #44 · **Spec:** spec.md (Approved, D1–D16) · **Author:**
daedalus (`evekhm-daedalus-app[bot]`)

Nine tasks. Each names the files it touches, the Decision rows it
satisfies, and the check that proves it.

**Pinned input.** Base `ba654b3` on `athena/44-repin-personas-to`
(PR #62), which sits on `odyssey/43-harness-agnostic-launch` @
`6cd3a53` (PR #60). PR #60 is taking review fixes on its own branch
while this plan is written (F1 binary preflight, F3 `smoke_launch.sh`
minting in-script instead of shelling out to a wrapper, F4 mode-bit
guard, F6 `work.md` frontmatter). **This plan therefore cites
functions, not line numbers**, and every task that edits a #43 file
begins by re-reading that file at the implementing SHA. The
implementer rebases onto whatever `athena/44-repin-personas-to`
resolves to at dispatch time and records that SHA in the PR body.

**Order.** T1 and T2 are **one commit** (D5) and come first, because
every later task runs against a tree where the pins and the compiled
targets already agree. T3 needs T1 only. T4 needs T1+T2 (it edits the
launch gate whose arms the pins decide). T5 is T4's acceptance run and
cannot precede it. T6 is independent of T4/T5 and may run any time
after T2. T7 describes what T4 built, so it is written after T4. T8's
*before* half reads transcripts that already exist and may be taken
first; its *after* half needs T5. T9 is the assembly pass and is last.

    T1 ─┐
        ├─(one commit)─→ T3 ─┐
    T2 ─┘                    ├─→ T4 → T5 ─┐
                             └─→ T6       ├─→ T7 → T9
                    T8a (any time) ───────┘   T8b (after T5)

**Five probes.** Each gates a task, is cheap, and carries the branch
to take on either outcome. P1 and P2 gate T5, P3 gates T6, P4 gates
T8, P5 gates T4. Every probe's raw output goes in the run folder
`runs/<YYYY-MM-DD>_44-repin-cost/` (D10's folder; one folder for the
issue, not one per probe) and is cited in the PR body.

**Contract tests.** Per the #36 and #43 precedent this plan specifies
each task's checks inside the task; they are run or written by the
implementer with the change, not committed ahead of it. No
contract-writer sub-agent was dispatched, for the same reason #43's
plan gave: five of the nine tasks are proved by a live launch or a
deterministic script that already exists, not by a new unit test.

**Nothing outside the spec's file set.** The tasks below touch exactly
`config/deployments.yaml`, the six compiled-target paths,
`scripts/ops/smoke_launch.sh`, `docs/SPEC.md`, and — by one recorded
reading (R2) — `scripts/ops/tests/work_test.sh`. `personas/**`,
`config/model_tiers.yaml`, `config/tools.yaml`,
`personas/lifecycle.json`, `scripts/ops/work.sh`,
`config/execution.yaml`, `CLAUDE.md` and
`scripts/auth/app_manifests.yaml` are not edited; T9 asserts it.

---

## T1 · `config/deployments.yaml` — the two pins and the reviewer comment — D1, D2

Two value edits inside the `personas:` block:

```yaml
  odyssey:   { harness: antigravity }
  cassandra: { harness: antigravity }
```

No other line of the `personas:` block moves — `athena`, `daedalus`,
`argus`, `atlas` are byte-identical after the edit (D1's after column).

One comment added **immediately above `constraints:`**, before the
existing comment inside that block (which explains what the constraint
is; this one explains why the pins under it may not move). Proposed
text, exact wording overrulable at the merge gate:

```yaml
# After #44, `argus` is the LAST persona pinned to a non-Gemini
# family. `atlas` is on antigravity, so repinning `argus` — or
# repinning "everything else for price" — violates the
# distinct_model_families constraint below (#2 D4) with a one-line
# edit and, until #6 automates the check, with no error. Move
# `atlas` off antigravity in the same edit, or do not move `argus`.
```

A vendor-family word (`Gemini`) in this file is allowed: the sanitize
gate's `vendor` rule matches only paths under `personas/` (the
`personas/*)` case arm in `scripts/ci/sanitize_check.sh`), and `config/`
is by #2 D2 the layer where vendor strings belong.

**Proves it (Acceptance 1, 2).** `git diff config/deployments.yaml`
shows exactly two changed `harness:` values and one added comment
block; `grep -c 'harness: antigravity' config/deployments.yaml` is 4
and `grep -c 'harness: claude-code'` is 2;
`bash scripts/ci/sanitize_check.sh` exits 0 and
`git diff scripts/ci/sanitize_allowlist.txt` is empty.

**Do not commit T1 alone** — see T2.

## T2 · the rebuild — `.claude/agents/**`, `.agents/agents/**` — D4, D5, D11

`python3 scripts/sync_agents.py`, never a hand-edit. Six target paths
move and no seventh:

```text
added    .agents/agents/odyssey/agent.md
added    .agents/agents/odyssey/agent.json
added    .agents/agents/cassandra/agent.md
added    .agents/agents/cassandra/agent.json
deleted  .claude/agents/odyssey.md
deleted  .claude/agents/cassandra.md
```

The deletions are the compiler's, not a `git rm`: both files carry the
generated marker, so `check()`/`write()`'s stale set prunes them once
`Resolver.harness_for` stops returning `claude-code` for those two
names. The five sub-agent targets (`coder`, `contract-writer`,
`mechanic`, `explorer`, `scanner`) are `kind: subagent`, for which
`harness_for` returns **both** harnesses regardless of any persona
pin, so none of them changes (D5, #2 D3).

`git commit` this together with T1. A tree in which
`deployments.yaml` says `antigravity` and `.claude/agents/odyssey.md`
still exists fails `sync_agents.py --check` and makes `work.sh`
preflight a target that is not there (#43 D3, exit 1) — a state no
bisect, no CI run and no cherry-pick may land on (D5).

**Proves it (Acceptance 4, 5, 12).** All of these, pasted into the PR
body:

```bash
python3 scripts/sync_agents.py --check            # exit 0
python3 scripts/sync_agents.py --verify           # exit 0
bash    scripts/ci/compiler_roundtrip.sh          # exit 0
git show --stat <pin-commit>                      # 7 paths, exactly
jq -r .model .agents/agents/odyssey/agent.json    # gemini-3.7-flash-high
jq -r .model .agents/agents/cassandra/agent.json  # gemini-3.7-flash-medium
grep -c '^model:' .agents/agents/odyssey/agent.md    # 0
grep -c '^model:' .agents/agents/cassandra/agent.md  # 0
jq -r .model .agents/agents/coder/agent.json      # gemini-3.7-flash-high (unchanged)
grep -c 'model: claude-sonnet-5' .claude/agents/coder.md  # 1 (unchanged)
git diff CLAUDE.md                                # empty (D11)
```

`git show --stat` must list `config/deployments.yaml` plus the six
target paths and nothing else. If it lists a sub-agent target, stop:
either a persona source changed (it must not have) or `harness_for`
does not behave as recorded here, and both are findings for #44, not
things to commit.

**Mechanic-tier task.** Fully specified, no decision: run the
compiler, run the three gates, run the ten assertions, report the
output verbatim.

## T3 · the #2 D4 resolution, performed and recorded — D3

No file changes. The check is a *resolution*, and D3 requires it be
run even though both of its inputs are byte-identical before and
after — "the inputs did not change" is a claim about the diff, and the
diff is what acceptance reads.

Run this from the repository root after T1+T2 and paste its output.
It reads the reviewer list out of `config/deployments.yaml` rather
than hard-coding `[argus, atlas]`, so a later edit to that list is
caught rather than assumed:

```bash
#!/usr/bin/env bash
# D3: resolve each distinct_model_families reviewer to its REVIEW model
# and assert the two vendor families differ. Exit 1 on violation.
set -euo pipefail
D=config/deployments.yaml; M=config/model_tiers.yaml

reviewers=$(sed -n 's/^ *distinct_model_families: *\[\(.*\)\].*/\1/p' "$D" \
            | tr -d ' ' | tr ',' ' ')
[ -n "$reviewers" ] || { echo "no distinct_model_families list"; exit 1; }

harness_of() { sed -n "s/^  $1: *{ *harness: *\([a-z-]*\).*/\1/p" "$D"; }
review_of()  { sed -n "/^  $1:\$/,/^  [a-z]/p" "$M" \
                 | sed -n 's/^ *REVIEW: *\([A-Za-z0-9.-]*\).*/\1/p'; }
family_of()  { case "$1" in gemini*) echo gemini ;; \
                            opus|haiku|claude*|sonnet*) echo claude ;; \
                            *) echo "UNKNOWN:$1" ;; esac; }

fams=""
for r in $reviewers; do
  h=$(harness_of "$r"); m=$(review_of "$h"); f=$(family_of "$m")
  [ -n "$h" ] && [ -n "$m" ] || { echo "unresolved: $r"; exit 1; }
  printf '%-10s -> %-12s -> %-22s (%s)\n' "$r" "$h" "$m" "$f"
  fams="$fams $f"
done
case "$fams" in *UNKNOWN*) echo "unclassified model family"; exit 1 ;; esac
u=$(printf '%s\n' $fams | sort -u | wc -l); n=$(printf '%s\n' $fams | wc -l)
[ "$u" = "$n" ] || { echo "VIOLATION of #2 D4: families collide:$fams"; exit 1; }
echo "OK: #2 D4 holds — $n reviewers, $u distinct families"
```

Expected output, which is the record D3 asks for:

```text
argus      -> claude-code  -> opus                   (claude)
atlas      -> antigravity  -> gemini-3.1-pro-high    (gemini)
OK: #2 D4 holds — 2 reviewers, 2 distinct families
```

`REVIEW` and only `REVIEW`: `cassandra`'s `escalation_tier: REVIEW`
resolving to `gemini-3.1-pro-high` after the move does not enter this
check, because the list is a list of *personas* and an escalation tier
is not one (D3).

This snippet is **not committed**. Automating the check is #6's; the
spec's file set does not include a CI script, and adding a permanent
gate here would be building #6 inside #44. It lives in this plan so it
is reproducible, and its output lives in the PR body, the run folder,
and the #44 comment.

**Proves it (Acceptance 3).** The four resolved values above, plus
`git diff config/model_tiers.yaml` empty, plus `git diff
config/deployments.yaml | grep -c '^[+-].*harness:'` equal to 4 (two
`-` lines and two `+` lines, i.e. exactly two pins moved).

**Mechanic-tier task.** Run it, paste it.

## T4 · `scripts/ops/smoke_launch.sh` — the arms follow the pins — D7, D14

### P5 (first) — re-read the script at the implementing SHA

#60's review fixes are landing on `odyssey/43-harness-agnostic-launch`
while this plan is written; F3 in particular replaces the wrapper-based
housekeeping calls with an in-script mint. Before editing, read the
whole script and locate: `banner`, `relabel`, `launch`,
`check_local_artifact`, `check_pushed_artifact`, `count_comments`,
`check_token`, `check_claim`, and the scratch-issue body writer.

- **If housekeeping now mints in-script:** the arm swap touches only
  the two arm blocks, the errand body, and the `check_claim` call
  sites. The auth path is not this issue's and must not be edited.
- **If `check_claim`'s shape changed:** preserve its behaviour exactly
  — a 403 is *tolerated* and prints `BLOCKED ON #47`, never asserted
  as "must be 403" (#43 D19's own testable property is that the line
  disappears when #47 lands **with no edit to the script**). Only its
  argument changes, to `daedalus`.

### The change

Today: `run 1 · claude-code · odyssey` (relabels `status:implementing`,
local artifact `runs/smoke-$ISSUE/odyssey.md`, comment count) and
`run 2 · antigravity · daedalus` (relabels `status:build`, deletes the
stale smoke branch, pushed artifact `SMOKE-$ISSUE.md`). Both arms end
with a `check_claim` for their own persona.

After (D7):

| | run 1 | run 2 |
|---|---|---|
| banner | `run 1 · claude-code · athena · #$ISSUE` | `run 2 · antigravity · odyssey · #$ISSUE` |
| relabel | `status:planning` | `status:implementing` |
| launch | `--as athena` | `--as odyssey` |
| artifact | local `runs/smoke-$ISSUE/athena.md` | pushed `SMOKE-$ISSUE.md` |
| identity observable | newest comment authored by `evekhm-athena-app[bot]` | commit authored by `evekhm-odyssey-app[bot]` |
| branch cleaned first | — | `odyssey/$ISSUE-<slug>` |

Five points where a mechanical swap goes wrong:

1. **The relabel targets must move with the arms**, or `work.sh`
   refuses at refusal (f): `status:planning` resolves to stage `plan`,
   whose only owner in `personas/athena.yaml` is `athena`;
   `status:implementing` resolves to `implement`, whose only owner is
   `odyssey`. Both are single-owner rungs, so neither arm hits the
   multi-owner early return.
2. **The branch `work.sh` derives moves with the persona.** It is
   `<persona>/<n>-<slug>`, so run 2's push target becomes
   `odyssey/$ISSUE-<slug>`, not `daedalus/...`. The stale-branch delete
   before run 2 and the contents-API read of `SMOKE-$ISSUE.md` after it
   must both name the new branch. `personas/odyssey.yaml`'s authority
   is `branch:odyssey/*`, so the push is inside its bounds.
3. **The errand text lives in the scratch issue's body, which this
   script writes** (#43 T11's amendment: `work.sh` has exactly one
   prompt literal for both harnesses, so a smoke test needing a second
   one would be testing something `work.sh` does not do). Rewrite the
   body to name `athena` and `odyssey` and to ask for the right
   artifact per arm — a written `runs/smoke-$ISSUE/athena.md` plus a
   comment for run 1; a committed and pushed `SMOKE-$ISSUE.md` for
   run 2. Writing the body is what makes a re-run identical to the
   first run; do not hand-edit the scratch issue instead.
4. **`check_claim` leaves the arms entirely** (D14). Delete both
   per-arm calls and add exactly one `check_claim daedalus` **outside
   both arms**, after run 2 and before the summary: one API call, one
   mint, no launch, no model tokens. Both new arm personas carry
   `issues: write`, so keeping their per-arm calls would make every
   `check_claim` pass and the string `BLOCKED ON #47` would vanish —
   for a reason that has nothing to do with #47 being granted, which
   is precisely the falsification D14 exists to prevent. See R1.
5. **The script's own housekeeping identity stays `odyssey`** — body
   write, relabel, branch delete, comment counting. Its App keeps
   `issues: write` and `contents: write` whatever harness runs it, and
   nothing about housekeeping depends on the pin.

**Proves it (Acceptance 6, 8).** `bash -n scripts/ops/smoke_launch.sh`;
`grep -c 'check_claim' scripts/ops/smoke_launch.sh` counts one
definition and one call; `grep -n 'run 1 ·\|run 2 ·'` shows the two
banners above. The live assertions are T5.

## T5 · the smoke run — the `tools:` block proved by launching — D6, D7

`scripts/ops/smoke_launch.sh <scratch-issue>` against a live scratch
issue. This is the only acceptance D6 accepts: an unrecognised name in
an `agent.md` `tools:` block is a **hard** error on this harness — exit
1, `status: "ERROR"`, zero tokens, no session at all — recorded inline
in `config/tools.yaml` from #43's smoke run (agy 1.1.25). Reading the
file proves nothing; both moved personas carry `delegate`, which is
the capability that was unlaunchable until that one line changed.

Expected resolved tool lists (from `config/tools.yaml`, for comparison
if P1 branch (b) fires): `odyssey` → `view_file, grep_search,
find_by_name, write_to_file, replace_file_content, run_command,
manage_subagents`; `cassandra` → the same minus `write_to_file` and
`replace_file_content` (its source declares no `write_repo`).

### P1 (first) — did `agy` load the persona, or fall back to the stock agent?

Both failure modes are silent at the process boundary
(`runs/2026-09-03_agy-headless/findings.md` Q1b, Q4: an unknown agent
exits 0 and answers normally). Three signals, all recorded:

- `jq -r .status` on the run's JSON is `SUCCESS`, not `ERROR`.
- the input-token count from `usage` (see P2) is in the *loaded* range,
  not the ~19k stock range measured for a `--add-dir` run with no
  persona.
- `grep 'Agent "odyssey" not found' ~/.gemini/antigravity-cli/cli.log`
  finds nothing (that warning is written to the log only — never to
  stdout or stderr, and the exit code stays 0).

Branches:

- **(a) all three clean** → D6 is satisfied; record the numbers.
- **(b) `status: "ERROR"`, zero tokens, exit 1** → an unrecognised
  `tools:` name. Diff `odyssey`'s emitted `tools:` list against
  `config/tools.yaml`'s `antigravity` column, name the offending token
  in a comment on #44, and **stop**. The fix is a `config/tools.yaml`
  line, a file this spec lists as deliberately not touched, so it is a
  spec amendment at the merge gate, not a silent edit.
- **(c) `not found` in the log, or a stock-shaped answer at stock token
  volume** → the frontmatter is malformed, not the tools. Re-run
  `sync_agents.py --verify`, then diff `.agents/agents/odyssey/agent.md`'s
  frontmatter against `.agents/agents/daedalus/agent.md`'s, which is
  known to load. Fix belongs to the compiler (#43's T1), report on #44.

### P2 (first) — the `usage` object's key names

findings Q5 records that `--output-format json` returns
`conversation_id, status, response, duration_seconds, num_turns,
usage` but does not record `usage`'s shape. Every "non-zero input
token count" assertion in this plan (Acceptance 7 and 9) needs one
field name. On the first launch, run `jq '.usage' <the captured json>`,
write the key into the run folder, and use it consistently.

- **If `usage` carries an input-token field** → use it for T5 and T6.
- **If `usage` is absent or empty on this agy build** → the token half
  of Acceptance 7/9 is unmeasurable; the observable degrades to the
  `cli.log` grep plus a persona-shaped answer, and the PR body says
  plainly that the token count could not be taken and why. Do not
  substitute `num_turns` for it.

**Proves it (Acceptance 6, 7, 8).** One run of the script, exit 0, with
its output pasted: both banners as in T4's table; per arm the exit
code, the artifact, and the author (`evekhm-athena-app[bot]` on the
comment, `evekhm-odyssey-app[bot]` on the commit); exactly one
`BLOCKED ON #47` line, from the standalone `check_claim daedalus`;
and P1's three signals for the antigravity arm. Identity is never
checked with `gh api user` — an App token gets 403 there (findings Q7);
the token-side check is `GET /installation/repositories`, which the
script already does in `check_token`.

## T6 · `cassandra` — one positive harness check, one negative dispatch assertion — D8, D15

`cassandra` is repinned but **not dispatchable**, and the reason is
structural rather than a gap in this issue: her only stage is
`maintain`, and `personas/lifecycle.json` states that `intake`,
`deploy` and `maintain` "are stage-enum values with no rung and are
absent by construction". No `status:*` label resolves to `maintain`,
so `work.sh <n> --as cassandra` refuses on every issue in the
repository — before this change and after it. Both halves are
asserted, because a future session must be able to tell "never proven"
from "proven not to apply" (D15).

### Positive — the line `work.sh` would build for her, run by hand

Exactly what `launch_argv` would produce, with `model_of` and
`timeout_mins_of` resolved by hand from the committed tree
(`gemini-3.7-flash-medium` from the T2 sidecar; `timeout_mins: 20`
from `personas/cassandra.yaml`):

```bash
agy -p '<the single prompt literal work.sh builds — copy it verbatim
        out of scripts/ops/work.sh, do not retype it>' \
    --agent cassandra \
    --add-dir <absolute repo root> \
    --model gemini-3.7-flash-medium \
    --output-format json \
    --print-timeout 20m
```

### P3 (first) — does that model id load this persona?

`gemini-3.7-flash-medium` is present in `agy models` (checked
2026-09-03 while planning), so the id is not the risk; `cassandra`'s
`tools:` block is, and it has never been launched — the id appears
elsewhere only as a compile-time string in the throwaway persona
`compiler_roundtrip.sh` builds. Apply P1's three signals with
`cassandra` substituted, and P1's branches (b) and (c) verbatim.

Accept: `status: "SUCCESS"`, non-zero input tokens (P2's field), and
an answer that shows the persona loaded — cassandra's role text is
distinctive (the 1σ/2σ/3σ proportional-response ladder), so an answer
that describes it is persona-shaped and the stock agent's is not.

### Negative — the refusal is asserted, and asserts its own cause

One new scenario in `scripts/ops/tests/work_test.sh`, using the
existing harness (`run()` with the stubs already on PATH; no
`fixture_tree` needed, because the refusal happens before any launch
and therefore before anything is minted):

- `--as cassandra` against a stubbed issue carrying any single
  `status:*` label exits **2**;
- the message matches the stage-owner refusal shape `does not own
  stage <stage>` and names that stage's real owners;
- the message contains **neither** `antigravity` nor `claude-code`
  nor `harness` — proving the refusal comes from the stage machinery
  (`maintain` has no rung) and not from the repin;
- `$WRITES`, `$LAUNCHES` and `$MINTS` are all empty.

Repeat the exit-2 assertion for a second `status:*` label, so the
scenario shows the refusal is not specific to one rung.

**Proves it (Acceptance 9).** The hand-run JSON (pasted, with the
prompt elided if long but the argv shown in full) plus
`bash scripts/ops/tests/work_test.sh` exit 0 with the new scenario
named in its output.

**Note for the PR body and the #44 handoff (D8).** Both must say, in
so many words, that `cassandra` is repinned but not dispatchable, and
name **#11** as the issue that changes it. A handoff that leaves this
out is the failure D8 describes.

## T7 · `docs/SPEC.md` — one upserted entry — D9

One entry, `ops.dispatch`, one sentence — its last one, the `Tests:`
sentence. It currently reads:

> Tests: `scripts/ops/tests/work_test.sh` against stubs, and
> `scripts/ops/smoke_launch.sh <scratch-issue>` for one real launch per
> harness — three named observables each, with the claim half of the
> Antigravity run reported as `BLOCKED ON #47` until that App's
> `issues: write` permission is granted, rather than asserted to fail.

The false half after T4 is the tail: the Antigravity run is now
`odyssey`, whose App already has `issues: write`, so its claim half is
not blocked and the `#47` signal no longer rides on it. Replace with a
sentence saying: one real launch per harness — `athena` on Claude Code
and `odyssey` on Antigravity, following the pins in
`config/deployments.yaml` — three named observables each; and that the
`#47` signal is a standalone claim probe for `daedalus` outside both
runs, which launches nothing and reports `BLOCKED ON #47` until that
App's `issues: write` permission is granted, rather than asserting a
403. Keep the entry ID and keep the sentence's position; upsert, never
append (AGENTS.md, the living spec).

**Nothing else in `docs/SPEC.md` moves.** Verified statically at
`ba654b3`: `grep -n 'odyssey\|cassandra\|daedalus\|antigravity\|
claude-code' docs/SPEC.md` returns four hits, all in
`personas.sources`, `identity.bots` and `config.bindings`, and none of
them states which harness backs which persona. That is by design —
`config.bindings` describes the mechanism and deliberately does not
enumerate pins, and the review policy deliberately says which family
backs which reviewer "appears nowhere in the policy" — so the repin
adds no new SPEC statement about who runs where. Re-run that grep at
the implementing SHA and confirm it still returns only those four.

`Spec-impact: none` is **not available** to this PR: `config/` and
`scripts/` are behavior-bearing paths under `scripts/ci/spec_check.sh`
and the behaviour genuinely changes (D9).

**Proves it (Acceptance 10).** `bash scripts/ci/spec_check.sh <base>`
exits 0 *because the diff touches `docs/SPEC.md`*, not because of a
marker — confirm by checking that the PR body carries no
`Spec-impact:` line; `git diff docs/SPEC.md` is one entry.

## T8 · the cost measurement — D10, D13

Two `session_spend.sh` runs on the Claude side and `agy`'s own `usage`
on the other. **No single cross-vendor dollar figure is produced**, and
the report says why: `scripts/ops/session_spend.sh` prices Claude Code
`*.jsonl` transcripts against the Anthropic rate table and reports a
model that table does not know as unpriced by name, with its tokens
excluded from the USD columns. A "we saved $X" number spanning both
vendors would be an invention (D10).

### P4 (first) — how many attributable baseline sessions exist?

D13 makes the baseline **a named set of sessions, not a calendar
window**: the last three `odyssey` implement-stage sessions on
`claude-code` before the merge, listed by transcript id, against the
first three after. A calendar window measures how busy the week was;
this measures what a session costs.

Enumerate candidate transcripts under
`~/.claude/projects/<mangled-checkout-path>/*.jsonl` — one directory
per checkout, so a dispatch that ran in a worktree has its own — and
identify the ones that were an `odyssey` dispatch. Branches:

- **(a) three or more** → take the newest three, by transcript id.
- **(b) one or two** → take them, and state the count and the word
  *provisional* in the report. D13 authorises exactly this.
- **(c) none** → the honest before column is "no `odyssey` dispatch on
  `claude-code` was ever recorded as its own session", and the report
  gives the after column alone plus the tier bindings that would have
  applied. It does **not** divide by a week and it does not state a
  saving.

Same procedure for `cassandra` by sweep; if #11 has not given her a
cadence, the row reads "no sessions yet" (D13) — which, given D8, is
the expected outcome.

One thing the report must say out loud: on `claude-code`,
`MECHANICAL` and `IMPLEMENTATION` both bind `claude-sonnet-5`, so a
per-model row cannot separate `odyssey` from the `mechanic` sub-agent
it dispatches. The comparison survives only because D13's unit is a
*session dispatched for odyssey* — inside which the `claude-sonnet-5`
rows are odyssey plus its own sub-agents, which is exactly the cost of
running odyssey. A per-model roll-up taken across the repo instead
would be meaningless, and taking one is the mistake to avoid.

### What is taken

- **(a) before** — `scripts/ops/session_spend.sh <transcript> --check`
  over each session in P4's baseline set, recording the two numbers
  AGENTS.md requires **together** — cache hit rate
  `read/(read+write+fresh)` and tokens-per-message — plus the
  per-model USD roll-up. Either number alone hides the other.
- **(b) after** — the same command over the after set. The observable
  is that the `claude-sonnet-5` and `haiku` rows attributable to
  `odyssey` and `cassandra` fall to zero **on that harness**.
- **(c) the antigravity side** — the `usage` object from each launch's
  `--output-format json` (T5, T6, and P2's field name), recorded per
  run as **tokens**, with the GCP bill named as the authority for
  dollars. No USD column.

### Where it lands

Run folder `runs/<YYYY-MM-DD>_44-repin-cost/` per AGENTS.md — which is
gitignored, so the numbers do not survive there. They are reported in
a **comment on #44** and summarised in the PR body, and the run
folder's `findings.md` carries the disposition footnote naming that
comment:

```text
---
Disposition (YYYY-MM-DD): reported in the cost comment on #44; summarised in PR #<n>.
```

**Proves it (Acceptance 11).** The #44 comment shows, for each of
before and after, hit rate **and** tokens-per-message **and** the
per-model USD table; it shows antigravity tokens with no USD column;
the baseline is named as a session list, not a date range; and the
run folder carries the footnote above.

## T9 · assembly — one PR, and the three negative assertions — D11, D12, D16

Not a code task; the pass that makes the PR honest.

**One pull request (D12).** The pins, the rebuild, the smoke arms and
the `docs/SPEC.md` sentence ship together. Splitting them opens a
window in which `smoke_launch.sh` launches `agy` twice, prints
`run 1 · claude-code · odyssey`, asserts three observables and
**exits 0** — a green gate reporting coverage of a harness it did not
touch, while `docs/SPEC.md` states a `BLOCKED ON #47` behaviour the
script no longer has. "Config-only" (#44's own wording) survives as a
statement about the *source* layer: `personas/**` is untouched and
exactly one line of one config file decides the harness.

**The three negative assertions**, each a command whose empty output
is the evidence:

```bash
git diff <base> -- CLAUDE.md                       # empty (D11)
git diff <base> -- personas/ config/model_tiers.yaml \
    config/tools.yaml personas/lifecycle.json \
    scripts/ops/work.sh scripts/auth/app_manifests.yaml   # empty
git diff <base> -- scripts/sync_agents.py          # empty (D16)
grep -rn 'escalation_tier' scripts/                # no hit in work.sh
                                                   # or sync_agents.py (D16)
```

**D16, recorded not fixed.** `odyssey` (`escalation_tier: FRONTIER`)
and `cassandra` (`escalation_tier: REVIEW`) are the only two personas
declaring one, and this issue moves both — so this is the first time
the compiled sentence "You may escalate to the … grade only when …" is
emitted for a persona on antigravity, where it has no mechanism: `agy`
takes one `--model` fixed at launch from the sidecar, headless print
mode is the only mode #43 offers for this harness (#43 D5), and #36 D7
forbids a flag that names a model. On antigravity, *escalate* means
stop and hand the question back on the issue — which is what
`odyssey`'s role text already requires for open design questions. The
#44 handoff comment must cite this as a known consequence. No
`escalation_tier` handling is added here; fixing it means either a
model-bearing flag (forbidden) or a second tier column consulted at
launch, and both belong to whoever needs the escalation.

**The handoff owes three sentences** it is easy to drop: `cassandra`
is repinned but not dispatchable, with #11 named (D8); `escalation_tier`
is prose without a mechanism on antigravity, accepted (D16); and the
cost report is two single-vendor measurements, never one number (D10).

---

## Acceptance → task

| # | derives from | task |
|---|---|---|
| 1 | D1, D2 | T1 |
| 2 | D2 | T1 |
| 3 | D3 | T3 |
| 4 | D4 | T2 |
| 5 | D5 | T2 |
| 6 | D7 | T4, T5 |
| 7 | D6 | T5 (P1, P2) |
| 8 | D14 | T4, T5 |
| 9 | D8, D15 | T6 (P3) |
| 10 | D9 | T7 |
| 11 | D10, D13 | T8 (P4) |
| 12 | D11 | T2, T9 |
| 13 | D12 | T9 |

Every decision is reached: D1/D2 → T1; D3 → T3; D4/D5/D11 → T2 and
T9; D6 → T5; D7/D14 → T4 and T5; D8/D15 → T6; D9 → T7; D10/D13 → T8;
D12/D16 → T9.

## Probes

| # | gates | question | (a) | (b) |
|---|---|---|---|---|
| P1 | T5 | did `agy --agent odyssey` load the persona? | clean: record and proceed | `ERROR`/zero tokens → name the offending `tools:` token on #44 and stop; `not found` in `cli.log` → compiler fault, report |
| P2 | T5, T6 | what is `usage`'s input-token field? | use it for Acceptance 7 and 9 | absent → the observable degrades to the log grep plus a persona-shaped answer, said plainly in the PR |
| P3 | T6 | does `gemini-3.7-flash-medium` load `cassandra`? | `SUCCESS`, non-zero tokens, σ-ladder answer | P1's branches (b)/(c) verbatim |
| P4 | T8 | how many attributable `odyssey` baseline sessions exist? | ≥3 → newest three | 1–2 → provisional, count stated; 0 → no before column, no saving figure |
| P5 | T4 | what shape is `smoke_launch.sh` in after #60's review fixes? | in-script mint → edit only arms, errand body, `check_claim` sites | `check_claim` reshaped → preserve tolerate-403 behaviour, change only its argument |

## Readings taken

Two places where the spec admits more than one implementation and this
plan chose. Both are cheap to overrule by editing the row.

**R1. D14 removes the per-arm `check_claim` calls rather than keeping
them alongside the standalone probe.** D14's two readings are "the
arms move and `check_claim` moves with them" and "the arms move and the
`#47` probe stays"; it does not say in so many words whether the second
excludes the first. This plan reads it as exclusive: D7 enumerates
exactly three observables per arm and `check_claim` is not one of them,
D14 says the probe sits "outside both arms", and Acceptance 8 says
"exactly one `BLOCKED ON #47` line, from a **standalone**
`check_claim daedalus`". Cost of overruling: one line per arm re-added,
and the arms gain a fourth observable D7 does not name. Consequence of
this reading: after the change, nothing asserts that `athena`'s and
`odyssey`'s Apps can write the `in-progress` label — but their comment
and commit observables already prove those Apps can write.

**R2. D15's negative assertion is a committed scenario in
`scripts/ops/tests/work_test.sh`, not a hand-run recorded in the PR.**
The spec's "What is being built" block does not list that file, which
argues for a hand-run; but D15 says the refusal is *asserted*, and its
differing case is explicitly about a **future** session that
misreads the absence of coverage — which a hand-run in a closed PR
does not serve. `work_test.sh` is on neither the built list nor the
deliberately-not-touched list, and a scenario there adds no new
behaviour, only an assertion about behaviour that already exists
unchanged. Cost of overruling: delete the scenario, run the same two
commands by hand, paste them into the PR body and the #44 comment; the
observable is identical and only its durability is lost.

## Delegation

`MECHANICAL_TIER` (a `mechanic`-tier sub-agent — fully specified, no
decisions): **T2** (run the compiler, run the three gates, run the ten
assertions, report verbatim), **T3** (run the snippet, paste the
output), **T9**'s four negative-assertion commands, and the static
half of **T4** (`bash -n`, the two `grep -c` counts).

Not delegable below `IMPLEMENTATION_TIER`: **T1** (the comment's
wording is a judgment), **T4**'s edit (five ways a mechanical swap goes
wrong), **T7** (a spec sentence is a claim reviewers verify against the
diff). Not delegable at all — they read a live outcome and decide
whether it means success: **T5**, **T6**, **T8**, and every probe
branch.

## Pull request

One PR (D12) against `athena/44-repin-personas-to`, body carrying
`Closes #44`, and:

- the pin diff and the D3 resolution's four values;
- `git show --stat` of the pin+rebuild commit (seven paths);
- the T5 smoke output, with both banners, the per-arm observables, the
  single `BLOCKED ON #47` line, and P1's three signals;
- T6's hand-run `agy` argv and its JSON status, plus the sentence that
  `cassandra` is repinned but not dispatchable and #11 owns the change;
- the cost summary and a link to the #44 comment carrying the tables;
- the probe outcomes, P1–P5, each with the branch taken;
- T9's three negative assertions;
- **no** `Spec-impact:` line (D9).

Gates, all run before pushing: `python3 scripts/sync_agents.py --check`
and `--verify`, `bash scripts/ci/compiler_roundtrip.sh`,
`bash scripts/ci/sanitize_check.sh`, `bash scripts/ci/spec_check.sh
<base>`, `bash -n scripts/ops/smoke_launch.sh`, and
`bash scripts/ops/tests/work_test.sh`.
