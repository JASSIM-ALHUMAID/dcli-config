hl.config({
    animations = {
        enabled = true,
    },
})

hl.curve("standard", { type = "bezier", points = { { 0.2, 0 }, { 0, 1 } } })
hl.animation({ leaf = "workspaces", enabled = true, speed = 5, bezier = "standard", style = "slidevert" })
