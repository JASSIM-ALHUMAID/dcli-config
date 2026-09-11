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
# So we install the fork's extra deps ourselves, as regular packages, and the ii
# config runs on whichever provider is enabled. See docs/PACKAGE-CONFLICTS.md
# and docs/shells/end4.md.
#
# Layout this script produces:
#   ~/.local/share/dots-hyprland   — my-ii fork checkout on branch my-ii (source of truth)
#                                    origin = plusdrag11/dots-hyprland, upstream = end-4/dots-hyprland
#   ~/.config/quickshell/ii        — symlink -> dots-hyprland/dots/.config/quickshell/ii
#   ~/.config/matugen              — symlink -> dots-hyprland/dots/.config/matugen
#   ~/.config/hypr/hyprland/scripts — symlink -> dcli/dotfiles/hypr/shells/end4/hyprland/scripts
#
# Note: the ii shell also writes its own state to
# ~/.config/illogical-impulse at runtime — nothing to do for that.
#
# Safe to re-run: it never clones over an existing setup, and skips
# symlinks that are already correct.
set -euo pipefail

# dcli may run hooks as root — always operate on the real user's home.
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

REPO_URL="https://github.com/plusdrag11/dots-hyprland.git"
UPSTREAM_URL="https://github.com/end-4/dots-hyprland.git"
REPO_BRANCH="my-ii"
REPO_DIR="$REAL_HOME/.local/share/dots-hyprland"
II_QS="$REAL_HOME/.config/quickshell/ii"
MATUGEN_CONF="$REAL_HOME/.config/matugen"

as_user() {
    if [ "$(id -u)" -eq 0 ] && [ "$REAL_USER" != "root" ]; then
        sudo -u "$REAL_USER" -H "$@"
    else
        "$@"
    fi
}

# Clone the my-ii fork only if the user opts in. Non-interactive shells skip
# silently (the user can re-run via `dcli module run-hook shell-end4` later).
if [ -d "$REPO_DIR/.git" ]; then
    echo ":: dots-hyprland already cloned at $REPO_DIR"
else
    if [ -e "$REPO_DIR" ]; then
        echo "!! $REPO_DIR exists but is not a git repo — refusing to touch it." >&2
        exit 1
    fi
    reply=""
    if [ -t 0 ]; then
        read -r -p ":: my-ii fork not found at $REPO_DIR. Clone it? [y/N] " reply
    fi
    case "$reply" in
        y|Y|yes|YES) ;;
        *)
            echo ":: Skipping my-ii fork setup (no clone). Re-run later with:"
            echo "     dcli module run-hook shell-end4"
            exit 0
            ;;
    esac
    echo ":: Cloning my-ii fork (branch $REPO_BRANCH)"
    as_user mkdir -p "$(dirname "$REPO_DIR")"
    as_user git clone --branch "$REPO_BRANCH" --recurse-submodules --shallow-submodules "$REPO_URL" "$REPO_DIR"
    as_user git -C "$REPO_DIR" remote add upstream "$UPSTREAM_URL"
fi
# Ensure submodules exist even on a pre-existing clone.
as_user git -C "$REPO_DIR" submodule update --init --recursive --depth 1

# 2) Install runtime dependencies.
#
# Extra Qt deps (from illogical-impulse-quickshell-git PKGBUILD):
QT_DEPS=(qt6-5compat qt6-imageformats qt6-multimedia
         qt6-positioning qt6-quicktimeline qt6-sensors qt6-svg qt6-tools
         qt6-translations qt6-virtualkeyboard qt6-wayland kirigami kdialog
         syntax-highlighting)

# AUR-only deps (not in official/distribution repos) — installed via paru as the
# real user (AUR helpers refuse to run as root); skipped if paru is missing.
AUR_DEPS=(qt6-avif-image-plugin songrec)

