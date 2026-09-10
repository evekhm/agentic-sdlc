#!/usr/bin/env bash
# scripts/ci/merge_gate.sh <pull-request-number>
#
# The deterministic merge writer (#64, D3). It reads recorded state and
# evaluates D5's eleven conjuncts; a conjunct that cannot be evaluated
# is false. It writes at most one merge, one loop-ledger row and one
# escalation, each behind a fresh hold/blocked read (D15), and every
# path that declines exits 0. With loop.autonomous_merge false it
# evaluates, logs the verdict and writes nothing (D18).
#
# State-carrying comments count only from a trusted writer (D23): the
# merge actor App alone, resolved from the token in scope via `gh api
# user` and never guessed. A marker posted by any other login,
# `github-actions[bot]` included, is prose. Both threads are read to
# exhaustion; an unreadable thread declines, because unreadable is not
# absent (D13).
#
# Consensus-ledger machine block this gate reads. The ledger, its
# schema and the recorder that writes it belong to #8/#9; until the
# recorder lands nothing emits this block and conjuncts (3), (4), (5)
# and (11) are false, which is plan P1's fail-closed posture. The
# recorder must emit exactly these lines; the gate adds no field.
#   <!-- consensus-ledger:<pr> -->
#   <!-- assigned:argus,atlas -->
#   <!-- reviewed-head:argus:<full-oid> -->
#   <!-- reviewed-head:atlas:<full-oid> -->              absent = never reviewed
#   <!-- ledger-row:<id>:<severity>:<status>:<peer> -->   0..n
#   <!-- consensus-ledger-end -->
#   severity: security|high|normal|suggestion   status: open|fixed|withdrawn
#   peer: pending|agree|dispute|none
#
# Loop ledger (D13): ONE container comment per issue, appended in place,
# three row kinds and no other.
#   <!-- loop-ledger:<issue> -->
#   <!-- loop-ledger-row: dispatch rung:<n> head-oid:<oid> pr:<n> at:<iso> event:<id> cost:<usd> -->
#   <!-- loop-ledger-row: terminal rung:<n> head-oid:<oid> pr:<n> at:<iso> -->
#   <!-- loop-ledger-row: refusal:<reason> rung:<n> head-oid:<oid> pr:<n> at:<iso> -->
#   <!-- loop-ledger-end -->
# A dispatch or terminal row at rung n carries the merged head that
# opened rung n, so it records that rung n-1 merged (D14): the highest
# merged rung is the highest such rung minus one. dispatch and terminal
# rows are keyed (rung, head-oid); refusal rows (rung, head-oid,
# reason). The advancer writes dispatch and terminal rows; this gate
# writes refusal rows. Only dispatch rows count against the bounds.
set -euo pipefail

TARGET="${1:?usage: merge_gate.sh <pull-request-number>}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
R="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY must name <owner>/<repo>}"
LIFECYCLE_JSON="$REPO_ROOT/personas/lifecycle.json"
DRY_RUN="${DRY_RUN:-0}"
ATLAS_LOGIN="${ATLAS_LOGIN:-evekhm-atlas-app[bot]}"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

log() { printf '%s\n' "$*" >&2; }
finish() { log "verdict: $*"; exit 0; }
decline() { log "Decline: $*"; finish "no merge for #$TARGET"; }
norm_login() { sed -E 's#^app/##; s/\[bot\]$//' <<<"$1"; }

# --- the merge actor's own login (S3, D23, D30): read from the credential
# in scope through GraphQL `viewer { login }`, never guessed. `GET /user`
# answers 403 for an App installation token (scripts/ops/post.sh says
# why); `viewer` answers with the `<slug>[bot]` login a comment author
# carries. A failed read trusts nobody and declines. An answer of
# github-actions[bot] is the default token, which D23 never trusts — the
# `pull_request` evaluate job lands here on every run, green under D29.
VIEWER_QUERY='query { viewer { login } }'
if ! MERGE_ACTOR="$(gh api graphql -f query="$VIEWER_QUERY" 2>/dev/null | jq -r '.data.viewer.login // empty')" || [ -z "$MERGE_ACTOR" ]; then
    decline "cannot resolve the merge actor's login via GraphQL viewer — failing closed rather than trusting a guessed identity (S3, D30)"
fi
if [ "$MERGE_ACTOR" = "github-actions[bot]" ]; then
    decline "the token in scope is github-actions[bot], which D23 never trusts — this run does not hold the merge actor's credential (D30)"
fi
TRUSTED="$(jq -nc --arg a "$MERGE_ACTOR" '[$a]')"

