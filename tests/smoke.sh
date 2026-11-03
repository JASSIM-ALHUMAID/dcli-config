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
#   grub  — the GRUB layer: 42_dcli_shells output through grub-script-check
#           (fixture themes dir + fixture 10_linux), dcli-grub-sync against a
#           fixture staging tree (valid install, hostile inputs refused),
#           install-grub-theme.sh / uninstall-grub-theme.sh into a fixture root,
#           boot-shell.sh consumption rules, the switch-shell.sh hook
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
GRUB_SCRIPTS=("$REPO_DIR/scripts/grub/dcli-grub-sync" "$REPO_DIR/scripts/grub/42_dcli_shells")
parse_targets+=("${GRUB_SCRIPTS[@]}")
SDDM_SYNC="$REPO_DIR/scripts/sddm/dcli-sddm-sync"
parse_targets+=("$SDDM_SYNC")
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

# ── exec: every entry-point script is executable ─────────────────────────────
# dcli runs hooks directly and update-*.sh exec their setup-*.sh, so a missing
# exec bit is "permission denied" at sync time. setup/update for glyph and ryoku
# were committed 100644 and nothing caught it until 2026-10-31. lib/*.sh is
# sourced, never executed, and is not checked.
for f in "$REPO_DIR"/scripts/*.sh; do
    if [ -x "$f" ]; then
        ok "executable ${f#"$REPO_DIR"/}"
    else
        bad "not executable: ${f#"$REPO_DIR"/} (chmod +x, and commit the mode)"
    fi
done

for f in "${GRUB_SCRIPTS[@]}"; do
    if [ -x "$f" ]; then
        ok "executable ${f#"$REPO_DIR"/}"
    else
        bad "not executable: ${f#"$REPO_DIR"/}"
    fi
done

# ── lint: the shellcheck gate ────────────────────────────────────────────────
if command -v "$SHELLCHECK" >/dev/null 2>&1 || [ -x "$SHELLCHECK" ]; then
    if (
        cd "$REPO_DIR" || exit 1
        # scripts/*.sh is the documented gate; lib/*.sh is the shared-code
        # superset — both must be clean.
        "$SHELLCHECK" scripts/*.sh scripts/lib/*.sh scripts/grub/dcli-grub-sync scripts/grub/42_dcli_shells scripts/sddm/dcli-sddm-sync
    ); then
        ok "shellcheck scripts/*.sh scripts/lib/*.sh scripts/grub/*"
    else
        bad "shellcheck scripts/*.sh scripts/lib/*.sh scripts/grub/*"
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

# ── drift: ryoku's launch is defined once ───────────────────────────────────
# launch-ryoku.sh owns the session PATH; setup-ryoku.sh builds into the same
# directory, and both launch points (login, switch) must go through it.
ryoku_bin_of() { sed -n 's|^RYOKU_BIN_DIR="\$[A-Z_]*HOME\(/[^"]*\)"$|\1|p' "$1"; }
launch_bin=$(ryoku_bin_of "$REPO_DIR/scripts/launch-ryoku.sh")
setup_bin=$(ryoku_bin_of "$REPO_DIR/scripts/setup-ryoku.sh")
if [ -n "$launch_bin" ] && [ "$launch_bin" = "$setup_bin" ]; then
    ok "ryoku bin dir agrees: ~$launch_bin"
else
    bad "ryoku bin dir drift: launch-ryoku.sh '~$launch_bin' vs setup-ryoku.sh '~$setup_bin'"
fi
for caller in dotfiles/hypr/shells/ryoku/hyprland/execs.lua scripts/switch-shell.sh; do
    if grep -q 'launch-ryoku\.sh' "$REPO_DIR/$caller"; then
        ok "$caller launches ryoku via launch-ryoku.sh"
    else
        bad "$caller starts ryoku without launch-ryoku.sh"
    fi
done

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

# ── grub: the bootloader theming layer ──────────────────────────────────────
GRUB_SRC="$REPO_DIR/scripts/grub"
grub_fx="$fixture_home/grub"
mkdir -p "$grub_fx"

# 42_dcli_shells against a fixture themes dir and a fixture 10_linux (the real
# one needs grub-probe and root). The fixture entry mirrors 10_linux's output
# shape: a top-level menuentry, then an Advanced submenu that must be ignored.
mkdir -p "$grub_fx/themes/alpha" "$grub_fx/themes/beta-2" "$grub_fx/themes/active" "$grub_fx/themes/_junk"
for t in alpha beta-2 active _junk; do : >"$grub_fx/themes/$t/theme.txt"; done
printf "alpha · Alpha 'quoted' \$x\n" >"$grub_fx/themes/alpha/title.txt"
cat >"$grub_fx/10_linux" <<'FIXTURE'
#!/bin/sh
cat <<'ENTRIES'
menuentry 'Fixture Linux' --class fixture --class gnu-linux --class gnu --class os $menuentry_id_option 'gnulinux-simple-fx' {
	load_video
	search --no-floppy --fs-uuid --set=root fx
	linux	/@/boot/vmlinuz-fixture root=UUID=fx rw rootflags=subvol=@ quiet 
	initrd	/@/boot/initramfs-fixture.img
}
submenu 'Advanced options' $menuentry_id_option 'gnulinux-advanced-fx' {
	menuentry 'Fixture Linux, fallback' $menuentry_id_option 'fx-fb' {
		linux /boot/fallback
	}
}
ENTRIES
FIXTURE
chmod +x "$grub_fx/10_linux"
grub_d_run() {
    DCLI_GRUB_THEMES_DIR="$grub_fx/themes" DCLI_GRUB_10_LINUX="$grub_fx/10_linux" \
        DCLI_GRUB_THEMES_URI=/@/boot/grub/themes/dcli GRUB_DISTRIBUTOR=Fixture "$GRUB_SRC/42_dcli_shells"
}
grub_d_out=$(grub_d_run)
if grep -q "dcli.shell=alpha\$" <<<"$grub_d_out" && grep -q "dcli.shell=beta-2\$" <<<"$grub_d_out" &&
    ! grep -q '_junk\|dcli-shell-active\|fallback' <<<"$grub_d_out" &&
    grep -q "^	submenu 'alpha · Alpha quoted x'" <<<"$grub_d_out"; then
    ok "grub: 42_dcli_shells emits one boot entry per shell, dcli.shell appended, active/junk skipped"
else
    bad "grub: 42_dcli_shells output wrong: $grub_d_out"
fi
if command -v grub-script-check >/dev/null 2>&1; then
    if grub-script-check <<<"$grub_d_out"; then
        ok "grub: 42_dcli_shells output passes grub-script-check"
    else
        bad "grub: 42_dcli_shells output fails grub-script-check"
    fi
else
    ok "grub: grub-script-check not installed — script check skipped"
fi
rm -f "$grub_fx/10_linux"
printf '#!/bin/sh\necho "nothing useful"\n' >"$grub_fx/10_linux"
chmod +x "$grub_fx/10_linux"
if [ -z "$(grub_d_run)" ]; then
    ok "grub: 42_dcli_shells prints nothing when 10_linux yields no entry"
else
    bad "grub: 42_dcli_shells emitted output without a derivable boot entry"
fi

# dcli-grub-sync: non-root, reading with `env` instead of setpriv, into a
# fixture destination. Same code path as the installed helper otherwise.
staging="$grub_fx/staging"
sync_dest="$grub_fx/dest"
sync_run() {
    DCLI_GRUB_ALLOW_NONROOT=1 DCLI_GRUB_DEST="$sync_dest" DCLI_GRUB_READER=env \
        DCLI_GRUB_MKCONFIG="touch $grub_fx/mkconfig-ran" \
        "$GRUB_SRC/dcli-grub-sync" --user "$(id -un)" --staging "$staging" 2>&1
}
png_bytes() { printf '\x89PNG\r\n\x1a\n\0\0\0\0'; }
jpg_bytes() { printf '\xff\xd8\xff\xe0\0\0'; }
stage_shell() {
    local d="$staging/$1"
    mkdir -p "$d/icons"
    png_bytes >"$d/pane.png"
    png_bytes >"$d/icons/os.png"
    jpg_bytes >"$d/background.jpg"
    printf 'desktop-image: "background.jpg"\n+ boot_menu { left = 10%% }\n' >"$d/theme.txt"
    printf '%s · Fixture\n' "$1" >"$d/title.txt"
    : >"$d/.complete"
}
mkdir -p "$staging/fonts"
printf 'FILE\0\0\0\4PFF2fixture' >"$staging/fonts/fixture.pf2"
printf 'fixture|fixture.pf2|Fixture Regular 22\n' >"$staging/fonts/MANIFEST"
stage_shell alpha
stage_shell beta
echo alpha >"$staging/active"
png_bytes >"$staging/alpha/preview.png"
if out=$(sync_run) && [ -f "$sync_dest/alpha/theme.txt" ] && [ -f "$sync_dest/beta/icons/os.png" ] &&
    [ -f "$sync_dest/active/fixture.pf2" ] && [ -f "$sync_dest/active/theme.txt" ] &&
    [ "$(cat "$sync_dest/active/.dcli-shell")" = alpha ] && [ ! -e "$sync_dest/alpha/preview.png" ] &&
    [ ! -e "$sync_dest/active/MANIFEST" ] &&
    [ ! -e "$sync_dest/alpha/.complete" ] && [ -f "$grub_fx/mkconfig-ran" ] &&
    [ "$(stat -c %a "$sync_dest/alpha/theme.txt")" = 644 ]; then
    ok "grub: dcli-grub-sync installs shells + active/ (fonts merged), previews + font MANIFEST skipped, grub.cfg regenerated"
else
    bad "grub: dcli-grub-sync valid install failed: $out"
fi
rm -f "$grub_fx/mkconfig-ran"
if out=$(sync_run) && [ ! -f "$grub_fx/mkconfig-ran" ]; then
    ok "grub: dcli-grub-sync leaves grub.cfg alone when the shell set is unchanged"
else
    bad "grub: dcli-grub-sync re-ran mkconfig for an unchanged shell set: $out"
fi
rm -rf "$staging/beta"
if out=$(sync_run) && [ ! -e "$sync_dest/beta" ] && [ -f "$grub_fx/mkconfig-ran" ]; then
    ok "grub: dcli-grub-sync drops shells that are no longer staged"
else
    bad "grub: dcli-grub-sync kept a removed shell: $out"
fi

# Hostile or malformed staging must be refused with the previous install intact.
expect_sync_refusal() {
    local desc="$1" before after
    before=$(cd "$sync_dest" && find . -type f -exec cksum {} + | sort)
    if out=$(sync_run); then
        bad "grub: dcli-grub-sync accepted $desc"
    else
        after=$(cd "$sync_dest" && find . -type f -exec cksum {} + | sort)
        if [ "$before" = "$after" ]; then
            ok "grub: dcli-grub-sync refuses $desc, installed tree untouched"
        else
            bad "grub: dcli-grub-sync refused $desc but changed the installed tree"
        fi
    fi
}
ln -s /etc/passwd "$staging/alpha/evil.png"
expect_sync_refusal "a symlink member"
rm -f "$staging/alpha/evil.png"
ln "$staging/alpha/pane.png" "$staging/alpha/hard.png"
expect_sync_refusal "a hardlink member"
rm -f "$staging/alpha/hard.png"
echo "not a png" >"$staging/alpha/fake.png"
expect_sync_refusal "a .png without PNG magic"
rm -f "$staging/alpha/fake.png"
echo '#!/bin/sh' >"$staging/alpha/run.sh"
expect_sync_refusal "a disallowed file type"
rm -f "$staging/alpha/run.sh"
printf 'x: "../../etc/shadow"\n' >>"$staging/alpha/theme.txt"
expect_sync_refusal "a theme.txt reference that escapes its directory"
printf 'desktop-image: "background.jpg"\n' >"$staging/alpha/theme.txt"
mv "$staging/alpha/.complete" "$grub_fx/.complete-held"
expect_sync_refusal "a shell without its .complete marker"
mv "$grub_fx/.complete-held" "$staging/alpha/.complete"
if out=$(sync_run); then
    ok "grub: dcli-grub-sync accepts the staging tree again once it is clean"
else
    bad "grub: dcli-grub-sync rejected a clean tree: $out"
fi
if DCLI_GRUB_ALLOW_NONROOT= DCLI_GRUB_DEST="$sync_dest" "$GRUB_SRC/dcli-grub-sync" --user "$(id -un)" --staging "$staging" >/dev/null 2>&1; then
    bad "grub: dcli-grub-sync ran without root"
else
    ok "grub: dcli-grub-sync refuses to run without root"
fi

# Wallpaper sources (lib/wallpaper.sh) against a fixture $HOME: every record
# kind, ~ expansion, first-existing-wins fallback, and "no wallpaper".
wp_home="$grub_fx/wp-home"
mkdir -p "$wp_home/pics" "$wp_home/.local/state/caelestia/wallpaper" "$wp_home/.local/state/dms" \
    "$wp_home/.local/state/noctalia" "$wp_home/.local/state/omarchy/current" "$wp_home/.local/state/rice" \
    "$wp_home/.local/share/xenon-shell/Assets"
for f in a b c d x; do png_bytes >"$wp_home/pics/$f.png"; done
echo "$wp_home/pics/a.png" >"$wp_home/.local/state/caelestia/wallpaper/path.txt"
printf '{"wallpaperPath":"%s"}\n' "$wp_home/pics/b.png" >"$wp_home/.local/state/dms/session.json"
printf '[wallpaper]\nx = 1\n\n    [wallpaper.default]\n    path = "%s"\n\n    [wallpaper.last]\n    path = "%s"\n' \
    "$wp_home/pics/a.png" "$wp_home/pics/c.png" >"$wp_home/.local/state/noctalia/settings.toml"
ln -s "$wp_home/pics/d.png" "$wp_home/.local/state/omarchy/current/background"
png_bytes >"$wp_home/.local/share/xenon-shell/Assets/default_wallpaper.png"
echo '~/pics/x.png' >"$wp_home/.local/state/ryoku-wallpaper"
printf '{"wall":""}\n' >"$wp_home/.local/state/rice/glyph.json"
wp_of() { SHELL_WALLPAPER_HOME="$wp_home" bash -c '. "'"$REPO_DIR"'/scripts/lib/wallpaper.sh"; shell_wallpaper "$1"' _ "$1"; }
if [ "$(wp_of caelestia)" = "$wp_home/pics/a.png" ] && [ "$(wp_of dms)" = "$wp_home/pics/b.png" ] &&
    [ "$(wp_of noctalia)" = "$wp_home/pics/c.png" ] && [ "$(wp_of omarchy)" = "$wp_home/pics/d.png" ] &&
    [ "$(wp_of ryoku)" = "$wp_home/pics/x.png" ] &&
    [ "$(wp_of xenon)" = "$wp_home/.local/share/xenon-shell/Assets/default_wallpaper.png" ] &&
    [ -z "$(wp_of glyph)" ] && [ -z "$(wp_of ambxst)" ] && [ -z "$(wp_of no-such-shell)" ]; then
    ok "wallpaper: text/json/toml section/link/~ records resolve; xenon falls back to its default; empty and absent give none"
else
    bad "wallpaper: shell_wallpaper resolved a fixture wrongly"
fi
missing_records=""
mapfile -t registry_shells < <(bash -c '. "'"$REPO_DIR"'/scripts/lib/shell-common.sh" && printf "%s\n" "${KNOWN[@]}"')
[ "${#registry_shells[@]}" -gt 0 ] || missing_records=" (registry unreadable)"
for name in "${registry_shells[@]}"; do
    grep -q "^    \"$name|" "$REPO_DIR/scripts/lib/wallpaper.sh" || missing_records+=" $name"
done
if [ -z "$missing_records" ]; then
    ok "wallpaper: every registry shell has a WALLPAPER_SOURCES record"
else
    bad "wallpaper: no WALLPAPER_SOURCES record for:$missing_records (GRUB would draw a gradient)"
fi

# Installer + shared status helper in a fixture root (no systemctl, no sync, no
# grub-mkconfig under DCLI_INSTALL_ROOT).
inst_root="$grub_fx/root"
mkdir -p "$inst_root/etc/default"
printf 'GRUB_TIMEOUT=5\nGRUB_THEME=/boot/grub/themes/old/theme.txt\n' >"$inst_root/etc/default/grub"
installer="$REPO_DIR/scripts/install-grub-theme.sh"
uninstaller="$REPO_DIR/scripts/uninstall-grub-theme.sh"
grub_problems() { DCLI_INSTALL_ROOT="$inst_root" bash -c '. "'"$REPO_DIR"'/scripts/lib/grub-common.sh"; grub_integration_problems'; }
if [ -n "$(grub_problems)" ]; then
    ok "grub: status helper reports a missing install"
else
    bad "grub: status helper called an empty root current"
fi
if DCLI_INSTALL_ROOT="$inst_root" "$installer" >/dev/null 2>&1 &&
    cmp -s "$inst_root/usr/local/libexec/dcli-grub-sync" "$GRUB_SRC/dcli-grub-sync" &&
    cmp -s "$inst_root/etc/grub.d/42_dcli_shells" "$GRUB_SRC/42_dcli_shells" &&
    grep -q "^ExecStart=/usr/local/libexec/dcli-grub-sync --user $(id -un) --staging $REPO_DIR/state/grub-theme\$" \
        "$inst_root/etc/systemd/system/dcli-grub-theme.service" &&
    grep -q '^GRUB_THEME="/boot/grub/themes/dcli/active/theme.txt"$' "$inst_root/etc/default/grub" &&
    [ "$(grep -c '^GRUB_THEME=' "$inst_root/etc/default/grub")" = 1 ] &&
    ! grep -q '@[A-Z]*@' "$inst_root"/etc/systemd/system/dcli-grub-theme.*; then
    ok "grub: installer lays out helper, grub.d script, substituted units, one GRUB_THEME line"
else
    bad "grub: installer fixture run failed or produced a wrong layout"
fi
units="$inst_root/user-units"
if grep -qx "ExecStart=$REPO_DIR/scripts/render-grub-theme.sh --changed all" "$units/dcli-grub-render.service" &&
    [ "$(grep -c '^PathChanged=' "$units/dcli-grub-render.path")" = "$(DCLI_INSTALL_ROOT="$inst_root" bash -c '. "'"$REPO_DIR"'/scripts/lib/wallpaper.sh"; wallpaper_state_files' | wc -l)" ] &&
    ! grep -q '@[A-Z_]*@' "$units"/dcli-grub-render.*; then
    ok "grub: installer writes the user render units, one PathChanged per wallpaper state file"
else
    bad "grub: user render units missing, unsubstituted or not watching every wallpaper state file"
fi
if [ -z "$(grub_problems)" ]; then
    ok "grub: status helper calls the installed fixture current"
else
    bad "grub: status helper still reports problems: $(grub_problems)"
fi
if DCLI_INSTALL_ROOT="$inst_root" "$installer" >/dev/null 2>&1 &&
    [ "$(cat "$inst_root/var/lib/dcli-grub/previous-grub-theme")" = 'GRUB_THEME=/boot/grub/themes/old/theme.txt' ] &&
    [ "$(grep -c '^GRUB_THEME=' "$inst_root/etc/default/grub")" = 1 ]; then
    ok "grub: a re-install keeps the remembered pre-install GRUB_THEME"
else
    bad "grub: a re-install overwrote the remembered GRUB_THEME or duplicated the line"
fi
if DCLI_INSTALL_ROOT="$inst_root" "$uninstaller" >/dev/null 2>&1 &&
    [ ! -e "$inst_root/usr/local/libexec/dcli-grub-sync" ] && [ ! -e "$inst_root/etc/grub.d/42_dcli_shells" ] &&
    [ ! -e "$inst_root/etc/systemd/system/dcli-grub-theme.path" ] &&
    [ ! -e "$inst_root/user-units/dcli-grub-render.path" ] &&
    grep -qx 'GRUB_THEME=/boot/grub/themes/old/theme.txt' "$inst_root/etc/default/grub"; then
    ok "grub: uninstaller removes everything and restores the previous GRUB_THEME"
else
    bad "grub: uninstaller left files behind or lost the previous GRUB_THEME"
fi
for script in "$installer" "$uninstaller"; do
    if DCLI_INSTALL_ROOT="$inst_root" "$script" --bogus >/dev/null 2>&1; then
        bad "grub: ${script##*/} accepted an unknown argument"
    else
        ok "grub: ${script##*/} rejects an unknown argument"
    fi
