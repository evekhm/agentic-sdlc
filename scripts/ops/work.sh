#!/usr/bin/env bash
# One-argument dispatch (#36, intent/36-dispatch/spec.md).
#
#   scripts/ops/work.sh <issue-or-pr-number> [--as <persona>]
#   DRY_RUN=1 scripts/ops/work.sh <issue-or-pr-number>
#
# A NUMBER IS THE WHOLE INSTRUCTION (D7). There is deliberately no flag
# naming a stage, a folder, an artifact or a branch: such a flag would
# let a session work a stage the labels say is not current, which is
# exactly the drift the labels-are-the-state-machine rule exists to
# stop. `--as <persona>` picks one of several owners of the same stage
# and is the only other input.
#
# Deterministic bash + gh + jq. No model call, no prompt, no API key:
# the issue's labels, the merged folder layout and three committed data
# files are the whole input, which is why the same number always
# resolves the same way. Failure mode first — the order is
#
#   resolve the number -> refusals -> owner set -> harness pin -> launch
#
# and every refusal happens BEFORE anything is dispatched.
#
# THIS SCRIPT NEVER WRITES TO GITHUB. It reads. The claim (`in-progress`
# plus the one-line claim comment, AGENTS.md "Working the tracker" step
# 2) belongs to the session this script launches, not to the launcher —
# a dispatcher that claimed on behalf of a session that then failed to
# start would leave the mutex held by nobody. `DRY_RUN=1` therefore
# differs in exactly one way: it prints the resolved launch command
# instead of executing it. Reads still run, so every guard below is
# exercised against the live issue.
#
# Where the facts come from, none of them restated here:
#   personas/lifecycle.json   label <-> stage, the artifact each stage
#                             owes, and the one-line brief (D1, D2)
#   personas/*.yaml           WHO owns a stage — derived, never stored:
#                             every kind: persona source whose `stage`
#                             list contains it (D2)
#   config/deployments.yaml   which harness a persona runs on (D10)
#
# Exit codes (D8):
#   0  launched, or printed (a dry run, an unlaunchable harness, or a
#      multi-owner stage that deliberately launches nothing)
#   2  refused — one of the six stated conditions in D5. Expected
#      behaviour, not a bug: the issue is not in a state to be worked.
#   1  unusable input: an unreadable number, a PR that resolves to no
#      issue, a stage no label names, a persona with no harness pin, or
#      an unparsable source file.

set -euo pipefail

GITHUB_REPO="${GITHUB_REPO:-${GITHUB_REPOSITORY:-evekhm/agentic-sdlc}}"
DRY_RUN="${DRY_RUN:-0}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIFECYCLE_JSON="$REPO_ROOT/personas/lifecycle.json"
DEPLOYMENTS="$REPO_ROOT/config/deployments.yaml"
PERSONA_DIR="$REPO_ROOT/personas"

usage() {
    cat <<'USAGE'
usage: scripts/ops/work.sh <issue-or-pr-number> [--as <persona>]
       DRY_RUN=1 scripts/ops/work.sh <issue-or-pr-number>

The number is the whole instruction. Nothing else about the work is an
argument: the stage comes from the issue's single status:* label, the
owner from the persona sources, the folder from the repository, and the
harness from config/deployments.yaml.
USAGE
}

die() { echo "work.sh: $*" >&2; exit 1; }             # unusable input
refuse() { echo "refused: $*" >&2; exit 2; }          # a stated D5 condition

# --- Arguments ----------------------------------------------------------------
NUMBER=""
AS=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --as)
            [ "$#" -ge 2 ] || die "--as needs a persona name"
            AS="$2"; shift 2 ;;
        --as=*) AS="${1#--as=}"; shift ;;
        -*) usage >&2; die "unknown flag '$1'; the number is the whole instruction" ;;
        *)
            [ -z "$NUMBER" ] \
                || die "one number is one run; got '$NUMBER' and '$1'"
            NUMBER="${1#\#}"; shift ;;
    esac
