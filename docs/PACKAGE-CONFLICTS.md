# Quickshell Provider Conflicts

**Date:** 2026-07-25
**System:** CachyOS + Hyprland + dcli
**Issue:** `paru -Syu` / `yay -Syu` fails with `quickshell-git and quickshell are in conflict`

---

## Problem Statement

A system update refuses to proceed:

```
:: quickshell-git and quickshell are in conflict. Remove quickshell? [y/N]
```

---

## Root Cause

**AUR `caelestia-shell` 2.2.0 changed its dependency from `quickshell` to
`quickshell-git`.** This host had `caelestia-shell` 2.1.0 installed, which used stock
`quickshell`. On upgrade the new version pulls `quickshell-git`, which declares
`Conflicts=quickshell`, so the transaction deadlocks against the installed provider.

This is ordinary, correct dependency resolution — not a bug.

> An earlier version of this document blamed "CachyOS repository metadata bugs" (a false
> `Required By: dms-shell` on `quickshell-git` / `noctalia-qs`) and claimed an `IgnorePkg`
> fix had been applied. Both claims were wrong:
>
> - `dms-shell` depends on plain `quickshell`; `quickshell-git` and `noctalia-qs` legitimately
>   satisfy that via `Provides=quickshell`. The "Required By" line is normal provider
>   resolution.
> - The `IgnorePkg` line was never actually added to `/etc/pacman.conf`, and it would not
>   have helped: `IgnorePkg` only skips *upgrades of already-installed packages*, and
>   neither `quickshell-git` nor `noctalia-qs` was installed. It has no effect on provider
>   selection during install.

---

## The Provider Landscape

Several packages provide `quickshell`, and all of them are mutually exclusive:

| Package | Repo | Provides | Conflicts With |
|---|---|---|---|
| `quickshell` | cachyos-extra-v3 / extra | — | — |
| `quickshell-git` | cachyos | `quickshell` | `quickshell` |
| `noctalia-qs` | cachyos | `quickshell`, `quickshell-git` | `quickshell`, `quickshell-git` |
| `illogical-impulse-quickshell-git` | AUR (end-4) | `quickshell` | `quickshell` |

**Exactly one may be installed at a time.** Because `quickshell-git` has
`Provides=quickshell`, every dependent still resolves under it:

| Shell | Needs | Runs on stock? | Runs on -git? |
|---|---|---|---|
| caelestia | `caelestia-shell` 2.2.0 → **`quickshell-git`** | no | yes |
| dms | `dms-shell` → `quickshell` | yes | yes (via Provides) |
| ambxst | unpackaged config | yes | yes |
| end4 (`ii`) | unpackaged config | yes | yes |
| end4pc | unpackaged config | yes | yes |
| noctalia | v5 needs **no quickshell at all** | n/a | n/a |

---

## Solution: Two Provider Modules

The quickshell provider is now owned declaratively by one of two dcli modules, which
declare each other in `conflicts:`:

| Module | Package |
|---|---|
| `modules/shells-quickshell.yaml` | `quickshell` |
| `modules/shells-quickshell-git.yaml` | `quickshell-git` |

`shells-quickshell-git` is the enabled default on this host, because caelestia requires it
and every other shell works under it. The six per-shell modules (`caelestia`, `ambxst`,
`shell-dms`, `shell-end4`, `shell-end4pc`, `shell-noctalia`) are unchanged and stay
independently enable-able; `modules/caelestia.yaml` additionally declares
`conflicts: [shells-quickshell]` since it cannot run on the stock provider.

Because all six shells run under `quickshell-git`, runtime switching with
`scripts/switch-shell.sh` still works across all of them without touching packages.

### Switching providers

```bash
scripts/switch-quickshell.sh          # report the current provider
scripts/switch-quickshell.sh git      # -> quickshell-git
scripts/switch-quickshell.sh stock    # -> quickshell (refuses while caelestia is enabled)
```

**Do not try to do this with `dcli module enable` alone.** Three dcli behaviours prevent it:

1. Module-level `conflicts:` only *prompts* at enable time
   (`Disable conflicting module(s)? [y/N]`) — it never uninstalls anything.
