#!/bin/bash
# Edit a shell's Hyprland settings in HyprMod, isolated per shell.
# Usage: edit-hypr.sh [shell] [-f|--force]
#   no argument = edit the currently active shell
#
# Mechanism: each shell owns a machine-written overlay at
# ~/.config/hypr/shells/<name>/hyprmod.lua (committed — ~/.config/hypr is the
# dcli repo). hyprland.lua require()s the active shell's file last, so GUI
# edits win. This script points hyprmod's managed-file path (a dconf key —
# its GSettings schema is bundled, not system-registered) at the target
# shell's file, pre-creates it (hyprmod's setup check executes hyprland.lua
# and only sees the file if the guarded require actually fires), and launches
# hyprmod with DCLI_HYPRMOD_SHELL so editing a non-active shell reads and
# writes that shell's tree coherently. See docs/shells/hyprmod.md.

set -u

SHELLS_DIR="$HOME/.config/hypr/shells"
ACTIVE="$SHELLS_DIR/active.conf"
KNOWN=(caelestia ambxst dms noctalia end4 end4pc omarchy xenon ml4w)
DCONF_KEY=/io/github/bluemancz/hyprmod/config-path

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

FORCE=0
SHELL_NAME=""
for arg in "$@"; do
  case "$arg" in
  -f | --force) FORCE=1 ;;
  *) SHELL_NAME="$arg" ;;
  esac
done
[ -z "$SHELL_NAME" ] && SHELL_NAME=$(current_shell)

case " ${KNOWN[*]} " in
*" $SHELL_NAME "*) ;;
*)
  echo "Unknown shell: $SHELL_NAME (choose from: ${KNOWN[*]})"
  exit 1
  ;;
esac

command -v hyprmod >/dev/null 2>&1 || {
  echo "hyprmod is not installed (yay -S hyprmod)"
  exit 1
}
command -v dconf >/dev/null 2>&1 || {
  echo "dconf CLI missing — cannot retarget hyprmod's managed file"
  exit 1
}

# Single-instance GTK app: a second `hyprmod` just activates the running
# window, which keeps the managed path it started with. Refuse unless forced.
# -A (--ignore-ancestors) per the repo convention; the process command line is
# "/usr/bin/python /usr/bin/hyprmod", so -f 'bin/hyprmod' anchors correctly.
if pgrep -A -f 'bin/hyprmod' >/dev/null 2>&1; then
  if [ "$FORCE" = 1 ]; then
    pkill -A -TERM -f 'bin/hyprmod' # clean quit: hyprmod routes TERM to app.quit()
    for _ in $(seq 20); do
      pgrep -A -f 'bin/hyprmod' >/dev/null 2>&1 || break
      sleep 0.1
    done
  else
    echo "hyprmod is already running (pinned to its launch-time shell)."
    echo "Close it, or re-run with --force (discards its unsaved changes)."
    exit 1
  fi
fi

# Per-shell managed file, by naming convention (no registry entry needed).
# Absolute expanded path on purpose: hyprmod applies the stored string via
# Path(path) without expanduser().
MANAGED="$SHELLS_DIR/$SHELL_NAME/hyprmod.lua"
mkdir -p "$SHELLS_DIR/$SHELL_NAME"
[ -f "$MANAGED" ] || printf -- '-- HyprMod managed settings for %s — seeded by edit-hypr.sh, written by hyprmod (Ctrl+S)\n' \
  "$SHELL_NAME" >"$MANAGED"

dconf write "$DCONF_KEY" "'$MANAGED'"

DCLI_HYPRMOD_SHELL="$SHELL_NAME" hyprmod &
disown

# hyprmod reloads the compositor on window construction; shells that keep
# their binds in a permanently-active "global" submap lose them on any bare
# reload. Re-enter it after the reload settles (same dance as switch-shell.sh).
(
  sleep 3
  if hyprctl binds | grep -qE '^[[:space:]]*submap: global$'; then
    hyprctl dispatch 'hl.dsp.submap("global")' >/dev/null 2>&1 || hyprctl dispatch submap global
  fi
) &
disown

echo "Editing $SHELL_NAME → $MANAGED"
[ "$SHELL_NAME" = "$(current_shell)" ] || echo \
  "Note: $SHELL_NAME is not the active shell — live previews apply to the running session until the next reload; saved settings only load when $SHELL_NAME is active."
