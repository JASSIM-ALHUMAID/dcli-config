# end4

end-4's [dots-hyprland](https://github.com/end-4/dots-hyprland) ("illogical
impulse"), run from a custom fork as the Quickshell config named `ii`.

| | |
|---|---|
| Module | `modules/shell-end4.yaml` |
| Packages | declared in the module (Qt deps, runtime tools, two AUR) — duplicated in `shell-end4pc` on purpose |
| Launch | `qs -c ii` |
| Setup hook | `scripts/setup-end4.sh` |
| Update | `scripts/update-end4.sh` (or `scripts/update-shells.sh end4`) |

## Layout

| Path | What |
|---|---|
| `~/.local/share/dots-hyprland` | Fork checkout, **source of truth**. origin `JASSIM-ALHUMAID/my-end4`, upstream `end-4/dots-hyprland`, branch `my-ii` |
| `~/.config/quickshell/ii` → `dots-hyprland/dots/.config/quickshell/ii` | The Quickshell config |
| `~/.config/matugen` → `dots-hyprland/dots/.config/matugen` | Theming config, **owned by this shell** |
| `~/.config/illogical-impulse` | Runtime state written by the shell itself |
| `dotfiles/hypr/shells/end4/hyprland.lua` | Its Hyprland config: end4's own tree under `shells/end4/hyprland/`, house overrides under `shells/end4/custom/`, all `require`d as `shells.end4.*` |
| `~/.config/hypr/hyprland/shellOverrides/main.lua` | What the ii settings app writes (`HyprlandConfig.qml`, `shellOverridesPath`); loaded last so the app's edits apply. The house `kb_layout` and `layout` lines were stripped from it and will return if the app rewrites those keys |

Neither symlink is a dcli `dotfiles:` entry — both point into the checkout, and a
dotfiles sync must not replace them.

## Never run end-4's own installer

`sdata/dist-arch/install-deps.sh` in the checkout does two things that would wreck
this machine:

| Line | What |
|---|---|
| 96 | Builds and installs the `illogical-impulse-quickshell-git` metapkg — a conflicting Quickshell provider |
| 20 | Replaces the entire hypr stack with `-git` builds: `hyprland`, `hyprlock`, `hypridle`, `hyprutils`, `hyprlang`, `hyprpicker`, `hyprcursor`, `xdg-desktop-portal-hyprland`, … |

There is no "run upstream's installer, then apply my fork" step. `setup-end4.sh`
clones the fork; the fork's **extra dependencies** are declared as regular packages
in `modules/shell-end4.yaml` (not in the hook: hooks run once, module packages are
re-checked every sync):

- **Qt deps** from the fork's PKGBUILD: `qt6-5compat`, `qt6-imageformats`,
  `qt6-multimedia`, `qt6-positioning`, `qt6-quicktimeline`, `qt6-sensors`,
  `qt6-svg`, `qt6-tools`, `qt6-translations`, `qt6-virtualkeyboard`,
  `qt6-wayland`, `kirigami`, `kdialog`, `syntax-highlighting`
- **AUR:** `qt6-avif-image-plugin`, `songrec`
- **Runtime tools** curated from the illogical-impulse meta packages: `cliphist`,
  `cava`, `playerctl`, `fuzzel`, `hypridle`, `hyprlock`, `hyprpicker`,
  `hyprshot`, `hyprsunset`, `wl-clipboard`, `wf-recorder`, `tesseract`, …

Deliberately skipped: the `illogical-impulse-*` meta packages themselves, the
xdg-desktop-portals (handled elsewhere), and the python/uv toolchain (only needed
by end-4's own installer).

## Submodules are mandatory

The `ii` config has a git submodule at `modules/common/widgets/shapes`. Without it
the shell fails to load:

```
module qs.modules.common.widgets.shapes is not installed
```

`setup-end4.sh` clones with `--recurse-submodules --shallow-submodules` and then
runs `submodule update --init --recursive` unconditionally, so it self-heals on a
pre-existing clone. **After any manual `git pull` here, re-run:**

```bash
git -C ~/.local/share/dots-hyprland submodule update --init --recursive --depth 1
```

The clone is deliberately **full, not shallow** — the fork's branch history
matters; only submodules are shallow.

## Shares `~/.config/matugen` with end4pc

This shell **owns** `~/.config/matugen` (symlink into its checkout). That is why
[end4pc](end4pc.md) needed `patch-end4pc.sh`: upstream end4-pC also expects
`~/.config/matugen`, so running both would have had them fighting over one config.
end4pc was repointed at its own `~/.config/matugen-end4pc` copy instead.

Runtime state is separate (`~/.config/illogical-impulse` vs
`~/.config/illogical-impulse-pC`), so the two coexist safely.

## Health check

```bash
scripts/doctor.sh
scripts/update-shells.sh --status end4
git -C ~/.local/share/dots-hyprland status --short
git -C ~/.local/share/dots-hyprland submodule status
readlink -f ~/.config/quickshell/ii     # must point into the checkout
qs -c ii 2>&1 | grep -E "Configuration Loaded|FATAL|not installed"
```
