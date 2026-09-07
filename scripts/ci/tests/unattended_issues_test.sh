#!/usr/bin/env bash
# Contract test for unattended.yml changes and issue forms (D6, D8, D9, D10, D14, D15, D22-D25)

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WF="${WORKFLOW_FILE:-$REPO/.github/workflows/unattended.yml}"
INTENT_FORM="${INTENT_FORM_FILE:-$REPO/.github/ISSUE_TEMPLATE/intent.yml}"
BUG_FORM="${BUG_FORM_FILE:-$REPO/.github/ISSUE_TEMPLATE/bug.yml}"
CONFIG="${CONFIG_FILE:-$REPO/.github/ISSUE_TEMPLATE/config.yml}"
INTENT_MD="${INTENT_MD_FILE:-$REPO/intent/117-typed-intake/intent.md}"

banner() { printf '\n--- %s\n' "$*"; }

SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

FAILURES=0

# The origin/main baseline is resolved ONCE, here, and by its own name.
# Two checks below (D8's pull_request trigger, D15's unchanged
# permission blocks) compare this file against its base revision. Where
# origin/main is not a local ref the comparison cannot run at all, and
# reporting that as a D8 or D15 verdict would claim a result nobody
# computed — on the two checks that guard the fork-secrets surface.
banner "Baseline (prerequisite for the D8 and D15 unchanged-block comparisons)"
BASELINE_WF=""
if BASELINE_TXT="$(git -C "$REPO" show origin/main:.github/workflows/unattended.yml 2>/dev/null)"; then
    BASELINE_WF="$SCRATCH/baseline-unattended.yml"
    printf '%s\n' "$BASELINE_TXT" > "$BASELINE_WF"
    echo "PASS: baseline origin/main resolved"
else
    echo "FAIL: baseline origin/main unavailable — the unchanged-block comparisons cannot run; check out with fetch-depth: 0 or run 'git fetch origin main' first" >&2
    FAILURES=$((FAILURES + 1))
fi

banner "Workflow checks (D6, D8, D9, D10, D14, D15)"
python3 -c "
import sys, yaml, re, os

wf_path = sys.argv[1]
try:
    with open(wf_path) as f:
        d = yaml.safe_load(f)
except Exception as e:
    print(f'FAIL: Workflow missing or unparseable: {e}')
    sys.exit(1)

failures = 0
def fail(msg):
    global failures
    failures += 1
    print(f'FAIL: {msg}', file=sys.stderr)

def pass_check(msg):
    print(f'PASS: {msg}')

on_block = d.get('on', d.get(True, {}))
try:
    with open(sys.argv[2]) as f:
        origin_d = yaml.safe_load(f) or {}
except Exception:
    origin_d = {}

try:
    if on_block.get('issues', {}).get('types') == ['opened']:
        pass_check('D6: issues trigger has only opened')
    else:
        fail('D6: issues trigger not exactly [opened]')
except Exception as e:
    fail(f'D6: {e}')

try:
    c = d.get('concurrency', {})
    expected_term = '\${{ github.event.pull_request.number || github.event.issue.number || inputs.number }}'
    group = c.get('group', '')
    if expected_term in group:
        pass_check('D10: concurrency group correct')
    else:
        fail('D10: concurrency group incorrect')
    
    triage = d.get('jobs', {}).get('triage', {})
    steps = triage.get('steps', [])
    triage_step = next((s for s in steps if s.get('name') == 'Triage'), None)
    if triage_step and triage_step.get('env', {}).get('NUMBER') == '\${{ github.event.pull_request.number || github.event.issue.number || inputs.number }}':
        pass_check('D10: NUMBER env correct')
    else:
        fail('D10: NUMBER env incorrect')
except Exception as e:
    fail(f'D10: {e}')

try:
    if origin_d:
        pr = d.get('on', d.get(True, {})).get('pull_request')
        origin_pr = origin_d.get('on', origin_d.get(True, {})).get('pull_request')
        if pr and origin_pr and pr == origin_pr:
            pass_check('D8: pull_request trigger unchanged')
        else:
            fail('D8: pull_request trigger changed or missing')
