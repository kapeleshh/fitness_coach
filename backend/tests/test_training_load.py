"""Training load: TRIMP, method priority across dedup groups, the
CTL/ATL/TSB/ACWR series, confidence, readiness fusion, the endpoints, and
the coach's Strava exclusion. Synthetic data only."""

from datetime import date, timedelta

import pytest
from fastapi.testclient import TestClient

import activities
import api_server
import coach
import db
import training_load_engine as tle
from tests.synthetic import generate_activities

DEFAULT_PARAMS = {"max_hr": 190.0, "max_hr_source": "observed", "trimp_sex": "male"}


@pytest.fixture(autouse=True)
def _no_athlete_env(monkeypatch):
    # A developer's .env must not change the defaults these tests assume.
    monkeypatch.delenv("ATHLETE_MAX_HR", raising=False)
    monkeypatch.delenv("TRIMP_SEX", raising=False)


def _row(source, source_id, local_date, sport="run", duration=3600, hour=7, **extra):
    """An activity row as db.get_activities(include_duplicates=True) returns it."""
    return {
        "id": f"{source}:{source_id}", "source": source, "source_id": str(source_id),
        "start_time_utc": f"{local_date}T{hour:02d}:00:00Z", "local_date": local_date,
        "sport_type": sport, "sport_family": activities.sport_family(sport), "name": None,
        "duration_s": duration, "moving_time_s": None, "distance_m": None,
        "elevation_gain_m": None, "avg_hr": None, "max_hr": None, "avg_power": None,
        "calories": None, "suffer_score": None, "training_load": None,
        "duplicate_of": None, **extra,
    }


def _wellness(start="2026-07-01", n=7, rhr0=50):
    d0 = date.fromisoformat(start)
    return [{"date": (d0 + timedelta(days=i)).isoformat(), "resting_hr": rhr0 + i}
            for i in range(n)][::-1]  # newest first, like db.get_all_days()


def _sessions_every_day(n, load, start=date(2026, 1, 1), method="garmin_load"):
    return [{"local_date": (start + timedelta(days=i)).isoformat(), "load": load,
             "method": method, "minutes": 60.0} for i in range(n)]


class TestTrimp:
    def test_hand_computed_values(self):
        # HRr = (150-50)/(190-50) = 0.714; 60 * HRr * a * e^(b*HRr)
        assert tle.trimp(60, 150, 50, 190) == pytest.approx(108.1, abs=0.05)
        assert tle.trimp(60, 150, 50, 190, sex="female") == pytest.approx(121.5, abs=0.05)

    @pytest.mark.parametrize("args", [
        (60, 45, 50, 190),    # average below resting -> no reserve used
        (60, 150, 50, 65),    # max - rest under MIN_HR_RESERVE: bad inputs
        (None, 150, 50, 190),
        (60, 150, None, 190),
        (0, 150, 50, 190),
    ])
    def test_rejects_unusable_inputs(self, args):
        assert tle.trimp(*args) is None

    def test_reserve_fraction_is_capped(self):
        assert tle.trimp(60, 200, 50, 190) == tle.trimp(60, 190, 50, 190)


class TestRestingHr:
    def test_point_in_time_median_with_earliest_fallback(self):
        at = tle.resting_hr_lookup(_wellness())   # 07-01..07-07 -> 50..56
        assert at("2026-07-03") == 51              # median of 50, 51, 52
        assert at("2026-08-01") == 53              # last 7 readings
        assert at("2026-01-01") == 53              # predates all: earliest 7

    def test_no_readings(self):
        assert tle.resting_hr_lookup([{"date": "2026-07-01", "resting_hr": None}])("2026-07-01") is None


class TestAthleteParams:
    def test_observed_max_ignores_implausible_values(self):
        rows = [_row("garmin", 1, "2026-07-01", max_hr=185), _row("garmin", 2, "2026-07-02", max_hr=250)]
        p = tle.athlete_params(rows, [{"max_hr": 170}], {})
        assert p == {"max_hr": 185, "max_hr_source": "observed", "trimp_sex": "male"}

    def test_env_beats_setting_and_bad_values_fall_back(self, monkeypatch):
        settings = {"athlete_max_hr": 180, "trimp_sex": "female"}
        assert tle.athlete_params([], [], settings)["max_hr"] == 180.0
        assert tle.athlete_params([], [], settings)["trimp_sex"] == "female"
        monkeypatch.setenv("ATHLETE_MAX_HR", "192")
        monkeypatch.setenv("TRIMP_SEX", "unknown")
        p = tle.athlete_params([], [], settings)
        assert p["max_hr"] == 192.0 and p["max_hr_source"] == "setting"
        assert p["trimp_sex"] == "male"


