#!/bin/bash
# Shared view of the GRUB integration's installed (root-owned) state, sourced by
# setup-grub-theme.sh and doctor.sh so both judge "installed and current" the
# same way. Read-only: nothing here writes or needs root. Callers own
# `set -euo pipefail`.
#
# DCLI_INSTALL_ROOT=<dir> prefixes every system path (the same fixture override
# install-grub-theme.sh / uninstall-grub-theme.sh honour); tests/smoke.sh uses it.

# Not every constant is read by every sourcing script.
# shellcheck disable=SC2034
GRUB_COMMON_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
GRUB_REPO_DIR=$(dirname "$(dirname "$GRUB_COMMON_DIR")")
GRUB_SRC_DIR="$GRUB_REPO_DIR/scripts/grub"
GRUB_STAGING_DIR=$(readlink -m "$GRUB_REPO_DIR/state/grub-theme")
GRUB_ROOT="${DCLI_INSTALL_ROOT:-}"
GRUB_HELPER_INSTALLED="$GRUB_ROOT/usr/local/libexec/dcli-grub-sync"
GRUB_D_INSTALLED="$GRUB_ROOT/etc/grub.d/42_dcli_shells"
GRUB_UNIT_DIR="$GRUB_ROOT/etc/systemd/system"
GRUB_DEFAULT_FILE="$GRUB_ROOT/etc/default/grub"
GRUB_THEMES_INSTALLED="$GRUB_ROOT/boot/grub/themes/dcli"
GRUB_STATE_INSTALLED="$GRUB_ROOT/var/lib/dcli-grub"
GRUB_PREV_THEME_FILE="$GRUB_STATE_INSTALLED/previous-grub-theme"
GRUB_PATH_UNIT=dcli-grub-theme.path
GRUB_SERVICE_UNIT=dcli-grub-theme.service
# User-scope pair: re-render on a wallpaper change (the root pair installs).
GRUB_RENDER_PATH_UNIT=dcli-grub-render.path
GRUB_RENDER_SERVICE_UNIT=dcli-grub-render.service
if [ -n "$GRUB_ROOT" ]; then
    GRUB_USER_UNIT_DIR="$GRUB_ROOT/user-units"
else
    GRUB_USER_UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
fi
GRUB_THEME_VALUE='/boot/grub/themes/dcli/active/theme.txt'
GRUB_ACTIVE_MARKER=.dcli-shell
GRUB_MODULE_FILE="$GRUB_REPO_DIR/modules/grub-theme.yaml"
# Both scripts run as you and call sudo themselves — never prefix them with it.
GRUB_INSTALL_COMMAND="$GRUB_REPO_DIR/scripts/install-grub-theme.sh"
GRUB_UNINSTALL_COMMAND="$GRUB_REPO_DIR/scripts/uninstall-grub-theme.sh"

# The module's `packages:` list, one per line — the single home of the GRUB
# layer's dependencies, so the installer's check can never drift from dcli's.
grub_module_packages() {
    awk '/^packages:/ { in_list = 1; next }
         in_list && /^[^[:space:]#-]/ { exit }
         in_list && /^[[:space:]]*-[[:space:]]/ { sub(/^[[:space:]]*-[[:space:]]*/, ""); sub(/[[:space:]#].*/, ""); print }' \
        "$GRUB_MODULE_FILE"
}

# One line per way the installed integration is missing or stale; empty output
# means current. The path unit's enablement is left to the caller (it needs
# systemctl, which fixtures lack).
grub_integration_problems() {
    local installed source pair
    for pair in "$GRUB_HELPER_INSTALLED|$GRUB_SRC_DIR/dcli-grub-sync" "$GRUB_D_INSTALLED|$GRUB_SRC_DIR/42_dcli_shells"; do
        installed=${pair%%|*}
        source=${pair#*|}
        if [ ! -f "$installed" ]; then
            echo "${installed#"$GRUB_ROOT"} not installed"
        elif ! cmp -s "$installed" "$source"; then
            echo "${installed#"$GRUB_ROOT"} differs from scripts/grub/${source##*/}"
        fi
    done
    if ! grep -qxF "PathChanged=$GRUB_STAGING_DIR/.stamp" "$GRUB_UNIT_DIR/$GRUB_PATH_UNIT" 2>/dev/null; then
        echo "dcli-grub-theme.path missing or watching another staging dir"
    fi
    if ! grep -qF -- "--staging $GRUB_STAGING_DIR" "$GRUB_UNIT_DIR/$GRUB_SERVICE_UNIT" 2>/dev/null; then
        echo "dcli-grub-theme.service missing or pointing at another staging dir"
    fi
    if ! grep -qF -- "ExecStart=$GRUB_REPO_DIR/scripts/render-grub-theme.sh --changed all" \
        "$GRUB_USER_UNIT_DIR/$GRUB_RENDER_SERVICE_UNIT" 2>/dev/null; then
        echo "user unit $GRUB_RENDER_SERVICE_UNIT missing or pointing at another renderer"
    fi
    if ! grep -q '^PathChanged=' "$GRUB_USER_UNIT_DIR/$GRUB_RENDER_PATH_UNIT" 2>/dev/null; then
        echo "user unit $GRUB_RENDER_PATH_UNIT missing (wallpaper changes would not re-render)"
    fi
    if ! grep -qE "^[[:space:]]*GRUB_THEME=\"?$GRUB_THEME_VALUE\"?[[:space:]]*\$" "$GRUB_DEFAULT_FILE" 2>/dev/null; then
        echo "GRUB_THEME in /etc/default/grub is not $GRUB_THEME_VALUE"
    fi
}
