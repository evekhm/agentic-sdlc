#!/usr/bin/env bash
# One-argument dispatch (#36, intent/36-dispatch/spec.md).
#
#   scripts/ops/work.sh <issue-or-pr-number> [--as <persona>]
#   DRY_RUN=1  scripts/ops/work.sh <issue-or-pr-number>
#   HEADLESS=1 scripts/ops/work.sh <issue-or-pr-number>
#
# A NUMBER IS THE WHOLE INSTRUCTION (D7). There is deliberately no flag
# naming a stage, a folder, an artifact or a branch: such a flag would
# let a session work a stage the labels say is not current, which is
# exactly the drift the labels-are-the-state-machine rule exists to
# stop. `--as <persona>` picks one of several owners of the same stage
# and is the only other input. Every MODE is an environment variable for
# the same reason argv is closed: `DRY_RUN`, and now `HEADLESS` (#43,
# D5) — a mode is how a run is executed, never what is worked.
#
# Deterministic bash + gh + jq up to the launch. No model call, no prompt,
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
# THIS SCRIPT NEVER PRINTS A TOKEN. It mints the launched persona's App
# token in the one step between the last refusal and the launch (#43,
# D11), hands it to the child as a variable-assignment prefix, and never
# writes it to a file, an argument or the log. A run that launches
# nothing — a dry run, a two-owner stage, a harness with no row —
# exchanges nothing and leaves no live credential behind.
#
# Exit codes (D8, extended by #43 D14/D23):
#   0  launched and the session reported `WORK-RESULT: ok`, or printed
#      (a dry run, an unlaunchable harness, or a multi-owner stage that
#      deliberately launches nothing)
#   2  the number was NOT WORKED, BY DESIGN — either this script refused
#      (one of the six D5 conditions) or the launched persona itself
#      reported `WORK-RESULT: refused|blocked`. One code, because a
#      caller asks whether the number was worked, not which layer
#      declined (#43, D23).
#   1  unusable input: an unreadable number, a PR that resolves to no
#      issue, a stage no label names, a persona with no harness pin, an
#      unparsable source file, a missing compiled target, a token that
#      could not be minted — or a headless session whose outcome could
#      not be observed (a crash, a timeout, or a clean exit with no
#      WORK-RESULT line; returning 0 for an outcome nobody saw is a lie).

set -euo pipefail

GITHUB_REPO="${GITHUB_REPO:-${GITHUB_REPOSITORY:-evekhm/agentic-sdlc}}"
DRY_RUN="${DRY_RUN:-0}"
HEADLESS="${HEADLESS:-0}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIFECYCLE_JSON="$REPO_ROOT/personas/lifecycle.json"
DEPLOYMENTS="$REPO_ROOT/config/deployments.yaml"
PERSONA_DIR="$REPO_ROOT/personas"

