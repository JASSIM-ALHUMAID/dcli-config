#!/bin/bash
# Shared view of the SDDM integration's repo sources and installed (root-owned)
# state, sourced by render-sddm-theme.sh, install/uninstall-sddm-theme.sh,
# switch-sddm-theme.sh and doctor.sh. Read-only: nothing here writes or needs
# root. Callers own `set -euo pipefail`.
#
# DCLI_INSTALL_ROOT=<dir> prefixes every system path (the fixture override the
# GRUB layer also honours); tests/smoke.sh uses it.

# Not every constant is read by every sourcing script.
# shellcheck disable=SC2034
SDDM_COMMON_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
SDDM_REPO_DIR=$(dirname "$(dirname "$SDDM_COMMON_DIR")")
SDDM_SRC_DIR="$SDDM_REPO_DIR/scripts/sddm"
SDDM_THEME_SRC="$SDDM_REPO_DIR/sddm"
SDDM_BASE_SRC="$SDDM_THEME_SRC/base"
SDDM_SHELL_SRC="$SDDM_THEME_SRC/themes"
SDDM_STAGING_DIR=$(readlink -m "$SDDM_REPO_DIR/state/sddm-theme")
SDDM_ROOT="${DCLI_INSTALL_ROOT:-}"
SDDM_HELPER_INSTALLED="$SDDM_ROOT/usr/local/libexec/dcli-sddm-sync"
SDDM_UNIT_DIR="$SDDM_ROOT/etc/systemd/system"
SDDM_THEMES_INSTALLED="$SDDM_ROOT/usr/share/sddm/themes"
SDDM_CONF_DIR="$SDDM_ROOT/etc/sddm.conf.d"
SDDM_CONF_FILE="$SDDM_CONF_DIR/zz-dcli-theme.conf"
SDDM_THEME_PREFIX=dcli-
SDDM_PATH_UNIT=dcli-sddm-theme.path
SDDM_SERVICE_UNIT=dcli-sddm-theme.service
SDDM_MODE_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/dcli/sddm-theme"
SDDM_MODE_AUTO=auto
SDDM_MODULE_FILE="$SDDM_REPO_DIR/modules/sddm-theme.yaml"
# Both scripts run as you and call sudo themselves — never prefix them with it.
SDDM_INSTALL_COMMAND="$SDDM_REPO_DIR/scripts/install-sddm-theme.sh"
SDDM_UNINSTALL_COMMAND="$SDDM_REPO_DIR/scripts/uninstall-sddm-theme.sh"

# The module's `packages:` list, one per line.
sddm_module_packages() {
    awk '/^packages:/ { in_list = 1; next }
         in_list && /^[^[:space:]#-]/ { exit }
         in_list && /^[[:space:]]*-[[:space:]]/ { sub(/^[[:space:]]*-[[:space:]]*/, ""); sub(/[[:space:]#].*/, ""); print }' \
        "$SDDM_MODULE_FILE"
}

# The persisted selector: "auto" (follow the running shell) or a shell name.
sddm_mode() {
    local mode=""
    [ -r "$SDDM_MODE_FILE" ] && mode=$(head -n1 "$SDDM_MODE_FILE")
    echo "${mode:-$SDDM_MODE_AUTO}"
}

# One line per way the installed integration is missing or stale; empty output
# means current. The path unit's enablement is left to the caller.
sddm_integration_problems() {
    if [ ! -f "$SDDM_HELPER_INSTALLED" ]; then
        echo "${SDDM_HELPER_INSTALLED#"$SDDM_ROOT"} not installed"
    elif ! cmp -s "$SDDM_HELPER_INSTALLED" "$SDDM_SRC_DIR/dcli-sddm-sync"; then
        echo "${SDDM_HELPER_INSTALLED#"$SDDM_ROOT"} differs from scripts/sddm/dcli-sddm-sync"
    fi
    if ! grep -qxF "PathChanged=$SDDM_STAGING_DIR/.stamp" "$SDDM_UNIT_DIR/$SDDM_PATH_UNIT" 2>/dev/null; then
        echo "$SDDM_PATH_UNIT missing or watching another staging dir"
    fi
    if ! grep -qF -- "--staging $SDDM_STAGING_DIR" "$SDDM_UNIT_DIR/$SDDM_SERVICE_UNIT" 2>/dev/null; then
        echo "$SDDM_SERVICE_UNIT missing or pointing at another staging dir"
    fi
    local name
    for name in "${KNOWN[@]}"; do
        [ -f "$SDDM_THEMES_INSTALLED/$SDDM_THEME_PREFIX$name/Main.qml" ] ||
            echo "theme $SDDM_THEME_PREFIX$name not installed"
    done
}
