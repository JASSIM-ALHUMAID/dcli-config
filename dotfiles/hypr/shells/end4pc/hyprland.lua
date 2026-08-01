-- ~/.config/hypr/shells/end4pc/hyprland.lua
-- end4-pC (pctrade's illogical-impulse fork) — Hyprland Lua config.
-- Runs the "end4-pC" quickshell config; independent of the "ii" (end4) shell.

local terminal     = "wezterm-gui"
local browser      = "brave-browser-nightly"
local defaultBrowser = "zen-browser"
local editor       = "codium"
local fileExplorer = "thunar"

local sensitivity  = 0.3
local accelProfile = "flat"
local kbOptions    = "grp:win_space_toggle, ctrl:nocaps"

-- NOTE: gaps, border size, rounding, blur, tiling layout, kb_layout and the
-- animation set are NOT set here — the end4-pC settings app owns them and
-- writes them to overrides/main.lua + overrides/animations.lua, which are
-- loaded at the bottom of this file. Its Hyprland page rewrites main.lua from
-- ~/.config/illogical-impulse-pC/config.json on every open, so setting them
-- here would only be overwritten. Change them in the app (SUPER + I), or seed
-- them in scripts/patch-end4pc.sh.

-- Default monitor conf (overridden by monitors.lua once the app's Displays
-- page has been used)
hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = 1,
})

-- Modules
require("hyprland.env")
require("hyprland.input")
require("hyprland.scrolling")
require("hyprland.misc")
require("hyprland.rules")
require("hyprland.execs")
require("hyprland.keybinds")

-- Files owned by the end4-pC shell rather than by this config, loaded last so
-- they win over everything above:
--   colors.lua              matugen (~/.config/matugen-end4pc), on every
--                           wallpaper/scheme change — border colours follow it
--   monitors.lua            settings app, Displays page
--   overrides/main.lua      settings app, Hyprland page
--   overrides/animations.lua  settings app, animation preset picker
--
-- All four are absent until the app (or matugen) has written them, hence the
-- loadfile guard. Explicit paths rather than require(): hyprland.lua's
-- add_to_package_path appends this dir AFTER ~/.config/hypr, so bare module
-- names like "monitors" would resolve ambiguously.
local end4pcDir = os.getenv("HOME") .. "/.config/hypr/shells/end4pc"
local function loadIfPresent(rel)
    local chunk = loadfile(end4pcDir .. "/" .. rel)
    if chunk then chunk() end
end

loadIfPresent("colors.lua")
loadIfPresent("monitors.lua")
loadIfPresent("overrides/main.lua")
loadIfPresent("overrides/animations.lua")
