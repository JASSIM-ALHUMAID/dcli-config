#!/bin/bash
# Install the GRUB theming layer: GRUB follows the active shell (docs/GRUB.md).
# Run as yourself — NOT with sudo; the root steps call sudo themselves:
#   scripts/install-grub-theme.sh
# Re-running is the upgrade path: it reinstalls the root-owned copies from the
# repo and leaves the remembered pre-install GRUB_THEME alone.
#
# This is the ONE moment repo files are copied into root-owned locations, under
# your sudo. From then on root only runs those installed copies; nothing in the
# repo is executed or sourced by root at runtime.
#
# Installs:
#   /usr/local/libexec/dcli-grub-sync        root side of the sync (0755)
#   /etc/grub.d/42_dcli_shells               "Shells" submenu generator (0755)
#   /etc/systemd/system/dcli-grub-theme.{path,service}   units, user + staging baked in
#   GRUB_THEME in /etc/default/grub          -> dcli/active/theme.txt (the one edited key)
#   ~/.config/systemd/user/dcli-grub-render.{path,service}   (as you) re-render on a
#                                            wallpaper change, watching lib/wallpaper.sh's files
# Reverse it with scripts/uninstall-grub-theme.sh.
#
# DCLI_INSTALL_ROOT=<dir> redirects every system file to <dir> and drops sudo,
# the dependency check, the render, systemctl and grub-mkconfig (tests only).

set -euo pipefail

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
# shellcheck source=lib/shell-common.sh disable=SC1091
. "$SCRIPT_DIR/lib/shell-common.sh" || exit 1
# shellcheck source=lib/grub-common.sh disable=SC1091
. "$SCRIPT_DIR/lib/grub-common.sh" || exit 1
# shellcheck source=lib/wallpaper.sh disable=SC1091
. "$SCRIPT_DIR/lib/wallpaper.sh" || exit 1

# ── Constants ────────────────────────────────────────────────────────────────
RENDERER="$SCRIPT_DIR/render-grub-theme.sh"
ABSENT_MARK='<absent>'
# Values land in unit files, where % and whitespace are special.
UNIT_VALUE_RE='^[A-Za-z0-9._/@+-]+$'
USER_RE='^[a-z_][a-z0-9_-]*$'
JOURNAL_TAIL_LINES=25
STEP_COUNT=8
STEP=0

if [ -n "$GRUB_ROOT" ]; then
    SUDO=()
    OWNER=()
else
    SUDO=(sudo)
    OWNER=(-o root -g root)
fi

step() { STEP=$((STEP + 1)); printf '\n:: [%d/%d] %s\n' "$STEP" "$STEP_COUNT" "$*"; }
log() { printf '   %s\n' "$*"; }
die() { printf '!! %s\n' "$*" >&2; exit 1; }

# Skipped under DCLI_INSTALL_ROOT, where no real system is being touched.
real_only() { [ -n "$GRUB_ROOT" ] || "$@"; }

