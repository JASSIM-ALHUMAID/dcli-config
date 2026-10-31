#!/bin/bash
# Install the SDDM theming layer: the login screen follows the active shell
# (docs/SDDM.md). Run as yourself — NOT with sudo; the root steps call sudo:
#   scripts/install-sddm-theme.sh
# Re-running is the upgrade path: it reinstalls the QML and the helper from the
# repo, then lets the sync service repopulate palette, wallpaper and avatar.
#
# This is the ONE moment repo files are copied into root-owned locations, under
# your sudo. From then on root only runs the installed helper, and the sync only
# ever writes data (colours, images, the active-theme drop-in) — never QML.
#
# Installs:
#   /usr/local/libexec/dcli-sddm-sync                 root side of the sync (0755)
#   /usr/share/sddm/themes/dcli-<shell>/              one theme per registry shell
#   /etc/systemd/system/dcli-sddm-theme.{path,service}  units, user + staging baked in
#   /etc/sddm.conf.d/zz-dcli-theme.conf               written by the sync: Current=
# Reverse it with scripts/uninstall-sddm-theme.sh.
#
# DCLI_INSTALL_ROOT=<dir> redirects every system file to <dir> and drops sudo,
# the dependency check, the render, systemctl and the first sync (tests only).

set -euo pipefail

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
# shellcheck source=lib/shell-common.sh disable=SC1091
. "$SCRIPT_DIR/lib/shell-common.sh" || exit 1
# shellcheck source=lib/sddm-common.sh disable=SC1091
. "$SCRIPT_DIR/lib/sddm-common.sh" || exit 1

# ── Constants ────────────────────────────────────────────────────────────────
RENDERER="$SCRIPT_DIR/render-sddm-theme.sh"
# Values land in unit files, where % and whitespace are special.
UNIT_VALUE_RE='^[A-Za-z0-9._/@+-]+$'
USER_RE='^[a-z_][a-z0-9_-]*$'
JOURNAL_TAIL_LINES=25
STEP_COUNT=6
STEP=0

if [ -n "$SDDM_ROOT" ]; then
    SUDO=()
    OWNER=()
else
    SUDO=(sudo)
    OWNER=(-o root -g root)
fi

step() { STEP=$((STEP + 1)); printf '\n:: [%d/%d] %s\n' "$STEP" "$STEP_COUNT" "$*"; }
log() { printf '   %s\n' "$*"; }
die() { printf '!! %s\n' "$*" >&2; exit 1; }
real_only() { [ -n "$SDDM_ROOT" ] || "$@"; }

