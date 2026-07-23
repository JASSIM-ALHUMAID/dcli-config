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

-- Default monitor conf
hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = 1,
})

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
        explicit_column_widths = "0.35, 0.5, 0.65, 0.95, 1.0",
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

hl.curve("standard", { type = "bezier", points = { { 0.2, 0 }, { 0, 1 } } })
hl.animation({ leaf = "workspaces", enabled = true, speed = 5, bezier = "standard", style = "slidevert" })

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
