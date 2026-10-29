#!/bin/bash
# Bootstrap the xenon shell — MannuVilasara/xenon-shell, a Quickshell config
# run as an independent config named "xenon".
#
# No personal fork: cloned straight from upstream (branch main), like end4-pC
# and omarchy.
#
# Layout this script produces:
#   ~/.local/share/xenon-shell    — upstream checkout on branch main (source of
#                                   truth). The repo root IS the quickshell
#                                   config: shell.qml sits at the top level,
#                                   same flat layout as end4-pC.
#   ~/.config/quickshell/xenon    — symlink -> the checkout root
#
# ~/.config/xenon (config.json) is NOT created here: it is a dcli-tracked
# dotfile, linked by scripts/link-dotfiles.sh. Generated state lives in
# ~/.cache/xenon and is machine-local.
#
# /etc/xdg/quickshell/xenon is a pre-existing ROOT-OWNED clone that no package
# owns. It is deliberately left untouched: quickshell resolves configs from
# XDG_CONFIG_HOME first, so ~/.config/quickshell/xenon shadows it for the user
# session. Nothing in this script writes to /etc.
#
# CRITICAL: no quickshell provider package is declared anywhere for this shell.
# The provider has exactly one owner — modules/shells-quickshell{,-git}.yaml —
# and xenon runs on whichever one is enabled. See docs/PACKAGE-CONFLICTS.md.
#
# Safe to re-run: it never clones over an existing checkout and skips symlinks
# that are already correct.
set -euo pipefail

# shellcheck source=lib/hook-common.sh disable=SC1091
. "$(dirname "$(readlink -f "$0")")/lib/hook-common.sh" || exit 1

REPO_URL="https://github.com/MannuVilasara/xenon-shell.git"
REPO_BRANCH="main"
REPO_DIR="$REAL_HOME/.local/share/xenon-shell"
QS_CONF="$REAL_HOME/.config/quickshell/xenon"

# 1) Clone upstream on branch main. No submodules — the repo has none.
clone_checkout "$REPO_DIR" "$REPO_URL" "$REPO_BRANCH" "xenon-shell"

# 2) Runtime dependencies (upstream README + what the QML actually execs) are
#    declared in modules/shell-xenon.yaml so every sync re-checks them.
#    Scripts/*.py are stdlib-only, so there is no pip step.

# 3) Symlink ~/.config/quickshell/xenon -> checkout root (the repo IS the config).
ensure_symlink "$REPO_DIR" "$QS_CONF" refuse || exit 1

echo ":: xenon shell ready — launch with 'qs -c xenon', switch with switch-shell.sh xenon"
