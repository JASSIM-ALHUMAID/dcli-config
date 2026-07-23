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

-- Default monitor conf
hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = 1,
})

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
        explicit_column_widths = "0.35, 0.5, 0.65, 0.95, 1.0",
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
hl.exec_cmd("qs -c ii")
hl.exec_cmd("gnome-keyring-daemon --start --components=secrets")
hl.exec_cmd("hypridle")
hl.exec_cmd("dbus-update-activation-environment --all")
hl.exec_cmd("wl-paste --type text --watch bash -c 'cliphist store && qs -c ii ipc call cliphistService update'")
hl.exec_cmd("wl-paste --type image --watch bash -c 'cliphist store && qs -c ii ipc call cliphistService update'")
hl.exec_cmd("systemctl --user start hyprpolkitagent")

-- Submap
hl.exec_cmd("hyprctl dispatch submap global")

-- Keybinds
-- Shell IPC — the ii shell registers these as hyprland globals. Tap Super
-- alone opens the launcher; Super+Space is the us/ara layout toggle.
hl.bind("SUPER + Super_L",  hl.dsp.global("quickshell:searchToggleRelease"), { release = true })
hl.bind("SUPER + D",        hl.dsp.exec_cmd("qs -c ii ipc call search toggle"))
hl.bind("SUPER + V",        hl.dsp.global("quickshell:overviewClipboardToggle"))
hl.bind("SUPER + A",        hl.dsp.global("quickshell:sidebarLeftToggle"))
hl.bind("SUPER + N",        hl.dsp.global("quickshell:sidebarRightToggle"))
hl.bind("SUPER + M",        hl.dsp.global("quickshell:mediaControlsToggle"))
hl.bind("SUPER + G",        hl.dsp.global("quickshell:overlayToggle"))
hl.bind("SUPER + J",        hl.dsp.global("quickshell:barToggle"))
hl.bind("SUPER + K",        hl.dsp.global("quickshell:oskToggle"))
hl.bind("SUPER + SLASH",    hl.dsp.global("quickshell:cheatsheetToggle"))
hl.bind("SUPER + PERIOD",   hl.dsp.global("quickshell:overviewEmojiToggle"))
hl.bind("SUPER + I",        hl.dsp.exec_cmd("qs -p " .. os.getenv("HOME") .. "/.config/quickshell/ii/settings.qml"))
hl.bind("CTRL + ALT + DELETE", hl.dsp.global("quickshell:sessionToggle"))
hl.bind("CTRL + SUPER + T",    hl.dsp.global("quickshell:wallpaperSelectorToggle"))
hl.bind("SUPER + SHIFT + W",   hl.dsp.global("quickshell:wallpaperSelectorToggle"))
hl.bind("CTRL + SUPER + SHIFT + D", hl.dsp.global("quickshell:toggleLightDark"))
hl.bind("SUPER + SHIFT + A", hl.dsp.global("quickshell:regionSearch"))
hl.bind("SUPER + SHIFT + X", hl.dsp.global("quickshell:regionOcr"))
hl.bind("SUPER + SHIFT + T", hl.dsp.global("quickshell:screenTranslate"))
hl.bind("SUPER + SHIFT + R", hl.dsp.global("quickshell:regionRecord"))

-- Window management
hl.bind("SUPER + Q",         hl.dsp.window.close())
hl.bind("SUPER + F",         hl.dsp.window.fullscreen({ mode = "fullscreen" }))
hl.bind("SUPER + SHIFT + F", hl.dsp.window.fullscreen({ mode = "maximized" }))
hl.bind("SUPER + ALT + F",   hl.dsp.window.float())

-- Focus
hl.bind("SUPER + LEFT",  hl.dsp.focus({ direction = "l" }))
hl.bind("SUPER + RIGHT", hl.dsp.focus({ direction = "r" }))
hl.bind("SUPER + UP",    hl.dsp.focus({ direction = "u" }))
hl.bind("SUPER + DOWN",  hl.dsp.focus({ direction = "d" }))

-- Move window
hl.bind("SUPER + SHIFT + LEFT",  hl.dsp.window.move({ direction = "l" }))
hl.bind("SUPER + SHIFT + RIGHT", hl.dsp.window.move({ direction = "r" }))
hl.bind("SUPER + SHIFT + UP",    hl.dsp.window.move({ direction = "u" }))
hl.bind("SUPER + SHIFT + DOWN",  hl.dsp.window.move({ direction = "d" }))

-- Scrolling layout
hl.bind("SUPER + EQUAL",          hl.dsp.layout("colresize +0.1"))
hl.bind("SUPER + MINUS",          hl.dsp.layout("colresize -0.1"))
hl.bind("SUPER + SHIFT + PERIOD", hl.dsp.layout("colresize +conf"))
hl.bind("SUPER + SHIFT + COMMA",  hl.dsp.layout("colresize -conf"))
hl.bind("SUPER + ALT + PERIOD",   hl.dsp.layout("move +col"))
hl.bind("SUPER + ALT + COMMA",    hl.dsp.layout("move -col"))
hl.bind("SUPER + CTRL + RIGHT",   hl.dsp.layout("swapcol r"))
hl.bind("SUPER + CTRL + LEFT",    hl.dsp.layout("swapcol l"))

-- Workspaces
for i = 1, 5 do
    hl.bind("SUPER + " .. i, hl.dsp.focus({ workspace = tostring(i) }))
    hl.bind("SUPER + ALT + " .. i, hl.dsp.window.move({ workspace = tostring(i) }))
end
hl.bind("SUPER + TAB",         hl.dsp.focus({ workspace = "m+1" }))
hl.bind("SUPER + SHIFT + TAB", hl.dsp.focus({ workspace = "m-1" }))
hl.bind("SUPER + Z", hl.dsp.focus({ workspace = "-1" }), { repeating = true })
hl.bind("SUPER + X", hl.dsp.focus({ workspace = "+1" }), { repeating = true })

-- Mouse
hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Media
hl.bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true })
hl.bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), { locked = true })
hl.bind("XF86AudioMute",         hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true })
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl set +5%"), { locked = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl set 5%-"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })

-- Screenshots (SUPER+SHIFT+S is the shell's own region screenshot)
hl.bind("PRINT", hl.dsp.exec_cmd("grim -g \"$(slurp)\" - | wl-copy"))
hl.bind("SUPER + SHIFT + S", hl.dsp.global("quickshell:regionScreenshot"))

-- Apps
hl.bind("SUPER + RETURN",   hl.dsp.exec_cmd(terminal))
hl.bind("SUPER + T",        hl.dsp.exec_cmd(terminal))
hl.bind("SUPER + B",        hl.dsp.exec_cmd(browser))
hl.bind("SUPER + E",        hl.dsp.exec_cmd(fileExplorer))
hl.bind("SUPER + R",        hl.dsp.exec_cmd(fileExplorer))
hl.bind("SUPER + ALT + K",  hl.dsp.exec_cmd("kitty"))
hl.bind("CTRL + ALT + B",   hl.dsp.exec_cmd("blueman-manager"))
hl.bind("SUPER + BACKSLASH",         hl.dsp.exec_cmd("hyprsunset -t 4500"))
hl.bind("SUPER + SHIFT + BACKSLASH", hl.dsp.exec_cmd("pkill hyprsunset"))
hl.bind("SUPER + SHIFT + O", hl.dsp.exec_cmd(os.getenv("HOME") .. "/.config/dcli/scripts/switch-shell.sh"))
