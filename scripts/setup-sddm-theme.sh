#!/bin/bash
# Module hook for modules/sddm-theme.yaml (runs as the user, once).
#
# User half only: render the per-shell palette/wallpaper staging tree. The root
# half needs sudo, which a dcli hook must never invoke itself — so when it is
# missing or stale this prints the one command to run and exits 0. See docs/SDDM.md.
set -euo pipefail

# shellcheck source=lib/hook-common.sh disable=SC1091
. "$(dirname "$(readlink -f "$0")")/lib/hook-common.sh" || exit 1
# shellcheck source=lib/sddm-common.sh disable=SC1091
. "$(dirname "$(readlink -f "$0")")/lib/sddm-common.sh" || exit 1

RENDERER="$SDDM_REPO_DIR/scripts/render-sddm-theme.sh"

if [ ! -x "$RENDERER" ]; then
    echo "!! $RENDERER is missing or not executable" >&2
    exit 1
fi
echo ":: Rendering SDDM themes for every shell"
as_user "$RENDERER" all || {
    echo "!! SDDM theme render failed — re-run: dcli module run-hook sddm-theme" >&2
    exit 1
}

problems=$(sddm_integration_problems)
if [ -z "$problems" ]; then
    echo ":: SDDM integration is installed and current"
    exit 0
fi
echo ":: The root-side SDDM integration needs (re)installing:"
while IFS= read -r problem; do echo "     - $problem"; done <<<"$problems"
echo ":: Run once, yourself (as you, not with sudo — it asks for sudo itself):"
echo "     $SDDM_INSTALL_COMMAND"
exit 0
