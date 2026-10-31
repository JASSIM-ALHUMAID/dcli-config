#!/bin/bash
# Render the per-shell GRUB themes into state/grub-theme/ (the user side of the
# GRUB layer; the root side — dcli-grub-sync — installs what lands here).
#
# Usage: render-grub-theme.sh [--active <shell>] [--changed] [shell|all]
#   (no argument)    render the active shell and refresh `active`
#   <shell>          render that one shell (`active` is left alone unless it is
#                    missing)
#   all              render every registry shell
#   --active <shell> make <shell> the active one and render it (combine with
#                    `all` to also render the rest)
#   --changed        skip targets whose wallpaper (path, mtime, size) and
#                    renderer are unchanged since their last render — what the
#                    dcli-grub-render.path user unit runs on every state write
#
# STAGING CONTRACT (state/grub-theme/, read by the root side)
#   fonts/<file>.pf2   the shared font set, fixed file names; fonts/MANIFEST
#                      lists `key|file|GRUB font name` — theme.txt files use
#                      exactly those names, read back from each pf2's NAME chunk
#   <shell>/           one complete theme: theme.txt background.jpg *.png
#                      icons/*.png title.txt preview.png .complete
#   active             one line, the active shell
#   contact-sheet.png  every preview tiled (humans only)
#   .stamp             rewritten LAST — the root path unit watches it
# A shell is rendered into <shell>.tmp/ and mv'd into place, .complete last.
#
# LOOK
#   Each shell's theme is generated from ITS wallpaper (lib/wallpaper.sh reads
#   it from the shell's own state) and ITS logo in one of
#   four layouts (STYLE_TABLE below). The accent comes from the wallpaper and is
#   nudged until it holds 4.5:1 against the panel. Everything pictorial —
#   glass, shadows, typography, the shell dock — is drawn as SVG and rasterised
#   by resvg; GRUB itself only draws the menu text, icons, the selection
#   9-slice and the countdown, so those are cut from the same drawings.
#
# GEOMETRY ASSUMPTION (GRUB 2.16 gui_list.c, could not be run here): item boxes
# are drawn OUTWARD from the content rectangle by their pads (pad = size of the
# edge pixmaps), the progress bar's boxes are drawn INSIDE its rectangle, and
# the list fits box + pads inside boot_menu width. Edge pixmaps are cut at
# exactly item_height so GRUB never stretches the part that carries artwork.
set -uo pipefail
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
REPO_DIR="${DCLI_DIR:-$(dirname "$SCRIPT_DIR")}"

# shellcheck source=lib/shell-common.sh disable=SC1091
. "$SCRIPT_DIR/lib/shell-common.sh" || exit 1
# shellcheck source=lib/wallpaper.sh disable=SC1091
. "$SCRIPT_DIR/lib/wallpaper.sh" || exit 1

# ── Constants ────────────────────────────────────────────────────────────────
STAGE_DIR="${DCLI_GRUB_STAGE:-$REPO_DIR/state/grub-theme}"
ICON_SRC_DIR="$REPO_DIR/dotfiles/fuzzel/shell-icons"
# Outside the staging tree on purpose: the root sync reads everything in there.
SIGNATURE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/dcli/grub-wallpaper"
LOCK_WAIT_SECONDS=120
SCREEN_W=1920
SCREEN_H=1080
JPEG_QUALITY=90
SPRITE_W=160
SPRITE_GAP=4
BLUR_DOWNSCALE_PCT=12.5
BLUR_SIGMA=3
HIST_SIZE=64
HIST_COLORS=8
LOGO_SAT_MIN=0.2
DEFAULT_STYLE=material
CONTACT_TILE_W=640
CONTACT_TILE_H=360
PREVIEW_ITEMS=5
DOCK_ICON=40
DOCK_GAP=26
DOCK_PAD=22
KEYMAP_SAMPLE="enter: boot, 'e': options, 'c': cmd-line"
TIMEOUT_SAMPLE="Booting in 5s"
FONT_GLYPHS="0x20-0x7e,0xa0-0x24f,0x2013-0x2026,0x2190-0x2199,0x2212-0x2212,0x25b6-0x25b6,0x276f-0x276f"
DARK_INK="0b0e14"
SHELL_NAME_RE='^[a-z0-9][a-z0-9-]*$'

# key|fc-match pattern|GRUB family name (-n)|size   (file: dcli-<key>.pf2)
FONT_SPECS='
sans-22|Inter:style=Regular|DcliSans|22
sans-sb-22|Inter:style=SemiBold|DcliSansSB|22
sans-16|Inter:style=Regular|DcliSans|16
mono-22|JetBrainsMono Nerd Font Mono:style=Regular|DcliMono|22
mono-b-22|JetBrainsMono Nerd Font Mono:style=Bold|DcliMonoB|22
mono-16|JetBrainsMono Nerd Font Mono:style=Regular|DcliMono|16
'

# ── Style table ──────────────────────────────────────────────────────────────
# shell -> style; a shell that is not listed falls back to DEFAULT_STYLE, so a
# new registry record renders without touching this file.
declare -A STYLE_OF=(
    [caelestia]=material [end4]=material [end4pc]=material [dms]=material [ambxst]=material
    [noctalia]=sidebar [xenon]=sidebar [ryoku]=sidebar
    [omarchy]=terminal
    [glyph]=dotmatrix
)

# style key value   — geometry in px at 1920x1080.
#   item_h/pad_*/spacing  boot_menu item box (pads = outward 9-slice edges)
#   menu_*                boot_menu rectangle (outer, pads included)
#   key_*/tmo_*/bar_*     keymap label, countdown label, countdown bar
#   tint/tint_a           colour + opacity laid over the blurred wallpaper
#   sel_alpha             selection fill strength (1 = solid accent)
#   logo_mono             1 = desaturate shell logos in icons and dock
STYLE_TABLE='
material font sans
material item_h 36
material pad_l 14
material pad_r 14
material pad_t 14
material spacing 20
material icon 32
material icon_gap 16
material menu_x 500
material menu_y 316
material menu_w 920
material menu_h 350
material key_x 508
material key_y 696
material key_w 904
material tmo_x 508
material tmo_y 776
material tmo_w 904
material bar_x 508
material bar_y 752
material bar_w 904
material bar_h 10
material bar_r 5
material tint 0b0e14
material tint_a 0.56
material sel_alpha 0.26
material px 460
material py 130
material pw 1000
material ph 720
material radius 30
material dock_cx 960
material dock_y 960
material logo_mono 0
sidebar font sans
sidebar item_h 36
sidebar pad_l 22
sidebar pad_r 14
sidebar pad_t 12
sidebar spacing 20
sidebar icon 32
sidebar icon_gap 16
sidebar menu_x 40
sidebar menu_y 300
sidebar menu_w 540
sidebar menu_h 380
sidebar key_x 72
sidebar key_y 880
sidebar key_w 476
sidebar tmo_x 72
sidebar tmo_y 960
sidebar tmo_w 476
sidebar bar_x 72
sidebar bar_y 936
sidebar bar_w 476
sidebar bar_h 10
sidebar bar_r 5
sidebar tint 080a10
sidebar tint_a 0.62
sidebar sel_alpha 0.20
sidebar px -2
sidebar py -2
sidebar pw 622
sidebar ph 1084
sidebar radius 0
sidebar dock_cx 1270
sidebar dock_y 990
sidebar logo_mono 0
terminal font mono
terminal item_h 32
terminal pad_l 46
terminal pad_r 16
terminal pad_t 6
terminal spacing 12
terminal icon 24
terminal icon_gap 14
terminal menu_x 392
terminal menu_y 372
terminal menu_w 1136
terminal menu_h 330
terminal key_x 400
terminal key_y 758
terminal key_w 1120
terminal tmo_x 400
terminal tmo_y 828
terminal tmo_w 1120
terminal bar_x 400
terminal bar_y 806
terminal bar_w 1120
terminal bar_h 8
terminal bar_r 0
terminal tint 05070a
terminal tint_a 0.80
terminal sel_alpha 1
terminal px 360
terminal py 170
terminal pw 1200
terminal ph 720
terminal radius 0
terminal dock_cx 960
terminal dock_y 966
terminal logo_mono 0
dotmatrix font mono
dotmatrix item_h 32
dotmatrix pad_l 58
dotmatrix pad_r 22
dotmatrix pad_t 10
dotmatrix spacing 22
dotmatrix icon 24
dotmatrix icon_gap 14
dotmatrix menu_x 592
dotmatrix menu_y 318
dotmatrix menu_w 736
dotmatrix menu_h 340
dotmatrix key_x 616
dotmatrix key_y 704
dotmatrix key_w 688
dotmatrix tmo_x 616
dotmatrix tmo_y 796
dotmatrix tmo_w 688
dotmatrix bar_x 616
dotmatrix bar_y 774
dotmatrix bar_w 688
dotmatrix bar_h 8
dotmatrix bar_r 4
dotmatrix tint 060606
dotmatrix tint_a 1
dotmatrix sel_alpha 1
dotmatrix px 560
dotmatrix py 130
dotmatrix pw 800
dotmatrix ph 760
dotmatrix radius 36
dotmatrix dock_cx 960
dotmatrix dock_y 966
dotmatrix logo_mono 1
'
declare -A ST=()

