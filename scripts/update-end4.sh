#!/bin/bash
# Update end-4 illogical-impulse shell: pulls latest from the my-ii fork.
set -euo pipefail

# shellcheck source=lib/hook-common.sh disable=SC1091
. "$(dirname "$(readlink -f "$0")")/lib/hook-common.sh" || exit 1

REPO_DIR="$REAL_HOME/.local/share/dots-hyprland"

require_checkout "$REPO_DIR" dots-hyprland setup-end4.sh || exit 1

echo ":: Updating dots-hyprland (my-ii branch)"
fast_forward_pull "$REPO_DIR"
update_submodules "$REPO_DIR"

echo ":: end-4 ii updated — restart shell with switch-shell.sh end4"

# Ensure the hyprland/scripts symlink is correct (may be needed after updates)
HYPR_SCRIPTS_SRC="$REAL_HOME/.config/dcli/dotfiles/hypr/shells/end4/hyprland/scripts"
HYPR_SCRIPTS_DST="$REAL_HOME/.config/hypr/hyprland/scripts"
ensure_symlink "$HYPR_SCRIPTS_SRC" "$HYPR_SCRIPTS_DST" force
