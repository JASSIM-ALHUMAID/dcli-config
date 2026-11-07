# Terminal alt-v2 — design

Date: 2026-11-06

## Intent

Give every registry shell a second, deliberately non-generic terminal identity:
one starship prompt and one fastfetch greeting per shell, each built from that
shell's own upstream world rather than from a shared template. The set is a new
layer (`alt-v2`), selectable alongside the current main configs and the existing
`_alt/` alternates.

## Goals

- All ten registry shells get `_alt-v2/<shell>/starship.toml` and
  `_alt-v2/<shell>/fastfetch/{config.jsonc,logo.txt}`.
- Every pair is structurally distinct: no shared frame, key style, prompt shape
  or logo between shells.
- Each config is palette-templated (`{{primary}}`, `{{primary.rgb}}`, …) and
  renders through the existing `terminal_render` path.
- Wearing it needs one switch: `apply-terminal-theme.sh --alt-v2 <shell>` for one
  session, or `--use alt-v2` to persist across shell switches.

## Non-goals

- Replacing `_alt/` or main; all three stay available.
- New packages, fonts, network calls or shell plugins.
- Changing the shell switcher's launch/teardown lifecycle.

## Approaches considered

- **A — third variant layer (chosen).** `_alt-v2/` plus a `prefer-alt-v2` flag,
  resolved by the same `terminal_source` / `terminal_render` code as main and
  `_alt`. Keeps A/B/C comparison and reuses the battle-tested renderer.
- **B — replace `_alt/`.** Less plumbing, but loses the current alternates.
- **C — unwired pack.** No resolver changes, but every use needs manual symlinks.

## Per-shell identities (alt-v2)

| Shell | Fastfetch | Starship |
|---|---|---|
| caelestia | Aurora tank: fluid wave header, density bars, constellation marks | Morphing capsule with orbit rings and a fluid wave |
| ambxst | AxLab boot console: `~ » Terminal ▏`, overclock counters, glossy Aero strip | AxLab shell line with red prompt block and readout |
| dms | Modular synth patchbay: rack rails, knobs, patch cables, duck on the scope | Patch-cable prompt with port blocks and a duck operator |
| noctalia | Observatory logbook: live moon phase, star field, owl at the eyepiece | Moon-phase prompt computed from local time |
| end4 | Oscilloscope: waveform trace from load, channel readouts, glitch static | Signal-trace prompt with latency and aperture mark |
| end4pc | Preset gallery card: preset number, swatch strip, tags, byline | Preset-picker prompt with chips and a download meter |
| omarchy | Omakase tasting menu: courses, dotted leaders, doctrine stamp | Order ticket with course numbers and chef's mark |
| xenon | Flight control: ignition stack, thrust/fuel telemetry, T-minus | Afterburner ramp with Mach-style duration |
| glyph | LED dot-matrix panel: `●○` pixel fields, one red live dot | Dot-matrix ticker with a single red pixel |
| ryoku | Amaterasu editorial issue: masthead, 力と美のために, red sun, rules | Magazine masthead with issue line and red sun |

## Mechanics

- `terminal-theme.sh` gains `TERMINAL_PREFER_ALT_V2` / `prefer-alt-v2`, with
  alt-v2 taking precedence over `_alt`, then ours/upstream as today.
- `terminal_rendered_path` maps `_alt-v2/*` to `state/terminal/render/alt-v2/`.
- `apply-terminal-theme.sh` accepts `--alt-v2`, and `--use alt-v2`; `--use alt`
  and `--use upstream` keep their meaning. `--refresh` reads the worn variant
  from the render path, so it needs no flag change.
- `doctor.sh` recognises all three variants.
- `tests/smoke.sh` renders and validates every main, `_alt` and `_alt-v2`
  template, and exercises `--alt-v2` plus `--use alt-v2` persistence.

## Constraints

- fastfetch 2.70.0, starship 1.27.0.
- Terminal width target: 80–100 columns.
- No unfilled `{{token}}`; smoke fails the render.
- Custom starship commands must be cheap (no network, no package queries).
- Configs are committed; rendered output stays under `state/` (gitignored).

## Success

`bash tests/smoke.sh` passes, `apply-terminal-theme.sh --dry-run --alt-v2 <shell>`
points both links at the alt-v2 render tree for all ten shells, and each rendered
pair is accepted by fastfetch/starship with the fixture palette.

## Revision — 2026-11-07 (execution pass)

The identities above stand; the execution was redone.

- **Logos are the shells' real brand marks**: `logo.png` (square-padded, from
  the picker icons; caelestia's black mark is tinted light) shown through
  fastfetch's `kitty` type, sized to the module line count. Hand-drawn ASCII
  figures are gone. Review note: a logo drawn while Hyprland is still tiling the
  new terminal looks torn; wait for the window to settle before judging it.
- **One skeleton, shell-specific dressing.** Logo (width = 2 × rows, height =
  module line count), title line, rule, ten aligned rows, footer. Keys are
  padded in the config, never positioned with cursor escapes.
- **Safe glyphs only.** `█▒░▰▱` render as tall or thin fragments in the target
  font; bars use `● ○ ■ □ ◆ ◇ ▪ ▫ ▬ ▭ ━ ╌ ·`.
- **Prompts have no right-hand frame.** Line 1 is identity · path · git, fill,
  duration · time; line 2 is the character. Powerline caps (`\ue0b0`–`\ue0b6`)
  join segments where a shell's identity is a capsule or ramp.
- Dim text uses `secondary`/`outline` depending on contrast; glyph's `outline`
  (`#2a2a2a`) is invisible on black, so glyph uses `secondary`.
- **alt-v3 (pixel edition).** `_alt-v3/<shell>/fastfetch/` keeps the pixel-art
  logos as their own layer: identical modules to alt-v2, `logo.txt` instead of
  `logo.png`, prompt inherited from alt-v2. `--alt-v3` / `--use alt-v3`;
  precedence v3 > v2 > alt. Logos in v2 are 640 px (sharp on a 1920×1200
  panel at the ~340 px the logo occupies).
