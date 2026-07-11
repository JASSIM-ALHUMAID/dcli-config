local wezterm = require("wezterm")
local Module = {}

-- TUI programs worth relaunching on restore/clone. Mirrors the list in
-- persistence.lua but kept local to avoid coupling.
local TUI_PROGRAMS = {
	nvim = true,
	vim = true,
	helix = true,
	hx = true,
	yazi = true,
	ranger = true,
	lf = true,
	nnn = true,
	btop = true,
	btop4win = true,
	htop = true,
	top = true,
	btm = true,
	bottom = true,
	lazygit = true,
	gitui = true,
	tig = true,
	lazydocker = true,
	k9s = true,
	ncdu = true,
	claude = true,
	opencode = true,
}

-- Compute the next auto-numbered name for a workspace clone/duplicate.
-- Scans both loaded and saved workspaces for "source-N" (N >= 1).
-- Returns "source-1" if no numbered variant exists, otherwise "source-(max+1)".
local function compute_next_name(list_saved, source)
	local seen = {}
	for _, mux_win in ipairs(wezterm.mux.all_windows()) do
		local name = mux_win:get_workspace()
		if name and name ~= "" then
			seen[name] = true
		end
	end
	for _, name in ipairs(list_saved() or {}) do
		seen[name] = true
	end

	local prefix = source .. "-"
	local max_n = 0
	for name, _ in pairs(seen) do
		local n = tonumber(name:match("^" .. prefix .. "(%d+)$"))
		if n and n >= 1 and n > max_n then
			max_n = n
		end
	end

	if max_n == 0 then
		return source .. "-1"
	end
	return source .. "-" .. tostring(max_n + 1)
end

-- Build spawn arguments for a pane-data entry.
-- pd: { prog (TUI path or nil), shell ("fish"/"pwsh"/nil), cwd (string or nil) }
local function build_pane_args(pd, helpers, constants)
	if not pd then
		return nil
	end

	if constants.is_windows then
		if pd.prog then
			local cd = pd.cwd and ("Set-Location " .. helpers.squote(pd.cwd) .. " ; ") or ""
			return { "pwsh.exe", "-NoLogo", "-NoExit", "-Command", cd .. "& " .. helpers.squote(pd.prog) }
		end

		if pd.shell == "fish" then
			local args = helpers.win_fish_prog()
			if pd.cwd then
				table.insert(args, "-C")
				table.insert(args, "cd " .. helpers.squote(helpers.to_msys_path(pd.cwd)))
			end
			return args
		end

		if pd.cwd then
			return { "pwsh.exe", "-NoLogo", "-NoExit", "-Command", "Set-Location " .. helpers.squote(pd.cwd) }
		end
		return helpers.win_pwsh_prog()
	end

	-- Unix
	local cd = pd.cwd and ("cd " .. helpers.squote(pd.cwd) .. " && ") or ""
	if pd.prog then
		local sh = os.getenv("SHELL") or "/bin/bash"
		return { sh, "-c", cd .. helpers.squote(pd.prog) .. "; exec " .. sh }
	end
	return helpers.spawn_args(pd.shell, pd.cwd, constants)
end

-- Share the TUI list and build helper with clone context.
local function collect_pane_data(pane, helpers)
	local cwd_uri = pane:get_current_working_dir()
	local cwd = cwd_uri and (type(cwd_uri) == "string" and cwd_uri or cwd_uri.file_path) or nil
	if cwd then
		cwd = helpers.normalize_cwd(cwd)
	end

	local fg = pane:get_foreground_process_name()
	local base = fg and (fg:gsub("\\", "/"):match("([^/]+)$") or fg):gsub("%.exe$", ""):lower() or nil
	local prog = base and TUI_PROGRAMS[base] and fg or nil
	local shell = (not prog) and helpers.detect_shell(fg) or nil

	return { cwd = cwd, prog = prog, shell = shell }
end

