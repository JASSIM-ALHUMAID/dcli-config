# dcli config — cachyos-desktop

Declarative system config managed with [dcli](https://gitlab.com/theblackdon) (v0.2.2):
packages, services, default apps, dotfiles, and bootstrap hooks for my
CachyOS + Hyprland setup running my **custom Caelestia shell fork**, with
**AMBXst**, **DankMaterialShell**, **Noctalia**, **end-4** and **end4-pC** as
alternate shells.

## What's in here

| Piece | Where | Notes |
|---|---|---|
| Host config | `hosts/cachyos-desktop.yaml` | enabled modules, services, default apps |
| Modules | `modules/*.yaml` | packages + dotfile mappings per area |
| Dotfiles | `dotfiles/` | symlinked to `~/.config/*` by `scripts/link-dotfiles.sh` |
| Hooks | `scripts/setup-caelestia.sh`, `setup-ambxst.sh`, `setup-end4.sh`, `setup-end4pc.sh`, `setup-noctalia.sh`, `setup-wezterm.sh` | clone + install each shell |
| Updates | `scripts/update-noctalia.sh`, `scripts/update-end4.sh`, `scripts/update-end4pc.sh` | pull latest QML/fork (noctalia: `--force` to re-download binary) |
| Shell switcher | `scripts/switch-shell.sh` | switch between caelestia / ambxst / dms / noctalia / end4 / end4pc |

WezTerm config is mirrored in `dotfiles/wezterm/`; its own history lives at
[JASSIM-ALHUMAID/wezterm](https://github.com/JASSIM-ALHUMAID/wezterm).

# Shell architecture

Six shells share one Hyprland session. Each owns its QML/UI process and its
own Hyprland config; this repo owns the entry point that picks between them.

## Where everything lives

Nothing below is guesswork — these are the actual paths on a synced machine.

| Path | What it is | Created by |
|---|---|---|
| `~/.config/hypr` → `dcli/dotfiles/hypr` | Hyprland entry point + per-shell configs | `link-dotfiles.sh` |
| `~/.config/environment.d` → `dcli/dotfiles/environment.d` | session env (`QML2_IMPORT_PATH`, `CAELESTIA_LIB_DIR`) | `link-dotfiles.sh` |
| `~/Projects/shell/real` | **caelestia fork checkout** — origin `plusdrag11/caelestia`, upstream `caelestia-dots/shell`. Source of truth for the shell's QML/C++ | `setup-caelestia.sh` |
| `~/.config/quickshell/caelestia` | the *installed* caelestia QML; overrides the packaged `/etc/xdg` copy. Refreshed by `~/Projects/shell/real/scripts/sync-live.sh` | fork |
| `~/.config/caelestia` → `~/Projects/shell/real/caelestia-configs` | caelestia's runtime config (`shell.json`, `keybinds.json`, `hypr-vars.lua`, `hypr-user.lua`) — version-controlled *inside the fork*, not here | `setup-caelestia.sh` |
| `~/.local/lib/qt6/qml` | Caelestia C++ plugin built from the fork; newer than the packaged one in `/usr/lib/qt6/qml` | `~/Projects/shell/real/scripts/install.sh --skip-sddm` |
| `~/.local/share/caelestia` | upstream `caelestia-dots/caelestia` dots clone. Provides `hypr/` (the Lua config caelestia loads) and is what `~/.config/uwsm` points into | `setup-caelestia.sh` |
| `~/.local/share/ambxst` → `~/.local/src/ambxst` | AMBXst fork (`plusdrag11/Ambxst`), ships its own `hyprland.lua` | `setup-ambxst.sh` |
| `~/.config/ambxst` → `dcli/dotfiles/ambxst` | AMBXst user config | `link-dotfiles.sh` |
| `~/.local/share/dots-hyprland` | end-4 fork (`plusdrag11/dots-hyprland`) | `setup-end4.sh` |
| `~/.config/quickshell/ii` → `dots-hyprland/dots/.config/quickshell/ii` | end-4's quickshell config | `setup-end4.sh` |
| `~/.local/share/end4-pC` | end4-pC fork (`pctrade/end4-pC`, branch `main`) — the repo root *is* the quickshell config (flat layout) | `setup-end4pc.sh` |
| `~/.config/quickshell/end4-pC` → `~/.local/share/end4-pC` | end4-pC's quickshell config | `setup-end4pc.sh` |
| `~/.config/quickshell/noctalia-shell` | Noctalia QML (`noctalia-dev/noctalia-shell`) | `setup-noctalia.sh` |
| `~/.local/opt/noctalia-qs` + `~/.local/bin/noctalia` | extracted quickshell fork + launcher wrapper | `setup-noctalia.sh` |
| `~/.config/noctalia` → `dcli/dotfiles/noctalia` | Noctalia user config | `link-dotfiles.sh` |
| `/usr/bin/dms` (pkg `dms-shell`) | DankMaterialShell binary | pacman |
| `~/.config/DankMaterialShell` → `dcli/dotfiles/DankMaterialShell` | DMS user config | `link-dotfiles.sh` |

Rule of thumb: **`~/.config/<x>` is a symlink into `dcli/dotfiles/<x>`** for
anything this repo owns, so editing the live config edits the repo. The two
deliberate exceptions are `~/.config/caelestia` (symlink into the fork, which
has its own git history) and `~/.config/uwsm` (symlink into the upstream
caelestia-dots clone — anything put there is lost on update).

## Per shell

| Shell | Launch command | Hyprland config | Its own config |
|---|---|---|---|
| **caelestia** | `caelestia shell -d` → `qs -c caelestia` | `~/.local/share/caelestia/hypr/hyprland.lua`, overridden by `~/.config/caelestia/hypr-vars.lua` (variables) and `hypr-user.lua` (sections/binds) | `~/.config/caelestia/` |
| **ambxst** | `ambxst` → `qs -p …/ambxst/shell.qml` | `~/.local/share/ambxst/hyprland.lua` + `shells/ambxst-overrides.lua` | `~/.config/ambxst` |
| **dms** | `dms run` | `shells/dms/hyprland.lua` (standalone) | `~/.config/DankMaterialShell` |
| **noctalia** | `~/.local/bin/noctalia` | `shells/noctalia/hyprland.lua` (standalone) | `~/.config/noctalia` |
| **end4** | `qs -c ii` | `shells/end4/hyprland.lua` (standalone) | `~/.config/quickshell/ii` |
| **end4pc** | `qs -c end4-pC` | `shells/end4pc/hyprland.lua` (standalone) | `~/.config/quickshell/end4-pC` |

caelestia and ambxst ship complete Hyprland configs, so we load theirs and
layer local tweaks on top. dms, noctalia, end4 and end4pc don't ship one we can
use, so each gets a standalone config here — seeded with the same input/layout
preferences and app binds, plus that shell's own IPC binds. They are fully
independent of each other; edit freely. (end4pc's IPC binds were reconciled
against end4-pC's own `GlobalShortcut` names, so a couple of the ii shell's
binds — cheatsheet, light/dark — are absent because that fork has no such
global.)

## How the pieces connect

```
~/.config/hypr/hyprland.lua          ← the only entry point Hyprland loads
  ├─ reads shells/active.conf        ← one bare shell name, written by switch-shell.sh
  ├─ appends <shell dir> to package.path
  ├─ seeds ~/.config/hypr/scheme/current.lua (colours) if absent
  ├─ dofile(<the shell's hyprland.lua>)
  └─ dofile(shells/<name>-overrides.lua)   ← if present; local tweaks on upstream configs
```

Connecting points worth knowing:

- **`shells/active.conf`** — the switch point. Holds a bare shell name (a
  legacy `source = …/<name>.conf` line is still parsed). It is committed, so
  the last-used shell survives replication.
- **`scripts/switch-shell.sh`** — kills every shell's processes (matching on
  distinctive command lines), rewrites `active.conf`, reloads Hyprland, then
  launches the chosen shell. No argument opens a themed fuzzel picker
  (`dotfiles/fuzzel/shell-picker.ini`).
- **`shells/<name>-overrides.lua`** — the hook for customising a shell whose
  Hyprland config is owned upstream, since editing the upstream file directly
  would be lost on update. Currently used by ambxst.
- **`dotfiles/environment.d/50-caelestia-qml.conf`** — puts
  `QML2_IMPORT_PATH=~/.local/lib/qt6/qml` in the *session* environment. Qt
  otherwise searches only `/usr/lib/qt6/qml`, where the packaged
  `caelestia-shell` plugin shadows the fork's newer build and the shell dies
  with `LogindManager is not a type`. uwsm runs the compositor as a systemd
  user unit, so environment.d reaches the compositor and every terminal —
  which Hyprland's own `env` cannot, as it applies only at compositor startup
  and only for whichever shell is active then.
- **Colours** — `caelestia scheme set` writes `~/.config/hypr/scheme/current.lua`,
  which the caelestia config `require`s as `scheme.current`. matugen writes
  `dotfiles/hypr/hyprland/colors.lua` and `hyprlock/colors.conf` for the rest.
- **Caelestia's keybinds** live in `~/.config/caelestia/keybinds.json` (editable
  in Nexus), applied at runtime by the shell's `services/KeybindApplier.qml`.
  They are *not* in any Hyprland config, and they vanish if the shell dies.

