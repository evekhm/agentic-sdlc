#!/usr/bin/env bash
# Tests for scripts/ci/merge_gate.sh and scripts/ci/escalate.sh (#64).
#
#   bash scripts/ci/tests/merge_gate_test.sh
#
# Hermetic: a stub `gh` first on PATH answers every read from fixture
# files under $FX and records every write in $WRITES; a stub `python3`
# answers `execution.py --loop <key>` and hands everything else to the
# real interpreter. No network, no token.
#
# Each scenario names the Decision row it pins. The green fixture is
# built once (mk_green) and every flip scenario changes exactly one
# thing from it, so a failure names the conjunct that moved. MG-21
# onward cover Amendment r2 (D23-D28) and S3: the trusted-writer set
# narrowed to the merge actor's own login, resolved via `gh api user`
# rather than guessed, and conjunct (2) read from `mergeStateStatus`
# rather than branch-protection required checks.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
GATE="$REPO/scripts/ci/merge_gate.sh"
ESCALATE="$REPO/scripts/ci/escalate.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }
banner() { printf '\n--- %s\n' "$*"; }

FX="$WORK/fx"
WRITES="$WORK/writes.log"
INVOKES="$WORK/invokes.log"
mkdir -p "$WORK/bin" "$FX"
export PATH="$WORK/bin:$PATH"
export FX WRITES INVOKES
export GITHUB_REPOSITORY="evekhm/agentic-sdlc"
export DRY_RUN=0
# #64 D24: the gate's own check run is excluded from conjunct (2) by its
# owning workflow-run id, not by name — fix it here so fixtures can
# stamp the gate's own check with the same id.
export GITHUB_RUN_ID=999
# Zero the retry sleep so the bounded UNKNOWN re-read (D24) does not
# slow the suite down.
export MERGE_STATE_RETRY_SLEEP=0

MERGER='evekhm-merge-actor-app[bot]'
ACTIONS='github-actions[bot]'
ATLAS='evekhm-atlas-app[bot]'
H="$(printf 'a%.0s' {1..40})"
H0="$(printf 'b%.0s' {1..40})"
export MERGER ACTIONS

for tool in claude gemini agy curl; do
  printf '#!/usr/bin/env bash\necho "%s stub called" >&2\nexit 1\n' "$tool" > "$WORK/bin/$tool"
  chmod +x "$WORK/bin/$tool"
done

cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "gh $*" >> "$INVOKES"
record_write() {
  printf '%s\n' "gh $*" >> "$WRITES"
  local prev=""
  for a in "$@"; do
    case "$prev" in --body-file|-F|--field) f="${a#body=@}"; [ -f "$f" ] && cat "$f" >> "$WRITES";; esac
    prev="$a"
  done
}
case "${1:-} ${2:-}" in
  "pr view")
    n="$3"
    [ -f "$FX/pr-$n.json" ] && { cat "$FX/pr-$n.json"; exit 0; }
    echo "no pull request fixture $n" >&2; exit 1;;
  "issue view")
    n="$3"
    [ -f "$FX/issue-$n.json" ] && { cat "$FX/issue-$n.json"; exit 0; }
    echo '{"labels":[]}'; exit 0;;
  "pr merge"|"issue edit"|"issue comment")
    record_write "$@"; exit 0;;
  "api user")
    # S3, D23: the merge actor's own login, resolved from the token in
    # scope. $FX/user-unreadable simulates an unresolvable identity.
    [ -f "$FX/user-unreadable" ] && { echo "unauthorized" >&2; exit 1; }
    printf '{"login":"%s"}\n' "$MERGER"; exit 0;;
  "api graphql")
    # D24: mergeStateStatus + check roll-up (with each CheckRun's owning
    # workflow-run id). $FX/mergestate-<pr>.state holds one state per
    # line, consumed in order across repeated calls (simulating GitHub's
    # lazy UNKNOWN -> verdict computation); the last line repeats once
    # exhausted. $FX/mergestate-<pr>.checks holds `|`-separated rows
    # (bash `read` collapses consecutive TAB delimiters as IFS
    # whitespace, which would swallow an empty middle field):
    # type(check|status)|name|conclusion-or-state|run-id
    # (run-id empty for a StatusContext or an unowned CheckRun).
    pr=""
    args=("$@")
    for ((i = 0; i < ${#args[@]}; i++)); do
      if [ "${args[$i]}" = "-F" ] && [[ "${args[$((i + 1))]:-}" == pr=* ]]; then
        pr="${args[$((i + 1))]#pr=}"
      fi
    done
    [ -n "$pr" ] || { echo "gh stub: graphql call missing -F pr=" >&2; exit 1; }
    if [ -f "$FX/mergestate-$pr.unreadable" ]; then exit 1; fi
    if [ ! -f "$FX/mergestate-$pr.state" ]; then
      echo '{"data":{"repository":{"pullRequest":null}}}'; exit 0
    fi
    cnt_file="$FX/mergestate-$pr.count"
    n=0; [ -f "$cnt_file" ] && n="$(cat "$cnt_file")"
    echo $((n + 1)) > "$cnt_file"
    mapfile -t states < "$FX/mergestate-$pr.state"
    idx="$n"; [ "$idx" -lt "${#states[@]}" ] || idx=$((${#states[@]} - 1))
    state="${states[$idx]}"
    checks_json="[]"
    if [ -f "$FX/mergestate-$pr.checks" ]; then
      checks_json="$(while IFS='|' read -r ty name val runid; do
        [ -n "$ty" ] || continue
        if [ "$ty" = check ]; then
          if [ -n "$runid" ]; then
            jq -nc --arg n "$name" --arg c "$val" --argjson r "$runid" \
              '{__typename:"CheckRun", name:$n, conclusion:$c, checkSuite:{workflowRun:{databaseId:$r}}}'
          else
            jq -nc --arg n "$name" --arg c "$val" \
              '{__typename:"CheckRun", name:$n, conclusion:$c, checkSuite:{workflowRun:null}}'
          fi
        else
          jq -nc --arg n "$name" --arg s "$val" '{__typename:"StatusContext", context:$n, state:$s}'
        fi
      done < "$FX/mergestate-$pr.checks" | jq -s .)"
    fi
    jq -nc --arg ms "$state" --argjson checks "$checks_json" \
      '{data: {repository: {pullRequest: {mergeStateStatus: $ms, commits: {nodes: [{commit: {statusCheckRollup: {contexts: {nodes: $checks}}}}]}}}}}'
    exit 0;;
esac
if [ "${1:-}" = api ]; then
  method=GET path="" skip=0
  for a in "${@:2}"; do
    if [ "$skip" = 1 ]; then skip=0; [ "$prevflag" = -X ] && method="$a"; continue; fi
    case "$a" in
      -X|-F|-f|--field|--input|-q|--jq) prevflag="$a"; skip=1;;
      -*) ;;
      *) [ -n "$path" ] || path="$a";;
    esac
  done
  if [ "$method" != GET ]; then record_write "$@"; echo '{"id":9001}'; exit 0; fi
  p="${path%%\?*}"
  case "$p" in
    repos/*/issues/*/comments)
      n="${p#*/issues/}"; n="${n%/comments}"
      [ -f "$FX/comments-$n.unreadable" ] && exit 1
      if [ -f "$FX/comments-$n.json" ]; then cat "$FX/comments-$n.json"; else echo '[]'; fi
      exit 0;;
    repos/*/contents/*)
      rel="${p#*/contents/}"; t="$FX/tree/$rel"
      if [ -d "$t" ]; then
        for e in "$t"/* "$t"/.[!.]*; do
          [ -e "$e" ] || continue
          if [ -d "$e" ]; then ty=dir; else ty=file; fi
          jq -nc --arg n "$(basename "$e")" --arg t "$ty" '{name: $n, type: $t}'
        done | jq -s .
        exit 0
      fi
      if [ -f "$t" ]; then jq -n --arg c "$(base64 -w0 "$t")" '{content: $c, encoding: "base64"}'; exit 0; fi
      echo '{"message":"Not Found","status":"404"}' >&2; exit 1;;
    repos/*)
      echo '{"default_branch":"main"}'; exit 0;;
  esac
fi
echo "gh stub: unhandled: $*" >&2
exit 1
STUB
chmod +x "$WORK/bin/gh"

# python3 stub: --loop answers come from $FX/loop-<key>; anything else is
# the real interpreter (base64 and jq do not need it, but escalate.sh's
# callers might).
cat > "$WORK/bin/python3" <<'STUB'
#!/usr/bin/env bash
if [ "${2:-}" = "--loop" ]; then
  [ -f "$FX/loop-$3" ] || exit 1
  cat "$FX/loop-$3"; exit 0
fi
exec /usr/bin/python3 "$@"
STUB
chmod +x "$WORK/bin/python3"

# --- fixture builders --------------------------------------------------------
loop_limits() { # <autonomous> <max-dispatch> <max-cost>
  printf '%s\n' "$1" > "$FX/loop-autonomous_merge"
  printf '%s\n' "$2" > "$FX/loop-max_rung_dispatches_per_issue"
  printf '%s\n' "$3" > "$FX/loop-max_cost_usd_per_issue"
}
# pr_fixture: every field has a green default; override through the
# named variables before calling. mergeStateStatus and the check
# roll-up are a separate fixture (mergestate_fixture/mergestate_checks,
# D24) since the gate reads them over GraphQL, never from `gh pr view`.
PR_BODY='Refs #456'; PR_AUTHOR='evekhm-odyssey-app[bot]'; PR_HEADREPO="$GITHUB_REPOSITORY"
PR_BASE='main'; PR_LABELS='[]'; PR_CLOSING='[]'; PR_HEAD="$H"; PR_STATE='OPEN'; PR_HEADREF='odyssey/456-thing'
pr_fixture() { # <number>
  jq -nc --argjson n "$1" --arg body "$PR_BODY" --arg author "$PR_AUTHOR" --arg hr "$PR_HEADREPO" \
    --arg base "$PR_BASE" --argjson labels "$PR_LABELS" --argjson closing "$PR_CLOSING" \
    --arg head "$PR_HEAD" --arg headref "$PR_HEADREF" --arg state "$PR_STATE" \
    '{number: $n, state: $state, body: $body, author: {login: $author}, headRefName: $headref,
      headRefOid: $head, headRepository: {nameWithOwner: $hr}, baseRefName: $base,
      labels: ($labels | map({name: .})), closingIssuesReferences: ($closing | map({number: .}))}' > "$FX/pr-$1.json"
}
issue_fixture() { # <number> [label ...]
  local n="$1"; shift
  printf '%s\n' "$@" | jq -R 'select(length > 0) | {name: .}' | jq -sc --argjson n "$n" '{number: $n, labels: .}' > "$FX/issue-$n.json"
}
comment() { # <login> <body> [created_at] [id] [type]
  jq -nc --arg l "$1" --arg b "$2" --arg c "${3:-2026-01-01T00:00:00Z}" --argjson i "${4:-$RANDOM}" --arg t "${5:-Bot}" \
    '{id: $i, user: {login: $l, type: $t}, body: $b, created_at: $c}'
}
comments_fixture() { # <number> <comment-json>...
  local n="$1"; shift
  printf '%s\n' "$@" | jq -sc . > "$FX/comments-$n.json"
}
consensus_ledger() { # <pr> <argus-oid|-> <atlas-oid|-> [row ...]   row = id:severity:status:peer
  local pr="$1" a="$2" b="$3"; shift 3
  local out="### Findings ledger for #$pr"$'\n'"<!-- consensus-ledger:$pr -->"
  [ "$a" = - ] || out="$out"$'\n'"<!-- reviewed-head:argus:$a -->"
  [ "$b" = - ] || out="$out"$'\n'"<!-- reviewed-head:atlas:$b -->"
  local r; for r in "$@"; do out="$out"$'\n'"<!-- ledger-row:$r -->"; done
  printf '%s\n%s\n' "$out" "<!-- consensus-ledger-end -->"
}
loop_ledger() { # <issue> [row-text ...]   row-text = what follows "loop-ledger-row: "
  local n="$1"; shift
  local out="### Loop ledger for #$n"$'\n'$'\n'"<!-- loop-ledger:$n -->"
  local r; for r in "$@"; do out="$out"$'\n'"- row <!-- loop-ledger-row: $r -->"; done
  printf '%s\n%s\n' "$out" "<!-- loop-ledger-end -->"
}
# D24: mergeStateStatus per pull request, one value per re-read attempt
# (repeats the last value once exhausted — GitHub's lazy computation
# means the first read after a push is often UNKNOWN and a later one
# settles).
mergestate_fixture() { # <pr> <state> [state ...]
  local pr="$1"; shift
  printf '%s\n' "$@" > "$FX/mergestate-$pr.state"
}
# D24: the check roll-up backing mergeStateStatus. Each row:
#   check|<name>|<conclusion|empty-for-pending>|<run-id|empty>
#   status|<name>|<state>|(ignored)
mergestate_checks() { # <pr> <row>...
  local pr="$1"; shift
  printf '%s\n' "$@" > "$FX/mergestate-$pr.checks"
}
row() { printf '%s|%s|%s|%s' "$1" "$2" "$3" "$4"; } # <type> <name> <val> <runid>
# The green roll-up: the gate's own check run (excluded by run id, D24)
# plus one other check and one status context, both green.
GREEN_CHECKS=(
  "$(row check merge-gate '' 999)"
  "$(row check 'execution — bindings' SUCCESS 1001)"
  "$(row status 'argus via gh-actions' SUCCESS '')"
)
# D13: a dispatch row at rung n carries the merged head that opened rung
# n, so it records that rung n-1 merged; three dispatches (2, 3, 4) mean
# rungs 1-3 merged and the issue sits at rung 4, status:implementing.
GREEN_LOOP_ROWS=(
  "dispatch rung:2 head-oid:$H0 event:e1 pr:11 at:2026-01-01T00:00:00Z cost:5.00"
  "dispatch rung:3 head-oid:$H0 event:e2 pr:12 at:2026-01-02T00:00:00Z cost:5.00"
  "dispatch rung:4 head-oid:$H0 event:e3 pr:13 at:2026-01-03T00:00:00Z cost:10.00"
)
mk_green() {
  rm -rf "$FX"; mkdir -p "$FX"; : > "$WRITES"; : > "$INVOKES"
  loop_limits true 12 50.00
  PR_BODY='Refs #456'; PR_AUTHOR='evekhm-odyssey-app[bot]'; PR_HEADREPO="$GITHUB_REPOSITORY"
  PR_BASE='main'; PR_LABELS='[]'; PR_CLOSING='[]'; PR_HEAD="$H"; PR_STATE='OPEN'; PR_HEADREF='odyssey/456-thing'
  pr_fixture 123
  mergestate_fixture 123 CLEAN
  mergestate_checks 123 "${GREEN_CHECKS[@]}"
  issue_fixture 456 status:implementing
  # D23: the trusted writer is the merge actor's own login alone —
  # github-actions[bot] no longer counts, so the green baseline's
  # state-carrying comments are authored by $MERGER.
  comments_fixture 456 "$(comment "$MERGER" "$(loop_ledger 456 "${GREEN_LOOP_ROWS[@]}")" 2026-01-03T00:00:00Z 700)"
  comments_fixture 123 "$(comment "$MERGER" "$(consensus_ledger 123 "$H" "$H" R1-1:high:fixed:none R1-2:normal:open:none)" 2026-01-04T00:00:00Z 800)"
}

OUT=""
run() { # <name> <arg...>  — the gate must exit 0 (every decline is green, D15)
  local name="$1"; shift
  local rc=0
  set +e
  OUT="$(bash "$GATE" "$@" 2>&1)"
  rc=$?
  set -e
  [ "$rc" -eq 0 ] || { printf '%s\n' "$OUT" >&2; fail "$name (exit $rc)"; }
  pass "$name (exit 0)"
}
run_fail() { # <script> <name> <arg...>
  local script="$1" name="$2"; shift 2
  local rc=0
  set +e
  OUT="$(bash "$script" "$@" 2>&1)"
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || { printf '%s\n' "$OUT" >&2; fail "$name (expected a non-zero exit)"; }
  pass "$name (exit $rc)"
}
has() { # <literal> <name>
  if printf '%s\n' "$OUT" | grep -qF -- "$1"; then pass "$2"
  else printf '%s\n' "$OUT" >&2; fail "$2 (expected to find: $1)"; fi
}
hasnt() { # <literal> <name>
  if printf '%s\n' "$OUT" | grep -qF -- "$1"; then printf '%s\n' "$OUT" >&2; fail "$2 (did not expect: $1)"
  else pass "$2"; fi
}
wrote() { # <extended-regex> <name>
  if grep -Eq -- "$1" "$WRITES"; then pass "$2"
  else cat "$WRITES" >&2; fail "$2 (no write matching: $1)"; fi
}
not_wrote() { # <extended-regex> <name>
  if grep -Eq -- "$1" "$WRITES"; then cat "$WRITES" >&2; fail "$2 (unexpected write matching: $1)"
  else pass "$2"; fi
}
no_writes() { [ ! -s "$WRITES" ] || { cat "$WRITES" >&2; fail "$1 (a write was attempted)"; }; pass "$1 (no write)"; }
merged() { wrote "^gh pr merge 123 --merge --match-head-commit $H\$" "$1"; }
not_merged() { not_wrote "^gh pr merge" "$1"; }

[ -f "$GATE" ] || fail "merge_gate.sh does not exist"
[ -f "$ESCALATE" ] || fail "escalate.sh does not exist"

# ---------------------------------------------------------------------------
banner "MG-1 · D5 all eleven · D18 true · the green fixture merges, once, pinned to the evaluated head"
mk_green
run "MG-1: green fixture exits 0" 123
merged "MG-1: exactly the one merge write, --match-head-commit pins the evaluated head"
has "conjunct (2): true" "MG-1: the gate's own run is excluded from conjunct (2) by run id (D24)"
has "conjunct (10): true" "MG-1: rung 4 > highest merged rung 3"
[ "$(grep -c '^gh pr merge' "$WRITES")" -eq 1 ] || fail "MG-1: more than one merge write"
not_wrote "loop-ledger-row" "MG-1: the gate writes no ledger row on a merge — the advancer records the merge it observes (D13)"

banner "MG-2 · D18 false · same fixture evaluates, logs the verdict, writes nothing"
mk_green; loop_limits false 12 50.00
run "MG-2: exits 0" 123
has "all eleven conjuncts hold" "MG-2: the verdict is logged"
has "autonomous_merge is false" "MG-2: and names the flag that stopped the write"
no_writes "MG-2"

banner "MG-3 · D23 · a consensus ledger by an untrusted login is prose"
mk_green
comments_fixture 123 "$(comment mallory "$(consensus_ledger 123 "$H" "$H")" 2026-01-04T00:00:00Z 801)"
run "MG-3: exits 0" 123
has "conjunct (3): false" "MG-3: conjunct (3) is false"
has "no consensus ledger for #123 from a trusted writer" "MG-3: and says the ledger it saw does not count"
not_merged "MG-3"

banner "MG-4 · D23 D13 · a loop ledger by an untrusted login is not counted; a trusted one is"
mk_green
rows=(); for i in $(seq 1 12); do rows+=("dispatch rung:1 head-oid:$H0 event:e$i at:2026-01-01T00:00:00Z cost:1.00"); done
comments_fixture 456 "$(comment mallory "$(loop_ledger 456 "${rows[@]}")" 2026-01-03T00:00:00Z 701)"
run "MG-4a: forged 12-row ledger exits 0" 123
hasnt "max_rung_dispatches_per_issue" "MG-4a: the forged rows do not count toward the bound"
merged "MG-4a: and the merge proceeds on the trusted (absent) ledger"
mk_green
comments_fixture 456 "$(comment "$MERGER" "$(loop_ledger 456 "${rows[@]}")" 2026-01-03T00:00:00Z 702)"
run "MG-4b: trusted 12-row ledger exits 0" 123
has "max_rung_dispatches_per_issue exceeded (12/12)" "MG-4b: the bound is named with its numbers"
wrote "^gh api -X PATCH repos/evekhm/agentic-sdlc/issues/comments/702 " "MG-4b: the refusal row is appended to the SAME container comment by id (D13)"
wrote "loop-ledger-row: refusal:budget rung:4 head-oid:$H pr:123 at:" "MG-4b: the row is a refusal:budget keyed on (rung, head-oid, reason)"
wrote "^gh issue edit 456 --add-label status:review-stuck --remove-label status:implementing" "MG-4b: escalate.sh swapped the label (D9)"
wrote "<!-- escalation:status:implementing:budget:$H -->" "MG-4b: the escalation marker carries the head OID, never the pull request number"
not_merged "MG-4b"
mk_green; loop_limits false 12 50.00
comments_fixture 456 "$(comment "$MERGER" "$(loop_ledger 456 "${rows[@]}")" 2026-01-03T00:00:00Z 702)"
run "MG-4c: the bound with autonomous_merge false exits 0" 123
has "max_rung_dispatches_per_issue exceeded (12/12)" "MG-4c: the bound is not under the flag (D18)"
wrote "loop-ledger-row: refusal:budget rung:4 head-oid:$H pr:123 at:" "MG-4c: the refusal row is still written"
not_wrote "^gh issue edit" "MG-4c: no label moves while the flag is false (D18)"
not_wrote "<!-- escalation:" "MG-4c: and no escalation is posted"
not_merged "MG-4c"

banner "MG-5 · D13 · cost bound, summed from trusted dispatch rows only"
mk_green
comments_fixture 456 "$(comment "$MERGER" "$(loop_ledger 456 "dispatch rung:1 head-oid:$H0 event:e1 at:2026-01-01T00:00:00Z cost:30.00" "dispatch rung:2 head-oid:$H0 event:e2 at:2026-01-01T00:00:00Z cost:20.00")" 2026-01-03T00:00:00Z 703)"
run "MG-5: exits 0" 123
has "max_cost_usd_per_issue exceeded (50.00/50.00)" "MG-5: the summed cost reaching the cap is a breach"
not_merged "MG-5"

banner "MG-6 · D13 · an unparseable ledger row is unreadable, and unreadable is not absent"
mk_green
comments_fixture 456 "$(comment "$MERGER" "$(loop_ledger 456 "dispatch: 1 ...")" 2026-01-03T00:00:00Z 704)"
run "MG-6: exits 0" 123
has "cannot parse" "MG-6: the decline names the parse failure"
not_merged "MG-6"
mk_green
: > "$FX/comments-456.unreadable"
run "MG-6b: unreadable issue thread exits 0" 123
has "unreadable" "MG-6b: an unreadable thread declines"
not_merged "MG-6b"

banner "MG-7 · conjunct (6) · D15 · hold on the issue, blocked on the pull request: nothing written"
mk_green; issue_fixture 456 status:implementing hold
run "MG-7a: hold on the issue exits 0" 123
has "halted by hold or blocked" "MG-7a: the halt is named"
no_writes "MG-7a"
mk_green; PR_LABELS='["blocked"]'; pr_fixture 123
run "MG-7b: blocked on the pull request exits 0" 123
has "halted by hold or blocked" "MG-7b: the halt is named"
no_writes "MG-7b"

banner "MG-8 · issue link · #245 · case-insensitive keyword, distinguishable no-link outcome, two links is corrupt input"
mk_green; PR_BODY='refs #456 lower-case'; pr_fixture 123
run "MG-8a: lower-case refs exits 0" 123
merged "MG-8a: lower-case \`refs #456\` resolves the issue"
mk_green; PR_BODY='no link at all'; PR_HEADREF='feature-x'; pr_fixture 123
run "MG-8b: no link exits 0" 123
has "no linked issue" "MG-8b: the outcome is named as no-link, not as a failed conjunct"
hasnt "Decline:" "MG-8b: and is not reported as a decline"
no_writes "MG-8b"
mk_green; PR_BODY='Closes #1 and Fixes #2'; pr_fixture 123
run "MG-8c: two closing links exits 0" 123
has "#1" "MG-8c: names the first"
has "#2" "MG-8c: names the second"
has "two different issues" "MG-8c: and calls it corrupted input"
no_writes "MG-8c"

banner "MG-9 · conjunct (1) · base is the default branch, head is this repository"
mk_green; PR_BASE=develop; pr_fixture 123
run "MG-9a: base develop exits 0" 123
has "conjunct (1): false" "MG-9a: a non-default base fails (1)"
not_merged "MG-9a"
mk_green; PR_HEADREPO='fork/agentic-sdlc'; pr_fixture 123
run "MG-9b: fork head exits 0" 123
has "conjunct (1): false" "MG-9b: a fork head fails (1)"
not_merged "MG-9b"

banner "MG-10 · conjunct (7) · the merging identity is never the author"
mk_green; PR_AUTHOR="$MERGER"; pr_fixture 123
run "MG-10: exits 0" 123
has "conjunct (7): false" "MG-10: author == merge actor fails (7)"
not_merged "MG-10"

banner "MG-11 · conjunct (2) · D24 · mergeStateStatus and its check roll-up"
mk_green
mergestate_fixture 123 BLOCKED
run "MG-11a: mergeStateStatus BLOCKED exits 0" 123
has "conjunct (2): false" "MG-11a: BLOCKED fails (2)"
has "mergeStateStatus is BLOCKED" "MG-11a: names the state"
not_merged "MG-11a"
mk_green
mergestate_checks 123 "$(row check merge-gate '' 999)"
run "MG-11b: only the gate's own run in the roll-up exits 0" 123
has "conjunct (2): false" "MG-11b: no check besides the gate itself fails (2)"
has "no check besides the gate's own run" "MG-11b: names the reason"
not_merged "MG-11b"
mk_green
mergestate_checks 123 "$(row check merge-gate '' 999)" "$(row check 'execution — bindings' FAILURE 1001)"
run "MG-11c: a failing check exits 0" 123
has "conjunct (2): false" "MG-11c: a failing check fails (2)"
has "execution — bindings=FAILURE" "MG-11c: and is named"
not_merged "MG-11c"

banner "MG-12 · conjunct (3) · D7 · verdict heads"
mk_green
comments_fixture 123 "$(comment "$MERGER" "$(consensus_ledger 123 "$H0" "$H")" 2026-01-04T00:00:00Z 802)"
run "MG-12a: argus at an older head exits 0" 123
has "conjunct (3): false" "MG-12a: argus must be at the current head"
not_merged "MG-12a"
mk_green
comments_fixture 123 "$(comment "$MERGER" "$(consensus_ledger 123 "$H" "$H0")" 2026-01-04T00:00:00Z 803)"
run "MG-12b: atlas at an older head, nothing outstanding, exits 0" 123
has "conjunct (3): true" "MG-12b: atlas carries forward (D7)"
merged "MG-12b: and the merge proceeds"
mk_green
comments_fixture 123 "$(comment "$MERGER" "$(consensus_ledger 123 "$H" -)" 2026-01-04T00:00:00Z 804)"
run "MG-12c: atlas never reviewed exits 0" 123
has "conjunct (3): false" "MG-12c: no atlas verdict on record fails D7 (i)"
not_merged "MG-12c"
mk_green; PR_LABELS='["deep-review"]'; pr_fixture 123
comments_fixture 123 "$(comment "$MERGER" "$(consensus_ledger 123 "$H" "$H0")" 2026-01-04T00:00:00Z 805)"
run "MG-12d: atlas older + deep-review label exits 0" 123
has "conjunct (3): false" "MG-12d: an unconsumed deep-review grant blocks carry-forward (D7 (v))"
not_merged "MG-12d"
mk_green
comments_fixture 123 \
  "$(comment "$MERGER" "$(consensus_ledger 123 "$H" "$H0")" 2026-01-04T00:00:00Z 806)" \
  "$(comment "$ATLAS" "Atlas round 1 verdict" 2026-01-02T00:00:00Z 807)" \
  "$(comment evekhm "@evekhm-atlas-app please look at the token path again" 2026-01-05T00:00:00Z 808 User)"
run "MG-12e: human mention of atlas after its last verdict exits 0" 123
has "conjunct (3): false" "MG-12e: an outstanding human mention blocks carry-forward (D7 (iv))"
not_merged "MG-12e"

banner "MG-13 · conjuncts (4) (5) · blocking set and consensus axis from ledger rows"
mk_green
comments_fixture 123 "$(comment "$MERGER" "$(consensus_ledger 123 "$H" "$H" R1-1:security:open:pending)" 2026-01-04T00:00:00Z 809)"
run "MG-13a: open security row exits 0" 123
has "conjunct (4): false" "MG-13a: an open security row is blocking"
has "conjunct (5): false" "MG-13a: and the axis is pending"
not_merged "MG-13a"
mk_green
comments_fixture 123 "$(comment "$MERGER" "$(consensus_ledger 123 "$H" "$H" R1-1:security:fixed:pending)" 2026-01-04T00:00:00Z 810)"
run "MG-13b: fixed security row without the peer's AGREE exits 0" 123
has "conjunct (4): false" "MG-13b: a security fix needs both AGREEs before it leaves the blocking set (REVIEW.md)"
not_merged "MG-13b"
mk_green
comments_fixture 123 "$(comment "$MERGER" "$(consensus_ledger 123 "$H" "$H" R1-1:high:open:dispute)" 2026-01-04T00:00:00Z 811)"
run "MG-13c: disputed open high row exits 0" 123
has "conjunct (4): false" "MG-13c: open high is blocking"
has "conjunct (5): false" "MG-13c: and a dispute fails the axis"
not_merged "MG-13c"
mk_green
comments_fixture 123 "$(comment "$MERGER" "$(consensus_ledger 123 "$H" "$H" R1-1:security:fixed:agree R1-2:normal:open:none)" 2026-01-04T00:00:00Z 812)"
run "MG-13d: security fixed with both AGREEs, normal open, exits 0" 123
has "conjunct (4): true" "MG-13d: a normal row is never blocking"
merged "MG-13d"
mk_green
comments_fixture 123 "$(comment "$MERGER" "$(consensus_ledger 123 "$H" "$H" "R1-1:severe:open:none")" 2026-01-04T00:00:00Z 813)"
run "MG-13e: a row outside the enum exits 0" 123
has "cannot parse" "MG-13e: an unparseable ledger row is unevaluable, and unevaluable is false"
not_merged "MG-13e"

banner "MG-14 · conjunct (11) · a ledger with no head marker earns nothing"
mk_green
comments_fixture 123 "$(comment "$MERGER" "$(consensus_ledger 123 - -)" 2026-01-04T00:00:00Z 814)"
run "MG-14: exits 0" 123
has "conjunct (11): false" "MG-14: no reviewed-head marker fails (11)"
not_merged "MG-14"

banner "MG-15 · conjunct (10) · D14 · the rung must exceed the highest merged rung"
mk_green
comments_fixture 456 "$(comment "$MERGER" "$(loop_ledger 456 "${GREEN_LOOP_ROWS[@]}" "terminal rung:5 head-oid:$H0 pr:14 at:2026-01-04T00:00:00Z")" 2026-01-03T00:00:00Z 705)"
run "MG-15: exits 0" 123
has "conjunct (10): false" "MG-15: a terminal row at rung 5 records rung 4 merged; rung 4 is not greater than 4"
not_merged "MG-15"

banner "MG-16 · conjunct (9) · rung structural facts, read from the head tree"
mk_green; issue_fixture 456 status:spec
mkdir -p "$FX/tree/intent/456-thing"
printf '# Spec\n\n**Status:** Draft\n**Open questions:** two\n' > "$FX/tree/intent/456-thing/spec.md"
run "MG-16a: a Draft spec at the spec rung exits 0" 123
has "conjunct (9): false" "MG-16a: Draft fails the spec rung's facts"
not_merged "MG-16a"
printf '# Spec\n\n**Status:** Approved (approval = merge of this PR)\n**Open questions:** none\n' > "$FX/tree/intent/456-thing/spec.md"
run "MG-16b: Approved with no open questions exits 0" 123
has "conjunct (9): true" "MG-16b: Approved + none passes (9)"
has "conjunct (10): false" "MG-16b: (10) still fails — rung 2 is below merged rung 3 — so nothing merges"
not_merged "MG-16b"
mkdir -p "$FX/tree/intent/456-other"
run "MG-16c: two intent folders exits 0" 123
has "conjunct (9): false" "MG-16c: more than one intent/456-*/ folder is corrupted state"
not_merged "MG-16c"
mk_green; issue_fixture 456 status:spec
run "MG-16d: spec rung with no artifact in the head tree exits 0" 123
has "conjunct (9): false" "MG-16d: a missing artifact fails (9)"
not_merged "MG-16d"

