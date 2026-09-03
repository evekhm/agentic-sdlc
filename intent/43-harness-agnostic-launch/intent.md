# Intent: harness-agnostic launch

**Issue:** #43 · **Stage:** plan · **Author:** athena
(`evekhm-athena-app[bot]`)

## Problem

`scripts/ops/work.sh` (#36, D10) can start exactly one harness. Its
launch table maps `claude-code` to `claude --agent <persona> "#<n>"`
and every other harness to the empty string, which the script reports
as *"this harness is started by hand"* and exits 0 on. The pin in
`config/deployments.yaml` therefore decides nothing at launch time:
`daedalus` and `atlas` are pinned to `antigravity` and neither can be
started by the one command the whole system is supposed to run
through.

Two consequences, both observed this week:

1. **Stages get impersonated.** Because the pinned harness will not
   start, a persona's stage gets worked by a subagent of whatever
   session happens to be open. The artifact lands, the lifecycle
   advances, and the persona whose judgment the stage exists to apply
   never ran. The system's central claim — that a role is a compiled,
   pinned, reproducible thing — is unfalsifiable while any session can
   act as any persona.
2. **The launched session posts as the operator.** `work.sh` passes no
   credential, so the child inherits whatever `gh` identity is ambient.
   Six GitHub Apps exist (#7) and `scripts/auth/mint_app_token.py`
   mints for any of them, but nothing on the dispatch path calls it.
   On 2026-09-03 a daedalus stage produced a plan and PR #46 whose
   handoff comment had to be posted by the operator bot, because the
   session had no daedalus token — and the tracker cannot tell a
   persona's work from a human's if both write under the same login.

Beneath both sits a third, measured this morning
(`runs/2026-09-03_agy-headless/findings.md`, agy 1.1.24): the
antigravity launch drafted on #43 **cannot work even once the table
row exists.** `agy --agent <name>` loads
`.agents/agents/<name>/agent.md`; the compiler emits
`agent.json` + `config.yaml` + `instructions.md`, which agy ignores. It
falls back to the stock agent, logs one line to a file nobody reads,
prints nothing, and **exits 0**. A bare `#<n>` prompt to that stock
agent burned 160,818 input tokens and hit the print timeout. So the
failure this issue must prevent is not a crash; it is a silent,
expensive success.

## Proposed outcome

One command starts any persona on its pinned harness, as itself.

1. **Both harnesses launch from the pin.** `work.sh`'s launch table
   gains an `antigravity` row, so `config/deployments.yaml` — and
   nothing else — decides which harness a number starts. This is the
   single line #25's `vm-local` adapter is built to call (D16), and
   the precondition #44 is waiting on.
2. **The launched session is the persona.** `work.sh` mints the owning
   persona's App token immediately before launch and hands it to the
   child process only, so what the session writes to GitHub is
   authored by `evekhm-<persona>-app[bot]`. `DRY_RUN=1` prints the
   identity's name and mints nothing.
3. **The launch is not silently wrong.** The compiled antigravity
   target changes to the layout agy actually reads, and the launch
   preflights that the target exists before spending a token on a
   prompt.
4. **Dispatch has one door.** A thin `/work` command for the
   interactive harness that is exactly `scripts/ops/work.sh
   $ARGUMENTS`, and a rule in AGENTS.md that persona stages are
   dispatched through `work.sh` and never impersonated by another
   persona's subagent.
5. **It is proven, not asserted.** A headless smoke test on a scratch
   issue, one run per harness, checking three observables: the exit
   code, the artifact, and the author of the commit or comment the
   session produced.

## Affected users and systems

- **The presenter**, who gains one command for every persona and loses
  the habit of hand-driving a stage in an open session.
- **`scripts/ops/work.sh`** — the launch table, a preflight, a mint
  step, and two environment-variable modes. The argv contract
  (`<number> [--as <persona>]`) does not change: a number is still the
  whole instruction (#36, D7).
- **`scripts/sync_agents.py` and `.agents/agents/**`** — the
  antigravity emitter, and every compiled antigravity target with it.
- **`scripts/auth/`** — one new credential helper, because `git push`
  does not read `GH_TOKEN` and an App token expires inside a long
  session.
- **AGENTS.md** — the dispatch rule; **`.claude/commands/`** — the new
  `/work` door.
- **#25** (the `vm-local` adapter calls this line), **#44** (blocked
  until an antigravity persona is launchable), **#47** (three Apps are
  registered `issues: read`, so a token minted for them cannot claim).

## Constraints

- **A number is the whole instruction.** No flag may name a stage, a
  folder, an artifact, a branch, a prompt or a model (#36, D7).
  Anything this issue adds is an environment-variable mode, following
  `DRY_RUN`'s precedent.
- **Deployment facts stay in `config/`.** Which harness, which model:
  one edit to `config/deployments.yaml` or `config/model_tiers.yaml`
  and nothing else (#2 D1/D2; #25 D18). Vendor and model names never
  enter `personas/**` — the sanitize gate enforces it.
- **Credentials by name only.** A token never appears in argv, in a
  log line, in a file, or in `DRY_RUN` output (#25 D3; the
  trusted-posting skill, rule 2).
- **The launcher never writes to GitHub.** The claim belongs to the
  session it starts, not to the dispatcher (#36).
- **Measured, not assumed.** agy's behaviour is pinned to agy 1.1.24 as
  observed in `runs/2026-09-03_agy-headless/findings.md`; anything not
  in that file is called out as unverified rather than guessed.
- **This issue does not fix #47.** Raising three Apps to `issues:
  write` is a human action on github.com that only the App owner can
  take.

## Open questions

None open. The two questions filed on #43 were answered by measurement
before this intent was written, and both answers are load-bearing
enough to be spec decisions rather than prose here:

- *Does `agy -p` return non-zero on refusal?* No. A prompt-forced
  `REFUSED: …` reply exits 0 with JSON `status: "SUCCESS"`; exit code
  and `status` track process health only.
- *Does it read the compiled instructions when started outside the
  repo root?* It reads no repository file at all without `--add-dir`,
  and it never reads `instructions.md` — the file it looks for is
  `agent.md`.

Both land in `spec.md` in this same folder, with the measurements
cited.
