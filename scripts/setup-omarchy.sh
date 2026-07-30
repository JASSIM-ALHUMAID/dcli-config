#!/bin/bash
# Bootstrap the omarchy shell — basecamp/omarchy, branch "quattro" (v4.0.0.alpha).
#
# WHAT THIS IS NOT: omarchy ships a whole-distro installer (install.sh). We never
# run it. It sets up sddm, plymouth, snapper snapshots, ufw, docker, PAM lockout
# limits and a chromium policy dir under /etc and /usr, and its config/ tree
# overwrites ~/.config for alacritty, foot, ghostty, btop, git, tmux, lazygit and
# nvim — all of which are dcli-symlinked here. This script reproduces by hand the
# only two user-level steps that matter: the checkout, and the theme seed from
# install/user/theme.sh.
#
# v4 is a good fit for this repo because it dropped waybar/walker: the whole
# desktop is now ONE quickshell instance, started as
#   quickshell -n -p $OMARCHY_PATH/shell
# and its Hyprland config is Lua. The v3 line (branch master) is .conf +
# waybar + walker + mako + swaybg and does not fit an all-Lua setup.
#
# CRITICAL: we do NOT install quickshell-git here even though it is in omarchy's
# package list. The quickshell provider is owned declaratively by
# modules/shells-quickshell{,-git}.yaml and must have exactly one owner — see
# docs/PACKAGE-CONFLICTS.md. omarchy runs on whichever provider is enabled.
#
# Layout this script produces:
#   ~/.local/share/omarchy          — the checkout; this is $OMARCHY_PATH
#     └ shell/                      — the quickshell shell (shell.qml + plugins/)
#     └ bin/                        — ~150 omarchy-* scripts, must be on PATH
#     └ default/hypr/*.lua          — Hyprland defaults, entered via bootstrap.lua
#   ~/.config/omarchy               — user config; linked to dcli by link-dotfiles.sh
#   ~/.local/state/omarchy          — generated state (current theme, toggles,
#                                     done markers). Machine-local, never in git.
#
# $OMARCHY_PATH defaults to /usr/share/omarchy upstream, and nothing in this repo
# puts it in the session environment on purpose — see docs/shells/omarchy.md for
# why that was a mistake the one time it was tried. This script exports it inline
# for the omarchy-* commands it runs; the Hyprland config resolves it itself.
#
# Safe to re-run: it never clones over an existing setup and never re-seeds a
# theme that is already set.
set -euo pipefail

# dcli may run hooks as root — always operate on the real user's home.
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

REPO_URL="https://github.com/basecamp/omarchy.git"
REPO_BRANCH="quattro"
OMARCHY_PATH="$REAL_HOME/.local/share/omarchy"
STATE_DIR="$REAL_HOME/.local/state/omarchy"
CONF_DIR="$REAL_HOME/.config/omarchy"

as_user() {
    if [ "$(id -u)" -eq 0 ] && [ "$REAL_USER" != "root" ]; then
        sudo -u "$REAL_USER" -H "$@"
    else
        "$@"
    fi
}

# omarchy-* scripts call each other by bare name and read $OMARCHY_PATH.
as_omarchy() {
    as_user env OMARCHY_PATH="$OMARCHY_PATH" PATH="$OMARCHY_PATH/bin:$PATH" "$@"
}

# 1) Clone upstream on the quattro branch. No submodules — the repo has none.
#    Unlike the other shells there is no personal fork: 4.0 is alpha and moves
#    daily, so we track upstream and fast-forward with update-omarchy.sh.
if [ -d "$OMARCHY_PATH/.git" ]; then
    echo ":: omarchy already cloned at $OMARCHY_PATH"
else
    if [ -e "$OMARCHY_PATH" ]; then
        echo "!! $OMARCHY_PATH exists but is not a git repo — refusing to touch it." >&2
        exit 1
    fi
    echo ":: Cloning omarchy (branch $REPO_BRANCH)"
    as_user mkdir -p "$(dirname "$OMARCHY_PATH")"
    as_user git clone --branch "$REPO_BRANCH" "$REPO_URL" "$OMARCHY_PATH"
fi