done
if [ "$(DCLI_INSTALL_ROOT="$inst_root" bash -c '. "'"$REPO_DIR"'/scripts/lib/grub-common.sh"; grub_module_packages' | head -n1)" = grub ]; then
    ok "grub: grub_module_packages reads modules/grub-theme.yaml"
else
    bad "grub: grub_module_packages returned nothing from modules/grub-theme.yaml"
fi
for unit in dcli-grub-theme.path dcli-grub-theme.service; do
    if grep -q '@STAGING@' "$GRUB_SRC/$unit"; then
        ok "grub: unit template $unit carries its @STAGING@ placeholder"
    else
        bad "grub: unit template $unit lost its @STAGING@ placeholder"
    fi
done

# boot-shell.sh: run from a copy next to a stub switch-shell.sh so a real
# switch can never fire. Fixture registry, cmdline, boot id and state dir.
bs_dir="$grub_fx/bootshell"
mkdir -p "$bs_dir/scripts" "$bs_dir/home/.config/hypr/shells"
cp "$REPO_DIR/scripts/boot-shell.sh" "$bs_dir/scripts/"
cp -r "$REPO_DIR/scripts/lib" "$bs_dir/scripts/lib"
printf '#!/bin/bash\necho "$1" >>"%s/switched"\n' "$bs_dir" >"$bs_dir/scripts/switch-shell.sh"
chmod +x "$bs_dir/scripts/"*.sh
printf 'alpha|a|a.svg|A\nbeta|b|b.svg|B\n' >"$bs_dir/registry"
printf 'alpha\n' >"$bs_dir/home/.config/hypr/shells/active.conf"
boot_shell_run() {
    printf '%s\n' "$1" >"$bs_dir/cmdline"
    printf '%s\n' "$2" >"$bs_dir/bootid"
    HOME="$bs_dir/home" SHELL_REGISTRY="$bs_dir/registry" DCLI_CMDLINE_FILE="$bs_dir/cmdline" \
        DCLI_BOOT_ID_FILE="$bs_dir/bootid" DCLI_BOOT_STATE_DIR="$bs_dir/state" DCLI_BOOT_SHELL_NO_WAIT=1 \
        "$bs_dir/scripts/boot-shell.sh" 2>/dev/null
}
boot_shell_run "quiet dcli.shell=beta" boot-1
boot_shell_run "quiet dcli.shell=beta" boot-1
if [ "$(cat "$bs_dir/switched" 2>/dev/null)" = beta ]; then
    ok "boot-shell: dcli.shell=beta switches once per boot id"
