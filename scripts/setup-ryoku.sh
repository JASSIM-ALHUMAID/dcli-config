#!/bin/bash
# Bootstrap the ryoku shell — Ryoku-dev/ryoku, run from a checkout.
#
# WHAT THIS IS NOT: ryoku is a distribution. Its installer adds a signed [ryoku]
# pacman repository, installs ryoku-desktop-hyprland (Hyprland + pinned plugins
# + SDDM + limine + snapshots) and converts the system in place; its
# `ryoku materialize` copies ryoku's config tree into ~/.config, including
# ~/.config/hypr. None of that is run here: ~/.config/hypr is dcli-owned and the
# rest is a distro takeover.
#
# WHAT THIS IS: the user-level half of the distro's packages, reproduced from
# their own recipes (release/packages/{ryoku-shell,ryogami,ryoku-hub,
# ryoku-desktop}/payload.sh) into ~/.local instead of /usr. Upstream's
# no-install path, ryoku/shell/dev-run.sh, is NOT enough on its own: it assumes
# a Ryoku box whose packages already put ~40 helpers on PATH, so on this machine
# the shell's browser/terminal/files actions (`ryoku-app`), the Hub's pages
# (`ryoku-hub`, `ryoku-host`), plugins (`ryostore`) and wallpapers (`ryogami`)
# were all silently dead (2026-10-31).
#
# Layout this script produces:
#   ~/.local/share/ryoku-shell           — checkout on main (source of truth)
#   ~/.local/lib/ryoku/bin               — the session's private bin dir, put on
#                                          PATH only by launch-ryoku.sh: compiled
#                                          daemons plus symlinks to the
#                                          user-level helpers
#   ~/.local/bin/ryoku-shell             — symlink into the bin dir, for binds/CLI
#   ~/.config/quickshell/<config>        — symlinks into the checkout, the layout
#                                          `ryoku materialize` would copy
#   ~/.local/lib/qt6/qml/Ryoku/*         — built and copied QML modules
#   ~/.local/share/ryogami/shell.qml     — the wallpaper picker entry point
#   ~/.local/share/ryoku/i18n            — the translation catalog
#   ~/.config/matugen                    — symlink to the checkout's matugen
#                                          templates (ryoku owns this path)
#   ~/Pictures/Wallpapers/ryoku          — the shipped wallpapers, seeded once
#
# The checkout lives at .../ryoku-shell, NOT .../ryoku: upstream installs its
# i18n catalog to ~/.local/share/ryoku/i18n, so a checkout at that path would
# grow an untracked directory inside itself and `update-shells.sh --status`
# would report it dirty forever.
#
# Deliberately NOT installed, because each one reaches outside the session:
#   - the `ryoku` CLI (doctor/materialize/deploy write ~/.config/hypr and /etc)
#   - ryoku-wm-* compositor providers: the Hub's Desktop page saves through
#     them and they re-author ~/.config/hypr; without one the save reports
#     "no provider" and writes nothing
#   - privileged helpers (pacman, /etc, sudo, systemd units) — dcli owns
#     packages and the system; see SYSTEM_HELPERS and HELPER_DENYLIST below
#   - ryoku-idle (it kills the running hypridle and starts its own, which would
#     outlive a shell switch), qylock, skwd-paper (Wallpaper Engine scenes)
#
# Safe to re-run: it never reclones, every build step is idempotent, and the
# seeds only write what is missing. update-ryoku.sh runs this script again
# after every pull to rebuild.
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
# Must match launch-ryoku.sh, which puts it on the session PATH (smoke.sh pins it).
RYOKU_BIN_DIR="$REAL_HOME/.local/lib/ryoku/bin"
QS_CONFIG_DIR="$REAL_HOME/.config/quickshell"
RYOKU_CONFIG_DIR="$REAL_HOME/.config/ryoku"
# Out of the checkout so a rebuild is incremental and `git status` stays clean.
PICKER_BUILD_DIR="$REAL_HOME/.cache/ryoku-build/ryogami-picker"
WALLPAPER_SEED_DIR="$REAL_HOME/Pictures/Wallpapers/ryoku"
MATUGEN_CONF="$REAL_HOME/.config/matugen"

