#!/bin/bash
# Bootstrap AMBXst from my fork (plusdrag11/Ambxst, branch my-ambxst;
# upstream Axenide/Ambxst kept as second remote) — clones to ~/.local/src/ambxst
# and runs THE FORK'S installer, which installs the Go daemon binary to
# /usr/local/bin/ambxst (it sudos where needed). My AMBXst settings (binds.json, config/,
# hypr-user.conf, presets/) are managed by dcli dotfiles -> ~/.config/ambxst.
#
# NOTE: that installer's arch package list includes stock `quickshell`, which
# would conflict with quickshell-git (see docs/PACKAGE-CONFLICTS.md). It is only
# safe because the installer's filter_packages() skips it when the `qs` binary is
# already on PATH — and quickshell-git owns /usr/bin/qs.
#
# Under dcli that ordering is guaranteed: sync installs every declared package in
# one aggregated phase and only then runs post-install hooks, and
# shells-quickshell-git declares quickshell-git. So a fresh `dcli sync` is safe
# with no extra steps. The caveat applies only when running THIS script or the
# fork's install.sh by hand before any provider is installed.
set -euo pipefail

# dcli may run hooks as root — always operate on the real user's home.
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

REPO_URL="https://github.com/plusdrag11/Ambxst.git"
UPSTREAM_URL="https://github.com/Axenide/Ambxst.git"
REPO_BRANCH="my-ambxst"
INSTALL_PATH="$REAL_HOME/.local/src/ambxst"

# Already fully set up?
if [ -d "$INSTALL_PATH/.git" ]; then
    echo ":: AMBXst already installed at $INSTALL_PATH"
    exit 0
fi

# Clone the fork only if the user opts in. Non-interactive shells skip
# silently (the user can re-run via `dcli module run-hook ambxst` later).
reply=""
if [ -t 0 ]; then
    read -r -p ":: AMBXst fork not found at $INSTALL_PATH. Clone it? [y/N] " reply
fi
case "$reply" in
    y|Y|yes|YES) ;;
    *)
        echo ":: Skipping AMBXst fork setup (no clone). Re-run later with:"
        echo "     dcli module run-hook ambxst"
        exit 0
        ;;
esac

echo ":: Cloning AMBXst fork (branch $REPO_BRANCH) to $INSTALL_PATH"
mkdir -p "$(dirname "$INSTALL_PATH")"
git clone --branch "$REPO_BRANCH" "$REPO_URL" "$INSTALL_PATH"
git -C "$INSTALL_PATH" remote add upstream "$UPSTREAM_URL"

echo ":: Running AMBXst installer"
bash "$INSTALL_PATH/install.sh"
