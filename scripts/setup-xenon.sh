#!/bin/bash
# Bootstrap the xenon shell — MannuVilasara/xenon-shell, a Quickshell config
# run as an independent config named "xenon".
#
# No personal fork: cloned straight from upstream (branch main), like end4-pC
# and omarchy.
#
# Layout this script produces:
#   ~/.local/share/xenon-shell    — upstream checkout on branch main (source of
#                                   truth). The repo root IS the quickshell
#                                   config: shell.qml sits at the top level,
#                                   same flat layout as end4-pC.
#   ~/.config/quickshell/xenon    — symlink -> the checkout root
#
# ~/.config/xenon (config.json) is NOT created here: it is a dcli-tracked
# dotfile, linked by scripts/link-dotfiles.sh. Generated state lives in
# ~/.cache/xenon and is machine-local.
#
# /etc/xdg/quickshell/xenon is a pre-existing ROOT-OWNED clone that no package
# owns. It is deliberately left untouched: quickshell resolves configs from
# XDG_CONFIG_HOME first, so ~/.config/quickshell/xenon shadows it for the user
# session. Nothing in this script writes to /etc.
#
# CRITICAL: no quickshell provider package is declared anywhere for this shell.
# The provider has exactly one owner — modules/shells-quickshell{,-git}.yaml —
# and xenon runs on whichever one is enabled. See docs/PACKAGE-CONFLICTS.md.
#
# Safe to re-run: it never clones over an existing checkout and skips symlinks
# that are already correct.
set -euo pipefail

# dcli may run hooks as root — always operate on the real user's home.
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

REPO_URL="https://github.com/MannuVilasara/xenon-shell.git"
REPO_BRANCH="main"
REPO_DIR="$REAL_HOME/.local/share/xenon-shell"
QS_CONF="$REAL_HOME/.config/quickshell/xenon"

as_user() {
    if [ "$(id -u)" -eq 0 ] && [ "$REAL_USER" != "root" ]; then
        sudo -u "$REAL_USER" -H "$@"
    else
        "$@"
    fi
}

# 1) Clone upstream on branch main. No submodules — the repo has none.
if [ -d "$REPO_DIR/.git" ]; then
    echo ":: xenon-shell already cloned at $REPO_DIR"
else
    if [ -e "$REPO_DIR" ]; then
        echo "!! $REPO_DIR exists but is not a git repo — refusing to touch it." >&2
        exit 1
    fi
    echo ":: Cloning xenon-shell (branch $REPO_BRANCH)"
    as_user mkdir -p "$(dirname "$REPO_DIR")"
    as_user git clone --branch "$REPO_BRANCH" "$REPO_URL" "$REPO_DIR"
fi

# 2) Runtime dependencies (upstream README + what the QML actually execs).
#    Scripts/*.py are stdlib-only, so there is no pip step.
#
#    openrgb is deliberately NOT installed: it is only used when the
#    openRgbDevices key is set in ~/.config/xenon/config.json, and it is
#    hardware-specific. See docs/shells/xenon.md.
RUNTIME_DEPS=(python imagemagick brightnessctl cliphist wl-clipboard
              ttf-jetbrains-mono-nerd ttf-nerd-fonts-symbols papirus-icon-theme)

echo ":: Installing xenon runtime dependencies"
if [ "$(id -u)" -eq 0 ]; then
    pacman -S --needed --noconfirm "${RUNTIME_DEPS[@]}"
else
    sudo pacman -S --needed --noconfirm "${RUNTIME_DEPS[@]}"
fi

# 3) Symlink ~/.config/quickshell/xenon -> checkout root (the repo IS the config).
if [ -L "$QS_CONF" ] && [ "$(readlink -f "$QS_CONF")" = "$(readlink -f "$REPO_DIR")" ]; then
    echo ":: ~/.config/quickshell/xenon already linked"
else
    if [ -e "$QS_CONF" ]; then
        echo "!! $QS_CONF exists and is not a correct symlink — refusing to clobber." >&2
        exit 1
    fi
    as_user mkdir -p "$(dirname "$QS_CONF")"
    as_user ln -s "$REPO_DIR" "$QS_CONF"
    echo ":: Symlinked $QS_CONF -> $REPO_DIR"
fi

echo ":: xenon shell ready — launch with 'qs -c xenon', switch with switch-shell.sh xenon"
