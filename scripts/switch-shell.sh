#!/bin/bash
# Switch between Hyprland shells: caelestia | ambxst | dms | noctalia | end4 | end4pc
# Usage: switch-shell.sh [shell]
#   no argument = interactive fuzzel picker (falls back to usage text)
#
# Mechanism: ~/.config/hypr/hyprland.lua reads shells/active.conf, extracts
# the shell name, and dofile()'s the matching Lua config. This script
# rewrites active.conf and reloads hyprland. The per-shell Lua configs live
# in the dcli repo (dotfiles/hypr/shells/).

set -u

# Prevent concurrent runs — only one switch-shell at a time
LOCKFILE="/tmp/switch-shell.lock"
exec 200>"$LOCKFILE"
flock -n 200 || { echo "switch-shell.sh: another instance is running"; exit 1; }

SHELLS_DIR="$HOME/.config/hypr/shells"
ACTIVE="$SHELLS_DIR/active.conf"
KNOWN=(caelestia ambxst dms noctalia end4 end4pc)

# Where each shell's Lua config lives — must match hyprland.lua's shell_paths
config_path() {
  case "$1" in
  caelestia) echo "$HOME/.local/share/caelestia/hypr/hyprland.lua" ;;
  ambxst) echo "$HOME/.local/share/ambxst/hyprland.lua" ;;
  *) echo "$SHELLS_DIR/$1/hyprland.lua" ;;
  esac
}

# active.conf holds a bare shell name; older versions wrote a
# "source = ~/.config/hypr/shells/<name>.conf" line, still accepted here.
current_shell() {
  [ -f "$ACTIVE" ] || {
    echo none
    return
  }
  local src
  src=$(grep -m1 -v '^[[:space:]]*\(#.*\)\?$' "$ACTIVE" |
    sed 's/^source[[:space:]]*=[[:space:]]*//; s/.*shells\///; s/\.conf.*//; s/\.lua.*//; s/[[:space:]]*$//')
  echo "${src:-none}"
}

SHELL_NAME="${1:-}"

# No argument: fuzzel picker (marks and preselects the current shell)
if [ -z "$SHELL_NAME" ]; then
  if command -v fuzzel >/dev/null 2>&1 && [ -n "${WAYLAND_DISPLAY:-}" ]; then
    cur=$(current_shell)
    # Real per-shell logo (SVG) + blurb, index-aligned with KNOWN. The logos
    # are committed under dotfiles/fuzzel/shell-icons and land at
    # ~/.config/fuzzel/shell-icons via the fuzzel dir symlink. Rendered by
    # fuzzel's dmenu icon protocol (label\0icon\x1f<abs-path>, libresvg).
    icon_dir="$HOME/.config/fuzzel/shell-icons"
    icon_files=(caelestia.svg ambxst.svg dms.svg noctalia.svg end4.svg end4pc.svg)
    blurbs=("Material 3 · quickshell"
      "Axenide · Astal"
      "DankMaterialShell"
      "v5 · native, no Qt"
      "illogical-impulse"
      "pctrade fork")
    args=(--dmenu --index)
    picker_ini="$HOME/.config/fuzzel/shell-picker.ini"
    [ -f "$picker_ini" ] && args+=(--config "$picker_ini") || args+=(--prompt "shell> ")
    # Preselect the active shell (separate loop — it appends to args, which the
    # menu-building subshell below can't do since it runs in a pipe).
    for i in "${!KNOWN[@]}"; do
      [ "${KNOWN[$i]}" = "$cur" ] && args+=(--select-index "$i")
    done
    # Build the menu straight into the pipe: the icon field needs a literal NUL,
    # which a bash variable cannot hold, so printf each entry directly.
    idx=$(
      for i in "${!KNOWN[@]}"; do
        s=${KNOWN[$i]}
        label=$(printf '%-10s  %s' "$s" "${blurbs[$i]}")
        [ "$s" = "$cur" ] && label+="  ●"
        printf '%s\0icon\x1f%s\n' "$label" "$icon_dir/${icon_files[$i]}"
      done | fuzzel "${args[@]}"
    )
    case "$idx" in *[!0-9]* | "") exit 0 ;; esac
    SHELL_NAME=${KNOWN[$idx]:-}
    [ -z "$SHELL_NAME" ] && exit 0
  else
    echo "Usage: switch-shell.sh [${KNOWN[*]}]  (current: $(current_shell))"
    exit 1
  fi
