# Architecture

Ten shells share one Hyprland session. Each owns its UI process and its Hyprland
config; this repo owns the entry point that picks between them, the scripts that
install and switch them, and everything the shells have in common.

## How the pieces connect

```
~/.config/hypr/hyprland.lua          <- the only entry point Hyprland loads
  |- reads shells/registry           <- name|config|icon|blurb, one record per shell
  |- reads shells/active.conf        <- one bare shell name, written by switch-shell.sh
  |- appends <shell dir> to package.path
  |- seeds ~/.config/hypr/scheme/current.lua (colours) if absent
  |- dofile(<the shell's config from the registry>)
  |- dofile(shells/<name>/overrides.lua)     <- if present; tweaks on upstream-owned configs
  `- require(shells.<name>.hyprmod)          <- if present; HyprMod GUI layer, loaded last
```

- **`dotfiles/hypr/shells/registry`** is the single list of shells. The Lua entry
  point and `scripts/lib/shell-common.sh` (used by `switch-shell.sh`,
  `edit-hypr.sh`, `switch-quickshell.sh`, `doctor.sh`, the fuzzel picker) both read
  it, so there is no hardcoded shell list anywhere else. A `~/` config path is
  `$HOME`-relative, anything else is relative to `~/.config/hypr`. If the registry
  is unreadable the entry point falls back to caelestia (and logs to stderr); the
  bash side refuses to start rather than half-parse.
- **`shells/active.conf`** is the switch point. It holds a bare shell name (a legacy
  `source = …/<name>.conf` line is still parsed by both runtimes). It is committed,
  so the last-used shell survives replication.
- **`scripts/switch-shell.sh`** tears down every shell, rewrites `active.conf`,
  reloads Hyprland, then launches the chosen one. The lifecycle is table-driven:
  `MATCH_SPECS` (per shell, pgrep flag + pattern lines; the first line is the
  "already running" guard, all lines are killed on teardown), optional
  `quit_<name>` (graceful IPC quit), and `launch_<name>`. `SHARED_MATCH_SPECS`
  reaps helpers no single shell owns (swaync, awww-daemon, any stray quickshell).
  `kill_matching` (TERM, then KILL after about 1s, always `pkill -A`) lives in
  `scripts/lib/shell-common.sh`. The lock is `$XDG_RUNTIME_DIR/switch-shell.lock`.
  No argument opens the themed fuzzel picker; `--dry-run <shell>` prints the plan
  and touches nothing.
- **`scripts/shell-theme-state.sh`** snapshots the *shared* app theming surface
  (GTK, Qt, cursor, Thunar colours, rofi) per shell and replays it on the way back,
  because most shells overwrite one global copy of it. Snapshots live in
  `state/shell-theme/<name>/`; `DCLI_SKIP_THEME_STATE=1` bypasses it. See
  [shells/README.md](shells/README.md), "The shared surface".
- **`dotfiles/hypr/common/*.lua`** is the shared preference layer standalone shells
  opt into; **`shells/<name>/hyprland/`** keeps only what differs per shell. See
  [HYPRLAND-LUA.md](HYPRLAND-LUA.md) for the `require`/`dofile` and namespacing
  rules.
- **`shells/<name>/overrides.lua`** customises a shell whose Hyprland config is
  owned upstream (editing the upstream file would be lost on update). Only ambxst
  uses it. caelestia's overrides live in its fork (`hypr-vars.lua`, `hypr-user.lua`).
  omarchy needs none: the file the entry point loads for it is already ours, a
  loader that runs omarchy's config and layers the house tweaks on top.
- **omarchy has no `environment.d` file, deliberately.** `$OMARCHY_PATH` must not
  come from the environment: `os.getenv()` in a Lua config runs at parse time, and
  a wrong login-scoped value beats any fallback — a literal `%h` once left the
  desktop with 3 binds instead of 216 and an empty `hyprctl configerrors`.
  `shells/omarchy/hyprland.lua` probes for the checkout and injects the path itself.
  See [shells/omarchy.md](shells/omarchy.md).
- **`dotfiles/environment.d/50-caelestia-qml.conf`** puts
  `QML2_IMPORT_PATH=~/.local/lib/qt6/qml` (and `CAELESTIA_LIB_DIR`) in the *session*
  environment. Qt otherwise searches only `/usr/lib/qt6/qml`; the fork's plugin
  lives under `~/.local`, so without it the shell cannot find its own C++ module.
  uwsm runs the compositor as a systemd user unit, so `environment.d` reaches the
  compositor and every terminal — which Hyprland's own `env` cannot.
- **Colours.** `caelestia scheme set` writes `~/.config/hypr/scheme/current.lua`
  (required as `scheme.current`). matugen writes `dotfiles/hypr/hyprland/colors.lua`
  and `hyprlock/colors.conf` for the rest; end4pc's matugen writes
  `shells/end4pc/colors.lua`. These are committed files, so wallpaper changes
  produce git diffs.
- **Caelestia's keybinds** live in `~/.config/caelestia/keybinds.json`, applied at
  runtime by the shell's `services/KeybindApplier.qml`. They are in no Hyprland
  config and vanish if the shell dies.

## Where everything lives

These are the actual paths on a synced machine.

| Path | What it is | Created by |
|---|---|---|
| `~/.config/hypr` -> `dcli/dotfiles/hypr` | Hyprland entry point, `common/`, per-shell configs, `shells/registry` | `link-dotfiles.sh` |
| `~/.config/environment.d` -> `dcli/dotfiles/environment.d` | session env (`QML2_IMPORT_PATH`, `CAELESTIA_LIB_DIR`) | `link-dotfiles.sh` |
| `~/.config/{foot,btop,fuzzel,cava,nvim,yazi,lazygit,git}` -> `dcli/dotfiles/*` | shared app config; several shells write generated palettes into foot/btop/fuzzel, so they cannot live in a shell's own checkout | `link-dotfiles.sh` |
| `~/Projects/shell/real` | **caelestia fork** — origin `JASSIM-ALHUMAID/my-caelestia`, branch `my-caelestia`, upstream `caelestia-dots/shell`. Source of truth for the QML/C++ | `setup-caelestia.sh` |
| `~/.config/quickshell/caelestia` | the installed caelestia QML (written by the fork's scripts, refreshed by `sync-live.sh`) | fork |
| `~/.config/caelestia` -> `~/Projects/shell/real/caelestia-configs` | caelestia's runtime config (`shell.json`, `keybinds.json`, `hypr-vars.lua`, `hypr-user.lua`) — version-controlled *inside the fork*, not here | `setup-caelestia.sh` |
| `~/.local/lib/qt6/qml`, `~/.local/lib/caelestia` | the C++ plugin built from the fork | fork `scripts/install.sh --skip-sddm` |
| `~/.local/share/caelestia` | upstream `caelestia-dots` dots clone; provides `hypr/hyprland.lua` (the Lua config caelestia loads). `~/.config/uwsm` is a symlink into it, **not created by this repo**. `~/.config/fish` is dcli's own (`dotfiles/fish`) and `~/.config/fastfetch` + `starship.toml` follow the active shell (`apply-terminal-theme.sh`) | `setup-caelestia.sh` |
| `~/.local/src/ambxst`, `~/.local/share/ambxst` (link) | **ambxst fork** — origin `JASSIM-ALHUMAID/my-Ambxst`, branch `my-ambxst`, upstream `Axenide/Ambxst`; ships its own `hyprland.lua` | `setup-ambxst.sh` |
| `~/.config/ambxst` -> `dcli/dotfiles/ambxst` | ambxst user config | `link-dotfiles.sh` |
| `~/.local/share/dots-hyprland` | **end4 fork** — origin `JASSIM-ALHUMAID/my-end4`, branch `my-ii`, upstream `end-4/dots-hyprland` | `setup-end4.sh` |
| `~/.config/quickshell/ii` -> `dots-hyprland/dots/.config/quickshell/ii` | end4's quickshell config | `setup-end4.sh` |
| `~/.local/share/end4-pC` | **end4pc fork** — origin `JASSIM-ALHUMAID/my-end4-pC`, branch `my-end4pc`, upstream `pctrade/end4-pC`; the repo root *is* the quickshell config | `setup-end4pc.sh` |
| `~/.config/quickshell/end4-pC` -> `~/.local/share/end4-pC` | end4pc's quickshell config | `setup-end4pc.sh` |
| `~/.config/matugen-end4pc` -> `dcli/dotfiles/matugen-end4pc` | end4pc's own matugen config | `link-dotfiles.sh` |
| `~/.config/matugen-end4` -> `dots-hyprland/dots/.config/matugen` | end4's own matugen config (passed with `-c`) | `setup-end4.sh` |
| `~/.config/matugen` -> `ryoku-shell/ryoku/shell/matugen` | ryoku's templates — its daemon hard-codes this path | `setup-ryoku.sh` |
| `/usr/bin/noctalia` (pkg `noctalia`, `extra`) | Noctalia v5 binary — native C++/Wayland, no Quickshell | pacman |
| `~/.config/noctalia` -> `dcli/dotfiles/noctalia` | Noctalia config (`config.toml`, hot-reloaded) | `link-dotfiles.sh` |
| `/usr/bin/dms` (pkg `dux-shell`) | Dux Shell (ex-DankMaterialShell); the CLI is still `dms` | pacman |
| `~/.config/DankMaterialShell` -> `dcli/dotfiles/DankMaterialShell` | DMS/Dux user config (the path did not change) | `link-dotfiles.sh` |
| `~/.local/share/omarchy` | omarchy checkout (`basecamp/omarchy`, branch `quattro`) — this is `$OMARCHY_PATH`; no personal fork | `setup-omarchy.sh` |
| `~/.config/omarchy` -> `dcli/dotfiles/omarchy` | omarchy user config (`shell.json`, hooks, extensions) | `link-dotfiles.sh` |
| `~/.local/state/omarchy` | omarchy generated state — machine-local, **not** in this repo | `omarchy-theme-set` |
| `~/.local/share/xenon-shell` | xenon checkout (`MannuVilasara/xenon-shell`, branch `main`); no personal fork | `setup-xenon.sh` |
| `~/.config/quickshell/xenon` -> `~/.local/share/xenon-shell` | xenon's quickshell config | `setup-xenon.sh` |
| `~/.config/xenon` -> `dcli/dotfiles/xenon` | xenon user config (`config.json`); generated data stays in `~/.cache/xenon` | `link-dotfiles.sh` |
| `~/.local/share/ryoku-shell` | ryoku checkout (`Ryoku-dev/ryoku`, branch `main`); no personal fork. Built daemon/QML modules land in `~/.local` | `setup-ryoku.sh` |
| `~/.config/ryoku`, `~/.local/share/ryoku` | ryoku runtime config (daemon-written) and i18n catalog — machine-local, **not** in this repo | `ryoku-shell` / `setup-ryoku.sh` |
| `/usr/bin/uwsm` (pkg `uwsm`, `base.yaml`) | starts the Hyprland session after SDDM login | `dcli sync` |
| SDDM (`/etc/sddm.conf`, pkg `sddm`) | display manager. Not declared in any module — a CachyOS default install; install it separately elsewhere | manual |

Rule of thumb: `~/.config/<x>` is a symlink into `dcli/dotfiles/<x>` for anything
this repo owns, so editing the live config edits the repo. The deliberate exceptions
are `~/.config/caelestia` and `~/.config/quickshell/{caelestia,ii,end4-pC,xenon}`
(symlinks into the fork/upstream checkouts, which are the source of truth) and
`wezterm` (its own repo, [JASSIM-ALHUMAID/wezterm](https://github.com/JASSIM-ALHUMAID/wezterm);
dcli keeps a snapshot copy). `~/.config/ryoku` is the daemon's own state — it has
no dcli-owned counterpart by design.

## Modules, hooks and the packages rule

- `dotfiles:` keys in flat YAML modules are documentation only;
  `scripts/link-dotfiles.sh` does the real linking from its `TARGETS` array, and
  `tests/smoke.sh` fails if a module names a source that is not in `TARGETS`.
- **Packages belong in the module's `packages:`, never only in a setup hook.**
  Hooks are `hook_behavior: once` — a hook-installed package is never re-checked,
  so it silently disappears from the declared state. Module packages are checked on
  every `dcli sync`, and `scripts/doctor.sh` fails if the dry run has anything to
  install. (end4 and end4pc deliberately declare the same dependency list in both
  modules: dcli has no module-to-module dependency, and it dedups the overlap.)
- Packages are installed in one global phase before any hook runs, so a hook can
  rely on any enabled module's packages already being present.
- `scripts/lib/hook-common.sh` is the shared hook library (sourced, never
  executed): the real-user block and `as_user`, `clone_checkout` (with `--opt-in`
  for forks a sync must not clone behind your back), `require_checkout`,
  `update_submodules`, `fast_forward_pull`, and `ensure_symlink <src> <dst>
  <policy>` where policy is `refuse` (error, touch nothing), `backup` (move aside to
  `<dst>.bak-<timestamp>`) or `force` (`ln -sfn`).
- `scripts/lib/shell-common.sh` is the registry/`active.conf`/`kill_matching` library
  for the runtime scripts.

## Packaging

Exactly one quickshell provider may be installed (`Conflicts=quickshell`). It is
owned by `modules/shells-quickshell{,-git}.yaml` and swapped with
`scripts/switch-quickshell.sh`, never `dcli module enable` alone. Provider table,
the stock-vs-git experiment and the incident history are in
[PACKAGE-CONFLICTS.md](PACKAGE-CONFLICTS.md).

How each shell is supplied:

- **caelestia** — a fork built from source into `~/.local`; the `caelestia-shell`
  package is not installed (removed 2026-09-11). Its runtime dependencies are
  declared in `modules/caelestia.yaml`. The `caelestia` CLI is the separate package
  `caelestia-cli`.
- **ambxst** — fork with its own installer; `packages: []`.
- **dms** — the packaged `dux-shell` (it replaced `dms-shell` on 2026-10-30).
- **noctalia** — the packaged `noctalia` 5.x from `extra`; no Quickshell, no Qt.
- **end4 / end4pc** — forks; their extra deps are module packages. The
  `illogical-impulse-quickshell-git` package is never installed (a fourth
  conflicting provider).
- **omarchy** — a checkout; `setup-omarchy.sh` never runs omarchy's `install.sh`
  (a whole-distro installer). `quickshell-git` is in omarchy's own package list and
  deliberately not in its module, so the provider keeps one owner.
- **xenon** — a checkout, no installer.
- **glyph** — a rice checkout; `setup-glyph.sh` links only its two Quickshell
  configs and fonts, never its `install.sh` (which takes over `~/.config/hypr`).
- **ryoku** — a distro checkout; `setup-ryoku.sh` reproduces the user-level
  half of the distro's packages from their own payload recipes (daemons, Hub and
  store backends, QML modules, user-level helpers) into `~/.local`, with a private
  bin dir only the ryoku session puts on `PATH`; never the distro installer,
  `ryoku materialize` or the `ryoku` CLI.

## Adding a shell — checklist

Adding a record to `dotfiles/hypr/shells/registry` is necessary but not
sufficient. Work through all of these:

1. **Registry record + icon.** Add `name|config|icon|blurb` to
   `dotfiles/hypr/shells/registry` (picker order) and the icon under
   `dotfiles/fuzzel/shell-icons/`. Make `lines=` in
   `dotfiles/fuzzel/shell-picker.ini` at least the new shell count — fuzzel scrolls
   the overflow with no indicator, so a short value silently hides shells.
2. **Module YAML** `modules/shell-<name>.yaml`. Runtime dependencies go in
   `packages:`, **not** in the setup hook. Never declare a quickshell provider
   there.
3. **Setup hook** `scripts/setup-<name>.sh`, sourcing `lib/hook-common.sh`
   (`clone_checkout`, `ensure_symlink`, ...). Set the module's `post_install_hook`
   and `hook_behavior: once`.
4. **`switch-shell.sh`:** a `MATCH_SPECS[<name>]` entry (first line is the running
   guard; anchor patterns with `-x` or a distinctive `-f` phrase), a
   `launch_<name>()`, and optionally `quit_<name>()` if the shell has a real
   graceful-quit IPC. `tests/smoke.sh` fails if a registry name lacks a spec or a
   launch function.
5. **`link-dotfiles.sh` `TARGETS`** if the shell has a dcli-owned config directory
   under `dotfiles/`.
6. **Hyprland config.** A standalone shell gets `dotfiles/hypr/shells/<name>/hyprland.lua`
   that opts into `require("common.*")` and requires its own files with qualified
   names (`require("shells.<name>.hyprland.keybinds")`); a shell whose config is
   owned upstream points its registry `config` at the upstream file and gets a
   `shells/<name>/overrides.lua` instead. Keep the common bind that returns to the
   switcher (`SUPER + SHIFT + O`). Add an entry to `scripts/edit-hypr.sh` only via the
   registry (it reads it).
7. **`update-shells.sh`:** a `CHECKOUT_RECORDS` entry (`name|dir|updater`; `-` means
   report only) and an `update-<name>.sh` if the shell is a checkout that can be
   fast-forwarded. Add the checkout to `CHECKOUTS` (and any `~/.config/quickshell/*`
   link to `SHELL_LINKS`) in `doctor.sh`.
8. **Host:** add the module to `enabled_modules` in `hosts/all-shells.yaml`.
9. **Audit the shell's writes** outside its own namespace (see
   [shells/README.md](shells/README.md), "Rules when adding a shell") and extend
   `shell-theme-state.sh` if it touches the shared surface.
10. **Docs:** `docs/shells/<name>.md` plus rows in `docs/shells/README.md`, the README
    shell table, and `docs/shells/atlas.html`.
11. **GRUB.** Add the shell's wallpaper record to `WALLPAPER_SOURCES` in
    `scripts/lib/wallpaper.sh` (smoke fails without one — the boot theme would be a
    gradient) and re-run `scripts/install-grub-theme.sh` so the watcher picks up the
    new state file. Optionally add a style-table entry in `render-grub-theme.sh` if
    the shell should not get the default `material` layout. See [GRUB.md](GRUB.md).
12. **SDDM.** Add a `LOOK_TABLE` row (and a `PALETTE_SOURCES` row if the shell writes a
    colour file) in `scripts/render-sddm-theme.sh`; a bespoke theme goes in
    `sddm/themes/<name>/`. Re-run `scripts/install-sddm-theme.sh` to install the new
    theme directory. See [SDDM.md](SDDM.md).
13. **Terminal.** Starship prompt and fastfetch follow the shell
    (`scripts/apply-terminal-theme.sh`, called by `switch-shell.sh`; it retargets
    `~/.config/starship.toml` and `~/.config/fastfetch`). Add the shell's upstream
    paths to `UPSTREAM_STARSHIP` / `UPSTREAM_FASTFETCH` in `scripts/lib/terminal-theme.sh`
    if it ships its own (read in place from the checkout; reachable with `--upstream`) — and
    always commit our own
    commit `dotfiles/terminal/<name>/starship.toml` and `fastfetch/{config.jsonc,logo.txt}`
    (smoke fails without a source for each). A config that references files its checkout
    keeps elsewhere (ryoku's emblem) lists them in `UPSTREAM_FASTFETCH_EXTRAS`; the applier
    then links a composed directory under `state/terminal/fastfetch/<name>/`. Every shell has its own config in `dotfiles/terminal/<name>/`; the upstream copy stays one
    flag away (`scripts/apply-terminal-theme.sh --upstream <name>`, until the next switch), and
    deleting a shell's file there makes upstream the default again. Never run an upstream installer that
    would symlink these two paths itself (glyph's did).
14. **Verify:** `bash tests/smoke.sh`,
    `DCLI_HYPRMOD_SHELL=<name> Hyprland --verify-config -c ~/.config/hypr/hyprland.lua`,
    `scripts/switch-shell.sh --dry-run <name>`, then `scripts/doctor.sh`.
