# Hyprland Lua Migration Summary — 2026-07-23

## What changed

### Entry point: `.conf` → `.lua`

**Before:** Hyprland loaded `~/.config/hypr/hyprland.conf` (hyprlang syntax). Shell switching worked by sourcing `active.conf` → `shells/<name>.conf` → shell-specific config files. Problem: upstream caelestia switched to Lua format, and Hyprland can't mix `.conf` and `.lua`.

**After:** Hyprland loads `~/.config/hypr/hyprland.lua`. It reads `active.conf`, extracts the shell name, and `dofile()`s the matching shell's Lua config. No `.conf` sourcing involved.

**Why:** Hyprland 0.55+ loads either `hyprland.conf` OR `hyprland.lua` — never both. The old `.conf` chain broke when upstream deleted their `.conf` files. Going fully Lua eliminates the format lock problem permanently.

### Shell configs: `.conf` → `.lua`

Each shell now has a self-contained Lua config using `hl.config()`, `hl.bind()`, `hl.window_rule()`, etc.:

| Shell | Config | Source |
|---|---|---|
| Caelestia | `~/.local/share/caelestia/hypr/hyprland.lua` | Upstream (already Lua) |
| AMBXst | `~/.local/share/ambxst/hyprland.lua` | Upstream (already Lua) |
| DMS | `~/.config/hypr/shells/dms/hyprland.lua` | Converted from `.conf` |
| Noctalia | `~/.config/hypr/shells/noctalia/hyprland.lua` | Converted from `.conf` |
| end4 | `~/.config/hypr/shells/end4/hyprland.lua` | Converted from `.conf` |

**Why:** The old DMS/Noctalia/end4 configs were ~120 lines each across 10+ `.conf` files with hyprlang syntax. The Lua versions are single files using the same `hl.*` API that upstream uses, making them consistent and easier to maintain.

### Caelestia overrides: `.conf` → `.lua`

| File | Purpose |
|---|---|
| `~/.config/caelestia/hypr-vars.lua` | Variable overrides (terminal=wezterm, editor=zeditor, cursor, keybinds) |
| `~/.config/caelestia/hypr-user.lua` | Section overrides (layout=scrolling, input=us,ara, env vars, launcher keybind) |

**Why:** The production clone's `hyprland.lua` does `require("hypr-vars")` and `require("hypr-user")` from `~/.config/caelestia/`. These must be `.lua` files (not `.conf`) for the require to work.

### switch-shell.sh updated

- Validates `.lua` files instead of `.conf` before switching
- `current_shell()` strips both `.conf` and `.lua` extensions from `active.conf`

### Dead `.conf` files removed

- `hyprland.conf` (old entry point)
- `shells/dms.conf`, `shells/noctalia.conf`, `shells/end4.conf`, `shells/ambxst.conf` (old dispatchers)
- `shells/*/hyprland/` directories (old section files)
- `shells/*/variables.conf`, `shells/*/scheme/` (old variables/colors)
- `shells/caelestia/` (entire directory — caelestia uses production clone now)
- `ambxst-overrides.conf`, `scheme/current.conf`, `dms/` directory

**Remaining `.conf` files:** `active.conf` (read by Lua entry point), `hyprlock/colors.conf` (unrelated).

### Shell migrations (ambxst, end4)

Both fork repos were updated to latest upstream while preserving local customizations:
- AMBXst: 6 commits behind, 18 local commits preserved (wallpaper transitions, lockscreen styles)
- end4: 5 commits behind, 15 local commits preserved (wallpaper transitions, video support)
- Backup branches: `backup-pre-migration-2026-07-23` on both repos

## Config loading chain (after)

```
~/.config/hypr/hyprland.lua
  └─ reads shells/active.conf → "caelestia"
       └─ dofile(~/.local/share/caelestia/hypr/hyprland.lua)
            ├─ require("variables")     ← base variables
            ├─ require("hypr-vars")     ← your overrides (hypr-vars.lua)
            ├─ require("hyprland.keybinds") ← base keybinds
            └─ require("hypr-user")     ← your overrides (hypr-user.lua)
```

## Files created/modified

| File | Action |
|---|---|
| `dotfiles/hypr/hyprland.lua` | Created — entry point |
| `dotfiles/hypr/shells/dms/hyprland.lua` | Created — DMS config |
| `dotfiles/hypr/shells/noctalia/hyprland.lua` | Created — Noctalia config |
| `dotfiles/hypr/shells/end4/hyprland.lua` | Created — end4 config |
| `~/.config/caelestia/hypr-vars.lua` | Created — variable overrides |
| `~/.config/caelestia/hypr-user.lua` | Created — section/keybind overrides |
| `scripts/switch-shell.sh` | Modified — check .lua, parse both extensions |

## Post-migration fixes (same day)