else
    bad "boot-shell: expected exactly one switch to beta, got '$(cat "$bs_dir/switched" 2>/dev/null)'"
fi
rm -f "$bs_dir/switched"
boot_shell_run "dcli.shell=beta" boot-2
rm -f "$bs_dir/switched"
boot_shell_run "dcli.shell=alpha" boot-3
boot_shell_run "dcli.shell=nonsense" boot-4
boot_shell_run "quiet" boot-5
if [ ! -e "$bs_dir/switched" ] && [ "$(cat "$bs_dir/state/boot-shell")" = boot-4 ]; then
    ok "boot-shell: current, unknown and absent parameters switch nothing; consumption recorded"
else
    bad "boot-shell: switched when it should not have"
fi

# switch-shell.sh: the detached non-fatal render hook, skip switch, plan line.
HOOK="$REPO_DIR/scripts/switch-shell.sh"
if grep -q '^grub_theme_render "\$SHELL_NAME"$' "$HOOK" && grep -q 'DCLI_SKIP_GRUB_THEME' "$HOOK" &&
    grep -q 'setsid -f "\$GRUB_RENDERER" --active' "$HOOK" &&
    out=$(HOME="$dry_home" XDG_RUNTIME_DIR="$dry_runtime" "$HOOK" --dry-run omarchy 2>&1) &&
    grep -q 'grub theme (detached, non-fatal)' <<<"$out"; then
    ok "grub: switch-shell.sh renders the GRUB theme detached and non-fatal; dry-run plan lists it"
