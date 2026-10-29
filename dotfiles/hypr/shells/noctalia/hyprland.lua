-- ~/.config/hypr/shells/noctalia/hyprland.lua
-- Noctalia — Hyprland Lua config (modular loader)

local terminal     = "wezterm-gui"
local browser      = "brave-browser-nightly"
local defaultBrowser = "zen-browser"
local editor       = "zed"
local fileExplorer = "thunar"
local noctaliaCmd  = "noctalia msg"

-- Modules are fully qualified: ~/.config/hypr/hyprland/ is a real directory
-- other shells' upstreams write into, so a bare "hyprland.<name>" could be
-- shadowed there. Preferences shared by every standalone shell are in
-- ~/.config/hypr/common/.
require("common.monitor")

require("common.env")
require("common.general")
require("common.input")
require("common.bind-options")
require("common.gestures")
require("common.scrolling")
require("common.decoration")
require("common.animations")
require("common.workspace-slide")
require("common.misc")
require("common.rules")
require("shells.noctalia.hyprland.execs")
require("shells.noctalia.hyprland.keybinds")
