------------------------------------------------------------------------------------------
-- Inspired by https://github.com/wez/wezterm/discussions/628#discussioncomment-1874614 --
------------------------------------------------------------------------------------------

local wezterm = require("wezterm")
local Cells = require("wezterm.utils.cells")
local OptsValidator = require("wezterm.utils.opts-validator")
local ustr = require("wezterm.utils.str")
local theme = require("wezterm.theme")

local nf = wezterm.nerdfonts
local attr = Cells.attr

---@class Event.TabTitleOptionsInput
---@field unseen_icon? 'circle' | 'numbered_circle' | 'numbered_box'
---@field hide_active_tab_unseen? boolean
---@field show_progress? boolean

---@class Event.TabTitleOptions
---@field unseen_icon 'circle' | 'numbered_circle' | 'numbered_box'
---@field hide_active_tab_unseen boolean
---@field show_progress boolean

---@type OptsValidator
local EVENT_OPTS = OptsValidator:new({
	{
		name = "unseen_icon",
		type = "string",
		enum = { "circle", "numbered_circle", "numbered_box" },
		default = "circle",
	},
	{
		name = "hide_active_tab_unseen",
		type = "boolean",
		default = true,
	},
	{
		name = "show_progress",
		type = "boolean",
		default = true,
	},
})

local M = {}

local PROGRESS_MIN_VERSION = 20250209
local PROGRESS_STALE_AFTER = 30

local ICON_SCIRCLE_LEFT = nf.ple_left_half_circle_thick
local ICON_SCIRCLE_RIGHT = nf.ple_right_half_circle_thick

---@enum PrefixIcon
local ICON_PREFIX = {
	admin = nf.md_shield_half_full,
	wsl = nf.cod_terminal_linux,
	debug = nf.fa_bug,
	select = nf.md_selection_search,
	launcher = nf.oct_rocket,
	edit = nf.fa_edit,
}

---@enum UnseenOutputIcon
local ICON_UNSEEN = {
	cirlce = nf.fa_circle,

	numbered_box_1 = nf.md_numeric_1_box_multiple,
	numbered_box_2 = nf.md_numeric_2_box_multiple,
	numbered_box_3 = nf.md_numeric_3_box_multiple,
	numbered_box_4 = nf.md_numeric_4_box_multiple,
	numbered_box_5 = nf.md_numeric_5_box_multiple,
	numbered_box_6 = nf.md_numeric_6_box_multiple,
	numbered_box_7 = nf.md_numeric_7_box_multiple,
	numbered_box_8 = nf.md_numeric_8_box_multiple,
	numbered_box_9 = nf.md_numeric_9_box_multiple,
	numbered_box_10 = nf.md_numeric_9_plus_box_multiple,

	numbered_circle_1 = nf.md_numeric_1_circle,
	numbered_circle_2 = nf.md_numeric_2_circle,
	numbered_circle_3 = nf.md_numeric_3_circle,
	numbered_circle_4 = nf.md_numeric_4_circle,
	numbered_circle_5 = nf.md_numeric_5_circle,
	numbered_circle_6 = nf.md_numeric_6_circle,
	numbered_circle_7 = nf.md_numeric_7_circle,
	numbered_circle_8 = nf.md_numeric_8_circle,
	numbered_circle_9 = nf.md_numeric_9_circle,
	numbered_circle_10 = nf.md_numeric_9_plus_circle,
}

local ICON_PROGRESS_PCT_FRAMES = {
	[1] = nf.md_circle_slice_1,
	[2] = nf.md_circle_slice_2,
	[3] = nf.md_circle_slice_3,
	[4] = nf.md_circle_slice_4,
	[5] = nf.md_circle_slice_5,
	[6] = nf.md_circle_slice_6,
	[7] = nf.md_circle_slice_7,
	[8] = nf.md_circle_slice_8,
}

local ICON_PROGRESS_IND_FRAMES = {
	[1] = "◜",
	[2] = "◠",
	[3] = "◝",
	[4] = "◞",
	[5] = "◡",
	[6] = "◟",
}

local TITLE_INSET = {
	default = 5,
	increment = 2,
}

local RS = {
	scircle_left = 1,
	icon = 2,
	title = 3,
	progress = 4,
	unseen_output = 5,
	padding = 6,
	scircle_right = 7,
}