done
[ -n "$NUMBER" ] || { usage >&2; exit 1; }
case "$NUMBER" in
    ''|*[!0-9]*) die "'$NUMBER' is not an issue or pull-request number" ;;
esac
[ -z "$AS" ] || case "$AS" in
    *[!a-z-]*) die "--as '$AS' is not a persona name" ;;
esac

# --- Preflight ----------------------------------------------------------------
for cmd in gh jq; do
    command -v "$cmd" >/dev/null || die "$cmd is not installed"
done
[ -r "$LIFECYCLE_JSON" ] || die "cannot read $LIFECYCLE_JSON"
jq -e '.stages | type == "array" and length > 0' "$LIFECYCLE_JSON" >/dev/null 2>&1 \
    || die "$LIFECYCLE_JSON has no usable 'stages' array"
[ -r "$DEPLOYMENTS" ] || die "cannot read $DEPLOYMENTS"
[ -d "$PERSONA_DIR" ] || die "cannot read $PERSONA_DIR"

# The ONE read path to GitHub. Every call goes through it, so a test can
# put a stub `gh` first on PATH and the whole script becomes hermetic.
gh_json() { # <api-path>
    gh api "$1"
}

# --- Resolve the number (D9) ---------------------------------------------------
# A pull request is not the unit of work; the issue is. A closing keyword
# and `#<n>` in the body first, then the <actor>/<n>-<slug> branch name,
# then give up:
# guessing which issue a PR belongs to is how two sessions end up on one
# issue.
view=""
if ! view="$(gh_json "repos/$GITHUB_REPO/issues/$NUMBER")"; then
    die "cannot read #$NUMBER from $GITHUB_REPO"
fi

ISSUE="$NUMBER"
RESOLVED_VIA=""
if [ "$(jq -r 'if .pull_request then "pr" else "issue" end' <<<"$view")" = "pr" ]; then
    pr_body="$(jq -r '.body // ""' <<<"$view")"
    # Every closing keyword GitHub honours, case-insensitively, same-repo
    # `#n` only: `Fixes #205` closes #205 on merge whether or not this
    # script reads the word, and a dispatcher that only knows `closes`
    # sends the session to the PR instead of the unit of work. Cross-repo
    # `owner/repo#9` and URL forms deliberately do not match — they close
    # an issue that is not in this tracker.
    closes="$(grep -Eoi '\b(close[sd]?|fix(es|ed)?|resolve[sd]?)[[:space:]]+#[0-9]+' \
        <<<"$pr_body" | grep -Eo '[0-9]+$' | sort -un || true)"
    closes_count=0
    [ -z "$closes" ] || closes_count="$(grep -c . <<<"$closes")"
    if [ "$closes_count" -gt 1 ]; then
        # Two closing references is two units of work. D5(d)'s never-guess
        # rule applies: report them and stop rather than take the first.
        die "PR #$NUMBER closes more than one issue: $(sed 's/^/#/' <<<"$closes" \
            | tr '\n' ' ')— dispatch one of them by its own number"
    fi
    if [ "$closes_count" -eq 1 ]; then
        ISSUE="$closes"
        RESOLVED_VIA="Closes #$ISSUE in the body"
    else
        pr_view=""
        if ! pr_view="$(gh_json "repos/$GITHUB_REPO/pulls/$NUMBER")"; then
            die "cannot resolve PR #$NUMBER to an issue"
        fi
        head_ref="$(jq -r '.head.ref // ""' <<<"$pr_view")"
        if [[ "$head_ref" =~ ^[a-z][a-z-]*/([0-9]+)- ]]; then
            ISSUE="${BASH_REMATCH[1]}"
            RESOLVED_VIA="the branch name $head_ref"
        else
            die "cannot resolve PR #$NUMBER to an issue"
        fi
    fi
    if ! view="$(gh_json "repos/$GITHUB_REPO/issues/$ISSUE")"; then
        die "PR #$NUMBER resolves to #$ISSUE, which cannot be read"
    fi
