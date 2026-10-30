# glyph

[Nebelung-cloud/glyph-rice](https://github.com/Nebelung-cloud/glyph-rice), a
Nothing-OS inspired rice: black, white dots, one red. One checkout supplies a
complete Hyprland Lua config and **two** Quickshell configs — `glyph` (the
desktop) and `rice` (a small shell switcher and the lock entry point).

| | |
|---|---|
| Module | `modules/shell-glyph.yaml` |
| Packages | declared in the module (`gnome-keyring`, `polkit-gnome`, `geoclue`, `gpu-screen-recorder`, `direnv`, `adw-gtk-theme`, `libnotify`, `bluez*`, AUR `qtengine`, `darkly-bin`, `bibata-cursor-theme-bin`) |
| Launch | `qs -p ~/.config/quickshell/glyph` |
| Setup hook | `scripts/setup-glyph.sh` |
| Update | `scripts/update-glyph.sh` (or `scripts/update-shells.sh glyph`) |

## Layout

| Path | What |
|---|---|
| `~/.local/share/glyph-rice` | Checkout, **source of truth**. origin `Nebelung-cloud/glyph-rice`, branch `main` — no personal fork |
| `~/.config/quickshell/glyph` → `config/quickshell/glyph` | The desktop QML (`shell.qml` at the root) |
| `~/.config/quickshell/rice` → `config/quickshell/rice` | The `rice` helper; the shell calls it by absolute path for `lock`/`list` |
| `~/.local/share/fonts/glyph` → `config/fonts` | Doto, Space Grotesk/Mono |
| `~/.config/demonshot` | `rules.json` and `hypridle.conf`, written by the shell's `Rules.qml` |
| `~/.local/state/rice/shell` | Which rice config `rice` starts; seeded to `glyph` |
| `~/Pictures/Wallpapers` | The wallpaper picker's source directory |
| `dotfiles/hypr/shells/glyph/hyprland.lua` | Loader for the checkout's `config/hypr/hyprland.lua` |

`~/.config/hypr` stays dcli's. Nothing in the checkout is symlinked over it.

## Why upstream's install.sh is never run

`install.sh` is written for a machine where the rice owns the desktop:

- it moves `~/.config/hypr` aside and symlinks the checkout's `config/hypr` in its
  place — the entry point, `shells/active.conf`, `common/` and every other shell's
  config live there;
- it links fish `config.fish`, kitty, qtengine, `starship.toml`, `fastfetch`,
  `btop`, `cava` and `gtk-{3,4}.0/gtk.css` — most of those are dcli dotfiles or
  shared by all ten shells;
- its package phase installs hyprland, quickshell, sddm and a full desktop.

`setup-glyph.sh` reproduces only the parts that do not collide: the checkout, the
two Quickshell configs, the bundled fonts, and the state directories.

## The loader, and why glyph needs one

glyph's own `hyprland.lua` requires its modules by **bare** name —
`require("hyprland.env")`, `require("variables")`, `require("scheme.demonshot")`.
Hyprland puts only `~/.config/hypr` on `package.path`, and
`~/.config/hypr/hyprland/` is a real directory other configurators write into, so
a short name can silently resolve to someone else's file. The entry point appends
the registry config's directory *after* `~/.config/hypr`, which is not enough.
`dotfiles/hypr/shells/glyph/hyprland.lua` therefore prepends the checkout's
config directory to `package.path` and then `dofile()`s upstream's entry point.
The house `common.*` layer still resolves because glyph has no files by those
names.

Your own binds belong in the checkout's `config/hypr/user.lua`: upstream loads it
last and gitignores it, so `git pull` never touches it. The loader itself only
adds the `SUPER + SHIFT + O` switcher — glyph does not bind that combination.

## Keybinds

Upstream's, with no house remapping (see its README for the full table):

| Bind | Action |
|---|---|
| `SUPER` (tap) | launcher |
| `SUPER + A` | quick settings |
| `SUPER + Space` | deck (dashboard from the bottom edge) |
| `SUPER + I` | preferences |
| `SUPER + V` | clipboard |
| `SUPER + .` | charms (emoji/kaomoji/symbols) |
| `SUPER + Print` / `Print` | screenshots and recording |
| `SUPER + SHIFT + W` | wallpapers |
| `SUPER + P` | VPN panel (Clash Verge) |
| `SUPER + Escape` | power menu |
| `SUPER + L` | lock (`rice lock`) |
| `SUPER + SHIFT + O` | dcli shell switcher (added by the loader) |

`SUPER + SUPER_L` (tap) is upstream's launcher and is not remapped. The house
`SUPER + SPACE` layout toggle does not apply while glyph is active; upstream's
keymap gives `SUPER + Space` to the deck.

## No graceful-quit IPC

glyph has no `quit`/`kill` verb of its own. `switch-shell.sh` matches the two
`qs -p …/quickshell/{glyph,rice}` invocations and reaps them with
`kill_matching`, the same way xenon and noctalia are handled. `rice kill` exists
but resolves the config from `~/.local/state/rice/shell`, which is not
necessarily the shell dcli is tearing down; the process match is authoritative.

`rice` is deliberately **not** on `PATH`. Its `rice switch <name>` writes the
rice state file and reloads Hyprland itself, which would bypass
`~/.config/hypr/shells/active.conf`. The shell's own calls use the absolute path
under `~/.config/quickshell/rice/`, and the in-shell Rice app is inert while only
one rice config is installed.

## Shared-surface audit

glyph writes two things outside its own namespace:

- **gsettings** `cursor-theme`/`cursor-size` at login (from `execs.lua`), and
  `gtk-theme`/`icon-theme` when `rice start` runs its `term()` step. All four keys
  are in `shell-theme-state.sh`'s managed set.
- **`gtk-{3,4}.0/gtk.css`** when `rice term` finds it absent or already a symlink.
  Both files are managed by `shell-theme-state.sh` (and it refuses to write a
  tracked path).

`rice term` also links `starship.toml`, `fastfetch`, `cava`, `btop`,
`qtengine.colors` and the `Rice` icon theme. The dcli-owned ones (`cava`, `btop`)
are skipped by rice's own "never replace a real file" guard. The rest are
terminal-prompt/Qt leftovers rather than the GTK/Qt colour surface, so they are
not snapshotted: switching away does not restore starship/fastfetch. That is
upstream's design, not a switch bug.

## Dependencies worth knowing about

- Everything already declared by base/terminal/file-manager/system modules is not
  repeated in `shell-glyph.yaml`: kitty, fish, starship, fastfetch, btop, cava,
  eza, zoxide, thunar, grim/slurp/swappy, cliphist, wl-clipboard, hyprpicker,
  imagemagick, libvips, the Noto/JetBrains Mono fonts and the xdg portals.
- `quickshell` is **not** in the module: the provider has exactly one owner
  (`modules/shells-quickshell{,-git}.yaml`), and glyph runs on whichever is
  enabled. See [../PACKAGE-CONFLICTS.md](../PACKAGE-CONFLICTS.md).
- `zen-browser`, `telegram-desktop` and `spotify-launcher` are bound by upstream
  but not declared: they are personal app choices, and a missing binary just
  leaves that bind inert.
- `polkit-gnome` is started by glyph's `execs.lua` at login. `hyprpolkitagent` is
  also installed by `base`; whichever claims the session's single agent slot
  first wins, which is harmless.

## Health check

```bash
scripts/doctor.sh
scripts/update-shells.sh --status glyph
git -C ~/.local/share/glyph-rice status --short
readlink -f ~/.config/quickshell/glyph
scripts/switch-shell.sh --dry-run glyph
DCLI_HYPRMOD_SHELL=glyph Hyprland --verify-config -c ~/.config/hypr/hyprland.lua
```