2. `auto_prune: false` on this host, so `dcli sync` will not remove the outgoing provider.
3. dcli installs with `pacman -S --noconfirm`, which cannot answer pacman's
   `Remove quickshell? [y/N]` conflict prompt — the sync just fails.

`switch-quickshell.sh` therefore performs the swap as one **interactive** pacman
transaction (the only safe order — removing the old provider first would break
`dms-shell`'s dependency and pacman would refuse), updating dcli module state around it and
running `dcli sync` afterwards to reconcile the rest.

### No pacman.conf change is needed

Once `quickshell-git` is explicitly declared by an enabled module, the provider is
determined and the conflict never arises. There is no `IgnorePkg` entry and none is wanted.

---

## Why the Shell Setup Scripts Never Install a Fork

`scripts/setup-end4.sh` and `scripts/setup-end4pc.sh` deliberately do **not** install
`illogical-impulse-quickshell-git`: it is a fourth mutually-exclusive provider that would
fight whichever one the provider module owns. Both configs run fine on stock `quickshell`
or `quickshell-git`, so the hooks install only the fork's *extra* dependencies as regular
packages.

---

## Noctalia v5 Removes One Provider Entirely

Noctalia v4 required `noctalia-qs`, the worst of the forks — it conflicts with **both**
`quickshell` and `quickshell-git`, so it could never coexist with either provider module.
`scripts/setup-noctalia.sh` worked around that by downloading the `noctalia-qs` package and
extracting it *unpackaged* to `~/.local/opt/noctalia-qs` behind a `~/.local/bin/noctalia`
wrapper.

**Noctalia v5 is a ground-up rewrite with no Quickshell and no Qt** — native C++23/Meson on
Wayland + OpenGL ES. Upstream moved `noctalia-dev/noctalia-shell` → `noctalia-dev/noctalia`
and renamed the package `noctalia-shell` → `noctalia` (AUR source build; its only
`Conflicts` are `noctalia-git` / `noctalia-bin`).

So `shell-noctalia` is now an ordinary module belonging to neither provider group, and
`setup-noctalia.sh` has become a one-shot teardown of the v4 artifacts. Removing the
`~/.local/bin/noctalia` wrapper matters: `~/.local/bin` normally precedes `/usr/bin` on
`PATH`, so it would shadow the real v5 binary.

Migration notes:

- Config moved from `settings.json` to TOML at `~/.config/noctalia/config.toml`. v5 does
  **not** read the v4 JSON (`src/config/config_migrations.cpp` only migrates between TOML
  config versions), so `dotfiles/noctalia/config.toml` was hand-ported. The v4 files are in
  git history — `git show c2789e8:dotfiles/noctalia/settings.json`.
- IPC changed from `noctalia ipc call <object> <method>` to flat kebab-case
  `noctalia msg <command>`; `dotfiles/hypr/shells/noctalia/hyprland.lua` was rewritten.
  Note v5's CLI accepts only `theme`, `msg`, `config`, `dmenu`, `plugins` and
  `firefox-theme` — **there is no `kill` subcommand**, and an unrecognised bare argument
  falls through and *starts the shell*.
- The vendored QML `video-wallpaper` plugin is gone (v5 plugins are Luau). Its official
  replacement is `noctalia/mpvpaper` ("Video Wallpaper") from the plugin store.
- **v5 is still beta** (`5.0.0_beta.4`).

---

## Verification

```bash
# Exactly one provider installed
pacman -Q quickshell quickshell-git

# Dependents resolve against it
pacman -Qi quickshell-git | grep 'Required By'

# The original failure is gone
paru -Syu

# Noctalia is the packaged v5 binary, not the old wrapper
command -v noctalia && noctalia --version

# No leftovers
pacman -Qdt
test ! -e ~/.local/opt/noctalia-qs && echo "v4 fork removed"
```

---

## Status

- [x] Correct root cause identified (`caelestia-shell` 2.2.0 → `quickshell-git`)
- [x] Two provider modules created, with `scripts/switch-quickshell.sh`
- [x] Noctalia migrated to v5, eliminating the `noctalia-qs` workaround
- [ ] Confirm every shell renders under `quickshell-git` (caelestia fork may need a rebuild)
- [ ] Confirm the hand-ported Noctalia v5 `config.toml` and rewritten keybinds
