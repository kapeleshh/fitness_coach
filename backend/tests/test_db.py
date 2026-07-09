"""Tests for the SQLite layer, especially the missing-data policy."""

import db
from tests.synthetic import generate_days


def _minimal_day(**overrides):
    day = {"date": "2026-07-01"}
    day.update(overrides)
    return day


class TestNormalizeRecord:
    def test_impossible_zeros_become_null(self):
        rec = db.normalize_record(_minimal_day(
            hrv=0, sleep_score=0, resting_hr=0, body_battery_start=0,
            avg_stress=0, total_calories=0,
        ))
        for field in ("hrv", "sleep_score", "resting_hr", "body_battery_start",
                      "avg_stress", "total_calories"):
            assert rec[field] is None, field

    def test_real_values_kept(self):
        rec = db.normalize_record(_minimal_day(hrv=58.9, sleep_score=71, steps=9231))
        assert rec["hrv"] == 58.9
        assert rec["sleep_score"] == 71
        assert rec["steps"] == 9231

    def test_zeroable_fields_keep_zero(self):
        rec = db.normalize_record(_minimal_day(
            steps=0, floors_climbed=0, active_minutes=0, stress_high_minutes=0,
        ))
        assert rec["steps"] == 0
        assert rec["floors_climbed"] == 0
        assert rec["active_minutes"] == 0
        assert rec["stress_high_minutes"] == 0

    def test_sleep_stages_null_only_when_sleep_missing(self):
        # Sleep record missing entirely -> stage zeros are missing too
        missing = db.normalize_record(_minimal_day(
            sleep_score=0, deep_sleep_minutes=0, light_sleep_minutes=0,
            rem_sleep_minutes=0, awake_minutes=0,
        ))
        assert missing["deep_sleep_minutes"] is None
        assert missing["awake_minutes"] is None
        # Tracked night with a genuine 0-minute stage -> kept
        tracked = db.normalize_record(_minimal_day(
            sleep_score=64, deep_sleep_minutes=0, awake_minutes=0,
        ))
        assert tracked["deep_sleep_minutes"] == 0
        assert tracked["awake_minutes"] == 0

    def test_unknown_hrv_status_null_when_hrv_missing(self):
        rec = db.normalize_record(_minimal_day(
            sleep_score=0, hrv=0, hrv_status="UNKNOWN",
        ))
        assert rec["hrv_status"] is None
        # With sleep present, status is kept as reported
        rec2 = db.normalize_record(_minimal_day(
            sleep_score=70, hrv=0, hrv_status="UNKNOWN",
        ))
        assert rec2["hrv_status"] == "UNKNOWN"

    def test_empty_strings_become_null(self):
        rec = db.normalize_record(_minimal_day(sleep_insight="", sleep_feedback=""))
        assert rec["sleep_insight"] is None
        assert rec["sleep_feedback"] is None

    def test_date_required(self):
        import pytest
        with pytest.raises(ValueError):
            db.normalize_record({"sleep_score": 70})


class TestStorage:
    def test_roundtrip_ordering_newest_first(self, temp_db):
        db.upsert_days(generate_days(10))
        records = db.get_all_days()
        dates = [r["date"] for r in records]
        assert dates == sorted(dates, reverse=True)

    def test_upsert_replaces_same_date(self, temp_db):
        db.upsert_days([_minimal_day(sleep_score=60)])
        db.upsert_days([_minimal_day(sleep_score=75)])
        assert db.count_days() == 1
        assert db.get_day("2026-07-01")["sleep_score"] == 75

    def test_legacy_zero_fill_restores_old_shape(self, temp_db):
        # A legacy record full of missing-as-zero values
        db.upsert_days([_minimal_day(
            sleep_score=0, hrv=0, resting_hr=0, sleep_insight="",
            hrv_status="UNKNOWN", steps=5000,
        )])
        raw = db.get_day("2026-07-01")
        assert raw["sleep_score"] is None and raw["hrv"] is None

        legacy = db.get_day("2026-07-01", legacy_zero_fill=True)
        assert legacy["sleep_score"] == 0
        assert legacy["hrv"] == 0.0
        assert legacy["sleep_insight"] == ""
        assert legacy["hrv_status"] == "UNKNOWN"
        assert legacy["steps"] == 5000

    def test_import_json(self, temp_db, tmp_path):
        import json
        json_file = tmp_path / "legacy.json"
        days = generate_days(5)
        days[0]["hrv"] = 0  # legacy missing-as-zero
        json_file.write_text(json.dumps(days))

        imported = db.import_json(json_file)
        assert imported == 5
        assert db.count_days() == 5
        assert db.get_day(days[0]["date"])["hrv"] is None

    def test_status_and_coverage(self, populated_db):
        status = db.get_status()
        assert status["status"] == "ok"
        assert status["total_days"] == 90
        assert status["earliest_date"] < status["latest_date"]

        report = db.coverage_report()
        assert report["total_days"] == 90
        assert report["coverage_pct"]["hrv"] == 100.0

    def test_empty_status(self, temp_db):
        assert db.get_status()["status"] == "no_data"

    def test_sleep_timestamps_preserve_type(self, temp_db):
        # Garmin sync sends epoch-millisecond integers; manual exports send
        # ISO strings. Each must round-trip as its original type (NUMERIC
        # affinity), not be coerced to text.
        db.upsert_days([
            {"date": "2026-07-02", "sleep_score": 70,
             "sleep_start_time": 1751490000000, "sleep_end_time": 1751522400000},
            {"date": "2026-07-01", "sleep_score": 71,
             "sleep_start_time": "2026-06-30T22:30:00.0",
             "sleep_end_time": "2026-07-01T06:30:00.0"},
        ])
        epoch_day = db.get_day("2026-07-02")
        assert epoch_day["sleep_start_time"] == 1751490000000
        assert isinstance(epoch_day["sleep_start_time"], int)

        iso_day = db.get_day("2026-07-01")
        assert iso_day["sleep_start_time"] == "2026-06-30T22:30:00.0"
        assert isinstance(iso_day["sleep_start_time"], str)


class TestSettings:
    def test_roundtrip(self, temp_db):
        db.set_setting("max_hr", 187)
        db.set_setting("zones", {"z2": [120, 140]})
        assert db.get_setting("max_hr") == 187
        assert db.get_setting("zones") == {"z2": [120, 140]}
        assert db.get_setting("absent", default="x") == "x"
        assert set(db.get_all_settings()) == {"max_hr", "zones"}