else
    bad "grub: switch-shell.sh GRUB hook or dry-run plan line missing"
fi

# Hyprland entry point: boot-shell.sh is launched from hyprland.start only.
if [ "$(grep -c 'exec_cmd.*boot-shell.sh' "$REPO_DIR/dotfiles/hypr/hyprland.lua")" = 1 ] &&
    grep -B1 'exec_cmd.*boot-shell.sh' "$REPO_DIR/dotfiles/hypr/hyprland.lua" | grep -q 'hl.on("hyprland.start"'; then
    ok "grub: hyprland.lua starts boot-shell.sh from hyprland.start (not on reload)"
else
    bad "grub: hyprland.lua does not launch boot-shell.sh from hl.on(\"hyprland.start\")"
fi

# ── sddm: the login-screen theming layer ────────────────────────────────────
sddm_fx="$fixture_home/sddm"
mapfile -t SDDM_SHELLS < <(grep -v '^[[:space:]]*\(#.*\)\?$' "$REPO_DIR/dotfiles/hypr/shells/registry" | cut -d'|' -f1)
mkdir -p "$sddm_fx/home/.local/state/dcli"
if command -v magick >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    # Render every shell into a fixture stage with an empty HOME: no live palette
    # files, no wallpapers -> the static fallbacks and generated background.
    if HOME="$sddm_fx/home" SHELL_WALLPAPER_HOME="$sddm_fx/home" DCLI_SDDM_STAGE="$sddm_fx/stage" \
        "$REPO_DIR/scripts/render-sddm-theme.sh" --active glyph all >/dev/null 2>&1 &&
        [ "$(cat "$sddm_fx/stage/active")" = glyph ] && [ -f "$sddm_fx/stage/.stamp" ] &&
        [ "$(find "$sddm_fx/stage" -name .complete | wc -l)" -eq "${#SDDM_SHELLS[@]}" ]; then
        ok "sddm: renderer stages every registry shell and the active file"
    else
        bad "sddm: renderer did not stage every shell"
    fi
    if grep -q '^primary=#d71921' "$sddm_fx/stage/glyph/theme.conf.user"; then
        ok "sddm: glyph keeps its fixed palette"
    else
        bad "sddm: glyph palette wrong"
    fi
    # Sync into a fixture themes root, reading as ourselves.
    for n in "${SDDM_SHELLS[@]}"; do mkdir -p "$sddm_fx/themes/dcli-$n"; done
    sync_run() {
        DCLI_SDDM_ALLOW_NONROOT=1 DCLI_SDDM_READER=env DCLI_SDDM_THEMES_DIR="$sddm_fx/themes" \
            DCLI_SDDM_CONF_DIR="$sddm_fx/conf.d" DCLI_SDDM_GREETER_CACHE="$sddm_fx/cache" \
            "$SDDM_SYNC" --user "$(id -un)" --staging "$sddm_fx/stage" 2>&1
    }
    if sync_run >/dev/null && grep -qx 'Current=dcli-glyph' "$sddm_fx/conf.d/zz-dcli-theme.conf" &&
        [ -f "$sddm_fx/themes/dcli-xenon/theme.conf.user" ] && [ -f "$sddm_fx/themes/dcli-xenon/assets/background.jpg" ]; then
        ok "sddm: sync installs data into every theme and writes Current="
    else
        bad "sddm: sync failed on a valid staging tree"
    fi
    # Hostile staging: a symlink, a bad conf line and a non-JPEG must each be refused.
    printf 'Exec=/bin/evil\nx="$(id)"\n' >"$sddm_fx/stage/xenon/theme.conf.user"
    printf 'notajpeg' >"$sddm_fx/stage/ambxst/background.jpg"
    out=$(sync_run) && rc=0 || rc=$?
    if [ "$rc" -ne 0 ] && grep -q 'xenon: theme.conf.user missing or invalid' <<<"$out" &&
        grep -q 'ambxst: background.jpg missing or not a JPEG' <<<"$out" &&
        ! grep -q evil "$sddm_fx/themes/dcli-xenon/theme.conf.user"; then
        ok "sddm: sync refuses a hostile conf line and a fake JPEG, keeps the old data"
    else
        bad "sddm: sync accepted hostile staging: $out"
    fi
    ln -sf /etc/passwd "$sddm_fx/stage/dms/background.jpg"
    if out=$(sync_run); then
        bad "sddm: sync accepted a staging tree holding a symlink"
    elif grep -q 'members other than files and directories' <<<"$out"; then
        ok "sddm: sync refuses a whole staging tree that carries a symlink"
    else
        bad "sddm: symlink refusal had the wrong reason: $out"
    fi
    # Installer + uninstaller into a fixture root.
    inst_root="$sddm_fx/root"
    if DCLI_INSTALL_ROOT="$inst_root" "$REPO_DIR/scripts/install-sddm-theme.sh" >/dev/null 2>&1 &&
        [ -f "$inst_root/usr/share/sddm/themes/dcli-omarchy/entry.png" ] &&
        [ -f "$inst_root/usr/share/sddm/themes/dcli-xenon/components/Palette.qml" ] &&
        [ -f "$inst_root/usr/share/sddm/themes/dcli-caelestia/components/Greeting.qml" ] &&
        grep -qxF "PathChanged=$(readlink -m "$REPO_DIR/state/sddm-theme")/.stamp" "$inst_root/etc/systemd/system/dcli-sddm-theme.path" &&
        DCLI_INSTALL_ROOT="$inst_root" "$REPO_DIR/scripts/uninstall-sddm-theme.sh" >/dev/null 2>&1 &&
        [ ! -e "$inst_root/usr/share/sddm/themes/dcli-xenon" ]; then
        ok "sddm: installer lays down one theme per shell + units; uninstaller removes them"
    else
        bad "sddm: install/uninstall into a fixture root failed"
    fi
