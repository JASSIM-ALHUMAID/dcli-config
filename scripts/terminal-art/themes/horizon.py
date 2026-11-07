"""horizon: the sky over Riyadh, right now, painted for the terminal greeting.

A south-facing window onto the real sky: the sun at its true height and bearing,
the moon with its true phase and tilted lit limb, stars once the sun is far
enough below the horizon, and three dune ridges lit by whatever light there is.
The picture is a function of the clock, the location and the local date alone
(the same land all day, new land tomorrow); the shell's palette is ignored.

STILL paints one frame fast enough for a greeting to wait for. FULL paints a
looping APNG: stars twinkle at night, the horizon shimmers in the heat by day.
The sky is valid for SKY_BUCKET_S seconds, then the next bucket's art is due.

Besides ``logo.png`` each paint writes one-line text files for the greeting
(``place``, ``sky``, ``almanac``, ``daylight``, ``moon``) and ``sun`` for the
prompt: ``<sunrise> <sunset> <next sunrise>`` in epoch seconds, where the
sunrise and sunset belong to the daylight at or before now and the sunrise is
the next one after now, so the prompt can place the sun (or the moon, at
night) from those three numbers and the clock alone.
"""

import functools
import math
import os
import random
import sys
from collections.abc import Sequence
from dataclasses import dataclass
from datetime import date, datetime, timedelta, tzinfo
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

from artlib import RGB, Mode, PaintContext, Painted, write_text_atomic
from themes.sky import (
    DEFAULT_LOCALTIME,
    HORIZON_Y,
    SKY_SIZE,
    Location,
    SkyState,
    SunTimes,
    bearing,
    bucket_expiry,
    location_from_env,
    moon_illumination,
    moon_phase_name,
    moon_position,
    resolve_zone,
    sky_colours,
    sky_gradient,
    sky_state,
    star_visibility,
    sun_light,
    sun_position,
    sun_times,
    twilight_glow,
    view_x,
    view_y,
)

REPAINT_AFTER_GREETING = False

# ── picture ──────────────────────────────────────────────────────────────────
WIDTH, HEIGHT = SKY_SIZE
HORIZON_PX = round(HORIZON_Y * HEIGHT)
LOGO_NAME = "logo.png"
FRAME_COUNT = 14
FRAME_MS = 180
BREATH_DEPTH = 0.07  # the sun's glow swells and settles this much over a loop
GLOW_BOOST = 1.2
SKY_CURVE = 2.0  # >1 keeps the zenith blue and gathers the colour at the horizon
MIDDLE_AT = 0.55  # where along that curve the sky's middle colour sits

# A glow mask is a 256 px radial gradient whose edge (distance 128) reads this value.
RADIAL_EDGE = 180

SUN_RADIUS_PX = 13
SUN_VISIBLE_FROM = -1.5
SUN_CORE_WHITE_ALTITUDE = 22.0
SUN_WHITE_ALTITUDE = 30.0  # the disc is orange on the horizon and white from here up
MOON_RADIUS_PX = 20
MOON_VISIBLE_FROM = -2.5
MOON_SUPERSAMPLE = 4
DISC_SUPERSAMPLE = 8
MOON_SOFTEN_PX = 0.7
MOON_DAYLIGHT_OPACITY = 0.55
MOON_LIGHT_RADIUS_PX = 150
MOON_DIM_RADIUS_PX = 150

# Stars: how many, how far down the sky, and how hard they twinkle.
STAR_COUNT = 230
STAR_CEILING_PX = HORIZON_PX - 26
STAR_ALPHA_LEVELS = 12
TWINKLE_DEPTH = (0.12, 0.38)
TWINKLE_CYCLES = (1, 2, 3)
STAR_TINTS: tuple[tuple[RGB, float], ...] = (
    ((236, 241, 255), 0.70),
    ((190, 210, 255), 0.15),
    ((255, 226, 192), 0.15),
)

# Heat shimmer: rows around the horizon sway sideways while the sun is up.
SHIMMER_SPAN_PX = 56
SHIMMER_SIGMA_PX = 24.0
SHIMMER_AMPLITUDE_PX = 2.6
SHIMMER_WAVELENGTH_PX = 38.0
SHIMMER_FULL_ALTITUDE = 8.0
SHIMMER_NONE_ALTITUDE = -8.0

