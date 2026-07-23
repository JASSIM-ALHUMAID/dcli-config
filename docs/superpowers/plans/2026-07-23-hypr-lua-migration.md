# Hyprland Lua Config Migration Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate all shell hypr configs from hyprlang `.conf` to Hyprland 0.55+ native Lua (`hl.*` API), enabling full compatibility with upstream caelestia and eliminating the `.conf`/`.lua` format lock constraint.

**Architecture:** Replace `~/.config/hypr/hyprland.conf` with `hyprland.lua` as the entry point. The Lua entry reads `active.conf`, then `dofile()`s the matching shell's Lua config. Each shell gets a dedicated Lua file using `hl.config()`, `hl.bind()`, `hl.window_rule()`, etc. Caelestia uses its production clone's existing `hyprland.lua`. Other shells get new Lua configs converted from their `.conf` counterparts.

**Tech Stack:** Hyprland 0.55+ Lua config API (`hl.*`), Lua 5.4+

---

## Global Constraints

- Hyprland loads EITHER `hyprland.conf` OR `hyprland.lua` — never both
- `hl.config()` is additive — multiple calls merge/override
- `hl.bind()` key format: `"MODIFIER + KEY"` (uppercase modifiers: SUPER, SHIFT, CTRL, ALT)
- `active.conf` is a plain text file containing just the shell name (e.g., `caelestia`)
- Production caelestia clone at `~/.local/share/caelestia` already has `hypr/hyprland.lua`
- AMBXst already has `~/.local/share/ambxst/hyprland.lua` (full Lua config)

---

## File Structure

### Entry point (replaces `hyprland.conf`)
- `~/.config/hypr/hyprland.lua` — reads `active.conf`, dispatches to shell

### Shell configs (new Lua files)
- `~/.config/hypr/shells/dms/hyprland.lua` — DMS Lua config
- `~/.config/hypr/shells/noctalia/hyprland.lua` — Noctalia Lua config
- `~/.config/hypr/shells/end4/hyprland.lua` — end4 Lua config

### Modified files
- `~/.config/dcli/scripts/switch-shell.sh` — no changes needed (writes `active.conf` which is shell-name only)
- `~/.config/hypr/shells/caelestia.conf` — DELETE (replaced by Lua dispatch)
- `~/.config/hypr/shells/active.conf` — no changes needed (plain text)

### Files to keep (still useful)
- All `variables.conf` files — kept for reference, Lua configs embed values directly
- All `hyprland/*.conf` files — kept for reference, Lua configs are self-contained

---

## Task 1: Create Lua entry point

**Files:**
- Create: `~/.config/hypr/hyprland.lua`
- Delete: `~/.config/hypr/hyprland.conf`

**Interfaces:**
- Consumes: `~/.config/hypr/shells/active.conf` (plain text, one line: shell name)
- Produces: Loads shell-specific Lua config via `dofile()`

- [ ] **Step 1: Create the Lua entry point**

```lua
-- ~/.config/hypr/hyprland.lua
-- Hyprland Lua config entry point — reads active.conf and dispatches

local function read_active_shell()
    local f = io.open(os.getenv("HOME") .. "/.config/hypr/shells/active.conf", "r")
    if not f then return "caelestia" end
    local content = f:read("*l")
    f:close()
    -- strip "source = " prefix if present (compat with old format)
    content = content:gsub("^source%s*=%s*", ""):gsub("^.-shells/", ""):gsub("%.conf$", ""):gsub("%.lua$", "")
    return content or "caelestia"
end

local shell = read_active_shell()
local home = os.getenv("HOME")

local shell_paths = {
    caelestia = home .. "/.local/share/caelestia/hypr/hyprland.lua",
    ambxst    = home .. "/.local/share/ambxst/hyprland.lua",
    dms       = home .. "/.config/hypr/shells/dms/hyprland.lua",
    noctalia  = home .. "/.config/hypr/shells/noctalia/hyprland.lua",
    end4      = home .. "/.config/hypr/shells/end4/hyprland.lua",
}

local path = shell_paths[shell]
if path then
    dofile(path)
else
    -- fallback: try caelestia
    dofile(shell_paths["caelestia"])
end
```

