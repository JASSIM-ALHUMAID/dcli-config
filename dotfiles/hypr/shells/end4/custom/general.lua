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
