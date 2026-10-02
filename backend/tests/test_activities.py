"""Activities: normalization, cross-source dedup, Strava export/API parsing,
Garmin mapping, and the activity endpoints. Synthetic data only."""

from datetime import UTC
from zoneinfo import ZoneInfo

import httpx
import pytest
from fastapi.testclient import TestClient

import activities
import api_server
import db
import garmin_sync
import strava_import
import strava_sync
from tests.synthetic import (
    GARMIN_ACTIVITY_DAYS,
    PRE_GARMIN_STRAVA_ACTIVITIES,
    generate_activities,
)


def _act(source, source_id, start, sport="Run", duration=3600, **extra):
    return {
        "source": source,
        "source_id": source_id,
        "start_time_utc": start,
        "local_date": start[:10],
        "sport_type": sport,
        "duration_s": duration,
        **extra,
    }


def _normalized(*raws):
    return [activities.normalize_activity(r) for r in raws]


class TestSportFamily:
    @pytest.mark.parametrize("sport_type, family", [
        ("Run", "run"), ("TrailRun", "run"), ("trail_running", "run"),
        ("treadmill_running", "run"), ("Ride", "ride"), ("road_biking", "ride"),
        ("EBikeRide", "ride"), ("indoor_cycling", "ride"), ("Swim", "swim"),
        ("lap_swimming", "swim"), ("WeightTraining", "strength"),
        ("strength_training", "strength"), ("Hike", "hike"), (None, "other"),
    ])
    def test_maps_strava_and_garmin_names(self, sport_type, family):
        assert activities.sport_family(sport_type) == family


class TestNormalize:
    def test_id_and_impossible_zeros(self):
        rec = activities.normalize_activity(
            _act("strava", 123, "2026-07-01T07:00:00Z", avg_hr=0, avg_power=0, name="")
        )
        assert rec["id"] == "strava:123"
        assert rec["source_id"] == "123"
        assert rec["avg_hr"] is None and rec["avg_power"] is None
        assert rec["name"] is None
        assert rec["sport_family"] == "run"

    def test_requires_identity_and_time(self):
        with pytest.raises(ValueError):
            activities.normalize_activity({"source": "strava", "source_id": 1})


class TestDedup:
    def test_garmin_upload_to_strava_is_duplicate(self):
        recs = _normalized(
            _act("garmin", 1, "2026-07-01T07:00:00Z", sport="running", duration=3600),
            _act("strava", 2, "2026-07-01T07:00:40Z", sport="Run", duration=3610),
        )
        assert activities.find_duplicates(recs) == {"strava:2": "garmin:1"}

    @pytest.mark.parametrize("start, sport, duration", [
        ("2026-07-01T07:06:00Z", "Run", 3600),   # starts > 5 min apart
        ("2026-07-01T07:00:30Z", "Ride", 3600),  # different sport family
        ("2026-07-01T07:00:30Z", "Run", 3000),   # duration differs > 10%
    ])
    def test_not_duplicates(self, start, sport, duration):
        recs = _normalized(
            _act("garmin", 1, "2026-07-01T07:00:00Z", sport="running", duration=3600),
            _act("strava", 2, start, sport=sport, duration=duration),
        )
        assert activities.find_duplicates(recs) == {}

    def test_same_source_back_to_back_sessions_are_distinct(self):
        recs = _normalized(
            _act("strava", 1, "2026-07-01T07:00:00Z", duration=600),
            _act("strava", 2, "2026-07-01T07:02:00Z", duration=620),
        )
        assert activities.find_duplicates(recs) == {}

    def test_one_upload_cannot_bridge_two_garmin_sessions(self):
        # A short Garmin interval at 07:00 and another at 07:04; the Strava
        # copy of the second sits between them and matches both windows.
        recs = _normalized(
            _act("garmin", 1, "2026-07-01T07:00:00Z", duration=180),
            _act("garmin", 2, "2026-07-01T07:04:00Z", duration=180),
            _act("strava", 3, "2026-07-01T07:03:50Z", duration=182),
        )
        assert activities.find_duplicates(recs) == {"strava:3": "garmin:2"}

    def test_missing_duration_falls_back_to_start_and_sport(self):
        recs = _normalized(
            _act("garmin", 1, "2026-07-01T07:00:00Z", duration=None),
            _act("strava", 2, "2026-07-01T07:01:00Z", duration=3600),
        )
        assert activities.find_duplicates(recs) == {"strava:2": "garmin:1"}

    def test_synthetic_dataset_matches_expected_links(self):
        data = generate_activities()
        recs = _normalized(*data["garmin"], *data["strava"])
        assert activities.find_duplicates(recs) == data["expected_duplicates"]


