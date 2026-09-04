#!/usr/bin/env bash
# Tests for the placement adapters and the D4 preflight
# (#25, intent/25-execution-model/plan.md T4, T5, T6, T8).
#
#   bash scripts/ops/tests/placement_test.sh
#
# Hermetic. A stub `gh` first on PATH answers every read from a canned
# fixture; the adapters run inside a FIXTURE TREE whose
# scripts/auth/_github_app.py is a stub, so the D4 preflight is exercised
# against a canned /installation/repositories selection with no network,
# no private key and no token exchange. Any real launch is a test
# failure: `claude` and `agy` stubs record the attempt and exit non-zero.
#
# Three things are proved here:
#
#   D16  every adapter's launch step is the single work.sh line, there
#        is no second dispatch path and no inline prompt — greped off
#        the sources, so an adapter added later is covered without
#        anyone remembering to add a scenario;
#   D4   the preflight refuses BEFORE any model call when the
#        installation's repository selection excludes this repository,
#        and its read is paginated;
#   D3   the gh-actions adapter names the private key by NAME only, and
#        refuses by that name when the variable is unset.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FIXTURES="$WORK/fixtures"
WRITES="$WORK/writes.log"
LAUNCHES="$WORK/launches.log"
mkdir -p "$FIXTURES" "$WORK/bin"
: > "$WRITES"; : > "$LAUNCHES"

export GITHUB_REPO="test/repo"
export FIXTURES WRITES LAUNCHES
export PATH="$WORK/bin:$PATH"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }
banner() { printf '\n--- %s\n' "$*"; }

# --- the stubs ----------------------------------------------------------------
cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" != "api" ] || [ "$#" -ne 2 ]; then
  echo "gh $*" >> "$WRITES"
  echo "stub gh: refusing non-read call: $*" >&2
  exit 1
fi
file="$FIXTURES/${2//\//_}.json"
[ -f "$file" ] || { echo "stub gh: no fixture for $2" >&2; exit 1; }
cat "$file"
STUB
for harness in claude agy; do
  cat > "$WORK/bin/$harness" <<STUB
#!/usr/bin/env bash
echo "$harness \$*" >> "\$WRITES"
echo "stub $harness: a session was launched by a test that forbids it" >&2
exit 1
STUB
done
chmod +x "$WORK/bin/gh" "$WORK/bin/claude" "$WORK/bin/agy"

# issue <n> <state> <labels-csv> <title>
issue() {
  jq -n --argjson n "$1" --arg state "$2" --arg labels "$3" --arg title "$4" \
    '{number: $n, state: $state, title: $title, body: "",
      labels: ($labels | if . == "" then [] else split(",") end | map({name: .}))}' \
    > "$FIXTURES/repos_test_repo_issues_$1.json"
  echo '[]' > "$FIXTURES/repos_test_repo_issues_$1_comments.json"
}

# fixture_tree -> a temp REPO_ROOT the adapters can be run out of. The
# adapters resolve everything by absolute path from BASH_SOURCE, so a
# tree is the only way to stub what they call.
#
# Two stubs go in:
#   scripts/auth/_github_app.py   canned authority, canned key, and a
#                                 fake urlopen serving ONE repository per
#                                 page — so a preflight that read only
#                                 the first page would answer wrong, and
#                                 the pagination is proved rather than
#                                 asserted.
#   scripts/auth/mint_app_token.py stays REAL: it is the code under test.
fixture_tree() {
  local t
  t="$(mktemp -d "$WORK/tree.XXXX")"
  cp -r "$REPO/personas" "$REPO/config" "$REPO/scripts" "$REPO/.agents" "$t/"
  mkdir -p "$t/.claude" "$t/.github/workflows"
  cp -r "$REPO/.claude/agents" "$t/.claude/"
  cp "$REPO/.github/workflows/unattended.yml" "$t/.github/workflows/"
  ln -s "$REPO/intent" "$t/intent"
  cat > "$t/scripts/auth/_github_app.py" <<'PYSTUB'
"""Stub of _github_app.py for placement_test.sh.

Canned authority and key, and a fake urlopen that serves ONE repository
per page of /installation/repositories. The page size is 1 on purpose:
a preflight that read only the first page would answer "not installed
here" for a selection that does include this repository, which is the
misread already on #25's thread.

$STUB_REPOS is the installation's repository selection, comma-separated.
"""

import json
import os
import urllib.request


def get_repo_info():
    return ("evekhm", "agentic-sdlc")


def load_authority(persona, require_installation):
    return {
        "identity": "evekhm-%s-app[bot]" % persona,
        "token": "%s_APP_PRIVATE_KEY" % persona.upper(),
        "client_id": "stub-client-id",
        "installation_id": 1,
    }


def load_private_key(token_name, identity):
    return "stub-private-key"


def mint_jwt(authority, private_key):
    return "stub-jwt"


class _Response:
    def __init__(self, payload):
        self._payload = payload

    def read(self):
        return json.dumps(self._payload).encode()

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False


def _fake_urlopen(request, *args, **kwargs):
    url = request.full_url
    with open(os.environ["STUB_API_LOG"], "a") as log:
        log.write(url + "\n")
    if "access_tokens" in url:
        return _Response({"token": "stub-installation-token"})
    names = [n for n in os.environ.get("STUB_REPOS", "").split(",") if n]
    page = 1
    if "&page=" in url:
        page = int(url.split("&page=")[1].split("&")[0])
    chunk = names[page - 1:page]
    return _Response(
        {"total_count": len(names),
         "repositories": [{"full_name": n} for n in chunk]}
    )


urllib.request.urlopen = _fake_urlopen
PYSTUB
  printf '%s\n' "$t"
}

