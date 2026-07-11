# Dynamic Project Launcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the hard-coded `leader+Shift+p` project list with a hybrid pinned plus dynamically discovered project selector.

**Architecture:** Add a focused project discovery module that returns plain project tables. Keep keymap registration responsible only for turning projects into selector choices and preserving the existing workspace switch/restore/spawn behavior.

**Tech Stack:** WezTerm Lua config, Lua standard filesystem calls through `wezterm.read_dir`, Git workspace state helpers already present in this config.

---

## File Structure

- Create: `wezterm/projects.lua` for pinned projects, scan roots, dedupe, sorting, and discovery.
- Modify: `wezterm/keymaps/projects.lua` to consume `wezterm.projects.list()` instead of building a local hard-coded table.
- Verify: run Lua module loading or WezTerm config validation where available, then inspect `git diff` and commit.

### Task 1: Add Project Discovery Module

**Files:**
- Create: `wezterm/projects.lua`

- [ ] **Step 1: Create the module**

Create `wezterm/projects.lua` with helpers for path normalization, workspace naming, pinned projects, scan roots, Git repo detection, dedupe, and final sorting.

```lua
local M = {}

local function normalize_path(path)
	return (tostring(path or ""):gsub("\\", "/"):gsub("/+$", ""))
end

local function workspace_name(name)
	local normalized = tostring(name or ""):lower():gsub("[^%w%-_]+", "-"):gsub("%-+", "-")
	return normalized:gsub("^%-", ""):gsub("%-$", "")
end

local function basename(path)
	return (normalize_path(path):match("([^/]+)$")) or ""
end

local function directory_exists(path)
	local ok, _, code = os.rename(path, path)
	return ok or code == 13
end

local function is_git_repo(path)
	return directory_exists(normalize_path(path) .. "/.git")
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

local function pinned_projects(constants)
	return {
		{ id = "wezterm", label = "WezTerm config", workspace = "wezterm", path = constants.CONFIG_DIR, pinned = true },
		{ id = "config", label = "Dot config", workspace = "config", path = constants.HOME .. "/.config", pinned = true },
		{ id = "nvim", label = "Neovim config", workspace = "nvim", path = constants.HOME .. "/AppData/Local/nvim", pinned = true },
		{ id = "uni", label = "UNI", workspace = "uni", path = constants.HOME .. "/UNI", pinned = true },
		{ id = "dev", label = "Downloads Development", workspace = "dev", path = constants.HOME .. "/Downloads/Development", pinned = true },
		{ id = "g", label = "G drive", workspace = "g-drive", path = "G:/", pinned = true },
	}
end

local function scan_roots(constants)
	return {
		constants.HOME .. "/Downloads/Development",
		constants.HOME .. "/UNI",
		constants.HOME .. "/.config",
		"G:/",
	}
end

local function discovered_projects(wezterm, constants)
	local projects = {}
	for _, root in ipairs(scan_roots(constants)) do
		local ok, entries = pcall(wezterm.read_dir, root)
		if ok and entries then
			for _, path in ipairs(entries) do
				local name = basename(path)
				local workspace = workspace_name(name)
				if workspace ~= "" and is_git_repo(path) then
					table.insert(projects, {
						id = "dir:" .. normalize_path(path),
						label = name,
						workspace = workspace,
						path = normalize_path(path),
					})
				end
			end
		end
	end

	table.sort(projects, function(a, b)
		return a.label:lower() < b.label:lower()
	end)

	return projects
end

function M.list(wezterm, constants)
	local projects = {}
	local seen_paths = {}
	local seen_workspaces = {}

	for _, project in ipairs(pinned_projects(constants)) do
		add_project(projects, seen_paths, seen_workspaces, project)
	end

	for _, project in ipairs(discovered_projects(wezterm, constants)) do
		add_project(projects, seen_paths, seen_workspaces, project)
	end

	return projects
end

return M
```

### Task 2: Wire Discovery Into Keymap

**Files:**
- Modify: `wezterm/keymaps/projects.lua:1-72`

- [ ] **Step 1: Replace the local hard-coded table**

Update `wezterm/keymaps/projects.lua` so `M.append` starts with the discovered project list.

```lua
local project_source = require("wezterm.projects")

local M = {}

-- Project launcher: switch to a named workspace and start in its root.
function M.append(keys, wezterm, workspaces, constants)
	local act = wezterm.action
	local projects = project_source.list(wezterm, constants)
```

Keep the existing `by_id`, `choices`, and action callback logic unchanged.

### Task 3: Verify And Commit

**Files:**
- Verify: `wezterm/projects.lua`, `wezterm/keymaps/projects.lua`, `docs/superpowers/specs/2026-05-04-dynamic-project-launcher-design.md`, `docs/superpowers/plans/2026-05-04-dynamic-project-launcher.md`

- [ ] **Step 1: Check syntax**

Run: `lua -e "package.path = package.path .. ';./?.lua'; require('wezterm.projects')"`

Expected: exits successfully if `lua` is available. If `lua` is not installed, use `wezterm cli` or `wezterm start --config-file wezterm.lua` only if available and safe.

- [ ] **Step 2: Inspect diff**

Run: `git diff -- wezterm/projects.lua wezterm/keymaps/projects.lua docs/superpowers/specs/2026-05-04-dynamic-project-launcher-design.md docs/superpowers/plans/2026-05-04-dynamic-project-launcher.md`

Expected: diff only contains the hybrid project launcher changes and the spec/plan docs.

- [ ] **Step 3: Commit**

```bash
git add wezterm/projects.lua wezterm/keymaps/projects.lua docs/superpowers/specs/2026-05-04-dynamic-project-launcher-design.md docs/superpowers/plans/2026-05-04-dynamic-project-launcher.md
git commit -m "feat: discover wezterm projects dynamically"
```
