# Terminal alt-v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a third, fully switchable terminal theme layer (`alt-v2`) with a unique starship prompt and fastfetch greeting for all ten registry shells.

**Architecture:** Extend the existing variant resolver in `scripts/lib/terminal-theme.sh` with a `prefer-alt-v2` flag and `_alt-v2/` template root, then render and link through the existing `terminal_render` / `apply-terminal-theme.sh` path. Configs are palette templates; rendered output stays under `state/terminal/render/alt-v2/`.

**Tech Stack:** Bash 5.3, fastfetch 2.70.0, starship 1.27.0, TOML/JSONC, the existing smoke fixture.

**Spec:** `docs/superpowers/specs/2026-11-06-terminal-alt-v2-design.md`

## Global Constraints

- fastfetch 2.70.0 and starship 1.27.0.
- Target 80–100 columns; no unfilled `{{token}}`.
- No new packages, fonts, network calls or shell plugins.
- Custom starship commands must be cheap (no network, no package queries).
- Keep `main` and `_alt` behaviour unchanged.
- Configs live in `dotfiles/terminal/_alt-v2/<shell>/`; rendered output is gitignored under `state/`.

## Review Focus

- A shell with no alt-v2 source must fall back to main/upstream instead of breaking a switch.
- A real file at `~/.config/starship.toml` or `~/.config/fastfetch` must still be backed up, never deleted.
- `--refresh` must follow alt-v2 templates and re-render on a palette change.
- `--use alt` and `--use upstream` must clear a standing alt-v2 choice.
- A starship custom command or fastfetch command that fails must not print an error or hang the prompt.

---

### Task 1: Variant plumbing and smoke coverage

**Files:**
- Modify: `scripts/lib/terminal-theme.sh`
- Modify: `scripts/apply-terminal-theme.sh`
- Modify: `scripts/doctor.sh:315-338`
- Test: `tests/smoke.sh:685-795`

**Interfaces:**
- Produces: `TERMINAL_PREFER_ALT_V2` (env, `1` = one-shot), `TERMINAL_PREFER_ALT_V2_FLAG` (state file), `terminal_prefers_alt_v2()`.
- Produces: `terminal_source` resolves `_alt-v2/<shell>` before `_alt/<shell>`.
- Produces: CLI `--alt-v2`, `--use alt-v2`.

- [ ] **Step 1: Add the failing smoke assertions**

Add an alt-v2 completeness check next to the existing terminal source check, and extend the template glob to `_alt-v2`. Add fixture assertions: `--dry-run --alt-v2 caelestia` names `render/alt-v2/...`; `--use alt-v2` persists across a switch; `--use alt` clears it; `--refresh` re-renders an alt-v2 link.

- [ ] **Step 2: Run the smoke test to verify it fails**

Run: `bash tests/smoke.sh`
Expected: FAIL — `terminal: no alt-v2 source for: …`, and the `--alt-v2` fixture assertions fail.

- [ ] **Step 3: Implement the resolver and CLI**

In `terminal-theme.sh`, add the flag path and `terminal_prefers_alt_v2()`; check it before `_alt` in `terminal_source`; map `_alt-v2/*` to `render/alt-v2/` in `terminal_rendered_path`.

In `apply-terminal-theme.sh`, parse `--alt-v2` as `TERMINAL_PREFER_ALT_V2=1`; `--use alt-v2` writes the flag and removes `prefer-alt`; `--use alt` writes `prefer-alt` and removes `prefer-alt-v2`; `--use upstream` removes both. Map `alt-v2/` in `--refresh`.

In `doctor.sh`, compute the alt-v2 target with `TERMINAL_PREFER_ALT_V2=1` and report it as `(alternate v2, --alt-v2)`.

- [ ] **Step 4: Create the ten alt-v2 directories**

Create `dotfiles/terminal/_alt-v2/<shell>/{starship.toml,fastfetch/{config.jsonc,logo.txt}}` for every registry shell with placeholder-free minimal configs, so the completeness and render tests can run before the creative pass. (The real configs replace them in Tasks 2–4.)

