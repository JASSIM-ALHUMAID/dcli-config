"""Unit tests for themes/sky.py: the astronomy and colour maths behind horizon.

Reference values are almanac facts (equinox and solstice noon heights, the dates
of real new and full moons), not outputs of the code under test.

Run: PYTHONPATH=scripts/terminal-art python3 -m unittest discover -s tests/terminal-art -p 'test_*.py'
"""

import unittest
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from tempfile import TemporaryDirectory
from zoneinfo import ZoneInfo

from themes.sky import (
    HORIZON_Y,
    RIYADH,
    SKY_BUCKET_S,
    SKY_SIZE,
    VIEW_AZIMUTH,
    Location,
    SkyState,
    SunTimes,
    bucket_expiry,
    location_from_env,
    moon_illumination,
    moon_phase_name,
    moon_position,
    resolve_zone,
    sky_colours,
    sky_state,
    sun_bar_progress,
    sun_light,
    sun_position,
    star_visibility,
    sun_times,
    twilight_glow,
    view_x,
)

RIYADH_TZ = ZoneInfo("Asia/Riyadh")
UTC = timezone.utc


def local(year: int, month: int, day: int, hour: int = 0, minute: int = 0) -> datetime:
    return datetime(year, month, day, hour, minute, tzinfo=RIYADH_TZ)


class SunTest(unittest.TestCase):
    def test_equinox_noon_altitude(self) -> None:
        noon = sun_times(date(2026, 3, 20), RIYADH, RIYADH_TZ).solar_noon
        altitude, _ = sun_position(noon, RIYADH)
        self.assertAlmostEqual(altitude, 65.3, delta=1.0)

    def test_solstice_noon_altitude(self) -> None:
        noon = sun_times(date(2026, 6, 21), RIYADH, RIYADH_TZ).solar_noon
        altitude, _ = sun_position(noon, RIYADH)
        self.assertAlmostEqual(altitude, 88.7, delta=1.0)

    def test_sun_is_due_south_at_solar_noon(self) -> None:
        noon = sun_times(date(2026, 11, 7), RIYADH, RIYADH_TZ).solar_noon
        _, azimuth = sun_position(noon, RIYADH)
        self.assertAlmostEqual(azimuth, 180.0, delta=1.0)

    def test_sunrise_is_east_and_sunset_west(self) -> None:
        times = sun_times(date(2026, 3, 20), RIYADH, RIYADH_TZ)
        self.assertAlmostEqual(sun_position(times.sunrise, RIYADH)[1], 90.0, delta=3.0)
        self.assertAlmostEqual(sun_position(times.sunset, RIYADH)[1], 270.0, delta=3.0)

    def test_sun_sits_on_the_horizon_at_sunrise_and_sunset(self) -> None:
        times = sun_times(date(2026, 11, 7), RIYADH, RIYADH_TZ)
        for moment in (times.sunrise, times.sunset):
            self.assertAlmostEqual(sun_position(moment, RIYADH)[0], -0.833, delta=0.2)

    def test_midnight_is_night(self) -> None:
        altitude, _ = sun_position(local(2026, 11, 7), RIYADH)
        self.assertEqual(sky_state(altitude), SkyState.NIGHT)

    def test_sunrise_before_noon_before_sunset(self) -> None:
        times = sun_times(date(2026, 11, 7), RIYADH, RIYADH_TZ)
        self.assertLess(times.sunrise, times.solar_noon)
        self.assertLess(times.solar_noon, times.sunset)
        self.assertEqual(times.sunrise.date(), date(2026, 11, 7))
        self.assertEqual(times.sunset.date(), date(2026, 11, 7))

    def test_equinox_day_length(self) -> None:
        times = sun_times(date(2026, 3, 20), RIYADH, RIYADH_TZ)
        length = times.sunset - times.sunrise
        self.assertAlmostEqual(length.total_seconds(), (12 * 60 + 8) * 60, delta=10 * 60)

    def test_june_days_longer_than_december(self) -> None:
        june = sun_times(date(2026, 6, 21), RIYADH, RIYADH_TZ)
        december = sun_times(date(2026, 12, 21), RIYADH, RIYADH_TZ)
        self.assertGreater(june.sunset - june.sunrise, december.sunset - december.sunrise + timedelta(hours=2))

    def test_times_are_in_the_requested_zone(self) -> None:
        times = sun_times(date(2026, 3, 20), RIYADH, RIYADH_TZ)
        self.assertEqual(times.sunrise.utcoffset(), timedelta(hours=3))
        self.assertTrue(5 <= times.sunrise.hour <= 7, times.sunrise)

    def test_local_date_follows_the_zone_not_utc(self) -> None:
        # Auckland's sunrise on its 7 November is still 6 November in UTC.
        auckland = Location(-36.85, 174.76, "Auckland")
        zone = ZoneInfo("Pacific/Auckland")
        times = sun_times(date(2026, 11, 7), auckland, zone)
        self.assertEqual(times.sunrise.astimezone(zone).date(), date(2026, 11, 7))
        self.assertEqual(times.sunset.astimezone(zone).date(), date(2026, 11, 7))
        self.assertLess(times.sunrise, times.sunset)

    def test_sun_times_on_a_dst_changeover_day(self) -> None:
        london = Location(51.5, -0.12, "London")
        zone = ZoneInfo("Europe/London")
        times = sun_times(date(2026, 3, 29), london, zone)
        # Clocks went forward at 01:00 UTC: sunrise is ~06:00 UTC = 07:00 BST.
        self.assertEqual(times.sunrise.utcoffset(), timedelta(hours=1))
        self.assertAlmostEqual(times.sunrise.hour + times.sunrise.minute / 60, 7.0, delta=0.5)


