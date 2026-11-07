"""The sky as numbers: where the sun and moon are, and what colour the air is.

Pure maths for the horizon theme (no Pillow, no I/O beyond reading a symlink).
Accuracy is what a picture needs, not an observatory: the sun follows NOAA's
low-precision series (well under 0.1 degree), the moon a truncated Meeus
series (about 0.3 degree), both geometric (no refraction), so a sunrise is
the moment the centre of the sun is 0.833 degrees below the horizon.

The view is a south-facing window: azimuth VIEW_AZIMUTH[0]..[1] maps linearly
across the picture, the horizon sits at HORIZON_Y of its height and altitude
0..90 degrees fills the sky above it.
"""

import math
import os
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone, tzinfo
from enum import Enum
from pathlib import Path
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

RGB = tuple[int, int, int]

# ── view and cadence ─────────────────────────────────────────────────────────
SKY_BUCKET_S = 600
SKY_SIZE = (792, 540)
VIEW_AZIMUTH = (60.0, 300.0)
HORIZON_Y = 0.72

LATLON_VAR = "DCLI_HORIZON_LATLON"
PLACE_VAR = "DCLI_HORIZON_PLACE"
# Beyond this the sun can fail to rise or set, and the day bar has no meaning.
MAX_ABS_LATITUDE = 65.0
MAX_ABS_LONGITUDE = 180.0

# ── constants of the sky ─────────────────────────────────────────────────────
JD_UNIX_EPOCH = 2440587.5
JD_J2000 = 2451545.0
SUNRISE_ALTITUDE = -0.833
MEAN_OBLIQUITY = 23.4393
EARTH_RADIUS_KM = 6371.0
SUN_DISTANCE_KM = 149_597_870.7
MINUTES_PER_DAY = 1440.0
MINUTES_PER_DEGREE = 4.0
QUARTER_BAND = 0.05
NEW_OR_FULL_BAND = 0.02
# How many times the sunrise or sunset is re-evaluated at its own instant: the
# declination and equation of time move, and one pass is already within a minute.
SUN_TIME_PASSES = 3
TIME_ZONE_DIRECTORY = "zoneinfo/"
DEFAULT_LOCALTIME = Path("/etc/localtime")


class SkyState(Enum):
    """The sky's phase of the day by sun altitude; the value is the greeting's wording."""

    NIGHT = "night"
    ASTRONOMICAL = "astronomical twilight"
    NAUTICAL = "nautical twilight"
    CIVIL = "civil twilight"
    GOLDEN = "golden hour"
    DAY = "daylight"


# Lower altitude bounds, brightest first; an edge belongs to the brighter state.
_STATE_FLOORS: tuple[tuple[float, SkyState], ...] = (
    (6.0, SkyState.DAY),
    (SUNRISE_ALTITUDE, SkyState.GOLDEN),
    (-6.0, SkyState.CIVIL),
    (-12.0, SkyState.NAUTICAL),
    (-18.0, SkyState.ASTRONOMICAL),
)


def sky_state(altitude: float) -> SkyState:
    """The named phase of the day for a sun altitude in degrees."""
    for floor, state in _STATE_FLOORS:
        if altitude >= floor:
            return state
    return SkyState.NIGHT


# ── where and when ───────────────────────────────────────────────────────────
@dataclass(frozen=True)
class Location:
    """A place on Earth: degrees north and east, and the name the greeting shows."""

    lat: float
    lon: float
    place: str


RIYADH = Location(24.7136, 46.6753, "Riyadh")


def _coordinate_label(lat: float, lon: float) -> str:
    return f"{abs(lat):.2f}°{'N' if lat >= 0 else 'S'} {abs(lon):.2f}°{'E' if lon >= 0 else 'W'}"


