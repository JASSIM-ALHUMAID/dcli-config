#!/bin/bash
# Switch between Hyprland shells: caelestia | ambxst | dms | noctalia | end4 | end4pc | omarchy | xenon
# Usage: switch-shell.sh [--dry-run] [shell]
#   no argument = interactive fuzzel picker (falls back to usage text)
#   --dry-run   = print the teardown/launch plan and the active.conf that would
#                 be written; touches nothing (no lock, no kill, no hyprctl, no
#                 theme snapshots)
#
# Mechanism: ~/.config/hypr/hyprland.lua reads shells/active.conf, extracts
# the shell name, and dofile()'s the matching Lua config. This script
# rewrites active.conf and reloads hyprland. The per-shell Lua configs live
# in the dcli repo (dotfiles/hypr/shells/); the shell list itself is the
# registry file next to them (read via lib/shell-common.sh).

set -u

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

DRY_RUN=0
SHELL_NAME=""
for arg in "$@"; do
  case "$arg" in
  --dry-run) DRY_RUN=1 ;;
  *) SHELL_NAME="$arg" ;;
  esac
done

# ── Single-instance lock ─────────────────────────────────────────────────────
# Prevent concurrent runs — only one switch-shell at a time. The fd number is
# bash-allocated (fd operands cannot come from expansion) and carried in LOCK_FD.
# $XDG_RUNTIME_DIR is per-user and 0700; /tmp is the fallback for sessions
# without one. A dry run takes no lock: it mutates nothing, so it must not
# contend with (or be blocked by) a real switch.
if [ "$DRY_RUN" = 0 ]; then
  LOCKFILE="${XDG_RUNTIME_DIR:-/tmp}/switch-shell.lock"
  exec {LOCK_FD}>"$LOCKFILE"
  flock -n "$LOCK_FD" || { echo "switch-shell.sh: another instance is running"; exit 1; }
fi

# Shared registry + active.conf parser (KNOWN, SHELL_RECORDS, current_shell,
# shell_config_path, kill_matching) — resolved off this script's real path so
# the script works from any cwd or through a symlink.
# shellcheck source=lib/shell-common.sh disable=SC1091
. "$SCRIPT_DIR/lib/shell-common.sh" || exit 1

# ── Target selection ─────────────────────────────────────────────────────────
# No argument: fuzzel picker (marks and preselects the current shell)
if [ -z "$SHELL_NAME" ]; then
  if command -v fuzzel >/dev/null 2>&1 && [ -n "${WAYLAND_DISPLAY:-}" ]; then
    cur=$(current_shell)
    # Real per-shell logo + blurb, split out of the shared registry's records
    # (name|config|icon|blurb — see the registry file for the set and why
    # omarchy is a .png). The logos are committed under dotfiles/fuzzel/shell-icons and land
    # at ~/.config/fuzzel/shell-icons via the fuzzel dir symlink. Rendered by
    # fuzzel's dmenu icon protocol (label\0icon\x1f<abs-path>, libresvg).
    icon_dir="$HOME/.config/fuzzel/shell-icons"
    icon_files=()
    blurbs=()
    for record in "${SHELL_RECORDS[@]}"; do
      IFS='|' read -r _ _ icon blurb <<<"$record"
      icon_files+=("$icon")
      blurbs+=("$blurb")
    done
    args=(--dmenu --index)
    picker_ini="$HOME/.config/fuzzel/shell-picker.ini"
    [ -f "$picker_ini" ] && args+=(--config "$picker_ini") || args+=(--prompt "shell> ")
    # Preselect the active shell (separate loop — it appends to args, which the
    # menu-building subshell below can't do since it runs in a pipe).
    for i in "${!KNOWN[@]}"; do
      [ "${KNOWN[$i]}" = "$cur" ] && args+=(--select-index "$i")
    done
    # Build the menu straight into the pipe: the icon field needs a literal NUL,
    # which a bash variable cannot hold, so printf each entry directly.
    idx=$(
      for i in "${!KNOWN[@]}"; do
        s=${KNOWN[$i]}
        label=$(printf '%-10s  %s' "$s" "${blurbs[$i]}")
        [ "$s" = "$cur" ] && label+="  ●"
        printf '%s\0icon\x1f%s\n' "$label" "$icon_dir/${icon_files[$i]}"
      done | fuzzel "${args[@]}"
    )
    case "$idx" in *[!0-9]* | "") exit 0 ;; esac
    SHELL_NAME=${KNOWN[$idx]:-}
    [ -z "$SHELL_NAME" ] && exit 0
  else
    echo "Usage: switch-shell.sh [${KNOWN[*]}]  (current: $(current_shell))"
    exit 1
  fi
