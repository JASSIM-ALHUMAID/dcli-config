# Important notes

Hard-won things about this machine that are not obvious from the code. Per-shell
detail lives in [shells/](shells/); package-conflict reasoning in
[PACKAGE-CONFLICTS.md](PACKAGE-CONFLICTS.md).

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
`caelestia-*`, `dms-shell` and `dgop`.

**`auto_prune: false` means sync never removes anything.** Disabling a module does
not uninstall its packages. Use `dcli sync --prune` deliberately.

**`dcli sync` installs with `pacman -S --noconfirm`,** so it cannot answer any
pacman prompt. Any transaction needing a conflict confirmation will just fail —
this is why `scripts/switch-quickshell.sh` does the provider swap itself,
interactively.

**Hooks with `hook_behavior: once` will not re-run.** Check state with
`dcli hooks list`; force one with `dcli module run-hook <module>`.

**Packages are installed in one global phase, before any hook runs.** `dcli sync`
aggregates every enabled module's packages into a single list (`Loaded 149
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
scripts/switch-quickshell.sh            # report current
scripts/switch-quickshell.sh git        # -> quickshell-git (default)
scripts/switch-quickshell.sh stock      # refuses while caelestia is enabled
```

All six shells run under `quickshell-git`, so shell switching never touches
packages. Only swap providers if `quickshell-git` itself regresses.

## Is it safe to `dcli update`?

Yes, with three things to keep in mind:

1. **The caelestia fork is safe from package upgrades** now that it installs under
   `~/.local` — `pacman -Qkk caelestia-shell` should stay at `0 altered files`.
   But if upstream renames the plugin target again, the shell breaks; see
   [shells/caelestia.md](shells/caelestia.md).
2. **noctalia is a beta package** whose config schema and IPC names shift between
   releases. Run `noctalia config validate ~/.config/noctalia/config.toml` after
   updating.
3. **`quickshell-git` tracks git.** A future bump could break any Quickshell-based
   shell. dms is the control case — if dms breaks too, it is the provider, not a
   fork.

## Debugging a shell that will not start

In order:

```bash
# 1. Strays from a previous shell are the most common cause
pgrep -a -f "qs -c|quickshell|ambxst|dms run|noctalia"

# 2. Read the actual error — never guess
qs -c <config> 2>&1 | head -30

# 3. Which provider is installed?
pacman -Q quickshell quickshell-git
```

Error → cause map, all seen for real on this machine:

| Error | Cause |
|---|---|
| `FATAL: Cannot add multiple registrations for Caelestia` | Two `.so`s declare the same QML module. Fork's plugin target name drifted from upstream's. |
| `<Type> is not a type` | A stale `.so` inside a module dir beats the fresh one in `../lib/` via `$ORIGIN` rpath. Wipe and reinstall. |
| `LogindManager is not a type` | `QML2_IMPORT_PATH` missing, so the packaged plugin is used instead of the fork's. |
| `module qs.modules...shapes is not installed` | Git submodules not populated (end4 / end4pc). |
| Binds dead after switching | Submap state leaked; `switch-shell.sh` resets it. |

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

- Hyprland loads `hyprland.conf` **or** `hyprland.lua`, never both. This setup is
  all-Lua, so `hyprctl keyword` is rejected (`keyword can't work with non-legacy
  parsers`).
- `hl.exec_cmd` at the top level re-runs on **every** `hyprctl reload`, which
  spawns a duplicate shell per switch. Use `hl.on("hyprland.start", ...)` instead —
  it fires once per session, like the old `exec-once`.
- Hyprland applies its own `env` only at startup, so anything added to a shell's
  env block does not exist in a session that started before it. Scripts must set
  such vars explicitly.

## Repo hygiene

- Two repos are in play: `~/.config/dcli` and the caelestia fork at
  `~/Projects/shell/real`. Changes to the shell itself belong in the fork.
- `~/.config/caelestia` is a symlink **into the fork**, so caelestia's runtime
  config is version-controlled there, not here. Do not let a dotfiles sync replace
  it — the same is true of `~/.config/quickshell/{caelestia,ii,end4-pC}`.
- `wezterm` has its own upstream repo; dcli keeps only a snapshot copy.
