-- ~/.config/hypr/shells/dms/hyprland.lua
-- DMS (DankMaterialShell) — Hyprland Lua config

-- Modules are fully qualified: ~/.config/hypr/hyprland/ is a real directory
-- other shells' upstreams write into, so a bare "hyprland.<name>" could be
-- shadowed there. Preferences shared by every standalone shell are in
-- ~/.config/hypr/common/.
require("common.monitor")

require("shells.dms.hyprland.env")
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
require("shells.dms.hyprland.execs")
require("shells.dms.hyprland.keybinds")

-- DMS theming (loaded last). Deliberately the SHARED ~/.config/hypr/dms/colors.lua
-- (DMS writes it there), not a shells/dms copy.
pcall(require, "dms.colors")
