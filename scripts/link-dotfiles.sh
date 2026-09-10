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
#
# foot and btop used to be symlinks into ~/.local/share/caelestia (the upstream
# caelestia-dots clone, which setup-caelestia.sh overwrites on update). They are
# NOT caelestia's: DMS's matugen writes foot/dank-colors.ini and noctalia's
# optional hooks rewrite btop.conf, so a clone that gets wiped was silently
# eating other shells' output. They are dcli dotfiles now — remove the old
# symlinks before the first run, this script refuses to clobber a wrong one.
set -euo pipefail

DOTFILES="$HOME/.config/dcli/dotfiles"
TARGETS=(hypr ambxst noctalia omarchy xenon DankMaterialShell matugen-end4pc fuzzel cava foot btop nvim yazi lazygit git environment.d)

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

# ── swaync D-Bus activation guard ────────────────────────────────────────────
#
# swaync ships /usr/share/dbus-1/services/org.erikreider.swaync.service, which
# declares `Name=org.freedesktop.Notifications` + `SystemdService=swaync.service`.
# So ANY app sending a notification while no daemon holds that name will D-Bus
# auto-activate swaync — regardless of whether the unit is enabled, and
# regardless of which shell is active.
#
# That is how swaync hijacked notifications on 2026-08-22: quickshell was dead
# for ~2h after the Qt 6.11.2 ABI break, and the first notification sent in that
# window spawned swaync, which then held the name even after caelestia came back.
# switch-shell.sh only tears swaync down on a *switch*; it cannot see a rogue
# activation. See docs/PACKAGE-CONFLICTS.md and docs/shells/README.md.
#
# Masking is safe: switch-shell.sh launches it as `swaync & disown`
# (a direct exec), which a masked unit does not block. Only the D-Bus/systemd
# activation path is blocked.
if command -v systemctl >/dev/null 2>&1; then
    if [ "$(systemctl --user is-enabled swaync.service 2>/dev/null)" != "masked" ]; then
        systemctl --user mask swaync.service >/dev/null 2>&1 &&
            echo ":: masked swaync.service (blocks rogue D-Bus activation)"
    else
        echo "ok swaync.service (already masked)"
    fi
fi
