# Spec: deployment bindings (config/)

**Issue:** #2 · **Status:** Approved (approval = merge of this PR) ·
**Open questions:** none

Bootstrap compression per intent/1-personas/spec.md D10 applies here
too: planning and implementation land in one PR, recorded once, not
a precedent.

## Decisions

| ID | Decision |
|----|----------|
| D1 | Three files, three axes: `model_tiers.yaml` = tier→model per harness; `deployments.yaml` = persona→harness pins; `tools.yaml` = capability→tool per harness. One axis per file so a swap edits exactly one place. |
| D2 | `config/` is the only layer where vendor/model/tool names may appear; CI (#6) greps everything else. |
| D3 | Sub-agents carry no deployment pin: they inherit the dispatching persona's harness and resolve tiers through it. |
| D4 | The reviewer constraint is data, not prose: `constraints.distinct_model_families: [argus, atlas]` in deployments.yaml, machine-checked by CI (#6) against model_tiers.yaml at REVIEW tier. |
| D5 | Optional capabilities without a mapping compile to the `fallback` text declared in tools.yaml (generated fallback, D4 of #1); required capabilities without a mapping fail compilation. |
| D6 | Harness-local model aliases are allowed only when verified on the target deployment; where an alias is a known trap (the claude "sonnet" alias resolving to a non-enabled model), the exact ID is mandatory and the trap documented inline. |

## Acceptance

- All three files parse as YAML.
- Every persona in `personas/*.yaml` (kind: persona) has a pin;
  every capability named in any source has an entry in tools.yaml.
- argus and atlas pins resolve to different model families at
  REVIEW tier (manual check until #6).
