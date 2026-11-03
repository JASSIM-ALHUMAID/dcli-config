#!/bin/bash
# Keep the house keyboard options alive under glyph's shell.
#
# glyph's Quickshell config (settings/Rules.qml, input()) rewrites Hyprland's
# kb_options at every shell start with only its layout-switch pick
# (grp:alt_shift_toggle by default). That lands AFTER the Lua config, so it
# silently drops the house `ctrl:nocaps` (Caps = Ctrl) and Super+Space toggle
# from common/input.lua. This prefixes the house options to glyph's own pick.
#
# A literal-string sed that normalises back to upstream first, so re-running is
# a no-op and a pull that moves the line still leaves the string intact.
# Run by setup-glyph.sh (after clone) and update-glyph.sh (after every pull).
set -euo pipefail

# shellcheck source=lib/hook-common.sh disable=SC1091
. "$(dirname "$(readlink -f "$0")")/lib/hook-common.sh" || exit 1

REPO_DIR="$REAL_HOME/.local/share/glyph-rice"
RULES_QML="$REPO_DIR/config/quickshell/glyph/settings/Rules.qml"
HOUSE_KB_OPTIONS="ctrl:nocaps,grp:win_space_toggle,"

require_checkout "$REPO_DIR" glyph-rice setup-glyph.sh || exit 1

as_user sed -i \
    -e "s|kb_options = \"${HOUSE_KB_OPTIONS}\${switches|kb_options = \"\${switches|" \
    -e "s|kb_options = \"\${switches|kb_options = \"${HOUSE_KB_OPTIONS}\${switches|" \
    "$RULES_QML"

if ! grep -qF "kb_options = \"${HOUSE_KB_OPTIONS}\${switches" "$RULES_QML"; then
    echo "!! patch-glyph.sh: kb_options line not found in Rules.qml — upstream changed" >&2
    exit 1
fi
echo ":: glyph Rules.qml keeps the house keyboard options"
