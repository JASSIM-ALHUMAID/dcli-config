# caelestia

Custom fork of [caelestia-dots/shell](https://github.com/caelestia-dots/shell),
built from source. **The most maintenance-heavy shell here** — it is the only one
whose C++ plugin is compiled locally, and that plugin is the source of every
serious breakage so far.

| | |
|---|---|
| Module | `modules/caelestia.yaml` |
| Packages | runtime deps declared in the module (`caelestia-cli`, `libcava`, `ddcutil`, fonts, Qt bits, …); **no `caelestia-shell` package** (removed 2026-09-11) |
| Launch | `caelestia shell -d` |
| Setup hook | `scripts/setup-caelestia.sh` (opt-in clone, via `lib/hook-common.sh`) |
| Update | none by design — rebase by hand; `scripts/update-shells.sh --status` reports it |
| Provider | the fork's README asks for **`quickshell-git`**; stock is an open experiment — see below |

## Layout

| Path | What |
|---|---|
| `~/Projects/shell/real` | Fork checkout, **source of truth**. origin `JASSIM-ALHUMAID/my-caelestia`, upstream `caelestia-dots/shell`, branch **`my-caelestia`** — the fork's *default* branch is `main`, a mirror of upstream, so the branch must be pinned explicitly or a fresh clone has none of the customizations |
| `~/.config/quickshell/caelestia` | Installed QML — the shell's live config |
| `~/.local/lib/qt6/qml/{Caelestia,M3Shapes}` | Locally built C++ plugin; found through `QML2_IMPORT_PATH` |
| `~/.local/lib/caelestia/version` | `beat` version helper lib |
| `~/.config/caelestia` → `fork/caelestia-configs` | Runtime config, version-controlled **inside the fork** |
| `~/.local/share/caelestia/hypr/hyprland.lua` | Its Hyprland config (upstream caelestia-dots clone, not in this repo). caelestia does **not** use `dotfiles/hypr/common/`; its input lives in the fork's `hypr-vars.lua` |
| `~/.config/fish` | `dotfiles/fish` (dcli-owned; the caelestia banner shows only while caelestia is active) |
| `~/.config/fastfetch` | follows the active shell; for caelestia it is `~/.local/share/caelestia/fastfetch` |
| `~/.config/{foot,btop}` → `dcli/dotfiles/{foot,btop}` | **No longer caelestia's** — see below |

### foot and btop moved out of the clone (2026-08-20)

`~/.config/foot` and `~/.config/btop` used to symlink into
`~/.local/share/caelestia/{foot,btop}`. That clone is the upstream
`caelestia-dots/caelestia` dots checkout, which `setup-caelestia.sh` overwrites
on update — and the two dirs are not caelestia-only:

- DMS's matugen writes `foot/dank-colors.ini`
  (`/usr/share/quickshell/dms/matugen/configs/foot.toml`)
- noctalia's optional foot/btop template hooks rewrite `foot.ini` and `btop.conf`
- caelestia's own CLI writes `btop/themes/caelestia.theme`

So every other shell's terminal/TUI theming was landing in a clone that gets
wiped, and `git status` there was permanently dirty. They are dcli dotfiles now
(`link-dotfiles.sh` `TARGETS`); the generated siblings are gitignored, the
hand-written `foot.ini` and `btop.conf` are tracked.

## Provider: `quickshell-git`, stock untested

The fork's README asks for `quickshell-git`, so that is the default provider
(`modules/shells-quickshell-git.yaml`). Until 2026-09-11 the `caelestia-shell`
package hard-depended on it, and `modules/caelestia.yaml` declared
`conflicts: [shells-quickshell]`; neither holds any more. `scripts/switch-quickshell.sh
stock` now warns and asks for confirmation (`--yes` without a tty) instead of
refusing. Whether stock 0.3.2 runs the fork is the pending experiment in
[../PACKAGE-CONFLICTS.md](../PACKAGE-CONFLICTS.md).

## Packaging traps (history — apply only if the package is reinstalled)

Traps 1-3 below were written while the `caelestia-shell` package was installed and
shadowed by the fork. The package is gone, so the "multiple registrations" and
"LogindManager" failures cannot recur unless it is reinstalled; the CMake target name
(trap 1) and the stale-`.so` rule (trap 2) are still correct build hygiene for the
fork itself.

## Trap 1: the plugin target name

**`plugin/src/Caelestia/CMakeLists.txt` must declare `qml_module(caelestia-core`,
never `qml_module(caelestia`.**

That target name determines the built filenames. Upstream renamed it in commit
`3d97d504` (shipped since v2.1.0), so the package ships
`libcaelestia-coreplugin.so` + `caelestia-core.qmltypes`. If the fork builds
different names, two `.so` files both declare `module Caelestia` and Qt aborts:

```
FATAL: Cannot add multiple registrations for Caelestia
```

Stock Quickshell tolerated the duplicate; **`quickshell-git` does not.** So this
bug can sit latent for days and then detonate on a provider swap.

**A rebase has already silently reverted this once** — commit `6fb4eafa "apply all
my-caelestia customizations on upstream/main"` restored the pre-2.1.0 name and
broke the shell on 2026-07-25. Check it after every rebase:

```bash
grep -n '^qml_module' ~/Projects/shell/real/plugin/src/Caelestia/CMakeLists.txt
# must print: qml_module(caelestia-core
```

## Trap 2: stale `.so` files

`cmake --install` only overwrites files it knows about, so an old `.so` from a
previous build survives inside a module dir — and there it beats the fresh one in
`../lib/` for the plugin's `$ORIGIN` rpath. The module then silently loads
outdated types:

```
ERROR: ButtonRow is not a type
```

All three installers now `rm -rf` the plugin dirs first. They never wipe
`~/.config/quickshell/caelestia`, because `config/` inside it is runtime state.

## Trap 3: `CMAKE_INSTALL_PREFIX` alone is not enough

`INSTALL_QMLDIR`, `INSTALL_QSCONFDIR` and `INSTALL_LIBDIR` default to *relative*
paths (`usr/lib/qt6/qml`, …). Passing them as absolute is what makes the prefix
irrelevant. Setting only `-DCMAKE_INSTALL_PREFIX="$HOME/.local"` installs to
`~/.local/usr/lib/...` — a stray tree that then rots and feeds trap 2.

## Installing

```bash
cd ~/Projects/shell/real
./scripts/install.sh --skip-sddm     # QML + C++ plugin, no sudo needed
```

Installs entirely under `~/.local` and `~/.config`, so pacman-owned files are never
touched. Run it without `--skip-sddm` once on a fresh machine for the SDDM lock
theme (needs sudo; also writes `/etc/sudoers.d/caelestia-sddm-sync`).

`devfiles/install-user.fish` does the same thing and additionally writes the
session env blocks (`hypr-user.conf`, `~/.config/uwsm/env`). Keep the three
`INSTALL_*` vars in sync between it and `scripts/install.sh`.

**Avoid `devfiles/install-system.fish`** on this machine — it installs to `/usr`
with sudo.

**Never run upstream's `install.fish`.** `devfiles/` exists only in the fork;
upstream's own installer installs system-wide with sudo. There is no "upstream
first, then fork" step — the fork is the only thing to install.

## Day-to-day

```bash
./scripts/sync-live.sh                 # QML only + restart; does NOT rebuild C++
./scripts/install.sh --skip-sddm       # needed whenever plugin/ changes
```

`sync-live.sh` warns if `plugin/` or `CMakeLists.txt` has pending changes, since it
cannot pick them up. **If the shell dies right after a `sync-live.sh`, the answer
is almost always that you needed `install.sh`.**

## Launch environment

Both vars are required, and Hyprland only applies its own `env` at startup — so a
session started before they were added never has them.
`dotfiles/environment.d/50-caelestia-qml.conf` provides them session-wide, and
`switch-shell.sh`'s `launch_caelestia` sets them explicitly:

```bash
QML2_IMPORT_PATH="$HOME/.local/lib/qt6/qml"    # fork plugin, not the package's
CAELESTIA_LIB_DIR="$HOME/.local/lib/caelestia"
```

Without the first, Qt does not search `~/.local/lib/qt6/qml` and the shell cannot
load its own plugin; with the `caelestia-shell` package installed it would pick up
the packaged one and die with `LogindManager is not a type` — the fork replaced
upstream's `sessionmanager` with its own `logindmanager`, its one intentional plugin
divergence.

## Other notes

- **Keybinds live in `~/.config/caelestia/keybinds.json`** (editable in Nexus),
  applied at runtime by `services/KeybindApplier.qml`. They are in no Hyprland
  config and **vanish if the shell dies**.
- There is no `caelestia-shell` package. The `caelestia` CLI used by scripts and
  keybinds is the separate package `caelestia-cli`.
- Shaders are committed as `.qsb` next to their `.frag`. After editing a `.frag`,
  run `scripts/compile-shaders.sh` and commit both.
- `plugin/cmake/qml-module.cmake` prints a nonsense `QML install dir:` line
  (prefix + absolute dir concatenated). Cosmetic only.

## Health check

```bash
cd ~/Projects/shell/real                                     # paths below are fork-relative
grep -n '^qml_module' plugin/src/Caelestia/CMakeLists.txt    # -> qml_module(caelestia-core
find ~/.local/lib/qt6/qml ! -newermt "$(date +%F)" -type f   # stale files: expect none
pacman -Q caelestia-shell                                    # -> not found (expected)

~/.config/dcli/scripts/doctor.sh                                  # checkout, links, provider, configerrors

# Launches the shell — run it when you can see the screen, not from a script.
env QML2_IMPORT_PATH=~/.local/lib/qt6/qml CAELESTIA_LIB_DIR=~/.local/lib/caelestia \
  qs -c caelestia 2>&1 | grep -E "Configuration Loaded|FATAL|not a type"
```
