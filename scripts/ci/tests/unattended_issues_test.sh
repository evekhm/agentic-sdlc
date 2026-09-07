#!/usr/bin/env bash
# Contract test for unattended.yml changes

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WF="$REPO/.github/workflows/unattended.yml"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

[ -f "$WF" ] || fail "Workflow file missing"

banner() { printf '\n--- %s\n' "$*"; }

python3 -c "
import sys, yaml
with open('$WF') as f:
    d = yaml.safe_load(f)

print('--- D6: issues trigger')
try:
    assert d['on']['issues']['types'] == ['opened'], 'issues trigger not exactly [opened]'
    print('PASS: D6: issues trigger has only opened')
except Exception as e:
    print(f'FAIL: D6: {e}')
    sys.exit(1)
" || fail "D6 failed"

python3 -c "
import sys, yaml
with open('$WF') as f:
    d = yaml.safe_load(f)

print('--- D14: triage job permissions')
try:
    p = d['jobs']['triage']['permissions']
    assert p.get('issues') == 'write' and p.get('contents') == 'read', 'triage permissions incorrect'
    print('PASS: D14: triage job permissions are correct')
except Exception as e:
    print(f'FAIL: D14: {e}')
    sys.exit(1)
" || fail "D14 failed"

python3 -c "
import sys, yaml
with open('$WF') as f:
    d = yaml.safe_load(f)

print('--- D9, D14: triage job if conjunction')
try:
    t_if = d['jobs']['triage']['if']
    assert \"github.event_name == 'issues'\" in t_if, 'missing issues check'
    assert \"github.event.issue.user.type != 'Bot'\" in t_if, 'missing Bot check'
    print('PASS: D9, D14: triage job if correctly formulated')
except Exception as e:
    print(f'FAIL: D9, D14: {e}')
    sys.exit(1)
" || fail "D9, D14 failed"

python3 -c "
import sys, yaml
with open('$WF') as f:
    d = yaml.safe_load(f)

print('--- D14: resolve job needs triage')
try:
    needs = d['jobs']['resolve']['needs']
    assert needs == 'triage' or 'triage' in needs, 'resolve does not need triage'
    print('PASS: D14: resolve needs triage')
except Exception as e:
    print(f'FAIL: D14: {e}')
    sys.exit(1)
" || fail "D14 failed"

python3 -c "
import sys, yaml
with open('$WF') as f:
    d = yaml.safe_load(f)

print('--- D14: resolve job if disjunction')
try:
    r_if = d['jobs']['resolve']['if']
    assert '!cancelled()' in r_if, 'missing !cancelled()'
    assert \"github.event_name == 'issues'\" in r_if, 'missing issues check'
    print('PASS: D14: resolve job if has both cancelled and issues check')
except Exception as e:
    print(f'FAIL: D14: {e}')
    sys.exit(1)
" || fail "D14 failed"