except Exception as e:
    fail(f'D8: {e}')

try:
    triage = d.get('jobs', {}).get('triage', {})
    expected_if = \"github.event_name == 'issues' && github.event.issue.user.type != 'Bot'\"
    actual_if = re.sub(r'\s+', ' ', triage.get('if', '')).strip()
    if actual_if == expected_if:
        pass_check('D8, D14: triage job if correctly formulated')
    else:
        fail(f'D8, D14: triage job if incorrect (expected {expected_if}, got {actual_if})')
except Exception as e:
    fail(f'D8, D14: {e}')

try:
    triage = d.get('jobs', {}).get('triage', {})
    steps = triage.get('steps', [])
    triage_step = next((s for s in steps if s.get('name') == 'Triage'), None)
    if not triage_step:
        fail('D14: Triage step missing')
    else:
        run_txt = triage_step.get('run', '')
        if '\"\$NUMBER\"' in run_txt and '\${{' not in run_txt:
            pass_check('D14: triage step \"\$NUMBER\" and no \${{')
        else:
            fail('D14: triage step run incorrect')
except Exception as e:
    fail(f'D14: {e}')

try:
    triage = d.get('jobs', {}).get('triage', {})
    p = triage.get('permissions', {})
    if p.get('issues') == 'write' and p.get('contents') == 'read' and len(p) == 2:
        pass_check('D14: triage job permissions are correct')
    else:
        fail('D14: triage job permissions incorrect')
except Exception as e:
    fail(f'D14: {e}')

try:
    if origin_d:
        dispatch = d.get('jobs', {}).get('dispatch', {})
        origin_dispatch = origin_d.get('jobs', {}).get('dispatch', {})
        if dispatch.get('permissions') == origin_dispatch.get('permissions'):
            pass_check('D15: dispatch job permissions are correct')
        else:
            fail('D15: dispatch job permissions incorrect')
        
        fp = d.get('permissions', {})
        origin_fp = origin_d.get('permissions', {})
        if fp == origin_fp:
            pass_check('D15: file-level permissions unchanged')
        else:
            fail('D15: file-level permissions changed')
        
    jobs = d.get('jobs', {})
    jobs_with_issues_write = [name for name, job in jobs.items() if job.get('permissions', {}).get('issues') == 'write']
    if jobs_with_issues_write == ['triage']:
        pass_check('D14, D15: only triage job carries issues: write')
    else:
        fail(f'D14, D15: issues: write on incorrect jobs: {jobs_with_issues_write}')
except Exception as e:
    fail(f'D15: {e}')

try:
    resolve = d.get('jobs', {}).get('resolve', {})
    expected_if = \"!cancelled() && ( (github.event_name == \'issues\' && github.event.issue.user.type != \'Bot\' && needs.triage.result == \'success\') || (github.event_name != \'issues\' && (github.event_name == \'workflow_dispatch\' || github.event.pull_request.head.repo.full_name == github.repository)) )\"
    actual_if = re.sub(r'\s+', ' ', resolve.get('if', '')).strip()
    if actual_if == expected_if:
        pass_check('D9: resolve job if correctly formulated')
    else:
        fail(f'D9: resolve job if incorrect (expected {expected_if}, got {actual_if})')
except Exception as e:
    fail(f'D9: {e}')

try:
    ci_gates_path = os.path.join(os.path.dirname(wf_path), 'ci-gates.yml')
    if os.path.exists(ci_gates_path):
        with open(ci_gates_path) as f2:
            ci_gates = f2.read()
        if 'scripts/ci/tests/intake_triage_test.sh' in ci_gates and 'scripts/ci/tests/unattended_issues_test.sh' in ci_gates:
            pass_check('D13: ci-gates runs both tests')
        else:
            fail('D13: ci-gates does not run both tests')
