#!/bin/bash
# Shared helpers for the dcli hook scripts (setup-*.sh, update-*.sh,
# update-shells.sh). Sourced, never executed: callers own `set -euo pipefail`.
# One home for the real-user block and the clone / symlink / pull patterns
# that used to be pasted into every hook and drifted apart.

# CLONED_NOW is only read by the sourcing hooks, which shellcheck cannot see.
# shellcheck disable=SC2034

# ── Real user ────────────────────────────────────────────────────────────────
# dcli may run hooks as root — always operate on the real user's home.
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

as_user() {
    if [ "$(id -u)" -eq 0 ] && [ "$REAL_USER" != "root" ]; then
        sudo -u "$REAL_USER" -H "$@"
    else
        "$@"
    fi
}

# ── Checkouts ────────────────────────────────────────────────────────────────
# Set by clone_checkout: 1 if it cloned just now, 0 if the checkout was already
# there. Callers use it to run post-clone-only steps (adding the upstream remote).
CLONED_NOW=0

# Refuse to treat a non-git path as a checkout slot.
require_clonable() {
    local dir="$1"
    if [ -e "$dir" ]; then
        echo "!! $dir exists but is not a git repo — refusing to touch it." >&2
        return 1
    fi
}

# Interactive opt-in. Non-interactive shells (dcli hooks) decline silently so a
# sync never clones a fork behind the user's back; exits the calling hook 0.
confirm_clone() {
    local label="$1" dir="$2" hook_module="$3" reply=""
    if [ -t 0 ]; then
        read -r -p ":: $label not found at $dir. Clone it? [y/N] " reply
    fi
    case "$reply" in
        y | Y | yes | YES) ;;
        *)
            echo ":: Skipping $label setup (no clone). Re-run later with:"
            echo "     dcli module run-hook $hook_module"
            exit 0
            ;;
    esac
}

# clone_checkout <dir> <url> <branch> <label> [--opt-in <hook-module>] [git clone args...]
# No-op when <dir> is already a checkout. Without --opt-in the clone is
# automatic; with it the user is asked first (see confirm_clone).
clone_checkout() {
    local dir="$1" url="$2" branch="$3" label="$4" opt_in_module=""
    shift 4
    if [ "${1:-}" = "--opt-in" ]; then
        opt_in_module="$2"
        shift 2
    fi
    CLONED_NOW=0
    if [ -d "$dir/.git" ]; then
        echo ":: $label already cloned at $dir"
        return 0
    fi
    require_clonable "$dir" || return 1
    if [ -n "$opt_in_module" ]; then
        confirm_clone "$label" "$dir" "$opt_in_module"
    fi
    echo ":: Cloning $label (branch $branch)"
    as_user mkdir -p "$(dirname "$dir")" || return 1
    as_user git clone --branch "$branch" "$@" "$url" "$dir" || return 1
    CLONED_NOW=1
}

update_submodules() {
    as_user git -C "$1" submodule update --init --recursive --depth 1
}

fast_forward_pull() {
    as_user git -C "$1" pull --ff-only
}

# Update scripts bail out early when their checkout was never set up.
require_checkout() {
    local dir="$1" label="$2" setup_script="$3"
    if [ ! -d "$dir/.git" ]; then
        echo "!! $label not found at $dir — run $setup_script first" >&2
        return 1
    fi
}

# ── Symlinks ─────────────────────────────────────────────────────────────────
# ensure_symlink <src> <dst> <policy>
# Policy is what happens when <dst> exists and is not already the right link:
#   refuse — error out, touch nothing
#   backup — move it aside to <dst>.bak-<timestamp>
#   force  — replace it (ln -sfn)
ensure_symlink() {
    local src="$1" dst="$2" policy="$3" shown="${2/#$REAL_HOME/\~}"
    if [ -L "$dst" ] && [ "$(readlink -f "$dst")" = "$(readlink -f "$src")" ]; then
        echo ":: $shown already linked"
        return 0
    fi
    case "$policy" in
        refuse)
            if [ -e "$dst" ] || [ -L "$dst" ]; then
                echo "!! $dst exists and is not a correct symlink — refusing to clobber." >&2
                return 1
            fi
            ;;
        backup)
            if [ -e "$dst" ]; then
                local backup
                backup="$dst.bak-$(date +%Y%m%d-%H%M%S)"
                echo ":: Backing up existing $dst -> $backup"
                as_user mv "$dst" "$backup" || return 1
            fi
            ;;
        force) ;;
        *)
            echo "!! ensure_symlink: unknown policy '$policy'" >&2
            return 1
            ;;
    esac
    as_user mkdir -p "$(dirname "$dst")" || return 1
    as_user ln -sfn "$src" "$dst" || return 1
    echo ":: Symlinked $dst -> $src"
}
