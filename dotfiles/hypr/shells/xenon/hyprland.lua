-- ~/.config/hypr/shells/xenon/hyprland.lua
-- xenon (MannuVilasara/xenon-shell) — Hyprland Lua config (modular loader)
--
-- The shell is the quickshell config named "xenon" (~/.config/quickshell/xenon,
-- a symlink into ~/.local/share/xenon-shell). Everything it exposes goes
-- through `qs -c xenon ipc call <target> <fn>` — see hyprland/keybinds.lua.

local terminal     = "wezterm-gui"
local browser      = "brave-browser-nightly"
local defaultBrowser = "zen-browser"
local editor       = "zed"
local fileExplorer = "thunar"
local xenonCmd     = "qs -c xenon ipc call"

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
