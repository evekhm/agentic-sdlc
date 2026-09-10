#!/usr/bin/env bash
# install.sh — wire this directory's scripts into Claude Code and Antigravity.
# Idempotent, and reversible with --uninstall. Sibling of
# scripts/ops/hooks/install.sh, which does the same for git hooks.
#
#   install.sh              # install statusline (user) + SessionStart hook (project)
#   install.sh --check      # run every piece for real and print pass/fail (exit 2 = broken)
#   install.sh --uninstall  # remove both, leaving other settings untouched
#   install.sh --show       # print the settings files' relevant keys
#
# Scope, and why it is split:
#   statusLine  -> ~/.claude/settings.json (and ~/.gemini/antigravity-cli/settings.json).
#                  Context size and spend matter in every session on this VM,
#                  including worktrees, whose project root is the worktree.
#   SessionStart-> <repo>/.claude/settings.json. The handoff is this repo's;
#                  no other project should be primed with it. Uses ${CLAUDE_PROJECT_DIR}
#                  so worktrees resolve portably without absolute path baking.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${REPO_DIR:-$(cd "$HERE/../../.." && pwd)}"
user_root=~
USER_SETTINGS="${CLAUDE_USER_SETTINGS:-$user_root/.claude/settings.json}"
AGY_SETTINGS="${AGY_USER_SETTINGS:-$user_root/.gemini/antigravity-cli/settings.json}"
PROJ_SETTINGS="$REPO/.claude/settings.json"
STATUSLINE="$HERE/statusline.sh"
SESSION_START_CMD='${CLAUDE_PROJECT_DIR}/scripts/ops/harness/session-start.sh'

command -v jq >/dev/null || { echo "install.sh: jq required" >&2; exit 1; }

edit() {  # edit <file> <jq-filter> [--arg ...]
  local file="$1" filter="$2"; shift 2
  mkdir -p "$(dirname "$file")"
  [[ -f "$file" ]] || echo '{}' > "$file"
  [[ -f "$file.bak" ]] || cp "$file" "$file.bak"
  local tmp="$file.tmp.$$"
  jq "$@" "$filter" "$file" > "$tmp" && mv -f "$tmp" "$file"
  echo "updated: $file"
}

