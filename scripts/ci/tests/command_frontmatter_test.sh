#!/usr/bin/env bash
# Contract test suite and CI gate for command YAML frontmatter (#425).
# Validates Decisions D1, D2, D3, D6 and Acceptance Tests AT-425-1 through AT-425-7.
#
# Hermetic: tests run locally without network access or GitHub API calls.
#
# At the build rung (Daedalus), before .claude/commands/bug.md and wrap.md are fixed,
# running this suite reports failures on the unfixed repository commands and exits 1.
# During the implement rung (Odyssey), once bug.md and wrap.md are quoted,
# all contract assertions pass green and this suite exits 0.
#
# Usage:
#   scripts/ci/tests/command_frontmatter_test.sh
#     Runs full contract test suite against repository commands and simulated fixtures.
#   scripts/ci/tests/command_frontmatter_test.sh <file-or-dir>...
#     Direct file/directory validator mode: validates YAML frontmatter of specified files.
#     Exits 0 if all specified files are valid, 1 if any file fails.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../../.." && pwd)"

TOTAL=0
PASSED=0
FAILED=0

banner() { printf '\n=== %s ===\n' "$*"; }

pass() {
    echo "PASS: $*"
    PASSED=$((PASSED + 1))
    TOTAL=$((TOTAL + 1))
}

fail() {
    echo "FAIL: $*" >&2
    FAILED=$((FAILED + 1))
    TOTAL=$((TOTAL + 1))
}

# validate_single_file <path> -> exits 0 on valid frontmatter, exits 1 on invalid
validate_single_file() {
    local target="$1"
    python3 - "$target" <<'PY'
import sys, yaml

path = sys.argv[1]
try:
    with open(path, 'r', encoding='utf-8') as f:
        raw = f.read().replace('\r\n', '\n')
except Exception as e:
    print(f"ERROR: cannot read {path}: {e}", file=sys.stderr)
    sys.exit(1)

if not raw.startswith('---\n'):
    print(f"FAIL: {path} does not start with frontmatter delimiter '---'", file=sys.stderr)
    sys.exit(1)

parts = raw.split('---\n', 2)
if len(parts) < 3:
    print(f"FAIL: {path} missing closing frontmatter delimiter '---'", file=sys.stderr)
    sys.exit(1)

try:
    data = yaml.safe_load(parts[1])
except Exception as e:
    print(f"FAIL: {path} frontmatter is not valid YAML ({type(e).__name__}: {e})", file=sys.stderr)
    sys.exit(1)

if not isinstance(data, dict):
    print(f"FAIL: {path} frontmatter is not a YAML mapping", file=sys.stderr)
    sys.exit(1)

desc = data.get('description')
if not desc or not isinstance(desc, str) or not desc.strip():
    print(f"FAIL: {path} missing or empty non-string 'description'", file=sys.stderr)
    sys.exit(1)

hint = data.get('argument-hint')
if not hint or not isinstance(hint, str) or not hint.strip():
    print(f"FAIL: {path} missing or empty non-string 'argument-hint'", file=sys.stderr)
    sys.exit(1)

sys.exit(0)
PY
}

