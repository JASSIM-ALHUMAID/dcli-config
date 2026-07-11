local M = {}

-- Compose appearance settings from smaller modules.
function M.apply(config, wezterm, constants)
	require("wezterm.appearance.base").apply(config, wezterm, constants)
	require("wezterm.appearance.fonts").apply(config, wezterm)
	require("wezterm.appearance.window").apply(config, wezterm)
	require("wezterm.appearance.colors").apply(config, constants)
end

return M
