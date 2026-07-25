#!/bin/bash
# Tear down the Noctalia v4 workaround after migrating to v5.
#
# v4 needed noctalia-qs, a quickshell fork with Conflicts=quickshell AND
# Conflicts=quickshell-git, so it could not coexist with either provider in
# modules/shells-quickshell{,-git}.yaml. This script used to work around that by
# downloading the noctalia-qs package, extracting it unpackaged to
# ~/.local/opt/noctalia-qs, and writing a ~/.local/bin/noctalia wrapper.
#
# v5 has no Quickshell and no Qt at all, and installs as the plain `noctalia`
# package (see modules/shell-noctalia.yaml). All three artifacts are now dead
# weight — and the wrapper is actively harmful: ~/.local/bin usually precedes
# /usr/bin on PATH, so it would shadow the real v5 binary and keep launching the
# v4 fork.
#
# Idempotent, and safe on a machine that never ran v4 (everything is skipped).
# Once every machine has run this, drop the hook from
# modules/shell-noctalia.yaml and delete this file.
set -euo pipefail

# dcli may run hooks as root — always operate on the real user's home.
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

OPT_DIR="$REAL_HOME/.local/opt/noctalia-qs"
WRAPPER="$REAL_HOME/.local/bin/noctalia"
QML_DIR="$REAL_HOME/.config/quickshell/noctalia-shell"

as_user() {
    if [ "$(id -u)" -eq 0 ] && [ "$REAL_USER" != "root" ]; then
        sudo -u "$REAL_USER" -H "$@"
    else
        "$@"
    fi
}

# 1) The launcher wrapper — only remove the one WE wrote, never a stranger's file.
if [ -e "$WRAPPER" ]; then
    if grep -q "setup-noctalia.sh" "$WRAPPER" 2>/dev/null; then
        as_user rm -f "$WRAPPER"
        echo ":: Removed the v4 launcher wrapper $WRAPPER"
    else
        echo "!! $WRAPPER exists but was not written by dcli — leaving it alone." >&2
        echo "!! It will shadow the packaged /usr/bin/noctalia; remove it yourself." >&2
    fi
else
    echo ":: No v4 launcher wrapper to remove"
fi

# 2) The extracted noctalia-qs fork.
if [ -d "$OPT_DIR" ]; then
    as_user rm -rf "$OPT_DIR"
    echo ":: Removed the extracted noctalia-qs fork at $OPT_DIR"
    # Tidy up ~/.local/opt itself, but only if nothing else lives there.
    as_user rmdir --ignore-fail-on-non-empty "$(dirname "$OPT_DIR")" 2>/dev/null || true
else
    echo ":: No extracted noctalia-qs fork to remove"
fi

# 3) The v4 QML checkout — a clone of noctalia-shell, meaningless to v5.
if [ -d "$QML_DIR" ]; then
    as_user rm -rf "$QML_DIR"
    echo ":: Removed the v4 QML checkout at $QML_DIR"
else
    echo ":: No v4 QML checkout to remove"
fi

echo ":: Noctalia v4 teardown complete."
echo ":: v5 config is ~/.config/noctalia/config.toml (dcli-managed)."
echo ":: Launch with 'noctalia', switch with switch-shell.sh noctalia."
echo ":: For video wallpapers, install the official 'Video Wallpaper' plugin"
echo ":: (noctalia/mpvpaper) from the plugin store — the v4 QML plugin is gone."
