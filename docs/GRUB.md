# GRUB: the bootloader follows your shell

Every registry shell gets its own GRUB theme, rendered from that shell's
wallpaper and logo. The active shell's theme is the boot menu; a **Shells**
submenu previews each theme and boots straight into a chosen shell. A shell
switch re-renders the theme set, **so does changing a shell's wallpaper**, and
the boot menu follows with no `grub-mkconfig` (the `GRUB_THEME` path never
changes).

```
 session (you)                                     root (installed once)
 ─────────────                                     ─────────────────────
 switch-shell.sh ──detached──► render-grub-theme.sh
 wallpaper change ─► dcli-grub-render.path (user) ─► … --changed all
                                  │ writes
                                  ▼
                         state/grub-theme/  ... .stamp  ──PathChanged──► dcli-grub-theme.path
                          fonts/ <shell>/ active                              │
                                                                              ▼
                              (read AS THE USER, setpriv + tar)    dcli-grub-theme.service
                                                                              │ /usr/local/libexec/dcli-grub-sync
                                                                              ▼
                                                       /boot/grub/themes/dcli/<shell>/  +  active/
                                                                              │ shell set changed?
                                                                              ▼
                                                  grub-mkconfig ► 42_dcli_shells ► "Shells" submenu
 boot ─ dcli.shell=<name> on the kernel line ─► Hyprland start ─► boot-shell.sh ─► switch-shell.sh <name>
```

## One-time install

`dcli sync` installs the packages and the user half (the module hook renders the
themes). The root half needs `sudo`, which a hook never calls, so the hook ends
by printing the one command to run yourself — **as you, not with sudo**; it asks
for your password when a step needs root:

```bash
~/.config/dcli/scripts/install-grub-theme.sh     # install / upgrade
~/.config/dcli/scripts/uninstall-grub-theme.sh   # remove ([--purge] also drops state/grub-theme/)
```

The installer works in numbered steps: checks the `modules/grub-theme.yaml`
packages (`pacman -T`, installs what is missing), renders every shell with the
current one as `active` (so the first sync never installs a stale tree), then
copies the helper and the grub.d script into root-owned locations, writes the
two units with your user name and the staging path baked in, runs the sync once,
points `GRUB_THEME` at `/boot/grub/themes/dcli/active/theme.txt` (the previous
line is remembered, `/etc/default/grub` is backed up first, only that key is
edited), runs `grub-mkconfig` and enables the path unit. If the first sync
fails it prints the service's journal and stops **before** `GRUB_THEME` is
touched. Re-run it after `scripts/grub/*` changes (it is the upgrade path and
keeps the remembered pre-install `GRUB_THEME`); `scripts/doctor.sh` (and the
hook) tell you when the installed copies are stale. `uninstall-grub-theme.sh`
reverses everything — including a half-finished install — and restores the old
`GRUB_THEME`.

## Where each wallpaper comes from

`scripts/lib/wallpaper.sh` holds `WALLPAPER_SOURCES` — one record per shell
(`shell|kind|file|query`) naming the file that shell itself persists its
wallpaper in: caelestia `path.txt`, ambxst `wallpapers.json` `.currentWall`, dms
`session.json` `.wallpaperPath`, noctalia `settings.toml` `[wallpaper.last]`,
end4/end4pc `config.json` `.background.wallpaperPath`, omarchy's
`current/background` symlink, xenon `wallpapers.json` (else its shipped
default), glyph `glyph.json` `.wall`, ryoku `~/.local/state/ryoku-wallpaper`. A
shell with no wallpaper (glyph's dot mode) gets a generated gradient.

It replaced `hyprlock/colors.conf`'s `$background_image`, which only the
matugen-driven shells rewrite: until 2026-10-31 noctalia, ryoku and glyph booted
with ambxst's wallpaper and dms with its previous one.

The same table drives the watcher: `install-grub-theme.sh` writes one
`PathChanged=` per state file into the user unit `dcli-grub-render.path`, whose
service runs `render-grub-theme.sh --changed all`. `--changed` compares each
shell's wallpaper path + mtime + size (plus the renderer's mtime and the newest
registry/logo mtime — every dock draws all logos) with the
signature of its last render (`~/.cache/dcli/grub-wallpaper/<shell>`) and exits in
~0.1 s when nothing moved — dms and noctalia rewrite those files for unrelated
settings constantly. A real change re-renders just that shell, rewrites
`.stamp`, and the root path unit installs it.

## Staging contract (`state/grub-theme/`)

Written by `scripts/render-grub-theme.sh`, read by the root side:

| Path | Content |
| --- | --- |
| `fonts/*.pf2` | shared font set, fixed names (`00_header` `loadfont`s the active dir's `*.pf2` at mkconfig time) |
| `fonts/MANIFEST` | renderer's `key\|file\|GRUB font name` ledger — excluded from the sync, never installed |
| `<shell>/` | one complete theme: `theme.txt`, `background.jpg`, `*.png`, `icons/*.png`, `title.txt`, `.complete` (written last) |
| `active` | one line: the active shell |
| `<shell>/preview.png`, `contact-sheet.png` | humans only, never read by root |
| `.stamp` | rewritten **last**; the path unit watches it |

Installed layout: `/boot/grub/themes/dcli/<shell>/` per shell, plus
`active/` = the active shell's files + the fonts at its top level + a generated
`.dcli-shell` marker (what `doctor.sh` compares with the session).

## Security model

A root service consuming a user-writable tree is the dangerous part, so:

- **Nothing from the repo runs as root at runtime.** Only the installed,
  root-owned copies run. The repo files are copied once, by the installer, under
  your explicit `sudo` (the installer is run as you and escalates per step).
- **The staging tree is read as the user.** `dcli-grub-sync` runs
  `setpriv --reuid --regid --clear-groups tar -c` (a user process), so a symlink
  planted in staging can only expose what the user could already read.
- **The stream is hostile.** It is size-capped (128 MiB), written to a root-owned
  temp dir (`mktemp`, `PrivateTmp`), its member types are listed first and
  anything but regular files and directories (symlinks, hardlinks, devices) or a
  `..`/absolute name rejects the whole archive, and only then is it extracted
  (`--no-same-owner --no-same-permissions`).
- **Every extracted file is re-validated** before `install -m0644`: names
  `^[A-Za-z0-9._-]+$`, shell names `^[a-z0-9][a-z0-9-]*$`, allowed types only
  (`theme.txt`, `title.txt`, `.png`, `.jpg`, `.pf2`), per-file cap 8 MiB, magic
  bytes for PNG/JPEG/PF2, `theme.txt` plain text whose quoted references contain
  no `..`, absolute, `(device)`, `$` or backslash.
- **Atomic and conservative.** Each shell is installed to `.new-<shell>` and
  renamed in. A shell that fails validation keeps its previous good copy and the
  run exits non-zero; a shell that is no longer staged is removed.
- **Unit hardening:** `ProtectSystem=strict`, `ReadWritePaths=/boot/grub`
  (and `/var/lib/os-prober` if present), `ProtectHome=read-only`, `PrivateTmp`,
  `PrivateNetwork`, `NoNewPrivileges`.

## The "Shells" submenu

`/etc/grub.d/42_dcli_shells` emits `submenu "Shells"` with, per installed shell,
a nested submenu (`set theme=...`, not exported, so leaving restores the active
theme) holding a boot entry. The entry body is the first top-level
`menuentry` of `/etc/grub.d/10_linux`, run with grub-mkconfig's own environment
(so root UUID, btrfs subvolume paths, microcode and initrd stay right), with
` dcli.shell=<name>` appended to its `linux` line. If any of that cannot be
derived the script prints nothing — it can never break `grub.cfg`.

## Boot into a shell

`scripts/boot-shell.sh` is launched from `dotfiles/hypr/hyprland.lua` inside
`hl.on("hyprland.start", ...)`, so a shell switch (a reload) cannot re-fire it. It
reads `dcli.shell=<name>` from `/proc/cmdline`; if it names a registry shell and
this boot's id (`/proc/sys/kernel/random/boot_id`) is not yet recorded in
`~/.local/state/dcli/boot-shell`, it records the id (before switching, so it
cannot loop) and runs `switch-shell.sh <name>` unless that shell is already
active. Unknown names are ignored.

## Operating it

| Task | How |
| --- | --- |
| Re-render all | `scripts/render-grub-theme.sh all` (the path unit installs the result) |
| Skip the render on a switch | `DCLI_SKIP_GRUB_THEME=1 scripts/switch-shell.sh <shell>` |
| Render log of the last switch | `~/.local/state/dcli/grub-theme.log` |
| Why was a theme not installed | `journalctl -u dcli-grub-theme.service` |
| Health | `scripts/doctor.sh` (GRUB lines are WARN, never FAIL) |
| Add a shell | registry record; the renderer defaults unknown shells to the `material` style |

Test knobs (never set in production): `DCLI_GRUB_DEST`, `DCLI_GRUB_READER`,
`DCLI_GRUB_MKCONFIG`, `DCLI_GRUB_ALLOW_NONROOT` (sync); `DCLI_GRUB_THEMES_DIR`,
`DCLI_GRUB_10_LINUX`, `DCLI_GRUB_THEMES_URI` (grub.d script);
`DCLI_INSTALL_ROOT` (installer, status helper); `DCLI_CMDLINE_FILE`,
`DCLI_BOOT_ID_FILE`, `DCLI_BOOT_STATE_DIR` (boot-shell). `tests/smoke.sh` drives
all of them against fixtures.
