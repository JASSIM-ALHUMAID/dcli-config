#!/bin/bash
# Update the omarchy shell: pulls latest from basecamp/omarchy (branch quattro).
#
# There is no personal fork and the checkout carries no local patches — the
# customisations live in this repo (dotfiles/hypr/shells/omarchy/hyprland.lua)
# and in ~/.config/omarchy — so this is a plain fast-forward. If it refuses,
# something wrote into the checkout and that is worth looking at before forcing.
#
# v4.0 is alpha and moves daily; expect to run this often.
set -euo pipefail

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

REPO_DIR="$REAL_HOME/.local/share/omarchy"

as_user() {
    if [ "$(id -u)" -eq 0 ] && [ "$REAL_USER" != "root" ]; then
        sudo -u "$REAL_USER" -H "$@"
    else
        "$@"
    fi
}

if [ ! -d "$REPO_DIR/.git" ]; then
    echo "!! omarchy not found at $REPO_DIR — run setup-omarchy.sh first" >&2
    exit 1
fi

if [ -n "$(as_user git -C "$REPO_DIR" status --porcelain)" ]; then
    echo "!! $REPO_DIR has local changes — refusing to pull:" >&2
    as_user git -C "$REPO_DIR" status --short >&2
    exit 1
fi

before=$(as_user git -C "$REPO_DIR" rev-parse HEAD)

echo ":: Updating omarchy (quattro branch)"
as_user git -C "$REPO_DIR" pull --ff-only

after=$(as_user git -C "$REPO_DIR" rev-parse HEAD)

if [ "$before" = "$after" ]; then
    echo ":: Already up to date ($(as_user cat "$REPO_DIR/version"))"
    exit 0
fi

echo ":: Updated to $(as_user cat "$REPO_DIR/version"):"
as_user git -C "$REPO_DIR" log --oneline "$before..$after"

# Upstream ships migrations for things installed by install.sh (system units,
# /etc files). We do not run them — see setup-omarchy.sh — but a migration that
# touches the shell or its Hyprland defaults is worth reading.
if as_user git -C "$REPO_DIR" diff --name-only "$before..$after" | grep -qE '^(migrations|install)/'; then
    echo "!! This update touched migrations/ or install/ — check whether any of it"
    echo "   applies to a checkout-only setup before assuming the shell is fine."
fi

echo ":: omarchy updated — restart the shell with switch-shell.sh omarchy"
