#!/usr/bin/env bash
# Live board: who owns what, at which stage, right now.
#
#   scripts/ops/board.sh                 # every issue in flight, once
#   scripts/ops/board.sh --watch [sec]   # redraw every 60s (or sec)
#   scripts/ops/board.sh --all           # include unclaimed intake too
#   scripts/ops/board.sh 57 43           # only these issues
#
# AGENTS.md is deliberate that there is no STATUS.md: state lives in the
# labels, the claim comments, the pull requests and the branches, and a
# committed status file would be stale the moment two sessions run in
# parallel. That rule is right and it has a cost — nobody can answer
# "who is working on what, and how far along is it?" by looking at the
# repository, because the answer is spread over five sources that
# nothing joins:
#
#   issue labels          the stage (one status:*), the claim mutex
#                         (in-progress), the breakers (hold/blocked),
#                         the review round (review:N)
#   claim comments        WHO holds the mutex — the author of the last
#                         comment opening with `Claim`, mapped through
#                         personas/*.yaml identities, exactly as
#                         work.sh does before dispatch
#   open pull requests    the artifact each stage produced, what it is
#                         stacked on, its checks and its reviewers
#   remote branches       which actors have touched the issue at all
#   local worktrees and   which of those branches has a checkout on
#   live processes        this machine, and whether a harness process
#                         is sitting in it right now
#
# This script joins them and prints the join. It is the read-only
# complement of work.sh: same inputs (gh + jq + git + the three
# committed data files), same identity table, no model call, and IT
# NEVER WRITES TO GITHUB. What it prints is a view; the labels stay the
# state machine.
#
# Exit codes: 0 printed; 1 unusable input or an unreadable repository.

set -euo pipefail

GITHUB_REPO="${GITHUB_REPO:-${GITHUB_REPOSITORY:-evekhm/agentic-sdlc}}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIFECYCLE_JSON="$REPO_ROOT/personas/lifecycle.json"
PERSONA_DIR="$REPO_ROOT/personas"
STALE_HOURS="${BOARD_STALE_HOURS:-6}"
DEFAULT_BRANCH="${BOARD_DEFAULT_BRANCH:-main}"

WATCH=""
ALL=0
NO_FETCH=0
ONLY=()