# ── Preconditions ────────────────────────────────────────────────────────────
[ $# -eq 0 ] || die "usage: install-sddm-theme.sh   (no arguments; run as yourself, not with sudo)"
[ "$(id -u)" -ne 0 ] || die "do not run this with sudo — run it as yourself; it asks for sudo when it needs it"

REAL_USER=$(id -un)
[[ "$REAL_USER" =~ $USER_RE ]] || die "unexpected user name: $REAL_USER"
[[ "$SDDM_STAGING_DIR" =~ $UNIT_VALUE_RE ]] || die "staging path has characters unsafe for a unit file: $SDDM_STAGING_DIR"
for f in dcli-sddm-sync "$SDDM_PATH_UNIT" "$SDDM_SERVICE_UNIT"; do
    [ -f "$SDDM_SRC_DIR/$f" ] || die "missing $SDDM_SRC_DIR/$f"
done
[ -f "$SDDM_BASE_SRC/Main.qml" ] || die "missing $SDDM_BASE_SRC/Main.qml"
[ -x "$RENDERER" ] || die "$RENDERER is missing or not executable"
# Root will own these trees; a symlink in them would be followed at install time.
if [ -n "$(find "$SDDM_THEME_SRC" -type l -print -quit)" ]; then
    die "symlink found under $SDDM_THEME_SRC — refusing to copy it into a root-owned tree"
fi

echo "dcli SDDM theme installer — root steps will ask for your sudo password once"
real_only sudo -v || die "sudo authentication failed"

# ── 1. Dependencies ──────────────────────────────────────────────────────────
step "Checking dependencies (modules/sddm-theme.yaml)"
mapfile -t packages < <(sddm_module_packages)
[ "${#packages[@]}" -gt 0 ] || die "no packages: list found in $SDDM_MODULE_FILE"
if [ -z "$SDDM_ROOT" ]; then
    missing=$(pacman -T "${packages[@]}" || true)
    if [ -n "$missing" ]; then
        mapfile -t missing_list <<<"$missing"
        log "installing: ${missing_list[*]}"
        sudo pacman -S --needed --noconfirm "${missing_list[@]}" || die "pacman could not install: ${missing_list[*]}"
    fi
fi
log "ok: ${packages[*]}"

# ── 2. Render (as you) ───────────────────────────────────────────────────────
step "Rendering every shell's palette and wallpaper (mode: $(sddm_mode))"
if [ -z "$SDDM_ROOT" ]; then
    "$RENDERER" all || die "render failed — fix it and re-run this installer"
    [ -f "$SDDM_STAGING_DIR/active" ] || die "renderer finished but nothing is staged at $SDDM_STAGING_DIR"
fi

# ── 3. Root-owned helper ─────────────────────────────────────────────────────
step "Installing the root-owned sync helper"
"${SUDO[@]}" install -d -m 0755 "$(dirname "$SDDM_HELPER_INSTALLED")"
"${SUDO[@]}" install -m 0755 "${OWNER[@]}" "$SDDM_SRC_DIR/dcli-sddm-sync" "$SDDM_HELPER_INSTALLED"
log "${SDDM_HELPER_INSTALLED#"$SDDM_ROOT"}"

# ── 4. Themes (QML, once) ────────────────────────────────────────────────────
# <name> = sddm/base + the shell's own sddm/themes/<name>/ on top. A shell whose
# overlay brings a complete Main.qml (upstream themes) simply replaces the base.
step "Installing one theme per shell into ${SDDM_THEMES_INSTALLED#"$SDDM_ROOT"}"
WORK=$(mktemp -d) || die "mktemp failed"
trap 'rm -rf "${WORK:?}"' EXIT
for name in "${KNOWN[@]}"; do
    tree="$WORK/$SDDM_THEME_PREFIX$name"
    mkdir -p "$tree"
    cp -r "$SDDM_BASE_SRC/." "$tree/"
    [ ! -d "$SDDM_SHELL_SRC/$name" ] || cp -r "$SDDM_SHELL_SRC/$name/." "$tree/"
    target="$SDDM_THEMES_INSTALLED/$SDDM_THEME_PREFIX$name"
    "${SUDO[@]}" rm -rf "${target:?}"
    "${SUDO[@]}" install -d -m 0755 "${OWNER[@]}" "$target"
    "${SUDO[@]}" cp -r --no-preserve=mode,ownership "$tree/." "$target/"
    [ -z "$SDDM_ROOT" ] || continue
    "${SUDO[@]}" chown -R root:root "$target"
    "${SUDO[@]}" find "$target" -type d -exec chmod 0755 {} +
    "${SUDO[@]}" find "$target" -type f -exec chmod 0644 {} +
    "${SUDO[@]}" install -d -m 0755 -o root -g root "$target/assets"
    log "$SDDM_THEME_PREFIX$name"
done

# ── 5. Units + first sync ────────────────────────────────────────────────────
step "Installing systemd units for $REAL_USER and running the first sync"
"${SUDO[@]}" install -d -m 0755 "$SDDM_UNIT_DIR"
for unit in "$SDDM_PATH_UNIT" "$SDDM_SERVICE_UNIT"; do
    sed "s|@USER@|$REAL_USER|g; s|@STAGING@|$SDDM_STAGING_DIR|g" "$SDDM_SRC_DIR/$unit" |
        "${SUDO[@]}" install -m 0644 "${OWNER[@]}" /dev/stdin "$SDDM_UNIT_DIR/$unit"
    log "${SDDM_UNIT_DIR#"$SDDM_ROOT"}/$unit"
done
real_only sudo systemctl daemon-reload
real_only sudo systemctl reset-failed "$SDDM_SERVICE_UNIT" 2>/dev/null || true
if [ -z "$SDDM_ROOT" ]; then
    if ! sudo systemctl start "$SDDM_SERVICE_UNIT"; then
        printf '!! sync failed — last %d journal lines:\n' "$JOURNAL_TAIL_LINES" >&2
        sudo journalctl -u "$SDDM_SERVICE_UNIT" -n "$JOURNAL_TAIL_LINES" --no-pager -o cat >&2 || true
        die "fix the above and re-run this installer"
    fi
    [ -f "$SDDM_CONF_FILE" ] || die "sync reported success but $SDDM_CONF_FILE is missing"
    log "$(grep '^Current=' "$SDDM_CONF_FILE")"
fi

# ── 6. Follow switches ───────────────────────────────────────────────────────
step "Enabling $SDDM_PATH_UNIT (refreshes on every render)"
real_only sudo systemctl enable --now "$SDDM_PATH_UNIT"

printf '\n:: Done — SDDM now follows the shell. Pick another look with:\n   %s/switch-sddm-theme.sh   (undo: %s)\n' \
    "$SCRIPT_DIR" "$SDDM_UNINSTALL_COMMAND"
