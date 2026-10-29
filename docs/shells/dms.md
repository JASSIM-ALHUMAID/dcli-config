# dms (Dux Shell, ex-DankMaterialShell)

The only shell here with **no fork and no build step** — fully packaged, so it is
the lowest maintenance. When something breaks across the board, it is the useful
control case: if the packaged shell also fails, the problem is the provider, Qt or
Hyprland, not a fork.

On 2026-10-30 the `dms-shell` package was replaced by **`dux-shell` 2.0.0**
([duxlabs-dev/dux-shell](https://github.com/duxlabs-dev/dux-shell)): it Provides
`dms-shell`, Conflicts with and Replaces `dms-shell` / `dms-shell-hyprland` /
`dms-shell-niri`. The CLI is still `dms` (`run`, `kill`, `ipc`, `doctor`, …) and the
config is still `~/.config/DankMaterialShell`, so the module keeps the name
`shell-dms` and this page keeps the name `dms`.

| | |
|---|---|
| Module | `modules/shell-dms.yaml` |
| Packages | `dux-shell` (depends on `accountsservice` and plain `quickshell`). `dgop` is gone from the repos; `dux-gop` Provides it and arrived as a dependency |
| Launch | `dms run` |
| Config | `~/.config/DankMaterialShell` -> `dotfiles/DankMaterialShell` (dcli-managed) |
| Hyprland | `dotfiles/hypr/shells/dms/hyprland.lua` (standalone: `common.*` plus `shells.dms.hyprland.{env,execs,keybinds}`; colours from the shared `~/.config/hypr/dms/colors.lua`, which DMS writes) |
| Setup hook | none |

## The packaged systemd unit must stay disabled

`dux-shell` ships `/usr/lib/systemd/user/dms.service`. `switch-shell.sh` owns start
and stop (`dms run` / `dms kill`); an enabled unit would start DMS under every other
shell as well. `scripts/doctor.sh` warns if the unit is enabled. Check with
`systemctl --user is-enabled dms.service` (expect `disabled`).

## Provider dependency

`dux-shell` depends on plain `quickshell`. Because `quickshell-git` declares
`Provides=quickshell`, that is satisfied under **either** provider module — no
changes needed when swapping. This is the fact that makes the two-provider
arrangement work; see [README.md](README.md).

## IPC

`dms ipc call <object> <method>` — dms **kept** the `ipc call` form that noctalia
dropped in v5. Binds in `dotfiles/hypr/shells/dms/hyprland/keybinds.lua`:

| Bind | Command |
|---|---|
| `SUPER` (tap) / `SUPER + D` | `spotlight toggle` |
| `SUPER + V` | `clipboard toggle` |
| `SUPER + N` | `notifications toggle` |
| `SUPER + I` | `settings toggle` |
| `SUPER + Escape` | `powermenu toggle` |
| `SUPER + ALT + L` | `lock lock` |

It also has a real `dms kill`, which `switch-shell.sh` uses for a graceful stop
(`quit_dms`) before falling back to `pkill -f "dms run"` (`MATCH_SPECS[dms]`).
(Contrast noctalia v5, which has no `kill` at all.)

## Notes

- `exec-once` does not re-fire on `hyprctl reload`, so `switch-shell.sh` starts it
  (`launch_dms`), guarded by the first `MATCH_SPECS` line.
- A `GeoClue2 unavailable: The name is not activatable` warning at startup is normal
  here (no geoclue provider configured) and harmless.
- DMS's matugen writes `foot/dank-colors.ini` into the shared, dcli-owned
  `~/.config/foot`, which is why foot and btop config are dotfiles here and not
  caelestia's.

## Health check

```bash
scripts/doctor.sh                          # includes the dms.service check
pacman -Q dux-shell
readlink -f ~/.config/DankMaterialShell    # -> dcli/dotfiles/DankMaterialShell
dms run 2>&1 | grep -E "Configuration Loaded|FATAL|ERROR"
```
