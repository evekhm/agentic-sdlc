# Plan: one-argument dispatch

**Issue:** #36 · **Spec:** spec.md (Approved) · **Author:** daedalus

Ten tasks; each names its files, the D-rows it satisfies, and the check
that proves it. Lines cite HEAD 710f2f6. Order: T1 and T2 first; then
T3–T5 (need T1); then T6, T7 (need T2, T4); then T8, T9; then T10.

## T1 · `personas/lifecycle.json` (NEW) — D1, D2

`advance_message` is byte-for-byte from `scripts/ci/lifecycle_advance.sh`
lines 258, 279 and 262, and `null` on the two artifact-less rows the
advancer never posts on. `implement.advances_to` is `status:in-review`, a
real rung whose writer arrives with #8/#9. Shown compact here.

```json
{
  "stages": [
    { "stage": "plan", "label": "status:planning", "artifact": "intent.md", "advances_to": "status:spec",
      "advance_message": "Intent accepted (merge = PLAN gate). Next: draft spec.md into the same folder; Approved requires empty Open questions.",
      "dispatch_brief": "Write the intent: the problem, the proposed outcome, the affected systems, the constraints, and the open questions." },
    { "stage": "design", "label": "status:spec", "artifact": "spec.md", "advances_to": "status:build",
      "advance_message": "Spec approved (DESIGN gate). Next: plan.md + failing contract tests citing Decision IDs.",
      "dispatch_brief": "Turn the accepted intent into a spec: numbered decisions with rationale plus an Acceptance list; Approved requires no open questions." },
    { "stage": "build", "label": "status:build", "artifact": "plan.md", "advances_to": "status:implementing",
      "advance_message": "Plan committed (BUILD gate). Next: implementation at a pinned SHA; PR carries diff + plan sync + docs/SPEC.md upsert.",
      "dispatch_brief": "Turn the Approved spec into an ordered plan: files touched, order of work, and the check that proves each task, before any code exists." },
    { "stage": "implement", "label": "status:implementing", "artifact": null, "advances_to": "status:in-review", "advance_message": null,
      "dispatch_brief": "Implement the committed plan at a pinned SHA; the pull request carries the diff, the plan sync, and the living-spec upsert." },
    { "stage": "review", "label": "status:in-review", "artifact": null, "advances_to": null, "advance_message": null,
      "dispatch_brief": "Review the open pull request against its spec and plan; post findings and a verdict, never a merge." }
  ]
}
```

**Proves it (Acceptance 1), asserted by T9:** `jq -e '.stages | length
== 5'`; every `label` is one `scripts/setup/bootstrap_tracker.sh`
creates (112–116); every `stage` is in `personas/schema.json:23`.

## T2 · `personas/skills/resume-protocol.md` (NEW) — D3, D4, D5, D7

Shaped like `personas/skills/trusted-posting.md`: no frontmatter, H1
`# Skill: resume-protocol`, wrapped at 68 columns. D4's seven steps as a
numbered list; a `## Refusals` section giving D5's six conditions in D5's
order; one sentence stating D7. It cites AGENTS.md and never restates the
stage table — that is T4's block. **Proves it:** `sanitize_check.sh`,
whose `vendor` rule (line 77) covers every path under `personas/`, so no
vendor or harness word may appear (D10).

## T3 · `scripts/ci/lifecycle_advance.sh` — D2

**Delete lines 253–289**: the `# --- pick the transition ---` banner,
the `target=""; marker_stage=""; message=""` initialiser, and the whole
`case "$stage" in … esac`, keeping only the `spec` arm's Draft
condition, which stays a script condition and not a row. **Delete
`rank_of()` at 113–120** and its call at 128.

```bash
# near line 65; then replacing rank_of's call at 128 and the deleted case
LIFECYCLE_JSON="$(git rev-parse --show-toplevel)/personas/lifecycle.json"
[ -r "$LIFECYCLE_JSON" ] || die "cannot read $LIFECYCLE_JSON"
rank="$(jq -r --arg a "$stage.md" \
  '([.stages[].artifact] | index($a) // -1) + 1' "$LIFECYCLE_JSON")"
row="$(jq -ec --arg a "$stage.md" \
        '.stages[] | select(.artifact == $a)' "$LIFECYCLE_JSON")" \
  || { fail_issue "no lifecycle row for '$stage.md' (#$issue)"; continue; }
target="$(jq -r '.advances_to' <<<"$row")"
message="$(jq -r '.advance_message' <<<"$row")"
marker_stage="${target#status:}"
```