local RV = {
	{ RS.scircle_left, RS.padding, RS.title, RS.padding, RS.scircle_right },
	{ RS.scircle_left, RS.padding, RS.title, RS.padding, RS.unseen_output, RS.padding, RS.scircle_right },

	{ RS.scircle_left, RS.padding, RS.title, RS.padding, RS.progress, RS.padding, RS.scircle_right },
	{
		RS.scircle_left,
		RS.padding,
		RS.title,
		RS.padding,
		RS.progress,
		RS.padding,
		RS.unseen_output,
		RS.padding,
		RS.scircle_right,
	},

	{ RS.scircle_left, RS.padding, RS.icon, RS.padding, RS.title, RS.padding, RS.scircle_right },
	{
		RS.scircle_left,
		RS.padding,
		RS.icon,
		RS.padding,
		RS.title,
		RS.padding,
		RS.unseen_output,
		RS.padding,
		RS.scircle_right,
	},

	{
		RS.scircle_left,
		RS.padding,
		RS.icon,
		RS.padding,
		RS.title,
		RS.padding,
		RS.progress,
		RS.padding,
		RS.scircle_right,
	},
	{
		RS.scircle_left,
		RS.padding,
		RS.icon,
		RS.padding,
		RS.title,
		RS.padding,
		RS.progress,
		RS.padding,
		RS.unseen_output,
		RS.padding,
		RS.scircle_right,
	},
}

-- Theme-adapted colors using the user's tab_bar and custom_colors from theme.lua
---@type table<string, Cells.SegmentColors>
local colors = {
	-- Tab body: default=near-black, hover=magenta, active=orange (pops!)
	text_default = { bg = theme.tab_bar.default_bg, fg = theme.tab_bar.default_fg },
	text_hover = { bg = theme.tab_bar.hover_bg, fg = theme.tab_bar.hover_fg },
	text_active = { bg = theme.tab_bar.active_bg2, fg = theme.tab_bar.active_fg2 },

	-- Unseen output badge
	unseen_output_default = { bg = theme.tab_bar.default_bg, fg = theme.tab_bar.unseen },
	unseen_output_hover = { bg = theme.tab_bar.hover_bg, fg = theme.tab_bar.unseen },
	unseen_output_active = { bg = theme.tab_bar.active_bg2, fg = theme.tab_bar.unseen },

	-- Half-circle ends: bg matches bar, fg matches tab body
	scircle_default = { bg = theme.tab_bar.bg, fg = theme.tab_bar.default_bg },
	scircle_hover = { bg = theme.tab_bar.bg, fg = theme.tab_bar.hover_bg },
	scircle_active = { bg = theme.tab_bar.bg, fg = theme.tab_bar.active_bg2 },

	-- Right half-circle: mirrors the left cap (tracks tab-body color)
	scircle_right_default = { bg = theme.tab_bar.bg, fg = theme.tab_bar.default_bg },
	scircle_right_hover = { bg = theme.tab_bar.bg, fg = theme.tab_bar.hover_bg },
	scircle_right_active = { bg = theme.tab_bar.bg, fg = theme.tab_bar.active_bg2 },

	-- Progress indicators
	progress_percentage_default = { bg = theme.tab_bar.default_bg, fg = theme.tab_bar.progress_ok },
	progress_percentage_hover = { bg = theme.tab_bar.hover_bg, fg = theme.tab_bar.progress_ok },
	progress_percentage_active = { bg = theme.tab_bar.active_bg2, fg = theme.tab_bar.progress_ok },

	progress_error_default = { bg = theme.tab_bar.default_bg, fg = theme.tab_bar.progress_err },
	progress_error_hover = { bg = theme.tab_bar.hover_bg, fg = theme.tab_bar.progress_err },
	progress_error_active = { bg = theme.tab_bar.active_bg2, fg = theme.tab_bar.progress_err },

	progress_indeterminate_default = { bg = theme.tab_bar.default_bg, fg = theme.tab_bar.progress_ind },
	progress_indeterminate_hover = { bg = theme.tab_bar.hover_bg, fg = theme.tab_bar.progress_ind },
	progress_indeterminate_active = { bg = theme.tab_bar.active_bg2, fg = theme.tab_bar.progress_ind },
}