banner "MG-17 · D10 · self-clearing"
mk_green; issue_fixture 456 status:review-stuck
comments_fixture 456 \
  "$(comment "$MERGER" "$(loop_ledger 456 "${GREEN_LOOP_ROWS[@]}")" 2026-01-03T00:00:00Z 706)" \
  "$(comment "$MERGER" "Escalation: budget at head $H0."$'\n\n'"<!-- escalation:status:implementing:budget:$H0 -->" 2026-01-05T00:00:00Z 707)"
run "MG-17a: budget escalation exits 0" 123
has "budget" "MG-17a: names the live escalation"
has "still live" "MG-17a: a budget escalation never clears itself"
no_writes "MG-17a"
mk_green; issue_fixture 456 status:review-stuck
comments_fixture 456 \
  "$(comment "$MERGER" "$(loop_ledger 456 "${GREEN_LOOP_ROWS[@]}")" 2026-01-03T00:00:00Z 708)" \
  "$(comment "$MERGER" "Escalation: dispute-at-cap at head $H0."$'\n\n'"<!-- escalation:status:implementing:dispute-at-cap:$H0 -->" 2026-01-05T00:00:00Z 709)"
run "MG-17b: dispute-at-cap escalation with consensus at a new head exits 0" 123
wrote "^gh issue edit 456 --add-label status:implementing --remove-label status:review-stuck" "MG-17b: the displaced label is restored"
merged "MG-17b: and D5 is evaluated for the new head"
mk_green; issue_fixture 456 status:review-stuck
comments_fixture 456 \
  "$(comment "$MERGER" "$(loop_ledger 456 "${GREEN_LOOP_ROWS[@]}")" 2026-01-03T00:00:00Z 710)" \
  "$(comment "$MERGER" "<!-- escalation:status:implementing:dispute-at-cap:$H -->" 2026-01-05T00:00:00Z 711)"
