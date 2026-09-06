# scripts/

Every script documents itself in its header comment or module
docstring; that header is the source of truth for flags and edge cases.
This file is the index: what exists, how it is invoked, and what it
touches. Four families plus the persona compiler at the top level.

Conventions shared by all of them:

- **Deterministic tools, no model calls.** bash + git + gh + jq, or
  plain Python. The same inputs always resolve the same way.
- **`DRY_RUN=1` previews.** `work.sh`, `worktrees.sh` and
  `lifecycle_advance.sh` print each mutation instead of performing it
  when `DRY_RUN=1` is set. Reads still run, so every guard is exercised.
  `bootstrap_tracker.sh` has no dry run; it is idempotent instead.
- **Tests are hermetic.** `scripts/*/tests/*_test.sh` stub `gh` and
  `claude`, use temp directories or a temp bare git origin, and fail on
  any attempted write. Run one with `bash <path-to-test>`; each prints
  a `PASS:` line per assertion and exits non-zero on the first failure.

## Top level

| Script | What it does | Invocation | Touches |
|---|---|---|---|
| `sync_agents.py` | The persona compiler (`intent/5-compiler/`). Compiles `personas/*.yaml` + `config/` into per-harness targets: `.claude/agents/` for Claude Code and `.agents/agents/<name>/` for Antigravity. Pure and byte-deterministic, so the drift gate is "rebuild and diff". | `python3 scripts/sync_agents.py` to build; `--check` to diff against committed targets without writing; `--verify` to re-parse the emitted targets; `--root` / `--out` to point at another tree. | Compiled target files only. |

## ci/ — gates run by GitHub Actions

All four are run by `.github/workflows/ci-gates.yml` or
`.github/workflows/lifecycle.yml` and runnable locally with the same
command CI uses (`intent/6-ci-gates/`, `intent/4-labels/`).

| Script | What it does | Invocation | Touches |
|---|---|---|---|
| `compiler_roundtrip.sh` | Seven-step proof for the compiler: schema check, determinism (two builds byte-identical), no drift against committed targets, roundtrip re-parse, a throwaway persona compiles end to end, a source carrying a home path is refused, and lifecycle invalid rungs and advances_on invariants are refused. | `bash scripts/ci/compiler_roundtrip.sh` | Temp directories only. |
| `sanitize_check.sh` | Scans every tracked file for things that must never reach a public repo: home paths, secrets, vendor-specific leakage. Exemptions live in `sanitize_allowlist.txt`, one `<rule> <path>  # reason` per line, scoped to exactly one rule and one file. | `bash scripts/ci/sanitize_check.sh` | Read-only. |
| `spec_check.sh` | The living-spec gate (AGENTS.md "The living spec"). A PR that touches a behavior-bearing path (`scripts/`, `personas/`, `config/`, workflows, AGENTS.md, REVIEW.md) must either change `docs/SPEC.md` or carry `Spec-impact: none — <reason>` in its body. Judges the choice, never the content. | `bash scripts/ci/spec_check.sh` (CI passes the PR context) | Read-only. |
| `lifecycle_advance.sh` | The deterministic stage advancer: the merge is the state transition. On every push to `main` it reads the merged PRs between two SHAs and moves each issue's single `status:*` label up the ladder, applying `hold` and stopping if the labels disagree. | `bash scripts/ci/lifecycle_advance.sh <before-sha> <after-sha>`; `DRY_RUN=1` prints every label change instead. | GitHub issue labels and comments. |

Tests: `scripts/ci/tests/lifecycle_advance_test.sh`.

## ops/ — tools a session runs by hand