else
    ok "sddm: skipped (imagemagick or jq missing)"
fi
if grep -q 'sddm_theme_render "\$SHELL_NAME"' "$REPO_DIR/scripts/switch-shell.sh" &&
    "$REPO_DIR/scripts/switch-shell.sh" --dry-run glyph 2>/dev/null | grep -q '^sddm theme (detached'; then
    ok "sddm: switch-shell.sh renders the SDDM theme detached; dry-run plan lists it"
else
    bad "sddm: switch-shell.sh SDDM hook or dry-run plan line missing"
fi

# ── terminal: every shell has a prompt and a fastfetch config ────────────────
# Static: each registry shell resolves to an upstream path (read live from its
# checkout) or a committed dotfiles/terminal template. Every template (main and
# _alt) must render with nothing left unfilled and yield configs fastfetch and
# starship accept; a live palette file must reach the rendered output, and
# --refresh must pick up a palette change. apply-terminal-theme.sh retargets
# fixture links without touching real files, and backs up (never deletes) a real
# file in the way. All rendering goes to a fixture TERMINAL_STATE_DIR, never the
# repo's state/.
terminal_missing=""
for name in "${registry_shells[@]}"; do
    for tool in starship fastfetch; do
        has=$(bash -c '. "'"$REPO_DIR"'/scripts/lib/terminal-theme.sh"
            if [ "'"$tool"'" = starship ]; then
                [ -n "${UPSTREAM_STARSHIP['"$name"']:-}" ] || [ -f "$TERMINAL_DOTFILES_DIR/'"$name"'/starship.toml" ] && echo y
            else
                [ -n "${UPSTREAM_FASTFETCH['"$name"']:-}" ] || [ -f "$TERMINAL_DOTFILES_DIR/'"$name"'/fastfetch/config.jsonc" ] && echo y
            fi')
        [ "$has" = y ] || terminal_missing="$terminal_missing $name/$tool"
    done
done
if [ -z "$terminal_missing" ]; then
    ok "terminal: every registry shell has a starship and a fastfetch source"
else
    bad "terminal: no source for:$terminal_missing"
fi

t_home="$fixture_home/term"
t_state="$fixture_home/term-state"
mkdir -p "$t_home/.config/hypr/shells"
# render_all: every template with the fixture home's palette; prints failures.
t_render_all=$(HOME="$t_home" TERMINAL_STATE_DIR="$t_state" bash -c '
    . "'"$REPO_DIR"'/scripts/lib/wallpaper.sh" && . "'"$REPO_DIR"'/scripts/lib/palette.sh" &&
    . "'"$REPO_DIR"'/scripts/lib/terminal-theme.sh" || exit 1
    for src in "$TERMINAL_DOTFILES_DIR"/*/starship.toml "$TERMINAL_DOTFILES_DIR"/*/fastfetch \
               "$TERMINAL_DOTFILES_DIR"/_alt/*/starship.toml "$TERMINAL_DOTFILES_DIR"/_alt/*/fastfetch; do
        [ -e "$src" ] || continue
        rel=${src#"$TERMINAL_DOTFILES_DIR"/}; shell=${rel#_alt/}; shell=${shell%%/*}
        terminal_render "$shell" "$src" 2>/dev/null || { echo "render:$rel"; continue; }
        out=$(terminal_rendered_path "$src")
        grep -rq "{{" "$out" && echo "unfilled:$rel"
        if [ -d "$out" ]; then
            command -v fastfetch >/dev/null 2>&1 || continue
            [ -z "$(fastfetch -c "$out/config.jsonc" --logo "$out/logo.txt" --pipe true 2>&1 >/dev/null)" ] || echo "fastfetch:$rel"
        else
            command -v starship >/dev/null 2>&1 || continue
            STARSHIP_CONFIG="$out" starship prompt --status=1 --cmd-duration=5000 2>&1 | grep -qi "warn\|error" && echo "starship:$rel"
        fi
    done' 2>&1)
if [ -z "$t_render_all" ]; then
    ok "terminal: every template renders cleanly (fastfetch + starship accept the output)"
else
    bad "terminal: template problems: $(echo "$t_render_all" | tr '\n' ' ')"
fi

# A live palette must reach the rendered prompt, and --refresh must follow it.
xenon_palette() { # <primary hex>
    mkdir -p "$t_home/.cache/xenon"
    jq -n --arg p "$1" '{colors: ({background:"#101010",surface:"#101010",surface_container:"#202020",
        surface_variant:"#303030",on_surface:"#eeeeee",primary:$p,on_primary:"#000000",secondary:"#aaaaaa",
        tertiary:"#bbbbbb",error:"#ff0000",outline:"#777777"} | map_values({dark: .}))}' >"$t_home/.cache/xenon/colors.json"
}
printf 'xenon\n' >"$t_home/.config/hypr/shells/active.conf"
printf 'user prompt\n' >"$t_home/.config/starship.toml"
xenon_palette "#12ab34"
t_apply() { HOME="$t_home" TERMINAL_STATE_DIR="$t_state" "$REPO_DIR/scripts/apply-terminal-theme.sh" "$@" >/dev/null 2>&1; }
if t_apply xenon &&
    [ -L "$t_home/.config/starship.toml" ] &&
    [ "$(readlink -f "$t_home/.config/starship.toml")" = "$t_state/render/main/xenon/starship.toml" ] &&
    [ "$(readlink -f "$t_home/.config/fastfetch")" = "$t_state/render/main/xenon/fastfetch" ] &&
    grep -q 'user prompt' "$t_home"/.config/starship.toml.bak-* &&
    grep -q '#12ab34' "$t_home/.config/starship.toml" &&
    t_apply noctalia &&
    [ "$(readlink -f "$t_home/.config/starship.toml")" = "$t_state/render/main/noctalia/starship.toml" ]; then
    ok "terminal: apply renders with the live palette, links, backs up a real file, retargets"
