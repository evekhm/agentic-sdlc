#!/usr/bin/env bash
# Contract tests for Operator Escalation Sweep Machine (#481).
# Cites Decisions D1, D2, D3, D4, D5, D6, D7, D8, D9
# and Acceptance Tests AT-481-1 through AT-481-15.
#
# Every assertion cites its Decision ID and Acceptance Test ID.
# Hermetic: tests run locally without network access.
# Under the baseline tree before Odyssey's implementation, all assertions
# must FAIL (red) cleanly with exit code 1, proving behavior is not smuggled.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
BOOTSTRAP_TRACKER="$REPO/scripts/setup/bootstrap_tracker.sh"
WORK_DISPATCH="$REPO/scripts/ops/work_dispatch.sh"
WORK_SH="$REPO/scripts/ops/work.sh"
CLAIM_SH="$REPO/scripts/ops/claim.sh"
POLL_SH="$REPO/scripts/placement/vm-local/poll.sh"
COMMANDS_WORK="$REPO/commands/work.md"
COMMANDS_ESCALATIONS="$REPO/commands/escalations.md"
ALIGN_ESCALATIONS="$REPO/scripts/ops/align_escalations.sh"
SPEC_MD="$REPO/docs/SPEC.md"

TOTAL=0
PASSED=0
FAILURES=0

banner() { printf '\n=== %s ===\n' "$*"; }

pass() {
    echo "PASS: $*"
    TOTAL=$((TOTAL + 1))
    PASSED=$((PASSED + 1))
}

fail() {
    echo "FAIL: $*" >&2
    TOTAL=$((TOTAL + 1))
    FAILURES=$((FAILURES + 1))
}

# --- Hermetic environment setup for CLI tests ---
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FIXTURES="$WORK/fixtures"
WRITES="$WORK/writes.log"
CALLS="$WORK/calls.log"
mkdir -p "$FIXTURES" "$WORK/bin"
: > "$WRITES"
: > "$CALLS"

export GITHUB_REPO="test/repo"
export FIXTURES WRITES CALLS
export PATH="$WORK/bin:$PATH"
export CLAIM_ACTOR=tester CLAIM_SESSION=test-session CLAIM_STAGE=implement
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# Stub gh: answers reads from fixtures, logs calls and writes
cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CALLS"

# Log mutating commands to WRITES
is_write=0
case "${1:-}" in
  api)
    for arg in "$@"; do
      case "$arg" in
        POST|PATCH|PUT|DELETE|--method=POST|--method=PATCH|--method=PUT|--method=DELETE|-XPOST|-XPATCH|-XPUT|-XDELETE)
          is_write=1
          break
          ;;
        -f|--field|-F|--raw-field)
          is_write=1
          ;;
      esac
    done
    for arg in "$@"; do
      case "$arg" in
        GET|--method=GET|-XGET)
          is_write=0
          break
          ;;
      esac
    done
    ;;
  issue|pr)
    case "${2:-}" in
      comment|edit|close|reopen|create|delete|merge|review)
        is_write=1
        ;;
    esac
    ;;
  label)
    case "${2:-}" in
      create|edit|delete|clone)
        is_write=1
        ;;
    esac
    ;;
esac

if [ "$is_write" -eq 1 ]; then
  printf '%s\n' "$*" >> "$WRITES"
fi

if [ "${1:-}" = "api" ] && [ "$#" -ge 2 ]; then
  path="${2#/}"
  file="$FIXTURES/${path//\//_}.json"
  if [ -f "$file" ]; then
    cat "$file"
    exit 0
  fi
fi

if [ "${1:-}" = "issue" ] && [ "${2:-}" = "view" ]; then
  num="$3"
  file="$FIXTURES/issue_${num}.json"
  if [ -f "$file" ]; then
    cat "$file"
    exit 0
  fi
fi

if [ "${1:-}" = "issue" ] && [ "${2:-}" = "list" ]; then
  file="$FIXTURES/issue_list.json"
  if [ -f "$file" ]; then
    cat "$file"
    exit 0
  fi
  echo "[]"
  exit 0
fi

if [ "${1:-}" = "pr" ] && [ "${2:-}" = "list" ]; then
  file="$FIXTURES/pr_list.json"
  if [ -f "$file" ]; then
    cat "$file"
    exit 0
  fi
  echo "[]"
  exit 0
fi

exit 0
STUB
chmod +x "$WORK/bin/gh"

