-- ~/.config/hypr/shells/ambxst/overrides.lua
-- Local overrides applied after ambxst's own hyprland.lua

require("common.monitor")
require("common.input")
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

-- ambxst's fork binds Super-tap to the launcher on key-press (the axctl
-- LuaGenerator emits no { release = true }), so the launcher fires the instant
-- Super is tapped — intercepting Super+<number> workspace switches. Rebind on
-- release, matching the house pattern shared by every other standalone shell.
hl.unbind("SUPER + Super_L")
hl.bind("SUPER + Super_L", hl.dsp.exec_cmd("ambxst run launcher"), { release = true })
