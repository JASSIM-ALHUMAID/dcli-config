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

# shellcheck source=lib/hook-common.sh disable=SC1091
. "$(dirname "$(readlink -f "$0")")/lib/hook-common.sh" || exit 1

REPO_URL="https://github.com/plusdrag11/Ambxst.git"
UPSTREAM_URL="https://github.com/Axenide/Ambxst.git"
REPO_BRANCH="my-ambxst"
INSTALL_PATH="$REAL_HOME/.local/src/ambxst"

# Already fully set up?
if [ -d "$INSTALL_PATH/.git" ]; then
    echo ":: AMBXst already installed at $INSTALL_PATH"
    exit 0
fi

# Clone the fork only if the user opts in; non-interactive shells skip silently.
clone_checkout "$INSTALL_PATH" "$REPO_URL" "$REPO_BRANCH" "AMBXst fork" --opt-in ambxst
as_user git -C "$INSTALL_PATH" remote add upstream "$UPSTREAM_URL"

echo ":: Running AMBXst installer"
bash "$INSTALL_PATH/install.sh"
