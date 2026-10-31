# SDDM: the login screen follows your shell

Every registry shell has its own SDDM theme, `dcli-<shell>`, and the one SDDM
wears is chosen by a selector: `auto` (follow the running shell, the default) or
a pinned shell. Palette, wallpaper and avatar come from the live desktop, so the
greeter matches what you log into. A shell switch re-stages the data, and so does
the selector; the root path unit installs it with no `sddm` restart needed (the
next greeter start picks it up).

```
 session (you)                                         root (installed once)
 ─────────────                                         ─────────────────────
 switch-shell.sh ──detached──► render-sddm-theme.sh
 switch-sddm-theme.sh <mode> ─► render-sddm-theme.sh all
                                  │ writes
                                  ▼
                state/sddm-theme/  <shell>/{theme.conf.user,background.jpg,avatar.png,.complete}
                                   active   .stamp ──PathChanged──► dcli-sddm-theme.path
                                                                          │
                                                                          ▼
                                                       dcli-sddm-theme.service ► /usr/local/libexec/dcli-sddm-sync
                                                          (reads staging AS THE USER)   │
                                                                                        ▼
                          /usr/share/sddm/themes/dcli-<shell>/{theme.conf.user,assets/}  +  /etc/sddm.conf.d/zz-dcli-theme.conf
```

## One-time install

`dcli sync` installs the packages and renders the staging tree. The root half
needs `sudo`, which a hook never calls, so run it yourself — **as you, not with
sudo**:

```bash
~/.config/dcli/scripts/install-sddm-theme.sh     # install / upgrade
~/.config/dcli/scripts/uninstall-sddm-theme.sh   # remove ([--purge] also drops staging + saved mode)
```

Steps: dependencies (`modules/sddm-theme.yaml`), render, root-owned helper,
one theme directory per registry shell (`sddm/base` + the shell's overlay in
`sddm/themes/<shell>/`), the two systemd units + first sync, enable the path
unit. Re-run it after changing any QML under `sddm/` — **QML is installed only
by this script**, never by the sync. `scripts/doctor.sh` warns when anything is
stale. The drop-in is `/etc/sddm.conf.d/zz-dcli-theme.conf`; the `zz-` prefix
makes it win over the older `caelestia.conf`, whose `GreeterEnvironment` still
applies and which the uninstaller leaves alone.

## The selector

```bash
scripts/switch-sddm-theme.sh            # fuzzel (or a numbered prompt) picker
scripts/switch-sddm-theme.sh auto       # follow the running shell
scripts/switch-sddm-theme.sh omarchy    # pin one shell's look
scripts/switch-sddm-theme.sh --list | --status
```

The choice lives in `~/.local/state/dcli/sddm-theme` (`auto` when absent).

## The themes

| Shell | Theme | Palette source |
| --- | --- | --- |
| caelestia | upstream "locklike" (`/home/awhss/Projects/shell/real/sddm/themes/locklike`, background path patched to `.jpg`) | caelestia's own `~/.local/state/caelestia/theme/sddm-theme.conf`, verbatim |
| omarchy | upstream omarchy greeter (`~/.local/share/omarchy/default/sddm/omarchy`), unmodified | baked into its PNGs — it does not follow omarchy theme switches |
| ambxst, dms, end4, end4pc, xenon, ryoku | `sddm/base` greeter, one layout each (`card` / `minimal`) | the shell's own colour file (`PALETTE_SOURCES` in `render-sddm-theme.sh`) |
| noctalia | `sddm/base`, `minimal` | none is written (v5 is native), so matugen on its wallpaper |
| glyph | `sddm/base`, `dots` (Doto dot-matrix clock) | fixed: black, white, one red |

`sddm/base` reads `theme.conf.user` through SDDM's `config` object
(`components/Palette.qml`): `variant` (`card` `minimal` `terminal` `dots`),
`fontFamily`, `radius`, `cardRadius`, the eleven colours. The per-shell look is
`LOOK_TABLE` in the renderer. Wallpaper comes from `lib/wallpaper.sh`, the same
table GRUB uses; the avatar from `~/.face` / `~/.face.icon`.

Adding a shell: a registry record, a `LOOK_TABLE` row, a `PALETTE_SOURCES` row if
it writes colours, optionally `sddm/themes/<shell>/` for a bespoke theme, then
re-run the installer.

## Security model

Same as GRUB (docs/GRUB.md): nothing from the repo runs as root at runtime.

- QML is copied once, by the installer, under your sudo, into root-owned dirs;
  the sync never creates a theme or writes QML. `dcli-sddm-sync` only accepts a
  staged shell that already has an installed `dcli-<shell>` directory.
- The staging tree is archived **as the user** (`setpriv`), size-capped, members
  restricted to files and directories (a symlink rejects the whole archive).
- Per file: `theme.conf.user` must be plain `key=value` lines from a safe
  character set (no `$`, backtick, backslash, control bytes) ≤ 16 KiB;
  `background.jpg` / `avatar.png` need JPEG / PNG magic bytes and ≤ 8 MiB. A shell
  that fails keeps its previous data and the run exits non-zero.
- `active` must match `^[a-z0-9][a-z0-9-]*$` — that is the only thing that reaches
  `Current=`.
- Unit hardening: `ProtectSystem=strict` with write access to the themes dir,
  `/etc/sddm.conf.d` and `/var/lib/sddm` only, `PrivateNetwork`, `NoNewPrivileges`.

## Operating it

| Task | How |
| --- | --- |
| Re-render all | `scripts/render-sddm-theme.sh all` |
| Skip on a switch | `DCLI_SKIP_SDDM_THEME=1 scripts/switch-shell.sh <shell>` |
| Render log of the last switch | `~/.local/state/dcli/sddm-theme.log` |
| Why was data not installed | `journalctl -u dcli-sddm-theme.service` |
| Preview a theme without logging out | stage + `sddm-greeter-qt6 --test-mode --theme <dir>` (see `tests/smoke.sh` for a fixture) |
| Health | `scripts/doctor.sh` (SDDM lines are WARN, never FAIL) |

Unlike GRUB there is no wallpaper path watcher: the data refreshes on every shell
switch and every selector change. Re-run `render-sddm-theme.sh all` after
changing a wallpaper if you want the greeter to catch up before the next switch.

Test knobs (never set in production): `DCLI_SDDM_THEMES_DIR`,
`DCLI_SDDM_CONF_DIR`, `DCLI_SDDM_READER`, `DCLI_SDDM_ALLOW_NONROOT`,
`DCLI_SDDM_GREETER_CACHE` (sync); `DCLI_SDDM_STAGE` (renderer);
`DCLI_INSTALL_ROOT` (installer/uninstaller).
