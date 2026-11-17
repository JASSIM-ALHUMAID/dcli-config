#!/bin/bash
# Where each shell keeps ITS current wallpaper — the one table of it, sourced by
# render-grub-theme.sh (what to draw) and install-grub-theme.sh (which files the
# re-render path unit watches). Read-only; callers own `set -euo pipefail`.
#
# Why not hyprlock/colors.conf's $background_image: only the matugen-driven
# shells rewrite it, so noctalia/ryoku/dms kept pointing at whatever an older
# shell had set (2026-10-31: all three showed ambxst's wallpaper at boot).
# Every shell persists its own choice somewhere; this reads that directly.
#
# One record per line:  shell|kind|path|query
#   path   relative to $HOME; the file the shell writes (the watcher watches it)
#   kind   text   first line of the file is the wallpaper path
#          json   jq `query` on the file
#          toml   `query` = "section.key" — the key's quoted string value in
#                 that [section] (noctalia's flat settings.toml; no TOML lib)
#          link   the file is a symlink to the wallpaper
#          file   the file itself is the wallpaper (a shipped default)
# A shell may have several records; the first that yields an existing file
# wins. No match = no wallpaper (the renderer draws a generated gradient).
# SHELL_WALLPAPER_HOME=<dir> replaces $HOME (tests only).

# shellcheck disable=SC2034  # read by the sourcing scripts
WALLPAPER_SOURCES=(
    "caelestia|text|.local/state/caelestia/wallpaper/path.txt|"
    "ambxst|json|.cache/ambxst/wallpapers.json|.currentWall // empty"
    "dms|json|.local/state/dms/session.json|.wallpaperPath // empty"
    "noctalia|toml|.local/state/noctalia/settings.toml|wallpaper.last.path"
    "end4|json|.config/illogical-impulse/config.json|.background.wallpaperPath // empty"
    "end4pc|json|.config/illogical-impulse-pC/config.json|.background.wallpaperPath // empty"
    "omarchy|link|.local/state/omarchy/current/background|"
    "xenon|json|.cache/xenon/wallpapers.json|(.wallpapers // {} | to_entries | .[0].value) // .defaultWallpaper // empty"
    "xenon|file|.local/share/xenon-shell/Assets/default_wallpaper.png|"
    "glyph|json|.local/state/rice/glyph.json|.wall // empty"
    "ryoku|text|.local/state/ryoku-wallpaper|"
)

wallpaper_home() { echo "${SHELL_WALLPAPER_HOME:-$HOME}"; }

# toml_string <file> <section> <key>: the double-quoted value of <key> directly
# under [<section>] (indented sub-tables are their own sections, so the scan
# stops at the next header).
toml_string() {
    awk -v want="[$2]" -v key="$3" '
        /^[[:space:]]*\[/ { sub(/^[[:space:]]+/, ""); sub(/[[:space:]]+$/, ""); here = ($0 == want); next }
        here && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
            if (match($0, /"[^"]*"/)) { print substr($0, RSTART + 1, RLENGTH - 2); exit }
        }' "$1"
}

# wallpaper_from_record <kind> <abs file> <query>: prints the raw path a record
# yields (possibly empty or ~-relative); never fails.
wallpaper_from_record() {
    local kind="$1" file="$2" query="$3"
    [ -e "$file" ] || return 0
    case "$kind" in
    text) head -n1 "$file" 2>/dev/null ;;
    json) jq -r "$query" "$file" 2>/dev/null | head -n1 ;;
    toml) toml_string "$file" "${query%.*}" "${query##*.}" 2>/dev/null ;;
    link) readlink -f "$file" ;;
    file) echo "$file" ;;
    esac
}

# shell_wallpaper <shell>: absolute path of the shell's current wallpaper, or
# nothing when it has none (or no record).
shell_wallpaper() {
    local want="$1" home record shell kind path query raw
    home=$(wallpaper_home)
    for record in "${WALLPAPER_SOURCES[@]}"; do
        IFS='|' read -r shell kind path query <<<"$record"
        [ "$shell" = "$want" ] || continue
        raw=$(wallpaper_from_record "$kind" "$home/$path" "$query")
        raw=${raw%$'\r'}
        # A literal "~/" some shells store (ryogami's index does), not an expansion.
        # shellcheck disable=SC2088
        case "$raw" in "~/"*) raw="$home/${raw#"~/"}" ;; esac
        [ -n "$raw" ] && [ -f "$raw" ] && { echo "$raw"; return 0; }
    done
    return 0
}

# wallpaper_state_files: every watched state file as an absolute path, one per
# line (shipped defaults excluded — they never change at runtime).
wallpaper_state_files() {
    local home record shell kind path query
    home=$(wallpaper_home)
    for record in "${WALLPAPER_SOURCES[@]}"; do
        IFS='|' read -r shell kind path query <<<"$record"
        [ "$kind" = file ] || echo "$home/$path"
    done
}

# ── Per-target override ──────────────────────────────────────────────────────
# GRUB and SDDM each remember one setting in ~/.local/state/dcli/<target>-wallpaper:
# `follow` (the shell's own wallpaper, above) or the absolute path of one image
# every shell's theme uses instead. A missing file means follow. Written by
# scripts/set-boot-wallpaper.sh; watched by the render path units.
BOOT_WALLPAPER_TARGETS=(grub sddm)
BOOT_WALLPAPER_FOLLOW=follow

# boot_wallpaper_file <grub|sddm>: where the target keeps its setting.
boot_wallpaper_file() {
    echo "${XDG_STATE_HOME:-$HOME/.local/state}/dcli/$1-wallpaper"
}

# boot_wallpaper_setting <target>: `follow` or the saved path. Never fails.
boot_wallpaper_setting() {
    local file setting=""
    file=$(boot_wallpaper_file "$1")
    [ -r "$file" ] && setting=$(head -n1 "$file" 2>/dev/null)
    setting=${setting%$'\r'}
    echo "${setting:-$BOOT_WALLPAPER_FOLLOW}"
}

# target_wallpaper <target> <shell>: the image <target> draws for <shell>'s
# theme — the fixed image when one is set and still readable, else the shell's
# own wallpaper. A fixed image that has vanished warns and follows, so a
# deleted file never leaves a boot or login screen without a background.
target_wallpaper() {
    local target="$1" shell="$2" setting
    setting=$(boot_wallpaper_setting "$target")
    if [ "$setting" != "$BOOT_WALLPAPER_FOLLOW" ]; then
        case "$setting" in
        /*) [ -f "$setting" ] && [ -r "$setting" ] && { echo "$setting"; return 0; } ;;
        esac
        echo "wallpaper: $target fixed image '$setting' is not a readable file — following the shell" >&2
    fi
    shell_wallpaper "$shell"
}
