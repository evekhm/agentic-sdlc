#!/usr/bin/env bash
# statusline.sh — Claude Code / Antigravity statusLine command. Two jobs:
#
#   1. Display context size against the 200K working ceiling (AGENTS.md
#      "Context ceiling"), session spend, and session-accumulated tokens
#      in/out, so the operator never has to ask an agent how expensive it
#      has become.
#   2. Write the same numbers to a side-channel file, because no hook event
#      receives a token count. Hooks read the file; this script is the only
#      place the harness hands the number over.
#
# stdin: the statusLine JSON payload (session_id, model, cost, context_window).
# stdout: one line, rendered in the terminal chrome.
#
# Env:
#   AGENTIC_CONTEXT_CEILING / CLAUDE_CONTEXT_CEILING  working ceiling in tokens (default 200000)
#   AGENTIC_CTX_DIR / CLAUDE_CTX_DIR / AGY_CTX_DIR    side-channel directory (default ~/.claude/context)
#   AGENTIC_SEAT / CLAUDE_SEAT                        seat name, shown in the line when set (seat.sh exports it)
#
# Why an absolute ceiling and not context_window.used_percentage: that field
# is measured against context_window_size, which is 1M on this deployment.
# The economic line is 200K (past it the whole request reprices at the
# long-context premium), so a threshold on the percentage fires 5x too late.
set -uo pipefail

CEILING="${AGENTIC_CONTEXT_CEILING:-${CLAUDE_CONTEXT_CEILING:-200000}}"
user_root=~
CTX_DIR="${AGENTIC_CTX_DIR:-${CLAUDE_CTX_DIR:-${AGY_CTX_DIR:-$user_root/.claude/context}}}"
SEAT="${AGENTIC_SEAT:-${CLAUDE_SEAT:-}}"

payload="$(cat)"

