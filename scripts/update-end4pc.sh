#!/bin/bash
# Update the end4-pC shell: pulls latest from pctrade/end4-pC (branch main).
set -euo pipefail

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

REPO_DIR="$REAL_HOME/.local/share/end4-pC"

as_user() {
    if [ "$(id -u)" -eq 0 ] && [ "$REAL_USER" != "root" ]; then
        sudo -u "$REAL_USER" -H "$@"
    else
        "$@"
    fi
}

if [ ! -d "$REPO_DIR/.git" ]; then
    echo "!! end4-pC not found at $REPO_DIR — run setup-end4pc.sh first" >&2
    exit 1
fi

echo ":: Updating end4-pC (main branch)"
as_user git -C "$REPO_DIR" pull --ff-only
as_user git -C "$REPO_DIR" submodule update --init --recursive --depth 1

echo ":: end4-pC updated — restart shell with switch-shell.sh end4pc"
