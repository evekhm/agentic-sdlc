#!/usr/bin/env bash
# Copyright 2026 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Tests for scripts/ops/session_spend.sh (R1-7 on PR #106). Synthetic
# transcripts with round token counts are written to a temp tree, so every
# expected USD figure is exact and hand-checkable. No tokens, no network.
#
#   bash scripts/ops/tests/session_spend_test.sh
#
# Each scenario pins a defect that shipped silently — the roll-up printed a
# plausible table either way, which is why these need a test and not a
# reviewer's eye. Exit 0 with a PASS line per scenario, non-zero on the first
# failure.

set -euo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/session_spend.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

# has <output> <literal> <name> — assert the roll-up contains a literal string.
has() {
  if printf '%s\n' "$1" | grep -qF -- "$2"; then pass "$3"
  else printf '%s\n' "$1" >&2; fail "$3 (expected to find: $2)"; fi
}
# ttl_row <output> <session> <column> — one field of one session's row in the
# --ttl-compare section. Scoped to that section on purpose: several tables
# print a row per session, and matching on the session name alone picks up the
# wrong one.
#   columns: 2=actual 3=at-1h 4=change 5=converted 6=taxed
ttl_row() {
  printf '%s\n' "$1" | awk -v s="$2" -v c="$3" \
    '/Repriced under the 1-hour TTL/ {f=1; next} f && $1==s {print $c}'
}
# model_usd <output> <model-id> — the USD cell of one row of the "Per model"
# table. Scoped to that section for the same reason as ttl_row, and asserted on
# instead of a bare `has` on the formatted number: several models in the rate
# fixtures below total the same USD, so a whole-output substring match would
# pass on a neighbour's row.
model_usd() {
  printf '%s\n' "$1" | awk -v m="$2" \
    '/^== Per model ==/ {f=1; next} /^== Main vs/ {f=0} f && $1==m {print $3}'
}
# is_usd <output> <model-id> <expected> <name>
is_usd() {
  local got; got=$(model_usd "$1" "$2")
  if [ "$got" = "$3" ]; then pass "$4"
  else printf '%s\n' "$1" >&2; fail "$4 (model $2: expected $3, got '${got:-<no row>}')"; fi
}

# msg <file> <ts> <model> <input> <read> <cw5m> <cw1h> <output>
# One assistant message with the modern usage schema.
msg() {
  local f=$1 ts=$2 model=$3 inp=$4 cr=$5 c5=$6 c1=$7 out=$8
  jq -cn --arg ts "$ts" --arg m "$model" \
    --argjson i "$inp" --argjson r "$cr" --argjson a "$c5" --argjson b "$c1" --argjson o "$out" \
    '{type:"assistant", timestamp:$ts, message:{model:$m, usage:{
        input_tokens:$i, cache_read_input_tokens:$r,
        cache_creation:{ephemeral_5m_input_tokens:$a, ephemeral_1h_input_tokens:$b},
        cache_creation_input_tokens:($a+$b), output_tokens:$o}}}' >> "$f"
}

# legacy_msg <file> <ts> <model> <cw_total> — the pre-breakdown schema: a
# cache_creation_input_tokens total with no 5m/1h split. Still live in older
# transcripts, so the fallback that prices it as 5m has to keep working.
legacy_msg() {
  local f=$1 ts=$2 model=$3 ctot=$4
  jq -cn --arg ts "$ts" --arg m "$model" --argjson c "$ctot" \
    '{type:"assistant", timestamp:$ts, message:{model:$m, usage:{
        input_tokens:0, cache_read_input_tokens:0,
        cache_creation_input_tokens:$c, output_tokens:0}}}' >> "$f"
}