run "MG-17c: escalation at the current head exits 0" 123
has "still live" "MG-17c: consensus at the SAME head does not clear the marker"
no_writes "MG-17c"
mk_green; issue_fixture 456 status:review-stuck
comments_fixture 456 \
  "$(comment "$MERGER" "$(loop_ledger 456 "${GREEN_LOOP_ROWS[@]}")" 2026-01-03T00:00:00Z 712)" \
  "$(comment mallory "<!-- escalation:status:implementing:dispute-at-cap:$H0 -->" 2026-01-05T00:00:00Z 713)"
run "MG-17d: marker by an untrusted login exits 0" 123
has "no escalation marker from a trusted writer" "MG-17d: a forged marker does not drive the restore (D23)"
no_writes "MG-17d"

banner "MG-18 · D9 · at the round cap an open security row escalates as security-open"
mk_green; PR_LABELS='["review:3"]'; pr_fixture 123
comments_fixture 123 "$(comment "$MERGER" "$(consensus_ledger 123 "$H" "$H" R1-1:security:open:pending)" 2026-01-04T00:00:00Z 815)"
run "MG-18: exits 0" 123
wrote "loop-ledger-row: refusal:security-open rung:4 head-oid:$H pr:123" "MG-18: the refusal row"
wrote "<!-- escalation:status:implementing:security-open:$H -->" "MG-18: the escalation marker"
not_merged "MG-18"

