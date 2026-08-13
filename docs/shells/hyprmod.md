# HyprMod — per-shell Hyprland settings GUI

[HyprMod](https://github.com/BlueManCZ/hyprmod) (GTK4, `yay -S hyprmod`) edits
Hyprland options, binds, rules, monitors and animations through a schema-driven
GUI. Stock HyprMod owns exactly **one** managed file for the whole machine —
useless here, where nine shells each carry their own Hyprland config. The
integration below gives every shell its own isolated HyprMod file.

**Always launch it through `scripts/edit-hypr.sh`, never bare `hyprmod`.**

## Mechanism

```
scripts/edit-hypr.sh [shell]          (no argument = active shell)
  │ 1. seeds ~/.config/hypr/shells/<name>/hyprmod.lua if missing
  │ 2. dconf write /io/github/bluemancz/hyprmod/config-path → that file
  │ 3. launches hyprmod with DCLI_HYPRMOD_SHELL=<name>
  ▼
hyprmod  ──reads/writes──►  shells/<name>/hyprmod.lua
  ▲                                 ▲
  │ executes hyprland.lua to map    │ require()'d LAST by hyprland.lua,
  │ the config tree (external       │ so GUI edits override the shell
  │ entries, setup check)           │ config AND shells/<name>-overrides.lua
```

- The managed file is `dotfiles/hypr/shells/<name>/hyprmod.lua` — a naming
  convention, no registry arrays to keep in sync. It is committed like any
  other dotfile; expect git churn after saving in the GUI.
- `DCLI_HYPRMOD_SHELL` is set only in hyprmod's process environment.
  `hyprland.lua` honors it (validated against `shell_paths`), so hyprmod's
  config reader evaluates the *target* shell's whole tree even when another
  shell is active: hand-written binds/settings show up read-only with correct
  file attribution, and overriding one writes `unbind` + `bind` (or the
  option) into the managed file.
- Load order in `hyprland.lua`: shell config → `<name>-overrides.lua` →
  `<name>/hyprmod.lua`. The GUI file is the "what I clicked most recently"
  layer; if a hand fix must beat a stale GUI value, delete the value from the
  GUI file (both are visible in git).

## The big caveat: no live preview

This setup is all-Lua, and **under a Lua config `hyprctl keyword` is rejected
outright** (`keyword can't work with non-legacy parsers` — and it exits 0, so
HyprMod believes the change applied). HyprMod's apply-as-you-click therefore
does nothing here. Changes take effect on **Ctrl+S**: Hyprland's autoreload
tracks `require()`'d files, so saving applies; if it doesn't, `hyprctl reload`
by hand.

## Other caveats

- **Never launch bare `hyprmod`.** Its setup check runs against whichever
  shell is active and, if it can't see the managed file, shows an onboarding
  dialog. Click **Cancel** — clicking through appends a *global*
  `require("hyprland-gui")` to `hyprland.lua` (one shared file for all nine
  shells; that already happened once and was reverted). Damage is a visible
  3-line git diff on `dotfiles/hypr/hyprland.lua`.
- **Never change the config path from HyprMod's own Settings page.** That
  calls its migration routine, which *moves* the file and rewrites
  `hyprland.lua`. Retargeting is `edit-hypr.sh`'s job.
- **Switching shells while HyprMod is open**: the window stays pinned to its
  launch-time shell and keeps writing to that shell's file. Close it and
  re-run the wrapper. It is single-instance — a second launch just raises the
  existing window, so the wrapper refuses when one is running (`--force`
  quits it, discarding unsaved changes).
- **Editing a non-active shell** (`edit-hypr.sh dms` while on noctalia): reads
  and saved files are correctly per-shell, but HyprMod's launch fires one
  `hyprctl reload` of the *running* session. The wrapper re-enters the
  `global` submap afterwards (same dance as `switch-shell.sh`).
- **Profiles** (`~/.config/hypr/hyprmod/profiles/`) are global across shells —
  restoring one writes that snapshot into whichever shell's file is currently
  targeted. Treat them as deliberate cross-shell presets, or avoid them.
