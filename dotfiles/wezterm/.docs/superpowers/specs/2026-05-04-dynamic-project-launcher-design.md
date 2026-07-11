# Dynamic Project Launcher Design

## Goal

Make `leader+Shift+p` useful without manually editing every project entry. The launcher should keep important pinned shortcuts while automatically discovering project directories from common roots.

## Behavior

- Keep a pinned project list for high-value locations such as the WezTerm config, dot config, Neovim config, UNI, Development, and `G:/`.
- Discover child directories under configured roots and add them as project choices.
- Prefer Git repositories when scanning broad roots so random folders do not flood the selector.
- Let pinned projects win when a discovered project resolves to the same path or workspace name.
- Use a normalized folder name as the workspace name for discovered projects.
- Preserve the existing workspace behavior: save the current workspace, switch to an existing workspace, restore a saved workspace, or create a new workspace at the project path.

## Design

Project discovery lives in a small module separate from keymap registration. `wezterm/keymaps/projects.lua` asks that module for the project list, converts projects into `InputSelector` choices, then reuses the existing switch/restore/spawn flow.

The discovery module exposes one function that takes `wezterm` and `constants`. It combines pinned projects with discovered projects, deduplicates them, sorts dynamic entries, and returns plain project tables.

## Error Handling

Missing scan roots are ignored. Directory scanning failures return an empty dynamic list rather than breaking WezTerm startup.

## Verification

Verify Lua syntax by loading the touched modules with the local Lua interpreter if available. Also inspect `git diff` before committing.
