#!/bin/bash
# Remove the GRUB theming layer installed by install-grub-theme.sh.
# Run as yourself — NOT with sudo; the root steps call sudo themselves:
#   scripts/uninstall-grub-theme.sh [--purge]
#
# Restores the GRUB_THEME line remembered at install time (or removes ours if
# there was none), deletes every installed file and regenerates grub.cfg. Also
# copes with a half-finished install. Your rendered themes under
# state/grub-theme/ stay unless --purge is given.
#
# DCLI_INSTALL_ROOT=<dir> redirects every system file to <dir> and drops sudo,
# systemctl and grub-mkconfig (tests only).

set -euo pipefail

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
# shellcheck source=lib/grub-common.sh disable=SC1091
. "$SCRIPT_DIR/lib/grub-common.sh" || exit 1

# ── Constants ────────────────────────────────────────────────────────────────
ABSENT_MARK='<absent>'
STEP_COUNT=4
STEP=0

if [ -n "$GRUB_ROOT" ]; then
    SUDO=()
else
    SUDO=(sudo)
fi

step() { STEP=$((STEP + 1)); printf '\n:: [%d/%d] %s\n' "$STEP" "$STEP_COUNT" "$*"; }
log() { printf '   %s\n' "$*"; }
die() { printf '!! %s\n' "$*" >&2; exit 1; }

real_only() { [ -n "$GRUB_ROOT" ] || "$@"; }

# ── Preconditions ────────────────────────────────────────────────────────────
PURGE=0
case "${1:-}" in
"") ;;
--purge) PURGE=1 ;;
*) die "usage: uninstall-grub-theme.sh [--purge]   (run as yourself, not with sudo)" ;;
esac
[ "$(id -u)" -ne 0 ] || die "do not run this with sudo — run it as yourself; it asks for sudo when it needs it"

echo "dcli GRUB theme uninstaller — root steps will ask for your sudo password once"
real_only sudo -v || die "sudo authentication failed"

# ── 1. Units ─────────────────────────────────────────────────────────────────
step "Stopping and removing the systemd units"
real_only systemctl --user disable --now "$GRUB_RENDER_PATH_UNIT" 2>/dev/null || true
real_only systemctl --user stop "$GRUB_RENDER_SERVICE_UNIT" 2>/dev/null || true
rm -f "$GRUB_USER_UNIT_DIR/$GRUB_RENDER_PATH_UNIT" "$GRUB_USER_UNIT_DIR/$GRUB_RENDER_SERVICE_UNIT"
real_only systemctl --user daemon-reload
real_only sudo systemctl disable --now "$GRUB_PATH_UNIT" 2>/dev/null || true
real_only sudo systemctl stop "$GRUB_SERVICE_UNIT" 2>/dev/null || true
real_only sudo systemctl reset-failed "$GRUB_SERVICE_UNIT" 2>/dev/null || true
"${SUDO[@]}" rm -f "$GRUB_UNIT_DIR/$GRUB_PATH_UNIT" "$GRUB_UNIT_DIR/$GRUB_SERVICE_UNIT"
real_only sudo systemctl daemon-reload

# ── 2. /etc/default/grub ─────────────────────────────────────────────────────
step "Restoring GRUB_THEME"
if [ -f "$GRUB_DEFAULT_FILE" ] && grep -qE '^[[:space:]]*GRUB_THEME="?/boot/grub/themes/dcli/' "$GRUB_DEFAULT_FILE"; then
    prev=""
    [ -f "$GRUB_PREV_THEME_FILE" ] && prev=$(head -n1 "$GRUB_PREV_THEME_FILE")
    "${SUDO[@]}" cp -p "$GRUB_DEFAULT_FILE" "$GRUB_DEFAULT_FILE.dcli-bak-$(date +%Y%m%d-%H%M%S)"
    if [ -z "$prev" ] || [ "$prev" = "$ABSENT_MARK" ]; then
        "${SUDO[@]}" sed -i -E '/^[[:space:]]*GRUB_THEME="?\/boot\/grub\/themes\/dcli\//d' "$GRUB_DEFAULT_FILE"
        log "removed our GRUB_THEME line (there was none before install)"
    else
        # Escape the replacement for sed (& \ and the | delimiter).
        esc=${prev//\\/\\\\}
        esc=${esc//&/\\&}
        esc=${esc//|/\\|}
        "${SUDO[@]}" sed -i -E "s|^[[:space:]]*GRUB_THEME=\"?/boot/grub/themes/dcli/.*\$|$esc|" "$GRUB_DEFAULT_FILE"
        log "restored: $prev"
    fi
else
    log "GRUB_THEME does not point at dcli — left as is"
fi

# ── 3. Installed files ───────────────────────────────────────────────────────
step "Removing the helper, grub.d generator and installed themes"
"${SUDO[@]}" rm -f "$GRUB_HELPER_INSTALLED" "$GRUB_D_INSTALLED"
"${SUDO[@]}" rm -rf "${GRUB_THEMES_INSTALLED:?}" "${GRUB_STATE_INSTALLED:?}"
if [ "$PURGE" = 1 ]; then
    rm -rf "${GRUB_STAGING_DIR:?}"
    log "purged rendered themes at $GRUB_STAGING_DIR"
else
    log "kept rendered themes at $GRUB_STAGING_DIR (--purge removes them)"
fi

# ── 4. grub.cfg ──────────────────────────────────────────────────────────────
step "Regenerating grub.cfg"
if [ -z "$GRUB_ROOT" ]; then
    sudo -v || die "sudo authentication failed"
    sudo grub-mkconfig -o /boot/grub/grub.cfg || die "grub-mkconfig failed (the old grub.cfg is untouched)"
fi

printf '\n:: Uninstalled. Re-install any time with:\n   %s\n' "$GRUB_INSTALL_COMMAND"