- [ ] **Step 2: Remove old hyprland.conf**

```bash
rm ~/.config/hypr/hyprland.conf
```

- [ ] **Step 3: Verify entry point loads**

```bash
cat ~/.config/hypr/shells/active.conf
# Should show: source = ~/.config/hypr/shells/caelestia.conf
lua -e "
local f = io.open(os.getenv('HOME') .. '/.config/hypr/shells/active.conf', 'r')
local content = f:read('*l')
f:close()
content = content:gsub('^source%s*=%s*', ''):gsub('^.-.shells/', ''):gsub('%.conf$', ''):gsub('%.lua$', '')
print('Shell: ' .. content)
"
# Expected: Shell: caelestia
```

- [ ] **Step 4: Commit**

```bash
cd ~/.config/dcli
git add -A
git commit -m "feat: migrate hypr entry point to Lua"
```

---

## Task 2: Create DMS Lua config

**Files:**
- Create: `~/.config/hypr/shells/dms/hyprland.lua`

**Interfaces:**
- Consumes: nothing (self-contained)
- Produces: Full DMS hyprland config via `hl.config()`, `hl.bind()`, `hl.window_rule()`

- [ ] **Step 1: Create DMS Lua config**

```lua
-- ~/.config/hypr/shells/dms/hyprland.lua
-- DMS (DankMaterialShell) — Hyprland Lua config

-- App variables
local terminal    = "wezterm-gui"
local browser     = "brave-browser-nightly"
local editor      = "codium"
local fileExplorer = "thunar"
local dmsCmd      = "dms ipc call"

-- Input
local sensitivity  = 0.3
local accelProfile = "flat"
local kbLayout     = "us,ara"
local kbOptions    = "grp:win_space_toggle, ctrl:nocaps"

-- Gaps
local gapsIn     = 4
local gapsOut    = 8
local borderSize = 2

-- Decoration
local rounding    = 12
local blurEnabled = true

-- Env vars
hl.config({
    env = {
        { "GDK_BACKEND", "wayland,x11" },
        { "QT_QPA_PLATFORM", "wayland;xcb" },
        { "SDL_VIDEODRIVER", "wayland,x11,windows" },
        { "CLUTTER_BACKEND", "wayland" },
        { "ELECTRON_OZONE_PLATFORM_HINT", "auto" },
        { "XDG_CURRENT_DESKTOP", "Hyprland" },
        { "XDG_SESSION_TYPE", "wayland" },
        { "XDG_SESSION_DESKTOP", "Hyprland" },
    },
})

-- General
hl.config({
    general = {
        gaps_in = gapsIn,
        gaps_out = gapsOut,
        border_size = borderSize,
        layout = "scrolling",
    },
})

-- Input
hl.config({
    input = {
        kb_layout = kbLayout,
        kb_options = kbOptions,
        sensitivity = sensitivity,
        accel_profile = accelProfile,
    },
    binds = {
        scroll_event_delay = 0,
        drag_threshold = 10,
    },
})

-- Scrolling
hl.config({
    scrolling = {
        column_width = 0.85,
        explicit_column_widths = { 0.35, 0.5, 0.65, 0.95, 1.0 },
    },
})

-- Decoration
hl.config({
    decoration = {
        rounding = rounding,
        blur = {
            enabled = blurEnabled,
        },
    },
})

-- Animations
hl.config({
    animations = {
        enabled = true,
    },
})

hl.animation({ leaf = "workspaces", enabled = true, speed = 5, style = "slidevert" })

-- Misc
hl.config({
    misc = {
        disable_hyprland_logo = true,
        force_default_wallpaper = 0,
        middle_click_paste = false,
    },
})

-- Rules
hl.window_rule({ float = true, match = { class = "blueman-manager" } })

-- Exec
hl.exec_cmd("dms run")
hl.exec_cmd("systemctl --user start hyprpolkitagent")
hl.exec_cmd("wl-paste --type text --watch cliphist store")
hl.exec_cmd("wl-paste --type image --watch cliphist store")

-- Keybinds
-- Shell IPC
hl.bind("SUPER + D",      hl.dsp.exec_cmd(dmsCmd .. " spotlight toggle"))
hl.bind("SUPER + V",      hl.dsp.exec_cmd(dmsCmd .. " clipboard toggle"))
hl.bind("SUPER + N",      hl.dsp.exec_cmd(dmsCmd .. " notifications toggle"))
hl.bind("SUPER + I",      hl.dsp.exec_cmd(dmsCmd .. " settings toggle"))
hl.bind("SUPER + Escape", hl.dsp.exec_cmd(dmsCmd .. " powermenu toggle"))
hl.bind("SUPER + SHIFT + L", hl.dsp.exec_cmd(dmsCmd .. " lock lock"))
hl.bind("SUPER + SHIFT + W", hl.dsp.exec_cmd(dmsCmd .. " wallpaper next"))

-- Window management
hl.bind("SUPER + Q",      hl.dsp.window.close())
hl.bind("SUPER + F",      hl.dsp.exec_cmd("hyprctl dispatch fullscreen 0"))
hl.bind("SUPER + ALT + F", hl.dsp.exec_cmd("hyprctl dispatch fullscreen 1"))
hl.bind("SUPER + SPACE",  hl.dsp.exec_cmd("hyprctl dispatch togglefloating"))

-- Focus
hl.bind("SUPER + LEFT",   hl.dsp.focus({ direction = "l" }))
hl.bind("SUPER + RIGHT",  hl.dsp.focus({ direction = "r" }))
hl.bind("SUPER + UP",     hl.dsp.focus({ direction = "u" }))
hl.bind("SUPER + DOWN",   hl.dsp.focus({ direction = "d" }))

-- Move window
hl.bind("SUPER + SHIFT + LEFT",  hl.dsp.window.move({ direction = "l" }))
hl.bind("SUPER + SHIFT + RIGHT", hl.dsp.window.move({ direction = "r" }))
hl.bind("SUPER + SHIFT + UP",    hl.dsp.window.move({ direction = "u" }))
hl.bind("SUPER + SHIFT + DOWN",  hl.dsp.window.move({ direction = "d" }))

-- Scrolling layout
hl.bind("SUPER + EQUAL",  hl.dsp.exec_cmd("hyprctl dispatch colresize +0.1"))
hl.bind("SUPER + MINUS",  hl.dsp.exec_cmd("hyprctl dispatch colresize -0.1"))
hl.bind("SUPER + CTRL + RIGHT", hl.dsp.exec_cmd("hyprctl dispatch layoutmsg swapcol r"))
hl.bind("SUPER + CTRL + LEFT",  hl.dsp.exec_cmd("hyprctl dispatch layoutmsg swapcol l"))

-- Workspaces
for i = 1, 5 do
    hl.bind("SUPER + " .. i, hl.dsp.focus({ workspace = tostring(i) }))
    hl.bind("SUPER + ALT + " .. i, hl.dsp.exec_cmd("hyprctl dispatch movetoworkspace " .. i))
end
hl.bind("SUPER + TAB",       hl.dsp.exec_cmd("hyprctl dispatch workspace -1"))
hl.bind("SUPER + SHIFT + TAB", hl.dsp.exec_cmd("hyprctl dispatch workspace +1"))
hl.bind("SUPER + Z",         hl.dsp.exec_cmd("hyprctl dispatch workspace -1"))
hl.bind("SUPER + X",         hl.dsp.exec_cmd("hyprctl dispatch workspace +1"))

-- Mouse
hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Media
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd(dmsCmd .. " volume increase"))
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd(dmsCmd .. " volume decrease"))
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd(dmsCmd .. " volume muteOutput"))
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd(dmsCmd .. " volume muteInput"))
hl.bind("XF86MonBrightnessUp",  hl.dsp.exec_cmd(dmsCmd .. " brightness increase"))
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd(dmsCmd .. " brightness decrease"))

-- Screenshots
hl.bind("PRINT",              hl.dsp.exec_cmd("grim -g \"$(slurp)\" - | wl-copy"))
hl.bind("SUPER + SHIFT + S",  hl.dsp.exec_cmd("grim -g \"$(slurp)\" - | wl-copy && swappy -d -"))

-- Apps
hl.bind("SUPER + E",         hl.dsp.exec_cmd(fileExplorer))
hl.bind("SUPER + W",         hl.dsp.exec_cmd(browser))
hl.bind("SUPER + T",         hl.dsp.exec_cmd(terminal))
hl.bind("SUPER + SHIFT + O", hl.dsp.exec_cmd(os.getenv("HOME") .. "/.config/dcli/scripts/switch-shell.sh"))
```