# ── land tunables ────────────────────────────────────────────────────────────
SAND: RGB = (226, 186, 136)
NIGHT_SAND: RGB = (110, 128, 190)  # colour drains from sand in moonlight and what is left is cold
AIRGLOW: tuple[float, float, float] = (0.030, 0.040, 0.075)  # light that never leaves the night sky
AMBIENT_GAIN = 0.55
FILL_DESATURATION = 0.6
DIRECT_GAIN = 0.9
MOONLIGHT: RGB = (150, 178, 240)
DUST_HAZE: RGB = (236, 204, 156)  # what distant dunes fade into on a bright day
DUST_SHARE = 0.75
DAYLIGHT_HAZE_ALTITUDE = 12.0
MOONLIGHT_GAIN = 0.95
MIN_LIGHT_ELEVATION = 4.0
LIGHT_SWAY_DEGREES = 35.0
TONE_KNEE = 0.7
WRAP_LIGHT = 0.2  # light wraps round a slope's edge, so the shadow side is not black
RIM_BOOST = 0.6
RIM_FADE_ALTITUDE = 40.0
RIM_HIGH_SUN_SHARE = 0.65  # how much of the rim light a high sun takes away
SLOPE_REACH_PX = 2
SHEAR_PAD_PX = 480
MAX_SHEAR = 1.6
MIN_SHEAR = 0.3  # shadow edges always lean a little; vertical seams look like cut paper
MIN_SHEAR_ELEVATION = 0.18
SHEAR_GAIN = 0.7


@dataclass(frozen=True)
class RidgeSpec:
    """One dune ridge: where its crest line wanders, how big its crests are, how hazy it is."""

    base_px: int  # below the horizon line: the ridge's lowest crest line
    rise_px: int
    crests: tuple[int, int]
    crest_width_px: int
    haze: float  # share of the horizon's colour mixed in (atmospheric depth)
    darkening: float  # how much darker the dune is at its foot than at its crest


RIDGES: tuple[RidgeSpec, ...] = (
    RidgeSpec(base_px=4, rise_px=22, crests=(5, 7), crest_width_px=150, haze=0.55, darkening=0.20),
    RidgeSpec(base_px=62, rise_px=42, crests=(4, 5), crest_width_px=210, haze=0.28, darkening=0.30),
    RidgeSpec(base_px=128, rise_px=64, crests=(3, 4), crest_width_px=300, haze=0.06, darkening=0.40),
)
SLIP_FACE_RATIO = 0.45  # the steep side of a crest is this fraction as wide as the gentle one
CREST_SHARPNESS = 1.6

# ── words ────────────────────────────────────────────────────────────────────
LABEL_COLUMNS = 32
WEEKDAYS = ("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")
MONTHS = (
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December",
)  # fmt: skip
MINUS = "−"
SEPARATOR = " · "
ELLIPSIS = "…"


# ── the scene: what the sky is doing ─────────────────────────────────────────
@dataclass(frozen=True)
class Body:
    """A sun or moon position in degrees."""

    altitude: float
    azimuth: float


@dataclass(frozen=True)
class MoonView:
    """The moon as seen now: where, how much of it is lit, and which way its lit limb points."""

    position: Body
    fraction: float
    waxing: bool
    limb_bearing: float


@dataclass(frozen=True)
class Scene:
    """Everything the sky depends on, computed once per paint."""

    when: datetime
    day: date
    location: Location
    sun: Body
    moon: MoonView
    state: SkyState
    today: SunTimes
    cycle: tuple[int, int, int]


def build_scene(when: datetime, location: Location, zone: tzinfo) -> Scene:
    """The sky at ``when`` over ``location``; day boundaries follow ``zone``."""
    day = when.astimezone(zone).date()
    today = sun_times(day, location, zone)
    sun = Body(*sun_position(when, location))
    moon_position_now = Body(*moon_position(when, location))
    fraction, waxing = moon_illumination(when)
    limb = bearing(moon_position_now.altitude, moon_position_now.azimuth, sun.altitude, sun.azimuth)
    if when < today.sunrise:
        yesterday = sun_times(day - timedelta(days=1), location, zone)
        cycle = (yesterday.sunrise, yesterday.sunset, today.sunrise)
    else:
        tomorrow = sun_times(day + timedelta(days=1), location, zone)
        cycle = (today.sunrise, today.sunset, tomorrow.sunrise)
    return Scene(
        when=when,
        day=day,
        location=location,
        sun=sun,
        moon=MoonView(moon_position_now, fraction, waxing, limb),
        state=sky_state(sun.altitude),
        today=today,
        cycle=(round(cycle[0].timestamp()), round(cycle[1].timestamp()), round(cycle[2].timestamp())),
    )


# ── small colour helpers ─────────────────────────────────────────────────────
def _mix(a: Sequence[float], b: Sequence[float], share: float) -> tuple[float, ...]:
    return tuple(x + (y - x) * share for x, y in zip(a, b))


def _clamp(value: float, low: float = 0.0, high: float = 1.0) -> float:
    return min(high, max(low, value))


def _to_rgb(values: Sequence[float]) -> RGB:
    red, green, blue = (round(_clamp(v, 0.0, 255.0)) for v in values)
    return red, green, blue