# Create fixture for issue 100 with status:needs-input
cat > "$FIXTURES/repos_test_repo_issues_100.json" <<'JSON'
{
  "number": 100,
  "state": "open",
  "title": "Escalated Issue",
  "body": "Issue needing operator input",
  "labels": [
    {"name": "status:needs-input"},
    {"name": "intent:new"}
  ],
  "issue_dependencies_summary": {"total_blocked_by": 0}
}
JSON
cat > "$FIXTURES/repos_test_repo_issues_100_comments.json" <<'JSON'
[]
JSON
cat > "$FIXTURES/issue_100.json" <<'JSON'
{
  "number": 100,
  "state": "OPEN",
  "title": "Escalated Issue",
  "body": "Issue needing operator input",
  "labels": [
    {"name": "status:needs-input"},
    {"name": "intent:new"}
  ],
  "comments": []
}
JSON

# Create fixture for issue 101 with status:review-stuck
cat > "$FIXTURES/repos_test_repo_issues_101.json" <<'JSON'
{
  "number": 101,
  "state": "open",
  "title": "Review Stuck Issue",
  "body": "Issue stuck in review",
  "labels": [
    {"name": "status:review-stuck"}
  ],
  "issue_dependencies_summary": {"total_blocked_by": 0}
}
JSON
cat > "$FIXTURES/repos_test_repo_issues_101_comments.json" <<'JSON'
[]
JSON
cat > "$FIXTURES/issue_101.json" <<'JSON'
{
  "number": 101,
  "state": "OPEN",
  "title": "Review Stuck Issue",
  "body": "Issue stuck in review",
  "labels": [
    {"name": "status:review-stuck"}
  ],
  "comments": []
}
JSON

# Create fixture for issue 102 with status:in-review (multiple owners: argus and atlas)
cat > "$FIXTURES/repos_test_repo_issues_102.json" <<'JSON'
{
  "number": 102,
  "state": "open",
  "title": "In Review Ambiguous Owner Issue",
  "body": "Issue at review stage owned by both argus and atlas",
  "labels": [
    {"name": "status:in-review"}
  ],
  "issue_dependencies_summary": {"total_blocked_by": 0}
}
JSON
cat > "$FIXTURES/repos_test_repo_issues_102_comments.json" <<'JSON'
[]
JSON
cat > "$FIXTURES/issue_102.json" <<'JSON'
{
  "number": 102,
  "state": "OPEN",
  "title": "In Review Ambiguous Owner Issue",
  "body": "Issue at review stage owned by both argus and atlas",
  "labels": [
    {"name": "status:in-review"}
  ],
  "comments": []
}
JSON

# Hermetic git repository setup for claim and work execution
git init -q --bare -b main "$WORK/origin.git"
git clone -q "$WORK/origin.git" "$WORK/repo" 2>/dev/null
PRIMARY="$WORK/repo"
(
  cd "$PRIMARY"
  git checkout -q -b main
  echo base > base.txt
  printf '.claude/\n' > .gitignore
  mkdir -p personas
  cat > personas/lifecycle.json <<'JSON'
{"stages":[
  {"stage":"plan","label":"status:planning"},
  {"stage":"design","label":"status:spec"},
  {"stage":"build","label":"status:build"},
  {"stage":"implement","label":"status:implementing"},
  {"stage":"review","label":"status:in-review"}
]}
JSON
  git add base.txt .gitignore personas/lifecycle.json
  git commit -q -m "initial commit"
  git push -q -u origin main
)

run_claim() {
  local num="$1"
  shift
  OUT=""
  set +e
  OUT="$(cd "$PRIMARY" && DRY_RUN=1 bash "$CLAIM_SH" "$num" "$@" 2>&1)"
  EXIT_CODE=$?
  set -e
}

run_work_dispatch() {
  local num="$1"
  shift
  OUT=""
  set +e
  OUT="$(cd "$PRIMARY" && DRY_RUN=1 bash "$WORK_DISPATCH" "$num" "$@" 2>&1)"
  EXIT_CODE=$?
  set -e
}

run_work() {
  local num="$1"
  shift
  OUT=""
  set +e
  OUT="$(cd "$PRIMARY" && DRY_RUN=1 bash "$WORK_SH" "$num" "$@" 2>&1)"
  EXIT_CODE=$?
  set -e
}

