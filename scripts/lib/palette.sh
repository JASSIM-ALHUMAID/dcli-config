#!/bin/bash
# One home for "what colours is shell X wearing right now", shared by the SDDM
# renderer and the terminal theme (prompt + fastfetch). Most shells here are
# Material You: they regenerate their palette from the wallpaper, so anything
# that wants to look like the shell has to read that, not a hard-coded guess.
#
# palette_for <shell> <wallpaper> prints one normalised JSON object
#   {background, surface, surfaceContainer, surfaceVariant, text, primary,
#    onPrimary, secondary, tertiary, error, outline}   (all #rrggbb)
# from, best first: the shell's own colour file (PALETTE_SOURCES), a palette
# fixed by design (STATIC_PALETTES), matugen on its wallpaper, DEFAULT_PALETTE.
# Needs jq; matugen is optional. Sourced after lib/wallpaper.sh; never executed.
# The tables are read by the sourcing scripts, which shellcheck cannot see.
# shellcheck disable=SC2034

MATUGEN_PREFER=saturation

# Colours used when neither a live file nor a wallpaper is available.
DEFAULT_PALETTE='{"background":"#111318","surface":"#111318","surfaceContainer":"#1d2024","surfaceVariant":"#43474e","text":"#e2e2e9","primary":"#a8c8ff","onPrimary":"#062e6f","secondary":"#bec6dc","tertiary":"#ddbce0","error":"#ffb4ab","outline":"#8d9199"}'

# Shells whose palette is fixed by design, not wallpaper-driven.
declare -A STATIC_PALETTES=(
  [glyph]='{"background":"#000000","surface":"#000000","surfaceContainer":"#0e0e0e","surfaceVariant":"#1a1a1a","text":"#f2f2f2","primary":"#d71921","onPrimary":"#f2f2f2","secondary":"#8c8c8c","tertiary":"#8c8c8c","error":"#d71921","outline":"#2a2a2a"}'
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
# caelestia stores bare hex (no '#') under .colours.
read -r -d '' JQ_CAELESTIA <<'JQ' || true
.colours | map_values("#" + .) |
{background:.background, surface:.surface, surfaceContainer:.surfaceContainer, surfaceVariant:.surfaceVariant,
 text:.onSurface, primary:.primary, onPrimary:.onPrimary, secondary:.secondary, tertiary:.tertiary,
 error:.error, outline:.outline}
JQ
PALETTE_SOURCES=(
    "caelestia|.local/state/caelestia/scheme.json|$JQ_CAELESTIA"
    "ambxst|.cache/ambxst/colors.json|$JQ_AMBXST"
    "dms|.cache/DankMaterialShell/dms-colors.json|$JQ_DMS"
    "end4|.local/state/quickshell/user/generated/colors.json|$JQ_SNAKE"
    "end4pc|.local/state/quickshell/user/generated/colors.json|$JQ_SNAKE"
    "xenon|.cache/xenon/colors.json|$JQ_XENON"
    "ryoku|.cache/ryoku/colors.json|$JQ_CAMEL"
)

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

# palette_for <shell> <wallpaper>: normalised JSON, best source first.
palette_for() {
    local shell="$1" wall="$2" out fallback
    out=$(live_palette "$shell")
    [ -n "$out" ] && { echo "$out"; return; }
    fallback="${STATIC_PALETTES[$shell]:-}"
    [ -n "$fallback" ] && { echo "$fallback"; return; }
    if [ -n "$wall" ]; then
        out=$(matugen_palette "$wall")
        normalised_ok "$out" && { echo "$out"; return; }
    fi
    echo "$DEFAULT_PALETTE"
}