# --- Direct File / Directory Validator Mode ------------------------------------
if [ "$#" -gt 0 ]; then
    direct_fail=0
    for arg in "$@"; do
        if [ -d "$arg" ]; then
            for f in "$arg"/*.md; do
                [ -f "$f" ] || continue
                if ! validate_single_file "$f"; then
                    direct_fail=1
                fi
            done
        elif [ -f "$arg" ]; then
            if ! validate_single_file "$arg"; then
                direct_fail=1
            fi
        else
            echo "ERROR: target does not exist: $arg" >&2
            direct_fail=1
        fi
    done
    if [ "$direct_fail" -ne 0 ]; then
        exit 1
    fi
    exit 0
fi

# --- Full Contract Test Suite Mode --------------------------------------------
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Fixture 1: Simulated command with unquoted colon in argument-hint (AT-425-6, D3)
SIM_UNQUOTED_COLON="$WORK/sim_unquoted_colon.md"
cat > "$SIM_UNQUOTED_COLON" <<'EOF_FIXTURE'
---
description: Simulated command with unquoted colon
argument-hint: <free text describing the bug: repro, expected vs actual>
allowed-tools: Read
---
Body text.
EOF_FIXTURE

# Fixture 2: Simulated command with unquoted leading bracket (flow sequence) (D3)
SIM_UNQUOTED_BRACKET="$WORK/sim_unquoted_bracket.md"
cat > "$SIM_UNQUOTED_BRACKET" <<'EOF_FIXTURE'
---
description: Simulated command with unquoted bracket
argument-hint: [<seat-or-slug>] [--snapshot]
allowed-tools: Read
---
Body text.
EOF_FIXTURE

# Fixture 3: Simulated command missing description (D3)
SIM_MISSING_DESC="$WORK/sim_missing_desc.md"
cat > "$SIM_MISSING_DESC" <<'EOF_FIXTURE'
---
argument-hint: '[<seat-or-slug>]'
allowed-tools: Read
---
Body text.
EOF_FIXTURE

# Fixture 4: Simulated command missing argument-hint (D3)
SIM_MISSING_HINT="$WORK/sim_missing_hint.md"
cat > "$SIM_MISSING_HINT" <<'EOF_FIXTURE'
---
description: Some valid description
allowed-tools: Read
---
Body text.
EOF_FIXTURE

# Fixture 5: Simulated command with valid single-quoted argument-hint (D2, D3)
SIM_VALID="$WORK/sim_valid.md"
cat > "$SIM_VALID" <<'EOF_FIXTURE'
---
description: Simulated valid command
argument-hint: '<free text describing the bug: repro, expected vs actual>'
allowed-tools: Read
---
Body text.
EOF_FIXTURE

banner "1. Simulated Fixture Assertions (D2, D3 / AT-425-6)"

# 1. Negative test: rejection of unquoted colon in argument-hint (D3 / AT-425-6)
if validate_single_file "$SIM_UNQUOTED_COLON" >/dev/null 2>&1; then
    fail "D3 / AT-425-6: failed to reject simulated command with unquoted colon in argument-hint"
else
    pass "D3 / AT-425-6: rejected simulated command with unquoted colon in argument-hint"
fi

# 2. Negative test: rejection of unquoted flow sequence in argument-hint (D3)
if validate_single_file "$SIM_UNQUOTED_BRACKET" >/dev/null 2>&1; then
    fail "D3: failed to reject simulated command with unquoted flow sequence in argument-hint"
else
    pass "D3: rejected simulated command with unquoted flow sequence in argument-hint"
fi

# 3. Negative test: rejection of missing description (D3)
if validate_single_file "$SIM_MISSING_DESC" >/dev/null 2>&1; then
    fail "D3: failed to reject simulated command missing description"
else
    pass "D3: rejected simulated command missing description"
fi

# 4. Negative test: rejection of missing argument-hint (D3)
if validate_single_file "$SIM_MISSING_HINT" >/dev/null 2>&1; then
    fail "D3: failed to reject simulated command missing argument-hint"
else
    pass "D3: rejected simulated command missing argument-hint"
fi

# 5. Positive test: acceptance of valid single-quoted argument-hint (D2, D3)
if validate_single_file "$SIM_VALID" >/dev/null 2>&1; then
    pass "D2, D3: accepted simulated command with valid single-quoted argument-hint"
else
    fail "D2, D3: failed to accept simulated command with valid single-quoted argument-hint"
fi

banner "2. Repository Command Assertions: bug.md (D1, D2, D6 / AT-425-1, AT-425-3)"

BUG_MD="$REPO/.claude/commands/bug.md"
EXPECTED_BUG_HINT='<free text describing the bug: repro, expected vs actual; may include "Given design:", "Given spec:", or "Given code:" sections>'

# 6. bug.md frontmatter validation and single-quoted argument-hint (D1, D2 / AT-425-1, AT-425-3)
bug_res="$(python3 - "$BUG_MD" "$EXPECTED_BUG_HINT" <<'PY'
import sys, yaml

path = sys.argv[1]
expected_hint = sys.argv[2]
try:
    with open(path, 'r', encoding='utf-8') as f:
        lines = f.read().splitlines()
except Exception as e:
    print(f"CANNOT_READ: {e}")
    sys.exit(0)

if len(lines) < 3:
    print("TOO_FEW_LINES")
    sys.exit(0)

line3 = lines[2]
expected_line3 = f"argument-hint: '{expected_hint}'"
if line3 != expected_line3:
    print(f"LINE3_MISMATCH: got {line3!r}, expected {expected_line3!r}")
    sys.exit(0)

raw = "\n".join(lines)
parts = raw.split('---\n', 2)
if len(parts) < 3:
    print("NO_FRONTMATTER")
    sys.exit(0)

try:
    data = yaml.safe_load(parts[1])
except Exception as e:
    print(f"YAML_ERROR: {e}")
    sys.exit(0)

parsed_hint = data.get('argument-hint')
if parsed_hint != expected_hint:
    print(f"HINT_MISMATCH: got {parsed_hint!r}, expected {expected_hint!r}")
    sys.exit(0)

print("OK")
PY
)"

if [ "$bug_res" = "OK" ]; then
    pass "D1, D2 / AT-425-1, AT-425-3: .claude/commands/bug.md has valid YAML frontmatter with single-quoted argument-hint"
else
    fail "D1, D2 / AT-425-1, AT-425-3: .claude/commands/bug.md frontmatter assertion failed ($bug_res)"
fi

# 7. bug.md surgical single-line edit preservation (D6 / AT-425-1)
bug_surgeries="$(python3 - "$BUG_MD" <<'PY'
import sys
path = sys.argv[1]
try:
    with open(path, 'r', encoding='utf-8') as f:
        lines = f.read().splitlines()
except Exception as e:
    print(f"ERROR: {e}")
    sys.exit(0)

if len(lines) < 5:
    print("TOO_FEW_LINES")
    sys.exit(0)

if lines[0] != "---":
    print("LINE1_MISMATCH")
    sys.exit(0)
if lines[1] != "description: Manual intake door for a defect — searches the tracker first, then files an intent:new + bug issue.":
    print("LINE2_MISMATCH")
    sys.exit(0)
if not lines[3].startswith("allowed-tools: "):
    print("LINE4_MISMATCH")
    sys.exit(0)
if lines[4] != "---":
    print("LINE5_MISMATCH")
    sys.exit(0)

print("OK")
PY
)"

if [ "$bug_surgeries" = "OK" ]; then
    pass "D6 / AT-425-1: .claude/commands/bug.md lines 1-2, 4-5 preserved"
else
    fail "D6 / AT-425-1: .claude/commands/bug.md surrounding lines corrupted ($bug_surgeries)"
fi

banner "3. Repository Command Assertions: wrap.md (D1, D2, D6 / AT-425-2, AT-425-4)"

WRAP_MD="$REPO/.claude/commands/wrap.md"
EXPECTED_WRAP_HINT='[<seat-or-slug>] [--snapshot]'

# 8. wrap.md frontmatter validation and single-quoted argument-hint (D1, D2 / AT-425-2, AT-425-4)
wrap_res="$(python3 - "$WRAP_MD" "$EXPECTED_WRAP_HINT" <<'PY'
import sys, yaml

path = sys.argv[1]
expected_hint = sys.argv[2]
try:
    with open(path, 'r', encoding='utf-8') as f:
        lines = f.read().splitlines()
except Exception as e:
    print(f"CANNOT_READ: {e}")
    sys.exit(0)

if len(lines) < 3:
    print("TOO_FEW_LINES")
    sys.exit(0)

line3 = lines[2]
expected_line3 = f"argument-hint: '{expected_hint}'"
if line3 != expected_line3:
    print(f"LINE3_MISMATCH: got {line3!r}, expected {expected_line3!r}")
    sys.exit(0)

raw = "\n".join(lines)
parts = raw.split('---\n', 2)
if len(parts) < 3:
    print("NO_FRONTMATTER")
    sys.exit(0)

try:
    data = yaml.safe_load(parts[1])
except Exception as e:
    print(f"YAML_ERROR: {e}")
    sys.exit(0)

parsed_hint = data.get('argument-hint')
if parsed_hint != expected_hint:
    print(f"HINT_MISMATCH: got {parsed_hint!r}, expected {expected_hint!r}")
    sys.exit(0)

print("OK")
PY
)"

if [ "$wrap_res" = "OK" ]; then
    pass "D1, D2 / AT-425-2, AT-425-4: .claude/commands/wrap.md has valid YAML frontmatter with single-quoted argument-hint"
else
    fail "D1, D2 / AT-425-2, AT-425-4: .claude/commands/wrap.md frontmatter assertion failed ($wrap_res)"
fi

# 9. wrap.md surgical single-line edit preservation (D6 / AT-425-2)
wrap_surgeries="$(python3 - "$WRAP_MD" <<'PY'
import sys
path = sys.argv[1]
try:
    with open(path, 'r', encoding='utf-8') as f:
        lines = f.read().splitlines()
except Exception as e:
    print(f"ERROR: {e}")
    sys.exit(0)

if len(lines) < 5:
    print("TOO_FEW_LINES")
    sys.exit(0)

if lines[0] != "---":
    print("LINE1_MISMATCH")
    sys.exit(0)
if lines[1] != "description: Close out this session, or refresh its handoff snapshot mid-flight. Writes ops/handoffs/handoff-<seat>-<date>.txt and prints the command that resumes from it. Prototype door for #85; when scripts/ops/wrap.sh exists this file calls it instead of prompting for the same work.":
    print("LINE2_MISMATCH")
    sys.exit(0)
if not lines[3].startswith("allowed-tools: "):
    print("LINE4_MISMATCH")
    sys.exit(0)
if lines[4] != "---":
    print("LINE5_MISMATCH")
    sys.exit(0)

print("OK")
PY
)"

if [ "$wrap_surgeries" = "OK" ]; then
    pass "D6 / AT-425-2: .claude/commands/wrap.md lines 1-2, 4-5 preserved"
else
    fail "D6 / AT-425-2: .claude/commands/wrap.md surrounding lines corrupted ($wrap_surgeries)"
fi

banner "4. Repository-Wide Command Assertions (D3 / AT-425-5)"

# 10. All .claude/commands/*.md parse cleanly via yaml.safe_load (D3 / AT-425-5)
repo_claude_commands=("$REPO/.claude/commands"/*.md)
repo_claude_failed=0
for cmd_file in "${repo_claude_commands[@]}"; do
    [ -f "$cmd_file" ] || continue
    if ! validate_single_file "$cmd_file" >/dev/null 2>&1; then
        echo "  - Invalid frontmatter in $cmd_file" >&2
        repo_claude_failed=$((repo_claude_failed + 1))
    fi
done

if [ "$repo_claude_failed" -eq 0 ]; then
    pass "D3 / AT-425-5: all files in .claude/commands/*.md contain valid YAML frontmatter"
else
    fail "D3 / AT-425-5: $repo_claude_failed file(s) in .claude/commands/*.md have invalid frontmatter"
fi

# 11. All commands/*.md parse cleanly if directory exists (D3)
if [ -d "$REPO/commands" ]; then
    repo_src_failed=0
    for cmd_file in "$REPO/commands"/*.md; do
        [ -f "$cmd_file" ] || continue
        if ! validate_single_file "$cmd_file" >/dev/null 2>&1; then
            echo "  - Invalid frontmatter in $cmd_file" >&2
            repo_src_failed=$((repo_src_failed + 1))
        fi
    done
    if [ "$repo_src_failed" -eq 0 ]; then
        pass "D3: all files in commands/*.md contain valid YAML frontmatter"
    else
        fail "D3: $repo_src_failed file(s) in commands/*.md have invalid frontmatter"
    fi
else
    pass "D3: commands/*.md directory not yet present (#416 pending)"
fi

banner "Summary"
printf 'Total: %d, Passed: %d, Failed: %d\n' "$TOTAL" "$PASSED" "$FAILED"

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
exit 0
