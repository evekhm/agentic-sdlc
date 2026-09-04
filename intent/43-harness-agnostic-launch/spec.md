# Spec: harness-agnostic launch

**Issue:** #43 · **Status:** Approved (approval = merge of this PR) ·
**Author:** athena (`evekhm-athena-app[bot]`) ·
**Open questions:** none

The two questions filed on #43 were answered by measurement, not by
argument: `runs/2026-09-03_agy-headless/findings.md` (agy 1.1.24,
probed 2026-09-03). Every claim below that concerns agy's behaviour
cites a row of that file; where a behaviour was **not** measured it is
labelled *unverified* and an acceptance check is what settles it.
**Any row in this table can be overruled by editing this file at the
merge gate** — the merge is the acceptance, so an edited row is the
decision, not a comment asking for one.

D1–D6 are the launch itself, D7–D10 the compiled target, D11–D13
identity, D14–D16 the doors and the rule, D17–D19 scope and
dependencies. D20–D24 came out of the spec-adversary pass against this
draft and are marked *(adversary)*.

A row amended after approval keeps its ID and carries an **Amended
&lt;date&gt; (&lt;who&gt;, &lt;why&gt;)** note in place, quoting the clause it
replaces — so the row's history reads without a diff, and the
Decision ID a contract test cites never moves. D1 set that format
(PR #60, finding F5); D8, D11, D15, D16, D19, D23 and the "What is
being built" block follow it. A row may be amended more than once: the
notes stack in date order under the rule, newest last.

## What is being built

```text
scripts/sync_agents.py            AntigravityEmitter: agent.md + agent.json
.agents/agents/*/                 REBUILT: agent.md NEW, config.yaml and
                                  instructions.md DELETED (drift gate)
scripts/ops/work.sh               launch table, preflight, mint, two modes
scripts/auth/git-credential-persona  NEW: re-minting git credential helper
scripts/ops/smoke_launch.sh       NEW: the two-harness smoke test
.claude/commands/work.md          NEW: the thin /work door
AGENTS.md                         NEW subsection: dispatch has one door
docs/SPEC.md                      ops.dispatch reworded; personas.compile
                                  reworded; ops.identity added

config/tools.yaml                 the per-harness tool names the compiled
                                  `tools:` block renders from
scripts/ci/compiler_roundtrip.sh  the roundtrip gate, for the new
                                  antigravity layout
scripts/ops/tests/work_test.sh    the launcher's hermetic test suite

scripts/auth/mint_app_token.py    mode 100644 → 100755; no content line
                                  changes
```

**Amended 2026-09-03 (athena, round-1 review of #60: F2 and Atlas's
open item (b)).** The three paths in the second block were added
after approval; the first block is the original. PR #60
changes all three and the list omitted them, and this block plus "Not
touched, deliberately" *is* this change's declared authority — the one
the merge gate's path check reads — so a list known to be untrue turns
that check into theatre. `config/tools.yaml` in particular decides
whether an antigravity persona loads at all, which makes D7 and D8
incomplete without it. #66 (nothing verifies the tool names) stays a
separate issue: this block records what the change touched, #66 records
what nothing checks.

**Amended 2026-09-03 (athena, round-2 review of #60: R2-4 and
AT-R2-3).** `scripts/auth/mint_app_token.py` — the third block — is the
twelfth path the diff touches and the first two blocks did not name it.
The alternative both reviewers offered, a standing "modes are not
paths" convention, is rejected: the mode change is the fix for the
defect that stopped both first smoke launches, `work_test.sh` now
asserts the file's index mode, and a file that only becomes executable
is still a file this change had to touch. The round-1 rule is not
qualified a round later — a list untrue by one path is untrue, whatever
the diff column it is untrue in. Two paths stay deliberately
unlisted and are not omissions: `intent/43-harness-agnostic-launch/plan.md`
and this `spec.md`, which the implement stage's own brief (the diff, the
plan sync, the living-spec upsert) puts in the pull request by
construction.

