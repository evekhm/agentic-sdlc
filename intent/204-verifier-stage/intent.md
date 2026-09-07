# Intent: the verifier seat — the review stage's verification protocol

**Issue:** #204 · **Author:** athena (`evekhm-athena-app[bot]`) ·
**Status:** accepted on merge of this PR

## Problem

Split from #199, which proposed formalizing two standing session seats
and is now scoped to seat 1 (the advisor persona). Seat 2 is the
verifier: the independent check that has run session-side for two
waves under a charter that exists only as a file in one operator's
home directory. Three things are wrong with that arrangement.

- **The review rung has no protocol, only a politics.** `REVIEW.md`
  is thorough about what a finding *is* — severity tiers, the closed
  `high` list, the round funnel, consensus keyed to Decision IDs,
  label derivation, the cost envelope. It is silent on what a
  reviewer must **do** before it is entitled to a verdict.
  `personas/lifecycle.json`'s review rung carries the entire
  instruction in one line: *"Review the open pull request against its
  spec and plan; post findings and a verdict, never a merge."* Between
  that line and a verdict sits everything the waves actually taught:
  never trust the implementer's summary, re-run every gate yourself in
  the PR's worktree, reproduce claims rather than read them, check
  whether the pasted evidence could have come from `origin/main`,
  mutation-test the tests whenever coverage is the point, and read the
  job log behind every green check. None of that is written anywhere a
  reviewer compiles from.
- **The protocol that does exist is folklore.** It lives at
  `~/persona-verifier.txt` on one machine, is versioned with nothing,
  and survives session turnover only by a dated handoff file. It is
  not a draft: two waves of practice produced it, wave-1's core track
  merged 6/6 with every defect caught by it and none by CI, and the
  fabrication catalog in `docs/PLAYBOOK.md` is its output. That is the
  argument for graduating it into the repo, not for leaving it in a
  home directory where drift from the rules it cites is invisible.
  On 2026-09-07 the same folklore failed in the small: a second
  verifier session was launched into the charter because the handoff
  file still named a session that had ended, and only a live peer
  check caught the double seat before two verdicts existed on one PR.
