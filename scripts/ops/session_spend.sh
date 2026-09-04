#!/usr/bin/env bash
# session_spend.sh — aggregate Claude Code session transcripts into token and USD roll-ups.
#
# Reads every *.jsonl under a transcript directory (top-level files are main
# sessions, files in subdirectories are subagents of the session named by the
# first path component), reduces each assistant message to one TSV row, and
# emits token + USD roll-ups: overall, per day, per session, per model, per
# kind (main vs subagent). No transcript content beyond the usage numbers is
# read or emitted.
#
# USD figures are list-rate estimates. Rates: Anthropic model pricing table
# (platform.claude.com/docs/en/about-claude/pricing, fetched 2026-08-23),
# per MTok: base input / 5m cache write / 1h cache write / cache read / output.
# Vertex AI bills separately (cloud.google.com/vertex-ai/generative-ai/pricing);
# the GCP bill is authoritative — these numbers rank spend, they don't invoice it.
# A model whose family+version the table does not list is left UNPRICED and
# reported by name with its token count, rather than being charged at a
# neighbouring tier (see rate_tier); its tokens are excluded from the USD
# columns, so a warning in the output means the totals are a lower bound.
#
# Usage:
#   session_spend.sh <transcript-dir-or-file> [--since YYYY-MM-DD] [--until YYYY-MM-DD]
#                    [--out DIR] [--check] [--ttl-compare]
#
# --check appends a health verdict on the two independent axes: cache hit rate
# (the price paid per re-sent token) and tokens per message (how many tokens
# are re-sent). Either one alone hides the other; see docs/COST_LESSONS.md,
# "Check your own session: two numbers, never one".
#
# Requires jq and gawk (the summary uses asorti/mktime, which mawk lacks).
#
# --ttl-compare reprices the same transcripts under the other cache TTL, per
# main session. Each turn is classified by the wall-clock gap since the
# previous turn of the same transcript stream — one file, one context, so a
# subagent's first turn is a cold start and not a gap in its parent's
# conversation: a gap in (5min, 1h] is a cold turn under the
# 5-minute TTL that a 1-hour entry would have kept warm, so its cache-write
# tokens are repriced as a cache read; every other turn keeps its write and is
# repriced at the 1-hour write rate (2x base, versus 1.25x for 5m). Reads,
# fresh input and output are unchanged. This over-states the saving slightly,
# since a converted turn would still write its own small delta. Enable the
# long TTL with ENABLE_PROMPT_CACHING_1H=1; force the short one back with
# FORCE_PROMPT_CACHING_5M=1. See docs/COST_LESSONS.md, "The 1-hour TTL".
#
# The transcript location is a required argument; there is deliberately no
# default (and $HOME is rejected) so the script cannot wander into unrelated
# session trees by accident.

set -euo pipefail

err() { echo "session_spend: $*" >&2; exit 1; }

# R1-3: the summary awk uses asorti(), sort-by-"@val_num_desc" and mktime(),
# all gawk extensions. mawk is the default awk on Debian and Ubuntu, and it
# aborts on them mid-pipeline — leaving a complete messages.tsv next to an
# empty summary, which reads as "no spend" rather than as a failure. Resolve
# gawk by name and fail here with something actionable instead.
if ! AWK=$(command -v gawk); then
  err "gawk is required (this script uses asorti/mktime, which mawk does not implement); install it with: sudo apt-get install gawk"
fi

[ $# -ge 1 ] || err "usage: session_spend.sh <transcript-dir-or-file> [--since YYYY-MM-DD] [--until YYYY-MM-DD] [--out DIR] [--check] [--ttl-compare]"
TARGET=$1; shift
SINCE="" UNTIL="" OUT="" CHECK=0 TTLC=0
while [ $# -gt 0 ]; do
  case $1 in
    --since) SINCE=${2:?--since needs a date}; shift 2 ;;
    --until) UNTIL=${2:?--until needs a date}; shift 2 ;;
    --out)   OUT=${2:?--out needs a directory}; shift 2 ;;
    --check) CHECK=1; shift ;;
    --ttl-compare) TTLC=1; shift ;;
    *) err "unknown argument: $1" ;;
  esac
