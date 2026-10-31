# ryoku

[Ryoku-dev/ryoku](https://github.com/Ryoku-dev/ryoku), the Quickshell desktop of
the Ryoku distribution, run **from a checkout**. One repo supplies the shell
QML, the Ryoku Hub settings app, the RyoStore catalog, the Go `ryoku-shell`
control plane, the `ryogami` wallpaper daemon, Qt QML modules and the Ryoku
Hyprland config. dcli uses everything that stays inside the user session and
none of the parts that convert the machine.

| | |
|---|---|
| Module | `modules/shell-ryoku.yaml` |
| Packages | declared in the module: build toolchain (`go`, `cmake`, `ninja`, `qt6-shadertools`, `vulkan-headers`, `wayland-protocols`) and runtime (`qt6-quick3d`, `qt6-multimedia`, `qt6-imageformats`, `ffmpeg`, `uv`, `socat`, `gum`, `inter-font`, `libqalculate`, `mpv-mpris`, `yt-dlp`, …) |
| Launch | `scripts/launch-ryoku.sh` — `ryogami` + `ryoku-shell daemon`, with `~/.local/lib/ryoku/bin` on `PATH` |
| Setup hook | `scripts/setup-ryoku.sh` |
| Update | `scripts/update-ryoku.sh` (or `scripts/update-shells.sh ryoku`) — pulls, then re-runs the hook to rebuild |

## Layout

| Path | What |
|---|---|
| `~/.local/share/ryoku-shell` | Checkout, **source of truth**. origin `Ryoku-dev/ryoku`, branch `main` — no personal fork |
| `~/.local/lib/ryoku/bin` | The session's private bin dir: compiled `ryoku-shell`, `ryogami`, `ryogami-live`, `ryoku-hub`, `ryoku-host`, `ryostore`, plus symlinks to the user-level helpers |
| `~/.local/bin/ryoku-shell` | Symlink into the bin dir, for binds, `switch-shell.sh` and `doctor.sh` |
| `~/.config/quickshell/<name>` | Symlinks into the checkout: every `ryoku/shell/quickshell/*` entry (`shell`, `inir`, `keys`, `stage`, `welcome`, …) plus `hub`, `ryostore`, `ryovm` |
| `~/.local/lib/qt6/qml/Ryoku/` | `Blobs`, `Spatial3D`, `Ryogami` (built C++), `Ui`, `FrameBars`, `PluginKit` (copied QML) |
| `~/.local/share/ryogami/shell.qml` | Wallpaper picker entry point |
| `~/.local/share/ryoku/i18n` | Translation catalog |
| `~/.config/matugen` | Symlink to the checkout's `ryoku/shell/matugen` — ryoku's templates (see the shared-surface audit) |
| `~/.local/share/ryoku/plugins` | Plugins installed from RyoStore (receipt-owned, written by `ryostore`) |
| `~/Pictures/Wallpapers/ryoku` | The 59 shipped wallpapers, seeded once as a reflink copy |
| `~/.config/ryoku` | `shell.json`, `desktop.json`, `widgets.json`, `matugen.json`, … — written by the daemon/Hub, machine-local |
| `~/.cache/ryoku-build/ryogami-picker` | Incremental build dir for the picker, outside the checkout |
| `dotfiles/hypr/shells/ryoku/hyprland.lua` | Standalone Hyprland config, in this repo |

The checkout is `…/ryoku-shell`, not `…/ryoku`: upstream installs its i18n
catalog to `~/.local/share/ryoku/i18n`, so a checkout at that path would contain
an untracked `i18n/` directory and show up dirty forever.

## How the distro maps onto this machine

Ryoku is a **distribution**. `ryoku-shell-installer` adds a signed `[ryoku]`
pacman repository, installs `ryoku-desktop-hyprland` (Hyprland with pinned
plugins, SDDM, limine, snapshots) and converts the machine in place.
`ryoku materialize` / `ryoku deploy` copy the distro's config tree into
`~/.config` — including `~/.config/hypr`, which is dcli's.

`setup-ryoku.sh` reproduces the distro's packages from their own recipes
(`release/packages/{ryoku-shell,ryogami,ryoku-hub,ryoku-desktop}/payload.sh`)
into `~/.local` instead of `/usr`, keeping only the user-level parts:

| Distro package | Here |
|---|---|
| `ryoku-shell` — daemon, `ryoku-*` scripts | built + linked into the session bin dir |
| `ryogami` — wallpaper daemon, `ryogami-live`, picker | built; started next to the daemon |
| `ryoku-hub` — Hub backend | built |
| `ryoku` (CLI) — `ryoku-host` | only `ryoku-host` (package/app queries the Hub calls); **not** the `ryoku` CLI |
| `ryoku-desktop` — Quickshell configs, apps, PluginKit/Ui/FrameBars, helpers | configs linked by name; QML modules installed; user-level `system/` helpers linked |
| `ryoku-blobs` | built (`plugin/build.sh`) |
| `ryoku-desktop-hyprland`, `ryoku-hypr-plugins`, SDDM/limine/snapshots | **not used** — Hyprland config is this repo's |
| `ryoku-palette-bridge`, `ryoku-rashin`, `gpk`, qylock, `skwd-paper-bin`, cursors | **not used** |

### Why upstream's `dev-run.sh` is not enough

`ryoku/shell/dev-run.sh` builds the daemon and QML modules and runs the shell
with `RYOKU_SHELL_DIR` pointing at the checkout. It is a developer loop for a
machine that **already runs Ryoku**: the packages there have put ~40 helpers on
`PATH`. On this machine the first version of the hook followed `dev-run.sh`
alone, and on 2026-10-31 the shell's log showed what that cost — every
helper the QML calls by bare name failed with "binary could not be found":

- `ryoku-app` → the browser/terminal/files/editor actions did nothing;
- `ryoku-hub`, `ryoku-host` → the Hub's desktop/config pages were empty;
- `ryostore` → no plugin or bundle catalog;
- no `ryogami` → no wallpaper surface, and hundreds of
  `QLocalSocket::ServerNotFoundError` from the shell polling `ryogami.sock`.

### Deployed mode, not `RYOKU_SHELL_DIR`

Quickshell does **not** canonicalize config paths. An instance started as
`qs -p <checkout>/…/shell` and the `qs -c shell ipc call …` that upstream
hard-codes in ~30 places (QML, the Go daemon, `ryostore`) are different
identities, so those calls miss the running shell. The daemon therefore runs in
its deployed mode — no `RYOKU_SHELL_DIR` — and every config resolves by name
through the `~/.config/quickshell/<name>` links, exactly as on a Ryoku install.
Because the daemon binary lives under `$HOME`, it adds `~/.local/lib/qt6/qml` to
the QML import path itself, and it finds `ryoku-reload-cover` next to its own
resolved executable — the bin dir.

The `~/.config/quickshell` names are generic (`shell`, `keys`, `stage`,
`plugins`, `inir`). The hook links them with `ensure_symlink … refuse`, so a
future shell claiming one of them fails the hook loudly instead of being
overwritten.

### The private `PATH`

`~/.local/lib/ryoku/bin` is put on `PATH` only by `scripts/launch-ryoku.sh`, the
one launch definition: `shells/ryoku/hyprland/execs.lua` calls it at login and
`launch_ryoku` in `switch-shell.sh` calls it on a switch. It starts `ryogami` if
it is not running and `exec`s the daemon, so the ryoku daemons and everything
they spawn see the bin dir, and Hyprland's own environment and the other shells
never do. A missing build stops it with a notification naming
`setup-ryoku.sh`. `tests/smoke.sh` pins the launcher's and `setup-ryoku.sh`'s
`RYOKU_BIN_DIR` to the same value and fails if either launch point bypasses
the launcher.

What goes in, and what deliberately does not:

| Linked | Not linked (and why) |
|---|---|
| every executable in `ryoku/shell/scripts` (`ryoku-app`, `ryoku-cmd-*`, `ryoku-kit`, `ryoku-eq`, `ryostage`, …) | `stash-install.sh` — installs packages |
| user-level `system/` helpers in `SYSTEM_HELPERS` (`ryoku-volume`, `ryoku-mic`, `ryoku-hw-backlight`, `ryoku-bluetooth-power`, …) | `ryoku-gpu*`, `ryoku-power*`, `ryoku-dns`, `ryoku-wifi-*` (root), `ryoku-pkg-*`, `ryostore-install`, `ryoku-docker` — dcli owns packages and `/etc` |
| `ryoku-plugins-place`, `ryoku-fastfetch` | `ryoku-idle` — kills the running `hypridle` and starts its own, which would outlive a shell switch |
| | `ryoku-wm-*` providers — see below |

The hook prunes its own links before relinking, so a helper renamed upstream
leaves nothing stale. If a `SYSTEM_HELPERS` path disappears upstream the hook
stops and names it.

## Runtime

`ryoku-shell daemon` owns the `qs -c shell` desktop and spawns/parks the Hub
and palettes on demand. It refuses to start a second daemon (single-instance
lock on `$XDG_RUNTIME_DIR/ryoku-shell.sock`), so `switch-shell.sh` uses
`pgrep -x ryoku-shell` as the "is it running" guard and calls the daemon's own
`quit` verb on teardown. `ryogami` is a sibling, not a child — the distro runs it
as a user unit — so its process, `ryogami-live` and the picker are matched
separately in `MATCH_SPECS`.

On first start ryogami picks a wallpaper from its library itself; pick another
with `SUPER + SHIFT + W`. The library is all of `~/Pictures/Wallpapers`
(recursive), so the house wallpapers other shells use appear next to ryoku's.
Delete `~/Pictures/Wallpapers/ryoku` to have the hook re-seed it.

### Default apps

`ryoku-app <role>` reads `~/.config/ryoku/desktop.json` → `desktop.apps`. The
hook seeds it once with the house apps (`zen-browser`, `wezterm`, `thunar`,
`wezterm start -- nvim`); the Hub's **Default Apps** page changes them. Without
the seed it falls back to firefox/chromium/zen, kitty and nautilus.

### Plugins

Shell plugins come from RyoStore (`ryostore`, a Go backend with a Quickshell
UI) and install under `~/.local/share/ryoku/plugins` with a receipt; placement
lives in `~/.config/ryoku/plugins.json`. Open it from the Hub's Add-ons page or
the bar's Community route. Store extras that need system packages go through
`ryostore-install`/`ryoku-pkg-*`, which are not installed: install those
packages through a dcli module instead.

Ryoku's **Hyprland** plugins (`ryoku-hypr-plugins`: hyprbars, hyprfocus,
borders-plus-plus; keysounds, hyprglass, hyprgrass, imgborders) are not used.
They load into the one compositor every shell shares and are ABI-pinned to the
Hyprland build.

