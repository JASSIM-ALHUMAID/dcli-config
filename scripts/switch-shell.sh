#!/bin/bash
# Switch between Hyprland shells: caelestia | ambxst | dms | noctalia | end4
# Usage: switch-shell.sh [shell]
#   no argument = interactive fuzzel picker (falls back to usage text)
#
# Mechanism: ~/.config/hypr/hyprland.conf sources shells/active.conf, which
# this script rewrites to point at shells/<name>.conf, then reloads hyprland
# and launches the chosen shell. The per-shell confs live in the dcli repo
# (dotfiles/hypr/shells/).

set -u

SHELLS_DIR="$HOME/.config/hypr/shells"
ACTIVE="$SHELLS_DIR/active.conf"
KNOWN=(caelestia ambxst dms noctalia end4)

current_shell() {
    [ -f "$ACTIVE" ] || { echo none; return; }
    local src
    src=$(grep -m1 '^source' "$ACTIVE" | sed 's/.*shells\///; s/\.conf.*//')
    echo "${src:-none}"
}

SHELL_NAME="${1:-}"

# No argument: fuzzel picker (marks and preselects the current shell)
if [ -z "$SHELL_NAME" ]; then
    if command -v fuzzel >/dev/null 2>&1 && [ -n "${WAYLAND_DISPLAY:-}" ]; then
        cur=$(current_shell)
        # Icon + blurb per shell, index-aligned with KNOWN
        icons=(󰓎 󰆧 󰍹 󰖔 󰣇)
        blurbs=("Material 3 · quickshell"
                "Axenide · Astal"
                "DankMaterialShell"
                "minimal · quickshell"
                "illogical-impulse")
        menu=""
        args=(--dmenu --index)
        picker_ini="$HOME/.config/fuzzel/shell-picker.ini"
        [ -f "$picker_ini" ] && args+=(--config "$picker_ini") || args+=(--prompt "shell> ")
        for i in "${!KNOWN[@]}"; do
            s=${KNOWN[$i]}
            line=$(printf '%s  %-10s  %s' "${icons[$i]}" "$s" "${blurbs[$i]}")
            if [ "$s" = "$cur" ]; then
                line+="  ●"
                args+=(--select-index "$i")
            fi
            menu+="$line"$'\n'
        done
        idx=$(printf '%s' "$menu" | fuzzel "${args[@]}")
        case "$idx" in *[!0-9]*|"") exit 0 ;; esac
        SHELL_NAME=${KNOWN[$idx]:-}
        [ -z "$SHELL_NAME" ] && exit 0
    else
        echo "Usage: switch-shell.sh [caelestia|ambxst|dms|noctalia|end4]  (current: $(current_shell))"
        exit 1
    fi
fi

case " ${KNOWN[*]} " in
    *" $SHELL_NAME "*) ;;
    *) echo "Unknown shell: $SHELL_NAME (choose from: ${KNOWN[*]})"; exit 1 ;;
esac

if [ ! -f "$SHELLS_DIR/$SHELL_NAME.conf" ]; then
    echo "Error: $SHELLS_DIR/$SHELL_NAME.conf not found (run dcli sync?)"
    exit 1
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

kill_all_shells() {
    # Ask nicely via each shell's own IPC first
    qs -c caelestia kill 2>/dev/null
    "$HOME/.local/bin/noctalia" kill 2>/dev/null
    dms kill 2>/dev/null
    qs -c ii kill 2>/dev/null
    # Only ask ambxst to quit if it's actually running: its CLI trusts a
    # cached PID in /tmp/ambxst.pid, and a stale entry there makes it kill
    # whatever unrelated process now owns that recycled PID.
    pgrep -f "ambxst/shell.qml" >/dev/null 2>&1 && ambxst quit 2>/dev/null
    # Caelestia / generic quickshell stragglers
    kill_matching -f "qs -c caelestia"
    kill_matching -f "bin/quickshell -c noctalia-shell"
    kill_matching -f "dms run"
    kill_matching -f "qs -c ii"
    kill_matching -x "quickshell"
    kill_matching -f "caelestia shell"
    kill_matching -f "caelestia resizer"
    # AMBXst — the launcher execs into `qs -p .../ambxst/shell.qml`, so the
    # main process must be matched by command line (-f); -x ambxst/axctl only
    # catches the wrapper scripts pre-exec. Helpers (comm=bash/tail) need -f
    # with a distinctive phrase.
    kill_matching -f "ambxst/shell.qml"
    kill_matching -x "ambxst"
    kill_matching -x "axctl"
    kill_matching -f "ambxst_ipc"
    kill_matching -f "loginlock.sh"
    kill_matching -f "sleep_monitor.sh"
    # Catch-all: no quickshell instance from any previous shell may linger
    killall -q qs quickshell 2>/dev/null
    sleep 1
}

kill_all_shells

# Point active.conf at the chosen shell
printf '# Written by switch-shell.sh — current shell: %s\nsource = ~/.config/hypr/shells/%s.conf\n' \
    "$SHELL_NAME" "$SHELL_NAME" > "$ACTIVE"

# Clear any leaked config-parser submap state before reloading: caelestia's
# KeybindApplier applies its JSON binds via `hyprctl keyword submap global;
# keyword bind ...` and that parser state persists, so without this reset the
# reload parses the ENTIRE new shell's binds into the "global" submap and
# they all go dead.
hyprctl keyword submap reset
hyprctl reload
sleep 2

# caelestia and end4 keep ALL their static binds in a permanently-active
# "global" submap (required for their catchall launcher-interrupt binds); the
# other shells' binds are root-level and go dead if a submap is left active.
# Detect from the loaded binds instead of hardcoding shell names.
if hyprctl binds -j | jq -e 'any(.[]; .submap == "global")' >/dev/null 2>&1; then
    hyprctl dispatch submap global
else
    hyprctl dispatch submap reset
fi

# Launch. dms and noctalia are exec-once'd from their shell conf, but
# exec-once does not re-fire on `hyprctl reload`, so start them here too
# (guarded so a fresh login doesn't double-start them).
case "$SHELL_NAME" in
    caelestia)
        pgrep -f "qs -c caelestia" >/dev/null 2>&1 || {
            caelestia shell -d & disown
        }
        ;;
    ambxst)
        pgrep -f "ambxst/shell.qml" >/dev/null 2>&1 || {
            ambxst & disown
            sleep 2
            hyprctl keyword monitor ", preferred, auto, 1"
        }
        ;;
    dms)
        pgrep -f "dms run" >/dev/null 2>&1 || { dms run & disown; }
        ;;
    noctalia)
        pgrep -f "bin/quickshell -c noctalia-shell" >/dev/null 2>&1 || { "$HOME/.local/bin/noctalia" & disown; }
        ;;
    end4)
        pgrep -f "qs -c ii" >/dev/null 2>&1 || { qs -c ii & disown; }
        ;;
esac

echo "Switched to $SHELL_NAME"
echo "Active shell conf:"
grep '^source' "$ACTIVE"
