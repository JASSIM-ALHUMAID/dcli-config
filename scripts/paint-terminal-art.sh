#!/bin/bash
# Paint the worn theme's live-art logo AHEAD of the greeting. The work — policy,
# lock, atomic generations, paint.log — is scripts/terminal-art/paint.py; this
# resolves what it paints: the theme, its live dir and the palette.
#   paint-terminal-art.sh --still|--next [--theme <name>]
# fish_greeting runs --still synchronously when the art is missing or expired
# (a quick single frame), then --next in the background after fastfetch (the
# full art, for the next terminal). The theme is the one whose live-art file
# ~/.config/fastfetch carries; with none, or for a theme that draws no live art
# (no scripts/terminal-art/themes/<name>.py), this does nothing and exits 0.
# --theme <name> paints that theme into $TERMINAL_STATE_DIR/live/<name> instead,
# worn or not (preview-terminal-themes.sh renders into a temp state first).
#
# The palette is the one the theme's greeting was last rendered with
# (terminal_render records it): the art matches the text around it, and
# palette_for, which can run matugen for seconds, stays off the greeting's path.
# Only when no render recorded one is it the running shell's live palette.
#
# Exit: 0 painted, up to date or nothing to do; 1 failed (the old art is kept,
# the detail is in state/terminal/live/paint.log); 2 usage.
# TERMINAL_ART_DIR=<dir> replaces scripts/terminal-art (tests only).
set -euo pipefail

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
TERMINAL_ART_DIR="${TERMINAL_ART_DIR:-$SCRIPT_DIR/terminal-art}"
EXIT_FAILED=1
EXIT_USAGE=2

# shellcheck source=lib/terminal-theme.sh disable=SC1091
. "$SCRIPT_DIR/lib/terminal-theme.sh" || exit 1

usage() { echo "usage: paint-terminal-art.sh --still|--next [--theme <name>]"; }
usage_error() {
  [ -z "${1:-}" ] || echo "!! paint-terminal-art: $1" >&2
  usage >&2
  exit "$EXIT_USAGE"
}

# ── Arguments ────────────────────────────────────────────────────────────────
mode=""
theme=""
while [ $# -gt 0 ]; do
  case "$1" in
    --still | --next)
      [ -z "$mode" ] || usage_error "--still and --next are exclusive"
      mode=${1#--}
      ;;
    --theme)
      if [ $# -lt 2 ] || [ -z "$2" ]; then usage_error "--theme needs a name"; fi
      theme=$2
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *) usage_error "unknown argument: $1" ;;
  esac
  shift
done
[ -n "$mode" ] || usage_error ""

# ── Theme, live dir, palette ─────────────────────────────────────────────────
if [ -n "$theme" ]; then
  terminal_theme_exists "$theme" || usage_error "unknown theme '$theme' (have: $(terminal_themes | tr '\n' ' '))"
  live="$TERMINAL_LIVE_DIR/$theme"
  rendered=$(terminal_rendered_path "$TERMINAL_THEMES_DIR/$theme/fastfetch")
else
  live=$(terminal_live_art "$FASTFETCH_LINK") || exit 0
  theme=${live##*/}
  rendered=$(readlink -f "$FASTFETCH_LINK")
fi
[ -f "$TERMINAL_ART_DIR/themes/$theme.py" ] || exit 0

if ! palette=$(terminal_render_palette "$rendered"); then
  # Sourced only here: the registry parse alone costs the greeting tens of ms.
  # shellcheck source=lib/shell-common.sh disable=SC1091
  . "$SCRIPT_DIR/lib/shell-common.sh" || exit 1
  # shellcheck source=lib/wallpaper.sh disable=SC1091
  . "$SCRIPT_DIR/lib/wallpaper.sh" || exit 1
  # shellcheck source=lib/palette.sh disable=SC1091
  . "$SCRIPT_DIR/lib/palette.sh" || exit 1
  running=$(current_shell)
  palette=$(palette_for "$running" "$(shell_wallpaper "$running")")
fi

# ── Paint ────────────────────────────────────────────────────────────────────
command -v python3 >/dev/null || { echo "!! paint-terminal-art: python3 is not installed" >&2; exit "$EXIT_FAILED"; }
exec python3 -E -s "$TERMINAL_ART_DIR/paint.py" --theme "$theme" --live "$live" --mode "$mode" --palette "$palette"
