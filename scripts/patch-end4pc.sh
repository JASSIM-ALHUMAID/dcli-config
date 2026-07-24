#!/bin/bash
# Repoint the end4-pC checkout at end4pc-owned paths, so its settings app edits
# OUR Hyprland config and so the shell stands on its own without shell-end4.
#
# Upstream end4-pC is a fork of illogical-impulse and inherits all of its
# hardcoded paths: it writes Hyprland overrides to ~/.config/hypr/hyprland/...
# (which our shells/<name>/hyprland.lua layout never reads), shares
# ~/.config/illogical-impulse/config.json with the "ii" shell, and expects
# ~/.config/matugen — which on this machine is a symlink INTO the ii checkout
# (~/.local/share/dots-hyprland), so end4pc breaks the moment shell-end4 goes.
#
# The rewrites are plain literal-string seds rather than context diffs, because
# sed survives upstream churn: a `git pull` that moves these lines around still
# leaves the strings intact. Every substitution normalises back to the upstream
# form first, so re-running this script is a no-op.
#
# Deliberately NOT rewritten: the secret-tool 'illogical-impulse' keyring label
# (scripts/keyring/try_lookup.sh, scripts/ai/gemini-categorize-wallpaper.sh,
# services/KeyringStorage.qml). The keyring entry stays shared with the ii shell
# so the Gemini API key doesn't have to be entered twice.
#
# Also seeds ~/.config/illogical-impulse-pC/config.json — see seed_config().
#
# Run by scripts/setup-end4pc.sh (after clone) and scripts/update-end4pc.sh
# (after every pull). Safe to run by hand at any time.
set -euo pipefail

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

REPO_DIR="$REAL_HOME/.local/share/end4-pC"

as_user() {
    if [ "$(id -u)" -eq 0 ] && [ "$REAL_USER" != "root" ]; then
        sudo -u "$REAL_USER" -H "$@"
    else
        "$@"
    fi
}

if [ ! -d "$REPO_DIR/.git" ]; then
    echo "!! end4-pC not found at $REPO_DIR — run setup-end4pc.sh first" >&2
    exit 1
fi

changed=0

# rewrite <relative-path> <expected-string-after> <sed-expr>...
#
# Applies the sed expressions, then asserts the result actually contains the
# string we were aiming for. A missing assertion means upstream renamed or moved
# something and the rewrite silently did nothing — which would look like the
# settings app "just not working" again, so fail loudly instead.
rewrite() {
    local rel="$1"; shift
    local expect="$1"; shift
    local path="$REPO_DIR/$rel"

    if [ ! -f "$path" ]; then
        echo "!! expected file missing: $rel — upstream layout changed" >&2
        exit 1
    fi

    local before after
    before=$(cat "$path")
    local args=()
    for expr in "$@"; do args+=(-e "$expr"); done
    after=$(printf '%s' "$before" | sed "${args[@]}")

    if ! printf '%s' "$after" | grep -qF "$expect"; then
        echo "!! rewrite of $rel did not produce '$expect' — upstream changed" >&2
        exit 1
    fi

    if [ "$before" != "$after" ]; then
        printf '%s\n' "$after" | as_user tee "$path" >/dev/null
        echo ":: patched $rel"
        changed=1
    fi
}

# 1) Shell config dir: ~/.config/illogical-impulse -> ~/.config/illogical-impulse-pC
#    One property in Directories.qml covers every QML consumer (config.json,
#    presets, AI prompts, user actions); the scripts hardcode the path instead.
# The /secret-tool/! guard keeps the keyring label alone — gemini-translate.sh
# has both the config dir and a `secret-tool lookup 'application'
# 'illogical-impulse'` in the same file.
II_SED=(
    '/secret-tool/!s|illogical-impulse-pC|illogical-impulse|g'
    '/secret-tool/!s|illogical-impulse|illogical-impulse-pC|g'
)
for f in \
    modules/common/Directories.qml \
    modules/ii/settings/SettingsContent.qml \
    services/LauncherSearch.qml \
    scripts/colors/switchwall.sh \
    scripts/colors/applycolor.sh \
    scripts/colors/random/random_osu_wall.sh \
    scripts/colors/random/random_konachan_wall.sh \
    scripts/ai/gemini-translate.sh \
    scripts/videos/record.sh \
    scripts/presets.sh \
    scripts/hyprland/autostart.py
do
    rewrite "$f" "illogical-impulse-pC" "${II_SED[@]}"
done

