#!/bin/bash
# Render the per-shell SDDM data into state/sddm-theme/ (the user side of the
# SDDM layer; the root side — dcli-sddm-sync — installs what lands here).
#
# Usage: render-sddm-theme.sh [--active <shell>] [--changed] [shell|all]
#   (no argument)    render the running shell and refresh `active`
#   <shell>          render that one shell
#   all              render every registry shell
#   --active <shell> treat <shell> as the running one (switch-shell.sh passes
#                    this before active.conf is trusted); in `auto` mode it is
#                    also the theme SDDM will wear
#   --changed        skip shells whose inputs (palette file, wallpaper,
#                    avatar, this script) are unchanged since the last render
#
# STAGING CONTRACT (state/sddm-theme/, read by the root side)
#   <shell>/theme.conf.user  key=value palette + look, written over theme.conf
#   <shell>/background.jpg   the shell's wallpaper, 1920x1080-ish JPEG
#   <shell>/avatar.png       optional, from ~/.face(.icon)
#   <shell>/.complete        written last
#   active                   one line: the shell whose theme SDDM wears
#   .stamp                   rewritten LAST — the root path unit watches it
#
# PALETTE
#   Each shell writes its live colours somewhere (PALETTE_SOURCES below); this
#   normalises them to one key set. A shell with no live file gets matugen run
#   on its own wallpaper, then the static default for the shell. Caelestia is
#   special: its own template already renders a complete theme.conf, which is
#   passed through (its theme is the upstream "locklike" one).
set -uo pipefail

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

# shellcheck source=lib/shell-common.sh disable=SC1091
. "$SCRIPT_DIR/lib/shell-common.sh" || exit 1
# shellcheck source=lib/wallpaper.sh disable=SC1091
. "$SCRIPT_DIR/lib/wallpaper.sh" || exit 1
# shellcheck source=lib/sddm-common.sh disable=SC1091
. "$SCRIPT_DIR/lib/sddm-common.sh" || exit 1

# ── Constants ────────────────────────────────────────────────────────────────
STAGE_DIR="${DCLI_SDDM_STAGE:-$SDDM_STAGING_DIR}"
SIGNATURE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/dcli/sddm-signature"
LOCK_WAIT_SECONDS=60
SCREEN_W=1920
SCREEN_H=1080
JPEG_QUALITY=88
AVATAR_PX=256
MATUGEN_PREFER=saturation
CAELESTIA_CONF=".local/state/caelestia/theme/sddm-theme.conf"
SHELL_RE='^[a-z0-9][a-z0-9-]*$'

# Colours used when neither a live file nor a wallpaper is available.
DEFAULT_PALETTE='{"background":"#111318","surface":"#111318","surfaceContainer":"#1d2024","surfaceVariant":"#43474e","text":"#e2e2e9","primary":"#a8c8ff","onPrimary":"#062e6f","secondary":"#bec6dc","tertiary":"#ddbce0","error":"#ffb4ab","outline":"#8d9199"}'

# Per-shell look: shell|variant|font|radius|cardRadius|fallback palette.
# variants: card | minimal | terminal | dots   (sddm/base/Main.qml)
# The fallback column overrides DEFAULT_PALETTE for shells whose palette is
# fixed by design (glyph) — "-" keeps the default.
LOOK_TABLE=(
    "caelestia|locklike|Rubik|20|30|-"
    "ambxst|card|Roboto Condensed|16|28|-"
    "dms|card|Google Sans Flex|20|28|-"
    "noctalia|minimal|Sans Serif|12|20|-"
    "end4|card|Google Sans Flex|17|30|-"
    "end4pc|minimal|Google Sans Flex|17|30|-"
    "omarchy|terminal|JetBrainsMono Nerd Font|0|0|-"
    "xenon|card|JetBrainsMono Nerd Font|12|20|-"
    "glyph|dots|Space Grotesk|4|27|{\"background\":\"#000000\",\"surface\":\"#000000\",\"surfaceContainer\":\"#0e0e0e\",\"surfaceVariant\":\"#1a1a1a\",\"text\":\"#f2f2f2\",\"primary\":\"#d71921\",\"onPrimary\":\"#f2f2f2\",\"secondary\":\"#8c8c8c\",\"tertiary\":\"#8c8c8c\",\"error\":\"#d71921\",\"outline\":\"#2a2a2a\"}"
    "ryoku|minimal|Space Grotesk|10|18|-"
)

