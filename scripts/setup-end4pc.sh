#!/bin/bash
# Bootstrap the end4-pC shell — pctrade's fork of end-4 dots-hyprland
# (illogical-impulse). Runs alongside the existing "end4" (ii) shell as a
# separate, independent quickshell config named "end4-pC".
#
# CRITICAL: like end-4's illogical-impulse-quickshell-git, we do NOT install
# any packaged quickshell fork — that would Conflicts=quickshell and remove the
# stock quickshell caelestia/dms need (see README.md). The config runs on stock
# quickshell with the fork's extra deps installed as regular packages.
#
# This shell's deps are the SAME set as setup-end4.sh installs; we duplicate
# them here (all --needed, so it's a no-op when shell-end4 already ran) so that
# end4-pC stands on its own if shell-end4 is disabled.
#
# Layout this script produces:
#   ~/.local/share/end4-pC         — pctrade/end4-pC checkout on branch main
#                                    (source of truth). The repo root IS the
#                                    quickshell config (flat layout — no
#                                    dots/.config/... wrapper like the ii fork).
#   ~/.config/quickshell/end4-pC   — symlink -> the checkout root
#
# No matugen symlink: end4-pC ships no matugen config and reuses the shared
# ~/.config/matugen owned by the ii (end4) checkout.
#
# The shell also writes its own runtime state under ~/.config (e.g.
# ~/.config/illogical-impulse) — nothing to do for that.
#
# Safe to re-run: it never clones over an existing setup, and skips symlinks
# that are already correct.
set -euo pipefail

# dcli may run hooks as root — always operate on the real user's home.
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

REPO_URL="https://github.com/pctrade/end4-pC.git"
REPO_BRANCH="main"
REPO_DIR="$REAL_HOME/.local/share/end4-pC"
QS_CONF="$REAL_HOME/.config/quickshell/end4-pC"

as_user() {
    if [ "$(id -u)" -eq 0 ] && [ "$REAL_USER" != "root" ]; then
        sudo -u "$REAL_USER" -H "$@"
    else
        "$@"
    fi
}

# 1) Clone the fork on branch main (full clone; submodules stay shallow. The
#    config has a .gitmodules and, like the ii fork, fails to load without its
#    submodules populated).
if [ -d "$REPO_DIR/.git" ]; then
    echo ":: end4-pC already cloned at $REPO_DIR"
else
    if [ -e "$REPO_DIR" ]; then
        echo "!! $REPO_DIR exists but is not a git repo — refusing to touch it." >&2
        exit 1
    fi
    echo ":: Cloning end4-pC (branch $REPO_BRANCH)"
    as_user mkdir -p "$(dirname "$REPO_DIR")"
    as_user git clone --branch "$REPO_BRANCH" --recurse-submodules --shallow-submodules "$REPO_URL" "$REPO_DIR"
fi
# Ensure submodules exist even on a pre-existing clone.
as_user git -C "$REPO_DIR" submodule update --init --recursive --depth 1

# 2) Install runtime dependencies (same set as setup-end4.sh; --needed so this
#    is a no-op when the ii shell already installed them).
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

ALL_DEPS=("${QT_DEPS[@]}" "${RUNTIME_DEPS[@]}")
echo ":: Installing end4-pC runtime dependencies"
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

# 3) Symlink ~/.config/quickshell/end4-pC -> checkout root (the repo IS the config).
if [ -L "$QS_CONF" ] && [ "$(readlink -f "$QS_CONF")" = "$(readlink -f "$REPO_DIR")" ]; then
    echo ":: ~/.config/quickshell/end4-pC already linked"
else
    if [ -e "$QS_CONF" ]; then
        echo "!! $QS_CONF exists and is not a correct symlink — refusing to clobber." >&2
        exit 1
    fi
    as_user mkdir -p "$(dirname "$QS_CONF")"
    as_user ln -s "$REPO_DIR" "$QS_CONF"
    echo ":: Symlinked $QS_CONF -> $REPO_DIR"
fi

echo ":: end4-pC shell ready — launch with 'qs -c end4-pC', switch with switch-shell.sh end4pc"
