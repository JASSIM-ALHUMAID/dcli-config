local wezterm = require('wezterm')
local Cells = require('wezterm.utils.cells')
local helpers = require('wezterm.helpers')
local constants = require('wezterm.constants')
local theme = require('wezterm.theme')

local nf = wezterm.nerdfonts
local act = wezterm.action
local attr = Cells.attr

local M = {}

---@type table<string, Cells.SegmentColors>
local colors = {
	label_text   = { fg = theme.tab_bar.fg },
	icon_default = { fg = theme.tab_bar.active_bg },
	icon_pwsh    = { fg = theme.custom_colors.red },
}

local cells = Cells:new()
	:add_segment('icon_default', ' ' .. nf.oct_terminal .. ' ', colors.icon_default)
	:add_segment('icon_pwsh', ' ' .. nf.md_powershell .. ' ', colors.icon_pwsh)
	:add_segment('label_text', '', colors.label_text, attr(attr.intensity('Bold')))

local function build_choices()
	local choices = {}
	local choices_data = {}

	-- Fish (default)
	cells:update_segment_text('label_text', 'fish')
	table.insert(choices, {
		id = '1',
		label = wezterm.format(cells:render({ 'icon_default', 'label_text' })),
	})
	table.insert(choices_data, { args = helpers.win_fish_prog() })

	-- PowerShell
	cells:update_segment_text('label_text', 'PowerShell')
	table.insert(choices, {
		id = '2',
		label = wezterm.format(cells:render({ 'icon_pwsh', 'label_text' })),
	})
	table.insert(choices_data, { args = helpers.win_pwsh_prog() })

	return choices, choices_data
end

local choices, choices_data = build_choices()

M.setup = function()
	wezterm.on('new-tab-button-click', function(window, pane, button, default_action)
		if default_action and button == 'Left' then
			window:perform_action(default_action, pane)
		end

		if button == 'Right' then
			window:perform_action(
				act.InputSelector({
					title = 'Launch Menu',
					choices = choices,
					fuzzy = true,
					fuzzy_description = nf.md_rocket .. ' Select a shell: ',
					action = wezterm.action_callback(function(_window, _pane, id, label)
						if not id and not label then
							return
						end
						window:perform_action(act.SpawnCommandInNewTab(choices_data[tonumber(id)]), pane)
					end),
				}),
				pane
			)
		end

		return false
	end)
end

return M
