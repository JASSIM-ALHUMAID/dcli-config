#!/bin/bash
# Bootstrap the ml4w shell — mylinuxforwork/dotfiles (ML4W OS), a Quickshell
# config run as an independent named config "ml4w".
#
# No personal fork: cloned straight from upstream (branch main), like end4pc,
# omarchy and xenon.
#
# Layout this script produces:
#   ~/.local/share/ml4w-dotfiles    — upstream checkout on branch main (source
#                                     of truth). The quickshell config is nested
#                                     at dotfiles/.config/quickshell.
#   ~/.config/quickshell/ml4w       — symlink -> checkout
#                                     dotfiles/.config/quickshell. Upstream runs
#                                     this as the DEFAULT config (bare `qs`);
#                                     this repo runs every shell as a NAMED
#                                     config, so we run `qs -c ml4w` here. The
#                                     QML imports are relative, so a named-config
#                                     symlink resolves fine.
#   ~/.config/ml4w                  — seeded COPY of checkout
#                                     dotfiles/.config/ml4w (REAL dir: the
#                                     sidebar/settings apps write into it and
#                                     matugen regenerates colors/colors.json).
#                                     Refreshed by update-ml4w.sh, never replaced.
#   ~/.config/ml4w-statusbar        — seeded statusbar override (statusbar.json)
#   ~/.config/matugen-ml4w          — symlink -> dcli dotfiles/matugen-ml4w. The
#                                     base hook links it; hooks run in parallel
#                                     so this hook ensures it too.
#   ~/.local/share/fonts            — Fira Sans + Material Icons copied from the
#                                     checkout's setup/fonts
#
# CRITICAL: no quickshell provider package is declared for this shell. The
# provider has exactly one owner — modules/shells-quickshell{,-git}.yaml — and
# ml4w runs on whichever one is enabled. See docs/PACKAGE-CONFLICTS.md.
#
# CRITICAL: never run the ML4W installer (bash <(curl -s https://ml4w.com/os/stable)).
# It is a whole-dotfiles installer that overwrites dcli-symlinked configs.
#
# Safe to re-run: never clones over an existing checkout and skips symlinks
# that are already correct.
set -euo pipefail

# dcli may run hooks as root — always operate on the real user's home.
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

REPO_URL="https://github.com/mylinuxforwork/dotfiles.git"
REPO_BRANCH="main"
REPO_DIR="$REAL_HOME/.local/share/ml4w-dotfiles"
CHECKOUT_QS="$REPO_DIR/dotfiles/.config/quickshell"
QS_CONF="$REAL_HOME/.config/quickshell/ml4w"
ML4W_DIR="$REAL_HOME/.config/ml4w"
SB_OVERRIDE="$REAL_HOME/.config/ml4w-statusbar/statusbar.json"
MATUGEN_CONF="$REAL_HOME/.config/matugen-ml4w"
MATUGEN_SRC="$REAL_HOME/.config/dcli/dotfiles/matugen-ml4w"
ROFI_DIR="$REAL_HOME/.config/rofi"
OVERVIEW_DIR="$REAL_HOME/.config/ml4w-overview"
ML4W_CACHE="$REAL_HOME/.cache/ml4w/hyprland-dotfiles"
SETTINGS_URL="https://github.com/mylinuxforwork/ml4w-dotfiles-settings.git"
SETTINGS_SRC="$REAL_HOME/.local/share/ml4w-dotfiles-settings-src"
SETTINGS_LIB="$REAL_HOME/.local/share/ml4w-dotfiles-settings"
SETTINGS_CONF="$REAL_HOME/.config/ml4w-dotfiles-settings"

as_user() {
    if [ "$(id -u)" -eq 0 ] && [ "$REAL_USER" != "root" ]; then
        sudo -u "$REAL_USER" -H "$@"
    else
        "$@"
    fi
}