### What the Hub cannot change here

The Hub's **Desktop** page saves through a `ryoku-wm-hyprland` provider binary
that re-authors `~/.config/hypr`. None is installed, so those saves report "no
provider" and write nothing — Hyprland settings stay in this repo. Two Hub
actions write into `~/.config/hypr` directly: importing a rice (`user.lua`) and
GPU mode (`gpu.lua`, which also needs the root-only `ryoku-gpu`). No shell
config here loads either file, and both are in `.gitignore` because
`~/.config/hypr` is a symlink into this repo.

## Keybinds

Keybinds call `ryoku-shell <verb>`, because upstream binds through Hyprland
global shortcuts that only exist under its own Hyprland config.
`dotfiles/hypr/shells/ryoku/hyprland/keybinds.lua` keeps the house
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
active — that combination is its overview. Media, screenshot and app binds use
the house tools (`wpctl`, `brightnessctl`, `grim`/`swappy`, wezterm, brave,
thunar) like every other shell; the daemon's OSD follows volume/brightness
changes either way. `ryoku-shell lock` (qylock) and `ryoku-shell voice`
(ryostage, an opt-in `ryostage install`) are not bound.

## Shared-surface audit: ryoku owns `~/.config/matugen`

**Read this before touching ryoku theming.** After generating a palette
(`matugen image … --dry-run`, which writes nothing), the daemon fans it out by
reading `~/.config/matugen/config.toml` — a path it gives no way to change —
filtering it into `~/.cache/ryoku/active-config.toml` and running
`matugen -c <that> json …`. So `setup-ryoku.sh` links `~/.config/matugen` to
the checkout's `ryoku/shell/matugen`, as a Ryoku install would.

