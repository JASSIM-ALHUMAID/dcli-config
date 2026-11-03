#!/bin/bash
# Per-shell prompt (starship) and system-info (fastfetch) configs. Sourced by
# apply-terminal-theme.sh, doctor.sh and tests/smoke.sh — one home for "which
# file does shell X wear", so the three never disagree.
#
# Resolution order, per shell and per tool:
#   1. dotfiles/terminal/<shell>/{starship.toml,fastfetch/}  — ours, committed
#   2. the shell's own upstream copy, read in place from its checkout so
#      update-shells.sh keeps it current
# Every shell now has its own config in (1); the upstream copy stays one flag
# away: TERMINAL_PREFER_UPSTREAM=1 (apply-terminal-theme.sh --upstream) skips (1)
# until the next switch, and deleting a shell's dotfiles/terminal/<shell>/ file
# makes upstream the default again.
# Sourced, never executed: callers own `set -euo pipefail`.

TERMINAL_LIB_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
TERMINAL_DOTFILES_DIR="${TERMINAL_DOTFILES_DIR:-$(readlink -f "$TERMINAL_LIB_DIR/../../dotfiles/terminal")}"

# Links the switcher owns. Fish reads both on every prompt / greeting. Read by
# the sourcing scripts, which shellcheck cannot see.
# shellcheck disable=SC2034
STARSHIP_LINK="$HOME/.config/starship.toml"
# shellcheck disable=SC2034
FASTFETCH_LINK="$HOME/.config/fastfetch"

# ── Upstream locations ───────────────────────────────────────────────────────
# end4pc has no starship of its own; it is a remix of end4, which does.
declare -A UPSTREAM_STARSHIP=(
  [caelestia]="$HOME/.local/share/caelestia/starship.toml"
  [end4]="$HOME/.local/share/dots-hyprland/dots/.config/starship.toml"
  [end4pc]="$HOME/.local/share/dots-hyprland/dots/.config/starship.toml"
  [omarchy]="$HOME/.local/share/omarchy/config/starship.toml"
  [glyph]="$HOME/.local/share/glyph-rice/config/quickshell/glyph/term/starship.toml"
  [ryoku]="$HOME/.local/share/ryoku-shell/ryoku/apps/starship/starship.toml"
)
declare -A UPSTREAM_FASTFETCH=(
  [caelestia]="$HOME/.local/share/caelestia/fastfetch"
  [omarchy]="$HOME/.local/share/omarchy/etc/fastfetch"
  [glyph]="$HOME/.local/share/glyph-rice/config/quickshell/glyph/term/fastfetch"
  [ryoku]="$HOME/.local/share/ryoku-shell/ryoku/apps/fastfetch"
)

# Files an upstream fastfetch config references but its checkout keeps elsewhere
# ("name=source" per entry). ryoku's installer drops the emblem into
# ~/.config/fastfetch itself; with the directory now shared that never happens,
# and kitty-direct renders nothing for a missing image.
declare -A UPSTREAM_FASTFETCH_EXTRAS=(
  [ryoku]="fastfetch-emblem.png=$HOME/.local/share/ryoku-shell/ryoku/assets/brand/fastfetch-emblem.png"
)

# Where composed fastfetch directories live (gitignored with the rest of state/).
TERMINAL_STATE_DIR="${TERMINAL_STATE_DIR:-$(readlink -f "$TERMINAL_LIB_DIR/../../state")/terminal}"

# ── Resolver ─────────────────────────────────────────────────────────────────
# terminal_source <starship|fastfetch> <shell>: prints the path to link and
# returns 0, or returns 1 when no candidate exists (checkout not installed yet).
terminal_source() {
  local tool="$1" shell="$2" ours upstream prefer_ours=1
  [ "${TERMINAL_PREFER_UPSTREAM:-0}" = 1 ] && prefer_ours=0
  if [ "$tool" = starship ]; then
    ours="$TERMINAL_DOTFILES_DIR/$shell/starship.toml"
    upstream="${UPSTREAM_STARSHIP[$shell]:-}"
    [ "$prefer_ours" = 1 ] && [ -f "$ours" ] && { echo "$ours"; return 0; }
    [ -n "$upstream" ] && [ -f "$upstream" ] && { echo "$upstream"; return 0; }
  else
    ours="$TERMINAL_DOTFILES_DIR/$shell/fastfetch"
    upstream="${UPSTREAM_FASTFETCH[$shell]:-}"
    [ "$prefer_ours" = 1 ] && [ -f "$ours/config.jsonc" ] && { echo "$ours"; return 0; }
    if [ -n "$upstream" ] && [ -f "$upstream/config.jsonc" ]; then
      # Extras need a composed directory; terminal_compose_fastfetch fills it.
      if [ -n "${UPSTREAM_FASTFETCH_EXTRAS[$shell]:-}" ]; then
        echo "$TERMINAL_STATE_DIR/fastfetch/$shell"
      else
        echo "$upstream"
      fi
      return 0
    fi
  fi
  # --upstream on a shell with no upstream copy (ambxst, dms, ...) keeps ours.
  [ -f "$ours" ] && { echo "$ours"; return 0; }
  [ -f "$ours/config.jsonc" ] && { echo "$ours"; return 0; }
  return 1
}

# ── Composition ──────────────────────────────────────────────────────────────
# terminal_compose_fastfetch <shell>: for a shell with extras, rebuild its
# directory as symlinks to every upstream file plus the extras, so the checkout
# is never written to by us. Rebuilt on each call, so files added upstream by an
# update appear. No-op for shells without extras. Returns 1 on a missing extra.
terminal_compose_fastfetch() {
  local shell="$1" upstream="${UPSTREAM_FASTFETCH[$1]:-}" dir entry name src f
  [ -n "${UPSTREAM_FASTFETCH_EXTRAS[$shell]:-}" ] || return 0
  dir="$TERMINAL_STATE_DIR/fastfetch/$shell"
  rm -rf "$dir" && mkdir -p "$dir" || return 1
  for f in "$upstream"/*; do
    [ -e "$f" ] && ln -s "$f" "$dir/${f##*/}"
  done
  for entry in ${UPSTREAM_FASTFETCH_EXTRAS[$shell]}; do
    name="${entry%%=*}"
    src="${entry#*=}"
    if [ ! -e "$src" ]; then
      echo "!! fastfetch extra for $shell missing: $src" >&2
      return 1
    fi
    ln -sf "$src" "$dir/$name"
  done
}
