-- ~/.config/hypr/shells/dms/hyprland.lua
-- DMS (DankMaterialShell) — Hyprland Lua config

-- Default monitor conf
hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = 1,
})

-- Load modules in order
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

-- DMS theming (loaded last)
pcall(require, "dms.colors")
