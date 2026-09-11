# dcli config — all-shells

Declarative system config managed with [dcli](https://gitlab.com/theblackdon) (v0.2.2):
packages, services, default apps, dotfiles, and bootstrap hooks for my
Hyprland setup running my **custom Caelestia shell fork**, with
**AMBXst**, **DankMaterialShell**, **Noctalia**, **end-4**, **end4-pC**,
**omarchy**, **xenon** as alternate shells.

## What's in here

| Piece | Where | Notes |
|---|---|---|
| Host config | `hosts/all-shells.yaml` | enabled modules, services, default apps |
| Modules | `modules/*.yaml` | packages + dotfile mappings per area |
| Dotfiles | `dotfiles/` | symlinked to `~/.config/*` by `scripts/link-dotfiles.sh` |
| Hooks | `scripts/setup-caelestia.sh`, `setup-ambxst.sh`, `setup-end4.sh`, `setup-end4pc.sh`, `setup-noctalia.sh`, `setup-omarchy.sh`, `setup-xenon.sh`, `setup-wezterm.sh` | clone + install each shell |
| Checkout patches | `scripts/patch-end4pc.sh` | repoint upstream checkouts at their own matugen/config paths; idempotent, re-run by the setup and update hooks |
| Updates | `scripts/update-end4.sh`, `scripts/update-end4pc.sh`, `scripts/update-omarchy.sh`, `scripts/update-xenon.sh` | pull latest fork checkouts (noctalia updates via `dcli update`, since it is a cachyos/extra package) |
| Shell switcher | `scripts/switch-shell.sh` | switch between caelestia / ambxst / dms / noctalia / end4 / end4pc / omarchy / xenon |
| Theme state | `scripts/shell-theme-state.sh` | per-shell snapshot/restore of the shared GTK/Qt/cursor surface, driven by the switcher |
| Provider switcher | `scripts/switch-quickshell.sh` | swap the quickshell provider: stock ↔ quickshell-git |
| Docs | `docs/` | see below |

WezTerm config is mirrored in `dotfiles/wezterm/`; its own history lives at
[JASSIM-ALHUMAID/wezterm](https://github.com/JASSIM-ALHUMAID/wezterm).

## Docs

| Doc | Read it when |
|---|---|
| [docs/NOTES.md](docs/NOTES.md) | Machine-wide gotchas: dcli behaviours that surprise you, whether it's safe to update, how to debug a shell that won't start |
| [docs/shells/](docs/shells/) | One page per shell — layout, traps, install/update, health check |
| [docs/PACKAGE-CONFLICTS.md](docs/PACKAGE-CONFLICTS.md) | Anything involving `quickshell` vs `quickshell-git` |
| [docs/LUA-MODULES.md](docs/LUA-MODULES.md), [docs/DIRECTORY-MODULES.md](docs/DIRECTORY-MODULES.md) | Writing dcli modules |
| [docs/CHEAT-SHEET.md](docs/CHEAT-SHEET.md) | dcli command reference |

**Three things worth knowing before you touch anything:**

1. `dotfiles:` keys in flat YAML modules are **documentation only** —
   `scripts/link-dotfiles.sh` does the real linking, from its own `TARGETS` array.
2. Only one quickshell provider can be installed. It's owned by
   `modules/shells-quickshell{,-git}.yaml`; swap it with
   `scripts/switch-quickshell.sh`, never `dcli module enable` alone.
3. Theming regenerates files that are committed here, so unexpected git changes
   after a wallpaper change are normal.

# Shell architecture

Nine shells share one Hyprland session. Each owns its QML/UI process and its
own Hyprland config; this repo owns the entry point that picks between them.

## Where everything lives

Nothing below is guesswork — these are the actual paths on a synced machine.

| Path | What it is | Created by |
|---|---|---|
| `~/.config/hypr` → `dcli/dotfiles/hypr` | Hyprland entry point + per-shell configs | `link-dotfiles.sh` |
| `~/.config/environment.d` → `dcli/dotfiles/environment.d` | session env (`QML2_IMPORT_PATH`, `CAELESTIA_LIB_DIR`) | `link-dotfiles.sh` |
| `~/.config/{foot,btop}` → `dcli/dotfiles/{foot,btop}` | terminal + TUI config **shared by every shell** — several of them write generated palettes in here, so it cannot live in a shell's own checkout (it used to be caelestia's) | `link-dotfiles.sh` |
| `~/Projects/shell/real` | **caelestia fork checkout** — origin `plusdrag11/caelestia`, upstream `caelestia-dots/shell`. Source of truth for the shell's QML/C++ | `setup-caelestia.sh` |
| `~/.config/quickshell/caelestia` | the *installed* caelestia QML; overrides the packaged `/etc/xdg` copy. Refreshed by `~/Projects/shell/real/scripts/sync-live.sh` | fork |
| `~/.config/caelestia` → `~/Projects/shell/real/caelestia-configs` | caelestia's runtime config (`shell.json`, `keybinds.json`, `hypr-vars.lua`, `hypr-user.lua`) — version-controlled *inside the fork*, not here | `setup-caelestia.sh` |
| `~/.local/lib/qt6/qml` | Caelestia C++ plugin built from the fork; newer than the packaged one in `/usr/lib/qt6/qml` | `~/Projects/shell/real/scripts/install.sh --skip-sddm` |
| `~/.local/share/caelestia` | upstream `caelestia-dots/caelestia` dots clone. Provides `hypr/` (the Lua config caelestia loads) and is what `~/.config/uwsm` points into | `setup-caelestia.sh` |
| `~/.local/share/ambxst` → `~/.local/src/ambxst` | AMBXst fork (`plusdrag11/Ambxst`), ships its own `hyprland.lua` | `setup-ambxst.sh` |
| `~/.config/ambxst` → `dcli/dotfiles/ambxst` | AMBXst user config | `link-dotfiles.sh` |
| `~/.local/share/dots-hyprland` | end-4 fork (`plusdrag11/dots-hyprland`) | `setup-end4.sh` |
| `~/.config/quickshell/ii` → `dots-hyprland/dots/.config/quickshell/ii` | end-4's quickshell config | `setup-end4.sh` |
| `~/.local/share/end4-pC` | end4-pC fork (`plusdrag11/end4-pC`, branch `my-end4pc`, upstream `pctrade/end4-pC`) — the repo root *is* the quickshell config (flat layout) | `setup-end4pc.sh` |
| `~/.config/quickshell/end4-pC` → `~/.local/share/end4-pC` | end4-pC's quickshell config | `setup-end4pc.sh` |
| `/usr/bin/noctalia` (pkg `noctalia`, CachyOS `cachyos-extra-v3`) | Noctalia v5 binary — native C++/Wayland, no Quickshell | cachyos/extra (paru) |
| `~/.config/noctalia` → `dcli/dotfiles/noctalia` | Noctalia v5 config (`config.toml`, TOML, hot-reloaded) | `link-dotfiles.sh` |
| `/usr/bin/dms` (pkg `dms-shell`) | DankMaterialShell binary | pacman |
| `~/.config/DankMaterialShell` → `dcli/dotfiles/DankMaterialShell` | DMS user config | `link-dotfiles.sh` |
| `~/.local/share/omarchy` | omarchy checkout (`basecamp/omarchy`, branch `quattro`, v4.0.0.alpha) — this is `$OMARCHY_PATH`. Its `shell/` is the Quickshell shell and its `bin/` must be on `PATH` | `setup-omarchy.sh` |
| `~/.config/omarchy` → `dcli/dotfiles/omarchy` | omarchy user config (`shell.json`, hooks, extensions) | `link-dotfiles.sh` |
| `~/.local/state/omarchy` | omarchy's generated state (`current/theme`, `toggles/`, `done/`, `indicators/`, `agents/`, `workspace-layouts/`, `notifications/`, `clipboard-history.json`, `monitor-scaling.log`) — machine-local, **not** in this repo | `omarchy-theme-set` |
| `~/.local/share/xenon-shell` | xenon checkout (`MannuVilasara/xenon-shell`, branch `main`) — the repo root *is* the quickshell config (flat layout) | `setup-xenon.sh` |
| `~/.config/quickshell/xenon` → `~/.local/share/xenon-shell` | xenon's quickshell config; shadows the hand-made root clone still sitting at `/etc/xdg/quickshell/xenon` | `setup-xenon.sh` |
| `~/.config/xenon` → `dcli/dotfiles/xenon` | xenon user config (`config.json`) — generated data stays in `~/.cache/xenon` | `link-dotfiles.sh` |
| `/usr/bin/uwsm` (pkg `uwsm`, `base.yaml`) | User Workspace State Manager — starts the Hyprland session after SDDM login | `dcli sync` |
| SDDM (`/etc/sddm.conf`, pkg `sddm`) | display manager for Hyprland. NOT declared in any dcli module — on CachyOS it is a default install; on a fresh non-CachyOS machine, install it separately. `/etc/sudoers.d/caelestia-sddm-sync` (NOPASSWD sudoers for the caelestia wallpaper sync script) is set up by the caelestia fork's `install.sh` (without `--skip-sddm`) — see below. | manual / fork `install.sh` |

Rule of thumb: `~/.config/<x>` is a symlink into `dcli/dotfiles/<x>`
anything this repo owns, so editing the live config edits the repo. The two
deliberate exceptions are `~/.config/caelestia` (symlink into the fork, which

## Per shell

**Each shell has its own notes page in [docs/shells/](docs/shells/)** — layout,
traps, install/update procedure and a health check. Start with
[docs/shells/README.md](docs/shells/README.md) for the rules that apply to all of
them, and [docs/NOTES.md](docs/NOTES.md) for machine-wide gotchas.

| Shell | Launch command | Hyprland config | Its own config |
|---|---|---|---|
| **caelestia** | `caelestia shell -d` → `qs -c caelestia` | `~/.local/share/caelestia/hypr/hyprland.lua`, overridden by `~/.config/caelestia/hypr-vars.lua` (variables) and `hypr-user.lua` (sections/binds) | `~/.config/caelestia/` |
| **ambxst** | `ambxst` → `qs -p …/ambxst/shell.qml` | `~/.local/share/ambxst/hyprland.lua` + `shells/ambxst-overrides.lua` | `~/.config/ambxst` |
| **dms** | `dms run` | `shells/dms/hyprland.lua` (standalone) | `~/.config/DankMaterialShell` |
| **noctalia** | `noctalia` | `shells/noctalia/hyprland.lua` (standalone) | `~/.config/noctalia` |
| **end4** | `qs -c ii` | `shells/end4/hyprland.lua` (standalone) | `~/.config/quickshell/ii` |
| **end4pc** | `qs -c end4-pC` | `shells/end4pc/hyprland.lua` (standalone) | `~/.config/quickshell/end4-pC` |
| **omarchy** | `quickshell -n -p $OMARCHY_PATH/shell` | `shells/omarchy/hyprland.lua` — a **loader** that runs omarchy's own `default/hypr/*.lua`, then layers house tweaks | `~/.config/omarchy` |
| **xenon** | `qs -c xenon` | `shells/xenon/hyprland.lua` (standalone) | `~/.config/xenon` |

caelestia, ambxst and omarchy ship complete Hyprland configs, so we load theirs
and layer local tweaks on top. dms, noctalia, end4, end4pc and xenon don't
ship one we can use, so each gets a standalone config here — seeded with the same
input/layout preferences and app binds, plus that shell's own IPC binds. They are fully
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
- **`scripts/shell-theme-state.sh`** — called by the switcher to snapshot the
  *shared* app theming surface (GTK, Qt, cursor, Thunar's colours, rofi) per
  shell and replay it on the way back, since six of the nine shells overwrite
  one global copy of it. Snapshots live in `state/shell-theme/<name>/`;
  `DCLI_SKIP_THEME_STATE=1` bypasses it. See
  [docs/shells/README.md](docs/shells/README.md), "The shared surface".
- **`shells/<name>-overrides.lua`** — the hook for customising a shell whose
  Hyprland config is owned upstream, since editing the upstream file directly
  would be lost on update. Currently used by ambxst. omarchy does *not* use it:
  the file the entry point loads for omarchy is already ours, so its tweaks live
  at the bottom of `shells/omarchy/hyprland.lua`.
- **omarchy has no `environment.d` file, deliberately.** `$OMARCHY_PATH` must not
  come from the environment: `os.getenv()` in a Lua config runs at parse time, and
  a login-scoped variable that is set to the *wrong* value silently beats any
  fallback — which is how a `%h` that `environment.d` does not expand once left the
  desktop with 3 binds instead of 216, with an empty `hyprctl configerrors`. A bad
  path makes omarchy's `require_all.files()` shell out to `find` and find nothing,
  registering **no binds and no error**. `shells/omarchy/hyprland.lua` therefore
  probes for the checkout and injects the path into `package.path` and
  `default.hypr.paths` itself; omarchy's own `envs.lua` covers spawned clients.
  See [docs/shells/omarchy.md](docs/shells/omarchy.md).
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

Every packaged quickshell fork `Conflicts=quickshell`, so only one provider may be
installed. That provider is owned declaratively by one of two modules —
`shells-quickshell` (stock) or `shells-quickshell-git` — which list each other in
`conflicts:`. `shells-quickshell-git` is the enabled default, because
`caelestia-shell` 2.2.0 requires it and every other shell resolves under it via
`Provides=quickshell`. Switch with `scripts/switch-quickshell.sh [stock|git]`;
never with `dcli module enable` alone. Full details in
[docs/PACKAGE-CONFLICTS.md](docs/PACKAGE-CONFLICTS.md).

Shells whose own fork packages are deliberately **not** pacman-installed:

- **end-4** — `illogical-impulse-quickshell-git` is a further conflicting provider.
  `setup-end4.sh` runs the `ii` config on whichever provider is enabled, with the
  extra qt6 deps installed separately. **end4-pC** (`plusdrag11/end4-pC`, branch
  `my-end4pc`, upstream `pctrade/end4-pC`) has the same trap: `setup-end4pc.sh`
  installs the same dep set (all `--needed`, a no-op when end4 already installed
  them).
- **Noctalia** — a plain `noctalia` package (CachyOS `cachyos-extra-v3`, v5).
  Ships native C++/Wayland; no longer touches Quickshell or Qt, so it belongs to
  neither provider group. Updates via `dcli update` (cachyos/extra).
- **omarchy** — lists `quickshell-git` in its own `install/omarchy-base.packages`;
  `modules/shell-omarchy.yaml` deliberately omits it so the provider keeps exactly
  one owner. omarchy is not a package at all here: `setup-omarchy.sh` clones the
  repo and **never runs its `install.sh`**, which is a whole-distro installer that
  would overwrite dcli-symlinked configs. See [docs/shells/omarchy.md](docs/shells/omarchy.md).
|- **caelestia** — the `caelestia-shell` package is installed but entirely
  shadowed: its QML by `~/.config/quickshell/caelestia`, its C++ plugin by
  `QML2_IMPORT_PATH`. The `caelestia` CLI used by scripts and keybinds is a
  *separate* package, `caelestia-cli`.

  Two traps in that shadowing, both of which broke the shell on 2026-07-25:

  1. The fork's `plugin/src/Caelestia/CMakeLists.txt` target **must** stay named
     `caelestia-core` (upstream's name since v2.1.0). It determines the built
     filenames, and if the fork's `.so` is named differently from the package's,
     both get registered for `module Caelestia` and Qt aborts with *"Cannot add
     multiple registrations for Caelestia"*. Stock quickshell tolerated this;
     `quickshell-git` does not. A rebase silently reverted the name once already.
  2. Never let stale `.so` files accumulate in `~/.local/lib/qt6/qml/Caelestia/*/`.
     A leftover there beats the fresh one in `../lib/` for the plugin's `$ORIGIN`
     rpath, so the module loads outdated types (*"ButtonRow is not a type"*).
     The fork's `scripts/install.sh` now wipes those dirs before every install.

  `scripts/install.sh --skip-sddm` stages the build and relocates it under
  `~/.local/lib`, so it needs no sudo and never touches pacman-owned files
  (verify with `pacman -Qkk caelestia-shell` → `0 altered files`).

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
  `hyprctl binds -j | jq 'group_by([.modmask,.key,.release])'` — **except under
  omarchy**, where `-j` emits invalid JSON because its binds carry descriptions
  (Hyprland shifts keys against values). Use the plain-text awk recipe in
  [docs/shells/omarchy.md](docs/shells/omarchy.md) there.
- **`hyprctl reload` wipes dynamically applied binds**, so whatever applies
  them must re-run on the `configreloaded` event.
- Types are strict: `explicit_column_widths` takes a **string**, not a table,
  and `hl.animation` needs a curve registered via `hl.curve(...)`.

Verify any config change with `hyprctl configerrors` — it is empty when clean.

# New machine bootstrap

1. Install [dcli](https://gitlab.com/theblackdon) (build from source → `~/.local/bin/dcli`).
2. Clone this repo:
   ```sh
   git clone https://github.com/JASSIM-ALHUMAID/dcli-config.git ~/.config/dcli
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
   `scripts/switch-shell.sh [caelestia|ambxst|dms|noctalia|end4|end4pc|omarchy|xenon]`.
   (omarchy needs no relogin — it resolves its own paths.)

**After `dcli sync` on a fresh machine — one more step for a full CachyOS/Arch
reproduction:**

- **Caelestia SDDM theme + wallpaper sync** — `dcli sync` installs the shell +
  plugin but skips the SDDM theme (it needs `sudo`). From the caelestia clone
  (`~/Projects/shell/real`), run the full installer **without** `--skip-sddm`:
  ```sh
  cd ~/Projects/shell/real
  ./scripts/install.sh
  ```
  This installs the SDDM lockscreen theme to `/usr/share/sddm/themes/caelestia/`,
  configures wallpaper auto-sync via `cli.json`, and sets up the sudoers drop-in
  (`/etc/sudoers.d/caelestia-sddm-sync`). Needs sudo once.

- **Everything else is automatic.** `dcli sync` handles all packages (pacman +
  AUR via paru), all 9 shell checkouts, all dotfiles, uwsm (in `base.yaml`), and
  `xdg-desktop-portal-hyprland` (in `base.yaml`). The session is started by SDDM →
  uwsm (declared in `base.yaml`) → Hyprland. SDDM itself is not declared in dcli —
  on a fresh non-CachyOS machine install it separately; on CachyOS it is a default
  install.
