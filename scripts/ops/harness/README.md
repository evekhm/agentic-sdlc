# Context statusline and session priming (#330)

One `statusline.sh` renders in both Claude Code and Antigravity;
`install.sh` is the only thing that wires it in. Nothing here is
active until `install.sh` has been run on the machine — the scripts
being tracked and merged does not install them.

## Install

```
scripts/ops/harness/install.sh
```

This writes three settings files, all machine-local and gitignored,
so it needs to be run once per machine (VM rebuild, new laptop, fresh
user account):

- `~/.claude/settings.json` — `statusLine.command` points at
  `statusline.sh` (Claude Code, user scope: every project on this
  machine, including worktrees).
- `~/.gemini/antigravity-cli/settings.json` — the same
  `statusLine.command`, only if that directory already exists (i.e.
  Antigravity is installed on this machine). If Antigravity is
  installed *after* this script has run, run it again.
- `<repo>/.claude/settings.json` — `autoCompactWindow: 180000` and the
  `SessionStart` hook that primes a session with its seat's newest
  handoff (project scope: this repo only, via `${CLAUDE_PROJECT_DIR}`
  so worktrees resolve without an absolute path).

Each edit keeps a `.bak` of the file it touched the first time it's
written, and only ever touches the `statusLine`, `hooks.SessionStart`
and `autoCompactWindow` keys — nothing else in those files is
disturbed.

## Activate

**Restart the session.** Both harnesses read `statusLine` and
`SessionStart` once, when a session starts. Running `install.sh` while
a Claude Code or Antigravity session is already open does not change
that session's statusline; open a new one.

## Verify

```
scripts/ops/harness/install.sh --check
```

Read-only. Confirms the scripts are executable, both harnesses'
`statusLine.command` are wired and identical (no drift), the
`SessionStart` hook is wired, then actually renders one line against a
synthetic payload and checks the side-channel file it writes. Exits 2
if anything is broken; the most common failure is "statusLine not
wired" when `install.sh` has never been run on this machine.

```
scripts/ops/harness/install.sh --show
```

Prints the relevant keys (`statusLine`, `hooks`, `autoCompactWindow`)
from all three settings files, for a quick diff against what
`--check` expects.

## Uninstall

```
scripts/ops/harness/install.sh --uninstall
```

Removes `statusLine` from both harnesses' user settings and the
`SessionStart` hook from the project settings, leaving every other key
in those files untouched.

## Reading the line

```
ctx <used>K/200K <pct>%[ <tag>]  $<cost>  tok <in> in/<out> out  cache <hit>%[ <ttl>]  <model>[ [<effort>]][ · <seat>]
```

`<used>` is measured against the 200K working ceiling (`AGENTS.md`,
"Context ceiling"), never the model's raw context window (200K on some
models, 1M on others) — that ceiling is the point past which a request
reprices entirely at the long-context premium, on either harness.
`<tag>` warns before either harness's own compaction runs: yellow
`wrap soon` at 60% (120K), red `WRAP NOW` at 70% (140K), red
`COMPACTING` at 90% (180K, Claude Code's own `autoCompactWindow`, set
by `install.sh` above). Full display contract, the side-channel file
schema, and acceptance tests:
[`intent/330-statusline-instrumentation/spec.md`](../../../intent/330-statusline-instrumentation/spec.md).

## Environment overrides

- `AGENTIC_CONTEXT_CEILING` (or `CLAUDE_CONTEXT_CEILING`) — working
  ceiling in tokens, default `200000`.
- `AGENTIC_CTX_DIR` (or `CLAUDE_CTX_DIR` / `AGY_CTX_DIR`) — side-channel
  directory, default `~/.claude/context`.
- `AGENTIC_SEAT` (or `CLAUDE_SEAT`) — seat name shown in the line,
  exported by `ops/waves/seat.sh` when a session is seated.

## Files

- `install.sh` — everything above; also the one place that knows the
  three settings file paths.
- `statusline.sh` — the renderer, one `jq` pass plus pure bash; also
  writes `$CTX_DIR/<session_id>.json` atomically for hooks and
  external observers.
- `session-start.sh` — the `SessionStart` hook body: resolves and
  injects the newest handoff for the session's seat.
- `newest-handoff.sh` — resolves the newest seat handoff across linked
  worktrees.
- `newest-dated.sh` — shared date/numeric-suffix ordering resolver
  used by `newest-handoff.sh`.

Tests: `scripts/ops/tests/harness_test.sh`.
