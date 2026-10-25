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
