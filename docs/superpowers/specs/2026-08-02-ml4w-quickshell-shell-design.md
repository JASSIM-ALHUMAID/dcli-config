# Design: ml4w quickshell shell — new module + shell switching

Date: 2026-08-02

## Purpose

Add **ml4w** (MyLinuxForWork / `mylinuxforwork/dotfiles`, ML4W OS) as a ninth
switchable shell in this repo, following the established per-shell pattern used
by xenon/end4pc/omarchy: a dcli module + setup/update scripts + a house-owned
Hyprland Lua config + registration in `switch-shell.sh`.

Scope decisions made with the user:

1. **Full quickshell shell, minimal ecosystem.** Run ml4w's whole quickshell
   config (`shell.qml` + StatusbarApp, SidebarApp, PowerApp, CalendarApp,
   WallpaperApp, WelcomeApp, CustomTheme) as one named quickshell config. Do
   **not** pull in ml4w's waybar, settings app (`ml4w-dotfiles-settings`),
   swaync config tree, GTK scripts, or the ML4W installer. Install only the
   runtime packages the QML actually needs.
2. **Checkout + symlink, track `main`.** Clone `mylinuxforwork/dotfiles` @
   `main` (rolling, Lua/Hyprland 0.55.x — matches this machine) into
   `~/.local/share/ml4w-dotfiles`. Symlink `~/.config/quickshell/ml4w` →
   checkout `dotfiles/.config/quickshell`. Upstream tracked directly, no
   personal fork (like end4pc/omarchy/xenon). Update via `git pull`.
3. **Machine-local seed for runtime config.** `~/.config/ml4w` and
   `~/.config/ml4w-statusbar` are **real directories** copied from the checkout
   by the setup script, not dcli symlinks and not symlinks into the checkout.
   The sidebar/settings apps write into them and matugen regenerates
   `colors.json`, so symlinking would dirty the checkout. Edits survive updates.

## Background: how ml4w's quickshell works

- The config lives at `mylinuxforwork/dotfiles` → `dotfiles/.config/quickshell/`
  with `shell.qml` at the top importing 7 app modules. Upstream launches it as
  bare `qs` (the *default* config at `~/.config/quickshell/shell.qml`).
- This repo runs shells as **named** quickshell configs (`qs -c <name>`), which
  live at `~/.config/quickshell/<name>/`. We therefore run ml4w as
  `qs -c ml4w` via the symlink above. The QML's imports are relative, so a
  named-config symlink resolves fine; its runtime reads use absolute
  `Quickshell.env("HOME") + "/.config/ml4w/..."` paths, which are independent
  of the config name.
- Theming: `CustomTheme/Theme.qml` (a QML singleton) reads
  `~/.config/ml4w/colors/colors.json` — a flat material-color JSON written by
  matugen. `Component.onCompleted: reloadTheme()` is commented out upstream, so
  the shell must be told to load colors after startup via
  `qs ipc call theme-manager reload` (there is an `IpcHandler { target:
  "theme-manager" }` in shell.qml).
- Statusbar: reads `~/.config/ml4w-statusbar/statusbar.json` (user override,
  the "master" when present) and `~/.config/ml4w/settings/statusbar.json`
  (shipped fallback). Sidebar switches write back into the master.
- Other couplings: SwayncModule needs swaync running; WallpaperApp uses the
  awww wallpaper daemon; ml4w scripts/listeners live under `~/.config/ml4w`.

## Layout produced

| Path | What | Owned by |
|---|---|---|
| `~/.local/share/ml4w-dotfiles` | clone of `mylinuxforwork/dotfiles` @ `main` (source of truth) | `setup-ml4w.sh` |
| `~/.config/quickshell/ml4w` → `~/.local/share/ml4w-dotfiles/dotfiles/.config/quickshell` | the QML shell, run as `qs -c ml4w` | `setup-ml4w.sh` |
| `~/.config/ml4w` | seeded copy of checkout `dotfiles/.config/ml4w` (settings, scripts, listeners, wallpapers, colors/) — real dir, machine-local | `setup-ml4w.sh` + `update-ml4w.sh` |
| `~/.config/ml4w-statusbar` | seeded statusbar config (real dir, machine-local) | `setup-ml4w.sh` |
| `~/.config/matugen-ml4w` → `dcli/dotfiles/matugen-ml4w` | matugen config + template producing `~/.config/ml4w/colors/colors.json` | `link-dotfiles.sh` |
| `~/.config/hypr/shells/ml4w/hyprland.lua` | house Hyprland config + IPC binds | repo |
| `dotfiles/fuzzel/shell-icons/ml4w.svg` | picker icon | repo |

