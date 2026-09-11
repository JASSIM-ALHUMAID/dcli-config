# end4pc
[plusdrag11/end4-pC](https://github.com/plusdrag11/end4-pC), a personal fork of
[pctrade/end4-pC](https://github.com/pctrade/end4-pC), run as an independent Quickshell config named `end4-pC`. It runs
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
| `~/.local/share/end4-pC` | Checkout, **source of truth**. origin `plusdrag11/end4-pC` (personal fork), branch `my-end4pc`, upstream `pctrade/end4-pC` |
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

**Any upstream pull must be followed by re-running it**, since a pull restores
upstream's paths. `scripts/update-end4pc.sh` does that for you — only run it by
hand after a manual `git pull`:

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
~/.config/dcli/scripts/update-end4pc.sh
```

That is the whole procedure — it discards the path patches, pulls, updates
submodules, and re-applies `patch-end4pc.sh`. Nothing to do by hand afterwards
except restart the shell.

**Why it discards first:** `patch-end4pc.sh` leaves 14 files modified in the
working tree, which would make the pull non-fast-forward. So the script runs
`git checkout -- .` before pulling.

That is safe *only because* every modified file is one the patch script owns and
will recreate. **Any manual edit you make in this checkout will be destroyed** —
there is no personal fork here, so there is nowhere for local changes to live.
Keep customizations in `dotfiles/hypr/shells/end4pc/` instead. To confirm before
updating, the dirty set should match the patch script's file list exactly:

```bash
cd ~/.local/share/end4-pC && git status --porcelain | wc -l    # expect 14
```

## Health check

```bash
git -C ~/.local/share/end4-pC status --short
git -C ~/.local/share/end4-pC submodule status
grep -c matugen-end4pc ~/.local/share/end4-pC/scripts/colors/switchwall.sh  # patch applied?
qs -c end4-pC 2>&1 | grep -E "Configuration Loaded|FATAL|not installed"
```