`marker_stage` derives correctly for all three transitions
(`status:spec`→`spec`, `status:build`→`build`,
`status:implementing`→`implementing`). The Draft override runs only when
`$stage` is `spec`, reusing the `git show` and `grep -Eq` at 272–282 and
setting `target=""`, `marker_stage="spec-draft"` and the unchanged
warning text; the `*)` arm at 285–288 is subsumed by the `jq -ec`
failure. **Proves it (Acceptance 2, 3):** T9 asserts each
`advance_message` appears in `DRY_RUN=1` output read from the JSON by
`jq`, and `grep -rn 'status:spec' scripts/` returns only reads of it.
*Amended in implementation (odyssey):* the header comment at 15–18 was
itself a copy of the artifact→label table, so it was replaced by a
pointer to `personas/lifecycle.json` — without that the Acceptance 2
grep still matched a table.

## T4 · `scripts/sync_agents.py` — D3

Read the file beside the schema (`json` already imported at 58,
`personas/schema.json` already read at 144 — same pattern, no new
dependency). In `compile_all` (545–583) build stage →
`sorted(p["name"] for p in personas if stage in p.get("stage", []))` and
pass the rows and that map into `render_body` (348). Render exactly like
`## Capability fallbacks` (441–453): guard, `## Lifecycle stages`, one
wrapped intro, then a `### <stage>` per row carrying its label, artifact,
sorted owners and `dispatch_brief`. Append after 453, emitted **only**
when `"resume-protocol.md" in persona.get("skills", [])` — D3's "only
into targets whose source declares the skill". Rows in file order; no
hand-authored copy. Add a `verify()` assertion beside 740–748 that each
`### <stage>` is in every such target. **Proves it (Acceptance 4, 5):**
T9, `sync_agents.py --check`, and the two-build diff already in
`compiler_roundtrip.sh` 41–49.

## T5 · `scripts/ops/work.sh` (NEW) — D7, D8, D9, D10

- [x] **Arguments.** One positional issue-or-PR number, `#` optional;
      `--as <persona>` the only flag (D9); `DRY_RUN=1` from the
      environment (D8). A second positional or any other flag exits 1 —
      nothing names a stage, folder, artifact or branch (D7).
      **Preflight:** `set -euo pipefail`; require `gh` and `jq`; read
      `personas/lifecycle.json` or exit 1. All `gh` calls go through one
      `gh_json()` helper so T9 can stub it.
- [x] **Resolve (D9).** If it is a PR: `Closes #<n>` in the body, else
      the `<actor>/<n>-<slug>` branch name, else exit 1 `cannot resolve
      PR #<n> to an issue`.
- [x] **Refusals, in D5's order, before any write**, each exit 2 naming
      the condition: (a) `refused: #<n> carries hold`; (b) `… is closed`
      / `… carries status:review-stuck`; (c) `… carries blocked`; (d) `…
      carries more than one status:* label: <list>`, reported and
      stopped, never guessed and never `hold`; (e) `refused: in-progress
      on #<n> is held by <actor>`, while a claim naming the resolved
      owner is a resume and proceeds; (f) `refused: <persona> does not
      own stage <stage>` when `--as` names a non-owner.
- [x] **Stage** from the single `status:*` label via the JSON;
      `intent:new` with no `status:*` is `plan` (D4). **Owners:** every
      `personas/*.yaml` whose `stage` contains it (D2), sorted; zero
      owners exits 1. **Folder (D6):** one `intent/<n>-*/` → reuse; none
      → derive (title cut at the first `:` or `;`, lowercased, runs
      outside `[a-z0-9]` → `-`, trimmed, truncated to ≤24 at the last
      `-` leaving a non-empty slug); more than one → exit 2 naming them.
      **Branch** `<persona>/<n>-<slug>`.
- [x] **Harness (D10).** `config/deployments.yaml` →
      `personas.<owner>.harness`; no pin exits 1. For `claude-code`,
      exec `claude --agent <persona> "#<n>"`; any other harness prints
      the persona, the target and that same one-line prompt, exit 0.
      **Multi-owner (D9):** more than one owner and no `--as` prints
      both instructions, launches neither, exits 0.
