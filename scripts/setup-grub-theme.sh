#!/bin/bash
# Module hook for modules/grub-theme.yaml (runs as the user, once).
#
# User half only: render the GRUB themes from the registry, wallpapers and
# logos. The root half (a helper in /usr/local/libexec, a grub.d script, two
# systemd units, GRUB_THEME) needs sudo, which a dcli hook must never invoke
# itself — so when it is missing or stale this prints the one command to run and
# exits 0. See docs/GRUB.md.
set -euo pipefail

# shellcheck source=lib/hook-common.sh disable=SC1091
. "$(dirname "$(readlink -f "$0")")/lib/hook-common.sh" || exit 1
# shellcheck source=lib/grub-common.sh disable=SC1091
. "$(dirname "$(readlink -f "$0")")/lib/grub-common.sh" || exit 1

RENDERER="$GRUB_REPO_DIR/scripts/render-grub-theme.sh"

# ── Render ───────────────────────────────────────────────────────────────────
if [ ! -x "$RENDERER" ]; then
    echo "!! $RENDERER is missing or not executable" >&2
    exit 1
fi
echo ":: Rendering GRUB themes for every shell"
as_user "$RENDERER" all || {
    echo "!! GRUB theme render failed — re-run: dcli module run-hook grub-theme" >&2
    exit 1
}

# ── Root half ────────────────────────────────────────────────────────────────
problems=$(grub_integration_problems)
if [ -z "$problems" ]; then
    echo ":: GRUB integration is installed and current"
    exit 0
fi
echo ":: The root-side GRUB integration needs (re)installing:"
while IFS= read -r problem; do echo "     - $problem"; done <<<"$problems"
echo ":: Run once, yourself (as you, not with sudo — it asks for sudo itself):"
echo "     $GRUB_INSTALL_COMMAND"
exit 0
