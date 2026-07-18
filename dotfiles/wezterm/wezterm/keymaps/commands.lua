local tab_bar = require("wezterm.tab_bar")

local M = {}

-- Fuzzy launcher for every leader-driven workflow. Each entry mirrors a real
-- keybinding (see the sibling keymap modules) so the launcher stays a complete,
-- searchable index of what LEADER can do. Labels carry the key hint for recall.
function M.append(keys, wezterm, workspaces, constants, helpers)
	local act = wezterm.action

	-- The raw cwd of a pane, tolerating both the string and Url shapes WezTerm
	-- returns across versions. Mirrors the pane-spawn helpers in tabs/panes.
	local function pane_cwd(pane)
		local uri = pane:get_current_working_dir()
		if not uri then
			return nil
		end
		local raw = type(uri) == "string" and uri or uri.file_path
		if not raw or raw == "" then
			return nil
		end
		return raw
	end

	-- New tab inheriting the current pane's shell and cwd (mirrors LEADER c).
	local function new_tab(window, pane)
		local shell = helpers.detect_shell(pane:get_foreground_process_name())
		local args = helpers.spawn_args(shell, pane_cwd(pane), constants)
		window:perform_action(act.SpawnCommandInNewTab({ args = args }), pane)
	end

	-- Split inheriting the current pane's shell and cwd (mirrors LEADER [ / ]).
	local function split(window, pane, direction)
		local shell = helpers.detect_shell(pane:get_foreground_process_name())
		local args = helpers.spawn_args(shell, pane_cwd(pane), constants)
		local split_action = direction == "Vertical" and act.SplitVertical or act.SplitHorizontal
		window:perform_action(split_action({ args = args, domain = "CurrentPaneDomain" }), pane)
	end

	-- Kill the foreground process, then close the pane (mirrors LEADER x).
	local function kill_pane(window, pane)
		window:perform_action(act.SendKey({ key = "c", mods = "CTRL" }), pane)
		wezterm.time.call_after(0.05, function()
			window:perform_action(act.CloseCurrentPane({ confirm = false }), pane)
		end)
	end

	local commands = {
		-- Workspaces
		{
			id = "workspace-menu",
			label = "Workspaces  Workspace menu               LEADER s",
			run = function(window, pane)
				workspaces.workspace_menu(window, pane)
			end,
		},
		{
			id = "new-workspace-same-cwd",
			label = "Workspaces  New workspace (same cwd)",
			run = function(window, pane)
				workspaces.new_workspace_same_cwd(window, pane)
			end,
		},
		{
			id = "clone-workspace",
			label = "Workspaces  Clone current workspace",
			run = function(window, pane)
				workspaces.clone_current_workspace(window, pane)
			end,
		},
		{
			id = "save-workspace",
			label = "Workspaces  Save current workspace        LEADER S",
			run = function(window, pane)
				workspaces.save_workspace(window, pane)
			end,
		},
		{
			id = "save-close-workspace",
			label = "Workspaces  Save and close workspace       LEADER Q",
			run = function(window, pane)
				workspaces.save_and_close_current_workspace(window, pane)
			end,
		},
		{
			id = "close-workspace",
			label = "Workspaces  Close workspace (no save)      LEADER Ctrl+q",
			run = function(window, pane)
				workspaces.close_current_workspace(window, pane)
			end,
		},
		{
			id = "rename-workspace",
			label = "Workspaces  Rename workspace               LEADER R",
			action = workspaces.rename_workspace(),
		},
		{
			id = "delete-workspace",
			label = "Workspaces  Delete saved workspace         LEADER D",
			run = function(window, pane)
				workspaces.delete_workspace_menu(window, pane)
			end,
		},

		-- Tabs
		{
			id = "new-tab",
			label = "Tabs        New tab                       LEADER c",
			run = new_tab,
		},
		{
			id = "tab-navigator",
			label = "Tabs        Tab navigator                 LEADER w",
			action = act.ShowTabNavigator,
		},
		{
			id = "next-tab",
			label = "Tabs        Next tab                      LEADER n",
			action = act.ActivateTabRelative(1),
		},
		{
			id = "prev-tab",
			label = "Tabs        Previous tab                  LEADER p",
			action = act.ActivateTabRelative(-1),
		},
		{
			id = "rename-tab",
			label = "Tabs        Rename tab                    LEADER ,",
			action = workspaces.rename_tab_title(),
		},
		{
			id = "move-tab-mode",
			label = "Tabs        Move tab mode                 LEADER .",
			action = act.ActivateKeyTable({ name = "move_tab", one_shot = false }),
		},
		{
			id = "toggle-tab-bar",
			label = "Tabs        Toggle bottom tab bar         LEADER t",
			run = function(window, _)
				tab_bar.toggle(window)
			end,
		},

		-- Panes
		{
			id = "split-right",
			label = "Panes       Split pane right              LEADER [",
			run = function(window, pane)
				split(window, pane, "Horizontal")
			end,
		},
		{
			id = "split-down",
			label = "Panes       Split pane down               LEADER ]",
			run = function(window, pane)
				split(window, pane, "Vertical")
			end,
		},
		{
			id = "pane-left",
			label = "Panes       Focus pane left               LEADER h",
			action = act.ActivatePaneDirection("Left"),
		},
		{
			id = "pane-down",
			label = "Panes       Focus pane down               LEADER j",
			action = act.ActivatePaneDirection("Down"),
		},
		{
			id = "pane-up",
			label = "Panes       Focus pane up                 LEADER k",
			action = act.ActivatePaneDirection("Up"),
		},
		{
			id = "pane-right",
			label = "Panes       Focus pane right              LEADER l",
			action = act.ActivatePaneDirection("Right"),
		},
		{
			id = "rotate-panes",
			label = "Panes       Rotate panes clockwise        LEADER Space",
			action = act.RotatePanes("Clockwise"),
		},
		{
			id = "resize-pane-mode",
			label = "Panes       Resize pane mode              LEADER r",
			action = act.ActivateKeyTable({ name = "resize_pane", one_shot = false }),
		},
		{
			id = "zoom-pane",
			label = "Panes       Zoom pane                     LEADER z",
			action = act.TogglePaneZoomState,
		},
		{
			id = "kill-pane",
			label = "Panes       Kill process and close pane   LEADER x",
			run = kill_pane,
		},
		{
			id = "move-pane-new-tab",
			label = "Panes       Move pane to new tab          LEADER !",
			run = function(_, pane)
				pane:move_to_new_tab()
			end,
		},

		-- Search / scrollback
		{
			id = "search",
			label = "Search      Search scrollback             LEADER /",
			action = act.Search("CurrentSelectionOrEmptyString"),
		},
		{
			id = "copy-mode",
			label = "Search      Copy mode                     LEADER y",
			action = act.ActivateCopyMode,
		},
		{
			id = "clear-scrollback",
			label = "Search      Clear scrollback              LEADER C",
			action = act.ClearScrollback("ScrollbackAndViewport"),
		},
		{
			id = "scroll-page-up",
			label = "Search      Scroll page up                LEADER PageUp",
			action = act.ScrollByPage(-1),
		},
		{
			id = "scroll-page-down",
			label = "Search      Scroll page down              LEADER PageDown",
			action = act.ScrollByPage(1),
		},

		-- General
		{
			id = "command-palette",
			label = "General     WezTerm command palette       LEADER ;",
			action = act.ActivateCommandPalette,
		},
		{
			id = "fullscreen",
			label = "General     Toggle fullscreen             LEADER F",
			action = act.ToggleFullScreen,
		},
		{
			id = "reload-config",
			label = "General     Reload WezTerm config         LEADER Ctrl+r",
			run = function(window, pane)
				window:perform_action(act.ReloadConfiguration, pane)
				window:toast_notification("WezTerm", "Config reloaded", nil, 2000)
			end,
		},

		-- Config / apps
		{
			id = "edit-wezterm",
			label = "Config      Edit WezTerm config",
			action = helpers.send_line('nvim "' .. constants.CONFIG_DIR .. '"'),
		},
		{
			id = "wezterm-config-dir",
			label = "Config      cd WezTerm config",
			action = helpers.quick_cd(constants.CONFIG_DIR),
		},
		{
			id = "nvim-here",
			label = "Apps        Open nvim here",
			action = helpers.send_line("nvim ."),
		},
		{
			id = "opencode",
			label = "Apps        opencode",
			action = helpers.send_line("opencode"),
		},
	}

	-- Shell launchers vary by platform (mirrors LEADER g / G in shortcuts.lua).
	if constants.is_windows then
		table.insert(commands, {
			id = "new-fish-tab",
			label = "Shells      New fish tab                  LEADER g",
			action = act.SpawnCommandInNewTab({ args = helpers.win_fish_prog() }),
		})
		table.insert(commands, {
			id = "new-pwsh-tab",
			label = "Shells      New pwsh tab                  LEADER G",
			action = act.SpawnCommandInNewTab({ args = helpers.win_pwsh_prog() }),
		})
	else
		local sh = os.getenv("SHELL") or (constants.is_darwin and "/bin/zsh" or "/bin/bash")
		table.insert(commands, {
			id = "new-shell-tab",
			label = "Shells      New shell tab                 LEADER g",
			action = act.SpawnCommandInNewTab({ args = { sh, "-l" } }),
		})
	end

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