- [x] **`DRY_RUN=1`** prints number, stage, label, owner(s), folder,
      branch, harness and the exact command line, then exits 0 having
      written nothing; reads still run, so the guards are exercised.
      **Exits:** 0 launched or printed, 2 a stated D5 refusal, 1
      unusable input / missing pin / unparsable source. **Proves it:**
      T9 (Acceptance 6, 7, 8, 9).

## T6, T7 · the fan-out — D12

Add `  - resume-protocol.md` to the block `skills:` list of the six
`kind: persona` sources — athena (22), daedalus (21), odyssey (23), argus
(21), atlas (21), cassandra (22) — and to no sub-agent (T6). Then run
`python3 scripts/sync_agents.py` and commit the rebuild; never hand-edit
(T7). **Proves it (Acceptance 4):** `--check` exits 0 and `git diff
--stat` shows exactly the six persona targets and no sub-agent target.

## T8, T9 · proof

**T8 · `scripts/ci/compiler_roundtrip.sh` (D3):** add
`resume-protocol.md` to the throwaway fixture's `skills` (66–96, which
already declares `stage: [maintain]`) and one `assert_in '### maintain'
"$AGENT/instructions.md"` beside line 116, so the generated block is
round-trip-proved on a persona built from scratch.
*Amended in implementation (odyssey):* `maintain` is not a rung of
`personas/lifecycle.json`, and D3 renders all five rungs with owners
derived from the sources rather than the target's own stages, so
`### maintain` can never appear; the asserts are `## Lifecycle stages`,
`### review` and the sorted `- Owner: argus, atlas` instead.

**T9 · tests**, plain bash in the style of
`scripts/ops/tests/session_spend_test.sh` — `set -euo pipefail`,
`pass`/`fail`/`has`, `mktemp -d` fixtures, a banner per scenario naming
the D-row it pins:

- `scripts/ops/tests/work_test.sh` — a stub `gh` first on `PATH`
  emitting canned JSON per number, so every case is hermetic.
  Scenarios: the six D5 refusals exit 2 with the condition named and
  nothing written; `in-progress` claimed by the owner proceeds; a clean
  issue under `DRY_RUN=1` prints all eight fields and exits 0; a PR
  resolved through `Closes #<n>` and through the branch fallback; a
  `status:in-review` issue printing two instructions and launching
  nothing; `--as <reviewer>` launching one; the slug rule over three
  titles, twice, stable and ≤24 chars; an existing folder reused.
- `scripts/ci/tests/lifecycle_advance_test.sh` (NEW directory, mirroring
  `scripts/ops/tests/`) — builds a synthetic range in a temp git repo
  adding each artifact, runs `DRY_RUN=1`, asserts the posted body carries
  the `advance_message` read from the JSON by `jq` so the test holds no
  second copy, plus the Draft case and a compression push adding all
  three. **Acceptance 3, 10:** byte-identity is additionally shown once
  during implementation — capture `DRY_RUN=1` output at 710f2f6 and after
  T3 over the same range into `runs/<YYYY-MM-DD_HHMMSS>/`, diff, and cite
  the empty diff in the PR.

## T10 · `docs/SPEC.md` — D11

Two new entries, placed by dependency, not sorted: `personas.resume`
after `personas.compiler` (ends 134) — the six keys, D4's seven steps, the
generated block; and `ops.dispatch` after `ops.spend` (ends 226) —
arguments, resolution order, refusals and exit codes, `DRY_RUN`. Three
in-place amendments keeping their IDs: `tracker.workflow` (35–42), the
number is the whole instruction; `lifecycle.labels` (163–197), the
advancer reads `personas/lifecycle.json` instead of an inline case; and
`personas.compiler` (108–134), whose assemble sentence at 116–120 gains
the generated ladder block.

## Pull request

One PR, per D14's bootstrap compression. The body carries `Closes #36`,
the plan-sync note and the rebuild evidence. Gates: `sync_agents.py
--check` at 0 with the six rebuilt targets in the diff, plus
`compiler_roundtrip.sh`, `spec_check.sh`, `sanitize_check.sh`, `bash -n`
on both scripts, and both test scripts.
