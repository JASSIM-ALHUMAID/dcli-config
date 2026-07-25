#!/bin/bash
# Switch the installed quickshell provider: stock | git
# Usage: switch-quickshell.sh [stock|git]
#   no argument = report the current provider and exit
#
# Why this script exists instead of plain `dcli module enable`:
#
#   1. dcli's module-level `conflicts:` only PROMPTS at enable time
#      ("Disable conflicting module(s)? [y/N]"). It never uninstalls anything.
#   2. auto_prune is false on this host, so `dcli sync` will not remove the
#      outgoing provider either.
#   3. dcli installs with `pacman -S --noconfirm`, which cannot answer pacman's
#      "quickshell-git and quickshell are in conflict. Remove quickshell? [y/N]"
#      prompt — so a sync alone can never complete the swap.
#
# So the provider swap is done here as ONE interactive pacman transaction (the
# only safe order: removing the old provider first would break dms-shell's
# dependency and pacman would refuse). dcli module state is updated around it and
# `dcli sync` reconciles the rest.
#
# See docs/PACKAGE-CONFLICTS.md for the background.

set -u

# Prevent concurrent runs — this mutates both dcli config and the package db.
LOCKFILE="/tmp/switch-quickshell.lock"
exec 200>"$LOCKFILE"
flock -n 200 || { echo "switch-quickshell.sh: another instance is running"; exit 1; }

REPO_DIR=$(dirname "$(dirname "$(readlink -f "$0")")")

KNOWN=(stock git)

provider_pkg() {
  case "$1" in
  stock) echo "quickshell" ;;
  git) echo "quickshell-git" ;;
  esac
}

provider_module() {
  case "$1" in
  stock) echo "shells-quickshell" ;;
  git) echo "shells-quickshell-git" ;;
  esac
}

other() {
  case "$1" in
  stock) echo "git" ;;
  git) echo "stock" ;;
  esac
}

# Which provider is actually installed right now, per pacman.
current_provider() {
  if pacman -Qq quickshell-git >/dev/null 2>&1; then
    echo git
  elif pacman -Qq quickshell >/dev/null 2>&1; then
    echo stock
  else
    echo none
  fi
}

module_enabled() {
  dcli module list -j 2>/dev/null |
    jq -e --arg m "$1" 'any(.modules[]; .name == $m and .enabled)' >/dev/null 2>&1
}

TARGET="${1:-}"

if [ -z "$TARGET" ]; then
  cur=$(current_provider)
  echo "Installed quickshell provider: $cur"
  for p in "${KNOWN[@]}"; do
    m=$(provider_module "$p")
    module_enabled "$m" && state="enabled" || state="disabled"
    printf '  %-6s  %-22s  module %s\n' "$p" "$(provider_pkg "$p")" "$state"
  done
  echo
  echo "Usage: switch-quickshell.sh [stock|git]"
  exit 0
fi

case " ${KNOWN[*]} " in
*" $TARGET "*) ;;
*)
  echo "Unknown provider: $TARGET (choose from: ${KNOWN[*]})"
  exit 1
  ;;
esac

OTHER=$(other "$TARGET")
TARGET_PKG=$(provider_pkg "$TARGET")
TARGET_MOD=$(provider_module "$TARGET")
OTHER_MOD=$(provider_module "$OTHER")

# caelestia-shell >= 2.2.0 hard-depends on quickshell-git. Switching to stock
# while caelestia is enabled cannot resolve, so refuse rather than let pacman
# offer to remove caelestia-shell.
if [ "$TARGET" = "stock" ] && module_enabled caelestia; then
  cat >&2 <<EOF
Refusing to switch to the stock provider: the 'caelestia' module is enabled and
caelestia-shell >= 2.2.0 hard-depends on quickshell-git.

Disable it first if you really want the stock provider:

    dcli module disable caelestia
    $0 stock
EOF
  exit 1
fi

if [ "$(current_provider)" = "$TARGET" ] && module_enabled "$TARGET_MOD"; then
  echo "Already on the $TARGET provider ($TARGET_PKG) — nothing to do."
  exit 0
fi

echo ":: Switching quickshell provider to $TARGET ($TARGET_PKG)"

# Running shells hold the old quickshell binary open. Stop them so the swap
# doesn't leave a half-dead shell against a replaced library.
if [ -x "$REPO_DIR/scripts/switch-shell.sh" ] && [ -n "${WAYLAND_DISPLAY:-}" ]; then
  echo ":: Stopping running shells first"
  pkill -f "qs -c" 2>/dev/null
  pkill -x quickshell 2>/dev/null
  pkill -f "dms run" 2>/dev/null
fi

# 1) dcli module state — disable the outgoing provider before enabling the
#    incoming one so `dcli module enable` has no conflict left to prompt about.
if module_enabled "$OTHER_MOD"; then
  echo ":: Disabling module $OTHER_MOD"
  dcli module disable "$OTHER_MOD" || exit 1
fi
if ! module_enabled "$TARGET_MOD"; then
  echo ":: Enabling module $TARGET_MOD"
  dcli module enable "$TARGET_MOD" --skip-sync || exit 1
fi

# 2) The package swap itself — interactive on purpose. pacman replaces the
#    conflicting provider in a single transaction and asks before doing so;
#    answer yes to that prompt. Uses the host's AUR helper when present because
#    quickshell-git may come from the AUR on other hosts.
echo ":: Installing $TARGET_PKG (answer 'y' to the conflict prompt)"
if command -v paru >/dev/null 2>&1; then
  paru -S --needed "$TARGET_PKG" || exit 1
else
  sudo pacman -S --needed "$TARGET_PKG" || exit 1
fi

# 3) Reconcile everything else dcli tracks (caelestia-*, dms-shell, ...).
echo ":: Reconciling with dcli sync"
dcli sync || exit 1

echo
echo ":: Now on the $TARGET provider: $(pacman -Q "$TARGET_PKG")"
echo ":: Relaunch a shell with: scripts/switch-shell.sh <name>"
