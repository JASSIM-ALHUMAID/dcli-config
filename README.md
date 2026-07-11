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
| Shell switcher | `scripts/switch-shell.sh` | switch between caelestia / ambxst / dms / noctalia |

### The custom Caelestia setup (important)

The `caelestia-shell` pacman package installs the *stock* shell into
`/etc/xdg/quickshell/caelestia`. My fork **overrides** it because quickshell
prefers the user path:

- `~/Projects/shell/real` — clone of [JASSIM-ALHUMAID/my-caelestia](https://github.com/JASSIM-ALHUMAID/my-caelestia) (source of truth)
- `~/.config/quickshell/caelestia` — the built fork QML (overrides `/etc/xdg`)
- `~/.config/caelestia` — symlink → `~/Projects/shell/real/caelestia-configs`

`scripts/setup-caelestia.sh` (the caelestia module's post-install hook)
produces exactly that layout. Because `~/.config/caelestia` is a symlink into
the fork, the caelestia module deliberately has **no dotfiles entry** — dcli
must not replace that symlink.

WezTerm config is mirrored in `dotfiles/wezterm/`; its own history lives at
[JASSIM-ALHUMAID/wezterm](https://github.com/JASSIM-ALHUMAID/wezterm).

### Shell switching

`~/.config/hypr/hyprland.conf` sources `shells/active.conf`, which points at
one of `shells/{caelestia,ambxst,dms,noctalia}.conf`:

- **caelestia** / **ambxst** ship their own full hyprland configs and are
  sourced directly.
- **dms** / **noctalia** don't, so their confs reuse caelestia's hyprland
  base (env, input, binds, my `hypr-user.conf`) plus an `exec-once` for the
  shell and replacement binds for launcher/lock (the caelestia-IPC binds in
  the base are no-ops when caelestia isn't running).

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
3. Sync everything (installs packages, symlinks `dotfiles/` into `~/.config`,
   enables services, runs the caelestia/ambxst hooks):
   ```sh
   dcli sync --force-dotfiles
   ```
4. Log out and back in once so the shell env (`QML2_IMPORT_PATH`,
   `CAELESTIA_LIB_DIR`) applies, then pick a shell with
   `scripts/switch-shell.sh [caelestia|ambxst]`.

AUR helper is `paru`; several packages (wezterm-nightly-bin, zen-browser-bin,
brave-nightly-bin, caelestia-*) come from AUR/chaotic.
