Title: Rung 3: Atlas — second reviewer, consensus live
Labels: bootstrap
Depends: argus-port
---
Port the second independent reviewer (predecessor's sidecar runtime,
`evekhm-atlas-bot`) and wire consensus per protocol v2: agree/dispute
per finding ID, keyed to Decision IDs where the spec provides them.

The deployment pin in `config/deployments.yaml` must resolve Atlas to
a **different model family** than Argus — that rule lives in config,
not in either persona.

**Done when:** both reviewers review the same PR, and at least one
disagreement is resolved by evidence in the thread — the
dual-reviewer value proposition, demonstrated.

**Depends on:** {{argus-port}} (consensus wiring and protocol
in place).