- [ ] **Step 2: Verify Lua syntax**

```bash
lua -e "dofile('/home/awhss/.config/hypr/shells/dms/hyprland.lua')" 2>&1 | head -5
# Expected: error about 'hl' not defined (normal — hl is a Hyprland runtime global)
# If syntax error, fix it
```

- [ ] **Step 3: Commit**

```bash
cd ~/.config/dcli
git add dotfiles/hypr/shells/dms/hyprland.lua
git commit -m "feat: add DMS Lua hyprland config"
```

---

## Task 3: Create Noctalia Lua config

**Files:**
- Create: `~/.config/hypr/shells/noctalia/hyprland.lua`

**Interfaces:**
- Consumes: nothing (self-contained)
- Produces: Full Noctalia hyprland config

- [ ] **Step 1: Create Noctalia Lua config**

```lua
-- ~/.config/hypr/shells/noctalia/hyprland.lua
-- Noctalia — Hyprland Lua config

local terminal     = "wezterm-gui"
local browser      = "brave-browser-nightly"
local editor       = "codium"
local fileExplorer = "thunar"
local noctaliaCmd  = os.getenv("HOME") .. "/.local/bin/noctalia ipc call"

local sensitivity  = 0.3
local accelProfile = "flat"
local kbLayout     = "us,ara"
local kbOptions    = "grp:win_space_toggle, ctrl:nocaps"

local gapsIn     = 4
local gapsOut    = 8
local borderSize = 2
local rounding   = 12

-- Env
hl.config({
    env = {
        { "GDK_BACKEND", "wayland,x11" },
        { "QT_QPA_PLATFORM", "wayland;xcb" },
        { "SDL_VIDEODRIVER", "wayland,x11,windows" },
        { "CLUTTER_BACKEND", "wayland" },
        { "ELECTRON_OZONE_PLATFORM_HINT", "auto" },
        { "XDG_CURRENT_DESKTOP", "Hyprland" },
        { "XDG_SESSION_TYPE", "wayland" },
        { "XDG_SESSION_DESKTOP", "Hyprland" },
    },
})

-- General
hl.config({
    general = {
        gaps_in = gapsIn,
        gaps_out = gapsOut,
        border_size = borderSize,
        layout = "scrolling",
    },
})

-- Input
hl.config({
    input = {
        kb_layout = kbLayout,
        kb_options = kbOptions,
        sensitivity = sensitivity,
        accel_profile = accelProfile,
    },
    binds = { scroll_event_delay = 0, drag_threshold = 10 },
})

-- Scrolling
hl.config({
    scrolling = {
        column_width = 0.85,
        explicit_column_widths = { 0.35, 0.5, 0.65, 0.95, 1.0 },
    },
})

-- Decoration
hl.config({
    decoration = {
        rounding = rounding,
        blur = { enabled = true },
    },
})

-- Animations
hl.config({ animations = { enabled = true } })
hl.animation({ leaf = "workspaces", enabled = true, speed = 5, style = "slidevert" })

-- Misc
hl.config({
    misc = {
        disable_hyprland_logo = true,
        force_default_wallpaper = 0,
        middle_click_paste = false,
    },
})

-- Rules
hl.window_rule({ float = true, match = { class = "blueman-manager" } })

-- Exec
hl.exec_cmd(noctaliaCmd)
hl.exec_cmd("systemctl --user start hyprpolkitagent")
hl.exec_cmd("wl-paste --type text --watch cliphist store")
hl.exec_cmd("wl-paste --type image --watch cliphist store")

-- Keybinds — Shell IPC
hl.bind("SUPER + Super_L", function() os.execute(noctaliaCmd .. " launcher toggle") end)
hl.bind("SUPER + D",      hl.dsp.exec_cmd(noctaliaCmd .. " controlCenter toggle"))
hl.bind("SUPER + N",      hl.dsp.exec_cmd(noctaliaCmd .. " notifications toggleHistory"))
hl.bind("SUPER + I",      hl.dsp.exec_cmd(noctaliaCmd .. " settings toggle"))
hl.bind("SUPER + L",      hl.dsp.exec_cmd(noctaliaCmd .. " lockScreen toggle"))
hl.bind("SUPER + SHIFT + W", hl.dsp.exec_cmd(noctaliaCmd .. " wallpaper random"))

-- Window management
hl.bind("SUPER + Q",      hl.dsp.window.close())
hl.bind("SUPER + F",      hl.dsp.exec_cmd("hyprctl dispatch fullscreen 0"))
hl.bind("SUPER + ALT + F", hl.dsp.exec_cmd("hyprctl dispatch fullscreen 1"))
hl.bind("SUPER + SPACE",  hl.dsp.exec_cmd("hyprctl dispatch togglefloating"))

-- Focus
hl.bind("SUPER + LEFT",   hl.dsp.focus({ direction = "l" }))
hl.bind("SUPER + RIGHT",  hl.dsp.focus({ direction = "r" }))
hl.bind("SUPER + UP",     hl.dsp.focus({ direction = "u" }))
hl.bind("SUPER + DOWN",   hl.dsp.focus({ direction = "d" }))

-- Move window
hl.bind("SUPER + SHIFT + LEFT",  hl.dsp.window.move({ direction = "l" }))
hl.bind("SUPER + SHIFT + RIGHT", hl.dsp.window.move({ direction = "r" }))
hl.bind("SUPER + SHIFT + UP",    hl.dsp.window.move({ direction = "u" }))
hl.bind("SUPER + SHIFT + DOWN",  hl.dsp.window.move({ direction = "d" }))

-- Scrolling layout
hl.bind("SUPER + EQUAL",  hl.dsp.exec_cmd("hyprctl dispatch colresize +0.1"))
hl.bind("SUPER + MINUS",  hl.dsp.exec_cmd("hyprctl dispatch colresize -0.1"))
hl.bind("SUPER + CTRL + RIGHT", hl.dsp.exec_cmd("hyprctl dispatch layoutmsg swapcol r"))
hl.bind("SUPER + CTRL + LEFT",  hl.dsp.exec_cmd("hyprctl dispatch layoutmsg swapcol l"))

-- Workspaces
for i = 1, 5 do
    hl.bind("SUPER + " .. i, hl.dsp.focus({ workspace = tostring(i) }))
    hl.bind("SUPER + ALT + " .. i, hl.dsp.exec_cmd("hyprctl dispatch movetoworkspace " .. i))
end
hl.bind("SUPER + Z",  hl.dsp.exec_cmd("hyprctl dispatch workspace -1"))
hl.bind("SUPER + X",  hl.dsp.exec_cmd("hyprctl dispatch workspace +1"))

-- Mouse
hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Media
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd(noctaliaCmd .. " volume increase"))
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd(noctaliaCmd .. " volume decrease"))
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd(noctaliaCmd .. " volume muteOutput"))
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd(noctaliaCmd .. " volume muteInput"))
hl.bind("XF86MonBrightnessUp",  hl.dsp.exec_cmd(noctaliaCmd .. " brightness increase"))
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd(noctaliaCmd .. " brightness decrease"))

-- Screenshots
hl.bind("PRINT",              hl.dsp.exec_cmd("grim -g \"$(slurp)\" - | wl-copy"))
hl.bind("SUPER + SHIFT + S",  hl.dsp.exec_cmd("grim -g \"$(slurp)\" - | wl-copy && swappy -d -"))

-- Apps
hl.bind("SUPER + W",         hl.dsp.exec_cmd(browser))
hl.bind("SUPER + R",         hl.dsp.exec_cmd(fileExplorer))
hl.bind("SUPER + T",         hl.dsp.exec_cmd(terminal))
hl.bind("SUPER + SHIFT + O", hl.dsp.exec_cmd(os.getenv("HOME") .. "/.config/dcli/scripts/switch-shell.sh"))
```

