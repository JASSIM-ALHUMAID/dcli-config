#!/bin/bash
# Smoke suite for the dcli scripts. Run from anywhere: bash tests/smoke.sh
#
# Sections:
#   parse — bash -n over scripts/*.sh, scripts/lib/*.sh, scripts/omarchy-shims/**
#   lint  — the repo gate (AGENTS.md → Gates): shellcheck scripts/*.sh with
#           cwd = repo root so .shellcheckrc applies, plus scripts/lib/*.sh
#   lib   — fixture test of shell-common.sh:current_shell() against a temp
#           active.conf (bare name, legacy "source =" line, comments-only,
#           missing file)
#   registry — dotfiles/hypr/shells/registry parses to the 9 shells in picker
#           order; config-path lookup; an unusable registry fails loudly
#   lifecycle — every registry name has a MATCH_SPECS entry and a launch_<name>
#           in switch-shell.sh, and `switch-shell.sh --dry-run <name>` exits 0
#           and touches nothing (fixture HOME + XDG_RUNTIME_DIR)
#   drift — every modules/*.yaml `dotfiles:` source must be a link-dotfiles.sh
#           TARGETS entry or an ALLOWED_DIVERGENCE entry below
#
# Read-only by design: no dcli/pacman/hyprctl, no live-session contact.

set -u

REPO_DIR=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)
# Pinned path per AGENTS.md → Stack; fall back to PATH for other machines.
SHELLCHECK="${SHELLCHECK:-$HOME/.local/bin/shellcheck}"

failures=0
ok() { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; failures=$((failures + 1)); }

in_list() {
    local want="$1" x
    shift
    for x in "$@"; do [ "$x" = "$want" ] && return 0; done
    return 1
}