fi

case " ${KNOWN[*]} " in
*" $SHELL_NAME "*) ;;
*)
  echo "Unknown shell: $SHELL_NAME (choose from: ${KNOWN[*]})"
  exit 1
  ;;
esac

SHELL_CONFIG=$(shell_config_path "$SHELL_NAME")
if [ ! -f "$SHELL_CONFIG" ]; then
  echo "Error: $SHELL_CONFIG not found (run dcli sync?)"
  exit 1
fi

PREV_SHELL=$(current_shell)

# ── Shared theming surface ───────────────────────────────────────────────────
# Per-shell snapshot/restore of the SHARED app theming surface (GTK, Qt, cursor,
# Thunar's colours, rofi). Those are one global copy that most of the shells
# overwrite, so without this the desktop keeps whichever look the last shell to
# run its theme pipeline left behind — usually the login shell, all session.
# scripts/shell-theme-state.sh has the full reasoning and the managed set.
#
# Never allowed to break a switch: a bad snapshot must cost you the theming, not
# the ability to change shells. This script is `set -u` only, so `|| true` is
# what keeps a non-zero exit from mattering.
theme_state() {
  [ "${DCLI_SKIP_THEME_STATE:-0}" = 1 ] && return 0
  local helper="$SCRIPT_DIR/shell-theme-state.sh"
  [ -x "$helper" ] || return 0
  "$helper" "$1" "$2" || true
}

# ── GRUB theme ───────────────────────────────────────────────────────────────
# The bootloader follows the shell: re-render the GRUB theme set with the new
# shell as `active`. Renders take seconds (image work), so it runs detached —
# a switch never waits on it — and its failure is never a switch failure. The
# root-side path unit installs the result when the renderer touches its stamp
# (docs/GRUB.md). DCLI_SKIP_GRUB_THEME=1 bypasses it.
GRUB_RENDERER="$SCRIPT_DIR/render-grub-theme.sh"
GRUB_RENDER_LOG="${XDG_STATE_HOME:-$HOME/.local/state}/dcli/grub-theme.log"

grub_theme_render() {
  [ "${DCLI_SKIP_GRUB_THEME:-0}" = 1 ] && return 0
  [ -x "$GRUB_RENDERER" ] || return 0
  mkdir -p "$(dirname "$GRUB_RENDER_LOG")" 2>/dev/null || return 0
  setsid -f "$GRUB_RENDERER" --active "$1" >"$GRUB_RENDER_LOG" 2>&1 </dev/null || true
}

# ── SDDM theme ───────────────────────────────────────────────────────────────
# The login screen follows the shell the same way (docs/SDDM.md): re-stage the
# palette/wallpaper with the new shell as the running one; the root path unit
# installs it. Detached and non-fatal, like the GRUB render.
# DCLI_SKIP_SDDM_THEME=1 bypasses it.
SDDM_RENDERER="$SCRIPT_DIR/render-sddm-theme.sh"
SDDM_RENDER_LOG="${XDG_STATE_HOME:-$HOME/.local/state}/dcli/sddm-theme.log"

sddm_theme_render() {
  [ "${DCLI_SKIP_SDDM_THEME:-0}" = 1 ] && return 0
  [ -x "$SDDM_RENDERER" ] || return 0
  mkdir -p "$(dirname "$SDDM_RENDER_LOG")" 2>/dev/null || return 0
  setsid -f "$SDDM_RENDERER" --active "$1" all >"$SDDM_RENDER_LOG" 2>&1 </dev/null || true
}

# ── Terminal theme ───────────────────────────────────────────────────────────
# The prompt (starship) and system-info (fastfetch) configs follow the shell
# too: two symlink retargets, so it runs inline and instant, not detached. A
# failure is reported by the helper and never fails the switch.
# DCLI_SKIP_TERMINAL_THEME=1 bypasses it.
TERMINAL_APPLIER="$SCRIPT_DIR/apply-terminal-theme.sh"

terminal_theme_apply() {
  [ "${DCLI_SKIP_TERMINAL_THEME:-0}" = 1 ] && return 0
  [ -x "$TERMINAL_APPLIER" ] || return 0
  "$TERMINAL_APPLIER" "$1" || true
}

