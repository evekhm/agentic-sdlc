#!/usr/bin/env bash
# Tests for scripts/ops/work_dispatch.sh (#441).
#
#   bash scripts/ops/tests/work_dispatch_test.sh
#
# Hermetic, fixture-tree technique from work_test.sh: work_dispatch.sh
# resolves its sibling scripts (resolve_work_target.sh, digest.sh,
# claim.sh, work.sh) by absolute path from its own location, so PATH
# cannot stub them; a whole scratch REPO_ROOT with stub siblings can.
# Only work_dispatch.sh itself is the real file under test; its
# siblings are one-line loggers so each scenario asserts exactly which
# ones ran, and in what mode.
#
# Exit 0 with a PASS line per assertion, non-zero on the first failure.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
REAL_DISPATCH="$REPO/scripts/ops/work_dispatch.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass() { echo "PASS: $*" >&2; }
fail() { echo "FAIL: $*" >&2; exit 1; }

FIXTURE="$WORK/fixture/scripts/ops"
mkdir -p "$FIXTURE"
cp "$REAL_DISPATCH" "$FIXTURE/work_dispatch.sh"
chmod +x "$FIXTURE/work_dispatch.sh"
DISPATCH="$FIXTURE/work_dispatch.sh"
CALLS="$WORK/calls.log"
: > "$CALLS"
export CALLS

# --- stub siblings, one-line loggers ---------------------------------------
# resolve_work_target.sh: RESOLVE_OUT / RESOLVE_RC drive its behaviour.
cat > "$FIXTURE/resolve_work_target.sh" <<'STUB'
#!/usr/bin/env bash
echo "resolve_work_target.sh $*" >> "$CALLS"
printf '%s' "${RESOLVE_OUT:-99}"
exit "${RESOLVE_RC:-0}"
STUB

cat > "$FIXTURE/digest.sh" <<'STUB'
#!/usr/bin/env bash
echo "digest.sh $*" >> "$CALLS"
echo "digest: #$1 stub"
STUB

cat > "$FIXTURE/claim.sh" <<'STUB'
#!/usr/bin/env bash
echo "claim.sh $*" >> "$CALLS"
echo "claimed #$1"
STUB

cat > "$FIXTURE/work.sh" <<'STUB'
#!/usr/bin/env bash
echo "work.sh HEADLESS=${HEADLESS:-} $*" >> "$CALLS"
echo "WORK-RESULT: ok #$1 stub launch"
STUB

chmod +x "$FIXTURE/resolve_work_target.sh" "$FIXTURE/digest.sh" "$FIXTURE/claim.sh" "$FIXTURE/work.sh"

export GITHUB_REPO="test/repo"

# --- stub gh, for the hold/closed/status:review-stuck/blocked/already-claimed
# checks in the non-yolo path: STATE and LABELS (a JSON array of name
# strings) drive the {state, labels: [{name: ...}]} object work_dispatch.sh's
# `--json state,labels` call would have produced (GitHub's real shape: each
# label is an object with a name field, not a bare string).
mkdir -p "$WORK/bin"
cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
if [ "$1 $2" = "issue view" ]; then
    LABEL_OBJS="$(jq -c '[.[] | {name: .}]' <<<"${LABELS:-[]}")"
    printf '{"state":"%s","labels":%s,"comments":%s}' "${STATE:-OPEN}" "$LABEL_OBJS" "${COMMENTS_JSON:-[]}"
    exit 0
fi
echo "stub gh: unexpected call: $*" >&2
exit 1
STUB
chmod +x "$WORK/bin/gh"
export PATH="$WORK/bin:$PATH"

reset_calls() { : > "$CALLS"; }

# --- 1. bare dispatch: resolves, digests, claims (not yet claimed) ---------
reset_calls
rc=0; out="$(RESOLVE_OUT=7 LABELS='[]' "$DISPATCH" 2>&1)" || rc=$?
[ "$rc" -eq 0 ] || fail "bare: expected exit 0, got $rc -- $out"
grep -q '^resolve_work_target.sh $' "$CALLS" || fail "bare: resolver not called with no args -- $(cat "$CALLS")"
grep -q '^digest.sh 7$' "$CALLS" || fail "bare: digest.sh not called with resolved number -- $(cat "$CALLS")"
grep -q '^claim.sh 7$' "$CALLS" || fail "bare: claim.sh not called -- $(cat "$CALLS")"
grep -q '^work.sh ' "$CALLS" && fail "bare: work.sh must never run without --yolo -- $(cat "$CALLS")"
pass "bare dispatch resolves, digests, and claims an unclaimed issue"

