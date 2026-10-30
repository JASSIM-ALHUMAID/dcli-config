-- ~/.config/hypr/shells/ryoku/hyprland.lua
-- ryoku (Ryoku-dev/ryoku) — Hyprland Lua config (checkout-only install)
--
-- The shell is one Quickshell config supervised by the ryoku-shell daemon
-- (~/.local/bin/ryoku-shell, built from the checkout by scripts/setup-ryoku.sh).
-- Every shell action goes through that CLI (`ryoku-shell launcher`, ...), which
-- forwards it over the daemon socket — see hyprland/keybinds.lua.
--
-- This file is NOT upstream's hyprland config. `ryoku materialize` would copy
-- the distro's whole ~/.config/hypr into place (entry point, monitors, binds,
-- plugins), and that tree is dcli's. Only the shell's surfaces are bound here;
-- the house common layer and the usual window/workspace keys stay.

local terminal      = "wezterm-gui"
local browser       = "brave-browser-nightly"
local defaultBrowser = "zen-browser"
local editor        = "zed"
local fileExplorer  = "thunar"

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
require("shells.ryoku.hyprland.execs")
require("shells.ryoku.hyprland.keybinds")
