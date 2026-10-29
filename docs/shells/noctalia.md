# noctalia

**v5 is a ground-up rewrite with no Quickshell and no Qt** — native C++23/Meson on
Wayland + OpenGL ES. It is the only shell here that is not a Quickshell config, and
therefore the only one immune to the provider conflict.

| | |
|---|---|
| Module | `modules/shell-noctalia.yaml` |
| Package | `noctalia` (`extra`, a plain binary package; not an AUR source build) |
| Version | `5.4.0` — stable |
| Launch | `noctalia` |
| Config | `~/.config/noctalia/config.toml` (TOML, hot-reloaded via inotify) |
| Upstream | [noctalia-dev/noctalia](https://github.com/noctalia-dev/noctalia) |
| Setup hook | none (the one-shot v4 teardown hook was deleted) |

## The v4 → v5 break

Upstream moved `noctalia-dev/noctalia-shell` → `noctalia-dev/noctalia` and renamed
the package `noctalia-shell` → `noctalia`. Nothing about v4 carried over.

**v4 needed `noctalia-qs`, the worst of the Quickshell forks** — it conflicts with
*both* `quickshell` and `quickshell-git`, so it could never coexist with either
provider module. The old workaround downloaded the package and extracted it
*unpackaged* to `~/.local/opt/noctalia-qs` behind a `~/.local/bin/noctalia`
wrapper. **All of that is gone.** v5 is an ordinary package.

A one-shot teardown hook (`setup-noctalia.sh`) removed the v4 artifacts on the only
machine that ever had them, and has been deleted along with its module hook. The
wrapper mattered: `~/.local/bin` normally precedes `/usr/bin` on `PATH`, so a
leftover `~/.local/bin/noctalia` would shadow the real v5 binary and keep launching
the old fork — the health check below still verifies it.

## Config: hand-ported, not migrated

v5 does **not** read v4's `settings.json` — `src/config/config_migrations.cpp` only
migrates between TOML config versions. `dotfiles/noctalia/config.toml` was ported by
hand. The v4 files are in git history:

```bash
git show c2789e8:dotfiles/noctalia/settings.json
```

`~/.config/noctalia` is a symlink to `dotfiles/noctalia/`, so `config.toml` is
dcli-managed and edits land straight in the repo.

### Always validate after editing

```bash
noctalia config validate ~/.config/noctalia/config.toml
noctalia config export full            # the effective config, post-merge
```

**Upstream's `example.toml` on `main` can be ahead of the released build.** Keys
copied from it may not exist in the installed version — `validate` caught three
back on 5.0.0 beta 4 (re-check against 5.4.0 when touching them):

| `example.toml` (main) | 5.0.0_beta.4 |
|---|---|
| `bar.main.margin_h` / `margin_v` | `margin_edge` / `margin_ends` / `margin_opposite_edge` |
| `wallpaper.automation.interval_minutes` | `interval_seconds` |

Unknown keys are only a `WARN` and are silently ignored, so a typo'd setting
quietly does nothing. `validate` is the only way to catch it.

## IPC: `noctalia msg`, not `ipc call`

v4 used `noctalia ipc call <object> <method>`. v5 uses flat kebab-case commands.
`dotfiles/hypr/shells/noctalia/hyprland.lua` was rewritten accordingly:

| v4 | v5 |
|---|---|
| `launcher toggle` | `panel-toggle launcher` |
| `controlCenter toggle` | `panel-toggle control-center` |
| `notifications toggleHistory` | `panel-toggle control-center notifications` |
| `settings toggle` | `settings-toggle` |
| `lockScreen toggle` | `session lock` |
| `wallpaper random` | `wallpaper-random` |
| `volume increase` / `decrease` | `volume-up` / `volume-down` |
| `volume muteOutput` / `muteInput` | `volume-mute` / `mic-mute` |
| `brightness increase` / `decrease` | `brightness-up` / `brightness-down` |

Discover everything with `noctalia msg --help`. Panel ids come from the error on a
bad one:

```
$ noctalia msg panel-toggle __bogus__
error: unknown panel "__bogus__" (available: clipboard, control-center,
       launcher, polkit, session, setup-wizard, test, tray-drawer, wallpaper)
```

Note there is **no separate notification-history panel** — it is the
control-center panel opened on its `notifications` context.

### There is no `kill` subcommand

The CLI accepts only `theme`, `msg`, `config`, `dmenu`, `plugins` and
`firefox-theme`. **An unrecognised bare argument falls through and *starts the
shell*** — so `noctalia kill` launches it rather than stopping it. `switch-shell.sh`
therefore kills it by name (`pkill -x noctalia`) with no graceful-quit IPC.

Also note **contexts are not validated**: `panel-toggle control-center __bogus__`
returns `ok` and opens the default section. Only panel *ids* are checked.

## Plugins

v5 plugins are **Luau**, not QML, so the vendored v4 `video-wallpaper` plugin was
deleted. The old `noctalia-plugins` repo split into `legacy-v4-plugins`,
`official-plugins` and `community-plugins`.

The official replacement for video wallpapers is **`noctalia/mpvpaper`
("Video Wallpaper")** — install it from the plugin store rather than vendoring it.

```bash
noctalia msg plugins list
```

## Update caveats

- v5 is stable now (5.4.0 in `extra`, updated by `dcli update`), but config keys and
  IPC command names still move between releases. Re-run `noctalia config validate`
  and re-check `noctalia msg --help` after each update.
- Only the latest version is maintained upstream; bug reports must reproduce on it.
- The plugin catalog's `plugin_api` can run ahead of the installed build — expect
  that kind of drift.

## Health check

```bash
command -v noctalia            # must be /usr/bin/noctalia, NOT ~/.local/bin
noctalia --version
noctalia config validate ~/.config/noctalia/config.toml
test ! -e ~/.local/opt/noctalia-qs && echo "v4 fork removed"
scripts/doctor.sh
```