# Line-icon artwork on a 24-unit grid (stroke only; dcli is drawn separately).
declare -A ICON_ART=(
    [cachyos]='<path d="M12 2.5 20 7v10l-8 4.5L4 17V7z"/><path d="M13.2 7 9.4 13h5L10.8 17.5"/>'
    [gnu-linux]='<path d="M4 7h9M17 7h3M4 17h3M11 17h9"/><circle cx="15" cy="7" r="2"/><circle cx="9" cy="17" r="2"/>'
    [os]='<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="3"/>'
    [snapshots]='<path d="M3.5 12a8.5 8.5 0 1 0 2.6-6.1L3.5 8.5"/><path d="M3.5 3.5v5h5"/><path d="M12 7.5V12l3 2"/>'
    [efi]='<rect x="7" y="7" width="10" height="10" rx="2"/><path d="M10 3v4M14 3v4M10 17v4M14 17v4M3 10h4M3 14h4M17 10h4M17 14h4"/>'
    [windows]='<path d="M3 5.8 11 4.6v7H3zM13 4.3 21 3v8.6h-8zM3 12.6h8v7L3 18.4zM13 12.6h8V21l-8-1.2z"/>'
    [recovery]='<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="3.8"/><path d="m5.6 5.6 3.7 3.7M14.7 14.7l3.7 3.7M18.4 5.6l-3.7 3.7M9.3 14.7l-3.7 3.7"/>'
    [memtest]='<rect x="2.5" y="7.5" width="19" height="9" rx="1.5"/><path d="M6.5 16.5v3M10.5 16.5v3M14.5 16.5v3M18.5 16.5v3M7 11.5h2M11 11.5h2M15 11.5h2"/>'
)
ICON_NAMES=(cachyos gnu-linux os snapshots efi windows recovery memtest)

# ── Messaging ────────────────────────────────────────────────────────────────
say() { echo ":: $*"; }
fail() { echo "!! $*" >&2; }

usage() {
    sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# ── Arguments ────────────────────────────────────────────────────────────────
ACTIVE_OVERRIDE=""
TARGET_ARG=""
ONLY_CHANGED=0
while [ $# -gt 0 ]; do
    case "$1" in
    --active)
        [ $# -ge 2 ] || {
            fail "--active needs a shell name"
            exit 2
        }
        ACTIVE_OVERRIDE="$2"
        shift 2
        ;;
    --changed)
        ONLY_CHANGED=1
        shift
        ;;
    -h | --help)
        usage
        exit 0
        ;;
    -*)
        fail "unknown option: $1"
        exit 2
        ;;
    *)
        [ -z "$TARGET_ARG" ] || {
            fail "only one shell argument is accepted"
            exit 2
        }
        TARGET_ARG="$1"
        shift
        ;;
    esac
done

is_known_shell() {
    local candidate="$1" name
    [[ "$candidate" =~ $SHELL_NAME_RE ]] || return 1
    for name in "${KNOWN[@]}"; do
        [ "$name" = "$candidate" ] && return 0
    done
    return 1
}

for argument in "$ACTIVE_OVERRIDE" "$TARGET_ARG"; do
    case "$argument" in '' | all) continue ;; esac
    is_known_shell "$argument" || {
        fail "unknown shell: $argument (known: ${KNOWN[*]})"
        exit 2
    }
done
[ "$ACTIVE_OVERRIDE" != all ] || {
    fail "--active takes a shell name, not 'all'"
    exit 2
}

ACTIVE_NAME="${ACTIVE_OVERRIDE:-$(current_shell)}"
if ! is_known_shell "$ACTIVE_NAME"; then
    fail "no active shell to render for (current: $ACTIVE_NAME) — pass a shell name"
    [ -n "$TARGET_ARG" ] || exit 1
    ACTIVE_NAME=""
fi

TARGETS=()
case "$TARGET_ARG" in
'') TARGETS=("$ACTIVE_NAME") ;;
all) TARGETS=("${KNOWN[@]}") ;;
*) TARGETS=("$TARGET_ARG") ;;
esac
# An installed `active` pointing at an unrendered shell would break the root side.
if [ -n "$ACTIVE_NAME" ] && [ ! -e "$STAGE_DIR/$ACTIVE_NAME/.complete" ]; then
    case " ${TARGETS[*]} " in *" $ACTIVE_NAME "*) ;; *) TARGETS+=("$ACTIVE_NAME") ;; esac
fi

# ── Single-instance lock ─────────────────────────────────────────────────────
# Waits (a second render usually means the shell changed mid-run, so dropping
# it would leave a stale theme); same fd scheme as switch-shell.sh.
exec {LOCK_FD}>"${XDG_RUNTIME_DIR:-/tmp}/render-grub-theme.lock"
if ! flock -n "$LOCK_FD"; then
    say "another render is running; waiting up to ${LOCK_WAIT_SECONDS}s"
    flock -w "$LOCK_WAIT_SECONDS" "$LOCK_FD" || {
        fail "another render-grub-theme.sh instance did not finish"
        exit 1
    }
fi

for tool in magick resvg grub-mkfont fc-match awk; do
    command -v "$tool" >/dev/null 2>&1 || {
        fail "missing tool: $tool (modules/grub-theme.yaml installs imagemagick, resvg, grub, fontconfig)"
        exit 1
    }
done

WORK=$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/render-grub-theme.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$STAGE_DIR" || exit 1

while read -r style key value; do
    [ -n "$style" ] && ST["$style.$key"]="$value"
done <<<"$STYLE_TABLE"

# ── Fonts ────────────────────────────────────────────────────────────────────
declare -A FONT_NAME=()

# Reads the NAME chunk of a pf2 (the only name GRUB matches theme.txt against).
pf2_name() {
    local file="$1" length
    length=$(od -An -tu1 -j19 -N1 "$file" | tr -d ' ')
    [ -n "$length" ] && [ "$length" -gt 1 ] || return 1
    tail -c +21 "$file" | head -c "$((length - 1))"
}

