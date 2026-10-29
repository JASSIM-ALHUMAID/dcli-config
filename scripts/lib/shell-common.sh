#!/bin/bash
# Shared shell registry + active.conf parser. Sourced by switch-shell.sh,
# edit-hypr.sh, switch-quickshell.sh, doctor.sh, and fixture-tested by
# tests/smoke.sh — one home for the things that used to exist as per-script
# copies and drifted silently (devfiles/doc/violations.md #2/#3).
# Sourcing fails (non-zero, empty KNOWN) when the registry is unusable — callers
# must `|| exit 1`.

# ── Registry ─────────────────────────────────────────────────────────────────
# The shell list lives in ONE data file, dotfiles/hypr/shells/registry, shared
# with hyprland.lua (the Lua runtime). Records are name|config|icon|blurb in
# picker order; the file header documents each field and the omarchy .png
# exception. It is resolved from this library's own real path (repo-relative),
# not via ~/.config/hypr, so fixtures and a not-yet-linked checkout work too;
# SHELL_REGISTRY overrides it for tests.
SHELL_COMMON_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
SHELL_REGISTRY="${SHELL_REGISTRY:-$SHELL_COMMON_DIR/../../dotfiles/hypr/shells/registry}"
REGISTRY_FIELDS=4

HYPR_DIR="$HOME/.config/hypr"
SHELLS_DIR="$HYPR_DIR/shells"
ACTIVE="$SHELLS_DIR/active.conf"

SHELL_RECORDS=()
KNOWN=()

# Fills SHELL_RECORDS/KNOWN. On a missing, unreadable, empty or malformed file
# it leaves both EMPTY and returns non-zero: a half-parsed list would let
# switch-shell.sh tear down a shell it then cannot start.
load_registry() {
    SHELL_RECORDS=()
    KNOWN=()
    [ -r "$SHELL_REGISTRY" ] || {
        echo "shell-common.sh: shell registry not readable: $SHELL_REGISTRY" >&2
        return 1
    }
    local line fields
    while IFS= read -r line; do
        case "$line" in '' | '#'*) continue ;; esac
        fields=$(tr -cd '|' <<<"$line")
        if [ "${#fields}" -ne $((REGISTRY_FIELDS - 1)) ]; then
            echo "shell-common.sh: malformed registry record (want $REGISTRY_FIELDS fields): $line" >&2
            SHELL_RECORDS=()
            KNOWN=()
            return 1
        fi
        SHELL_RECORDS+=("$line")
        KNOWN+=("${line%%|*}")
    done <"$SHELL_REGISTRY"
    [ "${#KNOWN[@]}" -gt 0 ] || {
        echo "shell-common.sh: shell registry has no records: $SHELL_REGISTRY" >&2
        return 1
    }
}

# Absolute path of a shell's Hyprland Lua config. "~/" in the registry means
# $HOME; anything else is relative to ~/.config/hypr (hyprland.lua resolves
# the same record the same way).
shell_config_path() {
    local record config
    for record in "${SHELL_RECORDS[@]}"; do
        [ "${record%%|*}" = "$1" ] || continue
        config=${record#*|}
        config=${config%%|*}
        case "$config" in
        \~/*) echo "$HOME/${config#\~/}" ;;
        *) echo "$HYPR_DIR/$config" ;;
        esac
        return 0
    done
    return 1
}

load_registry || return 1

# ── Process teardown ─────────────────────────────────────────────────────────
# TERM→KILL escalation limit (10 × 0.1s ≈ 1s).
TERM_POLL_ITERS=10
TERM_POLL_INTERVAL=0.1

# TERM first, escalate to KILL only for survivors. Patterns must be
# anchored (-x exact name, or -f with a distinctive phrase) so unrelated
# processes (e.g. an editor with an ambxst file open) are never matched.
#
# -A (--ignore-ancestors) is not optional: with -f, pgrep/pkill match the whole
# command line, so ANY ancestor of this script whose command line merely contains
# the pattern is a hit — including the shell that invoked us. That is not
# theoretical: a `bash -c` whose text mentioned "quickshell -n -p .../omarchy/shell"
# was TERMed by this function mid-switch, killing the script that was running it.
# -A excludes our own ancestors and costs nothing.
kill_matching() {
    local flag="$1" pattern="$2"
    pkill -A "$flag" "$pattern" 2>/dev/null || return 0
    # Poll up to 1s, bail immediately when process exits
    local i=0
    while [ "$i" -lt "$TERM_POLL_ITERS" ]; do
        pgrep -A "$flag" "$pattern" >/dev/null 2>&1 || return 0
        sleep "$TERM_POLL_INTERVAL"
        i=$((i + 1))
    done
    # Still alive after 1s — escalate to KILL
    pkill -9 -A "$flag" "$pattern" 2>/dev/null
}

# ── Active shell ─────────────────────────────────────────────────────────────
# active.conf holds a bare shell name; older versions wrote a
# "source = ~/.config/hypr/shells/<name>.conf" line, still accepted here.
# (hyprland.lua:read_active_shell is the Lua parser of the same contract —
# different runtime, kept separate, but the accepted forms must stay in sync.)
current_shell() {
    [ -f "$ACTIVE" ] || {
        echo none
        return
    }
    local src
    src=$(grep -m1 -v '^[[:space:]]*\(#.*\)\?$' "$ACTIVE" |
        sed 's/^source[[:space:]]*=[[:space:]]*//; s/.*shells\///; s/\.conf.*//; s/\.lua.*//; s/[[:space:]]*$//')
    echo "${src:-none}"
}