# ---------------------------------------------------------------------------
# 1. R1-1/AT-1 — a trailing slash on the target must not change the answer.
#    `find "$dir/"` prints "$dir//sub/file", so stripping the prefix "$dir/"
#    left "/sub/file", whose first path component is empty: every file, main
#    sessions included, classified as a subagent. Totals stayed correct, which
#    is exactly why it survived.
# ---------------------------------------------------------------------------
T1="$WORK/proj"
mkdir -p "$T1/abc-123"
msg "$T1/main-session.jsonl" 2026-08-20T10:00:00.000Z claude-opus-5 1000000 0 0 0 0
msg "$T1/abc-123/sub-one.jsonl" 2026-08-20T10:01:00.000Z claude-opus-5 1000000 0 0 0 0

no_slash=$("$SCRIPT" "$T1" --out "$WORK/o1")
with_slash=$("$SCRIPT" "$T1/" --out "$WORK/o2")
has "$no_slash" "main" "R1-1 baseline: a top-level transcript is classified main"
if [ "$no_slash" = "$with_slash" ]; then
  pass "R1-1: a trailing slash on the target produces an identical roll-up"
else
  diff <(printf '%s\n' "$no_slash") <(printf '%s\n' "$with_slash") >&2 || true
  fail "R1-1: trailing slash changed the roll-up"
fi
# And the classification itself, not just that the two runs agree.
main_line=$(printf '%s\n' "$no_slash" | grep -A3 'Main vs subagent' | grep '^main ')
sub_line=$(printf '%s\n' "$no_slash" | grep -A3 'Main vs subagent' | grep '^sub ')
has "$main_line" "1000000" "R1-1: the top-level file's tokens land under main"
has "$sub_line" "1000000" "R1-1: the subdirectory file's tokens land under sub"

# Aimed one level too high, the tool says so instead of mislabelling silently.
parent_err=$("$SCRIPT" "$WORK" --out "$WORK/o3" 2>&1 >/dev/null || true)
has "$parent_err" "no top-level" "R1-1: a parent-of-projects target warns about classification"

# ---------------------------------------------------------------------------
# 2. R1-2 — the $HOME refusal was a literal compare, so any non-canonical
#    spelling of $HOME walked past it and scanned the whole home directory.
# ---------------------------------------------------------------------------
for spelling in "$HOME" "$HOME/" "$HOME/."; do
  out=$("$SCRIPT" "$spelling" --out "$WORK/oh" 2>&1 || true)
  has "$out" "refusing to scan" "R1-2: '$spelling' is refused as \$HOME"
done

# ---------------------------------------------------------------------------
# 3. R1-4 — pre-4 model IDs spell the version before the family
#    (claude-3-5-haiku-*, claude-3-opus@*). The old patterns missed them and
#    they priced at a modern tier: 3.5-Haiku at $1/$5 instead of $0.80/$4,
#    3-Opus at $5/$25 instead of $15/$75. Silent, because a later tier always
#    matched and the table still printed a number.
#    1 MTok input + 1 MTok output, so USD == the per-MTok rates, added.
# ---------------------------------------------------------------------------
T3="$WORK/rates"; mkdir -p "$T3"
msg "$T3/h35.jsonl" 2026-08-20T10:00:00.000Z claude-3-5-haiku-20241022 1000000 0 0 0 1000000
msg "$T3/o3.jsonl"  2026-08-20T10:00:00.000Z claude-3-opus@20240229    1000000 0 0 0 1000000
msg "$T3/h3.jsonl"  2026-08-20T10:00:00.000Z claude-3-haiku@20240307   1000000 0 0 0 1000000
msg "$T3/h45.jsonl" 2026-08-20T10:00:00.000Z claude-haiku-4-5-20251001 1000000 0 0 0 1000000
msg "$T3/s35.jsonl" 2026-08-20T10:00:00.000Z claude-3-5-sonnet-20241022 1000000 0 0 0 1000000
rates=$("$SCRIPT" "$T3" --out "$WORK/o4")
has "$rates" "claude-3-5-haiku-20241022"  "R1-4 fixture: 3.5-Haiku appears in the per-model table"
# 0.80 + 4 = 4.80
has "$rates" "$(printf '%14d %12.2f' 2000000 4.80)" "R1-4: 3.5-Haiku prices at 0.80/4.00, not the 4.5-Haiku tier"
# 15 + 75 = 90
has "$rates" "$(printf '%14d %12.2f' 2000000 90.00)" "R1-4: 3-Opus prices at 15/75, not the Opus 5 tier"
# 0.25 + 1.25 = 1.50
has "$rates" "$(printf '%14d %12.2f' 2000000 1.50)" "R1-4: 3-Haiku prices at 0.25/1.25"
# 1 + 5 = 6 — the current Haiku tier must NOT have moved.
has "$rates" "$(printf '%14d %12.2f' 2000000 6.00)" "R1-4: 4.5-Haiku still prices at 1/5"
# 3 + 15 = 18 — 3.5-Sonnet shares the Sonnet tier; the /sonnet-5/ pattern must
# not catch the "3-5-sonnet" spelling.
has "$rates" "$(printf '%14d %12.2f' 2000000 18.00)" "R1-4: 3.5-Sonnet still prices at 3/15"