# fc-match -> "path|index" of the face behind a pattern, refusing a silent
# substitute (fontconfig always answers, even with the wrong family).
resolve_font() {
    local pattern="$1" want out
    want=$(tr '[:upper:]' '[:lower:]' <<<"${pattern%%:*}")
    out=$(fc-match -f '%{file}|%{index}|%{family}' "$pattern" 2>/dev/null) || return 1
    case "$(tr '[:upper:]' '[:lower:]' <<<"${out##*|}")" in *"$want"*) ;; *) return 1 ;; esac
    echo "${out%|*}"
}

fonts_current() {
    local manifest="$STAGE_DIR/fonts/MANIFEST" key file name pattern family size source
    [ -f "$manifest" ] || return 1
    while IFS='|' read -r key pattern family size; do
        [ -n "$key" ] || continue
        file="$STAGE_DIR/fonts/dcli-$key.pf2"
        [ -f "$file" ] || return 1
        source=$(resolve_font "$pattern") || return 1
        [ "${source%|*}" -ot "$manifest" ] 2>/dev/null || return 1
    done <<<"$FONT_SPECS"
}

load_font_names() {
    local key file name
    while IFS='|' read -r key file name; do
        [ -n "$key" ] && FONT_NAME["$key"]="$name"
    done <"$STAGE_DIR/fonts/MANIFEST"
}

ensure_fonts() {
    if fonts_current; then
        load_font_names
        return 0
    fi
    say "building the GRUB font set"
    local build="$STAGE_DIR/fonts.tmp" key pattern family size source name manifest=""
    rm -rf "$build"
    mkdir -p "$build" || return 1
    while IFS='|' read -r key pattern family size; do
        [ -n "$key" ] || continue
        source=$(resolve_font "$pattern") || {
            fail "font not installed: $pattern (inter-font / ttf-jetbrains-mono-nerd)"
            return 1
        }
        grub-mkfont -s "$size" -n "$family" -i "${source#*|}" -r "$FONT_GLYPHS" \
            -o "$build/dcli-$key.pf2" "${source%|*}" >/dev/null 2>&1 || {
            fail "grub-mkfont failed for $key"
            return 1
        }
        name=$(pf2_name "$build/dcli-$key.pf2") || {
            fail "cannot read the embedded name of dcli-$key.pf2"
            return 1
        }
        manifest+="$key|dcli-$key.pf2|$name"$'\n'
    done <<<"$FONT_SPECS"
    printf '%s' "$manifest" >"$build/MANIFEST" || return 1
    rm -rf "$STAGE_DIR/fonts"
    mv "$build" "$STAGE_DIR/fonts" || return 1
    load_font_names
}

# ── Colour ───────────────────────────────────────────────────────────────────
# One awk pass: histogram of the wallpaper on stdin -> accent, text, dim text,
# selected text, panel, selection fill (space separated hex, no '#').
PALETTE_AWK='
function h2n(s,   i, n) { s = tolower(s); n = 0; for (i = 1; i <= length(s); i++) n = n * 16 + index("0123456789abcdef", substr(s, i, 1)) - 1; return n }
function cr(h) { return h2n(substr(h, 1, 2)) }
function cg(h) { return h2n(substr(h, 3, 2)) }
function cb(h) { return h2n(substr(h, 5, 2)) }
function lin(c) { c /= 255; return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ^ 2.4 }
function lum(h) { return 0.2126 * lin(cr(h)) + 0.7152 * lin(cg(h)) + 0.0722 * lin(cb(h)) }
function con(a, b,   la, lb, t) { la = lum(a); lb = lum(b); if (la < lb) { t = la; la = lb; lb = t } return (la + 0.05) / (lb + 0.05) }
function cl(x) { x = int(x + 0.5); return x < 0 ? 0 : (x > 255 ? 255 : x) }
function hx(r, g, b) { return sprintf("%02x%02x%02x", cl(r), cl(g), cl(b)) }
function mix(a, b, t) { return hx(cr(a) * (1 - t) + cr(b) * t, cg(a) * (1 - t) + cg(b) * t, cb(a) * (1 - t) + cb(b) * t) }
function tohsv(h,   r, g, b, mx, mn, d) {
    r = cr(h) / 255; g = cg(h) / 255; b = cb(h) / 255
    mx = r > g ? (r > b ? r : b) : (g > b ? g : b); mn = r < g ? (r < b ? r : b) : (g < b ? g : b); d = mx - mn
    V = mx; S = mx == 0 ? 0 : d / mx
    if (d == 0) H = 0
    else if (mx == r) H = ((g - b) / d + 6) % 6
    else if (mx == g) H = (b - r) / d + 2
    else H = (r - g) / d + 4
}
function hsv2hex(h, s, v,   i, f, p, q, t) {
    i = int(h) % 6; f = h - int(h); p = v * (1 - s); q = v * (1 - f * s); t = v * (1 - (1 - f) * s)
    if (i == 0) return hx(v * 255, t * 255, p * 255)
    if (i == 1) return hx(q * 255, v * 255, p * 255)
    if (i == 2) return hx(p * 255, v * 255, t * 255)
    if (i == 3) return hx(p * 255, q * 255, v * 255)
    if (i == 4) return hx(t * 255, p * 255, v * 255)
    return hx(v * 255, p * 255, q * 255)
}
function best_ink(bg, a, b) { return con(a, bg) >= con(b, bg) ? a : b }
{
    for (i = 1; i <= NF; i++) if ($i ~ /^#[0-9A-Fa-f]{6}/) { n++; col[n] = tolower(substr($i, 2, 6)); cnt[n] = $1 + 0; total += cnt[n]; break }
}
END {
    panel = mix(avg, tint, tint_a)
    top = ""; topscore = -1
    for (i = 1; i <= n; i++) {
        tohsv(col[i]); sc = S * V * (0.5 + sqrt(cnt[i] / total))
        if (S < 0.22) sc *= 0.15
        if (V < 0.30) sc *= 0.2
        if (sc > topscore) { topscore = sc; top = col[i] }
    }
    if (top == "") top = "7aa2f7"
    if (fixed != "") top = fixed
    tohsv(top); topsat = S; hh = H; ss = S > 0.85 ? 0.85 : S; vv = V < 0.78 ? 0.78 : V
    accent = hsv2hex(hh, ss, vv)
    for (k = 0; k < 60 && con(accent, panel) < 4.5; k++) {
        if (vv < 1) { vv += 0.03; if (vv > 1) vv = 1; accent = hsv2hex(hh, ss, vv) } else accent = mix(accent, "ffffff", 0.06)
    }
    text = mix(accent, "ffffff", 0.85)
    for (k = 0; k < 40 && con(text, panel) < 7; k++) text = mix(text, "ffffff", 0.1)
    t = 0.45; dim = mix(text, panel, t)
    while (t > 0.05 && con(dim, panel) < 4.5) { t -= 0.05; dim = mix(text, panel, t) }
    fill = mix(panel, accent, sel_alpha)
    if (sel_alpha >= 0.99) seltext = best_ink(accent, "ffffff", ink)
    else { seltext = text; for (k = 0; k < 40 && con(seltext, fill) < 7; k++) seltext = mix(seltext, "ffffff", 0.1) }
    print accent, text, dim, seltext, panel, fill, topsat
}'

# Per-shell derived colours, set by derive_colors.
ACCENT="" TEXT="" DIM="" SELTEXT="" PANEL="" SELFILL=""

logo_histogram() {
    local shell="$1" file out="$WORK/logo-$1.hist" png="$WORK/logo-$1.png"
    file=$(shell_icon_file "$shell")
    case "$file" in
    *.svg) resvg -w "$HIST_SIZE" "$file" "$png" 2>/dev/null || return 1 ;;
    *) png="$file" ;;
    esac
    magick "$png" -background black -alpha remove -alpha off -resize "${HIST_SIZE}x${HIST_SIZE}!" \
        -colors "$HIST_COLORS" -depth 8 -format %c histogram:info:- >"$out" 2>/dev/null || return 1
    echo "$out"
}

derive_colors() {
    local shell="$1" style="$2" hist="$3" blur="$4" fixed=""
    local average
    average=$(magick "$blur" -resize 1x1! -format '%[hex:u.p{0,0}]' info: 2>/dev/null | cut -c1-6)
    [ -n "$average" ] || average="202428"
    [ "$style" = dotmatrix ] && fixed="d71921"
    run_palette() {
        awk -v avg="$average" -v tint="${ST[$style.tint]}" -v tint_a="${ST[$style.tint_a]}" \
            -v sel_alpha="${ST[$style.sel_alpha]}" -v fixed="$fixed" \
            -v ink="$DARK_INK" "$PALETTE_AWK" "${1:-$hist}"
    }
    local topsat logo_hist
    read -r ACCENT TEXT DIM SELTEXT PANEL SELFILL topsat < <(run_palette)
    # A grey wallpaper has no accent to offer: take it from the shell's logo.
    if [ -z "$fixed" ] && awk -v s="${topsat:-1}" -v min="$LOGO_SAT_MIN" 'BEGIN { exit !(s < min) }'; then
        logo_hist=$(logo_histogram "$shell") && [ -s "$logo_hist" ] &&
            read -r ACCENT TEXT DIM SELTEXT PANEL SELFILL topsat < <(run_palette "$logo_hist")
    fi
    [ "$style" = dotmatrix ] && SELTEXT=ffffff
    [ -n "$SELFILL" ] || {
        fail "$shell: palette derivation failed"
        return 1
    }
}

