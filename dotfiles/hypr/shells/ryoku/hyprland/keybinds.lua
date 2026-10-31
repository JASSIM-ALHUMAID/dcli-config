-- ryoku keybinds
--
-- Upstream binds its shell through Hyprland global shortcuts
-- (`hl.dsp.global("ryoku:launcher")`), which only exist while the checkout's
-- own Hyprland config is loaded. dcli owns ~/.config/hypr instead, so the same
-- surfaces are reached through the daemon CLI: `ryoku-shell <verb>`. The verbs
-- are the ones the daemon routes in ryoku/shell/ipc (launcher, overview,
-- visualizer*, quicksettings, wallpaper-menu, clipboard, hub).
--
-- The ryoku-* helpers are on the shell's own PATH (execs.lua), so its in-shell
-- actions work; these binds still use the house tools so every shell shares
-- one muscle memory. Not bound at all: `ryoku-shell lock` (qylock is not
-- installed — it would leave the session unlocked) and `ryoku-shell voice`
-- (needs the ryostage venv, an opt-in `ryostage install`).

local ryokuShell    = os.getenv("HOME") .. "/.local/bin/ryoku-shell"
local terminal      = "wezterm-gui"
local browser       = "brave-browser-nightly"
local defaultBrowser = "zen-browser"
local fileExplorer  = "thunar"

-- Shell surfaces. Tap Super alone opens the launcher; SUPER+Space stays the
-- house us/ara layout toggle (ryoku's own launcher sits on SUPER+Space, so it
-- moves to SUPER+D here). SUPER+TAB is the overview, not workspace cycling.
hl.bind("SUPER + Super_L",    hl.dsp.exec_cmd(ryokuShell .. " launcher"), { release = true })
hl.bind("SUPER + D",          hl.dsp.exec_cmd(ryokuShell .. " launcher"))
hl.bind("SUPER + V",          hl.dsp.exec_cmd(ryokuShell .. " clipboard"))
hl.bind("SUPER + N",          hl.dsp.exec_cmd(ryokuShell .. " quicksettings"))
hl.bind("SUPER + Escape",     hl.dsp.exec_cmd(ryokuShell .. " quicksettings"))
hl.bind("SUPER + I",          hl.dsp.exec_cmd(ryokuShell .. " hub open"))
hl.bind("SUPER + comma",      hl.dsp.exec_cmd(ryokuShell .. " hub open"))
hl.bind("SUPER + SHIFT + W",  hl.dsp.exec_cmd(ryokuShell .. " wallpaper-menu"))
hl.bind("SUPER + TAB",        hl.dsp.exec_cmd(ryokuShell .. " overview"))
hl.bind("SUPER + ALT + TAB",  hl.dsp.exec_cmd(ryokuShell .. " overview"))
hl.bind("SUPER + M",          hl.dsp.exec_cmd(ryokuShell .. " visualizer"))
hl.bind("SUPER + SHIFT + M",  hl.dsp.exec_cmd(ryokuShell .. " visualizer-overlay"))
hl.bind("SUPER + ALT + M",    hl.dsp.exec_cmd(ryokuShell .. " visualizer-place"))

-- Lock through the house hyprlock config. `ryoku-shell lock` engages qylock,
-- which the checkout does not install; it would leave the session unlocked.
hl.bind("SUPER + L",          hl.dsp.exec_cmd("hyprlock"))

-- The one bind every shell here shares.
hl.bind("SUPER + SHIFT + O",  hl.dsp.exec_cmd(os.getenv("HOME") .. "/.config/dcli/scripts/switch-shell.sh"))

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

-- Workspaces. SUPER+TAB is the overview, so cycling stays on Z/X.
for i = 1, 10 do
    local key = i == 10 and "0" or tostring(i)
    hl.bind("SUPER + " .. key, hl.dsp.focus({ workspace = tostring(i) }))
    hl.bind("SUPER + ALT + " .. key, hl.dsp.window.move({ workspace = tostring(i) }))
end
hl.bind("SUPER + Z", hl.dsp.focus({ workspace = "-1" }), { repeating = true })
hl.bind("SUPER + X", hl.dsp.focus({ workspace = "+1" }), { repeating = true })

-- Mouse
hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Media. The keys drive PipeWire and brightnessctl directly, as in every other
-- shell (bind execs do not inherit the ryoku PATH); the daemon's OSD follows the
-- sink/backlight change either way.
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
hl.bind("SUPER + RETURN",   hl.dsp.exec_cmd(terminal))
hl.bind("SUPER + T",        hl.dsp.exec_cmd(terminal))
hl.bind("SUPER + B",        hl.dsp.exec_cmd(browser))
hl.bind("SUPER + E",        hl.dsp.exec_cmd(fileExplorer))
hl.bind("SUPER + R",        hl.dsp.exec_cmd(fileExplorer))
hl.bind("SUPER + ALT + K",  hl.dsp.exec_cmd("kitty"))
hl.bind("CTRL + ALT + B",   hl.dsp.exec_cmd("blueman-manager"))
hl.bind("SUPER + BACKSLASH",         hl.dsp.exec_cmd("hyprsunset -t 4500"))
hl.bind("SUPER + SHIFT + BACKSLASH", hl.dsp.exec_cmd("pkill hyprsunset"))
hl.bind("SUPER + W",        hl.dsp.exec_cmd(defaultBrowser))
