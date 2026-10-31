-- ryoku login bootstrap.
--
-- The shell itself starts through scripts/launch-ryoku.sh, the one launch
-- definition switch-shell.sh also uses: it puts ryoku's private bin dir on the
-- shell's PATH only and starts ryogami (wallpapers) next to the daemon.
hl.on("hyprland.start", function()
    hl.exec_cmd(os.getenv("HOME") .. "/.config/dcli/scripts/launch-ryoku.sh")
    hl.exec_cmd("systemctl --user start hyprpolkitagent")
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")
end)
