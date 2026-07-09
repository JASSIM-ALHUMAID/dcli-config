#!/bin/bash
# Switch between Caelestia and AMBXst Hyprland shells
# Usage: switch-shell.sh [caelestia|ambxst]
# No argument = toggle between them

SHELL_NAME="${1:-}"
ENTRY="$HOME/.config/hypr/hyprland.conf"

if [ ! -f "$ENTRY" ]; then
    echo "Error: $ENTRY not found"
    exit 1
fi

# Auto-detect current shell if toggling
if [ -z "$SHELL_NAME" ]; then
    if grep -q "^source.*caelestia/hypr/hyprland.conf" "$ENTRY"; then
        SHELL_NAME="ambxst"
    else
        SHELL_NAME="caelestia"
    fi
fi

# TERM first, escalate to KILL only for survivors. Patterns must be
# anchored (-x exact name, or -f with a distinctive phrase) so unrelated
# processes (e.g. an editor with an ambxst file open) are never matched.
kill_matching() {
    local flag="$1" pattern="$2"
    pkill "$flag" "$pattern" 2>/dev/null || return 0
    for _ in 1 2 3 4 5; do
        pgrep "$flag" "$pattern" >/dev/null 2>&1 || return 0
        sleep 0.2
    done
    pkill -9 "$flag" "$pattern" 2>/dev/null
}

# Kill ALL running shell processes first
kill_all_shells() {
    # Caelestia / QuickShell: ask nicely via IPC, then clean up stragglers
    qs -c caelestia kill 2>/dev/null
    kill_matching -f "qs -c caelestia"
    kill_matching -x "quickshell"
    kill_matching -f "caelestia shell"
    kill_matching -f "caelestia resizer"
    # AMBXst (loginlock.sh / sleep_monitor.sh are old helpers; -x matches
    # comm, which the kernel truncates to 15 chars)
    kill_matching -x "ambxst"
    kill_matching -x "axctl"
    kill_matching -x "ambxst_ipc"
    kill_matching -x "loginlock.sh"
    kill_matching -x "sleep_monitor.s"
    sleep 1
}

case "$SHELL_NAME" in
    caelestia)
        # Kill everything
        kill_all_shells

        # Swap source lines
        sed -i 's/^source = ~\/.local\/share\/ambxst\/hyprland.conf/# source = ~\/.local\/share\/ambxst\/hyprland.conf/' "$ENTRY"
        sed -i 's/^# source = ~\/.local\/share\/caelestia\/hypr\/hyprland.conf/source = ~\/.local\/share\/caelestia\/hypr\/hyprland.conf/' "$ENTRY"
        sed -i 's/^source = ~\/.config\/hypr\/ambxst-overrides.conf/# source = ~\/.config\/hypr\/ambxst-overrides.conf/' "$ENTRY"

        # Reload and launch
        hyprctl reload
        sleep 2
        caelestia shell -d & disown
        echo "Switched to Caelestia"
        ;;
    ambxst)
        # Kill everything
        kill_all_shells

        # Swap source lines
        sed -i 's/^source = ~\/.local\/share\/caelestia\/hypr\/hyprland.conf/# source = ~\/.local\/share\/caelestia\/hypr\/hyprland.conf/' "$ENTRY"
        sed -i 's/^# source = ~\/.local\/share\/ambxst\/hyprland.conf/source = ~\/.local\/share\/ambxst\/hyprland.conf/' "$ENTRY"
        sed -i 's/^# source = ~\/.config\/hypr\/ambxst-overrides.conf/source = ~\/.config\/hypr\/ambxst-overrides.conf/' "$ENTRY"

        # Reload and launch
        hyprctl reload
        sleep 2
        ambxst & disown
        sleep 2
        hyprctl keyword monitor ", preferred, auto, 1"
        echo "Switched to AMBXst"
        ;;
    *)
        echo "Usage: switch-shell.sh [caelestia|ambxst]"
        exit 1
        ;;
esac

echo "Current config:"
grep "^source" "$ENTRY"
