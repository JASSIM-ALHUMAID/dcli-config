-- omarchy house layer — animations
-- omarchy ships workspace transitions disabled (looknfeel.lua: workspaces,
-- enabled = false). Enable the vertical slide, on omarchy's own curve.
-- Loaded after default.hypr.omarchy, so this wins; hyprmod.lua still loads
-- last — if a HyprMod save ever reintroduces a workspaces animation entry,
-- it overrides this file.

hl.animation({ leaf = "workspaces", enabled = true, speed = 6, bezier = "easeOutQuint", style = "slidevert" })
