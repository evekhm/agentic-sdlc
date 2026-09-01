#!/usr/bin/env bash
# Provisions the bootstrap tracker on GitHub: the base labels, the
# bootstrap backlog issues (bodies live in scripts/setup/issues/*.md,
# reviewable before anything is filed), and the pinned tracker issue
# that indexes them.
#
# Idempotent — safe to re-run: existing labels are kept, issues are
# matched by exact title and reused (numbers stay stable), and an
# existing tracker issue's body is NEVER overwritten (its checkboxes
# are live state).
#
# Issue body files may reference each other as {{slug}} (slug = the
# filename after NN-). Files are processed in filename order, so a
# body may only reference slugs from earlier files; the tracker
# (00-tracker.md) is filed last and may reference every slug.
set -euo pipefail

usage() {
  cat <<'EOF'
  export GITHUB_REPO="<owner>/<repo>"    # default: evekhm/agentic-sdlc
  bash scripts/setup/bootstrap_tracker.sh

Prerequisites: gh (authenticated as an identity with write access to
the repo: labels need push, issues need triage or better), jq.
The label set here is the bootstrap minimum; the full lifecycle
taxonomy is decided in the label-taxonomy issue — extend this script
there so provisioning stays re-runnable.
EOF
}

GITHUB_REPO="${GITHUB_REPO:-evekhm/agentic-sdlc}"
ISSUE_DIR="$(cd "$(dirname "$0")" && pwd)/issues"

# --- Preflight ---------------------------------------------------------------
for cmd in gh jq; do
  command -v "$cmd" >/dev/null || { echo "ERROR: $cmd is not installed." >&2; usage; exit 1; }
done
[ -d "$ISSUE_DIR" ] || { echo "ERROR: $ISSUE_DIR not found — run from the repo checkout." >&2; exit 1; }

perm="$(gh repo view "$GITHUB_REPO" --json viewerPermission --jq .viewerPermission 2>/dev/null || true)"
case "$perm" in
  ADMIN|MAINTAIN|WRITE) echo "==> $GITHUB_REPO reachable (permission: $perm)";;
  *) echo "ERROR: cannot write to $GITHUB_REPO (permission: ${perm:-none})." >&2
     echo "Fix: create the repo, or invite this identity with write access." >&2
     exit 1;;
esac

# --- Labels (bootstrap minimum; label-taxonomy issue extends this) -----------
ensure_label() { # name color description
  if gh label list --repo "$GITHUB_REPO" --limit 100 --json name \
       --jq '.[].name' | grep -Fxq "$1"; then
    echo "    label '$1' exists — kept"
  elif gh label create "$1" --repo "$GITHUB_REPO" --color "$2" --description "$3" \
       >/dev/null 2>&1; then
    echo "    label '$1' created"
  else
    # Re-check: a create failure is fine iff the label now exists (race).
    gh label list --repo "$GITHUB_REPO" --limit 100 --json name \
      --jq '.[].name' | grep -Fxq "$1" \
      || { echo "ERROR: could not create label '$1'." >&2; exit 1; }
    echo "    label '$1' raced an existing label — kept"
  fi
}

echo "==> Labels"
ensure_label "bootstrap"   "1D76DB" "Bootstrap backlog: building the system that builds itself"
ensure_label "intent:new"  "0E8A16" "Intake: a proposed change entering the lifecycle"
ensure_label "in-progress" "FBCA04" "Claimed by a session (the parallelism mutex)"
ensure_label "hold"        "B60205" "Circuit breaker: halts all automation while present"
ensure_label "blocked"     "D93F0B" "Needs a human or an unmet dependency"

# --- Issues -------------------------------------------------------------------
issue_number_by_title() { # exact title -> number or empty
  gh issue list --repo "$GITHUB_REPO" --state all --limit 200 \
    --json number,title \
    | jq -r --arg t "$1" 'map(select(.title == $t)) | (.[0].number // empty)'
}

declare -A NUM  # slug -> issue number

substitute() { # body on stdin; {{slug}} -> #N for every known slug
  local body slug
  body="$(cat)"
  for slug in "${!NUM[@]}"; do
    body="${body//\{\{$slug\}\}/#${NUM[$slug]}}"
  done
  printf '%s\n' "$body"
}

file_issue() { # path -> sets NUM[slug]
  local f="$1" base slug title labels body existing url n
  base="$(basename "$f" .md)"
  slug="${base#[0-9][0-9]-}"
  title="$(sed -n 's/^Title: //p' "$f")"
  labels="$(sed -n 's/^Labels: //p' "$f")"
  [ -n "$title" ] || { echo "ERROR: $f has no 'Title:' line." >&2; exit 1; }
  body="$(sed -n '/^---$/,$p' "$f" | sed '1d' | substitute)"
  if printf '%s' "$body" | grep -q '{{'; then
    echo "ERROR: unresolved {{slug}} reference in $f — file order must follow dependency order." >&2
    printf '%s' "$body" | grep -o '{{[a-z-]*}}' | sort -u >&2
    exit 1
  fi
  existing="$(issue_number_by_title "$title")"
  if [ -n "$existing" ]; then
    NUM[$slug]="$existing"
    echo "    #$existing '$title' exists — kept"
  else
    url="$(printf '%s' "$body" | gh issue create --repo "$GITHUB_REPO" \
             --title "$title" --label "$labels" --body-file -)"
    n="${url##*/}"
    NUM[$slug]="$n"
    echo "    #$n '$title' created"
  fi
}

echo "==> Backlog issues"
for f in "$ISSUE_DIR"/[0-9][0-9]-*.md; do
  case "$(basename "$f")" in 00-tracker.md) continue;; esac
  file_issue "$f"
done

# --- Tracker (filed last; never overwritten once it exists) -------------------
echo "==> Tracker issue"
tracker_file="$ISSUE_DIR/00-tracker.md"
tracker_title="$(sed -n 's/^Title: //p' "$tracker_file")"
tracker_n="$(issue_number_by_title "$tracker_title")"
if [ -n "$tracker_n" ]; then
  echo "    #$tracker_n exists — body left untouched (its checkboxes are live state)"
else
  file_issue "$tracker_file"
  tracker_n="${NUM[tracker]}"
fi

node_id="$(gh api "repos/$GITHUB_REPO/issues/$tracker_n" --jq .node_id)"
if gh api graphql -f query='mutation($id:ID!){pinIssue(input:{issueId:$id}){issue{number}}}' \
     -f id="$node_id" >/dev/null 2>&1; then
  echo "    #$tracker_n pinned"
else
  echo "    #$tracker_n pin skipped (already pinned, or the 3-pin limit) — pin manually if needed"
fi

echo "==> Done. Tracker: https://github.com/$GITHUB_REPO/issues/$tracker_n"
