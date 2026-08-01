-- ~/.config/hypr/shells/end4/hyprland.lua
-- end4 (illogical-impulse) — Hyprland Lua config
-- Uses upstream end4 config with house overrides in custom/

-- Prepend this shell's directory so require("hyprland.*") resolves here,
-- not into the shared ~/.config/hypr/hyprland/ (caelestia's).
local shell_dir = os.getenv("HOME") .. "/.config/hypr/shells/end4"
package.path = shell_dir .. "/?.lua;" .. shell_dir .. "/?/init.lua;" .. package.path

-- Internal stuff --
require("hyprland.lib")
require("hyprland.services")

-- Environment variables --
require("hyprland.env")
if is_file_exists(HOME .. "/.config/hypr/shells/end4/custom/env.lua") then
    require("custom.env")
end

-- Variables (house overrides loaded before keybinds so they take effect) --
require("hyprland.variables")
if is_file_exists(HOME .. "/.config/hypr/shells/end4/custom/variables.lua") then
    require("custom.variables")
end

-- Default configurations --
require("hyprland.execs")
require("hyprland.general")
require("hyprland.rules")
require("hyprland.colors")
require("hyprland.keybinds")

-- Custom configurations (house overrides) --
if is_file_exists(HOME .. "/.config/hypr/shells/end4/custom/execs.lua") then
    require("custom.execs")
end
if is_file_exists(HOME .. "/.config/hypr/shells/end4/custom/general.lua") then
    require("custom.general")
end
if is_file_exists(HOME .. "/.config/hypr/shells/end4/custom/rules.lua") then
    require("custom.rules")
end
if is_file_exists(HOME .. "/.config/hypr/shells/end4/custom/keybinds.lua") then
    require("custom.keybinds")
end

-- Shell overrides --
require("hyprland.shellOverrides.main")
