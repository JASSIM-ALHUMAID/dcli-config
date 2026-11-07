#!/bin/bash
# Render a terminal-theme variant for every registry shell into a throw-away
# tree and print the starship prompt + fastfetch greeting for review. The live
# ~/.config/starship.toml and ~/.config/fastfetch links are never touched.
#
# Usage:
#   preview-terminal-themes.sh [--variant main|alt|alt-v2|alt-v3] [shell...]
#   preview-terminal-themes.sh --help
#
# Defaults to every registry shell in picker order, wearing alt-v2 with each
# shell's live palette. `main`/`alt` show the matching template where one
# exists; upstream-only configs are reported as not previewable, not guessed.
set -euo pipefail

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
REPO_DIR=$(dirname "$SCRIPT_DIR")

# ── Constants ────────────────────────────────────────────────────────────────
PREVIEW_WIDTH=100
PREVIEW_CMD_MS=5000
PREVIEW_STATE=$(mktemp -d "${TMPDIR:-/tmp}/dcli-terminal-preview.XXXXXX") || exit 1
trap 'rm -rf "$PREVIEW_STATE"' EXIT
export TERMINAL_STATE_DIR="$PREVIEW_STATE"

BOLD=$'\033[1m'
DIM=$'\033[2m'
RESET=$'\033[0m'

# ── Libraries ────────────────────────────────────────────────────────────────
# shellcheck source=lib/shell-common.sh disable=SC1091
. "$SCRIPT_DIR/lib/shell-common.sh" || exit 1
# shellcheck source=lib/wallpaper.sh disable=SC1091
. "$SCRIPT_DIR/lib/wallpaper.sh" || exit 1
# shellcheck source=lib/palette.sh disable=SC1091
. "$SCRIPT_DIR/lib/palette.sh" || exit 1
# shellcheck source=lib/terminal-theme.sh disable=SC1091
. "$SCRIPT_DIR/lib/terminal-theme.sh" || exit 1

usage() {
    cat <<EOF
usage: preview-terminal-themes.sh [--variant main|alt|alt-v2|alt-v3] [shell...]

Renders each shell's prompt and greeting into a temporary directory and prints
them for review. No live symlink is changed.

  --variant main|alt|alt-v2|alt-v3   layer to preview (default: alt-v2)
  --help                      show this text

With no shell names, every registry shell is shown in picker order.
EOF
}

hex_rgb() {
    local hex=${1#\#}
    printf '%d;%d;%d' "$((16#${hex:0:2}))" "$((16#${hex:2:2}))" "$((16#${hex:4:2}))"
}

# ── Arguments ────────────────────────────────────────────────────────────────
variant=alt-v2
while [ $# -gt 0 ]; do
    case "$1" in
        --variant)
            [ $# -ge 2 ] || { usage >&2; exit 2; }
            variant=$2
            shift 2
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
        -*)
            echo "preview-terminal-themes: unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
        *)
            break
            ;;
    esac
done

case "$variant" in
    main | alt | alt-v2 | alt-v3) ;;
    *)
        echo "preview-terminal-themes: unknown variant: $variant" >&2
        usage >&2
        exit 2
        ;;
esac