usage() {
    cat <<'USAGE'
usage: scripts/ops/work.sh <issue-or-pr-number> [--as <persona>]
       DRY_RUN=1  scripts/ops/work.sh <issue-or-pr-number>
       HEADLESS=1 scripts/ops/work.sh <issue-or-pr-number>

The number is the whole instruction. Nothing else about the work is an
argument: the stage comes from the issue's single status:* label, the
owner from the persona sources, the folder from the repository, and the
harness from config/deployments.yaml.

Modes are environment variables, never flags:
  DRY_RUN=1   resolve and print, launch nothing, mint nothing.
  HEADLESS=1  run the session non-interactively and map its
              WORK-RESULT line to an exit code. Antigravity personas
              are always headless; there is no interactive row.
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
#     The label alone is enough to stop: `in-progress` whose thread
#     carries no structured claim is a mutex that names nobody, and
#     dispatching on it would launch a second session on an issue some
#     actor is holding without a readable claim (#36, Argus R2-1). The
#     same goes for a thread this script cannot read — an unverifiable
#     mutex is a held mutex. Removing `in-progress` is how a session
#     hands the issue back (AGENTS.md, "Working the tracker", step 5).
claim_holder=""
if has_label "in-progress"; then
    resumers="$owners"
    [ -z "$AS" ] || resumers="$AS"
    comments=""
    comments="$(gh_json "repos/$GITHUB_REPO/issues/$ISSUE/comments")" \
        || refuse "in-progress on #$ISSUE is set and its thread cannot be read, so the holder cannot be established"
    claim_re='\A[[:space:]]*\**[[:space:]]*Claim(ing)?\b'
    claim_login="$(jq -r --arg re "$claim_re" \
        '[.[] | select((.body // "") | test($re; "i"))] | last | .user.login // ""' \
        <<<"$comments")"
    [ -n "$claim_login" ] \
        || refuse "in-progress on #$ISSUE is set but no comment opens with a structured claim line (AGENTS.md, \"Working the tracker\", step 2): the mutex names no holder"
    claim_holder="$(persona_for_login "$claim_login")"
    [ -n "$claim_holder" ] \
        || refuse "in-progress on #$ISSUE is held by $claim_login, a login no persona identity names"
    grep -Fxq "$claim_holder" <<<"$resumers" \
        || refuse "in-progress on #$ISSUE is held by $claim_holder"
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
        antigravity) printf '.agents/agents/%s/agent.md' "$1" ;;
        *)           printf '' ;;
    esac
}

# The persona's own cap, read from the SOURCE. Limits live in
# personas/<p>.yaml and nowhere else: the compiler no longer copies them
# into a target, so there is one home for the fact (#43, D6, D9).
timeout_mins_of() { # <persona> -> limits.timeout_mins
    local persona="$1" file value
    file="$PERSONA_DIR/$persona.yaml"
    [ -f "$file" ] || die "personas/$persona.yaml does not exist"
    value="$(sed -n '/^limits:/,$p' "$file" \
        | sed -n 's/^[[:space:]][[:space:]]*timeout_mins:[[:space:]]*\([0-9][0-9]*\).*/\1/p' \
        | head -1)"
    [ -n "$value" ] \
        || die "personas/$persona.yaml declares no numeric limits.timeout_mins"
    printf '%s\n' "$value"
}

# The RESOLVED model, read from the compiled sidecar. Re-resolving the
# persona's tier against config/model_tiers.yaml in awk here would be a
# second implementation of the compiler's one job, and two of them drift
# silently (#43, D9).
model_of() { # <persona> -> the model agy is launched with
    local persona="$1" sidecar value
    sidecar=".agents/agents/$persona/agent.json"
    [ -f "$REPO_ROOT/$sidecar" ] \
        || die "$sidecar is missing; run scripts/sync_agents.py and commit the result"
    value="$(jq -r '.model // empty' "$REPO_ROOT/$sidecar")" \
        || die "$sidecar is not readable JSON"
    [ -n "$value" ] || die "$sidecar names no model for $persona"
    printf '%s\n' "$value"
}

# THE PROMPT (#43, D2, D21, D22). One literal, both harnesses, both
# modes. It names a number and nothing else — no stage, no folder, no
# artifact, no branch — so a launch cannot tell a session to work a rung
# the labels say is not current, which is the same rule that closes argv
# (D7). A bare `#<n>` is NOT sent: `#` is not a sigil to either harness,
# and a bare number handed to a persona that failed to load was measured
# burning 160k tokens before timing out. The WORK-RESULT sentence lives
# here rather than in personas/**: only a launcher reads it, and putting
# it in the sources would make every hand-opened interactive session emit
# a machine-readable result line for nobody (D21).
PROMPT="Work issue #$ISSUE in this repository. Follow your persona instructions and the repository's AGENTS.md; when you finish or refuse, print one final line WORK-RESULT: <ok|refused|blocked> #$ISSUE <one-line reason>."

