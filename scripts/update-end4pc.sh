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

# The working tree carries our path rewrites (scripts/patch-end4pc.sh), which
# would make the pull non-fast-forward. Drop them, pull, then re-apply — the
# rewrites are literal-string seds, so they survive upstream moving the lines.
echo ":: Discarding local path patches before pull"
as_user git -C "$REPO_DIR" checkout -- .

echo ":: Updating end4-pC (main branch)"
as_user git -C "$REPO_DIR" pull --ff-only
as_user git -C "$REPO_DIR" submodule update --init --recursive --depth 1

echo ":: Re-applying end4-pC path patches"
bash "$(dirname "$(readlink -f "$0")")/patch-end4pc.sh"

echo ":: end4-pC updated — restart shell with switch-shell.sh end4pc"