# 2) Hyprland overrides written by the settings app's Hyprland page:
#    ~/.config/hypr/hyprland/shellOverrides/{main,animations}.lua
#    -> ~/.config/hypr/shells/end4pc/overrides/{main,animations}.lua
#    dotfiles/hypr/shells/end4pc/hyprland.lua loads them last.
OVERRIDE_SED=(
    's|hypr/shells/end4pc/overrides/|hypr/hyprland/shellOverrides/|g'
    's|hypr/hyprland/shellOverrides/|hypr/shells/end4pc/overrides/|g'
)
rewrite services/HyprlandConfig.qml \
    "hypr/shells/end4pc/overrides/main.lua" "${OVERRIDE_SED[@]}"
rewrite scripts/hyprland/hyprconfigurator.py \
    "hypr/shells/end4pc/overrides/main.lua" "${OVERRIDE_SED[@]}"

# 3) Monitor layout written by the settings app's Displays page.
rewrite modules/common/models/hyprland/MonitorConfigOption.qml \
    "~/.config/hypr/shells/end4pc/monitors.lua" \
    's|~/.config/hypr/shells/end4pc/monitors.lua|~/.config/hypr/monitors.lua|g' \
    's|~/.config/hypr/monitors.lua|~/.config/hypr/shells/end4pc/monitors.lua|g'

# 4) matugen: use the vendored ~/.config/matugen-end4pc (dotfiles/matugen-end4pc)
#    instead of ~/.config/matugen, which belongs to the ii checkout. matugen
#    reads ~/.config/matugen/config.toml by default, so the call needs -c too.
rewrite scripts/colors/switchwall.sh \
    'MATUGEN_DIR="$XDG_CONFIG_HOME/matugen-end4pc"' \
    's|matugen-end4pc|matugen|g' \
    's|matugen -c "$MATUGEN_DIR/config.toml" |matugen |g' \
    's|MATUGEN_DIR="$XDG_CONFIG_HOME/matugen"|MATUGEN_DIR="$XDG_CONFIG_HOME/matugen-end4pc"|' \
    's|"$XDG_CONFIG_HOME"/matugen/|"$XDG_CONFIG_HOME"/matugen-end4pc/|g' \
    's|^\( *\)matugen "|\1matugen -c "$MATUGEN_DIR/config.toml" "|'

# Assert the -c flag landed too — the sed above has two independent goals.
if ! grep -qF 'matugen -c "$MATUGEN_DIR/config.toml"' "$REPO_DIR/scripts/colors/switchwall.sh"; then
    echo "!! switchwall.sh matugen invocation not rewritten — upstream changed" >&2
    exit 1
fi

# 5) Seed the shell config so the settings app's Hyprland page doesn't clobber
#    our setup. That page dumps its ENTIRE config.json "hyprland" block into the
#    override file on every open (Component.onCompleted in
#    modules/ii/settings/pages/HyprlandConfig.qml), so stock defaults would
#    silently replace layout=scrolling with dwindle and kb_layout=us,ara with us.
#    Seeding once, at creation time, makes that first open a no-op.
seed_config() {
    local dir="$REAL_HOME/.config/illogical-impulse-pC"
    local cfg="$dir/config.json"

    if [ -e "$cfg" ]; then
        echo ":: $cfg already exists — leaving it alone"
        return
    fi

    if ! command -v jq >/dev/null 2>&1; then
        echo "!! jq not found — cannot seed $cfg" >&2
        exit 1
    fi

    as_user mkdir -p "$dir"

    # Start from the ii shell's config when present: it carries API keys and
    # other settings worth inheriting. The hyprland block is overwritten below.
    local base="$REAL_HOME/.config/illogical-impulse/config.json"
    local seed
    if [ -f "$base" ]; then
        seed=$(cat "$base")
        echo ":: seeding from $base"
    else
        seed='{}'
    fi

    # These MUST match dotfiles/hypr/shells/end4pc/hyprland.lua's own values.
    # "niri" is the anim preset whose workspaces animation is slidevert, which
    # is what that file used before the settings app took the keys over.
    printf '%s' "$seed" | jq '
        .hyprland.general.layout      = "scrolling" |
        .hyprland.general.gapsIn      = 4 |
        .hyprland.general.gapsOut     = 8 |
        .hyprland.general.borderSize  = 2 |
        .hyprland.decoration.rounding = 12 |
        .hyprland.decoration.blur.enabled = true |
        .hyprland.input.kbLayout      = "us,ara" |
        .hyprland.animations.enable   = true |
        .hyprland.animations.animation = "niri"
    ' | as_user tee "$cfg" >/dev/null

    echo ":: seeded $cfg"
}
seed_config

if [ "$changed" -eq 0 ]; then
    echo ":: end4-pC checkout already patched — nothing to do"
else
    echo ":: end4-pC patched — restart the shell with switch-shell.sh end4pc"
fi
