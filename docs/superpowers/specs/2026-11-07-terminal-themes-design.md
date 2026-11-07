# Terminal themes — design

Date: 2026-11-07

## Intent

Every existing prompt/greeting (main, `_alt`, `_alt-v2`, `_alt-v3`) is the same
skeleton: a logo beside a key/value list, dressed per shell. This adds three
**shell-independent themes**. Each is one concept carried through both the
fastfetch greeting and the starship prompt, in a different medium:

| Theme | Medium | Greeting | Prompt |
|---|---|---|---|
| **horizon** | animated image (APNG) | the sky over Riyadh *right now*: sun height from the real time, the real moon phase, stars at night, dune ridges; almanac + machine stats beside it | a sunrise→sunset bar with the sun (☀) at its real position, a moon (☾) crossing at night |
| **gallery** | generative still (PNG) | a new abstract painting every terminal, in the live shell palette, whose composition encodes machine stats; a museum wall label beside it | gallery wayfinding: palette swatches, path, branch |
| **transit** | text only | the system as a metro map: a boot line firmware → kernel → init → compositor → shell → terminal, branch lines for CPU / memory / storage, a service-status footer | the path as metro stations, the git branch as a transfer, a failed command as a service disruption |

A theme is worn regardless of the running shell and survives shell switches.
The per-shell layers stay as they are.

## Non-goals

- Changing or removing main / `_alt` / `_alt-v2` / `_alt-v3`.
- Network calls, package queries, or new fonts. Pillow is the only new
  runtime dependency (installed; must be declared in a module).
- Image support outside WezTerm (the house terminal). Other terminals must
  still get a readable greeting; they may lose the picture.

## Verified platform facts (2026-11-07)

- WezTerm animates APNG, animated WebP and GIF sent through fastfetch's
  `"type": "iterm"` logo (screenshots taken 0.6 s apart show the frames
  alternate). GIF's 256 colours band gradients, so animation is **APNG**.
- WezTerm cells at the house font (JetBrainsMono NF 11 pt) measure
  **12 × 30 px**. fastfetch stretches an image to fill `width × height` cells
  unless `"preserveAspectRatio": true`. Images may be drawn larger than their
  box and scaled down (alt-v2 shows a 640 px logo in a ~28 × 14 box, sharp).
- If fastfetch's image logo file is missing, it falls back to the distro ASCII
  logo and still prints every module (exit 0).
- fastfetch 2.70 `command` module: `{"type":"command","text":"<sh>","format":"{result}"}`.
- starship 1.27 passes ANSI escapes from a `custom` module's output through to
  the prompt unchanged.
- Python 3.14 + Pillow 13 start and draw a simple 640 × 320 image in ~80 ms.

## Theme layer

- Location: `dotfiles/terminal/_themes/<theme>/starship.toml` and
  `dotfiles/terminal/_themes/<theme>/fastfetch/` (`config.jsonc` + assets).
  A theme exists when both files exist. They are templates like every other
  layer, rendered with the **running shell's** palette.
- Worn once: `apply-terminal-theme.sh --theme <name> <shell>` (until the next
  switch). Kept: `--use theme:<name>` writes the name to
  `state/terminal/theme` and removes the `prefer-alt*` flags; `--use
  alt|alt-v2|alt-v3|upstream` removes `state/terminal/theme`.
- Precedence: one-shot `--theme` > one-shot `--alt-v3` > `--alt-v2` > `--alt`
  > saved theme > saved alt-v3 > alt-v2 > alt > ours/upstream.
- An unknown name on the command line is a usage error (exit 2). A saved name
  whose directory has gone falls through to the next layer with a one-line
  warning on stderr — never a broken prompt.
- Rendered to `state/terminal/render/theme/<theme>/…`. `--refresh` follows a
  theme link and re-renders with the running shell's palette.
- New template token `{{live}}`, filled only in `_themes` templates, with the
  absolute path `state/terminal/live/<theme>`. An unfilled token still fails
  the render.