# --- 2. bare dispatch: already claimed -> claim.sh is skipped --------------
reset_calls
rc=0; out="$(RESOLVE_OUT=7 LABELS='["in-progress"]' "$DISPATCH" 2>&1)" || rc=$?
[ "$rc" -eq 0 ] || fail "already claimed: expected exit 0, got $rc -- $out"
grep -q '^claim.sh' "$CALLS" && fail "already claimed: claim.sh must not run -- $(cat "$CALLS")"
echo "$out" | grep -q 'already carries in-progress' || fail "already claimed: missing notice -- $out"
pass "an already-claimed issue is not reclaimed"

# --- 9. hold + in-progress -> refused, exit 2, claim.sh never runs ----------
reset_calls
rc=0; out="$(RESOLVE_OUT=7 LABELS='["in-progress","hold"]' "$DISPATCH" 2>&1)" || rc=$?
[ "$rc" -eq 2 ] || fail "hold+in-progress: expected exit 2, got $rc -- $out"
echo "$out" | grep -q 'refused: #7 carries hold' || fail "hold+in-progress: missing refusal message -- $out"
grep -q '^claim.sh' "$CALLS" && fail "hold+in-progress: claim.sh must not run -- $(cat "$CALLS")"
pass "hold on an already-claimed issue is refused, exit 2, even though in-progress is set"

# --- 10. blocked + in-progress -> refused, exit 2, claim.sh never runs -----
reset_calls
rc=0; out="$(RESOLVE_OUT=7 LABELS='["in-progress","blocked"]' "$DISPATCH" 2>&1)" || rc=$?
[ "$rc" -eq 2 ] || fail "blocked+in-progress: expected exit 2, got $rc -- $out"
echo "$out" | grep -q 'refused: #7 carries blocked' || fail "blocked+in-progress: missing refusal message -- $out"
grep -q '^claim.sh' "$CALLS" && fail "blocked+in-progress: claim.sh must not run -- $(cat "$CALLS")"
pass "blocked on an already-claimed issue is refused, exit 2, even though in-progress is set"

# --- 11. hold alone (not yet claimed) -> refused before claim.sh runs ------
reset_calls
rc=0; out="$(RESOLVE_OUT=7 LABELS='["hold"]' "$DISPATCH" 2>&1)" || rc=$?
[ "$rc" -eq 2 ] || fail "hold alone: expected exit 2, got $rc -- $out"
grep -q '^claim.sh' "$CALLS" && fail "hold alone: claim.sh must not run -- $(cat "$CALLS")"
pass "hold on an unclaimed issue is refused before claim.sh ever runs"

# --- 12. closed + in-progress -> refused, exit 2, claim.sh never runs -------
reset_calls
rc=0; out="$(RESOLVE_OUT=7 STATE=CLOSED LABELS='["in-progress"]' "$DISPATCH" 2>&1)" || rc=$?
[ "$rc" -eq 2 ] || fail "closed+in-progress: expected exit 2, got $rc -- $out"
echo "$out" | grep -q 'refused: #7 is closed' || fail "closed+in-progress: missing refusal message -- $out"
grep -q '^claim.sh' "$CALLS" && fail "closed+in-progress: claim.sh must not run -- $(cat "$CALLS")"
pass "a closed issue is refused, exit 2, even though in-progress is set"

# --- 13. status:review-stuck + in-progress -> refused, exit 2 --------------
reset_calls
rc=0; out="$(RESOLVE_OUT=7 LABELS='["in-progress","status:review-stuck"]' "$DISPATCH" 2>&1)" || rc=$?
[ "$rc" -eq 2 ] || fail "review-stuck+in-progress: expected exit 2, got $rc -- $out"
echo "$out" | grep -q 'refused: #7 carries status:review-stuck' || fail "review-stuck+in-progress: missing refusal message -- $out"
grep -q '^claim.sh' "$CALLS" && fail "review-stuck+in-progress: claim.sh must not run -- $(cat "$CALLS")"
pass "status:review-stuck on an already-claimed issue is refused, exit 2, even though in-progress is set"