done

[ -e "$TARGET" ] || err "no such file or directory: $TARGET"
# R1-1/AT-1/R1-2: resolve TARGET once, before anything compares or strips it.
# Two defects share this root. `find` prints paths built from the argument as
# given, so a trailing slash makes the prefix strip below look for "<dir>//",
# which never matches — every file then classifies as a subagent of the tree
# root, silently, since the token and USD totals stay correct. And the $HOME
# refusal was a literal string compare, so "$HOME/", "$HOME/." or
# "$HOME/foo/.." walked straight past it. Canonicalizing both sides closes
# both: it is the repo's "every gate fails fast" class, a gate that one
# trailing character disabled.
if [ -d "$TARGET" ]; then
  TARGET=$(cd -- "$TARGET" && pwd -P) || err "cannot resolve directory: $TARGET"
else
  _dir=$(cd -- "$(dirname -- "$TARGET")" && pwd -P) || err "cannot resolve: $TARGET"
  TARGET="$_dir/$(basename -- "$TARGET")"
fi
HOME_CANON=$(cd -- "$HOME" && pwd -P) || err "cannot resolve \$HOME"
[ "$TARGET" != "$HOME_CANON" ] || err "refusing to scan \$HOME; point at a specific transcript directory"
for d in "$SINCE" "$UNTIL"; do
  [ -z "$d" ] || echo "$d" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' || err "bad date: $d (want YYYY-MM-DD)"
done

if [ -n "$OUT" ]; then
  mkdir -p "$OUT"
else
  OUT=$(mktemp -d)
fi
TSV="$OUT/messages.tsv"
SUMMARY="$OUT/summary.txt"