else
    bad "terminal: apply-terminal-theme.sh fixture run failed"
fi
t_apply xenon
xenon_palette "#fe0dcb"
if t_apply --refresh && grep -q '#fe0dcb' "$t_home/.config/starship.toml"; then
    ok "terminal: --refresh re-renders when the shell's palette changes"
else
    bad "terminal: --refresh did not pick up the new palette"
fi
t_alt=$(HOME="$t_home" TERMINAL_STATE_DIR="$t_state" "$REPO_DIR/scripts/apply-terminal-theme.sh" --dry-run --alt caelestia 2>&1)
if grep -q "render/alt/caelestia/starship.toml" <<<"$t_alt" && grep -q "render/alt/caelestia/fastfetch" <<<"$t_alt"; then
    ok "terminal: --alt resolves the opt-in alternates"
else
    bad "terminal: --alt did not pick _alt/caelestia: $t_alt"
fi
# (re-applying caelestia after --use upstream fails here by design: the fixture
# has no caelestia checkout, so the link is left alone and the exit is non-zero)
printf 'caelestia\n' >"$t_home/.config/hypr/shells/active.conf"
if t_apply --use alt && [ -e "$t_state/prefer-alt" ] &&
    [ "$(readlink -f "$t_home/.config/starship.toml")" = "$t_state/render/alt/caelestia/starship.toml" ] &&
    t_apply noctalia && [ "$(readlink -f "$t_home/.config/starship.toml")" = "$t_state/render/main/noctalia/starship.toml" ] &&
    { t_apply --use upstream || true; } && [ ! -e "$t_state/prefer-alt" ]; then
    ok "terminal: --use alt persists across switches (a shell without one keeps ours); --use upstream ends it"
