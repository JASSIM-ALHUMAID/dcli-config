#!/bin/bash
# Bootstrap end-4 dots-hyprland (illogical-impulse) shell.
#
# CRITICAL: never run end-4's own dependency installer
# (sdata/dist-arch/install-deps.sh). Two reasons, both verified in the checkout:
#   - line 96 builds and installs the illogical-impulse-quickshell-git metapkg,
#     a FOURTH mutually-exclusive quickshell provider (Conflicts=quickshell) that
#     would fight the one owned by modules/shells-quickshell{,-git}.yaml;
#   - line 20 replaces the whole hypr stack (hyprland, hyprlock, hypridle,
#     xdg-desktop-portal-hyprland, ...) with -git builds.
# So the fork's extra deps are declared as regular packages in
# modules/shell-end4.yaml (re-checked on every sync), and the ii config runs on
# whichever provider is enabled. See docs/PACKAGE-CONFLICTS.md and
# docs/shells/end4.md.
#
# Layout this script produces:
#   ~/.local/share/dots-hyprland   — my-ii fork checkout on branch my-ii (source of truth)
#                                    origin = JASSIM-ALHUMAID/my-end4, upstream = end-4/dots-hyprland
#   ~/.config/quickshell/ii        — symlink -> dots-hyprland/dots/.config/quickshell/ii
#   ~/.config/matugen-end4         — symlink -> dots-hyprland/dots/.config/matugen
#                                    (NOT ~/.config/matugen: that is ryoku's —
#                                    see step 3)
#   ~/.config/hypr/hyprland/scripts — symlink -> dcli/dotfiles/hypr/shells/end4/hyprland/scripts
#
# Note: the ii shell also writes its own state to
# ~/.config/illogical-impulse at runtime — nothing to do for that.
#
# Safe to re-run: it never clones over an existing setup, and skips
# symlinks that are already correct.
set -euo pipefail

# shellcheck source=lib/hook-common.sh disable=SC1091
. "$(dirname "$(readlink -f "$0")")/lib/hook-common.sh" || exit 1

REPO_URL="https://github.com/JASSIM-ALHUMAID/my-end4.git"
UPSTREAM_URL="https://github.com/end-4/dots-hyprland.git"
REPO_BRANCH="my-ii"
REPO_DIR="$REAL_HOME/.local/share/dots-hyprland"
II_QS="$REAL_HOME/.config/quickshell/ii"
MATUGEN_CONF="$REAL_HOME/.config/matugen-end4"
LEGACY_MATUGEN_CONF="$REAL_HOME/.config/matugen"
HYPR_SCRIPTS_SRC="$REAL_HOME/.config/dcli/dotfiles/hypr/shells/end4/hyprland/scripts"
HYPR_SCRIPTS_DST="$REAL_HOME/.config/hypr/hyprland/scripts"

# 1) Clone the my-ii fork only if the user opts in; non-interactive shells skip
#    silently (re-run via `dcli module run-hook shell-end4`).
clone_checkout "$REPO_DIR" "$REPO_URL" "$REPO_BRANCH" "my-ii fork" --opt-in shell-end4 \
    --recurse-submodules --shallow-submodules
if [ "$CLONED_NOW" -eq 1 ]; then
    as_user git -C "$REPO_DIR" remote add upstream "$UPSTREAM_URL"
fi
# Ensure submodules exist even on a pre-existing clone.
update_submodules "$REPO_DIR"

# 2) Symlink ~/.config/quickshell/ii -> checkout.
ensure_symlink "$REPO_DIR/dots/.config/quickshell/ii" "$II_QS" refuse || exit 1

# 3) Symlink ~/.config/matugen-end4 -> checkout (ii's switchwall.sh passes it
#    to matugen with -c). Until 2026-10-31 ii used the default ~/.config/matugen;
#    ryoku's daemon reads that default path directly, so every ryoku wallpaper
#    change rendered ii's templates (fuzzel, GTK, ii's palette). The my-ii fork
#    moved, and the old link — only if it still points into this checkout — is
#    released here so setup-ryoku.sh can claim the path.
if [ -L "$LEGACY_MATUGEN_CONF" ] && \
    [ "$(readlink -f "$LEGACY_MATUGEN_CONF")" = "$(readlink -f "$REPO_DIR/dots/.config/matugen")" ]; then
    as_user rm "$LEGACY_MATUGEN_CONF"
    echo ":: Released ~/.config/matugen (ii now uses ~/.config/matugen-end4)"
fi
ensure_symlink "$REPO_DIR/dots/.config/matugen" "$MATUGEN_CONF" refuse || exit 1

echo ":: end-4 ii shell ready — launch with 'qs -c ii', switch with switch-shell.sh end4"

# 4) Symlink hyprland/scripts -> our dotfiles scripts so the upstream
#    keybinds.lua (which references $HOME/.config/hypr/hyprland/scripts)
#    can find them.
ensure_symlink "$HYPR_SCRIPTS_SRC" "$HYPR_SCRIPTS_DST" force
