# ambxst

Custom fork of [Axenide/Ambxst](https://github.com/Axenide/Ambxst). It uses
Quickshell (launched as `qs -p .../ambxst/shell.qml`) but installs itself through
its own installer rather than a package.

| | |
|---|---|
| Module | `modules/ambxst.yaml` |
| Packages | none declared — its own installer handles deps |
| Launch | `ambxst` (`/usr/local/bin/ambxst`) |
| Setup hook | `scripts/setup-ambxst.sh` |

## Layout

| Path | What |
|---|---|
| `~/.local/src/ambxst` | Fork checkout, **source of truth**. origin `plusdrag11/Ambxst`, upstream `Axenide/Ambxst`, branch `my-ambxst` |
| `~/.local/share/ambxst` → `~/.local/src/ambxst` | Where `hyprland.lua` is loaded from |
| `/usr/local/bin/ambxst` | Launcher written by the fork's `install.sh` (it sudos where needed) |
| `~/.config/ambxst` → `dotfiles/ambxst` | **dcli-managed** settings: `binds.json`, `config/`, `hypr-user.conf`, `presets/` |
| `dotfiles/hypr/shells/ambxst-overrides.lua` | Local overrides, applied *after* the fork's own Lua |

Note the launcher is the one shell binary in `/usr/local/bin` rather than `/usr/bin`
or `~/.local/bin` — written by the fork's installer, not by pacman or dcli.

## It supplies its own Hyprland config

Unlike dms/noctalia/end4/end4pc, ambxst's `hyprland.lua` comes from its checkout,
not from `dotfiles/hypr/shells/`. `~/.config/hypr/hyprland.lua` `dofile()`s
`~/.local/share/ambxst/hyprland.lua`, then — uniquely — loads
`dotfiles/hypr/shells/ambxst-overrides.lua` on top.

The overrides file exists because the fork's config sets things this machine wants
different: monitor scale, `us,ara` keyboard layout with `grp:win_space_toggle` and
`ctrl:nocaps`, pointer sensitivity/accel, scrolling column widths, and gesture
behaviour. **Put local tweaks there, not in the checkout** — the checkout is the
fork and edits there become fork commits.

## Trap: it rewrites the monitor on startup

ambxst changes the monitor configuration when it launches. `switch-shell.sh`
compensates by sleeping 1s after launch and re-applying scale 1 via `hyprctl eval`,
and `ambxst-overrides.lua` puts it back on the next reload. If your display scale
looks wrong right after switching to ambxst, that is this.

## Trap: the stale PID file

ambxst's CLI trusts a cached PID in `/tmp/ambxst.pid`. **A stale entry there makes
`ambxst quit` kill whatever unrelated process now owns that recycled PID.**
`switch-shell.sh` therefore only calls `ambxst quit` after confirming the shell is
actually running:

```bash
pgrep -f "ambxst/shell.qml" >/dev/null 2>&1 && ambxst quit
```

Never call `ambxst quit` unguarded from a script.

## Trap: matching its processes

The launcher `exec`s into `qs -p .../ambxst/shell.qml`, so the main process must be
matched by command line (`pkill -f`), not by name — `pkill -x ambxst` only catches
the wrapper before it execs. Helper processes appear as `bash`/`tail`, so they too
need `-f` with a distinctive phrase. `switch-shell.sh` matches
`ambxst/shell.qml`, `ambxst/cli.sh`, `ambxst_ipc`, `loginlock.sh` and
`sleep_monitor.sh` for exactly this reason.

## Its own import path

The launcher exports `QML2_IMPORT_PATH=~/.local/lib/qml` (note: **not**
`~/.local/lib/qt6/qml`, which is caelestia's). The two do not collide.

## Deps

`setup-ambxst.sh` clones the fork (branch `my-ambxst`, pinned) and runs **the
fork's** `install.sh`, which handles its own dependencies. `modules/ambxst.yaml`
declares `packages: []` — so dcli does not track what ambxst needs, and a
`dcli sync --prune` will not know about them. The setup hook is
`hook_behavior: once`, so it will not re-run on its own.

### Trap: its installer wants stock `quickshell`

The arch package list in `install.sh` includes `quickshell`, installed with
`$AUR_HELPER -S --needed --noconfirm`. On this machine that would conflict with
`quickshell-git`.

It is only safe because the installer's `filter_packages()` consults a
`BINARY_CHECK` map — `["quickshell"]="qs"` — and skips the package when the `qs`
binary is already on PATH, which `quickshell-git` owns (`pacman -Qo /usr/bin/qs`).

**Under dcli this is safe by construction**, including on a fresh machine: sync
installs every declared package in one aggregated phase and only then runs
post-install hooks (see [../NOTES.md](../NOTES.md)), and `shells-quickshell-git`
declares `quickshell-git`. So the provider is always present by the time this hook
runs. No extra steps.

The guard is still worth knowing about, because it rests on a binary-name
coincidence rather than on real dependency metadata. **It only matters on the
manual path** — running `setup-ambxst.sh` or the fork's `install.sh` directly on a
machine with no provider installed.

There is no "upstream installer first" step; the fork's installer is the only one
to run.

The fuzzel picker blurb calls it "Axenide · Astal", which is historical — it runs
on Quickshell like the others.

## Status (2026-07-25)

- **Up to date with `upstream/main`** (26 ahead with your customizations, 0 behind)
  — the only fork here that is current.
- Loads cleanly under `quickshell-git 0.3.0.r3` → `Configuration Loaded`.

The `axctl-1000.sock` connect error seen in a bare `ambxst` test launch is just its
daemon not being up yet; it is not a fault.

## Health check

```bash
git -C ~/.local/src/ambxst status --short
readlink -f ~/.local/share/ambxst        # -> ~/.local/src/ambxst
readlink -f ~/.config/ambxst            # -> dcli/dotfiles/ambxst
pgrep -af "ambxst/shell.qml"
```
