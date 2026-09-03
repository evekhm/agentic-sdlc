# Plan: README operator walkthrough

**Issue:** #35 · **Spec:** spec.md (Approved) · **Author:** daedalus

Committed before the README exists, per the lifecycle. The change
ships no behaviour — nine sections of prose plus two documentation
edits — so no contract tests are owed: every acceptance row in spec.md
is a deterministic text check, and each check below cites the Decision
ID it derives from. Hard dependency (D14): the implementing PR is
branched from and merges after #36's, because `scripts/ops/work.sh`
must exist at its base commit.

## Order of work

1. **`README.md` — the nine sections, in order (D1, D2).** Write the
   file top to bottom from the briefs below: one reader, the operator
   at the keyboard, named in the opening paragraph; no sentence
   instructs an agent. Nine `## ` headings byte-identical to spec.md's
   list, in that order, nothing nested past `###`.
   *Check:* `grep -c '^## ' README.md` is 9; the extracted heading list
   diffs clean against the spec's; `grep '^#### ' README.md` is empty.

2. **Explain, never duplicate (D3).** Every rule stated normatively
   elsewhere gets one sentence plus a link to its owner; one line says
   README is normative for nothing and loses every disagreement.
   *Check:* `grep -c '^|' README.md` is 0; no severity-tier list and no
   per-label semantics;
   `grep -niE 'status:[a-z-]+ *(->|=>|→) *status:' README.md` is empty
   and the five stage names appear in ladder order (D7).