# Go programs the packages build: <module dir>|<package>|<binary name>.
GO_BINARIES=(
    "ryoku/shell/ipc|.|ryoku-shell"
    "ryoku/shell/ryogami/daemon|.|ryogami"
    "ryoku/hub/backend|.|ryoku-hub"
    "ryoku/cli|./cmd/ryoku-host|ryoku-host"
    "ryoku/apps/ryostore/backend|.|ryostore"
)

# ryoku/shell/scripts is the shell's own helper set (ryoku-app, ryoku-cmd-*,
# ryoku-kit, ...) and is linked whole, as the ryoku-shell package installs it,
# minus the ones that install packages behind dcli's back.
HELPER_DENYLIST=(stash-install.sh)

# From system/, only the user-level helpers the shell or Hub calls by name. The
# rest of system/ (ryoku-gpu*, ryoku-power*, ryoku-dns, ryoku-pkg-*, ryoku-docker,
# ryoku-network-kill, ...) needs root or rewrites the machine.
SYSTEM_HELPERS=(
    system/hardware/audio/ryoku-bt-audio
    system/hardware/audio/ryoku-mic
    system/hardware/audio/ryoku-volume
    system/hardware/bluetooth/ryoku-bluetooth-power
    system/hardware/display/ryoku-hw-backlight
    system/hardware/gpu/ryoku-gpu-detect
    system/hardware/input/ryoku-hw-asus-aura
    system/hardware/input/ryoku-hw-qmk
    system/hardware/network/ryoku-wifi-backend
    system/hardware/power/ryoku-hw-laptop
    system/extras/ryoku-cmd-present
    ryoku/shell/quickshell/plugins/ryoku-plugins-place
    ryoku/apps/fastfetch/ryoku-fastfetch
)

# Quickshell configs reached by name (`qs -c shell`, `qs -c hub`, ...).
# Quickshell does not canonicalize config paths, so the daemon must run in its
# deployed mode — no RYOKU_SHELL_DIR — or every hard-coded `qs -c shell ipc`
# in upstream's QML and Go misses the instance it started with `qs -p`.
QS_APP_CONFIGS=(
    "ryoku/hub/quickshell|hub"
    "ryoku/apps/ryostore/quickshell|ryostore"
    "ryoku/apps/ryovm/quickshell|ryovm"
)

# 1) Checkout. Big (the repo carries the ISO/showroom media), but a checkout is
#    still the source of truth upstream's dev flow uses.
clone_checkout "$REPO_DIR" "$REPO_URL" "$REPO_BRANCH" "ryoku"

# 2) Toolchain. Declared as packages in modules/shell-ryoku.yaml, which dcli
#    installs before any hook runs. Fail with a clear message rather than a
#    half-built shell if this is run by hand on a fresh machine.
for tool in go cmake ninja cc wayland-scanner pkg-config; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "!! ryoku: $tool is required (dcli module run-hook shell-ryoku after sync)" >&2
        exit 1
    fi
done

as_user mkdir -p "$BIN_DIR" "$QML_DIR" "$RYOKU_BIN_DIR" "$QS_CONFIG_DIR" "$RYOKU_CONFIG_DIR"

# 3) Compiled programs, all into the private bin dir. ryoku-shell is the IPC
#    daemon/client; ryogami serves the wallpaper surface the shell renders and
#    ryogami-live plays video wallpapers; ryoku-hub and ryoku-host back the Hub
#    pages; ryostore is the plugin/bundle catalog. CGO off and -trimpath match
#    the package builds.
for entry in "${GO_BINARIES[@]}"; do
    IFS='|' read -r module package name <<<"$entry"
    echo ":: Building $name"
    as_user env CGO_ENABLED=0 go -C "$REPO_DIR/$module" build -trimpath -o "$RYOKU_BIN_DIR/$name" "$package"