banner "MG-19 · escalate.sh · D9 D23 · idempotent on a trusted marker only; body is real lines"
mk_green
comments_fixture 456 "$(comment "$MERGER" "<!-- escalation:status:implementing:budget:$H -->" 2026-01-05T00:00:00Z 716)"
run_fail "$ESCALATE" "MG-19a: --head that is not an OID is refused" 456 --reason budget --head 123
run_fail "$ESCALATE" "MG-19b: a reason outside D9's enum is refused" 456 --reason whatever --head "$H"
set +e; OUT="$(bash "$ESCALATE" 456 --reason budget --head "$H" 2>&1)"; rc=$?; set -e
[ "$rc" -eq 0 ] || { printf '%s\n' "$OUT" >&2; fail "MG-19c: escalate exit $rc"; }
has "already" "MG-19c: a trusted marker for (budget, head) is idempotent"
no_writes "MG-19c"
comments_fixture 456 "$(comment mallory "<!-- escalation:status:implementing:budget:$H -->" 2026-01-05T00:00:00Z 717)"
set +e; OUT="$(bash "$ESCALATE" 456 --reason budget --head "$H" 2>&1)"; rc=$?; set -e
[ "$rc" -eq 0 ] || { printf '%s\n' "$OUT" >&2; fail "MG-19d: escalate exit $rc"; }
wrote "^gh issue edit 456 --add-label status:review-stuck --remove-label status:implementing" "MG-19d: a forged marker does not suppress the escalation"
grep -qxF "<!-- escalation:status:implementing:budget:$H -->" "$WRITES" || { cat "$WRITES" >&2; fail "MG-19d: the marker is not on a line of its own (literal \\n in the body)"; }
pass "MG-19d: the marker sits on its own line"
[ "$(grep -c '^gh ' "$WRITES")" -eq 2 ] || { cat "$WRITES" >&2; fail "MG-19d: escalate.sh made other than exactly two writes"; }
pass "MG-19d: exactly two writes (D9)"