# The launch table (#43, D1, D5, D6). An ARRAY, not a string: a printed
# command and an executed one must not be two spellings of the same
# thing, so the report prints this array through printf '%q ' and the
# launch execs it.
#
#   harness       HEADLESS=0                     HEADLESS=1
#   claude-code   claude --agent P "$PROMPT"     claude -p … --output-format json
#   antigravity   (same as headless — D5)        agy -p … --add-dir … --print-timeout
#
# Every row is wrapped in `timeout $((T*60+60))` so a harness that
# ignores its own print timeout still ends; the spare minute is for the
# harness's own teardown.
LAUNCH_ARGV=()
#
# `antigravity` is ALWAYS headless, whatever HEADLESS says: only print
# mode was ever measured, an interactive agy session is untested, and it
# is not what a dispatcher needs — the presenter drives interactive
# antigravity work in the IDE, not through this script (D5).
headless_for() { # <harness> -> 1 | 0
    case "$1" in
        antigravity) printf '1\n' ;;
        *)           printf '%s\n' "$([ "$HEADLESS" = "1" ] && echo 1 || echo 0)" ;;
    esac
}

launch_argv() { # <persona> <harness> -> fills LAUNCH_ARGV; empty = no row
    local persona="$1" harness="$2" mins wrap model
    LAUNCH_ARGV=()
    case "$harness" in
        claude-code|antigravity) ;;
        *) return 0 ;;
    esac
    mins="$(timeout_mins_of "$persona")" || exit 1
    wrap=$(( mins * 60 + 60 ))
    LAUNCH_ARGV=( timeout "$wrap" )
    case "$harness" in
        claude-code)
            if [ "$(headless_for "$harness")" = "1" ]; then
                LAUNCH_ARGV+=( claude -p "$PROMPT" --agent "$persona"
                               --output-format json )
            else
                LAUNCH_ARGV+=( claude --agent "$persona" "$PROMPT" )
            fi
            ;;
        antigravity)
            # --add-dir is MANDATORY and is $REPO_ROOT: print mode
            # ignores the working directory entirely, and without this
            # flag not one repository file is opened. $REPO_ROOT is the
            # checkout that owns this script (derived from BASH_SOURCE
            # above), never `git rev-parse` from the caller's cwd — the
            # labels, the folder layout and the deployment pins were all
            # read from that tree, and reading state from one checkout
            # while editing another is the split #36 exists to avoid
            # (D24). This file `cd`s exactly once, immediately before
            # the launch, and only ever to $REPO_ROOT — the same value
            # --add-dir receives (D1 as amended). A `cd` to anywhere
            # else is what remains forbidden.
            model="$(model_of "$persona")" || exit 1
            LAUNCH_ARGV+=( agy -p "$PROMPT" --agent "$persona"
                           --add-dir "$REPO_ROOT" --model "$model"
                           --output-format json --print-timeout "${mins}m" )
            ;;
    esac
}

# Neither harness signals a model-level refusal at the process boundary:
# a forced `REFUSED: …` exits 0 with a SUCCESS status on both. So the
# outcome is read IN BAND, from the decoded response text — never
# grepped out of the raw JSON, where the newline is escaped and
# `^WORK-RESULT:` would silently never match. The two harnesses disagree
# on key names (measured, #43 probe P4: agy answers `.status`/`.response`,
# Claude Code `.is_error`/`.result`), so this is one mapping with one
# jq expression each rather than two mappings.
response_text() { # <harness>; raw JSON on stdin
    case "$1" in
        antigravity) jq -r '.response // ""' ;;
        claude-code) jq -r '.result // ""' ;;
        *)           cat ;;
    esac
}
process_status() { # <harness>; raw JSON on stdin -> SUCCESS | ERROR
    case "$1" in
        antigravity) jq -r 'if (.status // "ERROR") == "SUCCESS"
                            then "SUCCESS" else "ERROR" end' ;;
        # `.is_error == false`, not `.is_error // true`: jq's `//` treats
        # `false` as absent, so the alternative form turns every SUCCESS
        # into an ERROR. Written the explicit way, a missing key is an
        # ERROR too, which is the conservative reading we want.
        claude-code) jq -r 'if (.is_error == false) then "SUCCESS" else "ERROR" end' ;;
        *)           printf 'ERROR\n' ;;
    esac
}

