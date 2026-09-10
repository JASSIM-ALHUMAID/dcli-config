-- House overrides for end4 input settings
-- These override the upstream defaults with our keyboard preferences

hl.config({
    input = {
        kb_layout     = "us,ara",
        kb_variant    = "",
        kb_options    = "grp:win_space_toggle, ctrl:nocaps",
        sensitivity   = 0.3,
        accel_profile = "flat",
    },
})

-- House override: scrolling layout (was dwindle upstream)
hl.config({
    general = {
        layout = "scrolling",
    },
})

hl.config({
    scrolling = {
        column_width           = 0.85,
        explicit_column_widths = "0.35, 0.5, 0.65, 0.95, 1.0",
    },
})

-- House override: gestures like caelestia
-- Upstream end4 uses 3-finger swipe/pinch for move/fullscreen and 4-finger
-- up/down for overview. Caelestia uses 3-up/3-down for special workspace and
-- 4-down for sleep, with no generic swipe/pinch (which would double-fire with
-- the directional ones). Unset the upstream set, then apply caelestia's.
hl.config({
    gestures = {
        workspace_swipe_distance                 = 700,
        workspace_swipe_cancel_ratio             = 0.15,
        workspace_swipe_min_speed_to_force       = 5,
        workspace_swipe_direction_lock           = true,
        workspace_swipe_direction_lock_threshold = 10,
        workspace_swipe_create_new               = true,
    },
})

hl.gesture({ fingers = 3, direction = "swipe", action = "unset" })
hl.gesture({ fingers = 3, direction = "pinch", action = "unset" })
hl.gesture({ fingers = 4, direction = "up", action = "unset" })
hl.gesture({ fingers = 4, direction = "down", action = "unset" })

hl.gesture({ fingers = 4, direction = "horizontal", action = "workspace" })
hl.gesture({ fingers = 3, direction = "up", action = "special", workspace_name = "special" })
hl.gesture({
    fingers   = 3,
    direction = "down",
    action    = function()
        local active = hl.get_active_special_workspace()
        local target = active and active.name:gsub("^special:", "") or "special"
        hl.dispatch(hl.dsp.workspace.toggle_special(target))
    end,
})
hl.gesture({
    fingers   = 4,
    direction = "down",
    action    = function()
        hl.exec_cmd("systemctl suspend-then-hibernate")
    end,
})