case "${1:-}" in
  --show)
    for f in "$USER_SETTINGS" "$AGY_SETTINGS" "$PROJ_SETTINGS"; do
      echo "== $f"
      [[ -f "$f" ]] && jq '{statusLine, hooks, autoCompactWindow}' "$f" 2>/dev/null || echo "  (absent)"
    done
    exit 0 ;;

  --check)
    FAIL=0
    ok()   { printf 'pass  %s\n' "$1"; }
    bad()  { printf 'FAIL  %s\n' "$1"; FAIL=1; }
    note() { printf '      %s\n' "$1"; }

    for s in statusline.sh session-start.sh newest-dated.sh newest-handoff.sh; do
      [[ -x "$HERE/$s" ]] && ok "$s executable" || bad "$s missing or not executable"
    done

    # Check statusLine wiring
    jq -e --arg c "$STATUSLINE" '.statusLine.command == $c' "$USER_SETTINGS" >/dev/null 2>&1 \
      && ok "statusLine wired in $USER_SETTINGS" \
      || bad "statusLine not wired in $USER_SETTINGS (run: $0)"

    # Dual-harness drift check
    if [[ -f "$USER_SETTINGS" && -f "$AGY_SETTINGS" ]]; then
      c_cmd="$(jq -r '.statusLine.command // empty' "$USER_SETTINGS" 2>/dev/null || true)"
      a_cmd="$(jq -r '.statusLine.command // empty' "$AGY_SETTINGS" 2>/dev/null || true)"
      if [[ -n "$c_cmd" && -n "$a_cmd" && "$c_cmd" != "$a_cmd" ]]; then
        bad "drift detected between Claude ($c_cmd) and Antigravity ($a_cmd)"
      else
        ok "no drift between Claude and Antigravity statusLine commands"
      fi
    else
      ok "no drift (single harness or unconfigured)"
    fi

    # Check SessionStart hook wiring
    jq -e --arg c "$SESSION_START_CMD" '[.hooks.SessionStart[]?.hooks[]?.command] | any(. == $c)' \
      "$PROJ_SETTINGS" >/dev/null 2>&1 \
      && ok "SessionStart wired in $PROJ_SETTINGS" \
      || bad "SessionStart not wired in $PROJ_SETTINGS (run: $0)"

    # Test statusline render
    T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
    LINE="$(printf '{"session_id":"selfcheck","model":{"display_name":"Check 1"},"cost":{"total_cost_usd":1.5},"context_window":{"total_input_tokens":168000,"context_window_size":200000,"current_usage":{"input_tokens":1}}}' \
      | CLAUDE_CTX_DIR="$T" CLAUDE_SEAT=selfcheck "$STATUSLINE" 2>/dev/null)" || true
    [[ "$LINE" == *"168.0K/200K 84%"* ]] && ok "statusline renders" || bad "statusline output wrong: ${LINE:-<empty>}"
    note "$LINE"
    jq -e '.used_tokens == 168000 and .pct == 84' "$T/selfcheck.json" >/dev/null 2>&1 \
      && ok "side channel written ($T/selfcheck.json shape)" \
      || bad "side channel not written or wrong shape"

    # Resolver test
    for s in advisor verifier; do
      h="$("$HERE/newest-handoff.sh" "$s" 2>/dev/null)" \
        && { ok "handoff resolves for $s"; note "${h#"$REPO"/}"; } \
        || note "no handoff resolves for $s (acceptable in clean checkout)"
    done

    echo
    (( FAIL == 0 )) && echo "all checks passed" || echo "something is broken; see FAIL above"
    exit $(( FAIL * 2 )) ;;

  --uninstall)
    [[ -f "$USER_SETTINGS" ]] && edit "$USER_SETTINGS" 'del(.statusLine)'
    [[ -f "$AGY_SETTINGS" ]] && edit "$AGY_SETTINGS" 'del(.statusLine)'
    if [[ -f "$PROJ_SETTINGS" ]]; then
      edit "$PROJ_SETTINGS" 'if (.hooks.SessionStart? // empty)
          then .hooks.SessionStart |= map(select(
                 [.hooks[]?.command] | any(test("harness/session-start.sh")) | not))
             | (if (.hooks.SessionStart | length) == 0 then del(.hooks.SessionStart) else . end)
             | (if (.hooks | length) == 0 then del(.hooks) else . end)
          else . end'
    fi
    echo "uninstalled. Backups: *.bak"
    exit 0 ;;

  ""|--install) ;;
  *) sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac

chmod +x "$HERE"/*.sh

edit "$USER_SETTINGS" '.statusLine = {type: "command", command: $cmd, padding: 0}' \
  --arg cmd "$STATUSLINE"

if [[ -d "$(dirname "$AGY_SETTINGS")" ]]; then
  edit "$AGY_SETTINGS" '.statusLine = {type: "command", command: $cmd, padding: 0}' \
    --arg cmd "$STATUSLINE"
fi

edit "$PROJ_SETTINGS" '
  .autoCompactWindow = 180000 |
  .hooks.SessionStart = (
    ((.hooks.SessionStart // []) | map(select(
      [.hooks[]?.command] | any(test("harness/session-start.sh")) | not)))
    + [{hooks: [{type: "command", command: $cmd, timeout: 10}]}])' \
  --arg cmd "$SESSION_START_CMD"

cat <<MSG

installed:
  statusLine     $STATUSLINE          (user scope)
  SessionStart   $SESSION_START_CMD   (project scope, $REPO)

The statusline also writes \${AGENTIC_CTX_DIR:-~/.claude/context}/<session>.json.
MSG