# ── glows and discs ──────────────────────────────────────────────────────────
@functools.cache
def _glow_mask(half_width: int, half_height: int, strength: float, falloff: float) -> Image.Image:
    """An elliptical alpha falloff: ``strength`` at the centre, 0 at the edge, shaped by ``falloff``."""
    table = [round(255 * strength * (1.0 - min(1.0, v / RADIAL_EDGE)) ** falloff) for v in range(256)]
    mask = Image.radial_gradient("L").point(table)
    return mask.resize((2 * half_width, 2 * half_height), Image.Resampling.BILINEAR)


def _glow(canvas: Image.Image, centre: tuple[float, float], radii: tuple[int, int], colour: RGB, strength: float, falloff: float = 2.0) -> None:
    """Light up ``canvas`` around ``centre``; ``radii`` is the half width and height of the glow."""
    if strength <= 0.0:
        return
    mask = _glow_mask(radii[0], radii[1], round(_clamp(strength), 3), falloff)
    canvas.paste(colour, (round(centre[0]) - radii[0], round(centre[1]) - radii[1]), mask)


@functools.cache
def _disc_mask(radius: int) -> Image.Image:
    """An anti-aliased disc inside a square of side 2*radius."""
    size = 2 * radius * DISC_SUPERSAMPLE
    big = Image.new("L", (size, size), 0)
    ImageDraw.Draw(big).ellipse((0, 0, size - 1, size - 1), fill=255)
    return big.resize((2 * radius, 2 * radius), Image.Resampling.BOX)


# ── sky ──────────────────────────────────────────────────────────────────────
def _gradient_at(zenith: RGB, middle: RGB, horizon: RGB, depth: float) -> tuple[float, ...]:
    """The sky's colour ``depth`` (0 at the top, 1 at the horizon; more is below it) of the way down."""
    position = min(1.0, depth) ** SKY_CURVE
    if position < MIDDLE_AT:
        return _mix(zenith, middle, position / MIDDLE_AT)
    return _mix(middle, horizon, (position - MIDDLE_AT) / (1.0 - MIDDLE_AT))


def _render_sky(scene: Scene, breath: float = 1.0) -> Image.Image:
    """Gradient, twilight glows, sun and moon: everything that is not stars, land or heat."""
    altitude = scene.sun.altitude
    zenith, middle, horizon = sky_gradient(altitude)
    column = Image.new("RGB", (1, HEIGHT))
    column.putdata([_to_rgb(_gradient_at(zenith, middle, horizon, row / HORIZON_PX)) for row in range(HEIGHT)])
    sky = column.resize((WIDTH, HEIGHT), Image.Resampling.NEAREST)

    sun_x, sun_y = view_x(scene.sun.azimuth), view_y(altitude)
    glow_colour, glow_strength = twilight_glow(altitude)
    along_horizon = (round(WIDTH * 0.46), round(HORIZON_PX * 0.74))
    _glow(sky, (sun_x, min(sun_y, HORIZON_PX + 20)), along_horizon, glow_colour, min(1.0, glow_strength * GLOW_BOOST) * breath, 1.7)
    opposite_x = view_x(scene.sun.azimuth + 180.0)
    belt = _clamp((altitude + 9.0) / 6.0) * _clamp((1.0 - altitude) / 3.0)
    _glow(sky, (opposite_x, HORIZON_PX + 10), (round(WIDTH * 0.5), round(HORIZON_PX * 0.42)), (205, 130, 160), 0.30 * belt, 1.9)

    moon = scene.moon
    if moon.position.altitude > MOON_VISIBLE_FROM:
        _paint_moon(sky, scene)
    if altitude > SUN_VISIBLE_FROM - 3.0:
        _paint_sun(sky, scene, sun_x, sun_y, breath)
    return sky


def _paint_sun(sky: Image.Image, scene: Scene, x: float, y: float, breath: float) -> None:
    altitude = scene.sun.altitude
    colour, strength = sun_light(max(altitude, -0.833))
    fade = _clamp((altitude + 3.0) / 6.0)
    white = _to_rgb(_mix((255, 168, 92), (255, 252, 244), _clamp(altitude / SUN_WHITE_ALTITUDE)))
    _glow(sky, (x, y), (300, 260), colour, 0.20 * fade * (0.6 + strength) * breath, 2.4)
    _glow(sky, (x, y), (110, 110), white, 0.50 * fade * breath, 1.9)
    _glow(sky, (x, y), (46, 46), white, 0.85 * fade, 1.5)
    if altitude > SUN_VISIBLE_FROM:
        disc = _disc_mask(SUN_RADIUS_PX)
        sky.paste(_to_rgb(_mix((255, 196, 120), (255, 252, 240), _clamp(altitude / SUN_CORE_WHITE_ALTITUDE))), (round(x) - SUN_RADIUS_PX, round(y) - SUN_RADIUS_PX), disc)


