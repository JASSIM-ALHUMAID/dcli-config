local act = require("wezterm").action

local M = {}

-- Tab management bindings.
function M.append(keys, wezterm, workspaces, constants, helpers)
	table.insert(keys, { key = "w", mods = "LEADER", action = act.ShowTabNavigator })
	table.insert(keys, {
		key = "c",
		mods = "LEADER",
		action = wezterm.action_callback(function(window, pane)
			local cwd_uri = pane:get_current_working_dir()
			local cwd = nil
			if cwd_uri then
				local raw = type(cwd_uri) == "string" and cwd_uri or cwd_uri.file_path
				if raw and raw ~= "" then
					cwd = raw
				end
			end
			local shell = helpers.detect_shell(pane:get_foreground_process_name())
			local args = helpers.spawn_args(shell, cwd, constants)
			window:perform_action(act.SpawnCommandInNewTab({ args = args }), pane)
		end),
	})
	table.insert(keys, { key = "p", mods = "LEADER", action = act.ActivateTabRelative(-1) })
	table.insert(keys, { key = "n", mods = "LEADER", action = act.ActivateTabRelative(1) })
	table.insert(keys, { key = ",", mods = "LEADER", action = workspaces.rename_tab_title() })
	table.insert(keys, { key = ".", mods = "LEADER", action = act.ActivateKeyTable({ name = "move_tab", one_shot = false }) })
end

return M
