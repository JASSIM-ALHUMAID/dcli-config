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
| Health check | `pgrep -A -f "qs -c ml4w"`, `hyprctl configerrors` empty |

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
