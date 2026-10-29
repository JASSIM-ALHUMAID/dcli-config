# Important notes

Hard-won things about this machine that are not obvious from the code. Per-shell
detail lives in [shells/](shells/); package-conflict reasoning in
[PACKAGE-CONFLICTS.md](PACKAGE-CONFLICTS.md); how the pieces connect (and the
new-shell checklist) in [ARCHITECTURE.md](ARCHITECTURE.md); Hyprland Lua rules in
[HYPRLAND-LUA.md](HYPRLAND-LUA.md). dcli's own manual is not vendored here — see
`dcli --help` and dcli's project at <https://gitlab.com/theblackdon> (v0.2.2).

## dcli behaviours that surprise you

**`dotfiles:` keys in flat YAML modules do nothing.** dcli only honours them for
Lua and directory modules. `scripts/link-dotfiles.sh` (the `base` module's hook) is
the real mechanism — it symlinks `~/.config/<name>` → `dotfiles/<name>` for each
entry in its `TARGETS` array. **Adding a `dotfiles:` entry to a `.yaml` module has
no effect unless you also add the name to that array.**

**`conflicts:` is advisory, not enforced.** On `dcli module enable` it prompts
`Disable conflicting module(s)? [y/N]` and nothing more. It never uninstalls
anything, and it is not re-checked at sync time.

**There is no module → module dependency mechanism.** `import` exists only at host
level. A "grouping module" that pulls in other modules is impossible — an earlier
plan assumed otherwise and would have silently un-declared `quickshell`,
`caelestia-*` and the DMS packages.

**`auto_prune: false` means sync never removes anything.** Disabling a module does
not uninstall its packages. Use `dcli sync --prune` deliberately.

**`dcli sync` installs with `pacman -S --noconfirm`,** so it cannot answer any
pacman prompt. Any transaction needing a conflict confirmation will just fail —
this is why `scripts/switch-quickshell.sh` does the provider swap itself,
interactively.

**Hooks with `hook_behavior: once` will not re-run, so packages belong in
modules.** A package installed only by a setup hook is never re-checked: it is not
in the declared state, `dcli sync --dry-run` cannot see it missing, and it
disappears the day something removes it. Module `packages:` are checked on every
sync. That is why the end4/end4pc/xenon/omarchy dependencies moved out of their
hooks (end4 and end4pc declare the same list in both modules, because there is no
module-to-module dependency). `scripts/doctor.sh` fails when `dcli sync --dry-run`
has anything to install. Check hook state with `dcli hooks list`; force one with
`dcli module run-hook <module>`.

**Packages are installed in one global phase, before any hook runs.** `dcli sync`
aggregates every enabled module's packages into a single list (`Loaded N
declared packages`) and installs them, and only then runs post-install hooks.
`module_processing: parallel` does **not** affect this — parallelism applies to
module processing, not to the package phase.

This is load-bearing: a hook can rely on any package declared by *any* enabled
module already being installed. It is why `setup-ambxst.sh` is safe on a fresh
machine despite its installer wanting stock `quickshell` — `shells-quickshell-git`
has already provided `/usr/bin/qs` by then.

Verified by correlating `dcli hooks list` timestamps (UTC) with
`/var/log/pacman.log` (`+0300`): packages installed 14:16:19–14:16:32 UTC, hooks
ran at 14:16:33 UTC.

## Provider switching

```bash
scripts/switch-quickshell.sh                # report current
scripts/switch-quickshell.sh git            # -> aur/quickshell-git (default)
scripts/switch-quickshell.sh stock [--yes]  # warns + confirms while caelestia is enabled
```

Every Quickshell shell runs under `quickshell-git`, so shell switching never touches
packages. Only swap providers if `quickshell-git` itself regresses, or to run the
stock-provider experiment documented in [PACKAGE-CONFLICTS.md](PACKAGE-CONFLICTS.md).

## Is it safe to `dcli update`?

Yes, with three things to keep in mind:

1. **The caelestia fork is independent of pacman.** The `caelestia-shell` package is
   not installed (removed 2026-09-11) and the fork builds under `~/.local`, so an
   update cannot clobber it. It can still break if Qt moves: a rebuild of the
   plugin may be needed (see [shells/caelestia.md](shells/caelestia.md)).
2. **noctalia 5.x is a stable package in `extra`,** but its config schema and IPC
   names still shift between minor releases. Run
   `noctalia config validate ~/.config/noctalia/config.toml` after updating.
3. **`quickshell-git` tracks git and links Qt private ABI.** A Qt bump can break every
   Quickshell shell at once; `scripts/post-update.sh` (the `update_hooks.post_update`
   hook) rebuilds it automatically. The packaged shell is the control case: if
   `dms` (now the `dux-shell` package) breaks too, it is the provider or Qt, not a
   fork. Packages also get replaced under you (dux-shell replaced dms-shell
   overnight, 2026-10-30) — run `scripts/doctor.sh` after an update.

After updating checkouts, `scripts/update-shells.sh --status` shows what is behind.

## Debugging a shell that will not start

In order:

```bash
# 0. The whole picture in one read-only command: packages, provider, Hyprland
#    config errors, links, checkouts, services. Start here.
scripts/doctor.sh

# 1. Strays from a previous shell are the most common cause
pgrep -a -f "qs -c|quickshell|ambxst|dms run|noctalia"

# 2. Read the actual error — never guess
qs -c <config> 2>&1 | head -30

# 3. Which provider is installed?
pacman -Q quickshell quickshell-git

# 4. Is the Hyprland config itself valid? (live session, then any shell offline)
hyprctl configerrors
DCLI_HYPRMOD_SHELL=<shell> Hyprland --verify-config -c ~/.config/hypr/hyprland.lua

# 5. What would a switch do? (touches nothing)
scripts/switch-shell.sh --dry-run <shell>
```

Error -> cause map, all seen for real on this machine. The first three only apply
while the `caelestia-shell` package is installed or the fork's plugin build is wrong:

| Error | Cause |
|---|---|
| `FATAL: Cannot add multiple registrations for Caelestia` | Two `.so`s declare the same QML module: the fork's plugin target name drifted from upstream's, or the package is installed beside it. |
| `<Type> is not a type` | A stale `.so` inside a module dir beats the fresh one in `../lib/` via `$ORIGIN` rpath. Wipe and reinstall. |
| `LogindManager is not a type` | `QML2_IMPORT_PATH` missing, so a packaged plugin (if installed) or none is used instead of the fork's. |
| `undefined symbol ... Qt_6_PRIVATE_API` | quickshell built against an older Qt. `paru -S --rebuild aur/quickshell-git`. |
| `module qs.modules...shapes is not installed` | Git submodules not populated (end4 / end4pc). |
| Binds dead after switching | Submap state leaked; `switch-shell.sh` resets it. |
| Desktop has 3 binds, `configerrors` empty (omarchy) | A wrong `OMARCHY_PATH` from the environment; see [shells/omarchy.md](shells/omarchy.md). |

Two lessons from the 2026-07-25 incident worth repeating: **the trigger is not
always the cause** — a latent fork bug sat harmless for six days until a provider
swap exposed it. And **"it worked before" is evidence, not proof of correctness**;
check the pacman log (`/var/log/pacman.log`) to establish what actually changed and
when.

## Theming writes into this repo

Several shells' theming regenerates files that are committed here — end4pc's
matugen writes `dotfiles/hypr/shells/end4pc/colors.lua`, caelestia's CLI rewrites
the scheme, noctalia writes its own state under `~/.config/noctalia`. **Unexpected
git changes after a wallpaper change are normal.** `scheme/current.conf` is
gitignored for this reason; `dotfiles/noctalia/colors.json` was too.

## Hyprland Lua rules

Moved to [HYPRLAND-LUA.md](HYPRLAND-LUA.md): the Lua parser rules (`hyprctl keyword`
is rejected, `hl.on("hyprland.start")` vs reload), `require` vs `dofile`, the
fully-qualified `shells.<name>.*` names, the `common/` layer, and the
`Hyprland --verify-config` recipe.

## Repo hygiene

Several repos are in play. Changes to a shell itself belong in its checkout, not here.

| Checkout | Path | origin (branch) | upstream |
|---|---|---|---|
| caelestia fork | `~/Projects/shell/real` | `JASSIM-ALHUMAID/my-caelestia` (`my-caelestia`) | `caelestia-dots/shell` |
| ambxst fork | `~/.local/src/ambxst` | `JASSIM-ALHUMAID/my-Ambxst` (`my-ambxst`) | `Axenide/Ambxst` |
| end4 fork | `~/.local/share/dots-hyprland` | `JASSIM-ALHUMAID/my-end4` (`my-ii`) | `end-4/dots-hyprland` |
| end4pc fork | `~/.local/share/end4-pC` | `JASSIM-ALHUMAID/my-end4-pC` (`my-end4pc`) | `pctrade/end4-pC` |
| omarchy | `~/.local/share/omarchy` | `basecamp/omarchy` (`quattro`) | none |
| xenon | `~/.local/share/xenon-shell` | `MannuVilasara/xenon-shell` (`main`) | none |
| wezterm | `~/.config/wezterm` | `JASSIM-ALHUMAID/wezterm` | — (a secondary `plusdrag11` remote is added by `setup-wezterm.sh`) |

`scripts/update-shells.sh [--status]` reports or fast-forwards all of them. It
reports caelestia and ambxst only (development forks, never pulled) and refuses to
run an updater on a dirty tree. `scripts/doctor.sh` lists each checkout's branch
and dirty count.

- `~/.config/caelestia` is a symlink **into the caelestia fork**, so its runtime
  config is version-controlled there, not here. Do not let a dotfiles sync replace
  it — the same is true of `~/.config/quickshell/{caelestia,ii,end4-pC,xenon}`.
- `~/.config/fish` and `~/.config/fastfetch` are symlinks into
  `~/.local/share/caelestia` (the caelestia-dots clone). This repo does not create
  them; they are unmanaged.
- `link-dotfiles.sh` backs up a real directory it replaces to
  `~/.config/<name>.bak-<timestamp>`; `doctor.sh` warns about the ones left over.
  Delete them once you have checked nothing was lost.
- `wezterm` has its own upstream repo; dcli keeps only a snapshot copy.