class MoonTest(unittest.TestCase):
    def test_full_moon_is_lit(self) -> None:
        fraction, _ = moon_illumination(datetime(2026, 3, 3, 11, 38, tzinfo=UTC))
        self.assertGreater(fraction, 0.98)

    def test_new_moon_is_dark(self) -> None:
        fraction, _ = moon_illumination(datetime(2026, 2, 17, 12, 1, tzinfo=UTC))
        self.assertLess(fraction, 0.02)

    def test_first_quarter_is_half_lit_and_waxing(self) -> None:
        fraction, waxing = moon_illumination(datetime(2026, 2, 24, 12, 28, tzinfo=UTC))
        self.assertAlmostEqual(fraction, 0.5, delta=0.05)
        self.assertTrue(waxing)

    def test_waxing_before_full(self) -> None:
        self.assertTrue(moon_illumination(datetime(2026, 2, 27, 12, 0, tzinfo=UTC))[1])

    def test_waning_after_full(self) -> None:
        self.assertFalse(moon_illumination(datetime(2026, 3, 8, 12, 0, tzinfo=UTC))[1])

    def test_full_moon_opposes_sun(self) -> None:
        self.assertGreater(moon_position(local(2026, 3, 3, 0, 30), RIYADH)[0], 30)
        self.assertLess(moon_position(local(2026, 3, 3, 12, 0), RIYADH)[0], 0)

    def test_phase_names(self) -> None:
        cases = [
            (0.0, True, "new moon"),
            (0.25, True, "waxing crescent"),
            (0.5, True, "first quarter"),
            (0.8, True, "waxing gibbous"),
            (1.0, True, "full moon"),
            (0.8, False, "waning gibbous"),
            (0.5, False, "last quarter"),
            (0.25, False, "waning crescent"),
        ]
        for fraction, waxing, name in cases:
            with self.subTest(fraction=fraction, waxing=waxing):
                self.assertEqual(moon_phase_name(fraction, waxing), name)


class SkyStateTest(unittest.TestCase):
    def test_sky_state_thresholds(self) -> None:
        cases = {
            -20: SkyState.NIGHT,
            -15: SkyState.ASTRONOMICAL,
            -9: SkyState.NAUTICAL,
            -3: SkyState.CIVIL,
            3: SkyState.GOLDEN,
            30: SkyState.DAY,
        }
        for altitude, state in cases.items():
            with self.subTest(altitude=altitude):
                self.assertEqual(sky_state(altitude), state)

    def test_sky_state_edges_belong_to_the_brighter_state(self) -> None:
        self.assertEqual(sky_state(-18.0), SkyState.ASTRONOMICAL)
        self.assertEqual(sky_state(6.0), SkyState.DAY)