# ── moon ─────────────────────────────────────────────────────────────────────
def moon_lit_mask(fraction: float, limb_bearing: float, radius: int) -> Image.Image:
    """The lit part of the moon's disc as an 'L' mask, 2*radius square, lit limb toward ``limb_bearing``.

    ``limb_bearing`` is the screen direction of the sun from the moon, degrees
    clockwise from straight up. The terminator is an ellipse whose width follows
    the phase angle (cos i = 2 * fraction - 1); the mask is built facing right and
    rotated into place.
    """
    scale = MOON_SUPERSAMPLE
    size = 2 * radius * scale
    centre = size / 2.0
    terminator = 2.0 * fraction - 1.0
    lit = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(lit)
    for row in range(size):
        offset = row + 0.5 - centre
        half = math.sqrt(max(0.0, centre * centre - offset * offset))
        if half <= 0.0:
            continue
        draw.line((centre - terminator * half, row, centre + half, row), fill=255)
    rotated = lit.rotate(90.0 - limb_bearing, resample=Image.Resampling.BICUBIC)
    return rotated.resize((2 * radius, 2 * radius), Image.Resampling.BOX)


# Fixed "seas" on the near side, as (x, y, half width, half height) in a unit disc.
_MARIA: tuple[tuple[float, float, float, float], ...] = (
    (-0.28, -0.30, 0.30, 0.22),
    (0.18, -0.36, 0.20, 0.17),
    (0.34, -0.02, 0.16, 0.20),
    (-0.10, 0.12, 0.30, 0.20),
    (-0.36, 0.30, 0.14, 0.12),
    (0.14, 0.42, 0.18, 0.10),
)


@functools.cache
def _moon_surface(radius: int, tint: RGB) -> Image.Image:
    """The moon's face: pale limestone with darker seas, before any phase is applied."""
    scale = MOON_SUPERSAMPLE
    size = 2 * radius * scale
    face = Image.new("RGB", (size, size), tint)
    sea_colour = _to_rgb(_mix(tint, (95, 100, 118), 0.42))
    draw = ImageDraw.Draw(face)
    for x, y, half_w, half_h in _MARIA:
        cx, cy = size / 2 * (1 + x), size / 2 * (1 + y)
        draw.ellipse((cx - half_w * size / 2, cy - half_h * size / 2, cx + half_w * size / 2, cy + half_h * size / 2), fill=sea_colour)
    return face.resize((2 * radius, 2 * radius), Image.Resampling.BOX).filter(ImageFilter.GaussianBlur(MOON_SOFTEN_PX))


def _paint_moon(sky: Image.Image, scene: Scene) -> None:
    moon = scene.moon
    altitude = moon.position.altitude
    x, y = view_x(moon.position.azimuth), view_y(altitude)
    daylight = _clamp((scene.sun.altitude + 6.0) / 12.0)
    opacity = 1.0 - (1.0 - MOON_DAYLIGHT_OPACITY) * daylight
    visible = _clamp((altitude - MOON_VISIBLE_FROM) / 3.0)
    if visible <= 0.0:
        return
    near_horizon = _clamp(1.0 - altitude / 25.0)
    tint = _to_rgb(_mix((236, 234, 222), (255, 205, 150), 0.55 * near_horizon))
    glow_strength = (0.30 * moon.fraction + 0.04) * (1.0 - 0.8 * daylight) * visible
    _glow(sky, (x, y), (MOON_LIGHT_RADIUS_PX, MOON_LIGHT_RADIUS_PX), (170, 190, 240), glow_strength, 2.2)
    _glow(sky, (x, y), (round(WIDTH * 0.55), round(HEIGHT * 0.55)), (110, 130, 190), 0.10 * moon.fraction * (1.0 - daylight) * visible, 1.8)
    origin = (round(x) - MOON_RADIUS_PX, round(y) - MOON_RADIUS_PX)
    disc = _disc_mask(MOON_RADIUS_PX)
    # Earthshine: the unlit side is a faint disc, not a hole.
    sky.paste((46, 56, 88), origin, disc.point(lambda v: round(v * 0.30 * (1.0 - daylight) * visible)))
    lit = moon_lit_mask(moon.fraction, moon.limb_bearing, MOON_RADIUS_PX)
    lit = ImageChops.multiply(lit, disc).point(lambda v: round(v * opacity * visible))
    sky.paste(_moon_surface(MOON_RADIUS_PX, tint), origin, lit)