except Exception as e:
    fail(f'D13: {e}')

sys.exit(failures)
" "$WF" "$BASELINE_WF" || FAILURES=$((FAILURES + $?))

banner "Forms checks (D22, D23, D24, D25)"
python3 -c "
import sys, yaml, os

failures = 0
def fail(msg):
    global failures
    failures += 1
    print(f'FAIL: {msg}', file=sys.stderr)

def pass_check(msg):
    print(f'PASS: {msg}')

intent = {}
bug = {}
config = {}
try:
    with open(sys.argv[1]) as f:
        intent = yaml.safe_load(f) or {}
except Exception: pass
try:
    with open(sys.argv[2]) as f:
        bug = yaml.safe_load(f) or {}
except Exception: pass
try:
    with open(sys.argv[3]) as f:
        config = yaml.safe_load(f) or {}
except Exception: pass


# D22: parse as issue-form YAML with exact labels, required: flags, three Severity options
try:
    intent_labels = intent.get('labels', [])
    if intent_labels == ['intent:new']:
        pass_check('D22: intent form labels correct')
    else:
        fail('D22: intent form labels incorrect')
    
    bug_labels = bug.get('labels', [])
    if bug_labels == ['bug']:
        pass_check('D22: bug form labels correct')
    else:
        fail('D22: bug form labels incorrect')
    
    # Check Severity options in bug
    severity_body = next((i for i in bug.get('body', []) if i.get('attributes', {}).get('label') == 'Severity'), None)
    if severity_body and severity_body.get('attributes', {}).get('options') == ['blocks the loop', 'degrades a rung', 'cosmetic'] and severity_body.get('validations', {}).get('required') == True:
        pass_check('D22: bug form Severity options correct')
    else:
        fail('D22: bug form Severity options incorrect')
except Exception as e:
    fail(f'D22: {e}')

# D24, D25: no title: or checkboxes, config.yml blank_issues_enabled: false, no contact_links
try:
    if 'title' not in intent and 'title' not in bug:
        pass_check('D24: no title in forms')
    else:
        fail('D24: title present in forms')
        
    has_checkboxes = False
    for f in [intent, bug]:
        for i in f.get('body', []):
            if i.get('type') == 'checkboxes':
                has_checkboxes = True
    if not has_checkboxes:
        pass_check('D24: no checkboxes in forms')
    else:
        fail('D24: checkboxes present in forms')
    
    if config.get('blank_issues_enabled') == False and 'contact_links' not in config:
        pass_check('D25: config.yml correct')
    else:
        fail('D25: config.yml incorrect')
except Exception as e:
    fail(f'D24, D25: {e}')

sys.exit(failures)
" "$INTENT_FORM" "$BUG_FORM" "$CONFIG" || FAILURES=$((FAILURES + $?))

# Check D23
python3 -c "
import sys, yaml, re

failures = 0
def fail(msg):
    global failures
    failures += 1
    print(f'FAIL: {msg}', file=sys.stderr)
def pass_check(msg):
    print(f'PASS: {msg}')

intent = {}
md_text = ''
try:
    with open(sys.argv[1]) as f:
        intent = yaml.safe_load(f) or {}
except Exception: pass
try:
    with open(sys.argv[2]) as f:
        md_text = f.read()
except Exception: pass


md_headers = re.findall(r'^## (.*)', md_text, re.MULTILINE)
form_labels = [i.get('attributes', {}).get('label') for i in intent.get('body', []) if i.get('type') == 'textarea']
if len(md_headers) == 5 and md_headers == form_labels:
    pass_check('D23: intent form matches intent.md headers')
else:
    fail(f'D23: intent form headers mismatch (md: {md_headers}, form: {form_labels})')

sys.exit(failures)
" "$INTENT_FORM" "$INTENT_MD" || FAILURES=$((FAILURES + $?))

if [ "$FAILURES" -gt 0 ]; then
    echo "Total failures: $FAILURES" >&2
    exit 1
fi