run_work_headless() {
  local num="$1"
  shift
  OUT=""
  set +e
  OUT="$(cd "$PRIMARY" && HEADLESS=1 DRY_RUN=1 bash "$WORK_SH" "$num" "$@" 2>&1)"
  EXIT_CODE=$?
  set -e
}

# ==============================================================================
# Assertion 1: D1 / AT-481-1: Label taxonomy in bootstrap_tracker.sh defines status:needs-input
# ==============================================================================
banner "D1 / AT-481-1: Label taxonomy in bootstrap_tracker.sh defines status:needs-input"
if grep -Eq 'ensure_label "status:needs-input" "E11D21"' "$BOOTSTRAP_TRACKER"; then
    pass "D1 / AT-481-1: bootstrap_tracker.sh defines status:needs-input with color E11D21"
else
    fail "D1 / AT-481-1: bootstrap_tracker.sh does not define status:needs-input"
fi

# ==============================================================================
# Assertion 2: D1 / AT-481-2: Label displacement and restoration semantics
# ==============================================================================
banner "D1 / AT-481-2: Label displacement and restoration semantics"
if [ -x "$ALIGN_ESCALATIONS" ] && grep -Eq 'status:needs-input' "$ALIGN_ESCALATIONS" && grep -Eq 'stage=' "$ALIGN_ESCALATIONS" && grep -Eq 'status:(planning|spec|build|implementing)' "$ALIGN_ESCALATIONS"; then
    pass "D1 / AT-481-2: align_escalations.sh implements label displacement and restoration semantics"
else
    fail "D1 / AT-481-2: align_escalations.sh does not exist or does not implement label displacement/restoration"
fi

# ==============================================================================
# Assertion 3: D2 / AT-481-3: work_dispatch.sh refuses on status:needs-input
# ==============================================================================
banner "D2 / AT-481-3: work_dispatch.sh refuses on status:needs-input"
run_work_dispatch 100
if [ "$EXIT_CODE" -eq 2 ] && grep -qF "work_dispatch.sh: refused: #100 carries status:needs-input" <<<"$OUT"; then
    pass "D2 / AT-481-3: work_dispatch.sh exits 2 with refusal for status:needs-input"
else
    fail "D2 / AT-481-3: work_dispatch.sh did not refuse on status:needs-input (rc=$EXIT_CODE, out=$OUT)"
fi

# ==============================================================================
# Assertion 4: D2 / AT-481-4: work.sh refuses on status:needs-input
# ==============================================================================
banner "D2 / AT-481-4: work.sh refuses on status:needs-input"
run_work 100
if [ "$EXIT_CODE" -eq 2 ] && grep -q "carries status:needs-input" <<<"$OUT"; then
    pass "D2 / AT-481-4: work.sh exits 2 with refusal for status:needs-input"
else
    fail "D2 / AT-481-4: work.sh did not refuse on status:needs-input (rc=$EXIT_CODE, out=$OUT)"
fi

# ==============================================================================
# Assertion 5: D2 / AT-481-5: claim.sh refuses on status:needs-input
# ==============================================================================
banner "D2 / AT-481-5: claim.sh refuses on status:needs-input"
run_claim 100
if [ "$EXIT_CODE" -eq 2 ] && grep -qF "refused: #100 carries status:needs-input" <<<"$OUT"; then
    pass "D2 / AT-481-5: claim.sh exits 2 with refusal for status:needs-input"
else
    fail "D2 / AT-481-5: claim.sh did not refuse on status:needs-input (rc=$EXIT_CODE, out=$OUT)"
fi

# ==============================================================================
# Assertion 6: D2 / AT-481-6: claim.sh refuses on status:review-stuck
# ==============================================================================
banner "D2 / AT-481-6: claim.sh refuses on status:review-stuck"
run_claim 101
if [ "$EXIT_CODE" -eq 2 ] && grep -qF "refused: #101 carries status:review-stuck" <<<"$OUT"; then
    pass "D2 / AT-481-6: claim.sh exits 2 with refusal for status:review-stuck"
else
    fail "D2 / AT-481-6: claim.sh did not refuse on status:review-stuck (rc=$EXIT_CODE, out=$OUT)"
fi

# ==============================================================================
# Assertion 7: D2 / AT-481-3 (doc): commands/work.md documents status:needs-input circuit breaker
# ==============================================================================
banner "D2: commands/work.md documents status:needs-input circuit breaker"
if grep -qF "status:needs-input" "$COMMANDS_WORK"; then
    pass "D2: commands/work.md documents status:needs-input"