# ---------------------------------------------------------------------------
# 3b. R5-1/AT-6 — the same class as R1-4, one tier down. R1-4 added a pattern
#    per missed spelling but kept the bare-family fallback underneath, so the
#    next spelling it missed was mispriced the same silent way:
#    claude-opus-4-20250514 and claude-opus-4-0 are Opus 4 ($15/$75) and fell
#    through /opus/ to the Opus 5 tier ($5/$25), a third of the real rate.
#    The fix prices family+version explicitly and leaves everything else
#    unpriced-and-warned, so this scenario asserts both directions: the tiers
#    that must be right, and that an ID this table does not know reaches the
#    warning instead of a neighbouring rate.
#    1 MTok input + 1 MTok output throughout, so USD == the rates, added.
# ---------------------------------------------------------------------------
T3b="$WORK/rates2"; mkdir -p "$T3b"
for m in claude-opus-4-20250514 claude-opus-4-0 claude-opus-4-1-20250805 \
         claude-opus-4-5-20251101 claude-opus-4-8 claude-opus-5 \
         claude-sonnet-4-5-20250929 claude-sonnet-5 claude-fable-5 opus; do
  msg "$T3b/$m.jsonl" 2026-08-20T10:00:00.000Z "$m" 1000000 0 0 0 1000000
