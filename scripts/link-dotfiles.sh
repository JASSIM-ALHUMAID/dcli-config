#!/bin/bash
# Symlink ~/.config/<dir> -> ~/.config/dcli/dotfiles/<dir> so every config
# edit lands directly in the dcli repo (then just: cd ~/.config/dcli && git
# commit / dcli repo push).
#
# This script is the actual dotfiles mechanism of this setup: dcli's flat
# YAML modules silently ignore their `dotfiles:` keys (only Lua/directory
# modules support them), so those keys are documentation and THIS script
# does the linking. Run it once per machine (it's also the base module's
# post-install hook). Idempotent; existing real dirs are backed up first.
#
# Deliberately NOT linked:
#   caelestia — symlink into the my-caelestia fork, owned by setup-caelestia.sh
#   wezterm   — its own git repo (JASSIM-ALHUMAID/wezterm) is the source of
#               truth; dcli keeps a snapshot copy only
set -euo pipefail

DOTFILES="$HOME/.config/dcli/dotfiles"
TARGETS=(hypr ambxst noctalia omarchy xenon DankMaterialShell matugen-end4pc matugen-ml4w fuzzel cava nvim yazi lazygit git environment.d)

ts=$(date +%Y%m%d-%H%M%S)
for name in "${TARGETS[@]}"; do
    src="$DOTFILES/$name"
    dst="$HOME/.config/$name"
    if [ ! -d "$src" ]; then
        echo "!! skip $name: $src missing from repo"
        continue
    fi
    if [ -L "$dst" ] && [ "$(readlink -f "$dst")" = "$(readlink -f "$src")" ]; then
        echo "ok $name (already linked)"
        continue
    fi
    if [ -e "$dst" ]; then
        mv "$dst" "$dst.bak-$ts"
        echo ":: $name: backed up -> $dst.bak-$ts"
    fi
    if ! ln -s "$src" "$dst" 2>/dev/null; then
        if [ "$(readlink -f "$dst")" = "$(readlink -f "$src")" ]; then
            echo ":: $name: linked $dst -> $src (created by a concurrent hook)"
        else
            echo "!! $name: $dst exists and is not the correct symlink — refusing to clobber." >&2
            exit 1
        fi
    else
        echo ":: $name: linked $dst -> $src"
    fi
done
echo "Done. Backups (if any) are at ~/.config/*.bak-$ts"
