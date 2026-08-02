# Shells

Nine graphical shells live side by side on this machine. Any one can be made active
at runtime with `scripts/switch-shell.sh <name>` (no argument = fuzzel picker).

| Shell | Launch | Notes |
|---|---|---|
| [caelestia](caelestia.md) | `caelestia shell -d` | Custom fork, built from source. The most involved one. |
| [ambxst](ambxst.md) | `ambxst` | Custom fork, own installer. |
| [dms](dms.md) | `dms run` | Packaged, no fork. Lowest maintenance. |
| [noctalia](noctalia.md) | `noctalia` | v5 — native C++, **no Quickshell**. |
| [end4](end4.md) | `qs -c ii` | end-4 illogical-impulse, custom fork. |
| [end4pc](end4pc.md) | `qs -c end4-pC` | pctrade's end-4 fork, no local fork. |
| [omarchy](omarchy.md) | `quickshell -n -p $OMARCHY_PATH/shell` | DHH's v4 (alpha). Checkout, not a package. Never run its `install.sh`. |
| [xenon](xenon.md) | `qs -c xenon` | MannuVilasara/xenon-shell, no local fork. Was installed system-wide; now user-scope. |
| [ml4w](ml4w.md) | `qs -c ml4w` | mylinuxforwork/dotfiles (ML4W OS), no local fork. Checkout, not a package. |

## The one rule that breaks everything

**Exactly one Quickshell provider may be installed.** Every packaged fork declares
`Conflicts=quickshell`, so they are mutually exclusive:

| Provider | Provides | Conflicts with |
|---|---|---|
| `quickshell` | — | — |
| `quickshell-git` | `quickshell` | `quickshell` |
| `noctalia-qs` | `quickshell`, `quickshell-git` | both |
| `illogical-impulse-quickshell-git` | `quickshell` | `quickshell` |

The provider is owned declaratively by one of two dcli modules —
`shells-quickshell` or `shells-quickshell-git` — which list each other in
`conflicts:`. **`shells-quickshell-git` is the enabled default**, because
`caelestia-shell` >= 2.2.0 hard-depends on it and, since `quickshell-git` provides
`quickshell`, every other shell resolves and runs under it too.

That is what keeps all nine shells runtime-switchable: they share one provider, so
switching shells never touches packages.

omarchy is the newest case of the same trap: `quickshell-git` appears in its own
`install/omarchy-base.packages`, and `modules/shell-omarchy.yaml` deliberately
omits it so the provider keeps exactly one owner.

Switch providers with `scripts/switch-quickshell.sh [stock|git]` — **never** with
`dcli module enable` alone. Full reasoning in
[../PACKAGE-CONFLICTS.md](../PACKAGE-CONFLICTS.md).

Verified 2026-08-01: xenon reports `Configuration Loaded` from its user checkout
and survives a switch round-trip.
Verified 2026-07-25: the other five Quickshell-based shells report
`Configuration Loaded` under `quickshell-git 0.3.0.r3`.

## Never install a packaged Quickshell fork

`setup-end4.sh` and `setup-end4pc.sh` deliberately skip
`illogical-impulse-quickshell-git` and install only the fork's *extra*
dependencies as regular packages. The configs run fine on either provider.

Noctalia used to be the worst offender (`noctalia-qs` conflicts with *both*
providers, hence the old extract-to-`~/.local/opt` hack). **v5 removed Quickshell
entirely**, so that problem is gone — see [noctalia.md](noctalia.md).

## Every setup hook clones MY fork, never upstream

| Shell | origin | branch | `upstream` remote |
|---|---|---|---|
| caelestia | `plusdrag11/caelestia` | `my-caelestia-rebased` | `caelestia-dots/shell` |
| ambxst | `plusdrag11/Ambxst` | `my-ambxst` | `Axenide/Ambxst` |
| end4 | `plusdrag11/dots-hyprland` | `my-ii` | `end-4/dots-hyprland` |
| end4pc | `pctrade/end4-pC` | `main` | none — no personal fork |
| omarchy | `basecamp/omarchy` | `quattro` | none — no personal fork |
| xenon | `MannuVilasara/xenon-shell` | `main` | none — no personal fork |
| ml4w | `mylinuxforwork/dotfiles` | `main` | none — no personal fork |

All three forks pin their branch explicitly. **This matters:** the caelestia
fork's *default* branch is `main` (a mirror of upstream), so a bare clone lands on
the wrong branch and none of the customizations are present. Upstream is kept as a
second remote purely so `git fetch upstream` works for rebasing.