## Live art

horizon and gallery draw their logo with Python ("live art"). A greeting must
never wait for a full paint, so art is painted **ahead of time** and shown
from disk.

- `state/terminal/live/<theme>` is a symlink to the newest generation
  directory `state/terminal/live/.<theme>.<ns>/`. A paint writes a new
  generation, then swaps the symlink with one atomic rename; the previous
  generation is kept (a reader may still have it open), older ones are deleted.
  A generation holds `logo.png`, `expires` (epoch seconds), `kind`
  (`still`|`full`) and theme-specific text files.
- A theme's rendered fastfetch directory holds `live-art`, a one-line file
  containing `{{live}}`. Its presence is how the greeting knows art is involved.
- **Greeting flow** (fish_greeting): if `~/.config/fastfetch/live-art` exists,
  read its directory; if `expires` is missing, unreadable or ≤ now, run the
  painter in `--still` mode synchronously (budget ≤ 300 ms); run fastfetch;
  then start the painter in `--next` mode in the background.
- **Painter**: `scripts/paint-terminal-art.sh --still|--next [--theme <name>]`
  resolves the theme (default: the worn `live-art`), the running shell's
  palette and the live dir, then runs the Python entry point. With no live
  theme worn it exits 0 and does nothing. One paint per theme at a time
  (lock): `--next` skips if a paint is running; `--still` waits ≤ 2 s, then
  gives up (the old art is shown).
- **Policy**: `--still` paints only when art is missing or expired. `--next`
  paints the full version unless the current art is `full` and unexpired, or
  repaints every time for themes that ask for it (gallery).
- **Failure**: an exception is written with detail to
  `state/terminal/live/paint.log` (last 200 lines kept), the old art stays, and
  the painter exits 1. fish never shows painter output. `doctor.sh` reports
  the last failure and a missing Pillow when a live theme is worn.

## horizon

- Location: Riyadh, 24.7136 N 46.6753 E, label "Riyadh". Override with
  `DCLI_HORIZON_LATLON="<lat>,<lon>"` and `DCLI_HORIZON_PLACE`; an invalid
  override prints a warning and falls back to Riyadh. Time zone: the system's.
- The sky is valid for 10-minute buckets: `expires` = end of the current bucket.
- Sun: NOAA low-precision solar position (altitude, azimuth, sunrise, sunset,
  solar noon). Moon: low-precision ephemeris (~1°) for altitude and azimuth;
  illuminated fraction and waxing/waning from sun–moon elongation.
- Sky by sun altitude: night < −18°, astronomical twilight −18..−12, nautical
  −12..−6, civil −6..−0.833, golden hour −0.833..6, day > 6. Colours blend
  continuously between key altitudes.
- View: a south-facing window, azimuth 60°→300° mapped linearly across the
  width; horizon at 72 % of the height; altitude 0–90° above it. Bodies outside
  the window are not drawn, but their light still colours the sky.
- Ground: three dune ridges, seeded by the local date (the same land all day),
  lit from the sky's colour.
- Stars from sun altitude < −6° (fully visible by −18°), seeded by date. The
  moon is drawn with its real lit fraction and lit side when above the horizon.
- Image 792 × 540 px (1.5 × a 44 × 12 cell box), `preserveAspectRatio`. Still:
  one frame, ≤ 500 KB. Full: 12–16 frames, 2–3 s loop, infinite, ≤ 2 MB: stars
  twinkle at night; heat shimmer or drifting haze by day.
- Text written per paint: `sun` (`<sunrise> <sunset> <next sunrise>` as epoch
  seconds, for the prompt), plus human lines for the greeting: place and date,
  sky state, sunrise / sunset / day length, moon phase name and % lit.
- Prompt: line 1 = a 15-cell sun bar (`╶──☀──╴`, position = elapsed share
  of daylight; at night ☾ crosses sunset→next sunrise), path, git, fill,
  duration, time; line 2 = `›`. The bar is hidden when `sun` is missing.

