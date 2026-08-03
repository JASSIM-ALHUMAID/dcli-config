#!/bin/bash
# Application launcher for the ml4w shell.
#
# This path is NOT ours to choose: ml4w's StatusbarApp/LauncherModule.qml
# hardcodes "$HOME/.config/hypr/scripts/launcher.sh", and the checkout is
# tracked upstream unmodified — so the bar's launcher button lands here no
# matter what. ml4w's keybinds.lua points SUPER+CTRL+RETURN at it too.
#
# Mirrors upstream's own launcher.sh: read the configured launcher from
# ~/.config/ml4w/settings/launcher and dispatch to it. rofi is what ml4w ships
# configured (and what setup-ml4w.sh installs); walker is upstream's other
# option, supported here only if you install it yourself.
#
# rofi 2.x is Wayland-native, so plain `rofi` is correct — there is no
# rofi-wayland package to reach for.
#
# Only the ml4w shell references this script (grep dotfiles/hypr/shells). Should
# another shell ever want a launcher, give it its own — do not generalise this
# one, or ml4w's button breaks.
set -u

launcher="rofi"
[ -f "$HOME/.config/ml4w/settings/launcher" ] &&
    launcher=$(tr -d '[:space:]' <"$HOME/.config/ml4w/settings/launcher")

case "$launcher" in
walker)
    if command -v walker >/dev/null 2>&1; then
        exec "$HOME/.config/walker/launch.sh" --height 500
    fi
    ;;
esac

# rofi, and the fallback for an unknown/uninstalled choice. -replace so the
# button is idempotent: a second press re-focuses instead of stacking.
if command -v rofi >/dev/null 2>&1; then
    exec rofi -show drun -replace -i
fi

# Last resort so the button is never dead. wofi is unthemed here — if you land
# on this line, `paru -S rofi` is the fix.
exec wofi --show drun
