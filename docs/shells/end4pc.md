# end4pc

[pctrade/end4-pC](https://github.com/pctrade/end4-pC), a fork of end-4's
dots-hyprland, run as an independent Quickshell config named `end4-pC`. It runs
**alongside** [end4](end4.md) without either interfering with the other — that
separation is deliberate and took work.

| | |
|---|---|
| Module | `modules/shell-end4pc.yaml` |
| Packages | none declared — the hook installs deps directly |
| Launch | `qs -c end4-pC` |
| Setup hook | `scripts/setup-end4pc.sh` |
| Patch script | `scripts/patch-end4pc.sh` |
| Update | `scripts/update-end4pc.sh` |

## Layout

| Path | What |
|---|---|
| `~/.local/share/end4-pC` | Checkout, **source of truth**. origin `pctrade/end4-pC`, branch `main` — **no personal fork** |
| `~/.config/quickshell/end4-pC` → the checkout root | The repo root **is** the config (flat layout — no `dots/.config/...` wrapper like the `ii` fork) |
| `~/.config/matugen-end4pc` | Its **own** matugen config — dcli-managed dotfile |
| `~/.config/illogical-impulse-pC` | Runtime state, separate from end4's |
| `dotfiles/hypr/shells/end4pc/hyprland.lua` | Its Hyprland config (standalone, in this repo) |

## Why `patch-end4pc.sh` exists

Upstream end4-pC expects `~/.config/matugen` — but [end4](end4.md) **owns** that
path as a symlink into its own checkout. Running both meant end4pc died with end4.

`patch-end4pc.sh` repoints the checkout at end4pc-owned paths. It rewrites the
fork's `scripts/colors/switchwall.sh` to use `~/.config/matugen-end4pc`, points the shell's
settings app at end4pc's own files, and seeds
`~/.config/illogical-impulse-pC/config.json`. It is **idempotent** and is called
at the end of `setup-end4pc.sh`.

`setup-end4pc.sh` invokes it directly rather than via its `as_user` helper —
`patch-end4pc.sh` does its own `SUDO_USER` handling, and re-sudoing would make it
resolve `REAL_USER` as root.

**Re-run it after any upstream pull**, since a pull can restore upstream's paths:

```bash
bash ~/.config/dcli/scripts/patch-end4pc.sh
```

## Theming writes into this repo

end4pc's matugen templates write `dotfiles/hypr/shells/end4pc/colors.lua`, which
its `hyprland.lua` loads last — along with `monitors.lua` and `overrides/*.lua`,
written by the shell's own settings app (`SUPER + I`). So wallpaper changes and
in-shell settings edits produce **git changes in this repo**. That is expected.

## Never install `illogical-impulse-quickshell-git`

Same rule as [end4](end4.md) — it is a conflicting Quickshell provider. The config
runs on whichever provider is enabled.

`setup-end4pc.sh` installs the **same dependency set** as `setup-end4.sh`,
duplicated on purpose and all `--needed`, so it is a no-op when end4 already ran
and end4pc still stands alone if `shell-end4` is disabled.

## Submodules are mandatory

Like the `ii` fork, this config has a `.gitmodules` and fails to load without its
submodules populated. After a manual pull:

```bash
git -C ~/.local/share/end4-pC submodule update --init --recursive --depth 1
```

## What is still shared with end4

Only `~/.local/state/quickshell/user` and the `secret-tool` keyring entry. Neither
is needed for end4pc to run, so the two shells are effectively independent.

## Status (2026-07-25)

- **17 commits behind `origin/main`** — the most out-of-date shell here. There is
  no personal fork, so `origin` *is* upstream and a pull is a plain fast-forward
  with no local commits to rebase.
- Loads cleanly under `quickshell-git 0.3.0.r3` → `Configuration Loaded`.

After updating, re-run `patch-end4pc.sh` and the submodule update.

## Health check

```bash
git -C ~/.local/share/end4-pC status --short
git -C ~/.local/share/end4-pC submodule status
grep -c matugen-end4pc ~/.local/share/end4-pC/scripts/colors/switchwall.sh  # patch applied?
qs -c end4-pC 2>&1 | grep -E "Configuration Loaded|FATAL|not installed"
```
