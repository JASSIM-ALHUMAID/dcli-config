#!/bin/bash
# Update end-4 illogical-impulse shell: pulls latest from the my-ii fork.
set -euo pipefail

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

REPO_DIR="$REAL_HOME/.local/share/dots-hyprland"

as_user() {
    if [ "$(id -u)" -eq 0 ] && [ "$REAL_USER" != "root" ]; then
        sudo -u "$REAL_USER" -H "$@"
    else
        "$@"
    fi
}

if [ ! -d "$REPO_DIR/.git" ]; then
    echo "!! dots-hyprland not found at $REPO_DIR — run setup-end4.sh first" >&2
    exit 1
fi

echo ":: Updating dots-hyprland (my-ii branch)"
as_user git -C "$REPO_DIR" pull --ff-only
as_user git -C "$REPO_DIR" submodule update --init --recursive --depth 1

echo ":: end-4 ii updated — restart shell with switch-shell.sh end4"
