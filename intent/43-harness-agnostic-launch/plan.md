# Plan: harness-agnostic launch

**Issue:** #43 · **Spec:** spec.md (Approved) · **Author:** daedalus
(`evekhm-daedalus-app[bot]`)

Twelve tasks. Each names the files it touches, the Decision rows it
satisfies, and the check that proves it. Line numbers cite HEAD
`33cae9d` (branch `athena/43-harness-agnostic-launch`; the spec is not
on `main` — PR #49).

**Order.** The compiler chain first, because it is the only part
already covered end-to-end by a CI gate and because the launch row is
a lie until it exists: T1 → T2 → T3. Then T4, the test-harness
upgrade every launch task needs, then the launch path in dependency
order T5 → T6 → T7 → T8. T9 and T10 are independent of all of it and
may land any time after T5. T11 (smoke) needs T1–T8. T12 (living
spec) is last because it describes what the others built.

**Two unverified agy behaviours gate T1** and are its first two steps,
P1 and P2, each with a named fallback. Nothing else in the plan may be
written until they are answered, because both change the bytes the
emitter emits. A third unverified fact (`agy --model` in print mode)
gates T5 as P3, and a fourth (Claude Code's `-p --output-format json`
key names) gates T8 as P4. All four are cheap: run them, record the
output in `runs/<YYYY-MM-DD_HHMMSS>/`, and cite the folder in the PR.

**Contract tests.** Per the #36 precedent this plan specifies each
task's tests inside the task; they are written with the code by the
implementer, not committed ahead of it. No contract-writer sub-agent
was dispatched for that reason.

## T1 · `scripts/sync_agents.py` — the antigravity target — D7, D8, D9, D10

### P1 (first) — does agy tolerate a YAML comment in `agent.md` frontmatter?

Measured: `model:` in the frontmatter voids the whole agent, silently
(findings Q1b). A comment is not a key, but that is an argument, and
the spec labels it unverified. Reproduce the probe's A/B in a
throwaway git workspace outside this checkout — an `agent.md` whose
frontmatter is `# GENERATED …`, `name`, `description`, `tools`, and a
body holding a secret word; `agy -p "<ask for the secret word>"
--agent <name> --add-dir <workspace> --output-format json`. Loaded =
the secret word comes back and input tokens sit near the loaded
figure (6.5k, not 12.9k).

**Fallback if the comment voids the agent:** the marker becomes the
first line of the *body*, immediately below the closing `---`, as
`<!-- GENERATED … -->` — the form `instructions.md` uses today
(sync_agents.py:633). Nothing else moves: `existing_generated()`
(710–726) matches `MARKER` anywhere in the file, so pruning and the
drift gate are indifferent to where it sits.

### P2 (first) — does a sidecar `agent.json` beside `agent.md` break discovery?

The probe measured `agent.json` *without* `agent.md` (not found) and
`agent.md` alone (loaded). The pair was never run. Same throwaway
workspace, same prompt, now with both files present, the sidecar
carrying `model` and `subagent`.

**Fallback if the pair stops loading:** rename the sidecar
`agent.model.json` in the same directory and re-run; if a
non-`agent.md` file in that directory breaks discovery at all, move it
to `.agents/models/<name>.json` and add `.agents/models` to
`TARGET_DIRS` (639) so the drift gate still owns it — that is the one
line of D10 ("`TARGET_DIRS` is unchanged") the fallback overrules, and
it is reported in the PR body rather than done silently.

### The change

Rewrite `AntigravityEmitter` (607–634) to emit two files:

- `.agents/agents/<name>/agent.md` — frontmatter `# <MARKER>` (or P1's
  fallback), `name`, `description: <yaml_scalar(describe(role))>`,
  and `tools:` as a **YAML block list**, one `  - <tool>` per line.
  Block list, not the comma-joined form `ClaudeEmitter` uses (597):
  a list is what the probe measured loading (findings Q1b, 3,795
  tokens). No `model:` key, ever (D8). Then `---`, a blank line, and
  the same `body` argument the other emitter receives.
- `.agents/agents/<name>/agent.json` — reduced to `_generated`,
  `name`, `model`, and `subagent` (a real boolean, `persona["kind"]
  == "subagent"`). `limits` comes out: it lives in
  `personas/<name>.yaml` and T5 reads it there, so each fact has one
  home (D9).

`config.yaml` and `instructions.md` are not deleted by hand: they
carry `MARKER`, so `write()`'s stale-set (731, 741–742) removes them
on the next build and `rmdir`s nothing (the directory keeps two
files). Say so in the commit message — a reviewer expecting a `git rm`
should see why there is none.

`verify()`'s antigravity branch (831–857): replace the three-leaf
existence loop with `agent.md` + `agent.json`; keep the `name` and
`model` assertions against the sidecar; **drop** the `limits`
assertion; read tools out of `agent.md`'s frontmatter with
`read_frontmatter()` (776–788, already generic — update its docstring)
and compare to `record["tools"]`; assert `"model" not in front`;
assert `front["name"] == name` and a non-empty `description`; set
`body` from `read_frontmatter()`'s second return value so the skill,
fallback and ladder assertions at 859–886 keep working unchanged.

**Proves it (Acceptance 3):** `python3 scripts/sync_agents.py --check`
exits 0 after T3's rebuild; `--verify` exits 0; `grep -rn '^model:'
.agents/agents/*/agent.md` is empty; `ls .agents/agents/daedalus/` is
exactly `agent.json agent.md`. Plus T2 and the P1/P2 run folder.

## T2 · `scripts/ci/compiler_roundtrip.sh` — the roundtrip gate — D7, D10

Section 5's throwaway persona (95–130) is the only place a persona is
compiled from scratch, so it is where the new layout must be proved.
Replace the six `$AGENT/config.yaml` and `$AGENT/instructions.md`
asserts (115–128) with the same assertions against `agent.md`, and
keep `'"model": "gemini-3.7-flash-medium"'` and the marker assert
against `agent.json` (113, 129). Add two negative asserts the file has
no helper for yet — a three-line `assert_not_in` beside `assert_in`
(34): `model:` must not appear in `agent.md`, and neither
`config.yaml` nor `instructions.md` may exist under `$AGENT`.

**Proves it (Acceptance 3):** `bash scripts/ci/compiler_roundtrip.sh`
exits 0; it runs on every PR as the drift gate
(`.github/workflows/ci-gates.yml:59–63`), which needs no edit.

## T3 · `.agents/agents/**` — the rebuild — D7, D10

`python3 scripts/sync_agents.py`, commit the result, never hand-edit.
Seven directories change (atlas, daedalus, and the five sub-agents
coder, contract-writer, explorer, mechanic, scanner): 7 × `agent.md`
added, 7 × `agent.json` rewritten, 14 files pruned.

**Proves it (Acceptance 3):** `git diff --stat` shows exactly those 28
paths and nothing under `.claude/agents/` or `personas/`;
`sync_agents.py --check` exits 0 on the committed tree.

## T4 · `scripts/ops/tests/work_test.sh` — the fixture tree — enables T5–T8

Today the suite runs the real `scripts/ops/work.sh` against the real
`personas/` and `config/` with a stub `gh` and a stub `claude` on
PATH (35–55). Three of this issue's tasks cannot be tested that way:
`work.sh` invokes the mint script by absolute path derived from
`BASH_SOURCE` (54, D24), so PATH cannot stub it; the D10 scenario at
279–286 runs with `DRY=0` against daedalus and would now really start
`agy`; and no persona is pinned to a harness with no launch row any
more, so "an unlaunchable harness" has no fixture.

Add one helper, used only by the scenarios that need it:

```bash
# fixture_tree -> a temp REPO_ROOT owning its own copy of work.sh
fixture_tree() {
  local t; t="$(mktemp -d "$WORK/tree.XXXX")"
  cp -r "$REPO/personas" "$REPO/config" "$REPO/scripts" "$t/"
  ln -s "$REPO/intent" "$t/intent"
  printf '%s\n' '#!/usr/bin/env bash' 'echo "mint $*" >> "$MINTS"' \
    'echo "stub-token-for-$1"' \
    > "$t/scripts/auth/mint_app_token.py"
  chmod +x "$t/scripts/auth/mint_app_token.py"
  printf '%s\n' "$t"
}
```

`$MINTS` is a second log beside `$WRITES`, so a test can assert *zero*
mints as cheaply as it asserts zero writes. Copying `personas/` and
`config/` (rather than symlinking) lets a scenario add a persona
pinned to a third harness with `sed`, exactly as
`compiler_roundtrip.sh:100` does. Symlinking `intent/` keeps the
folder-reuse scenarios (311–316) answering the same way. Stub `agy`
beside the stub `claude` (49–53): it appends to `$WRITES` and prints
whatever `$AGY_JSON` names, so T8 can drive it.

Rewrite the D10 scenario (279–286) as two: daedalus under
`DRY_RUN=1` (the row now exists, so this is T5's assertion), and a
`fixture_tree` persona pinned to `harness: nonesuch` under `DRY=0`,
which still prints and exits 0 — the `*)` arm of `launch_command`
(389) stays reachable and stays tested.

**Proves it:** `bash scripts/ops/tests/work_test.sh` still exits 0
with every pre-existing scenario passing, before T5 changes any
behaviour. Run it once at this point and cite the output.

## T5 · `scripts/ops/work.sh` — the launch table — D1, D2, D3, D5, D6, D20, D22, D24

Five edits, all below line 357.

- **Modes.** `HEADLESS="${HEADLESS:-0}"` beside `DRY_RUN` (52). No new
  argv: the number and `--as` stay the whole contract (#36 D7;
  Acceptance 12).
- **`target_of()` (377–383).** The antigravity arm becomes
  `.agents/agents/%s/agent.md`.
- **Two readers.** `timeout_mins_of <persona>` — `sed -n '/^limits:/,$p'
  personas/<p>.yaml` then the first `timeout_mins: <n>`; absent or
  non-numeric is `die` (a broken source, exit 1). `model_of <persona>`
  — `jq -r '.model // empty' .agents/agents/<p>/agent.json`; empty is
  `die`. daedalus resolves 45 and `gemini-3.1-pro-high`
  (`config/model_tiers.yaml`, antigravity FRONTIER); odyssey 90.
- **One prompt literal (D2, D22).** A single assignment, present in
  both modes and both harnesses:

  ```bash
  PROMPT="Work issue #$ISSUE in this repository. Follow your persona instructions and the repository's AGENTS.md; when you finish or refuse, print one final line WORK-RESULT: <ok|refused|blocked> #$ISSUE <one-line reason>."
  ```

- **`launch_command()` (385–390) becomes `launch_argv()`**, filling a
  global bash array rather than a string, because a printed command
  and an executed one must not be two spellings of the same thing:

  | harness | `HEADLESS=0` | `HEADLESS=1` |
  |---|---|---|
  | `claude-code` | `claude --agent $P "$PROMPT"` | `claude -p "$PROMPT" --agent $P --output-format json` |
  | `antigravity` | *(same as headless — D5)* | `agy -p "$PROMPT" --agent $P --add-dir $REPO_ROOT --model $M --output-format json --print-timeout ${T}m` |

  Every row is wrapped: `WRAP=$(( T * 60 + 60 ))` and the argv is
  `timeout "$WRAP" …` (D6, "the whole child"). The report prints the
  array through `printf '%q '` so what is shown is what runs.

  *(Amended 2026-09-03, PR #60, round-2 finding R2-1; D15 and D16(a).
  The INTERACTIVE row's wrapper is `timeout --foreground "$WRAP" …`.
  GNU `timeout` calls `setpgid(0,0)` unless given that flag, and once
  T8's amendment removed the `exec` the call stopped being a no-op: the
  harness landed in a process group that is not the terminal's
  foreground group, where its first `tcsetattr` — raw mode, which every
  interactive TUI sets at startup — raises SIGTTOU and stops it, with a
  live token already minted, until the cap fires. The headless rows keep
  the plain form deliberately: nothing there reads or reconfigures a
  terminal, and group-wide signalling is what should kill a runaway
  non-interactive harness and its children at the cap. Knock-on: the T5
  binary preflight indexes the harness binary at `LAUNCH[3]` when the
  flag is present, `LAUNCH[2]` otherwise.)*

- **Preflight (D3, D20).** In the per-owner loop (410–431), after
  `target_of`, mark a missing target `(missing)` in the printed line
  and record it. **After** the multi-owner early return (434–441) and
  **before** any mint or launch, a missing target for the persona
  about to be launched is `die "…"` naming the path. A two-owner stage
  prints the marker and still exits 0.

- **`--add-dir` is `$REPO_ROOT` (D1, D24)** — the value already
  derived at line 54, absolute by construction, never `git rev-parse`
  from the caller's cwd, and no `cd` to anywhere other than
  `$REPO_ROOT`. The report gains a `root:` line so the operator sees
  which checkout a session will edit.

  *(Amended 2026-09-03, PR #60, round-2 findings R2-2 / AT-R2-1; D1 as
  amended on `main` in #70. This bullet read "and no `cd` anywhere" —
  the fourth copy of the clause F5 struck from `spec.md`, AT-3 struck
  from `work.sh:505` and the living spec already reflects. `work.sh`
  does `cd "$REPO_ROOT"` exactly once, immediately before the launch,
  because claude-code has no `--add-dir` and takes the working
  directory as the project; what D1 as amended forbids is a `cd` to
  anywhere else.)*

**Proves it (Acceptance 1, 4, 8):** T4's suite, extended —
`DRY_RUN=1` for a `status:build` issue prints the full agy line with
`--add-dir <the fixture tree, absolute>`, `--print-timeout 45m` and
`timeout 2760`; `HEADLESS=1 DRY_RUN=1` for an odyssey stage prints
`claude -p` and `timeout 5460` with no `--print-timeout`; unset
`HEADLESS`, the same stage prints the interactive form; a `fixture_tree`
run with `agent.md` renamed away exits 1 naming the path with
`$WRITES` and `$MINTS` both empty; the two-owner review stage exits 0
with both owners printed. Statically: `grep -c 'Work issue #\$ISSUE'
scripts/ops/work.sh` is 1, that line matches none of `stage|plan|
spec|branch`, and `grep -n '\bcd \b' scripts/ops/work.sh` finds
nothing before the launch. `bash -n` on the script.

## T6 · `scripts/ops/work.sh` — mint and hand off — D11, D12, D20

Immediately before the launch, after every refusal, the preflight, the
multi-owner return and the `DRY_RUN` return (442–445) — so a run that
launches nothing exchanges nothing:

```bash
tok="$("$REPO_ROOT/scripts/auth/mint_app_token.py" "$launch_persona")" \
  || die "cannot mint an App token for $launch_persona; refusing to launch as somebody else"
[ -n "$tok" ] || die "…"
```

The child gets it as an assignment prefix and gets nothing ambient:
`GH_TOKEN="$tok" GITHUB_TOKEN="$tok" exec timeout … ` (interactive) or
the same prefix on the captured headless call. Never `export` in the
parent, never a file, never argv, never an `echo`. `DRY_RUN=1` prints
one line instead, `identity: evekhm-<persona>-app[bot] (token minted
at launch; not printed)`, with the login read from
`personas/<p>.yaml`'s `authority.identity` — the field
`persona_for_login()` (249–260) already parses.

**Amended 2026-09-03 (PR #60, round-1 review finding AT-2; D11 as
amended).** Two changes to the hand-off above. (1) The prefix form is
now an `export` inside a subshell that then `exec`s, because the four
`GIT_CONFIG_*` pairs of T7 are appended at the caller's own offset and
their names are therefore computed; the properties the prefix had are
the ones a builtin `export` keeps — never argv, never a file, never an
`echo`. An `env VAR=… ` prefix would have been the obvious alternative
and is rejected: it puts the token in a world-readable argv. (2) Xtrace
is suppressed for the window between the mint and the launch and the
caller's setting restored the moment the child returns. Bash's `set -x`
expands both `tok="$(…)"` and every assignment of the value, so
`bash -x scripts/ops/work.sh <n>` wrote the live token to stderr — and
a Claude Code session captures tool stderr verbatim into an on-disk
transcript. The suppression is a no-op when xtrace is off.

**Proves it (Acceptance 2, 5, 16):** `DRY_RUN=1` output contains the
identity line, `$MINTS` is empty, and the output matches no
`[A-Za-z0-9_]{36,}`; the two-owner stage leaves `$MINTS` empty (D20);
in a `fixture_tree` whose stub mint exits 1, `work.sh` exits 1 naming
the persona with `$WRITES` empty; with the stub minting and
`GH_TOKEN=ambient-not-this-one` exported, the stub `agy` records the
`GH_TOKEN` it saw and the test asserts it is the minted value. Added
for the amendment: one scenario per row runs the fixture launch under
`bash -x`, captures stdout and stderr together, and fails if
`stub-token-for-` appears — with the trace asserted present, so the
check cannot pass vacuously, and the child asserted to have received
the token, so it proves suppression rather than withholding.

## T7 · `scripts/auth/git-credential-persona` (NEW) — D13

A short bash script: `git-credential-persona <persona> get` prints
`username=x-access-token` and `password=<a freshly minted token>`,
then a blank line; `store`/`erase` are no-ops that exit 0 (git calls
them, and a helper that fails on them fails the push). It shells out
to `mint_app_token.py` in the same directory — resolved from
`BASH_SOURCE`, so it names no home directory and needs no
`sanitize_allowlist.txt` entry (D4's rule, and the same property
`intent/25-execution-model/plan.md` T4 relies on).

`work.sh` installs it through the child's environment only:

```
GIT_CONFIG_COUNT=4
KEY_0 credential.helper                        VALUE_0 ""        # reset the generic list
KEY_1 credential.https://github.com.helper     VALUE_1 ""        # reset the URL-specific list
KEY_2 credential.https://github.com.helper     VALUE_2 "<abs path> <persona>"
KEY_3 url.https://github.com/.insteadOf        VALUE_3 git@github.com:
```

**Amended 2026-09-03 (PR #60, round-1 review finding AT-7).** The four
pairs are unchanged; the indices are not. They are appended at
`${GIT_CONFIG_COUNT:-0}` rather than written at 0, and the count is
extended rather than set, so a caller that already installs
`http.proxy` or `safe.directory` through `GIT_CONFIG_*` keeps its own
entries instead of having them silently replaced. With nothing
inherited the offset is 0 and the child's environment is what it was.
The two installs — interactive and headless — were byte-identical
copies and are now one `launch_child()` function, which is also what
makes a computed index affordable.

**Amended during implementation (was 3 entries; grounds below).**
**Grounds corrected 2026-09-03 (PR #60, review finding F7): the
install is unchanged, the reasoning first written here was not.** The
empty values are load-bearing: git collects every matching
`credential.helper` and `credential.<url>.helper` into **one** ordered
list, an empty value clears whatever has accumulated so far, and a
later entry appends to it. Without a reset an operator's global helper
is in that list ahead of ours and answers the push, so the session
pushes as the operator — the exact bug D12 exists to stop.

There are *two* resets, and the honest description of why is **belt and
braces**, not a measured necessity. The evidence originally quoted here
— `git config --get-all 'credential.https://github.com.helper'` showing
gh's helper first under the 3-entry install — is the wrong instrument:
that command reports raw configuration, it does not model credential
resolution, and `GIT_CONFIG_*` entries carry command-line precedence,
i.e. they are applied after system, global and local. On those
semantics the 3-entry form would very likely have won too. What the
two resets buy is that ours ends up the only helper in the list
*however* the operator configured theirs, on either key; the resets are
idempotent, and the failure they guard against is silent. That is worth
one extra pair of environment variables. The `insteadOf` rewrite is
load-bearing for a separate reason:
this repository's `origin` is SSH, and an SSH remote never consults a
credential helper.

**First check:** confirm how git invokes a helper configured with an
argument (`GIT_TRACE=1 git credential fill`), and use the `!f() { … };
f` shell-snippet form instead if the absolute-path-plus-argument form
does not reach the script. *(Done — the absolute-path-plus-argument
form reaches the script; this check is what turned up the ordering bug
above.)*

**Proves it (Acceptance 6):** a test in
`scripts/ops/tests/work_test.sh` that runs the helper directly against
the stub mint (asserting the two lines and that no token reaches
`stderr`), plus a real two-push check performed once during
implementation on a scratch branch — the helper is invoked twice and
mints twice — recorded in the run folder. After any run,
`git config --list` in the parent shell gains nothing and
`.git/config` is untouched.

## T8 · `scripts/ops/work.sh` — result signalling — D14, D15, D23

### P4 (first) — the Claude Code JSON shape

`claude -p "say hi" --output-format json | jq 'keys'`. The spec names
agy's keys from measurement (`status`, `response`) but not Claude
Code's. Write the mapping against what it prints; if the harnesses
disagree on key names, keep one `response_text()` and one
`process_status()` helper with a per-harness `jq` expression each —
two expressions, one mapping.

Headless (D14):

| observed | exit |
|---|---|
| `WORK-RESULT: ok …` | 0 |
| `WORK-RESULT: refused …` / `blocked …` | 2 |
| process status `ERROR` (timeout, crash), or the wrapper's 124 | 1 |
| status `SUCCESS` and no `WORK-RESULT` line | 1 |

The line is taken from the *decoded* response text, never grepped out
of the raw JSON (a JSON string escapes the newline, so `grep
'^WORK-RESULT:'` on raw bytes silently never matches). Last match
wins. The raw output is echoed to stdout before the mapping so nothing
a session said is swallowed. Exit 2 is deliberately the same code as
`refuse()` (72): a caller asks whether the number was worked, not
which layer declined (D23).

**Amended 2026-09-03 (PR #60, round-1 review finding AT-5; D15 and D23
as amended).** The interactive row maps too, and is no longer `exec`ed.
`exec timeout … ` returns the *wrapper's* status, so the row could hand
a caller 124 when the cap fires and 125/126/127 for `timeout`'s own
errors — outside #36 D8's 0/1/2 vocabulary — and a harness exiting 2
for a reason of its own read as a designed refusal. The child now runs
in the foreground, inheriting stdin, stdout, stderr and the terminal
(which is all "the operator's terminal *is* the session" required;
`timeout` was already an un-`exec`ed process between the two), and
`work.sh` waits and maps: child 0 → 0, anything non-zero → 1 with the
raw status named on stderr and, for 124, the cap named. Exit 2 is
produced by the launcher's own refusals and by D14's parsed
`refused`/`blocked`, never forwarded from a child.

**Proves it (Acceptance 7, 15):** four `fixture_tree` scenarios driving
the stub `agy` through `$AGY_JSON` — one canned document per row of
the table — asserting the four exits; plus four on the interactive row,
through a pty (`script -qec`, which the no-tty guard of T9 now
requires), asserting stub 0 → 0 and stubs 3, 2 and 124 → 1 with the raw
status in the message and the cap named for 124. The mapping of 3 to 1
is itself the proof that `exec` is gone.

*(Amended 2026-09-03, PR #60, round-2 finding R2-1.* ***"the child now
runs in the foreground" was only half true.*** *Dropping `exec` left
`timeout`'s `setpgid(0,0)` — previously a no-op, because `timeout` was
the process the shell had made the terminal's foreground group leader —
free to put the harness in a background process group with the tty
still attached: it could neither read the terminal (SIGTTIN) nor set raw
mode (SIGTTOU) and would stop with a live token until the cap. The
interactive wrapper is therefore `timeout --foreground` (see T5). The
four pty scenarios were blind to it because the stub `claude` never
touched the terminal, so the first of them now also asserts that the
child's process group **is** the terminal's foreground group and that a
real `tcsetattr` against the pty succeeds — the proof that the exit map
is not the whole of D15. The group comparison is the deterministic
assertion and it gates the raw-mode probe: SIGTTOU is delivered to the
whole process group, so an unguarded probe stops the suite rather than
failing it.)*

## T9 · `.claude/commands/work.md` (NEW) — D16

A new directory and one hand-authored file whose whole body is
`scripts/ops/work.sh $ARGUMENTS`, with two lines of front matter
description. It is outside `TARGET_DIRS` (sync_agents.py:639), so the
drift gate ignores it and this is not a compiler bypass. No
`.agents/workflows/` twin.

**Amended 2026-09-03 (PR #60, round-1 review findings AT-1, N2 and
Argus's open item (a); D16 as amended).** The body is not
`scripts/ops/work.sh $ARGUMENTS`. Its `` !`…` `` form runs in the
harness's own non-TTY bash *before* the turn, so for the four
`claude-code`-pinned personas it reached D5's interactive row and
`exec`ed a session that cannot start for want of a terminal — after
minting a one-hour credential, which is what D11's grounds forbid; and
a legitimate exit 2 surfaced as a failed tool call. The body is now
`` !`HEADLESS=1 scripts/ops/work.sh $ARGUMENTS; echo "[work.sh exit
$?]"` ``, with `allowed-tools` widened to match the mode-prefixed line,
and the cwd-relative property stated in the `description` rather than
left to be rediscovered. The complementary half is in `work.sh`, beside
the harness-binary preflight and **before** the mint: an interactive
row with no tty on stdin or stdout exits 1 naming `HEADLESS=1`, having
minted nothing and started no child — the guard that also holds for
cron, a CI step and a subagent's bash.

**Proves it (Acceptance 10, 14):** `/work 43` in an interactive session
runs the script with `43` (shown once during implementation);
statically, the file contains exactly one command line and it is the
`HEADLESS=1 … ; echo "[work.sh exit $?]"` form, and `git status` shows
nothing added under `.agents/workflows/`. In `work_test.sh`: the
interactive row invoked with stdout captured (i.e. no tty) exits 1, the
message names `HEADLESS=1`, and `$MINTS` and `$LAUNCHES` are both
empty; the same stage under `HEADLESS=1` launches and exits 0.

## T10 · `AGENTS.md` — dispatch has one door — D17

A new `###`-level subsection inside "Working the tracker: pick, claim,
work, hand off" (97–156), after the labels paragraph that ends at 148
and before "There is no STATUS.md" (150). Under 20 lines, three rules,
in D17's order: `work.sh <n>` is how a stage starts; no session acts
as a persona it is not (an in-session sub-agent is the acting
persona's own helper from its `delegates_to` list); a bootstrap
dispatch is allowed only when the claim comment declares it in its
first line, naming the persona and the reason.

It must restate nothing already in the file: step 2 (110–115) already
defines the claim, and the labels paragraph already defines the state
machine — the subsection cites them rather than repeating them.

**Proves it (Acceptance 11):** the subsection is present, under 20
lines, and a reviewer check that each of its three sentences appears
nowhere else in AGENTS.md. `scripts/ci/sanitize_check.sh` stays green
(AGENTS.md is not under `personas/`, so the vendor rule does not
apply, but the `home` rule does).

## T11 · `scripts/ops/smoke_launch.sh` (NEW) — D18, D19

`smoke_launch.sh <scratch-issue>`; two runs, three observables each,
each observable a named line so a failure says which one.

- **claude-code / odyssey** (App has `issues: write`): `HEADLESS=1
  work.sh <scratch>` exits 0; the stage's artifact is present in the
  working tree; the newest comment on the scratch issue is authored by
  `evekhm-odyssey-app[bot]`.
- **antigravity / daedalus** (`contents: write`, `issues: read` until
  #47): exits 0; the artifact is present; a commit on the scratch
  branch is authored by `evekhm-daedalus-app[bot]` — acceptance item
  5's "commit *or* comment", and the stock fallback agent pushes
  nothing, so it proves persona load and token handoff at once.
- Identity is never checked with `gh api user` (403 for an App token,
  findings Q7); the token-side check is `GET
  /installation/repositories`.
- The claim/handoff half of the daedalus run is written as a check
  that *expects* 403 and prints `BLOCKED ON #47` without failing the
  script. When #47's permission lands, that check passes and the line
  disappears **with no edit to the script** — so the expectation is
  written as "403 → report; 200/201 → pass", never as "must be 403".

**Proves it (Acceptance 9):** the script exits 0 today with the
`BLOCKED ON #47` line present. Run it once during implementation
against a scratch issue and cite the output in the PR.

**Amended during implementation.** Two changes, both forced by the run
itself:

- *The artifact observable is the errand's artifact, not the stage's.*
  The implement stage declares no artifact at all ("the output is code
  or a review") and the build stage's is a whole plan, while this run is
  explicitly one measured launch rather than a stage. odyssey's artifact
  is `runs/smoke-<n>/odyssey.md` (gitignored, so the tree stays clean);
  daedalus's is the `SMOKE-<n>.md` inside the commit it pushes, read
  back through the contents API — a second local copy would prove
  nothing the pushed file does not.
- *The errand lives in the scratch issue's body, which the script
  writes.* `work.sh` has exactly one prompt literal for both harnesses
  (D6); a smoke test needing a second one would be testing something
  `work.sh` does not do. Writing the body makes a re-run identical to
  the first run.

## T12 · `docs/SPEC.md` — the living spec — Acceptance 13, and the #25 contract

Three in-place amendments keeping their IDs, plus one new entry:

- **`personas.compiler` (123–153):** the antigravity target sentence at
  126–127 becomes `.agents/agents/<name>/{agent.md,agent.json}` — the
  markdown file with `name`/`description`/`tools` frontmatter and the
  assembled body, the sidecar with the resolved model and the
  sub-agent flag, and one clause saying the harness reads only
  `agent.md` and that a `model:` key there voids the agent.
- **`ops.dispatch` (277–320):** the two-harness table, `HEADLESS`
  beside `DRY_RUN`, the target preflight, the mint step, and the
  `WORK-RESULT` exit mapping — noting that exit 2 now covers both a
  launcher refusal and a launched persona's refusal (D23).
- **`identity.bots` (89–109):** one sentence that `work.sh` mints at
  launch and hands the token to the child only, pointing at the new
  entry.
- **NEW `ops.identity`, placed after `ops.dispatch` (ends 320):** the
  persona-identity handoff — mint immediately before launch, only for
  the persona launched, never under `DRY_RUN`; `GH_TOKEN`/
  `GITHUB_TOKEN` overwritten in the child and never inherited; `git`
  reached through `scripts/auth/git-credential-persona` installed via
  `GIT_CONFIG_*` in the child's environment with an `insteadOf`
  rewrite, because an installation token outlives neither a 90-minute
  cap nor an SSH remote.

**Also verify, changing nothing (Acceptance 12):** `work.sh <n> --as
<persona>` is still the whole argv contract, every mode added here is
an environment variable, and nothing under `scripts/placement/` exists
yet to mint or export — the interface
`intent/25-execution-model/plan.md` T4 is written against. If #25
lands first, its `mint_app_token.py --require-repo --quiet` flags are
additive and T6's plain call keeps working; confirm with a grep rather
than an assumption.

**Proves it:** `scripts/ci/spec_check.sh` on the implementing PR — it
touches behaviour-bearing paths, so the diff must carry `docs/SPEC.md`
(no `Spec-impact: none` escape).

## Acceptance → task

| # | task | # | task |
|---|---|---|---|
| 1 | T5 | 8 | T5 |
| 2 | T6 | 9 | T11 |
| 3 | T1, T2, T3 | 10 | T9 |
| 4 | T5 | 11 | T10 |
| 5 | T6 | 12 | T12 |
| 6 | T7 | 13 | T12 |
| 7 | T8 | 14 | T9 |
| | | 15 | T8 |
| | | 16 | T6 |

## Readings taken

Two places where the spec admits more than one implementation and this
plan chose; both are cheap to overrule by editing the row.

1. **D6's wrapper applies to the interactive row too** — `timeout
   $((T*60+60)) claude --agent …`. D6 says "the whole child is wrapped"
   without qualifying the mode. The consequence is that an interactive
   session is killed at the persona's cap; if that is wrong, D6 should
   say "headless". *(Amended 2026-09-03, PR #60, AT-5: the reading
   stands, the `exec` in front of it does not. The wrapper's 124 was
   exactly the code that escaped #36 D8's vocabulary, so the row now
   runs the child in the foreground and maps its status — see T8.)*
2. **The `WORK-RESULT` line is read from the decoded response text**,
   not from `.response` by name, so one code path serves both
   harnesses. D14 names `.response`, which is agy's key; Claude Code's
   is resolved by P4.

## Pull request

One PR per task group is not worth the review cost here: the compiler
chain (T1–T3) and the launch chain (T4–T8) each only make sense whole,
and T9–T12 are small. One implementing PR, body carrying `Closes #43`,
the plan sync, the P1–P4 run folder, and the `BLOCKED ON #47` line
from T11. Gates: `sync_agents.py --check` and `--verify`,
`compiler_roundtrip.sh`, `sanitize_check.sh`, `spec_check.sh`,
`bash -n` on `work.sh`, `git-credential-persona` and
`smoke_launch.sh`, and `work_test.sh`.
