# Fix switch-shell.sh: Ambxst Process Cleanup and Launch Guard

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix bugs in `scripts/switch-shell.sh` that cause ambxst helper processes to survive shell switches, caelestia/ambxst to double-start, and the script to kill itself when switching to ambxst.

**Architecture:** Three targeted fixes in a single file. (1) Hybrid kill patterns for ambxst: `-x` (exact comm match) for the main `ambxst` process (comm=`ambxst`, won't match the script itself), `-f` (command line match) only for helper scripts (comm=`bash`/`tail`). (2) Add missing `pgrep` launch guards for caelestia and ambxst. (3) Fix the self-kill bug where `pkill -f "ambxst"` matches the script's own argument.

**Tech Stack:** Bash, Hyprland

## Global Constraints

- Script is at `/home/awhss/.config/dcli/scripts/switch-shell.sh`
- Must remain compatible with bash (script uses `#!/bin/bash`)
- Do not change the overall structure or other shells' kill patterns
- Only fix the two identified bugs

---

### Task 1: Fix ambxst kill patterns (hybrid -x/-f approach)

**Files:**
- Modify: `/home/awhss/.config/dcli/scripts/switch-shell.sh:97-103`

**Problem:** Task 1 (commit 0cb5754) changed all ambxst patterns from `-x` to `-f`. But `pkill -f "ambxst"` matches the script itself (the argument `ambxst` appears in the command line), causing the script to kill itself before completing.

**Evidence:**
- `cat /proc/<script_pid>/cmdline` shows `bash .../switch-shell.sh ambxst`
- `pkill -f "ambxst"` matches this because "ambxst" is in the command line
- The script hangs at `kill_matching -f "ambxst"` and never reaches the printf that writes active.conf

**Solution:** Hybrid approach:
- Main `ambxst` process: comm=`ambxst` (bash script), use `-x` (exact comm match, won't match our script whose comm=`bash`)
- Helper scripts (`sleep_monitor.sh`, `loginlock.sh`): comm=`bash`/`tail`, use `-f` (command line match)
- `ambxst_ipc`: comm=`tail`, use `-f`
- `axctl`: comm=`axctl`, use `-x`

- [ ] **Step 1: Fix the ambxst kill patterns to hybrid approach**

Replace the current ambxst block (lines ~97-103):

```bash
# CURRENT (broken — kills the script itself):
  # AMBXst — use -f (command-line match) because the helper scripts
  # run as bash/tail, so their comm field is bash/tail, not the script name
  kill_matching -f "ambxst"
  kill_matching -f "axctl"
  kill_matching -f "ambxst_ipc"
  kill_matching -f "loginlock.sh"
  kill_matching -f "sleep_monitor.sh"

# FIXED (hybrid — main process uses -x, helpers use -f):
  # AMBXst — main process (comm=ambxst) uses -x to avoid matching this
  # script's own command line; helper scripts run as bash/tail, so use -f
  kill_matching -x "ambxst"
  kill_matching -x "axctl"
  kill_matching -f "ambxst_ipc"
  kill_matching -f "loginlock.sh"
  kill_matching -f "sleep_monitor.sh"
```

- [ ] **Step 2: Verify the fix by running the script**

Run:
```bash
timeout 30 bash /home/awhss/.config/dcli/scripts/switch-shell.sh ambxst 2>&1
echo "Exit: $?"
```

Expected: Script completes without hanging, prints "Switched to ambxst", active.conf is updated.

- [ ] **Step 3: Commit**

```bash
git add scripts/switch-shell.sh
git commit -m "fix(switch-shell): hybrid -x/-f for ambxst kill patterns

pkill -f 'ambxst' matches the script's own command line (the argument
'ambxst'), causing the script to kill itself. Use -x (exact comm match)
for the main ambxst process (comm=ambxst) and -f only for helper scripts
that run as bash/tail."
```

---

### Task 2: Add missing launch guards for caelestia and ambxst

**Files:**
- Modify: `/home/awhss/.config/dcli/scripts/switch-shell.sh:126-133`

**Evidence:** Only dms (line 134), noctalia (line 137), and end4 (line 140) have `pgrep` launch guards. Caelestia and ambxst do not. If either process survives `kill_all_shells` or the script is called twice quickly, they double-start.

**Process patterns:**
- Caelestia: actual running process is `qs -c caelestia -n -d`, so guard with `pgrep -f "qs -c caelestia"`
- Ambxst: binary is a bash script, comm=`ambxst` when running, so guard with `pgrep -x "ambxst"`

- [ ] **Step 1: Add pgrep guard around caelestia launch**

Replace the caelestia case (~line 126):

```bash
# OLD (broken):
caelestia)
  caelestia shell -d &
  disown
  ;;

# NEW (fixed):
caelestia)
  pgrep -f "qs -c caelestia" >/dev/null 2>&1 || {
    caelestia shell -d &
    disown
  }
  ;;
```

- [ ] **Step 2: Add pgrep guard around ambxst launch**

Replace the ambxst case (~line 129):

```bash
# OLD (broken):
ambxst)
  ambxst & disown
  sleep 2
  hyprctl keyword monitor ", preferred, auto, 1"
  ;;

# NEW (fixed):
ambxst)
  pgrep -x "ambxst" >/dev/null 2>&1 || {
    ambxst & disown
    sleep 2
    hyprctl keyword monitor ", preferred, auto, 1"
  }
  ;;
```

- [ ] **Step 3: Commit**

```bash
git add scripts/switch-shell.sh
git commit -m "fix(switch-shell): add missing pgrep guards for caelestia and ambxst

dms, noctalia, and end4 already had pgrep guards to prevent double-starting.
Caelestia and ambxst were the only shells missing this protection."
```

---

### Task 3: Verify all fixes work together

- [ ] **Step 1: Read the final script to confirm all changes are correct**

Run: `cat scripts/switch-shell.sh | head -170`

Verify:
1. Ambxst block uses hybrid approach: `-x` for `ambxst` and `axctl`, `-f` for helpers
2. The caelestia case has a `pgrep -f "qs -c caelestia"` guard
3. The ambxst case has a `pgrep -x "ambxst"` guard

- [ ] **Step 2: Test switching to ambxst (live Hyprland test)**

Run:
```bash
timeout 45 bash /home/awhss/.config/dcli/scripts/switch-shell.sh ambxst 2>&1
echo "Exit: $?"
```

Expected:
- Script completes without hanging
- Prints "Switched to ambxst"
- `active.conf` points to ambxst
- No ambxst helper processes survive after kill phase
- Ambxst launches successfully

- [ ] **Step 3: Test switching back to caelestia**

Run:
```bash
timeout 45 bash /home/awhss/.config/dcli/scripts/switch-shell.sh caelestia 2>&1
echo "Exit: $?"
```

Expected:
- Script completes without hanging
- Prints "Switched to caelestia"
- `active.conf` points to caelestia
- Caelestia launches successfully

- [ ] **Step 4: Final commit if any adjustments were needed**

```bash
git add scripts/switch-shell.sh
git commit -m "fix(switch-shell): final adjustments to kill patterns and launch guards"
```