| Script | What it does | Invocation | Touches |
|---|---|---|---|
| `work.sh` | One-argument dispatch (`intent/36-dispatch/`). A number is the whole instruction: it resolves an issue or PR, checks every refusal (claimed, held, corrupted labels), picks the owning persona for the current stage, pins the harness, and launches the session. It never claims on the session's behalf. | `scripts/ops/work.sh <issue-or-pr> [--as <persona>]`; `DRY_RUN=1` prints the resolved launch command. | Launches a harness session; reads GitHub, never writes it. |
| `claim.sh` | The claim protocol as one command (AGENTS.md "Working the tracker" steps 1-3, CLAUDE.md "Parallel sessions"). Verifies in order that the issue is open, carries no `hold`, carries no `in-progress` (naming the holder from the last claim comment's author), and that every issue on a "Depends on" line is closed, then that the branch and worktree path are free. Every refusal happens before the first write, so a failing `worktree add` can never leave the mutex held by nobody. It then adds `in-progress`, posts the one-line claim comment, and creates the worktree, printing the path to `cd` into on the last line. A dirty primary checkout is reported and left alone. | `scripts/ops/claim.sh <issue> [<slug>]`; `--release <issue>` removes `in-progress` for the pause case and posts nothing, because the handoff comment is the session's; `CLAIM_ACTOR`, `CLAIM_SESSION` and `CLAIM_STAGE` name the claim; `DRY_RUN=1` prints every mutation as a `would:` line instead. | The issue's `in-progress` label and one claim comment; a new local branch and worktree under `.claude/worktrees/`. |
| `worktrees.sh` | Worktree hygiene (AGENTS.md "Working the tracker", one session, one worktree, one issue). One line per worktree with lock state and whether the lock's pid is alive, dirty count, unpushed commits, merged state, and a verdict: `safe`, `dirty`, `unpushed`, `locked`. | `scripts/ops/worktrees.sh` is read-only; `--prune` removes only `safe` worktrees and local branches merged into `origin/main`, never with `--force`; `--prune-remote` also deletes merged remote branches; `DRY_RUN=1` previews. | Local worktrees and branches; remote branches only with `--prune-remote`. |
| `session_spend.sh` | Aggregates Claude Code transcripts (`*.jsonl`, subagents in subdirectories) into token and USD roll-ups per session, model and day. USD is a list-rate estimate; the cloud bill is authoritative. `--check` adds the two-number health verdict from AGENTS.md "Cost of execution": cache hit rate and tokens per message. | `scripts/ops/session_spend.sh <transcript-dir-or-file> [--since D] [--until D] [--out DIR] [--check] [--ttl-compare]`. Needs `jq` and `gawk`. | Read-only; writes reports only under `--out`. |

Tests: `scripts/ops/tests/work_test.sh`,
`scripts/ops/tests/worktrees_test.sh`,
`scripts/ops/tests/session_spend_test.sh`,
`scripts/ops/tests/claim_test.sh`.

## setup/ — one-time provisioning

| Script | What it does | Invocation | Touches |
|---|---|---|---|
| `bootstrap_tracker.sh` | Provisions the bootstrap tracker on GitHub: the base labels, the bootstrap backlog issues, and the pinned tracker issue that indexes them. Idempotent: labels are kept, issues are matched by exact title so numbers stay stable, and an existing tracker body is never overwritten because its checkboxes are live state. | `scripts/setup/bootstrap_tracker.sh`; `--labels-only` stops after the labels. Review `issues/*.md` before running; there is no dry run. | GitHub labels and issues. |
| `wif_setup.sh` | Provisions model access for the HOSTED runner (#146): Workload Identity Federation pool + GitHub OIDC provider, a predict-only custom role, a service account bound to it, the impersonation binding scoped to this repository, and the four Actions **variables** `unattended.yml` reads (`WIF_PROVIDER`, `WIF_SERVICE_ACCOUNT`, `CLAUDE_VERTEX_PROJECT_ID`, `ANTIGRAVITY_PROJECT_ID`). No cloud key at rest and no secret handled. Idempotent; an existing pool from a sibling project is reused, not duplicated. Until it has been run, `WIF_PROVIDER` is unset and every reviewer job reports a named skip and stays green. | `GCP_PROJECT=<project> GH_TOKEN=<admin token> bash scripts/setup/wif_setup.sh` — `--dry-run` prints the mutations, `--check` verifies and exits 1 on anything missing. Needs gcloud authenticated as owner/editor of `GCP_PROJECT`, and a token with repository ADMIN (the operator bot's PAT has push only). | GCP services, WIF pool/provider, custom role, service account, IAM bindings; GitHub repository variables. |
| `issues/*.md` | The bodies of the bootstrap backlog issues, one file per issue, numbered in ladder order. Reviewable in a PR before anything is filed. | Read by `bootstrap_tracker.sh`. | Nothing; data files. |

**Run on this repository 2026-09-04** against `GCP_PROJECT=agent-quality-lab-01`:
nine items created (`sts.googleapis.com`, the `unattendedVertexPredict` role,
the `unattended-personas` service account, its role binding, the
`evekhm/agentic-sdlc` impersonation binding, and the four variables), six
verified as already present — the `github-actions` pool and its provider were
reused from the predecessor's `argus_setup.sh` provisioning.
`wif_setup.sh --check` passes with `Missing: 0`.

Two steps no script can do, both still open unless a human has done them:

1. **Enable the Claude models you pin in Vertex Model Garden** for the project
   (console: Vertex AI → Model Garden, one click per model, per project).
   Until then every predict call fails with a permission or "model not found"
   error even though WIF is correct.
2. **Repository Settings → Actions → General**: allow the actions the workflow
   uses — `actions/checkout`, `actions/setup-python`, `actions/cache`,
   `google-github-actions/auth`. If the banner says this is managed at the
   organization level, an org owner must allow them there. The operator bot's
   PAT cannot read or set this (404 on `actions/permissions`).

## auth/ — GitHub App identities for the personas

Each persona is its own GitHub App. The full procedure, including the
two clicks GitHub itself requires, is in
[`scripts/auth/README.md`](auth/README.md); the short version:

| Script | What it does | Invocation |
|---|---|---|
| `create_all_apps.py` | Walks every persona in `app_manifests.yaml` through App registration, skipping any that already has an `app_id`. | `python3 scripts/auth/create_all_apps.py` |
| `create_github_app.py` | The same flow for one persona: writes the pre-filled manifest form, exchanges the code, records the ids into `personas/<name>.yaml`. | `scripts/auth/create_github_app.py <persona>` |
| `discover_installations.py` | Lists an App's installations to find the `installation_id` that goes into the persona's authority block. | `scripts/auth/discover_installations.py <persona>` |
| `mint_app_token.py` | Mints a one-hour installation token for a persona from its private key and prints only the token. Interactive sessions use this; Actions use `actions/create-github-app-token` instead. | `export GH_TOKEN=$(scripts/auth/mint_app_token.py <persona>)` |
| `_github_app.py` | Shared JWT and key-lookup helpers imported by the two scripts above. Not a CLI. | imported only |
| `app_manifests.yaml` | Name, description and permissions for each persona's App. | data file |
