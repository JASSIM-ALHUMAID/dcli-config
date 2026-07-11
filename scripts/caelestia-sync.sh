#!/bin/bash
# Sync the caelestia TESTING checkout with the PRODUCTION copy.
#
#   dev  (testing): ~/Projects/shell/real        — hack here, run with run-worktree.fish
#   prod (actual):  ~/.local/share/my-caelestia  — what the session shell is built from;
#                   ~/.config/caelestia -> prod/caelestia-configs (live config writes land here)
#
# What it does:
#   1) configs  prod -> dev   (live-edited shell.json/keybinds.json/... into the
#                              dev tree so git commits include current state)
#   2) code     dev  -> prod  (everything except caelestia-configs, .git, build)
#   3) with --install: rebuild + install the shell from prod (restarts qs)
#
# Usage: caelestia-sync.sh [--install] [--dry-run]
set -euo pipefail

DEV="${CAELESTIA_DEV:-$HOME/Projects/shell/real}"
PROD="${CAELESTIA_PROD:-$HOME/.local/share/my-caelestia}"

INSTALL=0
DRY=()
for arg in "$@"; do
    case "$arg" in
        --install|-i) INSTALL=1 ;;
        --dry-run|-n) DRY=(--dry-run -v) ;;
        *) echo "Usage: caelestia-sync.sh [--install] [--dry-run]"; exit 1 ;;
    esac
done

[ -d "$DEV/.git" ]  || { echo "!! dev checkout missing: $DEV" >&2; exit 1; }
[ -d "$PROD/.git" ] || { echo "!! prod copy missing: $PROD (clone the fork there first)" >&2; exit 1; }

echo ":: [1/2] configs: prod -> dev"
rsync -a "${DRY[@]}" "$PROD/caelestia-configs/" "$DEV/caelestia-configs/"

echo ":: [2/2] code: dev -> prod"
rsync -a --delete "${DRY[@]}" \
    --exclude '.git' \
    --exclude 'build' \
    --exclude 'caelestia-configs' \
    --exclude '.cache' \
    --exclude '.direnv' \
    --exclude '.superpowers' \
    --exclude '.worktrees' \
    --exclude 'logs' \
    "$DEV/" "$PROD/"

if [ "$INSTALL" -eq 1 ] && [ ${#DRY[@]} -eq 0 ]; then
    echo ":: rebuilding + installing shell from prod (restarts qs)"
    cd "$PROD"
    fish devfiles/install-user.fish
elif [ "$INSTALL" -eq 1 ]; then
    echo ":: (dry-run: skipping install)"
fi

echo ":: sync done. Review/commit in $DEV (git status) to publish."