# --- Report --------------------------------------------------------------------
owner_list="$(tr '\n' ' ' <<<"$owners")"
owner_count="$(grep -c . <<<"$owners")"

echo "==> #$ISSUE · $title"
[ -z "$RESOLVED_VIA" ] || echo "    resolved from #$NUMBER via $RESOLVED_VIA"
# Which checkout a session will actually edit (D24). Printed because the
# operator standing in a worktree and invoking another tree's copy of
# this script is a real and silent mistake.
echo "    root:     $REPO_ROOT"
echo "    stage:    $stage"
echo "    label:    $label"
echo "    artifact: $artifact"
echo "    owner:    ${owner_list% }"
echo "    folder:   $folder ($folder_origin)"
# Printed once, unquoted, because the per-owner `command:` line below is
# shell-escaped and a human cannot read the prompt out of it.
echo "    prompt:   $PROMPT"
if has_label "in-progress"; then
    # Reaching here with `in-progress` means (e) established a holder.
    echo "    claim:    in-progress, held by $claim_holder"
fi

launch_persona=""
launch_harness=""
launch_target=""
launch_missing=0
LAUNCH=()
while read -r persona; do
    [ -n "$persona" ] || continue
    harness="$(harness_of "$persona")"
    [ -n "$harness" ] \
        || die "config/deployments.yaml has no harness pin for persona '$persona'"
    target="$(target_of "$persona" "$harness")"
    # PREFLIGHT (D3). agy's failure mode for a missing agent file is
    # SILENT — it runs its stock agent, prints nothing anywhere a script
    # can see, and exits 0 — so before the process starts is the only
    # cheap place to notice. For an owner that is merely being printed
    # this is a marker and nothing more: a broken atlas target must not
    # stop `--as argus` (D20). It becomes fatal below, for the one
    # persona actually about to be launched.
    missing=0
    if [ -n "$target" ] && [ ! -f "$REPO_ROOT/$target" ]; then
        missing=1
    fi
    LAUNCH_ARGV=()
    [ "$missing" -eq 1 ] || launch_argv "$persona" "$harness"
    echo "--> $persona"
    echo "    harness:  $harness"
    if [ -z "$target" ]; then
        echo "    target:   (no compiled target known for harness $harness)"
    elif [ "$missing" -eq 1 ]; then
        echo "    target:   $target (missing)"
    else
        echo "    target:   $target"
    fi
    echo "    branch:   $persona/$ISSUE-$slug"
    echo "    brief:    $brief"
    if [ "${#LAUNCH_ARGV[@]}" -gt 0 ]; then
        # printf '%q ' so what is shown is exactly what runs.
        echo "    command:  $(printf '%q ' "${LAUNCH_ARGV[@]}")"
    else
        echo "    command:  none — this harness is started by hand; open the target"
        echo "              above and give it the prompt printed above."
    fi
    if [ -z "$launch_persona" ]; then
        launch_persona="$persona"
        launch_harness="$harness"
        launch_target="$target"
        launch_missing="$missing"
        LAUNCH=( ${LAUNCH_ARGV[@]+"${LAUNCH_ARGV[@]}"} )
    fi
done <<<"$owners"

# --- Launch (or deliberately not) ----------------------------------------------
if [ "$owner_count" -gt 1 ]; then
    # Auto-picking would silently halve a policy whose whole content is
    # that two independent reviewers both look (#2, D4). Name one with
    # --as if that is really what you meant. Nothing was minted and no
    # target was required to exist: a run that launches nothing
    # exchanges nothing (D20).
    echo "==> stage $stage has $owner_count owners; printing both and launching neither."
    echo "    Re-run with --as <persona> to launch exactly one."
    exit 0