# 2) Runtime dependencies.
#
# Derived from install/omarchy-base.packages minus everything already present on
# this machine and everything that is a system decision or an app opinion. The
# full excluded list, for the record:
#
#   provider/system : quickshell-git hyprland uwsm sddm plymouth kernel-modules-hook
#   apps            : chromium obsidian libreoffice-fresh nautilus evince imv
#                     kdenlive obs-studio pinta moonlight-qt gnome-calculator
#                     gnome-disk-utility localsend xournalpp
#   toolchains      : docker* ruby rust mise luarocks dotnet-runtime
#                     postgresql-libs mariadb-libs tree-sitter-cli
#   omarchy's own repo (pkgs.omarchy.org, NOT on the AUR — these back the
#   `omarchy-menu` extras, not the shell itself):
#                     aether omacut omawrite tensaku cliamp tobi-try omarchy-nvim
#
# If something in that last group turns out to be load-bearing for the bar,
# record it in docs/shells/omarchy.md rather than quietly adding it here.
REPO_DEPS=(pamixer gum socat udiskie gnome-themes-extra)

# AUR-only (installed as the real user; AUR helpers refuse to run as root).
#   xdg-terminal-exec — how omarchy-launch-terminal resolves a terminal
#   yaru-icon-theme   — the icon theme its themes reference by name
AUR_DEPS=(xdg-terminal-exec yaru-icon-theme)

echo ":: Installing omarchy runtime dependencies"
if [ "$(id -u)" -eq 0 ]; then
    pacman -S --needed --noconfirm "${REPO_DEPS[@]}"
else
    sudo pacman -S --needed --noconfirm "${REPO_DEPS[@]}"
fi

if as_user command -v paru >/dev/null 2>&1; then
    echo ":: Installing AUR deps via paru"
    as_user paru -S --needed --noconfirm "${AUR_DEPS[@]}"
else
    echo ":: paru not found — skipping AUR deps: ${AUR_DEPS[*]}"
fi

# 3) State and user-config directories. ~/.config/omarchy itself is created and
#    linked into this repo by link-dotfiles.sh; only make its themes/ subdir,
#    which omarchy-theme-set expects to exist for user-supplied themes.
as_user mkdir -p "$STATE_DIR" "$STATE_DIR/toggles" "$STATE_DIR/done" "$CONF_DIR/themes"

# 4) Fence off the parts of omarchy's theming that reach outside its own dirs.
#    `omarchy-theme-set` fans out to editors on every theme change; these flag
#    files are omarchy's own opt-out (bin/omarchy-toggle-enabled), so we set
#    them rather than patching the checkout — patches would block a ff pull.
#    VSCodium is this machine's editor (hosts/cachyos-desktop.yaml default_apps).
for t in skip-vscode-theme-changes skip-vscode-insiders-theme-changes \
         skip-codium-theme-changes skip-cursor-theme-changes; do
    as_user touch "$STATE_DIR/toggles/$t"
done

# 5) Skip omarchy's first-run sequence. It is fired from omarchy's own
#    autostart.lua on every session start, and on a machine we did not install
#    with install.sh most of it is wrong or unwanted:
#      - installs pacman post-update hooks (voxtype, fingerprint)
#      - `systemctl --user enable --now` five units that only exist when the
#        omarchy package installed them (bt-agent, omarchy-sleep-lock, …)
#      - gsettings the GTK/icon theme for the whole user session, i.e. for the
#        other six shells too
#      - audio "speaker tuning" aimed at specific laptop hardware
#    Marking it done is omarchy's own mechanism (bin/omarchy-done), so nothing
#    is patched. Run `omarchy-first-run --force` by hand if you ever want it.
as_user touch "$STATE_DIR/done/first-run-user"

# 6) Seed the theme, mirroring install/user/theme.sh. The shell needs
#    ~/.local/state/omarchy/current/theme to exist: omarchy's Hyprland config
#    require()s omarchy.current.theme.hyprland from there, and the bar reads its
#    colours from the same place. Guarded, so a re-run never overrides the theme
#    you switched to.
if [ -s "$STATE_DIR/current/theme.name" ]; then
    echo ":: omarchy theme already set ($(cat "$STATE_DIR/current/theme.name"))"
else
    echo ":: Seeding omarchy theme: Tokyo Night"
    as_omarchy omarchy-theme-set "Tokyo Night"
fi

echo ":: omarchy ready — switch with switch-shell.sh omarchy"
echo "   (no relogin needed: the Hyprland config resolves OMARCHY_PATH itself,"
echo "    and omarchy's own envs.lua puts its bin/ on PATH for the session)"