def location_from_env(env: Mapping[str, str]) -> tuple[Location, str | None]:
    """The viewer's location from DCLI_HORIZON_LATLON ('<lat>,<lon>') and DCLI_HORIZON_PLACE.

    Unset or empty means Riyadh. An override that is not two finite numbers within
    the range the day bar can serve returns Riyadh and a warning naming the variable.
    """
    raw = env.get(LATLON_VAR, "").strip()
    if not raw:
        return RIYADH, None
    parts = raw.split(",")
    try:
        if len(parts) != 2:
            raise ValueError("expected two numbers")
        lat, lon = float(parts[0]), float(parts[1])
        if not (abs(lat) <= MAX_ABS_LATITUDE and abs(lon) <= MAX_ABS_LONGITUDE):
            raise ValueError("out of range")
    except ValueError:
        return RIYADH, (
            f"{LATLON_VAR}={raw!r} is not '<lat>,<lon>' with latitude within ±{MAX_ABS_LATITUDE:g} and "
            f"longitude within ±{MAX_ABS_LONGITUDE:g} degrees; showing {RIYADH.place}"
        )
    place = env.get(PLACE_VAR, "").strip() or _coordinate_label(lat, lon)
    return Location(lat, lon, place), None


def resolve_zone(env: Mapping[str, str], localtime: Path, fallback: tzinfo) -> tzinfo:
    """The system's named time zone, so a DST changeover day is right; else ``fallback``.

    ``TZ`` decides when it is set (as in libc, which then ignores /etc/localtime),
    otherwise the zone named by the /etc/localtime symlink. A zone that cannot be
    named (a POSIX rule, a copied file) is the caller's fixed-offset ``fallback``.
    """
    configured = env.get("TZ", "")
    if configured:
        return _zone_named(configured.lstrip(":")) or fallback
    try:
        target = os.readlink(localtime)
    except OSError:
        return fallback
    return _zone_named(target) or fallback


def _zone_named(name: str) -> tzinfo | None:
    _, marker, tail = name.rpartition(TIME_ZONE_DIRECTORY)
    key = tail if marker else name
    try:
        return ZoneInfo(key)
    except (ZoneInfoNotFoundError, ValueError, OSError):
        return None


# ── the sun ──────────────────────────────────────────────────────────────────
@dataclass(frozen=True)
class SunTimes:
    """One local day's sun: sunrise and sunset (centre at -0.833 degrees) and solar noon."""

    sunrise: datetime
    sunset: datetime
    solar_noon: datetime


@dataclass(frozen=True)
class _SolarCoordinates:
    declination: float  # radians
    equation_of_time: float  # minutes
    ecliptic_longitude: float  # degrees, apparent


def _julian_day(when: datetime) -> float:
    if when.tzinfo is None:
        raise ValueError("a naive datetime has no instant; pass an aware one")
    return when.timestamp() / 86400.0 + JD_UNIX_EPOCH


def _solar_coordinates(jd: float) -> _SolarCoordinates:
    """NOAA's low-precision solar series for the Julian day ``jd``."""
    t = (jd - JD_J2000) / 36525.0
    mean_longitude = math.radians((280.46646 + t * (36000.76983 + t * 0.0003032)) % 360.0)
    anomaly = math.radians(357.52911 + t * (35999.05029 - 0.0001537 * t))
    eccentricity = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
    centre = (
        math.sin(anomaly) * (1.914602 - t * (0.004817 + 0.000014 * t))
        + math.sin(2 * anomaly) * (0.019993 - 0.000101 * t)
        + math.sin(3 * anomaly) * 0.000289
    )
    node = math.radians(125.04 - 1934.136 * t)
    ecliptic_longitude = math.degrees(mean_longitude) + centre - 0.00569 - 0.00478 * math.sin(node)
    obliquity = math.radians(
        23.0
        + (26.0 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60.0) / 60.0
        + 0.00256 * math.cos(node)
    )
    declination = math.asin(math.sin(obliquity) * math.sin(math.radians(ecliptic_longitude)))
    y = math.tan(obliquity / 2) ** 2
    equation = y * math.sin(2 * mean_longitude) - 2 * eccentricity * math.sin(anomaly)
    equation += 4 * eccentricity * y * math.sin(anomaly) * math.cos(2 * mean_longitude)
    equation -= 0.5 * y * y * math.sin(4 * mean_longitude) + 1.25 * eccentricity**2 * math.sin(2 * anomaly)
    return _SolarCoordinates(declination, math.degrees(equation) * MINUTES_PER_DEGREE, ecliptic_longitude % 360.0)


