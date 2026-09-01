# Intent: the CI gates (drift, sanitization, spec check)

**Issue:** #6 · **Status:** accepted on merge of this PR

## Problem

Every standard this repository has written down is currently
prompt-enforced. AGENTS.md says the compiled targets are generated and
must never be hand-edited; nothing stops a hand edit from merging.
AGENTS.md says a behavior-bearing PR updates `docs/SPEC.md`; nothing
notices when one does not. `docs/SPEC.md` itself says so out loud —
"CI enforcement of this spec does not exist yet: every rule below is
convention-enforced."

A convention that only a careful reader enforces is a convention that
holds until the first hurried session. The predecessor system shows
the failure mode exactly: `adk-agents` ships a committed `.env`
password *alongside* an unused credential-scanner skill
(`docs/CONTEXT.md` §5). The scanner existed. Nothing ran it. An
invoke-me-maybe skill is not a control.

## Proposed outcome

Three deterministic gates on every pull request, each a script a
contributor can run locally with the same command CI runs:

- **drift** — `scripts/sync_agents.py --check` plus the compiler
  roundtrip: the committed targets must equal a fresh build, so a hand
  edit under `.claude/agents/` or `.agents/` cannot merge.
- **sanitize** — one scan over every tracked file for home paths,
  credential shapes, and vendor names inside `personas/`. Committing
  the leak becomes impossible rather than discouraged.
- **spec check** — a PR touching behavior-bearing paths updates
  `docs/SPEC.md` or declares `Spec-impact: none — <reason>`. The
  living-spec rule stops depending on whoever reviews.

The gates are worth nothing unless they are shown to bite, so this
change also produces the evidence: one deliberately bad pull request
per gate, failed and closed unmerged.

## Affected users and systems

Every future PR, by every actor — human, compiled persona, or
automated workflow. The review automation (#8, #9) inherits a green
baseline it can trust: a reviewer that spends model tokens re-checking
what a `grep` settles is spending them badly. Presenters get the
workshop's sharpest demonstration: edit a compiled file by hand, watch
the merge become impossible.

## Constraints

- Deterministic and local-first: no model tokens, no vendor API calls,
  no network beyond the checkout and the two Python dependencies.
- Read-only: `permissions: contents: read`, no secrets, so the
  workflow is safe on a fork PR.
- One workflow file, three independent jobs — a PR sees all three
  verdicts on one push, not just the first failure.
- No literal of the thing being hidden: a public checker must not
  hard-code a local account name, and must not trip on its own source.
- Enforcement only. A gate decides whether a choice was MADE; whether
  the choice was a good one stays with the two reviewers.

## Open questions

None — resolved in [spec.md](spec.md).
