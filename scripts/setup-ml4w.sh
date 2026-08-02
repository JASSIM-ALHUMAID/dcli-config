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

# 4) Seed the statusbar override file from the shipped fallback when absent.
#    ~/.config/ml4w-statusbar/statusbar.json is the "master" file the
#    StatusbarApp reads when present; the shipped fallback lives in the ml4w
#    settings dir. Seeding it makes the bar read our copy, not upstream's.
if [ -f "$SB_OVERRIDE" ]; then
    echo ":: statusbar override already present"
else
    as_user mkdir -p "$(dirname "$SB_OVERRIDE")"
    as_user cp "$ML4W_DIR/settings/statusbar.json" "$SB_OVERRIDE"
    echo ":: Seeded $SB_OVERRIDE"
fi

# 5) Ensure the matugen-ml4w symlink (the base hook links it, but hooks run in
#    parallel so it may not exist yet).
if [ -L "$MATUGEN_CONF" ] && [ "$(readlink -f "$MATUGEN_CONF")" = "$(readlink -f "$MATUGEN_SRC")" ]; then
    echo ":: matugen-ml4w already linked"
else
    if [ -e "$MATUGEN_CONF" ]; then
        echo "!! $MATUGEN_CONF exists and is not a correct symlink — refusing to clobber." >&2
        exit 1
    fi
    as_user mkdir -p "$(dirname "$MATUGEN_CONF")"
    as_user ln -s "$MATUGEN_SRC" "$MATUGEN_CONF"
    echo ":: Symlinked $MATUGEN_CONF -> $MATUGEN_SRC"
fi

# 6) Fonts the QML references (Fira Sans for Theme.qml's fontFamily, Material
#    Icons for the icon font). Copied from the checkout, not pacman packages.
echo ":: Installing ml4w fonts"
as_user mkdir -p "$REAL_HOME/.local/share/fonts"
as_user cp -rn "$REPO_DIR/setup/fonts/"* "$REAL_HOME/.local/share/fonts/" 2>/dev/null || true
fc-cache -f >/dev/null 2>&1 || true

# 7) Runtime deps (external commands the QML execs). No quickshell provider
#    here — see docs/PACKAGE-CONFLICTS.md.
RUNTIME_DEPS=(swaync awww network-manager-applet)
echo ":: Installing ml4w runtime dependencies"
if [ "$(id -u)" -eq 0 ]; then
    pacman -S --needed --noconfirm "${RUNTIME_DEPS[@]}"
else
    sudo pacman -S --needed --noconfirm "${RUNTIME_DEPS[@]}"
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

echo ":: ml4w shell ready — launch with 'qs -c ml4w', switch with switch-shell.sh ml4w"