class TestSessionLoads:
    def test_method_priority(self):
        wellness = _wellness()
        rows = [
            _row("garmin", 1, "2026-07-02", training_load=120.0, avg_hr=150),
            _row("garmin", 2, "2026-07-03", avg_hr=150),                  # -> trimp
            _row("strava", 3, "2026-07-04", suffer_score=80.0),           # -> relative effort
            _row("strava", 4, "2026-07-05", sport="Walk", duration=1800),  # -> estimate
            _row("strava", 5, "2026-07-06", duration=None),               # -> none
        ]
        by_id = {s["id"]: s for s in tle.session_loads(rows, wellness, DEFAULT_PARAMS)}
        assert by_id["garmin:1"]["method"] == "garmin_load" and by_id["garmin:1"]["load"] == 120.0
        assert by_id["garmin:2"]["method"] == "trimp"
        # resting HR on 07-03 is the median of 50, 51, 52
        assert by_id["garmin:2"]["load"] == pytest.approx(tle.trimp(60, 150, 51, 190), abs=0.05)
        assert by_id["strava:3"]["method"] == "relative_effort"
        assert by_id["strava:4"]["method"] == "duration_estimate"
        assert by_id["strava:4"]["load"] == pytest.approx(30 * tle.LOAD_PER_MINUTE["walk"])
        assert by_id["strava:5"]["method"] == "none" and by_id["strava:5"]["load"] == 0.0

    def test_canonical_borrows_a_duplicates_signal(self):
        garmin = _row("garmin", 1, "2026-07-02")                          # no load, no HR
        twin = _row("strava", 2, "2026-07-02", suffer_score=80.0, duplicate_of="garmin:1")
        (s,) = tle.session_loads([garmin, twin], [], DEFAULT_PARAMS)
        assert s["id"] == "garmin:1"
        assert (s["method"], s["load"]) == ("relative_effort", 80.0)
        assert s["sources"] == ["garmin", "strava"]

    def test_excluding_a_source_drops_what_it_lent(self):
        garmin = _row("garmin", 1, "2026-07-02")
        twin = _row("strava", 2, "2026-07-02", suffer_score=80.0, duplicate_of="garmin:1")
        (s,) = tle.session_loads([garmin], [], DEFAULT_PARAMS)
        assert s["method"] == "duration_estimate"
        assert s["load"] == pytest.approx(60 * tle.LOAD_PER_MINUTE["run"])
        assert s["sources"] == ["garmin"]
        # With the twin present, the same session borrows its effort score.
        (borrowed,) = tle.session_loads([garmin, twin], [], DEFAULT_PARAMS)
        assert borrowed["method"] == "relative_effort"