Not touched, deliberately: `personas/**` (no persona source changes,
so no sanitize-gate surface and no new vendor string outside
`config/`), `config/deployments.yaml` (the pins #44 owns), and
`scripts/auth/app_manifests.yaml` (the permissions #47 owns).

## The launch table

One table, two harnesses, two columns. `$REPO_ROOT` is the value
`work.sh` already derives from `BASH_SOURCE` (D24), `$N` the resolved
issue number, `$P` the persona, `$T` the persona's
`limits.timeout_mins` from `personas/$P.yaml`, `$M` the resolved model
from the compiled sidecar (D9).

| harness | interactive (default) | headless (`HEADLESS=1`) |
|---|---|---|
| `claude-code` | `claude --agent $P "$PROMPT"` (foreground child, not `exec` — D15 as amended) | `claude -p "$PROMPT" --agent $P --output-format json` |
| `antigravity` | *(not offered — D5)* | `agy -p "$PROMPT" --agent $P --add-dir $REPO_ROOT --model $M --output-format json --print-timeout ${T}m` |

## Decisions

| # | Decision |
|---|---|
| D1 | **The `antigravity` row runs agy in print mode with `--add-dir "$REPO_ROOT"`, and the flag is mandatory.** Print mode ignores the working directory: without `--add-dir` the workspace is a per-conversation scratch directory the CLI creates under the user's own per-user state directory and *no repository file is opened at all* (findings Q1: strace shows none touched). With it, agy scans `$REPO_ROOT/.agents/{agents,rules,skills,workflows,…}` and loads `AGENTS.md` and `GEMINI.md` automatically (findings Q9) — which is why nothing in this spec passes the shared standards into the prompt. A nonexistent `--add-dir` path is silently ignored and exits 0 (findings Q1), so the value is always an absolute path this script already knows to exist. Testable: the launch line contains `--add-dir` with an absolute path, and the launched child's working directory is that same `$REPO_ROOT`. **Amended 2026-09-03 (odyssey, PR #60, review finding F5).** The clause originally read *"a grep of `work.sh` finds no `cd` before the launch"*, on the assumption that `--add-dir` pinned the workspace for both harnesses. The smoke run falsified it: `claude-code` has no `--add-dir` and takes `$PWD` as the project, so `work.sh` invoked by absolute path from a sibling clone resolved *this* checkout's personas, labels and targets and then handed the session the *other* one — which reported `WORK-RESULT: ok` having done the errand in the wrong working tree. `work.sh` therefore `cd`s to `$REPO_ROOT` immediately before the launch. The `cd` target is the same value `--add-dir` receives, so D24's intent — one checkout reads the labels and edits the tree — is strengthened rather than broken; what the original clause defended against was a `cd` to somewhere *else*, and that remains forbidden. |
| D2 | **The prompt is a fixed two-sentence string, identical on both harnesses, and a bare `#<n>` is never sent.** `#` is not a sigil to either harness: it arrives literally, and a bare `#43` handed to an agent that did not load ran 173 s, consumed 160,818 input tokens, hit the print timeout and exited 1 (findings Q6). The string is: `Work issue #<n> in this repository. Follow your persona instructions and the repository's AGENTS.md; when you finish or refuse, print one final line WORK-RESULT: <ok|refused|blocked> #<n> <one-line reason>.` It names a number and nothing else — no stage, folder, artifact, branch or model — so #36 D7 holds at the prompt boundary as well as at argv. Testable: exactly one prompt string literal exists in `work.sh`; it contains `#$ISSUE` and none of the words `stage`, `plan`, `spec`, `branch`. |
| D3 | **`work.sh` preflights that the launched persona's compiled target exists, and a missing target is exit 1.** For `antigravity` the target is `.agents/agents/$P/agent.md`, for `claude-code` `.claude/agents/$P.md`. Grounds: agy's failure mode for a missing agent is *silent* — it falls back to the stock agent, prints nothing on stdout or stderr, and exits 0 (findings Q1b, Q4), so the only cheap place to notice is before the process starts. Exit 1, not 2: a persona pinned to a harness whose target was never compiled is a broken deployment, the same class as `deployments.yaml` having no pin for it (#36, D8). Testable: with `.agents/agents/daedalus/agent.md` renamed away, `work.sh <n>` for a daedalus stage exits 1 with a message naming the missing path, and no model call is made. |
| D4 | **`work.sh` does not read agy's log file.** The persona-not-loaded warning exists only in the CLI's own rotating log file, inside its per-user state directory (findings Q1) — a machine-local location that does not exist on a runner and that a script could only reach by naming a home directory. D3's preflight covers the one cause that log line has — a missing `agent.md` — and D10 removes the other (a `model:` key). Testable: `scripts/ops/work.sh` opens no log file, and the sanitize gate's `home` rule passes on it with no allowlist entry. |
| D5 | **`antigravity` is launched headless always; `claude-code` is interactive by default and headless under `HEADLESS=1`.** Only print mode was measured (findings, all rows); an interactive `agy` session is untested and is not what a dispatcher needs — the presenter drives interactive antigravity work in the IDE, not through `work.sh`. `HEADLESS` is an environment variable rather than a flag because #36 D7 reserves argv for the number and `--as`, and `DRY_RUN` is the standing precedent for a mode. Testable: `HEADLESS=1 DRY_RUN=1 work.sh <n>` prints the `-p` form for a claude-code persona; unset, it prints the interactive form; for an antigravity persona both print the same `-p` form. |
| D6 | **Timeouts come from the persona source, doubly applied.** `--print-timeout ${T}m` where `$T` is `limits.timeout_mins` from `personas/$P.yaml`, and the whole child is wrapped in `timeout $((T * 60 + 60))` so a harness that ignores its own flag still ends. Grounds: a print-mode timeout is one of only two non-zero exits agy produces (findings Q3), so it is the mechanism that must be tuned rather than worked around; the extra minute is for the harness's own teardown. Testable: `DRY_RUN=1` for daedalus (`timeout_mins: 45`, antigravity) prints `--print-timeout 45m` inside a `timeout 2760` wrapper; `HEADLESS=1 DRY_RUN=1` for odyssey (`timeout_mins: 90`, claude-code) prints a `timeout 5460` wrapper and no `--print-timeout`, which that harness does not take. |
| D7 | **The compiled antigravity target changes to `.agents/agents/<name>/agent.md`, and #43 absorbs the change rather than filing it as a defect against #5.** agy 1.1.24 loads `agent.md` with YAML frontmatter; an A/B in a throwaway workspace showed `agent.md` with `name` + `description` loads the persona (6,482 input tokens, secret word returned) while the repository's `agent.json` + `instructions.md` layout does not (12,881 tokens, stock agent) — findings Q1b. Absorbed here, not filed, because the defect and this issue have the *same* single observable: a `work.sh` antigravity row shipped without it launches the stock agent and exits 0, which is exactly the silent success #43 exists to prevent. Splitting them would put a launch row and the thing that makes it real in two issues that must merge together anyway, and #5 is closed on a "done when" that this measurement retroactively falsifies — reopening a closed rung to re-land it is bookkeeping, not work. Testable: `scripts/sync_agents.py --check` passes on a tree containing `agent.md` and no `config.yaml`/`instructions.md`; the roundtrip gate (`scripts/ci/compiler_roundtrip.sh`) is a zero diff. |
| D8 | **`agent.md`'s frontmatter carries `name`, `description` and `tools`, and never `model`.** All three keys were measured to work; `model: gemini-3.1-pro-high` — a valid id per `agy models` — voids the whole agent, which then silently falls back (findings Q1b). The generated-file marker rides as a YAML comment inside the frontmatter, mirroring `.claude/agents/<name>.md`; a comment is not a key. The body below the frontmatter is the same rendered persona body the other emitter uses, and a loaded persona *replaces* the default system prompt (findings Q1b). Testable: no `.agents/agents/*/agent.md` contains a line matching `^model:`; each contains the marker comment; `agy` loads each one (proved by D19's smoke test, not by inspection). **Amended 2026-09-03 (athena, round-2 review of #60: AT-4).** The third clause read *"`agy` loads each one (proved by D19's smoke test, not by inspection)"*. It is unmet by construction rather than by a bug, and no implementation of the smoke as specified could meet it: D19's script writes the errand — create the file, set the commit author, push the branch, print `WORK-RESULT: ok` — into the scratch **issue body** (`smoke_launch.sh:107-143`), because D2 allows one prompt literal and the body is the only place left. agy's stock fallback agent then reads the same issue, in the same `--add-dir` tree, with the same minted token and the same credential helper, and satisfies all three antigravity observables; the third one, the commit's author name, is a string that same body dictates, so it is self-asserted, not authenticated. The rule is unchanged — the frontmatter keys and the ban on `model:` stand — and two facts that were conflated in one clause are separated. **(a) That this *layout* loads at all** is settled by measurement outside this spec's own test: findings Q1b A/B'd `agent.md` with `name`+`description` (6,482 input tokens, secret word returned) against `agent.json`+`instructions.md` (12,881 tokens, stock agent). **(b) That the *shipped target of the persona actually launched* loaded on a real `work.sh` run** is what D19's smoke must show, and only an observable whose instruction *and* value live in the loaded system prompt can show it — D19 as amended adds exactly that one. Testable, amended: no `.agents/agents/*/agent.md` contains a line matching `^model:`; each contains the marker comment; the three-key frontmatter loads (findings Q1b); and the launched persona's target is proved loaded by D19's persona-only marker observable — never by an exit code, a pushed file, or a commit author the errand itself named. |
| D9 | **The persona's model pin reaches agy as `--model`, read from a machine-readable sidecar `.agents/agents/<name>/agent.json` that the compiler emits and agy ignores.** The sidecar carries exactly what `agent.md` cannot: `model` (the tier already resolved through `config/model_tiers.yaml`) and `subagent`. `work.sh` reads `.model` with `jq`, which it already depends on. The alternative — re-resolving `personas/<p>.yaml`'s `tier` against `model_tiers.yaml` in awk inside `work.sh` — was rejected: tier→model resolution is the compiler's one job and a second implementation of it in bash is a second source of truth that drifts silently. Limits stay in `personas/<p>.yaml` (D6) rather than in the sidecar, so each fact has one home: source facts from the source, resolved facts from the compiler. Testable: `jq -r .model .agents/agents/daedalus/agent.json` equals `config/model_tiers.yaml`'s `antigravity.FRONTIER`; changing one line of `model_tiers.yaml` and rebuilding changes the launched `--model` and nothing else (#25, D18). |
| D10 | **`config.yaml` and `instructions.md` are deleted from the antigravity target; the drift gate reads the two new files.** Three files where agy reads one is three chances to drift. `sync_agents.py`'s verifier (its `--check` path) moves its `agent.json` assertions to the reduced sidecar and adds the `agent.md` frontmatter/body assertions. `TARGET_DIRS` is unchanged: `.agents/agents` is already covered, so the new layout inherits the gate. Testable: after a rebuild, `.agents/agents/<name>/` contains exactly `agent.md` and `agent.json`; a hand-edit to either fails `sync_agents.py --check`. |
| D11 | **`work.sh` mints the owning persona's App token immediately before the launch, once, only for the persona actually launched, and never under `DRY_RUN`.** The command is `scripts/auth/mint_app_token.py "$P"`; the result is captured into a shell variable and reaches the child as a variable-assignment prefix (`GH_TOKEN="$tok" exec …`), never as an argument, never through a file, never echoed. Minting is the last step before the launch so that a run which prints and launches nothing — `DRY_RUN=1`, a two-owner stage (#2 D4), a harness with no row — performs no token exchange and leaves no live credential behind. `DRY_RUN=1` prints one line, `identity: evekhm-<persona>-app[bot] (token minted at launch; not printed)`. Testable: `DRY_RUN=1` makes no network call to `api.github.com/app/installations` and its output contains no 40-character token-shaped string; a two-owner stage likewise. **Amended 2026-09-03 (athena, round-1 review of #60: AT-2).** The third clause read *"`set -x` output of a real launch contains no token"* — a claim about the code that nothing ran, and it is false as written: bash's xtrace expands both `tok="$(mint…)"` and the `GH_TOKEN="$tok" …` assignment prefix, so `bash -x scripts/ops/work.sh <n>` writes the live installation token to stderr, and a Claude Code session captures tool stderr verbatim into an on-disk transcript — a file and a log, the two places this row says the token never reaches. The rule is unchanged; the clause becomes a scenario. Testable, concretely: `scripts/ops/tests/work_test.sh` gains one hermetic scenario that runs the fixture tree's launch under `bash -x` with the mint stub returning the literal `stub-token-for-<persona>`, captures **stdout and stderr together**, and asserts `grep -q 'stub-token-for-'` over the captured text **fails**; the scenario runs on the headless row and on the interactive row (which, under D15 as amended, now returns rather than being `exec`'d away, so both need the guard). The scenario is written first and fails on the code as it stands. Whatever makes it pass must suppress xtrace only for the region between the mint and the launch and restore the caller's setting afterwards — `set -x` stays in force everywhere else, and the suppression is a no-op when xtrace is off. |
| D12 | **A failed mint is fatal — exit 1 — and the child never inherits an ambient `GH_TOKEN`.** `work.sh` overwrites `GH_TOKEN` and `GITHUB_TOKEN` in the child's environment with the minted value and with nothing else. Grounds: the alternative, warning and falling back to the operator's ambient credential, produces precisely the bug this issue exists to fix — a session that posts as the operator while everyone believes a persona ran (#43, Problem 2; observed on #25/PR #46, 2026-09-03). A launch that cannot be attributed is not a launch. Testable: with the private key removed from the environment and from the key directory, `work.sh <n>` exits 1, names the persona whose token could not be minted, and starts no child; with an ambient `GH_TOKEN` exported and a successful mint, the child's `GH_TOKEN` is the minted one. |
| D13 | **`git push` gets a re-minting credential helper, `gh` gets the snapshot, and both are installed through the child's environment only.** `git` does not read `GH_TOKEN`, and an installation token lives ~1 hour while `odyssey`'s cap is 90 minutes — so a snapshot alone would fail a long session mid-push. `work.sh` sets `GIT_CONFIG_COUNT` / `GIT_CONFIG_KEY_n` / `GIT_CONFIG_VALUE_n` in the child to (a) point `credential.https://github.com.helper` at `scripts/auth/git-credential-persona <persona>`, which on `get` prints `username=x-access-token` and a *freshly minted* password, and (b) rewrite `git@github.com:` to `https://github.com/` via `insteadOf`, because this repository's `origin` is SSH and an SSH remote would bypass the helper entirely. Nothing is written to `.git/config`, so a crashed session leaves no credential configuration behind. `gh` keeps the ~1-hour snapshot; a session that outlives it re-mints in-band with the same script. Testable: a child launched by `work.sh` can `git push` to an `athena/*` branch with no ambient credential helper on PATH; `git config --list` in the parent shell after the run shows no `credential.https://github.com.helper`; the helper script is invoked twice in a two-push session and mints twice. |
| D14 | **A launched persona's refusal is observed in-band and mapped to exit 2; agy's `status` maps only to exit 1.** Neither harness signals a model-level refusal at the process boundary: a prompt-forced `REFUSED: …` and an `ERROR: cannot proceed` both exit 0 with `status: "SUCCESS"`, and an unknown `--agent` answers normally and exits 0 (findings Q3, Q4). So in headless mode `work.sh` parses the JSON `.response` (or `.result.status` / final `result` event for `stream-json`) for D2's `WORK-RESULT:` line and maps: `refused` or `blocked` → exit 2, matching #36 D8's existing meaning that 2 is *"not worked, by design"*; `ok` → exit 0; `status: "ERROR"` (timeout, crash) → exit 1; **`SUCCESS` with no `WORK-RESULT` line → exit 1**, because a launcher that returns 0 for an outcome it could not observe is lying, and a session that ran out of turns leaves exactly that trace. The durable record stays the tracker — the persona's claim, artifact and handoff comment — and the exit code is only its shadow. Testable: four fixtures of a stubbed harness reproduce the four exits; a real refusal on a `hold`-labelled scratch issue exits 2 and leaves no `in-progress` label. |
| D15 | **Interactive `claude-code` keeps `exec` and keeps the harness's own exit code.** D14's mapping applies to headless launches only; there is no stdout to parse in an interactive session, and `exec` is what makes the operator's terminal *be* the session. Testable: `work.sh <n>` without `HEADLESS` replaces the shell process; `HEADLESS=1` returns a mapped code. **Amended 2026-09-03 (athena, round-1 review of #60: AT-5).** The row as written was in flat contradiction with #36 D8 and with D23: `exec timeout <secs> claude …` returns the *wrapper's* status, so the interactive row can hand a caller 124 when the cap fires and 125/126/127 for `timeout`'s own errors — codes outside the 0/1/2 vocabulary — and a harness that exits 2 for a reason of its own is read as a designed refusal. The interactive row therefore **maps too**, and the amended rule is: (1) `work.sh` does **not** `exec` the interactive launch. It runs `timeout <secs> <harness> …` as a foreground child that inherits stdin, stdout, stderr and the terminal — which is all "the operator's terminal *is* the session" ever required; `timeout` was already an un-`exec`'d process between the two, so this costs one process and changes nothing the operator can see. `work.sh` waits, maps, and exits, so **every** exit of this script is 0, 1 or 2. (2) The map is two-valued: child status 0 → **0**; child status **anything non-zero, including 124 and including 2** → **1**, with the raw status named on stderr — `==> <persona>'s session did not complete (exit <raw>)`, and for 124 the word *cap*: `==> <persona>'s session hit the <T>-minute cap (exit 124)`. A timeout is not a new outcome kind and gets no `WORK-RESULT` of its own: `WORK-RESULT` is a line the persona prints (D2, D21) and a timed-out session prints nothing, so 124 is the launcher's own observation — the same fact D14 already maps to 1 when it arrives headless as `status: "ERROR"`. The two modes now agree. (3) A child's numeric status is **never** passed through as 2. Exit 2 belongs to the launcher's own refusals and to D14's parsed `refused`/`blocked`, and to nothing else. (4) Interactive 0 therefore means *the session ran to completion*, not *the work was done*: an in-session refusal is visible to the operator and to the tracker, not to this script. #25's `vm-local` adapter drives `HEADLESS=1` and is unaffected. Testable, four scenarios against the stubbed harness on the interactive row: a stub exiting 0 → `work.sh` exits 0; a stub exiting 3 → exit 1 with `exit 3` in the message; a stub exiting 2 → exit **1**, not 2; a stub that outlives the wrapper → exit 1 with `124` and the cap named. Plus: the interactive launch line is not `exec`'d, and a `DRY_RUN=1` interactive dry run still prints the same command. |
| D16 | **The `/work` door is a hand-authored `.claude/commands/work.md` containing exactly `scripts/ops/work.sh $ARGUMENTS`; no antigravity twin ships in v1.** `.claude/commands/` is outside the compiler's `TARGET_DIRS` (`.claude/agents`, `.agents/agents`), so the drift gate ignores it and a hand-authored file there is not a compiler bypass. A command rather than `.claude/skills/work/SKILL.md`: a skill's description is injected into every session's context to make it discoverable, and this one is typed by the operator, not discovered by a model — a per-session token cost for zero benefit. The `.agents/workflows/` twin is an explicit non-goal for v1: dispatch is driven from the operator's interactive session, and two hand-authored files with no gate between them is the drift the compiler exists to prevent. Revisit when the presenter dispatches from the IDE. Testable: `/work 43` in an interactive session runs the script with `43`; no file under `.agents/workflows/` is added. **Amended 2026-09-03 (athena, round-1 review of #60: AT-1, Argus's open item (a), N2).** "Exactly `scripts/ops/work.sh $ARGUMENTS`" is a spec-level claim and it was the wrong line. The door's body runs in the harness's own non-TTY bash *before* the turn, so for the four `claude-code`-pinned personas (`config/deployments.yaml`) it reached D5's **interactive** row and `exec`'d a session that cannot start for want of a terminal — after minting a one-hour credential, which is precisely what D11's grounds forbid; and a `$ARGUMENTS` that legitimately refuses (exit 2 — `hold`, a closed issue, a foreign claim, an `--as` that does not own the stage) surfaced as a failed tool call, rendering D23's most informative answer as a crash. Four clauses replace the one line. **(a) The door names a mode.** Its body is exactly `` !`HEADLESS=1 scripts/ops/work.sh $ARGUMENTS; echo "[work.sh exit $?]"` ``. `HEADLESS` stays an environment variable and argv stays `<n> [--as <persona>]` — D5, #36 D7 and Acceptance 12 are untouched, and the door names the mode the way any other caller does. For an `antigravity` persona this changes nothing (that harness is always headless); for a `claude-code` persona `/work` is a `claude -p` dispatch whose output and mapped code land in the operator's session. The operator who wants their *terminal* to be the session runs `scripts/ops/work.sh <n>` from a terminal — that is what interactive means, and it is not a thing a slash command can be. **(b) The exit code is displayed, and the door never aborts the turn.** The trailing `; echo "[work.sh exit $?]"` makes the body exit 0 whatever `work.sh` returned, prints `work.sh`'s own refusal text (written before the exit) and states the code, so 0, 1 and 2 are all visible to the operator and to the model. `|| true` is rejected: it also unblocks the turn but throws the code away, and then a crash and a designed refusal read identically — the exact confusion D23 exists to prevent. **(c) `work.sh` refuses the interactive row when there is no terminal.** A guard beside the harness-binary preflight and **before** the mint: if the resolved row is interactive and stdin or stdout is not a tty, `work.sh` exits **1** — the same class as a missing harness binary, an environment that cannot start the row rather than a decision about the number, so exit 2 keeps meaning "not worked, by design" (D23) — with a message naming `HEADLESS=1`, having minted nothing and started no child. This is the clause that also holds for every other non-TTY caller: cron, a CI step, a subagent's bash. **(d) The door is cwd-relative, by design.** It invokes `scripts/ops/work.sh` by relative path, so `/work` resolves against the session's working directory: a session sitting in a worktree gets *that* worktree's copy, which is exactly what D24 instructs, and it simply fails from a subdirectory. That property is stated in the command's `description` rather than left to be rediscovered. Two documented properties, neither a code change: `allowed-tools` is widened so the mode-prefixed line matches (`Bash(HEADLESS=1 scripts/ops/work.sh:*)` if the prefix matcher accepts an assignment prefix, otherwise whatever spelling runs the door with no permission prompt — the testable is the absent prompt, not the spelling); and `$ARGUMENTS` is interpolated unquoted into a shell command line, so `/work 43; <anything>` runs, which makes the door an operator-typed surface and **not** a trust boundary — it is never invoked with model-generated or externally-sourced arguments. Testable, amended: the command file contains exactly one command line and it is the (a) form; `/work <n>` on a `claude-code` stage prints the `-p` launch, not the interactive one; `/work <n>` on a number that refuses prints `work.sh`'s refusal text followed by `[work.sh exit 2]` and does not surface as a tool failure; with stdin and stdout redirected away from a tty, `scripts/ops/work.sh <n>` on a `claude-code` stage exits 1 naming `HEADLESS=1`, with zero mints and zero launches; no file under `.agents/workflows/` is added. |
| D17 | **AGENTS.md gains one subsection under "Working the tracker": dispatch has one door.** Its content, in three rules: (1) a lifecycle stage is started by `scripts/ops/work.sh <n>` and by nothing else, so the harness, identity and model a stage runs under are the pinned ones; (2) **no session acts as a persona it is not** — an in-session subagent is the acting persona's own helper, drawn from its `delegates_to` list, and may never be given another persona's stage, because a stage worked by a borrowed subagent produces an artifact nobody's authority backs; (3) where the harness genuinely cannot start the persona natively yet, a bootstrap dispatch is allowed **only if the claim comment says so in its first line**, naming the persona and the reason — an exception that is visible on the tracker is an exception; one that is silent is impersonation. Testable: the subsection exists, is under 20 lines, and duplicates no rule already in the file. |
| D18 | **#47 is a stated dependency, not a fix.** Three Apps (daedalus, argus, atlas) are registered `issues: read` in `scripts/auth/app_manifests.yaml`, so a token minted for them cannot add `in-progress`, cannot post the `Claim:` line `work.sh` reads as the mutex holder, and cannot post the handoff. Only the App owner can change that, on `github.com/settings/apps/evekhm-<persona>-app/permissions`, followed by accepting the permissions on the installation. This spec therefore splits the smoke test's assertions by what each App can prove today (D19) and names the human step. Testable: the spec and PR body both name #47 as the blocker for the claim/handoff half of the antigravity smoke run. |
| D19 | **The smoke test is `scripts/ops/smoke_launch.sh <scratch-issue>`, one run per harness, asserting three observables each, with the identity proof chosen from each App's real permissions.** `claude-code` runs as `odyssey` (App has `issues: write`): exit 0, the stage's artifact present in the working tree, and a comment on the scratch issue authored by `evekhm-odyssey-app[bot]`. `antigravity` runs as `daedalus` (App has `contents: write` but only `issues: read` until #47): exit 0, the artifact present, and a **commit** on a scratch branch authored by `evekhm-daedalus-app[bot]` — which is acceptance item 5's "commit *or* comment", and it proves persona load and token handoff in one check, since the stock fallback agent has no instruction to push anything. Identity is never verified with `gh api user`: an App token has no user and gets 403 (findings Q7); `GET /installation/repositories` is the token-side check, the artifact's author the outcome-side one. The claim-and-handoff half of the antigravity run is written into the script as a check that is expected to fail with 403 until #47's human step lands, reported as `BLOCKED ON #47`, not as a #43 defect. Testable: the script exits 0 on the two runs above with #47 outstanding, and its `BLOCKED ON #47` line disappears once the permission is granted, with no edit to the script. **Amended 2026-09-03 (athena, round-2 review of #60: AT-4).** One grounds clause is struck as false and a fourth antigravity observable is added; the two runs, the three existing observables per run and the #47 split are unchanged. **Struck:** *"it proves persona load and token handoff in one check, since the stock fallback agent has no instruction to push anything."* The stock fallback agent has precisely that instruction, because the errand lives in the scratch issue's body and the prompt sends every agent to read it (D8 as amended). What the push does prove is the credential plumbing (D11–D13) and the exit mapping (D14) — real value, kept, and now claimed at its true width. **Added, the fourth observable:** the antigravity run also asserts a **persona-only marker** — a value whose *instruction to emit it* and whose *content* both reach the launched agent only through the system prompt the compiled target becomes. Concretely: for the duration of one run, `smoke_launch.sh` generates a fresh random nonce and writes it, together with the one sentence that tells the persona to end its commit message with it, into the compiled `agent.md` of the persona it is about to launch; the assertion is that the nonce appears in the **pushed commit's message**. The nonce and that sentence appear nowhere else — not in the issue body, not in D2's prompt, not in argv, not in any file the errand names — so an agent that did not load the target has nothing pointing it at a marker, while a loaded one cannot miss it. This is findings Q1b's instrument (a secret word only the compiled agent carries), moved from a throwaway workspace onto the real launch path. The honest claim is *"an agent that did not load had no reason to look"*, not *"could not know"*: `agent.md` sits inside the `--add-dir` tree and is readable, and the discrimination comes from nothing in the errand mentioning a marker at all. **Invariants, because the target is a gated generated file:** the injection is reverted on every exit path including a crash and an interrupt; the run refuses to start if that target is already modified in the working tree; and `scripts/sync_agents.py --check` plus `scripts/ci/compiler_roundtrip.sh` pass after the run. A smoke test that can leave the drift gate red is worse than the observable it buys. **Routing:** this is a change to `scripts/ops/smoke_launch.sh` and to nothing else, and it lands *after* PR #60 as a follow-up implementation PR on #43 carrying `Spec-impact: none` — the spec change is this amendment, the code is separable, and **#60 is not held for it**. Testable, amended: with the nonce injection stubbed out, the antigravity run fails on the marker observable and on no other; with it in place the run passes, the pushed commit's message contains the nonce, `grep` for the nonce over the scratch issue body and over `work.sh`'s prompt literal finds nothing, and `git status --porcelain .agents/agents/` is empty after the run. |
| D20 *(adversary)* | **A two-owner stage mints nothing and preflights nothing.** Two readings of D11 were defensible — mint for each owner printed, or only for the one launched. The differing case: `work.sh 42` on a `status:in-review` issue, whose owners are argus and atlas (#2 D4 requires both). Under the first reading the script performs two token exchanges and leaves two live one-hour credentials for a run that #36 deliberately makes launch nothing; under the second it performs zero. Zero is the rule. The same applies to D3: the preflight runs for the persona about to be launched, and for owners that are only printed a missing target is reported as a `target: … (missing)` marker without changing the exit code — so a broken atlas target cannot stop `--as argus`. |
| D21 *(adversary)* | **The `WORK-RESULT` line is requested by the launch prompt, not written into persona sources.** Two readings: the line is part of D2's prompt, or it is a rule added to `personas/**` and compiled into every persona. The differing case: the presenter opens an interactive session by hand, outside `work.sh`, and asks athena a question. Under the second reading every persona emits a machine-readable result line at the end of an ordinary conversation, and #43 has to edit six persona sources, re-run the sanitize gate, and rebuild every compiled target for a string that only a launcher reads. Under the first, the line exists exactly where something parses it. First reading. This is also why "Not touched" above can say `personas/**`. |
| D22 *(adversary)* | **One prompt string, both modes.** Two readings: the `WORK-RESULT` sentence is appended only in headless mode, or it is always present. Differing case: `work.sh 43` interactive — the first reading gives a clean conversational prompt, the second makes athena print a result line at the end of an interactive session. The second is chosen anyway: the noise is one line, and two prompt strings is two things to keep in sync for a difference nothing depends on. A single literal is also what makes D2's grep-based test meaningful. |
| D23 *(adversary)* | **A refusal by the *launcher* and a refusal by the *launched persona* share exit 2, and that is deliberate.** Two readings: exit 2 means "work.sh refused" (#36 D8's six conditions), or exit 2 means "this number was not worked, by design". Differing case: a caller — #25's `vm-local` adapter — runs `work.sh 42 --as atlas` on an issue that gained a `hold` label after dispatch but before the persona claimed. Under the first reading the launcher exits 0 (it launched fine) and the adapter records a successful run of a session that did nothing; under the second both the pre-launch and the in-session refusal arrive as 2 and the adapter's one branch is correct for both. Second reading: a caller cares whether the number was worked, not which layer declined. **Amended 2026-09-03 (athena, round-1 review of #60: AT-5).** The row stands; one clause is added to keep it true now that the interactive row maps as well (D15 as amended). Exit 2 is *produced*, never *forwarded*: it is written by the launcher's own refusals (#36 D8's conditions, in either mode) and by D14's parsed `refused`/`blocked`, and a launched child's exit status of 2 is mapped to 1 like any other non-zero. Otherwise the vocabulary the adapter's one branch depends on could be minted by an unrelated harness's numbering, which is the same collapse this row was written to prevent, arriving from below instead of above. |
| D24 *(adversary)* | **`--add-dir` is the checkout that owns the running `work.sh`, not the caller's current directory.** Two readings for `$REPO_ROOT`: the existing `BASH_SOURCE`-derived value, or `git rev-parse --show-toplevel` from the caller's cwd. Differing case: the operator, standing inside a worktree at `.claude/worktrees/x`, runs `/path/to/main/scripts/ops/work.sh 43`. The first reading points agy at the main checkout — the same tree from which the script already read `personas/lifecycle.json`, `config/deployments.yaml` and the intent folder; the second reads the labels and the folder layout from one tree and edits another. First reading: reading state from one checkout and writing to a different one is the split #36 was built to avoid. To dispatch into a worktree, invoke that worktree's own copy of the script — and `work.sh` prints the resolved root in its report so the operator can see which tree a session will edit. |

## Acceptance

Each item names the Decision it derives from; a contract test that
cannot cite one is a missed ambiguity and comes back here (the
spec-adversary skill's downstream contract).

1. `DRY_RUN=1 scripts/ops/work.sh <n>` for a `daedalus`-owned stage
   prints an `agy -p … --agent daedalus --add-dir <absolute root>
   --model <resolved> --output-format json --print-timeout 45m` line,
   and a `timeout 2760` wrapper (D1, D5, D6, D9).
2. The same command prints `identity: evekhm-daedalus-app[bot] (token
   minted at launch; not printed)`, makes no call to
   `api.github.com/app/installations`, and emits nothing token-shaped
   (D11).
3. A rebuild produces `.agents/agents/<name>/{agent.md,agent.json}` and
   no `config.yaml` or `instructions.md`; `sync_agents.py --check` and
   `scripts/ci/compiler_roundtrip.sh` both pass; no `agent.md` has a
   `model:` key (D7, D8, D10).
4. Renaming `.agents/agents/daedalus/agent.md` away makes
   `work.sh <n>` exit 1 with the missing path named, before any model
   call (D3).
5. With the App private key unavailable, `work.sh <n>` exits 1 and
   starts no child; with an ambient `GH_TOKEN` set and a successful
   mint, the child sees the minted token and not the ambient one
   (D12).
6. A child launched by `work.sh` pushes to `<persona>/*` over HTTPS
   with no ambient helper on PATH, and the parent shell's
   `git config --list` gains nothing (D13).
7. Stubbed-harness fixtures produce the four exits of D14: `ok` → 0,
   `refused`/`blocked` → 2, `status: ERROR` → 1, `SUCCESS` with no
   result line → 1 (D14).
8. `work.sh 42` on a two-owner review stage prints both owners,
   launches neither, exits 0, and mints zero tokens (D20).
9. `scripts/ops/smoke_launch.sh <scratch>` runs both harnesses and
   asserts, per run, the exit code, the artifact, and the author of
   the produced comment (`claude-code`/odyssey) or commit
   (`antigravity`/daedalus); the antigravity claim assertions report
   `BLOCKED ON #47` and the script still exits 0 (D18, D19).
10. `/work 43` in an interactive Claude Code session runs
    `HEADLESS=1 scripts/ops/work.sh 43` and prints `[work.sh exit <code>]`
    after it; nothing is added under `.agents/workflows/` (D16 as
    amended 2026-09-03 — the item originally read "runs
    `scripts/ops/work.sh 43`").
11. AGENTS.md carries the "dispatch has one door" subsection, and it
    restates no rule already in the file (D17).
12. The interfaces #25's plan depends on are unchanged: `work.sh <n>
    --as <persona>` is still the whole argv contract, every new mode is
    an environment variable, and `scripts/placement/vm-local/run.sh`
    mints nothing and exports nothing (#25 D16, D18; plan T4).
13. `docs/SPEC.md` is upserted in the implementing PR: `ops.dispatch`
    reworded for the two-harness table and the mint step, the compiler
    entry reworded for the new antigravity layout, and one new entry
    for the persona-identity handoff.

Items 14–16 were added 2026-09-03 by the round-1 review of PR #60
(AT-1, AT-5, AT-2); items 1–13 keep their numbers.

14. On a `claude-code` stage with stdin and stdout redirected away from
    a terminal, `scripts/ops/work.sh <n>` exits 1 naming `HEADLESS=1`,
    mints nothing and launches nothing; the same stage with
    `HEADLESS=1` launches (D16 as amended, clause (c)).
15. Interactive-row stubs produce two exits only: stub 0 → 0; stubs 3,
    2 and a fired cap → 1, each naming its raw status (`exit 3`,
    `exit 2`, `exit 124` with the cap) — and the interactive launch is
    not `exec`'d (D15, D23, both as amended).
16. The fixture tree's launch, run under `bash -x` with stdout and
    stderr captured together, contains no occurrence of the mint stub's
    `stub-token-for-` literal, on the headless row and on the
    interactive row (D11 as amended).

Item 17 was added 2026-09-03 by the round-2 review of PR #60 (AT-4);
items 1–16 keep their numbers. It is the one acceptance item PR #60 is
**not** expected to satisfy: per D19 as amended it lands in the named
follow-up PR, and #60 is not held for it.

17. The antigravity smoke run asserts a persona-only marker: a nonce
    generated per run and injected only into the launched persona's
    compiled `agent.md` appears in the pushed commit's message, and a
    `grep` for it over the scratch issue body and over `work.sh`'s
    prompt literal finds nothing. After the run — including after a
    crash or an interrupt — `git status --porcelain .agents/agents/` is
    empty and `scripts/sync_agents.py --check` passes (D8, D19, both as
    amended 2026-09-03).

## Out of scope

- **Raising the three Apps to `issues: write` (#47).** A human action
  on github.com; this spec depends on it and states it (D18).
- **Repinning personas to antigravity (#44).** Config-only, and
  blocked on this issue rather than part of it.
- **The permission posture on a CI runner.** Headless writes needed no
  flag in the measurement, but the cause is machine-local —
  the antigravity CLI's per-user `settings.json` carries
  `"toolPermission": "always-proceed"` and lists this repository under
  `trustedWorkspaces` (findings Q8). `--dangerously-skip-permissions`
  is a no-op here and is not passed. Every v1 binding for an
  antigravity persona is `placement: vm-local` (#25 D19), so the
  runner case is not on the critical path; the first `gh-actions`
  binding for an antigravity persona must settle it, and that belongs
  to whoever writes that adapter step.
- **An `.agents/workflows/` twin of `/work`** (D16).

## Inputs

- `runs/2026-09-03_agy-headless/findings.md` — every agy behaviour
  cited above, measured on agy 1.1.24, 2026-09-03.
- `intent/36-dispatch/spec.md` D7–D10 and `scripts/ops/work.sh` — the
  argv contract, the exit codes, the launch table this extends.
- `intent/25-execution-model/spec.md` D16–D19 and PR #46's plan T4 —
  the `vm-local` adapter that calls this line.
- `intent/2-config/` D1–D4 — deployment pins and the two-reviewer
  constraint.
- #47 (App permissions), #44 (repins), #5 (the compiler, whose
  antigravity emitter this corrects).
