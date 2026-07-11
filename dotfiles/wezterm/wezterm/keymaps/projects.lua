local project_source = require("wezterm.projects")

local M = {}

-- Project launcher: switch to a named workspace and start in its root.
-- The menu is built on each press so saved workspaces appear without a reload.
function M.append(keys, wezterm, workspaces, constants)
	local act = wezterm.action

	local function select_project(window, pane, by_id, id)
		local project = id and by_id[id]
		if not project then
			return
		end

		local current_workspace = window:active_workspace()
		if current_workspace ~= project.workspace and current_workspace ~= constants.DEFAULT_WORKSPACE then
			workspaces.save_workspace_by_name(current_workspace)
		end

		for _, name in ipairs(workspaces.get_mux_workspace_names()) do
			if name == project.workspace then
				window:perform_action(act.SwitchToWorkspace({ name = project.workspace }), pane)
				workspaces.touch_workspace_order(project.workspace)
				return
			end
		end

		if workspaces.restore_workspace_by_name(project.workspace) then
			workspaces.touch_workspace_order(project.workspace)
			window:perform_action(act.SwitchToWorkspace({ name = project.workspace }), pane)
			return
		end

		window:perform_action(
			act.SwitchToWorkspace({
				name = project.workspace,
				spawn = { cwd = project.path },
			}),
			pane
		)
		workspaces.touch_workspace_order(project.workspace)
	end

	table.insert(keys, {
		key = "P",
		mods = "LEADER|SHIFT",
		action = wezterm.action_callback(function(window, pane)
			local by_id = {}
			local choices = {}
			for _, project in ipairs(project_source.list(wezterm, constants)) do
				by_id[project.id] = project
				table.insert(choices, {
					id = project.id,
					label = project.label .. "  ->  " .. project.workspace,
				})
			end

			window:perform_action(
				act.InputSelector({
					title = "Project workspace",
					description = "Switch to a project workspace",
					fuzzy_description = "Project: ",
					fuzzy = true,
					choices = choices,
					action = wezterm.action_callback(function(inner_window, inner_pane, id)
						select_project(inner_window, inner_pane, by_id, id)
					end),
				}),
				pane
			)
		end),
	})
end

return M