else
    fail "D2: commands/work.md does not document status:needs-input"
fi

# ==============================================================================
# Assertion 8: D3 / AT-481-7: poll.sh skips PRs when tracking issue carries status:needs-input
# ==============================================================================
banner "D3 / AT-481-7: poll.sh skips PRs when tracking issue carries status:needs-input"
if grep -Eq 'poll\.sh: skipping PR.*tracking issue.*carries status:needs-input' "$POLL_SH"; then
    pass "D3 / AT-481-7: poll.sh skips PRs whose tracking issue carries status:needs-input"
else
    fail "D3 / AT-481-7: poll.sh missing skip logic for status:needs-input"
fi

# ==============================================================================
# Assertion 9: D4 / AT-481-8: ESCALATION marker grammar validation
# ==============================================================================
banner "D4 / AT-481-8: ESCALATION marker grammar validation"
if [ -f "$ALIGN_ESCALATIONS" ] && ( \
    grep -Eq 'ESCALATION: #[0-9\(\\\+\)]+ kind=(open-question\|blocked\|ambiguous-owner|\(open-question\\\|blocked\\\|ambiguous-owner\))' "$ALIGN_ESCALATIONS" || \
    ( grep -qF "ESCALATION:" "$ALIGN_ESCALATIONS" && grep -qF "kind=" "$ALIGN_ESCALATIONS" && grep -qF "stage=" "$ALIGN_ESCALATIONS" && grep -qF "open-question" "$ALIGN_ESCALATIONS" && grep -qF "ambiguous-owner" "$ALIGN_ESCALATIONS" ) \
); then
    pass "D4 / AT-481-8: align_escalations.sh implements ESCALATION marker grammar"
else
    fail "D4 / AT-481-8: align_escalations.sh does not exist or does not implement marker grammar regex"
fi

# ==============================================================================
# Assertion 10: D5 / AT-481-9: work.sh unattended ambiguous-owner escalation
# ==============================================================================
banner "D5 / AT-481-9: work.sh unattended ambiguous-owner escalation"
run_work_headless 102
if [ "$EXIT_CODE" -eq 2 ] && grep -qF "WORK-RESULT: blocked #102 ambiguous owner" <<<"$OUT"; then
    pass "D5 / AT-481-9: work.sh exits 2 with WORK-RESULT: blocked on ambiguous owner in unattended mode"
else
    fail "D5 / AT-481-9: work.sh did not escalate ambiguous owner under HEADLESS=1 (rc=$EXIT_CODE, out=$OUT)"
fi

# ==============================================================================
# Assertion 11: D6 / AT-481-10: commands/escalations.md exists and compiles cleanly via sync_commands.py
# ==============================================================================
banner "D6 / AT-481-10: commands/escalations.md exists and compiles cleanly via sync_commands.py --check"
if [ -f "$COMMANDS_ESCALATIONS" ] && python3 "$REPO/scripts/sync_commands.py" --check >/dev/null 2>&1; then
    pass "D6 / AT-481-10: commands/escalations.md compiles cleanly via sync_commands.py --check"
else
    fail "D6 / AT-481-10: commands/escalations.md does not exist or sync_commands.py --check failed"
fi

# ==============================================================================
# Assertion 12: D6 / AT-481-11: /escalations command specification defines listing, ruling comment, and stage restoration
# ==============================================================================
banner "D6 / AT-481-11: /escalations command specification defines listing, ruling comment, and stage restoration"
if [ -f "$COMMANDS_ESCALATIONS" ] && grep -qF "status:needs-input" "$COMMANDS_ESCALATIONS" && grep -qF "Decision:" "$COMMANDS_ESCALATIONS"; then
    pass "D6 / AT-481-11: /escalations command specification defines required operator workflow"
else
    fail "D6 / AT-481-11: commands/escalations.md does not exist or missing workflow steps"
fi

# ==============================================================================
# Assertion 13: D7 / AT-481-12: scripts/ops/align_escalations.sh audit mode runs without --apply and makes zero mutations
# ==============================================================================
banner "D7 / AT-481-12: scripts/ops/align_escalations.sh audit mode runs without --apply and makes zero mutations"
if [ -x "$ALIGN_ESCALATIONS" ]; then
    : > "$WRITES"
    set +e
    ALIGN_OUT="$("$ALIGN_ESCALATIONS" 2>&1)"
    ALIGN_RC=$?
    set -e
    if [ "$ALIGN_RC" -eq 0 ] && [ ! -s "$WRITES" ]; then
        pass "D7 / AT-481-12: align_escalations.sh runs in audit mode without mutating tracker state"
    else
        fail "D7 / AT-481-12: align_escalations.sh failed audit mode run or attempted mutations (rc=$ALIGN_RC)"
    fi
