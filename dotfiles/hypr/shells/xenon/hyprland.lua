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
require("shells.xenon.hyprland.execs")
require("shells.xenon.hyprland.keybinds")