# ── Shell lifecycle table ────────────────────────────────────────────────────
# Per registry name, everything switch-shell.sh knows about running that shell:
#   MATCH_SPECS     newline-separated "<pgrep flag> <pattern>" lines. The FIRST
#                   line is the "is it running" guard before launching; ALL
#                   lines are killed on teardown. Patterns must not contain '|'
#                   (they are joined into the reap-wait regex).
#   quit_<name>     optional graceful-quit through the shell's own IPC
#   launch_<name>   required; starts the shell in the background
# Adding a shell = a registry record + an entry in each of these (smoke.sh
# fails if a registry name lacks a spec or a launch function).
declare -A MATCH_SPECS=(
  [caelestia]='-f qs -c caelestia
-f caelestia shell
-f caelestia resizer'
  # AMBXst — /usr/local/bin/ambxst is now a Go daemon that supervises
  # children (`qs -p .../ambxst/shell.qml`, `axctl daemon`, `tail -f`
  # on the IPC pipe), so the main UI process must be matched by command
  # line (-f); -x ambxst/axctl catch the daemon binaries by name.
  # Helpers (comm=bash/tail) need -f with a distinctive phrase.
  [ambxst]='-f ambxst/shell.qml
-x ambxst
-x axctl
-f ambxst_ipc'
  [dms]='-f dms run'
  # Noctalia v5 is its own binary (no quickshell fork) — match it by name.
  [noctalia]='-x noctalia'
  [end4]='-f qs -c ii'
  [end4pc]='-f qs -c end4-pC'
  # omarchy v4 is one quickshell instance started as
  # `quickshell -n -p <checkout>/shell`. Like ambxst's `qs -p` it has no config
  # name, so it must be matched by command line — and the pattern is anchored on
  # the whole invocation, not just "omarchy/shell", which would also match an
  # editor holding a file from the checkout open.
  # omarchy-launch-shell supervises quickshell and respawns it on any exit —
  # kill the supervisor too or the shell comes right back.
  [omarchy]='-f quickshell -n -p .*omarchy/shell
-f omarchy-launch-shell'
  [xenon]='-f qs -c xenon'
  # glyph-rice runs two Quickshell configs from one checkout: `glyph` (the
  # desktop, `qs -p .../quickshell/glyph`) and `rice` (its shell switcher and
  # lock helper). `qs -p` has no config name, so match by command line — the
  # same anchoring omarchy needs. Both share the checkout prefix, so one
  # pattern covers the desktop, the lock process and the rice app.
  [glyph]='-f qs .*quickshell/glyph
-f qs .*quickshell/rice'
  # ryoku is supervised by its own daemon: ryoku-shell owns the qs children and
  # refuses to start a second copy, so the daemon is the "is it running" guard.
  # It runs in deployed mode, so its children are `qs -c shell` and the Hub and
  # store are `qs -c hub` / `qs -c ryostore` — config names no other shell here
  # uses. ryogami (wallpapers) is a sibling daemon, not a child: it, its video
  # player and its picker (`quickshell -p ~/.local/share/ryogami/shell.qml`)
  # are matched on their own.
  [ryoku]='-x ryoku-shell
-x ryogami
-x ryogami-live
-f quickshell -p .*ryogami/shell.qml
-f qs -c shell
-f qs -c hub
-f qs -c ryostore'
)

# Not owned by any one shell: helpers that previous shells' configs leave
# behind (hypridle — its lock_cmd is the previous shell's lock screen, and
# surviving a switch is what showed glyph's lock over omarchy 2026-10-31;
# swaync, awww-daemon, old quickshell wallpaper scripts) and the
# quickshell catch-all — no quickshell instance from any previous shell may
# linger. Killed after every shell's own specs.
SHARED_MATCH_SPECS='-x swaync
-f awww-daemon
-x quickshell
-f switchwall.sh
-x hypridle'