# 1) Clone upstream on branch main. No submodules — the repo has none.
if [ -d "$REPO_DIR/.git" ]; then
    echo ":: ml4w-dotfiles already cloned at $REPO_DIR"
else
    if [ -e "$REPO_DIR" ]; then
        echo "!! $REPO_DIR exists but is not a git repo — refusing to touch it." >&2
        exit 1
    fi
    echo ":: Cloning ml4w-dotfiles (branch $REPO_BRANCH)"
    as_user mkdir -p "$(dirname "$REPO_DIR")"
    as_user git clone --branch "$REPO_BRANCH" "$REPO_URL" "$REPO_DIR"
fi

# 2) Symlink ~/.config/quickshell/ml4w -> checkout quickshell dir (the repo IS
#    the config, nested one level deep).
if [ -L "$QS_CONF" ] && [ "$(readlink -f "$QS_CONF")" = "$(readlink -f "$CHECKOUT_QS")" ]; then
    echo ":: ~/.config/quickshell/ml4w already linked"
else
    if [ -e "$QS_CONF" ]; then
        echo "!! $QS_CONF exists and is not a correct symlink — refusing to clobber." >&2
        exit 1
    fi
    as_user mkdir -p "$(dirname "$QS_CONF")"
    as_user ln -s "$CHECKOUT_QS" "$QS_CONF"
    echo ":: Symlinked $QS_CONF -> $CHECKOUT_QS"
fi

# 3) Seed ~/.config/ml4w (real dir, machine-local). First run only; never
#    clobber an existing seed. update-ml4w.sh refreshes defaults afterwards.
if [ -f "$ML4W_DIR/settings/statusbar.json" ]; then
    echo ":: ~/.config/ml4w already seeded"
else
    echo ":: Seeding ~/.config/ml4w from checkout"
    as_user mkdir -p "$(dirname "$ML4W_DIR")"
    as_user cp -r "$REPO_DIR/dotfiles/.config/ml4w" "$ML4W_DIR"
    as_user mkdir -p "$ML4W_DIR/colors"
fi

# 4) Seed the statusbar override file. ~/.config/ml4w-statusbar/statusbar.json is
#    the "master" file the StatusbarApp reads when present; it wins over the
#    shipped fallback in the ml4w settings dir.
#
#    CRITICAL: written explicitly with "enabled": true rather than copied from
#    the checkout. Upstream ships the quickshell bar DISABLED
#    (StatusbarApp/statusbar.json) and covers the gap with waybar, which
#    conf/autostart.lua launches unconditionally; the flag only flips to true
#    when the user picks Quickshell in the SidebarApp switch. This repo installs
#    no waybar (minimal-ecosystem scope), so seeding upstream's default would
#    leave the session with no bar at all. Enabled-by-default is a deliberate
#    divergence — see docs/shells/ml4w.md.
if [ -f "$SB_OVERRIDE" ]; then
    echo ":: statusbar override already present"
else
    as_user mkdir -p "$(dirname "$SB_OVERRIDE")"
    as_user tee "$SB_OVERRIDE" >/dev/null <<'JSON'
{
    "bar": {
        "enabled": true,
        "alwaysExpanded": false
    }
}
JSON
    echo ":: Seeded $SB_OVERRIDE (bar enabled — no waybar fallback here)"
fi

# 5) Ensure the matugen-ml4w symlink (the base hook links it, but hooks run in
#    parallel so it may not exist yet).
if [ -L "$MATUGEN_CONF" ] && [ "$(readlink -f "$MATUGEN_CONF")" = "$(readlink -f "$MATUGEN_SRC")" ]; then
    echo ":: matugen-ml4w already linked"
else
    as_user mkdir -p "$(dirname "$MATUGEN_CONF")"
    if ! as_user ln -s "$MATUGEN_SRC" "$MATUGEN_CONF" 2>/dev/null; then
        if [ "$(readlink -f "$MATUGEN_CONF")" = "$(readlink -f "$MATUGEN_SRC")" ]; then
            echo ":: Symlinked $MATUGEN_CONF -> $MATUGEN_SRC (created by a concurrent hook)"
        else
            echo "!! $MATUGEN_CONF exists and is not the correct symlink — refusing to clobber." >&2
            exit 1
        fi
    else
        echo ":: Symlinked $MATUGEN_CONF -> $MATUGEN_SRC"
    fi