# ── stars ────────────────────────────────────────────────────────────────────
@dataclass(frozen=True)
class Star:
    """A fixed star: where, how bright, what colour, and how it twinkles over one loop."""

    x: int
    y: int
    brightness: float
    size: int  # 0: one pixel, 1: soft 3x3, 2: soft 5x5 with a faint cross
    tint: RGB
    phase: float
    cycles: int
    depth: float


def star_field(day: date) -> tuple[Star, ...]:
    """The night's stars, seeded by the local date so the sky is the same all evening."""
    rng = random.Random(f"horizon-stars-{day.isoformat()}")
    tints = [tint for tint, _ in STAR_TINTS]
    weights = [weight for _, weight in STAR_TINTS]
    stars = []
    for _ in range(STAR_COUNT):
        x = rng.randrange(WIDTH)
        y = round(STAR_CEILING_PX * rng.random() ** 0.85)
        brightness = 0.22 + 0.78 * rng.random() ** 2.6
        # Air near the horizon swallows starlight.
        brightness *= 1.0 - (y / STAR_CEILING_PX) ** 3 * 0.85
        size = 2 if brightness > 0.88 else 1 if brightness > 0.58 else 0
        stars.append(
            Star(
                x=x,
                y=y,
                brightness=brightness,
                size=size,
                tint=rng.choices(tints, weights)[0],
                phase=rng.random(),
                cycles=rng.choice(TWINKLE_CYCLES),
                depth=rng.uniform(*TWINKLE_DEPTH),
            )
        )
    return tuple(stars)


@functools.cache
def _star_stamp(size: int, level: int) -> Image.Image:
    """A star's alpha stamp at ``level``/STAR_ALPHA_LEVELS of full brightness."""
    reach = size + 1 if size else 0
    side = 2 * reach + 1
    stamp = Image.new("L", (side, side), 0)
    gain = level / STAR_ALPHA_LEVELS
    pixels = stamp.load()
    for dy in range(-reach, reach + 1):
        for dx in range(-reach, reach + 1):
            distance = math.hypot(dx, dy)
            core = max(0.0, 1.0 - distance / (size + 0.9)) ** 1.6 if size else (1.0 if distance == 0 else 0.0)
            cross = 0.0
            if size == 2 and (dx == 0 or dy == 0):
                cross = max(0.0, 1.0 - distance / (reach + 0.6)) ** 2 * 0.45
            pixels[dx + reach, dy + reach] = round(255 * gain * min(1.0, core + cross))
    return stamp


def _paint_stars(frame: Image.Image, stars: Sequence[Star], scene: Scene, phase: float) -> None:
    """Twinkle the visible stars at ``phase`` (0..1 of the loop) onto ``frame``."""
    visibility = star_visibility(scene.sun.altitude)
    if visibility <= 0.0:
        return
    moon = scene.moon
    moon_x, moon_y = view_x(moon.position.azimuth), view_y(moon.position.altitude)
    moon_up = moon.position.altitude > MOON_VISIBLE_FROM
    for star in stars:
        twinkle = 1.0 - star.depth * (0.5 + 0.5 * math.sin(2.0 * math.pi * (star.cycles * phase + star.phase)))
        alpha = star.brightness * visibility * twinkle
        if moon_up:
            distance = math.hypot(star.x - moon_x, star.y - moon_y)
            alpha *= 1.0 - (1.0 - _clamp(distance / MOON_DIM_RADIUS_PX)) * (0.35 + 0.6 * moon.fraction)
        level = round(_clamp(alpha) * STAR_ALPHA_LEVELS)
        if level <= 0:
            continue
        stamp = _star_stamp(star.size, level)
        reach = stamp.width // 2
        frame.paste(star.tint, (star.x - reach, star.y - reach), stamp)


# ── land ─────────────────────────────────────────────────────────────────────
def dune_profiles(day: date) -> tuple[tuple[float, ...], ...]:
    """The crest line of each ridge, back to front: ``WIDTH`` rows (float) per ridge, seeded by ``day``."""
    rng = random.Random(f"horizon-dunes-{day.isoformat()}")
    mirrored = rng.random() < 0.5  # the wind's side: every ridge in a day leans the same way
    profiles = []
    for spec in RIDGES:
        crests = [
            (
                rng.uniform(-0.1 * WIDTH, 1.1 * WIDTH),
                rng.uniform(0.55, 1.0),
                spec.crest_width_px * rng.uniform(0.8, 1.25),
            )
            for _ in range(rng.randint(*spec.crests))
        ]
        heights = []
        for column in range(WIDTH):
            x = WIDTH - 1 - column if mirrored else column
            total = 0.0
            for centre, height, width in crests:
                offset = x - centre
                reach = width if offset < 0 else width * SLIP_FACE_RATIO
                total += height * max(0.0, 1.0 - abs(offset) / reach) ** CREST_SHARPNESS
            heights.append(total)
        low, high = min(heights), max(heights)
        span = (high - low) or 1.0
        top = HORIZON_PX + spec.base_px
        profile = tuple(top - spec.rise_px * (h - low) / span for h in heights)
        profiles.append(tuple(reversed(profile)) if mirrored else profile)
    return tuple(profiles)


