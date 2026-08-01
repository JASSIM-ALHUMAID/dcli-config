-- House overrides for end4 keybinds
-- Adds the switch-shell bind

hl.bind("SUPER + SHIFT + O", hl.dsp.exec_cmd(os.getenv("HOME") .. "/.config/dcli/scripts/switch-shell.sh"))