fi

# 6) Fonts the QML references (Fira Sans for Theme.qml's fontFamily, Material
#    Icons for the icon font). Copied from the checkout, not pacman packages.
echo ":: Installing ml4w fonts"
as_user mkdir -p "$REAL_HOME/.local/share/fonts"
as_user cp -rn "$REPO_DIR/setup/fonts/"* "$REAL_HOME/.local/share/fonts/" 2>/dev/null || true
as_user fc-cache -f >/dev/null 2>&1 || true

# 7) Runtime deps: every external command the QML execs. No quickshell provider
#    here — see docs/PACKAGE-CONFLICTS.md. Keep this list in sync with
#    modules/shell-ml4w.yaml.
#
#    The QML fires these through Quickshell.execDetached, which has no error
#    path — a missing binary makes the button do nothing at all, with no log
#    line. So they are dependencies, not nice-to-haves.
RUNTIME_DEPS=(
    swaync awww network-manager-applet
    rofi                    # launcher (ml4w/settings/launcher == "rofi")
    gum jq                  # ml4w-dotfiles-settings is a shell script
    nwg-displays qt6ct mission-center waypaper gnome-text-editor
)
# hyprmod is AUR-only. paru handles repo + AUR in one transaction; without it
# the repo packages still install and only the hyprmod button stays dead.
AUR_DEPS=(hyprmod)
echo ":: Installing ml4w runtime dependencies"
if as_user command -v paru >/dev/null 2>&1; then
    as_user paru -S --needed --noconfirm "${RUNTIME_DEPS[@]}" "${AUR_DEPS[@]}"
else
    echo "!! paru not found — installing repo packages only, ${AUR_DEPS[*]} skipped"
    if [ "$(id -u)" -eq 0 ]; then
        pacman -S --needed --noconfirm "${RUNTIME_DEPS[@]}"
    else
        sudo pacman -S --needed --noconfirm "${RUNTIME_DEPS[@]}"
    fi
fi

# 7b) The rofi launcher config. Seeded as a REAL dir, not a symlink into the
#     checkout, because matugen writes colors.rasi into it on every wallpaper
#     change (config.toml's [templates.rofi]) — pointing that at the checkout
#     would dirty the git tree on every theme regeneration. Nothing else on this
#     machine owns ~/.config/rofi.
if [ -d "$ROFI_DIR" ]; then
    echo ":: ~/.config/rofi already present"
else
    echo ":: Seeding ~/.config/rofi from checkout"
    as_user cp -r "$REPO_DIR/dotfiles/.config/rofi" "$ROFI_DIR"
fi

# 7b2) The workspace overview. Upstream runs it straight out of the quickshell
#      dir, but matugen regenerates common/Appearance.colors.qml on every
#      wallpaper change and that file is TRACKED in the checkout — writing there
#      would dirty the tree and break update-ml4w.sh's `git pull --ff-only`.
#      So it gets a seeded real dir, same reasoning as ~/.config/ml4w.
#      update-ml4w.sh refreshes it (no-clobber) after a pull.
if [ -d "$OVERVIEW_DIR" ]; then
    echo ":: ~/.config/ml4w-overview already seeded"
else
    echo ":: Seeding ~/.config/ml4w-overview from checkout"
    as_user cp -r "$CHECKOUT_QS/overview" "$OVERVIEW_DIR"
fi

# 7c) ml4w's config.rasi @imports this cache file for the launcher's background
#     image. It is normally written by ml4w-wallpaper, which the house wallpaper
#     flow in execs.lua does not run — so seed it against the default wallpaper.
#     A missing @import is not fatal for rofi, but it loses the backdrop.
if [ -f "$ML4W_CACHE/current_wallpaper.rasi" ]; then
    echo ":: current_wallpaper.rasi already present"