- **The charter bundles three powers that are not review.**
  Merge-on-AGREE, fix-prompt authoring, and learning capture travel
  with the protocol today, and bundled they make the seat look like a
  seventh persona. Each has an owner elsewhere: consensus merge
  retires the first (#64/#151), the repair path owns the second (#82),
  the exercise convention owns the third (#181). Separate them and
  what remains is not a persona at all — it is the depth of a stage
  that already exists.

Underneath all three: **review has been the pipeline's weakest rung
precisely where it looks strongest.** Across batch 2, 4/4 pull
requests were blocked on defects the boards rendered green — argus
exiting without reading the diff, atlas dying on a model id, both
refusing while their checks stayed green (tracked centrally at #191).
Two defects a mechanized check would have caught for free: PR #188
shipped a commit authored under bot id `181938210`, which does not
exist on GitHub, and PR #185 carries no `Closes #74`, so merging it
would not close its issue.

## Proposed outcome

The verifier is **the review stage executed to a written protocol**,
not a new actor. Four parts.

1. **The protocol lands where reviewers read it.** `REVIEW.md` gains
   the section it lacks: what a review must do before it is entitled
   to a verdict. `personas/skills/review-protocol.md` gains the
   application rules that bind argus to it, and
   `personas/lifecycle.json`'s review `dispatch_brief` stops being the
   whole instruction and starts pointing at it. All of it reaches the
   runtimes through `scripts/sync_agents.py`, the compiler that
   already owns the agent briefs — **no new template mechanism and no
   new document** (AGENTS.md, "No document sprawl").
2. **The mechanizable half becomes code first.** `REVIEW.md`'s
   enforcement map is explicit that *"every rule must exist in code
   before a prompt may describe it in the present tense"*. The
   deterministic checks — one closing keyword; the branch matching the
   persona convention; the claim comment posted under the persona App
   identity; every commit authored as
   `<user-id>+<identity>@users.noreply.github.com` with the id
   verified to exist — are mechanizable today and land as a gate with
   tests **before** the prose describes them. The judgment steps
   (mutation testing, evidence provenance, reading the job log) stay
   prompt-enforced and are declared as such in the enforcement map,
   with the human seat named as their backstop.
3. **The seat's temporary powers stay in the temporary document.**
   `docs/PLAYBOOK.md` already exists to hold process that is true now
   and will not be true later; merge-on-AGREE, the fix-prompt handoff
   and the observations log belong there, carrying an explicit expiry
   pointer to #64/#151. `REVIEW.md` takes only what outlives the
   exercise. The alternative — writing an admittedly interim power
   into the durable policy doc — makes #64 responsible for unwriting
   it.
4. **No cast change.** `personas/lifecycle.json` derives a stage's
   owner as every `personas/*.yaml` whose `stage` list contains it,
   and `personas/schema.json` carries a closed stage enum. A `verify`
   rung would touch the enum, the compiler, the label taxonomy,
   `scripts/ops/work.sh` and `docs/SPEC.md` §lifecycle to buy a
   capability the review rung already has. The verifier is argus's
   stage, run to the protocol, with a human holding the merge.

**Done when:** a reviewer dispatched at the review rung — automated or
session-side — is handed the verification protocol through its
compiled brief rather than through an operator's home directory; the
four ladder checks run as code with tests, wired into CI, and fail on
the two real defects that motivated them (a non-existent bot id in a
commit author, a missing closing keyword); `REVIEW.md`'s enforcement
map lists every new rule as either code-enforced or prompt-enforced
with a named backstop; the interim merge power is written once, with
its expiry, in `docs/PLAYBOOK.md`; and `docs/SPEC.md` §review.policy
carries the upsert.

## Affected users and systems

- **Argus and Atlas** — both compile from the review-stage sources, so
  both inherit the protocol; neither gains a verb. They remain
  comment-only, and `REVIEW.md`'s invariant that *"a human is the sole
  merge authority on every path"* is untouched by this work.
- **The verifier session and its operator** — the seat stops being a
  file on one machine. Its temporary powers become documented and
  dated rather than inherited by rumor.
- `REVIEW.md` (the protocol section, the enforcement-map rows),
  `personas/skills/review-protocol.md`, `personas/lifecycle.json`
  (review `dispatch_brief`), the compiled agent briefs
  (regenerated, never hand-edited), `docs/PLAYBOOK.md` (seat
  mechanics with expiry), `docs/SPEC.md` (§review.policy), one
  extended or added CI gate plus its test suite, and
  `.github/workflows/ci-gates.yml`.
- `scripts/ci/lifecycle_advance.sh` **only if** the spec places the
  pre-merge checks there: it already owns the closing-keyword rule
  post-merge, which is why the spec must decide between extending it
  and standing up a sibling gate rather than duplicating the rule in
  both (AGENTS.md, "Never duplicate code").

## Constraints

- **Code before present tense.** `REVIEW.md`'s enforcement map rule
  is binding on this work specifically: the gate lands before, or in
  the same change as, any prose that describes it as existing.
- **No new authority.** Nothing here grants a bot the verbs
  `approve`, `merge`, `close`, or `edit`. The verifier's merge is a
  human's merge, exercised through an operator-driven session; that
  distinction is the reason this is a stage and not a persona.
- **No new persona, no stage-enum change, no new document.** The
  deliverable is depth in existing files.
- **Not blocked on #181.** A persona's compiled brief *is* the tracked
  launch template this repo already has; #181 generalizes the agy
  implementer dispatch preamble, a different artifact. Recorded here
  so the #199 and #204 specs do not both invent a template home.
- **Specs never hardcode pins.** The protocol names what a reviewer
  must do; it names no model, no harness, and no tier binding
  (AGENTS.md; #1 D3).
- **Narrow before wide.** The fake-green defect class — a check that
  renders green having reviewed nothing — is #191's, with its own
  dispatch. This issue mechanizes the four ladder checks only, and
  leaves job-log reading as a prompt-enforced step.
- **Retires with #64/#151.** The interim merge power is written with
  its expiry condition, so the consensus-merge work has one place to
  strike it rather than a search.

## Open questions

1. **Where the interim merge authority is recorded.** Proposed:
   durable protocol to `REVIEW.md`, seat mechanics (merge-on-AGREE,
   fix-prompt handoff, observations log) to `docs/PLAYBOOK.md`, both
   carrying the expiry pointer to #64/#151. The alternative is
   `REVIEW.md` for both, which makes the power binding rather than
   folklore at the cost of requiring #64 to unwrite it. Decide in
   spec.md.
2. **How wide the mechanized gate is.** Proposed: narrow — the four
   ladder checks, nothing else. The alternative adds the #191 class
   (assert a green check did real work), which is a larger change
   against a moving target. Decide in spec.md.
3. **Where the pre-merge checks live.** `lifecycle_advance.sh` owns
   the closing-keyword rule at merge time; the new checks run before
   merge. Extending it with a `--pr` mode keeps one owner for the
   rule; a sibling gate keeps the merge-time advancer simple. This is
   a discovery step the plan rung resolves, and the spec should state
   only the non-duplication requirement.
4. **Whether the verifier seat needs a declared identity.** The
   session merges under a human's authority and posts under whatever
   credential the operator's shell holds; `scripts/ops/claim.sh`'s
   identity check exists because that goes wrong, and it fired on this
   very issue's first claim attempt. Either the seat is explicitly the
   human (and the record says so), or it needs an identity the ladder
   checks can verify. Decide in spec.md.
