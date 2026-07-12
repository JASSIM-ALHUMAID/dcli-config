#!/bin/bash
# DEPRECATED: This script is superseded by the repo's own sync-live.sh.
#
# For day-to-day use, run from the repo root:
#   ./scripts/sync-live.sh
#
# For C++ plugin changes:
#   scripts/install.sh --skip-sddm
#
# This wrapper is kept for backwards compatibility — it delegates to sync-live.sh.
set -euo pipefail

REPO_DIR="${CAELESTIA_DEV:-$HOME/Projects/shell/real}"

if [ ! -d "$REPO_DIR/.git" ]; then
    echo "!! Repo not found at $REPO_DIR" >&2
    echo "   Run: dcli module run-hook caelestia" >&2
    exit 1
fi

echo ":: Delegating to $REPO_DIR/scripts/sync-live.sh"
exec "$REPO_DIR/scripts/sync-live.sh" "$@"