# Runtime tools (curated from illogical-impulse-basic/audio/toolkit/widgets/
# screencapture PKGBUILDs):
RUNTIME_DEPS=(bc cliphist jq go-yq cava pavucontrol-qt playerctl upower
              wtype ydotool fuzzel imagemagick hypridle hyprlock hyprpicker
              translate-shell wlogout libqalculate hyprshot slurp swappy
              tesseract tesseract-data-eng wf-recorder hyprsunset wl-clipboard)

# Deliberately skipped:
#   - illogical-impulse-* meta packages themselves (local PKGBUILDs, not needed)
#   - xdg-desktop-portal-kde/gtk (already handled elsewhere)
#   - python/uv toolchain (only needed for end-4's own installer)

ALL_DEPS=("${QT_DEPS[@]}" "${RUNTIME_DEPS[@]}")
echo ":: Installing end-4 ii runtime dependencies"
if [ "$(id -u)" -eq 0 ]; then
    pacman -S --needed --noconfirm "${ALL_DEPS[@]}"
else
    sudo pacman -S --needed --noconfirm "${ALL_DEPS[@]}"
fi

if as_user command -v paru >/dev/null 2>&1; then
    echo ":: Installing AUR deps via paru"
    as_user paru -S --needed --noconfirm "${AUR_DEPS[@]}"
else
    echo ":: paru not found — skipping AUR deps: ${AUR_DEPS[*]}"
fi

# 3) Symlink ~/.config/quickshell/ii -> checkout.
II_SRC="$REPO_DIR/dots/.config/quickshell/ii"
if [ -L "$II_QS" ] && [ "$(readlink -f "$II_QS")" = "$(readlink -f "$II_SRC")" ]; then
    echo ":: ~/.config/quickshell/ii already linked"
else
    if [ -e "$II_QS" ]; then
        echo "!! $II_QS exists and is not a correct symlink — refusing to clobber." >&2
        exit 1
    fi
    as_user mkdir -p "$(dirname "$II_QS")"
    as_user ln -s "$II_SRC" "$II_QS"
    echo ":: Symlinked $II_QS -> $II_SRC"
fi

# 4) Symlink ~/.config/matugen -> checkout (ii's theming reads it).
MATUGEN_SRC="$REPO_DIR/dots/.config/matugen"
if [ -L "$MATUGEN_CONF" ] && [ "$(readlink -f "$MATUGEN_CONF")" = "$(readlink -f "$MATUGEN_SRC")" ]; then
    echo ":: ~/.config/matugen already linked"
else
    if [ -e "$MATUGEN_CONF" ]; then
        echo "!! $MATUGEN_CONF exists and is not a correct symlink — refusing to clobber." >&2
        exit 1
    fi
    as_user ln -s "$MATUGEN_SRC" "$MATUGEN_CONF"
    echo ":: Symlinked $MATUGEN_CONF -> $MATUGEN_SRC"
fi

echo ":: end-4 ii shell ready — launch with 'qs -c ii', switch with switch-shell.sh end4"

# 5) Symlink hyprland/scripts -> our dotfiles scripts so the upstream
#    keybinds.lua (which references $HOME/.config/hypr/hyprland/scripts)
#    can find them.
HYPR_SCRIPTS_SRC="$REAL_HOME/.config/dcli/dotfiles/hypr/shells/end4/hyprland/scripts"
HYPR_SCRIPTS_DST="$REAL_HOME/.config/hypr/hyprland/scripts"
if [ -L "$HYPR_SCRIPTS_DST" ] && [ "$(readlink -f "$HYPR_SCRIPTS_DST")" = "$(readlink -f "$HYPR_SCRIPTS_SRC")" ]; then
    echo ":: ~/.config/hypr/hyprland/scripts already linked"
else
    as_user mkdir -p "$(dirname "$HYPR_SCRIPTS_DST")"
    as_user ln -sfn "$HYPR_SCRIPTS_SRC" "$HYPR_SCRIPTS_DST"
    echo ":: Symlinked $HYPR_SCRIPTS_DST -> $HYPR_SCRIPTS_SRC"
fi
