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
    # Caelestia / generic quickshell stragglers
    kill_matching -f "qs -c caelestia"
    kill_matching -f "bin/quickshell -c noctalia-shell"
    kill_matching -f "dms run"
    kill_matching -f "qs -c ii"
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

kill_all_shells

# Point active.conf at the chosen shell
printf '# Written by switch-shell.sh — current shell: %s\nsource = ~/.config/hypr/shells/%s.conf\n' \
    "$SHELL_NAME" "$SHELL_NAME" > "$ACTIVE"

hyprctl reload
sleep 2

# end4 keeps all its binds in a permanently-active "global" submap (required
# for its catchall launcher-interrupt bind). Make sure that submap isn't left
# active when switching to a shell whose config doesn't define it — their
# binds would all go dead.
[ "$SHELL_NAME" != "end4" ] && hyprctl dispatch submap reset

# Launch. dms and noctalia are exec-once'd from their shell conf, but
# exec-once does not re-fire on `hyprctl reload`, so start them here too
# (guarded so a fresh login doesn't double-start them).
case "$SHELL_NAME" in
    caelestia)
        caelestia shell -d & disown
        ;;
    ambxst)
        ambxst & disown
        sleep 2
        hyprctl keyword monitor ", preferred, auto, 1"
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
