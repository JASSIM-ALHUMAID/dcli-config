#!/bin/bash
# Point ~/.config/starship.toml and ~/.config/fastfetch at the given shell's
# prompt and system-info configs (resolution and rendering: lib/terminal-theme.sh).
# Called by switch-shell.sh on every shell change; also runnable by hand:
#   apply-terminal-theme.sh [--dry-run] [--theme <name>|--alt|--alt-v2|--alt-v3] <shell>
#   apply-terminal-theme.sh --refresh
#   apply-terminal-theme.sh --use alt|alt-v2|alt-v3|upstream|theme:<name>
# --alt wears the opt-in alternates in dotfiles/terminal/_alt/<shell>/ until the
# next switch (a shell without one keeps its normal config). --alt-v2 wears the
# second set in dotfiles/terminal/_alt-v2/<shell>/, which every registry shell
# has. --alt-v3 is the pixel-logo edition of alt-v2 (fastfetch only; the prompt
# stays alt-v2's). --use alt|alt-v2|alt-v3 makes that the standing choice for every shell and every
# switch; --use upstream ends both. Either --use re-applies the running shell
# straight away.
# --theme <name> wears a shell-independent theme from dotfiles/terminal/_themes/
# until the next switch; --use theme:<name> makes it the standing choice for
# every shell (any alt flag is cleared, and any --use alt* clears the theme).
# A theme beats every layer above, except that a one-shot --alt* beats a
# standing theme. An unknown theme name is a usage error and changes nothing.
# --refresh re-renders whatever the links currently wear when the shell's
# palette changed (a new wallpaper recolours a Material You shell mid-session);
# it never moves a link. fish_greeting runs it in the background.
#
# A symlink is simply retargeted. A real file or directory at either path is
# the user's own and is moved aside to <path>.bak-<timestamp> first, never
# deleted. A shell whose config cannot be found (checkout not installed) or
# rendered leaves that link exactly as it was and says so — a switch must never
# end up with a broken prompt.
set -euo pipefail

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
# shellcheck source=lib/shell-common.sh disable=SC1091
. "$SCRIPT_DIR/lib/shell-common.sh" || exit 1
# shellcheck source=lib/hook-common.sh disable=SC1091
. "$SCRIPT_DIR/lib/hook-common.sh" || exit 1
# shellcheck source=lib/wallpaper.sh disable=SC1091
. "$SCRIPT_DIR/lib/wallpaper.sh" || exit 1
# shellcheck source=lib/palette.sh disable=SC1091
. "$SCRIPT_DIR/lib/palette.sh" || exit 1
# shellcheck source=lib/terminal-theme.sh disable=SC1091
. "$SCRIPT_DIR/lib/terminal-theme.sh" || exit 1

EXIT_USAGE=2
THEME_USE_PREFIX="theme:"

usage() {
  echo "usage: apply-terminal-theme.sh [--dry-run] [--theme <name>|--alt|--alt-v2|--alt-v3] <${KNOWN[*]// /|}> | --refresh | --use alt|alt-v2|alt-v3|upstream|theme:<name>" >&2
  echo "themes: $(terminal_themes | tr '\n' ' ')" >&2
}

# require_theme <name>: exits with usage when it is not an installed theme.
require_theme() {
  terminal_theme_exists "$1" && return 0
  echo "!! terminal: unknown theme '$1'" >&2
  usage
  exit "$EXIT_USAGE"
}

dry_run=0
refresh=0
use=""
theme_flag=""
theme_flag_given=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) dry_run=1 ;;
    --alt) export TERMINAL_PREFER_ALT=1 ;;
    --alt-v2) export TERMINAL_PREFER_ALT_V2=1 ;;
    --alt-v3) export TERMINAL_PREFER_ALT_V3=1 ;;
    --theme)
      theme_flag="${2:-}"
      theme_flag_given=1
      shift $(($# > 1 ? 1 : 0))
      ;;
    --refresh) refresh=1 ;;
    --use)
      use="${2:-}"
      shift || true
      ;;
    *) break ;;
  esac
  shift
done
load_registry || exit 1
if [ "$theme_flag_given" = 1 ]; then
  require_theme "$theme_flag"
  export TERMINAL_THEME="$theme_flag"
fi
# Warn once, here, about a one-shot or saved theme that is gone; the resolver
# then skips it silently on its many later calls.
terminal_theme_choice >/dev/null