def ridge_coverage(profile: Sequence[float]) -> Image.Image:
    """An anti-aliased 'L' mask (picture size) of the land below one ridge's crest line."""
    mask = Image.new("L", SKY_SIZE, 0)
    draw = ImageDraw.Draw(mask)
    for column, crest in enumerate(profile):
        first_full = math.ceil(crest)
        if first_full < HEIGHT:
            draw.line((column, first_full, column, HEIGHT - 1), fill=255)
        edge = first_full - 1
        if 0 <= edge < HEIGHT:
            mask.putpixel((column, edge), round(255 * (first_full - crest)))
    return mask


@dataclass(frozen=True)
class Lamp:
    """A source of light on the land: unit direction (screen x, up) toward it, colour 0..1, strength."""

    direction: tuple[float, float]
    colour: tuple[float, float, float]
    strength: float


@dataclass(frozen=True)
class Lighting:
    """All the light the dunes get: lamps for sun and moon, a tinted ambient fill, the horizon haze."""

    lamps: tuple[Lamp, ...]
    ambient: tuple[float, float, float]
    haze: RGB
    sand: tuple[float, float, float]  # the land's albedo, 0..1 per channel
    rim_boost: float  # extra direct light on a crest's edge, where grains catch the sun


def _lamp_toward(body: Body, colour: RGB, strength: float) -> Lamp:
    sway = _clamp(((body.azimuth % 360.0) - 180.0) / LIGHT_SWAY_DEGREES, -1.0, 1.0)
    elevation = math.radians(max(body.altitude, MIN_LIGHT_ELEVATION))
    x, up = sway * math.cos(elevation), math.sin(elevation)
    length = math.hypot(x, up)
    return Lamp((x / length, up / length), (colour[0] / 255.0, colour[1] / 255.0, colour[2] / 255.0), strength)


def lighting_for(scene: Scene) -> Lighting:
    """The light on the land: sun while it shines, moon above the horizon, the sky's glow always."""
    zenith, horizon = sky_colours(scene.sun.altitude)
    skylight = [0.55 * h + 0.45 * z for h, z in zip(horizon, zenith)]
    # Under a bright sky the fill is nearly neutral; a blue one would turn warm sand to ash.
    grey = sum(skylight) / 3.0
    skylight = _mix(skylight, (grey, grey, grey), FILL_DESATURATION * _clamp(scene.sun.altitude / DAYLIGHT_HAZE_ALTITUDE))
    fill = tuple(AMBIENT_GAIN * light / 255.0 + floor for light, floor in zip(skylight, AIRGLOW))
    lamps = []
    sun_colour, sun_strength = sun_light(scene.sun.altitude)
    if sun_strength > 0.0:
        lamps.append(_lamp_toward(scene.sun, sun_colour, DIRECT_GAIN * sun_strength))
    moon = scene.moon
    dusk = 1.0 - _clamp((scene.sun.altitude + 8.0) / 8.0)
    moon_strength = MOONLIGHT_GAIN * moon.fraction * _clamp(moon.position.altitude / 8.0) * dusk
    if moon_strength > 0.0:
        lamps.append(_lamp_toward(moon.position, MOONLIGHT, moon_strength))
    daylight = _clamp(scene.sun.altitude / DAYLIGHT_HAZE_ALTITUDE)
    haze = _to_rgb(_mix(horizon, _mix(horizon, DUST_HAZE, DUST_SHARE), daylight))
    sand = _mix(SAND, NIGHT_SAND, 1.0 - _clamp((scene.sun.altitude + 6.0) / 12.0))
    low_sun = 1.0 - RIM_HIGH_SUN_SHARE * _clamp(scene.sun.altitude / RIM_FADE_ALTITUDE)
    return Lighting(
        tuple(lamps), (fill[0], fill[1], fill[2]), haze, (sand[0] / 255.0, sand[1] / 255.0, sand[2] / 255.0), RIM_BOOST * low_sun
    )


def _tone(light: float) -> float:
    """Scene light to 0..1: linear up to a knee, then a soft shoulder, so noon keeps its colour."""
    if light <= TONE_KNEE:
        return light
    return TONE_KNEE + (1.0 - TONE_KNEE) * (1.0 - math.exp(-(light - TONE_KNEE) / (1.0 - TONE_KNEE)))


