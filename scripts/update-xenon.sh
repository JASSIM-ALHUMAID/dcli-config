#!/bin/bash
# Update the xenon shell: pulls latest from MannuVilasara/xenon-shell (main).
#
# Nothing in this repo patches the checkout (unlike end4-pC), and the shell
# writes its own state to ~/.config/xenon and ~/.cache/xenon — so the working
# tree stays clean and a plain fast-forward is enough.
set -euo pipefail

# shellcheck source=lib/hook-common.sh disable=SC1091
. "$(dirname "$(readlink -f "$0")")/lib/hook-common.sh" || exit 1

REPO_DIR="$REAL_HOME/.local/share/xenon-shell"

require_checkout "$REPO_DIR" xenon-shell setup-xenon.sh || exit 1

echo ":: Updating xenon-shell (main branch)"
fast_forward_pull "$REPO_DIR"

echo ":: xenon-shell updated — restart shell with switch-shell.sh xenon"