# ── parse: bash -n over every script ─────────────────────────────────────────
parse_targets=()
for f in "$REPO_DIR"/scripts/*.sh "$REPO_DIR"/scripts/lib/*.sh; do
    parse_targets+=("$f")
done
# omarchy-shims holds extensionless executables, some nested — walk files only
# (the glob also matches a subdirectory, which bash -n cannot parse).
while IFS= read -r -d '' f; do parse_targets+=("$f"); done < <(
    find "$REPO_DIR/scripts/omarchy-shims" -type f -print0
)

# Per-run error file: a fixed name would let two concurrent smoke runs read
# each other's bash -n output.
bashn_err=$(mktemp /tmp/smoke-bashn.XXXXXX)
for f in "${parse_targets[@]}"; do
    if bash -n "$f" 2>"$bashn_err"; then
        ok "bash -n ${f#"$REPO_DIR"/}"
    else
        bad "bash -n ${f#"$REPO_DIR"/}: $(cat "$bashn_err")"
    fi
done
rm -f "$bashn_err"

# ── lint: the shellcheck gate ────────────────────────────────────────────────
if command -v "$SHELLCHECK" >/dev/null 2>&1 || [ -x "$SHELLCHECK" ]; then
    if (
        cd "$REPO_DIR" || exit 1
        # scripts/*.sh is the documented gate; lib/*.sh is the shared-code
        # superset — both must be clean.
        "$SHELLCHECK" scripts/*.sh scripts/lib/*.sh
    ); then
        ok "shellcheck scripts/*.sh scripts/lib/*.sh"
    else
        bad "shellcheck scripts/*.sh scripts/lib/*.sh"
    fi
else
    bad "shellcheck not found at $SHELLCHECK or on PATH"
fi

# ── lib: current_shell() fixtures ────────────────────────────────────────────
# current_shell() resolves ACTIVE from $HOME at source time, so point HOME at
# a throwaway tree instead of touching ~/.config/hypr/shells/active.conf.
fixture_home=$(mktemp -d)
trap 'rm -rf "$fixture_home"' EXIT
mkdir -p "$fixture_home/.config/hypr/shells"

expect_current_shell() {
    local desc="$1" content="$2" want="$3" got
    if [ "$content" = MISSING ]; then
        rm -f "$fixture_home/.config/hypr/shells/active.conf"
    else
        printf '%s\n' "$content" >"$fixture_home/.config/hypr/shells/active.conf"
    fi
    got=$(HOME="$fixture_home" bash -c '. "'"$REPO_DIR"'/scripts/lib/shell-common.sh"; current_shell')
    if [ "$got" = "$want" ]; then
        ok "current_shell: $desc -> $want"
    else
        bad "current_shell: $desc -> want '$want', got '$got'"
    fi
}

# The four active.conf shapes the parser must handle.
expect_current_shell "bare name" "omarchy" "omarchy"
expect_current_shell 'legacy "source =" line' \
    "source = ~/.config/hypr/shells/end4.conf" "end4"
expect_current_shell "comments-only file" \
    "# Written by switch-shell.sh — do not edit by hand

# nothing active" "none"
expect_current_shell "missing file" MISSING "none"

# ── registry: the shell list is a data file ────────────────────────────────
EXPECTED_SHELLS="caelestia ambxst dms noctalia end4 end4pc omarchy xenon glyph ryoku"
got=$(bash -c '. "'"$REPO_DIR"'/scripts/lib/shell-common.sh" && echo "${KNOWN[*]}"')
if [ "$got" = "$EXPECTED_SHELLS" ]; then
    ok "registry: parses to 10 names in order"
else
    bad "registry: want '$EXPECTED_SHELLS', got '$got'"
fi

got=$(HOME=/h bash -c '. "'"$REPO_DIR"'/scripts/lib/shell-common.sh" && shell_config_path caelestia && shell_config_path dms')
if [ "$got" = "/h/.local/share/caelestia/hypr/hyprland.lua
/h/.config/hypr/shells/dms/hyprland.lua" ]; then
    ok "registry: shell_config_path resolves ~/ and hypr-relative records"
else
    bad "registry: shell_config_path wrong: $got"
fi

# Fixture registry via SHELL_REGISTRY — the same override path doctor/tests use.
fixture_registry="$fixture_home/registry"
printf '# comment\n\nalpha|shells/alpha/hyprland.lua|a.svg|Alpha\nbeta|~/b/hyprland.lua|b.svg|Beta\n' >"$fixture_registry"
got=$(SHELL_REGISTRY="$fixture_registry" bash -c '. "'"$REPO_DIR"'/scripts/lib/shell-common.sh" && echo "${KNOWN[*]}"')
if [ "$got" = "alpha beta" ]; then
    ok "registry: SHELL_REGISTRY fixture, comments and blanks skipped"
else
    bad "registry: fixture parse got '$got'"
fi

if err=$(SHELL_REGISTRY="$fixture_home/nonexistent" bash -c '. "'"$REPO_DIR"'/scripts/lib/shell-common.sh"; echo "rc=$? known=${#KNOWN[@]}"' 2>&1) &&
    grep -q 'not readable' <<<"$err" && grep -q 'rc=1 known=0' <<<"$err"; then
    ok "registry: missing file fails loudly with empty KNOWN"
else
    bad "registry: missing-file behaviour wrong: $err"
fi

printf 'broken|only-two\n' >"$fixture_registry"
if SHELL_REGISTRY="$fixture_registry" bash -c '. "'"$REPO_DIR"'/scripts/lib/shell-common.sh"' >/dev/null 2>&1; then
    bad "registry: malformed record was accepted"
else
    ok "registry: malformed record rejected"
fi

# ── lifecycle: switch-shell.sh table covers every registry name ──────────────
SWITCH="$REPO_DIR/scripts/switch-shell.sh"
for name in $EXPECTED_SHELLS; do
    if grep -q "^launch_${name}()" "$SWITCH" && grep -q "^  \[${name}\]=" "$SWITCH"; then
        ok "lifecycle: $name has launch_$name and a MATCH_SPECS entry"
    else
        bad "lifecycle: $name lacks launch_$name or a MATCH_SPECS entry in switch-shell.sh"
    fi
done

# --dry-run must not touch anything: fixture HOME with every shell config
# present, a pre-existing active.conf, and an empty runtime dir (no lock file).
dry_home="$fixture_home/dry"
dry_runtime="$fixture_home/dry-runtime"
mkdir -p "$dry_home/.config/hypr/shells" "$dry_runtime"
for name in $EXPECTED_SHELLS; do
    config=$(HOME="$dry_home" bash -c '. "'"$REPO_DIR"'/scripts/lib/shell-common.sh" && shell_config_path '"$name")
    mkdir -p "$(dirname "$config")"
    : >"$config"
done
printf 'omarchy\n' >"$dry_home/.config/hypr/shells/active.conf"
tree_state() { (cd "$dry_home" && find . "$dry_runtime" -printf '%p %s %T@\n' | sort; cat .config/hypr/shells/active.conf); }
before=$(tree_state)
for name in $EXPECTED_SHELLS; do
    if out=$(HOME="$dry_home" XDG_RUNTIME_DIR="$dry_runtime" "$SWITCH" --dry-run "$name" 2>&1) &&
        grep -q "launch_$name" <<<"$out" && [ "$(tree_state)" = "$before" ]; then
        ok "lifecycle: switch-shell.sh --dry-run $name exits 0, touches nothing"
    else
        bad "lifecycle: switch-shell.sh --dry-run $name failed or modified the fixture"
    fi
done

if [ -x "$REPO_DIR/scripts/doctor.sh" ] && "$REPO_DIR/scripts/doctor.sh" --versions | grep -q '^| Hyprland '; then
    ok "doctor.sh --versions prints the stack table"
else
    bad "doctor.sh missing, not executable, or --versions broken"
fi

# ── drift: modules/*.yaml dotfiles: vs link-dotfiles.sh TARGETS ─────────────
# The YAML `dotfiles:` keys are documentation only — dcli silently ignores
# them and scripts/link-dotfiles.sh does the real linking, so nothing fails
# when they lie. Convert that silent lie into a failing gate.
ALLOWED_DIVERGENCE=(
    wezterm
)
# wezterm (why): dotfiles/wezterm is a SNAPSHOT COPY only. The source of truth
# is the wezterm git repo cloned to ~/.config/wezterm by setup-wezterm.sh —
# linking would shadow that repo (see link-dotfiles.sh header and
# modules/terminal-wezterm.yaml).

targets_line=$(sed -n 's/^TARGETS=(\(.*\))$/\1/p' "$REPO_DIR/scripts/link-dotfiles.sh")
if [ -n "$targets_line" ]; then
    # shellcheck disable=SC2206  # intentional word split of the array literal
    targets=($targets_line)
    ok "link-dotfiles.sh TARGETS parsed: ${targets[*]}"
else
    targets=()
    bad "TARGETS not found in scripts/link-dotfiles.sh"
fi

declared_sources=$(awk '
    indot && /^[^[:space:]]/ { indot = 0 }
    indot && /^  - source:/ {
        src = $0
        sub(/^  - source:[[:space:]]*/, "", src)
        print FILENAME ":" src
    }
    /^dotfiles:[[:space:]]*$/ { indot = 1 }
' "$REPO_DIR"/modules/*.yaml)

if [ -z "$declared_sources" ]; then
    bad "no dotfiles: sources found under modules/ (parser or layout broke?)"
fi

while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    mod=${entry%%:*}
    src=${entry#*:}
    if in_list "$src" "${targets[@]}"; then
        ok "drift: ${mod#"$REPO_DIR"/} source '$src' is linked"
    elif in_list "$src" "${ALLOWED_DIVERGENCE[@]}"; then
        ok "drift: ${mod#"$REPO_DIR"/} source '$src' is an allowed divergence"
    else
        bad "drift: ${mod#"$REPO_DIR"/} source '$src' is in neither link-dotfiles.sh TARGETS nor ALLOWED_DIVERGENCE"
    fi
done <<EOF
$declared_sources
EOF

# ── verdict ──────────────────────────────────────────────────────────────────
if [ "$failures" -eq 0 ]; then
    printf 'smoke: all checks passed\n'
    exit 0
fi
printf 'smoke: %s failure(s)\n' "$failures"
exit 1
