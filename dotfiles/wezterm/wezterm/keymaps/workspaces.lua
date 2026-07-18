local M = {}

-- Workspace-related leader bindings.
function M.append(keys, wezterm, workspaces)
	table.insert(keys, { key = "s", mods = "LEADER", action = wezterm.action_callback(workspaces.workspace_menu) })
	table.insert(keys, { key = "R", mods = "LEADER|SHIFT", action = workspaces.rename_workspace() })
	table.insert(keys, {
		key = "S",
		mods = "LEADER|SHIFT",
		action = wezterm.action_callback(function(window, pane)
			workspaces.save_workspace(window, pane)
		end),
	})
	table.insert(keys, {
		key = "D",
		mods = "LEADER|SHIFT",
		action = wezterm.action_callback(function(window, pane)
			workspaces.delete_workspace_menu(window, pane)
		end),
	})
	table.insert(keys, {
		key = "Q",
		mods = "LEADER|SHIFT",
		action = wezterm.action_callback(function(window, pane)
			workspaces.save_and_close_current_workspace(window, pane)
		end),
	})
	table.insert(keys, {
		key = "q",
		mods = "LEADER|CTRL",
		action = wezterm.action_callback(function(window, pane)
			workspaces.close_current_workspace(window, pane)
		end),
	})
end

return M