class TestIngest:
    def test_ingest_links_and_hides_duplicates(self, temp_db):
        data = generate_activities()
        activities.ingest(data["strava"])
        result = activities.ingest(data["garmin"])
        assert result["duplicates"] == len(data["expected_duplicates"])

        canonical = db.get_activities()
        n_garmin = GARMIN_ACTIVITY_DAYS // 2
        assert len(canonical) == n_garmin + PRE_GARMIN_STRAVA_ACTIVITIES
        assert {a["source"] for a in canonical[:n_garmin]} == {"garmin"}
        assert len(db.get_activities(include_duplicates=True)) == 2 * n_garmin + PRE_GARMIN_STRAVA_ACTIVITIES

        summary = db.activity_summary()
        assert summary["by_source"]["strava"]["duplicates"] == n_garmin
        assert summary["canonical"] == len(canonical)

    def test_reingest_is_idempotent(self, temp_db):
        data = generate_activities()
        activities.ingest(data["garmin"] + data["strava"])
        before = db.get_activities(include_duplicates=True)
        activities.ingest(data["garmin"] + data["strava"])
        assert db.get_activities(include_duplicates=True) == before

    def test_date_filter(self, temp_db):
        activities.ingest([
            _act("strava", 1, "2026-06-01T07:00:00Z"),
            _act("strava", 2, "2026-06-15T07:00:00Z"),
            _act("strava", 3, "2026-07-01T07:00:00Z"),
        ])
        got = db.get_activities(start="2026-06-10", end="2026-06-30")
        assert [a["id"] for a in got] == ["strava:2"]


# Header layout of a Strava export: several columns appear twice, the
# second copy in SI units. Values are synthetic.
_CSV = (
    "Activity ID,Activity Date,Activity Name,Activity Type,Elapsed Time,Distance,"
    "Max Heart Rate,Relative Effort,Elapsed Time,Moving Time,Distance,"
    "Elevation Gain,Max Heart Rate,Average Heart Rate,Average Watts,Calories,"
    "Relative Effort\n"
    '111,"Jan 5, 2024, 10:30:00 PM",Night run,Run,3600,10.0,180,55,3600.0,3500.0,'
    "10012.5,85.0,180.0,151.0,,612.0,55.0\n"
    '112,"Feb 1, 2024, 6:00:00 AM",Ride,Ride,7200,,,,7200.0,7000.0,'
    "50000.0,300.0,,,180.0,0,\n"
)


