-- ~/.config/hypr/shells/noctalia/hyprland.lua
-- Noctalia — Hyprland Lua config (modular loader)

local terminal     = "wezterm-gui"
local browser      = "brave-browser-nightly"
local defaultBrowser = "zen-browser"
local editor       = "zed"
local fileExplorer = "thunar"
local noctaliaCmd  = "noctalia msg"

-- Default monitor conf
hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = 1,
})

-- Modules
require("hyprland.env")
require("hyprland.general")
require("hyprland.input")
require("hyprland.scrolling")
require("hyprland.decoration")
require("hyprland.animations")
require("hyprland.misc")
require("hyprland.rules")
require("hyprland.execs")
require("hyprland.keybinds")
