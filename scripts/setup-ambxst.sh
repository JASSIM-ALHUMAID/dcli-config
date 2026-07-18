#!/bin/bash
# Bootstrap AMBXst from my fork (plusdrag11/Ambxst, branch my-ambxst;
# upstream Axenide/Ambxst kept as second remote) — clones to ~/.local/src/ambxst
# and runs its installer, which sets up a launcher at /usr/local/bin/ambxst
# (it sudos where needed). My AMBXst settings (binds.json, config/,
# hypr-user.conf, presets/) are managed by dcli dotfiles -> ~/.config/ambxst.
set -euo pipefail

# dcli may run hooks as root — always operate on the real user's home.
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

REPO_URL="https://github.com/plusdrag11/Ambxst.git"
UPSTREAM_URL="https://github.com/Axenide/Ambxst.git"
REPO_BRANCH="my-ambxst"
INSTALL_PATH="$REAL_HOME/.local/src/ambxst"

if [ -d "$INSTALL_PATH/.git" ]; then
    echo ":: AMBXst already installed at $INSTALL_PATH"
    exit 0
fi

echo ":: Cloning AMBXst fork (branch $REPO_BRANCH) to $INSTALL_PATH"
mkdir -p "$(dirname "$INSTALL_PATH")"
git clone --branch "$REPO_BRANCH" "$REPO_URL" "$INSTALL_PATH"
git -C "$INSTALL_PATH" remote add upstream "$UPSTREAM_URL"

echo ":: Running AMBXst installer"
bash "$INSTALL_PATH/install.sh"