load_registry || exit 1
if [ $# -gt 0 ]; then
    shells=("$@")
else
    shells=("${KNOWN[@]}")
fi
for shell in "${shells[@]}"; do
    printf '%s\n' "${KNOWN[@]}" | grep -qx -- "$shell" || {
        echo "preview-terminal-themes: unknown shell: $shell" >&2
        exit 2
    }
done

have_starship=0
have_fastfetch=0
command -v starship >/dev/null 2>&1 && have_starship=1
command -v fastfetch >/dev/null 2>&1 && have_fastfetch=1
if [ "$have_starship" = 0 ] && [ "$have_fastfetch" = 0 ]; then
    echo "preview-terminal-themes: neither starship nor fastfetch is installed" >&2
    exit 1
fi

# ── Preview ──────────────────────────────────────────────────────────────────
previewed=0
status=0

for shell in "${shells[@]}"; do
    case "$variant" in
        main) src="$TERMINAL_DOTFILES_DIR/$shell" ;;
        alt) src="$TERMINAL_DOTFILES_DIR/_alt/$shell" ;;
        alt-v2) src="$TERMINAL_DOTFILES_DIR/_alt-v2/$shell" ;;
        alt-v3) src="$TERMINAL_DOTFILES_DIR/_alt-v3/$shell" ;;
    esac
    starship_src="$src/starship.toml"
    # alt-v3 is a greeting-only layer; its prompt is alt-v2's.
    [ "$variant" = alt-v3 ] && starship_src="$TERMINAL_DOTFILES_DIR/_alt-v2/$shell/starship.toml"
    fastfetch_src="$src/fastfetch"

    if [ ! -e "$starship_src" ] && [ ! -d "$fastfetch_src" ]; then
        printf '\n%s%s%s  %s· no %s template%s\n' "$BOLD" "$shell" "$RESET" "$DIM" "$variant" "$RESET"
        continue
    fi

    blurb=""
    for record in "${SHELL_RECORDS[@]}"; do
        [ "${record%%|*}" = "$shell" ] && blurb=${record##*|}
    done
    palette=$(palette_for "$shell" "$(shell_wallpaper "$shell")")
    primary=$(jq -r '.primary' <<<"$palette")
    secondary=$(jq -r '.secondary' <<<"$palette")
    tertiary=$(jq -r '.tertiary' <<<"$palette")

    printf '\n\033[1;38;2;%sm▌\033[0m %s%s%s %s· %s · %s%s\n' \
        "$(hex_rgb "$primary")" "$BOLD" "$shell" "$RESET" "$DIM" "$variant" "$blurb" "$RESET"
    printf '%s  palette  %s  %s  %s%s\n\n' \
        "$DIM" "$primary" "$secondary" "$tertiary" "$RESET"

    rendered_any=0
    if [ -f "$starship_src" ]; then
        if terminal_render "$shell" "$starship_src"; then
            rendered_any=1
            if [ "$have_starship" = 1 ]; then
                starship_rendered=$(terminal_rendered_path "$starship_src")
                printf '%s  starship%s\n\n' "$DIM" "$RESET"
                starship_out=""
                if ! starship_out=$(env -u STARSHIP_SHELL STARSHIP_CONFIG="$starship_rendered" \
                    starship prompt --path "$REPO_DIR" --terminal-width "$PREVIEW_WIDTH" \
                    --status 0 --cmd-duration "$PREVIEW_CMD_MS" 2>&1 | sed 's/^/  /'); then
                    echo "!! starship failed for $shell ($variant)" >&2
                    status=1
                fi
                printf '%s\n\n' "$starship_out"
            else
                printf '%s  starship not installed%s\n\n' "$DIM" "$RESET"
            fi
        else
            echo "!! starship render failed for $shell ($variant)" >&2
            status=1
        fi
    fi

    if [ -d "$fastfetch_src" ]; then
        if terminal_render "$shell" "$fastfetch_src"; then
            rendered_any=1
            if [ "$have_fastfetch" = 1 ]; then
                fastfetch_rendered=$(terminal_rendered_path "$fastfetch_src")
                ff_args=(-c "$fastfetch_rendered/config.jsonc")
                if ! grep -qE '"logo"[[:space:]]*:[[:space:]]*(null|\{[[:space:]]*"type"[[:space:]]*:[[:space:]]*"none")' \
                    "$fastfetch_rendered/config.jsonc"; then
                    logo_file=""
                    for candidate in logo.png logo.txt; do
                        [ -f "$fastfetch_rendered/$candidate" ] && { logo_file="$fastfetch_rendered/$candidate"; break; }
                    done
                    if [ -n "$logo_file" ]; then
                        ff_args+=(--logo "$logo_file")
                    else
                        echo "!! missing logo (logo.png or logo.txt) for $shell ($variant)" >&2
                        status=1
                    fi
                fi
                printf '%s  fastfetch%s\n\n' "$DIM" "$RESET"
                # Not captured: an image logo needs the real tty.
                if ! fastfetch "${ff_args[@]}"; then
                    echo "!! fastfetch failed for $shell ($variant)" >&2
                    status=1
                fi
                printf '\n'
            else
                printf '%s  fastfetch not installed%s\n\n' "$DIM" "$RESET"
            fi
        else
            echo "!! fastfetch render failed for $shell ($variant)" >&2
            status=1
        fi
    fi

    [ "$rendered_any" = 1 ] && previewed=$((previewed + 1))
done

[ "$previewed" -eq 0 ] && printf '\n'
printf '%s%s shell(s) · %s%s\n' "$DIM" "$previewed" "$variant" "$RESET"
exit "$status"
