# Spec: the CI gates (drift, sanitization, spec check)

**Issue:** #6 · **Status:** Approved (approval = merge of this PR) ·
**Open questions:** none

Bootstrap compression per intent/1-personas/spec.md D10 applies:
planning artifacts and implementation land in one PR, recorded once,
not a precedent.

## What is being built

```text
.github/workflows/ci-gates.yml     one workflow, three independent jobs
scripts/ci/sanitize_check.sh       the sanitization gate
scripts/ci/sanitize_allowlist.txt  its exemptions, one rule + one path each
scripts/ci/spec_check.sh           the living-spec gate (ported)
scripts/ci/compiler_roundtrip.sh   already exists (#5); this change RUNS it
```

Three gates, one trigger set (`pull_request`, plus `push` to `main`
for drift and sanitize). Each gate is a script; the workflow is the
thin thing that calls it, so every gate is reproducible locally by the
command CI runs.

## Decisions

| ID | Decision |
|----|----------|
| D1 | One workflow file, three INDEPENDENT jobs (`drift`, `sanitize`, `spec-check`). Independent because a contributor should learn all three verdicts from one push; a chain of steps in one job reports the first failure and hides the rest. |
| D2 | The drift gate is `python3 scripts/sync_agents.py --check` AND `bash scripts/ci/compiler_roundtrip.sh`. `--check` alone catches a stale target; the roundtrip additionally proves the build is deterministic and that the emitted targets still carry their resolved model, mapped tools and full skill text (#5, D9). A gate that only diffs cannot tell a correct build from a consistently wrong one. |
| D3 | The sanitization gate scans every TRACKED file for three rules: `home` (an absolute home-directory path with an account segment, or a `$HOME` reference), `secret` (credential SHAPES — GitHub token and fine-grained PAT, AWS access key id, generic `sk-` key, Slack token, private-key block), and `vendor` (a vendor/model/family name inside `personas/**`, which is how #1's D3 stops being a promise). All-caps secret NAMES stay allowed: declaring `ATHENA_BOT_TOKEN` is the point (#1, D6). |
| D4 | The gate never prints the matched text — only `path:line: <label>`. A scanner that echoes a credential into a public build log has published it. The exception is the vendor rule, where the matched word is the whole finding and is harmless. |
| D5 | The gate's own patterns are ASSEMBLED from fragments so the checker's source never contains the literal path prefix it hunts for. A scanner that trips on itself teaches people to write exemptions, and the first real leak lands inside one. The credential regexes need no such trick: a character class is not a match for itself. |
| D6 | Exemptions live in `scripts/ci/sanitize_allowlist.txt` as `<rule> <path>  # reason`, scoped to ONE rule and ONE exact path — never a directory, never all rules. Six entries ship, each a file that implements or documents the pattern (the checker, the compiler's emit-time sanitizer, the spend script that refuses to scan a home directory and its test, and the two specs that state the rule). An unknown rule or a pathless line fails the run. |
| D7 | Site-specific literals (a local account name, an internal domain) are NOT in this checker, by the same reasoning as #5's D8a: hard-coding into a public repository the string you are hiding is the leak it was meant to prevent. The generic home-path rule already catches where such a name actually appears. `~/`-relative references are also out: they carry no account name, and the compiler's emit-time sanitizer — stricter on purpose, because it guards prompts that SHIP — still refuses them. This gate guards the repository. |
| D8 | The spec check is the predecessor's mechanism, ported verbatim in its decision logic and re-scoped to this repository: fail-closed on any unset input or failed diff, marker parsing in pure bash (no grep rc ambiguity), CRLF tolerated, a marker with no reason rejected. Predecessor issue numbers and paths are gone. |
| D9 | Behavior-bearing means a SOURCE of behavior: `scripts/**`, `personas/**`, `config/**`, `.github/workflows/**`, `AGENTS.md`, `REVIEW.md`. Compiled targets (`.claude/agents/**`, `.agents/**`) are deliberately EXCLUDED: they are derived, the drift gate owns them, and a hand edit there must fail as drift — one wrong thing, one gate, one message. |
| D10 | The PR body reaches the script through a file written from an `env:` value, never through `${{ }}` interpolated into a run script — that is code injection. `edited` is in the trigger types so adding the marker to the body re-runs the check without a push. The diff is taken against the MERGE BASE, not the base branch tip, so an advancing base cannot hand this PR another PR's files. |
| D11 | `permissions: contents: read`, no secrets, no model tokens, no vendor API calls; actions pinned by major version tag. The gates must be safe to run on a fork PR and cheap enough that nobody is tempted to skip them. |
| D12 | `spec_check.sh` takes a base ref positionally when run locally and the `BASE_SHA`/`HEAD_SHA`/`PR_BODY_FILE` env contract in CI, and refuses both at once. A gate a contributor cannot run before pushing is a gate that gets discovered as a red X. |
| D13 | Enforcement only, never judgement: the spec gate checks that the choice was MADE, not that the entry or the reason is good. Content is the two reviewers' job (#3, #8, #9). |

## Acceptance

- `python3 scripts/sync_agents.py --check` and
  `bash scripts/ci/compiler_roundtrip.sh` exit 0 on this branch.
- `bash scripts/ci/sanitize_check.sh` exits 0 on this branch, and
  exits 1 naming the file and line when a credential shape, a home
  path, or a vendor name in `personas/` is introduced.
- `bash scripts/ci/spec_check.sh <base-ref>` exits 1 on a diff that
  touches `scripts/` without `docs/SPEC.md`, and 0 once the spec is
  updated or the marker is supplied.
- Three demonstration pull requests, one per gate, each violating
  exactly one of them, each observed FAILING in Actions and then
  closed unmerged with its branch deleted. Their URLs and the failed
  check names are recorded in the handoff comment on #6.
- `docs/SPEC.md` gains `ci.gates` in the same PR, and its Deployment
  status paragraph stops saying CI enforcement does not exist.