## gallery

- A new painting for every greeting; `expires` is never (2³¹−1). Still and
  full are the same static PNG.
- Five compositions: `squares` (nested squares), `grid` (rectilinear grid with
  bars), `fields` (soft-edged stacked colour fields), `orbits` (circles and
  arcs), `stripes` (hard-edged bands). Chosen by seed.
- Colours come from the live shell palette (`primary`, `secondary`,
  `tertiary`, `error`, `surfaceVariant`, `text`), adjusted in lightness until
  every pair used is clearly distinct (RGB distance ≥ 48).
- Data in the picture: memory in use = area share of the dominant element;
  disk in use = share of the second element; CPU threads → divisions
  `clamp(round(√threads), 2, 6)`; load per thread → tension (offset and
  rotation, 0..1); uptime hours → accent count `clamp(h, 1, 12)`.
- Rendered 720 × 720 RGBA: canvas on a mat inside a thin frame, soft shadow,
  transparent around it. ≤ 400 KB.
- Wall label files: `title` ("<Form> for a <Adjective> <Noun>, No. <n>",
  word lists ≥ 12 each), `credit` ("<OS>, <year> · pigment on silicon"),
  `note` (one sentence ≤ 104 characters stating the real data mapping with
  the real number), `accession` (`<year>.<day of year>.<sequence>`). The
  sequence is persisted and goes up by one per painting.
- Greeting: label typography beside the painting: title (bold), credit,
  facts as label lines (dimensions = memory × threads, on view = uptime,
  collection = packages, provenance = kernel), the note, the accession.
- Prompt: three palette swatches (`■`), path, `╱`, branch, duration; line 2 `›`.

## transit

- Text only: fixed line colours, no palette tokens, no live art.
  Boot `#E8453C`, Compute `#2F7DE1`, Memory `#2FAE66`, Storage `#F2A93B`,
  Session `#9B5DE5`, track `#5B6170`, text `#E6E6E6`, dim `#8A90A0`.
- Logo: an original line-map emblem (`logo.txt`, ANSI, ≤ 24 × 12 cells), three
  coloured lines meeting at interchange rings. No real transit authority's
  roundel or mark.
- Greeting: title row, coloured rule, a vertical boot line whose fastfetch keys
  are the track (`●━━`, `┃`, `┣━━◆` for branches), stations with real values,
  "you are here" at the terminal, and a service-status footer (uptime,
  packages).
- Prompt: the path as stations, the last 4 at most (`┄` before them), `~`
  for home: `◯ ~ ━━ ◯ .config ━━ ◉ dcli`; the branch as `⇄ main`; a failed
  command as `⚠ disruption · exit N` (native `status`); ≥ 2 s as
  `delayed 12s`; time; line 2 `›` (green, red on error). The station command
  is one `awk` over `$PWD`.

## Shared constraints

- fastfetch 2.70.0, starship 1.27.0, Python 3.14, Pillow 13; numpy is not
  allowed (not declared, not needed).
- Width target 80–100 columns. Glyphs that render badly in the house font are
  not used: `█▒░▰▱`. Bars use `● ○ ■ □ ◆ ◇ ▪ ▫ ▬ ▭ ━ ╌ ·`.
- Prompts: no right-hand frame; `command_timeout = 300`; custom commands are
  one `sh`/`awk` call with no network or package queries.
- Configs are committed templates; everything rendered or painted lives under
  `state/` (gitignored).

## Success

`bash tests/smoke.sh` passes, including the Python unit tests for the painter
and both generators. `apply-terminal-theme.sh --dry-run --theme <t> <shell>`
targets `render/theme/<t>/` for all three themes and any shell. Each theme's
greeting and prompt, screenshotted in a real WezTerm window, looks finished,
and horizon's screenshots show the animation. `docs/` and `devfiles/doc/`
describe the layer, and `devfiles/doc/terminal-theme-ideas.md` keeps the ideas
that were not built.