def _horizontal(hour_angle: float, declination: float, latitude: float) -> tuple[float, float]:
    """(altitude, azimuth from north clockwise) in degrees, from radians in."""
    sin_altitude = math.sin(latitude) * math.sin(declination) + math.cos(latitude) * math.cos(declination) * math.cos(
        hour_angle
    )
    altitude = math.degrees(math.asin(max(-1.0, min(1.0, sin_altitude))))
    azimuth = math.atan2(
        math.sin(hour_angle),
        math.cos(hour_angle) * math.sin(latitude) - math.tan(declination) * math.cos(latitude),
    )
    return altitude, (math.degrees(azimuth) + 180.0) % 360.0


def sun_position(when: datetime, loc: Location) -> tuple[float, float]:
    """(altitude, azimuth) of the sun in degrees; azimuth runs from north through east."""
    jd = _julian_day(when)
    coordinates = _solar_coordinates(jd)
    minutes_utc = ((jd + 0.5) % 1.0) * MINUTES_PER_DAY
    solar_minutes = minutes_utc + coordinates.equation_of_time + MINUTES_PER_DEGREE * loc.lon
    hour_angle = math.radians(solar_minutes / MINUTES_PER_DEGREE - 180.0)
    return _horizontal(hour_angle, coordinates.declination, math.radians(loc.lat))


def _utc_midnight(day: date) -> datetime:
    return datetime(day.year, day.month, day.day, tzinfo=timezone.utc)


def _solar_noon(base: datetime, lon: float, guess: datetime) -> datetime:
    """Solar noon of the UTC day starting at ``base``, with the equation of time taken at ``guess``."""
    equation = _solar_coordinates(_julian_day(guess)).equation_of_time
    return base + timedelta(minutes=720.0 - MINUTES_PER_DEGREE * lon - equation)


def _horizon_hour_angle(declination: float, latitude: float) -> float:
    """Half the day, in degrees of hour angle (15 per hour); ValueError if the sun never crosses."""
    cosine = (math.sin(math.radians(SUNRISE_ALTITUDE)) - math.sin(latitude) * math.sin(declination)) / (
        math.cos(latitude) * math.cos(declination)
    )
    if not -1.0 <= cosine <= 1.0:
        raise ValueError("the sun does not rise and set on this day at this latitude")
    return math.degrees(math.acos(cosine))


def sun_times(day: date, loc: Location, tz: tzinfo) -> SunTimes:
    """Sunrise, sunset and solar noon of the local calendar ``day``, as aware datetimes in ``tz``.

    Raises ValueError where the sun does not rise and set that day (the polar
    regions, which location_from_env does not accept).
    """
    latitude = math.radians(loc.lat)
    local_noon = datetime(day.year, day.month, day.day, 12, tzinfo=tz)
    # The solar noon that falls on this local date may belong to the neighbouring UTC date.
    noon = min(
        (
            _solar_noon(_utc_midnight(day + timedelta(days=shift)), loc.lon, local_noon)
            for shift in (-1, 0, 1)
        ),
        key=lambda candidate: abs(candidate - local_noon),
    )
    base = _utc_midnight(noon.date())
    # Re-evaluate at the noon found, then at each crossing, so the series sees the right instant.
    for _ in range(SUN_TIME_PASSES):
        noon = _solar_noon(base, loc.lon, noon)
    crossings = []
    for direction in (-1, 1):
        moment = noon
        for _ in range(SUN_TIME_PASSES):
            half_day = _horizon_hour_angle(_solar_coordinates(_julian_day(moment)).declination, latitude)
            moment = _solar_noon(base, loc.lon, moment) + direction * timedelta(minutes=half_day * MINUTES_PER_DEGREE)
        crossings.append(moment)
    sunrise, sunset = crossings
    return SunTimes(sunrise.astimezone(tz), sunset.astimezone(tz), noon.astimezone(tz))


