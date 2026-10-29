-- Vertical slide between workspaces. Kept apart from animations.lua because
-- ambxst takes this but already owns its animations:enabled.
hl.curve("standard", { type = "bezier", points = { { 0.2, 0 }, { 0, 1 } } })
hl.animation({ leaf = "workspaces", enabled = true, speed = 5, bezier = "standard", style = "slidevert" })