# --- loop limits (D18, D20): unreadable is fail-closed --------------------------
read_limit() { python3 "$REPO_ROOT/scripts/ops/execution.py" --loop "$1" 2>/dev/null; }
if ! AUTONOMOUS="$(read_limit autonomous_merge)" \
   || ! MAX_DISPATCH="$(read_limit max_rung_dispatches_per_issue)" \
   || ! MAX_COST="$(read_limit max_cost_usd_per_issue)"; then
    decline "Failed to read loop limits. Failing closed."
fi
[ "$AUTONOMOUS" = "true" ] || AUTONOMOUS=false

# --- the pull request --------------------------------------------------------------
if ! PR_JSON="$(gh pr view "$TARGET" --json number,state,headRefName,headRefOid,headRepository,baseRefName,body,labels,author,closingIssuesReferences)"; then
    log "cannot read pull request #$TARGET"
    exit 1
fi
prq() { jq -r "$1" <<<"$PR_JSON"; }
PR="$(prq '.number')"
PR_STATE="$(prq '.state // "OPEN"')"
[ "$PR_STATE" = "OPEN" ] || finish "#$PR is $PR_STATE — nothing to evaluate"
HEAD="$(prq '.headRefOid // ""')"
PR_LABELS="$(prq '[.labels[]?.name] | .[]')"

# --- which issue this pull request belongs to (#245) -------------------------------
# GitHub's own closing references first, then every closing keyword and
# `refs` case-insensitively in the body, then the <actor>/<n>-<slug>
# branch. Two different issues is corrupted input; none is a pull
# request outside the ladder, a distinguishable outcome and no failure.
BODY_REFS="$(prq '.body // ""' | grep -Eoi '(^|[^[:alnum:]])(refs?|references?|close[sd]?|fix(es|ed)?|resolve[sd]?)[[:space:]]+#[0-9]+' | grep -Eo '[0-9]+$' || true)"
CLOSING_REFS="$(prq '[.closingIssuesReferences[]?.number] | .[]' 2>/dev/null || true)"
HEAD_REF="$(prq '.headRefName // ""')"
BRANCH_REFS=""
if [[ "$HEAD_REF" =~ ^[a-z][a-z-]*/([0-9]+)- ]]; then
    BRANCH_REFS="${BASH_REMATCH[1]}"
fi
LINKED="$(printf '%s\n%s\n%s\n' "$CLOSING_REFS" "$BODY_REFS" "$BRANCH_REFS" | grep -E '^[0-9]+$' | sort -un || true)"
n_linked="$(grep -c . <<<"$LINKED" || true)"
if [ "$n_linked" -gt 1 ]; then
    decline "#$PR links two different issues ($(tr '\n' ' ' <<<"$LINKED"| sed 's/ $//' | sed 's/\([0-9][0-9]*\)/#\1/g')) — corrupted input, nothing written"
fi
if [ "$n_linked" -eq 0 ]; then
    finish "no linked issue on #$PR (no closing reference, no \`Refs #n\`, no <actor>/<n>-<slug> branch) — not a ladder pull request; nothing evaluated, nothing written"
fi
ISSUE="$LINKED"

# --- hold / blocked (D15, conjunct 6): checked before anything is written ---------
labels_of() { # issue|pr <number>
    if [ "$1" = issue ]; then gh issue view "$2" --json labels | jq -r '.labels[]?.name'
    else gh pr view "$2" --json labels | jq -r '.labels[]?.name'; fi
}
halted_by_hold() { # returns 0 when hold/blocked is present or the labels cannot be read
    local il pl
    il="$(labels_of issue "$ISSUE")" || return 0
    pl="$(labels_of pr "$PR")" || return 0
    printf '%s\n%s\n' "$il" "$pl" | grep -qxE 'hold|blocked'
}
if ! ISSUE_LABELS="$(labels_of issue "$ISSUE")"; then
    decline "cannot read #$ISSUE — nothing evaluated"
fi
if printf '%s\n%s\n' "$ISSUE_LABELS" "$PR_LABELS" | grep -qxE 'hold|blocked'; then
    finish "halted by hold or blocked on #$PR or #$ISSUE — nothing written (D15)"
fi

# --- both threads, to exhaustion, with authors (D13, D22) -------------------------
read_comments() { gh api --paginate "repos/$R/issues/$1/comments?per_page=100" | jq -s 'add // []'; }
trusted_only() { jq -c --argjson t "$TRUSTED" '[.[] | select((.user.login // "") as $l | $t | index($l) != null)]' <<<"$1"; }
if ! ISSUE_COMMENTS="$(read_comments "$ISSUE")"; then
    decline "the #$ISSUE thread is unreadable — unreadable is not absent (D13)"
