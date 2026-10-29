-- ~/.config/hypr/shells/ambxst-overrides.lua
-- Local overrides applied after ambxst's own hyprland.lua

require("common.monitor")
require("common.input")
require("common.scrolling")
require("common.workspace-slide")
require("common.gestures")

-- Each setting appears once: a later duplicate would silently win over this.
hl.config({
    input = {
        kb_variant   = "",
        repeat_delay = 250,
        repeat_rate  = 25,
    },
    gestures = {
        workspace_swipe_create_new = true,
        workspace_swipe_forever    = true,
        workspace_swipe_distance   = 250,
    },
})