# No graceful-quit IPC for noctalia v5: its CLI only accepts theme/msg/config/
# dmenu/plugins/firefox-theme, and an unrecognised bare argument falls through
# and STARTS the shell — so `noctalia kill` would launch it. Killed by name via
# its MATCH_SPECS instead. Likewise xenon: its handlers are launcher,
# clipboard, sidePanel, wallpaperpanel, powermenu, infopanel, settings,
# cliphistService, wallpaper and lock — there is no kill/quit verb to call. It
# is TERMed by command line.
quit_caelestia() { command -v qs >/dev/null 2>&1 && qs -c caelestia kill 2>/dev/null; }
quit_dms() { command -v dms >/dev/null 2>&1 && dms kill 2>/dev/null; }
quit_end4() { command -v qs >/dev/null 2>&1 && qs -c ii kill 2>/dev/null; }
quit_end4pc() { command -v qs >/dev/null 2>&1 && qs -c end4-pC kill 2>/dev/null; }
# Only ask ambxst to quit if it's actually running: its CLI trusts a
# cached PID in /tmp/ambxst.pid, and a stale entry there makes it kill
# whatever unrelated process now owns that recycled PID.
quit_ambxst() { pgrep -A -f "ambxst/shell.qml" >/dev/null 2>&1 && ambxst quit 2>/dev/null; }
# ryoku's daemon has a real quit verb: it TERMs the Quickshell children it
# supervises and reaps them before exiting. Only ask when the daemon is running
# — a stray client would just fail to connect and print an error.
quit_ryoku() { pgrep -A -x ryoku-shell >/dev/null 2>&1 && "$HOME/.local/bin/ryoku-shell" quit 2>/dev/null; }

# dms and noctalia are exec-once'd from their shell conf, but exec-once does
# not re-fire on `hyprctl reload`, so they are started here too (guarded by the
# first MATCH_SPECS line so a fresh login doesn't double-start them).
# Settle wait between starting ambxst and re-asserting its monitor scale.
AMBXST_MONITOR_SETTLE_SECS=1

launch_caelestia() {
  # The fork's QML needs its own Caelestia.Internal plugin (~/.local/lib):
  # the packaged one in /usr/lib is older and lacks types like
  # LogindManager, so the shell dies with "Failed to load configuration".
  # hypr-user.lua exports these too, but hyprland only applies `env` at
  # startup — set them here so a switch works without a relogin.
  QML2_IMPORT_PATH="$HOME/.local/lib/qt6/qml${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}" \
    CAELESTIA_LIB_DIR="$HOME/.local/lib/caelestia" \
    caelestia shell -d &
  disown
}
launch_ambxst() {
  # ambxst rewrites the monitor on startup; shells/ambxst/overrides.lua
  # puts it back at scale 1 on the next reload.
  ambxst &
  disown
  sleep "$AMBXST_MONITOR_SETTLE_SECS"
  hyprctl eval 'hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })' >/dev/null 2>&1
}
launch_dms() {
  dms run &
  disown
}
launch_noctalia() {
  noctalia &
  disown
}
# end4/end4pc own hypridle (their execs.lua start it at login only), and the
# shared teardown kills it, so a switch into them has to start it again.
launch_end4() {
  qs -c ii &
  disown
  hypridle &
  disown
}
launch_end4pc() {
  qs -c end4-pC &
  disown
  hypridle &
  disown
}
launch_omarchy() {
  # Nothing puts OMARCHY_PATH in the session environment on purpose (see
  # docs/shells/omarchy.md), so it is exported here for the shell process.
  # The Hyprland config does not rely on this — it resolves the checkout
  # itself — but the shell's QML calls omarchy-* scripts by bare name.
  # QS_DISABLE_FILE_WATCHER/QS_NO_RELOAD_POPUP mirror upstream's
  # omarchy-launch-shell: quickshell's own file-watcher reload against a
  # half-updated checkout crashes the shell, so reloads stay deliberate.
  # scripts/omarchy-shims comes FIRST so house shims shadow same-named
  # upstream scripts for everything the shell spawns (currently just
  # omarchy-launch-screensaver — see the shim for why).
  OMARCHY_PATH="$HOME/.local/share/omarchy" \
    PATH="$SCRIPT_DIR/omarchy-shims:$HOME/.local/share/omarchy/bin:$PATH" \
    QS_DISABLE_FILE_WATCHER=1 QS_NO_RELOAD_POPUP=1 \
    quickshell -n -p "$HOME/.local/share/omarchy/shell" &
  disown
}
launch_xenon() {
  qs -c xenon &
  disown
}
launch_glyph() {
  # Started directly rather than through upstream's `rice start`: that helper
  # also symlinks glyph's starship/fastfetch/gtk term palettes into ~/.config,
  # which this repo and the other shells own. `-d` detaches, so the launcher
  # returns immediately. The shell's own `rice lock` still works — the config
  # directory is linked; only `rice switch` is deliberately not on PATH.
  qs -p "$HOME/.config/quickshell/glyph" -d &
  disown
}
launch_ryoku() {
  # launch-ryoku.sh is the one launch definition, shared with
  # shells/ryoku/hyprland/execs.lua (session PATH, ryogami, deployed mode).
  "$SCRIPT_DIR/launch-ryoku.sh" &
  disown
}

