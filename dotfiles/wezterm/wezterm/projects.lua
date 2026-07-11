local M = {}

local function normalize_path(path)
	return (tostring(path or ""):gsub("\\", "/"):gsub("/+$", ""))
end

local function add_project(projects, seen_paths, seen_workspaces, project)
	local path_key = normalize_path(project.path):lower()
	local workspace_key = tostring(project.workspace or ""):lower()
	if path_key == "" or workspace_key == "" or seen_paths[path_key] or seen_workspaces[workspace_key] then
		return
	end

	seen_paths[path_key] = true
	seen_workspaces[workspace_key] = true
	table.insert(projects, project)
end

-- Explicit, hand-picked project workspaces. Auto-discovery is intentionally off
-- so the launcher only ever shows these (plus saved workspaces, below).
local function pinned_projects(constants)
	return {
		{ id = "wezterm", label = "WezTerm config", workspace = "wezterm", path = constants.HOME .. "/.config/wezterm", pinned = true },
		{ id = "config", label = "Dot config", workspace = "config", path = constants.HOME .. "/.config", pinned = true },
	}
end

-- Workspaces the user has saved via LEADER S. Read fresh each call so newly
-- saved sessions show up in the launcher without a config reload.
local function saved_projects(wezterm)
	local dir = wezterm.config_dir .. "/state/workspaces"
	local out = {}

	local ok, entries = pcall(wezterm.read_dir, dir)
	if not ok or not entries then
		return out
	end

	for _, path in ipairs(entries) do
		local stem = normalize_path(path):match("([^/]+)%.json$")
		if stem then
			local workspace, cwd = stem, nil
			local f = io.open(path, "r")
			if f then
				local raw = f:read("*a")
				f:close()
				local pok, data = pcall(wezterm.json_parse, raw)
				if pok and type(data) == "table" then
					if type(data.name) == "string" and data.name ~= "" then
						workspace = data.name
					end
					if data.tabs and data.tabs[1] and data.tabs[1].panes and data.tabs[1].panes[1] then
						cwd = data.tabs[1].panes[1].cwd
					end
				end
			end
			table.insert(out, {
				id = "saved:" .. workspace,
				label = workspace .. "  (saved)",
				workspace = workspace,
				path = cwd,
				saved = true,
			})
		end
	end

	table.sort(out, function(a, b)
		return a.label:lower() < b.label:lower()
	end)

	return out
end

function M.list(wezterm, constants)
	local projects = {}
	local seen_paths = {}
	local seen_workspaces = {}

	for _, project in ipairs(pinned_projects(constants)) do
		add_project(projects, seen_paths, seen_workspaces, project)
	end

	-- Saved workspaces dedupe by workspace name only (a saved entry that shares a
	-- pinned name is skipped; selecting the pinned one still restores from save).
	for _, project in ipairs(saved_projects(wezterm)) do
		local key = tostring(project.workspace or ""):lower()
		if key ~= "" and not seen_workspaces[key] then
			seen_workspaces[key] = true
			table.insert(projects, project)
		end
	end

	return projects
end

return M
