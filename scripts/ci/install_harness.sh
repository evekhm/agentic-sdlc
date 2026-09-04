#!/usr/bin/env bash
# Put BOTH harness binaries on a fresh machine (#146), the same way on a
# GitHub-hosted runner and on a laptop that has neither:
#
#   scripts/ci/install_harness.sh resolve   # print the versions that WOULD be installed
#   scripts/ci/install_harness.sh install   # install whatever is missing or at another version
#   scripts/ci/install_harness.sh check     # exit 1 naming every binary that is not usable
#
# Why both, always. `.github/workflows/unattended.yml` is the trigger and
# never the runtime: it does not know, and must not learn, which harness
# a persona is pinned to (config/deployments.yaml, read by work.sh at
# dispatch). A runner that installed only "the right one" would need
# that answer, which is the second place to edit that D18 prices at one
# line. Installing both costs one cache restore per run and keeps the
# workflow harness-blind.
#
# Why this file and not two curl lines in the workflow. The same three
# verbs run in CI, in scripts/ops/tests/placement_test.sh, and by an
# operator reproducing the runner on a new machine; a runbook line that
# lives only in YAML is untestable and unreproducible. Everything the
# workflow does about harness binaries is a call into here.
#
# Versions.
#   agy    — the vendor publishes no pin; the version is whatever the
#            auto-updater manifest says today, read the way the reference
#            deployment reads it (agentic-experiments-lab,
#            scripts/ci/resolve_agy_version.sh). `resolve` prints it so
#            the cache key can name it BEFORE the install step runs.
#   claude — pinned to CLAUDE_CODE_VERSION (default below), passed to the
#            official installer, which accepts `stable`, `latest` or an
#            exact version. Pinned because a run must be reproducible and
#            because the cache key is computed before anything is
#            downloaded. Bump the default here and nowhere else; the
#            default is the version the presenter's machine runs, i.e.
#            the one every local test already passed on.
#
# Both binaries land under $HOME/.local/bin, which is what the workflow
# caches and appends to GITHUB_PATH. Nothing here names a model, a tier,
# a persona or a cost (D8, D15) — this is the toolchain, not a dispatch.

set -euo pipefail

CLAUDE_CODE_VERSION="${CLAUDE_CODE_VERSION:-2.1.261}"
AGY_MANIFEST_URL="${AGY_MANIFEST_URL:-https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/linux_amd64.json}"
AGY_INSTALL_URL="${AGY_INSTALL_URL:-https://antigravity.google/cli/install.sh}"
CLAUDE_INSTALL_URL="${CLAUDE_INSTALL_URL:-https://claude.ai/install.sh}"

BIN_DIR="$HOME/.local/bin"
export PATH="$BIN_DIR:$PATH"

die() { echo "install_harness: $*" >&2; exit 1; }

usage() { die "usage: $(basename "$0") resolve|install|check"; }

# The manifest is the only place the current agy version is published.
# Retried because a cold CDN edge answers the first request with a 5xx
# often enough to have been seen (reference, resolve_agy_version.sh).
resolve_agy() {
    local v
    v="$(curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors "$AGY_MANIFEST_URL" \
            | jq -r '.version // empty')" \
        || die "could not read the agy manifest at $AGY_MANIFEST_URL"
    [ -n "$v" ] || die "the agy manifest at $AGY_MANIFEST_URL carries no .version"
    printf '%s\n' "$v"
}

# What is on this machine, or empty. `--version` output shapes differ:
# agy prints the bare version, claude prints `<version> (Claude Code)`;
# the first whitespace-delimited token is the version in both.
installed_version() { # <binary>
    local bin="$1" out
    command -v "$bin" >/dev/null 2>&1 || return 0
    out="$("$bin" --version 2>/dev/null | head -n 1)" || return 0
    printf '%s\n' "${out%% *}"
}

cmd_resolve() {
    printf 'agy=%s\n' "$(resolve_agy)"
    printf 'claude=%s\n' "$CLAUDE_CODE_VERSION"
}

cmd_install() {
    local want have
    mkdir -p "$BIN_DIR"

    want="$(resolve_agy)"
    have="$(installed_version agy)"
    if [ "$have" = "$want" ]; then
        echo "agy $want already installed"
    else
        echo "installing agy $want${have:+ (replacing $have)}"
        curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors "$AGY_INSTALL_URL" | bash
        have="$(installed_version agy)"
        # The vendor installer takes no version argument: it ships what
        # the manifest names. A mismatch here means the manifest moved
        # between `resolve` and this step; the cache key is then wrong for
        # what was installed, and the next run must not restore it.
        [ "$have" = "$want" ] \
            || die "agy installed as '$have' but the manifest resolved '$want'; re-run so the cache key matches"
    fi

    want="$CLAUDE_CODE_VERSION"
    have="$(installed_version claude)"
    if [ "$have" = "$want" ]; then
        echo "claude $want already installed"
    else
        echo "installing claude $want${have:+ (replacing $have)}"
        curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors "$CLAUDE_INSTALL_URL" \
            | bash -s "$want"
        have="$(installed_version claude)"
        [ "$have" = "$want" ] \
            || die "claude installed as '$have' but $want was requested"
    fi
}

cmd_check() {
    local missing=() bin v
    for bin in claude agy; do
        v="$(installed_version "$bin")"
        if [ -n "$v" ]; then
            echo "$bin $v ($(command -v "$bin"))"
        else
            missing+=( "$bin" )
        fi
    done
    [ "${#missing[@]}" -eq 0 ] \
        || die "not usable on this machine: ${missing[*]}; run '$(basename "$0") install'"
}

[ "$#" -eq 1 ] || usage
case "$1" in
    resolve) cmd_resolve ;;
    install) cmd_install ;;
    check)   cmd_check ;;
    *)       usage ;;
esac
