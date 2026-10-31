#!/bin/bash
# Choose which shell's look the SDDM login screen wears.
#
# Usage: switch-sddm-theme.sh [auto|<shell>|--list|--status]
#   auto      follow the running shell (the default; every shell switch updates it)
#   <shell>   pin one registry shell's theme, whatever is running
#   --list    the choices, current one marked
#   --status  one line: mode, resolved theme, whether root has installed it
#   (none)    pick interactively: fuzzel when a session is up, else a numbered prompt
#
# Writes the selector (~/.local/state/dcli/sddm-theme) and re-renders; the root
# path unit installs the result (docs/SDDM.md). Needs no sudo.
set -uo pipefail

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
# shellcheck source=lib/shell-common.sh disable=SC1091
. "$SCRIPT_DIR/lib/shell-common.sh" || exit 1
# shellcheck source=lib/sddm-common.sh disable=SC1091
. "$SCRIPT_DIR/lib/sddm-common.sh" || exit 1

RENDERER="$SCRIPT_DIR/render-sddm-theme.sh"

die() { echo "switch-sddm-theme: $*" >&2; exit 1; }

valid_choice() {
    local c="$1" k
    [ "$c" = "$SDDM_MODE_AUTO" ] && return 0
    for k in "${KNOWN[@]}"; do [ "$k" = "$c" ] && return 0; done
    return 1
}

resolved() {
    local mode
    mode=$(sddm_mode)
    if [ "$mode" = "$SDDM_MODE_AUTO" ]; then current_shell; else echo "$mode"; fi
}

list_choices() {
    local mode record name blurb mark
    mode=$(sddm_mode)
    mark=' '
    [ "$mode" = "$SDDM_MODE_AUTO" ] && mark='*'
    echo "$mark auto|Follow the running shell (now: $(current_shell))"
    for record in "${SHELL_RECORDS[@]}"; do
        name=${record%%|*}
        blurb=${record##*|}
        mark=' '
        [ "$mode" = "$name" ] && mark='*'
        echo "$mark $name|$blurb"
    done
}

apply() {
    local choice="$1"
    valid_choice "$choice" || die "unknown choice '$choice' (try --list)"
    mkdir -p "$(dirname "$SDDM_MODE_FILE")" || die "cannot create $(dirname "$SDDM_MODE_FILE")"
    printf '%s\n' "$choice" >"$SDDM_MODE_FILE" || die "cannot write $SDDM_MODE_FILE"
    "$RENDERER" all || die "render failed"
    echo "SDDM theme: $choice (login screen wears: $(resolved))"
}

pick() {
    local choice
    if [ -n "${WAYLAND_DISPLAY:-}" ] && command -v fuzzel >/dev/null 2>&1; then
        choice=$(list_choices | sed 's/^[* ] //; s/|/  ·  /' | fuzzel --dmenu --prompt 'SDDM › ' | awk '{print $1}')
    else
        local -a names
        mapfile -t names < <(list_choices | sed 's/^[* ] //; s/|.*//')
        local i=1
        list_choices | sed 's/^\([* ]\) \([^|]*\)|\(.*\)/\1 \2 — \3/' | while IFS= read -r line; do
            printf '%2d) %s\n' "$i" "$line"
            i=$((i + 1))
        done
        read -r -p "Select [1-${#names[@]}]: " n || exit 1
        [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le "${#names[@]}" ] || die "invalid selection"
        choice=${names[$((n - 1))]}
    fi
    [ -n "$choice" ] || exit 0
    apply "$choice"
}

case "${1:-}" in
--list) list_choices | sed 's/|/  /' ;;
--status)
    theme="$SDDM_THEME_PREFIX$(resolved)"
    state=missing
    [ -f "$SDDM_THEMES_INSTALLED/$theme/Main.qml" ] && state=installed
    echo "mode=$(sddm_mode) theme=$theme root=$state conf=$(grep -h '^Current=' "$SDDM_CONF_FILE" 2>/dev/null || echo none)"
    ;;
"") pick ;;
-h | --help) sed -n '2,13p' "$0" ;;
*) apply "$1" ;;
esac