fi
if [ "$launch_missing" -eq 1 ]; then
    die "$launch_persona is pinned to $launch_harness but $launch_target does not exist in $REPO_ROOT; run scripts/sync_agents.py and commit the result. Launching without it would silently run the harness's stock agent and exit 0"
fi

# The identity the launched session will act as. The token itself is
# minted below and never printed; this line is the whole of what the
# operator gets to see about it (D11).
identity_of() { # <persona> -> the App login it posts as, or empty
    local file="$PERSONA_DIR/$1.yaml"
    [ -f "$file" ] || return 0
    sed -n 's/^[[:space:]]*identity:[[:space:]]*"\(.*\)".*/\1/p' "$file" | head -1
}
echo "    identity: $(identity_of "$launch_persona") (token minted at launch; not printed)"

if [ "$DRY_RUN" = "1" ]; then
    echo "==> DRY_RUN=1 — nothing was launched, nothing was written, and no token was minted."
    exit 0
fi
if [ "${#LAUNCH[@]}" -eq 0 ]; then
    echo "==> $launch_persona's harness is not one this script starts — printed above."
    exit 0
fi

# The harness binary, checked BEFORE the mint below. Without this the
# run exchanges a one-hour credential for a process that cannot start:
# `exec timeout 5460 agy …` with agy off PATH exits 127 — outside D8's
# 0/1/2 contract — and abandons a live token, which is exactly what
# D11's grounds for minting last forbid. The generic preflight near the
# top cannot do it: which binary is needed is not known until the
# persona, its harness and its --as narrowing have all resolved.
# LAUNCH is ( timeout <seconds> <binary> … ), so index 0 is the wrapper
# and index 2 the harness binary. Both are checked: the generic
# preflight near the top makes exactly this assumption explicit for `gh`
# and `jq`, and an absent `timeout` would fail the same way, 127 with a
# credential already spent (N1).
for _bin in "${LAUNCH[0]}" "${LAUNCH[2]}"; do
    command -v "$_bin" >/dev/null \
        || die "$_bin is not installed, so $launch_persona's $launch_harness session cannot start; nothing was minted"
done

# D16 as amended, clause (c). The interactive row IS the operator's
# terminal; with no tty on stdin or stdout the child cannot start, and
# minting first would abandon a live one-hour credential for a session
# that never ran — precisely what D11's mint-last ordering exists to
# prevent. Exit 1, not 2: like a missing harness binary this is an
# environment that cannot start the row rather than a decision about
# the number, so 2 keeps meaning "not worked, by design" (D23). The
# same guard holds for every other non-TTY caller — the `/work` door,
# cron, a CI step, a subagent's bash.
if [ "$(headless_for "$launch_harness")" != "1" ] \
   && { [ ! -t 0 ] || [ ! -t 1 ]; }; then
    die "$launch_persona's $launch_harness row is interactive and there is no terminal on stdin/stdout; re-run with HEADLESS=1, or from a terminal. Nothing was minted and nothing was launched"
fi

# The persona's own cap in minutes, for the 124 message below (D15 as
# amended). Read before the mint so a bad persona file cannot strand a
# live credential.
launch_mins="$(timeout_mins_of "$launch_persona")"

# --- Identity (#43, D11, D12, D13) ---------------------------------------------
# The last step before the launch, so that every run which prints and
# launches nothing performs no token exchange. A failed mint is FATAL:
# the alternative — warn and fall back to whatever credential the
# operator happens to be carrying — produces exactly the bug this exists
# to fix, a session that posts as the operator while everyone believes a
# persona ran. A launch that cannot be attributed is not a launch.
#
# XTRACE IS SUPPRESSED from here to the launch, and the caller's setting
# restored the moment the child returns (D11 as amended, PR #60, AT-2).
# Bash's xtrace expands both `tok="$(mint …)"` and every `GH_TOKEN="$tok"`
# assignment, so `bash -x scripts/ops/work.sh <n>` would write the live
# installation token to stderr — and a Claude Code session captures tool
# stderr verbatim into an on-disk transcript, a file and a log, the two
# places D11 says the token never reaches. The suppression is a no-op
# when xtrace is off, and `set -x` stays in force everywhere else.
_xtrace_was_on=0
case "$-" in *x*) _xtrace_was_on=1; set +x ;; esac