fi
if ! PR_COMMENTS="$(read_comments "$PR")"; then
    decline "the #$PR thread is unreadable — unreadable is not absent (D13)"
fi
ISSUE_TRUSTED="$(trusted_only "$ISSUE_COMMENTS")"
PR_TRUSTED="$(trusted_only "$PR_COMMENTS")"

# --- the loop ledger (D13) ---------------------------------------------------------
LEDGER_MARK="<!-- loop-ledger:$ISSUE -->"
LEDGER_ID="$(jq -r --arg m "$LEDGER_MARK" '[.[] | select(.body | contains($m))] | sort_by(.id) | .[0].id // empty' <<<"$ISSUE_TRUSTED")"
LEDGER_BODY=""
[ -z "$LEDGER_ID" ] || LEDGER_BODY="$(jq -r --argjson i "$LEDGER_ID" '.[] | select(.id == $i) | .body' <<<"$ISSUE_TRUSTED")"
ROWS="$(grep -oE '<!-- loop-ledger-row: [^>]*-->' <<<"$LEDGER_BODY" || true)"
n_rows_any="$(grep -c 'loop-ledger-row:' <<<"$LEDGER_BODY" || true)"
n_rows_ok="$(grep -cE '^<!-- loop-ledger-row: (dispatch|terminal|refusal:[a-z-]+) rung:[0-9]+ head-oid:[0-9a-f]{40}( [a-z-]+:[^ ]+)* -->$' <<<"$ROWS" || true)"
if [ "$n_rows_any" != "$n_rows_ok" ]; then
    decline "the loop ledger on #$ISSUE has a row this gate cannot parse — unreadable is not absent (D13)"
fi
rows_of() { grep -E "^<!-- loop-ledger-row: $1 " <<<"$ROWS" || true; }
DISPATCH_COUNT="$(rows_of dispatch | grep -c . || true)"
n_costs="$(rows_of dispatch | grep -cE ' cost:[0-9]+(\.[0-9]+)? ' || true)"
if [ "$DISPATCH_COUNT" != "$n_costs" ]; then
    decline "a dispatch row on #$ISSUE carries no cost — the ledger is the only source of spend (D13)"
fi
SUMMED_COST="$(rows_of dispatch | sed -nE 's/.* cost:([0-9.]+) .*/\1/p' | awk '{s += $1} END {printf "%.2f", s}')"
HIGHEST_ENTERED="$(rows_of '(dispatch|terminal)' | sed -nE 's/.* rung:([0-9]+) .*/\1/p' | sort -n | tail -1)"
HIGHEST_MERGED_RANK=0
[ -z "$HIGHEST_ENTERED" ] || HIGHEST_MERGED_RANK=$((HIGHEST_ENTERED - 1))

# --- writers ------------------------------------------------------------------------
# Every write is preceded by a fresh hold/blocked read (D15) and skipped
# entirely under DRY_RUN=1.
ledger_append() { # <kind> <rung>  (head-oid is the evaluated head; pr and at are added)
    local kind="$1" rung="$2"
    local row="<!-- loop-ledger-row: $kind rung:$rung head-oid:$HEAD pr:$PR at:$NOW -->"
    local key="<!-- loop-ledger-row: $kind rung:$rung head-oid:$HEAD "
    local line="- \`$kind\` · rung $rung · head \`${HEAD:0:12}\` · #$PR · $NOW $row"
    if grep -qF "$key" <<<"$LEDGER_BODY"; then
        log "loop ledger already carries ($kind, rung $rung, ${HEAD:0:12}) — no write"
        return 0
    fi
    if [ "$DRY_RUN" = "1" ]; then log "DRY-RUN loop-ledger append on #$ISSUE: $row"; return 0; fi
    if halted_by_hold; then finish "halted by hold or blocked before the ledger write — nothing written (D15)"; fi
    local f; f="$(mktemp)"
    if [ -n "$LEDGER_ID" ]; then
        awk -v l="$line" '/<!-- loop-ledger-end -->/ {print l} {print}' <<<"$LEDGER_BODY" > "$f"
        gh api -X PATCH "repos/$R/issues/comments/$LEDGER_ID" -F body=@"$f" >/dev/null
    else
        printf '### Loop ledger for #%s\n\n%s\n%s\n<!-- loop-ledger-end -->\n' "$ISSUE" "$LEDGER_MARK" "$line" > "$f"
        gh api -X POST "repos/$R/issues/$ISSUE/comments" -F body=@"$f" >/dev/null
    fi
    rm -f "$f"
    log "loop ledger on #$ISSUE: appended $kind row for rung $rung at ${HEAD:0:12}"
}
escalate() { # <reason-code>
    log "escalating $1 on #$ISSUE at head $HEAD"
    bash "$REPO_ROOT/scripts/ci/escalate.sh" "$ISSUE" --reason "$1" --head "$HEAD" --pr "$PR"
}
gh_write() { if [ "$DRY_RUN" = "1" ]; then log "DRY-RUN gh $*"; else gh "$@" >/dev/null; fi; }

