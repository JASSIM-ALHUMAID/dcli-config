-- House keyboard and pointer preferences. Loaded by the shells that own their
-- whole Hyprland config; caelestia keeps its own in its fork's hypr-vars.lua.
-- Shell-specific input keys (kb_variant, repeat rates, touchpad) go in the shell
-- file after this one: hl.config merges, so later keys win.
hl.config({
    input = {
        kb_layout     = "us,ara",
        kb_options    = "grp:win_space_toggle, ctrl:nocaps",
        sensitivity   = 0.3,
        accel_profile = "flat",
    },
})
