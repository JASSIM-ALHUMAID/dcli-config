#!/bin/bash
# Point ~/.config/starship.toml and ~/.config/fastfetch at the given shell's
# prompt and system-info configs (resolution rules: lib/terminal-theme.sh).
# Called by switch-shell.sh on every shell change; also runnable by hand:
#   apply-terminal-theme.sh [--dry-run] <shell>
#
# A symlink is simply retargeted. A real file or directory at either path is
# the user's own and is moved aside to <path>.bak-<timestamp> first, never
# deleted. A shell whose config cannot be found (checkout not installed) leaves
# that link exactly as it was and says so — a switch must never end up with a
# broken prompt.
set -euo pipefail

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
# shellcheck source=lib/shell-common.sh disable=SC1091
. "$SCRIPT_DIR/lib/shell-common.sh" || exit 1
# shellcheck source=lib/hook-common.sh disable=SC1091
. "$SCRIPT_DIR/lib/hook-common.sh" || exit 1
# shellcheck source=lib/terminal-theme.sh disable=SC1091
. "$SCRIPT_DIR/lib/terminal-theme.sh" || exit 1

dry_run=0
if [ "${1:-}" = "--dry-run" ]; then
  dry_run=1
  shift
fi
shell_name="${1:-}"
load_registry || exit 1
if ! printf '%s\n' "${KNOWN[@]}" | grep -qx -- "$shell_name"; then
  echo "usage: apply-terminal-theme.sh [--dry-run] <${KNOWN[*]// /|}>" >&2
  exit 2
fi

status=0
link_tool() {
  local tool="$1" dst="$2" src policy=backup
  if ! src=$(terminal_source "$tool" "$shell_name"); then
    echo "!! $tool: no config found for $shell_name — leaving ${dst/#$HOME/\~} as is" >&2
    status=1
    return 0
  fi
  if [ "$dry_run" = 1 ]; then
    echo "would link ${dst/#$HOME/\~} -> $src"
    return 0
  fi
  if [ "$tool" = fastfetch ] && [ "$dry_run" = 0 ]; then
    terminal_compose_fastfetch "$shell_name" || { status=1; return 0; }
  fi
  [ -L "$dst" ] && policy=force
  ensure_symlink "$src" "$dst" "$policy" || status=1
}

link_tool starship "$STARSHIP_LINK"
link_tool fastfetch "$FASTFETCH_LINK"
exit "$status"