---@param pct number
local function _pct_to_frame(pct)
	local frame = math.floor(pct * #ICON_PROGRESS_PCT_FRAMES / 100)
	return ICON_PROGRESS_PCT_FRAMES[frame]
end

local __indeter_frame = 1
local function _ind_to_frame()
	local frame = __indeter_frame
	__indeter_frame = (__indeter_frame % #ICON_PROGRESS_IND_FRAMES) + 1
	return ICON_PROGRESS_IND_FRAMES[frame]
end

---@param proc string
local function clean_process_name(proc)
	local a = string.gsub(proc, ".*[/\\](.*)", "%1")
	return a:gsub("%.exe$", "")
end

---@generic T
---@param pane_title string
---@param process_name string
---@return string, PrefixIcon?
local function create_base_title(pane_title, process_name)
	local prefix_icon = nil
	local base_title = pane_title

	if base_title == "Debug" then
		prefix_icon = ICON_PREFIX.debug
		base_title = base_title:upper()
	elseif base_title == "Launcher" then
		prefix_icon = ICON_PREFIX.launcher
		base_title = base_title:upper()
	elseif ustr.starts_with(base_title, "Administrator:") or ustr.ends_with(base_title, "(Admin)") then
		prefix_icon = ICON_PREFIX.admin
		base_title = base_title:gsub("Administrator: ", ""):gsub("%(Admin%)", "")
	elseif ustr.starts_with(process_name, "wsl") then
		prefix_icon = ICON_PREFIX.wsl
	elseif ustr.starts_with(base_title, "InputSelector:") then
		prefix_icon = ICON_PREFIX.select
		base_title = base_title:gsub("InputSelector: ", "")
	elseif ustr.starts_with(base_title, "InputLine:") then
		prefix_icon = ICON_PREFIX.edit
		base_title = base_title:gsub("InputLine: ", "")
	end

	return base_title, prefix_icon
end

---@param process_name string
---@param base_title string
---@param max_width number
---@param inset number
---@param tab_index number
local function create_title(process_name, base_title, max_width, inset, tab_index)
	local title
	local num = tostring(tab_index + 1) .. " "

	if process_name:len() > 0 then
		title = num .. process_name .. " ~ " .. base_title
	else
		title = num .. base_title
	end

	if wezterm.column_width(title) > max_width - inset then
		local diff = wezterm.column_width(title) - max_width + inset
		title = wezterm.truncate_right(title, wezterm.column_width(title) - diff)
	else
		local padding = max_width - wezterm.column_width(title) - inset
		local left_pad = math.floor(padding / 2)
		local right_pad = padding - left_pad
		title = string.rep(" ", left_pad) .. title .. string.rep(" ", right_pad)
	end

	return title
end

local progress_stale = (function()
	local status_score = {
		indeterminate = 100,
		error = 200,
		percentage = 300,
	}

	local entries = {}

	return function(tab_index, pane_index, status, pct)
		local entry_id = (tab_index << 5) | pane_index

		if not entries[entry_id] then
			entries[entry_id] = {}
			entries[entry_id].sum = status_score[status] + pct
			entries[entry_id].last_changed = os.time()
			return false
		end

		local sum = status_score[status] + pct

		if sum ~= entries[entry_id].sum then
			entries[entry_id].sum = sum
			entries[entry_id].last_changed = os.time()
			return false
		end

		return os.time() - entries[entry_id].last_changed > PROGRESS_STALE_AFTER
	end
end)()

---@param options Event.TabTitleOptions
---@param tab_index integer
---@param panes PaneInformation[]
---@return {icon: string?, status: 'indeterminate'|'percentage'|'error'?}[]
local function check_progress(options, tab_index, panes)
	if not options.show_progress then
		return {}
	end

	local progress = {}
	local limit = 3

	for _, pane in ipairs(panes) do
		if #progress > limit then
			break
		end

		local prog = pane.progress
		local status = nil
		local icon = nil
		local pct = 0

		if prog == "Indeterminate" then
			status = "indeterminate"
			icon = _ind_to_frame()
		elseif prog.Percentage ~= nil then
			status = "percentage"
			icon, pct = _pct_to_frame(prog.Percentage), prog.Percentage
		elseif prog.Error ~= nil then
			status = "error"
			icon, pct = _pct_to_frame(prog.Error), prog.Error
		end

		if icon and status then
			if not progress_stale(tab_index, pane.pane_index, status, pct) then
				table.insert(progress, { icon = icon, status = status })
			end
		end
	end

	return progress
end

---@param options Event.TabTitleOptions
---@param is_active boolean
---@param panes PaneInformation[]
---@return UnseenOutputIcon|nil
local function check_unseen_output(options, is_active, panes)
	if options.hide_active_tab_unseen and is_active then
		return nil
	end

	local icon = nil

	local count = 0
	local limit = 10

	if options.unseen_icon == "circle" then
		limit = 0
	end

	for _, pane in ipairs(panes) do
		if count > limit then
			break
		end

		if pane.has_unseen_output then
			count = count + 1
		end
	end

	if count > 0 then
		if options.unseen_icon == "circle" then
			icon = ICON_UNSEEN[options.unseen_icon]
		else
			icon = ICON_UNSEEN[options.unseen_icon .. "_" .. count]
		end
	end

	return icon
end

local progress_cells = Cells:new():add_segment(RS.progress):add_segment(RS.padding, " ")
local title_cells = Cells:new()
	:add_segment(RS.scircle_left, ICON_SCIRCLE_LEFT, colors.scircle_default)
	:add_segment(RS.icon)
	:add_segment(RS.title, nil, nil, attr(attr.intensity("Bold")))
	:add_nested_segment(RS.progress)
	:add_segment(RS.unseen_output)
	:add_segment(RS.padding, " ")
	:add_segment(RS.scircle_right, ICON_SCIRCLE_RIGHT, colors.scircle_default)

---@class Tab
---@field title_locked boolean
---@field locked_title string
---@field has_icon boolean
---@field has_unseen boolean
---@field has_progress boolean
local Tab = {}
Tab.__index = Tab

---@return Tab
function Tab:new()
	local tab = {
		has_icon = false,
		has_unseen = false,
		has_progress = false,
	}

	return setmetatable(tab, self)
end

---@param event_opts Event.TabTitleOptions
---@param tab TabInformation
---@param hover boolean
---@param max_width number
function Tab:update_cells(event_opts, tab, hover, max_width)
	self.has_icon = false
	self.has_unseen = false
	self.has_progress = false

	local tab_state = "default"
	if tab.is_active then
		tab_state = "active"
	elseif hover then
		tab_state = "hover"
	end

	local process_name = clean_process_name(tab.active_pane.foreground_process_name)
	-- Use custom tab title if set via set_title(), otherwise use pane title
	local pane_title = tab.tab_title ~= "" and tab.tab_title or tab.active_pane.title
	local base_title, prefix_icon = create_base_title(pane_title, process_name)
	local unseen_icon = check_unseen_output(event_opts, tab.is_active, tab.panes)
	local progress = check_progress(event_opts, tab.tab_index, tab.panes)
	local inset = TITLE_INSET.default

	-- User-set titles show as "N- title" without process name
	if tab.tab_title ~= "" then
		process_name = ""
	end

	if prefix_icon then
		inset = inset + TITLE_INSET.increment
		self.has_icon = true
		title_cells:update_segment_text(RS.icon, prefix_icon)
	end

	if unseen_icon then
		inset = inset + TITLE_INSET.increment
		self.has_unseen = true
		title_cells:update_segment_text(RS.unseen_output, unseen_icon)
	end

	inset = inset + (TITLE_INSET.increment * #progress)
	self.has_progress = #progress > 0

	local nested_items = {}

	if self.has_progress then
		for i, prog in ipairs(progress) do
			local prog_colors = "progress_" .. prog.status .. "_" .. tab_state
			progress_cells
				:update_segment_text(RS.progress, prog.icon)
				:update_segment_colors(RS.progress, colors[prog_colors])
				:update_segment_colors(RS.padding, colors["text_" .. tab_state])
			if i == #progress then
				table.insert(nested_items, progress_cells:render({ RS.progress }))
			else
				table.insert(nested_items, progress_cells:render({ RS.progress, RS.padding }))
			end
		end
	end

	title_cells:update_nested_segment(RS.progress, nested_items)

	local title = create_title(process_name, base_title, max_width, inset, tab.tab_index)

	title_cells:update_segment_text(RS.title, title)

	title_cells
		:update_segment_colors(RS.scircle_left, colors["scircle_" .. tab_state])
		:update_segment_colors(RS.icon, colors["text_" .. tab_state])
		:update_segment_colors(RS.title, colors["text_" .. tab_state])
		:update_segment_colors(RS.unseen_output, colors["unseen_output_" .. tab_state])
		:update_segment_colors(RS.padding, colors["text_" .. tab_state])
		:update_segment_colors(RS.scircle_right, colors["scircle_right_" .. tab_state])
end

---@return FormatItem[]
function Tab:render()
	local variant_idx = self.has_icon and 5 or 1
	if self.has_unseen then
		variant_idx = variant_idx + 1
	end
	if self.has_progress then
		variant_idx = variant_idx + 2
	end
	return title_cells:render(RV[variant_idx])
end

---@type Tab[]
local tab_list = {}

---@param opts? Event.TabTitleOptionsInput
M.setup = function(opts)
	local valid_opts, err = EVENT_OPTS:validate(opts or {})

	if err then
		wezterm.log_error(err)
	end

	if tonumber(wezterm.version:sub(1, 8)) < PROGRESS_MIN_VERSION then
		valid_opts.show_progress = false
	end

	wezterm.on("format-tab-title", function(tab, _tabs, _panes, _config, hover, max_width)
		if not tab_list[tab.tab_id] then
			tab_list[tab.tab_id] = Tab:new()
		end

		tab_list[tab.tab_id]:update_cells(valid_opts, tab, hover, max_width)
		return tab_list[tab.tab_id]:render()
	end)
end

return M
