# Quickshell provider and package conflicts

Current state first, then the dated incident log. Packages move under this
document — before trusting a table here, run `scripts/doctor.sh` or
`pacman -Q quickshell-git quickshell noctalia dux-shell`.

## Current state (verified 2026-10-30)

**Exactly one quickshell provider may be installed.** Every provider
`Conflicts=quickshell`, and each one `Provides=quickshell`, so every dependent
resolves under whichever is installed.

| Package | Repo | Provides | Conflicts with | Status here |
|---|---|---|---|---|
| `quickshell-git` | **AUR only** | `quickshell` | `quickshell` | **installed**: 0.3.2.r11 |
| `quickshell` | `extra` / `cachyos-extra-v3` | — | — | stock 0.3.2 — the pending experiment, below |
| `noctalia-qs` | `cachyos` repo | `quickshell`, `quickshell-git` | both | must stay **absent** (see ambiguity below) |
| `illogical-impulse-quickshell-git` | AUR | `quickshell` | `quickshell` | never installed |

| Shell | Quickshell? | Runtime provider requirement |
|---|---|---|
| caelestia | yes | the fork's README asks for `quickshell-git`; stock is untested (experiment below). No `caelestia-shell` package is installed — the fork runs from `~/.config/quickshell/caelestia` + `~/.local/lib/qt6/qml` |
| ambxst | yes | either |
| dms | yes | `dux-shell` (Provides `dms-shell`, replaces `dms-shell`/`dms-shell-hyprland`) depends on plain `quickshell`: either |
| end4 (`ii`) | yes | either; extra deps are module packages |
| end4pc | yes | either; same dep set |
| omarchy | yes | either (its own package list names `quickshell-git`; the module omits it on purpose) |
| xenon | yes | either |
| glyph | yes | either (rice checkout, no package) |
| ryoku | yes | either; built from the checkout, no `ryoku-desktop` package |
| noctalia | **no** | v5 is native C++/Wayland — belongs to neither provider group |

The provider is owned by one of two modules that list each other in `conflicts:`:
`modules/shells-quickshell-git.yaml` (enabled) and `modules/shells-quickshell.yaml`.
`modules/caelestia.yaml` no longer declares `conflicts: [shells-quickshell]`; it
declares its own runtime dependencies instead (including `libcava`, which nothing
else requires and orphan pruning would otherwise take).

### The `noctalia-qs` ambiguity

Since 2026-08-22 the distribution has no `quickshell-git` binary package; the only
repo package claiming that name is `noctalia-qs` (via `Provides`). So the *name*
`quickshell-git` no longer picks a provider:

```console
$ pacman -Sii quickshell-git
error: package 'quickshell-git' was not found
$ pacman -Sp quickshell-git
.../cachyos/noctalia-qs-0.0.12-2-x86_64.pkg.tar.zst    # not what you want
```

Therefore every install or rebuild must say **`aur/quickshell-git`**
(`paru -S --rebuild aur/quickshell-git`). `scripts/switch-quickshell.sh` and
`scripts/post-update.sh` pin `aur/` for exactly this reason. The module YAML cannot:
dcli does not strip a repo prefix, so with `aur/quickshell-git` declared
`dcli sync --dry-run` lists it as permanently missing. The module keeps the bare
name and the pin lives in the scripts. A normal sync is a no-op while the AUR build
stays installed; the ambiguity bites when bootstrapping a fresh machine, when
switching back from stock, and when anything removes `quickshell-git` first — the
resolver then picks `noctalia-qs`. `scripts/doctor.sh` fails if `noctalia-qs` is
installed, and `post-update.sh` refuses to run on top of it.

### Switching providers

```bash
scripts/switch-quickshell.sh                 # report the current provider
scripts/switch-quickshell.sh git             # -> aur/quickshell-git
scripts/switch-quickshell.sh stock [--yes]   # -> quickshell; warns and confirms while caelestia is enabled
```

The script stops running `qs -c` shells first. The confirmation applies while the
`caelestia` module is enabled; without a tty it refuses unless `--yes` is given. Do not do this with
`dcli module enable` alone: module `conflicts:` only prompts at enable time and never
uninstalls anything; `auto_prune: false` on this host, so a sync never removes the
outgoing provider; and dcli installs with `pacman -S --noconfirm`, which cannot
answer pacman's `Remove quickshell? [y/N]` conflict prompt. The script does the
swap as one interactive pacman transaction (removing the old provider first would
break dependents), updates dcli module state around it, then runs `dcli sync`.

### Pending experiment: stock quickshell 0.3.2 (runbook)

