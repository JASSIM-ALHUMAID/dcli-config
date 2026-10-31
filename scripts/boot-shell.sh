#!/bin/bash
# Boot straight into a chosen shell: GRUB's "Shells" submenu appends
# `dcli.shell=<name>` to the kernel command line (docs/GRUB.md); this runs once
# per login from the Hyprland entry point (hyprland.start, never on reload) and
# hands that name to switch-shell.sh.
#
# Consumption is per boot, keyed by /proc/sys/kernel/random/boot_id and recorded
# BEFORE switching: a Hyprland restart in the same boot never re-applies it, a
# crashing switch can never loop, and a later plain boot (no parameter) simply
# changes nothing. Always exits 0 — a login must not be held up by this.
#
# Overrides (tests only): DCLI_CMDLINE_FILE, DCLI_BOOT_ID_FILE, DCLI_BOOT_STATE_DIR,
# DCLI_BOOT_SHELL_NO_WAIT=1 (skip the compositor/settle wait).

set -u

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

# ── Constants ────────────────────────────────────────────────────────────────
CMDLINE_FILE="${DCLI_CMDLINE_FILE:-/proc/cmdline}"
BOOT_ID_FILE="${DCLI_BOOT_ID_FILE:-/proc/sys/kernel/random/boot_id}"
STATE_DIR="${DCLI_BOOT_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/dcli}"
CONSUMED_FILE="$STATE_DIR/boot-shell"
CMDLINE_KEY=dcli.shell
# The starting shell's own exec-once must finish before it is torn down, and
# hyprctl must answer before switch-shell.sh's reload.
COMPOSITOR_POLL_ITERS=40
COMPOSITOR_POLL_INTERVAL=0.5
SETTLE_SECS=3

# shellcheck source=lib/shell-common.sh disable=SC1091
. "$SCRIPT_DIR/lib/shell-common.sh" || exit 0

# ── Request ──────────────────────────────────────────────────────────────────
[ -r "$CMDLINE_FILE" ] || exit 0
requested=$(tr ' ' '\n' <"$CMDLINE_FILE" | sed -n "s/^${CMDLINE_KEY//./\\.}=//p" | tail -n1)
[ -n "$requested" ] || exit 0

boot_id=$(cat "$BOOT_ID_FILE" 2>/dev/null) || exit 0
[ -n "$boot_id" ] || exit 0
if [ -f "$CONSUMED_FILE" ] && [ "$(head -n1 "$CONSUMED_FILE")" = "$boot_id" ]; then
    exit 0
fi

mkdir -p "$STATE_DIR" && printf '%s\n' "$boot_id" >"$CONSUMED_FILE" || exit 0

# ── Apply ────────────────────────────────────────────────────────────────────
case " ${KNOWN[*]} " in
*" $requested "*) ;;
*)
    echo "boot-shell.sh: ignoring unknown shell '$requested' from the kernel command line" >&2
    exit 0
    ;;
esac
[ "$requested" != "$(current_shell)" ] || exit 0

if [ "${DCLI_BOOT_SHELL_NO_WAIT:-0}" != 1 ]; then
    i=0
    while [ "$i" -lt "$COMPOSITOR_POLL_ITERS" ] && ! hyprctl version >/dev/null 2>&1; do
        sleep "$COMPOSITOR_POLL_INTERVAL"
        i=$((i + 1))
    done
    sleep "$SETTLE_SECS"
fi

"$SCRIPT_DIR/switch-shell.sh" "$requested" || echo "boot-shell.sh: switch to $requested failed" >&2
exit 0