# ── Standing choice ──────────────────────────────────────────────────────────
case "$use" in
  "") ;;
  alt | alt-v2 | alt-v3 | upstream)
    mkdir -p "$TERMINAL_STATE_DIR" || exit 1
    case "$use" in
      alt)
        : >"$TERMINAL_PREFER_ALT_FLAG" || exit 1
        rm -f "$TERMINAL_PREFER_ALT_V2_FLAG" "$TERMINAL_PREFER_ALT_V3_FLAG" || exit 1
        ;;
      alt-v2)
        : >"$TERMINAL_PREFER_ALT_V2_FLAG" || exit 1
        rm -f "$TERMINAL_PREFER_ALT_FLAG" "$TERMINAL_PREFER_ALT_V3_FLAG" || exit 1
        ;;
      alt-v3)
        : >"$TERMINAL_PREFER_ALT_V3_FLAG" || exit 1
        rm -f "$TERMINAL_PREFER_ALT_FLAG" "$TERMINAL_PREFER_ALT_V2_FLAG" || exit 1
        ;;
      upstream)
        rm -f "$TERMINAL_PREFER_ALT_FLAG" "$TERMINAL_PREFER_ALT_V2_FLAG" "$TERMINAL_PREFER_ALT_V3_FLAG" || exit 1
        ;;
    esac
    # Every alt* choice and upstream ends a standing theme.
    rm -f "$TERMINAL_THEME_FILE" || exit 1
    echo ":: terminal: wearing the ${use} configs from now on"
    running=$(current_shell) || exit 0
    exec "$0" "$running"
    ;;
  "$THEME_USE_PREFIX"*)
    use_theme="${use#"$THEME_USE_PREFIX"}"
    require_theme "$use_theme"
    mkdir -p "$TERMINAL_STATE_DIR" || exit 1
    # Atomic, so a terminal opening mid-write never reads half a name.
    printf '%s\n' "$use_theme" >"$TERMINAL_THEME_FILE.tmp" && mv -f "$TERMINAL_THEME_FILE.tmp" "$TERMINAL_THEME_FILE" || exit 1
    rm -f "$TERMINAL_PREFER_ALT_FLAG" "$TERMINAL_PREFER_ALT_V2_FLAG" "$TERMINAL_PREFER_ALT_V3_FLAG" || exit 1
    echo ":: terminal: wearing the ${use_theme} theme from now on"
    running=$(current_shell) || exit 0
    exec "$0" "$running"
    ;;
  *)
    usage
    exit "$EXIT_USAGE"
    ;;
esac

# ── Refresh ──────────────────────────────────────────────────────────────────
# Re-render only what is worn: a link into the render tree names its template.
if [ "$refresh" = 1 ]; then
  shell_name=$(current_shell) || exit 0
  status=0
  for link in "$STARSHIP_LINK" "$FASTFETCH_LINK"; do
    worn=$(readlink -m "$link")
    case "$worn" in "$TERMINAL_RENDER_DIR"/*) ;; *) continue ;; esac
    rel="${worn#"$TERMINAL_RENDER_DIR"/}"
    render_shell=""
    case "$rel" in
      theme/*) rel="${rel#theme/}"; template="$TERMINAL_THEMES_DIR/$rel"; render_shell="$shell_name" ;;
      main/*) rel="${rel#main/}"; template="$TERMINAL_DOTFILES_DIR/$rel" ;;
      alt-v3/*) rel="${rel#alt-v3/}"; template="$TERMINAL_DOTFILES_DIR/_alt-v3/$rel" ;;
      alt-v2/*) rel="${rel#alt-v2/}"; template="$TERMINAL_DOTFILES_DIR/_alt-v2/$rel" ;;
      alt/*) rel="${rel#alt/}"; template="$TERMINAL_DOTFILES_DIR/_alt/$rel" ;;
      *) continue ;;
    esac
    [ -e "$template" ] || continue
    # A theme belongs to no shell; it wears the running shell's palette.
    terminal_render "${render_shell:-${rel%%/*}}" "$template" >/dev/null || status=1
  done
  exit "$status"
fi

shell_name="${1:-}"
if ! printf '%s\n' "${KNOWN[@]}" | grep -qx -- "$shell_name"; then
  usage
  exit "$EXIT_USAGE"
fi

# ── Apply ────────────────────────────────────────────────────────────────────
status=0
link_tool() {
  local tool="$1" dst="$2" src target policy=backup
  if ! src=$(terminal_source "$tool" "$shell_name"); then
    echo "!! $tool: no config found for $shell_name — leaving ${dst/#$HOME/\~} as is" >&2
    status=1
    return 0
  fi
  target=$(terminal_target "$tool" "$shell_name")
  if [ "$dry_run" = 1 ]; then
    if terminal_is_template "$src"; then
      echo "would render ${src#"$TERMINAL_DOTFILES_DIR"/} with $shell_name's palette"
    fi
    echo "would link ${dst/#$HOME/\~} -> $target"
    return 0
  fi
  if terminal_is_template "$src"; then
    terminal_render "$shell_name" "$src" || { status=1; return 0; }
  elif [ "$tool" = fastfetch ]; then
    terminal_compose_fastfetch "$shell_name" || { status=1; return 0; }
  fi
  [ -L "$dst" ] && policy=force
  ensure_symlink "$target" "$dst" "$policy" || status=1
}

link_tool starship "$STARSHIP_LINK"
link_tool fastfetch "$FASTFETCH_LINK"
exit "$status"
