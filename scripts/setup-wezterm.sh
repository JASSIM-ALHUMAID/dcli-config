#!/bin/bash
# Bootstrap my WezTerm config (JASSIM-ALHUMAID/wezterm).
#
# ~/.config/wezterm is that repo's own checkout (the source of truth);
# dcli/dotfiles/wezterm is only a fallback snapshot, used when the clone
# fails (no network / no auth). Mirrors the setup-caelestia.sh pattern.
#
# Safe to re-run: it never touches an existing ~/.config/wezterm.
set -euo pipefail

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

REPO_URL="https://github.com/JASSIM-ALHUMAID/wezterm.git"
WEZ_CONF="$REAL_HOME/.config/wezterm"
SNAPSHOT="$REAL_HOME/.config/dcli/dotfiles/wezterm"

as_user() {
    if [ "$(id -u)" -eq 0 ] && [ "$REAL_USER" != "root" ]; then
        sudo -u "$REAL_USER" -H "$@"
    else
        "$@"
    fi
}

if [ -e "$WEZ_CONF" ]; then
    echo ":: ~/.config/wezterm already exists — nothing to do."
    exit 0
fi

echo ":: WezTerm config not found — cloning $REPO_URL"
if as_user gh auth status >/dev/null 2>&1 && as_user gh repo clone "$REPO_URL" "$WEZ_CONF"; then
    echo ":: Cloned via gh."
elif as_user git clone "$REPO_URL" "$WEZ_CONF"; then
    echo ":: Cloned via git."
elif [ -d "$SNAPSHOT" ]; then
    echo "!! Clone failed — falling back to the dcli snapshot copy."
    as_user cp -r "$SNAPSHOT" "$WEZ_CONF"
    echo ":: Copied $SNAPSHOT -> $WEZ_CONF (snapshot, not a git checkout)."
else
    echo "!! Clone failed and no snapshot available at $SNAPSHOT." >&2
    exit 1
fi

echo ":: WezTerm config setup complete."
