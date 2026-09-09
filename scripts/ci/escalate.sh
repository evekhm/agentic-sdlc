#!/usr/bin/env bash
# scripts/ci/escalate.sh <issue> --reason <reason-code> --head <full-oid> [--pr <n>]
#
# The ONE escalation writer (#64, D9). Exactly two writes: swap the
# issue's status:* label for status:review-stuck, and post one comment
# carrying <!-- escalation:<displaced-label>:<reason-code>:<head-oid> -->.
# Idempotent on (reason-code, head-oid), judged only against markers
# posted by a trusted writer (D23): the merge actor alone, resolved from
# the token in scope via GraphQL `viewer { login }` (D30) and never
# guessed; `github-actions[bot]` is not trusted. Re-reads hold/blocked on the
# issue and the pull request before writing (D15) and writes nothing
# when either is set. An unreadable thread refuses the escalation; it
# never duplicates one.
#
# Two tokens (D25, D26): the comment write and the marker read use
# MERGE_ACTOR_TOKEN; the status:* -> status:review-stuck label swap uses
# the caller's ambient GH_TOKEN. In the gate job (merge_gate.sh) both
# are the merge actor's token. From lifecycle.yml on a D14 refusal,
# GH_TOKEN is github.token (a label write with it starts no workflow)
# and MERGE_ACTOR_TOKEN is the merge actor's minted token, passed
# separately.
set -euo pipefail

usage() { echo "Usage: $0 <issue> --reason <reason-code> --head <full-oid> [--pr <n>]" >&2; exit 1; }
[ $# -ge 5 ] || usage
ISSUE="$1"; shift
REASON=""; HEAD=""; PR=""
while [ $# -gt 0 ]; do
    case "$1" in
        --reason) REASON="${2:-}"; shift 2;;
        --head) HEAD="${2:-}"; shift 2;;
        --pr) PR="${2:-}"; shift 2;;
        *) echo "Unknown flag: $1" >&2; usage;;
    esac
done
case "$REASON" in
    consensus-timeout|dispute-at-cap|blocking-open-at-cap|security-open|budget|non-monotonic|behind) ;;
    *) echo "escalate: reason-code '$REASON' is not one D9 names" >&2; exit 1;;
esac
[[ "$HEAD" =~ ^[0-9a-f]{40}$ ]] || { echo "escalate: --head must be a full 40-hex commit OID, got '$HEAD'" >&2; exit 1; }

R="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY must name <owner>/<repo>}"
DRY_RUN="${DRY_RUN:-0}"
MERGE_ACTOR_TOKEN="${MERGE_ACTOR_TOKEN:-${GH_TOKEN:-}}"

log() { printf '%s\n' "$*" >&2; }
gh_write() { if [ "$DRY_RUN" = "1" ]; then log "DRY-RUN gh $*"; else gh "$@" >/dev/null; fi; }

# --- the merge actor's own login (S3, D23, D30): read from the token it writes with.
# `GET /user` is 403 for an App installation token; GraphQL `viewer`
# answers with the `<slug>[bot]` login the marker's author carries.
VIEWER_QUERY='query { viewer { login } }'
if ! MERGE_ACTOR="$(GH_TOKEN="$MERGE_ACTOR_TOKEN" gh api graphql -f query="$VIEWER_QUERY" 2>/dev/null | jq -r '.data.viewer.login // empty')" || [ -z "$MERGE_ACTOR" ]; then
    log "escalate: cannot resolve the merge actor's login via GraphQL viewer — refused, nothing written (S3, D30)"
    exit 1
fi
if [ "$MERGE_ACTOR" = "github-actions[bot]" ]; then
    log "escalate: MERGE_ACTOR_TOKEN resolves to github-actions[bot], which D23 never trusts — refused, nothing written (D30)"
    exit 1
fi
TRUSTED="$(jq -nc --arg a "$MERGE_ACTOR" '[$a]')"

# --- D15: hold / blocked on the issue and the pull request --------------------------
ISSUE_LABELS="$(gh issue view "$ISSUE" --json labels | jq -r '.labels[]?.name')" \
    || { log "escalate: cannot read #$ISSUE labels — refused, nothing written"; exit 1; }
PR_LABELS=""
if [ -n "$PR" ]; then
    PR_LABELS="$(gh pr view "$PR" --json labels | jq -r '.labels[]?.name')" \
        || { log "escalate: cannot read #$PR labels — refused, nothing written"; exit 1; }
fi
if printf '%s\n%s\n' "$ISSUE_LABELS" "$PR_LABELS" | grep -qxE 'hold|blocked'; then
    log "halted by hold or blocked — nothing written (D15)"
    exit 0
fi

# --- idempotency against trusted markers only (D9, D23), read under the merge-actor token (D26) ---
COMMENTS="$(GH_TOKEN="$MERGE_ACTOR_TOKEN" gh api --paginate "repos/$R/issues/$ISSUE/comments?per_page=100" | jq -s 'add // []')" \
    || { log "escalate: cannot read the #$ISSUE thread — refused rather than duplicated (D9)"; exit 1; }
if jq -r --argjson t "$TRUSTED" '.[] | select((.user.login // "") as $l | $t | index($l) != null) | .body' <<<"$COMMENTS" \
   | grep -qF ":$REASON:$HEAD -->"; then
    log "escalation ($REASON, $HEAD) already recorded on #$ISSUE by a trusted writer — idempotent, nothing written"
    exit 0
fi

# --- the two writes ------------------------------------------------------------------
STATUS="$(grep '^status:' <<<"$ISSUE_LABELS" || true)"
n_status="$(grep -c . <<<"$STATUS" || true)"
if [ "$n_status" -gt 1 ]; then
    log "escalate: #$ISSUE carries more than one status:* label ($(tr '\n' ' ' <<<"$STATUS")) — corrupted state, nothing written"
    exit 1
fi
DISPLACED="$STATUS"
[ "$DISPLACED" != "status:review-stuck" ] || DISPLACED=""
MARKER="<!-- escalation:$DISPLACED:$REASON:$HEAD -->"

if [ -n "$DISPLACED" ]; then
    gh_write issue edit "$ISSUE" --add-label "status:review-stuck" --remove-label "$DISPLACED"
elif [ "$STATUS" != "status:review-stuck" ]; then
    gh_write issue edit "$ISSUE" --add-label "status:review-stuck"
fi

BODY_FILE="$(mktemp)"
printf 'Escalation: `%s` at head `%s`%s. The loop stops here until a human clears it (D9, D10).\n\n%s\n' \
    "$REASON" "$HEAD" "${PR:+ on #$PR}" "$MARKER" > "$BODY_FILE"
if [ "$DRY_RUN" = "1" ]; then
    log "DRY-RUN gh issue comment $ISSUE --body-file - <<'BODY'"
    sed 's/^/    | /' "$BODY_FILE" >&2
    log "BODY"
else
    GH_TOKEN="$MERGE_ACTOR_TOKEN" gh issue comment "$ISSUE" --body-file "$BODY_FILE" >/dev/null
fi
rm -f "$BODY_FILE"
log "escalated #$ISSUE: $REASON at $HEAD (displaced ${DISPLACED:-nothing})"
exit 0
