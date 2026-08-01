# xenon

[MannuVilasara/xenon-shell](https://github.com/MannuVilasara/xenon-shell), a
Quickshell config run as an independent config named `xenon`. It was previously
installed **system-wide by hand** at `/etc/xdg/quickshell/xenon`; this module
moves it to user scope like every other shell here.

| | |
|---|---|
| Module | `modules/shell-xenon.yaml` |
| Packages | none declared — the hook installs deps directly |
| Launch | `qs -c xenon` |
| Setup hook | `scripts/setup-xenon.sh` |
| Update | `scripts/update-xenon.sh` |

## Layout

| Path | What |
|---|---|
| `~/.local/share/xenon-shell` | Checkout, **source of truth**. origin `MannuVilasara/xenon-shell`, branch `main` — **no personal fork** |
| `~/.config/quickshell/xenon` → the checkout root | The repo root **is** the config (flat layout — `shell.qml` at top level, same as end4-pC) |
| `~/.config/xenon` → `dcli/dotfiles/xenon` | `config.json` only — dcli-managed dotfile |
| `~/.cache/xenon` | Generated data: `colors.json`, wallpaper thumbnails, `app-usage.json`, `current_wallpaper` — machine-local, **not** in this repo |
| `dotfiles/hypr/shells/xenon/hyprland.lua` | Its Hyprland config (standalone, in this repo) |

## The system copy is left alone

`/etc/xdg/quickshell/xenon` is a root-owned clone that **no package owns** —
it predates this module and was made by hand. It is deliberately **not** removed:
Quickshell resolves configs from `XDG_CONFIG_HOME` first, so
`~/.config/quickshell/xenon` shadows it and `qs -c xenon` runs the user checkout.
Nothing in `setup-xenon.sh` writes to `/etc`.

Confirm which copy is live:

```bash
readlink -f ~/.config/quickshell/xenon   # expect ~/.local/share/xenon-shell
```

If you ever do want the system copy gone, remove it by hand — it is not
`pacman`-owned, so nothing else tracks it:

```bash
sudo rm -rf /etc/xdg/quickshell/xenon
```

## No graceful-quit IPC

Unlike caelestia / dms / end4 / end4pc, xenon registers **no `kill` or `quit`
handler**. Its IPC targets (`Modules/Overlays/Overlays.qml`,
`Modules/Lock/Lock.qml`) are:

```
qs -c xenon ipc call launcher toggle
qs -c xenon ipc call clipboard toggle
qs -c xenon ipc call sidePanel open|close|toggle
qs -c xenon ipc call wallpaperpanel toggle
qs -c xenon ipc call powermenu toggle
qs -c xenon ipc call infopanel toggle
qs -c xenon ipc call settings toggle
qs -c xenon ipc call wallpaper set <path>
qs -c xenon ipc call cliphistService update
qs -c xenon ipc call lock lock
```

So `switch-shell.sh` kills it purely by command line
(`kill_matching -f "qs -c xenon"` — TERM, then KILL after 1s), the same way
noctalia is handled. **Do not "fix" this by adding a `qs -c xenon kill` line** to
the graceful-IPC block: that verb does not exist.

## Keybinds

`dotfiles/hypr/shells/xenon/hyprland/keybinds.lua`, house keymap:

| Bind | Action |
|---|---|
| `SUPER` (tap) / `SUPER + D` | launcher |
| `SUPER + V` | clipboard |
| `SUPER + N` | sidePanel (xenon's control centre — it has no notification-history panel) |
| `SUPER + I` | settings |
| `SUPER + CTRL + I` | infopanel |
| `SUPER + Escape` | powermenu |
| `SUPER + ALT + L` | lock |
| `SUPER + SHIFT + W` | wallpaper panel |
| `SUPER + SHIFT + O` | shell switcher |

Volume and brightness keys do **not** go through the shell: xenon reads PipeWire
directly (`Services/VolumeService.qml`) and shells out to `brightnessctl`
(`Services/BrightnessService.qml`), so the binds drive `wpctl`/`brightnessctl`
and the shell's OSD follows.

## Dependencies

Installed by the hook: `python`, `imagemagick`, `brightnessctl`, `cliphist`,
`wl-clipboard`, `ttf-jetbrains-mono-nerd`, `ttf-nerd-fonts-symbols`,
`papirus-icon-theme`. The bundled `Scripts/*.py` (Material colour generation,
wallpaper previews) are **stdlib-only** — there is no pip step.

`openrgb` is **optional and not installed**: it is only used when the
`openRgbDevices` key in `config.json` points at real hardware. Upstream defaults
that key to `[0]`, which makes every wallpaper change shell out to a missing
`openrgb` binary — so the tracked `dotfiles/xenon/config.json` sets it to `[]`,
which the shell treats as "no devices selected, skipping sync"
(`Services/WallpaperService.qml`). One harmless `openrgb --list-devices` warning
still appears at startup: that probe is unconditional. Install `openrgb` and tick
the devices in Settings → Services if you want RGB sync.

## Never install a packaged Quickshell fork

Same rule as every other Quickshell shell here — see
[../PACKAGE-CONFLICTS.md](../PACKAGE-CONFLICTS.md). `modules/shell-xenon.yaml`
declares no provider; xenon runs on whichever one is enabled.

## Updating

```bash
~/.config/dcli/scripts/update-xenon.sh
```

A plain `git pull --ff-only`. No fork, no submodules, no patch script — the
lowest-maintenance checkout here. Nothing in this repo modifies the working tree,
so the pull stays a fast-forward.

## The shell rewrites `config.json` on every launch

xenon's `Config.save()` writes the whole adapter back to
`~/.config/xenon/config.json` — which is a symlink into this repo — so **running
the shell can produce a git diff here** even if you changed nothing (it
reformats, and fills in keys it defaulted). That is expected, same as end4pc's
matugen output; commit or discard as you like.

## Status (2026-08-01)

- Cloned at `c4bc400` (`feat: hide bar feature`), origin *is* upstream, so
  updates are plain fast-forwards.
- Loads cleanly: `Configuration Loaded`, config read from
  `~/.config/xenon/config.json`.
- Switch round-trip verified — `switch-shell.sh xenon` then back leaves no
  `qs -c xenon` process behind, despite the missing quit IPC.
- Startup warnings that are **normal on a fresh cache**: `wallpapers.json` /
  `wallpreviews_large/*` missing until the wallpaper panel generates thumbnails
  (needs `imagemagick`, installed), and the one `openrgb --list-devices` probe.

## Health check

```bash
git -C ~/.local/share/xenon-shell status --short
readlink -f ~/.config/quickshell/xenon
readlink -f ~/.config/xenon
qs -c xenon 2>&1 | grep -E "Configuration Loaded|FATAL|not installed"
qs -c xenon ipc call launcher toggle    # while it is running
```
