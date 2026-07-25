# caelestia

Custom fork of [caelestia-dots/shell](https://github.com/caelestia-dots/shell),
built from source. **The most maintenance-heavy shell here** — it is the only one
whose C++ plugin is compiled locally, and that plugin is the source of every
serious breakage so far.

| | |
|---|---|
| Module | `modules/caelestia.yaml` |
| Packages | `caelestia-cli`, `caelestia-meta`, `caelestia-shell` |
| Launch | `caelestia shell -d` |
| Setup hook | `scripts/setup-caelestia.sh` |
| Provider | **`quickshell-git` only** — see below |

## Layout

| Path | What |
|---|---|
| `~/Projects/shell/real` | Fork checkout, **source of truth**. origin `plusdrag11/caelestia`, upstream `caelestia-dots/shell`, branch **`my-caelestia-rebased`** — the fork's *default* branch is `main`, a mirror of upstream, so the branch must be pinned explicitly or a fresh clone has none of the customizations |
| `~/.config/quickshell/caelestia` | Installed QML — overrides the package's `/etc/xdg` copy |
| `~/.local/lib/qt6/qml/{Caelestia,M3Shapes}` | Locally built C++ plugin — overrides the package's `/usr/lib` copy |
| `~/.local/lib/caelestia/version` | `beat` version helper lib |
| `~/.config/caelestia` → `fork/caelestia-configs` | Runtime config, version-controlled **inside the fork** |
| `~/.local/share/caelestia/hypr/hyprland.lua` | Its Hyprland config (not in this repo) |

## Why it needs `quickshell-git`

AUR `caelestia-shell` 2.2.0 changed its dependency from `quickshell` to
`quickshell-git`. `modules/caelestia.yaml` therefore declares
`conflicts: [shells-quickshell]` — caelestia cannot run on the stock provider, and
`scripts/switch-quickshell.sh stock` refuses while this module is enabled.

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

Installs entirely under `~/.local` and `~/.config`, so pacman-owned files are
never touched and a `caelestia-shell` package upgrade cannot clobber the build.
Confirm with `pacman -Qkk caelestia-shell` → `0 altered files`.

`devfiles/install-user.fish` does the same thing and additionally writes the
session env blocks (`hypr-user.conf`, `~/.config/uwsm/env`). Keep the three
`INSTALL_*` vars in sync between it and `scripts/install.sh`.

**Avoid `devfiles/install-system.fish`** on this machine — it installs to `/usr`
with sudo and collides with the package.

**Never run upstream's `install.fish`.** `devfiles/` exists only in the fork;
upstream's own installer installs system-wide with sudo and collides with the
`caelestia-shell` package. There is no "upstream first, then fork" step — the fork
is the only thing to install.

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
session started before they were added never has them. `switch-shell.sh` sets them
explicitly:

```bash
QML2_IMPORT_PATH="$HOME/.local/lib/qt6/qml"    # fork plugin, not the package's
CAELESTIA_LIB_DIR="$HOME/.local/lib/caelestia"
```

Without the first, the packaged plugin is used and the shell dies with
`LogindManager is not a type` — the fork replaced upstream's `sessionmanager` with
its own `logindmanager`, its one intentional plugin divergence.

## Other notes

- **Keybinds live in `~/.config/caelestia/keybinds.json`** (editable in Nexus),
  applied at runtime by `services/KeybindApplier.qml`. They are in no Hyprland
  config and **vanish if the shell dies**.
- `caelestia-shell` the package is installed but entirely shadowed. The
  `caelestia` CLI used by scripts and keybinds is a *separate* package,
  `caelestia-cli`.
- Shaders are committed as `.qsb` next to their `.frag`. After editing a `.frag`,
  run `scripts/compile-shaders.sh` and commit both.
- `plugin/cmake/qml-module.cmake` prints a nonsense `QML install dir:` line
  (prefix + absolute dir concatenated). Cosmetic only.

## Health check

```bash
cd ~/Projects/shell/real                                     # paths below are fork-relative
grep -n '^qml_module' plugin/src/Caelestia/CMakeLists.txt    # -> qml_module(caelestia-core
find ~/.local/lib/qt6/qml ! -newermt "$(date +%F)" -type f   # stale files: expect none
pacman -Qkk caelestia-shell                                  # -> 0 altered files

# Launches the shell — run it when you can see the screen, not from a script.
env QML2_IMPORT_PATH=~/.local/lib/qt6/qml CAELESTIA_LIB_DIR=~/.local/lib/caelestia \
  qs -c caelestia 2>&1 | grep -E "Configuration Loaded|FATAL|not a type"
```