def _stripe_colours(profile: Sequence[float], spec: RidgeSpec, lighting: Lighting) -> tuple[list[RGB], list[RGB]]:
    """Per column: the sand's colour for the slope there, and the same lit harder for the crest's rim."""
    body, rim = [], []
    last = len(profile) - 1

    def colour(light: Sequence[float]) -> RGB:
        toned = [255.0 * _tone(lighting.sand[channel] * light[channel]) for channel in range(3)]
        return _to_rgb(_mix(toned, lighting.haze, spec.haze))

    for column in range(len(profile)):
        left, right = max(0, column - SLOPE_REACH_PX), min(last, column + SLOPE_REACH_PX)
        slope = (profile[right] - profile[left]) / (right - left)
        norm = math.hypot(slope, 1.0)
        direct = [0.0, 0.0, 0.0]
        for lamp in lighting.lamps:
            facing = max(0.0, (slope * lamp.direction[0] + lamp.direction[1] + WRAP_LIGHT) / (norm * (1.0 + WRAP_LIGHT)))
            for channel in range(3):
                direct[channel] += lamp.colour[channel] * lamp.strength * facing
        body.append(colour([a + d for a, d in zip(lighting.ambient, direct)]))
        rim.append(colour([a + (1.0 + lighting.rim_boost) * d for a, d in zip(lighting.ambient, direct)]))
    return body, rim


def _shear_mesh(profile: Sequence[float], shear: float) -> list[tuple[tuple[int, int, int, int], tuple[float, ...]]]:
    """Mesh pieces, one per column, that slide each column's shading sideways (right for positive ``shear``) with depth below its crest."""
    pieces = []
    for column, crest in enumerate(profile):
        top = max(0, math.floor(crest))
        near, far = top - crest, HEIGHT - crest
        left_top, left_foot = column - shear * near + SHEAR_PAD_PX, column - shear * far + SHEAR_PAD_PX
        pieces.append(
            (
                (column, top, column + 1, HEIGHT),
                (left_top, top, left_foot, HEIGHT, left_foot + 1, HEIGHT, left_top + 1, top),
            )
        )
    return pieces


def _render_ridge(profile: Sequence[float], spec: RidgeSpec, lighting: Lighting) -> tuple[Image.Image, Image.Image]:
    """(shade, coverage): the ridge's colours and its anti-aliased silhouette, both picture-sized.

    Each column is coloured for the slope at its crest, then the colours slide
    sideways as they go down the face: light and shadow edges run diagonally off
    every crest, the way a low sun throws a crest's shadow down the dune.
    """
    body, rim = _stripe_colours(profile, spec, lighting)
    padded = [body[0]] * SHEAR_PAD_PX + body + [body[-1]] * SHEAR_PAD_PX
    row = Image.new("RGB", (len(padded), 1))
    row.putdata(padded)
    stripes = row.resize((len(padded), HEIGHT), Image.Resampling.NEAREST)
    shade = stripes.transform(SKY_SIZE, Image.Transform.MESH, _shear_mesh(profile, lighting_shear(lighting)), Image.Resampling.BILINEAR)
    rim_line = ImageDraw.Draw(shade)
    for column, colour in enumerate(rim):
        crest = math.floor(profile[column])
        rim_line.line((column, crest, column, crest + 1), fill=colour)
    top = max(0, math.floor(min(profile)))
    foot = Image.linear_gradient("L").resize((WIDTH, HEIGHT - top), Image.Resampling.BILINEAR)
    darkness = Image.new("L", SKY_SIZE, 0)
    darkness.paste(foot.point(lambda v: round(v * spec.darkening)), (0, top))
    shadow = _to_rgb(tuple(255.0 * _tone(a * c) for a, c in zip(lighting.ambient, lighting.sand)))
    shade = Image.composite(Image.new("RGB", SKY_SIZE, shadow), shade, darkness)
    return shade, ridge_coverage(profile)


def lighting_shear(lighting: Lighting) -> float:
    """Sideways slide per pixel of depth: shadows lean away from the main lamp, longer when it is low."""
    if not lighting.lamps:
        return 0.0
    lamp = max(lighting.lamps, key=lambda candidate: candidate.strength)
    horizontal, up = lamp.direction
    lean = abs(horizontal) / max(up, MIN_SHEAR_ELEVATION) * SHEAR_GAIN
    return -math.copysign(min(MAX_SHEAR, max(MIN_SHEAR, lean)), horizontal)


# ── frames ───────────────────────────────────────────────────────────────────
def _shimmer(frame: Image.Image, phase: float, strength: float) -> None:
    """Sway the rows around the horizon sideways, like air over hot sand."""
    for row in range(HORIZON_PX - SHIMMER_SPAN_PX, HORIZON_PX + SHIMMER_SPAN_PX):
        weight = math.exp(-(((row - HORIZON_PX) / SHIMMER_SIGMA_PX) ** 2))
        wave = math.sin(2.0 * math.pi * (phase + row / SHIMMER_WAVELENGTH_PX))
        shift = round(SHIMMER_AMPLITUDE_PX * strength * weight * wave)
        if shift:
            strip = frame.crop((0, row, WIDTH, row + 1))
            frame.paste(ImageChops.offset(strip, shift, 0), (0, row))


