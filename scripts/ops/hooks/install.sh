#!/usr/bin/env bash
# Installs this repo's git hooks into the shared hooks directory
# (`git rev-parse --git-common-dir`, one location for the primary
# checkout and every linked worktree). Idempotent: safe to re-run.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
HOOKS_DIR="$(git -C "$REPO_ROOT" rev-parse --git-common-dir)/hooks"
mkdir -p "$HOOKS_DIR"

for hook in "$REPO_ROOT"/scripts/ops/hooks/*; do
    name="$(basename "$hook")"
    [ "$name" = "install.sh" ] && continue
    cp "$hook" "$HOOKS_DIR/$name"
    chmod +x "$HOOKS_DIR/$name"
    echo "installed: $HOOKS_DIR/$name"
done
