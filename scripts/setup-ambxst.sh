#!/bin/bash
# Bootstrap AMBXst (Axenide/Ambxst) — clones to ~/.local/src/ambxst and runs
# its installer, which sets up a launcher at /usr/local/bin/ambxst (it sudos
# where needed). My AMBXst settings (binds.json, config/, hypr-user.conf,
# presets/) are managed by dcli dotfiles -> ~/.config/ambxst.
set -euo pipefail

# dcli may run hooks as root — always operate on the real user's home.
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

REPO_URL="https://github.com/Axenide/Ambxst.git"
INSTALL_PATH="$REAL_HOME/.local/src/ambxst"

if [ -d "$INSTALL_PATH/.git" ]; then
    echo ":: AMBXst already installed at $INSTALL_PATH"
    exit 0
fi

echo ":: Cloning AMBXst to $INSTALL_PATH"
mkdir -p "$(dirname "$INSTALL_PATH")"
git clone "$REPO_URL" "$INSTALL_PATH"

echo ":: Running AMBXst installer"
bash "$INSTALL_PATH/install.sh"