fi

state="$(jq -r '.state' <<<"$view")"
title="$(jq -r '.title // ""' <<<"$view")"
labels="$(jq -r '.labels[].name' <<<"$view")"

has_label() { grep -Fxq "$1" <<<"$labels"; }

# --- Refusals, in D5's order, before anything else -----------------------------
# A refusal is a report, never a partial claim.

# (a) hold is absolute — not even a look further down the list.
if has_label "hold"; then
    refuse "#$ISSUE carries hold"
fi

# (b) humans have taken over.
if [ "$state" != "open" ]; then
    refuse "#$ISSUE is closed"
fi
if has_label "status:review-stuck"; then
    refuse "#$ISSUE carries status:review-stuck"
fi

# (c) blocked is a report-and-stop, not a wait.
if has_label "blocked"; then
    refuse "#$ISSUE carries blocked"
fi

# (d) more than one status:* is a corrupted state machine. Report the
#     labels and stop: never guess which is true, and never apply `hold`
#     either — the stage advancer is the single writer of the circuit
#     breaker, and two writers is two circuit breakers (#4, D1).
status_labels="$(grep '^status:' <<<"$labels" || true)"
status_count=0
[ -z "$status_labels" ] || status_count="$(grep -c . <<<"$status_labels")"
if [ "$status_count" -gt 1 ]; then
    refuse "#$ISSUE carries more than one status:* label: $(tr '\n' ' ' <<<"$status_labels")"
fi

# --- Stage, from the label, through the one table (D2, D4) ---------------------
if [ "$status_count" -eq 1 ]; then
    stage="$(jq -r --arg l "$status_labels" \
        '.stages[] | select(.label == $l) | .stage' "$LIFECYCLE_JSON")"
    [ -n "$stage" ] \
        || die "#$ISSUE carries '$status_labels', which is not a rung in $LIFECYCLE_JSON"
elif has_label "intent:new"; then
    # Filed but not yet on the ladder: the first rung is where work starts.
    stage="$(jq -r '.stages[0].stage' "$LIFECYCLE_JSON")"
else
    die "cannot derive a stage for #$ISSUE: it carries no status:* label and no intent:new"
fi

row="$(jq -ec --arg s "$stage" '.stages[] | select(.stage == $s)' "$LIFECYCLE_JSON")" \
    || die "no lifecycle row for stage '$stage'"
label="$(jq -r '.label' <<<"$row")"
brief="$(jq -r '.dispatch_brief' <<<"$row")"
artifact="$(jq -r '.artifact // "none — the output is code or a review"' <<<"$row")"

# --- Owners: derived from the sources, never stored (D2) -----------------------
# Every kind: persona source whose `stage` list contains this stage.
owners_of() { # <stage> -> sorted persona names, one per line
    local want="$1" file name stages
    for file in "$PERSONA_DIR"/*.yaml; do
        [ -f "$file" ] || continue
        grep -qx 'kind: persona' "$file" || continue
        stages="$(sed -n 's/^stage:[[:space:]]*\[\(.*\)\].*/\1/p' "$file")"
        [ -n "$stages" ] || continue
        name="$(basename "$file" .yaml)"
        case ",$(tr -d '[:space:]' <<<"$stages")," in
            *",$want,"*) echo "$name" ;;
        esac
    done | sort
}

owners="$(owners_of "$stage")"
[ -n "$owners" ] \
    || die "no persona source declares stage '$stage'; nothing can be dispatched"

# The identity a persona posts as, so a claim comment's author names an
# actor rather than a login.
# Compared as a string, never as a pattern: an app login ends in
# "[bot]", which a regexp would read as a character class and quietly
# mis-match.
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