# ── Wallpaper ────────────────────────────────────────────────────────────────
# Cover-fits the wallpaper once per distinct file and derives the blurred and
# histogram companions. $1=wallpaper path or empty (generated gradient), $2=shell
# (seeds the fallback hue). Sets WP_SHARP / WP_BLUR / WP_HIST.
prepare_wallpaper() {
    local source="$1" shell="$2" key dir hue
    key=$(printf '%s' "${source:-gradient:$shell}" | cksum | cut -d' ' -f1)
    dir="$WORK/wp-$key"
    WP_SHARP="$dir/sharp.jpg"
    WP_BLUR="$dir/blur.jpg"
    WP_HIST="$dir/hist.txt"
    [ -f "$WP_HIST" ] && return 0
    mkdir -p "$dir" || return 1
    if [ -n "$source" ] && [ -r "$source" ]; then
        magick -define "jpeg:size=${SCREEN_W}x${SCREEN_H}" "${source}[0]" -auto-orient -background black \
            -alpha remove -alpha off -colorspace sRGB -resize "${SCREEN_W}x${SCREEN_H}^" \
            -gravity center -extent "${SCREEN_W}x${SCREEN_H}" -quality 94 "$WP_SHARP"
    else
        [ -z "$source" ] || fail "$shell: wallpaper unreadable ($source) — using a generated gradient"
        hue=$(($(printf '%s' "$shell" | cksum | cut -d' ' -f1) % 360))
        magick -size "${SCREEN_W}x${SCREEN_H}" "gradient:hsl($hue,42%,26%)-hsl($(((hue + 50) % 360)),38%,7%)" \
            -quality 94 "$WP_SHARP"
    fi || return 1
    magick "$WP_SHARP" -resize "${BLUR_DOWNSCALE_PCT}%" -blur "0x$BLUR_SIGMA" -resize "${SCREEN_W}x${SCREEN_H}!" \
        -quality 92 "$WP_BLUR" || return 1
    magick "$WP_SHARP" -resize "${HIST_SIZE}x${HIST_SIZE}!" -colors "$HIST_COLORS" -depth 8 \
        -format %c histogram:info:- >"$WP_HIST" 2>/dev/null || return 1
}