tok=""
tok="$("$REPO_ROOT/scripts/auth/mint_app_token.py" "$launch_persona")" \
    || die "cannot mint an App token for $launch_persona; refusing to launch as somebody else"
[ -n "$tok" ] \
    || die "the App token minted for $launch_persona is empty; refusing to launch as somebody else"

# git does not read GH_TOKEN, and an installation token lives about an
# hour while odyssey's cap is ninety minutes — so `gh` gets the snapshot
# and `git` gets a helper that re-mints on every call. Both are
# installed through the CHILD's environment only: nothing is written to
# .git/config, so a crashed session leaves no credential configuration
# behind.
#
# The two EMPTY helper values are load-bearing. git collects every
# matching `credential.helper` and `credential.<url>.helper` into ONE
# ordered list and tries them in turn; an empty value clears whatever
# has accumulated so far, and a later entry appends to it. Without a
# reset an operator's global helper (a `gh auth git-credential` entry
# is the common one) is in that list ahead of ours and answers the
# push, so the session pushes as the operator — the exact bug D12
# exists to stop.
#
# Both keys are reset rather than one, and the honest reason is belt
# and braces rather than measurement: GIT_CONFIG_* entries carry
# command-line precedence, so ours would very likely win with a single
# reset. Two resets are idempotent and make ours the only helper in the
# list however the operator configured theirs, on either key. The
# failure this guards against is silent, which is what makes the extra
# pair of variables worth it.
#
# The insteadOf rewrite is load-bearing for a different reason: this
# repository's origin is SSH, and an SSH remote never consults a
# credential helper at all.
CRED_HELPER="$REPO_ROOT/scripts/auth/git-credential-persona"

# ONE install, used by both rows — the four pairs were written twice and
# had to stay byte-identical to be correct. Two properties beyond the
# comment above:
#
#   * the pairs are APPENDED at the caller's own GIT_CONFIG_COUNT rather
#     than written at index 0. An outer launch, or a runner that installs
#     `http.proxy` or `safe.directory` that way, would otherwise have its
#     entries silently replaced and see a push fail for an unrelated
#     reason (PR #60, AT-7). With no inherited set the offset is 0 and
#     the child sees exactly what it saw before.
#   * `export` inside a subshell, never an `env` prefix: `env
#     GH_TOKEN=… ` would put the token in a process's argv, which is
#     world-readable, and D11 forbids exactly that. The assignment
#     prefix this replaces had the same property; a builtin `export`
#     keeps it.
launch_child() { # runs "${LAUNCH[@]}" with the persona's credentials in its env
    local base="${GIT_CONFIG_COUNT:-0}"
    case "$base" in ''|*[!0-9]*) base=0 ;; esac
    (
        export GH_TOKEN="$tok" GITHUB_TOKEN="$tok"
        export "GIT_CONFIG_KEY_$base=credential.helper"
        export "GIT_CONFIG_VALUE_$base="
        export "GIT_CONFIG_KEY_$((base + 1))=credential.https://github.com.helper"
        export "GIT_CONFIG_VALUE_$((base + 1))="
        export "GIT_CONFIG_KEY_$((base + 2))=credential.https://github.com.helper"
        export "GIT_CONFIG_VALUE_$((base + 2))=$CRED_HELPER $launch_persona"
        export "GIT_CONFIG_KEY_$((base + 3))=url.https://github.com/.insteadOf"
        export "GIT_CONFIG_VALUE_$((base + 3))=git@github.com:"
        export GIT_CONFIG_COUNT=$((base + 4))
        exec "${LAUNCH[@]}"
    )
}

