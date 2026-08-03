# ml4w (ML4W OS)

[Stephan Raabe's ML4W OS](https://github.com/mylinuxforwork/dotfiles) quickshell
config, run as an independent named quickshell config. No personal fork — the
checkout tracks upstream `main` directly.

| | |
|---|---|
| Launch command | `qs -c ml4w` (+ overview and settings instances — see Processes) |
| Hyprland config | `shells/ml4w/hyprland.lua` (standalone) |
| Quickshell config | `~/.config/quickshell/ml4w` → `~/.local/share/ml4w-dotfiles/dotfiles/.config/quickshell` |
| Install | `scripts/setup-ml4w.sh` (module `shell-ml4w`) |
| Update | `scripts/update-ml4w.sh` |
| Health check | `pgrep -A -f "qs -c ml4w"`, `pgrep -A -f "qs -p .*ml4w-overview"`, `hyprctl configerrors` empty |

## Layout

| Path | What | Owned by |
|---|---|---|
| `~/.local/share/ml4w-dotfiles` | `mylinuxforwork/dotfiles` checkout @ `main` (source of truth) | setup hook |
| `~/.config/quickshell/ml4w` → checkout `dotfiles/.config/quickshell` | the QML shell (bar, launcher, powermenu, sidebar, calendar, wallpaper app, custom theme) | setup hook |
| `~/.config/ml4w` | seeded copy of the checkout's `ml4w` dir (settings, scripts, listeners, wallpapers, `colors/`) — **real dir**, apps write into it | setup + update hooks |
| `~/.config/ml4w-statusbar` | seeded statusbar override (`statusbar.json`) | setup hook |
| `~/.config/ml4w-overview` | seeded copy of the checkout's `quickshell/overview` — **real dir**, matugen writes `common/Appearance.colors.qml` into it | setup + update hooks |
| `~/.config/rofi` | seeded copy of the checkout's rofi config — **real dir**, matugen writes `colors.rasi` into it | setup + update hooks |
| `~/.local/share/ml4w-dotfiles-settings-src` | `ml4w-dotfiles-settings` checkout (a **separate** upstream repo) | setup + update hooks |
| `~/.local/share/ml4w-dotfiles-settings` | `make install` output — `quickshell/` here is the path the shell's IPC calls | setup hook |
| `~/.config/ml4w-dotfiles-settings` | seeded settings profile (`com.ml4w.dotfiles/settings.json`) | setup hook |
| `~/.config/matugen-ml4w` → `dcli/dotfiles/matugen-ml4w` | matugen config writing the shell's `colors.json`, rofi's `colors.rasi` and the overview's `Appearance.colors.qml` | `link-dotfiles.sh` |
| `~/.config/hypr/shells/ml4w/` | house Hyprland Lua config + IPC binds | repo |

`~/.config/ml4w*` and `~/.config/rofi` are deliberately **not** dcli symlinks and
**not** checkout symlinks — they are seeded real dirs, because the apps write
into them and matugen regenerates files inside them. The overview and rofi dirs
matter especially: their generated files (`Appearance.colors.qml`,
`colors.rasi`) are **tracked** in the checkout, so aiming matugen at the
symlinked copy would dirty the tree on every wallpaper change and break
`update-ml4w.sh`'s `git pull --ff-only`. Only `~/.config/quickshell/ml4w` and
`~/.config/matugen-ml4w` are symlinks.

## Processes

ml4w is three quickshell processes, not one — the same split upstream's
`ml4w-autostart` uses. All three are started by `execs.lua` at login and by
`switch-shell.sh` on a mid-session switch, and all three are torn down on switch
away:

| Process | IPC address | Windows |
|---|---|---|
| `qs -c ml4w` | `qs -c ml4w ipc call` | bar, sidebar, powermenu, calendar, wallpaper app, welcome |
| `qs -p ~/.config/ml4w-overview` | `qs -p <path> ipc call` | workspace overview |
| `PROFILE=com.ml4w.dotfiles qs -p ~/.local/share/ml4w-dotfiles-settings/quickshell` | `qs -p <path> ipc call` | ML4W Dotfiles Settings |

The two `-p` instances have **no config name**, so they are addressed by path —
in the binds and in `switch-shell.sh`'s `kill_matching` patterns alike.
`PROFILE` is not optional: `SettingsWindow` reads it to find its `settings.json`
under `~/.config/ml4w-dotfiles-settings` and renders nothing without it.

## What you get

The full ml4w desktop: status bar (pill, expand with SUPER+SPACE), launcher
button, sidebar, powermenu, calendar, wallpaper app, welcome window, workspace
overview, the ML4W Dotfiles Settings app, and the matugen-driven custom theme.
Six of those share the `qs -c ml4w` process; the overview and settings app are
their own instances (see Processes). `swaync`, `awww-daemon` and `nm-applet` are
started for the bar's notification/tray/wallpaper modules.

The quickshell statusbar is upstream's own — `~/.config/ml4w/settings/statusbar`
selects it (over waybar) and ml4w's scripts dispatch on that value. What differs
here is only that it is enabled out of the box; see Traps.

The sidebar, powermenu, calendar, wallpaper app, welcome window, overview and
settings app are all on-demand — an idle ml4w session shows the bar and nothing
else. That is expected.

The launcher is **rofi**, which is what `~/.config/ml4w/settings/launcher`
selects. `~/.config/hypr/scripts/launcher.sh` dispatches on that value (walker
is supported if you install it, wofi is the last-resort fallback). That path is
not ours to choose: `StatusbarApp/LauncherModule.qml` hardcodes it, so the bar's
launcher button lands there whatever we do. rofi 2.x is Wayland-native — there
is no `rofi-wayland` to reach for and nothing conflicts.

### Binds beyond upstream's

| Bind | Action |
|---|---|
| `SUPER+SHIFT+SPACE` | overview toggle (`SUPER+TAB` is the workspace cycle here) |
| `SUPER+CTRL+COMMA` | settings app toggle |
| `SUPER+CTRL+H` | welcome window toggle |

Not installed (minimal-ecosystem scope): ml4w's waybar, swaync config tree, GTK
scripts and the ML4W installer. Scripts that reference them no-op. `hyprmod` is
AUR-only, so it installs only when `paru` is present.

The checkout tracks branch `main` — upstream's development trunk, not the
`2.9.9.x` tags the ml4w.com stable installer uses. Same policy as end4pc,
omarchy and xenon.

## Traps

- **Never run the ML4W installer** (`bash <(curl -s https://ml4w.com/os/stable)`).
  It overwrites `~/.config/hypr`, waybar, sddm, etc. — all dcli-owned here.
- **The bar is opt-in upstream; this repo enables it.** Upstream ships
  `StatusbarApp/statusbar.json` with `"enabled": false` and lets waybar (launched
  from its `conf/autostart.lua`) cover the gap until you pick Quickshell in the
  SidebarApp switch. There is no waybar here, so `setup-ml4w.sh` seeds
  `~/.config/ml4w-statusbar/statusbar.json` with `"enabled": true`. **If the shell
  starts and no bar appears, check that flag first** — the process is running and
  the QML loaded, the window is just `visible: false`. Recover with
  `qs -c ml4w ipc call statusbar enable` or SUPER+CTRL+B.
- **Don't use the sidebar's waybar/quickshell statusbar switch.** Picking waybar
  runs `qs ipc call statusbar disable` and `~/.config/waybar/launch.sh`, which is
  not installed — leaving no bar at all, recoverable only through the IPC call
  above.
- **A dead button usually means a missing binary, and it fails silently.** The
  QML fires everything through `Quickshell.execDetached`, which has no error
  path — no dialog, no log line, nothing happens. That is why the button targets
  (`nwg-displays`, `qt6ct`, `mission-center`, `waypaper`, `gnome-text-editor`,
  `hyprmod`, `rofi`) are hard dependencies in `modules/shell-ml4w.yaml`, not
  nice-to-haves.
- **The overview logs one `"" is not a valid color name` warning at startup.**
  Cosmetic and upstream's own: their matugen template defines 23 colors while
  `Appearance.qml`'s default set has 46, so the rest resolve empty. A stock ML4W
  install does the same.
- **`swaync` and `awww-daemon` are ml4w-only and are torn down on switch.**
  `switch-shell.sh` kills both, because swaync holds the
  `org.freedesktop.Notifications` bus name and would swallow the next shell's
  notifications. `nm-applet` is left running on purpose — no bus conflict, and it
  is often started at login by something outside dcli.
- **`~/.config/ml4w-statusbar/statusbar.json` is the master file.** While it
  exists, `~/.config/ml4w/settings/statusbar.json` is ignored entirely. Both are
  parsed with a tolerant reader that strips `/* */` blocks and trailing commas but
  **not** `#` comments — a `#` line makes the file unparseable and it is silently
  dropped in favour of the built-in defaults.
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
