# omarchy

DHH's Hyprland desktop, run here as **a shell, not a distribution**. That
distinction is the whole story of this page.

| | |
|---|---|
| Module | `modules/shell-omarchy.yaml` |
| Source | git checkout, no package — `~/.local/share/omarchy` |
| Version | `4.0.0.alpha`, branch `quattro` |
| Launch | `quickshell -n -p $OMARCHY_PATH/shell` |
| Config | `~/.config/omarchy/shell.json` (bar layout, plugins, idle timers) |
| Upstream | [basecamp/omarchy](https://github.com/basecamp/omarchy) — no personal fork |
| Setup hook | `scripts/setup-omarchy.sh` |
| Update | `scripts/update-omarchy.sh` |

## Why v4 and not the stable release

The tagged releases (v3.8.4 and back, branch `master`) are **waybar + walker +
mako + swaybg, configured with `.conf` files**. That is a second bar/launcher
stack and a config format this setup does not use — Hyprland loads
`hyprland.conf` *or* `hyprland.lua`, never both, and this machine is all-Lua.

`quattro` (the default branch, v4.0.0.alpha) replaced that entire stack with
**one Quickshell instance**. Bar, launcher, notifications, OSD, polkit agent and
panels are all plugins inside a single process, and the Hyprland config became
Lua. `quickshell-git` — already the provider enabled here — is what it wants.
So the fit is architectural, not a coincidence, and the older stable line would
have been the harder integration.

The cost: **it is alpha and moves daily.** Expect `update-omarchy.sh` to be
routine, and expect keybinds and `shell.json` keys to shift under you.

## We never run `install.sh`

omarchy is a distro installer, not a dotfiles repo. `install/config/` alone sets
up sddm, plymouth, snapper snapshots, ufw, docker, PAM lockout limits and a
chromium policy directory under `/etc` and `/usr`; `config/` overwrites
`~/.config` for alacritty, foot, ghostty, btop, git, tmux, lazygit and nvim —
every one of which is dcli-symlinked here, so it would write straight into this
repo's dotfiles or clobber them.

`setup-omarchy.sh` reproduces by hand the only two user-level steps that matter:
the checkout, and the theme seed from `install/user/theme.sh`.

### First-run is deliberately marked done

omarchy's `autostart.lua` calls `omarchy-first-run` on **every** session start.
On a machine that was not installed by `install.sh`, most of what it does is
wrong:

- installs pacman post-update hooks (voxtype, fingerprint setup)
- `systemctl --user enable --now` on five units (`bt-agent`,
  `omarchy-sleep-lock`, …) that only exist if the omarchy package installed them
- **gsettings the GTK theme, colour scheme and icon theme for the whole user
  session** — i.e. for the other six shells too
- applies "speaker tuning" aimed at specific laptop hardware

The hook pre-creates `~/.local/state/omarchy/done/first-run-user`, which is
omarchy's own skip mechanism (`bin/omarchy-done`), so nothing is patched and a
`git pull` stays a fast-forward. Run `omarchy-first-run --force` by hand if you
ever want it.

### Theming still reaches outside omarchy

`omarchy-theme-set` fans out to editors and the desktop on every theme change.
The hook sets omarchy's own opt-out flags for the editor half:

```
~/.local/state/omarchy/toggles/skip-{vscode,vscode-insiders,codium,cursor}-theme-changes
```

**Not opted out** (there is no toggle for it): `omarchy-theme-set-gnome`, which
gsettings `gtk-theme`, `color-scheme` and `icon-theme`. Changing the omarchy
theme therefore changes the GTK look of *every* shell on this machine. That is
the one cross-shell side effect this integration leaves in place — it is
cosmetic and reversible with `gsettings`, and blocking it would mean patching
the checkout.

## Layout

| Path | What | Created by |
|---|---|---|
| `~/.local/share/omarchy` | the checkout — this is `$OMARCHY_PATH` | `setup-omarchy.sh` |
| `$OMARCHY_PATH/shell` | the Quickshell shell: `shell.qml` + `plugins/` | upstream |
| `$OMARCHY_PATH/bin` | ~150 `omarchy-*` scripts; the QML calls them by bare name | upstream |
| `$OMARCHY_PATH/default/hypr/*.lua` | Hyprland defaults, entered via `bootstrap.lua` | upstream |
| `$OMARCHY_PATH/themes/` | the 22 shipped themes | upstream |
| `~/.config/omarchy` → `dcli/dotfiles/omarchy` | `shell.json`, `hooks/`, `extensions/`, user `themes/` | `link-dotfiles.sh` |
| `~/.local/state/omarchy` | generated: `current/theme`, `toggles/`, `done/` | `omarchy-theme-set`, the shell |

`~/.local/state/omarchy` is **not** linked into this repo. It is per-machine
generated state, and `current/theme` is a path-dependent symlink into the
checkout. `dotfiles/omarchy/{plugins,themes}/` are gitignored because
`omarchy plugin add` and `omarchy theme install` clone git repos into them.

## `$OMARCHY_PATH` — this is the main trap, and it bit once already

Upstream defaults it to `/usr/share/omarchy`, the path its own package installs
to. We run from a checkout, so without the variable every `omarchy-*` script and
`default/hypr/bootstrap.lua` looks in a directory that does not exist.

The mistake worth not repeating: **do not source this from the environment at
all.** `os.getenv()` in a Hyprland Lua config runs at config **parse** time, so a
login-scoped variable is not reliably there — and worse, a variable that is set
to the *wrong* thing silently beats any fallback. Two things break on a bad
path, and **only the first one is loud**:

| Consumer | On a bad path |
|---|---|
| `bootstrap.lua` → `package.path` | `module 'default.hypr.omarchy' not found`; the config dies, so nothing after it registers either |
| `paths.lua` → `paths.omarchy_path` | `bindings.lua` and `apps.lua` pass it to `require_all.files()`, which shells out to `find <dir>`. A nonexistent directory yields no files and **no error**: zero keybinds, silently |

### How it actually broke, once

An earlier `dotfiles/environment.d/60-omarchy.conf` (since **deleted**) set:

```
OMARCHY_PATH=%h/.local/share/omarchy
```

`environment.d` expands `$VAR` and `${VAR}`, but **`%h` is a systemd *unit-file*
specifier and is not expanded here** — `environment.d(5)`: "no other elements of
shell syntax are supported." So the variable held the literal string `%h/...`,
which outranked the correct default, and after a reboot the desktop came up with
**3 binds instead of 216**. `hyprctl configerrors` was empty. The repo's
pre-existing `50-caelestia-qml.conf` had the right pattern all along: plain
absolute paths, no specifiers.

### What it does now

`shells/omarchy/hyprland.lua` resolves the path itself and *injects* it:

1. `has_bootstrap(dir)` probes for `<dir>/default/hypr/bootstrap.lua`.
   `$OMARCHY_PATH` is used **only if it passes**; otherwise
   `~/.local/share/omarchy`. A set-but-wrong value can no longer win.
2. If neither passes, it `error()`s with "run scripts/setup-omarchy.sh" — because
   the alternative is a desktop that looks up but has almost no keybinds.
3. It prepends the checkout to `package.path` and replaces
   `package.loaded["default.hypr.paths"]` with the table upstream builds, field
   for field. Both must happen **after** the `dofile` of `bootstrap.lua`, which
   clears `package.loaded` for the `default.hypr` prefix on every reload, and
   which applies its own `/usr/share/omarchy` fallback independently.

Verified against `%h/...`, unset, empty, relative, and a real-but-wrong directory
— 216 binds in every case; missing checkout errors loudly.

There is **no `environment.d` file for omarchy, deliberately.** omarchy's own
`default/hypr/envs.lua` does the runtime half — `hl.env("OMARCHY_PATH", …)` plus
its `bin/` at the front of `PATH` for every client Hyprland spawns — so terminals
opened from the session get `omarchy-*` on `PATH` and **no relogin is needed**.
The only gap is a bare tty or ssh session that is not descended from Hyprland,
where `OMARCHY_PATH` is simply unset; nothing here needs it there.

## The Hyprland config is a loader

`dotfiles/hypr/shells/omarchy/hyprland.lua` is not a standalone config like
dms/noctalia/end4/end4pc. It runs omarchy's own config and layers on top:

```
bootstrap.lua          sets package.path to three roots:
                       ~/.local/state/?.lua, ~/.config/?.lua, $OMARCHY_PATH/?.lua
default.hypr.omarchy   helpers, autostart, bindings, envs, looknfeel, input,
                       windows, + require_optional omarchy.current.theme.hyprland
<house layer>          monitor, input, four binds (below)
default.hypr.toggles   runtime toggle state; must be last
```

### Trap: `~/.config/?.lua` is on package.path

That is this repo's **shared** `dotfiles/hypr/` directory, used by all seven
shells. omarchy's own user config does `require("hypr.bindings")`,
`require("hypr.monitors")` and so on — meaning if
`dotfiles/hypr/{monitors,input,bindings,looknfeel,autostart}.lua` ever exist,
they start loading. Do not create files with those names, and use `dofile`
rather than `require` for anything of ours.

### Trap: two binds on one combo both fire

omarchy binds nearly every `SUPER` combination. The house layer is deliberately
tiny for that reason, and every override `hl.unbind`s first:

| Combo | omarchy | here | why |
|---|---|---|---|
| `SUPER + SPACE` | omarchy menu | **unbound** | it is the us/ara layout toggle on every shell here (`grp:win_space_toggle`) |
| `SUPER + Super_L` | — | omarchy menu | where noctalia's launcher lives too |
| `SUPER + SHIFT + O` | Obsidian | shell switcher | the way out of the shell; every shell must have it |
| `SUPER + T` | float toggle | terminal | house alias |
| `SUPER + Q`, `+B`, `+E`, `+R` | free | close / brave / thunar / thunar | free combos, no unbind needed |

**Everything else stays omarchy's.** That is the point of loading its config at
all. Worth knowing, because it differs from the other six shells:

- `SUPER + W` closes the window (it opens zen elsewhere here)
- `SUPER + RETURN` opens a terminal via `omarchy-launch-terminal` →
  `xdg-terminal-exec`, which resolves from the XDG default, not from a
  hardcoded `wezterm-gui`
- input defaults come from omarchy's `input.lua`, which derives `kb_layout` from
  `/etc/vconsole.conf`; the house layer re-asserts `us,ara` and `ctrl:nocaps`
  after it

Check for accidental doubles with:

**`hyprctl binds -j` does not work here** — it emits invalid JSON whenever binds
carry descriptions (it shifts keys against values: `"keycode": XF86AudioRaiseVolume`
unquoted, `"allow_input_capture": Volume up`). omarchy sets a description on all
216 of its binds, so every `hyprctl binds -j | jq …` recipe fails under it. Parse
the plain-text output instead:

```bash
hyprctl binds | awk '
  /^bind/          { type=$0; mod=""; key="" }
  /^\tmodmask:/    { mod=$2 }
  /^\tkey:/        { line=$0; sub(/^\tkey: /,"",line); key=line }
  /^\tdispatcher:/ { print type"  modmask="mod"  key="key }
' | sort | uniq -d
```

Note the `key:` value must be taken whole — omarchy's workspace binds render as
`key: SUPER + code:10`, so splitting on whitespace collapses them all to `SUPER`
and reports six duplicates that do not exist.

**`ALT + TAB` and `ALT + SHIFT + TAB` legitimately appear in that output.**
omarchy binds each of them twice on purpose (`default/hypr/bindings/tiling.lua`
lines 44–47: cycle the window *and* bring it to the top), and both firing is the
intent. Anything else in the list is a real collision. Verified 2026-07-29: the
house layer adds none.

## Packages

The module installs runtime deps only — the shell is a checkout, not a package.
`aur/omarchy` is a placeholder stub, and omarchy's real packages live in its own
repo at `pkgs.omarchy.org`, which this machine does not add.

**`quickshell-git` is in omarchy's package list and deliberately not in the
module's.** The provider has exactly one owner
(`modules/shells-quickshell{,-git}.yaml`) — see
[../PACKAGE-CONFLICTS.md](../PACKAGE-CONFLICTS.md).

Also excluded, and why: the apps omarchy is opinionated about (chromium,
obsidian, libreoffice, nautilus, evince, imv, kdenlive, obs-studio, …), the
toolchains it preinstalls (docker, ruby, rust, mise, luarocks, dotnet), the
system decisions (sddm, plymouth, uwsm, hyprland itself — all already handled
here), and its own repo packages (`aether`, `omacut`, `omawrite`, `tensaku`,
`cliamp`, `tobi-try`, `omarchy-nvim`), which back entries in `omarchy-menu`
rather than the shell. If one of those turns out to be load-bearing for the bar,
record it here before adding it to the module.

## Health check

```bash
# checkout and version
git -C ~/.local/share/omarchy log -1 --oneline
cat ~/.local/share/omarchy/version

# the binds are the real health signal: 216, not 3.
hyprctl binds | grep -c '^bind'
hyprctl configerrors                     # empty when clean

# omarchy-* reachable from a terminal opened inside the session (this comes from
# omarchy's own envs.lua, NOT from environment.d — there is no file for it).
command -v omarchy-menu

# theme seeded
cat ~/.local/state/omarchy/current/theme.name
readlink ~/.local/state/omarchy/current/background

# the shell loads at all, without touching the session's active shell
timeout 10 env OMARCHY_PATH=~/.local/share/omarchy \
  PATH=~/.local/share/omarchy/bin:$PATH \
  quickshell -n -p ~/.local/share/omarchy/shell 2>&1 | grep 'Configuration Loaded'

# once active
hyprctl configerrors                     # empty when clean
pgrep -af "quickshell -n -p .*omarchy/shell"
```

Two warnings are normal on a dry run while another shell is active — the
notification server and the polkit agent are already registered by it. They go
away once omarchy is the only shell running.