### Do NOT run upstream's installer first

The fork is the only thing to install — there is no "upstream then fork" step, and
running upstream's installer is actively harmful:

- **end4** — `sdata/dist-arch/install-deps.sh` builds and installs the
  `illogical-impulse-quickshell-git` metapkg (line 96), a conflicting provider, and
  replaces the whole hypr stack with `-git` builds (line 20). We never run it; the
  setup hook installs the fork's extra deps itself.
- **caelestia** — the installer we use (`devfiles/install-user.fish`) **only exists
  in the fork**. Upstream's `install.fish` installs system-wide with sudo and
  collides with the `caelestia-shell` package.
- **omarchy** — `install.sh` is a whole-distro installer: sddm, plymouth, snapper,
  ufw, docker, PAM limits, `/etc` and `/usr` writes, and a `config/` tree that
  overwrites `~/.config` for alacritty, foot, btop, git, tmux, lazygit and nvim,
  all of which are dcli-symlinked. `setup-omarchy.sh` reproduces only the clone
  and the theme seed. See [omarchy.md](omarchy.md).
- **ambxst** — we run the fork's own `install.sh`. Its arch package list includes
  stock `quickshell`, which is only skipped because its `filter_packages()` sees
  the `qs` binary already on PATH. **Install a provider before running this hook on
  a fresh machine**, or it will try to pull stock quickshell with `--noconfirm`.

## How a shell becomes active

1. `scripts/switch-shell.sh <name>` writes a bare shell name to
   `~/.config/hypr/shells/active.conf`, kills every running shell, reloads
   Hyprland, then launches the chosen one.
2. `~/.config/hypr/hyprland.lua` reads `active.conf` and `dofile()`s the matching
   per-shell Lua config from its `shell_paths` table.
3. Two shells supply their own Hyprland config from their checkout
   (`~/.local/share/caelestia`, `~/.local/share/ambxst`); the other six use
   `dotfiles/hypr/shells/<name>/hyprland.lua` in this repo. omarchy is a hybrid:
   that file is a *loader* which runs omarchy's own Lua config from its checkout
   and layers the house preferences on top, so it needs no `-overrides.lua`.

Adding or removing a shell means editing **three index-aligned arrays** in
`switch-shell.sh`: `KNOWN`, `icon_files`, and `blurbs`. They must stay in the same
order or the picker shows the wrong icon and switches to the wrong shell.

**And a fourth thing, in a different file:** `lines=` in
`dotfiles/fuzzel/shell-picker.ini` must equal the number of shells. fuzzel
scrolls the overflow with no on-screen indicator, so a stale value silently
hides the shells you just added.

## Fork divergence (2026-07-25)

| Fork | vs upstream | Update with |
|---|---|---|
| ambxst | up to date | fork's own installer |
| end4-pC | up to date | `scripts/update-end4pc.sh` |
| dots-hyprland (end4) | 1 behind | `scripts/update-end4.sh` |
| caelestia | 3 behind | rebase by hand — see [caelestia.md](caelestia.md) |
| omarchy | tracks upstream directly | `scripts/update-omarchy.sh` |
| xenon | tracks upstream directly | `scripts/update-xenon.sh` |
| ml4w | tracks upstream directly | `scripts/update-ml4w.sh` |

The update scripts only work where a plain fast-forward is possible. **caelestia
has no update script on purpose**: it carries 32 local commits, and its last
rebase is what reverted the plugin target name and broke the shell. It needs a
real rebase plus a rebuild-and-verify.

`dms` and `noctalia` are packages and track their repos via `dcli update`.

## Cross-cutting gotchas

- **Hyprland loads `hyprland.conf` *or* `hyprland.lua`, never both.** This setup is
  all-Lua. Under a Lua config `hyprctl keyword` is rejected outright.
- **Submap leak.** Shells that apply binds via `hyprctl keyword submap global`
  leave parser state behind; without the `submap reset` in `switch-shell.sh` the
  next shell's binds all land in the `global` submap and go dead.
- **`exec-once` does not re-fire on `hyprctl reload`**, so `switch-shell.sh`
  starts the shell itself, guarded by `pgrep` to avoid double-starting.
- **Stale processes are the usual cause of "the new shell looks broken."** Check
  with `pgrep -a -f "qs -c|quickshell|ambxst|dms run|noctalia"` — anything other
  than your active shell should not be there.
