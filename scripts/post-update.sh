#!/usr/bin/env bash
# Post-update self-heal, wired as update_hooks.post_update in hosts/*.yaml.
#
# WHY: quickshell links Qt's *private* API (Qt_6_PRIVATE_API), which carries no
# ABI guarantee even across patch releases. On 2026-08-22 a routine `dcli update`
# moved qt6-base 6.11.1 -> 6.11.2 and every quickshell-based shell (caelestia,
# ambxst, dms, end4, end4pc, xenon) died at once with:
#
#   qs: symbol lookup error: undefined symbol:
#       _ZN23QUntypedPropertyBindingC1EP23QPropertyBindingPrivate, version Qt_6_PRIVATE_API
#
# Nothing in dcli noticed: update_hooks were null, and `devel: false` means
# `dcli update` never passes --devel. The only warning was CachyOS's own
# quickshell-check.hook printing the error mid-transaction, where it scrolled
# past among 200 other upgrades. See docs/PACKAGE-CONFLICTS.md.

set -u

log="${HOME}/.local/state/dcli-quickshell-heal.log"
ts() { date '+%F %T'; }
note() { echo "[$(ts)] $*" >>"$log"; }

# ── Root guard ───────────────────────────────────────────────────────────────
# paru refuses to build as root, and under root $HOME is /root — the log would
# land in the wrong place and notify-send would never reach the user's session
# bus. Prefer run_as_user: true in the host config; this is the backstop.
if [ "$(id -u)" -eq 0 ]; then
    real_user="${SUDO_USER:-}"
    if [ -z "$real_user" ]; then
        echo "post-update: running as root with no SUDO_USER; cannot rebuild. " \
             "Set update_hooks.run_as_user: true." >&2
        exit 1
    fi
    exec runuser -u "$real_user" -- "$0" "$@"
fi

mkdir -p "$(dirname "$log")"

# ── Provider identification ──────────────────────────────────────────────────
# NB: `pacman -Qq quickshell-git` is NOT a name test — it resolves Provides too.
# With quickshell-git installed, `pacman -Qq quickshell` prints "quickshell-git";
# and noctalia-qs declares Provides=quickshell,quickshell-git, so it would also
# satisfy that query. Match the literal installed package name instead.
installed_name() { pacman -Qq 2>/dev/null | grep -qx "$1"; }

# noctalia-qs Conflicts with BOTH quickshell and quickshell-git, so if it is ever
# installed it has replaced the provider caelestia-shell and dms-shell depend on.
# Noctalia v5 is native C++ and needs no quickshell at all — it should never be
# here. Rebuilding on top of it cannot succeed, so bail out loudly instead.
if installed_name noctalia-qs; then
    note "noctalia-qs is installed - it conflicts with the real quickshell provider"
    notify-send -u critical -a dcli "Wrong quickshell provider" \
        "noctalia-qs replaced quickshell-git. Fix: paru -R noctalia-qs && paru -S aur/quickshell-git" \
        -i dialog-error 2>/dev/null
    exit 1
fi

installed_name quickshell-git || exit 0
command -v qs >/dev/null 2>&1 || exit 0

# ── ABI check ────────────────────────────────────────────────────────────────
# --private-check-compat is quickshell's own ABI probe — the same one CachyOS's
# quickshell-check.hook runs. Exits 0 when the binary matches the installed Qt.
if qs --private-check-compat >/dev/null 2>&1; then
    exit 0
fi

note "qt6 update broke quickshell ABI, rebuilding quickshell-git"
notify-send -a dcli "Quickshell broke" "Qt6 ABI mismatch detected. Rebuilding quickshell-git..." -i dialog-warning 2>/dev/null

helper=$(command -v paru || command -v yay || true)
if [ -z "$helper" ]; then
    note "no AUR helper found, cannot self-heal"
    exit 1
fi

# The rebuild needs sudo for its install step. A long `dcli update` can outlive
# sudo's 5-minute credential cache, and --noconfirm does not imply --no-password:
# without this the build would finish and then block on a password prompt.
if ! sudo -v 2>/dev/null; then
    note "sudo credentials unavailable - cannot rebuild unattended"
    notify-send -u critical -a dcli "Quickshell still broken" \
        "Rebuild needs sudo. Run: $helper -S --rebuild aur/quickshell-git" -i dialog-error 2>/dev/null
    exit 1
fi

# `aur/` is REQUIRED. CachyOS dropped its own quickshell-git binary package, so
# the bare name now resolves to the repo package noctalia-qs via its Provides,
# and paru would offer to remove the real provider instead of rebuilding it.
if "$helper" -S --rebuild --noconfirm aur/quickshell-git >>"$log" 2>&1 \
    && qs --private-check-compat >/dev/null 2>&1; then
    note "rebuild OK"
    notify-send -a dcli "Quickshell healed" "quickshell-git was rebuilt against the new Qt6." -i dialog-information 2>/dev/null
else
    note "rebuild FAILED - manual fix: $helper -S --rebuild aur/quickshell-git"
    notify-send -u critical -a dcli "Quickshell still broken" \
        "Auto-rebuild failed. Run: $helper -S --rebuild aur/quickshell-git (see $log)" -i dialog-error 2>/dev/null
    exit 1
fi