# ── the moon ─────────────────────────────────────────────────────────────────
@dataclass(frozen=True)
class _LunarCoordinates:
    longitude: float  # ecliptic, degrees
    latitude: float  # ecliptic, degrees
    distance_km: float


def _lunar_coordinates(jd: float) -> _LunarCoordinates:
    """Meeus ch. 47, truncated to its largest terms."""
    t = (jd - JD_J2000) / 36525.0
    mean_longitude = 218.3164477 + 481267.88123421 * t
    elongation = math.radians(297.8501921 + 445267.1114034 * t)
    sun_anomaly = math.radians(357.5291092 + 35999.0502909 * t)
    anomaly = math.radians(134.9633964 + 477198.8675055 * t)
    argument = math.radians(93.2720950 + 483202.0175233 * t)
    longitude = (
        mean_longitude
        + 6.289 * math.sin(anomaly)
        + 1.274 * math.sin(2 * elongation - anomaly)
        + 0.658 * math.sin(2 * elongation)
        + 0.214 * math.sin(2 * anomaly)
        - 0.186 * math.sin(sun_anomaly)
        - 0.114 * math.sin(2 * argument)
    )
    latitude = (
        5.128 * math.sin(argument)
        + 0.2806 * math.sin(anomaly + argument)
        + 0.2777 * math.sin(anomaly - argument)
        + 0.1732 * math.sin(2 * elongation - argument)
    )
    distance = (
        385000.56
        - 20905.355 * math.cos(anomaly)
        - 3699.111 * math.cos(2 * elongation - anomaly)
        - 2955.968 * math.cos(2 * elongation)
        - 569.925 * math.cos(2 * anomaly)
    )
    return _LunarCoordinates(longitude % 360.0, latitude, distance)


def moon_position(when: datetime, loc: Location) -> tuple[float, float]:
    """(altitude, azimuth) of the moon in degrees, corrected for parallax (up to a degree)."""
    jd = _julian_day(when)
    moon = _lunar_coordinates(jd)
    longitude, latitude = math.radians(moon.longitude), math.radians(moon.latitude)
    obliquity = math.radians(MEAN_OBLIQUITY)
    right_ascension = math.atan2(
        math.sin(longitude) * math.cos(obliquity) - math.tan(latitude) * math.sin(obliquity), math.cos(longitude)
    )
    declination = math.asin(
        math.sin(latitude) * math.cos(obliquity) + math.cos(latitude) * math.sin(obliquity) * math.sin(longitude)
    )
    sidereal = math.radians(280.46061837 + 360.98564736629 * (jd - JD_J2000) + loc.lon)
    altitude, azimuth = _horizontal(sidereal - right_ascension, declination, math.radians(loc.lat))
    parallax = math.degrees(math.asin(EARTH_RADIUS_KM / moon.distance_km))
    return altitude - parallax * math.cos(math.radians(altitude)), azimuth


def moon_illumination(when: datetime) -> tuple[float, bool]:
    """(fraction of the disc lit, waxing) from the sun-moon elongation."""
    jd = _julian_day(when)
    moon = _lunar_coordinates(jd)
    separation = math.radians(moon.longitude - _solar_coordinates(jd).ecliptic_longitude)
    cosine_elongation = math.cos(math.radians(moon.latitude)) * math.cos(separation)
    elongation = math.acos(max(-1.0, min(1.0, cosine_elongation)))
    phase_angle = math.atan2(SUN_DISTANCE_KM * math.sin(elongation), moon.distance_km - SUN_DISTANCE_KM * cosine_elongation)
    return (1.0 + math.cos(phase_angle)) / 2.0, math.sin(separation) > 0.0


def moon_phase_name(fraction: float, waxing: bool) -> str:
    """The phase's everyday name for a lit fraction and direction."""
    if fraction < NEW_OR_FULL_BAND:
        return "new moon"
    if fraction > 1.0 - NEW_OR_FULL_BAND:
        return "full moon"
    side = "waxing" if waxing else "waning"
    if abs(fraction - 0.5) <= QUARTER_BAND:
        return "first quarter" if waxing else "last quarter"
    return f"{side} {'crescent' if fraction < 0.5 else 'gibbous'}"


