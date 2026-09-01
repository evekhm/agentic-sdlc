Title: Rung 3: Athena — headless intake on intent:new
Labels: bootstrap
Depends: compiler bot-identities label-taxonomy
---
Automate the front of the loop: an issue labeled `intent:new`
triggers a headless Athena session that brainstorms in the thread
(scope, users, constraints, success) and opens the PR adding
`intent/<issue>-<slug>/intent.md`. The human gate is unchanged:
merge = accepted.

Runtime placement is INTENT.md open question 3 (label-triggered
Actions workflow, agent-farm style, vs presenter-driven interactive
session for v1) — resolve it inside this issue and close the open
question by PR.

**Done when:** filing a labeled issue produces an intent PR with no
human action in between, and the spec pass (Design stage) can be
triggered the same way after the intent merge.

**Depends on:** {{compiler}}, {{bot-identities}}, {{label-taxonomy}}.