That path used to be end4's. On 2026-10-31, the first session with a live
wallpaper daemon, every ryoku wallpaper change rendered end4's templates (end4's
palette, `hyprland/colors.lua`, GTK css and the tracked
`dotfiles/fuzzel/fuzzel_theme.ini`); a one-day `matugen` shim refused the pass
until end4 moved to `~/.config/matugen-end4` (my-ii fork commit `cd3447a2`,
[end4.md](end4.md)). `setup-ryoku.sh` stops with a message if the path still
points into end4's checkout. Every other shell passes its own `-c` (ambxst,
end4pc, dux generates its own; caelestia, noctalia, xenon and glyph do not use
matugen), so the default path is free for ryoku.

Window borders follow the same palette:
`dotfiles/hypr/shells/ryoku/hyprland/colors.lua` reads
`~/.cache/ryoku/hypr-colors.lua` at config parse time. Upstream also pushes
them live through `ryoku-wm-hyprland`, which is not installed, so a new palette
reaches the borders on the next login, switch or `hyprctl reload`.

### App theming starts off

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
Hub's appearance page is the opt-in. The core layer writes only new files no
other shell reads: kitty `current-theme.conf` (the house `kitty.conf` does not
include it), `btop/themes/ryoku.theme` (through the dcli `btop` link, so it is
in `.gitignore`), `fastfetch/ryoku-colors.json`, `qt6ct/colors/ryoku.conf` and
`~/.cache/ryoku`.