done

echo ":: Building ryogami-live"
as_user "$SHELL_DIR/livewall/build.sh" "$RYOKU_BIN_DIR/ryogami-live"

# The daemon locates ryoku-reload-cover next to its own resolved executable,
# and binds/switch-shell.sh/doctor.sh call ~/.local/bin/ryoku-shell; a symlink
# satisfies both. `force`: the old path held a binary this script built.
ensure_symlink "$RYOKU_BIN_DIR/ryoku-shell" "$BIN_DIR/ryoku-shell" force

# 4) QML modules. Blobs/Spatial3D/Ryogami are C++ (cmake + ninja + shader
#    tools); Ui/FrameBars/PluginKit are pure QML copies. All of them must be on
#    the import path before the daemon starts its shell.
echo ":: Building Ryoku.Blobs / Ryoku.Spatial3D"
as_user "$SHELL_DIR/plugin/build.sh" "$QML_DIR"

echo ":: Building Ryoku.Ryogami (wallpaper picker)"
as_user mkdir -p "$PICKER_BUILD_DIR"
as_user env RYOGAMI_PICKER_BUILD="$PICKER_BUILD_DIR" "$SHELL_DIR/ryogami/picker/build.sh" "$QML_DIR"
as_user install -Dm644 "$SHELL_DIR/ryogami/picker/shell.qml" "$DATA_DIR/ryogami/shell.qml"

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

# 6) Helpers on the session PATH. Links pointing into the checkout are pruned
#    first so a helper upstream renames, or one dropped from the lists above,
#    leaves no stale entry; the compiled binaries are regular files and stay.
echo ":: Linking helpers into ${RYOKU_BIN_DIR/#$REAL_HOME/\~}"
for link in "$RYOKU_BIN_DIR"/*; do
    if [ -L "$link" ] && [[ "$(readlink "$link")" == "$REPO_DIR"/* ]]; then
        as_user rm -f "$link"
    fi
done

helpers=()
for script in "$SHELL_DIR"/scripts/*; do
    [ -f "$script" ] && [ -x "$script" ] || continue
    [[ " ${HELPER_DENYLIST[*]} " == *" ${script##*/} "* ]] && continue
    helpers+=("$script")
done
for rel in "${SYSTEM_HELPERS[@]}"; do
    if [ ! -x "$REPO_DIR/$rel" ]; then
        echo "!! ryoku: $rel is gone upstream — update SYSTEM_HELPERS in ${0##*/}" >&2
        exit 1
    fi
    helpers+=("$REPO_DIR/$rel")
done
for helper in "${helpers[@]}"; do
    as_user ln -sfn "$helper" "$RYOKU_BIN_DIR/${helper##*/}"
done
echo ":: Linked ${#helpers[@]} helpers"

# A matugen shim lived here for one day (2026-10-31) while ~/.config/matugen
# was still end4's; step 8 claims that directory instead. Drop the stale link.
if [ -L "$RYOKU_BIN_DIR/matugen" ]; then
    as_user rm -f "$RYOKU_BIN_DIR/matugen"
fi

# 7) Quickshell configs, by name. Every directory under ryoku/shell/quickshell
#    is linked, not only the ones with a shell.qml: `shell` imports its siblings
#    (inir, stage, plugins) by relative path, so they must sit beside it.
#    `refuse`: another shell owning one of these names is a conflict to settle
#    by hand, not to overwrite.
for config_dir in "$SHELL_DIR"/quickshell/*/; do
    config_dir="${config_dir%/}"
    ensure_symlink "$config_dir" "$QS_CONFIG_DIR/${config_dir##*/}" refuse
done
for entry in "${QS_APP_CONFIGS[@]}"; do
    IFS='|' read -r rel name <<<"$entry"
    ensure_symlink "$REPO_DIR/$rel" "$QS_CONFIG_DIR/$name" refuse