done
r2=$("$SCRIPT" "$T3b" --out "$WORK/o4b")
# Opus 4 and 4.1: 15 + 75 = 90. The two undated/dated Opus 4 spellings are the
# regression R5-1 and AT-6 named; 4.1 was already correct and must stay so.
is_usd "$r2" claude-opus-4-20250514 90.00 "R5-1/AT-6: claude-opus-4-20250514 prices at 15/75, not the Opus 5 tier"
is_usd "$r2" claude-opus-4-0        90.00 "R5-1/AT-6: the claude-opus-4-0 alias prices at 15/75"
is_usd "$r2" claude-opus-4-1-20250805 90.00 "R5-1: Opus 4.1 still prices at 15/75"
# Opus 4.5+ and Opus 5: 5 + 25 = 30. Fixing Opus 4 must not drag these up.
is_usd "$r2" claude-opus-4-5-20251101 30.00 "R5-1: Opus 4.5 still prices at 5/25"
is_usd "$r2" claude-opus-4-8           30.00 "R5-1: Opus 4.8 still prices at 5/25"
is_usd "$r2" claude-opus-5             30.00 "R5-1: Opus 5 still prices at 5/25"
# Sonnet 4.5 is 3/15 and Sonnet 5 is 2/10; the version split must survive
# losing the /sonnet/ fallback that used to serve 4.5.
is_usd "$r2" claude-sonnet-4-5-20250929 18.00 "R5-1: Sonnet 4.5 still prices at 3/15"
is_usd "$r2" claude-sonnet-5            12.00 "R5-1: Sonnet 5 still prices at 2/10"
# 10 + 50 = 60.
is_usd "$r2" claude-fable-5             60.00 "R5-1: Fable 5 still prices at 10/50"
# AT-6, the point of the class fix: an ID with no version in it — the bare
# alias, whose tier changes underneath you as new models ship — is not priced
# at whatever the family's newest tier happens to be. It is reported.
is_usd "$r2" opus 0.00 "AT-6: a bare family alias is not silently priced at a family tier"
has "$r2" "no rate for model opus — 2000000 tokens" "AT-6: the bare alias is reported as unpriced"
# And a version this table has never seen, which is the same failure in the
# future tense: claude-opus-9 must warn rather than inherit the Opus 5 rate.
T3c="$WORK/rates3"; mkdir -p "$T3c"
msg "$T3c/future.jsonl" 2026-08-20T10:00:00.000Z claude-opus-9 1000000 0 0 0 1000000
r3=$("$SCRIPT" "$T3c" --out "$WORK/o4c")
is_usd "$r3" claude-opus-9 0.00 "R5-1: an unknown Opus version is unpriced, not given a neighbouring tier"
has "$r3" "no rate for model claude-opus-9 — 2000000 tokens" "R5-1: the unknown version is reported"

# ---------------------------------------------------------------------------
# 4. Legacy payloads: a cache-write total with no 5m/1h breakdown is priced as
#    5m and the roll-up says it did. Guards the null-fallback path.
# ---------------------------------------------------------------------------
T4="$WORK/legacy"; mkdir -p "$T4"
legacy_msg "$T4/old.jsonl" 2026-08-20T10:00:00.000Z claude-opus-5 1000000
legacy=$("$SCRIPT" "$T4" --out "$WORK/o5")
has "$legacy" "1000000 cache-write tokens lacked a 5m/1h breakdown" "assumed_5m: the fallback is applied and disclosed"
has "$legacy" "$(printf '%-18s %14d %12.2f' 'cache write 5m' 1000000 6.25)" "assumed_5m: priced at the 5m write rate (1.25x base)"

# ---------------------------------------------------------------------------
# 5. R1-8 — the unpriced warning printed one run-wide counter against each
#    unknown model, so two unknowns each claimed the other's tokens too.
# ---------------------------------------------------------------------------
T5="$WORK/unknown"; mkdir -p "$T5"
msg "$T5/u1.jsonl" 2026-08-20T10:00:00.000Z some-future-model-a 1000 0 0 0 0
msg "$T5/u2.jsonl" 2026-08-20T10:00:00.000Z some-future-model-b 7000 0 0 0 0
unk=$("$SCRIPT" "$T5" --out "$WORK/o6")
has "$unk" "no rate for model some-future-model-a — 1000 tokens" "R1-8: each unknown model reports its own token count"
has "$unk" "no rate for model some-future-model-b — 7000 tokens" "R1-8: the second unknown model is not given the first's total"
has "$unk" "* unpriced" "R1-8: unpriced rows are marked in the per-model table"

# ---------------------------------------------------------------------------
# 6. R3-2 — --ttl-compare classified turns by session+kind, which merged every
#    subagent of a session into one pseudo-stream. Two subagents that each
#    cold-start 30 minutes apart then looked like one conversation with a
#    30-minute gap, and the second one's cold start was counted as a saving the
#    1-hour TTL could never have delivered. Keyed per transcript file, a first
#    turn has no predecessor and converts nothing.
# ---------------------------------------------------------------------------
T6="$WORK/streams"; mkdir -p "$T6/sess-1"
msg "$T6/parent.jsonl"     2026-08-20T09:00:00.000Z claude-opus-5 0 0 100000 0 0
msg "$T6/sess-1/a.jsonl"   2026-08-20T10:00:00.000Z claude-opus-5 0 0 100000 0 0
msg "$T6/sess-1/b.jsonl"   2026-08-20T10:30:00.000Z claude-opus-5 0 0 100000 0 0
streams=$("$SCRIPT" "$T6" --ttl-compare --out "$WORK/o7")
conv_total=$(( $(ttl_row "$streams" sess-1 5) + $(ttl_row "$streams" parent 5) ))
if [ "$conv_total" -eq 0 ]; then
  pass "R3-2: a subagent's cold start is not counted as a TTL conversion"