# ── Preconditions ────────────────────────────────────────────────────────────
[ $# -eq 0 ] || die "usage: install-grub-theme.sh   (no arguments; run as yourself, not with sudo)"
[ "$(id -u)" -ne 0 ] || die "do not run this with sudo — run it as yourself; it asks for sudo when it needs it"

REAL_USER=$(id -un)
[[ "$REAL_USER" =~ $USER_RE ]] || die "unexpected user name: $REAL_USER"
[[ "$GRUB_STAGING_DIR" =~ $UNIT_VALUE_RE ]] || die "staging path has characters unsafe for a unit file: $GRUB_STAGING_DIR"
for f in dcli-grub-sync 42_dcli_shells "$GRUB_PATH_UNIT" "$GRUB_SERVICE_UNIT" \
    "$GRUB_RENDER_PATH_UNIT" "$GRUB_RENDER_SERVICE_UNIT"; do
    [ -f "$GRUB_SRC_DIR/$f" ] || die "missing $GRUB_SRC_DIR/$f"
done
[ -x "$RENDERER" ] || die "$RENDERER is missing or not executable"
[ -f "$GRUB_DEFAULT_FILE" ] || die "$GRUB_DEFAULT_FILE not found"

echo "dcli GRUB theme installer — root steps will ask for your sudo password once"
real_only sudo -v || die "sudo authentication failed"

# ── 1. Dependencies ──────────────────────────────────────────────────────────
step "Checking dependencies (modules/grub-theme.yaml)"
mapfile -t packages < <(grub_module_packages)
[ "${#packages[@]}" -gt 0 ] || die "no packages: list found in $GRUB_MODULE_FILE"
if [ -z "$GRUB_ROOT" ]; then
    # pacman -T prints exactly the unsatisfied targets; empty = all present.
    missing=$(pacman -T "${packages[@]}" || true)
    if [ -n "$missing" ]; then
        mapfile -t missing_list <<<"$missing"
        log "installing: ${missing_list[*]}"
        sudo pacman -S --needed --noconfirm "${missing_list[@]}" || die "pacman could not install: ${missing_list[*]}"
    fi
fi
log "ok: ${packages[*]}"

# ── 2. Render (as you) ───────────────────────────────────────────────────────
# Rendered before anything root-side exists, with the CURRENT shell as active,
# so the first sync never installs a stale or partial staging tree.
active=$(current_shell)
step "Rendering every shell's theme (active: ${active:-?})"
if [ -z "$GRUB_ROOT" ]; then
    [ -n "$active" ] || die "could not read the active shell from active.conf"
    "$RENDERER" --active "$active" all || die "render failed — fix it and re-run this installer"
    [ -f "$GRUB_STAGING_DIR/active" ] || die "renderer finished but nothing is staged at $GRUB_STAGING_DIR"
fi

# ── 3. Root-owned copies ─────────────────────────────────────────────────────
step "Installing the root-owned helper and grub.d generator"
"${SUDO[@]}" install -d -m 0755 "$(dirname "$GRUB_HELPER_INSTALLED")" "$(dirname "$GRUB_D_INSTALLED")"
"${SUDO[@]}" install -m 0755 "${OWNER[@]}" "$GRUB_SRC_DIR/dcli-grub-sync" "$GRUB_HELPER_INSTALLED"
"${SUDO[@]}" install -m 0755 "${OWNER[@]}" "$GRUB_SRC_DIR/42_dcli_shells" "$GRUB_D_INSTALLED"
log "${GRUB_HELPER_INSTALLED#"$GRUB_ROOT"}"
log "${GRUB_D_INSTALLED#"$GRUB_ROOT"}"

# ── 4. Units ─────────────────────────────────────────────────────────────────
step "Installing systemd units for $REAL_USER"
"${SUDO[@]}" install -d -m 0755 "$GRUB_UNIT_DIR"
for unit in "$GRUB_PATH_UNIT" "$GRUB_SERVICE_UNIT"; do
    sed "s|@USER@|$REAL_USER|g; s|@STAGING@|$GRUB_STAGING_DIR|g" "$GRUB_SRC_DIR/$unit" |
        "${SUDO[@]}" install -m 0644 "${OWNER[@]}" /dev/stdin "$GRUB_UNIT_DIR/$unit"
    log "${GRUB_UNIT_DIR#"$GRUB_ROOT"}/$unit"
done
real_only sudo systemctl daemon-reload
# A failed earlier attempt leaves the oneshot "failed"; clear it so this run's
# result is the one reported.
real_only sudo systemctl reset-failed "$GRUB_SERVICE_UNIT" 2>/dev/null || true

# ── 5. First sync ────────────────────────────────────────────────────────────
step "Installing the themes into ${GRUB_THEMES_INSTALLED#"$GRUB_ROOT"}"
if [ -z "$GRUB_ROOT" ]; then
    if ! sudo systemctl start "$GRUB_SERVICE_UNIT"; then
        printf '!! sync failed — last %d journal lines:\n' "$JOURNAL_TAIL_LINES" >&2
        sudo journalctl -u "$GRUB_SERVICE_UNIT" -n "$JOURNAL_TAIL_LINES" --no-pager -o cat >&2 || true
        die "GRUB was not touched (GRUB_THEME unchanged); fix the above and re-run this installer"
    fi
    [ -f "$GRUB_THEMES_INSTALLED/active/theme.txt" ] || die "sync reported success but $GRUB_THEMES_INSTALLED/active/theme.txt is missing"
    log "active: $(cat "$GRUB_THEMES_INSTALLED/active/$GRUB_ACTIVE_MARKER" 2>/dev/null || echo '?')"
fi

# ── 6. /etc/default/grub + grub.cfg ──────────────────────────────────────────
# Only GRUB_THEME is edited, in place. The pre-install line (or its absence) is
# remembered ONCE, so a re-run never overwrites it with our own value.
step "Pointing GRUB_THEME at the dcli themes and regenerating grub.cfg"
current_line=$(grep -m1 -E '^[[:space:]]*GRUB_THEME=' "$GRUB_DEFAULT_FILE" || true)
"${SUDO[@]}" install -d -m 0755 "$GRUB_STATE_INSTALLED"
if [ ! -f "$GRUB_PREV_THEME_FILE" ]; then
    printf '%s\n' "${current_line:-$ABSENT_MARK}" |
        "${SUDO[@]}" install -m 0644 "${OWNER[@]}" /dev/stdin "$GRUB_PREV_THEME_FILE"
    log "remembered previous: ${current_line:-<none>}"
fi
"${SUDO[@]}" cp -p "$GRUB_DEFAULT_FILE" "$GRUB_DEFAULT_FILE.dcli-bak-$(date +%Y%m%d-%H%M%S)"
if [ -n "$current_line" ]; then
    "${SUDO[@]}" sed -i -E "s|^[[:space:]]*GRUB_THEME=.*\$|GRUB_THEME=\"$GRUB_THEME_VALUE\"|" "$GRUB_DEFAULT_FILE"
else
    printf 'GRUB_THEME="%s"\n' "$GRUB_THEME_VALUE" | "${SUDO[@]}" tee -a "$GRUB_DEFAULT_FILE" >/dev/null
fi
log "GRUB_THEME=\"$GRUB_THEME_VALUE\""
# The themes place everything at 1920x1080 pixel coordinates and need gfxterm.
if ! grep -qE '^[[:space:]]*GRUB_GFXMODE="?1920x1080' "$GRUB_DEFAULT_FILE"; then
    log "note: GRUB_GFXMODE is not 1920x1080 — the themes are laid out for that mode"
fi
if grep -qE '^[[:space:]]*GRUB_TERMINAL(_OUTPUT)?="?console' "$GRUB_DEFAULT_FILE"; then
    log "warning: GRUB_TERMINAL/GRUB_TERMINAL_OUTPUT is console — the theme will not render"
fi
if [ -z "$GRUB_ROOT" ]; then
    # Rendering may have outlived sudo's timestamp; refresh before the long step.
    sudo -v || die "sudo authentication failed"
    sudo grub-mkconfig -o /boot/grub/grub.cfg || die "grub-mkconfig failed (the old grub.cfg is untouched)"
fi

# ── 7. Follow switches ───────────────────────────────────────────────────────
step "Enabling $GRUB_PATH_UNIT (re-installs on every render)"
real_only sudo systemctl enable --now "$GRUB_PATH_UNIT"

# ── 8. Follow wallpaper changes (user units) ─────────────────────────────────
# Systemd watches each shell's own wallpaper state file; the renderer's
# --changed check keeps the frequent unrelated writes free.
step "Enabling $GRUB_RENDER_PATH_UNIT (re-renders on a wallpaper change)"
mkdir -p "$GRUB_USER_UNIT_DIR" || die "cannot create $GRUB_USER_UNIT_DIR"
sed "s|@RENDERER@|$RENDERER|g" "$GRUB_SRC_DIR/$GRUB_RENDER_SERVICE_UNIT" \
    >"$GRUB_USER_UNIT_DIR/$GRUB_RENDER_SERVICE_UNIT" || die "cannot write $GRUB_RENDER_SERVICE_UNIT"
watched=$(wallpaper_state_files | while IFS= read -r file; do
    [[ "$file" =~ $UNIT_VALUE_RE ]] && echo "PathChanged=$file"
done)
[ -n "$watched" ] || die "no wallpaper state files to watch (scripts/lib/wallpaper.sh)"
awk -v lines="$watched" '$0 == "@PATH_CHANGED@" { print lines; next } { print }' \
    "$GRUB_SRC_DIR/$GRUB_RENDER_PATH_UNIT" >"$GRUB_USER_UNIT_DIR/$GRUB_RENDER_PATH_UNIT" ||
    die "cannot write $GRUB_RENDER_PATH_UNIT"
log "watching $(grep -c . <<<"$watched") wallpaper state files"
real_only systemctl --user daemon-reload
real_only systemctl --user enable --now "$GRUB_RENDER_PATH_UNIT"

printf '\n:: Done — GRUB now follows the shell. Switch shells as usual; undo with:\n   %s\n' "$GRUB_UNINSTALL_COMMAND"
