#!/bin/bash
# Bootstrap end-4 dots-hyprland (illogical-impulse) shell.
#
# CRITICAL: upstream's illogical-impulse-quickshell-git package has
# Conflicts=quickshell and would remove the stock quickshell needed by
# the caelestia and dms shells (same trap as noctalia-qs — see README.md).
# So we do NOT install it; the ii config runs on stock quickshell with
# the fork's extra deps installed as regular packages.
#
# Layout this script produces:
#   ~/.local/share/dots-hyprland   — the end-4/dots-hyprland checkout (source of truth)
#   ~/.config/quickshell/ii        — symlink -> dots-hyprland/dots/.config/quickshell/ii
#   ~/.config/matugen              — symlink -> dots-hyprland/dots/.config/matugen
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

REPO_URL="https://github.com/end-4/dots-hyprland.git"
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

# 1) Clone end-4/dots-hyprland (shallow, with submodules — the ii shell's
#    modules/common/widgets/shapes is a submodule and the shell fails to
#    load without it: "module qs.modules.common.widgets.shapes is not installed").
if [ -d "$REPO_DIR/.git" ]; then
    echo ":: dots-hyprland already cloned at $REPO_DIR"
else
    if [ -e "$REPO_DIR" ]; then
        echo "!! $REPO_DIR exists but is not a git repo — refusing to touch it." >&2
        exit 1
    fi
    echo ":: Cloning end-4/dots-hyprland (shallow)"
    as_user mkdir -p "$(dirname "$REPO_DIR")"
    as_user git clone --depth 1 --recurse-submodules --shallow-submodules "$REPO_URL" "$REPO_DIR"
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

# AUR-only deps (not in official/CachyOS repos) — installed via paru as the
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