def _shimmer_strength(sun_altitude: float) -> float:
    return _clamp((sun_altitude - SHIMMER_NONE_ALTITUDE) / (SHIMMER_FULL_ALTITUDE - SHIMMER_NONE_ALTITUDE))


def _frame(sky: Image.Image, stars: Sequence[Star], ridges: Sequence[tuple[Image.Image, Image.Image]], scene: Scene, phase: float, animate: bool) -> Image.Image:
    frame = sky
    _paint_stars(frame, stars, scene, phase)
    for shade, coverage in ridges:
        frame.paste(shade, (0, 0), coverage)
    if animate:
        _shimmer(frame, phase, _shimmer_strength(scene.sun.altitude))
    return frame


def render_frames(scene: Scene, mode: Mode) -> list[Image.Image]:
    """One frame for STILL, FRAME_COUNT looping frames for FULL."""
    lighting = lighting_for(scene)
    ridges = [
        _render_ridge(profile, spec, lighting)
        for profile, spec in zip(dune_profiles(scene.day), RIDGES)
    ]
    stars = star_field(scene.day)
    if mode is Mode.STILL:
        return [_frame(_render_sky(scene), stars, ridges, scene, 0.0, animate=False)]
    frames = []
    for index in range(FRAME_COUNT):
        phase = index / FRAME_COUNT
        breath = 1.0 + BREATH_DEPTH * math.sin(2.0 * math.pi * phase)
        frames.append(_frame(_render_sky(scene, breath), stars, ridges, scene, phase, animate=True))
    return frames


# ── words and files ──────────────────────────────────────────────────────────
def _clock(moment: datetime) -> str:
    return moment.strftime("%H:%M")


def _place_line(location: Location, day: date) -> str:
    date_part = f"{WEEKDAYS[day.weekday()]} {day.day} {MONTHS[day.month - 1]}"
    room = LABEL_COLUMNS - len(date_part) - len(SEPARATOR)
    place = location.place
    if len(place) > room:
        place = place[: max(1, room - 1)].rstrip() + ELLIPSIS
    return f"{place}{SEPARATOR}{date_part}"


def _height_text(altitude: float) -> str:
    degrees = round(altitude)
    if degrees == 0:
        return "0°"
    return f"{'+' if degrees > 0 else MINUS}{abs(degrees)}°"


def _daylight_text(times: SunTimes) -> str:
    minutes = round((times.sunset - times.sunrise).total_seconds() / 60)
    return f"{minutes // 60} h {minutes % 60:02d} m of daylight"


def greeting_lines(scene: Scene) -> dict[str, str]:
    """The one-line texts of the greeting, by file name (without newlines)."""
    moon = scene.moon
    return {
        "place": _place_line(scene.location, scene.day),
        "sky": f"{scene.state.value}{SEPARATOR}sun {_height_text(scene.sun.altitude)}",
        "almanac": f"sunrise {_clock(scene.today.sunrise)}{SEPARATOR}sunset {_clock(scene.today.sunset)}",
        "daylight": _daylight_text(scene.today),
        "moon": f"{moon_phase_name(moon.fraction, moon.waxing)}{SEPARATOR}{round(moon.fraction * 100)} % lit",
    }


def _save_logo(frames: Sequence[Image.Image], path: Path) -> None:
    first, rest = frames[0], list(frames[1:])
    if rest:
        first.save(path, "PNG", save_all=True, append_images=rest, duration=FRAME_MS, loop=0)
    else:
        first.save(path, "PNG")


def paint(ctx: PaintContext) -> Painted:
    """Paint the sky over the viewer's location at ``ctx.now`` into ``ctx.out_dir``."""
    if ctx.now.tzinfo is None:
        raise ValueError("horizon needs an aware clock")
    location, warning = location_from_env(os.environ)
    if warning:
        print(f"horizon: {warning}", file=sys.stderr)
    zone = resolve_zone(os.environ, DEFAULT_LOCALTIME, ctx.now.tzinfo)
    scene = build_scene(ctx.now, location, zone)
    _save_logo(render_frames(scene, ctx.mode), ctx.out_dir / LOGO_NAME)
    for name, line in greeting_lines(scene).items():
        write_text_atomic(ctx.out_dir / name, line + "\n")
    write_text_atomic(ctx.out_dir / "sun", " ".join(str(second) for second in scene.cycle) + "\n")
    return Painted(expires=bucket_expiry(ctx.now))
