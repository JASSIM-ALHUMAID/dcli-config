#!/bin/bash
# Fast-forward every shell checkout in one go.
#
# Usage: update-shells.sh [--status] [name|all]      (default: all)
#   --status   report only: never run an updater, never pull
#
# Shells with their own update-*.sh are updated by delegating to it. The
# caelestia and ambxst forks are development checkouts — they are only ever
# reported on, never pulled. Reporting means branch, dirty-file count and
# ahead/behind of @{u} after a `git fetch`. dms and noctalia are packages, not
# checkouts, so they are not listed. Exits non-zero if any update failed.
set -euo pipefail

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
# shellcheck source=lib/hook-common.sh disable=SC1091
. "$SCRIPT_DIR/lib/hook-common.sh" || exit 1

# ── Registry ─────────────────────────────────────────────────────────────────
# name|checkout|updater. An updater of "-" means report only.
CHECKOUT_RECORDS=(
    "caelestia|${CAELESTIA_DEV:-$REAL_HOME/Projects/shell/real}|-"
    "ambxst|$REAL_HOME/.local/src/ambxst|-"
    "end4|$REAL_HOME/.local/share/dots-hyprland|update-end4.sh"
    "end4pc|$REAL_HOME/.local/share/end4-pC|update-end4pc.sh"
    "omarchy|$REAL_HOME/.local/share/omarchy|update-omarchy.sh"
    "xenon|$REAL_HOME/.local/share/xenon-shell|update-xenon.sh"
    "glyph|$REAL_HOME/.local/share/glyph-rice|update-glyph.sh"
)
# No exemption for end4pc: its fork (my-end4pc) now carries patch-end4pc.sh's
# rewrites as commits, so a dirty tree there is real work — and update-end4pc.sh
# runs `git checkout -- .`, which would silently discard it.
FETCH_TIMEOUT_SEC=30

# ── Status ───────────────────────────────────────────────────────────────────
# Prints one line for the checkout and returns 0; a failed fetch only marks the
# ahead/behind numbers as stale.
report_status() {
    local name="$1" dir="$2" branch dirty counts ahead behind stale=""
    if ! as_user git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
        printf '%-10s not installed (%s)\n' "$name" "$dir"
        return 0
    fi
    as_user env GIT_TERMINAL_PROMPT=0 timeout "$FETCH_TIMEOUT_SEC" \
        git -C "$dir" fetch --quiet >/dev/null 2>&1 || stale=" (fetch failed, may be stale)"
    branch=$(as_user git -C "$dir" rev-parse --abbrev-ref HEAD)
    dirty=$(as_user git -C "$dir" status --porcelain | wc -l)
    if counts=$(as_user git -C "$dir" rev-list --left-right --count 'HEAD...@{u}' 2>/dev/null); then
        read -r ahead behind <<<"$counts"
        printf '%-10s %s  dirty:%s  ahead:%s  behind:%s%s\n' \
            "$name" "$branch" "$dirty" "$ahead" "$behind" "$stale"
    else
        printf '%-10s %s  dirty:%s  (no upstream)%s\n' "$name" "$branch" "$dirty" "$stale"
    fi
}

is_dirty() {
    [ -n "$(as_user git -C "$1" status --porcelain)" ]
}

# ── Update ───────────────────────────────────────────────────────────────────
# Returns 0 if the checkout is now as current as its updater can make it.
update_one() {
    local name="$1" dir="$2" updater="$3"
    if [ "$updater" = "-" ]; then
        echo ":: $name: development fork — reporting only, never pulled"
        return 0
    fi
    if [ ! -d "$dir/.git" ]; then
        echo ":: $name: not installed — run setup-${updater#update-}"
        return 0
    fi
    if is_dirty "$dir"; then
        echo "!! $name: working tree has local changes — refusing to pull" >&2
        return 1
    fi
    echo ":: $name: running $updater"
    bash "$SCRIPT_DIR/$updater"
}

in_list() {
    local want="$1" item
    shift
    for item in "$@"; do [ "$item" = "$want" ] && return 0; done
    return 1
}

# ── Main ─────────────────────────────────────────────────────────────────────
status_only=false
target=all
for arg in "$@"; do
    case "$arg" in
        --status) status_only=true ;;
        -h | --help)
            sed -n '2,11p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        -*)
            echo "!! unknown option: $arg" >&2
            exit 2
            ;;
        *) target="$arg" ;;
    esac
done

names=()
for record in "${CHECKOUT_RECORDS[@]}"; do names+=("${record%%|*}"); done
if [ "$target" != all ] && ! in_list "$target" "${names[@]}"; then
    echo "!! unknown shell '$target' — expected one of: all ${names[*]}" >&2
    exit 2
fi

failures=0
for record in "${CHECKOUT_RECORDS[@]}"; do
    IFS='|' read -r name dir updater <<<"$record"
    if [ "$target" != all ] && [ "$target" != "$name" ]; then continue; fi
    if ! $status_only; then
        update_one "$name" "$dir" "$updater" || failures=$((failures + 1))
    fi
    report_status "$name" "$dir"
done

if [ "$failures" -gt 0 ]; then
    echo "!! $failures shell update(s) failed" >&2
    exit 1
fi
