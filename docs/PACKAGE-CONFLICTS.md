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
| `quickshell-git` | **AUR only** (see below) | `quickshell` | `quickshell` |
| `noctalia-qs` | cachyos | `quickshell`, `quickshell-git` | `quickshell`, `quickshell-git` |
| `illogical-impulse-quickshell-git` | AUR (end-4) | `quickshell` | `quickshell` |

> **Changed 2026-08-22:** CachyOS **dropped its own `quickshell-git` binary package**. It is
> now AUR-only, and `noctalia-qs` is the sole *repo* package claiming that name (via
> `Provides`). Verify with:
>
> ```console
> $ pacman -Sii quickshell-git
> error: package 'quickshell-git' was not found
> $ pacman -Sp quickshell-git
> .../cachyos/noctalia-qs-0.0.12-2-x86_64.pkg.tar.zst      # <- not what you want
> $ pacman -Qm | grep quickshell
> quickshell-git 0.3.1.r0.g1a4716c-1                        # foreign: no repo tracks it
> ```
>
> This is why every install/rebuild of it must say `aur/quickshell-git`.

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

> **Amended 2026-08-22:** the second half of that no longer holds. Declaring the *name*
> `quickshell-git` no longer determines the provider, because CachyOS dropped the repo
> package and `noctalia-qs` now claims the name via `Provides`. The name is ambiguous again.
>
> It is not a live hazard while the package stays installed — `dcli sync` only installs what
> is *missing*, and `pacman -Qq quickshell-git` matches the installed AUR build, so a normal
> sync is a no-op (verified with `dcli sync --dry-run`). The ambiguity bites in three cases:
>
> 1. bootstrapping this host config on a fresh machine,
> 2. `switch-quickshell.sh git` when coming back from the stock provider,
> 3. anything that removes `quickshell-git` first.
>
> In all three, the resolver picks `noctalia-qs`. `switch-quickshell.sh` now pins `aur/` for
> exactly this reason. **`modules/shells-quickshell-git.yaml` cannot be pinned the same way:**
> dcli does not strip a repo prefix from package names — with `aur/quickshell-git` declared,
> `dcli sync --dry-run` reports it as a permanently missing package on every run. So the
> module keeps the bare name and the pin lives in the scripts.

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

---

## Incident 2026-08-22: Qt 6.11.2 ABI Break

**Symptom:** every `qs` invocation died instantly:

```
qs: symbol lookup error: qs: undefined symbol:
_ZN23QUntypedPropertyBindingC1EP23QPropertyBindingPrivate, version Qt_6_PRIVATE_API
```

**Root cause:** quickshell links Qt **private** APIs (`Qt_6_PRIVATE_API` symbol version),
which are only stable within one Qt build. `qt6-base 6.11.1 → 6.11.2` landed at 21:20 while
the installed `quickshell-git` binary was built on Jul 25 against 6.11.1. The
`/usr/share/libalpm/hooks/quickshell-check.hook` canary flagged it in the same transaction
(21:21) but cannot heal it. A reboot is irrelevant; this is an on-disk binary/library
mismatch, not stale state.

**This is a different failure class from the provider conflicts above:** there the question
is *which* package owns `quickshell`; here the correct package was already installed and
merely needed recompiling against new Qt headers.

### The fix

```bash
paru -S --rebuild aur/quickshell-git   # explicit aur/ prefix is required, see below
qs --version && qs --private-check-compat
qs -c caelestia -d
```

Notes from this incident:

- **Always use the `aur/` prefix.** Plain `paru -S --rebuild quickshell-git` resolves to the
  CachyOS repo package `noctalia-qs` (`Provides: quickshell-git`) and prompts to remove the
  AUR package caelestia depends on. Answering `y` there would have broken caelestia and
  desynced dcli's provider ownership.
- Upstream had added **cli11** as a new build dependency since the last build; paru pulled
  it automatically. It remains an orphan afterwards (build-time only) — keep it for future
  rebuilds.
- `-git` packages do NOT track dependency ABI changes: paru only auto-rebuilds them when
  upstream gets new commits. "Qt bumps without upstream commits" is the recurring gap.

### Prevention: post-update self-heal hook

`hosts/cachyos-desktop.yaml` now sets:

```yaml
update_hooks:
  pre_update: null
  post_update: scripts/post-update.sh
```

The hook runs after every `dcli update`, checks `qs --private-check-compat`, and if the ABI
check fails, rebuilds `aur/quickshell-git` non-interactively and notifies via
`notify-send`. Log: `~/.local/state/dcli-quickshell-heal.log`. If the auto rebuild fails
(e.g. sudo timestamp expired), fall back to the manual command above.

The hook also refuses to run on top of `noctalia-qs` and bails with a critical notification
instead, since rebuilding cannot succeed while the conflicting provider owns `quickshell`.

#### `update_hooks` schema quirks

`UpdateHooksConfig` has exactly four fields — `pre_update`, `post_update`, `devel`,
`run_as_user`. **Unknown keys are silently ignored, not rejected.** A `behavior:` key inside
`update_hooks` therefore does nothing at all: `dcli validate` passes with `behavior: ask`,
with `behavior: always`, with `behavior: totally-bogus-value`, and with the key removed
entirely. (`behavior` is real for *module* hooks — `hook_behavior` / `pre_hook_behavior` /
`post_hook_behavior` in the module schema — which is the likely source of the confusion.)

The practical consequence: **the post-update hook is not gated by any prompt — it always
runs.** That is what you want for a health check, but do not expect an "ask" step.

`run_as_user` matters here. paru refuses to build as root, and under root `$HOME` is `/root`,
so the heal log would land in the wrong place and `notify-send` would never reach the user's
session bus. The script re-execs itself via `runuser -u "$SUDO_USER"` as a backstop, but
setting `run_as_user: true` is the correct configuration.