# Live palette sources: shell|file (relative to $HOME)|jq program producing the
# normalised object. First existing file wins; none = matugen on the wallpaper.
read -r -d '' JQ_SNAKE <<'JQ' || true
{background:.background, surface:.surface, surfaceContainer:.surface_container, surfaceVariant:.surface_variant,
 text:.on_surface, primary:.primary, onPrimary:.on_primary, secondary:.secondary, tertiary:.tertiary,
 error:.error, outline:.outline}
JQ
read -r -d '' JQ_CAMEL <<'JQ' || true
{background:.background, surface:.surface, surfaceContainer:.surfaceContainer, surfaceVariant:.surfaceVariant,
 text:(.onSurface // .foreground), primary:.primary, onPrimary:.onPrimary, secondary:.secondary, tertiary:.tertiary,
 error:.error, outline:.outline}
JQ
read -r -d '' JQ_AMBXST <<'JQ' || true
{background:.background, surface:.surface, surfaceContainer:.surfaceContainer, surfaceVariant:.surfaceVariant,
 text:.overBackground, primary:.primary, onPrimary:.overPrimary, secondary:.secondary, tertiary:.tertiary,
 error:.error, outline:.outline}
JQ
read -r -d '' JQ_XENON <<'JQ' || true
.colors as $c | ($c | map_values(.dark)) as $d |
{background:$d.background, surface:$d.surface, surfaceContainer:$d.surface_container, surfaceVariant:$d.surface_variant,
 text:$d.on_surface, primary:$d.primary, onPrimary:$d.on_primary, secondary:$d.secondary, tertiary:$d.tertiary,
 error:$d.error, outline:$d.outline}
JQ
read -r -d '' JQ_DMS <<'JQ' || true
.colors.dark | {background:.background, surface:.surface, surfaceContainer:.surface_container, surfaceVariant:.surface_variant,
 text:.on_surface, primary:.primary, onPrimary:.on_primary, secondary:.secondary, tertiary:.tertiary,
 error:.error, outline:.outline}
JQ
PALETTE_SOURCES=(
    "ambxst|.cache/ambxst/colors.json|$JQ_AMBXST"
    "dms|.cache/DankMaterialShell/dms-colors.json|$JQ_DMS"
    "end4|.local/state/quickshell/user/generated/colors.json|$JQ_SNAKE"
    "end4pc|.local/state/quickshell/user/generated/colors.json|$JQ_SNAKE"
    "xenon|.cache/xenon/colors.json|$JQ_XENON"
    "ryoku|.cache/ryoku/colors.json|$JQ_CAMEL"
)

# ── Helpers ──────────────────────────────────────────────────────────────────
log() { echo "render-sddm-theme: $*"; }
warn() { echo "render-sddm-theme: !! $*" >&2; }

HEX_RE='^#[0-9a-fA-F]{6}$'

# normalised_ok <json>: every key present and a #rrggbb colour.
normalised_ok() {
    jq -e --arg re "$HEX_RE" '
        ([.background,.surface,.surfaceContainer,.surfaceVariant,.text,.primary,.onPrimary,.secondary,.tertiary,.error,.outline]
         | all(.[]; type == "string" and test($re)))' <<<"$1" >/dev/null 2>&1
}

# live_palette <shell>: normalised JSON from the shell's own file, or nothing.
live_palette() {
    local want="$1" rec shell file program out home
    home=$(wallpaper_home)
    for rec in "${PALETTE_SOURCES[@]}"; do
        shell=${rec%%|*}
        [ "$shell" = "$want" ] || continue
        file=${rec#*|}
        program=${file#*|}
        file=${file%%|*}
        [ -r "$home/$file" ] || continue
        out=$(jq -c "$program" "$home/$file" 2>/dev/null) || continue
        normalised_ok "$out" && { echo "$out"; return 0; }
    done
    return 0
}

# matugen_palette <wallpaper>: Material-3 dark palette for that image.
matugen_palette() {
    command -v matugen >/dev/null 2>&1 || return 0
    local out
    out=$(matugen image "$1" --json hex --dry-run -m dark --prefer "$MATUGEN_PREFER" 2>/dev/null) || return 0
    jq -c '.colors | def d(k): .[k].dark.color;
        {background:d("background"), surface:d("surface"), surfaceContainer:d("surface_container"),
         surfaceVariant:d("surface_variant"), text:d("on_surface"), primary:d("primary"), onPrimary:d("on_primary"),
         secondary:d("secondary"), tertiary:d("tertiary"), error:d("error"), outline:d("outline")}' <<<"$out" 2>/dev/null
}

look_field() { # <shell> <field index 1..5>
    local rec
    for rec in "${LOOK_TABLE[@]}"; do
        [ "${rec%%|*}" = "$1" ] || continue
        IFS='|' read -r -a parts <<<"$rec"
        echo "${parts[$2]}"
        return 0
    done
    return 1
}

# palette_for <shell> <wallpaper>: normalised JSON, best source first.
palette_for() {
    local shell="$1" wall="$2" out fallback
    out=$(live_palette "$shell")
    [ -n "$out" ] && { echo "$out"; return; }
    fallback=$(look_field "$shell" 5 || echo "-")
    if [ "$fallback" != "-" ] && [ -n "$fallback" ]; then echo "$fallback"; return; fi
    if [ -n "$wall" ]; then
        out=$(matugen_palette "$wall")
        normalised_ok "$out" && { echo "$out"; return; }
    fi
    echo "$DEFAULT_PALETTE"
}

# write_conf <shell> <palette json> <out file>
write_conf() {
    local shell="$1" palette="$2" out="$3" variant font radius card
    variant=$(look_field "$shell" 1 || echo card)
    font=$(look_field "$shell" 2 || echo Inter)
    radius=$(look_field "$shell" 3 || echo 14)
    card=$(look_field "$shell" 4 || echo 28)
    {
        echo "[General]"
        echo "# Rendered by scripts/render-sddm-theme.sh — do not edit"
        echo "shellName=$shell"
        echo "variant=$variant"
        echo "fontFamily=\"$font\""
        echo "radius=$radius"
        echo "cardRadius=$card"
        jq -r 'to_entries[] | "\(.key)=\(.value)"' <<<"$palette"
    } >"$out"
}

# write_caelestia_conf <out>: caelestia's rendered conf, verbatim, when present.
write_caelestia_conf() {
    local src
    src="$(wallpaper_home)/$CAELESTIA_CONF"
    [ -r "$src" ] || return 1
    cp -f "$src" "$1"
}

# stage_background <wallpaper> <palette json> <out.jpg>
stage_background() {
    local wall="$1" palette="$2" out="$3" bg
    if [ -n "$wall" ] && magick "${wall}[0]" -resize "${SCREEN_W}x${SCREEN_H}^" -gravity center \
        -extent "${SCREEN_W}x${SCREEN_H}" -quality "$JPEG_QUALITY" "$out" 2>/dev/null; then
        return 0
    fi
    bg=$(jq -r '.background' <<<"$palette")
    magick -size "${SCREEN_W}x${SCREEN_H}" "xc:$bg" -quality "$JPEG_QUALITY" "$out" 2>/dev/null
}

stage_avatar() { # <out.png>
    local src
    for src in "$HOME/.face" "$HOME/.face.icon"; do
        [ -f "$src" ] || continue
        magick "${src}[0]" -resize "${AVATAR_PX}x${AVATAR_PX}^" -gravity center -extent "${AVATAR_PX}x${AVATAR_PX}" \
            "$1" 2>/dev/null && return 0
    done
    rm -f "$1"
}

# signature <shell> <wallpaper>: cheap fingerprint of every input.
signature() {
    local shell="$1" wall="$2" rec file home
    home=$(wallpaper_home)
    {
        stat -c '%n %Y %s' "$0" "$wall" "$home/.face" "$home/.face.icon" "$home/$CAELESTIA_CONF" 2>/dev/null
        for rec in "${PALETTE_SOURCES[@]}"; do
            [ "${rec%%|*}" = "$shell" ] || continue
            file=${rec#*|}
            stat -c '%n %Y %s' "$home/${file%%|*}" 2>/dev/null
        done
    } | sha256sum | cut -c1-32
}

render_shell() {
    local shell="$1" wall palette tmp final sig
    wall=$(shell_wallpaper "$shell")
    final="$STAGE_DIR/$shell"
    if [ "$CHANGED_ONLY" = 1 ]; then
        sig=$(signature "$shell" "$wall")
        [ "$(cat "$SIGNATURE_DIR/$shell" 2>/dev/null)" = "$sig" ] && [ -f "$final/.complete" ] && return 1
    fi
    tmp="$STAGE_DIR/$shell.tmp"
    rm -rf "${tmp:?}"
    mkdir -p "$tmp" || { warn "$shell: cannot create $tmp"; return 2; }
    palette=$(palette_for "$shell" "$wall")
    if [ "$(look_field "$shell" 1 || true)" = locklike ] && write_caelestia_conf "$tmp/theme.conf.user"; then :
    else write_conf "$shell" "$palette" "$tmp/theme.conf.user"; fi
    stage_background "$wall" "$palette" "$tmp/background.jpg" || { warn "$shell: background render failed"; rm -rf "${tmp:?}"; return 2; }
    stage_avatar "$tmp/avatar.png"
    : >"$tmp/.complete"
    rm -rf "${final:?}"
    mv -T "$tmp" "$final" || { warn "$shell: could not move into place"; return 2; }
    mkdir -p "$SIGNATURE_DIR" && echo "${sig:-$(signature "$shell" "$wall")}" >"$SIGNATURE_DIR/$shell"
    log "rendered $shell"
    return 0
}

# ── Arguments ────────────────────────────────────────────────────────────────
ACTIVE_SHELL=""
CHANGED_ONLY=0
TARGET=""
while [ $# -gt 0 ]; do
    case "$1" in
    --active) ACTIVE_SHELL="${2:-}"; shift 2 || { warn "--active needs a shell"; exit 2; } ;;
    --changed) CHANGED_ONLY=1; shift ;;
    -h | --help) sed -n '2,12p' "$0"; exit 0 ;;
    -*) warn "unknown option $1"; exit 2 ;;
    *) TARGET="$1"; shift ;;
    esac
