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

# Ensure the hyprland/scripts symlink is correct (may be needed after updates)
HYPR_SCRIPTS_SRC="$REAL_HOME/.config/dcli/dotfiles/hypr/shells/end4/hyprland/scripts"
HYPR_SCRIPTS_DST="$REAL_HOME/.config/hypr/hyprland/scripts"
if [ -L "$HYPR_SCRIPTS_DST" ] && [ "$(readlink -f "$HYPR_SCRIPTS_DST")" = "$(readlink -f "$HYPR_SCRIPTS_SRC")" ]; then
    echo ":: ~/.config/hypr/hyprland/scripts already linked"
else
    as_user mkdir -p "$(dirname "$HYPR_SCRIPTS_DST")"
    as_user ln -sfn "$HYPR_SCRIPTS_SRC" "$HYPR_SCRIPTS_DST"
    echo ":: Symlinked $HYPR_SCRIPTS_DST -> $HYPR_SCRIPTS_SRC"
fi
