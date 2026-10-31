#!/bin/bash
# Read-only health check for this dcli setup. Never mutates anything.
# Usage: doctor.sh [--versions]
#   (none)      one "ok/WARN/FAIL/info  <check>" line per check, summary last;
#               exits non-zero if any check FAILed
#   --versions  print the stack versions as a markdown table (paste into
#               AGENTS.md → Stack) and exit
#
# Hyprland-dependent checks degrade to WARN outside a Hyprland session, so the
# script is usable from a TTY or ssh too.

set -u

# ── Constants ────────────────────────────────────────────────────────────────
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
REPO_DIR=$(dirname "$SCRIPT_DIR")
DOTFILES="$REPO_DIR/dotfiles"
CONFIG_DIR="$HOME/.config"
SHELLCHECK="${SHELLCHECK:-$HOME/.local/bin/shellcheck}"
DCLI_DRY_RUN_TIMEOUT_SECS=120

# Per-shell checkouts: path|what. Branches are reported, never asserted — the
# fork branches are in flux.
CHECKOUTS=(
    "$HOME/Projects/shell/real|caelestia fork workspace"
    "$HOME/.local/src/ambxst|ambxst"
    "$HOME/.local/share/dots-hyprland|end4"
    "$HOME/.local/share/end4-pC|end4pc"
    "$HOME/.local/share/omarchy|omarchy"
    "$HOME/.local/share/xenon-shell|xenon"
    "$HOME/.local/share/glyph-rice|glyph"
    "$HOME/.local/share/ryoku-shell|ryoku"
)
# ~/.config symlinks the shells' own launchers resolve through.
SHELL_LINKS=(caelestia quickshell/ii quickshell/end4-pC quickshell/xenon quickshell/glyph quickshell/rice
    quickshell/shell quickshell/hub quickshell/ryostore matugen matugen-end4)

# shellcheck source=lib/shell-common.sh disable=SC1091
. "$SCRIPT_DIR/lib/shell-common.sh" || exit 1

# ── Output ───────────────────────────────────────────────────────────────────
fail_count=0
warn_count=0
ok() { printf 'ok    %s\n' "$1"; }
info() { printf 'info  %s\n' "$1"; }
warn() { printf 'WARN  %s\n' "$1"; warn_count=$((warn_count + 1)); }
fail() { printf 'FAIL  %s\n' "$1"; fail_count=$((fail_count + 1)); }

# NB: `pacman -Qq <name>` is NOT a name test — it resolves Provides too (see
# post-update.sh). Match the literal installed package name.
installed_name() { pacman -Qq 2>/dev/null | grep -qx "$1"; }
pkg_version() { pacman -Q "$1" 2>/dev/null | awk '{print $2}'; }

# ── --versions ───────────────────────────────────────────────────────────────
print_versions() {
    local provider=quickshell-git
    installed_name quickshell-git || provider=quickshell
    local hypr nodev sc
    hypr=$(hyprctl version 2>/dev/null | sed -n 's/^Hyprland \([0-9.]*\).*/\1/p' | head -n1)
    nodev=$(node --version 2>/dev/null)
    sc=$("$SHELLCHECK" --version 2>/dev/null | sed -n 's/^version: //p')
    echo '| Layer | Version | Pinned by |'
    echo '| --- | --- | --- |'
    printf '| dcli | %s | `dcli --version` |\n' "$(dcli --version 2>/dev/null | awk '{print $NF}')"
    printf '| Bash | %s | `#!/bin/bash` scripts |\n' "${BASH_VERSION%%(*}"
    printf '| Hyprland | %s | `hyprctl version` |\n' "${hypr:-n/a}"
    printf '| qt6-base | %s | `pacman -Q qt6-base` |\n' "$(pkg_version qt6-base)"
    printf '| %s (provider) | %s | `pacman -Q %s` |\n' "$provider" "$(pkg_version "$provider")" "$provider"
    printf '| noctalia | %s | `pacman -Q noctalia` |\n' "$(pkg_version noctalia)"
    printf '| dux-shell | %s | `pacman -Q dux-shell` |\n' "$(pkg_version dux-shell)"
    printf '| fuzzel | %s | `pacman -Q fuzzel` |\n' "$(pkg_version fuzzel)"
    printf '| jq / git / paru | %s / %s / %s | script dependencies |\n' \
        "$(pkg_version jq)" "$(pkg_version git)" "$(pkg_version paru)"
    printf '| shellcheck | %s (`~/.local/bin`) | lint gate |\n' "${sc:-n/a}"
    printf '| Node | %s | docs build only (`devfiles/`) |\n' "${nodev#v}"
}

if [ "${1:-}" = --versions ]; then
    print_versions
    exit 0
