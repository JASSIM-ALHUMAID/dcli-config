#!/bin/bash
# Bootstrap the ryoku shell — Ryoku-dev/ryoku, run from a checkout.
#
# WHAT THIS IS NOT: ryoku is a distribution. Its installer adds a signed [ryoku]
# pacman repository, installs ryoku-desktop-hyprland (Hyprland + pinned plugins
# + SDDM + limine + snapshots) and converts the system in place; its
# `ryoku materialize` copies ryoku's config tree into ~/.config, including
# ~/.config/hypr. None of that is run here: ~/.config/hypr is dcli-owned and the
# rest is a distro takeover. This follows upstream's own no-install path,
# `ryoku/shell/dev-run.sh`.
#
# Layout this script produces:
#   ~/.local/share/ryoku-shell           — checkout on main (source of truth)
#   ~/.local/bin/ryoku-shell             — the Go IPC daemon/client, built from
#                                          ryoku/shell/ipc
#   ~/.local/lib/qt6/qml/Ryoku/{Blobs,Spatial3D}   — built C++ QML modules
#   ~/.local/lib/qt6/qml/Ryoku/{Ui,FrameBars,PluginKit} — copied pure-QML modules
#   ~/.local/share/ryoku/i18n            — the translation catalog
#
# The checkout lives at .../ryoku-shell, NOT .../ryoku: upstream installs its
# i18n catalog to ~/.local/share/ryoku/i18n, so a checkout at that path would
# grow an untracked directory inside itself and `update-shells.sh --status`
# would report it dirty forever.
#
# dev-run.sh omits Ryoku.PluginKit; without it the shell dies at startup with
# "module Ryoku.PluginKit is not installed" (Desktop.qml imports it), so the
# hook installs it too.
#
# There is deliberately no `ryoku materialize`, no `ryoku deploy` and no
# qylock install: they write ~/.config/hypr, ~/.config/ryoku or /etc. The
# Hyprland side is dotfiles/hypr/shells/ryoku/hyprland.lua in this repo, and
# the shell's runtime config is written by the daemon itself.
#
# Safe to re-run: it never reclones, and every build step is idempotent. After
# an update, update-ryoku.sh runs this script again to rebuild.
set -euo pipefail

# shellcheck source=lib/hook-common.sh disable=SC1091
. "$(dirname "$(readlink -f "$0")")/lib/hook-common.sh" || exit 1

REPO_URL="https://github.com/Ryoku-dev/ryoku.git"
REPO_BRANCH="main"
REPO_DIR="$REAL_HOME/.local/share/ryoku-shell"
SHELL_DIR="$REPO_DIR/ryoku/shell"
QML_DIR="$REAL_HOME/.local/lib/qt6/qml"
BIN_DIR="$REAL_HOME/.local/bin"
DATA_DIR="$REAL_HOME/.local/share"

# 1) Checkout. Big (the repo carries the ISO/showroom media), but a checkout is
#    still the source of truth upstream's dev flow uses.
clone_checkout "$REPO_DIR" "$REPO_URL" "$REPO_BRANCH" "ryoku"

# 2) Toolchain. Declared as packages in modules/shell-ryoku.yaml, which dcli
#    installs before any hook runs. Fail with a clear message rather than a
#    half-built shell if this is run by hand on a fresh machine.
for tool in go cmake ninja; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "!! ryoku: $tool is required (dcli module run-hook shell-ryoku after sync)" >&2
        exit 1
    fi
done

as_user mkdir -p "$BIN_DIR" "$QML_DIR"

# 3) The IPC daemon/client. This one binary both supervises the Quickshell
#    config and forwards keybind commands to it.
echo ":: Building ryoku-shell"
as_user go -C "$SHELL_DIR/ipc" build -o "$BIN_DIR/ryoku-shell" .

# 4) QML modules. Blobs/Spatial3D are C++ (cmake + ninja + shader tools);
#    Ui/FrameBars/PluginKit are pure QML copies. All of them must be on the
#    import path before the daemon starts its shell.
echo ":: Building Ryoku.Blobs / Ryoku.Spatial3D"
as_user "$SHELL_DIR/plugin/build.sh" "$QML_DIR"

for module in \
    "$REPO_DIR/ryoku/ui/install.sh" \
    "$SHELL_DIR/framebars/install.sh" \
    "$SHELL_DIR/quickshell/plugins/kit/install.sh"; do
    echo ":: Installing $(basename "$(dirname "$module")")"
    as_user "$module" "$QML_DIR"
done

# 5) Translation catalog, where every dev-checkout surface looks for it.
echo ":: Installing the i18n catalog"
as_user "$REPO_DIR/ryoku/i18n/tools/install.sh" "$DATA_DIR"

# 6) The daemon writes ~/.config/ryoku itself (it is the sole writer), with one
#    deliberate seed: app theming defaults ON and fans the palette across shared
#    config this repo owns — cava/config, btop/themes, yazi/theme.toml, fish,
#    starship and kitty. shell-theme-state.sh cannot isolate those (several
#    shells write the same files), so the toggle starts off and the Hub's
#    appearance page is the opt-in. See docs/shells/ryoku.md.
as_user mkdir -p "$REAL_HOME/.config/ryoku"
MATUGEN_KNOBS="$REAL_HOME/.config/ryoku/matugen.json"
if [ ! -e "$MATUGEN_KNOBS" ]; then
    printf '{"themeRyokuApps": false}\n' | as_user tee "$MATUGEN_KNOBS" >/dev/null
    echo ":: Seeded matugen.json with themeRyokuApps=false (shared app config stays dcli's)"
fi

echo ":: ryoku shell ready — switch with switch-shell.sh ryoku"
echo "   (checkout only: the [ryoku] repo, ryoku materialize and qylock are not installed)"
