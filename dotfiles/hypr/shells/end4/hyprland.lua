-- ~/.config/hypr/shells/end4/hyprland.lua
-- end4 (illogical-impulse) — Hyprland Lua config
-- Uses upstream end4 config with house overrides in custom/

-- Modules are fully qualified (shells.end4.*): the shared
-- ~/.config/hypr/hyprland/ and ~/.config/hypr/custom/ are real directories that
-- other shells and upstream installers write into, so bare names could be
-- shadowed there.

-- Internal stuff --
require("shells.end4.hyprland.lib")
require("shells.end4.hyprland.services")

-- Environment variables --
require("shells.end4.hyprland.env")
if is_file_exists(HOME .. "/.config/hypr/shells/end4/custom/env.lua") then
    require("shells.end4.custom.env")
end

-- Variables (house overrides loaded before keybinds so they take effect) --
require("shells.end4.hyprland.variables")
if is_file_exists(HOME .. "/.config/hypr/shells/end4/custom/variables.lua") then
    require("shells.end4.custom.variables")
end

-- Default configurations --
require("shells.end4.hyprland.execs")
require("shells.end4.hyprland.general")
require("shells.end4.hyprland.rules")
require("shells.end4.hyprland.colors")
require("shells.end4.hyprland.keybinds")

-- Custom configurations (house overrides) --
if is_file_exists(HOME .. "/.config/hypr/shells/end4/custom/execs.lua") then
    require("shells.end4.custom.execs")
end
if is_file_exists(HOME .. "/.config/hypr/shells/end4/custom/general.lua") then
    require("shells.end4.custom.general")
end
if is_file_exists(HOME .. "/.config/hypr/shells/end4/custom/rules.lua") then
    require("shells.end4.custom.rules")
end
if is_file_exists(HOME .. "/.config/hypr/shells/end4/custom/keybinds.lua") then
    require("shells.end4.custom.keybinds")
end

-- Shell overrides --
-- The shared ~/.config/hypr/hyprland/shellOverrides/main.lua, not a shells/end4
-- copy: it is what the ii settings app writes (HyprlandConfig.qml,
-- shellOverridesPath). require() so autoreload applies the app's runtime edits.
-- The house layout (scrolling) and keyboard (us,ara) were deliberately stripped
-- from that file; if the app rewrites those keys it will reintroduce them.
if is_file_exists(HOME .. "/.config/hypr/hyprland/shellOverrides/main.lua") then
    require("hyprland.shellOverrides.main")
end
