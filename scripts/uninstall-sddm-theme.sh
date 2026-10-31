#!/bin/bash
# Remove the SDDM theming layer installed by install-sddm-theme.sh.
# Run as yourself — NOT with sudo; the root steps call sudo themselves:
#   scripts/uninstall-sddm-theme.sh [--purge]
#
# Deletes the units, the helper, every dcli-<shell> theme and the Current=
# drop-in, so SDDM falls back to whatever theme the other drop-ins/sddm.conf
# name. Staged data under state/sddm-theme/ stays unless --purge is given.
#
# DCLI_INSTALL_ROOT=<dir> redirects every system file to <dir> and drops sudo
# and systemctl (tests only).

set -euo pipefail

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
# shellcheck source=lib/shell-common.sh disable=SC1091
. "$SCRIPT_DIR/lib/shell-common.sh" || exit 1
# shellcheck source=lib/sddm-common.sh disable=SC1091
. "$SCRIPT_DIR/lib/sddm-common.sh" || exit 1

STEP_COUNT=3
STEP=0
if [ -n "$SDDM_ROOT" ]; then SUDO=(); else SUDO=(sudo); fi

step() { STEP=$((STEP + 1)); printf '\n:: [%d/%d] %s\n' "$STEP" "$STEP_COUNT" "$*"; }
log() { printf '   %s\n' "$*"; }
die() { printf '!! %s\n' "$*" >&2; exit 1; }
real_only() { [ -n "$SDDM_ROOT" ] || "$@"; }

PURGE=0
case "${1:-}" in
"") ;;
--purge) PURGE=1 ;;
*) die "usage: uninstall-sddm-theme.sh [--purge]   (run as yourself, not with sudo)" ;;
esac
[ "$(id -u)" -ne 0 ] || die "do not run this with sudo — run it as yourself; it asks for sudo when it needs it"

echo "dcli SDDM theme uninstaller — root steps will ask for your sudo password once"
real_only sudo -v || die "sudo authentication failed"

step "Stopping and removing the systemd units"
real_only sudo systemctl disable --now "$SDDM_PATH_UNIT" 2>/dev/null || true
real_only sudo systemctl stop "$SDDM_SERVICE_UNIT" 2>/dev/null || true
real_only sudo systemctl reset-failed "$SDDM_SERVICE_UNIT" 2>/dev/null || true
"${SUDO[@]}" rm -f "$SDDM_UNIT_DIR/$SDDM_PATH_UNIT" "$SDDM_UNIT_DIR/$SDDM_SERVICE_UNIT"
real_only sudo systemctl daemon-reload

step "Removing the Current= drop-in and the themes"
"${SUDO[@]}" rm -f "$SDDM_CONF_FILE"
for d in "$SDDM_THEMES_INSTALLED/$SDDM_THEME_PREFIX"*/; do
    [ -d "$d" ] || continue
    "${SUDO[@]}" rm -rf "${d%/}"
    log "removed $(basename "$d")"
done

step "Removing the helper"
"${SUDO[@]}" rm -f "$SDDM_HELPER_INSTALLED"

if [ "$PURGE" = 1 ]; then
    rm -rf "${SDDM_STAGING_DIR:?}"
    rm -f "$SDDM_MODE_FILE"
    log "purged $SDDM_STAGING_DIR and the saved mode"
fi
printf '\n:: Done. SDDM uses its other configured theme again.\n'
