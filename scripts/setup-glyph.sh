#!/bin/bash
# Bootstrap glyph-rice — Nebelung-cloud/glyph-rice, a Nothing-OS rice: a
# Hyprland Lua config plus two Quickshell configs, `glyph` (the desktop) and
# `rice` (its shell switcher / lock helper).
#
# WHAT THIS IS NOT: glyph ships install.sh, which moves aside and symlinks its
# ENTIRE config/hypr tree over ~/.config/hypr, plus fish, kitty, qtengine and the
# terminal palettes (starship, fastfetch, btop, cava, gtk.css). ~/.config/hypr is
# dcli-owned and the terminal configs are shared across eight other shells, so
# that installer is never run. This script reproduces only the user-level steps
# that do not collide: the checkout, the two Quickshell configs, the bundled
# fonts, and the state directories the shell writes.
#
# Layout this script produces:
#   ~/.local/share/glyph-rice                     — checkout on main (source of
#                                                   truth); upstream gitignores
#                                                   config/hypr/user.lua, so
#                                                   local binds never block a pull
#   ~/.config/quickshell/glyph -> .../config/quickshell/glyph
#   ~/.config/quickshell/rice  -> .../config/quickshell/rice
#   ~/.local/share/fonts/glyph -> .../config/fonts
#   ~/.config/demonshot                           — rules.json written by the
#                                                   shell's Rules.qml
#   ~/.local/state/rice/shell                     — which config `rice` starts;
#                                                   seeded to `glyph`
#   ~/Pictures/Wallpapers                         — the wallpaper picker's source
#
# `rice` itself is not put on PATH: it can `rice switch` outside dcli's
# active.conf. The shell calls it by absolute path for lock/list, which is all
# this setup needs.
#
# Safe to re-run: clone_checkout never reclones, ensure_symlink skips correct
# links, and the state seed is idempotent.
set -euo pipefail

# shellcheck source=lib/hook-common.sh disable=SC1091
. "$(dirname "$(readlink -f "$0")")/lib/hook-common.sh" || exit 1

REPO_URL="https://github.com/Nebelung-cloud/glyph-rice.git"
REPO_BRANCH="main"
REPO_DIR="$REAL_HOME/.local/share/glyph-rice"
QS_DIR="$REAL_HOME/.config/quickshell"
STATE_FILE="$REAL_HOME/.local/state/rice/shell"

# 1) Upstream checkout. No submodules, no personal fork.
clone_checkout "$REPO_DIR" "$REPO_URL" "$REPO_BRANCH" "glyph-rice"

# 2) The two Quickshell configs. `glyph` is the desktop; `rice` is its shell
#    switcher and holds the lock entry point the shell and hypridle call.
for config in glyph rice; do
    ensure_symlink "$REPO_DIR/config/quickshell/$config" "$QS_DIR/$config" refuse || exit 1
done

# 3) Bundled fonts (Doto, Space Grotesk/Mono). A symlink keeps them current
#    across checkout updates; fc-cache is best-effort, as upstream's is.
ensure_symlink "$REPO_DIR/config/fonts" "$REAL_HOME/.local/share/fonts/glyph" refuse || exit 1
if command -v fc-cache >/dev/null 2>&1; then
    as_user fc-cache -f "$REAL_HOME/.local/share/fonts/glyph" >/dev/null 2>&1 || true
fi

# 4) State directories and the `rice` state seed. `rice start` reads this file;
#    without it, it falls back to glyph anyway, but seeding makes the intent
#    explicit and survives a future second rice installed beside this one.
as_user mkdir -p "$REAL_HOME/.config/demonshot" \
    "$REAL_HOME/.local/state/rice" "$REAL_HOME/Pictures/Wallpapers"
if [ "$(as_user cat "$STATE_FILE" 2>/dev/null || true)" != "glyph" ]; then
    as_user sh -c "printf 'glyph\n' > '$STATE_FILE'"
fi

echo ":: glyph-rice ready — switch with switch-shell.sh glyph"
echo "   (the checkout's own install.sh is deliberately not run: it would replace ~/.config/hypr)"