else
    bad "terminal: --use alt|upstream did not persist or reset"
fi
t_bad_dir="$fixture_home/term-bad"
mkdir -p "$t_bad_dir/xenon"
printf 'format = "{{nosuchkey}}"\n' >"$t_bad_dir/xenon/starship.toml"
if HOME="$t_home" TERMINAL_STATE_DIR="$fixture_home/term-bad-state" TERMINAL_DOTFILES_DIR="$t_bad_dir" bash -c '
    . "'"$REPO_DIR"'/scripts/lib/wallpaper.sh"; . "'"$REPO_DIR"'/scripts/lib/palette.sh"; . "'"$REPO_DIR"'/scripts/lib/terminal-theme.sh"
    ! terminal_render xenon "$TERMINAL_DOTFILES_DIR/xenon/starship.toml" 2>/dev/null &&
    [ ! -e "$TERMINAL_RENDER_DIR/main/xenon/starship.toml" ]'; then
    ok "terminal: an unknown palette token fails the render and ships nothing"
else
    bad "terminal: unknown palette token was rendered"
fi
if grep -q 'terminal_theme_apply "\$SHELL_NAME"' "$REPO_DIR/scripts/switch-shell.sh"; then
    ok "terminal: switch-shell.sh applies the terminal theme"
else
    bad "terminal: switch-shell.sh terminal hook missing"
fi

# ── verdict ──────────────────────────────────────────────────────────────────
if [ "$failures" -eq 0 ]; then
    printf 'smoke: all checks passed\n'
    exit 0
fi
printf 'smoke: %s failure(s)\n' "$failures"
exit 1
