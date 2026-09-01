#!/usr/bin/env bash
# The sanitization gate (#6), run by .github/workflows/ci-gates.yml and
# runnable locally with no arguments.
#
# It scans every TRACKED file in the working tree for three classes of
# thing that must never reach a public repository:
#
#   home    an absolute home-directory path or a $HOME reference — the
#           account name of whoever ran the tool, baked into a file
#   secret  a credential SHAPE (GitHub token, fine-grained PAT, AWS
#           access key id, generic sk- key, Slack token, private key
#           block). Secret NAMES in caps (ATHENA_BOT_TOKEN) are the
#           point of the persona sources and are deliberately allowed
#   vendor  a vendor, model, or model-family name inside personas/**,
#           which enforces #1's D3: personas are vendor-agnostic and
#           every vendor string lives in config/
#
# Failure mode first: any finding prints one line and the script exits
# 1. Exit 0 means the scan RAN and found nothing — an unreadable file,
# a missing git, or a bad allowlist line is an error, never "clean".
#
# Deliberately NOT covered here, because a different mechanism already
# owns it: `~/`-relative paths carry no account name, and the strings
# specific to one operator's machine (a local username, an internal
# domain) are supplied at run time to the compiler through
# SYNC_AGENTS_DENY and are never committed — hard-coding the literal
# you are hiding into a public checker is the leak it was meant to
# prevent (#5, D8a). The compiler's emit-time sanitizer is stricter
# than this gate on purpose: it protects prompts that SHIP, this gate
# protects the repository.
#
# Usage:
#   scripts/ci/sanitize_check.sh              # all tracked files
#   scripts/ci/sanitize_check.sh path [path]  # only these pathspecs
#
# Exemptions live in scripts/ci/sanitize_allowlist.txt, one
# `<rule> <path>  # reason` per line, and are scoped to ONE rule and
# ONE exact path — never a directory, never all rules at once.

set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
ALLOWLIST="$REPO/scripts/ci/sanitize_allowlist.txt"

die() { echo "ERROR: sanitize_check: $*" >&2; exit 1; }

command -v git >/dev/null || die "git is not installed"
git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || die "$REPO is not a git repository"

# --- patterns -----------------------------------------------------------------
# The home-path fragments are ASSEMBLED from pieces so that this file
# never contains the literal prefix it hunts for. A scanner that trips
# on its own source teaches people to write exemptions, and the first
# real leak lands inside one. The credential regexes need no such trick:
# a character class is not a match for itself.
_H='ho'; _H+='me'
_U='Us'; _U+='ers'
HOME_RE="/(${_H}|${_U})/[A-Za-z0-9._-]+|[\$]${_H^^}"

SECRET_RE=(
  '\bgh[pousr]_[A-Za-z0-9]{16,}'
  '\bgithub_pat_[A-Za-z0-9_]{16,}'
  '\bAKIA[0-9A-Z]{16}\b'
  '\bsk-[A-Za-z0-9]{20,}'
  '\bxox[baprs]-[A-Za-z0-9-]{10,}'
  '-----BEGIN [A-Z ]*PRIVATE KEY-----'
)
SECRET_LABEL=(
  'GitHub token'
  'GitHub fine-grained token'
  'AWS access key id'
  'API secret key'
  'Slack token'
  'private key block'
)

VENDOR_RE='\b(claude|gemini|sonnet|opus|haiku|flash|gpt|vertex|anthropic|google)\b'

# --- allowlist ----------------------------------------------------------------
# `<rule> <path>` pairs, joined with a NUL-free separator so an exact
# lookup is a substring test on a fixed string.
allowed=""
if [ -e "$ALLOWLIST" ]; then
  [ -r "$ALLOWLIST" ] || die "$ALLOWLIST exists but is not readable"
  lineno=0
  while IFS= read -r raw || [ -n "$raw" ]; do
    lineno=$((lineno + 1))
    entry="${raw%%#*}"
    # shellcheck disable=SC2295
    entry="$(printf '%s' "$entry" | tr -s '[:space:]' ' ')"
    entry="${entry# }"; entry="${entry% }"
    [ -n "$entry" ] || continue
    rule="${entry%% *}"
    path="${entry#* }"
    case "$rule" in
      home|secret|vendor) ;;
      *) die "$ALLOWLIST:$lineno: unknown rule '$rule' (want home, secret or vendor)" ;;
    esac
    [ -n "$path" ] && [ "$path" != "$rule" ] \
      || die "$ALLOWLIST:$lineno: rule '$rule' has no path"
    allowed+="|${rule}:${path}|"
  done < "$ALLOWLIST"
fi

# allowed <rule> <path>
allowed() { case "$allowed" in *"|$1:$2|"*) return 0 ;; *) return 1 ;; esac; }

# --- the scan -----------------------------------------------------------------
if [ "$#" -gt 0 ]; then
  mapfile -d '' -t files < <(git -C "$REPO" ls-files -z -- "$@")
else
  mapfile -d '' -t files < <(git -C "$REPO" ls-files -z)
fi
[ "${#files[@]}" -gt 0 ] || die "no tracked files matched; refusing to report a clean tree"

findings=0
scanned=0

# report <path> <line> <label>            — location only, never the match
report() {
  findings=$((findings + 1))
  printf '%s:%s: %s\n' "$1" "$2" "$3"
}

for rel in "${files[@]}"; do
  abs="$REPO/$rel"
  # A tracked path can be absent in a partial checkout; that is an
  # error, not a clean file.
  [ -f "$abs" ] || die "tracked file is missing from the working tree: $rel"
  # Binary and empty files hold no findings worth a line number.
  grep -Iq '' -- "$abs" || continue
  scanned=$((scanned + 1))

  if ! allowed home "$rel"; then
    while IFS=: read -r n _; do
      [ -n "$n" ] && report "$rel" "$n" "absolute home path or \$HOME reference"
    done < <(grep -nE -- "$HOME_RE" "$abs" || true)
  fi

  if ! allowed secret "$rel"; then
    for i in "${!SECRET_RE[@]}"; do
      while IFS=: read -r n _; do
        [ -n "$n" ] && report "$rel" "$n" "credential shape: ${SECRET_LABEL[$i]}"
      done < <(grep -nE -- "${SECRET_RE[$i]}" "$abs" || true)
    done
  fi

  case "$rel" in
    personas/*)
      if ! allowed vendor "$rel"; then
        while IFS=: read -r n hit; do
          [ -n "$n" ] && report "$rel" "$n" "vendor name in a persona source: $hit"
        done < <(grep -noiE -- "$VENDOR_RE" "$abs" || true)
      fi
      ;;
  esac
done

if [ "$findings" -gt 0 ]; then
  echo
  echo "sanitize_check: $findings finding(s) in $scanned files."
  echo "The matched text is deliberately NOT printed: a scanner that echoes a"
  echo "credential into a public build log has published it. Open each file at"
  echo "the line above and fix it one of three ways:"
  echo "  home    — take the path out; make it relative, or read it at run time"
  echo "  secret  — rotate the credential, then remove it; commit the NAME only"
  echo "  vendor  — move the vendor string into config/, keep personas/ abstract"
  echo "An exemption is a last resort: add '<rule> <path>  # reason' to"
  echo "scripts/ci/sanitize_allowlist.txt. It scopes to that one rule and that"
  echo "one path, and the reason is reviewed like any other claim."
  [ "${GITHUB_ACTIONS:-}" = "true" ] && echo "::error::sanitize gate: $findings finding(s); see the log above"
  exit 1
fi

echo "PASS: sanitize gate green ($scanned text files scanned, 0 findings)."
