# ml4w Quickshell Shell Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the ML4W OS quickshell config (`mylinuxforwork/dotfiles`) as a ninth switchable shell, run as the named quickshell config `ml4w`, following the repo's established per-shell pattern.

**Architecture:** Clone `mylinuxforwork/dotfiles` @ `main` into `~/.local/share/ml4w-dotfiles`. Symlink `~/.config/quickshell/ml4w` → the checkout's `dotfiles/.config/quickshell` so `qs -c ml4w` runs it. Seed `~/.config/ml4w` + `~/.config/ml4w-statusbar` as machine-local copies (apps write into them). Track a `matugen-ml4w` matugen config in dcli that writes `~/.config/ml4w/colors/colors.json`. Own the Hyprland Lua config under `dotfiles/hypr/shells/ml4w/`. Register in `switch-shell.sh` (named config launch + IPC binds for bar/launcher/etc.).

**Tech Stack:** bash, YAML (dcli modules), Lua (Hyprland config), QML (upstream, untouched), matugen, quickshell.

## Global Constraints

Copied verbatim from the spec `docs/superpowers/specs/2026-08-02-ml4w-quickshell-shell-design.md`:

- **Never run the ML4W installer** (`bash <(curl -s https://ml4w.com/os/stable)`). It is a whole-dotfiles installer that overwrites dcli-symlinked configs.
- **Never declare `quickshell`/`quickshell-git` in `shell-ml4w.yaml`** — the provider has exactly one owner (`shells-quickshell{,-git}.yaml`). ml4w is plain QML and runs on whichever provider is enabled (quickshell-git is default).
- **Never touch `~/.config/matugen`** — it is a symlink into the end4 checkout (owned by `shell-end4`). ml4w uses the separate `~/.config/matugen-ml4w`.
- `~/.config/ml4w` and `~/.config/ml4w-statusbar` are **real seeded dirs**, not dcli symlinks and not checkout symlinks. `~/.config/quickshell/ml4w` IS a checkout symlink. `~/.config/matugen-ml4w` IS a dcli dotfile symlink.
- Checkout tracks `main` directly, no personal fork (like end4pc/omarchy/xenon).
- Every task's `dotfiles:` YAML keys are documentation only — `scripts/link-dotfiles.sh` does the real linking.

---

### Task 1: ml4w picker icon

**Files:**
- Create: `dotfiles/fuzzel/shell-icons/ml4w.svg`

**Interfaces:**
- Produces: `dotfiles/fuzzel/shell-icons/ml4w.svg` — referenced by index 9 of `icon_files` in `switch-shell.sh` (Task 7). Lands at `~/.config/fuzzel/shell-icons/ml4w.svg` via the existing fuzzel dir symlink.

- [ ] **Step 1: Create the SVG**

```xml
<?xml version="1.0" encoding="utf-8"?>
<svg width="800px" height="800px" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect x="1" y="1" width="22" height="22" rx="5" fill="#1e293b"/>
  <path d="M6 17V7l6 6 6-6v10" stroke="#38bdf8" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
```

(A dark slate rounded tile with a sky-blue "M" monogram — the ML4W brand colors. Reads well on the dark fuzzel picker at icon size; swap for the real logo later if desired.)

- [ ] **Step 2: Verify it is valid XML**

Run: `python3 -c "import xml.dom.minidom as m; m.parse('dotfiles/fuzzel/shell-icons/ml4w.svg'); print('ok')"`
Expected: prints `ok`

- [ ] **Step 3: Commit**

```bash
git add dotfiles/fuzzel/shell-icons/ml4w.svg
git commit -m "feat(ml4w): add shell-picker icon"
```

---

### Task 2: `matugen-ml4w` config + colors template

**Files:**
- Create: `dotfiles/matugen-ml4w/config.toml`
- Create: `dotfiles/matugen-ml4w/templates/colors.json`

**Interfaces:**
- Produces: `~/.config/matugen-ml4w/config.toml` (symlink target of the dcli dotfile) — consumed by `setup-ml4w.sh` (Task 4) and `execs.lua` (Task 6) as `matugen -c ~/.config/matugen-ml4w/config.toml <wallpaper>`. The template's output lands at `~/.config/ml4w/colors/colors.json`, which ml4w's `CustomTheme/Theme.qml` reads.

- [ ] **Step 1: Create `dotfiles/matugen-ml4w/config.toml`**

```toml
# matugen config owned by the ml4w shell (shell-ml4w.yaml).
#
# Vendored from mylinuxforwork/dotfiles dotfiles/.config/matugen/config.toml so
# the ml4w shell never depends on ~/.config/matugen, which is a symlink into
# ~/.local/share/dots-hyprland (owned by shell-end4) — the same lesson as
# matugen-end4pc.
#
# Only colors.json matters here: CustomTheme/Theme.qml reads
# ~/.config/ml4w/colors/colors.json on `qs -c ml4w ipc call theme-manager reload`.
# Run it as: matugen -c ~/.config/matugen-ml4w/config.toml <wallpaper>

[config]
version_check = false

[templates.colorsjson]
input_path = '~/.config/matugen-ml4w/templates/colors.json'
output_path = '~/.config/ml4w/colors/colors.json'
```

- [ ] **Step 2: Create `dotfiles/matugen-ml4w/templates/colors.json`**

