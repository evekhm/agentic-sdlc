# Spec: Amend #64 D16 for VM Poller Dispatch Consumption and Adapter --as Argument

**Issue:** #288 · **Status:** Approved (approval = merge of this PR) ·
**Author:** athena (`evekhm-athena-app[bot]`) ·
**Open questions:** none

## What is being built

This specification defines Amendment r5 to `intent/64-autonomous-loop/spec.md` (issue #64), reconciling Decision D16 and Decision D19 with the autonomous dispatch architecture landed on `main`:

1. **Placement adapter `--as "$persona"` argument**: Authorize and require `scripts/ci/lifecycle_advance.sh` to pass `"$issue" --as "$persona"` when invoking placement adapters (`scripts/placement/<placement>/run.sh`). Both `vm-local` and `gh-actions` placement adapters require `<number> --as <persona>` in their command-line interface. This supersedes D16's original phrase "with the issue number and nothing else" and resolves the specification discrepancy tracked under defect #284.
2. **VM poller dispatch row consumption and record-and-return**: For `vm-local` placements, `scripts/ci/lifecycle_advance.sh` appends the `dispatch` row to the issue loop ledger and calls the adapter. When running inside GitHub Actions, `scripts/placement/vm-local/run.sh` performs record-and-return (logging delegation to the operator VM poller and exiting 0). The external VM poller daemon (`scripts/placement/vm-local/poll.sh`, specified in #251 D2 and D5) consumes unconsumed `dispatch` ledger rows on the operator VM, claims the issue, and executes the local launch. `.github/workflows/lifecycle.yml` preserves its triggers (`push` to `main` only) and permissions block (no `actions: write`), maintaining the token boundaries of #64 D23, D25, and D26.
3. **D19 scope boundary clarification**: Clarify that D19's file list and prohibitions bound solely issue #64's own implementing pull request (PR #257). D19 imposes no restriction on subsequent issues (such as #251 modifying `scripts/ops/work.sh` under #251 D8).

```text
intent/64-autonomous-loop/spec.md     # Amendment r5 added (D32, D33, D34) and D16/D19 qualified
intent/288-d16-vm-poller/spec.md      # Approved design specification for issue #288
intent/288-d16-vm-poller/intent.md    # Status updated to Accepted
```

Files outside `intent/**` are **not** touched by this pull request.

## Decisions

| ID | Decision | Rationale |
|---|---|---|
| D1 | **Placement adapter `--as "$persona"` invocation argument.** `lifecycle_advance.sh` passes `"$issue" --as "$persona"` when invoking placement adapters. Passing `--as "$persona"` is authorized and required across placement adapters (`vm-local`, `gh-actions`), matching each adapter's command-line interface (`<number> --as <persona>`). D16's original phrase "with the issue number and nothing else" is superseded by this requirement. | Resolves Open questions 1 and 6. Both placement adapters check for `--as <persona>` and exit with an error if it is missing. Passing the persona explicitly allows adapters to resolve execution ceilings and harness bindings deterministically without inspecting git branches or issues. |
| D2 | **VM poller dispatch row consumption and record-and-return delegation.** For `vm-local` placements, `lifecycle_advance.sh` appends the `dispatch` row to the loop ledger and invokes `scripts/placement/vm-local/run.sh "$issue" --as "$persona"`. When executed inside GitHub Actions (`GITHUB_ACTIONS=true`), `scripts/placement/vm-local/run.sh` executes record-and-return: it logs delegation to the operator VM poller and exits 0. The external VM poller daemon (`scripts/placement/vm-local/poll.sh`, specified in #251 D2 and D5) consumes unconsumed `dispatch` ledger rows on the operator VM, acquires the issue claim, and executes the local launch. The loop ledger remains append-only and immutable; Themis remains the single trusted writer of loop ledger comments (#64 D23). `.github/workflows/lifecycle.yml` retains its triggers (`push: branches: [main]` only) and permissions block (no `actions: write`), preserving #64 D23, D25, and D26 token boundaries. | Resolves Open questions 2 and 3. Builders require private keys and execution environments that are hosted on the operator VM to prevent exposing builder credentials to pull request workflows. Record-and-return allows GitHub Actions to record the authoritative loop ledger transition without requiring runner-to-VM direct communication or elevated workflow permissions. The daemon and polling mechanisms belong to #251, while #64 records the consumption contract and boundary integrity. |
| D3 | **D19 scope boundary clarification for subsequent issues.** D19's file list and prohibitions define the scope boundary solely for issue #64's own implementing pull request (PR #257). D19 imposes no prohibition or constraint on other issues (including #251 modifying `scripts/ops/work.sh` under #251 D8). | Resolves Open question 4. Each issue defines its own scope boundary in its specification. A scope list written to bound one PR cannot prevent subsequent issues from evolving repository tooling under their own accepted designs. |
| D4 | **Amendment r5 integration into `intent/64-autonomous-loop/spec.md`.** Amendment r5 is appended to `intent/64-autonomous-loop/spec.md` as `## Amendment r5 (2026-09-09)` containing decisions D32, D33, and D34. Decisions D16 and D19 in the main Decisions table of `intent/64-autonomous-loop/spec.md` gain in-place revision notes citing D32, D33, and D34. Acceptance item 16 is qualified by an in-place note and acceptance item 29 is appended. | Resolves Open questions 1 and 7. Appending a dated amendment section preserves the historical decision record established in r1 through r4. Adding in-place revision notes in D16 and D19 ensures readers of the main table see that those clauses have been qualified by Amendment r5. |
| D5 | **Defect #284 resolution and disposition.** Amendment r5 resolves the specification defect behind #284. Code implementation was completed in PR #294 on `main`. | Resolves Open question 5. PR #294 updated `lifecycle_advance.sh` to pass `--as "$persona"`. Amendment r5 updates the normative specification to match the codebase, resolving the discrepancy. |
| D6 | **Path authority and living spec boundary.** The pull request for this issue touches only files under `intent/**` (`intent/288-d16-vm-poller/spec.md`, `intent/288-d16-vm-poller/intent.md`, `intent/64-autonomous-loop/spec.md`), staying within Athena's path authority. `docs/SPEC.md` is not modified by this pull request (already documented under `loop.autonomous` in PR #294 and PR #297; `spec_check.sh` requires no living spec update for diffs confined to `intent/**`). | Resolves Open question 8. Athena's declared write authority is restricted to `intent/**`. `spec_check.sh` explicitly exempts pull requests touching only `intent/**` from living spec obligations. `docs/SPEC.md` lines 1153 to 1170 already describe the continuous poller architecture. |

## Acceptance

- **AT-1 (D1)** In `scripts/ci/lifecycle_advance.sh:1159`, the placement adapter invocation passes `"$issue" --as "$persona"`.
- **AT-2 (D1)** In `scripts/placement/vm-local/run.sh` and `scripts/placement/gh-actions/run.sh`, both adapters enforce `<number> --as <persona>`, exiting with `usage: run.sh <number> --as <persona>` when `--as` is omitted.
- **AT-3 (D2)** In `scripts/placement/vm-local/run.sh:58-61`, running with `GITHUB_ACTIONS=true` and non-dry-run logs delegation to the operator VM poller and exits 0 (record-and-return).
- **AT-4 (D2)** In `.github/workflows/lifecycle.yml`, the workflow trigger remains `push` to `main` and the permissions block contains no `actions: write` scope.
- **AT-5 (D3)** In `intent/64-autonomous-loop/spec.md`, D19 contains the explicit clarification that its scope list bounds solely #64's own implementing pull request and imposes no restriction on other issues.
- **AT-6 (D4)** `intent/64-autonomous-loop/spec.md` contains `## Amendment r5 (2026-09-09)` with decisions D32, D33, and D34, plus in-place r5 notes in D16 and D19.
- **AT-7 (D5)** Defect #284 is documented as resolved by Amendment r5, aligning specification with code on `main`.
- **AT-8 (D6)** `git diff --name-only origin/main` contains only files under `intent/**`.
- **AT-9 (D6)** `bash scripts/ci/spec_check.sh origin/main` exits 0 with notice that no behavior-bearing paths changed.
- **AT-10 (D6)** `bash scripts/ci/sanitize_check.sh` exits 0 on all modified files.

## Open questions

none