else
    as_user mkdir -p "$ML4W_CACHE"
    as_user tee "$ML4W_CACHE/current_wallpaper.rasi" >/dev/null <<RASI
* { current-image: url("$ML4W_DIR/wallpapers/default.jpg", height); }
RASI
    echo ":: Seeded $ML4W_CACHE/current_wallpaper.rasi"
fi

# 7d) The ML4W Dotfiles Settings app — a SEPARATE upstream repo, which is why it
#     was missing until now. The SidebarApp and WelcomeApp both toggle it via
#     `qs -p ~/.local/share/ml4w-dotfiles-settings/quickshell ipc call settings
#     toggle`, so that exact path has to exist.
#
#     Its own setup.sh is a curl|bash that appends to ~/.bashrc — not run here.
#     `make install` is the whole of it: bin/ -> ~/.local/bin, lib/* -> the lib
#     dir above. The checkout lives at ...-settings-src because make install
#     writes INTO ...-settings, so the two cannot be the same directory.
if [ -d "$SETTINGS_SRC/.git" ]; then
    echo ":: ml4w-dotfiles-settings already cloned"
else
    if [ -e "$SETTINGS_SRC" ]; then
        echo "!! $SETTINGS_SRC exists but is not a git repo — refusing to touch it." >&2
        exit 1
    fi
    echo ":: Cloning ml4w-dotfiles-settings"
    as_user git clone --depth 1 "$SETTINGS_URL" "$SETTINGS_SRC"
fi
if [ -d "$SETTINGS_LIB/quickshell" ]; then
    echo ":: ml4w-dotfiles-settings already installed"
else
    echo ":: Installing ml4w-dotfiles-settings (make install)"
    as_user make -C "$SETTINGS_SRC" install
fi
#     The settings PROFILE ("com.ml4w.dotfiles") is a directory of settings.json
#     under ~/.config/ml4w-dotfiles-settings — SettingsWindow reads $PROFILE and
#     renders nothing without it. Seeded real, like ~/.config/ml4w, because the
#     app writes to it.
if [ -f "$SETTINGS_CONF/com.ml4w.dotfiles/settings.json" ]; then
    echo ":: ml4w-dotfiles-settings profile already seeded"
else
    echo ":: Seeding $SETTINGS_CONF"
    as_user mkdir -p "$SETTINGS_CONF"
    as_user cp -rn "$REPO_DIR/dotfiles/.config/ml4w-dotfiles-settings/"* "$SETTINGS_CONF/"
fi

# 8) Initial theming so Theme.qml has colors on first launch. Theme.qml reads
#    ~/.config/ml4w/colors/colors.json and its onCompleted reload is disabled
#    upstream, so colors load on the `theme-manager reload` IPC that the shell's
#    execs and switch-shell.sh issue — but generate the file now anyway.
WALL="$ML4W_DIR/wallpapers/default.jpg"
if [ -f "$WALL" ] && command -v matugen >/dev/null 2>&1; then
    echo ":: Generating initial theme from $WALL"
    as_user matugen -c "$MATUGEN_CONF/config.toml" image "$WALL" --source-color-index 0 \
        || echo "!! matugen failed — the shell will still run; run it after the first wallpaper set"
fi

# 9) Repoint ml4w's own scripts at ~/.config/matugen-ml4w. Upstream calls
#    matugen bare, which reads ~/.config/matugen — a symlink into the end-4
#    checkout — so ml4w's WallpaperApp would regenerate end4's theme.
#    See scripts/patch-ml4w.sh for what and why. Idempotent.
bash "$(dirname "$(readlink -f "$0")")/patch-ml4w.sh"

echo ":: ml4w shell ready — launch with 'qs -c ml4w', switch with switch-shell.sh ml4w"
