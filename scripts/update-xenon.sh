#!/bin/bash
# Update the xenon shell: pulls latest from MannuVilasara/xenon-shell (main).
#
# Nothing in this repo patches the checkout (unlike end4-pC), and the shell
# writes its own state to ~/.config/xenon and ~/.cache/xenon — so the working
# tree stays clean and a plain fast-forward is enough.
set -euo pipefail

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

REPO_DIR="$REAL_HOME/.local/share/xenon-shell"

as_user() {
    if [ "$(id -u)" -eq 0 ] && [ "$REAL_USER" != "root" ]; then
        sudo -u "$REAL_USER" -H "$@"
    else
        "$@"
    fi
}

if [ ! -d "$REPO_DIR/.git" ]; then
    echo "!! xenon-shell not found at $REPO_DIR — run setup-xenon.sh first" >&2
    exit 1
fi

echo ":: Updating xenon-shell (main branch)"
as_user git -C "$REPO_DIR" pull --ff-only

echo ":: xenon-shell updated — restart shell with switch-shell.sh xenon"