# ── SVG helpers ──────────────────────────────────────────────────────────────
xml_escape() {
    local s="$1"
    s=${s//&/\&amp;}
    s=${s//</\&lt;}
    s=${s//>/\&gt;}
    s=${s//\"/\&quot;}
    echo "$s"
}

shell_field() {
    local name="$1" index="$2" record fields
    for record in "${SHELL_RECORDS[@]}"; do
        [ "${record%%|*}" = "$name" ] || continue
        IFS='|' read -r -a fields <<<"$record"
        echo "${fields[$index]}"
        return 0
    done
    return 1
}
shell_icon_file() { echo "$ICON_SRC_DIR/$(shell_field "$1" 2)"; }
shell_blurb() { shell_field "$1" 3; }

# Glass layers for a rect: soft shadow, blurred wallpaper, tint, top sheen,
# accent hairline, faint inner hairline.
svg_glass() {
    local id="$1" x="$2" y="$3" w="$4" h="$5" r="$6" shadow="${7:-1}"
    [ "$shadow" = 1 ] && echo "<rect x=\"$x\" y=\"$((y + 26))\" width=\"$w\" height=\"$h\" rx=\"$r\" fill=\"#000\" opacity=\".55\" filter=\"url(#shadow)\"/>"
    cat <<EOF
<clipPath id="clip-$id"><rect x="$x" y="$y" width="$w" height="$h" rx="$r"/></clipPath>
<image href="$WP_BLUR" x="0" y="0" width="$SCREEN_W" height="$SCREEN_H" clip-path="url(#clip-$id)"/>
<rect x="$x" y="$y" width="$w" height="$h" rx="$r" fill="#$TINT" fill-opacity="$TINT_A"/>
<rect x="$x" y="$y" width="$w" height="$h" rx="$r" fill="url(#sheen)"/>
<rect x="$((x + 1))" y="$((y + 1))" width="$((w - 2))" height="$((h - 2))" rx="$((r > 1 ? r - 1 : 0))" fill="none" stroke="#fff" stroke-opacity=".07"/>
<rect x="$x.5" y="$y.5" width="$((w - 1))" height="$((h - 1))" rx="$r" fill="none" stroke="#$ACCENT" stroke-opacity=".42"/>
EOF
}

# The family strip: every registry logo, dim and desaturated, the theme's own
# in full colour with an accent dot under it.
svg_dock() {
    local cx="$1" y="$2" shell="$3" count=${#KNOWN[@]} total plate_w plate_x x name file filter opacity
    total=$((count * DOCK_ICON + (count - 1) * DOCK_GAP))
    plate_w=$((total + DOCK_PAD * 2))
    plate_x=$((cx - plate_w / 2))
    svg_glass dock "$plate_x" "$((y - DOCK_PAD))" "$plate_w" "$((DOCK_ICON + DOCK_PAD * 2 + 12))" 30 1
    x=$((cx - total / 2))
    for name in "${KNOWN[@]}"; do
        file=$(shell_icon_file "$name")
        if [ "$name" = "$shell" ]; then
            filter=""
            [ "${ST[$STYLE.logo_mono]}" = 1 ] && filter=' filter="url(#mono)"'
            opacity=1
            echo "<circle cx=\"$((x + DOCK_ICON / 2))\" cy=\"$((y + DOCK_ICON + 13))\" r=\"3.2\" fill=\"#$ACCENT\"/>"
        else
            filter=' filter="url(#mono)"'
            opacity=.42
        fi
        echo "<image href=\"$file\" x=\"$x\" y=\"$y\" width=\"$DOCK_ICON\" height=\"$DOCK_ICON\" opacity=\"$opacity\"$filter/>"
        x=$((x + DOCK_ICON + DOCK_GAP))
    done
}

svg_prelude() {
    cat <<EOF
<svg xmlns="http://www.w3.org/2000/svg" width="$SCREEN_W" height="$SCREEN_H" viewBox="0 0 $SCREEN_W $SCREEN_H">
<defs>
<filter id="shadow" x="-30%" y="-30%" width="160%" height="170%"><feGaussianBlur stdDeviation="30"/></filter>
<filter id="softshadow" x="-10%" y="-10%" width="120%" height="130%"><feGaussianBlur stdDeviation="8"/></filter>
<filter id="mono" color-interpolation-filters="sRGB"><feColorMatrix type="saturate" values="0"/></filter>
<linearGradient id="sheen" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff" stop-opacity=".11"/><stop offset=".22" stop-color="#fff" stop-opacity=".02"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></linearGradient>
<radialGradient id="vignette" cx=".5" cy=".5" r=".75"><stop offset=".45" stop-color="#000" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity=".55"/></radialGradient>
<linearGradient id="floor" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#000" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity=".72"/></linearGradient>
<pattern id="grid" width="32" height="32" patternUnits="userSpaceOnUse"><path d="M32 0H0V32" fill="none" stroke="#fff" stroke-opacity=".035"/></pattern>
<pattern id="dots" width="20" height="20" patternUnits="userSpaceOnUse"><circle cx="10" cy="10" r="1.3" fill="#fff" fill-opacity=".10"/></pattern>
</defs>
<image href="$WP_SHARP" x="0" y="0" width="$SCREEN_W" height="$SCREEN_H"/>
<rect width="$SCREEN_W" height="$SCREEN_H" fill="url(#vignette)"/>
EOF
}

SANS='font-family="Inter Display, Inter, sans-serif"'
MONO='font-family="JetBrainsMono Nerd Font Mono, JetBrains Mono, monospace"'

# ── Per-style artwork ────────────────────────────────────────────────────────
# Each emits the baked background layer (everything GRUB does not draw itself).
svg_scene_material() {
    local shell="$1" name blurb
    name=$(xml_escape "${shell^}")
    blurb=$(xml_escape "$(shell_blurb "$shell")")
    local px=${ST[material.px]} py=${ST[material.py]} pw=${ST[material.pw]}
    svg_glass card "$px" "$py" "$pw" "${ST[material.ph]}" "${ST[material.radius]}"
    cat <<EOF
<image href="$(shell_icon_file "$shell")" x="$((px + 52))" y="$((py + 46))" width="72" height="72"/>
<text x="$((px + 148))" y="$((py + 90))" $SANS font-weight="600" font-size="40" letter-spacing="-.6" fill="#$TEXT">$name</text>
<text x="$((px + 148))" y="$((py + 122))" $SANS font-size="20" fill="#$DIM">$blurb</text>
<text x="$((px + pw - 52))" y="$((py + 62))" $SANS font-weight="500" font-size="15" letter-spacing="2.4" text-anchor="end" fill="#$DIM">DCLI · BOOT</text>
<rect x="$((px + 52))" y="$((py + 168))" width="$((pw - 104))" height="1" fill="#fff" fill-opacity=".09"/>
<rect x="$((px + 52))" y="$((py + 560))" width="$((pw - 104))" height="1" fill="#fff" fill-opacity=".09"/>
EOF
    svg_dock "${ST[material.dock_cx]}" "${ST[material.dock_y]}" "$shell"
}

svg_scene_sidebar() {
    local shell="$1" name blurb
    name=$(xml_escape "${shell^}")
    blurb=$(xml_escape "$(shell_blurb "$shell")")
    echo "<rect y=\"$((SCREEN_H / 2))\" x=\"600\" width=\"$((SCREEN_W - 600))\" height=\"$((SCREEN_H / 2))\" fill=\"url(#floor)\"/>"
    svg_glass side "${ST[sidebar.px]}" "${ST[sidebar.py]}" "${ST[sidebar.pw]}" "${ST[sidebar.ph]}" 0 0
    cat <<EOF
<image href="$(shell_icon_file "$shell")" x="72" y="84" width="64" height="64"/>
<text x="156" y="118" $SANS font-weight="600" font-size="30" letter-spacing="-.3" fill="#$TEXT">dcli</text>
<text x="156" y="144" $SANS font-size="17" letter-spacing="2.2" fill="#$DIM">CHOOSE A SYSTEM</text>
<rect x="72" y="204" width="476" height="1" fill="#fff" fill-opacity=".10"/>
<rect x="72" y="$((${ST[sidebar.key_y]} - 16))" width="476" height="1" fill="#fff" fill-opacity=".10"/>
<g filter="url(#softshadow)" opacity=".7"><text x="676" y="838" $SANS font-weight="600" font-size="164" letter-spacing="-5" fill="#000">$name</text></g>
<text x="676" y="838" $SANS font-weight="600" font-size="164" letter-spacing="-5" fill="#fff">$name</text>
<rect x="682" y="872" width="64" height="5" rx="2.5" fill="#$ACCENT"/>
<text x="682" y="928" $SANS font-weight="400" font-size="36" letter-spacing=".2" fill="#fff" fill-opacity=".86">$blurb</text>
EOF
    svg_dock "${ST[sidebar.dock_cx]}" "${ST[sidebar.dock_y]}" "$shell"
}

svg_scene_terminal() {
    local shell="$1" blurb px py pw ph
    blurb=$(xml_escape "$(shell_blurb "$shell")")
    px=${ST[terminal.px]} py=${ST[terminal.py]} pw=${ST[terminal.pw]} ph=${ST[terminal.ph]}
    svg_glass term "$px" "$py" "$pw" "$ph" 0
    cat <<EOF
<rect x="$px" y="$py" width="$pw" height="$ph" fill="url(#grid)"/>
<rect x="$px" y="$py" width="$pw" height="56" fill="#fff" fill-opacity=".045"/>
<rect x="$px" y="$((py + 56))" width="$pw" height="1" fill="#$ACCENT" fill-opacity=".5"/>
<text x="$((px + 28))" y="$((py + 36))" $MONO font-weight="700" font-size="22" fill="#$ACCENT">$shell@dcli</text>
<text x="$((px + 28 + 12 * 14 + 4))" y="$((py + 36))" $MONO font-size="22" fill="#$DIM">~ boot</text>
<rect x="$((px + pw - 100))" y="$((py + 22))" width="12" height="12" fill="#$DIM" fill-opacity=".6"/>
<rect x="$((px + pw - 76))" y="$((py + 22))" width="12" height="12" fill="#$DIM" fill-opacity=".6"/>
<rect x="$((px + pw - 52))" y="$((py + 22))" width="12" height="12" fill="#$ACCENT"/>
<image href="$(shell_icon_file "$shell")" x="$((px + pw - 100))" y="$((py + 90))" width="72" height="72"/>
<text x="$((px + 28))" y="$((py + 112))" $MONO font-size="20" fill="#$DIM"><tspan fill="#$ACCENT">❯</tspan> cat /etc/dcli/shell</text>
<text x="$((px + 28))" y="$((py + 148))" $MONO font-weight="700" font-size="26" fill="#$TEXT">$shell <tspan font-weight="400" fill="#$DIM">· $blurb</tspan></text>
<rect x="$((px + 28))" y="$((py + 176))" width="$((pw - 56))" height="1" fill="#fff" fill-opacity=".10"/>
<rect x="$((px + 28))" y="$((${ST[terminal.key_y]} - 14))" width="$((pw - 56))" height="1" fill="#fff" fill-opacity=".10"/>
EOF
    svg_dock "${ST[terminal.dock_cx]}" "${ST[terminal.dock_y]}" "$shell"
}

svg_scene_dotmatrix() {
    local shell="$1" name blurb px py pw ph
    name=$(xml_escape "${shell^^}")
    blurb=$(xml_escape "$(shell_blurb "$shell" | tr '[:lower:]' '[:upper:]')")
    px=${ST[dotmatrix.px]} py=${ST[dotmatrix.py]} pw=${ST[dotmatrix.pw]} ph=${ST[dotmatrix.ph]}
    svg_glass dm "$px" "$py" "$pw" "$ph" "${ST[dotmatrix.radius]}"
    cat <<EOF
<rect x="$px" y="$py" width="$pw" height="$ph" rx="${ST[dotmatrix.radius]}" fill="url(#dots)"/>
<circle cx="$((px + 66))" cy="$((py + 78))" r="9" fill="#$ACCENT"/>
<text x="$((px + 96))" y="$((py + 90))" $MONO font-weight="700" font-size="34" letter-spacing="9" fill="#$TEXT">$name</text>
<text x="$((px + 96))" y="$((py + 124))" $MONO font-size="15" letter-spacing="3.4" fill="#$DIM">$blurb</text>
<g fill="#$ACCENT">
<circle cx="$((px + pw - 78))" cy="$((py + 66))" r="3.5"/><circle cx="$((px + pw - 62))" cy="$((py + 66))" r="3.5" fill-opacity=".5"/><circle cx="$((px + pw - 46))" cy="$((py + 66))" r="3.5" fill-opacity=".22"/>
</g>
<rect x="$((px + 56))" y="$((py + 168))" width="$((pw - 112))" height="1" fill="#fff" fill-opacity=".14"/>
<rect x="$((px + 56))" y="$((${ST[dotmatrix.key_y]} - 18))" width="$((pw - 112))" height="1" fill="#fff" fill-opacity=".14"/>
EOF
    svg_dock "${ST[dotmatrix.dock_cx]}" "${ST[dotmatrix.dock_y]}" "$shell"
}

# ── Sprite sheet (icons + 9-slice pixmaps) ───────────────────────────────────
SPRITE_Y=0
SPRITE_SVG=""
SPRITE_CROPS=()
declare -A SLICE_PADS=()

sprite_crop() { # name x y w h -> crop group into the output dir
    SPRITE_CROPS+=('(' +clone -crop "${4}x${5}+${2}+${3}" +repage -depth 8 -write "PNG32:$OUT/$1" +delete ')')
}

# add_slice9 <prefix> <Lp> <Rp> <Tp> <Bp> <cw> <ch> — artwork on stdin, drawn
# in the outer box's own coordinates (0,0 .. W,H).
add_slice9() {
    local prefix="$1" lp="$2" rp="$3" tp="$4" bp="$5" cw="$6" ch="$7" height y art
    height=$((tp + ch + bp))
    y=$SPRITE_Y
    art=$(cat)
    SPRITE_SVG+="<g transform=\"translate(0,$y)\">$art</g>"$'\n'
    SPRITE_Y=$((SPRITE_Y + height + SPRITE_GAP))
    SLICE_PADS["$prefix"]="$lp $rp $tp $bp $cw $ch"
    sprite_crop "${prefix}_nw.png" 0 "$y" "$lp" "$tp"
    sprite_crop "${prefix}_n.png" "$lp" "$y" "$cw" "$tp"
    sprite_crop "${prefix}_ne.png" "$((lp + cw))" "$y" "$rp" "$tp"
    sprite_crop "${prefix}_w.png" 0 "$((y + tp))" "$lp" "$ch"
    sprite_crop "${prefix}_c.png" "$lp" "$((y + tp))" "$cw" "$ch"
    sprite_crop "${prefix}_e.png" "$((lp + cw))" "$((y + tp))" "$rp" "$ch"
    sprite_crop "${prefix}_sw.png" 0 "$((y + tp + ch))" "$lp" "$bp"
    sprite_crop "${prefix}_s.png" "$lp" "$((y + tp + ch))" "$cw" "$bp"
    sprite_crop "${prefix}_se.png" "$((lp + cw))" "$((y + tp + ch))" "$rp" "$bp"
}

SLICE_CW=8

selection_art() { # W H
    local w="$1" h="$2" lp=${ST[$STYLE.pad_l]} mid
    mid=$((h / 2))
    case "$STYLE" in
    material)
        cat <<EOF
<defs><linearGradient id="selg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#$ACCENT" stop-opacity=".38"/><stop offset="1" stop-color="#$ACCENT" stop-opacity=".16"/></linearGradient></defs>
<rect x=".5" y=".5" width="$((w - 1))" height="$((h - 1))" rx="24" fill="url(#selg)" stroke="#$ACCENT" stroke-opacity=".62"/>
<path d="M24 1.5H$((w - 24))" stroke="#fff" stroke-opacity=".22" stroke-width="1"/>
EOF
        ;;
    sidebar)
        cat <<EOF
<rect x=".5" y=".5" width="$((w - 1))" height="$((h - 1))" rx="16" fill="#$ACCENT" fill-opacity=".17" stroke="#$ACCENT" stroke-opacity=".34"/>
<rect x="8" y="$((mid - 11))" width="4" height="22" rx="2" fill="#$ACCENT"/>
EOF
        ;;
    terminal)
        cat <<EOF
<rect width="$w" height="$h" fill="#$ACCENT"/>
<path d="M$((lp - 28)) $((mid - 8))L$((lp - 17)) ${mid}L$((lp - 28)) $((mid + 8))" fill="none" stroke="#$SELTEXT" stroke-width="3" stroke-linecap="square"/>
EOF
        ;;
    dotmatrix)
        cat <<EOF
<rect x=".5" y=".5" width="$((w - 1))" height="$((h - 1))" rx="$((h / 2))" fill="#1a1a1a" stroke="#3a3a3a"/>
<circle cx="$((lp - 24))" cy="$mid" r="7" fill="#$ACCENT"/>
EOF
        ;;
    esac
}

item_art() { # W H — the unselected row
    local h="$2" lp=${ST[$STYLE.pad_l]}
    [ "$STYLE" = dotmatrix ] && echo "<circle cx=\"$((lp - 24))\" cy=\"$((h / 2))\" r=\"2.6\" fill=\"#fff\" fill-opacity=\".28\"/>"
    return 0
}

bar_art() { # W H track|fill
    local w="$1" h="$2" fill="$3" r=${ST[$STYLE.bar_r]}
    if [ "$fill" = track ]; then
        echo "<rect x=\".5\" y=\".5\" width=\"$((w - 1))\" height=\"$((h - 1))\" rx=\"$r\" fill=\"#fff\" fill-opacity=\".13\" stroke=\"#fff\" stroke-opacity=\".10\"/>"
    else
        echo "<rect width=\"$w\" height=\"$h\" rx=\"$r\" fill=\"#$ACCENT\"/>"
    fi
}

terminal_box_art() {
    local w="$1" h="$2" r=${ST[$STYLE.radius]}
    [ "$r" -gt 16 ] && r=16
    echo "<rect x=\".5\" y=\".5\" width=\"$((w - 1))\" height=\"$((h - 1))\" rx=\"$r\" fill=\"#$PANEL\" fill-opacity=\".94\" stroke=\"#$ACCENT\" stroke-opacity=\".5\"/>"
}

# Icons: line art tinted with the theme's text colour, shell logos as drawn.
add_icon_art() { # name  inner-svg  [filter]
    local name="$1" art="$2" size=${ST[$STYLE.icon]} y=$SPRITE_Y scale stroke cap
    scale=$(awk -v s="$size" 'BEGIN { printf "%.4f", s / 24 }')
    cap=round
    stroke=1.7
    [ "$STYLE" = terminal ] && { cap=square; stroke=2; }
    SPRITE_SVG+="<g transform=\"translate(0,$y) scale($scale)\" fill=\"none\" stroke=\"#$ICON_INK\" stroke-width=\"$stroke\" stroke-linecap=\"$cap\" stroke-linejoin=\"round\">$art</g>"$'\n'
    SPRITE_Y=$((SPRITE_Y + size + SPRITE_GAP))
    sprite_crop "icons/$name.png" 0 "$y" "$size" "$size"
}

add_logo_icon() { # name file
    local name="$1" file="$2" size=${ST[$STYLE.icon]} y=$SPRITE_Y filter=""
    [ "${ST[$STYLE.logo_mono]}" = 1 ] && filter=' filter="url(#mono)"'
    SPRITE_SVG+="<image href=\"$file\" x=\"0\" y=\"$y\" width=\"$size\" height=\"$size\"$filter/>"$'\n'
    SPRITE_Y=$((SPRITE_Y + size + SPRITE_GAP))
    sprite_crop "icons/$name.png" 0 "$y" "$size" "$size"
}

build_sprites() {
    local lp rp tp bp h w br bt name
    SPRITE_Y=0
    SPRITE_SVG=""
    SPRITE_CROPS=()
    SLICE_PADS=()
    ICON_INK="$TEXT"
    [ "$STYLE" = dotmatrix ] && ICON_INK="ffffff"
    lp=${ST[$STYLE.pad_l]} rp=${ST[$STYLE.pad_r]} tp=${ST[$STYLE.pad_t]} bp=${ST[$STYLE.pad_t]}
    h=${ST[$STYLE.item_h]}
    w=$((lp + SLICE_CW + rp))
    add_slice9 select "$lp" "$rp" "$tp" "$bp" "$SLICE_CW" "$h" < <(selection_art "$w" "$((tp + h + bp))")
    add_slice9 item "$lp" "$rp" "$tp" "$bp" "$SLICE_CW" "$h" < <(item_art "$w" "$((tp + h + bp))")
    br=${ST[$STYLE.bar_r]}
    [ "$br" -lt 2 ] && br=2
    bt=$(((${ST[$STYLE.bar_h]} - 2) / 2))
    w=$((br * 2 + SLICE_CW))
    add_slice9 timeout_bg "$br" "$br" "$bt" "$bt" "$SLICE_CW" 2 < <(bar_art "$w" "${ST[$STYLE.bar_h]}" track)
    add_slice9 timeout_hl "$br" "$br" "$bt" "$bt" "$SLICE_CW" 2 < <(bar_art "$w" "${ST[$STYLE.bar_h]}" fill)
    add_slice9 terminal_box 14 14 14 14 16 16 < <(terminal_box_art 44 44)
    for name in "${ICON_NAMES[@]}"; do
        add_icon_art "$name" "${ICON_ART[$name]}"
    done
    add_icon_art dcli "<rect x=\"3.5\" y=\"3.5\" width=\"7\" height=\"7\" rx=\"2\" fill=\"#$ACCENT\" stroke=\"#$ACCENT\"/><rect x=\"13.5\" y=\"3.5\" width=\"7\" height=\"7\" rx=\"2\"/><rect x=\"3.5\" y=\"13.5\" width=\"7\" height=\"7\" rx=\"2\"/><rect x=\"13.5\" y=\"13.5\" width=\"7\" height=\"7\" rx=\"2\"/>"
    for name in "${KNOWN[@]}"; do
        add_logo_icon "dcli-$name" "$(shell_icon_file "$name")"
    done
    {
        echo "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"$SPRITE_W\" height=\"$SPRITE_Y\" viewBox=\"0 0 $SPRITE_W $SPRITE_Y\"><defs><filter id=\"mono\" color-interpolation-filters=\"sRGB\"><feColorMatrix type=\"saturate\" values=\"0\"/></filter></defs>"
        printf '%s' "$SPRITE_SVG"
        echo "</svg>"
    } >"$WORK/sprite.svg"
    resvg "$WORK/sprite.svg" "$WORK/sprite.png" 2>/dev/null || return 1
    mkdir -p "$OUT/icons" || return 1
    magick "$WORK/sprite.png" "${SPRITE_CROPS[@]}" null: || return 1
}

# ── theme.txt ────────────────────────────────────────────────────────────────
write_theme() {
    local fam=${ST[$STYLE.font]} item sel small
    if [ "$fam" = mono ]; then
        item=${FONT_NAME[mono-22]} sel=${FONT_NAME[mono-b-22]} small=${FONT_NAME[mono-16]}
    else
        item=${FONT_NAME[sans-22]} sel=${FONT_NAME[sans-sb-22]} small=${FONT_NAME[sans-16]}
    fi
    local bar_h=${ST[$STYLE.bar_h]}
    cat >"$OUT/theme.txt" <<EOF
# dcli GRUB theme for $THEME_SHELL ($STYLE) — generated by scripts/render-grub-theme.sh
title-text: ""
desktop-image: "background.jpg"
desktop-color: "#$PANEL"
message-font: "${FONT_NAME[sans-16]}"
message-color: "#$TEXT"
message-bg-color: "#$PANEL"
terminal-font: "${FONT_NAME[mono-16]}"
terminal-box: "terminal_box_*.png"
terminal-left: "12%"
terminal-top: "12%"
terminal-width: "76%"
terminal-height: "76%"
terminal-border: "0"

+ boot_menu {
  left = ${ST[$STYLE.menu_x]}
  top = ${ST[$STYLE.menu_y]}
  width = ${ST[$STYLE.menu_w]}
  height = ${ST[$STYLE.menu_h]}
  item_font = "$item"
  selected_item_font = "$sel"
  item_color = "#$DIM"
  selected_item_color = "#$SELTEXT"
  icon_width = ${ST[$STYLE.icon]}
  icon_height = ${ST[$STYLE.icon]}
  item_height = ${ST[$STYLE.item_h]}
  item_padding = 0
  item_icon_space = ${ST[$STYLE.icon_gap]}
  item_spacing = ${ST[$STYLE.spacing]}
  item_pixmap_style = "item_*.png"
  selected_item_pixmap_style = "select_*.png"
}

+ label {
  left = ${ST[$STYLE.key_x]}
  top = ${ST[$STYLE.key_y]}
  width = ${ST[$STYLE.key_w]}
  height = 24
  text = "@KEYMAP_SHORT@"
  font = "$small"
  color = "#$DIM"
  align = "left"
}

+ progress_bar {
  id = "__timeout__"
  left = ${ST[$STYLE.bar_x]}
  top = ${ST[$STYLE.bar_y]}
  width = ${ST[$STYLE.bar_w]}
  height = $bar_h
  bar_style = "timeout_bg_*.png"
  highlight_style = "timeout_hl_*.png"
}

+ label {
  id = "__timeout__"
  left = ${ST[$STYLE.tmo_x]}
  top = ${ST[$STYLE.tmo_y]}
  width = ${ST[$STYLE.tmo_w]}
  height = 24
  text = "@TIMEOUT_NOTIFICATION_SHORT@"
  font = "$small"
  color = "#$ACCENT"
  align = "left"
}
EOF
}

# ── Preview ──────────────────────────────────────────────────────────────────
svg9() { # prefix x y W H -> nine <image> tags, edges stretched like GRUB does
    local prefix="$1" x="$2" y="$3" w="$4" h="$5" lp rp tp bp cw ch dir="$OUT"
    read -r lp rp tp bp cw ch <<<"${SLICE_PADS[$prefix]}"
    local cwid=$((w - lp - rp)) chei=$((h - tp - bp))
    local a='preserveAspectRatio="none"'
    cat <<EOF
<image href="$dir/${prefix}_nw.png" x="$x" y="$y" width="$lp" height="$tp" $a/>
<image href="$dir/${prefix}_n.png" x="$((x + lp))" y="$y" width="$cwid" height="$tp" $a/>
<image href="$dir/${prefix}_ne.png" x="$((x + w - rp))" y="$y" width="$rp" height="$tp" $a/>
<image href="$dir/${prefix}_w.png" x="$x" y="$((y + tp))" width="$lp" height="$chei" $a/>
<image href="$dir/${prefix}_c.png" x="$((x + lp))" y="$((y + tp))" width="$cwid" height="$chei" $a/>
<image href="$dir/${prefix}_e.png" x="$((x + w - rp))" y="$((y + tp))" width="$rp" height="$chei" $a/>
<image href="$dir/${prefix}_sw.png" x="$x" y="$((y + h - bp))" width="$lp" height="$bp" $a/>
<image href="$dir/${prefix}_s.png" x="$((x + lp))" y="$((y + h - bp))" width="$cwid" height="$bp" $a/>
<image href="$dir/${prefix}_se.png" x="$((x + w - rp))" y="$((y + h - bp))" width="$rp" height="$bp" $a/>
EOF
}

render_preview() {
    local fam=${ST[$STYLE.font]} font_attr bold_weight small_attr
    if [ "$fam" = mono ]; then
        font_attr="$MONO"
        bold_weight=700
    else
        font_attr="$SANS"
        bold_weight=600
    fi
    small_attr="$font_attr"
    local lp=${ST[$STYLE.pad_l]} tp=${ST[$STYLE.pad_t]} h=${ST[$STYLE.item_h]} pitch icon=${ST[$STYLE.icon]}
    local mx=${ST[$STYLE.menu_x]} my=${ST[$STYLE.menu_y]} mw=${ST[$STYLE.menu_w]} i y color weight
    pitch=$((h + ${ST[$STYLE.spacing]}))
    local labels=("CachyOS Linux" "Advanced options for CachyOS" "Shells" "CachyOS snapshots" "UEFI Firmware Settings")
    local icons=(cachyos gnu-linux dcli snapshots efi)
    {
        echo "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"$SCREEN_W\" height=\"$SCREEN_H\" viewBox=\"0 0 $SCREEN_W $SCREEN_H\">"
        echo "<image href=\"$OUT/background.jpg\" width=\"$SCREEN_W\" height=\"$SCREEN_H\"/>"
        for ((i = 0; i < PREVIEW_ITEMS; i++)); do
            y=$((my + tp + i * pitch))
            if [ "$i" = 0 ]; then
                svg9 select "$mx" "$((y - tp))" "$mw" "$((h + tp * 2))"
                color=$SELTEXT weight=$bold_weight
            else
                svg9 item "$mx" "$((y - tp))" "$mw" "$((h + tp * 2))"
                color=$DIM weight=400
            fi
            echo "<image href=\"$OUT/icons/${icons[$i]}.png\" x=\"$((mx + lp))\" y=\"$((y + (h - icon) / 2))\" width=\"$icon\" height=\"$icon\"/>"
            echo "<text x=\"$((mx + lp + icon + ${ST[$STYLE.icon_gap]}))\" y=\"$((y + h / 2 + 8))\" $font_attr font-size=\"22\" font-weight=\"$weight\" fill=\"#$color\">${labels[$i]}</text>"
        done
        echo "<text x=\"${ST[$STYLE.key_x]}\" y=\"$((${ST[$STYLE.key_y]} + 17))\" $small_attr font-size=\"16\" fill=\"#$DIM\">$(xml_escape "$KEYMAP_SAMPLE")</text>"
        svg9 timeout_bg "${ST[$STYLE.bar_x]}" "${ST[$STYLE.bar_y]}" "${ST[$STYLE.bar_w]}" "${ST[$STYLE.bar_h]}"
        svg9 timeout_hl "${ST[$STYLE.bar_x]}" "${ST[$STYLE.bar_y]}" "$((${ST[$STYLE.bar_w]} * 62 / 100))" "${ST[$STYLE.bar_h]}"
        echo "<text x=\"${ST[$STYLE.tmo_x]}\" y=\"$((${ST[$STYLE.tmo_y]} + 17))\" $small_attr font-size=\"16\" fill=\"#$ACCENT\">$TIMEOUT_SAMPLE</text>"
        echo "</svg>"
    } >"$WORK/preview.svg"
    resvg "$WORK/preview.svg" "$OUT/preview.png" 2>/dev/null
}

# ── One shell ────────────────────────────────────────────────────────────────
render_shell() {
    local shell="$1" wallpaper build title started
    started=$SECONDS
    STYLE=${STYLE_OF[$shell]:-$DEFAULT_STYLE}
    THEME_SHELL=$shell
    wallpaper=$(shell_wallpaper "$shell")

    prepare_wallpaper "$wallpaper" "$shell" || {
        fail "$shell: wallpaper preparation failed"
        return 1
    }
    derive_colors "$shell" "$STYLE" "$WP_HIST" "$WP_BLUR" || return 1
    TINT=${ST[$STYLE.tint]}
    TINT_A=${ST[$STYLE.tint_a]}

    build="$STAGE_DIR/$shell.tmp"
    rm -rf "$build"
    mkdir -p "$build/icons" || return 1
    OUT="$build"

    build_sprites || {
        fail "$shell: sprite rendering failed"
        return 1
    }
    {
        svg_prelude
        "svg_scene_$STYLE" "$shell"
        echo "</svg>"
    } >"$WORK/scene.svg"
    resvg "$WORK/scene.svg" "$WORK/scene.png" 2>/dev/null || {
        fail "$shell: scene rendering failed"
        return 1
    }
    magick "$WORK/scene.png" -background black -alpha remove -alpha off -colorspace sRGB -depth 8 \
        -interlace None -quality "$JPEG_QUALITY" "$OUT/background.jpg" || return 1

    write_theme || return 1
    title=$(printf '%s · %s' "$shell" "$(shell_blurb "$shell")" | tr -d '"\\$\n')
    printf '%s\n' "$title" >"$OUT/title.txt" || return 1
    render_preview || {
        fail "$shell: preview rendering failed"
        return 1
    }
    : >"$OUT/.complete" || return 1

    rm -rf "${STAGE_DIR:?}/$shell"
    mv "$build" "$STAGE_DIR/$shell" || return 1
    say "$shell ($STYLE) rendered in $((SECONDS - started))s — accent #$ACCENT"
}

# ── Main ─────────────────────────────────────────────────────────────────────
atomic_write() { # file content
    printf '%s\n' "$2" >"$1.tmp" && mv "$1.tmp" "$1"
}

contact_sheet() {
    local args=() name
    for name in "${KNOWN[@]}"; do
        [ -f "$STAGE_DIR/$name/preview.png" ] && args+=(-label "$name" "$STAGE_DIR/$name/preview.png")
    done
    [ "${#args[@]}" -gt 0 ] || return 0
    magick montage -font Inter-Medium -pointsize 24 -fill '#cfd3dc' -background '#0b0c10' \
        "${args[@]}" -tile 2x -geometry "${CONTACT_TILE_W}x${CONTACT_TILE_H}+16+16" \
        "$STAGE_DIR/contact-sheet.png.tmp.png" 2>/dev/null &&
        mv "$STAGE_DIR/contact-sheet.png.tmp.png" "$STAGE_DIR/contact-sheet.png"
}

# What a shell's theme was last drawn from: its wallpaper (path, mtime, size),
# this renderer's own mtime, and the newest of the registry and the logos —
# every theme's dock draws all of them, so a swapped logo re-renders everything.
wallpaper_signature() {
    local wallpaper
    wallpaper=$(shell_wallpaper "$1")
    printf '%s|%s|%s|%s\n' "${wallpaper:-gradient}" \
        "$([ -z "$wallpaper" ] || stat -c '%Y %s' -- "$wallpaper" 2>/dev/null)" \
        "$(stat -c %Y -- "${BASH_SOURCE[0]}")" \
        "$(stat -c %Y -- "$SHELL_REGISTRY" "$ICON_SRC_DIR"/* 2>/dev/null | sort -n | tail -n1)"
}

is_current() {
    [ -e "$STAGE_DIR/$1/.complete" ] &&
        [ "$(cat "$SIGNATURE_DIR/$1" 2>/dev/null)" = "$(wallpaper_signature "$1")" ]
}

if [ "$ONLY_CHANGED" = 1 ]; then
    stale=()
    for target in "${TARGETS[@]}"; do
        is_current "$target" || stale+=("$target")
    done
    # The path unit fires on every write to files like dms's session.json, so
    # the common case is "nothing changed" — exit before any image work.
    [ "${#stale[@]}" -gt 0 ] || exit 0
    TARGETS=("${stale[@]}")
fi

ensure_fonts || exit 1
mkdir -p "$SIGNATURE_DIR" || fail "cannot create $SIGNATURE_DIR (--changed will re-render)"

FAILED=0
RENDERED=0
for target in "${TARGETS[@]}"; do
    # Taken BEFORE rendering: a wallpaper changed mid-render must still look
    # stale next time.
    signature=$(wallpaper_signature "$target")
    if render_shell "$target"; then
        RENDERED=$((RENDERED + 1))
        printf '%s\n' "$signature" >"$SIGNATURE_DIR/$target" 2>/dev/null || true
    else
        FAILED=$((FAILED + 1))
        rm -rf "${STAGE_DIR:?}/$target.tmp"
    fi
done

if [ "$RENDERED" -gt 0 ]; then
    if [ -n "$ACTIVE_NAME" ] && { [ -n "$ACTIVE_OVERRIDE" ] || [ -z "$TARGET_ARG" ] || [ ! -s "$STAGE_DIR/active" ]; }; then
        [ -e "$STAGE_DIR/$ACTIVE_NAME/.complete" ] && atomic_write "$STAGE_DIR/active" "$ACTIVE_NAME"
    fi
    contact_sheet || fail "contact sheet failed (cosmetic)"
    atomic_write "$STAGE_DIR/.stamp" "$(date +%s%N)" || {
        fail "cannot write .stamp"
        exit 1
    }
fi

if [ "$FAILED" -gt 0 ]; then
    fail "$FAILED of ${#TARGETS[@]} shell theme(s) failed"
    exit 1
fi
say "GRUB themes staged in $STAGE_DIR"
