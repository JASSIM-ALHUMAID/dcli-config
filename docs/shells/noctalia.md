# noctalia

**v5 is a ground-up rewrite with no Quickshell and no Qt** — native C++23/Meson on
Wayland + OpenGL ES. It is the only shell here that is not a Quickshell config, and
therefore the only one immune to the provider conflict.

| | |
|---|---|
| Module | `modules/shell-noctalia.yaml` |
| Package | `noctalia` (AUR, source build via paru) |
| Version | `5.0.0_beta.4-1` — **still beta** |
| Launch | `noctalia` |
| Config | `~/.config/noctalia/config.toml` (TOML, hot-reloaded via inotify) |
| Upstream | [noctalia-dev/noctalia](https://github.com/noctalia-dev/noctalia) |
| Setup hook | `scripts/setup-noctalia.sh` — v4 teardown only |

## The v4 → v5 break

Upstream moved `noctalia-dev/noctalia-shell` → `noctalia-dev/noctalia` and renamed
the package `noctalia-shell` → `noctalia`. Nothing about v4 carried over.

**v4 needed `noctalia-qs`, the worst of the Quickshell forks** — it conflicts with
*both* `quickshell` and `quickshell-git`, so it could never coexist with either
provider module. The old workaround downloaded the package and extracted it
*unpackaged* to `~/.local/opt/noctalia-qs` behind a `~/.local/bin/noctalia`
wrapper. **All of that is gone.** v5 is an ordinary package.

`setup-noctalia.sh` is now a one-shot teardown that removes the three v4
artifacts. Removing the wrapper matters: `~/.local/bin` normally precedes
`/usr/bin` on `PATH`, so it would shadow the real v5 binary and keep launching the
old fork. Once every machine has run it, drop the hook and delete the script.

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

**Upstream's `example.toml` on `main` is ahead of the released beta.** Keys copied
from it may not exist in the installed build — `validate` caught three:

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

## Beta caveats

- Config keys and IPC command names can shift between betas. Re-run
  `noctalia config validate` and re-check `noctalia msg --help` after each update.
- Upstream flags v5 as beta in its own README; only the latest version is
  maintained, and bug reports must reproduce on it.
- The catalog already advertises `plugin_api = 9` while beta.4's notes say API 8 —
  expect that kind of drift.

## Health check

```bash
command -v noctalia            # must be /usr/bin/noctalia, NOT ~/.local/bin
noctalia --version
noctalia config validate ~/.config/noctalia/config.toml
test ! -e ~/.local/opt/noctalia-qs && echo "v4 fork removed"
```