banner "MG-20 · D5 D20 · an unevaluable conjunct is a decline: bounds the parser cannot read fail closed, nothing written"
mk_green
rm -f "$FX"/loop-*
run "MG-20: exits 0" 123
has "Failing closed" "MG-20: the decline names the fail-closed rule"
not_merged "MG-20"
no_writes "MG-20"

banner "MG-21 · merge_gate.sh · S3 · an unresolvable merge-actor login fails closed"
mk_green
: > "$FX/user-unreadable"
run "MG-21: exits 0 (a decline, not a script failure)" 123
has "cannot resolve the merge actor's login via 'gh api user'" "MG-21: names the S3 reason"
has "S3" "MG-21: cites the fixing decision"
not_merged "MG-21"
no_writes "MG-21"
rm -f "$FX/user-unreadable"

banner "MG-22 · D23 · github-actions[bot] is narrowed out of the trusted-writer set"
mk_green
comments_fixture 123 "$(comment "$ACTIONS" "$(consensus_ledger 123 "$H" "$H")" 2026-01-04T00:00:00Z 820)"
run "MG-22a: exits 0" 123
has "conjunct (3): false" "MG-22a: a github-actions[bot] consensus ledger no longer counts (D23)"
has "no consensus ledger for #123 from a trusted writer" "MG-22a: named as absent, not forged"
not_merged "MG-22a"
mk_green
rows2=(); for i in $(seq 1 12); do rows2+=("dispatch rung:1 head-oid:$H0 event:e$i at:2026-01-01T00:00:00Z cost:1.00"); done
comments_fixture 456 "$(comment "$ACTIONS" "$(loop_ledger 456 "${rows2[@]}")" 2026-01-03T00:00:00Z 821)"
run "MG-22b: exits 0" 123
hasnt "max_rung_dispatches_per_issue" "MG-22b: a github-actions[bot] loop ledger no longer counts toward the bound (D23)"
merged "MG-22b: and the merge proceeds on the trusted (absent) ledger"