# A spec line is "<flag> <pattern>"; the pattern may contain spaces.
spec_flag() { echo "${1%% *}"; }
spec_pattern() { echo "${1#* }"; }

guard_spec() { head -n1 <<<"${MATCH_SPECS[$1]}"; }

# ── Teardown ─────────────────────────────────────────────────────────────────
# Reap-wait limit (5 × TERM_POLL_INTERVAL ≈ 0.5s; the TERM/KILL escalation
# constants and kill_matching live in lib/shell-common.sh).
REAP_POLL_ITERS=5

spec_block_for() {
  if [ "$1" = shared ]; then echo "$SHARED_MATCH_SPECS"; else echo "${MATCH_SPECS[$1]}"; fi
}

# Alternation of every pattern in the table — what is left to wait for after
# the kills. Derived, so a new shell's spec is reaped without a second list.
reap_regex() {
  local shell spec patterns=()
  for shell in "${KNOWN[@]}" shared; do
    while IFS= read -r spec; do
      [ -n "$spec" ] && patterns+=("$(spec_pattern "$spec")")
    done <<<"$(spec_block_for "$shell")"
  done
  local IFS='|'
  echo "${patterns[*]}"
}

kill_spec_block() {
  local spec
  while IFS= read -r spec; do
    [ -n "$spec" ] && kill_matching "$(spec_flag "$spec")" "$(spec_pattern "$spec")"
  done <<<"$1"
}

kill_all_shells() {
  local shell
  # Ask nicely via each shell's own IPC first (skip if binary not installed)
  for shell in "${KNOWN[@]}"; do
    declare -F "quit_$shell" >/dev/null && "quit_$shell"
  done
  for shell in "${KNOWN[@]}" shared; do
    kill_spec_block "$(spec_block_for "$shell")"
  done
  # Catch-all: no quickshell instance from any previous shell may linger
  killall -q qs quickshell 2>/dev/null
  # Wait briefly for OS to reclaim resources from killed processes
  local i=0 regex
  regex=$(reap_regex)
  while [ "$i" -lt "$REAP_POLL_ITERS" ] && pgrep -A -f "$regex" >/dev/null 2>&1; do
    sleep "$TERM_POLL_INTERVAL"
    i=$((i + 1))
  done
}

launch_shell() {
  local guard
  guard=$(guard_spec "$1")
  pgrep -A "$(spec_flag "$guard")" "$(spec_pattern "$guard")" >/dev/null 2>&1 || "launch_$1"
}

# ── Dry run ──────────────────────────────────────────────────────────────────
# Read-only: pgrep only reports whether each pattern currently matches.
print_plan() {
  local shell line state
  echo "Dry run: switch $PREV_SHELL -> $SHELL_NAME (nothing touched)"
  echo "config: $SHELL_CONFIG"
  echo
  echo "graceful quit (in order):"
  for shell in "${KNOWN[@]}"; do
    declare -F "quit_$shell" >/dev/null && echo "  quit_$shell"
  done
  echo "kill (TERM, KILL for survivors; pgrep -A):"
  for shell in "${KNOWN[@]}" shared; do
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      pgrep -A "$(spec_flag "$line")" "$(spec_pattern "$line")" >/dev/null 2>&1 && state=running || state=idle
      printf '  %-9s %-2s %-40s [%s]\n' "$shell" "$(spec_flag "$line")" "$(spec_pattern "$line")" "$state"
    done <<<"$(spec_block_for "$shell")"
  done
  echo "  catch-all: killall -q qs quickshell"
  echo "reap-wait regex: $(reap_regex)"
  echo
  echo "launch guard: $(guard_spec "$SHELL_NAME")"
  declare -f "launch_$SHELL_NAME"
  echo
  if [ "${DCLI_SKIP_GRUB_THEME:-0}" = 1 ]; then
    echo "grub theme: skipped (DCLI_SKIP_GRUB_THEME=1)"
  else
    echo "grub theme (detached, non-fatal): $GRUB_RENDERER --active $SHELL_NAME  [log: $GRUB_RENDER_LOG]"
  fi
  if [ "${DCLI_SKIP_SDDM_THEME:-0}" = 1 ]; then
    echo "sddm theme: skipped (DCLI_SKIP_SDDM_THEME=1)"
  else
    echo "sddm theme (detached, non-fatal): $SDDM_RENDERER --active $SHELL_NAME all  [log: $SDDM_RENDER_LOG]"
  fi
  if [ "${DCLI_SKIP_TERMINAL_THEME:-0}" = 1 ]; then
    echo "terminal theme: skipped (DCLI_SKIP_TERMINAL_THEME=1)"
  else
    echo "terminal theme (starship + fastfetch links, inline):"
    "$TERMINAL_APPLIER" --dry-run "$SHELL_NAME" 2>&1 | sed 's/^/  /' || true
  fi
  echo
  echo "active.conf ($ACTIVE) would become:"
  printf '# Written by switch-shell.sh — do not edit by hand\n%s\n' "$SHELL_NAME"
}