# (e) in-progress held by somebody else. The holder is the AUTHOR of the
#     last claim comment, mapped through the identity table in
#     personas/*.yaml — never a name read out of the comment body. A body
#     is an unauthenticated string, and reading an actor out of it lets
#     any commenter decide whether dispatch refuses or proceeds, in both
#     directions (#36, Argus R1-1).
#     What counts as a claim is the structured line AGENTS.md "Working
#     the tracker" step 2 prescribes: the comment OPENS with `Claim`
#     (or `Claiming`, optionally bold). Prose that merely contains the
#     word — "the PR claims it is byte-identical" — is not a claim and is
#     ignored. An author no persona identity names is a foreign claim:
#     fail closed and name the login, because an unknown actor is exactly
#     the case where this script must not assume it is looking at itself.
#     A claim by an owner of this stage is that actor resuming its own
#     work and proceeds; when `--as` names one owner the mutex binds
#     against that actor alone, since atlas holding the claim is a
#     different actor from argus even though both own review. `--as` is
#     itself validated against the stage's owners by (f) below, which
#     leaves D5's refusal ORDER as written.
claim_holder=""
if has_label "in-progress"; then
    resumers="$owners"
    [ -z "$AS" ] || resumers="$AS"
    comments=""
    if comments="$(gh_json "repos/$GITHUB_REPO/issues/$ISSUE/comments")"; then
        claim_re='\A[[:space:]]*\**[[:space:]]*Claim(ing)?\b'
        claim_login="$(jq -r --arg re "$claim_re" \
            '[.[] | select((.body // "") | test($re; "i"))] | last | .user.login // ""' \
            <<<"$comments")"
        if [ -n "$claim_login" ]; then
            claim_holder="$(persona_for_login "$claim_login")"
            [ -n "$claim_holder" ] \
                || refuse "in-progress on #$ISSUE is held by $claim_login, a login no persona identity names"
            grep -Fxq "$claim_holder" <<<"$resumers" \
                || refuse "in-progress on #$ISSUE is held by $claim_holder"
        fi
    fi
fi

# (f) --as must name an owner of the stage the labels say is current.
if [ -n "$AS" ] && ! grep -Fxq "$AS" <<<"$owners"; then
    refuse "$AS does not own stage $stage (owners: $(tr '\n' ' ' <<<"$owners"))"
fi
[ -z "$AS" ] || owners="$AS"

# --- Folder and branch (D6) ----------------------------------------------------
# Reuse beats derive, and derive beats named-in-a-comment: two sessions
# on the same cold issue must land on the same path without reading each
# other.
derive_slug() { # <title> -> slug
    local s="$1" cut trimmed
    s="${s%%:*}"
    s="${s%%;*}"
    s="$(tr '[:upper:]' '[:lower:]' <<<"$s" | tr -cs 'a-z0-9' '-')"
    s="${s#-}"; s="${s%-}"
    if [ "${#s}" -gt 24 ]; then
        cut="${s:0:24}"
        trimmed="${cut%-*}"
        if [ -n "$trimmed" ] && [ "$trimmed" != "$cut" ]; then
            s="$trimmed"
        else
            s="${cut%-}"
        fi
    fi
    printf '%s\n' "$s"
}

shopt -s nullglob
existing=( "$REPO_ROOT/intent/$ISSUE-"*/ )
shopt -u nullglob
case "${#existing[@]}" in
    0)
        slug="$(derive_slug "$title")"
        [ -n "$slug" ] || die "cannot derive a folder slug from the title of #$ISSUE"
        folder_origin="derived from the title"
        ;;
    1)
        slug="$(basename "${existing[0]}")"
        slug="${slug#"$ISSUE-"}"
        folder_origin="existing"
        ;;
    *)
        refuse "#$ISSUE has more than one intent folder: $(
            for d in "${existing[@]}"; do printf '%s ' "$(basename "$d")"; done)"
        ;;
