# dcli config — cachyos-desktop

Declarative system config managed with [dcli](https://gitlab.com/theblackdon) (v0.2.2):
packages, services, default apps, dotfiles, and bootstrap hooks for my
CachyOS + Hyprland setup running my **custom Caelestia shell fork**, with
**AMBXst**, **DankMaterialShell**, and **Noctalia** as alternate shells.

## What's in here

| Piece | Where | Notes |
|---|---|---|
| Host config | `hosts/cachyos-desktop.yaml` | enabled modules, services, default apps |
| Modules | `modules/*.yaml` | packages + dotfile mappings per area |
| Dotfiles | `dotfiles/` | synced to `~/.config/*` by `dcli sync` |
| Hooks | `scripts/setup-caelestia.sh`, `scripts/setup-ambxst.sh` | clone + install the two shells |
| Shell switcher | `scripts/switch-shell.sh` | switch between caelestia / ambxst / dms / noctalia / end4 |

### The custom Caelestia setup (important)

The `caelestia-shell` pacman package installs the *stock* shell into
`/etc/xdg/quickshell/caelestia`. My fork **overrides** it because quickshell
prefers the user path:

- `~/.local/share/my-caelestia` — **production** clone of [JASSIM-ALHUMAID/my-caelestia](https://github.com/JASSIM-ALHUMAID/my-caelestia); the session shell is built from here
- `~/.config/quickshell/caelestia` — the built fork QML (overrides `/etc/xdg`)
- `~/.config/caelestia` — symlink → `~/.local/share/my-caelestia/caelestia-configs` (live config writes land in prod)
- `~/Projects/shell/real` — **testing** checkout (optional, dev machines only); hack here, run with `run-worktree.fish`

`scripts/setup-caelestia.sh` (the caelestia module's post-install hook)
produces the production layout. Because `~/.config/caelestia` is a symlink
into the fork, the caelestia module deliberately has **no dotfiles entry** —
dcli must not replace that symlink.

`scripts/caelestia-sync.sh` (also on PATH as `caelestia-sync`) promotes
tested changes: it pulls live-edited configs prod → dev (so git commits in
dev include current state), deploys code dev → prod, and with `--install`
rebuilds + installs the shell from prod (restarts qs). `--dry-run` previews.

WezTerm config is mirrored in `dotfiles/wezterm/`; its own history lives at
[JASSIM-ALHUMAID/wezterm](https://github.com/JASSIM-ALHUMAID/wezterm).

### Shell switching

`~/.config/hypr/hyprland.conf` sources `shells/active.conf`, which points at
one of `shells/{caelestia,ambxst,dms,noctalia,end4}.conf`:

- **caelestia** / **ambxst** ship their own full hyprland configs and are
  sourced directly.
- **dms** / **noctalia** / **end4** don't, so each gets its own **standalone** config
  in `shells/dms/`, `shells/noctalia/`, and `shells/end4/` — seeded with my input/layout
  preferences and app binds, plus each shell's own IPC binds (launcher on
  Super+D — Super+Space is taken by the us/ara layout toggle). Edit each
  freely; they are fully independent of caelestia/ambxst and of each other.

**Noctalia runs on its own quickshell fork.** The `noctalia-shell` package
depends on `noctalia-qs`, which *Conflicts=quickshell* and would remove the
stock quickshell that caelestia and dms need. So `scripts/setup-noctalia.sh`
instead clones the noctalia QML to `~/.config/quickshell/noctalia-shell` and
extracts the `noctalia-qs` package (never pacman-installed, so no conflict)
to `~/.local/opt/noctalia-qs`, with a `~/.local/bin/noctalia` wrapper that
launches/IPCs noctalia using the fork binary.

**end-4's illogical-impulse** uses a quickshell config launched with
`qs -c ii`. The `illogical-impulse-quickshell-git` package likewise
*Conflicts=quickshell*, so `scripts/setup-end4.sh` runs the ii config on
stock quickshell with its extra qt6 deps installed separately, and symlinks
`~/.config/quickshell/ii` into the `~/.local/share/dots-hyprland` checkout.
Like noctalia, end4's upstream Hyprland config is Lua-based and assumes it
owns `~/.config/hypr`, so `shells/end4/` provides a standalone wrapper
config.

Switch with `scripts/switch-shell.sh <name>` — no argument opens a fuzzel
picker. The script kills every shell's processes, rewrites `active.conf`,
reloads hyprland, and launches the chosen shell. `active.conf` is committed,
so the last-used shell survives replication.

## New machine bootstrap

1. Install [dcli](https://gitlab.com/theblackdon) (build from source → `~/.local/bin/dcli`).
2. Clone this repo:
   ```sh
   git clone https://github.com/JASSIM-ALHUMAID/dcli-config.git ~/.config/dcli
   ```
3. Sync everything (installs packages, enables services, runs the module
   hooks — including `link-dotfiles.sh`, which symlinks `~/.config/<dir>` →
   `dotfiles/<dir>`; dcli's own YAML `dotfiles:` keys are ignored by dcli
   and kept as documentation):
   ```sh
   dcli sync
   ```
   Day-to-day updates after that: configs edit themselves in-repo through
   the symlinks, so publishing is just
   `cd ~/.config/dcli && git add -A && git commit -m "..." && git push`.
4. Log out and back in once so the shell env (`QML2_IMPORT_PATH`,
   `CAELESTIA_LIB_DIR`) applies, then pick a shell with
   `scripts/switch-shell.sh [caelestia|ambxst|dms|noctalia|end4]`.

AUR helper is `paru`; several packages (wezterm-nightly-bin, zen-browser-bin,
brave-nightly-bin, caelestia-*) come from AUR/chaotic.