class ColourTest(unittest.TestCase):
    def test_sky_colours_are_continuous(self) -> None:
        previous = sky_colours(-30.0)
        altitude = -29.5
        while altitude <= 90.0:
            current = sky_colours(altitude)
            for before, after in zip(previous, current):
                self.assertLessEqual(max(abs(a - b) for a, b in zip(before, after)), 16, altitude)
            previous = current
            altitude += 0.5

    def test_sky_is_brighter_at_noon_than_at_midnight(self) -> None:
        night_zenith, _ = sky_colours(-30.0)
        noon_zenith, _ = sky_colours(60.0)
        self.assertGreater(sum(noon_zenith), sum(night_zenith) * 3)

    def test_low_sun_light_is_warmer_and_dimmer_than_high_sun(self) -> None:
        low_colour, low_strength = sun_light(2.0)
        high_colour, high_strength = sun_light(60.0)
        self.assertGreater(low_colour[0] - low_colour[2], high_colour[0] - high_colour[2])
        self.assertLess(low_strength, high_strength)

    def test_stars_fade_in_between_civil_dusk_and_astronomical_night(self) -> None:
        self.assertEqual(star_visibility(0.0), 0.0)
        self.assertEqual(star_visibility(-6.0), 0.0)
        self.assertEqual(star_visibility(-18.0), 1.0)
        self.assertEqual(star_visibility(-40.0), 1.0)
        self.assertAlmostEqual(star_visibility(-12.0), 0.5)
        values = [star_visibility(-6.0 - step) for step in range(13)]
        self.assertEqual(values, sorted(values))

    def test_twilight_glow_peaks_around_sunset_and_is_gone_in_deep_night(self) -> None:
        self.assertEqual(twilight_glow(-30.0)[1], 0.0)
        self.assertGreater(twilight_glow(-1.0)[1], twilight_glow(30.0)[1])
        self.assertGreater(twilight_glow(-1.0)[1], twilight_glow(-9.0)[1])
        for altitude in range(-40, 91, 5):
            colour, strength = twilight_glow(float(altitude))
            self.assertTrue(0.0 <= strength <= 1.0 and all(0 <= c <= 255 for c in colour))

    def test_colours_are_valid_rgb(self) -> None:
        for altitude in range(-40, 91, 5):
            zenith, horizon = sky_colours(float(altitude))
            for channel in (*zenith, *horizon, *sun_light(float(altitude))[0]):
                self.assertTrue(0 <= channel <= 255 and isinstance(channel, int), (altitude, channel))


class ViewTest(unittest.TestCase):
    def test_view_maps_azimuth_linearly_across_the_width(self) -> None:
        width = SKY_SIZE[0]
        self.assertAlmostEqual(view_x(VIEW_AZIMUTH[0]), 0.0)
        self.assertAlmostEqual(view_x(VIEW_AZIMUTH[1]), width)
        self.assertAlmostEqual(view_x(180.0), width / 2)

    def test_view_extends_past_the_window_without_wrapping_the_wrong_way(self) -> None:
        self.assertLess(view_x(30.0), 0)
        self.assertGreater(view_x(330.0), SKY_SIZE[0])
        self.assertLess(view_x(10.0), view_x(30.0))
        self.assertGreater(view_x(350.0), view_x(330.0))

    def test_constants(self) -> None:
        self.assertEqual(SKY_BUCKET_S, 600)
        self.assertEqual(SKY_SIZE, (792, 540))
        self.assertEqual(HORIZON_Y, 0.72)
        self.assertEqual(VIEW_AZIMUTH, (60.0, 300.0))


class BucketTest(unittest.TestCase):
    def test_bucket_expiry_is_next_boundary(self) -> None:
        self.assertEqual(bucket_expiry(local(2026, 11, 7, 14, 3).replace(second=20)), int(local(2026, 11, 7, 14, 10).timestamp()))
        self.assertEqual(bucket_expiry(local(2026, 11, 7, 14, 10)), int(local(2026, 11, 7, 14, 20).timestamp()))

    def test_bucket_expiry_just_before_a_boundary(self) -> None:
        late = local(2026, 11, 7, 14, 9).replace(second=59, microsecond=999000)
        self.assertEqual(bucket_expiry(late), int(local(2026, 11, 7, 14, 10).timestamp()))


class SunBarTest(unittest.TestCase):
    def setUp(self) -> None:
        self.today = sun_times(date(2026, 11, 7), RIYADH, RIYADH_TZ)
        self.tomorrow = sun_times(date(2026, 11, 8), RIYADH, RIYADH_TZ)
        self.yesterday = sun_times(date(2026, 11, 6), RIYADH, RIYADH_TZ)

    def progress(self, now: datetime) -> tuple[bool, float]:
        return sun_bar_progress(now, self.today, self.tomorrow.sunrise, self.yesterday.sunset)

    def test_day_progress_runs_from_sunrise_to_sunset(self) -> None:
        self.assertEqual(self.progress(self.today.sunrise), (True, 0.0))
        is_day, noon = self.progress(self.today.solar_noon)
        self.assertTrue(is_day)
        self.assertAlmostEqual(noon, 0.5, delta=0.02)
        just_before = self.today.sunset - timedelta(seconds=1)
        self.assertGreater(self.progress(just_before)[1], 0.99)

    def test_night_progress_spans_midnight(self) -> None:
        evening = self.progress(local(2026, 11, 7, 23, 0))
        small_hours = self.progress(local(2026, 11, 8, 3, 0))
        self.assertFalse(evening[0])
        self.assertFalse(small_hours[0])
        self.assertTrue(0 < evening[1] < 1)
        self.assertTrue(0 < small_hours[1] < 1)
        self.assertGreater(small_hours[1], evening[1])

    def test_night_runs_from_sunset_to_next_sunrise(self) -> None:
        self.assertEqual(self.progress(self.today.sunset), (False, 0.0))
        almost_dawn = self.progress(self.tomorrow.sunrise - timedelta(seconds=1))
        self.assertFalse(almost_dawn[0])
        self.assertGreater(almost_dawn[1], 0.99)

    def test_before_sunrise_belongs_to_last_night(self) -> None:
        is_day, progress = self.progress(self.today.sunrise - timedelta(seconds=1))
        self.assertFalse(is_day)
        self.assertGreater(progress, 0.99)