- [ ] **Step 2: Verify Lua syntax**

```bash
lua -e "dofile('/home/awhss/.config/hypr/shells/noctalia/hyprland.lua')" 2>&1 | head -5
```

- [ ] **Step 3: Commit**

```bash
cd ~/.config/dcli
git add dotfiles/hypr/shells/noctalia/hyprland.lua
git commit -m "feat: add Noctalia Lua hyprland config"
```

---

## Task 4: Create end4 Lua config

**Files:**
- Create: `~/.config/hypr/shells/end4/hyprland.lua`

**Interfaces:**
- Consumes: nothing (self-contained)
- Produces: Full end4 hyprland config (most complex — submap, quickshell globals)

- [ ] **Step 1: Create end4 Lua config**

```lua
-- ~/.config/hypr/shells/end4/hyprland.lua
-- end4 (illogical-impulse) — Hyprland Lua config

local terminal     = "wezterm-gui"
local browser      = "brave-browser-nightly"
local editor       = "codium"
local fileExplorer = "thunar"

local sensitivity  = 0.3
local accelProfile = "flat"
local kbLayout     = "us,ara"
local kbOptions    = "grp:win_space_toggle, ctrl:nocaps"

local gapsIn     = 4
local gapsOut    = 8
local borderSize = 2
local rounding   = 12

-- Env
hl.config({
    env = {
        { "GDK_BACKEND", "wayland,x11" },
        { "QT_QPA_PLATFORM", "wayland;xcb" },
        { "SDL_VIDEODRIVER", "wayland,x11,windows" },
        { "CLUTTER_BACKEND", "wayland" },
        { "ELECTRON_OZONE_PLATFORM_HINT", "auto" },
        { "XDG_CURRENT_DESKTOP", "Hyprland" },
        { "XDG_SESSION_TYPE", "wayland" },
        { "XDG_SESSION_DESKTOP", "Hyprland" },
    },
})

-- General
hl.config({
    general = {
        gaps_in = gapsIn,
        gaps_out = gapsOut,
        border_size = borderSize,
        layout = "scrolling",
    },
})

-- Input
hl.config({
    input = {
        kb_layout = kbLayout,
        kb_options = kbOptions,
        sensitivity = sensitivity,
        accel_profile = accelProfile,
    },
    binds = { scroll_event_delay = 0, drag_threshold = 10 },
})

-- Scrolling
hl.config({
    scrolling = {
        column_width = 0.85,
        explicit_column_widths = { 0.35, 0.5, 0.65, 0.95, 1.0 },
    },
})

-- Decoration
hl.config({
    decoration = {
        rounding = rounding,
        blur = { enabled = true },
    },
})

-- Animations
hl.config({ animations = { enabled = true } })
hl.animation({ leaf = "workspaces", enabled = true, speed = 5, style = "slidevert" })

-- Misc
hl.config({
    misc = {
        disable_hyprland_logo = true,
        force_default_wallpaper = 0,
        middle_click_paste = false,
    },
})

-- Rules
hl.window_rule({ float = true, match = { class = "blueman-manager" } })

-- Exec
hl.exec_cmd("qs -c ii")
hl.exec_cmd("gnome-keyring-daemon --start --components=secrets")
hl.exec_cmd("hypridle")
hl.exec_cmd("dbus-update-activation-environment --all")
hl.exec_cmd("wl-paste --type text --watch bash -c 'cliphist store && qs -c ii ipc call cliphistService update'")
hl.exec_cmd("wl-paste --type image --watch bash -c 'cliphist store && qs -c ii ipc call cliphistService update'")
hl.exec_cmd("systemctl --user start hyprpolkitagent")

-- Submap
hl.exec_cmd("hyprctl dispatch submap global")

-- Keybinds — Shell IPC (quickshell globals)
hl.bind("SUPER + Super_L", function() os.execute("qs -c ii ipc call TEST_ALIVE || pkill fuzzel || fuzzel") end)
hl.bind("SUPER + Super_L", hl.dsp.exec_cmd("qs -c ii ipc call searchGlobal toggleRelease"), { global = "quickshell:searchToggleRelease" })
hl.bind("SUPER + D",      hl.dsp.exec_cmd("qs -c ii ipc call searchGlobal toggleRelease"))
hl.bind("SUPER + N",      hl.dsp.exec_cmd("qs -c ii ipc call sidebar toggle"))
hl.bind("SUPER + I",      hl.dsp.exec_cmd("qs -c ii ipc call settings toggle"))
hl.bind("SUPER + L",      hl.dsp.exec_cmd("qs -c ii ipc call session toggle"))
hl.bind("SUPER + SHIFT + W", hl.dsp.exec_cmd("qs -c ii ipc call wallpaperSelector toggle"))

-- Window management
hl.bind("SUPER + Q",      hl.dsp.window.close())
hl.bind("SUPER + F",      hl.dsp.exec_cmd("hyprctl dispatch fullscreen 0"))
hl.bind("SUPER + ALT + F", hl.dsp.exec_cmd("hyprctl dispatch fullscreen 1"))
hl.bind("SUPER + SPACE",  hl.dsp.exec_cmd("hyprctl dispatch togglefloating"))

-- Focus
hl.bind("SUPER + LEFT",   hl.dsp.focus({ direction = "l" }))
hl.bind("SUPER + RIGHT",  hl.dsp.focus({ direction = "r" }))
hl.bind("SUPER + UP",     hl.dsp.focus({ direction = "u" }))
hl.bind("SUPER + DOWN",   hl.dsp.focus({ direction = "d" }))

-- Move window
hl.bind("SUPER + SHIFT + LEFT",  hl.dsp.window.move({ direction = "l" }))
hl.bind("SUPER + SHIFT + RIGHT", hl.dsp.window.move({ direction = "r" }))
hl.bind("SUPER + SHIFT + UP",    hl.dsp.window.move({ direction = "u" }))
hl.bind("SUPER + SHIFT + DOWN",  hl.dsp.window.move({ direction = "d" }))

-- Scrolling layout
hl.bind("SUPER + EQUAL",  hl.dsp.exec_cmd("hyprctl dispatch colresize +0.1"))
hl.bind("SUPER + MINUS",  hl.dsp.exec_cmd("hyprctl dispatch colresize -0.1"))
hl.bind("SUPER + CTRL + RIGHT", hl.dsp.exec_cmd("hyprctl dispatch layoutmsg swapcol r"))
hl.bind("SUPER + CTRL + LEFT",  hl.dsp.exec_cmd("hyprctl dispatch layoutmsg swapcol l"))

-- Workspaces
for i = 1, 5 do
    hl.bind("SUPER + " .. i, hl.dsp.focus({ workspace = tostring(i) }))
    hl.bind("SUPER + ALT + " .. i, hl.dsp.exec_cmd("hyprctl dispatch movetoworkspace " .. i))
end
hl.bind("SUPER + Z",  hl.dsp.exec_cmd("hyprctl dispatch workspace -1"))
hl.bind("SUPER + X",  hl.dsp.exec_cmd("hyprctl dispatch workspace +1"))

-- Mouse
hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Media (direct wpctl/brightnessctl)
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"))
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"))
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"))
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"))
hl.bind("XF86MonBrightnessUp",  hl.dsp.exec_cmd("brightnessctl set +5%"))
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl set 5%-"))

-- Screenshots
hl.bind("PRINT",              hl.dsp.exec_cmd("grim -g \"$(slurp)\" - | wl-copy"))
hl.bind("SUPER + SHIFT + S",  hl.dsp.exec_cmd("grim -g \"$(slurp)\" - | wl-copy && swappy -d -"))

-- Apps
hl.bind("SUPER + W",         hl.dsp.exec_cmd(browser))
hl.bind("SUPER + R",         hl.dsp.exec_cmd(fileExplorer))
hl.bind("SUPER + T",         hl.dsp.exec_cmd(terminal))
hl.bind("SUPER + SHIFT + O", hl.dsp.exec_cmd(os.getenv("HOME") .. "/.config/dcli/scripts/switch-shell.sh"))
```

