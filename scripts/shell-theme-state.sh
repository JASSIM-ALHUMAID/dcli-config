#!/bin/bash
# Per-shell snapshot/restore of the SHARED application theming surface.
#
# Usage: shell-theme-state.sh save|restore <shell>
#
# WHY
#
# Each shell owns its own config cleanly (dotfiles/<shell>, ~/.config/<shell>,
# its own matugen config). What no shell owns is the config of the programs it
# re-themes on the way past: GTK, Qt, the cursor, Thunar's colours, rofi. Those
# are ONE global copy with six writers:
#
#   gtk-{3,4}.0/gtk.css      caelestia, ambxst, end4, end4pc
#   gtk-{3,4}.0/settings.ini caelestia, end4pc, dms, ml4w
#   gsettings interface keys caelestia, ambxst, end4, end4pc, omarchy, dms
#   qt5ct / qt6ct            ambxst, dms, end4pc
#   gtk-{3,4}.0/thunar.css   caelestia (imported from gtk.css)
#   gtk-{3,4}.0/nautilus.css caelestia (imported from gtk.css)
#
# switch-shell.sh handled processes only, so the desktop kept whichever look the
# LAST shell to run its theme pipeline had left — usually the login shell, for
# the rest of the session. This script gives each shell its own copy of that
# surface: saved when you switch away, replayed when you switch back.
#
# STORE
#
# state/shell-theme/<shell>/ — state/.gitignore is `*`, so snapshots never
# enter git. Layout:
#   manifest       one line per managed path: "P <rel>" present, "A <rel>" absent
#   gsettings.txt  "<key>\t<value>" lines
#   files/<rel>    the mirrored tree
#
# The manifest is written LAST and is what restore keys off, so a snapshot
# interrupted half way is simply ignored rather than half-applied.
#
# RULES THAT MATTER
#
# 1. A missing snapshot is a no-op, never a reset. The first visit to a shell
#    saves; only the second one restores. Restoring an empty snapshot would
#    blank the desktop.
# 2. Absence is recorded, not just presence. If ambxst wrote a gtk.css and xenon
#    never does, restoring xenon must DELETE it — otherwise isolation is
#    one-way and ambxst's palette bleeds forward forever. Deletion is limited
#    strictly to the managed set.
# 3. Nothing tracked in a git repo is ever written. Several of these paths are
#    symlinks into dcli; hyprlock/colors.conf resolves there but is gitignored,
#    which is fine. fuzzel/fuzzel_theme.ini is deliberately NOT managed: it is a
#    committed seed (see .gitignore), so restoring it would dirty the tree on
#    every switch. The guard below enforces this for anything added later.
#
# Called from scripts/switch-shell.sh. Set DCLI_SKIP_THEME_STATE=1 to bypass.
set -u

REPO_DIR="${DCLI_DIR:-$HOME/.config/dcli}"
STORE_ROOT="$REPO_DIR/state/shell-theme"

# Managed single files, relative to $HOME.
MANAGED_FILES=(
    .config/gtk-3.0/gtk.css
    .config/gtk-3.0/settings.ini
    .config/gtk-3.0/thunar.css
    .config/gtk-3.0/nautilus.css
    .config/gtk-3.0/dank-colors.css
    .config/gtk-4.0/gtk.css
    .config/gtk-4.0/settings.ini
    .config/gtk-4.0/thunar.css
    .config/gtk-4.0/nautilus.css
    .config/gtk-4.0/dank-colors.css
    .gtkrc-2.0
    .icons/default/index.theme
    .config/hypr/hyprlock/colors.conf
    .config/rofi/colors.rasi
    .config/swaync/style.css
)

# Managed directories, mirrored wholesale (restore deletes what the snapshot
# does not have). Both hold per-shell colour files with shell-specific names —
# ambxst.colors, matugen.conf — so a per-file list would miss new ones.
MANAGED_DIRS=(
    .config/qt5ct
    .config/qt6ct
)

