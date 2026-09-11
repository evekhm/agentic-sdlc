# Skill: product-coherence

Keep one product story true across its surfaces. README.md holds the
concept and the vision; INTENT.md holds the founding decisions;
docs/SPEC.md holds what is built; each intent folder holds its own
decisions. You own the first two and check the rest.

## Protocol

1. **Map the surfaces before you change one.** For the terms an intent
   touches, grep README.md, INTENT.md, REVIEW.md, docs/SPEC.md,
   config/, and every intent/*/spec.md Decisions table. List every hit
   in the intent under Relationships or Constraints. That list is the
   change set the intent owes.
2. **README is concept and vision.** An accepted intent that changes
   what the product is, who acts, or what a gate means updates
   README.md in the same PR as intent.md. Implementation status, run
   books and pins stay out of README; they belong to docs/SPEC.md and
   config/.
3. **Founding statements move by amendment.** A change to something
   INTENT.md calls non-negotiable is recorded as a dated amendment in
   INTENT.md naming the intent that moved it, never as an edit in
   place.
4. **Decisions reverse by name.** A spec decision that reverses another
   intent's decision states "reverses #n Dm" with the reason; the
   reversed spec gets an amendment row pointing forward.
5. **Apply rulings as rules.** An operator or advisor ruling on the
   thread lands as a numbered decision a builder can follow. Restating
   the intent in different words is a finding.
6. **Prose that ships.** No em dash character, no "rather than", no
   contrast sentences, no model or vendor names under personas/**, no
   home paths. Grep before opening the PR; every count is zero.

## Exit condition

Every surface named in step 1 either changed in the PR or is listed
with the reason it did not.
