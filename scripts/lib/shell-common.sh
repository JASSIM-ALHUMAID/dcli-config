#!/bin/bash
# Shared shell registry + active.conf parser. Sourced by switch-shell.sh,
# edit-hypr.sh, and fixture-tested by tests/smoke.sh — one home for the two
# things that used to exist as per-script copies and drifted silently
# (devfiles/doc/violations.md #2/#3).

# ── Registry ─────────────────────────────────────────────────────────────────
# One record per shell: name|icon|blurb, in picker order. name is the
# switch-shell.sh / edit-hypr.sh argument and the active.conf value; icon is a
# file under dotfiles/fuzzel/shell-icons (landed at ~/.config/fuzzel/shell-icons
# via the fuzzel dir symlink); blurb is the picker label suffix.
#
# omarchy is a .png on purpose: upstream's only SVG is a 1215x285 wordmark
# in black, unusable at icon size on a dark picker. icon.png is the square
# 300x300 logo. fuzzel 1.14 is built +png, so it loads either.
SHELL_RECORDS=(
    "caelestia|caelestia.svg|Material 3 · quickshell"
    "ambxst|ambxst.svg|Axenide · Astal"
    "dms|dms.svg|DankMaterialShell"
    "noctalia|noctalia.svg|v5 · native, no Qt"
    "end4|end4.svg|illogical-impulse"
    "end4pc|end4pc.svg|pctrade fork"
    "omarchy|omarchy.png|DHH · v4 quickshell"
    "xenon|xenon.svg|MannuVilasara · quickshell"
)
KNOWN=()
for _record in "${SHELL_RECORDS[@]}"; do KNOWN+=("${_record%%|*}"); done
unset _record

# ── Active shell ─────────────────────────────────────────────────────────────
SHELLS_DIR="$HOME/.config/hypr/shells"
ACTIVE="$SHELLS_DIR/active.conf"

# active.conf holds a bare shell name; older versions wrote a
# "source = ~/.config/hypr/shells/<name>.conf" line, still accepted here.
# (hyprland.lua:read_active_shell is the Lua parser of the same contract —
# different runtime, kept separate, but the accepted forms must stay in sync.)
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
