#!/bin/bash
# Start the ryoku session: the ryogami wallpaper daemon, then the ryoku-shell
# daemon in its place (exec). The one launch definition — called at login by
# dotfiles/hypr/shells/ryoku/hyprland/execs.lua and on a switch by
# switch-shell.sh's launch_ryoku, so the two cannot drift.
#
# RYOKU_BIN_DIR (built by setup-ryoku.sh; smoke.sh pins the two values equal)
# goes on PATH for these processes only: the shell and Hub call ~40 helpers by
# bare name and everything they spawn inherits it, while Hyprland and the other
# shells never see it. No RYOKU_SHELL_DIR: the daemon runs in deployed mode
# against the ~/.config/quickshell links, so the `qs -c shell` calls upstream
# hard-codes reach the instance it started (docs/shells/ryoku.md). Because the
# daemon lives under $HOME it adds ~/.local/lib/qt6/qml to the QML import path
# itself. No RYOKU_POLKIT_AGENT: the house hyprpolkitagent keeps the session's
# single agent slot.
set -euo pipefail

RYOKU_BIN_DIR="$HOME/.local/lib/ryoku/bin"
MISSING_BUILD_EXIT=1

for binary in ryogami ryoku-shell; do
    if [ ! -x "$RYOKU_BIN_DIR/$binary" ]; then
        message="$RYOKU_BIN_DIR/$binary is missing — run ~/.config/dcli/scripts/setup-ryoku.sh"
        echo "!! launch-ryoku: $message" >&2
        notify-send -u critical "ryoku did not start" "$message" 2>/dev/null || true
        exit "$MISSING_BUILD_EXIT"
    fi
done

export PATH="$RYOKU_BIN_DIR:$PATH"

# ryogami is a sibling daemon (the distro runs it as a user unit), not a child
# of ryoku-shell; it is single-instance, so only start one that is not running.
if ! pgrep -A -x ryogami >/dev/null 2>&1; then
    "$RYOKU_BIN_DIR/ryogami" &
    disown
fi

exec "$RYOKU_BIN_DIR/ryoku-shell" daemon