```json
{
  "background": "{{colors.background.default.hex}}",
  "error": "{{colors.error.default.hex}}",
  "error_container": "{{colors.error_container.default.hex}}",
  "inverse_on_surface": "{{colors.inverse_on_surface.default.hex}}",
  "inverse_primary": "{{colors.inverse_primary.default.hex}}",
  "inverse_surface": "{{colors.inverse_surface.default.hex}}",
  "on_background": "{{colors.on_background.default.hex}}",
  "on_error": "{{colors.on_error.default.hex}}",
  "on_error_container": "{{colors.on_error_container.default.hex}}",
  "on_primary": "{{colors.on_primary.default.hex}}",
  "on_primary_container": "{{colors.on_primary_container.default.hex}}",
  "on_primary_fixed": "{{colors.on_primary_fixed.default.hex}}",
  "on_primary_fixed_variant": "{{colors.on_primary_fixed_variant.default.hex}}",
  "on_secondary": "{{colors.on_secondary.default.hex}}",
  "on_secondary_container": "{{colors.on_secondary_container.default.hex}}",
  "on_secondary_fixed": "{{colors.on_secondary_fixed.default.hex}}",
  "on_secondary_fixed_variant": "{{colors.on_secondary_fixed_variant.default.hex}}",
  "on_surface": "{{colors.on_surface.default.hex}}",
  "on_surface_variant": "{{colors.on_surface_variant.default.hex}}",
  "on_tertiary": "{{colors.on_tertiary.default.hex}}",
  "on_tertiary_container": "{{colors.on_tertiary_container.default.hex}}",
  "on_tertiary_fixed": "{{colors.on_tertiary_fixed.default.hex}}",
  "on_tertiary_fixed_variant": "{{colors.on_tertiary_fixed_variant.default.hex}}",
  "outline": "{{colors.outline.default.hex}}",
  "outline_variant": "{{colors.outline_variant.default.hex}}",
  "primary": "{{colors.primary.default.hex}}",
  "primary_container": "{{colors.primary_container.default.hex}}",
  "primary_fixed": "{{colors.primary_fixed.default.hex}}",
  "primary_fixed_dim": "{{colors.primary_fixed_dim.default.hex}}",
  "scrim": "{{colors.scrim.default.hex}}",
  "secondary": "{{colors.secondary.default.hex}}",
  "secondary_container": "{{colors.secondary_container.default.hex}}",
  "secondary_fixed": "{{colors.secondary_fixed.default.hex}}",
  "secondary_fixed_dim": "{{colors.secondary_fixed_dim.default.hex}}",
  "shadow": "{{colors.shadow.default.hex}}",
  "source_color": "{{colors.source_color.default.hex}}",
  "surface": "{{colors.surface.default.hex}}",
  "surface_bright": "{{colors.surface_bright.default.hex}}",
  "surface_container": "{{colors.surface_container.default.hex}}",
  "surface_container_high": "{{colors.surface_container_high.default.hex}}",
  "surface_container_highest": "{{colors.surface_container_highest.default.hex}}",
  "surface_container_low": "{{colors.surface_container_low.default.hex}}",
  "surface_container_lowest": "{{colors.surface_container_lowest.default.hex}}",
  "surface_dim": "{{colors.surface_dim.default.hex}}",
  "surface_tint": "{{colors.surface_tint.default.hex}}",
  "surface_variant": "{{colors.surface_variant.default.hex}}",
  "tertiary": "{{colors.tertiary.default.hex}}",
  "tertiary_container": "{{colors.tertiary_container.default.hex}}",
  "tertiary_fixed": "{{colors.tertiary_fixed.default.hex}}",
  "tertiary_fixed_dim": "{{colors.tertiary_fixed_dim.default.hex}}"
}
```

- [ ] **Step 3: Verify the template is a valid JSON template**

Run: `python3 -c "import json,re,sys; s=open('dotfiles/matugen-ml4w/templates/colors.json').read(); s=re.sub(r'\{\{.*?\}\}','\"0\"',s); json.loads(s); print('ok')"`
Expected: prints `ok`

- [ ] **Step 4: Verify the TOML parses**

Run: `python3 -c "import tomllib; tomllib.load(open('dotfiles/matugen-ml4w/config.toml','rb')); print('ok')"` (Python ≥3.11). If tomllib is unavailable, fall back to `matugen -c dotfiles/matugen-ml4w/config.toml` against a throwaway wallpaper — expected to fail only because there is no image argument.
Expected: prints `ok`

- [ ] **Step 5: Commit**

```bash
git add dotfiles/matugen-ml4w
git commit -m "feat(ml4w): add matugen-ml4w colors config"
```

---

### Task 3: `shell-ml4w.yaml` module

**Files:**
- Create: `modules/shell-ml4w.yaml`