class TestStravaExport:
    def test_parses_si_columns_and_local_date(self):
        (run, ride), skipped = strava_import.parse_activities_csv(_CSV, ZoneInfo("Asia/Tokyo"))
        assert skipped == 0
        assert run["source_id"] == "111"
        assert run["start_time_utc"] == "2024-01-05T22:30:00Z"
        # 22:30 UTC is the next morning in Tokyo.
        assert run["local_date"] == "2024-01-06"
        assert run["distance_m"] == 10012.5
        assert run["avg_hr"] == 151.0
        assert run["suffer_score"] == 55.0
        assert run["avg_power"] is None
        # Narrow no-break space before AM/PM.
        assert ride["start_time_utc"] == "2024-02-01T06:00:00Z"
        assert ride["avg_power"] == 180.0

    def test_single_distance_column_is_left_null(self):
        csv_text = (
            "Activity ID,Activity Date,Activity Type,Distance\n"
            '1,"Jan 5, 2024, 7:00:00 AM",Run,10.0\n'
        )
        (rec,), _ = strava_import.parse_activities_csv(csv_text, UTC)
        assert rec["distance_m"] is None

    def test_locale_ambiguous_numbers_are_null_and_bad_dates_skipped(self):
        csv_text = (
            "Activity ID,Activity Date,Activity Type,Calories\n"
            '1,"Jan 5, 2024, 7:00:00 AM",Run,"1,234"\n'
            "2,not a date,Run,500\n"
        )
        (rec,), skipped = strava_import.parse_activities_csv(csv_text, UTC)
        assert rec["calories"] is None
        assert skipped == 1

    def test_import_from_zip(self, temp_db, tmp_path):
        import zipfile
        archive = tmp_path / "export.zip"
        with zipfile.ZipFile(archive, "w") as zf:
            zf.writestr("export_1/activities.csv", _CSV)
        result = strava_import.import_export(archive, UTC)
        assert result["parsed"] == 2
        assert result["skipped_unreadable_date"] == 0
        ride = db.get_activity("strava:112")
        assert ride["calories"] is None  # 0 calories -> NULL


def _strava_item(i, start="2026-07-01T07:00:00Z"):
    return {
        "id": i, "name": f"Run {i}", "sport_type": "Run", "type": "Run",
        "start_date": start, "start_date_local": "2026-07-01T16:00:00Z",
        "elapsed_time": 3600, "moving_time": 3500, "distance": 10000.0,
        "total_elevation_gain": 50.0, "average_heartrate": 150.0,
        "max_heartrate": 175.0, "suffer_score": 60,
    }


@pytest.fixture()
def strava_env(temp_db, monkeypatch):
    monkeypatch.setenv("STRAVA_CLIENT_ID", "1")
    monkeypatch.setenv("STRAVA_CLIENT_SECRET", "secret")
    db.set_setting(strava_sync.TOKENS_SETTING, {
        "access_token": "old", "refresh_token": "r1", "expires_at": 0,
    })


class TestStravaSync:
    def test_from_api_uses_local_date(self):
        rec = strava_sync.from_api(_strava_item(5))
        assert rec["local_date"] == "2026-07-01"
        assert rec["start_time_utc"] == "2026-07-01T07:00:00Z"
        assert rec["distance_m"] == 10000.0

    def test_refreshes_token_and_pages(self, strava_env, monkeypatch):
        monkeypatch.setattr(strava_sync, "PAGE_SIZE", 2)
        pages = {1: [_strava_item(1), _strava_item(2, "2026-07-02T07:00:00Z")],
                 2: [_strava_item(3, "2026-07-03T07:00:00Z")]}
        seen = []

        def handler(request: httpx.Request) -> httpx.Response:
            if request.url.path == "/oauth/token":
                return httpx.Response(200, json={
                    "access_token": "new", "refresh_token": "r2", "expires_at": 9999999999,
                })
            assert request.headers["Authorization"] == "Bearer new"
            seen.append(dict(request.url.params))
            return httpx.Response(200, json=pages[int(request.url.params["page"])])

        with httpx.Client(transport=httpx.MockTransport(handler)) as http:
            result = strava_sync.sync(http)

        assert result["fetched"] == 3
        assert [p["page"] for p in seen] == ["1", "2"]
        assert seen[0]["after"] == "0"
        assert db.get_setting(strava_sync.TOKENS_SETTING)["refresh_token"] == "r2"
        assert len(db.get_activities()) == 3

    def test_incremental_after_latest(self, strava_env):
        activities.ingest([strava_sync.from_api(_strava_item(1))])
        db.set_setting(strava_sync.TOKENS_SETTING, {
            "access_token": "ok", "refresh_token": "r", "expires_at": 9999999999,
        })
        seen = []

        def handler(request):
            seen.append(dict(request.url.params))
            return httpx.Response(200, json=[])

        with httpx.Client(transport=httpx.MockTransport(handler)) as http:
            strava_sync.sync(http)
        # 2026-07-01T07:00:00Z minus one second (after= is exclusive).
        assert seen[0]["after"] == "1782889199"

    def test_rate_limit_keeps_progress(self, strava_env, monkeypatch):
        monkeypatch.setattr(strava_sync, "PAGE_SIZE", 1)

        def handler(request):
            if request.url.path == "/oauth/token":
                return httpx.Response(200, json={
                    "access_token": "a", "refresh_token": "r", "expires_at": 9999999999,
                })
            if request.url.params["page"] == "1":
                return httpx.Response(200, json=[_strava_item(1)])
            return httpx.Response(429, headers={"X-RateLimit-Usage": "100,500"})

        with (
            httpx.Client(transport=httpx.MockTransport(handler)) as http,
            pytest.raises(strava_sync.StravaRateLimited),
        ):
            strava_sync.sync(http)
        assert db.get_activity("strava:1") is not None

    def test_not_authorized(self, temp_db, monkeypatch):
        monkeypatch.setenv("STRAVA_CLIENT_ID", "1")
        monkeypatch.setenv("STRAVA_CLIENT_SECRET", "secret")
        assert strava_sync.is_configured() is False
        with pytest.raises(strava_sync.StravaNotConfigured):
            strava_sync.sync(httpx.Client(transport=httpx.MockTransport(lambda r: None)))


