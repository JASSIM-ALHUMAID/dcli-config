-- omarchy house layer — input
-- omarchy's default/hypr/input.lua derives kb_layout from /etc/vconsole.conf
-- and sets kb_options to "compose:caps,shift:both_capslock_cancel", which loses
-- both the Arabic layout and ctrl:nocaps. Re-assert the house settings; hl.config
-- merges, so the touchpad/repeat defaults it set survive.

hl.config({
    input = {
        kb_layout     = "us,ara",
        kb_variant    = "",
        kb_options    = "grp:win_space_toggle, ctrl:nocaps",
        sensitivity   = 0.3,
        accel_profile = "flat",
    },
})