if [ "$DRY_RUN" = 1 ]; then
  print_plan
  exit 0
fi

# ── Switch over ──────────────────────────────────────────────────────────────
# Snapshot the OUTGOING shell before anything is torn down — its theming has to
# be captured while it is still the live one. Skipped when the target is already
# active, so re-running the switch cannot overwrite a good snapshot with itself.
if [ "$PREV_SHELL" != "$SHELL_NAME" ]; then
  theme_state save "$PREV_SHELL"
fi

kill_all_shells

# Point active.conf at the chosen shell (read by ~/.config/hypr/hyprland.lua)
printf '# Written by switch-shell.sh — do not edit by hand\n%s\n' "$SHELL_NAME" >"$ACTIVE"

# ── Submap reset + reload ────────────────────────────────────────────────────
# Settle wait after `hyprctl reload` before the submap re-entry below.
RELOAD_SETTLE_SECS=0.2

# Clear any leaked config-parser submap state before reloading: caelestia's
# KeybindApplier applies its JSON binds via `hyprctl keyword submap global;
# keyword bind ...` and that parser state persists, so without this reset the
# reload parses the ENTIRE new shell's binds into the "global" submap and
# they all go dead. Under the Lua config `hyprctl keyword` is rejected outright
# ("keyword can't work with non-legacy parsers"), so this is best-effort.
hyprctl keyword submap reset >/dev/null 2>&1
hyprctl reload
sleep "$RELOAD_SETTLE_SECS"

# Shells that keep their static binds in a permanently-active "global" submap
# need it re-entered; root-level binds go dead if a submap is left active.
# Detect from the loaded binds instead of hardcoding shell names. Dispatchers
# take Lua syntax under a .lua config and legacy syntax under a .conf one.
#
# Parsed from the PLAIN-TEXT output on purpose: on Hyprland 0.56 `hyprctl binds -j`
# emitted invalid JSON whenever binds carried descriptions (it shifted keys
# against values, e.g. `"keycode": XF86AudioRaiseVolume` unquoted), and omarchy
# sets a description on every one of its 216 binds, so jq failed there. 0.57.0
# parsed fine under caelestia (168 binds); untested under omarchy. The text parse
# is robust either way, so it is kept defensively.
if hyprctl binds | grep -qE '^[[:space:]]*submap: global$'; then
  hyprctl dispatch 'hl.dsp.submap("global")' >/dev/null 2>&1 || hyprctl dispatch submap global
else
  hyprctl dispatch 'hl.dsp.submap("reset")' >/dev/null 2>&1 || hyprctl dispatch submap reset
fi

# ── Theme replay ─────────────────────────────────────────────────────────────
# Replay the incoming shell's theming. After the reload so it is not undone by
# it, and before the launch below so the shell reads the restored files at
# startup; GTK/Qt apps already running pick the gsettings keys up live. A shell
# with no snapshot yet (first visit) is left exactly as it is.
if [ "$PREV_SHELL" != "$SHELL_NAME" ]; then
  theme_state restore "$SHELL_NAME"
fi

# ── Launch ───────────────────────────────────────────────────────────────────
# Release the lock before launching background processes — they inherit
# the lock fd (LOCK_FD) and would hold the lock open after this script exits.
exec {LOCK_FD}>&-

grub_theme_render "$SHELL_NAME"
sddm_theme_render "$SHELL_NAME"
terminal_theme_apply "$SHELL_NAME"

launch_shell "$SHELL_NAME"

echo "Switched to $SHELL_NAME"
echo "Active shell: $(grep -v '^#' "$ACTIVE")"
