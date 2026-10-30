# ryoku

[Ryoku-dev/ryoku](https://github.com/Ryoku-dev/ryoku), the Quickshell desktop of
the Ryoku distribution, run **from a checkout**. One repo supplies the shell
QML, the Ryoku Hub settings app, the Go `ryoku-shell` control plane, three Qt
QML modules and the Ryoku Hyprland config — dcli uses only the shell half.

| | |
|---|---|
| Module | `modules/shell-ryoku.yaml` |
| Packages | declared in the module (`go`, `cmake`, `ninja`, `qt6-shadertools`, `qt6-quick3d`, `ffmpeg`, `uv`, `socat`, `gum`, `qrencode`, `zenity`, `inotify-tools`, `easyeffects`, `lsp-plugins-lv2`, `calf`, `ddcutil`, `upower`, `hyprlock`) |
| Launch | `RYOKU_SHELL_DIR=… ryoku-shell daemon` |
| Setup hook | `scripts/setup-ryoku.sh` |
| Update | `scripts/update-ryoku.sh` (or `scripts/update-shells.sh ryoku`) |

## Layout

| Path | What |
|---|---|
| `~/.local/share/ryoku-shell` | Checkout, **source of truth**. origin `Ryoku-dev/ryoku`, branch `main` — no personal fork |
| `~/.local/bin/ryoku-shell` | Go IPC daemon/client, built from `ryoku/shell/ipc` |
| `~/.local/lib/qt6/qml/Ryoku/Blobs`, `Spatial3D` | C++ QML modules, built by `ryoku/shell/plugin/build.sh` |
| `~/.local/lib/qt6/qml/Ryoku/Ui`, `FrameBars`, `PluginKit` | Pure-QML modules, copied by their own `install.sh` |
| `~/.local/share/ryoku/i18n` | Translation catalog (`ryoku/i18n/tools/install.sh`) |
| `~/.config/ryoku` | `shell.json`, `widgets.json`, `visualizer.json`, `matugen.json` — written by the daemon/Hub, machine-local |
| `dotfiles/hypr/shells/ryoku/hyprland.lua` | Standalone Hyprland config, in this repo |

The checkout is `…/ryoku-shell`, not `…/ryoku`: upstream installs its i18n
catalog to `~/.local/share/ryoku/i18n`, so a checkout at that path would contain
an untracked `i18n/` directory and show up dirty forever.

## Why this is a checkout, not the distro install

Ryoku is a **distribution**. `ryoku-shell-installer` adds a signed `[ryoku]`
pacman repository, installs `ryoku-desktop-hyprland` (Hyprland with pinned
plugins, SDDM, limine, snapshots) and converts the machine in place.
`ryoku materialize` / `ryoku deploy` copy the distro's config tree into
`~/.config` — including `~/.config/hypr`, which is dcli's. None of that runs
here.

`setup-ryoku.sh` reproduces upstream's own no-install path,
`ryoku/shell/dev-run.sh`: build `ryoku-shell`, build/install the QML modules,
install the i18n catalog, and launch the daemon against the checkout. It adds
one step dev-run.sh omits — `Ryoku.PluginKit` — because `Desktop.qml` imports it
and the shell otherwise dies at startup with
`module "Ryoku.PluginKit" is not installed`.

## Runtime

`ryoku-shell daemon` owns one Quickshell config and spawns/park the launcher and
overview palettes on demand. It refuses to start a second daemon (single-instance
lock on `$XDG_RUNTIME_DIR/ryoku-shell.sock`), so `switch-shell.sh` uses
`pgrep -x ryoku-shell` as the "is it running" guard and calls the daemon's own
`quit` verb on teardown — the daemon TERMs its children and reaps them.

Keybinds call `ryoku-shell <verb>` (`launcher`, `overview`, `visualizer`,
`quicksettings`, `wallpaper-menu`, `clipboard`, `hub open`), because upstream
binds through Hyprland global shortcuts that only exist under its own Hyprland
config. `dotfiles/hypr/shells/ryoku/hyprland/keybinds.lua` keeps the house
window/workspace/media keys and maps the shell surfaces onto them:

| Bind | Action |
|---|---|
| `SUPER` (tap), `SUPER + D` | launcher |
| `SUPER + V` | clipboard |
| `SUPER + N`, `SUPER + Escape` | quick settings |
| `SUPER + I`, `SUPER + ,` | Ryoku Hub |
| `SUPER + SHIFT + W` | wallpaper menu |
| `SUPER + TAB`, `SUPER + ALT + TAB` | overview |
| `SUPER + M`, `SUPER + SHIFT + M`, `SUPER + ALT + M` | visualizer / overlay / place |
| `SUPER + L` | `hyprlock` (house config) |
| `SUPER + SHIFT + O` | dcli shell switcher |

`SUPER + Space` stays the house us/ara layout toggle, so ryoku's own launcher
moves to `SUPER + D`. There is no workspace bind on `SUPER + TAB` while ryoku is
active — that combination is its overview.

## Tools that are not installed

A checkout-only setup deliberately has no `ryoku` CLI, no `ryoku-*` helper
scripts and no qylock. Binds that would need them are either replaced with house
tools or left out:

| Upstream | Here |
|---|---|
| `ryoku-shell lock` (qylock) | `hyprlock` |
| `ryoku-shell screenshot` (`ryoku-cmd-ryoshot`) | `grim`/`slurp`/`swappy` |
| `ryoku-volume`, `ryoku-cmd-brightness` | `wpctl`, `brightnessctl` |
| `ryoku-app` (terminal/files/browser) | house binaries |
| `ryoku-shell voice` (ryostage), `ryogami` wallpapers, `ryoku` CLI | not bound |

The daemon's OSD still follows volume/brightness changes made by those house
tools.

## Shared-surface audit: app theming starts off

Ryoku's palette pipeline has two layers:

- **core** (always rendered): kitty `current-theme.conf`, `btop/themes/ryoku.theme`,
  `fastfetch/ryoku-colors.json`, `qt6ct/colors/ryoku.conf`, Hyprland border
  colours under `~/.cache/ryoku/`;
- **app suite** (`themeRyokuApps`, gated again by `theme.json`'s “Theme apps”):
  GTK 3/4 stylesheets, cava, yazi, fish, starship, kitty, KDE colours and the
  rest of `apps.toml`.

The app suite writes files this repo owns and several shells write too —
`cava/config`, `btop/themes/`, `yazi/theme.toml`, fish, starship. dcli cannot
isolate them per shell (`shell-theme-state.sh` covers GTK/Qt/cursor/rofi, not the
terminal palettes), so `setup-ryoku.sh` seeds
`~/.config/ryoku/matugen.json` with `{"themeRyokuApps": false}` **once**, and the
Hub's appearance page is the opt-in. The core layer still writes only new,
harmless files under `btop/themes/`, `fastfetch/`, `qt6ct/colors/` and kitty.

Ryoku also writes these gsettings keys, all in `shell-theme-state.sh`'s managed
set: `color-scheme`, `accent-color`, `gtk-theme`, `font-name`,
`document-font-name`, `monospace-font-name`. GTK stylesheets are written to
`gtk-{3,4}.0/gtk.css`, which the same script snapshots.

## Dependencies worth knowing about

- Everything already declared by base/terminal/system modules is not repeated:
  `matugen`, `brightnessctl`, `wl-clipboard`/`wl-clip-persist`, `cliphist`,
  `playerctl`, `cava`, `imagemagick`, `hyprpicker`, `hypridle`, `hyprsunset`,
  `gpu-screen-recorder`, the xdg portals and the fonts.
- `quickshell` is **not** in the module: the provider has exactly one owner
  (`modules/shells-quickshell{,-git}.yaml`) and ryoku runs on whichever is
  enabled. See [../PACKAGE-CONFLICTS.md](../PACKAGE-CONFLICTS.md).
- Upstream's helper binaries live in `ryoku/bin` in the checkout. They are not
  added to `PATH`; only the compiled `ryoku-shell` is installed under
  `~/.local/bin`.

## Health check

```bash
scripts/doctor.sh
scripts/update-shells.sh --status ryoku
git -C ~/.local/share/ryoku-shell status --short
~/.local/bin/ryoku-shell ping
scripts/switch-shell.sh --dry-run ryoku
DCLI_HYPRMOD_SHELL=ryoku Hyprland --verify-config -c ~/.config/hypr/hyprland.lua
```
