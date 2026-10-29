#!/bin/bash
# Bootstrap the end4-pC shell — pctrade's fork of end-4 dots-hyprland
# (illogical-impulse). Runs alongside the existing "end4" (ii) shell as a
# separate, independent quickshell config named "end4-pC".
#
# CRITICAL: like end-4's illogical-impulse-quickshell-git, we do NOT install any
# packaged quickshell fork — each one Conflicts=quickshell and would fight the
# provider owned by modules/shells-quickshell{,-git}.yaml. The config runs on
# whichever provider is enabled, with the fork's extra deps installed as regular
# packages. See docs/PACKAGE-CONFLICTS.md.
#
# This shell's runtime deps are the SAME set as shell-end4's; they are declared
# in modules/shell-end4pc.yaml as well (dcli dedups) so that end4-pC stands on
# its own if shell-end4 is disabled.
#
# Layout this script produces:
#   ~/.local/share/end4-pC         — pctrade/end4-pC checkout on branch main
#                                    (source of truth). The repo root IS the
#                                    quickshell config (flat layout — no
#                                    dots/.config/... wrapper like the ii fork).
#   ~/.config/quickshell/end4-pC   — symlink -> the checkout root
#
# No matugen symlink: end4-pC ships no matugen config and reuses the shared
# ~/.config/matugen owned by the ii (end4) checkout.
#
# The shell also writes its own runtime state under ~/.config (e.g.
# ~/.config/illogical-impulse) — nothing to do for that.
#
# Safe to re-run: it never clones over an existing setup, and skips symlinks
# that are already correct.
set -euo pipefail

# shellcheck source=lib/hook-common.sh disable=SC1091
. "$(dirname "$(readlink -f "$0")")/lib/hook-common.sh" || exit 1

REPO_URL="https://github.com/pctrade/end4-pC.git"
REPO_BRANCH="main"
REPO_DIR="$REAL_HOME/.local/share/end4-pC"
QS_CONF="$REAL_HOME/.config/quickshell/end4-pC"

# 1) Clone the fork on branch main (full clone; submodules stay shallow. The
#    config has a .gitmodules and, like the ii fork, fails to load without its
#    submodules populated).
clone_checkout "$REPO_DIR" "$REPO_URL" "$REPO_BRANCH" "end4-pC" --opt-in shell-end4pc \
    --recurse-submodules --shallow-submodules
# Ensure submodules exist even on a pre-existing clone.
update_submodules "$REPO_DIR"

# 2) Symlink ~/.config/quickshell/end4-pC -> checkout root (the repo IS the config).
ensure_symlink "$REPO_DIR" "$QS_CONF" refuse || exit 1

# 3) Repoint the checkout at end4pc-owned paths (hypr overrides, shell config
#    dir, matugen config) and seed ~/.config/illogical-impulse-pC/config.json.
#    See scripts/patch-end4pc.sh for what and why. Idempotent.
#    Called directly, not via as_user: it does its own SUDO_USER handling, and
#    re-sudoing would make it resolve REAL_USER as root.
echo ":: Patching end4-pC paths"
bash "$(dirname "$(readlink -f "$0")")/patch-end4pc.sh"

echo ":: end4-pC shell ready — launch with 'qs -c end4-pC', switch with switch-shell.sh end4pc"
