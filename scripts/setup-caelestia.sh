#!/bin/bash
# Bootstrap my custom Caelestia shell (fork of caelestia-dots/shell).
#
# The caelestia-shell pacman package installs the stock QML config into
# /etc/xdg/quickshell/caelestia. My fork overrides it via the user config
# path ~/.config/quickshell/caelestia (quickshell prefers ~/.config over
# /etc/xdg), built and installed by the fork's own installer.
#
# Layout this script produces:
#   ~/Projects/shell/real                  — the fork checkout (source of truth)
#   ~/.config/quickshell/caelestia         — built QML config (overrides /etc/xdg)
#   ~/.config/caelestia                    — symlink -> fork/caelestia-configs
set -euo pipefail

REPO_URL="https://github.com/JASSIM-ALHUMAID/my-caelestia.git"
REPO_DIR="$HOME/Projects/shell/real"

if [ ! -d "$REPO_DIR/.git" ]; then
    echo ":: Cloning caelestia fork to $REPO_DIR"
    mkdir -p "$(dirname "$REPO_DIR")"
    git clone "$REPO_URL" "$REPO_DIR"
else
    echo ":: Fork already present at $REPO_DIR"
fi

cd "$REPO_DIR"

# 1) Build + install the shell into ~/.config/quickshell/caelestia (user install, no sudo)
if git describe --tags --abbrev=0 >/dev/null 2>&1; then
    fish devfiles/install-user.fish
else
    echo ":: No git tag reachable — using untagged installer"
    fish devfiles/install-user-untagged.fish
fi

# 2) Symlink ~/.config/caelestia -> fork/caelestia-configs
TARGET="$HOME/.config/caelestia"
SRC="$REPO_DIR/caelestia-configs"
if [ -L "$TARGET" ] && [ "$(readlink -f "$TARGET")" = "$(readlink -f "$SRC")" ]; then
    echo ":: ~/.config/caelestia already linked"
else
    if [ -e "$TARGET" ]; then
        BAK="$TARGET.bak-$(date +%Y%m%d-%H%M%S)"
        echo ":: Backing up existing $TARGET -> $BAK"
        mv "$TARGET" "$BAK"
    fi
    ln -s "$SRC" "$TARGET"
    echo ":: Symlinked $TARGET -> $SRC"
fi

echo ":: Caelestia fork setup complete. Log out/in once so QML2_IMPORT_PATH is picked up."