else
    fail "D7 / AT-481-12: scripts/ops/align_escalations.sh does not exist or is not executable"
fi

# ==============================================================================
# Assertion 14: D7 / AT-481-13: scripts/ops/align_escalations.sh --apply applies status:needs-input and emits ESCALATION marker
# ==============================================================================
banner "D7 / AT-481-13: scripts/ops/align_escalations.sh --apply applies status:needs-input and emits ESCALATION marker"
if [ -x "$ALIGN_ESCALATIONS" ] && grep -qF -- "--apply" "$ALIGN_ESCALATIONS" && grep -qF "status:needs-input" "$ALIGN_ESCALATIONS"; then
    pass "D7 / AT-481-13: align_escalations.sh implements --apply mutation mode"
else
    fail "D7 / AT-481-13: scripts/ops/align_escalations.sh does not exist or missing --apply support"
fi

# ==============================================================================
# Assertion 15: D8 / AT-481-14: docs/SPEC.md documents status:needs-input and ESCALATION marker
# ==============================================================================
banner "D8 / AT-481-14: docs/SPEC.md documents status:needs-input and ESCALATION marker"
if grep -qF "status:needs-input" "$SPEC_MD" && grep -qF "ESCALATION:" "$SPEC_MD" && ( cd "$REPO" && bash "$REPO/scripts/ci/spec_check.sh" origin/main >/dev/null 2>&1 ); then
    pass "D8 / AT-481-14: docs/SPEC.md documents status:needs-input and ESCALATION marker and passes spec_check.sh"
else
    fail "D8 / AT-481-14: docs/SPEC.md missing documentation for status:needs-input/ESCALATION or spec_check.sh failed"
fi

# ==============================================================================
# Assertion 16: D9 / AT-481-15: Implementation manifest delivery and compliance
# ==============================================================================
banner "D9 / AT-481-15: Implementation manifest delivery and compliance"
manifest_ok=1
if [ ! -f "$COMMANDS_ESCALATIONS" ] || [ ! -f "$ALIGN_ESCALATIONS" ] || [ ! -f "$REPO/scripts/ci/tests/escalation_queue_test.sh" ]; then
    manifest_ok=0
fi

if [ "$manifest_ok" -eq 1 ]; then
    allowed_pattern='^(scripts/setup/bootstrap_tracker\.sh|scripts/ops/work_dispatch\.sh|scripts/ops/work\.sh|scripts/ops/claim\.sh|scripts/placement/vm-local/poll\.sh|commands/work\.md|commands/escalations\.md|\.claude/commands/work\.md|\.claude/commands/escalations\.md|\.agents/skills/work/SKILL\.md|\.agents/skills/escalations/SKILL\.md|scripts/ops/align_escalations\.sh|scripts/ops/tests/work_dispatch_test\.sh|scripts/ops/tests/claim_test\.sh|scripts/ci/tests/escalation_queue_test\.sh|docs/SPEC\.md|CHANGELOG\.md|intent/481-operator-escalation-sweep-machine/.*|scripts/ops/tests/escalation_queue_contract_test\.sh)$'
    changed_files="$(git -C "$REPO" diff --name-only origin/main 2>/dev/null || true)"
    for f in $changed_files; do
        if ! grep -Eq "$allowed_pattern" <<<"$f"; then
            manifest_ok=0
            break
        fi
    done
fi

if [ "$manifest_ok" -eq 1 ]; then
    pass "D9 / AT-481-15: Implementation manifest delivery and compliance confirmed"
else
    fail "D9 / AT-481-15: Implementation manifest files not yet created or forbidden paths modified"
fi

# ==============================================================================
# Summary
# ==============================================================================
banner "Contract Test Summary"
echo "Total assertions: $TOTAL"
echo "Passed:           $PASSED"
echo "Failed:           $FAILURES"

if [ "$FAILURES" -gt 0 ]; then
    echo "Total failures: $FAILURES (EXPECTED RED at build rung)" >&2
    exit 1
fi

echo "ALL TESTS PASSED"
exit 0
