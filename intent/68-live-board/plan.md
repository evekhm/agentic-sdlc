# Plan: a live view of who owns which issue, at which rung

**Issue:** #68 · **Spec:** spec.md (Approved, D1–D11, AT-1..AT-14) ·
**Author:** daedalus (`evekhm-daedalus-app[bot]`)

Four tasks. Each names the files it touches, the steps in order, the
Decision rows it implements, the acceptance tests it makes pass, and
its done-when. **Implement on top of `origin/main` at the SHA the
dispatcher pins; this plan was verified at `dfe7d56`.** Every
`file:line` below was re-read at that commit and at the `bot/68-board`
head `5049ea5`, and where the spec's own citation no longer matches the
tree this plan says so and uses the verified line.

Order: T1 (tests, all red) → T2 (`lib/github.sh` and `board.sh` base) → T3 (parity delta) → T4 (docs) → T5 (gates). T2 and T3 commute with T4. T1 must come first.

**Verified corrections to the spec's citations:**
- **Main tree drift:**
  - D3 cites `docs/SPEC.md:460-465`; that sentence is `:484`.
  - D3 and D7 cite `work.sh:415-428` and `:417-425`; the claim resolution code is `:467-470`.
  - D5 cites `README.md` two-actions sentence at `:6-7`, and `## Where the rules actually live` at `:256`. Both match `main` today. `docs.structure` is `docs/SPEC.md:26`.
