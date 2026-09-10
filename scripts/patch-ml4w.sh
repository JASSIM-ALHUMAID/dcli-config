#!/bin/bash
# Point ml4w's own scripts at ml4w's matugen config instead of the default one.
#
# Bare `matugen` reads ~/.config/matugen — which on this machine is a symlink
# INTO the end-4 checkout (~/.local/share/dots-hyprland), owned by shell-end4.
# Upstream ml4w calls matugen bare, so setting a wallpaper from ml4w's
# WallpaperApp regenerates END4's theme files: the shared
# hypr/hyprlock/colors.conf, fuzzel/fuzzel_theme.ini and gtk-3.0/gtk.css, plus
# end4's own quickshell colours. One shell silently re-themes another.
#
# docs/shells/ml4w.md called this out as a hazard the house wallpaper flow
# avoids (execs.lua passes -c explicitly). That is only true for the house flow;
# the shell's own UI still reaches the unpatched scripts. This closes it.
#
# The rewrites are plain literal-string seds rather than context diffs, because
# sed survives upstream churn: a `git pull` that moves these lines around still
# leaves the strings intact. Every substitution normalises back to the upstream
# form first, so re-running this script is a no-op.
#
# NOTE the target is ~/.config/ml4w, a seeded REAL dir, not the checkout — see
# docs/shells/ml4w.md. update-ml4w.sh refreshes it with `cp -rn`/`cp -n`
# (no-clobber), so a patched file survives an update; this script is re-run
# afterwards anyway to catch files that were newly seeded.
#
# Run by scripts/setup-ml4w.sh (after seeding) and scripts/update-ml4w.sh
# (after every pull). Safe to run by hand at any time.
set -euo pipefail

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

ML4W_DIR="$REAL_HOME/.config/ml4w"
MATUGEN_CONF='"$HOME/.config/matugen-ml4w/config.toml"'

as_user() {
    if [ "$(id -u)" -eq 0 ] && [ "$REAL_USER" != "root" ]; then
        sudo -u "$REAL_USER" -H "$@"
    else
        "$@"
    fi
}

if [ ! -d "$ML4W_DIR" ]; then
    echo "!! ml4w config not found at $ML4W_DIR — run setup-ml4w.sh first" >&2
    exit 1
fi

changed=0

# rewrite <required|optional> <relative-path> <expected-string-after> <sed-expr>...
#
# Applies the sed expressions, then asserts the result actually contains the
# string we were aiming for. A missing assertion means upstream renamed or moved
# something and the rewrite silently did nothing — which would look like ml4w
# "just quietly trashing end4's theme" again, so fail loudly instead.
#
# `optional` downgrades a missing file to a skip: the listener below is not
# seeded on every install, and its absence is not an error.
rewrite() {
    local mode="$1"; shift
    local rel="$1"; shift
    local expect="$1"; shift
    local path="$ML4W_DIR/$rel"

    if [ ! -f "$path" ]; then
        if [ "$mode" = optional ]; then
            echo ":: skip $rel (not installed)"
            return 0
        fi
        echo "!! expected file missing: $rel — upstream layout changed" >&2
        exit 1
    fi

    local before after
    before=$(cat "$path")
    local args=()
    for expr in "$@"; do args+=(-e "$expr"); done
    after=$(printf '%s' "$before" | sed "${args[@]}")

    if ! printf '%s' "$after" | grep -qF "$expect"; then
        echo "!! rewrite of $rel did not produce '$expect' — upstream changed" >&2
        exit 1
    fi

    if [ "$before" != "$after" ]; then
        printf '%s\n' "$after" | as_user tee "$path" >/dev/null
        as_user chmod --reference="$path" "$path" 2>/dev/null || true
        echo ":: patched $rel"
        changed=1
    fi
}

# 1) The wallpaper picker. run_matugen() resolves the binary into $bin first
#    (~/.cargo/bin, ~/.local/bin, then PATH), so the call site to rewrite is
#    `"$bin" image`, not `matugen image`.
rewrite required "scripts/ml4w-wallpaper" \
    "\"\$bin\" -c $MATUGEN_CONF image" \
    "s|\"\$bin\" -c $MATUGEN_CONF image|\"\$bin\" image|g" \
    "s|\"\$bin\" image|\"\$bin\" -c $MATUGEN_CONF image|g"

# 2) The light/dark listener. Same call twice (one per mode), via $MATUGEN_BIN.
#    Not started by our execs.lua, but ml4w's settings app can start it.
rewrite optional "listeners/gtk-theme-switcher.sh" \
    "\$MATUGEN_BIN -c $MATUGEN_CONF image" \
    "s|\$MATUGEN_BIN -c $MATUGEN_CONF image|\$MATUGEN_BIN image|g" \
    "s|\$MATUGEN_BIN image|\$MATUGEN_BIN -c $MATUGEN_CONF image|g"

if [ "$changed" -eq 0 ]; then
    echo ":: ml4w scripts already patched — nothing to do"
else
    echo ":: ml4w patched — its wallpaper flow now uses ~/.config/matugen-ml4w"
fi
