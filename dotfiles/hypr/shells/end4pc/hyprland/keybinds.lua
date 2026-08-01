-- end4-pC (pctrade's illogical-impulse fork) keybinds

local terminal      = "wezterm-gui"
local browser       = "brave-browser-nightly"
local defaultBrowser = "zen-browser"
local fileExplorer  = "thunar"

-- Shell IPC — the end4-pC shell registers these as hyprland globals (verified
-- against its GlobalShortcut names). Tap Super alone opens the launcher;
-- Super+Space is the us/ara layout toggle.
hl.bind("SUPER + Super_L",  hl.dsp.global("quickshell:searchToggleRelease"), { release = true })
hl.bind("SUPER + D",        hl.dsp.global("quickshell:searchToggle"))
hl.bind("SUPER + V",        hl.dsp.global("quickshell:overviewClipboardToggle"))
hl.bind("SUPER + A",        hl.dsp.global("quickshell:sidebarLeftToggle"))
hl.bind("SUPER + N",        hl.dsp.global("quickshell:sidebarRightToggle"))
hl.bind("SUPER + M",        hl.dsp.global("quickshell:mediaControlsToggle"))
hl.bind("SUPER + G",        hl.dsp.global("quickshell:overlayToggle"))
hl.bind("SUPER + J",        hl.dsp.global("quickshell:barToggle"))
hl.bind("SUPER + K",        hl.dsp.global("quickshell:oskToggle"))
hl.bind("SUPER + PERIOD",   hl.dsp.global("quickshell:overviewEmojiToggle"))
hl.bind("SUPER + I",        hl.dsp.global("quickshell:settingsToggle"))
-- Note: end4-pC ships no cheatsheetToggle or toggleLightDark global, so the
-- ii shell's SUPER+SLASH (cheatsheet) and CTRL+SUPER+SHIFT+D (light/dark)
-- binds are intentionally omitted here.
hl.bind("CTRL + ALT + DELETE", hl.dsp.global("quickshell:sessionToggle"))
hl.bind("CTRL + SUPER + T",    hl.dsp.global("quickshell:wallpaperSelectorToggle"))
hl.bind("SUPER + SHIFT + W",   hl.dsp.global("quickshell:wallpaperSelectorRandom"))
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
hl.bind("SUPER + W",        hl.dsp.exec_cmd(defaultBrowser))
hl.bind("SUPER + E",        hl.dsp.exec_cmd(fileExplorer))
hl.bind("SUPER + R",        hl.dsp.exec_cmd(fileExplorer))
hl.bind("SUPER + ALT + K",  hl.dsp.exec_cmd("kitty"))
hl.bind("CTRL + ALT + B",   hl.dsp.exec_cmd("blueman-manager"))
hl.bind("SUPER + BACKSLASH",         hl.dsp.exec_cmd("hyprsunset -t 4500"))
hl.bind("SUPER + SHIFT + BACKSLASH", hl.dsp.exec_cmd("pkill hyprsunset"))
hl.bind("SUPER + SHIFT + O", hl.dsp.exec_cmd(os.getenv("HOME") .. "/.config/dcli/scripts/switch-shell.sh"))