class TestDailySeries:
    def test_single_impulse_hand_computed(self):
        series = tle.daily_series(
            [{"local_date": "2026-01-01", "load": 100.0, "method": "garmin_load", "minutes": 60.0}],
            end=date(2026, 1, 3),
        )
        day0, day1, day2 = series
        # Each row is the state ENTERING the day.
        assert (day0["ctl"], day0["atl"], day0["tsb"], day0["load"]) == (0.0, 0.0, 0.0, 100.0)
        assert (day1["ctl"], day1["atl"], day1["tsb"]) == (2.4, 13.3, -10.9)
        assert (day2["ctl"], day2["atl"], day2["load"]) == (2.3, 11.5, 0.0)

    def test_steady_load_converges_and_rest_days_are_zero(self):
        series = tle.daily_series(_sessions_every_day(400, 100.0))
        last = series[-1]
        assert (last["ctl"], last["atl"], last["tsb"]) == (100.0, 100.0, 0.0)
        assert last["form_band"] == "neutral" and last["acwr"] == pytest.approx(1.0, abs=0.01)
        assert last["confidence"] == "high" and last["flags"] == []

        gapped = tle.daily_series(
            _sessions_every_day(1, 100.0) + _sessions_every_day(1, 100.0, start=date(2026, 1, 11))
        )
        assert len(gapped) == 11 and [r["load"] for r in gapped[1:10]] == [0.0] * 9

    def test_load_spike_flag(self):
        steady = _sessions_every_day(60, 50.0)
        spike = _sessions_every_day(3, 300.0, start=date(2026, 1, 1) + timedelta(days=60))
        series = tle.daily_series(steady + spike, end=date(2026, 1, 1) + timedelta(days=63))
        before, after = series[60], series[63]
        assert "load_spike" not in before["flags"]
        assert after["acwr"] > tle.ACWR_SPIKE and "load_spike" in after["flags"]

    def test_maturity_gates(self):
        series = tle.daily_series(_sessions_every_day(60, 80.0))
        early, warming, mature = series[10], series[20], series[50]
        assert early["form_band"] is None and early["acwr"] is None
        assert warming["form_band"] is not None and "warming_up" in warming["flags"]
        assert warming["confidence"] == "low"
        assert "warming_up" not in mature["flags"] and mature["confidence"] == "high"

    def test_estimated_load_lowers_confidence(self):
        series = tle.daily_series(_sessions_every_day(60, 80.0, method="duration_estimate"))
        assert series[-1]["measured_share"] == 0.0 and series[-1]["confidence"] == "low"

    @pytest.mark.parametrize("pct, band", [
        (26, "transition"), (25, "fresh"), (6, "fresh"), (5, "neutral"),
        (-9, "neutral"), (-10, "building"), (-30, "overreaching"), (-50, "overreaching"),
    ])
    def test_form_bands(self, pct, band):
        assert tle._form_band(pct) == band


def _state(form_band, **extra):
    return {"form_band": form_band, "summary": "Training load: x.", "flags": [], **extra}


class TestReadinessFusion:
    @pytest.mark.parametrize("readiness_band, form_band, expected", [
        ("green", "overreaching", "capping intensity"),
        ("green", "fresh", "key session"),
        ("amber", "overreaching", "likely cause"),
        ("red", "neutral", "sleep, stress or illness"),
        ("amber", "building", None),
        ("unknown", "overreaching", None),
    ])
    def test_note(self, readiness_band, form_band, expected):
        note = tle.readiness_note(readiness_band, _state(form_band))
        assert note.startswith("Training load: x.")
        if expected:
            assert expected in note
        else:
            assert note == "Training load: x."

    def test_annotate_keeps_unscored_briefing(self):
        state = {k: None for k in tle._READINESS_FIELDS} | _state("fresh")
        out = tle.annotate_readiness({"date": "2026-07-07", "score": None,
                                      "band": "unknown", "briefing": "UNKNOWN"}, state)
        assert out["briefing"] == "UNKNOWN" and out["training_load"]["form_band"] == "fresh"
        assert tle.annotate_readiness({"score": 80, "briefing": "B"}, None)["training_load"] is None


@pytest.fixture()
def with_activities(populated_db):
    data = generate_activities()
    activities.ingest(data["garmin"] + data["strava"])
    return populated_db