GS_SCHEMA="org.gnome.desktop.interface"
GS_KEYS=(gtk-theme icon-theme color-scheme cursor-theme cursor-size font-name text-scaling-factor)

log() { printf '%s\n' "$*" >&2; }

# Refuse to write anything tracked in a git repo — see rule 3. Resolves the
# PARENT, because the file itself may legitimately not exist yet.
is_writable_target() {
    local rel="$1" abs parent resolved top
    abs="$HOME/$rel"
    parent=$(dirname "$abs")
    resolved=$(readlink -f "$parent" 2>/dev/null) || return 0
    [ -n "$resolved" ] || return 0

    case "$resolved/" in
    "$HOME"/*) ;;
    *)
        log ":: theme-state: skip $rel (resolves outside \$HOME: $resolved)"
        return 1
        ;;
    esac

    top=$(git -C "$resolved" rev-parse --show-toplevel 2>/dev/null) || return 0
    [ -n "$top" ] || return 0
    local inrepo="${resolved#"$top"/}/$(basename "$abs")"
    if git -C "$top" check-ignore -q "$inrepo" 2>/dev/null; then
        return 0 # gitignored — generated output, safe to churn
    fi
    if git -C "$top" ls-files --error-unmatch "$inrepo" >/dev/null 2>&1; then
        log ":: theme-state: skip $rel (tracked in $top)"
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# save
# ---------------------------------------------------------------------------
do_save() {
    local shell="$1"
    local store="$STORE_ROOT/$shell"
    local tmp="$store.tmp.$$"

    rm -rf "$tmp"
    mkdir -p "$tmp/files" || { log ":: theme-state: cannot create $tmp"; return 1; }

    : >"$tmp/manifest.part"

    local rel src
    for rel in "${MANAGED_FILES[@]}"; do
        src="$HOME/$rel"
        if [ -e "$src" ]; then
            mkdir -p "$tmp/files/$(dirname "$rel")"
            # -L: follow symlinks, store the CONTENT. Restoring a symlink would
            # replace the user's link with a copy.
            cp -aL "$src" "$tmp/files/$rel" 2>/dev/null &&
                printf 'P %s\n' "$rel" >>"$tmp/manifest.part" ||
                printf 'A %s\n' "$rel" >>"$tmp/manifest.part"
        else
            printf 'A %s\n' "$rel" >>"$tmp/manifest.part"
        fi
    done

    for rel in "${MANAGED_DIRS[@]}"; do
        src="$HOME/$rel"
        if [ -d "$src" ]; then
            mkdir -p "$tmp/files/$rel"
            cp -aL "$src/." "$tmp/files/$rel/" 2>/dev/null &&
                printf 'D %s\n' "$rel" >>"$tmp/manifest.part" ||
                printf 'A %s\n' "$rel" >>"$tmp/manifest.part"
        else
            printf 'A %s\n' "$rel" >>"$tmp/manifest.part"
        fi
    done

    if command -v gsettings >/dev/null 2>&1; then
        local k v
        : >"$tmp/gsettings.txt"
        for k in "${GS_KEYS[@]}"; do
            v=$(gsettings get "$GS_SCHEMA" "$k" 2>/dev/null) || continue
            [ -n "$v" ] && printf '%s\t%s\n' "$k" "$v" >>"$tmp/gsettings.txt"
        done
    fi

    # Manifest last — this is what makes the snapshot count as complete.
    mv "$tmp/manifest.part" "$tmp/manifest" || { rm -rf "$tmp"; return 1; }
    rm -rf "$store"
    mv "$tmp" "$store" || { rm -rf "$tmp"; return 1; }
    log ":: theme-state: saved $shell"
}

# ---------------------------------------------------------------------------
# restore
# ---------------------------------------------------------------------------
do_restore() {
    local shell="$1"
    local store="$STORE_ROOT/$shell"

    if [ ! -f "$store/manifest" ]; then
        # Rule 1: first visit, or an interrupted save. Leave the desktop alone.
        return 0
    fi

    local kind rel
    while read -r kind rel; do
        [ -n "${rel:-}" ] || continue
        is_writable_target "$rel" || continue
        case "$kind" in
        P)
            if [ -f "$store/files/$rel" ]; then
                mkdir -p "$(dirname "$HOME/$rel")"
                cp -a "$store/files/$rel" "$HOME/$rel" 2>/dev/null ||
                    log ":: theme-state: could not restore $rel"
            fi
            ;;
        D)
            if [ -d "$store/files/$rel" ]; then
                rm -rf "${HOME:?}/$rel"
                mkdir -p "$HOME/$rel"
                cp -a "$store/files/$rel/." "$HOME/$rel/" 2>/dev/null ||
                    log ":: theme-state: could not restore $rel/"
            fi
            ;;
        A)
            # Rule 2: this shell had no such file. Remove whatever the previous
            # shell left, so isolation works in both directions.
            rm -rf "${HOME:?}/$rel"
            ;;
        esac
    done <"$store/manifest"

    if [ -f "$store/gsettings.txt" ] && command -v gsettings >/dev/null 2>&1; then
        local k v
        while IFS=$'\t' read -r k v; do
            [ -n "${v:-}" ] || continue
            gsettings set "$GS_SCHEMA" "$k" "$v" 2>/dev/null ||
                log ":: theme-state: gsettings $k rejected '$v'"
        done <"$store/gsettings.txt"

        # The live Hyprland cursor is separate state from the gsettings key —
        # both have to be set or the pointer keeps the previous shell's theme
        # until relogin. caelestia/end4 each do this from their own execs.lua,
        # which never re-fires on a `hyprctl reload`, i.e. never on a switch.
        local ct cs
        ct=$(awk -F'\t' '$1=="cursor-theme"{print $2}' "$store/gsettings.txt" | tr -d "'")
        cs=$(awk -F'\t' '$1=="cursor-size"{print $2}' "$store/gsettings.txt")
        if [ -n "$ct" ]; then
            hyprctl setcursor "$ct" "${cs:-24}" >/dev/null 2>&1
        fi
    fi

    reassert_thunar_import
    log ":: theme-state: restored $shell"
}

# ambxst's GtkGenerator and end4pc's switchwall.sh `tee` a freshly generated
# gtk.css over the top of whatever was there. caelestia's theme.py writes
# Thunar's palette to a SIBLING file, gtk-3.0/thunar.css, and pulls it in with a
# trailing `@import` in gtk.css — which those two overwrites drop, silently
# un-theming Thunar until caelestia next runs. Re-assert the import instead of
# depending on the order shells happen to run in.
reassert_thunar_import() {
    local d f
    for d in "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0"; do
        [ -f "$d/thunar.css" ] || continue
        f="$d/gtk.css"
        [ -f "$f" ] || continue
        grep -qF '@import "thunar.css"' "$f" && continue
        printf '\n@import "thunar.css";\n' >>"$f" 2>/dev/null &&
            log ":: theme-state: re-added thunar.css import to ${f#"$HOME"/}"
    done
}

# ---------------------------------------------------------------------------

[ "${DCLI_SKIP_THEME_STATE:-0}" = 1 ] && exit 0

verb="${1:-}"
shell="${2:-}"

case "$verb" in
save | restore) ;;
*)
    echo "Usage: $(basename "$0") save|restore <shell>" >&2
    exit 2
    ;;
esac

# "none" is what switch-shell.sh's current_shell() reports before the first
# switch ever runs; there is nothing to snapshot under that name.
if [ -z "$shell" ] || [ "$shell" = none ]; then
    exit 0
fi

case "$shell" in
*/* | .*)
    echo "!! refusing suspicious shell name: $shell" >&2
    exit 2
    ;;
esac

"do_$verb" "$shell"