# One jq pass; the rest is pure bash so a render costs a single subprocess.
IFS=$'\t' read -r sid model used window cost dur hit warm ttl cwrite creq cmiss outtok effort has_req < <(
  printf '%s' "$payload" | jq -r '
    def nz($d): if . == null or . == "" then $d else . end;
    . as $r
    | (.context_window // {}) as $cw
    | ($cw.current_usage // {}) as $cu
    | (.prompt_cache // {}) as $pc
    | [ ($r.session_id | nz($r.conversation_id | nz("unknown")))
      , ($r.model.display_name | nz($r.model.id | nz("model")))
      , ( $cw.total_input_tokens
          // (($cu.input_tokens // 0) + ($cu.cache_read_input_tokens // 0)
              + ($cu.cache_creation_input_tokens // 0)) )
      , ($cw.context_window_size // 0)
      # Cost is rendered only when the harness reports one. An internal-quota
      # account carries no .cost at all; printing $0.00 there is a fabricated
      # number (#330 ruling item 4, operator decision 2026-09-10 on open
      # question 3: tokens only when cost is absent). Absent reads as "-".
      , ((.cost.total_cost_usd // .cost.total_usd) | if . == null then "-" else . end)
      , (.cost.total_duration_ms // 0)
      # Cache hit calculation: Claude prompt_cache.hit_ratio, or Antigravity cache_read_input_tokens / input_tokens
      , (if $pc.hit_ratio != null then ($pc.hit_ratio * 100 | floor)
         elif ($cu.cache_read_input_tokens != null and ($cu.input_tokens // $cw.total_input_tokens // 0) > 0)
         then (($cu.cache_read_input_tokens * 100) / ($cu.input_tokens // $cw.total_input_tokens) | floor)
         else -1 end)
      , (if $pc.warm != null then ($pc.warm | tostring)
         elif $cu.cache_read_input_tokens != null then (if $cu.cache_read_input_tokens > 0 then "true" else "false" end)
         else "-" end)
      , ($pc.ttl // "-")
      , ($pc.cache_write_tokens // 0)
      , ($pc.requests // -1)
      , ($pc.misses // 0)
      , ( $cw.total_output_tokens // ($cu.output_tokens // 0) )
      , ($r.effort.level | nz($r.model.effort | nz("-")))
      , (if $pc.requests != null then "true" else "false" end)
      ] | @tsv' 2>/dev/null
)
[[ -n "${sid:-}" ]] || exit 0   # unparseable payload: print nothing, never break the chrome
[[ "$sid" == "null" ]] && exit 0
[[ "$warm" == "-" ]] && warm=""
[[ "$ttl"  == "-" ]] && ttl=""
[[ "$cost" == "-" ]] && cost=""
[[ "$effort" == "-" ]] && effort=""

pct=$(( CEILING > 0 ? used * 100 / CEILING : 0 ))

# Session-accumulated tokens in/out.
accum_in=0 accum_out=0 prev_req=-1
if [[ "$sid" != unknown && -f "$CTX_DIR/$sid.json" ]]; then
  prev="$(cat "$CTX_DIR/$sid.json" 2>/dev/null)"
  [[ "$prev" =~ \"accum_input_tokens\":([0-9]+) ]]  && accum_in="${BASH_REMATCH[1]}"
  [[ "$prev" =~ \"accum_output_tokens\":([0-9]+) ]] && accum_out="${BASH_REMATCH[1]}"
  [[ "$prev" =~ \"requests\":([0-9]+) ]]             && prev_req="${BASH_REMATCH[1]}"
fi

if [[ "$has_req" == "true" ]]; then
  # Claude Code: requests is monotonic per-session call counter
  if (( creq != prev_req )); then
    accum_in=$(( accum_in + used ))
    accum_out=$(( accum_out + outtok ))
  fi
else
  # Antigravity: total_output_tokens is already a session running sum
  accum_out=$outtok
  accum_in=$used
fi
accum_tot=$(( accum_in + accum_out ))

# Side channel for the hooks. Atomic so a reader never sees a half-written file.
if [[ "$sid" != unknown ]]; then
  target_dir="$CTX_DIR"
  if ! mkdir -p "$target_dir" 2>/dev/null || [ ! -w "$target_dir" ]; then
    target_dir="/tmp/agentic-context"
    mkdir -p "$target_dir" 2>/dev/null || true
  fi
  tmp="$target_dir/.$sid.$$"
  ts="$(printf '%(%s)T' -1 2>/dev/null || date +%s)"
  printf '{"session_id":"%s","used_tokens":%s,"output_tokens":%s,"total_tokens":%s,"accum_input_tokens":%s,"accum_output_tokens":%s,"accum_total_tokens":%s,"ceiling":%s,"pct":%s,"window_size":%s,"cost_usd":%s,"duration_ms":%s,"seat":"%s","cache":{"hit_pct":%s,"warm":"%s","ttl":"%s","write_tokens":%s,"requests":%s,"misses":%s},"pre_compact_mechanical_ts":null,"pre_compact_narrative_ts":null,"ts":%s}\n' \
    "$sid" "$used" "$outtok" "$(( used + outtok ))" \
    "$accum_in" "$accum_out" "$accum_tot" \
    "$CEILING" "$pct" "$window" "${cost:-null}" "$dur" "$SEAT" \
    "$hit" "$warm" "$ttl" "$cwrite" "${creq:--1}" "$cmiss" "$ts" \
    > "$tmp" 2>/dev/null && mv -f "$tmp" "$target_dir/$sid.json" 2>/dev/null
  printf '%s' "$payload" > "$target_dir/$sid.raw.json" 2>/dev/null
fi

# Thresholds:
#   120K (60%)  yellow "wrap soon"  — runway to reach a stopping point
#   140K (70%)  red    "WRAP NOW"   — the last point a close-out still fits
#   180K (90%)  red    "COMPACTING" — backstop territory, state is at risk
D=$'\033[0m'; DIM=$'\033[2m'
if   (( pct >= 90 )); then C=$'\033[1;31m'; TAG=" COMPACTING"
elif (( pct >= 70 )); then C=$'\033[1;31m'; TAG=" WRAP NOW"
elif (( pct >= 60 )); then C=$'\033[33m';   TAG=" wrap soon"
else                       C=$'\033[32m';   TAG=""
fi

# Cache health
CACHE=""
if (( hit >= 0 )); then
  if   [[ "$warm" == "false" ]]; then CC=$'\033[33m'; SUFFIX=" cold"
  elif (( hit < 80 ));            then CC=$'\033[33m'; SUFFIX=""
  else                                 CC="$DIM";      SUFFIX=""
  fi
  CACHE="$(printf '  %scache %s%%%s%s%s' "$CC" "$hit" "$SUFFIX" "${ttl:+ $ttl}" "$D")"
fi

fmt_tok() {
  local n=$1
  if   (( n >= 1000000 )); then printf '%d.%01dM' $(( n / 1000000 )) $(( n % 1000000 / 100000 ))
  elif (( n >= 1000 ));    then printf '%d.%01dK' $(( n / 1000 ))    $(( n % 1000 / 100 ))
  else                          printf '%d' "$n"
  fi
}

fmt_tok_round() {
  local n=$1
  if   (( n >= 1000000 )); then printf '%d.%01dM' $(( (n + 50000) / 1000000 )) $(( (n + 50000) % 1000000 / 100000 ))
  elif (( n >= 1000 ));    then printf '%d.%01dK' $(( (n + 50) / 1000 ))    $(( (n + 50) % 1000 / 100 ))
  else                          printf '%d' "$n"
  fi
}

TOK="$(printf '  %stok %s in/%s out/%s tot%s' "$DIM" "$(fmt_tok "$accum_in")" "$(fmt_tok "$accum_out")" "$(fmt_tok_round "$accum_tot")" "$D")"
(( cwrite > 0 )) && CACHE+="$(printf ' %scw %s%s' "$DIM" "$(fmt_tok "$cwrite")" "$D")"

COST=""
[[ -n "$cost" ]] && COST="$(printf '  %s$%.2f%s' "$DIM" "$cost" "$D")"

printf '%sctx %s.%sK/%sK %s%%%s%s%s%s%s  %s%s%s%s%s\n' \
  "$C" "$(( used / 1000 ))" "$(( used % 1000 / 100 ))" "$(( CEILING / 1000 ))" "$pct" "$TAG" "$D" \
  "$COST" "$TOK" "$CACHE" \
  "$DIM" "$model" "${effort:+ [$effort]}" "${SEAT:+ · $SEAT}" "$D"
