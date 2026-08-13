-- ~/.config/hypr/shells/ambxst-overrides.lua
-- Local overrides applied after ambxst's own hyprland.lua

hl.monitor({
	output = "",
	mode = "preferred",
	position = "auto",
	scale = 1,
})

hl.config({
	scrolling = {
		column_width = 0.85,
		explicit_column_widths = "0.35, 0.5, 0.65, 0.95, 1.0",
	},
	input = {
		kb_layout = "us,ara",
		kb_variant = "",
		kb_options = "grp:win_space_toggle, ctrl:nocaps",
		sensitivity = 0.3,
		accel_profile = "flat",
		repeat_delay = 250,
		repeat_rate = 25,
	},
	gestures = {
		workspace_swipe_create_new = true,
		workspace_swipe_forever = true,
		workspace_swipe_distance = 250,
	},
})

hl.curve("standard", { type = "bezier", points = { { 0.2, 0 }, { 0, 1 } } })
hl.animation({ leaf = "workspaces", enabled = true, speed = 5, bezier = "standard", style = "slidevert" })

hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
