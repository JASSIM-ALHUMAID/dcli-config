#!/bin/bash
# Update the ryoku shell: pulls Ryoku-dev/ryoku (main) and rebuilds.
#
# Unlike the other checkouts this one ships compiled pieces — the Go IPC daemon
# and three QML modules — so a pull alone leaves the running shell on stale
# binaries. setup-ryoku.sh owns the build (and is idempotent), so it is re-run
# here rather than duplicating the steps.
set -euo pipefail

# shellcheck source=lib/hook-common.sh disable=SC1091
. "$(dirname "$(readlink -f "$0")")/lib/hook-common.sh" || exit 1

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
REPO_DIR="$REAL_HOME/.local/share/ryoku-shell"

require_checkout "$REPO_DIR" ryoku setup-ryoku.sh || exit 1

echo ":: Updating ryoku (main branch)"
fast_forward_pull "$REPO_DIR"

echo ":: Rebuilding the shell from the updated checkout"
exec "$SCRIPT_DIR/setup-ryoku.sh"