# --- bounds (conjunct 8, D11): a breach is a refusal row plus one escalation ------
over_budget=""
if [ "$DISPATCH_COUNT" -ge "$MAX_DISPATCH" ]; then
    over_budget="max_rung_dispatches_per_issue exceeded ($DISPATCH_COUNT/$MAX_DISPATCH)"
elif ! awk -v s="$SUMMED_COST" -v m="$MAX_COST" 'BEGIN { exit !(s + 0 < m + 0) }'; then
    over_budget="max_cost_usd_per_issue exceeded ($SUMMED_COST/$MAX_COST)"
fi

# --- the rung (conjuncts 9, 10) and the escalation state it may be hiding (D10) ----
STATUS="$(grep '^status:' <<<"$ISSUE_LABELS" || true)"
n_status="$(grep -c . <<<"$STATUS" || true)"
[ "$n_status" -le 1 ] || decline "#$ISSUE carries more than one status:* label ($(tr '\n' ' ' <<<"$STATUS")) — corrupted state, nothing written"
rung_of() { jq -r --arg l "$1" '[.stages[].label] | index($l)' "$LIFECYCLE_JSON"; }

# The bound is not under the flag (D18): the refusal row is written in
# both settings; the escalation is an unattended act and waits on it.
if [ -n "$over_budget" ]; then
    log "Decline: $over_budget"
    idx="$(rung_of "$STATUS")"
    if [ -z "$STATUS" ] && grep -Fxq "intent:new" <<<"$ISSUE_LABELS"; then
        idx=0
    fi
    [ "$idx" != "null" ] && rung=$((idx + 1)) || rung=0
    ledger_append "refusal:budget" "$rung"
    if [ "$AUTONOMOUS" = "true" ]; then escalate budget
    else log "autonomous_merge is false — refusal recorded, no escalation (D18)"; fi
    finish "no merge for #$TARGET"
fi