# ---------------------------------------------------------------------------
banner "D16 every adapter is the ONE work.sh line and nothing else"
# Greped off the sources, not off one adapter's output: an adapter added
# later is covered by this scenario without anyone remembering to.
shopt -s nullglob
adapters=( "$REPO"/scripts/placement/*/run.sh )
shopt -u nullglob
[ "${#adapters[@]}" -ge 2 ] \
  || fail "D16: expected at least the two v1 adapters, found ${#adapters[@]}"
pass "D16: ${#adapters[@]} adapters found under scripts/placement/"
for adapter in "${adapters[@]}"; do
  rel="${adapter#"$REPO"/}"
  [ -x "$adapter" ] || fail "D16: $rel is not executable"
  bash -n "$adapter" || fail "D16: $rel is not valid bash"
  n="$(grep -c 'scripts/ops/work\.sh' "$adapter")"
  [ "$n" = "1" ] \
    || fail "D16: $rel invokes work.sh $n times; one adapter, one dispatch"
  grep -q '^exec "\$REPO_ROOT/scripts/ops/work.sh" "\$NUMBER" --as "\$PERSONA"$' "$adapter" \
    || fail "D16: $rel's launch step is not the exact one-line contract"
  # No second dispatch path: nothing else in an adapter may start a
  # harness or a session.
  if grep -qE '\b(claude|agy|gemini)\b' "$adapter"; then
    fail "D16: $rel names a harness binary; adapters do not launch harnesses"
  fi
  # No inline prompt: an adapter that composed one could tell a session
  # which rung to work, which is the rule that closes argv (#36 D7).
  if grep -qiE 'Work issue|--agent |-p "' "$adapter"; then
    fail "D16: $rel composes a prompt"
  fi
  # No model, tier or cost literal (D8, D15).
  if grep -qE '\b(opus|sonnet|haiku|flash|pro-high|FRONTIER|REVIEW|IMPLEMENTATION)\b' "$adapter"; then
    fail "D16/D15: $rel names a model or a tier"
  fi
  pass "D16: $rel dispatches exactly once, through the one work.sh line"
done
grep -q 'directory name IS the value legal' "$REPO/scripts/placement/README.md" \
  || fail "D17: the registry README does not state the directory-name contract"
pass "D17: scripts/placement/README.md states the registry contract"

# ===========================================================================
T="$(fixture_tree)"
export STUB_API_LOG="$WORK/api.log"

banner "D4 the preflight refuses when the installation does not cover this repository"
: > "$STUB_API_LOG"
set +e
OUT="$(STUB_REPOS="evekhm/other,evekhm/another" \
  python3 "$T/scripts/auth/mint_app_token.py" odyssey --require-repo --quiet 2>"$WORK/err")"
rc=$?
set -e
[ "$rc" -ne 0 ] || fail "D4: an excluding selection exited 0"
pass "D4: an installation that excludes this repository exits non-zero (exit $rc)"
grep -qF "odyssey: the evekhm-odyssey-app installation does not cover evekhm/agentic-sdlc" \
  "$WORK/err" \
  || { cat "$WORK/err" >&2; fail "D4: the named error was not printed"; }
pass "D4: the error names the persona, the App and the repository"
[ -z "$OUT" ] || fail "D4: stdout was not empty — a token escaped a failed preflight"
pass "D4: stdout is empty; no token reached a shell variable"

banner "D4 the read is PAGINATED — a covering selection past page 1 still passes"
# The stub serves one repository per page. With the target second, a
# preflight that read only the first page would answer wrong; this is
# the exact misread corrected on #25's thread, made into a test.
: > "$STUB_API_LOG"
set +e
OUT="$(STUB_REPOS="evekhm/other,evekhm/agentic-sdlc" \
  python3 "$T/scripts/auth/mint_app_token.py" odyssey --require-repo --quiet 2>"$WORK/err")"
rc=$?
set -e
[ "$rc" -eq 0 ] || { cat "$WORK/err" >&2; fail "D4: a covering selection exited $rc"; }
pass "D4: a covering selection exits 0"
[ -z "$OUT" ] || fail "D4: --quiet printed something"
pass "D4: --quiet performs the check and prints nothing"
pages="$(grep -c 'installation/repositories' "$STUB_API_LOG")"
[ "$pages" -ge 2 ] \
  || { cat "$STUB_API_LOG" >&2; fail "D4: only $pages page(s) were read; the check is not paginated"; }
pass "D4: the selection was read across $pages pages"
# Without --require-repo the token still comes out on stdout: the
# preflight is an added flag, not a change to what minting does.
OUT="$(STUB_REPOS="" python3 "$T/scripts/auth/mint_app_token.py" odyssey)"
[ "$OUT" = "stub-installation-token" ] \
  || fail "D4: the default minting behaviour changed"
pass "D4: without --require-repo the script still prints the token and nothing else"

banner "T4/D16 vm-local: DRY_RUN=1 reads, reports and writes nothing"
issue 25 open "status:implementing" "Execution model for unattended personas"
: > "$WRITES"
set +e
OUT="$(STUB_REPOS="evekhm/agentic-sdlc" DRY_RUN=1 \
  "$T/scripts/placement/vm-local/run.sh" 25 --as odyssey 2>&1)"
rc=$?
set -e
[ "$rc" -eq 0 ] || { printf '%s\n' "$OUT" >&2; fail "T4: the vm-local dry run exited $rc"; }
pass "T4: DRY_RUN=1 through the vm-local adapter exits 0"
grep -qF "vm-local: #25 as odyssey (max_cost_usd" <<<"$OUT" \
  || { printf '%s\n' "$OUT" >&2; fail "T4: the adapter's report line is missing"; }
pass "T4: the adapter prints one report line naming the placement and the cap"
grep -qF "==> #25" <<<"$OUT" \
  || { printf '%s\n' "$OUT" >&2; fail "T4: work.sh's own report did not follow"; }
pass "D16: work.sh's dry-run report follows — DRY_RUN=1 passed through unchanged"
grep -qF "nothing was launched, nothing was written, and no token was minted" <<<"$OUT" \
  || fail "D16: the dry run did not say it wrote nothing"
pass "D16: the dry run reports zero writes and zero mints"
[ ! -s "$WRITES" ] || { cat "$WRITES" >&2; fail "T4: something was written or launched"; }
pass "T4: no GitHub write and no launch"

banner "T4 the adapter takes a number and --as, and nothing else"
for bad in "--stage implement" "--prompt hello"; do
  set +e
  # shellcheck disable=SC2086
  OUT="$("$T/scripts/placement/vm-local/run.sh" 25 --as odyssey $bad 2>&1)"
  rc=$?
  set -e
  [ "$rc" -eq 1 ] || fail "D16: '$bad' did not exit 1 (got $rc)"
  grep -qF "unknown flag" <<<"$OUT" || fail "D16: '$bad' was not refused by name"
done
pass "D16: a flag naming a stage or a prompt is refused outright"

banner "T5/D3 gh-actions refuses BY NAME when the key variable is unset"
: > "$WRITES"
set +e
OUT="$(env -u ARGUS_APP_PRIVATE_KEY STUB_REPOS="evekhm/agentic-sdlc" DRY_RUN=1 \
  "$T/scripts/placement/gh-actions/run.sh" 25 --as argus 2>&1)"
rc=$?
set -e
[ "$rc" -eq 1 ] || { printf '%s\n' "$OUT" >&2; fail "T5: an unset key exited $rc, not 1"; }
pass "T5: an unset private-key variable exits 1"
grep -qF "gh-actions: ARGUS_APP_PRIVATE_KEY is not set in this environment" <<<"$OUT" \
  || { printf '%s\n' "$OUT" >&2; fail "D3: the refusal does not name the variable"; }
pass "D3: the refusal names the variable, read out of personas/argus.yaml"
grep -qF "==> #25" <<<"$OUT" && fail "T5: work.sh ran behind a missing credential"
pass "T5: nothing was dispatched"
[ ! -s "$WRITES" ] || { cat "$WRITES" >&2; fail "T5: something was written or launched"; }

banner "T5/D16 gh-actions with the key set: DRY_RUN=1 reports and writes nothing"
: > "$WRITES"
issue 30 open "status:in-review" "A pull request to review"
set +e
OUT="$(ARGUS_APP_PRIVATE_KEY="stub-key-value" STUB_REPOS="evekhm/agentic-sdlc" DRY_RUN=1 \
  "$T/scripts/placement/gh-actions/run.sh" 30 --as argus 2>&1)"
rc=$?
set -e
[ "$rc" -eq 0 ] || { printf '%s\n' "$OUT" >&2; fail "T5: the gh-actions dry run exited $rc"; }
pass "T5: DRY_RUN=1 through the gh-actions adapter exits 0"
grep -qF "gh-actions: #30 as argus (max_cost_usd" <<<"$OUT" \
  || { printf '%s\n' "$OUT" >&2; fail "T5: the adapter's report line is missing"; }
pass "T5: the adapter prints its report line"
grep -qF "==> #30" <<<"$OUT" || fail "D16: work.sh's report did not follow"
pass "D16: DRY_RUN=1 passed through to work.sh unchanged"
grep -qF "stub-key-value" <<<"$OUT" && fail "D3: the private key VALUE was printed"
pass "D3: the key value appears nowhere in the output"
[ ! -s "$WRITES" ] || { cat "$WRITES" >&2; fail "T5: something was written or launched"; }
pass "T5: no GitHub write and no launch"

banner "T4/T5 a failing preflight stops the adapter before work.sh"
: > "$WRITES"
set +e
OUT="$(STUB_REPOS="evekhm/somewhere-else" DRY_RUN=1 \
  "$T/scripts/placement/vm-local/run.sh" 25 --as odyssey 2>&1)"
rc=$?
set -e
[ "$rc" -eq 1 ] || { printf '%s\n' "$OUT" >&2; fail "D4: a failed preflight exited $rc, not 1"; }
pass "D4: a failed preflight exits 1 through the adapter"
grep -qF "preflight failed for odyssey" <<<"$OUT" || fail "D4: the adapter did not say why"
grep -qF "==> #25" <<<"$OUT" && fail "D4: work.sh ran after a failed preflight"
pass "D4: nothing was dispatched behind a failed preflight"
[ ! -s "$WRITES" ] || { cat "$WRITES" >&2; fail "D4: something was written"; }

banner "D18 a placement move is ONE line and the duty still runs"
# Acceptance 8's first half, as a test rather than a one-off: flip
# argus to vm-local in the fixture's config and nothing else, and the
# dispatch still resolves.
sed -i 's/^    placement: gh-actions$/    placement: vm-local/' "$T/config/execution.yaml"
changed="$(diff "$REPO/config/execution.yaml" "$T/config/execution.yaml" \
  | grep -c '^[<>]' || true)"
[ "$changed" = "4" ] \
  || { diff "$REPO/config/execution.yaml" "$T/config/execution.yaml" >&2
       fail "D18: moving BOTH reviewers changed $changed lines, not 4 (2 per persona)"; }
pass "D18: moving both reviewers is two one-line edits, in config/execution.yaml alone"
python3 "$T/scripts/ops/execution.py" --check >/dev/null \
  || fail "D18: the moved config does not pass --check"
pass "D18: the moved config passes the gate"
: > "$WRITES"
set +e
OUT="$(STUB_REPOS="evekhm/agentic-sdlc" DRY_RUN=1 \
  "$T/scripts/placement/vm-local/run.sh" 30 --as argus 2>&1)"
rc=$?
set -e
[ "$rc" -eq 0 ] || { printf '%s\n' "$OUT" >&2; fail "D18: the moved duty does not run (exit $rc)"; }
grep -qF "vm-local: #30 as argus" <<<"$OUT" || fail "D18: the new placement did not take"
pass "D18: argus dispatches through vm-local with no edit outside config/execution.yaml"

echo
echo "placement_test.sh: all scenarios passed"