banner "MG-23 · D24 · mergeStateStatus UNKNOWN on every read is unevaluable after bounded retry"
mk_green
mergestate_fixture 123 UNKNOWN
run "MG-23: exits 0" 123
has "conjunct (2): false" "MG-23: persistent UNKNOWN fails (2)"
has "still UNKNOWN after" "MG-23: names the bounded retry"
[ "$(grep -c 'gh api graphql' "$INVOKES")" -eq 4 ] || { cat "$INVOKES" >&2; fail "MG-23: expected exactly 4 graphql reads (1 initial + 3 retries)"; }
pass "MG-23: exactly 4 graphql reads"
not_merged "MG-23"

banner "MG-24 · D24 · mergeStateStatus UNKNOWN then CLEAN on retry succeeds"
mk_green
mergestate_fixture 123 UNKNOWN CLEAN
run "MG-24: exits 0" 123
has "conjunct (2): true" "MG-24: the retry recovers a real verdict"
merged "MG-24: and the merge proceeds"

banner "MG-25 · D24 · an unreadable merge-state/check roll-up is unevaluable"
mk_green
: > "$FX/mergestate-123.unreadable"
run "MG-25: exits 0" 123
has "conjunct (2): false" "MG-25: an unreadable roll-up fails (2)"
has "unreadable" "MG-25: names the reason"
not_merged "MG-25"