## Packaging traps

Several shells' packages would uninstall the stock quickshell that caelestia
and dms need, so they are deliberately **not** pacman-installed:

- **Noctalia** — `noctalia-shell` depends on `noctalia-qs`, which
  `Conflicts=quickshell`. `setup-noctalia.sh` clones the QML to
  `~/.config/quickshell/noctalia-shell` and *extracts* the `noctalia-qs`
  package to `~/.local/opt/noctalia-qs`, with a `~/.local/bin/noctalia`
  wrapper that launches/IPCs using that binary.
- **end-4** — `illogical-impulse-quickshell-git` likewise conflicts.
  `setup-end4.sh` runs the `ii` config on stock quickshell with the extra qt6
  deps installed separately. **end4-pC** (pctrade's fork) has the same trap:
  `setup-end4pc.sh` runs the `end4-pC` config on stock quickshell and installs
  the same dep set (all `--needed`, a no-op when end4 already installed them).
- **caelestia** — the `caelestia-shell` package is installed but entirely
  shadowed: its QML by `~/.config/quickshell/caelestia`, its C++ plugin by
  `QML2_IMPORT_PATH`. The `caelestia` CLI used by scripts and keybinds is a
  *separate* package, `caelestia-cli`.

## Hyprland Lua config rules

Hyprland loads `hyprland.conf` **or** `hyprland.lua`, never both. This setup is
fully Lua, which changes several things that older `.conf` docs get wrong:

- **`hyprctl keyword …` is rejected outright** ("keyword can't work with
  non-legacy parsers"). Use `hyprctl eval 'hl.config({…})'` /
  `hl.bind(…)` / `hl.unbind(…)`.
- **`hyprctl dispatch <name> <args>` does not parse.** Dispatchers take Lua:
  `hyprctl dispatch 'hl.dsp.submap("global")'`. Anything bound as
  `hl.dsp.exec_cmd("hyprctl dispatch …")` is silently dead — use the native
  dispatcher (`hl.dsp.focus`, `hl.dsp.window.*`, `hl.dsp.layout`, `hl.dsp.global`).
- **A top-level `hl.exec_cmd()` re-runs on every reload.** Wrap startup
  commands in `hl.on("hyprland.start", function() … end)` — that is the
  `exec-once` equivalent. Getting this wrong spawns a duplicate shell on every
  switch.
- **`require` only searches the main config's directory** (`~/.config/hypr`),
  which is why the entry point appends each shell's own directory to
  `package.path` before `dofile`ing it.
- **Bind options**: `{ release = true }` (bindr), `{ locked = true }` (bindl),
  `{ repeating = true }` (binde), `{ mouse = true }` (bindm),
  `{ click = true }` (bindc — a tap, gated by `binds:drag_threshold`, so it can
  share a key with a drag bind: caelestia's Super+Z/X are tap-to-switch-workspace,
  hold-to-move/resize).
- **Two binds on one combo both fire.** A duplicated launcher bind toggles it
  open then shut. Check with
  `hyprctl binds -j | jq 'group_by([.modmask,.key,.release])'`.
- **`hyprctl reload` wipes dynamically applied binds**, so whatever applies
  them must re-run on the `configreloaded` event.
- Types are strict: `explicit_column_widths` takes a **string**, not a table,
  and `hl.animation` needs a curve registered via `hl.curve(...)`.

Verify any config change with `hyprctl configerrors` — it is empty when clean.

# New machine bootstrap

1. Install [dcli](https://gitlab.com/theblackdon) (build from source → `~/.local/bin/dcli`).
2. Clone this repo:
   ```sh
   git clone https://github.com/plusdrag11/dcli-config.git ~/.config/dcli
   ```
3. Sync everything (installs packages, enables services, runs the module
   hooks — including `link-dotfiles.sh`, which symlinks `~/.config/<dir>` →
   `dotfiles/<dir>`; dcli's own YAML `dotfiles:` keys are ignored by dcli
   and kept as documentation):
   ```sh
   dcli sync
   ```
   Day-to-day updates after that: configs edit themselves in-repo through
   the symlinks, so publishing is just
   `cd ~/.config/dcli && git add -A && git commit -m "..." && git push`.
4. Log out and back in once so the session env (`QML2_IMPORT_PATH`,
   `CAELESTIA_LIB_DIR`) applies, then pick a shell with
   `scripts/switch-shell.sh [caelestia|ambxst|dms|noctalia|end4|end4pc]`.

AUR helper is `paru`; several packages (wezterm-nightly-bin, zen-browser-bin,
brave-nightly-bin, caelestia-*) come from AUR/chaotic.