Rule of thumb exception worth recording: `~/.config/ml4w*` is deliberately NOT a
dcli symlink and NOT a checkout symlink — it is a seeded real dir (see Purpose
#3), unlike `~/.config/quickshell/ml4w` which IS a checkout symlink.

## Files changed/added in this repo

1. `modules/shell-ml4w.yaml` (new)
2. `scripts/setup-ml4w.sh` (new)
3. `scripts/update-ml4w.sh` (new)
4. `dotfiles/hypr/shells/ml4w/hyprland.lua` (new)
5. `dotfiles/matugen-ml4w/` — config.toml + `colors.json` template (new)
6. `dotfiles/fuzzel/shell-icons/ml4w.svg` (new)
7. `dotfiles/hypr/hyprland.lua` — add `ml4w` to `shell_paths` (edit)
8. `scripts/switch-shell.sh` — `KNOWN`, `icon_files`, `blurbs`,
   `kill_matching -f "qs -c ml4w"`, launch case (edit)
9. `scripts/link-dotfiles.sh` — add `matugen-ml4w` to `TARGETS` (edit)
10. `dotfiles/fuzzel/shell-picker.ini` — `lines=` 8 → 9 (edit)
11. `hosts/cachyos-desktop.yaml` — add `shell-ml4w` to `enabled_modules` (edit)
12. `docs/shells/ml4w.md` (new), `docs/shells/README.md` (edit), README.md
    (edit), `docs/NOTES.md` if any trap surfaces (edit)

## Module: `modules/shell-ml4w.yaml`

- `description`: ml4w (ML4W OS) — mylinuxforwork/dotfiles quickshell shell,
  named config "ml4w".
- `packages` (runtime deps only):
  - `swaync` — the SwayncModule statusbar widget needs it running
  - `awww` — the wallpaper engine (now `extra/awww`, the swww successor; the
    daemon binary is `awww-daemon`). Used by ml4w's WallpaperApp.
  - `network-manager-applet` — nm-applet for the tray
  - possibly `papirus-icon-theme` / `fira-sans-fonts` if the QML references
    them (verified by grepping the checkout's QML at implementation)
  - matugen is already in `base`; fonts/icons: ml4w QML uses Fira Sans (and
    house `ttf-*` already present); icons via papirus if the QML references it
  - **Do NOT declare `quickshell`/`quickshell-git`** — one-owner provider rule
    (docs/PACKAGE-CONFLICTS.md). ml4w is plain QML and runs on whichever
    provider is enabled (quickshell-git is the default).
  - **Do NOT declare `ml4w-hyprland` or any ML4W package** — AUR packages were
    removed upstream; the config is a git checkout, like omarchy.
- `post_install_hook: scripts/setup-ml4w.sh`, `hook_behavior: once`.
- `dotfiles:` key (documentation): `source: matugen-ml4w` → `target:
  ~/.config/matugen-ml4w`. The real linking is `link-dotfiles.sh`. `~/.config/
  quickshell/ml4w`, `~/.config/ml4w`, `~/.config/ml4w-statusbar` are
  deliberately NOT listed (checkout symlink + seeded dirs).
- Comment the upstream-installer warning: never run `bash <(curl -s
  https://ml4w.com/os/stable)` — it is a full-dotfiles installer that would
  overwrite dcli-symlinked configs (the omarchy trap, repeated).

## `scripts/setup-ml4w.sh`

Mirrors `setup-xenon.sh` structure (root-safe via `REAL_USER`/`as_user`):

1. Clone `https://github.com/mylinuxforwork/dotfiles.git` @ `main` into
   `~/.local/share/ml4w-dotfiles` if absent (refuse to touch a non-git dir).
2. Symlink `~/.config/quickshell/ml4w` → checkout `dotfiles/.config/quickshell`
   if not already correct.
3. Copy `checkout/dotfiles/.config/ml4w` → `~/.config/ml4w` (real dir, skip if
   it exists and looks populated — first-run only), and seed
   `~/.config/ml4w-statusbar/statusbar.json` from the shipped
   `ml4w/settings/statusbar.json` if the user override is absent.
4. matugen: the canonical config lives in dcli (`dotfiles/matugen-ml4w`,
   symlinked by `link-dotfiles.sh` to `~/.config/matugen-ml4w`). Because hooks
   run in parallel, `setup-ml4w.sh` must not assume that symlink exists yet —
   it ensures `~/.config/matugen-ml4w` → dcli `dotfiles/matugen-ml4w` itself.
   The `matugen-ml4w` template set is adapted once from ml4w's
   `dotfiles/.config/matugen/templates/colors.json` and committed; the setup
   script does NOT copy from the checkout. Its template writes
   `~/.config/ml4w/colors/colors.json`. **Never touch `~/.config/matugen`**
   (symlink into the end4 checkout — owned by shell-end4; this is exactly the
   matugen-end4pc lesson).
5. Seed a default wallpaper (copy one from checkout wallpapers) and run matugen
   once with the ml4w config so `Theme.qml` has colors on first launch.
6. Install `RUNTIME_DEPS` via pacman (`--needed --noconfirm`).
7. Report ready: launch with `qs -c ml4w`, switch with `switch-shell.sh ml4w`.

Safe to re-run: never clones over an existing checkout, skips correct symlinks,
and does not clobber an existing `~/.config/ml4w`.

## `scripts/update-ml4w.sh`

Mirrors `update-xenon.sh`:
- `git -C ~/.local/share/ml4w-dotfiles pull --ff-only` (fail loudly on
  divergence).
- Refresh `~/.config/ml4w` defaults from the checkout while preserving user
  edits: honour ml4w's `PROTECTED` marker files (empty files inside a dir that
  upstream uses to skip overwrites) and skip any file the user changed
  (timestamps or PROTECTED markers — mechanism verified at implementation).
- The QML updates for free through the symlink.

## Theming: `dotfiles/matugen-ml4w`

- A `matugen-ml4w` config dir tracked in dcli (mirrors `matugen-end4pc`),
  symlinked by `link-dotfiles.sh`.
- `config.toml` — image input from the active ml4w wallpaper
  (`~/.config/ml4w/wallpapers/`), output template writing
  `~/.config/ml4w/colors/colors.json` in the flat material-color JSON format
  Theme.qml expects (copied/adapted from ml4w's own
  `dotfiles/.config/matugen/templates`).
- After a wallpaper change, run `matugen -c ~/.config/matugen-ml4w/config.toml`
  then `qs ipc call theme-manager reload`.

## `dotfiles/hypr/shells/ml4w/hyprland.lua`

House standalone config (like xenon/end4pc — same input/layout/monitor/app
prefs: wezterm-gui, zen-browser, brave-browser-nightly, thunar, codium),
plus:
- `execs` on `hyprland.start`: `qs -c ml4w`, `swaync`, `nm-applet --indicator`,
  `awww-daemon`, wallpaper restore + matugen + `qs ipc call theme-manager
  reload` (to actually load colors — upstream's onCompleted reload is off).
- IPC binds via `qs -c ml4w ipc call <target> <fn>` (targets verified against
  the QML at implementation):
  - SUPER+SPACE → `statusbar focus`
  - SUPER+CTRL+B → `statusbar toggle`; SUPER+SHIFT+B → `statusbar reload`
  - launcher, `sidebar`, `power` (powermenu), `calendar`, `wallpaper`
  - (NOT `overview`: ml4w runs that as a *separate* `qs -p .../overview`
    process, not an IPC target of shell.qml — out of scope for the minimal
    ecosystem.)
- Guard the launch with pgrep like every other shell (exec-once does not
  re-fire on `hyprctl reload`).

## `switch-shell.sh` integration

- Add `ml4w` to `KNOWN`, `icon_files` (`ml4w.svg`), `blurbs`
  ("MyLinuxForWork · quickshell") — all three index-aligned.
- `kill_all_shells`: add `kill_matching -f "qs -c ml4w"` (anchored so it does
  not match an editor holding an ml4w file open).
- Launch case: `qs -c ml4w &` guarded by
  `pgrep -A -f "qs -c ml4w"`.
- `dotfiles/fuzzel/shell-picker.ini`: `lines=9`.
- `dotfiles/hypr/hyprland.lua`: add `ml4w = hypr .. "/shells/ml4w/hyprland.lua"`
  to `shell_paths`.

## Docs

- `docs/shells/ml4w.md` — layout table, launch command, the default-config
  note (upstream runs bare `qs`; we run it as `qs -c ml4w`), theming flow,
  update procedure (`scripts/update-ml4w.sh`), health check
  (`qs -c ml4w` + `hyprctl configerrors`).
- `docs/shells/README.md` — table row + "Never install a packaged Quickshell
  fork"-style note that ML4W's installer must never be run (full-dotfiles
  installer) and ml4w is a checkout, not a package.
- README.md — shell count (eight → nine), path table row for
  `~/.local/share/ml4w-dotfiles` + `~/.config/quickshell/ml4w` +
  `~/.config/ml4w`, `switch-shell.sh` argument list, bootstrap step 4 list.

## Host

`hosts/cachyos-desktop.yaml` `enabled_modules`: add `- shell-ml4w`.

## Verification plan

1. `dcli sync` on a fresh checkout — module installs, hook clones, links,
   seeds, matugen runs, `~/.config/ml4w/colors/colors.json` exists.
2. `scripts/switch-shell.sh ml4w` — active.conf rewritten, other shells killed,
   `qs -c ml4w` reports `Configuration Loaded`, bar visible, SUPER+SPACE
   expands it, theme colors load (theme-manager IPC works).
3. `hyprctl configerrors` is empty.
4. Round-trip to another shell and back (the repo's standard switch sanity
   check).
5. `scripts/update-ml4w.sh` — ff-only pull, PROTECTED files preserved.

## Out of scope / notes

- ml4w's `ml4w-dotfiles-settings` settings app, waybar, swaync config tree,
  GTK scripts, `hyprland-gui.lua`, welcome-app autostart popup are NOT
  installed. The SidebarApp's settings app-launcher buttons that point at them
  will no-op; acceptable for the minimal-ecosystem scope.
- ml4w ships `overview/` and `shared/` dirs — they come along via the symlink
  but are inert for this shell: `shared/` (icons) is used by the QML, while
  `overview/` is a separate quickshell process upstream and is not wired in.
- If ml4w's sidebar/welcome auto-popups prove intrusive, silence via the
  seeded `~/.cache/ml4w-welcome-autostart` marker (upstream's mechanism) — a
  follow-up, not part of the initial shell.