# --- 14. --as without --yolo -> refused, exit 1, before any digest ---------
reset_calls
rc=0; out="$(RESOLVE_OUT=7 "$DISPATCH" 7 --as athena 2>&1)" || rc=$?
[ "$rc" -eq 1 ] || fail "as without yolo: expected exit 1, got $rc -- $out"
echo "$out" | grep -q -- '--as is a --yolo dispatch override' || fail "as without yolo: missing message -- $out"
grep -q '^digest.sh' "$CALLS" && fail "as without yolo: digest.sh must not run -- $(cat "$CALLS")"
grep -q '^claim.sh' "$CALLS" && fail "as without yolo: claim.sh must not run -- $(cat "$CALLS")"
pass "--as without --yolo is refused before any digest line, exit 1"

# --- 3. explicit argument reaches the resolver ------------------------------
reset_calls
"$DISPATCH" 42 >/dev/null 2>&1 || true
grep -q '^resolve_work_target.sh 42$' "$CALLS" || fail "explicit arg: resolver not called with '42' -- $(cat "$CALLS")"
pass "an explicit numeric argument is forwarded to the resolver"

# --- 4. NEEDS_PICK (resolver exit 3) is relayed, work.sh never runs --------
reset_calls
rc=0; out="$(RESOLVE_OUT="NEEDS_PICK
9	Nine" RESOLVE_RC=3 "$DISPATCH" 2>&1)" || rc=$?
[ "$rc" -eq 3 ] || fail "needs pick: expected exit 3, got $rc -- $out"
echo "$out" | grep -q '^NEEDS_PICK$' || fail "needs pick: header not relayed -- $out"
echo "$out" | grep -q '^9	Nine$' || fail "needs pick: candidate not relayed -- $out"
grep -q '^digest.sh' "$CALLS" && fail "needs pick: digest.sh must not run -- $(cat "$CALLS")"
grep -q '^claim.sh' "$CALLS" && fail "needs pick: claim.sh must not run -- $(cat "$CALLS")"
pass "a resolver NEEDS_PICK is relayed verbatim, exit 3, nothing else runs"

# --- 5. --yolo: resolves, then hands straight to work.sh HEADLESS=1 -------
reset_calls
rc=0; out="$(RESOLVE_OUT=7 "$DISPATCH" --yolo 2>&1)" || rc=$?
[ "$rc" -eq 0 ] || fail "yolo: expected exit 0, got $rc -- $out"
grep -q '^work.sh HEADLESS=1 7$' "$CALLS" || fail "yolo: work.sh not called headless with '7' -- $(cat "$CALLS")"
grep -q '^digest.sh' "$CALLS" && fail "yolo: digest.sh must not run in --yolo mode -- $(cat "$CALLS")"
grep -q '^claim.sh' "$CALLS" && fail "yolo: claim.sh must not run in --yolo mode (work.sh owns its own claim) -- $(cat "$CALLS")"
pass "--yolo resolves and dispatches straight to headless work.sh, unchanged from before #441"

# --- 6. --as <persona> is forwarded to work.sh in --yolo mode -------------
reset_calls
RESOLVE_OUT=7 "$DISPATCH" 7 --yolo --as athena >/dev/null 2>&1 || true
grep -q '^work.sh HEADLESS=1 7 --as athena$' "$CALLS" || fail "as passthrough: work.sh not called with --as athena -- $(cat "$CALLS")"
pass "--as <persona> reaches work.sh under --yolo"

# --- 7. a non-numeric, non-flag token is refused, exit 1 -------------------
reset_calls
rc=0; out="$("$DISPATCH" a-description-not-a-number 2>&1)" || rc=$?
[ "$rc" -eq 1 ] || fail "bad token: expected exit 1, got $rc -- $out"
grep -q '^resolve_work_target.sh' "$CALLS" && fail "bad token: resolver must not run on unusable input -- $(cat "$CALLS")"
pass "a free-text token is refused before the resolver runs, exit 1"

