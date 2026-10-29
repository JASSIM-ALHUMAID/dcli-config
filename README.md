# dcli config — all-shells

Declarative system config for an Arch/CachyOS + Hyprland machine, managed with
[dcli](https://gitlab.com/theblackdon) v0.2.2: packages, services, default apps,
dotfiles and bootstrap hooks. One Hyprland session, eight switchable desktop
shells — my **custom Caelestia fork** as the daily driver, plus ambxst, Dux Shell
(DMS), Noctalia, end-4, end4-pC, omarchy and xenon.

`dcli sync` on a fresh machine reproduces the full session: SDDM login, uwsm,
Hyprland, the shell of your choice, with every shell's checkout, dependencies and
dotfiles in place. dcli's own manual is not vendored here — see dcli's project
([gitlab.com/theblackdon](https://gitlab.com/theblackdon)) and `dcli --help` /
`dcli <command> --help` for the v0.2.2 command surface.

## Bootstrap

1. Install dcli (build from source into `~/.local/bin/dcli`).
2. Clone this repo and sync:
   ```sh
   git clone https://github.com/JASSIM-ALHUMAID/dcli-config.git ~/.config/dcli
   dcli sync
   ```
   `sync` installs packages (pacman + AUR via paru), enables services, and runs the
   module hooks — including `scripts/link-dotfiles.sh`, which symlinks
   `~/.config/<dir>` to `dotfiles/<dir>`, and the per-shell `setup-*.sh` hooks that
   clone the forks. The caelestia, ambxst, end4 and end4pc fork clones are opt-in: a
   non-interactive sync skips them and prints the `dcli module run-hook <module>`
   command to run later.
3. Log out and back in once so the session environment (`QML2_IMPORT_PATH`,
   `CAELESTIA_LIB_DIR`) applies, then pick a shell with `scripts/switch-shell.sh`.
4. Two steps need `sudo` once and are deliberately not automatic:
   - **Caelestia SDDM theme + wallpaper sync:**
     `cd ~/Projects/shell/real && ./scripts/install.sh` (the fork's installer
     *without* `--skip-sddm`; it also writes `/etc/sudoers.d/caelestia-sddm-sync`).
   - **omarchy lock screen** (the shell refuses to lock without its PAM service):
     `sudo env PATH=~/.local/share/omarchy/bin:$PATH ~/.local/share/omarchy/bin/omarchy-apply-lock`
     (see [docs/shells/omarchy.md](docs/shells/omarchy.md)).

SDDM itself is not declared in any module (a CachyOS default); install it separately
on other distributions.

## Daily commands

| Command | What it does |
|---|---|
| `scripts/switch-shell.sh [shell]` | Switch the active shell (no argument: fuzzel picker). `--dry-run <shell>` prints the plan and changes nothing |
| `scripts/edit-hypr.sh [shell]` | Edit a shell's Hyprland settings in HyprMod, isolated per shell |
| `scripts/update-shells.sh [--status] [name\|all]` | Fast-forward the fork/upstream checkouts; `--status` only reports branch, dirty count, ahead/behind |
| `scripts/doctor.sh [--versions]` | Read-only health check (packages, provider, Hyprland errors, links, checkouts, services); `--versions` prints the stack table |
| `scripts/switch-quickshell.sh [stock\|git] [--yes]` | Report or swap the quickshell provider |
| `dcli sync` / `dcli update` | Apply modules / update the system (runs `scripts/post-update.sh` afterwards) |
| `bash tests/smoke.sh` | Parse, lint, registry, lifecycle and dotfile-drift checks |

Verify any shell's Hyprland config without switching to it:
`DCLI_HYPRMOD_SHELL=<shell> Hyprland --verify-config -c ~/.config/hypr/hyprland.lua`.

## The shells

| Shell | Launch | Hyprland config | Its own config | Source |
|---|---|---|---|---|
| **caelestia** | `caelestia shell -d` (`qs -c caelestia`) | `~/.local/share/caelestia/hypr/hyprland.lua`, overridden by `~/.config/caelestia/hypr-vars.lua` and `hypr-user.lua` | `~/.config/caelestia` | fork `JASSIM-ALHUMAID/my-caelestia` (`my-caelestia`), upstream `caelestia-dots/shell` |
| **ambxst** | `ambxst` | `~/.local/share/ambxst/hyprland.lua` + `shells/ambxst-overrides.lua` | `~/.config/ambxst` | fork `JASSIM-ALHUMAID/my-Ambxst` (`my-ambxst`), upstream `Axenide/Ambxst` |
| **dms** | `dms run` | `shells/dms/hyprland.lua` (standalone) | `~/.config/DankMaterialShell` | package `dux-shell` |
| **noctalia** | `noctalia` | `shells/noctalia/hyprland.lua` (standalone) | `~/.config/noctalia` | package `noctalia` (`extra`) |
| **end4** | `qs -c ii` | `shells/end4/hyprland.lua` (end4's tree + `custom/`) | `~/.config/quickshell/ii` | fork `JASSIM-ALHUMAID/my-end4` (`my-ii`), upstream `end-4/dots-hyprland` |
| **end4pc** | `qs -c end4-pC` | `shells/end4pc/hyprland.lua` (standalone) | `~/.config/quickshell/end4-pC` | fork `JASSIM-ALHUMAID/my-end4-pC` (`my-end4pc`), upstream `pctrade/end4-pC` |
| **omarchy** | `quickshell -n -p $OMARCHY_PATH/shell` | `shells/omarchy/hyprland.lua` — a loader that runs omarchy's own Lua config, then the house layer | `~/.config/omarchy` | `basecamp/omarchy` branch `quattro`, tracked directly |
| **xenon** | `qs -c xenon` | `shells/xenon/hyprland.lua` (standalone) | `~/.config/xenon` | `MannuVilasara/xenon-shell` branch `main`, tracked directly |

caelestia, ambxst and omarchy ship complete Hyprland configs, so we load theirs and
layer local tweaks on top; the rest are standalone configs here that share the
`dotfiles/hypr/common/` preference layer. The wezterm config has its own history at
[JASSIM-ALHUMAID/wezterm](https://github.com/JASSIM-ALHUMAID/wezterm).

## Things worth knowing

1. `dotfiles:` keys in flat YAML modules are **documentation only** —
   `scripts/link-dotfiles.sh` does the real linking, from its own `TARGETS` array.
2. Only one quickshell provider can be installed. It is owned by
   `modules/shells-quickshell{,-git}.yaml`; swap it with
   `scripts/switch-quickshell.sh`, never `dcli module enable` alone.
3. Runtime dependencies go in a module's `packages:`, never only in a setup hook.
   Hooks run once and are never re-checked; module packages are checked on every sync.
4. Theming regenerates files that are committed here, so unexpected git changes after
   a wallpaper change are normal.
5. Packages move under the docs (dux-shell replaced dms-shell overnight). Before
   trusting any package claim, run `scripts/doctor.sh` or `dcli sync --dry-run`.
6. Hyprland's config is Lua. `hyprctl keyword` and `hyprctl dispatch` do not work, and
   standalone shells must use fully-qualified `require` names — see
   [docs/HYPRLAND-LUA.md](docs/HYPRLAND-LUA.md).
7. `~/.config/fish` and `~/.config/fastfetch` are symlinks into the caelestia-dots
   clone at `~/.local/share/caelestia`; this repo does not create them.

## Docs

| Doc | Read it when |
|---|---|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | How the registry, entry point, switcher, hooks and checkouts fit together; where every path lives; the **new-shell checklist** |
| [docs/HYPRLAND-LUA.md](docs/HYPRLAND-LUA.md) | Writing or debugging Hyprland Lua config; the `common/` layer; verify-config |
| [docs/NOTES.md](docs/NOTES.md) | dcli behaviours that surprise you, whether `dcli update` is safe, debugging a shell that will not start |
| [docs/PACKAGE-CONFLICTS.md](docs/PACKAGE-CONFLICTS.md) | Anything involving `quickshell` vs `quickshell-git`, and the dated incident log |
| [docs/shells/](docs/shells/README.md) | One page per shell (layout, traps, install/update, health check), plus [atlas.html](docs/shells/atlas.html), a one-page visual overview |
