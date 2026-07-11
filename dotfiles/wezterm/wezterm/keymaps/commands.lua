local M = {}

-- Fuzzy launcher for common terminal workflows.
function M.append(keys, wezterm, workspaces, constants, helpers)
	local act = wezterm.action

	local commands = {
		{
			id = "new-workspace-same-cwd",
			label = "New workspace (same cwd)",
			run = function(window, pane)
				workspaces.new_workspace_same_cwd(window, pane)
			end,
		},
		{
			id = "clone-workspace",
			label = "Clone current workspace",
			run = function(window, pane)
				workspaces.clone_current_workspace(window, pane)
			end,
		},
		{
			id = "workspace-menu",
			label = "Workspace menu",
			run = function(window, pane)
				workspaces.workspace_menu(window, pane)
			end,
		},
		{
			id = "save-workspace",
			label = "Save current workspace",
			run = function(window, pane)
				workspaces.save_workspace(window, pane)
			end,
		},
		{
			id = "save-close-workspace",
			label = "Save and close current workspace",
			run = function(window, pane)
				workspaces.save_and_close_current_workspace(window, pane)
			end,
		},
		{
			id = "delete-workspace",
			label = "Delete saved workspace",
			run = function(window, pane)
				workspaces.delete_workspace_menu(window, pane)
			end,
		},
		{
			id = "edit-wezterm",
			label = "Edit WezTerm config",
			action = helpers.send_line('nvim "' .. constants.CONFIG_DIR .. '"'),
		},
		{
			id = "wezterm-config-dir",
			label = "cd WezTerm config",
			action = helpers.quick_cd(constants.CONFIG_DIR),
		},
		{
			id = "nvim-here",
			label = "Open nvim here",
			action = helpers.send_line("nvim ."),
		},
		{
			id = "nvim",
			label = "nvim",
			action = helpers.send_line('nvim "' .. constants.CONFIG_DIR .. '"'),
		},
		{
			id = "opencode",
			label = "opencode",
			action = helpers.send_line("opencode"),
		},
		{
			id = "command-palette",
			label = "WezTerm command palette",
			action = act.ActivateCommandPalette,
		},
		{
			id = "reload-config",
			label = "Reload WezTerm config",
			run = function(window, pane)
				window:perform_action(act.ReloadConfiguration, pane)
				window:toast_notification("WezTerm", "Config reloaded", nil, 2000)
			end,
		},
	}

	local by_id = {}
	local choices = {}
	for _, command in ipairs(commands) do
		by_id[command.id] = command
		table.insert(choices, { id = command.id, label = command.label })
	end

	table.insert(keys, {
		key = "m",
		mods = "LEADER",
		action = act.InputSelector({
			title = "Command launcher",
			description = "Run a common WezTerm workflow",
			fuzzy_description = "Command: ",
			fuzzy = true,
			choices = choices,
			action = wezterm.action_callback(function(window, pane, id)
				local command = id and by_id[id]
				if not command then
					return
				end

				if command.run then
					command.run(window, pane)
				else
					window:perform_action(command.action, pane)
				end
			end),
		}),
	})
end

return M
