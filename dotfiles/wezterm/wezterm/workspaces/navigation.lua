local Module = {}

-- Open, focus, and close workspace windows.
function Module.attach(M, ctx)
	local wezterm = ctx.wezterm
	local constants = ctx.constants

	-- Close the GUI window(s) for `workspace_name`, freeing the workspace from
	-- memory. This MUST be called while the workspace still has an attached GUI
	-- window: once the active workspace has been switched away, the workspace's
	-- mux windows go headless, `gui_window()` returns nil, and they can no
	-- longer be closed (the workspace would stay loaded).
	function M.close_loaded_workspace(workspace_name)
		if not workspace_name or workspace_name == "" or workspace_name == constants.DEFAULT_WORKSPACE then
			return
		end

		for _, mux_win in ipairs(wezterm.mux.all_windows()) do
			if mux_win:get_workspace() == workspace_name then
				pcall(function()
					local gui_win = mux_win:gui_window()
					if gui_win then
						gui_win:close()
					end
				end)
			end
		end
	end

	-- Bring up a GUI window for `workspace_name`, spawning one if the workspace
	-- isn't loaded yet. Uses per-window `focus()` rather than the global
	-- `set_active_workspace()` so that other workspaces' windows stay attached
	-- to their own mux windows (and can still be closed afterwards).
	function M.show_workspace_window(workspace_name)
		for _, mux_win in ipairs(wezterm.mux.all_windows()) do
			if mux_win:get_workspace() == workspace_name then
				local ok = pcall(function()
					local gui_win = mux_win:gui_window()
					if gui_win then
						gui_win:focus()
					end
				end)
				if ok then
					return true
				end
			end
		end

		return pcall(function()
			local _, _, mux_win = wezterm.mux.spawn_window({ workspace = workspace_name })
			local gui_win = mux_win and mux_win:gui_window()
			if gui_win then
				gui_win:focus()
			end
		end)
	end

	function M.open_or_focus_workspace(workspace_name)
		if not workspace_name or workspace_name == "" then
			return false
		end

		for _, mux_win in ipairs(wezterm.mux.all_windows()) do
			if mux_win:get_workspace() == workspace_name then
				local ok = pcall(function()
					local gui_win = mux_win:gui_window()
					if gui_win then
						gui_win:focus()
						wezterm.mux.set_active_workspace(workspace_name)
					end
				end)
				if ok then
					return true
				end
			end
		end

		local ok = pcall(function()
			local _, _, mux_win = wezterm.mux.spawn_window({ workspace = workspace_name })
			local gui_win = mux_win and mux_win:gui_window()
			if gui_win then
				gui_win:focus()
			end
			wezterm.mux.set_active_workspace(workspace_name)
		end)

		return ok
	end
end

return Module