def bearing(alt_from: float, az_from: float, alt_to: float, az_to: float) -> float:
    """Direction from one sky position to another, degrees: 0 is toward the zenith, 90 toward higher azimuth.

    Seen from inside a south-facing window that is straight up and to the right,
    so it is also the screen direction of the moon's bright limb (sun = target).
    """
    lift_from, lift_to = math.radians(alt_from), math.radians(alt_to)
    delta = math.radians(az_to - az_from)
    return math.degrees(
        math.atan2(
            math.sin(delta) * math.cos(lift_to),
            math.cos(lift_from) * math.sin(lift_to) - math.sin(lift_from) * math.cos(lift_to) * math.cos(delta),
        )
    )


# ── the picture's frame ──────────────────────────────────────────────────────
def view_x(azimuth: float) -> float:
    """Pixel column of an azimuth; beyond the window it runs off the edges, never wraps back in."""
    span = VIEW_AZIMUTH[1] - VIEW_AZIMUTH[0]
    centre = (VIEW_AZIMUTH[0] + VIEW_AZIMUTH[1]) / 2.0
    relative = (azimuth - centre + 180.0) % 360.0 - 180.0
    return SKY_SIZE[0] / 2.0 + relative / span * SKY_SIZE[0]


def view_y(altitude: float) -> float:
    """Pixel row of an altitude: 90 degrees at the top, 0 on the horizon, below it for negative."""
    horizon = HORIZON_Y * SKY_SIZE[1]
    return horizon * (1.0 - altitude / 90.0)