- [ ] **Step 5: Run the smoke test to verify the plumbing passes**

Run: `bash tests/smoke.sh`
Expected: PASS for the source/completeness and `--alt-v2` fixture assertions; every placeholder template renders cleanly.

- [ ] **Step 6: Commit**

```bash
git add scripts/lib/terminal-theme.sh scripts/apply-terminal-theme.sh scripts/doctor.sh tests/smoke.sh dotfiles/terminal/_alt-v2
git commit -m "feat(terminal): third alt-v2 variant, rendered and switchable"
```

---

### Task 2: Configs — caelestia, ambxst, dms, noctalia

**Files:**
- Replace: `dotfiles/terminal/_alt-v2/caelestia/{starship.toml,fastfetch/config.jsonc,fastfetch/logo.txt}`
- Replace: `dotfiles/terminal/_alt-v2/ambxst/…`
- Replace: `dotfiles/terminal/_alt-v2/dms/…`
- Replace: `dotfiles/terminal/_alt-v2/noctalia/…`

**Interfaces:**
- Consumes: `{{background}}`, `{{surface}}`, `{{surfaceContainer}}`, `{{surfaceVariant}}`, `{{text}}`, `{{primary}}`, `{{onPrimary}}`, `{{secondary}}`, `{{tertiary}}`, `{{error}}`, `{{outline}}` and their `.rgb` forms.
- Produces: four self-contained config pairs.

- [ ] **Step 1: caelestia — aurora tank**

Fastfetch: a full-width fluid wave header built from block glyphs, a constellation logo, “FLUID IDENTITY” title, density lines for CPU/memory with wave bars, and a `colors` footer. Starship: a capsule prompt with orbit rings, a wave seg, right-aligned time, and a morphing character.

- [ ] **Step 2: ambxst — AxLab boot console**

Fastfetch: `~ » Terminal ▏` header from axeni.de, an “OVERCLOCKED” status line, AxLab counter rows, a glossy Aero strip made of gradient blocks, and the blob as a small mark. Starship: a red prompt block, `~ »` path, `▏` cursor, and a “BUILD” segment for cmd duration.

- [ ] **Step 3: dms — modular synth patchbay**

Fastfetch: rack rails, knob glyphs (`◜◝`), patch cables between labelled ports, the duck on a scope, and a signal-flow footer. Starship: port blocks joined by cable glyphs, a duck operator, and a patch-bay git segment.

- [ ] **Step 4: noctalia — observatory logbook**

Fastfetch: “NOCTALIA OBSERVATORY” masthead, a live moon phase from `date`, a star-field logo, observation-log keys, and the owl at the eyepiece. Starship: moon-phase custom module from local time, constellation branch, owl character.

- [ ] **Step 5: Render and validate the four**

Run: `bash tests/smoke.sh`
Expected: PASS; no `fastfetch:` or `starship:` render complaints.

- [ ] **Step 6: Commit**

```bash
git add dotfiles/terminal/_alt-v2/{caelestia,ambxst,dms,noctalia}
git commit -m "feat(terminal): alt-v2 caelestia aurora, ambxst AxLab, dms patchbay, noctalia observatory"
```

---

### Task 3: Configs — end4, end4pc, omarchy, xenon

**Files:**
- Replace: `dotfiles/terminal/_alt-v2/end4/…`
- Replace: `dotfiles/terminal/_alt-v2/end4pc/…`
- Replace: `dotfiles/terminal/_alt-v2/omarchy/…`
- Replace: `dotfiles/terminal/_alt-v2/xenon/…`

**Interfaces:**
- Consumes: the palette tokens above.
- Produces: four self-contained config pairs.

- [ ] **Step 1: end4 — oscilloscope**

Fastfetch: “ILLOGICAL IMPULSE // LIVE SIGNAL”, a waveform generated from load average, channel readouts, glitch static, and the ii asterisk as a trace marker. Starship: a signal trace with `▁▂▃▅▂`, aperture mark, and latency duration.