**Interfaces:**
- Consumes: none (declared in Task 8's host enablement).
- Produces: dcli module `shell-ml4w` whose `post_install_hook` runs `scripts/setup-ml4w.sh` (Task 4).

- [ ] **Step 1: Create `modules/shell-ml4w.yaml`**

```yaml
description: ml4w (ML4W OS) - mylinuxforwork/dotfiles quickshell shell (named config "ml4w")

# Runtime deps only. The shell is a git checkout, not a package — there is no
# ml4w-hyprland package (upstream removed AUR packages). The Quickshell provider
# has exactly one owner (modules/shells-quickshell{,-git}.yaml) and must NOT be
# declared here; ml4w runs on whichever provider is enabled. These three are the
# external commands the QML execs: swaync (StatusbarApp/SwayncModule),
# awww (WallpaperApp + the awww-daemon, extra/awww), network-manager-applet
# (system tray). Fonts (Fira Sans, Material Icons) are copied from the checkout
# by scripts/setup-ml4w.sh, not installed as packages.
packages:
  - swaync
  - awww
  - network-manager-applet

# Never run the ML4W installer (bash <(curl -s https://ml4w.com/os/stable)): it
# is a whole-dotfiles installer that overwrites dcli-symlinked configs (sddm,
# waybar, ~/.config/hypr, ...). The hook reproduces only the checkout, the
# quickshell symlink, the seeded ~/.config/ml4w dirs and the matugen config.
# Details in docs/shells/ml4w.md.
post_install_hook: scripts/setup-ml4w.sh
hook_behavior: once

# ~/.config/quickshell/ml4w is deliberately NOT listed here: it is a symlink
# into ~/.local/share/ml4w-dotfiles (source of truth) and a dcli dotfiles sync
# must not replace it. ~/.config/ml4w and ~/.config/ml4w-statusbar are seeded
# REAL dirs (apps write into them, matugen regenerates colors.json), so they are
# machine-local, not dcli dotfiles. As always, the real linking is done by
# scripts/link-dotfiles.sh; this key is documentation.
dotfiles:
  - source: matugen-ml4w
    target: ~/.config/matugen-ml4w

# Launched per-session via ~/.config/hypr/shells/ml4w/hyprland.lua, which binds
# `qs -c ml4w ipc call <target> <fn>` (statusbar, sidebar, power, calendar,
# wallpaper, theme-manager). Switch with scripts/switch-shell.sh ml4w.
```

- [ ] **Step 2: Verify the YAML parses**

Run: `python3 -c "import yaml; yaml.safe_load(open('modules/shell-ml4w.yaml')); print('ok')"`
Expected: prints `ok`

- [ ] **Step 3: Commit**

```bash
git add modules/shell-ml4w.yaml
git commit -m "feat(ml4w): add shell-ml4w dcli module"
```

---

### Task 4: `scripts/setup-ml4w.sh`

**Files:**
- Create: `scripts/setup-ml4w.sh`

**Interfaces:**
- Consumes: checkout quickshell dir layout; `~/.config/matugen-ml4w` symlink target (Task 2); `~/.config/dcli/dotfiles/matugen-ml4w`.
- Produces: `~/.local/share/ml4w-dotfiles` (clone), `~/.config/quickshell/ml4w` (symlink), `~/.config/ml4w` + `~/.config/ml4w-statusbar` (seeded), `~/.config/matugen-ml4w` (symlink), fonts in `~/.local/share/fonts`, initial `~/.config/ml4w/colors/colors.json`. Refresh counterpart: `scripts/update-ml4w.sh` (Task 5).

- [ ] **Step 1: Create `scripts/setup-ml4w.sh`**

```bash
#!/bin/bash
# Bootstrap the ml4w shell — mylinuxforwork/dotfiles (ML4W OS), a Quickshell
# config run as an independent named config "ml4w".
#
# No personal fork: cloned straight from upstream (branch main), like end4pc,
# omarchy and xenon.
#
# Layout this script produces:
#   ~/.local/share/ml4w-dotfiles    — upstream checkout on branch main (source
#                                     of truth). The quickshell config is nested
#                                     at dotfiles/.config/quickshell.
#   ~/.config/quickshell/ml4w       — symlink -> checkout
#                                     dotfiles/.config/quickshell. Upstream runs
#                                     this as the DEFAULT config (bare `qs`);
#                                     this repo runs every shell as a NAMED
#                                     config, so we run `qs -c ml4w` here. The
#                                     QML imports are relative, so a named-config
#                                     symlink resolves fine.
#   ~/.config/ml4w                  — seeded COPY of checkout
#                                     dotfiles/.config/ml4w (REAL dir: the
#                                     sidebar/settings apps write into it and
#                                     matugen regenerates colors/colors.json).
#                                     Refreshed by update-ml4w.sh, never replaced.
#   ~/.config/ml4w-statusbar        — seeded statusbar override (statusbar.json)
#   ~/.config/matugen-ml4w          — symlink -> dcli dotfiles/matugen-ml4w. The
#                                     base hook links it; hooks run in parallel
#                                     so this hook ensures it too.
#   ~/.local/share/fonts            — Fira Sans + Material Icons copied from the
#                                     checkout's setup/fonts
#
# CRITICAL: no quickshell provider package is declared for this shell. The
# provider has exactly one owner — modules/shells-quickshell{,-git}.yaml — and
# ml4w runs on whichever one is enabled. See docs/PACKAGE-CONFLICTS.md.
#
# CRITICAL: never run the ML4W installer (bash <(curl -s https://ml4w.com/os/stable)).
# It is a whole-dotfiles installer that overwrites dcli-symlinked configs.
#
# Safe to re-run: never clones over an existing checkout and skips symlinks
# that are already correct.
set -euo pipefail

# dcli may run hooks as root — always operate on the real user's home.
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

REPO_URL="https://github.com/mylinuxforwork/dotfiles.git"
REPO_BRANCH="main"
REPO_DIR="$REAL_HOME/.local/share/ml4w-dotfiles"
CHECKOUT_QS="$REPO_DIR/dotfiles/.config/quickshell"
QS_CONF="$REAL_HOME/.config/quickshell/ml4w"
ML4W_DIR="$REAL_HOME/.config/ml4w"
SB_OVERRIDE="$REAL_HOME/.config/ml4w-statusbar/statusbar.json"
MATUGEN_CONF="$REAL_HOME/.config/matugen-ml4w"
MATUGEN_SRC="$REAL_HOME/.config/dcli/dotfiles/matugen-ml4w"

as_user() {
    if [ "$(id -u)" -eq 0 ] && [ "$REAL_USER" != "root" ]; then
        sudo -u "$REAL_USER" -H "$@"
    else
        "$@"
    fi
}

# 1) Clone upstream on branch main. No submodules — the repo has none.
if [ -d "$REPO_DIR/.git" ]; then
    echo ":: ml4w-dotfiles already cloned at $REPO_DIR"
else
    if [ -e "$REPO_DIR" ]; then
        echo "!! $REPO_DIR exists but is not a git repo — refusing to touch it." >&2
        exit 1
    fi
    echo ":: Cloning ml4w-dotfiles (branch $REPO_BRANCH)"
    as_user mkdir -p "$(dirname "$REPO_DIR")"
    as_user git clone --branch "$REPO_BRANCH" "$REPO_URL" "$REPO_DIR"
fi

# 2) Symlink ~/.config/quickshell/ml4w -> checkout quickshell dir (the repo IS
#    the config, nested one level deep).
if [ -L "$QS_CONF" ] && [ "$(readlink -f "$QS_CONF")" = "$(readlink -f "$CHECKOUT_QS")" ]; then
    echo ":: ~/.config/quickshell/ml4w already linked"
else
    if [ -e "$QS_CONF" ]; then
        echo "!! $QS_CONF exists and is not a correct symlink — refusing to clobber." >&2
        exit 1
    fi
    as_user mkdir -p "$(dirname "$QS_CONF")"
    as_user ln -s "$CHECKOUT_QS" "$QS_CONF"
    echo ":: Symlinked $QS_CONF -> $CHECKOUT_QS"
fi

# 3) Seed ~/.config/ml4w (real dir, machine-local). First run only; never
#    clobber an existing seed. update-ml4w.sh refreshes defaults afterwards.
if [ -f "$ML4W_DIR/settings/statusbar.json" ]; then
    echo ":: ~/.config/ml4w already seeded"
else
    echo ":: Seeding ~/.config/ml4w from checkout"
    as_user mkdir -p "$(dirname "$ML4W_DIR")"
    as_user cp -r "$REPO_DIR/dotfiles/.config/ml4w" "$ML4W_DIR"
    as_user mkdir -p "$ML4W_DIR/colors"
fi

# 4) Seed the statusbar override file from the shipped fallback when absent.
#    ~/.config/ml4w-statusbar/statusbar.json is the "master" file the
#    StatusbarApp reads when present; the shipped fallback lives in the ml4w
#    settings dir. Seeding it makes the bar read our copy, not upstream's.
if [ -f "$SB_OVERRIDE" ]; then
    echo ":: statusbar override already present"
else
    as_user mkdir -p "$(dirname "$SB_OVERRIDE")"
    as_user cp "$ML4W_DIR/settings/statusbar.json" "$SB_OVERRIDE"
    echo ":: Seeded $SB_OVERRIDE"
fi

# 5) Ensure the matugen-ml4w symlink (the base hook links it, but hooks run in
#    parallel so it may not exist yet).
if [ -L "$MATUGEN_CONF" ] && [ "$(readlink -f "$MATUGEN_CONF")" = "$(readlink -f "$MATUGEN_SRC")" ]; then
    echo ":: matugen-ml4w already linked"
else
    if [ -e "$MATUGEN_CONF" ]; then
        echo "!! $MATUGEN_CONF exists and is not a correct symlink — refusing to clobber." >&2
        exit 1
    fi
    as_user mkdir -p "$(dirname "$MATUGEN_CONF")"
    as_user ln -s "$MATUGEN_SRC" "$MATUGEN_CONF"
    echo ":: Symlinked $MATUGEN_CONF -> $MATUGEN_SRC"
fi

# 6) Fonts the QML references (Fira Sans for Theme.qml's fontFamily, Material
#    Icons for the icon font). Copied from the checkout, not pacman packages.
echo ":: Installing ml4w fonts"
as_user mkdir -p "$REAL_HOME/.local/share/fonts"
as_user cp -rn "$REPO_DIR/setup/fonts/"* "$REAL_HOME/.local/share/fonts/" 2>/dev/null || true
fc-cache -f >/dev/null 2>&1 || true

# 7) Runtime deps (external commands the QML execs). No quickshell provider
#    here — see docs/PACKAGE-CONFLICTS.md.
RUNTIME_DEPS=(swaync awww network-manager-applet)
echo ":: Installing ml4w runtime dependencies"
if [ "$(id -u)" -eq 0 ]; then
    pacman -S --needed --noconfirm "${RUNTIME_DEPS[@]}"
else
    sudo pacman -S --needed --noconfirm "${RUNTIME_DEPS[@]}"
fi

# 8) Initial theming so Theme.qml has colors on first launch. Theme.qml reads
#    ~/.config/ml4w/colors/colors.json and its onCompleted reload is disabled
#    upstream, so colors load on the `theme-manager reload` IPC that the shell's
#    execs and switch-shell.sh issue — but generate the file now anyway.
WALL="$ML4W_DIR/wallpapers/default.jpg"
if [ -f "$WALL" ] && command -v matugen >/dev/null 2>&1; then
    echo ":: Generating initial theme from $WALL"
    as_user matugen -c "$MATUGEN_CONF/config.toml" "$WALL" \
        || echo "!! matugen failed — the shell will still run; run it after the first wallpaper set"
fi

echo ":: ml4w shell ready — launch with 'qs -c ml4w', switch with switch-shell.sh ml4w"
```

- [ ] **Step 2: Make it executable and syntax-check**

Run: `chmod +x scripts/setup-ml4w.sh && bash -n scripts/setup-ml4w.sh && echo ok`
Expected: prints `ok`

- [ ] **Step 3: Review against the global constraints**

Confirm by reading the file: no quickshell provider install, no ML4W installer invocation, no reference to `~/.config/matugen`.

- [ ] **Step 4: Commit**

```bash
git add scripts/setup-ml4w.sh
git commit -m "feat(ml4w): add setup script"
```

---

### Task 5: `scripts/update-ml4w.sh`

**Files:**
- Create: `scripts/update-ml4w.sh`

**Interfaces:**
- Consumes: `~/.local/share/ml4w-dotfiles` + seeded `~/.config/ml4w` (Task 4).
- Produces: refreshed checkout + seeded defaults; the quickshell config updates for free through the symlink.

- [ ] **Step 1: Create `scripts/update-ml4w.sh`**

```bash
#!/bin/bash
# Update the ml4w shell: pulls latest from mylinuxforwork/dotfiles (main) and
# refreshes the seeded ~/.config/ml4w defaults without clobbering user edits.
#
# The quickshell config updates for free through the symlink
# (~/.config/quickshell/ml4w -> checkout dotfiles/.config/quickshell).
# ~/.config/ml4w is a seeded COPY, so it is refreshed here: subfolders marked
# PROTECTED (ml4w's mechanism — an empty PROTECTED file in the folder) and any
# existing file are left untouched (cp -rn = no-clobber), so new upstream
# defaults appear while your edits survive. ~/.config/matugen-ml4w is a dcli
# dotfile and needs no refresh.
set -euo pipefail

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

REPO_DIR="$REAL_HOME/.local/share/ml4w-dotfiles"
SRC="$REPO_DIR/dotfiles/.config/ml4w"
DST="$REAL_HOME/.config/ml4w"

as_user() {
    if [ "$(id -u)" -eq 0 ] && [ "$REAL_USER" != "root" ]; then
        sudo -u "$REAL_USER" -H "$@"
    else
        "$@"
    fi
}

if [ ! -d "$REPO_DIR/.git" ]; then
    echo "!! ml4w-dotfiles not found at $REPO_DIR — run setup-ml4w.sh first" >&2
    exit 1
fi

echo ":: Updating ml4w-dotfiles (main branch)"
as_user git -C "$REPO_DIR" pull --ff-only

# Refresh seeded defaults (PROTECTED subfolders and existing files survive).
if [ -d "$DST" ]; then
    for d in "$SRC"/*/; do
        [ -d "$d" ] || continue
        base=$(basename "$d")
        if [ -f "$DST/$base/PROTECTED" ]; then
            echo ":: skip $base (PROTECTED)"
        else
            as_user cp -rn "$d" "$DST/"
        fi
    done
    for f in "$SRC"/*; do
        [ -f "$f" ] || continue
        as_user cp -n "$f" "$DST/"
    done
else
    echo "!! $DST missing — run setup-ml4w.sh first" >&2
    exit 1
fi

echo ":: ml4w shell updated — restart shell with switch-shell.sh ml4w"
```

- [ ] **Step 2: Make it executable and syntax-check**

Run: `chmod +x scripts/update-ml4w.sh && bash -n scripts/update-ml4w.sh && echo ok`
Expected: prints `ok`

- [ ] **Step 3: Commit**

```bash
git add scripts/update-ml4w.sh
git commit -m "feat(ml4w): add update script"
```

---

### Task 6: ml4w Hyprland config + house launcher

**Files:**
- Create: `dotfiles/hypr/shells/ml4w/hyprland.lua`
- Copy base from: `dotfiles/hypr/shells/xenon/hyprland/` → `dotfiles/hypr/shells/ml4w/hyprland/`
- Modify: `dotfiles/hypr/shells/ml4w/hyprland/input.lua` (created by the copy)
- Create: `dotfiles/hypr/shells/ml4w/hyprland/execs.lua`
- Create: `dotfiles/hypr/shells/ml4w/hyprland/keybinds.lua`
- Create: `dotfiles/hypr/scripts/launcher.sh`

**Interfaces:**
- Consumes: `shell_paths` registration (Task 8); `matugen-ml4w` (Task 2); seeded `~/.config/ml4w` (Task 4).
- Produces: `qs -c ml4w` launch + IPC binds; `~/.config/hypr/scripts/launcher.sh` (exec'd by ml4w's `StatusbarApp/LauncherModule.qml`).

- [ ] **Step 1: Copy the house module set from xenon as the base**

Run: `cp -r dotfiles/hypr/shells/xenon/hyprland dotfiles/hypr/shells/ml4w/hyprland`
This copies `animations.lua decoration.lua env.lua general.lua input.lua keybinds.lua misc.lua rules.lua scrolling.lua execs.lua` (the `hyprland` subdir is the shell's package-path dir — `require("hyprland.env")` etc. resolve from it because `hyprland.lua` appends the shell dir to `package.path`).

- [ ] **Step 2: Overwrite `dotfiles/hypr/shells/ml4w/hyprland/input.lua`**

ml4w needs SUPER+SPACE for the statusbar (`statusbar focus`), but the house input uses XKB `grp:win_space_toggle` which ALSO grabs SUPER+SPACE and would double-fire. Move the layout toggle to ALT+SHIFT (ml4w upstream's own choice).

```lua
hl.config({
    input = {
        kb_layout     = "us,ara",
        kb_options    = "grp:alt_shift_toggle, ctrl:nocaps",
        sensitivity   = 0.3,
        accel_profile = "flat",
    },
    binds = {
        scroll_event_delay = 0,
        drag_threshold     = 10,
    },
})
```

- [ ] **Step 3: Overwrite `dotfiles/hypr/shells/ml4w/hyprland/execs.lua`**

```lua
hl.on("hyprland.start", function()
    -- The shell: one quickshell instance as named config "ml4w".
    hl.exec_cmd("qs -c ml4w")
    -- Supporting daemons. These are shared infra and survive shell switches,
    -- so a switch never needs to (re)start them.
    hl.exec_cmd("swaync")
    hl.exec_cmd("awww-daemon")
    hl.exec_cmd("nm-applet --indicator")
    -- Wallpaper + theming. Theme.qml reads ~/.config/ml4w/colors/colors.json
    -- and its onCompleted reload is disabled upstream, so load the colors
    -- explicitly after quickshell has registered its IPC handler. exec-once
    -- does not re-fire on `hyprctl reload`, so this is start-only; the switch
    -- script re-triggers the reload on switch.
    hl.exec_cmd("awww img " .. os.getenv("HOME") .. "/.config/ml4w/wallpapers/default.jpg")
    hl.exec_cmd("matugen -c " .. os.getenv("HOME") .. "/.config/matugen-ml4w/config.toml "
        .. os.getenv("HOME") .. "/.config/ml4w/wallpapers/default.jpg")
    hl.exec_cmd("sh -c 'sleep 2; qs -c ml4w ipc call theme-manager reload'")
    hl.exec_cmd("systemctl --user start hyprpolkitagent")
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")
end)
```

- [ ] **Step 4: Overwrite `dotfiles/hypr/shells/ml4w/hyprland/keybinds.lua`**

```lua
-- ml4w keybinds

local qs        = "qs -c ml4w ipc call"
local terminal  = "wezterm-gui"
local browser   = "brave-browser-nightly"
local defaultBrowser = "zen-browser"
local fileExplorer = "thunar"
local launcher  = os.getenv("HOME") .. "/.config/hypr/scripts/launcher.sh"

-- Shell IPC. Targets registered by ml4w's shell.qml / StatusbarApp /
-- SidebarApp / PowerApp / CalendarApp / WallpaperApp / CustomTheme.
-- `statusbar focus` expands the pill and grabs the keyboard (SUPER+SPACE).
-- `theme-manager reload` re-reads ~/.config/ml4w/colors/colors.json.
-- No bind for the welcome/settings apps — out of the minimal-ecosystem scope.
hl.bind("SUPER + SPACE",      hl.dsp.exec_cmd(qs .. " statusbar focus"))
hl.bind("SUPER + CTRL + B",   hl.dsp.exec_cmd(qs .. " statusbar toggle"))
hl.bind("SUPER + SHIFT + B",  hl.dsp.exec_cmd(qs .. " statusbar reload"))
hl.bind("SUPER + CTRL + S",   hl.dsp.exec_cmd(qs .. " sidebar toggle"))
hl.bind("SUPER + CTRL + P",   hl.dsp.exec_cmd(qs .. " power toggle"))
hl.bind("SUPER + CTRL + C",   hl.dsp.exec_cmd(qs .. " calendar toggle"))
hl.bind("SUPER + CTRL + W",   hl.dsp.exec_cmd(qs .. " wallpaper toggle"))
hl.bind("SUPER + SHIFT + W",  hl.dsp.exec_cmd(qs .. " wallpaper toggle"))
hl.bind("SUPER + CTRL + RETURN", hl.dsp.exec_cmd(launcher))

-- Window management
hl.bind("SUPER + Q",         hl.dsp.window.close())
hl.bind("SUPER + F",         hl.dsp.window.fullscreen({ mode = "fullscreen" }))
hl.bind("SUPER + SHIFT + F", hl.dsp.window.fullscreen({ mode = "maximized" }))
hl.bind("SUPER + ALT + F",   hl.dsp.window.float())

-- Focus
hl.bind("SUPER + LEFT",  hl.dsp.focus({ direction = "l" }))
hl.bind("SUPER + RIGHT", hl.dsp.focus({ direction = "r" }))
hl.bind("SUPER + UP",    hl.dsp.focus({ direction = "u" }))
hl.bind("SUPER + DOWN",  hl.dsp.focus({ direction = "d" }))

-- Move window
hl.bind("SUPER + SHIFT + LEFT",  hl.dsp.window.move({ direction = "l" }))
hl.bind("SUPER + SHIFT + RIGHT", hl.dsp.window.move({ direction = "r" }))
hl.bind("SUPER + SHIFT + UP",    hl.dsp.window.move({ direction = "u" }))
hl.bind("SUPER + SHIFT + DOWN",  hl.dsp.window.move({ direction = "d" }))

-- Scrolling layout
hl.bind("SUPER + EQUAL",          hl.dsp.layout("colresize +0.1"))
hl.bind("SUPER + MINUS",          hl.dsp.layout("colresize -0.1"))
hl.bind("SUPER + SHIFT + PERIOD", hl.dsp.layout("colresize +conf"))
hl.bind("SUPER + SHIFT + COMMA",  hl.dsp.layout("colresize -conf"))
hl.bind("SUPER + ALT + PERIOD",   hl.dsp.layout("move +col"))
hl.bind("SUPER + ALT + COMMA",    hl.dsp.layout("move -col"))
hl.bind("SUPER + CTRL + RIGHT",   hl.dsp.layout("swapcol r"))
hl.bind("SUPER + CTRL + LEFT",    hl.dsp.layout("swapcol l"))

-- Workspaces
for i = 1, 5 do
    hl.bind("SUPER + " .. i, hl.dsp.focus({ workspace = tostring(i) }))
    hl.bind("SUPER + ALT + " .. i, hl.dsp.window.move({ workspace = tostring(i) }))
end
hl.bind("SUPER + TAB",         hl.dsp.focus({ workspace = "m+1" }))
hl.bind("SUPER + SHIFT + TAB", hl.dsp.focus({ workspace = "m-1" }))
hl.bind("SUPER + Z", hl.dsp.focus({ workspace = "-1" }), { repeating = true })
hl.bind("SUPER + X", hl.dsp.focus({ workspace = "+1" }), { repeating = true })

-- Mouse
hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Media (ml4w's statusbar reads PipeWire directly via its VolumeModule; the
-- keys drive the tools and the OSD follows)
hl.bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd("wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true })
hl.bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), { locked = true })
hl.bind("XF86AudioMute",         hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true })
hl.bind("XF86AudioMicMute",      hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true })
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl s 5%+"), { locked = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl s 5%-"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })

-- Screenshots
hl.bind("PRINT",             hl.dsp.exec_cmd("grim -g \"$(slurp)\" - | wl-copy"))
hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd("grim -g \"$(slurp)\" - | swappy -f -"))

-- Apps
hl.bind("SUPER + RETURN",  hl.dsp.exec_cmd(terminal))
hl.bind("SUPER + T",       hl.dsp.exec_cmd(terminal))
hl.bind("SUPER + B",       hl.dsp.exec_cmd(browser))
hl.bind("SUPER + E",       hl.dsp.exec_cmd(fileExplorer))
hl.bind("SUPER + R",       hl.dsp.exec_cmd(fileExplorer))
hl.bind("SUPER + W",       hl.dsp.exec_cmd(defaultBrowser))
hl.bind("SUPER + SHIFT + O", hl.dsp.exec_cmd(os.getenv("HOME") .. "/.config/dcli/scripts/switch-shell.sh"))
```

- [ ] **Step 5: Create `dotfiles/hypr/shells/ml4w/hyprland.lua`**

```lua
-- ~/.config/hypr/shells/ml4w/hyprland.lua
-- ml4w (mylinuxforwork/dotfiles, ML4W OS) — Hyprland Lua config (modular loader)
--
-- The shell is the quickshell config named "ml4w" (~/.config/quickshell/ml4w,
-- a symlink into ~/.local/share/ml4w-dotfiles/dotfiles/.config/quickshell).
-- Everything it exposes goes through `qs -c ml4w ipc call <target> <fn>` — see
-- hyprland/keybinds.lua.

-- Default monitor conf
hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = 1,
})

-- Modules
require("hyprland.env")
require("hyprland.general")
require("hyprland.input")
require("hyprland.scrolling")
require("hyprland.decoration")
require("hyprland.animations")
require("hyprland.misc")
require("hyprland.rules")
require("hyprland.execs")
require("hyprland.keybinds")
```

- [ ] **Step 6: Create `dotfiles/hypr/scripts/launcher.sh`**

The `StatusbarApp/LauncherModule.qml` execs `~/.config/hypr/scripts/launcher.sh`; the house launcher is wofi. `~/.config/hypr` is the dcli-symlinked hypr dir, so this file lands at the right path.

```bash
#!/bin/bash
exec wofi --show drun
```

- [ ] **Step 7: Make executable and syntax-check everything**

Run: `chmod +x dotfiles/hypr/scripts/launcher.sh && bash -n dotfiles/hypr/scripts/launcher.sh && for f in dotfiles/hypr/shells/ml4w/hyprland.lua dotfiles/hypr/shells/ml4w/hyprland/*.lua; do command -v luac >/dev/null 2>&1 && luac -p "$f"; done; echo ok`
Expected: prints `ok` (luac -p is a syntax check; skip silently if luac is absent)

- [ ] **Step 8: Commit**

```bash
git add dotfiles/hypr/shells/ml4w dotfiles/hypr/scripts/launcher.sh
git commit -m "feat(ml4w): add hyprland config and house launcher"
```

---

### Task 7: `switch-shell.sh` + picker registration

**Files:**
- Modify: `scripts/switch-shell.sh`
- Modify: `dotfiles/fuzzel/shell-picker.ini`

**Interfaces:**
- Consumes: `dotfiles/fuzzel/shell-icons/ml4w.svg` (Task 1); `qs -c ml4w` (Tasks 4+6).
- Produces: `ml4w` selectable in the shell switcher; also kills/launches it.

- [ ] **Step 1: Register ml4w in the index-aligned arrays**

In `scripts/switch-shell.sh`:

1. Line 2 header comment: change `caelestia | ambxst | dms | noctalia | end4 | end4pc | omarchy | xenon` to `caelestia | ambxst | dms | noctalia | end4 | end4pc | omarchy | xenon | ml4w`.
2. `KNOWN=(caelestia ambxst dms noctalia end4 end4pc omarchy xenon ml4w)`
3. `icon_files=(caelestia.svg ambxst.svg dms.svg noctalia.svg end4.svg end4pc.svg omarchy.png xenon.svg ml4w.svg)`
4. `blurbs=(...)` — add `"MyLinuxForWork · quickshell"` as the 9th entry (after `"MannuVilasara · quickshell"`).

- [ ] **Step 2: Kill the ml4w shell process in `kill_all_shells`**

Add after the `kill_matching -f "qs -c xenon"` line:

```bash
  kill_matching -f "qs -c ml4w"
```

(The `-f` pattern is anchored on the full `qs -c ml4w` invocation so an editor holding an ml4w file open is never matched.)

- [ ] **Step 3: Launch case**

Add a `ml4w)` case at the end of the launch `case` statement (after `xenon)`):

```bash
  ml4w)
  pgrep -A -f "qs -c ml4w" >/dev/null 2>&1 || {
    qs -c ml4w &
    disown
    # Theme.qml loads colors only via IPC (its onCompleted reload is disabled
    # upstream), so trigger the reload once quickshell has registered the
    # handler. Delayed so the failure-free path is silent.
    ( sleep 1; qs -c ml4w ipc call theme-manager reload >/dev/null 2>&1 ) &
    disown
  }
  ;;
```

- [ ] **Step 4: Bump the fuzzel picker row count**

In `dotfiles/fuzzel/shell-picker.ini`, change `lines=8` to `lines=9`.

- [ ] **Step 5: Syntax-check and verify alignment**

Run: `bash -n scripts/switch-shell.sh && python3 - <<'EOF'
import re
src = open('scripts/switch-shell.sh').read()
def arr(name):
    m = re.search(r'%s=\((.*?)\)' % name, src, re.S)
    return m.group(1).split()
known = arr('KNOWN'); icons = arr('icon_files'); blurbs = arr('blurbs')
assert len(known) == len(icons) == len(blurbs) == 9, (len(known), len(icons), len(blurbs))
assert known[-1] == 'ml4w' and icons[-1] == 'ml4w.svg'
print('ok')
EOF`
Expected: prints `ok`

- [ ] **Step 6: Commit**

```bash
git add scripts/switch-shell.sh dotfiles/fuzzel/shell-picker.ini
git commit -m "feat(ml4w): register ml4w in switch-shell"
```

---

### Task 8: Entry point, link-dotfiles, host enablement

**Files:**
- Modify: `dotfiles/hypr/hyprland.lua` (`shell_paths`)
- Modify: `scripts/link-dotfiles.sh` (`TARGETS`)
- Modify: `hosts/cachyos-desktop.yaml` (`enabled_modules`)

**Interfaces:**
- Consumes: Task 6 config; Task 2 `matugen-ml4w` dir.
- Produces: `ml4w` resolvable from `active.conf`; `~/.config/matugen-ml4w` linked; module enabled.

- [ ] **Step 1: Add ml4w to `shell_paths`**

In `dotfiles/hypr/hyprland.lua`, after the `xenon` line:

```lua
    ml4w      = hypr .. "/shells/ml4w/hyprland.lua",
```

- [ ] **Step 2: Link the matugen-ml4w dotfile**

In `scripts/link-dotfiles.sh`, add `matugen-ml4w` to the `TARGETS` array:

```bash
TARGETS=(hypr ambxst noctalia omarchy xenon DankMaterialShell matugen-end4pc matugen-ml4w fuzzel cava nvim yazi lazygit git environment.d)
```

- [ ] **Step 3: Enable the module**

In `hosts/cachyos-desktop.yaml`, add `- shell-ml4w` to `enabled_modules` after `- shell-xenon`.

- [ ] **Step 4: Verify**

Run: `bash -n scripts/link-dotfiles.sh && python3 -c "import yaml; yaml.safe_load(open('hosts/cachyos-desktop.yaml')); yaml.safe_load(open('modules/shell-ml4w.yaml')); print('ok')"`
Expected: prints `ok`

- [ ] **Step 5: Commit**

```bash
git add dotfiles/hypr/hyprland.lua scripts/link-dotfiles.sh hosts/cachyos-desktop.yaml
git commit -m "feat(ml4w): wire entry point, dotfiles link, host module"
```

---

### Task 9: Documentation

**Files:**
- Create: `docs/shells/ml4w.md`
- Modify: `docs/shells/README.md`
- Modify: `README.md`

**Interfaces:**
- Consumes: all prior tasks.
- Produces: per-shell doc page; shells index row; main README shell table/paths.

- [ ] **Step 1: Create `docs/shells/ml4w.md`**

```markdown
# ml4w (ML4W OS)

[Stephan Raabe's ML4W OS](https://github.com/mylinuxforwork/dotfiles) quickshell
config, run as an independent named quickshell config. No personal fork — the
checkout tracks upstream `main` directly.

| | |
|---|---|
| Launch command | `qs -c ml4w` |
| Hyprland config | `shells/ml4w/hyprland.lua` (standalone) |
| Quickshell config | `~/.config/quickshell/ml4w` → `~/.local/share/ml4w-dotfiles/dotfiles/.config/quickshell` |
| Install | `scripts/setup-ml4w.sh` (module `shell-ml4w`) |
| Update | `scripts/update-ml4w.sh` |
| Health check | `pgrep -f "qs -c ml4w"`, `hyprctl configerrors` empty |

## Layout

| Path | What | Owned by |
|---|---|---|
| `~/.local/share/ml4w-dotfiles` | `mylinuxforwork/dotfiles` checkout @ `main` (source of truth) | setup hook |
| `~/.config/quickshell/ml4w` → checkout `dotfiles/.config/quickshell` | the QML shell (bar, launcher, powermenu, sidebar, calendar, wallpaper app, custom theme) | setup hook |
| `~/.config/ml4w` | seeded copy of the checkout's `ml4w` dir (settings, scripts, listeners, wallpapers, `colors/`) — **real dir**, apps write into it | setup + update hooks |
| `~/.config/ml4w-statusbar` | seeded statusbar override (`statusbar.json`) | setup hook |
| `~/.config/matugen-ml4w` → `dcli/dotfiles/matugen-ml4w` | matugen config writing `~/.config/ml4w/colors/colors.json` | `link-dotfiles.sh` |
| `~/.config/hypr/shells/ml4w/` | house Hyprland Lua config + IPC binds | repo |

`~/.config/ml4w*` are deliberately **not** dcli symlinks and **not** checkout
symlinks — they are seeded real dirs, because the sidebar/settings apps write
into them and matugen regenerates `colors.json`. Only
`~/.config/quickshell/ml4w` and `~/.config/matugen-ml4w` are symlinks.

## What you get

All seven ml4w quickshell apps run in one process: the status bar (pill,
expand with SUPER+SPACE), launcher button, sidebar, powermenu, calendar,
wallpaper app and the matugen-driven custom theme. `swaync`, `awww-daemon` and
`nm-applet` are started for the bar's notification/tray/wallpaper modules.

Not installed (minimal-ecosystem scope): ml4w's waybar, settings app
(`ml4w-dotfiles-settings`), swaync config tree, GTK scripts and the ML4W
installer. Buttons/scripts that reference them no-op.

## Traps

- **Never run the ML4W installer** (`bash <(curl -s https://ml4w.com/os/stable)`).
  It overwrites `~/.config/hypr`, waybar, sddm, etc. — all dcli-owned here.
- **No quickshell provider is declared for this shell.** It runs on whichever
  provider is enabled (`quickshell-git` is default). See
  [PACKAGE-CONFLICTS.md](../PACKAGE-CONFLICTS.md).
- **matugen uses `~/.config/matugen-ml4w`, not `~/.config/matugen`.** The latter
  is a symlink into the end-4 checkout (owned by `shell-end4`) and must not be
  touched. If you pick a wallpaper through ml4w's WallpaperApp, its script calls
  the *default* matugen config and would regenerate end4's files — the house
  wallpaper flow in `execs.lua` uses the ml4w config instead.
- **SUPER+SPACE is the statusbar**, not the us/ara layout toggle. `input.lua`
  uses `grp:alt_shift_toggle` so the two don't double-fire.
- **Theme colors load via IPC.** ml4w's `CustomTheme/Theme.qml` has its
  `Component.onCompleted` reload disabled upstream, so colors are applied by
  `qs -c ml4w ipc call theme-manager reload` (fired by `execs.lua` and
  `switch-shell.sh`). If the bar looks stuck on the default brown palette,
  re-run that IPC call.
- The bar's launcher button execs `~/.config/hypr/scripts/launcher.sh` (wofi),
  created by this repo so the button works.
```

- [ ] **Step 2: Add the ml4w row to `docs/shells/README.md`**

1. In the intro, change "Eight graphical shells" to "Nine graphical shells".
2. Add a table row after the xenon row:

```markdown
| [ml4w](ml4w.md) | `qs -c ml4w` | mylinuxforwork/dotfiles (ML4W OS), no local fork. Checkout, not a package. |
```

3. In the "Every setup hook clones MY fork, never upstream" table, add:

```markdown
| ml4w | `mylinuxforwork/dotfiles` | `main` | none — no personal fork |
```

4. In "Fork divergence", add:

```markdown
| ml4w | tracks upstream directly | `scripts/update-ml4w.sh` |
```

- [ ] **Step 3: Update the main `README.md`**

1. Intro: "with ... and xenon as alternate shells" → "with ..., xenon and ml4w as alternate shells".
2. The two shell-count mentions: "Eight shells share one Hyprland session" → "Nine shells share one Hyprland session"; the intro line "Eight shells" anywhere else likewise.
3. Path table: add rows

```markdown
| `~/.local/share/ml4w-dotfiles` | ml4w checkout (`mylinuxforwork/dotfiles`, branch `main`) — the quickshell config is nested at `dotfiles/.config/quickshell` | `setup-ml4w.sh` |
| `~/.config/quickshell/ml4w` → `~/.local/share/ml4w-dotfiles/dotfiles/.config/quickshell` | ml4w's quickshell config, run as `qs -c ml4w` | `setup-ml4w.sh` |
| `~/.config/ml4w` | ml4w runtime config (settings, scripts, wallpapers, `colors/`) — seeded real dir, machine-local | `setup-ml4w.sh` / `update-ml4w.sh` |
```

4. Per-shell table: add `| **ml4w** | `qs -c ml4w` | `shells/ml4w/hyprland.lua` (standalone) | `~/.config/ml4w` |`.
5. `switch-shell.sh` line: add `/ ml4w` to the switchable list.
6. Bootstrap step 4: add `ml4w` to the `switch-shell.sh [...]` argument list.
7. "What's in here" table: add `setup-ml4w.sh`, `update-ml4w.sh` rows and mention `ml4w` in the switch-shell row.

- [ ] **Step 4: Review and commit**

Read the three files once to confirm the counts are consistent (the README says "eight"/"eight shells" in the intro, line 7, and line 47 — all become nine).

```bash
git add docs/shells/ml4w.md docs/shells/README.md README.md
git commit -m "docs(ml4w): document the ml4w shell"
```

---

### Task 10: End-to-end verification

**Files:** none (run the shell on the machine).

**Interfaces:** consumes every task.

- [ ] **Step 1: Run the setup hook directly**

Run: `bash scripts/setup-ml4w.sh`
Expected: clones the checkout (or reports it exists), links `~/.config/quickshell/ml4w`, seeds `~/.config/ml4w` + `ml4w-statusbar`, links `matugen-ml4w`, installs fonts, installs `swaync awww network-manager-applet`, generates `~/.config/ml4w/colors/colors.json`.

- [ ] **Step 2: Verify the QML symlink resolves**

Run: `ls ~/.config/quickshell/ml4w/shell.qml`
Expected: path exists (via the symlink into the checkout).

- [ ] **Step 3: Verify colors.json exists and is valid JSON**

Run: `python3 -c "import json; json.load(open('$HOME/.config/ml4w/colors/colors.json')); print('ok')"`
Expected: prints `ok`

- [ ] **Step 4: Switch to the shell**

Run: `scripts/switch-shell.sh ml4w`
Expected: `active.conf` rewritten to `ml4w`, previous shells killed, `qs -c ml4w` running (check `pgrep -f "qs -c ml4w"`), bar visible, SUPER+SPACE expands the pill.

- [ ] **Step 5: Confirm the config is clean**

Run: `hyprctl configerrors`
Expected: empty output.

- [ ] **Step 6: Round-trip sanity check**

Run: `scripts/switch-shell.sh xenon && sleep 2 && scripts/switch-shell.sh ml4w`
Expected: both switches succeed; no duplicate qs instances (`pgrep -f "qs -c" | wc -l` shows only the active one).

- [ ] **Step 7: Test the update script's no-clobber refresh**

Run: `echo '# my edit' >> ~/.config/ml4w/settings/statusbar.json 2>/dev/null; bash scripts/update-ml4w.sh`
Expected: ff-only pull succeeds; the appended comment survives in `~/.config/ml4w/settings/statusbar.json` (no-clobber copy).

- [ ] **Step 8: Push the work**

```bash
git push
```
