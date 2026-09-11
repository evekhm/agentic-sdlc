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
# `--labels-only` runs the label section and exits before anything
# touches an issue. The label taxonomy (#4) outlives the bootstrap
# backlog and gets extended long after the issue bodies here have
# drifted, so growing the taxonomy must never depend on the issue
# half of this script still being accurate.
#
# Issue body files may reference each other as {{slug}} (slug = the
# filename after NN-). Files are processed in filename order, so a
# body may only reference slugs from earlier files; the tracker
# (00-tracker.md) is filed last and may reference every slug.
set -euo pipefail

usage() {
  cat <<'EOF'
  export GITHUB_REPO="<owner>/<repo>"    # default: evekhm/agentic-sdlc
  bash scripts/setup/bootstrap_tracker.sh                 # labels + issues + tracker
  bash scripts/setup/bootstrap_tracker.sh --labels-only   # labels only, then exit

--labels-only provisions the label taxonomy and NOTHING else: no issue
is read, filed, or pinned, and scripts/setup/issues/ is not even
required to exist. That mode is the one to reach for when the taxonomy
grows, because the issue body files drift as the backlog is worked
(numbers move, bodies are edited on GitHub) and re-filing against
drifted bodies is not a thing anyone wants to risk for a label.

Prerequisites: gh (authenticated as an identity with write access to
the repo: labels need push, issues need triage or better), jq.
EOF
}

GITHUB_REPO="${GITHUB_REPO:-evekhm/agentic-sdlc}"
ISSUE_DIR="$(cd "$(dirname "$0")" && pwd)/issues"

LABELS_ONLY=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --labels-only) LABELS_ONLY=1; shift;;
    -h|--help)     usage; exit 0;;
    *) echo "ERROR: unknown argument '$1'." >&2; usage; exit 1;;
  esac
done

# --- Preflight ---------------------------------------------------------------
for cmd in gh jq; do
  command -v "$cmd" >/dev/null || { echo "ERROR: $cmd is not installed." >&2; usage; exit 1; }
done
if [ "$LABELS_ONLY" -eq 0 ]; then
  [ -d "$ISSUE_DIR" ] || { echo "ERROR: $ISSUE_DIR not found — run from the repo checkout." >&2; exit 1; }
fi

perm="$(gh repo view "$GITHUB_REPO" --json viewerPermission --jq .viewerPermission 2>/dev/null || true)"
case "$perm" in
  ADMIN|MAINTAIN|WRITE) echo "==> $GITHUB_REPO reachable (permission: $perm)";;
  *) echo "ERROR: cannot write to $GITHUB_REPO (permission: ${perm:-none})." >&2
     echo "Fix: create the repo, or invite this identity with write access." >&2
     exit 1;;
esac

# --- Labels (the lifecycle taxonomy; #4) --------------------------------------
# One listing call, cached: ensure_label is called a dozen-plus times and
# re-listing per call is a dozen-plus API round trips to learn the same
# answer. A failed listing is an ERROR, never an empty tree — reading it
# as "no labels exist" would make every ensure_label attempt a create.
LABELS_CACHE=""
refresh_labels() {
  LABELS_CACHE="$(gh label list --repo "$GITHUB_REPO" --limit 200 --json name --jq '.[].name')" \
    || { echo "ERROR: cannot list labels on $GITHUB_REPO." >&2; exit 1; }
}
has_label() { printf '%s\n' "$LABELS_CACHE" | grep -Fxq "$1"; }

ensure_label() { # name color description
  if has_label "$1"; then
    echo "    label '$1' exists — kept"
  elif gh label create "$1" --repo "$GITHUB_REPO" --color "$2" --description "$3" \
       >/dev/null 2>&1; then
    LABELS_CACHE="$LABELS_CACHE
$1"
    echo "    label '$1' created"
  else
    # Re-check against a FRESH listing: a create failure is fine iff the
    # label now exists (race with another run, or a colour-only change).
    refresh_labels
    has_label "$1" || { echo "ERROR: could not create label '$1'." >&2; exit 1; }
    echo "    label '$1' raced an existing label — kept"
  fi
}

echo "==> Labels"
refresh_labels

# Human-facing: filed by people, read by people, honoured by automation.
ensure_label "bootstrap"   "1D76DB" "Bootstrap backlog: building the system that builds itself"
ensure_label "intent:new"  "0E8A16" "Intake: a proposed change entering the lifecycle"
ensure_label "intake:auto" "C2E0C6" "Opt-in for automated first-hop poller intake"
ensure_label "in-progress" "FBCA04" "Claimed by a session (the parallelism mutex)"
ensure_label "hold"        "B60205" "Circuit breaker: halts all automation while present"
ensure_label "blocked"     "D93F0B" "Needs a human or an unmet dependency"

# Machine-driven stage state (#4): at most ONE status:* per issue, ever.
# One hue family, darkening along the ladder, so the stage of a board is
# legible at a glance and a stray pair is visibly wrong.
ensure_label "status:planning"     "D4C5F9" "Stage: intent.md is being drafted (PLAN gate open)"
ensure_label "status:spec"         "BFA8F0" "Stage: spec.md is being drafted (DESIGN gate open)"
ensure_label "status:build"        "A98BE8" "Stage: plan.md + contract tests (BUILD gate open)"
ensure_label "status:implementing" "936FDD" "Stage: implementation at a pinned SHA"
ensure_label "status:in-review"    "7D52D1" "Stage: reviewers hold it (written by lifecycle.yml on the implementing PR's merge)"
# Escalation, deliberately outside the ladder's hue: humans take over.
ensure_label "status:review-stuck" "E11D21" "Review counter tripped at review:3 — humans take over"

# Review iteration counter (predecessor convention); review:3 escalates.
ensure_label "review:1" "C2F0EA" "Review iteration 1"
ensure_label "review:2" "76D7C4" "Review iteration 2"
ensure_label "review:3" "117A65" "Review iteration 3 — sets status:review-stuck"

# Review and consensus labels derived by Themis from the findings ledger (#267).
ensure_label "argus:findings"    "D93F0B" "Open blocking findings (security or high) on the pull request"
ensure_label "argus:suggestions" "C5DEF5" "Open non-blocking findings (normal or suggestion) on the pull request"
ensure_label "consensus:agreed"  "0E8A16" "All security findings agreed and no disputes on blocking rows"
ensure_label "consensus:pending" "FBCA04" "Security findings awaiting peer review concurrence"
ensure_label "consensus:disputed" "B60205" "Active dispute on one or more blocking findings"
ensure_label "review:merge-ready" "0E8A16" "No open blocking findings, consensus agreed, reviewed at current head"
ensure_label "review:verifying"  "1D76DB" "Open blocking findings exist and pull request head is newer than reviewed head"
ensure_label "deep-review" "5319E7" "Review grant: brings Argus into review before code gate"

# Area labels and triage support (#404).
ensure_label "duplicate"     "CFD3D7" "Duplicate: closed as duplicate of an existing issue or thread"
ensure_label "area:personas" "C5DEF5" "Issues and changes touching personas and agent definitions"
ensure_label "area:ci"       "C5DEF5" "Issues and changes touching CI workflows and merge gates"
ensure_label "area:ops"      "C5DEF5" "Issues and changes touching operational scripts and tooling"
ensure_label "area:docs"     "C5DEF5" "Issues and changes touching documentation and specifications"
ensure_label "area:harness"  "C5DEF5" "Issues and changes touching execution harnesses and runtime"

if [ "$LABELS_ONLY" -eq 1 ]; then
  echo "==> Done (--labels-only). No issue was read, filed, or pinned."
  exit 0
fi

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
