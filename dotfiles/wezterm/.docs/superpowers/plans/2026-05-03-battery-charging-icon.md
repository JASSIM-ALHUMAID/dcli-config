# Battery Charging Icon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show whether the laptop is currently charging in the WezTerm status bar battery segment.

**Architecture:** Keep the existing status-bar event flow in `wezterm/events.lua`. Extend the battery helper so it returns both the correct icon and percentage text based on WezTerm battery state.

**Tech Stack:** WezTerm Lua config, `wezterm.battery_info()`, Nerd Font icons.

---

### Task 1: Battery Charging Icon

**Files:**
- Modify: `wezterm/events.lua:5-17`
- Modify: `wezterm/events.lua:64-68`

- [ ] **Step 1: Inspect battery state shape**

Use the existing `wezterm.battery_info()` response in `get_battery_text()` and read `batteries[1].state` alongside `batteries[1].state_of_charge`.

- [ ] **Step 2: Update helper return value**

Replace the helper return with a table containing `icon` and `text`:

```lua
local state = batteries[1].state
local icon = state == "Charging" and wezterm.nerdfonts.md_power_plug or wezterm.nerdfonts.md_battery

return {
	icon = icon,
	text = tostring(math.floor((charge * 100) + 0.5)) .. "%",
}
```

- [ ] **Step 3: Render icon and percentage**

Update the right-status battery segment to use the helper table:

```lua
if battery then
	table.insert(right_status, { Text = " | " })
	table.insert(right_status, { Foreground = { Color = constants.custom_colors.green } })
	table.insert(right_status, { Text = battery.icon .. "  " .. battery.text })
end
```

- [ ] **Step 4: Verify syntax**

Run: `wezterm cli list`
Expected: command succeeds without reporting a Lua config error.

---

## Self-Review

- Spec coverage: The plan covers the approved plug-icon charging indicator and preserves existing hidden-battery fallback behavior.
- Placeholder scan: No placeholders remain.
- Type consistency: `get_battery_text()` returns `nil` or `{ icon = string, text = string }`; the renderer checks truthiness before using both fields.