# One row per assistant message:
# ts date session kind model input cache_read cw_5m cw_1h cw_total output stream
#
# `stream` is the transcript file the row came from. A session and a stream are
# not the same thing: one main session can spawn a dozen subagents, and each of
# those is its own context with its own cache lifecycle. --ttl-compare needs the
# stream, because a gap is only meaningful between consecutive turns of one
# context (R3-2). Everything else aggregates by session.
emit_file() {
  local f=$1 session=$2 kind=$3 stream=$4
  jq -r --arg s "$session" --arg k "$kind" --arg st "$stream" '
    select(.type=="assistant" and .message.usage != null and .message.model != "<synthetic>")
    | .message.usage as $u
    | [ .timestamp, (.timestamp[0:10]), $s, $k, (.message.model // "unknown"),
        ($u.input_tokens // 0), ($u.cache_read_input_tokens // 0),
        ($u.cache_creation.ephemeral_5m_input_tokens // 0),
        ($u.cache_creation.ephemeral_1h_input_tokens // 0),
        ($u.cache_creation_input_tokens // 0),
        ($u.output_tokens // 0), $st ] | @tsv' "$f"
}

: > "$TSV"
if [ -f "$TARGET" ]; then
  base=$(basename "$TARGET" .jsonl)
  emit_file "$TARGET" "$base" main "$base" >> "$TSV"
else
  found=0 n_main=0 n_sub=0
  while IFS= read -r f; do
    found=1
    rel=${f#"$TARGET"/}
    top=${rel%%/*}
    if [ "$rel" = "$top" ]; then
      n_main=$((n_main + 1))
      emit_file "$f" "${top%.jsonl}" main "$rel" >> "$TSV"
    else
      n_sub=$((n_sub + 1))
      emit_file "$f" "$top" sub "$rel" >> "$TSV"
    fi
  done < <(find "$TARGET" -name '*.jsonl' -type f | sort)
  [ "$found" -eq 1 ] || err "no *.jsonl files under $TARGET"
  # The main/sub split is positional: a file at the top level is a main
  # session, anything deeper is a subagent of the directory naming it. Aimed
  # one level too high (at ~/.claude/projects rather than at one project's
  # directory) every file is "deeper", so the whole tree reports as subagents
  # of nothing. Totals stay right, the attribution does not — say so rather
  # than print a confidently mislabelled table (R1-1).
  if [ "$n_main" -eq 0 ] && [ "$n_sub" -gt 0 ]; then
    echo "session_spend: WARNING: no top-level *.jsonl under $TARGET — every file was classified as a subagent." >&2
    echo "session_spend:          If this is a parent of project directories, point at one project directory instead." >&2
  fi
fi

# Sorted by stream then timestamp: --ttl-compare's prev[] must walk one
# context's turns in order, and only the stream identifies a context (R3-2).
sort -t$'\t' -k12,12 -k1,1 "$TSV" | "$AWK" -F'\t' -v since="$SINCE" -v until="$UNTIL" -v check="$CHECK" -v ttlc="$TTLC" '
function epoch(t,   a, d, tm) {
  split(substr(t, 1, 19), a, "T"); split(a[1], d, "-"); split(a[2], tm, ":")
  return mktime(d[1]" "d[2]" "d[3]" "tm[1]" "tm[2]" "int(tm[3]))
}
# R1-4, then R5-1/AT-6: the bare-family fallback was the defect, not any one
# missing pattern. Model IDs spell their version two ways — the 3.x families
# put it BEFORE the family name (claude-3-5-haiku-20241022,
# claude-3-opus@20240229) and 4.x flipped it (claude-haiku-4-5-20251001) — and
# each model ships under several spellings (the Vertex "@" separator, the
# Bedrock "anthropic.<id>-v1:0" wrapper, the undated alias). A chain that ended
# in `if (m ~ /opus/)` therefore priced every spelling its version branches
# missed at whichever tier happened to sit last: claude-3-opus at $5/$25
# instead of $15/$75 (R1-4), then claude-opus-4-20250514 and claude-opus-4-0
# the same way (R5-1/AT-6). Both were silent, because a rate was always found.
#
# So: normalise the ID to family + version once, price only the versions this
# table actually knows, and return "" for everything else — including a bare
# alias ("opus", "sonnet"), whose tier changes underneath you as new models
# ship. "" reaches the per-model unpriced warning in usd(), which is the loud
# failure the fallback was hiding. Rates are the ones dated in the header of
# this file; adding a model means adding its version here, deliberately.
function model_family(m) {
  if (m ~ /fable/)  return "fable"
  if (m ~ /mythos/) return "mythos"
  if (m ~ /opus/)   return "opus"
  if (m ~ /sonnet/) return "sonnet"
  if (m ~ /haiku/)  return "haiku"
  return ""
}
# "4.1", "3.0", "5.0" — or "" when the ID carries no version at all.
function model_version(m,   a, tail, p, n) {
  # Version before the family: claude-3-5-haiku-*, claude-3-opus@*.
  if (match(m, /[-.]([0-9]{1,2})(-([0-9]{1,2}))?-(opus|sonnet|haiku)/, a))
    return a[1] "." (a[3] == "" ? "0" : a[3])
  # Version after the family: claude-opus-4-1-*, claude-haiku-4-5-*. Split the
  # tail rather than regex it, so the 8-digit release date in
  # claude-opus-4-20250514 cannot be read as a minor version.
  if (!match(m, /(fable|mythos|opus|sonnet|haiku)[-@]/, a)) return ""
  tail = substr(m, RSTART + RLENGTH)
  n = split(tail, p, /[-@]/)
  if (p[1] !~ /^[0-9]{1,2}$/) return ""
  return p[1] "." ((n >= 2 && p[2] ~ /^[0-9]{1,2}$/) ? p[2] : "0")
}
function rate_tier(m,   f, v) {
  f = model_family(m)
  if (f == "") return ""
  v = model_version(m)
  if (f == "fable")  return (v == "5.0" || v == "5.1") ? "10 12.5 20 1 50" : ""
  if (f == "mythos") return (v == "5.0" || m ~ /mythos-preview/) ? "10 12.5 20 1 50" : ""
  if (f == "opus") {
    if (v == "3.0" || v == "4.0" || v == "4.1")   return "15 18.75 30 1.5 75"
    if (v == "4.5" || v == "4.6" || v == "4.7" ||
        v == "4.8" || v == "5.0")                 return "5 6.25 10 0.5 25"
    return ""
  }
  if (f == "sonnet") {
    if (v == "5.0")                               return "2 2.5 4 0.2 10"
    if (v == "3.0" || v == "3.5" || v == "3.7" ||
        v == "4.0" || v == "4.5" || v == "4.6")   return "3 3.75 6 0.3 15"
    return ""
  }
  if (f == "haiku") {
    if (v == "3.0")                               return "0.25 0.3125 0.5 0.025 1.25"
    if (v == "3.5")                               return "0.8 1 1.6 0.08 4"
    if (v == "4.5")                               return "1 1.25 2 0.1 5"
    return ""
  }
  return ""
}
function usd(model, inp, cr, c5, c1, out,   r, p) {
  r = rate_tier(model)
  # R1-8: accumulate per model, not run-wide. One shared counter printed once
  # per unknown model reported the same total against each of them, which reads
  # as N times the real gap.
  if (r == "") { unpriced[model] += inp + cr + c5 + c1 + out; return 0 }
  split(r, p, " ")
  return (inp*p[1] + c5*p[2] + c1*p[3] + cr*p[4] + out*p[5]) / 1e6
}
{
  date=$2; sess=$3; kind=$4; model=$5
  inp=$6+0; cr=$7+0; c5=$8+0; c1=$9+0; ctot=$10+0; out=$11+0
  if (since != "" && date < since) next
  if (until != "" && date > until) next
  # Older payloads lack the 5m/1h breakdown; count the total as 5m and say so.
  if (c5 + c1 == 0 && ctot > 0) { c5 = ctot; assumed_5m += ctot }
  d = usd(model, inp, cr, c5, c1, out)
  msgs++
  t_in+=inp; t_cr+=cr; t_c5+=c5; t_c1+=c1; t_out+=out; t_usd+=d
  day_tok[date]  += inp+cr+c5+c1+out; day_usd[date]  += d; day_out[date] += out
  ses_tok[sess]  += inp+cr+c5+c1+out; ses_usd[sess]  += d; ses_msgs[sess]++
  mod_tok[model] += inp+cr+c5+c1+out; mod_usd[model] += d
  kin_tok[kind]  += inp+cr+c5+c1+out; kin_usd[kind]  += d
  split(rate_tier(model), p, " ")
  if (p[1] != "") { u_in+=inp*p[1]/1e6; u_c5+=c5*p[2]/1e6; u_c1+=c1*p[3]/1e6; u_cr+=cr*p[4]/1e6; u_out+=out*p[5]/1e6
    # Counterfactual for --check: every input token at base rate, output unchanged.
    u_nocache += ((inp+cr+c5+c1)*p[1] + out*p[5]) / 1e6 }
  # --ttl-compare: reprice this turn under the 1-hour TTL. Input is sorted by
  # stream then timestamp, so prev[] holds the preceding turn of this same
  # context. Keying on session+kind instead (R3-2) merged every subagent of a
  # session into one pseudo-stream, which made the cold start of each subagent
  # look like a >5min gap in a running conversation and counted it as a saving
  # the 1-hour TTL would never have delivered.
  if (ttlc == "1" && p[1] != "") {
    key = $12
    gap = (key in prev) ? epoch($1) - prev[key] : 0
    prev[key] = epoch($1)
    cw = c5 + c1
    unchanged = (inp*p[1] + cr*p[4] + out*p[5]) / 1e6
    # R3-1: price the actual side at the rate each write actually paid — 5m
    # writes at p[2], 1h writes at p[3]. Charging every write at p[2] understated
    # the actual column by c1*(p[3]-p[2]) and inflated the reported saving.
    ttl_act[sess] += unchanged + (c5*p[2] + c1*p[3]) / 1e6
    if (gap > 300 && gap <= 3600) {   # cold at 5m, warm at 1h: write becomes a read
      ttl_cf[sess] += unchanged + cw*p[4]/1e6; conv_tok[sess] += cw; conv_n[sess]++
    } else {                          # unchanged behaviour, dearer write
      ttl_cf[sess] += unchanged + cw*p[3]/1e6; pen_tok[sess] += cw; pen_n[sess]++
      if (gap > 3600) far_n[sess]++
    }
  }
}
END {
  if (msgs == 0) { print "no assistant messages matched the filters"; exit 1 }
  printf "window: %s .. %s   metered messages: %d\n\n", (since==""?"(all)":since), (until==""?"(all)":until), msgs
  printf "== Totals (tokens | USD at list rates) ==\n"
  printf "%-18s %14s %12s\n", "category", "tokens", "USD"
  printf "%-18s %14d %12.2f\n", "fresh input",    t_in,  u_in
  printf "%-18s %14d %12.2f\n", "cache read",     t_cr,  u_cr
  printf "%-18s %14d %12.2f\n", "cache write 5m", t_c5,  u_c5
  printf "%-18s %14d %12.2f\n", "cache write 1h", t_c1,  u_c1
  printf "%-18s %14d %12.2f\n", "output",         t_out, u_out
  printf "%-18s %14d %12.2f\n", "TOTAL", t_in+t_cr+t_c5+t_c1+t_out, t_usd
  if (assumed_5m > 0) printf "note: %d cache-write tokens lacked a 5m/1h breakdown and were priced as 5m\n", assumed_5m
  for (m in unpriced) printf "WARNING: no rate for model %s — %d tokens unpriced (its USD column reads 0)\n", m, unpriced[m]
  printf "\n== Per day ==\n%-12s %14s %12s %12s\n", "day", "tokens", "output", "USD"
  n = asorti(day_tok, di); for (i=1;i<=n;i++) { d2=di[i]; printf "%-12s %14d %12d %12.2f\n", d2, day_tok[d2], day_out[d2], day_usd[d2] }
  printf "\n== Per session (by USD desc) ==\n%-40s %8s %14s %12s\n", "session", "msgs", "tokens", "USD"
  n = asorti(ses_usd, si, "@val_num_desc")
  for (i=1;i<=n;i++) { s2=si[i]; printf "%-40s %8d %14d %12.2f\n", s2, ses_msgs[s2], ses_tok[s2], ses_usd[s2] }
  printf "\n== Per model ==\n%-32s %14s %12s\n", "model", "tokens", "USD"
  n = asorti(mod_usd, mi, "@val_num_desc")
  # A 0.00 next to a large token count is a missing rate, not a free model.
  # Mark those rows so the per-model table cannot be read as complete (R1-8).
  for (i=1;i<=n;i++) { m2=mi[i]
    printf "%-32s %14d %12.2f%s\n", m2, mod_tok[m2], mod_usd[m2], ((m2 in unpriced) ? "  * unpriced" : "") }
  printf "\n== Main vs subagent ==\n"
  for (k2 in kin_tok) printf "%-8s %14d %12.2f\n", k2, kin_tok[k2], kin_usd[k2]

  if (ttlc == "1") {
    printf "\n== Repriced under the 1-hour TTL (2x writes, cold turns <=1h become reads) ==\n"
    printf "%-40s %12s %12s %10s %9s %9s\n", "session", "actual", "at 1h TTL", "change", "converted", "taxed"
    n = asorti(ttl_act, ti, "@val_num_desc")
    for (i=1;i<=n;i++) { s3=ti[i]
      pct = (ttl_act[s3] > 0) ? 100*(ttl_cf[s3]-ttl_act[s3])/ttl_act[s3] : 0
      printf "%-40s %12.2f %12.2f %9.1f%% %9d %9d\n", s3, ttl_act[s3], ttl_cf[s3], pct, conv_n[s3], pen_n[s3]
      g_act += ttl_act[s3]; g_cf += ttl_cf[s3]; g_conv += conv_n[s3]; g_pen += pen_n[s3]; g_far += far_n[s3]
    }
    if (n > 1) printf "%-40s %12.2f %12.2f %9.1f%% %9d %9d\n", "TOTAL", g_act, g_cf, \
      (g_act>0 ? 100*(g_cf-g_act)/g_act : 0), g_conv, g_pen
    printf "converted = cold turns a 1-hour entry would have kept warm; taxed = turns\n"
    printf "that pay the 2x write and gain nothing. %d turn(s) idled past an hour and\n", g_far
    printf "are beyond either TTL. Estimate: a converted turn would still write its delta.\n"
    # R3-1: the counterfactual only answers "what if these turns had run on 1h".
    # Turns that already ran on 1h are repriced onto a TTL they were on, so their
    # contribution to the comparison is noise. Name it rather than let the
    # percentage be read as a clean saving.
    if (t_c1 > 0)
      printf "NOTE: %d cache-write tokens in this window ALREADY used the 1-hour TTL. The\n      counterfactual reprices 5m->1h, so those turns compare against themselves\n      and the change column understates the real difference.\n", t_c1
  }

  if (check != "1") exit

  # Two independent axes. Axis 1 is the price paid per re-sent token; axis 2 is
  # how many tokens are re-sent. A good hit rate on a huge context is still a
  # huge bill, so neither number is a verdict on its own.
  tok = t_in + t_cr + t_c5 + t_c1 + t_out
  denom = t_cr + t_c5 + t_c1 + t_in
  printf "\n== Health check ==\n"
  if (denom == 0) { print "no input tokens in window; nothing to check"; exit }
  hit = 100 * t_cr / denom
  tpm = tok / msgs
  # Caching is net-positive while 1.25W + 0.1R < W + R, i.e. hit rate > 21.7%.
  if      (hit >= 90) h = "HEALTHY   interactive cadence; the TTL is landing"
  else if (hit >= 70) h = "OK        idle gaps or occasional prefix edits"
  else if (hit >= 50) h = "CHECK     cadence may exceed the 5-min TTL"
  else if (hit >= 22) h = "POOR      caching still net-positive, but barely"
  else                h = "BROKEN    caching costs more than it saves here"
  if      (tpm < 100000) v = "LEAN"
  else if (tpm < 250000) v = "NORMAL    typical working session"
  else if (tpm < 400000) v = "HEAVY     consider fan-out or a fresh session"
  else                   v = "BLOATED   every turn re-sends a small book"
  printf "  cache hit rate   %6.1f%%   %s\n", hit, h
  printf "  tokens/message   %6d    %s\n", tpm, v
  printf "  USD/message      %6.3f\n", t_usd / msgs
  # Counterfactual: same tokens with caching off — writes and reads at base rate.
  printf "  vs no caching    %.2f  (would be ~%.2f)\n", t_usd, u_nocache
  if (hit >= 90 && tpm >= 250000)
    printf "  NOTE: price is optimal and volume is not. The remedy is fan-out or\n        a fresh session, NOT a caching change.\n"
  if (hit < 70 && t_c1 == 0)
    printf "  NOTE: the 1-hour TTL was never used. If turns are >5 min apart by\n        design (a polling loop), that is the first thing to change.\n"
}' "$TSV" | tee "$SUMMARY"

echo >&2
echo "wrote: $TSV" >&2
echo "wrote: $SUMMARY" >&2