done

# 8) matugen templates. The daemon renders $XDG_CONFIG_HOME/matugen/config.toml
#    — a path it does not let you change — to fan the wallpaper palette into
#    kitty/current-theme.conf, btop/themes/ryoku.theme, fastfetch,
#    qt6ct/colors/ryoku.conf and ~/.cache/ryoku (all new files, nothing another
#    shell reads). On a Ryoku install that directory is ryoku's; here end4 held
#    it until 2026-10-31 and every ryoku wallpaper change rendered end4's
#    templates. end4 now uses ~/.config/matugen-end4 (setup-end4.sh releases its
#    old link), and every other shell passes its own -c. `refuse`: if something
#    else still owns the path, stop rather than theme it.
if [ -L "$MATUGEN_CONF" ] && [[ "$(readlink -f "$MATUGEN_CONF")" == "$REAL_HOME/.local/share/dots-hyprland/"* ]]; then
    echo "!! ryoku: ~/.config/matugen is still end4's — run setup-end4.sh first (it moves end4 to ~/.config/matugen-end4)" >&2
    exit 1
fi
ensure_symlink "$SHELL_DIR/matugen" "$MATUGEN_CONF" refuse

# 9) The daemon and Hub write ~/.config/ryoku themselves (they are the sole
#    writers), with two deliberate seeds, each written only when absent:
#
#    matugen.json — app theming defaults ON and fans the palette across shared
#    config this repo owns — cava/config, btop/themes, yazi/theme.toml, fish,
#    starship and kitty. shell-theme-state.sh cannot isolate those (several
#    shells write the same files), so the toggle starts off and the Hub's
#    appearance page is the opt-in. See docs/shells/ryoku.md.
MATUGEN_KNOBS="$RYOKU_CONFIG_DIR/matugen.json"
if [ ! -e "$MATUGEN_KNOBS" ]; then
    printf '{"themeRyokuApps": false}\n' | as_user tee "$MATUGEN_KNOBS" >/dev/null
    echo ":: Seeded matugen.json with themeRyokuApps=false (shared app config stays dcli's)"
fi

#    desktop.json — the roles `ryoku-app` launches (the shell's browser,
#    terminal, files and editor actions). Unset, it falls back to kitty and
#    nautilus; seed the house apps the keybinds use instead. The Hub deep-merges
#    this file over its defaults, so a partial file is valid, and its Default
#    Apps page changes the roles afterwards.
DESKTOP_STORE="$RYOKU_CONFIG_DIR/desktop.json"
if [ ! -e "$DESKTOP_STORE" ]; then
    jq -n '{desktop: {apps: {
        browser: "zen-browser",
        terminal: "wezterm",
        files: "thunar",
        editor: "wezterm start -- nvim"
    }}}' | as_user tee "$DESKTOP_STORE" >/dev/null
    echo ":: Seeded desktop.json default apps (zen-browser, wezterm, thunar, nvim)"
fi

# 10) Shipped wallpapers. ryogami scans ~/Pictures/Wallpapers recursively but
#    skips symlinks, so they must be real files; a subfolder keeps them apart
#    from the wallpapers other shells share, and a reflink copy costs no space
#    on btrfs. Seeded once: delete the folder to re-seed on the next run.
if [ ! -e "$WALLPAPER_SEED_DIR" ]; then
    echo ":: Seeding ryoku wallpapers into ${WALLPAPER_SEED_DIR/#$REAL_HOME/\~}"
    as_user mkdir -p "$WALLPAPER_SEED_DIR"
    as_user cp -a --reflink=auto "$REPO_DIR/ryoku/assets/wallpapers/." "$WALLPAPER_SEED_DIR/"
fi

echo ":: ryoku shell ready — switch with switch-shell.sh ryoku"
echo "   (no [ryoku] repo, ryoku CLI, compositor provider or qylock: see docs/shells/ryoku.md)"
