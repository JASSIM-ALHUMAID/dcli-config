#!/bin/bash
# Point ~/.config/starship.toml and ~/.config/fastfetch at the given shell's
# prompt and system-info configs (resolution and rendering: lib/terminal-theme.sh).
# Called by switch-shell.sh on every shell change; also runnable by hand:
#   apply-terminal-theme.sh [--dry-run] [--alt] <shell>
#   apply-terminal-theme.sh --refresh
#   apply-terminal-theme.sh --use alt|upstream
# --alt wears the opt-in alternates in dotfiles/terminal/_alt/<shell>/ until the
# next switch (a shell without one keeps its normal config). --use alt makes that
# the standing choice for every shell and every switch; --use upstream ends it.
# Either --use re-applies the running shell straight away.
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

dry_run=0
refresh=0
use=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) dry_run=1 ;;
    --alt) export TERMINAL_PREFER_ALT=1 ;;
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

# ── Standing choice ──────────────────────────────────────────────────────────
case "$use" in
  "") ;;
  alt | upstream)
    if [ "$use" = alt ]; then
      mkdir -p "$TERMINAL_STATE_DIR" && : >"$TERMINAL_PREFER_ALT_FLAG" || exit 1
    else
      rm -f "$TERMINAL_PREFER_ALT_FLAG" || exit 1
    fi
    echo ":: terminal: wearing the ${use} configs from now on"
    running=$(current_shell) || exit 0
    exec "$0" "$running"
    ;;
  *)
    echo "usage: apply-terminal-theme.sh --use alt|upstream" >&2
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
    case "$rel" in
      main/*) rel="${rel#main/}"; template="$TERMINAL_DOTFILES_DIR/$rel" ;;
      alt/*) rel="${rel#alt/}"; template="$TERMINAL_DOTFILES_DIR/_alt/$rel" ;;
      *) continue ;;
    esac
    [ -e "$template" ] || continue
    terminal_render "${rel%%/*}" "$template" >/dev/null || status=1
  done
  exit "$status"
fi

shell_name="${1:-}"
if ! printf '%s\n' "${KNOWN[@]}" | grep -qx -- "$shell_name"; then
  echo "usage: apply-terminal-theme.sh [--dry-run] [--alt] <${KNOWN[*]// /|}> | --refresh | --use alt|upstream" >&2
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