- **`bot/68-board` drift (PR #69 shifted after rebase):**
  - D1 cites `render_sessions` (`:162-183`), `render_issue` (`:185-320`), `render_orphans` (`:322-337`), and tests `163-228`. Verified at `:174-193`, `:195-338`, `:340-356`, and tests at `229-282`.
  - D2 cites host process gathering (`:153-160`), none (`:180`), local worktrees (`:312-320`), tests `12-16, 163-166`. Verified at `:164-171`, `:190`, `:325-337`, and tests at `12-16, 229`.
  - D3 cites contradiction lines (`:220, 230-234, 271-275`), tests `47-77, 280-285`. Verified at `:211, 229, 248, 274`, tests at `48-80, 285`.
  - D4 cites filter (`:357`), INTAKE (`:372-376`), flags (`:63-68, 351-355`), tests `188-193, 230-234`. Verified at `:370`, `:386-389`, `:63-68, 364-368`, tests at `252-256, 280`.
  - D6 cites `--watch` (`:59-62`), loop (`:394-403`), test `163-166`. Verified at `:60-62`, `:395-404`, test at `229`.
  - D7 cites regex (`:227`). Verified at `:220`.
  - D8 cites anomaly conditions (`:220, 230-234, 250-254, 271-275`), tests `170-186, 219-228`. Verified at `:211, 229, 248, 274`, tests at `232-246, 258-261`.
  - D9 cites PR correlation (`:282-321`), tests `197-217`. Verified at `:288-314`, tests at `263-273`.

---

## T1 · The acceptance suite, written first and red — AT-14

Touch: `scripts/ops/tests/board_test.sh`

This task STARTS FROM #69's code and modifies it.

**1. Create the test file:** Copy `scripts/ops/tests/board_test.sh` verbatim from PR #69 (`bot/68-board` at `5049ea5`).

**2. The failing test:** Insert a new scenario for AT-14.
Add the fixture after `issue 106` (`:141`):
```bash
issue 107 "status:implementing,in-progress" \
  "Scenario 11: case-insensitive claim" "2026-09-03T10:30:00Z"
comments 107 "evekhm-daedalus-app[bot]" "claim: case-insensitive match"
```

Add the assertion before the final `10: the whole run wrote nothing` banner (`:284`):
```bash
banner "11: case-insensitive claim matching"
block 107
blockhas "claim     daedalus" "11: case-insensitive match resolves the owner"
```

**Decisions:** D11.
**Acceptance:** AT-14.
**Done when:** `bash scripts/ops/tests/board_test.sh` fails. (It will fail on "board.sh not found" until T2, and then on the new scenario until T3).

---

## T2 · The live board base (from #69) — D1..D4, D6, D8, D9

Touch: `scripts/ops/lib/github.sh`, `scripts/ops/board.sh`

This task STARTS FROM #69's code verbatim.

1. **Library helper:** Copy `scripts/ops/lib/github.sh` verbatim from PR #69 to `scripts/ops/lib/github.sh`. This provides the pagination query fix.
2. **The command:** Copy `scripts/ops/board.sh` verbatim from PR #69 to `scripts/ops/board.sh`.

**Decisions:** D1, D2, D3, D4, D6, D8, D9.
**Acceptance:** AT-1, AT-2, AT-3..AT-12. (AT-2 and AT-9 pass because #69 implements the base resolution, but AT-14 remains red).
**Done when:** `bash scripts/ops/tests/board_test.sh` runs and fails exactly on scenario 11 (AT-14) due to the claim match failure.

---

## T3 · Claim resolution parity with `work.sh` — D7

Touch: `scripts/ops/board.sh`

This task STARTS FROM #69's code and modifies it. The spec evaluated PR #69 as partially satisfying D7 because it lacks the case-insensitive flag and null-coalescing.

**1. The code delta:** In `scripts/ops/board.sh`, replace line `220` (as brought in from #69):
```bash
    claim="$(jq -c '[.[] | select(.body | test("\\A[[:space:]]*\\**[[:space:]]*Claim(ing)?\\b"))] | last // empty' <<<"$comments")"
```
with the exact parity version from `work.sh:467-470` that includes case-insensitivity (`"i"`) and null-safety (`(.body // "")`):
```bash
    claim="$(jq -c '[.[] | select((.body // "") | test("\\A[[:space:]]*\\**[[:space:]]*Claim(ing)?\\b"; "i"))] | last // empty' <<<"$comments")"
```

**Decisions:** D7.
**Acceptance:** AT-14.
**Done when:** `bash scripts/ops/tests/board_test.sh` exits 0.

---

## T4 · Discovery and README structure — D5, D10

Touch: `README.md`, `docs/SPEC.md`

This task STARTS FROM SCRATCH for `docs/SPEC.md` and the `README.md` reword, and re-applies PR #69's content for the new sections. The spec evaluated PR #69 as missing the `docs.structure` update and placing the README section in the wrong order.

**1. `docs/SPEC.md` `docs.structure`:** At `docs/SPEC.md:26`, replace the sentence:
> exactly one command shown as an instruction (`scripts/ops/work.sh <n>`).

with:
> exactly one operational command shown as an instruction (`scripts/ops/work.sh <n>`) and one observational command (`scripts/ops/board.sh`).

**2. `docs/SPEC.md` `ops.board`:** Adopt the `ops.board` capability entry verbatim from PR #69 (`docs/SPEC.md:869-886`) and append it to the Capabilities section of `main`'s `docs/SPEC.md` (before `## Agreed, not yet built`).

**3. `README.md` rewording:** At `README.md:6-7`, replace:
> Your entire job is two actions,
> repeated: typing a number, and merging a pull request.

with:
> Your operational job is two actions,
> repeated: typing a number, and merging a pull request, supported by checking the board.

**4. `README.md` section insertion:** Take the "See who is doing what" section verbatim from PR #69 (`README.md:281-299`) and insert it into `main`'s `README.md` immediately **before** the `## Where the rules actually live` heading (at `:256`).

**Decisions:** D5, D10.
**Acceptance:** AT-13.
**Done when:** The diff shows the correct order and `scripts/ci/spec_check.sh origin/main <body-file>` exits 0.

---

## T5 · Gates, and the forbidden-path audit

Every command from the repository root, on the working tree with
T1–T4 applied.

| # | Command | Expected | Proves |
|---|---|---|---|
| 1 | `bash scripts/ops/tests/board_test.sh` | exit 0, all 11 scenarios passing | AT-1..AT-12, AT-14 |
| 2 | `bash scripts/ops/tests/work_test.sh` | exit 0 | no regressions in `work.sh` |
| 3 | `bash scripts/ci/sanitize_check.sh` | exit 0, `PASS` | house rule |
| 4 | `bash scripts/ci/spec_check.sh origin/main <body-file>` | exit 0 | AT-13 |
| 5 | `git diff --name-only origin/main` | exactly 5 files (`board.sh`, `github.sh`, `board_test.sh`, `README.md`, `SPEC.md`) | D10 boundary |

The whole diff is exactly five files:
`scripts/ops/board.sh`, `scripts/ops/lib/github.sh`, `scripts/ops/tests/board_test.sh`, `README.md`, `docs/SPEC.md`.

**Done when:** all five are green and step 5 lists those five paths
and nothing else.

---

## Branch, commit, pull request

- **Branch:** `odyssey/68-live-board`.
- **Closing keyword: none.** The body carries `Refs #68` and must not carry `Closes #68`.
- **`docs/SPEC.md` must be in the diff.** T4 satisfies this. The PR must carry `Spec-impact: none - intent/** only, not a behavior-bearing path` in the body to pass `spec_check.sh` on the intent files, but the code files themselves are validated by the `docs/SPEC.md` updates. Wait, the spec states: "This spec's PR carries `Spec-impact: none — intent/** only, not a behavior-bearing path`; the `docs/SPEC.md` upsert accompanies the implementing PR." Since the implementer's PR touches behavior-bearing paths and updates `docs/SPEC.md`, it does not need the `Spec-impact` exception tag.
- **Body** names the five changed files, and the T5 table with each command's actual exit code.

Open questions: none
