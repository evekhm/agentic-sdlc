# Plan: the CI gates (drift, sanitization, spec check)

**Issue:** #6 · single PR (bootstrap compression, see spec.md).
Stacked on #5 (the compiler), which is stacked on #2 (`config/`),
which is stacked on #1 (`personas/`).

1. `scripts/ci/sanitize_check.sh` — one pass over `git ls-files`,
   three rules (D3), failure mode first: `path:line: <label>` per
   finding with the matched text withheld (D4), a summary naming the
   three ways to fix it, exit 1. Errors — no git, a missing tracked
   file, an unreadable or malformed allowlist — die rather than
   report a clean tree. Patterns assembled from fragments so the file
   never contains the prefix it hunts for (D5).
2. `scripts/ci/sanitize_allowlist.txt` — the six `<rule> <path>`
   exemptions (D6), each carrying its reason inline.
3. `scripts/ci/spec_check.sh` — port the predecessor's script: keep
   the fail-closed env contract and the pure-bash marker parser,
   re-scope the behavior-bearing path list to this repository (D9),
   drop the predecessor's issue numbers, and add the positional
   local mode (D12).
4. `.github/workflows/ci-gates.yml` — three jobs (D1). `drift`
   installs pyyaml + jsonschema and runs `--check` then the roundtrip
   (D2); `sanitize` runs the scanner on the bare checkout; `spec-check`
   fetches full depth, guards that both SHAs are present, writes the
   body to a file and runs the script against the merge base (D10).
   `contents: read`, actions pinned by major tag (D11).
5. `docs/SPEC.md` — move `ci.gates` out of "Agreed, not yet built"
   into Capabilities citing #6 and `intent/6-ci-gates/`, and reword
   the Deployment status paragraph: enforcement is active from this
   PR's merge, not absent.
6. Evidence. Three throwaway branches off this one, one violation
   each — a hand-edited compiled target; a file carrying an obviously
   fake `ghp_` shape; a `scripts/` touch with no spec update and no
   marker. Each is opened as `demo(#6): …`, watched until Actions
   reports the FAILURE, then closed unmerged and its branch deleted.
   The three URLs and their failed check names go in the handoff.

Verification: all three gates run locally green on this branch; the
sanitize gate re-run with a planted fake token shows it red; the spec
gate run against `bootstrap/5-compiler` shows both verdicts (red
before the `docs/SPEC.md` edit, green after); the demonstration PRs
supply the failing half in CI itself.

Not in this change: any gate that needs a model (review automation is
#8/#9), the label state machine (#4), and branch protection — making
these checks *required* is a repository setting a human applies after
the first green run, not a file in the diff.
