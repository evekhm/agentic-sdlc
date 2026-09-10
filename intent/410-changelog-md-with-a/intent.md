# Intent: CHANGELOG.md with hard CI merge gate, full-history bootstrap, and persona/process update

**Issue:** #410 · **Author:** athena (`evekhm-athena-app[bot]`) ·
**Status:** accepted on merge of this PR

## Problem

There is no chronological, human-readable record of what shipped in the repository and why.
Three existing documents appear related but serve different purposes:

- `docs/SPEC.md` is a living system spec, gated by `scripts/ci/spec_check.sh` (the `spec-check` job in `.github/workflows/ci-gates.yml`). It is organized by stable capability IDs and written in present tense describing current capabilities. It specifies what the system does today, not what changed, why, or when.
- `docs/CRITICAL_PATH.md` is an operational status log owned by the advisor seat to track in-flight progress toward the autonomous loop milestone. It is an operational log, not gated by CI, not curated for a general reader, and not a permanent record of shipped features.
- `README.md` is specified (#35) to describe the system's target design and architectural vision; it explicitly does not narrate build status or feature history. Furthermore, it has separately drifted on facts about the live system (personas, harnesses, mechanics).

Net effect: nobody — including operators, maintainers, and reviewers — has an accessible, plain-English trail of what was built, in order. This surfaced concretely upon inspecting PR #406's diff: substantial behavior shipped with no accompanying human-readable summary anywhere in the repository.

## Proposed outcome

1. **New `CHANGELOG.md` at repo root:**
   - Reverse-chronological human-readable log recording merged PRs that changed behavior.
   - Entry structure: Date (YYYY-MM-DD), descriptive title/summary referencing the PR (#<n>) and issue (#<m>), followed by 1–3 concise sentences explaining what changed, why, and the operational impact.
   - Upserted per PR (same living-document discipline as `docs/SPEC.md`), not wholesale regenerated. Git history remains the detailed archive of diffs and commits; `CHANGELOG.md` provides the curated summary.

2. **Hard CI Merge Gate (Mechanically Enforced):**
   - Extend CI enforcement so any PR touching behavior-bearing paths (`scripts/`, `personas/`, `config/`, `.github/workflows/`, `AGENTS.md`, `REVIEW.md` — identical to `scripts/ci/spec_check.sh`) MUST either touch `CHANGELOG.md` in its diff or include a machine-marker line in the PR body (e.g. `Changelog: none — <reason>` or `Changelog-impact: none — <reason>`).
   - The check must be fail-closed, strictly grep-matched (requiring the em dash and reason), and configured as a required status check on `main` branch protection so that the merge actor (`Themis`) refuses PRs missing the entry or marker.

3. **Persona and Process Updates:**
   - `AGENTS.md`: Add a dedicated section ("The changelog", sibling to "The living spec") defining the upsert obligation, marker syntax, and format rules binding all agents.
   - `REVIEW.md`: Update review guidelines so reviewers (`argus`, `atlas`) verify changelog entries for factual accuracy and conciseness against the PR diff (and verify the validity of bypass reasons).
   - `personas/*.yaml`: Review implementer and reviewer persona configurations to ensure duties and authority correctly reflect this obligation.

4. **Curated Full-History Bootstrap:**
   - Perform a one-time historical backfill of `CHANGELOG.md` covering merged PRs from repository inception to current `main`.
   - Curated to highlight substantive behavior changes (features, major architectural evolutions, security/credential model enhancements, significant fixes), while filtering out noise, typo fixes, purely mechanical chore commits, review iteration rounds, and superseded experiments.

5. **`README.md` Fact Alignment & Drift Repair:**
   - Audit `README.md` against current `docs/SPEC.md` capabilities and repository state during the bootstrap pass.
   - Repair drifted facts (personas, harnesses, dispatch mechanics, hooks) discovered during the audit.

## Affected users and systems

- **Operators & Observers:** Gain an accessible, chronological summary of repository changes and feature deliveries.
- **Implementers (`odyssey`, `coder`):** Incur a mandatory check on behavior-bearing PRs: draft a changelog entry or provide an explicit bypass marker.
- **Reviewers (`argus`, `atlas`):** Review changelog entries for accuracy, clarity, and adherence to standard formats.
- **Merge Gate & CI (`Themis`, `.github/workflows/ci-gates.yml`, `merge_gate.sh`):** CI rejects PRs touching behavior-bearing paths without an entry or valid marker.
- **Repository Standards:** `AGENTS.md`, `REVIEW.md`, `README.md`, `docs/SPEC.md`.

## Constraints

- **Mechanical, fail-closed CI:** The check must fail closed if behavior-bearing files change without a `CHANGELOG.md` update and without an exact marker.
- **Path parity:** The behavior-bearing path definition must remain identical to `scripts/ci/spec_check.sh`.
- **Exact marker syntax:** Grep-matched format with em dash and reason; paraphrasing is rejected.
- **Non-duplication:** Summarizes intent and user/system impact, rather than duplicating git log commit hashes and file diffs.
- **Standard 5-rung lifecycle:** This PR introduces only `intent/<issue>-<slug>/intent.md`. `spec.md` with numbered Decisions follows upon acceptance; code, scripts, bootstrap, and tests follow upon spec approval.

## Relationships

- **Complements `docs/SPEC.md`:** `SPEC.md` specifies current system state by capability ID; `CHANGELOG.md` specifies chronological progression by PR and date.
- **Complements `docs/CRITICAL_PATH.md`:** `CRITICAL_PATH.md` tracks in-flight operational status toward the autonomy milestone; `CHANGELOG.md` records completed deliverables.
- **Follows #6 (living spec gate):** Reuses the proven pattern of `scripts/ci/spec_check.sh` and CI gate enforcement.
- **References PR #406:** The concrete impetus demonstrating the need for clear chronological summaries on merged PRs.
- **Repairs #35 drift:** Resolves factual drift in `README.md` identified during feature evolution.

## Open questions

1. **Gate implementation architecture:** Should `scripts/ci/spec_check.sh` be generalized to check both `docs/SPEC.md` and `CHANGELOG.md` in one pass, or should a dedicated `scripts/ci/changelog_check.sh` and distinct CI job (`changelog-check`) be created?
2. **Marker syntax naming:** Should the bypass marker be `Changelog: none — <reason>` or `Changelog-impact: none — <reason>` (for exact symmetry with `Spec-impact: none — <reason>`)?
3. **Themis / `merge_gate.sh` integration:** Does `scripts/ci/merge_gate.sh` need a dedicated conjunct verifying the changelog check status, or is the GitHub Actions required status check sufficient to block merge?
4. **Bootstrap granularity and grouping:** How should historical entries be grouped in `CHANGELOG.md` (e.g., by release wave / date / PR number), and what specific filter criteria determine whether a historical PR is substantive enough for an entry?
