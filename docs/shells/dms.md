# dms (DankMaterialShell)

The only shell here with **no fork and no build step** — fully packaged, so it is
by far the lowest maintenance. When something breaks across the board, dms is the
useful control case: if dms also fails, the problem is the provider or Hyprland,
not a fork.

| | |
|---|---|
| Module | `modules/shell-dms.yaml` |
| Packages | `dms-shell`, `dgop` (+ `dms-shell-hyprland` pulled in as the compositor backend) |
| Launch | `dms run` |
| Config | `~/.config/DankMaterialShell` → `dotfiles/DankMaterialShell` (dcli-managed) |
| Hyprland | `dotfiles/hypr/shells/dms/hyprland.lua` (standalone, in this repo) |
| Setup hook | none |

## Provider dependency

`dms-shell` depends on plain `quickshell`:

```
Depends On : dgop  accountsservice  quickshell  dms-shell-compositor
```

Because `quickshell-git` declares `Provides=quickshell`, that dependency is
satisfied under **either** provider module — no changes needed when swapping. This
is the fact that makes the whole two-provider arrangement work; see
[README.md](README.md).

`dms-shell-hyprland` provides the `dms-shell-compositor` virtual dependency.

## IPC

`dms ipc call <object> <method>` — note dms **kept** the `ipc call` form that
noctalia dropped in v5. Binds in `dotfiles/hypr/shells/dms/hyprland.lua`:

| Bind | Command |
|---|---|
| `SUPER` (tap) / `SUPER + D` | `spotlight toggle` |
| `SUPER + V` | `clipboard toggle` |
| `SUPER + N` | `notifications toggle` |
| `SUPER + I` | `settings toggle` |
| `SUPER + Escape` | `powermenu toggle` |
| `SUPER + ALT + L` | `lock lock` |

It also has a real `dms kill`, which `switch-shell.sh` uses for a graceful stop
before falling back to `pkill -f "dms run"`. (Contrast noctalia v5, which has no
`kill` at all.)

## Notes

- Launched per-session from its Hyprland Lua via `exec-once`, but `exec-once` does
  not re-fire on `hyprctl reload`, so `switch-shell.sh` starts it too — guarded by
  `pgrep -f "dms run"`.
- `dgop` is dms's system-metrics helper and is declared explicitly so dcli tracks
  it rather than leaving it an implicit dependency.
- A `GeoClue2 unavailable: The name is not activatable` warning at startup is
  normal here (no geoclue provider configured) and harmless.
- Both `repo` and `extra` carry `dms-shell` at the same version; the `repo`
  one lists `dms-shell-compositor` in its depends, the `extra` one lists
  `quickshell` directly. Either resolves fine.

## Health check

```bash
pacman -Q dms-shell dgop dms-shell-hyprland
readlink -f ~/.config/DankMaterialShell    # -> dcli/dotfiles/DankMaterialShell
dms run 2>&1 | grep -E "Configuration Loaded|FATAL|ERROR"
```