else
  printf '%s\n' "$streams" >&2
  fail "R3-2: $conv_total turn(s) counted as converted; each is a first turn of its own stream"
fi

# A real gap inside one stream still converts, or the fix would have broken the
# feature rather than corrected it.
T6b="$WORK/streams2"; mkdir -p "$T6b"
msg "$T6b/one.jsonl" 2026-08-20T10:00:00.000Z claude-opus-5 0 0 100000 0 0
msg "$T6b/one.jsonl" 2026-08-20T10:30:00.000Z claude-opus-5 0 0 100000 0 0
gap=$("$SCRIPT" "$T6b" --ttl-compare --out "$WORK/o8")
conv_one=$(ttl_row "$gap" one 5)
[ "$conv_one" = "1" ] || { printf '%s\n' "$gap" >&2; fail "R3-2: a 30-min gap within one stream should convert (got '$conv_one')"; }
pass "R3-2: a 30-minute gap within one stream still converts"

# ---------------------------------------------------------------------------
# 7. R3-1 — the "actual" column charged every cache write at the 5-minute rate,
#    including writes that really ran on the 1-hour TTL. That understated
#    actual spend and inflated the reported saving. 1 MTok of 1h writes on
#    Opus 5 is 1 * 10 = $10.00 actual, not 1 * 6.25.
# ---------------------------------------------------------------------------
T7="$WORK/ttl1h"; mkdir -p "$T7"
msg "$T7/long.jsonl" 2026-08-20T10:00:00.000Z claude-opus-5 0 0 0 1000000 0
ttl=$("$SCRIPT" "$T7" --ttl-compare --out "$WORK/o9")
actual=$(ttl_row "$ttl" long 2)
[ "$actual" = "10.00" ] || { printf '%s\n' "$ttl" >&2; fail "R3-1: 1h writes must price at 2x base in the actual column (got '$actual')"; }
pass "R3-1: 1-hour cache writes price at the 1-hour rate in the actual column"
has "$ttl" "ALREADY used the 1-hour TTL" "R3-1: a window already on 1h is flagged, not silently repriced onto itself"

# ---------------------------------------------------------------------------
# 8. --check reports both axes; neither is a verdict alone.
# ---------------------------------------------------------------------------
chk=$("$SCRIPT" "$T1" --check --out "$WORK/o10")
has "$chk" "cache hit rate" "--check: the price axis is reported"
has "$chk" "tokens/message" "--check: the volume axis is reported"

# ---------------------------------------------------------------------------
# 9. Argument handling: a bad date and an unknown flag both fail closed.
# ---------------------------------------------------------------------------
bad_date=$("$SCRIPT" "$T1" --since 2026-8-1 --out "$WORK/o11" 2>&1 || true)
has "$bad_date" "bad date" "args: a malformed --since is rejected"
bad_flag=$("$SCRIPT" "$T1" --nope --out "$WORK/o12" 2>&1 || true)
has "$bad_flag" "unknown argument" "args: an unknown flag is rejected"
no_match=$("$SCRIPT" "$T1" --since 2030-01-01 --out "$WORK/o13" 2>&1 || true)
has "$no_match" "no assistant messages matched" "args: an empty window is reported, not printed as zero spend"

echo
echo "session_spend_test.sh: all scenarios passed"
