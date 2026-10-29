# end4pc
[JASSIM-ALHUMAID/my-end4-pC](https://github.com/JASSIM-ALHUMAID/my-end4-pC), a personal fork of
[pctrade/end4-pC](https://github.com/pctrade/end4-pC), run as an independent Quickshell config named `end4-pC`. It runs
**alongside** [end4](end4.md) without either interfering with the other — that
separation is deliberate and took work.

| | |
|---|---|
| Module | `modules/shell-end4pc.yaml` |
| Packages | declared in the module — the same list as `shell-end4`, duplicated on purpose |
| Launch | `qs -c end4-pC` |
| Setup hook | `scripts/setup-end4pc.sh` |
| Patch script | `scripts/patch-end4pc.sh` — currently a no-op safety net, see below |
| Update | `scripts/update-end4pc.sh` |

## Layout

| Path | What |
|---|---|
| `~/.local/share/end4-pC` | Checkout, **source of truth**. origin `JASSIM-ALHUMAID/my-end4-pC`, branch `my-end4pc`, upstream `pctrade/end4-pC` |
| `~/.config/quickshell/end4-pC` → the checkout root | The repo root **is** the config (flat layout — no `dots/.config/...` wrapper like the `ii` fork) |
| `~/.config/matugen-end4pc` | Its **own** matugen config — dcli-managed dotfile |
| `~/.config/illogical-impulse-pC` | Runtime state, separate from end4's |
| `dotfiles/hypr/shells/end4pc/hyprland.lua` | Its Hyprland config (standalone, in this repo; opts into `common.*`, but leaves gaps, decoration, layout and animations to the settings app) |

## Why `patch-end4pc.sh` exists (and why it is now a no-op)

Upstream end4-pC expects `~/.config/matugen` — but [end4](end4.md) **owns** that
path as a symlink into its own checkout. Running both meant end4pc died with end4.

`patch-end4pc.sh` repoints a checkout at end4pc-owned paths. It rewrites the fork's
`scripts/colors/switchwall.sh` to use `~/.config/matugen-end4pc`, points the shell's
settings app at end4pc's own files, and seeds
`~/.config/illogical-impulse-pC/config.json`. It is idempotent and is called at the
end of `setup-end4pc.sh` and `update-end4pc.sh`.

**The `my-end4pc` fork now carries those rewrites as commits**, so on the current
checkout `patch-end4pc.sh` reports "already patched — nothing to do". It, and
`update-end4pc.sh`, are kept as a safety net (for a clone of plain upstream, or an
upstream merge that restores the old paths) — not because anything needs them today.
Run it by hand after a manual merge from upstream:

```bash
bash ~/.config/dcli/scripts/patch-end4pc.sh
```

`setup-end4pc.sh` invokes it directly rather than through `as_user` — the patch
script does its own `SUDO_USER` handling.

## Theming writes into this repo

end4pc's matugen templates write `dotfiles/hypr/shells/end4pc/colors.lua`, which
its `hyprland.lua` loads last — along with `monitors.lua` and `overrides/*.lua`,
written by the shell's own settings app (`SUPER + I`). So wallpaper changes and
in-shell settings edits produce **git changes in this repo**. That is expected.

## Never install `illogical-impulse-quickshell-git`

Same rule as [end4](end4.md) — it is a conflicting Quickshell provider. The config
runs on whichever provider is enabled.

`shell-end4pc` declares the **same dependency set**
as `shell-end4`, as module `packages:` duplicated on purpose (dcli dedups the overlap), so end4pc
still stands alone if `shell-end4` is disabled.

## Submodules are mandatory

Like the `ii` fork, this config has a `.gitmodules` and fails to load without its
submodules populated. `scripts/update-end4pc.sh` handles this too; run it by hand
only after a manual pull:

```bash
git -C ~/.local/share/end4-pC submodule update --init --recursive --depth 1
```

## What is still shared with end4

Only `~/.local/state/quickshell/user` and the `secret-tool` keyring entry. Neither
is needed for end4pc to run, so the two shells are effectively independent.

## Updating

```bash
~/.config/dcli/scripts/update-shells.sh end4pc     # refuses on a dirty tree
```

which runs `scripts/update-end4pc.sh`: `git checkout -- .`, `git pull --ff-only`, a
submodule update, then `patch-end4pc.sh`. Restart the shell afterwards.

> **Warning: `update-end4pc.sh` runs `git checkout -- .`, which discards every
> uncommitted change in the checkout.** That was designed for the era when the path
> patches were uncommitted working-tree edits. The checkout is now a real fork with
> its own commits and branch, so any uncommitted work there is exactly what would be
> lost. `update-shells.sh` refuses to run the script on a dirty tree; running the
> script directly does not. Commit or stash first, or prefer
> `git -C ~/.local/share/end4-pC pull --ff-only` plus the submodule update. (Whether
> to simplify or retire the script is the user's open decision.)

## Health check

```bash
scripts/doctor.sh
scripts/update-shells.sh --status end4pc
git -C ~/.local/share/end4-pC status --short
git -C ~/.local/share/end4-pC submodule status
grep -c matugen-end4pc ~/.local/share/end4-pC/scripts/colors/switchwall.sh  # patch applied? (>0)
qs -c end4-pC 2>&1 | grep -E "Configuration Loaded|FATAL|not installed"
```