- [ ] **Step 2: Verify Lua syntax**

```bash
lua -e "dofile('/home/awhss/.config/hypr/shells/end4/hyprland.lua')" 2>&1 | head -5
```

- [ ] **Step 3: Commit**

```bash
cd ~/.config/dcli
git add dotfiles/hypr/shells/end4/hyprland.lua
git commit -m "feat: add end4 Lua hyprland config"
```

---

## Task 5: Delete old hyprlang configs

**Files:**
- Delete: `~/.config/hypr/shells/caelestia.conf`
- Keep (for reference): All `hyprland/*.conf` files, `variables.conf` files

- [ ] **Step 1: Remove caelestia.conf (now handled by Lua dispatch)**

```bash
rm ~/.config/hypr/shells/caelestia.conf
```

- [ ] **Step 2: Commit**

```bash
cd ~/.config/dcli
git add -A
git commit -m "chore: remove old hyprlang shell configs, Lua is now primary"
```

---

## Task 6: Update diagnostic file

**Files:**
- Modify: `~/.config/dcli/DIAGNOSTIC-2026-07-23.md`

- [ ] **Step 1: Update config loading section**

Replace the "How hyprlang `.conf` override works" section with Lua-based description.

- [ ] **Step 2: Update file inventory**

- [ ] **Step 3: Commit**

```bash
cd ~/.config/dcli
git add DIAGNOSTIC-2026-07-23.md
git commit -m "docs: update diagnostic for Lua migration"
```

---

## Verification

After all tasks, restart Hyprland and verify:

1. **Caelestia** (default): `super+return` opens wezterm, `super+c` opens zeditor, layout is scrolling
2. **DMS**: `switch-shell.sh dms` → restart → DMS shell loads, `super+d` opens spotlight
3. **Noctalia**: `switch-shell.sh noctalia` → restart → Noctalia loads, `super+l` locks
4. **end4**: `switch-shell.sh end4` → restart → end4 loads, `super+d` opens search
5. **AMBXst**: Uses its own `hyprland.lua` directly — no dcli entry point needed

Switch back to caelestia: `switch-shell.sh caelestia` → restart → back to caelestia.
