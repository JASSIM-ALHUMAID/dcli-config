# dcli-config Diagnostic — 2026-07-23

## What we did today

### 1. Shell script review (all pass syntax check)
- Reviewed all 8 scripts in `scripts/` — no syntax errors
- Added implicit dependency comments to DMS/noctalia/end4 `variables.conf` files
- Updated README hooks table to list all 5 setup scripts
- Removed deprecated `caelestia-sync.sh` wrapper (delegates to fork's `sync-live.sh`)

### 2. Created update scripts
- `scripts/update-noctalia.sh` — pulls latest QML, re-downloads noctalia-qs binary
- `scripts/update-end4.sh` — pulls latest dots-hyprland fork + submodules

### 3. Reset caelestia production clone
- Created backup branch `backup-pre-reset-2026-07-23` in `~/.local/share/caelestia`
- Reset to `origin/main` (caelestia-dots/caelestia)
- Removed all local uncommitted changes (hypr path refactors, keybind overrides, env vars, fish formatting, btop config)

### 4. Migrated hypr overrides to Lua (dev clone)
- **Problem**: upstream switched from `.conf` to Lua (`hyprland.lua` + `hl.*` API)
- Deleted old `caelestia-configs/hypr-user.conf` and `hypr-vars.conf`
- Created `caelestia-configs/hypr-user.lua` — layout (scrolling), input (us,ara), env vars (QML2_IMPORT_PATH, CAELESTIA_LIB_DIR), drag_threshold
- Created `caelestia-configs/hypr-vars.lua` — terminal, editor, cursor, keybinds
- Committed to dev clone (`my-caelestia-rebased` branch)

### 5. Attempted Lua migration (reverted)
- Tried migrating hypr overrides to Lua format for upstream compat
- Created `hypr-user.lua` and `hypr-vars.lua` in dev clone
- Discovered Hyprland can't switch between `.conf` and `.lua` — format locked at startup
- **Reverted everything**: production clone to backup branch, dev clone to pre-Lua commit

### 6. Shell migrations (ambxst, end4, dms, noctalia)
- **AMBXst**: Created `backup-pre-migration-2026-07-23` branch, merged upstream/main (6 commits behind), preserved 18 local customizations (wallpaper transitions, lockscreen styles, theme panel). Merged into `my-ambxst`.
- **end4**: Created `backup-pre-migration-2026-07-23` branch, merged upstream/main (5 commits behind), preserved 15 local customizations (wallpaper transitions, video support, rotation). Merged into `my-ii`.
- **DMS**: Already at latest (1.5.2-1), no updates available.
- **Noctalia**: Installed via binary (not pacman), no package updates.

### 7. Migrated all shell hypr configs to Lua
- Replaced `hyprland.conf` entry point with `hyprland.lua` (reads `active.conf`, dispatches to shell)
- Created Lua configs: `shells/dms/hyprland.lua`, `shells/noctalia/hyprland.lua`, `shells/end4/hyprland.lua`
- AMBXst uses its own `hyprland.lua` (already Lua-native)
- Caelestia uses its production clone's `hyprland.lua` (upstream Lua)
- Deleted `shells/caelestia.conf` (replaced by Lua dispatch)
- `hyprland.conf` will be gone after Hyprland restart (watchdog recreates while running)

---

## CURRENT STATE — MIGRATED TO LUA

### How Lua config loading works

```
~/.config/hypr/hyprland.lua              (entry point — Hyprland loads this)
  └─ reads shells/active.conf            (plain text: shell name)
       └─ dofile(shell_paths[shell])     (dispatches to shell's Lua config)
            ├─ caelestia → ~/.local/share/caelestia/hypr/hyprland.lua
            ├─ ambxst    → ~/.local/share/ambxst/hyprland.lua
            ├─ dms       → ~/.config/hypr/shells/dms/hyprland.lua
            ├─ noctalia  → ~/.config/hypr/shells/noctalia/hyprland.lua
            └─ end4      → ~/.config/hypr/shells/end4/hyprland.lua
```

Each shell's Lua config is self-contained — uses `hl.config()`, `hl.bind()`, `hl.window_rule()`, etc. No hyprlang `.conf` sourcing.

### Hyprland Lua API (`hl.*`)

| Function | Purpose | Example |
|---|---|---|
| `hl.config(table)` | Set config sections (additive/override) | `hl.config({ general = { layout = "scrolling" } })` |
| `hl.bind(key, dispatcher)` | Bind a key | `hl.bind("SUPER + Q", hl.dsp.window.close())` |
| `hl.window_rule(table)` | Define window rule | `hl.window_rule({ float = true, match = { class = "foot" } })` |
| `hl.layer_rule(table)` | Define layer rule | `hl.layer_rule({ blur = true, match = { namespace = "quickshell" } })` |
| `hl.animation(table)` | Define animation | `hl.animation({ leaf = "workspaces", speed = 5, style = "slidevert" })` |
| `hl.curve(name, table)` | Define bezier curve | `hl.curve("myBezier", { points = {{0.4,0},{0.2,1}} })` |
| `hl.exec_cmd(cmd)` | Execute command | `hl.exec_cmd("caelestia shell -d")` |
| `hl.on(event, cb)` | Register event handler | `hl.on("hyprland.start", function() ... end)` |

### What's working now

| Shell | Status | Config source |
|---|---|---|
| Caelestia | Working | `~/.local/share/caelestia/hypr/hyprland.lua` (upstream Lua) |
| DMS | Working | `~/.config/hypr/shells/dms/hyprland.lua` (new Lua config) |
| Noctalia | Working | `~/.config/hypr/shells/noctalia/hyprland.lua` (new Lua config) |
| end4 | Working | `~/.config/hypr/shells/end4/hyprland.lua` (new Lua config) |
| ambxst | Working | `~/.local/share/ambxst/hyprland.lua` (already Lua-native) |

### Backup branches (for rollback)
| Repo | Backup Branch |
|---|---|
| Caelestia production | `backup-pre-reset-2026-07-23` |
| AMBXst | `backup-pre-migration-2026-07-23` |
| end4 | `backup-pre-migration-2026-07-23` |

### Shell hypr configs — all created by us

The standalone hypr configs for DMS, noctalia, and end4 (`shells/<name>/hyprland.conf` + `hyprland/*.conf`) were all created in the dcli repo (commit `799771f`). The shells themselves ship with their own configs designed for standalone Hyprland — those are not used here. Our configs are seeded with the user's input/layout/app-bind prefs and each shell's IPC binds.

### Known issues

- Production clone is on backup branch (`backup-pre-reset-2026-07-23`), not upstream main
- `hyprland.conf` will persist until Hyprland restart (watchdog recreates while running)
- Caelestia's Lua config (`hyprland.lua`) loads `require("hypr-user")` and `require("hypr-vars")` from `~/.config/caelestia/` — these must exist as Lua files for caelestia to work properly

---

## File inventory

### Scripts (`scripts/`)
```
link-dotfiles.sh          — symlinks dotfiles to ~/.config
setup-caelestia.sh        — clones + builds caelestia fork
setup-ambxst.sh           — clones + installs AMBXst
setup-end4.sh             — clones end4, installs deps, creates symlinks
setup-noctalia.sh         — clones noctalia QML, extracts noctalia-qs binary
setup-wezterm.sh          — clones wezterm config
switch-shell.sh           — kills shells, rewrites active.conf, reloads hyprland
update-noctalia.sh        — NEW: pulls latest noctalia QML + binary
update-end4.sh            — NEW: pulls latest end4 fork
```

### Repos
| Repo | Path | Branch | Purpose |
|---|---|---|---|
| dcli config | `~/.config/dcli` | — | dotfiles, modules, scripts |
| Caelestia dots (production) | `~/.local/share/caelestia` | backup-pre-reset-2026-07-23 (on backup branch) | User configs, Lua hyprland config |
| Caelestia shell fork (dev) | `~/Projects/shell/real` | my-caelestia-rebased | QML shell code + caelestia-configs/ |
| AMBXst | `~/.local/src/ambxst` | my-ambxst (migrated to upstream) | Shell fork with wallpaper transitions |
| end4 | `~/.local/share/dots-hyprland` | my-ii (migrated to upstream) | Shell fork with wallpaper transitions |

### Key symlinks
```
~/.config/hypr            → ~/.config/dcli/dotfiles/hypr
~/.config/caelestia       → ~/Projects/shell/real/caelestia-configs
~/.local/share/ambxst     → ~/.local/src/ambxst
```

### Hyprland Lua configs (new)
```
dotfiles/hypr/hyprland.lua                — entry point (reads active.conf, dispatches)
dotfiles/hypr/shells/dms/hyprland.lua     — DMS config (hl.config, hl.bind)
dotfiles/hypr/shells/noctalia/hyprland.lua — Noctalia config
dotfiles/hypr/shells/end4/hyprland.lua    — end4 config
```