Stock `quickshell` 0.3.2 is now in `extra`, and the distribution rebuilds it on every
Qt bump. If the caelestia fork runs on it, the `aur/` pins, the `noctalia-qs` guard
and most of `post-update.sh`'s self-heal become unnecessary. Qt is 6.12.0 now.

```bash
scripts/switch-quickshell.sh stock           # warns, asks (or --yes)
scripts/switch-shell.sh <name>               # for every shell, one at a time
qs -c <config> 2>&1 | head -30               # errors: Configuration Loaded vs FATAL / not a type
scripts/doctor.sh
```

Configs: `caelestia`, `ii`, `end4-pC`, `xenon`; ambxst, omarchy, dms and noctalia
start through `switch-shell.sh` (see each shell page's health check). If caelestia
and the rest load, keep stock and clean up the pins. If anything fails, go back:
`scripts/switch-quickshell.sh git`. Record the outcome here.

### Why the setup hooks never install a packaged fork

`setup-end4.sh` and `setup-end4pc.sh` do not install
`illogical-impulse-quickshell-git`: it is a fourth mutually exclusive provider. Both
configs run on stock or `quickshell-git`, so their extra dependencies are plain
module `packages:` in `modules/shell-end4.yaml` and `modules/shell-end4pc.yaml`
(declared in both on purpose: dcli has no module-to-module dependency and dedups the
overlap). They live in modules rather than the hook because hooks run once; module
packages are re-checked every sync.

### Noctalia v5 removed one provider entirely

Noctalia v4 required `noctalia-qs`, which conflicts with both providers, hence the
old extract-to-`~/.local/opt` workaround. **v5 is a rewrite with no Quickshell and no
Qt**; the package is `noctalia` (5.4.0 stable, in `extra`; its only `Conflicts` are
`noctalia-git` / `noctalia-bin`), so `shell-noctalia` is an ordinary module. The
v4 teardown hook `setup-noctalia.sh` has been deleted.
Migration notes (config format, IPC, plugins) are in
[shells/noctalia.md](shells/noctalia.md).

### Verification

```bash
pacman -Q quickshell quickshell-git          # exactly one (pacman -Q resolves Provides; doctor matches names)
qs --version && qs --private-check-compat    # exit 0 = built against the installed Qt
scripts/doctor.sh                            # provider, noctalia-qs, dcli sync --dry-run
dcli sync --dry-run
pacman -Qdt                                  # leftovers
```

### Status of the original action items

- [x] Root cause identified (2026-07-25) and two provider modules created, with
  `switch-quickshell.sh`.
- [x] Noctalia migrated to v5; `config.toml` hand-ported and in daily use (validate
  with `noctalia config validate ~/.config/noctalia/config.toml`).
- [x] Every shell renders under `quickshell-git` (verified 2026-07-25 and
  2026-08-01; `qs --private-check-compat` re-checked 2026-10-30 after Qt 6.12.0).
- [ ] Stock-provider experiment above.

---

## Incident log

### 2026-07-25 — `paru -Syu` deadlocks on `quickshell-git and quickshell are in conflict`

```
:: quickshell-git and quickshell are in conflict. Remove quickshell? [y/N]
```

**Root cause:** AUR `caelestia-shell` 2.2.0 changed its dependency from `quickshell`
to `quickshell-git`. The host had 2.1.0 on stock `quickshell`; the upgrade pulled
`quickshell-git` (`Conflicts=quickshell`) and the transaction deadlocked against the
installed provider. Ordinary dependency resolution, not a bug.

Two things an earlier version of this document got wrong: `dms-shell`'s "Required By"
on `quickshell-git` / `noctalia-qs` is normal provider resolution (not a repo
metadata bug), and the claimed `IgnorePkg` fix was never applied and would not have
helped (it only skips upgrades of installed packages; no `pacman.conf` change is
wanted).

**Fix:** the two provider modules and `scripts/switch-quickshell.sh` (above).

The same day, packaging traps in the caelestia fork surfaced because the provider
swap exposed them (see below for when they apply today):

1. The fork's `plugin/src/Caelestia/CMakeLists.txt` target must be named
   `caelestia-core` (upstream's name since v2.1.0). A differently named `.so` next
   to the package's registers `module Caelestia` twice and Qt aborts with *"Cannot
   add multiple registrations for Caelestia"*. Stock quickshell tolerated this;
   `quickshell-git` does not. A rebase had silently reverted the name.
2. Stale `.so` files left in `~/.local/lib/qt6/qml/Caelestia/*/` beat the fresh one
   via the plugin's `$ORIGIN` rpath (*"ButtonRow is not a type"*). The fork's
   `scripts/install.sh` now wipes those dirs before every install.

### 2026-08-22 — Qt 6.11.2 ABI break, and the distribution drops `quickshell-git`

**Symptom:** every `qs` invocation died instantly:

```
qs: symbol lookup error: qs: undefined symbol:
_ZN23QUntypedPropertyBindingC1EP23QPropertyBindingPrivate, version Qt_6_PRIVATE_API
```

**Root cause:** quickshell links Qt **private** APIs, stable only within one Qt build.
`qt6-base 6.11.1 -> 6.11.2` landed while the installed `quickshell-git` was built
against 6.11.1. The distribution's `quickshell-check.hook` canary flagged it in the
same transaction but cannot heal it. A reboot is irrelevant: it is an on-disk
binary/library mismatch. This is a different failure class from the provider
conflict: the right package was installed and merely needed recompiling.

**Fix:** `paru -S --rebuild aur/quickshell-git` (the `aur/` prefix is mandatory, see
the ambiguity section; answering `y` to the prompt a bare name triggers would have
removed the provider). Upstream had added **cli11** as a build dependency; keep it
as an orphan for future rebuilds. `-git` packages do not track dependency ABI
changes, so "Qt bumps without upstream commits" is the recurring gap.

**Also that day:** the distribution dropped its own `quickshell-git` binary package
(it became AUR-only and `noctalia-qs` started claiming the name), and swaync
hijacked notifications while quickshell was dead (see
[shells/README.md](shells/README.md)).

**Prevention:** `hosts/all-shells.yaml` sets `update_hooks.post_update:
scripts/post-update.sh` with `run_as_user: true`. After every `dcli update` it
checks `qs --private-check-compat`, and on failure rebuilds `aur/quickshell-git`
non-interactively and notifies (log: `~/.local/state/dcli-quickshell-heal.log`).
On the stock provider it exits 0 — the distribution rebuilds stock itself. It
refuses to run on top of `noctalia-qs`, and needs a live sudo timestamp for the
rebuild; if that fails, run the manual command.

`update_hooks` has exactly four fields (`pre_update`, `post_update`, `devel`,
`run_as_user`). **Unknown keys are silently ignored**: the host file still carries a
`behavior: ask` there that does nothing, so the post-update hook is never gated by a
prompt. (`behavior` is real for *module* hooks, which is the likely source of the
confusion.) `run_as_user` matters: paru refuses to build as root, and under root
`$HOME` is `/root`.

### 2026-09-11 — `caelestia-shell` package removed

The fork already ran entirely from `~/.config/quickshell/caelestia` and
`~/.local/lib/qt6/qml`, with the package fully shadowed. The package was uninstalled,
`modules/caelestia.yaml` now declares its runtime dependencies directly, and its
`conflicts: [shells-quickshell]` was dropped (the package's hard `quickshell-git`
dependency was the only reason for it).

The two caelestia traps above (*multiple registrations*, and the packaged plugin
shadowing the fork, *LogindManager is not a type*) are now **history**: they only
matter again if the `caelestia-shell` package is ever reinstalled. `QML2_IMPORT_PATH`
in `dotfiles/environment.d/50-caelestia-qml.conf` still matters, because the fork's
plugin lives outside Qt's default import path.

### 2026-10-30 — `dux-shell` replaces `dms-shell`; Qt 6.12.0

The routine update replaced `dms-shell` with `dux-shell` 2.0.0
(`duxlabs-dev/dux-shell`; Provides `dms-shell`, Conflicts/Replaces
`dms-shell`, `dms-shell-hyprland`, `dms-shell-niri`). The `dms` CLI and
`~/.config/DankMaterialShell` are unchanged, so `modules/shell-dms.yaml` just
declares `dux-shell` and keeps its name. `dgop` is gone from the repos
(`dux-gop` Provides it and arrived as a dependency; nothing requires it). The new
package ships `/usr/lib/systemd/user/dms.service`, which must stay disabled —
`switch-shell.sh` owns start/stop and a second launcher double-starts DMS;
`scripts/doctor.sh` checks it. Qt moved to 6.12.0 and quickshell-git to
0.3.2.r11 (private-ABI check still passes), and stock `quickshell` 0.3.2 appeared in
`extra`, which started the experiment above. The packages moved overnight; this is
why AGENTS.md says to run `scripts/doctor.sh` before trusting package docs.

### Lessons

The trigger is not always the cause (a latent fork bug sat harmless for six days until
a provider swap exposed it), and "it worked before" is evidence, not proof — check
`/var/log/pacman.log` to establish what changed and when.
