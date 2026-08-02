#!/bin/bash
# Update the ml4w shell: pulls latest from mylinuxforwork/dotfiles (main) and
# refreshes the seeded ~/.config/ml4w defaults without clobbering user edits.
#
# The quickshell config updates for free through the symlink
# (~/.config/quickshell/ml4w -> checkout dotfiles/.config/quickshell).
# ~/.config/ml4w is a seeded COPY, so it is refreshed here: subfolders marked
# PROTECTED (ml4w's mechanism — an empty PROTECTED file in the folder) and any
# existing file are left untouched (cp -rn = no-clobber), so new upstream
# defaults appear while your edits survive. ~/.config/matugen-ml4w is a dcli
# dotfile and needs no refresh.
set -euo pipefail

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

REPO_DIR="$REAL_HOME/.local/share/ml4w-dotfiles"
SRC="$REPO_DIR/dotfiles/.config/ml4w"
DST="$REAL_HOME/.config/ml4w"

as_user() {
    if [ "$(id -u)" -eq 0 ] && [ "$REAL_USER" != "root" ]; then
        sudo -u "$REAL_USER" -H "$@"
    else
        "$@"
    fi
}

if [ ! -d "$REPO_DIR/.git" ]; then
    echo "!! ml4w-dotfiles not found at $REPO_DIR — run setup-ml4w.sh first" >&2
    exit 1
fi

echo ":: Updating ml4w-dotfiles (main branch)"
as_user git -C "$REPO_DIR" pull --ff-only

# Refresh seeded defaults (PROTECTED subfolders and existing files survive).
if [ -d "$DST" ]; then
    for d in "$SRC"/*/; do
        [ -d "$d" ] || continue
        base=$(basename "$d")
        if [ -f "$DST/$base/PROTECTED" ]; then
            echo ":: skip $base (PROTECTED)"
        else
            as_user cp -rn "$d" "$DST/"
        fi
    done
    for f in "$SRC"/*; do
        [ -f "$f" ] || continue
        as_user cp -n "$f" "$DST/"
    done
else
    echo "!! $DST missing — run setup-ml4w.sh first" >&2
    exit 1
fi

echo ":: ml4w shell updated — restart shell with switch-shell.sh ml4w"