fi

case " ${KNOWN[*]} " in
*" $SHELL_NAME "*) ;;
*)
  echo "Unknown shell: $SHELL_NAME (choose from: ${KNOWN[*]})"
  exit 1
  ;;
esac

SHELL_CONFIG=$(config_path "$SHELL_NAME")
if [ ! -f "$SHELL_CONFIG" ]; then
  echo "Error: $SHELL_CONFIG not found (run dcli sync?)"
  exit 1
fi

# TERM first, escalate to KILL only for survivors. Patterns must be
# anchored (-x exact name, or -f with a distinctive phrase) so unrelated
# processes (e.g. an editor with an ambxst file open) are never matched.
kill_matching() {
  local flag="$1" pattern="$2"
  pkill "$flag" "$pattern" 2>/dev/null || return 0
  # Poll up to 1s, bail immediately when process exits
  local i=0
  while [ $i -lt 10 ]; do
    pgrep "$flag" "$pattern" >/dev/null 2>&1 || return 0
    sleep 0.1
    i=$((i + 1))
  done
  # Still alive after 1s — escalate to KILL
  pkill -9 "$flag" "$pattern" 2>/dev/null
}

kill_all_shells() {
  # Ask nicely via each shell's own IPC first (skip if binary not installed)
  command -v qs >/dev/null 2>&1 && qs -c caelestia kill 2>/dev/null
  # No graceful-quit IPC for noctalia v5: its CLI only accepts theme/msg/config/
  # dmenu/plugins/firefox-theme, and an unrecognised bare argument falls through
  # and STARTS the shell — so `noctalia kill` would launch it. Killed by name in
  # kill_matching below instead.
  command -v dms >/dev/null 2>&1 && dms kill 2>/dev/null
  command -v qs >/dev/null 2>&1 && qs -c ii kill 2>/dev/null
  command -v qs >/dev/null 2>&1 && qs -c end4-pC kill 2>/dev/null
  # Only ask ambxst to quit if it's actually running: its CLI trusts a
  # cached PID in /tmp/ambxst.pid, and a stale entry there makes it kill
  # whatever unrelated process now owns that recycled PID.
  pgrep -f "ambxst/shell.qml" >/dev/null 2>&1 && ambxst quit 2>/dev/null
  # Caelestia / generic quickshell stragglers
  kill_matching -f "qs -c caelestia"
  # Noctalia v5 is its own binary (no quickshell fork) — match it by name.
  kill_matching -x "noctalia"
  kill_matching -f "dms run"
  kill_matching -f "qs -c ii"
  kill_matching -f "qs -c end4-pC"
  kill_matching -x "quickshell"
  kill_matching -f "caelestia shell"
  kill_matching -f "caelestia resizer"
  # AMBXst — the launcher execs into `qs -p .../ambxst/shell.qml`, so the
  # main process must be matched by command line (-f); -x ambxst/axctl only
  # catches the wrapper scripts pre-exec. Helpers (comm=bash/tail) need -f
  # with a distinctive phrase.
  kill_matching -f "ambxst/shell.qml"
  kill_matching -f "ambxst/cli.sh"
  kill_matching -x "ambxst"
  kill_matching -x "axctl"
  kill_matching -f "ambxst_ipc"
  kill_matching -f "loginlock.sh"
  kill_matching -f "sleep_monitor.sh"
  # Old quickshell wallpaper scripts from previous configs
  kill_matching -f "switchwall.sh"
  # Catch-all: no quickshell instance from any previous shell may linger
  killall -q qs quickshell 2>/dev/null
  # Wait briefly for OS to reclaim resources from killed processes
  local i=0
  while [ $i -lt 5 ] && pgrep -f "qs -c|quickshell|ambxst|noctalia|dms run" >/dev/null 2>&1; do
    sleep 0.1
    i=$((i + 1))
  done
}

