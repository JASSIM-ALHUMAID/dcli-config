#!/bin/bash
# Update glyph-rice: pulls latest from Nebelung-cloud/glyph-rice (main).
#
# glyph's local overrides live in config/hypr/user.lua, which upstream
# gitignores — so a user's binds never make the working tree dirty and a plain
# fast-forward is always enough. The shell re-reads its QML live; the Hyprland
# side needs a reload, which switch-shell.sh glyph does.
set -euo pipefail

# shellcheck source=lib/hook-common.sh disable=SC1091
. "$(dirname "$(readlink -f "$0")")/lib/hook-common.sh" || exit 1

REPO_DIR="$REAL_HOME/.local/share/glyph-rice"

require_checkout "$REPO_DIR" glyph-rice setup-glyph.sh || exit 1

echo ":: Updating glyph-rice (main branch)"
fast_forward_pull "$REPO_DIR"

echo ":: glyph-rice updated — restart shell with switch-shell.sh glyph"
