# Hyprland Lua config rules

This machine runs Hyprland 0.57 with a **Lua config** (`hl.*` API). The rules
below are the ones that bit this setup; older `.conf` documentation gets most of
them wrong. How the entry point dispatches between shells is in
[ARCHITECTURE.md](ARCHITECTURE.md).

## Parser and runtime

- Hyprland loads `hyprland.conf` **or** `hyprland.lua`, never both. This setup is
  all-Lua.
- **`hyprctl keyword …` is rejected outright** (`keyword can't work with
  non-legacy parsers` — and it exits 0, so callers believe it worked). Use
  `hyprctl eval 'hl.config({…})'` / `hl.bind(…)` / `hl.unbind(…)`.
- **`hyprctl dispatch <name> <args>` does not parse.** Dispatchers take Lua:
  `hyprctl dispatch 'hl.dsp.submap("global")'`. Anything bound as
  `hl.dsp.exec_cmd("hyprctl dispatch …")` is silently dead — use the native
  dispatcher (`hl.dsp.focus`, `hl.dsp.window.*`, `hl.dsp.layout`, `hl.dsp.global`).
- **A top-level `hl.exec_cmd()` re-runs on every reload.** Wrap startup commands in
  `hl.on("hyprland.start", function() … end)` — the `exec-once` equivalent. Getting
  this wrong spawns a duplicate shell on every switch. Conversely, that event
  fires only at compositor start, **never on `hyprctl reload`** — and a shell
  switch is a reload, so `switch-shell.sh` launches the shell itself.
- Hyprland applies its own `env` (`hl.env`) only for clients spawned from the
  config and only at startup; a session started before a var was added never has
  it. Scripts must set such vars explicitly, and session-wide vars belong in
  `dotfiles/environment.d`.
- **`hyprctl reload` wipes dynamically applied binds**, so whatever applies them
  (caelestia's `KeybindApplier.qml`) must re-run on the `configreloaded` event.
- Types are strict: `explicit_column_widths` takes a **string**, not a table, and
  `hl.animation` needs a curve registered via `hl.curve(...)`.

## Always `hl.unbind` before rebinding

Two binds on one combo **both fire** (a duplicated launcher bind toggles it open
then shut). When a shell config takes over a combo another layer already bound
(omarchy's SUPER binds, the caelestia defaults), `hl.unbind` it first. Bind
options: `{ release = true }` (bindr), `{ locked = true }` (bindl),
`{ repeating = true }` (binde), `{ mouse = true }` (bindm), `{ click = true }`
(bindc — a tap, gated by `binds:drag_threshold`, so it can share a key with a drag
bind: caelestia's Super+Z/X are tap-to-switch-workspace, hold-to-move/resize).

Check for doubles with `hyprctl binds -j | jq 'group_by([.modmask,.key,.release])'`.
`hyprctl binds -j` emitted **invalid JSON on 0.56** whenever binds carried
descriptions (keys shifted against values), which is every omarchy bind. On 0.57
it parses under caelestia (168 binds); it is untested under omarchy, so the
plain-text awk recipe in [shells/omarchy.md](shells/omarchy.md) is kept
defensively.

## `require` vs `dofile`, and namespacing

Hyprland puts only the main config's directory (`~/.config/hypr`) on
`package.path`. The entry point appends the active shell's directory after it
(after, because the caelestia CLI writes the live `scheme/current.lua` into
`~/.config/hypr`).

- **`require()` only files Hyprland's autoreload must track** — the per-shell
  `shells/<name>/hyprmod.lua` (written by the HyprMod GUI) and shell-owned
  runtime files such as end4's `shellOverrides/main.lua`. `dofile()` everything
  else.
- **Standalone shells use fully-qualified names:** `require("common.input")` for
  the shared layer and `require("shells.<name>.hyprland.keybinds")` for their own
  files, never a bare `hyprland.keybinds`. `~/.config/hypr/hyprland/` is a **real
  directory** that upstream configurators (end4 and end4-pC settings apps)
  write into; a short name like `hyprland.rules` can resolve into it and load
  someone else's file, silently.
- **omarchy cannot `require` its own house code at all.** Its `bootstrap.lua` puts
  `~/.config/?.lua` on `package.path`, so `require("hypr.x")` anywhere in omarchy
  resolves into the shared `~/.config/hypr`. It `dofile()`s the `common/` files
  and its own `shells/omarchy/hyprland/*.lua`, and no file named `monitors`,
  `input`, `bindings`, `looknfeel` or `autostart` may ever exist in
  `dotfiles/hypr/` (they are the names omarchy's user config loads).

## The shared `common/` layer

`dotfiles/hypr/common/*.lua` holds the house preferences once: `monitor`, `input`
(`us,ara`, `grp:win_space_toggle`, `ctrl:nocaps`, sensitivity 0.3, flat accel),
`bind-options`, `gestures`, `scrolling`, `general`, `decoration`, `animations`,
`workspace-slide`, `misc`, `rules`, `env`. Standalone shells opt in file by file
(dms, noctalia, xenon and ryoku take almost all of them; end4pc leaves gaps,
decoration, layout and animations to its settings app; end4 keeps its upstream
tree and only layers `custom/`). ambxst's overrides file takes five of them,
omarchy `dofile()`s `monitor`, `input` and `gestures`. **caelestia does not use
`common/`** — its input lives in its fork's `hypr-vars.lua`; **ryoku does not
load its checkout's Hyprland config at all** (the distro owns that tree, dcli
owns `~/.config/hypr`), so its binds are house binds plus `ryoku-shell` verbs.
`hl.config` merges, so a shell file loaded after a `common/` file wins on any key
it sets again; set each key once.

## Verifying a change

```bash
hyprctl configerrors                       # empty when clean (live session)

# Any shell's config, without switching to it:
DCLI_HYPRMOD_SHELL=<shell> Hyprland --verify-config -c ~/.config/hypr/hyprland.lua
# expect "config ok"; run it for every shell after touching common/ or the entry point

scripts/switch-shell.sh --dry-run <shell>  # the teardown/launch plan; touches nothing
bash tests/smoke.sh
```

`DCLI_HYPRMOD_SHELL` is honoured by `hyprland.lua` only when it names a registry
shell (it is what `scripts/edit-hypr.sh` sets for HyprMod); Hyprland itself never
has it set, so the verify run is the only place it changes behaviour.
