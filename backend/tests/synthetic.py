"""Deterministic synthetic health data for tests and golden capture.

Never put real health data in tests or goldens — this generator produces
plausible fake values with a fixed seed so goldens are reproducible.

All numeric fields are intentionally non-zero so that the legacy JSON path
and the SQLite path (which maps impossible zeros to NULL) produce identical
API responses for this dataset.
"""

import random
from datetime import date, timedelta

FIXTURE_END_DATE = date(2026, 7, 7)
FIXTURE_DAYS = 90

_INSIGHTS = [
    "NEGATIVE_LONG_AWAKE_TIME",
    "POSITIVE_DEEP_SLEEP",
    "NEGATIVE_LATE_BEDTIME",
    "POSITIVE_CONSISTENT_SCHEDULE",
]
_FEEDBACK = [
    "GOOD_CONTINUITY",
    "FAIR_QUALITY",
    "GOOD_QUALITY",
    "POOR_CONTINUITY",
]
_HRV_STATUS = ["BALANCED", "BALANCED", "BALANCED", "LOW", "UNBALANCED"]


def generate_days(n: int = FIXTURE_DAYS, end: date = FIXTURE_END_DATE) -> list[dict]:
    """Return n synthetic daily records, newest first (matching the real file)."""
    rng = random.Random(42)
    records = []
    for i in range(n):
        day = end - timedelta(days=i)
        date_str = day.strftime("%Y-%m-%d")
        bb_start = rng.randint(40, 95)
        bb_end = rng.randint(5, 39)
        records.append({
            "date": date_str,
            "sleep_score": rng.randint(55, 92),
            "deep_sleep_minutes": rng.randint(40, 110),
            "light_sleep_minutes": rng.randint(180, 280),
            "rem_sleep_minutes": rng.randint(60, 130),
            "awake_minutes": rng.randint(10, 60),
            "sleep_start_time": f"{(day - timedelta(days=1)).strftime('%Y-%m-%d')}T22:{rng.randint(10, 59):02d}:00.0",
            "sleep_end_time": f"{date_str}T06:{rng.randint(10, 59):02d}:00.0",
            "avg_sleep_stress": round(rng.uniform(14.0, 34.0), 1),
            "sleep_insight": rng.choice(_INSIGHTS),
            "sleep_feedback": rng.choice(_FEEDBACK),
            "resting_hr": rng.randint(46, 60),
            "min_hr": rng.randint(40, 45),
            "max_hr": rng.randint(120, 172),
            "hrv": round(rng.uniform(42.0, 78.0), 1),
            "hrv_status": rng.choice(_HRV_STATUS),
            "body_battery_start": bb_start,
            "body_battery_end": bb_end,
            "body_battery_high": min(100, bb_start + rng.randint(0, 5)),
            "body_battery_low": max(1, bb_end - rng.randint(0, 4)),
            "body_battery_charged": rng.randint(30, 80),
            "body_battery_drained": rng.randint(40, 90),
            "avg_stress": rng.randint(20, 52),
            "max_stress": rng.randint(70, 99),
            "stress_rest_minutes": rng.randint(300, 700),
            "stress_low_minutes": rng.randint(150, 400),
            "stress_medium_minutes": rng.randint(30, 150),
            "stress_high_minutes": rng.randint(5, 60),
            "steps": rng.randint(3000, 16500),
            "distance_meters": round(rng.uniform(2200.0, 13000.0), 2),
            "active_calories": rng.randint(200, 950),
            "total_calories": rng.randint(1900, 3100),
            "floors_climbed": rng.randint(4, 26),
            "active_minutes": rng.randint(20, 130),
            "avg_respiration": round(rng.uniform(13.0, 17.0), 1),
            "lowest_respiration": round(rng.uniform(10.0, 13.0), 1),
            "highest_respiration": round(rng.uniform(17.0, 22.0), 1),
        })
    return records


# Garmin-era sessions in the last GARMIN_ACTIVITY_DAYS; Strava-only history
# before that (the pre-Garmin era a bulk export backfills).
GARMIN_ACTIVITY_DAYS = 60
PRE_GARMIN_STRAVA_ACTIVITIES = 30


def generate_activities(end: date = FIXTURE_END_DATE) -> dict:
    """Synthetic raw activities (pre-normalization), deterministic.

    Every Garmin activity has a Strava twin (auto-upload: start a few
    seconds later, duration within 2%) so dedup has known answers. Returns
    {"garmin": [...], "strava": [...], "expected_duplicates": {strava_id:
    garmin_id}} using the "<source>:<source_id>" activity ids.
    """
    rng = random.Random(7)
    garmin, strava, expected = [], [], {}
    sports = [("running", "Run"), ("road_biking", "Ride"), ("lap_swimming", "Swim")]

    for i in range(0, GARMIN_ACTIVITY_DAYS, 2):
        day = end - timedelta(days=i)
        hour = rng.randint(6, 18)
        duration = rng.randint(1800, 5400)
        garmin_type, strava_type = sports[i // 2 % len(sports)]
        g_id, s_id = 900000 + i, 500000 + i
        garmin.append({
            "source": "garmin",
            "source_id": g_id,
            "start_time_utc": f"{day.isoformat()}T{hour:02d}:00:00Z",
            "local_date": day.isoformat(),
            "sport_type": garmin_type,
            "name": f"Synthetic {strava_type}",
            "duration_s": duration,
            "distance_m": rng.randint(3000, 40000),
            "avg_hr": rng.randint(120, 165),
            "max_hr": rng.randint(166, 188),
            "training_load": rng.randint(40, 220),
        })
        strava.append({
            "source": "strava",
            "source_id": s_id,
            "start_time_utc": f"{day.isoformat()}T{hour:02d}:00:{rng.randint(5, 50):02d}Z",
            "local_date": day.isoformat(),
            "sport_type": strava_type,
            "name": f"Synthetic {strava_type}",
            "duration_s": round(duration * rng.uniform(0.98, 1.02)),
            "suffer_score": rng.randint(20, 150),
        })
        expected[f"strava:{s_id}"] = f"garmin:{g_id}"

    for j in range(PRE_GARMIN_STRAVA_ACTIVITIES):
        day = end - timedelta(days=GARMIN_ACTIVITY_DAYS + 10 + j * 3)
        strava.append({
            "source": "strava",
            "source_id": 400000 + j,
            "start_time_utc": f"{day.isoformat()}T07:30:00Z",
            "local_date": day.isoformat(),
            "sport_type": "Run",
            "name": "Synthetic early run",
            "duration_s": rng.randint(1500, 4000),
            "suffer_score": rng.randint(15, 120),
        })

    return {"garmin": garmin, "strava": strava, "expected_duplicates": expected}
