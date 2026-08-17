-- ml4w keybinds

local home      = os.getenv("HOME")
local qs        = "qs -c ml4w ipc call"
-- The overview and settings apps run as path-based quickshell instances, so
-- they are addressed with `qs -p <path>`, not by config name.
local overviewIpc = "qs -p " .. home .. "/.config/ml4w-overview ipc call"
local settingsIpc = "qs -p " .. home .. "/.local/share/ml4w-dotfiles-settings/quickshell ipc call"
local terminal  = "wezterm-gui"
local browser   = "brave-browser-nightly"
local defaultBrowser = "zen-browser"
local fileExplorer = "thunar"
local launcher  = os.getenv("HOME") .. "/.config/hypr/scripts/launcher.sh"

-- Shell IPC. Targets registered by ml4w's shell.qml / StatusbarApp /
-- SidebarApp / PowerApp / CalendarApp / WallpaperApp / CustomTheme.
-- `statusbar focus` expands the pill and grabs the keyboard (SUPER+SPACE).
-- `theme-manager reload` re-reads ~/.config/ml4w/colors/colors.json.
hl.bind("SUPER + SPACE",      hl.dsp.exec_cmd(qs .. " statusbar focus"))
hl.bind("SUPER + CTRL + B",   hl.dsp.exec_cmd(qs .. " statusbar toggle"))
hl.bind("SUPER + SHIFT + B",  hl.dsp.exec_cmd(qs .. " statusbar reload"))
hl.bind("SUPER + CTRL + S",   hl.dsp.exec_cmd(qs .. " sidebar toggle"))
hl.bind("SUPER + CTRL + P",   hl.dsp.exec_cmd(qs .. " power toggle"))
hl.bind("SUPER + CTRL + C",   hl.dsp.exec_cmd(qs .. " calendar toggle"))
hl.bind("SUPER + CTRL + W",   hl.dsp.exec_cmd(qs .. " wallpaper toggle"))
hl.bind("SUPER + SHIFT + W",  hl.dsp.exec_cmd(qs .. " wallpaper toggle"))
hl.bind("SUPER + CTRL + RETURN", hl.dsp.exec_cmd(launcher))
-- The welcome window lives in the same process as the bar (shell.qml
-- instantiates WelcomeWindow), so it answers on the "ml4w" config like the rest.
hl.bind("SUPER + CTRL + H",   hl.dsp.exec_cmd(qs .. " welcome toggle"))

-- Lock. ml4w has no lock of its own — the PowerApp's lock button shells out to
-- `ml4w-power -l` (`pidof hyprlock || hyprlock`), so the bind goes through the
-- same script. Bare hyprlock needs a config in an XDG path; the house one is
-- ~/.config/hypr/hyprlock.conf.
hl.bind("SUPER + L",          hl.dsp.exec_cmd(home .. "/.config/ml4w/scripts/ml4w-power -l"))

-- The overview and the settings app are their own quickshell processes (started
-- in execs.lua), so their IPC goes through `qs -p <path>`, NOT `qs -c ml4w`.
-- SUPER+TAB is already the workspace cycle below, so the overview takes
-- SUPER+SHIFT+SPACE.
hl.bind("SUPER + SHIFT + SPACE", hl.dsp.exec_cmd(overviewIpc .. " overview toggle"))
hl.bind("SUPER + CTRL + COMMA",  hl.dsp.exec_cmd(settingsIpc .. " settings toggle"))

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
for i = 1, 10 do
    local key = i == 10 and "0" or tostring(i)
    hl.bind("SUPER + " .. key, hl.dsp.focus({ workspace = tostring(i) }))
    hl.bind("SUPER + ALT + " .. key, hl.dsp.window.move({ workspace = tostring(i) }))
end
hl.bind("SUPER + TAB",         hl.dsp.focus({ workspace = "m+1" }))
hl.bind("SUPER + SHIFT + TAB", hl.dsp.focus({ workspace = "m-1" }))
hl.bind("SUPER + Z", hl.dsp.focus({ workspace = "-1" }), { repeating = true })
hl.bind("SUPER + X", hl.dsp.focus({ workspace = "+1" }), { repeating = true })

-- Mouse
hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Media (ml4w's statusbar reads PipeWire directly via its VolumeModule; the
-- keys drive the tools and the OSD follows)
hl.bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd("wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true })
hl.bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), { locked = true })
hl.bind("XF86AudioMute",         hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true })
hl.bind("XF86AudioMicMute",      hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true })
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl s 5%+"), { locked = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl s 5%-"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })

-- Screenshots
hl.bind("PRINT",             hl.dsp.exec_cmd("grim -g \"$(slurp)\" - | wl-copy"))
hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd("grim -g \"$(slurp)\" - | swappy -f -"))

-- Apps
hl.bind("SUPER + RETURN",  hl.dsp.exec_cmd(terminal))
hl.bind("SUPER + T",       hl.dsp.exec_cmd(terminal))
hl.bind("SUPER + B",       hl.dsp.exec_cmd(browser))
hl.bind("SUPER + E",       hl.dsp.exec_cmd(fileExplorer))
hl.bind("SUPER + R",       hl.dsp.exec_cmd(fileExplorer))
hl.bind("SUPER + W",       hl.dsp.exec_cmd(defaultBrowser))
hl.bind("SUPER + SHIFT + O", hl.dsp.exec_cmd(os.getenv("HOME") .. "/.config/dcli/scripts/switch-shell.sh"))