banner "MG-26 · D24 · a foreign check literally named merge-gate is NOT excluded — identity, not name"
mk_green
mergestate_checks 123 "$(row check merge-gate '' 999)" "$(row check merge-gate FAILURE 12345)"
run "MG-26: exits 0" 123
has "conjunct (2): false" "MG-26: the foreign merge-gate-named check still counts"
has "merge-gate=FAILURE" "MG-26: and is named as failing"
not_merged "MG-26"

banner "MG-27 · D24 · a pending check (no conclusion yet) fails conjunct (2)"
mk_green
mergestate_fixture 123 UNSTABLE
mergestate_checks 123 "$(row check merge-gate '' 999)" "$(row check 'execution — bindings' '' 1001)"
run "MG-27: exits 0" 123
has "conjunct (2): false" "MG-27: a pending check fails (2)"
has "execution — bindings=PENDING" "MG-27: and is named pending"
not_merged "MG-27"

banner "MG-28 · D27 · mergeStateStatus BEHIND escalates only when autonomous_merge is true"
mk_green
mergestate_fixture 123 BEHIND
run "MG-28a: exits 0" 123
has "conjunct (2): false" "MG-28a: BEHIND fails (2)"
wrote "loop-ledger-row: refusal:behind rung:4 head-oid:$H pr:123" "MG-28a: a refusal:behind row is written"
wrote "^gh issue edit 456 --add-label status:review-stuck --remove-label status:implementing" "MG-28a: and autonomous_merge=true escalates"
wrote "<!-- escalation:status:implementing:behind:$H -->" "MG-28a: with the behind marker"
not_merged "MG-28a"
mk_green; loop_limits false 12 50.00
mergestate_fixture 123 BEHIND
run "MG-28b: exits 0 with autonomous_merge false" 123
wrote "loop-ledger-row: refusal:behind rung:4 head-oid:$H pr:123" "MG-28b: the refusal row is still written"
not_wrote "^gh issue edit" "MG-28b: no label move while the flag is false (D27)"
not_wrote "<!-- escalation:" "MG-28b: and no escalation marker is posted"
not_merged "MG-28b"

banner "MG-29 · D28 · a behind escalation marker clears on the head's OWN mergeStateStatus, never on head-oid equality"
mk_green; issue_fixture 456 status:review-stuck
comments_fixture 456 \
  "$(comment "$MERGER" "$(loop_ledger 456 "${GREEN_LOOP_ROWS[@]}")" 2026-01-03T00:00:00Z 822)" \
  "$(comment "$MERGER" "Escalation: behind at head $H."$'\n\n'"<!-- escalation:status:implementing:behind:$H -->" 2026-01-05T00:00:00Z 823)"
mergestate_fixture 123 CLEAN
run "MG-29a: the SAME head, mergeStateStatus now CLEAN, exits 0" 123
wrote "^gh issue edit 456 --add-label status:implementing --remove-label status:review-stuck" "MG-29a: the marker clears on the head's own state, with no head-oid change at all"
merged "MG-29a: and the merge proceeds"
mk_green; issue_fixture 456 status:review-stuck
comments_fixture 456 \
  "$(comment "$MERGER" "$(loop_ledger 456 "${GREEN_LOOP_ROWS[@]}")" 2026-01-03T00:00:00Z 824)" \
  "$(comment "$MERGER" "Escalation: behind at head $H."$'\n\n'"<!-- escalation:status:implementing:behind:$H -->" 2026-01-05T00:00:00Z 825)"
mergestate_fixture 123 BEHIND
run "MG-29b: mergeStateStatus still BEHIND exits 0" 123
has "still live" "MG-29b: the marker stays live while mergeStateStatus is still BEHIND"
no_writes "MG-29b"
mk_green; issue_fixture 456 status:review-stuck
comments_fixture 456 \
  "$(comment "$MERGER" "$(loop_ledger 456 "${GREEN_LOOP_ROWS[@]}")" 2026-01-03T00:00:00Z 826)" \
  "$(comment "$MERGER" "Escalation: behind at head $H."$'\n\n'"<!-- escalation:status:implementing:behind:$H -->" 2026-01-05T00:00:00Z 827)"
mergestate_fixture 123 UNKNOWN
run "MG-29c: mergeStateStatus UNKNOWN exits 0" 123
has "still live" "MG-29c: the marker stays live while mergeStateStatus is UNKNOWN"
no_writes "MG-29c"

banner "MG-30 · escalate.sh · S3 · an unresolvable merge-actor login refuses, nothing written"
mk_green
comments_fixture 456 "$(comment "$MERGER" "<!-- escalation:status:implementing:budget:$H -->" 2026-01-05T00:00:00Z 828)"
: > "$FX/user-unreadable"
run_fail "$ESCALATE" "MG-30: escalate refuses when the merge actor's login is unresolvable" 456 --reason budget --head "$H"
has "cannot resolve the merge actor's login via 'gh api user'" "MG-30: names the S3 reason"
no_writes "MG-30"
rm -f "$FX/user-unreadable"

echo
echo "merge_gate_test.sh: all scenarios passed"