# The child starts in the checkout work.sh itself came from. agy is
# pinned with `--add-dir`; claude-code has no such flag and takes the
# working directory as the project, so a launcher invoked by absolute
# path from somewhere else would hand the session a DIFFERENT checkout
# than the one whose personas, labels and targets it just resolved.
# Measured: the first smoke run wrote its artifact into a sibling clone.
cd "$REPO_ROOT"

if [ "$(headless_for "$launch_harness")" != "1" ]; then
    # D15 and D23, both as amended (PR #60, AT-5): the interactive row
    # is NOT `exec`'d. The child runs in the FOREGROUND and inherits
    # stdin, stdout, stderr and the terminal — which is all "the
    # operator's terminal IS the session" ever required; `timeout` was
    # already an un-`exec`'d process between the two, so this costs one
    # process and changes nothing the operator can see. work.sh then
    # waits, maps and exits, so EVERY exit of this script is 0, 1 or 2.
    #
    # The map is two-valued: child 0 → 0; anything non-zero → 1, with
    # the raw status named, and for 124 the cap named too. A timeout is
    # not a new outcome kind — WORK-RESULT is a line the persona prints
    # (D2, D21) and a timed-out session prints nothing — so 124 is the
    # launcher's own observation, the same fact D14 maps to 1 when it
    # arrives headless as status ERROR. A child's status of 2 is never
    # forwarded: exit 2 is PRODUCED by the launcher's own refusals and
    # by D14's parsed refused/blocked, and by nothing else, or the
    # vocabulary #25's adapter branches on could be minted by an
    # unrelated harness's numbering (D23 as amended).
    echo "==> launching: $(printf '%q ' "${LAUNCH[@]}")"
    set +e
    launch_child
    rc=$?
    set -e
    tok=""
    [ "$_xtrace_was_on" = "0" ] || set -x
    if [ "$rc" -eq 0 ]; then
        # Interactive 0 means the session RAN TO COMPLETION, not that
        # the work was done: an in-session refusal is visible to the
        # operator and to the tracker, not to this script.
        exit 0
    elif [ "$rc" -eq 124 ]; then
        echo "==> $launch_persona's session hit the $launch_mins-minute cap (exit 124)." >&2
    else
        echo "==> $launch_persona's session did not complete (exit $rc)." >&2
    fi
    exit 1
fi

echo "==> launching headless: $(printf '%q ' "${LAUNCH[@]}")"
set +e
raw="$(launch_child)"
rc=$?
set -e
tok=""
[ "$_xtrace_was_on" = "0" ] || set -x

# Echoed first, always: nothing a session said is swallowed by the
# mapping that follows.
printf '%s\n' "$raw"

status="$(printf '%s' "$raw" | process_status "$launch_harness" 2>/dev/null)" || status=""
[ -n "$status" ] || status="ERROR"
if [ "$rc" -ne 0 ] || [ "$status" != "SUCCESS" ]; then
    echo "==> $launch_persona's session did not complete (exit $rc, status $status)." >&2
    exit 1
fi

text="$(printf '%s' "$raw" | response_text "$launch_harness" 2>/dev/null)" || text=""
result_line="$(printf '%s\n' "$text" \
    | grep -E '^[[:space:]]*WORK-RESULT:' | tail -1)" || result_line=""
if [ -z "$result_line" ]; then
    # A launcher that returns 0 for an outcome it could not observe is
    # lying, and a session that ran out of turns leaves exactly this
    # trace (D14).
    echo "==> $launch_persona's session exited cleanly but printed no WORK-RESULT line; the outcome was not observed." >&2
    exit 1
fi
verdict="$(printf '%s\n' "$result_line" | awk '{print $2}')"
echo "==> $launch_persona reported: $verdict"
case "$verdict" in
    ok)              exit 0 ;;
    refused|blocked) exit 2 ;;
    *)
        echo "==> '$verdict' is not one of ok|refused|blocked; the outcome was not observed." >&2
        exit 1 ;;
esac