- [ ] **Step 2: end4pc — preset gallery card**

Fastfetch: “PRESET pC-001”, a preview card frame, a 16-swatch strip via `colors`, tags, download/author lines, and a pctrade byline. Starship: a preset-picker line with chips, a download meter for cmd duration, and a remix mark.

- [ ] **Step 3: omarchy — omakase tasting menu**

Fastfetch: “OMA // OMAKASE”, courses with dotted leaders (“hardware”, “software”, “session”), a “CHEF'S CHOICE” stamp, and a doctrine line. Starship: an order ticket with course numbers, `◇` chef's mark, and a “NO SUBSTITUTIONS” error state.

- [ ] **Step 4: xenon — flight control**

Fastfetch: “XENON // FLIGHT CONTROL”, an ignition stack, thrust/fuel/thermal telemetry, T-minus uptime, and a flame plume. Starship: an afterburner ramp, Mach-style duration, and a flame character that changes on error.

- [ ] **Step 5: Render and validate the four**

Run: `bash tests/smoke.sh`
Expected: PASS; no `fastfetch:` or `starship:` render complaints.

- [ ] **Step 6: Commit**

```bash
git add dotfiles/terminal/_alt-v2/{end4,end4pc,omarchy,xenon}
git commit -m "feat(terminal): alt-v2 end4 scope, end4pc preset, omarchy omakase, xenon flight control"
```

---

### Task 4: Configs — glyph, ryoku

**Files:**
- Replace: `dotfiles/terminal/_alt-v2/glyph/…`
- Replace: `dotfiles/terminal/_alt-v2/ryoku/…`

**Interfaces:**
- Consumes: the palette tokens above; glyph uses its fixed black/white/red palette.
- Produces: two self-contained config pairs.

- [ ] **Step 1: glyph — LED dot-matrix panel**

Fastfetch: a dot-matrix masthead, `●○` pixel meters, fields as LED rows, one red live dot, and a `colors` strip in dots. Starship: a dot-matrix ticker, a single red pixel on error, and dotted separators.

- [ ] **Step 2: ryoku — Amaterasu editorial issue**

Fastfetch: “RYOKU — ISSUE 1.0 / AMATERASU”, a masthead rule, 力と美のために, a red sun mark, editorial columns for vitals/system/session, and a red seal. Starship: a masthead line, issue number, red sun prompt, and an editorial pull-quote for cmd duration.

- [ ] **Step 3: Render and validate the two**

Run: `bash tests/smoke.sh`
Expected: PASS; no `fastfetch:` or `starship:` render complaints.

- [ ] **Step 4: Commit**

```bash
git add dotfiles/terminal/_alt-v2/{glyph,ryoku}
git commit -m "feat(terminal): alt-v2 glyph dot matrix, ryoku Amaterasu editorial"
```

---

### Task 5: Docs and full gates

**Files:**
- Modify: `AGENTS.md` (command summary)
- Modify: `docs/ARCHITECTURE.md` (terminal paragraph + step 13)
- Modify: `devfiles/doc/ui-ux-design.md`
- Modify: `devfiles/doc/workflow.md`
- Modify: `devfiles/doc/project-structure.md`

- [ ] **Step 1: Document the third variant**

Name `--alt-v2` and `--use alt-v2` next to `--alt`/`--use alt`; describe `_alt-v2/` as the second opt-in set and list the ten identities in one paragraph.

- [ ] **Step 2: Run the full gates**

Run: `bash tests/smoke.sh`
Expected: PASS, zero FAIL lines.

Run: `node devfiles/tools/build-docs.mjs`
Expected: exits 0.

- [ ] **Step 3: Verify a shell end to end**

Run: `scripts/apply-terminal-theme.sh --dry-run --alt-v2 caelestia`
Expected: both links name `state/terminal/render/alt-v2/caelestia/…`.

- [ ] **Step 4: Commit**

```bash
git add AGENTS.md docs/ARCHITECTURE.md devfiles/doc docs/superpowers
git commit -m "docs(terminal): alt-v2 identities and switching"
```