esac
folder="intent/$ISSUE-$slug/"

# --- Harness and the launch table (D10) ----------------------------------------
# The pin says WHICH harness; this script says how to start the ones it
# knows. An unlaunchable harness is a supported outcome — it prints and
# exits 0. An owner with no pin is not: that is a broken deployment.
harness_of() { # <persona> -> harness, or empty
    awk -v want="$1" '
        $1 == "personas:" { inside = 1; next }
        /^[^[:space:]#]/  { inside = 0 }
        !inside { next }
        $1 == want ":" {
            for (i = 2; i <= NF; i++) {
                if ($i == "harness:") { v = $(i + 1); gsub(/[,}]/, "", v); print v; exit }
            }
            block = 1; next
        }
        block && $1 == "harness:" { v = $2; gsub(/[,}]/, "", v); print v; exit }
        block && $1 ~ /:$/ { block = 0 }
    ' "$DEPLOYMENTS"
}

target_of() { # <persona> <harness> -> the compiled target a launch runs
    case "$2" in
        claude-code) printf '.claude/agents/%s.md' "$1" ;;
        antigravity) printf '.agents/agents/%s/instructions.md' "$1" ;;
        *)           printf '(no compiled target known for harness %s)' "$2" ;;
    esac
}

launch_command() { # <persona> <harness> -> the command line, or empty
    case "$2" in
        claude-code) printf 'claude --agent %s "#%s"' "$1" "$ISSUE" ;;
        *)           printf '' ;;
    esac
}

# --- Report --------------------------------------------------------------------
owner_list="$(tr '\n' ' ' <<<"$owners")"
owner_count="$(grep -c . <<<"$owners")"

echo "==> #$ISSUE · $title"
[ -z "$RESOLVED_VIA" ] || echo "    resolved from #$NUMBER via $RESOLVED_VIA"
echo "    stage:    $stage"
echo "    label:    $label"
echo "    artifact: $artifact"
echo "    owner:    ${owner_list% }"
echo "    folder:   $folder ($folder_origin)"
if has_label "in-progress"; then
    echo "    claim:    in-progress, held by ${claim_holder:-nobody the thread names}"
fi

launch_persona=""
launch_line=""
while read -r persona; do
    [ -n "$persona" ] || continue
    harness="$(harness_of "$persona")"
    [ -n "$harness" ] \
        || die "config/deployments.yaml has no harness pin for persona '$persona'"
    command_line="$(launch_command "$persona" "$harness")"
    echo "--> $persona"
    echo "    harness:  $harness"
    echo "    target:   $(target_of "$persona" "$harness")"
    echo "    branch:   $persona/$ISSUE-$slug"
    echo "    brief:    $brief"
    if [ -n "$command_line" ]; then
        echo "    command:  $command_line"
    else
        echo "    command:  none — this harness is started by hand; open the target"
        echo "              above and give it the one-line prompt: #$ISSUE"
    fi
    if [ -z "$launch_persona" ]; then
        launch_persona="$persona"
        launch_line="$command_line"
    fi
done <<<"$owners"

# --- Launch (or deliberately not) ----------------------------------------------
if [ "$owner_count" -gt 1 ]; then
    # Auto-picking would silently halve a policy whose whole content is
    # that two independent reviewers both look (#2, D4). Name one with
    # --as if that is really what you meant.
    echo "==> stage $stage has $owner_count owners; printing both and launching neither."
    echo "    Re-run with --as <persona> to launch exactly one."
    exit 0
fi
if [ "$DRY_RUN" = "1" ]; then
    echo "==> DRY_RUN=1 — nothing was launched and nothing was written."
    exit 0
fi
if [ -z "$launch_line" ]; then
    echo "==> $launch_persona's harness is not one this script starts — printed above."
    exit 0
fi
echo "==> launching: $launch_line"
exec claude --agent "$launch_persona" "#$ISSUE"
