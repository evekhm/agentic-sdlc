Title: Rung 4: Cassandra — watchers, control bands, seeded incident
Labels: bootstrap
Depends: bot-identities label-taxonomy athena-headless
---
Close the loop. Deterministic watchers compare live metrics to
control bands (`bands.yaml`), responding in proportion: log at 1σ,
diagnose read-only at 2σ, propose at 3σ — and a proposal is a new
issue labeled `intent:new`, which re-enters the loop at INTAKE.

Includes the **seeded incident** mechanism for the workshop's
closing act: a re-runnable, presenter-triggered control-band breach
that Cassandra diagnoses and converts into the next intent.

**Done when:** the seeded breach produces a Cassandra-filed
`intent:new` issue and {{athena-headless}} picks it up — the loop
demonstrably closes without a human initiating.

**Depends on:** {{bot-identities}}, {{label-taxonomy}},
{{athena-headless}}.
