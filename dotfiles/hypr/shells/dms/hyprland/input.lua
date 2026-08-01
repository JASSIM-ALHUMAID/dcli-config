local sensitivity  = 0.3
local accelProfile = "flat"
local kbLayout     = "us,ara"
local kbOptions    = "grp:win_space_toggle, ctrl:nocaps"

hl.config({
    input = {
        kb_layout    = kbLayout,
        kb_options   = kbOptions,
        sensitivity  = sensitivity,
        accel_profile = accelProfile,
    },
    binds = {
        scroll_event_delay = 0,
        drag_threshold     = 10,
    },
})