class TestGarminMapping:
    def test_from_garmin_activity(self):
        rec = garmin_sync.from_garmin_activity({
            "activityId": 42, "activityName": "Morning Run",
            "startTimeGMT": "2026-07-01 22:30:00",
            "startTimeLocal": "2026-07-02 07:30:00",
            "activityType": {"typeKey": "running"},
            "duration": 3590.0, "elapsedDuration": 3600.0, "movingDuration": 3500.0,
            "distance": 10000.0, "elevationGain": 40.0, "averageHR": 150.0,
            "maxHR": 176.0, "calories": 650.0, "activityTrainingLoad": 120.5,
        })
        assert rec["source_id"] == 42
        assert rec["start_time_utc"] == "2026-07-01T22:30:00Z"
        assert rec["local_date"] == "2026-07-02"
        assert rec["sport_type"] == "running"
        assert rec["duration_s"] == 3600.0
        assert rec["training_load"] == 120.5


class TestActivityEndpoints:
    def _client(self):
        return TestClient(api_server.app)

    def test_list_and_get(self, temp_db):
        data = generate_activities()
        activities.ingest(data["garmin"] + data["strava"])
        with self._client() as client:
            res = client.get("/api/activities")
            assert res.status_code == 200
            assert all(a["duplicate_of"] is None for a in res.json())

            res = client.get("/api/activities", params={"include_duplicates": "true"})
            assert any(a["duplicate_of"] for a in res.json())

            first = data["garmin"][0]
            res = client.get(f"/api/activities/garmin:{first['source_id']}")
            assert res.status_code == 200
            assert res.json()["training_load"] == first["training_load"]

    def test_unknown_activity_404(self, temp_db):
        with self._client() as client:
            res = client.get("/api/activities/strava:nope")
        assert res.status_code == 404
        assert res.json() == {"error": "Activity not found"}

    def test_bad_date_400(self, temp_db):
        with self._client() as client:
            res = client.get("/api/activities", params={"start": "July"})
        assert res.status_code == 400

    def test_strava_sync_not_configured(self, temp_db, monkeypatch):
        monkeypatch.delenv("STRAVA_CLIENT_ID", raising=False)
        with self._client() as client:
            res = client.post("/api/sync/strava")
        assert res.status_code == 503

    def test_sync_status_reports_activities(self, temp_db):
        with self._client() as client:
            body = client.get("/api/sync/status").json()
        assert body["strava_configured"] is False
        assert body["activities"] == {"total": 0, "canonical": 0, "by_source": {}}

    def test_endpoints_listed(self, temp_db):
        for line in ("GET  /api/activities", "POST /api/sync/strava"):
            assert line in api_server.ENDPOINT_LIST
