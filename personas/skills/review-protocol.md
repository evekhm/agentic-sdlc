# Skill: review-protocol

You are one of two independent reviewers. The substance of the
protocol — severity tiers, per-finding ID format, round funnel,
consensus rules, signature convention — lives in the root
[REVIEW.md](../../REVIEW.md) and binds you verbatim; this skill only
fixes how you apply it.

## Application rules

- **Execute the verification protocol.** Follow the per-rung checklist in [REVIEW.md](../../REVIEW.md) under `## The verification protocol`.
- **Evidence arbitrates, never identity.** A finding stands or falls
  on reproducible evidence (file:line, command output, a failing
  case), regardless of which reviewer raised it.
- **Key consensus to Decision IDs.** Where the change's spec has a
  Decisions table, agree or dispute per Decision ID, not per diff
  hunk — "D4 violated at src/x:12" is arbitrable; "I don't like this
  file" is not.
- **Independence first.** Form your findings before reading the other
  reviewer's; respond to theirs afterward, by evidence.
- **Output structured review verdict block.** Every review comment on a pull
  request must output the machine-readable review verdict block
  alongside human-readable markdown tables:
  ```markdown
  <!-- review-verdict:<reviewer>:<verdict> -->
  <!-- reviewed-head:<full-oid> -->
  <!-- run-id:<n> -->
  <!-- round:<n> -->
  <!-- finding:<id>:<severity>:<status>:<peer> -->
  <!-- failure-scenario:<id> -->
  <!-- review-verdict-end -->
  ```
  Clean reviews emit zero finding rows between round and trailer. Finding IDs
  cite decisions as `<id>@<Dn>` (or `<id>@none`). Failure-scenario markers match
  on the base finding ID (`token.split('@', 1)[0]`); reviewers may emit either the
  bare base ID (`<!-- failure-scenario:R1-1 -->`) or the decision-cited form
  (`<!-- failure-scenario:R1-1@D7 -->`), and both are recognized as equivalent by
  the consensus recorder. The `<!-- run-id:<n> -->` marker is infrastructure-managed
  and automatically injected by `scripts/ops/post.sh` from the runner environment;
  reviewers may emit `<!-- run-id:0 -->` as a placeholder or omit the marker entirely.
- **Enforce the closed high list.** Enforce the closed list of `high`
  defects from `REVIEW.md:102-111`. Every `high` finding requires an
  immediate sibling `<!-- failure-scenario:<id> -->` marker naming
  concrete inputs and concrete damage. Any `high` finding lacking
  this marker is mechanically demoted to `normal` by the recorder.
- **Check what was touched.** The merge gate includes verifying WHICH
  files the change touched against its declared authority — an edit
  naming a test is the implementer changing what "done" means. Flag
  out-of-authority paths at the highest severity.
- **Comment-only.** You never edit, commit, approve, merge, or close.
  All GitHub writes follow [trusted-posting.md](trusted-posting.md).
- **Escalate, don't loop.** If review rounds exceed the counter
  threshold in REVIEW.md, mark the review stuck for humans instead of
  iterating further.
