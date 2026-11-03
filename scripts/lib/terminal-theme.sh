#!/bin/bash
# Per-shell prompt (starship) and system-info (fastfetch) configs. Sourced by
# apply-terminal-theme.sh, doctor.sh and tests/smoke.sh — one home for "which
# file does shell X wear", so the three never disagree.
#
# Resolution order, per shell and per tool:
#   1. dotfiles/terminal/<shell>/{starship.toml,fastfetch/}  — ours, committed,
#      only for shells that ship no config of their own
#   2. the shell's own upstream copy, read in place from its checkout so
#      update-shells.sh keeps it current
# dotfiles/terminal/_alt/<shell>/ holds opt-in alternates for the upstream
# shells; TERMINAL_PREFER_ALT=1 (apply-terminal-theme.sh --alt, one switch) or
# the persistent state/terminal/prefer-alt flag (--use alt) puts them first.
#
# Ours are TEMPLATES, never linked directly: most of these shells are Material
# You and recolour themselves from the wallpaper, so {{key}} (#rrggbb) and
# {{key.rgb}} (r;g;b, for fastfetch's 38;2;… codes) are filled from the shell's
# live palette (lib/palette.sh) into state/terminal/render/, which is linked.
# Sourced after lib/wallpaper.sh and lib/palette.sh; callers own `set -euo pipefail`.

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

# Where composed and rendered configs live (gitignored with the rest of state/).
TERMINAL_STATE_DIR="${TERMINAL_STATE_DIR:-$(readlink -f "$TERMINAL_LIB_DIR/../../state")/terminal}"
TERMINAL_RENDER_DIR="$TERMINAL_STATE_DIR/render"
TERMINAL_PREFER_ALT_FLAG="$TERMINAL_STATE_DIR/prefer-alt"

terminal_prefers_alt() { [ "${TERMINAL_PREFER_ALT:-0}" = 1 ] || [ -e "$TERMINAL_PREFER_ALT_FLAG" ]; }

# ── Resolver ─────────────────────────────────────────────────────────────────
# terminal_source <starship|fastfetch> <shell>: prints the path to link and
# returns 0, or returns 1 when no candidate exists (checkout not installed yet).
terminal_source() {
  local tool="$1" shell="$2" ours upstream alt="$TERMINAL_DOTFILES_DIR/_alt/$2"
  if terminal_prefers_alt; then
    [ "$tool" = starship ] && [ -f "$alt/starship.toml" ] && { echo "$alt/starship.toml"; return 0; }
    [ "$tool" = fastfetch ] && [ -f "$alt/fastfetch/config.jsonc" ] && { echo "$alt/fastfetch"; return 0; }
  fi
  if [ "$tool" = starship ]; then
    ours="$TERMINAL_DOTFILES_DIR/$shell/starship.toml"
    upstream="${UPSTREAM_STARSHIP[$shell]:-}"
    [ -f "$ours" ] && { echo "$ours"; return 0; }
    [ -n "$upstream" ] && [ -f "$upstream" ] && { echo "$upstream"; return 0; }
  else
    ours="$TERMINAL_DOTFILES_DIR/$shell/fastfetch"
    upstream="${UPSTREAM_FASTFETCH[$shell]:-}"
    [ -f "$ours/config.jsonc" ] && { echo "$ours"; return 0; }
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

# ── Templates ────────────────────────────────────────────────────────────────
# A source under dotfiles/terminal/ is a template; its rendered twin keeps the
# variant (main | alt) in the path, so --refresh can tell which one is worn.
terminal_is_template() { case "$1" in "$TERMINAL_DOTFILES_DIR"/*) return 0 ;; *) return 1 ;; esac; }

terminal_rendered_path() { # <template path> -> its rendered twin
  local rel="${1#"$TERMINAL_DOTFILES_DIR"/}" variant=main
  case "$rel" in _alt/*) variant=alt; rel="${rel#_alt/}" ;; esac
  echo "$TERMINAL_RENDER_DIR/$variant/$rel"
}

# terminal_target <tool> <shell>: what the link should point at.
terminal_target() {
  local src
  src=$(terminal_source "$1" "$2") || return 1
  if terminal_is_template "$src"; then terminal_rendered_path "$src"; else echo "$src"; fi
}

# terminal_render <shell> <template path>: fill the template (file or fastfetch
# directory) from the shell's palette into its rendered twin. Skipped when the
# palette and template are unchanged since the last render (a cheap signature),
# so --refresh can run on every terminal start. Atomic: a reader never sees a
# half-written config, and an unfilled {{token}} fails the render instead of
# shipping it.
terminal_render() {
  local shell="$1" src="$2" out palette sig tmp k v hex f
  local -a sed_args=()
  out=$(terminal_rendered_path "$src")
  palette=$(palette_for "$shell" "$(shell_wallpaper "$shell")")
  sig=$( { echo "$palette"; find "$src" -type f -exec cat {} +; } | sha256sum | cut -c1-32)
  [ -e "$out" ] && [ "$(cat "$out.sig" 2>/dev/null)" = "$sig" ] && return 0
  while IFS='=' read -r k v; do
    hex=${v#\#}
    sed_args+=(-e "s/{{$k}}/$v/g" -e "s/{{$k.rgb}}/$((16#${hex:0:2}));$((16#${hex:2:2}));$((16#${hex:4:2}))/g")
  done < <(jq -r 'to_entries[] | "\(.key)=\(.value)"' <<<"$palette")
  mkdir -p "$(dirname "$out")" || return 1
  tmp="$out.tmp"
  rm -rf "$tmp"
  if [ -d "$src" ]; then
    cp -r "$src" "$tmp" || return 1
    for f in "$tmp"/*; do [ -f "$f" ] && sed -i "${sed_args[@]}" "$f"; done
  else
    sed "${sed_args[@]}" "$src" >"$tmp" || return 1
  fi
  if grep -rqE '\{\{[a-zA-Z.]+\}\}' "$tmp"; then
    echo "!! $shell: unknown palette token in ${src#"$TERMINAL_DOTFILES_DIR"/}: $(grep -rhoE '\{\{[a-zA-Z.]+\}\}' "$tmp" | sort -u | tr '\n' ' ')" >&2
    rm -rf "$tmp"
    return 1
  fi
  rm -rf "$out" && mv -T "$tmp" "$out" || return 1
  echo "$sig" >"$out.sig"
}