kill_all_shells

# Point active.conf at the chosen shell (read by ~/.config/hypr/hyprland.lua)
printf '# Written by switch-shell.sh — do not edit by hand\n%s\n' "$SHELL_NAME" >"$ACTIVE"

# Clear any leaked config-parser submap state before reloading: caelestia's
# KeybindApplier applies its JSON binds via `hyprctl keyword submap global;
# keyword bind ...` and that parser state persists, so without this reset the
# reload parses the ENTIRE new shell's binds into the "global" submap and
# they all go dead. Under the Lua config `hyprctl keyword` is rejected outright
# ("keyword can't work with non-legacy parsers"), so this is best-effort.
hyprctl keyword submap reset >/dev/null 2>&1
hyprctl reload
sleep 0.2

# Shells that keep their static binds in a permanently-active "global" submap
# need it re-entered; root-level binds go dead if a submap is left active.
# Detect from the loaded binds instead of hardcoding shell names. Dispatchers
# take Lua syntax under a .lua config and legacy syntax under a .conf one.
if hyprctl binds -j | jq -e 'any(.[]; .submap == "global")' >/dev/null 2>&1; then
  hyprctl dispatch 'hl.dsp.submap("global")' >/dev/null 2>&1 || hyprctl dispatch submap global
else
  hyprctl dispatch 'hl.dsp.submap("reset")' >/dev/null 2>&1 || hyprctl dispatch submap reset
fi

# Release the lock before launching background processes — they inherit
# fd 200 and would hold the lock open after this script exits.
exec 200>&-

# Launch. dms and noctalia are exec-once'd from their shell conf, but
# exec-once does not re-fire on `hyprctl reload`, so start them here too
# (guarded so a fresh login doesn't double-start them).
case "$SHELL_NAME" in
caelestia)
  pgrep -f "qs -c caelestia" >/dev/null 2>&1 || {
    # The fork's QML needs its own Caelestia.Internal plugin (~/.local/lib):
    # the packaged one in /usr/lib is older and lacks types like
    # LogindManager, so the shell dies with "Failed to load configuration".
    # hypr-user.lua exports these too, but hyprland only applies `env` at
    # startup — set them here so a switch works without a relogin.
    QML2_IMPORT_PATH="$HOME/.local/lib/qt6/qml${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}" \
      CAELESTIA_LIB_DIR="$HOME/.local/lib/caelestia" \
      caelestia shell -d &
    disown
  }
  ;;
ambxst)
  pgrep -f "ambxst/shell.qml" >/dev/null 2>&1 || {
    # ambxst rewrites the monitor on startup; shells/ambxst-overrides.lua
    # puts it back at scale 1 on the next reload.
    ambxst &
    disown
    sleep 1
    hyprctl eval 'hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })' >/dev/null 2>&1
  }
  ;;
dms)
  pgrep -f "dms run" >/dev/null 2>&1 || {
    dms run &
    disown
  }
  ;;
noctalia)
  pgrep -x noctalia >/dev/null 2>&1 || {
    noctalia &
    disown
  }
  ;;
end4)
  pgrep -f "qs -c ii" >/dev/null 2>&1 || {
    qs -c ii &
    disown
  }
  ;;
end4pc)
  pgrep -f "qs -c end4-pC" >/dev/null 2>&1 || {
    qs -c end4-pC &
    disown
  }
  ;;
esac

echo "Switched to $SHELL_NAME"
echo "Active shell:"
grep '^source' "$ACTIVE"