done
[ -n "$ACTIVE_SHELL" ] || ACTIVE_SHELL=$(current_shell)

known() { local k; for k in "${KNOWN[@]}"; do [ "$k" = "$1" ] && return 0; done; return 1; }
if [ -n "$ACTIVE_SHELL" ] && [ "$ACTIVE_SHELL" != none ] && ! known "$ACTIVE_SHELL"; then
    warn "unknown shell: $ACTIVE_SHELL"; exit 2
fi

# `auto` follows the running shell; a pinned mode wins.
mode=$(sddm_mode)
if [ "$mode" = "$SDDM_MODE_AUTO" ]; then theme_shell="$ACTIVE_SHELL"; else theme_shell="$mode"; fi
known "$theme_shell" || theme_shell="${KNOWN[0]}"
[[ "$theme_shell" =~ $SHELL_RE ]] || { warn "bad theme name: $theme_shell"; exit 2; }

case "$TARGET" in
"") targets=("$theme_shell") ;;
all) targets=("${KNOWN[@]}") ;;
*) known "$TARGET" || { warn "unknown shell: $TARGET"; exit 2; }; targets=("$TARGET") ;;
esac
# The theme SDDM wears must always be fresh.
case " ${targets[*]} " in *" $theme_shell "*) ;; *) targets+=("$theme_shell") ;; esac

# ── Single-instance lock ─────────────────────────────────────────────────────
mkdir -p "$STAGE_DIR" || { warn "cannot create $STAGE_DIR"; exit 1; }
exec {LOCK_FD}>"${XDG_RUNTIME_DIR:-/tmp}/render-sddm-theme.lock"
flock -w "$LOCK_WAIT_SECONDS" "$LOCK_FD" || { warn "another render held the lock for ${LOCK_WAIT_SECONDS}s"; exit 1; }

# ── Render ───────────────────────────────────────────────────────────────────
touched=0
failures=0
for shell in "${targets[@]}"; do
    render_shell "$shell"
    case $? in 0) touched=1 ;; 2) failures=$((failures + 1)) ;; esac
done

previous_active=$(cat "$STAGE_DIR/active" 2>/dev/null || true)
if [ "$previous_active" != "$theme_shell" ]; then
    printf '%s\n' "$theme_shell" >"$STAGE_DIR/active.tmp" && mv -f "$STAGE_DIR/active.tmp" "$STAGE_DIR/active"
    touched=1
fi
[ "$touched" = 1 ] && : >"$STAGE_DIR/.stamp"
[ "$failures" -eq 0 ] || { warn "$failures shell(s) failed"; exit 1; }
exit 0