Ryoku also writes these gsettings keys, all in `shell-theme-state.sh`'s managed
set: `color-scheme`, `accent-color`, `gtk-theme`, `font-name`,
`document-font-name`, `monospace-font-name`. GTK stylesheets are written to
`gtk-{3,4}.0/gtk.css`, which the same script snapshots.

## Dependencies worth knowing about

- Packages also declared by end4/caelestia (`qt6-multimedia`,
  `qt6-imageformats`, `libqalculate`, `syntax-highlighting`) are repeated in the
  module on purpose: disabling another shell must not break this one.
- Already provided by the always-on base/terminal modules and not repeated:
  `matugen`, `brightnessctl`, `wl-clipboard`/`wl-clip-persist`, `cliphist`,
  `playerctl`, `cava`, `imagemagick`, `hyprpicker`, `hypridle`, `hyprsunset`,
  `gpu-screen-recorder`, `grim`/`slurp`, `kitty`, the xdg portals and the fonts.
- `quickshell` is **not** in the module: the provider has exactly one owner
  (`modules/shells-quickshell{,-git}.yaml`) and ryoku runs on whichever is
  enabled. See [../PACKAGE-CONFLICTS.md](../PACKAGE-CONFLICTS.md).
- `ryostore`'s Go module is not vendored upstream, so its build downloads
  modules on first run (cached under `~/go/pkg/mod`).
- `gpk` (the distro's package manager GUI) is not installed; the shell logs one
  "binary could not be found" for `gpk search --help` at startup — expected.

## Health check

```bash
scripts/doctor.sh                                   # checkout + ~/.config/quickshell links
scripts/update-shells.sh --status ryoku
git -C ~/.local/share/ryoku-shell status --short    # must stay clean
ls -l ~/.local/lib/ryoku/bin                        # binaries + helper links
find ~/.local/lib/ryoku/bin -xtype l                # dangling helper links (should be empty)
scripts/switch-shell.sh --dry-run ryoku
DCLI_HYPRMOD_SHELL=ryoku Hyprland --verify-config -c ~/.config/hypr/hyprland.lua
```

To see which helpers the running shell failed to find:

```bash
grep -a 'could not be found' /run/user/$UID/quickshell/by-id/*/log.log | sort -u
```