usage() {
    sed -n '2,8p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --watch)
            WATCH=60
            if [ $# -gt 1 ] && [[ "$2" =~ ^[0-9]+$ ]]; then WATCH="$2"; shift; fi ;;
        --all) ALL=1 ;;
        --no-fetch) NO_FETCH=1 ;;
        -h|--help) usage 0 ;;
        *)
            [[ "$1" =~ ^#?[0-9]+$ ]] || { echo "board.sh: not an issue number: $1" >&2; usage 1; }
            ONLY+=("${1#\#}") ;;
    esac
    shift
done

for tool in gh jq git; do
    command -v "$tool" >/dev/null 2>&1 || { echo "board.sh: $tool is required" >&2; exit 1; }
done

# ---------------------------------------------------------------- helpers
ndie() { echo "board.sh: $1" >&2; exit 1; }

NOW="$(date -u +%s)"

ago() { # <iso8601 | epoch> -> "22m" / "3h" / "2d"
    local t d
    [ -n "${1:-}" ] || { printf '?'; return; }
    if [[ "$1" =~ ^[0-9]+$ ]]; then t="$1"; else t="$(date -u -d "$1" +%s 2>/dev/null || echo "$NOW")"; fi
    d=$(( NOW - t ))
    if   [ "$d" -lt 3600 ];  then printf '%dm' $(( d / 60 ))
    elif [ "$d" -lt 86400 ]; then printf '%dh' $(( d / 3600 ))
    else                          printf '%dd' $(( d / 86400 )); fi
}

if [ -t 1 ]; then
    B=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; YEL=$'\033[33m'; GRN=$'\033[32m'; CYN=$'\033[36m'; R=$'\033[0m'
else
    B=""; DIM=""; RED=""; YEL=""; GRN=""; CYN=""; R=""
fi

. "$REPO_ROOT/scripts/ops/lib/github.sh"

# Identity table — the same lookup work.sh performs, so the board and
# the dispatcher never disagree about who a login is.
persona_for_login() { # <login> -> persona name, or empty
    local login="$1" file id
    for file in "$PERSONA_DIR"/*.yaml; do
        [ -f "$file" ] || continue
        id="$(sed -n 's/^[[:space:]]*identity:[[:space:]]*"\(.*\)".*/\1/p' "$file" | head -1)"
        if [ -n "$id" ] && [ "$id" = "$login" ]; then
            basename "$file" .yaml
            return 0
        fi
    done
    return 0
}

# A comment the operator bot posts "on behalf of <persona>" (#47: some
# App identities cannot write to issues yet) is attributed to that
# persona, marked, so the board tells the truth about who acted.
actor_of() { # <login> <body-head> -> "persona" | "persona (via operator)" | login
    local login="$1" head="$2" p via
    # `gh pr list` spells an App author "app/<slug>"; the issues API and
    # the identity table spell the same actor "<slug>[bot]".
    case "$login" in app/*) login="${login#app/}[bot]" ;; esac
    p="$(persona_for_login "$login")"
    if [ -n "$p" ]; then printf '%s' "$p"; return; fi
    via="$(sed -n 's/.*[Oo]n behalf of \([A-Za-z]*\).*/\1/p' <<<"$head" | head -1 | tr '[:upper:]' '[:lower:]')"
    if [ -n "$via" ]; then printf '%s (via %s)' "$via" "$login"; return; fi
    printf '%s' "$login"
}

owners_of() { # <stage> -> persona names, one per line
    local stage="$1" file
    for file in "$PERSONA_DIR"/*.yaml; do
        [ -f "$file" ] || continue
        grep -q '^kind:[[:space:]]*persona' "$file" || continue
        sed -n 's/^stage:[[:space:]]*\[\(.*\)\].*/\1/p' "$file" | tr ',' '\n' | tr -d ' ' \
            | grep -Fxq "$stage" && basename "$file" .yaml
    done | sort -u
}

stage_row() { # <label> -> json row from lifecycle.json, or empty
    jq -c --arg l "$1" '(.stages // .) | if type=="array" then .[] else to_entries[].value end | select(.label==$l)' "$LIFECYCLE_JSON" 2>/dev/null | head -1
}

# ---------------------------------------------------------------- gather

gather() {
    [ "$NO_FETCH" = 1 ] || git -C "$REPO_ROOT" fetch -q origin 2>/dev/null || true

    ISSUES_JSON="$(gh_json "repos/$GITHUB_REPO/issues?state=open" --paginate \
        | jq 'map(select(.pull_request|not))')" \
        || { echo "board.sh: cannot read issues of $GITHUB_REPO (GH_TOKEN?)" >&2; exit 1; }

    PRS_JSON="$(gh pr list --repo "$GITHUB_REPO" --state open --limit 100 \
        --json number,title,body,headRefName,baseRefName,isDraft,author,reviews,statusCheckRollup,updatedAt,mergeable 2>/dev/null)" \
        || PRS_JSON="[]"

    BRANCHES="$(git -C "$REPO_ROOT" for-each-ref --format='%(refname:short) %(committerdate:unix)' refs/remotes/origin \
        | sed 's#^origin/##' | grep -v '^HEAD ' || true)"

    # path<TAB>branch, one per worktree (porcelain: path first, then branch)
    WORKTREES="$(git -C "$REPO_ROOT" worktree list --porcelain \
        | awk '/^worktree /{p=substr($0,10)} /^branch /{b=substr($0,8); sub("^refs/heads/","",b); print p "\t" b; p=""} /^detached/{print p "\t(detached)"; p=""}')"

    # pid<TAB>etime<TAB>comm<TAB>cwd for harness processes on this host
    PROCS="$(ps -eo pid=,etime=,comm= | awk '$3 ~ /^(claude|agy|gemini|antigravity)$/ {print $1 "\t" $2 "\t" $3}' \
        | while IFS=$'\t' read -r pid et comm; do
            cwd="$(readlink "/proc/$pid/cwd" 2>/dev/null || true)"
            [ -n "$cwd" ] && printf '%s\t%s\t%s\t%s\n' "$pid" "$et" "$comm" "$cwd"
          done || true)"
}

# ---------------------------------------------------------------- render

render_sessions() {
    printf '%sSESSIONS on %s%s  %s(harness processes whose working directory is a checkout of this repo)%s\n' "$B" "$(hostname -s)" "$R" "$DIM" "$R"
    local shown=0 elsewhere=0
    while IFS=$'\t' read -r pid et comm cwd; do
        [ -n "$pid" ] || continue
        local br
        case "$cwd" in
            "$REPO_ROOT") br="$DEFAULT_BRANCH (primary checkout)" ;;
            "$REPO_ROOT"/*)
                br="$(awk -F'\t' -v p="$cwd" 'index(p,$1)==1 {print $2}' <<<"$WORKTREES" | head -1)"
                br="${br:-?}" ;;
            *) elsewhere=$(( elsewhere + 1 )); continue ;;
        esac
        printf '  %-8s pid %-8s up %-12s %s\n' "$comm" "$pid" "$et" "$br"
        shown=1
    done <<<"$PROCS"
    [ "$shown" = 1 ] || printf '  none\n'
    [ "$elsewhere" -gt 0 ] && printf '  %s(%s harness process(es) in other directories not shown)%s\n' "$DIM" "$elsewhere" "$R"
    printf '\n'
}

render_issue() {
    local n="$1" issue title labels stage_labels stage flags claim_login claim_at claim_head claim_actor
    issue="$(jq -c --argjson n "$n" '.[] | select(.number==$n)' <<<"$ISSUES_JSON")"
    [ -n "$issue" ] || { printf '%s#%s%s  not an open issue\n\n' "$B" "$n" "$R"; return; }
    title="$(jq -r '.title' <<<"$issue")"
    labels="$(jq -r '.labels[].name' <<<"$issue")"
    stage_labels="$(grep '^status:' <<<"$labels" || true)"
    stage="${stage_labels:-"(no stage)"}"

    flags=""
    grep -Fxq hold     <<<"$labels" && flags+=" ${RED}HOLD${R}"
    grep -Fxq blocked  <<<"$labels" && flags+=" ${RED}BLOCKED${R}"
    grep -Fxq in-progress <<<"$labels" && flags+=" ${CYN}claimed${R}"
    grep -Fxq intent:new  <<<"$labels" && flags+=" intent:new"
    grep -Fxq bootstrap   <<<"$labels" && flags+=" bootstrap"
    grep -q '^review:' <<<"$labels" && flags+=" ${YEL}$(grep '^review:' <<<"$labels" | tr '\n' ' ')${R}"
    [ "$(grep -c . <<<"$stage_labels")" -gt 1 ] 2>/dev/null && flags+=" ${RED}CORRUPT: two status labels${R}"

    printf '%s#%-4s%s %s%-22s%s%s\n' "$B" "$n" "$R" "$GRN" "$(tr '\n' '+' <<<"$stage" | sed 's/+$//')" "$R" "$flags"
    printf '      %s%s%s\n' "$DIM" "${title:0:96}" "$R"

    # --- claim + last word on the thread
    local comments
    comments="$(gh_json "repos/$GITHUB_REPO/issues/$n/comments" --paginate)" || comments="[]"
    local claim
    claim="$(jq -c '[.[] | select(.body | test("\\A[[:space:]]*\\**[[:space:]]*Claim(ing)?\\b"))] | last // empty' <<<"$comments")"
    if grep -Fxq in-progress <<<"$labels"; then
        if [ -n "$claim" ]; then
            claim_login="$(jq -r '.user.login' <<<"$claim")"
            claim_at="$(jq -r '.created_at' <<<"$claim")"
            claim_head="$(jq -r '.body | split("\n")[0]' <<<"$claim")"
            claim_actor="$(actor_of "$claim_login" "$claim_head")"
            printf '      %-9s %s%s%s  %s ago  %s%s%s\n' "claim" "$CYN" "$claim_actor" "$R" "$(ago "$claim_at")" "$DIM" "${claim_head:0:80}" "$R"
        else
            printf '      %-9s %sin-progress set but no structured Claim comment: the mutex names nobody%s\n' "claim" "$RED" "$R"
        fi
    elif [ -n "$claim" ]; then
        printf '      %-9s %sunclaimed%s  %s(last claim was %s, %s ago; released)%s\n' "claim" "$DIM" "$R" "$DIM" \
            "$(actor_of "$(jq -r '.user.login' <<<"$claim")" "$(jq -r '.body|split("\n")[0]' <<<"$claim")")" \
            "$(ago "$(jq -r '.created_at' <<<"$claim")")" "$R"
    else
        printf '      %-9s %sunclaimed%s\n' "claim" "$DIM" "$R"
    fi

    local last last_login last_at last_head
    last="$(jq -c 'last // empty' <<<"$comments")"
    if [ -n "$last" ]; then
        last_login="$(jq -r '.user.login' <<<"$last")"
        last_at="$(jq -r '.created_at' <<<"$last")"
        last_head="$(jq -r '.body | split("\n") | map(select(length>0)) | .[0] // ""' <<<"$last")"
        printf '      %-9s %s  %s ago  %s%s%s\n' "last" "$(actor_of "$last_login" "$last_head")" "$(ago "$last_at")" "$DIM" "${last_head:0:80}" "$R"
        if grep -Fxq in-progress <<<"$labels" && [ -n "${claim_at:-}" ]; then
            local idle=$(( (NOW - $(date -u -d "$last_at" +%s)) / 3600 ))
            [ "$idle" -ge "$STALE_HOURS" ] && printf '      %-9s %sno comment for %sh while claimed (BOARD_STALE_HOURS=%s)%s\n' "stale?" "$YEL" "$idle" "$STALE_HOURS" "$R"
        fi
    fi

    # --- what this stage owes and who owns the next one
    if [ -n "$stage_labels" ] && [ "$(grep -c . <<<"$stage_labels")" -eq 1 ]; then
        local row sname artifact next nrow nstage owners nowners
        row="$(stage_row "$stage_labels")"
        if [ -n "$row" ]; then
            sname="$(jq -r '.stage' <<<"$row")"
            artifact="$(jq -r '.artifact // empty' <<<"$row")"
            case "$sname" in
                implement) artifact="${artifact:-a PR with code + tests}" ;;
                review)    artifact="${artifact:-a review verdict on the PR}" ;;
                *)         artifact="${artifact:-?}" ;;
            esac
            next="$(jq -r '.advances_to // empty' <<<"$row")"
            owners="$(owners_of "$sname" | tr '\n' ',' | sed 's/,$//')"
            # A claim by an actor who does not own the current stage is
            # the drift the labels exist to prevent: either the label is
            # behind (a gate merged and lifecycle.yml has not caught up)
            # or a session is working a rung the labels say is not
            # current. Either way a human should look. claim_actor is set
            # only while in-progress is held: a released claim is history,
            # not a mismatch.
            if [ -n "${claim_actor:-}" ] && ! owners_of "$sname" | grep -Fxq "${claim_actor%% *}"; then
                printf '      %-9s %sclaimed by %s, but stage %s is owned by %s: label behind, or a rung worked out of order%s\n' \
                    "mismatch" "$YEL" "${claim_actor%% *}" "$sname" "${owners:-nobody}" "$R"
            fi
            if [ -n "$next" ]; then
                nrow="$(stage_row "$next")"; nstage="$(jq -r '.stage' <<<"$nrow")"
                nowners="$(owners_of "$nstage" | tr '\n' ',' | sed 's/,$//')"
                printf '      %-9s %s owes %s (%s)  %s->%s %s (%s)\n' "stage" "$sname" "$artifact" "${owners:-nobody}" "$DIM" "$R" "$next" "${nowners:-nobody}"
            else
                printf '      %-9s %s owes %s (%s)  %s-> merge closes the issue%s\n' "stage" "$sname" "$artifact" "${owners:-nobody}" "$DIM" "$R"
            fi
        fi
    fi

    # --- pull requests: by head branch pattern <actor>/<n>-…, by "(#n)" in the title, or "#n" in the body
    local prs
    prs="$(jq -c --arg n "$n" '[.[] | select(
            (.headRefName | test("^[^/]+/" + $n + "-")) or
            (.title | test("\\(#" + $n + "\\)")) or
            ((.body // "") | test("(?i)(closes|fixes|resolves|refs?|part of)\\s*#" + $n + "\\b")))]' <<<"$PRS_JSON")"
    if [ "$(jq length <<<"$prs")" -gt 0 ]; then
        jq -r '.[] | [.number, .headRefName, .baseRefName, (if .isDraft then "DRAFT" else "ready" end), .author.login, .updatedAt,
                 ([.statusCheckRollup[]? | (.conclusion // .state // .status)] | if length==0 then "no checks" elif all(.=="SUCCESS") then "checks ok" elif any(.=="FAILURE" or .=="ERROR") then "CHECKS FAILING" else "checks pending" end),
                 ([.reviews[]? | .author.login] | group_by(.) | map("\(.[0]) x\(length)") | join(" ") | if .=="" then "-" else . end),
                 ([.reviews[]? | .state] | last // "-"),
                 (.mergeable // "-")] | @tsv' <<<"$prs" \
        | while IFS=$'\t' read -r pn head base draft author upd checks reviewers lastrev mergeable; do
            # "-" stands in for an empty field: `read` collapses adjacent tabs.
            local base_note="" rev_note col
            if [ "$base" != "$DEFAULT_BRANCH" ]; then
                local bpr; bpr="$(jq -r --arg b "$base" '.[] | select(.headRefName==$b) | .number' <<<"$PRS_JSON" | head -1)"
                base_note="  ${YEL}stacked on $base${bpr:+ (#$bpr)}${R}"
            fi
            case "$checks" in *FAILING*) col="$RED";; *pending*) col="$YEL";; *) col="";; esac
            if [ "$reviewers" = "-" ]; then rev_note="no reviews"; else rev_note="$reviewers (last: $lastrev)"; fi
            [ "$mergeable" = "CONFLICTING" ] && rev_note+="  ${RED}CONFLICTS${R}"
            printf '      %-9s %s -> %s  %s  by %s  %s ago  %s%s%s  %s%s\n' "PR #$pn" "$head" "$base" "$draft" \
                "$(actor_of "$author" "")" "$(ago "$upd")" "$col" "$checks" "$R" "$rev_note" "$base_note"
        done
    else
        printf '      %-9s %snone open%s\n' "PR" "$DIM" "$R"
    fi

    # --- branches and local checkouts for this issue
    local br_line="" wt_line=""
    while read -r br ts; do
        [ -n "$br" ] || continue
        [[ "$br" =~ ^[^/]+/${n}- ]] || continue
        br_line+="${br%%/*}($(ago "$ts")) "
    done <<<"$BRANCHES"
    [ -n "$br_line" ] && printf '      %-9s %s\n' "branches" "$br_line"

    while IFS=$'\t' read -r path br; do
        [ -n "$path" ] || continue
        [[ "$br" =~ ^[^/]+/${n}- ]] || continue
        local live
        live="$(awk -F'\t' -v p="$path" '$4==p {printf "%s pid %s up %s; ", $3, $1, $2}' <<<"$PROCS")"
        if [ -n "$live" ]; then
            wt_line+="${GRN}${br} LIVE${R} (${live% ; }) "
        else
            wt_line+="${br} ${DIM}idle${R} "
        fi
    done <<<"$WORKTREES"
    [ -n "$wt_line" ] && printf '      %-9s %s\n' "local" "$wt_line"
    printf '\n'
}

render_orphans() {
    # Worktrees whose branch has neither a remote branch nor an open PR:
    # leftovers from finished or abandoned sessions, and the usual reason
    # `git worktree list` is unreadable.
    local out=""
    while IFS=$'\t' read -r path br; do
        [ -n "$path" ] || continue
        [ "$path" = "$REPO_ROOT" ] && continue
        case "$br" in "(detached)"|"") out+="  $(basename "$path")  (detached)\n"; continue;; esac
        grep -q "^$br " <<<"$BRANCHES" && continue
        out+="  $(basename "$path")  [$br]  no remote branch\n"
    done <<<"$WORKTREES"
    if [ -n "$out" ]; then
        printf '%sWORKTREES with nothing behind them%s  %s(no remote branch or detached; candidates for `git worktree remove`)%s\n' "$B" "$R" "$DIM" "$R"
        printf '%b\n' "$out"
    fi
}

render() {
    gather
    printf '%s%s  board @ %s%s  %s(labels + claims + PRs + branches + local checkouts; read-only)%s\n\n' \
        "$B" "$GITHUB_REPO" "$(date -u +%Y-%m-%dT%H:%MZ)" "$R" "$DIM" "$R"
    render_sessions

    local numbers
    if [ "${#ONLY[@]}" -gt 0 ]; then
        numbers="$(printf '%s\n' "${ONLY[@]}")"
    elif [ "$ALL" = 1 ]; then
        numbers="$(jq -r '.[] | .number' <<<"$ISSUES_JSON")"
    else
        numbers="$(jq -r '.[] | select(any(.labels[].name; startswith("status:") or .=="in-progress")) | .number' <<<"$ISSUES_JSON")"
    fi

    if [ -z "$numbers" ]; then
        printf '%sIN FLIGHT%s  nothing carries a status:* or in-progress label\n\n' "$B" "$R"
    else
        printf '%sIN FLIGHT%s  %s(open issues with a status:* or in-progress label, newest activity first)%s\n\n' "$B" "$R" "$DIM" "$R"
        # newest activity first
        for n in $(jq -r --argjson want "$(jq -cs . <<<"$numbers")" \
                    '.[] | select(.number as $n | $want | index($n)) | [.updated_at, .number] | @tsv' <<<"$ISSUES_JSON" \
                    | sort -r | cut -f2); do
            render_issue "$n"
        done
    fi

    local unclaimed
    unclaimed="$(jq -r '.[] | select((any(.labels[].name; startswith("status:") or .=="in-progress")|not) and any(.labels[].name; .=="intent:new")) | "  #\(.number)  \(.title[0:80])  (\(.created_at[0:10]))"' <<<"$ISSUES_JSON")"
    if [ -n "$unclaimed" ] && [ "${#ONLY[@]}" -eq 0 ]; then
        printf '%sINTAKE waiting%s  %s(intent:new, no stage yet: athena owes the plan rung)%s\n%s\n\n' "$B" "$R" "$DIM" "$R" "$unclaimed"
    fi

    [ "${#ONLY[@]}" -eq 0 ] && render_orphans
    return 0
}

if [ -n "$WATCH" ]; then
    while :; do
        out="$(render 2>&1)" || true
        clear
        printf '%s\n%srefresh every %ss — Ctrl-C to stop%s\n' "$out" "$DIM" "$WATCH" "$R"
        sleep "$WATCH"
    done
else
    render
fi
