#!/bin/bash
# Bootstrap my custom Caelestia shell (fork of caelestia-dots/shell).
# origin = plusdrag11/caelestia, upstream = caelestia-dots/shell
#
# Layout this script produces:
#   ~/Projects/shell/real              — the fork checkout (source of truth)
#   ~/.config/quickshell/caelestia     — built QML config (overrides /etc/xdg)
#   ~/.config/caelestia                — symlink -> fork/caelestia-configs
#
# After setup, use the repo's own scripts:
#   ./scripts/sync-live.sh             — sync QML + restart shell
#   scripts/install.sh --skip-sddm    — rebuild C++ plugin
#
# Safe to re-run: it never clones over or rebuilds an existing setup.
set -euo pipefail

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

REPO_URL="https://github.com/plusdrag11/caelestia.git"
UPSTREAM_URL="https://github.com/caelestia-dots/shell.git"
REPO_DIR="${CAELESTIA_DEV:-$REAL_HOME/Projects/shell/real}"
QS_CONF="$REAL_HOME/.config/quickshell/caelestia"
CAEL_CONF="$REAL_HOME/.config/caelestia"

as_user() {
    if [ "$(id -u)" -eq 0 ] && [ "$REAL_USER" != "root" ]; then
        sudo -u "$REAL_USER" -H "$@"
    else
        "$@"
    fi
}

# Starship: the live config is ~/starship.toml (regenerated from the fork's
# starship.toml.template by starship-theme.py on every wallpaper/theme change);
# ~/.config/starship.toml must be a symlink to it. Seed the file from the
# fork's snapshot so the prompt works before the first theme change.
ensure_starship() {
    if [ ! -f "$REAL_HOME/starship.toml" ] && [ -f "$CAEL_CONF/starship.toml" ]; then
        as_user cp "$CAEL_CONF/starship.toml" "$REAL_HOME/starship.toml"
        echo ":: Seeded ~/starship.toml from the fork (regenerates on first theme change)"
    fi
    if [ ! -e "$REAL_HOME/.config/starship.toml" ] && [ -f "$REAL_HOME/starship.toml" ]; then
        as_user ln -s "$REAL_HOME/starship.toml" "$REAL_HOME/.config/starship.toml"
        echo ":: Symlinked ~/.config/starship.toml -> ~/starship.toml"
    fi
}

# Already fully set up?
if [ -d "$REPO_DIR/.git" ] && [ -e "$QS_CONF/shell.qml" ] && [ -L "$CAEL_CONF" ]; then
    ensure_starship
    echo ":: Caelestia fork already set up ($REPO_DIR) — nothing to do."
    exit 0
fi

# 1) Clone
if [ ! -d "$REPO_DIR/.git" ]; then
    if [ -e "$REPO_DIR" ]; then
        echo "!! $REPO_DIR exists but is not a git repo — refusing to touch it." >&2
        exit 1
    fi
    reply=""
    if [ -t 0 ]; then
        read -r -p ":: Caelestia fork not found at $REPO_DIR. Clone it? [y/N] " reply
    fi
    case "$reply" in
        y|Y|yes|YES) ;;
        *)
            echo ":: Skipping caelestia fork setup (no clone). Re-run later with:"
            echo "     dcli module run-hook caelestia"
            exit 0
            ;;
    esac
    as_user mkdir -p "$(dirname "$REPO_DIR")"
    if as_user gh auth status >/dev/null 2>&1; then
        as_user gh repo clone "$REPO_URL" "$REPO_DIR"
    else
        as_user git clone "$REPO_URL" "$REPO_DIR"
    fi
    as_user git -C "$REPO_DIR" remote add upstream "$UPSTREAM_URL"
fi

# 2) Build + install the shell (only if not already installed)
if [ ! -e "$QS_CONF/shell.qml" ]; then
    cd "$REPO_DIR"
    if as_user git -C "$REPO_DIR" describe --tags --abbrev=0 >/dev/null 2>&1; then
        as_user fish devfiles/install-user.fish
    else
        echo ":: No git tag reachable — using untagged installer"
        as_user fish devfiles/install-user-untagged.fish
    fi
else
    echo ":: Shell already installed at $QS_CONF — skipping build."
fi

# 3) Symlink ~/.config/caelestia -> fork/caelestia-configs
SRC="$REPO_DIR/caelestia-configs"
if [ -L "$CAEL_CONF" ] && [ "$(readlink -f "$CAEL_CONF")" = "$(readlink -f "$SRC")" ]; then
    echo ":: ~/.config/caelestia already linked"
else
    if [ -e "$CAEL_CONF" ]; then
        BAK="$CAEL_CONF.bak-$(date +%Y%m%d-%H%M%S)"
        echo ":: Backing up existing $CAEL_CONF -> $BAK"
        as_user mv "$CAEL_CONF" "$BAK"
    fi
    as_user ln -s "$SRC" "$CAEL_CONF"
    echo ":: Symlinked $CAEL_CONF -> $SRC"
fi

ensure_starship

echo ":: Caelestia fork setup complete."
echo ":: Day-to-day workflow: edit files in $REPO_DIR, then run:"
echo "     ./scripts/sync-live.sh"
echo ""
echo ":: Optional (not automated): the SDDM and GRUB themes live in the fork too."
echo "   Install them interactively with:"
echo "     cd $REPO_DIR && ./install.fish   (options 3 = SDDM, 4 = GRUB)"
