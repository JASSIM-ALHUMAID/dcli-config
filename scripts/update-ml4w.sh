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
SB_OVERRIDE="$REAL_HOME/.config/ml4w-statusbar/statusbar.json"
SB_FALLBACK="$DST/settings/statusbar.json"
SB_MARKER="$REAL_HOME/.config/ml4w-statusbar/.dcli-bar-enabled-repair"
OVERVIEW_DIR="$REAL_HOME/.config/ml4w-overview"
ROFI_DIR="$REAL_HOME/.config/rofi"
SETTINGS_SRC="$REAL_HOME/.local/share/ml4w-dotfiles-settings-src"

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

# Refresh the other seeded copies the same no-clobber way. Both exist as real
# dirs rather than checkout symlinks because matugen writes generated files into
# them (rofi/colors.rasi, ml4w-overview/common/Appearance.colors.qml) and those
# paths are tracked in the checkout — see setup-ml4w.sh.
if [ -d "$OVERVIEW_DIR" ]; then
    as_user cp -rn "$SRC/../quickshell/overview/." "$OVERVIEW_DIR/" 2>/dev/null || true
fi
if [ -d "$ROFI_DIR" ]; then
    as_user cp -rn "$SRC/../rofi/." "$ROFI_DIR/" 2>/dev/null || true
fi

# The settings app is its own upstream repo, pulled and reinstalled here so a
# dcli update keeps it in step with the shell that toggles it.
if [ -d "$SETTINGS_SRC/.git" ]; then
    echo ":: Updating ml4w-dotfiles-settings"
    as_user git -C "$SETTINGS_SRC" pull --ff-only
    as_user make -C "$SETTINGS_SRC" install >/dev/null
fi

# One-time repair for installs seeded before the setup hook wrote the statusbar
# override with "enabled": true. shell-ml4w's hook_behavior is `once`, so the
# setup fix never reaches an existing machine — this does.
#
# Guarded by a marker so it runs exactly once: after the repair the flag is the
# user's to own (SUPER + CTRL + B / the SidebarApp switch persist into this same
# file), and a repair on every update would fight a deliberate toggle-off.
if [ -f "$SB_MARKER" ]; then
    : # already repaired
else
    if [ -f "$SB_OVERRIDE" ] && grep -qE '"enabled"[[:space:]]*:[[:space:]]*false' "$SB_OVERRIDE"; then
        as_user sed -i -E 's/("enabled"[[:space:]]*:[[:space:]]*)false/\1true/' "$SB_OVERRIDE"
        echo ":: Repaired $SB_OVERRIDE — statusbar enabled (no waybar fallback here)"
    fi
    as_user mkdir -p "$(dirname "$SB_MARKER")"
    as_user touch "$SB_MARKER"
fi

# The StatusbarApp's parser tolerates /* */ blocks and trailing commas but not
# `#` comments, and a hand-edited fallback that fails to parse is silently
# ignored (built-in defaults take over). Strip them so the file stays usable if
# the override is ever removed.
if [ -f "$SB_FALLBACK" ] && grep -qE '^[[:space:]]*#' "$SB_FALLBACK"; then
    as_user sed -i -E '/^[[:space:]]*#/d' "$SB_FALLBACK"
    echo ":: Stripped '#' comment lines from $SB_FALLBACK (invalid JSON)"
fi

echo ":: ml4w shell updated — restart shell with switch-shell.sh ml4w"