class TestEndpoints:
    def _client(self):
        return TestClient(api_server.app)

    def test_today(self, with_activities):
        with self._client() as client:
            body = client.get("/api/training-load").json()
        assert body["date"] == "2026-07-07"
        assert body["form_band"] is not None and body["confidence"] in ("medium", "high")
        assert body["parameters"]["max_hr_source"] == "observed"
        dates = [s["local_date"] for s in body["recent_sessions"]]
        assert dates == sorted(dates, reverse=True) and body["last_7_days"]["sessions"] == len(dates)
        assert body["summary"].startswith("Training load:")

    def test_empty(self, temp_db):
        with self._client() as client:
            body = client.get("/api/training-load").json()
        assert body["confidence"] == "none" and body["ctl"] is None
        assert "No activities" in body["summary"]
        with self._client() as client:
            assert client.get("/api/training-load/history").json()["series"] == []

    def test_history(self, with_activities):
        with self._client() as client:
            body = client.get("/api/training-load/history", params={"days": 30}).json()
        dates = [r["date"] for r in body["series"]]
        assert body["days"] == 30 and len(dates) == 30
        assert dates[0] == "2026-07-07" and dates == sorted(dates, reverse=True)

    def test_readiness_gets_training_load(self, with_activities):
        with self._client() as client:
            body = client.get("/api/readiness").json()
            dated = client.get("/api/readiness/2026-07-07").json()
        assert body["training_load"]["date"] == body["date"]
        assert "Training load:" in body["briefing"]
        assert dated["training_load"] == body["training_load"]

    def test_readiness_without_activities_is_unchanged(self, populated_db):
        with self._client() as client:
            body = client.get("/api/readiness").json()
        assert body["training_load"] is None and "Training load" not in body["briefing"]

    def test_endpoints_listed(self, temp_db):
        for line in ("GET  /api/training-load", "GET  /api/training-load/history"):
            assert line in api_server.ENDPOINT_LIST


class TestCoachExcludesStrava:
    """Strava's API Policy bars Strava Data, and anything derived from it,
    from grounding an AI application."""

    @pytest.fixture()
    def mixed(self, populated_db):
        activities.ingest([
            # Garmin session with load, plus its Strava auto-upload twin.
            {"source": "garmin", "source_id": 1, "start_time_utc": "2026-07-05T07:00:00Z",
             "local_date": "2026-07-05", "sport_type": "running", "duration_s": 3600,
             "training_load": 123.0, "max_hr": 180},
            {"source": "strava", "source_id": 11, "start_time_utc": "2026-07-05T07:00:20Z",
             "local_date": "2026-07-05", "sport_type": "Run", "duration_s": 3600,
             "suffer_score": 444.0, "max_hr": 210},
            # Garmin session without load or HR; only its Strava twin has an effort score.
            {"source": "garmin", "source_id": 2, "start_time_utc": "2026-07-06T07:00:00Z",
             "local_date": "2026-07-06", "sport_type": "running", "duration_s": 3600},
            {"source": "strava", "source_id": 12, "start_time_utc": "2026-07-06T07:00:30Z",
             "local_date": "2026-07-06", "sport_type": "Run", "duration_s": 3600,
             "suffer_score": 555.0},
            # Strava-only session.
            {"source": "strava", "source_id": 13, "start_time_utc": "2026-07-07T07:00:00Z",
             "local_date": "2026-07-07", "sport_type": "Ride", "duration_s": 5400,
             "suffer_score": 777.0},
        ])
        return populated_db

    def test_api_uses_every_source(self, mixed):
        by_id = {s["id"]: s for s in tle.compute()["sessions"]}
        assert by_id["garmin:2"]["method"] == "relative_effort" and by_id["garmin:2"]["load"] == 555.0
        assert by_id["strava:13"]["load"] == 777.0

    def test_coach_context_has_no_strava_data(self, mixed):
        ctx = coach.build_context()
        assert "Garmin-recorded activities only" in ctx
        assert "load 123 (Garmin training load)" in ctx
        assert "estimated from duration" in ctx           # garmin:2 without its twin's score
        assert "last 7 days: 2 sessions" in ctx            # the Strava-only ride isn't counted
        for strava_derived in ("load 444", "load 555", "load 777", "relative effort", ": ride,"):
            assert strava_derived not in ctx

    def test_derived_parameters_exclude_strava(self, mixed):
        assert tle.compute()["params"]["max_hr"] == 210
        assert tle.compute(exclude_sources=coach.AI_EXCLUDED_SOURCES)["params"]["max_hr"] == 180

    def test_coach_without_any_activities(self, populated_db):
        assert "no Garmin-recorded activities yet" in coach.build_context()

    def test_coach_without_wellness_still_has_section(self, temp_db):
        ctx = coach.build_context()
        assert "No wellness data" in ctx and "Training load" in ctx


class TestDatabaseRoundTrip:
    def test_compute_reads_settings(self, with_activities):
        db.set_setting("athlete_max_hr", 199)
        assert tle.compute()["params"] == {"max_hr": 199.0, "max_hr_source": "setting",
                                           "trimp_sex": "male"}
