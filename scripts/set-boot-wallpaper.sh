#!/bin/bash
# Choose the wallpaper behind the GRUB boot menu or the SDDM login screen.
#
# Usage: set-boot-wallpaper.sh <grub|sddm> [follow|<image>|--status]
#   follow     each shell's theme uses that shell's own wallpaper (the default)
#   <image>    one image behind every shell's theme, until set back to follow
#   --status   print the current setting (also the behaviour with no mode)
#
# The setting is one line in ~/.local/state/dcli/<target>-wallpaper, written
# atomically; the target's render path unit watches it, and this script also
# renders straight away so the result does not depend on the unit being enabled.
# See docs/GRUB.md and docs/SDDM.md.
set -euo pipefail

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
# shellcheck source=lib/wallpaper.sh disable=SC1091
. "$SCRIPT_DIR/lib/wallpaper.sh" || exit 1

# ── Helpers ──────────────────────────────────────────────────────────────────
die() { echo "set-boot-wallpaper: $*" >&2; exit 1; }
usage() { sed -n '2,12p' "$0"; }

is_target() { local t; for t in "${BOOT_WALLPAPER_TARGETS[@]}"; do [ "$t" = "$1" ] && return 0; done; return 1; }

# validate_image <path>: an absolute, single-line path to a file ImageMagick can
# decode — the renderers would otherwise fall back to a gradient at boot time.
validate_image() {
    case "$1" in /*) ;; *) die "'$1' is not an absolute path" ;; esac
    case "$1" in *$'\n'*) die "the path must not contain a newline" ;; esac
    [ -f "$1" ] && [ -r "$1" ] || die "'$1' is not a readable file"
    if command -v magick >/dev/null 2>&1; then
        magick identify -quiet "$1[0]" >/dev/null 2>&1 || die "'$1' is not an image ImageMagick can read"
    fi
}

# write_setting <file> <value>: atomic, so a path unit never sees a half line.
write_setting() {
    local file="$1" tmp
    mkdir -p "$(dirname "$file")" || die "cannot create $(dirname "$file")"
    tmp=$(mktemp "$file.XXXXXX") || die "cannot write next to $file"
    if ! { printf '%s\n' "$2" >"$tmp" && mv -f "$tmp" "$file"; }; then
        rm -f "$tmp"
        die "cannot write $file"
    fi
}

render_now() { # <target>
    local renderer="$SCRIPT_DIR/render-$1-theme.sh"
    [ -x "$renderer" ] || die "$renderer is missing or not executable"
    "$renderer" --changed all || die "the $1 render failed — the setting is saved; fix the error and re-run"
}

# ── Arguments ────────────────────────────────────────────────────────────────
[ $# -ge 1 ] && [ $# -le 2 ] || { usage >&2; exit 2; }
case "$1" in -h | --help) usage; exit 0 ;; esac
target="$1"
is_target "$target" || die "unknown target '$target' (want: ${BOOT_WALLPAPER_TARGETS[*]})"
mode="${2:---status}"

case "$mode" in
--status)
    echo "$target: $(boot_wallpaper_setting "$target")"
    ;;
"$BOOT_WALLPAPER_FOLLOW")
    write_setting "$(boot_wallpaper_file "$target")" "$BOOT_WALLPAPER_FOLLOW"
    echo "$target: following each shell's wallpaper"
    render_now "$target"
    ;;
-*) die "unknown option $mode" ;;
*)
    image=$(readlink -f -- "$mode" 2>/dev/null || true)
    [ -n "$image" ] || die "cannot resolve '$mode'"
    validate_image "$image"
    write_setting "$(boot_wallpaper_file "$target")" "$image"
    echo "$target: fixed image $image"
    render_now "$target"
    ;;
esac