3. **Hold the ceiling (D4).** At most 150 lines, exactly one diagram
   (section 1), no section over 25 lines. Section 5 is the pressure
   point: five rungs in 25 lines is five short paragraphs, not five
   sub-headings.
   *Check:*
   ```bash
   [ "$(wc -l < README.md)" -le 150 ]
   awk '/^## /{if(p)print NR-p; p=NR} END{if(p)print NR-p+1}' README.md |
     sort -rn | head -1                      # must be <= 25
   awk '/^`{3}/{n++} END{print n+0}' README.md   # must be 4 (2 blocks)
   ```

4. **One command, and only one (D5).** The single fenced shell block
   holds `scripts/ops/work.sh <n>` and nothing else. One sentence says
   that for a harness the script cannot start it prints the equivalent
   instruction instead — the instruction itself is never reproduced
   (#36 D10). Setup commands are links, not instructions (D11).
   *Check:*
   ```bash
   awk '/^`{3}(bash|sh)$/{n++} END{print n+0}' README.md    # must be 1
   awk '/^`{3}(bash|sh)$/{f=1;next} f&&/^`{3}/{f=0} f&&!/^ *(#|$)/' \
     README.md          # must print exactly: scripts/ops/work.sh <n>
   ```

5. **Forbidden words, stricter than CI (D6).** No vendor, product,
   harness or model-family name, no model ID, no absolute home path,
   no credential shape, no per-persona procedure text. CI applies the
   vendor rule only inside `personas/**`, so this one is run by hand
   on README and read at the merge gate; the patterns are *extracted*,
   never retyped, so they cannot drift from the scanner or the pins.
   *Check:*
   ```bash
   V=$(grep -m1 '^VENDOR_RE=' scripts/ci/sanitize_check.sh | cut -d"'" -f2)
   H=$(grep -oE 'harness: [a-z-]+' config/deployments.yaml |
       cut -d' ' -f2 | sort -u | paste -sd'|')
   grep -niE "$V|\\b($H)\\b" README.md      # must print nothing
   ```
   Then `bash scripts/ci/sanitize_check.sh` for the home-path and
   credential half, which CI does enforce on every tracked file.

6. **`docs/SPEC.md` — amend `docs.structure` (D13).** Extend the
   existing entry, no new capability ID: README.md is the
   operator-facing entry point, its audience is the operator at the
   keyboard (D1), it explains and never duplicates and loses every
   disagreement with the documents it links (D3), and it is bounded by
   a fixed nine-section list and a line ceiling (D2, D4).
   *Check:* the entry names `README.md` and states the
   loses-every-disagreement rule; `scripts/ci/spec_check.sh` exits 0.

7. **`INTENT.md` — correct the layout line (D13).** In "Repository
   layout (target)", the flagship-trio line drops the
   "(README/REVIEW.md to come)" annotation entirely: REVIEW.md has
   landed too, so both halves are stale.
   *Check:* that line no longer matches `grep -n 'to come' INTENT.md`;
   the surrounding block is otherwise byte-identical.

## Section briefs

What each section must say and what it links. The implementer writes
prose from these — no design decisions remain.

1. **The loop in one picture.** What this repository is, in a few
   sentences, plus the only diagram: an issue entering at `intent:new`
   and walking plan → design → build → implement → review, one PR per
   rung. Links INTENT.md for why the system exists.
2. **Before you start.** Three prerequisites, one sentence each — a
   clone, the six App private keys, `gh` and `jq` — and no
   registration or provisioning steps (D11). Links
   `scripts/auth/README.md` and `scripts/setup/`.
3. **File the change.** Humans file; no persona files intake issues,
   Atlas included, whose findings belong in the PR thread; every issue
   enters with `intent:new` and no `status:*`, which is what makes it
   stage `plan`. Links AGENTS.md, "Before filing an issue" (D9).
4. **Type the number.** The operator's whole typed input is one
   command on the issue or PR number — a number is the whole
   instruction, and a PR number resolves to its issue. Links
   `docs/SPEC.md` `ops.dispatch` (landing with #36).
5. **What happens at each gate.** One short paragraph per rung —
   plan, design, build, implement, review — naming the persona, the
   artifact its PR carries, and, in words, that merging it moves the
   item on. Links `docs/SPEC.md` `lifecycle.labels`.
6. **What you merge.** The three clauses, once, for all five gates: a
   merged PR is the human product owner's acceptance, a closed PR is a
   rejection and is not relitigated, and editing a Decision row in the
   PR *is* the decision. Links REVIEW.md, "Merge is the escape hatch"
   (D8).
7. **Review.** Two independent reviewers pinned to different model
   families — which families is a `config/` fact, named nowhere here;
   until the automation lands the operator runs the one command on the
   PR number, which prints both instructions and launches neither
   without `--as <persona>`. Links REVIEW.md and `review.policy`.
8. **When something is wrong.** `hold` halts all automation absolutely
   while present, `blocked` stops and reports, more than one
   `status:*` is corrupted state, `review:3` escalates to
   `status:review-stuck`; which rung a defect repair re-enters at is
   open and asserted nowhere. Links `lifecycle.labels` and #32 (D10).
9. **Where the rules actually live.** One sentence each for AGENTS.md,
   INTENT.md, `docs/SPEC.md`, REVIEW.md and `docs/CONTEXT.md`, plus
   the line that a tenth topic is a link from here and never a tenth
   section, and that README loses any disagreement (D2, D3).

## Merge gate

Before the implementing PR is opened, every check above passes, plus
`scripts/ci/spec_check.sh`, `scripts/ci/sanitize_check.sh` and
`scripts/ci/compiler_roundtrip.sh` at exit 0. PR requirements:

- Body says `Closes #35` and cites #36's implementing PR as the
  dependency it is based on (D14).
- Base branch is #36's implementing branch, once that exists; the
  README PR must not be opened against the default branch before
  #36's implementing PR merges, because `scripts/ops/work.sh` must be
  present at the base commit.
- One PR carries all three files: `README.md`, the `docs/SPEC.md`
  `docs.structure` amendment and the `INTENT.md` layout fix (D13).
- If any check here proves impossible against the written spec, that
  is a spec question returned to the product owner, not a judgment
  call: amend this plan in the same PR and say which D-row moved.
