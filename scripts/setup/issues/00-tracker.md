Title: Bootstrap tracker — the system builds itself
Labels: bootstrap
Depends:
---
The index of all bootstrap work, grouped by rung. The rung principle:
**each rung is built using only the mechanism the previous rung
established** — that ladder is the workshop's narrative.

Pick-up protocol (AGENTS.md, "Working the tracker"): find the first
unchecked line whose issue is claimable (no `in-progress` label, all
its dependencies closed), open it, read its last handoff comment,
claim, work, hand off. Rungs run in order; within a rung, issues run
in parallel wherever their `Depends on` lines allow.

**Rung 1 — the loop proves itself manually.** Humans drive sessions
that follow draft persona instructions by hand (wizard-of-Oz); every
artifact already flows through `intent/<issue>-<slug>/` and PRs.

- [ ] {{personas}} — persona schema and canonical sources
- [ ] {{config}} — model tiers, deployment pins, tools
- [ ] {{review-policy}} — REVIEW.md, protocol v2 port

**Rung 2 — the compiler makes personas real.** Sessions stop being
wizard-of-Oz: a session starts *as* a compiled persona, on either
harness.

- [ ] {{compiler}} — sync_agents.py, one build to all targets
- [ ] {{ci-gates}} — drift, sanitization, spec check

**Decisions — claimable any time, needed before Rung 3.**

- [ ] {{label-taxonomy}} — one label state machine must win
- [ ] {{bot-identities}} — Athena/Daedalus/Cassandra accounts

**Rung 3 — automate the seams, most-tested first.** From here the
system builds itself in the strict sense: each automation change is
itself an issue through the loop.

- [ ] {{argus-port}} — event-driven review workflow
- [ ] {{atlas-port}} — second reviewer, consensus live
- [ ] {{athena-headless}} — intake automation on `intent:new`

**Rung 4 — close the loop.**

- [ ] {{cassandra}} — watchers, control bands, seeded incident

House rules: state lives in this tracker and the issue threads, never
in a status file or a chat transcript. Tick a line only when its
issue closes (gate merged). `hold` label anywhere = all automation
stops.