The first boot after the migration failed with `module 'variables' not found` at
`~/.local/share/caelestia/hypr/hyprland.lua:47`. Six defects came out of that:

1. **`package.path` must include the shell's own directory.** Hyprland only puts the *main*
   config's directory (`~/.config/hypr`) on `package.path`, so a `dofile()`d config's
   `require("variables")` / `require("hyprland.env")` / `require("utils.functions")` cannot
   resolve. The entry point now appends `<shell dir>/?.lua` and `<shell dir>/?/init.lua` before
   the `dofile`, after `~/.config/hypr` so the CLI-written `scheme/current.lua` still wins.
2. **`scheme/current.lua` had to be seeded.** `variables.lua` requires `scheme.current`.
   Upstream's `maybe_copy` seeds it from `~/.config/hypr/scheme/default.lua`, which doesn't
   exist in our split layout (and Lua can't `mkdir`). The entry point now creates
   `~/.config/hypr/scheme/` and copies the shell's `scheme/default.lua` on first run;
   `caelestia scheme set` overwrites it from then on (`utils/theme.py:147`).
3. **The entry point read only line 1 of `active.conf`**, which is the `# Written by ...`
   comment — so every boot silently fell back to caelestia regardless of the selected shell.
   It now scans for the first non-comment line and accepts the legacy `source =` form.
4. **`switch-shell.sh` validated `shells/<name>.lua`**, a path that exists for no shell, so
   every invocation aborted. It now uses a `config_path()` helper mirroring the entry point's
   map. `active.conf` is written as a bare shell name.
5. **Overrides lost with the deleted `.conf` files were restored**:
   `QT_FFMPEG_DECODING_HW_DEVICE_TYPES=none` (from `shells/caelestia.conf`) went into
   `hypr-user.lua`, and `ambxst-overrides.conf` was ported to `shells/ambxst-overrides.lua`
   (monitor, scrolling widths, `us,ara` input, gestures, workspaces animation).
6. **Two conversion errors in the hand-written Lua**: `explicit_column_widths` takes a string
   (`"0.35, 0.5, ..."`), not a table — upstream `hyprland/general.lua:32` is the reference; and
   `hl.animation` requires a `bezier` (or spring), so dms/noctalia/end4 now register
   `hl.curve("standard", ...)` first.

All five shells were verified to load with `hyprctl configerrors` empty.

### IPC changes under a Lua config (found 2026-07-24)

`hyprctl keyword ...` is rejected outright ("keyword can't work with non-legacy parsers. Use
eval.") and `hyprctl dispatch <name> <args>` no longer parses — dispatchers take Lua syntax:

| Legacy | Lua config |
|---|---|
| `hyprctl keyword monitor ", preferred, auto, 1"` | `hyprctl eval 'hl.monitor({ ... })'` |
| `hyprctl dispatch submap global` | `hyprctl dispatch 'hl.dsp.submap("global")'` |
| `hyprctl keyword bind ...` | `hyprctl eval 'hl.bind("SUPER + B", hl.dsp.exec_cmd("..."))'` |

`switch-shell.sh` was updated for the first two. **Still broken:** the fork's
`services/KeybindApplier.qml` applies `~/.config/caelestia/keybinds.json` via `keyword
bind`/`keyword unbind`, so none of those user binds are live — `hyprctl binds` shows only the
141 static Lua binds, no Super+B, Super+Return or Super+Shift+O. It needs porting to
`hl.bind`/`hl.unbind` (both verified working over `hyprctl eval`).

### Caelestia shell wouldn't start

`qs -c caelestia` died with `IdleMonitors.qml: LogindManager is not a type`. `LogindManager`
only exists in the fork's plugin under `~/.local/lib/qt6/qml`; the packaged one in
`/usr/lib/qt6/qml/Caelestia` lacks it. `QML2_IMPORT_PATH` is declared in `hypr-user.lua`, but
hyprland applies `env` only at **startup** — and the boot where the Lua config failed never got
that far, so nothing in the session had it. `switch-shell.sh` now sets `QML2_IMPORT_PATH` and
`CAELESTIA_LIB_DIR` on the launch itself, so a switch works without a relogin.

### Monitor scale

dms/noctalia/end4 lost `monitor = , preferred, auto, 1` in the conversion and were falling back
to hyprland's auto scale. All five shells now set `hl.monitor({ ..., scale = 1 })` — caelestia
and ambxst in their own configs, the other three in theirs.

## After reboot

1. Hyprland will load `hyprland.lua` (no `.conf` exists to trigger hyprlang mode)
2. Caelestia should work with scrolling layout, us,ara keyboard, wezterm
3. Test switching: `~/.config/dcli/scripts/switch-shell.sh dms` → restart → DMS loads
4. If any shell doesn't load, check `~/.config/hypr/shells/active.conf` has the right shell name
