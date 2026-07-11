local Module = {}

-- Workspace ordering and fallback selection.
function Module.attach(M, ctx)
	local wezterm = ctx.wezterm
	local constants = ctx.constants
	local state = ctx.state

	function M.get_mux_workspace_names()
		local seen = {}
		local names = {}

		for _, mux_win in ipairs(wezterm.mux.all_windows()) do
			local workspace = mux_win:get_workspace()
			if workspace and workspace ~= "" and not seen[workspace] then
				seen[workspace] = true
				table.insert(names, workspace)
			end
		end

		table.sort(names)
		return names
	end

	function M.remove_workspace_from_order(workspace_name)
		for i = #state.workspace_order, 1, -1 do
			if state.workspace_order[i] == workspace_name then
				table.remove(state.workspace_order, i)
			end
		end
	end

	function M.touch_workspace_order(workspace_name)
		if not workspace_name or workspace_name == "" then
			return
		end

		M.remove_workspace_from_order(workspace_name)
		table.insert(state.workspace_order, workspace_name)
	end

	function M.sync_workspace_order(excluded_workspaces)
		excluded_workspaces = excluded_workspaces or {}

		local loaded = {}
		for _, name in ipairs(M.get_mux_workspace_names()) do
			if not excluded_workspaces[name] then
				loaded[name] = true
			end
		end

		if not excluded_workspaces[constants.DEFAULT_WORKSPACE] then
			loaded[constants.DEFAULT_WORKSPACE] = true
		end

		for i = #state.workspace_order, 1, -1 do
			if not loaded[state.workspace_order[i]] then
				table.remove(state.workspace_order, i)
			end
		end

		for name, _ in pairs(loaded) do
			local found = false
			for _, existing in ipairs(state.workspace_order) do
				if existing == name then
					found = true
					break
				end
			end
			if not found then
				table.insert(state.workspace_order, name)
			end
		end
	end

	function M.get_fallback_workspace_name(current_workspace, excluded_workspaces)
		M.sync_workspace_order(excluded_workspaces)

		for i = #state.workspace_order, 1, -1 do
			local name = state.workspace_order[i]
			if name ~= current_workspace and not (excluded_workspaces and excluded_workspaces[name]) then
				return name
			end
		end

		return constants.DEFAULT_WORKSPACE
	end

	function M.get_loaded_fallback_workspace_name(current_workspace)
		local loaded = {}
		for _, name in ipairs(M.get_mux_workspace_names()) do
			if name ~= current_workspace then
				loaded[name] = true
			end
		end

		for i = #state.workspace_order, 1, -1 do
			local name = state.workspace_order[i]
			if loaded[name] then
				return name
			end
		end

		for name, _ in pairs(loaded) do
			return name
		end

		return nil
	end
end

return Module