def bucket_expiry(now: datetime) -> int:
    """Epoch second ending the SKY_BUCKET_S-aligned bucket ``now`` is in (a boundary starts the next)."""
    return (int(now.timestamp() // SKY_BUCKET_S) + 1) * SKY_BUCKET_S


def sun_bar_progress(
    now: datetime, today: SunTimes, tomorrow_sunrise: datetime, yesterday_sunset: datetime
) -> tuple[bool, float]:
    """(is_day, 0..1): how far the sun has crossed the sky, or the moon the night.

    Daylight runs sunrise to sunset; night runs from the last sunset to the next
    sunrise, so just after midnight is already well into last evening's night.
    """
    if today.sunrise <= now < today.sunset:
        return True, _share(now, today.sunrise, today.sunset)
    if now >= today.sunset:
        return False, _share(now, today.sunset, tomorrow_sunrise)
    return False, _share(now, yesterday_sunset, today.sunrise)


def _share(now: datetime, start: datetime, end: datetime) -> float:
    return min(1.0, max(0.0, (now - start) / (end - start)))


# ── colour ───────────────────────────────────────────────────────────────────
def _lerp_stops(altitude: float, altitudes: Sequence[float], values: Sequence[Sequence[float]]) -> list[float]:
    """Piecewise-linear interpolation, clamped at both ends; ``values`` rows are equally long."""
    if altitude <= altitudes[0]:
        return list(values[0])
    for index in range(1, len(altitudes)):
        if altitude <= altitudes[index]:
            span = altitudes[index] - altitudes[index - 1]
            share = (altitude - altitudes[index - 1]) / span
            return [a + (b - a) * share for a, b in zip(values[index - 1], values[index])]
    return list(values[-1])


def _rgb(values: Sequence[float]) -> RGB:
    red, green, blue = (max(0, min(255, round(v))) for v in values)
    return red, green, blue


# Sun altitude -> (zenith, middle, horizon) of a clear desert sky: ink-blue
# night; a violet-to-rose horizon through twilight; apricot at sunrise with a
# lilac then pale-cyan middle (a straight blue-to-orange blend would pass through
# grey); pale gold; then blue all the way down.
_SKY_ALTITUDES = (-18.0, -15.0, -12.0, -9.0, -6.0, -3.0, SUNRISE_ALTITUDE, 2.0, 6.0, 15.0, 40.0, 90.0)
_SKY_STOPS: tuple[tuple[float, ...], ...] = (
    (4, 7, 20, 8, 12, 34, 20, 28, 58),
    (6, 10, 28, 12, 18, 46, 28, 36, 70),
    (10, 18, 46, 26, 34, 74, 48, 52, 98),
    (16, 28, 66, 52, 54, 106, 96, 76, 120),
    (28, 46, 100, 92, 78, 138, 170, 98, 122),
    (46, 78, 142, 128, 104, 160, 236, 128, 100),
    (62, 104, 170, 152, 132, 176, 252, 160, 100),
    (76, 124, 190, 156, 156, 196, 252, 184, 124),
    (84, 140, 206, 140, 172, 214, 246, 206, 160),
    (72, 138, 214, 118, 172, 226, 190, 214, 236),
    (52, 122, 210, 104, 164, 230, 160, 206, 240),
    (40, 108, 200, 96, 158, 228, 150, 200, 238),
)


def sky_gradient(altitude: float) -> tuple[RGB, RGB, RGB]:
    """(zenith, middle, horizon) colour of the sky for a sun altitude in degrees."""
    stops = _lerp_stops(altitude, _SKY_ALTITUDES, _SKY_STOPS)
    return _rgb(stops[:3]), _rgb(stops[3:6]), _rgb(stops[6:])


def sky_colours(altitude: float) -> tuple[RGB, RGB]:
    """(zenith, horizon) colour of the sky for a sun altitude in degrees."""
    zenith, _, horizon = sky_gradient(altitude)
    return zenith, horizon


# Sun altitude -> (r, g, b, strength) of direct sunlight on the land; below the
# horizon the strength falls to zero as the last light leaves the sand.
_LIGHT_ALTITUDES = (-4.0, -0.833, 2.0, 6.0, 15.0, 35.0)
_LIGHT_STOPS: tuple[tuple[float, ...], ...] = (
    (190, 80, 110, 0.0),
    (255, 120, 60, 0.35),
    (255, 160, 90, 0.7),
    (255, 205, 150, 0.85),
    (255, 232, 196, 0.95),
    (255, 246, 228, 1.0),
)


def sun_light(altitude: float) -> tuple[RGB, float]:
    """(colour, strength 0..1) of the sun's light on the ground at a sun altitude."""
    stops = _lerp_stops(altitude, _LIGHT_ALTITUDES, _LIGHT_STOPS)
    return _rgb(stops[:3]), stops[3]



# Sun altitude -> (r, g, b, strength) of the glow that hangs around the sun's
# bearing along the horizon: violet in deep dusk, rose, then apricot and gold.
_GLOW_ALTITUDES = (-14.0, -9.0, -5.0, -2.0, SUNRISE_ALTITUDE, 3.0, 10.0, 25.0, 45.0)
_GLOW_STOPS: tuple[tuple[float, ...], ...] = (
    (80, 70, 130, 0.0),
    (150, 90, 130, 0.18),
    (235, 120, 100, 0.45),
    (255, 150, 90, 0.62),
    (255, 175, 95, 0.68),
    (255, 205, 140, 0.55),
    (255, 225, 170, 0.32),
    (255, 235, 200, 0.16),
    (255, 240, 215, 0.10),
)


def twilight_glow(altitude: float) -> tuple[RGB, float]:
    """(colour, strength 0..1) of the sky glow around the sun's bearing at a sun altitude."""
    stops = _lerp_stops(altitude, _GLOW_ALTITUDES, _GLOW_STOPS)
    return _rgb(stops[:3]), stops[3]


STARS_FADE_IN_ALTITUDE = -6.0
STARS_FULL_ALTITUDE = -18.0


def star_visibility(altitude: float) -> float:
    """How visible the stars are (0..1) for a sun altitude: none above -6, all by -18, smooth between."""
    share = (STARS_FADE_IN_ALTITUDE - altitude) / (STARS_FADE_IN_ALTITUDE - STARS_FULL_ALTITUDE)
    share = min(1.0, max(0.0, share))
    return share * share * (3.0 - 2.0 * share)