class LocationTest(unittest.TestCase):
    def test_default_is_riyadh(self) -> None:
        self.assertEqual(location_from_env({}), (RIYADH, None))
        self.assertEqual((RIYADH.lat, RIYADH.lon, RIYADH.place), (24.7136, 46.6753, "Riyadh"))

    def test_invalid_latlon_override_warns_and_defaults(self) -> None:
        location, warning = location_from_env({"DCLI_HORIZON_LATLON": "north"})
        self.assertEqual(location, RIYADH)
        self.assertIn("DCLI_HORIZON_LATLON", warning or "")

    def test_valid_override_is_used_without_warning(self) -> None:
        env = {"DCLI_HORIZON_LATLON": "51.5,-0.12", "DCLI_HORIZON_PLACE": "London"}
        self.assertEqual(location_from_env(env), (Location(51.5, -0.12, "London"), None))

    def test_override_without_a_place_is_named_by_its_coordinates(self) -> None:
        location, warning = location_from_env({"DCLI_HORIZON_LATLON": "51.5, -0.12"})
        self.assertIsNone(warning)
        self.assertEqual((location.lat, location.lon), (51.5, -0.12))
        self.assertEqual(location.place, "51.50°N 0.12°W")

    def test_out_of_range_and_polar_overrides_warn(self) -> None:
        for bad in ("91,0", "10,181", "70,20", "nan,3", "1,2,3", "5"):
            with self.subTest(bad=bad):
                location, warning = location_from_env({"DCLI_HORIZON_LATLON": bad})
                self.assertEqual(location, RIYADH)
                self.assertIn("DCLI_HORIZON_LATLON", warning or "")

    def test_empty_override_means_unset(self) -> None:
        self.assertEqual(location_from_env({"DCLI_HORIZON_LATLON": "  "}), (RIYADH, None))

    def test_place_without_latlon_is_ignored(self) -> None:
        self.assertEqual(location_from_env({"DCLI_HORIZON_PLACE": "Atlantis"}), (RIYADH, None))


class ZoneTest(unittest.TestCase):
    def setUp(self) -> None:
        self.fallback = timezone(timedelta(hours=3))

    def test_tz_variable_wins(self) -> None:
        zone = resolve_zone({"TZ": "Europe/London"}, Path("/nonexistent"), self.fallback)
        self.assertEqual(getattr(zone, "key", None), "Europe/London")

    def test_tz_variable_with_a_leading_colon(self) -> None:
        zone = resolve_zone({"TZ": ":Asia/Riyadh"}, Path("/nonexistent"), self.fallback)
        self.assertEqual(getattr(zone, "key", None), "Asia/Riyadh")

    def test_localtime_symlink_names_the_zone(self) -> None:
        with TemporaryDirectory() as tmp:
            link = Path(tmp) / "localtime"
            link.symlink_to("/usr/share/zoneinfo/Europe/London")
            zone = resolve_zone({}, link, self.fallback)
        self.assertEqual(getattr(zone, "key", None), "Europe/London")

    def test_unresolvable_zone_falls_back_to_the_fixed_offset(self) -> None:
        with TemporaryDirectory() as tmp:
            plain_file = Path(tmp) / "localtime"
            plain_file.write_bytes(b"TZif")
            self.assertIs(resolve_zone({"TZ": "EST5EDT,M3.2.0,M11.1.0"}, plain_file, self.fallback), self.fallback)
            self.assertIs(resolve_zone({}, Path(tmp) / "missing", self.fallback), self.fallback)

    def test_dst_zone_is_right_on_a_changeover_day(self) -> None:
        zone = resolve_zone({"TZ": "Europe/London"}, Path("/nonexistent"), self.fallback)
        before = datetime(2026, 3, 29, 0, 30, tzinfo=zone)
        after = datetime(2026, 3, 29, 12, 0, tzinfo=zone)
        self.assertEqual(before.utcoffset(), timedelta(0))
        self.assertEqual(after.utcoffset(), timedelta(hours=1))


class SunTimesTypeTest(unittest.TestCase):
    def test_sun_times_is_frozen(self) -> None:
        times = sun_times(date(2026, 11, 7), RIYADH, RIYADH_TZ)
        self.assertIsInstance(times, SunTimes)
        with self.assertRaises(AttributeError):
            times.sunrise = times.sunset  # type: ignore[misc]


if __name__ == "__main__":
    unittest.main()
