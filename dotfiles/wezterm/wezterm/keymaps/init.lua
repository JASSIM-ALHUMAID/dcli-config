local M = {}

-- Compose leader keymaps from focused groups.
function M.apply(config, wezterm, workspaces, constants, helpers)
	config.leader = { key = "a", mods = "CTRL", timeout_milliseconds = 2000 }
	config.keys = {}

	require("wezterm.keymaps.general").append(config.keys, wezterm)
	require("wezterm.keymaps.workspaces").append(config.keys, wezterm, workspaces)
	require("wezterm.keymaps.tabs").append(config.keys, wezterm, workspaces, constants, helpers)
	require("wezterm.keymaps.panes").append(config.keys, wezterm, constants, helpers)
	require("wezterm.keymaps.shortcuts").append(config.keys, constants, helpers)
	require("wezterm.keymaps.commands").append(config.keys, wezterm, workspaces, constants, helpers)
	require("wezterm.keymaps.projects").append(config.keys, wezterm, workspaces, constants)
	require("wezterm.keymaps.help").append(config.keys, wezterm)
	require("wezterm.keymaps.search").append(config.keys)
	require("wezterm.keymaps.tab_bar").append(config.keys, wezterm)

	for i = 1, 9 do
		table.insert(config.keys, {
			key = tostring(i),
			mods = "LEADER",
			action = wezterm.action.ActivateTab(i - 1),
		})
	end

	config.key_tables = require("wezterm.keymaps.tables").build(wezterm)
end

return M
