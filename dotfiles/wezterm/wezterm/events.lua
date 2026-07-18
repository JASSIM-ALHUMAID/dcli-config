local helpers = require("wezterm.helpers")
local tab_bar = require("wezterm.tab_bar")
local tab_title = require("wezterm.events.tab-title")
local new_tab_button = require("wezterm.events.new-tab-button")

local M = {}

local function get_battery_text(wezterm)
	local ok, batteries = pcall(wezterm.battery_info)
	if not ok or type(batteries) ~= "table" or not batteries[1] then
		return nil
	end

	local charge = batteries[1].state_of_charge
	if type(charge) ~= "number" then
		return nil
	end

	local state = batteries[1].state
	local plugged_in = state == "Charging" or state == "Full"
	local icon = plugged_in and wezterm.nerdfonts.md_power_plug or wezterm.nerdfonts.md_battery

	return {
		icon = icon,
		text = tostring(math.floor((charge * 100) + 0.5)) .. "%",
	}
end

-- Register WezTerm event handlers.
function M.register(wezterm, workspaces, constants)
	tab_title.setup({})
	new_tab_button.setup()

	wezterm.on("update-status", function(window, pane)
		tab_bar.update(window)

		local stat = window:active_workspace()
		workspaces.touch_workspace_order(stat)
		workspaces.sync_workspace_order()

		local stat_color = constants.status_colors.workspace
		local leader_active = false
		if window:active_key_table() then
			stat = window:active_key_table()
			stat_color = constants.status_colors.mode
		end
		if window:leader_is_active() then
			stat = "LDR"
			stat_color = constants.status_colors.leader
			leader_active = true
		end

		local cwd_uri = pane:get_current_working_dir()
		local cwd = cwd_uri and helpers.basename(cwd_uri.file_path) or ""
		local cmd = helpers.basename(pane:get_foreground_process_name())
		local time = wezterm.strftime("%H:%M")
		local battery = get_battery_text(wezterm)

		local left_status
		if leader_active then
			-- Filled pill, like the focused tab: accent background + contrasting text.
			left_status = {
				{ Foreground = { Color = constants.status_colors.leader_fg } },
				{ Background = { Color = constants.status_colors.leader } },
				{ Attribute = { Intensity = "Bold" } },
				{ Text = "  " .. wezterm.nerdfonts.oct_table .. "  " .. stat .. "  " },
				"ResetAttributes",
				{ Foreground = { Color = constants.status_colors.leader } },
				{ Text = " |" },
			}
		else
			left_status = {
				{ Foreground = { Color = stat_color } },
				{ Text = "  " },
				{ Text = wezterm.nerdfonts.oct_table .. "  " .. stat },
				{ Text = " |" },
			}
		end
		window:set_left_status(wezterm.format(left_status))

		local right_status = {
			{ Foreground = { Color = constants.status_colors.cwd } },
			{ Text = wezterm.nerdfonts.md_folder .. "  " .. cwd },
			{ Text = " | " },
			{ Foreground = { Color = constants.status_colors.process } },
			{ Text = wezterm.nerdfonts.fa_code .. "  " .. cmd },
			{ Text = " | " },
			{ Foreground = { Color = constants.status_colors.clock } },
			{ Text = wezterm.nerdfonts.md_clock .. "  " .. time },
		}

		if battery then
			table.insert(right_status, { Text = " | " })
			table.insert(right_status, { Foreground = { Color = constants.status_colors.battery } })
			table.insert(right_status, { Text = battery.icon .. "  " .. battery.text })
		end

		table.insert(right_status, { Text = "  " })
		window:set_right_status(wezterm.format(right_status))
	end)

	wezterm.on("window-close-requested", function(window)
		local current_workspace = window:active_workspace()
		local fallback_workspace = workspaces.get_loaded_fallback_workspace_name(current_workspace)

		-- NOTE: do NOT save the workspace here. This handler fires while the
		-- last pane is being torn down (e.g. LEADER x on the final pane), and
		-- serializing a pane whose process/pty is mid-destruction races and can
		-- crash or hang WezTerm. Saves happen on workspace switch and LEADER S.
		workspaces.remove_workspace_from_order(current_workspace)

		if fallback_workspace then
			window:perform_action(wezterm.action.SwitchToWorkspace({ name = fallback_workspace }), window:active_pane())
			workspaces.touch_workspace_order(fallback_workspace)
			wezterm.time.call_after(0.1, function()
				workspaces.close_loaded_workspace(current_workspace)
			end)
			return false
		end
	end)
end

return M