-- User-facing workspace prompts and selectors.
function Module.attach(M, ctx)
	local wezterm = ctx.wezterm
	local act = ctx.act
	local constants = ctx.constants
	local helpers = ctx.helpers

	function M.switch_workspace(window, pane)
		local loaded_names = M.get_mux_workspace_names()
		local choices = {}

		for _, name in ipairs(loaded_names) do
			table.insert(choices, { id = name, label = name .. "  [loaded]" })
		end

		if #choices == 0 then
			window:toast_notification("WezTerm", "No workspaces found", nil, 2000)
			return
		end

		window:perform_action(
			act.InputSelector({
				title = "Switch workspace",
				description = "Switch to loaded workspace",
				fuzzy_description = "Search workspace: ",
				fuzzy = true,
				choices = choices,
				action = wezterm.action_callback(function(inner_window, inner_pane, id)
					if not id then
						return
					end

					M.touch_workspace_order(id)
					inner_window:perform_action(act.SwitchToWorkspace({ name = id }), inner_pane)
				end),
			}),
			pane
		)
	end

	function M.prompt_create_workspace(window, pane)
		window:perform_action(
			act.PromptInputLine({
				description = "Create workspace:",
				action = wezterm.action_callback(function(inner_window, inner_pane, line)
					if not line or line == "" then
						return
					end

					M.touch_workspace_order(line)
					inner_window:perform_action(act.SwitchToWorkspace({ name = line }), inner_pane)
				end),
			}),
			pane
		)
	end

	function M.workspace_menu(window, pane)
		local loaded_names = M.get_mux_workspace_names()
		local choices = {
			{ id = "__create__", label = "+ Create workspace" },
		}

		for _, name in ipairs(loaded_names) do
			table.insert(choices, { id = name, label = name .. "  [loaded]" })
		end

		window:perform_action(
			act.InputSelector({
				title = "Workspace",
				description = "Switch or create workspace",
				fuzzy_description = "Search workspace: ",
				fuzzy = true,
				choices = choices,
				action = wezterm.action_callback(function(inner_window, inner_pane, id)
					if not id then
						return
					end

					if id == "__create__" then
						M.prompt_create_workspace(inner_window, inner_pane)
						return
					end

					M.touch_workspace_order(id)
					inner_window:perform_action(act.SwitchToWorkspace({ name = id }), inner_pane)
				end),
			}),
			pane
		)
	end

	function M.rename_tab_title()
		return act.PromptInputLine({
			description = wezterm.format({
				{ Attribute = { Intensity = "Bold" } },
				{ Foreground = { AnsiColor = "Fuchsia" } },
				{ Text = "Renaming Tab Title...:" },
			}),
			action = wezterm.action_callback(function(window, _, line)
				if line and line ~= "" then
					window:active_tab():set_title(line)
				end
			end),
		})
	end

	function M.rename_workspace()
		return act.PromptInputLine({
			description = "Rename workspace:",
			action = wezterm.action_callback(function(_, _, line)
				if not line or line == "" then
					return
				end

				local old = wezterm.mux.get_active_workspace()
				if old == line then
					return
				end

				wezterm.mux.rename_workspace(old, line)
				M.remove_workspace_from_order(old)
				M.touch_workspace_order(line)
			end),
		})
	end

	local function toast_saved(window, name, saved)
		window:toast_notification(
			"WezTerm",
			saved and ('Saved workspace "' .. name .. '"') or ('Could not save workspace "' .. name .. '"'),
			nil,
			2000
		)
	end

	-- Pick a saved workspace and delete its state file (with confirmation).
	function M.delete_workspace_menu(window, pane)
		local saved = M.list_saved_workspaces()
		if #saved == 0 then
			window:toast_notification("WezTerm", "No saved workspaces", nil, 2000)
			return
		end

		local choices = {}
		for _, name in ipairs(saved) do
			table.insert(choices, { id = name, label = name })
		end

		window:perform_action(
			act.InputSelector({
				title = "Delete saved workspace",
				description = "Select a saved workspace to delete",
				fuzzy_description = "Delete: ",
				fuzzy = true,
				choices = choices,
				action = wezterm.action_callback(function(inner_window, inner_pane, id)
					if not id then
						return
					end

					inner_window:perform_action(
						act.InputSelector({
							title = 'Delete "' .. id .. '"?',
							description = "This permanently removes the saved session",
							choices = {
								{ id = "yes", label = "Yes, delete" },
								{ id = "no", label = "Cancel" },
							},
							action = wezterm.action_callback(function(confirm_window, _, confirm)
								if confirm ~= "yes" then
									return
								end
								local deleted = M.delete_workspace_by_name(id)
								confirm_window:toast_notification(
									"WezTerm",
									deleted and ('Deleted "' .. id .. '"') or ('Could not delete "' .. id .. '"'),
									nil,
									2000
								)
							end),
						}),
						inner_pane
					)
				end),
			}),
			pane
		)
	end

	-- Persist the active workspace. The default workspace is unnamed, so prompt
	-- for a name (renaming it) before saving.
	function M.save_workspace(window, pane)
		local name = window:active_workspace()

		if name ~= constants.DEFAULT_WORKSPACE then
			toast_saved(window, name, M.save_workspace_by_name(name))
			return
		end

		window:perform_action(
			act.PromptInputLine({
				description = "Name this workspace to save it:",
				action = wezterm.action_callback(function(inner_window, _, line)
					if not line or line == "" then
						return
					end

					local old = inner_window:active_workspace()
					wezterm.mux.rename_workspace(old, line)
					M.remove_workspace_from_order(old)
					M.touch_workspace_order(line)

					toast_saved(inner_window, line, M.save_workspace_by_name(line))
				end),
			}),
			pane
		)
	end
	-- Save the active workspace to disk, then close its window(s) and switch
	-- to the most recently used loaded workspace (or default if none remain).
	function M.save_and_close_current_workspace(window, pane)
		local name = window:active_workspace()

		local function finalize(name)
			M.save_workspace_by_name(name)

			-- Mirror closing the last pane (see window-close-requested): land on
			-- the most-recently-used other loaded workspace, or quit wezterm if
			-- this was the only one left.
			local fallback = M.get_loaded_fallback_workspace_name(name)

			if not fallback then
				M.remove_workspace_from_order(name)
				window:perform_action(act.QuitApplication, pane)
				return
			end

			-- Switch to the fallback workspace first (this properly materializes
			-- headless mux windows instead of spawning duplicates), then close
			-- the current workspace after a brief delay (see window-close-requested).
			M.remove_workspace_from_order(name)
			M.touch_workspace_order(fallback)
			window:perform_action(act.SwitchToWorkspace({ name = fallback }), pane)
			wezterm.time.call_after(0.1, function()
				M.close_loaded_workspace(name)
			end)
		end

		if name == constants.DEFAULT_WORKSPACE then
			window:perform_action(
				act.PromptInputLine({
					description = "Name this workspace to save and close it:",
					action = wezterm.action_callback(function(inner_window, _, line)
						if not line or line == "" then
							return
						end
						local old = inner_window:active_workspace()
						wezterm.mux.rename_workspace(old, line)
						M.remove_workspace_from_order(old)
						M.touch_workspace_order(line)
						finalize(line)
					end),
				}),
				pane
			)
			return
		end

		finalize(name)
	end

	function M.new_workspace_same_cwd(window, pane)
		local source = window:active_workspace()
		local name = compute_next_name(function()
			return M.list_saved_workspaces()
		end, source)

		local pd = collect_pane_data(pane, helpers)
		local args = build_pane_args(pd, helpers, constants)

		local ok, _, mux_win = pcall(wezterm.mux.spawn_window, {
			workspace = name,
			cwd = pd.cwd,
			args = args,
		})

		if not ok or not mux_win then
			window:toast_notification("WezTerm", 'Could not create workspace "' .. name .. '"', nil, 2000)
			return
		end

		M.touch_workspace_order(name)
		window:perform_action(act.SwitchToWorkspace({ name = name }), pane)
	end

	function M.clone_current_workspace(window, pane)
		local source = window:active_workspace()
		local name = compute_next_name(function()
			return M.list_saved_workspaces()
		end, source)

		local source_mux_win
		for _, mw in ipairs(wezterm.mux.all_windows()) do
			if mw:get_workspace() == source then
				source_mux_win = mw
				break
			end
		end

		if not source_mux_win then
			window:toast_notification("WezTerm", 'Could not find source workspace "' .. source .. '"', nil, 2000)
			return
		end

		local tabs_data = {}
		for _, tab in ipairs(source_mux_win:tabs()) do
			local entry = { title = tab:get_title() or "", panes = {} }
			local ok, infos = pcall(function()
				return tab:panes_with_info()
			end)
			if ok and infos then
				for _, info in ipairs(infos) do
					local pd = collect_pane_data(info.pane, helpers)
					pd.active = info.is_active == true
					table.insert(entry.panes, pd)
				end
			end
			if #entry.panes > 0 then
				table.insert(tabs_data, entry)
			end
		end

		if #tabs_data == 0 then
			window:toast_notification("WezTerm", "No tabs to clone", nil, 2000)
			return
		end

		local function pane_split(pane, pd, direction)
			if not pane or not pd then
				return nil
			end
			local args = build_pane_args(pd, helpers, constants)
			local ok2, new_pane = pcall(pane.split, pane, {
				direction = direction,
				cwd = pd.cwd,
				args = args,
			})
			return ok2 and new_pane or nil
		end

		local first = tabs_data[1]
		local first_lead = first.panes[1] or {}

		local ok, spawn_tab, spawn_pane, mux_win = pcall(wezterm.mux.spawn_window, {
			workspace = name,
			cwd = first_lead.cwd,
			args = build_pane_args(first_lead, helpers, constants),
		})

		if not ok or not mux_win then
			window:toast_notification("WezTerm", 'Could not clone workspace "' .. name .. '"', nil, 2000)
			return
		end

		if first.title and first.title ~= "" then
			pcall(spawn_tab.set_title, spawn_tab, first.title)
		end

		local active_pane = spawn_pane
		for i = 2, #first.panes do
			local direction = (i % 2 == 0) and "Right" or "Down"
			local new_pane = pane_split(active_pane, first.panes[i], direction)
			if new_pane then
				if first.panes[i].active then
					active_pane = new_pane
				end
			else
				break
			end
		end
		if active_pane and active_pane ~= spawn_pane then
			pcall(active_pane.activate, active_pane)
		end

		for i = 2, #tabs_data do
			local tab_entry = tabs_data[i]
			local lead = tab_entry.panes[1] or {}
			local ok2, tab, tab_pane = pcall(mux_win.spawn_tab, mux_win, {
				cwd = lead.cwd,
				args = build_pane_args(lead, helpers, constants),
			})
			if ok2 and tab then
				active_pane = tab_pane
				if tab_entry.title and tab_entry.title ~= "" then
					pcall(tab.set_title, tab, tab_entry.title)
				end
				for j = 2, #tab_entry.panes do
					local direction = (j % 2 == 0) and "Right" or "Down"
					local new_pane = pane_split(active_pane, tab_entry.panes[j], direction)
					if new_pane then
						if tab_entry.panes[j].active then
							active_pane = new_pane
						end
					else
						break
					end
				end
				if active_pane and active_pane ~= tab_pane then
					pcall(active_pane.activate, active_pane)
				end
			end
		end

		M.touch_workspace_order(name)
		window:perform_action(act.SwitchToWorkspace({ name = name }), pane)
	end
end

return Module