# --- 8. two numbers in one call is refused, exit 1 --------------------------
rc=0; out="$("$DISPATCH" 7 8 2>&1)" || rc=$?
[ "$rc" -eq 1 ] || fail "two numbers: expected exit 1, got $rc -- $out"
pass "more than one number in a single dispatch is refused"

# --- 15. already claimed: the claim comment's real author is surfaced ------
reset_calls
COMMENTS_JSON='[{"body":"unrelated chatter","author":{"login":"nobody"}},{"body":"Claim: eva (session-1), stage: implement. Worktree: .claude/worktrees/eva-7-x","author":{"login":"eva-bot"}}]'
rc=0; out="$(RESOLVE_OUT=7 LABELS='["in-progress"]' COMMENTS_JSON="$COMMENTS_JSON" "$DISPATCH" 2>&1)" || rc=$?
[ "$rc" -eq 0 ] || fail "already claimed holder: expected exit 0, got $rc -- $out"
echo "$out" | grep -q 'held by eva-bot' || fail "already claimed holder: missing holder login -- $out"
pass "an already-claimed issue's message names the claim comment's actual author, not the last comment"

# --- 16. already claimed, no structured claim line -> holder unresolved ----
reset_calls
COMMENTS_JSON='[{"body":"just a status update, not a claim","author":{"login":"someone"}}]'
rc=0; out="$(RESOLVE_OUT=7 LABELS='["in-progress"]' COMMENTS_JSON="$COMMENTS_JSON" "$DISPATCH" 2>&1)" || rc=$?
[ "$rc" -eq 0 ] || fail "already claimed no-claim: expected exit 0, got $rc -- $out"
echo "$out" | grep -q 'holder cannot be established' || fail "already claimed no-claim: missing message -- $out"
pass "an already-claimed issue with no structured claim line says the holder cannot be established"

# --- 17. unclaimed dispatch resolves the stage owner and claims as that
# persona, with a minted token, instead of git config user.name / an
# ambient gh login (#466) --------------------------------------------------
reset_calls
PERSONA_DIR="$WORK/fixture/personas"
mkdir -p "$PERSONA_DIR" "$WORK/fixture/scripts/auth"
cat > "$PERSONA_DIR/lifecycle.json" <<'JSON'
{"stages":[{"stage":"plan","label":"status:planning"},{"stage":"implement","label":"status:implementing"}]}
JSON
cat > "$PERSONA_DIR/athena.yaml" <<'YAML'
kind: persona
stage: [intake, plan, design]
YAML
cat > "$PERSONA_DIR/odyssey.yaml" <<'YAML'
kind: persona
stage: [implement]
YAML
cat > "$WORK/fixture/scripts/auth/mint_app_token.py" <<'STUB'
#!/usr/bin/env python3
import sys
print("minted-token-for-" + sys.argv[1])
STUB
chmod +x "$WORK/fixture/scripts/auth/mint_app_token.py"
cat > "$FIXTURE/claim.sh" <<'STUB'
#!/usr/bin/env bash
echo "claim.sh CLAIM_ACTOR=${CLAIM_ACTOR:-} GH_TOKEN=${GH_TOKEN:-} $*" >> "$CALLS"
echo "claimed #$1"
STUB
chmod +x "$FIXTURE/claim.sh"
rc=0; out="$(RESOLVE_OUT=7 LABELS='["intent:new"]' "$DISPATCH" 2>&1)" || rc=$?
[ "$rc" -eq 0 ] || fail "stage-owner claim: expected exit 0, got $rc -- $out"
grep -q '^claim.sh CLAIM_ACTOR=athena GH_TOKEN=minted-token-for-athena 7$' "$CALLS" \
    || fail "stage-owner claim: claim.sh did not receive the resolved persona's CLAIM_ACTOR/GH_TOKEN -- $(cat "$CALLS")"
pass "an unclaimed issue claims and posts as the stage-owning persona, not git config user.name or an ambient gh login"

echo "work_dispatch_test.sh: all assertions passed" >&2