fi
if [ $# -gt 0 ]; then
    echo "Usage: doctor.sh [--versions]" >&2
    exit 2
fi

# ── packages ─────────────────────────────────────────────────────────────────
check_dcli_sync() {
    local out count
    if ! command -v dcli >/dev/null 2>&1; then
        fail "dcli sync --dry-run: dcli not installed"
        return
    fi
    if ! out=$(timeout "$DCLI_DRY_RUN_TIMEOUT_SECS" dcli sync --dry-run 2>&1); then
        fail "dcli sync --dry-run: command failed"
        return
    fi
    count=$(sed -n 's/^Packages to install: *\([0-9][0-9]*\).*/\1/p' <<<"$out" | head -n1)
    if [ -z "$count" ] || [ "$count" = 0 ]; then
        ok "dcli sync --dry-run: nothing to install"
    else
        fail "dcli sync --dry-run: $count package(s) to install: $(sed -n '/^Packages to install:$/,/^$/p' <<<"$out" | sed '1d;/^$/d' | tr -d ' ' | paste -sd, -)"
    fi
}

check_quickshell_provider() {
    local present=()
    installed_name quickshell && present+=(quickshell)
    installed_name quickshell-git && present+=(quickshell-git)
    case "${#present[@]}" in
    1) ok "quickshell provider: exactly one (${present[0]} $(pkg_version "${present[0]}"))" ;;
    0) fail "quickshell provider: none installed" ;;
    *) fail "quickshell provider: both ${present[*]} installed" ;;
    esac
    if command -v qs >/dev/null 2>&1; then
        if qs --private-check-compat >/dev/null 2>&1; then
            ok "qs --private-check-compat"
        else
            fail "qs --private-check-compat: Qt private-ABI mismatch (rebuild quickshell-git)"
        fi
    else
        fail "qs --private-check-compat: qs not on PATH"
    fi
    if installed_name noctalia-qs; then
        fail "noctalia-qs installed (it displaces the real quickshell provider)"
    else
        ok "noctalia-qs absent"
    fi
}

# ── hyprland ─────────────────────────────────────────────────────────────────
check_hypr_errors() {
    local errs
    if [ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
        warn "hyprctl configerrors: skipped (no HYPRLAND_INSTANCE_SIGNATURE)"
        return
    fi
    if ! errs=$(hyprctl configerrors 2>&1); then
        fail "hyprctl configerrors: hyprctl failed"
    elif [ -n "$(tr -d '[:space:]' <<<"$errs")" ]; then
        fail "hyprctl configerrors: $(head -n1 <<<"$errs")"
    else
        ok "hyprctl configerrors: empty"
    fi
}

check_active_shell() {
    local cur config
    cur=$(current_shell)
    if ! printf '%s\n' "${KNOWN[@]}" | grep -qx "$cur"; then
        fail "active.conf: '$cur' is not a registry shell (${KNOWN[*]})"
        return
    fi
    config=$(shell_config_path "$cur")
    if [ -f "$config" ]; then
        ok "active.conf: $cur ($config)"
    else
        fail "active.conf: $cur but $config is missing"
    fi
}

# ── links ────────────────────────────────────────────────────────────────────
check_dotfile_links() {
    local targets_line targets name src dst
    targets_line=$(sed -n 's/^TARGETS=(\(.*\))$/\1/p' "$SCRIPT_DIR/link-dotfiles.sh")
    if [ -z "$targets_line" ]; then
        fail "link-dotfiles.sh TARGETS not found"
        return
    fi
    # shellcheck disable=SC2206  # intentional word split of the array literal
    targets=($targets_line)
    for name in "${targets[@]}"; do
        src="$DOTFILES/$name"
        dst="$CONFIG_DIR/$name"
        if [ -L "$dst" ] && [ "$(readlink -f "$dst")" = "$(readlink -f "$src")" ]; then
            ok "link ~/.config/$name -> dotfiles/$name"
        else
            fail "link ~/.config/$name is not a symlink to dotfiles/$name (run link-dotfiles.sh)"
        fi
    done
}

check_shell_links() {
    local rel
    for rel in "${SHELL_LINKS[@]}"; do
        if [ -L "$CONFIG_DIR/$rel" ] && [ -e "$CONFIG_DIR/$rel" ]; then
            ok "link ~/.config/$rel -> $(readlink -f "$CONFIG_DIR/$rel")"
        elif [ -L "$CONFIG_DIR/$rel" ]; then
            fail "link ~/.config/$rel is dangling"
        else
            fail "\$HOME/.config/$rel is not a symlink"
        fi
    done
}

check_checkouts() {
    local entry dir what branch dirty
    for entry in "${CHECKOUTS[@]}"; do
        dir=${entry%%|*}
        what=${entry#*|}
        if [ ! -d "$dir" ]; then
            fail "checkout $what: $dir missing"
        elif ! git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
            fail "checkout $what: $dir is not a git repo"
        else
            branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
            dirty=$(git -C "$dir" status --porcelain 2>/dev/null | wc -l)
            ok "checkout $what: $dir"
            info "$what on '$branch', $dirty dirty file(s)"
        fi
    done
}

# ── services ─────────────────────────────────────────────────────────────────
check_services() {
    local state
    state=$(systemctl --user is-enabled swaync.service 2>/dev/null)
    if [ "$state" = masked ]; then
        ok "swaync.service masked"
    else
        fail "swaync.service is '${state:-absent}', want masked"
    fi
    state=$(systemctl --user is-enabled dms.service 2>/dev/null)
    case "$state" in
    enabled | enabled-runtime | alias | linked)
        warn "dms.service is '$state': dux-shell's user unit would start DMS under every shell" ;;
    *) ok "dms.service not enabled (${state:-absent})" ;;
    esac
}

check_stray_backups() {
    local baks=()
    shopt -s nullglob
    baks=("$CONFIG_DIR"/*.bak-*)
    shopt -u nullglob
    if [ "${#baks[@]}" -eq 0 ]; then
        ok "no stray ~/.config/*.bak-*"
    else
        warn "${#baks[@]} stray ~/.config/*.bak-* (from link-dotfiles.sh): $(printf '%s ' "${baks[@]##*/}")"
    fi
}

check_dcli_sync
check_quickshell_provider
check_hypr_errors
check_active_shell
check_dotfile_links
check_shell_links
check_checkouts
check_services
check_stray_backups

# ── Summary ──────────────────────────────────────────────────────────────────
echo
if [ "$fail_count" -gt 0 ]; then
    printf 'doctor: %s FAIL, %s WARN\n' "$fail_count" "$warn_count"
    exit 1
fi
printf 'doctor: healthy (%s WARN)\n' "$warn_count"