# --- conjunct 2's state (D24): read once, used here for D10 and again below ------
# `mergeStateStatus` and the check roll-up with each check run's owning
# workflow-run id (`gh pr view --json statusCheckRollup` exposes neither
# the merge state nor that id) come from one GraphQL read. GitHub
# computes `mergeStateStatus` lazily: a read immediately after a push
# often returns UNKNOWN and a read seconds later returns the verdict, so
# UNKNOWN is re-read up to three more times before it is treated as
# unevaluable. Read once here — before D10, which needs it for a
# `behind` marker — and reused at conjunct (2) below without a second
# GraphQL call.
GRAPHQL_ROLLUP='query($owner:String!,$repo:String!,$pr:Int!){repository(owner:$owner,name:$repo){pullRequest(number:$pr){mergeStateStatus commits(last:1){nodes{commit{statusCheckRollup{contexts(first:100){nodes{__typename ... on CheckRun{name conclusion status databaseId checkSuite{workflowRun{databaseId}}} ... on StatusContext{context state}}}}}}}}}}'
read_merge_state() { # sets MERGE_STATE, CHECKS_TSV (name<TAB>state<TAB>run-id<TAB>db-id); returns 1 unreadable
    local owner="${R%%/*}" repo="${R#*/}" out
    out="$(gh api graphql -f query="$GRAPHQL_ROLLUP" -F owner="$owner" -F repo="$repo" -F pr="$PR" 2>/dev/null)" || return 1
    jq -e '.data.repository.pullRequest != null' <<<"$out" >/dev/null 2>&1 || return 1
    MERGE_STATE="$(jq -r '.data.repository.pullRequest.mergeStateStatus // "UNKNOWN"' <<<"$out")"
    CHECKS_TSV="$(jq -r '.data.repository.pullRequest.commits.nodes[0].commit.statusCheckRollup.contexts.nodes[]? |
        if .__typename == "CheckRun" then [(.name // "?"), ((.conclusion // .status) // ""), ((.checkSuite.workflowRun.databaseId) // ""), ((.databaseId) // "")]
        else [(.context // "?"), (.state // ""), "", ""] end | @tsv' <<<"$out")"
    return 0
}
MERGE_STATE_RETRY_SLEEP="${MERGE_STATE_RETRY_SLEEP:-2}"
merge_state_attempt=0; MERGE_STATE_READ_OK=1; MERGE_STATE="UNKNOWN"; CHECKS_TSV=""
while :; do
    if read_merge_state; then MERGE_STATE_READ_OK=1; else MERGE_STATE_READ_OK=0; fi
    [ "$MERGE_STATE_READ_OK" = 1 ] && [ "$MERGE_STATE" != "UNKNOWN" ] && break
    [ "$merge_state_attempt" -ge 3 ] && break
    merge_state_attempt=$((merge_state_attempt + 1))
    [ "$MERGE_STATE_RETRY_SLEEP" = 0 ] || sleep "$MERGE_STATE_RETRY_SLEEP"
done

# --- consensus (conjuncts 3, 4, 5, 11) from the ledger on the pull request ---------
declare -A C WHY
for i in 1 2 3 4 5 6 7 8 9 10 11; do C[$i]=0; WHY[$i]=""; done
C[6]=1; WHY[6]="neither hold nor blocked on #$PR or #$ISSUE"
C[8]=1; WHY[8]="$DISPATCH_COUNT/$MAX_DISPATCH dispatches, \$$SUMMED_COST/\$$MAX_COST"

CL_MARK="<!-- consensus-ledger:$PR -->"
CL_BODY="$(jq -r --arg m "$CL_MARK" '[.[] | select(.body | contains($m))] | sort_by(.id) | .[0].body // empty' <<<"$PR_TRUSTED")"
BLOCKING=""; DISPUTED=""; PENDING_SEC=""; ARGUS_HEAD=""; ATLAS_HEAD=""; AT_OPEN=""
if [ -z "$CL_BODY" ]; then
    for i in 3 4 5 11; do WHY[$i]="no consensus ledger for #$PR from a trusted writer"; done
else
    CL="$(awk -v m="$CL_MARK" '$0 == m {f = 1} f {print} /<!-- consensus-ledger-end -->/ {f = 0}' <<<"$CL_BODY")"
    ARGUS_HEAD="$(sed -nE 's/^<!-- reviewed-head:argus:([0-9a-f]{40}) -->$/\1/p' <<<"$CL" | tail -1)"
    ATLAS_HEAD="$(sed -nE 's/^<!-- reviewed-head:atlas:([0-9a-f]{40}) -->$/\1/p' <<<"$CL" | tail -1)"
    n_cl_any="$(grep -c 'ledger-row:' <<<"$CL" || true)"
    CTUP="$(sed -nE 's/^<!-- ledger-row:([A-Za-z0-9@-]+:(security|high|normal|suggestion):(open|fixed|withdrawn):(pending|agree|dispute|none)) -->$/\1/p' <<<"$CL")"
    n_cl_ok="$(grep -c . <<<"$CTUP" || true)"
    if [ "$n_cl_any" != "$n_cl_ok" ]; then
        for i in 3 4 5 11; do WHY[$i]="the consensus ledger has a row this gate cannot parse"; done
    else
        BLOCKING="$(awk -F: '(($2 == "security" || $2 == "high") && $3 == "open") || ($2 == "security" && $3 == "fixed" && $4 != "agree") {print $1}' <<<"$CTUP")"
        DISPUTED="$(awk -F: '$4 == "dispute" {print $1}' <<<"$CTUP")"
        PENDING_SEC="$(awk -F: '$2 == "security" && $4 == "pending" {print $1}' <<<"$CTUP")"
        AT_OPEN="$(awk -F: '$1 ~ /^AT-/ && $3 == "open" {print $1}' <<<"$CTUP")"
        if [ -n "$ARGUS_HEAD" ]; then C[11]=1; WHY[11]="ledger carries reviewed-head:argus and the head probe read $HEAD"
        else WHY[11]="the ledger carries no reviewed-head marker"; fi
        if [ -z "$BLOCKING" ]; then C[4]=1; WHY[4]="blocking set empty"
        else WHY[4]="blocking set: $(tr '\n' ' ' <<<"$BLOCKING")"; fi
        if [ -n "$DISPUTED" ]; then WHY[5]="dispute on: $(tr '\n' ' ' <<<"$DISPUTED")"
        elif [ -n "$PENDING_SEC" ]; then WHY[5]="consensus axis pending on: $(tr '\n' ' ' <<<"$PENDING_SEC")"
        else C[5]=1; WHY[5]="consensus axis agreed, no dispute"; fi
        if [ "$ARGUS_HEAD" != "$HEAD" ]; then
            WHY[3]="argus verdict is at ${ARGUS_HEAD:-none}, head is $HEAD"
        elif [ "$ATLAS_HEAD" = "$HEAD" ]; then
            C[3]=1; WHY[3]="argus and atlas both recorded at $HEAD"
        elif [ -z "$ATLAS_HEAD" ]; then
            WHY[3]="atlas has no verdict on record (D7 (i))"
        else
            # Atlas carry-forward (D7): (i) a verdict exists, (ii) no AT-* row
            # open, (iii) no security row open or fixed without both AGREEs,
            # (iv) no dispute and no human mention naming Atlas after its
            # last comment, (v) no unconsumed deep-review grant.
            ATLAS_LAST="$(jq -r --arg a "$ATLAS_LOGIN" '[.[] | select(.user.login == $a)] | sort_by(.created_at) | last | .created_at // ""' <<<"$PR_COMMENTS")"
            MENTIONS="$(jq -r --arg t "$ATLAS_LAST" '[.[] | select((.user.type // "") != "Bot") | select(.created_at > $t) | select(.body | test("atlas"; "i"))] | length' <<<"$PR_COMMENTS")"
            if [ -n "$AT_OPEN" ]; then WHY[3]="atlas cannot carry forward: AT row open ($(tr '\n' ' ' <<<"$AT_OPEN")) (D7 (ii))"
            elif [ -n "$BLOCKING" ] && awk -F: '$2 == "security" {found = 1} END {exit !found}' <<<"$CTUP"; then WHY[3]="atlas cannot carry forward: a security row is open or unconfirmed (D7 (iii))"
            elif [ -n "$DISPUTED" ]; then WHY[3]="atlas cannot carry forward: dispute (D7 (iv))"
            elif [ "$MENTIONS" != "0" ]; then WHY[3]="atlas cannot carry forward: a human mention naming atlas is outstanding since its last comment (D7 (iv))"
            elif grep -qx 'deep-review' <<<"$PR_LABELS"; then WHY[3]="atlas cannot carry forward: deep-review grant unconsumed (D7 (v))"
            else C[3]=1; WHY[3]="argus at $HEAD, atlas carries forward from $ATLAS_HEAD (D7)"; fi
        fi
    fi
fi
CONSENSUS_OK=0
[ "${C[3]}" = 1 ] && [ "${C[4]}" = 1 ] && [ "${C[5]}" = 1 ] && CONSENSUS_OK=1

# --- D10: an escalated issue may clear itself ----------------------------------------
RESTORE=""
if [ "$STATUS" = "status:review-stuck" ]; then
    MARKERS="$(jq -r '.[].body' <<<"$ISSUE_TRUSTED" | grep -oE '<!-- escalation:[^ ]*:[a-z-]+:[0-9a-f]{40} -->' || true)"
    [ -n "$MARKERS" ] || decline "#$ISSUE is status:review-stuck with no escalation marker from a trusted writer — a hand-applied escalation clears only by hand (D10)"
    live=""; first_displaced=""
    while IFS= read -r m; do
        [[ "$m" =~ ^\<!--\ escalation:(.*):([a-z-]+):([0-9a-f]{40})\ --\>$ ]] || continue
        displaced="${BASH_REMATCH[1]}"; reason="${BASH_REMATCH[2]}"; moid="${BASH_REMATCH[3]}"
        [ -n "$first_displaced" ] || first_displaced="$displaced"
        case "$reason" in
            budget|non-monotonic) live="$reason";;
            behind) # D28: clears on the head's OWN mergeStateStatus, never on
                    # head-oid equality — the head that is no longer behind is
                    # by construction a different one.
                    if [ "$MERGE_STATE_READ_OK" != 1 ] || [ "$MERGE_STATE" = "BEHIND" ] || [ "$MERGE_STATE" = "UNKNOWN" ]; then live="$reason"; fi;;
            *) if [ "$moid" = "$HEAD" ] || [ "$CONSENSUS_OK" != 1 ]; then live="$reason"; fi;;
        esac
    done <<<"$MARKERS"
    [ -z "$live" ] || decline "escalation $live on #$ISSUE is still live (D10) — no restore, no merge"
    [ -n "$first_displaced" ] || decline "no escalation marker on #$ISSUE records a displaced label (D10)"
    STATUS="$first_displaced"
    RESTORE=1
    log "D10: every escalation on #$ISSUE has cleared; $STATUS is the label to restore"
fi

# --- conjuncts 9 and 10 ---------------------------------------------------------------
RUNG=0; ARTIFACT=""
idx="$(rung_of "$STATUS")"
if [ -z "$STATUS" ] && grep -Fxq "intent:new" <<<"$ISSUE_LABELS"; then
    idx=0
fi
if [ -z "$STATUS" ] && ! grep -Fxq "intent:new" <<<"$ISSUE_LABELS" || [ "$idx" = "null" ]; then
    WHY[9]="#$ISSUE carries no ranked status label (${STATUS:-none})"; WHY[10]="${WHY[9]}"
else
    RUNG=$((idx + 1))
    ARTIFACT="$(jq -r ".stages[$idx].artifact // empty" "$LIFECYCLE_JSON")"
    if [ "$RUNG" -gt "$HIGHEST_MERGED_RANK" ]; then C[10]=1; WHY[10]="rung $RUNG > highest merged rung $HIGHEST_MERGED_RANK"
    else WHY[10]="rung $RUNG is not above highest merged rung $HIGHEST_MERGED_RANK (D14)"; fi
    if [ -z "$ARTIFACT" ]; then
        C[9]=1; WHY[9]="$STATUS owes no artifact"
    elif ! dirs="$(gh api "repos/$R/contents/intent?ref=$HEAD" 2>/dev/null | jq -r --arg p "$ISSUE-" '.[] | select(.type == "dir" and (.name | startswith($p))) | .name')"; then
        WHY[9]="intent/ is unreadable at $HEAD"
    elif [ "$(grep -c . <<<"$dirs" || true)" -ne 1 ]; then
        WHY[9]="expected exactly one intent/$ISSUE-*/ folder at $HEAD, found: $(tr '\n' ' ' <<<"${dirs:-none}")"
    elif ! content="$(gh api "repos/$R/contents/intent/$dirs/$ARTIFACT?ref=$HEAD" 2>/dev/null | jq -r '.content // empty' | base64 -d 2>/dev/null)" || [ -z "$content" ]; then
        WHY[9]="intent/$dirs/$ARTIFACT is absent at $HEAD"
    elif [ "$ARTIFACT" = "spec.md" ]; then
        if ! grep -Eq '(^|[^[:alnum:]_])\*{0,2}Status:\*{0,2}[[:space:]]+Approved([^[:alnum:]_]|$)' <<<"$content"; then
            WHY[9]="intent/$dirs/spec.md is not Status: Approved"
        elif ! grep -Eqi '\*{0,2}Open questions:\*{0,2}[[:space:]]+none' <<<"$content"; then
            WHY[9]="intent/$dirs/spec.md has open questions"
        else C[9]=1; WHY[9]="intent/$dirs/spec.md is Approved with no open questions"; fi
    else
        C[9]=1; WHY[9]="intent/$dirs/$ARTIFACT present at $HEAD"
    fi
fi

# --- conjunct 1 ------------------------------------------------------------------------
DEFAULT_BRANCH="$(gh api "repos/$R" 2>/dev/null | jq -r '.default_branch // empty' || true)"
BASE="$(prq '.baseRefName // ""')"
HEADREPO="$(prq '.headRepository.nameWithOwner // ""')"
if [ -z "$DEFAULT_BRANCH" ]; then WHY[1]="default branch unreadable"
elif [ "$BASE" != "$DEFAULT_BRANCH" ]; then WHY[1]="base is $BASE, default branch is $DEFAULT_BRANCH"
elif [ "$HEADREPO" != "$R" ]; then WHY[1]="head repository is ${HEADREPO:-unknown}, this repository is $R"
else C[1]=1; WHY[1]="base $BASE, head in $R"; fi

# --- conjunct 7 ------------------------------------------------------------------------
AUTHOR="$(prq '.author.login // ""')"
if [ -z "$AUTHOR" ]; then WHY[7]="author unreadable"
elif [ "$(norm_login "$AUTHOR")" = "$(norm_login "$MERGE_ACTOR")" ]; then WHY[7]="author $AUTHOR is the merging identity"
else C[7]=1; WHY[7]="author $AUTHOR, merger $MERGE_ACTOR"; fi

# --- conjunct 2 (D24): GitHub's own merge-state verdict, never branch protection ---
# `mergeStateStatus` and the check roll-up were already read above (with
# the bounded UNKNOWN re-read) because D10's `behind` clearing needs the
# same values; nothing here issues a second GraphQL call. The gate's own
# run is excluded by IDENTITY — the one roll-up entry whose
# `checkSuite.workflowRun.databaseId` equals this job's `GITHUB_RUN_ID`
# — never by name, so a foreign job named `merge-gate` still counts.
if [ "$MERGE_STATE_READ_OK" != 1 ]; then
    WHY[2]="the merge-state/check roll-up is unreadable — unevaluable (D24)"
    ledger_append "refusal:unknown" "$RUNG"
elif [ "$MERGE_STATE" = "UNKNOWN" ]; then
    WHY[2]="mergeStateStatus is still UNKNOWN after $merge_state_attempt re-read(s) — unevaluable (D24)"
    ledger_append "refusal:unknown" "$RUNG"
elif [ "$MERGE_STATE" = "BLOCKED" ] || [ "$MERGE_STATE" = "DIRTY" ] || [ "$MERGE_STATE" = "DRAFT" ] || [ "$MERGE_STATE" = "HAS_HOOKS" ]; then
    WHY[2]="mergeStateStatus is $MERGE_STATE"
elif [ "$MERGE_STATE" = "BEHIND" ]; then
    WHY[2]="mergeStateStatus is BEHIND"
    ledger_append "refusal:behind" "$RUNG"
    if [ "$AUTONOMOUS" = "true" ]; then escalate behind
    else log "autonomous_merge is false — behind recorded, no escalation (D27)"; fi
elif [ "$MERGE_STATE" = "CLEAN" ] || [ "$MERGE_STATE" = "UNSTABLE" ]; then
    RUN_ID="${GITHUB_RUN_ID:-}"
    eval_res="$(awk -F'\t' -v own_id="$RUN_ID" '
        {
            name = $1; st = $2; run_id = $3; db_id = $4
            if (own_id != "" && run_id == own_id) next
            if (!seen[name]) { seen[name] = 1; names[++total] = name }
            if (db_id != "") {
                if (!has_dbid[name] || (db_id + 0 > max_dbid[name] + 0)) {
                    has_dbid[name] = 1; max_dbid[name] = db_id + 0; state[name] = st
                }
            } else {
                if (!has_dbid[name]) state[name] = st
            }
        }
        END {
            failing = ""
            for (i = 1; i <= total; i++) {
                n = names[i]; s = state[n]; val = (s == "" ? "PENDING" : toupper(s))
                if (val != "SUCCESS" && val != "NEUTRAL") failing = failing " " n "=" val
            }
            printf "%d\t%s\n", total, failing
        }' <<<"$CHECKS_TSV")"
    n_other="${eval_res%%$'\t'*}"
    failing="${eval_res#*$'\t'}"
    if [ "$n_other" -eq 0 ]; then
        WHY[2]="mergeStateStatus $MERGE_STATE but no check besides the gate's own run"
    elif [ -n "$failing" ]; then
        WHY[2]="mergeStateStatus $MERGE_STATE but check(s) not success:$failing"
    else
        C[2]=1; WHY[2]="mergeStateStatus $MERGE_STATE, all $n_other other check(s) success"
    fi
else
    WHY[2]="unrecognised mergeStateStatus '$MERGE_STATE' — unevaluable"
fi

# --- verdict ---------------------------------------------------------------------------
ALL=1; FALSE=""
for i in 1 2 3 4 5 6 7 8 9 10 11; do
    if [ "${C[$i]}" = 1 ]; then log "conjunct ($i): true — ${WHY[$i]}"
    else log "conjunct ($i): false — ${WHY[$i]}"; ALL=0; FALSE="$FALSE ($i)"; fi
done

if [ "$ALL" = 1 ]; then
    if [ "$AUTONOMOUS" != "true" ]; then
        finish "all eleven conjuncts hold for #$PR at $HEAD; autonomous_merge is false — nothing written (D18)"
    fi
    if [ -n "$RESTORE" ]; then
        if halted_by_hold; then finish "halted by hold or blocked before the D10 restore — nothing written (D15)"; fi
        gh_write issue edit "$ISSUE" --add-label "$STATUS" --remove-label "status:review-stuck"
        log "D10: restored $STATUS on #$ISSUE"
    fi
    if halted_by_hold; then finish "halted by hold or blocked before the merge — nothing written (D15)"; fi
    gh_write pr merge "$PR" --merge --match-head-commit "$HEAD"
    finish "merged #$PR at $HEAD"
fi

# At the round cap (review:3 on the pull request) an unresolved ledger is
# an escalation, in D9's precedence: security-open, dispute-at-cap,
# blocking-open-at-cap. Below the cap the funnel is still running.
if [ "$AUTONOMOUS" = "true" ] && grep -qx 'review:3' <<<"$PR_LABELS" && [ -n "$CL_BODY" ]; then
    reason=""
    if awk -F: '$2 == "security" && $3 == "open" {found = 1} END {exit !found}' <<<"${CTUP:-}"; then reason="security-open"
    elif [ -n "$DISPUTED" ]; then reason="dispute-at-cap"
    elif [ -n "$BLOCKING" ]; then reason="blocking-open-at-cap"; fi
    if [ -n "$reason" ]; then
        ledger_append "refusal:$reason" "$RUNG"
        escalate "$reason"
    fi
fi
decline "conjunct(s)$FALSE false for #$PR at $HEAD"
